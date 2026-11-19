extends TestCase
## The illustrated city map (#642): pins land on the drawn map at any window
## size, the list stays one tap away, and areas waiting on a tier or a lot get
## roadworks or a hoarding that say what opens them.

var _holder: SubViewport


func after_each() -> void:
	if is_instance_valid(_holder):
		if _holder.is_inside_tree():
			_holder.get_parent().remove_child(_holder)
		_holder.free()
	_holder = null


func _site(id: StringName, status: ChainSummary.Status) -> ChainSummary.Site:
	var site: ChainSummary.Site = ChainSummary.Site.new()
	site.id = id
	site.lot = id
	site.name = "Shop %s" % id
	site.status = status
	site.staffed = true
	return site


func _lot(id: StringName, tier: int) -> LotDef:
	var lot: LotDef = LotDef.new()
	lot.id = id
	lot.display_name = "Lot %s" % id
	lot.min_tier = tier
	lot.price = 11500
	return lot


func _area(id: StringName, at: Vector2, lots: Array[StringName], soon: String = "") -> NeighbourhoodDef:
	var area: NeighbourhoodDef = NeighbourhoodDef.new()
	area.id = id
	area.display_name = String(id).capitalize()
	area.map_position = at
	area.lots = lots
	area.coming_soon = soon
	return area


## A panel in a screen of the given size, filled with a small town: the home
## shop, a lot for sale, a locked lot (roadworks) and an area with no lot yet
## (a hoarding).
func _panel(screen: Vector2i, texture: Texture2D = null) -> CityPanel:
	_holder = SubViewport.new()
	_holder.size = screen
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)
	var panel: CityPanel = (load("res://src/ui/city_panel.tscn") as PackedScene).instantiate() as CityPanel
	if texture != null:
		panel.map_texture = texture
	_holder.add_child(panel)
	var map: CityMapDef = CityMapDef.new()
	map.neighbourhoods = [
		_area(&"old", Vector2(0.5, 0.45), [&"home"] as Array[StringName]),
		_area(&"sea", Vector2(0.3, 0.72), [&"pier", &"cliff"] as Array[StringName]),
		_area(&"sky", Vector2(0.76, 0.55), [&"tower"] as Array[StringName]),
		_area(&"woods", Vector2(0.62, 0.14), [] as Array[StringName], "A cabin in the woods"),
	] as Array[NeighbourhoodDef]
	var view: CityPanel.View = CityPanel.View.new()
	view.sites = [_site(&"home", ChainSummary.Status.HERE)] as Array[ChainSummary.Site]
	view.lots = [_lot(&"pier", 3), _lot(&"cliff", 3), _lot(&"tower", 4)] as Array[LotDef]
	view.career_tier = 3
	panel.set_city(map, view)
	panel.show()
	return panel


func _settle() -> void:
	for _i: int in 3:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _map_texture() -> Texture2D:
	return load("res://assets/made/city_map/paper_map.png") as Texture2D


func test_the_shipped_map_is_the_default_art() -> void:
	var panel: CityPanel = (load("res://src/ui/city_panel.tscn") as PackedScene).instantiate() as CityPanel
	assert_not_null(panel.map_texture, "the paper map ships with the screen")
	assert_eq(float(panel.map_texture.get_width()) / float(panel.map_texture.get_height()), 1.5, "a 3:2 drawing")
	panel.free()


func test_pins_sit_inside_the_drawn_map_at_two_window_sizes() -> void:
	for screen: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(390, 844)]:
		var panel: CityPanel = _panel(screen, _map_texture())
		await _settle()
		var canvas: Control = panel.get_node("%Canvas") as Control
		assert_true(canvas.size.x > 100.0, "the map is laid out at %s" % screen)
		# The drawing's own shape, whatever the window.
		assert_true(absf(canvas.size.x / canvas.size.y - 1.5) < 0.02, "the map keeps its 3:2 shape at %s" % screen)
		var rect: Rect2 = Rect2(canvas.global_position, canvas.size)
		assert_true(panel.pins().size() >= 6, "a pin per area and lot")
		for pin: CityPin in panel.pins():
			var spot: Vector2 = pin.get_meta(&"map_at")
			var expected: Vector2 = rect.position + spot * rect.size
			var middle: Vector2 = pin.global_position + pin.size / 2.0
			if pin.kind == CityPin.AREA:
				assert_true(middle.distance_to(expected) < 2.0, "%s's name sits on its spot at %s" % [pin.row_id, screen])
			else:
				# The picture, at the top of the pin, is centred on the spot.
				assert_true(absf(middle.x - expected.x) < 2.0, "%s is centred on its spot at %s" % [pin.row_id, screen])
				assert_true(rect.has_point(Vector2(middle.x, pin.global_position.y + 8.0)), "%s is on the map at %s" % [pin.row_id, screen])
		_holder.get_parent().remove_child(_holder)
		_holder.free()
		_holder = null


