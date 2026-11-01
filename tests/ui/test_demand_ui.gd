extends TestCase
## Independent report data/text checks and real scaled-window presentation.
## The growth values in layout tests are explicit presentation fixtures.

const HUD: PackedScene = preload("res://src/ui/hud.tscn")
const REPORT: PackedScene = preload("res://src/ui/evening_report.tscn")
const MAIN: PackedScene = preload("res://src/world/main.tscn")
const FACTORS: Array[String] = ["reputation", "word_of_mouth", "menu", "vibe", "curb_appeal", "total"]

var _nodes: Array[Node] = []
var _old_clock: Dictionary = {}
var _old_books: Dictionary = {}
var _old_providers: Dictionary = {}
var _old_rngs: Dictionary[StringName, RandomNumberGenerator] = {}
var _old_seed: int


func before_each() -> void:
	_old_clock = {"sim": Clock.sim, "speed": Clock.speed, "last_speed": Clock._last_non_zero_speed,
		"accumulator": Clock._accumulator, "world": Clock.attached_world, "driver": Clock.tick_driver,
		"driven_tick": Clock.driven_world_tick, "processing": Clock.is_processing()}
	_old_books = {"ledger": Economy.ledger, "stock": Economy.stock, "loan": Economy.loan}
	_old_providers = SaveSystem._providers.duplicate()
	_old_seed = GameState.master_seed
	_old_rngs = GameState._rngs.duplicate()
	Clock.set_process(false)
	Clock.attach_world(null)
	Clock.sim = SimClock.new()
	Clock.set_speed(0)
	Economy.reset(1234)
	GameState.new_run(7)


func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	Clock.attach_world(_old_clock["world"], _old_clock["driver"])
	Clock.sim = _old_clock["sim"]
	Clock.set_speed(int(_old_clock["speed"]))
	Clock._last_non_zero_speed = int(_old_clock["last_speed"])
	Clock._accumulator = float(_old_clock["accumulator"])
	Clock.driven_world_tick = int(_old_clock["driven_tick"])
	Clock.set_process(bool(_old_clock["processing"]))
	Economy.ledger = _old_books["ledger"]
	Economy.stock = _old_books["stock"]
	Economy.loan = _old_books["loan"]
	GameState.master_seed = _old_seed
	GameState._rngs = _old_rngs
	SaveSystem._providers = _old_providers


func test_forecast_assignment_json_roundtrip_and_output_are_detached() -> void:
	var source: Dictionary = _forecast()
	source["private_state"] = {"renown": 90.0}
	var report: DayReport = DayReport.new()
	report.day = 3
	report.demand_forecast = source
	source["menu"] = 9.0
	assert_almost_eq(float(report.demand_forecast["menu"]), 1.0)
	assert_false(report.demand_forecast.has("private_state"), "only forecast primitives join historical reports")
	var snapshot: Dictionary = report.to_dict()
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(snapshot)))
	assert_eq(restored.demand_forecast, _forecast())
	snapshot["demand_forecast"]["total"] = 9.0
	assert_almost_eq(float(report.demand_forecast["total"]), 1.2)
	assert_almost_eq(float(restored.demand_forecast["total"]), 1.2)
	var incoming: Dictionary = report.to_dict()
	var copy: DayReport = DayReport.from_dict(incoming)
	incoming["demand_forecast"]["expected_guests"] = 999
	assert_eq(copy.demand_forecast["expected_guests"], 28)
	assert_eq(DayReport.from_dict({"day": 3}).demand_forecast, {})


func test_optional_malformed_forecast_is_omitted_without_losing_report_finances() -> void:
	var invalid: Array[Variant] = [null, [], "forecast", {}]
	for key: String in FACTORS:
		var missing: Dictionary = _forecast()
		missing.erase(key)
		invalid.append(missing)
		for bad: Variant in [0.0, -1.0, NAN, INF, "1.2", true]:
			var broken: Dictionary = _forecast()
			broken[key] = bad
			invalid.append(broken)
	for key: String in ["day", "expected_guests"]:
		for bad: Variant in [-1, 0.5, NAN, INF, "2", true, 9007199254740992]:
			var broken: Dictionary = _forecast()
			broken[key] = bad
			invalid.append(broken)
	var zero_day: Dictionary = _forecast()
	zero_day["day"] = 0
	invalid.append(zero_day)
	for value: Variant in invalid:
		var report: DayReport = DayReport.from_dict({"day": 3, "income": {"sale": 50},
			"costs": {"wages": 20}, "demand_forecast": value})
		assert_eq(report.demand_forecast, {})
		assert_eq(report.profit(), 30, "optional forecast corruption cannot discard the day's books")
	var zero_guests: Dictionary = _forecast()
	zero_guests["day"] = 4.0
	zero_guests["expected_guests"] = 0.0
	assert_eq(DayReport.public_demand_forecast(zero_guests)["expected_guests"], 0)


