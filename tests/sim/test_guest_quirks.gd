extends TestCase
## Guest quirks (docs/GUESTS.md): authored data, the lazy quirks stream, and
## the Shutterbug, Chatterbox and Lunch-breaker effects end to end.

const QUIRKS: GuestQuirkCatalogue = preload("res://data/customers/quirks.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")

var _provider_calls: int = 0


func test_authored_quirks_are_valid_and_their_quotes_exist() -> void:
	assert_true(QUIRKS.is_valid())
	assert_true(QUOTES.is_valid())
	for id: StringName in [&"shutterbug", &"chatterbox", &"lunch_break"]:
		var quirk: GuestQuirk = QUIRKS.find_quirk(id)
		assert_not_null(quirk, "%s is authored" % id)
		if quirk == null:
			continue
		assert_false(quirk.inspect_line.is_empty())
		var lines: PackedStringArray = QUOTES.groups.get(quirk.happy_cause, PackedStringArray())
		assert_true(lines.size() >= 4, "%s has its own quotes" % quirk.happy_cause)
		for line: String in lines:
			assert_true(line.length() <= 90, "short quote: %s" % line)
	var seen: Dictionary[String, bool] = {}
	for cause: StringName in QUOTES.groups:
		for line: String in QUOTES.groups[cause]:
			assert_false(seen.has(line.to_lower()), "no duplicate quote: %s" % line)
			seen[line.to_lower()] = true


func test_bad_quirks_fail_validation() -> void:
	var quirk: GuestQuirk = QUIRKS.find_quirk(&"lunch_break").duplicate() as GuestQuirk
	quirk.fast_food_bonus = 0.0
	assert_false(quirk.is_valid(), "a speed window needs a bonus")
	quirk = QUIRKS.find_quirk(&"shutterbug").duplicate() as GuestQuirk
	quirk.happy_cause = &"not_a_cause"
	assert_false(quirk.is_valid())
	quirk = QUIRKS.find_quirk(&"chatterbox").duplicate() as GuestQuirk
	quirk.linger_multiplier = 0.5
	assert_false(quirk.is_valid())


func test_roll_replays_by_seed_and_respects_types() -> void:
	var first: RandomNumberGenerator = _random(31)
	var second: RandomNumberGenerator = _random(31)
	var hits: int = 0
	for index: int in 400:
		var one: GuestQuirk = QUIRKS.roll(first, &"family")
		var two: GuestQuirk = QUIRKS.roll(second, &"family")
		assert_eq(one, two, "same seed roll %d" % index)
		if one != null:
			hits += 1
			assert_ne(one.id, &"lunch_break", "families are never on a lunch break")
	assert_true(hits > 20 and hits < 90, "about one in eight: %d of 400" % hits)
	var never: GuestQuirkCatalogue = QUIRKS.duplicate(true) as GuestQuirkCatalogue
	never.chance = 0.0
	for _index: int in 50:
		assert_null(never.roll(first, &"regular"))
	assert_null(QUIRKS.roll(null, &"regular"))


func test_no_quirk_stream_below_the_unlock_or_for_special_guests() -> void:
	var sim: RestaurantSim = _sim()
	sim.quirks = QUIRKS
	sim.quirk_rng_provider = _counted_provider
	assert_true(sim.world.clock.start_service())
	sim.set_customer_level(QUIRKS.unlock_level - 1)
	var guest: CustomerAgent = _guest(sim, &"regular", 1)
	assert_false(sim.try_give_quirk(guest))
	assert_eq(_provider_calls, 0, "no stream before the unlock")
	sim.set_customer_level(QUIRKS.unlock_level)
	var critic: CustomerAgent = _guest(sim, &"regular", 2)
	critic.critic_tells = [FoodCritic.NOTEBOOK]
	assert_false(sim.try_give_quirk(critic))
	var member: CustomerAgent = _guest(sim, &"family", 3)
	member.party = Party.new()
	assert_false(sim.try_give_quirk(member))
	assert_eq(_provider_calls, 0, "critics and party members never draw")
	sim.try_give_quirk(_guest(sim, &"regular", 4))
	assert_eq(_provider_calls, 1)


