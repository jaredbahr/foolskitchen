extends TestCase
## Existing production planning must respond when the same menu expects a
## larger crowd, without changing stock, money, saved choices or RNG.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _main: Node = null
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_providers = SaveSystem._providers.duplicate()


func after_each() -> void:
	if _main != null:
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
		_main = null
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_standing_order_target_follows_expected_crowd_without_side_effects() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 7)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	assert_true(_main.call("menu_set_enabled", &"tomato_soup", false))
	assert_true(_main.call("menu_set_enabled", &"grilled_cheese", false))
	var sim: RestaurantSim = _main.get("sim")
	assert_eq(sim.menu.size(), 1)
	assert_eq(sim.menu[0].id, &"burger")
	var cash: int = Economy.cash
	var stock: Dictionary = Economy.stock.to_dict()
	var rng: Dictionary = GameState._capture_save()
	var settings: ReorderSettings = _main.get("reorder_settings")
	var saved_choices: Dictionary = settings.to_dict()
	assert_true(sim.set_demand_factor(1.0))
	var ordinary_guests: int = sim.expected_demand_guests(sim.demand_factor)
	var ordinary_target: int = (_main.call("_reorder") as ReorderSettings).target(&"bun")
	assert_true(sim.set_demand_factor(2.0))
	var busier_guests: int = sim.expected_demand_guests(sim.demand_factor)
	var busier_target: int = (_main.call("_reorder") as ReorderSettings).target(&"bun")
	assert_true(ordinary_guests > 0)
	assert_true(busier_guests > ordinary_guests, "the real demand model expects a larger crowd")
	assert_eq(Economy.cash, cash, "planning never purchases stock")
	assert_eq(Economy.stock.to_dict(), stock, "planning leaves inventory untouched")
	assert_eq(GameState._capture_save(), rng, "crowd forecasts draw no random numbers")
	assert_eq(settings.to_dict(), saved_choices, "a forecast never overwrites player settings")
	print("FORECAST RESTOCK PAIR: ", JSON.stringify({"ordinary_guests": ordinary_guests,
		"busier_guests": busier_guests, "ordinary_bun_target": ordinary_target,
		"busier_bun_target": busier_target}))
	assert_true(busier_target > ordinary_target,
		"the standing order must buy more buns when the same burger menu expects more guests")
