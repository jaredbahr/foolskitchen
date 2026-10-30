extends TestCase
## Actual Main editor, cached UI, morning persistence and native Control layout.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "joined_table_session"

var _main: Node3D
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary
var _old_size: Vector2i
var _old_scale: float
var _tables: Array[PlacedItem] = []


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate(true)
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "joined_table_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	var window: Window = (Engine.get_main_loop() as SceneTree).root
	_old_size = window.size
	_old_scale = window.content_scale_factor


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _old_providers
	var window: Window = (Engine.get_main_loop() as SceneTree).root
	window.size = _old_size
	window.content_scale_factor = _old_scale
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_live_hover_and_inspect_each_physical_member_report_six_seats_and_refresh_when_split_while_paused() -> void:
	await _start()
	_join_starter_tables()
	var before_rng: Dictionary = GameState.call("_capture_save")
	var before_now: int = _world().now
	assert_true(_main.call("set_build_active", true))
	for table: PlacedItem in _tables:
		_mode().hover_item(table.id)
		assert_eq(_mode().dining_summary(), "Seats 6 (joined table)")
		assert_eq(_mode().hover_summary(), "Seats 6 (joined table)")
	assert_true(_main.call("set_build_active", false))
	var panel: InspectPanel = _panel()
	for table: PlacedItem in _tables:
		panel.show_item(table.id)
		panel.refresh()
		assert_true((panel.get_node("Panel/Rows/Details") as Label).text.contains("Seats 6 (joined table)"))
		assert_eq((panel.get_node("Panel/Rows/Reservations") as Label).text.split("\n").size(), 6)
	assert_true(_main.call("shop_move", _tables[1].id, Vector2i(10, 6), 1))
	panel.show_item(_tables[0].id)
	panel.refresh()
	assert_true((panel.get_node("Panel/Rows/Details") as Label).text.contains("Seats 2"))
	assert_false((panel.get_node("Panel/Rows/Details") as Label).text.contains("joined"))
	assert_eq((panel.get_node("Panel/Rows/Reservations") as Label).text.split("\n").size(), 2)
	assert_eq(_world().now, before_now)
	assert_eq(GameState.call("_capture_save"), before_rng)


func test_valid_buy_and_move_ghosts_use_proposed_group_capacity_without_editing_live_world() -> void:
	await _start()
	_join_starter_tables()
	assert_true(_main.call("set_build_active", true))
	var before: Dictionary = _editor().to_dict()
	var cash: int = Economy.cash
	assert_true(_mode().begin_buy(&"table_2", Vector2i(9, 6)))
	# Rotate the held model to the same north/south chair orientation.
	assert_true(_mode().rotate())
	assert_true(_mode().current_check.ok)
	assert_eq(_mode().current_check.dining_capacity, 8)
	assert_true(_mode().current_check.dining_joined)
	assert_eq(_mode().dining_summary(), "Seats 8 (joined table)")
	assert_eq(_editor().to_dict(), before)
	assert_eq(Economy.cash, cash)
	_mode().cancel_ghost()
	assert_true(_mode().pick_up(_tables[2].id))
	_mode().update_origin(Vector2i(10, 6))
	assert_true(_mode().current_check.ok)
	assert_eq(_mode().current_check.dining_capacity, 2)
	assert_false(_mode().current_check.dining_joined)
	assert_eq(_mode().dining_summary(), "Seats 2")
	assert_eq(_editor().to_dict(), before)
	_mode().update_origin(Vector2i(3, 6))
	assert_false(_mode().current_check.ok)
	assert_eq(_mode().dining_summary(), "", "an overlapping refusal does not advertise a valid joined capacity")
	_mode().cancel_ghost()


func test_normal_editor_refuses_unreserved_member_edits_and_new_joins_while_another_member_is_occupied() -> void:
	await _start()
	_join_starter_tables()
	var seat: Vector2i = _tables[0].seat_cells[0]
	assert_true(_tables[0].reserve(seat, 246001))
	var before: Dictionary = _editor().to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	assert_false(_editor().check_move(_tables[2].id, Vector2i(10, 6), 1).ok)
	assert_false(_main.call("shop_move", _tables[2].id, Vector2i(10, 6), 1))
	assert_false(_editor().check_sell(_tables[2].id).ok)
	assert_eq(_editor().sell(_tables[2].id), -1)
	assert_false(_editor().check_buy(&"table_2", Vector2i(9, 6), 1).ok)
	assert_false(_main.call("shop_buy", &"table_2", Vector2i(9, 6), 1))
	assert_eq(_editor().to_dict(), before)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(_tables[0].reserved_by(seat), 246001)
	assert_true(_tables[0].release(seat, 246001))
	assert_true(_main.call("shop_move", _tables[2].id, Vector2i(10, 6), 1))
	assert_eq(_world().grid.dining_group_members(_tables[0].id).size(), 2)
	assert_true(_main.call("set_build_active", true), "undo is invoked through the real active Build flow")
	assert_true(_main.call("undo_edit"))
	assert_eq(_world().grid.dining_group_members(_tables[0].id).size(), 3)
	assert_true(_main.call("redo_edit"))
	assert_eq(_world().grid.dining_group_members(_tables[0].id).size(), 2)


