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

## D26: WALL_FINISH puts up or recolours wall finishes; HANG, TAKE_DOWN and
## REHANG are wall decor bought, sold and moved.
enum Kind { BUY, MOVE, SELL, WALLS, FLOOR, PAINT, ROOMS, FLOORING, WALL_FINISH, HANG, TAKE_DOWN, REHANG, STAMP, VARIANT }

## One placed item across undo and redo. Re-placing an item gives it a new
## grid id, so entries share this reference instead of holding raw ids.
class ItemRef extends RefCounted:
	var id: int = -1

class Entry extends RefCounted:
	var kind: Kind = Kind.BUY
	## Player words for the undo/redo buttons, e.g. "buy Round table".
	var label: String = ""
	var blueprint: Blueprint
	var items: Array[ItemRef] = []
	var item: ItemRef
	var def_id: StringName = &""
	var origin: Vector2i = Vector2i.ZERO
	var turns: int = 0
	var to_origin: Vector2i = Vector2i.ZERO
	var to_turns: int = 0
	var swatch_id: StringName = &""
	var variant_id: StringName = &""
	var variant_after: StringName = &""
	## Signed cash the original edit moved (negative = spent).
	var cash: int = 0
	## Wall segments before and after (edge -> segment), changed edges only.
	var segments_before: Dictionary[Vector3i, int] = {}
	var segments_after: Dictionary[Vector3i, int] = {}
	var floor_cells: Array[Vector2i] = []
	var floor_adding: bool = true
	## Rooms before and after (cell -> Room), changed cells only (FK-101). A
	## floor removal keeps the room of every cell it took (Dining included) in
	## rooms_before, painted back on undo over the back-wall rule; a floor add
	## keeps the rooms it painted (the back-wall rule) in rooms_after, painted
	## again on redo, so both restore the shop exactly.
	var rooms_before: Dictionary[Vector2i, int] = {}
	var rooms_after: Dictionary[Vector2i, int] = {}
	## Floor looks before and after (D25), changed cells only. A floor removal
	## keeps the looks of the cells it took in finishes_before, laid again on undo.
	var finishes_before: Dictionary[Vector2i, FloorFinishes.Finish] = {}
	var finishes_after: Dictionary[Vector2i, FloorFinishes.Finish] = {}
	## Wall looks before and after (D26), changed faces only.
	var walls_before: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	var walls_after: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	## A wall or floor edit's losses (D26): the looks of faces it took away,
	## and the decor it took down (anchor -> ItemDef id), put back on undo
	## (the edit's exact cash already refunded them; redo takes them again).
	var lost_walls: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	var lost_decor: Dictionary[Vector3i, StringName] = {}
	## Wall decor (D26): where it hung before and after a hang, sale or move.
	var anchor: Vector3i = WallFaces.NO_FACE
	var to_anchor: Vector3i = WallFaces.NO_FACE
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
func buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0, swatch_id: StringName = &"",
		variant_id: StringName = &"") -> bool:
	if not _editor.buy(def_id, origin, quarter_turns, null, variant_id):
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
	entry.variant_id = _grid.item(_editor.last_item_id).variant_id
	entry.cash = _editor.last_cash_change
	entry.label = "buy " + _name(_editor.last_item_id)
	_push(entry)
	return true


## One entry for the entire group. Keep a private copy so renaming/deleting
## the library entry cannot alter redo; shared item refs survive later sales.
func stamp(blueprint: Blueprint, anchor: Vector2i, rotation: int = 0) -> bool:
	if not _editor.stamp(blueprint, anchor, rotation):
		return false
	var entry: Entry = Entry.new()
	entry.kind = Kind.STAMP
	entry.blueprint = blueprint.copy()
	entry.origin = anchor
	entry.turns = rotation
	entry.cash = _editor.last_cash_change
	entry.label = CatalogueText.blueprint_stamp_label(blueprint.display_name)
	for id: int in _editor.last_stamp_ids:
		entry.items.append(_ref(id))
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
	entry.variant_id = placed.variant_id
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
	var losses: Entry = _losses_before()
	if not _editor.apply_segments(changes):
		return false
	var entry: Entry = Entry.new()
	entry.kind = Kind.WALLS
	_note_losses(losses, entry)
	_diff_segments(before, _editor.segments(), entry)
	entry.cash = _editor.last_cash_change
	entry.label = "wall changes"
	_push(entry)
	return true


