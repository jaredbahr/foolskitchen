extends TestCase
## The real close raises the career tier (D30), the report announces it, Goals
## shows the next rung, and the tier joins the next morning autosave only.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "career_tier_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_close_raises_tier_announces_it_and_saves_next_morning() -> void:
	var main: Node = await _start(true)
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	assert_eq(owner.career_tier, 1)
	_show_goals(main)
	assert_eq(_goals_line(main), "Tier 1 → Tier 2: reach level 3")
	main.call("set_goals_visible", false)
	# Level 6 but only 3.0 stars: Tier 2 now, Tier 3 waits for the stars.
	owner.award_bonus(owner.threshold_for(6))
	var morning_file: String = _saved_text()
	_close_day(main)
	assert_eq(owner.career_tier, 2)
	assert_false(main.get("lease_expanded"), "the lease is untouched")
	var report: DayReport = main.get("shown_report") as DayReport
	assert_eq(report.career_tier_line, "Your restaurant reached Tier 2!")
	assert_eq(DayReport.from_dict(report.to_dict()).career_tier_line, report.career_tier_line)
	var line: Label = main.get_node("Overlay/EveningReport").get_node("%CareerTierUp") as Label
	assert_true(line.visible)
	assert_eq(line.text, "Your restaurant reached Tier 2!")
	assert_eq(_saved_text(), morning_file, "the close itself saves nothing")
	_show_goals(main)
	assert_eq(_goals_line(main), "Tier 2 → Tier 3: reach level 6 and 4.0 stars")
	main.call("set_goals_visible", false)
	assert_true(Clock.sim.next_day())
	assert_eq(int(_document()["data"]["owner"]["progress"]["career_tier"]), 2)
	# A good reputation reaches Tier 3 at the next close.
	assert_true((main.get("reputation") as ReputationBook).from_dict({"version": 1, "scores": [4, 4, 4, 4, 4]}))
	_close_day(main)
	assert_eq(owner.career_tier, 3)
	assert_eq((main.get("shown_report") as DayReport).career_tier_line, "Your restaurant reached Tier 3!")
	assert_true(Clock.sim.next_day())
	# A poor night never loses a tier, and announces nothing.
	assert_true((main.get("reputation") as ReputationBook).from_dict({"version": 1, "scores": [1, 1, 1, 1, 1]}))
	_close_day(main)
	assert_eq(owner.career_tier, 3)
	assert_eq((main.get("shown_report") as DayReport).career_tier_line, "")
	assert_false((main.get("shown_report") as DayReport).to_dict().has("career_tier_line"))
	assert_false(line.visible)
	assert_true(Clock.sim.next_day())
	var saved: Dictionary = owner.to_dict()
	_close(main)
	var second: Node = await _start(true)
	assert_eq((second.get("owner_progress") as OwnerProgress).to_dict(), saved, "save round trip")
	assert_eq((second.get("owner_progress") as OwnerProgress).career_tier, 3)


func test_tier_two_dish_opens_at_level_three_without_the_lease() -> void:
	var main: Node = await _start(false)
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var content: ContentDB = main.get("content")
	# Restore the cached definition before leaving this fixture.
	var recipe: RecipeDef = content.recipe(&"tomato_melt")
	var old_tier: int = recipe.unlock_tier
	recipe.unlock_tier = 2
	var menu: MenuSettings = main.get("menu_settings")
	main.call("_refresh_menu_catalogue")
	owner.award_bonus(owner.threshold_for(3))
	menu.set_owner_level(owner.level)
	main.call("_refresh_menu_catalogue")
	assert_null(menu.recipe(recipe.id), "level 3 alone waits for the close's Tier 2")
	_close_day(main)
	assert_eq([owner.career_tier, main.get("lease_expanded")], [2, false])
	assert_true((main.get("shown_report") as DayReport).owner_unlocks.has("Tomato melt recipe"),
		"the report names content the new tier opened")
	assert_true(Clock.sim.next_day())
	assert_true(menu.recipe(recipe.id) != null, "the morning menu offers the dish")
	assert_false(menu.is_enabled(recipe.id), "new food remains a player choice")
	assert_true(main.call("lease_refusal") != "Unlocks when your restaurant reaches Tier 2")
	recipe.unlock_tier = old_tier


func test_legacy_owner_section_loads_tier_from_the_lease() -> void:
	for expanded: bool in [false, true]:
		var first: Node = await _start(true)
		_close(first)
		var document: Dictionary = _document()
		var progress: Dictionary = document["data"]["owner"]["progress"]
		progress.erase("career_tier")
		# Saves from before #408 part 1 kept the lease on the owner only.
		document["data"]["shop"].erase("lease_expanded")
		if expanded:
			progress["property_tier"] = 2
		_write_document(document)
		var second: Node = await _start(true)
		var owner: OwnerProgress = second.get("owner_progress") as OwnerProgress
		assert_eq(owner.career_tier, 2 if expanded else 1)
		assert_eq(second.get("lease_expanded"), expanded, "the old owner lease is the site's own")
		_close(second)
		SaveSystem.delete_slot(SLOT)


func _start(saves: bool) -> Node:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 7)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _close_day(main: Node) -> void:
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	restaurant.spawner.min_gap = 100000
	restaurant.spawner.max_gap = 100000
	restaurant.start_day()
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)


func _show_goals(main: Node) -> void:
	assert_true(main.call("set_goals_visible", true))


func _goals_line(main: Node) -> String:
	var label: Label = main.get_node("Overlay/GoalsPanel").get_node("%CareerTier") as Label
	return label.text if label.visible else ""


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _document() -> Dictionary:
	return JSON.parse_string(_saved_text())


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_save_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
