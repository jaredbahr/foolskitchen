extends TestCase
## Exact production default outputs, refreshed for FK-077's explicitly approved
## mechanic change. The first baseline was pre-drinks main6f6495d; these rows
## were measured with authored everyday messes, then retained as strict guards.
## Customers RNG remains unchanged in this seed; reviews and service may change.

const MainScene: PackedScene = preload("res://src/world/main.tscn")
## Day -> [served, lost, sales, closing cash, customers RNG state, reviews RNG state].
const EXPECTED: Array = [[17, 4, 158, 280, "-3340690172320019757", "-3285513833473108564"], [16, 3, 146, 280, "1894290104310310707", "6227064950443097254"]]

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


func test_two_default_days_match_recorded_mishap_baseline() -> void:
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
