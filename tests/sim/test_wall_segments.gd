extends TestCase
## FK-070: wall segments on cell edges, their pathing, rules, prices and saves.

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
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash))


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null


# --- Grid and pathing ------------------------------------------------------

func test_edge_keys_round_trip() -> void:
	var edge: Vector3i = SimGrid.edge_between(Vector2i(2, 3), Vector2i(3, 3))
	assert_eq(edge, Vector3i(3, 3, SimGrid.EDGE_WEST))
	assert_eq(SimGrid.edge_between(Vector2i(3, 3), Vector2i(2, 3)), edge)
	assert_eq(SimGrid.edge_cells(edge), [Vector2i(2, 3), Vector2i(3, 3)] as Array[Vector2i])
	var north: Vector3i = SimGrid.edge_between(Vector2i(4, 1), Vector2i(4, 2))
	assert_eq(north, Vector3i(4, 2, SimGrid.EDGE_NORTH))
	assert_eq(SimGrid.edge_from_vertices(Vector2i(4, 2), Vector2i(5, 2)), north)
	assert_eq(SimGrid.edge_from_vertices(Vector2i(3, 4), Vector2i(3, 3)), edge)
	assert_eq(SimGrid.edge_between(Vector2i(0, 0), Vector2i(1, 1)), SimGrid.NO_EDGE)


func test_wall_and_window_block_their_edge_but_a_doorway_does_not() -> void:
	# A 5x3 room split down the middle (x = 2 | 3) by a three-segment line.
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([".....", ".....", "....."]))
	var line: Array[Vector3i] = []
	for y: int in 3:
		line.append(Vector3i(3, y, SimGrid.EDGE_WEST))
	for kind: SimGrid.Segment in [SimGrid.Segment.WALL, SimGrid.Segment.WINDOW]:
		for edge: Vector3i in line:
			assert_true(grid.set_segment(edge, kind))
		assert_true(grid.find_path(Vector2i(0, 1), Vector2i(4, 1)).is_empty(), "segment %d blocks" % kind)
		assert_false(grid.walkable_neighbours(Vector2i(2, 1)).has(Vector2i(3, 1)))
	assert_true(grid.set_segment(line[1], SimGrid.Segment.DOORWAY))
	var path: Array[Vector2i] = grid.find_path(Vector2i(0, 1), Vector2i(4, 1))
	assert_false(path.is_empty(), "a doorway lets people through")
	assert_true(path.has(Vector2i(2, 1)) and path.has(Vector2i(3, 1)), "through the doorway itself")
	for index: int in range(1, path.size()):
		assert_false(grid.edge_blocked(path[index - 1], path[index]))
	assert_true(grid.set_segment(line[1], SimGrid.Segment.NONE))
	assert_eq(grid.find_path(Vector2i(0, 1), Vector2i(4, 1)).size(), 5, "an empty edge is a gap")
	for edge: Vector3i in line:
		grid.set_segment(edge, SimGrid.Segment.NONE)
	assert_false(grid.has_segments())
	assert_eq(grid.find_path(Vector2i(0, 1), Vector2i(4, 1)).size(), 5)


func test_no_diagonal_past_a_segment_end_or_doorway_post() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["...", "...", "..."]))
	# A single doorway segment between (0,0) and (1,0): its end post stands at
	# vertex (1,1), so (0,0) -> (1,1) and (1,0) -> (0,1) may not cut past it.
	grid.set_segment(Vector3i(1, 0, SimGrid.EDGE_WEST), SimGrid.Segment.DOORWAY)
	assert_false(grid.walkable_neighbours(Vector2i(0, 0)).has(Vector2i(1, 1)))
	assert_false(grid.walkable_neighbours(Vector2i(1, 0)).has(Vector2i(0, 1)))
	assert_true(grid.walkable_neighbours(Vector2i(0, 0)).has(Vector2i(1, 0)), "the doorway itself is open")
	var path: Array[Vector2i] = grid.find_path(Vector2i(0, 0), Vector2i(1, 1))
	assert_eq(path.size(), 3, "goes round the post orthogonally")


