extends TestCase

const LEASE: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")


func test_offer_starts_at_authored_level_and_tier_is_strictly_decoded() -> void:
	var progress: OwnerProgress = OwnerProgress.new(PROGRESSION)
	assert_true(LEASE.is_valid())
	progress.award_bonus(progress.threshold_for(LEASE.owner_level) - 1)
	assert_false(LEASE.offered(progress, SimClock.Phase.MORNING))
	progress.award_bonus(1)
	assert_true(LEASE.offered(progress, SimClock.Phase.MORNING))
	progress.property_tier = 2
	var saved: Dictionary = progress.to_dict()
	var restored: OwnerProgress = OwnerProgress.new(PROGRESSION)
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(restored.property_tier, 2)
	for invalid: Variant in [0, 3, 1.5, "2", null]:
		var wrong: Dictionary = saved.duplicate(true)
		wrong["property_tier"] = invalid
		assert_false(restored.from_dict(wrong))
		assert_eq(restored.to_dict(), saved, "a refusal does not partially install progress")
	saved.erase("property_tier")
	assert_true(restored.from_dict(saved))
	assert_eq(restored.property_tier, 1)


func test_floor_and_wall_tier_gates_keep_owner_level_requirements() -> void:
	var floor: FloorStyleDef = FloorStyleDef.new()
	var wall: WallStyleDef = WallStyleDef.new()
	for style: Resource in [floor, wall]:
		style.set("unlock_tier", 2)
		style.set("unlock_level", 3)
		assert_false(style.call("unlocked", 3))
		assert_false(style.call("unlocked", 2, 2))
		assert_true(style.call("unlocked", 3, 2))
		assert_eq(style.call("locked_reason", 3, 2), "")
