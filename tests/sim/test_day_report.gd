extends TestCase
## Day report data and standalone UI regressions; no clock or ledger integration.

const REPORT_SCENE: PackedScene = preload("res://src/ui/evening_report.tscn")

var _screen: Control = null
var _host: Control = null
var _next_day_count: int = 0


func after_each() -> void:
	if _host != null:
		_host.free()
		_host = null
		_screen = null
	elif _screen != null:
		_screen.free()
		_screen = null


func test_restaurant_name_survives_json_with_review_context_and_legacy_defaults() -> void:
	var report: DayReport = _full_report()
	report.restaurant_name = "Mama's Diner"
	report.review_cards = [{"stars": 5, "quote": "Lovely soup"}] as Array[Dictionary]
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(report.to_dict())))
	assert_eq(restored.restaurant_name, "Mama's Diner")
	assert_eq(restored.review_cards, report.review_cards)
	var legacy: Dictionary = report.to_dict()
	legacy.erase("restaurant_name")
	assert_eq(DayReport.from_dict(legacy).restaurant_name, MenuSettings.DEFAULT_NAME)
	for invalid: Variant in [17, "Bad\nname", "x".repeat(25), ""]:
		legacy["restaurant_name"] = invalid
		assert_eq(DayReport.from_dict(legacy).restaurant_name, MenuSettings.DEFAULT_NAME)


func test_totals_and_positive_or_negative_profit() -> void:
	var report: DayReport = _full_report()
	assert_eq(report.total_income(), 1250)
	assert_eq(report.total_costs(), 340)
	assert_eq(report.profit(), 910)
	report.costs[&"rent"] = 2000
	assert_eq(report.profit(), -890)


func test_empty_report_has_zero_totals_and_no_leaders() -> void:
	var report: DayReport = DayReport.new()
	assert_eq(report.total_income(), 0)
	assert_eq(report.total_costs(), 0)
	assert_eq(report.profit(), 0)
	assert_eq(report.best_dish(), &"")
	assert_eq(report.top_leave_reason(), &"")


func test_best_dish_uses_count_then_alphabetical_id() -> void:
	var report: DayReport = DayReport.new()
	report.dishes_sold = {&"tomato_soup": 4, &"burger": 4, &"grilled_cheese": 2}
	assert_eq(report.best_dish(), &"burger")
	report.dishes_sold[&"tomato_soup"] = 5
	assert_eq(report.best_dish(), &"tomato_soup")


func test_top_leave_reason_is_deterministic_on_ties() -> void:
	var report: DayReport = DayReport.new()
	report.leave_reasons = {&"waited_too_long": 3, &"no_table": 3}
	assert_eq(report.top_leave_reason(), &"no_table")
	report.leave_reasons[&"waited_too_long"] = 4
	assert_eq(report.top_leave_reason(), &"waited_too_long")


func test_json_round_trip_restores_typed_ids_and_counts() -> void:
	var original: DayReport = _full_report()
	var encoded: String = JSON.stringify(original.to_dict())
	var decoded: Dictionary = JSON.parse_string(encoded)
	var restored: DayReport = DayReport.from_dict(decoded)
	assert_eq(restored.to_dict(), original.to_dict())
	assert_eq(restored.income[&"sale"], 1200)
	assert_eq(restored.cleanliness_label, "Grubby")
	assert_eq(typeof(restored.income.keys()[0]), TYPE_STRING_NAME)
	assert_eq(restored.best_dish(), &"burger")


func test_snapshots_do_not_share_mutable_data() -> void:
	var original: DayReport = _full_report()
	var snapshot: Dictionary = original.to_dict()
	var restored: DayReport = DayReport.from_dict(snapshot)
	snapshot["income"]["sale"] = 0
	snapshot["reviews"].append("A later review")
	assert_eq(original.total_income(), 1250)
	assert_eq(restored.total_income(), 1250)
	assert_eq(original.reviews.size(), 4)
	assert_eq(restored.reviews.size(), 4)


func test_missing_saved_fields_restore_an_empty_report() -> void:
	var report: DayReport = DayReport.from_dict({"day": 9})
	assert_eq(report.day, 9)
	assert_eq(report.profit(), 0)
	assert_true(report.reviews.is_empty())
	assert_true(report.leave_reasons.is_empty())
	assert_eq(report.cleanliness_label, "")
	assert_true(report.review_cards.is_empty())
	assert_almost_eq(report.reputation_before, 3.0)
	assert_almost_eq(report.reputation_after, 3.0)
	assert_eq(report.owner_level_before, 1)
	assert_eq(report.owner_level_after, 1)
	assert_true(report.owner_xp_breakdown.is_empty())
	assert_true(report.owner_unlocks.is_empty())


