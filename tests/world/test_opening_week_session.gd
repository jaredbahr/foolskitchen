extends TestCase
## The opening-week chain in a real session (#494): each goal's trigger, one
## ledger movement per goal, the tracker and Goals card, the save round trip,
## old saves and the end of the chain. Week 2 (#514): the hand-over, each
## goal in a real session, saves made mid-chain and old saves.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "opening_week_session"
const CHAIN: OpeningWeekSet = preload("res://data/balance/opening_week.tres")
const WEEKLY_CHALLENGES: WeeklyChallengePool = preload("res://data/balance/weekly_challenges.tres")
const WEEK_TWO: OpeningWeekSet = preload("res://data/balance/week_two.tres")
const LEASE: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
const CAREER: CareerTierTuning = preload("res://data/balance/career_tiers.tres")

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "opening_week_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_new_game_shows_the_chain_in_the_tracker_and_goals() -> void:
	var main: Node = await _start(false)
	var state: OpeningWeek = _state(main)
	assert_true(state.is_active(), "every new career game gets the opening week")
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var lines: Array[String] = hud.call("opening_week_lines")
	assert_eq(lines.size(), 3, "the tracker shows three goals")
	assert_eq(lines[0], OpeningWeekText.tracker_line(CHAIN.goals[0]))
	assert_eq(hud.call("opening_week_title"), "Opening week")
	assert_true(main.call("set_goals_visible", true))
	var goals: GoalsPanel = main.get_node("Overlay/GoalsPanel") as GoalsPanel
	assert_eq(goals.opening_goal_ids(), [&"change_price", &"place_decor", &"serve_15"] as Array[StringName])
	var list: VBoxContainer = goals.get_node("%List") as VBoxContainer
	assert_eq(list.get_child(0).name, &"OpeningWeek", "the Opening week card leads the panel")


func test_weekly_serving_goal_is_filtered_on_day_one_but_not_day_eight() -> void:
	var main: Node = await _start(false)
	var weekly: WeeklyChallengeState = main.get("weekly_challenge") as WeeklyChallengeState
	assert_true(weekly.is_active())
	assert_ne(weekly.kind, WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, "Opening week has its own serving rewards")
	for step: int in 6:
		_next_morning(main)
	assert_eq(Clock.sim.day, 7)
	assert_eq(_state(main).current(main.get("goal_chains")), CHAIN)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	var history: BusinessHistory = main.get("business_history") as BusinessHistory
	var expected: WeeklyChallengeState = null
	var chosen_seed: int = -1
	var expected_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# Pick a seed whose unfiltered week-2 draw is a serving goal, so leaving
	# the first-week filter on cannot accidentally pass with the same choice.
	for seed_value: int in range(50):
		expected_rng.seed = seed_value
		var candidate: WeeklyChallengeState = WeeklyChallengeState.new()
		if candidate.begin_week(8, (main.get("owner_progress") as OwnerProgress).level,
				WEEKLY_CHALLENGES, settings.enabled_recipes(), expected_rng, history, restaurant.seat_count()) \
				and candidate.kind == WeeklyChallenge.Kind.SERVE_IN_ONE_DAY:
			expected = candidate
			chosen_seed = seed_value
			break
	assert_not_null(expected, "the unfiltered pool offers a serving goal")
	if expected == null:
		return
	GameState.rng(&"weekly").seed = chosen_seed
	_next_morning(main)
	weekly = main.get("weekly_challenge") as WeeklyChallengeState
	assert_eq(Clock.sim.day, 8)
	assert_eq(_state(main).current(main.get("goal_chains")), WEEK_TWO)
	assert_eq(weekly.kind, WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, "Week 2 is unfiltered")
	assert_eq(weekly.to_dict(), expected.to_dict())
	assert_eq(GameState.rng(&"weekly").state, expected_rng.state)


func test_price_change_pays_once_as_its_own_ledger_movement() -> void:
	var main: Node = await _start(false)
	var cash: int = Economy.cash
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var dish: RecipeDef = settings.enabled_recipes()[0]
	var price: int = settings.price_of(dish)
	assert_true(main.call("menu_set_price", dish.id, price))
	assert_eq(Economy.cash, cash, "setting the same price is no change")
	assert_true(main.call("menu_set_price", dish.id, price + 1))
	var reward: int = CHAIN.by_id(&"change_price").reward_cash
	assert_eq(Economy.cash, cash + reward)
	assert_eq(_bonus_entries(), [reward] as Array[int], "one ledger movement for the goal")
	assert_true(main.call("menu_set_price", dish.id, price + 2))
	assert_eq(Economy.cash, cash + reward, "the goal pays once only")
	assert_true(_state(main).is_completed(&"change_price"))
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var lines: Array[String] = hud.call("opening_week_lines")
	assert_eq(lines[0], OpeningWeekText.tracker_line(CHAIN.by_id(&"place_decor")), "the tracker moves on")
	assert_true(_logged(main, OpeningWeekText.met_line(CHAIN, CHAIN.by_id(&"change_price"))), "a log line names the goal")


