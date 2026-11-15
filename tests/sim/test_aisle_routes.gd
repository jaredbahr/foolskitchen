extends TestCase
## #391: the aisle pinch pass. The faster route trees trace the routes the
## old ones did, a hover's re-survey equals a full survey, and the restroom,
## clearing, delivery and corner-to-corner checks each have a fixture. Only a
## squeeze nobody can walk around warns (Jared: "fewer, sharper").

class Catalogue extends ContentDB:
	var definitions: Dictionary[StringName, ItemDef] = {}

	func item(id: StringName) -> ItemDef:
		return definitions.get(id) as ItemDef

const DEEPER: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")
const ROOMIER: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const ORIGINAL: ShopLayout = preload("res://data/layouts/tier1_original.tres")
const LEASE: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
## The #389 implementation, kept as an oracle for the four trips it traced.
const REFERENCE: GDScript = preload("res://tests/fixtures/aisle_rules_reference.gd")
## A room cut in two by a wall with a one-cell gap at GAP.
const SPLIT: PackedStringArray = ["#########", "#...#...#", "#...#...#", "#.......#", "#...#...#",
	"#...#...#", "#########"]
## The same room with a street door bottom left.
const SPLIT_DOOR: PackedStringArray = ["#########", "#...#...#", "#...#...#", "#.......#", "#...#...#",
	"#...#...#", "#.#######", " E       "]
const GAP: Vector2i = Vector2i(4, 3)
## Family order in AisleRules.Survey.families.
const DOOR_TO_SEATS: int = 0
const RESTROOM_TO_SEATS: int = 4
const PASS_TO_RESTROOM: int = 5
const SINK_TO_SEATS: int = 6
const DELIVERY_TO_STORES: int = 7

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null


func test_new_trees_trace_the_old_routes_for_the_four_original_trips() -> void:
	for layout: ShopLayout in [DEEPER, ROOMIER, ORIGINAL]:
		_start(layout)
		_assert_matches_reference(_sim.world.grid, String(layout.save_layout_id))
	# ...and with a plant on every cell that takes one, which bends the
	# routes every way the room allows.
	_start(DEEPER)
	var grid: SimGrid = _sim.world.grid
	var plant: ItemDef = _content.item(&"potted_plant")
	var tried: int = 0
	for cell: Vector2i in grid.cells():
		if grid.can_place_def(plant, cell, 0) != SimGrid.PlaceResult.OK:
			continue
		var preview: SimGrid = _copy(grid)
		preview.place_def(plant, cell, 0)
		_assert_matches_reference(preview, "plant at %s" % cell)
		tried += 1
	assert_true(tried > 100, "the room takes a plant in many places")


func test_resurvey_equals_a_full_survey_for_every_buy_position() -> void:
	# The proof that reusing a family is safe. A busy shop, so every kind of
	# trip is live: a restroom, a back door and two more tables.
	_start(DEEPER)
	_furnish_every_trip()
	var grid: SimGrid = _sim.world.grid
	var lot: Rect2i = _editor.footprint().lot
	var live: AisleRules.Survey = AisleRules.survey(grid, lot)
	for family: AisleRules.Family in live.families:
		assert_false(family.cells.is_empty(), "every kind of trip is walked in this shop")
	var reused: int = 0
	var retraced: int = 0
	var proposals: Array[Array] = [[&"potted_plant", 0], [&"table_2", 1], [&"fridge", 0], [&"chair", 0],
		[&"toilet", 2]]
	for proposal: Array in proposals:
		var definition: ItemDef = _content.item(proposal[0])
		for cell: Vector2i in grid.cells():
			if grid.can_place_def(definition, cell, proposal[1]) != SimGrid.PlaceResult.OK:
				continue
			var preview: SimGrid = _copy(grid)
			var again: AisleRules.Survey = AisleRules.resurvey(live, preview,
				_cells_of(preview.place_def(definition, cell, proposal[1])), false, lot)
			_assert_same(again, AisleRules.survey(preview, lot), "%s at %s" % [proposal[0], cell])
			reused += again.families.size() - again.traced
			retraced += again.traced
	assert_true(reused > 0 and retraced > 0, "both ways are exercised (%d kept, %d traced)" % [reused, retraced])