func test_signal_reports_both_cells_and_change_only() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["...", "..."]))
	var seen: Array = []
	var record: Callable = func(cells: Array[Vector2i]) -> void: seen.append(cells)
	grid.cells_changed.connect(record)
	assert_true(grid.set_segment(Vector3i(1, 1, SimGrid.EDGE_NORTH), SimGrid.Segment.WALL))
	assert_true(grid.set_segment(Vector3i(1, 1, SimGrid.EDGE_NORTH), SimGrid.Segment.WALL))
	assert_eq(seen.size(), 1)
	assert_eq(seen[0], [Vector2i(1, 0), Vector2i(1, 1)] as Array[Vector2i])
	assert_false(grid.set_segment(Vector3i(0, 0, SimGrid.EDGE_WEST), SimGrid.Segment.WALL), "grid border")
	assert_false(grid.set_segment(Vector3i(1, 1, 7), SimGrid.Segment.WALL))
	grid.cells_changed.disconnect(record)


func test_a_run_changes_the_grid_with_one_signal() -> void:
	var grid: SimGrid = _sim.world.grid
	var seen: Array = []
	var record: Callable = func(cells: Array[Vector2i]) -> void: seen.append(cells)
	grid.cells_changed.connect(record)
	var run: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 9):
		run[_edge(9, y, 0)] = SimGrid.Segment.WALL
	assert_true(_editor.apply_segments(run))
	assert_eq(seen.size(), 1, "one rebuild for a whole dragged run")
	assert_eq((seen[0] as Array).size(), 8)
	grid.cells_changed.disconnect(record)


func test_walkers_never_step_through_a_new_wall() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["....", "....", "...."]))
	var world: SimWorld = SimWorld.new(grid)
	var walker: SimAgent = SimAgent.new()
	walker.cell = Vector2i(0, 0)
	world.add_agent(walker)
	assert_true(walker.set_destination(grid, Vector2i(1, 1)))
	assert_eq(walker.path[1], Vector2i(1, 1), "a diagonal first step")
	walker.move_progress = 0.5
	# A wall end appears beside the cell being left.
	grid.set_segment(Vector3i(1, 0, SimGrid.EDGE_WEST), SimGrid.Segment.WALL)
	assert_true(walker.needs_repath, "the cell being left counts as on the path")
	assert_eq(walker.step_move(world), SimAgent.MoveResult.BLOCKED)
	assert_false(grid.step_open(Vector2i(0, 0), Vector2i(1, 1)))


func test_buried_escape_does_not_jump_a_wall() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["...", "...", "..."]))
	grid.place(Vector2i.ONE, Vector2i(0, 1), 0, true)
	for y: int in 3:
		grid.set_segment(Vector3i(1, y, SimGrid.EDGE_WEST), SimGrid.Segment.WALL)
	grid.set_segment(Vector3i(0, 1, SimGrid.EDGE_NORTH), SimGrid.Segment.WALL)
	# Buried at (0, 1): (0, 0) is behind a wall, (0, 2) is open.
	var path: Array[Vector2i] = grid.find_path(Vector2i(0, 1), Vector2i(0, 2))
	assert_eq(path, [Vector2i(0, 1), Vector2i(0, 2)] as Array[Vector2i])
	assert_true(grid.find_path(Vector2i(0, 1), Vector2i(0, 0)).is_empty())


func test_furniture_cannot_straddle_a_segment_or_face_a_wall() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["......", "......", "......"]))
	grid.set_segment(Vector3i(2, 1, SimGrid.EDGE_WEST), SimGrid.Segment.DOORWAY)
	assert_eq(grid.can_place(Vector2i(2, 1), Vector2i(1, 1), 0), SimGrid.PlaceResult.WALL_IN_WAY)
	assert_eq(grid.can_place(Vector2i(2, 1), Vector2i(2, 1), 0), SimGrid.PlaceResult.OK)
	var stove: ItemDef = _content.item(&"stove")
	# Turned twice, the stove at (4..5, 0) works from (5, 1) below it.
	grid.set_segment(Vector3i(5, 1, SimGrid.EDGE_NORTH), SimGrid.Segment.WALL)
	var result: SimGrid.PlaceResult = grid.can_place_def(stove, Vector2i(4, 0), 2)
	assert_eq(result, SimGrid.PlaceResult.WALL_IN_WAY)
	assert_eq(ShopEditor.placement_reason(result), "A wall is in the way")


