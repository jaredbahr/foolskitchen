extends TestCase
## Purchase-value conservation through FIFO use, spoilage and legacy saves.

const MAX_VALUE: int = 9223372036854775807


func test_partial_fifo_use_and_spoilage_conserve_actual_purchase_value() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"rice", 2, 2, 14)
	stock.add(&"rice", 3, 1, 10)
	assert_eq(stock.value(), {"cost": 24, "recorded": true})
	var consumed: Dictionary = stock.take_many_valued({&"rice": 2})
	assert_eq(consumed, {"taken": true, "cost": 7, "recorded": true})
	assert_eq(stock.count(&"rice"), 3)
	assert_eq(stock.value(), {"cost": 17, "recorded": true})
	var spoiled: Dictionary = stock.expire_valued(3, {&"rice": 2})
	assert_eq(spoiled, {"quantities": {&"rice": 1}, "cost": 3, "recorded": true})
	assert_eq(stock.value(), {"cost": 14, "recorded": true})
	assert_eq(int(consumed["cost"]) + int(spoiled["cost"]) + int(stock.value()["cost"]), 24)
	assert_eq(stock.spoilage_value(3), {"cost": 3, "recorded": true})
	assert_eq(stock.expire_valued(3, {&"rice": 2})["quantities"], {})
	assert_eq(stock.spoilage_value(3), {"cost": 3, "recorded": true}, "repeated expiry cannot erase its day's loss")


func test_partial_lot_save_preserves_original_remainder_without_repricing() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"rice", 5, 1, 13)
	assert_eq(stock.take_many_valued({&"rice": 2})["cost"], 6)
	var snapshot: Dictionary = stock.to_dict()
	var restored: Stock = Stock.from_dict(JSON.parse_string(JSON.stringify(snapshot)))
	assert_not_null(restored)
	assert_eq(restored.value(), {"cost": 7, "recorded": true})
	assert_eq(restored.take_many_valued({&"rice": 1})["cost"], 3)
	assert_eq(restored.take_many_valued({&"rice": 2})["cost"], 4)
	assert_eq(restored.value(), {"cost": 0, "recorded": true})
	assert_eq(stock.value(), {"cost": 7, "recorded": true}, "restoring and taking never edits the source")


func test_short_or_malformed_multi_take_preserves_quantities_and_value() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"rice", 3, 1, 10)
	stock.add(&"cheese", 1, 1, 7)
	var before: Dictionary = stock.to_dict()
	for needs: Dictionary in [{&"rice": 2, &"cheese": 2}, {&"rice": 1, &"missing": 1},
			{&"rice": -1}, {&"rice": 1.5}, {false: 1}]:
		assert_false(stock.take_many_valued(needs)["taken"])
		assert_eq(stock.to_dict(), before, "failed atomic take preserves batch values as well as stock")
	assert_eq(stock.take_many_valued({&"rice": 1, &"cheese": 1}),
		{"taken": true, "cost": 11, "recorded": true})
	assert_eq(stock.value(), {"cost": 6, "recorded": true})


func test_legacy_unknown_cost_is_distinct_from_known_free_stock() -> void:
	var stock: Stock = Stock.from_dict({"batches": {"rice": [{"qty": "1", "bought_day": "1"}]}})
	stock.add(&"rice", 2, 2, 6)
	assert_false(stock.value()["recorded"], "current list prices cannot reconstruct historical costs")
	var unknown: Dictionary = stock.take_many_valued({&"rice": 1})
	assert_true(unknown["taken"], "unknown prices cannot block ordinary cooking")
	assert_false(unknown["recorded"])
	assert_eq(stock.value(), {"cost": 6, "recorded": true}, "newer known lots become exact once legacy stock is gone")
	stock.add(&"free", 3, 2, 0)
	assert_eq(stock.take_many_valued({&"free": 3}), {"taken": true, "cost": 0, "recorded": true})


func test_aggregate_value_overflow_does_not_block_physical_consumption() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"rice", 1, 1, MAX_VALUE)
	stock.add(&"cheese", 1, 1, 1)
	assert_false(stock.value()["recorded"], "an unrepresentable total is unavailable rather than negative")
	var consumed: Dictionary = stock.take_many_valued({&"rice": 1, &"cheese": 1})
	assert_true(consumed["taken"])
	assert_false(consumed["recorded"])
	assert_eq(stock.count(&"rice"), 0)
	assert_eq(stock.count(&"cheese"), 0)
	assert_eq(stock.value(), {"cost": 0, "recorded": true})
	stock.add(&"rice", 1, 2, MAX_VALUE)
	stock.add(&"cheese", 1, 2, 1)
	assert_eq(stock.take_many_valued({&"rice": 1}), {"taken": true, "cost": MAX_VALUE, "recorded": true})
	assert_eq(stock.value(), {"cost": 1, "recorded": true})