func test_the_editor_hover_reports_what_a_full_survey_would() -> void:
	# The same proof through ShopEditor, which works out the changed cells.
	_start(DEEPER)
	_furnish_every_trip()
	var grid: SimGrid = _sim.world.grid
	var lot: Rect2i = _editor.footprint().lot
	var had: Array[Vector2i] = AisleRules.survey(grid, lot).pinches
	var warned: int = 0
	var plant_def: ItemDef = _content.item(&"potted_plant")
	for cell: Vector2i in grid.cells():
		var check: EditCheck = _editor.check_buy(&"potted_plant", cell)
		if not check.ok:
			continue
		var preview: SimGrid = _copy(grid)
		preview.place_def(plant_def, cell, 0)
		var expected: Array[Vector2i] = AisleRules.added_pinches(had, AisleRules.survey(preview, lot))
		assert_eq(check.aisle_pinches, expected, "plant at %s" % cell)
		warned += 1 if not expected.is_empty() else 0
	assert_true(warned > 0)
	# A move takes an item away, which can open a shorter way anywhere: then
	# every kind of trip is traced again.
	var plant: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"potted_plant")[0]
	assert_true(_editor.check_move(plant.id, Vector2i(13, 2), 0).ok)
	assert_eq(_editor.last_aisle_traced, AisleRules.survey(grid, lot).families.size())


func test_resurvey_equals_a_full_survey_on_a_full_tier_two_shop() -> void:
	var layout: ShopLayout = LEASE.layout_for(DEEPER, 2)
	_start(layout)
	var bought: Array[Vector2i] = []
	var area: Rect2i = _editor.footprint().lot
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			if _editor.footprint().can_hold(Vector2i(x, y)):
				bought.append(Vector2i(x, y))
	assert_true(_editor.apply_floor(bought, true), _editor.last_check.why)
	var grid: SimGrid = _sim.world.grid
	var live: AisleRules.Survey = AisleRules.survey(grid, area)
	var plant: ItemDef = _content.item(&"potted_plant")
	var untouched: int = 0
	for cell: Vector2i in grid.cells():
		if grid.can_place_def(plant, cell, 0) != SimGrid.PlaceResult.OK:
			continue
		var preview: SimGrid = _copy(grid)
		var again: AisleRules.Survey = AisleRules.resurvey(live, preview,
			_cells_of(preview.place_def(plant, cell, 0)), false, area)
		_assert_same(again, AisleRules.survey(preview, area), "plant at %s" % cell)
		untouched += 1 if again.traced == 0 else 0
	assert_true(untouched > 200, "most of the new floor is far from every route (%d cells)" % untouched)


func test_a_proposal_far_from_every_route_traces_nothing() -> void:
	_start(DEEPER)
	# The kitchen's east end: nobody's route comes within a cell of it.
	var check: EditCheck = _editor.check_buy(&"potted_plant", Vector2i(13, 3))
	assert_true(check.ok, check.why)
	assert_eq(_editor.last_aisle_traced, 0)
	assert_eq(check.aisle_pinches, [] as Array[Vector2i])
	# In the door lane it has to look again.
	assert_true(_editor.check_buy(&"potted_plant", Vector2i(7, 12)).ok)
	assert_true(_editor.last_aisle_traced > 0)


func test_restroom_to_seat_route_is_checked() -> void:
	var grid: SimGrid = SimGrid.from_ascii(SPLIT)
	grid.place_def(_def(&"wc", ItemDef.Category.RESTROOM, [Vector2i.DOWN]), Vector2i(1, 1), 0)
	grid.place_def(_seat(), Vector2i(7, 2), 0)
	_assert_only_family_squeezes(grid, RESTROOM_TO_SEATS)
	assert_true(AisleRules.survey(grid).families[RESTROOM_TO_SEATS].guest, "guests walk it")


