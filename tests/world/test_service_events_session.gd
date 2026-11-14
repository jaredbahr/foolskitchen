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
func _apply(choice: ServiceEventChoice, entry: Dictionary = {}, risk: bool = false) -> bool:
	return _main.call("_apply_service_event", {"choice": choice, "entry": entry, "risk": risk, "title": "Test card"})


func _choice() -> ServiceEventChoice:
	var choice: ServiceEventChoice = ServiceEventChoice.new()
	choice.label = "Test"
	choice.result = "Tested"
	return choice


func _open_service() -> RestaurantSim:
	_start()
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 10)
	return _sim()


## Leaves exactly `amount` cash in the till.
func _set_cash(amount: int) -> void:
	Economy.add_cash(amount - Economy.cash, Ledger.OTHER)


func _newest_tomato_batch() -> Dictionary:
	var batches: Array = Economy.stock._batches.get(&"tomato", [])
	return batches.back() if not batches.is_empty() else {}


func _van() -> ServiceEventChoice:
	var choice: ServiceEventChoice = _choice()
	choice.stock_units = 20
	choice.stock_price_percent = 60
	return choice


const TOMATO: Dictionary = {"ingredient_id": "tomato", "names": {"ingredient": "tomato"}}


func test_each_effect_uses_its_own_system() -> void:
	var sim: RestaurantSim = _open_service()
	# Cash: its own ledger category.
	var choice: ServiceEventChoice = _choice()
	choice.cash = -10
	assert_true(_apply(choice))
	assert_eq(int(Economy.ledger.day_totals(1).get(Ledger.SERVICE_EVENT, 0)), -10)
	# A review joins the rolling window and today's reviews; a risk swaps in its own stars.
	choice = _choice()
	choice.review_stars = 2
	choice.risk_percent = 50
	choice.risk_review_stars = 5
	var before: int = sim.review_book.scores().size()
	var today: int = sim.reviews_today.size()
	_apply(choice, {}, true)
	assert_eq(sim.review_book.scores().size(), before + 1)
	assert_eq(sim.review_book.scores().back(), 5)
	assert_eq(sim.reviews_today.size(), today + 1, "the evening count includes the card's review")
	assert_eq(int(sim.reviews_today.back()["stars"]), 5)
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
	# Improvising uses stock and books it as today's food cost.
	Economy.stock.add(&"tomato", 5, Clock.day, 10)
	var tomatoes: int = Economy.stock.count(&"tomato")
	var food_cost: int = int((_main.get("_food_cost_today") as Dictionary)["cost"])
	choice = _choice()
	choice.stock_units = -2
	assert_true(_apply(choice, TOMATO))
	assert_eq(Economy.stock.count(&"tomato"), tomatoes - 2)
	assert_true(int((_main.get("_food_cost_today") as Dictionary)["cost"]) > food_cost,
		"the used tomatoes join today's food cost")
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


func test_the_van_buys_one_lot_at_its_real_price() -> void:
	_open_service()
	_set_cash(100)
	var tomatoes: int = Economy.stock.count(&"tomato")
	var spent: int = int(Economy.ledger.day_totals(1).get(Ledger.INGREDIENTS, 0))
	# $1 tomatoes at 60%: 20 for $12, one batch, one ledger line, no rounding to $0.
	assert_true(_apply(_van(), TOMATO))
	assert_eq(Economy.stock.count(&"tomato"), tomatoes + 20)
	assert_eq(Economy.cash, 88)
	assert_eq(int(Economy.ledger.day_totals(1).get(Ledger.INGREDIENTS, 0)), spent - 12)
	assert_eq(int(_newest_tomato_batch().get("total_cost", -1)), 12, "the batch costs what was paid")
	assert_eq(int(_newest_tomato_batch()["qty"]), 20)
	# A bad batch is part of the van's own crate: half never reaches the shelf.
	var choice: ServiceEventChoice = _van()
	choice.risk_percent = 25
	choice.risk_result = "Bad"
	choice.risk_stock_lost_percent = 50
	var older: Array = (Economy.stock._batches[&"tomato"] as Array).duplicate(true)
	assert_true(_apply(choice, TOMATO, true))
	assert_eq(Economy.stock.count(&"tomato"), tomatoes + 30)
	assert_eq(Economy.cash, 76)
	assert_eq(int(_newest_tomato_batch()["qty"]), 10)
	assert_eq(int(_newest_tomato_batch()["total_cost"]), 12, "the good half carries the whole price")
	assert_eq((Economy.stock._batches[&"tomato"] as Array).slice(0, older.size()), older,
		"older stock is untouched")
	assert_eq(int((_main.get("_thrown_today") as Dictionary).get(&"tomato", 0)), 10,
		"the bin shows in the Stock notes")


