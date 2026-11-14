extends TestCase
## #526 finding 2: a new game must start clean. Quit to title and New game
## replace Main with a fresh instance, but the autoloads (Clock, GameState,
## Economy, SaveSystem, Preferences) and static state live on. So a system that
## keeps state outside Main, or that Main forgets to reset, leaks last game's
## state into the next one. This plays two real days, starts a new game with
## the same seed and compares every registered save section with a first boot.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
## Two days: enough for every daily system (reports, goals, stock, staff, events)
## to change, while keeping the suite inside the hosted 25-minute limit.
const PLAYED_DAYS: int = 2
## Real ticks a service day may take before the test calls it stuck.
const MAX_BATCHES: int = 30

var _main: Node
var _providers: Dictionary


func before_each() -> void:
	_providers = SaveSystem._providers.duplicate(true)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_a_new_game_after_played_days_matches_a_first_boot() -> void:
	_start()
	var first: Dictionary = _capture_all()
	assert_true(first.size() >= 30, "every registered section is compared (%d)" % first.size())
	for day: int in PLAYED_DAYS:
		assert_true(Clock.sim.start_service(), "day %d opens" % Clock.sim.day)
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < MAX_BATCHES:
			_main.call("run_ticks", 1000)
			batches += 1
		assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED, "day %d closes" % Clock.sim.day)
		assert_true(Clock.sim.next_day(), "the next morning starts")
	var played: Dictionary = _capture_all()
	assert_true(played != first, "the played days changed the game, so the comparison means something")
	_close()
	_start()
	var second: Dictionary = _capture_all()
	assert_eq(second.keys(), first.keys(), "the same sections are registered")
	for key: String in first:
		assert_eq(JSON.stringify(second.get(key)), JSON.stringify(first[key]),
			"section %s starts the new game exactly as a first boot" % key)


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


## Every registered section, as the morning save would write it.
func _capture_all() -> Dictionary:
	var sections: Dictionary = {}
	for key: String in SaveSystem.keys():
		var capture: Callable = SaveSystem._providers[key]["capture"]
		sections[key] = capture.call() if capture.is_valid() else null
	return sections
