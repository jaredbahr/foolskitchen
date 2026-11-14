extends TestCase
## Service event cards (#495): the authored pool, the seeded daily draw, the
## cooldowns and conditions, the risk rolls, the previews and the save section.

const TUNING: ServiceEventTuning = preload("res://data/balance/service_events.tres")
const OPEN: int = 11 * 60
const CLOSE: int = 21 * 60


func _definitions() -> Array[ServiceEventDef]:
	var errors: PackedStringArray = []
	var found: Array[ServiceEventDef] = ServiceEvents.load_definitions(errors)
	assert_eq(errors.size(), 0, "every card is valid: %s" % ", ".join(errors))
	return found


func _model() -> ServiceEvents:
	return ServiceEvents.new(TUNING, _definitions())


## Everything a card can ask for: staff, a regular, rain and bought stock.
func _rich(level: int = 5, tier: int = 2) -> Dictionary:
	return {"level": level, "tier": tier,
		"staff": [{"id": "ana", "name": "Ana", "role": "cook"}, {"id": "bo", "name": "Bo", "role": "server"}],
		"regulars": ["Margo"], "rain": true,
		"ingredients": [{"id": "tomato", "name": "Tomato"}, {"id": "bun", "name": "Bun"}]}


func _bare() -> Dictionary:
	return {"level": 1, "tier": 1, "staff": [], "regulars": [], "rain": false, "ingredients": []}


## Plans and answers every card of `days` days with the first choice.
func _run_days(model: ServiceEvents, seed_value: int, days: int, context: Dictionary) -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	for day: int in range(1, days + 1):
		model.begin_morning(day)
		model.plan_day(day, seed_value, context, OPEN, CLOSE)
		for minute: int in range(OPEN, CLOSE + 1):
			var entry: Dictionary = model.due(minute)
			if entry.is_empty():
				continue
			var outcome: Dictionary = model.pick(0, seed_value)
			shown.append({"day": day, "id": entry["id"], "minute": entry["minute"],
				"risk": outcome["risk"], "result": outcome["result"]})
		model.end_service()
	return shown


func test_pool_loads_eleven_valid_cards_from_data() -> void:
	var definitions: Array[ServiceEventDef] = _definitions()
	# "Can I leave early?" waits for a real send-home (#506).
	assert_eq(definitions.size(), 11)
	var ids: Array[StringName] = []
	for definition: ServiceEventDef in definitions:
		ids.append(definition.id)
		assert_true(definition.choices.size() >= 2 and definition.choices.size() <= 3, "%s has 2-3 choices" % definition.id)
	for id: StringName in [&"off_menu", &"supplier_van", &"busker", &"spilled_drink", &"food_blogger",
			&"power_flicker", &"regular_birthday", &"neighbour_complaint", &"kids_drawing",
			&"rain_umbrellas", &"critic_rumour"]:
		assert_true(ids.has(id), "%s is in the pool" % id)
	assert_false(ids.has(&"leave_early"), "the leave-early card is out until send-home exists")


func test_every_card_keeps_a_free_choice() -> void:
	for definition: ServiceEventDef in _definitions():
		var free: int = 0
		for choice: ServiceEventChoice in definition.choices:
			if choice.is_free():
				free += 1
		assert_true(free >= 1, "%s can always be answered" % definition.id)
	var definition: ServiceEventDef = _definitions()[0].duplicate(true)
	for choice: ServiceEventChoice in definition.choices:
		choice.cash = -5
	assert_true(", ".join(definition.errors()).contains("one choice must cost no cash and no stock"))


func test_cash_needed_counts_a_costly_risk() -> void:
	var choice: ServiceEventChoice = ServiceEventChoice.new()
	assert_eq(choice.cash_needed(), 0)
	choice.cash = -10
	assert_eq(choice.cash_needed(), 10)
	choice.cash = 4
	choice.risk_percent = 30
	choice.risk_cash = -10
	assert_eq(choice.cash_needed(), 6, "a risk that may cost money must be affordable too")
	choice.risk_cash = 10
	assert_eq(choice.cash_needed(), 0)
	assert_true(choice.is_free())
	choice.stock_units = -2
	assert_false(choice.is_free(), "using stock is not free")