func test_no_wall_paths_match_the_plain_engine_search() -> void:
	var grid: SimGrid = ShopBuilder.build(LAYOUT, _content, [] as Array[String]).grid
	var plain: AStarGrid2D = AStarGrid2D.new()
	plain.region = Rect2i(Vector2i.ZERO, grid.size)
	plain.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	plain.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	plain.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	plain.update()
	for y: int in grid.size.y:
		for x: int in grid.size.x:
			plain.set_point_solid(Vector2i(x, y), not grid.is_walkable(Vector2i(x, y)))
	for goal: Vector2i in [Vector2i(1, 2), Vector2i(12, 9), Vector2i(6, 3), Vector2i(9, 7)]:
		assert_eq(grid.find_path(Vector2i(6, 11), goal), plain.get_id_path(Vector2i(6, 11), goal))


# --- Editor rules ----------------------------------------------------------

func test_edits_are_closed_only() -> void:
	var changes: Dictionary[Vector3i, int] = {_edge(9, 5, 0): SimGrid.Segment.WALL}
	for phase: SimClock.Phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		_sim.world.clock.phase = phase
		var check: EditCheck = _editor.check_segments(changes)
		assert_false(check.ok)
		assert_eq(check.why, ShopEditor.WALLS_CLOSED)
		assert_false(_editor.apply_segments(changes))
		assert_false(_sim.world.grid.has_segments())
	assert_eq(_entries.size(), 0)
	_sim.world.clock.phase = SimClock.Phase.CLOSED
	assert_true(_editor.apply_segments(changes))


