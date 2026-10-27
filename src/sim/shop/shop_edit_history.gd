class_name ShopEditHistory
extends RefCounted
## Undo and redo for one editing session (FK-085). Every shop edit made in
## the morning or after closing goes through here: each entry is applied by
## ShopEditor and records how to invert itself with the same editor calls, so
## an undo passes the same edit checks as a fresh edit. Money moves back
## exactly (ShopEditor.Exact), one noted ledger line per undo or redo. The
## session clears the history whenever the phase changes (the shop opens).

const UNDO_NOTE: String = "undo"
const REDO_NOTE: String = "redo"
## Older entries are dropped beyond this; a morning rarely comes close.
const MAX_ENTRIES: int = 200

enum Kind { BUY, MOVE, SELL, WALLS, FLOOR, PAINT }

## One placed item across undo and redo. Re-placing an item gives it a new
## grid id, so entries share this reference instead of holding raw ids.
class ItemRef extends RefCounted:
	var id: int = -1

class Entry extends RefCounted:
	var kind: Kind = Kind.BUY
	## Player words for the undo/redo buttons, e.g. "buy Round table".
	var label: String = ""
	var item: ItemRef
	var def_id: StringName = &""
	var origin: Vector2i = Vector2i.ZERO
	var turns: int = 0
	var to_origin: Vector2i = Vector2i.ZERO
	var to_turns: int = 0
	var swatch_id: StringName = &""
	## Signed cash the original edit moved (negative = spent).
	var cash: int = 0
	## Wall segments before and after (edge -> segment), changed edges only.
	var segments_before: Dictionary[Vector3i, int] = {}
	var segments_after: Dictionary[Vector3i, int] = {}
	var floor_cells: Array[Vector2i] = []
	var floor_adding: bool = true
	## &"wall", &"floor" or &"item"; colours before and after.
	var paint_target: StringName = &""
	var paint_after: StringName = &""

## Why the last undo or redo was refused ("" after a success).
var last_refusal: String = ""
var _editor: ShopEditor
var _grid: SimGrid
var _undo: Array[Entry] = []
var _redo: Array[Entry] = []
var _refs: Dictionary[int, ItemRef] = {}
## Which way the running step goes, for the refusal wording.
var _undoing: bool = true


func _init(editor: ShopEditor = null, grid: SimGrid = null) -> void:
	_editor = editor
	_grid = grid


func clear() -> void:
	_undo.clear()
	_redo.clear()
	_refs.clear()
	last_refusal = ""


func can_undo() -> bool:
	return not _undo.is_empty() and _editor != null and _editor.can_edit()


func can_redo() -> bool:
	return not _redo.is_empty() and _editor != null and _editor.can_edit()


func undo_count() -> int:
	return _undo.size()


func redo_count() -> int:
	return _redo.size()


## "buy Round table" etc., or "" when there is nothing to undo.
func undo_label() -> String:
	return _undo.back().label if not _undo.is_empty() else ""


func redo_label() -> String:
	return _redo.back().label if not _redo.is_empty() else ""


# --- Edits (each applies through ShopEditor, then records itself) -------------

## A colour (the eyedropper's copy) is a free repaint that is part of the buy.
func buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0, swatch_id: StringName = &"") -> bool:
	if not _editor.buy(def_id, origin, quarter_turns):
		return false
	if not swatch_id.is_empty():
		_editor.paint_item(_editor.last_item_id, swatch_id)
	var entry: Entry = Entry.new()
	entry.kind = Kind.BUY
	entry.item = _ref(_editor.last_item_id)
	entry.def_id = def_id
	entry.origin = origin
	entry.turns = quarter_turns
	entry.swatch_id = _paint_value(&"item", _editor.last_item_id)
	entry.cash = _editor.last_cash_change
	entry.label = "buy " + _name(_editor.last_item_id)
	_push(entry)
	return true


func move(item_id: int, origin: Vector2i, quarter_turns: int) -> bool:
	var placed: PlacedItem = _grid.item(item_id) if _grid != null else null
	if placed == null:
		return _editor.move(item_id, origin, quarter_turns)
	var from_origin: Vector2i = placed.origin
	var from_turns: int = placed.quarter_turns
	if not _editor.move(item_id, origin, quarter_turns):
		return false
	var entry: Entry = Entry.new()
	entry.kind = Kind.MOVE
	entry.item = _ref(item_id)
	entry.origin = from_origin
	entry.turns = from_turns
	entry.to_origin = origin
	entry.to_turns = quarter_turns
	entry.label = ("rotate " if from_origin == origin else "move ") + _name(item_id)
	_push(entry)
	return true


