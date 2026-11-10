extends TestCase
## The real session quotes, pays and presents seasonal supplier prices.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TERMS: HaggleTuning = preload("res://data/balance/haggle.tres")
const ECONOMY_TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SLOT: String = "season_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "season_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_current_day_stock_tags_menu_hint_and_reads_keep_prices_quality_and_rng() -> void:
	var main: Node = _start()
	# This declared date fixture crosses no simulated service or daily award.
	Clock.sim.day = 28
	var menu: MenuSettings = main.get("menu_settings") as MenuSettings
	var recipe: RecipeDef = (main.get("content") as ContentDB).recipe(&"grilled_cheese")
	var sale_price: int = menu.price_of(recipe)
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var rng: Dictionary = GameState._capture_save()
	var details: Dictionary = main.call("menu_recipe_details")
	var hints: Array[Dictionary] = details[&"grilled_cheese"]["ingredients"]
	assert_true(hints.any(func(row: Dictionary) -> bool:
		return str(row["text"]).contains("Bread") and str(row["text"]).contains("In season")))
	var rows: Array[Dictionary] = main.call("stock_rows")
	assert_eq(_row(rows, &"bread")["season_tag"], "In season")
	assert_eq(_row(rows, &"tomato")["season_tag"], "Pricey this season")
	assert_eq(_row(rows, &"mussels")["unit_cost"], 4)
	assert_true(main.call("set_stock_visible", true))
	var panel: StockPanel = main.get_node("Overlay/StockPanel") as StockPanel
	assert_eq((panel.row_for(&"mussels")["price"] as Label).text, "$4 each")
	assert_eq((panel.row_for(&"mussels")["season"] as Label).text, "Pricey this season")
	assert_eq((panel.row_for(&"bread")["season"] as Label).text, "In season")
	assert_eq(menu.price_of(recipe), sale_price, "supplier prices never change a meal's sale price")
	assert_eq((main.call("menu_recipe_details") as Dictionary)[&"grilled_cheese"]["quality"],
		details[&"grilled_cheese"]["quality"], "price reads never change dish quality")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(GameState._capture_save(), rng, "stock and menu reads draw no random numbers")


func test_manual_cart_haggle_discounts_rounded_seasonal_units_once() -> void:
	var main: Node = _start()
	Clock.sim.day = 28
	assert_true(main.call("stock_cart_set", &"mussels", 3))
	assert_eq(main.call("stock_cart_list_total"), 12, "three $4 seasonal units, not round($9 * 1.2)")
	assert_true(main.call("set_stock_visible", true))
	_play_haggle(main, 1.0)
	assert_eq(main.call("stock_haggle_percent"), 10)
	assert_eq(main.call("stock_cart_total"), HaggleRules.charge(12, 10))
	var cash: int = Economy.cash
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.cash, cash - 11)
	assert_eq(Economy.stock.count(&"mussels"), 3)
	var lots: Array = (Economy.stock.to_dict()["batches"] as Dictionary)["mussels"]
	assert_eq(lots[0]["total_cost"], "11", "the paid discount is the lot's purchase basis")
	assert_eq((main.call("build_report", 28) as DayReport).haggle_saved, 1)


func test_auto_premium_uses_seasonal_line_prices_before_one_order_rounding() -> void:
	var main: Node = _start()
	Clock.sim.day = 28
	# A detached normal-morning target makes only mussels eligible for this
	# second, real Main._restock call; the shipped resource stays untouched.
	var fixture: EconomyTuning = ECONOMY_TUNING.duplicate(true) as EconomyTuning
	fixture.morning_stock = {&"mussels": 2}
	fixture.station_stock.clear()
	var settings: ReorderSettings = ReorderSettings.new(fixture)
	assert_true(settings.set_target(&"mussels", 2))
	main.set("reorder_settings", settings)
	assert_eq(Economy.stock.count(&"mussels"), 0)
	var plan: Dictionary = (main.call("_reorder") as ReorderSettings).plan(Economy.stock,
		main.call("_unit_costs"), Economy.cash, float(main.get("auto_reorder_premium")),
		false, main.call("storage_space"))
	assert_eq(plan["lines"], [{"id": &"mussels", "qty": 2, "unit_cost": 4}] as Array[Dictionary])
	assert_eq(plan["list_total"], 8)
	assert_eq(plan["cost"], ReorderSettings.auto_cost(8, ECONOMY_TUNING.auto_reorder_premium))
	assert_eq(plan["cost"], 9, "the premium is charged once after unit rounding")
	var cash: int = Economy.cash
	main.call("_restock")
	assert_eq(Economy.cash, cash - 9, "Main's real auto-order pays the seasonal line plus premium")
	assert_eq(Economy.stock.count(&"mussels"), 2)
	var lots: Array = (Economy.stock.to_dict()["batches"] as Dictionary)["mussels"]
	assert_eq(lots[0]["total_cost"], "9")


