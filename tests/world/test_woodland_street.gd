extends TestCase
## The woodland cabin's street (#607): a clearing on a forest track. The woodland
## preset is valid and has no traffic; its named stands of trees exist beside and
## behind the lot, never over its maximum footprint, and can show stumps or cleared
## ground through a rebuild; and the starter street is exactly what it was.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const WOODLAND: String = "res://data/streets/woodland.tres"
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)
## The starter street's digest (see `_digest`), the same one test_promenade_street.gd
## holds: a change here means the starter street changed.
const STARTER_DIGEST: String = "aacd560112720e7b4f6c719fd747873106abd731cf8131875be5ac01ffd4d5ff"

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


func _configure(dressing: NeighbourhoodDressing, grid: SimGrid) -> void:
	dressing.configure(grid, RESERVE, [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])


func _dressing(preset: StreetPreset) -> NeighbourhoodDressing:
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	dressing.use_preset(preset)
	_configure(dressing, _grid())
	return dressing


func _free(dressing: NeighbourhoodDressing) -> void:
	dressing.get_parent().remove_child(dressing)
	dressing.free()


func _reserve(dressing: NeighbourhoodDressing) -> AABB:
	var box: Dictionary = dressing.capture_state()["bounds"]["reserve"]
	return AABB(_vector(box["position"]), _vector(box["size"]))


static func _vector(parts: Array) -> Vector3:
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


## The same digest as test_promenade_street.gd: every static mesh (name and vertex
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


func test_the_woodland_preset_is_valid_and_has_no_traffic() -> void:
	var woodland: StreetPreset = load(WOODLAND) as StreetPreset
	assert_not_null(woodland, "the woodland is a street preset")
	assert_eq(woodland.errors(), PackedStringArray())
	assert_eq(String(woodland.id), "woodland")
	assert_not_null(woodland.forest, "it is a forest clearing")
	assert_false(woodland.has_traffic(), "no cars come down a forest track")
	assert_true(StreetPreset.starter().has_traffic(), "the starter street keeps its road")
	# A forest with no walkers or an unknown walker is refused, in plain words.
	var broken: ForestSkin = woodland.forest.duplicate() as ForestSkin
	broken.walkers = [&"skate"] as Array[StringName]
	assert_true(broken.errors().size() > 0, "an unknown walker is an error")
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(woodland)
	assert_eq(dressing.build_error, "")
	assert_true(dressing.has_forest())
	assert_eq(dressing.capture_state()["car_count"], 0, "no car is built")
	assert_eq(dressing.find_child("Road", true, false).get_child_count(), 0, "no road is laid")
	assert_eq(dressing.find_child("Pavement", true, false).get_child_count(), 0, "no pavement either")
	assert_eq(dressing.find_child("Buildings", true, false).get_child_count(), 0, "no neighbouring buildings")
	assert_eq(dressing.far_root.get_child_count(), 0, "no far road")
	assert_eq(dressing.ground_root.get_child_count(), 0, "the street's meadow gives way to the clearing")
	assert_not_null(dressing.forest(), "the clearing is built")
	# Hikers and cyclists come along the track, and keep to it at any time.
	var kinds: Dictionary[StringName, bool] = {}
	for walker: Dictionary in dressing.walker_state():
		kinds[walker["kind"]] = true
	assert_true(kinds.has(&"hike"), "a hiker is out")
	assert_true(kinds.has(&"cycle"), "a cyclist is out")
	for seconds: float in [3.0, 47.5, 130.0]:
		dressing.set_review_time(seconds)
		for walker: Dictionary in dressing.walker_state():
			var local: Vector3 = dressing.local_frame().affine_inverse() * (walker["position"] as Vector3)
			var off: float = absf(local.z - dressing.forest().track_z(local.x))
			assert_true(off < NeighbourhoodForest.TRACK_HALF, "the %s keeps to the track (%.2f m off its middle)" % [walker["kind"], off])
			if walker["kind"] in [&"hike", &"cycle"]:
				assert_true(walker.has("prop"), "the %s has their backpack or bike" % walker["kind"])
	dressing.set_review_time(12.5)
	var first: String = var_to_str(dressing.walker_state())
	dressing.set_review_time(40.0)
	dressing.set_review_time(12.5)
	assert_eq(var_to_str(dressing.walker_state()), first, "the same time shows the same frame")
	# The fire burns and the bulbs glow only from dusk.
	dressing.set_night(0.0)
	assert_false(dressing.forest().is_fire_lit(), "no fire by day")
	dressing.set_night(1.0)
	assert_true(dressing.forest().is_fire_lit(), "the fire is lit at night")
	_free(dressing)


