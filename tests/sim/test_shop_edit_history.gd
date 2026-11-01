extends TestCase
## FK-085: undo and redo of shop edits. Each undo goes through the same
## ShopEditor checks as a fresh edit and moves money back exactly, so the
## ledger round-trips; refusals leave the history untouched.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const START_CASH: int = 1000

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = START_CASH
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null
	_ledger = null


func test_undo_buy_refunds_the_full_price_and_redo_charges_it_again() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_history.buy(&"potted_plant", Vector2i(12, 8)), _editor.last_check.why)
	var price: int = _content.item(&"potted_plant").price
	assert_eq(_ledger.cash, START_CASH - price)
	assert_eq(_history.undo_label(), "buy Potted plant")
	assert_true(_history.undo(), _history.last_refusal)
	assert_null(grid.item_at(Vector2i(12, 8)))
	assert_eq(_ledger.cash, START_CASH, "a full refund, not the half-price sell rate")
	assert_eq(_upgrades(), 0, "the day's upgrades net to zero")
	assert_eq(_last_entry()["note"], ShopEditHistory.UNDO_NOTE, "the refund is marked as an undo")
	assert_eq(_history.redo_label(), "buy Potted plant")
	assert_true(_history.redo(), _history.last_refusal)
	var placed: PlacedItem = grid.item_at(Vector2i(12, 8))
	assert_not_null(placed)
	assert_eq((placed.def as ItemDef).id, &"potted_plant")
	assert_eq(_ledger.cash, START_CASH - price)
	assert_eq(_last_entry()["note"], ShopEditHistory.REDO_NOTE)
	assert_eq(_history.undo_count(), 1)
	assert_eq(_history.redo_count(), 0)


