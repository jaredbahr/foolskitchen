extends TestCase
## The street's shopfronts and houses (#422): deterministic, clear of the lot and
## door approach at every rotation, never shading the lot, and modest in triangles.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
## Local street frame: u along the street, z outward. The maximum lot, 12 m by 12.5 m.
const RESERVE: AABB = AABB(Vector3(-5.0, 0.0, -12.5), Vector3(12.0, 1.4, 12.5))
## The camera looks down this steeply, so a point h metres up hides 0.5 h per axis along a diagonal.
const SHADE_PER_METRE: float = 0.5

var _viewport: SubViewport


func after_each() -> void:
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	NeighbourhoodDressing.clear_mesh_cache()


func _builder(salt: int = 7) -> NeighbourhoodBuildings:
	var builder: NeighbourhoodBuildings = NeighbourhoodBuildings.new()
	builder.street = StreetSet.standard()
	builder.street.seed_salt = salt
	builder.local_reserve = RESERVE
	builder.shift = 0.0
	builder.plan()
	return builder


func _vertices(mesh: MeshInstance3D) -> PackedVector3Array:
	return mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _xz(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


func _overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - 0.0001 and a.end.x > b.position.x + 0.0001 \
		and a.position.y < b.end.y - 0.0001 and a.end.y > b.position.y + 0.0001


func test_the_street_rebuilds_identically_and_the_seed_changes_it() -> void:
	var first: NeighbourhoodBuildings = _builder()
	var second: NeighbourhoodBuildings = _builder()
	assert_eq(first.plans.size(), 9, "two shops each side of the lot and five houses")
	for index: int in first.plans.size():
		var a: MeshInstance3D = first.build_mesh(first.plans[index])
		var b: MeshInstance3D = second.build_mesh(second.plans[index])
		assert_eq(_vertices(a), _vertices(b), "the same inputs build the same %s" % first.plans[index].id)
		assert_eq(first.plans[index].bounds, second.plans[index].bounds)
		a.free()
		b.free()
	assert_eq(first.footprints(), second.footprints())
	var other: NeighbourhoodBuildings = _builder(11)
	var differs: bool = false
	for index: int in first.plans.size():
		var p: NeighbourhoodBuildings.Plan = first.plans[index]
		var q: NeighbourhoodBuildings.Plan = other.plans[index]
		differs = differs or p.wall_h != q.wall_h or p.roof != q.roof or p.roof_col != q.roof_col or p.width != q.width
	assert_true(differs, "a different seed salt gives a different street")


func test_the_street_varies_heights_colours_roofs_and_businesses() -> void:
	var builder: NeighbourhoodBuildings = _builder()
	var heights: Dictionary[float, bool] = {}
	var walls: Dictionary[Color, bool] = {}
	var roofs: Dictionary[int, bool] = {}
	var roof_colours: Dictionary[Color, bool] = {}
	var shops: Dictionary[StringName, bool] = {}
	var previous: NeighbourhoodBuildings.Plan = null
	for p: NeighbourhoodBuildings.Plan in builder.plans:
		if not p.is_shop:
			heights[p.wall_h] = true
			walls[p.wall] = true
			roofs[p.roof] = true
			roof_colours[p.roof_col] = true
			if previous != null and not previous.is_shop:
				assert_true(previous.wall != p.wall, "neighbouring houses differ in colour")
				assert_true(previous.roof != p.roof or previous.wall_h != p.wall_h, "neighbouring houses differ in shape")
		else:
			shops[p.style.id] = true
			assert_true(p.style != null)
		previous = p
	assert_true(heights.size() >= 2 and walls.size() >= 3 and roofs.size() >= 2 and roof_colours.size() >= 2,
		"houses use a small mixed set: %d heights, %d walls, %d roofs" % [heights.size(), walls.size(), roofs.size()])
	assert_eq(shops.size(), 4, "each shopfront is a different business")


func test_no_building_touches_the_lot_the_door_approach_or_each_other_and_none_can_shade_the_lot() -> void:
	var builder: NeighbourhoodBuildings = _builder()
	var lot: Rect2 = _xz(RESERVE)
	# The widest door approach: the lot's whole frontage, 2.2 m deep, out to the street.
	var approach: Rect2 = Rect2(RESERVE.position.x, 0.0, RESERVE.size.x, 2.2)
	var boxes: Array[AABB] = builder.footprints()
	for index: int in boxes.size():
		var box: AABB = boxes[index]
		var rect: Rect2 = _xz(box)
		assert_false(_overlaps(rect, lot), "%s clears the maximum lot" % builder.plans[index].id)
		assert_false(_overlaps(rect, approach), "%s clears the door approach" % builder.plans[index].id)
		assert_true(box.size.y <= NeighbourhoodBuildings.MAX_NEAR_HEIGHT + 0.3 or not builder.plans[index].is_shop,
			"a near shop stays low enough")
		for other: int in range(index + 1, boxes.size()):
			assert_false(_overlaps(rect, _xz(boxes[other])), "%s and %s do not overlap" % [builder.plans[index].id, builder.plans[other].id])
		if builder.plans[index].is_shop:
			# Seen from any of the four diagonal views the box and its hidden ground
			# stay off the lot: no rotation lets a neighbour hide the shop.
			for diagonal: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
				var push: Vector2 = diagonal * SHADE_PER_METRE * box.size.y
				var swept: Rect2 = rect.merge(Rect2(rect.position + push, rect.size))
				assert_false(_overlaps(swept, lot), "%s cannot hide the lot from %s" % [builder.plans[index].id, diagonal])
	for lot_box: AABB in builder.lots():
		assert_false(_overlaps(_xz(lot_box), approach), "house lots stay across the road")
		assert_true(lot_box.position.z >= NeighbourhoodBuildings.FENCE_V - 0.001)


func test_every_house_lot_holds_its_house_path_and_fence() -> void:
	var builder: NeighbourhoodBuildings = _builder()
	var houses: int = 0
	for p: NeighbourhoodBuildings.Plan in builder.plans:
		if p.is_shop:
			continue
		houses += 1
		assert_true(p.lot.encloses(_xz(p.bounds)), "%s stands inside its own lot" % p.id)
		var mesh: MeshInstance3D = builder.build_mesh(p)
		var vertices: PackedVector3Array = _vertices(mesh)
		var box: AABB = AABB(vertices[0], Vector3.ZERO)
		for point: Vector3 in vertices:
			box = box.expand(point)
		var extent: Rect2 = _xz(box)
		assert_true(extent.position.x >= p.lot.position.x - 0.2 and extent.end.x <= p.lot.end.x + 0.2
			and extent.position.y >= NeighbourhoodBuildings.PAVEMENT_EDGE_V - 0.01 and extent.end.y <= p.lot.end.y + 0.2,
			"%s's yard, fence and path stay on its lot (the path runs on to the pavement)" % p.id)
		# The house faces the road: its door is on the street side of its body.
		assert_true(p.xf.basis.z.z < -0.9, "%s faces the street" % p.id)
		mesh.free()
	assert_eq(houses, 5)


func test_the_whole_street_is_a_modest_number_of_triangles_and_draw_calls() -> void:
	var builder: NeighbourhoodBuildings = _builder()
	var triangles: int = 0
	for p: NeighbourhoodBuildings.Plan in builder.plans:
		var mesh: MeshInstance3D = builder.build_mesh(p)
		assert_eq(mesh.mesh.get_surface_count(), 1, "one draw call per building")
		assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_eq(mesh.find_children("*", "CollisionObject3D", true, false).size(), 0)
		triangles += _vertices(mesh).size() / 3
		mesh.free()
	assert_true(triangles > 3000 and triangles < 16000, "a sensible triangle count: %d" % triangles)


func test_all_four_rotations_keep_every_building_off_the_lot_and_the_door_approach() -> void:
	await _host()
	for quarter: int in 4:
		var grid: SimGrid = _grid(quarter)
		var normal: Vector2i = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT][quarter]
		var reserve: Rect2i = _rotate_rect(Rect2i(-2, -2, 12, 9), quarter)
		var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
		_viewport.add_child(dressing)
		dressing.set_process(false)
		dressing.configure(grid, reserve, [{"cells": grid.entries().duplicate(), "normal": normal}] as Array[Dictionary], [] as Array[AABB])
		assert_eq(dressing.build_error, "", "rotation %d builds every building" % quarter)
		var boxes: Array[AABB] = dressing.building_boxes_in_view()
		assert_eq(boxes.size(), 9)
		var lot_rect: Rect2 = Rect2(Vector2(reserve.position) * 0.5, Vector2(reserve.size) * 0.5)
		var approaches: Array = dressing.capture_state()["bounds"]["door_approaches"]
		var buildings: Node3D = dressing.find_child("Buildings", true, false) as Node3D
		assert_eq(buildings.get_child_count(), 9)
		for box: AABB in boxes:
			assert_false(_overlaps(_xz(box), lot_rect), "rotation %d: a building clears the lot" % quarter)
			for entry: Dictionary in approaches:
				var door: AABB = AABB(Vector3(entry["position"][0], entry["position"][1], entry["position"][2]),
					Vector3(entry["size"][0], entry["size"][1], entry["size"][2]))
				assert_false(_overlaps(_xz(box), _xz(door)), "rotation %d: a building clears the door approach" % quarter)
		for mesh: Node in buildings.get_children():
			var bounds: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
			assert_false(_overlaps(_xz(bounds), lot_rect), "rotation %d: every mesh clears the lot" % quarter)
		dressing.get_parent().remove_child(dressing)
		dressing.free()


