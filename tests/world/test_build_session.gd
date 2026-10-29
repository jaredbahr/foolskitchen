extends TestCase
## Real Main, Camera3D projection, GUI dispatch, editor and Economy wiring.
## Source only until CI runs it; manual feel and rendered legibility are separate.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "build_session"
const CAPTURE: GDScript = preload("res://tools/screenshot.gd")
const TABLE_4: ItemDef = preload("res://data/items/table_4.tres")

class FreeCatalog extends ContentDB:
	var free_item: ItemDef = ItemDef.new()

	func _init() -> void:
		free_item.id = &"test_free_decor"
		free_item.display_name = "Free test decor"

	func item(id: StringName) -> ItemDef:
		return free_item if id == free_item.id else super.item(id)

var _main: Node3D
var _viewport: SubViewport
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "build_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)
	for key: String in ["owner", "shop", "menu", "staff", "plates"]:
		if SaveSystem._providers.has(key):
			_old_providers[key] = SaveSystem._providers[key].duplicate()


func after_each() -> void:
	_close_main()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	for key: String in ["owner", "shop", "menu", "staff", "plates"]:
		if _old_providers.has(key):
			var provider: Dictionary = _old_providers[key]
			SaveSystem.register(key, provider["capture"], provider["restore"])
		else:
			SaveSystem._providers.erase(key)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)
	Preferences.build_grid_enabled = true


func test_projected_world_clicks_match_editor_for_four_camera_quarters_and_four_world_turns() -> void:
	await _start()
	# Some target rotations have blocked work cells. Keep another fridge
	# reachable so all sixteen requests still isolate projection and rotation.
	assert_true(_main.call("shop_buy", &"fridge", Vector2i(10, 3), 0))
	assert_true(_main.call("set_build_active", true))
	var item: PlacedItem = _world().grid.item(_id(&"fridge"))
	var original: Vector2i = item.origin
	var original_turns: int = item.quarter_turns
	var books: Dictionary = Economy.ledger.to_dict()
	for quarter: int in range(4):
		_rig().initial_yaw_degrees = 45.0 + quarter * 90.0
		_rig().reset_view()
		assert_eq(_rig().camera_quarter(), quarter)
		for turns: int in range(4):
			_click(_project(item.cells[0]))
			assert_eq(_mode().selected_item_id, item.id)
			for rotation: int in range(posmod(turns - _mode().quarter_turns, 4)):
				_key(KEY_R)
			assert_eq(_mode().quarter_turns, turns)
			var bad_cell: Vector2i = Vector2i(4, 1)  # The actual prep counter.
			assert_true(_main.call("update_build_pointer", _project(bad_cell + _mode().grab_offset)))
			var expected: EditCheck = _editor().check_move(item.id, bad_cell, turns)
			assert_false(expected.ok)
			assert_eq(_mode().origin, bad_cell)
			assert_eq(_mode().current_check.ok, expected.ok)
			assert_eq(_mode().current_check.why, expected.why)
			_click(_project(bad_cell + _mode().grab_offset))
			assert_true(_mode().has_ghost())
			assert_eq(item.origin, original, "red click leaves the real item unchanged")
			var target: Vector2i = Vector2i(10, 8)
			expected = _editor().check_move(item.id, target, turns)
			assert_true(expected.ok)
			assert_true(_main.call("update_build_pointer", _project(target + _mode().grab_offset)))
			assert_eq(_mode().origin, target)
			assert_eq(_mode().current_check.ok, expected.ok)
			assert_eq(_mode().current_check.why, expected.why)
			assert_eq(_mode().warning_ids(), expected.unreachable)
			_main.call("update_build_pointer", _project(bad_cell + _mode().grab_offset))
			# The last hover is red: click must refresh from its own position.
			_click(_project(target + _mode().grab_offset))
			assert_eq(item.origin, target)
			assert_eq(item.quarter_turns, turns)
			assert_eq(_mode().state, BuildMode.State.IDLE)
			assert_eq(_mode().committed_warning_ids, _editor().check_current().unreachable)
			assert_true(_main.call("shop_move", item.id, original, original_turns))
	assert_eq(Economy.ledger.to_dict(), books, "all 16 moves and rotations are free")
	assert_eq(_world().now, 0)


func test_stationary_pointer_reprojects_after_camera_smoothing_without_a_mouse_event() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	var pointer: Vector2 = _viewport.get_mouse_position()
	_main.call("_process", 0.0)
	var before: Vector2i = _mode().origin
	_rig().rotate_quarter(1)
	_rig().zoom_steps(1.0)
	_rig().step_view(0.2, Vector2.RIGHT)
	var expected: Variant = _main.call("build_cell_at_screen_position", pointer)
	assert_true(expected is Vector2i)
	_main.call("_process", 0.0)
	assert_eq(_viewport.get_mouse_position(), pointer)
	assert_eq(_mode().origin, expected)
	assert_ne(_mode().origin, before, "actual camera motion changes the floor cell under a stationary pointer")
	var direct: Variant = Picker.floor_intersection(_camera().project_ray_origin(pointer), _camera().project_ray_normal(pointer))
	assert_true(direct is Vector3)
	assert_eq(_mode().origin, GridMath.world_to_cell(direct))
	assert_eq(_world().now, 0)


func test_projected_far_side_pickup_preserves_grab_offset_at_every_camera_quarter() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	var item: PlacedItem = _world().grid.item(_id(&"fridge"))
	var original: Vector2i = item.origin
	var original_turns: int = item.quarter_turns
	var books: Dictionary = Economy.ledger.to_dict()
	for quarter: int in range(4):
		_rig().initial_yaw_degrees = 45.0 + quarter * 90.0
		_rig().reset_view()
		var far_cell: Vector2i = original + Vector2i(1, 0)
		_click(_project(far_cell))
		assert_eq(_mode().selected_item_id, item.id)
		assert_eq(_mode().origin, original)
		assert_eq(_mode().grab_offset, Vector2i(1, 0))
		_main.call("update_build_pointer", _project(far_cell))
		assert_eq(_mode().origin, original, "the held furniture stays still under its clicked far tile")
		var cursor: Vector2i = far_cell + Vector2i(1, 1)
		_main.call("update_build_pointer", _project(cursor))
		assert_eq(_mode().origin, original + Vector2i(1, 1))
		var offsets: Array[Vector2i] = [Vector2i(0, 1), Vector2i.ZERO, Vector2i.ZERO, Vector2i(1, 0)]
		for step: int in range(4):
			_native_key(KEY_R)
			assert_eq(_mode().quarter_turns, (original_turns + step + 1) % 4)
			assert_eq(_mode().grab_offset, offsets[step])
			assert_eq(_mode().origin, cursor - offsets[step])
			assert_eq(_mode().origin + _mode().grab_offset, cursor)
			_main.call("update_build_pointer", _project(cursor))
			assert_eq(_mode().origin, cursor - offsets[step], "the projected stationary pointer keeps its grabbed tile")
			assert_eq(item.origin, original)
			assert_eq(Economy.ledger.to_dict(), books)
		assert_eq(_mode().origin, original + Vector2i(1, 1))
		assert_eq(item.origin, original)
		assert_true(_mode().current_check.ok)
		_click(_project(cursor))
		assert_eq(item.origin, original + Vector2i(1, 1))
		assert_eq(_mode().state, BuildMode.State.IDLE)
		assert_true(_main.call("shop_move", item.id, original, original_turns))
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(_world().now, 0)


func test_build_keys_suspend_inspection_cycle_world_turns_and_leave_service_r_unhandled() -> void:
	await _start()
	assert_true(_main.call("select_agent", _world().agents[0].id))
	assert_false(_main.call("route_build_input", _key_event(KEY_R)))
	_key(KEY_B)
	assert_true(_main.call("is_build_active"))
	var inspection: Dictionary = _main.call("inspection_state")
	assert_eq(inspection["selected_agent_id"], -1)
	assert_false(inspection["panel_visible"])
	assert_false(_main.call("select_agent", _world().agents[0].id))
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	for turn: int in [1, 2, 3, 0]:
		_key(KEY_R)
		assert_eq(_mode().quarter_turns, turn)
	var repeat: InputEventKey = _key_event(KEY_R)
	repeat.echo = true
	_main.call("_unhandled_input", repeat)
	assert_eq(_mode().quarter_turns, 0)
	_key(KEY_F3)
	assert_true(_main.call("is_debug_visible"), "F3 retains the same route while building")
	_key(KEY_ESCAPE)
	assert_eq(_mode().state, BuildMode.State.IDLE)
	_key(KEY_ESCAPE)
	assert_false(_main.call("is_build_active"))
	assert_false(_main.call("route_build_input", _key_event(KEY_R)), "no service-R action is invented here")
	assert_true(_main.call("select_agent", _world().agents[0].id))
	_key(KEY_ESCAPE)
	inspection = _main.call("inspection_state")
	assert_false(inspection["panel_visible"])


