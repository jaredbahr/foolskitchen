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
const SIGN_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const SIGN_FONT_SIZE: int = 48
## The name board: palette cream with a walnut frame (the frame is the darker
## outline tone) and the UI ink for letters, the same pairing as the HUD panel.
const SIGN_BOARD_SWATCH: SwatchDef = preload("res://data/swatches/cream.tres")
const SIGN_FRAME_SWATCH: SwatchDef = preload("res://data/swatches/walnut.tres")
## Fascia under the shop window, on the wall run beside the doorway. Its top
## stays below ShopView.LOWERED_HEIGHT, so the stub still carries it in Cutaway
## and Walls Down and it never hangs in the air.
const SIGN_MAX_CELLS: int = 4
const SIGN_SIDE_MARGIN: float = 0.05
const SIGN_BOTTOM: float = 0.025
const SIGN_FRAME_HEIGHT: float = 0.31
const SIGN_FRAME_WIDTH: float = 0.03
const SIGN_FRAME_DEPTH: float = 0.05
const SIGN_BOARD_DEPTH: float = 0.035
const SIGN_TEXT_PADDING: float = 0.05
## Letters: about 0.15 m caps at full size (legible at the default zoom), and
## never below MIN; a name too wide even at MIN is cut with an ellipsis.
const SIGN_CAP_HEIGHT: float = 0.15
const SIGN_MIN_CAP_HEIGHT: float = 0.11
## Cap height / em of the UI font (Open Sans: 1462 / 2048 units).
const SIGN_CAP_RATIO: float = 0.714
## Label3D centres the whole line box, which leaves the capitals high on the
## board under the top rail; drop them this share of an em (measured in captures).
const SIGN_TEXT_DROP: float = 0.21
const ELLIPSIS: String = "\u2026"

var _world: SimWorld
var _lowered_walls: Array[Vector2i] = []
var _wall_details: Array[Node3D] = []
var _name_signs: Array[Label3D] = []
var _restaurant_name: String = MenuSettings.DEFAULT_NAME


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


func set_restaurant_name(value: String) -> bool:
	var normalized: String = MenuSettings.normalized_restaurant_name(value)
	if normalized.is_empty():
		return false
	if normalized == _restaurant_name:
		return true
	_restaurant_name = normalized
	for sign: Label3D in _name_signs:
		_fit_name(sign)
	return true


func name_sign_nodes() -> Array[Label3D]:
	return _name_signs.duplicate()


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
	_name_signs.clear()
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
	_add_name_sign(entries, normal, entrance_index)
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


## A framed name board mounted low on the solid wall run beside the doorway,
## using the game's UI font. View-only: no item, collision, theme score or
## saved geometry. Returns without a sign when no wall cell flanks the door.
func _add_name_sign(entries: Array[Vector2i], normal: Vector2i, index: int) -> void:
	var cells: Array[Vector2i] = _sign_cells(_world.grid, entries, normal)
	if cells.is_empty():
		return
	var outward: Vector3 = Vector3(normal.x, 0.0, normal.y)
	var center: Vector3 = Vector3.ZERO
	for cell: Vector2i in cells:
		center += GridMath.cell_to_world(cell)
	center /= float(cells.size())
	var frame_width: float = float(cells.size()) * GridMath.CELL_SIZE - SIGN_SIDE_MARGIN * 2.0
	var board_size: Vector2 = Vector2(frame_width - SIGN_FRAME_WIDTH * 2.0, SIGN_FRAME_HEIGHT - SIGN_FRAME_WIDTH * 2.0)
	var root: Node3D = Node3D.new()
	root.name = "RestaurantNameSign%d" % index
	# Local +Z is the street side; the root sits on the wall's outer face.
	root.rotation.y = atan2(outward.x, outward.z)
	root.position = center + outward * (GridMath.CELL_SIZE * 0.5 + FACE_GAP)
	root.position.y = SIGN_BOTTOM + SIGN_FRAME_HEIGHT * 0.5
	root.set_meta(&"wall_cells", cells)
	root.set_meta(&"wall_normal", normal)
	root.set_meta(&"board_size", board_size)
	root.set_meta(&"frame_size", Vector2(frame_width, SIGN_FRAME_HEIGHT))
	root.add_child(_sign_frame(Vector2(frame_width, SIGN_FRAME_HEIGHT)))
	root.add_child(_sign_box("Board", Vector3(board_size.x, board_size.y, SIGN_BOARD_DEPTH),
		_sign_material(SIGN_BOARD_SWATCH.color), Vector2.ZERO))
	var text: Label3D = Label3D.new()
	text.name = "Text"
	text.font = SIGN_THEME.default_font if SIGN_THEME.default_font != null else ThemeDB.fallback_font
	text.font_size = SIGN_FONT_SIZE
	text.modulate = SIGN_THEME.get_color("font_color", "Label")
	text.outline_size = 0
	text.double_sided = false
	text.no_depth_test = false
	text.position = Vector3(0.0, 0.0, SIGN_BOARD_DEPTH + FACE_GAP)
	text.offset = Vector2(0.0, -SIGN_TEXT_DROP * float(SIGN_FONT_SIZE))
	text.set_meta(&"name_width", board_size.x - SIGN_TEXT_PADDING * 2.0)
	root.add_child(text)
	_fit_name(text)
	add_child(root)
	_name_signs.append(text)