func test_pass_to_restroom_route_is_checked() -> void:
	var grid: SimGrid = SimGrid.from_ascii(SPLIT)
	var hatch: ItemDef = _def(&"hatch", ItemDef.Category.PASS, [Vector2i.UP, Vector2i.DOWN])
	grid.place_def(hatch, Vector2i(1, 2), 0)
	grid.place_def(_def(&"wc", ItemDef.Category.RESTROOM, [Vector2i.DOWN]), Vector2i(7, 1), 0)
	_assert_only_family_squeezes(grid, PASS_TO_RESTROOM)


func test_sink_to_seat_route_is_checked() -> void:
	var grid: SimGrid = SimGrid.from_ascii(SPLIT)
	var basin: ItemDef = _def(&"basin", ItemDef.Category.STATION, [Vector2i.DOWN])
	basin.station_type = &"sink"
	grid.place_def(basin, Vector2i(1, 1), 0)
	grid.place_def(_seat(), Vector2i(7, 2), 0)
	_assert_only_family_squeezes(grid, SINK_TO_SEATS)
	# Another station is not where dishes go: nothing is walked from it.
	var other: SimGrid = SimGrid.from_ascii(SPLIT)
	other.place_def(_def(&"hob", ItemDef.Category.STATION, [Vector2i.DOWN]), Vector2i(1, 1), 0)
	other.place_def(_seat(), Vector2i(7, 2), 0)
	assert_eq(AisleRules.pinches(other), [] as Array[Vector2i])


func test_delivery_to_store_route_is_checked() -> void:
	var grid: SimGrid = SimGrid.from_ascii(SPLIT_DOOR)
	var shelf: ItemDef = _def(&"shelf", ItemDef.Category.STORAGE, [Vector2i.DOWN])
	shelf.storage_units = 10
	grid.place_def(shelf, Vector2i(7, 1), 0)
	_assert_only_family_squeezes(grid, DELIVERY_TO_STORES)
	var survey: AisleRules.Survey = AisleRules.survey(grid)
	assert_eq(survey.receiving, [Vector2i(1, 6)] as Array[Vector2i], "crates go down inside the street door")
	assert_eq(survey.receiving[0], WallRules.delivery_route(grid, Vector2i(7, 2))["drop"])
	# No store, no carry.
	assert_eq(AisleRules.survey(SimGrid.from_ascii(SPLIT_DOOR)).receiving, [] as Array[Vector2i])


func test_deliveries_are_traced_from_the_cell_the_dock_uses() -> void:
	_start(ORIGINAL)
	var grid: SimGrid = _sim.world.grid
	var lot: Rect2i = _editor.footprint().lot
	var store: Vector2i = DeliveryDock.storage_cell(grid)
	assert_ne(store, SimGrid.NO_CELL)
	var street: Vector2i = WallRules.delivery_route(grid, store, lot)["drop"]
	assert_eq(AisleRules.survey(grid, lot).receiving, [street] as Array[Vector2i])
	# A back door takes the deliveries over; a second one is never used, so
	# it is not a start either.
	assert_true(_editor.apply_segments({SimGrid.edge_between(Vector2i(12, 6), Vector2i(13, 6)):
		SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]), _editor.last_check.why)
	assert_eq(AisleRules.survey(grid, lot).receiving, [Vector2i(12, 6)] as Array[Vector2i])
	assert_true(grid.set_segment(SimGrid.edge_between(Vector2i(12, 8), Vector2i(13, 8)), SimGrid.Segment.DOORWAY))
	var survey: AisleRules.Survey = AisleRules.survey(grid, lot)
	assert_eq(survey.receiving, [WallRules.delivery_route(grid, store, lot)["drop"]] as Array[Vector2i])
	assert_eq(survey.receiving.size(), 1)
	assert_eq(survey.families[DELIVERY_TO_STORES].sources, survey.receiving)
	# A hover that buries the receiving cell moves it, as the dock would.
	var plant: ItemDef = _content.item(&"potted_plant")
	var preview: SimGrid = _copy(grid)
	var again: AisleRules.Survey = AisleRules.resurvey(survey, preview,
		_cells_of(preview.place_def(plant, survey.receiving[0], 0)), false, lot)
	assert_ne(again.receiving, survey.receiving)
	assert_eq(again.receiving, [WallRules.delivery_route(preview, store, lot)["drop"]] as Array[Vector2i])


