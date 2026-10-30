extends TestCase
## FK-114: exterior finishes and mounts preserve the inside wall contract.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
## Face coordinates name the cell looking into its wall, on either side.
const FRONT_FACE: Vector3i = Vector3i(3, 11, 0)
const INSIDE_FACE: Vector3i = Vector3i(3, 9, 2)
const OUTSIDE_NEON: Vector3i = Vector3i(8, 11, 0)
const WINDOW_EDGE: Vector3i = Vector3i(10, 10, SimGrid.EDGE_NORTH)
const WINDOW_SLOT: Vector3i = Vector3i(10, 9, 2)

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _ledger: Ledger


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 240, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = 3000
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func after_each() -> void:
	_history = null
	_editor = null
	_sim = null
	_content = null
	_ledger = null


func test_existing_wall_finish_check_accepts_the_street_outside_face() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_eq(grid.terrain(Vector2i(3, 10)), SimGrid.Terrain.WALL)
	assert_eq(grid.terrain(WallFaces.cell(FRONT_FACE)), SimGrid.Terrain.OUTSIDE)
	var inside: Dictionary[Vector3i, FloorFinishes.Finish] = {
		INSIDE_FACE: FloorFinishes.Finish.new(&"brick", &"sage", &"cream")}
	assert_true(_editor.check_wall_finishes(inside).ok, "the existing inside finish remains legal")
	var before: Dictionary = _editor.to_dict()
	var outside: Dictionary[Vector3i, FloorFinishes.Finish] = {
		FRONT_FACE: FloorFinishes.Finish.new(&"brick", &"sage", &"cream")}
	var check: EditCheck = _editor.check_wall_finishes(outside)
	assert_true(check.ok, "a solid street-facing outside wall accepts a finish: " + check.why)
	assert_eq(check.cost, _content.wall_style(&"brick").price)
	assert_eq(check.refund, 0)
	assert_eq(_editor.to_dict(), before, "checking an outside finish is read-only")


func test_existing_neon_check_accepts_outside_beside_door_and_keeps_window_control() -> void:
	assert_true(_editor.apply_segments({WINDOW_EDGE: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]),
		_editor.last_check.why)
	assert_true(WallFaces.is_window(_sim.world.grid, WINDOW_SLOT))
	var window: EditCheck = _editor.check_hang(&"neon_open_sign", WINDOW_SLOT)
	assert_true(window.ok, "the existing neon window mount stays legal: " + window.why)
	var before: Dictionary = _editor.to_dict()
	var outside: EditCheck = _editor.check_hang(&"neon_open_sign", OUTSIDE_NEON)
	assert_true(outside.ok, "the same OPEN sign may hang outside beside the door: " + outside.why)
	assert_eq(outside.cost, _content.item(&"neon_open_sign").price)
	assert_eq(_editor.to_dict(), before, "checking an outside mount is read-only")


func _can_spend(amount: int) -> bool:
	return amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)


func test_outside_finish_refunds_undoes_redoes_and_round_trips_independently_of_inside() -> void:
	var brick: Dictionary[Vector3i, FloorFinishes.Finish] = {
		FRONT_FACE: FloorFinishes.Finish.new(&"brick", &"sage", &"cream")}
	var original: Dictionary = _editor.to_dict()
	var initial_cash: int = _ledger.cash
	assert_true(_history.apply_wall_finishes(brick), _editor.last_check.why)
	assert_eq(_ledger.cash, initial_cash - _content.wall_style(&"brick").price)
	assert_eq(_editor.walls.finish(INSIDE_FACE).swatch, LAYOUT.wall_swatch_id)
	var striped: Dictionary[Vector3i, FloorFinishes.Finish] = {
		FRONT_FACE: FloorFinishes.Finish.new(&"stripes", &"clay", &"cream")}
	var replacement: EditCheck = _editor.check_wall_finishes(striped)
	var refund: int = floori(float(_content.wall_style(&"brick").price) / 2.0)
	assert_eq(replacement.refund, refund)
	assert_true(_history.apply_wall_finishes(striped))
	var replaced_cash: int = _ledger.cash
	var replaced: Dictionary = _editor.to_dict()
	assert_true(_history.undo())
	assert_eq(_editor.walls.finish(FRONT_FACE).style, &"brick")
	assert_eq(_ledger.cash, initial_cash - _content.wall_style(&"brick").price)
	assert_true(_history.redo())
	assert_eq(_editor.to_dict(), replaced)
	assert_eq(_ledger.cash, replaced_cash)
	var copy: ShopEditor = _restored_editor(replaced)
	if copy != null:
		assert_eq(copy.walls.to_rows(), _editor.walls.to_rows())
		assert_eq(copy.walls.finish(INSIDE_FACE).swatch, LAYOUT.wall_swatch_id)
	assert_true(_history.undo())
	assert_true(_history.undo())
	assert_eq(_ledger.cash, initial_cash)
	assert_eq(_editor.to_dict(), original)


