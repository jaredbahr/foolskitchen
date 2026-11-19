extends TestCase

const DISH: String = "Tomato Soup"


func test_each_situation_draws_from_its_authored_group() -> void:
	var quiet: DayReport = DayReport.new()
	quiet.customers_served = 7
	var record: DayReport = DayReport.new()
	record.record_lines = ["Most meals served"]
	var loss: DayReport = DayReport.new()
	loss.costs[Ledger.RENT] = 23
	var walkouts: DayReport = DayReport.new()
	walkouts.customers_lost = 4
	var review: DayReport = DayReport.new()
	review.review_cards = [{"stars": 5}]
	var inspection: DayReport = DayReport.new()
	inspection.inspection_lines = ["Inspection grade: B"]

	_assert_group(1, null, &"first_day", "0", "$0")
	_assert_group(2, quiet, &"quiet", "7", "$0")
	_assert_group(2, record, &"record", "0", "$0")
	_assert_group(2, loss, &"loss", "0", "-$23")
	_assert_group(2, walkouts, &"walkouts", "4", "$0")
	_assert_group(2, review, &"review", "0", "$0")
	_assert_group(2, inspection, &"inspection", "0", "$0")


func test_good_news_leads_and_a_full_house_is_not_a_walkout() -> void:
	var tier: DayReport = DayReport.new()
	tier.career_tier_line = "Your restaurant reached Tier 2!"
	tier.record_lines = ["Most guests"]
	tier.owner_level_before = 1
	tier.owner_level_after = 3
	var level: DayReport = DayReport.new()
	level.owner_level_before = 2
	level.owner_level_after = 3
	level.record_lines = ["Most guests"]
	var regular: DayReport = DayReport.new()
	regular.regulars_lines = ["Came: Felix", "New regulars: Mina"]
	regular.customers_lost = 9
	var came_only: DayReport = DayReport.new()
	came_only.regulars_lines = ["Came: Felix"]
	came_only.customers_served = 5
	var full: DayReport = DayReport.new()
	full.customers_served = 21
	full.customers_lost = 14
	full.leave_reasons = {&"no_table": 12, &"too_expensive": 2}
	var mixed: DayReport = DayReport.new()
	mixed.customers_lost = 6
	mixed.leave_reasons = {&"no_table": 2, &"waited_too_long": 4}

	_assert_group(2, tier, &"tier", "0", "$0")
	_assert_group(2, level, &"level_up", "0", "$0")
	_assert_group(2, regular, &"regular", "0", "$0")
	_assert_group(2, came_only, &"quiet", "5", "$0")
	_assert_group(2, full, &"full_house", "21", "$0")
	_assert_group(2, mixed, &"walkouts", "6", "$0")


func test_one_tip_names_the_biggest_reason_guests_left() -> void:
	var report: DayReport = DayReport.new()
	assert_eq(MorningPaper.tip_for(null), "")
	assert_eq(MorningPaper.tip_for(report), "")
	report.leave_reasons = {&"no_table": 2, &"too_expensive": 2, &"happy": 30}
	assert_eq(MorningPaper.tip_for(report), "", "two of a kind is not yet a pattern")
	report.leave_reasons = {&"no_table": 12, &"too_expensive": 4}
	assert_true(MorningPaper.tip_for(report).begins_with("12 guests found every seat taken."))
	report.leave_reasons = {&"no_table": 3, &"too_expensive": 5}
	assert_true(MorningPaper.tip_for(report).begins_with("5 guests left over the prices."))
	report.leave_reasons = {&"waited_too_long": 3, &"out_of_stock": 3}
	assert_true(MorningPaper.tip_for(report).begins_with("3 guests gave up waiting."), "ties keep the listed order")


func test_the_tip_comes_before_the_favourite_dish() -> void:
	var report: DayReport = DayReport.new()
	report.leave_reasons = {&"too_expensive": 4}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var edition: Dictionary = MorningPaper.build(2, report, WeatherState.Kind.SUNNY, ["Booked today"], rng, DISH)
	assert_eq(edition["notes"], ["Sunny today", "Booked today", MorningPaper.tip_for(report)])
	edition = MorningPaper.build(2, DayReport.new(), WeatherState.Kind.SUNNY, [], rng, DISH)
	assert_eq(edition["notes"], ["Sunny today", "%s was yesterday’s favorite." % DISH])


func test_slots_are_one_pass_and_leave_literal_dish_names_intact() -> void:
	var values: Dictionary[String, String] = {
		"dish": "Soup {cash} \\ $",
		"guests": "7",
		"cash": "-$23",
	}
	assert_eq(MorningPaper._fill("{dish} for {guests} at {cash}", values),
		"Soup {cash} \\ $ for 7 at -$23")


func test_notes_use_existing_copy_and_cap_the_hook_at_three() -> void:
	var report: DayReport = DayReport.new()
	report.inspection_lines = ["Inspection grade: B", "This is a second line"]
	var notes: Array[String] = [" ", "Rain today", "  Lunch rush  ", "Booked today"]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var edition: Dictionary = MorningPaper.build(2, report, WeatherState.Kind.RAIN, notes, rng)
	assert_eq(edition["notes"], ["Rain today", "Inspection grade: B", "Lunch rush"])
	assert_eq(notes, [" ", "Rain today", "  Lunch rush  ", "Booked today"])
	assert_eq(MorningPaper.build(2, null, -1, [], rng)["notes"], [])


func test_existing_history_guides_reloaded_mornings_with_no_report() -> void:
	var history: Dictionary = {"lost": 5, "served": 6, "cash_change": 30}
	_assert_group(2, null, &"walkouts", "5", "$30", history)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var missing: Dictionary = MorningPaper.build(2, null, WeatherState.Kind.SUNNY, [], rng)
	assert_eq(missing["headline"], MorningPaper.FALLBACK_HEADLINE)


func _assert_group(day: int, report: DayReport, group: StringName, guests: String, cash: String,
		history: Dictionary = {}) -> void:
	var expected: PackedStringArray = []
	for source: String in MorningPaper.HEADLINES.groups[group]:
		expected.append(source.replace("{dish}", DISH).replace("{guests}", guests).replace("{cash}", cash))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(12):
		rng.seed = seed_value
		var edition: Dictionary = MorningPaper.build(day, report, WeatherState.Kind.SUNNY, [], rng, DISH, history)
		var headline: String = edition["headline"]
		assert_eq(edition["masthead"], "The Daily Ladle")
		assert_true(expected.has(headline), "%s must draw from %s" % [headline, String(group)])
		assert_false(headline.contains("{"))
