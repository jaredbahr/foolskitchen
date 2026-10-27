class_name BuildMode
extends RefCounted
## Interaction state only. ShopEditor owns validation; injected session methods
## own every commit. Previews never change the grid, reservations or books.

## WALLS is the Walls tool (FK-070): drag along grid lines, click a segment.
enum State { INACTIVE, IDLE, MOVE, BUY, WALLS }

signal changed()

var state: State = State.INACTIVE
var selected_item_id: int = -1
var selected_definition: ItemDef = null
var origin: Vector2i = Vector2i.ZERO
var quarter_turns: int = 0
var grab_offset: Vector2i = Vector2i.ZERO
var current_check: EditCheck = EditCheck.new()
var committed_warning_ids: Array[int] = []
## Walls tool: the kind new edges get, the hovered edge and the dragged run.
var wall_kind: SimGrid.Segment = SimGrid.Segment.WALL
var wall_hover_edge: Vector3i = SimGrid.NO_EDGE
var wall_dragging: bool = false
var wall_drag_start: Vector2i = Vector2i.ZERO
var wall_drag_end: Vector2i = Vector2i.ZERO
## The proposal the current check describes (edge -> new segment).
var wall_changes: Dictionary[Vector3i, int] = {}

var _editor: ShopEditor
var _world: SimWorld
var _content: ContentDB
var _grid: SimGrid
var _clock: SimClock
var _phase: int = -1
var _move_command: Callable
var _buy_command: Callable
var _sell_command: Callable
var _walls_command: Callable
var _committing: bool = false
var _topology_dirty: bool = false


## Rebinding cancels the old interaction, even when the world is unchanged but
## its clock was replaced. Old signal sources are detached before new ones bind.
func bind_session(editor: ShopEditor, world: SimWorld, content: ContentDB,
		move_command: Callable, buy_command: Callable, sell_command: Callable,
		walls_command: Callable = Callable()) -> void:
	if _committing:
		return
	_disconnect_sources()
	_editor = editor
	_world = world
	_content = content
	_grid = world.grid if world != null else null
	_clock = world.clock if world != null else null
	_phase = _clock.phase if _clock != null else -1
	_move_command = move_command
	_buy_command = buy_command
	_sell_command = sell_command
	_walls_command = walls_command
	_clear_ghost(State.INACTIVE)
	committed_warning_ids.clear()
	_topology_dirty = false
	if _grid != null:
		_grid.cells_changed.connect(_on_cells_changed)
	if _clock != null:
		_clock.phase_changed.connect(_on_phase_changed)
	_refresh_committed()
	changed.emit()


func enter() -> bool:
	if _committing:
		return false
	if not _available() or not _editor.can_edit():
		_clear_ghost(State.INACTIVE)
		current_check = EditCheck.new(false, "Build mode is only available in the morning or after closing")
		changed.emit()
		return false
	if is_active() and _clock.phase != _phase:
		_phase = _clock.phase
		exit()
		return false
	if is_active():
		return true
	_phase = _clock.phase
	_clear_ghost(State.IDLE)
	_refresh_committed()
	changed.emit()
	return true


func exit() -> void:
	if not is_active():
		return
	_clear_ghost(State.INACTIVE)
	changed.emit()


func is_active() -> bool:
	return state != State.INACTIVE


func has_ghost() -> bool:
	return state == State.MOVE or state == State.BUY


## A valid item may still start a red ghost (for example a held reservation).
## The return value means selection started, not that placement is allowed.
func pick_up(item_id: int) -> bool:
	return _pick_up(item_id, Vector2i.ZERO, false)


## Keep the clicked tile under the pointer instead of jumping to the origin.
func pick_up_at(item_id: int, clicked_cell: Vector2i) -> bool:
	return _pick_up(item_id, clicked_cell, true)


func _pick_up(item_id: int, clicked_cell: Vector2i, keep_offset: bool) -> bool:
	if not _can_interact():
		return false
	var placed: PlacedItem = _grid.item(item_id)
	if placed == null or not placed.def is ItemDef:
		current_check = EditCheck.new(false, "That item is no longer in the shop")
		changed.emit()
		return false
	if keep_offset and not placed.cells.has(clicked_cell):
		current_check = EditCheck.new(false, "Pick an occupied tile of this item")
		changed.emit()
		return false
	state = State.MOVE
	selected_item_id = item_id
	selected_definition = placed.def as ItemDef
	origin = placed.origin
	grab_offset = clicked_cell - placed.origin if keep_offset else Vector2i.ZERO
	quarter_turns = posmod(placed.quarter_turns, 4)
	_recheck_ghost()
	changed.emit()
	return true


