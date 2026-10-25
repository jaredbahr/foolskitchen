extends TestCase
## Real checked session/UI boundaries. Departure attribution below is an
## explicitly labelled signal fixture, not a played visit or balance evidence.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const VIBE: VibeTuning = preload("res://data/balance/vibe.tres")
const ECONOMY: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SLOT: String = "vibe_session"

var _mains: Array[Node] = []
var _save_dir: String
var _old_save_dir: String
var _old_providers: Dictionary = {}
var _preferences: SettingsPreferences
var _old_preferences: Dictionary = {}
var _window_size: Vector2i
var _window_mode: Window.Mode
var _window_scale: float
var _notifications: int = 0


func before_each() -> void:
	var window: Window = (Engine.get_main_loop() as SceneTree).root
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "vibe_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_providers = SaveSystem._providers.duplicate()
	_preferences = window.get_node("Preferences") as SettingsPreferences
	_old_preferences.clear()
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save", "ui_scale_percent",
			"default_open_speed", "fullscreen_enabled", "edge_pan_enabled"]:
		_old_preferences[key] = _preferences.get(key)
	_window_size = window.size
	_window_mode = window.mode
	_window_scale = window.content_scale_factor
	_preferences.set("_file_path", _save_dir.path_join("preferences.cfg"))
	_preferences.set("_disk_enabled", false)
	_preferences.set("_pending_volume_save", false)
	_preferences.ui_scale_percent = 100
	_preferences.default_open_speed = 1
	_preferences.fullscreen_enabled = false
	_preferences.edge_pan_enabled = false
	_notifications = 0
	Clock.set_speed(0)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	assert_false(FileAccess.file_exists(_save_dir.path_join("preferences.cfg")))
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	for key: String in _old_preferences:
		_preferences.set(key, _old_preferences[key])
	var window: Window = (Engine.get_main_loop() as SceneTree).root
	if window.mode != _window_mode:
		window.mode = _window_mode
	if window.size != _window_size:
		window.size = _window_size
	window.content_scale_factor = _window_scale
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_default_is_neutral_and_real_arrival_budgets_and_recompute_rng_are_unchanged() -> void:
	var main: Node = await _start()
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var result: VibeModel.Result = main.get("vibe_result") as VibeModel.Result
	assert_true(result.valid)
	assert_almost_eq(result.score, 0.0, 0.0001)
	assert_almost_eq(result.patience_multiplier, 1.0, 0.0001)
	assert_almost_eq(result.raw_review_bonus, 0.0, 0.0001)
	assert_eq(sim.spawner.min_gap, ECONOMY.arrival_gap_min)
	assert_eq(sim.spawner.max_gap, ECONOMY.arrival_gap_max)
	var rng: Dictionary = GameState._capture_save()
	var books: Dictionary = Economy._capture_save()
	var saved: String = _saved_text()
	main.call("_recompute_vibe")
	assert_eq(GameState._capture_save(), rng)
	assert_eq(Economy._capture_save(), books)
	assert_eq(_saved_text(), saved)
	result.score = 100.0
	assert_almost_eq((main.get("vibe_result") as VibeModel.Result).score, 0.0, 0.0001,
		"public reads are detached from the live arrival snapshot")
	sim.spawner.min_gap = 1
	sim.spawner.max_gap = 1
	sim.spawner.reset()
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 1)
	assert_eq(sim.customers().size(), 1)
	var guest: CustomerAgent = sim.customers()[0]
	assert_eq(guest.queue_patience, 300)
	assert_eq(guest.food_patience, 1200)
	assert_almost_eq(guest.vibe_review_bonus, 0.0, 0.0001)
	assert_eq(_notifications, 1, "the explicit recompute is the only notification; service ticks do not evaluate")


