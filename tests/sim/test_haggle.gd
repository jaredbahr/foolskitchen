extends TestCase
## Whole-dollar pricing, seeded zones and purchase-basis conservation.

const TERMS: HaggleTuning = preload("res://data/balance/haggle.tres")
const ECONOMY: GDScript = preload("res://src/core/economy.gd")
const MAX_VALUE: int = 9223372036854775807
var _adapter: Node
var _old_clock: SimClock


func before_each() -> void:
	_old_clock = Clock.sim
	Clock.sim = SimClock.new()
	_adapter = ECONOMY.new()
	_adapter.call("reset", 100)


func after_each() -> void:
	_adapter.free()
	Clock.sim = _old_clock


func test_result_mapping_rounds_and_clamps_whole_percentages() -> void:
	for pair: Array in [[0.0, 0], [0.5, 5], [1.0, 10], [-2.0, 0], [2.0, 10], [0.56, 6]]:
		assert_eq(HaggleRules.discount_percent(float(pair[0]), TERMS.max_discount), int(pair[1]))
	assert_eq(HaggleRules.discount_percent(NAN, 0.1), 0)
	assert_eq(HaggleRules.discount_percent(1.0, INF), 0)
	assert_eq(HaggleRules.discount_percent(1.0, -1.0), 0)
	assert_eq(HaggleRules.discount_percent(1.0, 0.105), 10, "whole percent cannot exceed the data cap")
	assert_eq(HaggleRules.discount_percent(1.0, 0.29), 29)


func test_same_seed_places_same_three_zones_with_no_extra_draws() -> void:
	var first: RandomNumberGenerator = RandomNumberGenerator.new()
	var second: RandomNumberGenerator = RandomNumberGenerator.new()
	first.seed = 327
	second.seed = 327
	var centers: Array[float] = HaggleRules.zone_centers(TERMS, first)
	assert_eq(centers.size(), 3)
	assert_eq(centers, HaggleRules.zone_centers(TERMS, second))
	assert_eq(first.state, second.state)
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = 327
	for index: int in TERMS.rounds:
		expected.randf()
		assert_true(centers[index] >= TERMS.zone_widths[index] * 0.5)
		assert_true(centers[index] <= 1.0 - TERMS.zone_widths[index] * 0.5)
	assert_eq(first.state, expected.state, "exactly one draw per round")
	assert_almost_eq(HaggleRules.score(0.5, 0.5, 0.2), 1.0)
	assert_almost_eq(HaggleRules.score(0.55, 0.5, 0.2), 0.5)
	assert_almost_eq(HaggleRules.score(0.7, 0.5, 0.2), 0.0)
	assert_true(HaggleRules.score(0.55, 0.5, 0.4) > HaggleRules.score(0.55, 0.5, 0.2))
	assert_true(TERMS.zone_widths[0] > TERMS.zone_widths[1] and TERMS.zone_widths[1] > TERMS.zone_widths[2])
	assert_true(TERMS.speeds[0] < TERMS.speeds[1] and TERMS.speeds[1] < TERMS.speeds[2])


func test_one_rounded_order_allocates_nonnegative_actual_lot_costs() -> void:
	var lines: Array[Dictionary] = [{"id": &"bread", "qty": 5, "unit_cost": 1},
		{"id": &"free", "qty": 4, "unit_cost": 0}, {"id": &"rice", "qty": 4, "unit_cost": 3}]
	var before: Array[Dictionary] = lines.duplicate(true)
	var quote: Dictionary = HaggleRules.quote(lines, 6)
	assert_eq(quote["cost"], 16)
	assert_eq(quote["saved"], 1)
	assert_eq(quote["lines"], [{"id": &"bread", "qty": 5, "total_cost": 5},
		{"id": &"free", "qty": 4, "total_cost": 0}, {"id": &"rice", "qty": 4, "total_cost": 11}] as Array[Dictionary])
	assert_eq(lines, before)
	assert_eq(HaggleRules.charge(1, 10), 1, "small orders never accidentally become free")
	for percent: int in [0, 1, 6, 10, 100]:
		var allocated: Dictionary = HaggleRules.quote(lines, percent)
		var total: int = 0
		for index: int in lines.size():
			var cost: int = int(allocated["lines"][index]["total_cost"])
			assert_true(cost >= 0 and cost <= int(lines[index]["qty"]) * int(lines[index]["unit_cost"]))
			total += cost
		assert_eq(total, HaggleRules.charge(17, percent))


