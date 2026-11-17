extends TestCase
## DayReportBuilder: the evening report written out of the day's facts (#526).
## No scene, no Node and no autoload: the sources are filled by hand.


const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")

var _content_db: ContentDB = null


func _content() -> ContentDB:
	if _content_db == null:
		_content_db = ContentDB.new()
		_content_db.load_all()
	return _content_db


func _menu_recipes(content: ContentDB) -> Array[RecipeDef]:
	var recipes: Array[RecipeDef] = []
	# The ids the data ships; a missing one is simply not offered.
	var ids: Array[StringName] = [&"burger", &"salad", &"fries"]
	for id: StringName in ids:
		var recipe: RecipeDef = content.recipe(id)
		if recipe != null:
			recipes.append(recipe)
	return recipes


func _sources() -> DayReportSources:
	var sources: DayReportSources = DayReportSources.new()
	var sold: Dictionary[StringName, int] = {}
	sources.sim = RestaurantSim.new()
	sources.content = _content()
	sources.site = Ledger.HOME_SITE
	sources.ledger = Ledger.new()
	sources.stock = Stock.new()
	sources.menu = MenuSettings.new(_menu_recipes(sources.content), 1)
	sources.special = DailySpecial.new()
	sources.regulars = RegularCast.new()
	sources.viral = ViralReview.new()
	sources.owner = OwnerProgress.new(PROGRESSION)
	sources.service_events = null
	sources.notes = DayNotes.new()
	sources.reputation_average = 0.0
	sources.dishes_sold = sold
	sources.food_cost = PurchaseBasis.zero()
	sources.haggle_receipt = {}
	sources.stock_forecast = {}
	sources.demand_forecast = {}
	return sources


func test_ledger_totals_split_into_income_and_costs_for_this_day_and_site() -> void:
	var sources: DayReportSources = _sources()
	sources.ledger.record(5, 300, Ledger.SALE, "", Ledger.HOME_SITE)
	sources.ledger.record(5, -120, Ledger.INGREDIENTS, "", Ledger.HOME_SITE)
	sources.ledger.record(5, -80, Ledger.RENT, "", Ledger.HOME_SITE)
	sources.ledger.record(5, 900, Ledger.SALE, "", &"harbour")
	sources.ledger.record(4, 500, Ledger.SALE, "", Ledger.HOME_SITE)
	var report: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(int(report.income.get(Ledger.SALE, 0)), 300, "this site and day only")
	assert_false(report.costs.has(Ledger.SALE), "a sale is not a cost")
	assert_eq(int(report.costs.get(Ledger.INGREDIENTS, 0)), 120, "costs are written positive")
	assert_eq(int(report.costs.get(Ledger.RENT, 0)), 80)
	assert_eq(report.stock_bought, 120, "the gross ingredients spend")


func test_haggle_receipt_counts_only_for_its_own_day_and_site() -> void:
	var sources: DayReportSources = _sources()
	var baseline: DayReport = DayReportBuilder.build(5, sources)
	sources.haggle_receipt = {"day": 5, "site": sources.site, "percent": 12, "saved": 48}
	var report: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(report.haggle_percent, 12)
	assert_eq(report.haggle_saved, 48)
	sources.haggle_receipt = {"day": 4, "site": sources.site, "percent": 12, "saved": 48}
	var yesterday: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(yesterday.haggle_percent, baseline.haggle_percent, "another day's haggle stays out")
	sources.haggle_receipt = {"day": 5, "site": &"harbour", "percent": 12, "saved": 48}
	var elsewhere: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(elsewhere.haggle_saved, baseline.haggle_saved, "another site's haggle stays out")


