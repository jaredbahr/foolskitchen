extends TestCase
## FK-070 wall segment presentation: geometry follows the sim, never the reverse.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _view: ShopView
var _world: SimWorld


func before_each() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_world = ShopBuilder.build(LAYOUT, content, errors)
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
