extends TestCase
## Detached live-shop inputs and guest-arrival/departure integration; no nodes.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const VIBE: VibeTuning = preload("res://data/balance/vibe.tres")
const REVIEWS: ReviewTuning = preload("res://data/balance/reviews.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const CLEANLINESS: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func test_capture_copies_real_metadata_paint_menu_and_floor_layer_union() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(6, 4))
	assert_true(grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.WALL))
	assert_true(grid.set_terrain(Vector2i(0, 1), SimGrid.Terrain.ENTRY))
	assert_true(grid.set_terrain(Vector2i(5, 3), SimGrid.Terrain.OUTSIDE))
	var rug: ItemDef = _definition(&"test_rug", ItemDef.Category.DECOR, 3)
	rug.placement_layer = ItemDef.PlacementLayer.FLOOR_DECOR
	rug.solid = false
	rug.footprint = Vector2i(2, 2)
	var table: ItemDef = _definition(&"test_table", ItemDef.Category.TABLE, 0)
	table.seat_cells = [Vector2i(1, 0)] as Array[Vector2i]
	var plant: ItemDef = _definition(&"test_plant", ItemDef.Category.DECOR, 2)
	var placed_rug: PlacedItem = grid.place_def(rug, Vector2i(1, 1))
	var placed_table: PlacedItem = grid.place_def(table, Vector2i(1, 1))
	var placed_plant: PlacedItem = grid.place_def(plant, Vector2i(4, 2))
	assert_not_null(placed_rug)
	assert_not_null(placed_table)
	assert_not_null(placed_plant)
	if placed_rug == null or placed_table == null or placed_plant == null:
		return
	assert_true(placed_table.reserve(Vector2i(2, 1), 17))
	var paint: SwatchDef = SwatchDef.new()
	paint.id = &"test_vibe_paint"
	paint.display_name = "Warm test paint"
	paint.theme_tags = [&"rustic"] as Array[StringName]
	_content._swatches[paint.id] = paint
	placed_plant.swatch_id = paint.id
	var enabled: RecipeDef = RecipeDef.new()
	enabled.id = &"test_enabled"
	enabled.theme_tags = [&"cosy"] as Array[StringName]
	var menu: Array[RecipeDef] = [enabled]
	var inputs: VibeModel.Inputs = VibeInputs.capture(grid, _content, menu, paint.id, paint.id)
	assert_not_null(inputs)
	if inputs == null:
		return
	assert_eq(inputs.floor_cells.size(), 21)
	assert_false(inputs.floor_cells.has(Vector2i.ZERO))
	assert_false(inputs.floor_cells.has(Vector2i(0, 1)))
	assert_false(inputs.floor_cells.has(Vector2i(5, 3)))
	assert_eq(inputs.menu.size(), 1, "the adapter takes the enabled menu, not the whole database")
	assert_eq(inputs.menu[0].id, enabled.id)
	var rug_input: VibeModel.Item = _item(inputs, rug.id)
	var plant_input: VibeModel.Item = _item(inputs, plant.id)
	assert_not_null(rug_input)
	assert_not_null(plant_input)
	if rug_input == null or plant_input == null:
		return
	assert_true(rug_input.floor_decor)
	assert_eq(rug_input.cells, placed_rug.cells)
	assert_eq(plant_input.category, int(ItemDef.Category.DECOR))
	assert_almost_eq(plant_input.charm, 2.0)
	assert_eq(plant_input.paint_theme_tags, [&"rustic"] as Array[StringName])
	assert_eq(inputs.wall_paint_theme_tags, [&"rustic"] as Array[StringName])
	assert_eq(inputs.floor_paint_theme_tags, [&"rustic"] as Array[StringName])
	var result: VibeModel.Result = VibeModel.evaluate(inputs, VIBE)
	assert_true(result.valid)
	assert_eq(result.occupied_normal_cells, 2, "the rug adds no second coverage at the table")
	assert_almost_eq(result.crowding_density, 2.0 / 21.0)
	assert_eq(placed_table.reserved_by(Vector2i(2, 1)), 17, "capturing must not rebuild or release seats")
	# Later resource/layout edits cannot rewrite a detached capture.
	paint.theme_tags[0] = &"modern"
	enabled.theme_tags[0] = &"seafood"
	plant.theme_tags[0] = &"diner"
	assert_true(grid.relocate_def(placed_plant.id, Vector2i(4, 1), 0))
	assert_eq(plant_input.cells, [Vector2i(4, 2)] as Array[Vector2i])
	assert_eq(plant_input.theme_tags, [&"cosy"] as Array[StringName])
	assert_eq(inputs.menu[0].theme_tags, [&"cosy"] as Array[StringName])
	assert_eq(inputs.wall_paint_theme_tags, [&"rustic"] as Array[StringName])
	plant_input.paint_theme_tags.clear()
	assert_eq(paint.theme_tags, [&"modern"] as Array[StringName], "editing output cannot mutate content")
	assert_true(grid.remove(placed_rug.id))
	var without_rug: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(grid, _content, menu), VIBE)
	assert_true(without_rug.valid)
	assert_eq(without_rug.occupied_normal_cells, result.occupied_normal_cells)
	assert_almost_eq(without_rug.crowding_density, result.crowding_density)