func test_counters_leave_reasons_reviews_and_reputation_are_copied() -> void:
	var sources: DayReportSources = _sources()
	var reasons: Dictionary[StringName, int] = {}
	reasons[&"slow_service"] = 2
	reasons[&"happy"] = 5
	var reviews: Array[Dictionary] = []
	reviews.append({"stars": 5, "quote": "Lovely"})
	reviews.append({"stars": 3, "quote": "Slow"})
	sources.sim.served_today = 12
	sources.sim.lost_today = 3
	sources.sim.takeaways_today = 4
	sources.sim.leave_reasons_today = reasons
	sources.sim.reviews_today = reviews
	sources.sim.reputation_before_day = 4.2
	sources.reputation_average = 4.35
	var report: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(report.customers_served, 12)
	assert_eq(report.customers_lost, 3)
	assert_eq(report.takeaways, 4)
	assert_eq(int(report.leave_reasons.get(&"slow_service", 0)), 2)
	assert_false(report.leave_reasons.has(&"happy"), "happy leavers are not a reason")
	assert_eq(report.review_cards.size(), 2)
	assert_eq(int(report.review_cards[0]["stars"]), 5)
	assert_eq(String(report.review_cards[0]["quote"]), "Lovely")
	assert_almost_eq(report.today_review_average, 4.0, 0.001, "the day's stars averaged")
	assert_almost_eq(report.reputation_before, 4.2, 0.001, "the morning's reputation")
	assert_almost_eq(report.reputation_after, 4.35, 0.001, "the closing reputation")


func test_owner_award_breakdown_waits_for_the_award_day() -> void:
	var sources: DayReportSources = _sources()
	sources.owner.level = 3
	var plain: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(plain.owner_level_before, plain.owner_level_after, "no award, no change")
	assert_eq(plain.owner_level_after, 3)
	assert_true(plain.owner_xp_breakdown.is_empty())
	sources.notes.owner_award = {"happy_xp": 4, "profit_xp": 3, "review_xp": 2,
		"total_xp": 9, "level_before": 2}
	sources.notes.owner_award_day = 5
	var award: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(award.owner_xp_breakdown.size(), 4)
	assert_eq(int(award.owner_xp_breakdown["happy_xp"]), 4)
	assert_eq(int(award.owner_xp_breakdown["profit_xp"]), 3)
	assert_eq(int(award.owner_xp_breakdown["review_xp"]), 2)
	assert_eq(int(award.owner_xp_breakdown["total_xp"]), 9)
	assert_eq(award.owner_level_before, 2, "the level the day started on")
	assert_eq(award.owner_level_after, 3)


func test_bonus_xp_joins_the_breakdown_only_on_its_own_day() -> void:
	var sources: DayReportSources = _sources()
	sources.owner.level = 3
	sources.notes.owner_award = {"happy_xp": 4, "profit_xp": 3, "review_xp": 2,
		"total_xp": 9, "level_before": 2}
	sources.notes.owner_award_day = 5
	sources.notes.milestone_xp = 30
	sources.notes.opening_week_xp = 12
	sources.notes.opening_week_xp_day = 5
	var bonus: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(int(bonus.owner_xp_breakdown["milestone_xp"]), 30, "milestone XP joins the day")
	assert_eq(int(bonus.owner_xp_breakdown["opening_week_xp"]), 12, "opening week XP on its day")
	sources.notes.opening_week_xp_day = 4
	var early: DayReport = DayReportBuilder.build(5, sources)
	assert_false(early.owner_xp_breakdown.has("opening_week_xp"), "another day's bonus stays out")
	sources.notes.opening_week_xp_day = 5
	sources.notes.milestone_xp = 0
	sources.notes.opening_week_xp = 0
	var quiet: DayReport = DayReportBuilder.build(5, sources)
	assert_false(quiet.owner_xp_breakdown.has("milestone_xp"), "no XP, no line")
	assert_false(quiet.owner_xp_breakdown.has("opening_week_xp"))


