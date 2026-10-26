extends TestCase
## Customer preferences, actual visit effects and pre-type Regular compatibility.

const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const MAIN: Script = preload("res://tests/fixtures/customer_regular_main.gd")


func test_regular_only_golden_seed_1_against_pre_type_main() -> void:
	_assert_regular_golden(1)


func test_regular_only_golden_seed_7_against_pre_type_main() -> void:
	_assert_regular_golden(7)


func test_regular_only_golden_seed_42_against_pre_type_main() -> void:
	_assert_regular_golden(42)


func test_each_type_captures_multipliers_and_actual_cooked_quality() -> void:
	var sim: RestaurantSim = _sim(52)
	for kind: CustomerType in TYPES.types:
		var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(53), kind)
		assert_eq(guest.customer_type_id, kind.id)
		assert_eq(guest.customer_type_name, kind.display_name)
		assert_eq(guest.queue_patience, roundi(300.0 * kind.patience_multiplier))
		assert_eq(guest.food_patience, roundi(1200.0 * kind.patience_multiplier))
		guest.order = Order.new()
		guest.order.price = 1200
		guest.order.quality = 0.85
		guest.paid = true
		var visit: ReviewVisit = guest.review_visit(1000)
		assert_almost_eq(visit.price_ratio, 1.0 + 0.2 / kind.budget_multiplier)
		assert_eq(visit.quality, 0.85)
		assert_eq(visit.quality_weight, kind.quality_weight)
		assert_eq(visit.review_chance_multiplier, kind.review_chance_multiplier)
		assert_false(guest.configure_type(TYPES.find_type(&"student")), "live guests cannot change type")


func test_standard_and_cheaper_prices_never_refuse_or_penalize_any_type() -> void:
	var sim: RestaurantSim = _sim(61)
	var recipe: RecipeDef = sim.menu[0]
	sim.menu = [recipe]
	var review_tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	review_tuning.overprice_weight = 4.0
	for price: int in [recipe.standard_price, roundi(recipe.standard_price * 0.75)]:
		sim.prices[recipe.id] = price
		for index: int in TYPES.types.size():
			var kind: CustomerType = TYPES.types[index]
			var random: RandomNumberGenerator = _random(620 + index)
			var oracle: RandomNumberGenerator = _random(620 + index)
			oracle.randi_range(0, 0)  # Only the recipe choice, never a refusal draw.
			var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random, kind)
			guest.state = CustomerAgent.State.ORDERING
			assert_eq(sim.price_walkout_chance(recipe, kind.budget_multiplier), 0.0)
			assert_true(guest._take_order(SimAgent.new()))
			assert_not_null(guest.order, "%s accepts a standard or cheaper dish" % kind.display_name)
			assert_eq(random.state, oracle.state, "no early walkout draw at an acceptable price")
			if guest.order == null:
				continue
			guest.paid = true
			guest.order.quality = 0.5
			var visit: ReviewVisit = guest.review_visit(recipe.standard_price)
			assert_eq(visit.price_ratio, float(price) / float(recipe.standard_price))
			assert_eq(ReputationBook.score_visit(visit, review_tuning), 5,
				"a standard-price Student receives no overprice penalty")
			if price < recipe.standard_price:
				assert_eq(ReputationBook.cause_of(visit, review_tuning), &"great_value")


