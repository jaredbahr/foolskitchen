extends TestCase
## Guest type review voices and the morning paper's quirk brief (#662).

const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const QUIRKS: GuestQuirkCatalogue = preload("res://data/customers/quirks.tres")
const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const MAX_LINE: int = 90
const TYPE_IDS: Array[StringName] = [&"regular", &"student", &"foodie", &"family", &"tourist", &"office"]


func test_every_type_and_quirk_has_authored_lines() -> void:
	assert_true(QUOTES.is_valid())
	for kind: CustomerType in TYPES.types:
		var group: StringName = ReviewQuotes.type_cause(kind.id)
		assert_ne(group, &"lovely_place", "%s has its own voice" % kind.id)
		assert_true(QUOTES.groups.has(group))
	for quirk: GuestQuirk in QUIRKS.quirks:
		var lines: PackedStringArray = MorningPaper.HEADLINES.groups.get(
			StringName("brief_%s" % quirk.id), PackedStringArray())
		assert_false(lines.is_empty(), "%s has paper briefs" % quirk.id)
	assert_eq(ReviewQuotes.type_cause(&"alien"), &"lovely_place", "an unknown type falls back")
	assert_eq(ReviewQuotes.type_cause(&""), &"lovely_place")


func test_no_duplicate_lines_and_all_short() -> void:
	var seen: Dictionary[String, StringName] = {}
	var sources: Array[Dictionary] = [QUOTES.groups, {}]
	for key: StringName in MorningPaper.HEADLINES.groups:
		if String(key).begins_with("brief_"):
			sources[1][key] = MorningPaper.HEADLINES.groups[key]
	for source: Dictionary in sources:
		for key: StringName in source:
			var within: Dictionary[String, bool] = {}
			for line: String in source[key]:
				assert_false(within.has(line), "duplicate in %s: %s" % [key, line])
				within[line] = true
				if source == sources[1] or _is_voice(key):
					assert_lt_length(line, key)
					assert_false(seen.has(line), "%s repeats a line from %s" % [key, seen.get(line)])
					seen[line] = key
	assert_true(seen.size() >= 6 * 6 + 3 * 3)


func test_a_good_visit_draws_from_its_types_group() -> void:
	var always: ReviewTuning = TUNING.duplicate() as ReviewTuning
	always.review_chance = 1.0
	for type_id: StringName in TYPE_IDS:
		var group: PackedStringArray = QUOTES.groups[ReviewQuotes.type_cause(type_id)]
		for seed_value: int in 12:
			var visit: ReviewVisit = _visit(type_id, 0.1)
			var row: Dictionary = ReputationBook.new().record_visit(visit, always, QUOTES, _random(seed_value))
			assert_eq(row["cause"], &"lovely_place", "the report cause is untouched")
			assert_true(group.has(String(row["quote"])), "%s: %s" % [type_id, row["quote"]])
	# A type with no voice (or none given) keeps the shared pool.
	var row: Dictionary = ReputationBook.new().record_visit(_visit(&"alien", 0.1), always, QUOTES, _random(1))
	assert_true(QUOTES.groups[&"lovely_place"].has(String(row["quote"])))


func test_complaints_and_specific_causes_ignore_the_type() -> void:
	var always: ReviewTuning = TUNING.duplicate() as ReviewTuning
	always.review_chance = 1.0
	for type_id: StringName in TYPE_IDS:
		var slow: ReviewVisit = _visit(type_id, 1.0)
		slow.queue_wait_fraction = 1.0
		slow.food_wait_fraction = 1.0
		slow.dirt_fraction = 1.0
		var row: Dictionary = ReputationBook.new().record_visit(slow, always, QUOTES, _random(3))
		assert_lt(int(row["stars"]), 4)
		assert_true(QUOTES.groups[row["cause"]].has(String(row["quote"])), "%s complaint" % type_id)
		assert_false(QUOTES.groups[ReviewQuotes.type_cause(type_id)].has(String(row["quote"])))
		var cheap: ReviewVisit = _visit(type_id, 0.1)
		cheap.price_ratio = 0.5
		row = ReputationBook.new().record_visit(cheap, always, QUOTES, _random(4))
		assert_eq(row["cause"], &"great_value")
		assert_true(QUOTES.groups[&"great_value"].has(String(row["quote"])))
		var quirky: ReviewVisit = _visit(type_id, 0.1)
		quirky.quirk_cause = &"photo_happy"
		row = ReputationBook.new().record_visit(quirky, always, QUOTES, _random(5))
		assert_true(QUOTES.groups[&"photo_happy"].has(String(row["quote"])), "a quirk beats the type")
		var signature: ReviewVisit = _visit(type_id, 0.1)
		signature.ate_signature_dish = true
		row = ReputationBook.new().record_visit(signature, always, QUOTES, _random(6))
		assert_true(QUOTES.groups[&"signature_dish"].has(String(row["quote"])))


