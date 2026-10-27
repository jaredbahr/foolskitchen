extends TestCase
## FK-085 in the real Main: undo/redo keys and buttons with Economy, the
## history clearing on open, the eyedropper, sell tool, right-click, the
## rotate keys and the Build/Buy/Paint tabs.

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


func test_ctrl_z_and_ctrl_y_round_trip_a_buy_through_the_real_books() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	_editor().set_owner_level(2)
	var cash: int = Economy.cash
	var day: int = Clock.sim.day
	var entries: int = Economy.ledger.entries_for_day(day).size()
	assert_true(_mode().begin_buy(&"potted_plant", Vector2i(4, 9)))
	assert_true(_mode().commit())
	var price: int = _content().item(&"potted_plant").price
	assert_eq(Economy.cash, cash - price)
	assert_false(_catalogue().undo_button.disabled)
	assert_eq(_catalogue().undo_button.tooltip_text, "Undo buy Potted plant (Ctrl+Z)")
	_key(KEY_Z, true)
	assert_null(_world().grid.item_at(Vector2i(4, 9)))
	assert_eq(Economy.cash, cash, "undo refunds the full price")
	var lines: Array[Dictionary] = Economy.ledger.entries_for_day(day)
	assert_eq(lines.size(), entries + 2)
	assert_eq(lines.back()["note"], ShopEditHistory.UNDO_NOTE)
	assert_eq(int(Economy.ledger.day_totals(day).get(Ledger.UPGRADES, 0)), 0)
	assert_true(_hint().contains("Undid buy Potted plant"))
	assert_false(_catalogue().redo_button.disabled)
	_key(KEY_Y, true)
	assert_not_null(_world().grid.item_at(Vector2i(4, 9)))
	assert_eq(Economy.cash, cash - price)
	_catalogue().undo_button.pressed.emit()
	assert_eq(Economy.cash, cash)
	assert_true(_main.call("redo_edit"))
	assert_eq(Economy.cash, cash - price)


func test_history_clears_when_the_shop_opens() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	_editor().set_owner_level(2)
	assert_true(_mode().begin_buy(&"potted_plant", Vector2i(4, 9)))
	assert_true(_mode().commit())
	var history: ShopEditHistory = _main.get("edit_history") as ShopEditHistory
	assert_eq(history.undo_count(), 1)
	assert_true(Clock.sim.start_service())
	assert_eq(history.undo_count(), 0)
	assert_eq(history.redo_count(), 0)
	assert_false(_main.call("is_build_active"))
	assert_false(_main.call("undo_edit"))
	assert_not_null(_world().grid.item_at(Vector2i(4, 9)), "an opened shop keeps the morning's edits")


func test_eyedropper_picks_the_clicked_item_and_its_colour() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	var plant: PlacedItem = _world().grid.item(_id(&"potted_plant"))
	var history: ShopEditHistory = _main.get("edit_history") as ShopEditHistory
	assert_true(history.paint(&"item", &"sage", plant.id))
	_catalogue().tool_buttons[BuildMode.Tool.EYEDROPPER].pressed.emit()
	assert_eq(_mode().tool, BuildMode.Tool.EYEDROPPER)
	assert_true(_catalogue().tool_buttons[BuildMode.Tool.EYEDROPPER].button_pressed)
	assert_true(_main.call("update_build_pointer", _project(plant.cells[0])))
	assert_eq(_mode().hover_item_id, plant.id)
	assert_true(_hint().contains("Place another Potted plant"))
	_click(_project(plant.cells[0]))
	assert_eq(_mode().state, BuildMode.State.BUY)
	assert_eq(_mode().selected_definition.id, &"potted_plant")
	assert_eq(_mode().buy_swatch_id, &"sage")
	assert_eq(_catalogue().mode, BuildCatalogue.BUY)
	assert_eq(_catalogue().selected_category, &"decor", "the catalogue opens the item's room")
	assert_true(_plant_still_at(plant))
	# Placing the copy buys one in the same colour; undo removes the copy.
	_editor().set_owner_level(2)
	assert_true(_main.call("update_build_pointer", _project(Vector2i(4, 9))))
	var cash: int = Economy.cash
	assert_true(_mode().commit())
	var copy: PlacedItem = _world().grid.item_at(Vector2i(4, 9))
	assert_not_null(copy)
	assert_eq((copy.def as ItemDef).id, &"potted_plant")
	assert_eq(copy.swatch_id, &"sage")
	assert_true(_main.call("undo_edit"))
	assert_null(_world().grid.item_at(Vector2i(4, 9)))
	assert_eq(Economy.cash, cash)
	assert_true(_main.call("redo_edit"))
	assert_eq(_world().grid.item_at(Vector2i(4, 9)).swatch_id, &"sage", "redo keeps the copied colour")


