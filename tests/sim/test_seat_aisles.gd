extends TestCase
## #315: a seat is a stop, never an aisle. The editor walks as the movement
## coordinator does, so seats may end a path but never carry it on.

class Catalogue extends ContentDB:
	var definitions: Dictionary[StringName, ItemDef] = {}

	func item(id: StringName) -> ItemDef:
		return definitions.get(id) as ItemDef

const ENTRY: Vector2i = Vector2i(0, 11)
const CUT_TABLE: String = "Nobody walks through seats: this blocks the way to a table"

var _content: Catalogue
var _sim: RestaurantSim
var _editor: ShopEditor
var _cash: int = 1000


func before_each() -> void:
	_content = Catalogue.new()
	_add(&"stool", ItemDef.Category.CHAIR, Vector2i.ONE, [Vector2i.ZERO])
	_add(&"surface", ItemDef.Category.TABLE, Vector2i(2, 1))
	_add(&"small_surface", ItemDef.Category.TABLE)
	var booth: ItemDef = _add(&"booth", ItemDef.Category.CHAIR, Vector2i(2, 2), [Vector2i.ZERO, Vector2i.RIGHT])
	booth.blocking_cells = [Vector2i(0, 1), Vector2i(1, 1)]
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	grid.set_terrain(ENTRY, SimGrid.Terrain.ENTRY)
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(grid)
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash))
	_cash = 1000


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null


func test_stool_on_the_door_is_refused() -> void:
	# The entry's two thresholds: the cells right inside the street door.
	for cell: Vector2i in [Vector2i(0, 10), Vector2i(1, 11)]:
		assert_true(WallRules.door_cells(_sim.world.grid).has(cell))
		var table: PlacedItem = _place(&"small_surface", cell + Vector2i.UP)
		var check: EditCheck = _editor.check_buy(&"stool", cell)
		assert_false(check.ok, "a stool at %s would shut the door" % cell)
		assert_eq(check.why, ShopEditor.SEAT_IN_DOORWAY)
		assert_false(_editor.buy(&"stool", cell))
		assert_true(_sim.world.grid.remove(table.id))
	_place(&"small_surface", Vector2i(5, 4))
	assert_true(_editor.check_buy(&"stool", Vector2i(5, 5)).ok, "away from the door a stool is fine")


func test_door_lane_keeps_one_clear_way_in() -> void:
	# The cells straight in from the thresholds are the door lane's way in
	# (#308): one may hold a seat, but not every one.
	var lane: Dictionary[Vector2i, bool] = MovementCoordinator.lane_cells(_sim.world.grid)
	assert_true(lane.has(Vector2i(0, 9)) and lane.has(Vector2i(2, 11)))
	_place(&"small_surface", Vector2i(0, 8))
	_place(&"small_surface", Vector2i(2, 10))
	assert_true(_editor.buy(&"stool", Vector2i(0, 9)), _editor.last_check.why)
	var last: EditCheck = _editor.check_buy(&"stool", Vector2i(2, 11))
	assert_false(last.ok, "the last clear way in stays clear")
	assert_eq(last.why, ShopEditor.SEAT_IN_DOORWAY)


func test_stool_cannot_be_moved_onto_the_door() -> void:
	_place(&"small_surface", Vector2i(5, 4))
	_place(&"small_surface", Vector2i(0, 9))
	var stool: PlacedItem = _place(&"stool", Vector2i(5, 5))
	var check: EditCheck = _editor.check_move(stool.id, Vector2i(0, 10), 0)
	assert_false(check.ok)
	assert_eq(check.why, ShopEditor.SEAT_IN_DOORWAY)


