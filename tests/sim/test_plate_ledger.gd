extends TestCase
## Pure plate conservation, per-order ownership, replay safety and save validation.


func test_constructor_starts_all_clean_and_clamps_negative_stock() -> void:
	_assert_counts(PlateLedger.new(), 0, 0, 0, 0)
	_assert_counts(PlateLedger.new(-1), 0, 0, 0, 0)
	_assert_counts(PlateLedger.new(-PlateLedger.MAX_TOTAL - 1), 0, 0, 0, 0)
	_assert_counts(PlateLedger.new(5), 5, 5, 0, 0)


func test_zero_stock_and_invalid_ids_cannot_allocate_or_move_plates() -> void:
	var empty: PlateLedger = PlateLedger.new()
	var before: Dictionary = empty.state()
	assert_false(empty.take(1, 10))
	assert_false(empty.return_to_table(1, 10))
	assert_eq(empty.collect_table(10), 0)
	assert_eq(empty.recover_table(10), 0)
	assert_false(empty.wash_one())
	assert_eq(empty.state(), before)
	var ledger: PlateLedger = PlateLedger.new(2)
	before = ledger.state()
	for invalid_id: int in [0, -1, -PlateLedger.MAX_TOTAL - 1]:
		assert_false(ledger.take(invalid_id, 10))
		assert_false(ledger.take(1, invalid_id))
		assert_false(ledger.return_to_table(invalid_id, 10))
		assert_false(ledger.return_to_table(1, invalid_id))
		assert_false(ledger.recover_order(invalid_id))
		assert_eq(ledger.collect_table(invalid_id), 0)
		assert_eq(ledger.recover_table(invalid_id), 0)
		assert_false(ledger.has_order(invalid_id))
		assert_eq(ledger.state(), before)


func test_take_is_idempotent_for_same_order_and_cannot_steal_its_table() -> void:
	var ledger: PlateLedger = PlateLedger.new(2)
	assert_true(ledger.take(1, 10))
	_assert_counts(ledger, 2, 1, 0, 1)
	var before: Dictionary = ledger.state()
	assert_true(ledger.take(1, 10))
	assert_false(ledger.take(1, 20))
	assert_false(ledger.take(1, 0))
	assert_eq(ledger.state(), before)
	assert_true(ledger.take(2, 10), "another seat owns a distinct plate")
	assert_false(ledger.take(3, 20), "no clean stock remains")
	assert_true(ledger.take(2, 10), "replay still succeeds when stock is empty")
	assert_true(ledger.has_order(1))
	assert_true(ledger.has_order(2))
	assert_false(ledger.has_order(3))
	_assert_counts(ledger, 2, 0, 0, 2)


func test_return_requires_matching_order_and_table_and_keeps_plate_in_use() -> void:
	var ledger: PlateLedger = PlateLedger.new(2)
	assert_true(ledger.take(1, 10))
	var before: Dictionary = ledger.state()
	assert_false(ledger.return_to_table(1, 20))
	assert_false(ledger.return_to_table(2, 10))
	assert_eq(ledger.state(), before)
	assert_true(ledger.return_to_table(1, 10))
	assert_true(ledger.return_to_table(1, 10))
	assert_true(ledger.take(1, 10), "replay cannot replace a returned token")
	assert_true(ledger.state()["orders"][1]["returned"])
	assert_true(ledger.has_order(1))
	_assert_counts(ledger, 2, 1, 0, 1)


func test_collection_takes_only_returned_plates_at_the_requested_table() -> void:
	var ledger: PlateLedger = PlateLedger.new(4)
	assert_true(ledger.take(1, 10))
	assert_true(ledger.take(2, 10))
	assert_true(ledger.take(3, 20))
	assert_true(ledger.return_to_table(1, 10))
	assert_true(ledger.return_to_table(3, 20))
	assert_eq(ledger.collect_table(10), 1)
	assert_false(ledger.has_order(1))
	assert_true(ledger.has_order(2), "an active diner at the same table retains its plate")
	assert_true(ledger.has_order(3), "another table's returned plate remains held")
	_assert_counts(ledger, 4, 1, 1, 2)
	assert_eq(ledger.collect_table(10), 0)
	assert_false(ledger.take(1, 10), "collection retires the order")
	assert_true(ledger.return_to_table(2, 10))
	assert_eq(ledger.collect_table(10), 1)
	assert_eq(ledger.collect_table(20), 1)
	_assert_counts(ledger, 4, 1, 3, 0)


