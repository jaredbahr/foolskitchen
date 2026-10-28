extends TestCase
## FK-101: rooms. The starter kitchen is a Kitchen room; guests never walk
## through Kitchen or Storage cells while staff walk everywhere; edits that
## would seat guests in a staff room, or leave a seat, toilet or the door
## reachable only through one, are refused; painting is free and undoable,
## saves keep the rooms and older saves infer the starter kitchen.
## Grid: the starting shell is x 0..13, y 0..10. Kitchen x 1..12, y 1..3 plus
## the divider openings (5..7, 4); the pass is at (5, 4) with sides (5, 3) and
## (5, 5). The lot lets floor go on y -3..-1 behind and x 14 beside the shop.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _cash: int = 100000


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_cash = 100000
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null


func test_starter_kitchen_is_a_kitchen_and_new_floor_is_dining() -> void:
	var grid: SimGrid = _sim.world.grid
	for cell: Vector2i in _rect(1, 1, 12, 3) + ([Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4)] as Array[Vector2i]):
		assert_eq(grid.room(cell), SimGrid.Room.KITCHEN, "%s" % cell)
		assert_true(grid.is_staff_only(cell))
	for cell: Vector2i in _rect(1, 5, 12, 6):
		if grid.terrain(cell) == SimGrid.Terrain.FLOOR:
			assert_eq(grid.room(cell), SimGrid.Room.DINING, "%s" % cell)
	assert_eq(grid.room(Vector2i(0, 0)), SimGrid.Room.DINING, "walls take no room")
	assert_true(_editor.apply_floor(_rect(14, 0, 1, 10), true), _editor.last_check.why)
	assert_eq(grid.room(Vector2i(14, 5)), SimGrid.Room.DINING)
	assert_true(_editor.check_current().ok)


func test_guest_paths_never_enter_kitchen_or_storage() -> void:
	var grid: SimGrid = _sim.world.grid
	# A corridor along the east side: from the dining room round to the kitchen's far end.
	assert_true(_editor.apply_floor(_rect(14, 0, 1, 10), true), _editor.last_check.why)
	var start: Vector2i = Vector2i(2, 9)
	var goal: Vector2i = Vector2i(13, 2)
	assert_eq(grid.room(goal), SimGrid.Room.DINING, "the opened shell cell is new dining floor")
	var staff: Array[Vector2i] = grid.find_path(start, goal)
	var crosses: bool = false
	for cell: Vector2i in staff:
		crosses = crosses or grid.is_staff_only(cell)
	assert_true(crosses, "staff take the short way through the kitchen")
	var guest: Array[Vector2i] = grid.find_guest_path(start, goal)
	assert_false(guest.is_empty(), "guests go round")
	for cell: Vector2i in guest:
		assert_false(grid.is_staff_only(cell), "guest path enters %s" % cell)
	assert_true(guest.has(Vector2i(14, 4)), "round through the east corridor")
	# Storage is staff-only too: paint the corridor and guests can't go round.
	grid.set_rooms(_rooms(_rect(14, 0, 1, 10), SimGrid.Room.STORAGE))
	assert_true(grid.find_guest_path(start, goal).is_empty())
	assert_false(grid.find_path(start, goal).is_empty(), "staff still can")
	assert_true(grid.find_guest_path(start, Vector2i(3, 2)).is_empty(), "never into the kitchen")


func test_starter_guest_paths_are_unchanged_by_the_kitchen() -> void:
	var grid: SimGrid = _sim.world.grid
	for entry: Vector2i in grid.entries():
		for table: PlacedItem in grid.items():
			for seat: Vector2i in table.seat_cells:
				assert_eq(grid.find_guest_path(entry, seat), grid.find_path(entry, seat))


func test_seats_in_staff_rooms_are_refused() -> void:
	var check: EditCheck = _editor.check_buy(&"table_2", Vector2i(8, 2), 0)
	assert_false(check.ok)
	assert_eq(check.why, RoomRules.SEAT_IN_KITCHEN)
	# A table in the dining room, then its seat painted as storage.
	var table: PlacedItem = _sim.world.grid.item_at(Vector2i(2, 6))
	assert_eq(_editor.check_rooms(_rooms([table.seat_cells[0]], SimGrid.Room.STORAGE)).why, RoomRules.SEAT_IN_STORAGE)
	assert_eq(_editor.check_rooms(_rooms([table.seat_cells[0]], SimGrid.Room.KITCHEN)).why, RoomRules.SEAT_IN_KITCHEN)
	# Moving a table into the kitchen is refused the same way.
	assert_eq(_editor.check_move(table.id, Vector2i(8, 2), 0).why, RoomRules.SEAT_IN_KITCHEN)
	# Kitchen stations may stand in any room: staff walk everywhere.
	assert_true(_editor.check_buy(&"fryer", Vector2i(10, 8), 0).ok, _editor.check_buy(&"fryer", Vector2i(10, 8), 0).why)


