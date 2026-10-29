class_name SettingsPanel
extends Control
## Reusable settings view; a caller chooses where to show it. Main/Menu and a
## future title screen can both instantiate this scene without owning storage.

signal close_requested

const PLAY_GRID_LABEL: String = "Show floor grid while playing"
const BUILD_GRID_LABEL: String = "Show floor grid in Build"
const SAVE_DELAY: float = 0.5
const VIEW_MARGIN: float = 12.0

var _preferences: SettingsPreferences
var _save_delay: Timer
var _panel_top: float = VIEW_MARGIN

@onready var _panel: PanelContainer = $Panel
@onready var _column: VBoxContainer = $Panel/Column
@onready var _scroll: ScrollContainer = $Panel/Column/Scroll
@onready var _content: VBoxContainer = $Panel/Column/Scroll/Content

@onready var _master: HSlider = %MasterSlider
@onready var _music: HSlider = %MusicSlider
@onready var _effects: HSlider = %EffectsSlider
@onready var _master_value: Label = %MasterValue
@onready var _music_value: Label = %MusicValue
@onready var _effects_value: Label = %EffectsValue
@onready var _scale: OptionButton = %ScaleChoice
@onready var _speed: OptionButton = %SpeedChoice
@onready var _fullscreen_row: HBoxContainer = %FullscreenRow
@onready var _fullscreen: CheckButton = %FullscreenToggle
@onready var _edge_pan: CheckButton = %EdgePanToggle
@onready var _play_grid: CheckButton = %PlayGridToggle
@onready var _build_grid: CheckButton = %BuildGridToggle
@onready var _status: Label = %Status
@onready var _close: Button = %CloseButton


func _ready() -> void:
	_scale.add_item("100%", 100)
	_scale.add_item("125%", 125)
	_scale.add_item("150%", 150)
	_speed.add_item("1x", 1)
	_speed.add_item("2x", 2)
	_fullscreen_row.visible = not OS.has_feature("web")
	_master.value_changed.connect(_on_master_changed)
	_music.value_changed.connect(_on_music_changed)
	_effects.value_changed.connect(_on_effects_changed)
	for slider: HSlider in [_master, _music, _effects]:
		slider.drag_ended.connect(_on_volume_drag_ended)
	_save_delay = Timer.new()
	_save_delay.one_shot = true
	_save_delay.wait_time = SAVE_DELAY
	_save_delay.timeout.connect(_on_volume_save_timeout)
	add_child(_save_delay)
	_scale.item_selected.connect(_on_scale_selected)
	_speed.item_selected.connect(_on_speed_selected)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_edge_pan.toggled.connect(_on_edge_pan_toggled)
	_play_grid.text = PLAY_GRID_LABEL
	_build_grid.text = BUILD_GRID_LABEL
	_play_grid.toggled.connect(_on_play_grid_toggled)
	_build_grid.toggled.connect(_on_build_grid_toggled)
	_close.pressed.connect(_on_close_pressed)
	resized.connect(_layout_card)
	visibility_changed.connect(_on_visibility_changed)
	_content.minimum_size_changed.connect(_layout_card)
	get_viewport().size_changed.connect(_layout_card)
	if _preferences == null:
		_preferences = get_node_or_null("/root/Preferences") as SettingsPreferences
	_connect_preferences()
	refresh()
	_layout_card()


func _exit_tree() -> void:
	flush_pending_changes()
	if get_viewport().size_changed.is_connected(_layout_card):
		get_viewport().size_changed.disconnect(_layout_card)
	if _preferences != null and _preferences.changed.is_connected(_on_preference_changed):
		_preferences.changed.disconnect(_on_preference_changed)


func bind_preferences(model: SettingsPreferences) -> void:
	flush_pending_changes()
	if _preferences != null and _preferences.changed.is_connected(_on_preference_changed):
		_preferences.changed.disconnect(_on_preference_changed)
	_preferences = model
	if is_node_ready():
		_connect_preferences()
		refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	if _preferences == null:
		_status.text = "Settings are unavailable."
		return
	_master.set_value_no_signal(_preferences.master_volume_percent)
	_music.set_value_no_signal(_preferences.music_volume_percent)
	_effects.set_value_no_signal(_preferences.effects_volume_percent)
	_master_value.text = "%d%%" % _preferences.master_volume_percent
	_music_value.text = "%d%%" % _preferences.music_volume_percent
	_effects_value.text = "%d%%" % _preferences.effects_volume_percent
	_scale.select(_scale.get_item_index(_preferences.ui_scale_percent))
	_speed.select(_speed.get_item_index(_preferences.default_open_speed))
	_fullscreen.set_pressed_no_signal(_preferences.fullscreen_enabled)
	_edge_pan.set_pressed_no_signal(_preferences.edge_pan_enabled)
	_play_grid.set_pressed_no_signal(_preferences.play_grid_enabled)
	_build_grid.set_pressed_no_signal(_preferences.build_grid_enabled)
	_status.text = "Changes are saved automatically."
	_layout_card()


