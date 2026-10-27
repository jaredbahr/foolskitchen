extends TestCase
## FK-087 in the real game session: storage limits on hand orders and the
## auto-reorder, deliveries on the schedule, refunds, Build refusing to sell
## storage the stock needs, the morning save of pending orders, legacy saves
## and the shelves showing their stock.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SLOT: String = "delivery_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "delivery_session")
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


func test_a_new_game_fills_the_starter_storage_and_nothing_waits() -> void:
	var main: Node = _start(false)
	var space: StorageSpace = main.call("storage_space")
	assert_eq(space.in_stock(StorageSpace.FRIDGE), 28)
	assert_eq(space.capacity(StorageSpace.FRIDGE), 40)
	assert_eq(space.in_stock(StorageSpace.DRY), 50)
	assert_eq(space.capacity(StorageSpace.DRY), 60)
	assert_true((main.get("deliveries") as DeliveryBook).is_empty(), "the morning delivery came at once")
	var groups: Array[Dictionary] = main.call("stock_groups")
	assert_eq(groups.size(), 2, "Fridge and Dry; no freezer in the starter shop")
	assert_eq(groups[0]["label"], "Fridge")
	assert_eq(groups[1]["label"], "Dry")
	var rows: Array[Dictionary] = main.call("stock_rows")
	assert_eq(rows[0]["id"], &"beef_patty", "fridge first, in the fixed order")
	var beer: Dictionary = rows.filter(func(row: Dictionary) -> bool: return row["id"] == &"beer")[0]
	assert_false(beer["in_use"], "beer is listed greyed out: nothing on the menu uses it")
	assert_false((main.call("stock_notes") as Array[String]).any(func(note: String) -> bool: return note.contains("space")))


func test_a_hand_order_that_does_not_fit_is_refused() -> void:
	var main: Node = _start(false)
	assert_true(main.call("stock_cart_set", &"cheese", 12), "28 + 12 fills the 40-unit fridge")
	assert_false(main.call("stock_cart_set", &"lettuce", 1), "one more does not fit")
	assert_eq(main.call("stock_cart_refusal"), "")
	assert_true(main.call("stock_place_order"))
	assert_false(main.call("stock_cart_set", &"beef_patty", 1), "what is on order takes its space")
	Economy.stock.add(&"lettuce", 1, Clock.sim.day)
	var cart: Dictionary[StringName, int] = main.get("stock_cart")
	cart[&"beef_patty"] = 1
	assert_eq(main.call("stock_cart_refusal"), "Not enough fridge space")
	var cash: int = Economy.cash
	assert_false(main.call("stock_place_order"))
	assert_eq(Economy.cash, cash, "a refused order costs nothing")
	main.call("stock_clear_cart")
	assert_true(main.call("stock_cart_set", &"bread", 10), "the dry shelves have their own space")
	assert_false(main.call("stock_cart_set", &"bread", 11))
	main.call("stock_clear_cart")
	Economy.cash = 3
	assert_true(main.call("stock_cart_set", &"tomato", 4))
	assert_eq(main.call("stock_cart_refusal"), "Not enough cash")
	assert_true(main.call("set_stock_visible", true))
	var panel: StockPanel = main.get_node("Overlay/StockPanel") as StockPanel
	assert_true((panel.get_node("%Order") as Button).disabled)
	assert_eq((panel.get_node("%Order") as Button).tooltip_text, "Not enough cash")
	assert_true((panel.row_for(&"lettuce")["cart+1"] as Button).disabled)
	assert_eq((panel.row_for(&"lettuce")["cart+1"] as Button).tooltip_text, "Not enough fridge space")


func test_the_auto_reorder_buys_up_to_the_free_space_and_says_what_did_not_fit() -> void:
	var main: Node = _start(false)
	main.set("auto_reorder_premium", 0.0)
	# Cheese keeps five days; 20 extra leave room for only 12 fridge units tomorrow.
	Economy.stock.add(&"cheese", 20, Clock.sim.day)
	assert_true(Economy.stock.take(&"beef_patty", 10) and Economy.stock.take(&"lettuce", 10))
	var report: DayReport = main.call("build_report", Clock.sim.day)
	assert_true(report.low_stock.has("Lettuce: 0 left, target 10. Not enough fridge space to reorder 8."), str(report.low_stock))
	_next_morning()
	assert_eq(Economy.stock.count(&"beef_patty"), 10, "patties come first in the fixed order")
	assert_eq(Economy.stock.count(&"lettuce"), 2, "lettuce gets the last two units")
	var space: StorageSpace = main.call("storage_space")
	assert_eq(space.in_stock(StorageSpace.FRIDGE), 40)
	var notes: Array[String] = main.call("stock_notes")
	assert_true(notes.has("Not enough fridge space for 8 Lettuce this morning."), str(notes))
	assert_true(main.call("is_stock_visible"), "the Stock panel opens to say so")
	assert_eq(Economy.stock.count(&"bread"), 16, "dry goods are bought as usual")


