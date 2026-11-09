extends TestCase
## #389: the deeper starter dining room and the Build-mode aisle pinch warning.

const DEEPER: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")
const ROOMIER: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null


func test_deeper_room_is_three_rows_deeper_with_the_same_kitchen_and_lot() -> void:
	assert_eq(DEEPER.rows.size(), ROOMIER.rows.size() + 3)
	assert_eq(DEEPER.rows[0].length(), ROOMIER.rows[0].length())
	assert_eq(DEEPER.rows[DEEPER.rows.size() - 1], "       EE       ")
	assert_eq(DEEPER.room_rows, ROOMIER.room_rows, "the kitchen is unchanged")
	assert_eq(DEEPER.wall_segments, ROOMIER.wall_segments)
	for field: String in ["lot_west", "lot_east", "lot_north", "floor_cell_price", "patio_depth",
			"patio_cell_price", "pantry_units"]:
		assert_eq(DEEPER.get(field), ROOMIER.get(field), field)
	assert_eq(DEEPER.save_layout_id, &"tier1_deeper")
	assert_eq(ROOMIER.save_layout_id, &"tier1_roomier")


func test_deeper_default_room_has_two_cell_aisles_on_its_used_routes() -> void:
	_start(DEEPER)
	var grid: SimGrid = _sim.world.grid
	assert_eq(ShopBuilder.items_with_def(_sim.world, &"table_2").size(), 3)
	assert_false(AisleRules.route_cells(grid).is_empty())
	assert_eq(AisleRules.pinches(grid), [] as Array[Vector2i])
	var seats: Dictionary[Vector2i, bool] = {}
	for placed: PlacedItem in grid.items():
		for cell: Vector2i in placed.seat_cells:
			seats[cell] = true
	# The pass approach, the lane below the tables, the gaps between them and
	# the door lane are all two clear cells wide.
	for corridor: Rect2i in [Rect2i(1, 5, 14, 2), Rect2i(1, 11, 14, 2), Rect2i(5, 7, 2, 4),
			Rect2i(9, 7, 2, 4), Rect2i(7, 13, 2, 3)]:
		for y: int in range(corridor.position.y, corridor.end.y):
			for x: int in range(corridor.position.x, corridor.end.x):
				var cell: Vector2i = Vector2i(x, y)
				assert_true(grid.is_walkable(cell), "aisle cell %s" % cell)
				assert_false(seats.has(cell), "aisle cell %s is not a seat" % cell)
	assert_true(_editor.check_current().seat_warnings.is_empty())


func test_deeper_room_fits_five_tables_without_a_pinch() -> void:
	_start(DEEPER)
	for origin: Vector2i in [Vector2i(2, 13), Vector2i(11, 13)]:
		assert_true(_editor.buy(&"table_2", origin, 0), _editor.last_check.why)
		assert_eq(_editor.last_check.aisle_pinches, [] as Array[Vector2i], "table at %s" % origin)
	assert_eq(ShopBuilder.items_with_def(_sim.world, &"table_2").size(), 5)
	assert_eq(AisleRules.pinches(_sim.world.grid), [] as Array[Vector2i])
	assert_true(_editor.check_current().unreachable.is_empty())


func test_a_one_cell_pinch_on_a_used_route_warns_and_highlights_its_cell() -> void:
	_start(DEEPER)
	# Two plants either side of the left door lane leave one cell to walk in by.
	assert_true(_editor.buy(&"potted_plant", Vector2i(6, 14)), _editor.last_check.why)
	assert_eq(_editor.last_check.aisle_pinches, [] as Array[Vector2i], "the lane is still two wide")
	var check: EditCheck = _editor.check_buy(&"potted_plant", Vector2i(8, 14))
	assert_true(check.ok, "a pinch warns, never refuses")
	assert_eq(check.aisle_pinches, [Vector2i(7, 14)] as Array[Vector2i])
	assert_eq(check.aisle_id, 0, "the warning is on the proposed plant")
	assert_eq(check.seat_warnings.get(0, ""), AisleRules.WARNING)
	assert_true(_editor.buy(&"potted_plant", Vector2i(8, 14)), _editor.last_check.why)
	var plant: int = _editor.last_item_id
	var after: EditCheck = _editor.check_current()
	assert_eq(after.aisle_pinches, [Vector2i(7, 14)] as Array[Vector2i], "kept after the commit")
	assert_eq(after.seat_warnings.get(plant, ""), AisleRules.WARNING)
	# The next layout change clears the remembered warning.
	assert_true(_editor.move(plant, Vector2i(10, 14), 0), _editor.last_check.why)
	assert_eq(_editor.last_check.aisle_pinches, [] as Array[Vector2i])
	assert_eq(_editor.check_current().aisle_pinches, [] as Array[Vector2i])
	assert_false(_editor.check_current().seat_warnings.has(plant))


