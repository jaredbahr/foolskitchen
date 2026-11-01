extends TestCase
## D26: wall finishes and wall decor in the real Main. Build > Wall finish
## cards start the tool; a click or a drag along a wall puts the chosen finish
## up, Shift-click does the room, Alt-click copies a wall's look, Ctrl+Z
## undoes with exact cash; locked cards stay disabled. Buy > Decor > Wall decor
## tiles hold an item to hang on the pointed wall; the hand moves a hung item,
## Del sells it. Paint recolours the run of wall pointed at (Shift: the room)
## even while the shop is open. The view draws nothing for a default shop,
## draws finished faces and hung items, and hides items on lowered walls.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const WEST: int = 3

var _main: Node3D
var _viewport: SubViewport


func before_each() -> void:
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_a_default_shop_draws_no_facings_and_hangs_nothing() -> void:
	await _start()
	var view: ShopView = _view()
	assert_not_null(view.wall_finish_view)
	assert_eq(view.wall_finish_view.finish_nodes().size(), 0, "plain paint draws exactly as before")
	assert_eq(view.wall_finish_view.item_nodes.size(), 0)
	assert_null(view.wall_finish_view.ghost())
	assert_eq(_editor().wall_vibe_swatch(), _editor().wall_swatch_id)


func test_wall_finish_tool_puts_up_drags_copies_and_undoes() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	assert_true(_main.call("set_build_active", true))
	var catalogue: BuildCatalogue = _catalogue()
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.WALL_FINISH)
	assert_eq(catalogue.category_buttons[&"wall_finish"].text, "Wall finish")
	assert_true(catalogue.wall_style_buttons[&"stripes"].visible)
	assert_eq(catalogue.wall_style_buttons[&"stripes"].text, "Striped wallpaper\n$2 a wall")
	assert_true(catalogue.wall_style_buttons[&"brick"].disabled, "locked at level 1")
	assert_eq(catalogue.wall_style_buttons[&"brick"].text, "Brick\nLevel 3")
	catalogue.wall_style_buttons[&"brick"].pressed.emit()
	assert_eq(_mode().state, BuildMode.State.IDLE, "a locked card starts nothing")
	catalogue.wall_style_buttons[&"stripes"].pressed.emit()
	assert_eq(_mode().state, BuildMode.State.WALL_FINISH)
	assert_eq([_mode().wall_style, _mode().wall_swatch, _mode().wall_accent], [&"stripes", &"butter", &"cream"])
	var cash: int = Economy.cash
	# Hover over the west wall: one face previewed, nothing changed yet.
	_wall_pointer(_face(1, 6, WEST))
	assert_eq(_mode().wall_face_hover, _face(1, 6, WEST), "the pointer finds the wall face")
	assert_eq(_view().wall_finish_view.preview_faces(), [_face(1, 6, WEST)] as Array[Vector3i])
	assert_eq(_editor().walls.count(), 0)
	# A drag along the wall puts it up.
	_wall_click(_face(1, 6, WEST), true)
	_wall_pointer(_face(1, 8, WEST))
	assert_eq(_mode().wall_finish_summary(), "Put up Striped wallpaper on 3 walls: $6")
	_wall_click(_face(1, 8, WEST), false)
	assert_eq(_editor().walls.count(), 3)
	assert_eq(Economy.cash, cash - 6)
	assert_eq(_editor().walls.finish(_face(1, 7, WEST)).style, &"stripes")
	assert_eq(_view().wall_finish_view.finished_faces().size(), 3)
	# Shift-click: the whole room's walls, in a chip's colour.
	catalogue.wall_colour_buttons[&"sage"].pressed.emit()
	assert_eq(_mode().wall_swatch, &"sage")
	var dining: Array[Vector3i] = _editor().wall_room_faces(_face(1, 6, WEST))
	_mode().wall_finish_press(_face(1, 9, WEST), true)
	assert_eq(_mode().wall_finish_proposal(), dining)
	_mode().wall_finish_release(_face(1, 9, WEST))
	assert_eq(_editor().walls.finish(_face(12, 7, 1)).swatch, &"sage")
	assert_eq(Economy.cash, cash - 6 - 2 * (dining.size() - 3), "the three striped walls only change colour")
	# Alt-click copies a wall's look into the tool and the tab.
	catalogue.wall_style_buttons[&"wainscot"].pressed.emit()
	assert_true(_mode().wall_finish_pick(_face(1, 6, WEST)))
	assert_eq([_mode().wall_style, _mode().wall_swatch], [&"stripes", &"sage"])
	# Undo both, exactly.
	assert_true(_main.call("undo_edit"))
	assert_true(_main.call("undo_edit"))
	assert_eq(_editor().walls.count(), 0)
	assert_eq(Economy.cash, cash)
	assert_eq(_mode().state, BuildMode.State.IDLE, "undo drops the tool, as for floors")
	assert_eq(_view().wall_finish_view.preview_faces().size(), 0, "and its preview")