func test_kids_drawing_is_a_small_nudge() -> void:
	var hang: ServiceEventChoice = _model().definition(&"kids_drawing").choices[0]
	assert_eq(hang.review_stars, 4, "a four-star review, not a free five")
	assert_true(hang.result.contains("four stars"))


func test_invalid_cards_are_refused() -> void:
	var definition: ServiceEventDef = ServiceEventDef.new()
	definition.id = &"broken"
	definition.title = "Broken"
	definition.text = "Hello {regular}"
	var choice: ServiceEventChoice = ServiceEventChoice.new()
	choice.label = "Spend"
	choice.result = "Spent"
	choice.cash = -500
	definition.choices = [choice]
	var problems: PackedStringArray = definition.errors()
	assert_true(problems.size() >= 3, "one choice, a big cost and an unmet {regular} are all refused")


func test_same_seed_same_cards_and_outcomes() -> void:
	var first: Array[Dictionary] = _run_days(_model(), 7, 20, _rich())
	var second: Array[Dictionary] = _run_days(_model(), 7, 20, _rich())
	assert_eq(first, second, "a seed replays its cards, minutes and results exactly")
	var other: Array[Dictionary] = _run_days(_model(), 8, 20, _rich())
	assert_ne(first, other, "another seed meets other cards")


func test_one_or_two_cards_every_open_day() -> void:
	var counts: Dictionary[int, int] = {}
	for seed_value: int in [1, 2, 3]:
		var shown: Array[Dictionary] = _run_days(_model(), seed_value, 30, _rich())
		var per_day: Dictionary[int, int] = {}
		for row: Dictionary in shown:
			per_day[int(row["day"])] = int(per_day.get(int(row["day"]), 0)) + 1
		for day: int in range(1, 31):
			var count: int = int(per_day.get(day, 0))
			assert_true(count >= 1 and count <= 2, "seed %d day %d brings 1-2 cards, got %d" % [seed_value, day, count])
			counts[count] = int(counts.get(count, 0)) + 1
	assert_true(int(counts.get(1, 0)) > 10 and int(counts.get(2, 0)) > 10, "both one- and two-card days happen: %s" % str(counts))


func test_day_one_has_a_card_for_a_brand_new_shop() -> void:
	# Level 1, Tier 1, no staff, no regulars, dry: the bare starter morning.
	var shown: Array[Dictionary] = _run_days(_model(), 1, 2, _bare())
	var day_one: int = 0
	for row: Dictionary in shown:
		if int(row["day"]) == 1:
			day_one += 1
	assert_true(day_one >= 1, "day 1 brings a card")


func test_no_draw_without_opening() -> void:
	var model: ServiceEvents = _model()
	model.begin_morning(4)
	assert_eq(model.due(CLOSE), {}, "a day that never opened has no card due")
	assert_eq(model.schedule.size(), 0)
	assert_eq(model.day, 0, "and nothing was drawn")


func test_cards_keep_inside_service_and_clear_of_other_events() -> void:
	var blocked: Array[Vector2i] = [Vector2i(13 * 60, 14 * 60), Vector2i(17 * 60, 17 * 60 + 30)]
	for seed_value: int in range(1, 41):
		var model: ServiceEvents = _model()
		var plan: Array[Dictionary] = model.plan_day(3, seed_value, _rich(), OPEN, CLOSE, blocked)
		assert_true(plan.size() >= 1 and plan.size() <= 2)
		var previous: int = -1000
		for entry: Dictionary in plan:
			var minute: int = int(entry["minute"])
			assert_true(minute >= OPEN + TUNING.opening_margin_minutes, "not in the first minutes")
			assert_true(minute <= CLOSE - TUNING.closing_margin_minutes, "not in the last minutes")
			for window: Vector2i in blocked:
				assert_true(minute < window.x - TUNING.clear_minutes or minute > window.y + TUNING.clear_minutes,
					"seed %d: %d keeps clear of %s" % [seed_value, minute, window])
			assert_true(minute - previous >= TUNING.min_gap_minutes, "two cards come well apart")
			previous = minute


