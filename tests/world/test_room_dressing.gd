extends TestCase
## Native bounds and attachment identities are read without advancing the sim.
## These real kit scenes require the normal import; runtime gates are separate.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _roots: Array[Node] = []


func after_each() -> void:
	for root: Node in _roots:
		root.free()
	_roots.clear()


func test_name_sign_rename_and_rebuild_preserve_world_and_native_attachments() -> void:
	var world: SimWorld = _starter_world()
	var before: Dictionary = _world_snapshot(world)
	var dressing: RoomDressing = _dressing(world)
	assert_eq(dressing.name_sign_nodes().size(), 1)
	var sign: Label3D = dressing.name_sign_nodes()[0]
	var identity: int = sign.get_instance_id()
	var native_ids: Array[int] = _child_ids(dressing)
	assert_true(dressing.set_restaurant_name("Mama's Diner"))
	assert_eq(sign.text, "Mama's Diner")
	assert_eq(sign.get_instance_id(), identity)
	assert_eq(_child_ids(dressing), native_ids, "renaming allocates no replacement geometry")
	assert_false(dressing.set_restaurant_name("Bad\nname"))
	assert_eq(sign.text, "Mama's Diner")
	assert_eq(_world_snapshot(world), before)
	dressing.rebuild(world)
	assert_eq(dressing.name_sign_nodes().size(), 1)
	assert_eq(dressing.name_sign_nodes()[0].text, "Mama's Diner")
	dressing.rebuild(null)
	assert_true(dressing.name_sign_nodes().is_empty())


func test_name_board_hangs_on_solid_wall_beside_the_starter_door() -> void:
	var world: SimWorld = _starter_world()
	var dressing: RoomDressing = _dressing(world)
	var text: Label3D = dressing.name_sign_nodes()[0]
	var board: Node3D = text.get_parent() as Node3D
	var cells: Array[Vector2i] = board.get_meta(&"wall_cells")
	# The starter doorway gap is (6, 10)-(7, 10); the board takes the wall run to its street-left.
	assert_eq(cells, [Vector2i(5, 10), Vector2i(4, 10), Vector2i(3, 10), Vector2i(2, 10)] as Array[Vector2i])
	for cell: Vector2i in cells:
		assert_eq(world.grid.terrain(cell), SimGrid.Terrain.WALL, "the board is mounted on a wall cell, never the doorway")
	_assert_board_on_wall(board, text, cells, Vector2i.DOWN)
	# Readable at the default zoom: roughly 0.15 m capital letters in the UI ink on cream.
	assert_almost_eq(_cap_height(text), RoomDressing.SIGN_CAP_HEIGHT, 0.0001)
	assert_true(_cap_height(text) >= 0.14 and _cap_height(text) <= 0.2)
	assert_eq(text.text, MenuSettings.DEFAULT_NAME)
	assert_eq(text.modulate, RoomDressing.SIGN_THEME.get_color("font_color", "Label"))
	var board_color: Color = ((board.get_node("Board") as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D).albedo_color
	assert_eq(board_color, RoomDressing.SIGN_BOARD_SWATCH.color)


func test_name_board_stays_visible_on_the_cutaway_stub() -> void:
	var world: SimWorld = _starter_world()
	var dressing: RoomDressing = _dressing(world)
	var text: Label3D = dressing.name_sign_nodes()[0]
	var board: Node3D = text.get_parent() as Node3D
	var cells: Array[Vector2i] = board.get_meta(&"wall_cells")
	# Its whole frame sits below the lowered wall top, so the stub still carries it.
	assert_true(board.position.y + RoomDressing.SIGN_FRAME_HEIGHT * 0.5 <= ShopView.LOWERED_HEIGHT - 0.01)
	assert_true(board.position.y - RoomDressing.SIGN_FRAME_HEIGHT * 0.5 >= 0.0)
	for lowered: Array[Vector2i] in [[cells[0]] as Array[Vector2i], cells, [] as Array[Vector2i]]:
		dressing.set_lowered_walls(lowered)
		assert_true(board.is_visible_in_tree() and text.is_visible_in_tree(), "the name board stays visible in Cutaway and Walls Down")


func test_long_name_board_faces_each_frontage_and_fits_its_board() -> void:
	var normals: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]
	for quarter: int in 4:
		var world: SimWorld = _rotated_world(quarter)
		var dressing: RoomDressing = _dressing(world)
		assert_true(dressing.set_restaurant_name("W".repeat(24)))
		assert_eq(dressing.name_sign_nodes().size(), 1)
		var text: Label3D = dressing.name_sign_nodes()[0]
		var board: Node3D = text.get_parent() as Node3D
		var normal: Vector2i = normals[quarter]
		assert_true(board.basis.z.dot(Vector3(normal.x, 0.0, normal.y)) > 0.9999)
		var cells: Array[Vector2i] = board.get_meta(&"wall_cells")
		assert_eq(cells.size(), 2, "the embedded doorway leaves two solid frontage cells per side")
		for cell: Vector2i in cells:
			assert_eq(world.grid.terrain(cell), SimGrid.Terrain.WALL)
			assert_false(world.grid.entries().has(cell))
		_assert_board_on_wall(board, text, cells, normal)
		# Too wide even at the smallest letters: cut with an ellipsis.
		assert_almost_eq(_cap_height(text), RoomDressing.SIGN_MIN_CAP_HEIGHT, 0.0001)
		assert_true(text.text.ends_with(RoomDressing.ELLIPSIS))
		assert_true(text.text.begins_with("WWW"))
		assert_eq(text.get_meta(&"full_name"), "W".repeat(24))
		assert_true(dressing.set_restaurant_name("Cafe"))
		assert_eq(text.text, "Cafe", "a short name is never cut")
		assert_almost_eq(_cap_height(text), RoomDressing.SIGN_CAP_HEIGHT, 0.0001)
		_assert_board_on_wall(board, text, cells, normal)


