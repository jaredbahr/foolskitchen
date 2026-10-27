extends TestCase
## Pure menu choices and save validation; guest/order/sale integration is separate.

var _burger: RecipeDef
var _cheese: RecipeDef
var _soup: RecipeDef
var _menu: MenuSettings


func before_each() -> void:
	_burger = _recipe(&"burger", 12)
	_cheese = _recipe(&"grilled_cheese", 8)
	_soup = _recipe(&"tomato_soup", 9)
	_menu = MenuSettings.new([_soup, _burger, _cheese])


func test_defaults_use_every_injected_recipe_and_standard_price_in_lexical_order() -> void:
	assert_true(_menu.is_valid())
	assert_eq(_ids(_menu.recipes()), [&"burger", &"grilled_cheese", &"tomato_soup"] as Array[StringName])
	assert_eq(_ids(_menu.enabled_recipes()), _ids(_menu.recipes()))
	assert_eq(_menu.enabled_count(), 3)
	for definition: RecipeDef in [_burger, _cheese, _soup]:
		assert_true(_menu.is_enabled(definition.id))
		assert_eq(_menu.recipe(definition.id), definition)
		assert_eq(_menu.price_of(definition), definition.standard_price)
	var copy: Array[RecipeDef] = _menu.recipes()
	copy.clear()
	copy = _menu.enabled_recipes()
	copy.reverse()
	assert_eq(_menu.recipes().size(), 3)
	assert_eq(_ids(_menu.enabled_recipes()), [&"burger", &"grilled_cheese", &"tomato_soup"] as Array[StringName])
	assert_null(_menu.recipe(&"missing"))
	assert_false(_menu.is_enabled(&"missing"))
	assert_eq(_menu.price_of(null), 0)
	assert_eq(_menu.price_of(_recipe(&"missing", 7)), 7)


func test_at_least_one_dish_stays_enabled_and_unknown_ids_are_refused() -> void:
	assert_true(_menu.set_enabled(&"burger", false))
	assert_true(_menu.set_enabled(&"grilled_cheese", false))
	assert_eq(_ids(_menu.enabled_recipes()), [&"tomato_soup"] as Array[StringName])
	var before: Dictionary = _menu.to_dict()
	assert_false(_menu.set_enabled(&"tomato_soup", false))
	assert_true(_menu.set_enabled(&"burger", false), "already disabled is accepted")
	assert_false(_menu.set_enabled(&"missing", true))
	assert_false(_menu.set_price(&"missing", 12))
	assert_eq(_menu.to_dict(), before)
	assert_true(_menu.set_enabled(&"burger", true))
	assert_true(_menu.set_enabled(&"tomato_soup", false))
	assert_eq(_menu.enabled_count(), 1)


func test_level_locked_recipe_is_visible_but_cannot_be_enabled_or_priced() -> void:
	var seasonal: RecipeDef = _recipe(&"seasonal", 14)
	seasonal.unlock_level = 2
	var menu: MenuSettings = MenuSettings.new([_burger, seasonal])
	assert_true(menu.is_valid())
	assert_eq(menu.owner_level(), 1)
	assert_eq(_ids(menu.recipes()), [&"burger", &"seasonal"] as Array[StringName])
	assert_eq(_ids(menu.enabled_recipes()), [&"burger"] as Array[StringName])
	var before: Dictionary = menu.to_dict()
	assert_false(menu.set_enabled(&"seasonal", true))
	assert_false(menu.set_price(&"seasonal", 20))
	assert_eq(menu.to_dict(), before)
	assert_eq(menu.price_of(seasonal), seasonal.standard_price)
	assert_eq(menu.to_dict()["prices"]["seasonal"], "14")


func test_level_advance_allows_selection_without_enabling_it_automatically() -> void:
	var seasonal: RecipeDef = _recipe(&"seasonal", 14)
	seasonal.unlock_level = 2
	var menu: MenuSettings = MenuSettings.new([_burger, seasonal])
	assert_true(menu.set_owner_level(2))
	assert_eq(menu.owner_level(), 2)
	assert_false(menu.is_enabled(&"seasonal"))
	assert_true(menu.set_price(&"seasonal", 18))
	assert_true(menu.set_enabled(&"seasonal", true))
	assert_eq(_ids(menu.enabled_recipes()), [&"burger", &"seasonal"] as Array[StringName])
	assert_false(menu.set_owner_level(1), "an enabled dish cannot outlevel its owner")
	assert_eq(menu.owner_level(), 2)
	assert_true(menu.set_enabled(&"seasonal", false))
	assert_true(menu.set_owner_level(1))
	assert_false(menu.set_enabled(&"seasonal", true))
	assert_false(menu.set_price(&"seasonal", 15))
	assert_eq(menu.price_of(seasonal), 18)