func test_json_preserves_purchase_values_beyond_double_precision() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"rice", 3, 1, 9007199254740993)
	var restored: Stock = Stock.from_dict(JSON.parse_string(JSON.stringify(stock.to_dict())))
	assert_eq(restored.value(), {"cost": 9007199254740993, "recorded": true})
	assert_eq(restored.take_many_valued({&"rice": 1})["cost"], 3002399751580331)
	assert_eq(restored.value(), {"cost": 6004799503160662, "recorded": true})
	var maximum: Stock = Stock.new()
	maximum.add(&"rice", 4, 1, MAX_VALUE)
	assert_eq(maximum.take_many_valued({&"rice": 1})["cost"], 2305843009213693952)
	assert_eq(maximum.value(), {"cost": 6917529027641081855, "recorded": true})


func test_exact_charged_premium_is_conserved_across_lines_and_units() -> void:
	var lines: Array[Dictionary] = [{"id": &"rice", "qty": 3, "unit_cost": 2},
		{"id": &"free", "qty": 2, "unit_cost": 0}, {"id": &"cheese", "qty": 1, "unit_cost": 4}]
	var original: Array[Dictionary] = lines.duplicate(true)
	var lots: Array[Dictionary] = PurchaseBasis.allocate(lines, 15)
	assert_eq(lots, [{"id": &"rice", "qty": 3, "total_cost": 8},
		{"id": &"free", "qty": 2, "total_cost": 2}, {"id": &"cheese", "qty": 1, "total_cost": 5}] as Array[Dictionary])
	assert_eq(lines, original, "allocation cannot edit the paid order's lines")
	var stock: Stock = Stock.new()
	for lot: Dictionary in lots:
		stock.add(lot["id"], lot["qty"], 1, lot["total_cost"])
	assert_eq(stock.take_many_valued({&"rice": 1, &"free": 1, &"cheese": 1})["cost"], 9)
	assert_eq(stock.value(), {"cost": 6, "recorded": true})


func test_quantity_only_delivery_lines_keep_their_unknown_history() -> void:
	var lots: Array[Dictionary] = PurchaseBasis.allocate([{"id": &"rice", "qty": 3}] as Array[Dictionary])
	assert_false(lots[0].has("total_cost"))
	var explicit: Array[Dictionary] = PurchaseBasis.allocate(
		[{"id": &"rice", "qty": 3, "total_cost": 10}] as Array[Dictionary])
	assert_eq(explicit[0]["total_cost"], 10)
	var impossible: Array[Dictionary] = PurchaseBasis.allocate(
		[{"id": &"rice", "qty": 2, "unit_cost": 5}] as Array[Dictionary], 9)
	assert_false(impossible[0].has("total_cost"), "an inconsistent historical charge is never invented")


func test_malformed_optional_costs_cannot_install_a_partially_decoded_stock() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"rice", 3, 1, 10)
	var original: Dictionary = stock.to_dict()
	for malformed: Variant in [-1, 1.5, true, "-1", "NaN", "9223372036854775808", {}, null]:
		var bad: Dictionary = original.duplicate(true)
		bad["batches"]["rice"][0]["total_cost"] = malformed
		assert_null(Stock.from_dict(bad), "a present malformed price rejects the candidate")
	assert_eq(stock.to_dict(), original)
	var restored: Stock = Stock.from_dict(original)
	original["batches"]["rice"][0]["total_cost"] = "999"
	assert_eq(restored.value(), {"cost": 10, "recorded": true}, "decoded costs are detached")


func test_same_morning_reload_retains_spoilage_without_charging_it_twice() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"rice", 3, 1, 10)
	stock.add(&"rice", 2, 3, 14)
	stock.expire_valued(3, {&"rice": 2})
	var saved: Dictionary = stock.to_dict()
	var restored: Stock = Stock.from_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_eq(restored.spoilage_value(3), {"cost": 10, "recorded": true})
	assert_eq(restored.expire_valued(3, {&"rice": 2}),
		{"quantities": {}, "cost": 0, "recorded": true})
	assert_eq(restored.spoilage_value(3), {"cost": 10, "recorded": true})
	assert_eq(restored.value(), {"cost": 14, "recorded": true})
	assert_eq(restored.spoilage_value(4), {"cost": 0, "recorded": true})
	for malformed: Variant in [true, -1, "9223372036854775808", 1.5]:
		var bad: Dictionary = saved.duplicate(true)
		bad["spoilage"]["cost"] = malformed
		assert_null(Stock.from_dict(bad))
	var bad_flag: Dictionary = saved.duplicate(true)
	bad_flag["spoilage"]["recorded"] = 1
	assert_null(Stock.from_dict(bad_flag))