func test_starter_frontage_uses_two_native_panes_and_two_lamps_on_the_entry_wall() -> void:
	var world: SimWorld = _starter_world()
	var before: Dictionary = _world_snapshot(world)
	var dressing: RoomDressing = _dressing(world)
	var details: Array[Node3D] = dressing.wall_detail_nodes()
	assert_eq(details.size(), 4)
	var windows: int = 0
	var lamps: int = 0
	for detail: Node3D in details:
		var cell: Vector2i = detail.get_meta(&"wall_cell")
		assert_eq(cell.y, 10, "frontage belongs to the entry wall, never the north/side walls")
		assert_eq(detail.get_meta(&"wall_normal"), Vector2i.DOWN)
		assert_eq(world.grid.terrain(cell), SimGrid.Terrain.WALL)
		_assert_wall_geometry(detail as PropView, cell, Vector2i.DOWN)
		if detail.get_meta(&"kind") == &"window":
			windows += 1
			assert_true((detail as PropView).get_combined_aabb().size.y < ArtScale.WALL_HEIGHT,
				"the pane is used without importing a second full-height wall module")
		else:
			lamps += 1
			assert_true(detail.find_children("*", "Light3D", true, false).is_empty())
	assert_eq(windows, 2)
	assert_eq(lamps, 2)
	var detached: Array[Node3D] = dressing.wall_detail_nodes()
	detached.clear()
	assert_eq(dressing.wall_detail_nodes().size(), 4)
	assert_eq(_world_snapshot(world), before)


func test_all_wall_modes_and_camera_quarters_hide_the_same_native_attachments_without_reallocation() -> void:
	var world: SimWorld = _starter_world()
	var before: Dictionary = _world_snapshot(world)
	var dressing: RoomDressing = _dressing(world)
	var view: ShopView = ShopView.new()
	_roots.append(view)
	view.show_world(world)
	var identities: Array[int] = _child_ids(dressing)
	var attachments: Array[Node3D] = dressing.wall_detail_nodes()
	for mode: ShopView.WallMode in [ShopView.WallMode.UP, ShopView.WallMode.CUTAWAY, ShopView.WallMode.DOWN]:
		view.set_wall_mode(mode)
		for quarter: int in range(4):
			view.set_camera_quarter(quarter)
			var lowered: Array[Vector2i] = view.lowered_wall_cells()
			dressing.set_lowered_walls(lowered)
			assert_eq(_child_ids(dressing), identities)
			assert_eq(dressing.wall_detail_nodes(), attachments)
			for detail: Node3D in attachments:
				var cell: Vector2i = detail.get_meta(&"wall_cell")
				assert_eq(detail.visible, not lowered.has(cell), "each native detail follows its own wall")
			var visibility: Array[bool] = []
			for detail: Node3D in attachments:
				visibility.append(detail.visible)
			lowered.clear()
			for index: int in range(attachments.size()):
				assert_eq(attachments[index].visible, visibility[index], "the supplied array remains caller-owned")
			dressing.set_lowered_walls(view.lowered_wall_cells())
			assert_eq(_child_ids(dressing), identities, "an unchanged cutaway does not allocate replacement nodes")
	assert_eq(_world_snapshot(world), before)