func test_back_room_through_the_kitchen_is_refused_and_around_it_accepted() -> void:
	assert_true(_editor.apply_floor(_rect(1, -3, 12, 3), true), _editor.last_check.why)
	var check: EditCheck = _editor.check_buy(&"table_2", Vector2i(5, -2), 1)
	assert_false(check.ok)
	assert_eq(check.why, RoomRules.THROUGH_KITCHEN)
	# A corridor wrapping round the kitchen: east wing plus the back corner.
	assert_true(_editor.apply_floor(_rect(14, -3, 1, 13), true), _editor.last_check.why)
	assert_true(_editor.apply_floor(_rect(13, -3, 1, 3), true) or _sim.world.grid.terrain(Vector2i(13, -2)) == SimGrid.Terrain.FLOOR)
	assert_true(_editor.buy(&"table_2", Vector2i(5, -2), 1), _editor.last_check.why)
	var table: PlacedItem = _sim.world.grid.item_at(Vector2i(5, -2))
	# Wall the corridor off and only the kitchen route is left: refused.
	var wall: Dictionary[Vector3i, int] = {Vector3i(14, 4, SimGrid.EDGE_NORTH): SimGrid.Segment.WALL}
	assert_eq(_editor.check_segments(wall).why, RoomRules.THROUGH_KITCHEN)
	# Painting the corridor as storage cuts the guests' route too.
	assert_eq(_editor.check_rooms(_rooms(_rect(14, 0, 1, 4), SimGrid.Room.STORAGE)).why, RoomRules.THROUGH_KITCHEN)
	# A guest walks there round the kitchen, never through it.
	var grid: SimGrid = _sim.world.grid
	for other: PlacedItem in grid.items():
		if other.id != table.id and (other.def as ItemDef).category == ItemDef.Category.TABLE:
			for seat: Vector2i in other.seat_cells:
				other.reserve(seat, 9999)
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()
	_sim.world.clock.start_service()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 7
	var guest: CustomerAgent = _sim.add_customer(grid.entries()[0], random)
	var steps: int = 0
	while guest.state != CustomerAgent.State.ORDERING and steps < 400:
		_sim.advance()
		steps += 1
		assert_false(grid.is_staff_only(guest.cell), "guest stepped into %s" % guest.cell)
	assert_eq(guest.state, CustomerAgent.State.ORDERING)
	assert_eq(guest.table_item_id, table.id)
	print("ROOMS_BACK_ROOM steps=%d seat=%s" % [steps, guest.seat_cell])


func test_the_pass_needs_the_kitchen_and_the_guests() -> void:
	var pass_item: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	assert_eq(_editor.check_rooms(_rooms([pass_item.work_cells[0]], SimGrid.Room.DINING)).why, RoomRules.PASS_SIDES)
	assert_eq(_editor.check_rooms(_rooms([pass_item.work_cells[1]], SimGrid.Room.KITCHEN)).why, RoomRules.PASS_SIDES)
	# Turned round, its kitchen side faces the dining room: refused.
	assert_eq(_editor.check_move(pass_item.id, pass_item.origin, 2).why, RoomRules.PASS_SIDES)
	assert_true(_editor.check_current().ok, "the starter layout is valid")


func test_painting_is_free_closed_only_and_undoable() -> void:
	var grid: SimGrid = _sim.world.grid
	var cells: Array[Vector2i] = _rect(10, 8, 3, 2)
	var check: EditCheck = _editor.check_rooms(_rooms(cells, SimGrid.Room.RESTROOM))
	assert_true(check.ok, check.why)
	assert_eq(check.cost, 0)
	var before: int = _cash
	assert_true(_history.apply_rooms(_editor.room_changes(cells, SimGrid.Room.RESTROOM)), _editor.last_check.why)
	assert_eq(_cash, before, "free")
	for cell: Vector2i in cells:
		assert_eq(grid.room(cell), SimGrid.Room.RESTROOM, "painted under furniture too: %s" % cell)
	assert_eq(_history.undo_label(), "room painting")
	assert_true(_history.undo(), _history.last_refusal)
	for cell: Vector2i in cells:
		assert_eq(grid.room(cell), SimGrid.Room.DINING)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(grid.room(cells[0]), SimGrid.Room.RESTROOM)
	assert_eq(_editor.check_rooms(_rooms(cells, SimGrid.Room.RESTROOM)).why, RoomRules.ALREADY)
	assert_eq(_editor.check_rooms(_rooms([Vector2i(0, 0)], SimGrid.Room.KITCHEN)).why, RoomRules.NOT_FLOOR)
	_sim.world.clock.start_service()
	assert_eq(_editor.check_rooms(_rooms(cells, SimGrid.Room.DINING)).why, RoomRules.ROOMS_CLOSED)


