extends TestCase
## The career ladder (D30): thresholds, order, never dropping and old saves.

const CAREER: CareerTierTuning = preload("res://data/balance/career_tiers.tres")
const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")


func _owner_at(level: int) -> OwnerProgress:
	var progress: OwnerProgress = OwnerProgress.new(PROGRESSION)
	progress.award_bonus(progress.threshold_for(level))
	return progress


func test_authored_ladder_matches_the_placeholders() -> void:
	assert_true(CAREER.is_valid())
	var rows: Array = []
	for tier: int in range(2, CareerTierTuning.TOP_TIER + 1):
		var rung: CareerTier = CAREER.rung_for(tier)
		rows.append([rung.tier, rung.min_level, rung.min_reputation])
	assert_eq(rows, [[2, 3, 0.0], [3, 6, 4.0], [4, 9, 4.2], [5, 12, 4.4], [6, 15, 4.5]])
	assert_null(CAREER.rung_for(1))
	assert_null(CAREER.rung_for(7))


func test_invalid_ladders_are_refused() -> void:
	var short: CareerTierTuning = CareerTierTuning.new()
	assert_false(short.is_valid())
	assert_eq(short.reachable(1, 99, 5.0), 1, "an invalid ladder never raises")
	var shuffled: CareerTierTuning = CAREER.duplicate(true) as CareerTierTuning
	shuffled.tiers.reverse()
	assert_false(shuffled.is_valid())
	var bad_stars: CareerTierTuning = CAREER.duplicate(true) as CareerTierTuning
	bad_stars.tiers[1].min_reputation = 5.5
	assert_false(bad_stars.is_valid())


func test_thresholds_need_level_and_reputation() -> void:
	assert_eq(CAREER.reachable(1, 2, 5.0), 1, "Tier 2 needs level 3")
	assert_eq(CAREER.reachable(1, 3, 1.0), 2, "Tier 2 needs no reputation")
	assert_eq(CAREER.reachable(1, 6, 3.9), 2, "Tier 3 needs 4.0 stars as well")
	assert_eq(CAREER.reachable(1, 5, 5.0), 2, "Tier 3 needs level 6 as well")
	assert_eq(CAREER.reachable(1, 6, 4.0), 3)
	assert_eq(CAREER.reachable(1, 9, 4.2), 4)
	assert_eq(CAREER.reachable(1, 12, 4.4), 5)
	assert_eq(CAREER.reachable(1, 15, 4.5), 6)
	assert_eq(CAREER.reachable(1, 99, 5.0), 6, "Tier 6 is the top")
	# Stars count at the precision the report shows them.
	assert_eq(CAREER.reachable(2, 6, 3.96), 3, "3.96 shows as 4.0 stars")
	assert_eq(CAREER.reachable(2, 6, 3.94), 2, "3.94 shows as 3.9 stars")
	assert_eq(CAREER.reachable(2, 6, NAN), 2)


func test_tiers_climb_in_order_from_the_current_one() -> void:
	# Level 15 with 4.1 stars meets Tier 6's level but not Tier 4's stars.
	assert_eq(CAREER.reachable(1, 15, 4.1), 3)
	assert_eq(CAREER.reachable(4, 9, 0.0), 4, "a tier already held is kept")


func test_raise_never_drops_and_reports_only_a_change() -> void:
	var progress: OwnerProgress = _owner_at(6)
	assert_eq(progress.career_tier, 1)
	assert_eq(progress.raise_career_tier(CAREER, 4.0), 3)
	assert_eq(progress.career_tier, 3)
	assert_eq(progress.raise_career_tier(CAREER, 4.0), 0, "no change, no announcement")
	assert_eq(progress.raise_career_tier(CAREER, 1.0), 0, "a bad night never loses a tier")
	assert_eq(progress.career_tier, 3)
	assert_eq(progress.raise_career_tier(null, 5.0), 0)
	assert_eq(progress.property_tier, 1, "the ladder never touches the lease")


