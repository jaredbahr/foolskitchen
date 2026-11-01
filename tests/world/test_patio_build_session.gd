extends TestCase
## The real catalogue, projected drag input and morning session own patio edits.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "patio_build_session"

var _main: Node3D
var _viewport: SubViewport
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate(true)
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
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
	SaveSystem._providers = _old_providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_catalogue_drag_refund_undo_refusal_and_cancel_never_save() -> void:
	await _start()
	var checkpoint: String = _checkpoint()
	assert_false(checkpoint.is_empty(), "the ordinary morning checkpoint exists")
	var rng_before: Dictionary = GameState.call("_capture_save")
	var cash: int = Economy.cash
	assert_true(_main.call("set_build_active", true))
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.PATIO)
	assert_true(catalogue.patio_button.visible)
	assert_eq(catalogue.patio_button.text, "Build patio\n$15 a tile")
	catalogue.patio_button.pressed.emit()
	assert_eq(_mode().state, BuildMode.State.PATIO)
	var preview: BuildPreview = _main.get("_build_preview") as BuildPreview
	assert_not_null(preview.patio_lot)
	assert_false(_mode().patio_open_cells().has(Vector2i(6, 12)), "the street door approach is public")
	# The authored entry at (6, 11) reaches this 2×2 patch through (5, 11).
	# Four tiles preserve the purchase/refund arithmetic without a path fixture.
	_press(Vector2i(4, 11))
	_pointer(Vector2i(5, 12))
	assert_eq(_mode().patio_summary(), "Add 4 patio tiles  $60")
	assert_true(_mode().current_check.ok)
	assert_eq(preview.floor_ghost_cells.size(), 4)
	_release(Vector2i(5, 12))
	assert_eq(_editor().bought_patio().size(), 4)
	if _editor().bought_patio().size() != 4:
		return  # Keep the setup assertion; avoid misleading follow-on refusals.
	assert_eq(Economy.cash, cash - 60)
	assert_eq(_forecast(), WeatherText.forecast_for(_world().weather.kind, true))
	_press(Vector2i(5, 12), true)
	assert_eq(_mode().patio_summary(), "Remove 1 patio tile  (refund $7)")
	_release(Vector2i(5, 12))
	assert_eq(_editor().bought_patio().size(), 3)
	assert_eq(Economy.cash, cash - 53)
	_key(KEY_Z, true)
	assert_eq(_editor().bought_patio().size(), 4)
	assert_eq(Economy.cash, cash - 60, "undo restores exact cash, including odd cell prices")
	_key(KEY_Z, true)
	assert_eq(_editor().bought_patio().size(), 0)
	assert_eq(Economy.cash, cash)
	assert_eq(_forecast(), WeatherText.forecast_for(_world().weather.kind), "selling the last patio clears its status")
	assert_true(_main.call("begin_patio_tool"))
	_press(Vector2i(6, 11))
	assert_false(_mode().current_check.ok)
	assert_false(_mode().current_check.why.is_empty(), "the refusal is readable")
	assert_eq(preview.floor_ghost.get_meta("valid"), false)
	_release(Vector2i(6, 11))
	assert_eq(Economy.cash, cash)
	assert_true(_editor().bought_patio().is_empty())
	_press(Vector2i(5, 11))
	_key(KEY_ESCAPE)
	assert_eq(_mode().state, BuildMode.State.PATIO, "first Esc cancels the drag")
	assert_false(_mode().patio_dragging)
	_key(KEY_ESCAPE)
	assert_eq(_mode().state, BuildMode.State.IDLE, "second Esc closes the tool")
	assert_eq(_checkpoint(), checkpoint, "purchase, sale, undo and refusal add no save point")
	assert_eq(GameState.call("_capture_save"), rng_before, "previews and forecast refresh never draw RNG")


func test_morning_status_refreshes_for_rain_sun_and_last_cell_undo() -> void:
	await _start()
	_world().weather.kind = WeatherState.Kind.RAIN
	_main.call("_refresh_weather")
	assert_eq(_forecast(), "Rain today", "an older shop keeps its exact plain forecast")
	assert_true(_main.call("set_build_active", true))
	# This one tile borders the real public entry, rather than an isolated lot cell.
	var purchased: bool = _main.call("shop_patio", [Vector2i(5, 11)] as Array[Vector2i], true)
	assert_true(purchased, "the entry-adjacent patio cell must be buyable")
	if not purchased:
		return
	assert_eq(_forecast(), "Rain today  |  Patio closed in rain")
	_world().weather.kind = WeatherState.Kind.CLOUDY
	_main.call("_refresh_weather")
	assert_eq(_forecast(), "Cloudy today  |  Patio open today")
	assert_true(_main.call("undo_edit"))
	assert_eq(_forecast(), "Cloudy today")
	assert_true(_main.call("redo_edit"))
	assert_eq(_forecast(), "Cloudy today  |  Patio open today")
	assert_eq(WeatherText.forecast_for(WeatherState.Kind.SUNNY, true), "Sunny today  |  Patio open today")
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.ROOMS)
	assert_eq(catalogue.room_buttons.size(), SimGrid.Room.STORAGE + 1, "patio must be bought, never free room paint")
	assert_false(_mode().begin_rooms(SimGrid.Room.PATIO))


