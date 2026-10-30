extends TestCase
## FK-120: arrival_rate exposes morning-latched reputation demand.
## Existing Main also adjusts raw spawner gaps; that effect is separate.
## Two isolated fresh runs skip service and use the normal next-morning route.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SEED: int = 1

var _main: Node
var _old_providers: Dictionary[String, Dictionary] = {}
var _old_clock_processing: bool
var _old_speed: int


func before_each() -> void:
	_old_providers = SaveSystem._providers.duplicate(true)
	_old_clock_processing = Clock.is_processing()
	_old_speed = Clock.speed
	Clock.set_process(false)
	Clock.set_speed(0)


func after_each() -> void:
	_close_main()
	SaveSystem._providers = _old_providers
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_speed(_old_speed)
	Clock.set_process(_old_clock_processing)


func test_arrival_rate_exposes_morning_latched_reputation_in_matched_runs() -> void:
	var neutral: Dictionary = _sample_second_morning(3)
	if neutral.is_empty():
		return
	# The first Main has been removed/freed before the second is instantiated.
	var low: Dictionary = _sample_second_morning(1)
	if low.is_empty():
		return
	# Existing APIs prove the two day-2 contexts agree except for reputation.
	# No service happened, so no happy renown can accrue under the accepted plan.
	assert_eq(low["context"], neutral["context"], "matched day/menu/vibe/owner/weather")
	if low["context"] != neutral["context"]:
		return
	var neutral_rate: float = float(neutral["rate"])
	var low_rate: float = float(low["rate"])
	assert_true(is_finite(neutral_rate) and neutral_rate > 0.0, "valid neutral rate")
	assert_true(is_finite(low_rate) and low_rate > 0.0, "valid low-reputation rate")
	if not is_finite(neutral_rate) or neutral_rate <= 0.0 or not is_finite(low_rate) or low_rate <= 0.0:
		return
	print("DEMAND_RED_COMPARE neutral=%s low=%s context_equal=%s" % [
		neutral_rate, low_rate, low["context"] == neutral["context"]])
	# INTENDED semantic RED: actual8fbe returns VisitTuning1.0 for both arms.
	# Day-2 poor vibe can reduce BOTH rates in GREEN; it cannot satisfy this
	# reputation-specific comparison on its own. No fixed day-2 total is assumed.
	assert_true(low_rate < neutral_rate,
		"arrival_rate must expose the lower morning-latched reputation demand")


