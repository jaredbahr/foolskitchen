class_name SoundThrottle
extends RefCounted
## Lets each cue through at most once per its minimum interval (#117).
## Times are passed in, so tests need no clock.

var _last: Dictionary[StringName, float] = {}


## True (and remembered) when `cue` may play at `now` seconds.
func allow(cue: StringName, now: float, interval: float) -> bool:
	if _last.has(cue) and now - _last[cue] < interval:
		return false
	_last[cue] = now
	return true


func reset() -> void:
	_last.clear()