func test_finishes_reject_side_back_and_empty_ground_without_changing_existing_inside_faces() -> void:
	for face: Vector3i in [Vector3i(14, 6, 3), Vector3i(3, -1, 2), Vector3i(15, 11, 0)]:
		var changes: Dictionary[Vector3i, FloorFinishes.Finish] = {
			face: FloorFinishes.Finish.new(&"brick", &"sage", &"cream")}
		assert_false(_editor.check_wall_finishes(changes).ok, "only the actual street front may be finished")
	assert_true(WallFaces.is_face(_sim.world.grid, INSIDE_FACE))
	assert_false(WallFaces.is_exterior(_sim.world.grid, INSIDE_FACE))
	assert_eq(_editor.walls.count(), 0)


func test_outside_finish_and_whole_building_paint_leave_paths_clock_rng_and_inside_vibe_unchanged() -> void:
	var clock: Dictionary = _sim.world.clock.to_dict()
	var random_state: int = _sim.spawner.rng.state
	var path: Array[Vector2i] = _sim.world.grid.find_guest_path(Vector2i(6, 11), Vector2i(8, 8))
	var guest_colour: StringName = _editor.wall_vibe_swatch()
	assert_true(_history.apply_wall_finishes({FRONT_FACE:
		FloorFinishes.Finish.new(&"brick", &"sage", &"cream")} as Dictionary[Vector3i, FloorFinishes.Finish]))
	assert_eq(_editor.wall_vibe_swatch(), guest_colour, "a street finish has no vote in the inside wall colour")
	assert_true(_editor.paint_wall(&"clay"))
	assert_eq(_editor.walls.finish(INSIDE_FACE).swatch, &"clay")
	assert_eq(_editor.walls.finish(FRONT_FACE).swatch, &"sage", "a per-face finish overrides whole-building paint")
	assert_eq(_editor.wall_vibe_swatch(), &"clay")
	assert_eq(_sim.world.clock.to_dict(), clock)
	assert_eq(_sim.spawner.rng.state, random_state)
	assert_eq(_sim.world.grid.find_guest_path(Vector2i(6, 11), Vector2i(8, 8)), path)


