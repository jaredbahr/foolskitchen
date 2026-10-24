extends TestCase
## Camera behavior checks; visual feel still requires a playtest.

const RigScene: PackedScene = preload("res://src/world/camera_rig.tscn")
const MainScene: PackedScene = preload("res://src/world/main.tscn")

var _nodes: Array[Node] = []


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_both_projection_modes_keep_narrow_perspective_fov() -> void:
	var rig: CameraRig = _make_rig()
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	rig.use_orthographic = false
	rig.step_view(0.1, Vector2.ZERO)
	assert_eq(camera.projection, Camera3D.PROJECTION_PERSPECTIVE)
	assert_almost_eq(camera.fov, 30.0)
	assert_true(camera.position.y > 0.0)
	assert_true(camera.position.z > 0.0)


func test_pan_distance_matches_at_30_and_144_fps() -> void:
	var low: CameraRig = _make_rig()
	var high: CameraRig = _make_rig()
	low.pan_limits = Vector2(100.0, 100.0)
	high.pan_limits = low.pan_limits
	for frame: int in range(30):
		low.step_view(1.0 / 30.0, Vector2.RIGHT)
	for frame: int in range(144):
		high.step_view(1.0 / 144.0, Vector2.RIGHT)
	assert_almost_eq(low.position.distance_to(high.position), 0.0, 0.0001)
	assert_almost_eq(low.position.length(), low.pan_speed, 0.0001)


func test_diagonal_pan_is_not_faster_and_focus_is_clamped() -> void:
	var rig: CameraRig = _make_rig()
	rig.initial_yaw_degrees = 0.0
	rig.pan_limits = Vector2(100.0, 100.0)
	rig.reset_view()
	rig.step_view(1.0, Vector2.ONE)
	assert_almost_eq(rig.position.length(), rig.pan_speed, 0.0001)
	rig.pan_limits = Vector2(1.0, 2.0)
	rig.step_view(10.0, Vector2.ONE)
	assert_almost_eq(rig.position.x, 1.0)
	assert_almost_eq(rig.position.z, 2.0)
	assert_almost_eq(rig.position.y, 0.0)


func test_zoom_targets_are_clamped_at_both_limits() -> void:
	var rig: CameraRig = _make_rig()
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	rig.zoom_steps(100.0)
	rig.step_view(10.0, Vector2.ZERO)
	assert_almost_eq(camera.size, rig.maximum_zoom)
	rig.zoom_steps(-100.0)
	rig.step_view(10.0, Vector2.ZERO)
	assert_almost_eq(camera.size, rig.minimum_zoom)


func test_rotation_and_zoom_damping_match_across_frame_rates() -> void:
	var low: CameraRig = _make_rig()
	var high: CameraRig = _make_rig()
	low.rotate_quarter(1)
	high.rotate_quarter(1)
	low.zoom_steps(-3.0)
	high.zoom_steps(-3.0)
	for frame: int in range(30):
		low.step_view(1.0 / 30.0, Vector2.ZERO)
	for frame: int in range(144):
		high.step_view(1.0 / 144.0, Vector2.ZERO)
	assert_almost_eq(low.rotation.y, high.rotation.y, 0.0001)
	var low_camera: Camera3D = low.get_node("Camera3D") as Camera3D
	var high_camera: Camera3D = high.get_node("Camera3D") as Camera3D
	assert_almost_eq(low_camera.size, high_camera.size, 0.0001)
	assert_almost_eq(low.rotation.y, deg_to_rad(135.0), 0.001)


func test_edge_pan_ignores_center_outside_and_disabled_input() -> void:
	var rig: CameraRig = _make_rig()
	rig.edge_margin_pixels = 10.0
	var rect: Rect2 = Rect2(0.0, 0.0, 120.0, 100.0)
	assert_eq(rig.edge_pan_direction(Vector2(60.0, 50.0), rect), Vector2.ZERO)
	assert_eq(rig.edge_pan_direction(Vector2(-1.0, 50.0), rect), Vector2.ZERO)
	assert_eq(rig.edge_pan_direction(Vector2(120.0, 50.0), rect), Vector2.ZERO)
	assert_eq(rig.edge_pan_direction(Vector2(119.0, 50.0), rect), Vector2.RIGHT)
	assert_almost_eq(rig.edge_pan_direction(Vector2(1.0, 1.0), rect).length(), 1.0)
	rig.edge_pan_enabled = false
	assert_eq(rig.edge_pan_direction(Vector2(119.0, 50.0), rect), Vector2.ZERO)


func test_drag_uses_pixel_displacement_without_frame_time() -> void:
	var rig: CameraRig = _make_rig()
	rig.initial_yaw_degrees = 0.0
	rig.reset_view()
	rig.pan_by_drag(Vector2(100.0, 0.0), 1000.0)
	assert_almost_eq(rig.position.x, -2.6, 0.0001)
	assert_almost_eq(rig.position.z, 0.0)
	var before: Vector3 = rig.position
	rig.pan_by_drag(Vector2.ONE, 0.0)
	assert_eq(rig.position, before)


