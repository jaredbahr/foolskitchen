extends TestCase
## FK-113: actual catalogue, native input, removal ghosts and morning saving.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "wall_removal_session"

var _main: Node3D
var _viewport: SubViewport
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary
var _clock_processing: bool
var _last_native_point: Vector2 = Vector2.ZERO


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_clock_processing = Clock.is_processing()
	Clock.set_process(false)
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	SaveSystem._providers.merge(_old_providers)
	Clock.set_speed(0)
	Clock.set_process(_clock_processing)
	Economy.reset(0)
	GameState.new_run(1)


func test_visible_remove_button_enters_remove_without_building_or_spending() -> void:
	await _start()
	var button: Button = _remove_button()
	assert_not_null(button, "Walls exposes a Remove button alongside the wall kinds")
	if button == null:
		return
	assert_true(button.is_visible_in_tree())
	assert_eq(button.text, "Remove")
	assert_false(button.tooltip_text.is_empty())
	var cash: int = Economy.cash
	var walls: Dictionary[Vector3i, int] = _editor().segments()
	_native_click(button.get_global_rect().get_center())
	assert_eq(_mode().state, BuildMode.State.WALLS)
	assert_eq(_mode().wall_kind, SimGrid.Segment.NONE)
	assert_eq(Economy.cash, cash)
	assert_eq(_editor().segments(), walls)
	var hints: Label = _main.get_node("HUD/BuildHints/Scroll/Lines/Text") as Label
	assert_true(hints.text.to_lower().contains("del"))
	assert_true(hints.text.to_lower().contains("remove"))


func test_native_remove_drag_previews_red_refund_then_undo_and_next_morning_save() -> void:
	await _start()
	var button: Button = _remove_button()
	assert_not_null(button)
	if button == null:
		return
	_add_run()
	for frame: int in 2:
		await _tree().process_frame
	var morning: String = _saved_text()
	var cash: int = Economy.cash
	_focus(Vector2(9.0, 6.5) * GridMath.CELL_SIZE)
	_native_click(button.get_global_rect().get_center())
	assert_eq(_mode().state, BuildMode.State.WALLS)
	assert_eq(_mode().wall_kind, SimGrid.Segment.NONE)
	var start: Vector2 = _project(Vector2(9, 5) * GridMath.CELL_SIZE)
	var end: Vector2 = _project(Vector2(9, 8) * GridMath.CELL_SIZE)
	_assert_clear(start)
	_assert_clear(end)
	_native_mouse(start, true)
	_native_pointer(end, true)
	assert_eq(_mode().wall_changes.size(), 3)
	assert_true(_mode().current_check.ok, _mode().current_check.why)
	assert_eq(_mode().current_check.cost, 0)
	assert_eq(_mode().current_check.refund, 15)
	assert_true(_mode().wall_summary().contains("refund $15"))
	var preview: BuildPreview = _main.get_node("BuildPreview") as BuildPreview
	assert_eq(preview.wall_ghosts.size(), 3)
	for ghost: MeshInstance3D in preview.wall_ghosts:
		var material: BaseMaterial3D = ghost.get_active_material(0) as BaseMaterial3D
		assert_almost_eq(material.albedo_color.r, BuildPreview.INVALID_COLOR.r)
		assert_almost_eq(material.albedo_color.g, BuildPreview.INVALID_COLOR.g)
		assert_almost_eq(material.albedo_color.b, BuildPreview.INVALID_COLOR.b)
	assert_eq(Economy.cash, cash, "preview cannot refund before release")
	assert_eq(_saved_text(), morning)
	_native_mouse(end, false)
	for y: int in range(5, 8):
		assert_eq(_grid().segment(Vector3i(9, y, SimGrid.EDGE_WEST)), SimGrid.Segment.NONE)
	assert_eq(Economy.cash, cash + 15)
	assert_eq(_saved_text(), morning)
	_native_key(KEY_Z, true)
	for y: int in range(5, 8):
		assert_eq(_grid().segment(Vector3i(9, y, SimGrid.EDGE_WEST)), SimGrid.Segment.WALL)
	assert_eq(Economy.cash, cash, "native undo restores the exact refund")
	assert_eq(_saved_text(), morning)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	var saved: Dictionary = JSON.parse_string(_saved_text())
	var walls: Array = saved["data"]["shop"]["walls"]
	for y: int in range(5, 8):
		var expected: Dictionary = JSON.parse_string(JSON.stringify({
			"edge": [9, y, SimGrid.EDGE_WEST], "kind": "wall"}))
		assert_true(walls.has(expected), "the morning save contains the restored segment")


