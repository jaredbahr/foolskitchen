extends TestCase
## Pure interaction tests against the actual editor and Main-equivalent method
## wrappers. Camera projection, native input and rendering are session tests.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

class Catalog extends ContentDB:
	var extra: Dictionary[StringName, ItemDef] = {}

	func item(id: StringName) -> ItemDef:
		return extra[id] if extra.has(id) else super.item(id)

class CountingEditor extends ShopEditor:
	var current_queries: int = 0
	var move_queries: int = 0
	var buy_queries: int = 0

	func _init(sim: RestaurantSim, content: ContentDB, books: ShopEditBooks) -> void:
		super(sim, content, books)

	func check_current() -> EditCheck:
		current_queries += 1
		return super.check_current()

	func check_move(item_id: int, cell: Vector2i, turns: int) -> EditCheck:
		move_queries += 1
		return super.check_move(item_id, cell, turns)

	func check_buy(def_id: StringName, cell: Vector2i, turns: int = 0) -> EditCheck:
		buy_queries += 1
		return super.check_buy(def_id, cell, turns)

var _content: Catalog
var _sim: RestaurantSim
var _editor: CountingEditor
var _mode: BuildMode
var _cash: int = 1000
var _entries: Array[Dictionary] = []
var _cell_events: int = 0
var _move_calls: int = 0
var _buy_calls: int = 0
var _sell_calls: int = 0
var _refuse: bool = false
var _reenter: bool = false
var _reentry_result: bool = true


func before_each() -> void:
	_content = Catalog.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 55, errors)
	assert_eq(errors, [] as Array[String])
	_cash = 1000
	_editor = CountingEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash))
	_mode = BuildMode.new()
	_mode.bind_session(_editor, _sim.world, _content, _shop_move, _shop_buy, _shop_sell)
	_sim.world.grid.cells_changed.connect(_record_cells)


func after_each() -> void:
	_sim.world.grid.cells_changed.disconnect(_record_cells)
	_mode.bind_session(null, null, null, Callable(), Callable(), Callable())
	_mode = null
	_editor = null
	_sim = null
	_content = null
	_entries.clear()
	_cell_events = 0
	_move_calls = 0
	_buy_calls = 0
	_sell_calls = 0
	_refuse = false
	_reenter = false
	_reentry_result = true


func test_entry_requires_an_editable_phase_and_bound_session_methods() -> void:
	var before: Dictionary = _snapshot()
	for phase: SimClock.Phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		_sim.world.clock.phase = phase
		assert_false(_mode.enter())
		assert_eq(_mode.state, BuildMode.State.INACTIVE)
		assert_false(_mode.begin_buy(&"chair", Vector2i(4, 9)))
		assert_false(_mode.pick_up(_id(&"potted_plant")))
		assert_false(_mode.commit())
		assert_eq(_mode.sell_selected(), -1)
	for phase: SimClock.Phase in [SimClock.Phase.MORNING, SimClock.Phase.CLOSED]:
		_sim.world.clock.phase = phase
		assert_true(_mode.enter())
		assert_eq(_mode.state, BuildMode.State.IDLE)
		_mode.exit()
	_sim.world.clock.phase = SimClock.Phase.MORNING
	assert_eq(_snapshot(), before)
	assert_false(BuildMode.new().enter())
	_mode.bind_session(_editor, _sim.world, _content, Callable(), _shop_buy, _shop_sell)
	assert_false(_mode.enter(), "an incomplete command boundary cannot enter")
	assert_eq(_move_calls + _buy_calls + _sell_calls, 0)


func test_clock_transitions_cancel_ghosts_even_between_two_editable_phases() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"potted_plant")))
	var before: Dictionary = _editor.to_dict()
	assert_true(_sim.world.clock.start_service())
	assert_eq(_mode.state, BuildMode.State.INACTIVE)
	assert_false(_mode.has_ghost())
	assert_eq(_editor.to_dict(), before)
	_sim.world.clock.phase = SimClock.Phase.CLOSED
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	assert_true(_sim.world.clock.next_day())
	assert_eq(_mode.state, BuildMode.State.INACTIVE)
	assert_null(_mode.selected_definition)
	assert_eq(_entries.size(), 0)