func test_review_cards_round_trip_without_sim_cause_ids_or_shared_mutation() -> void:
	var report: DayReport = DayReport.new()
	report.review_cards = [{"stars": 4, "quote": "Fast and tasty", "cause": "too_expensive"}]
	report.today_review_average = 4.0
	report.reputation_before = 3.0
	report.reputation_after = 3.2
	var saved: Dictionary = report.to_dict()
	var cards: Array = saved["review_cards"]
	assert_eq(cards.size(), 1)
	assert_eq(cards[0], {"stars": 4, "quote": "Fast and tasty"})
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored: DayReport = DayReport.from_dict(decoded)
	assert_eq(restored.review_cards, cards)
	assert_almost_eq(restored.today_review_average, 4.0)
	assert_almost_eq(restored.reputation_before, 3.0)
	assert_almost_eq(restored.reputation_after, 3.2)
	cards[0]["quote"] = "Modified snapshot"
	assert_eq(report.review_cards[0]["quote"], "Fast and tasty")
	assert_eq(restored.review_cards[0]["quote"], "Fast and tasty")


func test_owner_progress_report_round_trip_detaches_breakdown_and_unlock_names() -> void:
	var report: DayReport = DayReport.new()
	report.owner_level_before = 1
	report.owner_level_after = 2
	report.owner_xp_breakdown = {"happy_xp": 8, "profit_xp": 5, "review_xp": 3,
		"milestone_xp": 4, "total_xp": 20, "internal_cause": 99}
	report.owner_unlocks = ["Tomato melt", "Potted plant"]
	report.owner_tips = ["Groups of two now visit."]
	var snapshot: Dictionary = report.to_dict()
	assert_false(snapshot["owner_xp_breakdown"].has("internal_cause"))
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	var restored: DayReport = DayReport.from_dict(decoded)
	assert_eq(restored.to_dict(), snapshot)
	snapshot["owner_xp_breakdown"]["happy_xp"] = 0
	snapshot["owner_unlocks"][0] = "Changed"
	assert_eq(restored.owner_xp_breakdown["milestone_xp"], 4)
	assert_eq(report.owner_xp_breakdown["happy_xp"], 8)
	assert_eq(restored.owner_xp_breakdown["happy_xp"], 8)
	assert_eq(report.owner_unlocks[0], "Tomato melt")
	assert_eq(restored.owner_unlocks[0], "Tomato melt")
	snapshot["owner_tips"][0] = "Changed"
	assert_eq(restored.owner_tips, ["Groups of two now visit."] as Array[String])


func test_milestone_rows_round_trip_only_player_facing_fields() -> void:
	var report: DayReport = DayReport.new()
	report.milestones_reached = [
		{"title": "Full house, no panic", "reward_xp": 25, "reward_cash": 40,
			"id": "first_rush", "condition": "served_today"},
		{"title": "Word gets around", "reward_xp": 30, "reward_cash": 20},
		{"title": "  ", "reward_xp": 25, "reward_cash": 40},
		{"title": "Negative", "reward_xp": -1, "reward_cash": 1},
		{"title": "Fractional", "reward_xp": 1.5, "reward_cash": 1},
		{"title": "Too large", "reward_xp": 1000001, "reward_cash": 1},
		{"title": "NaN", "reward_xp": NAN, "reward_cash": 1},
		{"title": "Infinite", "reward_xp": 1, "reward_cash": INF},
		{"title": "Boolean", "reward_xp": true, "reward_cash": 1},
		{"title": "Dictionary", "reward_xp": {}, "reward_cash": 1},
		{"title": 42, "reward_xp": 1, "reward_cash": 1},
	] as Array[Dictionary]
	var snapshot: Dictionary = report.to_dict()
	assert_eq(snapshot["milestones_reached"], [
		{"title": "Full house, no panic", "reward_xp": 25, "reward_cash": 40},
		{"title": "Word gets around", "reward_xp": 30, "reward_cash": 20},
	] as Array[Dictionary])
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(snapshot)))
	assert_eq(restored.milestones_reached, snapshot["milestones_reached"])
	snapshot["milestones_reached"][0]["title"] = "Changed snapshot"
	assert_eq(restored.milestones_reached[0]["title"], "Full house, no panic")
	assert_true(DayReport.from_dict({}).milestones_reached.is_empty())
	assert_eq(report.milestones_reached.size(), 11, "sanitizing output never edits supplied report rows")