func _sample_second_morning(stars: int) -> Dictionary:
	assert_true(stars == 1 or stars == 3, "fixture supports only declared arms")
	if stars != 1 and stars != 3:
		return {}
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", SEED)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")  # Existing runner never delivers _ready().
	_main.set_process(false)
	Clock.set_speed(0)
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var book: ReputationBook = _main.get("reputation") as ReputationBook
	var menu: MenuSettings = _main.get("menu_settings") as MenuSettings
	var owner: OwnerProgress = _main.get("owner_progress") as OwnerProgress
	assert_not_null(sim, "Main created its real restaurant")
	assert_not_null(book, "Main owns a real reputation book")
	assert_not_null(menu, "Main created menu choices")
	assert_not_null(owner, "Main created owner progress")
	if sim == null or book == null or menu == null or owner == null:
		return _invalid_sample()
	assert_true(sim.world != null and sim.world.clock == Clock.sim, "real world clock bound")
	if sim.world == null or sim.world.clock != Clock.sim:
		return _invalid_sample()
	assert_eq(Clock.sim.day, 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(book.scores(), [3, 3, 3, 3, 3])
	assert_true(sim.review_book == book, "Main and sim share the installed book")
	if Clock.sim.day != 1 or Clock.sim.phase != SimClock.Phase.MORNING \
			or sim.review_book != book or book.scores() != [3, 3, 3, 3, 3]:
		return _invalid_sample()
	assert_eq(menu.enabled_count(), 3)
	assert_eq(sim.visit_kinds(), [RecipeDef.FOOD])
	assert_almost_eq(sim.arrival_rate(), 1.0, 0.0001, "neutral day-1 baseline control")
	if menu.enabled_count() != 3 or sim.visit_kinds() != [RecipeDef.FOOD] \
			or not is_finite(sim.arrival_rate()) or absf(sim.arrival_rate() - 1.0) > 0.0001:
		return _invalid_sample()
	if stars == 1:
		var installed: bool = book.from_dict({"version": 1, "scores": [1, 1, 1, 1, 1]})
		assert_true(installed, "legal low reputation installs through existing decoder")
		if not installed:
			return _invalid_sample()
	# This is a disclosed morning-transition fixture, not a played service day.
	# It matches the existing weather persistence test's real next-day route.
	Clock.sim.phase = SimClock.Phase.CLOSED
	var advanced: bool = Clock.sim.next_day()
	assert_true(advanced, "next_day succeeds from CLOSED")
	if not advanced:
		return _invalid_sample()
	assert_eq(Clock.sim.day, 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_almost_eq(book.average(), float(stars), 0.0001)
	assert_almost_eq(sim.reputation_before_day, float(stars), 0.0001,
		"phase signal reached Main morning/start_day with the intended book")
	assert_true(sim.review_book == book)
	assert_true(sim.vibe_result.valid, "derive actual layout vibe, not default invalid zero")
	assert_almost_eq(sim.vibe_result.score, 0.0, 0.0001, "actual authored starter vibe")
	assert_eq(sim.visit_kinds(), [RecipeDef.FOOD])
	assert_true(sim.visit_tuning != null and sim.visit_tuning.is_valid())
	if Clock.sim.day != 2 or Clock.sim.phase != SimClock.Phase.MORNING \
			or absf(book.average() - float(stars)) > 0.0001 \
			or absf(sim.reputation_before_day - float(stars)) > 0.0001 \
			or sim.review_book != book or not sim.vibe_result.valid \
			or absf(sim.vibe_result.score) > 0.0001 or sim.visit_kinds() != [RecipeDef.FOOD] \
			or sim.visit_tuning == null or not sim.visit_tuning.is_valid():
		return _invalid_sample()
	var visit_rate: float = sim.visit_tuning.arrival_rate(sim.visit_kinds(), Clock.sim.display_minutes())
	assert_almost_eq(visit_rate, 1.0, 0.0001, "food-only full-weight hour, separate from demand")
	if not is_finite(visit_rate) or absf(visit_rate - 1.0) > 0.0001:
		return _invalid_sample()
	var menu_ids: Array[StringName] = []
	for recipe: RecipeDef in menu.enabled_recipes():
		menu_ids.append(recipe.id)
	var sample: Dictionary = {
		"rate": sim.arrival_rate(),
		"book_average": book.average(), "latched_reputation": sim.reputation_before_day,
		"book_identity": sim.review_book == book,
		"context": {"day": Clock.sim.day, "phase": Clock.sim.phase,
			"minute": Clock.sim.display_minutes(), "open": Clock.sim.display_open_minute,
			"close": Clock.sim.display_close_minute, "tick": Clock.sim.tick,
			"menu_ids": menu_ids, "menu_count": menu.enabled_count(),
			"visit_kinds": sim.visit_kinds(), "visit_rate": visit_rate,
			"vibe_valid": sim.vibe_result.valid, "vibe_score": sim.vibe_result.score,
			"owner_level": owner.level, "property_tier": owner.property_tier,
			"weather": sim.world.weather.to_dict()},
		# Diagnostic context only: never assert old gap numbers in GREEN.
		"existing_gap_min": sim.spawner.min_gap, "existing_gap_max": sim.spawner.max_gap,
	}
	print("DEMAND_RED_ARM stars=%d snapshot=%s" % [stars, JSON.stringify(sample)])
	_close_main()
	return sample


func _invalid_sample() -> Dictionary:
	_close_main()
	return {}


func _close_main() -> void:
	if not is_instance_valid(_main):
		_main = null
		return
	if _main.is_inside_tree():
		_main.get_parent().remove_child(_main)
	_main.free()
	_main = null

# End of initial existing-API session regression prefix.

# Integration coverage below deliberately retains the accepted RED above byte-for-byte.
const DEMAND_SLOT: String = "demand_session"
var _demand_old_dir: String
var _demand_dir: String
var _late_reject_reached: bool = false
var _late_reject_staged: bool = false


func test_paid_food_and_drink_award_one_complete_happy_departure_once_at_close() -> void:
	_start_demand(false)
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var state: DemandState = _main.get("demand_state") as DemandState
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 104
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random)
	guest.order = Order.new()
	guest.order.price = 12
	guest.order.recipe_id = sim.menu[0].id
	guest.extra_order = Order.new()
	guest.extra_order.price = 5
	guest.extra_order.state = Order.State.DELIVERED
	var cash: int = Economy.cash
	sim.pay(guest, guest.order)
	sim.pay(guest, guest.order)
	assert_eq(Economy.cash - cash, 17, "both actual payment events were delivered once")
	assert_almost_eq(state.renown, 0.0, 0.00001, "payment alone is not a completed visit")
	guest.leave_reason = &"happy"
	sim.record_departure(guest)
	sim.record_departure(guest)
	assert_eq(sim.leave_reasons_today.get(&"happy"), 1)
	assert_almost_eq(state.renown, 0.0, 0.00001, "renown waits for complete service close")
	Clock.sim.phase = SimClock.Phase.CLOSED
	sim.service_closed.emit(1)
	sim.service_closed.emit(1)
	assert_almost_eq(state.renown, 1.0)
	assert_eq(state.last_award_day, 1)
	assert_true(Clock.sim.next_day())
	assert_almost_eq(state.renown, 0.95)
	_main.call("_begin_morning")
	assert_almost_eq(state.renown, 0.95, 0.00001, "same morning never decays twice")
	_finish_demand()


func test_morning_save_restores_renown_and_guards_without_reapplying_decay() -> void:
	_start_demand(true)
	var state: DemandState = _main.get("demand_state") as DemandState
	state.renown = 100.0
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	sim.leave_reasons_today[&"happy"] = 20
	var initial_file: String = FileAccess.get_file_as_string(_demand_path())
	Clock.sim.phase = SimClock.Phase.CLOSED
	sim.service_closed.emit(1)
	assert_almost_eq(state.renown, 120.0)
	assert_eq(FileAccess.get_file_as_string(_demand_path()), initial_file, "close awards never save")
	assert_true(Clock.sim.next_day())
	assert_almost_eq(state.renown, 114.0)
	var expected: Dictionary = state.to_dict()
	var expected_demand: Dictionary = _main.call("current_demand_snapshot")
	assert_eq(_demand_document()["data"]["demand"], _json_value(expected))
	_close_main()
	_start_demand(true, false)
	assert_eq((_main.get("demand_state") as DemandState).to_dict(), expected)
	assert_eq(_main.call("current_demand_snapshot"), expected_demand)
	_main.call("_begin_morning")
	assert_eq((_main.get("demand_state") as DemandState).to_dict(), expected)
	_finish_demand()


func test_missing_legacy_demand_starts_at_saved_day_without_retroactive_decay() -> void:
	_start_demand(true)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	var legacy: Dictionary = _demand_document()
	legacy["data"].erase("demand")
	_write_demand_document(legacy)
	_close_main()
	_start_demand(true, false)
	var state: DemandState = _main.get("demand_state") as DemandState
	assert_eq(Clock.sim.day, 2)
	assert_eq(state.day, 2)
	assert_eq(state.last_decay_day, 2)
	assert_eq(state.last_award_day, 0)
	assert_almost_eq(state.renown, 0.0)
	assert_eq(_demand_document()["data"]["demand"], _json_value(state.to_dict()))
	_finish_demand()


func test_malformed_or_wrong_day_present_demand_fails_load_and_preserves_checkpoint() -> void:
	_start_demand(true)
	var valid: Dictionary = _demand_document()
	for patch: Dictionary in [{"renown": -1}, {"day": 2, "last_decay_day": 2},
		{"last_award_day": 1, "last_service_day": 1, "last_service_factor": 1.0}]:
		var broken: Dictionary = valid.duplicate(true)
		(broken["data"]["demand"] as Dictionary).merge(patch, true)
		_write_demand_document(broken)
		var bad_file: String = FileAccess.get_file_as_string(_demand_path())
		_close_main()
		_start_demand(true, false)
		assert_eq(Clock.sim.day, 1)
		assert_almost_eq((_main.get("demand_state") as DemandState).renown, 0.0)
		assert_null(_main.get("_loaded_demand"))
		assert_eq(FileAccess.get_file_as_string(_demand_path()), bad_file)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_eq(_demand_document()["data"]["demand"]["day"], 2.0, "later morning autosaves resume")
	_finish_demand()


func test_later_whole_load_failure_discards_staged_renown_before_new_session() -> void:
	_start_demand(true)
	var doc: Dictionary = _demand_document()
	doc["data"]["demand"]["renown"] = 900.0
	doc["data"]["demand_test_reject"] = {}
	SaveSystem.register("demand_test_reject", _demand_empty_capture, _reject_after_demand)
	_write_demand_document(doc)
	var failed_file: String = FileAccess.get_file_as_string(_demand_path())
	_close_main()
	_start_demand(true, false)
	assert_true(_late_reject_reached)
	assert_true(_late_reject_staged, "a real later provider rejected after valid demand was staged")
	assert_null(_main.get("_loaded_demand"))
	assert_almost_eq((_main.get("demand_state") as DemandState).renown, 0.0)
	assert_eq(FileAccess.get_file_as_string(_demand_path()), failed_file)
	assert_almost_eq((_main.call("current_demand_snapshot") as Dictionary)["total"], 1.0)
	_finish_demand()


func test_forecast_is_detached_projects_one_decay_and_never_advances_rng_or_saves() -> void:
	_start_demand(true)
	var state: DemandState = _main.get("demand_state") as DemandState
	state.renown = 120.0
	var before: Dictionary = _demand_readonly_snapshot()
	var first: Dictionary = _main.call("forecast_next_demand")
	assert_eq(first.get("day"), 2)
	# 120 * .95 = 114; tomorrow's actual starter vibe has no intro grace.
	assert_almost_eq(float(first.get("word_of_mouth", 0)), 1.0 + 0.8 * 114.0 / 204.0)
	assert_almost_eq(float(first.get("vibe", 0)), 0.9)
	# Real authored opening is 3600 ticks and mean gap is (100 + 260) / 2.
	# Food has full hourly weight: round(20 * .9 * (1 + .8 * 114 / 204)) = 26.
	assert_eq(first.get("expected_guests"), 26)
	var expected: Dictionary = first.duplicate(true)
	first["total"] = 999.0
	first["day"] = 999
	for repeat: int in 3:
		assert_eq(_main.call("forecast_next_demand"), expected)
		var report: DayReport = _main.call("build_report", 1) as DayReport
		assert_eq(report.demand_forecast, expected)
		report.demand_forecast["total"] = 888.0
		assert_eq(_demand_readonly_snapshot(), before)
	assert_false((GameState.call("_capture_save") as Dictionary)["rngs"].has("demand"))
	_finish_demand()


func test_accepted_menu_actions_refresh_live_factor_without_redrawing_gap_or_saving() -> void:
	_start_demand(true)
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var countdown: int = sim.spawner._remaining
	var streams: Dictionary = GameState.call("_capture_save")
	var saved: String = FileAccess.get_file_as_string(_demand_path())
	var menu: MenuSettings = _main.get("menu_settings") as MenuSettings
	# Explicit legal level-two unlock fixture; the real accepted action below
	# chooses a fourth dish that the starter stove/prep already supports.
	var owner: OwnerProgress = _main.get("owner_progress") as OwnerProgress
	owner.award_bonus(owner.threshold_for(2))
	assert_true(menu.set_owner_level(owner.level))
	assert_true(_main.call("menu_set_enabled", &"tomato_melt", true))
	assert_eq(menu.enabled_count(), 4)
	assert_almost_eq(sim.demand_factor, 1.04)
	assert_true(_main.call("menu_set_enabled", &"tomato_melt", true))
	assert_almost_eq(sim.demand_factor, 1.04, 0.00001, "a unique dish counts once")
	assert_true(_main.call("menu_set_price", &"burger", 15))
	assert_eq(sim.spawner._remaining, countdown)
	assert_eq(GameState.call("_capture_save"), streams)
	assert_eq(FileAccess.get_file_as_string(_demand_path()), saved)
	var detached: Dictionary = _main.call("current_demand_snapshot")
	detached["total"] = 999.0
	assert_almost_eq(sim.demand_factor, 1.04)
	assert_almost_eq((_main.call("current_demand_snapshot") as Dictionary)["total"], 1.04)
	assert_true(_main.call("menu_set_enabled", &"tomato_melt", false))
	assert_almost_eq(sim.demand_factor, 1.0)
	assert_eq(sim.spawner._remaining, countdown)
	assert_eq(GameState.call("_capture_save"), streams)
	assert_eq(FileAccess.get_file_as_string(_demand_path()), saved)
	_finish_demand()


func test_morning_reputation_and_renown_remain_latched_during_edit_refresh() -> void:
	_start_demand(false)
	var state: DemandState = _main.get("demand_state") as DemandState
	var book: ReputationBook = _main.get("reputation") as ReputationBook
	assert_true(book.from_dict({"version": 1, "scores": [1, 1, 1, 1, 1]}))
	state.renown = 60.0
	_main.call("_recompute_vibe")
	var current: Dictionary = _main.call("current_demand_snapshot")
	assert_almost_eq(float(current["reputation"]), 1.0)
	assert_almost_eq(float(current["word_of_mouth"]), 1.0)
	assert_almost_eq(float(current["total"]), 1.0)
	var tomorrow: Dictionary = _main.call("forecast_next_demand")
	assert_almost_eq(float(tomorrow["reputation"]), 0.6)
	assert_almost_eq(float(tomorrow["word_of_mouth"]), 1.0 + 0.8 * 57.0 / 147.0)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	current = _main.call("current_demand_snapshot")
	assert_almost_eq(float(current["reputation"]), 0.6)
	assert_almost_eq(float(current["word_of_mouth"]), 1.0 + 0.8 * 57.0 / 147.0)
	_finish_demand()


func test_accepted_layout_edit_updates_actual_raw_vibe_without_rng_gap_reset_or_save() -> void:
	_start_demand(true)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	assert_almost_eq(sim.demand_factor, 0.9)
	var countdown: int = sim.spawner._remaining
	var streams: Dictionary = GameState.call("_capture_save")
	var saved: String = FileAccess.get_file_as_string(_demand_path())
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	editor.set_owner_level(2) # Explicit purchase-unlock fixture, as in vibe session tests.
	assert_true(_main.call("shop_buy", &"potted_plant", Vector2i(11, 9), 0))
	assert_true(sim.vibe_result.valid)
	assert_true(sim.vibe_result.score > 0.0)
	assert_almost_eq(sim.demand_factor, 0.9 + 0.25 * sim.vibe_result.score / 100.0)
	assert_true(sim.demand_factor > 0.9)
	assert_eq(sim.spawner._remaining, countdown)
	assert_eq(GameState.call("_capture_save"), streams)
	assert_eq(FileAccess.get_file_as_string(_demand_path()), saved)
	_finish_demand()


func _start_demand(saves: bool, fresh_directory: bool = true) -> void:
	if fresh_directory:
		_demand_old_dir = SaveSystem.save_dir
		_demand_dir = SaveTestPaths.case_dir(OS.get_process_id(), DEMAND_SLOT)
		SaveSystem.save_dir = _demand_dir
		SaveSystem.delete_slot(DEMAND_SLOT)
	_main = MAIN.instantiate()
	_main.set("use_saves", saves)
	_main.set("skip_owner_picker", true)
	_main.set("save_slot", DEMAND_SLOT)
	_main.set("new_game_seed_override", SEED)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_speed(0)


func _finish_demand() -> void:
	_close_main()
	SaveSystem.delete_slot(DEMAND_SLOT)
	DirAccess.remove_absolute(_demand_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _demand_old_dir


func _demand_path() -> String:
	return _demand_dir.path_join(DEMAND_SLOT + ".json")


func _demand_document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_demand_path())) as Dictionary


