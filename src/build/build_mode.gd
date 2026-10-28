class_name BuildMode
extends RefCounted
## Interaction state only. ShopEditor owns validation; injected session methods
## own every commit. Previews never change the grid, reservations or books.

## WALLS is the Walls tool (FK-070): drag along grid lines, click a segment.
## FLOOR is the Floor tool (FK-080): drag a rectangle of lot cells.
## ROOMS is the Rooms tool (FK-101): drag a rectangle to paint a room type.
enum State { INACTIVE, IDLE, MOVE, BUY, WALLS, FLOOR, ROOMS }
## What a click on placed furniture does while IDLE (FK-085, Sims-style):
## HAND picks it up to move or rotate, EYEDROPPER starts buying another of
## it (in its colour), SELL sells it straight away.
enum Tool { HAND, EYEDROPPER, SELL }

signal changed()

var state: State = State.INACTIVE
var selected_item_id: int = -1
var selected_definition: ItemDef = null
var origin: Vector2i = Vector2i.ZERO
var quarter_turns: int = 0
var grab_offset: Vector2i = Vector2i.ZERO
var current_check: EditCheck = EditCheck.new()
var tool: Tool = Tool.HAND
## The placed item under the pointer while IDLE (-1 for none), for the sell
## and eyedropper tools' hover highlight and refund text.
var hover_item_id: int = -1
## Colour the eyedropper copied; a buy commits it as a free repaint.
var buy_swatch_id: StringName = &""
var committed_warning_ids: Array[int] = []
var committed_seat_warnings: Dictionary[int, String] = {}
## Walls tool: the kind new edges get, the hovered edge and the dragged run.
var wall_kind: SimGrid.Segment = SimGrid.Segment.WALL
var wall_hover_edge: Vector3i = SimGrid.NO_EDGE
var wall_dragging: bool = false
var wall_drag_start: Vector2i = Vector2i.ZERO
var wall_drag_end: Vector2i = Vector2i.ZERO
## The proposal the current check describes (edge -> new segment).
var wall_changes: Dictionary[Vector3i, int] = {}
## Floor tool: the hovered cell, the dragged rectangle and whether it removes.
var floor_hover: Vector2i = SimGrid.NO_CELL
var floor_dragging: bool = false
var floor_drag_start: Vector2i = Vector2i.ZERO
var floor_removing: bool = false
## Rooms tool: the room being painted (SimGrid.Room), the hovered cell and the drag.
var room_kind: int = SimGrid.Room.DINING
var room_hover: Vector2i = SimGrid.NO_CELL
var room_dragging: bool = false
var room_drag_start: Vector2i = Vector2i.ZERO
## Floor checks by [rect, removing] for the current topology/books (a check
## costs ~15 ms); cleared by refresh(), topology signals and commits.
var _floor_checks: Dictionary = {}

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
var _floor_command: Callable
var _rooms_command: Callable
var _committing: bool = false
var _topology_dirty: bool = false


## Rebinding cancels the old interaction, even when the world is unchanged but
## its clock was replaced. Old signal sources are detached before new ones bind.
func bind_session(editor: ShopEditor, world: SimWorld, content: ContentDB,
		move_command: Callable, buy_command: Callable, sell_command: Callable,
		walls_command: Callable = Callable(), floor_command: Callable = Callable(),
		rooms_command: Callable = Callable()) -> void:
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
	_floor_command = floor_command
	_rooms_command = rooms_command
	_clear_ghost(State.INACTIVE)
	committed_warning_ids.clear()
	committed_seat_warnings.clear()
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
	tool = Tool.HAND
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
	buy_swatch_id = &""
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


## World quarter turns deliberately have no camera-quarter input. `steps` is
## +1 (R or `.`, clockwise) or -1 (`,`, the other way).
func rotate(steps: int = 1) -> bool:
	if not _can_interact() or not has_ghost():
		return false
	var turn: int = posmod(steps, 4)
	if state == State.MOVE:
		var footprint: Vector2i = GridMath.rotated_footprint(selected_definition.footprint, quarter_turns)
		var rotated_offset: Vector2i = GridMath.rotate_cell(grab_offset, footprint, turn)
		origin += grab_offset - rotated_offset
		grab_offset = rotated_offset
	quarter_turns = (quarter_turns + turn) % 4
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
	elif not buy_swatch_id.is_empty():
		answer = _buy_command.call(selected_definition.id, origin, quarter_turns, buy_swatch_id)
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


