extends "res://src/world/main.gd"
## Explicit visual fixture: three synthetic floor messes in a paused morning.
## MESS_REVIEW_FLOOR=dark|light keeps the same cells, framing and approved art.
## This fixture does not pretend to demonstrate service mishap probabilities.

## One sample just south of each starter two-seat table, west to east, read
## from the real grid: open floor that is not a seat and has nobody on it.
var _review_cells: Array[Vector2i] = []


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	set_process(false)
	Clock.set_speed(0)
	_review_cells = _find_mess_cells()
	if _review_cells.size() != 3:
		push_error("Mess review needs open floor beside each of the three starter tables")
		return
	var floor_kind: String = OS.get_environment("MESS_REVIEW_FLOOR")
	if floor_kind not in ["dark", "light"] or sim.cleanliness == null:
		push_error("Mess review needs dark or light floor and the live cleanliness state")
		return
	if floor_kind == "light":
		if not set_paint_active(true):
			push_error("Mess review could not start its floor paint")
			return
		_on_swatch_requested(&"cream")
		if not paint_cell(_review_cells[1], true):
			push_error("Mess review could not paint the dining floor")
			return
		set_paint_active(false)
	for cell: Vector2i in _review_cells:
		if world.grid.terrain(cell) != SimGrid.Terrain.FLOOR or not world.grid.is_walkable(cell):
			push_error("Mess review needs unobstructed floor for every sample")
			return
	# Add one plain dirt spot deliberately, rather than sampling chance until it appears.
	sim.cleanliness._place(_review_cells[0])
	if not sim.cleanliness.add_spill(_review_cells[1]) or not sim.cleanliness.add_spill(_review_cells[2], true):
		push_error("Mess review could not prepare its spill and broken plate")
		return
	sim.clean_tasks.sync_spots()
	var view: ShopView = $ShopView
	view._process(0.0)
	var samples: Array[Dictionary] = []
	for index: int in range(_review_cells.size()):
		var cell: Vector2i = _review_cells[index]
		var node: MeshInstance3D = view.dirt_nodes.get(cell) as MeshInstance3D
		if node == null or not node.has_node("Outline") \
				or (index == 2 and not node.has_node("BrokenPlate")):
			push_error("Mess review is missing an outlined native mess")
			return
		var main_color: Color = view.drawn_floor_main_color(cell)
		var fill: Color = (node.material_override as StandardMaterial3D).albedo_color
		var outline: Color = ((node.get_node("Outline") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		if outline.get_luminance() >= fill.get_luminance() or fill != view.mess_fill_color(cell):
			push_error("Mess review is missing contrasting palette fill and darker outline")
			return
		samples.append({"cell": [cell.x, cell.y], "kind": sim.cleanliness.floor_mess_kind(cell),
			"main_floor": main_color.to_html(), "fill": fill.to_html(), "outline": outline.to_html(),
			"broken_plate_visible": node.has_node("BrokenPlate")})
	print("MESS_REVIEW ", JSON.stringify({"fixture": "three synthetic floor messes; normal floor-paint command; saves disabled",
		"floor": floor_kind, "samples": samples, "world_tick": world.now, "use_saves": use_saves}))


func _find_mess_cells() -> Array[Vector2i]:
	var grid: SimGrid = world.grid
	var avoid: Dictionary[Vector2i, bool] = {}
	for item: PlacedItem in grid.items():
		for cell: Vector2i in item.seat_cells:
			avoid[cell] = true
	var claims: Dictionary = world.movement.snapshot()
	for key: String in ["occupied", "next"]:
		for cell: Vector2i in claims[key]:
			avoid[cell] = true
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	tables.sort_custom(func(a: PlacedItem, b: PlacedItem) -> bool: return a.origin.x < b.origin.x)
	var result: Array[Vector2i] = []
	for table: PlacedItem in tables:
		var low: Vector2i = table.cells[0]
		var high: Vector2i = table.cells[0]
		for cell: Vector2i in table.cells:
			low = low.min(cell)
			high = high.max(cell)
		var found: Vector2i = SimGrid.NO_CELL
		for y: int in range(high.y + 1, high.y + 4):
			for x: int in range(low.x, high.x + 1):
				var cell: Vector2i = Vector2i(x, y)
				if found == SimGrid.NO_CELL and not avoid.has(cell) and not result.has(cell) \
						and grid.terrain(cell) == SimGrid.Terrain.FLOOR and grid.is_walkable(cell):
					found = cell
		if found != SimGrid.NO_CELL:
			result.append(found)
	return result
