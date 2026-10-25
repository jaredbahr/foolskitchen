extends TestCase
## FK-012: grid conventions, placement, reservations and pathfinding.

const NONE := Vector2i(-1, -1)


class FloorChangeProbe:
	extends RefCounted
	var records: Array[Dictionary] = []
	var _grid_ref: WeakRef
	var _table_id: int
	var _origin: Vector2i
	var _seat: Vector2i


	func _init(grid: SimGrid, table: PlacedItem) -> void:
		_grid_ref = weakref(grid)
		_table_id = table.id
		_origin = table.origin
		_seat = table.seat_cells[0]


	func changed(_cells: Array[Vector2i]) -> void:
		var grid: SimGrid = _grid_ref.get_ref() as SimGrid
		var normal: PlacedItem = grid.item_on_layer(_origin, ItemDef.PlacementLayer.NORMAL)
		var floor_item: PlacedItem = grid.item_on_layer(_origin, ItemDef.PlacementLayer.FLOOR_DECOR)
		var table: PlacedItem = grid.item(_table_id)
		records.append({"normal": normal.id if normal != null else 0,
			"floor": floor_item.id if floor_item != null else 0,
			"seat_table": grid.dining_table_id(_seat),
			"holder": table.reserved_by(_seat) if table != null else -1,
			"walkable": grid.is_walkable(_seat)})


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


func test_floor_layer_shares_normal_footprints_in_both_orders_and_all_rotations() -> void:
	for floor_first: bool in [true, false]:
		for turns: int in range(4):
			var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
			var floor_def: ItemDef = _floor_definition(Vector2i(4, 4))
			var table_def: ItemDef = _floor_test_table()
			var rug: PlacedItem = null
			var table: PlacedItem = null
			if floor_first:
				rug = grid.place_def(floor_def, Vector2i(1, 1), turns)
				table = grid.place_def(table_def, Vector2i(2, 2), turns)
			else:
				table = grid.place_def(table_def, Vector2i(2, 2), turns)
				rug = grid.place_def(floor_def, Vector2i(1, 1), turns)
			assert_not_null(rug)
			assert_not_null(table)
			if rug == null or table == null:
				continue
			var seat: Vector2i = table.origin + GridMath.rotate_cell(Vector2i(0, 1), table_def.footprint, turns)
			assert_eq(table.seat_cells, [seat] as Array[Vector2i])
			assert_eq(grid.dining_table_id(seat), table.id)
			assert_true(table.reserve(seat, 42))
			assert_true(grid.is_walkable(seat))
			assert_false(grid.find_path(Vector2i.ZERO, seat).is_empty())
			assert_false(grid.is_walkable(table.origin), "the normal solid table still blocks its footprint")
			assert_eq(grid.item_at(table.origin), table)
			assert_eq(grid.item_on_layer(table.origin, ItemDef.PlacementLayer.FLOOR_DECOR), rug)
			assert_eq(grid.items_at(table.origin), [table, rug] as Array[PlacedItem])
			var copies: Array[PlacedItem] = grid.items_at(table.origin)
			copies.clear()
			assert_eq(grid.items_at(table.origin).size(), 2)
			assert_eq(table.reserved_by(seat), 42)
			assert_eq(rug.placement_layer, ItemDef.PlacementLayer.FLOOR_DECOR)


