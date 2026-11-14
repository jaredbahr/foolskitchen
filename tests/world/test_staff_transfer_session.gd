extends TestCase
## Sending staff to another of the owner's restaurants in a real session
## (FK-087 part 5, #473): morning only, the frozen staff section, the site
## manager, the Staff panel, and the round trip through a switch and a save.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "staff_transfer_session"
const ECONOMY: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
var _main: Node
var _old_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _book() -> SiteBook:
	return _main.get("site_book")


func _roster() -> StaffRoster:
	return _main.get("staff_roster")


func _person(id: String, role: StringName, skill: int = 4) -> StaffMember:
	var member: StaffMember = StaffMember.new()
	member.id = StringName(id)
	member.display_name = id.capitalize()
	member.role = role
	member.skill = skill
	member.wage = ECONOMY.staff_wage(role, skill)
	member.trait_id = &"careful"
	return member


## Adds people to the live roster and installs them, as a hire would.
func _add_people(people: Array[StaffMember]) -> void:
	var data: Dictionary = _roster().to_dict()
	for member: StaffMember in people:
		(data["members"] as Array).append(member.to_dict())
	var roster: StaffRoster = StaffRoster.new(ECONOMY)
	assert_true(roster.from_dict(JSON.parse_string(JSON.stringify(data))))
	_main.set("staff_roster", roster)
	assert_true((_main.get("sim") as RestaurantSim).set_staff_roster(roster.members()))
	(_main.get_node("Overlay/StaffPanel") as StaffPanel).bind_roster(roster)


## A second site frozen this morning from the home site's sections, with
## `staff` as its team (an empty team, like a newly bought lot, by default).
func _second_site(staff: Array[StaffMember] = []) -> void:
	var sections: Dictionary = SaveSystem.capture_sections(SiteSections.PER_SITE)
	var team: Array = []
	for member: StaffMember in staff:
		team.append(member.to_dict())
	sections["staff"] = {"version": 1, "candidate_day": 0, "members": team, "candidates": []}
	assert_true(_book().add_site(&"second", &"second_lot", "Second", Clock.sim.day, sections))


func _frozen_ids(site: StringName) -> Array[StringName]:
	var roster: StaffRoster = StaffRoster.new(ECONOMY)
	assert_true(roster.from_dict(_book().frozen_sections(site)["staff"]))
	var ids: Array[StringName] = []
	for member: StaffMember in roster.members():
		ids.append(member.id)
	return ids


func _ids(roster: StaffRoster) -> Array[StringName]:
	var ids: Array[StringName] = []
	for member: StaffMember in roster.members():
		ids.append(member.id)
	return ids


func _live_staff(id: StringName) -> StaffAgent:
	for agent: SimAgent in (_main.get("world") as SimWorld).agents:
		if agent is StaffAgent and not agent is OwnerAgent and (agent as StaffAgent).member_id == id:
			return agent as StaffAgent
	return null


func test_a_cook_moves_and_works_at_the_new_site_after_a_switch_and_a_reload() -> void:
	_start()
	_add_people([_person("ana", &"cook")])
	_second_site()
	var cash: int = Economy.cash
	var before: Dictionary = {}
	for row: Dictionary in _roster().to_dict()["members"]:
		if row["id"] == "ana":
			before = row
	assert_true(_live_staff(&"ana") != null)
	assert_eq(_main.call("staff_transfer_refusal", &"ana", &"second"), StaffTransfer.Refusal.NONE)
	assert_true(_main.call("staff_transfer", &"ana", &"second"))
	assert_eq(Economy.cash, cash, "no fee and no severance")
	assert_eq(_ids(_roster()), [&"starter_cook", &"starter_server"])
	assert_null(_live_staff(&"ana"), "she has left this kitchen")
	assert_eq(_frozen_ids(&"second"), [&"ana"])
	assert_eq(_book().frozen_day(&"second"), Clock.sim.day, "the frozen day is kept")
	# The switch saves; the reload comes back at the second site.
	assert_true(_main.call("switch_site", &"second"))
	assert_eq(_ids(_roster()), [&"ana"])
	assert_true(_live_staff(&"ana") != null, "she works at the new site")
	assert_eq(_frozen_ids(SiteBook.HOME_ID), [&"starter_cook", &"starter_server"])
	_close()
	_start()
	assert_eq(_book().active_id, &"second")
	assert_eq(_ids(_roster()), [&"ana"])
	assert_true(_live_staff(&"ana") != null)
	var after: Dictionary = _roster().to_dict()["members"][0]
	assert_eq(after, before, "skill, trait, wage, mood and history survive the save")
	assert_eq(_frozen_ids(SiteBook.HOME_ID), [&"starter_cook", &"starter_server"])


func test_a_transfer_rides_the_next_morning_save() -> void:
	_start()
	_add_people([_person("ana", &"cook"), _person("cy", &"cleaner")])
	_second_site()
	assert_true(_main.call("staff_transfer", &"cy", &"second"))
	# The ordinary morning autosave (rule 9) writes both sites.
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")
	_close()
	_start()
	assert_eq(_book().active_id, SiteBook.HOME_ID)
	assert_false(_ids(_roster()).has(&"cy"))
	assert_true(_ids(_roster()).has(&"ana"))
	assert_eq(_frozen_ids(&"second"), [&"cy"])


