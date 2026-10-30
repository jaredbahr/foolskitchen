class_name WallFinishView
extends Node3D
## View-only wall finishes and wall decor (D26), under ShopView. Rebuilt from
## the grid, the editor's WallFinishes and WallDecor, and the wall heights.
##
## A finished face gets a thin facing just off the wall (wall_finish.gdshader,
## one material per look), as high as the wall is drawn: full height, or the
## stub in Cutaway and Walls Down. Faces left as the default plain paint draw
## nothing here, so a shop without finishes renders exactly as before.
## Hung items are the item's PropView wrapper with its back on the face; they
## hide while their wall is lowered (they would float over the stub), and the
## build ghost shows on any face so placing still reads. A window item (the
## neon OPEN sign) hangs in an outside window instead, fitted to its opening
## and facing the street (window_transform).

const SHADER: Shader = preload("res://src/world/wall_finish.gdshader")
## The facing sits this far off the wall surface (no depth fighting).
const FACE_GAP: float = 0.003
## Interior slabs are WallSegmentView.THICKNESS thick, centred on their line.
const HALF_THICKNESS: float = WallSegmentView.THICKNESS * 0.5
## Automatic accents: a darker shade of the main colour.
const AUTO_ACCENT_SHADE: float = 0.78
## Wall decor wrappers stand on a cell centre with their back on the cell's
## far edge; a face of an interior wall is this much nearer the room.
const HUNG_FALLBACK_HEIGHT: float = 0.6
## A glowing hung item (`ItemDef.glow_color`) gets one small omni light this
## far in front of its face, at its middle: a soft pool on the wall and the
## floor below, never the whole room. No shadows, so it stays cheap in the
## Compatibility renderer (each light is one more pass over the meshes in its
## range; Godot draws up to 8 per mesh). The shop has no day/night yet, so
## the glow is constant.
const GLOW_OUT: float = 0.2
const GLOW_RANGE: float = 1.2
const GLOW_ENERGY: float = 0.45
const GLOW_ATTENUATION: float = 1.6
## The glowing item's own meshes sit on this render layer only (every camera
## and the shop's lights still see it), and its glow skips it: the light
## would wash out the sign it comes from.
const GLOW_SELF_LAYER: int = 1 << 19
## A window item (the OPEN sign) hangs in the street end of the opening, its
## front to the street just inside the wall's outer face (the steep camera
## sees no deeper into a window from outside; from the room it shows its back
## through the glass), scaled down (never up) to this share of the opening's
## width and height, and centred in it. Its glow stands in the middle of the
## opening, so it pools on the floor inside and the pavement outside alike.
const WINDOW_GAP: float = 0.012
const WINDOW_FILL: Vector2 = Vector2(0.9, 0.8)
## A window item's glow never reaches another room: its light is this small
## (it lights the window's own jambs; a neighbouring room is at least 0.375 m
## away, past an interior wall at the window cell's side), and the pools on
## the floor inside and the ground outside are flat additive glow squares,
## each exactly the one cell in front of the window, brightest at the wall.
const WINDOW_GLOW_RANGE: float = 0.34
const WINDOW_GLOW_ENERGY: float = 0.6
const POOL_LIFT: float = 0.004
const POOL_STRENGTH: float = 0.55

var _grid: SimGrid
var _content: ContentDB
var _finishes: WallFinishes
var _decor: WallDecor
var _preview: Dictionary[Vector3i, FloorFinishes.Finish] = {}
var _wall_colour: Color = Color("e6d5b8")
var _shop_swatch: StringName = &""
var _interior_lowered: bool = false
var _lowered_cells: Dictionary[Vector2i, bool] = {}
var _materials: Dictionary[String, ShaderMaterial] = {}
var _finish_nodes: Array[MeshInstance3D] = []
## Hung items by anchor face.
var item_nodes: Dictionary[Vector3i, ItemVisual] = {}
var _ghost: ItemVisual
var _ghost_key: Array = []
var _hidden_anchor: Vector3i = WallFaces.NO_FACE
var _restaurant_name: String = MenuSettings.DEFAULT_NAME
var _hung_preview_anchor: Vector3i = WallFaces.NO_FACE
var _hung_preview_swatch: StringName = &""