func apply_floor(cells: Array[Vector2i], adding: bool) -> bool:
	var before: Dictionary[Vector3i, int] = _editor.segments()
	var bought_before: Array[Vector2i] = _editor.bought_floor()
	var rooms_before: Dictionary[Vector2i, int] = _editor.rooms()
	var looks_before: Dictionary[Vector2i, FloorFinishes.Finish] = _editor.floors.snapshot(_editor.floors.cells())
	var losses: Entry = _losses_before()
	var floor_before: Dictionary[Vector2i, bool] = {}
	if _grid != null:
		for cell: Vector2i in _grid.cells():
			if _grid.terrain(cell) == SimGrid.Terrain.FLOOR:
				floor_before[cell] = true
	if not _editor.apply_floor(cells, adding):
		return false
	var painted: Dictionary[Vector2i, int] = _editor.last_check.rooms.duplicate()
	# Only the cells that really changed, so redo and undo touch nothing else.
	var after: Array[Vector2i] = _editor.bought_floor()
	var changed: Array[Vector2i] = []
	for cell: Vector2i in (after if adding else bought_before):
		if (adding and not bought_before.has(cell)) or (not adding and not after.has(cell)):
			changed.append(cell)
	var entry: Entry = Entry.new()
	entry.kind = Kind.FLOOR
	_note_losses(losses, entry)
	entry.floor_cells = changed
	entry.floor_adding = adding
	for cell: Vector2i in floor_before:
		if _grid.terrain(cell) != SimGrid.Terrain.FLOOR:
			entry.rooms_before[cell] = rooms_before.get(cell, SimGrid.Room.DINING)
			if looks_before.has(cell):
				entry.finishes_before[cell] = looks_before[cell]
	entry.rooms_after = painted
	_diff_segments(before, _editor.segments(), entry)
	entry.cash = _editor.last_cash_change
	entry.label = "add floor" if adding else "remove floor"
	_push(entry)
	return true


## Paints rooms (cell -> SimGrid.Room) through ShopEditor (FK-101). Free.
func apply_rooms(changes: Dictionary[Vector2i, int]) -> bool:
	var before: Dictionary[Vector2i, int] = _editor.rooms()
	if not _editor.apply_rooms(changes):
		return false
	var entry: Entry = Entry.new()
	entry.kind = Kind.ROOMS
	for cell: Vector2i in _editor.last_check.rooms:
		entry.rooms_before[cell] = before.get(cell, SimGrid.Room.DINING)
		entry.rooms_after[cell] = _editor.last_check.rooms[cell]
	entry.label = "room painting"
	_push(entry)
	return true


## Lays or recolours floor looks (cell -> FloorFinishes.Finish, D25). Laying
## costs money and is closed-only; a recolour is free at any time and, like
## paint, recorded only while editing is allowed.
func apply_flooring(changes: Dictionary[Vector2i, FloorFinishes.Finish]) -> bool:
	var cells: Array[Vector2i] = []
	cells.assign(changes.keys())
	var before: Dictionary[Vector2i, FloorFinishes.Finish] = _editor.floors.snapshot(cells)
	if not _editor.apply_flooring(changes):
		return false
	var effective: Dictionary[Vector2i, FloorFinishes.Finish] = _editor.last_check.finishes
	if effective.is_empty() or not _editor.can_edit():
		return true
	var entry: Entry = Entry.new()
	entry.kind = Kind.FLOORING
	var laid: StringName = &""
	for cell: Vector2i in effective:
		entry.finishes_before[cell] = before[cell]
		entry.finishes_after[cell] = effective[cell]
		if before[cell].style != effective[cell].style and laid.is_empty():
			laid = effective[cell].style
	entry.cash = _editor.last_cash_change
	entry.label = "recolour the floor" if laid.is_empty() else "lay " + _editor.floor_style_name(laid)
	_push(entry)
	return true


