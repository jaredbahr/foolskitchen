extends TestCase
## Derived street appeal: fixed repeat families and actual front supports.

const TUNING: CurbAppealTuning = preload("res://data/balance/curb_appeal.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const FRONT: Vector3i = Vector3i(3, 11, 0)
const INSIDE: Vector3i = Vector3i(3, 9, 2)

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	_content = null


func test_authored_bare_front_is_exactly_neutral() -> void:
	assert_true(TUNING.is_valid())
	assert_true(CurbAppealTuning.new().is_valid(), "pure model authoring does not require an item map")
	var result: Dictionary = CurbAppealModel.evaluate([], TUNING)
	assert_true(result.valid)
	assert_eq(result.score, 0.0)
	assert_eq(result.multiplier, 1.0)


func test_one_of_each_family_uses_authored_weight_and_linear_bonus() -> void:
	for category: StringName in CurbAppealTuning.CATEGORIES:
		var result: Dictionary = CurbAppealModel.evaluate(_copies(category, 1), TUNING)
		var expected: float = minf(TUNING.weights[category], TUNING.caps[category])
		assert_true(result.valid)
		assert_almost_eq(result.score, expected)
		assert_almost_eq(result.multiplier, 1.0 + expected / 100.0 * TUNING.max_bonus)


func test_repeat_gains_diminish_before_the_family_cap() -> void:
	var one: Dictionary = CurbAppealModel.evaluate(_copies(&"finish", 1), TUNING)
	var two: Dictionary = CurbAppealModel.evaluate(_copies(&"finish", 2), TUNING)
	var three: Dictionary = CurbAppealModel.evaluate(_copies(&"finish", 3), TUNING)
	assert_true(two.score > one.score)
	assert_true(three.score > two.score)
	assert_true(three.score - two.score < two.score - one.score)
	assert_almost_eq(two.score - one.score, TUNING.weights[&"finish"] * TUNING.repeat_decay)


func test_ten_boxes_cannot_max_appeal_and_all_families_stay_bounded() -> void:
	var boxes: Dictionary = CurbAppealModel.evaluate(_copies(&"window_box", 10), TUNING)
	assert_eq(boxes.score, TUNING.caps[&"window_box"])
	assert_true(boxes.score < 100.0)
	var all: Array[Dictionary] = []
	for category: StringName in CurbAppealTuning.CATEGORIES:
		var previous: float = 0.0
		for count: int in [1, 2, 3, 5, 10, 50]:
			var result: Dictionary = CurbAppealModel.evaluate(_copies(category, count), TUNING)
			assert_true(result.score >= previous and result.score <= TUNING.caps[category])
			previous = result.score
		all.append_array(_copies(category, 50))
	var saturated: Dictionary = CurbAppealModel.evaluate(all, TUNING)
	assert_eq(saturated.score, 100.0)
	assert_eq(saturated.multiplier, 1.10)


func test_permutation_duplicates_and_cosmetics_do_not_change_repeat_rules() -> void:
	var rows: Array[Dictionary] = _copies(&"awning", 2)
	rows[0]["width"] = 2
	rows[0]["swatch"] = &"sage"
	rows[1]["width"] = 4
	rows[1]["swatch"] = &"clay"
	rows.append_array(_copies(&"finish", 3))
	var original: Array[Dictionary] = rows.duplicate(true)
	var expected: Dictionary = CurbAppealModel.evaluate(rows, TUNING)
	rows.reverse()
	rows.append(rows[0].duplicate(true))
	assert_eq(CurbAppealModel.evaluate(rows, TUNING), expected)
	rows.pop_back()
	rows.reverse()
	assert_eq(rows, original, "evaluation leaves caller records intact")
	expected.components[&"awning"] = -1.0
	assert_true(CurbAppealModel.evaluate(rows, TUNING).components[&"awning"] >= 0.0,
		"results do not share mutable component dictionaries")


func test_cap_boundaries_and_zero_decay_use_unrounded_points() -> void:
	var tuning: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
	tuning.weights[&"finish"] = 10.0
	tuning.repeat_decay = 0.5
	for cap: float in [14.999, 15.0, 15.001]:
		tuning.caps[&"finish"] = cap
		var result: Dictionary = CurbAppealModel.evaluate(_copies(&"finish", 2), tuning)
		assert_almost_eq(result.score, minf(15.0, cap))
	tuning.repeat_decay = 0.0
	assert_eq(CurbAppealModel.evaluate(_copies(&"finish", 50), tuning).score, 10.0)
	tuning.max_bonus = 0.0
	assert_eq(CurbAppealModel.evaluate(_copies(&"finish", 2), tuning).multiplier, 1.0)


func test_invalid_tuning_returns_no_partial_bonus() -> void:
	for value: float in [-0.01, 1.0, NAN, INF]:
		var tuning: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
		tuning.repeat_decay = value
		_assert_invalid(_copies(&"awning", 1), tuning)
	for value: float in [-1.0, 0.101, NAN, INF]:
		var tuning: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
		tuning.max_bonus = value
		_assert_invalid([], tuning)
	for value: float in [-1.0, NAN, INF]:
		var tuning: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
		tuning.weights[&"finish"] = value
		_assert_invalid(_copies(&"finish", 1), tuning)
	for value: float in [-1.0, 100.01, NAN, INF]:
		var tuning: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
		tuning.caps[&"sign"] = value
		_assert_invalid([], tuning)
	var missing: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
	missing.weights.erase(&"finish")
	_assert_invalid([], missing)
	var unknown: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
	unknown.caps[&"unknown"] = 1.0
	_assert_invalid([], unknown)
	var bad_map: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
	bad_map.item_categories[&"street_awning_2"] = &"unknown"
	_assert_invalid([], bad_map)
	bad_map.item_categories.erase(&"street_awning_2")
	bad_map.item_categories[&""] = &"awning"
	_assert_invalid([], bad_map)
	_assert_invalid([], null)


func test_invalid_rows_and_conflicting_object_identity_are_neutral() -> void:
	for row: Dictionary in [{}, {"category": &"unknown", "id": "x"},
		{"category": &"finish", "id": " "}, {"category": &"finish", "id": 1},
		{"category": 1, "id": "x"}]:
		_assert_invalid([{"category": &"awning", "id": "valid"}, row], TUNING)
	_assert_invalid([{"category": &"awning", "id": "same"},
		{"category": &"lights", "id": "same"}], TUNING)


func test_plain_paint_recolours_and_free_front_do_not_earn_points() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var finishes: WallFinishes = WallFinishes.new()
	var decor: WallDecor = WallDecor.new()
	assert_eq(CurbAppealInputs.collect(grid, finishes, decor, _content, TUNING), [] as Array[Dictionary])
	var paint: Dictionary[Vector3i, FloorFinishes.Finish] = {
		FRONT: FloorFinishes.Finish.new(&"paint", &"sage")}
	finishes.set_finishes(paint)
	finishes.set_default_swatch(&"clay")
	assert_eq(CurbAppealModel.evaluate(CurbAppealInputs.collect(grid, finishes, decor, _content, TUNING), TUNING).score, 0.0)


func test_only_nonpaint_supported_front_finishes_are_collected() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var finishes: WallFinishes = WallFinishes.new()
	var changes: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	for face: Vector3i in [FRONT, INSIDE, Vector3i(14, 6, 3), Vector3i(3, -1, 2)]:
		changes[face] = FloorFinishes.Finish.new(&"brick", &"sage", &"cream")
	changes[Vector3i(4, 11, 0)] = FloorFinishes.Finish.new(&"stripes", &"clay", &"cream")
	finishes.set_finishes(changes)
	var rows: Array[Dictionary] = CurbAppealInputs.collect(grid, finishes, WallDecor.new(), _content, TUNING)
	assert_eq(rows.size(), 2)
	assert_eq(rows[0].category, &"finish")
	assert_eq(rows[1].category, &"finish")
	assert_eq(CurbAppealModel.evaluate(rows, TUNING), CurbAppealModel.evaluate(_copies(&"finish", 2), TUNING),
		"style and swatch variants share one repeat family")


func test_all_named_exterior_items_count_once_in_their_family() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	assert_true(grid.set_segment(Vector3i(10, 10, SimGrid.EDGE_NORTH), SimGrid.Segment.WINDOW))
	assert_eq(TUNING.item_categories.size(), 9, "all approved street item widths and the OPEN sign are authored")
	for id: StringName in TUNING.item_categories:
		var definition: ItemDef = _content.item(id)
		var base: Vector3i = Vector3i(5, 11, 0)
		if id == &"flower_window_box":
			base = Vector3i(10, 11, 0)
		elif id == &"shop_name_sign":
			base = Vector3i(6, 11, 0)
		elif id == &"neon_open_sign":
			base = Vector3i(8, 11, 0)
		var anchor: Vector3i = ExteriorSupport.key_for(base, definition.exterior_band)
		var decor: WallDecor = WallDecor.new()
		assert_eq(decor.problem(grid, definition, anchor), "", String(id))
		assert_true(decor.add(id, anchor, definition.footprint.x, false, ItemDef.WallMount.EXTERIOR))
		var rows: Array[Dictionary] = CurbAppealInputs.collect(grid, WallFinishes.new(), decor, _content, TUNING)
		assert_eq(rows.size(), 1, "wide objects have one anchor: " + String(id))
		if rows.size() == 1:
			assert_eq(rows[0].category, TUNING.item_categories[id])


func test_item_eligibility_and_family_are_read_from_private_authored_tuning() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var decor: WallDecor = WallDecor.new()
	assert_true(decor.add(&"street_awning_2", Vector3i(6, 11, 4), 2, false, ItemDef.WallMount.EXTERIOR))
	var private_tuning: CurbAppealTuning = TUNING.duplicate(true) as CurbAppealTuning
	private_tuning.item_categories.clear()
	assert_true(private_tuning.is_valid())
	assert_eq(CurbAppealInputs.collect(grid, WallFinishes.new(), decor, _content, private_tuning),
		[] as Array[Dictionary], "an omitted item has no hardcoded eligibility")
	private_tuning.item_categories[&"street_awning_2"] = &"lights"
	var rows: Array[Dictionary] = CurbAppealInputs.collect(grid, WallFinishes.new(), decor, _content, private_tuning)
	assert_eq(rows.size(), 1)
	if rows.size() == 1:
		assert_eq(rows[0].category, &"lights", "the resource supplies the repeat family")
	assert_eq(private_tuning.item_categories, {&"street_awning_2": &"lights"})
	assert_eq(TUNING.item_categories[&"street_awning_2"], &"awning", "the shared authored resource is unchanged")


func test_same_front_cell_in_different_bands_has_distinct_stable_ids() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var finishes: WallFinishes = WallFinishes.new()
	finishes.set_finishes({FRONT: FloorFinishes.Finish.new(&"brick")} as Dictionary[Vector3i, FloorFinishes.Finish])
	var decor: WallDecor = WallDecor.new()
	for id: StringName in [&"street_awning_2", &"shop_name_sign", &"string_lights_2"]:
		var definition: ItemDef = _content.item(id)
		var anchor: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), definition.exterior_band)
		assert_true(decor.add(id, anchor, definition.footprint.x, false, ItemDef.WallMount.EXTERIOR))
	var rows: Array[Dictionary] = CurbAppealInputs.collect(grid, finishes, decor, _content, TUNING)
	assert_eq(rows.size(), 4)
	var ids: Dictionary[String, bool] = {}
	for row: Dictionary in rows:
		assert_false(ids.has(row.id))
		ids[row.id] = true
	assert_eq(CurbAppealInputs.collect(grid, finishes, decor, _content, TUNING), rows)


