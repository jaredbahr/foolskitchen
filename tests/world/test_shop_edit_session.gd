extends TestCase
## One staged shop provider; existing morning saves and failed-load behavior.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")
const SLOT: String = "shop_edit"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "shop_edit_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_morning_items_and_books_round_trip_through_the_shop_provider() -> void:
	var first: Node = _start()
	var original_file: String = FileAccess.get_file_as_string(_path())
	var price: int = (first.get("content") as ContentDB).item(&"chair").price
	var before_cash: int = Economy.cash
	assert_true(first.call("shop_buy", &"chair", Vector2i(2, 8)))
	assert_eq(Economy.cash, before_cash - price)
	assert_true(first.call("shop_move", _id(first, &"potted_plant"), Vector2i(11, 9), 1))
	assert_eq(FileAccess.get_file_as_string(_path()), original_file, "edits do not introduce another autosave boundary")
	assert_eq(SaveSystem.save_game(SLOT), OK)  # An explicit MORNING save.
	assert_false(_document()["data"].has("shop_session"))
	var snapshot: Dictionary = (first.get("shop_editor") as ShopEditor).to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	_close(first)
	Economy.reset(98765)
	GameState.new_run(42)
	var second: Node = _start()
	assert_eq((second.get("shop_editor") as ShopEditor).to_dict(), snapshot)
	assert_eq(Economy.ledger.to_dict(), books, "a full saved fridge needs no new purchase")
	assert_eq(Economy.stock.to_dict(), stock)
	_assert_bindings(second)
	var world: SimWorld = second.get("world")
	var extra: StaffAgent = StaffAgent.new(&"server")
	world.add_agent(extra)
	assert_true(second.call("select_agent", extra.id), "inspector binds the restored world")


func test_old_morning_save_without_shop_uses_original_layout() -> void:
	var first: Node = _start()
	assert_true(first.call("shop_move", _id(first, &"potted_plant"), Vector2i(11, 9), 2))
	assert_eq(SaveSystem.save_game(SLOT), OK)
	var document: Dictionary = _document()
	document["data"].erase("shop")
	_write_document(document)
	_remove_backup()
	var cash: int = Economy.cash
	_close(first)
	var second: Node = _start()
	var plant: PlacedItem = (second.get("world") as SimWorld).grid.item(_id(second, &"potted_plant"))
	assert_eq(plant.origin, Vector2i(12, 9))
	assert_eq(plant.quarter_turns, 0)
	assert_eq(Economy.cash, cash)
	assert_true(_document()["data"].has("shop"), "normal morning autosave upgrades the old save")
	_assert_bindings(second)


func test_invalid_shop_starts_fresh_skips_one_save_then_autosaves_next_morning() -> void:
	var first: Node = _start()
	var document: Dictionary = _document()
	document["data"]["clock"]["day"] = 9
	document["data"]["shop"]["items"][0]["def_id"] = "missing_item"
	_write_document(document)
	_remove_backup()
	var broken: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.day, 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq((second.get("world") as SimWorld).grid.item(_id(second, &"potted_plant")).origin, Vector2i(12, 9))
	assert_eq(Economy.cash, TUNING.starting_cash - _stock_cost(second))
	assert_eq(FileAccess.get_file_as_string(_path()), broken, "only the first autosave is skipped")
	assert_true(second.call("shop_buy", &"chair", Vector2i(2, 8)))
	assert_eq(FileAccess.get_file_as_string(_path()), broken, "editing does not write a save")
	_assert_bindings(second)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(int(_document()["data"]["clock"]["day"]), 2)
	assert_eq((_document()["data"]["shop"]["items"] as Array).size(), LAYOUT.placements.size() + 1,
		"later normal autosaves resume")


func test_non_morning_save_is_rejected_without_rebuilding_its_items() -> void:
	var first: Node = _start()
	assert_true(first.call("shop_move", _id(first, &"potted_plant"), Vector2i(11, 9), 2))
	assert_eq(SaveSystem.save_game(SLOT), OK)
	var document: Dictionary = _document()
	document["data"]["clock"]["phase"] = SimClock.Phase.CLOSED
	_write_document(document)
	_remove_backup()
	var broken: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq((second.get("world") as SimWorld).grid.item(_id(second, &"potted_plant")).origin, Vector2i(12, 9))
	assert_eq(FileAccess.get_file_as_string(_path()), broken)


func test_restore_callback_only_stages_a_decoded_layout() -> void:
	var main: Node = _start(false)
	var editor: ShopEditor = main.get("shop_editor")
	var before: Dictionary = editor.to_dict()
	var saved: Dictionary = before.duplicate(true)
	var plant: Dictionary = _saved_item(saved, "potted_plant")
	plant["origin"] = [11, 9]
	var world: SimWorld = main.get("world")
	assert_true(main.call("_restore_shop", saved))
	assert_true(main.get("world") == world)
	assert_eq(editor.to_dict(), before, "provider decoding does not replace or edit the live grid")


