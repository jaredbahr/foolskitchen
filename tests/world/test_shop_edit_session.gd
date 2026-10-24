extends TestCase
## Startup-only shop checkpoints, failed-save protection and edit-save boundaries.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SAVE_DIR: String = "user://test_shop_edit_sessions/"
const SLOT: String = "shop_edit"

var _mains: Array[Node] = []
var _old_save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	SaveSystem.save_dir = SAVE_DIR
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SAVE_DIR)
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_morning_edits_save_once_and_reload_items_books_and_reduced_stock() -> void:
	var first: Node = _start()
	var used: Dictionary[StringName, int] = {&"bun": 1}
	assert_true(Economy.stock.take_many(used))
	var price: int = (first.get("content") as ContentDB).item(&"chair").price
	var before_cash: int = Economy.cash
	assert_true(first.call("shop_buy", &"chair", Vector2i(4, 9)))
	assert_eq(Economy.cash, before_cash - price)
	var backup: Dictionary = _document(true)
	assert_eq((backup["data"]["shop"]["items"] as Array).size(), 8, "one save after the purchase, not two")
	assert_true(first.call("shop_move", _id(first, &"potted_plant"), Vector2i(11, 9), 1))
	backup = _document(true)
	var old_plant: Dictionary = _saved_item(backup["data"]["shop"], "potted_plant")
	assert_eq(old_plant["origin"], [12.0, 9.0], "the move produces one new checkpoint")
	var snapshot: Dictionary = (first.get("shop_editor") as ShopEditor).to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	_close(first)
	Economy.reset(98765)
	GameState.new_run(42)
	var second: Node = _start()
	assert_eq((second.get("shop_editor") as ShopEditor).to_dict(), snapshot)
	assert_eq(Economy.ledger.to_dict(), books, "loading does not replay purchases or restock")
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(Economy.stock.count(&"bun"), TUNING.morning_stock[&"bun"] - 1)
	_assert_bindings(second)
	var world: SimWorld = second.get("world")
	var extra: StaffAgent = StaffAgent.new(&"server")
	world.add_agent(extra)
	assert_true(second.call("select_agent", extra.id), "inspector binds the installed world, not the initial placeholder")


func test_old_morning_save_without_shop_uses_original_layout() -> void:
	var first: Node = _start()
	assert_true(first.call("shop_move", _id(first, &"potted_plant"), Vector2i(11, 9), 2))
	var document: Dictionary = _document()
	document["data"].erase("shop")
	document["data"].erase("shop_session")
	_write_document(document)
	_remove_backup()
	var original_file: String = FileAccess.get_file_as_string(_path())
	var cash: int = Economy.cash
	_close(first)
	var second: Node = _start()
	var plant: PlacedItem = (second.get("world") as SimWorld).grid.item(_id(second, &"potted_plant"))
	assert_eq(plant.origin, Vector2i(12, 9))
	assert_eq(plant.quarter_turns, 0)
	assert_eq(Economy.cash, cash)
	assert_eq(FileAccess.get_file_as_string(_path()), original_file, "startup resume does not rewrite the legacy checkpoint")
	assert_false(second.get("shop_save_blocked"))


func test_invalid_shop_starts_clean_and_protects_slot_from_later_edit_saves() -> void:
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
	assert_true(second.get("shop_save_blocked"))
	assert_eq((second.get("world") as SimWorld).grid.item(_id(second, &"potted_plant")).origin, Vector2i(12, 9))
	assert_eq(Economy.cash, TUNING.starting_cash - _stock_cost(second))
	_assert_bindings(second)
	assert_true(second.call("shop_buy", &"chair", Vector2i(4, 9)), "an edit stays usable even when its slot is protected")
	assert_eq(second.get("last_shop_save_error"), ERR_UNAVAILABLE)
	assert_eq(second.call("save_shop_changes"), ERR_UNAVAILABLE)
	assert_eq(FileAccess.get_file_as_string(_path()), broken)
	# The protection survives a later automatic morning save boundary as well.
	Clock.sim.phase = SimClock.Phase.CLOSED
	Clock.sim.next_day()
	assert_true(second.get("shop_save_blocked"))
	assert_eq(FileAccess.get_file_as_string(_path()), broken)


func test_old_closed_save_without_new_checkpoint_remains_unsupported() -> void:
	var first: Node = _start()
	var document: Dictionary = _document()
	document["data"]["clock"]["phase"] = SimClock.Phase.CLOSED
	document["data"].erase("shop_session")
	_write_document(document)
	_remove_backup()
	var broken: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start()
	assert_true(second.get("shop_save_blocked"))
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(FileAccess.get_file_as_string(_path()), broken)


