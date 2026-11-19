extends TestCase
## The city screen's words and list (docs/CITY_MAP.md): ChainText lines for
## every status and alert, and CityPanel built from a hand-made view. No
## session, no enum or id in player text (rule 11).


func _site(id: StringName, status: ChainSummary.Status) -> ChainSummary.Site:
	var site: ChainSummary.Site = ChainSummary.Site.new()
	site.id = id
	site.lot = id
	site.name = "Shop %s" % id
	site.status = status
	site.staffed = true
	return site


func _area(id: StringName, display_name: String, lots: Array[StringName], soon: String = "") -> NeighbourhoodDef:
	var area: NeighbourhoodDef = NeighbourhoodDef.new()
	area.id = id
	area.display_name = display_name
	area.lots = lots
	area.coming_soon = soon
	return area


func _lot(id: StringName, tier: int) -> LotDef:
	var lot: LotDef = LotDef.new()
	lot.id = id
	lot.display_name = "Lot %s" % id
	lot.min_tier = tier
	lot.price = 11500
	return lot


func test_status_lines() -> void:
	var here: ChainSummary.Site = _site(&"home", ChainSummary.Status.HERE)
	assert_eq(ChainText.status_line(here), "You are here")
	here.renovation_days = 2
	assert_eq(ChainText.status_line(here), "You are here · Still renovating: 2 days left")
	var managed: ChainSummary.Site = _site(&"pier", ChainSummary.Status.MANAGED)
	managed.manager_name = "Morgan"
	assert_eq(ChainText.status_line(managed), "Managed by Morgan")
	assert_eq(ChainText.status_line(_site(&"cliff", ChainSummary.Status.CLOSED)), "Closed")
	var renovating: ChainSummary.Site = _site(&"mill", ChainSummary.Status.RENOVATING)
	renovating.renovation_days = 1
	assert_eq(ChainText.status_line(renovating), "Still renovating: 1 day left")


func test_money_lines() -> void:
	var here: ChainSummary.Site = _site(&"home", ChainSummary.Status.HERE)
	here.yesterday_takings = 1412
	assert_eq(ChainText.yesterday_line(here), "Yesterday's takings: $1,412")
	assert_eq(ChainText.tonight_line(here), "", "the active site has no away result")
	var managed: ChainSummary.Site = _site(&"pier", ChainSummary.Status.MANAGED)
	managed.yesterday_earnings = 36
	managed.tonight = -12
	assert_eq(ChainText.yesterday_line(managed), "Yesterday (after the manager): +$36")
	assert_eq(ChainText.tonight_line(managed), "Tonight: about -$12", "a loss reads as one")
	var closed: ChainSummary.Site = _site(&"cliff", ChainSummary.Status.CLOSED)
	closed.tonight = -195
	assert_eq(ChainText.yesterday_line(closed), "")
	assert_eq(ChainText.tonight_line(closed), "Tonight: -$195 in rent and wages")
	closed.tonight = 0
	assert_eq(ChainText.tonight_line(closed), "Tonight: nothing to pay")


func test_manager_and_standing_lines() -> void:
	var site: ChainSummary.Site = _site(&"pier", ChainSummary.Status.MANAGED)
	assert_eq(ChainText.manager_line(site), "No manager")
	site.manager_name = "Morgan"
	site.manager_skill = 3
	site.manager_rate = 0.85
	assert_eq(ChainText.manager_line(site), "Manager: Morgan (keeps 85% of what you made here)")
	assert_eq(ChainText.standing_line(site), "No stars yet · No team yet")
	site.stars = 4.25
	site.golden_ladles = 2
	site.mood = 3.0
	assert_eq(ChainText.standing_line(site), "★ 4.2 · Golden Ladles: 2 · Team: happy")
	assert_eq(ChainText.mood(2.0), "Team: fine")
	assert_eq(ChainText.mood(1.0), "Team: unhappy")