## Esc backs out one level: a ghost or drag, then the Walls/Floor tool or the
## eyedropper/sell tool (back to the hand), and then the mode itself.
func cancel() -> void:
	if _committing or not _can_interact():
		return
	if cancel_ghost():
		return
	if state == State.IDLE and tool != Tool.HAND:
		set_tool(Tool.HAND)
	else:
		exit()


## Right-click: drops a held ghost or a drag (and a Walls/Floor tool) but never
## leaves the mode. Returns whether anything was cancelled.
func cancel_ghost() -> bool:
	if _committing or not _can_interact():
		return false
	if state == State.WALLS and wall_dragging:
		wall_dragging = false
		_recheck_walls()
		changed.emit()
	elif state == State.FLOOR and floor_dragging:
		floor_dragging = false
		_recheck_floor()
		changed.emit()
	elif state == State.ROOMS and room_dragging:
		room_dragging = false
		_recheck_rooms()
		changed.emit()
	elif has_ghost() or state == State.WALLS or state == State.FLOOR or state == State.ROOMS:
		_clear_ghost(State.IDLE)
		changed.emit()
	else:
		return false
	return true


func set_tool(next: Tool) -> void:
	if tool == next and state == State.IDLE:
		return
	if is_active() and state != State.IDLE and _can_interact():
		_clear_ghost(State.IDLE)
	tool = next
	if is_active():
		_recheck_hover()
	changed.emit()


## The placed item under the pointer while IDLE (-1 for none).
func hover_item(item_id: int) -> void:
	var next: int = item_id if state == State.IDLE and _grid != null and _grid.item(item_id) != null else -1
	if next == hover_item_id:
		return
	hover_item_id = next
	_recheck_hover()
	changed.emit()


## Sells the hovered item (the sell tool, or Del while idle). -1 is refusal.
func sell_hovered() -> int:
	if not _can_interact() or state != State.IDLE or hover_item_id < 0:
		return -1
	current_check = _editor.check_sell(hover_item_id)
	if not current_check.ok:
		changed.emit()
		return -1
	var previous_check: EditCheck = _editor.last_check
	_committing = true
	var answer: Variant = _sell_command.call(hover_item_id)
	var amount: int = answer if answer is int else -1
	var accepted: bool = amount >= 0
	_finish_command(accepted, previous_check, "The sale was refused; try again")
	if not accepted and current_check.ok:
		current_check = EditCheck.new(false, "The sale was refused; try again")
	return amount if accepted else -1


## The eyedropper: start buying another of a placed item, in its colour.
## Items that are not in the catalogue (the door) are refused with a reason.
func eyedrop(item_id: int, cell: Vector2i) -> bool:
	if not _can_interact():
		return false
	var placed: PlacedItem = _grid.item(item_id)
	var definition: ItemDef = placed.def as ItemDef if placed != null else null
	if definition == null:
		return false
	if not definition.catalogue_visible or definition.category == ItemDef.Category.DOOR:
		current_check = EditCheck.new(false, "%s isn't sold in the catalogue" % definition.display_name)
		changed.emit()
		return false
	if not begin_buy(definition.id, cell):
		return false
	quarter_turns = posmod(placed.quarter_turns, 4)
	buy_swatch_id = placed.swatch_id if definition.paintable else &""
	_recheck_ghost()
	changed.emit()
	return true


## One player sentence for the hovered item under the sell or eyedropper tool.
func hover_summary() -> String:
	if state != State.IDLE or hover_item_id < 0 or _grid == null:
		return ""
	var placed: PlacedItem = _grid.item(hover_item_id)
	var definition: ItemDef = placed.def as ItemDef if placed != null else null
	if definition == null:
		return ""
	match tool:
		Tool.SELL:
			return "Sell %s for %s" % [definition.display_name, Fmt.money(ShopEditor.sale_refund(definition))] \
				if current_check.ok else current_check.why
		Tool.EYEDROPPER:
			return "Place another %s" % definition.display_name if definition.catalogue_visible \
				and definition.category != ItemDef.Category.DOOR else "%s isn't sold in the catalogue" % definition.display_name
	return ""