func test_corner_to_corner_is_a_squeeze() -> void:
	var grid: SimGrid = SimGrid.from_ascii(["#######", "#.....#", "#.....#", "#.....#", "#.....#", "#.....#", "#######"])
	var block: ItemDef = _def(&"block", ItemDef.Category.DECOR, [])
	var middle: Vector2i = Vector2i(3, 3)
	assert_false(AisleRules.is_narrow(grid, middle, {}))
	grid.place_def(block, Vector2i(2, 2), 0)
	assert_false(AisleRules.is_narrow(grid, middle, {}), "one corner is not a squeeze")
	var far: PlacedItem = grid.place_def(block, Vector2i(4, 4), 0)
	assert_true(AisleRules.is_narrow(grid, middle, {}), "two things corner to corner leave one cell between them")
	assert_false(REFERENCE.call("is_pinch", grid, middle, {} as Dictionary[Vector2i, bool]), "new in #391")
	assert_true(grid.remove(far.id))
	grid.place_def(block, Vector2i(4, 2), 0)
	assert_false(AisleRules.is_narrow(grid, middle, {}), "two corners on the same side leave the other side open")
	# A seat closes a corner as an item does.
	assert_true(AisleRules.is_narrow(grid, middle, {Vector2i(2, 4): true} as Dictionary[Vector2i, bool]))


func test_a_corner_to_corner_squeeze_with_no_way_around_is_a_pinch() -> void:
	# Two walls step past each other: MIDDLE is open on all four sides, and
	# the only cell joining the two halves of the room.
	var rows: PackedStringArray = ["#########", "#....#..#", "#....#..#", "#.......#", "#..#....#", "#..#....#",
		"#########"]
	var middle: Vector2i = Vector2i(4, 3)
	var grid: SimGrid = SimGrid.from_ascii(rows)
	var basin: ItemDef = _def(&"basin", ItemDef.Category.STATION, [Vector2i.DOWN])
	basin.station_type = &"sink"
	grid.place_def(basin, Vector2i(1, 1), 0)
	grid.place_def(_seat(), Vector2i(7, 4), 0)
	assert_true(AisleRules.is_narrow(grid, middle, {}))
	assert_eq(AisleRules.pinches(grid), [middle] as Array[Vector2i])
	assert_eq(REFERENCE.call("pinches", grid), [] as Array[Vector2i], "new in #391")
	# Open one of the walls and people can walk around: no pinch.
	assert_true(grid.set_terrain(Vector2i(5, 1), SimGrid.Terrain.FLOOR))
	assert_true(AisleRules.is_narrow(grid, middle, {}), "still narrow")
	assert_eq(AisleRules.pinches(grid), [] as Array[Vector2i])


func test_a_plant_people_can_walk_around_does_not_warn() -> void:
	_start(DEEPER)
	# Open floor in the door lane, the gap between two tables, the lane below
	# the tables, the pass approach: each leaves a way round the plant.
	for cell: Vector2i in [Vector2i(7, 13), Vector2i(5, 8), Vector2i(6, 11), Vector2i(4, 4), Vector2i(9, 5)]:
		var check: EditCheck = _editor.check_buy(&"potted_plant", cell)
		assert_true(check.ok, check.why)
		assert_eq(check.aisle_pinches, [] as Array[Vector2i], "plant at %s" % cell)
		assert_false(check.seat_warnings.has(0), "plant at %s" % cell)
	# So does a fridge corner to corner with the stove.
	assert_eq(_editor.check_buy(&"fridge", Vector2i(10, 3)).aisle_pinches, [] as Array[Vector2i])
	# In the whole room only eight spots still warn: each takes the last way
	# through (half the street door, or the kitchen lane by the pass).
	var warned: Array[Vector2i] = []
	for cell: Vector2i in _sim.world.grid.cells():
		var check: EditCheck = _editor.check_buy(&"potted_plant", cell)
		if check.ok and not check.aisle_pinches.is_empty():
			warned.append(cell)
	assert_eq(warned, [Vector2i(4, 2), Vector2i(7, 2), Vector2i(9, 2), Vector2i(5, 3), Vector2i(7, 3),
		Vector2i(8, 3), Vector2i(7, 15), Vector2i(8, 15)] as Array[Vector2i])
	var door: EditCheck = _editor.check_buy(&"potted_plant", Vector2i(7, 15))
	assert_eq(door.aisle_pinches, [Vector2i(8, 15)] as Array[Vector2i], "half the street door")
	assert_eq(door.seat_warnings.get(0, ""), AisleRules.WARNING)


