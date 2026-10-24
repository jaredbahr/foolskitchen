extends TestCase
## Saved morning staffing choices; no world, autoload or filesystem required.

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const CATALOGUE: StaffCatalogue = preload("res://data/staff/traits.tres")


func test_defaults_keep_two_steady_skill_three_staff_and_detach_returned_choices() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var people: Array[StaffMember] = roster.members()
	assert_eq(people.size(), 2)
	assert_eq(people[0].role, &"cook")
	assert_eq(people[1].role, &"server")
	for member: StaffMember in people:
		assert_eq(member.skill, 3)
		assert_eq(member.trait_id, &"steady")
		assert_eq(member.wage, TUNING.wages[member.role])
	assert_eq(roster.total_wages(), TUNING.wages[&"cook"] + TUNING.wages[&"server"])
	assert_eq(roster.candidates().size(), 0)
	var before: Dictionary = roster.to_dict()
	people[0].wage = 99999
	people[0].display_name = "Changed copy"
	people.clear()
	assert_eq(roster.to_dict(), before, "panel copies cannot edit the saved roster")
	assert_ne(CATALOGUE.starters[0].display_name, "Changed copy")


func test_seeded_pool_is_repeatable_and_uses_the_role_skill_wage_curve() -> void:
	var first: StaffRoster = StaffRoster.new(TUNING)
	var repeated: StaffRoster = StaffRoster.new(TUNING)
	var first_rng: RandomNumberGenerator = _random(720072)
	var repeated_rng: RandomNumberGenerator = _random(720072)
	for day: int in [1, 2, 3]:
		assert_true(first.draw_candidates(day, first_rng))
		assert_true(repeated.draw_candidates(day, repeated_rng))
		assert_eq(first.to_dict(), repeated.to_dict())
		assert_eq(first_rng.state, repeated_rng.state)
		assert_eq(first.candidates().size(), 3)
		var ids: Dictionary[StringName, bool] = {}
		for member: StaffMember in first.candidates():
			assert_false(ids.has(member.id))
			ids[member.id] = true
			assert_true(member.role == &"cook" or member.role == &"server")
			assert_true(member.skill >= 1 and member.skill <= 5)
			assert_true(CATALOGUE.candidate_names.has(member.display_name))
			assert_not_null(CATALOGUE.find_trait(member.trait_id))
			assert_eq(member.wage, TUNING.staff_wage(member.role, member.skill))
		var copy: StaffMember = first.candidates()[0]
		copy.display_name = "Only a copy"
		assert_ne(first.candidates()[0].display_name, copy.display_name)
	assert_eq(TUNING.staff_wage(&"cook", 3), TUNING.wages[&"cook"])
	assert_true(TUNING.staff_wage(&"cook", 4) > TUNING.staff_wage(&"cook", 3))


func test_same_morning_refresh_after_hiring_preserves_pool_and_rng() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var random: RandomNumberGenerator = _random(720073)
	assert_true(roster.draw_candidates(4, random))
	var hired: StaffMember = roster.candidates()[0]
	assert_true(roster.hire(hired.id))
	var before: Dictionary = roster.to_dict()
	var state: int = random.state
	assert_true(roster.draw_candidates(4, random))
	assert_eq(roster.to_dict(), before, "reload/refresh cannot replace the two remaining candidates")
	assert_eq(random.state, state, "the same morning consumes no hiring draws")
	assert_false(roster.hire(hired.id), "a hired candidate cannot be hired twice")
	assert_false(roster.draw_candidates(3, random), "an earlier day cannot replace the pool")
	assert_eq(roster.to_dict(), before)
	assert_eq(random.state, state)


func test_json_roundtrip_keeps_hired_person_remaining_pool_and_same_day_rng() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var random: RandomNumberGenerator = _random(720074)
	assert_true(roster.draw_candidates(7, random))
	var hired: StaffMember = roster.candidates()[1]
	var wages_before: int = roster.total_wages()
	assert_true(roster.hire(hired.id))
	assert_eq(roster.total_wages(), wages_before + hired.wage)
	var saved: Dictionary = roster.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored: StaffRoster = StaffRoster.new(TUNING)
	assert_true(restored.from_dict(parsed), "JSON numbers are accepted without changing their meaning")
	assert_eq(restored.to_dict(), saved)
	assert_eq(restored.members().size(), 3)
	assert_eq(restored.candidates().size(), 2)
	assert_false(restored.can_hire(hired.id))
	var state: int = random.state
	assert_true(restored.draw_candidates(7, random))
	assert_eq(random.state, state)
	assert_eq(restored.to_dict(), saved)


func test_role_minimums_and_unknown_ids_refuse_without_changing_choices() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var original: Dictionary = roster.to_dict()
	for member: StaffMember in roster.members():
		assert_false(roster.can_let_go(member.id))
		assert_false(roster.let_go(member.id))
	assert_false(roster.hire(&"missing"))
	assert_false(roster.let_go(&"missing"))
	assert_eq(roster.to_dict(), original)
	assert_true(roster.draw_candidates(1, _random(720075)))
	var hire: StaffMember = roster.candidates()[0]
	assert_true(roster.hire(hire.id))
	var predecessor: StringName = &""
	for member: StaffMember in CATALOGUE.defaults(TUNING):
		if member.role == hire.role:
			predecessor = member.id
	assert_true(roster.let_go(predecessor), "a replacement permits the old person to leave")
	assert_false(roster.let_go(hire.id), "the replacement is now the last person of that role")
	assert_eq(roster.members().size(), 2)