func test_old_menu_save_adds_only_disabled_new_locked_recipe_transactionally() -> void:
	var seasonal: RecipeDef = _recipe(&"seasonal", 14)
	seasonal.unlock_level = 2
	var menu: MenuSettings = MenuSettings.new([_burger, seasonal])
	var old_save: Dictionary = {"enabled": ["burger"], "prices": {"burger": "12"}}
	assert_true(menu.from_dict(old_save))
	var restored: Dictionary = menu.to_dict()
	assert_eq(restored["enabled"], ["burger"] as Array[String])
	assert_eq(restored["prices"], {"burger": "12", "seasonal": "14"})
	var locked_enabled: Dictionary = {"enabled": ["burger", "seasonal"],
		"prices": {"burger": "12", "seasonal": "14"}}
	assert_false(menu.from_dict(locked_enabled))
	assert_eq(menu.to_dict(), restored)
	var missing_old_price: Dictionary = {"enabled": ["burger"],
		"prices": {"seasonal": "14"}}
	assert_false(menu.from_dict(missing_old_price))
	assert_eq(menu.to_dict(), restored)
	assert_true(menu.set_owner_level(2))
	assert_false(menu.from_dict({"enabled": ["burger", "seasonal"],
		"prices": {"burger": "12"}}), "an enabled dish always needs its saved price")
	assert_eq(menu.to_dict(), restored)


func test_whole_dollar_price_requests_clamp_to_ceil_half_and_double() -> void:
	assert_eq(_menu.minimum_price(&"tomato_soup"), 5)
	assert_eq(_menu.maximum_price(&"tomato_soup"), 18)
	assert_true(_menu.set_price(&"tomato_soup", 10))
	assert_eq(_menu.price_of(_soup), 10)
	assert_true(_menu.set_price(&"tomato_soup", -MenuSettings.MAX_PRICE - 1))
	assert_eq(_menu.price_of(_soup), 5)
	assert_true(_menu.set_price(&"tomato_soup", MenuSettings.MAX_PRICE))
	assert_eq(_menu.price_of(_soup), 18)
	assert_eq(_soup.standard_price, 9)
	assert_eq(_menu.standard_price(&"tomato_soup"), 9)
	assert_eq(_menu.minimum_price(&"missing"), 0)
	assert_eq(_menu.maximum_price(&"missing"), 0)


func test_zero_and_largest_integer_standard_prices_use_safe_bounds() -> void:
	var free: RecipeDef = _recipe(&"free", 0)
	var largest: RecipeDef = _recipe(&"largest", MenuSettings.MAX_PRICE)
	var half: RecipeDef = _recipe(&"half", MenuSettings.MAX_PRICE >> 1)
	var menu: MenuSettings = MenuSettings.new([largest, free, half])
	assert_true(menu.is_valid())
	assert_eq(menu.minimum_price(&"free"), 0)
	assert_eq(menu.maximum_price(&"free"), 0)
	assert_true(menu.set_price(&"free", MenuSettings.MAX_PRICE))
	assert_eq(menu.price_of(free), 0)
	assert_eq(menu.minimum_price(&"largest"), 4611686018427387904)
	assert_eq(menu.maximum_price(&"largest"), MenuSettings.MAX_PRICE)
	assert_eq(menu.maximum_price(&"half"), MenuSettings.MAX_PRICE - 1)
	assert_true(menu.set_price(&"largest", 0))
	assert_eq(menu.price_of(largest), 4611686018427387904)
	assert_true(menu.set_price(&"largest", MenuSettings.MAX_PRICE))
	assert_eq(menu.price_of(largest), MenuSettings.MAX_PRICE)
	assert_eq(largest.standard_price, MenuSettings.MAX_PRICE)


