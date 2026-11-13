extends TestCase
## The morning Menu's Property button (FK-087 part 2): hidden below Tier 3,
## then a browse-only screen whose Buy buttons say "Coming soon". Opening it
## changes no money, tier, save or sim state.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

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


func _start() -> Node:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 7)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	return _main


func _menu() -> MenuPanel:
	return _main.get_node("Overlay/MenuPanel") as MenuPanel


func _panel() -> PropertyPanel:
	return _main.get_node("Overlay/PropertyPanel") as PropertyPanel


func test_property_is_hidden_below_tier_three() -> void:
	await _start()
	var owner: OwnerProgress = _main.get("owner_progress") as OwnerProgress
	for tier: int in [1, 2]:
		owner.career_tier = tier
		assert_true(_main.call("set_menu_visible", true))
		assert_false(_menu().is_property_available(), "no Property button at Tier %d" % tier)
		assert_false((_menu().get_node("%PropertyButton") as Button).visible)
		assert_false(_main.call("set_property_visible", true), "the screen refuses below Tier 3")
		assert_false(_main.call("is_property_visible"))
		_main.call("set_menu_visible", false)


func test_tier_three_browses_lots_cheapest_first_and_cannot_buy() -> void:
	await _start()
	var owner: OwnerProgress = _main.get("owner_progress") as OwnerProgress
	owner.career_tier = 3
	assert_true(_main.call("set_menu_visible", true))
	assert_true(_menu().is_property_available())
	var cash: int = Economy.cash
	var saved_owner: Dictionary = owner.to_dict()
	(_menu().get_node("%PropertyButton") as Button).pressed.emit()
	assert_true(_main.call("is_property_visible"))
	assert_false(_main.call("is_menu_visible"), "the screen replaces the Menu")
	assert_eq(_panel().lot_ids(), [&"town_fixer_upper", &"seaside_cliff", &"skyscraper_rooftop"] as Array[StringName])
	for id: StringName in _panel().lot_ids():
		var card: Control = _panel().card_for(id)
		var buy: Button = card.get_node("Body/Top/Buy") as Button
		assert_true(buy.disabled, "browse only")
		assert_eq(buy.text, "Coming soon")
		for label: Label in card.find_children("*", "Label", true, false):
			assert_false(label.text.contains(String(id)) or label.text.contains("_"), "no raw id on screen: " + label.text)
	var rooftop: Control = _panel().card_for(&"skyscraper_rooftop")
	assert_true(rooftop.get_meta(&"locked"), "the rooftop needs Tier 4")
	assert_true((rooftop.get_node("Body/Lock") as Label).text.begins_with("Locked: needs Tier 4"))
	assert_null(_panel().card_for(&"town_fixer_upper").get_node_or_null("Body/Lock"), "the fixer-upper is open at Tier 3")
	assert_eq(Economy.cash, cash, "browsing spends nothing")
	assert_eq(owner.to_dict(), saved_owner)
	assert_true(_main.call("set_property_visible", false))
	assert_false(_main.call("is_property_visible"))
	assert_true(_main.call("is_menu_visible"), "closing returns to the Menu")


func test_service_hides_the_screen_and_the_button_needs_the_morning() -> void:
	await _start()
	(_main.get("owner_progress") as OwnerProgress).career_tier = 3
	assert_true(_main.call("set_menu_visible", true))
	assert_true(_main.call("set_property_visible", true))
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("is_property_visible"), "opening the restaurant closes the screen")
	assert_false(_main.call("set_property_visible", true), "the market is a morning screen")
