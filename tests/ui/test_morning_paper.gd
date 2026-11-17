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
