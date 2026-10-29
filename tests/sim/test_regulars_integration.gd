extends TestCase
## Real guest arrival, seating, tickets and departure consume the persistent cast.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")


func test_unpromoted_arrivals_and_departures_do_not_create_or_draw_regular_stream() -> void:
	var sim: RestaurantSim = _sim()
	var cast: RegularCast = RegularCast.new()
	sim.regulars = cast
	sim.regular_rng_provider = GameState.rng.bind(&"regulars")
	GameState.new_run(166)
	assert_true(sim.world.clock.start_service())
	var before: int = sim.rng.state
	for index: int in 4:
		var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(index), TYPES.find_type(&"regular"))
		assert_null(guest.regular_profile)
		assert_eq(guest.repeat_guest_key, "guest_%d" % index)
		guest.paid = true
		guest.order = Order.new()
		guest.order.recipe_id = sim.menu[0].id
		guest.order.quality = 0.9
		guest.seat_cell = Vector2i(3, 6)
		sim.record_departure(guest)
	assert_eq(sim.rng.state, before)
	assert_false(GameState._rngs.has(&"regulars"))
	assert_eq(cast.profiles.size(), 0)


func test_due_regular_replaces_one_solo_regular_and_keeps_stable_name_and_look() -> void:
	var sim: RestaurantSim = _sim()
	var profile: RegularProfile = _cast_member(sim)
	sim.world.clock.day = profile.next_visit_day
	assert_true(sim.world.clock.start_service())
	var before: int = sim.rng.state
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(44), TYPES.find_type(&"regular"))
	assert_eq(guest.regular_profile, profile)
	assert_eq(guest.display_name, profile.display_name)
	assert_eq(guest.regular_arrival_tick, sim.world.now)
	assert_true(guest.regular_favourite_available)
	assert_eq(guest.regular_favourite_label, sim.menu[0].display_name)
	assert_eq(sim.rng.state, before, "return scheduling uses its separate named stream")
	var second: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(45), TYPES.find_type(&"regular"))
	assert_null(second.regular_profile, "one regular visits at most once each day")
	assert_eq(sim.regulars.visited_today, [profile.id])


func test_favourite_seat_is_preferred_but_a_busy_seat_never_blocks_another() -> void:
	var sim: RestaurantSim = _sim()
	var profile: RegularProfile = _cast_member(sim)
	var tables: Array[PlacedItem] = []
	for placed: PlacedItem in sim.world.grid.items():
		if not placed.seat_cells.is_empty():
			tables.append(placed)
	var favourite: PlacedItem = tables.back()
	profile.favourite_seat = favourite.seat_cells.back()
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(46))
	guest.regular_profile = profile
	assert_true(guest._try_seat(sim.world))
	assert_eq(guest.seat_cell, profile.favourite_seat)
	var next: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(47))
	next.regular_profile = profile
	assert_true(next._try_seat(sim.world))
	assert_ne(next.seat_cell, profile.favourite_seat)


func test_favourite_orders_only_from_available_menu_and_missing_dish_still_orders() -> void:
	var sim: RestaurantSim = _sim()
	var profile: RegularProfile = _cast_member(sim)
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(48))
	guest.regular_profile = profile
	guest.state = CustomerAgent.State.ORDERING
	assert_true(guest._take_order(SimAgent.new()))
	assert_eq(guest.order.recipe_id, profile.favourite_dish)
	var alternative: RecipeDef = sim.menu[1]
	sim.menu = [alternative]
	var next: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(49))
	next.regular_profile = profile
	next.state = CustomerAgent.State.ORDERING
	assert_true(next._take_order(SimAgent.new()))
	assert_eq(next.order.recipe_id, alternative.id)


func test_real_departure_updates_mood_only_once_and_favourite_has_gentle_tip() -> void:
	var sim: RestaurantSim = _sim()
	var profile: RegularProfile = _cast_member(sim)
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(50))
	guest.regular_profile = profile
	guest.regular_favourite_available = true
	guest.paid = true
	guest.order = Order.new()
	guest.order.recipe_id = profile.favourite_dish
	guest.order.price = 20
	guest.order.quality = 0.9
	guest.seat_cell = profile.favourite_seat
	var mood: float = profile.mood
	sim.record_departure(guest)
	assert_true(profile.mood > mood)
	var changed: float = profile.mood
	sim.record_departure(guest)
	assert_eq(profile.mood, changed)
	assert_eq(sim.regular_tip(guest, guest.order), 2)
	guest.regular_favourite_available = false
	assert_eq(sim.regular_tip(guest, guest.order), 1)
	guest.order.price = 5
	assert_eq(sim.regular_tip(guest, guest.order), 0)
	guest.regular_favourite_available = true
	assert_eq(sim.regular_tip(guest, guest.order), 1, "a modest drink keeps its visible favourite bonus")


func _sim() -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_true(content.load_all().is_empty())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 166, errors, null, false)
	assert_eq(errors.size(), 0)
	for recipe: RecipeDef in sim.menu:
		sim.regular_recipe_labels[recipe.id] = recipe.display_name
	return sim


func _cast_member(sim: RestaurantSim) -> RegularProfile:
	var cast: RegularCast = RegularCast.new()
	sim.regulars = cast
	sim.regular_rng_provider = GameState.rng.bind(&"regulars")
	var dish: StringName = sim.menu[0].id
	cast.observe_visit("returning", &"regular", 1, 5.0, 20.0, dish, Vector2i(3, 6), 0.9, true, sim.regular_rng_provider)
	var profile: RegularProfile = cast.observe_visit("returning", &"regular", 6, 5.0, 20.0,
		dish, Vector2i(3, 6), 0.9, true, sim.regular_rng_provider)
	assert_not_null(profile)
	return profile


func _random(value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = value
	return random
