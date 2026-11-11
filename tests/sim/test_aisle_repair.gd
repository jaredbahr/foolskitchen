extends TestCase
## #320: older shops whose staff can't reach the kitchen without walking
## through seats get the blocking tables moved once, on load.

const ORIGINAL: ShopLayout = preload("res://data/layouts/tier1_original.tres")
const DEEPER: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


## Where the repair puts the original layout's tables: the west one turned
## where it stood, the others as they were.
const REPAIRED: Array[Array] = [[Vector2i(2, 6), 1], [Vector2i(6, 6), 0], [Vector2i(10, 6), 0]]


func test_template_holds_the_repaired_tables() -> void:
	_assert_tables(ORIGINAL, REPAIRED)
	assert_eq(AisleRepair.repair(ORIGINAL.duplicate() as ShopLayout, _content), 0)


func test_original_layout_is_cut_off_for_real_people() -> void:
	var blocked: ShopLayout = _blocked_original()
	var grid: SimGrid = _grid(blocked)
	assert_eq(AisleRepair.cut_off(grid, false).keys(), [], "walking across seats reaches everything")
	var cut: Array = AisleRepair.cut_off(grid, true).keys()
	assert_true(cut.size() >= 5, "the pass and the kitchen stations are behind the row of seats")
	var pass_counter: PlacedItem = ShopBuilder.items_with_def(ShopBuilder.build(blocked, _content, [] as Array[String]),
		&"pass_counter")[0]
	assert_true(cut.has("item:%d" % pass_counter.id))


func test_original_table_row_turns_one_table_and_keeps_every_seat() -> void:
	var layout: ShopLayout = _blocked_original()
	var shared: Array[ShopPlacement] = layout.placements.duplicate()
	var before: ShopLayout = layout.duplicate() as ShopLayout
	assert_eq(AisleRepair.repair(layout, _content), 1, "the fewest moves")
	assert_eq(layout.aisle_moved, 1)
	_assert_tables(layout, REPAIRED)
	for index: int in layout.placements.size():
		assert_eq(layout.placements[index].item_id, shared[index].item_id, "the placement order stays")
		if index != 4:
			assert_true(layout.placements[index] == shared[index], "only the west table moves")
	assert_eq(before.placements, shared, "a shallow copy sharing the array keeps its own placements")
	assert_eq(shared[4].quarter_turns, 0, "the placements it shared are untouched")
	var grid: SimGrid = _grid(layout)
	assert_eq(AisleRepair.cut_off(grid, true).keys(), [], "everyone can reach everything walking as people do")
	var seats: int = 0
	for table: PlacedItem in ShopBuilder.items_with_def(ShopBuilder.build(layout, _content, [] as Array[String]), &"table_2"):
		seats += DiningSeats.usable_cells(grid, table).size()
	assert_eq(seats, 6, "every seat stays usable")
	for role: StringName in layout.staff_spawns:
		assert_true(grid.is_walkable(layout.staff_spawns[role]), "%s still starts on open floor" % role)
	assert_eq(AisleRepair.repair(layout, _content), 0, "a repaired shop needs nothing more")


func test_moved_items_keep_their_look() -> void:
	var layout: ShopLayout = _blocked_original()
	for index: int in layout.placements.size():
		if layout.placements[index].item_id == &"table_2":
			var copy: ShopPlacement = layout.placements[index].duplicate() as ShopPlacement
			copy.variant_id = &"look_%d" % index
			copy.swatch_id = &"clay"
			layout.placements[index] = copy
	assert_eq(AisleRepair.repair(layout, _content), 1)
	assert_eq(layout.placements[4].quarter_turns, 1)
	for index: int in layout.placements.size():
		if layout.placements[index].item_id == &"table_2":
			assert_eq(layout.placements[index].variant_id, StringName("look_%d" % index))
			assert_eq(layout.placements[index].swatch_id, &"clay")


func test_the_search_is_fixed_and_ignores_the_base() -> void:
	var first: ShopLayout = _blocked_original()
	var second: ShopLayout = _blocked_original()
	second.save_layout_id = &"elsewhere"
	assert_eq(AisleRepair.repair(first, _content), 1)
	assert_eq(AisleRepair.repair(second, _content), 1)
	for index: int in first.placements.size():
		assert_eq(second.placements[index].origin, first.placements[index].origin, "the search never changes")
		assert_eq(second.placements[index].quarter_turns, first.placements[index].quarter_turns)


func test_a_table_pushed_into_the_aisle_moves_the_least() -> void:
	# The repaired layout with the west table shoved one cell east, into the
	# lane by the pass: one short move opens a way again.
	var layout: ShopLayout = ORIGINAL.duplicate() as ShopLayout
	layout.placements = ORIGINAL.placements.duplicate()
	var copy: ShopPlacement = layout.placements[4].duplicate() as ShopPlacement
	copy.origin = Vector2i(3, 6)
	layout.placements[4] = copy
	assert_false(AisleRepair.cut_off(_grid(layout), true).is_empty(), "the shove blocks the way")
	assert_eq(AisleRepair.repair(layout, _content), 1)
	assert_eq(AisleRepair.cut_off(_grid(layout), true).keys(), [])
	var moved: ShopPlacement = layout.placements[4]
	assert_eq(absi(moved.origin.x - 3) + absi(moved.origin.y - 6) + (0 if moved.quarter_turns == 1 else 1), 1,
		"one cell or one turn")
	assert_true(layout.placements[5] == ORIGINAL.placements[5], "the other tables stay")
	assert_true(layout.placements[6] == ORIGINAL.placements[6])


