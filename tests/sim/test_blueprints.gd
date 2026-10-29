extends TestCase
## FK-045: whole-group placement, rotations, exact history and durable library.

const START_CASH: int = 10000

var _content: ContentDB
var _sim: RestaurantSim
var _grid: SimGrid
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger
var _notifications: Array[int] = []
var _reenter: bool = false
var _reentry_accepted: bool = false
var _need: Dictionary[int, int] = {}


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_grid = SimGrid.new(Vector2i(20, 20))
	_grid.set_terrain(Vector2i(0, 10), SimGrid.Terrain.ENTRY)
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(_grid)
	_ledger = Ledger.new()
	_ledger.cash = START_CASH
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record))
	_editor.set_owner_level(20)
	_history = ShopEditHistory.new(_editor, _grid)
	_grid.cells_changed.connect(_changed)


func after_each() -> void:
	_grid.cells_changed.disconnect(_changed)
	_history = null
	_editor = null
	_sim = null
	_grid = null
	_ledger = null
	_content = null


func test_blocked_last_entry_is_atomic_including_ids_version_signals_and_history() -> void:
	var blueprint: Blueprint = _plants()
	var blocker: PlacedItem = _grid.place_def(_content.item(&"potted_plant"), Vector2i(6, 5))
	_notifications.clear()
	var before: Dictionary = _editor.to_dict()
	var version: int = _grid.version
	var next_id: int = int(_grid.get("_next_id"))
	assert_false(_editor.check_stamp(blueprint, Vector2i(5, 5)).ok)
	assert_false(_history.stamp(blueprint, Vector2i(5, 5)))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_grid.version, version)
	assert_eq(int(_grid.get("_next_id")), next_id)
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(_ledger.entries_for_day(1).size(), 0)
	assert_eq(_history.undo_count(), 0)
	assert_eq(_history.redo_count(), 0)
	assert_true(_notifications.is_empty())
	assert_true(_grid.item(blocker.id) == blocker)
	assert_null(_grid.item_at(Vector2i(5, 5)))


func test_group_money_check_uses_total_not_individually_affordable_items() -> void:
	var blueprint: Blueprint = _plants()
	_ledger.cash = _content.item(&"potted_plant").price
	var before: Dictionary = _editor.to_dict()
	assert_false(_history.stamp(blueprint, Vector2i(5, 5)))
	assert_eq(_editor.last_check.why, ShopEditBooks.CASH_REFUSAL)
	assert_eq(_ledger.cash, _content.item(&"potted_plant").price)
	assert_eq(_editor.to_dict(), before)
	assert_true(_notifications.is_empty())
	assert_true(_ledger.entries_for_day(1).is_empty())


func test_one_stamp_books_each_item_but_one_undo_refunds_exactly() -> void:
	var blueprint: Blueprint = _plants()
	blueprint.entries[0].swatch_id = &"sage"
	var before: Dictionary = _editor.to_dict()
	assert_true(_history.stamp(blueprint, Vector2i(5, 5)), _editor.last_check.why)
	assert_eq(_history.undo_count(), 1)
	assert_eq(_editor.last_stamp_ids.size(), 2)
	assert_eq(_ledger.cash, START_CASH - blueprint.total_price(_content))
	assert_eq(_editor.last_cash_change, -blueprint.total_price(_content))
	var lines: Array[Dictionary] = _ledger.entries_for_day(1)
	assert_eq(lines.size(), 2)
	assert_eq(int(lines[0]["amount"]), -_content.item(&"potted_plant").price)
	assert_eq(int(lines[1]["amount"]), -_content.item(&"potted_plant").price)
	assert_eq(_grid.item(_editor.last_stamp_ids[0]).swatch_id, &"sage")
	assert_eq(_notifications, [2] as Array[int], "observers see the complete group once")
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, START_CASH)
	assert_eq(int(_ledger.day_totals(1).get(Ledger.UPGRADES, 0)), 0)
	assert_eq(_ledger.entries_for_day(1).back()["note"], ShopEditHistory.UNDO_NOTE)
	assert_eq(_notifications, [2, 0] as Array[int])
	assert_eq(_history.undo_count(), 0)
	assert_eq(_history.redo_count(), 1)
	# History owns a copy; editing/deleting a library entry cannot alter redo.
	blueprint.entries.clear()
	blueprint.display_name = "Changed"
	assert_true(_history.redo(), _history.last_refusal)
	assert_eq(_grid.items().size(), 2)
	assert_eq(_grid.item_at(Vector2i(5, 5)).swatch_id, &"sage")
	assert_eq(_ledger.cash, START_CASH - 2 * _content.item(&"potted_plant").price)
	assert_eq(_ledger.entries_for_day(1).back()["note"], ShopEditHistory.REDO_NOTE)


