extends TestCase
## D26: where WallFinishView draws a face's facing and hangs an item. Pure
## geometry on a small grid; no rendering.


func test_shell_face_sits_just_off_the_wall_at_the_drawn_height() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["#####", "#...#", "#...#", "#####"]))
	var face: Vector3i = Vector3i(1, 1, 3)
	var frame: Dictionary = WallFinishView.face_frame(grid, face, false, {} as Dictionary[Vector2i, bool])
	assert_almost_eq((frame["origin"] as Vector3).x, 0.5 + WallFinishView.FACE_GAP, 0.0001, "on the west wall's room face")
	assert_eq(frame["normal"], Vector3(1, 0, 0), "facing into the room")
	assert_eq(frame["tangent"], Vector3(0, 0, -1), "its right, seen from the room, is north")
	assert_almost_eq(float(frame["height"]), ArtScale.WALL_HEIGHT, 0.0001)
	var lowered: Dictionary[Vector2i, bool] = {Vector2i(0, 1): true}
	frame = WallFinishView.face_frame(grid, face, false, lowered)
	assert_almost_eq(float(frame["height"]), ShopView.LOWERED_HEIGHT, 0.0001, "a lowered shell cell gives a stub")


func test_interior_faces_stop_at_a_joining_wall_and_wrap_the_far_side() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["######", "#....#", "#....#", "#....#", "######"]))
	# A wall on the line west of column 3 (rows 1-2) and one turning east from its foot.
	grid.set_segments({Vector3i(3, 1, SimGrid.EDGE_WEST): SimGrid.Segment.WALL,
		Vector3i(3, 2, SimGrid.EDGE_WEST): SimGrid.Segment.WALL,
		Vector3i(3, 3, SimGrid.EDGE_NORTH): SimGrid.Segment.WALL} as Dictionary[Vector3i, int])
	var none: Dictionary[Vector2i, bool] = {}
	var east_side: Dictionary = WallFinishView.face_frame(grid, Vector3i(3, 2, 3), true, none)
	assert_almost_eq((east_side["origin"] as Vector3).x, 1.5 + WallFinishView.HALF_THICKNESS + WallFinishView.FACE_GAP, 0.0001)
	assert_almost_eq(float(east_side["height"]), ShopView.LOWERED_HEIGHT, 0.0001, "interior walls lowered in Cutaway")
	# Seen from (3, 2) its right is north; its left (south) end meets the turning wall on the room's side.
	assert_almost_eq(float(east_side["x0"]), -0.25 + WallFinishView.HALF_THICKNESS, 0.0001, "stops at the joining slab")
	assert_almost_eq(float(east_side["x1"]), 0.25, 0.0001, "a free end stays at the vertex")
	var west_side: Dictionary = WallFinishView.face_frame(grid, Vector3i(2, 2, 1), false, none)
	# From (2, 2) the right is south: that end wraps the corner on the far side.
	assert_almost_eq(float(west_side["x1"]), 0.25 + WallFinishView.HALF_THICKNESS, 0.0001, "wraps the outside corner")
	assert_almost_eq(float(west_side["height"]), ArtScale.WALL_HEIGHT, 0.0001)


func test_hung_items_turn_their_back_to_the_wall_over_their_span() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["#####", "#...#", "#...#", "#####"]))
	for dir: int in 4:
		var into: Vector2i = WallFaces.DIRS[dir]
		var xf: Transform3D = WallFinishView.hung_transform(grid, Vector3i(2, 1, dir), 1)
		var back: Vector3 = xf.basis * Vector3(0, 0, 1)
		assert_almost_eq(back.x, float(into.x), 0.0001, "dir %d" % dir)
		assert_almost_eq(back.z, float(into.y), 0.0001, "dir %d" % dir)
	# Two faces wide on the north wall: centred between cells 1 and 2.
	var wide: Transform3D = WallFinishView.hung_transform(grid, Vector3i(1, 1, 0), 2)
	assert_almost_eq(wide.origin.x, 1.0, 0.0001)
	assert_almost_eq(wide.origin.z, 0.75, 0.0001)