func test_sell_tool_native_click_removes_a_hovered_segment_with_the_same_refund() -> void:
	await _start()
	_add_run()
	(_main.get_node("ShopView") as ShopView).set_wall_mode(ShopView.WallMode.UP)
	var edge: Vector3i = Vector3i(9, 6, SimGrid.EDGE_WEST)
	var cash: int = Economy.cash
	var saved: String = _saved_text()
	_mode().set_tool(BuildMode.Tool.SELL)
	_focus(Vector2(9.0, 6.5) * GridMath.CELL_SIZE)
	var point: Vector2 = _project(Vector2(9.0, 6.5) * GridMath.CELL_SIZE, 0.7)
	_assert_clear(point)
	_native_pointer(point)
	assert_true(_mode().hover_summary().contains("$5"), "Sell names the hovered segment's refund")
	_native_click(point)
	assert_eq(_grid().segment(edge), SimGrid.Segment.NONE)
	assert_eq(Economy.cash, cash + 5)
	assert_eq(_saved_text(), saved)
	_native_key(KEY_Z, true)
	assert_eq(_grid().segment(edge), SimGrid.Segment.WALL)
	assert_eq(Economy.cash, cash)


func test_native_remove_refusal_keeps_the_person_door_cash_and_reason() -> void:
	await _start()
	var button: Button = _remove_button()
	assert_not_null(button)
	if button == null:
		return
	var edge: Vector3i = Vector3i(13, 6, SimGrid.EDGE_WEST)
	assert_true(_main.call("set_build_active", false))
	assert_true(_main.call("shop_walls", {edge: SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]))
	var person: SimAgent = SimAgent.new()
	person.cell = Vector2i(13, 6)
	(_main.get("world") as SimWorld).add_agent(person)
	assert_true(_main.call("set_build_active", true))
	for frame: int in 2:
		await _tree().process_frame
	var cash: int = Economy.cash
	var saved: String = _saved_text()
	_focus(Vector2(13.0, 6.5) * GridMath.CELL_SIZE)
	_native_click(button.get_global_rect().get_center())
	assert_eq(_mode().state, BuildMode.State.WALLS)
	assert_eq(_mode().wall_kind, SimGrid.Segment.NONE)
	var point: Vector2 = _project(Vector2(13.0, 6.5) * GridMath.CELL_SIZE)
	_assert_clear(point)
	_native_pointer(point)
	assert_false(_mode().current_check.ok)
	assert_eq(_mode().wall_summary(), WallRules.CUT_PERSON)
	_native_click(point)
	assert_eq(_mode().wall_summary(), WallRules.CUT_PERSON)
	assert_eq(_grid().segment(edge), SimGrid.Segment.DOORWAY)
	assert_eq(person.cell, Vector2i(13, 6))
	assert_eq(Economy.cash, cash)
	assert_eq(_saved_text(), saved)


func test_native_delete_still_removes_a_wall_from_the_ordinary_walls_tool() -> void:
	await _start()
	_add_run()
	var cash: int = Economy.cash
	assert_true(_main.call("begin_wall_tool", SimGrid.Segment.WALL))
	_focus(Vector2(9.0, 6.5) * GridMath.CELL_SIZE)
	var point: Vector2 = _project(Vector2(9.0, 6.5) * GridMath.CELL_SIZE)
	_assert_clear(point)
	_native_pointer(point)
	_native_key(KEY_DELETE)
	assert_eq(_grid().segment(Vector3i(9, 6, SimGrid.EDGE_WEST)), SimGrid.Segment.NONE)
	assert_eq(Economy.cash, cash + 5)