func test_optional_milestone_xp_rejects_malformed_values_without_casting() -> void:
	for value: Variant in [NAN, INF, -1, 1.5, 1000000001, true, {}, "25"]:
		var report: DayReport = DayReport.from_dict({"owner_xp_breakdown": {"milestone_xp": value}})
		assert_false(report.owner_xp_breakdown.has("milestone_xp"),
			"invalid milestone XP is omitted: %s" % [value])
	assert_eq(DayReport.from_dict({"owner_xp_breakdown": {"milestone_xp": 0}})
		.owner_xp_breakdown["milestone_xp"], 0)
	assert_eq(DayReport.from_dict({"owner_xp_breakdown":
		{"milestone_xp": OwnerProgress.MAX_TOTAL_XP}}).owner_xp_breakdown["milestone_xp"],
		OwnerProgress.MAX_TOTAL_XP)


func test_milestone_bonus_stays_in_cash_but_not_operating_profit() -> void:
	var report: DayReport = DayReport.new()
	report.income = {Ledger.SALE: 100, Ledger.MILESTONE_BONUS: 25}
	report.costs = {Ledger.RENT: 120}
	assert_eq(report.total_income(), 125)
	assert_eq(report.profit(), 5, "the milestone award remains part of cash movement")
	assert_eq(report.operating_profit(), -20, "a one-off goal reward is not shop operations")
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(report.to_dict())))
	assert_eq(restored.profit(), 5)
	assert_eq(restored.operating_profit(), -20)


func test_ui_review_summary_and_star_quotes_then_clear() -> void:
	_screen = REPORT_SCENE.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.review_cards = [
		{"stars": 5, "quote": "Wonderful soup"},
		{"stars": 4, "quote": "Nice and cosy"},
		{"stars": 3, "quote": "Okay lunch"},
		{"stars": 2, "quote": "Fourth line is hidden"},
	]
	report.today_review_average = 3.5
	report.reputation_before = 3.2
	report.reputation_after = 3.4
	_screen.call("show_report", report)
	assert_eq((_screen.get_node("%ReviewStats") as Label).text, "Today's reviews: 3.5 stars")
	assert_eq((_screen.get_node("%Reputation") as Label).text, "Reputation: 3.2 to 3.4 stars")
	var lines: Node = _screen.get_node("%ReviewRows")
	assert_eq(lines.get_child_count(), 3)
	assert_eq((lines.get_child(0) as Label).text, '5 stars - "Wonderful soup"')
	assert_eq((lines.get_child(2) as Label).text, '3 stars - "Okay lunch"')
	_screen.call("show_report", DayReport.new())
	assert_eq((_screen.get_node("%ReviewStats") as Label).text, "Today's reviews: none")
	assert_eq((_screen.get_node("%Reputation") as Label).text, "Reputation: 3.0 to 3.0 stars")
	assert_eq(lines.get_child_count(), 1)
	assert_eq((lines.get_child(0) as Label).text, "No reviews today")


func test_ui_owner_xp_breakdown_level_up_and_unlocks_preserve_review_cards() -> void:
	_screen = REPORT_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.review_cards = [{"stars": 5, "quote": "Lovely meal"}]
	report.owner_level_before = 1
	report.owner_level_after = 2
	report.owner_xp_breakdown = {"happy_xp": 8, "profit_xp": 5, "review_xp": 3, "total_xp": 16}
	report.owner_unlocks = ["Tomato melt", "Potted plant"]
	_screen.call("show_report", report)
	assert_eq((_screen.get_node("%OwnerLevel") as Label).text, "Owner level 2")
	assert_true((_screen.get_node("%OwnerLevelUp") as Label).visible)
	assert_eq((_screen.get_node("%OwnerLevelUp") as Label).text, "Level up! Level 2 reached")
	var rows: Node = _screen.get_node("%OwnerXPRows")
	assert_eq(rows.get_child_count(), 8)
	assert_eq((rows.get_child(0) as Label).text, "Happy guests")
	assert_eq((rows.get_child(1) as Label).text, "+8 XP")
	assert_eq((rows.get_child(6) as Label).text, "Total")
	assert_eq((rows.get_child(7) as Label).text, "+16 XP")
	assert_eq((_screen.get_node("%OwnerUnlocks") as Label).text, "Unlocked: Tomato melt, Potted plant")
	assert_eq((_screen.get_node("%ReviewRows").get_child(0) as Label).text, '5 stars - "Lovely meal"')
	report.owner_tips = ["Groups of two now visit; four-seat tables help."]
	_screen.call("show_report", report)
	assert_eq((_screen.get_node("%OwnerUnlocks") as Label).text,
		"Unlocked: Tomato melt, Potted plant\nGroups of two now visit; four-seat tables help.")
	report.owner_unlocks = []
	_screen.call("show_report", report)
	assert_true((_screen.get_node("%OwnerUnlocks") as Label).visible, "a tip alone still shows")
	assert_eq((_screen.get_node("%OwnerUnlocks") as Label).text, "Groups of two now visit; four-seat tables help.")
	_screen.call("show_report", DayReport.new())
	assert_eq((_screen.get_node("%OwnerLevel") as Label).text, "Owner level 1")
	assert_false((_screen.get_node("%OwnerLevelUp") as Label).visible)
	assert_false((_screen.get_node("%OwnerUnlocks") as Label).visible)
	assert_eq((rows.get_child(0) as Label).text, "No owner XP recorded")
	assert_eq((_screen.get_node("%ReviewRows").get_child(0) as Label).text, "No reviews today")


