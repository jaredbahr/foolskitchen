extends TestCase
## Owner XP is a pure day-close calculation, independent of scenes or saves.

const TUNING: ProgressionTuning = preload("res://data/balance/progression.tres")


func test_authored_sources_and_known_day_breakdown() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.happy_guest_xp, 2)
	assert_eq(TUNING.profit_step, 10)
	assert_eq(TUNING.profit_step_xp, 1)
	assert_eq(TUNING.five_star_review_xp, 3)
	var progress: OwnerProgress = OwnerProgress.new(TUNING)
	var gained: Dictionary = progress.award_day(1, 4, 37, 2)
	assert_eq(gained["happy_xp"], 8)
	assert_eq(gained["profit_xp"], 3)
	assert_eq(gained["review_xp"], 6)
	assert_eq(gained["total_xp"], 17)
	assert_eq(gained["level_before"], 1)
	assert_eq(gained["level_after"], 1)
	assert_eq(gained["levels_gained"], [] as Array[int])
	assert_eq(progress.total_xp, 17)
	assert_eq(progress.last_awarded_day, 1)
	assert_eq(progress.award_day(1, 4, 37, 2), {})
	assert_eq(progress.total_xp, 17)


func test_total_xp_thresholds_follow_the_authored_power_curve() -> void:
	var progress: OwnerProgress = OwnerProgress.new(TUNING)
	assert_eq(progress.threshold_for(1), 0)
	assert_eq(progress.threshold_for(2), ceili(TUNING.level_base * pow(2.0, 1.5)))
	assert_eq(progress.threshold_for(3), ceili(TUNING.level_base * pow(3.0, 1.5)))
	assert_eq(progress.threshold_for(6), ceili(TUNING.level_base * pow(6.0, 1.5)))
	for target: int in [2, 3, 6, 20]:
		var threshold: int = progress.threshold_for(target)
		assert_eq(progress.level_at(threshold - 1), target - 1)
		assert_eq(progress.level_at(threshold), target)
	var at_two: int = progress.threshold_for(2)
	assert_true(progress.from_dict({"version": 1, "total_xp": at_two,
		"level": 2, "last_awarded_day": 3}))
	assert_eq(progress.xp_into_level(), 0)
	assert_eq(progress.xp_in_level(), progress.threshold_for(3) - at_two)


func test_one_day_can_cross_multiple_levels_without_skipping_unlock_numbers() -> void:
	var small: ProgressionTuning = TUNING.duplicate() as ProgressionTuning
	small.level_base = 10
	var progress: OwnerProgress = OwnerProgress.new(small)
	var gained: Dictionary = progress.award_day(1, 30, 0)
	assert_eq(gained["total_xp"], 60)
	assert_eq(gained["levels_gained"], [2, 3] as Array[int])
	assert_eq(progress.level, 3)
	assert_eq(progress.xp_into_level(), 60 - progress.threshold_for(3))


func test_negative_profit_partial_steps_and_empty_days_are_bounded() -> void:
	var progress: OwnerProgress = OwnerProgress.new(TUNING)
	assert_eq(progress.award_day(1, 1, -500)["total_xp"], 2)
	assert_eq(progress.award_day(2, 0, 9)["profit_xp"], 0)
	assert_eq(progress.award_day(3, 0, 10)["profit_xp"], 1)
	assert_eq(progress.award_day(4, 0, 0)["total_xp"], 0)
	assert_eq(progress.last_awarded_day, 4)
	assert_eq(progress.award_day(4, 20, 1000), {})
	assert_eq(progress.award_day(5, -1, 0), {})
	assert_eq(progress.award_day(5, 0, 0, -1), {})
	assert_eq(progress.last_awarded_day, 4)
	assert_eq(progress.total_xp, 3)


func test_present_save_section_decodes_strictly_and_transactionally() -> void:
	var progress: OwnerProgress = OwnerProgress.new(TUNING)
	progress.award_day(1, 6, 50)
	var saved: Dictionary = progress.to_dict()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored: OwnerProgress = OwnerProgress.new(TUNING)
	assert_true(restored.from_dict(decoded))
	assert_eq(restored.to_dict(), saved)
	var malformed: Array[Variant] = [{}, {"version": 1, "total_xp": 0,
		"level": 1, "last_awarded_day": 0, "extra": true}]
	var wrong: Dictionary = decoded.duplicate(true)
	wrong["level"] = 2
	malformed.append(wrong)
	wrong = decoded.duplicate(true)
	wrong["total_xp"] = 1.5
	malformed.append(wrong)
	wrong = decoded.duplicate(true)
	wrong["last_awarded_day"] = -1
	malformed.append(wrong)
	wrong = decoded.duplicate(true)
	wrong["version"] = 2
	malformed.append(wrong)
	for value: Variant in malformed:
		assert_false(restored.from_dict(value))
		assert_eq(restored.to_dict(), saved)