func test_no_repeat_inside_cooldown() -> void:
	var model: ServiceEvents = _model()
	var shown: Array[Dictionary] = _run_days(model, 5, 60, _rich())
	var last: Dictionary[String, int] = {}
	for row: Dictionary in shown:
		var id: String = row["id"]
		if last.has(id):
			var cooldown: int = model.definition(StringName(id)).cooldown_days
			assert_true(int(row["day"]) - last[id] >= cooldown, "%s waits %d days" % [id, cooldown])
		last[id] = int(row["day"])
	assert_true(last.size() >= 10, "most cards come up over two months: %s" % str(last.keys()))


func test_conditions_gate_cards() -> void:
	var seen: Dictionary[String, bool] = {}
	for seed_value: int in range(1, 6):
		for row: Dictionary in _run_days(_model(), seed_value, 40, _bare()):
			seen[row["id"]] = true
	for gated: String in ["regular_birthday", "rain_umbrellas", "critic_rumour",
			"supplier_van", "off_menu"]:
		assert_false(seen.has(gated), "%s needs its condition" % gated)
	assert_true(seen.has("busker") and seen.has("spilled_drink"), "ungated cards still come up")
	var model: ServiceEvents = _model()
	var rich: Dictionary = _rich(5, 1)
	assert_false(model.can_show(model.definition(&"critic_rumour"), 1, rich), "critic rumour is Tier 2+")
	assert_true(model.can_show(model.definition(&"critic_rumour"), 1, _rich(5, 2)))
	assert_true(model.can_show(model.definition(&"regular_birthday"), 1, rich))
	model.last_shown[&"busker"] = 10
	assert_false(model.can_show(model.definition(&"busker"), 13, rich), "inside the cooldown")
	assert_true(model.can_show(model.definition(&"busker"), 14, rich), "after the cooldown")


func test_names_fill_the_card_from_the_context() -> void:
	var model: ServiceEvents = _model()
	var context: Dictionary = _rich()
	for seed_value: int in range(1, 200):
		model = _model()
		model.plan_day(2, seed_value, context, OPEN, CLOSE)
		for entry: Dictionary in model.schedule:
			if entry["id"] == "supplier_van":
				var card: Dictionary = model.card_text(entry)
				assert_true(String(card["text"]).contains("Cheap tomato") or String(card["text"]).contains("Cheap bun"))
				assert_true(entry["ingredient_id"] in ["tomato", "bun"])
				assert_false(String(card["title"]).contains("{") or String(card["text"]).contains("{"))
				return
	assert_true(false, "supplier_van came up for some seed")


func test_risk_rolls_are_seeded_and_proportionate() -> void:
	var definition: ServiceEventDef = _model().definition(&"spilled_drink")
	var choice: ServiceEventChoice = definition.choices[1]
	assert_eq(choice.risk_percent, 40)
	var hits: int = 0
	for day: int in range(1, 401):
		var hit: bool = ServiceEvents.risk_hit(choice, 3, day, definition.id, 1)
		assert_eq(hit, ServiceEvents.risk_hit(choice, 3, day, definition.id, 1), "the same roll every time")
		if hit:
			hits += 1
	assert_true(hits > 120 and hits < 200, "about 40%% land, got %d of 400" % hits)
	assert_false(ServiceEvents.risk_hit(definition.choices[0], 3, 1, definition.id, 0), "no risk, no roll")