func _recheck_hover() -> void:
	if state != State.IDLE:
		return
	if tool == Tool.SELL and hover_item_id >= 0 and _editor != null:
		current_check = _editor.check_sell(hover_item_id)
	else:
		current_check = EditCheck.new(true)


## Explicit invalidation for money/session changes, not a render-frame query.
## Target/turn changes and live topology/phase signals refresh automatically.
func refresh() -> void:
	if _committing:
		_topology_dirty = true
		return
	var before: Dictionary = presentation_state()
	_floor_checks.clear()
	if is_active() and not _can_interact():
		return
	_refresh_committed()
	if has_ghost():
		_recheck_ghost()
	elif state == State.WALLS:
		_recheck_walls()
	elif state == State.FLOOR:
		_recheck_floor()
	elif state == State.ROOMS:
		_recheck_rooms()
	elif state == State.IDLE:
		_recheck_hover()
	if before != presentation_state():
		changed.emit()


## Invalid proposals never erase warnings belonging to actual furniture.
func warning_ids() -> Array[int]:
	var ids: Array[int] = current_check.unreachable.duplicate() \
		if _proposal_active() and current_check.ok else committed_warning_ids.duplicate()
	for item_id: int in seat_warnings():
		if not ids.has(item_id):
			ids.append(item_id)
	ids.sort()
	return ids


## A ghost, wall run or floor drag is being checked against the live shop.
func _proposal_active() -> bool:
	return has_ghost() or state == State.WALLS or state == State.FLOOR or state == State.ROOMS


func seat_warnings() -> Dictionary[int, String]:
	return current_check.seat_warnings.duplicate() \
		if _proposal_active() and current_check.ok else committed_seat_warnings.duplicate()


## Invalid actions take precedence; permitted layouts may still lose seats.
func feedback_text() -> String:
	if _proposal_active() and not current_check.ok and not current_check.why.is_empty():
		return current_check.why
	var warnings: Dictionary[int, String] = seat_warnings()
	var messages: PackedStringArray = []
	for item_id: int in warning_ids():
		if warnings.has(item_id) and not messages.has(warnings[item_id]):
			messages.append(warnings[item_id])
	return "\n".join(messages)


## Arrays are detached. The shared ItemDef is read-only content for rendering.
## Existing IDs are positive; 0 in a valid buy check denotes its proposed item.
func presentation_state() -> Dictionary:
	return {"state": state, "active": is_active(), "has_ghost": has_ghost(),
		"item_id": selected_item_id, "definition": selected_definition,
		"origin": origin, "quarter_turns": quarter_turns, "grab_offset": grab_offset,
		"check_ok": current_check.ok, "why": current_check.why,
		"unreachable": current_check.unreachable.duplicate(),
		"seat_warnings": seat_warnings(),
		"feedback": feedback_text(),
		"committed_warning_ids": committed_warning_ids.duplicate(), "warning_ids": warning_ids(),
		"wall_kind": int(wall_kind), "wall_changes": wall_changes.duplicate(),
		"wall_hover_edge": wall_hover_edge, "wall_dragging": wall_dragging,
		"wall_cost": current_check.cost, "wall_refund": current_check.refund,
		"floor_cells": floor_proposal(), "floor_removing": floor_removing,
		"floor_dragging": floor_dragging, "lot": lot_rect(), "lot_open": lot_open_cells(),
		"tool": int(tool), "hover_item_id": hover_item_id,
		"room_kind": room_kind, "room_cells": room_proposal(), "room_dragging": room_dragging}


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
		committed_seat_warnings = check.seat_warnings.duplicate()
	_topology_dirty = false


func _clear_ghost(next_state: State) -> void:
	state = next_state
	_floor_checks.clear()
	selected_item_id = -1
	selected_definition = null
	origin = Vector2i.ZERO
	grab_offset = Vector2i.ZERO
	quarter_turns = 0
	current_check = EditCheck.new(true)
	hover_item_id = -1
	buy_swatch_id = &""
	wall_hover_edge = SimGrid.NO_EDGE
	wall_dragging = false
	wall_changes.clear()
	floor_hover = SimGrid.NO_CELL
	floor_dragging = false
	floor_removing = false
	room_hover = SimGrid.NO_CELL
	room_dragging = false


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


