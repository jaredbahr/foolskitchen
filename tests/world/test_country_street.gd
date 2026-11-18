extends TestCase
## Old Mill Street's country lane (#613): an old watermill on a narrow lane. The
## country preset is valid and has no town traffic, only a tractor and a cyclist on the
## lane; the mill stream turns a waterwheel beside the lot. The meadow beside the lot
## and the cornfield behind it are named land plots that never overlap the lot, its
## first lease or the door's approach, keep their state through a rebuild, and lie flat
## once the lease covers them. The wheel turns under a wheel house whose axle housing
## meets the shop's wall (#619). Old Mill Street stands on the lane, and the starter,
## seaside, promenade and woodland streets are exactly what they were.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const COUNTRY: String = "res://data/streets/country.tres"
const OLD_MILL: String = "res://data/lots/town_fixer_upper.tres"
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)
## The building's own cells in `_grid()`: the first lease in the land tests, two cells
## in from the maximum lot on three sides.
const FIRST_LEASE: Rect2i = Rect2i(0, 0, 8, 7)
## Every other street's digest (see `_digest`), taken on main before the country lane:
## a change here means that street changed. The starter's is the one
## test_promenade_street.gd and test_woodland_street.gd hold.
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


func _configure(dressing: NeighbourhoodDressing, grid: SimGrid) -> void:
	dressing.configure(grid, RESERVE, [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])


func _dressing(preset: StreetPreset = null) -> NeighbourhoodDressing:
	if preset == null:
		preset = load(COUNTRY) as StreetPreset
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



func _leased(current: Rect2i) -> NeighbourhoodDressing:
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	dressing.use_preset(load(COUNTRY) as StreetPreset)
	dressing.set_lease(current, FIRST_LEASE)
	_configure(dressing, _grid())
	return dressing


static func _cells_box(cells: Rect2i) -> AABB:
	return AABB(Vector3(cells.position.x, 0.0, cells.position.y) * GridMath.CELL_SIZE,
		Vector3(cells.size.x, 1.0, cells.size.y) * GridMath.CELL_SIZE)


## Vertices of `mesh` (under `frame`) higher than `above` that fall inside any box.
static func _strays(mesh: Mesh, frame: Transform3D, boxes: Array[AABB], above: float) -> int:
	var count: int = 0
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		var world: Vector3 = frame * point
		if world.y <= above:
			continue
		for box: AABB in boxes:
			if world.x > box.position.x + 0.001 and world.x < box.end.x - 0.001 \
					and world.z > box.position.z + 0.001 and world.z < box.end.z - 0.001:
				count += 1
	return count



func _approaches(dressing: NeighbourhoodDressing) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for box: Dictionary in dressing.capture_state()["bounds"]["door_approaches"]:
		boxes.append(AABB(_vector(box["position"]), _vector(box["size"])))
	return boxes


func _local(dressing: NeighbourhoodDressing, point: Vector3) -> Vector3:
	return dressing.local_frame().affine_inverse() * point


