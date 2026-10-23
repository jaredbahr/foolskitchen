extends TestCase
## FK-013 soak test: the "it never breaks" pillar. Staff work a random stream
## of tasks while the world misbehaves on purpose: blockers dropped on and
## around them, stations boxed in, stations removed and re-placed, staff
## leaving and joining, and tasks whose timeout is shorter than their work.
## Every tick we check the self-healing invariants from docs/TECH.md 2.3. At
## the end the board must drain, and each healing path must actually have run
## (counters > 0), so the test can't pass while healing is switched off.

const TICKS: int = 8000
const DRAIN_TICKS: int = 3000

var completed: int = 0
var failed: int = 0
var reasons: Dictionary[StringName, int] = {}
var drops: Dictionary[StringName, int] = {}


func _on_completed(_t: SimTask) -> void:
	completed += 1


func _on_failed(_t: SimTask, reason: StringName) -> void:
	failed += 1
	reasons[reason] = reasons.get(reason, 0) + 1


func _on_dropped(_t: SimTask, _agent_id: int, reason: StringName) -> void:
	drops[reason] = drops.get(reason, 0) + 1


func _station(grid: SimGrid, x: int) -> PlacedItem:
	return grid.place(Vector2i(2, 1), Vector2i(x, 1), 0, true, [Vector2i(0, 1), Vector2i(1, 1)] as Array[Vector2i])