func test_decor_pays_at_opening_but_other_furniture_does_not() -> void:
	var main: Node = await _start(false)
	assert_true(_buy_anywhere(main, &"chair"), "a chair is placed")
	assert_true(_buy_anywhere(main, &"lamp_floor_round"), "a floor lamp is placed")
	assert_eq(_bonus_entries(), [] as Array[int], "nothing pays before opening")
	var cash: int = Economy.cash
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"place_decor"), "the lamp is still there at opening")
	assert_eq(_bonus_entries(), [CHAIN.by_id(&"place_decor").reward_cash] as Array[int])
	assert_eq(Economy.cash, cash + CHAIN.by_id(&"place_decor").reward_cash)


func test_buy_then_undo_before_opening_pays_nothing() -> void:
	var main: Node = await _start(false)
	assert_true(main.call("set_build_active", true))
	assert_true(_buy_anywhere(main, &"lamp_floor_round"))
	assert_true(main.call("undo_edit"), "undo the lamp")
	assert_true(_buy_anywhere(main, &"drinks_shelf", true))
	assert_true(main.call("undo_edit"), "undo the drinks shelf")
	assert_true(main.call("set_build_active", false))
	var cash: int = Economy.cash
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_completed(&"place_decor"), "an undone lamp pays nothing")
	assert_false(_state(main).is_completed(&"drink_on_menu"), "an undone shelf pays nothing")
	assert_eq(_bonus_entries(), [] as Array[int])
	assert_eq(Economy.cash, cash)


func test_a_drinks_shelf_puts_beer_on_the_menu_and_pays_at_opening() -> void:
	var main: Node = await _start(false)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_true(_buy_anywhere(main, &"drinks_shelf", true), "a reachable drinks shelf is placed")
	var drinks: int = 0
	for recipe: RecipeDef in settings.enabled_recipes():
		if recipe.is_drink():
			drinks += 1
	assert_true(drinks > 0, "beer goes on the menu by itself")
	assert_false(_state(main).is_completed(&"drink_on_menu"), "not before opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"drink_on_menu"))
	assert_eq(_bonus_entries(), [CHAIN.by_id(&"drink_on_menu").reward_cash] as Array[int])


func test_owner_on_the_floor_and_serving_count_only_during_service() -> void:
	var main: Node = await _start(false)
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	assert_true(restaurant.assign_owner(&"floor"))
	restaurant.served_today = 15
	main.call("_observe_opening_state")
	assert_false(_state(main).is_completed(&"owner_on_floor"), "the morning is not service")
	assert_false(_state(main).is_completed(&"serve_15"))
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"owner_on_floor"), "on the floor at opening")
	assert_true(_state(main).is_completed(&"serve_15"))
	assert_false(_state(main).is_completed(&"serve_25"))
	assert_eq(_bonus_entries().size(), 2)


func test_grow_together_needs_a_new_table_and_server_still_there_at_opening() -> void:
	var main: Node = await _start(false)
	assert_true(_buy_anywhere(main, &"table_2"), "a table is placed")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_completed(&"grow_together"), "a table alone is not enough")
	main.free()
	_mains.clear()
	main = await _start(false)
	var server: StringName = _server_candidate(main)
	assert_false(server.is_empty(), "a server is on offer on day one")
	assert_true(_buy_anywhere(main, &"table_2"))
	assert_true(main.call("staff_hire", server))
	assert_true(main.call("staff_let_go", server), "let go again before opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_completed(&"grow_together"), "the hire must still be there at opening")
	main.free()
	_mains.clear()
	main = await _start(false)
	server = _server_candidate(main)
	assert_true(_buy_anywhere(main, &"table_2"))
	assert_true(main.call("staff_hire", server))
	var cash: int = Economy.cash
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"grow_together"))
	assert_eq(Economy.cash, cash + CHAIN.by_id(&"grow_together").reward_cash)


