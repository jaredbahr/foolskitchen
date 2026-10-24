extends TestCase
## Native camera/viewport projection; Web canvas behavior still needs a browser.

const RIG: PackedScene = preload("res://src/world/camera_rig.tscn")
const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var _viewports: Array[SubViewport] = []
var _viewport: SubViewport
var _rig: CameraRig
var _floor: MeshInstance3D


func after_each() -> void:
	for viewport: SubViewport in _viewports:
		viewport.free()
	_viewports.clear()


func test_real_floor_projects_near_center_at_each_requested_startup_size() -> void:
	for size: Vector2i in SIZES:
		await _mount(size)
		_assert_floor_centered()
		var before: Vector3 = _rig.position
		_rig._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
		_rig.step_view(1.0, _rig._edge_pan_input(Vector2.ZERO, _viewport.get_visible_rect()))
		assert_eq(_rig.position, before, "mouse entry without a real position never drifts the startup view")
		_assert_floor_centered()


func test_resize_recenters_before_pan_without_resetting_rotation_zoom_or_grid() -> void:
	await _mount(SIZES[0])
	_rig.rotate_quarter(1)
	_rig.zoom_steps(-1.0)
	_rig.toggle_grid()
	_rig.step_view(10.0, Vector2.ZERO)
	var yaw: float = _rig.rotation.y
	var camera: Camera3D = _rig.get_node("Camera3D") as Camera3D
	var zoom: float = camera.size
	assert_false(_rig._has_panned, "zoom/rotation are not a pan")
	for size: Vector2i in [SIZES[1], SIZES[2], SIZES[0]]:
		# Model a displaced startup focus without issuing a player pan.
		_rig.position += Vector3(1.0, 0.0, 1.0)
		await _resize(size)
		assert_eq(_rig.position, Vector3(_rig.initial_focus.x, 0.0, _rig.initial_focus.y))
		assert_almost_eq(_rig.rotation.y, yaw)
		assert_almost_eq(camera.size, zoom)
		assert_false(_rig.grid_visible)
		assert_eq(_rig.grid_material.get_shader_parameter("grid_visible"), false)
		_assert_floor_centered()


func test_keyboard_pan_request_keeps_player_focus_through_resize() -> void:
	await _mount(SIZES[0])
	# This is the same screen-relative input consumed by the WASD frame path.
	_rig.step_view(0.25, Vector2.RIGHT)
	assert_true(_rig._has_panned)
	var panned: Vector3 = _rig.position
	for size: Vector2i in [SIZES[1], SIZES[2], SIZES[0]]:
		await _resize(size)
		assert_eq(_rig.position, panned)
		var camera: Camera3D = _rig.get_node("Camera3D") as Camera3D
		assert_true(camera.is_position_in_frustum(_floor_center()))


func test_drag_needs_actual_translation_and_reset_rearms_resize_centering() -> void:
	await _mount(SIZES[1])
	_rig.pan_by_drag(Vector2.ZERO, 900.0)
	_rig.pan_by_drag(Vector2.ONE, 0.0)
	_rig.step_view(0.0, Vector2.RIGHT)
	assert_false(_rig._has_panned, "zero displacement or invalid time/height does not count as a pan")
	await _resize(SIZES[0])
	_assert_floor_centered()
	_rig.pan_by_drag(Vector2(40.0, 20.0), float(SIZES[0].y))
	assert_true(_rig._has_panned)
	var panned: Vector3 = _rig.position
	await _resize(SIZES[2])
	assert_eq(_rig.position, panned)
	_rig.reset_view()
	assert_false(_rig._has_panned)
	_rig.position += Vector3(1.0, 0.0, 0.0)
	await _resize(SIZES[1])
	_assert_floor_centered()