func test_key_press_rotates_once_and_g_toggles_shared_grid_material() -> void:
	var main: Node3D = MainScene.instantiate() as Node3D
	_nodes.append(main)
	main.call("initialize")
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	rig.reset_view()
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	rig._unhandled_input(key)
	key.echo = true
	rig._unhandled_input(key)
	rig.step_view(10.0, Vector2.ZERO)
	assert_almost_eq(rig.rotation.y, deg_to_rad(135.0), 0.0001)
	key.physical_keycode = KEY_G
	key.echo = false
	rig._unhandled_input(key)
	assert_false(rig.grid_visible)
	assert_eq(rig.grid_material.get_shader_parameter("grid_visible"), false)
	var floor: MeshInstance3D = main.get_node("ShopView/Floor") as MeshInstance3D
	assert_true(rig.grid_floor == floor, "the exported node binds to the containing scene's floor")
	assert_true(floor.material_override == rig.grid_material)
	var material: ShaderMaterial = floor.material_override as ShaderMaterial
	assert_eq(material.get_shader_parameter("grid_visible"), false, "G changes the material actually rendered by the floor")


func test_grid_material_is_shared_within_each_main_and_isolated_between_mains() -> void:
	var first: Node3D = MainScene.instantiate() as Node3D
	var second: Node3D = MainScene.instantiate() as Node3D
	_nodes.append(first)
	_nodes.append(second)
	first.call("initialize")
	second.call("initialize")
	var first_rig: CameraRig = first.get_node("CameraRig") as CameraRig
	var second_rig: CameraRig = second.get_node("CameraRig") as CameraRig
	var first_floor: MeshInstance3D = first.get_node("ShopView/Floor") as MeshInstance3D
	var second_floor: MeshInstance3D = second.get_node("ShopView/Floor") as MeshInstance3D
	first_rig.reset_view()
	second_rig.reset_view()
	assert_true(first_rig.grid_floor == first_floor)
	assert_true(second_rig.grid_floor == second_floor)
	assert_true(first_rig.grid_material == first_floor.material_override)
	assert_true(second_rig.grid_material == second_floor.material_override)
	assert_true(first_floor.material_override != second_floor.material_override,
		"each main instance retains its own scene-local material")
	first_rig.toggle_grid()
	var first_material: ShaderMaterial = first_floor.material_override as ShaderMaterial
	var second_material: ShaderMaterial = second_floor.material_override as ShaderMaterial
	assert_eq(first_material.get_shader_parameter("grid_visible"), false)
	assert_eq(second_material.get_shader_parameter("grid_visible"), true,
		"toggling one scene cannot change another scene's grid")
	assert_true(second_rig.grid_visible)


func test_default_scene_has_shop_floor_and_fixed_mini_character_staff() -> void:
	var main: Node3D = MainScene.instantiate() as Node3D
	_nodes.append(main)
	main.call("initialize")
	var view: ShopView = main.get_node("ShopView") as ShopView
	assert_not_null(view.floor_mesh.mesh)
	assert_eq(view.agent_nodes.size(), 3)
	var world: SimWorld = main.get("world")
	var roles: Dictionary[StringName, int] = {&"cook": 0, &"server": 0, &"owner": 0}
	for agent: SimAgent in world.agents:
		assert_true(agent is StaffAgent)
		assert_true(roles.has(agent.role))
		if not roles.has(agent.role):
			continue
		roles[agent.role] += 1
		assert_true(view.agent_nodes.has(agent.id))
		if not view.agent_nodes.has(agent.id):
			continue
		var body: PersonView = view.agent_nodes[agent.id] as PersonView
		assert_not_null(body)
		if body == null:
			continue
		assert_eq(body.get_meta("agent_id"), agent.id)
		assert_eq(body.role, agent.role)
		assert_eq(body.position.y, 0.0)
	assert_eq(roles, {&"cook": 1, &"server": 1, &"owner": 1})


func _make_rig() -> CameraRig:
	var rig: CameraRig = RigScene.instantiate() as CameraRig
	_nodes.append(rig)
	rig.reset_view()
	return rig


func test_focus_clamps_around_pan_center() -> void:
	var rig: CameraRig = _make_rig()
	rig.initial_yaw_degrees = 0.0
	rig.pan_center = Vector2(3.5, 3.0)
	rig.pan_limits = Vector2(5.5, 5.0)
	rig.initial_focus = Vector2(3.5, 3.0)
	rig.reset_view()
	rig.step_view(100.0, Vector2(-1.0, -1.0))
	assert_almost_eq(rig.position.x, -2.0, 0.0001, "left edge = centre - limit")
	assert_almost_eq(rig.position.z, -2.0, 0.0001, "far edge = centre - limit")
	rig.step_view(100.0, Vector2(1.0, 1.0))
	assert_almost_eq(rig.position.x, 9.0, 0.0001, "right edge = centre + limit")
	assert_almost_eq(rig.position.z, 8.0, 0.0001, "near edge = centre + limit")
