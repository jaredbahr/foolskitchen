extends TestCase
## Staff-section compatibility and detached progression across roster copies.

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const CATALOGUE: StaffCatalogue = preload("res://data/staff/traits.tres")
const GROWTH: StaffGrowthTuning = preload("res://data/balance/staff_growth.tres")


func test_roster_fixture_leaves_authored_task_xp_unchanged() -> void:
	var authored: Dictionary = GROWTH.task_xp.duplicate()
	var tuning: StaffGrowthTuning = _fast_tuning()
	tuning.task_xp[&"cook"] = 999
	tuning.task_xp[&"clean_spot"] = 999
	assert_eq(GROWTH.task_xp, authored, "roster fixtures cannot alter the shared pacing data")


func test_authored_starters_begin_with_final_wage_even_if_template_was_read() -> void:
	var definitions: StaffCatalogue = CATALOGUE.duplicate(true) as StaffCatalogue
	definitions.starters[0].to_dict()
	var roster: StaffRoster = StaffRoster.new(TUNING, definitions)
	assert_eq(roster.members()[0].growth_state().wage, TUNING.wages[&"cook"])
	assert_eq(roster.members()[0].growth_state().progress_xp(&"cooking"), 0)


func test_six_field_legacy_members_and_candidates_load_with_zero_xp_and_mood_three() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	assert_true(roster.draw_candidates(4, _random(89001)))
	var legacy: Dictionary = roster.to_dict()
	for records: Array in [legacy["members"], legacy["candidates"]]:
		for row: Dictionary in records:
			row.erase("growth")
			assert_eq(row.size(), 6)
	var restored: StaffRoster = StaffRoster.new(TUNING)
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(legacy))))
	for person: StaffMember in restored.members() + restored.candidates():
		assert_eq(person.growth_state().mood, 3)
		assert_eq(person.growth_state().wage, person.wage)
		assert_eq(person.growth_state().skill_level(StaffMember._primary_skill(person.role)), person.skill)
		for skill: StringName in StaffGrowth.SKILLS:
			assert_eq(person.growth_state().progress_xp(skill), 0)
	assert_eq(restored.candidate_day, 4)
	assert_eq(restored.candidates().size(), 3)


func test_completed_task_xp_is_staged_for_employee_only_and_applied_at_close() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	var cook_id: StringName = roster.members()[0].id
	for _index: int in range(4):
		assert_true(roster.record_completed_task(cook_id, &"cook"))
	assert_false(roster.record_completed_task(&"missing", &"cook"))
	assert_false(roster.record_completed_task(cook_id, &"not_a_task"))
	assert_eq(roster.members()[0].skill, 3, "service-time XP does not change today's skill")
	assert_eq(roster.members()[0].growth_state().earned_today(&"cooking"), 8)
	var wages_before: int = roster.total_wages()
	var raised: Dictionary = roster.close_growth_day()
	assert_eq(raised[cook_id], [{"skill": "cooking", "level": 4}])
	assert_eq(roster.members()[0].skill, 4)
	assert_eq(roster.members()[0].growth_state().pending_raise_count(), 1)
	assert_eq(roster.total_wages(), wages_before, "a skill-up never silently applies a raise")
	assert_eq(roster.close_growth_day(), {}, "a repeated close has no extra level or raise")


