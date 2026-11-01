extends TestCase
## FK-100: real Build previews, atomic refusals and the opening notice.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "build_menu_access"
var _main: Node
var _old_dir: String
var _dir: String
var _providers: Dictionary[String, Dictionary]


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	SaveSystem._providers = _providers
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 23)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Economy.add_cash(1500, Ledger.OTHER)


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _settings() -> MenuSettings:
	return _main.get("menu_settings") as MenuSettings


func _grid() -> SimGrid:
	return (_main.get("world") as SimWorld).grid


func _item(id: StringName) -> PlacedItem:
	for placed: PlacedItem in _grid().items():
		if (placed.def as ItemDef).id == id:
			return placed
	return null


func _add_fryer() -> void:
	assert_true(_settings().set_owner_level(2))
	_editor().set_owner_level(2)
	assert_true(_main.call("shop_buy", &"fryer", Vector2i(9, 3), 0))
	assert_true(_main.call("menu_set_enabled", &"fries", true))


func test_furniture_preview_names_enabled_dishes_on_the_existing_amber_line_without_mutation() -> void:
	await _start()
	_add_fryer()
	assert_true(_main.call("set_build_active", true))
	var mode: BuildMode = _main.get("build_mode") as BuildMode
	assert_true(mode.pick_up(_item(&"potted_plant").id))
	var shop: Dictionary = _editor().to_dict()
	var menu: Dictionary = _settings().to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var random: Dictionary = GameState.call("_capture_save")
	var saved: String = FileAccess.get_file_as_string(SaveSystem._slot_path(SLOT))
	mode.update_origin(_item(&"fryer").work_cells[0])
	assert_true(mode.current_check.ok, mode.current_check.why)
	var warning: String = "Fries will leave the menu: staff can't reach the fryer"
	assert_eq(mode.current_check.menu_warning, warning)
	var hud: Node = _main.get_node("HUD")
	var label: Label = hud.get("_build_warning_text") as Label
	assert_true(label.visible)
	assert_eq(label.text, warning)
	assert_eq(label.get_theme_color("font_color"), hud.get("ADVICE_COLOR"))
	assert_eq(_editor().to_dict(), shop)
	assert_eq(_settings().to_dict(), menu)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(GameState.call("_capture_save"), random)
	assert_eq(FileAccess.get_file_as_string(SaveSystem._slot_path(SLOT)), saved)


func test_blocking_the_only_unlocked_cooking_line_is_refused_atomically() -> void:
	await _start()
	var shop: Dictionary = _editor().to_dict()
	var menu: Dictionary = _settings().to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var stove: PlacedItem = _item(&"stove")
	var plant: PlacedItem = _item(&"potted_plant")
	var check: EditCheck = _editor().check_move(plant.id, stove.work_cells[0], 0)
	assert_false(check.ok)
	assert_eq(check.why, MenuAccess.NO_DISH)
	assert_false(_main.call("shop_move", plant.id, stove.work_cells[0], 0))
	assert_eq(_editor().to_dict(), shop)
	assert_eq(_settings().to_dict(), menu)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_false((_main.get("edit_history") as ShopEditHistory).can_undo())


func test_reachable_second_station_keeps_the_dish_and_suppresses_the_warning() -> void:
	await _start()
	_add_fryer()
	assert_true(_main.call("shop_buy", &"fryer", Vector2i(1, 3), 0))
	var check: EditCheck = _editor().check_move(_item(&"potted_plant").id, Vector2i(9, 2), 0)
	assert_true(check.ok, check.why)
	assert_eq(check.menu_warning, "")
	assert_true(check.menu_losses.is_empty())