func _write_demand_document(doc: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_demand_path(), FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify(doc))
		file.close()
	DirAccess.remove_absolute(_demand_path() + ".bak")


func _json_value(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _demand_readonly_snapshot() -> Dictionary:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	return {"state": (_main.get("demand_state") as DemandState).to_dict(),
		"clock": Clock.sim.to_dict(), "world_tick": sim.world.now,
		"rngs": GameState.call("_capture_save"), "weather": sim.world.weather.to_dict(),
		"factor": sim.demand_factor, "countdown": sim.spawner._remaining,
		"economy": Economy.call("_capture_save"), "save": FileAccess.get_file_as_string(_demand_path())}


func _demand_empty_capture() -> Dictionary:
	return {}


func _reject_after_demand(_value: Dictionary) -> bool:
	_late_reject_reached = true
	var staged: DemandState = _main.get("_loaded_demand") as DemandState
	_late_reject_staged = staged != null and staged.day == 1 and staged.renown == 900.0
	return false


# Actual complete default Main day 1, seed 1, observed from immutable commit
# 8fbe652826c34333e6b7b51f63ede116901582f9. Full signed raw tick/event
# evidence is retained outside the project in issue247/day1-trace.
const DAY_ONE_EVENTS_SHA256: String = "89306e8b88e412022c872117b73ce9a2b89a2df664790a4b48256b9599c1ba7a"
const DAY_ONE_STREAMS: Dictionary = {
	"master_seed": "1",
	"rngs": {
		"cleanliness": {
			"seed": "2378578401",
			"state": "4204680873151375338"
		},
		"customers": {
			"seed": "232337077",
			"state": "-1878107458494558784"
		},
		"hiring": {
			"seed": "524528529",
			"state": "-4869216818992773893"
		},
		"reviews": {
			"seed": "7543029",
			"state": "7930172525103179214"
		},
		"weather": {
			"seed": "2145409216",
			"state": "-6132081484579833548"
		}
	}
}
var _trace_events: Array[Dictionary] = []


func test_actual_default_day_one_events_private_seeds_and_every_named_stream_match_8fbe() -> void:
	var first: Dictionary = _played_day_one()
	var repeated: Dictionary = _played_day_one()
	assert_eq(first, repeated, "complete actual service repeats from its master seed")
	assert_eq(first["streams"], DAY_ONE_STREAMS, "every created named stream, including absent extra streams")
	assert_eq(first["events_sha256"], DAY_ONE_EVENTS_SHA256,
		"actual arrival/payment/departure ticks and signed private RNG seeds/states match immutable8fbe")
	assert_eq(first["tick"], 4500)
	assert_eq(first["served"], 17)
	assert_eq(first["lost"], 1)
	assert_eq(first["happy"], 17)
	assert_almost_eq(float(first["renown"]), 17.0, 0.00001, "new progress accrues only after unchanged service")


func _played_day_one() -> Dictionary:
	_trace_events.clear()
	_start_demand(false)
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	sim.customer_arrived.connect(_demand_trace_arrived)
	sim.customer_paid.connect(_demand_trace_paid)
	sim.customer_left.connect(_demand_trace_left)
	assert_almost_eq(sim.demand_factor, 1.0)
	assert_true(sim.vibe_result.valid)
	assert_almost_eq(sim.vibe_result.score, 0.0)
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 5000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(sim.customers().is_empty())
	var result: Dictionary = {"streams": GameState.call("_capture_save"),
		"events_sha256": JSON.stringify(_trace_events, "", true, true).sha256_text(),
		"events": _trace_events.duplicate(true), "tick": Clock.sim.tick,
		"served": sim.served_today, "lost": sim.lost_today,
		"happy": sim.leave_reasons_today.get(&"happy", 0),
		"renown": (_main.get("demand_state") as DemandState).renown,
		"books": Economy.call("_capture_save"), "stock": sim.stock.to_dict(),
		"scores": sim.review_book.scores(), "log": sim.world.event_log.duplicate()}
	sim.customer_arrived.disconnect(_demand_trace_arrived)
	sim.customer_paid.disconnect(_demand_trace_paid)
	sim.customer_left.disconnect(_demand_trace_left)
	_finish_demand()
	return result


func _demand_trace_arrived(guest: CustomerAgent) -> void:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	_trace_events.append({"event": "arrived", "tick": sim.world.now, "id": guest.id,
		"private_seed": str(guest.rng.seed), "private_state": str(guest.rng.state),
		"kind": String(guest.customer_type_id), "visit": String(guest.visit_kind),
		"party": guest.party.member_ids.duplicate() if guest.party != null else []})


func _demand_trace_paid(guest: CustomerAgent, order: Order, amount: int) -> void:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	_trace_events.append({"event": "paid", "tick": sim.world.now, "id": guest.id,
		"order": order.id, "recipe": String(order.recipe_id), "amount": amount})


func _demand_trace_left(guest: CustomerAgent, reason: StringName) -> void:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	_trace_events.append({"event": "left", "tick": sim.world.now, "id": guest.id,
		"reason": String(reason), "private_seed": str(guest.rng.seed), "private_state": str(guest.rng.state)})