func test_refusals_keep_the_last_cook_and_server_and_stay_in_the_morning() -> void:
	_start()
	_add_people([_person("cy", &"cleaner")])
	_second_site()
	var before: Dictionary = _roster().to_dict()
	for id: StringName in [&"starter_cook", &"starter_server"]:
		assert_eq(_main.call("staff_transfer_refusal", id, &"second"), StaffTransfer.Refusal.LAST_OF_ROLE)
		assert_false(_main.call("staff_transfer", id, &"second"))
	assert_false(_main.call("staff_transfer", &"cy", SiteBook.HOME_ID), "not to the site you are at")
	assert_false(_main.call("staff_transfer", &"cy", &"nowhere"))
	assert_false(_main.call("staff_transfer", &"nobody", &"second"))
	assert_eq(_roster().to_dict(), before)
	assert_eq(_frozen_ids(&"second"), [])
	assert_true(Clock.sim.start_service())
	assert_eq(_main.call("staff_transfer_refusal", &"cy", &"second"), StaffTransfer.Refusal.UNKNOWN)
	assert_false(_main.call("staff_transfer", &"cy", &"second"), "never mid-service")
	assert_eq(_roster().to_dict()["members"].size(), 3)


func test_a_manager_runs_the_site_they_move_to_and_only_one_without_a_manager() -> void:
	_start()
	_add_people([_person("mo", StaffMember.MANAGER, 3)])
	assert_true(_main.call("assign_site_manager", &"mo"))
	_second_site([_person("di", StaffMember.MANAGER), _person("starter_cook", &"cook")])
	assert_true(_book().add_site(&"third", &"third_lot", "Third", Clock.sim.day,
		{"staff": {"version": 1, "candidate_day": 0, "members": [], "candidates": []}}))
	assert_eq(_main.call("staff_transfer_refusal", &"mo", &"second"), StaffTransfer.Refusal.HAS_MANAGER)
	assert_false(_main.call("staff_transfer", &"mo", &"second"))
	assert_eq(_main.call("site_manager"), &"mo")
	assert_true(_main.call("staff_transfer", &"mo", &"third"))
	assert_eq(_main.call("site_manager"), &"", "the departing site has no manager now")
	assert_eq(_book().manager(&"third"), &"mo", "they run the site they moved to")
	assert_eq(_frozen_ids(&"third"), [&"mo"])
	# Floor staff may join a site that has a manager; a clashing id is renamed.
	_add_people([_person("bo", &"cook")])
	assert_true(_main.call("staff_transfer", &"starter_cook", &"second"))
	assert_eq(_frozen_ids(&"second"), [&"di", &"starter_cook", &"starter_cook_2"])


func test_the_staff_panel_lists_the_other_sites_with_reasons() -> void:
	_start()
	var panel: StaffPanel = _main.get_node("Overlay/StaffPanel") as StaffPanel
	assert_true(_main.call("set_staff_visible", true))
	var cook_row: Control = panel.row_for(&"starter_cook")
	assert_false((cook_row.get_node("Top/Transfer") as MenuButton).visible, "one site: no Send to")
	assert_true(_main.call("set_staff_visible", false))
	_add_people([_person("ana", &"cook"), _person("mo", StaffMember.MANAGER, 3)])
	_second_site([_person("di", StaffMember.MANAGER)])
	assert_true(_main.call("set_staff_visible", true))
	var send: MenuButton = panel.row_for(&"ana").get_node("Top/Transfer") as MenuButton
	assert_true(send.visible)
	assert_false(send.disabled)
	assert_eq(send.text, "Send to…")
	assert_eq(send.get_popup().item_count, 1)
	assert_eq(send.get_popup().get_item_text(0), "Second")
	assert_false(send.get_popup().is_item_disabled(0))
	var manager: MenuButton = panel.row_for(&"mo").get_node("Top/Transfer") as MenuButton
	assert_eq(manager.get_popup().get_item_text(0), "Second (already has a manager)")
	assert_true(manager.get_popup().is_item_disabled(0))
	# Two cooks, one server: the server's button is locked, as Let go is.
	var starter: MenuButton = panel.row_for(&"starter_server").get_node("Top/Transfer") as MenuButton
	assert_true(starter.disabled, "the last server stays")
	assert_eq(starter.tooltip_text, "Keep at least one cook and one server here.")
	# Picking the site sends the request; the panel then shows the new team.
	send.get_popup().id_pressed.emit(0)
	assert_eq(_frozen_ids(&"second"), [&"di", &"ana"])
	assert_false(_ids(_roster()).has(&"ana"))
	assert_true((panel.row_for(&"starter_cook").get_node("Top/Transfer") as MenuButton).disabled,
		"now the last cook")
	assert_true(Clock.sim.start_service())
	assert_true(_main.call("set_staff_visible", true))
	assert_true((panel.row_for(&"starter_cook").get_node("Top/Transfer") as MenuButton).disabled)
	assert_eq((panel.row_for(&"starter_cook").get_node("Top/Transfer") as MenuButton).tooltip_text,
		StaffPanel.MORNING_HINT)
