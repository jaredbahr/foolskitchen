extends TestCase
## The city map's data and rules (docs/CITY_MAP.md): the shipped neighbourhoods
## validate against the game's lots, every lot stands in exactly one of them,
## and each lot and neighbourhood shows the market's own state. Pure.

const HOME: StringName = NeighbourhoodDef.HOME_LOT


func _lots() -> Array[LotDef]:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all(), PackedStringArray())
	return db.lots()


func _lot(id: StringName, tier: int = 3, stars: float = 0.0, display_name: String = "Test Lot") -> LotDef:
	var lot: LotDef = LotDef.new()
	lot.id = id
	lot.display_name = display_name
	lot.min_tier = tier
	lot.min_reputation = stars
	lot.price = 1000
	return lot


func _area(id: StringName, display_name: String, lots: Array[StringName], soon: String = "") -> NeighbourhoodDef:
	var area: NeighbourhoodDef = NeighbourhoodDef.new()
	area.id = id
	area.display_name = display_name
	area.lots = lots
	area.coming_soon = soon
	area.blurb = "A part of town for tests."
	return area


func _map(areas: Array[NeighbourhoodDef]) -> CityMapDef:
	var map: CityMapDef = CityMapDef.new()
	map.neighbourhoods = areas
	return map


func test_the_home_lot_matches_the_site_book() -> void:
	assert_eq(NeighbourhoodDef.HOME_LOT, SiteBook.HOME_LOT)
	assert_eq(CityMapDef.HOME_LOT, SiteBook.HOME_LOT)


func test_the_shipped_map_is_valid_against_the_game_lots() -> void:
	var map: CityMapDef = CityMap.load_default()
	assert_not_null(map)
	assert_eq(map.validate(CityMap.lot_names(_lots())), PackedStringArray())


func test_every_lot_and_the_home_shop_have_a_neighbourhood() -> void:
	var map: CityMapDef = CityMap.load_default()
	assert_not_null(map.neighbourhood_for_lot(HOME), "the starter shop stands somewhere")
	for lot: LotDef in _lots():
		assert_not_null(map.neighbourhood_for_lot(lot.id), "%s has a neighbourhood" % lot.id)


func test_reads_find_neighbourhoods_by_id_and_lot() -> void:
	var map: CityMapDef = _map([_area(&"a", "Alpha", [HOME]), _area(&"b", "Beta", [&"lot_b"])])
	assert_eq(map.ids(), [&"a", &"b"] as Array[StringName])
	assert_eq(map.neighbourhood(&"b").display_name, "Beta")
	assert_null(map.neighbourhood(&"missing"))
	assert_eq(map.neighbourhood_for_lot(&"lot_b").id, &"b")
	assert_null(map.neighbourhood_for_lot(&"nowhere"))


func test_validation_refuses_a_lot_in_no_neighbourhood() -> void:
	var map: CityMapDef = _map([_area(&"a", "Alpha", [HOME])])
	assert_eq(map.validate(CityMap.lot_names([_lot(&"lot_b")] as Array[LotDef])),
		PackedStringArray(["Lot 'lot_b' is in no neighbourhood"]))


func test_validation_refuses_a_lot_in_two_neighbourhoods() -> void:
	var map: CityMapDef = _map([_area(&"a", "Alpha", [HOME, &"lot_b"]), _area(&"b", "Beta", [&"lot_b"])])
	assert_eq(map.validate(CityMap.lot_names([_lot(&"lot_b")] as Array[LotDef])),
		PackedStringArray(["Lot 'lot_b' is in 2 neighbourhoods"]))


func test_validation_needs_the_home_lot() -> void:
	var map: CityMapDef = _map([_area(&"a", "Alpha", [&"lot_b"])])
	assert_eq(map.validate(CityMap.lot_names([_lot(&"lot_b")] as Array[LotDef])),
		PackedStringArray(["Lot 'home' is in no neighbourhood"]))


