extends TestCase
## FK-103: kit mirror, approved made hand dryer and thin edge panel.


func test_mirror_uses_shared_kit_scale_and_sits_in_front_of_its_wall() -> void:
	var scene: PackedScene = load("res://assets/props/restroom_mirror.tscn") as PackedScene
	var mirror: PropView = scene.instantiate() as PropView
	var box: AABB = mirror.get_combined_aabb()
	var art: Node3D = mirror.get_node("WallMount/Art") as Node3D
	assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
	assert_true(box.size.x <= GridMath.CELL_SIZE)
	assert_almost_eq(box.end.z, GridMath.CELL_SIZE * 0.5 - 0.005, 0.0001)
	assert_true(box.position.y > 0.5 and box.end.y < ArtScale.WALL_HEIGHT)
	mirror.free()


func test_partition_and_thumbnail_have_matching_thin_laminate_geometry() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["....", "....", "...."]))
	var edge: Vector3i = Vector3i(2, 1, SimGrid.EDGE_WEST)
	assert_true(grid.set_segment(edge, SimGrid.Segment.STALL_PARTITION))
	var view: WallSegmentView = WallSegmentView.new()
	view.set_materials(StandardMaterial3D.new(), StandardMaterial3D.new())
	view.rebuild(grid, false, [])
	var panel: MeshInstance3D = view.get_node("Segment_2_1_0/StallPanel") as MeshInstance3D
	assert_eq((panel.mesh as BoxMesh).size, Vector3(GridMath.CELL_SIZE,
		ArtScale.STALL_PARTITION_HEIGHT, ArtScale.STALL_PARTITION_THICKNESS))
	assert_almost_eq(panel.position.y, ArtScale.STALL_PARTITION_HEIGHT * 0.5, 0.0001)
	assert_eq((panel.material_override as StandardMaterial3D).albedo_color, StallPartitionView.SWATCH.color)
	var thumbnail: PropView = (load("res://assets/props/stall_partition.tscn") as PackedScene).instantiate() as PropView
	assert_eq(thumbnail.get_combined_aabb().size, (panel.mesh as BoxMesh).size)
	view.rebuild(grid, true, [])
	panel = view.get_node("Segment_2_1_0/StallPanel") as MeshInstance3D
	assert_almost_eq((panel.mesh as BoxMesh).size.y, ShopView.LOWERED_HEIGHT, 0.0001)
	assert_eq(grid.segment(edge), SimGrid.Segment.STALL_PARTITION, "lowering changes only presentation")
	thumbnail.free()
	view.free()


func test_hand_dryer_keeps_its_size_and_aligns_its_bottom_with_the_mirror() -> void:
	var scene: PackedScene = load("res://assets/props/wall_hand_dryer.tscn") as PackedScene
	var dryer: PropView = scene.instantiate() as PropView
	var mirror: PropView = (load("res://assets/props/restroom_mirror.tscn") as PackedScene).instantiate() as PropView
	var box: AABB = dryer.get_combined_aabb()
	var art: Node3D = dryer.get_node("WallMount/Art") as Node3D
	assert_eq(art.scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
	assert_almost_eq(box.size.x, 0.30 * ArtScale.FURNITURE_SCALE, 0.001)
	assert_almost_eq(box.size.y, 0.25 * ArtScale.FURNITURE_SCALE, 0.001)
	assert_true(box.size.z < 0.18)
	assert_almost_eq(box.position.y, mirror.get_combined_aabb().position.y, 0.001,
		"both fittings share a bottom edge at the game's person scale")
	assert_true(box.end.y < ArtScale.WALL_HEIGHT)
	assert_true(box.end.z < GridMath.CELL_SIZE * 0.5)
	assert_not_null(art.find_child("DownwardNozzle", true, false))
	assert_not_null(art.find_child("FrontSensor", true, false))
	mirror.free()
	dryer.free()
