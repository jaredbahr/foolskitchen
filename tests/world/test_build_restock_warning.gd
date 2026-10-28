extends TestCase
const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "restock_budget_warning"
var _main: Node
var _old_dir: String
var _dir: String
var _providers: Dictionary[String, Dictionary]

func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)

func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	SaveSystem._providers = _providers
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)

func _start() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 23)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)

func test_floor_budget_warning_is_visible_read_only_and_does_not_refuse_purchase() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("begin_floor_tool"))
	var mode: BuildMode = _main.get("build_mode")
	var cell: Vector2i = Vector2i(14, 5)
	assert_true(mode.floor_press(cell))
	var end: Vector2i = Vector2i(14, 9)
	mode.floor_pointer(end)
	assert_true(mode.current_check.ok, mode.current_check.why)
	var cost: int = mode.current_check.cost
	var estimate: int = _main.call("build_restock_estimate")
	assert_true(estimate > 0)
	Economy.add_cash(estimate + cost - 1 - Economy.cash, Ledger.OTHER)
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var random: Dictionary = GameState.call("_capture_save")
	var saved: String = FileAccess.get_file_as_string(SaveSystem._slot_path(SLOT))
	var warning: String = _main.call("build_restock_warning")
	assert_eq(warning, RestockBudgetWarning.text(Economy.cash, cost, estimate))
	assert_false(warning.is_empty())
	var hint: Label = _main.get_node("HUD").get("_build_hint_text")
	assert_true(hint.text.contains(warning), "the cash-change callback refreshes advice even while the check stays valid")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(GameState.call("_capture_save"), random)
	assert_eq(FileAccess.get_file_as_string(SaveSystem._slot_path(SLOT)), saved)
	assert_true(mode.current_check.ok, "advice never changes placement permission")
	var cash: int = Economy.cash
	assert_true(mode.floor_release(end), "the player may proceed below the restock reserve")
	assert_eq(Economy.cash, cash - cost)
	assert_eq(FileAccess.get_file_as_string(SaveSystem._slot_path(SLOT)), saved, "construction still does not autosave")

func test_buy_preview_advice_does_not_block_an_affordable_item() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	var mode: BuildMode = _main.get("build_mode")
	var world: SimWorld = _main.get("world")
	var editor: ShopEditor = _main.get("shop_editor")
	var place: Vector2i = SimGrid.NO_CELL
	for y: int in range(1, 10):
		for x: int in range(1, 13):
			var cell: Vector2i = Vector2i(x, y)
			if editor.check_buy(&"prep_counter", cell, 0).ok:
				place = cell
				break
		if place != SimGrid.NO_CELL:
			break
	assert_ne(place, SimGrid.NO_CELL)
	assert_true(mode.begin_buy(&"prep_counter", place))
	assert_true(mode.current_check.ok, mode.current_check.why)
	var cost: int = mode.selected_definition.price
	var estimate: int = _main.call("build_restock_estimate")
	Economy.add_cash(estimate + cost - 1 - Economy.cash, Ledger.OTHER)
	assert_false(String(_main.call("build_restock_warning")).is_empty())
	var cash: int = Economy.cash
	var count_before: int = ShopBuilder.items_with_def(world, &"prep_counter").size()
	assert_true(mode.commit(), "the advice is not a new spending rule")
	assert_eq(Economy.cash, cash - cost)
	assert_eq(ShopBuilder.items_with_def(world, &"prep_counter").size(), count_before + 1)


func test_estimate_tracks_enabled_targets_without_changing_them() -> void:
	await _start()
	var settings: ReorderSettings = _main.call("_reorder")
	var original: Dictionary = settings.to_dict()
	var estimate: int = _main.call("build_restock_estimate")
	assert_true(settings.set_enabled(&"tomato", false))
	assert_true(int(_main.call("build_restock_estimate")) < estimate)
	for id: StringName in settings.ids():
		assert_true(settings.set_enabled(id, false))
	assert_eq(_main.call("build_restock_estimate"), 0)
	assert_true(settings.from_dict(original))
	assert_eq(_main.call("build_restock_estimate"), estimate)

func test_closed_estimate_reuses_real_next_morning_forecast_and_idle_has_no_warning() -> void:
	await _start()
	assert_eq(_main.call("build_restock_warning"), "")
	assert_true(Clock.sim.start_service())
	for guard: int in 30:
		if Clock.sim.phase == SimClock.Phase.CLOSED:
			break
		_main.call("run_ticks", 1000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var content: ContentDB = _main.get("content")
	var book: DeliveryBook = _main.get("deliveries")
	var forecast: Dictionary = StockAlerts.forecast(Economy.stock, _main.call("_reorder"),
		_main.call("_shelf_lives"), Clock.sim.day + 1, _main.call("_unit_costs"), 2147483647,
		_main.get("auto_reorder_premium"), _main.call("_storage_capacity"),
		StorageSpace.kinds_of(content), book.pending_by_id())
	assert_eq(_main.call("build_restock_estimate"), forecast["order_cost"])
	var incoming_id: StringName = &""
	for row: Dictionary in forecast["rows"]:
		if int(row["buys"]) > 0:
			incoming_id = StringName(row["id"])
			break
	assert_ne(incoming_id, &"", "real service consumed an ingredient")
	assert_true(_main.call("stock_cart_set", incoming_id, 1))
	assert_true(_main.call("stock_place_order"), "the closed-day order is paid and due tomorrow")
	assert_eq(int(book.pending_by_id().get(incoming_id, 0)), 1)
	var paid_orders: Dictionary = book.to_dict()
	var paid_books: Dictionary = Economy.ledger.to_dict()
	var paid_cash: int = Economy.cash
	assert_true(int(_main.call("build_restock_estimate")) <= int(forecast["order_cost"]))
	assert_eq(book.to_dict(), paid_orders, "estimating never consumes or changes paid orders")
	assert_eq(Economy.ledger.to_dict(), paid_books)
	assert_eq(Economy.cash, paid_cash)