func test_open_phase_refuses_b_and_hud_and_direct_phase_writes_exit_cheaply() -> void:
	await _start()
	var books: Dictionary = Economy.ledger.to_dict()
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("set_build_active", true))
	_key(KEY_B)
	assert_false(_main.call("is_build_active"))
	var button: Button = _main.get_node("HUD/Top/Row/Build") as Button
	assert_true(button.disabled)
	assert_true(button.tooltip_text.contains("morning"))
	button.pressed.emit()
	assert_false(_main.call("is_build_active"))
	assert_false(_main.call("route_build_input", _key_event(KEY_R)))
	Clock.sim.phase = SimClock.Phase.CLOSED
	_main.call("_process", 0.0)
	assert_false(button.disabled)
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	Clock.sim.phase = SimClock.Phase.LAST_ORDERS
	_main.call("_process", 0.0)
	assert_false(_main.call("is_build_active"))
	assert_null(_preview().ghost_mesh)
	assert_false(_rig().is_grid_forced())
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(_world().now, 0)


func test_native_build_input_precedes_selected_owner_keys_and_station_commands() -> void:
	await _start(true)
	var owner: OwnerAgent = (_main.get("sim") as RestaurantSim).owner_agent()
	assert_not_null(owner)
	assert_true(_main.call("select_agent", owner.id))
	assert_true(_main.call("assign_owner_mode", &"floor"))
	var panel: InspectPanel = _main.get_node("Overlay/InspectPanel") as InspectPanel
	var owner_controls: Control = panel.get_node("Panel/Rows/OwnerModes") as Control
	assert_true(owner_controls.is_visible_in_tree())
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var rng_state: int = GameState.rng(&"customers").state
	var saved: String = FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))
	_native_key(KEY_B)
	assert_true(_main.call("is_build_active"))
	assert_eq(panel.selected_agent_id, -1)
	assert_false(panel.visible)
	assert_false(owner_controls.is_visible_in_tree())
	assert_true(_main.call("begin_buy_item", &"chair"))
	_main.call("update_build_pointer", _project(Vector2i(4, 9)))
	assert_eq(_mode().quarter_turns, 0)
	_native_key(KEY_R)
	assert_eq(_mode().quarter_turns, 1, "native R rotates the ghost through Main's build route")
	assert_eq(owner.current_mode(), &"floor", "the same R must not issue owner Rest")
	assert_false(_main.call("assign_owner_mode", &"rest"), "stale owner commands are gated while building")
	_native_key(KEY_ESCAPE)
	var fridge: PlacedItem = _world().grid.item(_id(&"fridge"))
	var point: Vector2 = _project(fridge.origin)
	_viewport.push_input(_mouse_event(point, true), true)
	_viewport.push_input(_mouse_event(point, false), true)
	assert_eq(_mode().state, BuildMode.State.MOVE)
	assert_eq(_mode().selected_item_id, fridge.id, "native station click picks furniture while building")
	assert_eq(owner.current_mode(), &"floor")
	_native_key(KEY_ESCAPE)
	_native_key(KEY_ESCAPE)
	assert_false(_main.call("is_build_active"))
	assert_true(_main.call("select_agent", owner.id))
	assert_true(owner_controls.is_visible_in_tree())
	_native_key(KEY_R)
	assert_eq(owner.current_mode(), &"rest", "the official owner R command works after exit and reselect")
	_viewport.push_input(_mouse_event(point, true), true)
	_viewport.push_input(_mouse_event(point, false), true)
	assert_eq(owner.current_mode(), &"kitchen", "the official station assignment route also resumes")
	assert_eq(panel.selected_agent_id, owner.id)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState.rng(&"customers").state, rng_state)
	assert_eq(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")), saved)
	assert_eq(_world().now, 0)


func test_native_alt_picks_moves_rotates_and_sells_only_the_covered_rug_at_all_camera_quarters() -> void:
	await _start(true)
	var table: PlacedItem = ShopBuilder.items_with_def(_world(), &"table_2")[1]
	var content: ContentDB = _main.get("content") as ContentDB
	var rug_def: ItemDef = content.item(&"rug_square")
	# Explicit purchase-unlock fixture; the gestures do not change progression.
	_editor().set_owner_level(rug_def.unlock_level)
	var saved: String = _saved_build_text()
	assert_true(_main.call("shop_buy", rug_def.id, table.origin, 0))
	var rug: PlacedItem = _world().grid.item_on_layer(table.origin, ItemDef.PlacementLayer.FLOOR_DECOR)
	assert_not_null(rug)
	if rug == null:
		return
	assert_eq(rug.cells, table.cells, "the normal furniture fully covers the rug's cells")
	assert_eq(_saved_build_text(), saved, "buying still waits for the normal morning checkpoint")
	assert_true(_main.call("set_build_active", true))
	await _frames(2)
	var normal: Dictionary = _normal_furniture_state(table)
	var unchanged: Dictionary = _build_side_effect_state()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var rug_visual: ItemVisual = view.item_nodes[rug.id]
	var clicked_cell: Vector2i = table.origin + Vector2i.ONE
	for quarter: int in 4:
		_rig().initial_yaw_degrees = 45.0 + quarter * 90.0
		_rig().reset_view()
		var point: Vector2 = _project(clicked_cell)
		_assert_world_click_clear_of_gui(point)
		_native_click(point)
		assert_eq(_mode().selected_item_id, table.id, "ordinary clicks still prefer normal furniture")
		_native_key(KEY_ESCAPE)
		assert_eq(_normal_furniture_state(table), normal)
		_native_click(point, true)
		assert_eq(_mode().state, BuildMode.State.MOVE)
		assert_eq(_mode().selected_item_id, rug.id)
		assert_eq(_mode().grab_offset, Vector2i.ONE)
		assert_false(rug_visual.visible)
		assert_true(view.item_nodes[table.id].visible, "the rug ghost never hides the table or its chairs")
		_native_key(KEY_R)
		assert_eq(_mode().quarter_turns, 1)
		assert_eq(_mode().origin + _mode().grab_offset, clicked_cell)
		var destination: Vector2i = _mode().origin
		_native_click(point, true) # Alt on an existing MOVE ghost still commits it.
		assert_eq(_mode().state, BuildMode.State.IDLE)
		assert_eq(rug.origin, destination)
		assert_eq(rug.quarter_turns, 1)
		assert_eq(_normal_furniture_state(table), normal)
		assert_eq(_build_side_effect_state(), unchanged)
		assert_true(_main.call("shop_move", rug.id, table.origin, 0))
		assert_true(view.item_nodes[rug.id] == rug_visual)
	var books_before_sale: int = Economy.ledger.entries_for_day(Clock.sim.day).size()
	var cash_before_sale: int = Economy.cash
	var point: Vector2 = _project(clicked_cell)
	_native_click(point, true)
	assert_eq(_mode().selected_item_id, rug.id)
	_native_key(KEY_DELETE)
	assert_eq(_mode().state, BuildMode.State.IDLE)
	assert_null(_world().grid.item(rug.id))
	assert_eq(Economy.cash, cash_before_sale + floori(float(rug_def.price) / 2.0))
	assert_eq(Economy.ledger.entries_for_day(Clock.sim.day).size(), books_before_sale + 1)
	assert_eq(_normal_furniture_state(table), normal)
	_native_click(point, true) # The table remains, but there is no floor-layer item.
	assert_eq(_mode().state, BuildMode.State.IDLE, "an Alt miss cannot fall back to the table")
	assert_eq((_main.call("inspection_state") as Dictionary)["selected_item_id"], -1)
	_native_key(KEY_DELETE)
	assert_eq(Economy.ledger.entries_for_day(Clock.sim.day).size(), books_before_sale + 1)
	assert_eq(GameState._capture_save(), unchanged["rng"])
	assert_eq(Clock.sim.to_dict(), unchanged["clock"])
	assert_eq(_saved_build_text(), saved)
	assert_eq(_world().now, 0)


func test_native_alt_buy_commit_and_gui_clicks_keep_existing_input_ownership() -> void:
	await _start(true)
	assert_true(_main.call("set_build_active", true))
	var content: ContentDB = _main.get("content") as ContentDB
	var plant_def: ItemDef = content.item(&"potted_plant")
	_editor().set_owner_level(plant_def.unlock_level) # Explicit purchase-unlock fixture.
	var origin: Vector2i = Vector2i(4, 9)
	assert_true(_mode().begin_buy(plant_def.id, origin))
	assert_true(_mode().current_check.ok)
	var before: Dictionary = _build_side_effect_state()
	var cash: int = Economy.cash
	_assert_world_click_clear_of_gui(_project(origin))
	_native_click(_project(origin), true)
	assert_eq(_mode().state, BuildMode.State.IDLE, "Alt does not replace a BUY ghost with a layer pick")
	assert_eq(_world().grid.item_at(origin).def, plant_def)
	assert_eq(Economy.cash, cash - plant_def.price)
	assert_eq(_saved_build_text(), before["saved"])
	assert_eq(GameState._capture_save(), before["rng"])
	assert_true(_mode().begin_buy(&"fridge", Vector2i(2, 8)))
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	await _frames(2)
	before = _build_side_effect_state()
	var placements: Dictionary = _editor().to_dict()
	var category: Button = catalogue.category_buttons[&"kitchen"]
	assert_true(category.is_visible_in_tree())
	_native_click(category.get_global_rect().get_center(), true)
	assert_eq(catalogue.selected_category, &"kitchen")
	assert_eq(_mode().state, BuildMode.State.BUY)
	assert_eq(_mode().selected_definition.id, &"fridge")
	assert_eq(_editor().to_dict(), placements, "native GUI input cannot commit the held ghost underneath")
	assert_eq(_build_side_effect_state(), before)
	var menu: Button = _main.get_node("HUD/Top/Row/Menu") as Button
	_native_click(menu.get_global_rect().get_center(), true)
	assert_true(_main.call("is_menu_visible"))
	assert_false(_main.call("is_build_active"))
	assert_false(_mode().has_ghost())
	assert_eq(_editor().to_dict(), placements)
	assert_eq(_build_side_effect_state(), before)


func test_native_hud_toggle_survives_refresh_between_mouse_down_and_up() -> void:
	await _start()
	var button: Button = _main.get_node("HUD/Top/Row/Build") as Button
	var identity: int = button.get_instance_id()
	var point: Vector2 = button.get_global_rect().get_center()
	_viewport.push_input(_mouse_event(point, true), true)
	_main.call("_process", 0.0)
	_main.get_node("HUD").call("refresh")
	await _frames(1)
	_viewport.push_input(_mouse_event(point, false), true)
	assert_true(_main.call("is_build_active"))
	assert_true(button.button_pressed)
	assert_eq(button.get_instance_id(), identity)
	assert_true(_rig().is_grid_forced())
	assert_eq((_main.get_node("HUD/BuildHints") as Control).theme, load("res://src/ui/theme/main_theme.tres"))
	assert_true((_main.get_node("HUD/BuildHints") as Control).visible)
	_viewport.push_input(_mouse_event(point, true), true)
	_main.get_node("HUD").call("refresh")
	await _frames(1)
	_viewport.push_input(_mouse_event(point, false), true)
	assert_false(_main.call("is_build_active"))
	assert_false(button.button_pressed)
	assert_false((_main.get_node("HUD/BuildHints") as Control).visible)


func test_native_catalogue_click_consumes_gui_input_and_starts_one_ghost_without_booking() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"chair", Vector2i(2, 8)))
	assert_true(_mode().current_check.ok)
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	await _frames(3)
	var books: Dictionary = Economy.ledger.to_dict()
	var items: int = _world().grid.items().size()
	var kitchen: Button = catalogue.category_buttons[&"kitchen"]
	assert_true(kitchen.is_visible_in_tree())
	var kitchen_point: Vector2 = kitchen.get_global_rect().get_center()
	_viewport.push_input(_mouse_event(kitchen_point, true), true)
	_viewport.push_input(_mouse_event(kitchen_point, false), true)
	assert_eq(catalogue.selected_category, &"kitchen")
	await _frames(1)
	var button: Button = catalogue.item_buttons[&"fridge"]
	assert_true(button.is_visible_in_tree(), "native clicks target the visible Kitchen card")
	var identity: int = button.get_instance_id()
	var point: Vector2 = button.get_global_rect().get_center()
	assert_true((catalogue.get_node("Panel") as Control).get_global_rect().has_point(point))
	_viewport.push_input(_mouse_event(point, true), true)
	_main.call("_process", 0.0)
	catalogue.refresh_content()
	await _frames(1)
	_viewport.push_input(_mouse_event(point, false), true)
	assert_eq(_mode().state, BuildMode.State.BUY)
	assert_eq(_mode().selected_definition.id, &"fridge")
	assert_eq(button.get_instance_id(), identity)
	assert_eq(_world().grid.items().size(), items)
	assert_eq(Economy.ledger.to_dict(), books, "GUI clicks request a ghost and never place underneath")
	assert_eq(catalogue.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq((catalogue.get_node("Panel") as Control).mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)


func test_main_build_hud_shows_partial_seats_and_clears_warning_after_the_layout_is_fixed() -> void:
	await _start()
	# The table below blocks the kitchen aisle; coffee remains serviceable.
	assert_true(_main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	var center: PlacedItem = _world().grid.item_at(Vector2i(6, 6))
	assert_true(int(_main.call("shop_sell", center.id)) >= 0)
	_editor().set_owner_level(TABLE_4.unlock_level)  # Explicit purchase-unlock fixture.
	assert_true(_main.call("set_build_active", true))
	var label: Label = _main.get_node("HUD/BuildHints/Scroll/Lines/Text") as Label
	assert_true(_mode().begin_buy(&"table_4", Vector2i(6, 5)))
	assert_true(_mode().current_check.ok)
	assert_true(label.text.contains("Only 3 of 4 seats usable"), "the production Main binding reaches the native HUD")
	assert_true(_mode().commit())
	var table: PlacedItem = _world().grid.item_at(Vector2i(6, 5))
	assert_true(label.text.contains("Only 3 of 4 seats usable"), "a committed table retains its warning")
	assert_true(_mode().pick_up(table.id))
	_mode().update_origin(Vector2i(-1, 0))
	assert_false(_mode().current_check.ok)
	assert_true(label.text.contains(_mode().current_check.why))
	assert_false(label.text.contains("Only 3 of 4"), "the invalid action's reason takes precedence")
	_mode().cancel()
	assert_true(label.text.contains("Only 3 of 4 seats usable"))
	assert_true(_main.call("set_build_active", false))
	assert_false((_main.get_node("HUD/BuildHints") as Control).visible)
	assert_true(_main.call("set_build_active", true))
	assert_true(label.text.contains("Only 3 of 4 seats usable"), "re-entering reads the actual layout")
	assert_true(_mode().pick_up(table.id))
	_mode().update_origin(Vector2i(6, 6))
	assert_true(_mode().current_check.ok)
	assert_false(label.text.contains("seats usable"), "a valid repaired proposal uses the new capacity")
	assert_true(_mode().commit())
	assert_false(label.text.contains("seats usable"))
	assert_eq(_world().now, 0, "Build feedback does not advance service")
	assert_false(FileAccess.file_exists(_save_dir.path_join(SLOT + ".json")), "the source fixture disables game saves")


func test_floor_tool_hint_keeps_the_partial_seat_warning_beside_its_summary() -> void:
	await _start()
	assert_true(_main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	var center: PlacedItem = _world().grid.item_at(Vector2i(6, 6))
	assert_true(int(_main.call("shop_sell", center.id)) >= 0)
	_editor().set_owner_level(TABLE_4.unlock_level)  # Explicit purchase-unlock fixture.
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"table_4", Vector2i(6, 5)))
	assert_true(_mode().commit())
	var label: Label = _main.get_node("HUD/BuildHints/Scroll/Lines/Text") as Label
	assert_true(_mode().begin_floor())
	# Before any lot hover the Floor check is (false, ""): the warning must still show.
	assert_false(_mode().current_check.ok)
	assert_true(label.text.contains("Only 3 of 4 seats usable"), "an empty floor check keeps the seat warning")
	_mode().floor_pointer(Vector2i(14, 6))
	assert_true(_mode().current_check.ok, _mode().current_check.why)
	assert_true(label.text.contains(_mode().floor_summary()), "the floor tool's own summary")
	assert_true(_mode().floor_summary().begins_with("Add 1 floor tile"))
	assert_true(label.text.contains("Only 3 of 4 seats usable"), "the blocked seat stays visible")
	assert_eq(_world().now, 0, "Build feedback does not advance service")


func test_build_hints_match_available_actions_and_fit_content_or_small_viewport_scroll() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	var label: Label = _main.get_node("HUD/BuildHints/Scroll/Lines/Text") as Label
	var panel: PanelContainer = _main.get_node("HUD/BuildHints") as PanelContainer
	var scroll: ScrollContainer = _main.get_node("HUD/BuildHints/Scroll") as ScrollContainer
	await _frames(2)
	assert_eq(label.text, "Click Pick up  |  Alt-click Pick up rug  |  Ctrl+Z Undo  Ctrl+Y Redo  |  Esc Exit")
	assert_true(panel.size.x < 700.0 and panel.size.y < 96.0, "one-line hints follow their content")
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	assert_true(label.text.contains("R Rotate"))
	assert_false(label.text.contains("Del Sell"))
	assert_true(_mode().pick_up(_id(&"potted_plant")))
	assert_true(label.text.contains("Del Sell"))
	_mode().cancel()
	assert_eq(label.text, "Click Pick up  |  Alt-click Pick up rug  |  Ctrl+Z Undo  Ctrl+Y Redo  |  Esc Exit")
	# Reproduce the real two-line red hint through the same proposal as capture.
	assert_true(_main.call("begin_buy_item", &"fridge"))
	assert_true(_main.call("update_build_pointer", _project(Vector2i(7, 7))))
	_key(KEY_R)
	assert_false(_mode().current_check.ok)
	await _frames(3)
	assert_eq(label.text, "Click Place  |  , . or R Rotate  |  Esc or Right-click Cancel\nSomething is in the way")
	assert_eq(label.get_line_count(), 2)
	_assert_hint_content_fits(label, scroll)
	# Presenter-only long text tests the bounded scroll, without posing sim state.
	_viewport.size = Vector2i(360, 100)
	_main.get_node("HUD").call("set_build_state", true, true,
		"A long placement explanation stays accessible in a small window. ".repeat(20), int(BuildMode.State.BUY))
	await _frames(4)
	var rect: Rect2 = panel.get_global_rect()
	assert_true(rect.position.x >= 12.0 and rect.position.y >= 12.0)
	assert_true(rect.end.x <= 348.5 and rect.end.y <= 88.5)
	assert_true(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page)
	assert_false(label.text.contains("Del Sell"))
	_viewport.size = Vector2i(1600, 900)
	_main.get_node("HUD").call("set_build_state", true, true, _mode().current_check.why, int(BuildMode.State.BUY))
	await _frames(4)
	assert_eq(label.get_line_count(), 2)
	_assert_hint_content_fits(label, scroll)
	assert_eq(_world().now, 0)


func test_forced_grid_preserves_both_preferences_and_rebinds_the_actual_new_floor() -> void:
	await _start()
	for preference: bool in [false, true]:
		if _rig().grid_visible != preference:
			_rig().toggle_grid()
		assert_true(_main.call("set_build_active", true))
		assert_true(_rig().is_grid_forced())
		assert_true(_rig().effective_grid_visible())
		assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), true)
		_rig()._unhandled_input(_key_event(KEY_G))
		assert_eq(_rig().grid_visible, preference, "G in Build leaves the G preference used elsewhere")
		assert_false(_rig().effective_grid_visible(), "G in Build hides Build's grid")
		assert_false(Preferences.build_grid_enabled)
		_rig()._unhandled_input(_key_event(KEY_G))
		assert_true(_rig().effective_grid_visible())
		assert_true(Preferences.build_grid_enabled)
		_key(KEY_ESCAPE)
		assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), preference)
	if _rig().grid_visible:
		_rig().toggle_grid()
	assert_true(_main.call("set_build_active", true))
	_click(_project(_world().grid.item(_id(&"potted_plant")).cells[0]))
	var old_mesh: ItemVisual = (_main.get_node("ShopView") as ShopView).item_nodes[_id(&"potted_plant")]
	assert_false(old_mesh.visible)
	var old_floor: MeshInstance3D = _rig().grid_floor
	var old_clock: SimClock = Clock.sim
	Clock.sim = SimClock.new()
	_main.call("_bind_world_presentation")
	_main.call("_bind_build_session")
	assert_false(is_instance_valid(old_floor))
	assert_false(is_instance_valid(old_mesh))
	assert_null(_preview().ghost_mesh)
	assert_false(_main.call("is_build_active"))
	assert_false(_rig().is_grid_forced())
	assert_false(_rig().grid_visible)
	assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), false)
	assert_true(_rig().grid_floor == (_main.get_node("ShopView") as ShopView).floor_mesh)
	assert_true(_mode().enter())
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	assert_true(old_clock.start_service())
	assert_true(_main.call("is_build_active"), "the detached clock cannot exit the rebound controller")
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("is_build_active"))
	assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), false)