## Main supplies the settled HUD bottom, including any wrapped action rows.
func set_panel_top(top: float) -> void:
	_panel_top = maxf(VIEW_MARGIN, top)
	_layout_card()


## Called by Close, Esc and any session path that replaces this view.
func flush_pending_changes() -> bool:
	if _save_delay != null:
		_save_delay.stop()
	return _preferences == null or _preferences.flush_pending_volumes()


func _layout_card() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = size
	var top: float = minf(_panel_top, maxf(VIEW_MARGIN, viewport_size.y - VIEW_MARGIN))
	var available: Vector2 = Vector2(viewport_size.x - VIEW_MARGIN * 2.0,
		viewport_size.y - top - VIEW_MARGIN)
	var padding: Vector2 = _panel.get_theme_stylebox("panel").get_minimum_size()
	var footer_height: float = _close.get_combined_minimum_size().y \
		+ float(_column.get_theme_constant("separation"))
	var natural: Vector2 = _content.get_combined_minimum_size()
	var content_height: float = minf(natural.y,
		maxf(0.0, available.y - padding.y - footer_height))
	var bar_width: float = _scroll.get_v_scroll_bar().get_combined_minimum_size().x \
		if content_height < natural.y else 0.0
	var content_width: float = minf(natural.x + bar_width,
		maxf(0.0, available.x - padding.x))
	_scroll.custom_minimum_size = Vector2(content_width, content_height)
	var card_size: Vector2 = Vector2(content_width + padding.x,
		content_height + footer_height + padding.y)
	_panel.size = card_size
	_panel.position = Vector2((viewport_size.x - card_size.x) * 0.5,
		top + maxf(0.0, (available.y - card_size.y) * 0.5))


func _connect_preferences() -> void:
	if _preferences != null and not _preferences.changed.is_connected(_on_preference_changed):
		_preferences.changed.connect(_on_preference_changed)


func _on_preference_changed(_key: StringName) -> void:
	refresh()


func _on_master_changed(value: float) -> void:
	_preview_volume(&"Master", value)


func _on_music_changed(value: float) -> void:
	_preview_volume(&"Music", value)


func _on_effects_changed(value: float) -> void:
	_preview_volume(&"Effects", value)


func _preview_volume(bus: StringName, value: float) -> void:
	if _preferences == null or not _preferences.preview_volume_percent(bus, roundi(value)):
		_record(false)
		return
	_save_delay.start()
	_status.text = "Changes are saved automatically."


func _on_volume_drag_ended(_value_changed: bool) -> void:
	_record(flush_pending_changes())


func _on_volume_save_timeout() -> void:
	_record(flush_pending_changes())


func _on_scale_selected(index: int) -> void:
	_record(_preferences != null and _preferences.set_ui_scale_percent(_scale.get_item_id(index)))


func _on_speed_selected(index: int) -> void:
	_record(_preferences != null and _preferences.set_default_open_speed(_speed.get_item_id(index)))


func _on_fullscreen_toggled(value: bool) -> void:
	_record(_preferences != null and _preferences.set_fullscreen_enabled(value))


func _on_edge_pan_toggled(value: bool) -> void:
	_record(_preferences != null and _preferences.set_edge_pan_enabled(value))


func _on_play_grid_toggled(value: bool) -> void:
	_record(_preferences != null and _preferences.set_play_grid_enabled(value))


func _on_build_grid_toggled(value: bool) -> void:
	_record(_preferences != null and _preferences.set_build_grid_enabled(value))


func _on_close_pressed() -> void:
	if flush_pending_changes():
		close_requested.emit()
	else:
		_record(false)


func _on_visibility_changed() -> void:
	if visible:
		_layout_card()
	else:
		flush_pending_changes()


func _record(saved: bool) -> void:
	if not saved:
		refresh()
		_status.text = "Could not save settings. Please try again."
