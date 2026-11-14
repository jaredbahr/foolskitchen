extends TestCase
## The opening-week chain in a real session (#494): each goal's trigger, one
## ledger movement per goal, the tracker and Goals card, the save round trip,
## old saves and the end of the chain.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "opening_week_session"
const CHAIN: OpeningWeekSet = preload("res://data/balance/opening_week.tres")

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "opening_week_session")
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


func test_new_game_shows_the_chain_in_the_tracker_and_goals() -> void:
	var main: Node = await _start(false)
	var state: OpeningWeek = _state(main)
	assert_true(state.is_active(), "every new career game gets the opening week")
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var lines: Array[String] = hud.call("opening_week_lines")
	assert_eq(lines.size(), 3, "the tracker shows three goals")
	assert_eq(lines[0], OpeningWeekText.tracker_line(CHAIN.goals[0]))
	assert_true(main.call("set_goals_visible", true))
	var goals: GoalsPanel = main.get_node("Overlay/GoalsPanel") as GoalsPanel
	assert_eq(goals.opening_goal_ids(), [&"change_price", &"place_decor", &"serve_15"] as Array[StringName])
	var list: VBoxContainer = goals.get_node("%List") as VBoxContainer
	assert_eq(list.get_child(0).name, &"OpeningWeek", "the Opening week card leads the panel")


func test_price_change_pays_once_as_its_own_ledger_movement() -> void:
	var main: Node = await _start(false)
	var cash: int = Economy.cash
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var dish: RecipeDef = settings.enabled_recipes()[0]
	var price: int = settings.price_of(dish)
	assert_true(main.call("menu_set_price", dish.id, price))
	assert_eq(Economy.cash, cash, "setting the same price is no change")
	assert_true(main.call("menu_set_price", dish.id, price + 1))
	var reward: int = CHAIN.by_id(&"change_price").reward_cash
	assert_eq(Economy.cash, cash + reward)
	assert_eq(_bonus_entries(), [reward] as Array[int], "one ledger movement for the goal")
	assert_true(main.call("menu_set_price", dish.id, price + 2))
	assert_eq(Economy.cash, cash + reward, "the goal pays once only")
	assert_true(_state(main).is_completed(&"change_price"))
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var lines: Array[String] = hud.call("opening_week_lines")
	assert_eq(lines[0], OpeningWeekText.tracker_line(CHAIN.by_id(&"place_decor")), "the tracker moves on")
	assert_true(_logged(main, OpeningWeekText.met_line(CHAIN.by_id(&"change_price"))), "a log line names the goal")


func test_decor_pays_at_opening_but_other_furniture_does_not() -> void:
	var main: Node = await _start(false)
	assert_true(_buy_anywhere(main, &"chair"), "a chair is placed")
	assert_true(_buy_anywhere(main, &"lamp_floor_round"), "a floor lamp is placed")
	assert_eq(_bonus_entries(), [] as Array[int], "nothing pays before opening")
	var cash: int = Economy.cash
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"place_decor"), "the lamp is still there at opening")
	assert_eq(_bonus_entries(), [CHAIN.by_id(&"place_decor").reward_cash] as Array[int])
	assert_eq(Economy.cash, cash + CHAIN.by_id(&"place_decor").reward_cash)


func test_buy_then_undo_before_opening_pays_nothing() -> void:
	var main: Node = await _start(false)
	assert_true(main.call("set_build_active", true))
	assert_true(_buy_anywhere(main, &"lamp_floor_round"))
	assert_true(main.call("undo_edit"), "undo the lamp")
	assert_true(_buy_anywhere(main, &"drinks_shelf", true))
	assert_true(main.call("undo_edit"), "undo the drinks shelf")
	assert_true(main.call("set_build_active", false))
	var cash: int = Economy.cash
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_completed(&"place_decor"), "an undone lamp pays nothing")
	assert_false(_state(main).is_completed(&"drink_on_menu"), "an undone shelf pays nothing")
	assert_eq(_bonus_entries(), [] as Array[int])
	assert_eq(Economy.cash, cash)


func test_a_drinks_shelf_puts_beer_on_the_menu_and_pays_at_opening() -> void:
	var main: Node = await _start(false)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_true(_buy_anywhere(main, &"drinks_shelf", true), "a reachable drinks shelf is placed")
	var drinks: int = 0
	for recipe: RecipeDef in settings.enabled_recipes():
		if recipe.is_drink():
			drinks += 1
	assert_true(drinks > 0, "beer goes on the menu by itself")
	assert_false(_state(main).is_completed(&"drink_on_menu"), "not before opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"drink_on_menu"))
	assert_eq(_bonus_entries(), [CHAIN.by_id(&"drink_on_menu").reward_cash] as Array[int])


func test_owner_on_the_floor_and_serving_count_only_during_service() -> void:
	var main: Node = await _start(false)
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	assert_true(restaurant.assign_owner(&"floor"))
	restaurant.served_today = 15
	main.call("_observe_opening_state")
	assert_false(_state(main).is_completed(&"owner_on_floor"), "the morning is not service")
	assert_false(_state(main).is_completed(&"serve_15"))
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"owner_on_floor"), "on the floor at opening")
	assert_true(_state(main).is_completed(&"serve_15"))
	assert_false(_state(main).is_completed(&"serve_25"))
	assert_eq(_bonus_entries().size(), 2)