func test_delete_books_refund_once_and_preserves_upstream_zero_popup_policy() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	var deltas: Control = _main.get_node("HUD/Deltas") as Control
	var count: int = deltas.get_child_count()
	var entries: int = Economy.ledger.entries_for_day(Clock.sim.day).size()
	var cash: int = Economy.cash
	var plant: PlacedItem = _world().grid.item(_id(&"potted_plant"))
	_click(_project(plant.cells[0]))
	_key(KEY_DELETE)
	assert_eq(Economy.cash, cash + 7)
	assert_eq(Economy.ledger.entries_for_day(Clock.sim.day).size(), entries + 1)
	assert_eq(deltas.get_child_count(), count + 1)
	assert_eq((deltas.get_child(count) as Label).text, "+$7")
	_key(KEY_DELETE)
	assert_eq(deltas.get_child_count(), count + 1)
	assert_eq(Economy.ledger.entries_for_day(Clock.sim.day).size(), entries + 1)
	_click(_project(_world().grid.item(_id(&"fridge")).cells[0]))
	_key(KEY_DELETE)
	assert_true(_mode().has_ghost())
	assert_false(_mode().current_check.ok)
	assert_eq(deltas.get_child_count(), count + 1, "a refused sale has no refund delta")
	_key(KEY_ESCAPE)
	# A zero-price in-memory definition exercises the real editor/Economy seam;
	# authored content resources and the product catalogue are not modified.
	var catalog: FreeCatalog = FreeCatalog.new()
	assert_eq(catalog.load_all(), PackedStringArray())
	_main.set("content", catalog)
	_main.set("shop_editor", ShopEditor.new(_main.get("sim"), catalog,
		ShopEditBooks.new(Economy.can_spend_without_loan, Economy.add_cash)))
	_main.call("_bind_build_session")
	assert_true(_mode().enter())
	assert_true(_mode().begin_buy(catalog.free_item.id, Vector2i(4, 9)))
	assert_true(_mode().commit())
	count = deltas.get_child_count()
	entries = Economy.ledger.entries_for_day(Clock.sim.day).size()
	cash = Economy.cash
	_click(_project(Vector2i(4, 9)))
	assert_eq(_mode().sell_selected(), 0)
	assert_eq(Economy.cash, cash)
	assert_eq(Economy.ledger.entries_for_day(Clock.sim.day).size(), entries + 1)
	assert_eq(deltas.get_child_count(), count, "upstream HUD ignores zero cash changes while the sale still succeeds")
	assert_eq(_mode().state, BuildMode.State.IDLE)
	assert_null(_world().grid.item_at(Vector2i(4, 9)))
	_key(KEY_DELETE)
	assert_eq(deltas.get_child_count(), count)
	assert_eq(Economy.ledger.entries_for_day(Clock.sim.day).size(), entries + 1)


