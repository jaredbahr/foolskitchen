extends TestCase
## One-day demand, menu mix and a small buffer guide automatic targets;
## explicit player choices and physical budget limits remain authoritative.

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func test_one_day_targets_grow_and_shrink_with_the_forecast_crowd() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"burger")] as Array[RecipeDef]
	var ordinary: Dictionary[StringName, int] = RestockForecast.targets(menu, 20, {}, 1.25)
	var busier: Dictionary[StringName, int] = RestockForecast.targets(menu, 40, {}, 1.25)
	var quieter: Dictionary[StringName, int] = RestockForecast.targets(menu, 10, {}, 1.25)
	assert_eq(ordinary, {&"bun": 25, &"beef_patty": 25, &"lettuce": 25} as Dictionary[StringName, int])
	assert_eq(busier[&"bun"], 50)
	assert_eq(quieter[&"bun"], 13)
	assert_false(ordinary.has(&"bread"), "disabled dishes do not create forecast ingredient needs")
	assert_eq(RestockForecast.targets(menu, 0, {}, 1.25)[&"bun"], 0)


func test_enabled_menu_mix_counts_repeated_recipe_ingredients() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"burger"), _content.recipe(&"grilled_cheese")] as Array[RecipeDef]
	var targets: Dictionary[StringName, int] = RestockForecast.targets(menu, 20, {}, 1.0)
	assert_eq(targets[&"bun"], 10)
	assert_eq(targets[&"beef_patty"], 10)
	assert_eq(targets[&"bread"], 20, "each grilled cheese uses two bread slices")
	assert_eq(targets[&"cheese"], 10)
	assert_false(targets.has(&"tomato"))
	menu = [_content.recipe(&"tomato_soup")] as Array[RecipeDef]
	targets = RestockForecast.targets(menu, 20, {}, 1.0)
	assert_eq(targets, {&"tomato": 40, &"soup_stock": 20} as Dictionary[StringName, int])


func test_visit_mix_and_meal_side_drink_are_both_counted() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"burger"), _content.recipe(&"coffee")] as Array[RecipeDef]
	var targets: Dictionary[StringName, int] = RestockForecast.targets(menu, 20,
		{RecipeDef.FOOD: 3.0, RecipeDef.COFFEE: 1.0}, 1.0, 0.2)
	assert_eq(targets[&"bun"], 15, "three quarters of visits order food")
	assert_eq(targets[&"coffee_beans"], 8, "five coffee visits plus three meal-side coffees")
	menu = [_content.recipe(&"coffee"), _content.recipe(&"croissant")] as Array[RecipeDef]
	targets = RestockForecast.targets(menu, 20,
		{RecipeDef.FOOD: 0.0, RecipeDef.COFFEE: 1.0}, 1.0, 0.0, 0.25)
	assert_eq(targets[&"coffee_beans"], 20)
	assert_eq(targets[&"pastry"], 5, "a pastry side adds stock use without adding another visit")


func test_manual_choices_survive_detached_forecasts_and_json() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(settings.set_target(&"bun", settings.default_target(&"bun")),
		"an explicit choice remains manual even when equal to the default")
	assert_true(settings.set_target(&"bread", 0))
	assert_true(settings.set_enabled(&"cheese", false))
	var saved: Dictionary = settings.to_dict()
	var targets: Dictionary[StringName, int] = {&"bun": 50, &"bread": 40, &"cheese": 30}
	var planned: ReorderSettings = settings.with_forecast(targets)
	assert_eq(settings.to_dict(), saved, "planning cannot overwrite the morning save model")
	assert_eq(planned.target(&"bun"), settings.default_target(&"bun"))
	assert_eq(planned.target(&"bread"), 0)
	assert_false(planned.is_enabled(&"cheese"))
	assert_eq(planned.target(&"cheese"), 30)
	assert_eq(planned.target(&"tomato"), 0, "untouched ingredients outside the menu stop being ordered")
	var restored: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(restored.with_forecast(targets).target(&"bun"), settings.default_target(&"bun"))
	assert_eq(restored.with_forecast(targets).target(&"bread"), 0)


