extends TestCase
## Exercise the production close/presentation/morning and whole-load boundaries.
## Currency expectations come from the actual report, not an economic golden.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "business_history_session"
const REJECT_SECTION: String = "business_history_test_reject"

var _main: Node
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary[String, Dictionary] = {}
var _old_clock_processing: bool
var _old_speed: int
var _preferences: SettingsPreferences
var _old_preferences: Dictionary = {}
var _reject_reached: bool = false
var _reject_staged: bool = false
var _reject_live_empty: bool = false
var _expected_staged: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate(true)
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_clock_processing = Clock.is_processing()
	_old_speed = Clock.speed
	Clock.set_process(false)
	Clock.set_speed(0)
	_preferences = (Engine.get_main_loop() as SceneTree).root.get_node("Preferences") as SettingsPreferences
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save"]:
		_old_preferences[key] = _preferences.get(key)
	_preferences.set("_file_path", _save_dir.path_join("preferences.cfg"))
	_preferences.set("_disk_enabled", false)
	_preferences.set("_pending_volume_save", false)
	_reject_reached = false
	_reject_staged = false
	_reject_live_empty = false
	_expected_staged = {}


func after_each() -> void:
	_close_main()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers = _old_providers
	for key: String in _old_preferences:
		_preferences.set(key, _old_preferences[key])
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_speed(_old_speed)
	Clock.set_process(_old_clock_processing)


func test_actual_close_records_final_report_and_report_queries_remain_pure() -> void:
	_start_main()
	var morning: String = _saved_text()
	var before: Dictionary = _observable_state()
	_main.call("build_report", Clock.sim.day)
	_main.call("build_report", Clock.sim.day)
	assert_eq(_observable_state(), before, "morning report previews cannot create history or save")
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var payments: Dictionary[StringName, Array] = {}
	sim.customer_paid.connect(func(_customer: CustomerAgent, order: Order, _cents: int) -> void:
		if not payments.has(order.recipe_id):
			payments[order.recipe_id] = []
		payments[order.recipe_id].append(order.quality))
	var diners: Dictionary[StringName, Array] = {}
	var recipes: Array[RecipeDef] = sim.menu.duplicate()
	var tuning: ReviewTuning = sim.review_tuning
	sim.customer_left.connect(func(customer: CustomerAgent, _reason: StringName) -> void:
		var standard_price: int = 0
		for recipe: RecipeDef in recipes:
			if customer.order != null and recipe.id == customer.order.recipe_id:
				standard_price = recipe.standard_price
		var visit: ReviewVisit = customer.review_visit(standard_price, customer.arrival_dirt_fraction)
		var stars: int = ReputationBook.score_visit(visit, tuning, RestaurantSim.VIBE_TUNING, true)
		for id: StringName in visit.consumed_recipe_ids:
			if not diners.has(id):
				diners[id] = []
			diners[id].append(stars >= 4))
	var report: DayReport = _finish_service()
	if report == null:
		return
	assert_eq(_history().summaries().size(), 1, "the real close records exactly one finalized day")
	_assert_matches(_history().summaries()[0], report)
	var week: Dictionary[StringName, Dictionary] = _history().dish_week(Clock.sim.day)
	assert_false(payments.is_empty(), "the default service fixture makes real paid sales")
	assert_false(diners.is_empty(), "the default service fixture includes completed visits")
	assert_eq(week.size(), payments.size())
	for id: StringName in payments:
		var qualities: Array = payments[id]
		var satisfaction: Array = diners.get(id, [])
		var entry: Dictionary = week.get(id, {})
		assert_eq(entry.get("sold"), qualities.size())
		var sum: float = 0.0
		for quality: float in qualities:
			sum += quality
		assert_almost_eq(float(entry.get("quality_sum", -1.0)), sum)
		assert_eq(entry.get("eaten"), satisfaction.size())
		assert_eq(entry.get("happy"), satisfaction.count(true))
	assert_eq(_saved_text(), morning, "closing records memory only, preserving the morning checkpoint")
	var old_cash_change: int = report.profit()
	# A bookkeeping fixture makes a query-only regression observable: a report
	# can see changed books before a presentation or Next day refresh records it.
	Economy.add_cash(-7, Ledger.UPGRADES)
	before = _observable_state()
	var preview: DayReport = _main.call("build_report", Clock.sim.day) as DayReport
	assert_not_null(preview)
	if preview != null:
		assert_eq(preview.profit(), old_cash_change - 7)
	assert_eq(_observable_state(), before, "build_report cannot upsert history, advance state or save")
	assert_eq(_history().summaries()[0]["cash_change"], old_cash_change)
	assert_eq(_main.get("shown_report"), report, "a query does not replace the presented report")