func begin_buy(def_id: StringName, cell: Vector2i) -> bool:
	if not _can_interact():
		return false
	var definition: ItemDef = _content.item(def_id)
	if definition == null:
		current_check = EditCheck.new(false, "Unknown item definition")
		changed.emit()
		return false
	state = State.BUY
	selected_item_id = -1
	selected_definition = definition
	origin = cell
	grab_offset = Vector2i.ZERO
	quarter_turns = 0
	_recheck_ghost()
	changed.emit()
	return true


func update_origin(cell: Vector2i) -> void:
	if not _can_interact() or not has_ghost():
		return
	var proposal: Vector2i = cell - grab_offset if state == State.MOVE else cell
	if origin == proposal and not _topology_dirty:
		return
	origin = proposal
	if _topology_dirty:
		_refresh_committed()
	_recheck_ghost()
	changed.emit()


## World quarter turns deliberately have no camera-quarter input.
func rotate() -> bool:
	if not _can_interact() or not has_ghost():
		return false
	if state == State.MOVE:
		var footprint: Vector2i = GridMath.rotated_footprint(selected_definition.footprint, quarter_turns)
		var rotated_offset: Vector2i = GridMath.rotate_cell(grab_offset, footprint, 1)
		origin += grab_offset - rotated_offset
		grab_offset = rotated_offset
	quarter_turns = (quarter_turns + 1) % 4
	_recheck_ghost()
	changed.emit()
	return true


func commit() -> bool:
	if not _can_interact() or not has_ghost():
		return false
	_recheck_ghost()
	if not current_check.ok:
		changed.emit()
		return false
	var previous_check: EditCheck = _editor.last_check
	_committing = true
	var answer: Variant
	if state == State.MOVE:
		answer = _move_command.call(selected_item_id, origin, quarter_turns)
	else:
		answer = _buy_command.call(selected_definition.id, origin, quarter_turns)
	var accepted: bool = answer is bool and answer
	_finish_command(accepted, previous_check, "The placement was refused; try again")
	return accepted


## -1 is refusal; zero is a successful sale. The session owns cash feedback.
func sell_selected() -> int:
	if not _can_interact() or state != State.MOVE:
		return -1
	current_check = _editor.check_sell(selected_item_id)
	if not current_check.ok:
		changed.emit()
		return -1
	var previous_check: EditCheck = _editor.last_check
	_committing = true
	var answer: Variant = _sell_command.call(selected_item_id)
	var amount: int = answer if answer is int else -1
	var accepted: bool = amount >= 0
	_finish_command(accepted, previous_check, "The sale was refused; try again")
	return amount if accepted else -1


## Esc cancels one ghost (or a wall drag, then the Walls tool); a further Esc leaves the mode.
func cancel() -> void:
	if _committing or not _can_interact():
		return
	if state == State.WALLS and wall_dragging:
		wall_dragging = false
		_recheck_walls()
		changed.emit()
	elif has_ghost() or state == State.WALLS:
		_clear_ghost(State.IDLE)
		changed.emit()
	else:
		exit()


## Explicit invalidation for money/session changes, not a render-frame query.
## Target/turn changes and live topology/phase signals refresh automatically.
func refresh() -> void:
	if _committing:
		_topology_dirty = true
		return
	var before: Dictionary = presentation_state()
	if is_active() and not _can_interact():
		return
	_refresh_committed()
	if has_ghost():
		_recheck_ghost()
	elif state == State.WALLS:
		_recheck_walls()
	if before != presentation_state():
		changed.emit()


## Invalid proposals never erase warnings belonging to actual furniture.
func warning_ids() -> Array[int]:
	return current_check.unreachable.duplicate() if (has_ghost() or state == State.WALLS) and current_check.ok \
		else committed_warning_ids.duplicate()


## Arrays are detached. The shared ItemDef is read-only content for rendering.
## Existing IDs are positive; 0 in a valid buy check denotes its proposed item.
func presentation_state() -> Dictionary:
	return {"state": state, "active": is_active(), "has_ghost": has_ghost(),
		"item_id": selected_item_id, "definition": selected_definition,
		"origin": origin, "quarter_turns": quarter_turns, "grab_offset": grab_offset,
		"check_ok": current_check.ok, "why": current_check.why,
		"unreachable": current_check.unreachable.duplicate(),
		"committed_warning_ids": committed_warning_ids.duplicate(), "warning_ids": warning_ids(),
		"wall_kind": int(wall_kind), "wall_changes": wall_changes.duplicate(),
		"wall_hover_edge": wall_hover_edge, "wall_dragging": wall_dragging,
		"wall_cost": current_check.cost, "wall_refund": current_check.refund}


