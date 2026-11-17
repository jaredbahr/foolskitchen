class_name Difficulty
extends RefCounted
## Per-run difficulty choice and next-morning change (D29, FK-177).

const MODES: Array[StringName] = [&"easy", &"normal", &"hard", &"custom"]
const AUTOMATION_KEYS: Array[StringName] = [
	&"buy", &"buy_premium", &"hire", &"wages", &"prices", &"jobs"
]
const DEFAULT_CUSTOM_FLAGS: Dictionary[StringName, bool] = {
	&"buy": true,
	&"buy_premium": true,
	&"hire": false,
	&"wages": false,
	&"prices": false,
	&"jobs": false,
}
const TUNING: Resource = preload("res://data/balance/difficulty.tres")

var _active_mode: StringName = &"normal"
var _custom_flags: Dictionary[StringName, bool] = DEFAULT_CUSTOM_FLAGS.duplicate()
var _pending_mode: StringName = &""
var _pending_effective_day: int = 0
var _pending_custom_flags: Dictionary[StringName, bool] = {}


func mode() -> StringName:
	return _active_mode


func pending_mode() -> StringName:
	return _pending_mode


func selected_custom_flags() -> Dictionary:
	if _pending_mode == &"custom":
		return _pending_custom_flags.duplicate(true)
	return _custom_flags.duplicate(true)


func active_custom_flags() -> Dictionary:
	return _custom_flags.duplicate(true)


## A non-mutating view of the rules that will apply on a forecast day.
func for_day(day: int) -> Difficulty:
	if _pending_mode.is_empty() or day < _pending_effective_day:
		return self
	var forecast: Difficulty = Difficulty.new()
	if not forecast.from_dict(to_dict()):
		return self
	forecast.apply_morning(day)
	return forecast


func start(mode_id: StringName, flags: Dictionary = {}) -> bool:
	if not MODES.has(mode_id):
		return false
	var decoded_flags: Dictionary[StringName, bool] = _custom_flags.duplicate()
	if mode_id == &"custom":
		if flags.is_empty():
			decoded_flags = DEFAULT_CUSTOM_FLAGS.duplicate()
		else:
			var parsed: Variant = _decode_flags(flags)
			if not parsed is Dictionary:
				return false
			decoded_flags = _typed_flags(parsed)
	_active_mode = mode_id
	if mode_id == &"custom":
		_custom_flags = decoded_flags
	_clear_pending()
	return true


func request_change(mode_id: StringName, flags: Dictionary, effective_day: int) -> bool:
	if not MODES.has(mode_id) or effective_day < 1:
		return false
	var decoded_flags: Dictionary[StringName, bool] = _custom_flags.duplicate()
	if mode_id == &"custom":
		if flags.is_empty():
			decoded_flags = _custom_flags.duplicate()
		else:
			var parsed: Variant = _decode_flags(flags)
			if not parsed is Dictionary:
				return false
			decoded_flags = _typed_flags(parsed)
	if mode_id == _active_mode and (mode_id != &"custom" or decoded_flags == _custom_flags):
		_clear_pending()
		return true
	_pending_mode = mode_id
	_pending_effective_day = effective_day
	if mode_id == &"custom":
		_pending_custom_flags = decoded_flags.duplicate()
	else:
		_pending_custom_flags = {}
	return true


func apply_morning(day: int) -> bool:
	if _pending_mode.is_empty() or day < _pending_effective_day:
		return false
	_active_mode = _pending_mode
	if _active_mode == &"custom":
		_custom_flags = _pending_custom_flags.duplicate()
	_clear_pending()
	return true


func auto(key: StringName) -> bool:
	var preset: DifficultyModeTuning = _tuning().mode_data(_active_mode)
	if preset == null:
		return false
	if _active_mode == &"custom":
		return bool(_custom_flags.get(key, false))
	match key:
		&"buy":
			return preset.auto_buy
		&"buy_premium":
			return preset.auto_buy_premium
		&"hire":
			return preset.auto_hire
		&"wages":
			return preset.auto_wages
		&"prices":
			return preset.auto_prices
		&"jobs":
			return preset.auto_jobs
	return false


func hire_wage_reserve_days() -> int:
	return _tuning().hire_wage_reserve_days


func mult(key: StringName) -> float:
	var preset: DifficultyModeTuning = _tuning().mode_data(_active_mode)
	if preset == null:
		return 1.0
	match key:
		&"patience":
			return preset.patience
		&"rent":
			return preset.rent
		&"messes":
			return preset.messes
	return 1.0


