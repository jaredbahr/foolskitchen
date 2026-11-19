class_name CityMap
extends RefCounted
## The city map's rules (docs/CITY_MAP.md): what each lot and neighbourhood
## shows, given what the owner has. Pure and static, with no random draw. The
## lot rules are the property market's own (PropertyMarket), so the map and the
## market never disagree about what is for sale or locked.

## What a lot's pin shows.
## OWNED: one of the owner's sites stands on it.
## FOR_SALE: listed on the market and not locked (it may still be too dear,
## or past the site limit: the lot card says why, as on the market).
## LOCKED: below the market tier, or short of its tier or stars.
## UNLISTED: not for sale and not owned (the starter shop once sold, or a lot
## missing from the game's data). The map draws nothing for it.
enum LotState { OWNED, FOR_SALE, LOCKED, UNLISTED }

## What a neighbourhood's patch shows.
## OPEN: the owner has a site there, or a lot there is for sale.
## LOCKED: a lot there is locked and none is owned or for sale.
## COMING_SOON: no lots yet (its coming-soon line says what is coming).
## EMPTY: its lots are all unlisted (the starter shop sold, a lot missing
## from the data): nothing to buy or open, and no lock to quote.
enum AreaState { OPEN, LOCKED, COMING_SOON, EMPTY }

const DEFAULT_PATH: String = "res://data/city/city_map.tres"


## The shipped city map, or null when the file is missing or not a city map.
static func load_default() -> CityMapDef:
	return load(DEFAULT_PATH) as CityMapDef if ResourceLoader.exists(DEFAULT_PATH) else null


## One lot's state. `definition` is its LotDef (null for the home lot, which
## is never listed). Stars compare at one decimal, as on the market.
static func lot_state(definition: LotDef, owned: bool, career_tier: int, reputation: float) -> LotState:
	if owned:
		return LotState.OWNED
	if definition == null:
		return LotState.UNLISTED
	if not PropertyMarket.shown(career_tier) or PropertyMarket.locked(definition, career_tier, reputation):
		return LotState.LOCKED
	return LotState.FOR_SALE


## A neighbourhood's state from its lots' states (`lots` are the game's lot
## definitions, `owned_lots` the lots the owner's sites stand on).
static func area_state(area: NeighbourhoodDef, lots: Array[LotDef], owned_lots: Array[StringName],
		career_tier: int, reputation: float) -> AreaState:
	if area == null or area.is_coming_soon():
		return AreaState.COMING_SOON
	var locked: bool = false
	for lot: StringName in area.lots:
		var state: LotState = lot_state(find_lot(lots, lot), owned_lots.has(lot), career_tier, reputation)
		if state == LotState.OWNED or state == LotState.FOR_SALE:
			return AreaState.OPEN
		locked = locked or state == LotState.LOCKED
	return AreaState.LOCKED if locked else AreaState.EMPTY


## The lowest career tier any lot in `area` needs (1 for the home lot), or 0
## when it holds no known lot. Read-only: lots keep their own gates (D28);
## this only words "Opens at Tier 4" on a locked patch.
static func opening_tier(area: NeighbourhoodDef, lots: Array[LotDef]) -> int:
	if area == null:
		return 0
	var lowest: int = 0
	for lot: StringName in area.lots:
		var tier: int = 1 if lot == NeighbourhoodDef.HOME_LOT else 0
		var definition: LotDef = find_lot(lots, lot)
		if definition != null:
			tier = definition.min_tier
		if tier > 0 and (lowest == 0 or tier < lowest):
			lowest = tier
	return lowest


## The van's route between two neighbourhoods (docs/CITY_MAP.md T5), in
## map coordinates (0 to 1): the start neighbourhood's position, the road's
## bends in travel order (reversed when the road is drawn the other way), then
## the end's position. Straight when no road joins them. Empty when either
## neighbourhood is unknown or they are the same one (no ride).
static func van_path(map: CityMapDef, from_area: StringName, to_area: StringName) -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array()
	if map == null or from_area == to_area:
		return path
	var start: NeighbourhoodDef = map.neighbourhood(from_area)
	var end: NeighbourhoodDef = map.neighbourhood(to_area)
	if start == null or end == null:
		return path
	path.append(start.map_position)
	var drawn: CityRoadDef = map.road(from_area, to_area)
	if drawn != null:
		var bends: PackedVector2Array = drawn.bends.duplicate()
		if drawn.from != from_area:
			bends.reverse()
		path.append_array(bends)
	path.append(end.map_position)
	return path


## Each lot's id to its display name, for CityMapDef.validate.
static func lot_names(lots: Array[LotDef]) -> Dictionary[StringName, String]:
	var names: Dictionary[StringName, String] = {}
	for lot: LotDef in lots:
		if lot != null:
			names[lot.id] = lot.display_name
	return names


## Each lot's id, for CityMapDef.reachable.
static func lot_ids(lots: Array[LotDef]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for lot: LotDef in lots:
		if lot != null:
			ids.append(lot.id)
	return ids


static func find_lot(lots: Array[LotDef], id: StringName) -> LotDef:
	for lot: LotDef in lots:
		if lot != null and lot.id == id:
			return lot
	return null