func test_a_quirk_is_applied_once_and_never_to_a_critic() -> void:
	var sim: RestaurantSim = _sim()
	var guest: CustomerAgent = _guest(sim, &"regular", 5)
	assert_true(guest.apply_quirk(QUIRKS.find_quirk(&"chatterbox")))
	assert_false(guest.apply_quirk(QUIRKS.find_quirk(&"shutterbug")), "one quirk per guest")
	var critic: CustomerAgent = _guest(sim, &"regular", 6)
	critic.critic_tells = [FoodCritic.NOTEBOOK]
	assert_false(critic.apply_quirk(QUIRKS.find_quirk(&"shutterbug")))


func test_shutterbug_always_reviews_a_good_visit_with_a_photo_quote() -> void:
	var never: ReviewTuning = TUNING.duplicate() as ReviewTuning
	never.review_chance = 0.0
	var sim: RestaurantSim = _sim()
	var plain: CustomerAgent = _served(_guest(sim, &"regular", 7), 0.1)
	var snapper: CustomerAgent = _served(_guest(sim, &"regular", 8), 0.1)
	assert_true(snapper.apply_quirk(QUIRKS.find_quirk(&"shutterbug")))
	var book: ReputationBook = ReputationBook.new()
	assert_true(book.record_visit(plain.review_visit(1000), never, QUOTES, _random(9)).is_empty())
	var row: Dictionary = book.record_visit(snapper.review_visit(1000), never, QUOTES, _random(9))
	assert_false(row.is_empty(), "a Shutterbug always posts")
	assert_eq(row.get("cause"), &"photo_happy")
	assert_true(QUOTES.groups[&"photo_happy"].has(String(row.get("quote"))))
	# An unserved Shutterbug is like anyone else: no forced review.
	var hungry: CustomerAgent = _guest(sim, &"regular", 10)
	assert_true(hungry.apply_quirk(QUIRKS.find_quirk(&"shutterbug")))
	hungry._reached_dining_seat = true
	assert_true(book.record_visit(hungry.review_visit(1000), never, QUOTES, _random(9)).is_empty())


func test_chatterbox_stays_longer_and_leaves_happier() -> void:
	var sim: RestaurantSim = _sim()
	var plain: CustomerAgent = _guest(sim, &"regular", 11)
	var chatty: CustomerAgent = _guest(sim, &"regular", 12)
	assert_true(chatty.apply_quirk(QUIRKS.find_quirk(&"chatterbox")))
	assert_eq(chatty.eat_ticks, roundi(plain.eat_ticks * 1.5))
	assert_eq(chatty.queue_patience, plain.queue_patience, "patience unchanged")
	_served(plain, 0.5)
	_served(chatty, 0.5)
	# A 4.4 visit rounds to 4; the chat's +0.5 makes it a 5 (4.9).
	var plain_visit: ReviewVisit = plain.review_visit(1000)
	var chatty_visit: ReviewVisit = chatty.review_visit(1000)
	plain_visit.food_wait_fraction = 0.6 / TUNING.food_wait_weight
	chatty_visit.food_wait_fraction = 0.6 / TUNING.food_wait_weight
	assert_eq(ReputationBook.score_visit(plain_visit, TUNING), 4)
	assert_eq(ReputationBook.score_visit(chatty_visit, TUNING), 5)
	assert_eq(ReputationBook.cause_of(chatty_visit, TUNING), &"chatty_happy")
	assert_eq(ReputationBook.cause_of(plain_visit, TUNING), &"lovely_place")


func test_lunch_breaker_is_impatient_and_loves_fast_food() -> void:
	var sim: RestaurantSim = _sim()
	var plain: CustomerAgent = _guest(sim, &"office", 13)
	var hurried: CustomerAgent = _guest(sim, &"office", 14)
	assert_true(hurried.apply_quirk(QUIRKS.find_quirk(&"lunch_break")))
	assert_eq(hurried.queue_patience, roundi(plain.queue_patience * 0.6))
	assert_eq(hurried.food_patience, roundi(plain.food_patience * 0.6))
	var fast: ReviewVisit = _served(hurried, 0.0).review_visit(1000)
	assert_eq(fast.quirk_bonus, 1.0)
	assert_eq(fast.quirk_cause, &"quick_lunch")
	hurried._food_wait = roundi(hurried.food_patience * 0.8)
	var slow: ReviewVisit = hurried.review_visit(1000)
	assert_eq(slow.quirk_bonus, 0.0, "no bonus when lunch was slow")
	assert_eq(slow.quirk_cause, &"")
	assert_ne(ReputationBook.cause_of(slow, TUNING), &"quick_lunch")


