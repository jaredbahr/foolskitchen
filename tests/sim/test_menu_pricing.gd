extends TestCase
## Real order callback/payment and seeded price refusal, without a scene tree.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const SAMPLE_COUNT: int = 1000

var _content: ContentDB
var _sim: RestaurantSim
var _paid: Array[int] = []


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_sim.customer_paid.connect(_on_paid)


func after_each() -> void:
	_sim.customer_paid.disconnect(_on_paid)
	_sim = null
	_content = null
	_paid.clear()


func test_missing_override_uses_immutable_standard_and_actual_order_payment_uses_override() -> void:
	var recipe: RecipeDef = _content.recipe(&"burger")
	var standard: int = recipe.standard_price
	assert_eq(_sim.price_of(recipe), standard)
	_sim.menu = [recipe]
	_sim.prices[recipe.id] = 9
	var guest: CustomerAgent = _ordering_guest(52)
	assert_true(guest.call("_take_order", null))
	assert_not_null(guest.order)
	assert_eq(guest.order.price, 9)
	assert_eq(guest.order.recipe_id, recipe.id)
	assert_true(_sim.orders.get_order(guest.order.id) == guest.order)
	_sim.prices[recipe.id] = 7  # An existing order keeps its captured price.
	_sim.pay(guest, guest.order)
	_sim.pay(guest, guest.order)
	assert_eq(_paid, [9] as Array[int], "the captured order price reaches payment exactly once")
	assert_eq(recipe.standard_price, standard)
	_sim.world.remove_agent(guest)


func test_standard_and_cheaper_prices_do_not_walk_out_or_consume_extra_rng() -> void:
	var recipe: RecipeDef = _content.recipe(&"burger")
	_sim.menu = [recipe]
	for price: int in [recipe.standard_price, recipe.standard_price - 1]:
		_sim.prices[recipe.id] = price
		assert_eq(_sim.price_walkout_chance(recipe), 0.0)
		for index: int in range(128):
			var guest: CustomerAgent = _ordering_guest(5200 + index)
			var expected: RandomNumberGenerator = RandomNumberGenerator.new()
			expected.state = guest.rng.state
			expected.randi_range(0, 0)  # The pre-existing dish selection draw only.
			assert_true(guest.call("_take_order", null))
			assert_not_null(guest.order)
			assert_ne(guest.leave_reason, &"too_expensive")
			assert_eq(guest.rng.state, expected.state)
			_sim.world.remove_agent(guest)


func test_seeded_double_price_walkout_rate_matches_formula_and_repeats() -> void:
	var recipe: RecipeDef = _content.recipe(&"burger")
	_sim.menu = [recipe]
	_sim.prices[recipe.id] = recipe.standard_price * 2
	var expected: float = clampf((2.0 - 1.0) * _sim.pricing_tuning.price_sensitivity, 0.0, _sim.pricing_tuning.max_price_walkout)
	assert_almost_eq(expected, 0.9)
	var first: int = _refusals(520052)
	var repeated: int = _refusals(520052)
	assert_eq(first, repeated, "the same guest seeds make the same decisions")
	assert_almost_eq(float(first) / SAMPLE_COUNT, expected, 0.04)
	assert_true(CustomerAgent.PLAYER_REASONS.has(&"too_expensive"))


func test_disabled_recipes_never_reach_actual_orders() -> void:
	var settings: MenuSettings = MenuSettings.new(_sim.menu)
	for recipe: RecipeDef in settings.recipes():
		if recipe.id != &"burger":
			assert_true(settings.set_enabled(recipe.id, false))
	_sim.menu = settings.enabled_recipes()
	assert_eq(_sim.menu.size(), 1)
	for index: int in range(128):
		var guest: CustomerAgent = _ordering_guest(12300 + index)
		assert_true(guest.call("_take_order", null))
		assert_not_null(guest.order)
		assert_eq(guest.order.recipe_id, &"burger")
		_sim.world.remove_agent(guest)


func test_price_chance_clamps_bad_balance_values_and_handles_free_standard() -> void:
	var recipe: RecipeDef = _content.recipe(&"burger")
	_sim.prices[recipe.id] = recipe.standard_price * 2
	_sim.pricing_tuning.price_sensitivity = -1.0
	assert_eq(_sim.price_walkout_chance(recipe), 0.0)
	_sim.pricing_tuning.price_sensitivity = 100.0
	_sim.pricing_tuning.max_price_walkout = 4.0
	assert_eq(_sim.price_walkout_chance(recipe), 1.0)
	_sim.pricing_tuning.max_price_walkout = -2.0
	assert_eq(_sim.price_walkout_chance(recipe), 0.0)
	_sim.pricing_tuning.price_sensitivity = NAN
	assert_eq(_sim.price_walkout_chance(recipe), 0.0)
	var free: RecipeDef = RecipeDef.new()
	free.id = &"free_test"
	free.standard_price = 0
	assert_eq(_sim.price_walkout_chance(free), 0.0)
	assert_eq(_sim.price_of(free), 0)


func _ordering_guest(seed: int) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random)
	guest.state = CustomerAgent.State.ORDERING
	return guest


func _refusals(seed: int) -> int:
	var seeds: RandomNumberGenerator = RandomNumberGenerator.new()
	seeds.seed = seed
	var count: int = 0
	for _index: int in range(SAMPLE_COUNT):
		var guest: CustomerAgent = _ordering_guest(seeds.randi())
		assert_true(guest.call("_take_order", null))
		if guest.leave_reason == &"too_expensive":
			count += 1
			assert_null(guest.order, "refusal creates no kitchen ticket")
		else:
			assert_not_null(guest.order)
		_sim.world.remove_agent(guest)
	return count


func _on_paid(_guest: CustomerAgent, _order: Order, amount: int) -> void:
	_paid.append(amount)
