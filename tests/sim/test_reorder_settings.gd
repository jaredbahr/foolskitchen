extends TestCase
## Morning auto-reorder settings, the order plan, its premium and its save data.

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")


func _costs() -> Dictionary:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var costs: Dictionary = {}
	for ingredient: IngredientDef in content.ingredients():
		costs[ingredient.id] = ingredient.unit_cost
	return costs


func _bought(plan: Dictionary) -> Dictionary:
	var bought: Dictionary = {}
	for line: Dictionary in plan["lines"]:
		bought[line["id"]] = int(line["qty"])
	return bought


## Every ingredient starts enabled at its old morning_stock amount, so an
## empty fridge buys exactly what the fixed top-up used to buy.
func test_defaults_reproduce_the_old_restock_amounts() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	assert_eq(settings.ids().size(), TUNING.morning_stock.size())
	var index: int = 0
	for id: StringName in TUNING.morning_stock:
		assert_eq(settings.ids()[index], id, "the fixed order follows morning_stock")
		index += 1
	for id: StringName in TUNING.morning_stock:
		assert_true(settings.is_enabled(id))
		assert_eq(settings.target(id), TUNING.morning_stock[id])
	var plan: Dictionary = settings.plan(Stock.new(), _costs(), 10000, TUNING.auto_reorder_premium)
	var bought: Dictionary = _bought(plan)
	# Frozen fries are station-only: the starter menu never auto-buys them.
	assert_false(TUNING.morning_stock.has(&"frozen_fries"))
	assert_false(bought.has(&"frozen_fries"))
	assert_eq(bought.size(), TUNING.morning_stock.size())
	for id: StringName in TUNING.morning_stock:
		assert_eq(int(bought.get(id, 0)), TUNING.morning_stock[id], "%s matches the old top-up" % id)
	assert_eq(plan["list_total"], 88)
	assert_eq(plan["cost"], ReorderSettings.auto_cost(88, TUNING.auto_reorder_premium),
		"the tuned premium applies once to the whole order")
	assert_true((plan["short"] as Dictionary).is_empty())
	# A part-stocked fridge only tops up what is missing.
	var stock: Stock = Stock.new()
	stock.add(&"bun", 7, 1)
	stock.add(&"tomato", 20, 1)
	var top_up: Dictionary = _bought(settings.plan(stock, _costs(), 10000, 0.1))
	assert_eq(top_up[&"bun"], 3)
	assert_false(top_up.has(&"tomato"), "stock above target buys nothing")


## Applied once to the order total, not per unit: 10 x $1 costs $11, not $20.
func test_premium_is_charged_once_on_the_order_total() -> void:
	assert_eq(ReorderSettings.auto_cost(10, 0.1), 11)
	assert_eq(ReorderSettings.auto_cost(88, 0.1), 97)
	assert_eq(ReorderSettings.auto_cost(1, 0.1), 2, "any premium on a non-empty order rounds up")
	assert_eq(ReorderSettings.auto_cost(0, 0.1), 0)
	assert_eq(ReorderSettings.auto_cost(10, 0.0), 10)
	assert_eq(ReorderSettings.auto_cost(100, 0.1), 110, "no float drift at exact tenths")
	var tuning: EconomyTuning = EconomyTuning.new()
	tuning.morning_stock = {&"bun": 10} as Dictionary[StringName, int]
	var settings: ReorderSettings = ReorderSettings.new(tuning)
	var plan: Dictionary = settings.plan(Stock.new(), {&"bun": 1}, 100, 0.1)
	assert_eq(plan["list_total"], 10)
	assert_eq(plan["cost"], 11)


func test_disabled_ingredient_is_not_bought() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(settings.set_enabled(&"tomato", false))
	var bought: Dictionary = _bought(settings.plan(Stock.new(), _costs(), 10000, 0.1))
	assert_false(bought.has(&"tomato"))
	assert_eq(bought[&"bread"], 16, "other ingredients are still bought")
	assert_false(settings.set_enabled(&"unknown", false))


## Short cash buys what fits in the fixed order, never more than the cash.
func test_short_cash_buys_partially_in_the_fixed_order() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	var plan: Dictionary = settings.plan(Stock.new(), _costs(), 30, 0.1)
	assert_true(int(plan["cost"]) <= 30, "the order never exceeds the cash")
	assert_eq(plan["cost"], ReorderSettings.auto_cost(int(plan["list_total"]), 0.1),
		"a partial order is priced as its own total")
	var bought: Dictionary = _bought(plan)
	assert_eq(bought[&"beef_patty"], 10, "the first ingredient in the fixed order is filled first")
	assert_true(bought.has(&"bread"))
	var short: Dictionary = plan["short"]
	assert_true(short.has(&"tomato"), "what did not fit is reported")
	for id: StringName in TUNING.morning_stock:
		assert_eq(int(bought.get(id, 0)) + int(short.get(id, 0)), TUNING.morning_stock[id])
	var broke: Dictionary = settings.plan(Stock.new(), _costs(), 0, 0.1)
	assert_true((broke["lines"] as Array).is_empty())
	assert_eq(broke["cost"], 0)
	assert_eq(settings.plan(Stock.new(), _costs(), -50, 0.1)["cost"], 0, "a negative balance never borrows")