func test_closing_the_way_around_far_off_makes_the_old_gap_a_pinch() -> void:
	# Two one-cell gaps in a wall. The trip uses the near one; while the far
	# one is open people can walk around, so nothing warns.
	var grid: SimGrid = SimGrid.from_ascii(["#########", "#...#...#", "#.......#", "#...#...#", "#...#...#",
		"#...#...#", "#.......#", "#...#...#", "#########"])
	var basin: ItemDef = _def(&"basin", ItemDef.Category.STATION, [Vector2i.DOWN])
	basin.station_type = &"sink"
	grid.place_def(basin, Vector2i(1, 1), 0)
	grid.place_def(_seat(), Vector2i(7, 2), 0)
	var near: Vector2i = Vector2i(4, 2)
	var live: AisleRules.Survey = AisleRules.survey(grid)
	assert_true(live.families[SINK_TO_SEATS].narrow.has(near))
	assert_eq(live.pinches, [] as Array[Vector2i])
	# Plugging the far gap touches no route, so nothing is traced again, yet
	# the near gap is now the only way through.
	var preview: SimGrid = _copy(grid)
	var plug: PlacedItem = preview.place_def(_def(&"block", ItemDef.Category.DECOR, []), Vector2i(4, 6), 0)
	var again: AisleRules.Survey = AisleRules.resurvey(live, preview, _cells_of(plug), false)
	assert_eq(again.traced, 0)
	assert_eq(again.pinches, [near] as Array[Vector2i])
	_assert_same(again, AisleRules.survey(preview), "far gap plugged")
	assert_eq(AisleRules.rerouted(preview, again.pinches, _cells_of(plug)), [near] as Array[Vector2i],
		"blamed on the gap, not on the plug")


