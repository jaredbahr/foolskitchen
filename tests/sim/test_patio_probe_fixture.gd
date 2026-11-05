extends TestCase
## The optional probe must retain real patio ownership without charging for
## its disclosed construction, changing weather, or granting service inputs.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const DIRT: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")

class SetupHost extends Node:
	var sim: RestaurantSim
	var content: ContentDB
	var shop_editor: ShopEditor
	var refreshes: int = 0

	func refresh_presentation() -> void:
		refreshes += 1

var _host: SetupHost
var _ledger: Ledger
var _saved_game: Dictionary


func before_each() -> void:
	_saved_game = GameState._capture_save().duplicate(true)
	_host = SetupHost.new()
	_host.content = ContentDB.new()
	assert_eq(_host.content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_host.sim = RestaurantSim.create(LAYOUT, _host.content, 243, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_host.sim.world.weather.day = 1
	_host.sim.world.weather.kind = WeatherState.Kind.RAIN
	_host.sim.stock.add(_host.content.ingredients()[0].id, 7, 1)
	assert_true(_host.sim.configure_cleanliness(CleanlinessState.new(_host.sim.world.grid,
		DIRT, GameState.rng(&"cleanliness")), DIRT))
	_ledger = Ledger.new()
	_ledger.cash = 300
	_host.shop_editor = ShopEditor.new(_host.sim, _host.content, ShopEditBooks.new(_can_spend, _record), LAYOUT)


func after_each() -> void:
	_host.free()
	_host = null
	_ledger = null
	assert_true(GameState._restore_save(_saved_game))


func test_patio_probe_owns_two_tables_and_cells_without_cash_stock_weather_or_rng_grants() -> void:
	var stock: Dictionary = _host.sim.stock.to_dict()
	var weather: Dictionary = _host.sim.world.weather.to_dict()
	var streams: Dictionary = GameState._capture_save().duplicate(true)
	assert_true(ProbeSetups.names().has("patio"))
	assert_true(ProbeSetups.apply("patio", _host))
	assert_eq(_host.shop_editor.bought_patio().size(), PatioArea.from_layout(LAYOUT).cells().size(),
		"probe floor ownership must live on the same editor that the session saves")
	assert_eq(ShopBuilder.items_with_def(_host.sim.world, &"table_2").size(), 3)
	assert_eq(ShopBuilder.items_with_def(_host.sim.world, &"patio_table_2").size(), 2)
	assert_eq(_ledger.cash, 300)
	assert_eq(_ledger.day_costs(1), 0)
	assert_eq(_host.sim.stock.to_dict(), stock)
	assert_eq(_host.sim.world.weather.to_dict(), weather, "probe setup never forces a convenient weather kind")
	assert_eq(GameState._capture_save(), streams)
	assert_eq(_host.refreshes, 1)
	assert_eq(_host.sim.world.grid.entries(), SimGrid.from_ascii(LAYOUT.rows).entries())
	for table: PlacedItem in ShopBuilder.items_with_def(_host.sim.world, &"patio_table_2"):
		assert_true(ProbeSetups.patio_table_origins(_host.sim.world.grid).has(table.origin))
		assert_eq(DiningSeats.usable_cells(_host.sim.world.grid, table).size(), 2)
		assert_eq(DiningSeats.usable_cells(_host.sim.world.grid, table, SimGrid.NO_CELL,
			WeatherState.Kind.RAIN).size(), 0)
	_host.sim.start_day()
	assert_eq(_host.shop_editor.bought_patio().size(), PatioArea.from_layout(LAYOUT).cells().size())
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(_host.shop_editor.to_dict(), LAYOUT, _host.content, errors)
	assert_eq(errors, [] as Array[String])
	assert_not_null(layout)
	if layout != null:
		var restored: RestaurantSim = RestaurantSim.create(layout, _host.content, 243, errors, null, false)
		assert_eq(errors, [] as Array[String])
		assert_eq(layout.patio_cells, _host.shop_editor.bought_patio())
		assert_eq(ShopBuilder.items_with_def(restored.world, &"patio_table_2").size(), 2)


func test_default_probe_keeps_its_shop_and_all_weather_rng_inputs_unchanged() -> void:
	var before: Dictionary = _host.shop_editor.to_dict()
	var streams: Dictionary = GameState._capture_save().duplicate(true)
	var weather: Dictionary = _host.sim.world.weather.to_dict()
	var bounds: Rect2i = _host.sim.world.grid.bounds
	assert_true(ProbeSetups.apply("default", _host))
	assert_eq(_host.shop_editor.to_dict(), before)
	assert_eq(_host.sim.world.grid.bounds, bounds)
	assert_eq(_host.sim.world.weather.to_dict(), weather)
	assert_eq(GameState._capture_save(), streams)
	assert_true(_host.shop_editor.bought_patio().is_empty())
	assert_eq(_host.refreshes, 0)
	assert_eq(_ledger.cash, 300)


func _can_spend(amount: int) -> bool:
	return amount >= 0 and amount <= _ledger.cash


func _record(amount: int, category: StringName) -> void:
	_ledger.record(1, amount, category)
