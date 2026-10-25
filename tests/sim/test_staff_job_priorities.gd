extends TestCase
## Saved per-job choices and actual idle-claim behavior, without scene nodes.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CLEANING: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")


func test_one_mapping_covers_every_production_task_kind() -> void:
	assert_eq(StaffJobPriorities.TASK_JOBS.size(), 6)
	for kind: StringName in [&"cook", &"take_order", &"deliver", &"bus_table", &"wash", &"clean_spot"]:
		assert_true(StaffJobPriorities.JOBS.has(StaffJobPriorities.job_for_task(kind)))
	assert_eq(StaffJobPriorities.job_for_task(&"take_order"), &"serving")
	assert_eq(StaffJobPriorities.job_for_task(&"deliver"), &"serving")
	assert_eq(StaffJobPriorities.job_for_task(&"unknown"), &"")


func test_defaults_and_readable_labels_match_current_role_capabilities() -> void:
	assert_eq(StaffJobPriorities.new(&"cook").to_dict(),
		{"cooking": 3, "serving": 0, "bussing": 0, "washing": 0, "cleaning": 0})
	assert_eq(StaffJobPriorities.new(&"server").to_dict(),
		{"cooking": 0, "serving": 2, "bussing": 2, "washing": 2, "cleaning": 1})
	assert_eq(StaffJobPriorities.new(&"cleaner").to_dict(),
		{"cooking": 0, "serving": 0, "bussing": 0, "washing": 0, "cleaning": 3})
	for job: StringName in StaffJobPriorities.JOBS:
		assert_ne(StaffJobPriorities.job_label(job), String(job))
	assert_eq(StaffJobPriorities.level_label(StaffJobPriorities.Level.HIGH), "High")
	assert_eq(StaffJobPriorities.level_label(StaffJobPriorities.Level.OFF), "Off")


func test_main_job_cannot_be_off_and_unsupported_work_cannot_be_enabled() -> void:
	for role: StringName in StaffMember.ROLES:
		var choices: StaffJobPriorities = StaffJobPriorities.new(role)
		var main: StringName = StaffJobPriorities.main_job(role)
		var before: Dictionary = choices.to_dict()
		assert_false(choices.set_priority(main, StaffJobPriorities.Level.OFF))
		assert_eq(choices.to_dict(), before)
		assert_true(choices.set_priority(main, StaffJobPriorities.Level.LOW))
		for job: StringName in StaffJobPriorities.JOBS:
			if not StaffJobPriorities.supports(role, job):
				assert_false(choices.set_priority(job, StaffJobPriorities.Level.HIGH))
				assert_eq(choices.priority(job), StaffJobPriorities.Level.OFF)
		assert_false(choices.set_priority(&"unknown", 2))
		assert_false(choices.set_priority(main, -1))
		assert_false(choices.set_priority(main, 4))


func test_priority_decoder_rejects_bad_rows_without_partial_changes() -> void:
	var choices: StaffJobPriorities = StaffJobPriorities.new(&"server")
	assert_true(choices.set_priority(&"cleaning", StaffJobPriorities.Level.HIGH))
	var before: Dictionary = choices.to_dict()
	for bad: Variant in [null, [], true, "High", {}]:
		assert_false(choices.from_dict(bad))
		assert_eq(choices.to_dict(), before)
	for bad: Variant in [-1, 4, 1.5, NAN, INF, true, "3", null, {}, []]:
		var row: Dictionary = before.duplicate(true)
		row["bussing"] = 0
		row["cleaning"] = bad
		assert_false(choices.from_dict(row))
		assert_eq(choices.to_dict(), before, "no earlier valid field may install on failure")
	for key: String in ["serving", "cooking", "washing"]:
		var row: Dictionary = before.duplicate(true)
		if key == "serving":
			row[key] = 0
		elif key == "cooking":
			row[key] = 1
		else:
			row.erase(key)
			row["unknown"] = 2
		assert_false(choices.from_dict(row))
		assert_eq(choices.to_dict(), before)
	var json_row: Variant = JSON.parse_string(JSON.stringify(before))
	assert_true(choices.from_dict(json_row), "JSON whole-number floats restore")
	assert_eq(choices.to_dict(), before)