func test_direct_phase_change_refuses_input_and_refresh_forces_exit() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	_sim.world.clock.phase = SimClock.Phase.OPEN
	assert_false(_mode.commit())
	assert_false(_mode.is_active())
	assert_eq(_buy_calls, 0)
	_sim.world.clock.phase = SimClock.Phase.CLOSED
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"potted_plant")))
	_sim.world.clock.phase = SimClock.Phase.MORNING
	_mode.refresh()
	assert_false(_mode.is_active(), "phase changes cancel even if both phases permit editing")
	assert_eq(_entries.size(), 0)


func test_move_preview_world_rotations_match_editor_and_cancel_preserves_live_data() -> void:
	assert_true(_mode.enter())
	var item: PlacedItem = _sim.world.grid.item(_id(&"fridge"))
	var original_turns: int = item.quarter_turns
	var before: Dictionary = _snapshot()
	assert_true(_mode.pick_up(item.id))
	_mode.update_origin(Vector2i(10, 8))
	for step: int in range(4):
		var expected: EditCheck = _editor.check_move(item.id, _mode.origin, _mode.quarter_turns)
		assert_eq(_mode.current_check.ok, expected.ok)
		assert_eq(_mode.current_check.why, expected.why)
		assert_eq(_mode.warning_ids(), expected.unreachable if expected.ok else _mode.committed_warning_ids)
		assert_eq(_mode.quarter_turns, (original_turns + step) % 4)
		assert_true(_mode.rotate())
	assert_eq(_mode.quarter_turns, original_turns)
	assert_true(_mode.selected_definition == item.def)
	assert_eq(_snapshot(), before, "holding or rotating a ghost performs no edit")
	_mode.cancel()
	assert_eq(_mode.state, BuildMode.State.IDLE)
	assert_eq(_mode.selected_item_id, -1)
	assert_eq(_snapshot(), before)
	_mode.cancel()
	assert_eq(_mode.state, BuildMode.State.INACTIVE)
	assert_eq(_snapshot(), before)


func test_invalid_preview_and_reserved_move_never_call_a_commit_method() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"chair", Vector2i(1, 1)))
	assert_false(_mode.current_check.ok)
	assert_false(_mode.current_check.why.is_empty())
	assert_false(_mode.commit())
	assert_true(_mode.has_ghost())
	assert_eq(_buy_calls, 0)
	var fridge: PlacedItem = _sim.world.grid.item(_id(&"fridge"))
	assert_true(fridge.reserve(fridge.work_cells[0], 88))
	assert_true(_mode.pick_up(fridge.id))
	_mode.update_origin(Vector2i(10, 8))
	assert_false(_mode.current_check.ok)
	assert_true(_mode.current_check.why.contains("in use"))
	assert_false(_mode.commit())
	assert_eq(_move_calls, 0)
	assert_eq(fridge.reserved_by(fridge.work_cells[0]), 88)
	assert_eq(_entries.size(), 0)


func test_successful_move_uses_one_session_wrapper_and_no_booking() -> void:
	var item: PlacedItem = _sim.world.grid.item(_id(&"potted_plant"))
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(item.id))
	_mode.update_origin(Vector2i(11, 9))
	assert_true(_mode.rotate())
	assert_true(_mode.commit())
	assert_eq(_move_calls, 1)
	assert_true(_sim.world.grid.item(item.id) == item)
	assert_eq(item.origin, Vector2i(11, 9))
	assert_eq(item.quarter_turns, 1)
	assert_eq(_mode.state, BuildMode.State.IDLE)
	assert_false(_mode.commit())
	assert_eq(_move_calls, 1)
	assert_eq(_cell_events, 1)
	assert_eq(_entries.size(), 0)


