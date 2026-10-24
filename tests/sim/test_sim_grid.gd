extends TestCase
## FK-012: grid conventions, placement, reservations and pathfinding.

const NONE := Vector2i(-1, -1)


func _room() -> SimGrid:
	# 8x6 room, door gap at the bottom, street entry below it.
	return SimGrid.from_ascii(PackedStringArray([
		"########",
		"#......#",
		"#......#",
		"#......#",
		"#......#",
		"###..###",
		"   EE   ",
	]))


func test_rotate_cell_matches_documented_example() -> void:
	# A 2x1 stove with its work cell in front of the left cell.
	var fp := Vector2i(2, 1)
	var w := Vector2i(0, -1)
	assert_eq(GridMath.rotate_cell(w, fp, 0), Vector2i(0, -1))
	assert_eq(GridMath.rotate_cell(w, fp, 1), Vector2i(1, 0))
	assert_eq(GridMath.rotate_cell(w, fp, 2), Vector2i(1, 1))
	assert_eq(GridMath.rotate_cell(w, fp, 3), Vector2i(-1, 1))
	assert_eq(GridMath.rotate_cell(w, fp, 4), w, "four turns is identity")
	assert_eq(GridMath.rotate_cell(w, fp, -1), Vector2i(-1, 1), "negative turns wrap")


func test_rotate_keeps_footprint_cells_inside_rotated_footprint() -> void:
	var fp := Vector2i(3, 2)
	for turns in 4:
		var rf := GridMath.rotated_footprint(fp, turns)
		for y in fp.y:
			for x in fp.x:
				var c := GridMath.rotate_cell(Vector2i(x, y), fp, turns)
				assert_true(c.x >= 0 and c.y >= 0 and c.x < rf.x and c.y < rf.y,
						"cell %s turn %d -> %s outside %s" % [Vector2i(x, y), turns, c, rf])


func test_cell_world_round_trip() -> void:
	var cell := Vector2i(3, 7)
	assert_eq(GridMath.cell_to_world(cell), Vector3(1.75, 0.0, 3.75))
	assert_eq(GridMath.world_to_cell(GridMath.cell_to_world(cell)), cell)


func test_ascii_terrain_and_entries() -> void:
	var g := _room()
	assert_eq(g.size, Vector2i(8, 7))
	assert_eq(g.terrain(Vector2i(0, 0)), SimGrid.Terrain.WALL)
	assert_eq(g.terrain(Vector2i(1, 1)), SimGrid.Terrain.FLOOR)
	assert_eq(g.terrain(Vector2i(0, 6)), SimGrid.Terrain.OUTSIDE)
	assert_eq(g.entries(), [Vector2i(3, 6), Vector2i(4, 6)] as Array[Vector2i])
	assert_false(g.is_walkable(Vector2i(0, 0)))
	assert_true(g.is_walkable(Vector2i(3, 6)))


func test_path_from_street_into_room() -> void:
	var g := _room()
	var path := g.find_path(Vector2i(3, 6), Vector2i(1, 1))
	assert_false(path.is_empty())
	assert_eq(path[0], Vector2i(3, 6))
	assert_eq(path[-1], Vector2i(1, 1))
	for c in path:
		assert_true(g.is_walkable(c), "path crosses blocked cell %s" % c)


func test_no_corner_cutting() -> void:
	# The wall at (0,1) means (0,0)->(1,1) may not step diagonally past it.
	var g := SimGrid.from_ascii(PackedStringArray(["..", "#."]))
	assert_eq(g.find_path(Vector2i(0, 0), Vector2i(1, 1)),
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)] as Array[Vector2i])
	assert_eq(g.find_path(Vector2i(1, 1), Vector2i(0, 0)),
			[Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0)] as Array[Vector2i])
	var open := SimGrid.from_ascii(PackedStringArray(["..", ".."]))
	assert_eq(open.find_path(Vector2i(0, 0), Vector2i(1, 1)).size(), 2, "open corner allows the diagonal")


func test_place_blocks_and_remove_reopens() -> void:
	var g := _room()
	# A 6-wide counter across the room except one gap.
	var counter := g.place(Vector2i(5, 1), Vector2i(1, 3), 0, true)
	assert_not_null(counter)
	assert_true(g.is_reachable(Vector2i(3, 6), Vector2i(6, 1)), "gap at x=6 keeps the back reachable")
	var plug := g.place(Vector2i(1, 1), Vector2i(6, 3), 0, true)
	assert_not_null(plug)
	assert_false(g.is_reachable(Vector2i(3, 6), Vector2i(6, 1)), "fully walled off")
	assert_true(g.remove(plug.id))
	assert_true(g.is_reachable(Vector2i(3, 6), Vector2i(6, 1)), "reopened after removal")
	assert_false(g.remove(plug.id), "removing twice fails")