func test_close_adds_the_xp_and_the_rating_goal() -> void:
	var main: Node = await _start(false)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var dish: RecipeDef = settings.enabled_recipes()[0]
	assert_true(main.call("menu_set_price", dish.id, settings.price_of(dish) + 1))
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var xp_before: int = owner.total_xp
	_five_star_reviews(main, 5)
	_close_day(main)
	var report: DayReport = main.get("shown_report") as DayReport
	var opening_xp: int = CHAIN.by_id(&"change_price").reward_xp + CHAIN.by_id(&"five_star_day").reward_xp
	assert_eq(int(report.owner_xp_breakdown.get("opening_week_xp", 0)), opening_xp)
	assert_true(owner.total_xp >= xp_before + opening_xp)
	assert_eq(_state(main).pending_xp, 0)
	assert_true(_state(main).is_completed(&"five_star_day"), "five 5-star reviews today meet the goal at close")
	assert_eq(int(report.income.get(Ledger.OPENING_WEEK_BONUS, 0)),
		CHAIN.by_id(&"change_price").reward_cash + CHAIN.by_id(&"five_star_day").reward_cash)


func test_a_guest_paid_on_the_closing_tick_counts_and_close_toasts_wait() -> void:
	var main: Node = await _start(false)
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	_five_star_reviews(main, 5)
	_close_day(main)
	# The 15th guest paid after the phase had turned CLOSED: the live check
	# missed them, so the close counts today's guests once more.
	assert_true(_state(main).is_completed(&"five_star_day"))
	assert_false(_state(main).is_completed(&"serve_15"))
	restaurant.served_today = 15
	main.call("_close_opening_week", Clock.sim.day)
	assert_true(_state(main).is_completed(&"serve_15"), "the close counts today's guests")
	var held: Array[String] = main.get("_held_opening_toasts")
	assert_true(held.size() >= 2, "toasts met under the evening report wait for the next day")
	var expected: Array[String] = held.duplicate()
	var hud: Node = main.get_node("HUD")
	# The top bar's Next day calls the clock directly, not the report's button.
	Clock.sim.next_day()
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_true((main.get("_held_opening_toasts") as Array[String]).is_empty())
	# The first toast is on screen; the rest wait in the HUD's queue.
	var texts: Array[String] = []
	var shown: Label = hud.get("_collection_toast_label") as Label
	if shown != null:
		texts.append(shown.text)
	for entry: Dictionary in hud.get("_collection_toast_queue"):
		texts.append(String(entry["text"]))
	for line: String in expected:
		assert_true(texts.has(line), "held toast reaches the HUD in the morning: %s" % line)


func test_progress_survives_the_morning_save_and_reload() -> void:
	var main: Node = await _start(true)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var dish: RecipeDef = settings.enabled_recipes()[0]
	assert_true(main.call("menu_set_price", dish.id, settings.price_of(dish) + 1))
	_close_day(main)
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.day, 2)
	var cash: int = Economy.cash
	var saved: Dictionary = _document()
	assert_eq((saved["data"] as Dictionary)["opening_week"]["completed"], ["change_price"])
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 2, "the morning save loaded")
	assert_true(_state(main).is_active())
	assert_eq(_state(main).completed_ids(), [&"change_price"] as Array[StringName])
	assert_eq(Economy.cash, cash)
	settings = main.get("menu_settings") as MenuSettings
	dish = settings.enabled_recipes()[0]
	assert_true(main.call("menu_set_price", dish.id, settings.price_of(dish) + 1))
	assert_eq(Economy.cash, cash, "a loaded, completed goal never pays again")


func test_old_saves_past_day_seven_join_week_two_inside_its_window() -> void:
	var main: Node = await _start(true)
	for step: int in 8:
		_next_morning(main)
	assert_eq(Clock.sim.day, 9)
	var document: Dictionary = _document()
	(document["data"] as Dictionary).erase("opening_week")
	_write_document(document)
	_remove_backup()
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 9, "the old save loaded")
	assert_true(_state(main).is_active(), "a save from before the chains, on day 9, gets Week 2")
	assert_eq(_state(main).current(main.get("goal_chains")), WEEK_TWO)
	assert_eq(_state(main).start_day, 8, "with the days of its window that remain")
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	assert_eq(hud.call("opening_week_title"), "Week 2")
	# Past day 21 an old save has no chain at all.
	for step: int in 13:
		_next_morning(main)
	assert_eq(Clock.sim.day, 22)
	document = _document()
	(document["data"] as Dictionary).erase("opening_week")
	_write_document(document)
	_remove_backup()
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 22)
	assert_false(_state(main).is_active(), "past Week 3's window there is no chain")
	hud = main.get_node("HUD") as CanvasLayer
	assert_eq((hud.call("opening_week_lines") as Array).size(), 0, "no tracker")