func test_targets_are_bounded() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(settings.set_target(&"bun", 0))
	assert_true(settings.set_target(&"bun", ReorderSettings.MAX_TARGET))
	assert_false(settings.set_target(&"bun", ReorderSettings.MAX_TARGET + 1))
	assert_false(settings.set_target(&"bun", -1))
	assert_false(settings.set_target(&"unknown", 3))
	assert_eq(settings.target(&"bun"), ReorderSettings.MAX_TARGET)
	assert_eq(settings.default_target(&"bun"), 10)


func test_settings_survive_a_json_round_trip() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	settings.set_enabled(&"cheese", false)
	settings.set_target(&"tomato", 24)
	var data: Dictionary = settings.to_dict()
	assert_eq(data["version"], ReorderSettings.VERSION)
	var json: Variant = JSON.parse_string(JSON.stringify(data))
	var restored: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(restored.from_dict(json))
	assert_false(restored.is_enabled(&"cheese"))
	assert_eq(restored.target(&"tomato"), 24)
	assert_eq(restored.to_dict(), data)
	var copy: ReorderSettings = restored.copy()
	copy.set_target(&"tomato", 2)
	assert_eq(restored.target(&"tomato"), 24, "a copy is detached")


## Missing ingredients keep defaults, retired ids are ignored, and bad data
## changes nothing.
func test_restore_validates_before_changing_anything() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(settings.from_dict({"version": 1, "ingredients": {
		"bun": {"enabled": false, "target": 4}, "retired": {"enabled": true, "target": 1}}}))
	assert_false(settings.is_enabled(&"bun"))
	assert_eq(settings.target(&"bread"), 16)
	var before: Dictionary = settings.to_dict()
	for bad: Dictionary in [{}, {"version": 2, "ingredients": {}}, {"version": 1},
			{"version": 1, "ingredients": {"bread": {"enabled": "yes", "target": 3}}},
			{"version": 1, "ingredients": {"bread": {"enabled": true, "target": 3}, "bun": {"enabled": true, "target": -1}}},
			{"version": 1, "ingredients": {"bread": {"enabled": true, "target": 2.5}}}]:
		assert_false(settings.from_dict(bad), "rejects %s" % [bad])
		assert_eq(settings.to_dict(), before)


func test_bar_fries_recipe_and_level_two_unlock() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var recipe: RecipeDef = content.recipe(&"bar_fries")
	assert_eq(recipe.display_name, "Bar fries")
	assert_eq(recipe.unlock_from, &"beer")
	assert_eq(recipe.unlock_level, 2)
	assert_eq(recipe.section, RecipeDef.Section.SIDES)
	assert_eq(recipe.standard_price, 5)
	assert_eq(recipe.theme_tags, [&"bar"] as Array[StringName])
	assert_eq(recipe.ingredients.size(), 2)
	assert_eq(recipe.ingredients[0].id, &"frozen_fries")
	assert_eq(recipe.ingredients[1].id, &"oil")
	assert_eq(recipe.steps.size(), 1)
	assert_eq(recipe.steps[0].station_type, &"fryer")
	assert_eq(recipe.steps[0].duration_ticks, 24)
	assert_eq(content.recipe(&"fries").ingredients[0].id, &"potato")
	assert_eq(RecipeDef.validate_unlocks(content.recipes()), PackedStringArray())
	var menu: MenuSettings = MenuSettings.new([content.recipe(&"beer"), recipe] as Array[RecipeDef], 1)
	assert_false(menu.set_enabled(&"bar_fries", true))
	assert_true(menu.set_owner_level(2))
	assert_true(menu.set_enabled(&"bar_fries", true))


