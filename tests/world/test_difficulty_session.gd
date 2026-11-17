extends TestCase
## Verify the career settings and stock rules through the live session.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "autosave"
const STAFF_TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")

var _main: Node
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary
var _old_clock: SimClock
var _clock_processed: bool
var _old_morning_paper: bool


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "difficulty_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_providers = SaveSystem._providers.duplicate()
	_old_clock = Clock.sim
	_clock_processed = Clock.is_processing()
	_old_morning_paper = Preferences.morning_paper_enabled
	Preferences.morning_paper_enabled = true
	Clock.set_process(false)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _old_providers
	Clock.sim = _old_clock
	Clock.set_speed(0)
	Clock.set_process(_clock_processed)
	Preferences.morning_paper_enabled = _old_morning_paper
	GameMode.request_new_game(false)
	GameMode.set_creative(false)
	Economy.reset(0)
	GameState.new_run(1)


func test_settings_change_applies_before_next_morning_and_survives_continue() -> void:
	_start()
	assert_true(_main.call("set_settings_visible", true))
	var settings: SettingsPanel = _main.get_node("Overlay/SettingsPanel") as SettingsPanel
	var choice: OptionButton = settings.get_node("%DifficultyChoice") as OptionButton
	var note: Label = settings.get_node("%DifficultySchedule") as Label
	var buy: CheckButton = settings.get_node("%AutoBuy") as CheckButton
	var premium: CheckButton = settings.get_node("%AutoBuyPremium") as CheckButton
	var tag: Label = _main.get_node("HUD/Top/Row/Difficulty") as Label
	assert_eq(Difficulty.MODES[choice.selected], &"normal")
	assert_false(tag.visible)
	assert_false(buy.visible)
	choice.item_selected.emit(Difficulty.MODES.find(&"custom"))
	assert_true(buy.visible)
	assert_true(premium.visible)
	premium.button_pressed = false
	assert_eq(note.text, "From tomorrow: Custom (today: Normal)")
	assert_eq(_difficulty().mode(), &"normal")
	assert_true(_difficulty().auto(&"buy_premium"))
	assert_false(tag.visible)
	assert_true(_main.call("set_settings_visible", false))
	_finish_service()
	assert_true(Clock.sim.next_day())
	assert_eq(_difficulty().mode(), &"custom")
	assert_true(_difficulty().auto(&"buy"))
	assert_false(_difficulty().auto(&"buy_premium"))
	assert_eq(_difficulty().pending_mode(), &"")
	assert_true(tag.visible)
	assert_eq(tag.text, "Custom")
	_close()
	_start()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_difficulty().mode(), &"custom")
	assert_false(_difficulty().auto(&"buy_premium"))


func test_hard_hides_standing_orders_and_charges_higher_rent() -> void:
	_start(&"hard")
	assert_true(_main.call("set_stock_visible", true))
	var stock: Control = _main.get_node("Overlay/StockPanel") as Control
	var rows: Array = _main.call("stock_rows")
	var id: StringName = rows[0]["id"]
	var row: Dictionary = stock.call("row_for", id)
	assert_false((row["auto"] as Button).visible)
	assert_false((row["reorder"] as HBoxContainer).visible)
	assert_false(_main.call("stock_set_auto", id, true))
	assert_true(_main.call("stock_cart_set", id, 1))
	assert_true(_main.call("stock_place_order"))
	assert_true(_main.call("set_stock_visible", false))
	_finish_service()
	assert_eq(int(Economy.ledger.day_totals(1)[Ledger.RENT]), -roundi(_main.call("_home_rent") * 1.1))
	assert_true(Clock.sim.next_day())
	for entry: Dictionary in Economy.ledger.entries_for_day(2):
		assert_false(String(entry["note"]).begins_with("auto_reorder"))


