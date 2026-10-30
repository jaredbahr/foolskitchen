extends TestCase
## FK-070 wall segment presentation: geometry follows the sim, never the reverse.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")

var _view: ShopView
var _world: SimWorld


func before_each() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	# Isolate synthetic wall/window/doorway geometry from authored segments.
	# The shipped thin divider has dedicated migration and session coverage.
	var layout: ShopLayout = LegacyTier1Layout.make()
	_world = ShopBuilder.build(layout, content, errors)
	assert_eq(errors, [] as Array[String])
	_view = VIEW.instantiate() as ShopView
	(Engine.get_main_loop() as SceneTree).root.add_child(_view)
	_view.show_world(_world)
	_view.set_wall_mode(ShopView.WallMode.UP)


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()
	_world = null


func test_each_interior_segment_gets_its_own_geometry() -> void:
	var grid: SimGrid = _world.grid
	assert_eq(_view.segment_view.get_child_count(), 0)
	grid.set_segment(Vector3i(9, 5, 0), SimGrid.Segment.WALL)
	grid.set_segment(Vector3i(9, 6, 0), SimGrid.Segment.WINDOW)
	grid.set_segment(Vector3i(9, 7, 0), SimGrid.Segment.DOORWAY)
	assert_eq(_view.segment_view.get_child_count(), 3, "cells_changed rebuilds the segments")
	var wall: Node3D = _view.segment_view.get_node("Segment_9_5_0") as Node3D
	var bounds: AABB = _bounds(wall)
	assert_almost_eq(bounds.size.y, ArtScale.WALL_HEIGHT + WallSegmentView.CAP_HEIGHT - 0.005, 0.001)
	assert_almost_eq(bounds.size.x, WallSegmentView.THICKNESS, 0.001)
	assert_almost_eq(bounds.size.z, GridMath.CELL_SIZE, 0.001, "a straight run butts end to end")
	assert_almost_eq(bounds.position.x, 9 * GridMath.CELL_SIZE - WallSegmentView.THICKNESS * 0.5, 0.001)
	assert_eq(_view.segment_view.pane_nodes().size(), 1, "the window holds one Kenney pane")
	var doorway: Node3D = _view.segment_view.get_node("Segment_9_7_0") as Node3D
	var opening: AABB = _bounds(doorway)
	assert_true(opening.position.y >= WallSegmentView.DOOR_HEIGHT - 0.001, "nothing below the doorway head")
	assert_true(WallSegmentView.DOOR_HEIGHT >= 1.1, "ART_STYLE door height")
	grid.set_segment(Vector3i(9, 6, 0), SimGrid.Segment.NONE)
	assert_eq(_view.segment_view.get_child_count(), 2)


func test_corners_close_and_cutaway_lowers_interior_walls() -> void:
	var grid: SimGrid = _world.grid
	grid.set_segment(Vector3i(9, 6, 0), SimGrid.Segment.WALL)
	grid.set_segment(Vector3i(9, 6, 1), SimGrid.Segment.WALL)
	var vertical: AABB = _bounds(_view.segment_view.get_node("Segment_9_6_0") as Node3D)
	assert_almost_eq(vertical.size.z, GridMath.CELL_SIZE + WallSegmentView.THICKNESS * 0.5, 0.001,
		"an L corner reaches half a thickness past the shared vertex")
	_view.set_wall_mode(ShopView.WallMode.CUTAWAY)
	vertical = _bounds(_view.segment_view.get_node("Segment_9_6_0") as Node3D)
	assert_true(vertical.end.y < ShopView.LOWERED_HEIGHT + 0.05)
	_view.set_wall_mode(ShopView.WallMode.UP)
	vertical = _bounds(_view.segment_view.get_node("Segment_9_6_0") as Node3D)
	assert_true(vertical.end.y > ArtScale.WALL_HEIGHT)


