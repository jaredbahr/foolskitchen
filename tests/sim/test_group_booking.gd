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
	assert_false(model.plan_offer(1, 2, menu, 11 * 60, 21 * 60, _provider(seed_value)).is_empty())
	return model


func test_tuning_and_party_limits_keep_walkins_at_six_and_bookings_at_ten() -> void:
	assert_true(TUNING.is_valid())
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
	assert_true(model.plan_offer(1, 1, [&"burger"] as Array[StringName], 660, 1260, provider).is_empty())
	assert_true(model.plan_offer(1, 2, [] as Array[StringName], 660, 1260, provider).is_empty())
	assert_true(model.plan_offer(1, 2, [&"burger"] as Array[StringName], 1200, 1260, provider).is_empty())
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
	first.plan_offer(1, 2, [&"burger"] as Array[StringName], 660, 1260, _provider(202))
	assert_eq(_provider_calls, 0, "the morning is never re-rolled after its first offer")
	var edge: GroupBooking = GroupBooking.new(_certain_tuning())
	var edge_offer: Dictionary = edge.plan_offer(1, 2, [&"burger"] as Array[StringName],
		667, 795, _provider(41))
	assert_eq(edge_offer["slot_minute"], 690, "open 11:07 plus 20-minute hold rounds up to 11:30")
	assert_eq(795 - int(edge_offer["slot_minute"]) - TUNING.slot_minutes, 90,
		"the only slot leaves exactly 90 minutes after the whole slot")
	var too_short: GroupBooking = GroupBooking.new(_certain_tuning())
	_provider_calls = 0
	assert_true(too_short.plan_offer(1, 2, [&"burger"] as Array[StringName],
		667, 794, _provider(42)).is_empty())
	assert_eq(_provider_calls, 0, "a window too short for one legal slot never fetches RNG")


func test_offer_odds_are_about_one_in_four() -> void:
	var offered: int = 0
	for seed: int in range(1, 401):
		var model: GroupBooking = GroupBooking.new(TUNING)
		if not model.plan_offer(seed, 2, [&"burger"] as Array[StringName], 660, 1260,
				_provider(seed * 7919)).is_empty():
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
	assert_true(model.plan_offer(2, 2, [&"burger"] as Array[StringName], 660, 1260, _provider(5)).is_empty())
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
	clock.display_close_minute = 780
	clock.open_ticks = 180
	assert_true(clock.start_service())
	clock.phase_tick = 9 # 10:09; the next tick is exactly the 10:10 T-20 hold boundary.
	var booking_model: GroupBooking = _accepted_for_service_slot(630, 6)
	sim.configure_booking(booking_model)
	sim.spawner._remaining = 100000
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _rng(95))
	guest.state = CustomerAgent.State.QUEUED
	sim.advance()
	var held_id: int = sim.world.booking_hold.group_for_booking(sim.world,
		int(booking_model.booking["booking_id"]))
	assert_true(held_id > 0, "the first T-20 query chooses an actual joined dining group")
	assert_eq(clock.display_minutes(), 610)
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
	var model: GroupBooking = _accepted_for_service_slot(630, 6)
	sim.configure_booking(model)
	sim.world.clock.day = 2
	sim.world.clock.display_open_minute = 600
	sim.world.clock.display_close_minute = 780
	sim.world.clock.open_ticks = 180
	assert_true(sim.world.clock.start_service())
	sim.world.clock.phase_tick = 10
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
	var model: GroupBooking = _accepted_for_service_slot(675, 6)
	sim.configure_booking(model)
	assert_true(clock.start_service())
	clock.phase_tick = 14
	var state_before_booking_spawn: int = sim.rng.state
	sim.advance()
	assert_eq(clock.display_minutes(), 675)
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
		maxi(slot_minute - 30, 0), slot_minute + 120, _provider(921))
	assert_false(offer.is_empty())
	# Pin the slot after a valid deterministic offer; model validation is covered
	# separately and these scenarios exercise the integration clock path.
	model.offer["slot_minute"] = slot_minute
	assert_false(model.accept_offer(1).is_empty())
	return model


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
