extends TestCase
## Main owns the lazy named stream, morning save, live arrivals and event report (#325).

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const RUSH_TUNING: RushTuning = preload("res://data/balance/rush_hour.tres")
const SLOT: String = "rush_hour_session"

var _main: Node
var _old_dir: String
var _providers: Dictionary
var _window_start: int = -1
var _window_end: int = -1
var _window_arrivals: int = 0
var _hold_rush_guests: bool = false
var _held_guests: Array[CustomerAgent] = []


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start(saves: bool = false) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", saves)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _sim() -> RestaurantSim:
	return _main.get("sim") as RestaurantSim


func _progress() -> OwnerProgress:
	return _main.get("owner_progress") as OwnerProgress


func _level(level: int) -> void:
	_progress().award_bonus(_progress().threshold_for(level))
	_sim().set_customer_level(_progress().level)


func _morning(day: int) -> void:
	Clock.sim.day = day
	_main.call("_begin_morning")


func test_level_one_mornings_never_create_the_rush_stream_or_report_line() -> void:
	_start()
	for day: int in range(2, 9):
		_morning(day)
	assert_false((GameState._capture_save()["rngs"] as Dictionary).has("rush"))
	var report: DayReport = _main.call("build_report", Clock.sim.day) as DayReport
	assert_true(report.rush_hour_lines.is_empty())
	assert_false(report.to_dict().has("rush_hour_lines"))


func test_event_plan_and_rush_stream_survive_morning_autosave_without_reroll() -> void:
	_start(true)
	assert_true(_main.call("set_opening_hours", 360, 600), "Six to ten is a valid custom service")
	_level(2)
	var tuning: RushTuning = RUSH_TUNING.duplicate(true) as RushTuning
	tuning.daily_chance = 1.0
	_sim().rush_hour.tuning = tuning
	_morning(2)
	assert_true(_sim().rush_hour.has_event())
	var planned: Dictionary = _sim().rush_hour.to_dict()
	assert_true(_sim().rush_hour.start_minute >= 390)
	assert_true(_sim().rush_hour.start_minute + _sim().rush_hour.duration_minutes <= 540)
	assert_eq(_sim().rush_hour.occasion, _main.get_node("Overlay/MenuPanel").get("_rush_notice_text").split(":")[0])
	var first_stream_state: int = int(GameState.rng(&"rush").state)
	assert_true(_main.call("set_opening_hours", 600, 840), "A valid four-hour edit shifts today's rush into the new hours")
	assert_true(_sim().rush_hour.start_minute >= 630)
	assert_true(_sim().rush_hour.start_minute + _sim().rush_hour.duration_minutes <= 780)
	assert_eq(GameState.rng(&"rush").state, first_stream_state, "Editing hours never draws a new plan")
	planned = _sim().rush_hour.to_dict()
	# The next existing morning checkpoint persists both the edited hours and
	# the deterministically fitted plan; repeating it cannot consume RNG.
	_main.call("_begin_morning")
	assert_eq(_sim().rush_hour.to_dict(), planned)
	assert_eq(GameState.rng(&"rush").state, first_stream_state)
	var saved_path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(saved_path))
	var normalized_plan: Dictionary = JSON.parse_string(JSON.stringify(planned))
	assert_eq(document["data"]["rush_hour"], normalized_plan,
		"JSON whole numbers normalize to floats on load")
	var saved_stream_state: int = int(GameState.rng(&"rush").state)
	_close()
	_start(true)
	assert_eq(Clock.sim.display_open_minute, 600)
	assert_eq(Clock.sim.display_close_minute, 840)
	assert_eq(_sim().rush_hour.to_dict(), planned)
	assert_eq(GameState.rng(&"rush").state, saved_stream_state,
		"Restoring and entering the same morning cannot reroll the plan")
	assert_true(_sim().rush_hour.morning_notice().begins_with(_sim().rush_hour.occasion + ":"))


func test_live_spawner_uses_clock_ramp_and_records_real_arrival_cohort() -> void:
	var baseline: Dictionary = _run_fixed_gap_window(false)
	var busy: Dictionary = _run_fixed_gap_window(true)
	assert_eq(busy["prefix_rng_state"], baseline["prefix_rng_state"],
		"The same seed and legacy gap behavior reach the event boundary")
	assert_true(int(busy["arrivals"]) > int(baseline["arrivals"]),
		"Real sim arrivals increase within the identical event window")
	assert_eq(busy["cohort_arrivals"], busy["arrivals"],
		"Every actual headcount arrival inside the window is recorded")
	assert_eq(busy["outside_multiplier"], 1.0)
	assert_eq(busy["patience_increment_once"], true, "One late patience departure is counted once")
	assert_eq(busy["no_seat_increment_once"], true, "One late no-seat departure is counted once")
	assert_eq(busy["closing_excluded"], true, "Closing and unrelated departures stay outside rush losses")
	assert_eq(busy["report_lines"].size(), 1)
	assert_true(String(busy["report_lines"][0]).contains("Book club"))
	assert_true(String(busy["report_lines"][0]).contains("%d guests" % int(busy["arrivals"])))