func test_grow_together_needs_a_new_table_and_server_still_there_at_opening() -> void:
	var main: Node = await _start(false)
	assert_true(_buy_anywhere(main, &"table_2"), "a table is placed")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_completed(&"grow_together"), "a table alone is not enough")
	main.free()
	_mains.clear()
	main = await _start(false)
	var server: StringName = _server_candidate(main)
	assert_false(server.is_empty(), "a server is on offer on day one")
	assert_true(_buy_anywhere(main, &"table_2"))
	assert_true(main.call("staff_hire", server))
	assert_true(main.call("staff_let_go", server), "let go again before opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_completed(&"grow_together"), "the hire must still be there at opening")
	main.free()
	_mains.clear()
	main = await _start(false)
	server = _server_candidate(main)
	assert_true(_buy_anywhere(main, &"table_2"))
	assert_true(main.call("staff_hire", server))
	var cash: int = Economy.cash
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"grow_together"))
	assert_eq(Economy.cash, cash + CHAIN.by_id(&"grow_together").reward_cash)


func test_close_adds_the_xp_and_the_rating_goal() -> void:
	var main: Node = await _start(false)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var dish: RecipeDef = settings.enabled_recipes()[0]
	assert_true(main.call("menu_set_price", dish.id, settings.price_of(dish) + 1))
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var xp_before: int = owner.total_xp
	main.set("reputation", _book_high())
	_close_day(main)
	var report: DayReport = main.get("shown_report") as DayReport
	var opening_xp: int = CHAIN.by_id(&"change_price").reward_xp + CHAIN.by_id(&"reach_4_stars").reward_xp
	assert_eq(int(report.owner_xp_breakdown.get("opening_week_xp", 0)), opening_xp)
	assert_true(owner.total_xp >= xp_before + opening_xp)
	assert_eq(_state(main).pending_xp, 0)
	assert_true(_state(main).is_completed(&"reach_4_stars"), "a 4-star close meets the rating goal")
	assert_eq(int(report.income.get(Ledger.OPENING_WEEK_BONUS, 0)),
		CHAIN.by_id(&"change_price").reward_cash + CHAIN.by_id(&"reach_4_stars").reward_cash)


func test_a_guest_paid_on_the_closing_tick_counts_and_close_toasts_wait() -> void:
	var main: Node = await _start(false)
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	main.set("reputation", _book_high())
	_close_day(main)
	# The 15th guest paid after the phase had turned CLOSED: the live check
	# missed them, so the close counts today's guests once more.
	assert_true(_state(main).is_completed(&"reach_4_stars"))
	assert_false(_state(main).is_completed(&"serve_15"))
	restaurant.served_today = 15
	main.call("_close_opening_week", Clock.sim.day)
	assert_true(_state(main).is_completed(&"serve_15"), "the close counts today's guests")
	var held: Array[String] = main.get("_held_opening_toasts")
	assert_true(held.size() >= 2, "toasts met under the evening report wait for the next day")
	var expected: Array[String] = held.duplicate()
	var hud: Node = main.get_node("HUD")
	# The top bar's Next day calls the clock directly, not the report's button.
	Clock.sim.next_day()
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_true((main.get("_held_opening_toasts") as Array[String]).is_empty())
	# The first toast is on screen; the rest wait in the HUD's queue.
	var texts: Array[String] = []
	var shown: Label = hud.get("_collection_toast_label") as Label
	if shown != null:
		texts.append(shown.text)
	for entry: Dictionary in hud.get("_collection_toast_queue"):
		texts.append(String(entry["text"]))
	for line: String in expected:
		assert_true(texts.has(line), "held toast reaches the HUD in the morning: %s" % line)


func test_progress_survives_the_morning_save_and_reload() -> void:
	var main: Node = await _start(true)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var dish: RecipeDef = settings.enabled_recipes()[0]
	assert_true(main.call("menu_set_price", dish.id, settings.price_of(dish) + 1))
	_close_day(main)
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.day, 2)
	var cash: int = Economy.cash
	var saved: Dictionary = _document()
	assert_eq((saved["data"] as Dictionary)["opening_week"]["completed"], ["change_price"])
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 2, "the morning save loaded")
	assert_true(_state(main).is_active())
	assert_eq(_state(main).completed_ids(), [&"change_price"] as Array[StringName])
	assert_eq(Economy.cash, cash)
	settings = main.get("menu_settings") as MenuSettings
	dish = settings.enabled_recipes()[0]
	assert_true(main.call("menu_set_price", dish.id, settings.price_of(dish) + 1))
	assert_eq(Economy.cash, cash, "a loaded, completed goal never pays again")