func test_paid_party_members_credit_their_own_dishes_and_satisfaction() -> void:
	_start_main()
	assert_true(Clock.sim.start_service())
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var party: Party = Party.new()
	party.member_ids = [1001, 1002]
	var happy: CustomerAgent = _paid_dish_guest(sim, 1001)
	happy.party = party
	happy.extra_order = _delivered_dish(&"coffee", 0.5)
	sim.pay(happy, happy.order)
	sim.record_departure(happy)
	sim.record_departure(happy)
	var unhappy: CustomerAgent = _paid_dish_guest(sim, 1002)
	unhappy.party = party
	# Two orders of the same recipe count as two sales and one diner.
	unhappy.extra_order = _delivered_dish(&"burger", 1.0)
	unhappy._queue_wait = unhappy.queue_patience - 1
	unhappy._food_wait = unhappy.food_patience - 1
	sim.pay(unhappy, unhappy.order)
	sim.record_departure(unhappy)
	assert_eq(unhappy.leave_reason, &"happy", "a paid departure reason does not measure satisfaction")
	var takeaway: CustomerAgent = _paid_dish_guest(sim, 1003)
	takeaway.takeaway = true
	sim.pay(takeaway, takeaway.order)
	sim.record_departure(takeaway)
	assert_eq(_history().dish_week(1), {}, "the dashboard snapshots only closed service")
	var cutoff: CustomerAgent = _paid_dish_guest(sim, 1004)
	sim.pay(cutoff, cutoff.order)
	var written_reviews: int = sim.reviews_today.size()
	# Exercise cutoff departure separately from the real closing test.
	Clock.sim.phase = SimClock.Phase.CLOSED
	sim.record_departure(cutoff)
	assert_eq(sim.reviews_today.size(), written_reviews, "closing still suppresses written reviews")
	var report: DayReport = _main.call("build_report", 1) as DayReport
	assert_eq(report.dish_metrics[&"burger"],
		{"sold": 5, "quality_sum": 4.0, "eaten": 3, "happy": 2})
	assert_eq(report.dish_metrics[&"coffee"],
		{"sold": 1, "quality_sum": 0.5, "eaten": 1, "happy": 1})


func test_two_service_days_keep_dish_metrics_separate() -> void:
	_start_main()
	var first: DayReport = _finish_service()
	if first == null:
		return
	assert_true(not first.dish_metrics.is_empty(), "the first service must sell a dish")
	assert_true(Clock.sim.next_day())
	var second: DayReport = _finish_service()
	if second == null:
		return
	assert_eq(second.day, first.day + 1)
	assert_true(not second.dish_metrics.is_empty(), "the second service must sell a dish")
	for recipe_id: StringName in second.dish_metrics:
		assert_eq(second.dish_metrics[recipe_id]["sold"], second.dishes_sold.get(recipe_id, 0),
			"the second day cannot count yesterday's sales")
	var rows: Array[Dictionary] = _history().summaries()
	assert_eq(rows.size(), 2)
	if rows.size() == 2:
		assert_eq(rows[1]["day"], second.day)
		assert_true(rows[1].has("dish_metrics"), "the second close keeps its measured quality")


