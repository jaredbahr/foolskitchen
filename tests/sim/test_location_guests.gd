extends TestCase
## Location guest types (#471): tourists and the office crowd, and a lot's
## guest mix deciding who walks in there while the home shop stays exact.

const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const SEASIDE: LotDef = preload("res://data/lots/seaside_cliff.tres")
const ROOFTOP: LotDef = preload("res://data/lots/skyscraper_rooftop.tres")
const LUNCH: int = 12 * 60
const AFTERNOON: int = 16 * 60 + 30


func test_tourists_and_office_crowd_load_validate_and_differ() -> void:
	assert_true(TYPES.is_valid())
	var tourist: CustomerType = TYPES.find_type(&"tourist")
	var office: CustomerType = TYPES.find_type(&"office")
	assert_not_null(tourist)
	assert_not_null(office)
	if tourist == null or office == null:
		return
	assert_eq(tourist.report_name, "Tourists")
	assert_eq(office.report_name, "Office crowd")
	assert_true(tourist.budget_multiplier > 1.0, "tourists are less fussy about price")
	assert_eq(tourist.patience_multiplier, 1.0, "average patience")
	assert_true(tourist.local_dish_bonus > 0.0)
	assert_true(office.budget_multiplier > 1.0, "the office crowd pays well")
	assert_true(office.patience_multiplier < 1.0, "and has little patience")
	assert_eq(office.local_dish_bonus, 0.0)


func test_home_shop_never_draws_location_types_and_keeps_its_stream() -> void:
	var old: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	for id: StringName in [&"regular", &"student", &"foodie", &"family"]:
		old.types.append(TYPES.find_type(id))
	for level: int in [1, 4, 10]:
		for stars: float in [1.0, 3.0, 5.0]:
			var with_new: RandomNumberGenerator = _random(4710 + level)
			var without: RandomNumberGenerator = _random(4710 + level)
			for index: int in 150:
				var minute: int = LUNCH if index % 2 == 0 else AFTERNOON
				var one: CustomerType = CustomerTypePicker.choose(TYPES, level, stars, with_new,
					&"", 0.0, null, {}, minute)
				var two: CustomerType = CustomerTypePicker.choose(old, level, stars, without)
				assert_not_null(one)
				if one == null or two == null:
					continue
				assert_eq(one.id, two.id, "home draw %d at level %d, %.0f stars" % [index, level, stars])
				assert_false([&"tourist", &"office"].has(one.id))
			assert_eq(with_new.state, without.state, "the home stream is unchanged")
	assert_eq(CustomerTypePicker.average_budget(TYPES, 10, 4.0),
		CustomerTypePicker.average_budget(old, 10, 4.0))


func test_seaside_mix_is_mostly_tourists_and_names_no_absent_type() -> void:
	var counts: Dictionary[StringName, int] = _draws(SEASIDE.guest_mix, AFTERNOON, 1000)
	assert_true(counts.get(&"tourist", 0) > 500, "mostly tourists: %s" % counts)
	assert_eq(counts.get(&"family", 0), 0, "a type missing from the mix never arrives")
	assert_eq(counts.get(&"office", 0), 0)
	assert_eq(PropertyText.guest_line(SEASIDE, TYPES), "Guests: mostly tourists")


func test_office_crowd_mostly_arrives_at_lunch() -> void:
	var office: CustomerType = TYPES.find_type(&"office")
	assert_eq(office.window_multiplier(LUNCH), 1.0)
	assert_eq(office.window_multiplier(11 * 60), office.off_window_weight)
	assert_eq(office.window_multiplier(-1), 1.0, "no clock, no window")
	assert_eq(TYPES.find_type(&"regular").window_multiplier(AFTERNOON), 1.0)
	var lunch: Dictionary[StringName, int] = _draws(ROOFTOP.guest_mix, LUNCH, 1000)
	var later: Dictionary[StringName, int] = _draws(ROOFTOP.guest_mix, AFTERNOON, 1000)
	assert_true(lunch.get(&"office", 0) > 350, "office crowd at lunch: %s" % lunch)
	assert_true(later.get(&"office", 0) < lunch.get(&"office", 0) / 2,
		"far fewer later: %s vs %s" % [later, lunch])
	assert_eq(PropertyText.guest_line(ROOFTOP, TYPES), "Guests: office crowd and foodies")


