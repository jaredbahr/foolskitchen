class_name WallSegmentView
extends Node3D
## View-only geometry for wall segments (FK-070). Rebuilt from the grid when
## segments, terrain or the cutaway state change; nothing here touches the sim.
##
## Interior segments are thin painted slabs centred on their grid line, the
## same material and height as the shell walls. A slab runs exactly from vertex
## to vertex, so a doorway's opening is the full 0.5 m cell edge (ART_STYLE:
## doors at least 0.5 wide and 1.1 high). Where segments meet at an angle each
## slab end reaches half a thickness past the vertex, which closes the corner;
## the overlapping pieces share one material, so nothing visibly fights.
## Windows hold the Kenney `wallWindow` pane (the same native pane the street
## frontage uses), framed by the slab: sill, head and two narrow jambs.
## Outer-face windows cut the same opening through the shell cell; ShopView
## lowers that cell's own box to the sill and keeps its top cap at full height.

## About Kenney's own wall panel (0.05) at the furniture scale.
const THICKNESS: float = 0.06
## Doorway head height: above ART_STYLE's 1.1 minimum and Kenney's 1.08 opening.
const DOOR_HEIGHT: float = 1.15
const CAP_HEIGHT: float = 0.02
## Shell panes sit this far inside the room-side face (as RoomDressing's FACE_GAP).
const SHELL_PANE_GAP: float = 0.005
const WINDOW_SCENE: PackedScene = preload("res://assets/kenney/furniture/wallWindow.glb")
const BACK_DOOR_SCENE: PackedScene = preload("res://assets/kenney/furniture/doorwayOpen.glb")
## Lowered (cutaway) windows show a glass-blue strip instead of the dark cap,
## so cycling wall -> window reads in the default view. Palette swatch only.
const GLASS_SWATCH: SwatchDef = preload("res://data/swatches/slate_blue.tres")
## Lowered doorways keep a post stub at each end and a floor threshold strip.
const LOWERED_POST: float = 0.06
const THRESHOLD_HEIGHT: float = 0.012

var _wall_material: Material
var _top_material: Material
## ShopView's floor material (world-space planks and grid), shared so a back
## door's threshold follows floor paint and the grid toggle.
var _floor_material: Material
var _glass_material: StandardMaterial3D
var _painted: Array[MeshInstance3D] = []
var _panes: Array[PropView] = []
var _pane_bounds: AABB = AABB()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()


## Sill and head heights shared with ShopView for shell windows.
func window_span() -> Vector2:
	var bounds: AABB = _native_pane_bounds()
	var center: float = ArtScale.WALL_HEIGHT * 0.5
	return Vector2(center - bounds.size.y * 0.5, center + bounds.size.y * 0.5)


func set_materials(wall_material: Material, top_material: Material, floor_material: Material = null) -> void:
	_wall_material = wall_material
	_top_material = top_material
	_floor_material = floor_material
	for mesh: MeshInstance3D in _painted:
		mesh.material_override = wall_material


func clear() -> void:
	_painted.clear()
	_panes.clear()
	for child: Node in get_children():
		remove_child(child)
		child.free()


## `interior_lowered` follows the cutaway/down wall mode; `lowered_cells` are
## the shell cells ShopView currently draws lowered (their windows hide).
func rebuild(grid: SimGrid, interior_lowered: bool, lowered_cells: Array[Vector2i]) -> void:
	clear()
	if grid == null:
		return
	var span: Vector2 = window_span()
	var interior: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in grid.segment_edges():
		if WallRules.is_interior(grid, edge):
			interior[edge] = grid.segment(edge)
	for edge: Vector3i in interior:
		_build_interior(edge, interior[edge] as SimGrid.Segment, interior, interior_lowered, span)
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) != SimGrid.Segment.WINDOW:
			continue
		var side: Vector2i = WallRules.outer_side(grid, edge)
		if side == Vector2i.ZERO:
			continue
		var cells: Array[Vector2i] = SimGrid.edge_cells(edge)
		var wall_cell: Vector2i = cells[0] if grid.terrain(cells[0]) == SimGrid.Terrain.WALL else cells[1]
		if not lowered_cells.has(wall_cell):
			_build_shell_window(wall_cell, side, span)
	var doors: Dictionary[Vector2i, Vector2i] = shell_door_cells(grid)
	for cell: Vector2i in doors:
		_build_shell_door(cell, doors[cell], lowered_cells.has(cell))


static func shell_door_cells(grid: SimGrid) -> Dictionary[Vector2i, Vector2i]:
	var cells: Dictionary[Vector2i, Vector2i] = {}
	if grid == null:
		return cells
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) != SimGrid.Segment.DOORWAY:
			continue
		var side: Vector2i = WallRules.back_door_side(grid, edge)
		if side == Vector2i.ZERO:
			continue
		for cell: Vector2i in SimGrid.edge_cells(edge):
			if grid.terrain(cell) == SimGrid.Terrain.WALL:
				cells[cell] = side
	return cells


