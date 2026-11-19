class_name CityMapDef
extends Resource
## The city's neighbourhoods (docs/CITY_MAP.md, D31): data only, authored in
## data/city/city_map.tres. Every lot on the property market, and the starter
## shop, stands in exactly one neighbourhood; `validate` checks that against
## the game's lots, so a new lot without a neighbourhood fails the data test.
## Pure reads with no script dependency but NeighbourhoodDef: lots come in as
## ids and names, and the shipped file is loaded by CityMap.load_default (a
## load() of the map's own file in here would be a script cycle, which leaks
## at exit). CityMap holds the rules that combine it with LotDefs and what the
## owner has.

const MAX_NAME_LENGTH: int = 40
const MAX_BLURB_LENGTH: int = 160
const MAX_COMMUTE_LINE_LENGTH: int = 120
const MAX_ID_LENGTH: int = 40
## The starter shop's lot (SiteBook.HOME_LOT; see NeighbourhoodDef).
const HOME_LOT: StringName = NeighbourhoodDef.HOME_LOT

## In map order (the order the list view shows them).
@export var neighbourhoods: Array[NeighbourhoodDef] = []
## The roads between neighbourhoods, at most one per pair (CityRoadDef).
@export var roads: Array[CityRoadDef] = []



## Every neighbourhood id, in map order.
func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for area: NeighbourhoodDef in neighbourhoods:
		if area != null:
			result.append(area.id)
	return result


## The neighbourhood with this id, or null.
func neighbourhood(id: StringName) -> NeighbourhoodDef:
	for area: NeighbourhoodDef in neighbourhoods:
		if area != null and area.id == id:
			return area
	return null


## The neighbourhood a lot stands in, or null when no neighbourhood lists it.
func neighbourhood_for_lot(lot: StringName) -> NeighbourhoodDef:
	for area: NeighbourhoodDef in neighbourhoods:
		if area != null and area.has_lot(lot):
			return area
	return null


## The road between two neighbourhoods (either way round), or null.
func road(a: StringName, b: StringName) -> CityRoadDef:
	for candidate: CityRoadDef in roads:
		if candidate != null and ((candidate.from == a and candidate.to == b)
				or (candidate.from == b and candidate.to == a)):
			return candidate
	return null