func test_ui_optional_milestone_xp_and_award_rows_render_then_clear() -> void:
	_screen = REPORT_SCENE.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.income = {Ledger.MILESTONE_BONUS: 40}
	report.owner_xp_breakdown = {"happy_xp": 1, "profit_xp": 2, "review_xp": 3,
		"milestone_xp": 55, "total_xp": 61}
	report.milestones_reached = [
		{"title": "First busy evening", "reward_xp": 25, "reward_cash": 40},
		{"title": "Regulars return", "reward_xp": 30, "reward_cash": 0},
	] as Array[Dictionary]
	_screen.call("show_report", report)
	var heading: Label = _screen.get_node("%MilestoneHeading") as Label
	var rows: VBoxContainer = _screen.get_node("%MilestoneRows") as VBoxContainer
	var income: GridContainer = _screen.get_node("%IncomeRows") as GridContainer
	assert_true(heading.visible)
	assert_eq(heading.text, "Milestone reached!")
	assert_eq(rows.get_child_count(), 2)
	assert_eq((rows.get_child(0).get_child(0) as Label).text, "First busy evening")
	assert_eq((rows.get_child(0).get_child(1) as Label).text, "Reward: +25 XP, $40")
	assert_eq((rows.get_child(1).get_child(0) as Label).text, "Regulars return")
	assert_eq((rows.get_child(1).get_child(1) as Label).text, "Reward: +30 XP, $0")
	assert_eq((income.get_child(0) as Label).text, "Milestone bonus")
	assert_eq((income.get_child(1) as Label).text, "$40")
	var xp_rows: GridContainer = _screen.get_node("%OwnerXPRows") as GridContainer
	assert_eq((xp_rows.get_child(6) as Label).text, "Career goals")
	assert_eq((xp_rows.get_child(7) as Label).text, "+55 XP")
	assert_eq((xp_rows.get_child(8) as Label).text, "Total")
	assert_eq((xp_rows.get_child(9) as Label).text, "+61 XP")
	_screen.call("show_report", report)
	assert_eq(rows.get_child_count(), 2, "reopening a report replaces rows instead of duplicating them")
	var empty: DayReport = DayReport.new()
	empty.owner_xp_breakdown = {"happy_xp": 1, "profit_xp": 2, "review_xp": 3, "total_xp": 6}
	_screen.call("show_report", empty)
	assert_false(heading.visible)
	assert_false(rows.visible)
	assert_eq(rows.get_child_count(), 0)
	xp_rows = _screen.get_node("%OwnerXPRows") as GridContainer
	assert_eq(xp_rows.get_child_count(), 8, "zero milestone XP preserves the existing breakdown rows")
	assert_eq((xp_rows.get_child(6) as Label).text, "Total")
	assert_eq((xp_rows.get_child(7) as Label).text, "+6 XP")
	assert_eq((income.get_child(0) as Label).text, "No income today")


func test_ui_report_skips_malformed_milestones_and_milestone_xp() -> void:
	_screen = REPORT_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.milestones_reached = [
		{"title": "Bad cash", "reward_xp": 5, "reward_cash": NAN},
		{"title": "Valid", "reward_xp": 5, "reward_cash": 5},
	] as Array[Dictionary]
	report.owner_xp_breakdown = {"happy_xp": 1, "milestone_xp": {"unexpected": true}, "total_xp": 1}
	_screen.call("show_report", report)
	var rows: VBoxContainer = _screen.get_node("%MilestoneRows") as VBoxContainer
	assert_eq(rows.get_child_count(), 1)
	assert_eq((rows.get_child(0).get_child(0) as Label).text, "Valid")
	assert_eq(DayReport.public_milestones(report.milestones_reached).size(), 1)
	assert_false(report.to_dict()["owner_xp_breakdown"].has("milestone_xp"))
	var xp_rows: GridContainer = _screen.get_node("%OwnerXPRows") as GridContainer
	for child: Node in xp_rows.get_children():
		assert_false(child is Label and (child as Label).text == "Career goals")


