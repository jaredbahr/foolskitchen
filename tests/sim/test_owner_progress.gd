extends TestCase
## Owner XP is a pure day-close calculation, independent of scenes or saves.

const TUNING: ProgressionTuning = preload("res://data/balance/progression.tres")


func test_authored_sources_and_known_day_breakdown() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.happy_guest_xp, 2)
	assert_eq(TUNING.profit_step, 10)
	assert_eq(TUNING.profit_step_xp, 1)
	assert_eq(TUNING.five_star_review_xp, 3)
	assert_eq(TUNING.level_base, 24)
	assert_eq(TUNING.level_exponent, 2.0)
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
	assert_eq(progress.threshold_for(2), 96)
	assert_eq(progress.threshold_for(3), 216)
	assert_eq(progress.threshold_for(6), 864)
	for target: int in [2, 3, 6, 20]:
		var threshold: int = progress.threshold_for(target)
		assert_eq(progress.level_at(threshold - 1), target - 1)
		assert_eq(progress.level_at(threshold), target)
	var at_two: int = progress.threshold_for(2)
	assert_true(progress.from_dict({"version": 1, "total_xp": at_two,
		"level": 2, "last_awarded_day": 3}))
	assert_eq(progress.xp_into_level(), 0)
	assert_eq(progress.xp_in_level(), progress.threshold_for(3) - at_two)


func test_level_exponent_is_authored_and_validated() -> void:
	var alternate: ProgressionTuning = TUNING.duplicate() as ProgressionTuning
	alternate.level_base = 10
	alternate.level_exponent = 1.5
	var progress: OwnerProgress = OwnerProgress.new(alternate)
	assert_eq(progress.threshold_for(4), 80)
	alternate.level_exponent = 2.0
	assert_eq(progress.threshold_for(4), 160)
	alternate.level_exponent = 0.0
	assert_false(alternate.is_valid())
	assert_eq(progress.threshold_for(4), OwnerProgress.MAX_TOTAL_XP + 1)


func test_one_day_can_cross_multiple_levels_without_skipping_unlock_numbers() -> void:
	var small: ProgressionTuning = TUNING.duplicate() as ProgressionTuning
	small.level_base = 10
	var progress: OwnerProgress = OwnerProgress.new(small)
	var gained: Dictionary = progress.award_day(1, 50, 0)
	assert_eq(gained["total_xp"], 100)
	assert_eq(gained["levels_gained"], [2, 3] as Array[int])
	assert_eq(progress.level, 3)
	assert_eq(progress.xp_into_level(), 100 - progress.threshold_for(3))


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


func test_bonus_crosses_authored_thresholds_without_consuming_the_daily_guard() -> void:
	var progress: OwnerProgress = OwnerProgress.new(TUNING)
	var initial_xp: int = progress.threshold_for(2) - 1
	assert_true(progress.from_dict({"version": 1, "total_xp": initial_xp,
		"level": 1, "last_awarded_day": 4}))
	var amount: int = progress.threshold_for(3) - initial_xp
	var gained: Dictionary = progress.award_bonus(amount)
	assert_eq(gained["bonus_xp"], amount)
	assert_eq(gained["total_xp"], amount)
	assert_eq(gained["level_before"], 1)
	assert_eq(gained["level_after"], 3)
	assert_eq(gained["levels_gained"], [2, 3] as Array[int])
	assert_eq(progress.total_xp, progress.threshold_for(3))
	assert_eq(progress.last_awarded_day, 4)
	assert_eq(progress.award_day(4, 10, 100), {}, "bonus XP cannot reopen a settled day")
	assert_eq(progress.award_day(5, 0, 0)["total_xp"], 0)
	assert_eq(progress.last_awarded_day, 5)


func test_bonus_zero_exact_capacity_and_rejected_amounts_are_atomic() -> void:
	var progress: OwnerProgress = OwnerProgress.new(TUNING)
	var maximum: int = OwnerProgress.MAX_TOTAL_XP
	assert_true(progress.from_dict({"version": 1, "total_xp": maximum - 1,
		"level": progress.level_at(maximum - 1), "last_awarded_day": 7}))
	assert_eq(progress.award_bonus(1)["total_xp"], 1)
	assert_eq(progress.total_xp, maximum)
	var before: Dictionary = progress.to_dict()
	var zero: Dictionary = progress.award_bonus(0)
	assert_eq(zero["bonus_xp"], 0)
	assert_eq(zero["total_xp"], 0)
	assert_eq(zero["levels_gained"], [] as Array[int])
	assert_eq(progress.to_dict(), before, "zero is valid even at the XP cap")
	for amount: int in [-1, 1, maximum + 1, 9223372036854775807, -9223372036854775807 - 1]:
		assert_eq(progress.award_bonus(amount), {})
		assert_eq(progress.to_dict(), before, "refusal never changes XP, level or the daily guard")
	var fresh: OwnerProgress = OwnerProgress.new(TUNING)
	assert_eq(fresh.award_bonus(maximum)["total_xp"], maximum)
	assert_eq(fresh.total_xp, maximum)
	assert_eq(fresh.last_awarded_day, 0)


func test_bonus_rejects_invalid_configuration_and_existing_state_without_repairing_it() -> void:
	var missing: OwnerProgress = OwnerProgress.new(null)
	var before: Dictionary = missing.to_dict()
	assert_eq(missing.award_bonus(1), {})
	assert_eq(missing.to_dict(), before)
	var private_tuning: ProgressionTuning = TUNING.duplicate(true) as ProgressionTuning
	private_tuning.level_exponent = NAN
	var invalid: OwnerProgress = OwnerProgress.new(private_tuning)
	before = invalid.to_dict()
	assert_eq(invalid.award_bonus(1), {})
	assert_eq(invalid.to_dict(), before)
	var progress: OwnerProgress = OwnerProgress.new(TUNING)
	progress.level = 2
	before = progress.to_dict()
	assert_eq(progress.award_bonus(1), {})
	assert_eq(progress.to_dict(), before)