func test_save_round_trip_is_canonical_detached_and_preserves_recipes() -> void:
	assert_true(_menu.set_enabled(&"grilled_cheese", false))
	assert_true(_menu.set_price(&"burger", 18))
	assert_true(_menu.set_price(&"tomato_soup", 5))
	var snapshot: Dictionary = _menu.to_dict()
	assert_eq(snapshot["enabled"], ["burger", "tomato_soup"] as Array[String])
	assert_eq(snapshot["prices"], {"burger": "18", "grilled_cheese": "8", "tomato_soup": "5"})
	var restored: MenuSettings = MenuSettings.new([_cheese, _soup, _burger])
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(snapshot))))
	assert_eq(restored.to_dict(), snapshot)
	assert_eq(_ids(restored.enabled_recipes()), [&"burger", &"tomato_soup"] as Array[StringName])
	snapshot["enabled"].clear()
	snapshot["prices"]["burger"] = "24"
	assert_eq(_menu.price_of(_burger), 18)
	assert_eq(_menu.enabled_count(), 2)
	assert_eq(restored.price_of(_burger), 18)
	assert_eq([_burger.standard_price, _cheese.standard_price, _soup.standard_price], [12, 8, 9])


func test_json_round_trip_preserves_full_integer_prices_without_float_rounding() -> void:
	var definition: RecipeDef = _recipe(&"large", MenuSettings.MAX_PRICE)
	var menu: MenuSettings = MenuSettings.new([definition])
	var restored: MenuSettings = MenuSettings.new([definition])
	var serialized: String = JSON.stringify(menu.to_dict())
	assert_true(serialized.contains('"9223372036854775807"'))
	assert_true(restored.from_dict(JSON.parse_string(serialized)))
	assert_eq(restored.price_of(definition), MenuSettings.MAX_PRICE)
	assert_true(menu.set_price(&"large", menu.minimum_price(&"large")))
	var discounted: Variant = JSON.parse_string(JSON.stringify(menu.to_dict()))
	assert_true(restored.from_dict(discounted))
	assert_eq(restored.price_of(definition), 4611686018427387904)


## FK-083: a dish the save has no price for (a drink whose station staff
## could not reach, so it was off the live menu) loads off at its standard
## price instead of rejecting the whole save.
func test_a_disabled_dish_missing_from_the_save_loads_off_at_its_standard_price() -> void:
	var section: Dictionary = {"enabled": ["burger"], "prices": {"burger": "12", "grilled_cheese": "8"}}
	assert_true(_menu.from_dict(section))
	assert_false(_menu.is_enabled(&"tomato_soup"))
	assert_eq(_menu.price_of(_menu.recipe(&"tomato_soup")), _menu.standard_price(&"tomato_soup"))
	assert_false(_menu.from_dict({"enabled": ["burger", "tomato_soup"], "prices": {"burger": "12"}}),
		"an enabled dish still needs its saved price")


func test_invalid_save_shapes_ids_and_missing_prices_do_not_change_current_choices() -> void:
	assert_true(_menu.set_enabled(&"burger", false))
	assert_true(_menu.set_price(&"tomato_soup", 13))
	var before: Dictionary = _menu.to_dict()
	var valid_prices: Dictionary = before["prices"].duplicate(true)
	var invalid: Array[Variant] = [null, [], "menu", {},
		{"enabled": ["burger"]}, {"prices": valid_prices},
		{"enabled": ["burger"], "prices": valid_prices, "extra": true},
		{"enabled": [], "prices": valid_prices},
		{"enabled": true, "prices": valid_prices},
		{"enabled": ["burger", "burger"], "prices": valid_prices},
		{"enabled": ["missing"], "prices": valid_prices},
		{"enabled": [""], "prices": valid_prices},
		{"enabled": [12], "prices": valid_prices},
		{"enabled": ["burger"], "prices": []},
		{"enabled": ["burger"], "prices": {}},
		{"enabled": ["burger"], "prices": {"missing": "12", "grilled_cheese": "8", "tomato_soup": "9"}},
		{"enabled": ["burger"], "prices": {&"burger": "12", "grilled_cheese": "8", "tomato_soup": "9"}}]
	for section: Variant in invalid:
		assert_false(_menu.from_dict(section), str(section))
		assert_eq(_menu.to_dict(), before, "failed restores are atomic")