## The shipped town (the real map and lots) at a given tier, optionally with
## Pinewood still empty (a hoarding), in a screen of the given size.
func _real_panel(screen: Vector2i, tier: int, empty_pinewood: bool) -> CityPanel:
	_holder = SubViewport.new()
	_holder.size = screen
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)
	var panel: CityPanel = (load("res://src/ui/city_panel.tscn") as PackedScene).instantiate() as CityPanel
	_holder.add_child(panel)
	var map: CityMapDef = CityMap.load_default()
	if empty_pinewood:
		var pinewood: NeighbourhoodDef = map.neighbourhood(&"pinewood")
		pinewood.lots = [] as Array[StringName]
		pinewood.coming_soon = "A cabin in the woods"
	var view: CityPanel.View = CityPanel.View.new()
	view.sites = [_site(&"home", ChainSummary.Status.HERE)] as Array[ChainSummary.Site]
	var cliff: ChainSummary.Site = _site(&"cliff", ChainSummary.Status.CLOSED)
	cliff.lot = &"seaside_cliff"
	cliff.name = "Seaside Cliff"
	cliff.alerts = [ChainSummary.Alert.NO_MANAGER] as Array[ChainSummary.Alert]
	view.sites.append(cliff)
	for path: String in ["town_fixer_upper", "beachfront_boardwalk", "seaside_cliff", "skyscraper_rooftop", "woodland_cabin"]:
		view.lots.append(load("res://data/lots/%s.tres" % path) as LotDef)
	view.career_tier = tier
	view.reputation = 3.8
	panel.set_city(map, view)
	panel.show()
	return panel


## Every pin's whole rect (picture and words) is on the drawn map, never across
## the paper's edge, in map px.
func _assert_pins_on_the_map(panel: CityPanel, where: String) -> void:
	var canvas: Control = panel.get_node("%Canvas") as Control
	var paper: Rect2 = Rect2(Vector2.ZERO, canvas.size).grow(-canvas.size.x * CityPanel.EDGE_MARGIN + 0.5)
	for pin: CityPin in panel.pins():
		if pin.kind == CityPin.AREA:
			continue
		assert_true(paper.encloses(Rect2(pin.global_position - canvas.global_position, pin.size)),
			"%s's picture and label are inside the map at %s" % [pin.row_id, where])


## No sign (picture and tag together) covers a name banner, a pin's label or another sign.
func _assert_signs_are_clear(panel: CityPanel, where: String) -> void:
	var canvas: Control = panel.get_node("%Canvas") as Control
	var signs: Array[Rect2] = panel.sign_rects()
	assert_true(signs.size() >= 2, "there are signs to check at %s" % where)
	for index: int in range(signs.size()):
		assert_true(Rect2(Vector2.ZERO, canvas.size).encloses(signs[index]), "sign %d is on the map at %s" % [index, where])
		for pin: CityPin in panel.pins():
			var rect: Rect2 = Rect2(pin.global_position - canvas.global_position, pin.size)
			assert_false(signs[index].intersects(rect), "sign %d clears %s (%s) at %s" % [index, pin.row_id, pin.kind, where])
		for other: int in range(index + 1, signs.size()):
			assert_false(signs[index].intersects(signs[other]), "signs %d and %d do not overlap at %s" % [index, other, where])


func test_every_pin_label_stays_on_the_map() -> void:
	for screen: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(390, 844)]:
		for tier: int in [3, 5]:
			var panel: CityPanel = _real_panel(screen, tier, false)
			await _settle()
			_assert_pins_on_the_map(panel, "%s tier %d" % [screen, tier])
			_holder.get_parent().remove_child(_holder)
			_holder.free()
			_holder = null
	var small: CityPanel = _panel(Vector2i(390, 844), _map_texture())
	await _settle()
	_assert_pins_on_the_map(small, "the test town at the phone fixture")


func test_signs_and_tags_never_cover_banners_pins_or_each_other() -> void:
	for screen: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(390, 844)]:
		for empty: bool in [false, true]:
			var panel: CityPanel = _real_panel(screen, 3, empty)
			await _settle()
			_assert_signs_are_clear(panel, "%s hoarding %s" % [screen, empty])
			_holder.get_parent().remove_child(_holder)
			_holder.free()
			_holder = null


