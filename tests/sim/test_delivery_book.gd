extends TestCase
## FK-087 deliveries: the schedule from data, when an order arrives, the
## countdown bar's values, full refunds and the save format.

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")


func _clock(phase: SimClock.Phase, phase_tick: int = 0, day: int = 3) -> SimClock:
	var clock: SimClock = SimClock.new()
	clock.day = day
	clock.phase = phase
	clock.phase_tick = phase_tick
	return clock


func _lines(id: StringName, qty: int, unit_cost: int = 1) -> Array[Dictionary]:
	return [{"id": id, "qty": qty, "unit_cost": unit_cost}] as Array[Dictionary]


func test_the_schedule_comes_from_data_and_scales_with_the_day() -> void:
	assert_true(TUNING.morning_delivery)
	assert_eq(TUNING.delivery_interval_minutes, 180)
	var clock: SimClock = _clock(SimClock.Phase.OPEN)
	# 11:00 to 21:00 in 3600 ticks: deliveries at 14:00, 17:00 and 20:00.
	assert_eq(DeliveryBook.slot_ticks(clock, TUNING), [1080, 2160, 3240] as Array[int])
	assert_eq(DeliveryBook.minute_of(clock, 1080), 14 * 60)
	clock.open_ticks = 600
	assert_eq(DeliveryBook.slot_ticks(clock, TUNING), [180, 360, 540] as Array[int], "a shortened test day keeps the times")
	var none: EconomyTuning = TUNING.duplicate() as EconomyTuning
	none.delivery_interval_minutes = 0
	assert_eq(DeliveryBook.slot_ticks(clock, none), [] as Array[int])


func test_an_order_comes_with_the_first_delivery_after_it_is_placed() -> void:
	assert_eq(DeliveryBook.next_due(_clock(SimClock.Phase.MORNING), TUNING), Vector2i(3, 0), "morning orders: at opening")
	assert_eq(DeliveryBook.next_due(_clock(SimClock.Phase.OPEN, 0), TUNING), Vector2i(3, 1080))
	assert_eq(DeliveryBook.next_due(_clock(SimClock.Phase.OPEN, 1079), TUNING), Vector2i(3, 1080))
	assert_eq(DeliveryBook.next_due(_clock(SimClock.Phase.OPEN, 1080), TUNING), Vector2i(3, 2160), "just missed it")
	assert_eq(DeliveryBook.next_due(_clock(SimClock.Phase.OPEN, 3300), TUNING), Vector2i(4, DeliveryBook.MORNING),
		"after the last delivery: tomorrow morning")
	assert_eq(DeliveryBook.next_due(_clock(SimClock.Phase.LAST_ORDERS), TUNING), Vector2i(4, DeliveryBook.MORNING))
	assert_eq(DeliveryBook.next_due(_clock(SimClock.Phase.CLOSED), TUNING), Vector2i(4, DeliveryBook.MORNING))
	var no_morning: EconomyTuning = TUNING.duplicate() as EconomyTuning
	no_morning.morning_delivery = false
	assert_eq(DeliveryBook.next_due(_clock(SimClock.Phase.CLOSED), no_morning), Vector2i(4, 0), "then at opening")


func test_orders_arrive_only_when_due() -> void:
	var book: DeliveryBook = DeliveryBook.new()
	assert_true(book.place(_lines(&"bread", 4), 4, false, Vector2i(3, 1080)))
	assert_true(book.place(_lines(&"cheese", 2), 2, false, Vector2i(3, 2160)))
	assert_true(book.place(_lines(&"bread", 1), 1, false, Vector2i(4, DeliveryBook.MORNING)))
	assert_eq(book.pending_by_id(), {&"bread": 5, &"cheese": 2})
	assert_eq(book.take_due(_clock(SimClock.Phase.OPEN, 1079)), [] as Array[Dictionary])
	assert_eq(book.take_due(_clock(SimClock.Phase.OPEN, 1080)), [{"id": &"bread", "qty": 4}] as Array[Dictionary])
	assert_eq(book.size(), 2)
	assert_eq(book.take_due(_clock(SimClock.Phase.CLOSED)), [{"id": &"cheese", "qty": 2}] as Array[Dictionary],
		"a missed daytime delivery lands at the latest at closing")
	assert_eq(book.take_due(_clock(SimClock.Phase.MORNING, 0, 4)), [] as Array[Dictionary],
		"the morning order waits for the morning delivery itself")
	assert_eq(book.take_due(_clock(SimClock.Phase.MORNING, 0, 4), true), [{"id": &"bread", "qty": 1}] as Array[Dictionary])
	assert_true(book.is_empty())


