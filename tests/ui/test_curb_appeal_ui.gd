extends TestCase
## Read-only curb appeal wording, native controls and responsive Build integration.

const CATALOGUE: PackedScene = preload("res://src/ui/build_catalogue.tscn")
const REPORT: PackedScene = preload("res://src/ui/evening_report.tscn")

var _nodes: Array[Node] = []


func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func test_bonus_words_distinguish_bare_front_small_bonus_and_rounded_display() -> void:
	assert_eq(CurbAppealText.caption(45.25), "Curb appeal 45 / 100")
	assert_eq(CurbAppealText.bonus(1.0), "No walk-in bonus")
	assert_eq(CurbAppealText.bonus(1.004), "Less than +1% walk-ins")
	assert_eq(CurbAppealText.bonus(1.044), "About +4% walk-ins")
	assert_eq(CurbAppealText.bonus(1.046), "About +5% walk-ins")
	assert_eq(CurbAppealText.bonus(1.10), "About +10% walk-ins")
	assert_eq(CurbAppealText.forecast_line(1.0), "Curb appeal: no change")
	assert_eq(CurbAppealText.forecast_line(1.004), "Curb appeal: less than +1%")
	assert_eq(CurbAppealText.forecast_line(1.044), "Curb appeal +4%")
	assert_true(CurbAppealText.explanation(45.0, 1.044).contains("Actual arrivals can vary."))
	assert_false(CurbAppealText.explanation(45.0, 1.044).contains("curb_appeal"))


