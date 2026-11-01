extends TestCase
## Actual paid tickets, cancelled cooking, deliveries, historical reports and
## the normal morning checkpoint keep cash and served-food costs distinct.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const REPORT_SCENE: PackedScene = preload("res://src/ui/evening_report.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SLOT: String = "profit_accounting"

var _mains: Array[Node] = []
var _screens: Array[Control] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for screen: Control in _screens:
		screen.free()
	_screens.clear()
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_real_paid_meal_and_extra_drink_exclude_consumed_cancelled_food() -> void:
	var main: Node = await _start(false)
	assert_true(main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	var sim: RestaurantSim = main.get("sim")
	var content: ContentDB = main.get("content")
	_no_arrivals(sim)
	for ingredient: IngredientDef in content.ingredients():
		main.call("stock_set_auto", ingredient.id, false)
	Economy.reset(1000)
	sim.stock = Economy.stock
	# Deliberate real purchase prices differ from today's recipe list costs.
	for line: Dictionary in [{"id": &"bun", "price": 3}, {"id": &"beef_patty", "price": 7},
			{"id": &"lettuce", "price": 2}, {"id": &"coffee_beans", "price": 5}]:
		assert_true(Economy.buy_ingredient(line["id"], 3, line["price"]))
	sim.menu = [content.recipe(&"burger"), content.recipe(&"coffee")] as Array[RecipeDef]
	assert_true(Clock.sim.start_service())
	var happy: CustomerAgent = _guest(sim, 3)
	happy.drink_add_chance = 1.0
	happy.eat_ticks = 300
	for tick: int in range(4000):
		main.call("run_ticks", 1)
		if happy.paid:
			break
	assert_true(happy.paid, "the actual guest paid after real preparation and delivery")
	assert_not_null(happy.order)
	assert_not_null(happy.extra_order)
	if happy.order == null or happy.extra_order == null:
		return
	assert_eq(happy.order.recipe_id, &"burger")
	assert_eq(happy.extra_order.recipe_id, &"coffee")
	assert_true(happy.order.paid)
	assert_true(happy.extra_order.paid, "a delivered side drink contributes its own paid cost")
	assert_eq(happy.order.ingredient_cost, 12)
	assert_eq(happy.extra_order.ingredient_cost, 5)
	assert_true(happy.order.ingredient_cost_recorded and happy.extra_order.ingredient_cost_recorded)
	var paid_report: DayReport = main.call("build_report", 1)
	assert_eq(paid_report.food_cost, 17)
	assert_true(paid_report.food_cost_recorded)
	assert_eq(paid_report.stock_bought, 51)
	assert_eq(paid_report.stock_on_hand, 34)
	var paid_books: Dictionary = Economy.ledger.to_dict()
	sim.pay(happy, happy.order)
	assert_eq(Economy.ledger.to_dict(), paid_books, "retrying payment never charges or counts food twice")
	assert_eq((main.call("build_report", 1) as DayReport).food_cost, 17)
	sim.menu = [content.recipe(&"burger")] as Array[RecipeDef]
	var cancelled: CustomerAgent = _guest(sim, 5)
	for tick: int in range(2000):
		main.call("run_ticks", 1)
		if cancelled.order != null and cancelled.order.ingredient_cost_recorded:
			break
	assert_not_null(cancelled.order)
	if cancelled.order == null:
		return
	assert_true(cancelled.order.ingredient_cost_recorded, "observe actual successful ingredient consumption")
	assert_eq(cancelled.order.ingredient_cost, 12)
	var stock_before_retry: Dictionary = Economy.stock.to_dict()
	var retried: bool = false
	for agent: SimAgent in sim.world.agents:
		if agent is StaffAgent and (agent as StaffAgent).task != null:
			var worker: StaffAgent = agent as StaffAgent
			if int(worker.task.payload.get("order_id", 0)) == cancelled.order.id \
					and bool(worker.task.payload.get("ingredients_taken", false)):
				assert_true(sim.kitchen._take_ingredients(worker))
				retried = true
	assert_true(retried, "retry the real task callback after its actual ingredient take")
	assert_eq(Economy.stock.to_dict(), stock_before_retry, "retry does not take or reprice food twice")
	sim.orders.set_state(cancelled.order, Order.State.CANCELLED, &"target_gone")
	assert_false(cancelled.paid)
	assert_false(cancelled.order.paid)
	assert_eq(cancelled.order.ingredient_cost, 12, "wasted prepared food retains its actual cost")
	var report: DayReport = main.call("build_report", 1)
	assert_eq(report.food_cost, 17, "consumed but unpaid food is not cost of sold dishes")
	assert_eq(report.stock_on_hand, 22)
	assert_eq(report.food_cost + cancelled.order.ingredient_cost + report.stock_on_hand, report.stock_bought)


func test_pending_order_refund_and_partial_crates_preserve_paid_purchase_basis() -> void:
	var main: Node = await _start(false)
	var sim: RestaurantSim = main.get("sim")
	_no_arrivals(sim)
	assert_true(Clock.sim.start_service())
	var before: DayReport = main.call("build_report", 1)
	var cash: int = Economy.cash
	assert_true(main.call("stock_cart_set", &"tomato", 2))
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.cash, cash - 2)
	var pending: DayReport = main.call("build_report", 1)
	assert_eq(pending.stock_bought, before.stock_bought + 2)
	assert_eq(pending.stock_on_hand, before.stock_on_hand, "paid pending goods are not inventory yet")
	assert_eq(pending.food_cost, 0)
	assert_eq(main.call("stock_cancel_orders"), 2)
	var refunded: DayReport = main.call("build_report", 1)
	assert_eq(Economy.cash, cash)
	assert_eq(refunded.stock_bought, before.stock_bought + 2, "gross stock bought remains visible after its refund")
	assert_eq(refunded.profit(), before.profit(), "the signed cash books include the full refund")
	assert_eq(refunded.operating_profit(), before.operating_profit())
	assert_eq(refunded.stock_on_hand, before.stock_on_hand)
	# A paid premium-bearing order keeps separate valued lots through JSON and
	# two physical storage kinds. Observe one crate put away before the other.
	var lines: Array[Dictionary] = [{"id": &"coffee_beans", "qty": 3, "unit_cost": 1},
		{"id": &"cheese", "qty": 2, "unit_cost": 2}]
	assert_true(Economy.pay_order(lines, 10, true))
	var book: DeliveryBook = DeliveryBook.new()
	assert_true(book.place(lines, 10, true, Vector2i(1, Clock.sim.phase_tick)))
	var restored: DeliveryBook = DeliveryBook.new()
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(book.to_dict()))))
	var delivered: Array[Dictionary] = restored.take_due_valued(Clock.sim)
	assert_eq(delivered.size(), 2)
	assert_eq(delivered[0]["total_cost"], 5)
	assert_eq(delivered[1]["total_cost"], 5)
	var inventory_before: int = int(Economy.stock.value()["cost"])
	assert_true(sim.dock.arrive(delivered))
	assert_eq(int(Economy.stock.value()["cost"]), inventory_before, "courier goods are not yet on hand")
	var saw_partial: bool = false
	for tick: int in range(2500):
		main.call("run_ticks", 1)
		var added: int = int(Economy.stock.value()["cost"]) - inventory_before
		if added > 0 and added < 10:
			assert_eq(added, 5, "the first carried crate retains only its paid lot value")
			saw_partial = true
			break
	assert_true(saw_partial, "real staff put away one crate before the second")
	sim.dock.store_all()
	assert_eq(int(Economy.stock.value()["cost"]), inventory_before + 10)
	assert_true(sim.dock.pending_by_id().is_empty())
	assert_eq((main.call("build_report", 1) as DayReport).food_cost, 0)


