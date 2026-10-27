extends TestCase
## FK-080: buying more floor on the lot. The outer walls re-wrap the floor,
## nothing shifts, shrinking refuses cut-offs, and saves keep the footprint.
## Grid: the starting shell is x 0..13, y 0..10 (street door at the bottom).
## The Tier 1 lot lets the outer walls move 2 cells west (x -2) and east
## (x 15) and 4 north (y -4); never towards the street. New floor can go on
## x -1 and x 14 beside the shop and on y -3..-1 behind it.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _cash: int = 1000
var _entries: Array[Dictionary] = []


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_cash = 1000
	_entries.clear()
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash), LAYOUT)


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null


func test_lot_comes_from_data_and_the_start_is_unchanged() -> void:
	var footprint: ShopFootprint = _editor.footprint()
	assert_eq(footprint.building, Rect2i(0, 0, 14, 11))
	assert_eq(footprint.lot, Rect2i(-2, -4, 18, 15))
	assert_eq(footprint.cell_price, 15)
	assert_true(footprint.can_hold(Vector2i(14, 9)))
	assert_true(footprint.can_hold(Vector2i(-1, 9)))
	assert_true(footprint.can_hold(Vector2i(-1, -3)))
	assert_false(footprint.can_hold(Vector2i(15, 9)), "the lot edge is kept for the wall")
	assert_false(footprint.can_hold(Vector2i(14, 10)), "never towards the street")
	assert_false(footprint.can_hold(Vector2i(5, 5)), "the starting building is not lot")
	var start: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var derived: Dictionary[Vector2i, int] = footprint.terrain_for({} as Dictionary[Vector2i, bool])
	for cell: Vector2i in start.cells():
		assert_eq(derived[cell], start.terrain(cell) as int, "cell %s" % cell)
	assert_eq(footprint.problem({} as Dictionary[Vector2i, bool]), "")
	assert_eq(_sim.world.grid.bounds, Rect2i(0, 0, 14, 12), "no growth until floor is bought")


func test_adding_a_side_wing_rewraps_the_outer_walls() -> void:
	var grid: SimGrid = _sim.world.grid
	var check: EditCheck = _editor.check_floor(_rect(14, 5, 1, 5), true)
	assert_true(check.ok, check.why)
	assert_eq(check.cost, 5 * 15)
	assert_eq(check.floor_cells.size(), 5)
	assert_eq(grid.terrain(Vector2i(13, 5)), SimGrid.Terrain.WALL, "checks change nothing")
	assert_true(_editor.apply_floor(_rect(14, 5, 1, 5), true))
	assert_eq(_cash, 1000 - 75)
	assert_eq(_entries[0]["category"], Ledger.UPGRADES)
	for y: int in range(5, 10):
		assert_eq(grid.terrain(Vector2i(13, y)), SimGrid.Terrain.FLOOR, "old wall at y %d opens up" % y)
		assert_eq(grid.terrain(Vector2i(14, y)), SimGrid.Terrain.FLOOR)
		assert_eq(grid.terrain(Vector2i(15, y)), SimGrid.Terrain.WALL, "new east wall")
	for x: int in range(13, 16):
		assert_eq(grid.terrain(Vector2i(x, 4)), SimGrid.Terrain.WALL, "new north wall of the wing")
		assert_eq(grid.terrain(Vector2i(x, 10)), SimGrid.Terrain.WALL, "street wall continues")
	assert_eq(grid.terrain(Vector2i(13, 3)), SimGrid.Terrain.WALL, "the kitchen's east wall stays")
	assert_eq(grid.terrain(Vector2i(14, 3)), SimGrid.Terrain.OUTSIDE)
	assert_eq(grid.terrain(Vector2i(15, 11)), SimGrid.Terrain.OUTSIDE, "the street is untouched")
	assert_eq(grid.entries(), [Vector2i(6, 11), Vector2i(7, 11)] as Array[Vector2i], "the door stays")
	assert_eq(WallRules.outer_side(grid, Vector3i(15, 7, SimGrid.EDGE_WEST)), Vector2i(1, 0))
	assert_eq(WallRules.outer_side(grid, Vector3i(14, 10, SimGrid.EDGE_NORTH)), Vector2i(0, 1))
	assert_eq(_editor.bought_floor().size(), 5)
	var path: Array[Vector2i] = grid.find_path(Vector2i(6, 11), Vector2i(14, 5))
	assert_false(path.is_empty(), "guests can walk into the wing")
	assert_eq(path[path.size() - 1], Vector2i(14, 5))