func test_deliveries_arrive_on_the_schedule_and_bring_sold_out_dishes_back() -> void:
	var main: Node = _start(false)
	var sim: RestaurantSim = main.get("sim")
	assert_true(main.call("stock_set_auto", &"soup_stock", false))
	assert_true(Economy.stock.take(&"soup_stock", 8))
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 5)
	assert_true(sim.is_sold_out(&"tomato_soup"))
	assert_true(main.call("stock_cart_set", &"soup_stock", 6))
	var cash: int = Economy.cash
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.cash, cash - 6, "paid when placed")
	var countdown: Dictionary = main.call("delivery_countdown")
	assert_eq(countdown["text"], "Next delivery at 14:00")
	main.call("run_ticks", 1080 - Clock.sim.phase_tick - 1)
	assert_eq(Economy.stock.count(&"soup_stock"), 0, "nothing before 14:00")
	main.call("run_ticks", 1)
	assert_eq(Clock.sim.phase_tick, 1080)
	assert_eq(Economy.stock.count(&"soup_stock"), 6, "the 14:00 delivery")
	assert_false(sim.is_sold_out(&"tomato_soup"), "the soup is back on")
	assert_true((main.get("deliveries") as DeliveryBook).is_empty())
	# After the last delivery (20:00) an order waits for the morning.
	main.call("run_ticks", 3240 - Clock.sim.phase_tick + 10)
	assert_true(main.call("stock_cart_set", &"bread", 2))
	assert_true(main.call("stock_place_order"))
	assert_eq((main.call("delivery_countdown") as Dictionary)["text"], "Next delivery: tomorrow morning")
	assert_true((main.call("stock_pending_text") as String).ends_with("It arrives tomorrow morning."))
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 30:
		main.call("run_ticks", 1000)
		guard += 1
	var bread_before: int = Economy.stock.count(&"bread")
	assert_false((main.get("deliveries") as DeliveryBook).is_empty(), "still on its way at closing")
	assert_true(Clock.sim.next_day())
	assert_true((main.get("deliveries") as DeliveryBook).is_empty(), "the morning delivery brought it")
	assert_true(Economy.stock.count(&"bread") >= mini(bread_before + 2, 16), "and the auto-order counted it")


func test_cancelling_before_delivery_refunds_in_full() -> void:
	var main: Node = _start(false)
	var cash: int = Economy.cash
	assert_true(main.call("stock_cart_set", &"tomato", 5))
	assert_true(main.call("stock_cart_set", &"beef_patty", 2))
	assert_eq(main.call("stock_cart_total"), 9)
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.cash, cash - 9)
	assert_eq(main.call("stock_cancel_orders"), 9)
	assert_eq(Economy.cash, cash, "a full refund")
	var last: Dictionary = Economy.ledger.entries_for_day(Clock.sim.day).back()
	assert_eq(last["note"], Economy.ORDER_REFUND_NOTE)
	assert_eq(last["category"], Ledger.INGREDIENTS)
	assert_eq(main.call("stock_cancel_orders"), -1, "nothing left to cancel")
	assert_true(Clock.sim.start_service())
	assert_eq(Economy.stock.count(&"tomato"), 16, "a cancelled order never arrives")


func test_build_refuses_to_sell_storage_the_stock_needs_and_undo_obeys() -> void:
	var main: Node = _start(false)
	Economy.add_cash(500, Ledger.SALE)
	assert_true(main.call("set_build_active", true))
	assert_true(main.call("shop_buy", &"storage_shelf", Vector2i(12, 1), 2))
	assert_true(main.call("stock_cart_set", &"bread", 30))
	assert_true(main.call("stock_place_order"), "80 dry units on hand and on order fit 100")
	assert_false(main.call("undo_edit"), "taking the shelf away would leave 80 in 60")
	assert_eq(main.get("_edit_notice"), "Can't undo: Move stock out first: the dry stock would not fit without it")
	var shelf: PlacedItem = (main.get("world") as SimWorld).grid.item_at(Vector2i(12, 1))
	assert_eq(main.call("shop_sell", shelf.id), -1)
	assert_eq((main.get("shop_editor") as ShopEditor).last_check.why,
		"Move stock out first: the dry stock would not fit without it")
	assert_true(main.call("stock_cancel_orders") > 0)
	assert_true(main.call("undo_edit"), "with the order cancelled the shelf can go")


## Rule 9: pending orders are written only by the morning autosave. With no
## morning delivery in the schedule, the standing order waits in that save.
func test_pending_orders_ride_the_morning_save() -> void:
	var tuning: EconomyTuning = TUNING.duplicate() as EconomyTuning
	tuning.morning_delivery = false
	var first: Node = _start(true, tuning)
	var book: DeliveryBook = first.get("deliveries")
	assert_eq(book.size(), 1, "the standing order waits for the opening delivery")
	assert_eq(Economy.stock.count(&"bread"), 0)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	assert_eq((saved["data"]["deliveries"]["orders"] as Array).size(), 1)
	var cash: int = Economy.cash
	_close(first)
	Economy.reset(12345)
	var second: Node = _start(true, tuning)
	assert_eq(Economy.cash, cash, "the reload paid nothing twice")
	assert_eq((second.get("deliveries") as DeliveryBook).pending_by_id(), book.pending_by_id())
	assert_true(Clock.sim.start_service())
	assert_eq(Economy.stock.count(&"bread"), TUNING.morning_stock[&"bread"], "it arrives at opening")
	assert_true((second.get("deliveries") as DeliveryBook).is_empty())


