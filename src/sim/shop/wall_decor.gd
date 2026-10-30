class_name WallDecor
extends RefCounted
## Items hung on wall faces (D26): framed art, menu boards, signs, and later
## restroom mirrors and dryers. Each is an ItemDef on the WALL placement layer,
## anchored at its leftmost face (seen from the room) and covering
## `footprint.x` faces to the right along one straight wall. Owned by
## ShopEditor, never by SimGrid: wall items never block a step, a seat or a
## work spot. One item per face. Placement rules are in `problem`.
## A window item (ItemDef.WallMount.WINDOW, the OPEN sign) hangs in an outside
## window instead, keyed by its window slot (WallFaces.window_problem): one
## per window, and it comes down with the window.

## Something was hung, moved or taken down.
signal changed()

const OCCUPIED: String = "Something already hangs here"
const NOT_WALL_DECOR: String = "This item does not hang on a wall"
const UNIQUE: String = "Your shop already has this sign"


## One hung item. Values only; never mutate a shared one.
class Hung extends RefCounted:
	var def_id: StringName = &""
	var anchor: Vector3i = WallFaces.NO_FACE
	var width: int = 1
	## Hangs in the window slot `anchor`, not on a wall face.
	var window: bool = false
	var mount: ItemDef.WallMount = ItemDef.WallMount.INSIDE_FACE
	var swatch_id: StringName = &""

	func _init(definition_id: StringName = &"", anchor_face: Vector3i = WallFaces.NO_FACE, faces: int = 1,
			in_window: bool = false, actual_mount: int = -1, swatch: StringName = &"") -> void:
		def_id = definition_id
		anchor = anchor_face
		width = 1 if in_window else maxi(faces, 1)
		mount = (ItemDef.WallMount.WINDOW if in_window else ItemDef.WallMount.INSIDE_FACE) \
			if actual_mount < 0 else actual_mount as ItemDef.WallMount
		window = mount == ItemDef.WallMount.WINDOW
		swatch_id = swatch

	func copy() -> Hung:
		return Hung.new(def_id, anchor, width, window, mount, swatch_id)

	## Where it still hangs on `grid` ("" when it does).
	func problem_on(grid: SimGrid) -> String:
		if mount == ItemDef.WallMount.EXTERIOR:
			return ExteriorSupport.span_problem(grid, anchor, width)
		if WallFaces.is_exterior(grid, anchor):
			return WallFaces.NOT_INSIDE
		return WallFaces.window_problem(grid, anchor) if window else WallFaces.span_problem(grid, anchor, width)

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
## `window`: in the window slot `anchor` (one wide).
func add(def_id: StringName, anchor: Vector3i, width: int, window: bool = false,
		mount: int = -1, swatch_id: StringName = &"") -> bool:
	var hung: Hung = Hung.new(def_id, anchor, width, window, mount, swatch_id)
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
## every face it covers is a solid wall face along one straight wall (a
## window item: `anchor` is an outside window), and none is covered by another
## item (`ignore`: the anchor of the item being moved).
func problem(grid: SimGrid, definition: ItemDef, anchor: Vector3i, ignore: Vector3i = WallFaces.NO_FACE) -> String:
	if definition == null or not definition.hangs_on_wall() or not definition.placement_layer_valid():
		return NOT_WALL_DECOR
	var outside: bool = WallFaces.is_exterior(grid, anchor)
	var width: int = definition.footprint.x
	var why: String = ""
	if outside:
		if definition.wall_mount != ItemDef.WallMount.EXTERIOR and not definition.allow_exterior:
			return WallFaces.NOT_INSIDE if not definition.hangs_in_window() else WallFaces.WINDOW_ONLY
		if ExteriorSupport.band(anchor) != definition.exterior_band:
			return ExteriorSupport.STREET_ONLY
		why = ExteriorSupport.span_problem(grid, anchor, width)
	elif definition.wall_mount == ItemDef.WallMount.EXTERIOR:
		return ExteriorSupport.STREET_ONLY
	elif definition.hangs_in_window():
		why = WallFaces.window_problem(grid, anchor)
	else:
		why = WallFaces.span_problem(grid, anchor, width)
	if definition.unique_per_shop:
		for placed: Vector3i in anchors():
			if placed != ignore and _items[placed].def_id == definition.id:
				return UNIQUE
	if not why.is_empty():
		return why
	for face: Vector3i in WallFaces.span(anchor, width):
		var holder: Vector3i = anchor_at(face)
		if holder != WallFaces.NO_FACE and holder != ignore:
			return OCCUPIED
	return ""


## Items whose faces `grid` no longer has (a wall edit took them away), sorted.
func lost_on(grid: SimGrid) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for anchor: Vector3i in anchors():
		var hung: Hung = _items[anchor]
		if not hung.problem_on(grid).is_empty():
			out.append(anchor)
	return out


## Save rows [x, y, dir, def_id], sorted (shop snapshot v6).
func to_rows() -> Array[Array]:
	var rows: Array[Array] = []
	for anchor: Vector3i in anchors():
		var hung: Hung = _items[anchor]
		var row: Array = [anchor.x, anchor.y, anchor.z, String(hung.def_id)]
		if hung.mount == ItemDef.WallMount.EXTERIOR:
			row.append(hung.mount)
			row.append(String(hung.swatch_id))
		rows.append(row)
	return rows


## A suggestion only: restroom decor is legal on any suitable inside wall.
static func room_hint(grid: SimGrid, definition: ItemDef, anchor: Vector3i) -> String:
	if grid == null or definition == null or definition.category != ItemDef.Category.RESTROOM:
		return ""
	for face: Vector3i in WallFaces.span(anchor, definition.footprint.x):
		if grid.room(WallFaces.cell(face)) != SimGrid.Room.RESTROOM:
			return "Tip: mark this room as Restroom in Build → Rooms"
	return ""


## Actual placement, rather than the definition's possible mount modes.
static func mount_for(grid: SimGrid, definition: ItemDef, anchor: Vector3i) -> ItemDef.WallMount:
	if WallFaces.is_exterior(grid, anchor):
		return ItemDef.WallMount.EXTERIOR
	return ItemDef.WallMount.WINDOW if definition.hangs_in_window() else ItemDef.WallMount.INSIDE_FACE


func set_swatch(anchor: Vector3i, swatch_id: StringName) -> bool:
	var hung: Hung = item(anchor)
	if hung == null:
		return false
	if hung.swatch_id == swatch_id:
		return true
	var changed_item: Hung = hung.copy()
	changed_item.swatch_id = swatch_id
	_items[anchor] = changed_item
	revision += 1
	changed.emit()
	return true