func test_native_menu_and_build_transitions_cancel_ghost_and_preserve_data_and_autosave() -> void:
	await _start(true)
	if _rig().grid_visible:
		_rig().toggle_grid()
	var menu: MenuPanel = _main.get_node("Overlay/MenuPanel") as MenuPanel
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	var saved_file: String = FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))
	var shop: Dictionary = _editor().to_dict()
	var choices: Dictionary = (_main.get("menu_settings") as MenuSettings).to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var rng_state: int = GameState.rng(&"customers").state
	assert_true(_main.call("set_menu_visible", true))
	assert_true(menu.visible)
	var build_button: Button = _main.get_node("HUD/Top/Row/Build") as Button
	var build_point: Vector2 = build_button.get_global_rect().get_center()
	_viewport.push_input(_mouse_event(build_point, true), true)
	_main.call("_process", 0.0)
	_main.get_node("HUD").call("refresh")
	await _frames(1)
	_viewport.push_input(_mouse_event(build_point, false), true)
	assert_true(_main.call("is_build_active"))
	assert_false(menu.visible, "native Build entry closes Menu before world building")
	assert_true(catalogue.visible)
	assert_true(_rig().is_grid_forced())
	assert_true(_main.call("begin_buy_item", &"chair"))
	_main.call("update_build_pointer", _project(Vector2i(2, 8)))
	assert_true(_mode().has_ghost())
	assert_true(_mode().current_check.ok)
	var menu_button: Button = _main.get_node("HUD/Top/Row/Menu") as Button
	var menu_point: Vector2 = menu_button.get_global_rect().get_center()
	_viewport.push_input(_mouse_event(menu_point, true), true)
	_main.call("_process", 0.0)
	_main.get_node("HUD").call("refresh")
	await _frames(1)
	_viewport.push_input(_mouse_event(menu_point, false), true)
	assert_true(menu.visible, "native Menu opens after cancelling the held build preview")
	assert_false(_main.call("is_build_active"))
	assert_false(_mode().has_ghost())
	assert_null(_preview().ghost_mesh)
	assert_false(catalogue.visible)
	assert_false(build_button.button_pressed)
	assert_false(_rig().is_grid_forced())
	assert_false(_rig().grid_visible)
	assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), false)
	assert_eq(_editor().to_dict(), shop)
	assert_eq((_main.get("menu_settings") as MenuSettings).to_dict(), choices)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState.rng(&"customers").state, rng_state)
	assert_eq(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")), saved_file)
	_key(KEY_ESCAPE)
	assert_false(menu.visible)


func test_preview_warning_ids_match_proposal_actual_purchase_cancel_exit_and_fix() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"fridge", Vector2i(11, 1)))
	assert_true(_mode().current_check.ok)
	assert_true(_mode().warning_ids().has(0))
	assert_eq(_preview().displayed_warning_ids(), _mode().current_check.unreachable)
	_key(KEY_ESCAPE)
	assert_eq(_preview().displayed_warning_ids(), _editor().check_current().unreachable)
	assert_true(_mode().begin_buy(&"fridge", Vector2i(11, 1)))
	_click(_project(Vector2i(11, 1)))
	var id: int = _world().grid.item_at(Vector2i(11, 1)).id
	assert_true(_preview().displayed_warning_ids().has(id))
	assert_false(_preview().displayed_warning_ids().has(0))
	_key(KEY_ESCAPE)
	assert_false(_main.call("is_build_active"))
	assert_eq(_preview().displayed_warning_ids(), _editor().check_current().unreachable)
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"chair", Vector2i(1, 1)))
	assert_false(_mode().current_check.ok)
	assert_true((_main.get_node("HUD/BuildHints/Scroll/Lines/Text") as Label).text.contains(_mode().current_check.why))
	assert_eq(_preview().displayed_warning_ids(), _mode().committed_warning_ids)
	_key(KEY_ESCAPE)
	assert_true(_preview().displayed_warning_ids().has(id))
	assert_true(_main.call("shop_move", id, Vector2i(3, 3), 0))
	assert_eq(_preview().displayed_warning_ids(), _editor().check_current().unreachable)
	assert_false(_preview().displayed_warning_ids().has(id))


