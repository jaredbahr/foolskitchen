class_name ThinDividers
extends RefCounted
## Pure migration of authored full-cell interior walls. Authored legacy rows
## supply provenance because older shop snapshots never stored terrain.

const CONVERTED: String = "Replaced thick interior dividers with thin walls."
const KEPT: String = "Some interior walls stayed thick to protect their existing fittings."
const REFUNDED: String = "Refunded wall finishes or decorations that no longer had a wall."
const INVALID: String = "Invalid saved interior divider terrain"
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


## Normalize the base rows BEFORE deriving the footprint, so subsequent Expand
## edits preserve both recovered floor and the cells kept thick for a frame.
static func prepare(data: Dictionary, template: ShopLayout, errors: Array[String]) -> ShopLayout:
	var layout: ShopLayout = template.duplicate() as ShopLayout
	var legacy: PackedStringArray = template.legacy_rows if not template.legacy_rows.is_empty() else template.rows
	if legacy.size() != template.rows.size():
		errors.append(INVALID)
		return null
	for y: int in legacy.size():
		if legacy[y].length() != template.rows[y].length():
			errors.append(INVALID)
			return null
	layout.legacy_rows = legacy.duplicate()
	layout.rows = legacy.duplicate()
	layout.thin_cells = []
	layout.thick_cells = []
	if int(data["version"]) < 8:
		return layout
	var allowed: Array[Vector2i] = ShopFootprint.from_layout(layout).interior_wall_cells()
	layout.rows = template.rows.duplicate()
	var used: Dictionary[Vector2i, bool] = {}
	if not _decode_cells(data.get("thin_cells", []), allowed, used, layout.thin_cells) \
			or not _decode_cells(data.get("thick_cells", []), allowed, used, layout.thick_cells):
		errors.append(INVALID)
		return null
	for cell: Vector2i in layout.thin_cells:
		_set_row(layout, cell, ".")
	for cell: Vector2i in layout.thick_cells:
		_set_row(layout, cell, "#")
	return layout


static func _decode_cells(value: Variant, allowed: Array[Vector2i], used: Dictionary[Vector2i, bool], out: Array[Vector2i]) -> bool:
	if not value is Array or (value as Array).size() > allowed.size():
		return false
	for entry: Variant in value:
		if not entry is Array or (entry as Array).size() != 2:
			return false
		var row: Array = entry
		for part: Variant in row:
			if not (part is int or part is float) or not is_finite(float(part)) \
					or float(part) != float(int(part)) or absf(float(part)) > 100000.0:
				return false
		var cell: Vector2i = Vector2i(int(row[0]), int(row[1]))
		if not allowed.has(cell) or used.has(cell):
			return false
		used[cell] = true
		out.append(cell)
	return true


static func rows(cells: Array[Vector2i]) -> Array[Array]:
	var cell_set: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		cell_set[cell] = true
	var out: Array[Array] = []
	for cell: Vector2i in ShopFootprint.sorted(cell_set):
		out.append([cell.x, cell.y])
	return out