func test_real_morning_spoilage_survives_checkpoint_reload_once() -> void:
	var first: Node = await _start(true)
	assert_true(Economy.buy_ingredient(&"coffee_beans", 2, 3))
	# Use a deliberately old known-value batch, through the public lot API,
	# then enter the ordinary morning path that expires and autosaves it.
	Economy.stock.add(&"coffee_beans", 1, -20, 7)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	var morning: DayReport = first.call("build_report", 2)
	assert_true(morning.spoiled_stock_recorded)
	assert_true(morning.spoiled_stock >= 7)
	assert_eq(Economy.stock.count(&"coffee_beans"), 2)
	var expected_spoilage: int = morning.spoiled_stock
	var expected_cash: int = Economy.cash
	var expected_inventory: int = morning.stock_on_hand
	_close(first)
	var second: Node = await _start(true)
	assert_eq(Clock.sim.day, 2)
	var reloaded: DayReport = second.call("build_report", 2)
	assert_eq(reloaded.spoiled_stock, expected_spoilage, "reload keeps the morning loss receipt")
	assert_true(reloaded.spoiled_stock_recorded)
	assert_eq(reloaded.stock_on_hand, expected_inventory)
	assert_eq(Economy.cash, expected_cash, "reloading neither buys nor charges expired goods twice")
	assert_eq(Economy.stock.count(&"coffee_beans"), 2)