func test_budget_scales_only_above_standard_walkouts_and_review_penalties() -> void:
	var sim: RestaurantSim = _sim(67)
	var recipe: RecipeDef = sim.menu[0]
	sim.menu = [recipe]
	sim.prices[recipe.id] = roundi(recipe.standard_price * 1.5)
	sim.pricing_tuning.price_sensitivity = 1.0
	sim.pricing_tuning.max_price_walkout = 1.0
	var excess: float = float(sim.price_of(recipe)) / float(recipe.standard_price) - 1.0
	var review_tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	review_tuning.overprice_weight = 4.0
	for kind: CustomerType in TYPES.types:
		var expected_excess: float = excess / kind.budget_multiplier
		assert_almost_eq(sim.price_walkout_chance(recipe, kind.budget_multiplier), expected_excess)
		var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(68), kind)
		guest.paid = true
		guest.order = Order.new()
		guest.order.price = sim.price_of(recipe)
		guest.order.quality = 0.5
		var visit: ReviewVisit = guest.review_visit(recipe.standard_price)
		assert_almost_eq(visit.price_ratio - 1.0, expected_excess)
		var expected_stars: int = roundi(clampf(5.0 - minf(expected_excess, 1.0) * 4.0, 1.0, 5.0))
		assert_eq(ReputationBook.score_visit(visit, review_tuning), expected_stars)
	var regular_chance: float = sim.price_walkout_chance(recipe, 1.0)
	assert_true(sim.price_walkout_chance(recipe, 0.8) > regular_chance, "Students react sooner to a markup")
	assert_true(sim.price_walkout_chance(recipe, 1.4) < regular_chance, "Foodies tolerate more of the same markup")
	# A sufficiently steep markup refusal consumes exactly the private chance draw.
	sim.pricing_tuning.price_sensitivity = 4.0
	var student_rng: RandomNumberGenerator = _random(69)
	var oracle: RandomNumberGenerator = _random(69)
	oracle.randi_range(0, 0)
	oracle.randf()
	var student: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], student_rng, TYPES.find_type(&"student"))
	student.state = CustomerAgent.State.ORDERING
	assert_eq(sim.price_walkout_chance(recipe, student.budget_multiplier), 1.0)
	assert_true(student._take_order(SimAgent.new()))
	assert_null(student.order)
	assert_eq(student.leave_reason, &"too_expensive")
	assert_eq(student_rng.state, oracle.state)


func test_type_patience_stacks_once_with_cleanliness_vibe_and_server() -> void:
	var sim: RestaurantSim = _sim(64)
	var tuning: CleanlinessTuning = preload("res://data/balance/cleanliness.tres").duplicate() as CleanlinessTuning
	tuning.arrival_chance = 0.0
	tuning.seat_departure_chance = 1.0
	var dirt: CleanlinessState = CleanlinessState.new(sim.world.grid, tuning, _random(65))
	assert_true(sim.configure_cleanliness(dirt, tuning))
	for y: int in sim.world.grid.size.y:
		for x: int in sim.world.grid.size.x:
			dirt.try_spawn_at_departed_seat(Vector2i(x, y))
	var clean_scale: float = dirt.patience_multiplier()
	assert_true(clean_scale < 1.0)
	var vibe: VibeModel.Result = VibeModel.Result.new()
	vibe.valid = true
	vibe.score = 50.0
	vibe.patience_multiplier = 1.1
	vibe.raw_review_bonus = 0.2
	sim.set_vibe(vibe)
	assert_true(sim.world.clock.start_service())
	var kind: CustomerType = TYPES.find_type(&"student").duplicate() as CustomerType
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(66), kind)
	var expected_queue: int = roundi(roundi(300.0 * 1.3) * clean_scale)
	var expected_food: int = roundi(roundi(1200.0 * 1.3) * clean_scale)
	expected_queue = roundi(expected_queue * 1.1)
	expected_food = roundi(expected_food * 1.1)
	assert_eq(guest.queue_patience, expected_queue)
	assert_eq(guest.food_patience, expected_food)
	assert_eq(guest.vibe_review_bonus, 0.2)
	kind.patience_multiplier = 9.0
	kind.display_name = "Changed later"
	assert_eq(guest.customer_type_name, "Student")
	assert_eq(guest.food_patience, expected_food)
	guest.state = CustomerAgent.State.ORDERING
	var server: StaffAgent = StaffAgent.new(&"server")
	server.food_patience_multiplier = 1.2
	# A free menu keeps this patience check independent of pricing choices.
	for recipe: RecipeDef in sim.menu:
		sim.prices[recipe.id] = 0
	assert_true(guest._take_order(server))
	assert_eq(guest.food_patience, roundi(expected_food * 1.2))
	assert_true(guest._take_order(server))
	assert_eq(guest.food_patience, roundi(expected_food * 1.2), "ticket replay must not multiply again")