func test_meter_keeps_native_controls_and_exact_fraction_without_changing_inputs() -> void:
	var meter: CurbAppealMeter = CurbAppealMeter.new()
	_nodes.append(meter)
	assert_eq(meter.caption_label.text, "Curb appeal —")
	assert_eq(meter.bonus_label.text, "Bonus unavailable")
	assert_eq(meter.theme, load("res://src/ui/theme/main_theme.tres"))
	assert_eq(meter.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(meter.focus_mode, Control.FOCUS_NONE)
	assert_eq(meter.score_bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(meter.score_bar.show_percentage)
	var label_id: int = meter.caption_label.get_instance_id()
	var bar_id: int = meter.score_bar.get_instance_id()
	meter.set_appeal(45.25, 1.044)
	assert_eq(meter.caption_label.text, "Curb appeal 45 / 100")
	assert_eq(meter.bonus_label.text, "About +4% walk-ins")
	assert_almost_eq(meter.score_bar.value, 45.25, 0.000001)
	assert_almost_eq(float(meter.view_state()["multiplier"]), 1.044, 0.000001)
	assert_eq(meter.tooltip_text, CurbAppealText.explanation(45.25, 1.044))
	meter.set_appeal(0.0, 1.0)
	assert_eq(meter.caption_label.text, "Curb appeal 0 / 100")
	assert_eq(meter.bonus_label.text, "No walk-in bonus")
	assert_eq(meter.score_bar.value, 0.0)
	assert_eq(meter.caption_label.get_instance_id(), label_id)
	assert_eq(meter.score_bar.get_instance_id(), bar_id)


func test_nonfinite_or_invalid_inputs_clear_stale_bonus_without_a_fake_zero_score() -> void:
	var meter: CurbAppealMeter = CurbAppealMeter.new()
	_nodes.append(meter)
	for invalid: Vector2 in [Vector2(NAN, 1.04), Vector2(INF, 1.04),
		Vector2(45.0, NAN), Vector2(45.0, INF), Vector2(45.0, 0.0), Vector2(45.0, 0.9)]:
		meter.set_appeal(45.0, 1.044)
		meter.set_appeal(invalid.x, invalid.y)
		assert_eq(meter.caption_label.text, "Curb appeal —")
		assert_eq(meter.bonus_label.text, "Bonus unavailable")
		assert_eq(meter.score_bar.value, 0.0)
		assert_false(meter.view_state()["available"])
	meter.set_appeal(150.0, 1.1)
	assert_eq(meter.caption_label.text, "Curb appeal 100 / 100")
	meter.set_appeal(-5.0, 1.0)
	assert_eq(meter.caption_label.text, "Curb appeal 0 / 100")


func test_forecast_reuses_existing_factor_without_storing_or_inventing_a_score() -> void:
	var forecast: Dictionary = _forecast()
	var report: DayReport = DayReport.new()
	report.day = 2
	report.demand_forecast = forecast
	var before: Dictionary = report.to_dict()
	var lines: PackedStringArray = DemandText.factor_lines(forecast)
	assert_eq(lines.size(), DemandText.FACTOR_KEYS.size())
	assert_eq(lines[4], "Curb appeal +4%")
	var view: Control = REPORT.instantiate() as Control
	_nodes.append(view)
	view.call("show_report", report)
	var factors: Label = view.get_node("Panel/Scroll/Content/DemandForecast/Factors") as Label
	assert_true(factors.text.contains("Curb appeal +4%"))
	assert_false(factors.text.contains("/ 100"), "the forecast records a factor, not a curb score")
	assert_eq(report.to_dict(), before)
	assert_eq(forecast, _forecast())
	forecast["curb_appeal"] = 1.0
	assert_eq(DemandText.factor_lines(forecast)[4], "Curb appeal: no change")
	assert_eq(DemandText.factor_lines({}), PackedStringArray())


func test_camera_visibility_updates_reuse_catalogue_controls_at_native_and_scaled_widths() -> void:
	var catalogue: BuildCatalogue = CATALOGUE.instantiate() as BuildCatalogue
	var host: Control = Control.new()
	_nodes.append(host)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(host)
	host.size = Vector2(1600.0, 900.0)
	host.add_child(catalogue)
	catalogue.set_build_visible(true)
	catalogue.set_curb_appeal(45.25, 1.044, false)
	var vibe: VibeModel.Result = VibeModel.Result.new()
	vibe.valid = true
	vibe.score = 100.0
	vibe.active_theme = &"italian"
	vibe.theme_label = "Italian"
	catalogue.set_vibe(vibe)
	assert_false(catalogue.curb_appeal_meter.visible)
	var meter: CurbAppealMeter = catalogue.curb_appeal_meter
	var vibe_id: int = catalogue.vibe_meter.get_instance_id()
	var tool_id: int = catalogue.tool_buttons[0].get_instance_id()
	var category_id: int = catalogue.category_buttons[&"walls"].get_instance_id()
	var panel: Control = catalogue.get_node("Panel") as Control
	var scroll: ScrollContainer = catalogue.get_node("Panel/Margin/Rows/Scroll") as ScrollContainer
	for scale_factor: float in [1.0, 1.25]:
		for bounds: Vector2 in [Vector2(1280.0, 720.0), Vector2(1600.0, 900.0)]:
			host.size = bounds / scale_factor
			host.scale = Vector2.ONE * scale_factor
			catalogue.set_curb_appeal(45.25, 1.044, true)
			await tree.process_frame
			await tree.process_frame
			assert_true(meter.is_visible_in_tree())
			assert_true(panel.get_global_rect().end.x <= bounds.x)
			assert_true(panel.get_global_rect().end.y <= bounds.y)
			assert_true(scroll.get_global_rect().encloses(meter.get_global_rect()))
			assert_true(meter.get_global_rect().encloses(meter.caption_label.get_global_rect()))
			assert_true(meter.get_global_rect().encloses(meter.bonus_label.get_global_rect()))
			assert_false(catalogue.vibe_meter.get_global_rect().intersects(meter.get_global_rect()))
			catalogue.set_curb_appeal(45.25, 1.044, true)
			assert_eq(catalogue.curb_appeal_meter, meter)
			assert_eq(catalogue.vibe_meter.get_instance_id(), vibe_id)
			assert_eq(catalogue.tool_buttons[0].get_instance_id(), tool_id)
			assert_eq(catalogue.category_buttons[&"walls"].get_instance_id(), category_id)
			catalogue.set_curb_appeal(45.25, 1.044, false)
			assert_false(meter.visible)
	catalogue.set_curb_appeal(64.0, 1.064, false)
	catalogue.set_curb_appeal(64.0, 1.064, true)
	assert_eq(meter.caption_label.text, "Curb appeal 64 / 100")
	assert_eq(meter.bonus_label.text, "About +6% walk-ins")
	catalogue.set_build_visible(false)
	assert_false(meter.is_visible_in_tree())


func _forecast() -> Dictionary:
	return {"day": 3, "expected_guests": 28, "reputation": 1.2,
		"word_of_mouth": 1.0, "menu": 1.0, "vibe": 1.0,
		"curb_appeal": 1.044, "total": 1.2528}
