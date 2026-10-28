class_name WallDecor
extends RefCounted
## Items hung on wall faces (D26): framed art, menu boards, signs, and later
## restroom mirrors and dryers. Each is an ItemDef on the WALL placement layer,
## anchored at its leftmost face (seen from the room) and covering
## `footprint.x` faces to the right along one straight wall. Owned by
## ShopEditor, never by SimGrid: wall items never block a step, a seat or a
## work spot. One item per face. Placement rules are in `problem`.

## Something was hung, moved or taken down.
signal changed()

const OCCUPIED: String = "Something already hangs here"
const NOT_WALL_DECOR: String = "This item does not hang on a wall"


## One hung item. Values only; never mutate a shared one.
class Hung extends RefCounted:
	var def_id: StringName = &""
	var anchor: Vector3i = WallFaces.NO_FACE
	var width: int = 1

	func _init(definition_id: StringName = &"", anchor_face: Vector3i = WallFaces.NO_FACE, faces: int = 1) -> void:
		def_id = definition_id
		anchor = anchor_face
		width = maxi(faces, 1)

	func faces() -> Array[Vector3i]:
		return WallFaces.span(anchor, width)


## Bumped on every change, so callers can cache against it.
var revision: int = 0
var _items: Dictionary[Vector3i, Hung] = {}
## Face -> the anchor of the item covering it.
var _cover: Dictionary[Vector3i, Vector3i] = {}


func item(anchor: Vector3i) -> Hung:
	return _items.get(anchor) as Hung


## The anchor of the item covering `face`, or NO_FACE.
func anchor_at(face: Vector3i) -> Vector3i:
	return _cover.get(face, WallFaces.NO_FACE)


## Every anchor, sorted.
func anchors() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	out.assign(_items.keys())
	WallFaces.sort(out)
	return out


func count() -> int:
	return _items.size()


## Covered faces, sorted.
func covered_faces() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	out.assign(_cover.keys())
	WallFaces.sort(out)
	return out


## Hangs without rules (callers check `problem` first). False on overlap.
func add(def_id: StringName, anchor: Vector3i, width: int) -> bool:
	var hung: Hung = Hung.new(def_id, anchor, width)
	for face: Vector3i in hung.faces():
		if _cover.has(face):
			return false
	_items[anchor] = hung
	for face: Vector3i in hung.faces():
		_cover[face] = anchor
	revision += 1
	changed.emit()
	return true


## Takes an item down; returns it, or null when nothing hangs there.
func remove(anchor: Vector3i) -> Hung:
	var hung: Hung = _items.get(anchor) as Hung
	if hung == null:
		return null
	_items.erase(anchor)
	for face: Vector3i in hung.faces():
		_cover.erase(face)
	revision += 1
	changed.emit()
	return hung


## Why `definition` cannot hang from `anchor` on `grid` ("" when it can):
## every face it covers is a solid wall face along one straight wall, and none
## is covered by another item (`ignore`: the anchor of the item being moved).
func problem(grid: SimGrid, definition: ItemDef, anchor: Vector3i, ignore: Vector3i = WallFaces.NO_FACE) -> String:
	if definition == null or not definition.hangs_on_wall() or not definition.placement_layer_valid():
		return NOT_WALL_DECOR
	var why: String = WallFaces.span_problem(grid, anchor, definition.footprint.x)
	if not why.is_empty():
		return why
	for face: Vector3i in WallFaces.span(anchor, definition.footprint.x):
		var holder: Vector3i = anchor_at(face)
		if holder != WallFaces.NO_FACE and holder != ignore:
			return OCCUPIED
	return ""


## Items whose faces `grid` no longer has (a wall edit took them away), sorted.
func lost_on(grid: SimGrid) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for anchor: Vector3i in anchors():
		var hung: Hung = _items[anchor]
		if not WallFaces.span_problem(grid, anchor, hung.width).is_empty():
			out.append(anchor)
	return out


## Save rows [x, y, dir, def_id], sorted (shop snapshot v6).
func to_rows() -> Array[Array]:
	var rows: Array[Array] = []
	for anchor: Vector3i in anchors():
		rows.append([anchor.x, anchor.y, anchor.z, String(_items[anchor].def_id)])
	return rows