func test_day_28_forecast_prices_the_next_morning_without_buying_or_rng() -> void:
	var main: Node = _start()
	Clock.sim.day = 28
	# Default $1 ingredients round neutrally. A valid, detached tuning fixture
	# makes the tomorrow-vs-today choice observable on the starter tomato target.
	var tuned: SeasonTuning = (main.get("season_tuning") as SeasonTuning).duplicate(true) as SeasonTuning
	tuned.out_of_season_multiplier = 2.0
	assert_true(tuned.validate((main.get("content") as ContentDB).ingredients()).is_empty())
	main.set("season_tuning", tuned)
	var settings: ReorderSettings = main.call("_reorder", true)
	var empty: Stock = Stock.new()
	var pending: Dictionary[StringName, int] = main.call("_on_the_way")
	var kinds: Dictionary[StringName, int] = StorageSpace.kinds_of(main.get("content") as ContentDB)
	var space: StorageSpace = StorageSpace.new(main.call("_storage_capacity"), empty, pending, kinds)
	var premium: float = float(main.get("auto_reorder_premium"))
	var tomorrow: int = int(settings.plan(empty, main.call("_unit_costs", 29), 2147483647,
		premium, false, space)["cost"])
	var today: int = int(settings.plan(empty, main.call("_unit_costs", 28), 2147483647,
		premium, false, space)["cost"])
	assert_ne(today, tomorrow, "the tomato target exposes the season boundary")
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var rng: Dictionary = GameState._capture_save()
	assert_eq(main.call("build_restock_estimate"), tomorrow)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(GameState._capture_save(), rng)


func test_paid_day_28_order_arriving_day_29_keeps_its_original_lot_basis() -> void:
	var main: Node = _start()
	Clock.sim.day = 28
	Clock.sim.phase = SimClock.Phase.CLOSED # Declared boundary fixture, no synthetic service result.
	assert_true(main.call("stock_cart_set", &"mussels", 1))
	assert_eq(main.call("stock_cart_total"), 4)
	var cash: int = Economy.cash
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.cash, cash - 4, "payment occurs when the order is placed")
	var book: DeliveryBook = main.get("deliveries") as DeliveryBook
	assert_eq(book.orders().size(), 1)
	assert_eq(book.orders()[0]["due"], Vector2i(29, DeliveryBook.MORNING))
	assert_eq(book.orders()[0]["lines"], [{"id": &"mussels", "qty": 1, "unit_cost": 4}] as Array[Dictionary])
	assert_eq(Economy.stock.count(&"mussels"), 0)
	reset_weekly_for_synthetic_day_jump(main)
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.day, 29)
	assert_true(book.is_empty(), "the real morning delivery unloaded the paid order")
	assert_eq(Economy.stock.count(&"mussels"), 1)
	var lots: Array = (Economy.stock.to_dict()["batches"] as Dictionary)["mussels"]
	assert_eq(lots[0]["total_cost"], "4", "day-29 list price must not reprice a day-28 purchase")
	assert_eq(_row(main.call("stock_rows"), &"mussels")["unit_cost"], 2)
	assert_eq(_row(main.call("stock_rows"), &"mussels")["season_tag"], "In season")
	var hints: Array[Dictionary] = (main.call("menu_recipe_details") as Dictionary)[&"mussels_broth"]["ingredients"]
	assert_true(hints.any(func(row: Dictionary) -> bool:
		return str(row["text"]).contains("Mussels") and str(row["text"]).contains("In season")))


func _row(rows: Array[Dictionary], id: StringName) -> Dictionary:
	for row: Dictionary in rows:
		if row["id"] == id:
			return row
	return {}


func _play_haggle(main: Node, score: float) -> void:
	main.call("stock_start_haggle")
	assert_true(main.call("is_haggle_active"))
	var game: HaggleGame = main.get_node("Overlay/HaggleGame") as HaggleGame
	game.set_process(false)
	for index: int in TERMS.rounds:
		var centers: Array = game.snapshot()["centers"]
		var marker: float = float(centers[index]) - TERMS.zone_widths[index] * 0.5 * (1.0 - score)
		game.call("_process", marker / TERMS.speeds[index])
		(game.get_node("%Stop") as Button).pressed.emit()
		game.call("_release_stop")
	assert_false(main.call("is_haggle_active"))


func _start() -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 340)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()