func test_exterior_faces_follow_entry_frontage_in_all_four_rotated_layouts() -> void:
	var rows: PackedStringArray = ["       ", " ##### ", " #...# ", " #...# ", " #...# ", " ##.## ", "   E   "]
	for turns: int in 4:
		var grid: SimGrid = SimGrid.from_ascii(_rotated_rows(rows, turns))
		var outside: Vector2i = GridMath.rotate_cell(Vector2i(2, 6), Vector2i(7, 7), turns)
		var front: Vector3i = WallFaces.make(outside, turns)
		assert_true(ExteriorSupport.is_exterior(grid, front), "rotated frontage %d" % turns)
		assert_eq(ExteriorSupport.finish_problem(grid, front), "")
		var shell: Vector2i = GridMath.rotate_cell(Vector2i(2, 5), Vector2i(7, 7), turns)
		assert_eq(ExteriorSupport.shell_cell(front), shell)
		assert_eq(WallRules.street_side(grid), WallFaces.DIRS[(2 + turns) % 4])
		var inside: Vector2i = GridMath.rotate_cell(Vector2i(2, 4), Vector2i(7, 7), turns)
		assert_false(ExteriorSupport.is_exterior(grid, WallFaces.make(inside, (2 + turns) % 4)))
		for band: int in range(ExteriorSupport.Band.LIGHTS + 1):
			var key: Vector3i = ExteriorSupport.key_for(front, band)
			assert_eq(ExteriorSupport.base_face(key), front)
			assert_eq(ExteriorSupport.band(key), band)
			assert_eq(WallFaces.step(key), WallFaces.step(front))
			assert_eq(WallFaces.span(key, 2)[1].z, key.z, "wide items retain their occupancy band")
		var window_floor: Vector2i = GridMath.rotate_cell(Vector2i(2, 4), Vector2i(7, 7), turns)
		var window_wall: Vector2i = GridMath.rotate_cell(Vector2i(2, 5), Vector2i(7, 7), turns)
		assert_true(grid.set_segment(SimGrid.edge_between(window_floor, window_wall), SimGrid.Segment.WINDOW))
		var decor: WallDecor = WallDecor.new()
		for id: StringName in [&"street_awning_2", &"shop_name_sign", &"flower_window_box", &"string_lights_2"]:
			var definition: ItemDef = _content.item(id)
			var key: Vector3i = ExteriorSupport.key_for(front, definition.exterior_band)
			assert_eq(decor.problem(grid, definition, key), "", "actual rotated mount support: %s/%d" % [id, turns])
			var back: Vector2i = GridMath.rotate_cell(Vector2i(2, 0), Vector2i(7, 7), turns)
			var wrong: Vector3i = ExteriorSupport.key_for(WallFaces.make(back, (2 + turns) % 4), definition.exterior_band)
			assert_false(decor.problem(grid, definition, wrong).is_empty(), "rotated back wall refuses exterior decor")


func test_new_item_definitions_accept_only_the_street_and_keep_expected_levels_prices_and_mounts() -> void:
	assert_true(_editor.apply_segments({WINDOW_EDGE: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]))
	for id: StringName in [&"street_awning_2", &"street_awning_3", &"street_awning_4",
		&"flower_window_box", &"shop_name_sign", &"string_lights_2", &"string_lights_3", &"string_lights_4"]:
		var definition: ItemDef = _content.item(id)
		assert_not_null(definition, String(id))
		if definition == null:
			continue
		assert_eq(definition.wall_mount, ItemDef.WallMount.EXTERIOR)
		assert_true(definition.placement_layer_valid())
		assert_true(definition.price >= 15 and definition.price <= 60)
		var expected_level: int = 3 if String(id).begins_with("string_lights") else (2 if id == &"shop_name_sign" else 1)
		assert_eq(definition.unlock_level, expected_level)
		var base: Vector3i = Vector3i(5, 11, 0)
		if id == &"flower_window_box":
			base = Vector3i(10, 11, 0)
		var anchor: Vector3i = ExteriorSupport.key_for(base, definition.exterior_band)
		assert_true(_editor.check_hang(id, anchor).ok, String(id) + ": " + _editor.check_hang(id, anchor).why)
		for wrong: Vector3i in [Vector3i(1, 6, 3), Vector3i(14, 6, 3), Vector3i(3, -1, 2)]:
			assert_false(_editor.check_hang(id, ExteriorSupport.key_for(wrong, definition.exterior_band)).ok)


