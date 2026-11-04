extends TestCase
## Public segment edits must not cut a real edge that a person already holds.
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CROSSING: Vector3i = Vector3i(5, 4, SimGrid.EDGE_WEST)
const OFF_EDGE: Vector3i = Vector3i(11, 3, SimGrid.EDGE_WEST)

class Walker extends SimAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _history: ShopEditHistory
var _walker: Walker
var _cash: int = 1000
var _entries: Array[Dictionary] = []


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_cash = 1000
	_entries.clear()
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_history = ShopEditHistory.new(_editor, _sim.world.grid)


func after_each() -> void:
	_history = null
	_editor = null
	_walker = null
	_sim = null
	_content = null


func test_morning_cardinal_half_edge_refuses_new_wall_despite_an_open_alternate_route() -> void:
	_partial(Vector2i(4, 4), Vector2i(5, 4), SimClock.Phase.MORNING)
	_assert_refused(CROSSING)


func test_closed_diagonal_half_edge_refuses_a_new_corner_post() -> void:
	_partial(Vector2i(4, 3), Vector2i(5, 4), SimClock.Phase.CLOSED)
	_assert_refused(CROSSING)


func test_harmless_wall_and_deletion_remain_allowed_during_a_half_edge() -> void:
	_partial(Vector2i(4, 4), Vector2i(5, 4), SimClock.Phase.CLOSED)
	var position: Vector3 = _walker.movement_position()
	var progress: float = _walker.move_progress
	var claims: Dictionary = _sim.world.movement.snapshot()
	assert_true(_history.apply_segments({OFF_EDGE: SimGrid.Segment.WALL} as Dictionary[Vector3i, int]), _editor.last_check.why)
	assert_true(_history.apply_segments({OFF_EDGE: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]), _editor.last_check.why)
	assert_eq(_sim.world.grid.segment(OFF_EDGE), SimGrid.Segment.NONE)
	assert_eq(_walker.movement_position(), position)
	assert_eq(_walker.move_progress, progress)
	assert_eq(_sim.world.movement.snapshot(), claims)
	assert_true(_sim.world.grid.step_open(_walker.cell, _walker.next_cell()))


func test_undo_restoring_a_previously_accepted_wall_refuses_current_half_edge_atomically() -> void:
	assert_true(_history.apply_segments({CROSSING: SimGrid.Segment.WALL} as Dictionary[Vector3i, int]), _editor.last_check.why)
	assert_true(_history.apply_segments({CROSSING: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]), _editor.last_check.why)
	_partial(Vector2i(4, 4), Vector2i(5, 4), SimClock.Phase.CLOSED)
	var before: Dictionary = _state()
	assert_false(_history.undo(), "accepted-layout history still protects the actual reserved edge")
	assert_eq(_editor.last_check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_state(), before, "refusal cannot pop history, change books or alter the real movement")


func test_redo_restoring_a_previously_accepted_wall_refuses_current_half_edge_atomically() -> void:
	assert_true(_history.apply_segments({CROSSING: SimGrid.Segment.WALL} as Dictionary[Vector3i, int]), _editor.last_check.why)
	assert_true(_history.undo(), _history.last_refusal)
	_partial(Vector2i(4, 4), Vector2i(5, 4), SimClock.Phase.MORNING)
	var before: Dictionary = _state()
	assert_false(_history.redo(), "redo must not restore a wall through a person already moving")
	assert_eq(_editor.last_check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_state(), before)


func _partial(start: Vector2i, goal: Vector2i, phase: SimClock.Phase) -> void:
	var world: SimWorld = _sim.world
	assert_true(world.grid.is_walkable(start) and world.grid.is_walkable(goal))
	_walker = Walker.new()
	_walker.cell = start
	world.add_agent(_walker)
	assert_true(world.agents.has(_walker), "the real person was admitted at a distinct legal vertex")
	assert_true(_walker.set_destination(world.grid, goal))
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	assert_eq(MovementInvariants.problem(world, before), "")
	assert_eq(_walker.cell, start)
	assert_eq(_walker.next_cell(), goal)
	assert_true(_walker.move_progress > 0.0 and _walker.move_progress < 1.0)
	var snapshot: Dictionary = world.movement.snapshot()
	assert_true(snapshot.edges.has({"id": _walker.id, "from": start, "to": goal}))
	# A real service/clock phase boundary may pause a partial route. Editing is
	# allowed in both phases, but cannot invalidate that already held edge.
	world.clock.phase = phase
	assert_true(_editor.can_edit())


func _assert_refused(edge: Vector3i) -> void:
	var world: SimWorld = _sim.world
	assert_eq(world.grid.segment(edge), SimGrid.Segment.NONE)
	# This isolated segment keeps both endpoints street-reachable via other
	# floor cells; the old global cut-off checks cannot substitute for an edge guard.
	var alternate: SimGrid = world.grid.terrain_copy()
	for placed: PlacedItem in world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		assert_not_null(definition)
		if definition == null:
			return
		assert_not_null(alternate.place_def(definition, placed.origin, placed.quarter_turns, placed.variant_id))
	var segments: Dictionary[Vector3i, int] = {}
	for existing: Vector3i in world.grid.segment_edges():
		segments[existing] = world.grid.segment(existing)
	segments[edge] = SimGrid.Segment.WALL
	alternate.set_segments(segments)
	assert_true(alternate.is_walkable(_walker.cell) and alternate.is_walkable(_walker.next_cell()))
	assert_false(alternate.step_open(_walker.cell, _walker.next_cell()))
	assert_false(alternate.find_path(_walker.cell, _walker.next_cell()).is_empty(), "an ordinary alternate route still exists")
	var before: Dictionary = _state()
	var changes: Dictionary[Vector3i, int] = {edge: SimGrid.Segment.WALL}
	var check: EditCheck = _editor.check_segments(changes)
	assert_false(check.ok, "a wall cannot be placed through a reserved half-edge")
	assert_eq(check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_state(), before, "checking the edit is value-only")
	assert_false(_editor.apply_segments(changes))
	assert_eq(_editor.last_check.why, ShopEditor.PERSON_IN_WAY)
	assert_eq(_state(), before)


func _state() -> Dictionary:
	return {"shop": _editor.to_dict(), "cash": _cash, "entries": _entries.duplicate(true),
		"undo": _history.undo_count(), "redo": _history.redo_count(), "tick": _sim.world.now,
		"claims": _sim.world.movement.snapshot(), "cell": _walker.cell, "next": _walker.next_cell(),
		"goal": _walker.destination(), "progress": _walker.move_progress,
		"path": _walker.path.duplicate(), "index": _walker.path_index}


func _can_spend(amount: int) -> bool:
	return _cash >= amount


func _record(amount: int, category: StringName) -> void:
	_cash += amount
	_entries.append({"amount": amount, "category": category})
