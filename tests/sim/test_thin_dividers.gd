extends TestCase
## FK-113: the recovered kitchen row remains useful after a real legacy load.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const LEGACY_ROWS: PackedStringArray = ["##############", "#............#", "#............#",
	"#............#", "#####...######", "#............#", "#............#", "#............#",
	"#............#", "#............#", "######..######", "      EE      "]
const LEGACY_ROOMS: PackedStringArray = ["", " KKKKKKKKKKKK", " KKKKKKKKKKKK",
	" KKKKKKKKKKKK", "     KKK"]

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _cash: int


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_cash = 3000
	_install(LAYOUT)


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null


func test_default_divider_recovers_nine_kitchen_cells_and_keeps_the_pass_gap() -> void:
	_assert_default_divider(_sim.world.grid)
	for cell: Vector2i in [Vector2i(0, 4), Vector2i(13, 4), Vector2i(3, 0), Vector2i(3, 10)]:
		assert_eq(_sim.world.grid.terrain(cell), SimGrid.Terrain.WALL, "the outside shell remains thick")
	assert_eq(ShopEditor.SNAPSHOT_VERSION, 8, "v7 is reserved for furniture variants")
	var pass_item: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	assert_eq(pass_item.origin, Vector2i(5, 4), "no furniture moves to recover the divider row")
	assert_eq(pass_item.work_cells, [Vector2i(5, 3), Vector2i(5, 5)] as Array[Vector2i])
	assert_eq(_sim.world.grid.room(pass_item.work_cells[0]), SimGrid.Room.KITCHEN)
	assert_eq(_sim.world.grid.room(pass_item.work_cells[1]), SimGrid.Room.DINING)
	for problem: String in RoomRules.violations(_sim.world.grid, {} as Dictionary[int, int]):
		assert_false(problem.begins_with("pass:"), "the pass still straddles the two rooms")


func test_real_cook_and_server_handoff_still_delivers_a_paid_meal() -> void:
	assert_eq(_sim.world.grid.terrain(Vector2i(2, 4)), SimGrid.Terrain.FLOOR)
	for ingredient: IngredientDef in _content.ingredients():
		_sim.stock.add(ingredient.id, 100, 1)
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random)
	guest.eat_ticks = 3
	guest.food_patience = 5000
	var pass_item: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	var cook: StaffAgent = _staff(&"cook")
	var server: StaffAgent = _staff(&"server")
	var cook_at_pass: bool = false
	var server_at_pass: bool = false
	var ready: bool = false
	assert_true(_sim.world.clock.start_service())
	for tick: int in range(4000):
		_sim.advance()
		if guest.order != null:
			ready = ready or guest.order.state == Order.State.READY
		if cook.task != null and cook.task.kind == &"cook" and cook.step_index == cook.task.steps.size() - 1:
			cook_at_pass = cook_at_pass or cook.cell == pass_item.work_cells[0]
		if server.task != null and server.task.kind == &"deliver" and server.step_index == 1:
			server_at_pass = server_at_pass or server.cell == pass_item.work_cells[1]
		if guest.state == CustomerAgent.State.LEFT:
			break
	assert_not_null(guest.order)
	if guest.order == null:
		return
	assert_true(ready)
	assert_true(cook_at_pass, "the cook plates at the kitchen work cell")
	assert_true(server_at_pass, "the server takes that plate from the dining work cell")
	assert_eq(guest.order.state, Order.State.DELIVERED)
	assert_eq(_sim.served_today, 1)
	assert_eq(_sim.lost_today, 0)


