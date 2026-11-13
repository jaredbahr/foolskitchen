extends TestCase
## The property market's data (FK-087 part 2, D28): LotDef validation, the
## three starter lots, cheapest-first order, lock rules and the screen's
## words. Browse only: nothing here buys or moves anything.

const CUSTOMER_TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const SEASIDE_PATH: String = "res://data/lots/seaside_cliff.tres"


func _db() -> ContentDB:
	var db: ContentDB = ContentDB.new()
	assert_eq(db.load_all(), PackedStringArray())
	return db


func _customer_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for kind: CustomerType in CUSTOMER_TYPES.types:
		ids.append(kind.id)
	return ids


func _good_lot(id: StringName = &"test_lot") -> LotDef:
	var lot: LotDef = LotDef.new()
	lot.id = id
	lot.display_name = "Test Lot"
	lot.blurb = "A lot for tests."
	lot.base_layout = load("res://data/layouts/lot_seaside_cliff.tres") as ShopLayout
	lot.price = 1000
	lot.daily_rent = 50
	lot.expansion_price = 500
	lot.expanded_daily_rent = 60
	lot.guest_mix = {&"foodie": 1.0}
	return lot


func _errors(lots: Array[LotDef]) -> PackedStringArray:
	return ContentDB.validate_lots(lots, _db().items(), _customer_ids())


func _has_error(errors: PackedStringArray, fragment: String) -> bool:
	for error: String in errors:
		if error.contains(fragment):
			return true
	return false


func test_three_starter_lots_load_with_their_own_layouts() -> void:
	var db: ContentDB = _db()
	var ids: Array[StringName] = []
	var layouts: Dictionary[ShopLayout, bool] = {}
	var sizes: Dictionary[int, bool] = {}
	for lot: LotDef in db.lots():
		ids.append(lot.id)
		layouts[lot.base_layout] = true
		sizes[lot.size_cells()] = true
	assert_eq(ids, [&"seaside_cliff", &"skyscraper_rooftop", &"town_fixer_upper"])
	assert_eq(layouts.size(), 3, "each lot has its own layout")
	assert_eq(sizes.size(), 3, "each lot is a different size")
	var fixer: LotDef = db.lot(&"town_fixer_upper")
	assert_true(fixer.is_fixer_upper())
	assert_eq(fixer.renovation_days, 3)
	assert_true(fixer.upstairs_allowed)
	assert_true(fixer.size_cells() > db.lot(&"seaside_cliff").size_cells(), "the fixer-upper is the big one")
	assert_eq(db.lot(&"skyscraper_rooftop").tags, [&"rooftop"] as Array[StringName])
	assert_eq(db.lot(&"seaside_cliff").tags, [&"seaside"] as Array[StringName])
	assert_true(db.lot(&"skyscraper_rooftop").daily_rent > db.lot(&"seaside_cliff").daily_rent)
	for lot: LotDef in db.lots():
		assert_true(lot.expansion_price > 0 and lot.expanded_daily_rent >= lot.daily_rent, "every lot can expand")
	assert_null(db.lot(&"home"))


func test_each_lot_layout_builds_a_shop_with_its_kitchen() -> void:
	var db: ContentDB = _db()
	for lot: LotDef in db.lots():
		var errors: Array[String] = []
		var sim: RestaurantSim = RestaurantSim.create(lot.base_layout, db, 1, errors)
		assert_eq(errors, [] as Array[String], "%s builds" % lot.id)
		assert_not_null(sim)
		var items: Array[StringName] = []
		for placement: ShopPlacement in lot.base_layout.placements:
			items.append(placement.item_id)
		for station: StringName in [&"fridge", &"prep_counter", &"stove", &"sink", &"pass_counter"]:
			assert_true(items.has(station), "%s has the starter's %s" % [lot.id, station])


func test_a_good_lot_passes_validation() -> void:
	assert_eq(_errors([_good_lot()]), PackedStringArray())
	var fixer: LotDef = _good_lot()
	fixer.price = 0
	fixer.fixer_price = 400
	fixer.renovation_bill = 200
	fixer.renovation_days = 5
	assert_eq(_errors([fixer]), PackedStringArray())


