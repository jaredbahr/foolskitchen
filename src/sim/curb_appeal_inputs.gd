class_name CurbAppealInputs
extends RefCounted
## Read-only bridge from supported street mounts and patio furniture to model rows.
## The authored tuning maps approved content to families, independently of
## swatch and occupied width. Reading it never changes the resource.


static func collect(grid: SimGrid, finishes: WallFinishes, decor: WallDecor, content: ContentDB,
		tuning: CurbAppealTuning) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if grid == null or finishes == null or decor == null or content == null or grid.entries().is_empty() \
			or tuning == null or not tuning.is_valid():
		return rows
	for face: Vector3i in finishes.faces():
		if not ExteriorSupport.finish_problem(grid, face).is_empty():
			continue
		var finish: FloorFinishes.Finish = finishes.finish(face)
		var style: WallStyleDef = content.wall_style(finish.style)
		## Even explicitly recoloured plain paint is the neutral starting front.
		if style == null or style.pattern == WallStyleDef.Pattern.PAINT:
			continue
		rows.append({"category": &"finish", "id": _id("finish", face)})
	## Count anchors, not covered faces: a four-wide awning is still one object.
	for anchor: Vector3i in decor.anchors():
		var hung: WallDecor.Hung = decor.item(anchor)
		if hung == null or not tuning.item_categories.has(hung.def_id):
			continue
		var definition: ItemDef = content.item(hung.def_id)
		if definition == null or not definition.hangs_on_wall() or not definition.placement_layer_valid() \
				or hung.width != definition.footprint.x:
			continue
		if not _supported_front(grid, hung, definition):
			continue
		rows.append({"category": tuning.item_categories[hung.def_id], "id": _id("decor", anchor)})
	## Tables and waiting benches share one family. Attached or separate chairs
	## never multiply a table's points; rain closes service, not its visible front.
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or not tuning.item_categories.has(definition.id) \
				or tuning.item_categories[definition.id] != &"patio" \
				or content.item(definition.id) != definition or not _supported_patio(grid, placed, definition):
			continue
		rows.append({"category": &"patio", "id": "patio:%d" % placed.id})
	return rows


static func _supported_patio(grid: SimGrid, placed: PlacedItem, definition: ItemDef) -> bool:
	if placed.removed or placed.placement_layer != ItemDef.PlacementLayer.NORMAL \
			or definition.placement_layer != ItemDef.PlacementLayer.NORMAL or not definition.outdoor_only \
			or (definition.category != ItemDef.Category.TABLE and definition.category != ItemDef.Category.WAITING) \
			or placed.cells.is_empty():
		return false
	for cells: Array[Vector2i] in [placed.cells, placed.work_cells, placed.seat_cells]:
		for cell: Vector2i in cells:
			if not grid.is_outdoor_floor(cell):
				return false
	## The dining projection drops blocked seats. Their authored use cells must
	## still have patio underneath, even when absent from that live projection.
	for authored: Vector2i in definition.work_cells + definition.seat_cells:
		var cell: Vector2i = placed.origin + GridMath.rotate_cell(authored, definition.footprint, placed.quarter_turns)
		if not grid.is_outdoor_floor(cell):
			return false
	return true


static func _supported_front(grid: SimGrid, hung: WallDecor.Hung, definition: ItemDef) -> bool:
	if hung.mount == ItemDef.WallMount.EXTERIOR:
		return (definition.wall_mount == ItemDef.WallMount.EXTERIOR or definition.allow_exterior) \
			and ExteriorSupport.band(hung.anchor) == definition.exterior_band \
			and ExteriorSupport.span_problem(grid, hung.anchor, hung.width).is_empty()
	if hung.mount == ItemDef.WallMount.WINDOW:
		return definition.hangs_in_window() and hung.width == 1 \
			and WallFaces.window_problem(grid, hung.anchor).is_empty() \
			and WallFaces.step(hung.anchor) == WallRules.street_side(grid)
	return false


static func _id(kind: String, face: Vector3i) -> String:
	return "%s:%d:%d:%d" % [kind, face.x, face.y, face.z]