func test_v6_save_converts_once_with_rooms_items_and_back_door_intact() -> void:
	_install(_legacy_layout())
	var door: Vector3i = Vector3i(13, 6, SimGrid.EDGE_WEST)
	assert_true(_editor.apply_segments({door: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	var old: Dictionary = _editor.to_dict()
	old["version"] = 6
	var errors: Array[String] = []
	var loaded: ShopLayout = ShopEditor.from_dict(old, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.load_notes.size(), 1, "one plain conversion note is staged for the morning log")
	_install(loaded)
	_assert_default_divider(_sim.world.grid)
	assert_true(_sim.world.grid.is_back_door(Vector2i(13, 6)))
	assert_eq(WallRules.delivery_cell(_sim.world.grid), Vector2i(12, 6))
	var converted: Dictionary = _editor.to_dict()
	assert_eq(converted["items"], old["items"], "the migration does not move or repaint furniture")
	assert_eq(int(converted["version"]), 8)
	var again: ShopLayout = ShopEditor.from_dict(converted, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(again)
	if again == null:
		return
	assert_true(again.load_notes.is_empty(), "loading the new snapshot does not convert or notify twice")
	_install(again)
	assert_eq(_editor.to_dict(), converted)


func test_legacy_kitchen_finish_and_decor_follow_the_new_face_in_the_same_room() -> void:
	_install(_legacy_layout())
	var before: Vector3i = Vector3i(2, 3, 2)
	var after: Vector3i = Vector3i(2, 4, 2)
	var faces: Array[Vector3i] = [before]
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes(faces, &"brick", &"sage", &"cream")))
	assert_true(_editor.hang(&"wall_art_sunrise", before), _editor.last_check.why)
	var old: Dictionary = _editor.to_dict()
	old["version"] = 6
	var errors: Array[String] = []
	var loaded: ShopLayout = ShopEditor.from_dict(old, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_true(loaded.wall_finishes.has(after), "the kitchen-side finish moves into the recovered row")
	assert_false(loaded.wall_finishes.has(before))
	assert_eq(loaded.wall_items.get(after), &"wall_art_sunrise")
	assert_false(loaded.wall_items.has(before))
	_install(loaded)
	assert_eq(_sim.world.grid.room(WallFaces.cell(after)), SimGrid.Room.KITCHEN)
	assert_true(WallFaces.is_face(_sim.world.grid, after))
	assert_eq(_editor.walls.finish(after).style, &"brick")
	assert_eq(_editor.walls.finish(after).swatch, &"sage")
	assert_not_null(_editor.decor.item(after))


func test_legacy_face_between_the_same_room_refunds_finish_and_decor_once_without_side_effects() -> void:
	_install(_legacy_layout())
	assert_true(_editor.apply_rooms({Vector2i(2, 5): SimGrid.Room.KITCHEN,
		Vector2i(3, 5): SimGrid.Room.KITCHEN} as Dictionary[Vector2i, int]))
	var face: Vector3i = Vector3i(3, 3, 2)
	var faces: Array[Vector3i] = [face]
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes(faces, &"brick", &"sage", &"cream")))
	assert_true(_editor.hang(&"wall_art_sunrise", face), _editor.last_check.why)
	var expected: int = floori(float(_content.wall_style(&"brick").price) / 2.0) \
		+ ShopEditor.sale_refund(_content.item(&"wall_art_sunrise"))
	var old: Dictionary = _editor.to_dict()
	old["version"] = 6
	var unchanged: Dictionary = old.duplicate(true)
	var cash: int = _cash
	var terrain: SimGrid.Terrain = _sim.world.grid.terrain(Vector2i(3, 4))
	var errors: Array[String] = []
	var loaded: ShopLayout = ShopEditor.from_dict(old, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.get("load_refund"), expected, "lost decor and finish each refund half their price")
	assert_eq(old, unchanged, "pure decoding never rewrites the supplied snapshot")
	assert_eq(_cash, cash, "pure decoding stages the refund without touching live books")
	assert_eq(_sim.world.grid.terrain(Vector2i(3, 4)), terrain, "pure decoding never changes the live grid")
	assert_not_null(_editor.decor.item(face), "the old editor is untouched until the new session installs")
	assert_false(loaded.wall_finishes.has(face))
	assert_false(loaded.wall_items.has(face))
	_install(loaded)
	assert_eq(_sim.world.grid.segment(WallFaces.edge(face)), SimGrid.Segment.NONE,
		"the two kitchen cells need no dividing wall")
	var snapshot: Dictionary = _editor.to_dict()
	var again: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(again)
	if again != null:
		assert_eq(again.get("load_refund"), 0, "a v8 reload cannot refund missing decor twice")
		assert_true(again.load_notes.is_empty())


func test_an_interior_cell_with_the_same_room_on_every_side_opens_without_a_wall() -> void:
	var old_layout: ShopLayout = _legacy_layout()
	var rows: PackedStringArray = old_layout.rows.duplicate()
	rows[8] = "#...##.......#"
	old_layout.rows = rows
	_install(old_layout)
	var face: Vector3i = Vector3i(5, 7, 2)
	var faces: Array[Vector3i] = [face]
	assert_true(_editor.apply_wall_finishes(_editor.wall_lay_changes(faces, &"stripes", &"sage", &"cream")))
	assert_true(_editor.hang(&"wall_art_sunrise", face), _editor.last_check.why)
	var refund: int = floori(float(_content.wall_style(&"stripes").price) / 2.0) \
		+ ShopEditor.sale_refund(_content.item(&"wall_art_sunrise"))
	var old: Dictionary = _editor.to_dict()
	old["version"] = 6
	var template: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	template.set("legacy_rows", rows)
	var errors: Array[String] = []
	var loaded: ShopLayout = ShopEditor.from_dict(old, template, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.get("load_refund"), refund)
	assert_false(loaded.wall_finishes.has(face))
	assert_false(loaded.wall_items.has(face))
	_install(loaded)
	var recovered: Vector2i = Vector2i(4, 8)
	assert_eq(_sim.world.grid.terrain(recovered), SimGrid.Terrain.FLOOR)
	assert_eq(_sim.world.grid.room(recovered), SimGrid.Room.DINING)
	for edge: Vector3i in SimGrid.cell_edges(recovered):
		assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.NONE)


