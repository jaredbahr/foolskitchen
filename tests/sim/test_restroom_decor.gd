extends TestCase
## FK-103: passive restroom accents and edge partitions preserve use spots.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const FACE: Vector3i = Vector3i(1, 8, 3)
var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null


func test_mirror_hangs_inside_or_outside_restroom_with_hint_only() -> void:
	var grid: SimGrid = _sim.world.grid
	var mirror: ItemDef = _content.item(&"restroom_mirror")
	assert_true(mirror.placement_layer_valid())
	assert_eq(mirror.placement_layer, ItemDef.PlacementLayer.WALL)
	assert_eq(mirror.wall_mount, ItemDef.WallMount.INSIDE_FACE)
	assert_eq(mirror.category, ItemDef.Category.RESTROOM)
	assert_eq(mirror.buy_room(), &"restroom")
	assert_true(_editor.check_hang(mirror.id, FACE).ok)
	assert_false(WallDecor.room_hint(grid, mirror, FACE).is_empty())
	var before: Array[Vector2i] = grid.find_guest_path(Vector2i(6, 11), Vector2i(1, 8))
	assert_true(_editor.hang(mirror.id, FACE), _editor.last_check.why)
	assert_eq(grid.find_guest_path(Vector2i(6, 11), Vector2i(1, 8)), before)
	grid.set_rooms({Vector2i(1, 8): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	assert_eq(WallDecor.room_hint(grid, mirror, FACE), "")
	assert_true(_editor.check_rehang(FACE, FACE).ok)
	assert_null(grid.place_def(mirror, Vector2i(1, 8), 0), "never becomes a floor obstruction")
	assert_eq(CatalogueText.group_for(mirror), &"wall_decor")
	assert_eq(CatalogueText.charm_text(mirror), "Charm +1")


func test_dryer_hangs_inside_or_outside_restroom_with_hint_only() -> void:
	var grid: SimGrid = _sim.world.grid
	var dryer: ItemDef = _content.item(&"wall_hand_dryer")
	assert_true(dryer.placement_layer_valid())
	assert_eq(dryer.placement_layer, ItemDef.PlacementLayer.WALL)
	assert_eq(dryer.wall_mount, ItemDef.WallMount.INSIDE_FACE)
	assert_eq(dryer.category, ItemDef.Category.RESTROOM)
	assert_eq(dryer.buy_room(), &"restroom")
	assert_true(_editor.check_hang(dryer.id, FACE).ok)
	assert_false(WallDecor.room_hint(grid, dryer, FACE).is_empty())
	var before: Array[Vector2i] = grid.find_guest_path(Vector2i(6, 11), Vector2i(1, 8))
	assert_true(_editor.hang(dryer.id, FACE), _editor.last_check.why)
	assert_eq(grid.find_guest_path(Vector2i(6, 11), Vector2i(1, 8)), before)
	grid.set_rooms({Vector2i(1, 8): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	assert_eq(WallDecor.room_hint(grid, dryer, FACE), "")
	assert_true(_editor.check_rehang(FACE, FACE).ok)
	assert_null(grid.place_def(dryer, Vector2i(1, 8), 0), "never becomes a floor obstruction")
	assert_eq(CatalogueText.group_for(dryer), &"wall_decor")
	assert_eq(CatalogueText.charm_text(dryer), "Charm +1")


func test_mirror_adds_small_charm_but_toilets_do_not() -> void:
	var grid: SimGrid = _sim.world.grid
	var tuning: VibeTuning = (load("res://data/balance/vibe.tres") as VibeTuning).duplicate() as VibeTuning
	tuning.free_charm = 0.0
	tuning.free_variety = 0
	var before: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(grid, _content, []), tuning)
	assert_true(_editor.hang(&"restroom_mirror", FACE))
	var after: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(grid, _content, [], &"", &"", _editor.decor_vibe_items()), tuning)
	assert_true(after.valid)
	assert_almost_eq(after.decor_points - before.decor_points, tuning.decor_points_per_charm, 0.0001)
	assert_almost_eq(after.crowding_penalty, before.crowding_penalty, 0.0001)
	var toilet: ItemDef = _content.item(&"toilet")
	assert_eq(CatalogueText.charm_text(toilet), "")
	# Even a malformed caller's floor fixture charm cannot count as wall decor.
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	var floor_fixture: VibeModel.Item = VibeModel.Item.new()
	floor_fixture.definition_id = toilet.id
	floor_fixture.category = ItemDef.Category.RESTROOM
	floor_fixture.charm = 1.0
	inputs.items.append(floor_fixture)
	assert_almost_eq(VibeModel.evaluate(inputs, tuning).decor_points, 0.0, 0.0001)


func test_dryer_adds_small_charm_but_toilets_do_not() -> void:
	var grid: SimGrid = _sim.world.grid
	var tuning: VibeTuning = (load("res://data/balance/vibe.tres") as VibeTuning).duplicate() as VibeTuning
	tuning.free_charm = 0.0
	tuning.free_variety = 0
	var before: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(grid, _content, []), tuning)
	assert_true(_editor.hang(&"wall_hand_dryer", FACE))
	var after: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(grid, _content, [], &"", &"", _editor.decor_vibe_items()), tuning)
	assert_true(after.valid)
	assert_almost_eq(after.decor_points - before.decor_points, tuning.decor_points_per_charm, 0.0001)
	assert_almost_eq(after.crowding_penalty, before.crowding_penalty, 0.0001)
	var toilet: ItemDef = _content.item(&"toilet")
	assert_eq(CatalogueText.charm_text(toilet), "")
	# Even a malformed caller's floor fixture charm cannot count as wall decor.
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	var floor_fixture: VibeModel.Item = VibeModel.Item.new()
	floor_fixture.definition_id = toilet.id
	floor_fixture.category = ItemDef.Category.RESTROOM
	floor_fixture.charm = 1.0
	inputs.items.append(floor_fixture)
	assert_almost_eq(VibeModel.evaluate(inputs, tuning).decor_points, 0.0, 0.0001)