func test_invalid_or_out_of_range_prices_are_rejected_without_partial_restore() -> void:
	assert_true(_menu.set_enabled(&"burger", false))
	assert_true(_menu.set_price(&"tomato_soup", 13))
	var before: Dictionary = _menu.to_dict()
	var invalid_prices: Array[Variant] = [-1, 1, 25, 12.5, INF, NAN, true, null, [], {},
		"", "-1", "+12", "012", "12.0", " 12", "12 ", "9223372036854775808", "99999999999999999999"]
	for price: Variant in invalid_prices:
		# duplicate(true) retains the writer's Dictionary[String, String] type.
		# JSON-shaped containers must permit malformed Variants to reach validation.
		var section: Dictionary = JSON.parse_string(JSON.stringify(before))
		section["enabled"] = ["burger"]
		section["prices"]["burger"] = price
		assert_false(_menu.from_dict(section), str(price))
		assert_eq(_menu.to_dict(), before)
	var numeric: Dictionary = {"enabled": ["tomato_soup", "burger"],
		"prices": {"burger": 18.0, "grilled_cheese": 8, "tomato_soup": 9.0}}
	assert_true(_menu.from_dict(numeric), "precise integral JSON numbers remain readable")
	assert_eq(_menu.to_dict()["enabled"], ["burger", "tomato_soup"] as Array[String])
	assert_eq(_menu.price_of(_burger), 18)


func test_imprecise_json_numeric_prices_are_rejected_transactionally() -> void:
	var definition: RecipeDef = _recipe(&"large", MenuSettings.MAX_JSON_INTEGER)
	var menu: MenuSettings = MenuSettings.new([definition])
	var before: Dictionary = menu.to_dict()
	assert_false(menu.from_dict({"enabled": ["large"], "prices": {"large": float(MenuSettings.MAX_JSON_INTEGER + 1)}}))
	assert_eq(menu.to_dict(), before)
	var imprecise: Dictionary = JSON.parse_string('{"enabled":["large"],"prices":{"large":9007199254740993}}')
	assert_eq(typeof(imprecise["prices"]["large"]), TYPE_FLOAT)
	assert_true(imprecise["prices"]["large"] > MenuSettings.MAX_JSON_INTEGER)
	assert_false(menu.from_dict(imprecise), "an imprecise JSON number remains outside the safe numeric range")
	assert_eq(menu.to_dict(), before)
	# Godot's decimal-float literal parser rounds 9007199254740991.0 down by one.
	# Convert the exact integer instead, so the fixture actually supplies 2^53 - 1.
	var exact_numeric: float = float(MenuSettings.MAX_JSON_INTEGER)
	assert_eq(int(exact_numeric), MenuSettings.MAX_JSON_INTEGER)
	assert_true(menu.from_dict({"enabled": ["large"], "prices": {"large": exact_numeric}}))
	assert_eq(menu.price_of(definition), MenuSettings.MAX_JSON_INTEGER)
	assert_eq(menu.to_dict()["prices"]["large"], "9007199254740991")
	assert_true(menu.from_dict(JSON.parse_string(JSON.stringify(before))), "canonical decimal strings stay exact through JSON")
	assert_eq(menu.price_of(definition), MenuSettings.MAX_JSON_INTEGER)


func test_invalid_injected_catalogs_fail_without_partial_defaults_or_engine_errors() -> void:
	var empty_id: RecipeDef = _recipe(&"", 9)
	var negative: RecipeDef = _recipe(&"negative", -1)
	var duplicate: RecipeDef = _recipe(&"burger", 10)
	var invalid_level: RecipeDef = _recipe(&"invalid_level", 10)
	invalid_level.unlock_level = 0
	var locked_only: RecipeDef = _recipe(&"locked_only", 10)
	locked_only.unlock_level = 2
	var invalid_section: RecipeDef = _recipe(&"invalid_section", 10)
	invalid_section.set("section", 99)
	var invalid_catalogs: Array = [[], [null], [_burger, null], [_burger, empty_id],
		[_burger, negative], [_burger, duplicate], [_burger, invalid_level], [locked_only], [_burger, invalid_section]]
	for values: Array in invalid_catalogs:
		var catalog: Array[RecipeDef] = []
		catalog.assign(values)
		var menu: MenuSettings = MenuSettings.new(catalog)
		assert_false(menu.is_valid())
		assert_eq(menu.enabled_count(), 0)
		assert_eq(menu.recipes().size(), 0)
		assert_eq(menu.to_dict(), {})
		assert_false(menu.set_enabled(&"burger", true))
		assert_false(menu.from_dict(_menu.to_dict()))
	assert_false(MenuSettings.new([_burger], 0).is_valid())