func test_only_real_layout_paint_and_enabled_menu_changes_recompute() -> void:
	var main: Node = await _start()
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	editor.set_owner_level(2) # Explicit purchase-unlock fixture.
	var rng: Dictionary = GameState._capture_save()
	var saved: String = _saved_text()
	assert_true(main.call("shop_buy", &"potted_plant", Vector2i(11, 9), 0))
	assert_eq(_notifications, 1)
	assert_true((main.get("vibe_result") as VibeModel.Result).score > 0.0)
	var world: SimWorld = main.get("world") as SimWorld
	var plant: PlacedItem = world.grid.item_at(Vector2i(11, 9))
	assert_true(main.call("shop_move", plant.id, Vector2i(10, 9), 0))
	assert_eq(_notifications, 2)
	assert_true(main.call("shop_move", plant.id, plant.origin, 0))
	assert_false(main.call("shop_move", plant.id, Vector2i.ZERO, 0))
	assert_false(main.call("shop_buy", &"missing", Vector2i(4, 8), 0))
	assert_eq(_notifications, 2)
	assert_true(main.call("set_paint_active", true))
	main.call("preview_paint_cell", Vector2i(4, 8))
	assert_eq(_notifications, 2, "hover is presentation only")
	main.set("_paint_swatch_id", &"missing")
	assert_false(main.call("paint_cell", Vector2i(4, 8)))
	assert_eq(_notifications, 2)
	main.set("_paint_swatch_id", &"slate_blue")
	assert_true(main.call("paint_cell", Vector2i(4, 8)))
	assert_eq(_notifications, 3)
	assert_true(main.call("paint_cell", Vector2i(4, 8)))
	assert_eq(_notifications, 3, "reapplying the same paint is not a vibe change")
	assert_true(main.call("paint_cell", Vector2i.ZERO))
	assert_eq(_notifications, 4)
	assert_true(main.call("paint_cell", plant.origin))
	assert_eq(_notifications, 5)
	assert_true(main.call("set_paint_active", false))
	assert_true(main.call("menu_set_enabled", &"tomato_soup", false))
	assert_eq(_notifications, 6)
	assert_true(main.call("menu_set_enabled", &"tomato_soup", false))
	assert_false(main.call("menu_set_enabled", &"missing", true))
	assert_true(main.call("menu_set_price", &"burger", 999))
	assert_eq(_notifications, 6, "prices and rejected/no-op choices do not change theme inputs")
	assert_true(main.call("menu_set_enabled", &"tomato_soup", true))
	assert_eq(_notifications, 7)
	_assert_current_inputs(main)
	main.call("refresh_presentation")
	main.call("_process", 0.0)
	assert_eq(_notifications, 7)
	assert_eq(GameState._capture_save(), rng)
	assert_eq(_saved_text(), saved)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 2)
	assert_eq(_notifications, 7)
	assert_false(main.call("menu_set_enabled", &"tomato_soup", false))
	assert_false(main.call("shop_move", plant.id, Vector2i(11, 9), 0))
	assert_eq(_notifications, 7)
	assert_eq(_saved_text(), saved)


func test_derived_state_reloads_from_normal_morning_sources_and_disconnects_old_grid() -> void:
	var main: Node = await _start()
	var saved: String = _saved_text()
	_decorate_modern(main)
	var expected: Dictionary = _result_state(main.get("vibe_result") as VibeModel.Result)
	assert_true(expected["score"] > 0.0)
	assert_eq(expected["theme"], &"modern")
	assert_eq(_saved_text(), saved)
	_close_service(main)
	assert_eq(_saved_text(), saved)
	assert_true(Clock.sim.next_day())
	var document: Dictionary = JSON.parse_string(_saved_text())
	assert_false(document["data"].has("vibe"), "vibe has no save provider")
	var shop: Dictionary = (main.get("shop_editor") as ShopEditor).to_dict()
	var menu: Dictionary = (main.get("menu_settings") as MenuSettings).to_dict()
	var books: Dictionary = Economy._capture_save()
	var old_grid: SimGrid = (main.get("world") as SimWorld).grid
	var callback: Callable = Callable(main, "_on_vibe_cells_changed")
	assert_true(old_grid.cells_changed.is_connected(callback))
	main.get_parent().remove_child(main)
	assert_false(old_grid.cells_changed.is_connected(callback))
	_close(main)
	var loaded: Node = await _start()
	assert_eq(Clock.sim.day, 2)
	assert_eq((loaded.get("shop_editor") as ShopEditor).to_dict(), shop)
	assert_eq((loaded.get("menu_settings") as MenuSettings).to_dict(), menu)
	assert_eq(Economy._capture_save(), books)
	assert_eq(_result_state(loaded.get("vibe_result") as VibeModel.Result), expected)
	_assert_current_inputs(loaded)
	var grid: SimGrid = (loaded.get("world") as SimWorld).grid
	assert_true(grid != old_grid)
	var matches: int = 0
	for connection: Dictionary in grid.cells_changed.get_connections():
		if connection["callable"] == Callable(loaded, "_on_vibe_cells_changed"):
			matches += 1
	assert_eq(matches, 1)