func test_partition_between_two_toilets_keeps_both_and_basin_accessible() -> void:
	var grid: SimGrid = _sim.world.grid
	for placed: PlacedItem in grid.items():
		if placed.origin.y >= 5 and (placed.def as ItemDef).category != ItemDef.Category.DOOR:
			grid.remove(placed.id)
	var rooms: Dictionary[Vector2i, int] = {}
	for x: int in range(1, 5):
		for y: int in range(7, 10):
			rooms[Vector2i(x, y)] = SimGrid.Room.RESTROOM
	grid.set_rooms(rooms)
	var first: PlacedItem = grid.place_def(_content.item(&"toilet"), Vector2i(1, 9), 0)
	var second: PlacedItem = grid.place_def(_content.item(&"toilet"), Vector2i(2, 9), 0)
	var basin: PlacedItem = grid.place_def(_content.item(&"bathroom_sink"), Vector2i(4, 9), 0)
	assert_not_null(first)
	assert_not_null(second)
	assert_not_null(basin)
	var edge: Vector3i = Vector3i(2, 9, SimGrid.EDGE_WEST)
	var changes: Dictionary[Vector3i, int] = {edge: SimGrid.Segment.STALL_PARTITION,
		Vector3i(2, 8, SimGrid.EDGE_WEST): SimGrid.Segment.STALL_PARTITION}
	assert_true(_editor.apply_segments(changes), _editor.last_check.why)
	assert_eq(RoomRules.restroom_toilets(grid).size(), 2)
	for fixture: PlacedItem in [first, second, basin]:
		for spot: Vector2i in fixture.work_cells:
			assert_true(grid.is_walkable(spot))
			assert_false(grid.find_guest_path(Vector2i(6, 11), spot).is_empty())
	assert_true(grid.edge_blocked(Vector2i(1, 8), Vector2i(2, 8)))
	# A panel across a toilet's front is refused, not placed through its use spot.
	assert_false(_editor.check_segments({Vector3i(1, 9, SimGrid.EDGE_NORTH):
		SimGrid.Segment.STALL_PARTITION} as Dictionary[Vector3i, int]).ok)
	assert_false(_editor.check_segments({Vector3i(4, 9, SimGrid.EDGE_NORTH):
		SimGrid.Segment.STALL_PARTITION} as Dictionary[Vector3i, int]).ok)
	assert_true(_editor.hang(&"restroom_mirror", FACE), _editor.last_check.why)
	assert_true(_editor.hang(&"wall_hand_dryer", Vector3i(1, 7, 3)), _editor.last_check.why)
	assert_eq(_content.wall_kinds().size(), 4)
	assert_eq(_content.wall_kind_for(SimGrid.Segment.STALL_PARTITION).id, &"stall_partition")
	var errors: Array[String] = []
	var saved: ShopLayout = ShopEditor.from_dict(JSON.parse_string(JSON.stringify(_editor.to_dict())), LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	var restored: SimWorld = ShopBuilder.build(saved, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(saved.wall_items[FACE], &"restroom_mirror")
	assert_eq(saved.wall_items[Vector3i(1, 7, 3)], &"wall_hand_dryer")
	assert_eq(restored.grid.segment(edge), SimGrid.Segment.STALL_PARTITION)
	assert_eq(RoomRules.restroom_toilets(restored.grid).size(), 2)


func test_partition_cannot_seal_toilet_use_spot() -> void:
	_assert_corner_fixture_stays_reachable(&"toilet")


func test_partition_cannot_seal_basin_use_spot() -> void:
	_assert_corner_fixture_stays_reachable(&"bathroom_sink")


func test_existing_sealed_restroom_fixture_allows_unrelated_wall_edit() -> void:
	var grid: SimGrid = _sim.world.grid
	var fixture: PlacedItem = _corner_fixture(&"toilet")
	var sealed: Vector3i = Vector3i(2, 5, SimGrid.EDGE_WEST)
	assert_true(grid.set_segment(sealed, SimGrid.Segment.STALL_PARTITION))
	assert_true(grid.find_guest_path(grid.entries()[0], fixture.work_cells[0]).is_empty())
	var unrelated: Vector3i = Vector3i(9, 6, SimGrid.EDGE_WEST)
	var check: EditCheck = _editor.check_segments({unrelated: SimGrid.Segment.STALL_PARTITION}
		as Dictionary[Vector3i, int])
	assert_true(check.ok, check.why)


func _assert_corner_fixture_stays_reachable(fixture_id: StringName) -> void:
	var grid: SimGrid = _sim.world.grid
	var fixture: PlacedItem = _corner_fixture(fixture_id)
	var spot: Vector2i = fixture.work_cells[0]
	assert_eq(spot, Vector2i(1, 5))
	assert_false(grid.find_guest_path(grid.entries()[0], spot).is_empty())
	# The shell closes north/west and the fixture closes south. This side panel
	# seals the east approach without crossing the fixture's own front edge.
	var edge: Vector3i = Vector3i(2, 5, SimGrid.EDGE_WEST)
	var check: EditCheck = _editor.check_segments({edge: SimGrid.Segment.STALL_PARTITION}
		as Dictionary[Vector3i, int])
	assert_false(check.ok, "a partition must not seal the %s use spot" % fixture_id)
	assert_eq(check.why, WallRules.CUT_RESTROOM)
	assert_eq(grid.segment(edge), SimGrid.Segment.NONE, "checking does not place the partition")


func _corner_fixture(fixture_id: StringName) -> PlacedItem:
	var grid: SimGrid = _sim.world.grid
	for placed: PlacedItem in grid.items():
		if placed.origin.y >= 5 and (placed.def as ItemDef).category != ItemDef.Category.DOOR:
			grid.remove(placed.id)
	var spot: Vector2i = Vector2i(1, 5)
	var origin: Vector2i = Vector2i(1, 6)
	assert_true(grid.set_rooms({spot: SimGrid.Room.RESTROOM, origin: SimGrid.Room.RESTROOM}
		as Dictionary[Vector2i, int]))
	var fixture: PlacedItem = grid.place_def(_content.item(fixture_id), origin, 0)
	assert_not_null(fixture)
	return fixture


func test_partition_tool_never_makes_an_outside_window() -> void:
	var edge: Vector3i = Vector3i(1, 8, SimGrid.EDGE_WEST)
	var kind: SimGrid.Segment = _editor.next_segment(edge, SimGrid.Segment.STALL_PARTITION)
	assert_eq(kind, SimGrid.Segment.STALL_PARTITION)
	assert_false(_editor.check_segments({edge: kind} as Dictionary[Vector3i, int]).ok)


func test_buy_and_move_hints_never_replace_a_valid_action_or_refusal() -> void:
	var mode: BuildMode = BuildMode.new()
	mode.bind_session(_editor, _sim.world, _content, _editor.move, _editor.buy, _editor.sell)
	mode.bind_walls(Callable(), _editor.hang, _editor.rehang, _editor.take_down)
	assert_true(mode.enter())
	assert_true(mode.begin_hang(&"restroom_mirror"))
	mode.hang_pointer(FACE)
	assert_true(mode.current_check.ok)
	assert_true(mode.hang_summary().begins_with("Hang Restroom mirror for $30. Tip:"))
	_sim.world.grid.set_rooms({Vector2i(1, 8): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	assert_eq(mode.hang_summary(), "Hang Restroom mirror for $30")
	assert_true(_editor.hang(&"restroom_mirror", FACE))
	assert_true(mode.begin_rehang(FACE))
	mode.hang_pointer(Vector3i(1, 7, 3))
	assert_true(mode.current_check.ok)
	assert_true(mode.hang_summary().begins_with("Move Restroom mirror here (Del sells it). Tip:"))
	mode.hang_pointer(Vector3i(4, 7, 0))
	assert_false(mode.current_check.ok)
	assert_eq(mode.hang_summary(), mode.current_check.why)
	mode.bind_session(null, null, null, Callable(), Callable(), Callable())
	mode.bind_walls(Callable(), Callable(), Callable(), Callable())


func test_partition_undo_redo_and_sale_use_existing_wall_history() -> void:
	var grid: SimGrid = _sim.world.grid
	var history: ShopEditHistory = ShopEditHistory.new(_editor, grid)
	var edge: Vector3i = Vector3i(9, 6, SimGrid.EDGE_WEST)
	var changes: Dictionary[Vector3i, int] = {edge: SimGrid.Segment.STALL_PARTITION}
	assert_eq(_editor.check_segments(changes).cost, _content.wall_kind(&"stall_partition").price)
	assert_true(history.apply_segments(changes), _editor.last_check.why)
	assert_eq(grid.segment(edge), SimGrid.Segment.STALL_PARTITION)
	assert_true(history.undo(), history.last_refusal)
	assert_eq(grid.segment(edge), SimGrid.Segment.NONE)
	assert_true(history.redo(), history.last_refusal)
	assert_eq(grid.segment(edge), SimGrid.Segment.STALL_PARTITION)
	assert_eq(_editor.check_segments({edge: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]).refund,
		floori(_content.wall_kind(&"stall_partition").price / 2.0))


func _can_spend(_amount: int) -> bool:
	return true


func _record(_amount: int, _category: StringName) -> void:
	pass
