extends TestCase
## Data-owned menu growth and authored section metadata, without a scene tree.

const TUNING: MenuTuning = preload("res://data/balance/menu.tres")


func test_authored_menu_limit_grows_every_two_levels_and_caps_without_overflow() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.limit_for_level(1), 6)
	assert_eq(TUNING.limit_for_level(2), 6)
	assert_eq(TUNING.limit_for_level(3), 7)
	assert_eq(TUNING.limit_for_level(4), 7)
	assert_eq(TUNING.limit_for_level(12), 11)
	assert_eq(TUNING.limit_for_level(13), 12)
	assert_eq(TUNING.limit_for_level(100), 12)
	assert_eq(TUNING.limit_for_level(9223372036854775807), 12)
	assert_eq(TUNING.limit_for_level(0), 0)


func test_invalid_capacity_tuning_is_rejected_and_large_valid_limits_are_safe() -> void:
	for values: Array in [[0, 2, 12], [-1, 2, 12], [6, 0, 12], [6, -1, 12], [6, 2, 5]]:
		var tuning: MenuTuning = MenuTuning.new()
		tuning.base_dishes = values[0]
		tuning.levels_per_extra_dish = values[1]
		tuning.max_dishes = values[2]
		assert_false(tuning.is_valid())
		assert_eq(tuning.limit_for_level(10), 0)
	var large: MenuTuning = MenuTuning.new()
	large.base_dishes = 9223372036854775806
	large.levels_per_extra_dish = 1
	large.max_dishes = 9223372036854775807
	assert_true(large.is_valid())
	assert_eq(large.limit_for_level(9223372036854775807), 9223372036854775807)


func test_authored_recipe_sections_have_one_plain_label_mapping() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	assert_eq(content.recipe(&"tomato_soup").section, RecipeDef.Section.STARTERS)
	for id: StringName in [&"burger", &"grilled_cheese", &"tomato_melt"]:
		assert_eq(content.recipe(id).section, RecipeDef.Section.MAINS)
	assert_eq(RecipeDef.new().section, RecipeDef.Section.MAINS)
	var expected: Array[String] = ["Starters", "Mains", "Sides", "Drinks", "Desserts", "Bakery"]
	for section: int in RecipeDef.Section.values():
		assert_eq(RecipeDef.section_name(section), expected[section])
	assert_eq(RecipeDef.section_name(-1), "")
	assert_eq(RecipeDef.section_name(6), "")
	assert_eq(RecipeDef.Section.STARTERS, 0)
	assert_eq(RecipeDef.Section.MAINS, 1)
	assert_eq(RecipeDef.Section.SIDES, 2)
	assert_eq(RecipeDef.Section.DRINKS, 3)
	assert_eq(RecipeDef.Section.DESSERTS, 4)
	assert_eq(RecipeDef.Section.BAKERY, 5)
	assert_eq(content.recipe(&"croissant").menu_section(), RecipeDef.Section.BAKERY)
