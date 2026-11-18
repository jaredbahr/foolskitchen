extends TestCase
## The Skyline Rooftop's street (#614): a city rooftop. The rooftop preset is valid
## and has no traffic, street, pavement, cars or neighbours at roof level; nothing it
## stands up is on the lot's maximum footprint or the door's approach; the lift lobby
## faces the shop's entrance; the city is the same every build and every frame for a
## given clock; the rooftop lot names the preset; and every other street builds
## exactly what it did before the rooftop.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const ROOFTOP: String = "res://data/streets/rooftop.tres"
const LOT: String = "res://data/lots/skyscraper_rooftop.tres"
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)
## Every other street's digest (see `_digest`, the same one test_woodland_street.gd
## holds), taken on main before the rooftop: a change here means that street changed.
const DIGESTS: Dictionary[String, String] = {
	"res://data/streets/starter.tres": "aacd560112720e7b4f6c719fd747873106abd731cf8131875be5ac01ffd4d5ff",
	"res://data/streets/seaside.tres": "84d6b57a43954776d68096fa88f967ba1fe6b9a51a8c40c4a7509146a81b0c86",
	"res://data/streets/promenade.tres": "6360419dd2afd9921e1450c39fea1879465f0ae8df33491001de67d8f2406649",
	"res://data/streets/woodland.tres": "25d71eed7b271fc2ae3df6c594d0deaa3efb3fe402918f832694dfa16a832950",
}

var _viewport: SubViewport


func after_each() -> void:
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	NeighbourhoodDressing.clear_mesh_cache()


func _host() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)


func _grid() -> SimGrid:
	return SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))


func _dressing(preset: StreetPreset) -> NeighbourhoodDressing:
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	dressing.use_preset(preset)
	var grid: SimGrid = _grid()
	dressing.configure(grid, RESERVE, [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])
	return dressing


func _free(dressing: NeighbourhoodDressing) -> void:
	dressing.get_parent().remove_child(dressing)
	dressing.free()


static func _vector(parts: Array) -> Vector3:
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


static func _box(entry: Dictionary) -> AABB:
	return AABB(_vector(entry["position"]), _vector(entry["size"]))