func test_a_version_one_save_hands_over_to_week_two() -> void:
	var main: Node = await _start(true)
	for step: int in 9:
		_next_morning(main)
	assert_eq(Clock.sim.day, 10)
	var document: Dictionary = _document()
	# What #494 wrote once the Opening week was over.
	(document["data"] as Dictionary)["opening_week"] = {"version": 1, "status": "ended",
		"completed": ["change_price", "serve_15"], "pending_xp": 0}
	_write_document(document)
	_remove_backup()
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 10)
	assert_true(_state(main).is_active())
	assert_eq(_state(main).current(main.get("goal_chains")), WEEK_TWO)
	assert_eq(_state(main).last_day(WEEK_TWO), 14, "an old save keeps the days of the window that remain")
	assert_true(_state(main).completed_ids().is_empty())
	assert_eq(int(_document()["data"]["opening_week"]["version"]), 2, "the load's morning saves version 2")


func test_old_saves_inside_the_week_join_the_chain() -> void:
	var main: Node = await _start(true)
	reset_weekly_for_synthetic_day_jump(main)
	Clock.sim.day += 1
	main.call("_begin_morning")
	var document: Dictionary = _document()
	(document["data"] as Dictionary).erase("opening_week")
	_write_document(document)
	_remove_backup()
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 2)
	assert_true(_state(main).is_active())
	assert_true(_state(main).completed_ids().is_empty())


func test_week_two_follows_the_morning_after_day_seven() -> void:
	var main: Node = await _start(false)
	for step: int in 6:
		_next_morning(main)
	assert_eq(Clock.sim.day, 7)
	assert_eq(_state(main).current(main.get("goal_chains")), CHAIN, "day 7 still has the Opening week")
	_state(main).observe(OpeningGoal.Condition.PRICE_CHANGED, 1.0, CHAIN)
	_next_morning(main)
	assert_true(_state(main).is_active())
	assert_eq(_state(main).current(main.get("goal_chains")), WEEK_TWO, "Week 2 starts on day 8")
	assert_eq(_state(main).start_day, 8)
	assert_true(_state(main).completed_ids().is_empty(), "its own goals, none done")
	assert_true(_logged(main, OpeningWeekText.started_line(WEEK_TWO)))
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	assert_eq(hud.call("opening_week_title"), "Week 2", "the tracker carries the new title")
	var lines: Array[String] = hud.call("opening_week_lines")
	assert_eq(lines, [OpeningWeekText.tracker_line(WEEK_TWO.goals[0]), OpeningWeekText.tracker_line(WEEK_TWO.goals[1]),
		OpeningWeekText.tracker_line(WEEK_TWO.goals[2])] as Array[String])
	assert_true(main.call("set_goals_visible", true))
	var goals: GoalsPanel = main.get_node("Overlay/GoalsPanel") as GoalsPanel
	assert_eq(goals.opening_goal_ids(), [&"bigger_lease", &"lay_floor", &"big_table"] as Array[StringName])
	var card: Node = goals.get_node("%List").get_node_or_null("OpeningWeek")
	assert_not_null(card, "the same card")
	if card != null:
		assert_eq((card.get_node("Body/Header/Title") as Label).text, "Week 2")
		assert_true((card.get_node("Body/Header/Status") as Label).text.contains("0 / 8 done   7 days left"))
	for step: int in 7:
		_next_morning(main)
	assert_eq(Clock.sim.day, 15)
	assert_eq(_state(main).current(main.get("goal_chains")).id, &"week_three", "Week 2 ends after day 14")
	assert_eq(hud.call("opening_week_title"), "Week 3", "Week 3 takes over the tracker")
	for step: int in 7:
		_next_morning(main)
	assert_eq(Clock.sim.day, 22)
	assert_false(_state(main).is_active(), "Week 3 ends after day 21")
	assert_eq(_state(main).status, OpeningWeek.Status.FINISHED)
	assert_eq((hud.call("opening_week_lines") as Array).size(), 0, "the tracker goes away")
	goals.call("_render")
	assert_null(goals.get_node("%List").get_node_or_null("OpeningWeek"), "the card goes away")


