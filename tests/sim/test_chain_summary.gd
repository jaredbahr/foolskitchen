extends TestCase
## The chain view's facts per site and the chain-wide figures
## (docs/CITY_MAP.md sections 4 to 6): ChainSummary and ChainStats. Pure: a
## SiteBook, a ledger and real saved sections (SiteThawFixture), no session.

const TUNING: SiteManagerTuning = preload("res://data/balance/site_managers.tres")
const BOOKINGS: BookingTuning = preload("res://data/balance/bookings.tres")
const DAY: int = 5
const HOME_RENT: int = 60


func _lots() -> Array[LotDef]:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all(), PackedStringArray())
	return db.lots()


## The fixture's sections (two in-person days: dish profit 35 and 49, a cook
## and a server at mood 3), with a Manager of `skill` added when above 0.
func _sections(skill: int = 0) -> Dictionary:
	var sections: Dictionary = SiteThawFixture.sections()
	sections["bookings"] = {}
	if skill > 0:
		var manager: StaffMember = StaffMember.new()
		manager.id = &"boss"
		manager.display_name = "Morgan"
		manager.role = StaffMember.MANAGER
		manager.skill = skill
		manager.wage = 45
		(sections["staff"]["members"] as Array).append(JSON.parse_string(JSON.stringify(manager.to_dict())))
	return sections


func _book() -> SiteBook:
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"beachfront_boardwalk", &"beachfront_boardwalk", "Pier Shack", 3, _sections(3)))
	assert_true(book.set_manager(&"beachfront_boardwalk", &"boss"))
	assert_true(book.add_site(&"seaside_cliff", &"seaside_cliff", "", 3, _sections()))
	assert_true(book.add_site(&"town_fixer_upper", &"town_fixer_upper", "Old Mill", 3, {"staff": {}}, 2))
	return book


func _build(book: SiteBook, ledger: Ledger = Ledger.new(), active: Dictionary = _sections()) -> Array[ChainSummary.Site]:
	return ChainSummary.build(book, active, "Fool's Kitchen", ledger, DAY, HOME_RENT, TUNING, BOOKINGS, _lots())


func _by_id(sites: Array[ChainSummary.Site], id: StringName) -> ChainSummary.Site:
	for site: ChainSummary.Site in sites:
		if site.id == id:
			return site
	fail("no site %s" % id)
	return ChainSummary.Site.new()


func test_one_site_per_site_active_first() -> void:
	var sites: Array[ChainSummary.Site] = _build(_book())
	var ids: Array[StringName] = []
	for site: ChainSummary.Site in sites:
		ids.append(site.id)
	assert_eq(ids, [&"home", &"beachfront_boardwalk", &"seaside_cliff", &"town_fixer_upper"] as Array[StringName])
	assert_eq(ChainSummary.build(null, {}, "", null, DAY, HOME_RENT, TUNING, BOOKINGS).size(), 0)


func test_the_active_site() -> void:
	var ledger: Ledger = Ledger.new()
	ledger.record(DAY - 1, 300, Ledger.SALE, "", &"home")
	ledger.record(DAY - 1, 20, Ledger.TIP, "", &"home")
	ledger.record(DAY - 1, -40, Ledger.INGREDIENTS, "", &"home")
	ledger.record(DAY, 99, Ledger.SALE, "", &"home")
	var home: ChainSummary.Site = _by_id(_build(_book(), ledger), &"home")
	assert_eq(home.status, ChainSummary.Status.HERE)
	assert_true(home.is_active())
	assert_eq(home.name, "Fool's Kitchen", "the live menu's name")
	assert_eq(home.yesterday_takings, 320, "gross sales and tips, yesterday only")
	assert_eq(home.tonight, 0)
	assert_true(home.staffed)
	assert_eq(home.recorded_days, 2)
	assert_eq(home.recent_mean, 42, "mean of 35 and 49")
	assert_almost_eq(home.mood, 3.0)
	assert_eq(home.alerts, [] as Array[ChainSummary.Alert], "the home shop is never 'ready to open'")