func test_stamp_refs_follow_later_sell_restore_move_undo_and_redo() -> void:
	assert_true(_history.stamp(_plants(), Vector2i(5, 5)))
	var first_id: int = _editor.last_stamp_ids[0]
	assert_true(_history.move(first_id, Vector2i(7, 5), 1))
	assert_true(_history.sell(first_id) >= 0)
	assert_true(_history.undo(), _history.last_refusal)
	var restored: PlacedItem = _grid.item_at(Vector2i(7, 5))
	assert_not_null(restored)
	if restored == null:
		return
	assert_ne(restored.id, first_id)
	assert_true(_history.undo(), _history.last_refusal)
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH)
	assert_true(_grid.items().is_empty())
	assert_true(_history.redo(), _history.last_refusal)
	assert_true(_history.redo(), _history.last_refusal)
	assert_not_null(_grid.item_at(Vector2i(7, 5)))
	assert_true(_history.redo(), _history.last_refusal)
	assert_null(_grid.item_at(Vector2i(7, 5)))
	assert_eq(_grid.items().size(), 1)


func test_non_square_and_already_rotated_footprints_rotate_as_one_group_four_ways() -> void:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Turned rugs"
	blueprint.entries = [_entry(&"rug_rectangle", Vector2i.ZERO, 1),
		_entry(&"rug_rectangle", Vector2i(3, 1), 0)]
	var originals: Array[Array] = []
	var size: Vector2i = Vector2i(7, 4)
	for entry: ShopPlacement in blueprint.entries:
		var cells: Array[Vector2i] = []
		var footprint: Vector2i = GridMath.rotated_footprint(_content.item(entry.item_id).footprint, entry.quarter_turns)
		for y: int in footprint.y:
			for x: int in footprint.x:
				cells.append(entry.origin + Vector2i(x, y))
		originals.append(cells)
	for turns: int in 4:
		assert_true(_history.stamp(blueprint, Vector2i(5, 5), turns), _editor.last_check.why)
		for index: int in blueprint.entries.size():
			var expected: Array[Vector2i] = []
			for cell: Vector2i in originals[index]:
				expected.append(Vector2i(5, 5) + GridMath.rotate_cell(cell, size, turns))
			var placed: PlacedItem = _grid.item(_editor.last_stamp_ids[index])
			assert_eq(placed.quarter_turns, posmod(blueprint.entries[index].quarter_turns + turns, 4))
			assert_eq(placed.cells.size(), expected.size())
			for cell: Vector2i in expected:
				assert_true(placed.cells.has(cell), "turn %d item %d must cover %s" % [turns, index, cell])
		assert_true(_history.undo(), _history.last_refusal)
		assert_eq(_ledger.cash, START_CASH)


func test_chair_before_table_and_rug_share_one_final_preview_in_all_rotations() -> void:
	var blueprint: Blueprint = _dining_group()
	for turns: int in 4:
		assert_true(_editor.check_stamp(blueprint, Vector2i(5, 5), turns).ok)
		assert_true(_history.stamp(blueprint, Vector2i(5, 5), turns), _editor.last_check.why)
		var chair: PlacedItem = _grid.item(_editor.last_stamp_ids[0])
		var table: PlacedItem = _grid.item(_editor.last_stamp_ids[1])
		assert_eq(_grid.dining_table_id(chair.origin), table.id)
		assert_eq(_grid.dining_furnishing_id(chair.origin), chair.id)
		assert_eq(_grid.items_at(table.origin).size(), 2, "rug and furniture can overlap")
		assert_true(_history.undo(), _history.last_refusal)
		assert_true(_grid.items().is_empty())
		assert_eq(_ledger.cash, START_CASH)


func test_room_rule_rejects_whole_group_when_chair_is_in_kitchen() -> void:
	var rooms: Dictionary[Vector2i, int] = {Vector2i(5, 6): SimGrid.Room.KITCHEN}
	_grid.set_rooms(rooms)
	_notifications.clear()
	var before: Dictionary = _editor.to_dict()
	assert_false(_history.stamp(_dining_group(), Vector2i(5, 5)))
	assert_eq(_editor.last_check.why, RoomRules.SEAT_IN_KITCHEN)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, START_CASH)
	assert_true(_notifications.is_empty())
	assert_eq(_history.undo_count(), 0)


