extends TestCase
## FK-013 soak test: the "it never breaks" pillar. Staff work a random stream
## of tasks while furniture is randomly placed and removed under them. Every
## tick we check the self-healing invariants from docs/TECH.md 2.3; at the end
## the board must drain completely.

const TICKS: int = 8000
const DRAIN_TICKS: int = 3000

var completed: int = 0
var failed: int = 0
var fail_reasons: Dictionary[StringName, int] = {}


func _on_completed(_t: SimTask) -> void:
	completed += 1


func _on_failed(_t: SimTask, reason: StringName) -> void:
	failed += 1
	fail_reasons[reason] = fail_reasons.get(reason, 0) + 1


func test_soak_no_stuck_agents_and_board_drains() -> void:
	var grid := SimGrid.from_ascii(PackedStringArray([
		"################",
		"#..............#",
		"#..............#",
		"#..............#",
		"#..............#",
		"#..............#",
		"#..............#",
		"#..............#",
		"#######..#######",
		"       EE       ",
	]))
	var stations: Array[PlacedItem] = []
	for x: int in [2, 5, 8, 11]:
		var st := grid.place(Vector2i(2, 1), Vector2i(x, 1), 0, true, [Vector2i(0, 1), Vector2i(1, 1)] as Array[Vector2i])
		stations.append(st)
	var world := SimWorld.new(grid)
	world.board.task_completed.connect(_on_completed)
	world.board.task_failed.connect(_on_failed)
	var staff: Array[StaffAgent] = []
	for i in 5:
		var a := StaffAgent.new(&"cook" if i < 3 else &"server", 1 + i % 5)
		a.cell = Vector2i(3 + i * 2, 6)
		world.add_agent(a)
		staff.append(a)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var blockers: Array[int] = []
	var posted := 0
	for tick in TICKS + DRAIN_TICKS:
		var posting := tick < TICKS
		if posting and tick % 15 == 0:
			var t := SimTask.new(&"job", &"cook" if rng.randf() < 0.6 else &"server", "Job %d" % posted)
			t.timeout_ticks = 400
			var a_station := stations[rng.randi_range(0, stations.size() - 1)]
			var b_station := stations[rng.randi_range(0, stations.size() - 1)]
			t.steps.append(TaskStep.go_to_item(a_station.id, "to A"))
			t.steps.append(TaskStep.work(rng.randi_range(5, 40), "work A"))
			t.steps.append(TaskStep.go_to_item(b_station.id, "to B"))
			t.steps.append(TaskStep.work(rng.randi_range(5, 40), "work B"))
			world.board.post(t, world.now)
			posted += 1
		if posting and tick % 97 == 0:
			# Drop a random 1x1 or 2x1 blocker on a random floor cell (possibly
			# on top of someone), or remove an old one.
			if blockers.size() > 6 or (blockers.size() > 0 and rng.randf() < 0.4):
				grid.remove(blockers.pop_front())
			else:
				var fp := Vector2i(rng.randi_range(1, 2), 1)
				var at := Vector2i(rng.randi_range(1, 13), rng.randi_range(2, 7))
				var it := grid.place(fp, at, rng.randi_range(0, 3), true)
				if it != null:
					blockers.append(it.id)
		if tick == TICKS:
			for id in blockers:
				grid.remove(id)
			blockers.clear()
		world.advance()
		# Invariants, every tick.
		for t in world.board.claimed_tasks():
			if world.now - t.claimed_tick > t.timeout_ticks + 1:
				fail("tick %d: task %s held past its timeout" % [world.now, t.label])
				return
		for a in staff:
			if a.task != null and not a.why().contains("waiting for") \
					and world.now - a.last_progress_tick > StaffAgent.STUCK_TICKS * 2 + 2:
				fail("tick %d: %s made no progress for too long (%s)" % [world.now, a.id, a.why()])
				return
	assert_eq(world.board.active_count(), 0, "the board drained after posting stopped")
	assert_eq(completed + failed, posted, "every task ended exactly once")
	assert_true(completed >= posted * 0.9,
			"most tasks complete (%d of %d; failures %s)" % [completed, posted, fail_reasons])
	for a in staff:
		assert_null(a.task, "agent %d idle at the end" % a.id)
	for st in stations:
		for c in st.work_cells:
			assert_eq(st.reserved_by(c), -1, "no reservation left on station %d" % st.id)
