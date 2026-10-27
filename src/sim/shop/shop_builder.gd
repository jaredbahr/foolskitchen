class_name ShopBuilder
extends RefCounted
## Builds a SimWorld from a ShopLayout and the content database.


## Returns a world with the layout's terrain and items. Problems (unknown item
## ids, items that don't fit) are appended to `errors`; a world is returned
## anyway with whatever could be placed, so the game can still show it.
## Validated edited layouts may cover staff spawns: agents use the grid's
## blocked-start escape. Authored layouts retain strict spawn checks by default.
static func build(layout: ShopLayout, content: ContentDB, errors: Array[String], allow_blocked_spawns: bool = false) -> SimWorld:
	var grid := SimGrid.from_ascii(layout.rows)
	for p in layout.placements:
		var def := content.item(p.item_id)
		if def == null:
			errors.append("%s: unknown item '%s'" % [layout.id, p.item_id])
			continue
		var placed: PlacedItem = grid.place_def(def, p.origin, p.quarter_turns)
		if placed == null:
			errors.append("%s: %s doesn't fit at %s (turns %d): %s" % [layout.id, p.item_id, p.origin,
					p.quarter_turns, SimGrid.PlaceResult.keys()[grid.can_place_def(def, p.origin, p.quarter_turns)]])
		else:
			placed.swatch_id = p.swatch_id if def.paintable and content.swatch(p.swatch_id) != null else &""
	for edge: Vector3i in layout.wall_segments:
		var kind: WallKindDef = content.wall_kind(layout.wall_segments[edge])
		var problem: String = "unknown wall kind" if kind == null else WallRules.edge_problem(grid, edge, kind.segment as SimGrid.Segment)
		if problem.is_empty():
			grid.set_segment(edge, kind.segment as SimGrid.Segment)
		else:
			errors.append("%s: wall at %s: %s" % [layout.id, edge, problem])
	for r: StringName in layout.staff_spawns:
		var spawn: Vector2i = layout.staff_spawns[r]
		var covering: PlacedItem = grid.item_at(spawn)
		var furniture_blocked: bool = grid.terrain(spawn) == SimGrid.Terrain.FLOOR and covering != null \
			and (covering.solid or covering.blocking_cells.has(spawn))
		if not grid.is_walkable(spawn) and not (allow_blocked_spawns and furniture_blocked):
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