func test_report_json_legacy_and_invalid_optional_values_are_truthful() -> void:
	var report: DayReport = _known_report()
	assert_eq(report.operating_profit(), 63)
	assert_eq(report.profit(), 46)
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(report.to_dict())))
	assert_eq(restored.to_dict(), report.to_dict())
	assert_true(restored.operating_profit_recorded())
	var legacy: DayReport = DayReport.from_dict({"day": 4, "income": {"sale": 100},
		"costs": {"ingredients": 45, "rent": 20}})
	assert_false(legacy.stock_values_recorded)
	assert_false(legacy.food_cost_recorded)
	assert_false(legacy.operating_profit_recorded())
	assert_eq(legacy.food_cost, 0)
	assert_eq(legacy.operating_profit(), 35, "historical cash-basis reports retain their original arithmetic")
	assert_eq(legacy.profit(), 35)
	for malformed: Variant in [-1, 1.5, true, {}, "-1", "9223372036854775808", null]:
		var bad: Dictionary = report.to_dict()
		bad["food_cost"] = malformed
		var decoded: DayReport = DayReport.from_dict(bad)
		assert_false(decoded.food_cost_recorded)
		assert_false(decoded.operating_profit_recorded())
		assert_eq(decoded.profit(), 46, "optional valuation rejection never rewrites historical cash")
	var large: Dictionary = report.to_dict()
	large["stock_on_hand"] = "9007199254740993"
	assert_eq(DayReport.from_dict(JSON.parse_string(JSON.stringify(large))).stock_on_hand, 9007199254740993)


func test_evening_report_renders_known_unknown_and_legacy_values_without_mutation() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var screen: Control = REPORT_SCENE.instantiate()
	_screens.append(screen)
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	var report: DayReport = _known_report()
	var original: Dictionary = report.to_dict()
	screen.call("show_report", report)
	assert_eq((screen.get_node("%Profit") as Label).text, "$63 operating profit")
	assert_eq((screen.get_node("%CashChange") as Label).text, "Cash change today: $46")
	assert_eq(_label_texts(screen.get_node("%StockRows")),
		["Stock bought today", "$45", "Spoiled stock", "$3", "Stock on hand worth", "$25"] as Array[String])
	var costs: Array[String] = _label_texts(screen.get_node("%CostRows"))
	assert_true(costs.has("Cost of food served"))
	assert_false(costs.has("Ingredients"))
	assert_eq(report.to_dict(), original, "presentation never rewrites the cash report")
	report.food_cost_recorded = false
	report.stock_on_hand_recorded = false
	screen.call("show_report", report)
	assert_eq((screen.get_node("%Profit") as Label).text, "Operating profit not recorded")
	assert_true(_label_texts(screen.get_node("%CostRows")).has("Not recorded"))
	assert_eq(_label_texts(screen.get_node("%StockRows"))[-1], "Not recorded")
	var legacy: DayReport = DayReport.from_dict({"income": {"sale": 20}, "costs": {"ingredients": 25}})
	screen.call("show_report", legacy)
	assert_eq((screen.get_node("%Profit") as Label).text, "Operating profit not recorded")
	assert_eq((screen.get_node("%CashChange") as Label).text, "Cash change today: -$5")
	assert_true(_label_texts(screen.get_node("%CostRows")).has("Ingredients"))
	assert_eq(_label_texts(screen.get_node("%StockRows")),
		["Stock bought today", "Not recorded", "Spoiled stock", "Not recorded",
		"Stock on hand worth", "Not recorded"] as Array[String])


