extends TestCase

var _rng: RandomNumberGenerator
var _requests: int = 0


func before_each() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 166
	_requests = 0


func test_authored_data_and_invalid_tuning() -> void:
	var tuning: RegularsTuning = RegularCast.DEFAULT_TUNING
	assert_true(tuning.is_valid())
	assert_eq(tuning.min_day, 6)
	assert_true(tuning.cast_cap >= 6 and tuning.cast_cap <= 10)
	var bad: RegularsTuning = tuning.duplicate(true) as RegularsTuning
	bad.min_day = 5
	assert_false(bad.is_valid())
	bad.min_day = 6
	bad.favourite_happiness = NAN
	assert_false(bad.is_valid())
	bad.favourite_happiness = 0.08
	bad.names[1] = bad.names[0]
	assert_false(bad.is_valid())


func test_empty_cast_before_promotion_uses_no_rng_or_provider_calls() -> void:
	var cast: RegularCast = RegularCast.new()
	var initial: int = _rng.state
	for visit_day: int in range(1, 6):
		cast.begin_day(visit_day)
		assert_null(_observe(cast, "cohort", visit_day))
		assert_null(cast.due_regular(visit_day))
	assert_eq(_requests, 0)
	assert_eq(_rng.state, initial)
	assert_eq(cast.active_count(), 0)
	assert_almost_eq(cast.menu_happiness(null, true), 0.0)
	assert_almost_eq(cast.tip_rate(null, true), 0.0)


func test_promotion_requires_regular_type_good_repeat_and_distinct_days() -> void:
	var cast: RegularCast = RegularCast.new()
	assert_null(_observe(cast, "student", 6, &"student"))
	assert_null(_observe(cast, "student", 7, &"student"))
	assert_null(_observe(cast, "unhappy", 6, &"regular", false))
	assert_null(_observe(cast, "bad_food", 6, &"regular", true, 0.4))
	assert_null(_observe(cast, "same_day", 6))
	assert_null(_observe(cast, "same_day", 6))
	assert_eq(_requests, 0)
	var profile: RegularProfile = _observe(cast, "same_day", 7)
	assert_not_null(profile)
	assert_eq(profile.visits, 2)
	assert_eq(profile.repeat_key, "same_day")
	assert_eq(_requests, 1)
	assert_null(_observe(cast, "same_day", 8), "promoted cohorts never promote twice")
	assert_eq(_requests, 1)


func test_stars_and_vibe_thresholds_are_live_promotion_gates() -> void:
	var cast: RegularCast = RegularCast.new()
	assert_null(_observe(cast, "cohort", 1))
	assert_null(_observe(cast, "cohort", 6, &"regular", true, 0.8, 2.49, 2.0))
	assert_null(_observe(cast, "cohort", 7, &"regular", true, 0.8, 3.0, 0.99))
	assert_eq(_requests, 0)
	assert_false(cast.can_promote("cohort", 8, NAN, 5.0))
	assert_false(cast.can_promote("cohort", 8, 5.0, INF))
	assert_not_null(_observe(cast, "cohort", 8, &"regular", true, 0.8, 2.5, 1.0))


func test_cast_cap_unique_names_and_fixed_looks() -> void:
	var cast: RegularCast = RegularCast.new()
	var names: Dictionary[String, bool] = {}
	for index: int in range(cast.tuning.cast_cap + 2):
		var key: String = "cohort_%d" % index
		assert_null(_observe(cast, key, 1))
		var profile: RegularProfile = _observe(cast, key, 6)
		if index < cast.tuning.cast_cap:
			assert_not_null(profile)
			assert_false(names.has(profile.display_name))
			names[profile.display_name] = true
			assert_true(cast.tuning.model_ids.has(profile.model_id))
			assert_true(cast.tuning.tint_ids.has(profile.tint_id))
			assert_true(cast.tuning.greetings.has(profile.greeting))
		else:
			assert_null(profile)
	assert_eq(cast.profiles.size(), cast.tuning.cast_cap)
	assert_eq(_requests, cast.tuning.cast_cap)