func test_owned_pavement_keeps_street_anchor_facade_and_outdoor_rain_mask() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var street_before: Dictionary = view.neighbourhood_dressing.capture_state()
	var windows_before: Array[Vector2i] = ExteriorSupport.window_cells(_world().grid)
	var door_before: Array[Vector2i] = _world().grid.entries()
	var floor_before: int = view.floor_mesh.mesh.get_surface_count()
	var vertices_before: int = view.floor_mesh.mesh.surface_get_array_len(0)
	# Connect the rendered test cell (2, 12) to the real entry (6, 11):
	# four cells along row 11, then one step down. This costs $75 from the
	# unchanged starter cash and does not require a disconnected floor island.
	var cells: Array[Vector2i] = [Vector2i(2, 11), Vector2i(3, 11), Vector2i(4, 11),
		Vector2i(5, 11), Vector2i(2, 12)]
	var purchased: bool = _main.call("shop_patio", cells, true)
	assert_true(purchased, "the connected pavement chain must be buyable from starter cash")
	if not purchased:
		return
	var street_after: Dictionary = view.neighbourhood_dressing.capture_state()
	assert_eq(street_after["frame"], street_before["frame"], "patio never pushes the road or pedestrian lanes forward")
	assert_eq(street_after["bounds"], street_before["bounds"], "the original pavement and road remain in place")
	assert_eq(ExteriorSupport.window_cells(_world().grid), windows_before)
	assert_eq(_world().grid.entries(), door_before, "buying pavement creates no new entry")
	assert_eq(view.floor_mesh.mesh.get_surface_count(), floor_before)
	assert_eq(view.floor_mesh.mesh.surface_get_array_len(0), vertices_before, "unpainted patio adds no wooden indoor tiles")
	assert_null(view.patio_floor_mesh)
	assert_eq(view.room_dressing.name_sign_nodes().size(), 1, "the existing sign keeps its facade support")
	_world().weather.kind = WeatherState.Kind.RAIN
	_main.call("_refresh_weather")
	var drop: AABB = AABB(Vector3(1.1, 0.2, 6.1), Vector3(0.01, 1.0, 0.01))
	assert_true(view.weather_view.call("_outside_bounds", drop), "patio remains outside the built-roof rain mask")
	var indoors: AABB = AABB(Vector3(1.1, 0.2, 3.1), Vector3(0.01, 1.0, 0.01))
	assert_false(view.weather_view.call("_outside_bounds", indoors))
	var changes: Dictionary[Vector2i, FloorFinishes.Finish] = _editor().lay_changes(
		[Vector2i(2, 12)] as Array[Vector2i], &"herringbone", &"honey")
	assert_true(_main.call("shop_flooring", changes))
	assert_not_null(view.patio_floor_mesh, "explicitly painted patio reuses the existing floor shader")
	if view.patio_floor_mesh == null:
		return  # The failed setup assertion is sufficient; do not raise a Nil error.
	assert_eq(view.patio_floor_mesh.material_override, view.floor_mesh.material_override)
	assert_true((view.patio_floor_mesh.layers & WeatherView.OUTDOOR_LAYER) != 0)


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
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 243)
	_viewport.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_speed(0)
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	rig.edge_pan_enabled = false
	(_main.get_node("ShopView") as ShopView).set_process(false)
	for frame: int in range(3):
		await tree.process_frame


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _mode() -> BuildMode:
	return _main.get("build_mode") as BuildMode


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _forecast() -> String:
	return (_main.get_node("Overlay/MenuPanel/Panel/Content/WeatherForecast") as Label).text


func _checkpoint() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _project(cell: Vector2i) -> Vector2:
	return (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(GridMath.cell_to_world(cell))


func _pointer(cell: Vector2i, shift: bool = false) -> void:
	assert_true(_main.call("update_build_pointer", _project(cell), shift))


func _press(cell: Vector2i, shift: bool = false) -> void:
	_pointer(cell, shift)
	_mouse(cell, true, shift)


func _release(cell: Vector2i) -> void:
	_mouse(cell, false)


func _mouse(cell: Vector2i, pressed: bool, shift: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = _project(cell)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.shift_pressed = shift
	assert_true(_main.call("route_build_input", event))


func _key(code: Key, control: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = control
	assert_true(_main.call("route_build_input", event))