func test_closed_only_and_unlock_refusals_leave_group_and_history_untouched() -> void:
	for phase: SimClock.Phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		_sim.world.clock.phase = phase
		assert_false(_editor.check_stamp(_plants(), Vector2i(5, 5)).ok)
		assert_false(_history.stamp(_plants(), Vector2i(5, 5)))
		assert_true(_grid.items().is_empty())
		assert_eq(_ledger.cash, START_CASH)
	_sim.world.clock.phase = SimClock.Phase.MORNING
	_editor.set_owner_level(1)
	assert_false(_history.stamp(_dining_group(), Vector2i(5, 5)))
	assert_true(_editor.last_check.why.begins_with("Unlocks at level"))
	assert_eq(_history.undo_count(), 0)
	assert_eq(_ledger.cash, START_CASH)


func test_invalid_bounds_internal_overlap_and_wall_block_are_atomic() -> void:
	var blueprint: Blueprint = _plants()
	assert_false(_history.stamp(blueprint, Vector2i(19, 19)))
	blueprint.entries[1].origin = Vector2i.ZERO
	assert_false(_history.stamp(blueprint, Vector2i(5, 5)))
	assert_eq(_editor.last_check.why, "Something is in the way")
	var rug: Blueprint = Blueprint.new()
	rug.display_name = "Rug"
	rug.entries = [_entry(&"rug_rectangle", Vector2i.ZERO)]
	_grid.set_segments({Vector3i(6, 5, SimGrid.EDGE_WEST): SimGrid.Segment.WALL} as Dictionary[Vector3i, int])
	_notifications.clear()
	var before: Dictionary = _editor.to_dict()
	assert_false(_history.stamp(rug, Vector2i(5, 5)))
	assert_eq(_editor.last_check.why, "A wall is in the way")
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, START_CASH)
	assert_true(_notifications.is_empty())


func test_refused_redo_keeps_stacks_and_cash_without_partial_group() -> void:
	assert_true(_history.stamp(_plants(), Vector2i(5, 5)))
	assert_true(_history.undo())
	_grid.place_def(_content.item(&"potted_plant"), Vector2i(6, 5))
	_notifications.clear()
	var before: Dictionary = _editor.to_dict()
	assert_false(_history.redo())
	assert_eq(_history.undo_count(), 0)
	assert_eq(_history.redo_count(), 1)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, START_CASH)
	assert_true(_notifications.is_empty())


func test_reserved_member_refuses_undo_of_entire_stamp() -> void:
	assert_true(_history.stamp(_dining_group(), Vector2i(5, 5)), _editor.last_check.why)
	var chair: PlacedItem = _grid.item(_editor.last_stamp_ids[0])
	var table: PlacedItem = _grid.item(_editor.last_stamp_ids[1])
	assert_true(table.reserve(chair.origin, 7))
	_notifications.clear()
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	assert_false(_history.undo())
	assert_eq(_history.undo_count(), 1)
	assert_eq(_history.redo_count(), 0)
	assert_eq(_ledger.cash, cash)
	assert_eq(_editor.to_dict(), before)
	assert_eq(table.reserved_by(chair.origin), 7)
	assert_true(_notifications.is_empty())
	assert_true(table.release(chair.origin, 7))
	assert_true(_history.undo(), _history.last_refusal)


func test_editor_reentry_during_group_notification_is_refused() -> void:
	_reenter = true
	assert_true(_history.stamp(_plants(), Vector2i(5, 5)))
	assert_false(_reentry_accepted)
	assert_true(_editor.last_check.ok, "nested refusals cannot replace the successful outer result")
	assert_eq(_grid.items().size(), 2)
	assert_eq(_notifications, [2] as Array[int])
	assert_eq(_ledger.cash, START_CASH - _plants().total_price(_content))


