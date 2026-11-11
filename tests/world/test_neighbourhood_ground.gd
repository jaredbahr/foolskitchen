extends TestCase
## The ground under the neighbourhood and the deliberate world edge (#421, #424).

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const RigScene: PackedScene = preload("res://src/world/camera_rig.tscn")

var _main: Node3D
var _viewport: SubViewport
var _old_providers: Dictionary
var _rigs: Array[Node] = []


func before_each() -> void:
	_old_providers = SaveSystem._providers.duplicate(true)
	Clock.set_speed(0)


func after_each() -> void:
	for rig: Node in _rigs:
		rig.free()
	_rigs.clear()
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	SaveSystem._providers = _old_providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("owner_creation_requested", false)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set_process(false)
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	rig.edge_pan_enabled = false
	for index: int in 4:
		await tree.process_frame


func _ground_box(dressing: NeighbourhoodDressing) -> Rect2:
	var meadow: MeshInstance3D = dressing.ground_root.get_node("Meadow") as MeshInstance3D
	var box: AABB = dressing.ground_root.global_transform * meadow.get_aabb()
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


## The ground a viewport corner shows, found by casting the real camera's rays.
func _visible_ground(rig: CameraRig, camera: Camera3D) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		var origin: Vector3 = camera.project_ray_origin(corner)
		var direction: Vector3 = camera.project_ray_normal(corner)
		var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
		if hit is Vector3:
			points.append(Vector2((hit as Vector3).x, (hit as Vector3).z))
	return points


func test_ground_covers_every_view_the_camera_clamp_allows_at_every_rotation_and_max_zoom() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var dressing: NeighbourhoodDressing = view.neighbourhood_dressing
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	assert_not_null(dressing)
	if dressing == null:
		return
	assert_true(dressing.ground_root.visible)
	var ground: Rect2 = _ground_box(dressing)
	assert_true(ground.encloses(dressing.world_rect()), "the meadow reaches the world edge the camera is held to")
	var bounds: Rect2 = rig.call("_focus_bounds")
	var corners: Array[Vector2] = [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end,
		Vector2(bounds.position.x, bounds.end.y), bounds.get_center()]
	var world: Rect2 = dressing.world_rect()
	for quarter: int in 4:
		for corner: Vector2 in corners:
			rig.zoom_steps(1000.0)
			rig.position = Vector3(corner.x, 0.0, corner.y)
			rig.step_view(10.0, Vector2.ZERO)
			assert_almost_eq(camera.size, rig.world_zoom_limit(), 0.01, "max zoom-out is the world's limit")
			for point: Vector2 in _visible_ground(rig, camera):
				assert_true(world.grow(0.01).has_point(point),
					"quarter %d corner %s shows nothing past the world edge: %s" % [quarter, corner, point])
				assert_true(ground.has_point(point), "ground under every visible point")
		rig.rotate_quarter(1)
		rig.step_view(10.0, Vector2.ZERO)


func test_max_zoom_out_still_shows_the_tree_line_and_is_never_a_cut_off() -> void:
	await _start()
	var dressing: NeighbourhoodDressing = (_main.get_node("ShopView") as ShopView).neighbourhood_dressing
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	assert_not_null(dressing)
	if dressing == null:
		return
	# The limit is tight: from the clamp's far corner the view just meets the world edge.
	var margin_rect: Rect2 = rig.call("_focus_bounds")
	var world: Rect2 = dressing.world_rect()
	var reach: float = rig.view_reach(rig.world_zoom_limit())
	var nearest: float = minf(minf(margin_rect.position.x - world.position.x, world.end.x - margin_rect.end.x),
		minf(margin_rect.position.y - world.position.y, world.end.y - margin_rect.end.y))
	assert_almost_eq(reach, nearest, 0.05)
	assert_true(rig.world_zoom_limit() > rig.initial_zoom * 1.5, "there is still real room to zoom out")
	var forest: MeshInstance3D = dressing.ground_root.get_node("Planting") as MeshInstance3D
	assert_not_null(forest.mesh)
	var planted: AABB = dressing.ground_root.global_transform * forest.mesh.get_aabb()
	assert_true(planted.size.y > 1.0, "trees, not just paint")
	assert_true(Rect2(planted.position.x, planted.position.z, planted.size.x, planted.size.z).size.x > world.size.x * 0.8,
		"the tree line runs the whole way round the clearing")