func test_wall_decor_hangs_moves_and_sells_from_the_buy_catalogue() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	assert_true(_main.call("set_build_active", true))
	var catalogue: BuildCatalogue = _catalogue()
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUY)
	catalogue.set_category(&"decor")
	catalogue.set_group(&"wall_decor")
	assert_true(catalogue.group_buttons[&"wall_decor"].visible)
	assert_eq(catalogue.visible_ids(), [&"street_awning_2", &"street_awning_3", &"street_awning_4",
		&"menu_board", &"flower_window_box", &"wall_art_peaks", &"neon_open_sign", &"shop_name_sign",
		&"wall_art_sunrise"] as Array[StringName], "the original four and five new exterior pieces by name")
	assert_true(catalogue.item_buttons[&"neon_open_sign"].disabled, "level 4")
	assert_eq(catalogue.hover_card_lines(&"wall_art_sunrise")[2], "Hangs on a wall, 2 tiles wide")
	var cash: int = Economy.cash
	catalogue.item_buttons[&"wall_art_sunrise"].pressed.emit()
	assert_eq(_mode().state, BuildMode.State.HANG)
	# The pointer's side of the face picks the neighbour: on the west wall the
	# right (seen from the room) is north.
	_mode().hang_pointer(_face(1, 7, WEST), -0.1)
	assert_eq(_mode().hang_anchor, _face(1, 8, WEST))
	_mode().hang_pointer(_face(1, 7, WEST), 0.1)
	assert_eq(_mode().hang_anchor, _face(1, 7, WEST))
	assert_eq(_mode().hang_summary(), "Hang Sunrise print for $30")
	assert_true(_view().wall_finish_view.ghost() != null, "a ghost shows where it would hang")
	assert_true(_mode().hang_commit())
	assert_eq(Economy.cash, cash - 30)
	assert_eq(_editor().decor.anchors(), [_face(1, 7, WEST)] as Array[Vector3i])
	assert_eq(_mode().state, BuildMode.State.HANG, "a buy keeps the item in hand")
	_mode().hang_pointer(_face(1, 6, WEST), 0.0)
	assert_false(_mode().current_check.ok)
	assert_eq(_mode().hang_summary(), WallDecor.OCCUPIED)
	_key(KEY_ESCAPE)
	assert_eq(_mode().state, BuildMode.State.IDLE)
	var view: ShopView = _view()
	assert_eq(view.wall_finish_view.item_nodes.size(), 1)
	assert_true(view.wall_finish_view.item_nodes[_face(1, 7, WEST)].visible, "the west wall stays up in Cutaway")
	# The hand picks it up, moves it and puts it down, free.
	assert_true(_mode().begin_rehang(_face(1, 7, WEST)))
	_mode().hang_pointer(_face(1, 9, WEST), 0.1)
	assert_true(_mode().hang_commit())
	assert_eq(_editor().decor.anchors(), [_face(1, 9, WEST)] as Array[Vector3i])
	assert_eq(Economy.cash, cash - 30)
	# Del on a held item sells it for half.
	assert_true(_mode().begin_rehang(_face(1, 9, WEST)))
	_key(KEY_DELETE)
	assert_eq(_editor().decor.count(), 0)
	assert_eq(Economy.cash, cash - 15)
	assert_true(_main.call("undo_edit"))
	assert_eq(_editor().decor.count(), 1)
	assert_eq(Economy.cash, cash - 30)
	# Walls Down hides it (it would float over the stub).
	view.set_wall_mode(ShopView.WallMode.DOWN)
	assert_false(view.wall_finish_view.item_nodes[_face(1, 9, WEST)].visible)
	view.set_wall_mode(ShopView.WallMode.UP)
	assert_true(view.wall_finish_view.item_nodes[_face(1, 9, WEST)].visible)


