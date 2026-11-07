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
const GUEST_URGENCY: GuestUrgencyTuning = preload("res://data/balance/guest_urgency.tres")

## How strongly the guests nearest to leaving are served first (#307).
var urgency_tuning: GuestUrgencyTuning = GUEST_URGENCY

## Skill per role, 1 (poor) .. 5 (great).
var skills: Dictionary[StringName, int] = {}
## Priority per role: 0 off, 1 low, 2 normal, 3 high. &"any" covers role-free tasks.
var priorities: Dictionary[StringName, int] = {}
## Employee job choices are separate from legacy role eligibility/score.
## Null keeps the owner's and manually constructed agents' existing policy.
var _job_priorities: StaffJobPriorities = null
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
var _cleaner_checked_tick: int = -1
var _cleaner_checked_agents: int = -1
var _cleaner_on_team: bool = false

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
	set_job_priorities(member.priority_state())
	# Work speed reads task roles, including a server's fallback mopping. Copy
	# every earned skill at morning setup without changing task priorities.
	for staff_role: StringName in StaffMember.ROLES:
		skills[staff_role] = member.growth_state().skill_level(StaffMember._primary_skill(staff_role))
	move_speed = move_speed / _walk_multiplier * definition.walk_multiplier
	_walk_multiplier = definition.walk_multiplier
	cook_quality_bonus = definition.cook_quality_bonus
	food_patience_multiplier = definition.food_patience_multiplier


## Copy only next-pick choices. Never reset a task, path, reservation or skill.
func set_job_priorities(choices: StaffJobPriorities) -> bool:
	if choices == null or choices.role != role:
		return false
	var staged: StaffJobPriorities = StaffJobPriorities.new(role)
	if not staged.from_dict(choices.to_dict()):
		return false
	_job_priorities = staged
	return true


func job_priorities() -> StaffJobPriorities:
	return _job_priorities.copy() if _job_priorities != null else null


func movement_multiplier() -> float:
	return _walk_multiplier


## Physical meals in hand, not a retained delivery batch before re-pickup.
func carries_food() -> bool:
	if task != null and task.kind == &"pour":
		var drink_world: SimWorld = movement_world()
		return drink_world != null and drink_world.carries_prepared_drink(self)
	if task == null or task.state != SimTask.State.CLAIMED or task.claimed_by != id \
			or task.kind != &"deliver" or int(task.payload.get("carried_count", 0)) <= 0:
		return false
	var world: SimWorld = movement_world()
	if world != null and world.board.get_task(task.id) != task:
		return false
	return not task.payload.has("pass_id") or step_index >= 2


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
		if not world.grid.is_walkable(cell):
			return
		_try_claim(world)
		return
	if not _maintain_claim(world):
		return
	_run_step(world)
	_recover_no_progress(world)


## Movement owns the physical tick, while task leases still need maintenance.
## This never claims work or advances a productive task step.
func maintain_movement_pause(world: SimWorld) -> void:
	if task == null or not _maintain_claim(world):
		return
	_recover_no_progress(world)


func _maintain_claim(world: SimWorld) -> bool:
	if task.state != SimTask.State.CLAIMED or task.claimed_by != id:
		_let_go(world)
		return false
	if world.now - task.claimed_tick > task.timeout_ticks:
		_drop(world, &"timeout")
		return false
	return true


func _recover_no_progress(world: SimWorld) -> void:
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
		var prefix: String = "waiting"
		if step_index < task.steps.size() and task.steps[step_index].kind == TaskStep.Kind.WAIT_UNTIL:
			prefix = "Waiting"
		step_text = "%s for %s" % [prefix, _waiting_for]
	return task.label if step_text.is_empty() else "%s: %s" % [task.label, step_text]


