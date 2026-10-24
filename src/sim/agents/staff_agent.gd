class_name StaffAgent
extends SimAgent
## A worker that claims tasks from the board and runs their steps, with the
## self-healing rules from docs/TECH.md 2.3:
## - a task held past its timeout is dropped back on the board;
## - no progress for STUCK_TICKS triggers a repath, a second time drops the task;
## - an unreachable or removed target drops the task;
## - a cancelled task is noticed on the next tick and let go.
## Waiting for a busy station is not "stuck": the task timeout covers it.

const STUCK_TICKS: int = 30

## Skill per role, 1 (poor) .. 5 (great).
var skills: Dictionary[StringName, int] = {}
## Priority per role: 0 off, 1 low, 2 normal, 3 high. &"any" covers role-free tasks.
var priorities: Dictionary[StringName, int] = {}
## Empty on the owner and legacy manually constructed agents.
var member_id: StringName = &""
var wage: int = 0
var trait_id: StringName = &"steady"
var cook_quality_bonus: float = 0.0
var food_patience_multiplier: float = 1.0
var _walk_multiplier: float = 1.0

var task: SimTask = null
var step_index: int = 0
var work_left: float = 0.0

var _step_started: bool = false
var _held_item_id: int = 0
var _held_cell: Vector2i = SimGrid.NO_CELL
var _repaths: int = 0
var _waiting_for: String = ""


func _init(staff_role: StringName = &"cook", skill: int = 3) -> void:
	role = staff_role
	skills[staff_role] = clampi(skill, 1, 5)
	priorities[staff_role] = 2
	priorities[&"any"] = 1


## Idempotent trait application; callers never configure the owner as staff.
func configure_member(member: StaffMember, definition: StaffTrait) -> void:
	if role != member.role:
		role = member.role
		skills.clear()
		priorities.clear()
		priorities[role] = 2
		priorities[&"any"] = 1
	member_id = member.id
	display_name = member.display_name
	wage = member.wage
	trait_id = member.trait_id
	skills[role] = member.skill
	move_speed = move_speed / _walk_multiplier * definition.walk_multiplier
	_walk_multiplier = definition.walk_multiplier
	cook_quality_bonus = definition.cook_quality_bonus
	food_patience_multiplier = definition.food_patience_multiplier


func movement_multiplier() -> float:
	return _walk_multiplier


## Skill used for a task role: role-free (&"any") tasks use the agent's own role.
func skill_for(task_role: StringName) -> int:
	var r := role if task_role == &"any" else task_role
	return skills.get(r, 1)


## Work units per tick for a task role: 0.7 at skill 1 up to 1.1 at skill 5.
func work_speed(task_role: StringName) -> float:
	return 0.6 + 0.1 * skill_for(task_role)


## Gives the task back (drop) and frees held cells when leaving the world.
func on_removed(world: SimWorld) -> void:
	if task != null:
		var t := task
		_let_go(world)
		world.board.drop(t, &"agent_removed")


func tick(world: SimWorld) -> void:
	if task == null:
		_try_claim(world)
		return
	if task.state != SimTask.State.CLAIMED or task.claimed_by != id:
		_let_go(world)
		return
	if world.now - task.claimed_tick > task.timeout_ticks:
		_drop(world, &"timeout")
		return
	_run_step(world)
	if task != null and _waiting_for.is_empty() and world.now - last_progress_tick > STUCK_TICKS:
		if _repaths == 0 and _step_started and repath(world.grid):
			_repaths += 1
			last_progress_tick = world.now
			world.log_event("%s re-planned (no progress)" % _name())
		else:
			_drop(world, &"stuck")


func why() -> String:
	if task == null:
		return "Idle: looking for work"
	var step_text := ""
	if step_index < task.steps.size():
		var s := task.steps[step_index]
		step_text = s.label
		if s.kind == TaskStep.Kind.WORK and _step_started:
			step_text += " (%ds left)" % ceili(work_left / (work_speed(task.role) * SimClock.TICKS_PER_SECOND))
	if not _waiting_for.is_empty():
		step_text = "waiting for %s" % _waiting_for
	return task.label if step_text.is_empty() else "%s: %s" % [task.label, step_text]


func _try_claim(world: SimWorld) -> void:
	var best: SimTask = null
	var best_score := 0.0
	for t in world.open_tasks_this_tick():
		if t.state != SimTask.State.OPEN:
			continue
		var score := _score(world, t)
		if score > best_score:
			best = t
			best_score = score
	if best != null and world.board.claim(best, id, world.now):
		task = best
		step_index = 0
		_step_started = false
		_repaths = 0
		last_progress_tick = world.now