func test_in_bounds_street_entrances_center_native_assets_and_rotate_the_frontage_in_all_four_directions() -> void:
	var normals: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]
	for quarter: int in range(4):
		var world: SimWorld = _rotated_world(quarter)
		var before: Dictionary = _world_snapshot(world)
		var dressing: RoomDressing = _dressing(world)
		var normal: Vector2i = normals[quarter]
		var center: Vector3 = Vector3.ZERO
		for entry: Vector2i in world.grid.entries():
			assert_true(world.grid.in_bounds(entry + normal))
			assert_eq(world.grid.terrain(entry + normal), SimGrid.Terrain.OUTSIDE)
			center += GridMath.cell_to_world(entry)
		center /= float(world.grid.entries().size())
		assert_eq(dressing.wall_detail_nodes().size(), 4)
		for detail: Node3D in dressing.wall_detail_nodes():
			var cell: Vector2i = detail.get_meta(&"wall_cell")
			assert_eq(detail.get_meta(&"wall_normal"), normal)
			assert_eq(cell.x * normal.x + cell.y * normal.y,
				world.grid.entries()[0].x * normal.x + world.grid.entries()[0].y * normal.y,
				"an embedded door uses its actual wall plane")
			_assert_wall_geometry(detail as PropView, cell, normal)
		var mat: PropView = dressing.get_node("EntryDoormat") as PropView
		var mat_bounds: AABB = mat.transform * mat.get_combined_aabb()
		assert_almost_eq(mat_bounds.get_center().x, center.x)
		assert_almost_eq(mat_bounds.get_center().z, center.z)
		assert_almost_eq(mat_bounds.position.y, 0.0)
		var first: PropView = dressing.get_node("StreetPavement0") as PropView
		var second: PropView = dressing.get_node("StreetPavement1") as PropView
		var first_bounds: AABB = first.transform * first.get_combined_aabb()
		var second_bounds: AABB = second.transform * second.get_combined_aabb()
		var tangent: Vector3 = Vector3(-normal.y, 0.0, normal.x)
		var spacing: float = absf((first_bounds.get_center() - second_bounds.get_center()).dot(tangent))
		assert_almost_eq(spacing, first.get_combined_aabb().size.x)
		assert_almost_eq(spacing, ArtScale.FURNITURE_SCALE * 0.5, 0.0001, "floorHalf keeps its native half-metre width")
		var paved_width: float = spacing * 2.0
		assert_true(paved_width <= GridMath.CELL_SIZE * world.grid.entries().size() + 0.1 + 0.0001,
			"the pavement stays about doorway-width (fit allowance on each side)")
		for bounds: AABB in [first_bounds, second_bounds]:
			var street_edge: float = center.dot(Vector3(normal.x, 0.0, normal.y)) + GridMath.CELL_SIZE * 0.5
			assert_true(_near_face(bounds, normal) >= street_edge, "paving never crosses back over the door edge")
			assert_true(_near_face(bounds, normal) - street_edge <= RoomDressing.FACE_GAP + 0.0001,
				"paving touches the doorway edge, leaving no visible gap")
			assert_almost_eq(bounds.position.y, 0.0, 0.0001, "paving stands on the ground plane")
			_assert_outside(world.grid, bounds)
		assert_eq(_world_snapshot(world), before)