func _try_claim(world: SimWorld) -> void:
	var candidates: Array[SimTask] = world.open_tasks_this_tick()
	var scores: Dictionary[int, float] = {}
	var reserved_buses: Dictionary[int, bool] = {}
	var highest_priorities: Dictionary[StringName, int] = {}
	var highest_job_level: int = StaffJobPriorities.Level.OFF
	var fallback_cleaning: bool = _can_fallback_clean(world)
	var service_work_open: bool = false
	var table_urgency: float = -1.0
	# Actor-local eligibility uses the existing score, including role preferences
	# and missing targets. Another worker may have claimed a cached task already.
	for t: SimTask in candidates:
		if t.state != SimTask.State.OPEN or world.board.get_task(t.id) != t:
			continue
		var score: float = _score(world, t)
		if score > 0.0:
			if GuestUrgency.is_table_task(t):
				if table_urgency < 0.0:
					table_urgency = GuestUrgency.waiting_for_table(world)
				score *= 1.0 + urgency_tuning.table_weight * table_urgency
			else:
				score *= 1.0 + urgency_tuning.guest_weight * GuestUrgency.of_task(world, t)
		scores[t.id] = score
		if score > 0.0:
			if t.kind == &"bus_table" and world.booking_hold != null \
					and world.booking_hold.prioritizes_bussing(world, t.first_item_id()):
				reserved_buses[t.id] = true
			if fallback_cleaning and t.role == &"server":
				service_work_open = true
			var job_level: int = _job_level(t)
			if job_level > highest_job_level:
				highest_job_level = job_level
				highest_priorities.clear()
			# Existing task urgency deferral stays within the chosen job tier.
			if job_level == highest_job_level and (not highest_priorities.has(t.role) or t.priority > highest_priorities[t.role]):
				highest_priorities[t.role] = t.priority
	var best: SimTask = null
	var best_score := 0.0
	for t: SimTask in candidates:
		if world.board.get_task(t.id) != t:
			continue
		# A reservation is a temporary promise: its eligible cleanup precedes
		# other positive saved job tiers. _score still makes OFF/roles absolute.
		if not reserved_buses.is_empty():
			if not reserved_buses.has(t.id) or t.state != SimTask.State.OPEN:
				continue
		elif not _eligible(t, highest_job_level, highest_priorities):
			continue
		# Legacy agents and the Floor-mode owner retain the original mop fallback.
		# Configured employees instead use the saved job tier above distance.
		if _job_priorities == null and fallback_cleaning and service_work_open and _is_clean_spot(t):
			continue
		var score: float = scores.get(t.id, 0.0)
		if score > best_score:
			best = t
			best_score = score
	if best != null and world.board.claim(best, id, world.now):
		task = best
		step_index = 0
		_step_started = false
		_repaths = 0
		last_progress_tick = world.now


## Still open, in the chosen job tier and not deferred to a more urgent task.
func _eligible(t: SimTask, job_level: int, highest_priorities: Dictionary[StringName, int]) -> bool:
	if t.state != SimTask.State.OPEN:
		return false
	if _job_level(t) != job_level:
		return false
	return not (t.defer_to_higher_priority and int(highest_priorities.get(t.role, t.priority)) > t.priority)


## 0 means "won't take it". Higher is better: priority x role priority x skill
## over distance to the first target.
func _score(world: SimWorld, t: SimTask) -> float:
	if _job_level(t) == StaffJobPriorities.Level.OFF:
		return 0.0
	var for_role := t.role
	var role_prio: int = priorities.get(for_role, 0)
	if _is_clean_spot(t) and role != &"cleaner":
		if not _can_fallback_clean(world):
			return 0.0
		role_prio = 1
	if t.kind == &"degrease" and role == &"owner" and _idle_server_can_clean(world):
		return 0.0
	# Cleaning a fish tank (#125) is the cleaner's; with no cleaner the owner
	# on Floor does it, never a server.
	if t.kind == AquariumCare.TASK_KIND and role != &"cleaner":
		if role != &"owner" or not _can_fallback_clean(world):
			return 0.0
		role_prio = 1
	# Putting deliveries away (FK-099): with a cleaner on the team it is theirs
	# (Cleaning), as mopping is; otherwise servers do it as Serving.
	if t.kind == DeliveryDock.TASK_KIND and role != &"cleaner" and _team_has_cleaner(world):
		return 0.0
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
	elif (_is_clean_spot(t) or t.kind == AquariumCare.TASK_KIND) and not t.steps.is_empty() \
			and t.steps[0].kind == TaskStep.Kind.GO_TO_CELL:
		target = t.steps[0].cell
	var skill := skill_for(for_role)
	return float((t.priority + 1) * role_prio * skill) / (1.0 + GridMath.octile(cell, target))