func test_evening_purchase_refresh_upserts_and_next_morning_load_preserves_it() -> void:
	_start_main()
	var morning: String = _saved_text()
	if _finish_service() == null:
		return
	var before_report: DayReport = _main.get("shown_report") as DayReport
	assert_not_null(before_report)
	if before_report == null:
		return
	var before_profit: int = before_report.profit()
	var before_cash: int = Economy.cash
	var report_view: Control = _main.get_node("Overlay/EveningReport") as Control
	var chart: BusinessTrendChart = report_view.get_node("%BusinessTrendChart") as BusinessTrendChart
	(report_view.get_node("%BusinessTrendSection/BusinessTrendRanges/Days30") as Button).pressed.emit()
	assert_eq(chart.review_snapshot()["range_days"], 30)
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("shop_buy", &"chair", ShopBuilder.items_with_def(_main.get("world") as SimWorld, &"table_2")[0].origin + Vector2i(1, 2)), "ordinary after-hours paid purchase")
	var paid_cost: int = before_cash - Economy.cash
	assert_true(paid_cost > 0)
	assert_true(_main.call("set_build_active", false))
	assert_eq(_history().summaries().size(), 1, "purchase/report rebuild replaces today's row")
	assert_eq(_history().summaries()[0]["cash_change"], before_profit - paid_cost,
		"leaving Build records the actual paid cost, rather than two agreeing stale snapshots")
	var refreshed: DayReport = _main.get("shown_report") as DayReport
	assert_not_null(refreshed)
	if refreshed != null:
		assert_eq(refreshed.profit(), before_profit - paid_cost)
	_assert_matches(_history().summaries()[0], _main.get("shown_report") as DayReport)
	assert_eq(_saved_text(), morning, "an evening purchase must not save")
	assert_true(_main.call("set_staff_visible", true))
	Economy.add_cash(-2, Ledger.UPGRADES) # A later book change while the report is hidden.
	assert_true(_main.call("set_staff_visible", false))
	assert_eq(chart.review_snapshot()["range_days"], 30, "returning to the same report retains the session range")
	assert_eq(_history().summaries().size(), 1, "returning from a panel cannot duplicate the day")
	_assert_matches(_history().summaries()[0], _main.get("shown_report") as DayReport)
	assert_eq(_saved_text(), morning)
	# No presentation follows this fixture adjustment. The actual Next day
	# signal must finalize the current books before the clock clears them.
	var recorded: Dictionary = _history().capture()
	Economy.add_cash(-3, Ledger.UPGRADES)
	var closing: DayReport = _main.call("build_report", Clock.sim.day) as DayReport
	assert_eq(_history().capture(), recorded, "the preview itself still does not record")
	(_main.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(chart.review_snapshot()["range_days"], 30, "Next day hides rather than replaces the session report")
	assert_eq(_history().summaries().size(), 1, "morning is not an extra closed day")
	_assert_matches(_history().summaries()[0], closing)
	var expected: Dictionary = _json(_history().capture())
	var closed_day_week: Dictionary[StringName, Dictionary] = _history().dish_week(1)
	assert_false(closed_day_week.is_empty())
	assert_ne(_saved_text(), morning, "the ordinary next morning publishes the updated history")
	assert_eq(_document()["data"]["business_history"], _json(expected))
	_close_main()
	_start_main()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_json(_history().capture()), expected, "whole-load success installs the saved history")
	assert_eq(_json(_history().dish_week(Clock.sim.day - 1)), _json(closed_day_week))
	assert_true(_main.call("set_menu_visible", true))
	var panel: MenuPanel = _main.get_node("Overlay/MenuPanel") as MenuPanel
	var history: Label = panel.get_node("%Detail/DishHistory") as Label
	for id: StringName in closed_day_week:
		assert_true(panel.select_recipe(id))
		assert_true(history.text.begins_with("7 days: %d sold" % closed_day_week[id]["sold"]))
	_main.call("set_menu_visible", false)
	assert_null(_main.get("_loaded_business_history"))
	_main.call("_begin_morning")
	assert_eq(_json(_history().capture()), expected, "re-entering the same morning does not duplicate history")
	assert_eq(_document()["data"]["business_history"], _json(expected))


func test_missing_legacy_section_clears_stale_staging_and_loads_empty() -> void:
	_start_main()
	_empty_next_morning()
	var legacy: Dictionary = _document()
	(legacy["data"] as Dictionary).erase("business_history")
	_write_document(legacy)
	_close_main()
	_start_main(_fixture_capture(1))
	assert_eq(Clock.sim.day, 2, "the otherwise valid legacy morning actually loaded")
	assert_eq(_history().summaries(), [] as Array[Dictionary])
	assert_eq(_history().recent(7), [] as Array[Dictionary])
	assert_null(_main.get("_loaded_business_history"), "missing optional data cannot reuse an old staged model")
	assert_true(_history().valid_before(Clock.sim.day))
	assert_eq(_document()["data"]["business_history"], _json(_history().capture()))