func test_bad_lots_are_reported() -> void:
	var cases: Array[Array] = []
	var no_name: LotDef = _good_lot()
	no_name.display_name = " "
	cases.append([no_name, "display_name is empty"])
	var no_layout: LotDef = _good_lot()
	no_layout.base_layout = null
	cases.append([no_layout, "base_layout is missing"])
	var both_prices: LotDef = _good_lot()
	both_prices.fixer_price = 10
	cases.append([both_prices, "exactly one of price"])
	var no_price: LotDef = _good_lot()
	no_price.price = 0
	cases.append([no_price, "exactly one of price"])
	var long_work: LotDef = _good_lot()
	long_work.price = 0
	long_work.fixer_price = 400
	long_work.renovation_bill = 200
	long_work.renovation_days = 6
	cases.append([long_work, "2 to 5 days"])
	var ready_with_work: LotDef = _good_lot()
	ready_with_work.renovation_days = 2
	cases.append([ready_with_work, "has no renovation"])
	var free_rent: LotDef = _good_lot()
	free_rent.daily_rent = 0
	cases.append([free_rent, "daily_rent must be > 0"])
	var no_expansion: LotDef = _good_lot()
	no_expansion.expansion_price = 0
	cases.append([no_expansion, "every lot can expand"])
	var cheaper_expanded: LotDef = _good_lot()
	cheaper_expanded.expanded_daily_rent = 10
	cases.append([cheaper_expanded, "every lot can expand"])
	var high_tier: LotDef = _good_lot()
	high_tier.min_tier = 7
	cases.append([high_tier, "min_tier must be 1 to 6"])
	var too_many_stars: LotDef = _good_lot()
	too_many_stars.min_reputation = 5.5
	cases.append([too_many_stars, "min_reputation"])
	var no_guests: LotDef = _good_lot()
	no_guests.guest_mix = {}
	cases.append([no_guests, "guest_mix is empty"])
	var tourists: LotDef = _good_lot()
	tourists.guest_mix = {&"tourist": 1.0}
	cases.append([tourists, "unknown customer type 'tourist'"])
	var zero_share: LotDef = _good_lot()
	zero_share.guest_mix = {&"foodie": 0.0}
	cases.append([zero_share, "must be > 0"])
	var odd_tag: LotDef = _good_lot()
	odd_tag.tags = [&"volcano"]
	cases.append([odd_tag, "unknown tag 'volcano'"])
	var home: LotDef = _good_lot(&"home")
	cases.append([home, "home lot is never listed"])
	for case: Array in cases:
		var errors: PackedStringArray = _errors([case[0] as LotDef])
		assert_true(_has_error(errors, case[1]), "expected '%s' in %s" % [case[1], errors])
	assert_true(_has_error(_errors([_good_lot(), _good_lot()]), "lot id 'test_lot' is duplicated"))
	assert_true(_has_error(_errors([null]), "lot[0] is null"))


func test_a_bad_lot_file_fails_the_whole_load() -> void:
	var lot: LotDef = load(SEASIDE_PATH) as LotDef
	var rent: int = lot.daily_rent
	# The loader returns this cached resource, so the load sees the bad rent.
	lot.daily_rent = 0
	var db: ContentDB = ContentDB.new()
	var errors: PackedStringArray = db.load_all()
	lot.daily_rent = rent
	assert_true(_has_error(errors, "lot 'seaside_cliff': daily_rent must be > 0"))
	assert_eq(db.lots().size(), 0, "nothing is published from a failed load")
	assert_null(db.recipe(&"burger"))
	assert_eq(db.load_all(), PackedStringArray(), "the restored lot loads again")
	assert_eq(db.lots().size(), 3)


