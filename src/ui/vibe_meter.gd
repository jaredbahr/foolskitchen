class_name VibeMeter
extends HBoxContainer
## Compact, read-only presentation of the current derived restaurant vibe.

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const BAR_MIN_WIDTH: float = 64.0
const BAR_HEIGHT: float = 12.0
const POINT_DISPLAY_LIMIT: float = 999.0

var caption_label: Label
var score_bar: ProgressBar
var _caption: String = "Vibe —"
var _tooltip: String = "Vibe unavailable"
var _value: float = 0.0


func _init() -> void:
	theme = SHARED_THEME
	name = "VibeMeter"
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	tooltip_text = _tooltip
	add_theme_constant_override("separation", 8)

	caption_label = Label.new()
	caption_label.name = "CaptionLabel"
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_label.focus_mode = Control.FOCUS_NONE
	caption_label.text = _caption
	caption_label.tooltip_text = _tooltip
	add_child(caption_label)

	score_bar = ProgressBar.new()
	score_bar.name = "ScoreBar"
	score_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_bar.focus_mode = Control.FOCUS_NONE
	score_bar.custom_minimum_size = Vector2(BAR_MIN_WIDTH, BAR_HEIGHT)
	score_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_bar.min_value = 0.0
	score_bar.max_value = 100.0
	score_bar.step = 0.0
	score_bar.value = 0.0
	score_bar.show_percentage = false
	score_bar.tooltip_text = _tooltip
	add_child(score_bar)


## Updates presentation only. Gameplay effects remain owned by the sim model.
func set_vibe(result: VibeModel.Result) -> void:
	if not _is_presentable(result):
		_set_unavailable()
		return

	_value = clampf(result.score, 0.0, 100.0)
	_caption = "Vibe %d / 100" % roundi(_value)
	_tooltip = _make_tooltip(result)
	_apply_presentation()


## Stable data for native-control integration and capture assertions.
func view_state() -> Dictionary:
	return {
		"caption": _caption,
		"value": _value,
		"tooltip": _tooltip,
		"caption_rect": caption_label.get_global_rect(),
		"bar_rect": score_bar.get_global_rect(),
	}


func _is_presentable(result: VibeModel.Result) -> bool:
	if result == null or not result.valid or not is_finite(result.score):
		return false
	return is_finite(result.decor_points) \
		and is_finite(result.variety_points) \
		and is_finite(result.theme_points) \
		and is_finite(result.lamp_points) \
		and is_finite(result.crowding_penalty)


func _make_tooltip(result: VibeModel.Result) -> String:
	var theme_name: String = result.theme_label.strip_edges()
	if result.active_theme.is_empty() or theme_name.is_empty():
		theme_name = "No active theme"
	var decor: int = _display_points(result.decor_points)
	var variety: int = _display_points(result.variety_points)
	var theme_points: int = _display_points(result.theme_points)
	var lamps: int = _display_points(result.lamp_points)
	var crowding: int = _display_points(result.crowding_penalty)
	return "Decor %d, Variety %d, Theme: %s %s, Lamps %d, Crowding %d" % [
		decor,
		variety,
		theme_name,
		("+%d" % theme_points) if theme_points >= 0 else str(theme_points),
		lamps,
		-crowding,
	]


func _display_points(value: float) -> int:
	return roundi(clampf(value, -POINT_DISPLAY_LIMIT, POINT_DISPLAY_LIMIT))


func _set_unavailable() -> void:
	_value = 0.0
	_caption = "Vibe —"
	_tooltip = "Vibe unavailable"
	_apply_presentation()


func _apply_presentation() -> void:
	tooltip_text = _tooltip
	caption_label.text = _caption
	caption_label.tooltip_text = _tooltip
	score_bar.value = _value
	score_bar.tooltip_text = _tooltip