func bind(grid: SimGrid, content: ContentDB, finishes: WallFinishes, decor: WallDecor) -> void:
	_grid = grid
	_content = content
	_finishes = finishes
	_decor = decor
	_preview.clear()
	rebuild()


## The same normalized name used by the HUD and the existing free name board.
func set_restaurant_name(value: String) -> bool:
	var normalized: String = MenuSettings.normalized_restaurant_name(value)
	if normalized.is_empty():
		return false
	_restaurant_name = normalized
	for node: ItemVisual in item_nodes.values():
		node.set_restaurant_name(normalized)
	if _ghost != null:
		_ghost.set_restaurant_name(normalized)
	return true


func preview_hung_paint(anchor: Vector3i, swatch_id: StringName) -> void:
	if _hung_preview_anchor == anchor and _hung_preview_swatch == swatch_id:
		return
	_hung_preview_anchor = anchor
	_hung_preview_swatch = swatch_id
	_rebuild_items()


func clear_hung_paint_preview() -> void:
	if _hung_preview_anchor == WallFaces.NO_FACE:
		return
	_hung_preview_anchor = WallFaces.NO_FACE
	_hung_preview_swatch = &""
	_rebuild_items()


## The shop's own wall colour (the default faces' paint) and its swatch id.
func set_wall_colour(colour: Color, swatch_id: StringName) -> void:
	if colour == _wall_colour and swatch_id == _shop_swatch:
		return
	_wall_colour = colour
	_shop_swatch = swatch_id
	_materials.clear()
	rebuild()


## Follows ShopView's wall heights: interior segments lowered (Cutaway and
## Down), and the shell cells drawn lowered.
func set_lowered(interior_lowered: bool, lowered_cells: Array[Vector2i]) -> void:
	var cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in lowered_cells:
		cells[cell] = true
	if interior_lowered == _interior_lowered and cells == _lowered_cells:
		return
	_interior_lowered = interior_lowered
	_lowered_cells = cells
	rebuild()


## Shows proposed looks (face -> Finish) until cleared. Nothing is changed.
func preview_finishes(changes: Dictionary[Vector3i, FloorFinishes.Finish]) -> void:
	if changes.size() == _preview.size():
		var same: bool = true
		for face: Vector3i in changes:
			if not _preview.has(face) or not _preview[face].same(changes[face]):
				same = false
				break
		if same:
			return
	_preview = changes.duplicate()
	_rebuild_finishes()


func clear_preview() -> void:
	if not _preview.is_empty():
		_preview.clear()
		_rebuild_finishes()


func preview_faces() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	out.assign(_preview.keys())
	WallFaces.sort(out)
	return out


## The build ghost of a wall item at `anchor` (valid: green, else red), and
## the hung item it moves (hidden while held). NO_FACE anchor hides it.
func show_ghost(definition: ItemDef, anchor: Vector3i, valid: bool, moving: Vector3i = WallFaces.NO_FACE) -> void:
	var held: WallDecor.Hung = _decor.item(moving) if _decor != null else null
	var swatch: StringName = held.swatch_id if held != null else &""
	var key: Array = [definition, anchor, valid, moving, swatch]
	if key == _ghost_key:
		return
	_ghost_key = key
	if _ghost != null:
		remove_child(_ghost)
		_ghost.free()
		_ghost = null
	_hidden_anchor = moving
	_sync_item_visibility()
	if definition == null or anchor == WallFaces.NO_FACE or _grid == null:
		return
	_ghost = ItemVisual.create(definition, HUNG_FALLBACK_HEIGHT, _flat(definition.placeholder_color))
	_ghost.name = "WallGhost"
	_ghost.set_restaurant_name(_restaurant_name)
	if definition.paintable and not swatch.is_empty():
		var color: Color = _colour(swatch, definition.placeholder_color)
		_ghost.apply_paint(color, _flat(color))
	var tint: Color = BuildPreview.VALID_COLOR if valid else BuildPreview.INVALID_COLOR
	tint.a = BuildPreview.VALID_ALPHA if valid else BuildPreview.INVALID_ALPHA
	_ghost.set_ghost_tint(tint)
	if ExteriorSupport.is_exterior(_grid, anchor):
		fit_exterior(_ghost, definition.footprint.x)
		_ghost.transform = exterior_transform(_grid, anchor, definition.footprint.x, _ghost.get_aabb())
	elif definition.hangs_in_window():
		# In a window, or (refused) flat on the pointed wall face.
		fit_window(_ghost)
		_ghost.transform = window_transform(anchor, _ghost.get_aabb()) if WallFaces.is_window(_grid, anchor) \
			else hung_transform(_grid, anchor, 1)
	else:
		_ghost.transform = hung_transform(_grid, anchor, definition.footprint.x)
	_ghost.set_meta(&"anchor", anchor)
	add_child(_ghost)