func test_separate_exterior_bands_coexist_and_same_band_overlaps_refuse() -> void:
	assert_true(_editor.apply_segments({WINDOW_EDGE: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]))
	var door: Vector3i = Vector3i(6, 11, 0)
	assert_true(_history.hang(&"street_awning_2", ExteriorSupport.key_for(door, ExteriorSupport.Band.CANOPY), &"sage"))
	assert_true(_history.hang(&"shop_name_sign", ExteriorSupport.key_for(door, ExteriorSupport.Band.HEADER)))
	assert_true(_history.hang(&"string_lights_2", ExteriorSupport.key_for(door, ExteriorSupport.Band.LIGHTS)))
	var pane: Vector3i = Vector3i(10, 11, 0)
	assert_true(_history.hang(&"flower_window_box", ExteriorSupport.key_for(pane, ExteriorSupport.Band.SILL)))
	assert_true(_history.hang(&"street_awning_2", ExteriorSupport.key_for(Vector3i(9, 11, 0), ExteriorSupport.Band.CANOPY)))
	assert_eq(_editor.decor.count(), 5, "a window box fits below its awning and door sign fits below its canopy")
	assert_false(_editor.check_hang(&"street_awning_2", ExteriorSupport.key_for(door, ExteriorSupport.Band.CANOPY)).ok)
	assert_false(_editor.check_hang(&"street_awning_3", ExteriorSupport.key_for(Vector3i(5, 11, 0), ExteriorSupport.Band.CANOPY)).ok)


func test_one_shop_sign_can_move_without_counting_itself_as_a_second_sign() -> void:
	var first: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), ExteriorSupport.Band.HEADER)
	var second: Vector3i = ExteriorSupport.key_for(Vector3i(5, 11, 0), ExteriorSupport.Band.HEADER)
	assert_true(_history.hang(&"shop_name_sign", first))
	var cash: int = _ledger.cash
	assert_false(_editor.check_hang(&"shop_name_sign", second).ok)
	assert_true(_history.rehang(first, second), _editor.last_check.why)
	assert_eq(_editor.decor.count(), 1)
	assert_not_null(_editor.decor.item(second))
	assert_eq(_ledger.cash, cash)
	assert_true(_history.undo())
	assert_not_null(_editor.decor.item(first))
	assert_true(_history.redo())
	assert_not_null(_editor.decor.item(second))
	assert_eq(_ledger.cash, cash)


func test_awning_selected_swatch_survives_rehang_sale_history_and_json_rows() -> void:
	var first: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), ExteriorSupport.Band.CANOPY)
	var second: Vector3i = ExteriorSupport.key_for(Vector3i(5, 11, 0), ExteriorSupport.Band.CANOPY)
	assert_true(_history.hang(&"street_awning_2", first, &"sage"))
	assert_eq(_editor.decor.item(first).swatch_id, &"sage")
	assert_eq(_editor.decor.item(first).mount, ItemDef.WallMount.EXTERIOR)
	var purchased_cash: int = _ledger.cash
	assert_true(_history.paint_hung(first, &"clay"))
	assert_eq(_editor.decor.item(first).swatch_id, &"clay")
	assert_eq(_ledger.cash, purchased_cash)
	assert_true(_history.undo())
	assert_eq(_editor.decor.item(first).swatch_id, &"sage")
	assert_true(_history.redo())
	assert_true(_history.rehang(first, second))
	assert_eq(_editor.decor.item(second).swatch_id, &"clay")
	var snapshot: Dictionary = _editor.to_dict()
	assert_true((snapshot["wall_items"] as Array).has([second.x, second.y, second.z, "street_awning_2", 2, "clay"]))
	var copy: ShopEditor = _restored_editor(snapshot)
	if copy != null:
		assert_eq(copy.decor.to_rows(), _editor.decor.to_rows())
	var expected_refund: int = floori(float(_content.item(&"street_awning_2").price) / 2.0)
	assert_eq(_history.take_down(second), expected_refund)
	assert_eq(_ledger.cash, purchased_cash + expected_refund)
	assert_true(_history.undo())
	assert_eq(_ledger.cash, purchased_cash)
	assert_eq(_editor.decor.item(second).swatch_id, &"clay")
	assert_true(_history.redo())
	assert_null(_editor.decor.item(second))