func review_bonus() -> float:
	var preset: DifficultyModeTuning = _tuning().mode_data(_active_mode)
	return preset.review_bonus if preset != null else 0.0


func to_dict() -> Dictionary:
	var result: Dictionary = {
		"version": 1,
		"mode": String(_active_mode),
		"custom_flags": _string_key_flags(_custom_flags),
	}
	if not _pending_mode.is_empty():
		result["pending"] = {
			"mode": String(_pending_mode),
			"effective_day": _pending_effective_day,
			"custom_flags": _string_key_flags(
				_pending_custom_flags if _pending_mode == &"custom" else _custom_flags
			),
		}
	return result


func from_dict(data: Dictionary) -> bool:
	if data.is_empty():
		_active_mode = &"normal"
		_custom_flags = DEFAULT_CUSTOM_FLAGS.duplicate()
		_clear_pending()
		return true
	if data.size() != 3 and data.size() != 4:
		return false
	if data.get("version") != 1 or not _is_integer(data.get("version")):
		return false
	var mode_value: Variant = data.get("mode")
	if not mode_value is String or not MODES.has(StringName(mode_value)):
		return false
	var flags_value: Variant = data.get("custom_flags")
	if not flags_value is Dictionary:
		return false
	var parsed_flags: Variant = _decode_flags(flags_value)
	if not parsed_flags is Dictionary:
		return false
	var parsed_mode: StringName = StringName(mode_value)
	var pending_mode_value: Variant = &""
	var pending_day: int = 0
	var pending_flags: Dictionary[StringName, bool] = parsed_flags.duplicate()
	if data.has("pending"):
		var pending_value: Variant = data.get("pending")
		if not pending_value is Dictionary:
			return false
		var pending: Dictionary = pending_value
		if pending.size() != 3:
			return false
		pending_mode_value = pending.get("mode")
		var day_value: Variant = pending.get("effective_day")
		var flags_pending_value: Variant = pending.get("custom_flags")
		if not pending_mode_value is String or not MODES.has(StringName(pending_mode_value)) \
				or not _is_integer(day_value) or int(day_value) < 1 \
				or not flags_pending_value is Dictionary:
			return false
		var parsed_pending: Variant = _decode_flags(flags_pending_value)
		if not parsed_pending is Dictionary:
			return false
		pending_flags = _typed_flags(parsed_pending)
		pending_day = int(day_value)
		if StringName(pending_mode_value) != &"custom" and pending_flags != parsed_flags:
			return false
	elif data.has("pending") or data.size() != 3:
		return false
	_active_mode = parsed_mode
	_custom_flags = parsed_flags
	if pending_mode_value is String and not String(pending_mode_value).is_empty():
		_pending_mode = StringName(pending_mode_value)
		_pending_effective_day = pending_day
		if _pending_mode == &"custom":
			_pending_custom_flags = pending_flags.duplicate()
		else:
			_pending_custom_flags = {}
	else:
		_clear_pending()
	return true


static func mode_name(mode_id: StringName) -> String:
	match mode_id:
		&"easy":
			return "Easy"
		&"normal":
			return "Normal"
		&"hard":
			return "Hard"
		&"custom":
			return "Custom"
	return ""


func _clear_pending() -> void:
	_pending_mode = &""
	_pending_effective_day = 0
	_pending_custom_flags = {}


func _tuning() -> DifficultyTuning:
	return TUNING as DifficultyTuning


static func _decode_flags(value: Dictionary) -> Variant:
	if value.size() != AUTOMATION_KEYS.size():
		return null
	var result: Dictionary[StringName, bool] = {}
	for key: StringName in AUTOMATION_KEYS:
		var flag: Variant = value.get(key, value.get(String(key), null))
		if not flag is bool:
			return null
		result[key] = flag
	for key: Variant in value.keys():
		if not AUTOMATION_KEYS.has(StringName(key)):
			return null
	return result


static func _typed_flags(value: Dictionary) -> Dictionary[StringName, bool]:
	var result: Dictionary[StringName, bool] = {}
	for key: StringName in AUTOMATION_KEYS:
		result[key] = bool(value[key])
	return result


static func _string_key_flags(flags: Dictionary[StringName, bool]) -> Dictionary:
	var result: Dictionary = {}
	for key: StringName in AUTOMATION_KEYS:
		result[String(key)] = flags.get(key, false)
	return result


static func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(value) and floorf(value) == value \
			and value >= -9007199254740991.0 and value <= 9007199254740991.0
	return false
