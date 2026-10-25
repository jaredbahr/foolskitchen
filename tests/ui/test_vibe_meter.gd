extends TestCase
## Native read-only meter controls; pixel appearance requires a capture.

var _meter: VibeMeter


func before_each() -> void:
	_meter = VibeMeter.new()


func after_each() -> void:
	if is_instance_valid(_meter):
		_meter.free()
	_meter = null


func test_initial_state_is_neutral_and_children_are_native_read_only_controls() -> void:
	assert_eq(_meter.name, &"VibeMeter")
	assert_eq(_meter.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(_meter.focus_mode, Control.FOCUS_NONE)
	assert_eq(_meter.get_child_count(), 2)
	assert_eq(_meter.get_child(0).name, &"CaptionLabel")
	assert_eq(_meter.get_child(1).name, &"ScoreBar")
	assert_eq(_meter.caption_label.text, "Vibe —")
	assert_eq(_meter.score_bar.min_value, 0.0)
	assert_eq(_meter.score_bar.max_value, 100.0)
	assert_eq(_meter.score_bar.step, 0.0)
	assert_eq(_meter.score_bar.value, 0.0)
	assert_false(_meter.score_bar.show_percentage)
	assert_eq(_meter.score_bar.custom_minimum_size.x, 64.0)
	assert_eq(_meter.theme, load("res://src/ui/theme/main_theme.tres"))
	assert_eq(_meter.caption_label.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_meter.score_bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_meter.tooltip_text, "Vibe unavailable")
	assert_eq(_meter.caption_label.tooltip_text, "Vibe unavailable")
	assert_eq(_meter.score_bar.tooltip_text, "Vibe unavailable")
	assert_eq(_meter.caption_label.focus_mode, Control.FOCUS_NONE)
	assert_eq(_meter.score_bar.focus_mode, Control.FOCUS_NONE)


func test_hoverable_meter_root_owns_native_tooltip_without_focus_or_mouse_consumption() -> void:
	assert_ne(_meter.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the native tooltip target must receive hover")
	assert_false(_meter.tooltip_text.is_empty())
	assert_eq(_meter.tooltip_text, "Vibe unavailable")
	assert_eq(_meter.mouse_filter, Control.MOUSE_FILTER_PASS,
		"hover and clicks continue to the owning parent")
	assert_eq(_meter.focus_mode, Control.FOCUS_NONE)
	assert_eq(_meter.caption_label.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_meter.score_bar.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_valid_result_updates_caption_bar_tooltip_and_view_state() -> void:
	_meter.set_vibe(_result(42.4321))
	assert_eq(_meter.caption_label.text, "Vibe 42 / 100")
	assert_almost_eq(_meter.score_bar.value, 42.4321, 0.000001)
	assert_eq(_meter.caption_label.tooltip_text,
		"Decor 32, Variety 18, Theme: Cosy +10, Lamps 6, Crowding -4")
	assert_eq(_meter.tooltip_text, _meter.caption_label.tooltip_text)
	assert_eq(_meter.score_bar.tooltip_text, _meter.caption_label.tooltip_text)
	var state: Dictionary = _meter.view_state()
	assert_eq(state["caption"], "Vibe 42 / 100")
	assert_almost_eq(float(state["value"]), 42.4321, 0.000001)
	assert_eq(state["tooltip"], _meter.caption_label.tooltip_text)
	assert_true(state.has("caption_rect"))
	assert_true(state.has("bar_rect"))


func test_updates_reuse_stable_children_and_theme_uses_display_label() -> void:
	var caption_id: int = _meter.caption_label.get_instance_id()
	var bar_id: int = _meter.score_bar.get_instance_id()
	var result: VibeModel.Result = _result(63.0)
	result.active_theme = &"italian"
	result.theme_label = "Italian"
	_meter.set_vibe(result)
	assert_eq(_meter.caption_label.get_instance_id(), caption_id)
	assert_eq(_meter.score_bar.get_instance_id(), bar_id)
	assert_true(_meter.caption_label.tooltip_text.contains("Theme: Italian +10"))
	assert_false(_meter.caption_label.tooltip_text.contains("italian"))
	result.theme_label = ""
	_meter.set_vibe(result)
	assert_true(_meter.caption_label.tooltip_text.contains("Theme: No active theme +10"))


func test_score_is_clamped_and_tooltip_amounts_are_bounded() -> void:
	var result: VibeModel.Result = _result(150.0)
	result.decor_points = 5000.0
	result.variety_points = -5000.0
	result.theme_points = 2500.0
	result.lamp_points = 2500.0
	result.crowding_penalty = 2500.0
	_meter.set_vibe(result)
	assert_eq(_meter.caption_label.text, "Vibe 100 / 100")
	assert_eq(_meter.score_bar.value, 100.0)
	assert_eq(_meter.caption_label.tooltip_text,
		"Decor 999, Variety -999, Theme: Cosy +999, Lamps 999, Crowding -999")


func test_invalid_or_non_finite_result_returns_to_neutral_fallback() -> void:
	_meter.set_vibe(_result(28.0))
	var invalid: VibeModel.Result = _result(88.0)
	invalid.valid = false
	_meter.set_vibe(invalid)
	_assert_unavailable()

	var non_finite_score: VibeModel.Result = _result(88.0)
	non_finite_score.score = INF
	_meter.set_vibe(non_finite_score)
	_assert_unavailable()

	var non_finite_breakdown: VibeModel.Result = _result(88.0)
	non_finite_breakdown.decor_points = INF
	_meter.set_vibe(non_finite_breakdown)
	_assert_unavailable()

	_meter.set_vibe(null)
	_assert_unavailable()


func _result(score: float) -> VibeModel.Result:
	var result: VibeModel.Result = VibeModel.Result.new()
	result.valid = true
	result.score = score
	result.decor_points = 32.0
	result.variety_points = 18.0
	result.theme_points = 10.0
	result.lamp_points = 6.0
	result.crowding_penalty = 4.0
	result.active_theme = &"cosy"
	result.theme_label = "Cosy"
	return result


func _assert_unavailable() -> void:
	assert_eq(_meter.caption_label.text, "Vibe —")
	assert_eq(_meter.score_bar.value, 0.0)
	assert_eq(_meter.caption_label.tooltip_text, "Vibe unavailable")
	assert_eq(_meter.score_bar.tooltip_text, "Vibe unavailable")