func test_sell_takes_visible_wall_decor_down_before_the_segment() -> void:
	await _start()
	_add_run()
	var face: Vector3i = Vector3i(9, 6, 3)
	assert_true(_main.call("shop_hang", &"wall_art_sunrise", face), _editor().last_check.why)
	var view: ShopView = _main.get_node("ShopView") as ShopView
	view.set_wall_mode(ShopView.WallMode.UP)
	var visual: ItemVisual = view.wall_finish_view.item_nodes[face]
	var centre: Vector3 = visual.global_transform * visual.get_aabb().get_center()
	var cash: int = Economy.cash
	var refund: int = ShopEditor.sale_refund((_main.get("content") as ContentDB).item(&"wall_art_sunrise"))
	_focus(Vector2(centre.x, centre.z))
	var point: Vector2 = (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(centre)
	_assert_clear(point)
	_mode().set_tool(BuildMode.Tool.SELL)
	_native_pointer(point)
	_native_click(point)
	assert_null(_editor().decor.item(face))
	assert_eq(_grid().segment(Vector3i(9, 6, SimGrid.EDGE_WEST)), SimGrid.Segment.WALL,
		"the first Sell click targets the visible wall decor")
	assert_eq(Economy.cash, cash + refund)
	_native_pointer(point)
	var pointed_edge: Vector3i = _mode().wall_hover_edge
	assert_ne(pointed_edge, SimGrid.NO_EDGE, "the revealed wall under the same native pointer is hovered")
	assert_eq(_grid().segment(pointed_edge), SimGrid.Segment.WALL)
	_native_click(point)
	assert_eq(_grid().segment(pointed_edge), SimGrid.Segment.NONE)
	assert_eq(Economy.cash, cash + refund + 5)
	_native_key(KEY_Z, true)
	assert_eq(_grid().segment(pointed_edge), SimGrid.Segment.WALL)
	assert_null(_editor().decor.item(face))
	assert_eq(Economy.cash, cash + refund)
	_native_key(KEY_Z, true)
	assert_not_null(_editor().decor.item(face))
	assert_eq(Economy.cash, cash)


func test_legacy_lost_face_refund_is_applied_only_after_successful_load_and_once() -> void:
	await _start()
	var cash: int = Economy.cash
	var document: Dictionary = JSON.parse_string(_saved_text())
	document["data"]["shop"] = _legacy_snapshot_with_lost_face()
	var content: ContentDB = _main.get("content") as ContentDB
	var refund: int = floori(float(content.wall_style(&"brick").price) / 2.0) \
		+ ShopEditor.sale_refund(content.item(&"wall_art_sunrise"))
	_write_document(document)
	_close_fixture()
	await _start()
	assert_eq(Economy.cash, cash + refund, "the staged refund reaches the successfully loaded morning")
	assert_eq(_grid().terrain(Vector2i(4, 4)), SimGrid.Terrain.FLOOR)
	assert_null(_editor().decor.item(Vector3i(3, 3, 2)))
	var saved: Dictionary = JSON.parse_string(_saved_text())
	assert_eq(int(saved["data"]["shop"]["version"]), 8)
	_close_fixture()
	await _start()
	assert_eq(Economy.cash, cash + refund, "reloading v8 never pays the migration refund again")


func test_a_later_invalid_save_section_does_not_apply_staged_migration_refunds() -> void:
	await _start()
	var cash: int = Economy.cash
	var document: Dictionary = JSON.parse_string(_saved_text())
	document["data"]["shop"] = _legacy_snapshot_with_lost_face()
	document["data"]["deliveries"] = {"version": 1, "orders": 5}
	_write_document(document)
	var broken: String = _saved_text()
	_close_fixture()
	await _start()
	assert_eq(Economy.cash, cash, "the fallback new game cannot receive a rejected save's refund")
	assert_eq(_saved_text(), broken, "the rejected save remains available for recovery")
	assert_eq(Clock.sim.day, 1)


func test_native_sell_removes_an_outer_window_header_without_exposing_a_paint_face() -> void:
	await _start()
	_assert_outer_sell(SimGrid.Segment.WINDOW)


func test_native_sell_removes_an_outer_back_door_top_with_exact_refund_and_undo() -> void:
	await _start()
	_assert_outer_sell(SimGrid.Segment.DOORWAY)


func test_native_sell_refuses_an_outer_door_frame_while_someone_stands_in_it() -> void:
	await _start()
	var mesh: MeshInstance3D = _prepare_outer_frame(SimGrid.Segment.DOORWAY)
	assert_not_null(mesh)
	if mesh == null:
		return
	var person: SimAgent = SimAgent.new()
	person.cell = Vector2i(13, 6)
	(_main.get("world") as SimWorld).add_agent(person)
	_mode().set_tool(BuildMode.Tool.SELL)
	var centre: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
	_rig().initial_yaw_degrees = 90.0
	_focus(Vector2(centre.x, centre.z))
	var point: Vector2 = _camera().unproject_position(centre)
	_assert_clear(point)
	var cash: int = Economy.cash
	_native_pointer(point)
	assert_eq(_mode().hover_summary(), WallRules.CUT_PERSON)
	_native_click(point)
	assert_eq(_grid().segment(Vector3i(13, 6, SimGrid.EDGE_WEST)), SimGrid.Segment.DOORWAY)
	assert_eq(person.cell, Vector2i(13, 6))
	assert_eq(Economy.cash, cash)
	assert_eq(_mode().hover_summary(), WallRules.CUT_PERSON)


func test_outer_frame_sell_ray_respects_foreground_furniture_and_thick_shell_geometry() -> void:
	await _start()
	var header: MeshInstance3D = _prepare_outer_frame(SimGrid.Segment.WINDOW)
	assert_not_null(header)
	if header == null:
		return
	assert_true(_main.call("shop_buy", &"fridge", Vector2i(9, 8), 0), _editor().last_check.why)
	var fridge: PlacedItem = _grid().item_at(Vector2i(9, 8))
	assert_not_null(fridge)
	if fridge == null:
		return
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var frame: Node3D = view.segment_view.get_node("ShellWindow_13_6") as Node3D
	var jamb: MeshInstance3D = _frame_piece(frame, false)
	assert_not_null(jamb)
	if jamb == null:
		return
	var target: Vector3 = jamb.global_transform * jamb.get_aabb().get_center()
	var furniture: ItemVisual = view.item_nodes[fridge.id]
	var furniture_bounds: AABB = furniture.global_transform * furniture.get_aabb()
	var furniture_point: Vector3 = furniture_bounds.get_center()
	furniture_point.y = furniture_bounds.end.y - 0.02
	assert_true(furniture_point.y > target.y, "the measured opaque furniture stands above this frame part")
	var origin: Vector3 = furniture_point + (furniture_point - target).normalized()
	var direction: Vector3 = (target - origin).normalized()
	var candidate: Dictionary = view.wall_segment_at_ray(origin, direction)
	assert_eq(candidate.get("edge", SimGrid.NO_EDGE), Vector3i(13, 6, SimGrid.EDGE_WEST))
	assert_true(view.nearest_item_distance(origin, direction) < float(candidate.get("distance", INF)),
		"the rendered furniture is measurably in front of the frame")
	_camera().global_position = origin
	_camera().look_at(target)
	_camera().near = 0.01
	var point: Vector2 = _camera().unproject_position(target)
	_assert_clear(point)
	assert_eq(_main.call("wall_segment_at_screen_position", point), SimGrid.NO_EDGE)
	_mode().set_tool(BuildMode.Tool.SELL)
	_native_pointer(point)
	assert_eq(_mode().wall_hover_edge, SimGrid.NO_EDGE)
	var shell: MeshInstance3D = (view.get("_wall_nodes") as Dictionary)[Vector2i(13, 5)] as MeshInstance3D
	var shell_bounds: AABB = shell.global_transform * shell.get_aabb()
	var shell_point: Vector3 = shell_bounds.get_center()
	shell_point.y = shell_bounds.end.y - 0.02
	origin = shell_point + (shell_point - target).normalized()
	direction = (target - origin).normalized()
	assert_true(view.wall_segment_at_ray(origin, direction).is_empty(),
		"the opaque shell blocks a frame behind it")
	_camera().global_position = origin
	_camera().look_at(target)
	point = _camera().unproject_position(target)
	assert_eq(_main.call("wall_segment_at_screen_position", point), SimGrid.NO_EDGE)
	assert_eq(_grid().segment(Vector3i(13, 6, SimGrid.EDGE_WEST)), SimGrid.Segment.WINDOW)


func _start() -> void:
	await _tree().process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_tree().root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("save_slot", SLOT)
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 1)
	_viewport.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	(_main.get_node("ShopView") as ShopView).set_process(false)
	_rig().set_process(false)
	_rig().edge_pan_enabled = false
	assert_true(_main.call("set_build_active", true))
	_catalogue().set_mode(BuildCatalogue.BUILD)
	_catalogue().set_category(BuildCatalogue.WALLS)
	for frame: int in 3:
		await _tree().process_frame