func hide_ghost() -> void:
	show_ghost(null, WallFaces.NO_FACE, false)


func ghost() -> ItemVisual:
	return _ghost


func rebuild() -> void:
	_rebuild_finishes()
	_rebuild_items()


# --- Finishes -------------------------------------------------------------------

## The look drawn on `face`: the preview, else the editor's, else the default.
func drawn_finish(face: Vector3i) -> FloorFinishes.Finish:
	if _preview.has(face):
		return _preview[face]
	if _finishes != null:
		return _finishes.finish(face)
	return FloorFinishes.Finish.new(WallStyleDef.DEFAULT_ID, _shop_swatch, &"")


## Faces drawn with a facing (stored or previewed), sorted.
func finished_faces() -> Array[Vector3i]:
	var wanted: Dictionary[Vector3i, bool] = {}
	if _finishes != null:
		for face: Vector3i in _finishes.faces():
			wanted[face] = true
	for face: Vector3i in _preview:
		wanted[face] = true
	var out: Array[Vector3i] = []
	for face: Vector3i in wanted:
		if _grid != null and WallFaces.is_face(_grid, face):
			out.append(face)
	WallFaces.sort(out)
	return out


func finish_nodes() -> Array[MeshInstance3D]:
	return _finish_nodes.duplicate()


func _rebuild_finishes() -> void:
	for node: MeshInstance3D in _finish_nodes:
		if is_instance_valid(node):
			remove_child(node)
			node.free()
	_finish_nodes.clear()
	if _grid == null:
		return
	var groups: Dictionary[String, Array] = {}
	var looks: Dictionary[String, FloorFinishes.Finish] = {}
	for face: Vector3i in finished_faces():
		var look: FloorFinishes.Finish = drawn_finish(face)
		var previewed: bool = _preview.has(face)
		var key: String = "%s|%s" % [str(look), previewed]
		if not groups.has(key):
			groups[key] = []
			looks[key] = look
		(groups[key] as Array).append(face)
	var keys: Array[String] = []
	keys.assign(groups.keys())
	keys.sort()
	for key: String in keys:
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for face: Vector3i in groups[key]:
			_add_face(surface, face)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "WallFinish%d" % _finish_nodes.size()
		node.mesh = surface.commit()
		node.material_override = _material(looks[key], key.ends_with("|true"))
		node.set_meta(&"look", key)
		node.set_meta(&"faces", groups[key].duplicate())
		_finish_nodes.append(node)
		add_child(node)