func test_pavement_tint_is_private_imported_transforms_survive_and_rebind_releases_the_old_dressing() -> void:
	var source_floor: Node3D = RoomDressing.PAVEMENT.instantiate() as Node3D
	var source_lamp: Node3D = RoomDressing.WALL_LAMP.instantiate() as Node3D
	_roots.append(source_floor)
	_roots.append(source_lamp)
	var floor_material: BaseMaterial3D = _named_material(source_floor, &"wood")
	assert_not_null(floor_material)
	if floor_material == null:
		return
	var original_color: Color = floor_material.albedo_color
	var native_lamp_transform: Transform3D = source_lamp.transform
	var dressing: RoomDressing = _dressing(_starter_world())
	var paving: PropView = dressing.get_node("StreetPavement0") as PropView
	assert_eq(paving.body_surface_count(), 1)
	assert_true(paving.active_body_material() != floor_material)
	assert_eq(paving.active_body_material().albedo_color, RoomDressing.pavement_color())
	var tint: Color = RoomDressing.pavement_color()
	assert_true(absf(tint.r - tint.g) < 0.05 and absf(tint.g - tint.b) < 0.05,
		"the palette mix is a near-neutral grey before the warm key light")
	assert_eq(floor_material.albedo_color, original_color, "shared kit materials keep their original colour")
	var lamp: PropView = dressing.get_node("WallLamp0") as PropView
	var model: Node3D = lamp.get_node("Body/Art/Model") as Node3D
	assert_eq(model.transform, native_lamp_transform, "the lamp's authored .58 transform is not overwritten")
	assert_eq((lamp.get_node("Body/Art") as Node3D).scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
	var old_nodes: Array[WeakRef] = []
	for child: Node in dressing.get_children():
		old_nodes.append(weakref(child))
	dressing.rebuild(_rotated_world(1))
	for old: WeakRef in old_nodes:
		assert_null(old.get_ref(), "world replacement removes every prior attachment")
	assert_eq(dressing.wall_detail_nodes().size(), 4)
	assert_eq(floor_material.albedo_color, original_color)
	dressing.rebuild(null)
	assert_eq(dressing.get_child_count(), 0)
	assert_true(dressing.wall_detail_nodes().is_empty())


func _starter_world() -> SimWorld:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(LAYOUT, content, errors)
	assert_eq(errors, [] as Array[String])
	return world


func _dressing(world: SimWorld) -> RoomDressing:
	var dressing: RoomDressing = RoomDressing.new()
	_roots.append(dressing)
	dressing.rebuild(world)
	return dressing


func _rotated_world(quarter: int) -> SimWorld:
	var base: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"          ", " ######## ", " #......# ", " #......# ", " ###EE### ",
		"          ", "          ", "          ", "          ", "          ",
	]))
	var rotated: SimGrid = SimGrid.new(base.size)
	for y: int in range(base.size.y):
		for x: int in range(base.size.x):
			var cell: Vector2i = Vector2i(x, y)
			rotated.set_terrain(GridMath.rotate_cell(cell, base.size, quarter), base.terrain(cell))
	return SimWorld.new(rotated)


func _assert_wall_geometry(detail: PropView, cell: Vector2i, normal: Vector2i) -> void:
	var bounds: AABB = detail.transform * detail.get_combined_aabb()
	var outward: Vector3 = Vector3(normal.x, 0.0, normal.y)
	var wall_face: float = GridMath.cell_to_world(cell).dot(outward) + GridMath.CELL_SIZE * 0.5
	assert_true(_near_face(bounds, normal) >= wall_face, "the entire detail lies on the exterior wall face")
	assert_true(bounds.position.y >= 0.0 and bounds.end.y <= ArtScale.WALL_HEIGHT,
		"native geometry fits the standing wall height")
	assert_true((-detail.basis.z).dot(outward) > 0.9999, "the wrapper front follows the facade normal")
	var tangent_width: float = bounds.size.x if normal.y != 0 else bounds.size.z
	assert_true(tangent_width <= GridMath.CELL_SIZE + 0.05, "a native pane/lamp stays within its wall cell")


func _near_face(bounds: AABB, normal: Vector2i) -> float:
	if normal.x > 0:
		return bounds.position.x
	if normal.x < 0:
		return -bounds.end.x
	if normal.y > 0:
		return bounds.position.z
	return -bounds.end.z


