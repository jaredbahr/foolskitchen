class_name SoundTuning
extends Resource
## Which sound each game cue plays, how loud, and how often it may repeat
## (#117). Presentation only: nothing here touches the simulation.

## One-shot cues on the Effects bus (cue -> stream).
@export var cues: Dictionary[StringName, AudioStream] = {}
## Per-cue gain in dB; a missing cue plays at 0 dB.
@export var volume_db: Dictionary[StringName, float] = {}
## Shortest gap between two plays of a cue, in real seconds. Fast-forward can
## raise many events in one frame; this keeps them from piling up.
@export var min_interval: Dictionary[StringName, float] = {}
## Looped station and jukebox sounds on the Effects bus (loop -> stream). The
## room tone and chatter live in `AmbienceTuning` on the Ambience bus.
@export var loops: Dictionary[StringName, AudioStream] = {}
## Gain in dB of a loop at full level.
@export var loop_volume_db: Dictionary[StringName, float] = {}
## Small pitch steps cycled per repeated cue, so repeats don't sound identical.
## A fixed cycle, not a random draw.
@export var pitch_cycle: PackedFloat32Array = PackedFloat32Array([1.0])


func interval(cue: StringName) -> float:
	return maxf(float(min_interval.get(cue, 0.0)), 0.0)


func gain_db(cue: StringName) -> float:
	return float(volume_db.get(cue, 0.0))


func loop_gain_db(loop: StringName) -> float:
	return float(loop_volume_db.get(loop, 0.0))


## Every stream present and every number usable.
func is_valid() -> bool:
	if pitch_cycle.is_empty():
		return false
	for pitch: float in pitch_cycle:
		if pitch <= 0.0:
			return false
	for table: Dictionary in [cues, loops]:
		for key: StringName in table:
			if table[key] == null:
				return false
	return true