func test_finishing_every_goal_ends_the_chain_at_once() -> void:
	var main: Node = await _start(false)
	var state: OpeningWeek = _state(main)
	for goal: OpeningGoal in CHAIN.goals:
		if goal.id != &"place_decor":
			state.observe(goal.condition, goal.target, CHAIN)
	assert_true(state.is_active())
	assert_true(_buy_anywhere(main, &"lamp_floor_round"))
	assert_true(state.is_active(), "the lamp counts at opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_active(), "the last goal ends the chain")
	assert_true(_logged(main, OpeningWeekText.complete_line(CHAIN)))


func test_creative_games_have_no_chain() -> void:
	GameMode.request_new_game(true)
	var main: Node = await _start(false)
	assert_false(_state(main).is_active())
	GameMode.request_new_game(false)


# --- Week 2 (#514) -----------------------------------------------------------

func test_lease_floor_and_table_pay_at_opening_not_before() -> void:
	var main: Node = await _start(false)
	_to_week_two(main)
	_eligible_for_lease(main)
	assert_true(main.call("lease_buy"), "the bigger lease")
	assert_true(main.call("shop_floor", _north_strip(main), true), "six new floor tiles")
	assert_true(_buy_anywhere(main, &"table_4"), "a four-seat table")
	assert_eq(_bonus_entries(), [] as Array[int], "nothing pays before opening")
	var cash: int = Economy.cash
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	for id: StringName in [&"bigger_lease", &"lay_floor", &"big_table"]:
		assert_true(_state(main).is_completed(id), "%s pays at opening" % id)
	var paid: Array[int] = _bonus_entries()
	paid.sort()
	assert_eq(paid, [60, 60, 150] as Array[int], "one ledger movement per goal")
	assert_eq(Economy.cash, cash + 270)
	assert_true(_logged(main, OpeningWeekText.met_line(WEEK_TWO, WEEK_TWO.by_id(&"bigger_lease"))))


func test_undone_floor_and_table_pay_nothing_and_small_tables_never_count() -> void:
	var main: Node = await _start(false)
	_to_week_two(main)
	_eligible_for_lease(main)
	assert_true(main.call("lease_buy"))
	assert_true(main.call("set_build_active", true))
	assert_true(main.call("shop_floor", _north_strip(main), true))
	assert_true(main.call("undo_edit"), "undo the floor")
	assert_true(_buy_anywhere(main, &"round_table"))
	assert_true(main.call("undo_edit"), "undo the round table")
	assert_true(_buy_anywhere(main, &"table_2"), "a two-seat table is not a big one")
	var strip: Array[Vector2i] = _north_strip(main)
	assert_true(main.call("shop_floor", strip.slice(0, 5), true), "five tiles are one short")
	assert_true(main.call("set_build_active", false))
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"bigger_lease"))
	assert_false(_state(main).is_completed(&"lay_floor"), "undone and short floor pays nothing")
	assert_false(_state(main).is_completed(&"big_table"), "an undone table pays nothing")
	assert_eq(_bonus_entries(), [WEEK_TWO.by_id(&"bigger_lease").reward_cash] as Array[int])


func test_a_fried_dish_on_the_menu_pays_at_opening() -> void:
	var main: Node = await _start(false)
	_to_week_two(main)
	_raise_level(main, 2)
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	assert_false(_state(main).is_completed(&"fried_dish"))
	Economy.cash = 5000
	assert_true(_buy_fryer_with_fries(main), "a reachable fryer and fries on the menu")
	assert_true(settings.enabled_recipes().has(settings.recipe(&"fries")))
	assert_false(_state(main).is_completed(&"fried_dish"), "not before opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"fried_dish"))
	assert_eq(_bonus_entries(), [WEEK_TWO.by_id(&"fried_dish").reward_cash] as Array[int])


func test_a_second_cook_at_opening_pays_but_one_let_go_does_not() -> void:
	var main: Node = await _start(false)
	_to_week_two(main)
	assert_true(_add_member(main, &"cook", &"test_cook"))
	assert_true(main.call("staff_let_go", &"test_cook"), "let go again before opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_completed(&"second_cook"), "the hire must still be there at opening")
	main.call("run_ticks", 3)
	assert_true(Clock.sim.next_day())
	assert_true(_add_member(main, &"cook", &"test_cook_2"))
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"second_cook"), "the starter cook plus one")


# --- Week 3 (early-game audit 2) ---------------------------------------------

func test_a_bench_bought_before_week_three_pays_at_its_first_opening() -> void:
	var main: Node = await _start(false)
	assert_true(_buy_anywhere(main, &"waiting_bench"), "a bench bought in the Opening week")
	_to_week_three(main)
	assert_eq(_bonus_entries(), [] as Array[int], "nothing pays before opening")
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"waiting_bench"), "a bench already owned counts")
	assert_eq(_bonus_entries(), [40] as Array[int])


func test_a_cleaner_on_the_team_at_week_three_opening_pays() -> void:
	var main: Node = await _start(false)
	_to_week_three(main)
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_false(_state(main).is_completed(&"hire_cleaner"), "no cleaner yet")
	main.call("run_ticks", 3)
	assert_true(Clock.sim.next_day())
	assert_true(_add_member(main, &"cleaner", &"test_cleaner_3"))
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_true(_state(main).is_completed(&"hire_cleaner"))