func test_undo_checks_combined_storage_not_only_each_shelf() -> void:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Shelves"
	blueprint.entries = [_entry(&"storage_shelf", Vector2i.ZERO), _entry(&"storage_shelf", Vector2i(2, 0))]
	assert_true(_history.stamp(blueprint, Vector2i(5, 5)), _editor.last_check.why)
	_editor.storage_need = _storage_need
	_need[StorageSpace.DRY] = _content.item(&"storage_shelf").storage_units
	# Each shelf could be sold alone, but undo must not discard all capacity.
	for id: int in _editor.last_stamp_ids:
		assert_true(_editor.check_sell(id).ok)
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	_notifications.clear()
	assert_false(_history.undo())
	assert_eq(_history.last_refusal, StorageSpace.removal_refusal(StorageSpace.DRY))
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_eq(_history.undo_count(), 1)
	assert_true(_notifications.is_empty())
	_need.clear()
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH)


func test_undo_non_storage_group_ignores_unrelated_existing_stock_overflow() -> void:
	assert_true(_history.stamp(_plants(), Vector2i(5, 5)))
	_editor.storage_need = _storage_need
	_need[StorageSpace.FREEZER] = 1
	for id: int in _editor.last_stamp_ids:
		assert_true(_editor.check_sell(id).ok, "ordinary sells do not inspect unrelated storage")
	assert_true(_history.undo(), _history.last_refusal)
	assert_eq(_ledger.cash, START_CASH)
	assert_true(_grid.items().is_empty())


func test_undo_cannot_remove_all_required_equipment_as_one_group() -> void:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Cold storage"
	blueprint.entries = [_entry(&"fridge", Vector2i.ZERO), _entry(&"fridge", Vector2i(3, 0))]
	assert_true(_history.stamp(blueprint, Vector2i(5, 5)), _editor.last_check.why)
	for id: int in _editor.last_stamp_ids:
		assert_true(_editor.check_sell(id).ok, "each fridge alone has a replacement")
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	_notifications.clear()
	assert_false(_history.undo())
	assert_eq(_history.last_refusal, "Keep at least one fridge")
	assert_eq(_history.undo_count(), 1)
	assert_eq(_history.redo_count(), 0)
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_true(_notifications.is_empty())


func test_low_level_group_preflight_never_consumes_ids_or_notifies_on_failure() -> void:
	var entries: Array[ShopPlacement] = [_entry(&"potted_plant", Vector2i(5, 5)),
		_entry(&"potted_plant", Vector2i(5, 5))]
	var definitions: Array[ItemDef] = [_content.item(&"potted_plant"), _content.item(&"potted_plant")]
	var version: int = _grid.version
	var next_id: int = int(_grid.get("_next_id"))
	assert_true(_grid.place_group(definitions, entries).is_empty())
	assert_eq(_grid.version, version)
	assert_eq(int(_grid.get("_next_id")), next_id)
	assert_true(_grid.items().is_empty())
	assert_true(_notifications.is_empty())
	var item: PlacedItem = _grid.place_def(definitions[0], Vector2i(5, 5))
	_notifications.clear()
	version = _grid.version
	assert_false(_grid.remove_group([item.id, item.id] as Array[int]))
	assert_false(_grid.remove_group([item.id, -1] as Array[int]))
	assert_true(_grid.item(item.id) == item)
	assert_false(item.removed)
	assert_eq(_grid.version, version)
	assert_true(_notifications.is_empty())


func test_structural_content_is_rejected_and_unknown_only_library_group_is_skipped() -> void:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Not furniture"
	blueprint.entries = [_entry(&"door", Vector2i.ZERO)]
	assert_false(_history.stamp(blueprint, Vector2i(5, 5)))
	assert_eq(_editor.last_check.why, CatalogueText.BLUEPRINT_CONTENT)
	var saved: Dictionary = {"version": 1, "blueprints": [{"name": "Old content", "entries": [
		{"item_id": "missing_forever", "offset": [0, 0], "rotation": 0, "swatch_id": ""}]}]}
	var library: BlueprintLibrary = BlueprintLibrary.new()
	var notes: Array[String] = []
	assert_true(library.restore(saved, _content, notes))
	assert_true(library.blueprints.is_empty())
	assert_eq(notes.size(), 1)
	assert_true(notes[0].contains("missing_forever"))