func test_the_west_side_grows_into_negative_cells() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_editor.apply_floor(_rect(-1, 5, 1, 5), true), _editor.last_check.why)
	assert_eq(grid.origin, Vector2i(-2, -4), "the grid grew west and north, nothing shifted")
	assert_eq(grid.terrain(Vector2i(0, 7)), SimGrid.Terrain.FLOOR)
	assert_eq(grid.terrain(Vector2i(-1, 7)), SimGrid.Terrain.FLOOR)
	assert_eq(grid.terrain(Vector2i(-2, 7)), SimGrid.Terrain.WALL)
	assert_eq(grid.terrain(Vector2i(-1, -1)), SimGrid.Terrain.OUTSIDE, "a real cell, not the no-cell marker")
	assert_ne(Vector2i(-1, -1), SimGrid.NO_CELL)
	assert_eq(grid.find_path(Vector2i(6, 11), Vector2i(-1, 9)).back(), Vector2i(-1, 9))
	assert_eq(grid.item_at(Vector2i(2, 6)).origin, Vector2i(2, 6), "the west table did not move")


func test_refuses_floor_that_does_not_join_or_leaves_the_lot() -> void:
	assert_eq(_editor.check_floor(_rect(3, -3, 2, 1), true).why, ShopFootprint.NOT_JOINED)
	assert_eq(_editor.check_floor(_rect(14, 5, 3, 3), true).why, ShopFootprint.OUTSIDE_LOT, "x 16 is beyond the lot")
	assert_eq(_editor.check_floor(_rect(3, -5, 1, 1), true).why, ShopFootprint.OUTSIDE_LOT)
	assert_eq(_editor.check_floor(_rect(15, 5, 1, 3), true).why, ShopFootprint.OUTSIDE_LOT, "the wall ring only")
	# A drag over the wall ring keeps its lot cells: the ring is skipped.
	var ring: EditCheck = _editor.check_floor(_rect(14, 5, 2, 6), true)
	assert_true(ring.ok, ring.why)
	assert_eq(ring.floor_cells, _rect(14, 5, 1, 5))
	assert_eq(_editor.check_floor(_rect(5, 11, 1, 1), true).why, ShopFootprint.OUTSIDE_LOT, "not into the street")
	assert_eq(_editor.check_floor(_rect(5, 5, 2, 2), true).why, ShopFootprint.ALREADY_BUILT)
	# Only diagonal contact with the room through a shell corner is not joined.
	assert_eq(_editor.check_floor(_rect(14, -1, 1, 1), true).why, ShopFootprint.NOT_JOINED)
	assert_eq(_cash, 1000)
	var bare: ShopEditor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash))
	assert_eq(bare.check_floor(_rect(14, 5, 1, 1), true).why, ShopFootprint.NO_LOT)


