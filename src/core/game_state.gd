extends Node
## Owns the run-wide state that every system shares: the master seed and
## one seeded RandomNumberGenerator per system. Never call global randf()/randi();
## use GameState.rng(&"customers") (or your system's name) instead, so a run
## replays exactly from its seed.

var master_seed: int = 1

var _rngs: Dictionary[StringName, RandomNumberGenerator] = {}


func _ready() -> void:
	SaveSystem.register("game_state", _capture_save, _restore_save)


func _capture_save() -> Dictionary:
	var systems: Dictionary = {}
	for system: StringName in _rngs:
		var generator: RandomNumberGenerator = _rngs[system]
		# JSON numbers parse as doubles; decimal strings preserve all 64 bits.
		systems[String(system)] = {"seed": str(generator.seed), "state": str(generator.state)}
	return {"master_seed": str(master_seed), "rngs": systems}


func _restore_save(data: Dictionary) -> bool:
	var seed_text: String = str(data.get("master_seed", ""))
	var systems_value: Variant = data.get("rngs", null)
	if not seed_text.is_valid_int() or not systems_value is Dictionary:
		return false
	var systems: Dictionary = systems_value
	var restored: Dictionary[StringName, RandomNumberGenerator] = {}
	for system: Variant in systems:
		if not system is String or not systems[system] is Dictionary:
			return false
		var entry: Dictionary = systems[system]
		var rng_seed: String = str(entry.get("seed", ""))
		var rng_state: String = str(entry.get("state", ""))
		if not rng_seed.is_valid_int() or not rng_state.is_valid_int():
			return false
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = rng_seed.to_int()
		generator.state = rng_state.to_int()
		restored[StringName(system)] = generator
	master_seed = seed_text.to_int()
	_rngs = restored
	return true


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
