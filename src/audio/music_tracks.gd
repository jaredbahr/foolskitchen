class_name MusicTracks
extends RefCounted
## Which music belongs to which part of the game, as one small table. A new
## track is a line in `BY_CONTEXT` and a `Sfx.set_music_context` call.
##
## - title: Kitchen Jamboree (the title screen)
## - service_day: Buoyant Swing Groove (from opening until dusk)
## - service_evening: Smoky Vamp (from dusk, when the shop lights come on)
## - anything else (morning, closed, the evening report): silence

const TITLE: StringName = &"title"
const SERVICE_DAY: StringName = &"service_day"
const SERVICE_EVENING: StringName = &"service_evening"

const BY_CONTEXT: Dictionary[StringName, AudioStream] = {
	TITLE: preload("res://assets/music/kitchen_jamboree.ogg"),
	SERVICE_DAY: preload("res://assets/music/buoyant_swing_groove.ogg"),
	SERVICE_EVENING: preload("res://assets/music/smoky_vamp.ogg"),
}

## The shop's own lights count as dusk once they reach this share of full
## (`DayLight.Look.interior_energy`, rising from 18:00 to about 20:30).
const EVENING_LIGHT: float = 0.25


## The track for `context`, or null when that part of the game has none.
static func track_for(context: StringName) -> AudioStream:
	return BY_CONTEXT.get(context)


static var _all_tracks: Array[AudioStream] = []


## Every mapped track, built once (the fade code asks every frame).
static func all_tracks() -> Array[AudioStream]:
	if _all_tracks.is_empty():
		for track: AudioStream in BY_CONTEXT.values():
			_all_tracks.append(track)
	return _all_tracks


## The context during service: daytime or evening by the shop light. Outside
## service there is none, so the music fades to silence.
static func service_context(open_for_service: bool, light: float) -> StringName:
	if not open_for_service:
		return &""
	return SERVICE_EVENING if light >= EVENING_LIGHT else SERVICE_DAY