## One facing quad: world-metre UV (along the line, up), 0..1 UV2.
func _add_face(surface: SurfaceTool, face: Vector3i) -> void:
	var frame: Dictionary = face_frame(_grid, face, _interior_lowered, _lowered_cells)
	var origin: Vector3 = frame["origin"]
	var tangent: Vector3 = frame["tangent"]
	var normal: Vector3 = frame["normal"]
	var x0: float = frame["x0"]
	var x1: float = frame["x1"]
	var height: float = frame["height"]
	var base_u: float = origin.x * tangent.x + origin.z * tangent.z
	var corners: Array[Vector3] = [origin + tangent * x0, origin + tangent * x1,
		origin + tangent * x1 + Vector3.UP * height, origin + tangent * x0 + Vector3.UP * height]
	var uvs: Array[Vector2] = [Vector2(base_u + x0, 0.0), Vector2(base_u + x1, 0.0),
		Vector2(base_u + x1, height), Vector2(base_u + x0, height)]
	var local: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	# Wound to face the room (front faces toward `normal`).
	for index: int in [0, 2, 1, 0, 3, 2]:
		surface.set_normal(normal)
		surface.set_uv(uvs[index])
		surface.set_uv2(local[index])
		surface.add_vertex(corners[index])


## Where a face is drawn: `origin` on the floor at the middle of the face (on
## the wall surface plus FACE_GAP), `normal` into the room, `tangent` along
## the wall to the right (seen from the room), the facing's ends `x0`/`x1`
## along it (interior faces reach round or stop at a joining wall's slab) and
## its `height` (the wall's drawn height). `inset` is from the grid line.
static func face_frame(grid: SimGrid, face: Vector3i, interior_lowered: bool,
		lowered_cells: Dictionary[Vector2i, bool]) -> Dictionary:
	var here: Vector2i = WallFaces.cell(face)
	var into: Vector2i = WallFaces.step(face)
	var right: Vector2i = WallFaces.along(face)
	var interior: bool = grid.segment(WallFaces.edge(face)) == SimGrid.Segment.WALL
	var inset: float = (HALF_THICKNESS if interior else 0.0) + FACE_GAP
	var normal: Vector3 = -Vector3(into.x, 0.0, into.y)
	var tangent: Vector3 = Vector3(right.x, 0.0, right.y)
	var origin: Vector3 = GridMath.cell_to_world(here) + Vector3(into.x, 0.0, into.y) * (GridMath.CELL_SIZE * 0.5 - inset)
	var half: float = GridMath.CELL_SIZE * 0.5
	var x0: float = -half
	var x1: float = half
	var lowered: bool = interior_lowered if interior else lowered_cells.has(here + into)
	if ExteriorSupport.is_exterior(grid, face) and grid.terrain(here + into) != SimGrid.Terrain.WALL:
		lowered = _opening_lowered(grid, face, lowered_cells)
	if interior:
		x0 -= _corner_reach(grid, face, -right)
		x1 += _corner_reach(grid, face, right)
	return {"origin": origin, "normal": normal, "tangent": tangent, "x0": x0, "x1": x1,
		"height": ShopView.LOWERED_HEIGHT if lowered else ArtScale.WALL_HEIGHT, "inset": inset, "lowered": lowered}


## The header over the fixed doorway follows its nearest supporting shell.
static func _opening_lowered(grid: SimGrid, face: Vector3i, lowered: Dictionary[Vector2i, bool]) -> bool:
	var shell: Vector2i = ExteriorSupport.shell_cell(face)
	var along: Vector2i = WallFaces.along(face)
	for direction: int in [-1, 1]:
		for distance: int in range(1, ItemDef.MAX_WALL_WIDTH + 1):
			var support: Vector2i = shell + along * direction * distance
			if grid.terrain(support) == SimGrid.Terrain.WALL:
				if lowered.has(support):
					return true
				break
	return false