func test_legacy_default_targets_adapt_while_legacy_custom_targets_stay_fixed() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	assert_true(settings.from_dict({"version": 1, "ingredients": {
		"bun": {"enabled": true, "target": settings.default_target(&"bun")},
		"bread": {"enabled": true, "target": 3}}}))
	var targets: Dictionary[StringName, int] = {&"bun": 40, &"bread": 30}
	assert_eq(settings.with_forecast(targets).target(&"bun"), 40)
	assert_eq(settings.with_forecast(targets).target(&"bread"), 3)
	var saved: Dictionary = settings.to_dict()
	var malformed: Dictionary = saved.duplicate(true)
	malformed["ingredients"]["bun"]["manual"] = 1
	assert_false(settings.from_dict(malformed))
	assert_eq(settings.to_dict(), saved, "invalid manual metadata rejects the candidate atomically")


func test_forecast_plan_still_respects_cash_storage_and_paid_pending_goods() -> void:
	var config: EconomyTuning = EconomyTuning.new()
	config.morning_stock = {&"bun": 1, &"beef_patty": 1, &"lettuce": 1} as Dictionary[StringName, int]
	var settings: ReorderSettings = ReorderSettings.new(config)
	settings = settings.with_forecast(RestockForecast.targets(
		[_content.recipe(&"burger")] as Array[RecipeDef], 20, {}, 1.25))
	var stock: Stock = Stock.new()
	stock.add(&"bun", 1, 1, 1)
	var space: StorageSpace = StorageSpace.new(
		{StorageSpace.DRY: 3, StorageSpace.FRIDGE: 4} as Dictionary[int, int], stock,
		{&"bun": 1} as Dictionary[StringName, int], StorageSpace.kinds_of(_content))
	var original: Dictionary = stock.to_dict()
	var rng: Dictionary = GameState._capture_save()
	var plan: Dictionary = settings.plan(stock, {&"bun": 1, &"beef_patty": 2, &"lettuce": 1}, 5, 0.0, false, space)
	assert_eq(plan["cost"], 5)
	assert_eq(plan["lines"], [{"id": &"bun", "qty": 1, "unit_cost": 1},
		{"id": &"beef_patty", "qty": 2, "unit_cost": 2}] as Array[Dictionary])
	assert_true((plan["unfit"] as Dictionary).has(&"bun"), "paid incoming units reserve their storage space")
	assert_true((plan["short"] as Dictionary).has(&"lettuce"))
	assert_eq(stock.to_dict(), original)
	assert_eq(GameState._capture_save(), rng, "forecast planning creates or advances no RNG stream")


func test_huge_forecasts_are_bounded_and_invalid_inputs_do_not_create_targets() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"burger")] as Array[RecipeDef]
	assert_eq(RestockForecast.targets(menu, 9223372036854775807, {}, 1.25)[&"bun"], ReorderSettings.MAX_TARGET)
	assert_eq(RestockForecast.targets(menu, -1, {}, 1.25), {} as Dictionary[StringName, int])
	assert_eq(RestockForecast.targets(menu, 20, {}, NAN), {} as Dictionary[StringName, int])
	assert_eq(RestockForecast.targets(menu, 20, {RecipeDef.FOOD: INF}, 1.25), {} as Dictionary[StringName, int])