func test_quality_term_is_real_bounded_and_keeps_unserved_policy() -> void:
	var sim: RestaurantSim = _sim(71)
	var foodie: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(72), TYPES.find_type(&"foodie"))
	foodie.paid = true
	foodie._food_wait = roundi(foodie.food_patience * 0.5)
	foodie.order = Order.new()
	foodie.order.quality = 0.0
	var poor: ReviewVisit = foodie.review_visit(0)
	foodie.order.quality = 1.0
	var good: ReviewVisit = foodie.review_visit(0)
	assert_eq(ReputationBook.score_visit(poor, TUNING), 4)
	assert_eq(ReputationBook.score_visit(good, TUNING), 5)
	assert_eq(ReputationBook.cause_of(good, TUNING), &"lovely_place")
	good.served = false
	assert_eq(ReputationBook.score_visit(good, TUNING), 1)
	good.served = true
	good.quality_weight = INF
	assert_eq(ReputationBook.score_visit(good, TUNING), ReputationBook.score_visit(poor, TUNING))
	good.quality_weight = 1.0e308
	assert_eq(ReputationBook.score_visit(good, TUNING), 5)
	good.quality = NAN
	assert_eq(ReputationBook.score_visit(good, TUNING), ReputationBook.score_visit(poor, TUNING))


func test_foodie_quality_moves_reviews_both_directions_from_neutral() -> void:
	var sim: RestaurantSim = _sim(73)
	var foodie: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(74), TYPES.find_type(&"foodie"))
	foodie.paid = true
	foodie.order = Order.new()
	var tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	tuning.food_wait_weight = 1.0
	foodie._food_wait = roundi(foodie.food_patience * 0.5)
	foodie.order.quality = 0.5
	var neutral: ReviewVisit = foodie.review_visit(0)
	assert_eq(ReputationBook.score_visit(neutral, tuning), 5)
	foodie.order.quality = 0.0
	assert_eq(ReputationBook.score_visit(foodie.review_visit(0), tuning), 4,
		"bad cooked quality lowers a Foodie's otherwise five-star review")
	foodie._food_wait = roundi(foodie.food_patience * 0.6)
	foodie.order.quality = 0.5
	assert_eq(ReputationBook.score_visit(foodie.review_visit(0), tuning), 4)
	foodie.order.quality = 1.0
	assert_eq(ReputationBook.score_visit(foodie.review_visit(0), tuning), 5,
		"good cooked quality improves a Foodie's otherwise four-star review")
	var regular: ReviewVisit = ReviewVisit.new()
	regular.served = true
	regular.food_wait_fraction = 0.5
	for quality: float in [0.0, 0.5, 1.0, NAN]:
		regular.quality = quality
		assert_eq(ReputationBook.score_visit(regular, tuning), 5,
			"Regular's zero quality weight never changes the existing rating")


