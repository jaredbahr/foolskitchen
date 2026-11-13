extends TestCase

const LEASE: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")
const CAREER: CareerTierTuning = preload("res://data/balance/career_tiers.tres")


func test_offer_starts_at_authored_level_and_tier_is_strictly_decoded() -> void:
	var progress: OwnerProgress = OwnerProgress.new(PROGRESSION)
	assert_true(LEASE.is_valid())
	progress.award_bonus(progress.threshold_for(LEASE.owner_level) - 1)
	assert_eq(progress.raise_career_tier(CAREER, 5.0), 0)
	assert_false(LEASE.offered(progress, false, SimClock.Phase.MORNING))
	progress.award_bonus(1)
	assert_false(LEASE.offered(progress, false, SimClock.Phase.MORNING), "the offer waits for the close's Tier 2")
	assert_eq(progress.raise_career_tier(CAREER, 3.0), 2)
	assert_true(LEASE.offered(progress, false, SimClock.Phase.MORNING))
	assert_false(LEASE.offered(progress, true, SimClock.Phase.MORNING), "the site's lease is already expanded")
	# The lease is the site's own since #408: the owner never saves it, and
	# reads it from older saves only.
	progress.property_tier = 2
	assert_false(progress.to_dict().has("property_tier"))
	var saved: Dictionary = progress.to_dict()
	saved["property_tier"] = 2
	var restored: OwnerProgress = OwnerProgress.new(PROGRESSION)
	assert_true(restored.from_dict(JSON.parse_string(JSON.stringify(saved))))
	assert_eq(restored.property_tier, 2)
	for invalid: Variant in [0, 3, 1.5, "2", null]:
		var wrong: Dictionary = saved.duplicate(true)
		wrong["property_tier"] = invalid
		assert_false(restored.from_dict(wrong))
		assert_eq(restored.property_tier, 2, "a refusal does not partially install progress")
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
