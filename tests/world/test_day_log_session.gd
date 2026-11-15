extends TestCase
## Production service events feed the actual Today button and panel.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _main: Node
var _providers: Dictionary


func before_each() -> void:
	_providers = SaveSystem._providers.duplicate(true)
	Clock.set_speed(0)
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func after_each() -> void:
	_main.get_parent().remove_child(_main)
	_main.free()
	_main = null
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_service_producers_feed_player_words_without_pausing_the_shop() -> void:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var content: ContentDB = _main.get("content") as ContentDB
	var recipe: RecipeDef = content.recipe(&"tomato_soup")
	sim.menu = [recipe] as Array[RecipeDef]
	assert_true(sim.kitchen.configure_plates(0))
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	var tomato: StringName = &"tomato"
	assert_true(sim.stock.take(tomato, sim.stock.count(tomato) - 3))
	sim.inspection.planned_day = Clock.sim.day
	sim.inspection.planned_tick = 1
	sim.critic.pending = true
	sim.critic.arrival_permille = 0
	sim.critic.tells = [FoodCritic.NOTEBOOK, FoodCritic.PRICIEST] as Array[StringName]
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 7301
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random)
	assert_true(Clock.sim.start_service())
	assert_true(sim.try_disguise_critic(guest))
	for tick: int in range(1200):
		_main.call("run_ticks", 1)
		if "\n".join(sim.day_log.newest_first()).contains("waiting for clean plates"):
			break
	assert_not_null(guest.order)
	assert_true(sim.kitchen.get("_plate_shortage_active"))
	sim.stock.add(tomato, 3, Clock.sim.day)
	sim.restock_sold_out()
	assert_true(sim.stock.take(tomato, sim.stock.count(tomato)))
	sim.refresh_sold_out()
	sim.record_event_review(4, "A nice lunch")
	guest.leave_reason = &"waited_too_long"
	sim.record_departure(guest)

	var panel: TodayPanel = _main.get_node("Overlay/TodayPanel") as TodayPanel
	var button: Button = _main.get_node("HUD/Today") as Button
	assert_eq(button.text, "Today")
	assert_false(panel.visible)
	var speed: int = Clock.speed
	button.pressed.emit()
	assert_true(panel.visible)
	assert_eq(Clock.speed, speed)
	var text: String = (panel.get_node("Column/Scroll/Lines") as Label).text
	assert_false(text.contains("food critic"), "the visitor's disguise stays hidden during service")
	for phrase: String in ["health inspector arrived", "Low stock: Tomato (1 left)",
			"Ran out of tomato", "Tomato soup sold out", "waiting for clean plates",
			"New 4-star review", "A guest left: waited too long"]:
		assert_true(text.contains(phrase), phrase + " should be in: " + text)
	var clock_prefix: RegEx = RegEx.create_from_string("^\\d{2}:\\d{2}  ")
	var internal_name: RegEx = RegEx.create_from_string("waited_too_long|tomato_soup|Guest #|[A-Z]+_[A-Z_]+")
	for line: String in text.split("\n"):
		assert_not_null(clock_prefix.search(line), line)
		assert_null(internal_name.search(line), line)
	assert_eq(text.count("waiting for clean plates"), 1)
	assert_false(text.contains("The kitchen is waiting for clean plates ("),
		"a cook retrying at the pass is one shortage")
	assert_true(text.begins_with(sim.day_log.newest_first()[0]))
	(panel.get_node("Column/Header/Close") as Button).pressed.emit()
	assert_false(panel.visible)
	button.pressed.emit()
	assert_true(panel.visible)
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_main.call("_unhandled_input", escape)
	assert_false(panel.visible, "Escape closes Today")
	Clock.sim.open_ticks = Clock.sim.phase_tick + 1
	Clock.sim.last_orders_max_ticks = 1
	_main.call("run_ticks", 8)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: Control = _main.get_node("Overlay/EveningReport") as Control
	assert_true(report.visible, "service close shows the evening report")
	var viewport: Window = _main.get_window()
	await viewport.get_tree().process_frame
	for pressed: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = button.get_global_rect().get_center()
		click.pressed = pressed
		viewport.push_input(click, true)
	assert_true(panel.visible)
	assert_true(panel.get_index() > report.get_index(), "Today draws above the report")
	assert_true(panel.position.y > button.get_global_rect().end.y,
		"Today opens below its launcher")
	assert_true((panel.get_node("Column/Scroll/Lines") as Label).text.contains("11:00  A food critic arrived"),
		"the closing log reveals the original arrival time")
	_main.call("_unhandled_input", escape)
	assert_false(panel.visible, "Escape closes the foremost panel")
	assert_true(report.visible, "the evening report remains open")
	assert_eq(sim.kitchen.clean_plates, 0)
	assert_true(Clock.sim.next_day())
	assert_false(sim.kitchen.get("_plate_shortage_active"),
		"another day re-arms the shortage even while there are zero plates")


func test_morning_clears_log_and_panel_rebind_leaves_the_old_shop_detached() -> void:
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	assert_true(Clock.sim.start_service())
	sim.record_event_review(4, "A nice lunch")
	var panel: TodayPanel = _main.get_node("Overlay/TodayPanel") as TodayPanel
	var button: Button = _main.get_node("HUD/Today") as Button
	button.pressed.emit()
	assert_true(panel.visible)
	assert_false(sim.day_log.newest_first().is_empty())
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	assert_false(panel.visible)
	assert_true(sim.day_log.newest_first().is_empty())
	button.pressed.emit()
	assert_eq((panel.get_node("Column/Scroll/Lines") as Label).text, "Nothing to report yet.")

	var next_log: DayLog = DayLog.new()
	panel.bind_log(next_log)
	assert_false(panel.visible)
	button.pressed.emit()
	sim.day_log.add(1, DayLog.Kind.REVIEW, "Old shop review")
	assert_eq((panel.get_node("Column/Scroll/Lines") as Label).text, "Nothing to report yet.")
	next_log.add(1, DayLog.Kind.REVIEW, "New shop review")
	assert_true((panel.get_node("Column/Scroll/Lines") as Label).text.ends_with("New shop review"))
