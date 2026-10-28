extends RefCounted
## Wall finishes and wall decor review fixture (D26), shared by
## `tools/screenshot.sh --walls-review` and hand-run review shots. Real
## morning edits through Main's own commands (nothing saved): an interior wall
## across the dining room, subway tiles on the kitchen's back wall, painted
## panelling and brick in the dining room, stripes on one side of the new wall,
## and four hung items. The owner level is raised to 4 on the editor only.
## Frame 12 shows the default Cutaway; from WALL_UP_FRAME the walls are up and
## Build > Wall finish holds a brick drag along the dining room's back wall.

## Faces: Vector3i(x, y, dir), dir 0 north, 1 east, 2 south, 3 west.
const WALL_X: int = 9
const WALL_ROWS: Vector2i = Vector2i(5, 7)
## [style, main colour, accent, faces] put up in this order.
const FINISHES: Array[Array] = [
	[&"subway_tile", &"cream", &"", [Vector2i(1, 1), Vector2i(12, 1)], 0],
	[&"wainscot", &"sage", &"", [Vector2i(1, 5), Vector2i(1, 9)], 3],
	[&"stripes", &"butter", &"cream", [Vector2i(8, 5), Vector2i(8, 7)], 1],
	[&"brick", &"brick", &"cream", [Vector2i(9, 5), Vector2i(9, 7)], 3],
	[&"brick", &"terracotta", &"cream", [Vector2i(12, 5), Vector2i(12, 9)], 1],
]
const HUNG: Array[Array] = [
	[&"wall_art_sunrise", Vector3i(1, 7, 3)],
	[&"neon_open_sign", Vector3i(1, 9, 3)],
	[&"menu_board", Vector3i(2, 1, 0)],
	[&"wall_art_peaks", Vector3i(9, 6, 3)],
]
const WALL_UP_FRAME: int = 20
## The drag along the dining room's back wall (both ends' faces turn north).
const DRAG_START: Vector3i = Vector3i(1, 5, 0)
const DRAG_END: Vector3i = Vector3i(3, 5, 0)
const HANG_FRAME: int = 40
## Hand-run: from DOWN_FRAME the tool is put away and the walls are Down.
const DOWN_FRAME: int = 60
const HANG_FACE: Vector3i = Vector3i(8, 1, 0)