func test_can_place_rules() -> void:
	var g := _room()
	assert_eq(g.can_place(Vector2i(2, 1), Vector2i(1, 1), 0), SimGrid.PlaceResult.OK)
	assert_eq(g.can_place(Vector2i(2, 1), Vector2i(0, 1), 0), SimGrid.PlaceResult.NOT_FLOOR, "on a wall")
	assert_eq(g.can_place(Vector2i(2, 1), Vector2i(7, 7), 0), SimGrid.PlaceResult.OUT_OF_BOUNDS)
	assert_eq(g.can_place(Vector2i(1, 2), Vector2i(3, 5), 0), SimGrid.PlaceResult.NOT_FLOOR, "street is not floor")
	g.place(Vector2i(2, 1), Vector2i(1, 1), 0, true)
	assert_eq(g.can_place(Vector2i(1, 1), Vector2i(2, 1), 0), SimGrid.PlaceResult.OVERLAPS)
	assert_null(g.place(Vector2i(1, 1), Vector2i(2, 1), 0, true), "overlapping place returns null")


func test_rotated_place_uses_rotated_cells() -> void:
	var g := _room()
	var stove := g.place(Vector2i(2, 1), Vector2i(3, 2), 1, true, [Vector2i(0, -1)] as Array[Vector2i])
	assert_not_null(stove)
	assert_eq(stove.cells, [Vector2i(3, 2), Vector2i(3, 3)] as Array[Vector2i], "1x2 after one turn")
	assert_eq(stove.work_cells, [Vector2i(4, 2)] as Array[Vector2i])
	assert_eq(g.item_at(Vector2i(3, 3)), stove)


func test_non_solid_item_stays_walkable() -> void:
	var g := _room()
	var rug := g.place(Vector2i(2, 2), Vector2i(2, 2), 0, false)
	assert_not_null(rug)
	assert_true(g.is_walkable(Vector2i(2, 2)))
	assert_eq(g.can_place(Vector2i(1, 1), Vector2i(2, 2), 0), SimGrid.PlaceResult.OVERLAPS, "still occupied")


func test_cells_changed_signal() -> void:
	var g := _room()
	var seen: Array[Vector2i] = []
	g.cells_changed.connect(func(cells: Array[Vector2i]) -> void: seen.append_array(cells))
	var it := g.place(Vector2i(2, 1), Vector2i(1, 1), 0, true)
	assert_eq(seen, [Vector2i(1, 1), Vector2i(2, 1)] as Array[Vector2i])
	seen.clear()
	g.remove(it.id)
	assert_eq(seen.size(), 2)


func test_path_out_of_newly_blocked_start() -> void:
	var g := _room()
	g.place(Vector2i(1, 1), Vector2i(3, 3), 0, true)
	var path := g.find_path(Vector2i(3, 3), Vector2i(1, 1))
	assert_false(path.is_empty(), "an agent covered by new furniture can still walk out")
	assert_true(g.find_path(Vector2i(1, 1), Vector2i(3, 3)).is_empty(), "but a blocked goal is unreachable")
	assert_false(g.is_walkable(Vector2i(3, 3)), "the start stays blocked afterwards")


func test_find_path_to_any_picks_cheapest() -> void:
	var g := _room()
	var goals: Array[Vector2i] = [Vector2i(6, 1), Vector2i(3, 4)]
	var path := g.find_path_to_any(Vector2i(3, 6), goals)
	assert_eq(path[-1], Vector2i(3, 4))
	assert_true(g.find_path_to_any(Vector2i(3, 6), [Vector2i(0, 0)] as Array[Vector2i]).is_empty())


func test_reservations() -> void:
	var g := _room()
	var table := g.place(Vector2i(2, 2), Vector2i(2, 2), 0, true, [] as Array[Vector2i],
			[Vector2i(-1, 0), Vector2i(2, 1)] as Array[Vector2i])
	var seat_a := g.free_seat_cell(table)
	assert_eq(seat_a, Vector2i(1, 2))
	assert_true(table.reserve(seat_a, 7))
	assert_true(table.reserve(seat_a, 7), "re-reserve own cell")
	assert_false(table.reserve(seat_a, 8), "taken by someone else")
	assert_eq(g.free_seat_cell(table), Vector2i(4, 3))
	assert_true(table.reserve(Vector2i(4, 3), 8))
	assert_eq(g.free_seat_cell(table), NONE)
	assert_false(table.reserve(Vector2i(0, 0), 9), "not one of its cells")
	table.release_all(7)
	assert_eq(table.reserved_by(seat_a), -1)
	assert_false(table.release(Vector2i(4, 3), 7), "can't release someone else's")
	assert_true(table.release(Vector2i(4, 3), 8))


func test_items_are_in_placement_order() -> void:
	var g := _room()
	var a := g.place(Vector2i(1, 1), Vector2i(6, 1), 0, true)
	var b := g.place(Vector2i(1, 1), Vector2i(1, 1), 0, true)
	var ids: Array[int] = []
	for it in g.items():
		ids.append(it.id)
	assert_eq(ids, [a.id, b.id] as Array[int])