## Returns the refund, or -1 when refused (like ShopEditor.sell).
func sell(item_id: int) -> int:
	var placed: PlacedItem = _grid.item(item_id) if _grid != null else null
	if placed == null:
		return _editor.sell(item_id)
	var entry: Entry = Entry.new()
	entry.kind = Kind.SELL
	entry.def_id = (placed.def as ItemDef).id
	entry.origin = placed.origin
	entry.turns = placed.quarter_turns
	entry.swatch_id = placed.swatch_id
	entry.label = "sell " + _name(item_id)
	entry.item = _ref(item_id)
	var refund: int = _editor.sell(item_id)
	if refund < 0:
		return refund
	_refs.erase(item_id)
	entry.cash = _editor.last_cash_change
	_push(entry)
	return refund


func apply_segments(changes: Dictionary[Vector3i, int]) -> bool:
	var before: Dictionary[Vector3i, int] = _editor.segments()
	if not _editor.apply_segments(changes):
		return false
	var entry: Entry = Entry.new()
	entry.kind = Kind.WALLS
	_diff_segments(before, _editor.segments(), entry)
	entry.cash = _editor.last_cash_change
	entry.label = "wall changes"
	_push(entry)
	return true


func apply_floor(cells: Array[Vector2i], adding: bool) -> bool:
	var before: Dictionary[Vector3i, int] = _editor.segments()
	var bought_before: Array[Vector2i] = _editor.bought_floor()
	if not _editor.apply_floor(cells, adding):
		return false
	# Only the cells that really changed, so redo and undo touch nothing else.
	var after: Array[Vector2i] = _editor.bought_floor()
	var changed: Array[Vector2i] = []
	for cell: Vector2i in (after if adding else bought_before):
		if (adding and not bought_before.has(cell)) or (not adding and not after.has(cell)):
			changed.append(cell)
	var entry: Entry = Entry.new()
	entry.kind = Kind.FLOOR
	entry.floor_cells = changed
	entry.floor_adding = adding
	_diff_segments(before, _editor.segments(), entry)
	entry.cash = _editor.last_cash_change
	entry.label = "add floor" if adding else "remove floor"
	_push(entry)
	return true


## `target` is &"wall", &"floor" or &"item" (with `item_id`). Paint is free.
## Recorded only while editing is allowed (paint also works during service).
func paint(target: StringName, swatch_id: StringName, item_id: int = -1) -> bool:
	var before: StringName = _paint_value(target, item_id)
	if not _paint(target, swatch_id, item_id):
		return false
	if before == swatch_id or _editor == null or not _editor.can_edit():
		return true
	var entry: Entry = Entry.new()
	entry.kind = Kind.PAINT
	entry.paint_target = target
	entry.swatch_id = before
	entry.paint_after = swatch_id
	if target == &"item":
		entry.item = _ref(item_id)
		entry.label = "paint " + _name(item_id)
	else:
		entry.label = "paint the walls" if target == &"wall" else "paint the floor"
	_push(entry)
	return true


# --- Undo and redo --------------------------------------------------------------

## Undoes the newest entry. A refusal (the edit checks say no now, for example
## someone is standing in the way) leaves the history exactly as it was.
func undo() -> bool:
	if not can_undo():
		last_refusal = "Nothing to undo" if _undo.is_empty() else "Undo is only available in the morning or after closing"
		return false
	var entry: Entry = _undo.back()
	if not _invert(entry):
		return false
	_undo.pop_back()
	_redo.append(entry)
	last_refusal = ""
	return true


func redo() -> bool:
	if not can_redo():
		last_refusal = "Nothing to redo" if _redo.is_empty() else "Redo is only available in the morning or after closing"
		return false
	var entry: Entry = _redo.back()
	if not _reapply(entry):
		return false
	_redo.pop_back()
	_undo.append(entry)
	last_refusal = ""
	return true


func _invert(entry: Entry) -> bool:
	_undoing = true
	_editor.last_check = EditCheck.new(true)
	var exact: ShopEditor.Exact = ShopEditor.Exact.new(-entry.cash, UNDO_NOTE)
	match entry.kind:
		Kind.BUY:
			return _remove(entry, exact)
		Kind.SELL:
			return _restore(entry, exact)
		Kind.MOVE:
			return _check(_editor.move(entry.item.id, entry.origin, entry.turns, exact))
		Kind.WALLS:
			return _check(_editor.apply_segments(entry.segments_before, exact))
		Kind.FLOOR:
			return _check(_editor.apply_floor(entry.floor_cells, not entry.floor_adding, exact,
				_put_back(entry.segments_before)))
		Kind.PAINT:
			return _check(_paint(entry.paint_target, entry.swatch_id, entry.item.id if entry.item != null else -1))
	return false