func test_neon_actual_mount_round_trips_between_legacy_window_and_street_with_undo() -> void:
	assert_true(_editor.apply_segments({WINDOW_EDGE: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]))
	assert_true(_history.hang(&"neon_open_sign", WINDOW_SLOT))
	var old_row: Array = [WINDOW_SLOT.x, WINDOW_SLOT.y, WINDOW_SLOT.z, "neon_open_sign"]
	assert_true(_editor.decor.to_rows().has(old_row), "the old window row remains four fields")
	var cash: int = _ledger.cash
	assert_true(_history.rehang(WINDOW_SLOT, OUTSIDE_NEON))
	assert_eq(_editor.decor.item(OUTSIDE_NEON).mount, ItemDef.WallMount.EXTERIOR)
	assert_false(_editor.decor.item(OUTSIDE_NEON).window)
	assert_eq(_ledger.cash, cash)
	var outside: Dictionary = _editor.to_dict()
	var copy: ShopEditor = _restored_editor(outside)
	if copy != null:
		assert_eq(copy.decor.item(OUTSIDE_NEON).mount, ItemDef.WallMount.EXTERIOR)
	assert_true(_history.undo())
	assert_true(_editor.decor.item(WINDOW_SLOT).window)
	assert_eq(_editor.decor.item(WINDOW_SLOT).mount, ItemDef.WallMount.WINDOW)
	assert_true(_editor.decor.to_rows().has(old_row))
	assert_true(_history.redo())
	assert_eq(_editor.decor.to_rows(), outside["wall_items"])
	assert_eq(_ledger.cash, cash)


func test_old_v6_and_v7_inside_finish_and_four_field_window_rows_load_without_reinterpretation() -> void:
	for version: int in [6, 7]:
		var legacy: Dictionary = {"version": version, "items": [],
			"walls": [{"edge": [10, 10, SimGrid.EDGE_NORTH], "kind": "window"}], "floor": [], "rooms": [],
			"wall_swatch_id": "cream", "floor_swatch_id": "walnut", "floor_style_id": "", "floors": [],
			"wall_style_id": "paint", "wall_finishes": [[1, 6, 3, "brick", "sage", "cream"]],
			"wall_items": [[1, 8, 3, "wall_art_sunrise"], [10, 9, 2, "neon_open_sign"]]}
		# Genuine old saves retain every required starter item and authored room.
		# Build their legacy fields directly; never lower a new exterior snapshot's version.
		for placement: ShopPlacement in LAYOUT.placements:
			var row: Dictionary = {"def_id": String(placement.item_id),
				"origin": [placement.origin.x, placement.origin.y],
				"quarter_turns": placement.quarter_turns, "swatch_id": String(placement.swatch_id)}
			if version == 7:
				row["variant_id"] = String(placement.variant_id)
			(legacy["items"] as Array).append(row)
		var rooms: Dictionary[Vector2i, int] = LAYOUT.authored_rooms()
		for cell: Vector2i in rooms:
			(legacy["rooms"] as Array).append([cell.x, cell.y, String(RoomRules.id_of(rooms[cell]))])
		var untouched: Dictionary = legacy.duplicate(true)
		var restored: ShopEditor = _restored_editor(legacy)
		assert_eq(legacy, untouched, "decoding a real legacy row format is pure")
		if restored == null:
			continue
		assert_eq(restored.walls.finish(Vector3i(1, 6, 3)).style, &"brick")
		assert_eq(restored.decor.to_rows(), legacy["wall_items"])
		assert_eq(restored.decor.item(WINDOW_SLOT).mount, ItemDef.WallMount.WINDOW)
		assert_true(restored.decor.item(WINDOW_SLOT).window)
		assert_eq(restored.decor.item(Vector3i(1, 8, 3)).mount, ItemDef.WallMount.INSIDE_FACE)


