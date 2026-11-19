extends TestCase
## Rain cover (#625): a pergola or awning keeps the patio seats under it open in
## rain, goes only over patio, and survives a save round trip.

const TABLE: ItemDef = preload("res://data/items/table_2.tres")
const OUTDOOR_TABLE: ItemDef = preload("res://data/items/patio_table_2.tres")
const PERGOLA: ItemDef = preload("res://data/items/pergola.tres")
const AWNING: ItemDef = preload("res://data/items/awning.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _ledger: Ledger


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 17, errors)
	assert_eq(errors, [] as Array[String])
	_ledger = Ledger.new()
	_ledger.cash = 2000
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)


func after_each() -> void:
	_editor = null
	_sim = null
	_content = null
	_ledger = null


func test_the_cover_items_are_passive_patio_only_floor_decor() -> void:
	for definition: ItemDef in [PERGOLA, AWNING]:
		assert_true(definition.rain_cover, definition.id)
		assert_true(definition.covers_from_rain())
		assert_true(definition.outdoor_only)
		assert_true(definition.placement_layer_valid())
		assert_false(definition.solid)
		assert_eq(definition.footprint, Vector2i(4, 4), "2 x 2 m")
		assert_true(definition.view_scene != null)
	assert_false(TABLE.rain_cover)
	assert_false(OUTDOOR_TABLE.covers_from_rain())


func test_covered_patio_seats_stay_open_in_rain_and_uncovered_ones_close() -> void:
	for cover: ItemDef in [PERGOLA, AWNING]:
		var sim: RestaurantSim = _plain(WeatherState.Kind.RAIN)
		var grid: SimGrid = sim.world.grid
		var under: PlacedItem = grid.place_def(OUTDOOR_TABLE, Vector2i(2, 7))
		var beside: PlacedItem = grid.place_def(OUTDOOR_TABLE, Vector2i(8, 7))
		assert_not_null(under)
		assert_not_null(beside)
		# Tables and chairs go under the canopy: it shares their cells.
		var canopy: PlacedItem = grid.place_def(cover, Vector2i(1, 6))
		assert_not_null(canopy, "%s goes over a placed table" % cover.id)
		for seat: Vector2i in under.seat_cells:
			assert_true(grid.is_rain_covered(seat))
			assert_true(PatioRules.seat_is_open(grid, seat, WeatherState.Kind.RAIN), "covered seat open in rain")
			assert_true(PatioRules.can_seat(grid, seat, WeatherState.Kind.RAIN))
		for seat: Vector2i in beside.seat_cells:
			assert_false(grid.is_rain_covered(seat))
			assert_false(PatioRules.seat_is_open(grid, seat, WeatherState.Kind.RAIN), "uncovered seat shut in rain")
			assert_false(PatioRules.can_seat(grid, seat, WeatherState.Kind.RAIN))
			assert_true(PatioRules.seat_is_open(grid, seat, WeatherState.Kind.SUNNY))
		assert_eq(DiningSeats.usable_cells(grid, under, SimGrid.NO_CELL, WeatherState.Kind.RAIN).size(), 2)
		assert_eq(DiningSeats.usable_cells(grid, beside, SimGrid.NO_CELL, WeatherState.Kind.RAIN).size(), 0)
		# The kitchen-keeping-up gate still applies under cover.
		var busy: Callable = func() -> bool: return false
		assert_false(PatioRules.can_seat(grid, under.seat_cells[0], WeatherState.Kind.RAIN, busy))
		# A real guest takes the covered table and never the open one.
		var guest: CustomerAgent = sim.add_customer(Vector2i(6, 6), _rng(625))
		assert_true(guest._try_seat(sim.world))
		assert_eq(guest.table_item_id, under.id, "rain seats the guest under the cover")
		# Taking the cover away closes the seats again.
		assert_true(grid.remove(canopy.id))
		assert_false(PatioRules.seat_is_open(grid, under.seat_cells[0], WeatherState.Kind.RAIN))


func test_cover_does_not_change_fair_weather_or_indoor_seats() -> void:
	var sim: RestaurantSim = _plain(WeatherState.Kind.SUNNY)
	var grid: SimGrid = sim.world.grid
	var inside: PlacedItem = grid.place_def(TABLE, Vector2i(2, 2))
	assert_not_null(grid.place_def(PERGOLA, Vector2i(1, 6)))
	for kind: int in [WeatherState.Kind.SUNNY, WeatherState.Kind.CLOUDY, WeatherState.Kind.RAIN]:
		for seat: Vector2i in inside.seat_cells:
			assert_true(PatioRules.seat_is_open(grid, seat, kind), "indoor seats are open in any weather")
		assert_true(PatioRules.seat_is_open(grid, Vector2i(2, 7), kind), "a covered patio cell is open in any weather")
	assert_false(PatioRules.seat_is_open(grid, Vector2i(10, 8), WeatherState.Kind.RAIN), "bare patio still shuts in rain")
	assert_true(PatioRules.seat_is_open(grid, Vector2i(10, 8), WeatherState.Kind.CLOUDY))