func _available() -> bool:
	return _editor != null and _world != null and _grid != null and _clock != null and _content != null \
		and _move_command.is_valid() and _buy_command.is_valid() and _sell_command.is_valid()


func _can_interact() -> bool:
	if _committing or not is_active():
		return false
	if not _available() or _clock.phase != _phase or not (
		_clock.phase == SimClock.Phase.MORNING or _clock.phase == SimClock.Phase.CLOSED):
		if _clock != null:
			_phase = _clock.phase
		exit()
		return false
	# A topology signal can arrive while another editor transaction is applying.
	# That temporary guard refuses input without treating the phase as closed.
	return _editor.can_edit()


func _recheck_ghost() -> void:
	if state == State.MOVE:
		current_check = _editor.check_move(selected_item_id, origin, quarter_turns)
	elif state == State.BUY:
		current_check = _editor.check_buy(selected_definition.id, origin, quarter_turns)


func _refresh_committed() -> void:
	if _editor == null:
		return
	var check: EditCheck = _editor.check_current()
	if check.ok:
		committed_warning_ids = check.unreachable.duplicate()
	_topology_dirty = false


func _clear_ghost(next_state: State) -> void:
	state = next_state
	selected_item_id = -1
	selected_definition = null
	origin = Vector2i.ZERO
	grab_offset = Vector2i.ZERO
	quarter_turns = 0
	current_check = EditCheck.new(true)
	wall_hover_edge = SimGrid.NO_EDGE
	wall_dragging = false
	wall_changes.clear()


func _finish_command(accepted: bool, previous_check: EditCheck, fallback_reason: String) -> void:
	# cells_changed can run inside the wrapper, before its books are recorded.
	# Keep the guard until all resulting state and actual-ID warnings settle.
	_refresh_committed()
	if accepted:
		_clear_ghost(State.IDLE if is_active() else State.INACTIVE)
	elif has_ghost():
		var result: EditCheck = _editor.last_check
		current_check = result if result != previous_check and not result.ok else EditCheck.new(false, fallback_reason)
	if _clock.phase != _phase or not _editor.can_edit():
		_phase = _clock.phase
		_clear_ghost(State.INACTIVE)
	_committing = false
	changed.emit()


# --- Walls tool (FK-070) ------------------------------------------------------

## Enters the Walls tool from idle or a held ghost; new edges get `kind`.
func begin_walls(kind: SimGrid.Segment) -> bool:
	if not _can_interact() or not _walls_command.is_valid() or kind == SimGrid.Segment.NONE:
		return false
	_clear_ghost(State.WALLS)
	wall_kind = kind
	_recheck_walls()
	changed.emit()
	return true


## Pointer on the floor plane, in shop metres (x, z). Hover picks the nearest
## grid edge; a drag follows the nearest grid vertex.
func wall_pointer(point: Vector2) -> void:
	if state != State.WALLS or not _can_interact():
		return
	var edge: Vector3i = nearest_edge(point)
	var vertex: Vector2i = nearest_vertex(point)
	if edge == wall_hover_edge and (not wall_dragging or vertex == wall_drag_end) and not _topology_dirty:
		return
	wall_hover_edge = edge
	if wall_dragging:
		wall_drag_end = vertex
	if _topology_dirty:
		_refresh_committed()
	_recheck_walls()
	changed.emit()


func wall_press(point: Vector2) -> bool:
	if state != State.WALLS or not _can_interact():
		return false
	wall_dragging = true
	wall_drag_start = nearest_vertex(point)
	wall_drag_end = wall_drag_start
	wall_hover_edge = nearest_edge(point)
	_recheck_walls()
	changed.emit()
	return true


## Ends a drag: a run builds the dragged line; a click without a run changes
## the clicked edge (empty -> chosen kind, wall -> doorway -> window -> wall,
## outer face solid <-> window). Returns true when the shop changed.
func wall_release(point: Vector2) -> bool:
	if state != State.WALLS or not wall_dragging or not _can_interact():
		return false
	wall_drag_end = nearest_vertex(point)
	if wall_drag_end == wall_drag_start:
		wall_hover_edge = nearest_edge(point)
	_recheck_walls()
	wall_dragging = false
	return _commit_walls()