func test_saved_furniture_on_staff_spawn_loads_and_staff_can_escape() -> void:
	var first: Node = _start()
	var spawn: Vector2i = LAYOUT.staff_spawns[&"server"]
	var morning_file: String = FileAccess.get_file_as_string(_path())
	var before_books: Dictionary = Economy.ledger.to_dict()
	assert_false(first.call("shop_buy", &"potted_plant", spawn), "level one cannot buy a new plant")
	assert_eq((first.get("shop_editor") as ShopEditor).last_check.why, "Unlocks at level 2")
	assert_eq(Economy.ledger.to_dict(), before_books)
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file)
	assert_false(first.call("menu_set_enabled", &"tomato_melt", true),
		"the new recipe is locked before level two")
	# Drive the production closing path with known happy guests to unlock it;
	# keep the first morning snapshot intact until the next normal autosave.
	var progress: OwnerProgress = first.get("owner_progress") as OwnerProgress
	var happy_needed: int = ceili(float(progress.threshold_for(2)) / float(PROGRESSION.happy_guest_xp))
	(first.get("sim") as RestaurantSim).leave_reasons_today[&"happy"] = happy_needed
	Clock.sim.phase = SimClock.Phase.CLOSED
	first.call("_on_service_closed", Clock.sim.day)
	assert_eq(progress.level, 2)
	var report: DayReport = first.get("shown_report") as DayReport
	assert_eq(report.owner_level_before, 1)
	assert_eq(report.owner_level_after, 2)
	assert_eq(report.owner_unlocks, ["Four-seat table", "Glass of wine recipe", "Potted plant",
		"Rectangular rug", "Round table", "Rounded chair", "Side table", "Square rug", "Standing coat rack",
		"Tomato melt recipe", "Two-seat bench"] as Array[String],
		"the level-up banner lists every available level-two unlock")
	var panel: Control = first.get_node("Overlay/EveningReport") as Control
	var banner: Label = panel.get_node("Panel/Scroll/Content/LevelUpCallout/OwnerLevelUp") as Label
	var unlocks: Label = panel.get_node("Panel/Scroll/Content/LevelUpCallout/OwnerUnlocks") as Label
	assert_true(banner.visible)
	assert_eq(banner.text, "Level up! Level 2 reached")
	assert_eq(unlocks.text, "Unlocked: Four-seat table, Glass of wine recipe, Potted plant, Rectangular rug, Round table, Rounded chair, Side table, Square rug, Standing coat rack, Tomato melt recipe, Two-seat bench")
	var xp_rows: GridContainer = panel.get_node("Panel/Scroll/Content/OwnerXPRows") as GridContainer
	assert_eq(xp_rows.get_child_count(), 8, "the native report shows four labelled XP sources")
	assert_eq((xp_rows.get_child(7) as Label).text, "+%d XP" % report.owner_xp_breakdown["total_xp"])
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file)
	assert_true(first.call("shop_buy", &"potted_plant", spawn))
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file, "unlock and purchase do not save immediately")
	assert_true(Clock.sim.next_day())
	assert_true(first.call("menu_set_enabled", &"tomato_melt", true),
		"the unlocked dish can be planned next morning")
	var saved_progress: Dictionary = progress.to_dict()
	var raw_progress: Dictionary = _document()["data"]["owner"]["progress"]
	assert_eq(raw_progress.size(), saved_progress.size())
	for key: String in saved_progress:
		assert_true(raw_progress.has(key))
	var decoded: OwnerProgress = OwnerProgress.new(progress.tuning)
	assert_true(decoded.from_dict(raw_progress), "the morning JSON stores valid owner progress")
	assert_eq(decoded.to_dict(), saved_progress)
	_close(first)
	var second: Node = _start()
	assert_eq((second.get("owner_progress") as OwnerProgress).to_dict(), saved_progress,
		"level-two XP and its awarded-day guard survive the morning reload")
	var world: SimWorld = second.get("world")
	assert_false(world.grid.is_walkable(spawn))
	var server: SimAgent = world.agents[1]
	assert_eq(server.cell, spawn)
	assert_true(server.set_destination(world.grid, world.grid.entries()[0]))
	assert_eq(server.path[0], spawn)
	for _index: int in range(200):
		if server.has_arrived():
			break
		assert_ne(server.step_move(world), SimAgent.MoveResult.BLOCKED)
	assert_true(server.has_arrived())