## The same digest as test_woodland_street.gd: every static mesh (name and vertex
## count), the furniture plan, the neighbours' doors, the bounds and the street life.
func _digest(dressing: NeighbourhoodDressing) -> String:
	var parts: Array = []
	for node: Node in dressing.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null or not dressing.is_ancestor_of(mesh) or mesh.get_parent() is PersonView \
				or dressing.car != null and dressing.car.is_ancestor_of(mesh) or _in_person(mesh):
			continue
		var vertices: int = 0
		for surface: int in mesh.mesh.get_surface_count():
			vertices += (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		parts.append("%s:%d" % [dressing.get_path_to(mesh), vertices])
	parts.sort()
	for entry: Dictionary in dressing.furniture_plan():
		parts.append("%d@%.3f,%.3f" % [entry["kind"], entry["u"], entry["v"]])
	for door: float in dressing.shop_door_positions():
		parts.append("door%.3f" % door)
	dressing.set_review_time(7.0)
	var state: Dictionary = dressing.capture_state()
	parts.append(var_to_str(state["bounds"]))
	parts.append(var_to_str(state["car"]))
	for actor: Dictionary in state["actors"]:
		parts.append(var_to_str([actor["guest_id"], actor["position"], actor["direction"]]))
	return var_to_str(parts).sha256_text()


func _in_person(node: Node) -> bool:
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is PersonView:
			return true
		parent = parent.get_parent()
	return false


func test_the_rooftop_preset_is_valid_and_has_no_traffic() -> void:
	var rooftop: StreetPreset = load(ROOFTOP) as StreetPreset
	assert_not_null(rooftop, "the rooftop is a street preset")
	assert_eq(rooftop.errors(), PackedStringArray())
	assert_eq(String(rooftop.id), "rooftop")
	assert_not_null(rooftop.rooftop, "it is a city rooftop")
	assert_false(rooftop.has_traffic(), "no cars drive across a roof")
	# A rooftop missing a list it draws from is refused, in plain words.
	var broken: RooftopSkin = rooftop.rooftop.duplicate() as RooftopSkin
	broken.facade_colors = [] as Array[Color]
	assert_true(broken.errors().size() > 0, "a city with no facade colours is an error")
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(rooftop)
	assert_eq(dressing.build_error, "")
	assert_true(dressing.has_rooftop())
	assert_false(dressing.has_forest())
	assert_eq(dressing.capture_state()["car_count"], 0, "no car is built")
	assert_eq(dressing.find_child("Road", true, false).get_child_count(), 0, "no road is laid")
	assert_eq(dressing.find_child("Pavement", true, false).get_child_count(), 0, "no pavement either")
	assert_eq(dressing.find_child("Buildings", true, false).get_child_count(), 0, "no neighbouring shops at roof level")
	assert_eq(dressing.find_child("StreetLamps", true, false).get_child_count(), 0, "no street lamps")
	assert_eq(dressing.far_root.get_child_count(), 0, "no far road")
	assert_eq(dressing.ground_root.get_child_count(), 0, "the street's meadow gives way to the roof")
	assert_eq(dressing.walker_state(), [] as Array[Dictionary], "nobody strolls past at roof level")
	var roof: NeighbourhoodRooftop = dressing.rooftop()
	assert_not_null(roof, "the rooftop is built")
	assert_true(roof.lots.size() > 40, "a whole city stands round the tower")
	var towers: int = 0
	for lot: NeighbourhoodRooftop.Lot in roof.lots:
		assert_true(lot.top <= NeighbourhoodRooftop.TOWER_TOP + 0.001, "ours is the tallest tower in town")
		if lot.kind == &"tower":
			towers += 1
	assert_true(towers >= 2, "a few towers carry aircraft lights")
	assert_eq(roof.terraces.size(), 2, "a terrace either side of the path")
	# The windows, bulbs and red lights come on from dusk; pigeons roost at night.
	dressing.set_night(0.0)
	assert_false(roof.is_lit())
	assert_true(roof.pigeons.size() > 0 and roof.pigeons[0].visible, "pigeons sit on the parapet by day")
	dressing.set_night(1.0)
	assert_true(roof.is_lit(), "the city lights up at night")
	assert_false(roof.pigeons[0].visible, "the pigeons have gone to roost")
	_free(dressing)


func test_nothing_stands_on_the_lot_or_the_approach() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(ROOFTOP) as StreetPreset)
	var state: Dictionary = dressing.capture_state()
	var reserve: AABB = _box(state["bounds"]["reserve"])
	var lot: AABB = AABB(Vector3(RESERVE.position.x, 0.0, RESERVE.position.y) * GridMath.CELL_SIZE,
		Vector3(RESERVE.size.x, 1.0, RESERVE.size.y) * GridMath.CELL_SIZE)
	assert_true(reserve.encloses(lot.grow(-0.01)), "the reserve covers the maximum lot")
	var keep_off: Array[AABB] = [reserve]
	for box: Dictionary in state["bounds"]["door_approaches"]:
		keep_off.append(_box(box))
	assert_true(keep_off.size() > 1, "the door has an approach")
	var roof: NeighbourhoodRooftop = dressing.rooftop()
	var frame: Transform3D = roof.root.global_transform
	var pieces: Array[MeshInstance3D] = []
	for label: NodePath in [^"Props", ^"Glass", ^"Tower"]:
		pieces.append(roof.root.get_node(label) as MeshInstance3D)
	for chunk: Node in roof.root.get_node(^"City").get_children():
		pieces.append(chunk as MeshInstance3D)
	assert_true(pieces.size() > 6, "the city is batched in chunks")
	# Only flat roof (under the floor line) lies under the lot and the approach.
	for piece: MeshInstance3D in pieces:
		var stray: int = 0
		for point: Vector3 in (piece.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			var world: Vector3 = frame * point
			if world.y < 0.02:
				continue
			for box: AABB in keep_off:
				if world.x > box.position.x and world.x < box.end.x and world.z > box.position.z and world.z < box.end.z:
					stray += 1
		assert_eq(stray, 0, "nothing in %s stands on the lot or the door's approach" % piece.name)
	for vertex: Vector3 in (roof.root.get_node(^"Roof") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		assert_true(vertex.y < 0.0, "the roof's surface lies under the shop floor")
		break
	# The pieces' own rects keep off the lot and the approach too.
	var local_keep: Array[Rect2] = []
	for box: AABB in keep_off:
		var local: AABB = frame.affine_inverse() * box
		local_keep.append(Rect2(local.position.x, local.position.z, local.size.x, local.size.z).grow(-0.001))
	for rect: Rect2 in [roof.lobby] + roof.terraces:
		for keep: Rect2 in local_keep:
			assert_false(rect.intersects(keep), "%s stays off the lot and the approach" % rect)
	# The parapet frames the whole lot, with room for the lobby and plant.
	var local_reserve: AABB = frame.affine_inverse() * reserve
	assert_true(roof.roof.encloses(Rect2(local_reserve.position.x, local_reserve.position.z, local_reserve.size.x, local_reserve.size.z).grow(2.0)),
		"the roof runs well past the maximum lot")
	assert_true(roof.roof.encloses(roof.lobby.grow(1.0)), "the lobby stands on the roof")
	_free(dressing)


func test_the_lobby_doors_face_the_entrance() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(ROOFTOP) as StreetPreset)
	var roof: NeighbourhoodRooftop = dressing.rooftop()
	var door: Rect2 = roof.door
	assert_true(door.has_area(), "the shop's door was found")
	assert_true(roof.lobby.position.x < door.get_center().x and roof.lobby.end.x > door.get_center().x,
		"the lobby stands square in front of the door")
	assert_true(roof.lobby.position.y > door.end.y, "out past the door's approach")
	assert_almost_eq(roof.walkway.get_center().x, door.get_center().x, 0.001, "the path runs straight from the lobby to the door")
	assert_almost_eq(roof.walkway.end.y, roof.lobby.position.y, 0.001, "and meets the lobby's doors")
	_free(dressing)


func test_the_rooftop_is_the_same_every_build_and_frame() -> void:
	await _host()
	var first: NeighbourhoodDressing = _dressing(load(ROOFTOP) as StreetPreset)
	var a: String = _digest(first)
	first.set_review_time(31.5)
	var roof: NeighbourhoodRooftop = first.rooftop()
	var pose: String = var_to_str([roof.pigeon_transform(0, 31.5), roof.bird_transform(2, 31.5), roof.plane_transform(31.5),
		roof.pigeons[1].transform, roof.fans[0].rotation])
	first.set_review_time(80.0)
	first.set_review_time(31.5)
	assert_eq(var_to_str([roof.pigeon_transform(0, 31.5), roof.bird_transform(2, 31.5), roof.plane_transform(31.5),
		roof.pigeons[1].transform, roof.fans[0].rotation]), pose, "the same time shows the same frame")
	_free(first)
	NeighbourhoodDressing.clear_mesh_cache()
	var second: NeighbourhoodDressing = _dressing(load(ROOFTOP) as StreetPreset)
	assert_eq(_digest(second), a, "the city is laid out the same way every time (no randomness)")
	_free(second)


## Clouds far off only (#618): none drifts just under the roof. Each puff drifts along
## u alone (city_cloud.gdshader moves VERTEX.x), so a puff whose every vertex keeps well
## clear of the roof across v, and deep below it, never comes near the tower.
func test_no_cloud_drifts_near_the_roof() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(ROOFTOP) as StreetPreset)
	var roof: NeighbourhoodRooftop = dressing.rooftop()
	var clouds: MeshInstance3D = dressing.find_child("Clouds", true, false) as MeshInstance3D
	assert_not_null(clouds, "the rooftop still has clouds, far off")
	var vertices: PackedVector3Array = clouds.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(vertices.size() > 0, "the clouds are drawn")
	var clear: float = roof.roof.size.y * 0.5 + 8.0
	var near: int = 0
	for vertex: Vector3 in vertices:
		if absf(vertex.z - roof.centre().y) < clear or vertex.y > -20.0:
			near += 1
	assert_eq(near, 0, "every cloud stays at least 8 m clear of the roof's sides and 20 m below it")
	var shader: String = (clouds.material_override as ShaderMaterial).shader.code
	assert_true(shader.contains("VERTEX.x +=") and not shader.contains("VERTEX.z"), "clouds drift along u only")
	_free(dressing)


func test_the_rooftop_lot_stands_on_the_rooftop() -> void:
	var lot: LotDef = load(LOT) as LotDef
	assert_eq(lot.street_preset, ROOFTOP)
	assert_eq(String(StreetPreset.for_lot(lot).id), "rooftop")


func test_the_other_streets_are_unchanged() -> void:
	await _host()
	for path: String in DIGESTS:
		var dressing: NeighbourhoodDressing = _dressing(load(path) as StreetPreset)
		assert_eq(dressing.build_error, "")
		assert_false(dressing.has_rooftop())
		assert_null(dressing.rooftop())
		assert_eq(_digest(dressing), DIGESTS[path], "%s builds exactly what it did before the rooftop" % path)
		_free(dressing)
		NeighbourhoodDressing.clear_mesh_cache()
