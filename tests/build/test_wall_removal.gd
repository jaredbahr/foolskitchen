extends TestCase
## FK-113: Remove reuses the checked wall transaction, including exact undo.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _mode: BuildMode
var _cash: int
var _wall_calls: int


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 55, errors)
	assert_eq(errors, [] as Array[String])
	_cash = 3000
	_wall_calls = 0
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)
	_mode = BuildMode.new()
	_mode.bind_session(_editor, _sim.world, _content, _move, _buy, _sell, _walls)


func after_each() -> void:
	_mode.bind_session(null, null, null, Callable(), Callable(), Callable())
	_mode = null
	_history = null
	_editor = null
	_sim = null
	_content = null


func test_remove_click_previews_only_removal_and_undo_restores_exact_cash() -> void:
	var edge: Vector3i = Vector3i(9, 6, SimGrid.EDGE_WEST)
	assert_true(_editor.apply_segments({edge: SimGrid.Segment.WALL} as Dictionary[Vector3i, int]))
	var before: int = _cash
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.NONE), "Remove is an available Walls mode")
	var point: Vector2 = Vector2(9.0, 6.5) * GridMath.CELL_SIZE
	_mode.wall_pointer(point)
	assert_eq(_mode.wall_changes, {edge: SimGrid.Segment.NONE} as Dictionary[Vector3i, int])
	assert_true(_mode.current_check.ok, _mode.current_check.why)
	assert_eq(_mode.current_check.cost, 0)
	assert_eq(_mode.current_check.refund, 5)
	assert_true(_mode.wall_summary().contains("refund $5"))
	assert_eq(_cash, before, "hover never refunds a wall")
	assert_true(_mode.wall_press(point))
	assert_true(_mode.wall_release(point))
	assert_eq(_wall_calls, 1)
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.NONE)
	assert_eq(_cash, before + 5)
	assert_true(_history.undo())
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.WALL)
	assert_eq(_cash, before)
	assert_true(_history.redo())
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.NONE)
	assert_eq(_cash, before + 5)


func test_remove_drag_skips_empty_edges_and_refunds_the_run_as_one_undo_step() -> void:
	var run: Dictionary[Vector3i, int] = {
		Vector3i(9, 5, SimGrid.EDGE_WEST): SimGrid.Segment.WALL,
		Vector3i(9, 7, SimGrid.EDGE_WEST): SimGrid.Segment.WALL,
	}
	assert_true(_editor.apply_segments(run), _editor.last_check.why)
	var before: int = _cash
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.NONE))
	assert_true(_mode.wall_press(Vector2(9, 5) * GridMath.CELL_SIZE))
	_mode.wall_pointer(Vector2(9, 8) * GridMath.CELL_SIZE)
	var expected: Dictionary[Vector3i, int] = {
		Vector3i(9, 5, SimGrid.EDGE_WEST): SimGrid.Segment.NONE,
		Vector3i(9, 7, SimGrid.EDGE_WEST): SimGrid.Segment.NONE,
	}
	assert_eq(_mode.wall_changes, expected, "a gap never becomes a wall in Remove mode")
	assert_eq(_mode.current_check.refund, 10)
	assert_eq(_mode.current_check.cost, 0)
	assert_true(_mode.wall_release(Vector2(9, 8) * GridMath.CELL_SIZE))
	assert_eq(_wall_calls, 1)
	assert_eq(_history.undo_count(), 1)
	assert_eq(_cash, before + 10)
	assert_true(_history.undo())
	assert_eq(_cash, before)
	for edge: Vector3i in run:
		assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.WALL)
	assert_eq(_sim.world.grid.segment(Vector3i(9, 6, SimGrid.EDGE_WEST)), SimGrid.Segment.NONE)


func test_refused_remove_exposes_existing_reason_and_never_commits_or_refunds() -> void:
	var edge: Vector3i = Vector3i(13, 6, SimGrid.EDGE_WEST)
	assert_true(_editor.apply_segments({edge: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	var person: SimAgent = SimAgent.new()
	person.cell = Vector2i(13, 6)
	_sim.world.add_agent(person)
	var before: int = _cash
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.NONE))
	var point: Vector2 = Vector2(13.0, 6.5) * GridMath.CELL_SIZE
	_mode.wall_pointer(point)
	assert_false(_mode.current_check.ok)
	assert_eq(_mode.wall_summary(), WallRules.CUT_PERSON)
	_mode.wall_press(point)
	assert_false(_mode.wall_release(point))
	assert_eq(_mode.wall_summary(), WallRules.CUT_PERSON)
	assert_eq(_wall_calls, 0)
	assert_eq(_cash, before)
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.DOORWAY)
	assert_eq(_history.undo_count(), 0)


func test_delete_shortcut_still_removes_hovered_wall_in_the_build_mode() -> void:
	var edge: Vector3i = Vector3i(9, 6, SimGrid.EDGE_WEST)
	assert_true(_editor.apply_segments({edge: SimGrid.Segment.WALL} as Dictionary[Vector3i, int]))
	var before: int = _cash
	assert_true(_mode.enter())
	assert_true(_mode.begin_walls(SimGrid.Segment.WALL))
	_mode.wall_pointer(Vector2(9.0, 6.5) * GridMath.CELL_SIZE)
	assert_true(_mode.wall_remove_hovered())
	assert_eq(_sim.world.grid.segment(edge), SimGrid.Segment.NONE)
	assert_eq(_cash, before + 5)


func _walls(changes: Dictionary[Vector3i, int]) -> bool:
	_wall_calls += 1
	return _history.apply_segments(changes)


func _move(item_id: int, cell: Vector2i, turns: int) -> bool:
	return _history.move(item_id, cell, turns)


func _buy(def_id: StringName, cell: Vector2i, turns: int = 0) -> bool:
	return _history.buy(def_id, cell, turns)


func _sell(item_id: int) -> int:
	return _history.sell(item_id)


func _can_spend(amount: int) -> bool:
	return amount <= _cash


func _record(amount: int, _category: StringName, _note: String = "") -> void:
	_cash += amount