func test_floor_layer_keeps_terrain_and_same_layer_overlap_rules() -> void:
	var grid: SimGrid = _room()
	var floor_def: ItemDef = _floor_definition(Vector2i(2, 2))
	assert_eq(grid.can_place_def(floor_def, Vector2i(0, 1)), SimGrid.PlaceResult.NOT_FLOOR)
	assert_eq(grid.can_place_def(floor_def, Vector2i(8, 6)), SimGrid.PlaceResult.OUT_OF_BOUNDS)
	assert_eq(grid.can_place_def(floor_def, Vector2i(3, 5)), SimGrid.PlaceResult.NOT_FLOOR)
	var rug: PlacedItem = grid.place_def(floor_def, Vector2i(2, 2))
	assert_not_null(rug)
	assert_eq(grid.can_place_def(floor_def, Vector2i(2, 2)), SimGrid.PlaceResult.OVERLAPS)
	assert_null(grid.place_def(floor_def, Vector2i(3, 3)))
	assert_false(grid.set_terrain(Vector2i(2, 2), SimGrid.Terrain.WALL))
	assert_true(grid.is_walkable(Vector2i(2, 2)))
	assert_eq(grid.item_at(Vector2i(2, 2)), rug, "a lone floor item remains available to legacy picking")
	assert_null(grid.item_on_layer(Vector2i(2, 2), ItemDef.PlacementLayer.NORMAL))
	var normal: PlacedItem = grid.place(Vector2i.ONE, Vector2i(2, 2), 0, false)
	assert_not_null(normal)
	assert_eq(grid.can_place(Vector2i.ONE, Vector2i(2, 2), 0), SimGrid.PlaceResult.OVERLAPS)
	assert_true(grid.is_walkable(Vector2i(2, 2)), "two non-solid layers never block people")
	assert_null(grid.place(Vector2i.ONE, Vector2i(2, 2), 0, false))
	assert_null(grid.place_def(floor_def, Vector2i(2, 2)))


func test_floor_relocation_and_removal_preserve_table_chair_and_live_reservation() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(10, 10))
	var table: PlacedItem = grid.place_def(_floor_test_table(), Vector2i(2, 2))
	var chair_def: ItemDef = ItemDef.new()
	chair_def.id = &"floor_test_chair"
	chair_def.category = ItemDef.Category.CHAIR
	chair_def.solid = false
	chair_def.seat_cells = [Vector2i.ZERO]
	var chair: PlacedItem = grid.place_def(chair_def, Vector2i(3, 3))
	# The second seat faces the other half of the same physical table.
	var occupied: Vector2i = chair.origin
	assert_eq(grid.dining_furnishing_id(occupied), chair.id)
	assert_true(table.reserve(occupied, 77))
	var table_seats: Array[Vector2i] = table.seat_cells.duplicate()
	var rug: PlacedItem = grid.place_def(_floor_definition(Vector2i(4, 4)), Vector2i(1, 1))
	var rug_id: int = rug.id
	var table_origin: Vector2i = table.origin
	var changed: Array[Array] = []
	grid.cells_changed.connect(func(cells: Array[Vector2i]) -> void: changed.append(cells.duplicate()))
	assert_true(grid.relocate_def(rug_id, Vector2i(5, 5), 1))
	assert_eq(changed.size(), 1)
	assert_true(grid.item(rug_id) == rug)
	assert_eq(grid.item_on_layer(occupied, ItemDef.PlacementLayer.NORMAL), chair)
	assert_null(grid.item_on_layer(occupied, ItemDef.PlacementLayer.FLOOR_DECOR))
	assert_true(grid.item(table.id) == table)
	assert_eq(table.origin, table_origin)
	assert_eq(table.seat_cells, table_seats)
	assert_eq(table.reserved_by(occupied), 77)
	assert_eq(grid.dining_table_id(occupied), table.id)
	assert_eq(grid.dining_furnishing_id(occupied), chair.id)
	assert_true(grid.remove(rug_id))
	assert_eq(changed.size(), 2)
	assert_eq(table.reserved_by(occupied), 77)
	assert_eq(grid.item_at(occupied), chair)
	assert_false(grid.relocate_def(chair.id, Vector2i(4, 4), 0), "the original occupied-chair guard still applies")


func test_normal_move_and_remove_leave_the_floor_item_in_place() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var rug: PlacedItem = grid.place_def(_floor_definition(Vector2i(4, 4)), Vector2i(1, 1))
	var table: PlacedItem = grid.place_def(_floor_test_table(), Vector2i(2, 2))
	assert_true(grid.relocate_def(table.id, Vector2i(3, 3), 1))
	assert_eq(grid.item_at(Vector2i(2, 2)), rug)
	assert_true(grid.is_walkable(Vector2i(2, 2)))
	assert_eq(grid.item_on_layer(Vector2i(3, 3), ItemDef.PlacementLayer.FLOOR_DECOR), rug)
	assert_false(grid.is_walkable(Vector2i(3, 3)))
	assert_true(grid.remove(table.id))
	assert_true(grid.item(rug.id) == rug)
	assert_eq(grid.item_at(Vector2i(3, 3)), rug)
	assert_true(grid.is_walkable(Vector2i(3, 3)))
	assert_eq(rug.origin, Vector2i(1, 1))