## At the end of an interior face towards `side`: another segment meeting it
## at a right angle on the room's side stops the facing at that slab's face
## (-half a thickness); one on the far side only is wrapped (+half a
## thickness, like the slab's own corner); none leaves the face 0.5 m.
static func _corner_reach(grid: SimGrid, face: Vector3i, side: Vector2i) -> float:
	var here: Vector2i = WallFaces.cell(face)
	var into: Vector2i = WallFaces.step(face)
	# The grid vertex at that end of the face's line (vertex (x, y) is cell (x, y)'s NW corner).
	var corner: Vector2 = Vector2(here) + Vector2(0.5, 0.5) + Vector2(into) * 0.5 + Vector2(side) * 0.5
	var vertex: Vector2i = Vector2i(roundi(corner.x), roundi(corner.y))
	var own: Vector3i = WallFaces.edge(face)
	var room_side: bool = false
	var far_side: bool = false
	for other: Vector3i in SimGrid.edges_at_vertex(vertex):
		if other == own or other.z == own.z or grid.segment(other) == SimGrid.Segment.NONE \
				or not WallRules.is_interior(grid, other):
			continue
		var ends: Array[Vector2i] = SimGrid.edge_vertices(other)
		var far: Vector2i = ends[1] if ends[0] == vertex else ends[0]
		var toward: Vector2i = far - vertex
		if toward == -into:
			room_side = true
		else:
			far_side = true
	if room_side:
		return -HALF_THICKNESS
	return HALF_THICKNESS if far_side else 0.0


func _material(look: FloorFinishes.Finish, previewed: bool) -> ShaderMaterial:
	var style: WallStyleDef = _content.wall_style(look.style) if _content != null else null
	var pattern: int = int(style.pattern) if style != null else 0
	var main: Color = _colour(look.swatch, _wall_colour)
	var accent: Color = _colour(look.accent, main) if not look.accent.is_empty() \
		else auto_accent(pattern, main, _wall_colour)
	var key: String = "%d|%s|%s|%s" % [pattern, main.to_html(), accent.to_html(), previewed]
	if _materials.has(key):
		return _materials[key]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("pattern", pattern)
	material.set_shader_parameter("main_color", main)
	material.set_shader_parameter("accent_color", accent)
	material.set_shader_parameter("preview", previewed)
	material.set_shader_parameter("preview_color", BuildPreview.VALID_COLOR)
	_materials[key] = material
	return material


## The automatic accent: the shop's wall colour above painted panelling, a
## darker shade of the main colour for the other patterns.
static func auto_accent(pattern: int, main: Color, wall: Color) -> Color:
	if pattern == WallStyleDef.Pattern.WAINSCOT:
		return wall
	return Color(main.r * AUTO_ACCENT_SHADE, main.g * AUTO_ACCENT_SHADE, main.b * AUTO_ACCENT_SHADE)


## A swatch's colour; "" (and unknown ids) is `fallback`.
func _colour(swatch_id: StringName, fallback: Color) -> Color:
	if swatch_id.is_empty():
		return fallback
	if swatch_id == _shop_swatch:
		return _wall_colour
	var swatch: SwatchDef = _content.swatch(swatch_id) if _content != null else null
	return swatch.color if swatch != null else fallback


# --- Wall decor ----------------------------------------------------------------

## Where a hung item's wrapper stands: on the floor at the middle of its span,
## turned so its front (-Z) faces the room, pulled in to the face's surface.
static func hung_transform(grid: SimGrid, anchor: Vector3i, width: int) -> Transform3D:
	var into: Vector2i = WallFaces.step(anchor)
	var right: Vector2i = WallFaces.along(anchor)
	var centre: Vector3 = GridMath.cell_to_world(WallFaces.cell(anchor)) \
		+ Vector3(right.x, 0.0, right.y) * (GridMath.CELL_SIZE * float(maxi(width, 1) - 1) * 0.5)
	var interior: bool = grid != null and grid.segment(WallFaces.edge(anchor)) == SimGrid.Segment.WALL
	if interior:
		centre -= Vector3(into.x, 0.0, into.y) * HALF_THICKNESS
	# The wrapper's +Z (its back) points into the wall.
	var basis: Basis = Basis(Vector3.UP, atan2(float(into.x), float(into.y)))
	return Transform3D(basis, centre)


