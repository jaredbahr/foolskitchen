class_name ShopBuilder
extends RefCounted
## Builds a SimWorld from a ShopLayout and the content database.


## Returns a world with the layout's terrain and items. Problems (unknown item
## ids, items that don't fit) are appended to `errors`; a world is returned
## anyway with whatever could be placed, so the game can still show it.
static func build(layout: ShopLayout, content: ContentDB, errors: Array[String]) -> SimWorld:
	var grid := SimGrid.from_ascii(layout.rows)
	for p in layout.placements:
		var def := content.item(p.item_id)
		if def == null:
			errors.append("%s: unknown item '%s'" % [layout.id, p.item_id])
			continue
		if grid.place_def(def, p.origin, p.quarter_turns) == null:
			errors.append("%s: %s doesn't fit at %s (turns %d): %s" % [layout.id, p.item_id, p.origin,
					p.quarter_turns, SimGrid.PlaceResult.keys()[grid.can_place(def.footprint, p.origin, p.quarter_turns)]])
	for r: StringName in layout.staff_spawns:
		if not grid.is_walkable(layout.staff_spawns[r]):
			errors.append("%s: spawn for %s at %s is not walkable" % [layout.id, r, layout.staff_spawns[r]])
	return SimWorld.new(grid)


## Placed items whose def has the given id, in placement order.
static func items_with_def(world: SimWorld, item_id: StringName) -> Array[PlacedItem]:
	var out: Array[PlacedItem] = []
	for it in world.grid.items():
		var def := it.def as ItemDef
		if def != null and def.id == item_id:
			out.append(it)
	return out