func test_old_saves_past_day_seven_never_get_the_chain() -> void:
	var main: Node = await _start(true)
	for step: int in 8:
		reset_weekly_for_synthetic_day_jump(main)
		Clock.sim.day += 1
		main.call("_begin_morning")
	assert_eq(Clock.sim.day, 9)
	assert_false(_state(main).is_active(), "the chain ended after day 7")
	var document: Dictionary = _document()
	(document["data"] as Dictionary).erase("opening_week")
	_write_document(document)
	_remove_backup()
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 9, "the old save loaded")
	assert_false(_state(main).is_active(), "a save from before the chain, past day 7, has none")
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	assert_eq((hud.call("opening_week_lines") as Array).size(), 0, "no tracker")


func test_old_saves_inside_the_week_join_the_chain() -> void:
	var main: Node = await _start(true)
	reset_weekly_for_synthetic_day_jump(main)
	Clock.sim.day += 1
	main.call("_begin_morning")
	var document: Dictionary = _document()
	(document["data"] as Dictionary).erase("opening_week")
	_write_document(document)
	_remove_backup()
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 2)
	assert_true(_state(main).is_active())
	assert_true(_state(main).completed_ids().is_empty())


func test_chain_ends_the_morning_after_day_seven() -> void:
	var main: Node = await _start(false)
	for step: int in 6:
		reset_weekly_for_synthetic_day_jump(main)
		Clock.sim.day += 1
		main.call("_begin_morning")
	assert_eq(Clock.sim.day, 7)
	assert_true(_state(main).is_active(), "day 7 still has the chain")
	reset_weekly_for_synthetic_day_jump(main)
	Clock.sim.day += 1
	main.call("_begin_morning")
	assert_false(_state(main).is_active())
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	assert_eq((hud.call("opening_week_lines") as Array).size(), 0, "the tracker goes away")
	assert_true(main.call("set_goals_visible", true))
	var goals: GoalsPanel = main.get_node("Overlay/GoalsPanel") as GoalsPanel
	assert_null(goals.get_node("%List").get_node_or_null("OpeningWeek"), "the card goes away")


func test_finishing_every_goal_ends_the_chain_at_once() -> void:
	var main: Node = await _start(false)
	var state: OpeningWeek = _state(main)
	for goal: OpeningGoal in CHAIN.goals:
		if goal.id != &"place_decor":
			state.observe(goal.condition, goal.target, CHAIN)
	assert_true(state.is_active())
	assert_true(_buy_anywhere(main, &"lamp_floor_round"))
	assert_true(state.is_active(), "the lamp counts at opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_active(), "the last goal ends the chain")
	assert_true(_logged(main, OpeningWeekText.COMPLETE_LINE))


func test_creative_games_have_no_chain() -> void:
	GameMode.request_new_game(true)
	var main: Node = await _start(false)
	assert_false(_state(main).is_active())
	GameMode.request_new_game(false)


func _start(saves: bool) -> Node:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 7)
	main.set("skip_owner_picker", true)
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


func _state(main: Node) -> OpeningWeek:
	return main.get("opening_week") as OpeningWeek


func _bonus_entries() -> Array[int]:
	var amounts: Array[int] = []
	for entry: Dictionary in Economy.ledger.entries_for_day(Clock.sim.day):
		if entry["category"] == Ledger.OPENING_WEEK_BONUS:
			amounts.append(int(entry["amount"]))
	return amounts


func _logged(main: Node, line: String) -> bool:
	var world: SimWorld = main.get("world") as SimWorld
	for row: Variant in world.event_log:
		if str(row).contains(line):
			return true
	return false


## Places the item on the first cell the real editor accepts. With
## `needs_drink`, a station must also open a drink (a reachable work cell).
func _buy_anywhere(main: Node, item_id: StringName, needs_drink: bool = false) -> bool:
	var world: SimWorld = main.get("world") as SimWorld
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var cells: Array[Vector2i] = world.grid.cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in cells:
		for turns: int in 4:
			var before: Dictionary[int, bool] = {}
			for placed: PlacedItem in world.grid.items():
				before[placed.id] = true
			if main.call("shop_buy", item_id, cell, turns):
				if not needs_drink:
					return true
				for recipe: RecipeDef in settings.enabled_recipes():
					if recipe.is_drink():
						return true
				# Its work cell faces a wall: sell it and try the next spot.
				for placed: PlacedItem in world.grid.items():
					if not before.has(placed.id):
						main.call("shop_sell", placed.id)
	return false


func _server_candidate(main: Node) -> StringName:
	for member: StaffMember in (main.get("staff_roster") as StaffRoster).candidates():
		if member.role == &"server":
			return member.id
	return &""


## Ten fives: a rating well above four stars, whatever today adds.
func _book_high() -> ReputationBook:
	var book: ReputationBook = ReputationBook.new()
	assert_true(book.from_dict({"version": 1, "scores": [5, 5, 5, 5, 5, 5, 5, 5, 5, 5]}))
	return book


func _quiet_service(main: Node) -> void:
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	restaurant.spawner.min_gap = 100000
	restaurant.spawner.max_gap = 100000
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1


func _close_day(main: Node) -> void:
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")))


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_save_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_backup() -> void:
	var path: String = _save_dir.path_join(SLOT + ".json.bak")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
