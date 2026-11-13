class_name AutoPause
extends PanelContainer
## Only the player HUD can pause for public service events.

const COOLDOWN_MS: int = 30_000
const NONINTERACTIVE_SCRIPTS: Array[String] = ["run_tests.gd", "parse_all.gd", "balance_probe.gd"]

var _next_pause_at_ms: int = 0

@onready var _label: Label = $Text
@onready var _timer: Timer = $Timer


func activate() -> void:
	if not supports_runtime(DisplayServer.get_name(), OS.get_cmdline_args()):
		return
	EventBus.dish_sold_out.connect(_on_dish_sold_out)
	EventBus.health_inspector_arrived.connect(_on_health_inspector_arrived)
	EventBus.guest_left_angry.connect(_on_guest_left_angry)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_timer.timeout.connect(hide)


static func supports_runtime(display_driver: String, arguments: PackedStringArray) -> bool:
	if display_driver == "headless":
		return false
	for argument: String in arguments:
		if argument == "--":
			break
		var script_name: String = argument.trim_prefix("--script=").replace("\\", "/").get_file()
		if NONINTERACTIVE_SCRIPTS.has(script_name):
			return false
	return true


func _on_dish_sold_out(display_name: String) -> void:
	_try_pause(SettingsPreferences.PAUSE_ON_SOLD_OUT, "%s sold out" % display_name)


func _on_health_inspector_arrived() -> void:
	_try_pause(SettingsPreferences.PAUSE_ON_INSPECTOR, "Health inspector arrived")


func _on_guest_left_angry() -> void:
	_try_pause(SettingsPreferences.PAUSE_ON_ANGRY_GUEST, "A guest left angry")


func _try_pause(key: StringName, reason: String) -> void:
	if not _take_pause(Preferences, key, Clock.phase, Clock.speed, Time.get_ticks_msec()):
		return
	Clock.set_speed(0)
	_label.text = "Paused: %s" % reason
	show()
	_timer.start()


func _take_pause(preferences: SettingsPreferences, key: StringName, phase: SimClock.Phase,
		speed: int, now_ms: int) -> bool:
	if not preferences.auto_pause_enabled(key) or speed == 0 or now_ms < _next_pause_at_ms:
		return false
	if phase != SimClock.Phase.OPEN and phase != SimClock.Phase.LAST_ORDERS:
		return false
	_next_pause_at_ms = now_ms + COOLDOWN_MS
	return true


func _on_day_phase_changed(_day: int, phase: int) -> void:
	if phase == SimClock.Phase.MORNING or phase == SimClock.Phase.CLOSED:
		_timer.stop()
		hide()
