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
## The kit's doorway with its own door leaf (D25: a real back door). Like a
## real service door the leaf swings out, onto the path outside where nothing
## is ever placed, as the delivery person (or staff) pass; ShopView sets how
## far from where people are (set_door_open), view only.
const BACK_DOOR_SCENE: PackedScene = preload("res://assets/kenney/furniture/doorway.glb")
## How far a fully open leaf turns (degrees): right round, flat against the
## outside wall like a propped-open service door, clear of the path and of
## anyone on it (the Mini Characters' heads are as wide as the door).
const DOOR_OPEN_DEGREES: float = 178.0
## While the leaf turns to square its hinge moves out to the wall's outer
## face, so past square the leaf swings round outside the wall and lies on the
## face: its centre this far from the wall's centre line (half the 0.5 m wall
## plus the leaf's handle).
const DOOR_FLAT_OUT: float = 0.315
## Past square the leaf slides this far onto its hinge-side jamb (metres), so
## an open leaf is clear of the opening.
const DOOR_OPEN_SLIDE: float = 0.08
## Share of DOOR_OPEN_SLIDE the hinge steps away from its jamb while turning
## to square (0.16 = 13 mm), so the slab's corner clears the jamb.
const DOOR_TURN_CLEARANCE: float = 0.16
## The back path (FK-099): one square of the street's pavement per cell with a
## thin joint between them, laid flush (a sliver thick, so no side face shows
## against the dark beyond the lot).
const PATH_JOINT: float = 0.025
const PATH_THICKNESS: float = 0.008
## Paving lightness steps (towards cream / charcoal), picked per tile from its
## cell, so the path reads as laid stones, not one slab.
const PATH_SHADES: Array[float] = [0.0, 0.07, -0.06, 0.03, -0.03]
## The back alley is solid across the lot and PATH_SOLID_CELLS past it, then
## fades into the ground colour over PATH_FADE_CELLS and stops (the delivery
## person walks on, out of sight, and fades in and out further away). It is
## ALLEY_LANES cells wide.
const PATH_SOLID_CELLS: int = 4
## The paving reaches this many cells past the lot (her route goes on further,
## WallRules.ALLEY_REACH, over bare ground well out of sight).
const PATH_REACH: int = 24
const PATH_FADE_CELLS: int = PATH_REACH - PATH_SOLID_CELLS
const ALLEY_LANES: int = 2
## A side wall's alley fades out over this many cells past the shop's front,
## towards the street, rather than stopping square at the front line.
const PATH_STREET_FADE_CELLS: int = 3
## The fade's end: walnut darkened towards charcoal, close to the dark ground
## the lighting rig shows beyond the lot. Palette swatches only.
const PATH_FAR_SWATCH: SwatchDef = preload("res://data/swatches/walnut.tres")
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
## Back-door leaves by shell cell: {leaf, sign (turns it outward), base
## (shut position), slide (fully open offset, in the leaf's parent space)}.
var _leaves: Dictionary[Vector2i, Dictionary] = {}
## Pavement of the paths outside back doors (their tints are released on clear).
var _paths: Array[PropView] = []
## The shop's lot (ShopView.set_lot from Main): the back alley runs along its
## outer edge. Empty: along the building's.
var lot: Rect2i = Rect2i()
var _grid: SimGrid
var _stone_bounds: AABB = AABB()
## The pane's bounds for `window_opening` (measured once).
static var _opening_bounds: AABB = AABB()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()


## Sill and head heights shared with ShopView for shell windows.
func window_span() -> Vector2:
	var bounds: AABB = _native_pane_bounds()
	var center: float = ArtScale.WALL_HEIGHT * 0.5
	return Vector2(center - bounds.size.y * 0.5, center + bounds.size.y * 0.5)