func test_edge_pan_requires_fresh_motion_and_stale_positions_are_disarmed() -> void:
	await _mount(SIZES[0])
	var corner: Vector2 = Vector2(1.0, 1.0)
	_rig._notification(Node.NOTIFICATION_WM_MOUSE_ENTER)
	_motion(corner, Vector2.ZERO)
	assert_eq(_rig._edge_pan_input(corner, _viewport.get_visible_rect()), Vector2.ZERO)
	_motion(corner, Vector2.ONE)
	var edge: Vector2 = _rig._edge_pan_input(corner, _viewport.get_visible_rect())
	assert_true(edge.length() > 0.0, "a real edge movement still enables ordinary edge pan")
	_rig.step_view(0.25, edge)
	assert_true(_rig._has_panned)
	var panned: Vector3 = _rig.position
	await _resize(SIZES[1])
	assert_eq(_rig.position, panned)
	assert_eq(_rig._edge_pan_input(corner, _viewport.get_visible_rect()), Vector2.ZERO, "resize invalidates old pointer coordinates")
	_motion(corner, Vector2.ONE)
	assert_true(_rig._edge_pan_input(corner, _viewport.get_visible_rect()).length() > 0.0)
	_rig._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_eq(_rig._edge_pan_input(corner, _viewport.get_visible_rect()), Vector2.ZERO)
	_motion(corner, Vector2.ONE)
	_rig._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	assert_eq(_rig._edge_pan_input(corner, _viewport.get_visible_rect()), Vector2.ZERO)


func test_viewport_reparent_and_free_release_only_their_resize_binding() -> void:
	await _mount(SIZES[0])
	var first: SubViewport = _viewport
	var callback: Callable = _rig._on_viewport_resized
	assert_true(first.size_changed.is_connected(callback))
	var second: SubViewport = _new_viewport(SIZES[1])
	first.remove_child(_rig)
	assert_false(first.size_changed.is_connected(callback))
	second.add_child(_rig)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(second.size_changed.is_connected(callback))
	_rig.free()
	_rig = null
	assert_false(second.size_changed.is_connected(callback))
	# An already-removed rig cannot receive either viewport's later resize.
	first.size = SIZES[2]
	second.size = SIZES[0]


func _mount(size: Vector2i) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = _new_viewport(size)
	var content: ContentDB = ContentDB.new()
	assert_true(content.load_all().is_empty())
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(LAYOUT, content, errors)
	assert_true(errors.is_empty())
	var view: ShopView = VIEW.instantiate() as ShopView
	view.set_process(false)
	view.show_world(world)
	_viewport.add_child(view)
	_floor = view.floor_mesh
	_rig = RIG.instantiate() as CameraRig
	_rig.set_process(false)  # Host mouse/keyboard state must not affect fixtures.
	_rig.grid_floor = _floor
	# Match Main's existing room-focus contract without starting a game/session.
	var half: Vector2 = Vector2(world.grid.size) * GridMath.CELL_SIZE * 0.5
	_rig.initial_focus = half
	_rig.pan_center = half
	_rig.pan_limits = half + Vector2(2.0, 2.0)
	_rig.initial_zoom = 12.0
	_viewport.add_child(_rig)
	await tree.process_frame
	await tree.process_frame
	assert_true(_rig.is_node_ready())
	assert_eq((_rig.get_node("Camera3D") as Camera3D).get_viewport(), _viewport)


func _new_viewport(size: Vector2i) -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	(Engine.get_main_loop() as SceneTree).root.add_child(viewport)
	_viewports.append(viewport)
	return viewport


func _resize(size: Vector2i) -> void:
	_viewport.size = size
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(_viewport.size, size)


func _floor_center() -> Vector3:
	return _floor.to_global(_floor.get_aabb().get_center())


func _assert_floor_centered() -> void:
	var camera: Camera3D = _rig.get_node("Camera3D") as Camera3D
	var rect: Rect2 = _viewport.get_visible_rect()
	var point: Vector3 = _floor_center()
	assert_true(rect.has_area())
	assert_false(camera.is_position_behind(point))
	var projected: Vector2 = camera.unproject_position(point)
	var error: Vector2 = (projected - rect.get_center()).abs() / rect.size
	assert_true(error.x <= 0.1 and error.y <= 0.1, "real floor projection must be within 10%% of viewport center: %s" % error)


func _motion(position: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	_rig._unhandled_input(event)
