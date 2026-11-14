extends TestCase
## Pure model and signed cash accounting for tomorrow's group bookings.

const TUNING: BookingTuning = preload("res://data/balance/bookings.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CLOTH_TABLE: ItemDef = preload("res://data/items/cloth_table.tres")
const CHAIR: ItemDef = preload("res://data/items/chair.tres")
const REVIEW_TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const REVIEW_QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")

var _provider_calls: int = 0


func _provider(seed_value: int) -> Callable:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return func() -> RandomNumberGenerator:
		_provider_calls += 1
		return random


func _certain_tuning() -> BookingTuning:
	var tuned: BookingTuning = TUNING.duplicate() as BookingTuning
	tuned.offer_chance = 1.0
	return tuned


func _offer(seed_value: int = 316) -> GroupBooking:
	var model: GroupBooking = GroupBooking.new(_certain_tuning())
	var menu: Array[StringName] = [&"burger", &"soup", &"grilled_cheese"]
	assert_false(model.plan_offer(1, 2, menu, 11 * 60, 21 * 60, _provider(seed_value), TUNING.max_party_size).is_empty())
	return model


func test_tuning_and_party_limits_keep_walkins_at_six_and_bookings_at_ten() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.hold_before_minutes, 75)
	assert_eq(TUNING.reserved_queue_grace_minutes, 30)
	assert_eq(TUNING.unlock_level, 2)
	assert_almost_eq(TUNING.offer_chance, 0.25)
	assert_eq(TUNING.min_party_size, 6)
	assert_eq(TUNING.max_party_size, 10)
	assert_eq(Party.MAX_SIZE, 6)
	assert_false(Party.new([1, 2, 3, 4, 5, 6, 7] as Array[int]).is_valid())
	assert_false(Party.new([1, 2, 3, 4, 5] as Array[int], true).is_valid())
	assert_true(Party.new([1, 2, 3, 4, 5, 6, 7] as Array[int], true).is_valid())
	assert_true(Party.new([1, 2, 3, 4, 5, 6, 7, 8, 9, 10] as Array[int], true).is_valid())
	assert_false(Party.new([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] as Array[int], true).is_valid())
	for seed: int in range(1, 51):
		var booking: GroupBooking = _offer(seed)
		assert_true(int(booking.offer["party_size"]) >= 6 and int(booking.offer["party_size"]) <= 10)
		assert_eq(booking.offer["guest_seeds"].size(), int(booking.offer["party_size"]))


func test_level_gate_empty_menu_and_no_slot_never_fetch_rng() -> void:
	var model: GroupBooking = GroupBooking.new(_certain_tuning())
	var provider: Callable = _provider(9)
	_provider_calls = 0
	assert_true(model.plan_offer(1, 1, [&"burger"] as Array[StringName], 660, 1260, provider, TUNING.max_party_size).is_empty())
	assert_true(model.plan_offer(1, 2, [] as Array[StringName], 660, 1260, provider, TUNING.max_party_size).is_empty())
	assert_true(model.plan_offer(1, 2, [&"burger"] as Array[StringName], 1200, 1260, provider, TUNING.max_party_size).is_empty())
	assert_eq(_provider_calls, 0)
	assert_eq(model.planned_day, 0, "an ineligible morning does not consume its daily roll")


func test_offer_is_deterministic_idempotent_and_requires_a_usable_quarter_hour() -> void:
	var first: GroupBooking = _offer(101)
	var second: GroupBooking = _offer(101)
	assert_eq(first.offer, second.offer)
	assert_eq(int(first.offer["service_day"]), 2)
	assert_true(int(first.offer["slot_minute"]) % 15 == 0)
	assert_true(int(first.offer["slot_minute"]) >= 11 * 60 + TUNING.hold_before_minutes)
	assert_true(21 * 60 - int(first.offer["slot_minute"]) - TUNING.slot_minutes \
		>= TUNING.min_service_remaining_minutes, "buffer follows the whole arrival slot")
	assert_true(TUNING.occasions.has(String(first.offer["occasion"])))
	assert_true([&"burger", &"soup", &"grilled_cheese"].has(StringName(first.offer["recipe_id"])))
	_provider_calls = 0
	first.plan_offer(1, 2, [&"burger"] as Array[StringName], 660, 1260, _provider(202), TUNING.max_party_size)
	assert_eq(_provider_calls, 0, "the morning is never re-rolled after its first offer")
	var edge: GroupBooking = GroupBooking.new(_certain_tuning())
	var edge_offer: Dictionary = edge.plan_offer(1, 2, [&"burger"] as Array[StringName],
		667, 855, _provider(41), TUNING.max_party_size)
	assert_eq(edge_offer["slot_minute"], 750, "open 11:07 plus 75-minute hold rounds up to 12:30")
	assert_eq(855 - int(edge_offer["slot_minute"]) - TUNING.slot_minutes, 90,
		"the only slot leaves exactly 90 minutes after the whole slot")
	var too_short: GroupBooking = GroupBooking.new(_certain_tuning())
	_provider_calls = 0
	assert_true(too_short.plan_offer(1, 2, [&"burger"] as Array[StringName],
		667, 854, _provider(42), TUNING.max_party_size).is_empty())
	assert_eq(_provider_calls, 0, "a window too short for one legal slot never fetches RNG")


func test_offers_fit_seating_and_unaccepted_oversized_offers_expire() -> void:
	var menu: Array[StringName] = [&"burger"]
	var too_small: GroupBooking = GroupBooking.new(_certain_tuning())
	_provider_calls = 0
	assert_true(too_small.plan_offer(1, 2, menu, 660, 1260, _provider(1), 5).is_empty())
	assert_eq(_provider_calls, 0)
	for capacity: int in range(6, 10):
		for seed_value: int in range(32):
			var model: GroupBooking = GroupBooking.new(_certain_tuning())
			var offer: Dictionary = model.plan_offer(1, 2, menu, 660, 1260,
				_provider(seed_value), capacity)
			var size: int = int(offer.get("party_size", 0))
			assert_true(size >= 6 and size <= capacity)
			assert_eq(offer["guest_seeds"].size(), size)
			var draws: int = _provider_calls
			assert_true(model.plan_offer(1, 2, menu, 660, 1260, _provider(99), 5).is_empty())
			assert_true(model.accept_offer(1).is_empty())
			assert_eq(_provider_calls, draws)


func test_offer_odds_are_about_one_in_four() -> void:
	var offered: int = 0
	for seed: int in range(1, 401):
		var model: GroupBooking = GroupBooking.new(TUNING)
		if not model.plan_offer(seed, 2, [&"burger"] as Array[StringName], 660, 1260,
				_provider(seed * 7919), TUNING.max_party_size).is_empty():
			offered += 1
	assert_true(offered >= 70 and offered <= 130, "observed offers: %d/400" % offered)


func test_accept_decline_and_only_one_accepted_booking() -> void:
	var model: GroupBooking = _offer()
	var accepted: Dictionary = model.accept_offer(1)
	assert_false(accepted.is_empty())
	assert_eq(accepted["booking_id"], 1)
	assert_eq(accepted["service_day"], 2)
	assert_eq(accepted["deposit_amount"], int(accepted["party_size"]) * TUNING.deposit_per_guest)
	assert_true(model.has_active_booking())
	assert_true(model.plan_offer(2, 2, [&"burger"] as Array[StringName], 660, 1260, _provider(5), TUNING.max_party_size).is_empty())
	assert_eq(model.booking["booking_id"], 1)
	var declined: GroupBooking = _offer(55)
	assert_true(declined.decline_offer(1))
	assert_false(declined.decline_offer(1))
	assert_true(declined.offer.is_empty())