## Up to SIGN_MAX_CELLS solid frontage walls in a row, starting right beside
## the doorway on the longer side (the street's left on a tie). Never a gap cell.
func _sign_cells(grid: SimGrid, entries: Array[Vector2i], normal: Vector2i) -> Array[Vector2i]:
	var frontage: Array[Vector2i] = _frontage_cells(grid, entries, normal)
	var best: Array[Vector2i] = []
	if frontage.is_empty():
		return best
	var plane: int = _axis_value(frontage[0], normal)
	var tangent: Vector2i = Vector2i(-normal.y, normal.x)
	var low: int = 9223372036854775807
	var high: int = -9223372036854775807
	var doorway: Vector2i = Vector2i.ZERO
	for entry: Vector2i in entries:
		var along: int = _axis_value(entry, tangent)
		low = mini(low, along)
		high = maxi(high, along)
		doorway = entry + normal * (plane - _axis_value(entry, normal))
	for side: int in [1, -1]:
		var edge: int = high if side == 1 else low
		var cell: Vector2i = doorway + tangent * (edge - _axis_value(doorway, tangent) + side)
		var run: Array[Vector2i] = []
		while run.size() < SIGN_MAX_CELLS and _is_frontage_wall(grid, cell, normal):
			run.append(cell)
			cell += tangent * side
		if run.size() > best.size():
			best = run
	return best


func _is_frontage_wall(grid: SimGrid, cell: Vector2i, normal: Vector2i) -> bool:
	var outside: SimGrid.Terrain = grid.terrain(cell + normal)
	return grid.terrain(cell) == SimGrid.Terrain.WALL and grid.terrain(cell - normal) == SimGrid.Terrain.FLOOR \
		and (outside == SimGrid.Terrain.OUTSIDE or outside == SimGrid.Terrain.ENTRY)


## Four walnut rails standing proud of the cream board, like a picture frame.
func _sign_frame(size: Vector2) -> Node3D:
	var frame: Node3D = Node3D.new()
	frame.name = "Frame"
	var material: StandardMaterial3D = _sign_material(SIGN_FRAME_SWATCH.color)
	var rail: float = SIGN_FRAME_WIDTH
	var inner: float = size.y - rail * 2.0
	frame.add_child(_sign_box("Top", Vector3(size.x, rail, SIGN_FRAME_DEPTH), material, Vector2(0.0, (size.y - rail) * 0.5)))
	frame.add_child(_sign_box("Bottom", Vector3(size.x, rail, SIGN_FRAME_DEPTH), material, Vector2(0.0, (rail - size.y) * 0.5)))
	frame.add_child(_sign_box("Left", Vector3(rail, inner, SIGN_FRAME_DEPTH), material, Vector2((rail - size.x) * 0.5, 0.0)))
	frame.add_child(_sign_box("Right", Vector3(rail, inner, SIGN_FRAME_DEPTH), material, Vector2((size.x - rail) * 0.5, 0.0)))
	return frame


static func _sign_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


## A flat-shaded palette box whose back face lies on the root's wall plane.
static func _sign_box(node_name: String, size: Vector3, material: StandardMaterial3D, offset: Vector2) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	box.material = material
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = box
	mesh.position = Vector3(offset.x, offset.y, size.z * 0.5)
	return mesh


## Full-size letters when the name fits the board, smaller down to the minimum
## cap height, then cut with an ellipsis so the text never leaves the board.
func _fit_name(sign: Label3D) -> void:
	var available: float = sign.get_meta(&"name_width")
	var full: float = SIGN_CAP_HEIGHT / SIGN_CAP_RATIO / float(sign.font_size)
	var smallest: float = SIGN_MIN_CAP_HEIGHT / SIGN_CAP_RATIO / float(sign.font_size)
	var text: String = _restaurant_name
	var width: float = _text_width(sign, text)
	sign.pixel_size = clampf(available / maxf(1.0, width), smallest, full)
	if width * sign.pixel_size > available + 0.0001:
		while text.length() > 1 and _text_width(sign, text.strip_edges(false, true) + ELLIPSIS) * sign.pixel_size > available:
			text = text.left(text.length() - 1)
		text = text.strip_edges(false, true) + ELLIPSIS
	sign.text = text
	sign.set_meta(&"full_name", _restaurant_name)


static func _text_width(sign: Label3D, text: String) -> float:
	return sign.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sign.font_size).x


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