func test_purchase_uses_session_wrapper_and_books_exactly_once() -> void:
	var price: int = _content.item(&"chair").price
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	assert_true(_mode.commit())
	assert_eq(_buy_calls, 1)
	assert_eq(_cash, 1000 - price)
	assert_eq(_entries, [{"amount": -price, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_eq(_mode.state, BuildMode.State.IDLE)
	assert_false(_mode.commit())
	assert_eq(_buy_calls, 1)
	assert_eq(_cell_events, 1)
	assert_not_null(_sim.world.grid.item_at(Vector2i(4, 9)))


func test_refused_session_commands_keep_the_ghost_pose_and_actual_reason() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"potted_plant")))
	_mode.update_origin(Vector2i(11, 9))
	assert_true(_mode.rotate())
	var before: Dictionary = _snapshot()
	_refuse = true
	assert_false(_mode.commit())
	assert_eq(_move_calls, 1)
	assert_eq(_mode.state, BuildMode.State.MOVE)
	assert_eq(_mode.origin, Vector2i(11, 9))
	assert_eq(_mode.quarter_turns, 1)
	assert_eq(_mode.current_check.why, "Session refused move")
	assert_eq(_snapshot(), before)
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	assert_false(_mode.commit())
	assert_eq(_mode.state, BuildMode.State.BUY)
	assert_eq(_mode.selected_definition.id, &"chair")
	assert_eq(_mode.current_check.why, "Session refused buy")
	assert_eq(_snapshot(), before)


func test_sell_refusal_is_minus_one_and_retains_selection_without_refund() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"fridge")))
	assert_eq(_mode.sell_selected(), -1)
	assert_eq(_sell_calls, 0, "the actual editor keeps the last fridge")
	assert_true(_mode.current_check.why.contains("Keep at least one"))
	assert_eq(_mode.state, BuildMode.State.MOVE)
	assert_true(_mode.pick_up(_id(&"potted_plant")))
	var before: Dictionary = _snapshot()
	_refuse = true
	assert_eq(_mode.sell_selected(), -1)
	assert_eq(_sell_calls, 1)
	assert_eq(_mode.current_check.why, "Session refused sale")
	assert_true(_mode.has_ghost())
	assert_eq(_snapshot(), before)
	assert_true(_entries.is_empty())


func test_sell_uses_actual_selected_item_and_accepts_zero_without_double_booking() -> void:
	assert_true(_mode.enter())
	var plant: PlacedItem = _sim.world.grid.item(_id(&"potted_plant"))
	assert_true(_mode.pick_up(plant.id))
	_mode.update_origin(Vector2i(11, 9))
	assert_eq(_mode.sell_selected(), 7)
	assert_eq(_entries, [{"amount": 7, "category": Ledger.UPGRADES}] as Array[Dictionary])
	assert_null(_sim.world.grid.item(plant.id))
	assert_eq(_mode.state, BuildMode.State.IDLE)
	assert_eq(_mode.sell_selected(), -1)
	assert_eq(_sell_calls, 1)
	var free: ItemDef = ItemDef.new()
	free.id = &"test_free_decor"
	_content.extra[free.id] = free
	assert_true(_mode.begin_buy(free.id, Vector2i(4, 9)))
	assert_true(_mode.commit())
	assert_true(_mode.pick_up(_sim.world.grid.item_at(Vector2i(4, 9)).id))
	assert_eq(_mode.sell_selected(), 0)
	assert_eq(_mode.state, BuildMode.State.IDLE)
	assert_null(_sim.world.grid.item_at(Vector2i(4, 9)))
	assert_eq(_entries.size(), 3, "each successful buy or sale books once, including zero")
	assert_eq(_sell_calls, 2)


func test_buy_warning_zero_becomes_the_actual_committed_item_id() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"fridge", Vector2i(10, 1)))
	assert_true(_mode.current_check.ok)
	assert_true(_mode.current_check.unreachable.has(0))
	assert_eq(_mode.warning_ids(), _mode.current_check.unreachable)
	assert_true(_mode.commit(), "reachability warnings do not block a fitting purchase")
	var id: int = _sim.world.grid.item_at(Vector2i(10, 1)).id
	assert_true(id > 0)
	assert_true(_mode.committed_warning_ids.has(id))
	assert_false(_mode.committed_warning_ids.has(0))
	assert_eq(_mode.warning_ids(), _editor.check_current().unreachable)
	assert_eq(_entries.size(), 1)