# --- Floor tool (FK-080) ------------------------------------------------------

## Enters the Floor tool from idle or a held ghost. Only shops with a lot can grow.
func begin_floor() -> bool:
	if not _can_interact() or not _floor_command.is_valid() or _editor.footprint() == null \
			or not _editor.footprint().has_lot():
		return false
	_clear_ghost(State.FLOOR)
	_recheck_floor()
	changed.emit()
	return true


## Pointer over a floor cell. `removing` (Shift) previews taking floor away.
func floor_pointer(cell: Vector2i, removing: bool = false) -> void:
	if state != State.FLOOR or not _can_interact():
		return
	if cell == floor_hover and (floor_dragging or removing == floor_removing) and not _topology_dirty:
		return
	floor_hover = cell
	if not floor_dragging:
		floor_removing = removing
	if _topology_dirty:
		_refresh_committed()
	_recheck_floor()
	changed.emit()


func floor_press(cell: Vector2i, removing: bool = false) -> bool:
	if state != State.FLOOR or not _can_interact():
		return false
	floor_dragging = true
	floor_removing = removing
	floor_drag_start = cell
	floor_hover = cell
	_recheck_floor()
	changed.emit()
	return true


## Ends a drag: buys (or removes) the floor in the dragged rectangle.
func floor_release(cell: Vector2i) -> bool:
	if state != State.FLOOR or not floor_dragging or not _can_interact():
		return false
	floor_hover = cell
	_recheck_floor()
	floor_dragging = false
	if not current_check.ok or current_check.floor_cells.is_empty():
		changed.emit()
		return false
	var previous_check: EditCheck = _editor.last_check
	var proposal: Array[Vector2i] = current_check.floor_cells.duplicate()
	_floor_checks.clear()
	_committing = true
	var answer: Variant = _floor_command.call(proposal, not floor_removing)
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
		_recheck_floor()
	changed.emit()
	return accepted


## Cells of the dragged rectangle (or the hovered cell), row-major.
func floor_rect() -> Rect2i:
	if floor_hover == SimGrid.NO_CELL:
		return Rect2i()
	var start: Vector2i = floor_drag_start if floor_dragging else floor_hover
	var low: Vector2i = start.min(floor_hover)
	return Rect2i(low, (start.max(floor_hover) - low) + Vector2i.ONE)


## The cells a valid check would change, else every cell of the rectangle.
func floor_proposal() -> Array[Vector2i]:
	if state != State.FLOOR:
		return []
	if current_check.ok and not current_check.floor_cells.is_empty():
		return current_check.floor_cells.duplicate()
	return [] as Array[Vector2i] if current_check.why.is_empty() else _rect_cells(floor_rect())


## Where floor may be bought (the lot inside its wall ring), empty without a lot.
func lot_rect() -> Rect2i:
	if _editor == null or _editor.footprint() == null or not _editor.footprint().has_lot():
		return Rect2i()
	return _editor.footprint().floor_area()


## Unbuilt lot cells (no floor or wall yet), for the pale lot outline.
func lot_open_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_active() or _grid == null or lot_rect() == Rect2i():
		return out
	for cell: Vector2i in _editor.footprint().lot_cells(lot_rect()):
		if _editor.footprint().can_hold(cell) and _grid.terrain(cell) == SimGrid.Terrain.OUTSIDE:
			out.append(cell)
	return out


## One player sentence: what the floor proposal costs, or why it can't.
func floor_summary() -> String:
	if state != State.FLOOR:
		return ""
	if not current_check.ok:
		return current_check.why
	var count: int = current_check.floor_cells.size()
	var text: String = "%s %d floor tile%s" % ["Remove" if not current_check.floor_adding else "Add",
		count, "" if count == 1 else "s"]
	if current_check.cost > 0:
		text += "  $%d" % current_check.cost
	if current_check.refund > 0:
		text += "  (refund $%d)" % current_check.refund
	return text