func test_capture_invalid_sources_evaluate_neutrally_without_mutation() -> void:
	assert_null(VibeInputs.capture(null, _content, [] as Array[RecipeDef]))
	var grid: SimGrid = SimGrid.new(Vector2i(3, 3))
	assert_null(VibeInputs.capture(grid, null, [] as Array[RecipeDef]))
	var definition: ItemDef = _definition(&"invalid_paint", ItemDef.Category.DECOR, 4)
	var placed: PlacedItem = grid.place_def(definition, Vector2i.ONE)
	assert_not_null(placed)
	if placed == null:
		return
	placed.swatch_id = &"unknown_paint"
	var inputs: VibeModel.Inputs = VibeInputs.capture(grid, _content, [] as Array[RecipeDef])
	assert_null(inputs)
	var rejected: VibeModel.Result = VibeModel.evaluate(inputs, VIBE)
	assert_false(rejected.valid)
	assert_almost_eq(rejected.score, 0.0)
	assert_almost_eq(rejected.patience_multiplier, 1.0)
	assert_eq(placed.swatch_id, &"unknown_paint")
	placed.swatch_id = &""
	assert_null(VibeInputs.capture(grid, _content, [] as Array[RecipeDef], &"unknown_wall"))
	assert_null(VibeInputs.capture(grid, _content, [] as Array[RecipeDef], &"", &"unknown_floor"))
	var recipe: RecipeDef = RecipeDef.new()
	recipe.id = &"duplicate_menu_dish"
	assert_null(VibeInputs.capture(grid, _content, [recipe, recipe] as Array[RecipeDef]))
	definition.charm = -1
	assert_null(VibeInputs.capture(grid, _content, [] as Array[RecipeDef]))
	assert_eq(definition.charm, -1, "rejection does not repair or mutate content")
	var untyped_grid: SimGrid = SimGrid.new(Vector2i(2, 2))
	assert_not_null(untyped_grid.place(Vector2i.ONE, Vector2i.ZERO, 0, true))
	assert_null(VibeInputs.capture(untyped_grid, _content, [] as Array[RecipeDef]),
		"a generic grid item is not silently dropped from a production vibe")


func test_actual_starter_capture_keeps_arrival_budgets_and_effects_neutral() -> void:
	var sim: RestaurantSim = _restaurant()
	var result: VibeModel.Result = VibeModel.evaluate(VibeInputs.capture(sim.world.grid, _content, sim.menu), VIBE)
	assert_true(result.valid)
	assert_almost_eq(result.score, 0.0)
	sim.set_vibe(result)
	assert_true(sim.world.clock.start_service())
	var arrival_state: int = sim.rng.state
	var guest_rng: RandomNumberGenerator = _random(122001)
	var guest_state: int = guest_rng.state
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], guest_rng)
	assert_eq(guest.queue_patience, 300)
	assert_eq(guest.food_patience, 1200)
	assert_almost_eq(guest.vibe_review_bonus, 0.0)
	assert_eq(guest.vibe_theme_label, "")
	assert_eq(sim.rng.state, arrival_state)
	assert_eq(guest_rng.state, guest_state)


