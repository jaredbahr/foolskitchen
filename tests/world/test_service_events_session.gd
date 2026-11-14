extends TestCase
## The real session wires service event cards (#495): the opening draw, the
## pausing card, every effect through its own system, the log and report, the
## Settings toggle and the save section.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "service_events_session"
var _main: Node
var _old_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Preferences.service_events_enabled = true
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Preferences.service_events_enabled = true
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start(events: bool = true, saves: bool = false, auto_pick: int = -1) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", saves)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	_main.set("service_events_for_tools", events)
	_main.set("service_event_auto_pick", auto_pick)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _sim() -> RestaurantSim:
	return _main.get("sim")


func _events() -> ServiceEvents:
	return _main.get("service_events")


func _card() -> ServiceEventCard:
	return _main.get_node("Overlay/ServiceEventCard") as ServiceEventCard


## Runs ticks one at a time until a card shows or service ends.
func _until_card() -> bool:
	while Clock.sim.phase == SimClock.Phase.OPEN:
		_main.call("run_ticks", 1)
		if _card().visible:
			return true
	return false


func _finish_day() -> void:
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 40:
		_main.call("run_ticks", 1000)
		guard += 1


func _event_lines_for(seed_value: int, days: int) -> Array:
	_close()
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", seed_value)
	_main.set("service_events_for_tools", true)
	_main.set("service_event_auto_pick", 0)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	var lines: Array = []
	for day: int in range(1, days + 1):
		assert_true(Clock.sim.start_service(), "day %d opens" % day)
		_finish_day()
		var report: DayReport = _main.call("build_report", day)
		assert_true(report.service_event_lines.size() >= 1 and report.service_event_lines.size() <= 2,
			"day %d: 1-2 cards answered, got %d" % [day, report.service_event_lines.size()])
		lines.append(report.service_event_lines)
		Clock.sim.next_day()
	return [lines, Economy.cash]


func test_card_pauses_blocks_escape_and_restores_speed() -> void:
	_start()
	assert_true(Clock.sim.start_service())
	Clock.set_speed(2)
	assert_eq(_events().day, 1, "the cards are drawn as the doors open")
	assert_true(_events().schedule.size() >= 1, "day 1 has a card")
	assert_true(_until_card(), "a card comes up during service")
	assert_eq(Clock.speed, 0, "the card pauses the game")
	assert_true(Clock.sim.display_minutes() >= int(_events().schedule[0]["minute"]))
	var escape: InputEventKey = InputEventKey.new()
	escape.pressed = true
	escape.physical_keycode = KEY_ESCAPE
	_main.call("_unhandled_input", escape)
	assert_true(_card().visible, "Escape does not dismiss it")
	assert_false(_main.call("is_settings_visible"), "nor open Settings under it")
	_main.get_node("HUD").call("_set_speed", 4)
	assert_eq(Clock.speed, 0, "the speed buttons wait for a choice")
	assert_false(_main.call("set_menu_visible", true))
	var buttons: Array[Button] = _card().choice_buttons()
	assert_true(buttons.size() >= 2)
	var preview: Label = buttons[0].get_node("Lines/Preview") as Label
	assert_false(preview.text.is_empty(), "each choice shows its preview")
	buttons[0].pressed.emit()
	assert_false(_card().visible, "a choice closes the card")
	assert_eq(Clock.speed, 2, "and the game runs at its earlier speed")
	var log: PackedStringArray = _sim().world.event_log
	var logged: bool = false
	for line: String in log:
		logged = logged or line.contains("Service event: ")
	assert_true(logged, "the Today log records the card and the choice")
	Clock.set_speed(0)
	_finish_day()
	var report: DayReport = _main.call("build_report", 1)
	assert_true(report.service_event_lines.size() >= 1, "the evening report has a line")
	assert_eq(DayReport.from_dict(report.to_dict()).service_event_lines, report.service_event_lines)


func test_same_seed_same_cards_and_outcomes_over_days() -> void:
	var first: Array = _event_lines_for(3, 3)
	var second: Array = _event_lines_for(3, 3)
	assert_eq(first, second, "a seed replays the same cards, choices, results and cash")


func test_setting_off_means_no_cards() -> void:
	Preferences.service_events_enabled = false
	_start()
	assert_true(Clock.sim.start_service())
	_finish_day()
	assert_eq(_events().day, 0, "nothing is drawn")
	assert_false(_card().visible)
	assert_eq((_main.call("build_report", 1) as DayReport).service_event_lines.size(), 0)


func test_tools_and_probe_runs_have_none_by_default() -> void:
	_start(false)
	assert_true(Clock.sim.start_service())
	_finish_day()
	assert_eq(_events().day, 0)
	assert_false(Economy.ledger.day_totals(1).has(Ledger.SERVICE_EVENT))


func test_closed_day_has_no_cards() -> void:
	_start()
	Clock.sim.opening_refusal = "Closed for the test"
	assert_true(Clock.sim.close_without_opening())
	assert_eq(_events().day, 0, "a day that never opens draws nothing")
	assert_true(_events().schedule.is_empty())