func test_malformed_and_future_history_fail_load_without_replacing_checkpoint() -> void:
	_start_main()
	_empty_next_morning()
	var valid: Dictionary = _document()
	# The final entry is intrinsically valid but belongs to the saved morning,
	# so Main's separate day-boundary validation must reject it.
	for bad: Variant in [[], {"version": 99, "days": []}, _fixture_capture(2)]:
		var broken: Dictionary = valid.duplicate(true)
		broken["data"]["business_history"] = bad
		_write_document(broken)
		var failing: String = _saved_text()
		_close_main()
		_start_main(_fixture_capture(1))
		assert_eq(Clock.sim.day, 1, "invalid present history is a failed whole load, not a legacy default")
		assert_eq(_history().summaries(), [] as Array[Dictionary])
		assert_null(_main.get("_loaded_business_history"))
		assert_eq(_saved_text(), failing, "the first fresh morning preserves the rejected checkpoint")
	_empty_next_morning()
	assert_eq(Clock.sim.day, 2)
	assert_eq(_document()["data"]["business_history"], _json(_history().capture()), "later normal morning saves resume")


func test_late_whole_load_rejection_and_missing_slot_clear_live_and_staged_rows() -> void:
	_start_main()
	_empty_next_morning()
	_expected_staged = _fixture_capture(1)
	var doc: Dictionary = _document()
	doc["data"]["business_history"] = _expected_staged.duplicate(true)
	doc["data"][REJECT_SECTION] = {}
	SaveSystem.register(REJECT_SECTION, _empty_capture, _reject_after_history)
	_write_document(doc)
	var failing: String = _saved_text()
	_close_main()
	_start_main()
	assert_true(_reject_reached, "a real later provider must actually run")
	assert_true(_reject_staged, "valid history was decoded before the later provider rejected")
	assert_true(_reject_live_empty, "history cannot be installed before the whole load succeeds")
	assert_eq(Clock.sim.day, 1)
	assert_eq(_history().summaries(), [] as Array[Dictionary])
	assert_null(_main.get("_loaded_business_history"))
	assert_eq(_saved_text(), failing)
	# Early failure is a distinct branch: a new attempt must clear preexisting
	# live and staged rows even when no provider will run because the slot vanished.
	var fixture: BusinessHistory = BusinessHistory.new()
	assert_true(fixture.restore(_expected_staged))
	_main.set("business_history", fixture)
	assert_true(_main.call("_restore_business_history", _expected_staged))
	SaveSystem.delete_slot(SLOT)
	assert_false(_main.call("_load_autosave"))
	assert_eq(_history().summaries(), [] as Array[Dictionary])
	assert_null(_main.get("_loaded_business_history"))
	_close_main()
	_start_main(_expected_staged)
	assert_eq(_history().summaries(), [] as Array[Dictionary], "an actual fresh session also clears pending history")
	assert_null(_main.get("_loaded_business_history"))


func test_hidden_report_reopens_and_hud_next_day_records_the_final_books() -> void:
	_start_main()
	if _finish_service() == null:
		return
	var report_view: Control = _main.get_node("Overlay/EveningReport") as Control
	var report_button: Button = _main.get_node("HUD/Top/Row/Report") as Button
	assert_true(report_view.visible)
	assert_false(report_button.visible, "no Report button while the report is showing")
	(report_view.get_node("%Close") as Button).pressed.emit()
	assert_false(report_view.visible)
	assert_true(report_button.visible, "the top bar offers the hidden report back")
	report_button.pressed.emit()
	assert_true(report_view.visible, "the Report button shows it again")
	assert_false(report_button.visible)
	(report_view.get_node("%Close") as Button).pressed.emit()
	# Bookkeeping fixture while the report is hidden, like a top-bar loan repayment.
	Economy.add_cash(-5, Ledger.UPGRADES)
	var closing: DayReport = _main.call("build_report", Clock.sim.day) as DayReport
	(_main.get_node("HUD/Top/Row/Context") as Button).pressed.emit()
	assert_eq(Clock.sim.day, 2, "the top bar's Next day starts the next morning")
	assert_eq(_history().summaries().size(), 1)
	assert_eq(_history().summaries()[0]["cash_change"], closing.profit(),
		"the top bar's Next day records the books as they closed, including the hidden-report change")