func _job_level(candidate: SimTask) -> int:
	if _job_priorities == null:
		return StaffJobPriorities.Level.NORMAL
	var job: StringName = StaffJobPriorities.job_for_task(candidate.kind, role)
	# Synthetic role-free tasks keep their legacy selection behavior. Every
	# production kind is named in the one sim mapping, not inferred from roles.
	return StaffJobPriorities.Level.NORMAL if job.is_empty() else _job_priorities.priority(job)


func _is_clean_spot(candidate: SimTask) -> bool:
	return (candidate.kind == &"clean_spot" or candidate.kind == &"degrease") and candidate.role == &"cleaner"


## A Floor owner is the last maintenance fallback, even if nearer the stove.
## Busy servers may keep serving while the owner helps; Cleaning Off stays Off.
func _idle_server_can_clean(world: SimWorld) -> bool:
	for agent: SimAgent in world.agents:
		var server: StaffAgent = agent as StaffAgent
		if server != null and server.role == &"server" and server.task == null \
				and int(server.priorities.get(&"server", 0)) > 0 \
				and (server._job_priorities == null or server._job_priorities.priority(&"cleaning") > StaffJobPriorities.Level.OFF):
			return true
	return false


## An available dedicated cleaner keeps this fallback off, even while busy.
func _can_fallback_clean(world: SimWorld) -> bool:
	if not (role == &"server" and int(priorities.get(&"server", 0)) > 0) \
			and not (role == &"owner" and int(priorities.get(&"cleaner", 0)) > 0):
		return false
	return not _team_has_cleaner(world)


## Asked for every candidate task, so it is worked out once per tick.
func _team_has_cleaner(world: SimWorld) -> bool:
	if _cleaner_checked_tick == world.now and _cleaner_checked_agents == world.agents.size():
		return _cleaner_on_team
	_cleaner_checked_tick = world.now
	_cleaner_checked_agents = world.agents.size()
	_cleaner_on_team = false
	for agent: SimAgent in world.agents:
		if agent is StaffAgent and agent.role == &"cleaner":
			_cleaner_on_team = true
			break
	return _cleaner_on_team


## Stops at once when the task held was withdrawn (DeliveryDock at closing),
## instead of on the next tick.
func let_go_if_withdrawn(world: SimWorld) -> void:
	if task != null and (task.state != SimTask.State.CLAIMED or task.claimed_by != id):
		_let_go(world)


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
		TaskStep.Kind.WAIT_UNTIL:
			_run_wait(world, s)


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
		elif not s.use_seat and target != SimGrid.NO_CELL:
			# Select once from this worker's real vertex, keeping authored ties.
			var candidates: Array[Vector2i] = []
			for work_cell: Vector2i in it.work_cells:
				if it.reserved_by(work_cell) == -1 and world.grid.is_walkable(work_cell):
					candidates.append(work_cell)
			target = _closest_go_to_candidate(world, candidates, SimGrid.NO_CELL)
			if target == SimGrid.NO_CELL:
				_drop(world, &"unreachable")
				return
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
		var target: Vector2i = s.cell
		if not s.candidate_cells.is_empty():
			target = _closest_go_to_candidate(world, s.candidate_cells, s.candidate_origin)
			if target == SimGrid.NO_CELL:
				_drop(world, &"unreachable")
				return
		if not set_destination(world.grid, target):
			_drop(world, &"unreachable")
			return
		_step_started = true
	_walk(world)