func test_zero_hourly_weights_still_stock_the_real_fallback_visit_kind() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"coffee")] as Array[RecipeDef]
	var targets: Dictionary[StringName, int] = RestockForecast.targets(menu, 20,
		{RecipeDef.COFFEE: 0.0}, 1.0)
	assert_eq(targets[&"coffee_beans"], 20,
		"the positive arrival floor still brings guests when the sole visit kind has zero raw weight")
	menu = [_content.recipe(&"coffee"), _content.recipe(&"burger")] as Array[RecipeDef]
	targets = RestockForecast.targets(menu, 20,
		{RecipeDef.FOOD: 0.0, RecipeDef.COFFEE: 0.0}, 1.0)
	assert_eq(targets[&"bun"], 20, "zero-sum choice follows FOOD/COFFEE/DRINKS order, independent of recipe order")
	assert_eq(targets[&"coffee_beans"], 0)
	var restaurant: RestaurantSim = RestaurantSim.new()
	restaurant.world = SimWorld.new(SimGrid.new())
	restaurant.visit_tuning = null
	restaurant.menu = menu
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 7
	var rng_before: int = random.state
	assert_eq(CustomerSpawner.choose_visit(restaurant.visit_kinds(), null, restaurant, random), RecipeDef.FOOD,
		"the production chooser falls back to the first available kind when visit tuning is absent")
	assert_eq(random.state, rng_before, "the zero-weight fallback draws no kind ticket")
	targets = RestockForecast.targets(menu, 20, restaurant.expected_visit_weights(), 1.0)
	assert_eq(targets[&"bun"], 20)
	assert_eq(targets[&"coffee_beans"], 0, "the forecast follows the same real null-tuning fallback")


func test_hour_weights_integrate_partial_hours_and_empty_service_windows() -> void:
	var tuning: VisitTuning = VisitTuning.new()
	for kind: StringName in RecipeDef.ORDER_TYPES:
		var hours: PackedFloat32Array = PackedFloat32Array()
		hours.resize(24)
		hours.fill(0.0)
		tuning.hourly_weights[kind] = hours
	tuning.hourly_weights[RecipeDef.FOOD][10] = 1.0
	tuning.hourly_weights[RecipeDef.FOOD][11] = 3.0
	tuning.hourly_weights[RecipeDef.FOOD][12] = 2.0
	tuning.hourly_weights[RecipeDef.COFFEE][10] = 4.0
	tuning.hourly_weights[RecipeDef.COFFEE][11] = 0.5
	tuning.hourly_weights[RecipeDef.COFFEE][12] = 1.0
	tuning.hourly_weights[RecipeDef.DRINKS][11] = 2.0
	tuning.hourly_weights[RecipeDef.DRINKS][12] = 4.0
	assert_eq(_hour_weights(tuning, 10 * 60 + 30, 12 * 60 + 15),
		{RecipeDef.FOOD: 240.0, RecipeDef.COFFEE: 165.0, RecipeDef.DRINKS: 180.0} as Dictionary[StringName, float])
	var empty: Dictionary[StringName, float] = {
		RecipeDef.FOOD: 0.0, RecipeDef.COFFEE: 0.0, RecipeDef.DRINKS: 0.0}
	assert_eq(_hour_weights(tuning, 720, 720), empty)
	assert_eq(_hour_weights(tuning, 780, 720), empty)


func test_actual_visit_hours_are_read_only_and_match_authored_day_weights() -> void:
	var tuning: VisitTuning = load("res://data/balance/visits.tres") as VisitTuning
	var before: Dictionary[StringName, PackedFloat32Array] = tuning.hourly_weights.duplicate(true)
	var rng: Dictionary = GameState._capture_save()
	var weights: Dictionary[StringName, float] = _hour_weights(tuning, 11 * 60, 21 * 60)
	assert_almost_eq(weights[RecipeDef.FOOD], 600.0)
	assert_almost_eq(weights[RecipeDef.COFFEE], 141.0)
	assert_almost_eq(weights[RecipeDef.DRINKS], 219.0)
	assert_eq(tuning.hourly_weights, before)
	assert_eq(GameState._capture_save(), rng)
	assert_eq(_hour_weights(null, 630, 735),
		{RecipeDef.FOOD: 0.0, RecipeDef.COFFEE: 0.0, RecipeDef.DRINKS: 0.0} as Dictionary[StringName, float],
		"null visit tuning preserves the production chooser's zero raw weights")


