class_name SettingsPreferences
extends Node
## Local player preferences. Unlike a game save, changes are written at once to
## user://settings.cfg and never enter SaveSystem's morning snapshot.

signal changed(key: StringName)

const DEFAULT_PATH: String = "user://settings.cfg"
const SECTION: String = "preferences"
const VERSION: int = 1
const UI_SCALES: Array[int] = [100, 125, 150]
const OPEN_SPEEDS: Array[int] = [1, 2]
const MISSING: String = "__missing_preference__"

var master_volume_percent: int = 100
var music_volume_percent: int = 100
var effects_volume_percent: int = 100
var ui_scale_percent: int = 100
var default_open_speed: int = 1
var fullscreen_enabled: bool = false
var edge_pan_enabled: bool = true

var _file_path: String = DEFAULT_PATH


func _init(path: String = DEFAULT_PATH) -> void:
	_file_path = path


func _ready() -> void:
	load_from_disk()
	apply_audio()
	apply_window(get_window())


## Missing, malformed or invalid files leave the complete default set intact.
## No settings read is allowed to mutate game saves or the active simulation.
func load_from_disk() -> bool:
	_reset_defaults()
	if not _file_path.begins_with("user://") or not FileAccess.file_exists(_file_path):
		return false
	var config: ConfigFile = ConfigFile.new()
	if config.load(_file_path) != OK:
		return false
	var version: Variant = config.get_value(SECTION, "version", MISSING)
	var master: Variant = config.get_value(SECTION, "master_volume", MISSING)
	var music: Variant = config.get_value(SECTION, "music_volume", MISSING)
	var effects: Variant = config.get_value(SECTION, "effects_volume", MISSING)
	var scale: Variant = config.get_value(SECTION, "ui_scale", MISSING)
	var speed: Variant = config.get_value(SECTION, "default_open_speed", MISSING)
	var fullscreen: Variant = config.get_value(SECTION, "fullscreen", MISSING)
	var edge_pan: Variant = config.get_value(SECTION, "edge_pan", MISSING)
	if not version is int or version != VERSION \
			or not _valid_volume(master) or not _valid_volume(music) \
			or not _valid_volume(effects) or not scale is int \
			or not UI_SCALES.has(scale) or not speed is int \
			or not OPEN_SPEEDS.has(speed) or not fullscreen is bool \
			or not edge_pan is bool:
		return false
	master_volume_percent = master
	music_volume_percent = music
	effects_volume_percent = effects
	ui_scale_percent = scale
	default_open_speed = speed
	fullscreen_enabled = fullscreen
	edge_pan_enabled = edge_pan
	return true


func save_to_disk() -> bool:
	if not _file_path.begins_with("user://"):
		return false
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, "version", VERSION)
	config.set_value(SECTION, "master_volume", master_volume_percent)
	config.set_value(SECTION, "music_volume", music_volume_percent)
	config.set_value(SECTION, "effects_volume", effects_volume_percent)
	config.set_value(SECTION, "ui_scale", ui_scale_percent)
	config.set_value(SECTION, "default_open_speed", default_open_speed)
	config.set_value(SECTION, "fullscreen", fullscreen_enabled)
	config.set_value(SECTION, "edge_pan", edge_pan_enabled)
	return config.save(_file_path) == OK


func volume_percent(bus: StringName) -> int:
	match bus:
		&"Master": return master_volume_percent
		&"Music": return music_volume_percent
		&"Effects": return effects_volume_percent
	return -1


func set_volume_percent(bus: StringName, percent: int) -> bool:
	if not _valid_volume(percent) or volume_percent(bus) < 0:
		return false
	var before: int = volume_percent(bus)
	if before == percent:
		return true
	_set_volume(bus, percent)
	if not save_to_disk():
		_set_volume(bus, before)
		return false
	apply_audio()
	changed.emit(bus)
	return true


func set_ui_scale_percent(percent: int) -> bool:
	if not UI_SCALES.has(percent):
		return false
	var before: int = ui_scale_percent
	if before == percent:
		return true
	ui_scale_percent = percent
	if not save_to_disk():
		ui_scale_percent = before
		return false
	if is_inside_tree():
		apply_window(get_window())
	changed.emit(&"ui_scale")
	return true


func set_default_open_speed(value: int) -> bool:
	if not OPEN_SPEEDS.has(value):
		return false
	var before: int = default_open_speed
	if before == value:
		return true
	default_open_speed = value
	if not save_to_disk():
		default_open_speed = before
		return false
	changed.emit(&"default_open_speed")
	return true


func set_fullscreen_enabled(value: bool) -> bool:
	var before: bool = fullscreen_enabled
	if before == value:
		return true
	fullscreen_enabled = value
	if not save_to_disk():
		fullscreen_enabled = before
		return false
	if is_inside_tree():
		apply_window(get_window())
	changed.emit(&"fullscreen")
	return true


func set_edge_pan_enabled(value: bool) -> bool:
	var before: bool = edge_pan_enabled
	if before == value:
		return true
	edge_pan_enabled = value
	if not save_to_disk():
		edge_pan_enabled = before
		return false
	changed.emit(&"edge_pan")
	return true


## Audio buses are authored in default_bus_layout.tres. A missing bus on an
## older project is ignored rather than causing an engine error.
func apply_audio() -> void:
	for bus: StringName in [&"Master", &"Music", &"Effects"]:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var linear: float = float(volume_percent(bus)) / 100.0
		AudioServer.set_bus_mute(index, is_zero_approx(linear))
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))


func apply_window(window: Window) -> void:
	if window == null:
		return
	window.content_scale_factor = float(ui_scale_percent) / 100.0
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		window.mode = Window.MODE_FULLSCREEN if fullscreen_enabled else Window.MODE_WINDOWED


func _set_volume(bus: StringName, percent: int) -> void:
	match bus:
		&"Master": master_volume_percent = percent
		&"Music": music_volume_percent = percent
		&"Effects": effects_volume_percent = percent


static func _valid_volume(value: Variant) -> bool:
	return value is int and value >= 0 and value <= 100


func _reset_defaults() -> void:
	master_volume_percent = 100
	music_volume_percent = 100
	effects_volume_percent = 100
	ui_scale_percent = 100
	default_open_speed = 1
	fullscreen_enabled = false
	edge_pan_enabled = true