func test_recovery_moves_active_or_returned_order_to_dirty_exactly_once() -> void:
	var ledger: PlateLedger = PlateLedger.new(3)
	assert_true(ledger.take(1, 10))
	assert_true(ledger.take(2, 10))
	assert_true(ledger.take(3, 20))
	assert_true(ledger.return_to_table(2, 10))
	assert_true(ledger.recover_order(1))
	assert_false(ledger.recover_order(1))
	assert_false(ledger.return_to_table(1, 10))
	assert_true(ledger.recover_order(2))
	assert_false(ledger.recover_order(2))
	assert_eq(ledger.collect_table(10), 0)
	assert_eq(ledger.recover_table(20), 1)
	assert_false(ledger.recover_order(3))
	assert_eq(ledger.recover_table(20), 0)
	_assert_counts(ledger, 3, 0, 3, 0)
	for order_id: int in [1, 2, 3]:
		assert_false(ledger.has_order(order_id))
	assert_true(ledger.wash_one())
	assert_false(ledger.take(1, 10), "washing cannot revive a cancelled order")
	assert_false(ledger.take(2, 10))
	assert_false(ledger.take(3, 20))
	_assert_counts(ledger, 3, 1, 2, 0)


func test_cancellation_before_allocation_rejects_a_late_take_until_morning() -> void:
	var ledger: PlateLedger = PlateLedger.new(1)
	assert_false(ledger.recover_order(7), "there was no held plate to move")
	assert_false(ledger.recover_order(7))
	assert_false(ledger.take(7, 10), "late work cannot plate a cancelled order")
	assert_false(ledger.take(7, 20))
	_assert_counts(ledger, 1, 1, 0, 0)
	ledger.tidy_overnight()
	assert_true(ledger.take(7, 20))
	_assert_counts(ledger, 1, 0, 0, 1)


func test_removed_table_recovers_all_its_seats_without_touching_another_table() -> void:
	var ledger: PlateLedger = PlateLedger.new(4)
	assert_true(ledger.take(1, 10))
	assert_true(ledger.take(2, 10))
	assert_true(ledger.take(3, 20))
	assert_true(ledger.take(4, 20))
	assert_true(ledger.return_to_table(1, 10))
	assert_true(ledger.return_to_table(3, 20))
	assert_eq(ledger.recover_table(10), 2)
	assert_eq(ledger.recover_table(10), 0)
	assert_false(ledger.has_order(1))
	assert_false(ledger.has_order(2))
	assert_true(ledger.has_order(3))
	assert_true(ledger.has_order(4))
	assert_true(ledger.state()["orders"][3]["returned"])
	assert_false(ledger.state()["orders"][4]["returned"])
	_assert_counts(ledger, 4, 0, 2, 2)
	assert_eq(ledger.collect_table(20), 1)
	assert_eq(ledger.recover_table(20), 1)
	_assert_counts(ledger, 4, 0, 4, 0)
	assert_true(ledger.wash_one())
	for order_id: int in [1, 2, 3, 4]:
		assert_false(ledger.take(order_id, 30), "removed and collected tokens stay retired")
	_assert_counts(ledger, 4, 1, 3, 0)


func test_wash_moves_one_dirty_plate_and_never_an_active_plate() -> void:
	var ledger: PlateLedger = PlateLedger.new(2)
	assert_true(ledger.take(1, 10))
	assert_true(ledger.take(2, 10))
	assert_false(ledger.wash_one())
	assert_true(ledger.return_to_table(1, 10))
	assert_false(ledger.wash_one(), "a returned plate still needs collection")
	assert_eq(ledger.collect_table(10), 1)
	assert_true(ledger.wash_one())
	_assert_counts(ledger, 2, 1, 0, 1)
	assert_true(ledger.has_order(2))
	assert_false(ledger.wash_one())
	assert_false(ledger.take(1, 10))
	assert_true(ledger.take(3, 20), "a new order can use the washed plate")
	_assert_counts(ledger, 2, 0, 0, 2)