func _build_shell_door(cell: Vector2i, side: Vector2i, lowered: bool) -> void:
	var root: Node3D = Node3D.new()
	root.name = "BackDoor_%d_%d" % [cell.x, cell.y]
	root.position = GridMath.cell_to_world(cell)
	root.rotation.y = -PI * 0.5 if side.y == 0 else 0.0
	add_child(root)
	# The opened shell cell gets a floor tile, level with the room's floor and
	# in its material, so the doorway has a threshold instead of a hole.
	var tile: MeshInstance3D = MeshInstance3D.new()
	tile.name = "Floor"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(GridMath.CELL_SIZE, GridMath.CELL_SIZE)
	tile.mesh = plane
	tile.material_override = _floor_material
	root.add_child(tile)
	var half: float = GridMath.CELL_SIZE * 0.5
	if lowered:
		_slab(root, -half, -half + LOWERED_POST, 0.0, ShopView.LOWERED_HEIGHT, GridMath.CELL_SIZE)
		_slab(root, half - LOWERED_POST, half, 0.0, ShopView.LOWERED_HEIGHT, GridMath.CELL_SIZE)
		return
	_slab(root, -half, half, DOOR_HEIGHT, ArtScale.WALL_HEIGHT, GridMath.CELL_SIZE)
	_cap(root, -half, half, ArtScale.WALL_HEIGHT, GridMath.CELL_SIZE)
	var door: PropView = RoomDressing.make_asset(BACK_DOOR_SCENE, "KenneyDoor")
	if door != null:
		var bounds: AABB = door.get_combined_aabb()
		door.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
		root.add_child(door)


## Shell cells whose own box ShopView must cut down to the sill.
static func shell_window_cells(grid: SimGrid) -> Dictionary[Vector2i, Vector2i]:
	var cells: Dictionary[Vector2i, Vector2i] = {}
	if grid == null:
		return cells
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) != SimGrid.Segment.WINDOW:
			continue
		var side: Vector2i = WallRules.outer_side(grid, edge)
		if side == Vector2i.ZERO:
			continue
		var pair: Array[Vector2i] = SimGrid.edge_cells(edge)
		var wall_cell: Vector2i = pair[0] if grid.terrain(pair[0]) == SimGrid.Terrain.WALL else pair[1]
		if not cells.has(wall_cell):
			cells[wall_cell] = side
	return cells


func pane_nodes() -> Array[PropView]:
	return _panes.duplicate()


func _build_interior(edge: Vector3i, kind: SimGrid.Segment, interior: Dictionary[Vector3i, int],
		lowered: bool, span: Vector2) -> void:
	var ends: Array[Vector2i] = SimGrid.edge_vertices(edge)
	var start_extra: float = _corner_extension(edge, ends[0], interior)
	var end_extra: float = _corner_extension(edge, ends[1], interior)
	var root: Node3D = Node3D.new()
	root.name = "Segment_%d_%d_%d" % [edge.x, edge.y, edge.z]
	root.set_meta(&"edge", edge)
	root.set_meta(&"kind", int(kind))
	var mid: Vector2 = (Vector2(ends[0]) + Vector2(ends[1])) * 0.5 * GridMath.CELL_SIZE
	root.position = Vector3(mid.x, 0.0, mid.y)
	# Local +X runs along the grid line: east for north edges, south for west edges.
	root.rotation.y = -PI * 0.5 if edge.z == SimGrid.EDGE_WEST else 0.0
	add_child(root)
	var half: float = GridMath.CELL_SIZE * 0.5
	var x0: float = -half - start_extra
	var x1: float = half + end_extra
	var full: float = ArtScale.WALL_HEIGHT
	var low: float = ShopView.LOWERED_HEIGHT
	match kind:
		SimGrid.Segment.WALL:
			var height: float = low if lowered else full
			_slab(root, x0, x1, 0.0, height, THICKNESS)
			_cap(root, x0, x1, height, THICKNESS)
		SimGrid.Segment.DOORWAY:
			if lowered:
				# Post stubs at both ends plus a threshold: the opening still reads.
				_slab(root, x0, x0 + LOWERED_POST + start_extra, 0.0, low, THICKNESS)
				_cap(root, x0, x0 + LOWERED_POST + start_extra, low, THICKNESS)
				_slab(root, x1 - LOWERED_POST - end_extra, x1, 0.0, low, THICKNESS)
				_cap(root, x1 - LOWERED_POST - end_extra, x1, low, THICKNESS)
				var threshold: MeshInstance3D = _box(Vector3(x1 - x0, THRESHOLD_HEIGHT, THICKNESS), _top_material)
				threshold.name = "Threshold"
				threshold.position = Vector3((x0 + x1) * 0.5, THRESHOLD_HEIGHT * 0.5, 0.0)
				root.add_child(threshold)
			else:
				_slab(root, x0, x1, DOOR_HEIGHT, full, THICKNESS)
				_cap(root, x0, x1, full, THICKNESS)
		SimGrid.Segment.WINDOW:
			if lowered:
				var height: float = minf(low, span.x)
				_slab(root, x0, x1, 0.0, height, THICKNESS)
				var glass: MeshInstance3D = _box(Vector3(x1 - x0, CAP_HEIGHT, THICKNESS), _glass())
				glass.name = "Glass"
				glass.position = Vector3((x0 + x1) * 0.5, height + 0.005, 0.0)
				root.add_child(glass)
			else:
				var opening: float = _native_pane_bounds().size.x * 0.5
				_slab(root, x0, x1, 0.0, span.x, THICKNESS)
				_slab(root, x0, x1, span.y, full, THICKNESS)
				_slab(root, x0, -opening, span.x, span.y, THICKNESS)
				_slab(root, opening, x1, span.x, span.y, THICKNESS)
				_cap(root, x0, x1, full, THICKNESS)
				_pane(root, span)