func test_validation_refuses_bad_fields() -> void:
	var lots: Array[LotDef] = [_lot(&"lot_b", 3, 0.0, "Pier Shack")]
	var cases: Array[Array] = [
		[_area(&"Bad Id", "Alpha", [HOME]), "has an invalid id"],
		[_area(&"a", "", [HOME]), "needs a trimmed name"],
		[_area(&"a", " Alpha", [HOME]), "needs a trimmed name"],
		[_area(&"a", "Pier Shack", [HOME]), "has the same name as a lot"],
		[_area(&"a", "Alpha", [HOME, &"ghost"]), "lists unknown lot 'ghost'"],
		[_area(&"a", "Alpha", [HOME, HOME]), "lists lot 'home' twice"],
	]
	for case: Array in cases:
		var area: NeighbourhoodDef = case[0]
		var errors: PackedStringArray = _map([area, _area(&"z", "Zed", [&"lot_b"])]).validate(CityMap.lot_names(lots))
		assert_true(" ".join(errors).contains(case[1]), "expected '%s' in %s" % [case[1], errors])


func test_a_coming_soon_area_is_valid_with_no_lots() -> void:
	var map: CityMapDef = _map([_area(&"a", "Alpha", [HOME]), _area(&"s", "Soon", [] as Array[StringName], "A cabin")])
	assert_eq(map.validate({} as Dictionary[StringName, String]), PackedStringArray())
	assert_true(map.neighbourhood(&"s").is_coming_soon())


func test_validation_refuses_an_empty_blurb_and_an_untrimmed_coming_soon() -> void:
	var bare: NeighbourhoodDef = _area(&"a", "Alpha", [HOME])
	bare.blurb = "  "
	var soon: NeighbourhoodDef = _area(&"s", "Soon", [] as Array[StringName], "A cabin ")
	var errors: String = " ".join(_map([bare, soon]).validate({} as Dictionary[StringName, String]))
	assert_true(errors.contains("Neighbourhood 'a' needs a blurb"))
	assert_true(errors.contains("Neighbourhood 's' has a coming-soon line with spaces at its ends"))


func test_validation_refuses_off_map_positions_and_long_blurbs() -> void:
	var area: NeighbourhoodDef = _area(&"a", "Alpha", [HOME])
	area.map_position = Vector2(1.2, 0.5)
	area.blurb = "x".repeat(CityMapDef.MAX_BLURB_LENGTH + 1)
	var errors: String = " ".join(_map([area]).validate({} as Dictionary[StringName, String]))
	assert_true(errors.contains("is off the map"))
	assert_true(errors.contains("has a blurb over"))


func test_validation_refuses_duplicates() -> void:
	var errors: String = " ".join(_map([_area(&"a", "Alpha", [HOME]), _area(&"a", "Alpha", [] as Array[StringName], "Soon")])
		.validate({} as Dictionary[StringName, String]))
	assert_true(errors.contains("is listed twice"))
	assert_true(errors.contains("repeats the name 'Alpha'"))


func test_coming_soon_needs_a_line_and_no_lots() -> void:
	var empty: String = " ".join(_map([_area(&"a", "Alpha", [HOME]), _area(&"b", "Beta", [] as Array[StringName])])
		.validate({} as Dictionary[StringName, String]))
	assert_true(empty.contains("needs a coming-soon line"))
	var both: String = " ".join(_map([_area(&"a", "Alpha", [HOME], "Soon")]).validate({} as Dictionary[StringName, String]))
	assert_true(both.contains("cannot be coming soon"))
	assert_eq(_map([] as Array[NeighbourhoodDef]).validate({} as Dictionary[StringName, String]),
		PackedStringArray(["The city map has no neighbourhoods"]))