func test_overnight_tidy_cleans_every_bucket_and_clears_all_token_history() -> void:
	var ledger: PlateLedger = PlateLedger.new(4)
	assert_true(ledger.take(1, 10))
	assert_true(ledger.take(2, 10))
	assert_true(ledger.take(3, 20))
	assert_true(ledger.return_to_table(1, 10))
	assert_eq(ledger.collect_table(10), 1)
	assert_true(ledger.return_to_table(2, 10))
	assert_false(ledger.recover_order(9))
	_assert_counts(ledger, 4, 1, 1, 2)
	ledger.tidy_overnight()
	_assert_counts(ledger, 4, 4, 0, 0)
	assert_eq(ledger.state()["orders"], {})
	assert_eq(ledger.state()["retired"], [] as Array[int])
	ledger.tidy_overnight()
	_assert_counts(ledger, 4, 4, 0, 0)
	for order_id: int in [1, 2, 3, 9]:
		assert_true(ledger.take(order_id, 30), "the new day can reuse either live or retired IDs")
	_assert_counts(ledger, 4, 0, 0, 4)


func test_state_is_sorted_and_detached_including_nested_tokens_and_tombstones() -> void:
	var ledger: PlateLedger = PlateLedger.new(4)
	assert_true(ledger.take(30, 300))
	assert_true(ledger.take(10, 100))
	assert_true(ledger.take(20, 200))
	assert_true(ledger.return_to_table(20, 200))
	assert_true(ledger.recover_order(30))
	assert_false(ledger.recover_order(7))
	var before: Dictionary = ledger.state()
	assert_eq(before["orders"].keys(), [10, 20])
	assert_eq(before["retired"], [7, 30] as Array[int])
	var snapshot: Dictionary = ledger.state()
	snapshot["total"] = 999
	snapshot["clean"] = 999
	snapshot["dirty"] = 999
	snapshot["in_use"] = 999
	var orders: Dictionary = snapshot["orders"]
	var returned_token: Dictionary = orders[20]
	returned_token["table_id"] = 999
	returned_token["returned"] = false
	orders.clear()
	var retired: Array = snapshot["retired"]
	retired.clear()
	assert_eq(ledger.state(), before)
	_assert_counts(ledger, 4, 1, 1, 2)


func test_save_contains_only_total_and_restore_starts_all_clean_with_new_history() -> void:
	var ledger: PlateLedger = PlateLedger.new(5)
	assert_true(ledger.take(1, 10))
	assert_true(ledger.take(2, 10))
	assert_true(ledger.return_to_table(1, 10))
	assert_eq(ledger.collect_table(10), 1)
	assert_false(ledger.recover_order(9))
	var saved: Dictionary = ledger.to_dict()
	assert_eq(saved, {"version": 1, "total": 5})
	var restored: PlateLedger = PlateLedger.from_dict(saved)
	assert_not_null(restored)
	if restored == null:
		return
	_assert_counts(restored, 5, 5, 0, 0)
	assert_eq(restored.state()["orders"], {})
	assert_eq(restored.state()["retired"], [] as Array[int])
	assert_true(restored.take(1, 20))
	assert_true(restored.take(2, 20))
	assert_true(restored.take(9, 20))
	saved["total"] = 999
	assert_eq(ledger.total, 5)
	assert_eq(restored.total, 5)
	_assert_counts(ledger, 5, 3, 1, 1)


func test_json_round_trip_writes_numeric_stock_and_restores_the_supported_range() -> void:
	for quantity: int in [1, 12, 999]:
		var ledger: PlateLedger = PlateLedger.new(quantity)
		var saved: Dictionary = ledger.to_dict()
		assert_eq(saved, {"version": 1, "total": quantity})
		assert_eq(typeof(saved["total"]), TYPE_INT)
		var direct: PlateLedger = PlateLedger.from_dict(saved)
		assert_not_null(direct)
		if direct != null:
			_assert_counts(direct, quantity, quantity, 0, 0)
		var serialized: String = JSON.stringify(saved)
		var parsed: Dictionary = JSON.parse_string(serialized)
		assert_eq(typeof(parsed["total"]), TYPE_FLOAT, "Godot parses JSON numbers as floats")
		assert_eq(parsed["total"], float(quantity))
		var restored: PlateLedger = PlateLedger.from_dict(parsed)
		assert_not_null(restored)
		if restored == null:
			continue
		_assert_counts(restored, quantity, quantity, 0, 0)
		assert_eq(restored.to_dict(), ledger.to_dict())


func test_legacy_canonical_string_totals_restore_and_rewrite_as_numbers() -> void:
	for quantity: int in [1, 12, 999]:
		var legacy: Dictionary = {"version": 1, "total": str(quantity)}
		var before: PackedByteArray = var_to_bytes(legacy)
		var restored: PlateLedger = PlateLedger.from_dict(legacy)
		assert_not_null(restored)
		assert_eq(var_to_bytes(legacy), before, "legacy reads leave their input unchanged")
		if restored == null:
			continue
		_assert_counts(restored, quantity, quantity, 0, 0)
		assert_eq(restored.to_dict(), {"version": 1, "total": quantity})
		assert_eq(typeof(restored.to_dict()["total"]), TYPE_INT)