func test_a_managed_away_site_previews_tonight_exactly() -> void:
	var book: SiteBook = _book()
	var ledger: Ledger = Ledger.new()
	ledger.record(DAY - 1, 36, Ledger.AWAY_SITE_INCOME, "", &"beachfront_boardwalk")
	var pier: ChainSummary.Site = _by_id(_build(book, ledger), &"beachfront_boardwalk")
	assert_eq(pier.status, ChainSummary.Status.MANAGED)
	assert_eq(pier.name, "Pier Shack")
	assert_eq(pier.manager_name, "Morgan")
	assert_eq(pier.manager_skill, 3)
	assert_almost_eq(pier.manager_rate, 0.85)
	assert_eq(pier.yesterday_earnings, 36)
	assert_eq(pier.yesterday_takings, 0)
	assert_eq(pier.tonight, AwaySites.earnings_from_section(_sections()["business_history"], 3, TUNING))
	assert_eq(pier.tonight, 36, "0.85 of the mean 42, rounded")
	var plans: Array[Dictionary] = AwaySites.plan_close(book, DAY, HOME_RENT, TUNING, BOOKINGS, _lots())
	assert_eq(plans[0]["site"], &"beachfront_boardwalk")
	assert_eq(int(plans[0]["amount"]), pier.tonight, "the same figure the close books")
	assert_eq(pier.alerts, [] as Array[ChainSummary.Alert])


func test_a_closed_away_site_without_a_manager() -> void:
	var cliff: ChainSummary.Site = _by_id(_build(_book()), &"seaside_cliff")
	assert_eq(cliff.status, ChainSummary.Status.CLOSED)
	assert_eq(cliff.name, "Fool's Kitchen", "no own name: the frozen menu's name")
	assert_eq(cliff.manager_skill, 0)
	assert_eq(cliff.manager_name, "")
	var rent: int = 0
	for lot: LotDef in _lots():
		if lot.id == &"seaside_cliff":
			rent = lot.rent(false)
	assert_true(rent > 0)
	assert_eq(cliff.tonight, -(rent + 55), "rent and the cook's and server's wages")
	assert_eq(cliff.alerts, [ChainSummary.Alert.NO_MANAGER] as Array[ChainSummary.Alert])


func test_a_renovating_site() -> void:
	var mill: ChainSummary.Site = _by_id(_build(_book()), &"town_fixer_upper")
	assert_eq(mill.status, ChainSummary.Status.RENOVATING)
	assert_eq(mill.renovation_days, 2)
	assert_true(mill.staffed, "an empty staff section loads the starter team")
	assert_true(is_nan(mill.stars), "no closed day yet")
	assert_true(is_nan(mill.mood))
	assert_eq(mill.alerts, [] as Array[ChainSummary.Alert], "no manager alert while renovating")


func test_a_new_site_with_nobody_hired_and_ready_to_open() -> void:
	var book: SiteBook = SiteBook.new()
	var empty_staff: Dictionary = JSON.parse_string(JSON.stringify(StaffRoster.new().to_dict()))
	(empty_staff["members"] as Array).clear()
	assert_true(book.add_site(&"seaside_cliff", &"seaside_cliff", "Cliff", 3, {"staff": empty_staff}))
	var cliff: ChainSummary.Site = _by_id(_build(book), &"seaside_cliff")
	assert_false(cliff.staffed)
	assert_eq(cliff.alerts, [ChainSummary.Alert.NOT_STAFFED, ChainSummary.Alert.NO_MANAGER,
		ChainSummary.Alert.READY_TO_OPEN] as Array[ChainSummary.Alert], "most urgent first")


