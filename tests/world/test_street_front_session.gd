extends TestCase
## Real Main requests, native world input, rendered picking and morning-only saves.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "street_front_session"
const FRONT: Vector3i = Vector3i(3, 11, 0)

var _main: Node3D
var _viewport: SubViewport
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary[String, Dictionary] = {}
var _mouse_position: Vector2 = Vector2.ZERO


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate(true)
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "street_front_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _old_providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_purchased_sign_tracks_live_menu_rename_rebuild_and_next_morning_reload() -> void:
	await _start(true)
	var sign: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), ExteriorSupport.Band.HEADER)
	var morning: String = _saved_text()
	assert_true(_main.call("shop_hang", &"shop_name_sign", sign))
	assert_eq(_saved_text(), morning, "buying a name sign never writes an action save")
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var random: Dictionary = GameState.call("_capture_save")
	var menu: MenuPanel = _main.get_node("Overlay/MenuPanel") as MenuPanel
	menu.restaurant_name_requested.emit("  Copper & Thyme  ")
	assert_eq((_main.get("menu_settings") as MenuSettings).restaurant_name(), "Copper & Thyme")
	assert_eq(_name_label(sign).text, "Copper & Thyme")
	assert_eq(_name_label(sign).get_meta(&"full_name"), "Copper & Thyme")
	assert_eq(_saved_text(), morning)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState.call("_capture_save"), random)
	_view().wall_finish_view.rebuild()
	assert_eq(_name_label(sign).text, "Copper & Thyme", "rebuilding keeps the canonical menu name")
	var free_signs: Array[Label3D] = _view().room_dressing.name_sign_nodes()
	assert_false(free_signs.is_empty(), "the original free name board remains present")
	assert_eq(free_signs[0].text, "Copper & Thyme")
	_next_morning()
	var saved: Dictionary = JSON.parse_string(_saved_text())
	assert_eq(saved["data"]["menu"]["name"], "Copper & Thyme")
	var saved_rows: Array = saved["data"]["shop"]["wall_items"]
	var expected_row: Array = [float(sign.x), float(sign.y), float(sign.z), "shop_name_sign", 2.0, ""]
	var numeric_types: Array[int] = []
	var first_row: Array = saved_rows[0] if not saved_rows.is_empty() else []
	for value: Variant in first_row:
		numeric_types.append(typeof(value))
	assert_eq(saved_rows, [expected_row], "morning sign row: actual%s expected%s actual element types%s" %
		[saved_rows, expected_row, numeric_types])
	_close()
	await _start(true)
	assert_eq(_name_label(sign).text, "Copper & Thyme")
	assert_eq(_editor().decor.count(), 1)


func test_awning_colour_and_exterior_finish_join_only_the_existing_morning_checkpoint() -> void:
	await _start(true)
	var canopy: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), ExteriorSupport.Band.CANOPY)
	var morning: String = _saved_text()
	assert_true(_main.call("shop_hang", &"street_awning_2", canopy, &"sage"))
	_assert_awning_colour(canopy, &"sage")
	assert_true((_main.get("edit_history") as ShopEditHistory).apply_wall_finishes({FRONT:
		FloorFinishes.Finish.new(&"brick", &"sage", &"cream")} as Dictionary[Vector3i, FloorFinishes.Finish]))
	assert_true((_main.get("edit_history") as ShopEditHistory).paint_hung(canopy, &"clay"))
	assert_eq(_saved_text(), morning)
	assert_eq(_editor().decor.item(canopy).swatch_id, &"clay")
	_assert_awning_colour(canopy, &"clay")
	_next_morning()
	var expected: Array[Array] = _editor().decor.to_rows()
	_close()
	await _start(true)
	assert_eq(_editor().decor.to_rows(), expected)
	assert_eq(_editor().decor.item(canopy).swatch_id, &"clay")
	_assert_awning_colour(canopy, &"clay")
	assert_eq(_editor().walls.finish(FRONT).style, &"brick")
	assert_eq(_editor().walls.finish(FRONT).swatch, &"sage")