func _paid_dish_guest(sim: RestaurantSim, id: int) -> CustomerAgent:
	var guest: CustomerAgent = CustomerAgent.new(sim, RandomNumberGenerator.new())
	guest.id = id
	guest._eating = guest.eat_ticks
	guest.order = _delivered_dish(&"burger", 0.75)
	return guest


func _delivered_dish(id: StringName, quality: float) -> Order:
	var order: Order = Order.new()
	order.recipe_id = id
	order.price = 10
	order.state = Order.State.DELIVERED
	order.quality = quality
	return order


func _start_main(staged_before_start: Dictionary = {}) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("skip_owner_picker", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	if not staged_before_start.is_empty():
		assert_true(_main.call("_restore_business_history", staged_before_start))
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_process(false)
	Clock.set_speed(0)


func _close_main() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _history() -> BusinessHistory:
	var history: BusinessHistory = _main.get("business_history") as BusinessHistory
	assert_not_null(history)
	return history


func _finish_service() -> DayReport:
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = _main.get("shown_report") as DayReport
	assert_not_null(report)
	return report


func _empty_next_morning() -> void:
	# Persistence-only fixtures skip service; they do not claim a played day.
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())


func _assert_matches(row: Dictionary, report: DayReport) -> void:
	assert_not_null(report)
	if report == null:
		return
	assert_eq(row["day"], report.day)
	assert_eq(row["served"], report.customers_served)
	assert_eq(row["lost"], report.customers_lost)
	assert_eq(row["cash_change"], report.profit())
	assert_eq(row["dish_profit_recorded"], report.operating_profit_recorded())
	if report.operating_profit_recorded():
		assert_eq(row["dish_profit"], report.operating_profit())
	assert_almost_eq(float(row["reputation"]), report.reputation_after)
	var metrics: Dictionary = row.get("dish_metrics", {})
	assert_eq(metrics.size(), report.dish_metrics.size())
	for id: StringName in report.dish_metrics:
		assert_eq(metrics.get(String(id)), report.dish_metrics[id])


func _fixture_capture(day: int) -> Dictionary:
	var report: DayReport = DayReport.new()
	report.day = day
	report.customers_served = 3
	report.customers_lost = 1
	report.income[Ledger.SALE] = 27
	report.costs[Ledger.WAGES] = 5
	report.reputation_after = 3.5
	report.stock_values_recorded = true
	report.food_cost_recorded = true
	report.stock_bought_recorded = true
	report.spoiled_stock_recorded = true
	report.stock_on_hand_recorded = true
	report.food_cost = 4
	report.stock_bought = 8
	report.stock_on_hand = 4
	var history: BusinessHistory = BusinessHistory.new()
	history.record(report)
	return history.capture()


func _observable_state() -> Dictionary:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	return {"history": _history().capture(), "clock": Clock.sim.to_dict(),
		"rng": GameState.call("_capture_save"), "economy": Economy.call("_capture_save"),
		"world_tick": sim.world.now, "events": sim.world.event_log.duplicate(),
		"file": _saved_text()}


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_path())


func _document() -> Dictionary:
	var value: Variant = JSON.parse_string(_saved_text())
	assert_true(value is Dictionary, "a real morning checkpoint must exist")
	return value if value is Dictionary else {}


func _write_document(doc: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(JSON.stringify(doc))
		file.close()
	DirAccess.remove_absolute(_path() + ".bak") # Do not let recovery hide the malformed fixture.


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _empty_capture() -> Dictionary:
	return {}


func _reject_after_history(_data: Dictionary) -> bool:
	_reject_reached = true
	var staged: BusinessHistory = _main.get("_loaded_business_history") as BusinessHistory
	_reject_staged = staged != null and staged.capture() == _expected_staged
	_reject_live_empty = _history().summaries().is_empty()
	return false
