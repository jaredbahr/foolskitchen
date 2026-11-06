extends TestCase

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _observed_grid: SimGrid
var _notifications: int = 0
var _saw_unmarked_floor: bool = false


func test_authored_strip_reserves_the_street_approach() -> void:
	var patio: PatioArea = PatioArea.from_layout(LAYOUT)
	assert_eq(patio.area, Rect2i(0, _street(0, 0).y, LAYOUT.rows[0].length(), LAYOUT.patio_depth))
	assert_eq(patio.cell_price, 15)
	assert_eq(patio.cells().size(), (LAYOUT.rows[0].length() - SimGrid.from_ascii(LAYOUT.rows).entries().size()) * LAYOUT.patio_depth)
	assert_true(patio.can_hold(_street(-1, 0)))
	assert_true(patio.can_hold(_street(2, 3)))
	assert_false(patio.can_hold(_street(0, 0)))
	assert_false(patio.can_hold(_street(1, 3)))
	assert_false(patio.can_hold(_street(-1, -1)))
	assert_false(patio.can_hold(_street(-1, 4)))


func test_empty_ownership_and_older_layouts_do_not_change_the_grid() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var before: Rect2i = grid.bounds
	var version: int = grid.version
	assert_true(PatioArea.from_layout(LAYOUT).apply(grid, []))
	assert_eq(grid.bounds, before)
	assert_eq(grid.version, version)
	var older: ShopLayout = ShopLayout.new()
	older.rows = LAYOUT.rows.duplicate()
	var patio: PatioArea = PatioArea.from_layout(older)
	assert_eq(patio.cells(), [] as Array[Vector2i])
	assert_true(patio.apply(grid, older.patio_cells))
	assert_eq(grid.bounds, before)
	assert_false(grid.is_outdoor_floor(_street(-1, 0)))


func test_purchase_and_removal_preserve_entries_and_indoor_shell() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var patio: PatioArea = PatioArea.from_layout(LAYOUT)
	var entries: Array[Vector2i] = grid.entries()
	assert_true(patio.apply(grid, patio.cells()))
	assert_eq(grid.entries(), entries)
	assert_true(grid.is_guest_reachable(_street(0, 0), _street(-5, 3)))
	assert_true(grid.is_reachable(Vector2i(8, 8), _street(6, 3)))
	assert_eq(grid.terrain(_street(-1, -1)), SimGrid.Terrain.WALL)
	assert_eq(grid.terrain(_street(0, 1)), SimGrid.Terrain.OUTSIDE)
	assert_true(patio.apply(grid, []))
	assert_eq(grid.entries(), entries)
	for cell: Vector2i in patio.cells():
		assert_eq(grid.terrain(cell), SimGrid.Terrain.OUTSIDE)
		assert_false(grid.is_outdoor_floor(cell))


func test_ownership_changes_publish_only_complete_patio_rooms() -> void:
	_observed_grid = SimGrid.from_ascii(LAYOUT.rows)
	_observed_grid.cells_changed.connect(_observe_patio)
	var patio: PatioArea = PatioArea.from_layout(LAYOUT)
	assert_true(patio.apply(_observed_grid, patio.cells()))
	assert_eq(_notifications, 1)
	assert_false(_saw_unmarked_floor)
	_observed_grid.cells_changed.disconnect(_observe_patio)
	_observed_grid = null


func _observe_patio(changed: Array[Vector2i]) -> void:
	_notifications += 1
	for cell: Vector2i in changed:
		if _observed_grid.terrain(cell) == SimGrid.Terrain.FLOOR and not _observed_grid.is_outdoor_floor(cell):
			_saw_unmarked_floor = true


func test_invalid_ownership_refuses_before_growing_or_changing_terrain() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var patio: PatioArea = PatioArea.from_layout(LAYOUT)
	var before: Rect2i = grid.bounds
	var version: int = grid.version
	assert_false(patio.apply(grid, [_street(-1, 3), _street(0, 3)]))
	assert_eq(grid.bounds, before)
	assert_eq(grid.version, version)
	assert_false(patio.apply(grid, [_street(-1, 3), _street(-1, 3)]))
	assert_eq(grid.bounds, before)


func test_decoder_sorts_and_rejects_duplicate_reserved_or_fractional_cells() -> void:
	var patio: PatioArea = PatioArea.from_layout(LAYOUT)
	var errors: Array[String] = []
	assert_eq(patio.decode([[float(_street(2, 1).x), float(_street(2, 1).y)], _row(-1, 0)], errors), [_street(-1, 0), _street(2, 1)] as Array[Vector2i])
	assert_eq(errors, [] as Array[String])
	for malformed: Variant in [[_row(-1, 0), _row(-1, 0)], [_row(0, 1)], [[5.5, 11]], [[5, 11, 1]], "bad", [[INF, 11]]]:
		errors.clear()
		assert_eq(patio.decode(malformed, errors), [] as Array[Vector2i])
		assert_false(errors.is_empty())


