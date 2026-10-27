extends TestCase
## Source contract for authored profiles and the customers-RNG selector.

const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")


func test_four_authored_types_are_valid_and_regular_is_neutral() -> void:
	assert_true(TYPES.is_valid())
	assert_eq(TYPES.types.size(), 4)
	var regular: CustomerType = TYPES.find_type(&"regular")
	assert_not_null(regular)
	if regular == null:
		return
	assert_eq(regular.display_name, "Regular")
	assert_eq(regular.budget_multiplier, 1.0)
	assert_eq(regular.patience_multiplier, 1.0)
	assert_eq(regular.quality_weight, 0.0)
	assert_eq(regular.review_chance_multiplier, 1.0)
	assert_eq(regular.party_size_min, 1)
	assert_eq(regular.party_size_max, 2)
	assert_eq(regular.unlock_level, 1)
	assert_eq(regular.weight_for_stars(1.0), regular.weight_for_stars(5.0))
	assert_null(TYPES.find_type(&"not_authored"))


func test_profiles_and_reputation_weights_match_the_data_contract() -> void:
	var student: CustomerType = TYPES.find_type(&"student")
	var foodie: CustomerType = TYPES.find_type(&"foodie")
	var family: CustomerType = TYPES.find_type(&"family")
	assert_not_null(student)
	assert_not_null(foodie)
	assert_not_null(family)
	if student == null or foodie == null or family == null:
		return
	assert_eq(student.budget_multiplier, 0.8)
	assert_eq(student.patience_multiplier, 1.3)
	assert_eq(student.review_chance_multiplier, 0.9)
	assert_eq(student.unlock_level, 1)
	assert_eq(foodie.budget_multiplier, 1.4)
	assert_eq(foodie.patience_multiplier, 0.9)
	assert_true(foodie.quality_weight > family.quality_weight)
	assert_eq(foodie.review_chance_multiplier, 1.4)
	assert_eq(foodie.unlock_level, 3)
	assert_eq(family.budget_multiplier, 1.1)
	assert_eq(family.patience_multiplier, 1.4)
	assert_eq(family.review_chance_multiplier, 1.1)
	assert_eq(family.party_size_min, 2)
	assert_eq(family.party_size_max, 4)
	assert_eq(family.unlock_level, 4)
	assert_true(foodie.weight_for_stars(5.0) > foodie.weight_for_stars(1.0))
	assert_eq(foodie.weight_for_stars(3.0), 13.5)
	assert_eq(foodie.weight_for_stars(0.0), foodie.weight_for_stars(1.0))
	assert_eq(foodie.weight_for_stars(9.0), foodie.weight_for_stars(5.0))


func test_single_regular_uses_no_extra_rng_draw() -> void:
	var only_regular: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	var regular: CustomerType = TYPES.find_type(&"regular")
	only_regular.types.append(regular)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var before: int = rng.state
	for index: int in 20:
		assert_eq(CustomerTypePicker.choose(only_regular, 1, 3.0, rng), regular,
			"Regular-only selection %d" % index)
	assert_eq(rng.state, before, "legacy arrivals retain their random stream")


func test_locked_types_never_spawn_and_same_seed_replays_the_mix() -> void:
	var first: RandomNumberGenerator = RandomNumberGenerator.new()
	var second: RandomNumberGenerator = RandomNumberGenerator.new()
	first.seed = 381
	second.seed = 381
	for index: int in 200:
		var one: CustomerType = CustomerTypePicker.choose(TYPES, 1, 4.5, first)
		var two: CustomerType = CustomerTypePicker.choose(TYPES, 1, 4.5, second)
		assert_not_null(one)
		assert_eq(one, two, "same seed draw %d" % index)
		if one != null:
			assert_true([&"regular", &"student"].has(one.id),
				"level-one draw %d stays unlocked" % index)
	assert_eq(first.state, second.state)


