extends TestCase
## Away sites at the active site's close (FK-087, #408 D2): a managed site's
## earnings formula, a closed site's rent and a lapsing away booking. Pure.

const TUNING: SiteManagerTuning = preload("res://data/balance/site_managers.tres")
const BOOKINGS: BookingTuning = preload("res://data/balance/bookings.tres")


func _rows(profits: Array[int], recorded: bool = true) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in range(profits.size()):
		rows.append({"day": index + 1, "served": 10, "lost": 0, "dish_profit": profits[index],
			"dish_profit_recorded": recorded, "cash_change": profits[index], "reputation": 4.0})
	return rows


func _staff_with_manager(skill: int, id: StringName = &"boss") -> Dictionary:
	var data: Dictionary = StaffRoster.new().to_dict()
	var manager: StaffMember = StaffMember.new()
	manager.id = id
	manager.display_name = "Morgan"
	manager.role = StaffMember.MANAGER
	manager.skill = skill
	manager.wage = 45
	(data["members"] as Array).append(manager.to_dict())
	return JSON.parse_string(JSON.stringify(data))


func _history(profits: Array[int]) -> Dictionary:
	var history: BusinessHistory = BusinessHistory.new()
	for row: Dictionary in _rows(profits):
		history._days.append(row)
	return JSON.parse_string(JSON.stringify(history.capture()))


func _accepted_booking(day: int) -> Dictionary:
	var offer: Dictionary = SiteThawFixture.sections()["bookings"]["offer"]
	offer["offer_day"] = float(day - 1)
	offer["service_day"] = float(day)
	var booking: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(booking.from_dict({"version": 1.0, "planned_day": float(day - 1), "offer": offer, "booking": {}}))
	assert_false(booking.accept_offer(day - 1).is_empty())
	return JSON.parse_string(JSON.stringify(booking.to_dict()))


func test_the_authored_tuning_is_valid() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.hire_tier, 3)
	assert_almost_eq(TUNING.rate_for(1), 0.70)
	assert_almost_eq(TUNING.rate_for(3), 0.85)
	assert_almost_eq(TUNING.rate_for(5), 1.00)
	assert_almost_eq(TUNING.rate_for(0), 0.70, 0.0001, "skill clamps to 1..5")
	assert_almost_eq(TUNING.rate_for(9), 1.00)


func test_no_history_earns_nothing() -> void:
	assert_eq(AwaySites.earnings([] as Array[Dictionary], 5, TUNING), 0)
	assert_eq(AwaySites.earnings(_rows([90, 120], false), 5, TUNING), 0,
		"rows without a recorded dish profit do not count")
	assert_eq(AwaySites.earnings_from_section({}, 5, TUNING), 0)


func test_one_row_is_the_mean() -> void:
	assert_eq(AwaySites.earnings(_rows([100]), 1, TUNING), 70)
	assert_eq(AwaySites.earnings(_rows([100]), 3, TUNING), 85)
	assert_eq(AwaySites.earnings(_rows([100]), 5, TUNING), 100)


func test_seven_rows_use_all_of_them() -> void:
	# Mean 40.
	var profits: Array[int] = [10, 20, 30, 40, 50, 60, 70]
	assert_eq(AwaySites.earnings(_rows(profits), 1, TUNING), 28)
	assert_eq(AwaySites.earnings(_rows(profits), 3, TUNING), 34)
	assert_eq(AwaySites.earnings(_rows(profits), 5, TUNING), 40)


func test_ten_rows_use_the_last_seven_recorded() -> void:
	# The last seven are 40..100 (mean 70); the first three are ignored.
	var profits: Array[int] = [1000, 1000, 1000, 40, 50, 60, 70, 80, 90, 100]
	assert_eq(AwaySites.earnings(_rows(profits), 5, TUNING), 70)
	assert_eq(AwaySites.earnings(_rows(profits), 1, TUNING), 49)
	# An unrecorded day in the window is skipped, reaching one row further back.
	var rows: Array[Dictionary] = _rows(profits)
	rows[9]["dish_profit_recorded"] = false
	rows[9]["dish_profit"] = 0
	# Now 1000, 40..90: (1000 + 390) / 7 = 198.57...
	assert_eq(AwaySites.earnings(rows, 5, TUNING), 199)