func test_day_gated_notes_show_only_on_their_day() -> void:
	var sources: DayReportSources = _sources()
	var notes: DayNotes = sources.notes
	var goal: Milestone = Milestone.new()
	goal.title = "First full house"
	notes.record_day = 5
	notes.record_lines = ["New record: 40 covers"] as Array[String]
	notes.away_site_day = 5
	notes.away_site_lines = ["Second site: closed"] as Array[String]
	notes.weekly_challenge_reward_day = 5
	notes.weekly_challenge_line = "Weekly challenge complete"
	notes.loan_notice_day = 5
	notes.milestone_award_day = 5
	notes.milestones_reached = [goal] as Array[Milestone]
	var report: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(report.record_lines.size(), 1)
	assert_eq(report.record_lines[0], "New record: 40 covers")
	assert_eq(report.away_site_lines.size(), 1)
	assert_eq(report.weekly_challenge_line, "Weekly challenge complete")
	assert_true(report.loan_first_advance)
	assert_eq(report.milestones_reached.size(), 1)
	assert_eq(String(report.milestones_reached[0]["title"]), "First full house")
	var later: DayReport = DayReportBuilder.build(4, sources)
	assert_true(later.record_lines.is_empty())
	assert_true(later.away_site_lines.is_empty())
	assert_eq(later.weekly_challenge_line, "")
	assert_false(later.loan_first_advance)
	assert_true(later.milestones_reached.is_empty())


func test_forecasts_pass_through_and_an_empty_one_adds_no_line() -> void:
	var sources: DayReportSources = _sources()
	var forecast: Dictionary = {"day": 6, "expected_guests": 24}
	for key: String in DayReport.DEMAND_FACTOR_KEYS:
		forecast[key] = 1.0
	sources.demand_forecast = forecast
	var report: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(int(report.demand_forecast.get("day", 0)), 6, "the demand forecast is the session's")
	assert_eq(int(report.demand_forecast.get("expected_guests", 0)), 24)
	assert_true(report.low_stock.is_empty(), "no stock-out and no forecast, no line")


func test_sell_outs_come_before_the_stock_forecast() -> void:
	var sources: DayReportSources = _sources()
	var dishes: Array[StringName] = [&"burger"]
	var events: Array[Dictionary] = [{"ingredient": &"bun", "minute": 1180, "dishes": dishes}]
	sources.sim.stock_outs_today = events
	sources.stock_forecast = {"rows": [], "order_cost": 79}
	var report: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(report.low_stock.size(), 2)
	assert_true(report.low_stock[0].contains("sold out"), "what ran out today comes first")
	assert_true(report.low_stock[1].contains("$79"), "then tomorrow's order")


func test_daily_special_line_names_the_special_and_counts_its_sales() -> void:
	var sources: DayReportSources = _sources()
	var special_recipe: RecipeDef = sources.content.recipe(&"burger")
	assert_not_null(special_recipe, "the data must carry the test recipe")
	assert_true(sources.special.select(&"burger", sources.menu.enabled_recipes()),
		"the menu must offer the special")
	var sold: Dictionary[StringName, int] = {}
	sold[&"burger"] = 7
	sources.dishes_sold = sold
	var report: DayReport = DayReportBuilder.build(5, sources)
	assert_false(report.daily_special_line.is_empty())
	assert_true(report.daily_special_line.contains(special_recipe.display_name),
		"the line names the dish")
	assert_true(report.daily_special_line.contains("7"), "the line counts the day's sales")
	var bare: DayReport = DayReportBuilder.build(5, _sources())
	assert_true(bare.daily_special_line.is_empty(), "no special, no line")


func test_viral_line_appears_only_on_the_day_it_triggered() -> void:
	var sources: DayReportSources = _sources()
	var quiet: DayReport = DayReportBuilder.build(5, sources)
	assert_true(quiet.viral_line.is_empty())
	sources.viral.last_trigger_day = 5
	sources.viral.dish = &"burger"
	var viral: DayReport = DayReportBuilder.build(5, sources)
	assert_false(viral.viral_line.is_empty())
	sources.viral.last_trigger_day = 4
	var yesterday: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(yesterday.viral_line, quiet.viral_line, "another day's viral stays out")


func test_the_builder_copies_the_collections_it_keeps() -> void:
	var sources: DayReportSources = _sources()
	var sold: Dictionary[StringName, int] = {}
	sold[&"burger"] = 3
	var bookings: Array[String] = ["Table for two at 19:00"]
	sources.dishes_sold = sold
	sources.sim.booking_report_lines = bookings
	var report: DayReport = DayReportBuilder.build(5, sources)
	sold[&"burger"] = 9
	bookings.append("Table for four at 20:00")
	assert_eq(int(report.dishes_sold.get(&"burger", 0)), 3, "the report keeps its own tallies")
	assert_eq(report.booking_lines.size(), 1, "the report keeps its own bookings")


