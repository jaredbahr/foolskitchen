extends StaffAgent
## Test-only frozen selection policy from main dfbc206efdecd4b44654979901511fc813c48ee3.
## staff_agent.gd blob 9e5f28040bd43e1d9246c608a8fd58b22f281e2f.
## Only selection is historical. Movement/work remains production code and the
## fixture installs this subclass before service without changing IDs or RNG.


func _try_claim(world: SimWorld) -> void:
	var candidates: Array[SimTask] = world.open_tasks_this_tick()
	var scores: Dictionary[int, float] = {}
	var highest_priorities: Dictionary[StringName, int] = {}
	var fallback_cleaning: bool = _can_fallback_clean(world)
	var service_work_open: bool = false
	# Actor-local eligibility uses the existing score, including role preferences
	# and missing targets. Another worker may have claimed a cached task already.
	for t: SimTask in candidates:
		if t.state != SimTask.State.OPEN or world.board.get_task(t.id) != t:
			continue
		var score: float = _score(world, t)
		scores[t.id] = score
		if score > 0.0:
			if fallback_cleaning and t.role == &"server":
				service_work_open = true
			if not highest_priorities.has(t.role) or t.priority > highest_priorities[t.role]:
				highest_priorities[t.role] = t.priority
	var best: SimTask = null
	var best_score := 0.0
	for t: SimTask in candidates:
		if t.state != SimTask.State.OPEN or world.board.get_task(t.id) != t:
			continue
		if t.defer_to_higher_priority and int(highest_priorities.get(t.role, t.priority)) > t.priority:
			continue
		# A server (or Floor-mode owner) mops only after all currently eligible
		# service work is claimed. Distance must never invert this fallback order.
		if fallback_cleaning and service_work_open and _is_clean_spot(t):
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


func _score(world: SimWorld, t: SimTask) -> float:
	var for_role := t.role
	var role_prio: int = priorities.get(for_role, 0)
	if _is_clean_spot(t) and role != &"cleaner":
		if not _can_fallback_clean(world):
			return 0.0
		role_prio = 1
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
	elif _is_clean_spot(t) and not t.steps.is_empty() and t.steps[0].kind == TaskStep.Kind.GO_TO_CELL:
		target = t.steps[0].cell
	var skill := skill_for(for_role)
	return float((t.priority + 1) * role_prio * skill) / (1.0 + GridMath.octile(cell, target))


func _is_clean_spot(candidate: SimTask) -> bool:
	return candidate.kind == &"clean_spot" and candidate.role == &"cleaner"


func _can_fallback_clean(world: SimWorld) -> bool:
	if not (role == &"server" and int(priorities.get(&"server", 0)) > 0) \
			and not (role == &"owner" and int(priorities.get(&"cleaner", 0)) > 0):
		return false
	for agent: SimAgent in world.agents:
		if agent is StaffAgent and agent.role == &"cleaner":
			return false
	return true