func test_soft_group_hold_and_once_only_effects_are_booking_scoped() -> void:
	var model: GroupBooking = _offer()
	var booking: Dictionary = model.accept_offer(1)
	var id: int = int(booking["booking_id"])
	assert_true(model.mark_held_group(id, 901, [11, 12] as Array[int]))
	assert_false(model.mark_held_group(id, 0, [11, 12] as Array[int]))
	assert_false(model.clear_held_group(id, 902))
	assert_eq(int(model.booking["held_group_id"]), 901)
	for effect: StringName in [GroupBooking.EFFECT_PAYMENT, GroupBooking.EFFECT_TIP, GroupBooking.EFFECT_REVIEW]:
		assert_true(model.claim_effect(id, effect))
		assert_false(model.claim_effect(id, effect), "effect %s is claimed once" % effect)
	assert_true(model.settle(id))
	assert_false(model.has_active_booking())
	assert_false(model.claim_effect(id, GroupBooking.EFFECT_REVIEW))
	var restored: GroupBooking = GroupBooking.new(TUNING)
	assert_true(restored.from_dict(model.to_dict()), "a settled reservation round-trips after clearing its held group")


func test_no_seat_timeout_refund_and_review_are_a_single_terminal_path() -> void:
	var model: GroupBooking = _offer()
	var booking: Dictionary = model.accept_offer(1)
	var id: int = int(booking["booking_id"])
	assert_true(model.claim_effect(id, GroupBooking.EFFECT_NO_SEAT))
	assert_true(model.claim_effect(id, GroupBooking.EFFECT_REVIEW))
	assert_false(model.claim_effect(id, GroupBooking.EFFECT_PAYMENT))
	assert_true(model.settle(id, true))
	assert_false(model.settle(id, true), "a second timeout cannot issue another refund")
	assert_false(model.claim_effect(id, GroupBooking.EFFECT_NO_SEAT))
	assert_false(model.claim_effect(id, GroupBooking.EFFECT_TIP))


func test_accepted_booking_round_trips_and_rejects_malformed_data_atomically() -> void:
	var model: GroupBooking = _offer(88)
	model.accept_offer(1)
	model.mark_held_group(1, 22, [31, 32] as Array[int])
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(model.to_dict())) as Dictionary
	var restored: GroupBooking = GroupBooking.new(TUNING)
	assert_true(restored.from_dict(encoded))
	assert_eq(restored.booking, encoded["booking"], "booking fields survive JSON numeric forms and arrays")
	assert_eq(restored.offer, encoded["offer"])
	assert_eq(restored.planned_day, 1)
	var before: Dictionary = restored.to_dict()
	var malformed: Dictionary = encoded.duplicate(true)
	malformed["booking"]["guest_seeds"] = [1]
	assert_false(restored.from_dict(malformed))
	var invalid_tuning: BookingTuning = TUNING.duplicate() as BookingTuning
	invalid_tuning.slot_minutes = 0
	assert_false(GroupBooking.new(invalid_tuning).from_dict(encoded), "invalid tuning fails before modulo")
	var contradictory: Dictionary = encoded.duplicate(true)
	contradictory["booking"]["status"] = String(GroupBooking.STATUS_SETTLED)
	contradictory["booking"]["effects"] = [String(GroupBooking.EFFECT_PAYMENT),
		String(GroupBooking.EFFECT_NO_SEAT), String(GroupBooking.EFFECT_REVIEW)]
	assert_false(restored.from_dict(contradictory), "payment and no-seat effects cannot conflict")
	var bad_terminal: Dictionary = encoded.duplicate(true)
	bad_terminal["booking"]["status"] = String(GroupBooking.STATUS_REFUNDED)
	bad_terminal["booking"]["effects"] = [String(GroupBooking.EFFECT_NO_SEAT)]
	assert_false(restored.from_dict(bad_terminal), "a settled booking must have its one review")
	var double_plan: Dictionary = encoded.duplicate(true)
	double_plan["offer"] = _offer(89).offer.duplicate(true)
	assert_false(restored.from_dict(double_plan), "an active booking cannot coexist with an offer")
	var wrong_day: Dictionary = {"version": GroupBooking.SAVE_VERSION, "planned_day": 1,
		"offer": {"offer_day": 2}, "booking": {}}
	assert_false(restored.from_dict(wrong_day), "offer and planned-day stamps must agree")
	assert_eq(restored.to_dict(), before, "invalid save data cannot partially replace live state")


func test_deposit_and_full_sale_keep_signed_cash_and_operating_income_distinct() -> void:
	var ledger: Ledger = Ledger.new()
	var model: GroupBooking = _offer()
	var booking: Dictionary = model.accept_offer(1)
	var deposit: int = int(booking["deposit_amount"])
	var advance: Dictionary = BookingSettlement.deposit_movement(booking)
	assert_false(advance.is_empty(), "no affordability check is part of booking acceptance")
	_apply(ledger, 1, advance)
	assert_eq(ledger.cash, deposit)
	assert_eq(ledger.day_profit(1), deposit, "raw cash reporting shows the incoming advance")
	assert_eq(ledger.day_totals(1)[Ledger.BOOKING_DEPOSIT], deposit)
	var deposit_report: DayReport = DayReport.new()
	deposit_report.income[Ledger.BOOKING_DEPOSIT] = deposit
	assert_eq(deposit_report.purchase_basis_operating_profit(), 0)
	assert_eq(deposit_report.operating_profit(), 0)
	var movements: Array[Dictionary] = BookingSettlement.pay_bill(booking, 120)
	for movement: Dictionary in movements:
		_apply(ledger, 2, movement)
	assert_eq(ledger.cash, 120, "cash after deposit and balance payment equals the bill")
	assert_eq(ledger.day_profit(2), 120 - deposit, "service-day cash movement is just the balance")
	assert_eq(ledger.day_totals(2)[Ledger.SALE], 120)
	var service_report: DayReport = DayReport.new()
	service_report.income[Ledger.SALE] = 120
	service_report.costs[Ledger.BOOKING_DEPOSIT] = deposit
	service_report.income[Ledger.BANK_LOAN] = 300
	service_report.costs[Ledger.LOAN_REPAYMENT] = 75
	assert_eq(service_report.purchase_basis_operating_profit(), 120)
	service_report.stock_values_recorded = true
	service_report.food_cost_recorded = true
	service_report.food_cost = 0
	assert_eq(service_report.operating_profit(), 120, "full earned bill appears once in actual report policy")