func test_foodie_frequency_rises_with_stars_for_the_same_seed() -> void:
	var low_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var high_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	low_rng.seed = 9021
	high_rng.seed = 9021
	var low_foodies: int = 0
	var high_foodies: int = 0
	for index: int in 400:
		var low: CustomerType = CustomerTypePicker.choose(TYPES, 4, 1.0, low_rng)
		var high: CustomerType = CustomerTypePicker.choose(TYPES, 4, 5.0, high_rng)
		if low != null and low.id == &"foodie":
			low_foodies += 1
		if high != null and high.id == &"foodie":
			high_foodies += 1
	assert_true(high_foodies > low_foodies + 20,
		"authored reputation curve substantially changes the type mix")


func test_invalid_types_and_missing_rng_cannot_be_selected() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4
	assert_null(CustomerTypePicker.choose(TYPES, 1, 3.0, null))
	assert_null(CustomerTypePicker.choose(TYPES, 0, 3.0, rng))
	assert_null(CustomerTypePicker.choose(TYPES, 1, NAN, rng))
	var invalid: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	var wrong_party: CustomerType = CustomerType.new()
	wrong_party.id = &"group"
	wrong_party.display_name = "Group"
	wrong_party.party_size_max = 5
	invalid.types.append(wrong_party)
	assert_false(invalid.is_valid())
	assert_null(CustomerTypePicker.choose(invalid, 1, 3.0, rng))


func test_rejected_inputs_and_weight_overflow_leave_named_rng_unchanged() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7401
	var duplicate_ids: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	var duplicate: CustomerType = _weighted_type(&"same", 4.0, 4.0)
	duplicate_ids.types = [duplicate, _weighted_type(&"same", 8.0, 8.0)] as Array[CustomerType]
	_assert_rejected_without_rng(duplicate_ids, 1, 3.0, rng, "duplicate IDs")

	var null_entry: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	null_entry.types = [_weighted_type(&"valid", 4.0, 4.0), null] as Array[CustomerType]
	_assert_rejected_without_rng(null_entry, 1, 3.0, rng, "null catalogue entry")

	var locked_only: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	locked_only.types = [_weighted_type(&"locked", 4.0, 4.0, 2)] as Array[CustomerType]
	_assert_rejected_without_rng(locked_only, 1, 3.0, rng, "no eligible types")

	var zero_weight: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	zero_weight.types = [_weighted_type(&"zero", 0.0, 0.0)] as Array[CustomerType]
	_assert_rejected_without_rng(zero_weight, 1, 3.0, rng, "zero eligible weights")
	_assert_rejected_without_rng(TYPES, 1, NAN, rng, "non-finite reputation")

	var overflow: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	var huge: float = 1.0e308
	overflow.types = [_weighted_type(&"huge_a", huge, huge),
		_weighted_type(&"huge_b", huge, huge)] as Array[CustomerType]
	assert_true(overflow.is_valid(), "each authored weight is finite before accumulation")
	_assert_rejected_without_rng(overflow, 1, 3.0, rng, "accumulated weight overflow")


func test_only_eligible_positive_weight_type_keeps_rng_unchanged() -> void:
	var catalogue: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	catalogue.types = [
		_weighted_type(&"locked", 50.0, 50.0, 4),
		_weighted_type(&"zero", 0.0, 0.0, 2),
		_weighted_type(&"only", 12.0, 12.0, 2),
	] as Array[CustomerType]
	assert_true(catalogue.is_valid())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 617
	var before: int = rng.state
	var chosen: CustomerType = CustomerTypePicker.choose(catalogue, 2, 3.0, rng)
	assert_not_null(chosen)
	if chosen == null:
		return
	assert_eq(chosen.id, &"only")
	assert_eq(rng.state, before, "unlock and zero-weight filtering leave one deterministic choice")