## A window's opening seen from the room: x across the wall from its middle,
## y from the floor (sill to head). Hung window items (D26) fit inside it.
static func window_opening() -> Rect2:
	if _opening_bounds.size == Vector3.ZERO:
		var pane: PropView = RoomDressing.make_asset(WINDOW_SCENE, "Measure", true)
		if pane != null:
			_opening_bounds = pane.get_combined_aabb()
			pane.free()
	var centre: float = ArtScale.WALL_HEIGHT * 0.5
	return Rect2(-_opening_bounds.size.x * 0.5, centre - _opening_bounds.size.y * 0.5,
		_opening_bounds.size.x, _opening_bounds.size.y)


func set_materials(wall_material: Material, top_material: Material, floor_material: Material = null) -> void:
	_wall_material = wall_material
	_top_material = top_material
	_floor_material = floor_material
	for mesh: MeshInstance3D in _painted:
		mesh.material_override = wall_material


func clear() -> void:
	_painted.clear()
	_panes.clear()
	_leaves.clear()
	for tile: PropView in _paths:
		if is_instance_valid(tile):
			tile.clear_body_tint()
	_paths.clear()
	for child: Node in get_children():
		remove_child(child)
		child.free()


## `interior_lowered` follows the cutaway/down wall mode; `lowered_cells` are
## the shell cells ShopView currently draws lowered (their windows hide).
func rebuild(grid: SimGrid, interior_lowered: bool, lowered_cells: Array[Vector2i]) -> void:
	clear()
	_grid = grid
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
		var alley: Dictionary = WallRules.back_alley(grid, cell, doors[cell], lot)
		_build_shell_door(grid, cell, doors[cell], lowered_cells.has(cell), alley.get("from", Vector2i.ZERO))
		_build_back_path(cell, alley, doors[cell])


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


func _build_shell_door(grid: SimGrid, cell: Vector2i, side: Vector2i, lowered: bool,
		approach_from: Vector2i = Vector2i.ZERO) -> void:
	var root: Node3D = Node3D.new()
	root.name = "BackDoor_%d_%d" % [cell.x, cell.y]
	root.set_meta(&"segment_edge", SimGrid.edge_between(cell, cell - side))
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
		var leaf: Node3D = door.find_child("door", true, false) as Node3D
		if leaf != null:
			# Hinged on the side where the open leaf has open ground beside the
			# path (a wing of the shop round an inner corner would cut it), and
			# else on the side away from where deliveries come along the alley.
			var hinge: Vector2i = _hinge_side(root, leaf)
			var blocked: bool = not _open_ground(grid, cell + side + hinge)
			if (blocked or hinge == approach_from) and _open_ground(grid, cell + side - hinge):
				root.rotation.y += PI
			leaf.set_meta(&"door_cell", cell)
			_leaves[cell] = {"leaf": leaf, "sign": _outward_sign(root, leaf, side), "base": leaf.position,
				"slide": _hinge_slide(root, leaf), "out": _flat_out(root, leaf, side)}


## The paving behind a back door (FK-099): a short path from the door out to
## the back alley (WallRules.back_alley), and the alley itself, two cells
## wide along the lot's outer edge, both of the street's pavement (Kenney
## floorHalf, palette tint) cut to one stone per cell, flush with the floor.
## The alley is solid across the lot and PATH_SOLID_CELLS past it, then
## fades into the ground over PATH_FADE_CELLS (out of sight at the usual
## zoom); a side wall's alley is solid to the shop's front and fades out over
## PATH_STREET_FADE_CELLS towards the street.
func _build_back_path(door: Vector2i, alley: Dictionary, side: Vector2i) -> void:
	if alley.is_empty():
		return
	var path: Array[Vector2i] = alley["path"]
	for cell: Vector2i in path:
		_add_stone(cell, 0.0, door)
	var junction: Vector2i = alley["junction"]
	var axis: Vector2i = alley["axis"]
	var along: int = junction.x * axis.x + junction.y * axis.y
	var span_low: int = int(alley["first"]) + WallRules.ALLEY_REACH
	var span_high: int = int(alley["last"]) - WallRules.ALLEY_REACH
	var street: Vector2i = WallRules.street_side(_grid) if _grid != null else Vector2i.DOWN
	if street == axis:
		span_high = int(alley["last"])
	elif street == -axis:
		span_low = int(alley["first"])
	for t: int in range(int(alley["first"]), int(alley["last"]) + 1):
		var outside: int = maxi(span_low - t, t - span_high) - PATH_SOLID_CELLS
		if outside > PATH_FADE_CELLS:
			continue
		var fade: float = float(maxi(outside, 0)) / float(PATH_FADE_CELLS + 1)
		var cell: Vector2i = junction + axis * (t - along)
		for lane: int in ALLEY_LANES:
			_add_stone(cell + side * lane, fade, door)
	# A side wall's alley runs solid to the shop's front, then fades out over
	# PATH_STREET_FADE_CELLS towards the street instead of stopping square.
	if street == axis or street == -axis:
		var end: int = int(alley["last"]) if street == axis else int(alley["first"])
		for step: int in range(1, PATH_STREET_FADE_CELLS + 1):
			var fade: float = float(step) / float(PATH_STREET_FADE_CELLS + 1)
			var cell: Vector2i = junction + axis * (end + street.x * axis.x * step + street.y * axis.y * step - along)
			for lane: int in ALLEY_LANES:
				_add_stone(cell + side * lane, fade, door)


