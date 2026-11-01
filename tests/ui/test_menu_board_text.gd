extends TestCase
## Board copy and menu-only theme shares are read-only projections.


func test_automatic_board_chooses_first_nonempty_section_and_sorts_dishes() -> void:
	var menu: Array[RecipeDef] = [
		_recipe(&"main_b", "Burger", RecipeDef.Section.MAINS),
		_recipe(&"starter_b", "Soup", RecipeDef.Section.STARTERS),
		_recipe(&"starter_a", "Salad", RecipeDef.Section.STARTERS),
	]
	assert_eq(MenuBoardText.selected_section(menu), RecipeDef.Section.STARTERS)
	assert_eq(MenuBoardText.text("Café Corner", menu), "Café Corner\nStarters\n• Salad\n• Soup")
	assert_eq(MenuBoardText.text("Café Corner", menu, RecipeDef.Section.MAINS),
		"Café Corner\nMains\n• Burger")


func test_explicit_empty_section_stays_chosen_and_invalid_request_falls_back() -> void:
	var menu: Array[RecipeDef] = [_recipe(&"burger", "Burger", RecipeDef.Section.MAINS)]
	assert_eq(MenuBoardText.selected_section(menu, RecipeDef.Section.BAKERY), RecipeDef.Section.BAKERY)
	assert_eq(MenuBoardText.text("The Fryer", menu, RecipeDef.Section.BAKERY),
		"The Fryer\nBakery\nNo dishes today")
	assert_eq(MenuBoardText.selected_section(menu, 100), RecipeDef.Section.MAINS)
	assert_eq(MenuBoardText.selected_section([] as Array[RecipeDef]), -1)
	assert_eq(MenuBoardText.text("", [] as Array[RecipeDef]),
		MenuSettings.DEFAULT_NAME + "\nToday's menu\nNo dishes today")


func test_board_uses_only_todays_enabled_dishes_and_at_most_four() -> void:
	var recipes: Array[RecipeDef] = []
	for letter: String in ["a", "b", "c", "d", "e", "f"]:
		recipes.append(_recipe(StringName(letter), "Dish " + letter, RecipeDef.Section.MAINS))
	var settings: MenuSettings = MenuSettings.new(recipes)
	assert_true(settings.is_valid())
	assert_true(settings.set_enabled(&"b", false))
	var copy: String = MenuBoardText.text("Fool's Kitchen", settings.enabled_recipes())
	assert_eq(copy, "Fool's Kitchen\nMains\n• Dish a\n• Dish c\n• Dish d\n• Dish e")
	assert_false(copy.contains("Dish b"), "off-menu dishes do not appear")
	assert_false(copy.contains("Dish f"), "the fifth enabled dish does not overflow the board")
	assert_false(copy.contains("$"), "the board does not advertise prices")
	var font: Font = MenuBoardText.THEME.default_font if MenuBoardText.THEME.default_font != null else ThemeDB.fallback_font
	var height: float = font.get_multiline_string_size(copy, HORIZONTAL_ALIGNMENT_LEFT, -1, MenuBoardText.FONT_SIZE).y \
		* MenuBoardText.PIXEL_SIZE
	assert_true(height <= MenuBoardText.FACE_HEIGHT_M,
		"name, section and four dishes fit the actual board face vertically")


func test_drinks_use_the_same_section_as_the_menu_panel() -> void:
	var coffee: RecipeDef = _recipe(&"coffee", "Coffee", RecipeDef.Section.BAKERY)
	coffee.order_type = RecipeDef.COFFEE
	assert_eq(MenuBoardText.selected_section([coffee] as Array[RecipeDef]), RecipeDef.Section.DRINKS)
	assert_eq(MenuBoardText.text("Corner", [coffee] as Array[RecipeDef]), "Corner\nDrinks\n• Coffee")


func test_long_name_and_dish_fit_the_chalkboard_face_with_ellipses() -> void:
	var long_name: String = "W".repeat(100)
	var long_dish: String = "W".repeat(100)
	var copy: String = MenuBoardText.text(long_name,
		[_recipe(&"large", long_dish, RecipeDef.Section.MAINS)] as Array[RecipeDef])
	var lines: PackedStringArray = copy.split("\n")
	assert_eq(lines.size(), 3)
	assert_true(lines[0].ends_with(MenuBoardText.ELLIPSIS))
	assert_true(lines[2].ends_with(MenuBoardText.ELLIPSIS))
	var font: Font = MenuBoardText.THEME.default_font if MenuBoardText.THEME.default_font != null else ThemeDB.fallback_font
	for line: String in lines:
		var width: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, MenuBoardText.FONT_SIZE).x \
			* MenuBoardText.PIXEL_SIZE
		assert_true(width <= MenuBoardText.MAX_LINE_WIDTH_M + 0.0001,
			"every displayed line stays inside the 0.59-metre board face")


func test_theme_shares_count_tagged_dishes_using_authored_labels() -> void:
	var menu: Array[RecipeDef] = []
	for index: int in 3:
		menu.append(_tagged(StringName("diner%d" % index), [&"diner"]))
	for index: int in 2:
		menu.append(_tagged(StringName("cafe%d" % index), [&"cafe"]))
	menu.append(_tagged(&"untagged", []))
	assert_eq(MenuThemeText.summary(menu), "Menu leans: Diner 60%, Café 40%")
	menu.reverse()
	assert_eq(MenuThemeText.summary(menu), "Menu leans: Diner 60%, Café 40%")


func test_multitag_votes_are_full_shares_and_duplicate_unknown_tags_do_not_vote() -> void:
	var menu: Array[RecipeDef] = [
		_tagged(&"both", [&"cafe", &"diner", &"diner", &"unknown"]),
		_tagged(&"diner", [&"diner"]),
		_tagged(&"unknown", [&"unknown"]),
	]
	assert_eq(MenuThemeText.summary(menu), "Menu leans: Diner 100%, Café 50%")


func test_theme_ties_keep_authored_order_and_no_known_tags_read_neutrally() -> void:
	var tied: Array[RecipeDef] = [
		_tagged(&"diner", [&"diner"]), _tagged(&"cosy", [&"cosy"]),
	]
	assert_eq(MenuThemeText.summary(tied), "Menu leans: Cosy 50%, Diner 50%")
	assert_eq(MenuThemeText.summary([] as Array[RecipeDef]), "Menu leans: No theme")
	assert_eq(MenuThemeText.summary([_tagged(&"unknown", [&"unknown"])] as Array[RecipeDef]),
		"Menu leans: No theme")
	var no_menu_votes: VibeTuning = MenuThemeText.DEFAULT_TUNING.duplicate(true) as VibeTuning
	no_menu_votes.theme_menu_weight = 0.0
	assert_true(no_menu_votes.is_valid())
	assert_eq(MenuThemeText.summary(tied, no_menu_votes), "Menu leans: No theme")


func _recipe(id: StringName, title: String, section: RecipeDef.Section) -> RecipeDef:
	var recipe: RecipeDef = RecipeDef.new()
	recipe.id = id
	recipe.display_name = title
	recipe.section = section
	recipe.standard_price = 5
	return recipe


func _tagged(id: StringName, tags: Array[StringName]) -> RecipeDef:
	var recipe: RecipeDef = _recipe(id, String(id), RecipeDef.Section.MAINS)
	recipe.theme_tags = tags
	return recipe