func test_a_dead_end_no_route_uses_is_never_flagged() -> void:
	_start(DEEPER)
	# A plant one cell off the south-west corner leaves a one-cell pocket at
	# (1,14) between it and the wall: nobody's route goes there.
	var check: EditCheck = _editor.check_buy(&"potted_plant", Vector2i(2, 14))
	assert_true(check.ok)
	assert_true(AisleRules.is_pinch(_preview_with(&"potted_plant", Vector2i(2, 14)), Vector2i(1, 14), {}),
		"the pocket is one cell wide")
	assert_eq(check.aisle_pinches, [] as Array[Vector2i])
	assert_false(check.seat_warnings.has(0))


func test_an_older_squeeze_is_not_blamed_on_an_unrelated_edit() -> void:
	_start(ROOMIER)
	# The 7-row room's pass corner already squeezes between the pass and a seat.
	assert_eq(AisleRules.pinches(_sim.world.grid), [Vector2i(7, 5)] as Array[Vector2i])
	assert_true(_editor.check_current().seat_warnings.is_empty(), "an old layout gains no warning")
	var check: EditCheck = _editor.check_buy(&"potted_plant", Vector2i(1, 11))
	assert_true(check.ok)
	assert_eq(check.aisle_pinches, [] as Array[Vector2i])


func test_a_stamp_puts_the_warning_on_the_entry_nearest_the_pinch() -> void:
	_start(DEEPER)
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Two plants"
	var left: ShopPlacement = ShopPlacement.new()
	left.item_id = &"potted_plant"
	left.origin = Vector2i.ZERO
	var right: ShopPlacement = ShopPlacement.new()
	right.item_id = &"potted_plant"
	right.origin = Vector2i(2, 0)
	blueprint.entries = [left, right]
	var check: EditCheck = _editor.check_stamp(blueprint, Vector2i(6, 14))
	assert_true(check.ok, check.why)
	assert_eq(check.aisle_pinches, [Vector2i(7, 14)] as Array[Vector2i])
	assert_eq(check.seat_warnings.get(check.aisle_id, ""), AisleRules.WARNING)
	assert_true(_editor.stamp(blueprint, Vector2i(6, 14)), _editor.last_check.why)
	assert_eq(_editor.check_current().aisle_pinches, [Vector2i(7, 14)] as Array[Vector2i])


func test_old_roomier_snapshot_loads_its_own_size_and_never_the_deeper_one() -> void:
	_start(ROOMIER)
	var snapshot: Dictionary = _editor.to_dict()
	assert_eq(snapshot["layout_id"], "tier1_roomier")
	var errors: Array[String] = []
	var restored: ShopLayout = ShopEditor.from_dict(snapshot, ROOMIER, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(restored)
	if restored != null:
		assert_eq(restored.rows, ROOMIER.rows)
		assert_eq(restored.save_layout_id, &"tier1_roomier")
		assert_eq(restored.staff_spawns, ROOMIER.staff_spawns)
	errors.clear()
	assert_null(ShopEditor.from_dict(snapshot, DEEPER, _content, errors), "a roomier save is not a deeper one")
	assert_false(errors.is_empty())
	_start(DEEPER)
	var deeper: Dictionary = _editor.to_dict()
	assert_eq(deeper["layout_id"], "tier1_deeper")
	errors.clear()
	assert_null(ShopEditor.from_dict(deeper, ROOMIER, _content, errors))


func _start(layout: ShopLayout) -> void:
	var errors: Array[String] = []
	_sim = RestaurantSim.create(layout, _content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), layout)
	_editor.set_owner_level(5)


func _preview_with(id: StringName, origin: Vector2i) -> SimGrid:
	var preview: SimGrid = _sim.world.grid.terrain_copy()
	for placed: PlacedItem in _sim.world.grid.items():
		preview.place_def(placed.def as ItemDef, placed.origin, placed.quarter_turns)
	preview.place_def(_content.item(id), origin, 0)
	return preview


func _can_spend(_amount: int) -> bool:
	return true


func _record(_amount: int, _category: StringName, _note: String = "") -> void:
	pass
