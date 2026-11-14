extends TestCase
## Sending an employee to another of the owner's sites (FK-087 part 5, #473):
## pure roster rules, no world.

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")


## A roster of the starter cook and server plus `extra` people.
func _roster(extra: Array[Dictionary] = []) -> StaffRoster:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var data: Dictionary = roster.to_dict()
	for row: Dictionary in extra:
		(data["members"] as Array).append(row)
	var loaded: StaffRoster = StaffRoster.new(TUNING)
	assert_true(loaded.from_dict(JSON.parse_string(JSON.stringify(data))))
	return loaded


func _empty() -> StaffRoster:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	assert_true(roster.from_dict({"version": 1, "candidate_day": 0, "members": [], "candidates": []}))
	return roster


func _person(id: String, role: StringName, skill: int = 4, trait_id: StringName = &"careful") -> Dictionary:
	var member: StaffMember = StaffMember.new()
	member.id = StringName(id)
	member.display_name = id.capitalize()
	member.role = role
	member.skill = skill
	member.wage = TUNING.staff_wage(role, skill)
	member.trait_id = trait_id
	return member.to_dict()


func _ids(roster: StaffRoster) -> Array[StringName]:
	var ids: Array[StringName] = []
	for member: StaffMember in roster.members():
		ids.append(member.id)
	return ids


func _row(roster: StaffRoster, id: StringName) -> Dictionary:
	for row: Dictionary in roster.to_dict()["members"]:
		if row["id"] == String(id):
			return row
	return {}


func test_a_transfer_keeps_everything_about_the_person() -> void:
	var home: StaffRoster = _roster([_person("ana", &"cook", 4, &"careful")])
	# Some history: lifetime work, a priority choice and a lower mood.
	var data: Dictionary = home.to_dict()
	var ana: Dictionary = (data["members"] as Array)[2]
	ana["work"] = {"cooked": 12}
	ana["growth"]["mood"] = 2
	assert_true(home.from_dict(JSON.parse_string(JSON.stringify(data))))
	assert_true(home.set_job_priority(&"ana", &"cooking", StaffJobPriorities.Level.LOW))
	var before: Dictionary = _row(home, &"ana")
	var away: StaffRoster = _empty()
	var wages: int = home.total_wages()
	assert_eq(StaffTransfer.refusal(home, &"ana", away), StaffTransfer.Refusal.NONE)
	assert_eq(StaffTransfer.move(home, &"ana", away), &"ana")
	assert_eq(_ids(home), [&"starter_cook", &"starter_server"])
	assert_eq(_ids(away), [&"ana"])
	assert_eq(_row(away, &"ana"), before, "skill, trait, wage, mood, priorities and work all move")
	assert_eq(home.total_wages() + away.total_wages(), wages, "no fee, no severance, same pay")
	var reloaded: StaffRoster = StaffRoster.new(TUNING)
	assert_true(reloaded.from_dict(JSON.parse_string(JSON.stringify(away.to_dict()))))
	assert_eq(reloaded.to_dict(), away.to_dict(), "the destination's section saves and loads")


func test_the_last_cook_or_server_cannot_leave() -> void:
	var home: StaffRoster = _roster()
	var away: StaffRoster = _empty()
	var before: Dictionary = home.to_dict()
	for id: StringName in [&"starter_cook", &"starter_server"]:
		assert_false(home.can_let_go(id), "the same rule as letting go")
		assert_eq(StaffTransfer.refusal(home, id, away), StaffTransfer.Refusal.LAST_OF_ROLE)
		assert_eq(StaffTransfer.move(home, id, away), &"")
	assert_eq(home.to_dict(), before)
	assert_true(away.members().is_empty())
	# With a second cook, either cook may go, but not both.
	var two: StaffRoster = _roster([_person("bo", &"cook")])
	assert_eq(StaffTransfer.move(two, &"starter_cook", away), &"starter_cook")
	assert_eq(StaffTransfer.refusal(two, &"bo", away), StaffTransfer.Refusal.LAST_OF_ROLE)


func test_a_manager_moves_only_to_a_site_without_one() -> void:
	var home: StaffRoster = _roster([_person("mo", StaffMember.MANAGER)])
	var managed: StaffRoster = _roster([_person("di", StaffMember.MANAGER)])
	var unmanaged: StaffRoster = _roster()
	var before: Dictionary = home.to_dict()
	assert_eq(StaffTransfer.refusal(home, &"mo", managed), StaffTransfer.Refusal.HAS_MANAGER)
	assert_eq(StaffTransfer.move(home, &"mo", managed), &"")
	assert_eq(home.to_dict(), before)
	assert_eq(_ids(managed), [&"starter_cook", &"starter_server", &"di"])
	assert_eq(StaffTransfer.move(home, &"mo", unmanaged), &"mo")
	assert_true(StaffTransfer.has_manager(unmanaged))
	assert_false(StaffTransfer.has_manager(home))
	# Floor staff may join a site that has a manager.
	var cook: StaffRoster = _roster([_person("cy", &"cook")])
	assert_eq(StaffTransfer.refusal(cook, &"cy", managed), StaffTransfer.Refusal.NONE)


func test_a_full_site_takes_nobody() -> void:
	var extra: Array[Dictionary] = []
	for id: String in ["a", "b", "c", "d"]:
		extra.append(_person("full_" + id, &"cleaner"))
	var full: StaffRoster = _roster(extra)
	assert_eq(full.members().size(), StaffRoster.CAPACITY)
	var home: StaffRoster = _roster([_person("cy", &"cook")])
	assert_eq(StaffTransfer.refusal(home, &"cy", full), StaffTransfer.Refusal.FULL)
	assert_eq(StaffTransfer.move(home, &"cy", full), &"")
	assert_eq(_ids(home), [&"starter_cook", &"starter_server", &"cy"])


func test_unknown_people_and_missing_rosters_are_refused() -> void:
	var home: StaffRoster = _roster()
	assert_eq(StaffTransfer.refusal(home, &"nobody", _empty()), StaffTransfer.Refusal.UNKNOWN)
	assert_eq(StaffTransfer.refusal(home, &"starter_cook", null), StaffTransfer.Refusal.UNKNOWN)
	assert_eq(StaffTransfer.refusal(null, &"starter_cook", _empty()), StaffTransfer.Refusal.UNKNOWN)
	# A candidate is not an employee yet.
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 7
	assert_true(home.draw_candidates(1, random))
	assert_eq(StaffTransfer.refusal(home, home.candidates()[0].id, _empty()), StaffTransfer.Refusal.UNKNOWN)


func test_an_id_already_used_at_the_destination_gets_a_free_one() -> void:
	# Ids are unique only within one roster: both sites have a starter cook.
	var home: StaffRoster = _roster([_person("cy", &"cook")])
	var away: StaffRoster = _roster([_person("starter_cook_2", &"cleaner")])
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 7
	assert_true(away.draw_candidates(1, random))
	var name: String = home.members()[0].display_name
	assert_eq(StaffTransfer.move(home, &"starter_cook", away), &"starter_cook_3")
	assert_eq(_row(away, &"starter_cook_3")["name"], name)
	var reloaded: StaffRoster = StaffRoster.new(TUNING)
	assert_true(reloaded.from_dict(JSON.parse_string(JSON.stringify(away.to_dict()))),
		"no duplicate id among members and candidates")
	# A candidate's id is taken too.
	var candidate: StringName = away.candidates()[0].id
	assert_eq(StaffTransfer.arrival_id(away, candidate), StringName(String(candidate) + "_2"))