## One paving stone on `cell`: the street's pavement, flush, a joint round
## it, its shade picked from the cell, `fade` (0..1) of the way into the dark
## ground beyond the lot.
func _add_stone(cell: Vector2i, fade: float, door: Vector2i) -> void:
	if _stone_bounds == AABB():
		var probe: PropView = RoomDressing.make_asset(RoomDressing.PAVEMENT, "Measure", false, true)
		if probe == null:
			return
		_stone_bounds = probe.get_combined_aabb()
		probe.clear_body_tint()
		probe.free()
	var tile: PropView = RoomDressing.make_asset(RoomDressing.PAVEMENT, "BackPath_%d_%d" % [cell.x, cell.y], false, true)
	if tile == null:
		return
	var shade: float = PATH_SHADES[posmod(cell.x * 7 + cell.y * 13, PATH_SHADES.size())]
	var color: Color = RoomDressing.pavement_color()
	color = color.lerp(RoomDressing.PAVEMENT_LIGHT_SWATCH.color, shade) if shade >= 0.0 \
		else color.lerp(RoomDressing.PAVEMENT_SWATCH.color, -shade)
	if fade > 0.0:
		color = color.lerp(PATH_FAR_SWATCH.color.lerp(RoomDressing.PAVEMENT_SWATCH.color, 0.3).darkened(0.35), fade)
	tile.set_body_tint(color)
	var square: float = GridMath.CELL_SIZE - PATH_JOINT
	tile.scale = Vector3(square / _stone_bounds.size.x, PATH_THICKNESS / _stone_bounds.size.y, square / _stone_bounds.size.z)
	tile.position = GridMath.cell_to_world(cell)
	tile.position.y = -PATH_THICKNESS + 0.001
	tile.set_meta(&"door_cell", door)
	tile.set_meta(&"cell", cell)
	_paths.append(tile)
	add_child(tile)


func path_tiles() -> Array[PropView]:
	return _paths.duplicate()


## Back-door shell cells whose leaf is drawn (walls up), in grid order.
func door_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = _leaves.keys()
	cells.sort()
	return cells


func door_leaf(cell: Vector2i) -> Node3D:
	return _leaves[cell]["leaf"] as Node3D if _leaves.has(cell) else null