## The divider's end cells (0, 4) and (13, 4) never open, so floor bought
## beside them alone would be a sealed pocket.
func test_floor_beside_the_kitchen_divider_alone_is_refused() -> void:
	assert_eq(_editor.check_floor(_rect(-1, 4, 1, 1), true).why, ShopFootprint.NOT_JOINED)
	assert_eq(_editor.check_floor(_rect(14, 4, 1, 1), true).why, ShopFootprint.NOT_JOINED)
	assert_true(_editor.apply_floor(_rect(-1, 3, 1, 2), true), _editor.last_check.why)
	assert_eq(_sim.world.grid.terrain(Vector2i(0, 4)), SimGrid.Terrain.WALL)
	assert_eq(_sim.world.grid.find_path(Vector2i(6, 11), Vector2i(-1, 4)).back(), Vector2i(-1, 4))
	assert_eq(_editor.check_floor(_rect(-1, 3, 1, 1), false).why, ShopFootprint.SPLITS,
		"removing the joining cell would seal (-1, 4)")
	assert_true(_editor.check_floor(_rect(-1, 4, 1, 1), false).ok)


## A west outer window turns into an interior window when the wall behind it
## opens. Floor bought behind it alone would be sealed off by that window.
func test_floor_sealed_by_an_old_outer_window_is_refused() -> void:
	var window: Vector3i = Vector3i(1, 2, SimGrid.EDGE_WEST)
	assert_true(_editor.apply_segments({window: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]), _editor.last_check.why)
	_cash = 1000
	assert_eq(_editor.check_floor(_rect(-1, 2, 1, 1), true).why, ShopFootprint.NOT_JOINED)
	assert_false(_editor.apply_floor(_rect(-1, 2, 1, 1), true))
	assert_eq(_cash, 1000)
	assert_eq(_sim.world.grid.terrain(Vector2i(0, 2)), SimGrid.Terrain.WALL)
	assert_true(_editor.check_floor(_rect(-1, 2, 1, 2), true).ok, "with a neighbour it joins round the window")


## Fuzz seed 5: a two-cell notch at (4..5, -1) between wall runs used to stay
## OUTSIDE, a void inside the walls. It now fills in as wall; nothing bought.
func test_a_notch_between_walls_fills_in_as_wall() -> void:
	_cash = 5000
	var grid: SimGrid = _sim.world.grid
	for rect: Array[Vector2i] in [_rect(1, -2, 2, 2), _rect(1, -3, 5, 1), _rect(7, -3, 2, 3)]:
		assert_true(_editor.apply_floor(rect, true), _editor.last_check.why)
	for cell: Vector2i in [Vector2i(4, -1), Vector2i(5, -1)]:
		assert_eq(grid.terrain(cell), SimGrid.Terrain.WALL, "%s fills in" % cell)
		assert_false(_editor.is_bought(cell))
	assert_eq(_editor.bought_floor().size(), 4 + 5 + 6)
	assert_eq(_cash, 5000 - 15 * 15, "only bought cells are paid for")
	assert_eq(_enclosed_outside(grid), [] as Array[Vector2i])
	# Selling the floor back opens the notch to the outside again.
	assert_true(_editor.apply_floor(_rect(7, -3, 2, 3), false), _editor.last_check.why)
	assert_eq(_enclosed_outside(grid), [] as Array[Vector2i])
	assert_eq(grid.terrain(Vector2i(5, -1)), SimGrid.Terrain.OUTSIDE)


## Random add/remove drags never leave an OUTSIDE cell enclosed by walls.
func test_random_floor_edits_never_leave_enclosed_voids() -> void:
	_cash = 1000000
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var grid: SimGrid = _sim.world.grid
	for seed_value: int in [5, 11]:
		rng.seed = seed_value
		for op: int in range(150):
			var rect: Array[Vector2i] = _rect(rng.randi_range(-2, 15), rng.randi_range(-4, 10),
				rng.randi_range(1, 4), rng.randi_range(1, 4))
			_editor.apply_floor(rect, rng.randf() < 0.65)
			var enclosed: Array[Vector2i] = _enclosed_outside(grid)
			if not enclosed.is_empty():
				fail("seed %d op %d leaves %s enclosed" % [seed_value, op, enclosed])
				return


