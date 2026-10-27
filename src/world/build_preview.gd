class_name BuildPreview
extends Node3D
## Read-only geometry from BuildMode's checked snapshot. No placement or path checks.

signal reason_changed(reason: String)

const VALID_COLOR: Color = Color("6caa7b")
const INVALID_COLOR: Color = Color("ce6958")
const VALID_ALPHA: float = 0.92
const INVALID_ALPHA: float = 0.68
const WORK_COLOR: Color = Color("579fa8")
const SEAT_COLOR: Color = Color("ddbd70")
const WALL_GHOST_ALPHA: float = 0.55
## A little thicker than the built slab so the ghost reads over an existing one.
const WALL_GHOST_DEPTH: float = 0.12
## Floor tool (FK-080): proposed tiles, and the pale unbuilt lot (palette cream).
const LOT_SWATCH: SwatchDef = preload("res://data/swatches/cream.tres")
const LOT_FILL_ALPHA: float = 0.22
const LOT_EDGE_ALPHA: float = 0.75
const LOT_EDGE_WIDTH: float = 0.05
const FLOOR_GHOST_ALPHA: float = 0.6
const FLOOR_GHOST_INSET: float = 0.03

var ghost_mesh: ItemVisual
var work_markers: Array[MeshInstance3D] = []
var seat_markers: Array[MeshInstance3D] = []
var warning_nodes: Dictionary[int, Node3D] = {}
## Walls tool ghosts (FK-070), one per proposed edge change.
var wall_ghosts: Array[MeshInstance3D] = []
## Floor tool ghost (one merged mesh) and the cells it covers.
var floor_ghost: MeshInstance3D
var floor_ghost_cells: Array[Vector2i] = []
## FK-085: the tiles under the item the hand, eyedropper or sell tool points at.
var hover_mesh: MeshInstance3D
## The lot outline and fill, shown in every Build mode state.
var lot_outline: Node3D
var _lot_root: Node3D
var _controller: BuildMode
var _shop_view: ShopView
var _grid: SimGrid
var _ghost_root: Node3D
var _hidden_original: ItemVisual
var _original_visible: bool = true
var _reason: String = ""


## Explicit binding also works before _ready in the custom test runner.
func bind_build_mode(controller: BuildMode, shop_view: ShopView) -> void:
	_disconnect_controller()
	_clear_geometry()
	_controller = controller
	_shop_view = shop_view
	_grid = shop_view.world.grid if is_instance_valid(shop_view) and shop_view.world != null else null
	_connect_controller()
	refresh()


func invalid_reason() -> String:
	return _reason


func displayed_warning_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(warning_nodes.keys())
	ids.sort()
	return ids


## Native-node evidence only, independent of the controller's expected state.
## visible is the local flag; visible_in_tree additionally requires tree entry.
## Global transforms are absent before tree entry. All values are JSON-safe copies.
func visual_state() -> Dictionary:
	var result: Dictionary = {"inside_tree": is_inside_tree(), "ghost": {},
		"work_markers": _native_markers(work_markers), "seat_markers": _native_markers(seat_markers),
		"warning_ids": [] as Array[int], "warnings": [] as Array[Dictionary]}
	if is_instance_valid(ghost_mesh):
		var ghost: Dictionary = _native_item_state(ghost_mesh)
		var valid: Variant = ghost_mesh.get_meta("valid", null)
		ghost["valid"] = valid if valid is bool else null
		result["ghost"] = ghost
	var ids: Array[int] = []
	ids.assign(warning_nodes.keys())
	ids.sort()
	for id: int in ids:
		var reference: Variant = warning_nodes[id]
		if not is_instance_valid(reference):
			continue
		var root: Node3D = reference as Node3D
		var warning: Dictionary = _native_node_state(root)
		var metadata_id: Variant = root.get_meta("item_id", null)
		warning["item_id"] = id
		warning["metadata_item_id"] = metadata_id if metadata_id is int else null
		var rails: Array[Dictionary] = []
		for child: Node in root.get_children():
			if child is MeshInstance3D:
				rails.append(_native_mesh_state(child as MeshInstance3D))
		warning["rails"] = rails
		warning["child_count"] = root.get_child_count()
		result["warning_ids"].append(id)
		result["warnings"].append(warning)
	return result