func test_invalid_or_cancelled_ghost_preserves_committed_warnings_until_fixed() -> void:
	assert_true(_editor.buy(&"fridge", Vector2i(10, 1)))
	var id: int = _sim.world.grid.item_at(Vector2i(10, 1)).id
	assert_true(_mode.enter())
	var warnings: Array[int] = _editor.check_current().unreachable
	assert_true(warnings.has(id))
	assert_eq(_mode.committed_warning_ids, warnings)
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	_mode.update_origin(Vector2i(1, 1))
	assert_false(_mode.current_check.ok)
	assert_eq(_mode.warning_ids(), warnings)
	_mode.cancel()
	assert_eq(_mode.warning_ids(), warnings)
	_mode.exit()
	assert_true(_mode.enter())
	assert_eq(_mode.warning_ids(), warnings, "reentry queries the actual current shop")
	assert_true(_mode.pick_up(id))
	_mode.update_origin(Vector2i(10, 2))
	assert_true(_mode.current_check.ok)
	assert_false(_mode.current_check.unreachable.has(id))
	assert_true(_mode.commit())
	assert_false(_mode.committed_warning_ids.has(id))
	assert_eq(_mode.committed_warning_ids, _editor.check_current().unreachable)


func test_current_query_is_read_only_and_does_not_replace_last_operation_check() -> void:
	assert_true(_editor.buy(&"fridge", Vector2i(10, 1)))
	var fridge: PlacedItem = _sim.world.grid.item(_id(&"fridge"))
	assert_true(fridge.reserve(fridge.work_cells[0], 99))
	var last: EditCheck = _editor.last_check
	var before: Dictionary = _snapshot()
	var check: EditCheck = _editor.check_current()
	assert_true(check.ok)
	assert_true(check.unreachable.has(_sim.world.grid.item_at(Vector2i(10, 1)).id))
	check.unreachable.clear()
	assert_false(_editor.check_current().unreachable.is_empty(), "query arrays are independent")
	assert_true(_editor.last_check == last)
	assert_eq(fridge.reserved_by(fridge.work_cells[0]), 99)
	assert_eq(_snapshot(), before)
	_sim.world.clock.phase = SimClock.Phase.OPEN
	before = _snapshot()
	assert_true(_editor.check_current().ok, "view warnings can be queried outside an edit phase")
	assert_eq(_snapshot(), before)
	assert_true(_editor.last_check == last)


func test_topology_and_money_invalidation_refresh_the_existing_ghost() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	assert_true(_mode.current_check.ok)
	assert_true(_editor.buy(&"chair", Vector2i(4, 9)))
	_mode.refresh()
	assert_eq(_mode.state, BuildMode.State.BUY)
	assert_false(_mode.current_check.ok, "a cached preview is rechecked after a topology edit")
	_mode.update_origin(Vector2i(4, 8))
	assert_true(_mode.current_check.ok)
	_cash = 0
	_mode.refresh()
	assert_false(_mode.current_check.ok)
	assert_true(_mode.current_check.why.contains("cash"))
	assert_eq(_buy_calls, 0)
	_cash = 1000
	_mode.refresh()
	assert_true(_mode.current_check.ok)


func test_reentrant_grid_signal_cannot_commit_or_book_a_second_purchase() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	_reenter = true
	assert_true(_mode.commit())
	assert_false(_reentry_result)
	assert_eq(_buy_calls, 1)
	assert_eq(_entries.size(), 1)
	assert_eq(_cell_events, 1)
	assert_eq(_mode.state, BuildMode.State.IDLE)
	assert_eq(_mode.committed_warning_ids, _editor.check_current().unreachable)