func test_a_manager_with_no_day_to_go_on() -> void:
	var book: SiteBook = SiteBook.new()
	var sections: Dictionary = _sections(4)
	sections.erase("business_history")
	assert_true(book.add_site(&"seaside_cliff", &"seaside_cliff", "Cliff", 3, sections))
	assert_true(book.set_manager(&"seaside_cliff", &"boss"))
	var cliff: ChainSummary.Site = _by_id(_build(book), &"seaside_cliff")
	assert_eq(cliff.status, ChainSummary.Status.CLOSED)
	assert_eq(cliff.manager_skill, 4, "still their manager")
	assert_true(cliff.alerts.has(ChainSummary.Alert.MANAGER_NEEDS_A_DAY))
	assert_false(cliff.alerts.has(ChainSummary.Alert.NO_MANAGER))


func test_stars_ladles_losses_mood_and_bookings() -> void:
	var sections: Dictionary = _sections(2)
	var critic: FoodCritic = FoodCritic.new()
	critic.golden_ladles = 2
	sections["critic"] = JSON.parse_string(JSON.stringify(critic.to_dict()))
	sections["reviews"] = {"version": 1, "scores": [4, 4, 4, 5, 5]}
	sections["business_history"]["days"][0]["dish_profit"] = "-120"
	sections["staff"]["members"][0]["growth"]["mood"] = 1.0
	sections["bookings"] = _booking_due(DAY)
	var book: SiteBook = SiteBook.new()
	assert_true(book.add_site(&"seaside_cliff", &"seaside_cliff", "Cliff", 3, sections))
	assert_true(book.set_manager(&"seaside_cliff", &"boss"))
	var cliff: ChainSummary.Site = _by_id(_build(book), &"seaside_cliff")
	assert_almost_eq(cliff.stars, 4.4)
	assert_eq(cliff.golden_ladles, 2)
	assert_eq(cliff.recent_mean, -36, "mean of -120 and 49, rounded")
	assert_eq(cliff.lowest_mood, 1)
	assert_almost_eq(cliff.mood, 2.0, 0.0001, "the manager's mood is not the team's")
	assert_eq(cliff.alerts, [ChainSummary.Alert.LOSING_MONEY, ChainSummary.Alert.BOOKING_LAPSES,
		ChainSummary.Alert.UNHAPPY_TEAM] as Array[ChainSummary.Alert])
	var deposit: int = int(sections["bookings"]["booking"]["deposit_amount"])
	assert_eq(cliff.tonight, -36 - deposit, "a loss is paid as a loss, and the deposit refunded")


func _booking_due(day: int) -> Dictionary:
	var offer: Dictionary = SiteThawFixture.sections()["bookings"]["offer"]
	offer["offer_day"] = float(day - 1)
	offer["service_day"] = float(day)
	var booking: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(booking.from_dict({"version": 1.0, "planned_day": float(day - 1), "offer": offer, "booking": {}}))
	assert_false(booking.accept_offer(day - 1).is_empty())
	return JSON.parse_string(JSON.stringify(booking.to_dict()))


func test_a_live_capture_reads_like_a_saved_one() -> void:
	# A live capture holds StringNames and ints; the summary decodes it in
	# saved-file shape, as a load would.
	var live: Dictionary = _sections()
	live["staff"]["members"][0]["role"] = &"cook"
	live["critic"] = FoodCritic.new().to_dict()
	var home: ChainSummary.Site = _by_id(_build(_book(), Ledger.new(), live), &"home")
	assert_true(home.staffed)
	assert_eq(home.golden_ladles, 0)


func test_the_summary_is_deterministic() -> void:
	var first: Array[ChainSummary.Site] = _build(_book())
	var second: Array[ChainSummary.Site] = _build(_book())
	for index: int in range(first.size()):
		assert_eq(first[index].tonight, second[index].tonight)
		assert_eq(first[index].alerts, second[index].alerts)