func test_food_needs_a_reachable_fridge_and_both_pass_sides_but_drinks_do_not() -> void:
	await _start()
	var plant: PlacedItem = _item(&"potted_plant")
	var spots: Array[Vector2i] = _item(&"fridge").work_cells.duplicate()
	spots.append_array(_item(&"pass_counter").work_cells)
	for spot: Vector2i in spots:
		var refused: EditCheck = _editor().check_move(plant.id, spot, 0)
		assert_false(refused.ok)
		assert_true(refused.why == MenuAccess.NO_DISH or refused.why == RoomRules.PASS_SIDES,
			"the menu guard or existing room-side guard protects this support")
	assert_true(_main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	var check: EditCheck = _editor().check_move(plant.id, _item(&"fridge").work_cells[0], 0)
	assert_true(check.ok, check.why)
	assert_true(check.menu_warning.ends_with("staff can't reach the fridge"), check.menu_warning)
	assert_eq(check.menu_losses.size(), 3)
	assert_true(_main.call("shop_move", plant.id, _item(&"fridge").work_cells[0], 0))
	assert_true(_settings().is_enabled(&"coffee"))
	assert_null(_settings().recipe(&"burger"))


func test_undo_redo_restores_menu_prices_and_cash_exactly_and_open_names_the_loss() -> void:
	await _start()
	_add_fryer()
	assert_true(_main.call("menu_set_price", &"fries", 6))
	assert_true(_main.call("set_build_active", true))
	var menu: Dictionary = _settings().to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var cash: int = Economy.cash
	assert_true(_main.call("shop_move", _item(&"potted_plant").id, _item(&"fryer").work_cells[0], 0))
	assert_null(_settings().recipe(&"fries"))
	assert_true(_main.call("undo_edit"))
	assert_eq(_settings().to_dict(), menu)
	assert_eq(Economy.cash, cash)
	assert_eq(Economy.ledger.to_dict(), books, "a move and its undo never book money")
	assert_true(_main.call("redo_edit"))
	assert_null(_settings().recipe(&"fries"))
	assert_true(Clock.sim.start_service())
	var note: String = "Fries left today's menu: staff can't reach the fryer"
	assert_eq(_main.call("menu_open_note"), note)
	assert_true((_main.get_node("HUD/MenuNotice") as Control).visible)
	assert_eq((_main.get_node("HUD/MenuNotice/Text") as Label).text, note)
	assert_eq(Economy.cash, cash, "opening buys no supplies for the lost dish")


func test_undo_before_opening_removes_the_notice_and_disabled_dishes_are_not_named() -> void:
	await _start()
	_add_fryer()
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("shop_move", _item(&"potted_plant").id, _item(&"fryer").work_cells[0], 0))
	assert_true(_main.call("undo_edit"))
	assert_true(_main.call("menu_set_enabled", &"fries", false))
	assert_true(_main.call("shop_move", _item(&"potted_plant").id, _item(&"fryer").work_cells[0], 0))
	assert_true(Clock.sim.start_service())
	assert_eq(_main.call("menu_open_note"), "")
	assert_false((_main.get_node("HUD/MenuNotice") as Control).visible)


func test_wall_refusal_keeps_named_dish_advice_without_weakening_the_work_spot_guard() -> void:
	await _start()
	_add_fryer()
	var changes: Dictionary[Vector3i, int] = {}
	for adjacent: Vector2i in [Vector2i(8, 2), Vector2i(9, 1), Vector2i(10, 2)]:
		changes[SimGrid.edge_between(Vector2i(9, 2), adjacent)] = SimGrid.Segment.WALL
	# Row 4 is now floor, so the sink can reach the new route around the fryer.
	# Enclose its actual work cell too, retaining the sink-specific guard.
	var sink_work: Vector2i = _item(&"sink").work_cells[0]
	changes[SimGrid.edge_between(sink_work, sink_work + Vector2i.RIGHT)] = SimGrid.Segment.WALL
	var check: EditCheck = _editor().check_segments(changes)
	assert_false(check.ok)
	assert_eq(check.why, WallRules.CUT_SINK)
	assert_eq(check.menu_warning, "Fries will leave the menu: staff can't reach the fryer")
	var shop: Dictionary = _editor().to_dict()
	assert_false(_main.call("shop_walls", changes))
	assert_eq(_editor().to_dict(), shop)