func test_member_priorities_round_trip_and_legacy_rows_receive_defaults() -> void:
	var member: StaffMember = _member(&"server")
	assert_true(member.priority_state().set_priority(&"cleaning", 3))
	assert_true(member.priority_state().set_priority(&"bussing", 0))
	var saved: Dictionary = member.to_dict()
	var restored: StaffMember = StaffMember.from_dict(JSON.parse_string(JSON.stringify(saved)), StaffRoster.CATALOGUE)
	assert_not_null(restored)
	if restored == null:
		return
	assert_eq(restored.to_dict(), saved)
	var detached: StaffMember = member.copy()
	assert_true(detached.priority_state().set_priority(&"cleaning", 1))
	assert_eq(member.priority_state().priority(&"cleaning"), 3)
	for has_growth: bool in [true, false]:
		var legacy: Dictionary = saved.duplicate(true)
		legacy.erase("priorities")
		if not has_growth:
			legacy.erase("growth")
		var older: StaffMember = StaffMember.from_dict(legacy, StaffRoster.CATALOGUE)
		assert_not_null(older)
		if older != null:
			assert_eq(older.priority_state().to_dict(), StaffJobPriorities.new(&"server").to_dict())


func test_roster_restore_is_transactional_and_returned_priority_state_is_detached() -> void:
	var roster: StaffRoster = StaffRoster.new()
	assert_true(roster.set_job_priority(&"starter_server", &"cleaning", 3))
	assert_false(roster.set_job_priority(&"missing", &"cleaning", 3))
	assert_false(roster.set_job_priority(&"starter_server", &"serving", 0))
	var before: Dictionary = roster.to_dict()
	var copy: StaffJobPriorities = roster.job_priorities(&"starter_server")
	assert_true(copy.set_priority(&"cleaning", 1))
	assert_eq(roster.to_dict(), before)
	assert_null(roster.job_priorities(&"missing"))
	var bad: Dictionary = before.duplicate(true)
	bad["members"][0]["name"] = "Must not install"
	bad["members"][1]["priorities"]["serving"] = 0
	assert_false(roster.from_dict(bad))
	assert_eq(roster.to_dict(), before)
	var restored: StaffRoster = StaffRoster.new()
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(before))))
	assert_eq(restored.to_dict(), before)