func test_prices_and_refunds_go_through_the_ledger() -> void:
	var run: Array[Vector3i] = [_edge(9, 5, 0), _edge(9, 6, 0), _edge(9, 7, 0)]
	var check: EditCheck = _editor.check_segments(_editor.run_changes(run, SimGrid.Segment.WALL))
	assert_true(check.ok, check.why)
	assert_eq(check.cost, 30)
	assert_true(_editor.apply_segments(_editor.run_changes(run, SimGrid.Segment.WALL)))
	assert_eq(_entries, [{"amount": -30, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_eq(_cash, 970)
	# Re-dragging over existing walls charges nothing new.
	assert_true(_editor.run_changes(run, SimGrid.Segment.WALL).is_empty())
	# Click cycle: wall -> doorway refunds half the wall and buys a doorway.
	_entries.clear()
	assert_eq(_editor.next_segment(run[1], SimGrid.Segment.WALL), SimGrid.Segment.DOORWAY)
	assert_true(_editor.apply_segments({run[1]: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	assert_eq(_entries, [{"amount": 5, "category": Ledger.UPGRADES},
		{"amount": -15, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_eq(_editor.next_segment(run[1], SimGrid.Segment.WALL), SimGrid.Segment.WINDOW)
	_entries.clear()
	assert_true(_editor.apply_segments({run[1]: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]))
	assert_eq(_entries, [{"amount": 7, "category": Ledger.UPGRADES},
		{"amount": -20, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_eq(_editor.next_segment(run[1], SimGrid.Segment.WALL), SimGrid.Segment.WALL)
	# Removing sells at half price.
	_entries.clear()
	assert_true(_editor.apply_segments({run[1]: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]))
	assert_eq(_entries, [{"amount": 10, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_eq(_sim.world.grid.segment(run[1]), SimGrid.Segment.NONE)


func test_prices_come_from_data() -> void:
	assert_eq(_content.wall_kind(&"wall").price, 10)
	assert_eq(_content.wall_kind(&"doorway").price, 15)
	assert_eq(_content.wall_kind(&"window").price, 20)
	var ids: Array[StringName] = []
	for definition: WallKindDef in _content.wall_kinds():
		ids.append(definition.id)
	assert_eq(ids, [&"wall", &"doorway", &"window"] as Array[StringName])


func test_wall_definitions_are_validated() -> void:
	var first: WallKindDef = WallKindDef.new()
	first.id = &"wall"
	first.display_name = "Wall"
	first.segment = SimGrid.Segment.WALL
	var twin: WallKindDef = first.duplicate() as WallKindDef
	twin.id = &"other"
	twin.price = -1
	var errors: PackedStringArray = ContentDB.validate_wall_kinds([first, twin] as Array[WallKindDef])
	assert_eq(errors.size(), 2, str(errors))
	var blank: WallKindDef = WallKindDef.new()
	blank.id = &"blank"
	assert_eq(ContentDB.validate_wall_kinds([blank] as Array[WallKindDef]).size(), 2)


func test_cash_shortage_refuses_without_side_effects() -> void:
	_cash = 5
	var check: EditCheck = _editor.check_segments({_edge(9, 5, 0): SimGrid.Segment.WALL} as Dictionary[Vector3i, int])
	assert_false(check.ok)
	assert_eq(check.why, ShopEditBooks.CASH_REFUSAL)
	assert_false(_sim.world.grid.has_segments())


func test_cut_off_edits_are_refused_with_readable_reasons() -> void:
	var grid: SimGrid = _sim.world.grid
	# Close the kitchen door (x = 7 in the divider row): the kitchen is cut off.
	var kitchen: Dictionary[Vector3i, int] = {_edge(7, 5, 1): SimGrid.Segment.WALL}
	var check: EditCheck = _editor.check_segments(kitchen)
	assert_false(check.ok)
	assert_eq(check.why, WallRules.CUT_SINK, "the sink is the first kitchen target named")
	# Box in the two cells inside the street door: the door is cut off.
	var door: Dictionary[Vector3i, int] = {_edge(6, 9, 0): SimGrid.Segment.WALL,
		_edge(8, 9, 0): SimGrid.Segment.WALL}
	for x: int in [6, 7]:
		door[_edge(x, 9, 1)] = SimGrid.Segment.WALL
	check = _editor.check_segments(door)
	assert_false(check.ok)
	assert_eq(check.why, WallRules.CUT_DOOR)
	# Wall off the east table completely: its seats are cut off.
	var corner: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 10):
		corner[_edge(9, y, 0)] = SimGrid.Segment.WALL
	check = _editor.check_segments(corner)
	assert_false(check.ok)
	assert_eq(check.why, WallRules.CUT_SEAT)
	# With a doorway in the run the same corner is fine.
	corner[_edge(9, 8, 0)] = SimGrid.Segment.DOORWAY
	check = _editor.check_segments(corner)
	assert_true(check.ok, check.why)
	assert_eq(check.cost, 4 * 10 + 15)
	assert_false(grid.has_segments(), "checks never change the shop")


func test_walls_cannot_cut_furniture_or_door_or_leave_the_floor() -> void:
	var problem: Callable = func(edge: Vector3i, kind: SimGrid.Segment) -> String:
		return _editor.check_segments({edge: kind} as Dictionary[Vector3i, int]).why
	# Through the middle of the 2x2 table at (2, 6).
	assert_eq(problem.call(_edge(3, 6, 0), SimGrid.Segment.DOORWAY), WallRules.THROUGH_FURNITURE)
	# Between the stove (7..8, 1) and its work cell (8, 2) below it.
	assert_eq(problem.call(_edge(8, 2, 1), SimGrid.Segment.WALL), WallRules.BLOCKS_ACCESS)
	# The street door opening and its threshold stay fixed.
	assert_eq(problem.call(_edge(7, 10, 0), SimGrid.Segment.WALL), WallRules.DOOR_FIXED)
	assert_eq(problem.call(_edge(6, 10, 1), SimGrid.Segment.WALL), WallRules.DOOR_FIXED)
	# Inside the kitchen divider wall, or out on the street.
	assert_eq(problem.call(_edge(2, 4, 0), SimGrid.Segment.WALL), WallRules.NOT_INSIDE)
	assert_eq(problem.call(_edge(1, 11, 0), SimGrid.Segment.WALL), WallRules.NOT_INSIDE)
	# Removing nothing.
	assert_eq(problem.call(_edge(9, 6, 0), SimGrid.Segment.NONE), "Nothing to change here")


## Regression (review): furniture blocking a doorway must not let a later wall
## edit seal the room for good once that furniture is sold.
func test_temporary_furniture_cannot_hide_a_permanent_seal() -> void:
	var room: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 10):
		room[_edge(9, y, 0)] = SimGrid.Segment.WALL
	room[_edge(9, 9, 0)] = SimGrid.Segment.DOORWAY
	assert_true(_editor.apply_segments(room), _editor.last_check.why)
	_editor.set_owner_level(6)
	assert_true(_editor.buy(&"potted_plant", Vector2i(9, 9)), _editor.last_check.why)
	assert_false(_editor.last_check.unreachable.is_empty(), "the plant only warns")
	var close: Dictionary[Vector3i, int] = {_edge(9, 9, 0): SimGrid.Segment.WALL}
	var check: EditCheck = _editor.check_segments(close)
	assert_false(check.ok, "walls-only, the corner table would be sealed in")
	assert_eq(check.why, WallRules.CUT_SEAT)
	assert_false(_editor.apply_segments(close))
	assert_eq(_sim.world.grid.segment(_edge(9, 9, 0)), SimGrid.Segment.DOORWAY)


## The cosy corner: a table may stand flush against an interior wall, like
## against the shell. Its seat across the wall is dropped; open seats remain.
func test_tables_sit_flush_against_interior_walls() -> void:
	var grid: SimGrid = _sim.world.grid
	var east: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[2]
	assert_eq(east.seat_cells, [Vector2i(9, 7), Vector2i(12, 7)] as Array[Vector2i])
	var flush: Dictionary[Vector3i, int] = {_edge(10, 6, 0): SimGrid.Segment.WALL,
		_edge(10, 7, 0): SimGrid.Segment.WALL}
	var check: EditCheck = _editor.check_segments(flush)
	assert_true(check.ok, check.why)
	assert_true(_editor.apply_segments(flush))
	assert_eq(east.seat_cells, [Vector2i(12, 7)] as Array[Vector2i], "the walled seat is dropped")
	# A new table can be bought into the corner too, and chairs tucked around it.
	var corner: Dictionary[Vector3i, int] = {_edge(5, 8, 0): SimGrid.Segment.WALL,
		_edge(5, 9, 0): SimGrid.Segment.WALL}
	assert_true(_editor.apply_segments(corner), _editor.last_check.why)
	assert_true(_editor.buy(&"table_2", Vector2i(5, 8)), _editor.last_check.why)
	var tucked: PlacedItem = grid.item_at(Vector2i(5, 8))
	assert_eq(tucked.seat_cells, [Vector2i(7, 9)] as Array[Vector2i])
	assert_true(_editor.buy(&"chair", Vector2i(10, 5), 2), _editor.last_check.why)
	assert_true(east.seat_cells.has(Vector2i(10, 5)), "a chair on an open side links")


func test_seat_cannot_be_walled_from_its_table() -> void:
	assert_true(_editor.buy(&"chair", Vector2i(3, 5), 2), _editor.last_check.why)
	# The chair at (3, 5) faces the table cell (3, 6) below it.
	var check: EditCheck = _editor.check_segments({_edge(3, 6, 1): SimGrid.Segment.WALL} as Dictionary[Vector3i, int])
	assert_false(check.ok)
	assert_eq(check.why, DiningSeats.WALLED_OFF)


func test_outer_windows_follow_the_shell_rules() -> void:
	var grid: SimGrid = _sim.world.grid
	var east: Vector3i = _edge(13, 6, 0)
	assert_eq(WallRules.outer_side(grid, east), Vector2i(1, 0))
	assert_eq(_editor.check_segments({east: SimGrid.Segment.WALL} as Dictionary[Vector3i, int]).why,
		WallRules.OUTER_WINDOW_ONLY)
	assert_eq(_editor.next_segment(east, SimGrid.Segment.WALL), SimGrid.Segment.WINDOW)
	assert_true(_editor.apply_segments({east: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]))
	assert_eq(_cash, 980)
	assert_eq(_editor.next_segment(east, SimGrid.Segment.WALL), SimGrid.Segment.NONE)
	# Outer windows never change paths.
	assert_true(grid.find_path(Vector2i(6, 11), Vector2i(12, 6)).size() > 0)
	# Every east face but one may become a window; the last stays solid.
	var faces: Array[Vector3i] = []
	for y: int in range(grid.size.y):
		var edge: Vector3i = _edge(13, y, 0)
		if WallRules.outer_side(grid, edge) != Vector2i.ZERO and edge != east:
			faces.append(edge)
	assert_eq(faces.size(), 7, "east faces at y 1-3 and 5-9")
	var all_but_one: Dictionary[Vector3i, int] = {}
	for index: int in range(faces.size() - 1):
		all_but_one[faces[index]] = SimGrid.Segment.WINDOW
	assert_true(_editor.check_segments(all_but_one).ok)
	all_but_one[faces[faces.size() - 1]] = SimGrid.Segment.WINDOW
	assert_eq(_editor.check_segments(all_but_one).why, WallRules.KEEP_SOLID_SIDE)
	# The kitchen divider is not part of the outer shell.
	assert_eq(WallRules.outer_side(grid, _edge(2, 5, 1)), Vector2i.ZERO)
	# A shell window's edge becomes interior when the wall behind turns to floor
	# (a future floor expansion): it then blocks paths like any window.
	assert_true(grid.set_terrain(Vector2i(13, 6), SimGrid.Terrain.FLOOR))
	assert_true(WallRules.is_interior(grid, east))
	assert_false(grid.walkable_neighbours(Vector2i(12, 6)).has(Vector2i(13, 6)))


# --- Saves -------------------------------------------------------------------

func test_back_door_opens_shell_without_changing_customer_entries() -> void:
	var grid: SimGrid = _sim.world.grid
	var east: Vector3i = _edge(13, 6, 0)
	var entries: Array[Vector2i] = grid.entries()
	assert_false(grid.is_walkable(Vector2i(13, 6)))
	assert_eq(_editor.next_segment(east, SimGrid.Segment.DOORWAY), SimGrid.Segment.DOORWAY)
	assert_true(_editor.apply_segments({east: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]), _editor.last_check.why)
	assert_eq(_cash, 985, "same data-defined doorway price")
	assert_true(grid.is_walkable(Vector2i(13, 6)))
	assert_false(grid.find_path(Vector2i(13, 6), Vector2i(8, 8)).is_empty())
	assert_eq(grid.entries(), entries, "guests continue to use the street")
	assert_eq(WallRules.delivery_cell(grid, Vector2i(8, 8)), Vector2i(12, 6))
	assert_eq(_editor.next_segment(east, SimGrid.Segment.DOORWAY), SimGrid.Segment.NONE)
	assert_true(_editor.apply_segments({east: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]))
	assert_false(grid.is_walkable(Vector2i(13, 6)), "removing the door restores its solid shell")
	assert_eq(WallRules.delivery_cell(grid), entries[0])


func test_back_door_refuses_street_frontage_and_service_edits() -> void:
	var front: Vector3i = _edge(5, 10, 1)
	assert_eq(_editor.check_segments({front: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]).why,
		WallRules.BACK_OR_SIDE)
	_sim.world.clock.phase = SimClock.Phase.OPEN
	assert_eq(_editor.check_segments({_edge(13, 6, 0): SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]).why,
		ShopEditor.WALLS_CLOSED)
	assert_false(_sim.world.grid.has_segments())
	assert_eq(_cash, 1000)


func test_person_walks_through_back_door_before_it_can_be_removed() -> void:
	var world: SimWorld = _sim.world
	var edge: Vector3i = _edge(13, 6, 0)
	assert_true(_editor.apply_segments({edge: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	var person: SimAgent = SimAgent.new()
	person.cell = Vector2i(13, 6)
	world.add_agent(person)
	assert_eq(_editor.check_segments({edge: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]).why,
		WallRules.CUT_PERSON, "cannot restore solid shell around someone")
	assert_true(person.set_destination(world.grid, Vector2i(12, 6)))
	for tick: int in 60:
		if person.cell == Vector2i(12, 6):
			break
		person.step_move(world)
	assert_eq(person.cell, Vector2i(12, 6), "actual movement crosses the shell edge")
	assert_true(_editor.apply_segments({edge: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]))
	assert_false(world.grid.is_walkable(Vector2i(13, 6)))


func test_delivery_falls_back_when_back_door_receiving_cell_is_blocked() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_eq(WallRules.delivery_cell(grid), grid.entries()[0])
	assert_true(_editor.apply_segments({_edge(13, 6, 0): SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	assert_eq(WallRules.delivery_cell(grid), Vector2i(12, 6))
	var blocker: PlacedItem = grid.place(Vector2i.ONE, Vector2i(12, 6), 0, true)
	assert_not_null(blocker)
	assert_eq(WallRules.delivery_cell(grid), grid.entries()[0], "blocked drop spots do not strand deliveries")
	assert_true(grid.remove(blocker.id))
	assert_eq(WallRules.delivery_cell(grid), Vector2i(12, 6))
	assert_eq(WallRules.delivery_cell(grid, Vector2i(1, 0)), SimGrid.NO_CELL, "no reachable receiving route")


func test_back_door_refreshes_when_expansion_moves_the_shell() -> void:
	var grid: SimGrid = _sim.world.grid
	var east: Vector3i = _edge(13, 6, 0)
	assert_true(_editor.apply_segments({east: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	assert_true(grid.set_terrain(Vector2i(13, 6), SimGrid.Terrain.FLOOR))
	assert_true(WallRules.is_interior(grid, east))
	assert_eq(WallRules.delivery_cell(grid), grid.entries()[0], "an interior doorway is no longer a receiving entrance")
	assert_true(grid.is_walkable(Vector2i(13, 6)))
	assert_true(grid.set_terrain(Vector2i(13, 6), SimGrid.Terrain.WALL))
	assert_eq(WallRules.delivery_cell(grid), Vector2i(12, 6))
	# Losing the exterior approach makes the retained edge ineligible too.
	grid.grow_to(Rect2i(Vector2i.ZERO, Vector2i(15, 12)))
	assert_true(grid.set_terrain(Vector2i(14, 6), SimGrid.Terrain.WALL))
	assert_false(grid.is_walkable(Vector2i(13, 6)))
	assert_eq(WallRules.delivery_cell(grid), grid.entries()[0])


func test_back_door_snapshot_round_trip_keeps_receiving_route() -> void:
	assert_true(_editor.apply_segments({_edge(13, 6, 0): SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	var rebuilt: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, true, true)
	assert_eq(errors, [] as Array[String])
	assert_eq(WallRules.delivery_cell(rebuilt.world.grid), Vector2i(12, 6))
	assert_false(rebuilt.world.grid.find_path(Vector2i(13, 6), Vector2i(8, 8)).is_empty())

func test_snapshot_round_trip_keeps_segments() -> void:
	var changes: Dictionary[Vector3i, int] = {_edge(13, 6, 0): SimGrid.Segment.WINDOW}
	for y: int in range(5, 10):
		changes[_edge(9, y, 0)] = SimGrid.Segment.WALL
	changes[_edge(9, 8, 0)] = SimGrid.Segment.DOORWAY
	changes[_edge(9, 6, 0)] = SimGrid.Segment.WINDOW
	assert_true(_editor.apply_segments(changes), _editor.last_check.why)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(_editor.to_dict()))
	assert_eq(int(snapshot["version"]), 3)
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	assert_eq(layout.wall_segments.size(), 6)
	var rebuilt: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, true, true)
	assert_eq(errors, [] as Array[String])
	for edge: Vector3i in changes:
		assert_eq(rebuilt.world.grid.segment(edge), changes[edge] as SimGrid.Segment)
	assert_eq(rebuilt.world.grid.segment_edges(), _sim.world.grid.segment_edges())


func test_version_one_snapshot_loads_without_walls() -> void:
	var legacy: Dictionary = _editor.to_dict()
	legacy["version"] = 1
	legacy.erase("walls")
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(legacy, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	assert_true(layout.wall_segments.is_empty())
	var rebuilt: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, true, true)
	assert_eq(errors, [] as Array[String])
	assert_false(rebuilt.world.grid.has_segments())


func test_bad_saved_walls_are_rejected() -> void:
	var base: Dictionary = _editor.to_dict()
	for walls: Array in [
			[{"edge": [3, 6, 0], "kind": "wall"}],  # through a table
			[{"edge": [9, 6, 0], "kind": "tower"}],
			[{"edge": [9, 6], "kind": "wall"}],
			[{"edge": [99, 6, 0], "kind": "wall"}],
			[{"edge": [9, 6, 0], "kind": "wall"}, {"edge": [9, 6, 0], "kind": "window"}]]:
		var data: Dictionary = base.duplicate(true)
		data["walls"] = walls
		var errors: Array[String] = []
		assert_null(ShopEditor.from_dict(data, LAYOUT, _content, errors), str(walls))
		assert_false(errors.is_empty())
	var legacy: Dictionary = base.duplicate(true)
	legacy["version"] = 1
	legacy["walls"] = "bad"
	assert_null(ShopEditor.from_dict(legacy, LAYOUT, _content, [] as Array[String]), "bad walls fail cleanly in any version")
	var missing: Dictionary = base.duplicate(true)
	missing.erase("walls")
	assert_null(ShopEditor.from_dict(missing, LAYOUT, _content, [] as Array[String]), "version 2 needs walls")


# --- Soak --------------------------------------------------------------------

## Five real service days with the east dining corner walled off behind a
## doorway, and windows inside and out. Nobody ever crosses a wall or window,
## every day drains, and guests still use the walled-off table.
func test_five_day_soak_with_a_walled_off_dining_corner() -> void:
	var layout: ShopLayout = LAYOUT.duplicate() as ShopLayout
	var segments: Dictionary[Vector3i, StringName] = {}
	for y: int in range(5, 10):
		segments[_edge(9, y, 0)] = &"wall"
	segments[_edge(9, 8, 0)] = &"doorway"
	segments[_edge(9, 6, 0)] = &"window"
	segments[_edge(13, 7, 0)] = &"window"
	layout.wall_segments = segments
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 1000, 1)
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, _content, 4242, errors, stock)
	assert_eq(errors, [] as Array[String])
	var grid: SimGrid = sim.world.grid
	assert_eq(grid.segment_edges().size(), 6)
	sim.carry_capacity = 2
	sim.spawner.min_gap = 120
	sim.spawner.max_gap = 220
	var corner_seats: Array[Vector2i] = [Vector2i(9, 7), Vector2i(12, 7)]
	var corner_guests: int = 0
	var served: int = 0
	var crossings: int = 0
	for day: int in range(5):
		sim.start_day()
		assert_true(sim.world.clock.start_service())
		var previous: Dictionary[int, Vector2i] = {}
		var seated: Dictionary[int, bool] = {}
		for tick: int in range(7000):
			sim.advance()
			for agent: SimAgent in sim.world.agents:
				var before: Vector2i = previous.get(agent.id, agent.cell)
				if before != agent.cell and before.distance_squared_to(agent.cell) <= 2 \
						and (grid.edge_blocked(before, agent.cell) or not grid.walkable_neighbours(before).has(agent.cell)):
					if grid.is_walkable(before):
						crossings += 1
				previous[agent.id] = agent.cell
				var guest: CustomerAgent = agent as CustomerAgent
				if guest != null and corner_seats.has(guest.seat_cell) and guest.cell == guest.seat_cell:
					seated[guest.id] = true
			if sim.world.clock.phase == SimClock.Phase.CLOSED and sim.customers().is_empty():
				break
		assert_eq(sim.world.clock.phase, SimClock.Phase.CLOSED, "day %d closed" % (day + 1))
		for tick: int in range(1500):
			if sim.kitchen.is_clean() and sim.world.board.active_count() == 0:
				break
			sim.advance()
		assert_eq(sim.customers().size(), 0)
		assert_eq(sim.world.board.active_count(), 0, "day %d board drained" % (day + 1))
		assert_true(sim.kitchen.is_clean())
		for item: PlacedItem in grid.items():
			for cell: Vector2i in item.work_cells + item.seat_cells:
				assert_eq(item.reserved_by(cell), -1)
		corner_guests += seated.size()
		served += sim.served_today
		if day < 4:
			assert_true(sim.world.clock.next_day())
	assert_eq(crossings, 0, "nobody walks through a wall or window")
	assert_true(served > 0)
	assert_true(corner_guests > 0, "guests sit in the walled-off corner")
	print("WALL_SOAK served=%d corner_guests=%d" % [served, corner_guests])


func _edge(x: int, y: int, axis: int) -> Vector3i:
	return Vector3i(x, y, axis)


func _can_spend(amount: int) -> bool:
	return amount <= _cash


func _record_cash(amount: int, category: StringName) -> void:
	_cash += amount
	_entries.append({"amount": amount, "category": category})