func _reapply(entry: Entry) -> bool:
	_undoing = false
	_editor.last_check = EditCheck.new(true)
	var exact: ShopEditor.Exact = ShopEditor.Exact.new(entry.cash, REDO_NOTE)
	match entry.kind:
		Kind.BUY:
			return _restore(entry, exact)
		Kind.SELL:
			return _remove(entry, exact)
		Kind.MOVE:
			return _check(_editor.move(entry.item.id, entry.to_origin, entry.to_turns, exact))
		Kind.WALLS:
			return _check(_editor.apply_segments(entry.segments_after, exact))
		Kind.FLOOR:
			# The same cells take down the same segments as the first time.
			return _check(_editor.apply_floor(entry.floor_cells, entry.floor_adding, exact))
		Kind.PAINT:
			return _check(_paint(entry.paint_target, entry.paint_after, entry.item.id if entry.item != null else -1))
	return false


## Takes an item out of the shop (undo a buy, redo a sell).
func _remove(entry: Entry, exact: ShopEditor.Exact) -> bool:
	var id: int = entry.item.id
	if not _check(_editor.sell(id, exact) >= 0):
		return false
	_refs.erase(id)
	return true


## Puts an item back where it was, with its colour (undo a sell, redo a buy).
func _restore(entry: Entry, exact: ShopEditor.Exact) -> bool:
	if not _check(_editor.buy(entry.def_id, entry.origin, entry.turns, exact)):
		return false
	var id: int = _editor.last_item_id
	entry.item.id = id
	_refs[id] = entry.item
	if not entry.swatch_id.is_empty():
		_editor.paint_item(id, entry.swatch_id)
	return true


func _check(accepted: bool) -> bool:
	if not accepted:
		var why: String = _editor.last_check.why if _editor.last_check != null and not _editor.last_check.ok else ""
		last_refusal = why if not why.is_empty() else (
			"That can't be undone right now" if _undoing else "That can't be redone right now")
	return accepted


func _paint(target: StringName, swatch_id: StringName, item_id: int) -> bool:
	match target:
		&"wall":
			return _editor.paint_wall(swatch_id)
		&"floor":
			return _editor.paint_floor(swatch_id)
		&"item":
			return _editor.paint_item(item_id, swatch_id)
	return false


func _paint_value(target: StringName, item_id: int) -> StringName:
	match target:
		&"wall":
			return _editor.wall_swatch_id
		&"floor":
			return _editor.floor_swatch_id
		&"item":
			var placed: PlacedItem = _grid.item(item_id) if _grid != null else null
			return placed.swatch_id if placed != null else &""
	return &""


func _push(entry: Entry) -> void:
	_undo.append(entry)
	if _undo.size() > MAX_ENTRIES:
		_undo.pop_front()
	_redo.clear()
	last_refusal = ""


func _ref(item_id: int) -> ItemRef:
	if not _refs.has(item_id):
		var ref: ItemRef = ItemRef.new()
		ref.id = item_id
		_refs[item_id] = ref
	return _refs[item_id]


func _name(item_id: int) -> String:
	var placed: PlacedItem = _grid.item(item_id) if _grid != null else null
	var definition: ItemDef = placed.def as ItemDef if placed != null else null
	return definition.display_name if definition != null else "item"


static func _diff_segments(before: Dictionary[Vector3i, int], after: Dictionary[Vector3i, int], entry: Entry) -> void:
	for edge: Vector3i in before:
		if after.get(edge, SimGrid.Segment.NONE) != before[edge]:
			entry.segments_before[edge] = before[edge]
			entry.segments_after[edge] = after.get(edge, SimGrid.Segment.NONE)
	for edge: Vector3i in after:
		if not before.has(edge):
			entry.segments_before[edge] = SimGrid.Segment.NONE
			entry.segments_after[edge] = after[edge]


## Segments a floor change took down, to put back when it is undone.
static func _put_back(before: Dictionary[Vector3i, int]) -> Dictionary[Vector3i, int]:
	var out: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in before:
		if before[edge] != SimGrid.Segment.NONE:
			out[edge] = before[edge]
	return out
