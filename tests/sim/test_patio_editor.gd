extends TestCase
## Patio transactions use the shipped pavement, ordinary books and the same
## checked history path as indoor construction. Refusals must be atomic.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const LOAN_TERMS: LoanTuning = preload("res://data/balance/loans.tres")
const START_CASH: int = 1000

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger
var _loan: LoanAccount
var _changes: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = START_CASH
	_loan = LoanAccount.new()
	_changes = 0
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record, _purchase_refusal), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)
	_sim.world.grid.cells_changed.connect(_cells_changed)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null
	_ledger = null
	_loan = null


func test_purchase_deduplicates_and_skips_the_public_approach_in_a_rectangle() -> void:
	var grid: SimGrid = _sim.world.grid
	var before: Dictionary = _editor.to_dict()
	var drag: Array[Vector2i] = _rect(-1, 0, 4, 2)
	drag.append(_street(-1, 0))
	var expected: Array[Vector2i] = [_street(-1, 0), _street(2, 0), _street(-1, 1), _street(2, 1)]
	var check: EditCheck = _editor.check_patio(drag, true)
	assert_true(check.ok, check.why)
	assert_eq(check.floor_cells, expected)
	assert_true(check.floor_adding)
	assert_eq([check.cost, check.refund], [4 * LAYOUT.patio_cell_price, 0])
	assert_eq(_editor.to_dict(), before, "a preview cannot buy pavement")
	assert_eq(_changes, 0)
	assert_true(_history.apply_patio(drag, true), _editor.last_check.why)
	assert_eq(_editor.bought_patio(), expected)
	assert_eq(_ledger.cash, START_CASH - 60)
	assert_eq(_ledger.entries_for_day(1).size(), 1)
	assert_eq(_last_entry()["category"], Ledger.UPGRADES)
	assert_eq(_last_entry()["amount"], -60)
	for cell: Vector2i in expected:
		assert_true(_editor.is_patio_bought(cell))
		assert_true(grid.is_outdoor_floor(cell))
		assert_eq(grid.room(cell), SimGrid.Room.PATIO)
		assert_false(grid.find_guest_path(_street(0, 0), cell).is_empty())
	for cell: Vector2i in _rect(0, 0, 2, 4):
		assert_false(_editor.is_patio_bought(cell), "both door approach columns stay public")
		assert_false(grid.is_outdoor_floor(cell))
	assert_eq(grid.entries(), [_street(0, 0), _street(1, 0)] as Array[Vector2i])
	assert_eq(grid.terrain(_street(-1, -1)), SimGrid.Terrain.WALL, "the street wall stays put")
	assert_true(_editor.bought_floor().is_empty(), "pavement is separate from the indoor lot")
	var owned: Array[Vector2i] = _editor.bought_patio()
	owned.clear()
	assert_eq(_editor.bought_patio(), expected, "callers cannot mutate ownership through the getter")


func test_sale_and_history_reverse_the_original_cash_exactly() -> void:
	var cells: Array[Vector2i] = _rect(-2, 0, 2, 2)
	assert_true(_history.apply_patio(cells, true), _editor.last_check.why)
	var purchase: Dictionary = _editor.to_dict()
	var paid: int = _ledger.cash
	var sold: Array[Vector2i] = [_street(-2, 1), _street(-2, 1)]
	var check: EditCheck = _editor.check_patio(sold, false)
	assert_true(check.ok, check.why)
	assert_false(check.floor_adding)
	assert_eq(check.floor_cells, [_street(-2, 1)] as Array[Vector2i])
	assert_eq([check.cost, check.refund], [0, 7])
	assert_true(_history.apply_patio(sold, false), _editor.last_check.why)
	var after_sale: Dictionary = _editor.to_dict()
	assert_eq(_ledger.cash, paid + 7)
	assert_eq(_sim.world.grid.terrain(_street(-2, 1)), SimGrid.Terrain.OUTSIDE)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), purchase)
	assert_eq(_ledger.cash, paid, "undo charges the $7 refund, not a fresh $15 purchase")
	assert_eq(_last_entry()["note"], ShopEditHistory.UNDO_NOTE)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), after_sale)
	assert_eq(_ledger.cash, paid + 7)
	assert_eq(_last_entry()["note"], ShopEditHistory.REDO_NOTE)
	assert_true(_history.undo(), _history.last_refusal)
	assert_true(_history.undo(), _history.last_refusal)
	assert_true(_editor.bought_patio().is_empty())
	assert_eq(_ledger.cash, START_CASH, "undo of buying returns the full original price")
	assert_eq(int(_ledger.day_totals(1).get(Ledger.UPGRADES, 0)), 0)
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), purchase)
	assert_eq(_ledger.cash, paid)