func test_outdoor_scope_covers_rotated_footprint_work_and_seat_cells() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(6, 6))
	var outdoor: ItemDef = _outdoor()
	assert_eq(grid.can_place_def(outdoor, Vector2i(2, 2)), SimGrid.PlaceResult.OUTDOOR_ONLY)
	assert_true(grid.set_rooms({Vector2i(2, 2): SimGrid.Room.PATIO, Vector2i(3, 2): SimGrid.Room.PATIO}))
	assert_eq(grid.can_place_def(outdoor, Vector2i(2, 2)), SimGrid.PlaceResult.OUTDOOR_ONLY, "seat also needs patio")
	assert_true(grid.set_rooms({Vector2i(2, 3): SimGrid.Room.PATIO}))
	assert_eq(grid.can_place_def(outdoor, Vector2i(2, 2)), SimGrid.PlaceResult.OK)
	assert_eq(grid.can_place_def(outdoor, Vector2i(2, 2), 1), SimGrid.PlaceResult.OUTDOOR_ONLY)
	assert_true(grid.set_rooms({Vector2i(1, 2): SimGrid.Room.PATIO}))
	assert_eq(grid.can_place_def(outdoor, Vector2i(2, 2), 1), SimGrid.PlaceResult.OK)


func test_indoor_items_cannot_use_patio_but_definitionless_placement_is_unchanged() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(6, 6))
	var indoor: ItemDef = _outdoor()
	indoor.outdoor_only = false
	assert_eq(grid.can_place_def(indoor, Vector2i(2, 2)), SimGrid.PlaceResult.OK)
	assert_true(grid.set_rooms({Vector2i(3, 2): SimGrid.Room.PATIO}))
	assert_eq(grid.can_place_def(indoor, Vector2i(2, 2)), SimGrid.PlaceResult.INDOOR_ONLY, "work cell touches patio")
	assert_true(grid.set_rooms({Vector2i(3, 2): SimGrid.Room.DINING, Vector2i(2, 3): SimGrid.Room.PATIO}))
	assert_eq(grid.can_place_def(indoor, Vector2i(2, 2)), SimGrid.PlaceResult.INDOOR_ONLY, "seat touches patio")
	assert_true(grid.set_rooms({Vector2i(2, 2): SimGrid.Room.PATIO}))
	assert_null(grid.place_def(indoor, Vector2i(2, 2)))
	assert_not_null(grid.place(Vector2i.ONE, Vector2i(2, 2), 0, false))


func test_direct_definition_placement_move_and_groups_enforce_outdoor_scope() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var patio: PatioArea = PatioArea.from_layout(LAYOUT)
	assert_true(patio.apply(grid, patio.cells()))
	var outdoor: ItemDef = _outdoor()
	assert_null(grid.place(outdoor.footprint, Vector2i(2, 2), 0, outdoor.solid,
		outdoor.work_cells, outdoor.seat_cells, outdoor))
	var placed: PlacedItem = grid.place_def(outdoor, _street(-4, 1))
	assert_not_null(placed)
	if placed == null:
		return
	assert_false(grid.relocate_def(placed.id, Vector2i(2, 2), 0))
	assert_eq(placed.origin, _street(-4, 1))
	assert_true(grid.relocate_def(placed.id, _street(-3, 1), 0))
	var placement: ShopPlacement = ShopPlacement.new()
	placement.origin = Vector2i(2, 2)
	var before_version: int = grid.version
	assert_eq(grid.place_group([outdoor], [placement]), [] as Array[PlacedItem])
	assert_eq(grid.items().size(), 1)
	assert_eq(grid.version, before_version)


func test_removing_occupied_or_authored_access_patio_is_transactional() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var patio: PatioArea = PatioArea.from_layout(LAYOUT)
	assert_true(patio.apply(grid, patio.cells()))
	var placed: PlacedItem = grid.place_def(_outdoor(), _street(-4, 1))
	assert_not_null(placed)
	var before: int = grid.version
	assert_false(patio.apply(grid, []))
	var remaining: Array[Vector2i] = patio.cells()
	remaining.erase(_street(-3, 1))
	assert_false(patio.apply(grid, remaining), "authored work spot must remain patio")
	remaining = patio.cells()
	remaining.erase(_street(-4, 2))
	assert_false(patio.apply(grid, remaining), "authored seat must remain patio")
	assert_eq(grid.version, before)
	assert_true(grid.is_outdoor_floor(_street(-3, 1)))