func test_native_outside_paint_keeps_whole_building_behavior_and_per_face_override() -> void:
	await _start(true)
	assert_true((_main.get("edit_history") as ShopEditHistory).apply_wall_finishes({FRONT:
		FloorFinishes.Finish.new(&"brick", &"sage", &"cream")} as Dictionary[Vector3i, FloorFinishes.Finish]))
	_main.call("refresh_presentation")
	assert_true(_main.call("set_paint_active", true))
	(_main.get_node("Overlay/BuildCatalogue") as BuildCatalogue).swatch_buttons[&"clay"].pressed.emit()
	var target: Vector3 = WallFinishView.face_frame(_world().grid, FRONT, false,
		{} as Dictionary[Vector2i, bool])["origin"] + Vector3.UP * 0.7
	await _focus(target)
	var point: Vector2 = _camera().unproject_position(target)
	_assert_clear(point)
	var origin: Vector3 = _camera().project_ray_origin(point)
	var direction: Vector3 = _camera().project_ray_normal(point)
	var hit: Dictionary = _view().wall_face_at_ray(origin, direction)
	assert_eq(hit.get("face", WallFaces.NO_FACE), FRONT, "the actual shell ray identifies its street face")
	assert_eq(_main.call("paint_face_at_screen_position", point), WallFaces.NO_FACE,
		"whole-building Paint keeps its original outside route")
	var books: Dictionary = Economy.ledger.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var random: Dictionary = GameState.call("_capture_save")
	var morning: String = _saved_text()
	await _native_click(point)
	assert_eq(_editor().wall_swatch_id, &"clay")
	assert_eq(_editor().walls.finish(Vector3i(3, 9, 2)).swatch, &"clay")
	assert_eq(_editor().walls.finish(FRONT).swatch, &"sage")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState.call("_capture_save"), random)
	assert_eq(_saved_text(), morning)


func test_native_paint_hits_the_actual_awning_model_and_changes_only_its_swatch() -> void:
	await _start(true)
	var canopy: Vector3i = ExteriorSupport.key_for(Vector3i(6, 11, 0), ExteriorSupport.Band.CANOPY)
	assert_true(_main.call("shop_hang", &"street_awning_2", canopy, &"sage"))
	_assert_awning_colour(canopy, &"sage")
	assert_true(_main.call("set_paint_active", true))
	(_main.get_node("Overlay/BuildCatalogue") as BuildCatalogue).swatch_buttons[&"clay"].pressed.emit()
	var visual: ItemVisual = _view().wall_finish_view.item_nodes[canopy]
	var mesh: MeshInstance3D = _largest_mesh(visual)
	assert_not_null(mesh)
	if mesh == null:
		return
	var target: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
	await _focus(target)
	var point: Vector2 = _camera().unproject_position(target)
	_assert_clear(point)
	assert_eq(_view().wall_item_at_ray(_camera().project_ray_origin(point), _camera().project_ray_normal(point)), canopy)
	var wall_colour: StringName = _editor().wall_swatch_id
	var books: Dictionary = Economy.ledger.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var random: Dictionary = GameState.call("_capture_save")
	var morning: String = _saved_text()
	await _native_click(point)
	assert_eq(_editor().decor.item(canopy).swatch_id, &"clay")
	_assert_awning_colour(canopy, &"clay")
	assert_eq(_editor().wall_swatch_id, wall_colour)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState.call("_capture_save"), random)
	assert_eq(_saved_text(), morning)