func test_capacity_keeps_the_next_candidate_available_and_wages_exact() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var random: RandomNumberGenerator = _random(720076)
	var expected_wages: int = roster.total_wages()
	assert_true(roster.draw_candidates(1, random))
	for member: StaffMember in roster.candidates():
		expected_wages += member.wage
		assert_true(roster.hire(member.id))
	assert_eq(roster.members().size(), 5)
	assert_true(roster.draw_candidates(2, random))
	var last: StaffMember = roster.candidates()[0]
	expected_wages += last.wage
	assert_true(roster.hire(last.id))
	assert_eq(roster.members().size(), 6)
	assert_eq(roster.total_wages(), expected_wages)
	var refused: StaffMember = roster.candidates()[0]
	var full: Dictionary = roster.to_dict()
	assert_false(roster.can_hire(refused.id))
	assert_false(roster.hire(refused.id))
	assert_eq(roster.to_dict(), full, "capacity refusal neither hires nor consumes the candidate")


func test_invalid_decoder_is_atomic_for_roster_pool_and_day() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	assert_true(roster.draw_candidates(5, _random(720077)))
	assert_true(roster.hire(roster.candidates()[0].id))
	var before: Dictionary = roster.to_dict()
	var invalid: Array[Dictionary] = []
	var row: Dictionary = before.duplicate(true)
	row["version"] = 2
	invalid.append(row)
	row = before.duplicate(true)
	row["candidate_day"] = -1
	invalid.append(row)
	row = before.duplicate(true)
	row["candidate_day"] = 0
	invalid.append(row)
	row = before.duplicate(true)
	row["members"] = []
	invalid.append(row)
	row = before.duplicate(true)
	row["candidates"] = "not an array"
	invalid.append(row)
	row = before.duplicate(true)
	row["candidates"][0]["id"] = row["members"][0]["id"]
	invalid.append(row)
	row = before.duplicate(true)
	for employee: Dictionary in row["members"]:
		employee["role"] = "cook"
	invalid.append(row)
	for field: String in ["skill", "wage", "role", "trait", "id"]:
		row = before.duplicate(true)
		var bad: Dictionary = {"skill": 1.5, "wage": -1, "role": "owner", "trait": "unknown", "id": ""}
		row["members"][0][field] = bad[field]
		invalid.append(row)
	row = before.duplicate(true)
	row["candidates"][0].erase("name")
	invalid.append(row)
	row = before.duplicate(true)
	row["extra"] = true
	invalid.append(row)
	for document: Dictionary in invalid:
		assert_false(roster.from_dict(document))
		assert_eq(roster.to_dict(), before, "a rejected section leaves every live choice untouched")


func test_generated_ids_cannot_collide_with_a_person_restored_from_an_older_pool() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var saved: Dictionary = roster.to_dict()
	saved["members"][0]["id"] = "candidate_2_0"
	assert_true(roster.from_dict(saved))
	assert_true(roster.draw_candidates(2, _random(720078)))
	var seen: Dictionary[StringName, bool] = {}
	for member: StaffMember in roster.members() + roster.candidates():
		assert_false(seen.has(member.id))
		seen[member.id] = true
	assert_true(roster.hire(roster.candidates()[0].id))
	var restored: StaffRoster = StaffRoster.new(TUNING)
	assert_true(restored.from_dict(roster.to_dict()))
	assert_eq(restored.to_dict(), roster.to_dict())


func test_candidate_names_are_unique_and_skip_team_names_case_insensitively() -> void:
	var definitions: StaffCatalogue = CATALOGUE.duplicate(true) as StaffCatalogue
	definitions.candidate_names = PackedStringArray(["Alex", "Sam", "Robin", "robin", "Jamie", "Casey"])
	var roster: StaffRoster = StaffRoster.new(TUNING, definitions)
	assert_true(roster.draw_candidates(1, _random(720079)))
	var names: Dictionary[String, bool] = {}
	for member: StaffMember in roster.members():
		names[member.display_name.to_lower()] = true
	for member: StaffMember in roster.candidates():
		var key: String = member.display_name.to_lower()
		assert_false(names.has(key))
		names[key] = true
	assert_eq(roster.candidates().size(), 3)


func test_insufficient_unique_names_refuse_before_rng_or_model_changes() -> void:
	var definitions: StaffCatalogue = CATALOGUE.duplicate(true) as StaffCatalogue
	definitions.candidate_names = PackedStringArray(["Alex", "Sam", "Robin", "robin", " "])
	var roster: StaffRoster = StaffRoster.new(TUNING, definitions)
	var random: RandomNumberGenerator = _random(720080)
	var before: Dictionary = roster.to_dict()
	var state: int = random.state
	assert_false(roster.draw_candidates(1, random))
	assert_eq(random.state, state)
	assert_eq(roster.to_dict(), before)


func test_legacy_same_day_duplicate_names_stay_saved_without_rerolling() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var random: RandomNumberGenerator = _random(720081)
	assert_true(roster.draw_candidates(3, random))
	var legacy: Dictionary = roster.to_dict()
	legacy["candidates"][0]["name"] = "Alex"
	legacy["candidates"][1]["name"] = "Alex"
	assert_true(roster.from_dict(legacy))
	var state: int = random.state
	assert_true(roster.draw_candidates(3, random))
	assert_eq(roster.to_dict(), legacy, "new eligibility rules never rewrite a saved morning pool")
	assert_eq(random.state, state)
	assert_true(roster.draw_candidates(4, random))
	var names: Dictionary[String, bool] = {}
	for member: StaffMember in roster.members() + roster.candidates():
		assert_false(names.has(member.display_name.to_lower()))
		names[member.display_name.to_lower()] = true


func _random(seed: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	return random