func test_the_country_preset_is_valid_and_has_no_town_traffic() -> void:
	var country: StreetPreset = load(COUNTRY) as StreetPreset
	assert_not_null(country, "the country lane is a street preset")
	assert_eq(country.errors(), PackedStringArray())
	assert_eq(String(country.id), "country")
	assert_not_null(country.country, "it is a country lane")
	assert_false(country.has_traffic(), "no town traffic comes down a country lane")
	assert_eq(country.wall_style, &"mill", "the mill's walls are stone and timber")
	var broken: CountrySkin = country.country.duplicate() as CountrySkin
	broken.walkers = [&"skate"] as Array[StringName]
	assert_true(broken.errors().size() > 0, "an unknown walker is an error")
	broken.walkers = [] as Array[StringName]
	assert_true(broken.errors().size() > 0, "an empty lane is an error")
	await _host()
	var dressing: NeighbourhoodDressing = _dressing()
	assert_eq(dressing.build_error, "")
	assert_true(dressing.has_country())
	assert_false(dressing.has_forest())
	assert_eq(dressing.capture_state()["car_count"], 0, "no car is built")
	assert_eq(dressing.find_child("Road", true, false).get_child_count(), 0, "no road is laid")
	assert_eq(dressing.find_child("Pavement", true, false).get_child_count(), 0, "no pavement either")
	assert_eq(dressing.find_child("Buildings", true, false).get_child_count(), 0, "no neighbouring shops")
	assert_eq(dressing.find_child("StreetLamps", true, false).get_child_count(), 0, "no street lamps")
	assert_eq(dressing.far_root.get_child_count(), 0, "no far road")
	assert_eq(dressing.ground_root.get_child_count(), 0, "the town's meadow gives way to the fields")
	var country_view: NeighbourhoodCountry = dressing.country()
	assert_not_null(country_view, "the lane is built")
	# A cyclist and walkers come along the lane, and keep to it at any time.
	var kinds: Dictionary[StringName, bool] = {}
	for walker: Dictionary in dressing.walker_state():
		kinds[walker["kind"]] = true
	assert_true(kinds.has(&"cycle"), "a cyclist is out")
	assert_true(kinds.has(&"stroll"), "and someone on foot")
	for seconds: float in [3.0, 47.5, 130.0]:
		dressing.set_review_time(seconds)
		for walker: Dictionary in dressing.walker_state():
			var local: Vector3 = _local(dressing, walker["position"])
			var off: float = absf(local.z - country_view.lane_z(local.x))
			assert_true(off < NeighbourhoodCountry.LANE_HALF, "the %s keeps to the lane (%.2f m off its middle)" % [walker["kind"], off])
			if walker["kind"] == &"cycle":
				assert_true(walker.has("prop"), "the cyclist has a bike")
	# The tractor keeps to the lane's middle and comes and goes; it is never town traffic.
	var seen: bool = false
	var gone: bool = false
	var seconds_at: float = 0.0
	while seconds_at < 260.0:
		dressing.set_review_time(seconds_at)
		var tractor: Node3D = country_view.tractor
		if tractor.visible:
			seen = true
			var off_lane: float = absf(tractor.position.z - country_view.lane_z(tractor.position.x))
			assert_true(off_lane < 0.2, "the tractor keeps to the lane's middle (%.2f m off)" % off_lane)
		else:
			gone = true
		seconds_at += 4.5
	assert_true(seen and gone, "the tractor comes along now and then")
	# The wheel turns with the clock, and the same time shows the same frame.
	dressing.set_review_time(12.5)
	var turned: Basis = country_view.wheel.basis
	var first: String = var_to_str([dressing.walker_state(), country_view.tractor.transform, turned])
	dressing.set_review_time(14.0)
	assert_false(country_view.wheel.basis.is_equal_approx(turned), "the waterwheel turns")
	dressing.set_review_time(12.5)
	assert_eq(var_to_str([dressing.walker_state(), country_view.tractor.transform, country_view.wheel.basis]), first,
		"the same time shows the same frame")
	# The lanterns light from dusk; the tractor goes home at night.
	dressing.set_night(0.0)
	assert_false(country_view.is_lit(), "no lanterns by day")
	dressing.set_night(1.0, 1.0)
	assert_true(country_view.is_lit(), "the lanterns are lit at night")
	for seconds: float in [10.0, 60.0, 120.0]:
		dressing.set_review_time(seconds)
		assert_false(country_view.tractor.visible, "no tractor late at night")
	_free(dressing)


func test_the_mill_stream_runs_past_the_lot() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _leased(FIRST_LEASE)
	var country_view: NeighbourhoodCountry = dressing.country()
	var reserve: AABB = _reserve(dressing)
	var local: AABB = dressing.local_frame().affine_inverse() * reserve
	# The wheel turns beside the lot, outside it, on the side without land to grow into.
	var wheel: Vector3 = country_view.wheel_at
	assert_true(wheel.x < local.position.x or wheel.x > local.end.x, "the wheel stands outside the lot")
	assert_true(wheel.z > local.position.z and wheel.z < local.end.z, "beside the lot's side")
	# The stream never runs over the lot, from behind the mill pond to past the bridge.
	var z: float = local.position.z - 8.0
	while z < country_view.lane_z(wheel.x) + 6.0:
		var u: float = country_view.stream_u(z)
		var half: float = country_view.stream_half(z)
		assert_true(u + half < local.position.x or u - half > local.end.x, "no water over the lot at z %.1f" % z)
		z += 0.5
	_free(dressing)


