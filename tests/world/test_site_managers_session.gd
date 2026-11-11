extends TestCase
## Managers and away sites in a real session (FK-087, #408 D2): a manager is
## hired and assigned at the home site, the owner switches to a second site,
## and that site's close pays the home site's away earnings (or rent) and
## lapses its booking, all booked to the home site's own books.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "site_managers_session"
const BOOKINGS: BookingTuning = preload("res://data/balance/bookings.tres")
const ECONOMY: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const MANAGER_ID: StringName = &"candidate_manager"
var _main: Node
var _old_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _book() -> SiteBook:
	return _main.get("site_book")


func _roster() -> StaffRoster:
	return _main.get("staff_roster")


func _owner() -> OwnerProgress:
	return _main.get("owner_progress")


## Day 3 of a new game, with two recorded home days (dish profit 100 and 300)
## and a second site frozen this morning from the home site's sections.
func _two_sites() -> int:
	_start()
	for step: int in 2:
		reset_weekly_for_synthetic_day_jump(_main)
		Clock.sim.day += 1
		_main.call("_begin_morning")
	var day: int = Clock.sim.day
	assert_true(_book().add_site(&"second", &"second_lot", "Second", day,
		SaveSystem.capture_sections(SiteSections.PER_SITE)))
	var history: BusinessHistory = _main.get("business_history")
	var rows: Array[Dictionary] = []
	for row: Array in [[day - 2, "100"], [day - 1, "300"]]:
		rows.append({"day": row[0], "served": 20, "lost": 1, "dish_profit": row[1],
			"dish_profit_recorded": true, "cash_change": row[1], "reputation": 4.0})
	assert_true(history.restore({"version": 1, "days": rows}))
	return day


## Puts a skill-3 Manager in this morning's candidate pool.
func _offer_manager() -> void:
	var data: Dictionary = _roster().to_dict()
	var manager: StaffMember = StaffMember.new()
	manager.id = MANAGER_ID
	manager.display_name = "Morgan"
	manager.role = StaffMember.MANAGER
	manager.skill = 3
	manager.wage = ECONOMY.staff_wage(StaffMember.MANAGER, 3)
	# The pool is full (three a morning): the manager takes the last place.
	var pool: Array = data["candidates"]
	if pool.size() >= StaffRoster.CANDIDATE_COUNT:
		pool.pop_back()
	pool.append(manager.to_dict())
	var roster: StaffRoster = StaffRoster.new(ECONOMY)
	assert_true(roster.from_dict(JSON.parse_string(JSON.stringify(data))))
	_main.set("staff_roster", roster)


func _hire_and_assign_manager() -> void:
	_offer_manager()
	assert_false(_main.call("staff_hire", MANAGER_ID), "no manager hire below Tier 3")
	_owner().career_tier = 3
	assert_true(_main.call("staff_hire", MANAGER_ID), "hired at Tier 3")
	assert_false(_main.call("assign_site_manager", &"starter_cook"), "a cook cannot manage")
	assert_false(_main.call("assign_site_manager", &"nobody"))
	assert_true(_main.call("assign_site_manager", MANAGER_ID))
	assert_eq(_main.call("site_manager"), MANAGER_ID)


func _play_to_close(day: int) -> DayReport:
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = _main.get("shown_report")
	assert_true(report != null and report.day == day)
	return report