func _hour_weights(tuning: VisitTuning, open_minute: int, close_minute: int) -> Dictionary[StringName, float]:
	var restaurant: RestaurantSim = RestaurantSim.new()
	restaurant.world = SimWorld.new(SimGrid.new())
	restaurant.visit_tuning = tuning
	restaurant.world.clock.display_open_minute = open_minute
	restaurant.world.clock.display_close_minute = close_minute
	return restaurant.expected_visit_weights()


func test_starting_menu_forecast_covers_whole_buffered_recipe_portions() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"burger"), _content.recipe(&"grilled_cheese"),
		_content.recipe(&"tomato_soup")] as Array[RecipeDef]
	var targets: Dictionary[StringName, int] = RestockForecast.targets(menu, 20, {}, 1.10)
	# ceil(20 / 3 * 1.10) = 8 portions per recipe. Fifteen bread slices
	# would cover only seven complete sandwiches despite buying eight cheese.
	assert_eq(targets[&"bread"], 16, "eight whole grilled cheese portions need two bread slices each")
	assert_eq(targets[&"cheese"], 8)
	assert_eq(targets[&"bun"], 8)
	assert_eq(targets[&"beef_patty"], 8)
	assert_eq(targets[&"lettuce"], 8)
	assert_eq(targets[&"tomato"], 16, "eight whole soup portions need two tomatoes each")
	assert_eq(targets[&"soup_stock"], 8)


func test_primary_and_side_coffee_combine_before_buffered_portion_rounding() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"burger"), _content.recipe(&"coffee")] as Array[RecipeDef]
	var targets: Dictionary[StringName, int] = RestockForecast.targets(menu, 4,
		{RecipeDef.FOOD: 1.0, RecipeDef.COFFEE: 1.0}, 1.10, 0.1)
	# Two coffee visits plus 0.2 meal-side coffees: ceil(2.2 * 1.10) = 3.
	# Rounding each source separately would incorrectly buy 3 + 1 = 4.
	assert_eq(targets[&"coffee_beans"], 3, "the same coffee recipe combines primary and side portions")
	assert_eq(targets[&"bun"], 3)


func test_primary_and_side_pastry_combine_before_buffered_portion_rounding() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"croissant"), _content.recipe(&"coffee")] as Array[RecipeDef]
	var targets: Dictionary[StringName, int] = RestockForecast.targets(menu, 4,
		{RecipeDef.FOOD: 1.0, RecipeDef.COFFEE: 1.0}, 1.10, 0.0, 0.1)
	# Two food visits plus 0.2 coffee-side pastries also need three whole
	# portions, rather than four from separately rounding the two sources.
	assert_eq(targets[&"pastry"], 3, "the same pastry recipe combines primary and side portions")
	assert_eq(targets[&"coffee_beans"], 3)


func test_whole_portion_rounding_bounds_huge_repeated_ingredients_and_keeps_zero() -> void:
	var menu: Array[RecipeDef] = [_content.recipe(&"grilled_cheese"),
		_content.recipe(&"tomato_soup"), _content.recipe(&"tomato_melt")] as Array[RecipeDef]
	# Tomato melt also shares bread, cheese and tomato with the other recipes.
	var huge: Dictionary[StringName, int] = RestockForecast.targets(menu, 9223372036854775807, {}, 2.0)
	assert_eq(huge, {&"bread": 99, &"cheese": 99, &"tomato": 99,
		&"soup_stock": 99} as Dictionary[StringName, int], "bound whole portions before integer conversion")
	assert_eq(RestockForecast.targets(menu, 0, {}, 1.10),
		{&"bread": 0, &"cheese": 0, &"tomato": 0, &"soup_stock": 0} as Dictionary[StringName, int])