func test_level_three_announcements_skip_hidden_tall_plant_and_keep_visible_unlocks() -> void:
	var main: Node = _start()
	var content: ContentDB = main.get("content") as ContentDB
	var hidden: ItemDef = content.item(&"plant_small_3")
	var visible: ItemDef = content.item(&"cushioned_bench")
	assert_eq(hidden.unlock_level, 3)
	assert_false(hidden.catalogue_visible)
	assert_eq(visible.unlock_level, 3)
	assert_true(visible.catalogue_visible)
	var saved: String = FileAccess.get_file_as_string(_path())
	var books: Dictionary = Economy._capture_save()
	var rng: Dictionary = GameState._capture_save()
	var unlocked: Array[String] = main.call("_unlocked_at_levels", 2, 3)
	assert_false(unlocked.has(hidden.display_name))
	assert_true(unlocked.has(visible.display_name))
	assert_eq(FileAccess.get_file_as_string(_path()), saved)
	assert_eq(Economy._capture_save(), books)
	assert_eq(GameState._capture_save(), rng)


func test_loaded_morning_keeps_the_existing_restock_and_autosave_policy() -> void:
	var first: Node = _start()
	var used: Dictionary[StringName, int] = {&"bun": 1}
	assert_true(Economy.stock.take_many(used))
	assert_eq(SaveSystem.save_game(SLOT), OK)
	var cash: int = Economy.cash
	var unit_cost: int = (first.get("content") as ContentDB).ingredient(&"bun").unit_cost
	_close(first)
	var second: Node = _start()
	assert_eq(Economy.stock.count(&"bun"), TUNING.morning_stock[&"bun"])
	assert_eq(Economy.cash, cash - ReorderSettings.auto_cost(unit_cost, TUNING.auto_reorder_premium),
		"loaded morning tops up missing stock as before, as one auto-order with its premium")
	var expected_loan: Dictionary = {"version": 1, "principal": "0",
		"last_settled_day": "0", "has_borrowed": false}
	assert_eq(Economy.loan.to_dict(), expected_loan, "a debt-free morning does not create or settle a loan")
	var expected: Dictionary = {"ledger": Economy.ledger.to_dict(),
		"stock": Economy.stock.to_dict(), "loan": expected_loan}
	assert_eq(_document()["data"]["economy"], JSON.parse_string(JSON.stringify(expected)),
		"the whole topped-up Economy section is autosaved in its JSON representation")
	_assert_bindings(second)


func test_closed_edits_wait_for_next_morning_autosave() -> void:
	var first: Node = _start()
	var morning_file: String = FileAccess.get_file_as_string(_path())
	_run_day(first)
	var before_cash: int = Economy.cash
	var refund: int = (first.get("content") as ContentDB).item(&"potted_plant").price >> 1
	assert_eq(first.call("shop_sell", _id(first, &"potted_plant")), refund)
	assert_eq(Economy.cash, before_cash + refund)
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file)
	var closed_totals: Dictionary = Economy.ledger.day_totals(1)
	(first.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	assert_eq(int(_document()["data"]["clock"]["phase"]), int(SimClock.Phase.MORNING))
	var snapshot: Dictionary = (first.get("shop_editor") as ShopEditor).to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	_close(first)
	var second: Node = _start()
	assert_eq((second.get("shop_editor") as ShopEditor).to_dict(), snapshot)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.ledger.day_totals(1), closed_totals, "loading does not repeat closing costs")


func _start(with_saves: bool = true) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("save_slot", SLOT)
	main.set("use_saves", with_saves)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _id(main: Node, def_id: StringName) -> int:
	return ShopBuilder.items_with_def(main.get("world"), def_id)[0].id


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_backup() -> void:
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")


func _saved_item(shop: Dictionary, def_id: String) -> Dictionary:
	for item: Dictionary in shop["items"]:
		if item["def_id"] == def_id:
			return item
	return {}


func _stock_cost(main: Node) -> int:
	var content: ContentDB = main.get("content")
	var total: int = 0
	for id: StringName in TUNING.morning_stock:
		total += TUNING.morning_stock[id] * content.ingredient(id).unit_cost
	# The morning auto-order pays its premium once on the order total (#54).
	return ReorderSettings.auto_cost(total, TUNING.auto_reorder_premium)


func _assert_bindings(main: Node) -> void:
	var sim: RestaurantSim = main.get("sim")
	assert_true(Clock.attached_world == sim.world)
	assert_true(sim.world.clock == Clock.sim)
	assert_true(sim.stock == Economy.stock)
	assert_true(sim.kitchen.stock == Economy.stock)
	assert_true(sim.rng == GameState.rng(&"customers"))
	assert_true(sim.spawner.rng == sim.rng)


func _run_day(main: Node) -> void:
	assert_true(Clock.sim.start_service())
	for _guard: int in range(30):
		if Clock.sim.phase == SimClock.Phase.CLOSED:
			break
		main.call("run_ticks", 1000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
