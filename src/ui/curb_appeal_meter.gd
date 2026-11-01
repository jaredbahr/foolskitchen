class_name CurbAppealMeter
extends HBoxContainer
## Compact native controls; the caller owns scoring, balance and visibility.

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const BAR_MIN_WIDTH: float = 64.0
const BAR_HEIGHT: float = 12.0

var caption_label: Label
var bonus_label: Label
var score_bar: ProgressBar
var _available: bool = false
var _value: float = 0.0
var _multiplier: float = 1.0


func _init() -> void:
	theme = SHARED_THEME
	name = "CurbAppealMeter"
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	add_theme_constant_override("separation", 8)
	var captions: VBoxContainer = VBoxContainer.new()
	captions.name = "Captions"
	captions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	captions.add_theme_constant_override("separation", 0)
	add_child(captions)
	caption_label = Label.new()
	caption_label.name = "CaptionLabel"
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_label.focus_mode = Control.FOCUS_NONE
	caption_label.add_theme_font_size_override("font_size", 18)
	captions.add_child(caption_label)
	bonus_label = Label.new()
	bonus_label.name = "BonusLabel"
	bonus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bonus_label.focus_mode = Control.FOCUS_NONE
	bonus_label.add_theme_font_size_override("font_size", 16)
	captions.add_child(bonus_label)
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
	score_bar.show_percentage = false
	add_child(score_bar)
	_apply_presentation()


func set_appeal(score: float, multiplier: float) -> void:
	var available: bool = CurbAppealText.is_presentable(score, multiplier)
	var value: float = clampf(score, 0.0, 100.0) if available else 0.0
	var factor: float = multiplier if available else 1.0
	if available == _available and value == _value and factor == _multiplier:
		return
	_available = available
	_value = value
	_multiplier = factor
	_apply_presentation()


## Detached native presentation data for tests and visual review.
func view_state() -> Dictionary:
	return {"available": _available, "caption": caption_label.text,
		"bonus": bonus_label.text, "value": _value, "multiplier": _multiplier,
		"tooltip": tooltip_text, "caption_rect": caption_label.get_global_rect(),
		"bonus_rect": bonus_label.get_global_rect(), "bar_rect": score_bar.get_global_rect()}


func _apply_presentation() -> void:
	caption_label.text = CurbAppealText.caption(_value) if _available else CurbAppealText.UNAVAILABLE
	bonus_label.text = CurbAppealText.bonus(_multiplier) if _available else CurbAppealText.BONUS_UNAVAILABLE
	tooltip_text = CurbAppealText.explanation(_value, _multiplier) if _available \
		else CurbAppealText.explanation(NAN, NAN)
	caption_label.tooltip_text = tooltip_text
	bonus_label.tooltip_text = tooltip_text
	score_bar.tooltip_text = tooltip_text
	score_bar.value = _value
