class_name WallFinishes
extends RefCounted
## The walls' look per face (D26): a wall finish (WallStyleDef id), a main
## colour and an accent colour (SwatchDef ids), keyed by WallFaces face keys.
## Looks only, owned by ShopEditor like FloorFinishes (and sharing its Finish
## value), so paths, seats and every sim rule ignore it.
##
## Only faces that differ from the shop default are stored. The default is
## the free plain paint in the shop's own wall colour (the legacy whole-shop
## wall paint, empty for the authored cream), so an older shop with no stored
## faces looks exactly as it always did, and a new wall starts as the default.

## `faces` changed look (empty when the default itself changed).
signal changed(faces: Array[Vector3i])

var default_style: StringName = WallStyleDef.DEFAULT_ID
## The shop's own wall colour (ShopEditor.wall_swatch_id); empty = authored cream.
var default_swatch: StringName = &""
## Bumped on every `changed`, so callers can cache derived areas against it.
var revision: int = 0
var _faces: Dictionary[Vector3i, FloorFinishes.Finish] = {}
var _default: FloorFinishes.Finish


func _init(style_id: StringName = WallStyleDef.DEFAULT_ID, swatch_id: StringName = &"") -> void:
	default_style = style_id
	default_swatch = swatch_id
	_default = FloorFinishes.Finish.new(default_style, default_swatch, &"")


## The shared default look (never mutate it).
func default_finish() -> FloorFinishes.Finish:
	return _default


## The face's look: stored, else the default (any key, face or not).
func finish(face: Vector3i) -> FloorFinishes.Finish:
	return _faces[face] if _faces.has(face) else _default


func is_default(face: Vector3i) -> bool:
	return not _faces.has(face)


## Faces with a stored (non-default) look, sorted.
func faces() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	out.assign(_faces.keys())
	WallFaces.sort(out)
	return out


func count() -> int:
	return _faces.size()


## The current look of each given face (defaults included), for undo history.
func snapshot(wanted: Array[Vector3i]) -> Dictionary[Vector3i, FloorFinishes.Finish]:
	var out: Dictionary[Vector3i, FloorFinishes.Finish] = {}
	for face: Vector3i in wanted:
		out[face] = finish(face)
	return out


## Applies looks (face -> Finish); a default look clears the face. One
## `changed` for the faces whose look really changed. Returns those faces.
func set_finishes(changes: Dictionary[Vector3i, FloorFinishes.Finish]) -> Array[Vector3i]:
	var touched: Array[Vector3i] = []
	for face: Vector3i in changes:
		var next: FloorFinishes.Finish = changes[face]
		if next == null or finish(face).same(next):
			continue
		if next.same(_default):
			_faces.erase(face)
		else:
			_faces[face] = FloorFinishes.Finish.new(next.style, next.swatch, next.accent)
		touched.append(face)
	return _emit(touched)


## Forgets the looks of `dropped` faces (walls that were taken away).
func drop(dropped: Array[Vector3i]) -> Array[Vector3i]:
	var touched: Array[Vector3i] = []
	for face: Vector3i in dropped:
		if _faces.erase(face):
			touched.append(face)
	return _emit(touched)


## A new shop colour for every default face (the legacy whole-shop paint).
## Stored faces that now match the default stop being stored.
func set_default_swatch(swatch_id: StringName) -> void:
	if swatch_id == default_swatch:
		return
	default_swatch = swatch_id
	_default = FloorFinishes.Finish.new(default_style, default_swatch, &"")
	for face: Vector3i in _faces.keys():
		if _faces[face].same(_default):
			_faces.erase(face)
	revision += 1
	changed.emit([] as Array[Vector3i])


## Save rows [x, y, dir, style, swatch, accent], sorted (shop snapshot v6).
func to_rows() -> Array[Array]:
	var rows: Array[Array] = []
	for face: Vector3i in faces():
		var look: FloorFinishes.Finish = _faces[face]
		rows.append([face.x, face.y, face.z, String(look.style), String(look.swatch), String(look.accent)])
	return rows


## The connected run of `face`'s look along its walls, inside its room (a
## paint click): it turns inside corners and stops at doorways, other looks
## and room edges. Sorted; empty when `face` is not a wall face.
func area_faces(grid: SimGrid, face: Vector3i) -> Array[Vector3i]:
	if not WallFaces.is_face(grid, face):
		return []
	var look: FloorFinishes.Finish = finish(face)
	var room: int = grid.room(WallFaces.cell(face))
	return WallFaces.flood(grid, face, func(next: Vector3i) -> bool:
		return grid.room(WallFaces.cell(next)) == room and finish(next).same(look))


func _emit(touched: Array[Vector3i]) -> Array[Vector3i]:
	if not touched.is_empty():
		WallFaces.sort(touched)
		revision += 1
		changed.emit(touched)
	return touched