func test_int64_quotes_are_exact_and_overflow_refuses_before_purchase() -> void:
	assert_eq(HaggleRules.charge(MAX_VALUE, 0), MAX_VALUE)
	assert_eq(HaggleRules.charge(MAX_VALUE, 10), 8301034833169298227)
	assert_eq(HaggleRules.charge(MAX_VALUE, 100), 0)
	assert_eq(HaggleRules.charge(9007199254740993, 6), 8466767299456534)
	var overflow: Array[Dictionary] = [{"id": &"rice", "qty": 1, "unit_cost": MAX_VALUE},
		{"id": &"bread", "qty": 1, "unit_cost": 1}]
	assert_eq(HaggleRules.quote(overflow, 10), {})
	assert_false(_adapter.call("buy_haggled_order", overflow, 10))
	assert_eq((_adapter.get("ledger") as Ledger).entries_for_day(1), [])
	assert_eq((_adapter.get("stock") as Stock).value(), PurchaseBasis.zero())
	for bad: Array in [[], [{"id": &"rice", "qty": 1, "unit_cost": -1}],
			[{"id": &"rice", "qty": 0, "unit_cost": 1}], [{"id": false, "qty": 1, "unit_cost": 1}]]:
		var candidate: Array[Dictionary] = []
		candidate.assign(bad)
		assert_eq(HaggleRules.quote(candidate, 10), {})


func test_actual_charge_and_valued_stock_reconcile_through_fifo_expiry_and_json() -> void:
	var lines: Array[Dictionary] = [{"id": &"rice", "qty": 5, "unit_cost": 3},
		{"id": &"free", "qty": 2, "unit_cost": 0}, {"id": &"bread", "qty": 5, "unit_cost": 1}]
	assert_true(_adapter.call("buy_haggled_order", lines, 10))
	var ledger: Ledger = _adapter.get("ledger")
	assert_eq(ledger.cash, 82)
	assert_eq(ledger.day_income(1), 0, "a saving is not fake income")
	assert_eq(ledger.day_costs(1), 18)
	var stock: Stock = _adapter.get("stock")
	assert_eq(stock.value(), {"cost": 18, "recorded": true})
	var used: Dictionary = stock.take_many_valued({&"rice": 2, &"free": 1})
	assert_true(used["recorded"])
	var restored: Stock = Stock.from_dict(JSON.parse_string(JSON.stringify(stock.to_dict())))
	var expired: Dictionary = restored.expire_valued(3, {&"rice": 2})
	assert_eq(int(used["cost"]) + int(expired["cost"]) + int(restored.value()["cost"]), 18)
	assert_true(restored.value()["recorded"])
	# The existing allocator's inconsistent-history and premium contracts stay intact.
	assert_false(PurchaseBasis.allocate(lines, 18)[0].has("total_cost"))
	assert_eq(PurchaseBasis.allocate(lines, 23)[0]["total_cost"], 16)


func test_failed_payment_quantity_and_wrong_phase_are_atomic() -> void:
	var lines: Array[Dictionary] = [{"id": &"rice", "qty": 5, "unit_cost": 30}]
	assert_false(_adapter.call("buy_haggled_order", lines, 10))
	var stock: Stock = _adapter.get("stock")
	stock.add(&"rice", MAX_VALUE, 1, 0)
	assert_false(_adapter.call("buy_haggled_order", [{"id": &"rice", "qty": 1, "unit_cost": 1}] as Array[Dictionary], 10))
	Clock.sim.phase = SimClock.Phase.OPEN
	assert_false(_adapter.call("buy_haggled_order", [{"id": &"bread", "qty": 1, "unit_cost": 1}] as Array[Dictionary], 10))
	assert_eq((_adapter.get("ledger") as Ledger).cash, 100)
	assert_eq((_adapter.get("ledger") as Ledger).entries_for_day(1), [])
	assert_eq(stock.count(&"rice"), MAX_VALUE)
