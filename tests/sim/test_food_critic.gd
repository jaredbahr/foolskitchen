extends TestCase
## The disguised food critic (#303): when one comes, what gives them away, how
## their review weighs and what the player is told.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CRITIC: CriticTuning = preload("res://data/balance/critic.tres")
const REVIEWS: ReviewTuning = preload("res://data/balance/reviews.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")

var _draws: int = 0


func _always() -> CriticTuning:
	var tuning: CriticTuning = CRITIC.duplicate() as CriticTuning
	tuning.daily_chance = 1.0
	return tuning


func _provider(seed_value: int) -> Callable:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return func() -> RandomNumberGenerator:
		_draws += 1
		return random


func _days(critic: FoodCritic, level: int, provider: Callable, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for day: int in range(1, count + 1):
		critic.plan_day(day, level, provider)
		if critic.pending:
			out.append({"day": day, "tells": critic.tells.duplicate(), "at": critic.arrival_permille})
	return out


func test_data_is_valid_and_has_the_specified_defaults() -> void:
	assert_true(CRITIC.is_valid())
	assert_eq(CRITIC.unlock_level, 2)
	assert_eq(CRITIC.cooldown_days, 5)
	assert_almost_eq(CRITIC.daily_chance, 0.2)
	assert_eq(CRITIC.review_weight, 5)
	assert_eq(CRITIC.tell_count, 2)
	assert_almost_eq(CRITIC.linger_multiplier, 1.2)


func test_no_critic_before_level_two_and_the_stream_is_not_touched() -> void:
	var critic: FoodCritic = FoodCritic.new(_always())
	_draws = 0
	var days: Array[Dictionary] = _days(critic, 1, _provider(1), 60)
	assert_eq(days.size(), 0)
	assert_eq(_draws, 0, "the named stream is created only once a critic can appear")
	assert_eq(critic.last_visit_day, 0)
	days = _days(FoodCritic.new(_always()), 2, _provider(1), 3)
	assert_eq(days.size(), 1)
	assert_true(_draws > 0)


func test_at_most_one_critic_in_five_days() -> void:
	var critic: FoodCritic = FoodCritic.new(_always())
	var days: Array[Dictionary] = _days(critic, 4, _provider(7), 200)
	assert_true(days.size() >= 30, "with a certain chance they come every fifth day")
	for index: int in range(1, days.size()):
		assert_true(int(days[index]["day"]) - int(days[index - 1]["day"]) >= 5)
	# The real chance: still never closer than five days.
	days = _days(FoodCritic.new(CRITIC), 4, _provider(8), 400)
	assert_true(days.size() > 5 and days.size() < 80)
	for index: int in range(1, days.size()):
		assert_true(int(days[index]["day"]) - int(days[index - 1]["day"]) >= 5)


func test_same_seed_gives_the_same_days_and_tells() -> void:
	var first: Array[Dictionary] = _days(FoodCritic.new(CRITIC), 3, _provider(303), 300)
	var second: Array[Dictionary] = _days(FoodCritic.new(CRITIC), 3, _provider(303), 300)
	var other: Array[Dictionary] = _days(FoodCritic.new(CRITIC), 3, _provider(304), 300)
	assert_true(first.size() > 5)
	assert_eq(first, second)
	assert_ne(first, other)
	for visit: Dictionary in first:
		var tells: Array = visit["tells"]
		assert_eq(tells.size(), 2)
		assert_ne(tells[0], tells[1])


func test_a_day_is_rolled_once_and_odd_hours_are_odd() -> void:
	var critic: FoodCritic = FoodCritic.new(_always())
	var provider: Callable = _provider(5)
	critic.plan_day(1, 2, provider)
	var plan: Array[StringName] = critic.tells.duplicate()
	_draws = 0
	critic.plan_day(1, 2, provider)
	assert_eq(_draws, 0, "reloading the morning does not redraw")
	assert_eq(critic.tells, plan)
	var odd: int = 0
	for day: int in range(1, 400, 5):
		var other: FoodCritic = FoodCritic.new(_always())
		other.plan_day(day, 2, _provider(day))
		if other.has_tell(FoodCritic.ODD_HOUR):
			odd += 1
			assert_true(other.arrival_permille <= CRITIC.early_arrival_permille.y \
				or other.arrival_permille >= CRITIC.late_arrival_permille.x)
		else:
			assert_true(other.arrival_permille >= CRITIC.normal_arrival_permille.x \
				and other.arrival_permille <= CRITIC.normal_arrival_permille.y)
	assert_true(odd > 10)


func test_the_cooldown_survives_save_and_load_mid_week() -> void:
	var critic: FoodCritic = FoodCritic.new(_always())
	critic.plan_day(1, 2, _provider(11))
	assert_true(critic.pending)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(critic.to_dict())) as Dictionary
	var restored: FoodCritic = FoodCritic.new(_always())
	assert_true(restored.from_dict(saved))
	assert_eq(restored.last_visit_day, 1)
	assert_eq(restored.tells, critic.tells)
	assert_eq(restored.arrival_permille, critic.arrival_permille)
	assert_true(restored.pending, "today's plan is kept")
	_draws = 0
	restored.plan_day(1, 2, _provider(99))
	assert_eq(_draws, 0)
	for day: int in range(2, 6):
		restored.plan_day(day, 2, _provider(99))
		assert_false(restored.pending, "day %d is inside the cooldown" % day)
	restored.plan_day(6, 2, _provider(99))
	assert_true(restored.pending)
	assert_false(FoodCritic.new().from_dict({"version": 1}))
	var bad: Dictionary = saved.duplicate()
	bad["tells"] = ["nonsense"]
	assert_false(FoodCritic.new().from_dict(bad))


