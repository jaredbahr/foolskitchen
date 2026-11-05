extends TestCase
## The surprise health inspector (#302): when it comes, what it reads, the grade
## it leaves and how long the grade nudges arrivals.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: InspectionTuning = preload("res://data/balance/inspection.tres")
const OPEN_TICKS: int = 3600

var _asked: int = 0


func after_each() -> void:
	GameState.new_run(1)


# --- Data -----------------------------------------------------------------------

func test_data_defaults_match_the_issue() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.unlock_level, 3)
	assert_eq(TUNING.min_gap_days, 7)
	assert_almost_eq(TUNING.daily_chance, 0.15)
	assert_eq(TUNING.effect_days, 7)
	assert_almost_eq(TUNING.factor_a, 1.05)
	assert_almost_eq(TUNING.factor_b, 1.0)
	assert_almost_eq(TUNING.factor_c, 0.9)
	assert_eq(TUNING.visit_ticks, 600, "about sixty seconds at ten ticks a second")


func test_invalid_tuning_is_refused() -> void:
	var bad: InspectionTuning = TUNING.duplicate(true) as InspectionTuning
	bad.grade_a_max = 9.0
	assert_false(bad.is_valid(), "A may not be a worse line than B")
	bad = TUNING.duplicate(true) as InspectionTuning
	bad.factor_c = 0.0
	assert_false(bad.is_valid())


# --- Grades ---------------------------------------------------------------------

func test_grade_follows_the_data_thresholds() -> void:
	assert_eq(InspectionModel.grade_for(0.0, TUNING), &"A")
	assert_eq(InspectionModel.grade_for(TUNING.grade_a_max, TUNING), &"A")
	assert_eq(InspectionModel.grade_for(TUNING.grade_a_max + 0.01, TUNING), &"B")
	assert_eq(InspectionModel.grade_for(TUNING.grade_b_max, TUNING), &"B")
	assert_eq(InspectionModel.grade_for(TUNING.grade_b_max + 0.01, TUNING), &"C")
	var strict: InspectionTuning = TUNING.duplicate(true) as InspectionTuning
	strict.grade_a_max = 0.0
	strict.grade_b_max = 1.0
	assert_eq(InspectionModel.grade_for(0.5, strict), &"B", "the lines are data")


func test_findings_are_weighted_by_data_and_worst_first() -> void:
	var facts: Dictionary = {InspectionModel.TABLES: 2, InspectionModel.FLOOR: 1,
		InspectionModel.RESTROOM: 1, InspectionModel.STOCK: 8, InspectionModel.DISHES: 5}
	var result: Dictionary = InspectionModel.evaluate(facts, TUNING)
	# 2 tables x 2 + 1 spill x 1 + 1 restroom x 1.5 + 8 cash x 0.25 + (5 - 3) plates x 0.5
	assert_almost_eq(float(result["points"]), 4.0 + 1.0 + 1.5 + 2.0 + 1.0)
	assert_eq(result["grade"], &"C")
	var kinds: Array[StringName] = []
	for row: Dictionary in result["findings"]:
		kinds.append(row["kind"])
	assert_eq(kinds, [InspectionModel.TABLES, InspectionModel.STOCK, InspectionModel.RESTROOM,
		InspectionModel.FLOOR, InspectionModel.DISHES] as Array[StringName])


func test_spoiled_stock_is_capped_and_a_few_dirty_plates_are_free() -> void:
	var result: Dictionary = InspectionModel.evaluate({InspectionModel.STOCK: 10000}, TUNING)
	assert_almost_eq(float(result["points"]), TUNING.spoiled_points_cap)
	result = InspectionModel.evaluate({InspectionModel.DISHES: TUNING.dirty_plates_free}, TUNING)
	assert_eq(result["grade"], &"A")
	assert_true((result["findings"] as Array).is_empty())


