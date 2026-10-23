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
	var seed_value: Variant = data.get("master_seed", null)
	var systems_value: Variant = data.get("rngs", null)
	if not _is_int64_text(seed_value) or not systems_value is Dictionary:
		return false
	var seed_text: String = seed_value
	var systems: Dictionary = systems_value
	var restored: Dictionary[StringName, RandomNumberGenerator] = {}
	for system: Variant in systems:
		if not system is String or not systems[system] is Dictionary:
			return false
		var entry: Dictionary = systems[system]
		var seed_variant: Variant = entry.get("seed", null)
		var state_variant: Variant = entry.get("state", null)
		if not _is_int64_text(seed_variant) or not _is_int64_text(state_variant):
			return false
		var rng_seed: String = seed_variant
		var rng_state: String = state_variant
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = rng_seed.to_int()
		generator.state = rng_state.to_int()
		restored[StringName(system)] = generator
	master_seed = seed_text.to_int()
	_rngs = restored
	return true


func _is_int64_text(value: Variant) -> bool:
	if not value is String or value.is_empty():
		return false
	var text: String = value
	var negative: bool = text.begins_with("-")
	var digits: String = text.substr(1) if negative else text
	if digits.is_empty():
		return false
	for character: String in digits:
		if character < "0" or character > "9":
			return false
	digits = digits.lstrip("0")
	if digits.is_empty():
		return true
	var limit: String = "9223372036854775808" if negative else "9223372036854775807"
	return digits.length() < limit.length() or (digits.length() == limit.length() and digits <= limit)


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
