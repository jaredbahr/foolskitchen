extends TestCase
## Every location has its own starter building (#596, D39): the Seaside Cliff's
## kitchen cottage, the Skyline Rooftop's glass pavilion, Old Mill Street's
## L-shaped mill hall and granary, and the Beachfront Boardwalk's wide kiosk.
## Each opens and serves on day one, and a site saved on a lot's earlier
## rectangle keeps loading on that rectangle.

const STARTING_STOCK: int = 100
const SERVICE_TICKS: int = 6000
const GUESTS: int = 6
const LOTS: Array[StringName] = [&"seaside_cliff", &"skyscraper_rooftop", &"town_fixer_upper",
	&"beachfront_boardwalk"]

var _content: ContentDB
var _paid: int = 0
var _left: Dictionary[StringName, int] = {}


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_paid = 0
	_left.clear()


func after_each() -> void:
	_content = null


func _layout(lot_id: StringName) -> ShopLayout:
	return _content.lot(lot_id).base_layout


func _sim(layout: ShopLayout, seed: int = 596) -> RestaurantSim:
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, STARTING_STOCK, 1)
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, _content, seed, errors, stock)
	assert_eq(errors, [] as Array[String], "%s builds" % layout.id)
	return sim


func _editor(sim: RestaurantSim, layout: ShopLayout) -> ShopEditor:
	var editor: ShopEditor = ShopEditor.new(sim, _content, ShopEditBooks.new(_any_spend, _no_cash), layout)
	editor.set_owner_level(5)
	return editor


func _any_spend(_amount: int) -> bool:
	return true


func _no_cash(_amount: int, _category: StringName, _note: String) -> void:
	pass