func test_closed_report_is_hidden_during_edit_and_rebuilt_on_exit_without_day_setup_or_costs() -> void:
	await _start()
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 10)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var panel: Control = _main.get_node("Overlay/EveningReport") as Control
	assert_true(panel.visible)
	var old_report: DayReport = _main.get("shown_report") as DayReport
	var clock: Dictionary = Clock.sim.to_dict()
	var costs: Dictionary = Economy.ledger.day_totals(Clock.sim.day)
	var entries: int = Economy.ledger.entries_for_day(Clock.sim.day).size()
	_key(KEY_B)
	assert_false(panel.visible)
	_click(_project(_world().grid.item(_id(&"potted_plant")).cells[0]))
	_key(KEY_DELETE)
	assert_false(panel.visible)
	_key(KEY_B)
	assert_true(panel.visible)
	var updated: DayReport = _main.get("shown_report") as DayReport
	assert_true(updated != old_report)
	assert_eq(updated.income.get(Ledger.UPGRADES, 0), 7)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(Economy.ledger.entries_for_day(Clock.sim.day).size(), entries + 1)
	var totals: Dictionary = Economy.ledger.day_totals(Clock.sim.day)
	assert_eq(totals.get(Ledger.WAGES), costs.get(Ledger.WAGES))
	assert_eq(totals.get(Ledger.RENT), costs.get(Ledger.RENT))
	var books: Dictionary = Economy.ledger.to_dict()
	_key(KEY_B)
	assert_false(panel.visible)
	_key(KEY_ESCAPE)
	assert_true(panel.visible)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Clock.sim.to_dict(), clock)


func test_saved_startup_replaces_initial_world_before_final_controller_clock_binding() -> void:
	await _start(true)
	var morning_file: String = FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"chair", Vector2i(2, 8)))
	_click(_project(Vector2i(2, 8)))
	assert_eq(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")), morning_file,
		"build commits do not introduce another autosave")
	assert_eq(SaveSystem.save_game(SLOT), OK)  # Existing explicit MORNING save.
	var snapshot: Dictionary = _editor().to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	_close_main()
	_main = MAIN.instantiate() as Node3D
	_main.set("save_slot", SLOT)
	_main.call("initialize")
	var provisional: SimWorld = _world()
	_viewport.add_child(_main)
	_main.call("start")
	_disable_frame_drivers()
	assert_true(_world() != provisional)
	assert_true(_world().clock == Clock.sim)
	assert_true(Clock.attached_world == _world())
	assert_eq(_editor().to_dict(), snapshot)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_true(_main.call("set_build_active", true))
	assert_true(_mode().begin_buy(&"chair", Vector2i(3, 8)))
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("is_build_active"), "the final restored clock owns cancellation")
	assert_null(_preview().ghost_mesh)


func test_shared_layers_wait_for_normal_morning_save_then_reload_with_poses_paint_and_seats() -> void:
	await _start(true)
	var saved: String = _saved_build_text()
	var rng: Dictionary = GameState._capture_save()
	var content: ContentDB = _main.get("content") as ContentDB
	var rug_def: ItemDef = content.item(&"rug_square")
	_editor().set_owner_level(rug_def.unlock_level) # Explicit level-two purchase fixture.
	var origin: Vector2i = Vector2i(4, 8)
	assert_true(_main.call("shop_buy", rug_def.id, origin, 1))
	assert_true(_main.call("shop_buy", &"table_2", origin, 0))
	var rug: PlacedItem = _world().grid.item_on_layer(origin, ItemDef.PlacementLayer.FLOOR_DECOR)
	var table: PlacedItem = _world().grid.item_on_layer(origin, ItemDef.PlacementLayer.NORMAL)
	assert_not_null(rug)
	assert_not_null(table)
	if rug == null or table == null:
		return
	assert_true(_editor().paint_item(table.id, &"terracotta"))
	assert_eq(_saved_build_text(), saved, "both purchases and paint leave the current morning file unchanged")
	assert_eq(GameState._capture_save(), rng)
	var table_id: int = table.id
	var rug_id: int = rug.id
	var expected_tray_level: int = int(_main.get("tray_level"))
	var seats: Array[Vector2i] = table.seat_cells.duplicate()
	var path: Array[Vector2i] = _world().grid.find_path(_world().grid.entries()[0], seats[0])
	assert_false(path.is_empty())
	var shop: Dictionary = _editor().to_dict()
	var expected_shop_wire: Dictionary = shop.duplicate(true)
	expected_shop_wire["tray_level"] = expected_tray_level
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_eq(_saved_build_text(), saved, "closing also adds no action save")
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.day, 2)
	var document: Dictionary = JSON.parse_string(_saved_build_text())
	assert_eq(document["data"]["shop"], JSON.parse_string(JSON.stringify(expected_shop_wire)))
	var books: Dictionary = Economy._capture_save()
	var hiring_rng: int = GameState.rng(&"hiring").state
	_close_main()
	_main = MAIN.instantiate() as Node3D
	_main.set("save_slot", SLOT)
	_viewport.add_child(_main)
	_main.call("start")
	_disable_frame_drivers()
	assert_eq(Clock.sim.day, 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(int(_main.get("tray_level")), expected_tray_level)
	assert_eq(_editor().to_dict(), shop)
	assert_eq(Economy._capture_save(), books)
	assert_eq(GameState.rng(&"hiring").state, hiring_rng)
	rug = _world().grid.item_on_layer(origin, ItemDef.PlacementLayer.FLOOR_DECOR)
	table = _world().grid.item_on_layer(origin, ItemDef.PlacementLayer.NORMAL)
	assert_not_null(rug)
	assert_not_null(table)
	if rug == null or table == null:
		return
	assert_eq([rug.id, table.id], [rug_id, table_id])
	assert_eq([rug.quarter_turns, table.quarter_turns], [1, 0])
	assert_eq(table.swatch_id, &"terracotta")
	assert_eq(table.seat_cells, seats)
	for seat: Vector2i in seats:
		assert_eq(_world().grid.dining_table_id(seat), table.id)
		assert_eq(_world().grid.dining_furnishing_id(seat), table.id)
	assert_eq(_world().grid.find_path(_world().grid.entries()[0], seats[0]), path)
	assert_eq(_world().grid.items_at(origin), [table, rug] as Array[PlacedItem])
	assert_false(_world().grid.is_walkable(origin), "the normal table still determines blocking")
	assert_eq((_main.get_node("ShopView") as ShopView).item_nodes.size(), _world().grid.items().size())


func test_paint_during_service_previews_then_commits_without_books_or_immediate_save() -> void:
	await _start(true)
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("set_build_active", true))
	var plant: PlacedItem = _world().grid.item(_id(&"potted_plant"))
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var books: Dictionary = Economy.ledger.to_dict()
	var saved: String = FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))
	assert_true(_main.call("set_paint_active", true))
	assert_true(_main.call("is_paint_active"))
	_main.call("preview_paint_cell", plant.cells[0])
	assert_eq(plant.swatch_id, &"", "hover only changes the view")
	assert_eq(view.item_nodes[plant.id].primary_body_material().albedo_color,
		(_main.get("content") as ContentDB).swatch(&"butter").color)
	assert_true(_main.call("paint_cell", plant.cells[0]))
	assert_eq(plant.swatch_id, &"butter")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")), saved)
	assert_true(_main.call("set_paint_active", false))
	assert_false(_main.call("is_paint_active"))