func test_review_chance_modifier_uses_only_the_dedicated_review_rng() -> void:
	var sim: RestaurantSim = _sim(81)
	var tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	tuning.review_chance = 0.5
	var expected: RandomNumberGenerator = _random(82)
	var actual: RandomNumberGenerator = _random(82)
	var book: ReputationBook = ReputationBook.new()
	var foodie: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(83), TYPES.find_type(&"foodie"))
	foodie.paid = true
	var visit: ReviewVisit = foodie.review_visit(0)
	var arrival_state: int = sim.rng.state
	var guest_state: int = foodie.rng.state
	for index: int in 40:
		var should_review: bool = expected.randf() < 0.7
		var row: Dictionary = book.record_visit(visit, tuning, QUOTES, actual)
		assert_eq(not row.is_empty(), should_review)
		# Quote picking can consume another draw; retain the decision oracle's alignment.
		expected.state = actual.state
	assert_eq(sim.rng.state, arrival_state)
	assert_eq(foodie.rng.state, guest_state)
	visit.closing = true
	var before: int = actual.state
	assert_eq(book.record_visit(visit, tuning, QUOTES, actual), {})
	assert_eq(actual.state, before)
	visit.closing = false
	visit.review_chance_multiplier = NAN
	assert_eq(book.record_visit(visit, tuning, QUOTES, actual), {})
	assert_eq(actual.state, before)


func test_configuration_is_detached_rejects_invalid_and_does_not_draw() -> void:
	var sim: RestaurantSim = _sim(91)
	var before: int = sim.rng.state
	assert_null(sim.customer_types, "legacy simulation starts with Regular only")
	assert_false(sim.configure_customer_types(null, 1))
	assert_false(sim.configure_customer_types(TYPES, 0))
	var invalid: CustomerTypeCatalogue = TYPES.duplicate(true) as CustomerTypeCatalogue
	invalid.types[0].patience_multiplier = NAN
	assert_false(sim.configure_customer_types(invalid, 1))
	assert_null(sim.customer_types)
	assert_true(sim.configure_customer_types(TYPES, 1))
	assert_ne(sim.customer_types, TYPES)
	assert_ne(sim.customer_types.types[0], TYPES.types[0])
	assert_false(sim.set_customer_level(0))
	assert_eq(sim.customer_level, 1)
	assert_true(sim.set_customer_level(4))
	assert_eq(sim.customer_level, 4)
	var count: int = sim.world.agents.size()
	var bad_kind: CustomerType = TYPES.types[0].duplicate() as CustomerType
	bad_kind.party_size_max = 5
	assert_null(sim.add_customer(sim.world.grid.entries()[0], _random(92), bad_kind))
	assert_eq(sim.world.agents.size(), count)
	assert_eq(sim.rng.state, before)


func test_live_spawner_replays_mixed_types_and_observes_level_unlocks() -> void:
	var one: RestaurantSim = _sim(101)
	var two: RestaurantSim = _sim(101)
	for sim: RestaurantSim in [one, two]:
		assert_true(sim.configure_customer_types(TYPES, 1))
		sim.spawner.min_gap = 1
		sim.spawner.max_gap = 1
		sim.world.clock.open_ticks = 500
		sim.start_day()
		assert_true(sim.world.clock.start_service())
	var seen: Dictionary[StringName, bool] = {}
	for index: int in 100:
		one.spawner.advance(one)
		two.spawner.advance(two)
		var first: CustomerAgent = one.customers().back()
		var repeated: CustomerAgent = two.customers().back()
		assert_eq(first.customer_type_id, repeated.customer_type_id)
		assert_eq(first.rng.seed, repeated.rng.seed)
		assert_eq(first.cell, repeated.cell)
		assert_true([&"regular", &"student"].has(first.customer_type_id))
		seen[first.customer_type_id] = true
	assert_eq(seen.size(), 2)
	assert_eq(one.rng.state, two.rng.state)
	assert_true(one.set_customer_level(4))
	seen.clear()
	for index: int in 200:
		one.spawner.advance(one)
		seen[one.customers().back().customer_type_id] = true
	assert_true(seen.has(&"foodie"))
	assert_true(seen.has(&"family"))
	# Existing level-one guests retain their original captured preferences.
	assert_true([&"regular", &"student"].has(one.customers()[0].customer_type_id))


