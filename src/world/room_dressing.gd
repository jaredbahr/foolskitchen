class_name RoomDressing
extends Node3D
## View-only Kenney frontage. Rebuild for a new world/terrain; cutaways only
## change visibility on the existing wall attachments.

const WALL_WINDOW: PackedScene = preload("res://assets/kenney/furniture/wallWindow.glb")
const WALL_LAMP: PackedScene = preload("res://assets/kenney/furniture/lampWall.glb")
const DOORMAT: PackedScene = preload("res://assets/kenney/furniture/rugDoormat.glb")
const PAVEMENT: PackedScene = preload("res://assets/kenney/furniture/floorHalf.glb")
const PAVEMENT_SWATCH: SwatchDef = preload("res://data/swatches/charcoal.tres")
## The warm key light browns a plain charcoal tint, so the pavement mixes in
## palette slate (cancels the warm cast) and cream (lifts it off the dark street).
const PAVEMENT_COOL_SWATCH: SwatchDef = preload("res://data/swatches/slate_blue.tres")
const PAVEMENT_LIGHT_SWATCH: SwatchDef = preload("res://data/swatches/cream.tres")
const PAVEMENT_COOL_MIX: float = 0.55
const PAVEMENT_LIGHT_MIX: float = 0.25
const FACE_GAP: float = 0.005
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var _world: SimWorld
var _lowered_walls: Array[Vector2i] = []
var _wall_details: Array[Node3D] = []


func rebuild(world: SimWorld, lowered_wall_cells: Array[Vector2i] = []) -> void:
	_clear_dressing()
	_world = world
	_lowered_walls.clear()
	if _world == null:
		return
	var windows: int = 0
	var lamps: int = 0
	var attached: Dictionary[Vector2i, bool] = {}
	var entrance_index: int = 0
	for entrance: Dictionary in _entrances(_world.grid):
		var cells: Array[Vector2i] = entrance[&"cells"]
		var normal: Vector2i = entrance[&"normal"]
		for cell: Vector2i in _frontage_cells(_world.grid, cells, normal):
			if attached.has(cell):
				continue
			if _player_window(_world.grid, cell, normal):
				# A player's window (FK-070) takes this slot; later slots keep their place.
				attached[cell] = true
				if windows < 2:
					windows += 1
				elif lamps < 2:
					lamps += 1
				continue
			var detail: PropView = null
			if windows < 2:
				detail = _asset(WALL_WINDOW, "StreetWindow%d" % windows, true)
				windows += 1
			elif lamps < 2:
				detail = _asset(WALL_LAMP, "WallLamp%d" % lamps)
				lamps += 1
			else:
				break
			if detail != null:
				_mount_wall(detail, cell, normal)
				attached[cell] = true
		_add_entry_dressing(cells, normal, entrance_index)
		entrance_index += 1
	set_lowered_walls(lowered_wall_cells)


## Palette-only pavement tint: charcoal, cooled by slate and lifted by cream.
static func pavement_color() -> Color:
	return PAVEMENT_SWATCH.color.lerp(PAVEMENT_COOL_SWATCH.color, PAVEMENT_COOL_MIX) \
		.lerp(PAVEMENT_LIGHT_SWATCH.color, PAVEMENT_LIGHT_MIX)


func set_lowered_walls(cells: Array[Vector2i]) -> void:
	if cells == _lowered_walls:
		return
	_lowered_walls = cells.duplicate()
	for detail: Node3D in _wall_details:
		var cell: Vector2i = detail.get_meta(&"wall_cell")
		detail.visible = not _lowered_walls.has(cell)


## Detached node list for native presentation checks; attachment identity stays
## stable across Up/Cutaway/Down and all camera quarters.
func wall_detail_nodes() -> Array[Node3D]:
	return _wall_details.duplicate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_tints()


func _release_tints() -> void:
	for child: Node in get_children():
		if child is PropView:
			(child as PropView).clear_body_tint()


func _clear_dressing() -> void:
	_release_tints()
	_wall_details.clear()
	for child: Node in get_children():
		remove_child(child)
		child.free()