func test_unused_advance_refunds_and_no_seat_refund_are_not_operating_profit() -> void:
	var ledger: Ledger = Ledger.new()
	var booking: Dictionary = _offer().accept_offer(1)
	var deposit: int = int(booking["deposit_amount"])
	_apply(ledger, 1, BookingSettlement.deposit_movement(booking))
	var movements: Array[Dictionary] = BookingSettlement.pay_bill(booking, 20)
	assert_eq(movements.size(), 3)
	for movement: Dictionary in movements:
		_apply(ledger, 2, movement)
	assert_eq(ledger.cash, 20)
	assert_eq(ledger.day_totals(2)[Ledger.SALE], 20)
	var no_seat: Ledger = Ledger.new()
	_apply(no_seat, 1, BookingSettlement.deposit_movement(booking))
	var refund: Dictionary = BookingSettlement.no_seat_refund(booking)
	assert_false(refund.is_empty())
	_apply(no_seat, 2, refund)
	assert_eq(no_seat.cash, 0)
	assert_eq(no_seat.day_profit(1), deposit)
	assert_eq(no_seat.day_profit(2), -deposit)
	assert_eq(no_seat.day_totals(2)[Ledger.BOOKING_REFUND], -deposit)
	var failed_report: DayReport = DayReport.new()
	failed_report.income[Ledger.BOOKING_DEPOSIT] = deposit
	failed_report.costs[Ledger.BOOKING_REFUND] = deposit
	assert_eq(failed_report.purchase_basis_operating_profit(), 0)
	assert_eq(failed_report.operating_profit(), 0)
	assert_eq(BookingSettlement.good_service_tip(100, 3, TUNING), 0)
	assert_eq(BookingSettlement.good_service_tip(100, 4, TUNING), 15)


func test_first_hold_tick_blocks_walkin_before_its_seat_acquisition() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	layout.placements.clear()
	for placement: ShopPlacement in LAYOUT.placements:
		if content.item(placement.item_id).category != ItemDef.Category.TABLE:
			layout.placements.append(placement.duplicate(true) as ShopPlacement)
	for x: int in [3, 5, 7]:
		layout.placements.append(_placement(&"cloth_table", Vector2i(x, 7)))
		layout.placements.append(_placement(&"chair", Vector2i(x, 6), 2))
		layout.placements.append(_placement(&"chair", Vector2i(x, 8)))
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, content, 315, errors, null, false)
	assert_eq(errors, [] as Array[String])
	var clock: SimClock = sim.world.clock
	clock.day = 2
	clock.display_open_minute = 600
	clock.display_close_minute = 900
	clock.open_ticks = 300
	assert_true(clock.start_service())
	clock.phase_tick = 14 # 10:14; the next tick is exactly the 10:15 T-75 hold boundary.
	var booking_model: GroupBooking = _accepted_for_service_slot(690, 6)
	sim.configure_booking(booking_model)
	sim.spawner._remaining = 100000
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _rng(95))
	guest.state = CustomerAgent.State.QUEUED
	sim.advance()
	var held_id: int = sim.world.booking_hold.group_for_booking(sim.world,
		int(booking_model.booking["booking_id"]))
	assert_true(held_id > 0, "the first T-75 query chooses an actual joined dining group")
	assert_eq(clock.display_minutes(), 615)
	assert_true(sim.world.booking_hold.blocks_group(sim.world, held_id),
		"a walk-in cannot acquire the group on the boundary tick")
	assert_false(guest._book_table(sim.world, false), "the normal singleton path respects the hold")
	assert_eq(guest.table_item_id, 0, "the ordinary customer did not reserve or start walking to the held group")


func test_unreachable_lower_id_group_does_not_keep_the_hold_from_a_usable_group() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	layout.placements.clear()
	for y: int in [3, 8]:
		for x: int in [3, 5, 7]:
			layout.placements.append(_placement(&"cloth_table", Vector2i(x, y)))
			layout.placements.append(_placement(&"chair", Vector2i(x, y - 1), 2))
			layout.placements.append(_placement(&"chair", Vector2i(x, y + 1)))
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, content, 317, errors, null, false)
	assert_eq(errors, [] as Array[String])
	var wall_edges: Dictionary[Vector3i, int] = {}
	for x: int in range(1, 16):
		wall_edges[Vector3i(x, 7, SimGrid.EDGE_NORTH)] = SimGrid.Segment.WALL
	assert_true(sim.world.grid.set_segments(wall_edges))
	var model: GroupBooking = _accepted_for_service_slot(690, 6)
	sim.configure_booking(model)
	sim.world.clock.day = 2
	sim.world.clock.display_open_minute = 600
	sim.world.clock.display_close_minute = 900
	sim.world.clock.open_ticks = 300
	assert_true(sim.world.clock.start_service())
	sim.world.clock.phase_tick = 15
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(sim.world, &"cloth_table")
	assert_eq(tables.size(), 6)
	var inaccessible_id: int = PartySeating.table_group_id(tables[0], sim.world.grid)
	var usable_id: int = PartySeating.table_group_id(tables[3], sim.world.grid)
	assert_true(inaccessible_id < usable_id)
	assert_true(PartySeating.table_group_seats(tables[0], sim.world.grid).size() >= 6)
	assert_true(PartySeating.table_group_seats(tables[3], sim.world.grid).size() >= 6)
	assert_eq(sim.world.grid.is_guest_reachable(sim.world.grid.entries()[0],
		PartySeating.table_group_seats(tables[0], sim.world.grid)[0]), false)
	var held_id: int = sim.world.booking_hold.group_for_booking(sim.world,
		int(model.booking["booking_id"]))
	assert_eq(held_id, usable_id, "the inaccessible low-ID candidate cannot hide a usable group")
	assert_false(sim.world.booking_hold.blocks_group(sim.world, inaccessible_id))
	assert_true(sim.world.booking_hold.blocks_group(sim.world, usable_id))
	var view: ShopView = ShopView.new()
	view.show_world(sim.world)
	view.set_booking_marker(held_id, "Reserved\nGroup · 6 guests")
	var marker: Label3D = view.get_node("BookingReservationMarker") as Label3D
	assert_true(marker.visible, "the native marker identifies the actual held group")
	assert_eq(marker.text, "Reserved\nGroup · 6 guests")
	assert_true(sim.world.grid.remove_group(PartySeating.table_group_members(tables[3], sim.world.grid)))
	assert_eq(sim.world.booking_hold.group_for_booking(sim.world,
		int(model.booking["booking_id"])), 0, "a removed joined topology clears its hold")
	view.set_booking_marker(0, "")
	assert_false(marker.visible, "the marker disappears when no usable held group remains")
	view.show_world(SimWorld.new(SimGrid.new(Vector2i(8, 8))))
	assert_false(marker.visible, "a world replacement cannot retain the old shop marker")
	assert_true(model.claim_effect(int(model.booking["booking_id"]), GroupBooking.EFFECT_NO_SEAT))
	assert_true(model.claim_effect(int(model.booking["booking_id"]), GroupBooking.EFFECT_REVIEW))
	assert_true(model.settle(int(model.booking["booking_id"]), true))
	view.set_booking_marker(0, "")
	assert_false(marker.visible, "settlement clears the visual reservation")
	view.free()