func test_undo_sell_charges_back_the_refund_and_restores_place_turn_and_colour() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_history.buy(&"potted_plant", Vector2i(12, 8)), _editor.last_check.why)
	var plant: PlacedItem = grid.item_at(Vector2i(12, 8))
	assert_true(_history.paint(&"item", &"sage", plant.id))
	assert_true(_history.move(plant.id, Vector2i(11, 8), 1), _editor.last_check.why)
	var cash_before_sale: int = _ledger.cash
	var refund: int = _history.sell(plant.id)
	assert_eq(refund, _content.item(&"potted_plant").price / 2)
	assert_eq(_ledger.cash, cash_before_sale + refund)
	assert_true(_history.undo(), _history.last_refusal)
	var back: PlacedItem = grid.item_at(Vector2i(11, 8))
	assert_not_null(back)
	assert_eq(back.quarter_turns, 1)
	assert_eq(back.swatch_id, &"sage", "the colour comes back with it")
	assert_eq(_ledger.cash, cash_before_sale, "exactly the refund is charged back")
	# Older entries follow the restored item to its new grid id.
	assert_true(_history.undo(), _history.last_refusal)
	assert_not_null(grid.item_at(Vector2i(12, 8)), "the move is undone on the restored item")
	assert_eq(grid.item_at(Vector2i(12, 8)).quarter_turns, 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(grid.item_at(Vector2i(12, 8)).swatch_id, &"")
	assert_true(_history.undo(), _history.last_refusal)
	assert_null(grid.item_at(Vector2i(12, 8)))
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(_upgrades(), 0)
	# And all the way forward again.
	for step: int in range(4):
		assert_true(_history.redo(), "redo %d: %s" % [step, _history.last_refusal])
	assert_null(grid.item_at(Vector2i(11, 8)), "sold again")
	assert_eq(_ledger.cash, cash_before_sale + refund)


func test_undo_move_and_rotate_of_starter_furniture() -> void:
	var grid: SimGrid = _sim.world.grid
	var table: PlacedItem = grid.item_at(Vector2i(2, 6))
	assert_not_null(table)
	var origin: Vector2i = table.origin
	assert_true(_history.move(table.id, origin + Vector2i(0, 1), table.quarter_turns), _editor.last_check.why)
	assert_eq(_history.undo_label(), "move " + (table.def as ItemDef).display_name)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(table.origin, origin)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(table.origin, origin + Vector2i(0, 1))
	assert_eq(_ledger.cash, START_CASH, "moves are free")


func test_undo_wall_edits_with_an_exact_ledger_round_trip() -> void:
	var grid: SimGrid = _sim.world.grid
	var edge: Vector3i = Vector3i(9, 6, SimGrid.EDGE_WEST)
	var support: Vector3i = Vector3i(9, 5, SimGrid.EDGE_WEST)
	assert_true(_history.apply_segments({edge: SimGrid.Segment.WALL,
		support: SimGrid.Segment.WALL} as Dictionary[Vector3i, int]), _editor.last_check.why)
	var after_build: int = _ledger.cash
	assert_lt(after_build, START_CASH)
	# Turning it into a doorway refunds the wall at half and buys a doorway.
	assert_true(_history.apply_segments({edge: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]), _editor.last_check.why)
	assert_eq(grid.segment(edge), SimGrid.Segment.DOORWAY)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(grid.segment(edge), SimGrid.Segment.WALL)
	assert_eq(_ledger.cash, after_build)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(grid.segment(edge), SimGrid.Segment.NONE)
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(_upgrades(), 0)
	assert_true(_history.redo(), _history.last_refusal)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(grid.segment(edge), SimGrid.Segment.DOORWAY)
	assert_false(_history.redo())
	assert_eq(_history.last_refusal, "Nothing to redo")


func test_undo_floor_puts_back_the_window_it_took_down() -> void:
	var grid: SimGrid = _sim.world.grid
	var window: Vector3i = Vector3i(13, 7, SimGrid.EDGE_WEST)
	assert_true(_history.apply_segments({window: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]), _editor.last_check.why)
	var before_floor: int = _ledger.cash
	assert_true(_history.apply_floor(_rect(14, 6, 1, 4), true), _editor.last_check.why)
	assert_eq(grid.segment(window), SimGrid.Segment.NONE, "the wing opens the old wall and removes its window")
	assert_eq(_ledger.cash, before_floor - 60 + 10)
	assert_eq(grid.terrain(Vector2i(14, 7)), SimGrid.Terrain.FLOOR)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(grid.terrain(Vector2i(14, 7)), SimGrid.Terrain.OUTSIDE)
	assert_eq(grid.terrain(Vector2i(13, 7)), SimGrid.Terrain.WALL)
	assert_eq(grid.segment(window), SimGrid.Segment.WINDOW, "the window is back")
	assert_eq(_ledger.cash, before_floor, "the floor price and the window refund both reverse")
	assert_true(_editor.bought_floor().is_empty())
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(grid.terrain(Vector2i(14, 7)), SimGrid.Terrain.FLOOR)
	assert_eq(grid.segment(window), SimGrid.Segment.NONE)
	assert_true(_history.undo(), _history.last_refusal)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(_upgrades(), 0)


func test_undo_wall_removal_restores_its_orphaned_opening_and_exact_cash() -> void:
	var grid: SimGrid = _sim.world.grid
	var wall: Vector3i = Vector3i(9, 6, SimGrid.EDGE_WEST)
	var window: Vector3i = Vector3i(9, 7, SimGrid.EDGE_WEST)
	assert_true(_history.apply_segments({wall: SimGrid.Segment.WALL,
		window: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]), _editor.last_check.why)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	assert_true(_history.apply_segments({wall: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]), _editor.last_check.why)
	assert_eq(grid.segment(window), SimGrid.Segment.NONE)
	assert_eq(_ledger.cash, cash + 15)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(grid.segment(window), SimGrid.Segment.NONE)
	assert_eq(_ledger.cash, cash + 15)


func test_undo_expansion_restores_the_back_door_and_its_receiving_route() -> void:
	var grid: SimGrid = _sim.world.grid
	var door: Vector3i = Vector3i(13, 6, SimGrid.EDGE_WEST)
	assert_true(_history.apply_segments({door: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]), _editor.last_check.why)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	assert_true(_history.apply_floor(_rect(14, 5, 1, 5), true), _editor.last_check.why)
	assert_eq(grid.segment(door), SimGrid.Segment.NONE)
	assert_eq(_ledger.cash, cash - 75 + 7)
	assert_eq(WallRules.delivery_cell(grid), grid.entries()[0])
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_eq(WallRules.delivery_cell(grid), Vector2i(12, 6))
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(grid.segment(door), SimGrid.Segment.NONE)
	assert_eq(_ledger.cash, cash - 75 + 7)


func test_undo_floor_removal_stages_restored_walls_before_checking_existing_openings() -> void:
	assert_true(_history.apply_floor(_rect(1, -3, 12, 3), true), _editor.last_check.why)
	var grid: SimGrid = _sim.world.grid
	var wall: Vector3i = Vector3i(5, -2, SimGrid.EDGE_NORTH)
	var window: Vector3i = Vector3i(6, -2, SimGrid.EDGE_NORTH)
	assert_true(_history.apply_segments({wall: SimGrid.Segment.WALL,
		window: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]), _editor.last_check.why)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var removed: Array[Vector2i] = [Vector2i(5, -3)]
	assert_true(_history.apply_floor(removed, false), _editor.last_check.why)
	assert_eq(grid.segment(wall), SimGrid.Segment.NONE)
	assert_eq(grid.segment(window), SimGrid.Segment.WINDOW, "the new shell cell supports the existing window")
	assert_eq(_ledger.cash, cash + 7 + 5, "one floor tile and wall refund")
	var after: Dictionary = _editor.to_dict()
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(grid.segment(wall), SimGrid.Segment.WALL)
	assert_eq(grid.segment(window), SimGrid.Segment.WINDOW, "the restored wall supplies support in the final plan")
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), after)
	assert_eq(_ledger.cash, cash + 12)