## Puts up or recolours wall looks (face -> Finish, D26), like apply_flooring:
## a new finish costs money and is closed-only; a recolour is free at any
## time and recorded only while editing is allowed.
func apply_wall_finishes(changes: Dictionary[Vector3i, FloorFinishes.Finish]) -> bool:
	var faces: Array[Vector3i] = []
	faces.assign(changes.keys())
	var before: Dictionary[Vector3i, FloorFinishes.Finish] = _editor.walls.snapshot(faces)
	if not _editor.apply_wall_finishes(changes):
		return false
	var effective: Dictionary[Vector3i, FloorFinishes.Finish] = _editor.last_check.wall_finishes
	if effective.is_empty() or not _editor.can_edit():
		return true
	var entry: Entry = Entry.new()
	entry.kind = Kind.WALL_FINISH
	var laid: StringName = &""
	for face: Vector3i in effective:
		entry.walls_before[face] = before[face]
		entry.walls_after[face] = effective[face]
		if before[face].style != effective[face].style and laid.is_empty():
			laid = effective[face].style
	entry.cash = _editor.last_cash_change
	entry.label = "recolour the walls" if laid.is_empty() else "put up " + _editor.wall_style_name(laid)
	_push(entry)
	return true


## Hangs new wall decor (D26).
func hang(def_id: StringName, anchor: Vector3i) -> bool:
	if not _editor.hang(def_id, anchor):
		return false
	var entry: Entry = Entry.new()
	entry.kind = Kind.HANG
	entry.def_id = def_id
	entry.anchor = anchor
	entry.cash = _editor.last_cash_change
	entry.label = "hang " + _decor_name(def_id)
	_push(entry)
	return true


## Sells wall decor; the refund, or -1 when refused.
func take_down(anchor: Vector3i) -> int:
	var definition: ItemDef = _editor.hung_definition(anchor)
	var refund: int = _editor.take_down(anchor)
	if refund < 0 or definition == null:
		return refund
	var entry: Entry = Entry.new()
	entry.kind = Kind.TAKE_DOWN
	entry.def_id = definition.id
	entry.anchor = anchor
	entry.cash = _editor.last_cash_change
	entry.label = "sell " + definition.display_name
	_push(entry)
	return refund


func rehang(anchor: Vector3i, to_anchor: Vector3i) -> bool:
	var definition: ItemDef = _editor.hung_definition(anchor)
	if not _editor.rehang(anchor, to_anchor):
		return false
	if anchor == to_anchor or definition == null:
		return true
	var entry: Entry = Entry.new()
	entry.kind = Kind.REHANG
	entry.def_id = definition.id
	entry.anchor = anchor
	entry.to_anchor = to_anchor
	entry.label = "move " + definition.display_name
	_push(entry)
	return true


func paint_variant(item_id: int, variant_id: StringName) -> bool:
	var placed: PlacedItem = _grid.item(item_id) if _grid != null else null
	if placed == null:
		return false
	var before: StringName = placed.variant_id
	var paint_before: StringName = placed.swatch_id
	if not _editor.paint_variant(item_id, variant_id):
		return false
	if not _editor.can_edit() or (before == placed.variant_id and paint_before.is_empty()):
		return true
	var entry: Entry = Entry.new()
	entry.kind = Kind.VARIANT
	entry.item = _ref(item_id)
	entry.variant_id = before
	entry.variant_after = placed.variant_id
	entry.swatch_id = paint_before
	entry.label = "change look of " + _name(item_id)
	_push(entry)
	return true