func test_booking_review_replaces_member_reviews_with_one_weighted_group_result() -> void:
	var book: ReputationBook = ReputationBook.new()
	var booking_tuning: BookingTuning = TUNING.duplicate() as BookingTuning
	booking_tuning.review_weight = 3
	var visits: Array[ReviewVisit] = []
	for _member: int in 6:
		var visit: ReviewVisit = ReviewVisit.new()
		visit.served = true
		visit.was_seated = true
		visit.quality = 1.0
		visits.append(visit)
	var result: Dictionary = book.record_booking(visits, REVIEW_TUNING, REVIEW_QUOTES,
		_rng(108), booking_tuning, 6)
	assert_eq(result["stars"], 5)
	assert_true(result["good_service"])
	assert_eq(result["weight"], 3, "the authored good-service review weight is honored")
	assert_eq(book.scores().slice(-3), [5, 5, 5])
	assert_eq(book.scores().size(), ReputationBook.INITIAL_REVIEWS + 3)
	var partial: Array[ReviewVisit] = visits.slice(0, 5)
	var partial_result: Dictionary = book.record_booking(partial, REVIEW_TUNING,
		REVIEW_QUOTES, _rng(109), booking_tuning, 6)
	assert_false(partial_result["good_service"], "an incomplete group cannot earn the good-service bonus")
	assert_eq(partial_result["weight"], 1)
	var poor_visits: Array[ReviewVisit] = []
	for _member: int in 6:
		var poor: ReviewVisit = ReviewVisit.new()
		poor.served = true
		poor.was_seated = true
		poor.queue_wait_fraction = 1.0
		poor.food_wait_fraction = 1.0
		poor_visits.append(poor)
	var poor_result: Dictionary = book.record_booking(poor_visits, REVIEW_TUNING,
		REVIEW_QUOTES, _rng(110), booking_tuning, 6)
	assert_false(poor_result["good_service"])
	assert_eq(poor_result["weight"], 1, "poor service keeps the ordinary score weight")
	var no_seat: ReviewVisit = ReviewVisit.new()
	no_seat.closing = true
	var no_seat_result: Dictionary = book.record_booking([no_seat] as Array[ReviewVisit],
		REVIEW_TUNING, REVIEW_QUOTES, _rng(111), booking_tuning, 6)
	assert_eq(no_seat_result["stars"], 1)
	assert_eq(no_seat_result["weight"], 1)
	assert_true(no_seat.closing, "booking scoring never mutates the captured visit")
	var report: DayReport = DayReport.new()
	report.booking_lines = ["A reserved group could not be seated and received a full deposit refund."]
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(report.to_dict())))
	assert_eq(restored.booking_lines, report.booking_lines)


func test_positive_booking_quote_can_name_a_signature_consumed_by_one_member() -> void:
	var ate: ReviewVisit = ReviewVisit.new()
	ate.served = true
	ate.was_seated = true
	ate.ate_signature_dish = true
	var other: ReviewVisit = ReviewVisit.new()
	other.served = true
	other.was_seated = true
	var visits: Array[ReviewVisit] = [ate, other]
	var result: Dictionary = ReputationBook.new().record_booking(visits, REVIEW_TUNING,
		REVIEW_QUOTES, _rng(112), TUNING, 3)
	assert_true(int(result["stars"]) >= 4)
	assert_false(result["good_service"], "an incomplete party retains ordinary weight")
	assert_eq(result["weight"], 1)
	assert_true(REVIEW_QUOTES.groups[&"signature_dish"].has(result["quote"]))
	ate.ate_signature_dish = false
	var no_sig_rng: RandomNumberGenerator = _rng(112)
	var unconsumed: Dictionary = ReputationBook.new().record_booking(visits, REVIEW_TUNING,
		REVIEW_QUOTES, no_sig_rng, TUNING, 3)
	assert_false(REVIEW_QUOTES.groups[&"signature_dish"].has(unconsumed["quote"]))
	var expected_rng: RandomNumberGenerator = _rng(112)
	var used: Dictionary[String, bool] = {}
	assert_eq(unconsumed["quote"], REVIEW_QUOTES.pick(unconsumed["cause"], expected_rng, used))
	assert_eq(no_sig_rng.state, expected_rng.state, "ordinary booking still makes one quote draw")
	var contradictory: ReviewVisit = ReviewVisit.new()
	contradictory.ate_signature_dish = true
	var positive_group: Array[ReviewVisit] = [contradictory]
	for _member: int in 4:
		var served: ReviewVisit = ReviewVisit.new()
		served.served = true
		positive_group.append(served)
	var unserved_tag: Dictionary = ReputationBook.new().record_booking(positive_group,
		REVIEW_TUNING, REVIEW_QUOTES, _rng(113), TUNING, 6)
	assert_true(int(unserved_tag["stars"]) >= 4,
		"the guard is tested even when the aggregate rating qualifies")
	assert_false(REVIEW_QUOTES.groups[&"signature_dish"].has(unserved_tag["quote"]),
		"an unserved member's contradictory tag never licenses group praise")


func test_booking_spawns_once_at_its_slot_without_waiting_for_a_walkin_gap() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.ENTRY)
	var clock: SimClock = SimClock.new()
	clock.day = 2
	clock.display_open_minute = 660
	clock.display_close_minute = 1260
	clock.open_ticks = 600 # one displayed minute per tick
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(grid, clock)
	sim.rng.seed = 716
	sim.spawner = CustomerSpawner.new(sim.rng)
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.start_day()
	var model: GroupBooking = _accepted_for_service_slot(735, 6)
	sim.configure_booking(model)
	assert_true(clock.start_service())
	clock.phase_tick = 74
	var state_before_booking_spawn: int = sim.rng.state
	sim.advance()
	assert_eq(clock.display_minutes(), 735)
	assert_eq(sim.customers().size(), 6, "the booked group arrives at its slot even with no walk-in gap")
	var booked: Party = sim.customers()[0].party
	assert_not_null(booked)
	assert_eq(booked.booking_id, int(model.booking["booking_id"]))
	for index: int in 6:
		assert_eq(sim.customers()[index].rng.seed, int(model.booking["guest_seeds"][index]))
	assert_eq(sim.rng.state, state_before_booking_spawn, "private booking seeds do not draw the customer stream")
	sim.advance()
	assert_eq(sim.customers().size(), 6, "the same booking cannot spawn twice on later ticks")


func _accepted_for_service_slot(slot_minute: int, party_size: int) -> GroupBooking:
	var tuned: BookingTuning = TUNING.duplicate() as BookingTuning
	tuned.min_party_size = party_size
	tuned.max_party_size = party_size
	tuned.offer_chance = 1.0
	var model: GroupBooking = GroupBooking.new(tuned)
	var offer: Dictionary = model.plan_offer(1, 2, [&"burger"] as Array[StringName],
		maxi(slot_minute - tuned.hold_before_minutes, 0), slot_minute + 120, _provider(921), party_size)
	assert_false(offer.is_empty())
	# Pin the slot after a valid deterministic offer; model validation is covered
	# separately and these scenarios exercise the integration clock path.
	model.offer["slot_minute"] = slot_minute
	assert_false(model.accept_offer(1).is_empty())
	return model