func test_failed_floor_move_is_atomic_and_does_not_clear_other_layer() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(8, 8))
	var definition: ItemDef = _floor_definition(Vector2i(2, 2))
	var rug: PlacedItem = grid.place_def(definition, Vector2i(1, 1))
	var other: PlacedItem = grid.place_def(definition, Vector2i(5, 5))
	var normal: PlacedItem = grid.place(Vector2i.ONE, Vector2i(5, 5), 0, true)
	var changed: Array[Array] = []
	grid.cells_changed.connect(func(cells: Array[Vector2i]) -> void: changed.append(cells.duplicate()))
	assert_false(grid.relocate_def(rug.id, Vector2i(5, 5), 1))
	assert_false(grid.relocate_def(rug.id, Vector2i(7, 7), 0))
	assert_eq(changed.size(), 0)
	assert_eq(rug.origin, Vector2i(1, 1))
	assert_eq(grid.item_on_layer(Vector2i(1, 1), ItemDef.PlacementLayer.FLOOR_DECOR), rug)
	assert_eq(grid.items_at(Vector2i(5, 5)), [normal, other] as Array[PlacedItem])
	assert_false(grid.is_walkable(Vector2i(5, 5)))


func test_invalid_floor_definition_is_rejected_without_any_placement() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(4, 4))
	var definition: ItemDef = _floor_definition(Vector2i.ONE)
	definition.solid = true
	assert_eq(grid.can_place_def(definition, Vector2i.ONE), SimGrid.PlaceResult.INVALID_LAYER)
	assert_null(grid.place_def(definition, Vector2i.ONE))
	definition.solid = false
	assert_null(grid.place(Vector2i.ONE, Vector2i.ONE, 0, true, [], [], definition),
		"generic callers cannot smuggle a solid item into the floor layer")
	assert_eq(grid.items().size(), 0)
	assert_true(grid.is_walkable(Vector2i.ONE))


func test_floor_notifications_observe_complete_coverage_and_preserved_dining_holds() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(10, 10))
	var table: PlacedItem = grid.place_def(_floor_test_table(), Vector2i(2, 2))
	assert_true(table.reserve(table.seat_cells[0], 91))
	var probe: FloorChangeProbe = FloorChangeProbe.new(grid, table)
	grid.cells_changed.connect(probe.changed)
	var rug: PlacedItem = grid.place_def(_floor_definition(Vector2i(4, 4)), Vector2i(1, 1))
	assert_eq(probe.records, [{"normal": table.id, "floor": rug.id,
		"seat_table": table.id, "holder": 91, "walkable": true}] as Array[Dictionary])
	assert_true(grid.relocate_def(rug.id, Vector2i(5, 5), 1))
	assert_true(grid.remove(rug.id))
	assert_eq(probe.records.size(), 3, "one coherent notification per accepted floor edit")
	for index: int in [1, 2]:
		assert_eq(probe.records[index], {"normal": table.id, "floor": 0,
			"seat_table": table.id, "holder": 91, "walkable": true})
	grid.cells_changed.disconnect(probe.changed)


func _floor_definition(footprint: Vector2i) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"floor_test_rug"
	definition.category = ItemDef.Category.DECOR
	definition.placement_layer = ItemDef.PlacementLayer.FLOOR_DECOR
	definition.footprint = footprint
	definition.solid = false
	return definition


func _floor_test_table() -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"floor_test_table"
	definition.category = ItemDef.Category.TABLE
	definition.footprint = Vector2i(2, 1)
	definition.seat_cells = [Vector2i(0, 1)]
	return definition