func test_undo_floor_removal_adds_it_back_at_the_refunded_amount() -> void:
	assert_true(_history.apply_floor(_rect(1, -3, 12, 3), true), _editor.last_check.why)
	var full: int = _ledger.cash
	assert_true(_history.apply_floor(_rect(9, -3, 3, 1), false), _editor.last_check.why)
	assert_eq(_ledger.cash, full + 3 * 7)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, full, "only the refund is charged back, not the full floor price")
	assert_eq(_editor.bought_floor().size(), 36)


func test_paint_undo_restores_the_previous_colours() -> void:
	var wall: StringName = _editor.wall_swatch_id
	assert_true(_history.paint(&"wall", &"sage"))
	assert_true(_history.paint(&"floor", &"honey"))
	assert_eq(_history.undo_label(), "paint the floor")
	assert_true(_history.undo())
	assert_eq(_editor.floor_swatch_id, &"" if LAYOUT.floor_swatch_id.is_empty() else LAYOUT.floor_swatch_id)
	assert_true(_history.undo())
	assert_eq(_editor.wall_swatch_id, wall)
	assert_true(_history.redo())
	assert_eq(_editor.wall_swatch_id, &"sage")
	assert_true(_history.paint(&"wall", &"sage"), "repainting the same colour succeeds")
	assert_eq(_history.redo_count(), 1, "an unchanged colour is not a new edit")
	assert_eq(_ledger.cash, START_CASH)


func test_a_new_edit_clears_redo() -> void:
	assert_true(_history.buy(&"potted_plant", Vector2i(12, 8)))
	assert_true(_history.undo())
	assert_eq(_history.redo_count(), 1)
	assert_true(_history.buy(&"potted_plant", Vector2i(11, 8)))
	assert_eq(_history.redo_count(), 0)
	assert_false(_history.redo())


## Undo uses the normal edit checks. Removing floor someone now stands on
## would shut them out, so the undo is refused and nothing changes.
func test_an_undo_that_would_shut_someone_in_is_refused_and_kept() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_history.apply_floor(_rect(1, -3, 12, 3), true), _editor.last_check.why)
	var cash: int = _ledger.cash
	var staff: SimAgent = null
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent:
			staff = agent
			break
	assert_not_null(staff)
	var post: Vector2i = staff.cell
	staff.cell = Vector2i(3, -3)
	assert_false(_history.undo())
	assert_eq(_history.last_refusal, WallRules.CUT_PERSON)
	assert_eq(_history.undo_count(), 1, "the entry stays for a later try")
	assert_eq(_history.redo_count(), 0)
	assert_eq(_ledger.cash, cash, "a refused undo moves no money")
	assert_eq(grid.terrain(Vector2i(3, -3)), SimGrid.Terrain.FLOOR)
	staff.cell = post
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH)