func test_every_alert_has_a_plain_sentence() -> void:
	for alert: int in ChainSummary.Alert.values():
		var line: String = ChainText.alert_line(alert)
		assert_false(line.is_empty(), "alert %d has words" % alert)
		assert_false(line.contains("_"), "no internal names: %s" % line)
		assert_true(line.ends_with("."), line)


func test_go_label() -> void:
	var here: ChainSummary.Site = _site(&"home", ChainSummary.Status.HERE)
	assert_eq(ChainText.go_label(here, ""), "You are here")
	var away: ChainSummary.Site = _site(&"pier", ChainSummary.Status.CLOSED)
	assert_eq(ChainText.go_label(away, ""), "Work here today")
	assert_eq(ChainText.go_label(away, "Mornings only"), "Mornings only")
	away.renovation_days = 2
	assert_eq(ChainText.go_label(away, ""), "Design here today")


func test_area_lot_and_chain_lines() -> void:
	assert_eq(ChainText.area_line(CityMap.AreaState.OPEN, 3, ""), "")
	assert_eq(ChainText.area_line(CityMap.AreaState.LOCKED, 4, ""), "Opens at Tier 4")
	assert_eq(ChainText.area_line(CityMap.AreaState.COMING_SOON, 0, "A cabin in the woods"),
		"Coming soon: A cabin in the woods")
	var lot: LotDef = _lot(&"pier", 4)
	assert_eq(ChainText.lot_line(lot, CityMap.LotState.FOR_SALE, 4, NAN), "For sale · $11,500 · move-in ready")
	assert_eq(ChainText.lot_line(lot, CityMap.LotState.LOCKED, 3, NAN), "Locked: needs Tier 4")
	var a: ChainSummary.Site = _site(&"a", ChainSummary.Status.HERE)
	a.stars = 4.0
	a.golden_ladles = 1
	var b: ChainSummary.Site = _site(&"b", ChainSummary.Status.MANAGED)
	b.stars = 4.4
	assert_eq(ChainText.chain_line([a, b] as Array[ChainSummary.Site]),
		"2 restaurants · ★ 4.2 average · Golden Ladles: 1")
	assert_eq(ChainText.chain_line([_site(&"c", ChainSummary.Status.HERE)] as Array[ChainSummary.Site]),
		"1 restaurant · Golden Ladles: 0")
	assert_eq(ChainText.alerts_heading(0), "")
	assert_eq(ChainText.alerts_heading(1), "1 thing needs you")
	assert_eq(ChainText.alerts_heading(3), "3 things need you")


func test_the_panel_lists_areas_sites_and_lots_in_map_order() -> void:
	var panel: CityPanel = (load("res://src/ui/city_panel.tscn") as PackedScene).instantiate() as CityPanel
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	var map: CityMapDef = CityMapDef.new()
	map.neighbourhoods = [_area(&"old", "Old", [&"home"]), _area(&"sea", "Sea", [&"pier", &"cliff"]),
		_area(&"woods", "Woods", [] as Array[StringName], "A cabin")] as Array[NeighbourhoodDef]
	var view: CityPanel.View = CityPanel.View.new()
	var home: ChainSummary.Site = _site(&"home", ChainSummary.Status.HERE)
	var pier: ChainSummary.Site = _site(&"pier", ChainSummary.Status.CLOSED)
	pier.alerts = [ChainSummary.Alert.NO_MANAGER] as Array[ChainSummary.Alert]
	view.sites = [home, pier] as Array[ChainSummary.Site]
	view.refusals = {&"pier": "Mornings only"}
	view.lots = [_lot(&"pier", 3), _lot(&"cliff", 4)] as Array[LotDef]
	view.career_tier = 3
	panel.set_city(map, view)
	assert_eq(panel.area_ids(), [&"old", &"sea", &"woods"] as Array[StringName])
	assert_eq(panel.site_ids(), [&"home", &"pier"] as Array[StringName])
	var go: Button = panel.row_for(&"pier").get_node("Body/Top/Go") as Button
	assert_true(go.disabled)
	assert_eq(go.text, "Mornings only")
	assert_eq((panel.row_for(&"pier").get_node("Body/Alert0") as Label).text,
		"Closed: nobody runs it while you're away, and it still pays rent.")
	assert_eq(panel.row_for(&"cliff").get_meta(&"state"), CityMap.LotState.LOCKED)
	assert_eq((panel.row_for(&"alerts").get_node("Heading") as Label).text, "1 thing needs you")
	assert_eq((panel.get_node("%Chain") as Label).text, "2 restaurants · Golden Ladles: 0")
	# Picking a site emits its id; the session decides.
	view.refusals = {&"pier": ""}
	panel.set_city(map, view)
	var chosen: Array[StringName] = []
	panel.site_chosen.connect(chosen.append)
	(panel.row_for(&"pier").get_node("Body/Top/Go") as Button).pressed.emit()
	assert_eq(chosen, [&"pier"] as Array[StringName])
	panel.get_parent().remove_child(panel)
	panel.free()