## Exterior wrappers face out; their measured back rests on the actual shell.
## Geometry is translated, never stretched to fit a wall or an opening.
static func exterior_transform(grid: SimGrid, anchor: Vector3i, width: int, box: AABB) -> Transform3D:
	if grid == null:
		return Transform3D.IDENTITY
	var into: Vector2i = WallFaces.step(anchor)
	var right: Vector2i = WallFaces.along(anchor)
	var inward: Vector3 = Vector3(into.x, 0.0, into.y)
	var basis: Basis = Basis(Vector3.UP, atan2(float(into.x), float(into.y)))
	var at: Vector3 = GridMath.cell_to_world(WallFaces.cell(anchor)) + inward * GridMath.CELL_SIZE * 0.5 \
		+ Vector3(right.x, 0.0, right.y) * GridMath.CELL_SIZE * float(maxi(width, 1) - 1) * 0.5
	var bottom: float = HUNG_FALLBACK_HEIGHT
	var outset: float = FACE_GAP
	match ExteriorSupport.band(anchor):
		ExteriorSupport.Band.CANOPY:
			bottom = ArtScale.EXTERIOR_CANOPY_BOTTOM
		ExteriorSupport.Band.HEADER:
			bottom = ArtScale.EXTERIOR_HEADER_BOTTOM
		ExteriorSupport.Band.SILL:
			bottom = maxf(0.0, minf(ArtScale.EXTERIOR_SILL_BOTTOM,
				WallSegmentView.window_opening().position.y - box.size.y - FACE_GAP))
		ExteriorSupport.Band.LIGHTS:
			bottom = ArtScale.EXTERIOR_LIGHTS_BOTTOM
			outset += ArtScale.EXTERIOR_LIGHTS_OUTSET
	at += Vector3.UP * bottom - inward * outset
	return Transform3D(basis, at - basis * Vector3(box.get_center().x, box.position.y, box.end.z))


## Existing wide wall models may occupy one facade face. Fit the whole model
## uniformly before positioning; authored pieces that already fit stay unchanged.
static func fit_exterior(node: ItemVisual, width: int) -> void:
	var box: AABB = node.get_aabb()
	if box.size.x <= 0.0:
		return
	var available: float = GridMath.CELL_SIZE * float(maxi(width, 1))
	var fit: float = minf(1.0, available / box.size.x)
	if fit >= 1.0:
		return
	var part: Node3D = node.prop if node.prop != null else node.fallback
	if part != null:
		part.scale *= fit


## Scales a window item's model down to fit the window opening (WINDOW_FILL).
static func fit_window(node: ItemVisual) -> void:
	var box: AABB = node.get_aabb()
	var opening: Rect2 = WallSegmentView.window_opening()
	if box.size.x <= 0.0 or box.size.y <= 0.0 or opening.size.x <= 0.0:
		return
	var fit: float = minf(1.0, minf(opening.size.x * WINDOW_FILL.x / box.size.x, opening.size.y * WINDOW_FILL.y / box.size.y))
	var part: Node3D = node.prop if node.prop != null else node.fallback
	if part != null:
		part.scale *= fit


## Where a window item's wrapper stands: its front (-Z) to the street, just
## inside the shell's outer face, centred in the opening (`box`: its fitted
## bounds).
static func window_transform(slot: Vector3i, box: AABB) -> Transform3D:
	var into: Vector2i = WallFaces.step(slot)
	var out: Vector3 = Vector3(into.x, 0.0, into.y)
	var opening: Rect2 = WallSegmentView.window_opening()
	var basis: Basis = Basis(Vector3.UP, atan2(-float(into.x), -float(into.y)))
	var at: Vector3 = GridMath.cell_to_world(WallFaces.cell(slot)) + out * (GridMath.CELL_SIZE * 1.5 - WINDOW_GAP) \
		+ Vector3.UP * opening.get_center().y
	var front: Vector3 = Vector3(box.get_center().x, box.get_center().y, box.position.z)
	return Transform3D(basis, at - basis * front)