func test_agent_buried_under_large_item_gets_out() -> void:
	var g := _room()
	g.place(Vector2i(3, 3), Vector2i(2, 1), 0, true)
	var path := g.find_path(Vector2i(3, 2), Vector2i(1, 4))
	assert_false(path.is_empty(), "the centre of a 3x3 item still has a way out")
	assert_eq(path[0], Vector2i(3, 2))
	for k in range(1, path.size()):
		assert_true(g.is_walkable(path[k]), "only the start may be blocked")
	var exit := g.nearest_walkable(Vector2i(3, 2))
	assert_true(g.is_walkable(exit))
	assert_eq(maxi(absi(exit.x - 3), absi(exit.y - 2)), 2, "exit is in the first open ring")
	assert_eq(g.nearest_walkable(Vector2i(3, 2)), exit, "same answer every time")


func test_free_cells_skip_unwalkable() -> void:
	var g := _room()
	# A table against the left wall: its left seat lands on the wall.
	var table := g.place(Vector2i(2, 2), Vector2i(1, 1), 0, true, [] as Array[Vector2i],
			[Vector2i(-1, 0), Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(g.free_seat_cell(table), Vector2i(3, 1), "the wall seat is skipped")
	# A stove whose work cell then gets covered by another item.
	var stove := g.place(Vector2i(2, 1), Vector2i(4, 3), 0, true, [Vector2i(0, 1)] as Array[Vector2i])
	assert_eq(g.free_work_cell(stove), Vector2i(4, 4))
	g.place(Vector2i(1, 1), Vector2i(4, 4), 0, true)
	assert_eq(g.free_work_cell(stove), NONE, "a covered work cell is not offered")


func test_removed_item_is_inert() -> void:
	var g := _room()
	var removed: Array[int] = []
	g.item_removed.connect(func(it: PlacedItem) -> void: removed.append(it.id))
	var table := g.place(Vector2i(2, 2), Vector2i(2, 2), 0, true, [] as Array[Vector2i],
			[Vector2i(-1, 0)] as Array[Vector2i])
	assert_true(table.reserve(Vector2i(1, 2), 5))
	g.remove(table.id)
	assert_eq(removed, [table.id] as Array[int])
	assert_true(table.removed)
	assert_eq(table.reserved_by(Vector2i(1, 2)), -1, "reservations cleared")
	assert_false(table.reserve(Vector2i(1, 2), 5), "can't reserve a removed item")
	assert_eq(g.free_seat_cell(table), NONE)


func test_set_terrain_refuses_under_items() -> void:
	var g := _room()
	g.place(Vector2i(1, 1), Vector2i(2, 2), 0, true)
	assert_false(g.set_terrain(Vector2i(2, 2), SimGrid.Terrain.WALL))
	assert_eq(g.terrain(Vector2i(2, 2)), SimGrid.Terrain.FLOOR)
	assert_true(g.set_terrain(Vector2i(3, 3), SimGrid.Terrain.WALL))
	assert_false(g.set_terrain(Vector2i(99, 0), SimGrid.Terrain.FLOOR))


func test_empty_ascii_is_outside() -> void:
	var g := SimGrid.from_ascii(PackedStringArray())
	assert_eq(g.size, Vector2i(1, 1))
	assert_false(g.is_walkable(Vector2i.ZERO))


func test_path_cost_is_exact_for_equal_paths() -> void:
	var a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 2)]
	var b: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 1), Vector2i(3, 2)]
	assert_true(GridMath.path_cost(a) == GridMath.path_cost(b), "same step mix, same cost")
	assert_almost_eq(GridMath.path_cost(a), 1.0 + 2.0 * GridMath.DIAGONAL_COST)
	assert_true(GridMath.octile(Vector2i(0, 0), Vector2i(3, 2)) <= GridMath.path_cost(a), "octile is a lower bound")


func test_find_path_to_any_tie_goes_to_earlier_goal() -> void:
	var g := SimGrid.new(Vector2i(5, 5))
	assert_eq(g.find_path_to_any(Vector2i(2, 2), [Vector2i(4, 2), Vector2i(0, 2)] as Array[Vector2i])[-1],
			Vector2i(4, 2), "equal cost: the first listed goal wins")
	assert_eq(g.find_path_to_any(Vector2i(2, 2), [Vector2i(0, 2), Vector2i(4, 2)] as Array[Vector2i])[-1],
			Vector2i(0, 2), "and the order decides, not the position")


## Neighbours have a stable order, skip walls, and never cut blocked corners.
func test_walkable_neighbours_order_and_corner_rules() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(3, 3))
	assert_eq(grid.walkable_neighbours(Vector2i(1, 1)), [Vector2i(1, 0), Vector2i(2, 1),
		Vector2i(1, 2), Vector2i(0, 1), Vector2i(2, 0), Vector2i(2, 2),
		Vector2i(0, 2), Vector2i(0, 0)] as Array[Vector2i])
	grid.set_terrain(Vector2i(1, 0), SimGrid.Terrain.WALL)
	assert_eq(grid.walkable_neighbours(Vector2i(1, 1)), [Vector2i(2, 1), Vector2i(1, 2),
		Vector2i(0, 1), Vector2i(2, 2), Vector2i(0, 2)] as Array[Vector2i])
	assert_eq(grid.walkable_neighbours(Vector2i.ZERO), [Vector2i(0, 1)] as Array[Vector2i])