func test_reserved_grace_requires_a_live_matching_occupied_or_dirty_group_and_absolute_window() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var model: GroupBooking = fixture["model"]
	var tables: Array[PlacedItem] = fixture["tables"]
	var hold: BookingSeatHold = sim.world.booking_hold
	var booking_id: int = int(model.booking["booking_id"])
	assert_false(hold.pauses_queue_patience(sim.world, booking_id), "an empty clean group grants no grace")
	# Isolated predicate fixture: a physical dining-seat reservation, not a
	# claim that this synthetic owner has eaten a meal. The lifecycle test uses real diners.
	var seat: Vector2i = tables[0].seat_cells[0]
	assert_true(tables[0].reserve(seat, 900))
	var before: Dictionary = model.to_dict()
	assert_true(hold.pauses_queue_patience(sim.world, booking_id))
	assert_false(hold.pauses_queue_patience(sim.world, booking_id + 1))
	sim.world.clock.day = 3
	assert_false(hold.pauses_queue_patience(sim.world, booking_id))
	sim.world.clock.day = 2
	sim.world.clock.phase_tick = 89 # 11:29, before the 11:30 slot.
	assert_false(hold.pauses_queue_patience(sim.world, booking_id))
	sim.world.clock.phase_tick = 119 # 11:59, just before the absolute 12:00 cutoff.
	assert_true(hold.pauses_queue_patience(sim.world, booking_id))
	sim.world.clock.phase_tick = 120
	assert_false(hold.pauses_queue_patience(sim.world, booking_id), "the exact slot+30 minute resumes normal patience")
	assert_eq(model.to_dict(), before, "predicate calls never choose a group or mutate the model")
	sim.world.clock.phase_tick = 90
	assert_true(tables[0].release(seat, 900))
	assert_false(hold.pauses_queue_patience(sim.world, booking_id))
	sim.kitchen.mark_table_dirty(tables[0].id)
	assert_true(hold.pauses_queue_patience(sim.world, booking_id), "empty but dirty is still waiting on its own table")
	var held: Dictionary = model.to_dict()
	assert_true(sim.world.grid.remove_group(PartySeating.table_group_members(tables[0], sim.world.grid)))
	assert_false(hold.pauses_queue_patience(sim.world, booking_id), "a missing held topology gets ordinary patience")
	assert_eq(model.to_dict(), held, "invalid-group observation cannot silently reselect a reservation")


func test_hold_chooses_an_empty_dirty_group_before_an_occupied_lower_id_group() -> void:
	var fixture: Dictionary = _reservation_fixture([7, 10] as Array[int])
	var sim: RestaurantSim = fixture["sim"]
	var model: GroupBooking = fixture["model"]
	var tables: Array[PlacedItem] = fixture["tables"]
	assert_true(tables[0].reserve(tables[0].seat_cells[0], 900))
	sim.kitchen.mark_table_dirty(tables[3].id)
	assert_true(model.clear_held_group(int(model.booking["booking_id"])))
	assert_eq(sim.world.booking_hold.group_for_booking(sim.world, int(model.booking["booking_id"])), tables[3].id,
		"a real dirty empty group can be cleared sooner than the occupied lower-ID group")


func test_reserved_bussing_precedes_high_service_but_respects_off_and_stale_reservations() -> void:
	for condition: String in ["active_low", "active_off", "settled", "wrong_day", "invalid_group"]:
		var fixture: Dictionary = _reservation_fixture()
		var sim: RestaurantSim = fixture["sim"]
		var model: GroupBooking = fixture["model"]
		var tables: Array[PlacedItem] = fixture["tables"]
		sim.kitchen.mark_table_dirty(tables[2].id)
		var bus: SimTask = null
		for task: SimTask in sim.world.board.open_tasks():
			if task.kind == &"bus_table" and task.first_item_id() == tables[2].id:
				bus = task
		assert_not_null(bus)
		var worker: StaffAgent = StaffAgent.new(&"server", 3)
		worker.cell = Vector2i(2, 10)
		sim.world.add_agent(worker)
		var priorities: StaffJobPriorities = StaffJobPriorities.new(&"server")
		assert_true(priorities.set_priority(&"serving", StaffJobPriorities.Level.HIGH))
		assert_true(priorities.set_priority(&"bussing", StaffJobPriorities.Level.OFF \
			if condition == "active_off" else StaffJobPriorities.Level.LOW))
		assert_true(worker.set_job_priorities(priorities))
		var saved_priorities: Dictionary = worker.job_priorities().to_dict()
		var service: SimTask = SimTask.new(&"take_order", &"server", "Nearby service")
		service.priority = 3
		service.steps = [TaskStep.go_to_cell(worker.cell), TaskStep.work(1)] as Array[TaskStep]
		sim.world.board.post(service, sim.world.now)
		if condition == "settled":
			var id: int = int(model.booking["booking_id"])
			assert_true(model.claim_effect(id, GroupBooking.EFFECT_NO_SEAT))
			assert_true(model.claim_effect(id, GroupBooking.EFFECT_REVIEW))
			assert_true(model.settle(id, true))
		elif condition == "wrong_day":
			sim.world.clock.day = 3
		elif condition == "invalid_group":
			# Keep the bus's own physical target but invalidate its held joined group.
			assert_true(sim.world.grid.remove(tables[0].id))
		worker.call("_try_claim", sim.world)
		assert_eq(worker.task, bus if condition == "active_low" else service, condition)
		assert_eq(worker.job_priorities().to_dict(), saved_priorities, "reservation urgency never edits saved choices")
		if condition == "active_low":
			assert_eq(service.state, SimTask.State.OPEN)
		else:
			assert_eq(bus.state, SimTask.State.OPEN, "ordinary/disabled work is not force-claimed")


func test_shared_queue_keeps_spent_patience_and_resumes_once_per_tick_at_the_absolute_cap() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var model: GroupBooking = fixture["model"]
	var tables: Array[PlacedItem] = fixture["tables"]
	assert_true(tables[0].reserve(tables[0].seat_cells[0], 900))
	# Unit admission staging, not an eating/service claim. Use the normal
	# reset API only while MORNING so every queued body is genuinely admitted.
	sim.world.clock.phase = SimClock.Phase.MORNING
	var party: Party = sim.add_booking_party(sim.world.grid.entries()[0], model.booking)
	assert_not_null(party)
	if party == null:
		return
	var guests: Array[CustomerAgent] = PartySeating.members(party, sim.world)
	for guest: CustomerAgent in guests:
		assert_true(sim.world.reset_agent_position(guest, _free_queue_cell(sim.world)))
		assert_true(guest.movement_admitted)
		guest.state = CustomerAgent.State.QUEUED
		guest.queue_patience = 20
	party.queue_started = true
	party.queue_wait = 7
	sim.world.clock.phase = SimClock.Phase.OPEN
	var before: Dictionary = model.to_dict()
	for _guest: CustomerAgent in guests:
		PartySeating.advance_queue(party, sim.world, sim, false)
	assert_eq(party.queue_wait, 7, "grace does not erase previously spent queue patience")
	assert_eq(model.to_dict(), before)
	sim.world.clock.phase_tick = 120 # Exactly slot+30; the group remains occupied.
	sim.world.now += 1
	for _guest: CustomerAgent in guests:
		PartySeating.advance_queue(party, sim.world, sim, false)
	assert_eq(party.queue_wait, 8, "all member callbacks spend exactly one shared tick after the cutoff")
	for guest: CustomerAgent in guests:
		assert_eq(guest._queue_wait, 8)
	sim.world.now += 1
	PartySeating.advance_queue(party, sim.world, sim, false)
	assert_eq(party.queue_wait, 9, "a retry cannot start a new grace window")


func _free_queue_cell(world: SimWorld) -> Vector2i:
	for y: int in world.grid.size.y:
		for x: int in world.grid.size.x:
			var cell: Vector2i = world.grid.origin + Vector2i(x, y)
			if world.grid.is_guest_walkable(cell) and world.grid.dining_table_id(cell) == 0 \
					and world.movement.standing_cell(world, cell):
				var occupied: bool = false
				for agent: SimAgent in world.all_agents():
					occupied = occupied or agent.cell == cell
				if not occupied:
					return cell
	fail("Queue-unit fixture has no free non-dining start")
	return SimGrid.NO_CELL