func test_secondary_cleaning_skill_speeds_next_shift_mopping_without_midday_change() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	var before: StaffMember = roster.members()[1]
	var live: StaffAgent = StaffAgent.new(before.role, before.skill)
	live.configure_member(before, CATALOGUE.find_trait(before.trait_id))
	live.priorities[&"server"] = 3
	var priorities: Dictionary[StringName, int] = live.priorities.duplicate()
	for _index: int in range(2):
		assert_true(roster.record_completed_task(before.id, &"clean_spot"))
	assert_eq(roster.members()[1].growth_state().skill_level(&"cleaning"), 1)
	var raised: Dictionary = roster.close_growth_day()
	assert_eq(raised[before.id], [{"skill": "cleaning", "level": 2}])
	assert_eq(live.skill_for(&"cleaner"), 1, "closing never changes the live shift")
	var after: StaffMember = roster.members()[1]
	assert_eq(after.skill, 3, "mopping does not level up service")
	live.configure_member(after, CATALOGUE.find_trait(after.trait_id))
	assert_eq(live.skill_for(&"cleaner"), 2)
	assert_eq(live.skill_for(&"server"), 3)
	assert_eq(live.priorities, priorities, "morning skill setup preserves role priorities")
	assert_almost_eq(live.work_speed(&"cleaner"), 0.6 + 0.1 * 2)
	assert_true(_mop_ticks(after) < _mop_ticks(before), "the earned skill completes real mop work sooner")
	var restored: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	assert_true(restored.from_dict(_json_copy(roster.to_dict())))
	assert_eq(restored.members()[1].growth_state().skill_level(&"cleaning"), 2)
	assert_eq(_mop_ticks(restored.members()[1]), _mop_ticks(after))


func test_secondary_skill_update_already_covered_by_pay_cannot_reduce_mood() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	var server: StaffMember = roster.members()[1]
	for _index: int in range(2):
		assert_true(roster.record_completed_task(server.id, &"clean_spot"))
	roster.close_growth_day()
	var offers: Array[Dictionary] = roster.morning_raise_offers(2, SimClock.Phase.MORNING)
	assert_eq(offers.size(), 1, "one skill-up still has exactly one morning acknowledgement")
	assert_false(bool(offers[0]["requires_raise"]))
	assert_eq(offers[0]["old_wage"], server.wage)
	assert_eq(offers[0]["new_wage"], server.wage)
	assert_true(String(offers[0]["message"]).contains("Their pay stays at"))
	assert_false(String(offers[0]["message"]).contains("They'd like"))
	assert_false(roster.decline_raise(server.id, 2, SimClock.Phase.MORNING))
	assert_eq(roster.members()[1].growth_state().mood, 3)
	assert_eq(roster.members()[1].growth_state().pending_raise_count(), 1)
	assert_eq(roster.morning_raise_offers(2, SimClock.Phase.MORNING), offers,
		"reading and refusing an informational update never consume it")
	assert_true(roster.accept_raise(server.id, SimClock.Phase.MORNING))
	assert_eq(roster.members()[1].wage, server.wage)
	assert_eq(roster.members()[1].growth_state().mood, 3)
	assert_eq(roster.morning_raise_offers(2, SimClock.Phase.MORNING), [])
	assert_false(roster.accept_raise(server.id, SimClock.Phase.MORNING))


func test_primary_skill_update_on_flat_wage_curve_is_an_acknowledgement() -> void:
	var economy: EconomyTuning = TUNING.duplicate() as EconomyTuning
	economy.staff_wage_curve = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0])
	var roster: StaffRoster = StaffRoster.new(economy, CATALOGUE, _fast_tuning())
	var cook: StaffMember = roster.members()[0]
	for _index: int in range(4):
		assert_true(roster.record_completed_task(cook.id, &"cook"))
	roster.close_growth_day()
	var offer: Dictionary = roster.morning_raise_offers(2, SimClock.Phase.MORNING)[0]
	assert_eq(offer["new_wage"], economy.staff_wage(&"cook", 4))
	assert_false(bool(offer["requires_raise"]))
	assert_false(roster.decline_raise(cook.id, 2, SimClock.Phase.MORNING))
	assert_eq(roster.members()[0].growth_state().mood, 3)
	assert_true(roster.accept_raise(cook.id, SimClock.Phase.MORNING))
	assert_eq(roster.members()[0].growth_state().pending_raise_count(), 0)


