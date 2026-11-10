extends TestCase
## SiteThaw (FK-087 step C2): a frozen site's sections aged to a later morning.

const F: int = SiteThawFixture.FROZEN_DAY
const BOOKINGS: BookingTuning = preload("res://data/balance/bookings.tres")
const DEMAND: DemandTuning = preload("res://data/balance/demand.tres")
const RUSH: RushTuning = preload("res://data/balance/rush_hour.tres")
const VIRAL: ViralTuning = preload("res://data/balance/viral.tres")
const SIGNATURE: SignatureTuning = preload("res://data/balance/signature.tres")


func _tunings() -> SiteThawTunings:
	return SiteThawTunings.authored()


func _thaw(sections: Dictionary, today: int, frozen_day: int = F) -> Dictionary:
	return SiteThaw.thaw(sections, frozen_day, today, _tunings())


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func test_every_per_site_section_has_a_decision() -> void:
	for key: String in SiteSections.PER_SITE:
		assert_true(SiteThaw.DECISIONS.has(key), "SiteThaw must decide what thawing does to '%s'" % key)
	for key: String in SiteThaw.DECISIONS:
		assert_true(SiteSections.is_per_site(key), "'%s' is not a per-site section" % key)


func test_the_fixture_is_a_whole_frozen_site() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	assert_eq(sections.size(), SiteSections.PER_SITE.size())
	for key: String in SiteSections.PER_SITE:
		assert_true(sections.get(key) is Dictionary, key)


func test_gap_zero_is_an_exact_copy() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	var result: Dictionary = _thaw(sections, F)
	assert_false(result.is_empty())
	assert_eq(JSON.stringify(result["sections"]), JSON.stringify(sections), "byte for byte")
	assert_true(result["sections"] == sections)
	assert_true((result["refunds"] as Array).is_empty())
	(result["sections"]["demand"] as Dictionary)["renown"] = -1.0
	assert_ne(sections["demand"]["renown"], -1.0, "a detached copy")


func test_the_input_is_never_changed() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	sections["bookings"] = _accepted_booking(F - 1)
	var before: String = JSON.stringify(sections)
	var result: Dictionary = _thaw(sections, F + 4)
	assert_false(result.is_empty())
	assert_eq(JSON.stringify(sections), before)
	(result["sections"]["staff"] as Dictionary)["candidate_day"] = 99.0
	assert_eq(JSON.stringify(sections), before, "the result shares nothing with the input")


func test_a_real_site_three_days_later_passes_the_morning_checks() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	var today: int = F + 3
	var result: Dictionary = _thaw(sections, today)
	assert_false(result.is_empty())
	var out: Dictionary = result["sections"]
	assert_eq(out.size(), sections.size())
	assert_true((result["refunds"] as Array).is_empty(), "an offer is not a booking: nothing to refund")
	# The day conditions of main.gd's _load_autosave_sections.
	var demand: DemandState = DemandState.new()
	assert_true(demand.from_dict(out["demand"]))
	assert_eq(demand.day, today)
	assert_eq(demand.last_decay_day, today)
	assert_true(demand.last_award_day < today)
	assert_true(demand.last_service_factor <= DEMAND.total_cap)
	var viral: ViralReview = ViralReview.new(VIRAL)
	assert_true(viral.from_dict(out["viral"]) and viral.valid_before_morning(today))
	var history: BusinessHistory = BusinessHistory.new()
	assert_true(history.restore(out["business_history"]) and history.valid_before(today))
	var records: ShopRecords = ShopRecords.new()
	assert_true(records.restore(out["shop_records"]) and records.valid_before(today))
	assert_true(SignatureState.new([&"burger", &"grilled_cheese", &"tomato_soup"]).from_dict(
		out["signature"], today, SIGNATURE))
	assert_true(int(out["staff"]["candidate_day"]) <= today)
	assert_true(RushHour.new(RUSH).from_dict(out["rush_hour"], 540, 1320))
	assert_true(GroupBooking.new(BOOKINGS).from_dict(out["bookings"]))
	assert_true(DeliveryBook.new().from_dict(out["deliveries"]))
	assert_true(FoodCritic.new().from_dict(out["critic"]))
	assert_true(InspectionBook.new().from_dict(out["inspection"]))
	assert_true(AquariumCare.valid_dict(out["aquarium"]))
	assert_not_null(Stock.from_dict(out["pantry"]["stock"]))
	var special: DailySpecial = DailySpecial.new()
	assert_true(special.from_dict(out["daily_special"], [], today))
	# Sections without day-bound state come through untouched.
	for key: String in ["shop", "menu", "staff", "plates", "reviews", "regulars", "reorder",
			"cat", "business_history", "shop_records", "signature", "viral", "inspection"]:
		assert_eq(JSON.stringify(out[key]), JSON.stringify(sections[key]), "%s is unchanged" % key)