func test_single_weighted_draw_replays_with_same_seed_and_authored_order() -> void:
	var catalogue: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	catalogue.types = [
		_weighted_type(&"first_in_authored_order", 7.0, 7.0),
		_weighted_type(&"second_in_authored_order", 2.0, 2.0),
		_weighted_type(&"third_in_authored_order", 5.0, 5.0),
	] as Array[CustomerType]
	var first_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var replay_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var oracle_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	first_rng.seed = 381
	replay_rng.seed = 381
	oracle_rng.seed = 381
	var before: int = first_rng.state
	var ticket: float = oracle_rng.randf() * 14.0
	var expected_id: StringName = &"first_in_authored_order"
	if ticket >= 7.0 and ticket < 9.0:
		expected_id = &"second_in_authored_order"
	elif ticket >= 9.0:
		expected_id = &"third_in_authored_order"
	var chosen: CustomerType = CustomerTypePicker.choose(catalogue, 1, 3.0, first_rng)
	var replayed: CustomerType = CustomerTypePicker.choose(catalogue, 1, 3.0, replay_rng)
	assert_not_null(chosen)
	assert_not_null(replayed)
	if chosen == null or replayed == null:
		return
	assert_true(catalogue.types.has(chosen), "the selected object belongs to authored catalogue order")
	assert_eq(chosen.id, expected_id, "the independent one-draw ticket lands in the authored weight interval")
	assert_eq(chosen.id, replayed.id, "one weighted draw repeats for the same seed and catalogue")
	assert_ne(first_rng.state, before, "multiple eligible types consume the injected RNG")
	assert_eq(first_rng.state, oracle_rng.state, "the selector consumes exactly one RNG draw")
	assert_eq(first_rng.state, replay_rng.state)


func _assert_rejected_without_rng(catalogue: CustomerTypeCatalogue, owner_level: int,
		stars: float, rng: RandomNumberGenerator, case_name: String) -> void:
	var before: int = rng.state
	assert_null(CustomerTypePicker.choose(catalogue, owner_level, stars, rng), case_name)
	assert_eq(rng.state, before, "%s does not advance the customers RNG" % case_name)


func _weighted_type(id: StringName, one_star: float, five_stars: float,
		unlock_level: int = 1) -> CustomerType:
	var kind: CustomerType = CustomerType.new()
	kind.id = id
	kind.display_name = String(id).capitalize()
	kind.weight_at_one_star = one_star
	kind.weight_at_five_stars = five_stars
	kind.unlock_level = unlock_level
	return kind


func test_pairs_unlock_at_level_five_and_families_keep_their_own_unlock() -> void:
	for id: StringName in [&"regular", &"student", &"foodie"]:
		var kind: CustomerType = TYPES.find_type(id)
		assert_eq(kind.party_unlock_level, 5, String(id) + " comes in pairs from owner level 5")
		assert_eq(kind.group_level(), 5)
		var locked: RandomNumberGenerator = RandomNumberGenerator.new()
		locked.seed = 77
		var before: int = locked.state
		assert_eq(kind.draw_party_size_at(locked, 4), 1)
		assert_eq(locked.state, before, "a locked pair consumes no size draw")
		var open: RandomNumberGenerator = RandomNumberGenerator.new()
		open.seed = 77
		var oracle: RandomNumberGenerator = RandomNumberGenerator.new()
		oracle.seed = 77
		assert_eq(kind.draw_party_size_at(open, 5), oracle.randi_range(1, 2))
		assert_eq(open.state, oracle.state)
	var family: CustomerType = TYPES.find_type(&"family")
	assert_eq(family.party_unlock_level, 1, "families are groups whenever they visit")
	assert_eq(family.group_level(), family.unlock_level)
	var draw: RandomNumberGenerator = RandomNumberGenerator.new()
	draw.seed = 5
	assert_true(family.draw_party_size_at(draw, family.unlock_level) >= 2)
	var locked: CustomerType = TYPES.find_type(&"regular").duplicate() as CustomerType
	locked.party_unlock_level = 0
	assert_false(locked.is_valid())


func test_group_tip_is_reported_once_when_pairs_start_visiting() -> void:
	var tip: String = "Groups of two now visit: bigger tables, more floor and more staff help."
	assert_eq(TYPES.level_up_tips(1, 4), [] as Array[String])
	assert_eq(TYPES.level_up_tips(4, 5), [tip] as Array[String], "one tip, not one per type")
	assert_eq(TYPES.level_up_tips(5, 6), [] as Array[String], "already shown at level 5")
	assert_eq(TYPES.level_up_tips(5, 5), [] as Array[String])
	assert_eq(TYPES.level_up_tips(3, 7), [tip] as Array[String], "a multi-level jump still shows it once")