func test_cleaner_legacy_and_growth_saves_keep_optional_role_and_next_morning_quit() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	var saved: Dictionary = roster.to_dict()
	saved["members"].append({"id": "mop_1", "name": "Robin", "role": "cleaner",
		"skill": 1, "wage": TUNING.staff_wage(&"cleaner", 1), "trait": "steady"})
	assert_true(roster.from_dict(_json_copy(saved)), "legacy six-field cleaners receive growth defaults")
	assert_eq(roster.members()[2].growth_state().skill_level(&"cleaning"), 1)
	assert_eq(roster.members()[2].growth_state().mood, 3)
	assert_true(roster.can_let_go(&"mop_1"))
	assert_false(roster.can_let_go(&"starter_cook"))
	assert_false(roster.can_let_go(&"starter_server"))
	for _index: int in range(15):
		assert_true(roster.record_completed_task(&"mop_1", &"clean_spot"))
	roster.close_growth_day()
	assert_eq(roster.members()[2].skill, 5)
	for _index: int in range(3):
		assert_true(roster.decline_raise(&"mop_1", 2, SimClock.Phase.MORNING))
	var restored: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	assert_true(restored.from_dict(_json_copy(roster.to_dict())))
	assert_eq(restored.to_dict(), roster.to_dict())
	assert_eq(restored.process_morning_quits(2, SimClock.Phase.MORNING), [])
	var notices: Array[Dictionary] = restored.process_morning_quits(3, SimClock.Phase.MORNING)
	assert_eq(notices.size(), 1, "the last cleaner is optional and may leave")
	assert_eq(notices[0]["message"], "Robin left after their raise requests were refused.")
	assert_eq(restored.members().size(), 2)
	assert_eq(restored.process_morning_quits(3, SimClock.Phase.MORNING), [])


func test_returned_member_growth_is_deeply_detached_from_saved_roster() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	var before: Dictionary = roster.to_dict()
	var detached: StaffMember = roster.members()[0]
	assert_true(detached.growth_state().record_task(&"cook", _fast_tuning()))
	detached.growth_state().close_day(_fast_tuning())
	detached.display_name = "Changed copy"
	assert_eq(roster.to_dict(), before)
	assert_eq(roster.members()[0].growth_state().earned_today(&"cooking"), 0)


func test_growth_section_json_roundtrip_keeps_skill_raise_pool_and_day() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	assert_true(roster.draw_candidates(6, _random(89002)))
	var hired: StaffMember = roster.candidates()[0]
	assert_true(roster.hire(hired.id))
	var cook_id: StringName = roster.members()[0].id
	for _index: int in range(4):
		roster.record_completed_task(cook_id, &"cook")
	roster.close_growth_day()
	var saved: Dictionary = roster.to_dict()
	var restored: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(restored.to_dict(), saved)
	assert_eq(restored.candidate_day, 6)
	assert_eq(restored.members().size(), 3)
	assert_eq(restored.members()[0].growth_state().pending_raise_count(), 1)
	assert_eq(restored.members()[0].skill, 4)
	assert_eq(restored.total_wages(), roster.total_wages())


func test_malformed_growth_or_mismatched_outer_fields_leave_roster_untouched() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	assert_true(roster.draw_candidates(3, _random(89003)))
	var before: Dictionary = roster.to_dict()
	var invalid: Array[Dictionary] = []
	var row: Dictionary = _json_copy(before)
	row["members"][0]["growth"]["mood"] = 4
	invalid.append(row)
	row = _json_copy(before)
	row["members"][0]["growth"]["skills"]["cooking"] = 5
	invalid.append(row)
	row = _json_copy(before)
	row["members"][0]["growth"]["wage"] = 999
	invalid.append(row)
	row = _json_copy(before)
	row["members"][0]["growth"] = {"not": "a growth record"}
	invalid.append(row)
	row = _json_copy(before)
	row["members"][0].erase("growth")
	row["members"][0]["extra"] = true
	invalid.append(row)
	row = _json_copy(before)
	row["candidates"][0]["growth"]["xp"]["service"] = -1
	invalid.append(row)
	for document: Dictionary in invalid:
		assert_false(roster.from_dict(document))
		assert_eq(roster.to_dict(), before, "a bad nested member never replaces any live roster state")
		assert_eq(roster.candidate_day, 3)