func test_build_grid_toggles_with_g_or_the_grid_button_and_is_remembered() -> void:
	await _start()
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	assert_true(Preferences.build_grid_enabled, "Build shows the grid by default")
	if _rig().grid_visible:
		_rig().toggle_grid()
	assert_true(_main.call("set_build_active", true))
	assert_true(_rig().effective_grid_visible(), "on in Build even with G off elsewhere")
	assert_true(catalogue.grid_button.visible)
	assert_true(catalogue.grid_button.button_pressed)
	assert_eq(catalogue.grid_button.text, "Grid")
	assert_eq(catalogue.grid_button.tooltip_text, BuildCatalogue.GRID_TIP)
	catalogue.grid_button.pressed.emit()
	assert_false(_rig().effective_grid_visible())
	assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), false)
	assert_false(catalogue.grid_button.button_pressed)
	assert_false(Preferences.build_grid_enabled, "remembered for this player, not in the shop save")
	assert_false(_rig().grid_visible, "the G choice outside Build is untouched")
	# Leaving and coming back keeps the choice; G shows it again and the button follows.
	_key(KEY_ESCAPE)
	assert_false(_main.call("is_build_active"))
	assert_true(_main.call("set_build_active", true))
	assert_false(_rig().effective_grid_visible(), "Build remembers the hidden grid")
	_rig()._unhandled_input(_key_event(KEY_G))
	assert_true(_rig().effective_grid_visible())
	assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), true)
	assert_true(catalogue.grid_button.button_pressed)
	assert_true(Preferences.build_grid_enabled)
	# A fresh camera (a new session) reads the remembered choice.
	Preferences.build_grid_enabled = false
	var rig: CameraRig = CameraRig.new()
	_main.add_child(rig)
	assert_false(rig.build_grid_visible)
	rig.queue_free()
	Preferences.build_grid_enabled = true
	# Paint keeps the G choice and hides the button.
	_key(KEY_ESCAPE)
	assert_true(_main.call("set_paint_active", true))
	assert_false(catalogue.grid_button.visible)
	assert_true(_main.call("set_paint_active", false))


func test_paint_preserves_grid_preference_without_forcing_it() -> void:
	await _start()
	for preference: bool in [false, true]:
		if _rig().grid_visible != preference:
			_rig().toggle_grid()
		assert_true(_main.call("set_paint_active", true))
		assert_false(_rig().is_grid_forced())
		assert_eq(_rig().effective_grid_visible(), preference)
		assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), preference)
		assert_true(_main.call("set_paint_active", false))
		assert_false(_rig().is_grid_forced())
		assert_eq(_rig().grid_visible, preference)


func test_paint_screen_pick_uses_visible_item_depth_before_wall_or_floor() -> void:
	await _start()
	assert_true(_main.call("set_paint_active", true))
	var view: ShopView = _main.get_node("ShopView") as ShopView
	for def_id: StringName in [&"potted_plant", &"prep_counter"]:
		var item: PlacedItem = _world().grid.item(_id(def_id))
		var mesh: ItemVisual = view.item_nodes[item.id]
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		var top_center: Vector3 = bounds.position + Vector3(bounds.size.x * 0.5, bounds.size.y, bounds.size.z * 0.5)
		var pointer: Vector2 = _camera().unproject_position(top_center)
		assert_eq(_main.call("paint_cell_at_screen_position", pointer), item.origin,
			"a visible %s must win over its projected floor cell or rear wall" % def_id)
		_click(pointer)
		assert_eq(item.swatch_id, &"butter")
	assert_eq(_world().now, 0)


func test_catalogue_vibe_uid_scope_is_read_only_exact_and_rejects_missing_or_stale_records() -> void:
	var sources: Array[String] = ["res://src/sim/vibe/vibe_model.gd", "res://src/sim/vibe/vibe_tuning.gd",
		"res://tests/sim/test_vibe_model.gd", "res://src/sim/vibe/vibe_inputs.gd",
		"res://tests/sim/test_vibe_effects.gd", "res://tests/sim/test_vibe_swatches.gd",
		"res://src/ui/vibe_meter.gd", "res://tests/ui/test_vibe_meter.gd", "res://tests/world/test_vibe_session.gd"]
	assert_eq(CAPTURE.VIBE_UID_SOURCES, sources)
	var before: Dictionary = {}
	for path: String in sources:
		before[path] = {"exists": FileAccess.file_exists(path + ".uid"),
			"text": FileAccess.get_file_as_string(path + ".uid") if FileAccess.file_exists(path + ".uid") else "",
			"id": ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID}
	var evidence: Dictionary = CAPTURE.generated_uid_evidence(CAPTURE.VIBE_UID_SOURCES)
	assert_true(CAPTURE.catalogue_vibe_uids_valid(evidence), "normal import must provide genuine Vibe UID provenance: " + JSON.stringify(evidence))
	for index: int in range(sources.size()):
		var path: String = sources[index]
		var row: Dictionary = evidence["entries"][index]
		assert_eq(row["source"], path)
		assert_eq(row["sidecar_text"], before[path]["text"])
		assert_eq(row["registered_id"], str(before[path]["id"]))
		assert_eq(FileAccess.file_exists(path + ".uid"), before[path]["exists"])
		assert_eq(FileAccess.get_file_as_string(path + ".uid") if FileAccess.file_exists(path + ".uid") else "", before[path]["text"])
	assert_eq(CAPTURE.generated_uid_evidence()["entries"].size(), 5, "the loan default scope stays intact")
	assert_eq(CAPTURE.generated_uid_evidence(CAPTURE.CATALOGUE_UID_SOURCES)["entries"].size(), 9)
	assert_eq(CAPTURE.generated_uid_evidence(CAPTURE.STAFF_PRIORITY_UID_SOURCES)["entries"].size(), 6)
	assert_false(CAPTURE.catalogue_vibe_uids_valid({}))
	var wrong: Dictionary = evidence.duplicate(true)
	(wrong["entries"] as Array).pop_back()
	assert_false(CAPTURE.catalogue_vibe_uids_valid(wrong))
	wrong = evidence.duplicate(true)
	wrong["entries"][0]["sidecar_text"] = ""
	assert_false(CAPTURE.catalogue_vibe_uids_valid(wrong))
	wrong = evidence.duplicate(true)
	wrong["entries"][0]["registered_id"] = evidence["entries"][1]["registered_id"]
	assert_false(CAPTURE.catalogue_vibe_uids_valid(wrong), "a stale registered ID cannot agree with another sidecar's text")
	wrong = evidence.duplicate(true)
	wrong["entries"][0]["matches_registered"] = false
	assert_false(CAPTURE.catalogue_vibe_uids_valid(wrong))


func test_rustic_capture_fixture_uses_checked_links_paint_and_real_room_nodes() -> void:
	await _assert_catalogue_capture_fixture(&"rustic")


func test_modern_capture_fixture_uses_checked_links_paint_and_real_room_nodes() -> void:
	await _assert_catalogue_capture_fixture(&"modern")