func test_first_three_review_quotes_fit_without_scrolling_at_both_capture_sizes() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_host = Control.new()
	_host.size = Vector2(1600.0, 900.0)
	tree.root.add_child(_host)
	_screen = REPORT_SCENE.instantiate()
	_host.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.income = {&"sale": 1200, &"tip": 50}
	report.costs = {&"ingredients": 140, &"rent": 200, &"wages": 300}
	report.dishes_sold = {&"tomato_soup": 2, &"burger": 8}
	report.customers_served = 12
	report.customers_lost = 4
	report.leave_reasons = {&"no_table": 1, &"waited_too_long": 3}
	report.cleanliness_label = "Grubby"
	report.review_cards = [
		{"stars": 5, "quote": "Warm room, good food, happy me."},
		{"stars": 4, "quote": "I aged a little waiting for lunch. Worth a bite, though."},
		{"stars": 3, "quote": "A little mop magic would help this place."},
	]
	report.today_review_average = 4.0
	report.reputation_before = 3.0
	report.reputation_after = 3.2
	report.owner_level_before = 1
	report.owner_level_after = 2
	report.owner_unlocks = ["Potted plant", "Tomato melt recipe"]
	_screen.call("show_report", report)
	var scroll: ScrollContainer = _screen.get_node("Panel/Scroll") as ScrollContainer
	var rows: VBoxContainer = _screen.get_node("%ReviewRows") as VBoxContainer
	var profit: Label = _screen.get_node("%Profit") as Label
	var callout: HBoxContainer = _screen.get_node("Panel/Scroll/Content/LevelUpCallout") as HBoxContainer
	var banner: Label = _screen.get_node("%OwnerLevelUp") as Label
	var unlocks: Label = _screen.get_node("%OwnerUnlocks") as Label
	var finances: HBoxContainer = _screen.get_node("Panel/Scroll/Content/Finances") as HBoxContainer
	for bounds: Vector2 in [Vector2(1600.0, 900.0), Vector2(1280.0, 720.0)]:
		_host.size = bounds
		scroll.scroll_vertical = 0
		await tree.process_frame
		await tree.process_frame
		assert_eq(_screen.size, bounds)
		assert_eq(scroll.scroll_vertical, 0)
		assert_eq(rows.get_child_count(), 3)
		var viewport: Rect2 = scroll.get_global_rect()
		assert_true(callout.visible and banner.visible and unlocks.visible)
		assert_eq(banner.text, "Level up! Level 2 reached")
		assert_eq(unlocks.text, "Unlocked: Potted plant, Tomato melt recipe")
		assert_true(callout.get_global_rect().position.y >= profit.get_global_rect().end.y - 1.0)
		assert_true(callout.get_global_rect().end.y <= finances.get_global_rect().position.y + 1.0)
		for label: Label in [banner, unlocks]:
			var label_rect: Rect2 = label.get_global_rect()
			assert_true(label_rect.size.x > 0.0 and label_rect.size.y > 0.0)
			assert_true(label_rect.position.x >= viewport.position.x - 1.0
				and label_rect.end.x <= viewport.end.x + 1.0
				and label_rect.position.y >= viewport.position.y - 1.0
				and label_rect.end.y <= viewport.end.y + 1.0,
				"the level-up payoff fits the unscrolled %dx%d report" % [int(bounds.x), int(bounds.y)])
		for index: int in range(3):
			var card: Dictionary = report.review_cards[index]
			var native: Label = rows.get_child(index) as Label
			assert_eq(native.text, '%d stars - "%s"' % [card["stars"], card["quote"]])
			assert_true(native.is_visible_in_tree())
			var rect: Rect2 = native.get_global_rect()
			assert_true(rect.size.x > 0.0 and rect.size.y > 0.0)
			assert_true(rect.position.x >= viewport.position.x - 1.0
				and rect.end.x <= viewport.end.x + 1.0
				and rect.position.y >= viewport.position.y - 1.0
				and rect.end.y <= viewport.end.y + 1.0,
				"review %d fits the unscrolled %dx%d report" % [index, int(bounds.x), int(bounds.y)])