func test_a_reroute_through_an_old_gap_is_blamed_on_the_gap() -> void:
	# A wall across the room with a wide opening by the door and, further
	# along, an opening two counters narrow to one cell. Everyone uses the
	# wide one until something shuts it.
	var catalogue: Catalogue = Catalogue.new()
	_content = catalogue
	for id: StringName in [&"counter", &"long_counter"]:
		catalogue.definitions[id] = _def(id, ItemDef.Category.TABLE, [])
	catalogue.definitions[&"long_counter"].footprint = Vector2i(2, 1)
	catalogue.definitions[&"stool"] = _seat()
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	grid.set_terrain(Vector2i(0, 11), SimGrid.Terrain.ENTRY)
	for x: int in range(12):
		if x not in [1, 2, 8, 9, 10]:
			assert_true(grid.set_terrain(Vector2i(x, 4), SimGrid.Terrain.WALL))
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(grid)
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record))
	var left: PlacedItem = grid.place_def(catalogue.item(&"counter"), Vector2i(8, 4), 0)
	var right: PlacedItem = grid.place_def(catalogue.item(&"counter"), Vector2i(10, 4), 0)
	grid.place_def(catalogue.item(&"counter"), Vector2i(4, 1), 0)
	grid.place_def(catalogue.item(&"stool"), Vector2i(4, 2), 0)
	var gap: Vector2i = Vector2i(9, 4)
	assert_true(AisleRules.is_narrow(grid, gap, {}), "the gap is one cell wide already")
	assert_eq(AisleRules.pinches(grid), [] as Array[Vector2i], "but nobody has to walk through it")
	var check: EditCheck = _editor.check_buy(&"long_counter", Vector2i(1, 4))
	assert_true(check.ok, check.why)
	assert_eq(check.aisle_pinches, [gap] as Array[Vector2i])
	assert_true(check.aisle_rerouted, "the counter closed nothing beside the gap")
	var beside: int = mini(left.id, right.id)
	assert_eq(check.aisle_id, beside, "the warning is on a counter beside the gap")
	assert_eq(check.seat_warnings.get(beside, ""), AisleRules.REROUTE_WARNING)
	assert_false(check.seat_warnings.has(0), "not on the counter being placed")
	assert_true(_editor.buy(&"long_counter", Vector2i(1, 4)), _editor.last_check.why)
	var after: EditCheck = _editor.check_current()
	assert_eq(after.aisle_pinches, [gap] as Array[Vector2i], "kept after the commit")
	assert_true(after.aisle_rerouted)
	assert_eq(after.seat_warnings.get(beside, ""), AisleRules.REROUTE_WARNING)
	assert_false(after.seat_warnings.has(_editor.last_item_id))
	# An item that itself narrows the way keeps the plain warning, on itself.
	assert_true(grid.remove(_editor.last_item_id))
	assert_true(grid.remove(right.id))
	var squeeze: EditCheck = _editor.check_buy(&"long_counter", Vector2i(1, 4))
	assert_eq(squeeze.aisle_pinches, [] as Array[Vector2i], "two cells wide again: no squeeze")
	assert_true(grid.remove(left.id))
	assert_true(_editor.buy(&"long_counter", Vector2i(1, 4)), _editor.last_check.why)
	var own: EditCheck = _editor.check_buy(&"counter", Vector2i(8, 4))
	assert_eq(own.aisle_pinches, [] as Array[Vector2i], "two of the three cells stay open")
	own = _editor.check_buy(&"long_counter", Vector2i(8, 4))
	assert_eq(own.aisle_pinches, [Vector2i(10, 4)] as Array[Vector2i])
	assert_false(own.aisle_rerouted)
	assert_eq(own.seat_warnings.get(0, ""), AisleRules.WARNING)


## Only `index`'s kind of trip is walked in `grid`, and it squeezes through GAP.
func _assert_only_family_squeezes(grid: SimGrid, index: int) -> void:
	var survey: AisleRules.Survey = AisleRules.survey(grid)
	for other: int in survey.families.size():
		var family: AisleRules.Family = survey.families[other]
		if other == index:
			assert_true(family.cells.has(GAP), "trip %d goes through the gap" % index)
			assert_eq(family.pinches, [GAP] as Array[Vector2i])
		else:
			assert_true(family.cells.is_empty(), "trip %d is not walked here" % other)
	assert_eq(survey.pinches, [GAP] as Array[Vector2i])
	assert_eq(REFERENCE.call("pinches", grid), [] as Array[Vector2i], "the #389 pass did not look at this trip")


## The four #389 trips walk the cells the old trees walked and are narrow
## where those squeezed; anything more is a corner-to-corner squeeze. (Which
## narrow cells warn is the #391 rule: only those with no way around.)
func _assert_matches_reference(grid: SimGrid, what: String) -> void:
	var survey: AisleRules.Survey = AisleRules.survey(grid)
	var cells: Dictionary[Vector2i, bool] = {}
	var narrow: Array[Vector2i] = []
	for index: int in range(DOOR_TO_SEATS, DOOR_TO_SEATS + 4):
		cells.merge(survey.families[index].cells)
		for cell: Vector2i in survey.families[index].narrow:
			if not narrow.has(cell):
				narrow.append(cell)
		for cell: Vector2i in survey.families[index].pinches:
			assert_true(survey.families[index].narrow.has(cell), "a pinch is a narrow cell, %s" % what)
	var expected: Dictionary[Vector2i, bool] = REFERENCE.call("route_cells", grid)
	assert_eq(_sorted(cells.keys()), _sorted(expected.keys()), "routes, %s" % what)
	var old: Array[Vector2i] = REFERENCE.call("pinches", grid)
	for cell: Vector2i in old:
		assert_true(narrow.has(cell), "old pinch %s is narrow, %s" % [cell, what])
	var seats: Dictionary[Vector2i, bool] = survey.net.seats
	for cell: Vector2i in narrow:
		assert_true(old.has(cell) or not REFERENCE.call("is_pinch", grid, cell, seats),
			"new narrow cell %s is a corner squeeze, %s" % [cell, what])