func test_a_clean_staged_shop_is_an_a_and_a_messy_one_a_c() -> void:
	var sim: RestaurantSim = _staged_sim()
	var clean: Dictionary = InspectionModel.evaluate(InspectionModel.capture(sim), TUNING)
	assert_eq(clean["grade"], &"A")
	assert_true((clean["findings"] as Array).is_empty())
	_make_messy(sim)
	var messy: Dictionary = InspectionModel.evaluate(InspectionModel.capture(sim), TUNING)
	assert_eq(messy["grade"], &"C")
	var findings: Array = messy["findings"]
	assert_true(findings.size() >= 2)
	var lines: Array[String] = InspectionText.report_lines(messy, TUNING)
	assert_eq(lines[0], "Health inspection: grade C")
	assert_true(lines.size() <= 1 + TUNING.report_findings, "only the worst few are named")
	for line: String in lines:
		assert_false(line.contains("_"), "plain words, no ids: " + line)


func test_report_lines_for_a_spotless_shop() -> void:
	var result: Dictionary = InspectionModel.evaluate({}, TUNING)
	assert_eq(InspectionText.report_lines(result, TUNING),
		["Health inspection: grade A", InspectionText.CLEAN] as Array[String])
	assert_eq(InspectionText.report_lines({}, TUNING), [] as Array[String])


# --- When it comes --------------------------------------------------------------

func test_no_visits_before_level_three_and_no_stream_either() -> void:
	var book: InspectionBook = InspectionBook.new(TUNING)
	_asked = 0
	for day: int in range(1, 400):
		book.plan_day(day, TUNING.unlock_level - 1, OPEN_TICKS, _never_asked)
		assert_eq(book.planned_tick, -1, "day %d" % day)
	assert_eq(_asked, 0, "the stream is never even asked for")
	assert_false((GameState._capture_save()["rngs"] as Dictionary).has("inspector"))


func test_at_most_one_visit_in_any_seven_days() -> void:
	var chatty: InspectionTuning = TUNING.duplicate(true) as InspectionTuning
	chatty.daily_chance = 1.0
	var book: InspectionBook = InspectionBook.new(chatty)
	var days: Array[int] = []
	for day: int in range(1, 120):
		book.plan_day(day, 3, OPEN_TICKS, _stream(5))
		if book.planned_tick >= 0:
			days.append(day)
			book.record(day, {"grade": &"B", "findings": []})
	assert_true(days.size() >= 15, "a certain chance visits as often as it may")
	for index: int in range(1, days.size()):
		assert_true(days[index] - days[index - 1] >= 7, "days %d and %d" % [days[index - 1], days[index]])
	assert_eq(days[0], 1)
	assert_eq(days[1], 8)


func test_same_seed_same_visit_days_and_other_seeds_differ() -> void:
	var first: Array[int] = _visit_days(11)
	assert_eq(_visit_days(11), first)
	assert_true(first.size() >= 3 and first.size() <= 40, "a sensible number over 300 days")
	assert_ne(_visit_days(12), first)
	var plain: Array[int] = []
	for day: int in range(1, 301):
		plain.append(day)
	for day: int in first:
		assert_true(plain.has(day))


func test_arrival_tick_falls_inside_the_open_window() -> void:
	var chatty: InspectionTuning = TUNING.duplicate(true) as InspectionTuning
	chatty.daily_chance = 1.0
	for seed_value: int in 20:
		var book: InspectionBook = InspectionBook.new(chatty)
		book.plan_day(1, 3, OPEN_TICKS, _stream(seed_value))
		assert_true(book.planned_tick >= floori(OPEN_TICKS * chatty.arrival_from))
		assert_true(book.planned_tick <= floori(OPEN_TICKS * chatty.arrival_to))


func test_planning_the_same_morning_twice_draws_once() -> void:
	var chatty: InspectionTuning = TUNING.duplicate(true) as InspectionTuning
	chatty.daily_chance = 1.0
	var book: InspectionBook = InspectionBook.new(chatty)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 3
	book.plan_day(5, 3, OPEN_TICKS, func() -> RandomNumberGenerator: return random)
	var state: int = random.state
	var tick: int = book.planned_tick
	book.plan_day(5, 3, OPEN_TICKS, func() -> RandomNumberGenerator: return random)
	assert_eq(random.state, state, "a reloaded morning does not draw again")
	assert_eq(book.planned_tick, tick)


# --- The grade's effect on arrivals ----------------------------------------------

