extends RefCounted
## Explicit, unsaved street-front review using the production morning edits.
## One daylight frame includes every new mounting band, a live purchased name,
## the existing OPEN model outside, a paid finish and the real owner for scale.

const NAME: String = "Little Lantern"
const AWNING_SWATCH: StringName = &"slate_blue"
const CAPTURE_FRAME: int = 60


## Keep this fixture separate from all existing captures and service options.
static func options(arguments: PackedStringArray) -> Dictionary:
	var enabled: bool = false
	for argument: String in arguments:
		if argument.begins_with("--street-front-review"):
			if argument != "--street-front-review" or enabled:
				return {"enabled": false, "error": "Use --street-front-review once without a value"}
			enabled = true
	if not enabled:
		return {"enabled": false, "error": ""}
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in arguments:
		if argument == "--street-front-review" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=%d" % CAPTURE_FRAME:
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		else:
			return {"enabled": false, "error": "Street-front review needs only --speed=0 --frames=60"}
	if speeds != 1 or frames != 1 or scenes > 1:
		return {"enabled": false, "error": "Street-front review needs one --speed=0 and --frames=60"}
	return {"enabled": true, "error": ""}


static func prepare(main: Node, root: Window) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	if world == null or editor == null or world.clock.phase != SimClock.Phase.MORNING \
			or bool(main.get("use_saves")) or not editor.decor.anchors().is_empty():
		return {"error": "Street-front review needs a fresh, unsaved morning"}
	var pieces: Array[Dictionary] = _pieces(world.grid)
	if pieces.is_empty():
		return {"error": "Street-front review needs the starter's door and adjoining window"}
	root.get_node("Economy").call("add_cash", 2000, Ledger.OTHER)
	editor.set_owner_level(4)
	var faces: Array[Vector3i] = _finish_faces(world.grid)
	if not bool(main.call("shop_wall_finishes", editor.wall_lay_changes(faces, &"brick", &"terracotta", &"cream"))):
		return {"error": "The outside finish was refused: " + editor.last_check.why}
	for piece: Dictionary in pieces:
		if not bool(main.call("shop_hang", piece["id"], piece["anchor"], piece["swatch"])):
			return {"error": "Hanging %s was refused: %s" % [piece["id"], editor.last_check.why]}
	if not bool(main.call("menu_set_restaurant_name", NAME)):
		return {"error": "The real menu rename was refused"}
	var owner: OwnerAgent = (main.get("sim") as RestaurantSim).owner_agent()
	if owner == null:
		return {"error": "The real owner is missing from the street-front review"}
	# An existing reachable entry, never a new person or an altered model.
	owner.cell = world.grid.entries()[-1]
	owner.path.clear()
	owner.move_progress = 0.0
	return {"error": "", "fixture": "Seed 1; synthetic review cash/level; production purchases and rename; no saves",
		"restaurant_name": NAME, "pieces": pieces.size(), "finish_faces": faces.size()}


static func focus(main: Node) -> void:
	var view: ShopView = main.get_node("ShopView") as ShopView
	view.set_wall_mode(ShopView.WallMode.UP)
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	var world: SimWorld = main.get("world") as SimWorld
	var into: Vector2i = -WallRules.street_side(world.grid)
	var along: Vector2i = WallFaces.DIRS[posmod(WallFaces.DIRS.find(into) + 1, 4)]
	var doors: Array[Vector2i] = ExteriorSupport.door_cells(world.grid)
	var middle: Vector2 = Vector2.ZERO
	for cell: Vector2i in doors:
		middle += Vector2(cell)
	middle /= float(doors.size())
	var target: Vector3 = Vector3((middle.x + 0.5) * GridMath.CELL_SIZE, 0.65,
		(middle.y + 0.5) * GridMath.CELL_SIZE)
	var outward: Vector3 = Vector3(-into.x, 0.0, -into.y)
	var right: Vector3 = Vector3(along.x, 0.0, along.y)
	camera.global_position = target + outward * 7.0 + right * 2.0 + Vector3.UP * 2.8
	camera.look_at(target)
	camera.size = 4.5


