extends TestCase

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "morning_paper_session"

var _main: Node
var _old_preference: bool
var _old_clock_processing: bool
var _old_speed: int
var _old_providers: Dictionary[String, Dictionary] = {}
var _old_save_dir: String
var _save_dir: String


func before_each() -> void:
	_old_preference = Preferences.morning_paper_enabled
	_old_clock_processing = Clock.is_processing()
	_old_speed = Clock.speed
	_old_providers = SaveSystem._providers.duplicate(true)
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_process(false)
	Clock.set_speed(0)


func after_each() -> void:
	_close_main()
	Preferences.morning_paper_enabled = _old_preference
	SaveSystem._providers = _old_providers
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_speed(_old_speed)
	Clock.set_process(_old_clock_processing)


func test_default_paper_shows_at_start_and_after_real_service() -> void:
	_start_main(true)
	var paper: MorningPaperCard = _paper()
	assert_true(paper.visible)
	assert_eq((paper.get_node("%Masthead") as Label).text, "The Daily Ladle")
	assert_true(MorningPaper.HEADLINES.groups[&"first_day"].has((paper.get_node("%Headline") as Label).text))
	var first_draw: Dictionary = _streams()["paper"]
	_main.call("_begin_morning")
	assert_eq(_streams()["paper"], first_draw, "re-entering the same morning cannot draw again")

	(paper.get_node("%CloseButton") as Button).pressed.emit()
	assert_false(paper.visible)
	assert_eq(_streams()["paper"], first_draw)

	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var yesterday: DayReport = _main.get("shown_report") as DayReport
	assert_not_null(yesterday)
	if yesterday == null:
		return
	assert_false(paper.visible)
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	assert_true(paper.visible)
	assert_ne(_streams()["paper"], first_draw)
	var expected_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	expected_rng.seed = String(first_draw["seed"]).to_int()
	expected_rng.state = String(first_draw["state"]).to_int()
	var world: SimWorld = _main.get("world") as SimWorld
	var content: ContentDB = _main.get("content") as ContentDB
	var dish: String = MorningPaper.best_dish(yesterday.dishes_sold, content)
	var expected: Dictionary = MorningPaper.build(2, yesterday, world.weather.kind, [], expected_rng, dish)
	assert_eq((paper.get_node("%Headline") as Label).text, expected["headline"])
	assert_eq(String(_streams()["paper"]["state"]).to_int(), expected_rng.state)

	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_main.call("_unhandled_input", escape)
	assert_false(paper.visible)
	assert_eq(Clock.sim.day, 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


func test_off_never_allocates_paper_stream_or_changes_other_morning_state() -> void:
	_start_main(true)
	var enabled_streams: Dictionary = _streams()
	assert_true(enabled_streams.erase("paper"))
	var cash: Dictionary = Economy._capture_save()
	var morning: Dictionary = Clock._capture_save()
	_close_main()

	_start_main(false)
	assert_false(_paper().visible)
	assert_false(_streams().has("paper"))
	assert_eq(_streams(), enabled_streams)
	assert_eq(Economy._capture_save(), cash)
	assert_eq(Clock._capture_save(), morning)
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	assert_false(_paper().visible)
	assert_false(_streams().has("paper"))


func test_settings_toggle_hides_an_open_paper_immediately() -> void:
	_start_main(true)
	var settings: SettingsPanel = _main.get_node("Overlay/SettingsPanel") as SettingsPanel
	var toggle: CheckButton = settings.get_node("%MorningPaperToggle") as CheckButton
	assert_true(toggle.button_pressed)
	toggle.button_pressed = false
	assert_false(Preferences.morning_paper_enabled)
	assert_false(_paper().visible)


func test_next_morning_edition_survives_autosave_reload_without_drawing_again() -> void:
	_start_main(true, true)
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var yesterday: DayReport = _main.get("shown_report") as DayReport
	assert_not_null(yesterday)
	if yesterday == null:
		return
	# A record headline cannot be reconstructed from the older Business Trend row.
	yesterday.record_lines = ["New shop record"]
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	var headline: String = (_paper().get_node("%Headline") as Label).text
	var notes: String = (_paper().get_node("%Notes") as Label).text
	var stream: Dictionary = _streams()["paper"].duplicate(true)
	_close_main()

	_start_main(true, true)
	assert_eq(Clock.sim.day, 2)
	assert_true(_paper().visible)
	assert_eq((_paper().get_node("%Headline") as Label).text, headline)
	assert_eq((_paper().get_node("%Notes") as Label).text, notes)
	assert_eq(_streams()["paper"], stream, "reloading never consumes another draw")


func test_150_percent_paper_avoids_both_right_hand_hud_cards() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1600, 900)
	host.gui_embed_subwindows = true
	tree.root.add_child(host)
	var window: Window = Window.new()
	window.borderless = true
	window.size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_factor = 1.5
	host.add_child(window)
	_start_main(true, false, window)
	var hud: Node = _main.get_node("HUD")
	hud.call("set_booking_status", "Booking today: six guests at 12:30.")
	var goals: Array[String] = ["Buy a floor lamp.", "Set a price.", "Serve customers."]
	hud.call("set_opening_week", goals, "Opening Week")
	for frame: int in range(4):
		await tree.process_frame
	assert_almost_eq(window.get_visible_rect().size.x, 1280.0 / 1.5, 0.01)
	assert_true(_paper().visible)
	var paper_rect: Rect2 = _paper().get_global_rect()
	var today: Button = hud.get_node("Today") as Button
	assert_true(today.is_visible_in_tree())
	assert_true(paper_rect.position.x >= today.get_global_rect().end.x + 8.0,
		"the newspaper leaves the Today launcher readable")
	for path: String in ["BookingStatus", "OpeningWeek"]:
		var box: Control = hud.get_node(path) as Control
		assert_true(box.is_visible_in_tree())
		assert_true(paper_rect.end.x <= box.get_global_rect().position.x - 8.0,
			"the newspaper has a visible gap beside " + path)
		assert_false(paper_rect.intersects(box.get_global_rect()))
	_close_main()
	host.free()


func _start_main(paper_enabled: bool, use_saves: bool = false, host: Node = null) -> void:
	Preferences.morning_paper_enabled = paper_enabled
	_main = MAIN.instantiate()
	_main.set("use_saves", use_saves)
	_main.set("save_slot", SLOT)
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 346)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var parent: Node = host if host != null else tree.root
	parent.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_process(false)
	Clock.set_speed(0)


func _close_main() -> void:
	if is_instance_valid(_main):
		_main.free()
	_main = null


func _paper() -> MorningPaperCard:
	return _main.get_node("Overlay/MorningPaper") as MorningPaperCard


func _streams() -> Dictionary:
	return GameState._capture_save()["rngs"]
