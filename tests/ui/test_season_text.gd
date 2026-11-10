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
	var in_season_id: StringName = &""
	var out_of_season_id: StringName = &""
	for ingredient: IngredientDef in content.ingredients():
		if SEASON_TUNING.is_in_season(ingredient.id, kind):
			in_season_id = ingredient.id
		if SEASON_TUNING.is_out_of_season(ingredient.id, kind):
			out_of_season_id = ingredient.id
	assert_false(in_season_id.is_empty(), "Spring has authored in-season ingredients")
	assert_false(out_of_season_id.is_empty(), "Spring has authored pricey ingredients")
	assert_eq(SeasonText.ingredient_tag(in_season_id, day, SEASON_TUNING), "In season")
	assert_eq(SeasonText.ingredient_tag(out_of_season_id, day, SEASON_TUNING), "Pricey this season")
	assert_eq(SeasonText.ingredient_tag(&"not_an_ingredient", day, SEASON_TUNING), "")