func test_the_arrival_effect_lasts_exactly_seven_days() -> void:
	for case: Array in [[&"A", 1.05], [&"B", 1.0], [&"C", 0.9]]:
		var book: InspectionBook = InspectionBook.new(TUNING)
		assert_almost_eq(book.arrival_factor(10), 1.0, 0.000001, "no grade yet")
		book.record(12, {"grade": case[0], "findings": []})
		assert_almost_eq(book.arrival_factor(12), 1.0, 0.000001, "the day itself is already over")
		for day: int in range(13, 20):
			assert_almost_eq(book.arrival_factor(day), float(case[1]), 0.000001, "%s on day %d" % [case[0], day])
		assert_almost_eq(book.arrival_factor(20), 1.0, 0.000001, "back to normal on the eighth day")
		assert_almost_eq(book.arrival_factor(11), 1.0, 0.000001)
		assert_eq(book.last_grade, case[0], "the card stays until the next inspection")


# --- Saving ---------------------------------------------------------------------

func test_the_grade_survives_a_save() -> void:
	var book: InspectionBook = InspectionBook.new(TUNING)
	book.record(12, {"grade": &"B", "findings": []})
	book.planned_day = 13
	book.planned_tick = 900
	var copy: InspectionBook = InspectionBook.new(TUNING)
	assert_true(copy.from_dict(JSON.parse_string(JSON.stringify(book.to_dict()))))
	assert_eq(copy.last_grade, &"B")
	assert_eq(copy.last_day, 12)
	assert_eq(copy.planned_day, 13)
	assert_eq(copy.planned_tick, 900)
	assert_eq(copy.to_dict(), book.to_dict())


func test_a_damaged_section_is_refused_whole() -> void:
	var good: Dictionary = {"version": 1, "last_grade": "A", "last_day": 4, "planned_day": 5, "planned_tick": -1}
	var book: InspectionBook = InspectionBook.new(TUNING)
	assert_true(book.from_dict(good))
	for change: Array in [["last_grade", "D"], ["last_grade", ""], ["last_day", 0], ["last_day", -1],
			["last_day", 2.5], ["version", 2], ["planned_tick", -2], ["planned_day", "x"], ["last_grade", 3]]:
		var bad: Dictionary = good.duplicate()
		bad[change[0]] = change[1]
		var fresh: InspectionBook = InspectionBook.new(TUNING)
		assert_false(fresh.from_dict(bad), str(change))
		assert_eq(fresh.last_grade, &"", "a refusal changes nothing")
	var extra: Dictionary = good.duplicate()
	extra["note"] = 1
	assert_false(InspectionBook.new(TUNING).from_dict(extra))
	assert_false(InspectionBook.new(TUNING).from_dict(7))


# --- The inspector in the shop ---------------------------------------------------

func test_the_inspector_walks_the_rooms_for_about_a_minute_then_leaves_and_grades() -> void:
	var sim: RestaurantSim = _service_sim()
	var day: int = sim.world.clock.day
	sim.inspection.planned_day = day
	sim.inspection.planned_tick = 5
	var done: Array[Dictionary] = []
	sim.inspection_done.connect(func(result: Dictionary) -> void: done.append(result))
	var seen: Dictionary[Vector2i, bool] = {}
	var first_tick: int = -1
	var last_tick: int = -1
	var inspector: InspectorAgent = null
	for tick: int in 3000:
		sim.advance()
		if sim.inspector != null:
			inspector = sim.inspector
			if inspector.movement_admitted:
				seen[inspector.cell] = true
				last_tick = sim.world.now
				first_tick = sim.world.now if first_tick < 0 else first_tick
			for guest: CustomerAgent in sim.customers():
				assert_ne(guest.id, inspector.id, "never a customer")
		elif inspector != null:
			break
	assert_not_null(inspector)
	assert_null(sim.inspector, "gone after the visit")
	assert_eq(done.size(), 1, "one grade")
	assert_eq(sim.inspection.last_day, day)
	assert_eq(sim.inspection.last_grade, done[0]["grade"])
	assert_true(seen.size() >= 6, "it really walked about: %d cells" % seen.size())
	var length: int = last_tick - first_tick
	assert_true(length >= TUNING.visit_ticks and length <= TUNING.visit_cap_ticks + 400, "ticks in the shop: %d" % length)
	assert_true(sim.world.agent(inspector.id) == null and sim.world.pending_agent(inspector.id) == null)


