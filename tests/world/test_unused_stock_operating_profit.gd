extends TestCase
## Real matched service days: buying unused stock changes cash, but cannot
## change the profit made by exactly the same dishes sold to the same guests.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SEED: int = 7
const UNUSED_INGREDIENT: StringName = &"coffee_beans"
const SLOT: String = "unused_stock_operating_profit"

var _mains: Array[Node] = []
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


func test_unused_stock_purchase_changes_cash_but_not_operating_profit() -> void:
	var baseline: Dictionary = await _run_real_day(false)
	var purchased: Dictionary = await _run_real_day(true)
	var ordinary: DayReport = baseline["report"]
	var extra: DayReport = purchased["report"]
	var purchase_cost: int = purchased["purchase_cost"]
	assert_true(ordinary.customers_served > 0, "the real kitchen served paying guests")
	assert_true(int(ordinary.income.get(Ledger.SALE, 0)) > 0, "real meals earned sales")
	assert_eq(purchased["opening_cash"], baseline["opening_cash"], "same morning before purchase")
	assert_eq(purchased["opening_rng"], baseline["opening_rng"], "same initial random streams")
	assert_eq(purchased["closing_rng"], baseline["closing_rng"], "same final random streams")
	assert_eq(purchased["clock"], baseline["clock"], "same complete service duration")
	assert_eq(purchased["orders"], baseline["orders"], "same real tickets, outcomes and quality")
	assert_eq(purchased["stock"], baseline["stock"], "same consumption of every menu ingredient")
	assert_eq(extra.customers_served, ordinary.customers_served, "same served guests")
	assert_eq(extra.customers_lost, ordinary.customers_lost, "same lost guests")
	assert_eq(extra.dishes_sold, ordinary.dishes_sold, "same dishes sold")
	assert_eq(extra.leave_reasons, ordinary.leave_reasons, "same guest departures")
	assert_eq(extra.review_cards, ordinary.review_cards, "same reviews and quotes")
	assert_eq(extra.reputation_after, ordinary.reputation_after, "same closing reputation")
	assert_eq(extra.owner_xp_breakdown, ordinary.owner_xp_breakdown, "purchase crosses no XP threshold")
	assert_eq(purchased["owner"], baseline["owner"], "same owner progression")
	assert_eq(purchased["milestones"], baseline["milestones"], "same milestone completions")
	assert_eq(extra.milestones_reached, ordinary.milestones_reached, "same authored rewards")
	assert_eq(purchased["loan"], baseline["loan"], "same financing settlement")
	assert_eq(extra.income, ordinary.income, "all income including bonus and financing is unchanged")
	var cash_costs: Dictionary = extra.costs.duplicate()
	cash_costs.erase(Ledger.INGREDIENTS)
	var ordinary_costs: Dictionary = ordinary.costs.duplicate()
	ordinary_costs.erase(Ledger.INGREDIENTS)
	assert_eq(cash_costs, ordinary_costs, "same wages, rent and every other cash cost")
	assert_eq(purchased["unused_stock"], int(baseline["unused_stock"]) + 1,
		"the entire extra purchased unit remains unused at closing")
	assert_eq(int(extra.costs.get(Ledger.INGREDIENTS, 0)),
		int(ordinary.costs.get(Ledger.INGREDIENTS, 0)) + purchase_cost,
		"the real purchase remains in the cash books")
	assert_eq(int(purchased["cash"]), int(baseline["cash"]) - purchase_cost,
		"closing cash falls by exactly the real stock purchase")
	assert_eq(extra.profit(), ordinary.profit() - purchase_cost,
		"cash change includes the extra purchase exactly once")
	print("UNUSED STOCK PAIR: ", JSON.stringify({"seed": SEED, "cost": purchase_cost,
		"baseline_profit": ordinary.operating_profit(), "purchased_profit": extra.operating_profit(),
		"baseline_cash": baseline["cash"], "purchased_cash": purchased["cash"],
		"served": ordinary.customers_served, "dishes": ordinary.dishes_sold}))
	assert_eq(extra.operating_profit(), ordinary.operating_profit(),
		"buying stock that was never used cannot reduce profit from the same dishes sold")


func _run_real_day(buy_unused: bool) -> Dictionary:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", SEED)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	var sim: RestaurantSim = main.get("sim")
	var content: ContentDB = main.get("content")
	for recipe: RecipeDef in sim.menu:
		for ingredient: IngredientDef in recipe.ingredients:
			assert_ne(ingredient.id, UNUSED_INGREDIENT, "the extra stock is absent from the real menu")
	var opening_cash: int = Economy.cash
	var opening_rng: Dictionary = GameState._capture_save()
	var opening_unused: int = Economy.stock.count(UNUSED_INGREDIENT)
	var purchase_cost: int = content.ingredient(UNUSED_INGREDIENT).unit_cost
	assert_true(purchase_cost > 0, "use a genuine charged ingredient")
	if buy_unused:
		assert_true(Economy.buy_ingredient(UNUSED_INGREDIENT, 1, purchase_cost), "real stock purchase succeeds")
		assert_eq(Economy.cash, opening_cash - purchase_cost, "purchase charges the authored cost")
		assert_eq(GameState._capture_save(), opening_rng, "buying unused stock draws no randomness")
	assert_true(Clock.sim.start_service(), "the unchanged shop opens")
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 20:
		main.call("run_ticks", 1000)
		guard += 1
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED, "the full real day closes")
	var report: DayReport = main.get("shown_report")
	assert_not_null(report, "normal closing builds the real report")
	assert_eq(report.profit(), Economy.cash - TUNING.starting_cash, "report cash movement reconciles")
	assert_eq(Economy.stock.count(UNUSED_INGREDIENT), opening_unused + (1 if buy_unused else 0),
		"no extra stock is consumed or spoiled")
	var stocks: Dictionary = {}
	for id: StringName in Economy.stock.ids():
		if id != UNUSED_INGREDIENT:
			stocks[id] = Economy.stock.count(id)
	var tickets: Array[Dictionary] = []
	for state: int in Order.State.values():
		for order: Order in sim.orders.orders_in_state(state):
			tickets.append({"id": order.id, "customer": order.customer_id,
				"recipe": order.recipe_id, "price": order.price, "placed": order.placed_tick,
				"state": order.state, "quality": order.quality, "reason": order.cancellation_reason})
	var snapshot: Dictionary = {"report": report, "cash": Economy.cash,
		"opening_cash": opening_cash, "purchase_cost": purchase_cost,
		"opening_rng": opening_rng, "closing_rng": GameState._capture_save(),
		"clock": Clock.sim.to_dict(), "orders": tickets, "stock": stocks,
		"unused_stock": Economy.stock.count(UNUSED_INGREDIENT),
		"owner": (main.get("owner_progress") as OwnerProgress).to_dict(),
		"milestones": (main.get("milestones") as MilestoneTracker).to_dict(),
		"loan": Economy.loan.to_dict()}
	_close(main)
	return snapshot


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()
