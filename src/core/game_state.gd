extends Node
## Owns one repeatable RNG stream per named system for the pinned engine.
## Request order and draws in another system do not change a stream's seed.

const RNG_NAMES: Array[StringName] = [&"customers", &"staff", &"events", &"minigames"]

var run_seed: int = 1
var _rngs: Dictionary[StringName, RandomNumberGenerator] = {}


func _init() -> void:
	reset_rngs(run_seed)


## Starts all streams from the given seed; call only at a new run boundary.
func reset_rngs(new_seed: int) -> void:
	run_seed = new_seed
	_rngs.clear()
	for system_name: StringName in RNG_NAMES:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = ("%d:%s" % [run_seed, system_name]).hash()
		_rngs[system_name] = rng


## Returns the existing stream. Callers must not reseed or randomize it.
func get_rng(system_name: StringName) -> RandomNumberGenerator:
	assert(_rngs.has(system_name), "Unknown RNG system: %s" % system_name)
	return _rngs[system_name]
