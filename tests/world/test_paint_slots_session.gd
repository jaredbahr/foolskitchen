extends TestCase
## Paint slots (#431) in the real Main: the Part and Material rows, hover
## preview, Shift for every piece of a kind in the room, Alt-click copy and
## paste, undo, and the drawn materials.

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


func test_parts_materials_shift_and_undo_through_the_real_panel() -> void:
	await _start()
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(_world(), &"table_2")
	assert_true(tables.size() >= 2)
	var cash: int = Economy.cash
	assert_true(_main.call("set_paint_active", true))
	_main.call("preview_paint_cell", tables[0].origin)
	assert_eq(_catalogue().paint_target(), _content().item(&"table_2"), "hovering names the table's parts")
	assert_eq(_catalogue().part_buttons[0].text, "Table")
	assert_eq(_catalogue().part_buttons[1].text, "Cushions")
	assert_false(_catalogue().part_buttons[2].visible)
	_catalogue().part_buttons[1].pressed.emit()
	_catalogue().material_buttons[PaintFinish.FABRIC].pressed.emit()
	_catalogue().swatch_buttons[&"tomato"].pressed.emit()
	assert_eq(_title(), "Paint | Tomato fabric on the cushions - Click a wall, floor or item")
	_main.call("preview_paint_cell", tables[0].origin, true)
	assert_true(tables[1].paint.is_empty(), "hover never changes the shop")
	assert_eq(_carpet(tables[1]).albedo_color, _colour(&"tomato"), "Shift previews every table in the room")
	assert_true(_main.call("paint_cell", tables[0].origin, true))
	for table: PlacedItem in tables:
		assert_eq(table.paint.swatch(&"cushion"), &"tomato")
		assert_eq(table.paint.material(&"cushion"), PaintFinish.FABRIC)
	assert_eq(_carpet(tables[0]).albedo_texture, PaintMaterials.texture(PaintFinish.FABRIC))
	assert_eq(Economy.cash, cash, "recolouring stays free")
	_key(KEY_Z, true)
	for table: PlacedItem in tables:
		assert_true(table.paint.is_empty(), "one undo step takes back the whole Shift paint")
	# A plant has one part: the chosen second part falls back to its main one.
	var plant: PlacedItem = ShopBuilder.items_with_def(_world(), &"potted_plant")[0]
	_catalogue().swatch_buttons[&"sage"].pressed.emit()
	_main.call("preview_paint_cell", plant.origin)
	assert_true(_catalogue().part_buttons[0].button_pressed, "the plant's pot is what a click paints")
	assert_true(_main.call("paint_cell", plant.origin))
	assert_eq(plant.swatch_id, &"sage")


func test_alt_click_copies_a_look_and_pastes_it() -> void:
	await _start()
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(_world(), &"table_2")
	assert_true(_main.call("set_paint_active", true))
	_catalogue().part_buttons[1].pressed.emit()
	_catalogue().swatch_buttons[&"mint"].pressed.emit()
	assert_true(_main.call("paint_cell", tables[0].origin))
	_catalogue().part_buttons[0].pressed.emit()
	_catalogue().material_buttons[PaintFinish.PAINTED].pressed.emit()
	_catalogue().swatch_buttons[&"navy"].pressed.emit()
	assert_true(_main.call("paint_cell", tables[0].origin))
	assert_true(_main.call("copy_paint_look", tables[0].origin))
	assert_eq(_title(), "Paint | Two-seat table look copied - Click pieces to paste it")
	assert_true(_main.call("paint_cell", tables[1].origin))
	assert_eq(tables[1].swatch_id, &"navy")
	assert_true(tables[1].paint.equals(tables[0].paint))
	_catalogue().swatch_buttons[&"butter"].pressed.emit()
	assert_true(_catalogue().copied_look.is_empty(), "picking a colour drops the copied look")


func test_copy_look_button_copies_the_next_piece_clicked() -> void:
	await _start()
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(_world(), &"table_2")
	assert_true(_main.call("set_paint_active", true))
	_catalogue().part_buttons[1].pressed.emit()
	_catalogue().swatch_buttons[&"berry"].pressed.emit()
	assert_true(_main.call("paint_cell", tables[0].origin))
	var wall: StringName = _editor().wall_swatch_id
	_catalogue().copy_look_button.pressed.emit()
	assert_true(_catalogue().copy_look_button.button_pressed)
	assert_eq(_title(), CatalogueText.PAINT_COPY_ARMED)
	assert_false(_main.call("paint_cell", Vector2i(0, 6)), "a wall click while copying paints nothing")
	assert_eq(_editor().wall_swatch_id, wall)
	assert_true(_main.call("paint_cell", tables[0].origin), "the click copies")
	assert_eq(tables[0].paint.swatch(&"cushion"), &"berry", "copying changes nothing")
	assert_eq(_title(), "Paint | Two-seat table look copied - Click pieces to paste it")
	assert_true(_main.call("paint_cell", tables[1].origin))
	assert_eq(tables[1].paint.swatch(&"cushion"), &"berry")


func _title() -> String:
	return (_catalogue().get_node("Panel/Margin/Rows/Scroll/Content/Title") as Label).text


func _colour(id: StringName) -> Color:
	var colour: Color = _content().swatch(id).color
	return Color(colour.r, colour.g, colour.b, 1.0)


func _carpet(placed: PlacedItem) -> BaseMaterial3D:
	var visual: ItemVisual = (_main.get_node("ShopView") as ShopView).item_nodes[placed.id]
	for mesh_node: MeshInstance3D in visual.rendered_meshes():
		for index: int in mesh_node.mesh.get_surface_count():
			var imported: Material = mesh_node.mesh.surface_get_material(index)
			if imported != null and imported.resource_name == "carpet":
				return mesh_node.get_active_material(index) as BaseMaterial3D
	return null


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