func _run_fixed_gap_window(with_rush: bool) -> Dictionary:
	_start()
	var sim: RestaurantSim = _sim()
	sim.customer_types = null
	sim.spawner.min_gap = 60
	sim.spawner.max_gap = 60
	sim.spawner._remaining = 60
	_window_start = Clock.sim.display_open_minute + 30
	_window_end = _window_start + 45
	_window_arrivals = 0
	_held_guests.clear()
	_hold_rush_guests = with_rush
	sim.customer_arrived.connect(_on_window_customer_arrived)
	if with_rush:
		sim.rush_hour.rolled_day = Clock.sim.day
		sim.rush_hour.occasion = "Book club"
		sim.rush_hour.start_minute = _window_start
		sim.rush_hour.duration_minutes = 45
	assert_eq(sim.rush_multiplier(), 1.0, "Before service the factor is neutral")
	assert_true(Clock.sim.start_service())
	var tick_per_minute: int = Clock.sim.open_ticks \
		/ (Clock.sim.display_close_minute - Clock.sim.display_open_minute)
	var first_window_tick: int = (_window_start - Clock.sim.display_open_minute) * tick_per_minute
	var end_window_tick: int = (_window_end - Clock.sim.display_open_minute) * tick_per_minute
	var prefix_rng_state: int = 0
	var captured_prefix: bool = false
	for _tick: int in end_window_tick + 5:
		sim.advance()
		if not captured_prefix and Clock.sim.phase_tick >= first_window_tick:
			prefix_rng_state = int(GameState.rng(&"customers").state)
			captured_prefix = true
	var result: Dictionary = {"arrivals": _window_arrivals, "prefix_rng_state": prefix_rng_state,
		"cohort_arrivals": sim.rush_hour.cohort_arrivals,
		"outside_multiplier": sim.rush_hour.multiplier_at(_window_end)}
	if with_rush:
		assert_true(_held_guests.size() >= 3, "Hold three actual rush arrivals for post-window departures")
		var first: CustomerAgent = _held_guests[0]
		first.paid = false
		first.order = null
		first.leave_reason = &"waited_too_long"
		first.state = CustomerAgent.State.LEFT
		var prior_patience_losses: int = sim.rush_hour.cohort_lost_patience
		sim.world.remove_agent(first)
		sim.record_departure(first)
		var patience_count: int = sim.rush_hour.cohort_lost_patience
		assert_eq(patience_count, prior_patience_losses + 1)
		sim.record_departure(first)
		result["patience_increment_once"] = sim.rush_hour.cohort_lost_patience == patience_count
		var second: CustomerAgent = _held_guests[1]
		second.paid = false
		second.order = null
		second.leave_reason = &"no_table"
		second.state = CustomerAgent.State.LEFT
		var prior_no_seat_losses: int = sim.rush_hour.cohort_lost_no_seat
		sim.world.remove_agent(second)
		sim.record_departure(second)
		var no_seat_count: int = sim.rush_hour.cohort_lost_no_seat
		assert_eq(no_seat_count, prior_no_seat_losses + 1)
		sim.record_departure(second)
		result["no_seat_increment_once"] = sim.rush_hour.cohort_lost_no_seat == no_seat_count
		var closing: CustomerAgent = _held_guests[2]
		closing.paid = false
		closing.order = null
		closing.leave_reason = &"closing"
		closing.state = CustomerAgent.State.LEFT
		var before_closing_patience: int = sim.rush_hour.cohort_lost_patience
		var before_closing_no_seat: int = sim.rush_hour.cohort_lost_no_seat
		sim.world.remove_agent(closing)
		sim.record_departure(closing)
		assert_eq(sim.rush_hour.cohort_lost_patience, before_closing_patience)
		assert_eq(sim.rush_hour.cohort_lost_no_seat, before_closing_no_seat)
		var unrelated: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _seeded_rng(913))
		unrelated.paid = false
		unrelated.order = null
		unrelated.leave_reason = &"waited_too_long"
		unrelated.state = CustomerAgent.State.LEFT
		var before_unrelated_patience: int = sim.rush_hour.cohort_lost_patience
		sim.world.remove_agent(unrelated)
		sim.record_departure(unrelated)
		result["closing_excluded"] = sim.rush_hour.cohort_lost_no_seat == before_closing_no_seat \
			and sim.rush_hour.cohort_lost_patience == before_unrelated_patience
		var report: DayReport = _main.call("build_report", Clock.sim.day) as DayReport
		result["report_lines"] = report.rush_hour_lines.duplicate()
	_close()
	return result


func _on_window_customer_arrived(customer: CustomerAgent) -> void:
	var minute: int = Clock.sim.display_minutes()
	if minute < _window_start or minute >= _window_end:
		return
	_window_arrivals += 1
	if _hold_rush_guests and _held_guests.size() < 3:
		customer.queue_patience = 1000000
		customer.food_patience = 1000000
		customer.eat_ticks = 1000000
		_held_guests.append(customer)


func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