func test_guests_without_quirks_review_exactly_as_before() -> void:
	var sim: RestaurantSim = _sim()
	var guest: CustomerAgent = _served(_guest(sim, &"regular", 15), 0.3)
	var visit: ReviewVisit = guest.review_visit(1000)
	assert_false(visit.always_reviews)
	assert_eq(visit.quirk_bonus, 0.0)
	assert_eq(visit.quirk_cause, &"")


func test_the_spawner_gives_quirks_and_leaves_the_customers_stream_alone() -> void:
	var always: GuestQuirkCatalogue = QUIRKS.duplicate(true) as GuestQuirkCatalogue
	always.chance = 1.0
	var plain: RestaurantSim = _spawning_sim(null)
	var quirky: RestaurantSim = _spawning_sim(always)
	for _index: int in 300:
		plain.spawner.advance(plain)
		quirky.spawner.advance(quirky)
	assert_eq(quirky.rng.state, plain.rng.state, "the customers stream is byte-identical")
	var plain_guests: Array[CustomerAgent] = plain.customers()
	var quirky_guests: Array[CustomerAgent] = quirky.customers()
	assert_eq(quirky_guests.size(), plain_guests.size())
	assert_true(quirky_guests.size() > 10, "arrivals: %d" % quirky_guests.size())
	var with_quirk: int = 0
	for index: int in quirky_guests.size():
		var guest: CustomerAgent = quirky_guests[index]
		assert_eq(guest.customer_type_id, plain_guests[index].customer_type_id, "same arrival %d" % index)
		assert_null(plain_guests[index].quirk)
		if guest.party == null and not guest.is_critic():
			assert_not_null(guest.quirk, "the spawner offered every solo arrival a quirk")
		if guest.quirk != null:
			with_quirk += 1
	assert_true(with_quirk > 0)


func test_about_one_guest_in_eight_through_the_named_stream() -> void:
	GameState.new_run(652)
	var sim: RestaurantSim = _sim()
	sim.quirks = QUIRKS
	sim.quirk_rng_provider = GameState.rng.bind(&"quirks")
	sim.set_customer_level(QUIRKS.unlock_level)
	assert_true(sim.world.clock.start_service())
	var hits: int = 0
	for index: int in 800:
		var guest: CustomerAgent = _guest(sim, &"regular", 2000 + index)
		if sim.try_give_quirk(guest):
			hits += 1
		sim.world.remove_agent(guest)
	assert_true(hits > 70 and hits < 135, "about 100 of 800: %d" % hits)
	GameState.new_run(1)


func _spawning_sim(catalogue: GuestQuirkCatalogue) -> RestaurantSim:
	var sim: RestaurantSim = _sim()
	sim.configure_customer_types(TYPES, QUIRKS.unlock_level)
	sim.use_rng(_random(6520))
	if catalogue != null:
		sim.quirks = catalogue
		sim.quirk_rng_provider = _counted_provider
	sim.spawner.min_gap = 1
	sim.spawner.max_gap = 1
	assert_true(sim.world.clock.start_service())
	sim.world.clock.phase_tick = 360
	sim.spawner._remaining = -1  # Draw the first gap from the 1-tick range.
	return sim


func _counted_provider() -> RandomNumberGenerator:
	_provider_calls += 1
	return _random(700 + _provider_calls)


func _guest(sim: RestaurantSim, type_id: StringName, seed: int) -> CustomerAgent:
	return sim.add_customer(sim.world.grid.entries()[0], _random(seed), TYPES.find_type(type_id))


## A paid, seated guest who ate a 1000 dish; `wait` is the share of their food
## patience the food took.
func _served(guest: CustomerAgent, wait: float) -> CustomerAgent:
	guest.paid = true
	guest._reached_dining_seat = true
	guest.order = Order.new()
	guest.order.price = 1000
	guest.order.quality = 0.5
	guest._food_wait = roundi(guest.food_patience * wait)
	return guest


func _sim() -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 637, errors, null, false)
	assert_eq(errors, [] as Array[String])
	return sim


func _random(value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = value
	return random