func test_reserved_bussing_cannot_grant_an_ineligible_worker_a_new_role() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var tables: Array[PlacedItem] = fixture["tables"]
	sim.kitchen.mark_table_dirty(tables[2].id)
	var worker: StaffAgent = StaffAgent.new(&"cook", 3)
	worker.cell = _free_queue_cell(sim.world)
	sim.world.add_agent(worker)
	var ordinary: SimTask = SimTask.new(&"cook", &"cook", "Ordinary cooking")
	ordinary.steps = [TaskStep.go_to_cell(worker.cell), TaskStep.work(1)] as Array[TaskStep]
	sim.world.board.post(ordinary, sim.world.now)
	worker.call("_try_claim", sim.world)
	assert_eq(worker.task, ordinary, "the reservation cannot invent server eligibility")


func test_new_reserved_cleanup_does_not_interrupt_already_claimed_service() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var tables: Array[PlacedItem] = fixture["tables"]
	var worker: StaffAgent = StaffAgent.new(&"server", 3)
	worker.cell = _free_queue_cell(sim.world)
	sim.world.add_agent(worker)
	var service: SimTask = SimTask.new(&"take_order", &"server", "Already serving")
	service.steps = [TaskStep.go_to_cell(worker.cell), TaskStep.work(100)] as Array[TaskStep]
	sim.world.board.post(service, sim.world.now)
	assert_true(sim.world.board.claim(service, worker.id, sim.world.now))
	worker.task = service
	sim.kitchen.mark_table_dirty(tables[2].id)
	worker.tick(sim.world)
	assert_eq(worker.task, service)
	assert_eq(service.state, SimTask.State.CLAIMED)
	assert_eq(sim.world.board.open_tasks().size(), 1, "reserved cleanup waits for an idle eligible worker")


func test_travelling_mop_yields_repeatedly_without_losing_work_or_failure_budget() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var tables: Array[PlacedItem] = fixture["tables"]
	var worker: StaffAgent = StaffAgent.new(&"server", 3)
	worker.cell = _free_queue_cell(sim.world)
	sim.world.add_agent(worker)
	var mop: SimTask = _claimed_mop(sim.world, worker)
	mop.drops = TaskBoard.MAX_DROPS - 1
	var original_id: int = mop.id
	var posted_tick: int = mop.posted_tick
	for _cycle: int in 4:
		sim.kitchen.mark_table_dirty(tables[2].id)
		worker.tick(sim.world)
		assert_eq(mop.state, SimTask.State.OPEN)
		assert_eq(mop.claimed_by, -1)
		assert_eq(mop.claimed_tick, -1)
		assert_eq(mop.drops, TaskBoard.MAX_DROPS - 1)
		assert_eq(mop.posted_tick, posted_tick)
		assert_eq(sim.world.board.get_task(original_id), mop)
		assert_not_null(worker.task)
		if worker.task == null:
			return
		var bus: SimTask = worker.task
		assert_eq(bus.kind, &"bus_table")
		assert_eq(worker.step_index, 0)
		assert_false(worker._step_started, "yielding cannot also run productive bus steps")
		# Isolated claim-cycle control; the Main lifecycle proves actual WORK.
		worker.call("_let_go", sim.world)
		sim.world.board.complete(bus)
		assert_true(sim.world.board.claim(mop, worker.id, sim.world.now))
		worker.task = mop


func test_mop_yield_respects_off_role_stale_work_and_service_controls() -> void:
	for condition: String in ["off", "wrong_role", "settled", "wrong_day", "invalid_group",
			"working", "service", "carrying"]:
		var fixture: Dictionary = _reservation_fixture()
		var sim: RestaurantSim = fixture["sim"]
		var model: GroupBooking = fixture["model"]
		var tables: Array[PlacedItem] = fixture["tables"]
		var worker: StaffAgent = StaffAgent.new(&"cook" if condition == "wrong_role" else &"server", 3)
		worker.cell = _free_queue_cell(sim.world)
		sim.world.add_agent(worker)
		var current: SimTask = _claimed_mop(sim.world, worker)
		if condition == "off":
			var choices: StaffJobPriorities = StaffJobPriorities.new(&"server")
			assert_true(choices.set_priority(&"bussing", StaffJobPriorities.Level.OFF))
			assert_true(worker.set_job_priorities(choices))
		elif condition == "working":
			worker.step_index = 1
			worker._step_started = true
			worker.work_left = 100.0
		elif condition == "service":
			current.kind = &"take_order"
		elif condition == "carrying":
			current.kind = &"deliver"
			current.payload = {"carried_count": 1}
			assert_true(worker.carries_food())
		sim.kitchen.mark_table_dirty(tables[2].id)
		if condition == "settled":
			var id: int = int(model.booking["booking_id"])
			assert_true(model.claim_effect(id, GroupBooking.EFFECT_NO_SEAT))
			assert_true(model.claim_effect(id, GroupBooking.EFFECT_REVIEW))
			assert_true(model.settle(id, true))
		elif condition == "wrong_day":
			sim.world.clock.day = 3
		elif condition == "invalid_group":
			assert_true(sim.world.grid.remove(tables[0].id))
		worker.tick(sim.world)
		assert_eq(worker.task, current, condition)
		assert_eq(current.state, SimTask.State.CLAIMED, condition)
		assert_eq(current.drops, 0, condition)


func test_mid_edge_mop_yield_keeps_physical_ownership_until_the_edge_finishes() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var tables: Array[PlacedItem] = fixture["tables"]
	var worker: StaffAgent = StaffAgent.new(&"server", 3)
	worker.cell = Vector2i(2, 10)
	sim.world.add_agent(worker)
	var mop: SimTask = _claimed_mop(sim.world, worker, Vector2i(12, 10))
	sim.world.advance()
	assert_true(worker.move_progress > 0.0, "the normal navigation step really began")
	var from: Vector2i = worker.cell
	var next: Vector2i = worker.next_cell()
	var progress: float = worker.move_progress
	var position: Vector3 = worker.movement_position()
	sim.kitchen.mark_table_dirty(tables[2].id)
	worker.tick(sim.world)
	assert_eq(mop.state, SimTask.State.OPEN)
	assert_eq(worker.task.kind, &"bus_table")
	assert_eq(worker.cell, from)
	assert_eq(worker.next_cell(), next)
	assert_eq(worker.move_progress, progress, "yielding does not move twice")
	assert_eq(worker.movement_position(), position, "the drawn mid-edge position never jumps")
	assert_true(sim.world.movement.is_stopping(worker.id))
	var snapshot: Dictionary = sim.world.movement.snapshot()
	assert_eq(snapshot["occupied"].get(from, -1), worker.id)
	assert_eq(snapshot["next"].get(next, -1), worker.id)
	assert_eq(worker._held_item_id, 0)
	assert_eq(worker._held_cell, SimGrid.NO_CELL)
	for _tick: int in 12:
		if not sim.world.movement.is_stopping(worker.id):
			break
		sim.world.advance()
	assert_false(sim.world.movement.is_stopping(worker.id))
	assert_eq(worker.cell, next)
	assert_eq(worker.move_progress, 0.0)
	assert_false(worker._step_started, "the bus route waits for the physical stop")
	# The ordinary original server may reclaim the returned mop while this
	# worker finishes its edge. It remains the same live queued/claimed job.
	assert_eq(sim.world.board.get_task(mop.id), mop)
	assert_true(mop.state in [SimTask.State.OPEN, SimTask.State.CLAIMED])
	if mop.state == SimTask.State.CLAIMED:
		assert_true(mop.claimed_by != worker.id, "the yielding worker retained its bus claim")
	assert_eq(mop.drops, 0, "returning to the queue is not a failed attempt")
	assert_eq(mop.posted_tick, 0)