func test_chair_row_that_seals_off_a_table_warns_but_is_allowed() -> void:
	# A wall across the room with a two-cell gap, each side of it flanked by a
	# counter a stool can face.
	var grid: SimGrid = _sim.world.grid
	for x: int in range(12):
		if x < 3 or x > 6:
			assert_true(grid.set_terrain(Vector2i(x, 4), SimGrid.Terrain.WALL))
	_place(&"small_surface", Vector2i(3, 4))
	_place(&"small_surface", Vector2i(6, 4))
	_place(&"small_surface", Vector2i(8, 1))
	_place(&"stool", Vector2i(8, 2))
	var left: int = _facing(Vector2i.LEFT)
	var right: int = _facing(Vector2i.RIGHT)
	var first: EditCheck = _editor.check_buy(&"stool", Vector2i(4, 4), left)
	assert_true(first.ok)
	assert_eq(first.seat_cut_warning, "", "one stool still leaves the gap open")
	# ...but only one cell of it, on the way to the table (#389).
	assert_false(first.aisle_pinches.is_empty())
	assert_eq(first.seat_warnings.get(0, ""), AisleRules.WARNING)
	assert_true(_editor.buy(&"stool", Vector2i(4, 4), left))
	var sealing: EditCheck = _editor.check_buy(&"stool", Vector2i(5, 4), right)
	assert_true(sealing.ok, "seat cut-offs follow the furniture rule: warn, never block")
	assert_eq(sealing.seat_warnings.get(0, ""), "Nobody walks through seats: this blocks the way to a table")
	assert_true(_editor.buy(&"stool", Vector2i(5, 4), right))
	# Plain paths still walk across the stools; real people never do.
	assert_true(grid.is_reachable(ENTRY, Vector2i(8, 2)))
	assert_false(WallRules.reachable(grid, true).has(Vector2i(8, 2)))
	assert_true(_editor.check_current().ok)
	var moved: EditCheck = _editor.check_move(grid.item_at(Vector2i(5, 4)).id, Vector2i(5, 4), right)
	assert_true(moved.seat_warnings.is_empty(), "only what an edit newly cuts off counts")


func test_seat_cut_off_of_a_station_warns() -> void:
	var grid: SimGrid = _sim.world.grid
	var stove: ItemDef = _add(&"stove", ItemDef.Category.STATION)
	stove.work_cells = [Vector2i.DOWN]
	for x: int in range(12):
		if x != 4 and x != 5:
			assert_true(grid.set_terrain(Vector2i(x, 4), SimGrid.Terrain.WALL))
	var station: PlacedItem = _place(&"stove", Vector2i(2, 1))
	_place(&"small_surface", Vector2i(4, 4))
	assert_false(_editor.check_current().unreachable.has(station.id))
	var check: EditCheck = _editor.check_buy(&"stool", Vector2i(5, 4), _facing(Vector2i.LEFT))
	assert_true(check.ok)
	assert_eq(check.seat_warnings.get(0, ""), "Nobody walks through seats: this blocks the way to a kitchen station")


func test_joined_tables_with_chair_rows_pass_without_warnings() -> void:
	_place(&"surface", Vector2i(4, 5))
	_place(&"surface", Vector2i(6, 5))
	for x: int in range(4, 8):
		var above: EditCheck = _editor.check_buy(&"stool", Vector2i(x, 4), _facing(Vector2i.DOWN))
		assert_true(above.ok)
		assert_true(above.seat_warnings.is_empty(), "a seat ending a path is fine")
		assert_true(_editor.buy(&"stool", Vector2i(x, 4), _facing(Vector2i.DOWN)))
		var below: EditCheck = _editor.check_buy(&"stool", Vector2i(x, 6), _facing(Vector2i.UP))
		assert_true(below.ok)
		assert_true(below.seat_warnings.is_empty())
		assert_true(_editor.buy(&"stool", Vector2i(x, 6), _facing(Vector2i.UP)))
	var table: PlacedItem = _sim.world.grid.item_at(Vector2i(4, 5))
	assert_eq(DiningSeats.usable_cells(_sim.world.grid, table).size(), 8, "joined capacity is unchanged")
	var current: EditCheck = _editor.check_current()
	assert_true(current.ok)
	assert_true(current.unreachable.is_empty())
	assert_true(current.seat_warnings.is_empty())