func test_same_world_rebind_detaches_replaced_clock_and_cancels_selection() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.pick_up(_id(&"potted_plant")))
	var old_clock: SimClock = _sim.world.clock
	var new_clock: SimClock = SimClock.new()
	_sim.world.clock = new_clock
	_mode.bind_session(_editor, _sim.world, _content, _shop_move, _shop_buy, _shop_sell)
	assert_eq(_mode.state, BuildMode.State.INACTIVE)
	assert_false(_mode.has_ghost())
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	assert_true(old_clock.start_service())
	assert_true(_mode.has_ghost(), "the detached old clock cannot cancel the new interaction")
	assert_true(new_clock.start_service())
	assert_false(_mode.is_active(), "the replacement clock owns phase cancellation")
	assert_eq(_entries.size(), 0)


func test_presentation_reads_are_detached_cached_and_do_not_recheck_each_frame() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_buy(&"fridge", Vector2i(10, 1)))
	var current_queries: int = _editor.current_queries
	var buy_queries: int = _editor.buy_queries
	var before: Dictionary = _snapshot()
	for frame: int in range(12):
		var view: Dictionary = _mode.presentation_state()
		assert_true(view["definition"] == _content.item(&"fridge"))
		assert_eq(view["item_id"], -1)
		assert_true(view["unreachable"].has(0))
		view["unreachable"].clear()
		view["warning_ids"].clear()
		view["committed_warning_ids"].append(999)
		_mode.warning_ids().clear()
		_mode.update_origin(Vector2i(10, 1))
	assert_true(_mode.current_check.unreachable.has(0))
	assert_false(_mode.committed_warning_ids.has(999))
	assert_eq(_editor.current_queries, current_queries)
	assert_eq(_editor.buy_queries, buy_queries)
	assert_eq(_snapshot(), before)


func test_pickup_offset_keeps_the_grabbed_tile_and_clears_on_cancel_or_buy() -> void:
	assert_true(_mode.enter())
	var item: PlacedItem = _sim.world.grid.item(_id(&"fridge"))
	var far_side: Vector2i = item.origin + Vector2i(1, 0)
	var before: Dictionary = _snapshot()
	assert_false(_mode.pick_up_at(item.id, Vector2i(11, 9)))
	assert_eq(_mode.state, BuildMode.State.IDLE)
	assert_true(_mode.pick_up_at(item.id, far_side))
	assert_eq(_mode.grab_offset, Vector2i(1, 0))
	_mode.update_origin(far_side)
	assert_eq(_mode.origin, item.origin, "pickup and the first stationary hover do not jump")
	_mode.update_origin(far_side + Vector2i(1, 1))
	assert_eq(_mode.origin, item.origin + Vector2i(1, 1))
	assert_eq(_snapshot(), before, "the grab offset affects only the held preview")
	_mode.cancel()
	assert_eq(_mode.grab_offset, Vector2i.ZERO)
	assert_true(_mode.begin_buy(&"chair", Vector2i(4, 9)))
	_mode.update_origin(Vector2i(4, 8))
	assert_eq(_mode.origin, Vector2i(4, 8))
	assert_eq(_mode.grab_offset, Vector2i.ZERO)
	assert_eq(_snapshot(), before)


