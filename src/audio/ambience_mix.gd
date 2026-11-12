class_name AmbienceMix
extends RefCounted
## The mixing rules of the dining-room ambience (#366), as pure functions so
## they are tested without audio: how the chatter layers share out the crowd,
## how often cutlery clinks, and a clink's pitch and the gap to the next one.


## Level (0..1) of each chatter layer for `crowd` guests. `anchors` maps each
## available layer to the crowd size where it is at full level, in increasing
## order. Below the first anchor that layer fades in from silence; between two
## anchors the pair crossfades at equal power (their squares sum to 1); past
## the last, the last layer stays full. Layers not in `anchors` are absent.
static func chatter_levels(crowd: int, anchors: Dictionary[StringName, int]) -> Dictionary[StringName, float]:
	var levels: Dictionary[StringName, float] = {}
	var layers: Array[StringName] = []
	layers.assign(anchors.keys())
	for layer: StringName in layers:
		levels[layer] = 0.0
	if layers.is_empty() or crowd <= 0:
		return levels
	var first: int = maxi(anchors[layers[0]], 1)
	if crowd <= first:
		levels[layers[0]] = sqrt(float(crowd) / float(first))
		return levels
	for index: int in range(1, layers.size()):
		var low: int = anchors[layers[index - 1]]
		var high: int = anchors[layers[index]]
		if crowd <= high:
			var t: float = float(crowd - low) / float(maxi(high - low, 1))
			levels[layers[index - 1]] = sqrt(1.0 - t)
			levels[layers[index]] = sqrt(t)
			return levels
	levels[layers.back()] = 1.0
	return levels


## Scales chatter down under a playing jukebox.
static func chatter_gain(jukebox_playing: bool, duck_db: float) -> float:
	return db_to_linear(duck_db) if jukebox_playing else 1.0


## Moves a level toward its target by one frame of a `fade_seconds` fade.
static func fade(level: float, target: float, delta: float, fade_seconds: float) -> float:
	return move_toward(level, target, delta / maxf(fade_seconds, 0.001))


## Cutlery clinks per second for `eating` guests: grows with the room, capped
## so a packed room is a patter, not a wall of clanks.
static func cutlery_rate(eating: int, per_eater: float, max_rate: float) -> float:
	return minf(float(maxi(eating, 0)) * per_eater, max_rate)


## Seconds until the next cutlery clink at `rate` per second, drawn from the
## given presentation RNG (never the sim's): random gaps sound less mechanical.
## A zero rate never clinks.
static func next_gap(rng: RandomNumberGenerator, rate: float) -> float:
	if rate <= 0.0:
		return INF
	return -log(maxf(rng.randf(), 0.0001)) / rate


## A clink's pitch, within +-`spread` of normal.
static func pitch(rng: RandomNumberGenerator, spread: float) -> float:
	return 1.0 + rng.randf_range(-spread, spread)