func test_back_to_back_booth_row_passes_without_warnings() -> void:
	# Two booths share a back line, each facing its own table, as in a diner.
	_place(&"surface", Vector2i(3, 3))
	_place(&"surface", Vector2i(3, 8))
	var up: EditCheck = _editor.check_buy(&"booth", Vector2i(3, 4), 0)
	assert_true(up.ok)
	assert_true(up.seat_warnings.is_empty())
	assert_true(_editor.buy(&"booth", Vector2i(3, 4), 0))
	var down: EditCheck = _editor.check_buy(&"booth", Vector2i(3, 6), 2)
	assert_true(down.ok)
	assert_true(down.seat_warnings.is_empty())
	assert_true(_editor.buy(&"booth", Vector2i(3, 6), 2))
	var reach: Dictionary[Vector2i, bool] = WallRules.reachable(_sim.world.grid, true)
	for item: PlacedItem in _sim.world.grid.items():
		for seat: Vector2i in item.seat_cells:
			assert_true(reach.has(seat), "booth seat %s is reached from its open end" % seat)
	var current: EditCheck = _editor.check_current()
	assert_true(current.unreachable.is_empty())
	assert_true(current.seat_warnings.is_empty())


func test_side_by_side_booths_warn_about_the_seats_between_them() -> void:
	_place(&"surface", Vector2i(2, 3))
	_place(&"surface", Vector2i(4, 3))
	assert_true(_editor.buy(&"booth", Vector2i(2, 4), 0))
	var second: EditCheck = _editor.check_buy(&"booth", Vector2i(4, 4), 0)
	assert_true(second.ok, "a warning, never a refusal")
	assert_eq(second.seat_warnings.get(0, ""), "Nobody walks through seats: this blocks the way to a table",
		"the inner seats can only be reached through another seat")


func test_a_plant_that_leaves_only_a_way_through_seats_warns() -> void:
	var grid: SimGrid = _sim.world.grid
	var plant: ItemDef = _add(&"plant", ItemDef.Category.DECOR)
	plant.solid = true
	for x: int in range(12):
		if x < 3 or x > 5:
			assert_true(grid.set_terrain(Vector2i(x, 4), SimGrid.Terrain.WALL))
	_place(&"small_surface", Vector2i(3, 4))
	_place(&"stool", Vector2i(4, 4), _facing(Vector2i.LEFT))
	_place(&"small_surface", Vector2i(8, 1))
	_place(&"stool", Vector2i(8, 2))
	var check: EditCheck = _editor.check_buy(&"plant", Vector2i(5, 4))
	assert_true(check.ok)
	assert_eq(check.seat_warnings.get(0, ""), "Nobody walks through seats: this blocks the way to a table")


func test_cut_off_warning_stays_on_the_item_until_the_next_change() -> void:
	_seal_with_plant_gap()
	assert_true(_editor.buy(&"plant", Vector2i(5, 4)))
	var plant: PlacedItem = _sim.world.grid.item_at(Vector2i(5, 4))
	assert_eq(_editor.check_current().seat_warnings.get(plant.id, ""), CUT_TABLE,
		"after the commit the warning stays on the plant")
	_place(&"small_surface", Vector2i(9, 9))
	assert_true(_editor.check_current().seat_warnings.is_empty(), "any later change ends it")


func test_cut_off_warning_joins_an_existing_one() -> void:
	var check: EditCheck = EditCheck.new(true)
	check.seat_warnings[4] = "Only 3 of 4 seats usable"
	ShopEditor._add_seat_warning(check, 4, CUT_TABLE)
	assert_eq(check.seat_warnings[4], "Only 3 of 4 seats usable\n" + CUT_TABLE)
	ShopEditor._add_seat_warning(check, 4, CUT_TABLE)
	assert_eq(check.seat_warnings[4], "Only 3 of 4 seats usable\n" + CUT_TABLE, "never twice")


func test_stamp_warns_on_the_entry_that_causes_the_cut() -> void:
	_seal_with_plant_gap()
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Two plants"
	blueprint.entries = [_entry(&"plant", Vector2i(0, 3)), _entry(&"plant", Vector2i(2, 0))]
	var check: EditCheck = _editor.check_stamp(blueprint, Vector2i(3, 4))
	assert_true(check.ok, check.why)
	assert_false(check.seat_warnings.has(-1), "the harmless first plant")
	assert_eq(check.seat_warnings.get(-2, ""), CUT_TABLE, "the plant in the gap")
	assert_true(_editor.stamp(blueprint, Vector2i(3, 4)), _editor.last_check.why)
	var gap: PlacedItem = _sim.world.grid.item_at(Vector2i(5, 4))
	assert_eq(_editor.check_current().seat_warnings.get(gap.id, ""), CUT_TABLE)
	assert_false(_editor.check_current().seat_warnings.has(_sim.world.grid.item_at(Vector2i(3, 7)).id))