## OUTSIDE cells that cannot reach beyond the grid through OUTSIDE cells.
func _enclosed_outside(grid: SimGrid) -> Array[Vector2i]:
	var area: Rect2i = grid.bounds
	var open: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in grid.cells():
		var edge: bool = cell.x == area.position.x or cell.y == area.position.y \
			or cell.x == area.end.x - 1 or cell.y == area.end.y - 1
		if edge and grid.terrain(cell) == SimGrid.Terrain.OUTSIDE:
			open[cell] = true
			frontier.append(cell)
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for side: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var near: Vector2i = cell + side
				if grid.in_bounds(near) and not open.has(near) and grid.terrain(near) == SimGrid.Terrain.OUTSIDE:
					open[near] = true
					next.append(near)
		frontier = next
	var out: Array[Vector2i] = []
	for cell: Vector2i in grid.cells():
		if grid.terrain(cell) == SimGrid.Terrain.OUTSIDE and not open.has(cell):
			out.append(cell)
	return out


func test_an_l_shaped_building_opens_its_inner_corner() -> void:
	var grid: SimGrid = _sim.world.grid
	_cash = 5000
	assert_true(_editor.apply_floor(_rect(14, 0, 1, 10), true), _editor.last_check.why)
	assert_eq(grid.terrain(Vector2i(13, 0)), SimGrid.Terrain.WALL, "the corner waits for floor beside it")
	assert_true(_editor.apply_floor(_rect(1, -3, 14, 3), true), _editor.last_check.why)
	for cell: Vector2i in [Vector2i(13, 0), Vector2i(13, 5), Vector2i(6, 0), Vector2i(14, -3)]:
		assert_eq(grid.terrain(cell), SimGrid.Terrain.FLOOR, "%s" % cell)
	# (13, 4) ends the kitchen divider: authored interior walls never open.
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(0, -2), Vector2i(0, -4), Vector2i(15, -4), Vector2i(15, 4), Vector2i(12, 4), Vector2i(13, 4)]:
		assert_eq(grid.terrain(cell), SimGrid.Terrain.WALL, "%s" % cell)
	assert_false(grid.find_path(Vector2i(7, 11), Vector2i(1, -3)).is_empty())
	assert_eq(_cash, 5000 - (10 + 42) * 15)


func test_furniture_walls_and_windows_keep_their_places() -> void:
	var grid: SimGrid = _sim.world.grid
	var walls: Dictionary[Vector3i, int] = {
		Vector3i(13, 7, SimGrid.EDGE_WEST): SimGrid.Segment.WINDOW,  # outer face, becomes interior
		Vector3i(13, 5, SimGrid.EDGE_WEST): SimGrid.Segment.WINDOW,  # outer face, buried by the wing's wall
		Vector3i(9, 6, SimGrid.EDGE_WEST): SimGrid.Segment.WALL,
	}
	assert_true(_editor.apply_segments(walls), _editor.last_check.why)
	var before: Array[Array] = []
	for placed: PlacedItem in grid.items():
		before.append([placed.id, placed.origin, placed.quarter_turns, placed.cells.duplicate()])
	_cash = 1000
	var check: EditCheck = _editor.check_floor(_rect(14, 6, 1, 4), true)
	assert_true(check.ok, check.why)
	assert_eq(check.changes, {Vector3i(13, 5, SimGrid.EDGE_WEST): SimGrid.Segment.NONE} as Dictionary[Vector3i, int],
		"a window that no longer faces outside comes down")
	assert_eq(check.refund, 10)
	assert_true(_editor.apply_floor(_rect(14, 6, 1, 4), true))
	assert_eq(_cash, 1000 - 4 * 15 + 10)
	assert_true(_editor.apply_floor(_rect(1, -2, 4, 2), true), _editor.last_check.why)
	assert_true(_editor.apply_floor(_rect(-1, 2, 1, 7), true), _editor.last_check.why)
	var after: Array[Array] = []
	for placed: PlacedItem in grid.items():
		after.append([placed.id, placed.origin, placed.quarter_turns, placed.cells.duplicate()])
	assert_eq(after, before, "items keep ids, origins and cells")
	assert_eq(grid.segment(Vector3i(9, 6, SimGrid.EDGE_WEST)), SimGrid.Segment.WALL)
	var inner: Vector3i = Vector3i(13, 7, SimGrid.EDGE_WEST)
	assert_eq(grid.segment(inner), SimGrid.Segment.WINDOW, "the outer window is now an interior window")
	assert_true(WallRules.is_interior(grid, inner))
	assert_false(grid.walkable_neighbours(Vector2i(12, 7)).has(Vector2i(13, 7)), "and blocks like one")
	assert_false(grid.find_path(Vector2i(12, 7), Vector2i(13, 7)).is_empty(), "people go round it")
	assert_eq(_editor.next_segment(inner, SimGrid.Segment.WALL), SimGrid.Segment.WALL, "it cycles as interior")
	# No wall is added along the old outline: the room just opens up.
	assert_eq(grid.segment_edges().size(), 2)
	assert_eq(_sim.staff_spawns[&"cook"], Vector2i(6, 2))