func test_old_window_open_sign_counts_only_on_the_actual_front_window() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var front_slot: Vector3i = Vector3i(10, 9, 2)
	var side_slot: Vector3i = Vector3i(12, 6, 1)
	var back_slot: Vector3i = Vector3i(3, 1, 0)
	for slot: Vector3i in [front_slot, side_slot, back_slot]:
		assert_true(grid.set_segment(WallFaces.edge(slot), SimGrid.Segment.WINDOW))
		assert_eq(WallFaces.window_problem(grid, slot), "")
	var decor: WallDecor = WallDecor.new()
	for slot: Vector3i in [front_slot, side_slot, back_slot]:
		assert_true(decor.add(&"neon_open_sign", slot, 1, true))
	var rows: Array[Dictionary] = CurbAppealInputs.collect(grid, WallFinishes.new(), decor, _content, TUNING)
	assert_eq(rows.size(), 1)
	if rows.size() == 1:
		assert_eq(rows[0].category, &"open_sign")
		assert_eq(rows[0].id, "decor:10:9:2")


func test_stale_unsupported_wrong_band_width_and_inside_mounts_are_excluded() -> void:
	var grid: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	var decor: WallDecor = WallDecor.new()
	assert_true(decor.add(&"street_awning_2", Vector3i(3, 11, 4), 2, false, ItemDef.WallMount.EXTERIOR),
		"above solid wall without a window or door")
	assert_true(decor.add(&"shop_name_sign", Vector3i(6, 11, 16), 2, false, ItemDef.WallMount.EXTERIOR),
		"wrong band")
	assert_true(decor.add(&"string_lights_4", Vector3i(9, 11, 16), 1, false, ItemDef.WallMount.EXTERIOR),
		"stale width")
	assert_true(decor.add(&"neon_open_sign", Vector3i(8, 11, 0), 1, false, ItemDef.WallMount.INSIDE_FACE),
		"definition allows exterior, but this actual mount does not")
	assert_true(decor.add(&"neon_open_sign", Vector3i(10, 9, 2), 1, true), "no actual window")
	assert_true(decor.add(&"string_lights_2", Vector3i(14, 6, 19), 2, false, ItemDef.WallMount.EXTERIOR),
		"side wall")
	assert_eq(CurbAppealInputs.collect(grid, WallFinishes.new(), decor, _content, TUNING), [] as Array[Dictionary])