static func evidence(main: Node, root: Window) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var view: ShopView = main.get_node("ShopView") as ShopView
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	var content: ContentDB = main.get("content") as ContentDB
	var pieces: Array[Dictionary] = _pieces(world.grid)
	var items: Array[Dictionary] = []
	var sign_text: String = ""
	var sign_visible: bool = false
	var all_visible: bool = true
	for piece: Dictionary in pieces:
		var anchor: Vector3i = piece["anchor"]
		var hung: WallDecor.Hung = editor.decor.item(anchor)
		var visual: ItemVisual = view.wall_finish_view.item_nodes.get(anchor) as ItemVisual
		var native_model: bool = visual != null and visual.prop != null and visual.fallback == null
		var visible: bool = native_model and visual.is_visible_in_tree() \
			and _fully_in_view(visual, camera, root.get_visible_rect())
		var correct: bool = hung != null and hung.def_id == piece["id"] \
			and hung.mount == ItemDef.WallMount.EXTERIOR and hung.swatch_id == piece["swatch"]
		var tint_correct: bool = true
		if piece["swatch"] != &"":
			var material: BaseMaterial3D = visual.primary_body_material() if visual != null else null
			tint_correct = material != null and material.albedo_color.is_equal_approx(content.swatch(piece["swatch"]).color)
		var glow_correct: bool = true
		if piece["id"] in [&"neon_open_sign", &"string_lights_4"]:
			var glow: OmniLight3D = visual.get_node_or_null("Glow") as OmniLight3D if visual != null else null
			glow_correct = glow != null and glow.is_visible_in_tree() and glow.light_energy > 0.0
		all_visible = all_visible and visible and correct and tint_correct and glow_correct
		items.append({"id": String(piece["id"]), "anchor": [anchor.x, anchor.y, anchor.z],
			"visible": visible, "native_model": native_model, "correct_instance": correct,
			"drawn_tint_correct": tint_correct, "glow_requirement_met": glow_correct,
			"swatch": String(hung.swatch_id) if hung != null else "",
			"bounds": str(visual.global_transform * visual.get_aabb()) if visual != null else ""})
		if piece["id"] == &"shop_name_sign" and visual != null:
			var label: Label3D = visual.restaurant_name_label
			if label != null:
				sign_text = label.text
				sign_visible = label.is_visible_in_tree() and camera.is_position_in_frustum(label.global_position)
	var owner: OwnerAgent = (main.get("sim") as RestaurantSim).owner_agent()
	var person: PersonView = view.agent_nodes.get(owner.id) as PersonView if owner != null else null
	var person_pixels: float = 0.0
	if person != null and person.is_visible_in_tree():
		var head: Vector3 = person.to_global(person.head_anchor_position())
		if camera.is_position_in_frustum(head) and camera.is_position_in_frustum(person.global_position):
			person_pixels = camera.unproject_position(person.global_position).distance_to(camera.unproject_position(head))
	var finishes: int = 0
	for face: Vector3i in _finish_faces(world.grid):
		var finish: FloorFinishes.Finish = view.wall_finish_view.drawn_finish(face)
		if finish.style == &"brick" and finish.swatch == &"terracotta" and finish.accent == &"cream" \
				and view.wall_finish_view.finished_faces().has(face):
			finishes += 1
	return {"items": items, "all_visible": all_visible, "stored_items": editor.decor.count(),
		"outside_finishes": finishes, "restaurant_name": (main.get("menu_settings") as MenuSettings).restaurant_name(),
		"purchased_sign_text": sign_text, "purchased_sign_visible": sign_visible,
		"owner_height_pixels": person_pixels, "wall_mode": int(view.wall_mode),
		"phase": int(world.clock.phase), "inside_decor_vibe_empty": editor.decor_vibe_items().is_empty()}


static func valid(state: Dictionary) -> bool:
	return state.get("all_visible") == true and state.get("stored_items") == 5 \
		and state.get("outside_finishes") == 4 and state.get("restaurant_name") == NAME \
		and state.get("purchased_sign_text") == NAME and state.get("purchased_sign_visible") == true \
		and float(state.get("owner_height_pixels", 0.0)) >= 60.0 \
		and state.get("wall_mode") == ShopView.WallMode.UP \
		and state.get("phase") == SimClock.Phase.MORNING and state.get("inside_decor_vibe_empty") == true


static func _pieces(grid: SimGrid) -> Array[Dictionary]:
	var doors: Array[Vector2i] = ExteriorSupport.door_cells(grid)
	var into: Vector2i = -WallRules.street_side(grid)
	var dir: int = WallFaces.DIRS.find(into)
	if doors.size() != 2 or dir < 0:
		return []
	var along: Vector2i = WallFaces.DIRS[posmod(dir + 1, 4)]
	var first: Vector2i = doors[0]
	for cell: Vector2i in doors:
		if cell.x * along.x + cell.y * along.y < first.x * along.x + first.y * along.y:
			first = cell
	var window: Vector2i = first - along
	if not ExteriorSupport.window_cells(grid).has(window):
		return []
	return [
		{"id": &"street_awning_4", "anchor": _key(window, into, ExteriorSupport.Band.CANOPY), "swatch": AWNING_SWATCH},
		{"id": &"flower_window_box", "anchor": _key(first + along * doors.size(), into, ExteriorSupport.Band.SILL), "swatch": &""},
		{"id": &"shop_name_sign", "anchor": _key(first, into, ExteriorSupport.Band.HEADER), "swatch": &""},
		{"id": &"string_lights_4", "anchor": _key(first + along * 3, into, ExteriorSupport.Band.LIGHTS), "swatch": &""},
		{"id": &"neon_open_sign", "anchor": _key(window - along, into, ExteriorSupport.Band.BODY), "swatch": &""},
	]


static func _finish_faces(grid: SimGrid) -> Array[Vector3i]:
	var pieces: Array[Dictionary] = _pieces(grid)
	var result: Array[Vector3i] = []
	if pieces.is_empty():
		return result
	var canopy: Vector3i = pieces[0]["anchor"]
	var along: Vector2i = WallFaces.along(canopy)
	for index: int in range(1, 5):
		result.append(ExteriorSupport.base_face(Vector3i(canopy.x - along.x * index,
			canopy.y - along.y * index, canopy.z)))
	return result


static func _key(shell: Vector2i, into: Vector2i, band: int) -> Vector3i:
	return ExteriorSupport.key_for(WallFaces.make(shell - into, WallFaces.DIRS.find(into)), band)


static func _fully_in_view(visual: ItemVisual, camera: Camera3D, viewport: Rect2) -> bool:
	var bounds: AABB = visual.global_transform * visual.get_aabb()
	var visible: Rect2 = Rect2(Vector2(0.0, 110.0), viewport.size - Vector2(0.0, 110.0))
	for index: int in 8:
		var point: Vector3 = bounds.position + Vector3(bounds.size.x if (index & 1) != 0 else 0.0,
			bounds.size.y if (index & 2) != 0 else 0.0, bounds.size.z if (index & 4) != 0 else 0.0)
		if not camera.is_position_in_frustum(point) or not visible.has_point(camera.unproject_position(point)):
			return false
	return true