func test_shrinking_refunds_and_refuses_cut_offs() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_editor.apply_floor(_rect(1, -3, 12, 3), true))
	# A turned table in the new back room: its seats are at (5, -3) and (5, 0).
	assert_true(_editor.buy(&"table_2", Vector2i(5, -2), 1), _editor.last_check.why)
	assert_eq(grid.item_at(Vector2i(5, -2)).seat_cells, [Vector2i(5, -3), Vector2i(5, 0)] as Array[Vector2i])
	_cash = 1000
	_entries.clear()
	assert_eq(_editor.check_floor(_rect(1, -3, 12, 1), false).why, WallRules.CUT_SEAT, "the table's seat needs that floor")
	assert_eq(_editor.check_floor(_rect(8, -2, 1, 1), false).why, ShopFootprint.LEAVES_GAP)
	assert_eq(_editor.check_floor(_rect(1, -2, 12, 1), false).why, ShopFootprint.SPLITS)
	assert_eq(_editor.check_floor(_rect(10, 5, 2, 2), false).why, ShopFootprint.ONLY_BOUGHT)
	assert_eq(_editor.check_floor(_rect(1, -3, 12, 3), false).why, ShopFootprint.HAS_FURNITURE)
	_editor.set_owner_level(5)
	assert_true(_editor.buy(&"potted_plant", Vector2i(12, -3)), _editor.last_check.why)
	_cash = 1000
	assert_eq(_editor.check_floor(_rect(9, -3, 4, 1), false).why, ShopFootprint.HAS_FURNITURE)
	assert_eq(_cash, 1000, "refusals change no books")
	# Peeling three empty back cells refunds half of $15 per cell.
	var check: EditCheck = _editor.check_floor(_rect(9, -3, 3, 1), false)
	assert_true(check.ok, check.why)
	assert_eq(check.refund, 3 * 7)
	assert_eq(check.cost, 0)
	assert_true(_editor.apply_floor(_rect(9, -3, 3, 1), false))
	assert_eq(_cash, 1021)
	assert_eq(grid.terrain(Vector2i(10, -3)), SimGrid.Terrain.WALL, "the wall moves back in")
	assert_eq(grid.terrain(Vector2i(10, -4)), SimGrid.Terrain.OUTSIDE)
	assert_eq(_editor.bought_floor().size(), 33)


func test_removing_all_bought_floor_restores_the_shell() -> void:
	var grid: SimGrid = _sim.world.grid
	var start: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	assert_true(_editor.apply_floor(_rect(1, -3, 12, 3), true), _editor.last_check.why)
	assert_eq(grid.terrain(Vector2i(5, 0)), SimGrid.Terrain.FLOOR)
	assert_true(_editor.apply_floor(_rect(1, -3, 12, 3), false), _editor.last_check.why)
	for cell: Vector2i in grid.cells():
		assert_eq(grid.terrain(cell), start.terrain(cell) if start.in_bounds(cell) else SimGrid.Terrain.OUTSIDE, "%s" % cell)
	assert_eq(_cash, 1000 - 36 * 15 + 36 * 7)


