extends TestCase
## Real session guards, morning lifetime, exact books and sole save boundary.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TERMS: HaggleTuning = preload("res://data/balance/haggle.tres")
const SLOT: String = "haggle_session"
var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "haggle_session")
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


func _start(with_saves: bool = false) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 327)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _cart(main: Node, qty: int = 20) -> void:
	for id: StringName in Economy.stock.ids():
		main.call("stock_throw_out", id)
	assert_true(main.call("stock_cart_set", &"tomato", qty))
	assert_true(main.call("set_stock_visible", true))


## Explicit deterministic timing in a test, not an injected result: stop the
## actual game three times at the marker location yielding the given score.
func _play(main: Node, score: float) -> void:
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


func test_stream_is_lazy_one_attempt_survives_panel_and_same_morning_setup() -> void:
	var main: Node = _start()
	_cart(main)
	assert_false(GameState._capture_save()["rngs"].has("haggle"))
	main.call("stock_start_haggle")
	assert_true(GameState._capture_save()["rngs"].has("haggle"))
	var streams: Dictionary = GameState._capture_save()
	main.call("stock_start_haggle")
	assert_eq(GameState._capture_save(), streams, "a repeated start cannot draw zones again")
	assert_true(main.call("set_stock_visible", false), "closing the parent spends the attempted game")
	assert_false(main.call("is_haggle_active"))
	main.call("set_stock_visible", true)
	assert_false(main.call("can_start_haggle"))
	main.call("_begin_morning")
	assert_false(main.call("can_start_haggle"), "same-day setup cannot refresh an attempt")
	assert_eq(GameState._capture_save()["rngs"]["haggle"], streams["rngs"]["haggle"])


func test_discount_survives_refusal_then_applies_once_to_cash_lots_and_report() -> void:
	var main: Node = _start()
	_cart(main)
	_play(main, 1.0)
	assert_eq(main.call("stock_haggle_percent"), 10)
	assert_eq(main.call("stock_cart_total"), 18)
	Economy.cash = 17
	var books: Dictionary = Economy.ledger.to_dict()
	assert_false(main.call("stock_place_order"))
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(main.call("stock_haggle_percent"), 10)
	# An external quantity fault can make a valid cart stop fitting. Refusal
	# cannot consume the earned offer or partially charge it.
	Economy.cash = 100
	books = Economy.ledger.to_dict()
	var space: StorageSpace = main.call("storage_space")
	var full_storage: int = space.capacity(space.kind_of(&"tomato"))
	Economy.stock.add(&"tomato", full_storage, Clock.day, 0)
	assert_eq(main.call("stock_cart_refusal"), "Not enough dry storage space")
	assert_false(main.call("stock_place_order"))
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(main.call("stock_haggle_percent"), 10)
	Economy.stock.take(&"tomato", full_storage)
	var cost_before: int = Economy.ledger.day_costs(Clock.day)
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.cash, 82)
	assert_eq(Economy.ledger.day_costs(Clock.day) - cost_before, 18)
	assert_eq(Economy.stock.value(), {"cost": 18, "recorded": true})
	assert_eq(main.call("stock_haggle_percent"), 0)
	assert_false(main.call("can_start_haggle"))
	assert_true(main.call("stock_cart_set", &"tomato", 10))
	assert_eq(main.call("stock_cart_total"), 10)
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.cash, 72)
	var report: DayReport = main.call("build_report", Clock.day)
	assert_eq(report.haggle_percent, 10)
	assert_eq(report.haggle_saved, 2)
	assert_eq(report.stock_on_hand, 28)
	assert_eq(report.food_cost, 0, "buying supplies does not invent served-food cost")
	assert_false(report.to_dict().has("haggle_percent"))
	assert_false(report.to_dict().has("haggle_saved"))
	assert_eq(Economy.stock.take_many_valued({&"tomato": 20})["cost"], 18)
	assert_eq(Economy.stock.value()["cost"], 10)