func test_capture_is_detached_and_excludes_door_and_preserves_rug_and_swatch() -> void:
	var first: PlacedItem = _grid.place_def(_content.item(&"potted_plant"), Vector2i(8, 9), 2)
	first.swatch_id = &"sage"
	var rug: PlacedItem = _grid.place_def(_content.item(&"rug_rectangle"), Vector2i(7, 8), 1)
	var door: PlacedItem = _grid.place_def(_content.item(&"door"), Vector2i(1, 1))
	assert_not_null(door)
	if door == null:
		return
	var blueprint: Blueprint = Blueprint.capture(_grid, [rug.id, door.id, first.id] as Array[int], "  Plants  ")
	assert_eq(blueprint.display_name, "Plants")
	assert_eq(blueprint.entries.size(), 2)
	assert_eq(blueprint.entries[0].origin, Vector2i(1, 1))
	assert_eq(blueprint.entries[0].quarter_turns, 2)
	assert_eq(blueprint.entries[0].swatch_id, &"sage")
	assert_eq(blueprint.entries[1].origin, Vector2i.ZERO)
	first.swatch_id = &"honey"
	assert_eq(blueprint.entries[0].swatch_id, &"sage")
	assert_eq(blueprint.total_price(_content), _content.item(&"potted_plant").price + _content.item(&"rug_rectangle").price)


func test_library_roundtrip_rename_delete_and_unknown_item_skip() -> void:
	var library: BlueprintLibrary = BlueprintLibrary.new()
	var blueprint: Blueprint = _plants()
	blueprint.entries[0].swatch_id = &"sage"
	assert_true(library.add(blueprint))
	assert_true(library.rename(blueprint, "  Green corner  "))
	assert_eq(blueprint.display_name, "Green corner")
	var saved: Dictionary = library.to_dict()
	# JSON's float decoding is part of the save/load contract.
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved)) as Dictionary
	var restored: BlueprintLibrary = BlueprintLibrary.new()
	var notes: Array[String] = []
	assert_true(restored.restore(decoded, _content, notes))
	assert_eq(restored.to_dict(), saved)
	assert_true(notes.is_empty())
	var rows: Array = decoded["blueprints"]
	var entries: Array = rows[0]["entries"]
	entries.append({"item_id": "removed_old_item", "offset": [2, 0], "rotation": 0, "swatch_id": ""})
	assert_true(restored.restore(decoded, _content, notes))
	assert_eq(restored.blueprints[0].entries.size(), 2)
	assert_eq(notes.size(), 1)
	assert_true(notes[0].contains("removed_old_item"))
	assert_true(library.remove(blueprint))
	assert_true(library.blueprints.is_empty())
	assert_false(library.remove(blueprint))
	assert_eq(restored.blueprints.size(), 1, "libraries own independent restored values")


func test_malformed_library_restore_is_transactional_and_drops_unknown_swatch() -> void:
	var library: BlueprintLibrary = BlueprintLibrary.new()
	assert_true(library.add(_plants()))
	var before: Dictionary = library.to_dict()
	var malformed: Dictionary = before.duplicate(true)
	var rows: Array = malformed["blueprints"]
	var entries: Array = rows[0]["entries"]
	entries[1]["rotation"] = 1.5
	var notes: Array[String] = []
	assert_false(library.restore(malformed, _content, notes))
	assert_eq(library.to_dict(), before)
	assert_true(notes.is_empty())
	entries[1]["rotation"] = 0
	entries[1]["swatch_id"] = "removed_colour"
	assert_true(library.restore(malformed, _content, notes))
	assert_eq(library.blueprints[0].entries[1].swatch_id, &"")
	assert_false(library.rename(library.blueprints[0], "  "))
	assert_false(library.rename(library.blueprints[0], "line\nbreak"))


func _plants() -> Blueprint:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Plant pair"
	blueprint.entries = [_entry(&"potted_plant", Vector2i.ZERO), _entry(&"potted_plant", Vector2i(1, 0))]
	return blueprint


func _dining_group() -> Blueprint:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Table and rug"
	blueprint.entries = [_entry(&"chair", Vector2i(0, 1)),
		_entry(&"cross_table", Vector2i.ZERO), _entry(&"rug_rectangle", Vector2i.ZERO)]
	return blueprint


func _entry(id: StringName, offset: Vector2i, turns: int = 0) -> ShopPlacement:
	var entry: ShopPlacement = ShopPlacement.new()
	entry.item_id = id
	entry.origin = offset
	entry.quarter_turns = turns
	return entry


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)


func _changed(_cells: Array[Vector2i]) -> void:
	_notifications.append(_grid.items().size())
	if _reenter:
		_reentry_accepted = _editor.stamp(_plants(), Vector2i(12, 12))


func _storage_need() -> Dictionary[int, int]:
	return _need.duplicate()
