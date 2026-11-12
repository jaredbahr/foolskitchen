extends TestCase

const SEASON_TUNING: SeasonTuning = preload("res://data/balance/seasons.tres")


func test_season_names_follow_all_calendar_boundaries() -> void:
	for row: Array in [[1, "Spring"], [28, "Spring"], [29, "Summer"], [112, "Winter"], [113, "Spring"]]:
		assert_eq(SeasonText.name_for_day(int(row[0])), String(row[1]))


func test_ingredient_tags_match_authored_season_lists() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var day: int = 1
	var kind: Season.Kind = Season.kind_for_day(day)
	var tagged: int = 0
	for ingredient: IngredientDef in content.ingredients():
		var id: StringName = ingredient.id
		var tag: String = SeasonText.ingredient_tag(id, day, SEASON_TUNING, ingredient.unit_cost)
		var price: int = Season.purchase_unit_cost(id, ingredient.unit_cost, day, SEASON_TUNING)
		if price == ingredient.unit_cost:
			assert_eq(tag, "", "%s keeps its usual price, so it gets no tag" % id)
		elif SEASON_TUNING.is_in_season(id, kind):
			assert_eq(tag, "In season", String(id))
			tagged += 1
		else:
			assert_true(SEASON_TUNING.is_out_of_season(id, kind), String(id))
			assert_eq(tag, "Pricey this season", String(id))
			tagged += 1
	assert_true(tagged > 0, "spring moves at least one price")
	assert_eq(SeasonText.ingredient_tag(&"not_an_ingredient", day, SEASON_TUNING, 3), "")


func test_a_listed_ingredient_whose_rounded_price_does_not_move_gets_no_tag() -> void:
	# Spring lists bread ($1) as in season and tomato as pricey, but 0.8 and 1.2
	# round both back to their usual price; shrimp ($3) really drops to $2.
	assert_true(SEASON_TUNING.is_in_season(&"bread", Season.kind_for_day(1)))
	assert_eq(SeasonText.ingredient_tag(&"bread", 1, SEASON_TUNING, 1), "")
	assert_eq(SeasonText.ingredient_tag(&"tomato", 1, SEASON_TUNING, 1), "")
	assert_eq(SeasonText.ingredient_tag(&"shrimp", 1, SEASON_TUNING, 3), "In season")
	assert_eq(SeasonText.ingredient_tag(&"mussels", 1, SEASON_TUNING, 3), "Pricey this season")