func test_runtime_roster_copy_preserves_staged_xp_until_close_and_detaches_growth() -> void:
	var tuning: EconomyTuning = EconomyTuning.new()
	var rules: StaffGrowthTuning = StaffRoster.GROWTH_TUNING.duplicate(true) as StaffGrowthTuning
	rules.task_xp[&"cook"] = 2
	rules.task_xp[&"deliver"] = 1
	rules.next_level_xp = PackedInt32Array([4, 6, 8, 10])
	var roster: StaffRoster = StaffRoster.new(tuning, StaffRoster.CATALOGUE, rules)
	for _index: int in range(3):
		assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	assert_true(roster.record_completed_task(&"starter_server", &"deliver"))
	var server_xp: int = rules.xp_for_task(&"deliver")
	var before: Dictionary = roster.to_dict()
	var staged: StaffRoster = roster.copy()
	assert_eq(staged.to_dict(), before)
	assert_eq(staged.members()[0].growth_state().earned_today(&"cooking"), 6,
		"the runtime copy retains XP that the saved wire intentionally omits")
	assert_eq(staged.members()[1].growth_state().earned_today(&"service"), server_xp)
	assert_true(staged.set_job_priority(&"starter_server", &"cleaning", StaffJobPriorities.Level.HIGH))
	assert_eq(roster.job_priorities(&"starter_server").priority(&"cleaning"), StaffJobPriorities.Level.LOW)
	# Policies remain the exact injected resources, rather than defaults or
	# independently duplicated tuning. Only runtime people are detached.
	rules.task_xp[&"cook"] = 1
	tuning.wages[&"cook"] = 100
	for _index: int in range(2):
		assert_true(staged.record_completed_task(&"starter_cook", &"cook"))
	assert_eq(staged.members()[0].growth_state().earned_today(&"cooking"), 8)
	var raised: Dictionary = staged.close_growth_day()
	assert_eq(raised[&"starter_cook"], [{"skill": "cooking", "level": 4}])
	assert_eq(staged.members()[0].growth_state().progress_xp(&"cooking"), 0)
	assert_eq(staged.members()[1].growth_state().progress_xp(&"service"), server_xp)
	assert_eq(staged.members()[0].growth_state().earned_today(&"cooking"), 0)
	var offers: Array[Dictionary] = staged.morning_raise_offers(1, SimClock.Phase.MORNING)
	assert_eq(offers.size(), 1)
	if offers.is_empty():
		return
	assert_eq(offers[0]["new_wage"], tuning.staff_wage(&"cook", 4))
	assert_eq(staged.close_growth_day(), {}, "a second flush grants no duplicate XP or raise")
	assert_eq(staged.members()[0].growth_state().pending_raise_count(), 1)
	assert_eq(roster.to_dict(), before, "closing the detached copy leaves the original saved state intact")
	assert_eq(roster.members()[0].growth_state().earned_today(&"cooking"), 6)
	assert_eq(roster.members()[1].growth_state().earned_today(&"service"), server_xp)
	assert_eq(roster.close_growth_day(), {})
	assert_eq(roster.members()[0].growth_state().progress_xp(&"cooking"), 6)
	assert_eq(roster.members()[1].growth_state().progress_xp(&"service"), server_xp)
	assert_eq(roster.close_growth_day(), {})
	assert_eq(roster.members()[0].growth_state().progress_xp(&"cooking"), 6)


func test_runtime_roster_copy_keeps_pool_metadata_catalogue_and_rng_and_detaches_candidates() -> void:
	var definitions: StaffCatalogue = StaffRoster.CATALOGUE.duplicate(true) as StaffCatalogue
	var roster: StaffRoster = StaffRoster.new(null, definitions)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 82014
	assert_true(roster.draw_candidates(8, random))
	var rng_state: int = random.state
	var before: Dictionary = roster.to_dict()
	var staged: StaffRoster = roster.copy()
	assert_true(staged.catalogue == definitions)
	assert_eq(staged.candidate_day, 8)
	assert_eq(staged.to_dict(), before, "the complete member and candidate rows keep their IDs and metadata")
	assert_eq(random.state, rng_state)
	assert_true(staged.draw_candidates(8, random), "the copied pool is already prepared for this morning")
	assert_eq(random.state, rng_state)
	assert_eq(staged.to_dict(), before)
	var candidate: StaffMember = staged.candidates()[0]
	assert_true(staged.hire(candidate.id))
	assert_true(staged.set_job_priority(candidate.id, StaffJobPriorities.main_job(candidate.role), StaffJobPriorities.Level.LOW))
	assert_eq(staged.members().size(), 3)
	assert_eq(staged.members()[2].id, candidate.id)
	assert_eq(staged.candidates().size(), 2)
	var kind: StringName = &"cook" if candidate.role == &"cook" else (&"deliver" if candidate.role == &"server" else &"clean_spot")
	var skill: StringName = StaffMember._primary_skill(candidate.role)
	assert_true(staged.record_completed_task(candidate.id, kind))
	assert_true(staged.members()[2].growth_state().earned_today(skill) > 0)
	assert_eq(roster.candidates()[0].growth_state().earned_today(skill), 0,
		"work by the copied hire cannot stage XP on the original candidate")
	assert_eq(roster.to_dict(), before, "hiring and editing the copied candidate cannot consume or edit the original pool")
	assert_eq(random.state, rng_state)


