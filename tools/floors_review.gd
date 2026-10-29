extends RefCounted
## Floor types review fixture (D25), shared by `tools/screenshot.sh
## --floors-review` and hand-run review shots. Real morning edits through
## Main's own commands (nothing saved): a back door in the kitchen, small tiles
## over the kitchen, narrow planks, herringbone, checker, hex, terracotta, terrazzo, concrete and carpet in the dining
## room, so thresholds, both doorways and standing staff are in view. The
## owner level is raised to 5 on the editor only, so every type can be laid while
## the catalogue still shows it locked for this level-1 owner.

const BACK_DOOR: Vector2i = Vector2i(12, 0)
const BACK_DOOR_INSIDE: Vector2i = Vector2i(12, 1)
const DRAG_START: Vector2i = Vector2i(8, 5)
const DRAG_END: Vector2i = Vector2i(11, 6)
## [style, main colour, accent, first cell, last cell] laid in this order; a
## room fill (kitchen) uses the room around its first cell.
const AREAS: Array[Array] = [
	[&"small_tile", &"cream", &"", Vector2i(3, 2), Vector2i(-1, -1)],
	[&"narrow_planks", &"honey", &"", Vector2i(1, 5), Vector2i(12, 7)],
	[&"herringbone", &"honey", &"walnut", Vector2i(1, 8), Vector2i(4, 9)],
	[&"checker", &"cream", &"charcoal", Vector2i(5, 8), Vector2i(12, 10)],
	[&"hex_tile", &"butter", &"cream", Vector2i(1, 5), Vector2i(4, 5)],
	[&"terracotta", &"terracotta", &"clay", Vector2i(9, 7), Vector2i(12, 7)],
	[&"terrazzo", &"cream", &"slate_blue", Vector2i(5, 5), Vector2i(8, 5)],
	[&"concrete", &"slate_blue", &"charcoal", Vector2i(5, 6), Vector2i(8, 6)],
	[&"carpet", &"dusty_rose", &"walnut", Vector2i(9, 5), Vector2i(12, 6)],
]
## Cells and the floor pattern each must draw with once the fixture is laid.
## Keep samples outside DRAG_START..DRAG_END: the later live preview replaces
## those texels with herringbone without changing the stored floor.
const SAMPLES: Dictionary = {
	Vector2i(5, 5): FloorStyleDef.Pattern.TERRAZZO, Vector2i(6, 5): FloorStyleDef.Pattern.TERRAZZO,
	Vector2i(5, 6): FloorStyleDef.Pattern.CONCRETE, Vector2i(6, 6): FloorStyleDef.Pattern.CONCRETE,
	Vector2i(12, 5): FloorStyleDef.Pattern.CARPET, Vector2i(12, 6): FloorStyleDef.Pattern.CARPET,
	Vector2i(2, 5): FloorStyleDef.Pattern.HEX_TILE, Vector2i(3, 5): FloorStyleDef.Pattern.HEX_TILE,
	Vector2i(10, 7): FloorStyleDef.Pattern.TERRACOTTA, Vector2i(11, 7): FloorStyleDef.Pattern.TERRACOTTA,
	Vector2i(3, 2): FloorStyleDef.Pattern.SMALL_TILE, Vector2i(6, 4): FloorStyleDef.Pattern.SMALL_TILE,
	Vector2i(2, 6): FloorStyleDef.Pattern.NARROW_PLANKS, Vector2i(2, 9): FloorStyleDef.Pattern.HERRINGBONE,
	Vector2i(9, 9): FloorStyleDef.Pattern.CHECKER, Vector2i(6, 11): FloorStyleDef.Pattern.CHECKER,
	Vector2i(12, 0): FloorStyleDef.Pattern.SMALL_TILE,
}


static func prepare(main: Node, root: Window) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	if world == null or editor == null or world.clock.phase != SimClock.Phase.MORNING \
			or not main.has_method("shop_flooring") or not main.has_method("shop_walls"):
		return {"error": "floors review needs Main's morning flooring commands"}
	root.get_node("Economy").call("add_cash", 2000, Ledger.OTHER)
	editor.set_owner_level(5)
	var door: Dictionary[Vector3i, int] = {SimGrid.edge_between(BACK_DOOR_INSIDE, BACK_DOOR): SimGrid.Segment.DOORWAY}
	if not bool(main.call("shop_walls", door)):
		return {"error": "the back door was refused: " + editor.last_check.why}
	for area: Array in AREAS:
		var cells: Array[Vector2i] = editor.floor_room_cells(area[3]) if area[4] == Vector2i(-1, -1) \
			else rect_cells(area[3], area[4])
		var changes: Dictionary[Vector2i, FloorFinishes.Finish] = editor.lay_changes(cells, area[0], area[1], area[2])
		if not bool(main.call("shop_flooring", changes)):
			return {"error": "laying %s was refused: %s" % [area[0], editor.last_check.why]}
	return {"error": "", "stored_cells": editor.floors.count()}


## Build > Floors with herringbone held in a drag over part of the planks.
static func begin_drag(main: Node, root: Window) -> Dictionary:
	var camera: Camera3D = main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var catalogue: BuildCatalogue = main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var mode: BuildMode = main.get("build_mode") as BuildMode
	if camera == null or catalogue == null or mode == null or not bool(main.call("set_build_active", true)):
		return {"error": "floors review could not enter Build mode"}
	main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.FLOORS)
	var card: Button = catalogue.floor_style_buttons.get(&"herringbone") as Button
	if card == null:
		return {"error": "floors review cannot find the Herringbone card"}
	card.pressed.emit()
	if mode.state != BuildMode.State.FLOORS:
		return {"error": "the Herringbone card did not start the Floors tool"}
	var start: Vector2 = camera.unproject_position(GridMath.cell_to_world(DRAG_START))
	var pointer: Vector2 = camera.unproject_position(GridMath.cell_to_world(DRAG_END))
	main.call("update_build_pointer", start)
	if not mode.floors_press(DRAG_START):
		return {"error": "the Floors tool refused the drag"}
	root.warp_mouse(pointer)
	main.call("update_build_pointer", pointer)
	return {"error": "", "pointer": pointer}


## What the frame shows: the drawn pattern per sample cell and the tool state.
static func evidence(main: Node) -> Dictionary:
	var view: ShopView = main.get_node_or_null("ShopView") as ShopView
	var mode: BuildMode = main.get("build_mode") as BuildMode
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	if view == null or mode == null or editor == null:
		return {}
	var patterns: Dictionary = {}
	var matches: bool = true
	for cell: Vector2i in SAMPLES:
		var texel: Color = view.finish_texel(cell)
		patterns["%d,%d" % [cell.x, cell.y]] = texel.r8
		matches = matches and texel.r8 == int(SAMPLES[cell])
	var thresholds: int = 0
	for cell: Vector2i in view.world.grid.cells():
		if view.finish_texel(cell).a8 != 0:
			thresholds += 1
	return {"patterns": patterns, "patterns_match": matches, "threshold_cells": thresholds,
		"stored_cells": editor.floors.count(), "state": int(mode.state), "dragging": mode.floors_dragging,
		"summary": mode.floors_summary(), "check_ok": mode.current_check.ok,
		"proposal": mode.current_check.finishes.size(), "preview_cells": view.floor_preview_cells().size(),
		"floor_material_shared": view.segment_view != null and view.floor_mesh != null}


static func rect_cells(first: Vector2i, last: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			cells.append(Vector2i(x, y))
	return cells