func test_the_van_respects_cash_and_storage() -> void:
	_open_service()
	var choice: ServiceEventChoice = _van()
	choice.risk_percent = 25
	choice.risk_result = "Bad"
	choice.risk_stock_lost_percent = 50
	# Not enough cash: refused, nothing changes, and the reason says so.
	_set_cash(5)
	var tomatoes: int = Economy.stock.count(&"tomato")
	var entries: int = Economy.ledger.entries_for_day(1, Economy.active_site).size()
	assert_eq(_main.call("service_event_refusal", choice, TOMATO), ServiceEventText.NOT_ENOUGH_CASH)
	assert_false(_apply(choice, TOMATO, true))
	assert_eq(Economy.cash, 5, "cash never goes negative")
	assert_eq(Economy.stock.count(&"tomato"), tomatoes)
	assert_eq(Economy.ledger.entries_for_day(1, Economy.active_site).size(), entries)
	assert_eq(int((_main.get("_thrown_today") as Dictionary).get(&"tomato", 0)), 0, "no bad batch without a buy")
	# Not enough fridge space: refused the same way.
	_set_cash(100)
	var space: StorageSpace = _main.call("storage_space")
	var kind: int = space.kind_of(&"tomato")
	var room: int = space.free_units(kind)
	if room > 10:
		Economy.stock.add(&"tomato", room - 10, Clock.day, 0)
	assert_eq(_main.call("service_event_refusal", choice, TOMATO), StorageSpace.refusal(kind))
	assert_false(_apply(choice, TOMATO))
	assert_eq(Economy.cash, 100)
	assert_true((_main.call("storage_space") as StorageSpace).committed(kind)
		<= (_main.call("storage_space") as StorageSpace).capacity(kind), "storage is never overfilled")
	# Improvising needs the stock on the shelves.
	var improvise: ServiceEventChoice = _choice()
	improvise.stock_units = -2
	Economy.stock.take(&"tomato", Economy.stock.count(&"tomato"))
	Economy.stock.add(&"tomato", 1, Clock.day, 1)
	assert_eq(_main.call("service_event_refusal", improvise, TOMATO), "Not enough tomato")
	assert_false(_apply(improvise, TOMATO))
	assert_eq(Economy.stock.count(&"tomato"), 1)


## Brings the busker's card up for real, with `cash` in the till.
func _show_busker(cash: int) -> void:
	_open_service()
	_set_cash(cash)
	var events: ServiceEvents = _events()
	events.day = Clock.sim.day
	events.schedule = [{"id": "busker", "minute": 0, "shown": false, "names": {},
		"staff_id": "", "staff_role": "", "ingredient_id": ""}]
	var entry: Dictionary = events.due(Clock.sim.display_minutes())
	_main.call("_show_service_event_card", entry)
	assert_true(_card().visible)


func _key(code: Key) -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = code
	return key


func test_a_choice_you_cannot_afford_is_greyed_out_with_a_reason() -> void:
	_show_busker(5)
	var buttons: Array[Button] = _card().choice_buttons()
	assert_true(buttons[0].disabled, "the $15 tip is out of reach")
	assert_true((buttons[0].get_node("Lines/Preview") as Label).text.begins_with("Not enough cash"))
	assert_false(buttons[1].disabled, "the free choice always stays")
	assert_eq((buttons[0].get_node("Lines/Label") as Label).text, "1. Tip him to stay", "each button shows its key")
	assert_eq((buttons[1].get_node("Lines/Label") as Label).text, "2. Move him along")
	# Neither a pick nor key 1 takes it: nothing spent, rolled or logged.
	assert_false(_main.call("service_event_pick", 0))
	_main.call("_unhandled_input", _key(KEY_1))
	assert_true(_card().visible)
	assert_eq(Economy.cash, 5)
	assert_eq(_events().answered.size(), 0)
	# Key 2 picks the free choice.
	_main.call("_unhandled_input", _key(KEY_2))
	assert_false(_card().visible)
	assert_eq(_events().answered.size(), 1)
	assert_eq(Economy.cash, 5)


func test_number_keys_pick_an_affordable_choice() -> void:
	_show_busker(100)
	_main.call("_unhandled_input", _key(KEY_3))
	assert_true(_card().visible, "there is no third choice")
	_main.call("_unhandled_input", _key(KEY_1))
	assert_false(_card().visible)
	assert_eq(Economy.cash, 85, "the tip is paid")


func test_tools_auto_pick_falls_back_to_a_free_choice() -> void:
	_start(true, false, 0)
	_set_cash(0)
	assert_true(Clock.sim.start_service())
	_finish_day()
	assert_true(_events().answered.size() >= 1, "the day's cards were answered")
	assert_true(int(Economy.ledger.day_totals(1).get(Ledger.SERVICE_EVENT, 0)) >= 0,
		"with no cash, no card spends any")


func test_a_card_due_in_photo_mode_leaves_photo_mode() -> void:
	_open_service()
	var photo: PhotoMode = _main.get_node("PhotoMode") as PhotoMode
	photo.toggle_held()
	assert_true(photo.held)
	var events: ServiceEvents = _events()
	events.day = Clock.sim.day
	events.schedule = [{"id": "busker", "minute": 0, "shown": false, "names": {},
		"staff_id": "", "staff_role": "", "ingredient_id": ""}]
	_main.call("run_ticks", 1)
	assert_true(_card().visible)
	assert_false(photo.held, "photo mode is left, so the card can be seen and answered")
	assert_true((_main.get_node("Overlay") as CanvasLayer).visible)


func test_blogger_buzz_is_its_own_nudge_at_its_own_site() -> void:
	var sim: RestaurantSim = _open_service()
	var street: float = _main.call("_street_factor", 2)
	_finish_day()
	Clock.sim.next_day()
	_events().boost_day = 2
	_events().boost_percent = 8
	_events().boost_site = "elsewhere"
	assert_almost_eq(_main.call("_street_factor", 2), street, 0.0001, "never shown as curb appeal")
	assert_true(Clock.sim.start_service())
	assert_almost_eq(sim.event_arrival_factor, 1.0, 0.0001, "another site's buzz does nothing here")
	_finish_day()
	Clock.sim.next_day()
	_events().boost_day = 3
	_events().boost_percent = 8
	_events().boost_site = String(Economy.active_site)
	assert_true(Clock.sim.start_service())
	assert_almost_eq(sim.event_arrival_factor, 1.08, 0.0001, "today's arrivals at this shop")
	var logged: bool = false
	for line: String in sim.world.event_log:
		logged = logged or line.contains("food blogger")
	assert_true(logged, "the Today log names it")
