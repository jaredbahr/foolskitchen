extends TestCase
## Explain the same arithmetic used by the kitchen without changing its defaults.


func test_food_breakdown_sums_in_order_and_is_detached() -> void:
	var recipe: RecipeDef = RecipeDef.new()
	recipe.base_quality = 0.5
	var cook: StaffAgent = StaffAgent.new(&"cook", 3)
	cook.cook_quality_bonus = 0.05
	var station: ItemDef = ItemDef.new()
	station.display_name = "Stove"
	station.quality_bonus = 0.1
	var result: DishQuality = DishQuality.breakdown(recipe, cook, [station] as Array[ItemDef])
	assert_almost_eq(result.quality, 0.65)
	assert_almost_eq(result.recipe_base * result.skill_factor + result.trait_bonus
		+ result.station_bonuses[0], result.unclamped)
	assert_true(result.explanation().contains("Stove +0.10"))
	cook.cook_quality_bonus = 0.0
	station.quality_bonus = 0.0
	assert_almost_eq(result.quality, 0.65)
	assert_almost_eq(result.station_bonuses[0], 0.1)


func test_clamping_and_data_weights_preserve_legacy_formula_for_all_skills() -> void:
	var tuning: MenuTuning = load("res://data/balance/menu.tres") as MenuTuning
	assert_true(tuning.is_valid())
	assert_almost_eq(tuning.quality_skill_base, 0.7)
	assert_almost_eq(tuning.quality_per_skill, 0.1)
	var recipe: RecipeDef = RecipeDef.new()
	recipe.base_quality = 0.9
	for skill: int in range(1, 6):
		var cook: StaffAgent = StaffAgent.new(&"cook", skill)
		cook.cook_quality_bonus = 0.05
		var result: DishQuality = DishQuality.breakdown(recipe, cook, [])
		assert_almost_eq(result.quality, clampf(0.9 * (0.7 + 0.1 * skill) + 0.05, 0.0, 1.0))
	var limited: DishQuality = DishQuality.breakdown(recipe, StaffAgent.new(&"cook", 5), [])
	assert_almost_eq(limited.quality, 1.0)
	assert_true(limited.explanation().contains("limited to"))
	tuning = tuning.duplicate() as MenuTuning
	tuning.quality_per_skill = -0.1
	assert_false(tuning.is_valid())


func test_drink_uses_service_skill_and_keeps_cooking_trait_out() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var worker: StaffAgent = StaffAgent.new(&"server", 2)
	worker.skills[&"cook"] = 5
	worker.cook_quality_bonus = 0.2
	var station: ItemDef = content.item(&"coffee_machine")
	var recipe: RecipeDef = content.recipe(&"coffee")
	var result: DishQuality = DishQuality.breakdown(recipe, worker, [station] as Array[ItemDef])
	assert_almost_eq(result.quality, clampf(recipe.base_quality * 0.9 + station.quality_bonus, 0.0, 1.0))
	assert_almost_eq(result.trait_bonus, 0.0)
	assert_true(result.explanation().contains("server skill 2"))


func test_report_averages_only_delivered_orders_including_drinks_and_round_trips() -> void:
	var food: Order = Order.new()
	food.state = Order.State.DELIVERED
	food.quality = 0.6
	var drink: Order = Order.new()
	drink.state = Order.State.DELIVERED
	drink.quality = 0.8
	var cancelled: Order = Order.new()
	cancelled.state = Order.State.CANCELLED
	cancelled.quality = 1.0
	var report: DayReport = DayReport.new()
	report.record_dish_quality([food, drink, cancelled] as Array[Order])
	assert_eq(report.dish_quality_count, 2)
	assert_almost_eq(report.dish_quality_average, 0.7)
	assert_eq(report.food_quality_text(), "Food quality: good (3.5 / 5)")
	assert_eq(DayReport.from_dict(report.to_dict()).food_quality_text(), report.food_quality_text())
	report.record_dish_quality([])
	assert_eq(report.food_quality_text(), "Food quality: no dishes served")
	assert_eq(DayReport.from_dict({}).food_quality_text(), report.food_quality_text())