func test_bad_windows_and_bonuses_fail_validation() -> void:
	var kind: CustomerType = TYPES.find_type(&"office").duplicate() as CustomerType
	kind.arrival_window_end = kind.arrival_window_start
	assert_false(kind.is_valid())
	kind = TYPES.find_type(&"office").duplicate() as CustomerType
	kind.off_window_weight = 1.5
	assert_false(kind.is_valid())
	kind = TYPES.find_type(&"tourist").duplicate() as CustomerType
	kind.local_dish_bonus = -0.1
	assert_false(kind.is_valid())


func test_office_guest_has_short_patience_in_the_sim() -> void:
	var sim: RestaurantSim = _sim()
	var office: CustomerType = TYPES.find_type(&"office")
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(1), office)
	var regular: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(2),
		TYPES.find_type(&"regular"))
	assert_eq(guest.queue_patience, roundi(300.0 * office.patience_multiplier))
	assert_true(guest.queue_patience < regular.queue_patience)
	assert_true(guest.food_patience < regular.food_patience)


func test_tourists_never_join_the_regulars_cohort() -> void:
	var sim: RestaurantSim = _sim()
	sim.regulars = RegularCast.new()
	sim.regular_rng_provider = GameState.rng.bind(&"regulars")
	GameState.new_run(471)
	assert_true(sim.world.clock.start_service())
	for index: int in 4:
		var tourist: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(10 + index),
			TYPES.find_type(&"tourist"))
		assert_eq(tourist.repeat_guest_key, "", "a tourist is a one-time visitor")
		assert_null(tourist.regular_profile)
		tourist.paid = true
		tourist.order = Order.new()
		tourist.order.recipe_id = sim.menu[0].id
		tourist.order.quality = 0.9
		sim.record_departure(tourist)
	assert_eq(sim.regulars.profiles.size(), 0)


func test_tourists_enjoy_local_dishes_only() -> void:
	var content: ContentDB = _content()
	var fish: RecipeDef = content.recipe(&"fish_and_chips")
	var soft_serve: RecipeDef = content.recipe(&"soft_serve")
	var seaside_tags: Array[StringName] = [&"seaside"]
	var none: Array[StringName] = []
	assert_true(CustomerType.is_local_dish(fish, none), "seafood is local by the sea and in town")
	assert_true(CustomerType.is_local_dish(soft_serve, seaside_tags))
	assert_false(CustomerType.is_local_dish(soft_serve, none))
	var sim: RestaurantSim = _sim()
	sim.configure_lot_guests(SEASIDE)
	assert_eq(sim.lot_tags, SEASIDE.tags)
	sim.menu = [fish, content.recipe(&"burger")] as Array[RecipeDef]
	var tourist: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(5),
		TYPES.find_type(&"tourist"))
	var regular: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _random(6),
		TYPES.find_type(&"regular"))
	var local_visit: ReviewVisit = ReviewVisit.new()
	local_visit.consumed_recipe_ids = [&"fish_and_chips"]
	var plain_visit: ReviewVisit = ReviewVisit.new()
	plain_visit.consumed_recipe_ids = [&"burger"]
	assert_eq(sim.local_dish_bonus_for(tourist, local_visit), tourist.local_dish_bonus)
	assert_eq(sim.local_dish_bonus_for(tourist, plain_visit), 0.0)
	assert_eq(sim.local_dish_bonus_for(regular, local_visit), 0.0, "only local-food lovers")
	# The bonus lifts the rounded score: a 4.2 visit rounds to 4, and to 5 with +0.3.
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.was_seated = true
	visit.food_wait_fraction = 0.8 / TUNING.food_wait_weight
	assert_eq(ReputationBook.score_visit(visit, TUNING), 4)
	visit.local_dish_bonus = 0.3
	assert_eq(ReputationBook.score_visit(visit, TUNING), 5)
	sim.configure_lot_guests(null)
	assert_true(sim.lot_guest_mix.is_empty(), "the home shop has no mix")
	assert_true(sim.lot_tags.is_empty())


func _draws(mix: Dictionary[StringName, float], minute: int, count: int) -> Dictionary[StringName, int]:
	var random: RandomNumberGenerator = _random(9471 + minute)
	var counts: Dictionary[StringName, int] = {}
	for _index: int in count:
		var kind: CustomerType = CustomerTypePicker.choose(TYPES, 10, 4.5, random,
			&"", 0.0, null, mix, minute)
		if kind != null:
			counts[kind.id] = counts.get(kind.id, 0) + 1
	return counts


func _content() -> ContentDB:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	return content


func _sim() -> RestaurantSim:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content(), 471, errors, null, false)
	assert_eq(errors, [] as Array[String])
	return sim


func _random(value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = value
	return random