func _entries(day: int, site: StringName, category: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in Economy.ledger.entries_for_day(day, site):
		if entry["category"] == category:
			found.append(entry)
	return found


func _operating(day: int, site: StringName) -> int:
	var total: int = 0
	for entry: Dictionary in Economy.ledger.entries_for_day(day, site):
		if not DayReport.NON_OPERATING_CATEGORIES.has(entry["category"]):
			total += int(entry["amount"])
	return total


func _assert_report_excludes_away(report: DayReport, msg: String) -> void:
	for category: StringName in [Ledger.AWAY_SITE_INCOME, Ledger.AWAY_SITE_RENT, Ledger.BOOKING_REFUND]:
		assert_false(report.income.has(category) or report.costs.has(category), "%s: no %s" % [msg, category])


func test_a_managed_home_site_earns_at_the_second_sites_close() -> void:
	var day: int = _two_sites()
	_hire_and_assign_manager()
	assert_true(_main.call("switch_site", &"second"))
	assert_eq(_book().manager(SiteBook.HOME_ID), MANAGER_ID, "the home row keeps its manager")
	# The assignment is saved: the switch's autosave reloads with it.
	_close()
	_start()
	assert_eq(_book().active_id, &"second")
	assert_eq(_book().manager(SiteBook.HOME_ID), MANAGER_ID, "a reload keeps the manager")
	# Mean of 100 and 300 at skill 3: 0.85 x 200.
	var expected: int = 170
	var cash_before: int = Economy.cash
	var report: DayReport = _play_to_close(day)
	var income: Array[Dictionary] = _entries(day, SiteBook.HOME_ID, Ledger.AWAY_SITE_INCOME)
	assert_eq(income.size(), 1, "one away payment")
	assert_eq(int(income[0]["amount"]), expected)
	assert_eq(_entries(day, SiteBook.HOME_ID, Ledger.AWAY_SITE_RENT).size(), 0, "a managed site pays no rent")
	assert_eq(_entries(day, SiteBook.HOME_ID, Ledger.WAGES).size(), 0, "nor wages: the mean is net")
	assert_eq(Economy.cash - cash_before, Economy.ledger.day_profit(day, &"second") + expected,
		"the owner's cash is the second site's day plus the away income")
	_assert_report_excludes_away(report, "the active report")
	assert_eq(report.away_site_lines, ["Fool's Kitchen (managed): +$170"] as Array[String])
	var history: Array[Dictionary] = (_main.get("business_history") as BusinessHistory).recent(1)
	assert_eq(int(history[0]["day"]), day)
	assert_eq(int(history[0]["cash_change"]), report.profit(), "the second site's history leaves it out")
	assert_eq(report.profit(), Economy.ledger.day_profit(day, &"second"))
	var award: Dictionary = _main.get("_owner_award_today")
	var tuning: ProgressionTuning = _owner().tuning
	if not award.is_empty():
		assert_eq(int(award["profit_xp"]), maxi(0, _operating(day, &"second")) / tuning.profit_step
			* tuning.profit_step_xp, "XP reads only the second site's profit")
	# The home site's own history gained no away day.
	var home_history: Dictionary = _book().frozen_sections(SiteBook.HOME_ID)["business_history"]
	assert_eq((home_history["days"] as Array).size(), 2, "away days are never written into history")


func test_an_unmanaged_home_site_pays_only_its_rent() -> void:
	var day: int = _two_sites()
	_owner().career_tier = 3
	_offer_manager()
	assert_true(_main.call("staff_hire", MANAGER_ID))
	# Hired but not assigned: the home site stays closed.
	assert_true(_main.call("switch_site", &"second"))
	var rent: int = _main.call("_home_rent")
	assert_true(rent > 0)
	var report: DayReport = _play_to_close(day)
	var charged: Array[Dictionary] = _entries(day, SiteBook.HOME_ID, Ledger.AWAY_SITE_RENT)
	assert_eq(charged.size(), 1)
	assert_eq(int(charged[0]["amount"]), -rent)
	assert_eq(_entries(day, SiteBook.HOME_ID, Ledger.AWAY_SITE_INCOME).size(), 0)
	_assert_report_excludes_away(report, "the active report")
	assert_eq(report.away_site_lines, ["Fool's Kitchen (closed): rent -$%d" % rent] as Array[String])


func test_an_away_booking_lapses_at_the_close_with_its_deposit() -> void:
	var day: int = _two_sites()
	assert_true(_main.call("switch_site", &"second"))
	# The home site had accepted yesterday a booking for today, the day the
	# owner is at the second site.
	var offer: Dictionary = SiteThawFixture.sections()["bookings"]["offer"]
	offer["offer_day"] = float(day - 1)
	offer["service_day"] = float(day)
	var booking: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(booking.from_dict({"version": 1.0, "planned_day": float(day - 1), "offer": offer, "booking": {}}))
	assert_false(booking.accept_offer(day - 1).is_empty())
	var deposit: int = int(booking.booking["deposit_amount"])
	assert_true(deposit > 0)
	assert_true(_book().set_frozen_section(SiteBook.HOME_ID, "bookings", booking.to_dict()))
	var report: DayReport = _play_to_close(day)
	var refunds: Array[Dictionary] = _entries(day, SiteBook.HOME_ID, Ledger.BOOKING_REFUND)
	assert_eq(refunds.size(), 1)
	assert_eq(int(refunds[0]["amount"]), -deposit)
	_assert_report_excludes_away(report, "the active report")
	var lapsed: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(lapsed.from_dict(_book().frozen_sections(SiteBook.HOME_ID)["bookings"]))
	assert_false(lapsed.has_active_booking(), "the frozen booking is gone")
	assert_true(report.away_site_lines[0].ends_with("a group booking there was refunded (-$%d)" % deposit))
	# Back home the next morning: the thaw finds nothing more to refund.
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.day, day + 1)
	assert_true(_main.call("switch_site", SiteBook.HOME_ID))
	assert_eq(Economy.ledger.day_totals(day + 1).get(Ledger.BOOKING_REFUND, 0), 0, "refunded once")
	assert_false((_main.get("group_booking") as GroupBooking).has_active_booking())


func test_letting_the_manager_go_clears_the_assignment() -> void:
	_two_sites()
	_hire_and_assign_manager()
	assert_true(_main.call("staff_let_go", MANAGER_ID))
	assert_eq(_main.call("site_manager"), &"", "a manager who left no longer runs the site")
	assert_true(_main.call("switch_site", &"second"))
	assert_eq(_book().manager(SiteBook.HOME_ID), &"")


func test_one_site_has_no_away_lines() -> void:
	_start()
	var day: int = Clock.sim.day
	var report: DayReport = _play_to_close(day)
	assert_true(report.away_site_lines.is_empty())
	assert_false(report.to_dict().has("away_site_lines"), "a one-site report keeps its shape")
	for category: StringName in [Ledger.AWAY_SITE_INCOME, Ledger.AWAY_SITE_RENT]:
		assert_eq(Economy.ledger.day_totals(day).get(category, 0), 0)