func test_arrival_snapshots_are_detached_and_later_edits_only_affect_new_guests() -> void:
	var sim: RestaurantSim = _restaurant()
	var source: VibeModel.Result = _full_vibe()
	sim.set_vibe(source)
	source.patience_multiplier = 1.0
	source.raw_review_bonus = 0.0
	source.theme_label = "Changed argument"
	var exposed: VibeModel.Result = sim.vibe_result
	exposed.patience_multiplier = 1.0
	exposed.raw_review_bonus = 0.0
	assert_true(sim.world.clock.start_service())
	var first: CustomerAgent = _guest(sim, 122002)
	assert_eq(first.queue_patience, 345)
	assert_eq(first.food_patience, 1380)
	assert_almost_eq(first.vibe_review_bonus, 0.4)
	assert_eq(first.vibe_theme_label, "Cosy")
	sim.set_vibe(null)
	var second: CustomerAgent = _guest(sim, 122003)
	assert_eq(second.queue_patience, 300)
	assert_eq(second.food_patience, 1200)
	assert_almost_eq(second.vibe_review_bonus, 0.0)
	assert_eq(first.queue_patience, 345)
	assert_eq(first.food_patience, 1380)
	assert_almost_eq(first.review_visit(0).vibe_review_bonus, 0.4)
	assert_eq(first.vibe_theme_label, "Cosy")
	for bad_value: float in [NAN, INF, -1.0, 1.16]:
		var invalid: VibeModel.Result = _full_vibe()
		invalid.patience_multiplier = bad_value
		sim.set_vibe(invalid)
		_assert_neutral_snapshot(sim.vibe_result)
		assert_eq(_guest(sim, 122004).food_patience, 1200)
	var invalid_bonus: VibeModel.Result = _full_vibe()
	invalid_bonus.raw_review_bonus = NAN
	sim.set_vibe(invalid_bonus)
	_assert_neutral_snapshot(sim.vibe_result)
	var rejected_guest: CustomerAgent = _guest(sim, 122014)
	assert_true(is_finite(rejected_guest.vibe_review_bonus))
	assert_eq(rejected_guest.vibe_review_bonus, 0.0)
	assert_eq(rejected_guest.queue_patience, 300)
	assert_eq(rejected_guest.food_patience, 1200)
	sim.set_vibe(VibeModel.Result.new())
	_assert_neutral_snapshot(sim.vibe_result)


func test_vibe_composes_after_cleanliness_without_extra_random_draws() -> void:
	var enhanced: RestaurantSim = _restaurant()
	var control: RestaurantSim = _restaurant()
	var tuning: CleanlinessTuning = CLEANLINESS.duplicate() as CleanlinessTuning
	tuning.arrival_chance = 0.0
	tuning.seat_departure_chance = 1.0
	var enhanced_rng: RandomNumberGenerator = _random(122005)
	var control_rng: RandomNumberGenerator = _random(122005)
	var enhanced_dirt: CleanlinessState = CleanlinessState.new(enhanced.world.grid, tuning, enhanced_rng)
	var control_dirt: CleanlinessState = CleanlinessState.new(control.world.grid, tuning, control_rng)
	assert_true(enhanced.configure_cleanliness(enhanced_dirt, tuning))
	assert_true(control.configure_cleanliness(control_dirt, tuning))
	assert_true(enhanced_dirt.try_spawn_at_departed_seat(Vector2i(3, 8)))
	assert_true(control_dirt.try_spawn_at_departed_seat(Vector2i(3, 8)))
	var cleanliness_scale: float = enhanced_dirt.patience_multiplier()
	enhanced.set_vibe(_full_vibe())
	assert_true(enhanced.world.clock.start_service())
	assert_true(control.world.clock.start_service())
	var first: CustomerAgent = _guest(enhanced, 122006)
	var second: CustomerAgent = _guest(control, 122006)
	assert_eq(second.queue_patience, roundi(300.0 * cleanliness_scale))
	assert_eq(second.food_patience, roundi(1200.0 * cleanliness_scale))
	assert_eq(first.queue_patience, roundi(float(second.queue_patience) * 1.15))
	assert_eq(first.food_patience, roundi(float(second.food_patience) * 1.15))
	assert_almost_eq(first.arrival_dirt_fraction, second.arrival_dirt_fraction)
	assert_eq(enhanced_rng.state, control_rng.state, "vibe consumes no cleanliness draw")
	assert_eq(enhanced.rng.state, control.rng.state, "vibe consumes no arrival draw")
	assert_eq(first.rng.state, second.rng.state, "vibe consumes no private guest draw")
	assert_eq(enhanced_dirt.spots(), control_dirt.spots())
	var retained_budget: int = first.food_patience
	assert_true(enhanced_dirt.clear_spot(Vector2i(3, 8)))
	enhanced.set_vibe(null)
	assert_eq(first.food_patience, retained_budget, "mopping and decorating cannot reset this visit")