## Each connected doorway run owns one outward normal. OUTSIDE is terrain,
## including in-bounds street cells, rather than a synonym for grid bounds.
func _entrances(grid: SimGrid) -> Array[Dictionary]:
	var entrances: Array[Dictionary] = []
	var remaining: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in grid.entries():
		remaining[cell] = true
	for entry: Vector2i in grid.entries():
		if not remaining.has(entry):
			continue
		remaining.erase(entry)
		var normal: Vector2i = _outside_normal(grid, entry)
		if normal == Vector2i.ZERO:
			continue
		var tangent: Vector2i = Vector2i(-normal.y, normal.x)
		var cells: Array[Vector2i] = [entry]
		for sign_value: int in [-1, 1]:
			var next: Vector2i = entry + tangent * sign_value
			while remaining.has(next) and _outside_normal(grid, next) == normal:
				cells.append(next)
				remaining.erase(next)
				next += tangent * sign_value
		entrances.append({&"cells": cells, &"normal": normal})
	return entrances


func _outside_normal(grid: SimGrid, entry: Vector2i) -> Vector2i:
	for inside_kind: SimGrid.Terrain in [SimGrid.Terrain.FLOOR, SimGrid.Terrain.ENTRY]:
		for normal: Vector2i in CARDINALS:
			if grid.terrain(entry + normal) == SimGrid.Terrain.OUTSIDE \
					and grid.terrain(entry - normal) == inside_kind:
				return normal
	return Vector2i.ZERO


## The starter's street entries sit one row beyond the doorway. An embedded
## ENTRY may share its wall row. Neither case selects the other exterior walls.
func _frontage_cells(grid: SimGrid, entries: Array[Vector2i], normal: Vector2i) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for depth: int in [0, 1]:
		var plane: int = _axis_value(entries[0] - normal * depth, normal)
		for cell: Vector2i in grid.cells():
			if _axis_value(cell, normal) != plane or grid.terrain(cell) != SimGrid.Terrain.WALL:
				continue
			var outside: SimGrid.Terrain = grid.terrain(cell + normal)
			if grid.terrain(cell - normal) == SimGrid.Terrain.FLOOR \
					and (outside == SimGrid.Terrain.OUTSIDE or outside == SimGrid.Terrain.ENTRY):
				candidates.append(cell)
		if not candidates.is_empty():
			break
	var ordered: Array[Vector2i] = []
	while not candidates.is_empty() and ordered.size() < 4:
		var nearest_index: int = 0
		var nearest_distance: int = _entry_distance(candidates[0], entries)
		for index: int in range(1, candidates.size()):
			var distance: int = _entry_distance(candidates[index], entries)
			if distance < nearest_distance:
				nearest_index = index
				nearest_distance = distance
		ordered.append(candidates[nearest_index])
		candidates.remove_at(nearest_index)
	return ordered


## The player has opened a real window in this shell cell's room-side face.
func _player_window(grid: SimGrid, cell: Vector2i, normal: Vector2i) -> bool:
	return grid.segment(SimGrid.edge_between(cell, cell - normal)) == SimGrid.Segment.WINDOW


func _axis_value(cell: Vector2i, normal: Vector2i) -> int:
	return cell.x * normal.x + cell.y * normal.y


func _entry_distance(cell: Vector2i, entries: Array[Vector2i]) -> int:
	var distance: int = 9223372036854775807
	for entry: Vector2i in entries:
		distance = mini(distance, absi(cell.x - entry.x) + absi(cell.y - entry.y))
	return distance


func _mount_wall(detail: PropView, cell: Vector2i, normal: Vector2i) -> void:
	var bounds: AABB = detail.get_combined_aabb()
	var outward: Vector3 = Vector3(normal.x, 0.0, normal.y)
	var center_y: float = ArtScale.WALL_HEIGHT * (0.5 if detail.get_meta(&"kind") == &"window" else 0.75)
	detail.rotation.y = atan2(-outward.x, -outward.z)
	detail.position = GridMath.cell_to_world(cell) \
		+ outward * (GridMath.CELL_SIZE * 0.5 + bounds.end.z + FACE_GAP)
	detail.position.y = center_y - bounds.get_center().y
	detail.set_meta(&"wall_cell", cell)
	detail.set_meta(&"wall_normal", normal)
	detail.set_meta(&"native_bounds", bounds)
	_wall_details.append(detail)
	add_child(detail)


