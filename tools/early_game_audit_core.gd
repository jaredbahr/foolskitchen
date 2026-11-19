extends RefCounted
## Core of tools/early_game_audit.gd. Loaded after autoloads exist.

const MAX_TICK_BATCHES: int = 30
const TICKS_PER_BATCH: int = 1000


static func run_cli(tree: SceneTree, args: PackedStringArray) -> int:
	var days: int = 10
	var seed_value: int = 1
	var player: String = "engaged"
	var mode_id: StringName = &"normal"
	for arg: String in args:
		if arg.begins_with("--days="):
			days = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--player="):
			player = arg.get_slice("=", 1)
		elif arg.begins_with("--difficulty="):
			mode_id = StringName(arg.get_slice("=", 1))
	if player not in ["engaged", "passive"] or mode_id not in [&"normal", &"easy", &"hard"] or days < 1:
		printerr("Usage: --days=N --seed=N --player=engaged|passive --difficulty=normal|easy|hard")
		return 2
	return run(tree, days, seed_value, player, mode_id)


static func run(tree: SceneTree, days: int, seed_value: int, player: String, mode_id: StringName) -> int:
	var setup: String = "week_two" if player == "engaged" else "default"
	var main: Node = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", seed_value)
	main.set("service_events_for_tools", true)
	main.set("service_event_auto_pick", 0)
	if mode_id != &"normal":
		GameMode.request_new_game(false, mode_id)
	tree.root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null or not ProbeSetups.apply(setup, main):
		printerr("Could not start the session")
		return 2
	# ProbeSetups.apply turns events back on for its own set-up only.
	main.set("service_events_for_tools", true)
	main.set("service_event_auto_pick", 0)
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var cash_start: int = Economy.cash
	print("AUDIT_START ", JSON.stringify({"seed": seed_value, "player": player,
		"difficulty": String(mode_id), "cash": cash_start, "level": progress.level,
		"tier": progress.effective_tier(), "menu": _menu(main),
		"paper": _paper(main)}))
	sim.start_day(progress.effective_tier())
	for day_index: int in range(days):
		if day_index > 0 and not ProbeSetups.morning(setup, main):
			printerr("Morning set-up failed on day %d" % (day_index + 1))
		if day_index > 0 and player == "engaged":
			_week_three(main)
		# Hard buys nothing by itself: order the forecast through the Stock cart.
		if mode_id == &"hard" and not BalanceProbe._place_hard_stock_order(main):
			printerr("Hard stock order failed on day %d" % (day_index + 1))
		var morning: Dictionary = {"day": Clock.sim.day, "cash_open": Economy.cash,
			"weekday": Clock.sim.day, "goals_shown": _goals_shown(main),
			"weekly": (main.get("weekly_challenge") as WeeklyChallengeState).to_dict(),
			"booking_offer": (main.get("group_booking") as GroupBooking).offer.duplicate(),
			"candidates": (main.get("staff_roster") as StaffRoster).candidates().size(),
			"weather": int(sim.world.weather.kind), "paper": _paper(main),
			"lease_refusal": str(main.call("lease_refusal")) if main.has_method("lease_refusal") else "",
			"menu": _menu(main)}
		var log_before: int = sim.world.event_log.size()
		if not Clock.sim.start_service():
			printerr("Shop did not open on day %d" % (day_index + 1))
			return 2
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < MAX_TICK_BATCHES:
			main.call("run_ticks", TICKS_PER_BATCH)
			batches += 1
		var report: DayReport = main.get("shown_report") as DayReport
		var book: Dictionary = Economy.ledger.day_totals(report.day)
		var ledger: Dictionary = {}
		for key: Variant in book:
			ledger[String(key)] = int(book[key])
		var reasons: Dictionary = {}
		for reason: Variant in sim.leave_reasons_today:
			reasons[String(reason)] = int(sim.leave_reasons_today[reason])
		morning.merge({"arrivals": sim.served_today + sim.lost_today,
			"served": report.customers_served, "lost": report.customers_lost,
			"reasons": reasons, "ledger": ledger,
			"profit": Economy.ledger.day_profit(report.day), "cash_close": Economy.cash,
			"stars_before": snappedf(report.reputation_before, 0.01),
			"stars_after": snappedf(report.reputation_after, 0.01),
			"today_review_avg": snappedf(report.today_review_average, 0.01),
			"level": progress.level, "xp": progress.total_xp, "tier": progress.effective_tier(),
			"xp_breakdown": report.owner_xp_breakdown,
			"unlocks": report.owner_unlocks, "tips": report.owner_tips,
			"milestones": report.milestones_reached.map(func(m: Dictionary) -> String: return str(m.get("title", m))),
			"weekly_line": report.weekly_challenge_line, "tier_line": report.career_tier_line,
			"events": report.service_event_lines, "bookings": report.booking_lines,
			"regulars": report.regulars_lines, "rush": report.rush_hour_lines,
			"critic": report.critic_lines, "records": report.record_lines,
			"viral": report.viral_line, "reviews": report.reviews.slice(0, 3),
			"review_count": report.review_cards.size(),
			"goals_done": (main.get("opening_week") as OpeningWeek).completed_ids().map(
				func(id: StringName) -> String: return String(id)),
			"dishes": report.dishes_sold, "low_stock": report.low_stock,
			"log_lines": sim.world.event_log.size() - log_before})
		print("AUDIT_DAY ", JSON.stringify(morning))
		if day_index + 1 < days and not Clock.sim.next_day():
			printerr("Next morning failed")
			return 2
	main.queue_free()
	return 0


