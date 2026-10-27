extends TestCase
## The evening report's Low stock facts and their player sentences (#54).

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func _lives() -> Dictionary:
	var lives: Dictionary = {}
	for ingredient: IngredientDef in _content.ingredients():
		lives[ingredient.id] = ingredient.shelf_life_days
	return lives


func _full_stock(day: int) -> Stock:
	var stock: Stock = Stock.new()
	for id: StringName in TUNING.morning_stock:
		stock.add(id, TUNING.morning_stock[id], day)
	return stock


func _costs() -> Dictionary:
	var costs: Dictionary = {}
	for ingredient: IngredientDef in _content.ingredients():
		costs[ingredient.id] = ingredient.unit_cost
	return costs


## Below tomorrow's target (after tonight's expiry) or expiring tomorrow.
func test_forecast_rows_include_shortfalls_and_expiry() -> void:
	var settings: ReorderSettings = ReorderSettings.new(TUNING)
	var stock: Stock = _full_stock(5)
	assert_true(stock.take(&"bread", 12))
	assert_true(settings.set_enabled(&"bread", false))
	assert_true(stock.take(&"tomato", 6))
	stock.add(&"lettuce", 3, 3)  # Lettuce keeps 3 days: bought day 3, gone on day 6.
	var before: Dictionary = stock.to_dict()
	var result: Dictionary = StockAlerts.forecast(stock, settings, _lives(), 6, _costs(), 1000, 0.1)
	assert_eq(stock.to_dict(), before, "the forecast never changes the real fridge")
	var rows: Array = result["rows"]
	assert_eq(rows.size(), 3, "full ingredients are not listed: %s" % [rows])
	assert_eq(rows[0]["id"], &"bread")
	assert_eq(rows[0]["usable"], 4)
	assert_eq(rows[0]["target"], 16)
	assert_false(rows[0]["enabled"])
	assert_eq(rows[0]["buys"], 0)
	assert_eq(rows[1]["id"], &"lettuce")
	assert_eq(rows[1]["expiring"], 3)
	assert_eq(rows[1]["usable"], 10, "expiring units do not count toward tomorrow")
	assert_eq(rows[2]["id"], &"tomato")
	assert_eq(rows[2]["buys"], 6)
	assert_eq(result["order_cost"], ReorderSettings.auto_cost(6, 0.1))
	# The day-5 beef patties (2-day shelf life) expire the morning after.
	var later: Array = StockAlerts.forecast(stock, settings, _lives(), 7, _costs(), 1000, 0.1)["rows"]
	var beef: Array = later.filter(func(row: Dictionary) -> bool: return row["id"] == &"beef_patty")
	assert_eq(beef.size(), 1)
	assert_eq(beef[0]["expiring"], 10)
	assert_eq(beef[0]["usable"], 0)
	assert_eq(beef[0]["buys"], 10)
	# With too little cash the shortfall is known tonight.
	var poor: Array = StockAlerts.forecast(stock, settings, _lives(), 6, _costs(), 3, 0.1)["rows"]
	assert_eq(poor[2]["short"], 4, "$3 buys two tomatoes with the premium")


func test_forecast_lines_list_only_what_needs_the_player() -> void:
	var data: Dictionary = {"order_cost": 31, "rows": [
		{"id": &"bread", "usable": 4, "target": 16, "expiring": 0, "enabled": true, "buys": 12, "short": 0},
		{"id": &"tomato", "usable": 2, "target": 16, "expiring": 3, "enabled": false, "buys": 0, "short": 0},
		{"id": &"cheese", "usable": 8, "target": 8, "expiring": 2, "enabled": true, "buys": 0, "short": 0},
		{"id": &"lettuce", "usable": 1, "target": 10, "expiring": 0, "enabled": true, "buys": 4, "short": 5},
	]}
	assert_eq(StockAlerts.forecast_lines(data, _content), [
		"Tomato: 3 expire tomorrow, 2 left, target 16. Auto-reorder is off.",
		"Cheese: 2 expire tomorrow. Auto-reorder replaces them.",
		"Lettuce: 1 left, target 10. Not enough cash to reorder 5.",
		"With tonight's cash, tomorrow morning's auto-order will cost $31.",
	] as Array[String], "a plain top-up (bread) is only part of the order cost")
	assert_true(StockAlerts.forecast_lines({"rows": [], "order_cost": 0}, _content).is_empty())


func test_sell_out_lines_name_the_ingredient_time_and_dishes() -> void:
	var events: Array[Dictionary] = [
		{"ingredient": &"tomato", "minute": 19 * 60 + 40,
			"dishes": [&"tomato_soup", &"tomato_melt"] as Array[StringName]},
		{"ingredient": &"beef_patty", "minute": 12 * 60 + 5, "dishes": [&"burger"] as Array[StringName]},
	]
	assert_eq(StockAlerts.sell_out_lines(events, _content), [
		"Tomato ran out at 19:40: Tomato soup and Tomato melt sold out",
		"Beef patty ran out at 12:05: Burger sold out",
	] as Array[String])
	assert_eq(StockAlerts.join_names(["A", "B", "C"] as Array[String]), "A, B and C")
	assert_eq(StockAlerts.join_names([] as Array[String]), "")


func test_report_low_stock_survives_a_snapshot() -> void:
	var report: DayReport = DayReport.new()
	report.low_stock = ["Tomato ran out at 19:40: Tomato soup sold out"] as Array[String]
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(report.to_dict())))
	assert_eq(restored.low_stock, report.low_stock)
	assert_true(DayReport.from_dict({}).low_stock.is_empty(), "older reports have no section")