func _seats(grid: SimGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for placed: PlacedItem in grid.items():
		out.append_array(placed.seat_cells)
	return out


func _items(grid: SimGrid, id: StringName) -> Array[PlacedItem]:
	var out: Array[PlacedItem] = []
	for placed: PlacedItem in grid.items():
		if (placed.def as ItemDef).id == id:
			out.append(placed)
	return out


func _on_paid(_guest: CustomerAgent, _order: Order, _amount: int) -> void:
	_paid += 1


func _on_left(_guest: CustomerAgent, reason: StringName) -> void:
	_left[reason] = int(_left.get(reason, 0)) + 1


func test_every_lot_has_its_own_building_shape() -> void:
	var shapes: Dictionary[String, StringName] = {}
	for lot_id: StringName in LOTS:
		var layout: ShopLayout = _layout(lot_id)
		var key: String = "|".join(layout.rows)
		assert_false(shapes.has(key), "%s shares its shell with %s" % [lot_id, shapes.get(key, &"")])
		shapes[key] = lot_id
		assert_ne(String(layout.save_layout_id), "lot_" + String(lot_id), "%s: a new shell has a new save id" % lot_id)


func test_every_lot_opens_with_a_working_kitchen_and_no_warnings() -> void:
	for lot_id: StringName in LOTS:
		var layout: ShopLayout = _layout(lot_id)
		var sim: RestaurantSim = _sim(layout)
		var grid: SimGrid = sim.world.grid
		for station: StringName in [&"fridge", &"prep_counter", &"stove", &"sink", &"pass_counter"]:
			assert_false(_items(grid, station).is_empty(), "%s has its %s" % [lot_id, station])
		for role: StringName in layout.staff_spawns:
			assert_true(grid.is_walkable(layout.staff_spawns[role]), "%s: %s starts on clear floor" % [lot_id, role])
		assert_eq(RoomRules.violations(grid, {} as Dictionary[int, int]), {} as Dictionary[String, String],
			"%s keeps the room rules" % lot_id)
		assert_eq(WallRules.layout_problem(grid), "", "%s: walls keep every spot reachable" % lot_id)
		var check: EditCheck = _editor(sim, layout).check_current()
		assert_true(check.seat_warnings.is_empty(), "%s: no seat warnings: %s" % [lot_id, check.seat_warnings])
		assert_true(check.unreachable.is_empty(), "%s: nothing unreachable: %s" % [lot_id, check.unreachable])
		assert_true(_seats(grid).size() >= 6, "%s seats a starter crowd" % lot_id)


func test_every_lot_serves_guests_on_a_sunny_first_day() -> void:
	for lot_id: StringName in LOTS:
		_paid = 0
		_left.clear()
		var sim: RestaurantSim = _sim(_layout(lot_id))
		sim.world.weather.kind = WeatherState.Kind.SUNNY
		sim.spawner.min_gap = 100000
		sim.spawner.max_gap = 100000
		sim.start_day()
		sim.customer_paid.connect(_on_paid)
		sim.customer_left.connect(_on_left)
		var entry: Vector2i = sim.world.grid.entries()[0]
		for index: int in GUESTS:
			var random: RandomNumberGenerator = RandomNumberGenerator.new()
			random.seed = 5960 + index
			var guest: CustomerAgent = sim.add_customer(entry, random)
			guest.food_patience = 5000
			guest.queue_patience = 5000
		assert_true(sim.world.clock.start_service())
		for tick: int in SERVICE_TICKS:
			sim.advance()
			if sim.customers().is_empty():
				break
		assert_eq(_paid, GUESTS, "%s serves every guest (left: %s)" % [lot_id, _left])
		sim.customer_paid.disconnect(_on_paid)
		sim.customer_left.disconnect(_on_left)


func test_the_cliff_cottage_is_all_kitchen_with_every_seat_on_the_terrace() -> void:
	var layout: ShopLayout = _layout(&"seaside_cliff")
	var grid: SimGrid = _sim(layout).world.grid
	var seats: Array[Vector2i] = _seats(grid)
	assert_false(seats.is_empty())
	for seat: Vector2i in seats:
		assert_true(grid.is_outdoor_floor(seat), "seat %s is out on the terrace" % seat)
	var footprint: ShopFootprint = ShopFootprint.from_layout(layout)
	for cell: Vector2i in grid.cells():
		if footprint.building.has_point(cell) and grid.terrain(cell) == SimGrid.Terrain.FLOOR \
				and cell.y < footprint.building.end.y - 1:
			assert_eq(grid.room(cell), SimGrid.Room.KITCHEN, "the cottage room %s is kitchen" % cell)
	# The serving hatch: the pass stands just inside an opening in the front
	# wall, its guest side in that opening, off the terrace.
	var pass_item: PlacedItem = _items(grid, &"pass_counter")[0]
	var guest_side: Vector2i = pass_item.work_cells[1]
	assert_eq(guest_side.y, footprint.building.end.y - 1, "the pass serves through the front wall")
	assert_true(grid.is_outdoor_floor(guest_side + Vector2i.DOWN), "the hatch opens onto the terrace")
	assert_true(grid.is_guest_walkable(guest_side))


func test_the_rooftop_pavilion_has_a_walled_core_a_bar_and_glass() -> void:
	var layout: ShopLayout = _layout(&"skyscraper_rooftop")
	var grid: SimGrid = _sim(layout).world.grid
	var footprint: ShopFootprint = ShopFootprint.from_layout(layout)
	assert_true(footprint.building.size.x > footprint.building.size.y * 2, "a wide, shallow box")
	assert_eq(footprint.interior_wall_cells().size(), 8, "the lift core is walled off, not floor")
	assert_eq(grid.terrain(Vector2i(footprint.building.get_center().x, 1)), SimGrid.Terrain.WALL,
		"the core stands in the middle of the back")
	assert_true(_items(grid, &"bar_counter").size() >= 2, "a long bar fronts the kitchen")
	assert_eq(_items(grid, &"bar_stool").size(), 8, "a stool at every bar piece")
	var windows: int = 0
	for edge: Vector3i in grid.segment_edges():
		if grid.segment(edge) == SimGrid.Segment.WINDOW:
			windows += 1
	assert_true(windows >= 12, "the dining room is glazed")


func test_the_mill_is_an_l_with_a_granary_through_an_archway() -> void:
	var layout: ShopLayout = _layout(&"town_fixer_upper")
	var sim: RestaurantSim = _sim(layout)
	var grid: SimGrid = sim.world.grid
	var footprint: ShopFootprint = ShopFootprint.from_layout(layout)
	var notch: Vector2i = footprint.building.end - Vector2i(2, 3)
	assert_eq(grid.terrain(notch), SimGrid.Terrain.OUTSIDE, "the front right corner is open ground")
	assert_false(footprint.is_starting_shell(notch))
	assert_true(footprint.can_hold(notch), "the notch is lot land the mill can be built out over")
	var granary_seat: Vector2i = Vector2i(-1, -1)
	for seat: Vector2i in _seats(grid):
		if seat.x > 15:
			granary_seat = seat
	assert_ne(granary_seat, Vector2i(-1, -1), "the granary has tables")
	assert_true(RoomRules.guest_reachable(grid).has(granary_seat), "guests walk through the archway")
	var walls: int = 0
	for edge: Vector3i in grid.segment_edges():
		if edge.z == SimGrid.EDGE_WEST and edge.x == 15 and grid.segment(edge) == SimGrid.Segment.WALL:
			walls += 1
	assert_eq(walls, 6, "a thin wall the player can knock through, with a two-cell archway")


func test_building_out_over_the_mill_notch_wraps_it_in_wall() -> void:
	var layout: ShopLayout = _layout(&"town_fixer_upper")
	var footprint: ShopFootprint = ShopFootprint.from_layout(layout)
	var bought: Dictionary[Vector2i, bool] = {}
	# Fill the notch but its front row (the street line stays).
	for y: int in range(10, 15):
		for x: int in range(16, 25):
			bought[Vector2i(x, y)] = true
	assert_eq(footprint.problem(bought), "")
	var terrain: Dictionary[Vector2i, int] = footprint.terrain_for(bought)
	assert_eq(terrain[Vector2i(15, 12)], SimGrid.Terrain.FLOOR, "the hall's side wall opens")
	assert_eq(terrain[Vector2i(20, 9)], SimGrid.Terrain.FLOOR, "the granary's front wall opens")
	assert_eq(terrain[Vector2i(20, 15)], SimGrid.Terrain.WALL, "a new front wall on the street line")
	assert_eq(terrain[Vector2i(25, 12)], SimGrid.Terrain.WALL, "a new side wall")
	# Floor bought beside the notch, east of the granary, still gets its wall.
	var beside: Dictionary[Vector2i, bool] = {Vector2i(26, 8): true, Vector2i(26, 9): true, Vector2i(26, 10): true}
	assert_eq(footprint.problem(beside), "")
	var wrapped: Dictionary[Vector2i, int] = footprint.terrain_for(beside)
	assert_eq(wrapped[Vector2i(25, 10)], SimGrid.Terrain.WALL, "no floor ever stands open to the notch")
	assert_eq(wrapped[Vector2i(24, 12)], SimGrid.Terrain.OUTSIDE, "the rest of the notch stays open ground")


func test_the_boardwalk_kiosk_has_a_takeaway_counter_and_a_back_archway_to_the_patio() -> void:
	var layout: ShopLayout = _layout(&"beachfront_boardwalk")
	var sim: RestaurantSim = _sim(layout)
	var grid: SimGrid = sim.world.grid
	var footprint: ShopFootprint = ShopFootprint.from_layout(layout)
	assert_true(footprint.building.size.x >= footprint.building.size.y * 3, "a wide, shallow shopfront")
	var counter: PlacedItem = _items(grid, &"order_counter")[0]
	assert_false(OrderCounter.usable_counters(sim, grid.entries()[0]).is_empty(), "the takeaway counter works")
	for cell: Vector2i in counter.seat_cells:
		assert_true(RoomRules.guest_reachable(grid).has(cell), "guests reach the counter from the door")
	var front: int = footprint.building.end.y - 1
	assert_eq(grid.segment(Vector3i(counter.origin.x, front, SimGrid.EDGE_NORTH)), SimGrid.Segment.WINDOW,
		"the counter looks out on the promenade")
	var patio_seat: Vector2i = Vector2i(-1, -1)
	for seat: Vector2i in _seats(grid):
		if grid.is_outdoor_floor(seat):
			patio_seat = seat
	assert_ne(patio_seat, Vector2i(-1, -1), "tables out on the beach patio")
	assert_true(RoomRules.guest_reachable(grid).has(patio_seat), "guests walk out the back archway")


func test_a_site_saved_on_a_lots_old_rectangle_keeps_it() -> void:
	for lot_id: StringName in LOTS:
		var lot: LotDef = _content.lot(lot_id)
		assert_eq(lot.legacy_layouts.size(), 1, "%s keeps its first shell" % lot_id)
		var legacy: ShopLayout = lot.legacy_layouts[0]
		assert_eq(String(legacy.save_layout_id), "lot_" + String(lot_id), "the shell older saves name")
		assert_true(_content.lot_for_layout(legacy.save_layout_id) == lot)
		assert_true(lot.layout_for_id(legacy.save_layout_id) == legacy)
		assert_true(lot.layout_for_id(lot.base_layout.save_layout_id) == lot.base_layout)
		assert_null(lot.layout_for_id(&"nowhere"))
		assert_true(lot.owns_layout(legacy) and lot.owns_layout(lot.base_layout))
		# An older save: the legacy shell, saved and loaded back on itself.
		var errors: Array[String] = []
		var shell: RestaurantSim = RestaurantSim.new()
		shell.world = ShopBuilder.build(legacy, _content, errors)
		var saved: Dictionary = ShopEditor.new(shell, _content, ShopEditBooks.new(), legacy).to_dict()
		assert_eq(saved["layout_id"], String(legacy.save_layout_id))
		var loaded: ShopLayout = ShopEditor.from_dict(saved, lot.layout_for_id(StringName(saved["layout_id"])),
			_content, errors)
		assert_eq(errors, [] as Array[String], "%s: an old site still loads" % lot_id)
		assert_not_null(loaded)
		assert_eq(loaded.rows, legacy.rows, "%s: on its own old rectangle" % lot_id)
		errors.clear()
		assert_null(ShopEditor.from_dict(saved, lot.base_layout, _content, errors),
			"an old site never loads onto the new shell")
		# A new site saves the new shell's id.
		var fresh: RestaurantSim = RestaurantSim.new()
		fresh.world = ShopBuilder.build(lot.base_layout, _content, errors)
		var made: Dictionary = ShopEditor.new(fresh, _content, ShopEditBooks.new(), lot.base_layout).to_dict()
		assert_eq(made["layout_id"], String(lot.base_layout.save_layout_id))


func test_legacy_layouts_need_their_own_save_ids() -> void:
	var lot: LotDef = _content.lot(&"seaside_cliff").duplicate() as LotDef
	lot.id = &"legacy_test"
	var clash: ShopLayout = lot.base_layout.duplicate() as ShopLayout
	lot.legacy_layouts = [clash] as Array[ShopLayout]
	lot.legacy_expansion = {} as Dictionary[StringName, Vector3i]
	var types: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
	var type_ids: Array[StringName] = []
	for kind: CustomerType in types.types:
		type_ids.append(kind.id)
	var errors: PackedStringArray = ContentDB.validate_lots([lot] as Array[LotDef], _content.items(), type_ids)
	assert_true(errors.size() == 1 and errors[0].contains("legacy layout"), str(errors))
	var stray: LotDef = _content.lot(&"seaside_cliff").duplicate() as LotDef
	stray.id = &"legacy_terms_test"
	stray.legacy_expansion = {&"nowhere": Vector3i(0, 4, 2)} as Dictionary[StringName, Vector3i]
	errors = ContentDB.validate_lots([stray] as Array[LotDef], _content.items(), type_ids)
	assert_true(errors.size() == 1 and errors[0].contains("legacy_expansion"), str(errors))


func test_floor_bought_in_the_mill_notch_stays_dining_beside_a_kitchen() -> void:
	var layout: ShopLayout = _layout(&"town_fixer_upper")
	var footprint: ShopFootprint = ShopFootprint.from_layout(layout)
	# The player bought a notch cell and painted it Kitchen; the next cell
	# bought beside it is lot floor, not an opened shell wall: it stays Dining.
	var before: SimGrid = SimGrid.from_ascii(layout.rows)
	assert_true(footprint.apply(before, {Vector2i(16, 10): true} as Dictionary[Vector2i, bool]))
	assert_true(before.set_rooms({Vector2i(16, 10): SimGrid.Room.KITCHEN} as Dictionary[Vector2i, int]))
	var after: SimGrid = SimGrid.from_ascii(layout.rows)
	assert_true(footprint.apply(after, {Vector2i(16, 10): true, Vector2i(17, 10): true} as Dictionary[Vector2i, bool]))
	assert_false(RoomRules.opened_kitchen(before, after, footprint).has(Vector2i(17, 10)))
	# The back-wall rule still holds for the shell itself: the hall's side wall
	# opened beside its own Kitchen cell becomes Kitchen.
	var shell_before: SimGrid = SimGrid.from_ascii(layout.rows)
	assert_true(shell_before.set_rooms({Vector2i(14, 10): SimGrid.Room.KITCHEN} as Dictionary[Vector2i, int]))
	var shell_after: SimGrid = SimGrid.from_ascii(layout.rows)
	assert_true(footprint.apply(shell_after, {Vector2i(16, 10): true} as Dictionary[Vector2i, bool]))
	var opened: Dictionary[Vector2i, int] = RoomRules.opened_kitchen(shell_before, shell_after, footprint)
	assert_eq(opened.get(Vector2i(15, 10), -1), SimGrid.Room.KITCHEN)
	assert_false(opened.has(Vector2i(16, 10)))


func test_a_legacy_cliff_site_keeps_its_old_lease_and_east_floor() -> void:
	var lot: LotDef = _content.lot(&"seaside_cliff")
	var legacy: ShopLayout = lot.layout_for_id(&"lot_seaside_cliff")
	var old_lease: LeaseUpgrade = lot.lease_upgrade_for(legacy)
	assert_eq([old_lease.extra_west, old_lease.extra_east, old_lease.extra_north], [0, 4, 2],
		"the old rectangle keeps the old expansion")
	var new_lease: LeaseUpgrade = lot.lease_upgrade_for(lot.base_layout)
	assert_eq([new_lease.extra_west, new_lease.extra_east, new_lease.extra_north], [4, 0, 2])
	assert_eq(old_lease.deposit, new_lease.deposit, "price and rent are shared")
	# An old cliff site on its tier-2 lease with floor bought east of the shell.
	var template: ShopLayout = old_lease.layout_for(legacy, 2)
	var shell: Rect2i = ShopFootprint.from_layout(legacy).building
	var footprint: ShopFootprint = ShopFootprint.from_layout(template)
	assert_true(footprint.lot.end.x > shell.end.x + 2, "the expanded lot is reserved on the east")
	var east: Array[Vector2i] = [Vector2i(shell.end.x, 5), Vector2i(shell.end.x + 1, 5)]
	assert_eq(footprint.problem(ShopFootprint.to_set(east)), "")
	var built: ShopLayout = template.duplicate() as ShopLayout
	built.floor_cells = east
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = ShopBuilder.build(built, _content, errors)
	assert_eq(errors, [] as Array[String])
	var saved: Dictionary = ShopEditor.new(sim, _content, ShopEditBooks.new(), built).to_dict()
	assert_eq(saved["layout_id"], "lot_seaside_cliff")
	assert_eq((saved["floor"] as Array).size(), 2)
	var loaded: ShopLayout = ShopEditor.from_dict(saved, template, _content, errors)
	assert_eq(errors, [] as Array[String], "it loads on its own lot")
	assert_not_null(loaded)
	assert_eq(loaded.floor_cells, east)
	assert_eq(ShopFootprint.from_layout(loaded).lot, footprint.lot, "with its lot still on the east")
	errors.clear()
	assert_null(ShopEditor.from_dict(saved, lot.lease_upgrade().layout_for(legacy, 2), _content, errors),
		"the new lot's terms would not fit it")


func test_the_kiosk_serves_a_drinks_guest_at_its_counter_on_day_one() -> void:
	var sim: RestaurantSim = _sim(_layout(&"beachfront_boardwalk"))
	var grid: SimGrid = sim.world.grid
	assert_eq(_items(grid, &"drinks_fridge").size(), 1, "the kiosk pours cold drinks")
	sim.world.weather.kind = WeatherState.Kind.SUNNY
	sim.menu.append(_content.recipe(&"soft_drink"))
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.start_day()
	sim.customer_paid.connect(_on_paid)
	sim.customer_left.connect(_on_left)
	var guests: Array[CustomerAgent] = []
	for index: int in 3:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 5970 + index
		var guest: CustomerAgent = sim.add_visitor(grid.entries()[0], random, null, RecipeDef.DRINKS)
		guest.food_patience = 5000
		guest.queue_patience = 5000
		guests.append(guest)
	assert_true(sim.world.clock.start_service())
	var at_counter: Dictionary[int, bool] = {}
	for tick: int in SERVICE_TICKS:
		sim.advance()
		for guest: CustomerAgent in guests:
			if guest.counter_visit:
				at_counter[guest.id] = true
		if sim.customers().is_empty():
			break
	assert_eq(_paid, guests.size(), "every drinks guest is served (left: %s)" % _left)
	assert_eq(at_counter.size(), guests.size(), "each one orders at the kiosk counter")