static func prepare(main: Node, root: Window) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	if world == null or editor == null or world.clock.phase != SimClock.Phase.MORNING \
			or not main.has_method("shop_wall_finishes") or not main.has_method("shop_hang"):
		return {"error": "walls review needs Main's morning wall commands"}
	root.get_node("Economy").call("add_cash", 2000, Ledger.OTHER)
	editor.set_owner_level(4)
	var wall: Dictionary[Vector3i, int] = {}
	for y: int in range(WALL_ROWS.x, WALL_ROWS.y + 1):
		wall[Vector3i(WALL_X, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.WALL
	if not bool(main.call("shop_walls", wall)):
		return {"error": "the interior wall was refused: " + editor.last_check.why}
	for finish: Array in FINISHES:
		var faces: Array[Vector3i] = []
		var ends: Array = finish[3]
		for y: int in range((ends[0] as Vector2i).y, (ends[1] as Vector2i).y + 1):
			for x: int in range((ends[0] as Vector2i).x, (ends[1] as Vector2i).x + 1):
				faces.append(Vector3i(x, y, int(finish[4])))
		var changes: Dictionary[Vector3i, FloorFinishes.Finish] = editor.wall_lay_changes(faces, finish[0], finish[1], finish[2])
		if not bool(main.call("shop_wall_finishes", changes)):
			return {"error": "putting up %s was refused: %s" % [finish[0], editor.last_check.why]}
	for hung: Array in HUNG:
		if not bool(main.call("shop_hang", hung[0], hung[1])):
			return {"error": "hanging %s was refused: %s" % [hung[0], editor.last_check.why]}
	return {"error": "", "stored_faces": editor.walls.count(), "hung": editor.decor.count()}


## Walls Up, and Build > Wall finish holding a striped wallpaper drag.
static func begin_drag(main: Node, root: Window) -> Dictionary:
	var view: ShopView = main.get_node_or_null("ShopView") as ShopView
	var catalogue: BuildCatalogue = main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var mode: BuildMode = main.get("build_mode") as BuildMode
	if view == null or catalogue == null or mode == null or not bool(main.call("set_build_active", true)):
		return {"error": "walls review could not enter Build mode"}
	view.set_wall_mode(ShopView.WallMode.UP)
	main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.WALL_FINISH)
	var card: Button = catalogue.wall_style_buttons.get(&"stripes") as Button
	if card == null:
		return {"error": "walls review cannot find the Striped wallpaper card"}
	card.pressed.emit()
	if mode.state != BuildMode.State.WALL_FINISH:
		return {"error": "the Striped wallpaper card did not start the Wall finish tool"}
	var camera: Camera3D = main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	mode.wall_finish_pointer(DRAG_START)
	if not mode.wall_finish_press(DRAG_START):
		return {"error": "the Wall finish tool refused the drag"}
	# The pointer rests on the end face, a little up the wall.
	var pointer: Vector2 = camera.unproject_position(face_point(DRAG_END))
	root.warp_mouse(pointer)
	main.call("update_build_pointer", pointer)
	return {"error": "", "pointer": pointer}


## Buy > Decor > Wall decor holding a chalk menu board on a free wall (a
## hand-run third frame after HANG_FRAME; the CI capture stops before it).
static func begin_hang(main: Node, root: Window) -> Dictionary:
	var camera: Camera3D = main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var catalogue: BuildCatalogue = main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var mode: BuildMode = main.get("build_mode") as BuildMode
	mode.cancel_ghost()
	main.call("_on_catalogue_mode_requested", BuildCatalogue.BUY)
	catalogue.set_category(&"decor")
	catalogue.set_group(&"wall_decor")
	var tile: Button = catalogue.item_buttons.get(&"menu_board") as Button
	if tile == null:
		return {"error": "walls review cannot find the menu board tile"}
	tile.pressed.emit()
	if mode.state != BuildMode.State.HANG:
		return {"error": "the menu board tile did not start hanging"}
	var pointer: Vector2 = camera.unproject_position(face_point(HANG_FACE))
	root.warp_mouse(pointer)
	main.call("update_build_pointer", pointer)
	return {"error": "", "pointer": pointer}


## Walls Down with nothing held: the stubs keep their finishes, hung items hide.
static func walls_down(main: Node) -> Dictionary:
	var view: ShopView = main.get_node_or_null("ShopView") as ShopView
	(main.get("build_mode") as BuildMode).cancel_ghost()
	view.set_wall_mode(ShopView.WallMode.DOWN)
	return {"error": ""}


## A point on a face's wall, 0.7 m up, in world space.
static func face_point(face: Vector3i) -> Vector3:
	var into: Vector2i = WallFaces.step(face)
	return GridMath.cell_to_world(WallFaces.cell(face)) + Vector3(into.x, 0.0, into.y) * 0.24 + Vector3.UP * 0.7


## What the frame shows: facings drawn, hung items shown, and the tool state.
static func evidence(main: Node) -> Dictionary:
	var view: ShopView = main.get_node_or_null("ShopView") as ShopView
	var mode: BuildMode = main.get("build_mode") as BuildMode
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	if view == null or mode == null or editor == null or view.wall_finish_view == null:
		return {}
	var drawn: int = 0
	for node: MeshInstance3D in view.wall_finish_view.finish_nodes():
		drawn += (node.get_meta(&"faces", []) as Array).size()
	var shown: int = 0
	for anchor: Vector3i in view.wall_finish_view.item_nodes:
		if view.wall_finish_view.item_nodes[anchor].visible:
			shown += 1
	return {"stored_faces": editor.walls.count(), "drawn_faces": drawn, "hung": editor.decor.count(),
		"hung_shown": shown, "wall_mode": int(view.wall_mode), "state": int(mode.state),
		"dragging": mode.wall_face_dragging, "check_ok": mode.current_check.ok,
		"proposal": mode.current_check.wall_finishes.size(), "preview_faces": view.wall_finish_view.preview_faces().size(),
		"summary": mode.wall_finish_summary()}
