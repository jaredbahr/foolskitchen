extends Node
## Owns the run-wide state that every system shares: the master seed and
## one seeded RandomNumberGenerator per system. Never call global randf()/randi();
## use GameState.rng(&"customers") (or your system's name) instead, so a run
## replays exactly from its seed.

var master_seed: int = 1

var _rngs: Dictionary[StringName, RandomNumberGenerator] = {}


## Starts a new run: sets the master seed and drops all per-system RNGs.
func new_run(seed_value: int) -> void:
	master_seed = seed_value
	_rngs.clear()


## Returns the RNG for a system, creating it on first use. Its seed is derived
## from the master seed and the system name, so systems don't disturb each other.
func rng(system: StringName) -> RandomNumberGenerator:
	if not _rngs.has(system):
		var r := RandomNumberGenerator.new()
		r.seed = hash(str(master_seed) + ":" + String(system))
		_rngs[system] = r
	return _rngs[system]
