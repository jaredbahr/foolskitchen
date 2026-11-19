extends TestCase
## Travelling in a real session (docs/CITY_MAP.md T5, T6): the van ride and its
## commute line follow a switch to another neighbourhood and nothing else;
## a click, a key or skip ends it at once; the switch itself is exactly the
## same with or without it; and the morning card's "See the map" opens the
## city screen. Rides are off in headless runs, so each test turns one on.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const FIXER: StringName = &"town_fixer_upper"

var _main: Node


func after_each() -> void:
	_close()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _close() -> void:
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


## A started game at Tier 3 with the Old Mill Street lot bought, so there is a
## second site in another neighbourhood to travel to.
func _start(ride_seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 7)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set("van_ride_seconds", ride_seconds)
	(_main.get("owner_progress") as OwnerProgress).career_tier = 3
	Economy.add_cash(9000 - Economy.cash, Ledger.OTHER, "test cash")
	assert_true(_main.call("buy_lot", FIXER))


func _ride() -> VanRide:
	return _main.get("_van_ride") as VanRide


func _book() -> SiteBook:
	return _main.get("site_book")


func _card() -> SiteCard:
	return _main.get_node("Overlay/SiteCard") as SiteCard


func test_rides_are_off_in_headless_runs_by_default() -> void:
	await _start(0.0)
	assert_eq(float(_main.get("van_ride_seconds")), 0.0)
	assert_true(_main.call("travel_to_site", FIXER))
	assert_false(_main.call("is_van_ride_visible"))
	assert_eq(_book().active_id, FIXER, "the switch happened all the same")


func test_the_ride_runs_only_for_a_real_site_change() -> void:
	await _start(2.0)
	assert_false(_main.call("travel_to_site", SiteBook.HOME_ID), "already here: switch_site refuses")
	assert_false(_main.call("is_van_ride_visible"), "same site, no ride")
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("travel_to_site", FIXER), "a refused switch")
	assert_false(_main.call("is_van_ride_visible"), "nothing changed, no ride")
	assert_eq(_book().active_id, SiteBook.HOME_ID)


func test_the_ride_follows_a_switch_to_another_neighbourhood() -> void:
	await _start(2.0)
	assert_true(_main.call("travel_to_site", FIXER))
	assert_eq(_book().active_id, FIXER, "the switch is done before the ride")
	assert_true(_main.call("is_van_ride_visible"))
	var line: String = _ride().line()
	assert_false(line.is_empty())
	var lines: CommuteLines = CommuteLines.load_default()
	var allowed: PackedStringArray = lines.pool(CityMap.load_default().neighbourhood(&"millbrook").commute_line)
	assert_true(allowed.has(line), "a line from the data: %s" % line)
	_ride().tick(5.0)
	assert_false(_main.call("is_van_ride_visible"), "it ends by itself")


func test_the_ride_needs_two_neighbourhoods_and_map_art() -> void:
	await _start(2.0)
	assert_false(_main.call("_start_van_ride", SiteBook.HOME_ID, SiteBook.HOME_ID, 1), "same neighbourhood")
	assert_false(_main.call("_start_van_ride", &"nowhere", FIXER, 1), "a lot with no neighbourhood")
	assert_false(_main.call("is_van_ride_visible"))
	(_main.get_node("Overlay/CityPanel") as CityPanel).map_texture = null
	assert_true(_main.call("travel_to_site", FIXER))
	assert_false(_main.call("is_van_ride_visible"), "no map art, just the switch")
	assert_eq(_book().active_id, FIXER)


func test_skip_ends_it_at_once_by_key_click_or_call() -> void:
	await _start(2.0)
	assert_true(_main.call("travel_to_site", FIXER))
	assert_true(_main.call("is_van_ride_visible"))
	_main.call("skip_van_ride")
	assert_false(_main.call("is_van_ride_visible"))
	assert_true(_main.call("travel_to_site", SiteBook.HOME_ID))
	assert_true(_main.call("is_van_ride_visible"))
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	_main.call("_unhandled_input", key)
	assert_false(_main.call("is_van_ride_visible"), "any key skips")
	assert_true(_main.call("travel_to_site", FIXER))
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_ride()._gui_input(click)
	assert_false(_main.call("is_van_ride_visible"), "a click skips")


func test_the_commute_line_never_repeats_back_to_back() -> void:
	await _start(2.0)
	var seen: Array[String] = []
	for trip: int in range(6):
		var target: StringName = FIXER if trip % 2 == 0 else SiteBook.HOME_ID
		# Back in the morning for each trip, as the real game has it.
		Clock.sim.phase = SimClock.Phase.MORNING
		assert_true(_main.call("travel_to_site", target), "trip %d" % trip)
		assert_true(_main.call("is_van_ride_visible"))
		seen.append(_ride().line())
		_ride().skip()
	for index: int in range(1, seen.size()):
		assert_ne(seen[index], seen[index - 1], "trip %d repeated a line" % index)


## The switch's whole effect: the active site, the cash and every per-site
## section, as a ride or no ride leaves them.
func _after_switch(ride_seconds: float) -> Dictionary:
	await _start(ride_seconds)
	assert_true(_main.call("travel_to_site", FIXER))
	var result: Dictionary = {
		"active": _book().active_id,
		"cash": Economy.cash,
		"day": Clock.sim.day,
		"phase": Clock.sim.phase,
		"sections": SaveSystem.capture_sections(SiteSections.PER_SITE),
		"ride": _main.call("is_van_ride_visible"),
	}
	_close()
	Economy.reset(0)
	GameState.new_run(1)
	return result


func test_the_switch_is_identical_with_and_without_the_ride() -> void:
	var plain: Dictionary = await _after_switch(0.0)
	var ridden: Dictionary = await _after_switch(2.0)
	assert_false(plain["ride"])
	assert_true(ridden["ride"])
	for key: String in ["active", "cash", "day", "phase", "sections"]:
		assert_eq(ridden[key], plain[key], "the ride changed %s" % key)


func test_the_morning_card_offers_the_map_and_it_opens_the_city_screen() -> void:
	await _start(0.0)
	assert_true(_main.call("set_site_card_visible", true))
	var button: Button = _card().get_node("Center/Panel/Content/List/Footer/SeeMap") as Button
	assert_not_null(button)
	assert_eq(button.text, "See the map")
	button.pressed.emit()
	assert_false(_main.call("is_site_card_visible"), "the card gives way")
	assert_true(_main.call("is_city_visible"), "the city screen opens")


func test_the_map_button_waits_for_tier_three_and_stays_off_the_purchase_question() -> void:
	await _start(0.0)
	(_main.get("owner_progress") as OwnerProgress).career_tier = 2
	assert_true(_main.call("set_site_card_visible", true))
	assert_null(_card().get_node_or_null("Center/Panel/Content/List/Footer"), "the map opens from Tier 3")
	_main.call("set_site_card_visible", false)
	(_main.get("owner_progress") as OwnerProgress).career_tier = 3
	_card().show_prompt("Q", "Detail", "Yes", "No")
	assert_null(_card().get_node_or_null("Center/Panel/Content/List/Footer"))