func test_the_cap_is_the_mean() -> void:
	var generous: SiteManagerTuning = TUNING.duplicate()
	generous.rate_at_skill_1 = 1.0
	generous.rate_at_skill_5 = 1.0
	assert_eq(AwaySites.earnings(_rows([33, 34]), 5, generous), 34, "33.5 rounds, never above the mean")
	assert_eq(AwaySites.earnings(_rows([33, 34]), 1, TUNING), 23, "0.7 x 33.5 = 23.45")


func test_a_negative_mean_is_paid_as_a_whole_loss() -> void:
	# min(rate x mean, mean) takes the mean when it is negative: a manager
	# never does better than the owner did in person.
	assert_eq(AwaySites.earnings(_rows([-40, -20]), 1, TUNING), -30)
	assert_eq(AwaySites.earnings(_rows([-40, -20]), 5, TUNING), -30)
	assert_eq(AwaySites.earnings(_rows([-100, 40]), 3, TUNING), -30)


func test_earnings_are_deterministic() -> void:
	var rows: Array[Dictionary] = _rows([17, 23, 5, 81, -9, 44, 60, 13])
	var first: int = AwaySites.earnings(rows, 2, TUNING)
	for repeat: int in 5:
		assert_eq(AwaySites.earnings(rows.duplicate(true), 2, TUNING), first)
	var section: Dictionary = _history([17, 23, 5, 81, -9, 44, 60, 13])
	assert_eq(AwaySites.earnings_from_section(section, 2, TUNING), first, "the saved section reads the same")


func test_manager_skill_needs_a_manager_in_that_roster() -> void:
	var staff: Dictionary = _staff_with_manager(4)
	assert_eq(AwaySites.manager_skill(staff, &"boss"), 4)
	assert_eq(AwaySites.manager_skill(staff, &"starter_cook"), 0, "a cook is no manager")
	assert_eq(AwaySites.manager_skill(staff, &"nobody"), 0)
	assert_eq(AwaySites.manager_skill(staff, &""), 0)
	assert_eq(AwaySites.manager_skill({}, &"boss"), 0)


func _lot(id: StringName, rent: int, expanded_rent: int) -> LotDef:
	var lot: LotDef = LotDef.new()
	lot.id = id
	lot.daily_rent = rent
	lot.expansion_price = 500
	lot.expanded_daily_rent = expanded_rent
	return lot


func test_rent_is_the_home_rule_or_the_lots_own() -> void:
	var pier: LotDef = _lot(&"pier_lot", 70, 95)
	assert_eq(AwaySites.lot_rent(SiteBook.HOME_LOT, 40), 40)
	assert_eq(AwaySites.lot_rent(SiteBook.HOME_LOT, 40, pier, true), 40, "home keeps its own rule")
	assert_eq(AwaySites.lot_rent(&"pier_lot", 40, pier, false), 70)
	assert_eq(AwaySites.lot_rent(&"pier_lot", 40, pier, true), 95, "an expanded lease pays the expanded rent")
	assert_eq(AwaySites.lot_rent(&"pier_lot", 40), AwaySites.UNKNOWN_RENT, "a lot missing from the data")
	assert_eq(AwaySites.lot_rent(&"roof_lot", 40, pier, false), AwaySites.UNKNOWN_RENT, "never another lot's rent")


func test_an_away_lot_site_pays_its_lots_rent_normal_and_expanded() -> void:
	var lots: Array[LotDef] = [_lot(&"pier_lot", 70, 95), _lot(&"roof_lot", 120, 160)]
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "Pier Shack", 3, {"shop": {"lease_expanded": false}}))
	assert_true(book.add_site(&"rooftop", &"roof_lot", "Sky Bar", 3, {"shop": {"lease_expanded": true}}))
	var plans: Array[Dictionary] = AwaySites.plan_close(book, 4, 40, TUNING, BOOKINGS, lots)
	assert_eq(plans.size(), 2)
	assert_true(bool(plans[0]["rent_known"]))
	assert_eq(int(plans[0]["amount"]), -70)
	assert_eq(JSON.stringify(plans[0]["movements"]), JSON.stringify([{"amount": -70,
		"category": Ledger.AWAY_SITE_RENT, "note": AwaySites.RENT_NOTE}]))
	assert_eq(AwaySites.report_line("Pier Shack", plans[0]), "Pier Shack (closed): rent -$70")
	assert_eq(int(plans[1]["amount"]), -160, "its own lease is expanded")
	assert_eq(AwaySites.report_line("Sky Bar", plans[1]), "Sky Bar (closed): rent -$160")