func test_restaurant_identity_is_canonical_and_invalid_edits_preserve_choices() -> void:
	assert_eq(_menu.restaurant_name(), "Fool's Kitchen")
	assert_eq(_menu.menu_limit(), 6)
	assert_true(_menu.set_restaurant_name("  Café, Soup & Co.  "))
	assert_eq(_menu.restaurant_name(), "Café, Soup & Co.")
	assert_eq(MenuSettings.normalized_restaurant_name("  Café, Soup & Co.  "), _menu.restaurant_name())
	assert_true(_menu.set_restaurant_name("x".repeat(24)))
	var before: Dictionary = _menu.to_dict()
	var invalid: Array[String] = ["", "   ", "x".repeat(25), "A\nB", " A\t", "\rA", "A" + String.chr(1), "A" + String.chr(31),
		"A" + String.chr(127), "A" + String.chr(133), "A" + String.chr(159)]
	for value: String in invalid:
		assert_eq(MenuSettings.normalized_restaurant_name(value), "")
		assert_false(_menu.set_restaurant_name(value))
		assert_eq(_menu.to_dict(), before, "invalid name edits do not alter menu choices")
	assert_true(_menu.set_restaurant_name("Hell's Kitchen"), "names have no profanity filter")
	assert_eq(_burger.standard_price, 12)


func test_identity_round_trips_with_choices_and_legacy_saves_use_default_name() -> void:
	assert_true(_menu.set_restaurant_name("The Little Diner"))
	assert_true(_menu.set_enabled(&"grilled_cheese", false))
	assert_true(_menu.set_price(&"burger", 17))
	var snapshot: Dictionary = _menu.to_dict()
	assert_eq(snapshot["version"], 1)
	assert_eq(snapshot["name"], "The Little Diner")
	var restored: MenuSettings = MenuSettings.new([_burger, _cheese, _soup])
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(snapshot))))
	assert_eq(restored.to_dict(), snapshot)
	var legacy: Dictionary = {"enabled": snapshot["enabled"], "prices": snapshot["prices"]}
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(legacy))))
	assert_eq(restored.restaurant_name(), MenuSettings.DEFAULT_NAME)
	assert_eq(restored.enabled_recipes(), _menu.enabled_recipes())
	assert_eq(restored.price_of(_burger), 17)
	assert_eq(_menu.restaurant_name(), "The Little Diner", "restoring another model does not rename this one")


func test_invalid_identity_save_versions_shapes_and_prices_restore_nothing() -> void:
	assert_true(_menu.set_restaurant_name("Local Favourite"))
	assert_true(_menu.set_enabled(&"burger", false))
	var before: Dictionary = _menu.to_dict()
	var invalid: Array[Dictionary] = []
	for version: Variant in [0, 2, 1.5, true, "1", null]:
		var section: Dictionary = JSON.parse_string(JSON.stringify(before))
		section["version"] = version
		invalid.append(section)
	for name_value: Variant in ["", "   ", "Long".repeat(7), "Name\n", 12, null, []]:
		var section: Dictionary = JSON.parse_string(JSON.stringify(before))
		section["name"] = name_value
		invalid.append(section)
	var missing_name: Dictionary = before.duplicate(true)
	missing_name.erase("name")
	invalid.append(missing_name)
	var extra: Dictionary = before.duplicate(true)
	extra["extra"] = true
	invalid.append(extra)
	var unversioned_name: Dictionary = before.duplicate(true)
	unversioned_name.erase("version")
	invalid.append(unversioned_name)
	var bad_price: Dictionary = JSON.parse_string(JSON.stringify(before))
	bad_price["name"] = "Would Replace Name"
	bad_price["enabled"] = ["burger"]
	bad_price["prices"]["burger"] = "999"
	invalid.append(bad_price)
	for section: Dictionary in invalid:
		assert_false(_menu.from_dict(section))
		assert_eq(_menu.to_dict(), before, "name, dishes and prices are one transaction")