func test_the_stands_exist_beside_and_behind_the_lot() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(WOODLAND) as StreetPreset)
	var ids: Array[StringName] = dressing.stand_ids()
	assert_eq(ids.size(), 3, "a stand on each side and one behind")
	# The lot fronts south (the entrances face +z), so its sides are west and east and its back north.
	for id: StringName in [&"west", &"east", &"north"]:
		assert_true(ids.has(id), "the %s stand is there" % id)
		assert_eq(dressing.stand_state(id), NeighbourhoodForest.StandState.FOREST, "standing forest by default")
		var node: Node3D = dressing.forest().stand(id).node
		assert_not_null(node, "%s has its own node" % id)
		for look: NodePath in [^"Forest", ^"Stumps", ^"Cleared"]:
			assert_not_null(node.get_node_or_null(look), "%s can show %s" % [id, look])
		assert_true(dressing.forest().stand(id).trees.size() >= 6, "%s is a real stand of trees" % id)
	assert_true(dressing.stand_bounds(&"east").get_center().x > dressing.stand_bounds(&"west").get_center().x, "east is east of west")
	assert_true(dressing.stand_bounds(&"north").get_center().z < _reserve(dressing).position.z, "north is behind the lot")
	assert_eq(dressing.stand_bounds(&"south"), AABB(), "no stand over the track")
	_free(dressing)