func test_starter_layout_gains_no_warning() -> void:
	var errors: Array[String] = []
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	for layout: ShopLayout in [load("res://data/layouts/tier1_hole_in_the_wall.tres") as ShopLayout,
			load("res://data/layouts/tier1_original.tres") as ShopLayout]:
		var sim: RestaurantSim = RestaurantSim.create(layout, content, 1, errors)
		assert_eq(errors, [] as Array[String])
		var editor: ShopEditor = ShopEditor.new(sim, content, ShopEditBooks.new(_can_spend, _record_cash))
		var check: EditCheck = editor.check_current()
		assert_true(check.ok)
		assert_true(check.unreachable.is_empty())
		assert_true(check.seat_warnings.is_empty())
		for placed: PlacedItem in sim.world.grid.items():
			assert_eq(ShopEditor.seat_doorway_problem(sim.world.grid, placed), "")


func test_a_seat_ends_a_walk_and_diagonals_never_brush_one() -> void:
	var grid: SimGrid = _sim.world.grid
	for x: int in range(12):
		if x != 5:
			assert_true(grid.set_terrain(Vector2i(x, 4), SimGrid.Terrain.WALL))
	_place(&"small_surface", Vector2i(4, 5))
	_place(&"stool", Vector2i(5, 5), _facing(Vector2i.LEFT))
	var reach: Dictionary[Vector2i, bool] = WallRules.reachable(grid, true)
	assert_true(reach.has(Vector2i(5, 5)), "the seat itself is a reachable stop")
	assert_false(reach.has(Vector2i(5, 4)), "nobody walks on through it")
	assert_false(reach.has(Vector2i(6, 4)))
	assert_true(WallRules.reachable(grid).has(Vector2i(5, 4)), "the plain flood still crosses it")
	assert_false(WallRules.seat_step_ok(grid, Vector2i(5, 6), Vector2i(6, 5)),
		"a diagonal step brushing the seat's corner is refused")
	assert_true(WallRules.seat_step_ok(grid, Vector2i(6, 6), Vector2i(7, 7)))


## A wall across the room whose two-cell gap already holds one stool, and a
## table with its stool behind it: a plant in the other gap cell cuts it off.
func _seal_with_plant_gap() -> void:
	var grid: SimGrid = _sim.world.grid
	var plant: ItemDef = _add(&"plant", ItemDef.Category.DECOR)
	plant.solid = true
	for x: int in range(12):
		if x < 3 or x > 5:
			assert_true(grid.set_terrain(Vector2i(x, 4), SimGrid.Terrain.WALL))
	_place(&"small_surface", Vector2i(3, 4))
	_place(&"stool", Vector2i(4, 4), _facing(Vector2i.LEFT))
	_place(&"small_surface", Vector2i(8, 1))
	_place(&"stool", Vector2i(8, 2))


func _entry(id: StringName, offset: Vector2i, turns: int = 0) -> ShopPlacement:
	var entry: ShopPlacement = ShopPlacement.new()
	entry.item_id = id
	entry.origin = offset
	entry.quarter_turns = turns
	return entry


func _facing(direction: Vector2i) -> int:
	for turns: int in range(4):
		if GridMath.rotate_cell(Vector2i.UP, Vector2i.ONE, turns) == direction:
			return turns
	return 0


func _add(id: StringName, category: ItemDef.Category, footprint: Vector2i = Vector2i.ONE,
		seats: Array[Vector2i] = []) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = id
	definition.display_name = "Test furniture"
	definition.category = category
	definition.footprint = footprint
	definition.seat_cells = seats.duplicate()
	definition.solid = category != ItemDef.Category.CHAIR
	definition.price = 10
	definition.unlock_level = 1
	_content.definitions[id] = definition
	return definition


func _place(id: StringName, origin: Vector2i, turns: int = 0) -> PlacedItem:
	var placed: PlacedItem = _sim.world.grid.place_def(_content.item(id), origin, turns)
	assert_not_null(placed)
	return placed


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _cash


func _record_cash(amount: int, _category: StringName) -> void:
	_cash += amount