func _add_run() -> void:
	# Prepare the existing wall before entering the player's interaction mode.
	# Native controller commits normally guard transient editor change signals.
	assert_true(_main.call("set_build_active", false))
	var changes: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 8):
		changes[Vector3i(9, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.WALL
	assert_true(_main.call("shop_walls", changes), _editor().last_check.why)
	assert_true(_main.call("set_build_active", true))


func _assert_outer_sell(kind: SimGrid.Segment) -> void:
	var mesh: MeshInstance3D = _prepare_outer_frame(kind)
	assert_not_null(mesh)
	if mesh == null:
		return
	var centre: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
	_rig().initial_yaw_degrees = 90.0
	_focus(Vector2(centre.x, centre.z))
	var point: Vector2 = _camera().unproject_position(centre)
	_assert_clear(point)
	var paint: Dictionary = _main.call("wall_face_at_screen_position", point, false)
	assert_eq(paint.get("face", WallFaces.NO_FACE), WallFaces.NO_FACE,
		"a removable fitting never becomes a paintable wall face")
	var edge: Vector3i = Vector3i(13, 6, SimGrid.EDGE_WEST)
	assert_eq(_main.call("wall_segment_at_screen_position", point), edge)
	_mode().set_tool(BuildMode.Tool.SELL)
	var cash: int = Economy.cash
	var saved: String = _saved_text()
	var refund: int = floori(float((_main.get("content") as ContentDB).wall_kind_for(kind).price) / 2.0)
	_native_pointer(point)
	assert_eq(_mode().wall_hover_edge, edge)
	assert_true(_mode().hover_summary().contains("$%d" % refund))
	_native_click(point)
	assert_eq(_grid().segment(edge), SimGrid.Segment.NONE)
	assert_false(_grid().is_walkable(Vector2i(13, 6)), "removing the fitting restores the thick shell")
	assert_eq(Economy.cash, cash + refund)
	assert_eq(_saved_text(), saved)
	_native_key(KEY_Z, true)
	assert_eq(_grid().segment(edge), kind)
	assert_eq(Economy.cash, cash)
	assert_eq(_saved_text(), saved)


func _prepare_outer_frame(kind: SimGrid.Segment) -> MeshInstance3D:
	assert_true(_main.call("set_build_active", false))
	assert_true(_main.call("shop_walls", {Vector3i(13, 6, SimGrid.EDGE_WEST): kind} as Dictionary[Vector3i, int]),
		_editor().last_check.why)
	assert_true(_main.call("set_build_active", true))
	var view: ShopView = _main.get_node("ShopView") as ShopView
	view.set_wall_mode(ShopView.WallMode.UP)
	var name: String = "ShellWindow_13_6" if kind == SimGrid.Segment.WINDOW else "BackDoor_13_6"
	var root: Node3D = view.segment_view.get_node_or_null(name) as Node3D
	assert_not_null(root)
	return _frame_piece(root, true) if root != null else null


func _frame_piece(root: Node3D, highest: bool) -> MeshInstance3D:
	var selected: MeshInstance3D
	for child: Node in root.get_children():
		if not child is MeshInstance3D or child.name == &"Floor":
			continue
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var height: float = (mesh.global_transform * mesh.get_aabb().get_center()).y
		if selected == null:
			selected = mesh
		else:
			var previous: float = (selected.global_transform * selected.get_aabb().get_center()).y
			if (highest and height > previous) or (not highest and height < previous):
				selected = mesh
	return selected


func _legacy_snapshot_with_lost_face() -> Dictionary:
	var layout: ShopLayout = (load("res://data/layouts/tier1_hole_in_the_wall.tres") as ShopLayout).duplicate(true) as ShopLayout
	layout.rows[4] = "#####...######"
	layout.room_rows = PackedStringArray(["", " KKKKKKKKKKKK", " KKKKKKKKKKKK", " KKKKKKKKKKKK", "     KKK"])
	layout.wall_segments.clear()
	layout.rooms_explicit = false
	layout.room_cells.clear()
	var content: ContentDB = _main.get("content") as ContentDB
	var errors: Array[String] = []
	var legacy: RestaurantSim = RestaurantSim.create(layout, content, 99, errors)
	assert_eq(errors, [] as Array[String])
	var editor: ShopEditor = ShopEditor.new(legacy, content, ShopEditBooks.new(_allow_spend, _ignore_record), layout)
	editor.set_owner_level(6)
	assert_true(editor.apply_rooms({Vector2i(2, 5): SimGrid.Room.KITCHEN,
		Vector2i(3, 5): SimGrid.Room.KITCHEN} as Dictionary[Vector2i, int]))
	var face: Vector3i = Vector3i(3, 3, 2)
	var faces: Array[Vector3i] = [face]
	assert_true(editor.apply_wall_finishes(editor.wall_lay_changes(faces, &"brick", &"sage", &"cream")))
	assert_true(editor.hang(&"wall_art_sunrise", face), editor.last_check.why)
	var snapshot: Dictionary = editor.to_dict()
	snapshot["version"] = 6
	return snapshot


func _allow_spend(_amount: int) -> bool:
	return true


func _ignore_record(_amount: int, _category: StringName, _note: String = "") -> void:
	pass


func _write_document(document: Dictionary) -> void:
	var path: String = _save_dir.path_join(SLOT + ".json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")


func _close_fixture() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	_viewport = null


func _focus(point: Vector2) -> void:
	_rig().initial_focus = point
	_rig().reset_view()


func _project(point: Vector2, height: float = 0.0) -> Vector2:
	return (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(Vector3(point.x, height, point.y))


func _assert_clear(point: Vector2) -> void:
	assert_true(_viewport.get_visible_rect().has_point(point))
	for path: String in ["HUD/Top", "HUD/BuildHints", "Overlay/BuildCatalogue/Panel"]:
		assert_false((_main.get_node(path) as Control).get_global_rect().has_point(point), path)


func _native_click(point: Vector2) -> void:
	_native_mouse(point, true)
	_native_mouse(point, false)


func _native_mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	_viewport.push_input(event, true)
	_last_native_point = point


func _native_pointer(point: Vector2, pressed: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _last_native_point
	event.screen_relative = event.relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_viewport.push_input(event, true)
	_last_native_point = point


func _native_key(code: Key, ctrl: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		_viewport.push_input(event, true)


func _remove_button() -> Button:
	return _catalogue().get("wall_remove_button") as Button


func _catalogue() -> BuildCatalogue:
	return _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue


func _mode() -> BuildMode:
	return _main.get("build_mode") as BuildMode


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _grid() -> SimGrid:
	return (_main.get("world") as SimWorld).grid


func _rig() -> CameraRig:
	return _main.get_node("CameraRig") as CameraRig


func _camera() -> Camera3D:
	return _main.get_node("CameraRig/Camera3D") as Camera3D


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