func _assert_catalogue_capture_fixture(profile: StringName) -> void:
	await _start()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var fixture: Dictionary = CAPTURE.prepare_catalogue_review(_main, tree.root, profile)
	assert_eq(fixture["error"], "")
	assert_eq(fixture["kind"], "furnishing_fixture")
	assert_eq(fixture["removed_tables"], 3)
	assert_eq(fixture["simulation_ticks"], 0)
	assert_eq((_main.get("owner_progress") as OwnerProgress).level, 6)
	var content: ContentDB = _main.get("content") as ContentDB
	var recipe: Dictionary = CAPTURE.catalogue_review_profile(profile)
	var total: int = 0
	var purchased: Array[int] = []
	for row: Dictionary in recipe["items"]:
		var definition: ItemDef = content.item(row["id"])
		assert_true(definition.catalogue_visible, "capture purchases must remain available in the catalogue")
		total += definition.price
		var item: PlacedItem = _world().grid.item_on_layer(row["origin"], definition.placement_layer)
		assert_not_null(item)
		if item != null:
			assert_eq((item.def as ItemDef).id, definition.id)
			purchased.append(item.id)
	assert_eq(fixture["purchase_total"], total, "funding follows authored prices rather than a fixed fixture budget")
	assert_eq(fixture["purchased_ids"], purchased, "each purchase records its own layer's item")
	if profile == &"rustic":
		var rug: PlacedItem = _world().grid.item_on_layer(Vector2i(5, 6), ItemDef.PlacementLayer.FLOOR_DECOR)
		assert_not_null(rug)
		if rug != null:
			assert_eq((rug.def as ItemDef).id, &"rug_rectangle")
			assert_eq(rug.quarter_turns, 0)
			assert_false(rug.solid)
			for cell: Vector2i in [Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7)]:
				assert_eq(_world().grid.item_on_layer(cell, ItemDef.PlacementLayer.FLOOR_DECOR), rug)
				assert_not_null(_world().grid.item_on_layer(cell, ItemDef.PlacementLayer.NORMAL))
	var shop: ShopView = _main.get_node("ShopView") as ShopView
	shop._process(0.0) # Existing test driver keeps the world view's frame loop off.
	await _frames(2)
	var before: Dictionary = _catalogue_capture_snapshot()
	var catalogue: Dictionary = CAPTURE.catalogue_review_evidence(_main, tree.root)
	assert_eq(_catalogue_capture_snapshot(), before, "native evidence never requests a missing thumbnail")
	assert_eq(catalogue["dining_links"].size(), 4)
	assert_true((catalogue["dining_failures"] as Dictionary).is_empty())
	assert_true(catalogue["catalogue_visible"])
	_assert_catalogue_cards_match_data(catalogue, content)
	_assert_catalogue_vibe_matches_actual_sources(catalogue, 90)
	assert_true(CAPTURE.catalogue_tabs_valid(catalogue, recipe), "the real Buy tabs include Blueprints without an ItemDef room")
	var blueprint_index: int = -1
	for index: int in range(catalogue["tabs"].size()):
		if catalogue["tabs"][index]["id"] == String(BuildCatalogue.BLUEPRINTS):
			blueprint_index = index
	assert_true(blueprint_index >= 0)
	if blueprint_index >= 0:
		for field: String in ["shown", "text", "id"]:
			var invalid: Dictionary = catalogue.duplicate(true)
			invalid["tabs"][blueprint_index][field] = false if field == "shown" else "missing"
			assert_false(CAPTURE.catalogue_tabs_valid(invalid, recipe), "hidden or malformed Blueprints must fail")
		for field: String in ["visible", "inside_clip"]:
			var invalid: Dictionary = catalogue.duplicate(true)
			invalid["tabs"][blueprint_index]["native"][field] = false
			assert_false(CAPTURE.catalogue_tabs_valid(invalid, recipe), "Blueprints must be visibly inside the viewport")
		var missing: Dictionary = catalogue.duplicate(true)
		missing["tabs"].remove_at(blueprint_index)
		assert_false(CAPTURE.catalogue_tabs_valid(missing, recipe), "a missing tab must fail")
	var bad_meter: Dictionary = catalogue["vibe"].duplicate(true)
	bad_meter["meter"]["caption_bounds"][0] = float(bad_meter["meter"]["panel_bounds"][0]) - 10.0
	assert_false(CAPTURE.catalogue_vibe_valid(bad_meter, 90), "the native meter cannot be clipped out of its panel or scroll viewport")
	if DisplayServer.get_name() == "headless":
		assert_false(catalogue["cache"]["supported"])
		assert_false(catalogue["cache"]["icons_match"])
		assert_false(CAPTURE.catalogue_review_valid(catalogue, 90, fixture), "headless state never fabricates rendered previews")
	# Locked cards and unselected categories still belong to the expected set.
	var panel: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	panel.set_owner_level(1)
	await _frames(2)
	var locked: Dictionary = CAPTURE.catalogue_review_evidence(_main, tree.root)
	_assert_catalogue_cards_match_data(locked, content)
	var saw_locked: bool = false
	for card: Dictionary in locked["cards"]:
		if int(card["unlock_level"]) > 1:
			saw_locked = true
			assert_true(card["disabled"])
	assert_true(saw_locked)
	panel.set_owner_level(6)
	await _frames(2)
	assert_true(_main.call("set_build_active", false))
	await _frames(2)
	before = _catalogue_capture_snapshot()
	var room: Dictionary = CAPTURE.catalogue_review_evidence(_main, tree.root)
	_assert_catalogue_vibe_matches_actual_sources(room, 120)
	assert_true(CAPTURE.catalogue_review_valid(room, 120, fixture))
	assert_false(CAPTURE.catalogue_review_valid(room, 90, fixture))
	assert_eq(_catalogue_capture_snapshot(), before)
	assert_eq(_world().now, 0)
	assert_eq(_world().clock.phase, SimClock.Phase.MORNING)
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.OTHER, 0), fixture["cash_grant"])
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.UPGRADES, 0), fixture["refund"] - fixture["purchase_total"])
	assert_false(FileAccess.file_exists(_save_dir.path_join(SLOT + ".json")))
	# A broken final placement must be reported from the actual world, not a
	# profile label. Mutating only the detached evidence checks this gate.
	var wrong: Dictionary = room.duplicate(true)
	wrong.erase("vibe")
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "missing Vibe evidence fails closed")
	wrong = room.duplicate(true)
	wrong["vibe"]["main"]["score"] = float(wrong["vibe"]["main"]["score"]) + 0.5
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "stale Main state must disagree with the actual inputs")
	wrong = room.duplicate(true)
	wrong["vibe"]["meter"]["caption"] = "Vibe -"
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "native label text is read independently of cached view_state")
	wrong = room.duplicate(true)
	wrong["vibe"]["meter"]["value"] = NAN
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "nonfinite native values cannot pass approximate comparisons")
	wrong = room.duplicate(true)
	wrong["vibe"]["meter"]["view_state"]["tooltip"] = "Vibe unavailable"
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture))
	wrong = room.duplicate(true)
	wrong["vibe"]["meter"]["fill_color"] = [0.0, 0.0, 0.0, 0.0]
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "the meter retains the shared theme")
	wrong = room.duplicate(true)
	wrong.erase("generated_vibe_uids")
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture))
	wrong = room.duplicate(true)
	wrong["generated_vibe_uids"]["entries"][0]["matches_registered"] = false
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture))
	wrong = room.duplicate(true)
	wrong["vibe"]["meter"]["caption_bounds"] = [0.0, 0.0, 0.0, 0.0]
	assert_true(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "hidden closed-catalogue controls need not be onscreen")
	wrong = room.duplicate(true)
	wrong["dining_links"][0]["front_table"] = 0
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture))
	wrong = room.duplicate(true)
	(wrong["cards"] as Array).pop_back()
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "missing cards cannot shrink the expected data set")
	wrong = room.duplicate(true)
	(wrong["cache"]["expected_scenes"] as Array).pop_back()
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "expected wrappers are checked against all visible data")
	wrong = room.duplicate(true)
	# Locate a purchased record, rather than assuming item order after table sales.
	for item: Dictionary in wrong["items"]:
		if purchased.has(item["id"]):
			item["catalogue_visible"] = false
			break
	assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture))
	if profile == &"rustic":
		assert_eq(room["server"]["cell"], [8, 8])
		assert_true(room["server"]["native_person"])
		assert_true(room["server"]["visible"])
		assert_true(room["server"]["model_visible"])
		assert_eq(room["server"]["clip"], "idle")
		assert_eq(room["server"]["model"], room["server"]["expected_model"])
		wrong = room.duplicate(true)
		wrong["server"]["visible"] = false
		assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "a hidden server cannot prove the person-beside-rug requirement")
		wrong = room.duplicate(true)
		wrong["server"]["head"]["in_frustum"] = false
		assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture))
		wrong = room.duplicate(true)
		for item: Dictionary in wrong["items"]:
			if item["definition"] == "rug_rectangle":
				item["coverage"] = []
				break
		assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "layer coverage must prove the table and both chairs are on the rug")
		wrong = room.duplicate(true)
		for item: Dictionary in wrong["items"]:
			if item["definition"] == "rug_rectangle":
				for cell: Dictionary in item["coverage"]:
					if cell["normal"] != 0:
						cell["normal"] = 0
						break
		assert_false(CAPTURE.catalogue_review_valid(wrong, 120, fixture), "normal and floor-decor indexes must agree with the actual furniture")