static func _native_node_state(node: Node3D) -> Dictionary:
	var inside: bool = node.is_inside_tree()
	var result: Dictionary = {"name": String(node.name), "inside_tree": inside,
		"visible": node.visible, "visible_in_tree": inside and node.is_visible_in_tree(),
		"position": _vector_values(node.position), "rotation": _vector_values(node.rotation),
		"scale": _vector_values(node.scale), "global_transform": [] as Array[float]}
	if inside:
		var actual: Transform3D = node.global_transform
		result["global_transform"] = [actual.basis.x.x, actual.basis.x.y, actual.basis.x.z,
			actual.basis.y.x, actual.basis.y.y, actual.basis.y.z,
			actual.basis.z.x, actual.basis.z.y, actual.basis.z.z,
			actual.origin.x, actual.origin.y, actual.origin.z]
	return result


static func _native_mesh_state(node: MeshInstance3D) -> Dictionary:
	var result: Dictionary = _native_node_state(node)
	result["mesh_class"] = node.mesh.get_class() if node.mesh != null else ""
	result["mesh_size"] = _vector_values(node.mesh.get_aabb().size) if node.mesh != null else []
	result["material_color"] = [] as Array[float]
	result["transparency"] = -1
	var material: Material = node.material_override
	if node.mesh != null and node.mesh.get_surface_count() > 0:
		material = node.get_active_material(0)
	if material is BaseMaterial3D:
		var native: BaseMaterial3D = material as BaseMaterial3D
		var color: Color = native.albedo_color
		result["material_color"] = [color.r, color.g, color.b, color.a]
		result["transparency"] = int(native.transparency)
	return result


static func _native_item_state(node: ItemVisual) -> Dictionary:
	var result: Dictionary = _native_node_state(node)
	var meshes: Array[MeshInstance3D] = node.rendered_meshes()
	result["mesh_class"] = meshes[0].mesh.get_class() if not meshes.is_empty() else ""
	result["mesh_size"] = _vector_values(node.get_aabb().size)
	result["bounds_position"] = _vector_values(node.get_aabb().position)
	result["material_color"] = [] as Array[float]
	result["transparency"] = -1
	result["model_scene"] = node.prop.scene_file_path if node.prop != null else ""
	result["meshes"] = [] as Array[Dictionary]
	for mesh_node: MeshInstance3D in meshes:
		result["meshes"].append(_native_mesh_state(mesh_node))
	var body: BaseMaterial3D = node.primary_body_material()
	result["body_material_name"] = body.resource_name if body != null else ""
	if body != null:
		var color: Color = body.albedo_color
		result["material_color"] = [color.r, color.g, color.b, color.a]
		result["transparency"] = int(body.transparency)
	return result