## grid is the decoder's isolated staged grid, never the live world. Frames
## keep enough of their original thick support; no furniture is relocated.
static func convert(layout: ShopLayout, grid: SimGrid, content: ContentDB) -> void:
	var candidates: Array[Vector2i] = ShopFootprint.from_layout(layout).interior_wall_cells()
	if candidates.is_empty():
		return
	var before: SimGrid = WallRules.walls_only(grid)
	var converted: Dictionary[Vector2i, bool] = {}
	var rooms: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in candidates:
		var kind: int = _bordering_room(before, cell, candidates)
		if kind >= 0:
			converted[cell] = true
			rooms[cell] = kind
	var after: SimGrid = _proposal(before, converted, rooms)
	# Removing a full-cell support can orphan a legal interior window. Restore
	# a supporting original cell, then rederive boundary walls; this terminates
	# after at most one pass per candidate and never deletes the old frame.
	for _attempt: int in candidates.size():
		var broken: Array[Vector3i] = WallRules.orphan_openings(after)
		if broken.is_empty():
			break
		var restored: bool = false
		for edge: Vector3i in broken:
			var along: Vector3i = Vector3i(0, 1, 0) if edge.z == SimGrid.EDGE_WEST else Vector3i(1, 0, 0)
			var support: Dictionary[Vector2i, bool] = {}
			for neighbour: Vector3i in [edge, edge - along, edge + along]:
				for cell: Vector2i in SimGrid.edge_cells(neighbour):
					if converted.has(cell) and before.terrain(cell) == SimGrid.Terrain.WALL:
						support[cell] = true
			var ordered: Array[Vector2i] = ShopFootprint.sorted(support)
			if not ordered.is_empty():
				converted.erase(ordered[0])
				restored = true
		if not restored:
			converted.clear()
			break
		after = _proposal(before, converted, rooms)
	after = _proposal(before, converted, rooms)
	var terrain: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in candidates:
		terrain[cell] = SimGrid.Terrain.FLOOR if converted.has(cell) else SimGrid.Terrain.WALL
	grid.set_terrains(terrain)
	_replace_segments(grid, _segments(after))
	_replace_rooms(grid, after.rooms())
	# Preserve the old shop if any additional geometry rule would be broken.
	if not WallRules.layout_problem(grid).is_empty():
		converted.clear()
		for cell: Vector2i in candidates:
			terrain[cell] = SimGrid.Terrain.WALL
		grid.set_terrains(terrain)
		_replace_segments(grid, _segments(before))
		_replace_rooms(grid, before.rooms())
	layout.thin_cells.clear()
	layout.thick_cells.clear()
	for cell: Vector2i in candidates:
		if converted.has(cell):
			layout.thin_cells.append(cell)
			_set_row(layout, cell, ".")
		else:
			layout.thick_cells.append(cell)
			_set_row(layout, cell, "#")
	layout.room_cells = grid.rooms()
	layout.wall_segments.clear()
	for edge: Vector3i in grid.segment_edges():
		var definition: WallKindDef = content.wall_kind_for(grid.segment(edge))
		if definition != null:
			layout.wall_segments[edge] = definition.id
	_relocate_faces(layout, before, grid, converted, content)
	if not converted.is_empty():
		layout.load_notes.append(CONVERTED)
	if not layout.thick_cells.is_empty():
		layout.load_notes.append(KEPT)
	if layout.load_refund > 0:
		layout.load_notes.append(REFUNDED)


static func _proposal(before: SimGrid, converted: Dictionary[Vector2i, bool], rooms: Dictionary[Vector2i, int]) -> SimGrid:
	var after: SimGrid = WallRules.walls_only(before)
	for cell: Vector2i in converted:
		after.set_terrain(cell, SimGrid.Terrain.FLOOR)
	var painted: Dictionary[Vector2i, int] = before.rooms()
	for cell: Vector2i in converted:
		painted[cell] = rooms[cell]
	after.set_rooms(painted)
	for cell: Vector2i in converted:
		for side: Vector2i in SIDES:
			var other: Vector2i = cell + side
			var edge: Vector3i = SimGrid.edge_between(cell, other)
			if after.terrain(other) == SimGrid.Terrain.FLOOR and after.room(cell) != after.room(other) \
					and after.segment(edge) == SimGrid.Segment.NONE:
				after.set_segment(edge, SimGrid.Segment.WALL)
	return after


static func _bordering_room(grid: SimGrid, start: Vector2i, candidates: Array[Vector2i]) -> int:
	var seen: Dictionary[Vector2i, bool] = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		var border: Dictionary[Vector2i, bool] = {}
		for cell: Vector2i in frontier:
			for side: Vector2i in SIDES:
				var other: Vector2i = cell + side
				if grid.terrain(other) == SimGrid.Terrain.FLOOR:
					border[other] = true
				elif candidates.has(other) and not seen.has(other):
					seen[other] = true
					next.append(other)
		if not border.is_empty():
			var best: int = -1
			for cell: Vector2i in ShopFootprint.sorted(border):
				var kind: int = grid.room(cell)
				if best < 0 or _room_rank(kind) < _room_rank(best):
					best = kind
			return best
		frontier = next
	return -1


static func _room_rank(kind: int) -> int:
	return 3 if kind == SimGrid.Room.DINING else kind - 1