func test_far_tile_stays_fixed_through_four_rotations_of_a_two_by_one_item() -> void:
	assert_true(_mode.enter())
	var item: PlacedItem = _sim.world.grid.item(_id(&"fridge"))
	assert_eq((item.def as ItemDef).footprint, Vector2i(2, 1))
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i.ZERO, Vector2i.ZERO]
	var cursor: Vector2i = Vector2i(10, 8)
	for initial_turns: int in range(4):
		assert_true(_editor.move(item.id, item.origin, initial_turns))
		var before: Dictionary = _snapshot()
		assert_true(_mode.pick_up_at(item.id, item.origin + offsets[initial_turns]))
		_mode.update_origin(cursor)
		for step: int in range(1, 5):
			assert_true(_mode.rotate())
			var turns: int = (initial_turns + step) % 4
			assert_eq(_mode.quarter_turns, turns)
			assert_eq(_mode.grab_offset, offsets[turns])
			assert_eq(_mode.origin, cursor - offsets[turns])
			assert_eq(_mode.origin + _mode.grab_offset, cursor, "rotation preserves the world grabbed tile")
			_mode.update_origin(cursor)
			assert_eq(_mode.origin + _mode.grab_offset, cursor, "stationary hover does not undo the pivot")
			var expected: EditCheck = _editor.check_move(item.id, _mode.origin, turns)
			assert_eq(_mode.current_check.ok, expected.ok)
			assert_eq(_mode.current_check.why, expected.why)
			assert_eq(_snapshot(), before, "rotation previews never move the actual item or book a transaction")
		assert_eq(_mode.origin, cursor - offsets[initial_turns])
		_mode.cancel()
		assert_eq(_snapshot(), before)
	assert_eq(_move_calls + _buy_calls + _sell_calls, 0)


func test_all_place_results_have_player_sentences_used_by_actual_editor_checks() -> void:
	var reasons: Dictionary[int, String] = {
		SimGrid.PlaceResult.OK: "",
		SimGrid.PlaceResult.OUT_OF_BOUNDS: "Outside the shop",
		SimGrid.PlaceResult.NOT_FLOOR: "Must be placed on the floor",
		SimGrid.PlaceResult.OVERLAPS: "Something is in the way",
	}
	assert_eq(reasons.size(), SimGrid.PlaceResult.size(), "every placement result has one mapping")
	for result: int in SimGrid.PlaceResult.values():
		assert_eq(ShopEditor.placement_reason(result as SimGrid.PlaceResult), reasons[result])
	var before: Dictionary = _snapshot()
	assert_eq(_editor.check_buy(&"chair", Vector2i(-1, 0)).why, reasons[SimGrid.PlaceResult.OUT_OF_BOUNDS])
	assert_eq(_editor.check_buy(&"chair", Vector2i(0, 0)).why, reasons[SimGrid.PlaceResult.NOT_FLOOR])
	assert_eq(_editor.check_buy(&"chair", Vector2i(1, 1)).why, reasons[SimGrid.PlaceResult.OVERLAPS])
	assert_eq(_editor.check_buy(&"chair", Vector2i(4, 9)).why, reasons[SimGrid.PlaceResult.OK])
	assert_eq(_snapshot(), before)


func _id(def_id: StringName) -> int:
	return ShopBuilder.items_with_def(_sim.world, def_id)[0].id


func _snapshot() -> Dictionary:
	return {"shop": _editor.to_dict(), "cash": _cash, "entries": _entries.duplicate(true),
		"cell_events": _cell_events, "clock": _sim.world.clock.to_dict(),
		"now": _sim.world.now, "rng_state": _sim.rng.state, "rng_seed": _sim.rng.seed}


func _can_spend(amount: int) -> bool:
	return amount >= 0 and _cash >= amount


func _record_cash(amount: int, category: StringName) -> void:
	_cash += amount
	_entries.append({"amount": amount, "category": category})


func _shop_move(item_id: int, cell: Vector2i, turns: int) -> bool:
	_move_calls += 1
	if _refuse:
		_editor.last_check = EditCheck.new(false, "Session refused move")
		return false
	return _editor.move(item_id, cell, turns)


func _shop_buy(def_id: StringName, cell: Vector2i, turns: int) -> bool:
	_buy_calls += 1
	if _refuse:
		_editor.last_check = EditCheck.new(false, "Session refused buy")
		return false
	return _editor.buy(def_id, cell, turns)


func _shop_sell(item_id: int) -> int:
	_sell_calls += 1
	if _refuse:
		_editor.last_check = EditCheck.new(false, "Session refused sale")
		return -1
	return _editor.sell(item_id)


func _record_cells(_cells: Array[Vector2i]) -> void:
	_cell_events += 1
	if _reenter:
		_reenter = false
		_reentry_result = _mode.commit()
