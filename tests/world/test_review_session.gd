extends TestCase
## FK-048: reviews travel through the real shop session, report, and morning save.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const ECONOMY_TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const REVIEW_TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const REVIEW_QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const SLOT: String = "review_session"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "review_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_providers.clear()
	for key: String in ["owner", "shop", "menu", "staff", "plates", "reviews"]:
		if SaveSystem._providers.has(key):
			_old_providers[key] = SaveSystem._providers[key].duplicate()


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	for key: String in ["owner", "shop", "menu", "staff", "plates", "reviews"]:
		if _old_providers.has(key):
			var provider: Dictionary = _old_providers[key]
			SaveSystem.register(key, provider["capture"], provider["restore"])
		else:
			SaveSystem._providers.erase(key)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_new_game_starts_at_three_stars_with_five_virtual_reviews() -> void:
	var main: Node = _start(false)
	var book: ReputationBook = main.get("reputation") as ReputationBook
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	assert_eq(book.scores(), [3, 3, 3, 3, 3])
	assert_eq(book.average(), 3.0)
	assert_true(sim.review_book == book)
	assert_true(sim.review_rng == GameState.rng(&"reviews"))
	assert_eq(sim.reputation_before_day, 3.0)
	assert_eq(sim.spawner.min_gap, ECONOMY_TUNING.arrival_gap_min)
	assert_eq(sim.spawner.max_gap, ECONOMY_TUNING.arrival_gap_max)


func test_departure_updates_report_but_not_the_current_morning_save() -> void:
	var main: Node = _start(true)
	assert_true(main.call("menu_set_restaurant_name", "Harbour Kitchen"))
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var book: ReputationBook = main.get("reputation") as ReputationBook
	var morning_file: String = FileAccess.get_file_as_string(_path())
	_certain_reviews(sim, book)
	assert_true(Clock.sim.start_service())
	_depart_unserved(sim, 86001)
	assert_eq(book.scores(), [3, 3, 3, 3, 3, 1])
	assert_eq(sim.reviews_today.size(), 1)
	var row: Dictionary = sim.reviews_today[0]
	assert_eq(row["stars"], 1)
	assert_false(String(row["quote"]).is_empty())
	assert_eq(row["before"], 3.0)
	assert_eq(row["after"], book.average())
	var report: DayReport = main.call("build_report", Clock.sim.day) as DayReport
	assert_eq(report.restaurant_name, "Harbour Kitchen")
	assert_eq(DayReport.from_dict(report.to_dict()).restaurant_name, "Harbour Kitchen")
	assert_eq(report.review_cards.size(), 1)
	assert_eq(report.review_cards[0]["stars"], 1)
	assert_eq(report.review_cards[0]["quote"], row["quote"])
	assert_eq(report.today_review_average, 1.0)
	assert_eq(report.reputation_before, 3.0)
	assert_eq(report.reputation_after, book.average())
	assert_eq(FileAccess.get_file_as_string(_path()), morning_file,
		"a review changes memory and the report, not the morning checkpoint")
	var saved_book: ReputationBook = ReputationBook.new()
	assert_true(saved_book.from_dict(_document()["data"]["reviews"]))
	assert_eq(saved_book.scores(), [3, 3, 3, 3, 3])


func test_closing_departure_neither_reviews_nor_draws_review_rng() -> void:
	var main: Node = _start(false)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var book: ReputationBook = main.get("reputation") as ReputationBook
	_certain_reviews(sim, book)
	var state: int = sim.review_rng.state
	var guest: CustomerAgent = CustomerAgent.new(sim, RandomNumberGenerator.new())
	guest.id = 86002
	guest.leave_reason = &"closing"
	sim.record_departure(guest)
	assert_eq(sim.reviews_today.size(), 0)
	assert_eq(book.scores(), [3, 3, 3, 3, 3])
	assert_eq(sim.review_rng.state, state)


func test_same_named_seed_replays_departure_reviews_and_quotes() -> void:
	var first: Node = _start(false)
	var first_rows: Array[Dictionary] = _seeded_departures(first, 86003)
	var first_scores: Array[int] = (first.get("reputation") as ReputationBook).scores()
	assert_true(first_rows.size() > 0, "the seeded service actually generated reviews")
	_close(first)
	var second: Node = _start(false)
	assert_eq(_seeded_departures(second, 86003), first_rows)
	assert_eq((second.get("reputation") as ReputationBook).scores(), first_scores)


