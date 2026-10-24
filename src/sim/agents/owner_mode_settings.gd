class_name OwnerModeSettings
extends RefCounted
## A mode-only save provider: no scene, world or agent references.

var _mode: StringName = &"rest"


func current_mode() -> StringName:
	return _mode


func assign_mode(mode: StringName) -> bool:
	if not OwnerAgent.MODES.has(mode):
		return false
	_mode = mode
	return true


func reset() -> void:
	_mode = &"rest"


func to_dict() -> Dictionary:
	return {"mode": String(_mode)}


## Invalid data leaves the previous value intact; startup handles failed loads.
func restore(data: Dictionary) -> bool:
	if data.size() != 1 or not data.has("mode") or not data["mode"] is String:
		return false
	return assign_mode(StringName(data["mode"]))
