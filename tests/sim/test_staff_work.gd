extends TestCase
## Work counts use real roster entry points; XP and staffing policies stay separate.

func test_each_completed_kind_uses_one_group_without_changing_xp_or_wages() -> void:
	var roster: StaffRoster = StaffRoster.new()
	var wages: int = roster.total_wages()
	for kind: StringName in [&"cook", &"take_order", &"deliver", &"bus_table", &"wash", &"pour", &"clean_spot", &"degrease"]:
		assert_true(roster.record_completed_task(&"starter_cook", kind))
	assert_false(roster.record_completed_task(&"starter_cook", &"not_a_task"))
	assert_false(roster.record_completed_task(&"not_an_employee", &"cook"))
	var member: StaffMember = roster.members()[0]
	assert_eq(member.work_today(), {"cooked": 1, "orders": 1, "served": 1, "cleared": 1, "washed": 1, "other": 4})
	assert_eq(member.work_total(), member.work_today())
	assert_eq(member.growth_state().earned_today(&"cooking"), 3)
	assert_eq(member.growth_state().earned_today(&"service"), 5)
	assert_eq(member.growth_state().earned_today(&"cleaning"), 16)
	assert_eq(member.skill, 3)
	assert_eq(roster.total_wages(), wages)
	assert_true(member.work_summary().contains("1 order taken"))
	member.record_completed_work(&"take_order")
	assert_true(member.work_summary().contains("2 orders taken"))
	assert_false(member.work_summary().contains("take_order"))
	assert_eq(roster.members()[1].work_total()["cooked"], 0)


func test_new_morning_clears_today_once_while_copies_preserve_the_guard() -> void:
	var roster: StaffRoster = StaffRoster.new()
	assert_eq(roster.process_morning_quits(4, SimClock.Phase.MORNING), [])
	assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	var staged: StaffRoster = roster.copy()
	for candidate: StaffRoster in [roster, staged]:
		assert_eq(candidate.process_morning_quits(5, SimClock.Phase.OPEN), [])
		assert_eq(candidate.process_morning_quits(3, SimClock.Phase.MORNING), [])
		assert_eq(candidate.process_morning_quits(4, SimClock.Phase.MORNING), [])
		assert_eq(candidate.members()[0].work_today()["cooked"], 1)
	assert_eq(roster.process_morning_quits(5, SimClock.Phase.MORNING), [])
	assert_eq(roster.members()[0].work_today()["cooked"], 0)
	assert_eq(roster.members()[0].work_total()["cooked"], 1)
	assert_eq(staged.members()[0].work_today()["cooked"], 1)
	assert_eq(roster.members()[0].growth_state().earned_today(&"cooking"), 3,
		"daily display reset does not flush or clear staged XP")


func test_work_getters_runtime_copies_and_saved_snapshots_never_alias() -> void:
	var roster: StaffRoster = StaffRoster.new()
	assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	var returned: StaffMember = roster.members()[0]
	var counts: Dictionary = returned.work_today()
	counts["cooked"] = 900
	assert_eq(returned.work_today()["cooked"], 1)
	returned.record_completed_work(&"cook")
	assert_eq(roster.members()[0].work_today()["cooked"], 1)
	var staged: StaffRoster = roster.copy()
	assert_true(staged.record_completed_task(&"starter_cook", &"cook"))
	assert_eq(staged.members()[0].work_total()["cooked"], 2)
	assert_eq(roster.members()[0].work_total()["cooked"], 1)
	var saved: Dictionary = roster.to_dict()
	saved["members"][0]["work"]["cooked"] = 900
	assert_eq(roster.members()[0].work_total()["cooked"], 1)


func test_lifetime_survives_json_while_today_and_legacy_records_start_empty() -> void:
	var roster: StaffRoster = StaffRoster.new()
	assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	var saved: Dictionary = roster.to_dict()
	var restored: StaffRoster = StaffRoster.new()
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(restored.to_dict(), saved)
	assert_eq(restored.members()[0].work_total()["cooked"], 1)
	assert_eq(restored.members()[0].work_today()["cooked"], 0)
	for rows: Array in [saved["members"], saved["candidates"]]:
		for row: Dictionary in rows:
			row.erase("work")
	var legacy: StaffRoster = StaffRoster.new()
	assert_true(legacy.from_dict(JSON.parse_string(JSON.stringify(saved))))
	for member: StaffMember in legacy.members():
		for count: int in member.work_total().values():
			assert_eq(count, 0)


func test_bad_work_counts_reject_the_whole_roster_without_clearing_today() -> void:
	var roster: StaffRoster = StaffRoster.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 35101
	assert_true(roster.draw_candidates(4, random))
	assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	var before: Dictionary = roster.to_dict()
	var today: Dictionary = roster.members()[0].work_today()
	var rng_state: int = random.state
	for invalid: Variant in [true, -1, 1.5, INF, NAN, "3", StaffMember.MAX_WORK_COUNT + 1]:
		var document: Dictionary = before.duplicate(true)
		document["members"][0]["name"] = "Must not install"
		document["candidates"][0]["work"]["washed"] = invalid
		assert_false(roster.from_dict(document))
		assert_eq(roster.to_dict(), before)
		assert_eq(roster.members()[0].work_today(), today)
	var wrong_keys: Dictionary = before.duplicate(true)
	wrong_keys["members"][0]["work"].erase("washed")
	wrong_keys["members"][0]["work"]["unknown"] = 0
	assert_false(roster.from_dict(wrong_keys))
	assert_eq(roster.to_dict(), before)
	assert_eq(random.state, rng_state)


func test_work_count_cap_does_not_suppress_earned_xp() -> void:
	var roster: StaffRoster = StaffRoster.new()
	var saved: Dictionary = roster.to_dict()
	saved["members"][0]["work"]["cooked"] = StaffMember.MAX_WORK_COUNT
	assert_true(roster.from_dict(saved))
	assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	assert_eq(roster.members()[0].work_total()["cooked"], StaffMember.MAX_WORK_COUNT)
	assert_eq(roster.members()[0].work_today()["cooked"], 1)
	assert_eq(roster.members()[0].growth_state().earned_today(&"cooking"), 3)