func test_the_inspector_never_orders_pays_or_counts_as_a_guest() -> void:
	var sim: RestaurantSim = _service_sim()
	sim.inspection.planned_day = sim.world.clock.day
	sim.inspection.planned_tick = 5
	var inspector_id: int = -1
	var finished: bool = false
	for tick: int in 3600:
		sim.advance()
		if sim.inspector != null:
			inspector_id = sim.inspector.id
		elif inspector_id > 0:
			finished = true
			break
	assert_true(finished)
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY,
			Order.State.DELIVERED, Order.State.CANCELLED]:
		for order: Order in sim.orders.orders_in_state(state):
			assert_ne(order.customer_id, inspector_id)
	assert_false(sim.leave_reasons_today.has(&"removed"), "not counted as a lost guest")


func test_the_inspector_leaves_when_the_shop_closes() -> void:
	var sim: RestaurantSim = _service_sim()
	sim.world.clock.open_ticks = 200
	sim.world.clock.last_orders_max_ticks = 40
	sim.inspection.planned_day = sim.world.clock.day
	sim.inspection.planned_tick = 20
	for tick: int in 400:
		sim.advance()
	assert_eq(sim.world.clock.phase, SimClock.Phase.CLOSED)
	assert_null(sim.inspector, "closing sends the inspector out")
	assert_eq(sim.inspection.last_day, sim.world.clock.day, "a cut-short visit is still graded")


func test_a_visit_never_blocks_the_shop_in_a_busy_day() -> void:
	# The same seeded day with and without a visit. The inspector shares cells
	# with real guests and staff, so outcomes may shift a little, but they still
	# serve nearly as many guests and never stall the shop.
	var plain: RestaurantSim = _service_sim()
	var visited: RestaurantSim = _service_sim()
	visited.inspection.planned_day = visited.world.clock.day
	visited.inspection.planned_tick = 100
	var was_there: bool = false
	var looked: int = 0
	var longest_still: int = 0
	var still: int = 0
	var last_cell: Vector2i = SimGrid.NO_CELL
	for tick: int in 3400:
		plain.advance()
		visited.advance()
		if visited.inspector != null:
			was_there = true
			looked = maxi(looked, visited.inspector.looked)
			if visited.inspector.cell == last_cell and visited.inspector.state != InspectorAgent.State.LOOKING:
				still += 1
				longest_still = maxi(longest_still, still)
			else:
				still = 0
			last_cell = visited.inspector.cell
	assert_true(was_there, "the inspector really came")
	assert_true(looked >= 2, "and looked at stops: %d" % looked)
	assert_null(visited.inspector)
	assert_true(longest_still < 300, "never stuck for long: %d ticks" % longest_still)
	assert_true(visited.served_today > 0)
	assert_true(visited.served_today >= plain.served_today - 3, "served %d vs %d" % [visited.served_today, plain.served_today])


func test_a_visit_that_reaches_no_stop_gives_no_grade_and_no_cooldown() -> void:
	var sim: RestaurantSim = _service_sim()
	sim.inspection.planned_day = sim.world.clock.day
	sim.inspection.planned_tick = 5
	for tick: int in 12:
		sim.advance()
	assert_not_null(sim.inspector)
	# Closing arrives before they have looked at anything.
	sim.world.clock.open_ticks = sim.world.clock.phase_tick + 1
	sim.world.clock.last_orders_max_ticks = 1
	for tick: int in 10:
		sim.advance()
	assert_null(sim.inspector)
	assert_eq(sim.inspection.last_day, 0, "no inspection happened")
	assert_eq(sim.inspection.last_grade, &"")
	assert_true(sim.inspection.can_visit(sim.world.clock.day + 1, 3), "and no cooldown started")


func test_a_cut_short_visit_is_graded_from_the_last_completed_stop() -> void:
	var sim: RestaurantSim = _service_sim()
	var tuning: CleanlinessTuning = CleanlinessTuning.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 9
	sim.cleanliness = CleanlinessState.new(sim.world.grid, tuning, random)
	var spots: Array[Vector2i] = InspectorAgent.choose_stops(sim.world.grid, sim.world.grid.entries()[0], 6)
	sim.inspection.planned_day = sim.world.clock.day
	sim.inspection.planned_tick = 5
	var looked_at_tick: int = -1
	for tick: int in 1500:
		sim.advance()
		if sim.inspector != null and sim.inspector.looked == 1 and looked_at_tick < 0:
			looked_at_tick = tick
			# Make the shop filthy after the first stop: it must not count.
			for spot: Vector2i in spots:
				sim.cleanliness.add_spill(spot)
			sim.world.clock.open_ticks = sim.world.clock.phase_tick + 1
			sim.world.clock.last_orders_max_ticks = 1
		if looked_at_tick >= 0 and sim.inspector == null:
			break
	assert_true(looked_at_tick >= 0)
	assert_eq(sim.inspection.last_day, sim.world.clock.day, "graded")
	for row: Dictionary in sim.inspection.last_result["findings"]:
		assert_ne(row["kind"], InspectionModel.FLOOR, "the mess made after the last stop is not counted")