func test_six_actual_bookings_are_visible_in_every_member_inspector_within_native_window_bounds() -> void:
	await _start()
	_join_starter_tables()
	var randoms: Array[RandomNumberGenerator] = []
	for index: int in 6:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 24650 + index
		randoms.append(random)
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var party: Party = sim.add_party(_world().grid.entries()[0], randoms)
	assert_true(PartySeating.try_seat(party, _world(), sim.kitchen))
	var panel: InspectPanel = _panel()
	var window: Window = (Engine.get_main_loop() as SceneTree).root
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		window.size = dimensions
		for scale: float in [1.0, 1.5]:
			window.content_scale_factor = scale
			for table: PlacedItem in _tables:
				panel.show_item(table.id)
				panel.refresh()
				await _frames(3)
				var body: Control = panel.get_node("Panel") as Control
				var details: Label = panel.get_node("Panel/Rows/Details") as Label
				var reservations: Label = panel.get_node("Panel/Rows/Reservations") as Label
				assert_true(details.text.contains("Seats 6 (joined table)"))
				assert_eq(reservations.text.split("\n").size(), 6)
				assert_false(reservations.text.contains(": Free"))
				for guest: CustomerAgent in PartySeating.members(party, _world()):
					assert_true(reservations.text.contains(str(guest.seat_cell)))
				assert_true(window.get_visible_rect().grow(1.0).encloses(body.get_global_rect()),
					"six actual reservation rows fit the native window at each supported scale")
				assert_true(body.get_global_rect().grow(1.0).encloses(details.get_global_rect()))
				assert_true(body.get_global_rect().grow(1.0).encloses(reservations.get_global_rect()))


func test_joined_groups_remain_derived_across_real_next_morning_save_and_new_world_rebind() -> void:
	await _start(true)
	var original_file: String = FileAccess.get_file_as_string(_path())
	_join_starter_tables()
	assert_eq(FileAccess.get_file_as_string(_path()), original_file, "moving tables adds no save boundary")
	assert_true(_main.call("set_build_active", true))
	_mode().hover_item(_tables[0].id)
	assert_eq(_mode().dining_summary(), "Seats 6 (joined table)")
	assert_true(_main.call("set_build_active", false))
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path())) as Dictionary
	var shop: Dictionary = saved["data"]["shop"]
	assert_false(shop.has("groups"))
	assert_false(shop.has("dining_groups"))
	assert_false((saved["data"] as Dictionary).has("dining_groups"))
	for item: Dictionary in shop["items"]:
		assert_false(item.has("group_id"))
		assert_false(item.has("booked_table_ids"))
	var old_world: SimWorld = _world()
	_close()
	await _start(true)
	assert_false(_world() == old_world)
	assert_eq(Clock.sim.day, 2)
	assert_eq(DiningSeats.largest_usable_capacity(_world().grid), 6)
	_tables.assign(ShopBuilder.items_with_def(_world(), &"table_2"))
	assert_true(_main.call("set_build_active", true))
	for table: PlacedItem in _tables:
		_mode().hover_item(table.id)
		assert_eq(_mode().dining_summary(), "Seats 6 (joined table)")
	assert_true(_main.call("set_build_active", false))
	_panel().show_item(_tables[2].id)
	_panel().refresh()
	assert_true((_panel().get_node("Panel/Rows/Details") as Label).text.contains("Seats 6 (joined table)"))


func _start(with_saves: bool = false) -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", with_saves)
	_main.set("save_slot", SLOT)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	_main.get_node("CameraRig").set_process(false)
	_main.get_node("ShopView").set_process(false)
	Clock.set_speed(0)
	await _frames(3)


func _join_starter_tables() -> void:
	_tables.assign(ShopBuilder.items_with_def(_world(), &"table_2"))
	assert_eq(_tables.size(), 3)
	for index: int in _tables.size():
		assert_true(_main.call("shop_move", _tables[index].id, Vector2i(3 + index * 2, 6), 1))
	assert_eq(DiningSeats.largest_usable_capacity(_world().grid), 6)