func test_favourites_learn_enjoyed_dishes_and_most_used_seat() -> void:
	var cast: RegularCast = RegularCast.new()
	var first: Vector2i = Vector2i(2, 3)
	var other: Vector2i = Vector2i(4, 3)
	assert_null(cast.observe_visit("cohort", &"regular", 1, 4.0, 10.0,
		&"burger", first, 0.9, true, _random_provider))
	var profile: RegularProfile = cast.observe_visit("cohort", &"regular", 6,
		4.0, 10.0, &"soup", other, 0.9, true, _random_provider)
	assert_not_null(profile)
	assert_eq(profile.favourite_dish, &"burger", "first enjoyed dish wins a tie")
	assert_eq(profile.favourite_seat, first, "first used seat wins a tie")
	cast.finish_visit(profile, 8, [&"soup"] as Array[StringName], other, true, 0.9, 0.1, true)
	assert_eq(profile.favourite_dish, &"soup")
	assert_eq(profile.favourite_seat, other)
	cast.finish_visit(profile, 10, [&"burger"] as Array[StringName], first, true, 0.1, 0.1, true)
	assert_eq(profile.dish_counts[&"burger"], 1, "bad food is never learnt as an enjoyed dish")


func test_visit_calendar_is_seeded_two_to_four_days_and_no_duplicate_arrival() -> void:
	var a: RegularCast = RegularCast.new()
	var b: RegularCast = RegularCast.new()
	assert_null(_observe(a, "cohort", 1))
	var pa: RegularProfile = _observe(a, "cohort", 6)
	_rng.seed = 166
	assert_null(_observe(b, "cohort", 1))
	var pb: RegularProfile = _observe(b, "cohort", 6)
	assert_eq(pa.to_dict(), pb.to_dict())
	assert_true(pa.next_visit_day >= 8 and pa.next_visit_day <= 10)
	assert_null(a.due_regular(7))
	var due: int = pa.next_visit_day
	var state: int = _rng.state
	assert_eq(a.due_regular(due), pa)
	assert_eq(a.due_regular(due + 1), pa, "missed arrivals remain due")
	assert_eq(_rng.state, state, "calendar queries never draw")
	assert_true(a.mark_arrived(pa, due, _rng))
	assert_eq(a.visited_today, [pa.id] as Array[int])
	state = _rng.state
	assert_false(a.mark_arrived(pa, due, _rng))
	assert_eq(_rng.state, state)
	assert_true(pa.next_visit_day >= due + 2 and pa.next_visit_day <= due + 4)
	assert_null(a.due_regular(due))
	a.begin_day(due + 1)
	assert_eq(a.visited_today.size(), 0)
	assert_eq(a.new_today.size(), 0)


func test_mood_good_bad_waits_missing_favourite_and_departure() -> void:
	var cast: RegularCast = RegularCast.new()
	var profile: RegularProfile = _promoted(cast)
	var start: float = profile.mood
	cast.finish_visit(profile, 8, [&"burger"] as Array[StringName], Vector2i.ONE, true, 0.9, 0.1, true)
	assert_almost_eq(profile.mood, start + cast.tuning.good_visit_gain)
	cast.finish_visit(profile, 10, [&"burger"] as Array[StringName], Vector2i.ONE, true, 0.9, 0.9, true)
	assert_almost_eq(profile.mood, start + cast.tuning.good_visit_gain - cast.tuning.bad_visit_loss)
	# First missing favourite is tolerated; repeated omissions cost mood.
	start = profile.mood
	cast.finish_visit(profile, 12, [&"soup"] as Array[StringName], Vector2i.ONE, true, 0.9, 0.1, false)
	assert_almost_eq(profile.mood, start + cast.tuning.good_visit_gain)
	start = profile.mood
	cast.finish_visit(profile, 14, [&"soup"] as Array[StringName], Vector2i.ONE, true, 0.9, 0.1, false)
	assert_almost_eq(profile.mood, start + cast.tuning.good_visit_gain - cast.tuning.missing_favourite_loss)
	for visit_day: int in [16, 18, 20]:
		cast.finish_visit(profile, visit_day, [] as Array[StringName], Vector2i.ONE, false, 0.0, 1.0, false)
	assert_false(profile.active)
	assert_eq(cast.left_today, [profile.id] as Array[int])
	assert_null(cast.due_regular(30))
	assert_almost_eq(cast.tip_rate(profile, true), 0.0)
	start = profile.mood
	cast.finish_visit(profile, 22, [&"burger"] as Array[StringName], Vector2i.ONE, true, 0.9, 0.1, true)
	assert_eq(profile.mood, start, "departed guests cannot be revived by a stale callback")


func test_menu_pull_is_gentle_and_missing_favourite_neutral() -> void:
	var cast: RegularCast = RegularCast.new()
	var profile: RegularProfile = _promoted(cast)
	assert_almost_eq(cast.menu_happiness(profile, true), 0.08)
	assert_almost_eq(cast.menu_happiness(profile, false), 0.0)
	assert_almost_eq(cast.tip_rate(profile, true), 0.08)
	assert_almost_eq(cast.tip_rate(profile, false), 0.04)
	assert_true(cast.favourite_on_menu(&"burger"))
	assert_false(cast.favourite_on_menu(&"soup"))