func test_selling_patio_refunds_the_floor_finish_and_undo_restores_its_look() -> void:
	var cell: Array[Vector2i] = [_street(-1, 0)]
	assert_true(_history.apply_patio(cell, true), _editor.last_check.why)
	assert_true(_history.apply_flooring(_editor.lay_changes(cell, &"herringbone", &"sage")), _editor.last_check.why)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var check: EditCheck = _editor.check_patio(cell, false)
	assert_true(check.ok, check.why)
	assert_eq(check.floor_finish_refund, 1)
	assert_eq(check.refund, 8, "$7 pavement plus half the $3 finish, rounded down")
	assert_true(_history.apply_patio(cell, false), _editor.last_check.why)
	assert_eq(_ledger.cash, cash + 8)
	assert_eq(_editor.floors.count(), 0)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_eq(_editor.floors.finish(cell[0]).style, &"herringbone")
	assert_eq(_editor.floors.finish(cell[0]).swatch, &"sage")
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_ledger.cash, cash + 8)
	assert_eq(_editor.floors.count(), 0)


func test_outside_disconnected_and_public_only_purchases_change_nothing() -> void:
	var before: Dictionary = _editor.to_dict()
	for cells: Array[Vector2i] in [
		[_street(-1, 0), _street(-1, 4)] as Array[Vector2i],
		[_street(-7, 0)] as Array[Vector2i],
		[_street(-3, 3)] as Array[Vector2i],
		_rect(0, 0, 2, 4),
	]:
		assert_false(_editor.check_patio(cells, true).ok, str(cells))
		assert_false(_history.apply_patio(cells, true), str(cells))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(_ledger.entries_for_day(1).size(), 0)
	assert_eq(_changes, 0)
	assert_eq(_history.undo_count(), 0)
	assert_eq(_sim.world.grid.bounds, SimGrid.from_ascii(LAYOUT.rows).bounds)


func test_cash_and_active_loan_refusals_are_atomic_and_use_the_book_reason() -> void:
	var before: Dictionary = _editor.to_dict()
	_ledger.cash = 14
	assert_false(_history.apply_patio([_street(-1, 0)] as Array[Vector2i], true))
	assert_eq(_editor.last_check.why, ShopEditBooks.CASH_REFUSAL)
	assert_eq(_ledger.cash, 14)
	_ledger.cash = START_CASH
	_loan.principal = 50
	assert_false(_history.apply_patio(_rect(-2, 0, 2, 2), true))
	assert_eq(_editor.last_check.why, "Pay off your bank loan first")
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_changes, 0)
	assert_eq(_ledger.entries_for_day(1).size(), 0)
	assert_eq(_history.undo_count(), 0)
	assert_eq(_loan.principal, 50, "a purchase never borrows or repays")
	assert_true(_history.apply_patio([_street(-1, 0)] as Array[Vector2i], true), _editor.last_check.why)
	assert_eq(_ledger.cash, START_CASH - 15, "the ordinary small-purchase allowance still applies")


func test_patio_changes_are_morning_or_closed_only_including_exact_replay() -> void:
	var cells: Array[Vector2i] = [_street(-1, 0)]
	assert_true(_history.apply_patio(cells, true), _editor.last_check.why)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var changes: int = _changes
	for phase: SimClock.Phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		_sim.world.clock.phase = phase
		assert_false(_editor.apply_patio([_street(-1, 1)] as Array[Vector2i], true))
		assert_false(_editor.apply_patio(cells, false, ShopEditor.Exact.new(15, ShopEditHistory.UNDO_NOTE)))
		assert_false(_history.undo())
		assert_eq(_editor.to_dict(), before)
		assert_eq(_ledger.cash, cash)
		assert_eq(_changes, changes)
		assert_eq(_history.undo_count(), 1)
	_sim.world.clock.phase = SimClock.Phase.CLOSED
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH)


func test_removal_refuses_furniture_its_authored_seats_and_staff_even_for_exact() -> void:
	assert_true(_history.apply_patio(_rect(-6, 0, 6, 4), true), _editor.last_check.why)
	assert_true(_editor.buy(&"patio_table_2", _street(-4, 1)), _editor.last_check.why)
	var table: PlacedItem = _sim.world.grid.item_at(_street(-4, 1))
	assert_not_null(table)
	if table == null:
		return
	var staff: StaffAgent = null
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent:
			staff = agent as StaffAgent
			break
	assert_not_null(staff)
	if staff == null:
		return
	var post: Vector2i = staff.cell
	staff.cell = _street(-6, 3)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var changes: int = _changes
	var entries: int = _ledger.entries_for_day(1).size()
	for cell: Vector2i in [table.origin, _street(-5, 2), staff.cell]:
		for exact: ShopEditor.Exact in [null, ShopEditor.Exact.new(15, ShopEditHistory.UNDO_NOTE)]:
			assert_false(_editor.check_patio([cell] as Array[Vector2i], false, exact).ok, str(cell))
			assert_false(_editor.apply_patio([cell] as Array[Vector2i], false, exact), str(cell))
	assert_false(_history.undo(), "history cannot remove occupied pavement either")
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_eq(_changes, changes)
	assert_eq(_ledger.entries_for_day(1).size(), entries)
	assert_eq(_history.undo_count(), 1)
	staff.cell = post