func test_a_seated_group_counts_when_it_pays() -> void:
	var main: Node = await _start(false)
	_to_week_two(main)
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	var single: CustomerAgent = CustomerAgent.new(restaurant, RandomNumberGenerator.new())
	main.call("_observe_opening_party", single)
	var waiting: CustomerAgent = CustomerAgent.new(restaurant, RandomNumberGenerator.new())
	waiting.party = Party.new([901, 902])
	main.call("_observe_opening_party", waiting)
	assert_false(_state(main).is_completed(&"seat_group"), "a lone guest or a party still waiting is no seated group")
	var pair: CustomerAgent = CustomerAgent.new(restaurant, RandomNumberGenerator.new())
	pair.party = Party.new([903, 904])
	pair.party.seated = true
	main.call("_observe_opening_party", pair)
	assert_true(_state(main).is_completed(&"seat_group"), "a seated pair counts")
	assert_eq(_bonus_entries(), [WEEK_TWO.by_id(&"seat_group").reward_cash] as Array[int])


func test_thirty_guests_and_a_calm_day_pay() -> void:
	var main: Node = await _start(false)
	_to_week_two(main)
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	var stars: ReputationBook = main.get("reputation") as ReputationBook
	# Day 8: 4.0 stars, but one guest gave up waiting.
	for i: int in 5:
		stars.record_event_review(5)
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	restaurant.served_today = 29
	main.call("_observe_opening_state")
	assert_false(_state(main).is_completed(&"serve_30"))
	restaurant.served_today = 30
	main.call("_observe_opening_state")
	assert_true(_state(main).is_completed(&"serve_30"), "30 guests in a day")
	restaurant.leave_reasons_today[&"waited_too_long"] = 1
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_false(_state(main).is_completed(&"calm_day"), "one guest giving up spoils the day")
	# Day 9: guests turned away for want of a table do not count, still 4.0 stars.
	assert_true(Clock.sim.next_day())
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	restaurant.leave_reasons_today[&"no_table"] = 12
	restaurant.leave_reasons_today[&"too_expensive"] = 2
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(_state(main).is_completed(&"calm_day"), "no guest gave up waiting; no-table and other leaves do not count")
	assert_eq(_bonus_entries(), [WEEK_TWO.by_id(&"calm_day").reward_cash] as Array[int])


func test_the_morning_card_shows_a_fresh_day_not_yesterdays_counts() -> void:
	var main: Node = await _start(false)
	_to_week_two(main)
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	restaurant.served_today = 12
	restaurant.leave_reasons_today[&"waited_too_long"] = 1
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(Clock.sim.next_day())
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	var values: Dictionary = main.call("_opening_values")
	assert_eq(values[OpeningGoal.Condition.SERVED_TODAY], 0.0, "yesterday's guests are not today's")
	assert_true(float(values[OpeningGoal.Condition.CALM_DAY_STARS]) >= 0.0, "yesterday's leaver does not spoil today")


func test_a_calm_day_below_three_and_a_half_stars_does_not_pay() -> void:
	var main: Node = await _start(false)
	_to_week_two(main)
	var stars: ReputationBook = main.get("reputation") as ReputationBook
	assert_true(stars.average() < 3.45, "the starting rating is below 3.5 stars")
	_close_day(main)
	assert_false(_state(main).is_completed(&"calm_day"))