func test_morning_offer_is_readable_stable_and_unavailable_while_open() -> void:
	var roster: StaffRoster = _roster_with_cook_raise()
	var cook_id: StringName = roster.members()[0].id
	assert_eq(roster.morning_raise_offers(2, SimClock.Phase.OPEN), [])
	assert_eq(roster.morning_raise_offers(2, SimClock.Phase.CLOSED), [])
	var offers: Array[Dictionary] = roster.morning_raise_offers(2, SimClock.Phase.MORNING)
	assert_eq(offers.size(), 1)
	assert_eq(offers[0]["member_id"], cook_id)
	assert_eq(offers[0]["old_wage"], 30)
	assert_eq(offers[0]["new_wage"], TUNING.staff_wage(&"cook", 4))
	assert_true(String(offers[0]["message"]).contains("Alex (Cook) got better at cooking"))
	assert_false(String(offers[0]["message"]).contains(String(cook_id)), "the notice never exposes an internal ID")
	assert_eq(roster.morning_raise_offers(2, SimClock.Phase.MORNING), offers)
	assert_eq(roster.members()[0].growth_state().pending_raise_count(), 1,
		"reading the panel twice cannot duplicate or consume an offer")


func test_accept_applies_only_this_morning_and_cannot_apply_twice() -> void:
	var roster: StaffRoster = _roster_with_cook_raise()
	var cook_id: StringName = roster.members()[0].id
	var before: int = roster.total_wages()
	assert_false(roster.accept_raise(cook_id, SimClock.Phase.CLOSED))
	assert_false(roster.accept_raise(&"missing", SimClock.Phase.MORNING))
	assert_eq(roster.total_wages(), before)
	assert_true(roster.accept_raise(cook_id, SimClock.Phase.MORNING))
	assert_eq(roster.members()[0].wage, TUNING.staff_wage(&"cook", 4))
	assert_eq(roster.members()[0].growth_state().wage, roster.members()[0].wage)
	assert_eq(roster.total_wages(), before - 30 + TUNING.staff_wage(&"cook", 4))
	assert_false(roster.accept_raise(cook_id, SimClock.Phase.MORNING))
	assert_eq(roster.morning_raise_offers(2, SimClock.Phase.MORNING), [])


func test_three_refusals_schedule_one_next_morning_departure_when_redundant() -> void:
	var roster: StaffRoster = _low_skill_cook_with_raises(true)
	var cook_id: StringName = &"starter_cook"
	var original_wage: int = roster.members()[0].wage
	assert_eq(roster.members()[0].growth_state().pending_raise_count(), 4)
	assert_false(roster.decline_raise(cook_id, 2, SimClock.Phase.OPEN))
	for mood_after: int in [2, 1, 0]:
		assert_true(roster.decline_raise(cook_id, 2, SimClock.Phase.MORNING))
		assert_eq(roster.members()[0].growth_state().mood, mood_after)
	assert_eq(roster.morning_raise_offers(2, SimClock.Phase.MORNING), [],
		"a scheduled departure hides any fourth queued offer")
	assert_false(roster.decline_raise(cook_id, 2, SimClock.Phase.MORNING))
	assert_false(roster.accept_raise(cook_id, SimClock.Phase.MORNING))
	assert_eq(roster.members()[0].wage, original_wage)
	assert_eq(roster.process_morning_quits(2, SimClock.Phase.MORNING), [],
		"a person never leaves during the morning they refuse")
	assert_eq(roster.morning_raise_offers(3, SimClock.Phase.MORNING), [],
		"due departure must be settled before another queued raise is shown")
	assert_false(roster.decline_raise(cook_id, 3, SimClock.Phase.MORNING),
		"a direct call cannot postpone the scheduled departure")
	assert_false(roster.accept_raise(cook_id, SimClock.Phase.MORNING),
		"a direct call cannot pay someone whose departure is due")
	assert_eq(roster.process_morning_quits(3, SimClock.Phase.OPEN), [])
	var notices: Array[Dictionary] = roster.process_morning_quits(3, SimClock.Phase.MORNING)
	assert_eq(notices.size(), 1)
	assert_eq(notices[0]["message"], "Alex left after their raise requests were refused.")
	assert_false(String(notices[0]["message"]).contains(String(cook_id)))
	assert_eq(roster.members().size(), 2)
	assert_eq(roster.process_morning_quits(3, SimClock.Phase.MORNING), [],
		"a departure notice cannot be replayed")


