class_name DayReportBuilder
extends RefCounted
## Writes the evening report from the day's facts (#526). Pure: it reads
## `sources`, draws no random number and changes nothing but the report it
## returns, so the report can be rebuilt any number of times.
##
## A new report line is a field of `DayReport` and a line here. If it needs a
## fact the close decided, that is a field of `DayNotes`; if it needs another
## system, that is a field of `DayReportSources`.


static func build(day: int, sources: DayReportSources) -> DayReport:
	var report := DayReport.new()
	report.day = day
	# The receipt names its site: a haggled order bought before a switch
	# stays out of the arriving site's report (FK-087).
	if int(sources.haggle_receipt.get("day", 0)) == day \
			and StringName(sources.haggle_receipt.get("site", &"")) == sources.site:
		report.haggle_percent = int(sources.haggle_receipt["percent"])
		report.haggle_saved = int(sources.haggle_receipt["saved"])
	report.staff_activity = sources.sim.staff_activity.snapshot()
	report.staff_nicknames = sources.staff_nicknames.duplicate()
	report.restaurant_name = sources.menu.restaurant_name() if sources.menu != null else MenuSettings.DEFAULT_NAME
	report.regulars_lines = RegularText.report_lines(sources.regulars)
	report.critic_lines = FoodCritic.report_lines(sources.sim.critic_result)
	if sources.viral.triggered_on(day):
		var best: RecipeDef = sources.content.recipe(sources.viral.dish)
		report.viral_line = ViralReviewText.evening(best.display_name if best != null else "food")
	report.booking_lines = sources.sim.booking_report_lines.duplicate()
	report.loan_first_advance = sources.notes.loan_notice_day == day
	# Only this site's books (FK-087): another site's morning stays in its own.
	var totals: Dictionary = sources.ledger.day_totals(day, sources.site)
	for category: StringName in totals:
		var amount: int = totals[category]
		if amount > 0:
			report.income[category] = amount
		elif amount < 0:
			report.costs[category] = -amount
	if sources.notes.tip_jar_day == day:
		report.tip_jar_bonus = sources.notes.tip_jar_bonus
	report.stock_values_recorded = true
	report.food_cost = int(sources.food_cost["cost"])
	report.food_cost_recorded = bool(sources.food_cost["recorded"])
	# Gross purchases remain visible even when a cancelled order was refunded.
	var bought: Dictionary = PurchaseBasis.zero()
	for entry: Dictionary in sources.ledger.entries_for_day(day, sources.site):
		if entry["category"] == Ledger.INGREDIENTS and int(entry["amount"]) < 0:
			PurchaseBasis.combine(bought, {"cost": -int(entry["amount"]), "recorded": true})
	report.stock_bought = int(bought["cost"])
	report.stock_bought_recorded = bool(bought["recorded"])
	var spoiled: Dictionary = sources.stock.spoilage_value(day)
	report.spoiled_stock = int(spoiled["cost"])
	report.spoiled_stock_recorded = bool(spoiled["recorded"])
	var on_hand: Dictionary = sources.stock.value()
	report.stock_on_hand = int(on_hand["cost"])
	report.stock_on_hand_recorded = bool(on_hand["recorded"])
	report.dishes_sold = sources.dishes_sold.duplicate()
	report.dish_metrics = sources.dish_metrics.duplicate(true)
	report.daily_special_line = DailySpecialText.report(
		DailySpecialText.name_for(sources.special.recipe_id(), sources.menu.enabled_recipes()),
		int(report.dishes_sold.get(sources.special.recipe_id(), 0)))
	report.slowest_seller_snapshot = sources.sim.service_menu_report_snapshot()
	report.customers_served = sources.sim.served_today
	report.customers_lost = sources.sim.lost_today
	report.visitor_breakdown = sources.sim.visitor_breakdown()
	report.takeaways = sources.sim.takeaways_today
	if sources.sim.mishaps != null:
		report.mishaps_text = MishapText.daily(sources.sim.mishaps.spills_today,
			sources.sim.mishaps.broken_plates_today, sources.sim.mishaps.degreases_today)
	report.record_dish_quality(sources.sim.orders.orders_in_state(Order.State.DELIVERED))
	for reason: StringName in sources.sim.leave_reasons_today:
		if reason != &"happy":
			report.leave_reasons[reason] = sources.sim.leave_reasons_today[reason]
	if sources.sim.cleanliness != null:
		report.cleanliness_label = sources.sim.cleanliness.worst_category_label()
	var star_total: int = 0
	for row: Dictionary in sources.sim.reviews_today:
		var stars: int = int(row.get("stars", 0))
		star_total += stars
		report.review_cards.append({"stars": stars, "quote": String(row.get("quote", ""))})
	report.today_review_average = float(star_total) / float(report.review_cards.size()) \
		if not report.review_cards.is_empty() else 0.0
	report.reputation_before = sources.sim.reputation_before_day
	report.reputation_after = sources.reputation_average
	report.owner_level_before = sources.owner.level
	report.owner_level_after = sources.owner.level
	if sources.notes.owner_award_day != day and sources.notes.career_tier_reached > 0 and not sources.notes.owner_unlocks.is_empty():
		report.owner_unlocks = sources.notes.owner_unlocks.duplicate()
	if sources.notes.owner_award_day == day:
		report.owner_xp_breakdown = {
			"happy_xp": int(sources.notes.owner_award["happy_xp"]),
			"profit_xp": int(sources.notes.owner_award["profit_xp"]),
			"review_xp": int(sources.notes.owner_award["review_xp"]),
			"total_xp": int(sources.notes.owner_award["total_xp"]),
		}
		report.owner_level_before = int(sources.notes.owner_award.get("level_before", sources.owner.level))
		report.owner_level_after = sources.owner.level
		report.owner_unlocks = sources.notes.owner_unlocks.duplicate()
		report.owner_tips = sources.notes.owner_tips.duplicate()
		if sources.notes.milestone_xp > 0:
			report.owner_xp_breakdown["milestone_xp"] = sources.notes.milestone_xp
		if sources.notes.opening_week_xp_day == day and sources.notes.opening_week_xp > 0:
			report.owner_xp_breakdown["opening_week_xp"] = sources.notes.opening_week_xp
	if sources.sim.inspection.last_day == day:
		report.inspection_lines = InspectionText.report_lines(sources.sim.inspection.last_result, sources.sim.inspection.tuning)
	report.rush_hour_lines = sources.sim.rush_hour.report_lines()
	if sources.service_events != null and sources.service_events.day == day:
		report.service_event_lines = sources.service_events.report_lines()
	report.low_stock = StockAlerts.sell_out_lines(sources.sim.stock_outs_today, sources.content)
	report.low_stock.append_array(StockAlerts.forecast_lines(sources.stock_forecast, sources.content))
	if sources.notes.milestone_award_day == day:
		for goal: Milestone in sources.notes.milestones_reached:
			report.milestones_reached.append({"title": goal.title,
				"reward_xp": goal.reward_xp, "reward_cash": goal.reward_cash})
	if sources.notes.weekly_challenge_reward_day == day:
		report.weekly_challenge_line = sources.notes.weekly_challenge_line
	if sources.notes.career_tier_day == day:
		report.career_tier_line = CareerTierTuning.reached_text(sources.notes.career_tier_reached)
	if sources.notes.away_site_day == day:
		report.away_site_lines = sources.notes.away_site_lines.duplicate()
	report.demand_forecast = sources.demand_forecast
	if sources.notes.record_day == day:
		report.record_lines = sources.notes.record_lines.duplicate()
	return report