func test_report_overflow_and_malformed_flags_cannot_advertise_an_exact_headline() -> void:
	var report: DayReport = _known_report()
	report.food_cost = 9223372036854775807
	assert_false(report.operating_profit_recorded(), "food plus fixed costs exceeds the integer range")
	report = _known_report()
	report.income = {Ledger.SALE: 9223372036854775807, Ledger.TIP: 1}
	assert_false(report.operating_profit_recorded(), "total takings cannot wrap into an exact loss")
	for field: String in ["food_cost", "stock_bought", "spoiled_stock", "stock_on_hand"]:
		var bad: Dictionary = _known_report().to_dict()
		bad[field + "_recorded"] = 1
		var restored: DayReport = DayReport.from_dict(bad)
		assert_false(restored.get(field + "_recorded"), "a truthy number is not a recorded-value flag")
	var invalid_version_flag: Dictionary = _known_report().to_dict()
	invalid_version_flag["stock_values_recorded"] = "true"
	assert_false(DayReport.from_dict(invalid_version_flag).operating_profit_recorded())


func test_real_morning_and_opening_station_orders_use_the_forecast_menu_mix() -> void:
	var main: Node = await _start(false)
	assert_true(main.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(main.call("menu_set_enabled", &"grilled_cheese", false))
	var sim: RestaurantSim = main.get("sim")
	Economy.reset(1000)
	sim.stock = Economy.stock
	assert_true(sim.set_demand_factor(0.5))
	var expected_meals: int = sim.expected_demand_guests(0.5)
	var expected_units: int = ceili(expected_meals * TUNING.restock_buffer)
	assert_true(expected_units > 0 and expected_units * 2 <= 40,
		"this focused shop can store a whole forecast day's burger ingredients")
	var rng: Dictionary = GameState._capture_save()
	var targets: Dictionary = main.call("restock_forecast_targets")
	assert_eq(targets[&"bun"], expected_units)
	assert_eq(GameState._capture_save(), rng)
	main.call("_restock")
	for id: StringName in [&"bun", &"beef_patty", &"lettuce"]:
		assert_eq(Economy.stock.count(id), expected_units, "the real morning order buys the forecast use")
	for id: StringName in [&"bread", &"cheese", &"tomato", &"soup_stock"]:
		assert_eq(Economy.stock.count(id), 0, "unused automatic food is absent from the real order")
	assert_true(main.call("shop_buy", &"coffee_machine", Vector2i(12, 5), 2))
	assert_true(main.call("menu_set_enabled", &"tea", false))
	assert_true(main.call("menu_set_enabled", &"burger", false))
	assert_eq(sim.menu.size(), 1)
	assert_eq(sim.menu[0].id, &"coffee")
	Economy.reset(1000)
	sim.stock = Economy.stock
	assert_true(sim.set_demand_factor(0.5))
	var expected_coffees: int = sim.expected_demand_guests(0.5)
	var expected_beans: int = ceili(expected_coffees * TUNING.restock_buffer)
	assert_true(expected_beans > 0 and expected_beans <= 60)
	assert_true(Clock.sim.start_service())
	assert_eq(Economy.stock.count(&"coffee_beans"), expected_beans,
		"opening station supplies use a day of forecast coffee rather than the fixed 30-unit order")
	assert_eq(Economy.stock.ids(), [&"coffee_beans"] as Array[StringName])
	var report: DayReport = main.call("build_report", 1)
	assert_eq(report.food_cost, 0)
	assert_eq(report.stock_on_hand, report.stock_bought, "all paid opening supplies remain unused on hand")


func test_real_legacy_stock_cooks_and_sells_without_inventing_a_purchase_cost() -> void:
	var main: Node = await _start(false)
	var sim: RestaurantSim = main.get("sim")
	var content: ContentDB = main.get("content")
	_no_arrivals(sim)
	Economy.reset(1000)
	sim.stock = Economy.stock
	for ingredient: IngredientDef in content.recipe(&"burger").ingredients:
		Economy.stock.add(ingredient.id, 3, 1)
	sim.menu = [content.recipe(&"burger")] as Array[RecipeDef]
	assert_true(Clock.sim.start_service())
	var guest: CustomerAgent = _guest(sim, 3)
	for tick: int in range(2000):
		main.call("run_ticks", 1)
		if guest.paid:
			break
	assert_true(guest.paid, "legacy price metadata never blocks actual cooking or payment")
	assert_not_null(guest.order)
	if guest.order == null:
		return
	assert_true(guest.order.paid)
	assert_false(guest.order.ingredient_cost_recorded)
	var report: DayReport = main.call("build_report", 1)
	assert_false(report.food_cost_recorded)
	assert_false(report.operating_profit_recorded(), "today's catalog price cannot reconstruct yesterday's lot")
	assert_eq(report.profit(), guest.order.price)
	assert_eq(Economy.cash, 1000 + guest.order.price)


func test_rejected_optional_stock_metadata_preserves_live_economy_models() -> void:
	var main: Node = await _start(false)
	var ledger: Ledger = Economy.ledger
	var stock: Stock = Economy.stock
	var loan: LoanAccount = Economy.loan
	var original: Dictionary = Economy._capture_save()
	var bad: Dictionary = original.duplicate(true)
	var first_id: String = bad["stock"]["batches"].keys()[0]
	bad["stock"]["batches"][first_id][0]["total_cost"] = "9223372036854775808"
	assert_false(Economy._restore_save(bad))
	assert_true(Economy.ledger == ledger)
	assert_true(Economy.stock == stock)
	assert_true(Economy.loan == loan)
	assert_eq(Economy._capture_save(), original)
	assert_true((main.get("sim") as RestaurantSim).stock == stock, "failed restore keeps the live kitchen inventory")


func test_tomorrows_standing_targets_follow_projected_growth_without_mutating_the_morning() -> void:
	var main: Node = await _start(false)
	assert_true(main.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(main.call("menu_set_enabled", &"grilled_cheese", false))
	var before: Dictionary = main.call("forecast_next_demand")
	var sim: RestaurantSim = main.get("sim")
	var growth: DemandState = main.get("demand_state")
	var tuning: DemandTuning = main.get("demand_tuning")
	assert_true(growth.award_close(1, 100, sim.demand_factor, tuning), "a real growth-model award raises tomorrow's renown")
	var after: Dictionary = main.call("forecast_next_demand")
	assert_true(int(after["expected_guests"]) > int(before["expected_guests"]))
	var state: Dictionary = growth.to_dict()
	var choices: Dictionary = (main.get("reorder_settings") as ReorderSettings).to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var rng: Dictionary = GameState._capture_save()
	var stock: Dictionary = Economy.stock.to_dict()
	var cash: int = Economy.cash
	var targets: Dictionary = main.call("restock_forecast_targets", true)
	var expected_units: int = ceili(int(after["expected_guests"]) * TUNING.restock_buffer)
	assert_eq(targets[&"bun"], expected_units)
	assert_eq((main.call("_reorder", true) as ReorderSettings).target(&"bun"), expected_units)
	assert_eq(growth.to_dict(), state, "forecasting stages tomorrow's decay without applying it today")
	assert_eq((main.get("reorder_settings") as ReorderSettings).to_dict(), choices)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(GameState._capture_save(), rng)
	assert_eq(Economy.stock.to_dict(), stock)
	assert_eq(Economy.cash, cash)


func _known_report() -> DayReport:
	var report: DayReport = DayReport.new()
	report.income = {Ledger.SALE: 100, Ledger.TIP: 5, Ledger.MILESTONE_BONUS: 20}
	report.costs = {Ledger.INGREDIENTS: 45, Ledger.WAGES: 20, Ledger.RENT: 10, Ledger.LOAN_REPAYMENT: 4}
	report.stock_values_recorded = true
	report.food_cost = 12
	report.food_cost_recorded = true
	report.stock_bought = 45
	report.stock_bought_recorded = true
	report.spoiled_stock = 3
	report.spoiled_stock_recorded = true
	report.stock_on_hand = 25
	report.stock_on_hand_recorded = true
	return report


func _label_texts(node: Node) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in node.get_children():
		if child is Label:
			labels.append((child as Label).text)
	return labels


func _no_arrivals(sim: RestaurantSim) -> void:
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.start_day()


func _guest(sim: RestaurantSim, seed_value: int) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random)
	guest.food_patience = 5000
	guest.eat_ticks = 3
	return guest


func _start(saves: bool) -> Node:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 7)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()