func _assert_outside(grid: SimGrid, bounds: AABB) -> void:
	var first: Vector2i = GridMath.world_to_cell(bounds.position)
	var last: Vector2i = GridMath.world_to_cell(bounds.end - Vector3(0.00001, 0.0, 0.00001))
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			assert_eq(grid.terrain(Vector2i(x, y)), SimGrid.Terrain.OUTSIDE)


func _child_ids(root: Node) -> Array[int]:
	var ids: Array[int] = []
	for child: Node in root.get_children():
		ids.append(child.get_instance_id())
	return ids


func _named_material(root: Node, material_name: StringName) -> BaseMaterial3D:
	var mesh: MeshInstance3D = root as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for index: int in range(mesh.mesh.get_surface_count()):
			var material: BaseMaterial3D = mesh.get_active_material(index) as BaseMaterial3D
			if material != null and StringName(material.resource_name) == material_name:
				return material
	for child: Node in root.get_children():
		var found: BaseMaterial3D = _named_material(child, material_name)
		if found != null:
			return found
	return null


func _world_snapshot(world: SimWorld) -> Dictionary:
	var terrain: Array[int] = []
	for y: int in range(world.grid.size.y):
		for x: int in range(world.grid.size.x):
			terrain.append(world.grid.terrain(Vector2i(x, y)))
	var items: Array[Dictionary] = []
	for item: PlacedItem in world.grid.items():
		var holds: Dictionary[Vector2i, int] = {}
		for cell: Vector2i in item.work_cells + item.seat_cells:
			holds[cell] = item.reserved_by(cell)
		items.append({"id": item.id, "origin": item.origin, "turns": item.quarter_turns,
			"cells": item.cells.duplicate(), "swatch": item.swatch_id, "holds": holds})
	var agents: Array[int] = []
	for agent: SimAgent in world.agents:
		agents.append(agent.id)
	return {"now": world.now, "clock": world.clock.to_dict(), "terrain": terrain,
		"items": items, "agents": agents, "open_tasks": world.board.open_tasks().size(),
		"claimed_tasks": world.board.claimed_tasks().size()}


## The frame lies flat on the outer wall face and within the wall run; the
## letters (including their left/right bearing) stay inside the cream board.
func _assert_board_on_wall(board: Node3D, text: Label3D, cells: Array[Vector2i], normal: Vector2i) -> void:
	var outward: Vector3 = Vector3(normal.x, 0.0, normal.y)
	var tangent: Vector3 = Vector3(-normal.y, 0.0, normal.x)
	var face: float = GridMath.cell_to_world(cells[0]).dot(outward) + GridMath.CELL_SIZE * 0.5
	assert_almost_eq(board.position.dot(outward), face + RoomDressing.FACE_GAP, 0.0001, "the board's back rests on the wall face")
	var low: float = INF
	var high: float = -INF
	for cell: Vector2i in cells:
		var along: float = GridMath.cell_to_world(cell).dot(tangent)
		low = minf(low, along - GridMath.CELL_SIZE * 0.5)
		high = maxf(high, along + GridMath.CELL_SIZE * 0.5)
	var frame: Vector2 = board.get_meta(&"frame_size")
	assert_almost_eq(((board.get_node("Frame/Top") as MeshInstance3D).mesh as BoxMesh).size.x, frame.x)
	var centre: float = board.position.dot(tangent)
	assert_true(centre - frame.x * 0.5 >= low - 0.0001 and centre + frame.x * 0.5 <= high + 0.0001,
		"the frame never reaches over the doorway gap")
	var board_size: Vector2 = board.get_meta(&"board_size")
	var width: float = text.font.get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text.font_size).x * text.pixel_size
	assert_true(width <= board_size.x - RoomDressing.SIGN_TEXT_PADDING * 2.0 + 0.0001, "the name fits its board")
	var line: float = (text.font.get_ascent(text.font_size) + text.font.get_descent(text.font_size)) * text.pixel_size
	assert_true(line <= board_size.y + 0.05, "the letters keep to the board's height")


func _cap_height(text: Label3D) -> float:
	return float(text.font_size) * text.pixel_size * RoomDressing.SIGN_CAP_RATIO