func test_server_clean_high_selects_real_floor_spot_before_real_dirty_table() -> void:
	var sim: RestaurantSim = _restaurant()
	var server: StaffAgent = _server(sim)
	var spot: Vector2i = server.cell
	assert_true(sim.cleanliness.try_spawn_at_departed_seat(spot))
	sim.clean_tasks.sync_spots()
	var clean: SimTask = sim.clean_tasks.task_for(spot)
	var table: PlacedItem = ShopBuilder.items_with_def(sim.world, &"table_2")[0]
	sim.kitchen.mark_table_dirty(table.id)
	var bus: SimTask = _task(sim.world, &"bus_table")
	assert_not_null(clean)
	assert_not_null(bus)
	var choices: StaffJobPriorities = server.job_priorities()
	assert_true(choices.set_priority(&"cleaning", StaffJobPriorities.Level.HIGH))
	assert_true(sim.apply_staff_job_priorities(server.member_id, choices))
	sim.world.advance()
	assert_eq(server.task, clean, "available High cleaning is picked before bussing")
	assert_eq(bus.state, SimTask.State.OPEN)
	assert_true(sim.kitchen.is_table_dirty(table.id), "selection alone does not bus the table")
	assert_true(sim.cleanliness.has_spot(spot), "selection alone does not clean the floor")


func test_service_change_preserves_real_bus_then_affects_next_pick_only() -> void:
	var sim: RestaurantSim = _restaurant()
	var server: StaffAgent = _server(sim)
	var table: PlacedItem = ShopBuilder.items_with_def(sim.world, &"table_2")[0]
	sim.kitchen.mark_table_dirty(table.id)
	sim.world.advance()
	var bus: SimTask = server.task
	assert_not_null(bus)
	if bus == null:
		return
	assert_eq(bus.kind, &"bus_table")
	sim.world.advance()
	var spot: Vector2i = server.cell
	assert_true(sim.cleanliness.try_spawn_at_departed_seat(spot))
	sim.clean_tasks.sync_spots()
	var path_before: Array[Vector2i] = server.path.duplicate()
	var step_before: int = server.step_index
	var progress_before: float = server.move_progress
	var work_before: float = server.work_left
	var held: Vector2i = server.get("_held_cell")
	var holder_before: int = table.reserved_by(held)
	assert_ne(held, SimGrid.NO_CELL, "the in-flight task has a real held table seat")
	assert_eq(holder_before, server.id)
	var choices: StaffJobPriorities = server.job_priorities()
	assert_true(choices.set_priority(&"bussing", StaffJobPriorities.Level.OFF))
	assert_true(choices.set_priority(&"cleaning", StaffJobPriorities.Level.HIGH))
	assert_true(sim.apply_staff_job_priorities(server.member_id, choices))
	assert_eq(server.task, bus)
	assert_eq(bus.state, SimTask.State.CLAIMED)
	assert_eq(server.path, path_before)
	assert_eq(server.step_index, step_before)
	assert_eq(server.move_progress, progress_before)
	assert_eq(server.work_left, work_before)
	assert_eq(table.reserved_by(held), holder_before)
	for _tick: int in range(500):
		sim.world.advance()
		if bus.state == SimTask.State.DONE:
			break
	assert_eq(bus.state, SimTask.State.DONE, "the original real bus task completes normally")
	assert_false(sim.kitchen.is_table_dirty(table.id))
	assert_null(server.task)
	sim.world.advance()
	assert_eq(server.task, sim.clean_tasks.task_for(spot), "the changed choice applies at the next claim")