## `target` is &"wall", &"floor" or &"item" (with `item_id`). Paint is free.
## Recorded only while editing is allowed (paint also works during service).
func paint(target: StringName, swatch_id: StringName, item_id: int = -1) -> bool:
	var before: StringName = _paint_value(target, item_id)
	# Whole-shop paint folds faces or cells already in the new colour into the
	# default; keep their own looks so undo puts them back exactly.
	var walls_before: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	var floors_before: Dictionary[Vector2i, FloorFinishes.Finish] = {}
	if _editor != null and target == &"wall":
		for face: Vector3i in _editor.walls.faces():
			walls_before[face] = _editor.walls.finish(face)
	elif _editor != null and target == &"floor":
		for cell: Vector2i in _editor.floors.cells():
			floors_before[cell] = _editor.floors.finish(cell)
	if not _paint(target, swatch_id, item_id):
		return false
	if before == swatch_id or _editor == null or not _editor.can_edit():
		return true
	var entry: Entry = Entry.new()
	entry.kind = Kind.PAINT
	entry.paint_target = target
	entry.swatch_id = before
	entry.paint_after = swatch_id
	entry.walls_before = walls_before
	entry.finishes_before = floors_before
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
		Kind.STAMP:
			var ids: Array[int] = []
			for item: ItemRef in entry.items:
				ids.append(item.id)
			if not _check(_editor.remove_stamp(ids, exact)):
				return false
			for id: int in ids:
				_refs.erase(id)
			return true
		Kind.BUY:
			return _remove(entry, exact)
		Kind.SELL:
			return _restore(entry, exact)
		Kind.MOVE:
			return _check(_editor.move(entry.item.id, entry.origin, entry.turns, exact))
		Kind.WALLS:
			if not _check(_editor.apply_segments(entry.segments_before, exact)):
				return false
			_restore_losses(entry)
			return true
		Kind.FLOOR:
			if not _check(_editor.apply_floor(entry.floor_cells, not entry.floor_adding, exact,
					_put_back(entry.segments_before))):
				return false
			# The cells a removal took come back with their exact rooms (free, no
			# check), over whatever the back-wall rule painted on re-adding.
			if not entry.rooms_before.is_empty():
				_editor.apply_rooms(entry.rooms_before, ShopEditor.Exact.new(0, UNDO_NOTE))
			# And with the floor looks they had (free, like the rooms).
			if not entry.finishes_before.is_empty():
				_editor.apply_flooring(entry.finishes_before, ShopEditor.Exact.new(0, UNDO_NOTE))
			_restore_losses(entry)
			return true
		Kind.VARIANT:
			if not _check(_editor.paint_variant(entry.item.id, entry.variant_id)):
				return false
			return _check(_editor.paint_item(entry.item.id, entry.swatch_id))
		Kind.PAINT:
			if not _check(_paint(entry.paint_target, entry.swatch_id, entry.item.id if entry.item != null else -1)):
				return false
			if not entry.walls_before.is_empty():
				_editor.walls.set_finishes(entry.walls_before)
			if not entry.finishes_before.is_empty():
				_editor.floors.set_finishes(entry.finishes_before)
			return true
		Kind.ROOMS:
			return _check(_editor.apply_rooms(entry.rooms_before, exact))
		Kind.FLOORING:
			return _check(_editor.apply_flooring(entry.finishes_before, exact))
		Kind.WALL_FINISH:
			return _check(_editor.apply_wall_finishes(entry.walls_before, exact))
		Kind.HANG:
			return _check(_editor.take_down(entry.anchor, exact) >= 0)
		Kind.TAKE_DOWN:
			return _check(_editor.hang(entry.def_id, entry.anchor, exact))
		Kind.REHANG:
			return _check(_editor.rehang(entry.to_anchor, entry.anchor, exact))
	return false