func test_pin_badges_and_positions() -> void:
	assert_eq(ChainText.pin_badge(_site(&"home", ChainSummary.Status.HERE)), "Here")
	assert_eq(ChainText.pin_badge(_site(&"a", ChainSummary.Status.MANAGED)), "Managed")
	assert_eq(ChainText.pin_badge(_site(&"b", ChainSummary.Status.RENOVATING)), "Renovating")
	var closed: ChainSummary.Site = _site(&"c", ChainSummary.Status.CLOSED)
	assert_eq(ChainText.pin_badge(closed), "Closed")
	closed.alerts = [ChainSummary.Alert.NO_MANAGER] as Array[ChainSummary.Alert]
	assert_eq(ChainText.pin_badge(closed), "Needs you")
	assert_eq(CityPanel.pin_position(Vector2(0.5, 0.5), 0, 1), Vector2(0.5, 0.57))
	assert_eq(CityPanel.pin_position(Vector2(0.5, 0.5), 0, 2), Vector2(0.46, 0.57))
	assert_eq(CityPanel.pin_position(Vector2(0.5, 0.5), 1, 2), Vector2(0.54, 0.57))
	assert_eq(CityPanel.pin_position(Vector2(0.99, 0.99), 1, 2), Vector2(1.0, 1.0), "kept on the map")


func test_the_map_view_shows_once_the_art_is_in() -> void:
	var panel: CityPanel = (load("res://src/ui/city_panel.tscn") as PackedScene).instantiate() as CityPanel
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	var map: CityMapDef = CityMapDef.new()
	map.neighbourhoods = [_area(&"old", "Old", [&"home"]), _area(&"sea", "Sea", [&"pier", &"cliff"])] \
		as Array[NeighbourhoodDef]
	var view: CityPanel.View = CityPanel.View.new()
	view.sites = [_site(&"home", ChainSummary.Status.HERE)] as Array[ChainSummary.Site]
	view.lots = [_lot(&"pier", 3), _lot(&"cliff", 4)] as Array[LotDef]
	view.career_tier = 3
	panel.set_city(map, view)
	assert_false((panel.get_node("%MapView") as Control).visible, "no art yet: the plain list")
	assert_eq(panel.pins().size(), 0)
	panel.map_texture = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGB8))
	panel.set_city(map, view)
	assert_true((panel.get_node("%MapView") as Control).visible)
	var kinds: Array[String] = []
	for pin: CityPin in panel.pins():
		kinds.append("%s:%s" % [pin.row_id, pin.kind])
	assert_eq(kinds, ["old:area", "home:shop", "sea:area", "pier:for_sale", "cliff:locked"] as Array[String])
	assert_eq(panel.pins()[1].text, "Shop home\nHere")
	panel.get_parent().remove_child(panel)
	panel.free()