## The hard rule (#602): the voice changes quote text only. The same seeded
## visits, through the real quotes and through a copy with no type groups,
## give identical stars, causes, windows and review-stream states.
func test_type_voices_never_change_seeded_review_outcomes() -> void:
	var plain: ReviewQuotes = ReviewQuotes.new()
	plain.groups = QUOTES.groups.duplicate()
	for type_id: StringName in TYPE_IDS:
		plain.groups.erase(ReviewQuotes.type_cause(type_id))
	var tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	tuning.review_chance = 0.6
	var voiced_total: int = 0
	var differing_quotes: int = 0
	for seed_value: int in [1, 7, 42]:
		var with_voice: ReputationBook = ReputationBook.new()
		var without: ReputationBook = ReputationBook.new()
		var rng_a: RandomNumberGenerator = _random(seed_value)
		var rng_b: RandomNumberGenerator = _random(seed_value)
		var maker: RandomNumberGenerator = _random(seed_value + 1000)
		for day: int in 6:
			with_voice.begin_day()
			without.begin_day()
			for index: int in 40:
				var type_id: StringName = TYPE_IDS[maker.randi_range(0, TYPE_IDS.size() - 1)]
				var visit: ReviewVisit = _visit(type_id, maker.randf())
				visit.served = maker.randf() < 0.9
				visit.queue_wait_fraction = maker.randf()
				visit.price_ratio = 0.8 + maker.randf() * 0.6
				visit.quirk_cause = &"quick_lunch" if maker.randf() < 0.1 else &""
				visit.always_reviews = maker.randf() < 0.1
				var a: Dictionary = with_voice.record_visit(visit, tuning, QUOTES, rng_a)
				var b: Dictionary = without.record_visit(visit, tuning, plain, rng_b)
				assert_eq(a.is_empty(), b.is_empty(), "same review decision")
				assert_eq(rng_a.state, rng_b.state, "same number of draws, day %d visit %d" % [day, index])
				if a.is_empty():
					continue
				voiced_total += 1
				assert_eq(a["stars"], b["stars"])
				assert_eq(a["cause"], b["cause"])
				assert_eq(a["after"], b["after"])
				if a["quote"] != b["quote"]:
					differing_quotes += 1
			assert_eq(with_voice.scores(), without.scores())
	assert_true(voiced_total > 300, "enough reviews to mean something: %d" % voiced_total)
	assert_true(differing_quotes > 20, "the voices were actually used: %d" % differing_quotes)


## The same sequence run on main before the voices existed gave this hash of
## every (stars, review-stream state) pair, so the voices change neither.
func test_seeded_stream_matches_the_pre_voice_golden() -> void:
	var tuning: ReviewTuning = TUNING.duplicate() as ReviewTuning
	tuning.review_chance = 0.6
	var out: PackedStringArray = PackedStringArray()
	for seed_value: int in [1, 7, 42]:
		var book: ReputationBook = ReputationBook.new()
		var rng: RandomNumberGenerator = _random(seed_value)
		var maker: RandomNumberGenerator = _random(seed_value + 1000)
		for day: int in 6:
			book.begin_day()
			for index: int in 40:
				var visit: ReviewVisit = ReviewVisit.new()
				visit.served = maker.randf() < 0.9
				visit.was_seated = true
				visit.food_wait_fraction = maker.randf() * 0.3
				visit.queue_wait_fraction = maker.randf()
				visit.price_ratio = 0.8 + maker.randf() * 0.6
				visit.type_id = TYPE_IDS[maker.randi_range(0, 5)]
				var row: Dictionary = book.record_visit(visit, tuning, QUOTES, rng)
				out.append("%d|%d" % [int(row.get("stars", 0)), rng.state])
	assert_eq(out.size(), 720)
	assert_eq("\n".join(out).hash(), 3271145376)


