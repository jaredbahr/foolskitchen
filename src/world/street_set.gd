class_name StreetSet
extends Resource
## The buildings of one street (#422): palettes, roof shapes, heights, fences and
## the little businesses that stand in the row beside the player's lot. Like
## GroundSkin it is the street preset's swappable half: a seaside street (#425)
## supplies its own set and NeighbourhoodBuildings builds it the same way.
## `standard()` is the first street: warm swatches, cottages and a baker's row.

enum Roof { GABLE_FRONT, GABLE_SIDE, HIP, PYRAMID, SHED, FLAT, FALSE_FRONT }
enum Fence { PICKET, HEDGE, WALL, RAIL }

## Changes every hashed choice (colours, heights, widths) without touching rules.
@export var seed_salt: int = 7
## Shopfronts on each side of the player's lot, sharing the street line.
@export_range(1, 3) var shops_per_side: int = 2
## Houses across the road, each on its own lot.
@export_range(1, 8) var house_count: int = 5
@export var wall_colors: Array[Color] = []
@export var roof_colors: Array[Color] = []
@export var door_colors: Array[Color] = []
@export var hedge_colors: Array[Color] = []
@export var bloom_colors: Array[Color] = []
@export var trim: Color = Color.WHITE
@export var glass: Color = Color.WHITE
@export var stone: Color = Color.WHITE
@export var path: Color = Color.WHITE
@export var wood: Color = Color.WHITE
@export var house_roofs: Array[int] = []
@export var shop_roofs: Array[int] = []
@export var house_heights: Array[float] = []
@export var shop_heights: Array[float] = []
@export var fences: Array[int] = []
@export var shops: Array[ShopStyle] = []


static func _swatch(id: String) -> Color:
	return (load("res://data/swatches/%s.tres" % id) as SwatchDef).color


static func standard() -> StreetSet:
	var set: StreetSet = StreetSet.new()
	var cream: Color = _swatch("cream")
	var butter: Color = _swatch("butter")
	var peach: Color = _swatch("peach")
	var blush: Color = _swatch("blush")
	var mint: Color = _swatch("mint")
	var sky: Color = _swatch("powder_blue")
	var sand: Color = _swatch("sand")
	var rose: Color = _swatch("dusty_rose")
	var oat: Color = _swatch("oat")
	var terracotta: Color = _swatch("terracotta")
	var brick: Color = _swatch("brick")
	var slate: Color = _swatch("slate_blue")
	var walnut: Color = _swatch("walnut")
	var plum: Color = _swatch("plum")
	var moss: Color = _swatch("moss")
	var teal: Color = _swatch("teal")
	var honey: Color = _swatch("honey")
	var coral: Color = _swatch("coral")
	var navy: Color = _swatch("navy")
	var milk: Color = _swatch("milk")
	set.wall_colors = [cream, butter, peach, blush, mint, sky, sand, oat, rose.lightened(0.25)]
	set.roof_colors = [terracotta, brick.lightened(0.1), slate.lightened(0.12), honey.darkened(0.08), rose.darkened(0.08),
		teal.lightened(0.28), walnut.lightened(0.3)]
	set.door_colors = [terracotta, teal, honey, slate, coral, plum.lightened(0.15), moss]
	set.hedge_colors = [moss.lightened(0.08), _swatch("leaf"), _swatch("sage").darkened(0.1), _swatch("forest").lightened(0.1)]
	set.bloom_colors = [butter, rose, cream, coral, honey, sky]
	set.trim = milk
	set.glass = slate.lerp(sky, 0.35)
	set.stone = _swatch("pebble")
	set.path = sand.lerp(cream, 0.4)
	set.wood = walnut.lightened(0.12)
	set.house_roofs = [Roof.GABLE_FRONT, Roof.GABLE_SIDE, Roof.HIP, Roof.PYRAMID]
	set.shop_roofs = [Roof.GABLE_SIDE, Roof.SHED, Roof.FLAT, Roof.FALSE_FRONT]
	set.house_heights = [1.45, 1.65, 1.85]
	set.shop_heights = [1.7, 1.95, 2.2]
	set.fences = [Fence.PICKET, Fence.HEDGE, Fence.WALL, Fence.RAIL]
	set.shops = [
		ShopStyle.make(&"bakery", butter, terracotta, cream, oat, terracotta, ShopStyle.Accent.CRATE),
		ShopStyle.make(&"florist", mint, moss.lightened(0.1), cream, blush, teal, ShopStyle.Accent.BUCKETS),
		ShopStyle.make(&"laundromat", sky, slate, milk, cream, navy.lightened(0.2), ShopStyle.Accent.PORTHOLE),
		ShopStyle.make(&"sweet_shop", blush, rose, cream, butter, plum.lightened(0.2), ShopStyle.Accent.JARS),
		ShopStyle.make(&"tea_room", cream, navy.lightened(0.25), milk, sand, coral, ShopStyle.Accent.TABLE),
	]
	return set


## A string that changes whenever anything in the set does; used in cache keys.
func signature() -> String:
	var parts: Array = [seed_salt, shops_per_side, house_count, wall_colors, roof_colors, door_colors, hedge_colors,
		bloom_colors, trim, glass, stone, path, wood, house_roofs, shop_roofs, house_heights, shop_heights, fences]
	for style: ShopStyle in shops:
		parts.append([style.id, style.wall, style.awning_a, style.awning_b, style.sign_board, style.door, int(style.accent)])
	return var_to_str(parts)