func test_chain_income_and_series() -> void:
	var ledger: Ledger = Ledger.new()
	ledger.record(3, 200, Ledger.SALE, "", &"home")
	ledger.record(4, 250, Ledger.SALE, "", &"home")
	ledger.record(4, 15, Ledger.TIP, "", &"home")
	ledger.record(4, -80, Ledger.WAGES, "", &"home")
	ledger.record(4, 36, Ledger.AWAY_SITE_INCOME, "", &"beachfront_boardwalk")
	ledger.record(4, -95, Ledger.AWAY_SITE_RENT, "", &"seaside_cliff")
	var sites: Array[StringName] = [&"home", &"beachfront_boardwalk", &"seaside_cliff"]
	assert_eq(ChainStats.site_income(ledger, 4, &"home"), 265, "takings: sales and tips, gross")
	assert_eq(ChainStats.site_income(ledger, 4, &"beachfront_boardwalk"), 36, "net away earnings")
	assert_eq(ChainStats.site_income(ledger, 4, &"seaside_cliff"), 0, "a closed site's rent is not income")
	assert_eq(ChainStats.chain_income(ledger, 4, sites), 301)
	assert_eq(ChainStats.site_series(ledger, 4, 3, &"home"), [0, 200, 265] as Array[int], "oldest first")
	assert_eq(ChainStats.site_series(ledger, 1, 3, &"home"), [0, 0, 0] as Array[int], "days before day 1")
	assert_eq(ChainStats.chain_total(ledger, 4, 7, sites), 501)


func test_chain_totals_from_the_summary() -> void:
	var sites: Array[ChainSummary.Site] = _build(_book())
	_by_id(sites, &"home").golden_ladles = 1
	_by_id(sites, &"beachfront_boardwalk").golden_ladles = 2
	assert_eq(ChainStats.total_ladles(sites), 3)
	var home_stars: float = _by_id(sites, &"home").stars
	var pier_stars: float = _by_id(sites, &"beachfront_boardwalk").stars
	assert_almost_eq(ChainStats.mean_stars(sites), (home_stars * 2.0 + pier_stars) / 3.0,
		0.0001, "the renovating site has no stars yet and is left out")
	assert_true(is_nan(ChainStats.mean_stars([] as Array[ChainSummary.Site])))
	var counts: Dictionary[int, int] = ChainStats.status_counts(sites)
	assert_eq(counts[ChainSummary.Status.HERE], 1)
	assert_eq(counts[ChainSummary.Status.MANAGED], 1)
	assert_eq(counts[ChainSummary.Status.CLOSED], 1)
	assert_eq(counts[ChainSummary.Status.RENOVATING], 1)
	var expected: int = 0
	for site: ChainSummary.Site in sites:
		expected += site.tonight
	assert_eq(ChainStats.tonight_total(sites), expected)


func test_chain_alerts_most_urgent_first_then_site_order() -> void:
	var a: ChainSummary.Site = ChainSummary.Site.new()
	a.id = &"a"
	a.alerts = [ChainSummary.Alert.READY_TO_OPEN, ChainSummary.Alert.NO_MANAGER] as Array[ChainSummary.Alert]
	var b: ChainSummary.Site = ChainSummary.Site.new()
	b.id = &"b"
	b.alerts = [ChainSummary.Alert.NO_MANAGER, ChainSummary.Alert.NOT_STAFFED] as Array[ChainSummary.Alert]
	var found: Array[Dictionary] = ChainStats.alerts([a, b] as Array[ChainSummary.Site])
	var flat: Array[String] = []
	for entry: Dictionary in found:
		flat.append("%s:%d" % [entry["site"], entry["alert"]])
	assert_eq(flat, ["b:%d" % ChainSummary.Alert.NOT_STAFFED, "a:%d" % ChainSummary.Alert.NO_MANAGER,
		"b:%d" % ChainSummary.Alert.NO_MANAGER, "a:%d" % ChainSummary.Alert.READY_TO_OPEN] as Array[String])