func test_arrival_curve_is_sampled_before_first_gap_and_locked_for_the_day() -> void:
	var main: Node = _start(false)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var book: ReputationBook = main.get("reputation") as ReputationBook
	assert_true(book.from_dict({"version": 1, "scores": [5, 5, 5, 5, 5]}))
	var rate: float = book.arrival_multiplier(REVIEW_TUNING)
	var expected_min: int = maxi(1, roundi(float(ECONOMY_TUNING.arrival_gap_min) / rate))
	var expected_max: int = maxi(expected_min, roundi(float(ECONOMY_TUNING.arrival_gap_max) / rate))
	var expected_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	expected_rng.state = GameState.rng(&"customers").state
	var first_gap: int = expected_rng.randi_range(expected_min, expected_max)
	main.call("_begin_morning")
	assert_eq(sim.spawner.min_gap, expected_min)
	assert_eq(sim.spawner.max_gap, expected_max)
	assert_eq(int(sim.spawner.get("_remaining")), first_gap,
		"the first arrival uses today's rating, not yesterday's gap")
	assert_eq(GameState.rng(&"customers").state, expected_rng.state)
	assert_eq(sim.reputation_before_day, 5.0)
	_certain_reviews(sim, book)
	assert_true(Clock.sim.start_service())
	_depart_unserved(sim, 86004)
	assert_true(book.average() < 5.0)
	assert_eq(sim.spawner.min_gap, expected_min,
		"a review cannot change the active day's arrival rate")
	assert_eq(sim.spawner.max_gap, expected_max)
	assert_eq(int(sim.spawner.get("_remaining")), first_gap)


func test_next_morning_saves_reviews_and_trays_together_then_reloads_both() -> void:
	var first: Node = _start(true)
	var sim: RestaurantSim = first.get("sim") as RestaurantSim
	var book: ReputationBook = first.get("reputation") as ReputationBook
	Economy.add_cash(500, Ledger.OTHER)
	assert_true(first.call("tray_buy", 1))
	assert_eq(first.get("tray_level"), 1)
	assert_eq(sim.carry_capacity, 2)
	assert_eq(_document()["data"]["shop"]["tray_level"], 0.0,
		"a tray purchase does not rewrite the current morning checkpoint")
	_certain_reviews(sim, book)
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	_depart_unserved(sim, 86005)
	var morning_book: ReputationBook = ReputationBook.new()
	assert_true(morning_book.from_dict(_document()["data"]["reviews"]))
	assert_eq(morning_book.scores(), [3, 3, 3, 3, 3])
	first.call("run_ticks", 10)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(Clock.sim.next_day())
	var saved: Dictionary = book.to_dict()
	var loaded_book: ReputationBook = ReputationBook.new()
	assert_true(loaded_book.from_dict(_document()["data"]["reviews"]))
	assert_eq(loaded_book.to_dict(), saved)
	assert_eq(_document()["data"]["shop"]["tray_level"], 1.0)
	_close(first)
	GameState.new_run(999)
	var second: Node = _start(true)
	assert_eq(Clock.sim.day, 2)
	assert_eq((second.get("reputation") as ReputationBook).to_dict(), saved)
	assert_true((second.get("sim") as RestaurantSim).review_book == second.get("reputation"))
	assert_eq(second.get("tray_level"), 1)
	assert_eq((second.get("sim") as RestaurantSim).carry_capacity, 2)


func test_older_morning_save_without_reviews_starts_with_virtual_three_stars() -> void:
	var first: Node = _start(true)
	var document: Dictionary = _document()
	document["data"].erase("reviews")
	_write(document)
	_close(first)
	var second: Node = _start(true)
	assert_eq(Clock.sim.day, 1, "the old morning still loads")
	assert_eq((second.get("reputation") as ReputationBook).scores(), [3, 3, 3, 3, 3])
	assert_eq((second.get("reputation") as ReputationBook).average(), 3.0)


func _start(with_saves: bool) -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", with_saves)
	main.set("save_slot", SLOT)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")  # the test runner does not deliver _ready()
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _certain_reviews(sim: RestaurantSim, book: ReputationBook) -> void:
	var certain: ReviewTuning = REVIEW_TUNING.duplicate() as ReviewTuning
	certain.review_chance = 1.0
	sim.configure_reviews(book, certain, REVIEW_QUOTES, GameState.rng(&"reviews"))


func _depart_unserved(sim: RestaurantSim, id: int) -> void:
	var guest: CustomerAgent = CustomerAgent.new(sim, RandomNumberGenerator.new())
	guest.id = id
	guest.leave_reason = &"no_table"
	sim.record_departure(guest)
	sim.record_departure(guest)


func _seeded_departures(main: Node, seed: int) -> Array[Dictionary]:
	GameState.new_run(seed)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var book: ReputationBook = main.get("reputation") as ReputationBook
	sim.configure_reviews(book, REVIEW_TUNING, REVIEW_QUOTES, GameState.rng(&"reviews"))
	for index: int in range(32):
		_depart_unserved(sim, 87000 + index)
	return sim.reviews_today.duplicate(true)


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_path()))


func _write(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(_path() + ".bak"):
		assert_eq(DirAccess.remove_absolute(_path() + ".bak"), OK)