func test_real_window_neon_picking_respects_foreground_furniture_and_opaque_shell() -> void:
	await _start()
	var edge: Vector3i = Vector3i(11, 10, SimGrid.EDGE_NORTH)
	var slot: Vector3i = Vector3i(11, 9, 2)
	assert_true(_main.call("shop_walls", {edge: SimGrid.Segment.WINDOW} as Dictionary[Vector3i, int]))
	assert_true(_main.call("shop_hang", &"neon_open_sign", slot))
	var neon: ItemVisual = _view().wall_finish_view.item_nodes[slot]
	var target: Vector3 = _largest_mesh(neon).global_transform * _largest_mesh(neon).get_aabb().get_center()
	var from_street: Vector3 = target + Vector3(0, 0.15, 2.0)
	assert_eq(_view().wall_item_at_ray(from_street, (target - from_street).normalized()), slot)
	assert_true(_main.call("shop_buy", &"coat_rack_standing", Vector2i(11, 8)))
	var rack: PlacedItem = _world().grid.item_at(Vector2i(11, 8))
	assert_not_null(rack)
	if rack == null:
		return
	var blocker: MeshInstance3D = _largest_mesh(_view().item_nodes[rack.id])
	var centre: Vector3 = blocker.global_transform * blocker.get_aabb().get_center()
	var origin: Vector3 = centre + (centre - target).normalized() * 0.3
	var direction: Vector3 = (target - origin).normalized()
	assert_true(_view().nearest_item_distance(origin, direction) < origin.distance_to(target))
	assert_true(_view().wall_distance(origin, direction) >= origin.distance_to(target) - 0.01,
		"the real window path is clear of opaque wall, so furniture is the blocker")
	assert_eq(_view().wall_item_at_ray(origin, direction), WallFaces.NO_FACE)
	var body: Vector3i = Vector3i(8, 11, 0)
	assert_true(_main.call("shop_hang", &"neon_open_sign", body))
	var exterior: ItemVisual = _view().wall_finish_view.item_nodes[body]
	var outside_target: Vector3 = _largest_mesh(exterior).global_transform * _largest_mesh(exterior).get_aabb().get_center()
	var inside_origin: Vector3 = GridMath.cell_to_world(Vector2i(8, 8)) + Vector3.UP * outside_target.y
	assert_true(_view().wall_distance(inside_origin, (outside_target - inside_origin).normalized()) < inside_origin.distance_to(outside_target))
	assert_eq(_view().wall_item_at_ray(inside_origin, (outside_target - inside_origin).normalized()), WallFaces.NO_FACE)


func _start(with_saves: bool = false) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", with_saves)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 240)
	_viewport.add_child(_main)
	_main.call("start")
	_editor().set_owner_level(6)
	_main.set_process(false)
	_rig().set_process(false)
	_rig().edge_pan_enabled = false
	_view().set_process(false)
	_view().set_wall_mode(ShopView.WallMode.UP)
	Clock.set_speed(0)
	await _frames(4)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	_viewport = null


func _focus(target: Vector3) -> void:
	_rig().initial_focus = Vector2(target.x, target.z)
	_rig().initial_yaw_degrees = 45.0
	_rig().reset_view()
	await _frames(3)


func _native_click(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = point - _mouse_position
	motion.screen_relative = motion.relative
	_mouse_position = point
	_viewport.push_input(motion, true)
	await _frames(2)
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		_viewport.push_input(event, true)
	await _frames(2)


func _assert_clear(point: Vector2) -> void:
	assert_true(_viewport.get_visible_rect().has_point(point))
	for path: String in ["HUD/Top", "HUD/BuildHints", "Overlay/BuildCatalogue/Panel"]:
		var control: Control = _main.get_node(path) as Control
		assert_false(control.visible and control.get_global_rect().has_point(point), path + " leaves the world click clear")


func _largest_mesh(visual: ItemVisual) -> MeshInstance3D:
	var largest: MeshInstance3D
	var volume: float = -1.0
	for mesh: MeshInstance3D in visual.rendered_meshes():
		var box: AABB = mesh.get_aabb()
		if box.get_volume() > volume:
			volume = box.get_volume()
			largest = mesh
	return largest


func _next_morning() -> void:
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _name_label(anchor: Vector3i) -> Label3D:
	var visual: ItemVisual = _view().wall_finish_view.item_nodes[anchor]
	assert_not_null(visual.restaurant_name_label)
	return visual.restaurant_name_label


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _view() -> ShopView:
	return _main.get_node("ShopView") as ShopView


func _rig() -> CameraRig:
	return _main.get_node("CameraRig") as CameraRig


func _camera() -> Camera3D:
	return _main.get_node("CameraRig/Camera3D") as Camera3D


func _frames(count: int) -> void:
	for frame: int in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _assert_awning_colour(anchor: Vector3i, swatch_id: StringName) -> void:
	var visual: ItemVisual = _view().wall_finish_view.item_nodes[anchor]
	var material: BaseMaterial3D = visual.primary_body_material()
	assert_not_null(material, "the real awning exposes its named body surface")
	if material != null:
		var content: ContentDB = _main.get("content") as ContentDB
		assert_eq(material.albedo_color, content.swatch(swatch_id).color,
			"the actual rendered body uses the canonical selected swatch")