## 0 shut .. 1 flat open, out onto the path. View only.
func set_door_open(cell: Vector2i, amount: float) -> void:
	if not _leaves.has(cell):
		return
	var leaf: Node3D = _leaves[cell]["leaf"] as Node3D
	var open: float = clampf(amount, 0.0, 1.0)
	var degrees: float = DOOR_OPEN_DEGREES * open
	# Up to square the leaf turns inside the opening while its hinge moves out
	# to the wall's outer face; only then does it swing on round towards the
	# wall, and slide onto the jamb, so no part of it ever passes into the wall.
	var out: float = clampf(degrees / 90.0, 0.0, 1.0)
	var slide: float = clampf((degrees - 90.0) / (DOOR_OPEN_DEGREES - 90.0), 0.0, 1.0)
	# Mid-turn the slab's hinge-side corner would graze the jamb: the hinge
	# steps that far off it (a few millimetres) and back by square.
	slide -= DOOR_TURN_CLEARANCE * sin(PI * out)
	leaf.rotation.y = float(_leaves[cell]["sign"]) * deg_to_rad(degrees)
	leaf.position = (_leaves[cell]["base"] as Vector3) + (_leaves[cell]["slide"] as Vector3) * slide \
		+ (_leaves[cell]["out"] as Vector3) * out


## +1 or -1: the turn of the leaf about its hinge that moves its free edge out
## of the shop (towards `side`, the outward direction). Read from the leaf's
## actual transforms below the door root, so the kit's own facing is kept.
static func _outward_sign(root: Node3D, leaf: Node3D, side: Vector2i) -> float:
	var outward: Vector3 = Vector3(side.x, 0.0, side.y)
	var local_outward: Vector3 = root.transform.basis.inverse() * outward
	var saved: float = leaf.rotation.y
	leaf.rotation.y = PI * 0.5
	var open_edge: Vector3 = _to_ancestor(leaf, root) * Vector3(0.4, 0.0, 0.0)
	leaf.rotation.y = 0.0
	var shut_edge: Vector3 = _to_ancestor(leaf, root) * Vector3(0.4, 0.0, 0.0)
	leaf.rotation.y = saved
	return 1.0 if (open_edge - shut_edge).dot(local_outward) > 0.0 else -1.0


## The grid direction along the wall from the door's centre to its hinge.
static func _hinge_side(root: Node3D, leaf: Node3D) -> Vector2i:
	var hinge: Vector3 = root.transform.basis * (_to_ancestor(leaf.get_parent() as Node3D, root) * leaf.position)
	if absf(hinge.x) >= absf(hinge.z):
		return Vector2i(int(signf(hinge.x)), 0)
	return Vector2i(0, int(signf(hinge.z)))


## Open ground outside: unbought lot, or beyond the grid.
static func _open_ground(grid: SimGrid, cell: Vector2i) -> bool:
	return not grid.in_bounds(cell) or grid.terrain(cell) == SimGrid.Terrain.OUTSIDE


## DOOR_OPEN_SLIDE along the wall toward the leaf's hinge, in the leaf's
## parent space (the kit model sits under a scaled, turned Art node).
static func _hinge_slide(root: Node3D, leaf: Node3D) -> Vector3:
	var parent: Node3D = leaf.get_parent() as Node3D
	var to_root: Transform3D = _to_ancestor(parent, root)
	var hinge: Vector3 = to_root * leaf.position
	# Local +X runs along the wall; the hinge is on the side its x points to.
	var along: Vector3 = Vector3(signf(hinge.x), 0.0, 0.0) * DOOR_OPEN_SLIDE
	return to_root.basis.inverse() * along


## DOOR_FLAT_OUT towards `side` (out of the shop), in the leaf's parent space.
static func _flat_out(root: Node3D, leaf: Node3D, side: Vector2i) -> Vector3:
	var to_root: Transform3D = _to_ancestor(leaf.get_parent() as Node3D, root)
	var local_out: Vector3 = root.transform.basis.inverse() * Vector3(side.x, 0.0, side.y)
	var hinge: Vector3 = to_root * leaf.position
	var shift: float = DOOR_FLAT_OUT - hinge.dot(local_out.normalized())
	return to_root.basis.inverse() * (local_out.normalized() * shift)


static func _to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			xf = (cursor as Node3D).transform * xf
		cursor = cursor.get_parent()
	return xf


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
		SimGrid.Segment.STALL_PARTITION:
			var height: float = low if lowered else ArtScale.STALL_PARTITION_HEIGHT
			root.add_child(StallPartitionView.make_panel(height))
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
	root.set_meta(&"segment_edge", SimGrid.edge_between(cell, cell - side))
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
