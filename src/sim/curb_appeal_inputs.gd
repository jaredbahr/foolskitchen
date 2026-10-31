class_name CurbAppealInputs
extends RefCounted
## Read-only bridge from actual supported street mounts to detached model rows.
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
	return rows


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