func test_cancelling_refunds_everything_paid() -> void:
	var book: DeliveryBook = DeliveryBook.new()
	assert_true(book.place(_lines(&"bread", 4), 4, false, Vector2i(3, 1080)))
	assert_true(book.place(_lines(&"beef_patty", 3, 2), 7, true, Vector2i(3, 0)), "a standing order with its premium")
	assert_eq(book.paid_total(), 11)
	assert_eq(book.cancel_all(), 11, "the premium is refunded too")
	assert_true(book.is_empty())
	assert_eq(book.cancel_all(), 0)
	assert_false(book.place([] as Array[Dictionary], 0, false, Vector2i(3, 0)))
	assert_false(book.place(_lines(&"bread", 0), 0, false, Vector2i(3, 0)))


func test_the_countdown_bar() -> void:
	var morning: Dictionary = DeliveryBook.countdown(_clock(SimClock.Phase.MORNING), TUNING)
	assert_eq(morning["when"], &"open")
	assert_eq(morning["minute"], 11 * 60)
	var early: Dictionary = DeliveryBook.countdown(_clock(SimClock.Phase.OPEN, 270), TUNING)
	assert_eq(early["when"], &"today")
	assert_eq(early["minute"], 14 * 60)
	assert_almost_eq(float(early["fraction"]), 0.25, 0.0001)
	var later: Dictionary = DeliveryBook.countdown(_clock(SimClock.Phase.OPEN, 1620), TUNING)
	assert_eq(later["minute"], 17 * 60)
	assert_almost_eq(float(later["fraction"]), 0.5, 0.0001, "measured from the 14:00 delivery")
	assert_eq(DeliveryBook.countdown(_clock(SimClock.Phase.OPEN, 3500), TUNING)["when"], &"tomorrow")
	assert_eq(DeliveryBook.countdown(_clock(SimClock.Phase.CLOSED), TUNING)["when"], &"tomorrow")


func test_save_round_trip_and_validation() -> void:
	var book: DeliveryBook = DeliveryBook.new()
	assert_true(book.place(_lines(&"bread", 4), 4, false, Vector2i(3, 1080)))
	assert_true(book.place(_lines(&"cheese", 2), 3, true, Vector2i(4, DeliveryBook.MORNING)))
	var data: Dictionary = JSON.parse_string(JSON.stringify(book.to_dict()))
	var restored: DeliveryBook = DeliveryBook.new()
	assert_true(restored.from_dict(data))
	assert_eq(restored.orders(), book.orders())
	assert_eq(restored.paid_total(), 7)
	for broken: Dictionary in [{}, {"version": 2, "orders": []}, {"version": 1},
			{"version": 1, "orders": [{"day": 3, "tick": 0, "cost": 1, "standing": false, "lines": [{"id": "bread", "qty": 0, "unit_cost": 1}]}]},
			{"version": 1, "orders": [{"day": 3, "tick": -2, "cost": 1, "standing": false, "lines": [{"id": "bread", "qty": 1, "unit_cost": 1}]}]},
			{"version": 1, "orders": [{"day": 3, "tick": 0, "cost": -1, "standing": false, "lines": [{"id": "bread", "qty": 1, "unit_cost": 1}]}]},
			{"version": 1, "orders": [{"day": 3, "tick": 0, "cost": 1, "standing": "no", "lines": []}]}]:
		var target: DeliveryBook = DeliveryBook.new()
		assert_true(target.place(_lines(&"tea", 1), 1, false, Vector2i(1, 0)))
		assert_false(target.from_dict(broken), "rejects %s" % [broken])
		assert_eq(target.pending_by_id(), {&"tea": 1}, "a refused load changes nothing")