func _reapply(entry: Entry) -> bool:
	_undoing = false
	_editor.last_check = EditCheck.new(true)
	var exact: ShopEditor.Exact = ShopEditor.Exact.new(entry.cash, REDO_NOTE)
	match entry.kind:
		Kind.STAMP:
			if not _check(_editor.stamp(entry.blueprint, entry.origin, entry.turns, exact)):
				return false
			for index: int in entry.items.size():
				var item: ItemRef = entry.items[index]
				item.id = _editor.last_stamp_ids[index]
				_refs[item.id] = item
			return true
		Kind.BUY:
			return _restore(entry, exact)
		Kind.SELL:
			return _remove(entry, exact)
		Kind.MOVE:
			return _check(_editor.move(entry.item.id, entry.to_origin, entry.to_turns, exact))
		Kind.WALLS:
			return _check(_editor.apply_segments(entry.segments_after, exact))
		Kind.FLOOR:
			# The same cells take down the same segments as the first time, and
			# an add paints the same rooms it painted then.
			if not _check(_editor.apply_floor(entry.floor_cells, entry.floor_adding, exact)):
				return false
			if not entry.rooms_after.is_empty():
				_editor.apply_rooms(entry.rooms_after, ShopEditor.Exact.new(0, REDO_NOTE))
			return true
		Kind.VARIANT:
			return _check(_editor.paint_variant(entry.item.id, entry.variant_after))
		Kind.PAINT:
			return _check(_paint(entry.paint_target, entry.paint_after, entry.item.id if entry.item != null else -1))
		Kind.ROOMS:
			return _check(_editor.apply_rooms(entry.rooms_after, exact))
		Kind.FLOORING:
			return _check(_editor.apply_flooring(entry.finishes_after, exact))
		Kind.WALL_FINISH:
			return _check(_editor.apply_wall_finishes(entry.walls_after, exact))
		Kind.HANG:
			return _check(_editor.hang(entry.def_id, entry.anchor, exact))
		Kind.TAKE_DOWN:
			return _check(_editor.take_down(entry.anchor, exact) >= 0)
		Kind.REHANG:
			return _check(_editor.rehang(entry.anchor, entry.to_anchor, exact))
	return false


## The wall looks and decor before a wall or floor edit (D26), to note what
## it took away.
func _losses_before() -> Entry:
	var snapshot: Entry = Entry.new()
	snapshot.lost_walls = _editor.walls.snapshot(_editor.walls.faces())
	for anchor: Vector3i in _editor.decor.anchors():
		snapshot.lost_decor[anchor] = _editor.decor.item(anchor).def_id
	return snapshot


func _note_losses(before: Entry, entry: Entry) -> void:
	for face: Vector3i in _editor.last_check.lost_finishes:
		if before.lost_walls.has(face):
			entry.lost_walls[face] = before.lost_walls[face]
	for anchor: Vector3i in _editor.last_check.lost_decor:
		if before.lost_decor.has(anchor):
			entry.lost_decor[anchor] = before.lost_decor[anchor]


## Puts back what an undone wall or floor edit took down (free: its exact
## cash already moved the money back).
func _restore_losses(entry: Entry) -> void:
	if not entry.lost_walls.is_empty():
		_editor.apply_wall_finishes(entry.lost_walls, ShopEditor.Exact.new(0, UNDO_NOTE))
	var anchors: Array[Vector3i] = []
	anchors.assign(entry.lost_decor.keys())
	WallFaces.sort(anchors)
	for anchor: Vector3i in anchors:
		_editor.hang(entry.lost_decor[anchor], anchor, ShopEditor.Exact.new(0, UNDO_NOTE))
	_editor.last_check = EditCheck.new(true)


func _decor_name(def_id: StringName) -> String:
	var definition: ItemDef = _editor.hung_definition(_editor.last_anchor)
	return definition.display_name if definition != null and definition.id == def_id else "wall decor"


## Takes an item out of the shop (undo a buy, redo a sell).
func _remove(entry: Entry, exact: ShopEditor.Exact) -> bool:
	var id: int = entry.item.id
	if not _check(_editor.sell(id, exact) >= 0):
		return false
	_refs.erase(id)
	return true


## Puts an item back where it was, with its colour (undo a sell, redo a buy).
func _restore(entry: Entry, exact: ShopEditor.Exact) -> bool:
	if not _check(_editor.buy(entry.def_id, entry.origin, entry.turns, exact, entry.variant_id)):
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