static func _segments(grid: SimGrid) -> Dictionary[Vector3i, int]:
	var out: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in grid.segment_edges():
		out[edge] = grid.segment(edge)
	return out


static func _replace_segments(grid: SimGrid, wanted: Dictionary[Vector3i, int]) -> void:
	var changes: Dictionary[Vector3i, int] = wanted.duplicate()
	for edge: Vector3i in grid.segment_edges():
		if not wanted.has(edge):
			changes[edge] = SimGrid.Segment.NONE
	grid.set_segments(changes)


static func _replace_rooms(grid: SimGrid, wanted: Dictionary[Vector2i, int]) -> void:
	var changes: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in grid.rooms():
		changes[cell] = SimGrid.Room.DINING
	changes.merge(wanted, true)
	grid.set_rooms(changes)


static func _set_row(layout: ShopLayout, cell: Vector2i, value: String) -> void:
	var row: String = layout.rows[cell.y]
	layout.rows[cell.y] = row.substr(0, cell.x) + value + row.substr(cell.x + 1)


static func _face(before: SimGrid, after: SimGrid, old: Vector3i, converted: Dictionary[Vector2i, bool]) -> Vector3i:
	var room: int = before.room(WallFaces.cell(old))
	if WallFaces.is_face(after, old) and after.room(WallFaces.cell(old)) == room:
		return old
	var here: Vector2i = WallFaces.cell(old)
	for _distance: int in maxi(before.size.x, before.size.y):
		here += WallFaces.step(old)
		if not converted.has(here) or after.room(here) != room:
			break
		var face: Vector3i = WallFaces.make(here, old.z)
		if WallFaces.kind(after, face) == WallFaces.Kind.INTERIOR:
			return face
	return WallFaces.NO_FACE


static func _relocate_faces(layout: ShopLayout, before: SimGrid, after: SimGrid,
		converted: Dictionary[Vector2i, bool], content: ContentDB) -> void:
	var finishes: Dictionary[Vector3i, PackedStringArray] = layout.wall_finishes.duplicate()
	var items: Dictionary[Vector3i, StringName] = layout.wall_items.duplicate()
	layout.wall_finishes.clear()
	layout.wall_items.clear()
	var faces: Array[Vector3i] = []
	faces.assign(finishes.keys())
	WallFaces.sort(faces)
	# Unchanged faces keep priority: relocation never overwrites another look.
	for moved: bool in [false, true]:
		for old: Vector3i in faces:
			var target: Vector3i = _face(before, after, old, converted)
			if (target != old) != moved:
				continue
			if target != WallFaces.NO_FACE and not layout.wall_finishes.has(target):
				layout.wall_finishes[target] = finishes[old]
			else:
				var style: WallStyleDef = content.wall_style(StringName(finishes[old][0]))
				layout.load_refund += floori(style.price / 2.0) if style != null else 0
	var anchors: Array[Vector3i] = []
	anchors.assign(items.keys())
	WallFaces.sort(anchors)
	var staged: WallDecor = WallDecor.new()
	for moved: bool in [false, true]:
		for old: Vector3i in anchors:
			var definition: ItemDef = content.item(items[old])
			if definition == null:
				continue
			var target: Vector3i = old if definition.hangs_in_window() and WallFaces.is_window(after, old) \
				else _face(before, after, old, converted)
			if (target != old) != moved:
				continue
			var valid: bool = target != WallFaces.NO_FACE and staged.problem(after, definition, target).is_empty()
			if valid and not definition.hangs_in_window():
				var old_span: Array[Vector3i] = WallFaces.span(old, definition.footprint.x)
				var new_span: Array[Vector3i] = WallFaces.span(target, definition.footprint.x)
				for index: int in old_span.size():
					if _face(before, after, old_span[index], converted) != new_span[index]:
						valid = false
			if valid:
				staged.add(definition.id, target, definition.footprint.x, definition.hangs_in_window())
				layout.wall_items[target] = definition.id
			else:
				# Same half-price, rounded-down rule as ShopEditor.sale_refund.
				layout.load_refund += floori(definition.price / 2.0)
