extends TestCase
## Roster-level priority persistence, including candidates and legacy rows.

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const CATALOGUE: StaffCatalogue = preload("res://data/staff/traits.tres")
const GROWTH: StaffGrowthTuning = preload("res://data/balance/staff_growth.tres")


func test_json_roundtrip_keeps_candidates_custom_priorities_and_queued_raise() -> void:
	var growth_rules: StaffGrowthTuning = _fast_growth_rules()
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, growth_rules)
	var hiring_rng: RandomNumberGenerator = _random(82011)
	assert_true(roster.draw_candidates(6, hiring_rng))
	var rng_state: int = hiring_rng.state

	assert_true(roster.set_job_priority(&"starter_cook", &"cooking", StaffJobPriorities.Level.LOW))
	assert_true(roster.set_job_priority(&"starter_server", &"washing", StaffJobPriorities.Level.OFF))
	assert_true(roster.set_job_priority(&"starter_server", &"cleaning", StaffJobPriorities.Level.HIGH))
	var detached_member: StaffMember = roster.members()[1]
	assert_true(detached_member.priority_state().set_priority(&"cleaning", StaffJobPriorities.Level.NORMAL))
	var detached_choices: StaffJobPriorities = roster.job_priorities(&"starter_server")
	assert_true(detached_choices.set_priority(&"cleaning", StaffJobPriorities.Level.LOW))
	assert_eq(roster.to_dict()["members"][1]["priorities"]["cleaning"],
		StaffJobPriorities.Level.HIGH, "returned member and choices cannot edit the saved roster")
	for _index: int in range(4):
		assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	var closed: Dictionary = roster.close_growth_day()
	assert_eq(closed[&"starter_cook"], [{"skill": "cooking", "level": 4}])
	assert_eq(roster.morning_raise_offers(2, SimClock.Phase.MORNING).size(), 1,
		"the saved state contains a real queued raise")

	var saved: Dictionary = roster.to_dict()
	var restored: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, growth_rules)
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(restored.to_dict(), saved,
		"IDs, names, traits, wages, growth, raise, priorities and candidate pool survive JSON")
	assert_eq(restored.candidate_day, 6)
	assert_eq(restored.candidates().size(), 3)
	assert_eq(restored.morning_raise_offers(2, SimClock.Phase.MORNING),
		roster.morning_raise_offers(2, SimClock.Phase.MORNING))
	assert_eq(hiring_rng.state, rng_state, "loading a roster consumes no hiring RNG")
	assert_true(restored.draw_candidates(saved["candidate_day"], hiring_rng),
		"refreshing an already saved candidate day succeeds")
	assert_eq(restored.to_dict(), saved, "same-day refresh preserves the restored pool and raise")
	assert_eq(hiring_rng.state, rng_state, "same-day refresh consumes no hiring RNG")


func test_employee_and_candidate_legacy_rows_get_role_defaults_with_or_without_growth() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE)
	assert_true(roster.draw_candidates(8, _random(82012)))
	var current: Dictionary = roster.to_dict()

	for keep_growth: bool in [true, false]:
		var legacy: Dictionary = _json_copy(current)
		for records: Array in [legacy["members"], legacy["candidates"]]:
			for row: Dictionary in records:
				row.erase("priorities")
				if not keep_growth:
					row.erase("growth")
				assert_eq(row.size(), 7 if keep_growth else 6)
		var restored: StaffRoster = StaffRoster.new(TUNING, CATALOGUE)
		assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(legacy))))
		assert_eq(restored.candidate_day, 8)
		assert_eq(restored.members().size(), 2)
		assert_eq(restored.candidates().size(), 3)
		_assert_identity_fields_preserved(current, restored.to_dict())
		for member: StaffMember in restored.members() + restored.candidates():
			assert_eq(member.priority_state().to_dict(), StaffJobPriorities.new(member.role).to_dict(),
				"a legacy candidate or employee receives exactly their role defaults")


func test_bad_candidate_priorities_reject_whole_roster_without_changing_raise_or_rng() -> void:
	var growth_rules: StaffGrowthTuning = _fast_growth_rules()
	var roster: StaffRoster = StaffRoster.new(TUNING, CATALOGUE, growth_rules)
	var hiring_rng: RandomNumberGenerator = _random(82013)
	assert_true(roster.draw_candidates(9, hiring_rng))
	assert_true(roster.set_job_priority(&"starter_server", &"cleaning", StaffJobPriorities.Level.HIGH))
	for _index: int in range(4):
		assert_true(roster.record_completed_task(&"starter_cook", &"cook"))
	roster.close_growth_day()
	var before: Dictionary = roster.to_dict()
	var rng_state: int = hiring_rng.state
	var candidate_role: StringName = StringName(before["candidates"][0]["role"])
	var unsupported: StringName = &""
	for job: StringName in StaffJobPriorities.JOBS:
		if not StaffJobPriorities.supports(candidate_role, job):
			unsupported = job
			break
	assert_false(unsupported.is_empty(), "each supported role has at least one unsupported job")

	var invalid: Array[Dictionary] = []
	var priorities: Dictionary = before["candidates"][0]["priorities"].duplicate(true)
	priorities.erase("bussing")
	invalid.append(priorities)
	priorities = before["candidates"][0]["priorities"].duplicate(true)
	priorities.erase("bussing")
	priorities["unknown_job"] = StaffJobPriorities.Level.NORMAL
	invalid.append(priorities)
	priorities = before["candidates"][0]["priorities"].duplicate(true)
	priorities.erase("bussing")
	priorities[5] = StaffJobPriorities.Level.NORMAL
	invalid.append(priorities)
	priorities = before["candidates"][0]["priorities"].duplicate(true)
	priorities["serving"] = "2"
	invalid.append(priorities)
	priorities = before["candidates"][0]["priorities"].duplicate(true)
	priorities["serving"] = true
	invalid.append(priorities)
	priorities = before["candidates"][0]["priorities"].duplicate(true)
	priorities["cooking"] = 4
	invalid.append(priorities)
	priorities = before["candidates"][0]["priorities"].duplicate(true)
	priorities[String(StaffJobPriorities.main_job(candidate_role))] = StaffJobPriorities.Level.OFF
	invalid.append(priorities)
	priorities = before["candidates"][0]["priorities"].duplicate(true)
	priorities[String(unsupported)] = StaffJobPriorities.Level.HIGH
	invalid.append(priorities)

	for bad_priorities: Dictionary in invalid:
		var document: Dictionary = _json_copy(before)
		document["members"][0]["name"] = "Must not install"
		document["candidates"][0]["priorities"] = bad_priorities
		assert_false(roster.from_dict(document))
		assert_eq(roster.to_dict(), before,
			"a rejected candidate row cannot replace employees, raises or other candidates")
		assert_eq(hiring_rng.state, rng_state)


func _assert_identity_fields_preserved(before: Dictionary, after: Dictionary) -> void:
	for key: String in ["members", "candidates"]:
		assert_eq(after[key].size(), before[key].size())
		for index: int in range(before[key].size()):
			for field: String in ["id", "name", "role", "skill", "wage", "trait"]:
				assert_eq(after[key][index][field], before[key][index][field])


func _fast_growth_rules() -> StaffGrowthTuning:
	var rules: StaffGrowthTuning = GROWTH.duplicate(true) as StaffGrowthTuning
	rules.task_xp[&"cook"] = 2
	rules.next_level_xp = PackedInt32Array([4, 6, 8, 10])
	return rules


func _json_copy(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func _random(seed: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	return random
