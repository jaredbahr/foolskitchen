extends GutTest
## Sample core test: seeded streams reproduce and remain independent.

const GameStateScript: GDScript = preload("res://src/core/game_state.gd")


func test_named_rngs_repeat_without_cross_system_interference() -> void:
	var first: GameStateScript = GameStateScript.new()
	var second: GameStateScript = GameStateScript.new()
	add_autofree(first)
	add_autofree(second)
	first.reset_rngs(12345)
	second.reset_rngs(12345)
	var initial_draw: int = first.get_rng(&"customers").randi()
	assert_eq(initial_draw, second.get_rng(&"customers").randi())
	first.get_rng(&"staff").randi()
	assert_eq(first.get_rng(&"customers").randi(), second.get_rng(&"customers").randi())
	assert_ne(first.get_rng(&"customers"), first.get_rng(&"staff"))
	first.reset_rngs(12345)
	second.reset_rngs(12345)
	assert_eq(first.get_rng(&"customers").randi(), initial_draw)
	assert_eq(second.get_rng(&"customers").randi(), initial_draw)