func test_a_renovating_site_pays_rent_even_with_a_manager() -> void:
	var lots: Array[LotDef] = [_lot(&"pier_lot", 70, 95)]
	var book: SiteBook = SiteBook.new()
	var sections: Dictionary = {"staff": _staff_with_manager(5), "business_history": _history([60, 80])}
	assert_true(book.add_site(&"harbour", &"pier_lot", "Pier Shack", 3, sections, 2))
	assert_true(book.set_manager(&"harbour", &"boss"))
	var plan: Dictionary = AwaySites.plan_close(book, 3, 40, TUNING, BOOKINGS, lots)[0]
	assert_eq(plan["status"], AwaySites.CLOSED, "it cannot open, so no manager runs it")
	assert_eq(int(plan["amount"]), -70)
	assert_eq(book.count_down_renovations(), [] as Array[StringName])
	assert_eq(AwaySites.plan_close(book, 4, 40, TUNING, BOOKINGS, lots)[0]["status"], AwaySites.CLOSED,
		"its last renovation day is still closed (planned before the countdown)")
	assert_eq(book.count_down_renovations(), [&"harbour"] as Array[StringName])
	var ready: Dictionary = AwaySites.plan_close(book, 5, 40, TUNING, BOOKINGS, lots)[0]
	assert_eq(ready["status"], AwaySites.MANAGED, "once ready, its manager runs it")
	assert_eq(int(ready["amount"]), 70)


func test_a_booking_lapses_on_its_day_with_the_deposit() -> void:
	var section: Dictionary = _accepted_booking(6)
	var deposit: int = int(section["booking"]["deposit_amount"])
	assert_true(deposit > 0)
	assert_true(AwaySites.lapse_booking(section, 5, BOOKINGS).is_empty(), "not before its day")
	var lapsed: Dictionary = AwaySites.lapse_booking(section, 6, BOOKINGS)
	assert_eq(int(lapsed["refund"]), deposit)
	var after: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(after.from_dict(lapsed["section"]), "the rewritten section still loads")
	assert_false(after.has_active_booking())
	assert_eq(after.planned_day, 5, "the frozen planned day is kept")
	assert_true(AwaySites.lapse_booking(lapsed["section"], 6, BOOKINGS).is_empty(), "only once")
	assert_true(AwaySites.lapse_booking({}, 6, BOOKINGS).is_empty())


func test_a_close_plans_each_inactive_site() -> void:
	var book: SiteBook = SiteBook.new()
	var managed: Dictionary = {"staff": _staff_with_manager(5), "business_history": _history([60, 80])}
	assert_true(book.add_site(&"harbour", &"pier_lot", "Pier Shack", 3, managed))
	assert_true(book.set_manager(&"harbour", &"boss"))
	assert_true(book.add_site(&"rooftop", &"roof_lot", "Sky Bar", 3, {"bookings": _accepted_booking(4)}))
	var plans: Array[Dictionary] = AwaySites.plan_close(book, 4, 40, TUNING, BOOKINGS)
	assert_eq(plans.size(), 2, "the active home site is not planned")
	assert_eq(plans[0]["site"], &"harbour")
	assert_eq(plans[0]["status"], AwaySites.MANAGED)
	assert_eq(int(plans[0]["amount"]), 70)
	assert_eq(JSON.stringify(plans[0]["movements"]), JSON.stringify([{"amount": 70,
		"category": Ledger.AWAY_SITE_INCOME, "note": AwaySites.INCOME_NOTE}]))
	assert_eq(AwaySites.report_line("Pier Shack", plans[0]), "Pier Shack (managed): +$70")
	assert_eq(plans[1]["status"], AwaySites.CLOSED)
	assert_false(bool(plans[1]["rent_known"]), "no lot data passed: no rent source")
	var refund: int = int(plans[1]["refund"])
	assert_true(refund > 0)
	assert_eq(JSON.stringify(plans[1]["movements"]), JSON.stringify([{"amount": -refund,
		"category": Ledger.BOOKING_REFUND, "note": SiteThaw.REFUND_NOTE}]), "rent unknown: only the refund")
	assert_true(plans[1].has("bookings"))
	assert_eq(AwaySites.report_line("Sky Bar", plans[1]),
		"Sky Bar (closed): no rent charged; a group booking there was refunded (-$%d)" % refund)
	assert_eq(JSON.stringify(AwaySites.plan_close(book, 4, 40, TUNING, BOOKINGS)), JSON.stringify(plans),
		"planning changes nothing and repeats exactly")