func test_seated_booking_ends_reserved_cleanup_urgency_but_keeps_ordinary_bus_jobs() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var model: GroupBooking = fixture["model"]
	var tables: Array[PlacedItem] = fixture["tables"]
	# Give the real single-file routing time without changing anyone's patience
	# or positions. No food-service result is claimed by this selection test.
	sim.world.clock.open_ticks = 3600
	sim.world.clock.phase_tick = 1080 # The same 11:30 slot, now 12 ticks/minute.
	var party: Party = sim.add_booking_party(sim.world.grid.entries()[0], model.booking)
	assert_not_null(party)
	if party == null:
		return
	for _tick: int in 600:
		if party.seated:
			break
		sim.world.advance()
	assert_true(party.seated, "all six real guests reached their actual reserved seats")
	if not party.seated:
		return
	var group_id: int = int(model.booking["held_group_id"])
	assert_eq(party.table_item_id, group_id, "the party stores the canonical joined-group identity")
	assert_true(PartySeating.booking_valid(party, sim.world))
	sim.kitchen.mark_table_dirty(tables[0].id)
	var hold: BookingSeatHold = sim.world.booking_hold
	var before: Dictionary = model.to_dict()
	assert_false(hold.prioritizes_bussing(sim.world, tables[0].id))
	assert_false(hold.defers_bussing(sim.world, tables[0].id), "a fulfilled booking keeps ordinary cleanup eligibility")
	# Explicit predicate controls: only the exact seated booking/group can end
	# reservation urgency. Restore each field before inspecting live selection.
	party.seated = false
	assert_true(hold.prioritizes_bussing(sim.world, tables[0].id))
	party.seated = true
	party.booking_id += 1
	assert_true(hold.prioritizes_bussing(sim.world, tables[0].id))
	party.booking_id -= 1
	party.booking_owned = false
	assert_true(hold.prioritizes_bussing(sim.world, tables[0].id))
	party.booking_owned = true
	party.table_item_id = -1
	assert_true(hold.prioritizes_bussing(sim.world, tables[0].id))
	party.table_item_id = group_id
	assert_false(hold.prioritizes_bussing(sim.world, tables[0].id))
	assert_eq(model.to_dict(), before, "the priority query never mutates or reselects the hold")
	var worker: StaffAgent = StaffAgent.new(&"server", 3)
	worker.cell = _free_queue_cell(sim.world)
	sim.world.add_agent(worker)
	var mop: SimTask = _claimed_mop(sim.world, worker)
	worker.tick(sim.world)
	assert_eq(worker.task, mop, "a seated booking cannot interrupt navigation to ordinary mopping")
	assert_eq(mop.state, SimTask.State.CLAIMED)
	worker.call("_let_go", sim.world)
	sim.world.board.cancel(mop, &"selection_control_finished")
	var choices: StaffJobPriorities = StaffJobPriorities.new(&"server")
	assert_true(choices.set_priority(&"serving", StaffJobPriorities.Level.HIGH))
	assert_true(choices.set_priority(&"bussing", StaffJobPriorities.Level.LOW))
	assert_true(worker.set_job_priorities(choices))
	var service: SimTask = SimTask.new(&"take_order", &"server", "Ordinary service")
	service.steps = [TaskStep.go_to_cell(worker.cell), TaskStep.work(1)] as Array[TaskStep]
	sim.world.board.post(service, sim.world.now)
	worker.call("_try_claim", sim.world)
	assert_not_null(worker.task)
	if worker.task != null:
		assert_true(worker.task.kind in [&"take_order", &"deliver"],
			"eligible serving work regains its saved priority after seating")
	assert_true(sim.kitchen.is_table_dirty(tables[0].id), "normal cleanup was not removed or completed")
	var has_bus: bool = false
	for task: SimTask in sim.world.board.open_tasks():
		has_bus = has_bus or task.kind == &"bus_table" and task.first_item_id() == tables[0].id
	assert_true(has_bus, "the same ordinary bus job remains available")


func test_open_reserved_bus_jobs_wait_for_prior_diners_then_regain_priority_after_physical_release() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var model: GroupBooking = fixture["model"]
	var tables: Array[PlacedItem] = fixture["tables"]
	var diner: CustomerAgent = _prior_diner_at_seat(sim, tables[2])
	sim.kitchen.mark_dining_group_dirty(tables[0].id)
	var buses: Array[SimTask] = []
	var original: Dictionary[int, Array] = {}
	for task: SimTask in sim.world.board.open_tasks():
		if task.kind == &"bus_table":
			buses.append(task)
			original[task.id] = [task.posted_tick, task.drops]
	assert_eq(buses.size(), 3)
	var before: Dictionary = model.to_dict()
	for table: PlacedItem in tables:
		assert_true(sim.world.booking_hold.defers_bussing(sim.world, table.id), "one occupied member defers the whole joined cleanup")
	assert_eq(model.to_dict(), before, "deferral is a pure observation")
	var worker: StaffAgent = StaffAgent.new(&"server", 3)
	worker.cell = _free_queue_cell(sim.world)
	sim.world.add_agent(worker)
	var choices: StaffJobPriorities = StaffJobPriorities.new(&"server")
	assert_true(choices.set_priority(&"serving", StaffJobPriorities.Level.HIGH))
	assert_true(choices.set_priority(&"bussing", StaffJobPriorities.Level.LOW))
	assert_true(worker.set_job_priorities(choices))
	# Controlled READY-delivery selection, not a claim that a meal was cooked.
	var delivery: SimTask = SimTask.new(&"deliver", &"server", "Ready meal delivery")
	delivery.priority = 3
	delivery.steps = [TaskStep.go_to_cell(worker.cell), TaskStep.work(1000)] as Array[TaskStep]
	sim.world.board.post(delivery, sim.world.now)
	worker.call("_try_claim", sim.world)
	assert_eq(worker.task, delivery, "prior diners' service wins while their table cannot yet stay clean")
	for bus: SimTask in buses:
		assert_eq(bus.state, SimTask.State.OPEN)
		assert_eq(sim.world.board.get_task(bus.id), bus)
	# Unit departure control: normal cleanup defers the reservation until the
	# real body moves off its seat. No payment or full meal is claimed here.
	var seat: Vector2i = diner.seat_cell
	diner._leave(sim.world, sim, &"happy")
	assert_true(sim.world.booking_hold.defers_bussing(sim.world, tables[0].id), "LEAVING alone does not free a physical seat")
	for _tick: int in 12:
		if tables[2].reserved_by(seat) == -1:
			break
		# Advance only this release's physical actor/movement in the selection
		# fixture; other staff must not race the following claim assertion.
		sim.world.now += 1
		sim.world.movement.begin_tick(sim.world)
		diner.tick(sim.world)
	assert_true(diner.cell != seat)
	assert_eq(tables[2].reserved_by(seat), -1)
	for bus: SimTask in buses:
		assert_false(sim.world.booking_hold.defers_bussing(sim.world, bus.first_item_id()))
		assert_true(sim.world.booking_hold.prioritizes_bussing(sim.world, bus.first_item_id()))
		assert_eq(bus.state, SimTask.State.OPEN, "deferral never cancels or completes the real job")
		assert_eq([bus.posted_tick, bus.drops], original[bus.id])
		assert_eq(sim.world.board.get_task(bus.id), bus)
	worker.call("_let_go", sim.world)
	sim.world.board.drop(delivery, &"selection_control")
	worker.call("_try_claim", sim.world)
	assert_true(buses.has(worker.task), "the same reserved bus jobs immediately outrank high service after release")