func test_ground_is_view_only_cheap_and_rebuilds_identically() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var dressing: NeighbourhoodDressing = view.neighbourhood_dressing
	assert_not_null(dressing)
	if dressing == null:
		return
	var triangles: int = 0
	var surfaces: int = 0
	for node: Node in dressing.ground_root.get_children():
		var mesh: MeshInstance3D = node as MeshInstance3D
		assert_not_null(mesh)
		assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_eq(mesh.find_children("*", "CollisionObject3D", true, false).size(), 0)
		if mesh.mesh != null:
			surfaces += mesh.mesh.get_surface_count()
			triangles += (mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	assert_true(surfaces <= 3, "the whole ground is at most three draw calls")
	assert_true(triangles > 2000 and triangles < 90000, "a sensible triangle count: %d" % triangles)
	var before: PackedVector3Array = (dressing.ground_root.get_node("Planting") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var builder: NeighbourhoodGround = NeighbourhoodGround.new()
	builder.local_reserve = AABB(Vector3(-1.0, 0.0, -9.0), Vector3(12.0, 1.4, 9.0))
	builder.shift = 0.0
	var first: Array[MeshInstance3D] = builder.build()
	var second: Array[MeshInstance3D] = builder.build()
	for index: int in first.size():
		if first[index].mesh != null:
			assert_eq(first[index].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], second[index].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],
				"the same inputs always plant the same world")
	for node: MeshInstance3D in first + second:
		node.free()
	assert_true(before.size() > 0)
	# Rebuilding the street (a patio purchase, a lot change) keeps the same ground nodes.
	var node_before: Node = dressing.ground_root.get_node("Meadow")
	dressing.rebuild()
	assert_true(dressing.ground_root.get_node("Meadow") == node_before, "unchanged street keeps its ground")


func test_the_camera_rig_caps_zoom_so_the_view_stays_inside_any_world() -> void:
	var rig: CameraRig = RigScene.instantiate() as CameraRig
	_rigs.append(rig)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	rig.pan_center = Vector2.ZERO
	rig.pan_limits = Vector2(6.0, 4.0)
	rig.reset_view()
	rig.zoom_steps(1000.0)
	rig.step_view(10.0, Vector2.ZERO)
	assert_almost_eq(camera.size, rig.maximum_zoom, 0.001)
	assert_almost_eq(rig.world_zoom_limit(), rig.maximum_zoom)
	rig.set_world_bounds(Rect2(-30.0, -30.0, 60.0, 60.0))
	rig.step_view(10.0, Vector2.ZERO)
	var limit: float = rig.world_zoom_limit()
	assert_true(limit < rig.maximum_zoom)
	assert_almost_eq(camera.size, limit, 0.01)
	# From the farthest allowed focus the rotated view's far corner meets the edge, never passes it.
	assert_almost_eq(rig.view_reach(limit), 30.0 - 6.0, 0.01)
	rig.set_world_bounds(Rect2())
	rig.zoom_steps(1000.0)
	rig.step_view(10.0, Vector2.ZERO)
	assert_almost_eq(camera.size, rig.maximum_zoom, 0.001)
	# A world too small to hold even the minimum view still never zooms in past it.
	rig.set_world_bounds(Rect2(-5.0, -5.0, 10.0, 10.0))
	rig.step_view(10.0, Vector2.ZERO)
	assert_almost_eq(camera.size, rig.minimum_zoom, 0.01)


func test_a_street_can_be_reskinned_without_touching_the_geometry() -> void:
	var plain: NeighbourhoodGround = NeighbourhoodGround.new()
	plain.local_reserve = AABB(Vector3(-1.0, 0.0, -9.0), Vector3(12.0, 1.4, 9.0))
	var autumn: NeighbourhoodGround = NeighbourhoodGround.new()
	autumn.local_reserve = plain.local_reserve
	autumn.skin = GroundSkin.standard()
	autumn.skin.grass = Color(0.8, 0.5, 0.2)
	autumn.skin.tree_density = 0.0
	var first: Array[MeshInstance3D] = plain.build()
	var second: Array[MeshInstance3D] = autumn.build()
	var a: PackedColorArray = first[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var b: PackedColorArray = second[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_ne(a[6], b[6], "the skin colours the meadow")
	assert_eq(first[0].mesh.get_aabb(), second[0].mesh.get_aabb(), "the world edge is the same for every skin")
	for node: MeshInstance3D in first + second:
		node.free()