## 0 means "won't take it". Higher is better: priority x role priority x skill
## over distance to the first target.
func _score(world: SimWorld, t: SimTask) -> float:
	var for_role := t.role
	var role_prio: int = priorities.get(for_role, 0)
	if for_role != &"any" and for_role != role and role_prio == 0:
		return 0.0
	if role_prio == 0:
		return 0.0
	var target := cell
	var item_id := t.first_item_id()
	if item_id != 0:
		var it := world.grid.item(item_id)
		if it == null:
			return 0.0
		target = it.origin
	var skill := skill_for(for_role)
	return float((t.priority + 1) * role_prio * skill) / (1.0 + GridMath.octile(cell, target))


func _run_step(world: SimWorld) -> void:
	if step_index >= task.steps.size():
		_finish(world)
		return
	var s := task.steps[step_index]
	match s.kind:
		TaskStep.Kind.GO_TO_ITEM:
			_run_go_to_item(world, s)
		TaskStep.Kind.GO_TO_CELL:
			_run_go_to_cell(world, s)
		TaskStep.Kind.WORK:
			_run_work(world, s)


func _run_go_to_item(world: SimWorld, s: TaskStep) -> void:
	var it := world.grid.item(s.item_id)
	if it == null or it.removed:
		_drop(world, &"target_gone")
		return
	if not _step_started:
		# Let go of the previous station before waiting for the next one, so
		# two workers can never hold each other's stations (deadlock).
		_release_held(world)
		var target := world.grid.free_seat_cell(it) if s.use_seat else world.grid.free_work_cell(it)
		if s.work_cell_index >= 0:
			if s.work_cell_index >= it.work_cells.size():
				_drop(world, &"invalid_work_cell")
				return
			target = it.work_cells[s.work_cell_index]
			if not world.grid.is_walkable(target):
				_drop(world, &"unreachable")
				return
			if it.reserved_by(target) != -1:
				target = SimGrid.NO_CELL
		if target == SimGrid.NO_CELL:
			_waiting_for = s.label if not s.label.is_empty() else "a free spot"
			last_progress_tick = world.now
			return
		_waiting_for = ""
		it.reserve(target, id)
		_held_item_id = it.id
		_held_cell = target
		if not set_destination(world.grid, target):
			_drop(world, &"unreachable")
			return
		_step_started = true
	_walk(world)


func _run_go_to_cell(world: SimWorld, s: TaskStep) -> void:
	if not _step_started:
		if not set_destination(world.grid, s.cell):
			_drop(world, &"unreachable")
			return
		_step_started = true
	_walk(world)


func _walk(world: SimWorld) -> void:
	if needs_repath and not repath(world.grid):
		_drop(world, &"unreachable")
		return
	match step_move(world):
		MoveResult.ARRIVED:
			_next_step(world)
		MoveResult.BLOCKED:
			if not repath(world.grid):
				_drop(world, &"unreachable")


func _run_work(world: SimWorld, s: TaskStep) -> void:
	if not _step_started:
		work_left = float(s.ticks)
		_step_started = true
	work_left -= work_speed(task.role)
	last_progress_tick = world.now
	if work_left > 0.0:
		return
	if s.on_done.is_valid() and not s.on_done.call(self):
		world.log_event("%s could not finish: %s" % [_name(), task.label])
		var t := task
		_let_go(world)
		world.board.cancel(t, &"step_failed")
		return
	_next_step(world)


func _next_step(world: SimWorld) -> void:
	step_index += 1
	_step_started = false
	_repaths = 0
	clear_path()
	if step_index >= task.steps.size():
		_finish(world)


func _finish(world: SimWorld) -> void:
	var t := task
	_let_go(world)
	world.board.complete(t)


func _drop(world: SimWorld, reason: StringName) -> void:
	var t := task
	world.log_event("%s dropped \"%s\" (%s)" % [_name(), t.label, reason])
	_let_go(world)
	world.board.drop(t, reason)


## Forgets the task and frees everything held, without touching the board.
func _let_go(world: SimWorld) -> void:
	_release_held(world)
	task = null
	step_index = 0
	_step_started = false
	_waiting_for = ""
	_repaths = 0
	clear_path()


func _release_held(world: SimWorld) -> void:
	if _held_item_id != 0:
		var it := world.grid.item(_held_item_id)
		if it != null:
			it.release(_held_cell, id)
	_held_item_id = 0
	_held_cell = SimGrid.NO_CELL


func _name() -> String:
	return display_name if not display_name.is_empty() else "%s #%d" % [role, id]