func test_skip_and_service_orders_keep_list_prices_and_real_refunds() -> void:
	var main: Node = _start()
	_cart(main)
	main.call("stock_start_haggle")
	(main.get_node("Overlay/HaggleGame").get_node("%Skip") as Button).pressed.emit()
	var cash: int = Economy.cash
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.cash, cash - 20)
	assert_true(Clock.sim.start_service())
	assert_true(main.call("stock_cart_set", &"tomato", 5))
	assert_eq(main.call("stock_cart_total"), 5)
	assert_true(main.call("stock_place_order"))
	assert_eq(main.call("stock_cancel_orders"), 5)
	assert_eq(Economy.cash, cash - 20)
	assert_eq((main.get("deliveries") as DeliveryBook).paid_total(), 0)
	assert_false(main.call("can_start_haggle"))


func test_opening_expires_offer_and_auto_order_keeps_its_premium() -> void:
	var main: Node = _start()
	_cart(main)
	_play(main, 0.6)
	assert_eq(main.call("stock_haggle_percent"), 6)
	var auto_lines: Array[Dictionary] = [{"id": &"tomato", "qty": 1, "unit_cost": 1}]
	var cash: int = Economy.cash
	assert_true(Economy.buy_auto_order(auto_lines, 2))
	assert_eq(Economy.cash, cash - 2)
	assert_eq(main.call("stock_haggle_percent"), 6, "standing orders do not spend the offer")
	assert_true(Clock.sim.start_service())
	assert_eq(main.call("stock_haggle_percent"), 0)
	assert_eq(main.call("stock_cart_total"), 20)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	_cart(main)
	assert_true(main.call("can_start_haggle"))
	assert_eq(main.call("stock_haggle_percent"), 0)


func test_modal_blocks_actual_hud_open_speed_edit_and_camera_polling() -> void:
	var main: Node = _start()
	_cart(main)
	Clock.set_speed(2)
	var camera: CameraRig = main.get_node("CameraRig") as CameraRig
	camera.set_process(true)
	var tick: int = Clock.tick
	main.call("stock_start_haggle")
	assert_eq(Clock.speed, 0)
	assert_false(camera.is_processing())
	main.get_node("HUD").call("_on_context_pressed")
	main.get_node("HUD").call("_set_speed", 4)
	assert_eq(Clock.phase, SimClock.Phase.MORNING)
	assert_eq(Clock.speed, 0)
	assert_false(main.call("stock_place_order"))
	assert_false(main.call("set_build_active", true))
	assert_false(main.call("set_paint_active", true))
	assert_false(main.call("set_settings_visible", true))
	assert_false(main.call("assign_owner_mode", &"kitchen"))
	Clock.call("_process", 10.0)
	assert_eq(Clock.tick, tick)
	main.get_node("Overlay/HaggleGame").call("_on_skip_pressed")
	assert_true(camera.is_processing())
	assert_eq(Clock.speed, 2)


func test_load_in_existing_main_and_new_run_reset_without_action_saves() -> void:
	var main: Node = _start(true)
	var path: String = _save_dir.path_join(SLOT + ".json")
	var original: String = FileAccess.get_file_as_string(path)
	_cart(main)
	_play(main, 0.6)
	assert_eq(FileAccess.get_file_as_string(path), original, "haggling never saves")
	assert_true(main.call("_load_autosave"))
	_cart(main)
	assert_true(main.call("can_start_haggle"), "reloading the same Main resets the attempt")
	assert_eq(main.call("stock_haggle_percent"), 0)
	main.call("stock_start_haggle")
	main.call("_new_game")
	assert_false(main.call("is_haggle_active"))
	assert_false(bool(main.get("_haggle_attempted")))
	assert_eq(main.call("stock_haggle_percent"), 0)
	assert_eq(FileAccess.get_file_as_string(path), original)