func test_the_card_sits_beside_the_map_on_a_wide_screen_and_under_it_on_a_phone() -> void:
	var wide: CityPanel = _real_panel(Vector2i(1600, 900), 3, false)
	await _settle()
	var canvas: Control = wide.get_node("%Canvas") as Control
	var detail: Control = wide.get_node("%Detail") as Control
	var before: Vector2 = canvas.size
	assert_true(wide.card_is_beside(), "a wide screen puts the card beside the map")
	wide.pin_pressed_for_review(&"cliff")
	await _settle()
	assert_eq(canvas.size, before, "the open card does not shrink the map")
	assert_true(detail.global_position.x >= canvas.global_position.x + canvas.size.x - 1.0, "the card is right of the map")
	assert_true(detail.get_child(0).size.x >= CityPanel.SIDE_CARD_WIDTH - 1.0, "and wide enough to read")
	assert_true(canvas.size.x > 700.0, "the map keeps its size at 1600x900")
	_holder.get_parent().remove_child(_holder)
	_holder.free()
	var phone: CityPanel = _real_panel(Vector2i(390, 844), 3, false)
	await _settle()
	canvas = phone.get_node("%Canvas") as Control
	detail = phone.get_node("%Detail") as Control
	assert_false(phone.card_is_beside(), "a phone keeps the card under the map")
	phone.pin_pressed_for_review(&"cliff")
	await _settle()
	assert_true(detail.global_position.y >= canvas.global_position.y + canvas.size.y - 1.0, "the card is under the map")
	assert_true(canvas.size.x > 300.0, "the map still fits the phone's width")


func test_the_list_toggle_swaps_the_map_and_the_list() -> void:
	var panel: CityPanel = _panel(Vector2i(1600, 900), _map_texture())
	await _settle()
	var toggle: Button = panel.get_node("%ViewToggle") as Button
	assert_true(toggle.visible)
	assert_true(panel.is_map_showing())
	assert_eq(toggle.text, ChainText.SHOW_LIST)
	assert_false((panel.get_node("Panel/Content/Scroll") as Control).visible)
	toggle.pressed.emit()
	assert_false(panel.is_map_showing())
	assert_eq(toggle.text, ChainText.SHOW_MAP)
	assert_true((panel.get_node("Panel/Content/Scroll") as Control).visible, "the list is back")
	assert_not_null(panel.row_for(&"home"), "with its rows")
	toggle.pressed.emit()
	assert_true(panel.is_map_showing())


func test_without_art_there_is_only_the_list_and_no_toggle() -> void:
	var panel: CityPanel = _panel(Vector2i(1600, 900))
	panel.map_texture = null
	panel.set_city(CityMap.load_default(), CityPanel.View.new())
	assert_false(panel.is_map_showing())
	assert_false((panel.get_node("%ViewToggle") as Button).visible)
	assert_true((panel.get_node("Panel/Content/Scroll") as Control).visible)


func test_a_pin_shows_its_card_under_the_map() -> void:
	var panel: CityPanel = _panel(Vector2i(1600, 900), _map_texture())
	await _settle()
	var detail: Control = panel.get_node("%Detail") as Control
	assert_eq(panel.selected_id(), &"")
	panel.get_node("%Pins").get_node("Pin_home").pressed.emit()
	assert_eq(panel.selected_id(), &"home")
	assert_not_null(detail.get_child(0).get_node("Body/Top/Go"), "the shop's card, with its button")
	panel.get_node("%Pins").get_node("Pin_pier").pressed.emit()
	assert_not_null(detail.get_child(0).get_node("Body/Top/Market"), "a lot for sale links to the market")


func test_locked_areas_get_roadworks_and_empty_areas_a_hoarding() -> void:
	var panel: CityPanel = _panel(Vector2i(1600, 900), _map_texture())
	await _settle()
	var overlays: Control = panel.get_node("%Overlays") as Control
	var works: TextureRect = overlays.get_node_or_null("Roadworks_sky") as TextureRect
	var hoarding: TextureRect = overlays.get_node_or_null("Hoarding_woods") as TextureRect
	assert_not_null(works, "Skyline waits on Tier 4: roadworks")
	assert_not_null(hoarding, "no lot yet: a hoarding")
	assert_null(overlays.get_node_or_null("Roadworks_old"), "an open area has none")
	assert_eq((works.get_node("Tag") as Label).text, "Opens at Tier 4")
	assert_true((hoarding.get_node("Tag") as Label).text.replace("\n", " ").begins_with("Coming soon: A cabin"))
	var canvas: Rect2 = Rect2(Vector2.ZERO, (panel.get_node("%Canvas") as Control).size)
	for sign_art: TextureRect in [works, hoarding]:
		assert_true(canvas.encloses(Rect2(sign_art.position, sign_art.size)), "%s is on the map" % sign_art.name)