func test_cover_is_refused_off_the_patio_with_a_clear_reason() -> void:
	var grid: SimGrid = _plain(WeatherState.Kind.SUNNY).world.grid
	# On a wall, on the public pavement and running off the patio edge.
	for origin: Vector2i in [Vector2i(2, 1), Vector2i(0, 0), Vector2i(11, 8)]:
		for cover: ItemDef in [PERGOLA, AWNING]:
			assert_ne(grid.can_place_def(cover, origin), SimGrid.PlaceResult.OK, "%s at %s" % [cover.id, origin])
			assert_null(grid.place_def(cover, origin))
	assert_eq(grid.can_place_def(PERGOLA, Vector2i(1, 6)), SimGrid.PlaceResult.OK)
	assert_eq(ShopEditor.placement_reason(SimGrid.PlaceResult.OUTDOOR_ONLY, PERGOLA), ShopEditor.RAIN_COVER_NEEDS_PATIO)
	assert_eq(ShopEditor.placement_reason(SimGrid.PlaceResult.OUTDOOR_ONLY), "Outdoor furniture needs patio floor",
		"other outdoor furniture keeps its own wording")


func test_the_editor_refuses_cover_off_the_patio_and_charges_on_it() -> void:
	var patio: Array[Vector2i] = _left_patio()
	assert_true(_editor.apply_patio(patio, true), _editor.last_check.why)
	var cash: int = _ledger.cash
	var inside: Vector2i = _street(0, -3)
	for spot: Vector2i in [inside, _street(2, 0), _street(2, 3)]:
		assert_false(_editor.buy(&"pergola", spot), str(spot))
		assert_eq(_editor.last_check.why, ShopEditor.RAIN_COVER_NEEDS_PATIO, str(spot))
	assert_false(_editor.buy(&"awning", inside))
	assert_eq(_ledger.cash, cash, "a refused cover costs nothing")
	var origin: Vector2i = _cover_origin(patio)
	assert_true(_editor.buy(&"awning", origin), _editor.last_check.why)
	assert_eq(_ledger.cash, cash - AWNING.price)


func test_the_save_round_trips_cover_and_an_old_save_still_loads() -> void:
	var patio: Array[Vector2i] = _left_patio()
	assert_true(_editor.apply_patio(patio, true), _editor.last_check.why)
	var before: Dictionary = _editor.to_dict()
	# A save written before cover existed has no cover and loads unchanged.
	var errors: Array[String] = []
	var old: ShopLayout = ShopEditor.from_dict(JSON.parse_string(JSON.stringify(before)), LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(old)
	assert_eq(ShopBuilder.items_with_def(RestaurantSim.create(old, _content, 17, errors, null, true, true).world, &"pergola").size(), 0)
	var origin: Vector2i = _cover_origin(patio)
	assert_true(_editor.buy(&"pergola", origin), _editor.last_check.why)
	assert_true(_editor.buy(&"patio_table_2", origin + Vector2i(1, 1)), _editor.last_check.why)
	var expected: Dictionary = _editor.to_dict()
	var layout: ShopLayout = ShopEditor.from_dict(JSON.parse_string(JSON.stringify(expected)), LAYOUT, _content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	if layout == null:
		return
	var restored: RestaurantSim = RestaurantSim.create(layout, _content, 17, errors, null, true, true)
	assert_eq(errors, [] as Array[String])
	assert_eq(ShopEditor.new(restored, _content, ShopEditBooks.new(_can_spend, _record), layout).to_dict(), expected)
	var covers: Array[PlacedItem] = ShopBuilder.items_with_def(restored.world, &"pergola")
	assert_eq(covers.size(), 1)
	var table: PlacedItem = ShopBuilder.items_with_def(restored.world, &"patio_table_2")[0]
	restored.world.weather.kind = WeatherState.Kind.RAIN
	for seat: Vector2i in table.seat_cells:
		assert_true(PatioRules.seat_is_open(restored.world.grid, seat, WeatherState.Kind.RAIN),
			"the restored cover still keeps the seats open")


func _plain(kind: int) -> RestaurantSim:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
		"##############", "#............#", "#............#", "#............#", "#............#",
		"######..######", "......EE......", "..............", "..............", "..............", ".............."
	]))
	var rooms: Dictionary[Vector2i, int] = {}
	for y: int in range(6, 11):
		for x: int in 14:
			var cell: Vector2i = Vector2i(x, y)
			if grid.terrain(cell) == SimGrid.Terrain.FLOOR:
				rooms[cell] = SimGrid.Room.PATIO
	assert_true(grid.set_rooms(rooms))
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(grid)
	grid.cells_changed.connect(sim._on_layout_changed)
	sim.world.weather.kind = kind as WeatherState.Kind
	sim.rng.seed = 625
	sim.spawner = CustomerSpawner.new(sim.rng)
	return sim


## The top-left of a 4 x 4 block inside the bought patio.
func _cover_origin(patio: Array[Vector2i]) -> Vector2i:
	var corner: Vector2i = patio[0]
	for cell: Vector2i in patio:
		corner = Vector2i(mini(corner.x, cell.x), mini(corner.y, cell.y))
	return corner


func _left_patio() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row: int in range(_street(0, 0).y, _street(0, 0).y + LAYOUT.patio_depth):
		for column: int in range(0, _street(0, 0).x):
			cells.append(Vector2i(column, row))
	return cells


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName, note: String = "") -> void:
	_ledger.record(1, amount, category, note)


func _street(x: int, y: int) -> Vector2i:
	return _sim.world.grid.entries()[0] + Vector2i(x, y)