func test_floor_removal_names_the_affected_dish_before_refusing_a_lost_work_spot() -> void:
	await _start()
	_add_fryer()
	var wing: Array[Vector2i] = [Vector2i(14, 1), Vector2i(14, 2), Vector2i(14, 3)]
	assert_true(_main.call("shop_floor", wing, true))
	assert_true(_main.call("shop_move", _item(&"fryer").id, Vector2i(12, 2), 1))
	var removal: Array[Vector2i] = wing.duplicate()
	var check: EditCheck = _editor().check_floor(removal, false)
	assert_false(check.ok)
	assert_eq(check.menu_warning, "Fries will leave the menu: staff can't reach the fryer")
	var shop: Dictionary = _editor().to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	assert_false(_main.call("shop_floor", removal, false))
	assert_eq(_editor().to_dict(), shop)
	assert_eq(Economy.ledger.to_dict(), books)


func test_legacy_empty_catalogue_explains_and_disables_open_until_access_is_repaired() -> void:
	await _start()
	var definition: ItemDef = (_main.get("content") as ContentDB).item(&"potted_plant")
	var blocker: PlacedItem = _grid().place_def(definition, _item(&"stove").work_cells[0])
	assert_not_null(blocker)
	_main.call("_refresh_menu_catalogue")
	var context: Button = _main.get_node("HUD/Top/Row/Context") as Button
	assert_true(context.disabled)
	assert_eq(context.tooltip_text, MenuAccess.NO_DISH)
	assert_eq((_main.get_node("HUD/MenuNotice/Text") as Label).text, MenuAccess.NO_DISH)
	(_main.get_node("HUD") as Node).call("_on_context_pressed")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_true(_grid().remove(blocker.id))
	_main.call("_refresh_menu_catalogue")
	assert_false(context.disabled)
	assert_false((_main.get_node("HUD/MenuNotice") as Control).visible)


func test_exact_undo_can_restore_an_accepted_layout_even_when_its_menu_was_already_blocked() -> void:
	await _start()
	var definition: ItemDef = (_main.get("content") as ContentDB).item(&"potted_plant")
	var old_spot: Vector2i = _item(&"stove").work_cells[0]
	var blocker: PlacedItem = _grid().place_def(definition, old_spot)
	assert_not_null(blocker)
	_main.call("_refresh_menu_catalogue")
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("shop_move", blocker.id, Vector2i(10, 3), 0))
	assert_false((_main.get_node("HUD/Top/Row/Context") as Button).disabled)
	assert_false(_editor().check_move(blocker.id, old_spot, 0).ok, "a fresh request cannot empty the menu")
	assert_true(_main.call("undo_edit"), "history restores an accepted layout under its existing exemption")
	assert_eq(_grid().item(blocker.id).origin, old_spot)
	assert_true((_main.get_node("HUD/Top/Row/Context") as Button).disabled)
	assert_true(_main.call("redo_edit"))
	assert_false((_main.get_node("HUD/Top/Row/Context") as Button).disabled)


func test_a_legacy_blocked_morning_save_loads_its_shop_with_opening_refused() -> void:
	await _start()
	var definition: ItemDef = (_main.get("content") as ContentDB).item(&"potted_plant")
	var blocked_spot: Vector2i = _item(&"stove").work_cells[0]
	assert_not_null(_grid().place_def(definition, blocked_spot))
	# Reproduce a morning saved before the empty-catalogue guard existed.
	assert_eq(SaveSystem.save_game(SLOT), OK)
	_main.get_parent().remove_child(_main)
	_main.free()
	_main = null
	await _start()
	assert_not_null(_grid().item_at(blocked_spot), "the old edited shop loads rather than starting fresh")
	assert_eq((_main.get_node("HUD/MenuNotice/Text") as Label).text, MenuAccess.NO_DISH)
	assert_true((_main.get_node("HUD/Top/Row/Context") as Button).disabled)


## Preserve a real old morning choice before
## load-time reachability filtering, with another meal still reachable.
func _save_partial_blocked_coffee(enabled: bool) -> Vector2i:
	await _start()
	assert_true(_settings().set_owner_level(2))
	_editor().set_owner_level(2)
	assert_true(_main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	for id: StringName in [&"tea", &"tomato_soup", &"grilled_cheese"]:
		assert_true(_main.call("menu_set_enabled", id, false))
	assert_true(_main.call("menu_set_enabled", &"coffee", enabled))
	assert_true(_main.call("menu_set_price", &"burger", 18))
	var cell: Vector2i = _item(&"coffee_machine").work_cells[0]
	assert_true(_editor().buy(&"potted_plant", cell, 0, ShopEditor.Exact.new()))
	assert_eq(_settings().is_enabled(&"coffee"), enabled)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem._slot_path(SLOT)))
	assert_eq((document["data"]["menu"]["enabled"] as Array).has("coffee"), enabled,
		"the actual morning autosave retains the pre-filter Coffee choice")
	return cell


