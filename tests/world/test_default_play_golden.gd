extends TestCase
## FK-083 golden: default hours, the default menu and no drink station play
## exactly as main did before drinks, Café/Bar themes and opening hours
## (main 6f6495d). Two seeded production days; every value below was
## recorded on that main. The new arrival weights, visit draw and drink-add
## chance must draw nothing and change nothing here.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
## Day -> [served, lost, sales, closing cash, customers RNG state, reviews RNG state].
const EXPECTED: Array = [[18, 3, 166, 308, "-3340690172320019757", "759273845251939063"], [17, 2, 155, 330, "1894290104310310707", "1950031383951538676"]]

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


func test_two_default_days_match_main_draw_for_draw() -> void:
	_main = MainScene.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 7)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	var rows: Array = []
	for day: int in range(2):
		assert_true(Clock.sim.start_service())
		var guard: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 30:
			_main.call("run_ticks", 1000)
			guard += 1
		var sim: RestaurantSim = _main.get("sim") as RestaurantSim
		var book: Dictionary = Economy.ledger.day_totals(Clock.sim.day)
		rows.append([sim.served_today, sim.lost_today, int(book.get(Ledger.SALE, 0)), Economy.cash,
			str(GameState.rng(&"customers").state), str(GameState.rng(&"reviews").state)])
		assert_true(Clock.sim.next_day())
	assert_eq(rows, EXPECTED)