func test_off_is_never_picked_and_high_washing_is_not_deferred_to_low_service() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var server: StaffAgent = _employee(world, &"server")
	var choices: StaffJobPriorities = server.job_priorities()
	assert_true(choices.set_priority(&"bussing", 0))
	assert_true(choices.set_priority(&"washing", 3))
	assert_true(choices.set_priority(&"serving", 1))
	assert_true(server.set_job_priorities(choices))
	var bus: SimTask = SimTask.new(&"bus_table", &"server", "Clear a table")
	bus.priority = 3
	var serving: SimTask = SimTask.new(&"deliver", &"server", "Deliver a meal")
	serving.priority = 3
	var washing: SimTask = SimTask.new(&"wash", &"server", "Wash plates")
	washing.priority = 0
	washing.defer_to_higher_priority = true
	for task: SimTask in [bus, serving, washing] as Array[SimTask]:
		task.steps.append(TaskStep.work(2, "working"))
		world.board.post(task, world.now)
	world.advance()
	assert_eq(server.task, washing)
	world.board.cancel(washing)
	world.advance()
	world.advance()
	assert_eq(server.task, serving)
	world.board.cancel(serving)
	world.advance()
	world.advance()
	assert_null(server.task)
	assert_eq(bus.state, SimTask.State.OPEN)


func test_equal_job_tiers_keep_existing_score_and_id_tie_order() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var server: StaffAgent = _employee(world, &"server")
	var first: SimTask = SimTask.new(&"bus_table", &"server", "First equal task")
	var second: SimTask = SimTask.new(&"wash", &"server", "Second equal task")
	world.board.post(first, world.now)
	world.board.post(second, world.now)
	world.advance()
	assert_eq(server.task, first, "equal old score keeps the earlier board ID")


func test_high_cleaning_still_respects_existing_dedicated_cleaner_capability_gate() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var server: StaffAgent = _employee(world, &"server")
	var cleaner: StaffAgent = _employee(world, &"cleaner")
	var choices: StaffJobPriorities = server.job_priorities()
	assert_true(choices.set_priority(&"cleaning", 3))
	assert_true(server.set_job_priorities(choices))
	var clean: SimTask = SimTask.new(&"clean_spot", &"cleaner", "Mop floor")
	clean.steps.append(TaskStep.go_to_cell(Vector2i(1, 1), "walking"))
	clean.steps.append(TaskStep.work(30, "mopping"))
	world.board.post(clean, world.now)
	world.advance()
	assert_null(server.task)
	assert_eq(cleaner.task, clean)


func test_priority_install_copies_state_and_rejects_wrong_role_without_mutation() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var server: StaffAgent = _employee(world, &"server")
	var choices: StaffJobPriorities = server.job_priorities()
	assert_true(choices.set_priority(&"cleaning", 3))
	assert_true(server.set_job_priorities(choices))
	assert_true(choices.set_priority(&"cleaning", 0))
	assert_eq(server.job_priorities().priority(&"cleaning"), 3)
	assert_false(server.set_job_priorities(StaffJobPriorities.new(&"cook")))
	assert_false(server.set_job_priorities(null))
	assert_eq(server.job_priorities().priority(&"cleaning"), 3)


func _member(role: StringName) -> StaffMember:
	var member: StaffMember = StaffMember.new()
	member.id = StringName("test_" + String(role))
	member.display_name = "Test employee"
	member.role = role
	member.wage = 30
	return member


func _employee(world: SimWorld, role: StringName) -> StaffAgent:
	var employee: StaffAgent = StaffAgent.new(role, 3)
	employee.configure_member(_member(role), StaffRoster.CATALOGUE.find_trait(&"steady"))
	world.add_agent(employee)
	return employee


func _restaurant() -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 82001, errors)
	assert_eq(errors, [] as Array[String])
	var rules: CleanlinessTuning = CLEANING.duplicate() as CleanlinessTuning
	rules.arrival_chance = 0.0
	rules.seat_departure_chance = 1.0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 82002
	assert_true(sim.configure_cleanliness(CleanlinessState.new(sim.world.grid, rules, random), rules))
	assert_true(sim.world.clock.start_service())
	return sim


func _server(sim: RestaurantSim) -> StaffAgent:
	for agent: SimAgent in sim.world.agents:
		if agent is StaffAgent and agent.role == &"server":
			return agent as StaffAgent
	return null


func _task(world: SimWorld, kind: StringName) -> SimTask:
	for task: SimTask in world.board.open_tasks():
		if task.kind == kind:
			return task
	return null