## The neighbourhoods, in map order, that hold at least one of `owned_lots`
## (for chain goals such as "shops in three neighbourhoods").
func covered(owned_lots: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for area: NeighbourhoodDef in neighbourhoods:
		if area == null:
			continue
		for lot: StringName in area.lots:
			if owned_lots.has(lot):
				result.append(area.id)
				break
	return result


## The neighbourhoods, in map order, where the owner could have a site: those
## holding a lot that is owned or on the game's list (`listed`, lot ids).
## Coming-soon areas do not count until they have a lot.
func reachable(listed: Array[StringName], owned_lots: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for area: NeighbourhoodDef in neighbourhoods:
		if area == null:
			continue
		for lot: StringName in area.lots:
			if owned_lots.has(lot) or listed.has(lot):
				result.append(area.id)
				break
	return result


## Every problem with this map against the game's lots (`lots`: each
## LotDef id to its display name; CityMap.lot_names builds it), in a stable order;
## empty when it is good. The rules: at least one neighbourhood; each has a
## unique valid id, a unique trimmed name of 1 to 40 characters that is not a
## lot's name, a blurb of 1 to 160 characters, a trimmed coming-soon line, a map position inside 0..1, and either
## lots (each listed once, each the home lot or a known lot) or a coming-soon
## line, never both; every lot, plus the home lot, stands in exactly one
## neighbourhood; and each road joins two different known neighbourhoods, at
## most once per pair, with its bends on the map.
func validate(lots: Dictionary[StringName, String]) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if neighbourhoods.is_empty():
		errors.append("The city map has no neighbourhoods")
		return errors
	var known: Dictionary[StringName, String] = {HOME_LOT: ""}
	for lot: StringName in lots:
		if lot != HOME_LOT:
			known[lot] = lots[lot]
	var lot_names: Array[String] = []
	for lot_id: StringName in known:
		if not known[lot_id].is_empty():
			lot_names.append(known[lot_id])
	var seen_ids: Dictionary[StringName, bool] = {}
	var seen_names: Dictionary[String, bool] = {}
	var placed: Dictionary[StringName, int] = {}
	for index: int in range(neighbourhoods.size()):
		var area: NeighbourhoodDef = neighbourhoods[index]
		if area == null:
			errors.append("Neighbourhood %d is empty" % index)
			continue
		var label: String = "Neighbourhood '%s'" % String(area.id)
		if not valid_id(String(area.id)):
			errors.append("%s has an invalid id" % label)
		elif seen_ids.has(area.id):
			errors.append("%s is listed twice" % label)
		seen_ids[area.id] = true
		if not _valid_name(area.display_name):
			errors.append("%s needs a trimmed name of 1 to %d characters" % [label, MAX_NAME_LENGTH])
		elif seen_names.has(area.display_name):
			errors.append("%s repeats the name '%s'" % [label, area.display_name])
		elif lot_names.has(area.display_name):
			errors.append("%s has the same name as a lot" % label)
		seen_names[area.display_name] = true
		if area.blurb.strip_edges().is_empty():
			errors.append("%s needs a blurb" % label)
		elif area.blurb.length() > MAX_BLURB_LENGTH:
			errors.append("%s has a blurb over %d characters" % [label, MAX_BLURB_LENGTH])
		if area.commute_line != area.commute_line.strip_edges() or area.commute_line.length() > MAX_COMMUTE_LINE_LENGTH:
			errors.append("%s needs a trimmed commute line of at most %d characters" % [label, MAX_COMMUTE_LINE_LENGTH])
		if area.coming_soon != area.coming_soon.strip_edges():
			errors.append("%s has a coming-soon line with spaces at its ends" % label)
		if not _on_map(area.map_position):
			errors.append("%s is off the map (positions run 0 to 1)" % label)
		if area.lots.is_empty() and area.coming_soon.strip_edges().is_empty():
			errors.append("%s has no lots, so it needs a coming-soon line" % label)
		if not area.lots.is_empty() and not area.coming_soon.is_empty():
			errors.append("%s has lots, so it cannot be coming soon" % label)
		var own: Dictionary[StringName, bool] = {}
		for lot: StringName in area.lots:
			if own.has(lot):
				errors.append("%s lists lot '%s' twice" % [label, String(lot)])
				continue
			own[lot] = true
			if not known.has(lot):
				errors.append("%s lists unknown lot '%s'" % [label, String(lot)])
				continue
			placed[lot] = int(placed.get(lot, 0)) + 1
	_validate_roads(errors, seen_ids)
	var lot_ids: PackedStringArray = PackedStringArray()
	for lot: StringName in known:
		lot_ids.append(String(lot))
	lot_ids.sort()
	for lot: String in lot_ids:
		var count: int = int(placed.get(StringName(lot), 0))
		if count == 0:
			errors.append("Lot '%s' is in no neighbourhood" % lot)
		elif count > 1:
			errors.append("Lot '%s' is in %d neighbourhoods" % [lot, count])
	return errors


func _validate_roads(errors: PackedStringArray, areas: Dictionary[StringName, bool]) -> void:
	var pairs: Dictionary[String, bool] = {}
	for index: int in range(roads.size()):
		var entry: CityRoadDef = roads[index]
		if entry == null:
			errors.append("Road %d is empty" % index)
			continue
		var label: String = "Road '%s' to '%s'" % [String(entry.from), String(entry.to)]
		if not areas.has(entry.from) or not areas.has(entry.to):
			errors.append("%s names an unknown neighbourhood" % label)
		elif entry.from == entry.to:
			errors.append("%s goes nowhere" % label)
		var ends: Array[String] = [String(entry.from), String(entry.to)]
		ends.sort()
		var key: String = "/".join(ends)
		if pairs.has(key):
			errors.append("%s is listed twice" % label)
		pairs[key] = true
		for bend: Vector2 in entry.bends:
			if not _on_map(bend):
				errors.append("%s bends off the map (positions run 0 to 1)" % label)
				break


## Ids follow SiteBook's rules: 1 to 40 of a-z, 0-9 and "_".
static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > MAX_ID_LENGTH:
		return false
	for character: String in id:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") \
				and character != "_":
			return false
	return true


static func _valid_name(display_name: String) -> bool:
	return not display_name.is_empty() and display_name.length() <= MAX_NAME_LENGTH \
		and display_name == display_name.strip_edges()


static func _on_map(position: Vector2) -> bool:
	return is_finite(position.x) and is_finite(position.y) and position.x >= 0.0 and position.x <= 1.0 \
		and position.y >= 0.0 and position.y <= 1.0