func test_exterior_items_add_no_inside_vibe_or_path_clock_random_side_effects() -> void:
	var before: Array[ItemDef] = _editor.decor_vibe_items()
	var colour: StringName = _editor.wall_vibe_swatch()
	var random_state: int = _sim.spawner.rng.state
	var clock: Dictionary = _sim.world.clock.to_dict()
	var path: Array[Vector2i] = _sim.world.grid.find_guest_path(Vector2i(6, 11), Vector2i(8, 8))
	var canopy: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), ExteriorSupport.Band.CANOPY)
	assert_true(_history.hang(&"street_awning_2", canopy, &"sage"))
	assert_true(_history.hang(&"neon_open_sign", OUTSIDE_NEON))
	assert_true(_history.hang(&"string_lights_2", ExteriorSupport.key_for(Vector3i(6, 11, 0), ExteriorSupport.Band.LIGHTS)))
	assert_eq(_editor.decor_vibe_items(), before)
	assert_eq(_editor.wall_vibe_swatch(), colour)
	assert_eq(_sim.spawner.rng.state, random_state)
	assert_eq(_sim.world.clock.to_dict(), clock)
	assert_eq(_sim.world.grid.find_guest_path(Vector2i(6, 11), Vector2i(8, 8)), path)
	assert_true(_sim.world.clock.start_service())
	var service_clock: Dictionary = _sim.world.clock.to_dict()
	var service_rng: int = _sim.spawner.rng.state
	var history_count: int = _history.undo_count()
	assert_true(_history.paint_hung(canopy, &"clay"))
	assert_eq(_history.undo_count(), history_count, "free service paint adds no closed-phase undo entry")
	assert_eq(_sim.world.clock.to_dict(), service_clock)
	assert_eq(_sim.spawner.rng.state, service_rng)
	assert_false(_history.paint_hung(canopy, &"missing_palette_colour"))


func test_removing_a_supporting_window_refunds_its_box_and_undo_restores_exact_item_and_cash() -> void:
	var player_window: Vector3i = Vector3i(11, 10, SimGrid.EDGE_NORTH)
	assert_true(_history.apply_segments({player_window: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]))
	var box: Vector3i = ExteriorSupport.key_for(Vector3i(11, 11, 0), ExteriorSupport.Band.SILL)
	assert_true(_history.hang(&"flower_window_box", box))
	var before: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	var expected: int = floori(float(_content.item(&"flower_window_box").price) / 2.0) \
		+ floori(float(_content.wall_kind_for(SimGrid.Segment.WINDOW).price) / 2.0)
	assert_true(_history.apply_segments({player_window: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]))
	assert_null(_editor.decor.item(box))
	assert_eq(_ledger.cash, cash + expected, "support loss refunds exactly the window and box at half price")
	assert_true(_history.undo())
	assert_eq(_editor.to_dict(), before)
	assert_eq(_ledger.cash, cash)
	assert_true(_history.redo())
	assert_null(_editor.decor.item(box))


func _restored_editor(snapshot: Dictionary) -> ShopEditor:
	var errors: Array[String] = []
	var data: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	if layout == null:
		return null
	var sim: RestaurantSim = RestaurantSim.create(layout, _content, 240, errors, null, false, true)
	assert_eq(errors, [] as Array[String])
	return ShopEditor.new(sim, _content, ShopEditBooks.new(_can_spend, _record), layout)


func _rotated_rows(rows: PackedStringArray, turns: int) -> PackedStringArray:
	var size: Vector2i = Vector2i(rows[0].length(), rows.size())
	var rotated: PackedStringArray = []
	for y: int in size.y:
		rotated.append(" ".repeat(size.x))
	for y: int in size.y:
		for x: int in size.x:
			var target: Vector2i = GridMath.rotate_cell(Vector2i(x, y), size, turns)
			rotated[target.y] = rotated[target.y].substr(0, target.x) + rows[y][x] + rotated[target.y].substr(target.x + 1)
	return rotated