func _recheck_floor() -> void:
	if state != State.FLOOR or _editor == null:
		return
	var cells: Array[Vector2i] = _rect_cells(floor_rect())
	# Plain hover over the building or the street proposes nothing; a drag may
	# start inside the shop and run out onto the lot.
	if cells.is_empty() or (not floor_dragging and _editor.footprint() != null
			and not _editor.footprint().can_hold(floor_hover)):
		current_check = EditCheck.new(false, "")
		return
	var key: Array = [floor_rect(), floor_removing]
	if not _floor_checks.has(key):
		_floor_checks[key] = _editor.check_floor(cells, not floor_removing)
	current_check = _floor_checks[key]


static func _rect_cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out


# --- Rooms tool (FK-101) -------------------------------------------------------

## Enters the Rooms tool: a drag paints `kind` (SimGrid.Room) onto floor cells.
func begin_rooms(kind: int) -> bool:
	if not _can_interact() or not _rooms_command.is_valid() \
			or kind < SimGrid.Room.DINING or kind > SimGrid.Room.STORAGE:
		return false
	_clear_ghost(State.ROOMS)
	room_kind = kind
	_recheck_rooms()
	changed.emit()
	return true


func rooms_pointer(cell: Vector2i) -> void:
	if state != State.ROOMS or not _can_interact():
		return
	if cell == room_hover and not _topology_dirty:
		return
	room_hover = cell
	if _topology_dirty:
		_refresh_committed()
	_recheck_rooms()
	changed.emit()


func rooms_press(cell: Vector2i) -> bool:
	if state != State.ROOMS or not _can_interact():
		return false
	room_dragging = true
	room_drag_start = cell
	room_hover = cell
	_recheck_rooms()
	changed.emit()
	return true


## Ends a drag: paints the room onto the dragged rectangle's floor.
func rooms_release(cell: Vector2i) -> bool:
	if state != State.ROOMS or not room_dragging or not _can_interact():
		return false
	room_hover = cell
	_recheck_rooms()
	room_dragging = false
	if not current_check.ok or current_check.rooms.is_empty():
		changed.emit()
		return false
	var previous_check: EditCheck = _editor.last_check
	var proposal: Dictionary[Vector2i, int] = current_check.rooms.duplicate()
	_committing = true
	var answer: Variant = _rooms_command.call(proposal)
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
		_recheck_rooms()
	changed.emit()
	return accepted


## The dragged rectangle (or the hovered cell).
func room_rect() -> Rect2i:
	if room_hover == SimGrid.NO_CELL:
		return Rect2i()
	var start: Vector2i = room_drag_start if room_dragging else room_hover
	var low: Vector2i = start.min(room_hover)
	return Rect2i(low, (start.max(room_hover) - low) + Vector2i.ONE)


## The floor cells of the rectangle, row-major (what a paint would cover).
func room_proposal() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if state != State.ROOMS or _grid == null:
		return out
	for cell: Vector2i in _rect_cells(room_rect()):
		if _grid.terrain(cell) == SimGrid.Terrain.FLOOR:
			out.append(cell)
	return out


## One player sentence: what the drag paints, or why it can't.
func rooms_summary() -> String:
	if state != State.ROOMS:
		return ""
	var name: String = RoomRules.label(room_kind)
	if not current_check.ok and not current_check.why.is_empty():
		return current_check.why
	var count: int = current_check.rooms.size()
	if count == 0:
		return "Drag over the floor to paint it as %s" % name
	return "Paint %d tile%s as %s (free)" % [count, "" if count == 1 else "s", name]


func _recheck_rooms() -> void:
	if state != State.ROOMS or _editor == null:
		return
	var cells: Array[Vector2i] = room_proposal()
	# Nothing proposed (off the floor, or hovering a tile that is already this
	# room): an empty refusal keeps the shop's own warnings showing.
	if cells.is_empty():
		current_check = EditCheck.new(false, "")
		return
	current_check = _editor.check_rooms(_editor.room_changes(cells, room_kind))
	if not room_dragging and not current_check.ok and current_check.why == RoomRules.ALREADY:
		current_check = EditCheck.new(false, "")


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	_topology_dirty = true
	_floor_checks.clear()
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