func test_mid_morning_save_has_no_card_and_round_trips() -> void:
	_start(true, true)
	var events: ServiceEvents = _events()
	events.last_shown[&"busker"] = 1
	events.boost_day = 2
	events.boost_percent = 8
	assert_eq(SaveSystem.save_game(SLOT), OK)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		SaveSystem.save_dir.path_join(SLOT + ".json")))
	var section: Dictionary = document["data"]["service_events"]
	assert_false(section.has("pending"), "no card is ever saved")
	assert_eq((section["schedule"] as Array).size(), 0, "a morning save has no drawn cards")
	_close()
	_start(true, true)
	assert_eq(_events().last_shown, {&"busker": 1} as Dictionary[StringName, int])
	assert_almost_eq(_events().arrival_factor(2), 1.08)
	assert_true(_events().pending.is_empty())
	# A save from before service events loads with an empty event state.
	(document["data"] as Dictionary).erase("service_events")
	var file: FileAccess = FileAccess.open(SaveSystem.save_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_close()
	_start(true, true)
	assert_eq(_events().last_shown.size(), 0)
	assert_eq(_events().boost_day, 0)


## One effect at a time, through the session's own apply step.
func _apply(choice: ServiceEventChoice, entry: Dictionary = {}, risk: bool = false) -> void:
	_main.call("_apply_service_event", {"choice": choice, "entry": entry, "risk": risk, "title": "Test card"})


func _choice() -> ServiceEventChoice:
	var choice: ServiceEventChoice = ServiceEventChoice.new()
	choice.label = "Test"
	choice.result = "Tested"
	return choice


func test_each_effect_uses_its_own_system() -> void:
	_start()
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 10)
	var sim: RestaurantSim = _sim()
	# Cash: its own ledger category.
	var choice: ServiceEventChoice = _choice()
	choice.cash = -10
	_apply(choice)
	assert_eq(int(Economy.ledger.day_totals(1).get(Ledger.SERVICE_EVENT, 0)), -10)
	# A review joins the rolling window; a risk swaps in its own stars.
	choice = _choice()
	choice.review_stars = 2
	choice.risk_percent = 50
	choice.risk_review_stars = 5
	var before: int = sim.review_book.scores().size()
	_apply(choice, {}, true)
	assert_eq(sim.review_book.scores().size(), before + 1)
	assert_eq(sim.review_book.scores().back(), 5)
	# Guests in the shop now.
	var guest: CustomerAgent = CustomerAgent.new(sim, RandomNumberGenerator.new())
	guest.cell = sim.world.grid.entries()[0]
	sim.world.add_agent(guest)
	var queue: int = guest.queue_patience
	choice = _choice()
	choice.guest_patience_seconds = 20
	_apply(choice)
	assert_eq(guest.queue_patience, queue + 20 * SimClock.TICKS_PER_SECOND)
	choice.guest_patience_seconds = -60
	_apply(choice)
	assert_true(guest.queue_patience >= 10 * SimClock.TICKS_PER_SECOND, "a cut never sends a guest away at once")
	# Today's later guests and arrivals.
	choice = _choice()
	choice.day_patience_percent = 10
	choice.day_arrivals_percent = 5
	var rate: float = sim.arrival_rate()
	_apply(choice)
	assert_almost_eq(sim.event_patience_multiplier, 1.1)
	assert_almost_eq(sim.arrival_rate(), rate * 1.05)
	# Tomorrow's arrivals join tomorrow's street factor.
	var street: float = _main.call("_street_factor", 2)
	_events().boost_day = 2
	_events().boost_percent = 8
	assert_almost_eq(_main.call("_street_factor", 2), street * 1.08)
	# Stock: a discounted batch through the normal purchase, a bad batch, and use.
	var entry: Dictionary = {"ingredient_id": "tomato"}
	var tomatoes: int = Economy.stock.count(&"tomato")
	var spent: int = int(Economy.ledger.day_totals(1).get(Ledger.INGREDIENTS, 0))
	choice = _choice()
	choice.stock_units = 20
	choice.stock_price_percent = 60
	_apply(choice, entry)
	assert_eq(Economy.stock.count(&"tomato"), tomatoes + 20)
	assert_eq(int(Economy.ledger.day_totals(1).get(Ledger.INGREDIENTS, 0)), spent - 12, "20 at $1 for 60%")
	choice.risk_percent = 25
	choice.risk_result = "Bad"
	choice.risk_stock_lost_percent = 50
	_apply(choice, entry, true)
	assert_eq(Economy.stock.count(&"tomato"), tomatoes + 30, "half the second crate went in the bin")
	choice = _choice()
	choice.stock_units = -2
	_apply(choice, entry)
	assert_eq(Economy.stock.count(&"tomato"), tomatoes + 28)
	# Staff mood stays between 1 and 3.
	var roster: StaffRoster = _main.get("staff_roster")
	var member: StaffMember = roster.members()[0]
	choice = _choice()
	choice.staff_mood = -1
	for _time: int in 4:
		_apply(choice, {"staff_id": String(member.id)})
	assert_eq(roster.members()[0].growth_state().mood, 1, "a sulk never makes anyone quit")
	choice.staff_mood = 1
	_apply(choice, {"staff_id": String(member.id)})
	assert_eq(roster.members()[0].growth_state().mood, 2)
	# The owner's job.
	choice = _choice()
	choice.owner_mode = &"help"
	_apply(choice)
	if sim.owner_agent() != null:
		assert_eq(sim.owner_agent().current_mode(), &"help")
	# The floor's dirty spots.
	var spot: Vector2i = sim.world.grid.entries()[0]
	sim.cleanliness.add_spill(spot)
	choice = _choice()
	choice.clean_spots = true
	_apply(choice)
	assert_eq(sim.cleanliness.spot_count(), 0)
	# Nothing leaks into tomorrow: a new day resets today's nudges.
	_finish_day()
	Clock.sim.next_day()
	assert_almost_eq(sim.event_patience_multiplier, 1.0)
	assert_almost_eq(sim.event_arrival_factor, 1.0)