func test_a_rebuild_reuses_the_cached_street_and_a_new_set_replaces_it() -> void:
	await _host()
	var grid: SimGrid = _grid(0)
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	var frontage: Array[Dictionary] = [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary]
	dressing.configure(grid, Rect2i(-2, -2, 12, 9), frontage, [] as Array[AABB])
	var buildings: Node3D = dressing.find_child("Buildings", true, false) as Node3D
	var first: Array[PackedVector3Array] = []
	for mesh: Node in buildings.get_children():
		first.append((mesh as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	# A different set (a seaside street, say) swaps the whole building set.
	var other: StreetSet = StreetSet.standard()
	other.seed_salt = 99
	other.house_count = 3
	dressing.street_set = other
	dressing.rebuild()
	buildings = dressing.find_child("Buildings", true, false) as Node3D
	assert_eq(buildings.get_child_count(), 7, "two shops each side and the three houses of the new set")
	dressing.street_set = StreetSet.standard()
	dressing.rebuild()
	buildings = dressing.find_child("Buildings", true, false) as Node3D
	assert_eq(buildings.get_child_count(), 9)
	for index: int in buildings.get_child_count():
		assert_eq((buildings.get_child(index) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], first[index],
			"going back to the standard set restores the same street")
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func _host() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)


func _grid(quarter: int) -> SimGrid:
	var base: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	for cell: Vector2i in base.cells():
		grid.set_terrain(_rotate(cell, quarter), base.terrain(cell))
	return grid


func _rotate(cell: Vector2i, quarter: int) -> Vector2i:
	match quarter:
		1:
			return Vector2i(7 - cell.y, cell.x)
		2:
			return Vector2i(7 - cell.x, 7 - cell.y)
		3:
			return Vector2i(cell.y, 7 - cell.x)
	return cell


func _rotate_rect(rect: Rect2i, quarter: int) -> Rect2i:
	var cells: Array[Vector2i] = [_rotate(rect.position, quarter), _rotate(rect.end - Vector2i.ONE, quarter),
		_rotate(Vector2i(rect.end.x - 1, rect.position.y), quarter), _rotate(Vector2i(rect.position.x, rect.end.y - 1), quarter)]
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for cell: Vector2i in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	return Rect2i(low, high - low + Vector2i.ONE)
