class_name SettingsPanel
extends Control
## Reusable settings view; a caller chooses where to show it. Main/Menu and a
## future title screen can both instantiate this scene without owning storage.

signal close_requested

var _preferences: SettingsPreferences

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
	_scale.item_selected.connect(_on_scale_selected)
	_speed.item_selected.connect(_on_speed_selected)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_edge_pan.toggled.connect(_on_edge_pan_toggled)
	_close.pressed.connect(_on_close_pressed)
	if _preferences == null:
		_preferences = get_node_or_null("/root/Preferences") as SettingsPreferences
	_connect_preferences()
	refresh()


func _exit_tree() -> void:
	if _preferences != null and _preferences.changed.is_connected(_on_preference_changed):
		_preferences.changed.disconnect(_on_preference_changed)


func bind_preferences(model: SettingsPreferences) -> void:
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
	_status.text = "Changes are saved right away."


func _connect_preferences() -> void:
	if _preferences != null and not _preferences.changed.is_connected(_on_preference_changed):
		_preferences.changed.connect(_on_preference_changed)


func _on_preference_changed(_key: StringName) -> void:
	refresh()


func _on_master_changed(value: float) -> void:
	_record(_preferences != null and _preferences.set_volume_percent(&"Master", roundi(value)))


func _on_music_changed(value: float) -> void:
	_record(_preferences != null and _preferences.set_volume_percent(&"Music", roundi(value)))


func _on_effects_changed(value: float) -> void:
	_record(_preferences != null and _preferences.set_volume_percent(&"Effects", roundi(value)))


func _on_scale_selected(index: int) -> void:
	_record(_preferences != null and _preferences.set_ui_scale_percent(_scale.get_item_id(index)))


func _on_speed_selected(index: int) -> void:
	_record(_preferences != null and _preferences.set_default_open_speed(_speed.get_item_id(index)))


func _on_fullscreen_toggled(value: bool) -> void:
	_record(_preferences != null and _preferences.set_fullscreen_enabled(value))


func _on_edge_pan_toggled(value: bool) -> void:
	_record(_preferences != null and _preferences.set_edge_pan_enabled(value))


func _on_close_pressed() -> void:
	close_requested.emit()


func _record(saved: bool) -> void:
	if not saved:
		refresh()
		_status.text = "Could not save settings. Please try again."
