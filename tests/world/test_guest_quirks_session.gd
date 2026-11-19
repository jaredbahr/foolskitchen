extends TestCase
## Guest quirks in a real session: Main gives the sim the authored quirks and
## the named `quirks` stream, which stays uncreated until a quirk can roll.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
var _main: Node


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_main_wires_the_quirks_and_their_lazy_stream() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	var sim: RestaurantSim = _main.get("sim")
	assert_eq(sim.quirks, preload("res://data/customers/quirks.tres"))
	assert_true(sim.quirk_rng_provider.is_valid())
	assert_false(GameState._rngs.has(&"quirks"), "no stream until a quirk can roll")
	assert_eq(sim.quirk_rng_provider.call(), GameState.rng(&"quirks"), "the named quirks stream")
