class_name MusicTracks
extends RefCounted
## Which music belongs to which part of the game, as one small table. A new
## track is a line in `BY_CONTEXT` and a `Sfx.set_music_context` call.
##
## - title: Stir It Slow (the title screen and menus)
## - service_day: Buoyant Swing Groove, then Kitchen Jamboree, alternating
##   (from opening until dusk; when one ends the other follows)
## - service_evening: Smoky Vamp (from dusk, when the shop lights come on)
## - the evening report has no song: whatever service music was playing
##   carries on under it
## - anything else (morning, closed with no report open): silence

const TITLE: StringName = &"title"
const SERVICE_DAY: StringName = &"service_day"
const SERVICE_EVENING: StringName = &"service_evening"

## Each context's tracks in play order. One track loops; several play in turn
## (the next starts when one ends, wrapping round), always from the first.
const BY_CONTEXT: Dictionary[StringName, Array] = {
	TITLE: [preload("res://assets/music/stir_it_slow.ogg")],
	SERVICE_DAY: [
		preload("res://assets/music/buoyant_swing_groove.ogg"),
		preload("res://assets/music/kitchen_jamboree.ogg"),
	],
	SERVICE_EVENING: [preload("res://assets/music/smoky_vamp.ogg")],
}

## The shop's own lights count as dusk once they reach this share of full
## (`DayLight.Look.interior_energy`, rising from 18:00 to about 20:30).
const EVENING_LIGHT: float = 0.25


## The `index`th track of `context` (wrapping round), or null when that part of
## the game has none.
static func track_for(context: StringName, index: int = 0) -> AudioStream:
	var tracks: Array = BY_CONTEXT.get(context, [])
	if tracks.is_empty():
		return null
	return tracks[posmod(index, tracks.size())]


## How many tracks `context` plays in turn (0 for none).
static func track_count(context: StringName) -> int:
	return (BY_CONTEXT.get(context, []) as Array).size()


static var _all_tracks: Array[AudioStream] = []


## Every mapped track, built once (the fade code asks every frame).
static func all_tracks() -> Array[AudioStream]:
	if _all_tracks.is_empty():
		for tracks: Array in BY_CONTEXT.values():
			for track: AudioStream in tracks:
				_all_tracks.append(track)
	return _all_tracks


## True for a track that shares its context with others, so it plays once and
## hands over rather than looping.
static func in_playlist(track: AudioStream) -> bool:
	for tracks: Array in BY_CONTEXT.values():
		if tracks.size() > 1 and tracks.has(track):
			return true
	return false


## The context for the shop: daytime or evening by the shop light during
## service. The evening report has no song of its own: while it is open the shop
## counts as still serving, so the same light-based service track carries on
## under it. Outside service with no report open there is none, so the music
## fades to silence.
static func service_context(open_for_service: bool, light: float, report_open: bool = false) -> StringName:
	if not open_for_service and not report_open:
		return &""
	return SERVICE_EVENING if light >= EVENING_LIGHT else SERVICE_DAY