func test_soak_world_misbehaves_and_heals() -> void:
	var grid := SimGrid.from_ascii(PackedStringArray([
		"##################",
		"#................#",
		"#................#",
		"#................#",
		"#................#",
		"#................#",
		"#................#",
		"#................#",
		"########..########",
		"        EE        ",
	]))
	var station_x: Array[int] = [2, 5, 8, 11, 14]
	var stations: Array[PlacedItem] = []
	for x in station_x:
		stations.append(_station(grid, x))
	var world := SimWorld.new(grid)
	world.board.task_completed.connect(_on_completed)
	world.board.task_failed.connect(_on_failed)
	world.board.task_dropped.connect(_on_dropped)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 5:
		var a := StaffAgent.new(&"cook" if i < 3 else &"server", 1 + i % 5)
		a.cell = Vector2i(3 + i * 2, 6)
		world.add_agent(a)
	var blockers: Array[int] = []
	var box: Array[int] = []
	var posted := 0
	var removed_agents := 0
	var replaced_stations := 0
	for tick in TICKS + DRAIN_TICKS:
		var chaos := tick < TICKS
		if chaos and tick % 15 == 0:
			var t := SimTask.new(&"job", &"cook" if rng.randf() < 0.6 else &"server", "Job %d" % posted)
			# One task in ten can't finish within its timeout.
			t.timeout_ticks = 60 if rng.randf() < 0.1 else 400
			var a_st := stations[rng.randi_range(0, stations.size() - 1)]
			var b_st := stations[rng.randi_range(0, stations.size() - 1)]
			t.steps.append(TaskStep.go_to_item(a_st.id, "to A"))
			t.steps.append(TaskStep.work(rng.randi_range(5, 40), "work A"))
			t.steps.append(TaskStep.go_to_item(b_st.id, "to B"))
			t.steps.append(TaskStep.work(rng.randi_range(5, 40), "work B"))
			world.board.post(t, world.now)
			posted += 1
		if chaos and tick % 97 == 0:
			# Random blockers, sometimes right on top of someone.
			if blockers.size() > 6 or (blockers.size() > 0 and rng.randf() < 0.4):
				grid.remove(blockers.pop_front())
			else:
				var fp := Vector2i(rng.randi_range(1, 3), rng.randi_range(1, 2))
				var at := Vector2i(rng.randi_range(1, 15), rng.randi_range(2, 7))
				var it := grid.place(fp, at, rng.randi_range(0, 3), true)
				if it != null:
					blockers.append(it.id)
		if chaos and tick % 1200 == 300:
			# Box the middle station in for a while (its work cells become unreachable).
			for x in range(7, 11):
				var b := grid.place(Vector2i(1, 1), Vector2i(x, 3), 0, true)
				if b != null:
					box.append(b.id)
			for x: int in [7, 10]:
				var b := grid.place(Vector2i(1, 1), Vector2i(x, 2), 0, true)
				if b != null:
					box.append(b.id)
		if tick % 1200 == 700:
			for id in box:
				grid.remove(id)
			box.clear()
		if chaos and tick % 1500 == 900:
			# Remove a random station and put a new one in its place.
			var k := rng.randi_range(0, stations.size() - 1)
			grid.remove(stations[k].id)
			var fresh := _station(grid, station_x[k])
			if fresh != null:
				stations[k] = fresh
				replaced_stations += 1
		if chaos and tick % 1000 == 500:
			# A worker goes home mid-task; a new one starts.
			var leaver: SimAgent = world.agents[rng.randi_range(0, world.agents.size() - 1)]
			var role := leaver.role
			world.remove_agent(leaver)
			removed_agents += 1
			var hire := StaffAgent.new(role, rng.randi_range(1, 5))
			hire.cell = Vector2i(8, 9)
			world.add_agent(hire)
		if tick == TICKS:
			for id in blockers:
				grid.remove(id)
			blockers.clear()
		world.advance()
		var problem := _check_invariants(world)
		if not problem.is_empty():
			fail("tick %d: %s" % [world.now, problem])
			return
	assert_eq(world.board.active_count(), 0, "the board drained after the chaos stopped")
	assert_eq(completed + failed, posted, "every task ended exactly once")
	# ~10% of tasks have an impossible timeout and station swaps fail others on purpose.
	assert_true(completed >= posted * 0.6, "most tasks complete (%d of %d; failures %s, drops %s)" % [completed, posted, reasons, drops])
	# Each healing path must actually have been exercised.
	assert_true(drops.get(&"timeout", 0) > 0, "timeouts fired (%s)" % drops)
	assert_true(drops.get(&"agent_removed", 0) > 0 or removed_agents == 0, "removed agents gave tasks back (%s)" % drops)
	assert_true(reasons.get(&"target_gone", 0) > 0, "tasks for removed stations failed (%s)" % reasons)
	assert_true(replaced_stations > 0)
	assert_true(drops.get(&"unreachable", 0) > 0, "boxed-in stations caused unreachable drops (%s)" % drops)
	for a in world.agents:
		var s := a as StaffAgent
		assert_null(s.task, "agent %d idle at the end" % a.id)
	for st in stations:
		for c in st.work_cells:
			assert_eq(st.reserved_by(c), -1, "no reservation left on station %d" % st.id)


## Returns "" when all invariants hold, otherwise a description.
func _check_invariants(world: SimWorld) -> String:
	for t in world.board.claimed_tasks():
		if world.now - t.claimed_tick > t.timeout_ticks + 2:
			return "task %s held past its timeout" % t.label
		var holder := world.agent(t.claimed_by)
		if holder == null:
			return "task %s claimed by a missing agent %d" % [t.label, t.claimed_by]
		if (holder as StaffAgent).task != t:
			return "task %s claimed by %d, who is doing something else" % [t.label, t.claimed_by]
	for a in world.agents:
		var s := a as StaffAgent
		if s.task != null and not s.why().contains("waiting for") \
				and world.now - s.last_progress_tick > StaffAgent.STUCK_TICKS * 2 + 2:
			return "agent %d made no progress for too long (%s)" % [a.id, s.why()]
	for it in world.grid.items():
		for c in it.work_cells + it.seat_cells:
			var holder_id := it.reserved_by(c)
			if holder_id == -1:
				continue
			var holder := world.agent(holder_id)
			if holder == null or (holder as StaffAgent).task == null:
				return "cell %s of item %d reserved by idle or missing agent %d" % [c, it.id, holder_id]
	return ""