func test_lot_state_follows_the_market() -> void:
	var lot: LotDef = _lot(&"lot_b", 4, 4.2)
	assert_eq(CityMap.lot_state(lot, true, 1, NAN), CityMap.LotState.OWNED, "owned wins over any lock")
	assert_eq(CityMap.lot_state(null, true, 3, 4.0), CityMap.LotState.OWNED, "the home lot is owned")
	assert_eq(CityMap.lot_state(null, false, 6, 5.0), CityMap.LotState.UNLISTED)
	assert_eq(CityMap.lot_state(lot, false, 2, 5.0), CityMap.LotState.LOCKED, "below the market tier")
	assert_eq(CityMap.lot_state(lot, false, 3, 5.0), CityMap.LotState.LOCKED, "below the lot's tier")
	assert_eq(CityMap.lot_state(lot, false, 4, 4.1), CityMap.LotState.LOCKED, "short of its stars")
	assert_eq(CityMap.lot_state(lot, false, 4, NAN), CityMap.LotState.LOCKED, "no closing stars yet")
	assert_eq(CityMap.lot_state(lot, false, 4, 4.15), CityMap.LotState.FOR_SALE, "stars at one decimal")
	assert_eq(CityMap.lot_state(_lot(&"free"), false, 3, NAN), CityMap.LotState.FOR_SALE, "no star gate")


func test_area_state() -> void:
	var lots: Array[LotDef] = [_lot(&"lot_b", 3), _lot(&"lot_c", 5)]
	var mixed: NeighbourhoodDef = _area(&"m", "Mixed", [&"lot_b", &"lot_c"])
	var high: NeighbourhoodDef = _area(&"h", "High", [&"lot_c"])
	var home: NeighbourhoodDef = _area(&"o", "Old", [HOME])
	var soon: NeighbourhoodDef = _area(&"s", "Soon", [] as Array[StringName], "A cabin")
	var owned: Array[StringName] = [HOME]
	assert_eq(CityMap.area_state(mixed, lots, owned, 3, NAN), CityMap.AreaState.OPEN, "one lot for sale")
	assert_eq(CityMap.area_state(mixed, lots, owned, 2, NAN), CityMap.AreaState.LOCKED, "before the market")
	assert_eq(CityMap.area_state(high, lots, owned, 3, NAN), CityMap.AreaState.LOCKED)
	assert_eq(CityMap.area_state(high, lots, [HOME, &"lot_c"] as Array[StringName], 3, NAN),
		CityMap.AreaState.OPEN, "a site there opens it")
	assert_eq(CityMap.area_state(home, lots, owned, 1, NAN), CityMap.AreaState.OPEN)
	assert_eq(CityMap.area_state(soon, lots, owned, 6, 5.0), CityMap.AreaState.COMING_SOON)
	assert_eq(CityMap.area_state(home, lots, [] as Array[StringName], 6, 5.0), CityMap.AreaState.EMPTY,
		"the starter shop sold: nothing there, and no lock to quote")
	var sold_and_locked: NeighbourhoodDef = _area(&"x", "Mixed", [HOME, &"lot_c"])
	assert_eq(CityMap.area_state(sold_and_locked, lots, [] as Array[StringName], 3, NAN), CityMap.AreaState.LOCKED,
		"an unlisted lot beside a locked one still reads locked")


func test_opening_tier_is_the_lowest_lot_gate() -> void:
	var lots: Array[LotDef] = [_lot(&"lot_b", 4), _lot(&"lot_c", 3)]
	assert_eq(CityMap.opening_tier(_area(&"m", "M", [&"lot_b", &"lot_c"]), lots), 3)
	assert_eq(CityMap.opening_tier(_area(&"o", "O", [HOME]), lots), 1)
	assert_eq(CityMap.opening_tier(_area(&"s", "S", [] as Array[StringName], "Soon"), lots), 0)
	assert_eq(CityMap.opening_tier(_area(&"g", "G", [&"ghost"]), lots), 0, "an unknown lot has no gate")


func test_shipped_opening_tiers() -> void:
	var map: CityMapDef = CityMap.load_default()
	var lots: Array[LotDef] = _lots()
	assert_eq(CityMap.opening_tier(map.neighbourhood_for_lot(HOME), lots), 1)
	assert_eq(CityMap.opening_tier(map.neighbourhood_for_lot(&"skyscraper_rooftop"), lots), 4)