func _close() -> void:
	_tables.clear()
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _mode() -> BuildMode:
	return _main.get("build_mode") as BuildMode


func _panel() -> InspectPanel:
	return _main.get_node("Overlay/InspectPanel") as InspectPanel


func _frames(count: int) -> void:
	for index: int in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func test_rebinding_existing_inspector_and_build_controller_drops_old_same_id_group_cache() -> void:
	await _start()
	_join_starter_tables()
	assert_true(_main.call("set_build_active", true))
	_mode().hover_item(_tables[0].id)
	assert_eq(_mode().dining_summary(), "Seats 6 (joined table)")
	var panel: InspectPanel = _panel()
	panel.show_item(_tables[0].id)
	panel.refresh()
	var replacement: RestaurantSim = RestaurantSim.new()
	replacement.world = SimWorld.new(SimGrid.new(Vector2i(16, 16)), SimClock.new())
	replacement.world.grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.ENTRY)
	for index: int in _tables[0].id - 1:
		assert_not_null(replacement.world.grid.place(Vector2i.ONE, Vector2i(0, index + 1), 0, false))
	var lone: PlacedItem = replacement.world.grid.place_def(preload("res://data/items/table_2.tres"), Vector2i(5, 5), 1)
	assert_eq(lone.id, _tables[0].id, "the replacement reuses the old leader ID but is a different grid")
	var content: ContentDB = _main.get("content") as ContentDB
	var editor: ShopEditor = ShopEditor.new(replacement, content, ShopEditBooks.new())
	_mode().bind_session(editor, replacement.world, content, editor.move, editor.buy, editor.sell)
	assert_true(_mode().enter())
	_mode().hover_item(lone.id)
	assert_eq(_mode().dining_summary(), "Seats 2")
	panel.bind_world(replacement.world)
	panel.show_item(lone.id)
	panel.refresh()
	assert_true((panel.get_node("Panel/Rows/Details") as Label).text.contains("Seats 2"))
	assert_false((panel.get_node("Panel/Rows/Details") as Label).text.contains("joined"))
	assert_eq((panel.get_node("Panel/Rows/Reservations") as Label).text.split("\n").size(), 2)
	assert_eq(replacement.world.now, 0)


func test_occupied_singleton_cannot_move_or_accept_joins_but_its_legacy_sale_still_clears_the_hold() -> void:
	await _start()
	_tables.assign(ShopBuilder.items_with_def(_world(), &"table_2"))
	assert_eq(_tables.size(), 3)
	var single: PlacedItem = _tables[0]
	var incoming: PlacedItem = _tables[2]
	assert_eq(single.origin, Vector2i(2, 6))
	assert_eq(_world().grid.dining_group_members(single.id), [single.id] as Array[int])
	assert_true(_editor().check_move(single.id, Vector2i(2, 8), 0).ok,
		"the singleton relocation is legal before the hold")
	assert_true(_editor().check_buy(&"table_2", Vector2i(4, 6), 1).ok,
		"the proposed new-table join is legal before the hold")
	assert_true(_editor().check_move(incoming.id, Vector2i(4, 6), 1).ok,
		"the proposed moved-table join is legal before the hold")
	var held_seat: Vector2i = Vector2i(1, 7)
	assert_true(single.seat_cells.has(held_seat))
	assert_true(single.reserve(held_seat, 246002))
	var layout: Dictionary = _editor().to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var cash: int = Economy.cash
	var relocation: EditCheck = _editor().check_move(single.id, Vector2i(2, 8), 0)
	var purchase: EditCheck = _editor().check_buy(&"table_2", Vector2i(4, 6), 1)
	var joining: EditCheck = _editor().check_move(incoming.id, Vector2i(4, 6), 1)
	for check: EditCheck in [relocation, purchase, joining]:
		assert_false(check.ok)
		assert_true(check.why.contains("in use"), "the actual hold, rather than incidental placement, refuses the edit")
	assert_false(_main.call("shop_move", single.id, Vector2i(2, 8), 0))
	assert_false(_main.call("shop_buy", &"table_2", Vector2i(4, 6), 1))
	assert_false(_main.call("shop_move", incoming.id, Vector2i(4, 6), 1))
	assert_eq(_editor().to_dict(), layout)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.cash, cash)
	assert_eq(single.reserved_by(held_seat), 246002)
	assert_true(_editor().check_sell(single.id).ok, "legacy singleton sale remains a valid cancellation path")
	assert_eq(_editor().sell(single.id), 20)
	assert_null(_world().grid.item(single.id))
	assert_eq(single.reserved_by(held_seat), -1)
	assert_eq(Economy.cash, cash + 20)
