extends TestCase
## Actual five-day sessions compare default job choices with the frozen picker.
## FK-077 adds a new task kind absent from that historical policy: both sides
## use zero spill chance and an unreachable grease threshold here. All report,
## books, RNG and actual task trace equality assertions remain unchanged.
## Feature-enabled five-day invariants and test_mishaps cover everyday messes.
## The reference is dfbc206efdecd4b44654979901511fc813c48ee3, not a fabricated
## expected score table. Runtime evidence exists only after this test is run.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
const FrozenMainStaff: Script = preload("res://tests/fixtures/frozen_main_staff_picker.gd")
const DAYS: int = 5
## Same ceilings as the existing five-day invariant and manual probe.
const MAX_TICK_BATCHES: int = 30
const TICKS_PER_BATCH: int = 1000

var _mains: Array[Node] = []


class TaskTrace:
	extends RefCounted
	var rows: Array[Dictionary] = []
	var _world_ref: WeakRef


	func _init(world: SimWorld) -> void:
		_world_ref = weakref(world)


	func posted(task: SimTask) -> void:
		_record(&"posted", task)


	func completed(task: SimTask) -> void:
		_record(&"completed", task)


	func failed(task: SimTask, reason: StringName) -> void:
		_record(reason, task)


	func dropped(task: SimTask, agent_id: int, reason: StringName) -> void:
		_record(reason, task, agent_id)


	func _record(event: StringName, task: SimTask, previous_agent: int = -1) -> void:
		var world: SimWorld = _world_ref.get_ref() as SimWorld
		rows.append({"event": String(event), "tick": world.now, "task": task.id,
			"kind": String(task.kind), "claimant": task.claimed_by,
			"previous_claimant": previous_agent, "claimed_tick": task.claimed_tick,
			"state": task.state, "drops": task.drops})


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_default_seed_one_matches_frozen_main_for_five_days() -> void:
	await _check_seed(1)


func test_default_seed_seven_matches_frozen_main_for_five_days() -> void:
	await _check_seed(7)


func test_default_seed_forty_two_matches_frozen_main_for_five_days() -> void:
	await _check_seed(42)


func _check_seed(seed_value: int) -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var reference: Dictionary = _run_case(seed_value, true)
	assert_false(reference.has("error"), str(reference.get("error", "")))
	if reference.has("error"):
		return
	var current: Dictionary = _run_case(seed_value, false)
	assert_false(current.has("error"), str(current.get("error", "")))
	if current.has("error"):
		return
	assert_eq(current["days"], reference["days"], "seed %d: reports, books, staff, stock and named RNGs match main" % seed_value)
	assert_eq(current["tasks"], reference["tasks"], "seed %d: actual task order, claimant and completion ticks match main" % seed_value)
	assert_true(int(current["served"]) > 0, "a nonempty real service comparison is required")


func _run_case(seed_value: int, frozen: bool) -> Dictionary:
	var main: Node = MainScene.instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", seed_value)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null:
		_close(main)
		return {"error": "The actual Main session did not start"}
	var legacy: MessTuning = sim.mishaps.tuning.duplicate() as MessTuning
	legacy.spill_chance_per_cell = 0.0
	legacy.grease_threshold = 1000
	sim.mishaps.tuning = legacy
	if frozen and not _install_frozen_picker(main, sim):
		_close(main)
		return {"error": "Could not install the frozen main picker before service"}
	var trace: TaskTrace = TaskTrace.new(sim.world)
	sim.world.board.task_posted.connect(trace.posted)
	sim.world.board.task_completed.connect(trace.completed)
	sim.world.board.task_failed.connect(trace.failed)
	sim.world.board.task_dropped.connect(trace.dropped)
	var daily: Array[Dictionary] = []
	var served: int = 0
	var error: String = ""
	for day: int in range(1, DAYS + 1):
		if frozen:
			for agent: SimAgent in sim.world.agents:
				if agent is StaffAgent and not agent is OwnerAgent:
					assert_eq(agent.get_script(), FrozenMainStaff, "morning retains the frozen picker")
		if Clock.sim.day != day or not Clock.sim.start_service():
			error = "The shop did not open on day %d" % day
			break
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < MAX_TICK_BATCHES:
			main.call("run_ticks", TICKS_PER_BATCH)
			batches += 1
		if Clock.sim.phase != SimClock.Phase.CLOSED:
			error = "Day %d exceeded the existing tick ceiling" % day
			break
		var report: DayReport = main.get("shown_report") as DayReport
		if report == null:
			error = "The actual Main session produced no evening report on day %d" % day
			break
		served += sim.served_today
		var roster: StaffRoster = main.get("staff_roster") as StaffRoster
		daily.append({"report": report.to_dict(), "ledger": Economy.ledger.to_dict(),
			"cash": Economy.cash, "stock": Economy.stock.to_dict(), "staff": roster.to_dict(),
			"clock": Clock.sim.to_dict(), "now": sim.world.now,
			"rng": GameState.call("_capture_save")})
		if day < DAYS and not Clock.sim.next_day():
			error = "The next morning did not start after day %d" % day
			break
	sim.world.board.task_posted.disconnect(trace.posted)
	sim.world.board.task_completed.disconnect(trace.completed)
	sim.world.board.task_failed.disconnect(trace.failed)
	sim.world.board.task_dropped.disconnect(trace.dropped)
	_close(main)
	if not error.is_empty():
		return {"error": error}
	return {"days": daily, "tasks": trace.rows, "served": served}


## Replace only idle starting employees, preserving the production world,
## objects, agent order/IDs, owner, stock, clocks, RNGs and every task poster.
## Main's normal morning roster install then retains these same employees.
func _install_frozen_picker(main: Node, sim: RestaurantSim) -> bool:
	var roster: StaffRoster = main.get("staff_roster") as StaffRoster
	var members: Dictionary[StringName, StaffMember] = {}
	for member: StaffMember in roster.members():
		members[member.id] = member
	var replacements: Dictionary[int, StaffAgent] = {}
	for index: int in range(sim.world.agents.size()):
		var employee: StaffAgent = sim.world.agents[index] as StaffAgent
		if employee == null or employee is OwnerAgent:
			continue
		if employee.task != null or not employee.path.is_empty() or not members.has(employee.member_id):
			return false
		var member: StaffMember = members[employee.member_id]
		var replacement: StaffAgent = FrozenMainStaff.new(member.role, member.skill) as StaffAgent
		replacement.configure_member(member, StaffRoster.CATALOGUE.find_trait(member.trait_id))
		replacement.id = employee.id
		replacement.cell = employee.cell
		replacement.last_progress_tick = employee.last_progress_tick
		replacements[index] = replacement
	for index: int in replacements:
		sim.world.agents[index] = replacements[index]
	return replacements.size() == members.size()


func _close(main: Node) -> void:
	_mains.erase(main)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()