func test_the_review_moves_reputation_by_the_data_weight() -> void:
	var book: ReputationBook = ReputationBook.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 1
	var visit: ReviewVisit = _visit(0.95, 0.0)
	var stars: int = ReputationBook.score_visit(visit, REVIEWS)
	var before: float = book.average()
	var row: Dictionary = book.record_critic(visit, REVIEWS, QUOTES, random, CRITIC)
	assert_eq(row["stars"], stars)
	assert_eq(book.scores().size(), 5 + CRITIC.review_weight)
	assert_almost_eq(book.average(), (before * 5.0 + float(stars * CRITIC.review_weight)) / float(5 + CRITIC.review_weight))
	var heavy: CriticTuning = CRITIC.duplicate() as CriticTuning
	heavy.review_weight = 9
	var other: ReputationBook = ReputationBook.new()
	other.record_critic(visit, REVIEWS, QUOTES, random, heavy)
	assert_eq(other.scores().size(), 5 + 9)
	# A closing guest is never reviewed, and a window stays at its limit.
	var closing: ReviewVisit = _visit(0.9, 0.0)
	closing.closing = true
	assert_true(ReputationBook.new().record_critic(closing, REVIEWS, QUOTES, random, CRITIC).is_empty())
	for _round: int in 12:
		book.record_critic(visit, REVIEWS, QUOTES, random, CRITIC)
	assert_eq(book.scores().size(), ReputationBook.WINDOW)


func test_a_good_meal_is_positive_and_a_bad_one_negative() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 2
	var good: Dictionary = ReputationBook.new().record_critic(_visit(0.95, 0.0), REVIEWS, QUOTES, random, CRITIC)
	assert_true(int(good["stars"]) >= CRITIC.good_stars)
	assert_eq(good["cause"], &"critic_good")
	assert_true(QUOTES.groups[&"critic_good"].has(good["quote"]))
	var bad: Dictionary = ReputationBook.new().record_critic(_visit(0.1, 0.9), REVIEWS, QUOTES, random, CRITIC)
	assert_true(int(bad["stars"]) <= CRITIC.bad_stars)
	assert_eq(bad["cause"], &"critic_bad")
	assert_true(QUOTES.groups[&"critic_bad"].has(bad["quote"]))
	var unserved: ReviewVisit = ReviewVisit.new()
	var none: Dictionary = ReputationBook.new().record_critic(unserved, REVIEWS, QUOTES, random, CRITIC)
	assert_eq(none["stars"], 1)
	assert_eq(FoodCritic.verdict_word(5), "A rave review")
	assert_eq(FoodCritic.verdict_word(1), "A scathing review")


func test_six_critic_quotes_three_good_three_bad() -> void:
	assert_true(QUOTES.is_valid())
	assert_eq(QUOTES.groups[&"critic_good"].size(), 3)
	assert_eq(QUOTES.groups[&"critic_bad"].size(), 3)
	for line: String in QUOTES.groups[&"critic_good"] + QUOTES.groups[&"critic_bad"]:
		assert_false(line.to_lower().contains("critic"), "the quote never names the disguise")