func test_undo_is_refused_while_open_and_clear_empties_both_stacks() -> void:
	assert_true(_history.buy(&"potted_plant", Vector2i(12, 8)))
	assert_true(_history.undo())
	assert_true(_history.redo())
	assert_true(_history.undo())
	assert_true(_history.redo())
	assert_true(_sim.world.clock.start_service())
	assert_false(_history.can_undo())
	assert_false(_history.undo())
	assert_eq(_history.last_refusal, "Undo is only available in the morning or after closing")
	assert_not_null(_sim.world.grid.item_at(Vector2i(12, 8)))
	_history.clear()
	assert_eq(_history.undo_count(), 0)
	assert_eq(_history.redo_count(), 0)


func test_paint_during_service_is_not_recorded() -> void:
	assert_true(_sim.world.clock.start_service())
	assert_true(_history.paint(&"wall", &"sage"))
	assert_eq(_editor.wall_swatch_id, &"sage")
	assert_eq(_history.undo_count(), 0)


func assert_lt(actual: int, limit: int) -> void:
	assert_true(actual < limit, "%d < %d" % [actual, limit])


func _upgrades() -> int:
	return int(_ledger.day_totals(1).get(Ledger.UPGRADES, 0))


func _last_entry() -> Dictionary:
	var entries: Array[Dictionary] = _ledger.entries_for_day(1)
	return entries.back() if not entries.is_empty() else {}


func _rect(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in range(y, y + h):
		for column: int in range(x, x + w):
			out.append(Vector2i(column, row))
	return out


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)


func test_undo_sell_restores_starter_furniture_above_the_owner_level() -> void:
	_editor.set_owner_level(1)
	var plant: PlacedItem = null
	for placed: PlacedItem in _sim.world.grid.items():
		if (placed.def as ItemDef).id == &"potted_plant":
			plant = placed
	assert_not_null(plant)
	assert_true((plant.def as ItemDef).unlock_level > 1, "a starter piece the owner could not buy yet")
	var cell: Vector2i = plant.origin
	assert_true(_history.sell(plant.id) >= 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_not_null(_sim.world.grid.item_at(cell))
	assert_eq(_ledger.cash, START_CASH)
	assert_false(_editor.check_buy(&"potted_plant", Vector2i(4, 9)).ok, "a new purchase still needs the level")


## Review M1: undo restores a layout the shop already accepted, even when that
## layout had a seat nobody could reach. The table's seat at (0, 5) sat in the
## old west wall; the new floor there made it usable, and undoing the floor must
## not be refused forever with "That would cut off a seat".
func test_undo_back_to_an_accepted_layout_with_an_unusable_seat() -> void:
	# This historical accepted seat relies on the old thick divider endpoint.
	var layout: ShopLayout = LegacyTier1Layout.make()
	_sim = RestaurantSim.create(layout, _content, 1, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), layout)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)
	var grid: SimGrid = _sim.world.grid
	var table: PlacedItem = grid.item(5)
	assert_not_null(table)
	assert_true(_history.move(table.id, Vector2i(1, 5), 2), _editor.last_check.why)
	assert_eq(grid.terrain(Vector2i(0, 5)), SimGrid.Terrain.WALL)
	var before_floor: int = _ledger.cash
	assert_true(_history.apply_floor(_rect(-1, 4, 1, 3), true), _editor.last_check.why)
	assert_eq(grid.terrain(Vector2i(0, 5)), SimGrid.Terrain.FLOOR)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(grid.terrain(Vector2i(0, 5)), SimGrid.Terrain.WALL)
	assert_eq(_ledger.cash, before_floor)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_history.undo_count(), 0)
	assert_eq(_ledger.cash, START_CASH)
	# A fresh removal is still checked as before.
	assert_true(_history.redo(), _history.last_refusal)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.check_floor(_rect(-1, 4, 1, 3), false).why, WallRules.CUT_SEAT)