func test_the_neon_sign_hangs_in_a_window_facing_the_street_and_glows_both_ways() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	_editor().set_owner_level(4)
	var slot: Vector3i = Vector3i(8, 9, 2)
	var other: Vector3i = Vector3i(10, 9, 2)
	var windows: Dictionary[Vector3i, int] = {Vector3i(8, 10, SimGrid.EDGE_NORTH): SimGrid.Segment.WINDOW,
		Vector3i(10, 10, SimGrid.EDGE_NORTH): SimGrid.Segment.WINDOW}
	assert_true(_main.call("shop_walls", windows), _editor().last_check.why)
	assert_true(_main.call("shop_hang", &"wall_art_sunrise", _face(2, 1, 0)))
	assert_false(_main.call("shop_hang", &"neon_open_sign", _face(1, 9, WEST)), "not on an inside wall")
	assert_eq(_editor().last_check.why, "This sign hangs in a window")
	assert_true(_main.call("shop_hang", &"neon_open_sign", slot), _editor().last_check.why)
	var view: ShopView = _view()
	view.set_wall_mode(ShopView.WallMode.UP)
	var finish_view: WallFinishView = view.wall_finish_view
	assert_eq(finish_view.find_children("Glow", "OmniLight3D", true, false).size(), 1, "prints do not glow")
	var sign: ItemVisual = finish_view.item_nodes[slot]
	# Centred in the opening, inside the shell cell's depth, its front (-Z) to the street (+Z here).
	var opening: Rect2 = WallSegmentView.window_opening()
	var bounds: AABB = sign.global_transform * sign.get_aabb()
	assert_true(bounds.size.x <= opening.size.x and bounds.size.y <= opening.size.y, "fits the window")
	assert_almost_eq(bounds.get_center().x, GridMath.cell_to_world(Vector2i(8, 9)).x, 0.001, "centred across")
	assert_almost_eq(bounds.get_center().y, opening.get_center().y, 0.001, "centred up and down")
	var inner: float = GridMath.cell_to_world(Vector2i(8, 9)).z + GridMath.CELL_SIZE * 0.5
	assert_true(bounds.position.z > inner and bounds.end.z < inner + GridMath.CELL_SIZE, "in the opening")
	assert_true((sign.global_transform.basis * Vector3.FORWARD).dot(Vector3.BACK) > 0.99, "text faces the street")
	var glow: OmniLight3D = sign.get_node("Glow") as OmniLight3D
	assert_false(glow.shadow_enabled, "no shadows: cheap in Compatibility")
	assert_true(glow.light_energy <= 1.0)
	assert_true(glow.light_color.r > 0.9 and glow.light_color.g < 0.3, "neon red")
	assert_almost_eq(glow.global_position.z, inner + GridMath.CELL_SIZE * 0.5, 0.001,
		"in the window plane, halfway between the room and the street")
	assert_almost_eq(glow.global_position.x, bounds.get_center().x, 0.001)
	# Its light stays in the window: a room beside it starts past an interior
	# wall on the window cell's side line, at least sqrt(0.28^2 + 0.25^2) away.
	assert_true(glow.omni_range < Vector2(GridMath.CELL_SIZE * 0.5 + WallSegmentView.THICKNESS * 0.5, GridMath.CELL_SIZE * 0.5).length(),
		"the light never reaches a neighbouring room")
	# The pools are exactly the floor cell inside and the ground cell outside.
	var pools: Dictionary[String, Vector2i] = {"PoolInside": Vector2i(8, 9), "PoolOutside": Vector2i(8, 11)}
	for pool_name: String in pools:
		var pool: MeshInstance3D = sign.get_node(pool_name) as MeshInstance3D
		var area: AABB = pool.global_transform * pool.get_aabb()
		var cell: Vector3 = GridMath.cell_to_world(pools[pool_name])
		assert_almost_eq(area.get_center().x, cell.x, 0.001, pool_name)
		assert_almost_eq(area.get_center().z, cell.z, 0.001, pool_name)
		assert_true(area.size.x <= GridMath.CELL_SIZE + 0.001 and area.size.z <= GridMath.CELL_SIZE + 0.001, pool_name)
		assert_true(area.position.y < 0.01, "%s lies on the ground" % pool_name)
		assert_eq(pool.layers & glow.light_cull_mask, 0)
	for mesh: MeshInstance3D in sign.rendered_meshes():
		assert_eq(mesh.layers & glow.light_cull_mask, 0, "the glow does not wash out its own sign")
	assert_true(glow.is_visible_in_tree())
	# Walls Down hides the sign and its glow; a held sign hides both too.
	view.set_wall_mode(ShopView.WallMode.DOWN)
	assert_false(glow.is_visible_in_tree())
	view.set_wall_mode(ShopView.WallMode.UP)
	assert_true(glow.is_visible_in_tree())
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_rehang(slot))
	assert_eq(_mode().hang_summary(), "Move Neon OPEN sign here (Del sells it)")
	_mode().hang_pointer(_face(1, 6, WEST), 0.1)
	assert_eq(_mode().current_check.why, "This sign hangs in a window", "a wall is refused")
	_mode().hang_pointer(other, 0.1)
	assert_true(_mode().current_check.ok, _mode().current_check.why)
	assert_false(glow.is_visible_in_tree(), "the held sign's glow goes with it")
	assert_eq(finish_view.ghost().find_children("Glow", "OmniLight3D", true, false).size(), 0,
		"a ghost previews no light")
	assert_true(_mode().hang_commit())
	var moved: ItemVisual = finish_view.item_nodes[other]
	assert_true((moved.get_node("Glow") as Node3D).is_visible_in_tree(), "the glow follows the sign")
	assert_eq(finish_view.find_children("Glow", "OmniLight3D", true, false).size(), 1)
	# Closing the window takes the sign (and its glow) down.
	_mode().cancel_ghost()
	var close: Dictionary[Vector3i, int] = {Vector3i(10, 10, SimGrid.EDGE_NORTH): SimGrid.Segment.NONE}
	assert_true(_main.call("shop_walls", close), _editor().last_check.why)
	assert_eq(_editor().decor.count(), 1, "only the print is left")
	assert_eq(finish_view.find_children("Glow", "OmniLight3D", true, false).size(), 0)