func test_report_lines_name_the_visit_and_the_verdict() -> void:
	assert_eq(FoodCritic.report_lines({}), [] as Array[String])
	var lines: Array[String] = FoodCritic.report_lines({"stars": 5, "quote": "Lovely."})
	assert_eq(lines, ["A food critic visited today", "A rave review (5 stars)", "\"Lovely.\""] as Array[String])
	var report: DayReport = DayReport.new()
	report.critic_lines = lines
	assert_eq(DayReport.from_dict(report.to_dict()).critic_lines, lines)
	assert_false(DayReport.new().to_dict().has("critic_lines"), "other days keep their exact shape")


func test_the_inspector_shows_the_tells_but_never_the_word_critic() -> void:
	var sim: RestaurantSim = _sim(31)
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(32), null)
	assert_true(guest.disguise_as_critic([FoodCritic.NOTEBOOK, FoodCritic.PRICIEST] as Array[StringName], CRITIC))
	var panel: InspectPanel = (load("res://src/ui/inspect_panel.tscn") as PackedScene).instantiate() as InspectPanel
	panel.bind_world(sim.world)
	panel.show_agent(guest.id)
	var text: String = (panel.get_node("%Details") as Label).text
	assert_true(text.contains("Scribbling in a little notebook"))
	assert_false(text.contains("most expensive"), "the order is not placed yet")
	guest.order = Order.new()
	panel.refresh()
	text = (panel.get_node("%Details") as Label).text
	assert_true(text.contains("Ordered the most expensive dish"))
	for part: Label in [panel.get_node("%Title"), panel.get_node("%Why"), panel.get_node("%Details")]:
		assert_false(part.text.to_lower().contains("critic"), part.text)
	panel.free()


func test_tells_change_how_the_critic_eats_and_orders() -> void:
	var sim: RestaurantSim = _sim(41)
	sim.set_customer_level(3)
	var plain: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(42), null)
	var meal: int = plain.eat_ticks
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(42), null)
	assert_true(guest.disguise_as_critic([FoodCritic.LINGERS, FoodCritic.PRICIEST] as Array[StringName], CRITIC))
	assert_eq(guest.eat_ticks, roundi(float(meal) * 1.2), "lingers 20% longer")
	assert_eq(guest.quality_weight, CRITIC.quality_weight)
	assert_false(guest.disguise_as_critic([FoodCritic.NOTEBOOK] as Array[StringName], CRITIC), "only once, on arrival")
	guest.state = CustomerAgent.State.ORDERING
	assert_true(guest._take_order(SimAgent.new()))
	var dearest: int = 0
	for recipe: RecipeDef in sim.available_of(RecipeDef.FOOD, sim.available_menu()):
		dearest = maxi(dearest, sim.price_of(recipe))
	assert_eq(guest.order.price, dearest, "orders the most expensive dish")


func test_a_day_with_a_critic_brings_one_disguised_solo_guest_and_one_review() -> void:
	var sim: RestaurantSim = _sim(51)
	sim.set_customer_level(2)
	sim.critic.tuning = _always()
	sim.critic_rng_provider = _provider(52)
	sim.start_day()
	assert_true(sim.critic.pending)
	var critics: Array[CustomerAgent] = []
	sim.world.clock.start_service()
	for _tick: int in 3400:
		sim.advance()
		for guest: CustomerAgent in sim.customers():
			if guest.is_critic() and not critics.has(guest):
				critics.append(guest)
		if not critics.is_empty():
			break
	assert_eq(critics.size(), 1)
	assert_eq(critics[0].critic_tells, sim.critic.tells)
	assert_false(sim.critic.pending)
	assert_eq(critics[0].party, null, "they arrive alone")
	# Their departure is a weighted review, kept apart from the ordinary cards.
	var book_size: int = sim.review_book.scores().size()
	var cards: int = sim.reviews_today.size()
	critics[0].paid = true
	critics[0].order = Order.new()
	critics[0].order.quality = 0.9
	critics[0].order.price = 10
	sim.record_departure(critics[0])
	assert_eq(sim.critic_result.get("stars"), 5)
	assert_eq(sim.review_book.scores().size(), mini(book_size + CRITIC.review_weight, ReputationBook.WINDOW))
	assert_eq(sim.reviews_today.size(), cards)


func _visit(quality: float, food_wait: float) -> ReviewVisit:
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.quality = quality
	visit.quality_weight = CRITIC.quality_weight
	visit.food_wait_fraction = food_wait
	return visit


func _sim(seed_value: int) -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, seed_value, errors, null, false)
	assert_eq(errors, [] as Array[String])
	sim.configure_reviews(ReputationBook.new(), REVIEWS, QUOTES, _random(seed_value + 1))
	return sim


func _random(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
