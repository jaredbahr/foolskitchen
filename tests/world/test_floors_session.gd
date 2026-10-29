extends TestCase
## D25: the Floors tool and floor paint in the real Main. Build > Floors cards
## start the tool; a drag lays the chosen floor type, Shift-click fills a room,
## Alt-click copies a floor's look into the tool and the tab, Esc backs out,
## Ctrl+Z undoes with exact cash; locked cards stay disabled; Paint recolours
## the connected floor (Shift: the whole room) even while the shop is open.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

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


func test_floors_tool_lays_fills_copies_cancels_and_undoes() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	assert_true(_main.call("set_build_active", true))
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.FLOORS)
	assert_eq(catalogue.category_buttons[&"floor"].text, "Expand", "the lot tool is Expand now")
	assert_eq(catalogue.category_buttons[&"floors"].text, "Floors")
	assert_true(catalogue.floor_style_buttons[&"herringbone"].visible)
	assert_true(catalogue.floor_style_buttons[&"checker"].disabled, "locked at level 1")
	assert_eq(catalogue.floor_style_buttons[&"checker"].text, "Checker tiles\nLevel 3")
	assert_eq(catalogue.floor_style_buttons[&"narrow_planks"].text, "Narrow planks\n$1 a tile")
	catalogue.floor_style_buttons[&"checker"].pressed.emit()
	assert_eq(_mode().state, BuildMode.State.IDLE, "a locked card starts nothing")
	catalogue.floor_style_buttons[&"herringbone"].pressed.emit()
	assert_eq(_mode().state, BuildMode.State.FLOORS)
	assert_eq([_mode().floor_style, _mode().floor_swatch, _mode().floor_accent], [&"herringbone", &"honey", &"walnut"],
		"herringbone starts as honey oak parquet with walnut seams")
	# Hover previews on the floor itself, nothing changes yet.
	var cash: int = Economy.cash
	_pointer(Vector2i(2, 6))
	assert_eq((_main.get_node("ShopView") as ShopView).floor_preview_cells(), [Vector2i(2, 6)] as Array[Vector2i])
	assert_eq(_editor().floors.count(), 0)
	# A drag lays the rectangle.
	_press(Vector2i(2, 6))
	_pointer(Vector2i(3, 7))
	assert_eq(_mode().floors_summary(), "Lay 4 tiles of Herringbone: $12")
	_release(Vector2i(3, 7))
	assert_eq(_editor().floors.count(), 4)
	assert_eq(Economy.cash, cash - 12)
	assert_eq(_editor().floors.finish(Vector2i(3, 7)).style, &"herringbone")
	# A colour chip changes what the running tool lays; Shift-click fills the room.
	catalogue.floor_colour_buttons[&"walnut"].pressed.emit()
	assert_eq(_mode().floor_swatch, &"walnut")
	var kitchen: Array[Vector2i] = _editor().floor_room_cells(Vector2i(3, 2))
	_press(Vector2i(3, 2), true)
	_release(Vector2i(3, 2))
	assert_eq(_editor().floors.finish(Vector2i(12, 3)).style, &"herringbone")
	assert_eq(_editor().floors.finish(Vector2i(12, 3)).swatch, &"walnut")
	assert_eq(Economy.cash, cash - 12 - 3 * kitchen.size())
	assert_eq(_editor().floors.finish(Vector2i(3, 6)).swatch, &"honey", "the dining room is another room")
	# Alt-click copies a floor's look into the tool and the tab.
	catalogue.floor_style_buttons[&"narrow_planks"].pressed.emit()
	_main.call("_unhandled_input", _mouse_event(_project(Vector2i(2, 6)), true, false, true))
	assert_eq([_mode().floor_style, _mode().floor_swatch], [&"herringbone", &"honey"])
	assert_eq([catalogue.selected_floor_style, catalogue.selected_floor_swatch], [&"herringbone", &"honey"])
	assert_true(catalogue.floor_style_buttons[&"herringbone"].button_pressed)
	# Esc backs out of the tool (and its floor preview), then out of Build.
	_pointer(Vector2i(8, 8))
	assert_false((_main.get_node("ShopView") as ShopView).floor_preview_cells().is_empty())
	_key(KEY_ESCAPE)
	assert_eq(_mode().state, BuildMode.State.IDLE)
	assert_eq((_main.get_node("ShopView") as ShopView).floor_preview_cells(), [] as Array[Vector2i])
	# Ctrl+Z puts the kitchen back exactly, money too.
	var undo: InputEventKey = InputEventKey.new()
	undo.physical_keycode = KEY_Z
	undo.ctrl_pressed = true
	undo.pressed = true
	_main.call("_unhandled_input", undo)
	assert_eq(_editor().floors.finish(Vector2i(12, 3)).style, FloorStyleDef.DEFAULT_ID)
	assert_eq(Economy.cash, cash - 12)
	_key(KEY_ESCAPE)
	assert_false(_main.call("is_build_active"))