func test_menu_limit_bounds_initial_choices_selection_and_owner_downgrade() -> void:
	var catalog: Array[RecipeDef] = _large_catalog()
	catalog.reverse()
	var menu: MenuSettings = MenuSettings.new(catalog)
	assert_true(menu.is_valid())
	assert_eq(menu.enabled_count(), 6)
	assert_eq(_ids(menu.enabled_recipes()), [&"dish_0", &"dish_1", &"dish_2", &"dish_3", &"dish_4", &"dish_5"] as Array[StringName])
	var before: Dictionary = menu.to_dict()
	assert_false(menu.set_enabled(&"dish_6", true))
	assert_eq(menu.to_dict(), before)
	assert_true(menu.set_enabled(&"dish_0", true), "an already enabled dish is valid even at the limit")
	assert_true(menu.set_enabled(&"dish_0", false))
	assert_true(menu.set_enabled(&"dish_6", true))
	assert_true(menu.set_owner_level(3))
	assert_eq(menu.menu_limit(), 7)
	assert_eq(menu.enabled_count(), 6, "level-ups never silently add dishes")
	assert_true(menu.set_enabled(&"dish_7", true))
	before = menu.to_dict()
	assert_false(menu.set_owner_level(2), "downgrades cannot leave an oversized menu")
	assert_eq(menu.owner_level(), 3)
	assert_eq(menu.to_dict(), before)
	assert_true(menu.set_enabled(&"dish_7", false))
	assert_true(menu.set_owner_level(2))
	assert_eq(menu.menu_limit(), 6)


func test_oversized_menu_survives_every_morning_save_round_trip() -> void:
	var catalog: Array[RecipeDef] = _large_catalog()
	var expanded: MenuSettings = MenuSettings.new(catalog, 5)
	assert_eq(expanded.enabled_count(), 8)
	assert_true(expanded.set_restaurant_name("Eight Courses"))
	var oversized: Dictionary = expanded.to_dict()
	# A versioned save over the level-1 limit still loads: losing the game is
	# worse than an oversized menu, which only blocks additions.
	var small: MenuSettings = MenuSettings.new(catalog)
	assert_eq(small.menu_limit(), 6)
	assert_true(small.from_dict(JSON.parse_string(JSON.stringify(oversized))))
	assert_eq(small.to_dict(), oversized)
	# Legacy load, then the next morning's v1 save, then a fresh load.
	var legacy: Dictionary = {"enabled": oversized["enabled"], "prices": oversized["prices"]}
	var day_one: MenuSettings = MenuSettings.new(catalog)
	assert_true(day_one.from_dict(JSON.parse_string(JSON.stringify(legacy))))
	var resaved: Dictionary = JSON.parse_string(JSON.stringify(day_one.to_dict()))
	assert_eq(int(resaved["version"]), 1)
	var day_two: MenuSettings = MenuSettings.new(catalog)
	assert_true(day_two.from_dict(resaved), "the next morning's save must load")
	assert_eq(day_two.enabled_count(), 8)


func test_unversioned_oversized_menu_loads_and_blocks_additions_until_under_limit() -> void:
	var catalog: Array[RecipeDef] = _large_catalog()
	var expanded: MenuSettings = MenuSettings.new(catalog, 5)
	assert_eq(expanded.enabled_count(), 8)
	var oversized: Dictionary = expanded.to_dict()
	var menu: MenuSettings = MenuSettings.new(catalog)
	assert_eq(menu.menu_limit(), 6)
	# A pre-limit save (no version) with 8 dishes on at level 1 keeps them all.
	var legacy: Dictionary = {"enabled": oversized["enabled"], "prices": oversized["prices"]}
	assert_true(menu.from_dict(JSON.parse_string(JSON.stringify(legacy))))
	assert_eq(menu.enabled_count(), 8)
	assert_eq(menu.restaurant_name(), MenuSettings.DEFAULT_NAME)
	var off: StringName = menu.enabled_recipes()[0].id
	assert_true(menu.set_enabled(off, false))
	assert_false(menu.set_enabled(off, true), "an oversized menu takes no new dish")
	for index: int in range(2):
		assert_true(menu.set_enabled(menu.enabled_recipes()[0].id, false))
	assert_eq(menu.enabled_count(), 5)
	assert_true(menu.set_enabled(off, true), "under the limit again, dishes can be added")