func test_last_cook_and_server_clamp_each_refusal_before_saving_or_morning() -> void:
	for role: StringName in [&"cook", &"server"]:
		var roster: StaffRoster = _low_skill_role_with_raises(role)
		var member_id: StringName = &"starter_cook" if role == &"cook" else &"starter_server"
		var index: int = 0 if role == &"cook" else 1
		var wage: int = roster.members()[index].wage
		var remaining: int = roster.members()[index].growth_state().pending_raise_count()
		for mood_after: int in [2, 1, 1, 1]:
			assert_true(roster.decline_raise(member_id, 4, SimClock.Phase.MORNING))
			remaining -= 1
			var protected_member: StaffMember = roster.members()[index]
			assert_eq(protected_member.growth_state().mood, mood_after,
				"the last worker never exposes mood zero after a refusal")
			assert_eq(protected_member.growth_state().quit_due_day(), 0)
			assert_eq(protected_member.growth_state().pending_raise_count(), remaining)
			assert_eq(protected_member.wage, wage)
			var restored: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
			assert_true(restored.from_dict(_json_copy(roster.to_dict())))
			assert_eq(restored.to_dict(), roster.to_dict(), "every immediate save is internally consistent")
		assert_eq(roster.process_morning_quits(4, SimClock.Phase.MORNING), [])
		assert_eq(roster.process_morning_quits(5, SimClock.Phase.MORNING), [])
		assert_eq(roster.members().size(), 2)
		assert_false(roster.decline_raise(member_id, 5, SimClock.Phase.MORNING))


func test_redundant_cook_and_server_still_schedule_departure_at_zero() -> void:
	for role: StringName in [&"cook", &"server"]:
		var roster: StaffRoster = _low_skill_role_with_raises(role)
		var index: int = 0 if role == &"cook" else 1
		var member_id: StringName = roster.members()[index].id
		var saved: Dictionary = roster.to_dict()
		saved["members"].append({"id": "backup", "name": "Robin", "role": String(role),
			"skill": 3, "wage": TUNING.staff_wage(role, 3), "trait": "steady"})
		assert_true(roster.from_dict(_json_copy(saved)))
		for mood_after: int in [2, 1, 0]:
			assert_true(roster.decline_raise(member_id, 4, SimClock.Phase.MORNING))
			assert_eq(roster.members()[index].growth_state().mood, mood_after)
		assert_eq(roster.members()[index].growth_state().quit_due_day(), 5)
		var restored: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
		assert_true(restored.from_dict(_json_copy(roster.to_dict())))
		assert_eq(restored.process_morning_quits(4, SimClock.Phase.MORNING), [])
		assert_eq(restored.process_morning_quits(5, SimClock.Phase.MORNING).size(), 1)
		assert_eq(restored.members().size(), 2)