func test_an_unmanaged_home_site_pays_its_rent() -> void:
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "Pier Shack", 3, {}))
	assert_true(book.swap_active(&"harbour", 3, {"staff": _staff_with_manager(3),
		"menu": {"name": "Fool's Kitchen"}}))
	var plans: Array[Dictionary] = AwaySites.plan_close(book, 3, 40, TUNING, BOOKINGS)
	assert_eq(plans.size(), 1)
	assert_eq(plans[0]["site"], SiteBook.HOME_ID)
	assert_eq(plans[0]["status"], AwaySites.CLOSED, "a manager on the roster but not assigned")
	assert_eq(int(plans[0]["amount"]), -40)
	assert_eq(AwaySites.display_name(book, SiteBook.HOME_ID), "Fool's Kitchen", "named from its menu")
	assert_eq(AwaySites.report_line("Fool's Kitchen", plans[0]), "Fool's Kitchen (closed): rent -$40")
	# A manager id that is not a Manager in that roster does not run it.
	assert_true(book.set_manager(SiteBook.HOME_ID, &"starter_cook"))
	assert_eq(AwaySites.plan_close(book, 3, 40, TUNING, BOOKINGS)[0]["status"], AwaySites.CLOSED)
	assert_true(book.set_manager(SiteBook.HOME_ID, &"boss"))
	var managed: Dictionary = AwaySites.plan_close(book, 3, 40, TUNING, BOOKINGS)[0]
	assert_eq(managed["status"], AwaySites.CLOSED, "no history: nothing to go on, so it stays closed")
	assert_eq(int(managed["amount"]), -40, "and pays its rent")
	assert_eq(JSON.stringify(managed["movements"]), JSON.stringify([{"amount": -40,
		"category": Ledger.AWAY_SITE_RENT, "note": AwaySites.RENT_NOTE}]))
	assert_eq(AwaySites.report_line("Fool's Kitchen", managed),
		"Fool's Kitchen (closed until you run it for a day): rent -$40")


func test_a_managed_lot_needs_a_recorded_day_before_its_manager_runs_it() -> void:
	var lots: Array[LotDef] = [_lot(&"pier_lot", 70, 95)]
	var book: SiteBook = SiteBook.new()
	var unrecorded: BusinessHistory = BusinessHistory.new()
	for row: Dictionary in _rows([0], false):
		unrecorded._days.append(row)
	var sections: Dictionary = {"staff": _staff_with_manager(5),
		"business_history": JSON.parse_string(JSON.stringify(unrecorded.capture()))}
	assert_true(book.add_site(&"harbour", &"pier_lot", "Pier Shack", 3, sections))
	assert_true(book.set_manager(&"harbour", &"boss"))
	assert_eq(AwaySites.recorded_days(sections["business_history"]), 0)
	var plan: Dictionary = AwaySites.plan_close(book, 4, 40, TUNING, BOOKINGS, lots)[0]
	assert_eq(plan["status"], AwaySites.CLOSED, "only unrecorded days: still nothing to go on")
	assert_eq(int(plan["amount"]), -70)
	assert_true(bool(plan.get("no_history", false)))
	assert_eq(AwaySites.recorded_days(_history([60, 80])), 2)


func test_set_frozen_section_keeps_the_frozen_day() -> void:
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"harbour", &"pier_lot", "", 3, {"bookings": {}}))
	assert_true(book.set_frozen_section(&"harbour", "bookings", {"version": 1}))
	assert_eq(book.frozen_day(&"harbour"), 3)
	assert_eq(JSON.stringify(book.frozen_sections(&"harbour")["bookings"]), JSON.stringify({"version": 1.0}))
	assert_false(book.set_frozen_section(SiteBook.HOME_ID, "bookings", {}), "not the active site")
	assert_false(book.set_frozen_section(&"harbour", "owner", {}), "only per-site sections")
	assert_false(book.set_frozen_section(&"nowhere", "bookings", {}))