func test_closed_day_neither_pays_goals_nor_loses_the_weekly_calendar_on_reload() -> void:
	var main: Node = await _start(true)
	_to_week_two(main)
	var pool: WeeklyChallengePool = WeeklyChallengePool.new()
	pool.challenges = [WEEKLY_CHALLENGES.by_id(&"lose_no_guests_three_days")]
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 476
	var weekly: WeeklyChallengeState = WeeklyChallengeState.new()
	assert_true(weekly.begin_week(Clock.sim.day, 1, pool, [], random))
	main.set("weekly_challenge", weekly)
	# Earn two qualifying service days so the next one would pay the reward.
	for day: int in 2:
		_close_day(main)
		assert_true(Clock.sim.next_day())

	weekly = main.get("weekly_challenge") as WeeklyChallengeState
	assert_true(weekly.is_active())
	assert_eq(weekly.progress, 2)
	var stars: ReputationBook = main.get("reputation") as ReputationBook
	for review: int in 5:
		stars.record_event_review(5)
	assert_true(stars.average() >= WEEK_TWO.by_id(&"calm_day").target)
	assert_true(_add_member(main, &"cleaner", &"test_closed_day_cleaner"))
	# Set up a roster still waiting for a cook. Staff cannot dismiss the last one.
	var roster: StaffRoster = main.get("staff_roster") as StaffRoster
	var staff: Dictionary = roster.to_dict()
	staff["members"] = staff["members"].filter(func(row: Dictionary) -> bool: return row["role"] != "cook")
	assert_true(roster.from_dict(staff))
	assert_true((main.get("sim") as RestaurantSim).set_staff_roster(roster.members()))
	main.call("_refresh_opening_block")
	assert_false(Clock.sim.start_service(), "a shop without a cook cannot open")
	var closed_day: int = Clock.sim.day
	assert_true(main.call("close_for_today"))
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_false(_state(main).is_completed(&"calm_day"))
	assert_false(_state(main).is_completed(&"second_cook"))
	assert_eq(_bonus_entries(), [] as Array[int])
	assert_eq(Economy.ledger.day_totals(closed_day).get(Ledger.WEEKLY_CHALLENGE_BONUS, 0), 0,
		"no-lost-guests reward requires a service day")
	weekly = main.get("weekly_challenge") as WeeklyChallengeState
	assert_true(weekly.is_active(), "the closed day cannot complete the weekly challenge")
	assert_eq(weekly.progress, 2, "the closed day cannot earn weekly progress")
	assert_eq(weekly.last_evaluated_day, closed_day)
	var expected: Dictionary = weekly.to_dict()

	assert_true(Clock.sim.next_day())
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, closed_day + 1)
	weekly = main.get("weekly_challenge") as WeeklyChallengeState
	assert_eq(weekly.to_dict(), expected, "the same active challenge loaded the next morning")
	assert_false(_state(main).is_completed(&"calm_day"))
	assert_false(_state(main).is_completed(&"second_cook"))
	roster = main.get("staff_roster") as StaffRoster
	var candidate: StaffMember = roster.candidates()[0]
	assert_eq(candidate.role, &"cook")
	assert_true(main.call("staff_hire", candidate.id))
	_close_day(main)
	weekly = main.get("weekly_challenge") as WeeklyChallengeState
	assert_eq(weekly.status, WeeklyChallengeState.Status.COMPLETED)
	assert_eq(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.WEEKLY_CHALLENGE_BONUS, 0), weekly.reward_cash)
	assert_true(_state(main).is_completed(&"calm_day"))
	assert_false(_state(main).is_completed(&"second_cook"), "one cook is not two")


func test_week_two_progress_survives_the_morning_save_and_reload() -> void:
	var main: Node = await _start(true)
	_to_week_two(main)
	_state(main).observe(OpeningGoal.Condition.SERVED_TODAY, 30.0, WEEK_TWO)
	_next_morning(main)
	assert_eq(Clock.sim.day, 9)
	var row: Dictionary = _document()["data"]["opening_week"]
	assert_eq(int(row["version"]), 2)
	assert_eq(row["chain"], "week_two")
	assert_eq(int(row["start_day"]), 8)
	assert_eq(row["completed"], ["serve_30"])
	_close(main)
	main = await _start(true)
	assert_eq(Clock.sim.day, 9, "the morning save loaded")
	assert_true(_state(main).is_active())
	assert_eq(_state(main).current(main.get("goal_chains")), WEEK_TWO)
	assert_eq(_state(main).completed_ids(), [&"serve_30"] as Array[StringName])
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	assert_eq(hud.call("opening_week_title"), "Week 2")
	(main.get("sim") as RestaurantSim).served_today = 40
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	assert_eq(_bonus_entries(), [] as Array[int], "a loaded, completed goal never pays again")


func _next_morning(main: Node) -> void:
	reset_weekly_for_synthetic_day_jump(main)
	Clock.sim.day += 1
	main.call("_begin_morning")


## Seven synthetic mornings: day 8, the first morning of Week 2.
func _to_week_two(main: Node) -> void:
	for step: int in 7:
		_next_morning(main)
	assert_eq(_state(main).current(main.get("goal_chains")), WEEK_TWO)


## Fourteen synthetic mornings: day 15, the first morning of Week 3.
func _to_week_three(main: Node) -> void:
	for step: int in 14:
		_next_morning(main)
	assert_eq(_state(main).current(main.get("goal_chains")).id, &"week_three")


func _raise_level(main: Node, level: int) -> void:
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	if progress.level < level:
		progress.award_bonus(progress.threshold_for(level) - progress.total_xp)
	(main.get("menu_settings") as MenuSettings).set_owner_level(progress.level)
	(main.get("shop_editor") as ShopEditor).set_owner_level(progress.level)
	main.call("_refresh_menu_catalogue")


