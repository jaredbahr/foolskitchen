class_name AmbienceTuning
extends Resource
## Every level of the dining-room ambience (#366) in one place: the room tone,
## the chatter layers and the table clinks. All of it plays on the Ambience bus,
## which the Settings Ambience slider controls. Presentation only.

const CHATTER_LAYERS: Array[StringName] = [&"chatter_light", &"chatter_busy", &"chatter_packed"]
const MIN_CLINK_VARIANTS: int = 4

## Looped ambience on the Ambience bus (loop -> stream). A chatter layer whose
## stream is still null is skipped: it plugs in when its file arrives.
@export var loops: Dictionary[StringName, AudioStream] = {}
## Gain in dB of a loop at full level.
@export var loop_volume_db: Dictionary[StringName, float] = {}
## Guests in the shop at which the room tone reaches full level.
@export var room_tone_full_guests: int = 14
## Guests at which each chatter layer (light, busy, packed) is at its full
## level; between two of them the layers crossfade. Increasing.
@export var chatter_guests: PackedInt32Array = PackedInt32Array([2, 8, 16])
## Chatter level change per real second, so it swells and fades smoothly and
## dies away over a few seconds at closing.
@export var chatter_fade_seconds: float = 3.0
## Chatter sits this far lower while a counted jukebox is playing, as the
## music theme does, so the jukebox stays audible.
@export var chatter_jukebox_duck_db: float = -8.0

## Table clinks by kind: plate, cutlery, dish_stack, sink, glass.
@export var clinks: Dictionary[StringName, ClinkSet] = {}
## Each clink plays at a pitch within this fraction of normal (0.05 = +-5%).
@export var pitch_spread: float = 0.05
## How strongly a clink pans toward its table's side of the screen (0 = none).
@export var panning_strength: float = 1.0
## Cutlery clinks per real second for each guest eating, and the most per
## second however full the room is.
@export var cutlery_per_eater: float = 0.08
@export var cutlery_max_rate: float = 1.2


func loop_gain_db(loop: StringName) -> float:
	return float(loop_volume_db.get(loop, 0.0))


func clink(kind: StringName) -> ClinkSet:
	return clinks.get(kind) as ClinkSet


## The chatter layers that have a file, as the crowd sizes they peak at, in
## layer order. A missing layer drops out and its neighbours cover it.
func chatter_anchors() -> Dictionary[StringName, int]:
	var anchors: Dictionary[StringName, int] = {}
	for index: int in CHATTER_LAYERS.size():
		var layer: StringName = CHATTER_LAYERS[index]
		if loops.get(layer) != null and index < chatter_guests.size():
			anchors[layer] = chatter_guests[index]
	return anchors


## Every number usable and every clink kind with enough variants.
func is_valid() -> bool:
	if room_tone_full_guests < 1 or chatter_fade_seconds <= 0.0 or chatter_guests.size() != CHATTER_LAYERS.size():
		return false
	for index: int in chatter_guests.size():
		if chatter_guests[index] < 1 or (index > 0 and chatter_guests[index] <= chatter_guests[index - 1]):
			return false
	if pitch_spread < 0.0 or pitch_spread >= 0.5 or cutlery_per_eater < 0.0 or cutlery_max_rate < 0.0:
		return false
	if loops.get(&"room_tone") == null:
		return false
	for kind: StringName in clinks:
		var clink_set: ClinkSet = clinks[kind]
		if clink_set == null or not clink_set.is_valid(MIN_CLINK_VARIANTS):
			return false
	return true
