extends TestCase
## Morning offer pricing, private-choice draws and checkpoint compatibility.

var _burger: RecipeDef
var _soup: RecipeDef
var _choices: Array[RecipeDef]


func before_each() -> void:
	_burger = RecipeDef.new()
	_burger.id = &"burger"
	_burger.standard_price = 12
	_soup = RecipeDef.new()
	_soup.id = &"tomato_soup"
	_soup.standard_price = 9
	_choices = [_burger, _soup]


func test_discount_uses_the_player_price_and_rounds_half_up_without_int64_overflow() -> void:
	var special: DailySpecial = DailySpecial.new()
	assert_true(special.select(_burger.id, _choices))
	assert_eq(special.price_for(_burger, 12), 11)
	assert_eq(special.price_for(_burger, 25), 23)
	assert_eq(special.price_for(_burger, 5), 5)
	assert_eq(special.price_for(_burger, 0), 0)
	assert_eq(special.price_for(_burger, MenuSettings.MAX_PRICE), 8301034833169298226)
	assert_eq(special.price_for(_soup, 9), 9)
	assert_eq(_burger.standard_price, 12, "shared recipe content is never repriced")


func test_zero_and_full_discounts_preserve_the_exact_int64_endpoints() -> void:
	var config: MenuTuning = MenuTuning.new()
	config.special_discount = 0.0
	var free_choice: DailySpecial = DailySpecial.new(config)
	assert_true(free_choice.select(_burger.id, _choices))
	assert_eq(free_choice.price_for(_burger, MenuSettings.MAX_PRICE), MenuSettings.MAX_PRICE)
	config.special_discount = 1.0
	var full_discount: DailySpecial = DailySpecial.new(config)
	assert_true(full_discount.select(_burger.id, _choices))
	assert_eq(full_discount.price_for(_burger, MenuSettings.MAX_PRICE), 0)
	assert_eq(free_choice.price_for(_burger, MenuSettings.MAX_PRICE), MenuSettings.MAX_PRICE,
		"each model owns its tuning copy")


func test_special_tuning_rejects_nonfinite_and_out_of_range_rates() -> void:
	for value: float in [-0.01, 1.01, INF, NAN]:
		var config: MenuTuning = MenuTuning.new()
		config.special_discount = value
		assert_false(config.is_valid())
		config.special_discount = 0.1
		config.special_pull = value
		assert_false(config.is_valid())


func test_no_special_or_unavailable_special_preserves_every_private_draw() -> void:
	var special: DailySpecial = DailySpecial.new()
	var actual: RandomNumberGenerator = RandomNumberGenerator.new()
	var baseline: RandomNumberGenerator = RandomNumberGenerator.new()
	actual.seed = 42
	baseline.seed = 42
	for _visit: int in 200:
		var ordinary: RecipeDef = _choices[actual.randi_range(0, _choices.size() - 1)]
		var expected: RecipeDef = _choices[baseline.randi_range(0, _choices.size() - 1)]
		assert_eq(special.pick(ordinary, _choices, actual), expected)
		assert_eq(actual.state, baseline.state)
	assert_true(special.select(_burger.id, _choices))
	assert_eq(special.pick(_soup, [_soup] as Array[RecipeDef], actual), _soup)
	assert_eq(actual.state, baseline.state, "sold-out special causes no additional draw")


func test_enabled_special_increases_its_share_with_one_extra_draw_per_choice() -> void:
	var special: DailySpecial = DailySpecial.new()
	assert_true(special.select(_burger.id, _choices))
	var actual: RandomNumberGenerator = RandomNumberGenerator.new()
	var baseline: RandomNumberGenerator = RandomNumberGenerator.new()
	actual.seed = 7
	baseline.seed = 7
	var ordinary_burgers: int = 0
	var promoted_burgers: int = 0
	for _visit: int in 2000:
		var ordinary: RecipeDef = _choices[actual.randi_range(0, _choices.size() - 1)]
		var expected: RecipeDef = _choices[baseline.randi_range(0, _choices.size() - 1)]
		ordinary_burgers += int(ordinary == _burger)
		var picked: RecipeDef = special.pick(ordinary, _choices, actual)
		var pulled: bool = baseline.randf() < 0.25
		assert_eq(picked, _burger if pulled else expected)
		assert_eq(actual.state, baseline.state)
		promoted_burgers += int(picked == _burger)
	assert_true(promoted_burgers > ordinary_burgers + 150)
	assert_true(promoted_burgers > 1150 and promoted_burgers < 1350)


func test_same_morning_is_idempotent_and_next_morning_clears_the_single_choice() -> void:
	var special: DailySpecial = DailySpecial.new()
	assert_true(special.select(_burger.id, _choices))
	assert_true(special.begin_morning(1))
	assert_eq(special.recipe_id(), _burger.id)
	assert_false(special.select(&"missing", _choices))
	assert_eq(special.recipe_id(), _burger.id)
	assert_true(special.select(_soup.id, _choices))
	assert_eq(special.recipe_id(), _soup.id)
	assert_true(special.begin_morning(2))
	assert_eq(special.recipe_id(), &"")
	assert_true(special.select(_burger.id, _choices))
	special.reconcile([_soup] as Array[RecipeDef])
	assert_eq(special.recipe_id(), &"")


func test_saved_choice_round_trips_and_invalid_restore_keeps_the_live_choice() -> void:
	var selected: DailySpecial = DailySpecial.new()
	assert_true(selected.begin_morning(7))
	assert_true(selected.select(_burger.id, _choices))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(selected.to_dict()))
	var restored: DailySpecial = DailySpecial.new()
	assert_true(restored.from_dict(saved, _choices, 7))
	assert_eq(restored.to_dict(), selected.to_dict())
	for invalid: Dictionary in [
		{"version": 1, "day": 7, "recipe": "missing"},
		{"version": 1, "day": 8, "recipe": "burger"},
		{"version": 1, "day": 7.5, "recipe": "burger"},
		{"version": true, "day": 7, "recipe": "burger"},
		{"version": 1, "day": 7, "recipe": "burger", "extra": true},
	]:
		assert_false(restored.from_dict(invalid, _choices, 7))
		assert_eq(restored.to_dict(), selected.to_dict())
	assert_true(restored.from_dict(saved, _choices, 8))
	assert_eq(restored.recipe_id(), &"", "an earlier service's offer never carries into a new morning")