func test_only_open_arrivals_receive_vibe_and_neutral_budgets_stay_exact() -> void:
	var sim: RestaurantSim = _restaurant()
	sim.set_vibe(_full_vibe())
	for phase: int in [SimClock.Phase.MORNING, SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]:
		sim.world.clock.phase = phase as SimClock.Phase
		var guest: CustomerAgent = _guest(sim, 122007)
		assert_eq(guest.queue_patience, 300)
		assert_eq(guest.food_patience, 1200)
		assert_almost_eq(guest.vibe_review_bonus, 0.0)
		assert_eq(guest.vibe_theme_label, "")
	for budget: int in [-10, 0, 1, 300, 9223372036854775807]:
		assert_eq(RestaurantSim._vibe_patience(budget, 1.0), budget)
	assert_eq(RestaurantSim._vibe_patience(-10, 1.15), -10)
	assert_eq(RestaurantSim._vibe_patience(0, 1.15), 0)
	assert_eq(RestaurantSim._vibe_patience(9223372036854775807, 1.15), 9223372036854775807)


func test_cheerful_order_bonus_still_applies_once_after_arrival_vibe() -> void:
	var sim: RestaurantSim = _restaurant()
	sim.set_vibe(_full_vibe())
	assert_true(sim.world.clock.start_service())
	var guest: CustomerAgent = _guest(sim, 122008)
	guest.state = CustomerAgent.State.ORDERING
	guest._food_wait = 137
	guest._queue_wait = 11
	var member: StaffMember = StaffRoster.CATALOGUE.defaults(preload("res://data/balance/tier1_economy.tres"))[1]
	member.trait_id = &"cheerful"
	var server: StaffAgent = StaffAgent.new(&"server", member.skill)
	server.configure_member(member, StaffRoster.CATALOGUE.find_trait(&"cheerful"))
	assert_true(guest._take_order(server))
	assert_eq(guest.food_patience, 1518)
	assert_eq(guest.queue_patience, 345)
	assert_eq(guest._food_wait, 137)
	assert_eq(guest._queue_wait, 11)
	var order: Order = guest.order
	var guest_state: int = guest.rng.state
	assert_true(guest._take_order(server))
	assert_true(guest.order == order)
	assert_eq(guest.food_patience, 1518)
	assert_eq(guest.rng.state, guest_state, "replaying order acceptance stacks neither bonus nor draw")