func test_sell_tool_shows_the_refund_sells_on_click_and_undo_restores() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	var plant: PlacedItem = _world().grid.item(_id(&"potted_plant"))
	var cell: Vector2i = plant.cells[0]
	_catalogue().tool_buttons[BuildMode.Tool.SELL].pressed.emit()
	assert_true(_main.call("update_build_pointer", _project(cell)))
	assert_true(_hint().contains("Sell Potted plant for $7"), _hint())
	assert_eq(_preview().hover_mesh.get_meta("item_id"), plant.id, "the item to sell is highlighted")
	var cash: int = Economy.cash
	_click(_project(cell))
	assert_null(_world().grid.item_at(cell))
	assert_eq(Economy.cash, cash + 7)
	assert_eq(_mode().tool, BuildMode.Tool.SELL, "the sell tool stays for the next item")
	_key(KEY_Z, true)
	assert_not_null(_world().grid.item_at(cell))
	assert_eq(Economy.cash, cash, "undo charges back exactly the refund")
	# A refused sale explains itself on hover and changes nothing.
	var fridge: PlacedItem = _world().grid.item(_id(&"fridge"))
	assert_true(_main.call("update_build_pointer", _project(fridge.cells[0])))
	assert_false(_mode().current_check.ok)
	_key(KEY_DELETE)
	assert_not_null(_world().grid.item(fridge.id))
	assert_eq(Economy.cash, cash)
	_key(KEY_ESCAPE)
	assert_eq(_mode().tool, BuildMode.Tool.HAND, "Esc steps back to the hand first")
	assert_true(_main.call("is_build_active"))
	_key(KEY_ESCAPE)
	assert_false(_main.call("is_build_active"))


func test_rotate_keys_and_right_click_cancel_keep_the_mode() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	_key(KEY_PERIOD)
	assert_eq(_mode().quarter_turns, 1)
	_key(KEY_COMMA)
	_key(KEY_COMMA)
	assert_eq(_mode().quarter_turns, 3)
	_key(KEY_R)
	assert_eq(_mode().quarter_turns, 0)
	_right_click(_project(Vector2i(4, 9)))
	assert_false(_mode().has_ghost())
	assert_true(_main.call("is_build_active"), "right-click only drops the ghost")
	_right_click(_project(Vector2i(4, 9)))
	assert_true(_main.call("is_build_active"))


func test_undo_is_refused_with_a_reason_and_kept() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	Economy.add_cash(2000, Ledger.OTHER)
	assert_true(_main.call("shop_floor", _rect(1, -3, 12, 3), true), _editor().last_check.why)
	var cash: int = Economy.cash
	for agent: SimAgent in _world().agents:
		if agent is StaffAgent:
			agent.cell = Vector2i(3, -3)
			break
	assert_false(_main.call("undo_edit"))
	assert_true(_hint().contains("Can't undo: " + WallRules.CUT_PERSON), _hint())
	assert_eq((_main.get("edit_history") as ShopEditHistory).undo_count(), 1)
	assert_eq(Economy.cash, cash)


func test_build_buy_and_paint_tabs_drive_the_session() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	assert_eq(_catalogue().mode, BuildCatalogue.BUY)
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	_catalogue().mode_buttons[BuildCatalogue.BUILD].pressed.emit()
	assert_eq(_catalogue().mode, BuildCatalogue.BUILD)
	assert_false(_mode().has_ghost(), "a held Buy piece is dropped when switching to Build")
	_catalogue().wall_buttons.values()[0].pressed.emit()
	assert_eq(_mode().state, BuildMode.State.WALLS)
	_catalogue().category_buttons[&"paint"].pressed.emit()
	assert_true(_main.call("is_paint_active"))
	assert_true(_catalogue().is_paint_visible())
	# Paint undo works with Ctrl+Z too.
	var wall: StringName = _editor().wall_swatch_id
	_catalogue().swatch_buttons[&"sage"].pressed.emit()
	assert_true(_main.call("paint_cell", Vector2i(0, 6)))
	assert_eq(_editor().wall_swatch_id, &"sage")
	_key(KEY_Z, true)
	assert_eq(_editor().wall_swatch_id, wall)
	_key(KEY_ESCAPE)
	assert_false(_main.call("is_paint_active"))
	assert_true(_main.call("is_build_active"), "Esc in Paint goes back one level to Build")
	assert_eq(_catalogue().mode, BuildCatalogue.BUILD)
	_catalogue().mode_buttons[BuildCatalogue.BUY].pressed.emit()
	assert_eq(_catalogue().mode, BuildCatalogue.BUY)
	assert_true(_catalogue().category_buttons[&"dining"].visible)


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
	return (_main.get_node("HUD/BuildHints/Scroll/Text") as Label).text


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
