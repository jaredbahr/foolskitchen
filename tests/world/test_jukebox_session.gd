extends TestCase
## #294 in the real game session: the counted jukebox plays its music style as a
## quiet loop only while the shop is open, the Inspect panel picks the style, and
## headless runs create no audio player at all.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SPOT: Vector2i = Vector2i(11, 5)

var _mains: Array[Node] = []


func after_each() -> void:
	for main: Node in _mains:
		if is_instance_valid(main):
			if main.is_inside_tree():
				main.get_parent().remove_child(main)
			main.free()
	_mains.clear()
	Sfx.stop_loops()
	Sfx.reset_throttle()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start() -> Node:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Economy.add_cash(500, Ledger.OTHER)
	(main.get("shop_editor") as ShopEditor).set_owner_level(3)
	return main


func _loops_playing() -> Array[StringName]:
	var playing: Array[StringName] = []
	for style: StringName in [&"jukebox_diner_rock", &"jukebox_cafe_jazz", &"jukebox_bar_blues"]:
		if Sfx.loop_level(style) > 0.0:
			playing.append(style)
	return playing


func test_music_plays_only_while_the_shop_is_open_and_follows_the_style() -> void:
	var main: Node = _start()
	assert_true(bool(main.call("shop_buy", &"jukebox", SPOT, 0)), (main.get("shop_editor") as ShopEditor).last_check.why)
	var world: SimWorld = main.get("world")
	var jukebox: PlacedItem = world.grid.item_at(SPOT)
	Clock.set_speed(1)
	main.call("refresh_presentation")
	assert_eq(_loops_playing(), [] as Array[StringName], "quiet during morning prep")
	assert_true(Clock.sim.phase == SimClock.Phase.MORNING)
	Clock.set_speed(0)
	assert_true(Clock.sim.start_service(), "service opens")
	Clock.set_speed(1)
	main.call("refresh_presentation")
	assert_eq(_loops_playing(), [&"jukebox_diner_rock"] as Array[StringName], "the default style plays once open")
	assert_true(bool(main.call("shop_item_look", jukebox.id, &"jukebox_bar_blues")), "a style can change during service")
	main.call("refresh_presentation")
	assert_eq(_loops_playing(), [&"jukebox_bar_blues"] as Array[StringName], "changing style swaps the music")
	Clock.set_speed(0)
	main.call("refresh_presentation")
	assert_eq(_loops_playing(), [] as Array[StringName], "paused is silent")


func test_the_inspect_panel_picks_the_music_style() -> void:
	var main: Node = _start()
	assert_true(bool(main.call("shop_buy", &"jukebox", SPOT, 0)))
	var world: SimWorld = main.get("world")
	var jukebox: PlacedItem = world.grid.item_at(SPOT)
	var panel: InspectPanel = main.get_node("Overlay/InspectPanel") as InspectPanel
	panel.show_item(jukebox.id)
	var row: Control = panel.get_node_or_null("Panel/Rows/MusicStyleRow") as Control
	assert_not_null(row)
	assert_true(row.is_visible_in_tree(), "the style picker shows for a jukebox")
	var buttons: Array[Node] = row.get_node("MusicStyleButtons").get_children()
	assert_eq(buttons.size(), 3)
	var names: Array[String] = []
	for button: Node in buttons:
		names.append((button as Button).text)
	assert_eq(names, ["Diner rock", "Café jazz", "Bar blues"] as Array[String], "player names, not ids")
	assert_true((buttons[0] as Button).button_pressed)
	(buttons[1] as Button).pressed.emit()
	assert_eq(jukebox.variant_id, &"jukebox_cafe_jazz")
	assert_true((buttons[1] as Button).button_pressed and not (buttons[0] as Button).button_pressed)
	assert_true((panel.get_node("Panel/Rows/Details") as Label).text.contains("Plays: Café jazz"))
	assert_true((panel.get_node("Panel/Rows/Details") as Label).text.contains("Theme: Café"))


func test_headless_runs_create_no_audio_player() -> void:
	assert_true(Sfx.is_silent_run(DisplayServer.get_name(), OS.get_cmdline_args()), "the test run is a silent run")
	var main: Node = _start()
	assert_true(bool(main.call("shop_buy", &"jukebox", SPOT, 0)))
	Clock.set_speed(0)
	assert_true(Clock.sim.start_service())
	Clock.set_speed(1)
	main.call("refresh_presentation")
	assert_eq(_loops_playing(), [&"jukebox_diner_rock"] as Array[StringName], "the level is still tracked")
	var players: int = 0
	for child: Node in Sfx.get_children():
		if child is AudioStreamPlayer:
			players += 1
	assert_eq(players, 0, "no AudioStreamPlayer exists, not even a stopped one")
