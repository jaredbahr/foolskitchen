class_name CommuteLines
extends Resource
## The jokey line shown after a van ride between restaurants (docs/CITY_MAP.md
## T5). Data only: the general lines live in data/city/commute_lines.tres, and
## each neighbourhood may add its own (NeighbourhoodDef.commute_line). The
## pick is pure and deterministic: the day and the destination decide it, with
## no random draw, and it never repeats the line shown just before.

const DEFAULT_PATH: String = "res://data/city/commute_lines.tres"
## How many times a neighbourhood's own line sits in the pool, so a trip there
## mentions the place more often than a general line comes up.
const AREA_WEIGHT: int = 3

## Lines that fit any trip.
@export var general: PackedStringArray = PackedStringArray()


## The shipped lines, or null when the file is missing or not commute lines.
static func load_default() -> CommuteLines:
	return load(DEFAULT_PATH) as CommuteLines if ResourceLoader.exists(DEFAULT_PATH) else null


## The general lines, then the destination's own line AREA_WEIGHT times.
func pool(area_line: String) -> PackedStringArray:
	var lines: PackedStringArray = general.duplicate()
	if not area_line.strip_edges().is_empty():
		for _copy: int in range(AREA_WEIGHT):
			lines.append(area_line)
	return lines


## The line for a ride on `day` to `destination` (`area_line` is that
## neighbourhood's own joke, "" for none). `previous` is the line shown last
## time: it is skipped when another line exists. "" when there are no lines.
func pick(day: int, destination: StringName, area_line: String, previous: String = "") -> String:
	var lines: PackedStringArray = pool(area_line)
	if lines.is_empty():
		return ""
	var start: int = mix(day, destination) % lines.size()
	for step: int in range(lines.size()):
		var line: String = lines[(start + step) % lines.size()]
		if line != previous:
			return line
	return lines[start]


## A fixed 32-bit scramble of the day and the neighbourhood's id: the same
## inputs always give the same number, on every machine and every run.
static func mix(day: int, destination: StringName) -> int:
	var h: int = 2166136261
	for code: int in String(destination).to_utf8_buffer():
		h = ((h ^ code) * 16777619) & 0xFFFFFFFF
	h = ((h ^ (day & 0xFFFFFFFF)) * 2654435761) & 0xFFFFFFFF
	h = (h ^ (h >> 15)) * 2246822519 & 0xFFFFFFFF
	return (h ^ (h >> 13)) & 0x7FFFFFFF