func test_listing_is_cheapest_to_open_first() -> void:
	var db: ContentDB = _db()
	var ids: Array[StringName] = []
	for lot: LotDef in PropertyMarket.listing(db.lots()):
		ids.append(lot.id)
	# Fixer-upper $6,000 + $2,500 work, seaside $18,000, rooftop $30,000.
	assert_eq(ids, [&"town_fixer_upper", &"seaside_cliff", &"skyscraper_rooftop"])
	var cheap_fixer: LotDef = _good_lot(&"b_fixer")
	cheap_fixer.price = 0
	cheap_fixer.fixer_price = 700
	cheap_fixer.renovation_bill = 400
	cheap_fixer.renovation_days = 2
	var ready: LotDef = _good_lot(&"a_ready") # $1,000 beats $700 + $400 of work.
	var tie: LotDef = _good_lot(&"c_tie")
	tie.display_name = "Another Lot"
	var order: Array[StringName] = []
	for lot: LotDef in PropertyMarket.listing([cheap_fixer, null, ready, tie]):
		order.append(lot.id)
	assert_eq(order, [&"c_tie", &"a_ready", &"b_fixer"], "cost, then name; nulls dropped")


func test_market_shows_from_tier_three() -> void:
	assert_false(PropertyMarket.shown(1))
	assert_false(PropertyMarket.shown(2))
	assert_true(PropertyMarket.shown(3))
	assert_true(PropertyMarket.shown(6))


func test_lock_lines_name_what_is_missing() -> void:
	var db: ContentDB = _db()
	var rooftop: LotDef = db.lot(&"skyscraper_rooftop") # Tier 4 and 4.3 stars.
	var seaside: LotDef = db.lot(&"seaside_cliff") # Tier 3 and 4.2 stars.
	var fixer: LotDef = db.lot(&"town_fixer_upper") # Tier 3, no stars.
	assert_eq(PropertyText.lock_line(rooftop, 3, 4.0), "Locked: needs Tier 4 and 4.3 stars")
	assert_eq(PropertyText.lock_line(rooftop, 3, 4.6), "Locked: needs Tier 4")
	assert_eq(PropertyText.lock_line(rooftop, 4, 4.0), "Locked: needs 4.3 stars (you have 4.0)")
	assert_eq(PropertyText.lock_line(rooftop, 5, 4.3), "")
	assert_eq(PropertyText.lock_line(seaside, 3, 4.16), "", "stars compare at one decimal, as shown")
	assert_eq(PropertyText.lock_line(seaside, 3, 4.1), "Locked: needs 4.2 stars (you have 4.1)")
	assert_eq(PropertyText.lock_line(fixer, 3, 0.0), "")
	assert_true(PropertyMarket.locked(rooftop, 3, 5.0))
	assert_false(PropertyMarket.locked(fixer, 3, 1.0))


func test_screen_lines_use_names_not_ids() -> void:
	var db: ContentDB = _db()
	var fixer: LotDef = db.lot(&"town_fixer_upper")
	var rooftop: LotDef = db.lot(&"skyscraper_rooftop")
	var seaside: LotDef = db.lot(&"seaside_cliff")
	assert_eq(PropertyText.price_line(fixer), "Fixer-upper $6,000 + renovation $2,500 (3 days of work)")
	assert_eq(PropertyText.price_line(seaside), "$18,000 · move-in ready")
	assert_eq(PropertyText.rent_line(rooftop), "Rent $220 a day")
	assert_eq(PropertyText.expansion_line(rooftop), "Expand later for $15,000, then rent $300 a day")
	assert_eq(PropertyText.size_line(fixer), "%d floor tiles" % fixer.size_cells())
	assert_eq(PropertyText.guest_line(rooftop, CUSTOMER_TYPES), "Guests: mostly foodies")
	assert_eq(PropertyText.guest_line(seaside, CUSTOMER_TYPES), "Guests: families and foodies")
	assert_eq(PropertyText.guest_line(fixer, CUSTOMER_TYPES), "Guests: regulars and families")
	assert_eq(PropertyText.perks_line(seaside), "Perks: Fresh catch")
	assert_eq(PropertyText.perks_line(rooftop), "Perks: Rooftop bar")
	assert_eq(PropertyText.perks_line(fixer), "Perks: Room for an upstairs")
	for tag: StringName in LotDef.KNOWN_TAGS:
		assert_true(PropertyText.TAG_PERKS.has(tag), "every known tag has a perk name")
	assert_eq(PropertyText.plural("Family"), "families")
	assert_eq(PropertyText.plural("Foodie"), "foodies")
	assert_eq(PropertyText.plural("Day"), "days")