func test_native_meter_hud_and_report_fit_scaled_windows_without_changing_header_width() -> void:
	var main: Node = await _start()
	_decorate_modern(main)
	assert_true(main.call("set_build_active", true))
	var catalogue: BuildCatalogue = main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	var meter: VibeMeter = catalogue.vibe_meter
	assert_eq(catalogue.get_node("Panel/Margin/Rows/Scroll/Content/VibeMeter"), meter)
	var reputation: Label = main.get_node("HUD/Top/Row/Reputation") as Label
	var width: float = reputation.get_combined_minimum_size().x
	for _refresh: int in 3:
		main.get_node("HUD").call("refresh")
	assert_eq(reputation.tooltip_text.count("Theme:"), 1)
	assert_true(reputation.tooltip_text.contains("Theme: Modern"))
	assert_eq(reputation.get_combined_minimum_size().x, width)
	# Read-only report presentation fixture; its normal scroll keeps the new
	# summary accessible without removing finance, review or progression rows.
	var report: Control = main.get_node("Overlay/EveningReport") as Control
	report.call("show_report", main.call("build_report", Clock.sim.day))
	var summary: Label = report.get_node("Panel/Scroll/Content/VibeSummary") as Label
	var report_scroll: ScrollContainer = report.get_node("Panel/Scroll") as ScrollContainer
	var window: Window = (Engine.get_main_loop() as SceneTree).root
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		window.size = physical_size
		for scale: int in [125, 150]:
			_preferences.ui_scale_percent = scale
			_preferences.apply_window(window)
			main.get_node("HUD").call("refresh")
			await _frames(3)
			var panel: Control = catalogue.get_node("Panel") as Control
			var scroll: ScrollContainer = catalogue.get_node("Panel/Margin/Rows/Scroll") as ScrollContainer
			var viewport: Rect2 = window.get_visible_rect()
			assert_true(viewport.grow(0.5).encloses(panel.get_global_rect()))
			assert_true(panel.size.y <= maxf(96.0, viewport.size.y * BuildCatalogue.PANEL_HEIGHT_SHARE) + 0.5)
			var native: Dictionary = meter.view_state()
			assert_true(meter.is_visible_in_tree())
			assert_true(scroll.get_global_rect().grow(0.5).encloses(native["caption_rect"]))
			assert_true(scroll.get_global_rect().grow(0.5).encloses(native["bar_rect"]))
			assert_almost_eq(native["value"], (main.get("vibe_result") as VibeModel.Result).score, 0.0001)
			assert_true(native["tooltip"].contains("Decor"))
			assert_true(native["tooltip"].contains("Variety"))
			assert_true(native["tooltip"].contains("Theme: Modern"))
			assert_true(native["tooltip"].contains("Lamps"))
			assert_true(native["tooltip"].contains("Crowding"))
			report_scroll.ensure_control_visible(summary)
			await _frames(1)
			assert_true(viewport.grow(0.5).encloses((report.get_node("Panel") as Control).get_global_rect()))
			assert_true(report_scroll.get_global_rect().grow(0.5).encloses(summary.get_global_rect()))
	assert_eq(meter.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(meter.get_node("CaptionLabel").get("mouse_filter"), Control.MOUSE_FILTER_IGNORE)
	assert_eq(meter.get_node("ScoreBar").get("mouse_filter"), Control.MOUSE_FILTER_IGNORE)
	assert_true(main.call("set_paint_active", true))
	assert_false(meter.visible)
	assert_true(main.call("set_paint_active", false))
	assert_true(main.call("set_build_active", true))
	assert_true(meter.visible)
	report.call("show_report", main.call("build_report", Clock.sim.day))
	assert_true((report.get_node("Panel/Scroll/Content/VibeSummary") as Label).text.begins_with("Vibe: Modern"))
	assert_true((report.get_node("Panel/Scroll/Content/Profit") as Label).text.contains("operating profit"))


func test_departure_signal_fixture_attributes_arrival_theme_not_later_repaint_and_resets_each_morning() -> void:
	var main: Node = await _start()
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	assert_true(sim.customer_left.is_connected(Callable(main, "_on_vibe_customer_left")))
	var line: Label = main.get_node("Overlay/EveningReport/Panel/Scroll/Content/VibeSummary") as Label
	assert_true(line.text.begins_with("Vibe:"), "no paid departures cannot claim guests loved the room")
	var before: Dictionary = _side_effects()
	# These controlled departure notifications test Main's UI-only callback.
	# Pure sim tests separately prove real once-only departure/review emission.
	_departure_fixture(sim, false, 0.3, "Cosy")
	_departure_fixture(sim, true, NAN, "Cosy")
	_departure_fixture(sim, true, 0.3, "unapproved")
	assert_true(line.text.begins_with("Vibe:"))
	_departure_fixture(sim, true, 0.3, "Modern")
	_departure_fixture(sim, true, 0.3, "Cosy")
	assert_eq(line.text, "Guests loved the cosy vibe.", "equal counts use lexical human-label order")
	assert_eq(_side_effects(), before)
	assert_eq(_notifications, 0, "observing departures never evaluates the room again")
	_decorate_modern(main)
	assert_eq((main.get("vibe_result") as VibeModel.Result).active_theme, &"modern")
	assert_eq(line.text, "Guests loved the cosy vibe.", "later paint cannot replace arrival evidence")
	_close_service(main)
	assert_eq(line.text, "Guests loved the cosy vibe.")
	assert_true(Clock.sim.next_day())
	assert_true(line.text.begins_with("Vibe: Modern"))


func _start() -> Node:
	await _frames(1)
	var main: Node = MAIN.instantiate()
	main.set("use_saves", true)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 12201)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	main.set_process(false)
	(main.get_node("CameraRig") as CameraRig).set_process(false)
	(main.get_node("ShopView") as ShopView).set_process(false)
	Clock.set_speed(0)
	main.connect("vibe_changed", _on_vibe_changed)
	await _frames(2)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.free()