## Delete removes the hovered segment (refunded like furniture).
func wall_remove_hovered() -> bool:
	if state != State.WALLS or wall_dragging or not _can_interact() or _grid == null \
			or _grid.segment(wall_hover_edge) == SimGrid.Segment.NONE:
		return false
	wall_changes = {wall_hover_edge: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]
	current_check = _editor.check_segments(wall_changes)
	return _commit_walls()


## One player sentence for the HUD: what the proposal costs, or why it can't.
func wall_summary() -> String:
	if state != State.WALLS:
		return ""
	if not current_check.ok:
		return current_check.why
	var added: int = 0
	var removed: int = 0
	var last: int = SimGrid.Segment.NONE
	for edge: Vector3i in current_check.changes:
		last = current_check.changes[edge]
		if last == SimGrid.Segment.NONE:
			removed += 1
		else:
			added += 1
	var text: String = ""
	var definition: WallKindDef = _content.wall_kind_for(last) if _content != null else null
	if removed > 0 and added == 0:
		text = "Remove"
	elif added == 1 and definition != null:
		text = definition.display_name
	elif definition != null:
		text = "%d %ss" % [added, definition.display_name.to_lower()]
	if current_check.cost > 0:
		text += "  $%d" % current_check.cost
	if current_check.refund > 0:
		text += "  (refund $%d)" % current_check.refund
	return text.strip_edges()


static func nearest_vertex(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / GridMath.CELL_SIZE), roundi(point.y / GridMath.CELL_SIZE))


static func nearest_edge(point: Vector2) -> Vector3i:
	var u: float = point.x / GridMath.CELL_SIZE
	var v: float = point.y / GridMath.CELL_SIZE
	if absf(u - roundf(u)) <= absf(v - roundf(v)):
		return Vector3i(roundi(u), floori(v), SimGrid.EDGE_WEST)
	return Vector3i(floori(u), roundi(v), SimGrid.EDGE_NORTH)


## Edges of a straight run between two vertices, along the longer axis.
static func run_edges(start: Vector2i, end: Vector2i) -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	var delta: Vector2i = end - start
	if absi(delta.x) >= absi(delta.y):
		for x: int in range(mini(start.x, end.x), maxi(start.x, end.x)):
			edges.append(Vector3i(x, start.y, SimGrid.EDGE_NORTH))
	else:
		for y: int in range(mini(start.y, end.y), maxi(start.y, end.y)):
			edges.append(Vector3i(start.x, y, SimGrid.EDGE_WEST))
	return edges


func _recheck_walls() -> void:
	if state != State.WALLS or _editor == null:
		return
	wall_changes.clear()
	if wall_dragging and wall_drag_end != wall_drag_start:
		var run: Array[Vector3i] = run_edges(wall_drag_start, wall_drag_end)
		wall_changes = _editor.run_changes(run, wall_kind)
		if wall_changes.is_empty():
			current_check = EditCheck.new(false, "These walls are already built")
			return
	elif _grid != null and _grid.edge_in_bounds(wall_hover_edge):
		wall_changes[wall_hover_edge] = _editor.next_segment(wall_hover_edge, wall_kind)
	if wall_changes.is_empty():
		current_check = EditCheck.new(false, WallRules.NOT_INSIDE)
		return
	current_check = _editor.check_segments(wall_changes)


func _commit_walls() -> bool:
	if not current_check.ok or wall_changes.is_empty():
		changed.emit()
		return false
	var previous_check: EditCheck = _editor.last_check
	var proposal: Dictionary[Vector3i, int] = wall_changes.duplicate()
	_committing = true
	var answer: Variant = _walls_command.call(proposal)
	var accepted: bool = answer is bool and answer
	_refresh_committed()
	if not accepted:
		var result: EditCheck = _editor.last_check
		current_check = result if result != previous_check and not result.ok \
			else EditCheck.new(false, "The change was refused; try again")
	_committing = false
	if _clock.phase != _phase or not _editor.can_edit():
		_phase = _clock.phase
		_clear_ghost(State.INACTIVE)
	elif accepted:
		_recheck_walls()
	changed.emit()
	return accepted


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	_topology_dirty = true
	if not _committing:
		refresh()


func _on_phase_changed(_day: int, phase: SimClock.Phase) -> void:
	_phase = phase
	exit()


func _disconnect_sources() -> void:
	if _grid != null and _grid.cells_changed.is_connected(_on_cells_changed):
		_grid.cells_changed.disconnect(_on_cells_changed)
	if _clock != null and _clock.phase_changed.is_connected(_on_phase_changed):
		_clock.phase_changed.disconnect(_on_phase_changed)
