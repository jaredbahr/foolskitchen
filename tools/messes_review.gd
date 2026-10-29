extends "res://src/world/main.gd"
## Explicit visual fixture: three synthetic floor messes in a paused morning.
## MESS_REVIEW_FLOOR=dark|light keeps the same cells, framing and approved art.
## This fixture does not pretend to demonstrate service mishap probabilities.

const MESS_CELLS: Array[Vector2i] = [Vector2i(3, 8), Vector2i(6, 8), Vector2i(10, 8)]


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	set_process(false)
	Clock.set_speed(0)
	var floor_kind: String = OS.get_environment("MESS_REVIEW_FLOOR")
	if floor_kind not in ["dark", "light"] or sim.cleanliness == null:
		push_error("Mess review needs dark or light floor and the live cleanliness state")
		return
	if floor_kind == "light":
		if not set_paint_active(true):
			push_error("Mess review could not start its floor paint")
			return
		_on_swatch_requested(&"cream")
		if not paint_cell(MESS_CELLS[1], true):
			push_error("Mess review could not paint the dining floor")
			return
		set_paint_active(false)
	for cell: Vector2i in MESS_CELLS:
		if world.grid.terrain(cell) != SimGrid.Terrain.FLOOR or not world.grid.is_walkable(cell):
			push_error("Mess review needs unobstructed floor for every sample")
			return
	# Add one plain dirt spot deliberately, rather than sampling chance until it appears.
	sim.cleanliness._place(MESS_CELLS[0])
	if not sim.cleanliness.add_spill(MESS_CELLS[1]) or not sim.cleanliness.add_spill(MESS_CELLS[2], true):
		push_error("Mess review could not prepare its spill and broken plate")
		return
	sim.clean_tasks.sync_spots()
	var view: ShopView = $ShopView
	view._process(0.0)
	var samples: Array[Dictionary] = []
	for index: int in range(MESS_CELLS.size()):
		var cell: Vector2i = MESS_CELLS[index]
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