func test_undo_restores_an_accepted_layout_without_room_checks() -> void:
	var grid: SimGrid = _sim.world.grid
	var seat: Vector2i = grid.item_at(Vector2i(2, 6)).seat_cells[0]
	# An older save could have a seat in the kitchen; the shop accepted it.
	grid.set_rooms({seat: SimGrid.Room.KITCHEN} as Dictionary[Vector2i, int])
	assert_true(_editor.check_current().ok)
	assert_true(_history.apply_rooms(_rooms([seat], SimGrid.Room.DINING)), _editor.last_check.why)
	assert_eq(_editor.check_rooms(_rooms([seat], SimGrid.Room.KITCHEN)).why, RoomRules.SEAT_IN_KITCHEN)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(grid.room(seat), SimGrid.Room.KITCHEN, "undo puts the accepted layout back")
	# An unrelated edit still works beside the old problem.
	assert_true(_editor.check_rooms(_rooms([Vector2i(12, 9)], SimGrid.Room.RESTROOM)).ok)


func test_floor_removal_undo_brings_its_rooms_back() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_history.apply_floor(_rect(14, 0, 1, 10), true), _editor.last_check.why)
	assert_true(_history.apply_rooms(_rooms(_rect(14, 7, 1, 2), SimGrid.Room.RESTROOM)), _editor.last_check.why)
	assert_true(_history.apply_floor(_rect(14, 0, 1, 10), false), _editor.last_check.why)
	assert_eq(grid.room(Vector2i(14, 7)), SimGrid.Room.DINING, "no room off the floor")
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(grid.room(Vector2i(14, 7)), SimGrid.Room.RESTROOM)


func test_rooms_save_and_load() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_editor.apply_rooms(_rooms(_rect(11, 8, 2, 2), SimGrid.Room.RESTROOM)), _editor.last_check.why)
	var snapshot: Dictionary = _editor.to_dict()
	assert_eq(int(snapshot["version"]), 4)
	assert_true((snapshot["rooms"] as Array).has([11, 8, "restroom"]))
	assert_true((snapshot["rooms"] as Array).has([5, 4, "kitchen"]))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(JSON.parse_string(JSON.stringify(snapshot)), LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	var restored: RestaurantSim = RestaurantSim.create(layout, _content, 1, errors, null, false, true)
	assert_eq(errors, [] as Array[String])
	assert_eq(restored.world.grid.rooms(), grid.rooms())
	# Bad rows refuse the whole snapshot.
	for bad: Array in [[0, 0, "kitchen"], [3, 6, "attic"], [3, 6, "dining"]]:
		var broken: Dictionary = snapshot.duplicate(true)
		(broken["rooms"] as Array).append(bad)
		var bad_errors: Array[String] = []
		assert_null(ShopEditor.from_dict(broken, LAYOUT, _content, bad_errors), "%s" % [bad])


func test_older_saves_infer_the_starter_kitchen() -> void:
	var snapshot: Dictionary = _editor.to_dict()
	snapshot["version"] = 3
	snapshot.erase("rooms")
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(layout.room_map(), LAYOUT.authored_rooms())
	# A table a player once put in the kitchen keeps its seats.
	var legacy: Dictionary = snapshot.duplicate(true)
	(legacy["items"] as Array).append({"def_id": "table_2", "origin": [9, 2], "quarter_turns": 0, "swatch_id": ""})
	var legacy_layout: ShopLayout = ShopEditor.from_dict(legacy, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_false(legacy_layout.room_map().has(Vector2i(8, 3)), "seat cell left as dining")
	assert_true(legacy_layout.room_map().has(Vector2i(2, 2)))


func test_vibe_counts_decor_only_in_guest_rooms() -> void:
	var grid: SimGrid = _sim.world.grid
	var plant: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"potted_plant")[0]
	var inputs: VibeModel.Inputs = VibeInputs.capture(grid, _content, [])
	assert_eq(inputs.items.size(), grid.items().size(), "the starter plant counts")
	# A plant in the kitchen does not count.
	assert_not_null(grid.place_def(_content.item(&"potted_plant"), Vector2i(12, 3)))
	inputs = VibeInputs.capture(grid, _content, [])
	assert_eq(inputs.items.size(), grid.items().size() - 1)
	# A walled-off corner of the dining room does not count either.
	var walls: Dictionary[Vector3i, int] = {}
	walls[SimGrid.edge_between(plant.cells[0], plant.cells[0] + Vector2i.LEFT)] = SimGrid.Segment.WALL
	walls[SimGrid.edge_between(plant.cells[0], plant.cells[0] + Vector2i.UP)] = SimGrid.Segment.WALL
	grid.set_segments(walls)
	inputs = VibeInputs.capture(grid, _content, [])
	assert_eq(inputs.items.size(), grid.items().size() - 2)


func _rooms(cells: Array[Vector2i], kind: int) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in cells:
		out[cell] = kind
	return out


func _rect(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in range(y, y + h):
		for column: int in range(x, x + w):
			out.append(Vector2i(column, row))
	return out


func _can_spend(amount: int) -> bool:
	return amount <= _cash


func _record_cash(amount: int, _category: StringName) -> void:
	_cash += amount