func _assert_regular_golden(seed: int) -> void:
	var legacy: RestaurantSim = _sim(seed, true)
	var typed: RestaurantSim = _sim(seed)
	var regular: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	var single: CustomerType = TYPES.find_type(&"regular").duplicate() as CustomerType
	single.party_size_min = 1
	single.party_size_max = 1
	regular.types = [single]
	assert_true(typed.configure_customer_types(regular, 4))
	for sim: RestaurantSim in [legacy, typed]:
		sim.spawner.min_gap = 90
		sim.spawner.max_gap = 150
		sim.world.clock.open_ticks = 1800
		sim.world.clock.last_orders_max_ticks = 2000
		if seed == 7:
			for recipe: RecipeDef in sim.menu:
				sim.prices[recipe.id] = recipe.standard_price * 2
		sim.start_day()
		assert_true(sim.world.clock.start_service())
	assert_eq(_snapshot(typed), _snapshot(legacy), "seed %d initial state" % seed)
	for tick: int in 3801:
		legacy.advance()
		typed.advance()
		assert_eq(_snapshot(typed), _snapshot(legacy), "seed %d actual-model tick %d" % [seed, tick])
		if legacy.world.clock.phase == SimClock.Phase.CLOSED:
			break
	assert_eq(typed.world.clock.phase, SimClock.Phase.CLOSED)
	assert_true(typed.served_today + typed.lost_today > 5, "the oracle exercises real arrivals and departures")
	if seed == 1:
		assert_true(typed.served_today > 0, "stocked real Kitchen reaches payment and review scoring")
	assert_eq(typed.customers().size(), 0)
	assert_eq(typed.kitchen.plates.total, typed.kitchen.plates.clean + typed.kitchen.plates.dirty + typed.kitchen.plates.in_use)


func _sim(seed: int, legacy: bool = false) -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, seed, errors, null, false)
	assert_eq(errors, [] as Array[String])
	if legacy:
		var original: RestaurantSim = sim
		sim = MAIN.MainRestaurant.new()
		sim.world = original.world
		sim.menu = original.menu
		sim.staff_spawns = original.staff_spawns
		sim.rng = original.rng
		sim.spawner = MAIN.MainSpawner.new(sim.rng)
	if seed != 42:
		for ingredient: IngredientDef in content.ingredients():
			sim.stock.add(ingredient.id, 100, 1)
	sim.kitchen = Kitchen.new(sim, content, sim.stock)
	var book: ReputationBook = MAIN.MainBook.new() if legacy else ReputationBook.new()
	sim.configure_reviews(book, TUNING, QUOTES, _random(seed + 9000))
	return sim


func _snapshot(sim: RestaurantSim) -> Dictionary:
	var guests: Array = []
	for guest: CustomerAgent in sim.customers():
		guests.append([guest.id, guest.state, guest.cell, guest.path.duplicate(), guest.path_index,
			guest.move_progress, guest.table_item_id, guest.seat_cell, guest.queue_patience,
			guest.food_patience, guest._queue_wait, guest._food_wait, guest._walk_wait,
			guest._eating, guest.leave_reason, guest.paid, guest.rng.seed, guest.rng.state])
	var orders: Array = []
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY,
			Order.State.DELIVERED, Order.State.CANCELLED]:
		for order: Order in sim.orders.orders_in_state(state):
			orders.append([order.id, order.customer_id, order.recipe_id, order.price,
				order.placed_tick, order.state, order.quality, order.cancellation_reason])
	return {"now": sim.world.now, "clock": sim.world.clock.to_dict(),
		"rng": sim.rng.state, "review_rng": sim.review_rng.state,
		"next_arrival": sim.spawner._remaining, "guests": guests, "orders": orders,
		"log": sim.world.event_log.duplicate(), "served": sim.served_today, "lost": sim.lost_today,
		"reasons": sim.leave_reasons_today.duplicate(), "reviews": sim.reviews_today.duplicate(true),
		"scores": sim.review_book.scores(), "stock": sim.stock.to_dict(),
		"plates": sim.kitchen.plates.to_dict()}


func _random(seed: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	return random
