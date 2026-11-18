class_name StreetPreset
extends Resource
## One street's whole recipe (#425): the ground and tree line (`ground`, a GroundSkin)
## and the building set, palette and street furniture (`buildings`, a StreetSet).
## Presets are data in data/streets/<id>.tres. A lot names its preset
## (`LotDef.street_preset`); the home lot and a lot without one use the starter
## street (`STARTER`). ShopView hands the active site's preset to
## NeighbourhoodDressing, which builds the street from it and nothing else, so a
## new street (seaside, suburb) is a new .tres, never new code.

const STARTER: String = "res://data/streets/starter.tres"

@export var id: StringName = &""
@export var ground: GroundSkin
@export var buildings: StreetSet
## The beach and sea behind the back lane (#588); none keeps the meadow and tree line.
@export var shore: ShoreSkin
## A car-free promenade instead of the road (#596); none keeps the road and its traffic.
@export var promenade: PromenadeSkin
## A woodland clearing on a forest track instead of a street (#607): no road, cars,
## pavements or neighbouring buildings. None keeps the street.
@export var forest: ForestSkin
## The shop's default wall finish on this street (#611, a WallStyleDef id): every
## wall face starts in it and Build can still change any face. Empty is plain paint.
@export var wall_style: StringName = &""


## The starter street, the one every site had before presets (#422, #423).
static func starter() -> StreetPreset:
	return load(STARTER) as StreetPreset


## True when cars drive past: every street but a promenade or a forest track.
func has_traffic() -> bool:
	return promenade == null and forest == null


## The preset at `path`, or the starter street when `path` is empty, missing or
## not a valid preset. Never null while the starter itself is valid.
static func from_path(path: String) -> StreetPreset:
	if not path.is_empty() and ResourceLoader.exists(path):
		var preset: StreetPreset = load(path) as StreetPreset
		if preset != null and preset.errors().is_empty():
			return preset
		push_warning("Street preset %s is not valid; using the starter street" % path)
	return starter()


## The street a lot stands on (null lot: the home lot, which uses the starter street).
static func for_lot(lot: LotDef) -> StreetPreset:
	return from_path(lot.street_preset if lot != null else "")


## The street of the active site: its lot's preset, or the starter street.
static func for_site(book: SiteBook, content: ContentDB) -> StreetPreset:
	if book == null or content == null:
		return starter()
	return for_lot(content.lot(book.lot_id(book.active_id)))


## What makes the preset unusable, in plain words (empty when it is valid). The
## builders index every list below by hash, so each must have at least one entry.
func errors() -> PackedStringArray:
	var problems: PackedStringArray = []
	if String(id).strip_edges().is_empty():
		problems.append("the preset has no id")
	if ground == null:
		problems.append("no ground")
	elif ground.flowers.is_empty():
		problems.append("the ground has no flower colours")
	if buildings == null:
		problems.append("no building set")
		return problems
	var lists: Dictionary[String, Array] = {
		"wall_colors": buildings.wall_colors, "roof_colors": buildings.roof_colors,
		"door_colors": buildings.door_colors, "hedge_colors": buildings.hedge_colors,
		"bloom_colors": buildings.bloom_colors, "laundry_colors": buildings.laundry_colors,
		"play_colors": buildings.play_colors, "window_glows": buildings.window_glows,
		"house_roofs": buildings.house_roofs, "shop_roofs": buildings.shop_roofs,
		"house_heights": buildings.house_heights, "shop_heights": buildings.shop_heights,
		"fences": buildings.fences, "shops": buildings.shops, "bin_colors": buildings.bin_colors,
		"bird_colors": buildings.bird_colors, "leaf_colors": buildings.leaf_colors,
	}
	for key: String in lists:
		if lists[key].is_empty():
			problems.append("the building set has no %s" % key)
	for roof: int in buildings.house_roofs + buildings.shop_roofs:
		if roof < 0 or roof >= StreetSet.Roof.size():
			problems.append("unknown roof shape %d" % roof)
	for fence: int in buildings.fences:
		if fence < 0 or fence >= StreetSet.Fence.size():
			problems.append("unknown fence %d" % fence)
	for height: float in buildings.house_heights + buildings.shop_heights:
		if height <= 0.0:
			problems.append("a wall height must be above 0")
	for style: ShopStyle in buildings.shops:
		if style == null or String(style.id).is_empty():
			problems.append("a neighbour shop has no id")
	var named: Dictionary[StringName, bool] = {}
	for style: ShopStyle in buildings.terrace_left + buildings.terrace_right:
		if style == null or String(style.id).is_empty():
			problems.append("a terrace neighbour has no id")
		elif named.has(style.id):
			problems.append("two terrace neighbours are both %s" % style.id)
		else:
			named[style.id] = true
	if promenade != null:
		problems.append_array(promenade.errors())
	if shore != null:
		problems.append_array(shore.errors())
	if forest != null:
		problems.append_array(forest.errors())
	for spec: StreetPropSpec in buildings.furniture:
		if spec == null:
			problems.append("an empty street furniture entry")
	return problems