func test_json_save_round_trip_candidates_promotion_and_legacy_empty() -> void:
	var cast: RegularCast = RegularCast.new()
	var profile: RegularProfile = _promoted(cast)
	assert_null(_observe(cast, "candidate", 6))
	profile.mood = 0.51
	var saved: Dictionary = JSON.parse_string(JSON.stringify(cast.to_dict()))
	var loaded: RegularCast = RegularCast.new()
	assert_true(loaded.from_dict(saved))
	assert_eq(loaded.to_dict(), cast.to_dict())
	assert_not_null(_observe(loaded, "candidate", 7), "anonymous repeat history also survives a morning load")
	assert_true(loaded.from_dict({}))
	assert_eq(loaded.profiles.size(), 0)
	assert_eq(loaded.to_dict()["candidates"].size(), 0)


func test_corrupt_save_rejects_transactionally() -> void:
	var cast: RegularCast = RegularCast.new()
	_promoted(cast)
	var before: Dictionary = cast.to_dict()
	var corrupt: Dictionary = before.duplicate(true)
	corrupt["profiles"][0]["mood"] = NAN
	assert_false(cast.from_dict(corrupt))
	assert_eq(cast.to_dict(), before)
	corrupt = before.duplicate(true)
	corrupt["profiles"][0]["name"] = "raw_internal_guest_999"
	assert_false(cast.from_dict(corrupt))
	assert_eq(cast.to_dict(), before)
	corrupt = before.duplicate(true)
	corrupt["profiles"].append(corrupt["profiles"][0].duplicate(true))
	assert_false(cast.from_dict(corrupt))
	assert_eq(cast.to_dict(), before)
	assert_false(cast.from_dict({"version": 2, "profiles": [], "candidates": []}))


func test_saved_calendar_continues_identically_with_saved_seeded_stream() -> void:
	var cast: RegularCast = RegularCast.new()
	var profile: RegularProfile = _promoted(cast)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(cast.to_dict()))
	var loaded: RegularCast = RegularCast.new()
	assert_true(loaded.from_dict(saved))
	var restored_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	restored_rng.seed = _rng.seed
	restored_rng.state = _rng.state
	for visit_day: int in range(7, 26):
		cast.begin_day(visit_day)
		loaded.begin_day(visit_day)
		var due: RegularProfile = cast.due_regular(visit_day)
		var restored_due: RegularProfile = loaded.due_regular(visit_day)
		assert_eq(due != null, restored_due != null)
		if due != null:
			assert_true(cast.mark_arrived(due, visit_day, _rng))
			assert_true(loaded.mark_arrived(restored_due, visit_day, restored_rng))
			assert_true(profile.next_visit_day >= visit_day + 2 and profile.next_visit_day <= visit_day + 4)
		assert_eq(cast.to_dict(), loaded.to_dict())
		assert_eq(_rng.state, restored_rng.state)


func test_candidate_history_corruption_keeps_existing_cast() -> void:
	var cast: RegularCast = RegularCast.new()
	_promoted(cast)
	assert_null(_observe(cast, "candidate", 6))
	var before: Dictionary = cast.to_dict()
	var corrupt: Dictionary = before.duplicate(true)
	corrupt["candidates"][0]["seats"][0]["count"] = -1
	assert_false(cast.from_dict(corrupt))
	assert_eq(cast.to_dict(), before)
	corrupt = before.duplicate(true)
	corrupt["candidates"][0]["key"] = "cohort"
	assert_false(cast.from_dict(corrupt), "a promoted cohort cannot also be anonymous")
	assert_eq(cast.to_dict(), before)


func _promoted(cast: RegularCast) -> RegularProfile:
	assert_null(_observe(cast, "cohort", 1))
	var profile: RegularProfile = _observe(cast, "cohort", 6)
	assert_not_null(profile)
	return profile


func _observe(cast: RegularCast, key: String, visit_day: int,
		type_id: StringName = &"regular", satisfied: bool = true, quality: float = 0.8,
		stars: float = 4.0, vibe: float = 10.0) -> RegularProfile:
	return cast.observe_visit(key, type_id, visit_day, stars, vibe, &"burger",
		Vector2i.ONE, quality, satisfied, _random_provider)


func _random_provider() -> RandomNumberGenerator:
	_requests += 1
	return _rng