func test_save_rejects_missing_unknown_and_non_string_keys() -> void:
	var invalid: Array[Dictionary] = [
		{},
		{"version": 1},
		{"total": "1"},
		{"version": 1, "total": "1", "extra": true},
		{"version": 1, "total": "1", "clean": "1"},
		{&"version": 1, "total": "1"},
		{"version": 1, &"total": "1"},
		{1: 1, "total": "1"},
	]
	for section: Dictionary in invalid:
		assert_null(PlateLedger.from_dict(section), str(section))


func test_save_rejects_wrong_version_types_and_values() -> void:
	var invalid_versions: Array[Variant] = [
		null, true, false, 0, -1, 2, 1.5, INF, NAN, "1", &"1", [], {},
	]
	for version: Variant in invalid_versions:
		assert_null(PlateLedger.from_dict({"version": version, "total": "3"}), str(version))
	assert_not_null(PlateLedger.from_dict({"version": 1, "total": "3"}))
	assert_not_null(PlateLedger.from_dict({"version": 1.0, "total": "3"}), "JSON's integral version is accepted")


func test_save_rejects_invalid_types_noncanonical_strings_and_out_of_range_totals() -> void:
	var invalid_totals: Array[Variant] = [
		null, true, false, 0, -1, 1000, PlateLedger.MAX_TOTAL, -PlateLedger.MAX_TOTAL - 1, 9007199254740993,
		0.0, -1.0, 1000.0, 0.5, 1.5, 999.5, INF, -INF, NAN, float(PlateLedger.MAX_TOTAL), 1.0e100,
		[], {}, &"3",
		"", "0", "-1", "-0", "+1", "00", "01", " 1", "1 ", "1\n", "1.0", "1e2", "x", "1000", "9999",
		"9223372036854775808", "9999999999999999999", "18446744073709551615",
		"100000000000000000000",
	]
	for quantity: Variant in invalid_totals:
		var section: Dictionary = {"version": 1, "total": quantity}
		# Byte snapshots compare NAN safely while preserving every input type.
		var before: PackedByteArray = var_to_bytes(section)
		assert_null(PlateLedger.from_dict(section), str(quantity))
		assert_eq(var_to_bytes(section), before, "rejected totals leave their input unchanged")


func test_maximum_stock_and_ids_preserve_conservation_through_every_bucket() -> void:
	var maximum: int = PlateLedger.MAX_TOTAL
	var ledger: PlateLedger = PlateLedger.new(maximum)
	assert_true(ledger.take(maximum, maximum))
	assert_true(ledger.take(1, maximum))
	_assert_counts(ledger, maximum, maximum - 2, 0, 2)
	assert_true(ledger.return_to_table(maximum, maximum))
	assert_eq(ledger.collect_table(maximum), 1)
	_assert_counts(ledger, maximum, maximum - 2, 1, 1)
	assert_eq(ledger.recover_table(maximum), 1)
	_assert_counts(ledger, maximum, maximum - 2, 2, 0)
	assert_true(ledger.wash_one())
	_assert_counts(ledger, maximum, maximum - 1, 1, 0)
	assert_true(ledger.wash_one())
	assert_false(ledger.wash_one())
	_assert_counts(ledger, maximum, maximum, 0, 0)
	assert_false(ledger.take(maximum, maximum))
	ledger.tidy_overnight()
	assert_true(ledger.take(maximum, maximum))
	_assert_counts(ledger, maximum, maximum - 1, 0, 1)
	ledger.tidy_overnight()
	_assert_counts(ledger, maximum, maximum, 0, 0)


func _assert_counts(ledger: PlateLedger, total: int, clean: int, dirty: int, in_use: int) -> void:
	assert_eq(ledger.total, total)
	assert_eq(ledger.clean, clean)
	assert_eq(ledger.dirty, dirty)
	assert_eq(ledger.in_use, in_use)
	assert_true(ledger.clean >= 0)
	assert_true(ledger.dirty >= 0)
	assert_true(ledger.in_use >= 0)
	assert_eq(ledger.clean + ledger.dirty + ledger.in_use, ledger.total, "plate stock is conserved")