func test_pick_records_the_answer_and_tomorrow_nudge() -> void:
	var model: ServiceEvents = _model()
	model.day = 6
	model.schedule = [{"id": "food_blogger", "minute": 700, "shown": false, "names": {},
		"staff_id": "", "staff_role": "", "ingredient_id": ""}]
	assert_false(model.due(699).size() > 0, "not before its minute")
	var entry: Dictionary = model.due(700)
	assert_eq(entry["id"], "food_blogger")
	assert_eq(model.last_shown[&"food_blogger"], 6, "the cooldown starts when it shows")
	assert_eq(model.due(800), {}, "nothing else while a card is up")
	assert_eq(model.pick(5, 1), {}, "an out-of-range choice is refused")
	var outcome: Dictionary = model.pick(0, 1, "home")
	assert_eq(outcome["label"], "Seat them now")
	assert_almost_eq(model.arrival_factor(7, "home"), 1.08)
	assert_almost_eq(model.arrival_factor(7, "site_2"), 1.0, 0.0001, "the buzz is about the shop it happened at")
	assert_almost_eq(model.arrival_factor(6, "home"), 1.0)
	assert_eq(model.report_lines().size(), 1)
	assert_true(model.report_lines()[0].begins_with("Food blogger at the door: Seat them now."))
	model.begin_morning(8)
	assert_almost_eq(model.arrival_factor(8, "home"), 1.0, 0.0001, "the nudge was for one day")
	assert_eq(model.answered.size(), 0, "a new morning forgets yesterday's answers")


func test_closing_drops_an_unanswered_card() -> void:
	var model: ServiceEvents = _model()
	model.plan_day(2, 4, _rich(), OPEN, CLOSE)
	var entry: Dictionary = model.due(CLOSE)
	assert_false(entry.is_empty())
	model.end_service()
	assert_true(model.pending.is_empty())
	assert_eq(model.due(CLOSE), {}, "the rest of the day's cards are spent")
	assert_eq(model.answered.size(), 0, "an unanswered card has no outcome")


func test_save_round_trip_and_old_saves() -> void:
	var model: ServiceEvents = _model()
	_run_days(model, 9, 6, _rich())
	model.boost_day = 7
	model.boost_percent = 8
	model.boost_site = "home"
	var saved: Dictionary = JSON.parse_string(JSON.stringify(model.to_dict()))
	assert_false(saved.has("pending"), "a card on screen is never saved")
	var loaded: ServiceEvents = _model()
	assert_true(loaded.from_dict(saved))
	assert_eq(loaded.to_dict(), model.to_dict())
	assert_true(loaded.pending.is_empty())
	# The next days continue exactly as the unsaved run does.
	assert_eq(_continue(loaded), _continue(model))
	for broken: Dictionary in [{}, {"version": 2}, saved.merged({"boost_percent": 90}, true),
			saved.merged({"last_shown": {"busker": -1}}, true), saved.merged({"boost_site": 3}, true)]:
		assert_false(_model().from_dict(broken), "invalid data is refused: %s" % str(broken))
	var fresh: ServiceEvents = _model()
	assert_eq(fresh.last_shown.size(), 0, "a game from before service events starts empty")


func _continue(model: ServiceEvents) -> Array:
	var rows: Array = []
	for day: int in range(7, 12):
		model.begin_morning(day)
		for entry: Dictionary in model.plan_day(day, 9, _rich(), OPEN, CLOSE):
			rows.append([day, entry["id"], entry["minute"]])
	return rows


func test_every_choice_has_a_plain_preview() -> void:
	for definition: ServiceEventDef in _definitions():
		for choice: ServiceEventChoice in definition.choices:
			var text: String = ServiceEventText.preview(choice, {"staff": "Ana", "ingredient": "tomato"}, 1)
			assert_false(text.is_empty(), "%s: %s has a preview" % [definition.id, choice.label])
			assert_false(text.contains("_") or text.contains("{"), "no raw names: %s" % text)
	var van: ServiceEventChoice = _model().definition(&"supplier_van").choices[0]
	assert_eq(ServiceEventText.preview(van, {"ingredient": "tomato"}, 1),
		"Buy tomato x20 for $12, might be a bad batch")
	var busker: ServiceEventChoice = _model().definition(&"busker").choices[0]
	assert_eq(ServiceEventText.preview(busker), "-$15, guests more patient today, more walk-ins today")
	assert_eq(ServiceEventText.preview(_model().definition(&"busker").choices[1]), ServiceEventText.NOTHING)
