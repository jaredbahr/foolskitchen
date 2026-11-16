extends TestCase

const TUNING: PrestigeTuning = preload("res://data/balance/prestige.tres")


func test_placed_furniture_and_wall_art_sum_and_lowest_cap_wins() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var grid: SimGrid = SimGrid.new(Vector2i(16, 10))
	for cell: Vector2i in grid.cells():
		grid.set_terrain(cell, SimGrid.Terrain.FLOOR)
	var decor: WallDecor = WallDecor.new()
	assert_eq(Prestige.score(grid, content, decor), 0)
	var cloth: ItemDef = content.item(&"cloth_table")
	for x: int in [1, 4, 7, 10]:
		assert_ne(grid.place_def(cloth, Vector2i(x, 3)), null)
	assert_ne(grid.place_def(content.item(&"lamp_pendant"), Vector2i(2, 6)), null)
	assert_true(decor.add(&"wall_art_peaks", Vector3i(2, 2, 0), 1))
	assert_true(decor.add(&"wall_art_sunrise", Vector3i(4, 2, 0), 1))
	assert_eq(Prestige.score(grid, content), 16)
	assert_eq(Prestige.score(grid, content, decor), 20)
	assert_ne(grid.place_def(content.item(&"jukebox"), Vector2i(7, 6)), null)
	assert_eq(Prestige.score(grid, content, decor), 15)
	assert_true(decor.add(&"neon_open_sign", Vector3i(6, 2, 0), 1, true))
	var evaluated: Prestige.Result = Prestige.evaluate(grid, content, decor)
	assert_eq(evaluated.uncapped_score, 20)
	assert_eq(evaluated.value(), 10)
	assert_eq(evaluated.cap_item.id, &"neon_open_sign")


func test_authored_thresholds_award_at_exact_boundaries() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.thresholds, Vector3i(20, 40, 60))
	var scores: Array[int] = [0, 19, 20, 39, 40, 59, 60, 100]
	var expected: Array[int] = [0, 0, 1, 1, 2, 2, 3, 3]
	for index: int in range(scores.size()):
		assert_eq(Prestige.ladles(scores[index], TUNING), expected[index])


func test_only_a_good_review_raises_the_award_and_the_best_is_kept() -> void:
	var critic: FoodCritic = FoodCritic.new()
	var good: Dictionary = {"cause": &"critic_good", "stars": 4}
	var bad: Dictionary = {"cause": &"critic_bad", "stars": 2}
	assert_eq(critic.award_golden_ladles({}, 2), 0)
	assert_eq(critic.award_golden_ladles(bad, 3), 0)
	assert_eq(critic.golden_ladles, 0)
	assert_eq(critic.award_golden_ladles(good, 2), 2)
	assert_eq(critic.award_golden_ladles(bad, 3), 0)
	assert_eq(critic.award_golden_ladles(good, 1), 0)
	assert_eq(critic.award_golden_ladles(good, 2), 0)
	assert_eq(critic.golden_ladles, 2)
	good["golden_ladles_awarded"] = 2
	var lines: Array[String] = FoodCritic.report_lines(good)
	assert_eq(lines.back(), "The critic awarded your kitchen two Golden Ladles!")
	assert_eq(critic.award_golden_ladles(good, 3), 3)


func test_recognition_round_trips_and_legacy_critic_state_defaults_to_zero() -> void:
	var critic: FoodCritic = FoodCritic.new()
	var legacy: Dictionary = critic.to_dict()
	assert_false(legacy.has("golden_ladles"))
	critic.award_golden_ladles({"cause": &"critic_good"}, 2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(critic.to_dict()))
	var restored: FoodCritic = FoodCritic.new()
	assert_true(restored.from_dict(saved))
	assert_eq(restored.golden_ladles, 2)
	saved["golden_ladles"] = 4
	assert_false(restored.from_dict(saved))
	assert_eq(restored.golden_ladles, 2)
	assert_true(restored.from_dict(legacy))
	assert_eq(restored.golden_ladles, 0)