func test_stops_avoid_the_door_lane_and_work_cells() -> void:
	var sim: RestaurantSim = _service_sim()
	var grid: SimGrid = sim.world.grid
	var from: Vector2i = grid.entries()[0]
	var stops: Array[Vector2i] = InspectorAgent.choose_stops(grid, from, 6)
	assert_true(stops.size() >= 3)
	var lane: Array[Vector2i] = ExteriorSupport.door_cells(grid)
	for stop: Vector2i in stops:
		for door: Vector2i in lane:
			assert_true(GridMath.octile(stop, door) > 1.5, "%s too near the door" % stop)
		for item: PlacedItem in grid.items():
			assert_false(item.work_cells.has(stop), "%s is a work cell" % stop)
		assert_true(grid.is_guest_reachable(from, stop))
		assert_true(grid.seat_items_at(stop).is_empty())


func test_hours_edited_in_the_morning_cannot_drop_a_planned_visit() -> void:
	var book: InspectionBook = InspectionBook.new(TUNING)
	book.planned_day = 4
	book.planned_tick = 3000
	assert_false(book.arriving(4, 100, 3600))
	assert_false(book.arriving(4, floori(1200 * TUNING.arrival_to) - 1, 1200), "before the shortened window's late edge")
	assert_true(book.arriving(4, floori(1200 * TUNING.arrival_to), 1200), "clamped into a 1200-tick day")
	assert_true(book.arriving(4, 3000, 3600))
	book.mark_arrived(4)
	assert_false(book.arriving(4, 3600, 3600), "once a day")


# --- Helpers --------------------------------------------------------------------

func _never_asked() -> RandomNumberGenerator:
	_asked += 1
	return null


func _stream(seed_value: int) -> Callable:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return func() -> RandomNumberGenerator: return random


func _visit_days(seed_value: int) -> Array[int]:
	var book: InspectionBook = InspectionBook.new(TUNING)
	var stream: Callable = _stream(seed_value)
	var days: Array[int] = []
	for day: int in range(1, 301):
		book.plan_day(day, 3, OPEN_TICKS, stream)
		if book.planned_tick >= 0:
			days.append(day)
			book.record(day, {"grade": &"A", "findings": []})
	return days


func _service_sim() -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 4, errors, stock)
	assert_eq(errors, [] as Array[String])
	sim.start_day()
	assert_true(sim.world.clock.start_service())
	return sim


## A shop with a kitchen and a few tables, with nothing dirty yet.
func _staged_sim() -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(SimGrid.new(Vector2i(10, 10)))
	sim.kitchen = Kitchen.new(sim, ContentDB.new(), Stock.new())
	var tuning: CleanlinessTuning = CleanlinessTuning.new()
	tuning.seat_departure_chance = 1.0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 302
	sim.cleanliness = CleanlinessState.new(sim.world.grid, tuning, random)
	return sim


func _make_messy(sim: RestaurantSim) -> void:
	var definition: ItemDef = ItemDef.new()
	definition.category = ItemDef.Category.TABLE
	definition.footprint = Vector2i.ONE
	definition.solid = true
	definition.seat_cells = [Vector2i.RIGHT]
	for index: int in 3:
		var table: PlacedItem = sim.world.grid.place_def(definition, Vector2i(1 + index * 3, 1))
		assert_not_null(table)
		sim.kitchen.mark_table_dirty(table.id)
	assert_true(sim.cleanliness.try_spawn_at_departed_seat(Vector2i(4, 6)))
	assert_true(sim.cleanliness.try_spawn_at_departed_seat(Vector2i(5, 6)))