func test_cutaway_still_shows_doorways_and_windows() -> void:
	var grid: SimGrid = _world.grid
	var run: Dictionary[Vector3i, int] = {Vector3i(9, 5, 0): SimGrid.Segment.WALL,
		Vector3i(9, 6, 0): SimGrid.Segment.WINDOW, Vector3i(9, 7, 0): SimGrid.Segment.DOORWAY}
	grid.set_segments(run)
	_view.set_wall_mode(ShopView.WallMode.CUTAWAY)
	var doorway: Node3D = _view.segment_view.get_node("Segment_9_7_0") as Node3D
	assert_not_null(doorway.get_node_or_null("Threshold"), "a lowered doorway keeps a threshold")
	var posts: int = 0
	for child: Node in doorway.get_children():
		# Caps and the threshold are thin strips; posts stand to the lowered height.
		if child is MeshInstance3D and ((child as MeshInstance3D).mesh as BoxMesh).size.y > 0.1:
			posts += 1
	assert_eq(posts, 2, "and a post stub at each end")
	var window: Node3D = _view.segment_view.get_node("Segment_9_6_0") as Node3D
	var glass: MeshInstance3D = window.get_node_or_null("Glass") as MeshInstance3D
	assert_not_null(glass, "a lowered window shows a glass strip, not the wall cap")
	assert_eq((glass.material_override as StandardMaterial3D).albedo_color, WallSegmentView.GLASS_SWATCH.color)
	assert_null(window.get_node_or_null("Top"))


func test_shell_window_opens_the_cell_and_replaces_street_dressing() -> void:
	var grid: SimGrid = _world.grid
	# The south frontage next to the street door carries dressing on (5, 10).
	var dressed: Array[Vector2i] = []
	for detail: Node3D in _view.room_dressing.wall_detail_nodes():
		dressed.append(detail.get_meta(&"wall_cell"))
	assert_true(dressed.has(Vector2i(5, 10)))
	var detail_count: int = dressed.size()
	grid.set_segment(Vector3i(5, 10, SimGrid.EDGE_NORTH), SimGrid.Segment.WINDOW)
	var box: MeshInstance3D = _view.get_node("Walls").get_children().filter(
		func(node: Node) -> bool: return node.get_meta("wall_cell", Vector2i(-1, -1)) == Vector2i(5, 10))[0]
	var span: Vector2 = _view.segment_view.window_span()
	assert_almost_eq((box.mesh as BoxMesh).size.y, span.x, 0.001, "the cell box keeps only its sill")
	assert_almost_eq(box.position.y + (box.get_node("Top") as Node3D).position.y, ArtScale.WALL_HEIGHT + 0.005, 0.001)
	assert_not_null(_view.segment_view.get_node_or_null("ShellWindow_5_10"))
	var after: Array[Vector2i] = []
	for detail: Node3D in _view.room_dressing.wall_detail_nodes():
		after.append(detail.get_meta(&"wall_cell"))
	assert_false(after.has(Vector2i(5, 10)), "no street pane over the player's window")
	assert_eq(after.size(), detail_count - 1, "the other frontage details keep their places")


func test_back_door_replaces_shell_and_restores_it_when_removed() -> void:
	var grid: SimGrid = _world.grid
	var edge: Vector3i = Vector3i(13, 6, SimGrid.EDGE_WEST)
	grid.set_segment(edge, SimGrid.Segment.DOORWAY)
	var door: Node3D = _view.segment_view.get_node_or_null("BackDoor_13_6") as Node3D
	assert_not_null(door)
	assert_not_null(door.get_node_or_null("KenneyDoor"), "existing kit frame at the shared scale")
	var tile: MeshInstance3D = door.get_node_or_null("Floor") as MeshInstance3D
	assert_not_null(tile, "the opened shell cell has a floor threshold")
	assert_eq(tile.material_override, _view.floor_mesh.material_override, "same floor material")
	assert_almost_eq(tile.global_position.y, 0.0, 0.0001)
	var box: MeshInstance3D = _view.get_node("Walls").get_children().filter(
		func(node: Node) -> bool: return node.get_meta("wall_cell", SimGrid.NO_CELL) == Vector2i(13, 6))[0]
	assert_false(box.visible, "no solid shell box inside the opening")
	_view.set_wall_mode(ShopView.WallMode.DOWN)
	door = _view.segment_view.get_node("BackDoor_13_6") as Node3D
	assert_null(door.get_node_or_null("KenneyDoor"), "cutaway keeps low posts without a floating frame")
	assert_not_null(door.get_node_or_null("Floor"), "cutaway keeps the threshold")
	assert_true(_bounds(door).end.y <= ShopView.LOWERED_HEIGHT + 0.001)
	grid.set_segment(edge, SimGrid.Segment.NONE)
	box = _view.get_node("Walls").get_children().filter(
		func(node: Node) -> bool: return node.get_meta("wall_cell", SimGrid.NO_CELL) == Vector2i(13, 6))[0]
	assert_true(box.visible)
	assert_null(_view.segment_view.get_node_or_null("BackDoor_13_6"))


func _bounds(root: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for child: Node in root.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null:
			continue
		# Shop-local: the runner's scene root may not have entered the tree yet.
		var box: AABB = root.transform * mesh.transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