func test_easy_forces_auto_buy_without_rewriting_saved_ingredient_preferences() -> void:
	_start()
	var rows: Array = _main.call("stock_rows")
	var id: StringName = rows[0]["id"]
	assert_true(_main.call("stock_set_auto", id, false))
	assert_true(_difficulty().request_change(&"easy", {}, 2))
	_finish_service()
	assert_true(Clock.sim.next_day())
	assert_true((_main.call("_reorder") as ReorderSettings).is_enabled(id))
	assert_false((_main.get("reorder_settings") as ReorderSettings).is_enabled(id))
	assert_false(_main.call("stock_set_auto", id, false))
	assert_eq(_main.call("_reorder_premium"), 0.0)
	var replenished: bool = false
	for entry: Dictionary in Economy.ledger.entries_for_day(2):
		var note: String = entry["note"]
		assert_ne(note, "auto_reorder_premium")
		replenished = replenished or note.begins_with("auto_reorder:")
	assert_true(replenished, "Easy used the real morning standing order")


func test_save_without_difficulty_section_loads_normal() -> void:
	_start(&"easy")
	_close()
	var path: String = _save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true((document["data"] as Dictionary).erase("difficulty"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_start()
	assert_eq(_difficulty().mode(), &"normal")
	assert_true(_difficulty().auto(&"buy_premium"))
	assert_false((_main.get_node("HUD/Top/Row/Difficulty") as Label).visible)


func test_easy_fills_one_missing_role_per_morning_and_does_not_rehire_on_load() -> void:
	_start(&"easy")
	_stage_staff([])
	_next_staff_morning()
	var hired: Array[StaffMember] = _roster().members()
	assert_eq(hired.size(), 1)
	if hired.size() != 1:
		return
	assert_eq(hired[0].role, &"cook")
	assert_true(_paper_notes().contains("Hired %s (cook) because the shop needed a cook." % hired[0].display_name))
	var saved: Dictionary = _roster().to_dict()
	_main.call("_begin_morning")
	assert_eq(_roster().to_dict(), saved)
	_close()
	_start()
	assert_eq(_difficulty().mode(), &"easy")
	assert_eq(_roster().to_dict(), saved, "same-day reload retains the hire and the remaining offers")
	_next_staff_morning()
	assert_eq(_roster().members().size(), 2)
	assert_true(_roster().missing_service_roles().is_empty())


func test_normal_leaves_open_roles_to_the_player() -> void:
	_start()
	_stage_staff([])
	_next_staff_morning()
	assert_eq(_roster().members().size(), 0)
	assert_eq(_roster().candidates().size(), StaffRoster.CANDIDATE_COUNT)
	assert_false(_paper_notes().contains("Hired "))


func test_easy_adds_a_bottleneck_role_only_with_cash_for_the_wage_reserve() -> void:
	_start(&"easy")
	Economy.reset(0)
	_stage_cook_bottleneck()
	_next_staff_morning()
	var cook_offered: bool = false
	for candidate: StaffMember in _roster().candidates():
		cook_offered = cook_offered or candidate.role == &"cook"
	assert_true(cook_offered, "the low-cash case must have a cook to turn down")
	assert_eq(_roster().members().size(), 2)
	assert_false(_paper_notes().contains("Hired "))

	Economy.reset(1000)
	_stage_cook_bottleneck()
	_next_staff_morning()
	var hired: Array[StaffMember] = _roster().members()
	assert_eq(hired.size(), 3)
	if hired.size() != 3:
		return
	assert_eq(hired[2].role, &"cook")
	assert_true(Economy.cash >= 5 * hired[2].wage)
	assert_true(_paper_notes().contains("Hired %s (cook) because guests were waiting for the kitchen." \
		% hired[2].display_name))


func test_easy_replaces_a_quitter_even_when_their_role_is_still_covered() -> void:
	_start(&"easy")
	var members: Array = _roster().to_dict()["members"]
	var departing: Dictionary = members[0].duplicate(true)
	departing["id"] = "departing_cook"
	departing["name"] = "Toby"
	departing["growth"]["quit_day"] = 2
	departing["growth"]["mood"] = 0
	members.append(departing)
	_stage_staff(members)
	_next_staff_morning()
	var hired: Array[StaffMember] = _roster().members()
	assert_eq(hired.size(), 3)
	assert_false(_roster().has_id(&"departing_cook"))
	if hired.size() != 3:
		return
	assert_eq(hired[0].id, &"starter_cook")
	assert_eq(hired[1].id, &"starter_server")
	assert_eq(hired[2].role, &"cook")
	assert_true(_paper_notes().contains("Hired %s (cook) because a teammate left." % hired[2].display_name))


func _stage_staff(members: Array) -> void:
	var choices: StaffRoster = StaffRoster.new(STAFF_TUNING)
	var document: Dictionary = _roster().to_dict()
	document["members"] = members
	assert_true(choices.from_dict(document))
	assert_true((_main.get("sim") as RestaurantSim).set_staff_roster(choices.members()))
	_main.set("staff_roster", choices)


func _stage_cook_bottleneck() -> void:
	var report: DayReport = DayReport.new()
	report.day = Clock.sim.day
	report.staff_activity = {"day": report.day, "open_ticks": 1000, "roles": {
		"cook": {"busy_ticks": 950, "open_ticks": 1000},
	}}
	report.leave_reasons = {&"waited_too_long": 2}
	_main.set("shown_report", report)


func _next_staff_morning() -> void:
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())


func _roster() -> StaffRoster:
	return _main.get("staff_roster") as StaffRoster


func _paper_notes() -> String:
	return (_main.get_node("Overlay/MorningPaper/%Notes") as Label).text
func test_automatic_prices_lock_charges_without_locking_the_menu() -> void:
	_start()
	var menu: MenuSettings = _main.get("menu_settings") as MenuSettings
	var burger: RecipeDef = menu.recipe(&"burger")
	var standard: int = burger.standard_price
	assert_true(_main.call("menu_set_price", burger.id, standard + 2))
	assert_true(_main.call("menu_set_enabled", &"grilled_cheese", false))
	var presets: MenuPresetLibrary = _main.get("menu_presets") as MenuPresetLibrary
	assert_true(presets.save_menu("Alternate menu", menu))
	assert_true(_main.call("menu_set_enabled", &"grilled_cheese", true))
	var flags: Dictionary = Difficulty.DEFAULT_CUSTOM_FLAGS.duplicate()
	flags[&"prices"] = true
	assert_true(_difficulty().request_change(&"custom", flags, 2))
	assert_eq(menu.price_of(burger), standard + 2, "queued automation leaves today's prices alone")
	_finish_service()
	assert_true(Clock.sim.next_day())
	assert_false(_difficulty().auto(&"jobs"), "the Custom flags are independent")
	for recipe: RecipeDef in menu.recipes():
		assert_eq(menu.price_of(recipe), recipe.standard_price)
	assert_false(_main.call("menu_set_price", burger.id, standard + 1))
	assert_false(_main.call("menu_reset_prices"))
	assert_true(_main.call("set_menu_visible", true))
	var panel: MenuPanel = _main.get_node("Overlay/MenuPanel") as MenuPanel
	var row: Control = panel.row_for(burger.id)
	for action: String in ["Plus", "Minus"]:
		var button: Button = row.get_node("Price/" + action) as Button
		assert_true(button.disabled)
		assert_false(button.visible, "locked controls leave room for the price label")
	assert_eq((row.get_node("Price/Amount") as Label).text, "$%d · Standard price (auto)" % standard)
	for action: String in ["PlusTen", "MinusTen", "Reset"]:
		var button: Button = panel.get_node("%List/BulkPrices/" + action) as Button
		assert_true(button.disabled)
		assert_false(button.visible)
	assert_true(_main.call("set_menu_visible", false))
	var result: Dictionary = _main.call("menu_load_preset", 0)
	assert_true(bool(result.get("enabled_changed", false)))
	assert_false(menu.is_enabled(&"grilled_cheese"))
	assert_eq(menu.price_of(burger), standard, "a saved preset cannot bypass automatic prices")
	assert_true(_main.call("menu_set_special", burger.id))
	assert_true(_difficulty().request_change(&"normal", {}, 3))
	_finish_service()
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var paid_burgers: int = 0
	for order: Order in sim.orders.orders_in_state(Order.State.DELIVERED):
		if order.recipe_id == burger.id and order.paid:
			paid_burgers += 1
			assert_eq(order.price, standard, "the advertised special also sells at standard")
	assert_true(paid_burgers > 0, "a real service took payment for the dish")
	assert_true(Clock.sim.next_day())
	assert_false(menu.automatic_prices())
	assert_eq(menu.price_of(burger), standard)
	assert_false(menu.is_enabled(&"grilled_cheese"))
	assert_true(_main.call("menu_set_price", burger.id, standard + 1))


func test_automatic_jobs_reset_every_morning_and_leave_defaults_when_turned_off() -> void:
	_start()
	var roster: StaffRoster = _main.get("staff_roster") as StaffRoster
	var server_id: StringName = &""
	for member: StaffMember in roster.members():
		if member.role == &"server":
			server_id = member.id
	assert_false(server_id.is_empty())
	var high: int = StaffJobPriorities.Level.HIGH
	assert_true(_main.call("staff_set_job_priority", server_id, &"bussing", high))
	var flags: Dictionary = Difficulty.DEFAULT_CUSTOM_FLAGS.duplicate()
	flags[&"jobs"] = true
	assert_true(_difficulty().request_change(&"custom", flags, 2))
	_finish_service()
	assert_true(Clock.sim.next_day())
	assert_false(_difficulty().auto(&"prices"))
	assert_true(_main.call("menu_set_price", &"burger", 13))
	_assert_default_jobs(server_id)
	var panel: StaffPanel = _main.get_node("Overlay/StaffPanel") as StaffPanel
	var heading: Label = panel.get_node("%Priorities/Heading") as Label
	assert_eq(heading.text, "Jobs: handled for you")
	assert_true(panel.priority_button_for(server_id, &"bussing").disabled)
	assert_false(_main.call("staff_set_job_priority", server_id, &"bussing", high))
	# A stale saved choice must be reset even when the mode does not change.
	roster = _main.get("staff_roster") as StaffRoster
	assert_true(roster.set_job_priority(server_id, &"bussing", high))
	_finish_service()
	assert_true(Clock.sim.next_day())
	_assert_default_jobs(server_id)
	_close()
	_start()
	assert_eq(Clock.sim.day, 3)
	assert_true(_difficulty().auto(&"jobs"))
	_assert_default_jobs(server_id)
	assert_true(_difficulty().request_change(&"normal", {}, 4))
	_finish_service()
	assert_true(Clock.sim.next_day())
	_assert_default_jobs(server_id)
	panel = _main.get_node("Overlay/StaffPanel") as StaffPanel
	assert_false(panel.priority_button_for(server_id, &"bussing").disabled)
	assert_true(_main.call("staff_set_job_priority", server_id, &"bussing", high))


func _assert_default_jobs(server_id: StringName) -> void:
	var roster: StaffRoster = _main.get("staff_roster") as StaffRoster
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	for member: StaffMember in roster.members():
		assert_eq(roster.job_priorities(member.id).to_dict(), StaffJobPriorities.new(member.role).to_dict())
	var employee: StaffAgent = sim.employee(server_id)
	assert_not_null(employee)
	if employee != null:
		var priorities: StaffJobPriorities = employee.get("_job_priorities") as StaffJobPriorities
		assert_eq(priorities.priority(&"bussing"), StaffJobPriorities.Level.NORMAL)


func _start(mode_id: StringName = &"normal") -> void:
	GameMode.request_new_game(false, mode_id)
	_main = MAIN.instantiate()
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 1)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_main)
	_main.call("start")


func _close() -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null


func _difficulty() -> Difficulty:
	return _main.get("difficulty") as Difficulty


func _finish_service() -> void:
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 15000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