## Follows Week 3's goals once that chain runs (if the data has it), as cash
## allows: a second cook, an oven and a pizza slice, a waiting bench.
## Prices drop back to standard to chase the 4-star day.
static func _week_three(main: Node) -> void:
	var state: OpeningWeek = main.get("opening_week") as OpeningWeek
	var chain: OpeningWeekSet = state.current(main.get("goal_chains") as GoalChainSequence) if state != null else null
	if chain == null or chain.id != &"week_three" or not state.is_active():
		return
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	for recipe: RecipeDef in settings.enabled_recipes():
		main.call("menu_set_price", recipe.id, recipe.standard_price)
	var roster: StaffRoster = main.get("staff_roster") as StaffRoster
	var cooks: int = 0
	for member: StaffMember in roster.members():
		if member.role == &"cook":
			cooks += 1
	if cooks < 2:
		var hired: bool = false
		for member: StaffMember in roster.candidates():
			if member.role == &"cook":
				hired = main.call("staff_hire", member.id)
				break
		if not hired:
			ProbeSetups._add_staff(main, &"cook", 3)
	if ProbeSetups._count_items(sim.world.grid, &"oven") == 0:
		ProbeSetups._buy_first_fit(main, &"oven")
	if settings.recipe(&"pizza_slice") != null and not settings.is_enabled(&"pizza_slice"):
		main.call("menu_set_enabled", &"pizza_slice", true)
	if ProbeSetups._count_items(sim.world.grid, &"waiting_bench") < 1:
		ProbeSetups._buy_first_fit(main, &"waiting_bench")


static func _goals_shown(main: Node) -> Array:
	var state: OpeningWeek = main.get("opening_week") as OpeningWeek
	var chains: GoalChainSequence = main.get("goal_chains") as GoalChainSequence
	if state == null or not state.is_active():
		return []
	var chain: OpeningWeekSet = state.current(chains)
	if chain == null:
		return []
	var out: Array = []
	for goal: OpeningGoal in state.shown(chain):
		out.append("%s ($%d)" % [goal.title, goal.reward_cash])
	return out


static func _paper(main: Node) -> Dictionary:
	var edition: Dictionary = main.get("_morning_paper_edition")
	return {"headline": edition.get("headline", ""), "notes": edition.get("notes", [])}


static func _menu(main: Node) -> Array:
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var out: Array = []
	for recipe: RecipeDef in settings.enabled_recipes():
		out.append(String(recipe.id))
	return out