func test_departure_uses_arrival_raw_bonus_once_after_room_changes() -> void:
	var sim: RestaurantSim = _restaurant()
	var certain: ReviewTuning = REVIEWS.duplicate() as ReviewTuning
	certain.review_chance = 1.0
	var review_rng: RandomNumberGenerator = _random(122009)
	sim.configure_reviews(ReputationBook.new(), certain, QUOTES, review_rng)
	sim.set_vibe(_full_vibe())
	assert_true(sim.world.clock.start_service())
	var guest: CustomerAgent = _guest(sim, 122010)
	guest._queue_wait = 207 # 60% of the expanded queue budget; base score is 4.
	guest.order = Order.new()
	guest.order.recipe_id = sim.menu[0].id
	guest.order.price = sim.menu[0].standard_price
	sim.pay(guest, guest.order)
	sim.set_vibe(null)
	var visit: ReviewVisit = guest.review_visit(sim.menu[0].standard_price)
	assert_almost_eq(visit.vibe_review_bonus, 0.4)
	assert_eq(ReputationBook.score_visit(visit, certain), 5)
	visit.vibe_review_bonus = 0.0
	assert_eq(ReputationBook.score_visit(visit, certain), 4)
	sim.record_departure(guest)
	assert_eq(sim.reviews_today.size(), 1)
	assert_eq(sim.reviews_today[0]["stars"], 5)
	assert_false(sim.reviews_today[0].has("cause"))
	var state: int = review_rng.state
	sim.record_departure(guest)
	assert_eq(sim.reviews_today.size(), 1)
	assert_eq(review_rng.state, state)


func test_raw_review_bonus_is_bounded_before_integer_rounding_and_preserves_draws() -> void:
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.queue_wait_fraction = 0.6
	assert_eq(ReputationBook.score_visit(visit, REVIEWS), 4)
	assert_eq(ReputationBook.cause_of(visit, REVIEWS), &"lovely_place")
	var control: ReputationBook = ReputationBook.new()
	var enhanced: ReputationBook = ReputationBook.new()
	var control_rng: RandomNumberGenerator = _random(122011)
	var enhanced_rng: RandomNumberGenerator = _random(122011)
	var certain: ReviewTuning = REVIEWS.duplicate() as ReviewTuning
	certain.review_chance = 1.0
	var ordinary: Dictionary = control.record_visit(visit, certain, QUOTES, control_rng)
	visit.vibe_review_bonus = 0.4
	var decorated: Dictionary = enhanced.record_visit(visit, certain, QUOTES, enhanced_rng)
	assert_eq(ordinary["stars"], 4)
	assert_eq(decorated["stars"], 5, "0.4 is a raw term, then the unchanged integer rounding applies")
	assert_eq(ordinary["cause"], decorated["cause"])
	assert_eq(ordinary["quote"], decorated["quote"])
	assert_eq(control_rng.state, enhanced_rng.state, "no extra review/quote draw")
	for bonus: float in [NAN, INF, -0.1]:
		visit.vibe_review_bonus = bonus
		assert_eq(ReputationBook.score_visit(visit, REVIEWS), 4)
	visit.vibe_review_bonus = 999.0
	assert_eq(ReputationBook.score_visit(visit, REVIEWS), 5, "oversized finite values cap at the raw limit")
	visit.queue_wait_fraction = 1.0
	assert_eq(ReputationBook.score_visit(visit, REVIEWS), 4, "the cap cannot erase a whole penalty")
	visit.served = false
	assert_eq(ReputationBook.score_visit(visit, REVIEWS), 1)
	visit.closing = true
	var state: int = enhanced_rng.state
	assert_eq(enhanced.record_visit(visit, certain, QUOTES, enhanced_rng), {})
	assert_eq(enhanced_rng.state, state)
	assert_eq(ReputationBook.score_visit(visit, REVIEWS), 0)