func test_renown_decays_like_the_mornings_in_between() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	var stepped: DemandState = DemandState.new()
	assert_true(stepped.from_dict(sections["demand"]))
	assert_true(stepped.renown > 0.0)
	for day: int in range(F + 1, F + 6):
		assert_true(stepped.begin_morning(day, DEMAND))
	var jumped: DemandState = DemandState.new()
	assert_true(jumped.from_dict(sections["demand"]))
	assert_true(jumped.begin_morning(F + 5, DEMAND))
	var out: Dictionary = _thaw(sections, F + 5)["sections"]
	# Compared as a save file holds it (JSON keeps 15 significant digits).
	assert_eq(out["demand"], _json(jumped.to_dict()), "one step over the whole gap")
	assert_true(absf(float(out["demand"]["renown"]) - stepped.renown) <= 1e-9 * maxf(1.0, stepped.renown),
		"the same renown as five separate mornings, to rounding")
	assert_eq(int(out["demand"]["last_award_day"]), int(sections["demand"]["last_award_day"]),
		"no close ran while frozen")


func test_a_long_gap_costs_one_step() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	var started: int = Time.get_ticks_msec()
	var out: Dictionary = _thaw(sections, F + 10000000)
	assert_false(out.is_empty())
	assert_true(Time.get_ticks_msec() - started < 2000, "ten million days thaw at once")


func test_demand_frozen_on_another_day_is_refused() -> void:
	var sections: Dictionary = {"demand": _json(DemandState.legacy_for_day(F - 1).to_dict())}
	assert_true(SiteThaw.thaw(sections, F, F, SiteThawTunings.authored()).is_empty())
	assert_true(SiteThaw.thaw(sections, F, F + 2, SiteThawTunings.authored()).is_empty())


func test_a_delivery_day_past_the_32_bit_range_is_refused() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	assert_false((sections["deliveries"]["orders"] as Array).is_empty(), "the fixture has a delivery waiting")
	assert_true(SiteThaw.thaw(sections, F, F + 2147483647, SiteThawTunings.authored()).is_empty())


func test_no_renown_ages_to_today_with_no_work() -> void:
	var sections: Dictionary = {"demand": _json(DemandState.legacy_for_day(F).to_dict())}
	var out: Dictionary = _thaw(sections, 1000000)["sections"]
	assert_eq(int(out["demand"]["day"]), 1000000)
	assert_eq(int(out["demand"]["last_decay_day"]), 1000000)
	assert_eq(float(out["demand"]["renown"]), 0.0)


func test_the_daily_special_clears() -> void:
	var sections: Dictionary = {"daily_special": {"version": 1.0, "day": float(F), "recipe": "burger"}}
	var out: Dictionary = _thaw(sections, F + 1)["sections"]
	assert_eq(out["daily_special"], {"version": 1.0, "day": float(F + 1), "recipe": ""})
	assert_eq(_thaw(sections, F)["sections"], sections, "kept on the same morning")


