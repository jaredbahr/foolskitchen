extends TestCase
## Real Main, Camera3D projection, GUI dispatch, editor and Economy wiring.
## Source only until CI runs it; manual feel and rendered legibility are separate.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "build_session"

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


func test_projected_world_clicks_match_editor_for_four_camera_quarters_and_four_world_turns() -> void:
	await _start()
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
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	await _frames(3)
	var button: Button = catalogue.item_buttons[&"fridge"]
	var identity: int = button.get_instance_id()
	var books: Dictionary = Economy.ledger.to_dict()
	var items: int = _world().grid.items().size()
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


func test_build_hints_match_available_actions_and_fit_content_or_small_viewport_scroll() -> void:
	await _start()
	assert_true(_main.call("set_build_active", true))
	var label: Label = _main.get_node("HUD/BuildHints/Scroll/Text") as Label
	var panel: PanelContainer = _main.get_node("HUD/BuildHints") as PanelContainer
	var scroll: ScrollContainer = _main.get_node("HUD/BuildHints/Scroll") as ScrollContainer
	await _frames(2)
	assert_eq(label.text, "Esc Exit")
	assert_true(panel.size.x < 700.0 and panel.size.y < 96.0, "one-line hints follow their content")
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	assert_true(label.text.contains("R Rotate"))
	assert_false(label.text.contains("Del Sell"))
	assert_true(_mode().pick_up(_id(&"potted_plant")))
	assert_true(label.text.contains("Del Sell"))
	_mode().cancel()
	assert_eq(label.text, "Esc Exit")
	# Reproduce the real two-line red hint through the same proposal as capture.
	assert_true(_main.call("begin_buy_item", &"fridge"))
	assert_true(_main.call("update_build_pointer", _project(Vector2i(7, 7))))
	_key(KEY_R)
	assert_false(_mode().current_check.ok)
	await _frames(3)
	assert_eq(label.text, "R Rotate  |  Esc Cancel\nSomething is in the way")
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
		assert_eq(_rig().grid_visible, preference, "G cannot overwrite the saved preference while forced")
		_key(KEY_ESCAPE)
		assert_eq(_rig().grid_material.get_shader_parameter("grid_visible"), preference)
	if _rig().grid_visible:
		_rig().toggle_grid()
	assert_true(_main.call("set_build_active", true))
	_click(_project(_world().grid.item(_id(&"potted_plant")).cells[0]))
	var old_mesh: MeshInstance3D = (_main.get_node("ShopView") as ShopView).item_nodes[_id(&"potted_plant")]
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
	_main.call("update_build_pointer", _project(Vector2i(4, 9)))
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
	assert_true((_main.get_node("HUD/BuildHints/Scroll/Text") as Label).text.contains(_mode().current_check.why))
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
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 9)))
	_click(_project(Vector2i(4, 9)))
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
	assert_true(_mode().begin_buy(&"chair", Vector2i(4, 8)))
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("is_build_active"), "the final restored clock owns cancellation")
	assert_null(_preview().ghost_mesh)


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


func _mouse_event(point: Vector2, down: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
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