func test_save_round_trip_and_strict_decode() -> void:
	var progress: OwnerProgress = _owner_at(9)
	progress.raise_career_tier(CAREER, 4.2)
	var saved: Dictionary = progress.to_dict()
	assert_eq(saved["career_tier"], 4)
	var restored: OwnerProgress = OwnerProgress.new(PROGRESSION)
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(restored.career_tier, 4)
	assert_eq(restored.to_dict(), saved)
	for invalid: Variant in [0, 7, 2.5, "3", null]:
		var wrong: Dictionary = saved.duplicate(true)
		wrong["career_tier"] = invalid
		assert_false(restored.from_dict(wrong))
		assert_eq(restored.to_dict(), saved, "a refusal does not partially install progress")


func test_legacy_saves_load_tier_from_the_lease() -> void:
	var progress: OwnerProgress = _owner_at(2)
	var legacy: Dictionary = progress.to_dict()
	legacy.erase("career_tier")
	var restored: OwnerProgress = OwnerProgress.new(PROGRESSION)
	assert_true(restored.from_dict(legacy))
	assert_eq(restored.career_tier, 1, "below Tier 2's level and without an expanded lease")
	var levelled: Dictionary = _owner_at(4).to_dict()
	levelled.erase("career_tier")
	assert_true(restored.from_dict(levelled))
	assert_eq(restored.career_tier, 2, "an old save already at Tier 2's level keeps the lease offer")
	var ladder: CareerTierTuning = preload("res://data/balance/career_tiers.tres")
	assert_eq(OwnerProgress.LEGACY_TIER_TWO_LEVEL, ladder.rung_for(2).min_level,
		"the legacy rule matches the authored Tier 2 level")
	assert_eq(ladder.rung_for(2).min_reputation, 0.0, "Tier 2 has no star condition")
	legacy["property_tier"] = 2
	assert_true(restored.from_dict(legacy))
	assert_eq(restored.career_tier, 2, "an expanded lease meant Tier 2")
	legacy.erase("property_tier")
	assert_true(restored.from_dict(legacy))
	assert_eq([restored.property_tier, restored.career_tier], [1, 1], "the oldest saves")


func test_lease_offer_needs_tier_two_not_the_lease_level() -> void:
	var lease: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
	var progress: OwnerProgress = _owner_at(5)
	assert_false(lease.offered(progress, SimClock.Phase.MORNING))
	assert_eq(lease.refusal(progress, SimClock.Phase.MORNING, 100000, 0),
		"Unlocks when your restaurant reaches Tier 2")
	progress.raise_career_tier(CAREER, 3.0)
	assert_true(lease.offered(progress, SimClock.Phase.MORNING))
	assert_eq(lease.refusal(progress, SimClock.Phase.MORNING, 100000, 0), "")


func test_goal_and_report_text() -> void:
	assert_eq(CAREER.goal_text(1), "Tier 1 → Tier 2: reach level 3")
	assert_eq(CAREER.goal_text(2), "Tier 2 → Tier 3: reach level 6 and 4.0 stars")
	assert_eq(CAREER.goal_text(5), "Tier 5 → Tier 6: reach level 15 and 4.5 stars")
	assert_eq(CAREER.goal_text(6), "Top tier reached")
	assert_eq(CareerTierTuning.reached_text(3), "Your restaurant reached Tier 3!")


func test_tier_two_content_unlocks_at_level_three_without_the_lease() -> void:
	var floor: FloorStyleDef = FloorStyleDef.new()
	floor.unlock_tier = 2
	var progress: OwnerProgress = _owner_at(3)
	assert_false(floor.unlocked(progress.level, progress.career_tier))
	assert_eq(floor.locked_reason(progress.level, progress.career_tier), "Unlocks at Tier 2")
	progress.raise_career_tier(CAREER, 3.0)
	assert_eq(progress.property_tier, 1)
	assert_true(floor.unlocked(progress.level, progress.career_tier))
