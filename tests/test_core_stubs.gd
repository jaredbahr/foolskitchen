extends TestCase
## Phase 0 sanity tests for the core autoload stubs.

const GameStateScript := preload("res://src/core/game_state.gd")
const ClockScript := preload("res://src/core/clock.gd")


func test_rng_is_deterministic_per_seed_and_system() -> void:
	var a: Node = GameStateScript.new()
	var b: Node = GameStateScript.new()
	a.new_run(42)
	b.new_run(42)
	var ra: RandomNumberGenerator = a.rng(&"customers")
	var rb: RandomNumberGenerator = b.rng(&"customers")
	assert_eq(ra.randi(), rb.randi(), "same seed and system give the same sequence")
	a.free()
	b.free()


func test_rng_systems_are_independent() -> void:
	var gs: Node = GameStateScript.new()
	gs.new_run(7)
	var c: int = gs.rng(&"customers").randi()
	var s: int = gs.rng(&"staff").randi()
	assert_ne(c, s, "different systems get different streams")
	assert_true(gs.rng(&"customers") == gs.rng(&"customers"), "the same RNG object is reused")
	gs.free()


func test_clock_rejects_unknown_speed() -> void:
	var clock: Node = ClockScript.new()
	assert_true(clock.set_speed(2))
	assert_eq(clock.speed, 2)
	assert_false(clock.set_speed(3), "3x is not an allowed speed")
	assert_eq(clock.speed, 2, "speed unchanged after a rejected value")
	clock.free()