func test_two_milestones_and_three_quotes_fit_native_1600x900_report() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_host = Control.new()
	_host.size = Vector2(1600.0, 900.0)
	tree.root.add_child(_host)
	_screen = REPORT_SCENE.instantiate()
	_host.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.milestones_reached = [
		{"title": "A full dining room and a very good evening", "reward_xp": 25, "reward_cash": 40},
		{"title": "Regulars came back for seconds", "reward_xp": 30, "reward_cash": 20},
	] as Array[Dictionary]
	report.review_cards = [
		{"stars": 5, "quote": "Warm room, good food, happy me."},
		{"stars": 4, "quote": "I aged a little waiting for lunch. Worth a bite, though."},
		{"stars": 3, "quote": "A little mop magic would help this place."},
	]
	report.today_review_average = 4.0
	_screen.call("show_report", report)
	await tree.process_frame
	await tree.process_frame
	var scroll: ScrollContainer = _screen.get_node("Panel/Scroll") as ScrollContainer
	var viewport: Rect2 = scroll.get_global_rect()
	assert_eq(_screen.size, Vector2(1600.0, 900.0))
	assert_eq(scroll.scroll_vertical, 0)
	# The report footer may scroll. The payoff and complete quotes below must
	# fit the actual initial viewport without scrolling to reach them.
	var milestone_rows: VBoxContainer = _screen.get_node("%MilestoneRows") as VBoxContainer
	var review_rows: VBoxContainer = _screen.get_node("%ReviewRows") as VBoxContainer
	assert_true((_screen.get_node("%MilestoneHeading") as Label).is_visible_in_tree())
	assert_eq(milestone_rows.get_child_count(), 2)
	assert_eq(review_rows.get_child_count(), 3)
	for index: int in range(2):
		var row: HBoxContainer = milestone_rows.get_child(index) as HBoxContainer
		assert_eq((row.get_child(0) as Label).text, report.milestones_reached[index]["title"])
		assert_eq((row.get_child(1) as Label).text,
			"Reward: +%d XP, $%d" % [report.milestones_reached[index]["reward_xp"],
				report.milestones_reached[index]["reward_cash"]])
		for label: Label in [row.get_child(0) as Label, row.get_child(1) as Label]:
			var rect: Rect2 = label.get_global_rect()
			assert_true(rect.size.x > 0.0 and rect.size.y > 0.0)
			assert_true(viewport.grow(0.5).encloses(rect), "both milestone labels fit the actual report viewport")
	for index: int in range(3):
		var card: Dictionary = report.review_cards[index]
		var quote: Label = review_rows.get_child(index) as Label
		assert_eq(quote.text, '%d stars - "%s"' % [card["stars"], card["quote"]])
		assert_true(quote.is_visible_in_tree())
		assert_true(viewport.grow(0.5).encloses(quote.get_global_rect()),
			"all three complete review quotes remain visible with both milestone rows")


func test_ui_full_report_then_empty_clears_every_section() -> void:
	_screen = REPORT_SCENE.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_screen)
	_screen.call("show_report", _full_report())
	assert_eq((_screen.get_node("%Header") as Label).text, "Day 3: Closed")
	assert_eq((_screen.get_node("%Profit") as Label).text, "$910 operating profit")
	assert_eq((_screen.get_node("%Guests") as Label).text, "12 served  /  4 lost")
	assert_eq((_screen.get_node("%Cleanliness") as Label).text, "Cleanliness: Grubby")
	assert_true((_screen.get_node("%Cleanliness") as Label).visible)
	assert_almost_eq((_screen.get_node("%GuestBar") as ProgressBar).value, 12.0)
	assert_almost_eq((_screen.get_node("%GuestBar") as ProgressBar).max_value, 16.0)
	assert_eq(_screen.get_node("%ReviewRows").get_child_count(), 3)
	assert_eq((_screen.get_node("%ReasonRows").get_child(0) as Label).text, "Waited too long")
	assert_eq((_screen.get_node("%DishRows").get_child(0) as Label).text, "Burger (best seller)")
	_screen.call("show_report", DayReport.new())
	assert_eq(_screen.get_node("%IncomeRows").get_child_count(), 2)
	assert_eq((_screen.get_node("%IncomeRows").get_child(0) as Label).text, "No income today")
	assert_eq((_screen.get_node("%CostRows").get_child(0) as Label).text, "No costs today")
	assert_eq((_screen.get_node("%DishRows").get_child(0) as Label).text, "No dishes sold today")
	assert_eq((_screen.get_node("%Guests") as Label).text, "No guests visited today")
	assert_eq((_screen.get_node("%Cleanliness") as Label).text, "")
	assert_false((_screen.get_node("%Cleanliness") as Label).visible)
	assert_almost_eq((_screen.get_node("%GuestBar") as ProgressBar).value, 0.0)
	assert_eq((_screen.get_node("%ReasonRows").get_child(0) as Label).text, "No unhappy departures today")
	assert_eq(_screen.get_node("%ReviewRows").get_child_count(), 1)