func test_the_plots_lie_beside_and_behind_the_lot() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing()
	var ids: Array[StringName] = dressing.plot_ids()
	assert_eq(ids.size(), 2, "a meadow beside the lot and a cornfield behind it")
	# The lot fronts south (the entrances face +z): the stream runs down its west side,
	# the meadow is east and the cornfield north.
	assert_true(ids.has(&"east") and ids.has(&"north"), "the plots are named by compass: %s" % [ids])
	assert_eq(dressing.plot_crop(&"east"), &"meadow")
	assert_eq(dressing.plot_crop(&"north"), &"corn")
	assert_eq(dressing.plot_crop(&"nowhere"), &"")
	for id: StringName in ids:
		assert_eq(dressing.plot_state(id), NeighbourhoodCountry.PlotState.GROWN, "%s grows by default" % id)
		var node: Node3D = dressing.country().plot(id).node
		for look: NodePath in [^"Grown", ^"Mown", ^"Cleared"]:
			assert_not_null(node.get_node_or_null(look), "%s can show %s" % [id, look])
		var body: MeshInstance3D = node.get_node(^"Grown/Body") as MeshInstance3D
		assert_true(body.mesh.get_surface_count() > 0, "%s has its crop" % id)
	assert_true(dressing.plot_bounds(&"east").get_center().x > _reserve(dressing).end.x, "the meadow is east of the lot")
	assert_true(dressing.plot_bounds(&"north").get_center().z < _reserve(dressing).position.z, "the cornfield is behind the lot")
	assert_eq(dressing.plot_bounds(&"south"), AABB(), "no plot over the lane")
	_free(dressing)


func test_nothing_stands_on_the_lot_the_lease_or_the_door_approach() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _leased(FIRST_LEASE)
	assert_eq(dressing.build_error, "")
	var reserve: AABB = _reserve(dressing)
	var lease: AABB = _cells_box(FIRST_LEASE)
	var approaches: Array[AABB] = _approaches(dressing)
	assert_true(approaches.size() > 0, "the door has an approach")
	var ids: Array[StringName] = dressing.plot_ids()
	for id: StringName in [&"east", &"north", &"east_land", &"west_land", &"north_land"]:
		assert_true(ids.has(id), "the plot %s is there" % id)
	for id: StringName in ids:
		var bounds: AABB = dressing.plot_bounds(id)
		var entry: NeighbourhoodCountry.Plot = dressing.country().plot(id)
		if entry.is_land:
			assert_false(NeighbourhoodMeshBatch.xz_intersects(bounds, lease.grow(-0.01)), "the land plot %s keeps off the first lease" % id)
		else:
			assert_false(NeighbourhoodMeshBatch.xz_intersects(bounds, reserve.grow(-0.01)), "the plot %s keeps off the lot" % id)
		for other: StringName in ids:
			if other != id:
				var a: Rect2 = entry.rect
				var b: Rect2 = dressing.country().plot(other).rect
				assert_false(a.grow(-0.005).intersects(b), "the plots %s and %s do not overlap" % [id, other])
		# No crop stands on the first lease or the door's approach.
		var keep_off: Array[AABB] = [lease]
		keep_off.append_array(approaches)
		for look: String in ["Grown", "Mown", "Cleared"]:
			var body: MeshInstance3D = entry.node.get_node(NodePath(look + "/Body")) as MeshInstance3D
			assert_eq(_strays(body.mesh, dressing.country().root.global_transform, keep_off, 0.02), 0,
				"nothing in %s's %s look stands on the lease or the approach" % [id, look])
	# Nothing the country stands up (walls, hedges, the forecourt's pieces, the stand,
	# trees, cottages) is on the lot or in front of its door; only flat ground lies there.
	var frame: Transform3D = dressing.country().root.global_transform
	var keep_clear: Array[AABB] = [reserve]
	keep_clear.append_array(approaches)
	for label: NodePath in [^"Props", ^"Bounds", ^"Fields", ^"Ground"]:
		var piece: MeshInstance3D = dressing.country().root.get_node(label) as MeshInstance3D
		assert_eq(_strays(piece.mesh, frame, keep_clear, 0.02), 0, "nothing in %s stands on the lot or the door's approach" % label)
	for child: Node in dressing.country().root.get_node(^"Waterwheel").get_children():
		var part: MeshInstance3D = child as MeshInstance3D
		assert_eq(_strays(part.mesh, part.global_transform, [reserve] as Array[AABB], -1.0), 0, "the waterwheel stays off the lot")
	_free(dressing)


