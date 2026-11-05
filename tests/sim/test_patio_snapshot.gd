extends TestCase
## Version 9 stages purchased pavement before validating outdoor items, keeps
## room identity tied to ownership, and never mutates a running shop on decode.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _ledger: Ledger
var _changes: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 17, errors)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = 1000
	_changes = 0
	_editor = ShopEditor.new(_sim, _content, _books(), LAYOUT)
	_editor.set_owner_level(6)
	_sim.world.grid.cells_changed.connect(_cells_changed)


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null
	_ledger = null


func test_json_round_trip_keeps_outdoor_items_paint_finishes_and_sorted_ownership() -> void:
	var cells: Array[Vector2i] = _left_patio()
	cells.reverse()
	assert_true(_editor.apply_patio(cells, true), _editor.last_check.why)
	assert_true(_editor.buy(&"patio_table_2", _street(-4, 1)), _editor.last_check.why)
	# The table's built-in seats are (1, 13) and (4, 13). This extra chair
	# faces north from (2, 14) to the unclaimed south edge at (2, 13).
	assert_true(_editor.buy(&"patio_chair", _street(-4, 3)), _editor.last_check.why)
	# In the far corner: at (-6, 0) its seats would wall the pocket behind the
	# table off, since nobody walks through a seat.
	assert_true(_editor.buy(&"patio_waiting_bench", _street(-7, 0)), _editor.last_check.why)
	var table: PlacedItem = _sim.world.grid.item_at(_street(-4, 1))
	var bench: PlacedItem = _sim.world.grid.item_at(_street(-7, 0))
	assert_not_null(table)
	assert_not_null(bench)
	if table == null or bench == null:
		return
	assert_true(_editor.paint_variant(table.id, &"patio_dark_metal"))
	assert_true(_editor.paint_item(bench.id, &"sage"))
	assert_true(_editor.paint_wall(&"clay"))
	assert_true(_editor.paint_floor(&"honey"))
	assert_true(_editor.apply_flooring(_editor.lay_changes([_street(-1, 0)] as Array[Vector2i],
		&"herringbone", &"sage")), _editor.last_check.why)
	var expected: Dictionary = _editor.to_dict()
	assert_eq(expected["version"], 9)
	var ownership: Array[Array] = []
	for cell: Vector2i in _left_patio():
		ownership.append([cell.x, cell.y])
	assert_eq(expected["patio"], ownership, "wire order is row-major regardless of purchase order")
	var cash: int = _ledger.cash
	var entries: int = _ledger.entries_for_day(1).size()
	var changes: int = _changes
	var document: Dictionary = JSON.parse_string(JSON.stringify(expected))
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(document, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	if layout == null:
		return
	assert_eq(layout.patio_cells, _left_patio())
	var restored: RestaurantSim = RestaurantSim.create(layout, _content, 17, errors, null, true, true)
	assert_eq(errors, [] as Array[String])
	var copy: ShopEditor = ShopEditor.new(restored, _content, _books(), layout)
	assert_eq(copy.to_dict(), expected)
	assert_eq(restored.world.clock.phase, SimClock.Phase.MORNING)
	assert_eq(restored.world.now, 0)
	assert_eq(restored.world.grid.entries(), [_street(0, 0), _street(1, 0)] as Array[Vector2i])
	assert_eq(ShopBuilder.items_with_def(restored.world, &"patio_table_2").size(), 1)
	assert_eq(ShopBuilder.items_with_def(restored.world, &"patio_waiting_bench").size(), 1)
	assert_eq(ShopBuilder.items_with_def(restored.world, &"patio_chair").size(), 1)
	for cell: Vector2i in layout.patio_cells:
		assert_true(restored.world.grid.is_outdoor_floor(cell))
		assert_eq(restored.world.grid.room(cell), SimGrid.Room.PATIO)
	assert_eq(restored.world.grid.item_at(_street(-4, 1)).variant_id, &"patio_dark_metal")
	assert_eq(restored.world.grid.item_at(_street(-7, 0)).swatch_id, &"sage")
	assert_eq(_editor.to_dict(), expected, "building the staged session leaves the live shop alone")
	assert_eq(_ledger.cash, cash)
	assert_eq(_ledger.entries_for_day(1).size(), entries, "restoring never replays purchases")
	assert_eq(_changes, changes)
	assert_true(LAYOUT.patio_cells.is_empty(), "the shared template is never filled with saved ownership")


func test_version_nine_requires_strict_patio_ownership_and_rejects_bad_items_transactionally() -> void:
	var base: Dictionary = _editor.to_dict()
	for ownership: Variant in ["patio", null, {}, [[5]], [_row(-1, 0), _row(-1, 0)],
		[[5, "11"]], [[5.5, 11]], [[NAN, 11]], [_row(-1, 4)], [_row(0, 0)], [_row(-1, -1)]]:
		var data: Dictionary = base.duplicate(true)
		data["patio"] = ownership
		_reject(data, str(ownership))
	var missing: Dictionary = base.duplicate(true)
	missing.erase("patio")
	_reject(missing, "version 9 requires the ownership array")
	var unknown: Dictionary = base.duplicate(true)
	(unknown["items"] as Array).append({"def_id": "unknown_patio_table", "origin": _row(-1, 0), "quarter_turns": 0})
	_reject(unknown, "unknown saved furniture")
	var unowned: Dictionary = base.duplicate(true)
	(unowned["items"] as Array).append({"def_id": "patio_chair", "origin": _row(-1, 0), "quarter_turns": 0})
	_reject(unowned, "outdoor furniture needs purchased pavement")


func test_saved_patio_rooms_must_match_ownership_in_both_directions() -> void:
	assert_true(_editor.apply_patio([_street(-1, 0)] as Array[Vector2i], true), _editor.last_check.why)
	var base: Dictionary = _editor.to_dict()
	var missing: Dictionary = base.duplicate(true)
	var missing_rooms: Array = missing["rooms"]
	for index: int in range(missing_rooms.size() - 1, -1, -1):
		var row: Array = missing_rooms[index]
		if row[0] == _street(-1, 0).x and row[1] == _street(-1, 0).y:
			missing_rooms.remove_at(index)
	_reject(missing, "owned pavement cannot silently turn into dining floor")
	var changed: Dictionary = base.duplicate(true)
	for row: Array in changed["rooms"]:
		if row[0] == _street(-1, 0).x and row[1] == _street(-1, 0).y:
			row[2] = "storage"
	_reject(changed, "owned pavement cannot be a staff-only room")
	var extra: Dictionary = base.duplicate(true)
	(extra["rooms"] as Array).append([11, 8, "patio"])
	_reject(extra, "a patio room inside the shell does not create ownership")
	var unknown: Dictionary = base.duplicate(true)
	(unknown["rooms"] as Array).append([11, 8, "unknown_patio"])
	_reject(unknown, "unknown room kinds are refused")


func test_version_eight_without_patio_rebuilds_the_default_shop_unchanged() -> void:
	var current: Dictionary = _editor.to_dict()
	var legacy: Dictionary = current.duplicate(true)
	legacy["version"] = 8
	legacy.erase("patio")
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(legacy, LAYOUT, _content, errors)
	assert_not_null(layout)
	assert_eq(errors, [] as Array[String])
	if layout == null:
		return
	assert_true(layout.patio_cells.is_empty())
	var world: SimWorld = ShopBuilder.build(layout, _content, errors, true)
	assert_eq(errors, [] as Array[String])
	assert_eq(world.grid.bounds, _sim.world.grid.bounds)
	assert_eq(world.grid.rooms(), _sim.world.grid.rooms())
	assert_eq(world.grid.entries(), _sim.world.grid.entries())
	assert_eq(world.grid.items().size(), _sim.world.grid.items().size())
	for cell: Vector2i in _sim.world.grid.cells():
		assert_eq(world.grid.terrain(cell), _sim.world.grid.terrain(cell), str(cell))
		assert_eq(world.grid.is_walkable(cell), _sim.world.grid.is_walkable(cell), str(cell))
	var restored: RestaurantSim = RestaurantSim.new()
	restored.world = world
	var copy: ShopEditor = ShopEditor.new(restored, _content, _books(), layout)
	assert_eq(copy.to_dict(), current, "only the schema version and empty patio field are added")
	assert_eq(_ledger.entries_for_day(1).size(), 0)
	assert_eq(_changes, 0)


func test_versions_one_to_eight_ignore_future_ownership_and_cannot_restore_outdoor_items() -> void:
	var legacy_layout: ShopLayout = LegacyTier1Layout.make()
	var errors: Array[String] = []
	var old_sim: RestaurantSim = RestaurantSim.new()
	old_sim.world = ShopBuilder.build(legacy_layout, _content, errors)
	assert_eq(errors, [] as Array[String])
	var old_editor: ShopEditor = ShopEditor.new(old_sim, _content, _books(), legacy_layout)
	var old_base: Dictionary = old_editor.to_dict()
	var current: Dictionary = _editor.to_dict()
	for version: int in range(1, 9):
		var data: Dictionary = (current if version == 8 else old_base).duplicate(true)
		data["version"] = version
		data["patio"] = [_row(-1, 0)]
		if version < 2:
			data.erase("walls")
		if version < 3:
			data.erase("floor")
		if version < 4:
			data.erase("rooms")
		if version < 5:
			data.erase("floors")
			data.erase("floor_style_id")
		if version < 6:
			data.erase("wall_style_id")
			data.erase("wall_finishes")
			data.erase("wall_items")
		errors.clear()
		var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
		assert_eq(errors, [] as Array[String], "version %d" % version)
		assert_not_null(layout, "version %d" % version)
		if layout != null:
			assert_true(layout.patio_cells.is_empty(), "version %d never grants patio ownership" % version)
		var outdoor: Dictionary = data.duplicate(true)
		(outdoor["items"] as Array).append({"def_id": "patio_chair", "origin": _row(-1, 0), "quarter_turns": 0})
		_reject(outdoor, "version %d has no purchased pavement for outdoor items" % version)
	assert_eq(_editor.to_dict(), current)
	assert_eq(_ledger.cash, 1000)
	assert_eq(_ledger.entries_for_day(1).size(), 0)
	assert_eq(_changes, 0)


func _reject(data: Dictionary, label: String) -> void:
	var before: Dictionary = _editor.to_dict()
	var input: Dictionary = data.duplicate(true)
	var cash: int = _ledger.cash
	var changes: int = _changes
	var entries: int = _ledger.entries_for_day(1).size()
	var errors: Array[String] = []
	assert_null(ShopEditor.from_dict(data, LAYOUT, _content, errors), label)
	assert_false(errors.is_empty(), label)
	assert_eq(_editor.to_dict(), before, label)
	# NaN does not equal itself; every other document can be compared directly.
	if not str(input).contains("nan"):
		assert_eq(data, input, "the decoder does not rewrite the supplied document")
	assert_eq(_ledger.cash, cash, label)
	assert_eq(_ledger.entries_for_day(1).size(), entries, label)
	assert_eq(_changes, changes, label)
	assert_true(LAYOUT.patio_cells.is_empty(), label)


func _left_patio() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row: int in range(_street(0, 0).y, _street(0, 0).y + LAYOUT.patio_depth):
		for column: int in range(0, _street(0, 0).x):
			cells.append(Vector2i(column, row))
	return cells


func _books() -> ShopEditBooks:
	return ShopEditBooks.new(_can_spend, _record)


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)


func _cells_changed(_cells: Array[Vector2i]) -> void:
	_changes += 1


func _street(x: int, y: int) -> Vector2i:
	return _sim.world.grid.entries()[0] + Vector2i(x, y)


func _row(x: int, y: int) -> Array[int]:
	var cell: Vector2i = _street(x, y)
	return [cell.x, cell.y]