func test_ui_cleanliness_word_updates_without_displacing_review_quotes() -> void:
	_screen = REPORT_SCENE.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.cleanliness_label = "Spotless"
	report.review_cards = [{"stars": 4, "quote": "Lovely soup"}]
	_screen.call("show_report", report)
	assert_eq((_screen.get_node("%Guests") as Label).text, "No guests visited today")
	assert_eq((_screen.get_node("%Cleanliness") as Label).text, "Cleanliness: Spotless")
	assert_true((_screen.get_node("%Cleanliness") as Label).visible)
	assert_eq((_screen.get_node("%ReviewRows") as VBoxContainer).get_child_count(), 1)
	report.cleanliness_label = "A bit messy"
	_screen.call("show_report", report)
	assert_eq((_screen.get_node("%Cleanliness") as Label).text, "Cleanliness: A bit messy")
	assert_eq(((_screen.get_node("%ReviewRows") as VBoxContainer).get_child(0) as Label).text,
		'4 stars - "Lovely soup"')
	_screen.call("show_report", DayReport.new())
	assert_eq((_screen.get_node("%Guests") as Label).text, "No guests visited today")
	assert_eq((_screen.get_node("%Cleanliness") as Label).text, "")
	assert_false((_screen.get_node("%Cleanliness") as Label).visible)


func test_ui_loss_and_next_day_signal_without_clock_integration() -> void:
	_screen = REPORT_SCENE.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.costs = {&"rent": 1234}
	_screen.call("show_report", report)
	assert_eq((_screen.get_node("%Profit") as Label).text, "-$1,234 operating profit")
	_screen.connect("next_day_pressed", _on_next_day)
	(_screen.get_node("%NextDay") as Button).pressed.emit()
	assert_eq(_next_day_count, 1)
	assert_not_null(_screen.theme)


func test_ui_report_before_ready_is_preserved_and_connects_once() -> void:
	_screen = REPORT_SCENE.instantiate()
	_screen.call("show_report", _full_report())
	assert_eq((_screen.get_node("%Header") as Label).text, "Day 3: Closed")
	_screen.call("_ready")
	_screen.call("_ready")
	assert_eq((_screen.get_node("%Header") as Label).text, "Day 3: Closed")
	assert_eq((_screen.get_node("%Profit") as Label).text, "$910 operating profit")
	_screen.connect("next_day_pressed", _on_next_day)
	(_screen.get_node("%NextDay") as Button).pressed.emit()
	assert_eq(_next_day_count, 1)


func test_first_loan_notice_snapshot_is_boolean_and_older_reports_default_hidden() -> void:
	var report: DayReport = DayReport.new()
	report.loan_first_advance = true
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(report.to_dict()))
	assert_true(DayReport.from_dict(decoded).loan_first_advance)
	assert_false(DayReport.from_dict({}).loan_first_advance)
	assert_false(DayReport.from_dict({"loan_first_advance": "true"}).loan_first_advance)


func test_native_report_maps_bank_lines_and_wraps_first_notice_then_clears_it() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_host = Control.new()
	_host.size = Vector2(1600.0, 900.0)
	tree.root.add_child(_host)
	_screen = REPORT_SCENE.instantiate()
	_host.add_child(_screen)
	var report: DayReport = DayReport.new()
	report.income = {Ledger.BANK_LOAN: 150}
	report.costs = {Ledger.LOAN_INTEREST: 5, Ledger.LOAN_REPAYMENT: 50}
	report.loan_first_advance = true
	_screen.call("show_report", report)
	var income: GridContainer = _screen.get_node("%IncomeRows") as GridContainer
	var costs: GridContainer = _screen.get_node("%CostRows") as GridContainer
	assert_eq((income.get_child(0) as Label).text, "Bank loan")
	assert_eq((income.get_child(1) as Label).text, "$150")
	assert_eq((costs.get_child(0) as Label).text, "Loan interest")
	assert_eq((costs.get_child(1) as Label).text, "$5")
	assert_eq((costs.get_child(2) as Label).text, "Loan repayment")
	assert_eq((costs.get_child(3) as Label).text, "$50")
	var notice: Label = _screen.get_node("%LoanNotice") as Label
	assert_eq(report.profit(), 95, "all financing movements remain in the cash result")
	assert_eq((_screen.get_node("%Profit") as Label).text, "$0 operating profit")
	assert_eq(notice.text, "The bank covered your shortfall. It'll take a share of your profits until it's paid back.")
	for bounds: Vector2 in [Vector2(1600.0, 900.0), Vector2(1280.0, 720.0)]:
		_host.size = bounds
		await tree.process_frame
		await tree.process_frame
		var scroll: ScrollContainer = _screen.get_node("Panel/Scroll") as ScrollContainer
		var viewport: Rect2 = scroll.get_global_rect()
		assert_true(notice.is_visible_in_tree())
		assert_true(viewport.grow(0.5).encloses(notice.get_global_rect()), "the introduction fits the unscrolled report")
		assert_true(notice.size.y >= notice.get_combined_minimum_size().y - 0.5)
		assert_true(notice.global_position.y >= costs.get_global_rect().end.y)
	_screen.call("show_report", DayReport.new())
	assert_false(notice.visible)
	assert_eq(notice.text, "")
	assert_eq((income.get_child(0) as Label).text, "No income today")
	assert_eq((costs.get_child(0) as Label).text, "No costs today")