## Load time (#320 review): a big messy shop, two rows of loose chairs
## across the deeper starter room, has many movable items and no fix the
## editor would accept. The search stays inside its budget, counted in tries
## and full checks rather than wall time, and leaves the shop alone.
func test_a_fruitless_search_stays_inside_its_budget() -> void:
	var layout: ShopLayout = DEEPER.duplicate() as ShopLayout
	layout.placements = DEEPER.placements.duplicate()
	for y: int in [12, 13]:
		for x: int in range(1, 15):
			var chair: ShopPlacement = ShopPlacement.new()
			chair.item_id = &"chair"
			chair.origin = Vector2i(x, y)
			layout.placements.append(chair)
	var before: Array[ShopPlacement] = layout.placements.duplicate()
	assert_false(AisleRepair.cut_off(_grid(layout), true).is_empty(), "the chairs shut the kitchen off")
	assert_eq(AisleRepair.repair(layout, _content), 0)
	assert_true(AisleRepair.last_tries <= AisleRepair.MAX_TRIES, "tries %d" % AisleRepair.last_tries)
	assert_true(AisleRepair.last_checks <= AisleRepair.MAX_CHECKS, "checks %d" % AisleRepair.last_checks)
	assert_eq(layout.placements, before, "nothing moves")
	assert_eq(layout.aisle_moved, 0)


func test_the_original_row_needs_few_tries() -> void:
	assert_eq(AisleRepair.repair(_blocked_original(), _content), 1)
	assert_true(AisleRepair.last_tries <= 40, "tries %d" % AisleRepair.last_tries)
	assert_true(AisleRepair.last_checks <= 5, "checks %d" % AisleRepair.last_checks)


func test_a_shop_people_can_walk_is_left_alone() -> void:
	var layout: ShopLayout = DEEPER.duplicate() as ShopLayout
	assert_eq(AisleRepair.repair(layout, _content), 0)
	assert_eq(layout.aisle_moved, 0)
	assert_eq(layout.placements, DEEPER.placements)


func test_version_nine_original_snapshot_repairs_once_and_round_trips() -> void:
	var editor: ShopEditor = _editor(_blocked_original())
	var snapshot: Dictionary = editor.to_dict()
	assert_eq(int(snapshot["version"]), 10)
	var old: Dictionary = snapshot.duplicate(true)
	old["version"] = 9
	var errors: Array[String] = []
	var restored: ShopLayout = ShopEditor.from_dict(old, ORIGINAL, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(restored)
	if restored == null:
		return
	assert_eq(restored.aisle_moved, 1)
	_assert_tables(restored, REPAIRED)
	var saved: Dictionary = _editor(restored).to_dict()
	assert_eq(int(saved["version"]), ShopEditor.SNAPSHOT_VERSION)
	var reloaded: ShopLayout = ShopEditor.from_dict(saved, ORIGINAL, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(reloaded)
	if reloaded == null:
		return
	assert_eq(reloaded.aisle_moved, 0, "the note is for the first morning only")
	assert_eq(_editor(reloaded).to_dict(), saved, "the repaired shop round-trips")
	# A current snapshot is never repaired again, even if seats block the way.
	var current: ShopLayout = ShopEditor.from_dict(snapshot, ORIGINAL, _content, errors)
	assert_not_null(current)
	if current != null:
		assert_eq(current.aisle_moved, 0)
		_assert_tables(current, AisleRepair.ORIGINAL_TABLES)


## The original template as saves before #320 hold it: the three tables in
## one row whose seats shut the kitchen off.
func _blocked_original() -> ShopLayout:
	var layout: ShopLayout = ORIGINAL.duplicate() as ShopLayout
	layout.placements = ORIGINAL.placements.duplicate()
	var table: int = 0
	for index: int in layout.placements.size():
		if layout.placements[index].item_id != &"table_2":
			continue
		var copy: ShopPlacement = layout.placements[index].duplicate() as ShopPlacement
		copy.origin = AisleRepair.ORIGINAL_TABLES[table][0]
		copy.quarter_turns = AisleRepair.ORIGINAL_TABLES[table][1]
		layout.placements[index] = copy
		table += 1
	return layout


func _assert_tables(layout: ShopLayout, expected: Array[Array]) -> void:
	var tables: Array[ShopPlacement] = _tables(layout)
	assert_eq(tables.size(), expected.size())
	for index: int in mini(tables.size(), expected.size()):
		assert_eq(tables[index].origin, expected[index][0], "table %d" % index)
		assert_eq(tables[index].quarter_turns, expected[index][1], "table %d" % index)


func _tables(layout: ShopLayout) -> Array[ShopPlacement]:
	var out: Array[ShopPlacement] = []
	for placement: ShopPlacement in layout.placements:
		if placement.item_id == &"table_2":
			out.append(placement)
	return out


func _grid(layout: ShopLayout) -> SimGrid:
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(layout, _content, errors, true)
	assert_eq(errors, [] as Array[String])
	return world.grid


func _editor(layout: ShopLayout) -> ShopEditor:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = ShopBuilder.build(layout, _content, errors)
	assert_eq(errors, [] as Array[String])
	return ShopEditor.new(sim, _content, ShopEditBooks.new(_can_spend, _record), layout)


func _can_spend(_amount: int) -> bool:
	return true


func _record(_amount: int, _category: StringName, _note: String = "") -> void:
	pass