func test_a_generic_legacy_template_without_metadata_converts_its_actual_terrain() -> void:
	var template: ShopLayout = _legacy_layout()
	template.set("legacy_rows", PackedStringArray())
	_install(template)
	var snapshot: Dictionary = _editor.to_dict()
	snapshot["version"] = 6
	var errors: Array[String] = []
	var loaded: ShopLayout = ShopEditor.from_dict(snapshot, template, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(loaded)
	if loaded == null:
		return
	_install(loaded)
	_assert_default_divider(_sim.world.grid)


func test_v3_rejected_kitchen_inference_stays_all_dining_after_divider_conversion() -> void:
	_install(_legacy_layout())
	var snapshot: Dictionary = _editor.to_dict()
	snapshot["version"] = 3
	snapshot.erase("rooms")
	(snapshot["items"] as Array).append({"def_id": "table_2", "origin": [9, 2],
		"quarter_turns": 0, "swatch_id": ""})
	var errors: Array[String] = []
	var loaded: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_true(loaded.room_map().is_empty(), "a rejected kitchen inference cannot return through migration")
	assert_true(loaded.rooms_unmarked)
	var restored: RestaurantSim = RestaurantSim.create(loaded, _content, 1, errors, null, false, true)
	assert_eq(errors, [] as Array[String])
	var grid: SimGrid = restored.world.grid
	assert_eq(grid.terrain(Vector2i(2, 4)), SimGrid.Terrain.FLOOR)
	assert_eq(grid.room(Vector2i(2, 4)), SimGrid.Room.DINING)
	assert_eq(grid.segment(Vector3i(2, 5, SimGrid.EDGE_NORTH)), SimGrid.Segment.NONE)
	var table: PlacedItem = grid.item_at(Vector2i(9, 2))
	assert_not_null(table)
	if table == null:
		return
	assert_false(DiningSeats.usable_cells(grid, table).is_empty())
	for seat: Vector2i in table.seat_cells:
		assert_eq(grid.is_guest_reachable(grid.entries()[0], seat), grid.is_reachable(grid.entries()[0], seat),
			"no discarded room inference may block a saved guest seat")


func test_v8_terrain_overrides_reject_shell_cells_duplicates_and_overlap() -> void:
	var original: Dictionary = _editor.to_dict()
	for changes: Dictionary in [
		{"thin_cells": [[0, 4]]}, {"thick_cells": [[0, 4]]},
		{"thin_cells": [[2, 4], [2, 4]]}, {"thick_cells": [[2, 4], [2, 4]]},
		{"thin_cells": [[2, 4]], "thick_cells": [[2, 4]]},
	]:
		var malformed: Dictionary = original.duplicate(true)
		malformed.merge(changes, true)
		var errors: Array[String] = []
		assert_null(ShopEditor.from_dict(malformed, LAYOUT, _content, errors))
		assert_false(errors.is_empty())
		assert_eq(_editor.to_dict(), original, "invalid terrain cannot alter the live shop")


func test_legal_window_keeps_its_only_thick_support_across_conversion_and_v8_reload() -> void:
	_install(_legacy_layout())
	var window: Vector3i = Vector3i(9, 5, SimGrid.EDGE_WEST)
	assert_true(_editor.apply_segments({window: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]),
		_editor.last_check.why)
	assert_true(WallRules.has_continuing_wall(_sim.world.grid, window))
	var old: Dictionary = _editor.to_dict()
	old["version"] = 6
	var cash: int = _cash
	var errors: Array[String] = []
	var loaded: ShopLayout = ShopEditor.from_dict(old, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.get("load_refund"), 0, "a safely retained frame is never sold by migration")
	assert_true(loaded.load_notes.size() >= 1)
	assert_eq(_cash, cash)
	_install(loaded)
	assert_eq(_sim.world.grid.segment(window), SimGrid.Segment.WINDOW)
	assert_true(WallRules.has_continuing_wall(_sim.world.grid, window), "the legal frame is still supported")
	var supports: Array[Vector2i] = []
	for cell: Vector2i in [Vector2i(8, 4), Vector2i(9, 4)]:
		if _sim.world.grid.terrain(cell) == SimGrid.Terrain.WALL:
			supports.append(cell)
	assert_false(supports.is_empty(), "at least one original full-cell wall supports the frame")
	var snapshot: Dictionary = _editor.to_dict()
	var again: ShopLayout = ShopEditor.from_dict(snapshot, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(again)
	if again == null:
		return
	assert_eq(again.get("load_refund"), 0)
	assert_true(again.load_notes.is_empty())
	_install(again)
	assert_eq(_sim.world.grid.segment(window), SimGrid.Segment.WINDOW)
	assert_true(WallRules.has_continuing_wall(_sim.world.grid, window))
	for cell: Vector2i in supports:
		assert_eq(_sim.world.grid.terrain(cell), SimGrid.Terrain.WALL, "protected terrain survives a v8 reload")
	assert_eq(_editor.to_dict(), snapshot)
	var wing: Array[Vector2i] = [Vector2i(14, 7), Vector2i(14, 8), Vector2i(14, 9)]
	assert_true(_editor.apply_floor(wing, true), _editor.last_check.why)
	assert_eq(_sim.world.grid.terrain(Vector2i(14, 8)), SimGrid.Terrain.FLOOR)
	assert_eq(_sim.world.grid.terrain(Vector2i(2, 4)), SimGrid.Terrain.FLOOR)
	assert_eq(_sim.world.grid.segment(window), SimGrid.Segment.WINDOW)
	for cell: Vector2i in supports:
		assert_eq(_sim.world.grid.terrain(cell), SimGrid.Terrain.WALL, "an unrelated expansion keeps the protected support")
	var expanded: Dictionary = _editor.to_dict()
	var expanded_layout: ShopLayout = ShopEditor.from_dict(expanded, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(expanded_layout)
	if expanded_layout != null:
		_install(expanded_layout)
		assert_eq(_sim.world.grid.terrain(Vector2i(14, 8)), SimGrid.Terrain.FLOOR)
		assert_eq(_sim.world.grid.segment(window), SimGrid.Segment.WINDOW)
		assert_true(WallRules.has_continuing_wall(_sim.world.grid, window))
		for cell: Vector2i in supports:
			assert_eq(_sim.world.grid.terrain(cell), SimGrid.Terrain.WALL)
		assert_eq(_editor.to_dict(), expanded)


func test_a_two_cell_thick_divider_joins_nearest_rooms_and_separates_them() -> void:
	var old_layout: ShopLayout = _legacy_layout()
	var rows: PackedStringArray = old_layout.rows.duplicate()
	rows[5] = "#####...######"
	old_layout.rows = rows
	_install(old_layout)
	var old: Dictionary = _editor.to_dict()
	old["version"] = 6
	var template: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	template.set("legacy_rows", rows)
	var errors: Array[String] = []
	var loaded: ShopLayout = ShopEditor.from_dict(old, template, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(loaded)
	if loaded == null:
		return
	_install(loaded)
	for x: int in [1, 2, 3, 4, 8, 9, 10, 11, 12]:
		assert_eq(_sim.world.grid.terrain(Vector2i(x, 4)), SimGrid.Terrain.FLOOR)
		assert_eq(_sim.world.grid.terrain(Vector2i(x, 5)), SimGrid.Terrain.FLOOR)
		assert_eq(_sim.world.grid.room(Vector2i(x, 4)), SimGrid.Room.KITCHEN)
		assert_eq(_sim.world.grid.room(Vector2i(x, 5)), SimGrid.Room.DINING)
		assert_eq(_sim.world.grid.segment(Vector3i(x, 5, SimGrid.EDGE_NORTH)), SimGrid.Segment.WALL)


func _assert_default_divider(grid: SimGrid) -> void:
	for x: int in range(1, 13):
		assert_eq(grid.terrain(Vector2i(x, 4)), SimGrid.Terrain.FLOOR, "row 4 cell %d is recovered floor" % x)
		assert_eq(grid.room(Vector2i(x, 4)), SimGrid.Room.KITCHEN)
		var wanted: int = SimGrid.Segment.NONE if x in [5, 6, 7] else SimGrid.Segment.WALL
		assert_eq(int(grid.segment(Vector3i(x, 5, SimGrid.EDGE_NORTH))), wanted)


func _legacy_layout() -> ShopLayout:
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	layout.rows = LEGACY_ROWS.duplicate()
	layout.room_rows = LEGACY_ROOMS.duplicate()
	layout.rooms_explicit = false
	layout.room_cells.clear()
	layout.wall_segments.clear()
	return layout


func _install(layout: ShopLayout) -> void:
	var errors: Array[String] = []
	_sim = RestaurantSim.create(layout, _content, 29015, errors)
	assert_eq(errors, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), layout)
	_editor.set_owner_level(6)


func _staff(role: StringName) -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent is StaffAgent and agent.role == role:
			return agent as StaffAgent
	return null


func _can_spend(amount: int) -> bool:
	return amount <= _cash


func _record(amount: int, _category: StringName, _note: String = "") -> void:
	_cash += amount