func test_level_up_with_an_oversized_legacy_menu_unlocks_new_recipes() -> void:
	var catalog: Array[RecipeDef] = _large_catalog()
	var later: RecipeDef = _recipe(&"late_dish", 12)
	later.unlock_level = 2
	catalog.append(later)
	var menu: MenuSettings = MenuSettings.new(catalog)
	var enabled: Array[String] = []
	var prices: Dictionary = {}
	for definition: RecipeDef in catalog:
		prices[String(definition.id)] = str(definition.standard_price)
		if definition.unlock_level == 1:
			enabled.append(String(definition.id))
	assert_true(menu.from_dict({"enabled": enabled, "prices": prices}))
	assert_eq(menu.enabled_count(), 8)
	assert_true(menu.set_owner_level(2), "a level-up is never refused by an oversized menu")
	assert_eq(menu.owner_level(), 2)
	assert_false(menu.set_owner_level(1), "a downgrade still respects the smaller limit")
	assert_eq(menu.owner_level(), 2)
	for index: int in range(3):
		assert_true(menu.set_enabled(menu.enabled_recipes()[0].id, false))
	assert_true(menu.set_enabled(&"late_dish", true), "the newly unlocked dish can join once there is room")

func test_menu_tuning_is_injected_detached_and_invalid_tuning_has_no_choices() -> void:
	var tuning: MenuTuning = MenuTuning.new()
	tuning.base_dishes = 2
	tuning.levels_per_extra_dish = 3
	tuning.max_dishes = 4
	var menu: MenuSettings = MenuSettings.new([_burger, _cheese, _soup], 1, tuning)
	assert_eq(menu.enabled_count(), 2)
	assert_eq(menu.menu_limit(), 2)
	tuning.base_dishes = 4
	assert_eq(menu.menu_limit(), 2, "external edits cannot change the live model's limit")
	assert_true(menu.set_owner_level(4))
	assert_eq(menu.menu_limit(), 3)
	assert_true(menu.set_enabled(&"tomato_soup", true))
	tuning.levels_per_extra_dish = 0
	var invalid: MenuSettings = MenuSettings.new([_burger], 1, tuning)
	assert_false(invalid.is_valid())
	assert_eq(invalid.enabled_count(), 0)
	assert_eq(invalid.menu_limit(), 0)
	assert_false(invalid.set_restaurant_name("Invalid"))
	assert_eq(invalid.to_dict(), {})


func _large_catalog() -> Array[RecipeDef]:
	var result: Array[RecipeDef] = []
	for index: int in 8:
		result.append(_recipe(StringName("dish_%d" % index), 10))
	return result


func _recipe(id: StringName, standard: int) -> RecipeDef:
	var definition: RecipeDef = RecipeDef.new()
	definition.id = id
	definition.display_name = String(id).capitalize()
	definition.standard_price = standard
	return definition


func _ids(definitions: Array[RecipeDef]) -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: RecipeDef in definitions:
		result.append(definition.id)
	return result


func test_new_drinks_join_only_while_the_menu_has_room() -> void:
	var food: Array[RecipeDef] = []
	for index: int in range(5):
		food.append(_recipe(StringName("dish_%d" % index), 10))
	var menu: MenuSettings = MenuSettings.new(food)
	assert_eq(menu.enabled_count(), 5)
	assert_eq(menu.menu_limit(), 6)
	var with_drinks: Array[RecipeDef] = food.duplicate()
	for id: StringName in [&"drink_a", &"drink_b"]:
		var drink: RecipeDef = _recipe(id, 3)
		drink.order_type = RecipeDef.COFFEE
		drink.section = RecipeDef.Section.DRINKS
		with_drinks.append(drink)
	assert_true(menu.set_catalogue(with_drinks))
	assert_eq(menu.enabled_count(), 6, "the first new drink fills the last free place")
	assert_true(menu.is_enabled(&"drink_a"))
	assert_false(menu.is_enabled(&"drink_b"), "a full menu leaves the next drink off")
	assert_eq(_ids(menu.crowded_out_drinks()), [&"drink_b"] as Array[StringName], "the panel can name the waiting drink")
	assert_true(menu.set_enabled(&"dish_0", false))
	assert_true(menu.set_enabled(&"drink_b", true))
	assert_true(menu.crowded_out_drinks().is_empty(), "a drink switched on is no longer waiting")
	assert_true(menu.set_enabled(&"drink_b", false))
	assert_true(menu.set_catalogue(food))
	assert_true(menu.crowded_out_drinks().is_empty(), "a drink whose station left is not listed")