## An order placed after the morning save is lost on reload together with its
## payment, like everything else since that save: no money is lost.
func test_an_order_after_the_morning_save_goes_back_with_its_payment() -> void:
	var first: Node = _start(true)
	var saved_cash: int = Economy.cash
	assert_true(first.call("stock_cart_set", &"tomato", 5))
	assert_true(first.call("stock_place_order"))
	assert_eq(Economy.cash, saved_cash - 5)
	_close(first)
	Economy.reset(12345)
	var second: Node = _start(true)
	assert_eq(Economy.cash, saved_cash, "the payment is not kept")
	assert_true((second.get("deliveries") as DeliveryBook).is_empty(), "and nothing is on order")
	assert_eq(Economy.stock.count(&"tomato"), TUNING.morning_stock[&"tomato"])


func test_legacy_saves_load_with_nothing_on_order_and_keep_over_full_stock() -> void:
	var first: Node = _start(true)
	_close(first)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	document["data"].erase("deliveries")
	# A save from before storage limits: far more cheese than the fridge holds.
	var batches: Dictionary = document["data"]["economy"]["stock"]["batches"]
	batches["cheese"] = [{"qty": "60", "bought_day": "1"}]
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(_path() + ".bak"):
		DirAccess.remove_absolute(_path() + ".bak")
	Economy.reset(12345)
	var second: Node = _start(true)
	assert_true((second.get("deliveries") as DeliveryBook).is_empty())
	assert_eq(Economy.stock.count(&"cheese"), 60, "nothing is lost")
	var space: StorageSpace = second.call("storage_space")
	assert_true(space.is_over(StorageSpace.FRIDGE))
	assert_false(second.call("stock_cart_set", &"lettuce", 1), "new fridge buys wait until it is back under")
	assert_true(second.call("stock_cart_set", &"bread", 1), "dry buys are fine")
	var notes: Array[String] = second.call("stock_notes")
	assert_true(notes.has("The fridge is over its space: nothing more of it can be ordered until some is used."), str(notes))


func test_freezer_ingredients_keep_longer() -> void:
	var main: Node = _start(false)
	var cheese: IngredientDef = (main.get("content") as ContentDB).ingredient(&"cheese")
	var storage: IngredientDef.Storage = cheese.storage
	cheese.storage = IngredientDef.Storage.FREEZER
	var lives: Dictionary = main.call("_shelf_lives")
	cheese.storage = storage
	assert_eq(lives[&"cheese"], TUNING.freezer_shelf_life_days)
	assert_eq((main.call("_shelf_lives") as Dictionary)[&"cheese"], 5, "the fridge uses the ingredient's own")


func test_shelves_show_crates_in_proportion_to_how_full_dry_storage_is() -> void:
	var main: Node = _start(false)
	Economy.add_cash(500, Ledger.SALE)
	assert_true(main.call("set_build_active", true))
	assert_true(main.call("shop_buy", &"storage_shelf", Vector2i(12, 1), 2))
	assert_true(main.call("set_build_active", false))
	var shelf: PlacedItem = (main.get("world") as SimWorld).grid.item_at(Vector2i(12, 1))
	main.call("refresh_presentation")
	assert_eq(_shown(main, shelf.id), 6, "50 of 100 dry units: 6 of 11 crates and boxes")
	for id: StringName in [&"bread", &"bun", &"soup_stock", &"tomato"]:
		Economy.stock.take(id, Economy.stock.count(id))
	Economy.stock.add(&"bread", 2, Clock.sim.day)
	main.call("refresh_presentation")
	assert_eq(_shown(main, shelf.id), 1, "a nearly empty store still shows its last crate")
	Economy.stock.take(&"bread", 2)
	main.call("refresh_presentation")
	assert_eq(_shown(main, shelf.id), 0)
	Economy.stock.add(&"bread", 100, Clock.sim.day)
	main.call("refresh_presentation")
	assert_eq(_shown(main, shelf.id), 11, "full")
	assert_eq(ShopView.stock_slots_shown(0.5, 11), 6)
	assert_eq(ShopView.stock_slots_shown(0.01, 11), 1)


func _shown(main: Node, item_id: int) -> int:
	var view: ShopView = main.get_node("ShopView") as ShopView
	var node: Node = view.item_nodes[item_id]
	var slots: Array[Node3D] = []
	ShopView._collect_stock_slots(node, slots)
	assert_eq(slots.size(), 11)
	var shown: int = 0
	for slot: Node3D in slots:
		if slot.visible:
			shown += 1
	return shown


func _next_morning() -> void:
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


func _start(with_saves: bool, tuning: EconomyTuning = null) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	if tuning != null:
		main.set("delivery_tuning", tuning)
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


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")
