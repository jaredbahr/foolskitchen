class_name MusicTracks
extends RefCounted
## To add a theme track, drop its .ogg in assets/music/ with loop=true in its
## .import, then add its preload to BY_THEME. A theme picks one track per day.
##
## - title: Stir It Slow (the title screen and menus)
## - service_day: Buoyant Swing Groove, then Kitchen Jamboree, alternating
##   (from opening until dusk; when one ends the other follows)
## - service_evening: Smoky Vamp (from dusk, when the shop lights come on)
## - the evening report has no song: whatever service music was playing
##   carries on under it
## - Seaside Cliff plays Buoyant Sea Shanty all service, whatever the theme (#625)
## - anything else (morning, closed with no report open): silence

const TITLE: StringName = &"title"
const MORNING: StringName = &"morning"
const REPORT: StringName = &"report"
const SERVICE_DAY: StringName = &"service_day"
const SERVICE_EVENING: StringName = &"service_evening"

## Each context's tracks in play order. One track loops; several play in turn
## (the next starts when one ends, wrapping round), always from the first.
const BY_CONTEXT: Dictionary[StringName, Array] = {
	TITLE: [preload("res://assets/music/stir_it_slow.ogg")],
	MORNING: [],
	REPORT: [],
	SERVICE_DAY: [
		preload("res://assets/music/buoyant_swing_groove.ogg"),
		preload("res://assets/music/kitchen_jamboree.ogg"),
	],
	SERVICE_EVENING: [preload("res://assets/music/smoky_vamp.ogg")],
}

const BY_THEME: Dictionary[StringName, Array] = {
	&"bar": [preload("res://assets/music/smoky_vamp.ogg")],
	&"diner": [preload("res://assets/music/diner_boogie.ogg")],
	&"cafe": [preload("res://assets/music/coffee_shop_morning.ogg")],
	&"seafood": [preload("res://assets/music/coastal_afternoon.ogg")],
	SITE_CLIFF: [preload("res://assets/music/buoyant_sea_shanty.ogg")],
}

## Site music (#625): a lot with its own song plays it whatever the vibe theme.
## The value is a BY_THEME key no vibe theme can have, so the day-long single
## loop rules for themes apply unchanged. Other lots never reach these entries.
const SITE_CLIFF: StringName = &"site_seaside_cliff"
const BY_LOT: Dictionary[StringName, StringName] = {
	&"seaside_cliff": SITE_CLIFF,
}

## The shop's own lights count as dusk once they reach this share of full
## (`DayLight.Look.interior_energy`, rising from 18:00 to about 20:30).
const EVENING_LIGHT: float = 0.25


## The `index`th track of `context` (wrapping round), or null when that part of
## the game has none.
static func track_for(context: StringName, index: int = 0) -> AudioStream:
	var tracks: Array = BY_THEME[context] if BY_THEME.has(context) else BY_CONTEXT.get(context, [])
	return track_at(tracks, index)


## Day numbers index theme lists the same way playlist indices wrap.
static func track_at(tracks: Array, index: int) -> AudioStream:
	if tracks.is_empty():
		return null
	return tracks[posmod(index, tracks.size())]


## How many tracks a regular context plays in turn (0 for none).
static func track_count(context: StringName) -> int:
	return (BY_CONTEXT.get(context, []) as Array).size()


static var _all_tracks: Array[AudioStream] = []


## Every mapped track, built once (the fade code asks every frame).
static func all_tracks() -> Array[AudioStream]:
	if _all_tracks.is_empty():
		for tracks: Array in BY_CONTEXT.values() + BY_THEME.values():
			for track: AudioStream in tracks:
				if not _all_tracks.has(track):
					_all_tracks.append(track)
	return _all_tracks


## True for a track that shares its context with others, so it plays once and
## hands over rather than looping.
static func in_playlist(track: AudioStream) -> bool:
	for tracks: Array in BY_CONTEXT.values():
		if tracks.size() > 1 and tracks.has(track):
			return true
	return false


## A mapped room theme wins over the fallback, which follows the shop light.
## A lot's own song (BY_LOT) wins over both.
static func service_context(open_for_service: bool, light: float, theme: StringName = &"",
		lot: StringName = &"") -> StringName:
	if not open_for_service:
		return &""
	if BY_LOT.has(lot):
		return BY_LOT[lot]
	if BY_THEME.has(theme):
		return theme
	return SERVICE_EVENING if light >= EVENING_LIGHT else SERVICE_DAY