## The world-space vertices of a mesh under `frame` (empty for an empty mesh).
static func _points(mesh: Mesh, frame: Transform3D) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	if mesh == null or mesh.get_surface_count() == 0:
		return points
	for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		points.append(frame * point)
	return points


func test_the_wheel_house_meets_the_mill_wall() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _leased(FIRST_LEASE)
	var country_view: NeighbourhoodCountry = dressing.country()
	var reserve: AABB = _reserve(dressing)
	var local: AABB = dressing.local_frame().affine_inverse() * reserve
	var frame: Transform3D = country_view.root.global_transform
	var wheel: Vector3 = country_view.wheel_at
	assert_eq(country_view.stream_side, -1.0, "the stream runs down the lot's west side")
	# The shop's wall is the building's west face, a metre in from the lot's edge.
	var building: AABB = dressing.local_frame().affine_inverse() * _cells_box(FIRST_LEASE)
	assert_almost_eq(country_view.mill_wall, building.position.x, 0.001, "the housing runs to the shop's west wall")
	# A slate roof stands over the wheel, off the lot.
	var roofed: int = 0
	for point: Vector3 in _points((country_view.root.get_node(^"Props") as MeshInstance3D).mesh, Transform3D.IDENTITY):
		if point.y > NeighbourhoodCountry.HOUSE_LOW and absf(point.z - wheel.z) < NeighbourhoodCountry.HOUSE_HALF \
				and absf(point.x - wheel.x) < NeighbourhoodCountry.WHEEL_WIDTH:
			roofed += 1
	assert_true(roofed > 0, "the wheel turns under the wheel house's roof")
	# The axle housing crosses the strip to the wall, never onto the shop, the lease or the door's approach.
	var housing: MeshInstance3D = country_view.root.get_node(^"AxleHousing") as MeshInstance3D
	var points: PackedVector3Array = _points(housing.mesh, Transform3D.IDENTITY)
	assert_true(points.size() > 0, "the axle housing crosses the strip")
	var reach: float = INF
	for point: Vector3 in points:
		reach = minf(reach, absf(point.x - country_view.mill_wall))
		assert_true(point.x >= local.position.x - 0.001 and point.x <= country_view.mill_wall + 0.001,
			"the housing lies between the lot's edge and the wall (u %.2f)" % point.x)
		assert_true(absf(point.z - wheel.z) < NeighbourhoodCountry.CASING_HALF + 0.06, "and along the axle's line")
		assert_true(point.y < NeighbourhoodCountry.CASING_TOP + 0.2, "it stays low")
	assert_almost_eq(reach, 0.0, 0.001, "it meets the wall")
	var keep_off: Array[AABB] = [_cells_box(FIRST_LEASE)]
	keep_off.append_array(_approaches(dressing))
	assert_eq(_strays(housing.mesh, frame, keep_off, -1.0), 0, "the housing never stands on the shop or the door's approach")
	# The standing wheat sways on the street's display clock.
	var wheat: ShaderMaterial = (country_view.plot(&"north").node.get_node(^"Grown/Body") as MeshInstance3D).material_override as ShaderMaterial
	assert_not_null(wheat, "the standing wheat has its swaying material")
	dressing.set_review_time(21.5)
	assert_almost_eq(float(wheat.get_shader_parameter(&"sway_time")), 21.5, 0.001, "the wheat sways with the display clock")
	_free(dressing)
	NeighbourhoodDressing.clear_mesh_cache()
	# Built out to the lot's edge: the housing is gone and the wheel house meets the wall.
	var built_out: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(built_out)
	built_out.set_process(false)
	built_out.use_preset(load(COUNTRY) as StreetPreset)
	built_out.configure(_grid(), Rect2i(0, -2, 10, 9), [{"cells": _grid().entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])
	country_view = built_out.country()
	var edge: float = (built_out.local_frame().affine_inverse() * _reserve(built_out)).position.x
	assert_almost_eq(country_view.mill_wall, edge, 0.001, "the shop's wall stands on the lot's edge")
	assert_eq(_points((country_view.root.get_node(^"AxleHousing") as MeshInstance3D).mesh, Transform3D.IDENTITY).size(), 0,
		"no housing is left over the shop")
	var meets: int = 0
	for point: Vector3 in _points((country_view.root.get_node(^"Props") as MeshInstance3D).mesh, Transform3D.IDENTITY):
		assert_false(point.x > edge + 0.001 and point.x < edge + 1.0 and point.y > 0.02 and absf(point.z - country_view.wheel_at.z) < NeighbourhoodCountry.HOUSE_HALF + 0.2,
			"nothing of the wheel house stands inside the shop")
		if absf(point.x - edge) < 0.001 and absf(point.z - country_view.wheel_at.z) < NeighbourhoodCountry.CASING_HALF and point.y > 0.3:
			meets += 1
	assert_true(meets > 0, "the axle's casing meets the wall at the lot's edge")
	_free(built_out)


func test_plot_state_survives_a_rebuild() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing()
	assert_true(dressing.set_plot_state(&"east", NeighbourhoodCountry.PlotState.MOWN))
	assert_true(dressing.set_plot_state(&"north", NeighbourhoodCountry.PlotState.CLEARED))
	assert_false(dressing.set_plot_state(&"nowhere", NeighbourhoodCountry.PlotState.CLEARED), "an unknown plot is refused")
	var east: Node3D = dressing.country().plot(&"east").node
	assert_false((east.get_node(^"Grown") as Node3D).visible, "mown: the long grass is gone")
	assert_true((east.get_node(^"Mown") as Node3D).visible, "the hay shows")
	var generation: int = dressing.capture_state()["rebuild_generation"]
	# A fresh grid forces a real rebuild of the whole street.
	_configure(dressing, _grid())
	assert_true(int(dressing.capture_state()["rebuild_generation"]) > generation, "the lane was rebuilt")
	assert_eq(dressing.build_error, "")
	assert_eq(dressing.plot_state(&"east"), NeighbourhoodCountry.PlotState.MOWN)
	assert_eq(dressing.plot_state(&"north"), NeighbourhoodCountry.PlotState.CLEARED)
	east = dressing.country().plot(&"east").node
	var north: Node3D = dressing.country().plot(&"north").node
	assert_true((east.get_node(^"Mown") as Node3D).visible, "still mown after the rebuild")
	assert_false((east.get_node(^"Grown") as Node3D).visible)
	assert_true((north.get_node(^"Cleared") as Node3D).visible, "still cleared after the rebuild")
	assert_false((north.get_node(^"Grown") as Node3D).visible)
	assert_true(dressing.set_plot_state(&"east", NeighbourhoodCountry.PlotState.GROWN))
	assert_true((east.get_node(^"Grown") as Node3D).visible, "and can grow back for a review")
	_free(dressing)


func test_leased_land_is_mown_flat_and_never_grown() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _leased(FIRST_LEASE)
	for id: StringName in [&"east_land", &"west_land", &"north_land"]:
		assert_false(dressing.plot_leased(id), "%s is not leased yet" % id)
		assert_eq(dressing.plot_state(id), NeighbourhoodCountry.PlotState.GROWN, "%s grows its crop" % id)
	assert_eq(dressing.plot_crop(&"north_land"), &"corn", "corn behind")
	assert_eq(dressing.plot_crop(&"east_land"), &"meadow", "meadow beside")
	var generation: int = dressing.capture_state()["rebuild_generation"]
	dressing.set_lease(RESERVE, FIRST_LEASE)
	_configure(dressing, _grid())
	assert_true(int(dressing.capture_state()["rebuild_generation"]) > generation, "the lease change rebuilt the lane")
	var frame: Transform3D = dressing.country().root.global_transform
	for id: StringName in [&"east_land", &"west_land", &"north_land"]:
		assert_true(dressing.plot_leased(id), "%s is leased" % id)
		assert_eq(dressing.plot_state(id), NeighbourhoodCountry.PlotState.MOWN, "%s is mown" % id)
		var node: Node3D = dressing.country().plot(id).node
		assert_false((node.get_node(^"Grown") as Node3D).visible, "no standing crop on %s" % id)
		for look: String in ["Mown", "Cleared"]:
			var body: MeshInstance3D = node.get_node(NodePath(look + "/Body")) as MeshInstance3D
			assert_eq(_strays(body.mesh, frame, [_cells_box(RESERVE)] as Array[AABB], -0.002), 0,
				"%s's %s look lies flat, under the floor line" % [id, look])
		assert_false(dressing.set_plot_state(id, NeighbourhoodCountry.PlotState.GROWN), "crops never grow back on leased land")
		assert_true(dressing.set_plot_state(id, NeighbourhoodCountry.PlotState.CLEARED), "it can be cleared")
		assert_true((node.get_node(^"Cleared") as Node3D).visible)
	_free(dressing)


func test_the_country_is_the_same_every_build() -> void:
	await _host()
	var first: NeighbourhoodDressing = _dressing()
	var a: String = _digest(first)
	_free(first)
	NeighbourhoodDressing.clear_mesh_cache()
	var second: NeighbourhoodDressing = _dressing()
	assert_eq(_digest(second), a, "the country is laid out the same way every time (no randomness)")
	_free(second)


func test_old_mill_street_stands_on_the_lane() -> void:
	var lot: LotDef = load(OLD_MILL) as LotDef
	assert_eq(lot.id, &"town_fixer_upper", "the lot keeps its id")
	assert_eq(lot.display_name, "Old Mill Street")
	assert_eq(lot.street_preset, COUNTRY)
	assert_eq(String(StreetPreset.for_lot(lot).id), "country")
	assert_true(lot.blurb.contains("watermill"), "the blurb names the mill")
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var mill: WallStyleDef = content.wall_style(&"mill")
	assert_not_null(mill, "a stone-and-timber wall finish exists")
	assert_eq(int(mill.pattern), WallStyleDef.Pattern.MILL)
	assert_true(mill.price > 0, "a priced finish on other lots")
	assert_not_null(content.swatch(mill.default_swatch), "its stone is a palette colour")
	assert_not_null(content.swatch(mill.default_accent), "and so is its timber")


func test_the_other_streets_are_unchanged() -> void:
	await _host()
	for path: String in DIGESTS:
		var dressing: NeighbourhoodDressing = _dressing(load(path) as StreetPreset)
		assert_eq(dressing.build_error, "")
		assert_false(dressing.has_country(), "%s is no country lane" % path)
		assert_eq(dressing.plot_ids(), [] as Array[StringName], "%s has no plots" % path)
		assert_false(dressing.set_plot_state(&"east", NeighbourhoodCountry.PlotState.MOWN))
		assert_eq(_digest(dressing), DIGESTS[path], "%s builds exactly what it did before the country lane" % path)
		_free(dressing)
		NeighbourhoodDressing.clear_mesh_cache()

