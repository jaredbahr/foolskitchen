extends TestCase
## Street furniture, night lamps and small life (#423): props stand only on the free pavement
## band (never in a lane, a door approach, the lot or on each other), the plan and its meshes are
## deterministic, the lamps glow at night and not by day, the idle life is a pure function of the
## display clock, and the whole thing stays view-only and cheap.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const MAIN: PackedScene = preload("res://src/world/main.tscn")
const DAY_LIGHT: DayLightTuning = preload("res://data/look/day_light.tres")
## The near pedestrian lane's inner edge: props stay short of it.
const NEAR_LANE_EDGE: float = 2.255
const RESERVES: Array[Rect2i] = [Rect2i(-2, -2, 12, 9), Rect2i(-4, -3, 16, 15)]

var _viewport: SubViewport
var _main: Node3D


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	NeighbourhoodDressing.clear_mesh_cache()
	Clock.set_speed(0)
	GameState.new_run(1)


func _host() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)


func _dressing(quarter: int, reserve: Rect2i, salt: int = 7) -> NeighbourhoodDressing:
	var grid: SimGrid = _grid(quarter)
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	var set: StreetSet = StreetSet.standard()
	set.seed_salt = salt
	dressing.street_set = set
	var normal: Vector2i = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT][quarter]
	dressing.configure(grid, _rotate_rect(reserve, quarter), [{"cells": grid.entries().duplicate(), "normal": normal}] as Array[Dictionary],
		[] as Array[AABB])
	return dressing


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


func _free_dressing(dressing: NeighbourhoodDressing) -> void:
	dressing.get_parent().remove_child(dressing)
	dressing.free()


## A world box (dressing space) as an (u, v) rectangle in the street's local frame.
func _local_rect(dressing: NeighbourhoodDressing, box: Dictionary) -> Rect2:
	var world: AABB = AABB(Vector3(box["position"][0], box["position"][1], box["position"][2]),
		Vector3(box["size"][0], box["size"][1], box["size"][2]))
	var local: AABB = dressing.local_frame().affine_inverse() * world
	return Rect2(local.position.x, local.position.z - dressing.street_shift(), local.size.x, local.size.z)


func _overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - 0.0001 and a.end.x > b.position.x + 0.0001 \
		and a.position.y < b.end.y - 0.0001 and a.end.y > b.position.y + 0.0001


func _assert_props_clear(dressing: NeighbourhoodDressing, label: String) -> int:
	var bounds: Dictionary = dressing.capture_state()["bounds"]
	var reserve: Rect2 = _local_rect(dressing, bounds["reserve"])
	var forbidden: Array[Rect2] = []
	for key: String in ["door_approaches", "native_pavement", "pedestrian_sweeps"]:
		for box: Dictionary in bounds[key]:
			forbidden.append(_local_rect(dressing, box))
	var doors: Array[float] = dressing.shop_door_positions()
	var plan: Array[Dictionary] = dressing.furniture_plan()
	var shops: Array[AABB] = []
	for box: AABB in dressing.building_footprints():
		if box.position.z + box.size.z * 0.5 < dressing.street_shift():
			shops.append(box)
	for index: int in plan.size():
		var rect: Rect2 = plan[index]["rect"]
		var id: String = "%s prop %d (kind %d)" % [label, index, int(plan[index]["kind"])]
		assert_true(rect.position.y >= NeighbourhoodFurniture.BAND_LO - 0.0001, "%s is past the shop stock and awnings" % id)
		assert_true(rect.end.y <= NEAR_LANE_EDGE - 0.05, "%s stays out of the near walking lane" % id)
		assert_true(rect.end.x <= reserve.position.x - 0.0 or rect.position.x >= reserve.end.x,
			"%s is not in front of the lot" % id)
		for box: Rect2 in forbidden:
			assert_false(_overlaps(rect, box), "%s clears the door approach, the entrance pads and every walking sweep" % id)
		for door: float in doors:
			assert_false(_overlaps(rect, Rect2(door - 0.5, 0.0, 1.0, 2.2)), "%s clears the neighbours' doors" % id)
		for shop: AABB in shops:
			assert_false(_overlaps(rect, Rect2(shop.position.x, shop.position.z - dressing.street_shift(), shop.size.x, shop.size.z)),
				"%s clears the shop fronts and their awnings" % id)
		for other: int in range(index + 1, plan.size()):
			assert_false(_overlaps(rect, plan[other]["rect"]), "%s does not overlap prop %d" % [id, other])
	return plan.size()