func test_plain_percentages_keep_individual_effects_distinct_from_overall_demand() -> void:
	assert_eq(DemandText.change_text(1.004), "no change")
	assert_eq(DemandText.change_text(0.996), "no change")
	assert_eq(DemandText.change_text(1.006), "+1%")
	assert_eq(DemandText.change_text(0.994), "−1%")
	assert_eq(DemandText.factor_label(&"private_renown"), "")
	var forecast: Dictionary = _forecast()
	forecast["reputation"] = 1.5
	forecast["word_of_mouth"] = 1.5
	forecast["total"] = 2.25
	assert_eq(DemandText.forecast_summary(forecast), "About 28 guests expected (demand +125%)")
	assert_eq(DemandText.factor_lines(forecast), PackedStringArray([
		"Reputation: +50%", "Word of mouth: +50%", "Menu variety: no change",
		"Vibe: no change", "Curb appeal: no change"]))
	assert_false(DemandText.forecast_note(forecast).contains("limit"), "uncapped growth needs no limit warning")
	forecast["reputation"] = 1.6
	forecast["word_of_mouth"] = 1.8
	forecast["menu"] = 1.3
	forecast["vibe"] = 1.15
	forecast["total"] = 3.0
	assert_eq(DemandText.forecast_summary(forecast), "About 28 guests expected (demand +200%)")
	assert_true(DemandText.forecast_note(forecast).contains("Crowd growth is at its limit."))
	forecast["expected_guests"] = 1
	assert_true(DemandText.forecast_summary(forecast).begins_with("About 1 guest expected"))
	assert_eq(DemandText.forecast_summary({}), "")
	assert_eq(DemandText.factor_lines({}), PackedStringArray())


func test_actual_evening_report_replaces_forecast_without_mutating_snapshot() -> void:
	var view: Control = REPORT.instantiate() as Control
	_nodes.append(view)
	var report: DayReport = DayReport.new()
	report.day = 3
	report.demand_forecast = _forecast()
	var before: Dictionary = report.to_dict()
	view.call("show_report", report)
	view.call("show_report", report)
	var section: Control = view.get_node("Panel/Scroll/Content/DemandForecast") as Control
	assert_true(section.visible)
	assert_eq((section.get_node("Heading") as Label).text, "Tomorrow's crowd")
	assert_eq((section.get_node("Summary") as Label).text, "About 28 guests expected (demand +20%)")
	assert_eq((section.get_node("Factors") as Label).text,
		"Reputation: +20%\nWord of mouth: no change\nMenu variety: no change\nVibe: no change\nCurb appeal: no change")
	assert_eq(report.to_dict(), before, "rendering and rebuilding the report is read-only")
	assert_eq(section.get_child_count(), 4, "repeated builds reuse one section")
	view.call("show_report", DayReport.from_dict({"day": 2}))
	assert_false(section.visible)
	assert_eq((section.get_node("Summary") as Label).text, "")
	assert_eq((section.get_node("Factors") as Label).text, "")
	assert_eq((section.get_node("Explanation") as Label).text, "")


func test_hud_growth_notice_uses_valid_history_and_only_appears_in_the_morning() -> void:
	var hud: CanvasLayer = HUD.instantiate() as CanvasLayer
	_nodes.append(hud)
	hud.call("refresh")
	var notice: Control = hud.get_node("DemandNotice") as Control
	var before_clock: Dictionary = Clock.sim.to_dict()
	var before_books: Dictionary = Economy._capture_save()
	var before_rng: Dictionary = GameState._capture_save()
	for pair: Vector2 in [Vector2(1.2, 1.0), Vector2(1.0, 1.0), Vector2(0.9, 1.0),
			Vector2(1.2, 0.0), Vector2(1.2, -1.0), Vector2(INF, 1.0), Vector2(1.2, NAN)]:
		hud.call("set_demand_status", pair.x, pair.y)
		assert_eq(notice.visible, pair == Vector2(1.2, 1.0))
	hud.call("set_demand_status", 1.2, 1.0)
	assert_eq((notice.get_node("Text") as Label).text, "Busier than yesterday")
	Clock.sim.phase = SimClock.Phase.OPEN
	hud.call("refresh")
	assert_false(notice.visible)
	Clock.sim.phase = SimClock.Phase.MORNING
	hud.call("refresh")
	assert_true(notice.visible)
	assert_eq(Clock.sim.to_dict(), before_clock)
	assert_eq(Economy._capture_save(), before_books)
	assert_eq(GameState._capture_save(), before_rng)


