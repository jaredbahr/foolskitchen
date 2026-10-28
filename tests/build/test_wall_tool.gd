extends TestCase
## FK-070 Walls tool: interaction state only, committed through a Main-like wrapper.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CAPTURE: Script = preload("res://tools/screenshot.gd")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _mode: BuildMode
var _cash: int = 1000
var _entries: Array[Dictionary] = []
var _wall_calls: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 55, errors)
	assert_eq(errors, [] as Array[String])
	_cash = 1000
	_entries.clear()
	_wall_calls = 0
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash))
	_mode = BuildMode.new()
	_mode.bind_session(_editor, _sim.world, _content, _shop_move, _shop_buy, _shop_sell, _shop_walls)


func after_each() -> void:
	_mode.bind_session(null, null, null, Callable(), Callable(), Callable())
	_mode = null
	_editor = null
	_sim = null
	_content = null


func test_pointer_maps_to_nearest_grid_line_and_vertex() -> void:
	# Cell (4, 6) spans x 2.0-2.5 and z 3.0-3.5.
	assert_eq(BuildMode.nearest_edge(Vector2(2.03, 3.2)), Vector3i(4, 6, SimGrid.EDGE_WEST))
	assert_eq(BuildMode.nearest_edge(Vector2(2.2, 3.47)), Vector3i(4, 7, SimGrid.EDGE_NORTH))
	assert_eq(BuildMode.nearest_vertex(Vector2(2.2, 3.1)), Vector2i(4, 6))
	assert_eq(BuildMode.run_edges(Vector2i(9, 5), Vector2i(9, 8)),
		[Vector3i(9, 5, 0), Vector3i(9, 6, 0), Vector3i(9, 7, 0)] as Array[Vector3i])
	assert_eq(BuildMode.run_edges(Vector2i(4, 9), Vector2i(2, 10)),
		[Vector3i(2, 9, 1), Vector3i(3, 9, 1)] as Array[Vector3i], "the longer axis wins")


func test_drag_previews_a_priced_run_then_builds_it() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.WALL))
	assert_eq(_mode.state, BuildMode.State.WALLS)
	assert_true(_mode.wall_press(_vertex(9, 5)))
	_mode.wall_pointer(_vertex(9, 8))
	var state: Dictionary = _mode.presentation_state()
	assert_eq((state["wall_changes"] as Dictionary).size(), 3)
	assert_true(state["check_ok"])
	assert_eq(state["wall_cost"], 30)
	assert_eq(_mode.wall_summary(), "3 walls  $30")
	assert_false(_sim.world.grid.has_segments(), "a preview never builds")
	assert_true(_mode.wall_release(_vertex(9, 8)))
	assert_eq(_wall_calls, 1)
	assert_eq(_sim.world.grid.segment_edges().size(), 3)
	assert_eq(_cash, 970)
	assert_eq(_mode.state, BuildMode.State.WALLS, "the tool stays ready for the next run")


func test_click_cycles_a_segment_and_delete_removes_it() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.WALL))
	var on_edge: Vector2 = Vector2(9 * 0.5, 6.5 * 0.5)
	assert_true(_mode.wall_press(on_edge))
	assert_true(_mode.wall_release(on_edge))
	var edge: Vector3i = Vector3i(9, 6, SimGrid.EDGE_WEST)
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.WALL)
	_mode.wall_pointer(on_edge)
	assert_eq(_mode.wall_summary(), "Doorway  $15  (refund $5)")
	_mode.wall_press(on_edge)
	assert_true(_mode.wall_release(on_edge))
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.DOORWAY)
	_mode.wall_press(on_edge)
	assert_true(_mode.wall_release(on_edge))
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.WINDOW)
	assert_true(_mode.wall_remove_hovered())
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.NONE)
	assert_false(_mode.wall_remove_hovered(), "nothing left to remove")


func test_refused_run_shows_the_reason_and_changes_nothing() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.WALL))
	# Wall off the east corner completely: its seats would be cut off.
	_mode.wall_press(_vertex(9, 5))
	_mode.wall_pointer(_vertex(9, 10))
	assert_false(_mode.current_check.ok)
	assert_eq(_mode.wall_summary(), WallRules.CUT_SEAT)
	assert_false(_mode.wall_release(_vertex(9, 10)))
	assert_eq(_wall_calls, 0)
	assert_false(_sim.world.grid.has_segments())
	assert_eq(_cash, 1000)


func test_doorway_tool_builds_and_removes_a_back_door() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.DOORWAY))
	var point: Vector2 = Vector2(13 * 0.5, 6.5 * 0.5)
	assert_true(_mode.wall_press(point))
	assert_true(_mode.wall_release(point), _mode.current_check.why)
	assert_eq(WallRules.delivery_cell(_sim.world.grid), Vector2i(12, 6))
	assert_eq(_wall_calls, 1)
	assert_eq(_cash, 985)
	assert_true(_mode.wall_press(point))
	assert_true(_mode.wall_release(point))
	assert_eq(_wall_calls, 2)
	assert_false(_sim.world.grid.is_walkable(Vector2i(13, 6)))


func test_escape_cancels_the_drag_then_the_tool_then_build_mode() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.DOORWAY))
	_mode.wall_press(_vertex(9, 5))
	_mode.wall_pointer(_vertex(9, 7))
	_mode.cancel()
	assert_eq(_mode.state, BuildMode.State.WALLS)
	assert_false(_mode.wall_dragging)
	_mode.cancel()
	assert_eq(_mode.state, BuildMode.State.IDLE)
	_mode.cancel()
	assert_eq(_mode.state, BuildMode.State.INACTIVE)
	assert_eq(_wall_calls, 0)


func test_service_phase_leaves_the_tool() -> void:
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.WALL))
	_sim.world.clock.start_service()
	_mode.wall_press(_vertex(9, 5))
	assert_eq(_mode.state, BuildMode.State.INACTIVE)
	assert_false(_mode.begin_walls(SimGrid.Segment.WALL))
	assert_false(_sim.world.grid.has_segments())


func test_walls_need_the_session_command() -> void:
	_mode.bind_session(_editor, _sim.world, _content, _shop_move, _shop_buy, _shop_sell)
	assert_true(_mode.enter())
	assert_false(_mode.begin_walls(SimGrid.Segment.WALL))
	assert_eq(_mode.state, BuildMode.State.IDLE)


func test_review_capture_fixture_is_an_accepted_edit() -> void:
	var fixture: Dictionary[Vector3i, int] = CAPTURE.walls_fixture()
	var check: EditCheck = _editor.check_segments(fixture)
	assert_true(check.ok, check.why)
	assert_eq(check.changes.size(), fixture.size())


func _vertex(x: int, y: int) -> Vector2:
	return Vector2(x, y) * GridMath.CELL_SIZE


func _shop_walls(changes: Dictionary[Vector3i, int]) -> bool:
	_wall_calls += 1
	return _editor.apply_segments(changes)


func _shop_move(item_id: int, origin: Vector2i, turns: int) -> bool:
	return _editor.move(item_id, origin, turns)


func _shop_buy(def_id: StringName, origin: Vector2i, turns: int = 0) -> bool:
	return _editor.buy(def_id, origin, turns)


func _shop_sell(item_id: int) -> int:
	return _editor.sell(item_id)


func _can_spend(amount: int) -> bool:
	return amount <= _cash


func _record_cash(amount: int, category: StringName) -> void:
	_cash += amount
	_entries.append({"amount": amount, "category": category})