func test_stands_never_overlap_the_lot() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(WOODLAND) as StreetPreset)
	var reserve: AABB = _reserve(dressing)
	var lot: AABB = AABB(Vector3(RESERVE.position.x, 0.0, RESERVE.position.y) * GridMath.CELL_SIZE,
		Vector3(RESERVE.size.x, 1.0, RESERVE.size.y) * GridMath.CELL_SIZE)
	assert_true(reserve.encloses(lot.grow(-0.01)), "the reserve covers the maximum lot")
	for id: StringName in dressing.stand_ids():
		var bounds: AABB = dressing.stand_bounds(id)
		assert_true(bounds.size.x > 0.0 and bounds.size.z > 0.0, "%s has bounds" % id)
		assert_false(NeighbourhoodMeshBatch.xz_intersects(bounds, reserve),
			"no tree in the %s stand reaches over the lot (crowns included)" % id)
		for other: StringName in dressing.stand_ids():
			if other != id:
				var a: Rect2 = dressing.forest().stand(id).rect
				var b: Rect2 = dressing.forest().stand(other).rect
				assert_false(a.intersects(b), "the %s and %s stands do not overlap" % [id, other])
	# Nothing the clearing stands up (trees, porch, woodpile, fire pit, bridge) is on
	# the lot or in front of its door; only flat ground lies under them.
	var keep_off: Array[AABB] = [reserve]
	for box: Dictionary in dressing.capture_state()["bounds"]["door_approaches"]:
		keep_off.append(AABB(_vector(box["position"]), _vector(box["size"])))
	var frame: Transform3D = dressing.forest().root.global_transform
	var pieces: Array[MeshInstance3D] = [dressing.forest().root.get_node(^"Props") as MeshInstance3D]
	for chunk: Node in dressing.forest().root.get_node(^"Forest").get_children():
		pieces.append(chunk as MeshInstance3D)
	assert_true(pieces.size() > 10, "the forest is batched in chunks")
	for piece: MeshInstance3D in pieces:
		var label: String = String(piece.name)
		var stray: int = 0
		for point: Vector3 in (piece.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			if point.y < 0.02:
				continue
			var world: Vector3 = frame * point
			for box: AABB in keep_off:
				if world.x > box.position.x and world.x < box.end.x and world.z > box.position.z and world.z < box.end.z:
					stray += 1
		assert_eq(stray, 0, "nothing in %s stands on the lot or the door's approach" % label)
	_free(dressing)


func test_stand_state_survives_a_rebuild() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(load(WOODLAND) as StreetPreset)
	assert_true(dressing.set_stand_state(&"east", NeighbourhoodForest.StandState.STUMPS))
	assert_true(dressing.set_stand_state(&"north", NeighbourhoodForest.StandState.CLEARED))
	assert_false(dressing.set_stand_state(&"nowhere", NeighbourhoodForest.StandState.CLEARED), "an unknown stand is refused")
	var east: Node3D = dressing.forest().stand(&"east").node
	assert_false((east.get_node(^"Forest") as Node3D).visible, "felled: the trees are gone")
	assert_true((east.get_node(^"Stumps") as Node3D).visible, "the stumps show")
	var generation: int = dressing.capture_state()["rebuild_generation"]
	# A fresh grid forces a real rebuild of the whole street.
	_configure(dressing, _grid())
	assert_true(int(dressing.capture_state()["rebuild_generation"]) > generation, "the street was rebuilt")
	assert_eq(dressing.build_error, "")
	assert_eq(dressing.stand_state(&"east"), NeighbourhoodForest.StandState.STUMPS)
	assert_eq(dressing.stand_state(&"north"), NeighbourhoodForest.StandState.CLEARED)
	assert_eq(dressing.stand_state(&"west"), NeighbourhoodForest.StandState.FOREST)
	east = dressing.forest().stand(&"east").node
	var north: Node3D = dressing.forest().stand(&"north").node
	var west: Node3D = dressing.forest().stand(&"west").node
	assert_true((east.get_node(^"Stumps") as Node3D).visible, "still stumps after the rebuild")
	assert_false((east.get_node(^"Forest") as Node3D).visible)
	assert_true((north.get_node(^"Cleared") as Node3D).visible, "still cleared after the rebuild")
	assert_false((north.get_node(^"Stumps") as Node3D).visible)
	assert_true((west.get_node(^"Forest") as Node3D).visible, "the untouched stand still stands")
	assert_true(dressing.set_stand_state(&"east", NeighbourhoodForest.StandState.FOREST))
	assert_true((east.get_node(^"Forest") as Node3D).visible, "and can grow back for a review")
	_free(dressing)


func test_the_forest_is_the_same_every_build() -> void:
	await _host()
	var first: NeighbourhoodDressing = _dressing(load(WOODLAND) as StreetPreset)
	var a: String = _digest(first)
	_free(first)
	NeighbourhoodDressing.clear_mesh_cache()
	var second: NeighbourhoodDressing = _dressing(load(WOODLAND) as StreetPreset)
	assert_eq(_digest(second), a, "the forest is planted the same way every time (no randomness)")
	_free(second)


func test_the_starter_street_is_unchanged() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(StreetPreset.starter())
	assert_eq(dressing.build_error, "")
	assert_false(dressing.has_forest())
	assert_eq(dressing.stand_ids(), [] as Array[StringName], "a street has no stands")
	assert_false(dressing.set_stand_state(&"east", NeighbourhoodForest.StandState.STUMPS))
	assert_eq(_digest(dressing), STARTER_DIGEST, "the starter street builds exactly what it did before the woodland")
	_free(dressing)