func test_front_orientation_rotates_with_entry_for_finishes_and_both_open_mounts() -> void:
	var ascii: PackedStringArray = ["       ", " ##### ", " #...# ", " #...# ", " #...# ", " ##.## ", "   E   "]
	for turns: int in 4:
		var grid: SimGrid = SimGrid.from_ascii(_rotated_rows(ascii, turns))
		var outside: Vector2i = GridMath.rotate_cell(Vector2i(2, 6), Vector2i(7, 7), turns)
		var front: Vector3i = WallFaces.make(outside, turns)
		var finishes: WallFinishes = WallFinishes.new()
		finishes.set_finishes({front: FloorFinishes.Finish.new(&"brick")} as Dictionary[Vector3i, FloorFinishes.Finish])
		var decor: WallDecor = WallDecor.new()
		assert_true(decor.add(&"neon_open_sign", front, 1, false, ItemDef.WallMount.EXTERIOR))
		var window_floor: Vector2i = GridMath.rotate_cell(Vector2i(4, 4), Vector2i(7, 7), turns)
		var window_wall: Vector2i = GridMath.rotate_cell(Vector2i(4, 5), Vector2i(7, 7), turns)
		assert_true(grid.set_segment(SimGrid.edge_between(window_floor, window_wall), SimGrid.Segment.WINDOW))
		var slot: Vector3i = WallFaces.make(window_floor, (2 + turns) % 4)
		assert_true(decor.add(&"neon_open_sign", slot, 1, true))
		var rows: Array[Dictionary] = CurbAppealInputs.collect(grid, finishes, decor, _content, TUNING)
		assert_eq(rows.size(), 3, "rotated front %d" % turns)
		assert_eq(CurbAppealModel.evaluate(rows, TUNING).score, TUNING.weights[&"finish"] + TUNING.caps[&"open_sign"])