func test_provider_failure_resets_partial_core_state_and_protects_the_slot() -> void:
	var first: Node = _start()
	var document: Dictionary = _document()
	document["data"]["clock"]["day"] = 7
	document["data"]["shop_session"]["day"] = 7
	document["data"]["game_state"]["master_seed"] = "123456"
	document["data"]["economy"] = {"ledger": false, "stock": {}}
	_write_document(document)
	_remove_backup()
	var broken: String = FileAccess.get_file_as_string(_path())
	_close(first)
	var second: Node = _start()
	assert_true(second.get("shop_save_blocked"))
	assert_eq(Clock.sim.day, 1)
	assert_ne(GameState.master_seed, 123456)
	assert_eq(Economy.cash, TUNING.starting_cash - _stock_cost(second))
	assert_eq(FileAccess.get_file_as_string(_path()), broken)
	_assert_bindings(second)


func test_invalid_shop_primary_recovers_backup_and_later_edit_keeps_that_backup() -> void:
	var first: Node = _start()
	assert_true(first.call("shop_move", _id(first, &"potted_plant"), Vector2i(11, 9), 1))
	var good_backup: String = FileAccess.get_file_as_string(_path() + ".bak")
	var document: Dictionary = _document()
	document["data"]["shop"]["items"][0]["def_id"] = "missing_item"
	_write_document(document)
	_close(first)
	var second: Node = _start()
	assert_false(second.get("shop_save_blocked"))
	assert_eq((second.get("world") as SimWorld).grid.item(_id(second, &"potted_plant")).origin, Vector2i(12, 9))
	assert_true(second.call("shop_move", _id(second, &"potted_plant"), Vector2i(10, 9), 2))
	assert_eq(second.get("last_shop_save_error"), OK)
	assert_eq(FileAccess.get_file_as_string(_path() + ".bak"), good_backup)


func test_saved_furniture_on_staff_spawn_loads_and_staff_can_escape() -> void:
	var first: Node = _start()
	var spawn: Vector2i = LAYOUT.staff_spawns[&"server"]
	assert_true(first.call("shop_buy", &"potted_plant", spawn))
	_close(first)
	var second: Node = _start()
	assert_false(second.get("shop_save_blocked"))
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