## As test_lease_session: the authored level for career Tier 2 and the deposit.
func _eligible_for_lease(main: Node) -> void:
	_raise_level(main, CAREER.rung_for(2).min_level)
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	assert_eq(progress.raise_career_tier(CAREER, 3.0), 2)
	(main.get("shop_editor") as ShopEditor).set_career_tier(progress.career_tier)
	Economy.cash = LEASE.deposit + 10000


## Six cells in the row just north of the building, inside the bigger lot.
func _north_strip(main: Node) -> Array[Vector2i]:
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var building: Rect2i = editor.footprint().building
	var cells: Array[Vector2i] = []
	for x: int in range(building.position.x + 1, building.position.x + 7):
		cells.append(Vector2i(x, building.position.y - 1))
	return cells


## A fryer on the first spot whose work cell the kitchen can reach, with fries
## switched on in the menu.
func _buy_fryer_with_fries(main: Node) -> bool:
	var world: SimWorld = main.get("world") as SimWorld
	var cells: Array[Vector2i] = world.grid.cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in cells:
		for turns: int in 4:
			var before: Dictionary[int, bool] = {}
			for placed: PlacedItem in world.grid.items():
				before[placed.id] = true
			if main.call("shop_buy", &"fryer", cell, turns):
				if main.call("menu_set_enabled", &"fries", true):
					return true
				for placed: PlacedItem in world.grid.items():
					if not before.has(placed.id):
						main.call("shop_sell", placed.id)
	return false


## Adds a hired member through the roster, as the balance probe does.
func _add_member(main: Node, role: StringName, id: StringName) -> bool:
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	var roster: StaffRoster = main.get("staff_roster") as StaffRoster
	var snapshot: Dictionary = roster.to_dict()
	var members: Array = snapshot["members"]
	var member: StaffMember = StaffMember.new()
	member.id = id
	member.display_name = "Test %s" % String(role)
	member.role = role
	member.skill = 3
	member.wage = restaurant.pricing_tuning.staff_wage(role, 3)
	member.trait_id = &"steady"
	members.append(member.to_dict())
	snapshot["members"] = members
	return roster.from_dict(snapshot) and restaurant.set_staff_roster(roster.members())


func _start(saves: bool) -> Node:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 7)
	main.set("skip_owner_picker", true)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _state(main: Node) -> OpeningWeek:
	return main.get("opening_week") as OpeningWeek


func _bonus_entries() -> Array[int]:
	var amounts: Array[int] = []
	for entry: Dictionary in Economy.ledger.entries_for_day(Clock.sim.day):
		if entry["category"] == Ledger.OPENING_WEEK_BONUS:
			amounts.append(int(entry["amount"]))
	return amounts


func _logged(main: Node, line: String) -> bool:
	var world: SimWorld = main.get("world") as SimWorld
	for row: Variant in world.event_log:
		if str(row).contains(line):
			return true
	return false


## Places the item on the first cell the real editor accepts. With
## `needs_drink`, a station must also open a drink (a reachable work cell).
func _buy_anywhere(main: Node, item_id: StringName, needs_drink: bool = false) -> bool:
	var world: SimWorld = main.get("world") as SimWorld
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var cells: Array[Vector2i] = world.grid.cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in cells:
		for turns: int in 4:
			var before: Dictionary[int, bool] = {}
			for placed: PlacedItem in world.grid.items():
				before[placed.id] = true
			if main.call("shop_buy", item_id, cell, turns):
				if not needs_drink:
					return true
				for recipe: RecipeDef in settings.enabled_recipes():
					if recipe.is_drink():
						return true
				# Its work cell faces a wall: sell it and try the next spot.
				for placed: PlacedItem in world.grid.items():
					if not before.has(placed.id):
						main.call("shop_sell", placed.id)
	return false


func _server_candidate(main: Node) -> StringName:
	for member: StaffMember in (main.get("staff_roster") as StaffRoster).candidates():
		if member.role == &"server":
			return member.id
	return &""


## Ten fives: a rating well above four stars, whatever today adds.
func _five_star_reviews(main: Node, count: int) -> void:
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	for i: int in count:
		restaurant.reviews_today.append({"stars": 5})


func _quiet_service(main: Node) -> void:
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	restaurant.spawner.min_gap = 100000
	restaurant.spawner.max_gap = 100000
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1


func _close_day(main: Node) -> void:
	_quiet_service(main)
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")))


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_save_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_backup() -> void:
	var path: String = _save_dir.path_join(SLOT + ".json.bak")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