func test_covered_and_reachable_neighbourhoods_in_map_order() -> void:
	var map: CityMapDef = _map([_area(&"a", "Alpha", [HOME]), _area(&"b", "Beta", [&"lot_b", &"lot_c"]),
		_area(&"c", "Gamma", [&"lot_d"]), _area(&"s", "Soon", [] as Array[StringName], "Soon")])
	var lots: Array[LotDef] = [_lot(&"lot_b"), _lot(&"lot_c"), _lot(&"lot_d")]
	assert_eq(map.covered([HOME] as Array[StringName]), [&"a"] as Array[StringName])
	assert_eq(map.covered([&"lot_d", &"lot_c", HOME] as Array[StringName]),
		[&"a", &"b", &"c"] as Array[StringName], "map order, each once")
	assert_eq(map.reachable(CityMap.lot_ids(lots), [HOME] as Array[StringName]), [&"a", &"b", &"c"] as Array[StringName])
	assert_eq(map.reachable([] as Array[StringName], [] as Array[StringName]), [] as Array[StringName],
		"the home lot counts only while owned")


func _road(from: StringName, to: StringName, bends: PackedVector2Array = PackedVector2Array()) -> CityRoadDef:
	var road: CityRoadDef = CityRoadDef.new()
	road.from = from
	road.to = to
	road.bends = bends
	return road


func test_the_shipped_roads_join_every_neighbourhood() -> void:
	var map: CityMapDef = CityMap.load_default()
	for id: StringName in map.ids():
		var joined: bool = false
		for other: StringName in map.ids():
			joined = joined or map.road(id, other) != null
		assert_true(joined, "%s has a road" % id)


func test_road_validation() -> void:
	var map: CityMapDef = _map([_area(&"a", "Alpha", [HOME]), _area(&"b", "Beta", [] as Array[StringName], "Soon")])
	map.roads = [_road(&"a", &"ghost"), _road(&"a", &"a"), _road(&"a", &"b", PackedVector2Array([Vector2(2, 0)])),
		_road(&"b", &"a")] as Array[CityRoadDef]
	var errors: String = " ".join(map.validate({} as Dictionary[StringName, String]))
	assert_true(errors.contains("Road 'a' to 'ghost' names an unknown neighbourhood"))
	assert_true(errors.contains("Road 'a' to 'a' goes nowhere"))
	assert_true(errors.contains("Road 'a' to 'b' bends off the map"))
	assert_true(errors.contains("Road 'b' to 'a' is listed twice"), "one road per pair, either way round")


func test_van_path_follows_the_road_either_way() -> void:
	var a: NeighbourhoodDef = _area(&"a", "Alpha", [HOME])
	a.map_position = Vector2(0.1, 0.1)
	var b: NeighbourhoodDef = _area(&"b", "Beta", [&"lot_b"])
	b.map_position = Vector2(0.9, 0.9)
	var c: NeighbourhoodDef = _area(&"c", "Gamma", [&"lot_c"])
	c.map_position = Vector2(0.5, 0.2)
	var map: CityMapDef = _map([a, b, c])
	map.roads = [_road(&"a", &"b", PackedVector2Array([Vector2(0.3, 0.5), Vector2(0.7, 0.6)]))] as Array[CityRoadDef]
	assert_eq(CityMap.van_path(map, &"a", &"b"), PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.3, 0.5),
		Vector2(0.7, 0.6), Vector2(0.9, 0.9)]))
	assert_eq(CityMap.van_path(map, &"b", &"a"), PackedVector2Array([Vector2(0.9, 0.9), Vector2(0.7, 0.6),
		Vector2(0.3, 0.5), Vector2(0.1, 0.1)]), "the road's bends reversed")
	assert_eq(CityMap.van_path(map, &"a", &"c"), PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.5, 0.2)]),
		"no road: straight across")
	assert_eq(CityMap.van_path(map, &"a", &"a").size(), 0, "no ride to where you are")
	assert_eq(CityMap.van_path(map, &"a", &"ghost").size(), 0)
	assert_eq(map.road(&"b", &"a"), map.roads[0])
	assert_null(map.road(&"a", &"c"))