func test_shrink_refuses_to_shut_in_staff_or_stations() -> void:
	assert_true(_editor.apply_floor(_rect(1, -3, 12, 3), true))
	# Move the stove into the back room: its work spot is on the back row.
	var stove: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"stove")[0]
	assert_true(_editor.move(stove.id, Vector2i(5, -2), 0), _editor.last_check.why)
	assert_eq(stove.work_cells, [Vector2i(5, -3)] as Array[Vector2i])
	assert_eq(_editor.check_floor(_rect(1, -3, 12, 1), false).why, WallRules.CUT_STATION)
	assert_true(_editor.move(stove.id, Vector2i(7, 1), 2), _editor.last_check.why)
	assert_true(_editor.check_floor(_rect(1, -3, 12, 1), false).ok)
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent:
			agent.cell = Vector2i(3, -3)
			break
	assert_eq(_editor.check_floor(_rect(1, -3, 12, 1), false).why, WallRules.CUT_PERSON)


func test_floor_edits_are_closed_only() -> void:
	assert_true(_sim.world.clock.start_service())
	assert_eq(_editor.check_floor(_rect(14, 5, 1, 5), true).why, ShopFootprint.FLOOR_CLOSED)
	assert_false(_editor.apply_floor(_rect(14, 5, 1, 5), true))
	assert_eq(_cash, 1000)
	assert_eq(_sim.world.grid.terrain(Vector2i(13, 5)), SimGrid.Terrain.WALL)


func test_cash_shortage_refuses() -> void:
	_cash = 50
	assert_false(_editor.check_floor(_rect(14, 5, 1, 5), true).ok)
	assert_false(_editor.apply_floor(_rect(14, 5, 1, 5), true))
	assert_eq(_cash, 50)


func test_snapshot_round_trip_keeps_the_footprint() -> void:
	_cash = 5000
	assert_true(_editor.apply_floor(_rect(14, 0, 1, 10), true))
	assert_true(_editor.apply_floor(_rect(8, -3, 7, 3), true), _editor.last_check.why)
	assert_true(_editor.apply_floor(_rect(-1, 2, 1, 6), true), _editor.last_check.why)
	assert_true(_editor.buy(&"table_2", Vector2i(10, -2)), _editor.last_check.why)
	assert_true(_editor.apply_segments({Vector3i(15, 3, SimGrid.EDGE_WEST): SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]),
		_editor.last_check.why)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	assert_eq(int(snapshot["version"]), 3)
	assert_eq((snapshot["floor"] as Array).size(), 10 + 21 + 6)
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	assert_eq(layout.floor_cells, _editor.bought_floor())
	var rebuilt: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, true, true)
	assert_eq(errors, [] as Array[String])
	var live: SimGrid = _sim.world.grid
	var grid: SimGrid = rebuilt.world.grid
	assert_eq(grid.bounds, live.bounds)
	for cell: Vector2i in live.cells():
		assert_eq(grid.terrain(cell), live.terrain(cell), "%s" % cell)
	assert_eq(grid.segment_edges(), live.segment_edges())
	assert_eq(grid.items().size(), live.items().size())
	for index: int in range(live.items().size()):
		assert_eq(grid.items()[index].origin, live.items()[index].origin)
	var copy: ShopEditor = ShopEditor.new(rebuilt, _content, ShopEditBooks.new(_can_spend, _record_cash), layout)
	assert_eq(copy.bought_floor(), _editor.bought_floor(), "the restored editor knows what was bought")
	assert_eq(copy.to_dict(), _editor.to_dict())


