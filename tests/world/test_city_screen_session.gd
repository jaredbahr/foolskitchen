extends TestCase
## The city screen in a real session (docs/CITY_MAP.md, phase C2): the Menu's
## City button from Tier 3, the neighbourhoods in map order with your
## restaurants and the lots around town, "Work here today" switching site in
## the morning, and the market one click away. Opening it moves no money and
## changes no saved state.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const FIXER: StringName = &"town_fixer_upper"

var _main: Node


func after_each() -> void:
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 7)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _menu() -> MenuPanel:
	return _main.get_node("Overlay/MenuPanel") as MenuPanel


func _panel() -> CityPanel:
	return _main.get_node("Overlay/CityPanel") as CityPanel


func _book() -> SiteBook:
	return _main.get("site_book")


func _owner() -> OwnerProgress:
	return _main.get("owner_progress")


func _set_cash(amount: int) -> void:
	Economy.add_cash(amount - Economy.cash, Ledger.OTHER, "test cash")


func test_the_city_is_hidden_below_tier_three() -> void:
	await _start()
	for tier: int in [1, 2]:
		_owner().career_tier = tier
		assert_true(_main.call("set_menu_visible", true))
		assert_false(_menu().is_city_available(), "no City button at Tier %d" % tier)
		assert_false(_main.call("set_city_visible", true), "the screen refuses below Tier 3")
		assert_false(_main.call("is_city_visible"))
		_main.call("set_menu_visible", false)


func test_tier_three_lists_the_neighbourhoods_and_the_lots_without_changing_anything() -> void:
	await _start()
	_owner().career_tier = 3
	assert_true(_main.call("set_menu_visible", true))
	assert_true(_menu().is_city_available())
	var cash: int = Economy.cash
	var before: Dictionary = SaveSystem.capture_sections(SiteSections.PER_SITE)
	(_menu().get_node("%CityButton") as Button).pressed.emit()
	assert_true(_main.call("is_city_visible"))
	assert_false(_main.call("is_menu_visible"), "the screen replaces the Menu")
	assert_eq(_panel().area_ids(), CityMap.load_default().ids(), "map order")
	assert_eq(_panel().site_ids(), [SiteBook.HOME_ID] as Array[StringName])
	var home: Control = _panel().row_for(SiteBook.HOME_ID)
	assert_eq((home.get_node("Body/Status") as Label).text, "You are here")
	var here: Button = home.get_node("Body/Top/Go") as Button
	assert_true(here.disabled)
	var fixer: Control = _panel().row_for(FIXER)
	assert_eq(fixer.get_meta(&"state"), CityMap.LotState.FOR_SALE)
	assert_not_null(fixer.get_node("Body/Top/Market"), "a lot for sale links to the market")
	var rooftop: Control = _panel().row_for(&"skyscraper_rooftop")
	assert_eq(rooftop.get_meta(&"state"), CityMap.LotState.LOCKED)
	assert_eq((rooftop.get_node("Body/Line") as Label).text, "Locked: needs Tier 4 and 4.3 stars")
	assert_eq(_panel().row_for(&"skyline").get_meta(&"state"), CityMap.AreaState.LOCKED)
	assert_eq((_panel().row_for(&"skyline").get_node("State") as Label).text, "Opens at Tier 4")
	# Pinewood holds the Woodland Cabin (Tier 3, 4.0 stars): at Tier 3 with no
	# closing stars yet it is locked, and says what is missing, not a tier.
	assert_eq(_panel().row_for(&"pinewood").get_meta(&"state"), CityMap.AreaState.LOCKED)
	assert_eq((_panel().row_for(&"pinewood").get_node("State") as Label).text, "Locked: needs 4.0 stars")
	var cabin: Control = _panel().row_for(&"woodland_cabin")
	assert_eq(cabin.get_meta(&"state"), CityMap.LotState.LOCKED)
	assert_eq((cabin.get_node("Body/Line") as Label).text, "Locked: needs 4.0 stars")
	assert_eq(Economy.cash, cash, "browsing is free")
	assert_eq(JSON.stringify(SaveSystem.capture_sections(SiteSections.PER_SITE)), JSON.stringify(before),
		"the summary's capture changes nothing")
	_panel().close_requested.emit()
	assert_false(_main.call("is_city_visible"))
	assert_true(_main.call("is_menu_visible"), "closing goes back to the Menu")


func test_the_market_is_one_click_away() -> void:
	await _start()
	_owner().career_tier = 3
	assert_true(_main.call("set_menu_visible", true))
	assert_true(_main.call("set_city_visible", true))
	(_panel().row_for(FIXER).get_node("Body/Top/Market") as Button).pressed.emit()
	assert_false(_main.call("is_city_visible"))
	assert_true(_main.call("is_property_visible"))


func test_work_here_today_switches_site_in_the_morning() -> void:
	await _start()
	_owner().career_tier = 3
	_set_cash(9000)
	assert_true(_main.call("buy_lot", FIXER))
	assert_true(_main.call("set_menu_visible", true))
	assert_true(_main.call("set_city_visible", true))
	assert_eq(_panel().site_ids(), [SiteBook.HOME_ID, FIXER] as Array[StringName])
	var mill: Control = _panel().row_for(FIXER)
	assert_eq((mill.get_node("Body/Status") as Label).text, "Still renovating: 3 days left")
	assert_true((mill.get_node("Body/Tonight") as Label).text.begins_with("Tonight: -$"),
		"a renovating site pays its rent tonight")
	var go: Button = mill.get_node("Body/Top/Go") as Button
	assert_eq(go.text, "Design here today")
	assert_false(go.disabled)
	go.pressed.emit()
	assert_eq(_book().active_id, FIXER, "the same switch as the morning card")
	assert_false(_main.call("is_city_visible"))


func test_the_city_is_a_morning_view() -> void:
	await _start()
	_owner().career_tier = 3
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("set_city_visible", true), "not during service")
	assert_false(_main.call("is_city_visible"))


func test_dismissing_the_market_dismisses_the_city() -> void:
	await _start()
	_owner().career_tier = 3
	assert_true(_main.call("set_menu_visible", true))
	assert_true(_main.call("set_city_visible", true))
	_main.call("_dismiss_property")
	assert_false(_main.call("is_city_visible"))