## A shell cell's window: head and jambs around the pane. The sill is the
## cell's own lowered box, drawn by ShopView.
func _build_shell_window(cell: Vector2i, side: Vector2i, span: Vector2) -> void:
	var root: Node3D = Node3D.new()
	root.name = "ShellWindow_%d_%d" % [cell.x, cell.y]
	root.set_meta(&"wall_cell", cell)
	root.position = GridMath.cell_to_world(cell)
	# Local +X runs along the wall face; local Z through the wall.
	root.rotation.y = -PI * 0.5 if side.y == 0 else 0.0
	add_child(root)
	var half: float = GridMath.CELL_SIZE * 0.5
	var depth: float = GridMath.CELL_SIZE
	var opening: float = _native_pane_bounds().size.x * 0.5
	_slab(root, -half, half, span.y, ArtScale.WALL_HEIGHT, depth)
	_slab(root, -half, -opening, span.x, span.y, depth)
	_slab(root, opening, half, span.x, span.y, depth)
	var pane: PropView = _pane(root, span)
	if pane != null:
		# Flush with the room-side face, so the steep camera sees the whole pane
		# from inside and a deep reveal from the street.
		var bounds: AABB = pane.get_combined_aabb()
		var inward: Vector3 = -Vector3(side.x, 0.0, side.y) * (depth * 0.5 - bounds.size.z * 0.5 - SHELL_PANE_GAP)
		pane.position += root.transform.basis.inverse() * inward


## Half a thickness past a vertex where another segment meets at an angle.
func _corner_extension(edge: Vector3i, vertex: Vector2i, interior: Dictionary[Vector3i, int]) -> float:
	for other: Vector3i in SimGrid.edges_at_vertex(vertex):
		if other != edge and other.z != edge.z and interior.has(other):
			return THICKNESS * 0.5
	return 0.0


func _slab(root: Node3D, x0: float, x1: float, y0: float, y1: float, depth: float) -> void:
	if x1 - x0 <= 0.0001 or y1 - y0 <= 0.0001:
		return
	var mesh: MeshInstance3D = _box(Vector3(x1 - x0, y1 - y0, depth), _wall_material)
	mesh.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)
	_painted.append(mesh)
	root.add_child(mesh)


func _cap(root: Node3D, x0: float, x1: float, height: float, depth: float) -> void:
	var mesh: MeshInstance3D = _box(Vector3(x1 - x0, CAP_HEIGHT, depth), _top_material)
	mesh.name = "Top"
	mesh.position = Vector3((x0 + x1) * 0.5, height + 0.005, 0.0)
	root.add_child(mesh)


func _pane(root: Node3D, span: Vector2) -> PropView:
	var pane: PropView = RoomDressing.make_asset(WINDOW_SCENE, "Pane", true)
	if pane == null:
		return null
	var bounds: AABB = pane.get_combined_aabb()
	pane.position = Vector3(0.0, (span.x + span.y) * 0.5 - bounds.get_center().y, -bounds.get_center().z)
	_panes.append(pane)
	root.add_child(pane)
	return pane


func _glass() -> StandardMaterial3D:
	if _glass_material == null:
		_glass_material = StandardMaterial3D.new()
		_glass_material.albedo_color = GLASS_SWATCH.color
		_glass_material.roughness = 0.3
	return _glass_material


func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	return node


func _native_pane_bounds() -> AABB:
	if _pane_bounds.size == Vector3.ZERO:
		var pane: PropView = RoomDressing.make_asset(WINDOW_SCENE, "Measure", true)
		if pane != null:
			_pane_bounds = pane.get_combined_aabb()
			pane.free()
	return _pane_bounds
