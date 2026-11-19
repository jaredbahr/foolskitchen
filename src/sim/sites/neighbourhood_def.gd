class_name NeighbourhoodDef
extends Resource
## One neighbourhood on the city map (docs/CITY_MAP.md): data only, held by a
## CityMapDef in data/city/city_map.tres. It names the lots that stand in it
## (LotDef ids, plus HOME_LOT for the starter shop) and where it sits
## on the map. An area with no lots yet is a locked "coming soon" patch and
## says what is coming. CityMapDef.validate checks every field.

## The starter shop's lot: equal to SiteBook.HOME_LOT (a test keeps them
## together). Kept here, the leaf of the city scripts, so loading the map
## never loads the sites model or forms a script cycle (which leaks at exit).
const HOME_LOT: StringName = &"home"

@export var id: StringName = &""
## The name on the map. Never repeats a lot's name (a lot is a shop, this is
## the part of town it stands in).
@export var display_name: String = ""
## One short line about the place, shown when the player points at it.
@export var blurb: String = ""
## LotDef ids of the lots in this neighbourhood, in map order.
@export var lots: Array[StringName] = []
## Where the neighbourhood's label sits on the map, 0 to 1 on each axis
## (x from the left, y from the top), so the art can be any size.
@export var map_position: Vector2 = Vector2(0.5, 0.5)
## For an area with no lots yet: what is coming ("A cabin in the woods").
## Empty for an area with lots.
@export var coming_soon: String = ""
## An extra commute joke that only turns up when the owner drives to this
## neighbourhood (CommuteLines mixes it in with the general ones). Empty for none.
@export var commute_line: String = ""


func is_coming_soon() -> bool:
	return lots.is_empty()


func has_lot(lot: StringName) -> bool:
	return lots.has(lot)

