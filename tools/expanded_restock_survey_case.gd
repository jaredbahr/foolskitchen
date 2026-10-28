extends "res://tests/world/test_expanded_shop_invariants.gd"
## Manual seed survey: the original soak and assertions are retained.
var survey_seed: int = 1
var mornings: Array[Dictionary] = []
var _quotes: Dictionary[int, Dictionary] = {}

func _start() -> Node:
	var main: Node = MainScene.instantiate()
	main.set("use_saves", true)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", survey_seed)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim")
	sim.customer_arrived.connect(_on_arrived)
	sim.customer_paid.connect(_on_paid)
	return main

func _assert_clean_morning(main: Node, day: int) -> void:
	var order: Dictionary = main.get("_morning_order")
	var shortages: Dictionary = {}
	for id: StringName in TUNING.morning_stock:
		var missing: int = maxi(0, int(TUNING.morning_stock[id]) - Economy.stock.count(id))
		if missing > 0:
			shortages[String(id)] = missing
	mornings.append({"day": day, "cash_after_order": Economy.cash,
		"missing_target_units": shortages, "cash_short_units": order.get("short", {}),
		"storage_unfit_units": order.get("unfit", {}), "previous_close_quote": _quotes.get(day, {})})
	super._assert_clean_morning(main, day)

func _assert_closed_books(main: Node, day: int) -> void:
	super._assert_closed_books(main, day)
	var settings: ReorderSettings = main.call("_reorder")
	var lives: Dictionary = main.call("_shelf_lives")
	var costs: Dictionary = main.call("_unit_costs")
	var capacity: Dictionary[int, int] = main.call("_storage_capacity")
	var content: ContentDB = main.get("content")
	var book: DeliveryBook = main.get("deliveries")
	var full: Dictionary = StockAlerts.forecast(Economy.stock, settings, lives, day + 1,
		costs, 2147483647, main.get("auto_reorder_premium"), capacity,
		StorageSpace.kinds_of(content), book.pending_by_id())
	_quotes[day + 1] = {"cash_before_order": Economy.cash, "full_order_cost": full["order_cost"],
		"cash_shortfall": maxi(0, int(full["order_cost"]) - Economy.cash)}