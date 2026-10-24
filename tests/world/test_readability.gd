extends TestCase
## Presentation regressions. Pixel brightness and legibility need rendered shots.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const RIG: PackedScene = preload("res://src/world/camera_rig.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
## Exact Tier 1 sets, enumerated from the ASCII layout's two-cell diagonal rays.
const LOWERED: Array[String] = [
	"13,2;13,3;2,4;3,4;4,4;8,4;9,4;10,4;11,4;12,4;13,4;13,5;13,6;13,7;13,8;13,9;2,10;3,10;4,10;5,10;8,10;9,10;10,10;11,10;12,10;13,10",
	"2,0;3,0;4,0;5,0;6,0;7,0;8,0;9,0;10,0;11,0;12,0;13,0;13,1;13,2;13,3;2,4;3,4;4,4;8,4;9,4;10,4;11,4;12,4;13,4;13,5;13,6;13,7;13,8;8,10",
	"0,0;1,0;2,0;3,0;4,0;5,0;6,0;7,0;8,0;9,0;10,0;11,0;0,1;0,2;0,3;0,4;1,4;2,4;3,4;4,4;8,4;9,4;10,4;11,4;0,5;0,6;0,7;0,8;5,10",
	"0,2;0,3;0,4;1,4;2,4;3,4;4,4;8,4;9,4;10,4;11,4;0,5;0,6;0,7;0,8;0,9;0,10;1,10;2,10;3,10;4,10;5,10;8,10;9,10;10,10;11,10",
]

var _view: ShopView
var _rig: CameraRig
var _quarters: Array[int] = []


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()
	if is_instance_valid(_rig):
		_rig.free()


func test_tier_one_exact_cutaway_sets_at_every_camera_quarter() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all().size(), 0)
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(LAYOUT, content, errors)
	assert_eq(errors.size(), 0)
	_view = VIEW.instantiate() as ShopView
	_view.show_world(world)
	assert_eq(_view.wall_mode, ShopView.WallMode.CUTAWAY)
	for quarter: int in range(4):
		_view.set_camera_quarter(quarter)
		var expected: Array[Vector2i] = _cells(LOWERED[quarter])
		assert_eq(_view.lowered_wall_cells(), expected, "quarter %d" % quarter)
		for node: Node in _view.get_node("Walls").get_children():
			var wall: MeshInstance3D = node as MeshInstance3D
			var cell: Vector2i = wall.get_meta("wall_cell")
			var height: float = 0.35 if expected.has(cell) else 2.4
			assert_almost_eq((wall.mesh as BoxMesh).size.y, height)
			assert_almost_eq(wall.position.y, height * 0.5)
		assert_true(expected.has(Vector2i(3, 4)), "kitchen divider lowers in front of kitchen")
	assert_false(_cells(LOWERED[0]).has(Vector2i(3, 0)), "north back wall stays up at default quarter")
	assert_false(_cells(LOWERED[2]).has(Vector2i(3, 10)), "south back wall stays up from opposite quarter")
	assert_eq(world.now, 0, "presentation never advances the simulation")


func test_cutaway_two_cell_limit_and_terrain_rebuild() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([".  #", " . #", "  ##", "####"]))
	_view = VIEW.instantiate() as ShopView
	_view.show_world(SimWorld.new(grid))
	assert_true(_view.lowered_wall_cells().has(Vector2i(3, 3)), "floor two diagonal cells away")
	grid.set_terrain(Vector2i(1, 1), SimGrid.Terrain.OUTSIDE)
	assert_false(_view.lowered_wall_cells().has(Vector2i(3, 3)), "floor three cells away does not qualify")


func test_c_key_cycles_up_cutaway_down_up_and_ignores_echo_release() -> void:
	_view = VIEW.instantiate() as ShopView
	_view.show_world(SimWorld.new(SimGrid.from_ascii(PackedStringArray(["###", "#.#", "###"]))))
	_view.set_wall_mode(ShopView.WallMode.UP)
	assert_eq(_view.lowered_wall_cells().size(), 0)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	_view._unhandled_input(key)
	assert_eq(_view.wall_mode, ShopView.WallMode.CUTAWAY)
	key.echo = true
	_view._unhandled_input(key)
	assert_eq(_view.wall_mode, ShopView.WallMode.CUTAWAY)
	key.echo = false
	_view._unhandled_input(key)
	assert_eq(_view.wall_mode, ShopView.WallMode.DOWN)
	assert_eq(_view.lowered_wall_cells().size(), 8)
	_view._unhandled_input(key)
	assert_eq(_view.wall_mode, ShopView.WallMode.UP)
	key.pressed = false
	_view._unhandled_input(key)
	assert_eq(_view.wall_mode, ShopView.WallMode.UP)


func test_yaw_signal_is_once_per_target_change_not_per_smoothed_frame() -> void:
	_rig = RIG.instantiate() as CameraRig
	_rig.reset_view()
	_rig.yaw_snapped.connect(_record_quarter)
	_rig.rotate_quarter(1)
	_rig.rotate_quarter(0)
	_rig.step_view(0.1, Vector2.ZERO)
	_rig.step_view(0.1, Vector2.ZERO)
	_rig.rotate_quarter(2)
	_rig.rotate_quarter(1)
	assert_eq(_quarters, [1, 3, 0] as Array[int])
	assert_eq(_rig.camera_quarter(), 0)
	_rig.reset_view()
	_rig.reset_view()
	assert_eq(_quarters, [1, 3, 0, 0] as Array[int], "one reset changes the unwrapped target; repeated reset does not")


func test_wall_tops_and_agent_noses_are_darker_without_sim_changes() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["#.", ".."])))
	var agent: StaffAgent = StaffAgent.new(&"server")
	agent.cell = Vector2i(1, 1)
	world.add_agent(agent)
	_view = VIEW.instantiate() as ShopView
	_view.show_world(world)
	var wall: MeshInstance3D = _view.get_node("Walls").get_child(0) as MeshInstance3D
	var wall_material: StandardMaterial3D = wall.material_override as StandardMaterial3D
	var top_material: StandardMaterial3D = (wall.get_node("Top") as MeshInstance3D).material_override as StandardMaterial3D
	assert_true(top_material.albedo_color.get_luminance() < wall_material.albedo_color.get_luminance())
	var body: MeshInstance3D = _view.agent_nodes[agent.id]
	var nose: MeshInstance3D = body.get_node("FacingMarker") as MeshInstance3D
	assert_true(nose.position.z < 0.0, "nose points along local forward -Z")
	assert_true(nose.position.y > 0.5, "nose sits at head height")
	assert_true((nose.material_override as StandardMaterial3D).albedo_color.get_luminance() < (body.material_override as StandardMaterial3D).albedo_color.get_luminance())
	assert_eq(world.now, 0)


func _cells(encoded: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for pair: String in encoded.split(";"):
		var coordinates: PackedStringArray = pair.split(",")
		cells.append(Vector2i(int(coordinates[0]), int(coordinates[1])))
	return cells


func _record_quarter(quarter: int) -> void:
	_quarters.append(quarter)