func test_closed_edit_restores_report_and_costs_without_replaying_closing() -> void:
	var first: Node = _start()
	_run_day(first)
	var served: int = (first.get("sim") as RestaurantSim).served_today
	assert_true(served > 0, "the real kitchen served meals")
	assert_eq(first.call("shop_sell", _id(first, &"potted_plant")), 7)
	assert_eq(first.get("last_shop_save_error"), OK)
	var books: Dictionary = Economy.ledger.to_dict()
	var cash: int = Economy.cash
	var rng_state: int = GameState.rng(&"customers").state
	var report: DayReport = first.get("shown_report")
	var sold: Dictionary = report.dishes_sold.duplicate()
	var reasons: Dictionary = report.leave_reasons.duplicate()
	var lost: int = report.customers_lost
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_eq(Economy.cash, cash)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(GameState.rng(&"customers").state, rng_state, "closed resume does not draw a new morning gap")
	var restored: DayReport = second.get("shown_report")
	assert_not_null(restored)
	assert_eq(restored.customers_served, served)
	assert_eq(restored.customers_lost, lost)
	assert_eq(restored.dishes_sold, sold)
	assert_eq(restored.leave_reasons, reasons)
	assert_true((second.get_node("Overlay/EveningReport") as Control).visible)
	var sim: RestaurantSim = second.get("sim")
	assert_eq(sim.customers().size(), 0)
	assert_eq(sim.world.board.active_count(), 0)
	assert_true(sim.kitchen.dirty_tables.is_empty())
	for staff: SimAgent in sim.world.agents:
		assert_null((staff as StaffAgent).task)
	_assert_bindings(second)
	var closed_totals: Dictionary = Economy.ledger.day_totals(Clock.sim.day)
	assert_eq(closed_totals[Ledger.WAGES], -55)
	assert_eq(closed_totals[Ledger.RENT], -40)
	(second.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	assert_eq(Economy.ledger.day_totals(1), closed_totals, "the next morning does not charge the old closing again")
	assert_false((second.get_node("Overlay/EveningReport") as Control).visible)


func test_save_failure_keeps_edit_committed_and_retry_only_saves() -> void:
	var main: Node = _start()
	main.set("save_slot", "invalid/slot")
	var before: int = Economy.cash
	assert_true(main.call("shop_buy", &"chair", Vector2i(4, 9)))
	assert_eq(main.get("last_shop_save_error"), ERR_INVALID_PARAMETER)
	assert_eq(Economy.cash, before - 10)
	var books: Dictionary = Economy.ledger.to_dict()
	var shop: Dictionary = (main.get("shop_editor") as ShopEditor).to_dict()
	main.set("save_slot", SLOT)
	assert_eq(main.call("save_shop_changes"), OK)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq((main.get("shop_editor") as ShopEditor).to_dict(), shop)
	assert_eq((_document()["data"]["shop"]["items"] as Array).size(), 9)


func test_mixed_purchase_refund_keeps_gross_report_flows_after_closed_reload() -> void:
	var first: Node = _start()
	_run_day(first)
	var day: int = Clock.sim.day
	var old_cash: int = Economy.cash
	var old_income: int = Economy.ledger.day_income(day)
	var old_costs: int = Economy.ledger.day_costs(day)
	assert_true(first.call("shop_buy", &"chair", Vector2i(4, 9)))
	var chair: PlacedItem = (first.get("world") as SimWorld).grid.item_at(Vector2i(4, 9))
	assert_eq(first.call("shop_sell", chair.id), 5)
	assert_eq(first.get("last_shop_save_error"), OK)
	assert_eq(Economy.cash, old_cash - 5)
	assert_eq(Economy.ledger.day_totals(day)[Ledger.UPGRADES], -5, "signed category totals keep their existing meaning")
	var report: DayReport = first.get("shown_report")
	assert_eq(report.income.get(Ledger.UPGRADES, 0), 5)
	assert_eq(report.costs.get(Ledger.UPGRADES, 0), 10)
	assert_eq(report.total_income(), old_income + 5)
	assert_eq(report.total_costs(), old_costs + 10)
	_assert_report_flows(first)
	var income: Dictionary = report.income.duplicate()
	var costs: Dictionary = report.costs.duplicate()
	var books: Dictionary = Economy.ledger.to_dict()
	var cash: int = Economy.cash
	_close(first)
	var second: Node = _start()
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_eq(Economy.cash, cash)
	assert_eq(Economy.ledger.to_dict(), books, "reloading does not replay either flow")
	var restored: DayReport = second.get("shown_report")
	assert_eq(restored.income, income)
	assert_eq(restored.costs, costs)
	assert_eq(restored.income.get(Ledger.UPGRADES, 0), 5)
	assert_eq(restored.costs.get(Ledger.UPGRADES, 0), 10)
	_assert_report_flows(second)


func test_checkpoint_validation_is_read_only_and_rejects_inconsistent_totals() -> void:
	var main: Node = _start()
	var before: Dictionary = (main.get("shop_editor") as ShopEditor).to_dict()
	var sections: Dictionary = _document()["data"]
	sections["clock"]["phase"] = SimClock.Phase.CLOSED
	sections["shop_session"]["phase"] = SimClock.Phase.CLOSED
	sections["shop_session"]["served"] = 1
	sections["shop_session"]["reasons"] = {"happy": 1}
	assert_false(main.call("_validate_shop_sections", sections), "one served guest needs one sold dish")
	sections["shop_session"]["dishes"] = {"burger": 1}
	sections["shop_session"]["day"] = 9
	assert_false(main.call("_validate_shop_sections", sections), "checkpoint day must match the clock")
	sections["shop_session"]["day"] = 1
	sections["shop_session"]["served"] = 1.5
	assert_false(main.call("_validate_shop_sections", sections), "fractional counters are refused")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq((main.get("shop_editor") as ShopEditor).to_dict(), before)


func test_old_main_cleanup_cannot_unregister_a_newer_shop_provider() -> void:
	var first: Node = _start(false)
	var second: Node = _start(false)
	assert_true(second.call("shop_move", _id(second, &"potted_plant"), Vector2i(11, 9), 3))
	_close(first)
	assert_eq(SaveSystem.save_game(SLOT), OK)
	var plant: Dictionary = _saved_item(_document()["data"]["shop"], "potted_plant")
	assert_eq(plant["origin"], [11.0, 9.0])
	assert_eq(plant["quarter_turns"], 3.0)


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
	return SAVE_DIR.path_join(SLOT + ".json")


func _document(backup: bool = false) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path() + (".bak" if backup else "")))


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
	return total


func _assert_bindings(main: Node) -> void:
	var sim: RestaurantSim = main.get("sim")
	assert_true(Clock.attached_world == sim.world)
	assert_true(sim.world.clock == Clock.sim)
	assert_true(sim.stock == Economy.stock)
	assert_true(sim.kitchen.stock == Economy.stock)
	assert_true(sim.rng == GameState.rng(&"customers"))
	assert_true(sim.spawner.rng == sim.rng)


func _assert_report_flows(main: Node) -> void:
	var report: DayReport = main.get("shown_report")
	assert_eq(report.total_income(), Economy.ledger.day_income(Clock.sim.day))
	assert_eq(report.total_costs(), Economy.ledger.day_costs(Clock.sim.day))
	assert_eq(report.profit(), Economy.ledger.day_profit(Clock.sim.day))
	var lifetime_changes: int = 0
	for day: int in range(1, Clock.sim.day + 1):
		lifetime_changes += Economy.ledger.day_profit(day)
	assert_eq(Economy.cash, TUNING.starting_cash + lifetime_changes)


func _run_day(main: Node) -> void:
	assert_true(Clock.sim.start_service())
	for _guard: int in range(30):
		if Clock.sim.phase == SimClock.Phase.CLOSED:
			break
		main.call("run_ticks", 1000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