func test_growth_notice_and_real_morning_panels_fit_native_and_scaled_windows() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1600, 900)
	host.gui_embed_subwindows = true
	_nodes.append(host)
	tree.root.add_child(host)
	var window: Window = Window.new()
	window.borderless = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	host.add_child(window)
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	main.set("skip_owner_picker", true)
	main.set("guide_for_tools", true)
	main.set("new_game_seed_override", 7)
	window.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var initial: Dictionary = {"clock": Clock.sim.to_dict(), "books": Economy._capture_save(),
		"rng": GameState._capture_save()}
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		window.size = dimensions
		window.content_scale_size = Vector2i.ZERO
		window.content_scale_factor = 1.0 if dimensions.x == 1600 else 1.5
		hud.call("set_menu_notice", "Fries left today's menu: staff can't reach the fryer")
		hud.call("set_demand_status", 1.2, 1.0)
		main.call("refresh_hints")
		await _layout_frames()
		if dimensions.x == 1280:
			assert_almost_eq(window.get_visible_rect().size.x, 1280.0 / 1.5, 0.01)
			assert_almost_eq(window.get_visible_rect().size.y, 480.0, 0.01)
		var menu_note: Control = hud.get_node("MenuNotice") as Control
		var growth: Control = hud.get_node("DemandNotice") as Control
		assert_true(growth.is_visible_in_tree())
		_assert_enclosed(growth, window)
		_assert_enclosed(growth.get_node("Text") as Control, window)
		assert_true(growth.global_position.y >= menu_note.get_global_rect().end.y + 3.5)
		assert_true(float(hud.call("panel_top")) >= growth.get_global_rect().end.y + 11.5)
		var bubble: Control = main.get_node("Overlay/HintsBubble") as Control
		assert_true(bubble.is_visible_in_tree(), "the actual morning guide remains available")
		var card: Control = bubble.get_node("Bubble") as Control
		_assert_enclosed(card, window)
		assert_false(card.get_global_rect().intersects(growth.get_global_rect()), "guide text does not cover growth")
		for action: String in ["GotIt", "SkipGuide"]:
			var button: Button = card.get_node("Column/Actions/" + action) as Button
			_assert_enclosed(button, window)
			assert_false(button.disabled)
			assert_true(button.mouse_filter != Control.MOUSE_FILTER_IGNORE)
		for panel_name: String in ["menu", "staff", "goals"]:
			assert_true(main.call("set_" + panel_name + "_visible", true))
			await _layout_frames()
			var title: String = panel_name.capitalize() + "Panel"
			var panel: Control = main.get_node("Overlay/" + title + "/Panel") as Control
			assert_true(panel.is_visible_in_tree())
			_assert_enclosed(panel, window)
			assert_true(panel.global_position.y >= growth.get_global_rect().end.y + 11.5,
				panel_name + " clears both notices")
			assert_false(bubble.visible, "the guide yields to each actual panel")
			if panel_name != "goals":
				var outer_scroll: ScrollContainer = panel as ScrollContainer
				var list: Control = panel.get_node("Content/Body" if panel_name == "menu" else "Content/Scroll") as Control
				assert_true(list.size.y >= 99.5, "the list retains a usable scrolling area below the header")
				outer_scroll.ensure_control_visible(list)
				await _layout_frames()
				assert_true(panel.get_global_rect().intersects(list.get_global_rect()), "the actual list remains reachable")
				outer_scroll.scroll_vertical = 0
			assert_true(main.call("set_" + panel_name + "_visible", false))
		# Exercise the same HUD key strip without changing the shop's build state.
		hud.call("set_build_state", true, true)
		await _layout_frames()
		var hints: Control = hud.get_node("BuildHints") as Control
		_assert_enclosed(hints, window)
		assert_true(hints.global_position.y >= growth.get_global_rect().end.y + 5.5)
		hud.call("set_build_state", true, false)
	assert_eq(Clock.sim.to_dict(), initial["clock"], "layout controls never advance service")
	assert_eq(Economy._capture_save(), initial["books"])
	assert_eq(GameState._capture_save(), initial["rng"])


func _forecast() -> Dictionary:
	return {"day": 4, "expected_guests": 28, "reputation": 1.2, "word_of_mouth": 1.0,
		"menu": 1.0, "vibe": 1.0, "curb_appeal": 1.0, "total": 1.2}


func _layout_frames() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for frame: int in range(4):
		await tree.process_frame


func _assert_enclosed(control: Control, window: Window) -> void:
	assert_true(control.size.x > 0.0 and control.size.y > 0.0, String(control.name) + " has a drawn area")
	assert_true(window.get_visible_rect().grow(0.5).encloses(control.get_global_rect()),
		"%s stays inside logical window bounds: %s in %s" % [control.get_path(),
			control.get_global_rect(), window.get_visible_rect()])
	var drawn: Rect2 = control.get_viewport_transform() * control.get_global_rect()
	assert_true(Rect2(Vector2.ZERO, Vector2(window.size)).grow(0.5).encloses(drawn),
		"%s stays inside physical window bounds: %s in %s" % [control.get_path(), drawn, window.size])
