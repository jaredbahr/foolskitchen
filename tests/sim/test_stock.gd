extends TestCase
## FIFO stock, atomic recipe consumption, expiry boundaries and snapshots.


## Ingredient counts combine batches without mixing separate ids.
func test_add_count_and_has_across_ingredients() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 2, 1)
	stock.add(&"bun", 3, 2)
	stock.add(&"cheese", 4, 1)
	assert_eq(stock.count(&"bun"), 5)
	assert_eq(stock.count(&"cheese"), 4)
	assert_eq(stock.count(&"missing"), 0)
	assert_true(stock.has(&"bun", 5))
	assert_false(stock.has(&"bun", 6))


## Invalid additions cannot introduce empty ids, negative stock or overflow.
func test_invalid_additions_and_nonnegative_needs() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"", 3, 1)
	stock.add(&"bun", -1, 1)
	stock.add(&"bun", 0, 1)
	assert_eq(stock.count(&"bun"), 0)
	assert_eq(stock.count(&""), 0)
	assert_true(stock.has(&"missing", 0))
	assert_false(stock.has(&"missing", -1))
	assert_false(stock.take(&"missing", -1))
	assert_true(stock.take(&"missing", 0))
	stock.add(&"bun", Stock.MAX_QUANTITY, 1)
	stock.add(&"bun", 1, 2)
	assert_eq(stock.count(&"bun"), Stock.MAX_QUANTITY)


## Taking across batches removes the oldest units before newer ones.
func test_take_consumes_fifo_and_keeps_remaining_batch_date() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 2, 1)
	stock.add(&"bun", 3, 2)
	assert_true(stock.take(&"bun", 3))
	assert_eq(stock.count(&"bun"), 2)
	assert_eq(stock.to_dict()["batches"]["bun"], [{"qty": 2, "bought_day": 2}])


## Inserting an older dated batch still keeps FIFO in purchase-day order.
func test_out_of_order_addition_is_consumed_oldest_first() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 3, 3)
	stock.add(&"bun", 2, 1)
	assert_true(stock.take(&"bun", 2))
	assert_eq(stock.to_dict()["batches"]["bun"], [{"qty": 3, "bought_day": 3}])


## A short single-ingredient take cannot partially consume its batches.
func test_take_is_all_or_nothing() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 2, 1)
	var before: Dictionary = stock.to_dict()
	assert_false(stock.take(&"bun", 3))
	assert_eq(stock.to_dict(), before)
	assert_true(stock.take(&"bun", 2))
	assert_eq(stock.count(&"bun"), 0)
	assert_false(stock.to_dict()["batches"].has("bun"))


## One recipe can consume multiple ids only when all are available.
func test_take_many_consumes_all_ids_together() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bread", 4, 1)
	stock.add(&"cheese", 2, 1)
	assert_true(stock.take_many({&"bread": 2, &"cheese": 1}))
	assert_eq(stock.count(&"bread"), 2)
	assert_eq(stock.count(&"cheese"), 1)
	assert_true(stock.take_many({}))


## A shortage on any id leaves every other ingredient untouched.
func test_take_many_shortage_leaves_all_batches_unchanged() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bread", 4, 1)
	stock.add(&"cheese", 1, 1)
	var before: Dictionary = stock.to_dict()
	assert_false(stock.take_many({&"bread": 2, &"cheese": 2}))
	assert_eq(stock.to_dict(), before)
	assert_false(stock.take_many({&"bread": 1, &"missing": 1}))
	assert_eq(stock.to_dict(), before)


## Malformed requirements fail through a return value without taking stock.
func test_take_many_rejects_negative_fractional_or_invalid_ids() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bread", 4, 1)
	var before: Dictionary = stock.to_dict()
	assert_false(stock.take_many({&"bread": -1}))
	assert_false(stock.take_many({&"bread": 1.5}))
	assert_false(stock.take_many({1: 1}))
	assert_eq(stock.to_dict(), before)


## A day-d batch with life n expires at d+n, after its final usable day.
func test_expiry_boundary_day_is_exact() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 2, 4)
	assert_eq(stock.expire(6, {&"bun": 3}), {})
	assert_eq(stock.count(&"bun"), 2)
	assert_eq(stock.expire(7, {&"bun": 3}), {&"bun": 2})
	assert_eq(stock.count(&"bun"), 0)


## Expiry removes only old batches and never removes unspecified ids.
func test_expiry_keeps_new_batches_and_unspecified_ingredients() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 2, 1)
	stock.add(&"bun", 3, 3)
	stock.add(&"bread", 5, 1)
	assert_eq(stock.expire(4, {"bun": 3}), {&"bun": 2})
	assert_eq(stock.count(&"bun"), 3)
	assert_eq(stock.count(&"bread"), 5)
	assert_eq(stock.expire(100, {}), {})
	assert_eq(stock.count(&"bread"), 5)


## Zero-day shelf life expires on purchase day, but not before purchase.
func test_zero_day_shelf_life_and_future_batch() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 2, 5)
	assert_eq(stock.expire(4, {&"bun": 0}), {})
	assert_eq(stock.expire(5, {&"bun": 0}), {&"bun": 2})


## FIFO consumption and expiry cooperate without moving the surviving dates.
func test_expiry_after_partial_fifo_take() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 3, 1)
	stock.add(&"bun", 4, 2)
	stock.take(&"bun", 2)
	assert_eq(stock.expire(3, {&"bun": 2}), {&"bun": 1})
	assert_eq(stock.count(&"bun"), 4)


## JSON round trips retain dates and isolate both the restored and source stock.
func test_json_round_trip_and_snapshot_ownership() -> void:
	var stock: Stock = Stock.new()
	stock.add(&"bun", 2, 1)
	stock.add(&"bun", 3, 2)
	stock.add(&"cheese", 4, 3)
	var snapshot: Dictionary = stock.to_dict()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	var restored: Stock = Stock.from_dict(decoded)
	assert_eq(restored.to_dict(), snapshot)
	decoded["batches"]["bun"][0]["qty"] = 999
	assert_eq(restored.count(&"bun"), 5)
	assert_true(restored.take(&"bun", 3))
	assert_eq(restored.count(&"bun"), 2)
	assert_eq(stock.count(&"bun"), 5)
	assert_eq(restored.expire(4, {&"bun": 2}), {&"bun": 2})
	assert_eq(stock.count(&"bun"), 5)


## An empty snapshot produces an empty stock model.
func test_empty_snapshot_has_no_batches() -> void:
	var stock: Stock = Stock.from_dict({})
	assert_eq(stock.to_dict(), {"batches": {}})
	assert_eq(stock.count(&"bun"), 0)