## Read current physical permissions once, when this worker actually starts GO.
## Later repaths follow the existing selected _goal, not the posted anchor.
func _closest_go_to_candidate(world: SimWorld, candidates: Array[Vector2i],
		origin: Vector2i) -> Vector2i:
	if not movement_admitted or world.agent(id) != self or not is_finite(move_progress) \
			or move_progress < 0.0 or move_progress >= 1.0:
		return SimGrid.NO_CELL
	var start: Vector2i = cell
	if move_progress > 0.0:
		var next: Vector2i = next_cell()
		var snapshot: Dictionary = world.movement.snapshot()
		var delta: Vector2i = next - cell
		if maxi(absi(delta.x), absi(delta.y)) != 1 \
				or not world.grid.is_walkable(cell) or not world.grid.is_walkable(next) \
				or not world.grid.step_open(cell, next) \
				or snapshot.occupied.get(cell, -1) != id or snapshot.next.get(next, -1) != id:
			return SimGrid.NO_CELL
		var swept: Array[Vector2i] = [next]
		if delta.x != 0 and delta.y != 0:
			swept.append(cell + Vector2i(delta.x, 0))
			swept.append(cell + Vector2i(0, delta.y))
		for point: Vector2i in swept:
			if not world.movement.can_enter(world, self, point):
				return SimGrid.NO_CELL
		var held_edge: bool = false
		for edge: Dictionary in snapshot.edges:
			if edge.id == id and edge["from"] == cell and edge["to"] == next:
				held_edge = true
				break
		if not held_edge:
			return SimGrid.NO_CELL
		# set_destination retains this real edge and defers the chosen goal.
		start = next
	var current_neighbours: Array[Vector2i] = []
	if origin != SimGrid.NO_CELL:
		if not world.grid.is_walkable(origin):
			return SimGrid.NO_CELL
		current_neighbours = world.grid.walkable_neighbours(origin)
	var chosen: Vector2i = SimGrid.NO_CELL
	var shortest: float = INF
	for candidate: Vector2i in candidates:
		if origin != SimGrid.NO_CELL and not current_neighbours.has(candidate):
			continue
		if not world.movement.standing_cell(world, candidate):
			continue
		var route: Array[Vector2i] = world.movement.route(world, self, start, candidate, false)
		if route.is_empty():
			continue
		var cost: float = GridMath.path_cost(route)
		if cost < shortest:
			shortest = cost
			chosen = candidate
	return chosen



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
	var factor: float = float(s.work_rate.call(self)) if s.work_rate.is_valid() else 1.0
	work_left -= work_speed(task.role) * factor
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


func _run_wait(world: SimWorld, s: TaskStep) -> void:
	if not s.on_done.is_valid():
		_drop(world, &"step_failed")
		return
	var ready: Variant = s.on_done.call(self)
	if task == null or task.state != SimTask.State.CLAIMED:
		return
	if ready is bool and ready:
		_waiting_for = ""
		_next_step(world)
		# An available resource must not add a tick to the existing work chain.
		if task != null and task.state == SimTask.State.CLAIMED:
			if step_index < task.steps.size() and task.steps[step_index].kind == TaskStep.Kind.WORK:
				_run_work(world, task.steps[step_index])
	else:
		_waiting_for = s.label if not s.label.is_empty() else "the next step"
		last_progress_tick = world.now


func _next_step(world: SimWorld) -> void:
	step_index += 1
	_step_started = false
	_waiting_for = ""
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
			if it.seat_cells.has(_held_cell):
				world.movement.defer_seat_release(world, it.id, _held_cell, id)
			else:
				it.release(_held_cell, id)
	_held_item_id = 0
	_held_cell = SimGrid.NO_CELL


func _name() -> String:
	return display_name if not display_name.is_empty() else "%s #%d" % [role, id]