func test_reserved_bus_deferral_does_not_escape_its_live_group_day_or_role_controls() -> void:
	for condition: String in ["active", "settled", "wrong_day", "before_hold", "invalid_group", "unrelated", "off", "wrong_role"]:
		var fixture: Dictionary = _reservation_fixture([7, 10] as Array[int])
		var sim: RestaurantSim = fixture["sim"]
		var model: GroupBooking = fixture["model"]
		var tables: Array[PlacedItem] = fixture["tables"]
		_prior_diner_at_seat(sim, tables[0])
		var target: PlacedItem = tables[3] if condition == "unrelated" else tables[2]
		sim.kitchen.mark_table_dirty(target.id)
		if condition == "settled":
			var id: int = int(model.booking["booking_id"])
			assert_true(model.claim_effect(id, GroupBooking.EFFECT_NO_SEAT))
			assert_true(model.claim_effect(id, GroupBooking.EFFECT_REVIEW))
			assert_true(model.settle(id, true))
		elif condition == "wrong_day":
			sim.world.clock.day = 3
		elif condition == "before_hold":
			sim.world.clock.phase_tick = 0
		elif condition == "invalid_group":
			assert_true(sim.world.grid.remove(tables[1].id))
		assert_eq(sim.world.booking_hold.defers_bussing(sim.world, target.id), condition in ["active", "off", "wrong_role"], condition)
		var worker: StaffAgent = StaffAgent.new(&"cook" if condition == "wrong_role" else &"server", 3)
		worker.cell = _free_queue_cell(sim.world)
		sim.world.add_agent(worker)
		if condition == "off":
			var choices: StaffJobPriorities = StaffJobPriorities.new(&"server")
			assert_true(choices.set_priority(&"bussing", StaffJobPriorities.Level.OFF))
			assert_true(worker.set_job_priorities(choices))
		if condition in ["off", "wrong_role"]:
			# Check OFF/role independently, after the hold stops deferring.
			sim.world.clock.day = 3
		var bus: SimTask = null
		for candidate: SimTask in sim.world.board.open_tasks():
			if candidate.kind == &"bus_table" and candidate.first_item_id() == target.id:
				bus = candidate
		assert_not_null(bus)
		if bus == null:
			return
		var score: float = worker.call("_score", sim.world, bus)
		assert_eq(score > 0.0, condition in ["settled", "wrong_day", "before_hold", "invalid_group", "unrelated"], condition)


func test_booking_deferral_does_not_preempt_a_bus_claim_made_before_the_hold() -> void:
	var fixture: Dictionary = _reservation_fixture()
	var sim: RestaurantSim = fixture["sim"]
	var tables: Array[PlacedItem] = fixture["tables"]
	_prior_diner_at_seat(sim, tables[0])
	sim.world.clock.phase_tick = 0 # Before the hold starts.
	sim.kitchen.mark_table_dirty(tables[2].id)
	var worker: StaffAgent = StaffAgent.new(&"server", 3)
	worker.cell = _free_queue_cell(sim.world)
	sim.world.add_agent(worker)
	worker.call("_try_claim", sim.world)
	var bus: SimTask = worker.task
	assert_not_null(bus)
	if bus == null:
		return
	assert_eq(bus.kind, &"bus_table")
	sim.world.clock.phase_tick = 90
	assert_true(sim.world.booking_hold.defers_bussing(sim.world, tables[2].id))
	worker.tick(sim.world)
	assert_eq(worker.task, bus, "this change intentionally does not preempt an existing bus claim")
	assert_eq(bus.state, SimTask.State.CLAIMED)
	assert_eq(bus.drops, 0)


func _prior_diner_at_seat(sim: RestaurantSim, table: PlacedItem) -> CustomerAgent:
	# Explicit component-state admission, not a normal-service/meal fixture.
	# Main lifecycle and the unchanged normal soak provide the full-game proof.
	sim.world.clock.phase = SimClock.Phase.MORNING
	var diner: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _rng(31601))
	var seat: Vector2i = table.seat_cells[0]
	assert_true(table.reserve(seat, diner.id))
	assert_true(sim.world.reset_agent_position(diner, seat))
	diner.table_item_id = table.id
	diner.booked_table_ids = sim.world.grid.dining_group_members(table.id)
	diner.seat_cell = seat
	diner.state = CustomerAgent.State.EATING
	sim.world.clock.phase = SimClock.Phase.OPEN
	return diner


func _claimed_mop(world: SimWorld, worker: StaffAgent, target: Vector2i = SimGrid.NO_CELL) -> SimTask:
	var mop: SimTask = SimTask.new(&"clean_spot", &"any", "Mop a floor spot")
	mop.steps = [TaskStep.go_to_cell(worker.cell if target == SimGrid.NO_CELL else target),
		TaskStep.work(100)] as Array[TaskStep]
	world.board.post(mop, world.now)
	assert_true(world.board.claim(mop, worker.id, world.now))
	worker.task = mop
	return mop


func _reservation_fixture(rows: Array[int] = [7]) -> Dictionary:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	layout.placements.clear()
	for placement: ShopPlacement in LAYOUT.placements:
		if content.item(placement.item_id).category != ItemDef.Category.TABLE:
			layout.placements.append(placement.duplicate(true) as ShopPlacement)
	for y: int in rows:
		for x: int in [3, 5, 7]:
			layout.placements.append(_placement(&"cloth_table", Vector2i(x, y)))
			layout.placements.append(_placement(&"chair", Vector2i(x, y - 1), 2))
			layout.placements.append(_placement(&"chair", Vector2i(x, y + 1)))
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, content, 316, errors)
	assert_eq(errors, [] as Array[String])
	var model: GroupBooking = _accepted_for_service_slot(690, 6)
	sim.configure_booking(model)
	sim.world.clock.day = 2
	sim.world.clock.display_open_minute = 600
	sim.world.clock.display_close_minute = 900
	sim.world.clock.open_ticks = 300 # One displayed minute per tick for exact boundary checks.
	assert_true(sim.world.clock.start_service())
	sim.world.clock.phase_tick = 90
	sim.spawner._remaining = 100000
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(sim.world, &"cloth_table")
	assert_eq(tables.size(), 3 * rows.size())
	assert_eq(sim.world.booking_hold.group_for_booking(sim.world, int(model.booking["booking_id"])), tables[0].id)
	return {"sim": sim, "model": model, "tables": tables}


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random


func _placement(id: StringName, origin: Vector2i, turns: int = 0) -> ShopPlacement:
	var value: ShopPlacement = ShopPlacement.new()
	value.item_id = id
	value.origin = origin
	value.quarter_turns = turns
	return value


func _apply(ledger: Ledger, day: int, movement: Dictionary) -> void:
	ledger.record(day, int(movement["amount"]), movement["category"], String(movement["note"]))