## An interior wall with a doorway splits the dining room; the east wing is
## bought behind it. After a save and load the wall still stands, the old
## outer face beside the wing has opened (no segment there), and guests reach
## the wing only through the doorway.
func test_a_walled_shop_still_loads_and_paths_after_expanding() -> void:
	var divider: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 10):
		divider[Vector3i(9, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.WALL
	divider[Vector3i(9, 8, SimGrid.EDGE_WEST)] = SimGrid.Segment.DOORWAY
	assert_true(_editor.apply_segments(divider), _editor.last_check.why)
	assert_true(_editor.apply_floor(_rect(14, 5, 1, 5), true), _editor.last_check.why)
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(JSON.parse_string(JSON.stringify(_editor.to_dict())), LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	var rebuilt: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, true, true)
	assert_eq(errors, [] as Array[String])
	var grid: SimGrid = rebuilt.world.grid
	for edge: Vector3i in divider:
		assert_eq(grid.segment(edge), divider[edge] as SimGrid.Segment)
	var opened: Vector3i = Vector3i(13, 7, SimGrid.EDGE_WEST)
	assert_true(WallRules.is_interior(grid, opened), "the old outer face is now inside")
	assert_eq(grid.segment(opened), SimGrid.Segment.NONE, "and open: no wall was added on the old outline")
	assert_true(grid.walkable_neighbours(Vector2i(12, 7)).has(Vector2i(13, 7)))
	var path: Array[Vector2i] = grid.find_path(Vector2i(6, 11), Vector2i(14, 7))
	assert_false(path.is_empty(), "guests reach the wing")
	assert_true(path.has(Vector2i(8, 8)) and path.has(Vector2i(9, 8)), "through the doorway")
	for index: int in range(1, path.size()):
		assert_false(grid.edge_blocked(path[index - 1], path[index]), "never through the wall")


func test_older_snapshots_load_as_the_starting_shell() -> void:
	for version: int in [1, 2]:
		var legacy: Dictionary = _editor.to_dict()
		legacy["version"] = version
		legacy.erase("floor")
		if version == 1:
			legacy.erase("walls")
		var errors: Array[String] = []
		var layout: ShopLayout = ShopEditor.from_dict(legacy, LAYOUT, _content, errors)
		assert_eq(errors, [] as Array[String])
		assert_not_null(layout)
		assert_true(layout.floor_cells.is_empty())
		var rebuilt: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, true, true)
		assert_eq(errors, [] as Array[String])
		assert_eq(rebuilt.world.grid.bounds, Rect2i(0, 0, 14, 12))


func test_bad_saved_floor_is_rejected() -> void:
	var base: Dictionary = _editor.to_dict()
	for floor: Variant in ["x", [[99, 5]], [[14, 5], [14, 5]], [[15, 5]], [[14]], [[5, 5]], [[14.5, 5]], [[14, -2]]]:
		var data: Dictionary = base.duplicate(true)
		data["floor"] = floor
		var errors: Array[String] = []
		assert_null(ShopEditor.from_dict(data, LAYOUT, _content, errors), str(floor))
		assert_false(errors.is_empty())
	var missing: Dictionary = base.duplicate(true)
	missing.erase("floor")
	assert_null(ShopEditor.from_dict(missing, LAYOUT, _content, [] as Array[String]), "version 3 needs floor")
	var outside: Dictionary = base.duplicate(true)
	outside["items"].append({"def_id": "potted_plant", "origin": [14, 6], "quarter_turns": 0})
	assert_null(ShopEditor.from_dict(outside, LAYOUT, _content, [] as Array[String]), "items need bought floor")


func _rect(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in range(y, y + h):
		for column: int in range(x, x + w):
			out.append(Vector2i(column, row))
	return out


func _can_spend(amount: int) -> bool:
	return amount <= _cash


func _record_cash(amount: int, category: StringName) -> void:
	_cash += amount
	_entries.append({"amount": amount, "category": category})