func test_station_target_follows_menu_use_and_preserves_saved_zero() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	assert_false(TUNING.morning_stock.has(&"frozen_fries"))
	assert_eq(settings.default_target(&"frozen_fries"), 12)
	assert_false(settings.ids().has(&"frozen_fries"))
	settings.set_in_use([&"frozen_fries"])
	assert_true(settings.ids().has(&"frozen_fries"))
	assert_true(settings.from_dict({"version": 1, "ingredients": {
		"frozen_fries": {"enabled": true, "target": 0}}}))
	assert_eq(settings.target(&"frozen_fries"), 0)
	var restored: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(settings.to_dict()))))
	assert_eq(restored.target(&"frozen_fries"), 0, "explicit old-save zero is a player choice")
	settings.set_in_use([])
	assert_false(settings.ids().has(&"frozen_fries"))
	assert_true(restored.copy().target(&"frozen_fries") == 0)
	var capacity: Dictionary[int, int] = {StorageSpace.FREEZER: 40}
	var kinds: Dictionary[StringName, int] = {&"frozen_fries": StorageSpace.FREEZER}
	var stock: Stock = Stock.new()
	restored.set_in_use([&"frozen_fries"])
	assert_eq(_quantity(restored.plan(stock, {&"frozen_fries": 1}, 100, 0.05, true,
		StorageSpace.new(capacity, stock, {}, kinds))), 0, "a saved zero never buys even with a freezer")


func test_missing_disabled_and_custom_frozen_targets_keep_player_intent() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(settings.from_dict({"version": 1, "ingredients": {}}))
	assert_eq(settings.target(&"frozen_fries"), 12, "a missing row inherits the new default")
	var stock: Stock = Stock.new()
	var capacity: Dictionary[int, int] = {StorageSpace.FREEZER: 40}
	var kinds: Dictionary[StringName, int] = {&"frozen_fries": StorageSpace.FREEZER}
	var room: StorageSpace = StorageSpace.new(capacity, stock, {}, kinds)
	for enabled: bool in [false, true]:
		assert_true(settings.from_dict({"version": 1, "ingredients": {
			"frozen_fries": {"enabled": enabled, "target": 7}}}))
		var restored: ReorderSettings = ReorderSettings.new(TUNING)
		assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(settings.to_dict()))))
		assert_eq(restored.target(&"frozen_fries"), 7)
		assert_eq(restored.is_enabled(&"frozen_fries"), enabled)
		restored.set_in_use([&"frozen_fries"])
		assert_eq(_quantity(restored.copy().plan(stock, {&"frozen_fries": 1}, 100, 0.05, true, room)),
			7 if enabled else 0)
		restored.set_in_use([])
		assert_eq(_quantity(restored.plan(stock, {&"frozen_fries": 1}, 100, 0.05, true, room)), 0)
		assert_eq(restored.target(&"frozen_fries"), 7)


func test_freezer_capacity_and_pending_orders_bound_the_plan_without_mutation() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	settings.set_in_use([&"frozen_fries"])
	var stock: Stock = Stock.new()
	var costs: Dictionary = {&"frozen_fries": 1}
	var kinds: Dictionary[StringName, int] = {&"frozen_fries": StorageSpace.FREEZER}
	var capacity: Dictionary[int, int] = {StorageSpace.FREEZER: 0}
	var absent: StorageSpace = StorageSpace.new(capacity, stock, {}, kinds)
	var blocked: Dictionary = settings.plan(stock, costs, 100, 0.05, true, absent)
	assert_eq(_quantity(blocked), 0)
	assert_eq(blocked["cost"], 0)
	assert_eq(blocked["unfit"].get(&"frozen_fries", 0), 12)
	capacity[StorageSpace.FREEZER] = 12
	var room: StorageSpace = StorageSpace.new(capacity, stock, {}, kinds)
	assert_eq(_quantity(settings.plan(stock, costs, 100, 0.05, true, room)), 12)
	var pending: Dictionary[StringName, int] = {&"frozen_fries": 5}
	room = StorageSpace.new(capacity, stock, pending, kinds)
	var before: Dictionary = settings.to_dict()
	assert_eq(_quantity(settings.plan(stock, costs, 100, 0.05, true, room)), 7)
	assert_eq(room.pending_of(&"frozen_fries"), 5)
	assert_eq(settings.to_dict(), before)
	assert_eq(stock.count(&"frozen_fries"), 0)
	kinds[&"another_frozen_food"] = StorageSpace.FREEZER
	stock.add(&"another_frozen_food", 4, 1)
	room = StorageSpace.new(capacity, stock, pending, kinds)
	assert_eq(_quantity(settings.plan(stock, costs, 100, 0.05, true, room)), 3,
		"other frozen goods and pending fries share the same freezer capacity")
	assert_true(stock.take(&"another_frozen_food", 4))
	stock.add(&"frozen_fries", 12, 1)
	room = StorageSpace.new(capacity, stock, {}, kinds)
	assert_eq(_quantity(settings.plan(stock, costs, 100, 0.05, true, room)), 0)


func _quantity(plan: Dictionary) -> int:
	for line: Dictionary in plan["lines"]:
		if line["id"] == &"frozen_fries":
			return int(line["qty"])
	return 0