func test_street_furniture_never_stands_in_a_lane_a_door_approach_or_the_lot_across_salts_shifts_and_rotations() -> void:
	await _host()
	var props: int = 0
	for quarter: int in 4:
		for reserve: Rect2i in RESERVES:
			for salt: int in [7, 99]:
				var dressing: NeighbourhoodDressing = _dressing(quarter, reserve, salt)
				assert_eq(dressing.build_error, "")
				var label: String = "quarter %d reserve %s salt %d" % [quarter, str(reserve), salt]
				var count: int = _assert_props_clear(dressing, label)
				assert_true(count >= 9, "%s: most of the street's list finds a place (%d)" % [label, count])
				props += count
				_free_dressing(dressing)
	assert_true(props > 100)


func test_more_salts_keep_every_prop_clear_and_each_kind_is_planned() -> void:
	await _host()
	var kinds: Dictionary = {}
	for salt: int in [3, 11, 23, 1234, 99999]:
		var dressing: NeighbourhoodDressing = _dressing(0, RESERVES[0], salt)
		_assert_props_clear(dressing, "salt %d" % salt)
		for item: Dictionary in dressing.furniture_plan():
			kinds[int(item["kind"])] = true
		_free_dressing(dressing)
	for kind: int in [StreetPropSpec.Kind.TREE_PLANTER, StreetPropSpec.Kind.BENCH, StreetPropSpec.Kind.BIN,
			StreetPropSpec.Kind.BIKE_RACK, StreetPropSpec.Kind.HYDRANT, StreetPropSpec.Kind.BUS_STOP, StreetPropSpec.Kind.POSTBOX]:
		assert_true(kinds.has(kind), "kind %d is placed" % kind)


func test_the_plan_and_its_meshes_are_deterministic_and_the_salt_changes_them() -> void:
	await _host()
	var first: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	var second: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	assert_eq(first.furniture_plan(), second.furniture_plan())
	var a: MeshInstance3D = first.find_child("PropBody", true, false) as MeshInstance3D
	var b: MeshInstance3D = second.find_child("PropBody", true, false) as MeshInstance3D
	assert_true(a != null and b != null)
	assert_eq(a.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], b.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var shadow_a: MeshInstance3D = first.find_child("PropShadows", true, false) as MeshInstance3D
	var shadow_b: MeshInstance3D = second.find_child("PropShadows", true, false) as MeshInstance3D
	assert_eq(shadow_a.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], shadow_b.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var other: NeighbourhoodDressing = _dressing(0, RESERVES[0], 99)
	assert_ne(first.furniture_plan(), other.furniture_plan(), "a different seed salt sets the furniture out differently")
	_free_dressing(first)
	_free_dressing(second)
	_free_dressing(other)


func test_a_street_set_can_swap_the_prop_list() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	var before: int = dressing.furniture_plan().size()
	var seaside: StreetSet = StreetSet.standard()
	seaside.furniture = [StreetPropSpec.make(StreetPropSpec.Kind.BENCH, 1, StreetPropSpec.Zone.WALL)]
	dressing.street_set = seaside
	dressing.rebuild()
	assert_eq(dressing.furniture_plan().size(), 1)
	assert_true(before > 1)
	seaside.furniture = []
	assert_ne(seaside.signature(), StreetSet.standard().signature(), "the prop list is part of the street's cache key")
	_free_dressing(dressing)