func test_the_sim_counts_served_quirk_guests_per_day() -> void:
	var sim: RestaurantSim = _sim()
	for index: int in 3:
		var guest: CustomerAgent = _guest(sim, &"regular", index)
		assert_true(guest.apply_quirk(QUIRKS.find_quirk(&"chatterbox" if index == 0 else &"shutterbug")))
		guest.paid = index != 2
		guest.leave_reason = &"happy"
		sim.record_departure(guest)
	sim.record_departure(_guest(sim, &"regular", 9))
	assert_eq(sim.quirks_today, {&"chatterbox": 1, &"shutterbug": 1} as Dictionary[StringName, int])
	var builder_report: DayReport = DayReport.new()
	builder_report.quirk_counts = sim.quirks_today.duplicate()
	assert_eq(builder_report.quirk_counts.size(), 2)
	assert_false(builder_report.to_dict().has("quirk_counts"), "no new save state")
	sim.start_day()
	assert_true(sim.quirks_today.is_empty())


func test_the_brief_shows_only_after_a_quirk_day_and_is_deterministic() -> void:
	var rng: RandomNumberGenerator = _random(5)
	assert_eq(MorningPaper.quirk_brief(5, null), "")
	assert_eq(MorningPaper.quirk_brief(5, DayReport.new()), "")
	var quiet: Dictionary = MorningPaper.build(5, DayReport.new(), WeatherState.Kind.SUNNY, [], rng)
	assert_eq(quiet["notes"], ["Sunny today"])
	var report: DayReport = DayReport.new()
	report.quirk_counts = {&"shutterbug": 1}
	var lines: PackedStringArray = MorningPaper.HEADLINES.groups[&"brief_shutterbug"]
	for day: int in range(2, 9):
		var line: String = MorningPaper.quirk_brief(day, report)
		assert_eq(line, lines[day % lines.size()])
		assert_eq(MorningPaper.quirk_brief(day, report), line, "same day, same line")
		var edition: Dictionary = MorningPaper.build(day, report, WeatherState.Kind.SUNNY, [], rng)
		assert_eq(edition["notes"], ["Sunny today", line])
	# Most-seen wins; a tie goes to the lower quirk id; unknown quirks are skipped.
	report.quirk_counts = {&"shutterbug": 2, &"chatterbox": 3, &"lunch_break": 3}
	assert_true(MorningPaper.HEADLINES.groups[&"brief_chatterbox"].has(MorningPaper.quirk_brief(4, report)))
	report.quirk_counts = {&"shutterbug": 3, &"lunch_break": 3, &"mystery": 9}
	assert_true(MorningPaper.HEADLINES.groups[&"brief_lunch_break"].has(MorningPaper.quirk_brief(4, report)))
	report.quirk_counts = {&"mystery": 9}
	assert_eq(MorningPaper.quirk_brief(4, report), "")


func test_the_brief_never_pushes_out_another_note() -> void:
	var report: DayReport = DayReport.new()
	report.quirk_counts = {&"chatterbox": 2}
	var rng: RandomNumberGenerator = _random(6)
	var brief: String = MorningPaper.quirk_brief(3, report)
	var full: Dictionary = MorningPaper.build(3, report, WeatherState.Kind.SUNNY, ["A tip line", "Booked today"], rng)
	assert_eq(full["notes"], ["Sunny today", "A tip line", "Booked today"])
	var dish: Dictionary = MorningPaper.build(3, report, WeatherState.Kind.SUNNY, ["A tip line"], rng, "Tomato Soup")
	assert_eq(dish["notes"], ["Sunny today", "A tip line", "Tomato Soup was yesterday’s favorite."])
	var room: Dictionary = MorningPaper.build(3, report, WeatherState.Kind.SUNNY, ["A tip line"], rng)
	assert_eq(room["notes"], ["Sunny today", "A tip line", brief])
	assert_true(room["notes"].size() <= MorningPaper.MAX_NOTES)


func _is_voice(key: StringName) -> bool:
	return String(key).ends_with("_happy")


func assert_lt_length(line: String, key: StringName) -> void:
	assert_true(line.length() < MAX_LINE, "%s is %d characters: %s" % [key, line.length(), line])


func assert_lt(value: int, limit: int) -> void:
	assert_true(value < limit, "%d should be under %d" % [value, limit])


## A served, otherwise perfect visit; `wait` is the share of food patience spent.
func _visit(type_id: StringName, wait: float) -> ReviewVisit:
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.was_seated = true
	visit.type_id = type_id
	visit.food_wait_fraction = wait * 0.3
	return visit


func _guest(sim: RestaurantSim, type_id: StringName, seed_value: int) -> CustomerAgent:
	return sim.add_customer(sim.world.grid.entries()[0], _random(seed_value), TYPES.find_type(type_id))


func _sim() -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 662, errors, null, false)
	assert_eq(errors, [] as Array[String])
	return sim


func _random(value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = value
	return random