func test_the_frozen_mornings_rush_and_critic_lapse_but_their_cooldowns_stay() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	assert_eq(sections["rush_hour"]["occasion"], "Local meetup", "the fixture has a rush planned")
	assert_eq(sections["critic"]["pending"], true, "and a critic due")
	var out: Dictionary = _thaw(sections, F + 2)["sections"]
	var rush: RushHour = RushHour.new(RUSH)
	assert_true(rush.from_dict(out["rush_hour"]))
	assert_false(rush.has_event())
	assert_eq(rush.rolled_day, F, "today's morning still rolls")
	assert_eq(rush.last_rush_day, int(sections["rush_hour"]["last_rush_day"]))
	var critic: FoodCritic = FoodCritic.new()
	assert_true(critic.from_dict(out["critic"]))
	assert_false(critic.pending)
	assert_true(critic.tells.is_empty())
	assert_eq(critic.rolled_day, F, "today's morning still rolls")
	assert_eq(critic.last_visit_day, int(sections["critic"]["last_visit_day"]))


func test_a_rush_that_already_ran_keeps_its_cooldown_day() -> void:
	var rush: RushHour = RushHour.new(RUSH)
	rush.rolled_day = F
	rush.last_rush_day = F - 1
	var out: Dictionary = _thaw({"rush_hour": _json(rush.to_dict())}, F + 1)["sections"]
	assert_eq(int(out["rush_hour"]["last_rush_day"]), F - 1)


func test_viral_boost_and_signature_cooldown_are_kept() -> void:
	var viral: ViralReview = ViralReview.new(VIRAL)
	viral.last_close_day = F - 1
	viral.last_trigger_day = F - 1
	viral.days_left = VIRAL.boosted_open_days
	viral.dish = &"burger"
	var signature: SignatureState = SignatureState.new([&"burger"])
	assert_true(signature.record_sale(&"burger", SIGNATURE.signature_unlock_sales))
	assert_true(signature.select(&"burger", F - 1, SimClock.Phase.MORNING, SIGNATURE))
	var sections: Dictionary = {"viral": _json(viral.to_dict()), "signature": _json(signature.to_dict())}
	var out: Dictionary = _thaw(sections, F + 4)["sections"]
	assert_eq(out, sections, "a boost waits for open services; cooldowns run on the calendar")


func test_deliveries_arrive_the_gap_later() -> void:
	var book: DeliveryBook = DeliveryBook.new()
	var lines: Array[Dictionary] = [{"id": &"bun", "qty": 3, "unit_cost": 2}, {"id": &"cheese", "qty": 1, "unit_cost": 5}]
	assert_true(book.place(lines, 11, true, Vector2i(F + 1, DeliveryBook.MORNING)))
	var afternoon: Array[Dictionary] = [{"id": &"bread", "qty": 2, "unit_cost": 1}]
	assert_true(book.place(afternoon, 2, false, Vector2i(F, 40)))
	var out: Dictionary = _thaw({"deliveries": _json(book.to_dict())}, F + 5)["sections"]
	var moved: DeliveryBook = DeliveryBook.new()
	assert_true(moved.from_dict(out["deliveries"]))
	var orders: Array[Dictionary] = moved.orders()
	assert_eq(orders.size(), 2)
	assert_eq(orders[0]["due"], Vector2i(F + 6, DeliveryBook.MORNING))
	assert_eq(orders[1]["due"], Vector2i(F + 5, 40), "this afternoon's delivery")
	assert_eq(moved.paid_total(), 13)
	assert_eq(moved.pending_by_id(), book.pending_by_id())
	assert_eq(orders[0]["standing"], true)