func test_paint_recolours_the_connected_floor_or_the_room_while_open() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("shop_flooring", _editor().lay_changes(_rect(2, 8, 2, 2), &"herringbone", &"walnut")))
	assert_true(_main.call("set_build_active", false))
	Clock.sim.start_service()
	assert_true(_main.call("set_paint_active", true))
	_main.set("_paint_swatch_id", &"sage")
	var cash: int = Economy.cash
	_main.call("preview_paint_cell", Vector2i(2, 8))
	assert_eq((_main.get_node("ShopView") as ShopView).floor_preview_cells().size(), 4, "hover shows the area")
	assert_true(_main.call("paint_cell", Vector2i(2, 8)))
	for cell: Vector2i in _rect(2, 8, 2, 2):
		assert_eq(_editor().floors.finish(cell).swatch, &"sage")
		assert_eq(_editor().floors.finish(cell).style, &"herringbone", "the floor type stays")
	assert_eq(_editor().floors.finish(Vector2i(5, 8)).swatch, _editor().floor_swatch_id, "planks are another area")
	assert_true(_main.call("paint_cell", Vector2i(9, 8), true))
	assert_eq(_editor().floors.finish(Vector2i(5, 8)).swatch, &"sage", "Shift paints the whole room")
	assert_eq(_editor().floors.finish(Vector2i(2, 8)).style, &"herringbone")
	assert_eq(_editor().floors.finish(Vector2i(3, 2)).swatch, _editor().floor_swatch_id, "not the kitchen")
	assert_eq(Economy.cash, cash, "recolouring is free")
	assert_eq(_editor().floor_vibe_swatch(), &"sage")
	assert_true(_main.call("set_paint_active", false))


func test_paint_click_in_the_dining_room_leaves_the_kitchen_alone() -> void:
	await _start()
	assert_true(_main.call("set_paint_active", true))
	_main.set("_paint_swatch_id", &"sage")
	var dining: Array[Vector2i] = _editor().floor_room_cells(Vector2i(9, 8))
	var kitchen: Array[Vector2i] = _editor().floor_room_cells(Vector2i(3, 2))
	assert_false(kitchen.is_empty())
	_main.call("preview_paint_cell", Vector2i(9, 8))
	assert_eq((_main.get_node("ShopView") as ShopView).floor_preview_cells().size(), dining.size(),
		"hover shows the dining room only")
	assert_true(_main.call("paint_cell", Vector2i(9, 8)))
	for cell: Vector2i in dining:
		assert_eq(_editor().floors.finish(cell).swatch, &"sage")
	for cell: Vector2i in kitchen:
		assert_eq(_editor().floors.finish(cell).swatch, _editor().floor_swatch_id, "the open pass is a room edge")
	assert_eq(_editor().floors.count(), dining.size())
	assert_true(_main.call("set_paint_active", false))


func test_shift_alone_switches_the_room_preview_without_a_mouse_move() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var dining: Array[Vector2i] = _editor().floor_room_cells(Vector2i(2, 8))
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("shop_flooring", _editor().lay_changes(_rect(2, 8, 2, 2), &"herringbone", &"honey")))
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.FLOORS)
	catalogue.floor_style_buttons[&"narrow_planks"].pressed.emit()
	_pointer(Vector2i(5, 6))
	assert_eq(view.floor_preview_cells().size(), 1)
	_main.call("_unhandled_input", _shift_event(true))
	assert_eq(view.floor_preview_cells().size(), dining.size(), "Shift shows the room fill at once")
	_main.call("_unhandled_input", _shift_event(false))
	assert_eq(view.floor_preview_cells().size(), 1)
	_key(KEY_ESCAPE)
	assert_true(_main.call("set_build_active", false))
	# Paint: a click's patch, Shift the room, both without moving.
	assert_true(_main.call("set_paint_active", true))
	_main.set("_paint_swatch_id", &"sage")
	_main.call("update_paint_pointer", _project(Vector2i(3, 9)))
	assert_eq(view.floor_preview_cells().size(), 4)
	_main.call("_unhandled_input", _shift_event(true))
	assert_eq(view.floor_preview_cells().size(), dining.size())
	_main.call("_unhandled_input", _shift_event(false))
	assert_eq(view.floor_preview_cells().size(), 4)
	assert_true(_main.call("set_paint_active", false))


func _shift_event(down: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_SHIFT
	event.keycode = KEY_SHIFT
	event.pressed = down
	event.shift_pressed = down
	return event


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


func _project(cell: Vector2i) -> Vector2:
	return (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(GridMath.cell_to_world(cell))


func _pointer(cell: Vector2i, shift: bool = false) -> void:
	assert_true(_main.call("update_build_pointer", _project(cell), shift))


func _press(cell: Vector2i, shift: bool = false) -> void:
	_pointer(cell, shift)
	_main.call("_unhandled_input", _mouse_event(_project(cell), true, shift))


func _release(cell: Vector2i) -> void:
	_main.call("_unhandled_input", _mouse_event(_project(cell), false))


func _mouse_event(point: Vector2, down: bool, shift: bool = false, alt: bool = false) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	event.shift_pressed = shift
	event.alt_pressed = alt
	return event


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	_main.call("_unhandled_input", event)


func _rect(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in range(y, y + h):
		for column: int in range(x, x + w):
			out.append(Vector2i(column, row))
	return out


func test_review_fixture_maps_both_new_patterns_across_adjacent_cells() -> void:
	await _start()
	var fixture: Script = load("res://tools/floors_review.gd")
	var prepared: Dictionary = fixture.prepare(_main, _main.get_tree().root)
	assert_eq(prepared.get("error"), "")
	var evidence: Dictionary = fixture.evidence(_main)
	assert_true(evidence.get("patterns_match", false))
	var patterns: Dictionary = evidence.get("patterns", {})
	assert_eq(patterns.get("2,5"), FloorStyleDef.Pattern.HEX_TILE)
	assert_eq(patterns.get("3,5"), FloorStyleDef.Pattern.HEX_TILE)
	assert_eq(patterns.get("10,7"), FloorStyleDef.Pattern.TERRACOTTA)
	assert_eq(patterns.get("11,7"), FloorStyleDef.Pattern.TERRACOTTA)