func test_vibe_crossing_four_stars_uses_positive_cause_without_extra_draws() -> void:
	var sim: RestaurantSim = _restaurant()
	var tuning: ReviewTuning = REVIEWS.duplicate() as ReviewTuning
	tuning.review_chance = 1.0
	tuning.food_wait_weight = 1.8
	var review_rng: RandomNumberGenerator = _random(122012)
	sim.configure_reviews(ReputationBook.new(), tuning, QUOTES, review_rng)
	sim.set_vibe(_full_vibe())
	assert_true(sim.world.clock.start_service())
	var guest: CustomerAgent = _guest(sim, 122013)
	guest._food_wait = guest.food_patience
	guest.order = Order.new()
	guest.order.recipe_id = sim.menu[0].id
	guest.order.price = sim.menu[0].standard_price
	sim.pay(guest, guest.order)
	var visit: ReviewVisit = guest.review_visit(sim.menu[0].standard_price)
	visit.vibe_review_bonus = 0.0
	assert_eq(ReputationBook.score_visit(visit, tuning), 3, "the unbonused raw score is 3.2")
	assert_eq(ReputationBook.cause_of(visit, tuning), &"slow_food")
	visit.vibe_review_bonus = 0.4
	assert_eq(ReputationBook.score_visit(visit, tuning), 4, "the boosted raw score is 3.6")
	assert_eq(ReputationBook.cause_of(visit, tuning), &"lovely_place",
		"the existing final-rating positive-quote threshold includes vibe")
	# Preserve the old one review-chance draw plus one quote choice, including
	# when the bonus changes the cause group. Other named streams stay untouched.
	var expected_rng: RandomNumberGenerator = _random(122012)
	assert_true(expected_rng.randf() < tuning.review_chance)
	var used: Dictionary[String, bool] = {}
	var expected_quote: String = QUOTES.pick(&"lovely_place", expected_rng, used)
	var arrival_state: int = sim.rng.state
	var guest_state: int = guest.rng.state
	sim.record_departure(guest)
	assert_eq(sim.reviews_today.size(), 1)
	assert_eq(sim.reviews_today[0]["stars"], 4)
	assert_eq(sim.reviews_today[0]["quote"], expected_quote)
	assert_eq(review_rng.state, expected_rng.state)
	assert_eq(sim.rng.state, arrival_state)
	assert_eq(guest.rng.state, guest_state)
	# An absent bonus retains the original first-cause tie, not a new vibe rule.
	var tied: ReviewVisit = ReviewVisit.new()
	tied.served = true
	tied.queue_wait_fraction = 1.0
	tied.food_wait_fraction = 1.0
	var tie_tuning: ReviewTuning = REVIEWS.duplicate() as ReviewTuning
	tie_tuning.food_wait_weight = tie_tuning.queue_wait_weight
	assert_eq(tied.vibe_review_bonus, 0.0)
	assert_eq(ReputationBook.score_visit(tied, tie_tuning), 3)
	assert_eq(ReputationBook.cause_of(tied, tie_tuning), &"slow_seating")


func _assert_neutral_snapshot(result: VibeModel.Result) -> void:
	assert_false(result.valid)
	for value: float in [result.score, result.decor_points, result.variety_points,
			result.theme_points, result.lamp_points, result.crowding_penalty,
			result.theme_share, result.raw_review_bonus, result.arrival_theme_strength,
			result.crowding_density]:
		assert_true(is_finite(value), "neutral snapshot values must be finite")
		assert_eq(value, 0.0)
	assert_true(is_finite(result.patience_multiplier))
	assert_eq(result.patience_multiplier, 1.0)
	assert_eq(result.interior_cells, 0)
	assert_eq(result.occupied_normal_cells, 0)
	assert_eq(result.active_theme, &"")
	assert_eq(result.theme_label, "")


func _restaurant() -> RestaurantSim:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 122000, errors, null, false)
	assert_eq(errors, [] as Array[String])
	return sim


func _guest(sim: RestaurantSim, seed: int) -> CustomerAgent:
	return sim.add_customer(sim.world.grid.entries()[0], _random(seed))


func _random(seed: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	return random


func _definition(id: StringName, category: ItemDef.Category, charm: int) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = id
	definition.category = category
	definition.charm = charm
	definition.theme_tags = [&"cosy"] as Array[StringName]
	return definition


func _item(inputs: VibeModel.Inputs, id: StringName) -> VibeModel.Item:
	for item: VibeModel.Item in inputs.items:
		if item.definition_id == id:
			return item
	return null


func _full_vibe() -> VibeModel.Result:
	var result: VibeModel.Result = VibeModel.Result.new()
	result.valid = true
	result.score = 100.0
	result.active_theme = &"cosy"
	result.theme_label = "Cosy"
	result.theme_share = 1.0
	result.patience_multiplier = 1.15
	result.raw_review_bonus = 0.4
	result.arrival_theme_strength = 1.0
	return result