func test_stock_does_not_age_while_frozen() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	var out: Dictionary = _thaw(sections, F + 4)["sections"]
	var before: Dictionary = sections["pantry"]["stock"]["batches"]
	var after: Dictionary = out["pantry"]["stock"]["batches"]
	assert_eq(after.keys(), before.keys())
	for id: String in before:
		assert_eq((after[id] as Array).size(), (before[id] as Array).size())
		for index: int in (before[id] as Array).size():
			assert_eq(int(after[id][index]["bought_day"]), int(before[id][index]["bought_day"]) + 4, id)
			assert_eq(after[id][index]["qty"], before[id][index]["qty"])
			assert_eq(after[id][index]["total_cost"], before[id][index]["total_cost"])
	# A lot one day from spoiling on the frozen morning is still one day away.
	var stock: Stock = Stock.new()
	stock.add(&"lettuce", 2, F - 2, 4)
	assert_true(stock.expire(F, {&"lettuce": 3}).is_empty())
	var thawed: Dictionary = _thaw({"pantry": _json({"stock": stock.to_dict()})}, F + 10)["sections"]
	var aged: Stock = Stock.from_dict(thawed["pantry"]["stock"])
	assert_true(aged.expire(F + 10, {&"lettuce": 3}).is_empty(), "nothing spoiled while frozen")
	assert_eq(aged.expire(F + 11, {&"lettuce": 3}), {&"lettuce": 2}, "it spoils a day after reopening")
	assert_eq(thawed["pantry"]["stock"]["spoilage"], _json(stock.to_dict())["spoilage"],
		"the frozen morning's spoilage receipt keeps its day")


func test_tanks_do_not_cloud_while_frozen() -> void:
	var data: Dictionary = {"version": 1.0, "tanks": [
		{"def_id": "fish_tank", "origin": [2.0, 3.0], "cleaned_day": float(F - 1)}]}
	var out: Dictionary = _thaw({"aquarium": data}, F + 6)["sections"]
	assert_eq(out["aquarium"]["tanks"][0]["cleaned_day"], float(F + 5))
	assert_eq(out["aquarium"]["tanks"][0]["origin"], [2.0, 3.0])


func test_a_booking_on_a_closed_day_lapses_with_its_deposit_refunded() -> void:
	# Accepted on the frozen morning for the next day; reopened two days later.
	var sections: Dictionary = {"bookings": _accepted_booking(F)}
	var deposit: int = int(sections["bookings"]["booking"]["deposit_amount"])
	assert_true(deposit > 0)
	var result: Dictionary = _thaw(sections, F + 2)
	var booking: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(booking.from_dict(result["sections"]["bookings"]))
	assert_false(booking.has_active_booking())
	assert_true(booking.booking.is_empty())
	assert_true(booking.offer.is_empty())
	assert_eq(result["refunds"], [{"amount": -deposit, "category": Ledger.BOOKING_REFUND,
		"note": SiteThaw.REFUND_NOTE}] as Array[Dictionary])
	# A booking for the frozen day itself (accepted the day before) also lapses.
	var today_lapsed: Dictionary = _thaw({"bookings": _accepted_booking(F - 1)}, F + 1)
	assert_eq((today_lapsed["refunds"] as Array).size(), 1)
	assert_true((today_lapsed["sections"]["bookings"]["booking"] as Dictionary).is_empty())


func test_a_booking_for_the_reopening_day_is_kept() -> void:
	var sections: Dictionary = {"bookings": _accepted_booking(F)}
	var result: Dictionary = _thaw(sections, F + 1)
	assert_true((result["refunds"] as Array).is_empty())
	var booking: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(booking.from_dict(result["sections"]["bookings"]))
	assert_true(booking.has_active_booking(), "the party still comes: the site opens today")
	assert_eq(int(booking.booking["service_day"]), F + 1)


func test_a_pending_offer_clears_and_a_settled_booking_stays() -> void:
	var real: Dictionary = SiteThawFixture.sections()["bookings"]
	assert_false((real["offer"] as Dictionary).is_empty())
	var out: Dictionary = _thaw({"bookings": real}, F + 1)["sections"]
	assert_true((out["bookings"]["offer"] as Dictionary).is_empty())
	assert_eq(int(out["bookings"]["planned_day"]), F, "today's morning may offer again")
	var settled: Dictionary = _accepted_booking(F - 1)
	settled["booking"]["status"] = "settled"
	settled["booking"]["effects"] = ["payment", "review"]
	var kept: Dictionary = _thaw({"bookings": settled}, F + 3)
	assert_true((kept["refunds"] as Array).is_empty())
	assert_eq(kept["sections"]["bookings"]["booking"], settled["booking"])
	assert_eq(_thaw({"bookings": {}}, F + 3)["sections"], {"bookings": {}}, "an empty section stays empty")