func test_collect_and_evaluate_leave_world_rng_clock_and_edit_state_unchanged() -> void:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 244, errors, null, false)
	assert_eq(errors, [] as Array[String])
	var grid: SimGrid = sim.world.grid
	var finishes: WallFinishes = WallFinishes.new()
	finishes.set_finishes({FRONT: FloorFinishes.Finish.new(&"brick")} as Dictionary[Vector3i, FloorFinishes.Finish])
	var decor: WallDecor = WallDecor.new()
	assert_true(decor.add(&"street_awning_2", Vector3i(6, 11, 4), 2, false, ItemDef.WallMount.EXTERIOR))
	var clock: Dictionary = sim.world.clock.to_dict()
	var rng_state: int = sim.spawner.rng.state
	var grid_version: int = grid.version
	var finish_rows: Array[Array] = finishes.to_rows()
	var decor_rows: Array[Array] = decor.to_rows()
	var finish_revision: int = finishes.revision
	var decor_revision: int = decor.revision
	var path: Array[Vector2i] = grid.find_guest_path(Vector2i(6, 11), Vector2i(8, 8))
	var tuning_before: Dictionary = {"items": TUNING.item_categories.duplicate(),
		"weights": TUNING.weights.duplicate(), "caps": TUNING.caps.duplicate(),
		"decay": TUNING.repeat_decay, "bonus": TUNING.max_bonus}
	var rows: Array[Dictionary] = CurbAppealInputs.collect(grid, finishes, decor, _content, TUNING)
	var first: Dictionary = CurbAppealModel.evaluate(rows, TUNING)
	assert_true(first.valid and first.score > 0.0)
	assert_eq(CurbAppealModel.evaluate(CurbAppealInputs.collect(grid, finishes, decor, _content, TUNING), TUNING), first)
	assert_eq(sim.world.clock.to_dict(), clock)
	assert_eq(sim.spawner.rng.state, rng_state)
	assert_eq(grid.version, grid_version)
	assert_eq(finishes.to_rows(), finish_rows)
	assert_eq(decor.to_rows(), decor_rows)
	assert_eq(finishes.revision, finish_revision)
	assert_eq(decor.revision, decor_revision)
	assert_eq(grid.find_guest_path(Vector2i(6, 11), Vector2i(8, 8)), path)
	assert_eq({"items": TUNING.item_categories, "weights": TUNING.weights, "caps": TUNING.caps, "decay": TUNING.repeat_decay,
		"bonus": TUNING.max_bonus}, tuning_before)


func _copies(category: StringName, count: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in count:
		rows.append({"category": category, "id": "%s:%d" % [category, index]})
	return rows


func _assert_invalid(rows: Array[Dictionary], tuning: CurbAppealTuning) -> void:
	var result: Dictionary = CurbAppealModel.evaluate(rows, tuning)
	assert_false(result.valid)
	assert_eq(result.score, 0.0)
	assert_eq(result.multiplier, 1.0)
	assert_eq(result.components, {})


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