func test_every_prop_stands_on_a_baked_contact_shadow() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	var shadow: MeshInstance3D = dressing.find_child("PropShadows", true, false) as MeshInstance3D
	assert_not_null(shadow)
	var vertices: PackedVector3Array = shadow.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shift: float = dressing.street_shift()
	for item: Dictionary in dressing.furniture_plan():
		var rect: Rect2 = item["rect"]
		var centre: Vector2 = rect.get_center()
		var covered: bool = false
		# Some shadow triangle lies under the prop's centre (the shadow polygon is a fan, so test its triangles).
		for index: int in range(0, vertices.size() - 2, 3):
			var triangle: PackedVector2Array = PackedVector2Array([Vector2(vertices[index].x, vertices[index].z - shift),
				Vector2(vertices[index + 1].x, vertices[index + 1].z - shift), Vector2(vertices[index + 2].x, vertices[index + 2].z - shift)])
			if Geometry2D.is_point_in_polygon(centre, triangle):
				covered = true
				break
		assert_true(covered, "kind %d at %s has a shadow under it" % [int(item["kind"]), str(centre)])
	_free_dressing(dressing)


func test_street_furniture_and_life_are_view_only_and_cheap() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	var triangles: int = 0
	var draws: int = 0
	for root_name: String in ["Furniture", "Life"]:
		var root: Node = dressing.find_child(root_name, true, false)
		assert_not_null(root, root_name)
		for node: Node in root.find_children("*", "", true, false) + [root]:
			assert_false(node is Light3D, "no real lights (view-only rule)")
			assert_false(node is CollisionObject3D)
			assert_false(node is CollisionShape3D)
			assert_false(node is NavigationRegion3D)
			var geometry: GeometryInstance3D = node as GeometryInstance3D
			if geometry != null:
				assert_eq(geometry.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh != null and mesh.mesh != null:
				draws += mesh.mesh.get_surface_count()
				for surface: int in mesh.mesh.get_surface_count():
					triangles += (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var instances: MultiMeshInstance3D = node as MultiMeshInstance3D
			if instances != null:
				draws += 1
				triangles += (instances.multimesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3 * instances.multimesh.instance_count
	assert_true(triangles > 500, "the props and life exist: %d triangles" % triangles)
	assert_true(triangles < 4000, "the props, lamps' glow and life stay cheap: %d triangles" % triangles)
	# Sixteen for the props, lamps and life, plus up to three lit-window meshes (#440).
	assert_true(draws <= 19, "the props, lamps' glow, windows and life batch into few draw calls: %d" % draws)
	var furniture: MeshInstance3D = dressing.find_child("PropBody", true, false) as MeshInstance3D
	assert_eq(furniture.mesh.get_surface_count(), 1, "every static prop is one batched mesh")
	_free_dressing(dressing)


func test_street_lamps_glow_at_night_and_are_off_by_day() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	var day: Dictionary = dressing.lamp_state()
	assert_eq(day["lamps"], 2)
	assert_eq(day["night"], 0.0)
	assert_eq(day["bulb_energy"], 0.0, "the bulb is dark by day")
	assert_false(day["glow_visible"], "no pool of light by day")
	assert_false(day["halos_visible"])
	dressing.set_night(1.0)
	var night: Dictionary = dressing.lamp_state()
	assert_true(night["bulb_energy"] > 1.0, "the emissive bulb is lit at night")
	assert_true(night["glow_visible"] and night["halos_visible"], "the soft glow discs show at night")
	assert_eq(night["glow_alpha"], 1.0)
	dressing.set_night(0.5)
	assert_true(dressing.lamp_state()["bulb_energy"] < night["bulb_energy"], "dusk is in between")
	dressing.set_night(0.0)
	assert_eq(dressing.lamp_state()["bulb_energy"], 0.0)
	assert_false(dressing.lamp_state()["glow_visible"])
	# A rebuild keeps the night the day cycle last set.
	dressing.set_night(1.0)
	dressing.street_set = StreetSet.standard()
	dressing.street_set.seed_salt = 5
	dressing.rebuild()
	assert_true(dressing.lamp_state()["glow_visible"])
	for node: Node in dressing.find_children("*", "Light3D", true, false):
		assert_true(false, "lamps use emissive meshes, never %s" % node.name)
	_free_dressing(dressing)


func test_the_day_cycle_lights_the_lamps_at_dusk_and_not_at_midday() -> void:
	var midday: DayLight.Look = DayLight.sample(780.0, DAY_LIGHT)
	var morning: DayLight.Look = DayLight.sample(480.0, DAY_LIGHT)
	var dusk: DayLight.Look = DayLight.sample(1230.0, DAY_LIGHT)
	var night: DayLight.Look = DayLight.sample(1320.0, DAY_LIGHT)
	assert_eq(DayNightView.street_night(midday), 0.0)
	assert_eq(DayNightView.street_night(morning), 0.0)
	assert_eq(DayNightView.street_night(dusk), 1.0)
	assert_eq(DayNightView.street_night(night), 1.0)
	var evening: float = DayNightView.street_night(DayLight.sample(1155.0, DAY_LIGHT))
	assert_true(evening > 0.0 and evening < 1.0, "the lamps come on gradually")


func test_main_drives_the_street_lamps_from_the_real_clock() -> void:
	await _host()
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("owner_creation_requested", false)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set_process(false)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var world: SimWorld = _main.get("world") as SimWorld
	var dressing: NeighbourhoodDressing = (_main.get_node("ShopView") as ShopView).neighbourhood_dressing
	assert_not_null(dressing)
	world.clock.phase = SimClock.Phase.MORNING
	_main.call("refresh_presentation")
	assert_eq(dressing.lamp_state()["night"], 0.0, "the lamps are off in the morning")
	assert_false(dressing.lamp_state()["glow_visible"])
	world.clock.phase = SimClock.Phase.CLOSED
	world.clock.phase_tick = 0
	_main.call("refresh_presentation")
	assert_eq(dressing.lamp_state()["night"], 1.0, "the lamps are on once the shop has closed for the night")
	assert_true(dressing.lamp_state()["glow_visible"])
	world.clock.phase = SimClock.Phase.MORNING
	_main.call("refresh_presentation")
	assert_eq(dressing.lamp_state()["night"], 0.0)


func test_small_life_is_a_pure_function_of_the_display_clock() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	var life: NeighbourhoodLife = dressing.life()
	assert_eq(life.sign_nodes.size(), 4, "a hanging sign on each neighbouring shop")
	assert_eq(life.bird_nodes.size(), 3)
	assert_eq(life.leaf_transforms.size(), 8)
	assert_true(dressing.set_review_time(12.5))
	var signs: Array[Transform3D] = []
	for node: MeshInstance3D in life.sign_nodes:
		signs.append(node.transform)
	var birds: Array[Transform3D] = []
	for node: MeshInstance3D in life.bird_nodes:
		birds.append(node.transform)
	var leaves: Array[Transform3D] = life.leaf_transforms.duplicate()
	assert_true(dressing.set_review_time(40.0))
	assert_true(dressing.set_review_time(12.5))
	for index: int in signs.size():
		assert_eq(life.sign_nodes[index].transform, signs[index], "the same time shows the same sign")
	for index: int in birds.size():
		assert_eq(life.bird_nodes[index].transform, birds[index], "the same time shows the same bird")
	assert_eq(life.leaf_transforms, leaves)
	var moved_sign: bool = false
	var moved_bird: bool = false
	var moved_leaf: bool = false
	dressing.set_review_time(14.0)
	for index: int in signs.size():
		moved_sign = moved_sign or life.sign_nodes[index].transform != signs[index]
	for index: int in birds.size():
		moved_bird = moved_bird or life.bird_nodes[index].transform != birds[index]
	moved_leaf = life.leaf_transforms != leaves
	assert_true(moved_sign and moved_bird and moved_leaf, "signs sway, birds move and leaves drift with the clock")
	# No random draws and no wall clock: only the display clock and integer hashes.
	for path: String in ["res://src/world/neighbourhood_life.gd", "res://src/world/neighbourhood_furniture.gd"]:
		var source: String = FileAccess.get_file_as_string(path)
		for banned: String in ["randf", "randi", "Time.", "RandomNumberGenerator"]:
			assert_false(source.contains(banned), "%s has no %s" % [path, banned])
	_free_dressing(dressing)


func test_signs_sway_a_modest_angle_and_birds_stay_on_the_lawn_beside_the_lot_and_hop_low() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	var life: NeighbourhoodLife = dressing.life()
	var limit: float = deg_to_rad(dressing.street_set.sign_sway_degrees) + 0.0001
	var widest: float = 0.0
	var lot: Rect2 = _local_rect(dressing, dressing.capture_state()["bounds"]["reserve"])
	var footprints: Array[AABB] = dressing.building_footprints()
	var shift: float = dressing.street_shift()
	for step: int in 400:
		var time: float = float(step) * 0.37
		for index: int in life.sign_nodes.size():
			var angle: float = life.sign_angle(index, time)
			widest = maxf(widest, absf(angle))
			assert_true(absf(angle) <= limit, "sign %d at %f swings %f" % [index, time, angle])
		for index: int in life.bird_nodes.size():
			var pose: Dictionary = life.bird_pose(index, time)
			assert_true(float(pose["hop"]) >= 0.0 and float(pose["hop"]) <= 0.15, "a bird hops low")
			var spot: Rect2 = Rect2(float(pose["u"]) - 0.15, float(pose["z"]) - shift - 0.15, 0.3, 0.3)
			assert_false(_overlaps(spot, lot), "bird %d never enters the lot (time %f)" % [index, time])
			for box: AABB in footprints:
				assert_false(_overlaps(spot, Rect2(box.position.x, box.position.z - shift, box.size.x, box.size.z)),
					"bird %d stays off the buildings" % index)
			assert_true(float(pose["z"]) - shift < 0.0, "birds hop on the lawn behind the pavement")
	assert_true(widest > deg_to_rad(4.0), "the signs really swing")
	_free_dressing(dressing)


func test_life_stops_when_the_dressing_stops_processing() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing(0, RESERVES[0])
	dressing.set_process(true)
	assert_true(dressing.is_processing())
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame
	assert_true(dressing.display_seconds > 0.0, "the tree really drives _process while processing")
	dressing.set_process(false)
	assert_false(dressing.is_processing())
	var seconds: float = dressing.display_seconds
	var life: NeighbourhoodLife = dressing.life()
	var frozen: Array[Transform3D] = life.leaf_transforms.duplicate()
	var sign: Transform3D = life.sign_nodes[0].transform
	for frame: int in 5:
		await tree.process_frame
	assert_eq(dressing.display_seconds, seconds, "the display clock does not advance")
	assert_eq(life.leaf_transforms, frozen, "nothing animates once the dressing is not processing")
	assert_eq(life.sign_nodes[0].transform, sign)
	_free_dressing(dressing)


func test_a_dressing_recreated_at_night_has_its_lamps_on_at_once() -> void:
	await _host()
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("owner_creation_requested", false)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set_process(false)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var world: SimWorld = _main.get("world") as SimWorld
	world.clock.phase = SimClock.Phase.CLOSED
	world.clock.phase_tick = 0
	# Binding the world again builds a brand new shop view and dressing while it is night.
	_main.call("_bind_world_presentation")
	var dressing: NeighbourhoodDressing = (_main.get_node("ShopView") as ShopView).neighbourhood_dressing
	assert_not_null(dressing)
	assert_eq(world.clock.phase, SimClock.Phase.CLOSED)
	assert_eq(dressing.lamp_state()["night"], 1.0, "lamps are on straight after show_world")
	assert_true(dressing.lamp_state()["glow_visible"])