func _on_vibe_changed(_result: VibeModel.Result) -> void:
	_notifications += 1


func _decorate_modern(main: Node) -> void:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	editor.set_owner_level(2) # Explicit design fixture, not normal progression/balance evidence.
	for table: PlacedItem in ShopBuilder.items_with_def(world, &"table_2"):
		assert_true(main.call("shop_sell", table.id) >= 0)
	for origin: Vector2i in [Vector2i(2, 6), Vector2i(6, 6), Vector2i(10, 6)]:
		assert_true(main.call("shop_buy", &"rug_square", origin, 0))
	assert_true(main.call("set_paint_active", true))
	main.set("_paint_swatch_id", &"slate_blue")
	assert_true(main.call("paint_cell", Vector2i.ZERO))
	assert_true(main.call("paint_cell", Vector2i(4, 8)))
	assert_true(main.call("set_paint_active", false))
	assert_true(main.call("menu_set_enabled", &"tomato_soup", false))
	_assert_current_inputs(main)


func _close_service(main: Node) -> void:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)


func _assert_current_inputs(main: Node) -> void:
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var expected: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(
		(main.get("world") as SimWorld).grid, main.get("content") as ContentDB,
		(main.get("menu_settings") as MenuSettings).enabled_recipes(), editor.wall_swatch_id, editor.floor_swatch_id), VIBE)
	assert_eq(_result_state(main.get("vibe_result") as VibeModel.Result), _result_state(expected))


func _result_state(result: VibeModel.Result) -> Dictionary:
	return {"valid": result.valid, "score": result.score, "decor": result.decor_points,
		"variety": result.variety_points, "theme_points": result.theme_points, "lamps": result.lamp_points,
		"crowding": result.crowding_penalty, "theme": result.active_theme, "label": result.theme_label,
		"share": result.theme_share, "patience": result.patience_multiplier, "review": result.raw_review_bonus,
		"arrival": result.arrival_theme_strength, "floor": result.interior_cells, "occupied": result.occupied_normal_cells}


func _departure_fixture(sim: RestaurantSim, paid: bool, bonus: float, label: String) -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 12217
	var guest: CustomerAgent = CustomerAgent.new(sim, random)
	guest.paid = paid
	guest.vibe_review_bonus = bonus
	guest.vibe_theme_label = label
	sim.customer_left.emit(guest, &"happy")


func _side_effects() -> Dictionary:
	return {"books": Economy._capture_save(), "rng": GameState._capture_save(),
		"clock": Clock.sim.to_dict(), "speed": Clock.speed, "saved": _saved_text()}


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _frames(count: int) -> void:
	for _frame: int in count:
		await (Engine.get_main_loop() as SceneTree).process_frame