func _add_entry_dressing(entries: Array[Vector2i], normal: Vector2i, entrance_index: int) -> void:
	var center: Vector3 = Vector3.ZERO
	for entry: Vector2i in entries:
		center += GridMath.cell_to_world(entry)
	center /= float(entries.size())
	var outward: Vector3 = Vector3(normal.x, 0.0, normal.y)
	var tangent: Vector3 = Vector3(-normal.y, 0.0, normal.x)
	var doormat: PropView = _asset(DOORMAT, "EntryDoormat" if entrance_index == 0 else "EntryDoormat%d" % entrance_index)
	if doormat != null:
		doormat.rotation.y = atan2(-outward.x, -outward.z)
		doormat.position = center
		add_child(doormat)
	for index: int in range(entries.size()):
		var tile_name: String = "StreetPavement%d" % index if entrance_index == 0 \
			else "StreetPavement%d_%d" % [entrance_index, index]
		var paving: PropView = _asset(PAVEMENT, tile_name, false, true)
		if paving == null:
			continue
		var bounds: AABB = paving.get_combined_aabb()
		paving.rotation.y = atan2(-outward.x, -outward.z)
		paving.position = center + tangent * ((float(index) - float(entries.size() - 1) * 0.5) * bounds.size.x) \
			+ outward * (GridMath.CELL_SIZE * 0.5 + bounds.size.z * 0.5 + FACE_GAP)
		if not _only_outside(_world.grid, paving.transform * bounds):
			paving.clear_body_tint()
			paving.free()
			continue
		add_child(paving)


func _only_outside(grid: SimGrid, bounds: AABB) -> bool:
	var first: Vector2i = GridMath.world_to_cell(bounds.position)
	var last: Vector2i = GridMath.world_to_cell(bounds.end - Vector3(0.00001, 0.0, 0.00001))
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			if grid.terrain(Vector2i(x, y)) != SimGrid.Terrain.OUTSIDE:
				return false
	return true


func _asset(scene: PackedScene, node_name: String, pane_only: bool = false, grey: bool = false) -> PropView:
	return make_asset(scene, node_name, pane_only, grey)


## PropView adds the shared scale above the untouched imported node transforms
## and measures/centres the actual native mesh hierarchy before placement.
## Shared with WallSegmentView, whose player windows use the same native pane.
static func make_asset(scene: PackedScene, node_name: String, pane_only: bool = false, grey: bool = false) -> PropView:
	var model: Node3D = scene.instantiate() as Node3D
	if model == null:
		return null
	if pane_only:
		var pane: Node3D = model.find_child("window", true, false) as Node3D
		if pane == null:
			model.free()
			return null
		var native_transform: Transform3D = pane.transform
		var ancestor: Node = pane.get_parent()
		while ancestor != null:
			if ancestor is Node3D:
				native_transform = (ancestor as Node3D).transform * native_transform
			if ancestor == model:
				break
			ancestor = ancestor.get_parent()
		pane.get_parent().remove_child(pane)
		model.free()
		model = pane
		model.transform = native_transform
	var view: PropView = PropView.new()
	view.name = node_name
	view.set_meta(&"kind", &"window" if pane_only else (&"pavement" if grey else &"decor"))
	if grey:
		view.body_material_names = PackedStringArray(["wood"])
	var part: Node3D = Node3D.new()
	part.name = "Body"
	var art: Node3D = Node3D.new()
	art.name = "Art"
	art.rotation.y = PI
	model.name = "Model"
	view.add_child(part)
	part.add_child(art)
	art.add_child(model)
	view.prepare()
	if grey:
		view.set_body_tint(pavement_color())
	return view