func test_operating_profit_excludes_all_financing_without_changing_cash_totals() -> void:
	var report: DayReport = DayReport.new()
	report.income = {Ledger.SALE: 40, Ledger.BANK_LOAN: 100}
	report.costs = {Ledger.RENT: 80, Ledger.LOAN_INTEREST: 5, Ledger.LOAN_REPAYMENT: 10}
	assert_eq(report.total_income(), 140)
	assert_eq(report.total_costs(), 95)
	assert_eq(report.profit(), 45, "financial cash movement retains every bank line")
	assert_eq(report.operating_profit(), -40, "a bank advance cannot turn an operating loss into profit")
	report.income = {Ledger.SALE: 100}
	report.costs = {Ledger.RENT: 20, Ledger.LOAN_INTEREST: 5, Ledger.LOAN_REPAYMENT: 90}
	assert_eq(report.profit(), -15)
	assert_eq(report.operating_profit(), 80, "interest and repayment cannot lower operating performance")


func test_historical_report_decoding_keeps_cash_profit_and_derives_operating_profit() -> void:
	var saved: Dictionary = {"day": 4, "income": {"sale": 40, "bank_loan": 100},
		"costs": {"rent": 80, "loan_interest": 5, "loan_repayment": 10}}
	var report: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_eq(report.profit(), 45)
	assert_eq(report.operating_profit(), -40)
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(report.to_dict())))
	assert_eq(restored.to_dict(), report.to_dict())
	assert_eq(restored.profit(), 45)
	assert_eq(restored.operating_profit(), -40)
	var older: DayReport = DayReport.from_dict({"income": {"sale": 40}, "costs": {"rent": 80}})
	assert_eq(older.operating_profit(), older.profit(), "older reports without financing keep their result")


func test_native_headline_and_color_use_operating_profit_while_bank_rows_remain() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_screen = REPORT_SCENE.instantiate()
	tree.root.add_child(_screen)
	var report: DayReport = DayReport.from_dict({"income": {"sale": 40, "bank_loan": 100},
		"costs": {"rent": 80, "loan_interest": 5, "loan_repayment": 10}})
	_screen.call("show_report", report)
	var headline: Label = _screen.get_node("%Profit") as Label
	assert_eq(report.profit(), 45)
	assert_eq(headline.text, "-$40 operating profit")
	assert_eq(headline.get_theme_color("font_color"), Color("a83e35"))
	assert_eq((_screen.get_node("%IncomeRows").get_child(0) as Label).text, "Bank loan")
	assert_eq((_screen.get_node("%CostRows").get_child(0) as Label).text, "Loan interest")
	assert_eq((_screen.get_node("%CostRows").get_child(2) as Label).text, "Loan repayment")
	report = DayReport.from_dict({"income": {"sale": 100},
		"costs": {"rent": 20, "loan_interest": 5, "loan_repayment": 90}})
	_screen.call("show_report", report)
	assert_eq(report.profit(), -15)
	assert_eq(headline.text, "$80 operating profit")
	assert_eq(headline.get_theme_color("font_color"), Color("38764b"))


func _full_report() -> DayReport:
	var report: DayReport = DayReport.new()
	report.day = 3
	report.income = {&"sale": 1200, &"tip": 50}
	report.costs = {&"ingredients": 140, &"rent": 200}
	report.dishes_sold = {&"tomato_soup": 2, &"burger": 8}
	report.customers_served = 12
	report.customers_lost = 4
	report.leave_reasons = {&"no_table": 1, &"waited_too_long": 3}
	report.reviews = ["Lovely soup", "Cosy place", "Great burger", "Fourth quote is hidden"]
	report.cleanliness_label = "Grubby"
	return report


func _on_next_day() -> void:
	_next_day_count += 1