func test_simultaneous_due_departures_keep_the_last_cook_and_server() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var saved: Dictionary = roster.to_dict()
	for role_index: int in range(2):
		var row: Dictionary = saved["members"][role_index]
		row["growth"]["mood"] = 0
		row["growth"]["quit_day"] = 3
		var backup: Dictionary = row.duplicate(true)
		backup["id"] = "backup_%d" % role_index
		backup["name"] = "Robin %d" % role_index
		saved["members"].append(backup)
	assert_true(roster.from_dict(_json_copy(saved)))
	var notices: Array[Dictionary] = roster.process_morning_quits(3, SimClock.Phase.MORNING)
	assert_eq(notices.size(), 4)
	assert_eq(roster.members().size(), 2)
	assert_eq(roster.members()[0].role, &"cook")
	assert_eq(roster.members()[1].role, &"server")
	for member: StaffMember in roster.members():
		assert_eq(member.growth_state().mood, 1)
		assert_eq(member.growth_state().quit_due_day(), 0)
	assert_eq(roster.process_morning_quits(3, SimClock.Phase.MORNING), [])


func test_legacy_six_field_load_starts_without_a_pending_raise_or_quit() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var legacy: Dictionary = roster.to_dict()
	for row: Dictionary in legacy["members"]:
		row.erase("growth")
	var restored: StaffRoster = StaffRoster.new(TUNING)
	assert_true(restored.from_dict(_json_copy(legacy)))
	assert_eq(restored.morning_raise_offers(1, SimClock.Phase.MORNING), [])
	assert_eq(restored.process_morning_quits(1, SimClock.Phase.MORNING), [])
	assert_eq(restored.total_wages(), roster.total_wages())


func _roster_with_cook_raise() -> StaffRoster:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	for _index: int in range(4):
		roster.record_completed_task(&"starter_cook", &"cook")
	roster.close_growth_day()
	return roster


func _low_skill_cook_with_raises(backup: bool) -> StaffRoster:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	var saved: Dictionary = roster.to_dict()
	var cook: Dictionary = saved["members"][0]
	cook["skill"] = 1
	cook["wage"] = TUNING.staff_wage(&"cook", 1)
	cook["growth"]["skills"]["cooking"] = 1
	cook["growth"]["wage"] = cook["wage"]
	if backup:
		var second: Dictionary = cook.duplicate(true)
		second["id"] = "backup_cook"
		second["name"] = "Robin"
		saved["members"].append(second)
	assert_true(roster.from_dict(_json_copy(saved)))
	for _index: int in range(15):
		assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	roster.close_growth_day()
	return roster


func _low_skill_role_with_raises(role: StringName) -> StaffRoster:
	if role == &"cook":
		return _low_skill_cook_with_raises(false)
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, _fast_tuning())
	var saved: Dictionary = roster.to_dict()
	var server: Dictionary = saved["members"][1]
	server["skill"] = 1
	server["wage"] = TUNING.staff_wage(&"server", 1)
	server["growth"]["skills"]["service"] = 1
	server["growth"]["wage"] = server["wage"]
	assert_true(roster.from_dict(_json_copy(saved)))
	for _index: int in range(30):
		assert_true(roster.record_completed_task(&"starter_server", &"deliver"))
	roster.close_growth_day()
	return roster


func _json_copy(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func _fast_tuning() -> StaffGrowthTuning:
	var tuning: StaffGrowthTuning = GROWTH.duplicate(true) as StaffGrowthTuning
	# Small mechanic fixtures stay independent of provisional production pacing.
	tuning.task_xp[&"cook"] = 2
	tuning.task_xp[&"clean_spot"] = 2
	tuning.next_level_xp = PackedInt32Array([4, 6, 8, 10])
	return tuning


func _mop_ticks(member: StaffMember) -> int:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["###", "#.#", "###"])))
	var server: StaffAgent = StaffAgent.new(member.role, member.skill)
	server.configure_member(member, CATALOGUE.find_trait(member.trait_id))
	server.cell = Vector2i(1, 1)
	world.add_agent(server)
	var task: SimTask = SimTask.new(&"clean_spot", &"cleaner", "Mop the floor")
	task.steps.append(TaskStep.work(30, "mopping"))
	world.board.post(task, world.now)
	for _index: int in range(100):
		world.advance()
		if task.state == SimTask.State.DONE:
			break
	assert_eq(task.state, SimTask.State.DONE)
	return world.now


func _random(seed: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	return random