func _assert_same(actual: AisleRules.Survey, expected: AisleRules.Survey, what: String) -> void:
	assert_eq(actual.families.size(), expected.families.size(), what)
	assert_eq(actual.receiving, expected.receiving, "receiving cell, %s" % what)
	assert_eq(actual.pinches, expected.pinches, "pinches, %s" % what)
	assert_eq(_sorted(actual.route_cells.keys()), _sorted(expected.route_cells.keys()), "route cells, %s" % what)
	for index: int in mini(actual.families.size(), expected.families.size()):
		var mine: AisleRules.Family = actual.families[index]
		var full: AisleRules.Family = expected.families[index]
		assert_eq(mine.sources, full.sources, "trip %d starts, %s" % [index, what])
		assert_eq(mine.targets, full.targets, "trip %d ends, %s" % [index, what])
		assert_eq(_sorted(mine.cells.keys()), _sorted(full.cells.keys()), "trip %d cells, %s" % [index, what])
		assert_eq(_sorted(mine.narrow), _sorted(full.narrow), "trip %d narrow cells, %s" % [index, what])
		assert_eq(_sorted(mine.pinches), _sorted(full.pinches), "trip %d pinches, %s" % [index, what])


## A restroom, a back door and two more tables, so all eight trips are walked.
func _furnish_every_trip() -> void:
	assert_true(_editor.buy(&"toilet", Vector2i(13, 13), 2), _editor.last_check.why)
	for origin: Vector2i in [Vector2i(2, 13), Vector2i(11, 13)]:
		assert_true(_editor.buy(&"table_2", origin, 0), _editor.last_check.why)
	assert_true(_editor.apply_segments({SimGrid.edge_between(Vector2i(14, 2), Vector2i(15, 2)):
		SimGrid.Segment.DOORWAY} as Dictionary[Vector3i, int]), _editor.last_check.why)


func _start(layout: ShopLayout) -> void:
	var errors: Array[String] = []
	_sim = RestaurantSim.create(layout, _content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), layout)
	_editor.set_owner_level(5)


## The standing shop again (terrain, wall segments, items), as the editor
## builds a proposal.
func _copy(grid: SimGrid) -> SimGrid:
	var copy: SimGrid = grid.terrain_copy()
	var segments: Dictionary[Vector3i, int] = {}
	for edge: Vector3i in grid.segment_edges():
		segments[edge] = grid.segment(edge)
	copy.set_segments(segments)
	for placed: PlacedItem in grid.items():
		copy.place_def(placed.def as ItemDef, placed.origin, placed.quarter_turns)
	return copy


func _cells_of(placed: PlacedItem) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for group: Array[Vector2i] in [placed.cells, placed.seat_cells, placed.work_cells]:
		for cell: Vector2i in group:
			if not cells.has(cell):
				cells.append(cell)
	return cells


func _def(id: StringName, category: ItemDef.Category, work: Array[Vector2i]) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = id
	definition.display_name = "Test furniture"
	definition.category = category
	definition.footprint = Vector2i.ONE
	definition.work_cells = work.duplicate()
	definition.solid = true
	definition.price = 10
	definition.unlock_level = 1
	return definition


func _seat() -> ItemDef:
	var definition: ItemDef = _def(&"stool", ItemDef.Category.CHAIR, [])
	definition.seat_cells = [Vector2i.ZERO]
	definition.solid = false
	return definition


func _sorted(cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(cells)
	out.sort()
	return out


func _can_spend(_amount: int) -> bool:
	return true


func _record(_amount: int, _category: StringName, _note: String = "") -> void:
	pass