func test_missing_sections_stay_missing() -> void:
	var sections: Dictionary = {"cat": {"version": 1.0, "adopted": false, "name": "Biscuit"}}
	assert_eq(_thaw(sections, F + 2)["sections"], sections)
	assert_eq(_thaw({}, F + 2), {"sections": {}, "refunds": [] as Array[Dictionary]})


func test_thawing_is_deterministic() -> void:
	var first: Dictionary = _thaw(SiteThawFixture.sections(), F + 7)
	var second: Dictionary = _thaw(SiteThawFixture.sections(), F + 7)
	assert_eq(JSON.stringify(first), JSON.stringify(second))


func test_impossible_days_and_tunings_are_refused() -> void:
	var sections: Dictionary = SiteThawFixture.sections()
	assert_eq(_thaw(sections, F - 1), {}, "today before the frozen day")
	assert_eq(_thaw(sections, 5, 0), {}, "no day zero")
	assert_eq(SiteThaw.thaw(sections, F, F + 1, null), {})
	assert_eq(SiteThaw.thaw(sections, F, F + 1, SiteThawTunings.new()), {})


func test_malformed_sections_are_refused() -> void:
	var cases: Array[Array] = [
		["demand", {"version": 1.0, "day": "soon"}],
		["demand", _json(DemandState.legacy_for_day(F + 1).to_dict())],
		["deliveries", {"version": 1.0, "orders": [{"day": 0.0}]}],
		["pantry", {"stock": 5}],
		["pantry", {"stock": {"batches": {"bun": [{"qty": "x", "bought_day": "1"}]}}}],
		["aquarium", {"version": 1.0, "tanks": [{"def_id": "fish_tank"}]}],
		["bookings", {"version": 1.0, "planned_day": 1.0}],
		["rush_hour", {"version": 1.0}],
		["critic", {"version": 1.0}],
		["viral", {"version": 1.0}],
		["signature", {"version": 1.0}],
		["business_history", {"version": "x"}],
		["shop_records", {"version": "x"}],
		["inspection", {"version": 1.0}],
		["staff", {"candidate_day": float(F + 1)}],
		["daily_special", {"version": 1.0, "day": float(F + 1), "recipe": ""}],
	]
	for row: Array in cases:
		var sections: Dictionary = SiteThawFixture.sections()
		sections[row[0]] = row[1]
		assert_eq(_thaw(sections, F + 2), {}, "%s: %s" % [row[0], JSON.stringify(row[1])])
	var not_a_dictionary: Dictionary = SiteThawFixture.sections()
	not_a_dictionary["menu"] = [1, 2]
	assert_eq(_thaw(not_a_dictionary, F + 2), {})
	var global: Dictionary = SiteThawFixture.sections()
	global["clock"] = {}
	assert_eq(_thaw(global, F + 2), {}, "a frozen site never holds a shared section")
	assert_eq(_thaw(global, F), {}, "not even on the same morning")


## A bookings section with a booking accepted on `offer_day` (service the next
## day), built through GroupBooking's own API from the real offer.
func _accepted_booking(offer_day: int) -> Dictionary:
	var real: Dictionary = SiteThawFixture.sections()["bookings"]
	var offer: Dictionary = real["offer"]
	offer["offer_day"] = float(offer_day)
	offer["service_day"] = float(offer_day + 1)
	var booking: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(booking.from_dict({"version": 1.0, "planned_day": float(offer_day), "offer": offer, "booking": {}}))
	assert_false(booking.accept_offer(offer_day).is_empty())
	return _json(booking.to_dict())