func test_building_twice_gives_the_same_report() -> void:
	var sources: DayReportSources = _sources()
	sources.sim.served_today = 12
	sources.sim.lost_today = 3
	sources.reputation_average = 4.35
	sources.ledger.record(5, 300, Ledger.SALE, "", Ledger.HOME_SITE)
	sources.ledger.record(5, -120, Ledger.INGREDIENTS, "", Ledger.HOME_SITE)
	var first: DayReport = DayReportBuilder.build(5, sources)
	var second: DayReport = DayReportBuilder.build(5, sources)
	assert_eq(first.to_dict(), second.to_dict())


func test_visitor_counts_and_final_mood_are_detached_and_reset_the_next_morning() -> void:
	var sources: DayReportSources = _sources()
	var sim: RestaurantSim = sources.sim
	sim.world = SimWorld.new(SimGrid.new(Vector2i(6, 6)), SimClock.new())
	sim.spawner = CustomerSpawner.new(sim.rng)
	var types: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
	var fake_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	fake_rng.seed = 42
	var regular: CustomerAgent = sim.add_customer(Vector2i(1, 1), fake_rng)
	var student: CustomerAgent = sim.add_customer(Vector2i(2, 1), fake_rng, types.find_type(&"student"))
	var party_randoms: Array[RandomNumberGenerator] = [RandomNumberGenerator.new(), RandomNumberGenerator.new()]
	party_randoms[0].seed = 43
	party_randoms[1].seed = 44
	var party: Party = sim.add_party(Vector2i(3, 1), party_randoms, types.find_type(&"family"))
	assert_not_null(party)
	var early: DayReport = DayReportBuilder.build(1, sources)
	assert_eq(early.visitor_breakdown, [
		{"name": "Regulars", "count": 1, "average_mood": null},
		{"name": "Students", "count": 1, "average_mood": null},
		{"name": "Families", "count": 2, "average_mood": null},
	])
	regular.state = CustomerAgent.State.QUEUED
	regular.queue_patience = 100
	regular._queue_wait = 100
	regular.give_up_blocked(sim.world)
	assert_eq(regular.state, CustomerAgent.State.LEAVING)
	assert_eq(regular.mood(), 1.0, "the live mood query remains unchanged")
	sim.world.remove_agent(regular)
	sim.record_departure(regular)
	student.state = CustomerAgent.State.WAITING_FOOD
	student.food_patience = 100
	student._food_wait = 50
	sim.world.remove_agent(student)
	var remaining: Array[CustomerAgent] = sim.customers()
	assert_eq(remaining.size(), 2, "up to two individual family arrivals may share the entry")
	for index: int in range(remaining.size()):
		var guest: CustomerAgent = remaining[index]
		guest.state = CustomerAgent.State.QUEUED
		guest.queue_patience = 100
		guest._queue_wait = 80 + index * 30
	# The real closing tick removes both the admitted and pending family guests.
	# Removing the first can start the second leaving as part of the same party.
	sim.world.clock.phase = SimClock.Phase.LAST_ORDERS
	sim.world.clock.last_orders_max_ticks = 1
	sim.advance()
	assert_eq(sim.world.clock.phase, SimClock.Phase.CLOSED)
	assert_true(sim.customers().is_empty())
	var report: DayReport = DayReportBuilder.build(1, sources)
	assert_eq(report.visitor_breakdown, [
		{"name": "Regulars", "count": 1, "average_mood": 0.0},
		{"name": "Students", "count": 1, "average_mood": 0.5},
		{"name": "Families", "count": 2, "average_mood": 0.1},
	])
	assert_eq(report.customers_lost, 4)
	assert_null(early.visitor_breakdown[2]["average_mood"], "earlier snapshots are detached")
	assert_true(sim.world.clock.next_day())
	sim.start_day()
	assert_true(DayReportBuilder.build(2, sources).visitor_breakdown.is_empty())
	assert_eq(report.visitor_breakdown.size(), 3, "morning cannot change yesterday's snapshot")
