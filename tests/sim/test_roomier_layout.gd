extends TestCase
## Authored geometry and snapshot staging; historical geometry is a separate resource.

const NEW: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const ORIGINAL: ShopLayout = preload("res://data/layouts/tier1_original.tres")

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func test_new_shop_has_two_cell_aisles_and_six_seats_without_moving_the_old_template() -> void:
	assert_eq(NEW.rows.size(), 13)
	assert_eq(NEW.rows[0].length(), 16)
	assert_eq(ORIGINAL.rows.size(), 12)
	assert_eq(ORIGINAL.rows[0].length(), 14)
	assert_eq(ORIGINAL.staff_spawns[&"server"], Vector2i(8, 8))
	assert_eq(ORIGINAL.rows[11], "      EE      ")
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(NEW, _content, errors)
	assert_eq(errors, [] as Array[String])
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	assert_eq(tables.size(), 3)
	var seats: Array[Vector2i] = []
	for table: PlacedItem in tables:
		seats.append_array(table.seat_cells)
	assert_eq(seats.size(), 6)
	for corridor: Rect2i in [Rect2i(4, 5, 2, 6), Rect2i(9, 5, 2, 6),
			Rect2i(4, 9, 7, 2), Rect2i(5, 5, 2, 2), Rect2i(7, 10, 2, 3)]:
		for y: int in range(corridor.position.y, corridor.end.y):
			for x: int in range(corridor.position.x, corridor.end.x):
				var cell: Vector2i = Vector2i(x, y)
				assert_true(world.grid.is_walkable(cell), "two-cell aisle at %s" % cell)
				assert_false(seats.has(cell), "a through aisle cannot be another guest's seat")
	assert_eq(world.grid.entries(), [Vector2i(7, 12), Vector2i(8, 12)] as Array[Vector2i])


func test_current_snapshot_identifies_its_base_and_rejects_wrong_or_malformed_identity() -> void:
	var editor: ShopEditor = _editor(NEW)
	var snapshot: Dictionary = editor.to_dict()
	assert_eq(snapshot["version"], 8)
	assert_eq(snapshot["layout_id"], "tier1_roomier")
	var errors: Array[String] = []
	var restored: ShopLayout = ShopEditor.from_dict(snapshot, NEW, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(restored)
	if restored != null:
		assert_eq(_editor(restored).to_dict(), snapshot)
	for wrong: Variant in [ORIGINAL.save_layout_id, "unknown", 1, [], null]:
		var malformed: Dictionary = snapshot.duplicate(true)
		malformed["layout_id"] = wrong
		errors.clear()
		assert_null(ShopEditor.from_dict(malformed, NEW, _content, errors))
		assert_false(errors.is_empty())
	assert_eq(editor.to_dict(), snapshot, "refused decoding leaves the original shop untouched")


func test_pre_roomier_v8_keeps_its_looks_and_thin_thick_base_dimensions() -> void:
	var editor: ShopEditor = _editor(ORIGINAL)
	editor.set_owner_level(3)
	assert_true(editor.paint_wall(&"sage"))
	assert_true(editor.apply_wall_finishes({Vector3i(3, 11, 0):
		FloorFinishes.Finish.new(&"brick", &"sage", &"cream")} as Dictionary[Vector3i, FloorFinishes.Finish]))
	assert_true(editor.hang(&"street_awning_2", Vector3i(6, 11, 4), null, &"clay"))
	var snapshot: Dictionary = editor.to_dict()
	assert_false(snapshot.has("layout_id"), "an original base retains its previous wire shape")
	var errors: Array[String] = []
	var restored: ShopLayout = ShopEditor.from_dict(snapshot, ORIGINAL, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(restored)
	if restored != null:
		assert_eq(_editor(restored).to_dict(), snapshot)
		assert_eq(restored.rows, ORIGINAL.rows)
		assert_eq(restored.staff_spawns, ORIGINAL.staff_spawns)
		assert_eq(ShopFootprint.from_layout(restored).lot, ShopFootprint.from_layout(ORIGINAL).lot)
	var terrain: ShopLayout = ThinDividers.prepare({"version": 8,
		"thin_cells": [[1, 4]], "thick_cells": [[2, 4]]}, ORIGINAL, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(terrain)
	if terrain != null:
		assert_eq(terrain.rows.size(), 12)
		assert_eq(terrain.rows[0].length(), 14)
		assert_eq(terrain.rows[4][1], ".")
		assert_eq(terrain.rows[4][2], "#")
		assert_eq(terrain.thin_cells, [Vector2i(1, 4)] as Array[Vector2i])
		assert_eq(terrain.thick_cells, [Vector2i(2, 4)] as Array[Vector2i])


func test_versions_one_to_seven_use_original_thick_terrain_and_preserve_item_positions() -> void:
	var thick: ShopLayout = ORIGINAL.duplicate(true) as ShopLayout
	thick.rows = ORIGINAL.legacy_rows.duplicate()
	thick.room_rows = PackedStringArray(["", " KKKKKKKKKKKK", " KKKKKKKKKKKK", " KKKKKKKKKKKK", "     KKK"])
	thick.wall_segments.clear()
	var snapshot: Dictionary = _editor(thick).to_dict()
	for version: int in [1, 3, 6, 7]:
		var old: Dictionary = snapshot.duplicate(true)
		old["version"] = version
		if version < 4:
			old.erase("rooms")
		var errors: Array[String] = []
		var restored: ShopLayout = ShopEditor.from_dict(old, ORIGINAL, _content, errors)
		assert_eq(errors, [] as Array[String], "original-base version %d" % version)
		assert_not_null(restored)
		if restored == null:
			continue
		assert_eq(restored.rows.size(), ORIGINAL.rows.size())
		assert_eq(restored.rows[0].length(), ORIGINAL.rows[0].length())
		assert_eq(restored.legacy_rows, ORIGINAL.legacy_rows)
		assert_eq(restored.staff_spawns, ORIGINAL.staff_spawns)
		assert_eq(ShopFootprint.from_layout(restored).lot, ShopFootprint.from_layout(ORIGINAL).lot)
		assert_eq(_editor(restored).to_dict()["items"], snapshot["items"])


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
