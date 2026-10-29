extends TestCase
## FK-045 real Main request wiring, input, exact undo and amber restock advice.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _main: Node3D
var _viewport: SubViewport


func before_each() -> void:
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_blueprint_catalogue_requests_select_save_stamp_and_exact_undo() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	_catalogue().set_category(BuildCatalogue.BLUEPRINTS)
	var plant: PlacedItem = _world().grid.item(_id(&"potted_plant"))
	_catalogue().blueprint_select.pressed.emit()
	assert_eq(_mode().state, BuildMode.State.SELECT)
	_mouse(_project(plant.origin), true)
	assert_true(_mode().blueprint_dragging)
	assert_true(_catalogue().blueprint_save.disabled)
	_mouse(_project(plant.origin), false)
	assert_eq(_mode().blueprint_selection, [plant.id] as Array[int])
	assert_false(_catalogue().blueprint_save.disabled)
	_catalogue().blueprint_name.text = "Leafy corner"
	_catalogue().blueprint_save.pressed.emit()
	var library: BlueprintLibrary = _main.get("blueprint_library")
	assert_eq(library.blueprints.size(), 1)
	assert_eq(library.blueprints[0].display_name, "Leafy corner")
	_catalogue().blueprint_buttons[0].pressed.emit()
	assert_eq(_mode().state, BuildMode.State.BLUEPRINT)
	_editor().set_owner_level(2)
	assert_true(_main.call("update_build_pointer", _project(Vector2i(4, 9))))
	_key(KEY_R)
	assert_eq(_mode().quarter_turns, 1)
	_key(KEY_COMMA)
	assert_eq(_mode().quarter_turns, 0)
	_key(KEY_PERIOD)
	assert_eq(_mode().quarter_turns, 1)
	var cash: int = Economy.cash
	_click(_project(Vector2i(4, 9)))
	assert_eq(_mode().state, BuildMode.State.IDLE)
	assert_not_null(_world().grid.item_at(Vector2i(4, 9)))
	assert_eq(Economy.cash, cash - _content().item(&"potted_plant").price)
	assert_eq((_main.get("edit_history") as ShopEditHistory).undo_count(), 1)
	_key(KEY_Z, true)
	assert_null(_world().grid.item_at(Vector2i(4, 9)))
	assert_eq(Economy.cash, cash)


func test_blueprint_restock_advice_is_amber_below_cost_and_never_blocks_stamp() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	_editor().set_owner_level(2)
	var blueprint: Blueprint = Blueprint.capture(_world().grid, [_id(&"potted_plant")] as Array[int], "Green corner")
	assert_true(_mode().begin_blueprint(blueprint, Vector2i(4, 9)))
	var cost: int = blueprint.total_price(_content())
	var estimate: int = _main.call("build_restock_estimate")
	Economy.add_cash(estimate + cost - 1 - Economy.cash, Ledger.OTHER)
	assert_true(_mode().current_check.ok, _mode().current_check.why)
	var warning: String = RestockBudgetWarning.text(Economy.cash, cost, estimate)
	var label: Label = _main.get_node("HUD/BuildHints/Scroll/Lines/Warning") as Label
	assert_eq(label.text, warning)
	assert_false(warning.is_empty())
	assert_true(label.visible)
	assert_eq(label.get_theme_color("font_color"), _main.get_node("HUD").get("ADVICE_COLOR"))
	assert_true(_hint().contains(Fmt.money(cost)))
	assert_false(_hint().contains(warning))
	assert_true(_mode().commit())
	assert_eq(Economy.cash, estimate - 1)


func test_name_focus_protects_world_keys_and_deleted_held_blueprint_cancels() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	_catalogue().set_category(BuildCatalogue.BLUEPRINTS)
	var library: BlueprintLibrary = _main.get("blueprint_library")
	var blueprint: Blueprint = Blueprint.capture(_world().grid, [_id(&"potted_plant")] as Array[int], "Plants")
	assert_true(library.add(blueprint))
	_catalogue().blueprint_buttons[0].pressed.emit()
	await (Engine.get_main_loop() as SceneTree).process_frame
	_catalogue().blueprint_name.grab_focus()
	assert_true(_catalogue().blueprint_name_has_focus())
	for code: Key in [KEY_R, KEY_B, KEY_P, KEY_ESCAPE]:
		_key(code)
	assert_eq(_mode().state, BuildMode.State.BLUEPRINT)
	assert_eq(_mode().quarter_turns, 0)
	assert_false(_main.call("is_paint_active"))
	_catalogue().blueprint_name.release_focus()
	var row: HBoxContainer = _catalogue().blueprint_rows.get_child(0) as HBoxContainer
	(row.get_node("Delete") as Button).pressed.emit()
	assert_true(library.blueprints.is_empty())
	assert_eq(_mode().state, BuildMode.State.IDLE)
	assert_true(_preview().blueprint_ghosts.is_empty())


func test_release_over_panel_finishes_selection_and_service_refuses_library_mutation() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	_catalogue().set_category(BuildCatalogue.BLUEPRINTS)
	var plant: PlacedItem = _world().grid.item(_id(&"potted_plant"))
	_catalogue().blueprint_select.pressed.emit()
	_mouse(_project(plant.origin), true)
	assert_true(_mode().blueprint_dragging)
	# Native GUI consumed mouse-up: the frame guard sees the physical button up.
	_main.call("_process", 0.0)
	assert_false(_mode().blueprint_dragging)
	assert_false(_catalogue().blueprint_save.disabled)
	_catalogue().blueprint_save.pressed.emit()
	var library: BlueprintLibrary = _main.get("blueprint_library")
	var blueprint: Blueprint = library.blueprints[0]
	assert_true(Clock.sim.start_service())
	_main.call("_on_blueprint_rename_requested", blueprint, "Changed while open")
	_main.call("_on_blueprint_delete_requested", blueprint)
	assert_eq(library.blueprints.size(), 1)
	assert_ne(blueprint.display_name, "Changed while open")
	assert_eq(_mode().state, BuildMode.State.INACTIVE)


func _mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	_main.call("route_build_input", event)


func _plant_still_at(plant: PlacedItem) -> bool:
	return _world().grid.item(plant.id) == plant


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


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _content() -> ContentDB:
	return _main.get("content") as ContentDB


func _mode() -> BuildMode:
	return _main.get("build_mode") as BuildMode


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _catalogue() -> BuildCatalogue:
	return _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue


func _preview() -> BuildPreview:
	return _main.get_node("BuildPreview") as BuildPreview


func _hint() -> String:
	return (_main.get_node("HUD/BuildHints/Scroll/Lines/Text") as Label).text


func _id(def_id: StringName) -> int:
	return ShopBuilder.items_with_def(_world(), def_id)[0].id


func _project(cell: Vector2i) -> Vector2:
	return (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(GridMath.cell_to_world(cell))


func _click(point: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	_main.call("_unhandled_input", event)


func _right_click(point: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_RIGHT
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	event.pressed = true
	_main.call("_unhandled_input", event)


func _key(code: Key, ctrl: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	_main.call("_unhandled_input", event)


func _rect(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in range(y, y + h):
		for column: int in range(x, x + w):
			out.append(Vector2i(column, row))
	return out
