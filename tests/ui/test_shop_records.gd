extends TestCase

const GOALS: PackedScene = preload("res://src/ui/goals_panel.tscn")
const REPORT: PackedScene = preload("res://src/ui/evening_report.tscn")


func test_empty_records_and_unknown_profit_have_plain_distinct_messages() -> void:
	var records: ShopRecords = ShopRecords.new()
	assert_eq(ShopRecordsText.rows(records.snapshot()),
		["Finish a service day to start your records."] as Array[String])
	records.record(DayReport.new())
	assert_true(ShopRecordsText.rows(records.snapshot()).has("Best operating profit: not recorded yet"))
	assert_true(ShopRecordsText.rows(records.snapshot()).has("Longest run without angry guests: 1 day (day 1)"))
	var next: DayReport = DayReport.new()
	next.day = 2
	records.record(next)
	assert_true(ShopRecordsText.rows(records.snapshot()).has("Longest run without angry guests: 2 days (day 2)"))


func test_most_sold_ties_use_stable_ids_but_only_display_names_reach_players() -> void:
	var content: ContentDB = ContentDB.new()
	var alpha: RecipeDef = RecipeDef.new()
	alpha.id = &"alpha_private_id"
	alpha.display_name = "Tomato soup"
	var zulu: RecipeDef = RecipeDef.new()
	zulu.id = &"zulu_private_id"
	zulu.display_name = "Grilled cheese"
	content._recipes[alpha.id] = alpha
	content._recipes[zulu.id] = zulu
	var day: DayReport = DayReport.new()
	day.dishes_sold = {zulu.id: 3, alpha.id: 3, &"former_private_id": 2}
	var records: ShopRecords = ShopRecords.new()
	records.record(day)
	var lines: Array[String] = ShopRecordsText.rows(records.snapshot(), content)
	assert_true(lines.has("Most-sold dish ever: Tomato soup (3)"))
	assert_true(lines.has("Tomato soup: 3"))
	assert_true(lines.has("Grilled cheese: 3"))
	assert_true(lines.has("Former dish: 2"))
	assert_false("\n".join(PackedStringArray(lines)).contains("private_id"))
	assert_eq(records.snapshot()["dishes"][&"former_private_id"], 2, "missing content keeps its lifetime count")


func test_record_lines_survive_report_roundtrip_and_clear_on_an_old_report() -> void:
	var records: ShopRecords = ShopRecords.new()
	var first: DayReport = DayReport.new()
	first.customers_served = 10
	assert_eq(records.record(first), [] as Array[StringName], "the first recorded day is not news")
	var day: DayReport = DayReport.new()
	day.day = 2
	day.customers_served = 61
	var beaten: Array[StringName] = records.record(day)
	day.record_lines = ShopRecordsText.new_record_lines(records.snapshot(), beaten)
	assert_true(day.record_lines.has("New record: most guests in a day (61)!"))
	assert_true(day.record_lines.has("New record: longest run without angry guests (2 days)!"))
	var next: DayReport = DayReport.new()
	next.day = 3
	var next_beaten: Array[StringName] = records.record(next)
	assert_true(ShopRecordsText.new_record_lines(records.snapshot(), next_beaten).has(
		"New record: longest run without angry guests (3 days)!"))
	var restored: DayReport = DayReport.from_dict(JSON.parse_string(JSON.stringify(day.to_dict())))
	assert_eq(restored.record_lines, day.record_lines)
	var panel: Control = REPORT.instantiate() as Control
	panel.call("show_report", restored)
	var notices: Label = panel.get_node("%RecordNotices") as Label
	assert_true(notices.visible)
	assert_eq(notices.text, "\n".join(PackedStringArray(day.record_lines)))
	panel.call("show_report", DayReport.from_dict({}))
	assert_false(notices.visible)
	assert_eq(notices.text, "")
	assert_false(DayReport.new().to_dict().has("record_lines"))
	panel.free()


func test_zero_first_bests_are_kept_quietly_and_a_loss_is_never_celebrated() -> void:
	var records: ShopRecords = ShopRecords.new()
	var day: DayReport = DayReport.new()
	day.reputation_after = 0.0
	day.leave_reasons = {&"waited_too_long": 1}
	day.stock_values_recorded = true
	day.food_cost_recorded = true
	day.costs[Ledger.RENT] = 5
	assert_eq(records.record(day), [] as Array[StringName], "the first day sets bests quietly")
	var worse: DayReport = DayReport.new()
	worse.day = 2
	worse.stock_values_recorded = true
	worse.food_cost_recorded = true
	worse.costs[Ledger.RENT] = 2
	worse.reputation_after = 0.0
	worse.leave_reasons = {&"waited_too_long": 1}
	var beaten: Array[StringName] = records.record(worse)
	assert_true(beaten.has(&"profit"), "a smaller loss is still the best day so far")
	assert_eq(ShopRecordsText.new_record_lines(records.snapshot(), beaten), [] as Array[String],
		"a loss is never announced as a profit record")
	assert_eq(records.snapshot()["bests"][&"guests"], {"value": 0, "day": 1})
	assert_true(ShopRecordsText.rows(records.snapshot()).has("Longest run without angry guests: 0 days (day 1)"))


func test_goals_records_are_detached_readonly_rows_and_remain_without_a_goal_catalogue() -> void:
	var panel: GoalsPanel = GOALS.instantiate() as GoalsPanel
	var lines: Array[String] = ["Total guests served: 61", "Most-sold dish ever: Tomato soup (40)"]
	panel.set_records(lines)
	lines.clear()
	panel.set_goals(null, [] as Array[StringName], {} as Dictionary[StringName, float], 1)
	var rows: VBoxContainer = panel.get_node("%RecordsRows") as VBoxContainer
	assert_eq(rows.get_child_count(), 2)
	assert_eq((rows.get_child(0) as Label).text, "Total guests served: 61")
	assert_eq((rows.get_child(1) as Label).text, "Most-sold dish ever: Tomato soup (40)")
	for child: Node in rows.get_children():
		assert_eq((child as Label).autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
		assert_eq((child as Label).mouse_filter, Control.MOUSE_FILTER_IGNORE)
	panel.free()


func test_reputation_best_survives_a_save_without_a_false_record() -> void:
	var records: ShopRecords = ShopRecords.new()
	var day: DayReport = DayReport.new()
	day.reputation_after = 10.0 / 3.0
	records.record(day)
	var restored: ShopRecords = ShopRecords.new()
	assert_true(restored.restore(JSON.parse_string(JSON.stringify(records.capture()))))
	var same: DayReport = DayReport.new()
	same.day = 2
	same.reputation_after = 10.0 / 3.0
	assert_false(restored.record(same).has(&"reputation"), "an equal reputation after a reload is not a record")
	assert_eq(restored.snapshot()["bests"][&"reputation"]["day"], 1)
