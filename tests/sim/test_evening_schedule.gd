extends "res://tests/test_case.gd"


func test_changeover_uses_the_opening_hours_grid_and_strict_bounds() -> void:
	var tuning: OpeningHoursTuning = OpeningHoursTuning.new()
	assert_false(EveningSchedule.allowed_minute(660, 660, 1260, tuning))
	assert_false(EveningSchedule.allowed_minute(1260, 660, 1260, tuning))
	assert_false(EveningSchedule.allowed_minute(1021, 660, 1260, tuning))
	assert_true(EveningSchedule.allowed_minute(1020, 660, 1260, tuning))
	assert_false(EveningSchedule.allowed_minute(1020, 1050, 1260, tuning))


func test_changeover_tick_reaches_the_exact_display_minute() -> void:
	var clock: SimClock = SimClock.new()
	var tuning: OpeningHoursTuning = OpeningHoursTuning.new()
	var schedule: EveningSchedule = _schedule()
	var changeover: int = schedule.changeover_tick(clock, tuning)
	assert_eq(changeover, 2160)
	assert_true(clock.start_service())
	clock.phase_tick = changeover - 1
	assert_eq(clock.display_minutes(), 1019)
	clock.advance()
	assert_eq(clock.display_minutes(), 1020)
	schedule.enabled = false
	assert_eq(schedule.changeover_tick(clock, tuning), 0)


func test_short_service_rounds_up_to_the_first_eligible_tick() -> void:
	var clock: SimClock = SimClock.new()
	var schedule: EveningSchedule = _schedule()
	var tuning: OpeningHoursTuning = OpeningHoursTuning.new()
	clock.open_ticks = 19
	assert_eq(schedule.changeover_tick(clock, tuning), 12)
	assert_true(clock.start_service())
	clock.phase_tick = 11
	assert_true(clock.display_minutes() < schedule.minute)
	clock.advance()
	assert_true(clock.display_minutes() >= schedule.minute)
	clock.open_ticks = 1
	assert_eq(schedule.changeover_tick(clock, tuning), 0)


func test_schedule_round_trips_json_and_rejects_invalid_data_atomically() -> void:
	var schedule: EveningSchedule = _schedule()
	var encoded: Dictionary = schedule.to_save()
	var restored: EveningSchedule = EveningSchedule.new()
	assert_true(restored.restore(JSON.parse_string(JSON.stringify(encoded))))
	assert_eq(restored.to_save(), encoded)
	for field: String in ["version", "enabled", "minute", "day_preset", "evening_preset"]:
		var invalid: Dictionary = encoded.duplicate()
		invalid.erase(field)
		assert_false(restored.restore(invalid))
		assert_eq(restored.to_save(), encoded)
	var fractional: Dictionary = encoded.duplicate()
	fractional["minute"] = 1020.5
	assert_false(restored.restore(fractional))
	assert_eq(restored.to_save(), encoded)
	assert_true(restored.restore({}))
	assert_false(restored.enabled)
	assert_eq(restored.to_save(), {})


func test_evening_mix_uses_the_same_seed_and_favors_eligible_foodies() -> void:
	var catalogue: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
	var tuning: DayPartsTuning = preload("res://data/balance/day_parts.tres")
	assert_true(tuning.is_valid())
	var daytime: RandomNumberGenerator = RandomNumberGenerator.new()
	var evening: RandomNumberGenerator = RandomNumberGenerator.new()
	daytime.seed = 591
	evening.seed = 591
	var day_foodies: int = 0
	var evening_foodies: int = 0
	for i: int in 500:
		var day_kind: CustomerType = CustomerTypePicker.choose(catalogue, 6, 4.0, daytime)
		var evening_kind: CustomerType = CustomerTypePicker.choose(catalogue, 6, 4.0, evening, &"", 0.0, tuning)
		day_foodies += int(day_kind.id == &"foodie")
		evening_foodies += int(evening_kind.id == &"foodie")
	assert_true(day_foodies > 0)
	assert_true(evening_foodies > day_foodies * 1.25)
	assert_eq(daytime.state, evening.state, "weighting still uses one draw per ordinary choice")
	var early_kind: CustomerType = CustomerTypePicker.choose(catalogue, 1, 4.0, evening, &"", 0.0, tuning)
	assert_true(early_kind.unlock_level <= 1)


func test_changeover_accounts_for_the_display_clocks_fractional_rounding() -> void:
	var clock: SimClock = SimClock.new()
	var tuning: OpeningHoursTuning = OpeningHoursTuning.new()
	assert_true(OpeningHours.apply(clock, 570, 1230, tuning))
	var schedule: EveningSchedule = _schedule()
	var tick: int = schedule.changeover_tick(clock, tuning)
	assert_true(clock.open_display_minutes_at(tick - 1) < schedule.minute)
	assert_eq(clock.open_display_minutes_at(tick), schedule.minute)


func _schedule() -> EveningSchedule:
	var result: EveningSchedule = EveningSchedule.new()
	result.enabled = true
	result.minute = 1020
	result.day_preset = "Lunch"
	result.evening_preset = "Dinner"
	return result