func test_removing_the_only_connection_refuses_but_a_leaf_can_be_sold() -> void:
	assert_true(_history.apply_patio(_rect(-2, 0, 2, 3), true), _editor.last_check.why)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var changes: int = _changes
	assert_false(_history.apply_patio([_street(-1, 0)] as Array[Vector2i], false))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_eq(_changes, changes)
	assert_true(_history.apply_patio([_street(-2, 2)] as Array[Vector2i], false), _editor.last_check.why)
	for cell: Vector2i in _editor.bought_patio():
		assert_false(_sim.world.grid.find_guest_path(_street(0, 0), cell).is_empty(), str(cell))


func test_editor_buy_and_move_keep_indoor_and_outdoor_furniture_on_their_own_floor() -> void:
	assert_true(_editor.apply_patio(_rect(-2, 0, 2, 3), true), _editor.last_check.why)
	assert_true(_editor.buy(&"patio_waiting_bench", _street(-2, 1)), _editor.last_check.why)
	var bench: PlacedItem = _sim.world.grid.item_at(_street(-2, 1))
	assert_not_null(bench)
	if bench == null:
		return
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var changes: int = _changes
	var entries: int = _ledger.entries_for_day(1).size()
	for exact: ShopEditor.Exact in [null, ShopEditor.Exact.new()]:
		assert_false(_editor.check_buy(&"patio_waiting_bench", Vector2i(10, 8), 0, exact).ok)
		assert_false(_editor.buy(&"patio_waiting_bench", Vector2i(10, 8), 0, exact))
		assert_false(_editor.check_buy(&"potted_plant", _street(-2, 0), 0, exact).ok)
		assert_false(_editor.buy(&"potted_plant", _street(-2, 0), 0, exact))
		assert_false(_editor.check_move(bench.id, Vector2i(10, 8), 0, exact).ok)
		assert_false(_editor.move(bench.id, Vector2i(10, 8), 0, exact))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_eq(_ledger.entries_for_day(1).size(), entries)
	assert_eq(_changes, changes)
	assert_true(_editor.move(bench.id, _street(-2, 2), 0), _editor.last_check.why)
	assert_eq(bench.origin, _street(-2, 2))
	assert_eq(_ledger.cash, cash, "moving between bought patio cells is free")


func test_indoor_expansion_preserves_patio_and_room_paint_cannot_create_or_remove_it() -> void:
	var cells: Array[Vector2i] = _rect(-2, 0, 2, 2)
	assert_true(_history.apply_patio(cells, true), _editor.last_check.why)
	assert_true(_editor.apply_floor(_rect(8, -6, 1, 4), true), _editor.last_check.why)
	assert_true(_editor.apply_floor(_rect(8, -6, 1, 4), false), _editor.last_check.why)
	for cell: Vector2i in cells:
		assert_true(_sim.world.grid.is_outdoor_floor(cell))
	assert_eq(_editor.bought_patio(), cells)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var changes: int = _changes
	for exact: ShopEditor.Exact in [null, ShopEditor.Exact.new()]:
		assert_false(_editor.apply_rooms({_street(-1, 0): SimGrid.Room.DINING} as Dictionary[Vector2i, int], exact))
		assert_false(_editor.apply_rooms({Vector2i(11, 8): SimGrid.Room.PATIO} as Dictionary[Vector2i, int], exact))
	assert_false(_editor.apply_floor(cells, false), "indoor sale cannot sell outdoor ownership")
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_eq(_changes, changes)


func _rect(x: int, y: int, width: int, height: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row: int in range(_street(x, y).y, _street(x, y).y + height):
		for column: int in range(_street(x, y).x, _street(x, y).x + width):
			cells.append(Vector2i(column, row))
	return cells


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash \
		and (_loan.principal == 0 or amount <= LOAN_TERMS.large_purchase_limit)


func _purchase_refusal(_amount: int) -> String:
	return "Pay off your bank loan first" if _loan.principal > 0 else ShopEditBooks.CASH_REFUSAL


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)


func _last_entry() -> Dictionary:
	var entries: Array[Dictionary] = _ledger.entries_for_day(1)
	return entries.back() if not entries.is_empty() else {}


func _cells_changed(_cells: Array[Vector2i]) -> void:
	_changes += 1


func _street(x: int, y: int) -> Vector2i:
	return _sim.world.grid.entries()[0] + Vector2i(x, y)