func test_inside_only_decor_still_refuses_every_outside_body_face() -> void:
	assert_true(WallFaces.is_face(_sim.world.grid, FRONT_FACE), "an exterior finish surface exists")
	for id: StringName in [&"wall_art_sunrise", &"wall_art_peaks", &"menu_board", &"restroom_mirror", &"wall_hand_dryer"]:
		assert_false(_editor.check_hang(id, FRONT_FACE).ok, String(id) + " retains its inside-only mount")
	assert_true(_editor.check_hang(&"wall_art_sunrise", Vector3i(1, 8, 3)).ok)


func test_inside_room_fill_preserves_its_face_set_and_cost_without_exterior_votes() -> void:
	# Exact 31 dining-wall faces from pristine55765, independent of changed enumeration.
	var expected: Array[Vector3i] = [
		Vector3i(1, 5, 0), Vector3i(1, 5, 3), Vector3i(2, 5, 0), Vector3i(3, 5, 0),
		Vector3i(4, 5, 0), Vector3i(8, 5, 0), Vector3i(9, 5, 0), Vector3i(10, 5, 0),
		Vector3i(11, 5, 0), Vector3i(12, 5, 0), Vector3i(12, 5, 1), Vector3i(1, 6, 3),
		Vector3i(12, 6, 1), Vector3i(1, 7, 3), Vector3i(12, 7, 1), Vector3i(1, 8, 3),
		Vector3i(12, 8, 1), Vector3i(1, 9, 2), Vector3i(1, 9, 3), Vector3i(2, 9, 2),
		Vector3i(3, 9, 2), Vector3i(4, 9, 2), Vector3i(5, 9, 2), Vector3i(8, 9, 2),
		Vector3i(9, 9, 2), Vector3i(10, 9, 2), Vector3i(11, 9, 2), Vector3i(12, 9, 1),
		Vector3i(12, 9, 2), Vector3i(6, 10, 3), Vector3i(7, 10, 1),
	]
	var grid: SimGrid = _sim.world.grid
	var actual: Array[Vector3i] = _editor.wall_room_faces(INSIDE_FACE)
	assert_eq(actual, expected, "Shift-fill retains the original inside dining-wall set")
	var changes: Dictionary[Vector3i, FloorFinishes.Finish] = _editor.wall_lay_changes(actual, &"stripes", &"sage", &"cream")
	var check: EditCheck = _editor.check_wall_finishes(changes)
	assert_true(check.ok, check.why)
	assert_eq(check.cost, expected.size() * _content.wall_style(&"stripes").price)
	assert_false(changes.has(FRONT_FACE))
	for face: Vector3i in changes:
		assert_false(WallFaces.is_exterior(grid, face))


func test_malformed_exterior_band_or_mount_cannot_install_unsupported_items_or_extra_signs() -> void:
	var sign: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), ExteriorSupport.Band.HEADER)
	assert_true(_history.hang(&"shop_name_sign", sign))
	var baseline: Dictionary = _editor.to_dict()
	var cash: int = _ledger.cash
	for bad: Array in [
		[3, 11, 1000, "street_awning_2", 2, "sage"],
		[3, 11, 4, "street_awning_2", "EXTERIOR", "sage"],
		[3, 11, 4, "street_awning_2", 1, "sage"],
		[3, 11, 0, "street_awning_2", 2, "sage"],
		[14, 6, 7, "street_awning_2", 2, "sage"],
		[5, 11, 8, "shop_name_sign", 2, ""],
	]:
		var malformed: Dictionary = baseline.duplicate(true)
		(malformed["wall_items"] as Array).append(bad)
		var errors: Array[String] = []
		var loaded: ShopLayout = ShopEditor.from_dict(malformed, LAYOUT, _content, errors)
		if loaded != null:
			var restored: ShopEditor = _restored_editor(malformed)
			if restored != null:
				assert_eq(restored.decor.to_rows(), baseline["wall_items"], "invalid row cannot bypass mount/support/uniqueness")
		else:
			assert_false(errors.is_empty())
		assert_eq(_editor.to_dict(), baseline, "failed pure decode leaves the live editor untouched")
		assert_eq(_ledger.cash, cash)