func _reload_saved_morning() -> void:
	_main.get_parent().remove_child(_main)
	_main.free()
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)


func test_loading_enabled_unreachable_dish_keeps_the_same_mornings_opening_note() -> void:
	var cell: Vector2i = await _save_partial_blocked_coffee(true)
	_reload_saved_morning()
	assert_eq((_grid().item_at(cell).def as ItemDef).id, &"potted_plant", "the accepted blocked layout loaded")
	assert_true(_settings().is_enabled(&"burger"), "another unlocked meal remains reachable")
	assert_eq(_settings().price_of(_settings().recipe(&"burger")), 18)
	assert_false(_settings().is_enabled(&"coffee"))
	assert_null(_settings().recipe(&"coffee"))
	assert_true((_main.get("_menu_access_losses") as Dictionary).has(&"coffee"))
	_main.call("_begin_morning")
	assert_true((_main.get("_menu_access_losses") as Dictionary).has(&"coffee"),
		"repeated setup of the same morning retains the load-time loss")
	assert_true(Clock.sim.start_service())
	var note: String = "Coffee left today's menu: staff can't reach the coffee machine"
	assert_eq(_main.call("menu_open_note"), note)
	assert_eq((_main.get_node("HUD/MenuNotice/Text") as Label).text, note)
	assert_true((_main.get_node("HUD/MenuNotice") as Control).visible)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_true((_main.get("_menu_access_losses") as Dictionary).is_empty())
	assert_eq(_main.call("menu_open_note"), "", "the next morning does not repeat yesterday's loss")
	assert_false((_main.get_node("HUD/MenuNotice") as Control).visible)
	_reload_saved_morning()
	assert_true((_main.get("_menu_access_losses") as Dictionary).is_empty(),
		"the rewritten save no longer had Coffee enabled")


func test_loading_disabled_unreachable_dish_does_not_report_a_loss() -> void:
	await _save_partial_blocked_coffee(false)
	_reload_saved_morning()
	assert_true(_settings().is_enabled(&"burger"))
	assert_false(_settings().is_enabled(&"coffee"))
	assert_true((_main.get("_menu_access_losses") as Dictionary).is_empty())
	assert_true(Clock.sim.start_service())
	assert_eq(_main.call("menu_open_note"), "")
	assert_false((_main.get_node("HUD/MenuNotice") as Control).visible)


func test_repairing_a_loaded_station_clears_its_loss_and_undo_restores_it() -> void:
	var cell: Vector2i = await _save_partial_blocked_coffee(true)
	_reload_saved_morning()
	assert_true((_main.get("_menu_access_losses") as Dictionary).has(&"coffee"))
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("shop_move", _grid().item_at(cell).id, Vector2i(10, 9), 0))
	assert_true(_settings().is_enabled(&"coffee"))
	assert_true(_main.call("menu_set_enabled", &"tea", false))
	assert_true((_main.get("_menu_access_losses") as Dictionary).is_empty())
	assert_true(_main.call("undo_edit"))
	assert_false(_settings().is_enabled(&"coffee"))
	assert_true((_main.get("_menu_access_losses") as Dictionary).has(&"coffee"))
	assert_true(Clock.sim.start_service())
	assert_eq(_main.call("menu_open_note"), "Coffee left today's menu: staff can't reach the coffee machine")


func test_fresh_game_fallback_clears_a_partially_loaded_access_notice() -> void:
	await _save_partial_blocked_coffee(true)
	_reload_saved_morning()
	assert_true((_main.get("_menu_access_losses") as Dictionary).has(&"coffee"))
	_main.call("_new_game")
	assert_true((_main.get("_menu_access_losses") as Dictionary).is_empty())
	assert_eq(_main.get("_menu_access_day"), 0)
	assert_false((_main.get_node("HUD/MenuNotice") as Control).visible)