func _rebuild_items() -> void:
	var wanted: Dictionary[Vector3i, bool] = {}
	if _decor != null and _grid != null:
		for anchor: Vector3i in _decor.anchors():
			wanted[anchor] = true
	for anchor: Vector3i in item_nodes.keys():
		var node: ItemVisual = item_nodes[anchor]
		var hung: WallDecor.Hung = _decor.item(anchor) if _decor != null else null
		if not wanted.has(anchor) or hung == null or node.get_meta(&"def_id") != hung.def_id:
			remove_child(node)
			node.free()
			item_nodes.erase(anchor)
	for anchor: Vector3i in wanted:
		var hung: WallDecor.Hung = _decor.item(anchor)
		var definition: ItemDef = _content.item(hung.def_id) if _content != null else null
		if definition == null:
			continue
		var node: ItemVisual = item_nodes.get(anchor) as ItemVisual
		if node == null:
			node = ItemVisual.create(definition, HUNG_FALLBACK_HEIGHT, _flat(definition.placeholder_color))
			node.name = "Hung_%d_%d_%d" % [anchor.x, anchor.y, anchor.z]
			node.set_meta(&"anchor", anchor)
			node.set_meta(&"def_id", definition.id)
			item_nodes[anchor] = node
			if hung.window:
				fit_window(node)
			elif hung.mount == ItemDef.WallMount.EXTERIOR:
				fit_exterior(node, hung.width)
			add_child(node)
			_add_glow(node, definition, hung.window, hung.mount == ItemDef.WallMount.EXTERIOR)
		if hung.mount == ItemDef.WallMount.EXTERIOR:
			node.transform = exterior_transform(_grid, anchor, hung.width, node.get_aabb())
		else:
			node.transform = window_transform(anchor, node.get_aabb()) if hung.window \
				else hung_transform(_grid, anchor, hung.width)
		node.set_restaurant_name(_restaurant_name)
		if hung.mount == ItemDef.WallMount.EXTERIOR and definition.paintable:
			var swatch: StringName = _hung_preview_swatch if anchor == _hung_preview_anchor else hung.swatch_id
			if swatch.is_empty():
				node.clear_paint()
			else:
				var colour: Color = _colour(swatch, definition.placeholder_color)
				node.apply_paint(colour, _flat(colour))
		if hung.window:
			place_window_glow(node, anchor)
	_sync_item_visibility()


## The soft light of a glowing item, a child of its visual so it hides with
## it (a lowered wall, a held item). Build ghosts get none. A window item's
## stands in the middle of the opening, behind its front.
static func _add_glow(node: ItemVisual, definition: ItemDef, window: bool = false, exterior: bool = false) -> void:
	if definition.glow_color.a <= 0.0:
		return
	var box: AABB = node.get_aabb()
	for mesh: MeshInstance3D in node.rendered_meshes():
		mesh.layers = GLOW_SELF_LAYER
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "Glow"
	light.light_color = Color(definition.glow_color, 1.0)
	light.light_energy = GLOW_ENERGY * definition.glow_color.a
	light.light_specular = 0.0
	light.shadow_enabled = false
	light.omni_range = GLOW_RANGE
	light.omni_attenuation = GLOW_ATTENUATION
	light.light_bake_mode = Light3D.BAKE_DISABLED
	light.light_cull_mask = 0xFFFFF & ~GLOW_SELF_LAYER
	node.add_child(light)
	if window:
		# Placed by place_window_glow once the item stands in its window.
		light.omni_range = WINDOW_GLOW_RANGE
		light.light_energy = WINDOW_GLOW_ENERGY * definition.glow_color.a
		for pool_name: String in ["PoolInside", "PoolOutside"]:
			node.add_child(_glow_pool(pool_name, definition.glow_color))
		return
	# The wrapper's front is -Z; its back (+Z) is on the face.
	var centre: Vector3 = box.get_center() if box.size != Vector3.ZERO else Vector3(0.0, HUNG_FALLBACK_HEIGHT, 0.0)
	light.position = Vector3(centre.x, centre.y, box.position.z - GLOW_OUT)
	if exterior:
		# An outside accent never lights through the thick shell into the room.
		light.omni_range = WINDOW_GLOW_RANGE


