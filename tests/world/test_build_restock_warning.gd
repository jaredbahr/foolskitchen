extends TestCase
const MAIN: PackedScene = preload("res://src/world/main.tscn")
const MANUAL_MAIN: GDScript = preload("res://tests/fixtures/manual_restock_main.gd")
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

func _start(manual_stock: bool = false) -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate()
	if manual_stock:
		_main.set_script(MANUAL_MAIN)
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
	var hud: Node = _main.get_node("HUD")
	var line: Label = hud.get("_build_warning_text")
	assert_eq(line.text, warning, "the cash-change callback refreshes advice even while the check stays valid")
	assert_true(line.visible)
	assert_eq(line.get_theme_color("font_color"), hud.get("ADVICE_COLOR"), "advice is amber, not the red of an error")
	var hint: Label = hud.get("_build_hint_text")
	assert_false(hint.text.contains(warning), "the cost line above keeps its normal colour")
	assert_true(hint.text.contains(mode.floor_summary()))
	assert_false(hint.has_theme_color_override("font_color"))
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


func test_floor_laying_preview_warns_with_its_tile_cost() -> void:
	# Literal restock wording uses the original player-selected fixed targets.
	await _start(true)
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("begin_floors_tool", &"herringbone", &"honey"))
	var mode: BuildMode = _main.get("build_mode")
	assert_eq(_main.call("build_restock_estimate"), 93)
	Economy.add_cash(217 - Economy.cash, Ledger.OTHER)
	assert_true(mode.floors_press(Vector2i(1, 1)))
	mode.floors_pointer(Vector2i(8, 6))
	assert_true(mode.current_check.ok, mode.current_check.why)
	# The rectangle now includes five reclaimed row-4 floor tiles.
	assert_eq(mode.current_check.finishes.size(), 48)
	assert_eq(mode.current_check.cost, 144)
	assert_eq(_main.call("build_restock_warning"), "Leaves $73 — tomorrow's restock needs about $93")
	assert_true(mode.floors_release(Vector2i(8, 6)), "the advice never refuses laying the floor")
	assert_eq(Economy.cash, 217 - 144)


func test_estimate_tracks_enabled_targets_without_changing_them() -> void:
	await _start()
	var settings: ReorderSettings = _main.get("reorder_settings")
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
		StorageSpace.kinds_of(content), _main.call("_on_the_way"))
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


func test_wall_finish_drag_warns_with_its_net_cost() -> void:
	# Literal restock wording uses the original player-selected fixed targets.
	await _start(true)
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("begin_wall_finish_tool", &"stripes", &"butter", &"cream"))
	var mode: BuildMode = _main.get("build_mode")
	var estimate: int = _main.call("build_restock_estimate")
	assert_eq(estimate, 93)
	# Shift-click: the dining room's walls, $2 a face, nothing to refund.
	assert_true(mode.wall_finish_press(Vector3i(1, 6, 3), true))
	assert_true(mode.current_check.ok, mode.current_check.why)
	var cost: int = mode.current_check.cost - mode.current_check.refund
	assert_true(cost > 0)
	Economy.add_cash(estimate + cost - 5 - Economy.cash, Ledger.OTHER)
	mode.wall_finish_pointer(Vector3i(1, 6, 3), true)
	assert_eq(_main.call("build_restock_warning"), "Leaves $88 — tomorrow's restock needs about $93")
	_assert_amber_warning("Leaves $88 — tomorrow's restock needs about $93")
	assert_true(_hint_label().text.contains(mode.wall_finish_summary()), "the cost line stays above the advice")
	var cash: int = Economy.cash
	assert_true(mode.wall_finish_release(Vector3i(1, 6, 3)), "the advice never refuses a wall finish")
	assert_eq(Economy.cash, cash - cost)


func test_neon_sign_hang_warns_with_its_price_and_a_move_does_not() -> void:
	# Literal restock wording uses the original player-selected fixed targets.
	await _start(true)
	assert_true(_main.call("set_build_active", true))
	var editor: ShopEditor = _main.get("shop_editor")
	editor.set_owner_level(4)
	var mode: BuildMode = _main.get("build_mode")
	# Two street-front windows for the sign (it hangs only in a window).
	Economy.add_cash(500, Ledger.OTHER)
	var windows: Dictionary[Vector3i, int] = {Vector3i(8, 10, SimGrid.EDGE_NORTH): SimGrid.Segment.WINDOW,
		Vector3i(10, 10, SimGrid.EDGE_NORTH): SimGrid.Segment.WINDOW}
	assert_true(_main.call("shop_walls", windows), editor.last_check.why)
	assert_true(mode.begin_hang(&"neon_open_sign"))
	Economy.add_cash(93 + 80 - 5 - Economy.cash, Ledger.OTHER)
	mode.hang_pointer(Vector3i(8, 9, 2), 0.1)
	assert_true(mode.current_check.ok, mode.current_check.why)
	assert_eq(mode.current_check.cost, 80)
	assert_eq(_main.call("build_restock_warning"), "Leaves $88 — tomorrow's restock needs about $93")
	_assert_amber_warning("Leaves $88 — tomorrow's restock needs about $93")
	assert_true(mode.hang_commit(), "the advice never refuses hanging")
	assert_eq(Economy.cash, 88)
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUY)
	mode.cancel_ghost()
	assert_true(mode.begin_rehang(Vector3i(8, 9, 2)))
	mode.hang_pointer(Vector3i(10, 9, 2), 0.1)
	assert_true(mode.current_check.ok, mode.current_check.why)
	assert_eq(_main.call("build_restock_warning"), "", "moving wall decor is free")
	var line: Label = _warning_label()
	assert_false(line.visible, "no advice line for a free move")
	assert_eq(line.text, "")


func _warning_label() -> Label:
	return _main.get_node("HUD/BuildHints/Scroll/Lines/Warning") as Label


func _hint_label() -> Label:
	return _main.get_node("HUD/BuildHints/Scroll/Lines/Text") as Label


## The advice sits on the amber Warning line, not on the cost line above it.
func _assert_amber_warning(expected: String) -> void:
	var line: Label = _warning_label()
	var hud: Node = _main.get_node("HUD")
	assert_eq(line.text, expected)
	assert_true(line.visible)
	assert_eq(line.get_theme_color("font_color"), hud.get("ADVICE_COLOR"), "advice is amber")
	assert_false(_hint_label().text.contains(expected), "the cost line keeps its own text")