func test_indoor_expansion_preserves_occupied_patio_and_exterior_windows() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var patio: PatioArea = PatioArea.from_layout(LAYOUT)
	assert_true(patio.apply(grid, patio.cells()))
	var placed: PlacedItem = grid.place_def(_outdoor(), _street(-4, 1))
	assert_not_null(placed)
	var footprint: ShopFootprint = ShopFootprint.from_layout(LAYOUT)
	var bought: Dictionary[Vector2i, bool] = {}
	for y: int in range(5, 10):
		bought[Vector2i(-1, y)] = true
	assert_eq(footprint.problem(bought), "")
	assert_true(footprint.apply(grid, bought))
	assert_true(grid.is_outdoor_floor(_street(-4, 1)))
	assert_true(grid.item_at(_street(-4, 1)) == placed)
	assert_eq(WallRules.street_side(grid), Vector2i.DOWN)
	assert_eq(WallRules.outer_side(grid, Vector3i(_street(-1, -1).x, _street(-1, -1).y, SimGrid.EDGE_NORTH)), Vector2i.DOWN)
	assert_eq(WallRules.back_door_side(grid, Vector3i(_street(-1, -1).x, _street(-1, -1).y, SimGrid.EDGE_NORTH)), Vector2i.ZERO)
	assert_false(WallRules.door_cells(grid).has(_street(-1, 0)))


func test_street_direction_ignores_patio_beside_a_rotated_door() -> void:
	var layout: ShopLayout = ShopLayout.new()
	layout.rows = PackedStringArray(["##### ", "#...# ", "#....E", "#...# ", "##### "])
	layout.patio_depth = 4
	var grid: SimGrid = SimGrid.from_ascii(layout.rows)
	var patio: PatioArea = PatioArea.from_layout(layout)
	assert_eq(patio.area, Rect2i(5, 0, 4, 5))
	assert_false(patio.can_hold(Vector2i(5, 2)))
	assert_true(patio.apply(grid, patio.cells()))
	assert_eq(WallRules.street_side(grid), Vector2i.RIGHT)
	assert_eq(WallRules.door_cells(grid).size(), 1)


func test_builder_applies_patio_before_outdoor_furniture_without_repainting_it() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	layout.patio_cells = PatioArea.from_layout(layout).cells()
	var placement: ShopPlacement = ShopPlacement.new()
	placement.item_id = &"patio_table_2"
	placement.origin = _street(-4, 1)
	layout.placements.append(placement)
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(layout, content, errors)
	assert_eq(errors, [] as Array[String])
	assert_true(world.grid.is_outdoor_floor(_street(-4, 1)))
	assert_eq(ShopBuilder.items_with_def(world, &"patio_table_2").size(), 1)


func test_unbought_patio_keeps_the_same_authored_world_as_an_older_layout() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var older: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	older.patio_depth = 0
	older.patio_cell_price = 0
	var errors: Array[String] = []
	var current: SimWorld = ShopBuilder.build(LAYOUT, content, errors)
	var legacy: SimWorld = ShopBuilder.build(older, content, errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(current.grid.bounds, legacy.grid.bounds)
	assert_eq(current.grid.entries(), legacy.grid.entries())
	assert_eq(current.grid.rooms(), legacy.grid.rooms())
	for cell: Vector2i in legacy.grid.cells():
		assert_eq(current.grid.terrain(cell), legacy.grid.terrain(cell))
	assert_eq(current.grid.items().size(), legacy.grid.items().size())
	for index: int in legacy.grid.items().size():
		var now: PlacedItem = current.grid.items()[index]
		var before: PlacedItem = legacy.grid.items()[index]
		assert_eq(now.cells, before.cells)
		assert_eq(now.seat_cells, before.seat_cells)
		assert_eq(now.work_cells, before.work_cells)


func _outdoor() -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"test_outdoor"
	definition.outdoor_only = true
	definition.solid = false
	definition.work_cells = [Vector2i.RIGHT]
	definition.seat_cells = [Vector2i.DOWN]
	return definition


func _street(x: int, y: int) -> Vector2i:
	return SimGrid.from_ascii(LAYOUT.rows).entries()[0] + Vector2i(x, y)


func _row(x: int, y: int) -> Array[int]:
	var cell: Vector2i = _street(x, y)
	return [cell.x, cell.y]