func test_pointing_at_a_window_picks_its_slot_for_the_sign() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	_editor().set_owner_level(4)
	var windows: Dictionary[Vector3i, int] = {Vector3i(8, 10, SimGrid.EDGE_NORTH): SimGrid.Segment.WINDOW}
	assert_true(_main.call("shop_walls", windows), _editor().last_check.why)
	var view: ShopView = _view()
	view.set_wall_mode(ShopView.WallMode.UP)
	# A ray from above the street down into the window's opening.
	var target: Vector3 = GridMath.cell_to_world(Vector2i(8, 10)) + Vector3(0.0, 0.7, 0.0)
	var origin: Vector3 = target + Vector3(0.0, 4.0, 3.0)
	var hit: Dictionary = view.window_at_ray(origin, (target - origin).normalized())
	assert_eq(hit.get("face"), Vector3i(8, 9, 2))
	assert_true(view.window_at_ray(origin, (GridMath.cell_to_world(Vector2i(3, 6)) - origin).normalized()).is_empty(),
		"nothing away from windows")


func test_removing_a_wall_takes_its_finish_and_decor_off_the_view() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	assert_true(_main.call("set_build_active", true))
	var wall: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 8):
		wall[Vector3i(9, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.WALL
	assert_true(_main.call("shop_walls", wall))
	assert_true(_main.call("shop_wall_finishes", _editor().wall_lay_changes(
		[_face(9, 6, WEST), _face(8, 6, 1)] as Array[Vector3i], &"stripes", &"butter")))
	assert_true(_main.call("shop_hang", &"menu_board", _face(9, 6, WEST)))
	var view: ShopView = _view()
	view.set_wall_mode(ShopView.WallMode.UP)
	assert_eq(view.wall_finish_view.finished_faces().size(), 2)
	assert_true(view.wall_finish_view.item_nodes[_face(9, 6, WEST)].visible)
	view.set_wall_mode(ShopView.WallMode.CUTAWAY)
	assert_false(view.wall_finish_view.item_nodes[_face(9, 6, WEST)].visible, "interior walls are lowered in Cutaway")
	var cash: int = Economy.cash
	for edge: Vector3i in wall:
		wall[edge] = SimGrid.Segment.NONE
	assert_true(_main.call("shop_walls", wall))
	assert_eq(view.wall_finish_view.finished_faces().size(), 0)
	assert_eq(view.wall_finish_view.item_nodes.size(), 0)
	assert_eq(Economy.cash, cash + 3 * 5 + 2 * 1 + 12)
	assert_true(_main.call("undo_edit"))
	assert_eq(view.wall_finish_view.finished_faces().size(), 2)
	assert_eq(view.wall_finish_view.item_nodes.size(), 1)
	assert_eq(Economy.cash, cash)


func test_paint_recolours_the_run_of_wall_or_the_room_while_open() -> void:
	await _start()
	Clock.sim.start_service()
	assert_true(_main.call("set_paint_active", true))
	_main.set("_paint_swatch_id", &"sage")
	var cash: int = Economy.cash
	var face: Vector3i = _face(1, 6, WEST)
	var run: Array[Vector3i] = _editor().wall_area_faces(face)
	_main.call("update_paint_pointer", _face_point(face))
	assert_eq(_main.call("paint_face_at_screen_position", _face_point(face)), face, "the click lands on the wall")
	assert_eq(_view().wall_finish_view.preview_faces(), run, "hover shows the run")
	assert_true(_main.call("paint_face", face))
	for painted: Vector3i in run:
		assert_eq(_editor().walls.finish(painted).swatch, &"sage")
	assert_eq(_editor().walls.finish(_face(3, 1, 0)).swatch, _editor().wall_swatch_id, "the kitchen is another room")
	assert_true(_main.call("paint_face", _face(3, 1, 0), true))
	assert_eq(_editor().walls.finish(_face(12, 2, 1)).swatch, &"sage", "Shift paints the kitchen's walls")
	assert_eq(_editor().wall_vibe_swatch(), _editor().wall_swatch_id, "guests see mostly the old paint still")
	assert_true(_main.call("paint_face", _face(12, 7, 1), true))
	assert_eq(_editor().walls.finish(_face(12, 7, 1)).swatch, &"sage", "Shift paints the dining room's walls")
	assert_eq(Economy.cash, cash, "recolouring is free")
	assert_eq(_editor().wall_vibe_swatch(), &"sage")
	assert_true(_main.call("set_paint_active", false))


func test_a_paint_click_on_wall_decor_paints_nothing() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("shop_hang", &"menu_board", _face(1, 8, WEST)))
	assert_true(_main.call("set_build_active", false))
	assert_true(_main.call("set_paint_active", true))
	_main.set("_paint_swatch_id", &"sage")
	var point: Vector2 = _face_point(_face(1, 8, WEST))
	assert_eq(_main.call("wall_item_at_screen_position", point), _face(1, 8, WEST))
	assert_eq(_main.call("paint_face_at_screen_position", point), WallFaces.NO_FACE, "the board covers the wall")
	_main.call("update_paint_pointer", point)
	assert_eq(_view().wall_finish_view.preview_faces().size(), 0)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_true(_main.call("route_paint_input", click))
	assert_eq(_editor().wall_swatch_id, &"", "never the whole building behind it")
	assert_eq(_editor().walls.count(), 0)
	assert_true(_main.call("set_paint_active", false))


func test_the_street_side_of_a_shell_wall_has_no_face() -> void:
	await _start()
	var view: ShopView = _view()
	view.set_wall_mode(ShopView.WallMode.UP)
	var west: Vector3 = GridMath.cell_to_world(Vector2i(1, 6))
	var along: Vector3 = Vector3(1.0, -0.1, 0.0).normalized()
	var outside: Dictionary = view.wall_face_at_ray(Vector3(-3.0, 1.0, west.z), along)
	assert_false(outside.is_empty(), "the wall is hit")
	assert_eq(outside.get("face"), WallFaces.NO_FACE, "its street side is not the room-side face")
	var inside: Dictionary = view.wall_face_at_ray(Vector3(3.0, 1.0, west.z), Vector3(-1.0, -0.1, 0.0).normalized())
	assert_eq(inside.get("face"), _face(1, 6, WEST), "the room side still is")


func test_wall_decor_behind_a_wall_cannot_be_picked_or_sold() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	_editor().set_owner_level(4)
	var view: ShopView = _view()
	assert_true(_main.call("shop_hang", &"wall_art_sunrise", _face(1, 8, WEST)), _editor().last_check.why)
	var wall: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 8):
		wall[Vector3i(9, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.WALL
	assert_true(_main.call("shop_walls", wall), _editor().last_check.why)
	assert_true(_main.call("shop_hang", &"menu_board", _face(9, 6, WEST)), _editor().last_check.why)
	view.set_wall_mode(ShopView.WallMode.UP)
	var print_node: ItemVisual = view.wall_finish_view.item_nodes[_face(1, 8, WEST)]
	var print_centre: Vector3 = print_node.global_transform * print_node.get_aabb().get_center()
	# From the street, through the shell: not picked. From the room: picked.
	var from_street: Vector3 = print_centre + Vector3(-3.0, 0.3, 0.0)
	assert_eq(view.wall_item_at_ray(from_street, (print_centre - from_street).normalized()), WallFaces.NO_FACE)
	var from_room: Vector3 = print_centre + Vector3(3.0, 0.3, 0.0)
	assert_eq(view.wall_item_at_ray(from_room, (print_centre - from_room).normalized()), _face(1, 8, WEST))
	# Through the interior slab from the room west of it: not picked.
	var board: ItemVisual = view.wall_finish_view.item_nodes[_face(9, 6, WEST)]
	var board_centre: Vector3 = board.global_transform * board.get_aabb().get_center()
	var behind: Vector3 = board_centre + Vector3(-3.0, 0.3, 0.0)
	assert_eq(view.wall_item_at_ray(behind, (board_centre - behind).normalized()), WallFaces.NO_FACE)
	# The real camera at quarter 2, Walls Up: the west wall hides the print.
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	rig.rotate_quarter(2 - rig.camera_quarter())
	rig.step_view(10.0, Vector2.ZERO)
	var camera: Camera3D = _main.get_node("CameraRig/Camera3D") as Camera3D
	var screen: Vector2 = camera.unproject_position(print_centre)
	assert_eq(_main.call("wall_item_at_screen_position", screen), WallFaces.NO_FACE)
	assert_true(_main.call("set_build_active", true))
	view.set_wall_mode(ShopView.WallMode.UP)
	_mode().tool = BuildMode.Tool.SELL
	_main.call("update_build_pointer", screen)
	var cash: int = Economy.cash
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = screen
	click.global_position = screen
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_main.call("_unhandled_input", click)
	assert_eq(_editor().decor.count(), 2, "nothing sold through the wall")
	assert_eq(Economy.cash, cash)


func test_a_window_sign_is_picked_from_the_street_not_through_the_wall() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	_editor().set_owner_level(4)
	var windows: Dictionary[Vector3i, int] = {Vector3i(8, 10, SimGrid.EDGE_NORTH): SimGrid.Segment.WINDOW}
	assert_true(_main.call("shop_walls", windows), _editor().last_check.why)
	assert_true(_main.call("shop_hang", &"neon_open_sign", Vector3i(8, 9, 2)), _editor().last_check.why)
	var view: ShopView = _view()
	view.set_wall_mode(ShopView.WallMode.UP)
	var sign: ItemVisual = view.wall_finish_view.item_nodes[Vector3i(8, 9, 2)]
	var centre: Vector3 = sign.global_transform * sign.get_aabb().get_center()
	var street: Vector3 = centre + Vector3(0.0, 2.0, 2.0)
	assert_eq(view.wall_item_at_ray(street, (centre - street).normalized()), Vector3i(8, 9, 2))
	# From the room the ray drops past the window head: the wall is in the way.
	var room: Vector3 = centre + Vector3(0.0, 2.0, -2.0)
	assert_eq(view.wall_item_at_ray(room, (centre - room).normalized()), WallFaces.NO_FACE)


func test_the_hand_names_the_hung_item_it_points_at() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	assert_true(_main.call("shop_hang", &"menu_board", _face(2, 1, 0)), _editor().last_check.why)
	assert_true(_main.call("set_build_active", true))
	_mode().hover_wall_item(_face(2, 1, 0))
	assert_eq(_mode().hover_summary(), "Pick up Chalk menu board to move it")


func _start() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set_process(false)
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	rig.edge_pan_enabled = false
	(_main.get_node("ShopView") as ShopView).set_process(false)
	for frame: int in range(3):
		await tree.process_frame


func _mode() -> BuildMode:
	return _main.get("build_mode") as BuildMode


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _view() -> ShopView:
	return _main.get_node("ShopView") as ShopView


func _catalogue() -> BuildCatalogue:
	return _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue


func _face(x: int, y: int, dir: int) -> Vector3i:
	return Vector3i(x, y, dir)


## The screen point of a face's wall, 0.7 m up.
func _face_point(face: Vector3i) -> Vector2:
	var into: Vector2i = WallFaces.step(face)
	var point: Vector3 = GridMath.cell_to_world(WallFaces.cell(face)) + Vector3(into.x, 0.0, into.y) * 0.24 + Vector3.UP * 0.7
	return (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(point)


func _wall_pointer(face: Vector3i) -> void:
	assert_true(_main.call("update_build_pointer", _face_point(face)))


func _wall_click(face: Vector3i, down: bool) -> void:
	_wall_pointer(face)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = _face_point(face)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	_main.call("_unhandled_input", event)


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	_main.call("_unhandled_input", event)