static func _native_markers(markers: Array[MeshInstance3D]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reference: Variant in markers:
		if not is_instance_valid(reference):
			continue
		var marker: MeshInstance3D = reference as MeshInstance3D
		var actual: Dictionary = _native_mesh_state(marker)
		var cell: Variant = marker.get_meta("cell", null)
		actual["cell"] = [cell.x, cell.y] if cell is Vector2i else []
		result.append(actual)
	return result


static func _vector_values(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


## Called on meaningful controller changes, never from a frame polling loop.
func refresh() -> void:
	_clear_geometry()
	var reason: String = ""
	if _controller == null or not is_instance_valid(_shop_view):
		_set_reason(reason)
		return
	var snapshot: Dictionary = _controller.presentation_state()
	reason = snapshot.get("feedback", "")
	if is_inside_tree() and _shop_view.is_inside_tree():
		global_transform = _shop_view.global_transform
	else:
		transform = _shop_view.transform
	var definition: ItemDef = snapshot.get("definition") as ItemDef
	var origin: Vector2i = snapshot.get("origin", Vector2i.ZERO)
	var turns: int = snapshot.get("quarter_turns", 0)
	var has_ghost: bool = snapshot.get("active", false) and snapshot.get("has_ghost", false) and definition != null
	var valid: bool = snapshot.get("check_ok", false)
	var selected_id: int = snapshot.get("item_id", -1)
	if has_ghost:
		_build_ghost(definition, origin, turns, valid)
		if selected_id > 0 and _shop_view.item_nodes.has(selected_id):
			_hidden_original = _shop_view.item_nodes[selected_id]
			if is_instance_valid(_hidden_original):
				_original_visible = _hidden_original.visible
				_hidden_original.visible = false
				_shop_view.refresh_item_selection()
		if not valid:
			reason = snapshot.get("why", "")
	elif snapshot.get("active", false) and snapshot.get("state", -1) == BuildMode.State.WALLS:
		var changes: Dictionary = snapshot.get("wall_changes", {})
		_build_wall_ghosts(changes, valid)
		if not valid:
			reason = snapshot.get("why", "")
	elif snapshot.get("active", false) and snapshot.get("state", -1) == BuildMode.State.FLOOR:
		var floor_cells: Array[Vector2i] = []
		floor_cells.assign(snapshot.get("floor_cells", []))
		_build_floor_ghost(floor_cells, valid, snapshot.get("floor_removing", false))
		if not valid:
			reason = snapshot.get("why", "")
	elif snapshot.get("active", false) and snapshot.get("state", -1) == BuildMode.State.IDLE:
		_build_hover(snapshot.get("hover_item_id", -1), snapshot.get("tool", BuildMode.Tool.HAND), valid)
		if not valid:
			reason = snapshot.get("why", "")
	if snapshot.get("active", false):
		var open_cells: Array[Vector2i] = []
		open_cells.assign(snapshot.get("lot_open", []))
		_build_lot(snapshot.get("lot", Rect2i()), open_cells)
	var warning_ids: Array[int] = []
	warning_ids.assign(snapshot.get("warning_ids", []))
	for id: int in warning_ids:
		# A valid check describes the proposed layout: a moved item's real ID
		# follows its ghost. An invalid proposal retains actual-layout warnings.
		if has_ghost and valid and (id == 0 or id == selected_id):
			_build_warning(id, definition, origin, turns)
		elif _shop_view.world != null:
			var item: PlacedItem = _shop_view.world.grid.item(id)
			if item != null and item.def is ItemDef:
				_build_warning(id, item.def as ItemDef, item.origin, item.quarter_turns)
	_set_reason(reason)


func clear() -> void:
	_disconnect_controller()
	_clear_geometry()
	_controller = null
	_shop_view = null
	_grid = null
	_set_reason("")


func _enter_tree() -> void:
	_connect_controller()
	refresh()


func _exit_tree() -> void:
	_disconnect_controller()
	_clear_geometry()
	_set_reason("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_UNPARENTED:
		_disconnect_controller()
		_clear_geometry()
		if what == NOTIFICATION_UNPARENTED:
			_set_reason("")


func _connect_controller() -> void:
	if _controller != null and not _controller.changed.is_connected(refresh):
		_controller.changed.connect(refresh)
	# Bound after ShopView: its replacement mesh must be hidden as well as the
	# old mesh seen by an earlier controller notification during the same edit.
	if _grid != null and not _grid.cells_changed.is_connected(_on_cells_changed):
		_grid.cells_changed.connect(_on_cells_changed)


func _disconnect_controller() -> void:
	if _controller != null and _controller.changed.is_connected(refresh):
		_controller.changed.disconnect(refresh)
	if _grid != null and _grid.cells_changed.is_connected(_on_cells_changed):
		_grid.cells_changed.disconnect(_on_cells_changed)


func _on_cells_changed(_cells: Array[Vector2i]) -> void:
	refresh()


func _clear_geometry() -> void:
	if is_instance_valid(_hidden_original):
		_hidden_original.visible = _original_visible
	_hidden_original = null
	if is_instance_valid(_shop_view):
		_shop_view.refresh_item_selection()
	if is_instance_valid(_ghost_root):
		_free_node(_ghost_root)
	_ghost_root = null
	ghost_mesh = null
	wall_ghosts.clear()
	floor_ghost = null
	floor_ghost_cells.clear()
	hover_mesh = null
	if is_instance_valid(_lot_root):
		_free_node(_lot_root)
	_lot_root = null
	lot_outline = null
	work_markers.clear()
	seat_markers.clear()
	for node: Node3D in warning_nodes.values():
		if is_instance_valid(node):
			_free_node(node)
	warning_nodes.clear()


func _build_ghost(definition: ItemDef, origin: Vector2i, turns: int, valid: bool) -> void:
	_ghost_root = Node3D.new()
	_ghost_root.name = "Ghost"
	add_child(_ghost_root)
	var height: float = ShopView.HEIGHTS.get(definition.category, 0.6)
	var tint: Color = definition.placeholder_color.lerp(VALID_COLOR if valid else INVALID_COLOR, 0.8)
	tint.a = VALID_ALPHA if valid else INVALID_ALPHA
	ghost_mesh = ItemVisual.create(definition, height, _material(definition.placeholder_color))
	ghost_mesh.set_ghost_tint(tint)
	ghost_mesh.name = "Furniture"
	ghost_mesh.transform = ItemVisual.placed_transform(definition, origin, turns)
	ghost_mesh.rotation.y = -turns * PI * 0.5
	ghost_mesh.set_meta("valid", valid)
	_ghost_root.add_child(ghost_mesh)
	for offset: Vector2i in definition.work_cells:
		var cell: Vector2i = origin + GridMath.rotate_cell(offset, definition.footprint, turns)
		var marker: MeshInstance3D = _box(Vector3(0.30, 0.045, 0.30), _material(WORK_COLOR))
		marker.position = GridMath.cell_to_world(cell) + Vector3(0.0, 0.04, 0.0)
		marker.set_meta("cell", cell)
		marker.name = "Work%d" % work_markers.size()
		work_markers.append(marker)
		_ghost_root.add_child(marker)
	for offset: Vector2i in definition.seat_cells:
		var cell: Vector2i = origin + GridMath.rotate_cell(offset, definition.footprint, turns)
		var marker: MeshInstance3D = MeshInstance3D.new()
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = 0.16
		disc.bottom_radius = 0.16
		disc.height = 0.045
		disc.radial_segments = 12
		marker.mesh = disc
		marker.material_override = _material(SEAT_COLOR)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position = GridMath.cell_to_world(cell) + Vector3(0.0, 0.04, 0.0)
		marker.set_meta("cell", cell)
		marker.name = "Seat%d" % seat_markers.size()
		seat_markers.append(marker)
		_ghost_root.add_child(marker)


## Translucent slabs on each proposed edge: full height for a new or changed
## segment, low for a removal; green when the change is allowed, red if not.
func _build_wall_ghosts(changes: Dictionary, valid: bool) -> void:
	if changes.is_empty():
		return
	_ghost_root = Node3D.new()
	_ghost_root.name = "WallGhost"
	add_child(_ghost_root)
	var tint: Color = VALID_COLOR if valid else INVALID_COLOR
	tint.a = WALL_GHOST_ALPHA
	var material: StandardMaterial3D = _material(tint, true)
	for key: Variant in changes:
		var edge: Vector3i = key
		var removing: bool = int(changes[key]) == SimGrid.Segment.NONE
		var height: float = ShopView.LOWERED_HEIGHT if removing else ArtScale.WALL_HEIGHT
		var ends: Array[Vector2i] = SimGrid.edge_vertices(edge)
		var mid: Vector2 = (Vector2(ends[0]) + Vector2(ends[1])) * 0.5 * GridMath.CELL_SIZE
		var length: float = GridMath.CELL_SIZE
		var depth: float = WALL_GHOST_DEPTH
		var size: Vector3 = Vector3(depth, height, length) if edge.z == SimGrid.EDGE_WEST else Vector3(length, height, depth)
		var ghost: MeshInstance3D = _box(size, material)
		ghost.name = "Edge_%d_%d_%d" % [edge.x, edge.y, edge.z]
		ghost.position = Vector3(mid.x, height * 0.5 + 0.002, mid.y)
		ghost.set_meta("edge", edge)
		ghost.set_meta("valid", valid)
		wall_ghosts.append(ghost)
		_ghost_root.add_child(ghost)


## Flat translucent tiles on each proposed cell: green to add, gold to
## remove, red when the change is not allowed.
func _build_floor_ghost(cells: Array[Vector2i], valid: bool, removing: bool) -> void:
	if cells.is_empty():
		return
	_ghost_root = Node3D.new()
	_ghost_root.name = "FloorGhost"
	add_child(_ghost_root)
	var tint: Color = (SEAT_COLOR if removing else VALID_COLOR) if valid else INVALID_COLOR
	tint.a = FLOOR_GHOST_ALPHA
	floor_ghost = MeshInstance3D.new()
	floor_ghost.name = "Tiles"
	floor_ghost.mesh = _tile_mesh(cells, 0.03, FLOOR_GHOST_INSET)
	floor_ghost.material_override = _material(tint, true)
	floor_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_ghost.set_meta("valid", valid)
	floor_ghost.set_meta("removing", removing)
	floor_ghost_cells = cells.duplicate()
	_ghost_root.add_child(floor_ghost)


## Tiles under the pointed-at item: red for Sell (or a refused sale), green for
## the eyedropper, the warm seat colour for the hand.
func _build_hover(item_id: int, tool: int, valid: bool) -> void:
	if item_id < 0 or _shop_view.world == null:
		return
	var item: PlacedItem = _shop_view.world.grid.item(item_id)
	if item == null or item.cells.is_empty():
		return
	_ghost_root = Node3D.new()
	_ghost_root.name = "Hover"
	add_child(_ghost_root)
	var tint: Color = SEAT_COLOR
	if tool == BuildMode.Tool.SELL or not valid:
		tint = INVALID_COLOR
	elif tool == BuildMode.Tool.EYEDROPPER:
		tint = VALID_COLOR
	tint.a = FLOOR_GHOST_ALPHA
	hover_mesh = MeshInstance3D.new()
	hover_mesh.name = "Tiles"
	hover_mesh.mesh = _tile_mesh(item.cells, 0.035, FLOOR_GHOST_INSET)
	hover_mesh.material_override = _material(tint, true)
	hover_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover_mesh.set_meta("item_id", item_id)
	_ghost_root.add_child(hover_mesh)


## The lot (FK-080): a pale fill on unbuilt cells and a pale line around it.
func _build_lot(lot: Rect2i, open_cells: Array[Vector2i]) -> void:
	if lot.size.x <= 0 or lot.size.y <= 0:
		return
	_lot_root = Node3D.new()
	_lot_root.name = "Lot"
	add_child(_lot_root)
	if not open_cells.is_empty():
		var fill: MeshInstance3D = MeshInstance3D.new()
		fill.name = "Fill"
		fill.mesh = _tile_mesh(open_cells, 0.004, 0.0)
		var fill_color: Color = LOT_SWATCH.color
		fill_color.a = LOT_FILL_ALPHA
		fill.material_override = _material(fill_color, true)
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lot_root.add_child(fill)
	var edge_color: Color = LOT_SWATCH.color
	edge_color.a = LOT_EDGE_ALPHA
	var material: StandardMaterial3D = _material(edge_color, true)
	lot_outline = Node3D.new()
	lot_outline.name = "Outline"
	lot_outline.set_meta("lot", lot)
	_lot_root.add_child(lot_outline)
	var low: Vector2 = Vector2(lot.position) * GridMath.CELL_SIZE
	var high: Vector2 = Vector2(lot.end) * GridMath.CELL_SIZE
	var mid: Vector2 = (low + high) * 0.5
	var span: Vector2 = high - low
	var height: float = 0.012
	for z: float in [low.y, high.y]:
		var rail: MeshInstance3D = _box(Vector3(span.x + LOT_EDGE_WIDTH, height, LOT_EDGE_WIDTH), material)
		rail.position = Vector3(mid.x, height * 0.5 + 0.004, z)
		lot_outline.add_child(rail)
	for x: float in [low.x, high.x]:
		var rail: MeshInstance3D = _box(Vector3(LOT_EDGE_WIDTH, height, span.y + LOT_EDGE_WIDTH), material)
		rail.position = Vector3(x, height * 0.5 + 0.004, mid.y)
		lot_outline.add_child(rail)


## One upward-facing quad per cell at `height`, inset from the cell edges.
static func _tile_mesh(cells: Array[Vector2i], height: float, inset: float) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in cells:
		var low: Vector3 = Vector3(cell.x * GridMath.CELL_SIZE + inset, height, cell.y * GridMath.CELL_SIZE + inset)
		var size: float = GridMath.CELL_SIZE - inset * 2.0
		var corners: Array[Vector3] = [low, low + Vector3(size, 0, 0), low + Vector3(size, 0, size), low + Vector3(0, 0, size)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(corners[index])
	return surface.commit()


func _build_warning(id: int, definition: ItemDef, origin: Vector2i, turns: int) -> void:
	if warning_nodes.has(id):
		return
	var root: BoundsOutline = BoundsOutline.new()
	root.name = "Unreachable%d" % id
	root.set_meta("item_id", id)
	var height: float = ShopView.HEIGHTS.get(definition.category, 0.6)
	var sample: ItemVisual = ItemVisual.create(definition, height, _material(definition.placeholder_color))
	root.draw_bounds(sample.get_aabb(), INVALID_COLOR)
	sample.free()
	root.transform = ItemVisual.placed_transform(definition, origin, turns)
	root.rotation.y = -turns * PI * 0.5
	warning_nodes[id] = root
	add_child(root)


func _set_reason(reason: String) -> void:
	if _reason != reason:
		_reason = reason
		reason_changed.emit(_reason)


static func _box(size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func _free_node(node: Node) -> void:
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()
