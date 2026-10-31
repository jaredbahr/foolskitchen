extends TestCase
## Constructed advice fixtures test policy; no departures or utilization are
## staged in a running restaurant, and no balance outcome is claimed here.

const AUTHORED: StaffAdviceTuning = preload("res://data/balance/staff_advice.tres")


func test_authored_thresholds_match_reviewed_policy() -> void:
	assert_eq(AUTHORED.high_busy_percent, 90.0)
	assert_eq(AUTHORED.low_busy_percent, 70.0)
	assert_eq(AUTHORED.min_waiting_losses, 1)
	assert_eq(AUTHORED.min_no_table_losses, 5)


func test_cook_rule_uses_raw_fraction_and_qualifying_waiting_losses() -> void:
	var summary: Dictionary = _summary({"cook": _row(900, 1000), "server": _row(0, 1000)})
	assert_eq(AUTHORED.recommendation(summary, {&"waited_too_long": 1}), &"cook")
	summary["roles"]["cook"]["busy_ticks"] = 899
	assert_eq(AUTHORED.recommendation(summary, {&"waited_too_long": 1}), &"keeping_up",
		"89.9% can display as90% but must not cross the raw90% threshold")
	summary["roles"]["cook"]["busy_ticks"] = 900
	for losses: Dictionary in [{}, {&"closing": 99}, {&"out_of_stock": 99}, {&"no_table": 99}]:
		assert_eq(AUTHORED.recommendation(summary, losses), &"keeping_up")
	assert_eq(AUTHORED.recommendation(summary, {"waited_too_long": 1}), &"cook",
		"report JSON string keys carry the same facts as runtime StringName keys")


func test_server_rule_and_feasible_cook_server_collision_have_fixed_priority() -> void:
	var summary: Dictionary = _summary({"cook": _row(0, 10), "server": _row(9, 10)})
	assert_eq(AUTHORED.recommendation(summary, {&"waited_too_long": 1}), &"server")
	summary["roles"]["cook"] = _row(9, 10)
	assert_eq(AUTHORED.recommendation(summary, {&"waited_too_long": 1}), &"cook")
	var reordered: Dictionary = _summary({"server": _row(9, 10), "cook": _row(9, 10)})
	assert_eq(AUTHORED.recommendation(reordered, {&"waited_too_long": 1}), &"cook",
		"recommendation priority cannot depend on map insertion order")


func test_tables_require_all_present_regular_roles_strictly_below_low_threshold() -> void:
	var summary: Dictionary = _summary({"cook": _row(699, 1000), "server": _row(0, 1000),
		"cleaner": _row(0, 1000), "owner": _row(1000, 1000)})
	assert_eq(AUTHORED.recommendation(summary, {&"no_table": 5}), &"tables",
		"owner is separate from the regular staffing-capacity predicate")
	assert_eq(AUTHORED.recommendation(summary, {&"no_table": 4}), &"keeping_up")
	summary["roles"]["cook"]["busy_ticks"] = 700
	assert_eq(AUTHORED.recommendation(summary, {&"no_table": 5}), &"keeping_up")
	summary["roles"]["cook"]["busy_ticks"] = 950
	assert_eq(AUTHORED.recommendation(summary, {&"no_table": 50}), &"keeping_up",
		"an idle cleaner must not average away a busy cook and suggest more tables")
	summary["roles"]["cook"]["busy_ticks"] = 0
	summary["roles"]["cleaner"]["busy_ticks"] = 700
	assert_eq(AUTHORED.recommendation(summary, {&"no_table": 5}), &"keeping_up")


func test_unknown_and_owner_only_cannot_claim_capacity_advice() -> void:
	assert_eq(AUTHORED.recommendation({}, {&"no_table": 99, &"waited_too_long": 99}), &"")
	assert_eq(AUTHORED.recommendation(_summary({"owner": _row(0, 10)}), {&"no_table": 99}), &"keeping_up")
	var invalid: Dictionary = _summary({"cook": _row(11, 10)})
	assert_eq(AUTHORED.recommendation(invalid, {&"waited_too_long": 99}), &"")
	assert_eq(AUTHORED.recommendation(_summary({"cook": _row(0, 10)}), {}), &"keeping_up")


func test_custom_authored_thresholds_control_policy_without_mutating_inputs() -> void:
	var custom: StaffAdviceTuning = AUTHORED.duplicate(true) as StaffAdviceTuning
	custom.high_busy_percent = 80
	custom.low_busy_percent = 60
	custom.min_waiting_losses = 2
	custom.min_no_table_losses = 3
	var summary: Dictionary = _summary({"cook": _row(8, 10)})
	var losses: Dictionary = {&"waited_too_long": 2}
	var before: Dictionary = summary.duplicate(true)
	assert_eq(custom.recommendation(summary, losses), &"cook")
	assert_eq(AUTHORED.recommendation(summary, losses), &"keeping_up")
	assert_eq(custom.recommendation(summary, {&"waited_too_long": 1}), &"keeping_up")
	assert_eq(summary, before)
	assert_eq(losses, {&"waited_too_long": 2})
	assert_eq(AUTHORED.high_busy_percent, 90.0, "editing a copied resource cannot rewrite global policy")


func _summary(roles: Dictionary) -> Dictionary:
	return {"day": 1, "open_ticks": 1000, "roles": roles}


func _row(busy: int, total: int) -> Dictionary:
	return {"busy_ticks": busy, "open_ticks": total}