## One flat glow square for a window item: a cell-sized quad just above the
## ground, additive and unshaded, fading from its -Z edge (the wall) outward.
static func _glow_pool(pool_name: String, colour: Color) -> MeshInstance3D:
	var gradient: Gradient = Gradient.new()
	var strong: Color = Color(colour.r, colour.g, colour.b) * POOL_STRENGTH * colour.a
	gradient.set_color(0, Color(strong, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 1.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	texture.width = 64
	texture.height = 64
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = texture
	material.disable_receive_shadows = true
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2.ONE * GridMath.CELL_SIZE
	var pool: MeshInstance3D = MeshInstance3D.new()
	pool.name = pool_name
	pool.mesh = plane
	pool.material_override = material
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.layers = GLOW_SELF_LAYER
	return pool


## Puts a window item's glow in place (parent space: the window at `slot`):
## the light halfway through the opening at the item's height, one pool on
## the floor cell inside and one on the ground cell outside the shell.
static func place_window_glow(node: ItemVisual, slot: Vector3i) -> void:
	var light: Node3D = node.get_node_or_null(^"Glow") as Node3D
	if light == null:
		return
	var into: Vector2i = WallFaces.step(slot)
	var out: Vector3 = Vector3(into.x, 0.0, into.y)
	var inside: Vector3 = GridMath.cell_to_world(WallFaces.cell(slot))
	var back: Transform3D = node.transform.affine_inverse()
	var height: float = (node.transform * node.get_aabb()).get_center().y
	light.position = back * (inside + out * GridMath.CELL_SIZE + Vector3.UP * height)
	# Each pool's -Z edge lies on the wall: +Z points away from it.
	var room_side: Basis = Basis(Vector3.UP, atan2(-out.x, -out.z))
	var street_side: Basis = Basis(Vector3.UP, atan2(out.x, out.z))
	var pools: Dictionary[String, Transform3D] = {
		"PoolInside": Transform3D(room_side, inside + Vector3.UP * POOL_LIFT),
		"PoolOutside": Transform3D(street_side, inside + out * GridMath.CELL_SIZE * 2.0 + Vector3.UP * POOL_LIFT),
	}
	for pool_name: String in pools:
		var pool: Node3D = node.get_node_or_null(NodePath(pool_name)) as Node3D
		if pool != null:
			pool.transform = back * pools[pool_name]


## A hung item hides while any wall it covers is drawn lowered, or while it
## is held for a move.
func _sync_item_visibility() -> void:
	for anchor: Vector3i in item_nodes:
		var node: ItemVisual = item_nodes[anchor]
		var hung: WallDecor.Hung = _decor.item(anchor) if _decor != null else null
		node.visible = hung != null and anchor != _hidden_anchor and not is_hung_lowered(anchor, hung.width)


func is_hung_lowered(anchor: Vector3i, width: int) -> bool:
	for face: Vector3i in WallFaces.span(anchor, width):
		if bool(face_frame(_grid, face, _interior_lowered, _lowered_cells)["lowered"]):
			return true
	return false


## The anchor of the visible hung item nearest along the ray, with its
## distance ({} for none).
func item_hit(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	var best: Dictionary = {}
	for anchor: Vector3i in item_nodes:
		var node: ItemVisual = item_nodes[anchor]
		if not node.is_visible_in_tree():
			continue
		var hung: WallDecor.Hung = _decor.item(anchor) if _decor != null else null
		var distance: float = -1.0
		if hung != null and hung.mount == ItemDef.WallMount.EXTERIOR:
			for mesh: MeshInstance3D in node.rendered_meshes():
				if mesh.mesh == null or not mesh.is_visible_in_tree():
					continue
				var hit: float = ShopView.ray_box_distance(ray_origin, ray_direction, mesh.global_transform * mesh.get_aabb())
				if hit >= 0.0 and (distance < 0.0 or hit < distance):
					distance = hit
		else:
			distance = ShopView.ray_box_distance(ray_origin, ray_direction, node.global_transform * node.get_aabb())
		if distance >= 0.0 and (best.is_empty() or distance < float(best["distance"])):
			best = {"anchor": anchor, "distance": distance}
	return best


func _flat(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material