func _assert_catalogue_vibe_matches_actual_sources(state: Dictionary, frame: int) -> void:
	var menu: MenuSettings = _main.get("menu_settings") as MenuSettings
	var content: ContentDB = _main.get("content") as ContentDB
	var inputs: VibeModel.Inputs = VibeInputs.capture(_world().grid, content, menu.enabled_recipes(),
		_editor().wall_swatch_id, _editor().floor_vibe_swatch())
	var fresh: VibeModel.Result = VibeModel.evaluate(inputs, CAPTURE.VIBE_TERMS)
	var vibe: Dictionary = state["vibe"]
	assert_true(fresh.valid)
	assert_true(CAPTURE.catalogue_vibe_valid(vibe, frame), "actual meter/Main/pure Vibe mismatch: " + JSON.stringify(vibe))
	assert_eq(vibe["expected"]["score"], fresh.score)
	assert_eq(vibe["expected"]["active_theme"], String(fresh.active_theme))
	assert_eq(vibe["expected"]["theme_label"], fresh.theme_label)
	assert_eq(vibe["main"], vibe["expected"])
	assert_eq(vibe["meter"]["caption"], "Vibe %d / 100" % roundi(fresh.score))
	assert_eq(vibe["meter"]["value"], fresh.score)
	assert_eq(vibe["inputs"]["wall"], String(_editor().wall_swatch_id))
	assert_eq(vibe["inputs"]["floor"], String(_editor().floor_vibe_swatch()))
	var ids: Array[String] = []
	for recipe: RecipeDef in menu.enabled_recipes():
		ids.append(String(recipe.id))
	ids.sort()
	assert_eq(vibe["inputs"]["menu_ids"], ids)
	assert_true(CAPTURE.catalogue_vibe_uids_valid(state["generated_vibe_uids"]), JSON.stringify(state["generated_vibe_uids"]))
	assert_eq(vibe["meter"]["visible"], frame == 90)


func _assert_catalogue_cards_match_data(state: Dictionary, content: ContentDB) -> void:
	var wanted: Array[String] = []
	var wrappers: Array[String] = []
	for definition: ItemDef in content.items():
		if not definition.catalogue_visible or definition.id.is_empty() or definition.display_name.strip_edges().is_empty() \
				or definition.price < 0 or definition.unlock_level < 1 or definition.footprint.x < 1 or definition.footprint.y < 1 \
				or not definition.placement_layer_valid() or definition.category < ItemDef.Category.TABLE \
				or definition.category > ItemDef.Category.WAITING:
			continue
		wanted.append(String(definition.id))
		if definition.view_scene != null and not wrappers.has(definition.view_scene.resource_path):
			wrappers.append(definition.view_scene.resource_path)
	# The Walls tab's Kenney piece previews share the same thumbnail cache.
	for wall: WallKindDef in content.wall_kinds():
		if wall.thumbnail_scene != null and not wrappers.has(wall.thumbnail_scene.resource_path):
			wrappers.append(wall.thumbnail_scene.resource_path)
	# So does the Floor card (FK-080).
	if not wrappers.has(BuildCatalogue.FLOOR_THUMBNAIL.resource_path):
		wrappers.append(BuildCatalogue.FLOOR_THUMBNAIL.resource_path)
	wanted.sort()
	wrappers.sort()
	var actual: Array[String] = []
	for card: Dictionary in state["cards"]:
		actual.append(card["id"])
	actual.sort()
	assert_eq(actual, wanted, "all valid visible data, including locked and other-category entries, has one real card")
	assert_eq(state["cache"]["expected_scenes"], wrappers)
	assert_eq(state["cache"]["expected"], wrappers.size())
	for hidden: StringName in [&"plant_small_1", &"plant_small_2", &"plant_small_3"]:
		assert_false(content.item(hidden).catalogue_visible)
		assert_false(actual.has(String(hidden)))
	assert_true(actual.has("potted_plant"))
	assert_true(actual.has("waiting_bench"), "waiting seats remain real catalogue cards")


func _catalogue_capture_snapshot() -> Dictionary:
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var agents: Array[Dictionary] = []
	for agent: SimAgent in _world().agents:
		agents.append({"id": agent.id, "cell": agent.cell, "path": agent.path.duplicate(),
			"path_index": agent.path_index, "move_progress": agent.move_progress})
	return {"books": Economy.ledger.to_dict(), "shop": _editor().to_dict(), "world_tick": _world().now,
		"vibe": CAPTURE._vibe_result_record(_main.get("vibe_result") as VibeModel.Result),
		"menu": (_main.get("menu_settings") as MenuSettings).to_dict(),
		"rng": [sim.rng.seed, sim.rng.state], "pending": catalogue._thumbnails.pending_count(),
		"cached": catalogue._thumbnails.cached_count(), "category": catalogue.selected_category, "agents": agents}


func _start(with_saves: bool = false) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame  # The custom runner may begin before root entry.
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", with_saves)
	_main.set("save_slot", SLOT)
	_viewport.add_child(_main)
	_main.call("start")
	_disable_frame_drivers()
	await _frames(3)
	assert_true(_main.is_inside_tree())
	assert_true(_camera().is_inside_tree())
	assert_eq(_viewport.get_visible_rect().size, Vector2(1600.0, 900.0))


func _disable_frame_drivers() -> void:
	Clock.set_speed(0)
	_main.set_process(false)
	_rig().set_process(false)
	_rig().edge_pan_enabled = false
	(_main.get_node("ShopView") as ShopView).set_process(false)


func _close_main() -> void:
	if not is_instance_valid(_main):
		return
	if _main.get_parent() != null:
		_main.get_parent().remove_child(_main)
	_main.free()
	_main = null


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for frame: int in range(count):
		await tree.process_frame


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _mode() -> BuildMode:
	return _main.get("build_mode") as BuildMode


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _rig() -> CameraRig:
	return _main.get_node("CameraRig") as CameraRig


func _camera() -> Camera3D:
	return _main.get_node("CameraRig/Camera3D") as Camera3D


func _preview() -> BuildPreview:
	return _main.get_node("BuildPreview") as BuildPreview


func _id(def_id: StringName) -> int:
	return ShopBuilder.items_with_def(_world(), def_id)[0].id


func _project(cell: Vector2i) -> Vector2:
	return _camera().unproject_position(GridMath.cell_to_world(cell))


func _click(point: Vector2) -> void:
	_main.call("_unhandled_input", _mouse_event(point, true))


func _native_click(point: Vector2, alt: bool = false) -> void:
	_viewport.push_input(_mouse_event(point, true, alt), true)
	_viewport.push_input(_mouse_event(point, false, alt), true)


func _assert_world_click_clear_of_gui(point: Vector2) -> void:
	assert_true(_viewport.get_visible_rect().has_point(point))
	assert_false((_main.get_node("HUD/Top") as Control).get_global_rect().has_point(point))
	assert_false((_main.get_node("HUD/BuildHints") as Control).get_global_rect().has_point(point))
	assert_false((_main.get_node("Overlay/BuildCatalogue/Panel") as Control).get_global_rect().has_point(point))


func _normal_furniture_state(table: PlacedItem) -> Dictionary:
	var visual: ItemVisual = (_main.get_node("ShopView") as ShopView).item_nodes[table.id]
	var chairs: Array[int] = []
	for child: Node in visual.prop.get_children():
		if child.has_meta(&"seat_cell"):
			chairs.append(child.get_instance_id())
	assert_eq(chairs.size(), 2, "retain both native built-in chairs")
	return {"item": table, "origin": table.origin, "turns": table.quarter_turns,
		"cells": table.cells.duplicate(), "seats": table.seat_cells.duplicate(),
		"reservations": table._reservations.duplicate(), "visual": visual.get_instance_id(),
		"prop": visual.prop.get_instance_id(), "chairs": chairs, "transform": visual.transform,
		"body": visual.primary_body_material().get_instance_id(), "visible": visual.visible}


func _build_side_effect_state() -> Dictionary:
	return {"cash": Economy.cash, "books": Economy.ledger.to_dict(), "stock": Economy.stock.to_dict(),
		"clock": Clock.sim.to_dict(), "speed": Clock.speed, "tick": _world().now,
		"rng": GameState._capture_save(), "saved": _saved_build_text()}


func _saved_build_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _mouse_event(point: Vector2, down: bool, alt: bool = false) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	event.alt_pressed = alt
	return event


func _key_event(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _key(code: Key) -> void:
	_main.call("_unhandled_input", _key_event(code))


func _assert_hint_content_fits(label: Label, scroll: ScrollContainer) -> void:
	assert_eq(scroll.custom_minimum_size.y, ceilf(label.get_minimum_size().y), "height follows the final native text width")
	assert_false(scroll.get_v_scroll_bar().visible, "a short desktop hint has no vertical scrollbar")
	assert_false(scroll.get_h_scroll_bar().visible, "a short desktop hint has no horizontal scrollbar")
	assert_true(scroll.get_v_scroll_bar().max_value <= scroll.get_v_scroll_bar().page)
	assert_true(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page)
	assert_true(label.size.x <= scroll.size.x)
	assert_true(label.size.y <= scroll.size.y, "the whole native Label fits inside the scroll viewport")


func _native_key(code: Key) -> void:
	var event: InputEventKey = _key_event(code)
	_viewport.push_input(event, true)
	event.pressed = false
	_viewport.push_input(event, true)
