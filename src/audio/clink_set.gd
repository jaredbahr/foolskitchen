class_name ClinkSet
extends Resource
## One kind of table clink (#366): a few recorded variants of the same sound,
## how loud they play and how often the kind may repeat. Presentation only.

## The variants; one is picked at random each time (never the sim's random).
@export var streams: Array[AudioStream] = []
## Gain in dB at the Ambience bus.
@export var volume_db: float = 0.0
## Shortest gap in real seconds between two plays of this kind, so a burst of
## events in one frame (fast-forward) is one clink, not a pile of them.
@export var min_interval: float = 0.1


func is_valid(min_variants: int) -> bool:
	if streams.size() < min_variants or min_interval < 0.0:
		return false
	for stream: AudioStream in streams:
		if stream == null:
			return false
	return true
