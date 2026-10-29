extends TestCase
## Capture setup is tested as source logic; rendered acceptance stays separate.

const REVIEW: Script = preload("res://tools/blueprint_review.gd")
const MAIN: PackedScene = preload("res://src/world/main.tscn")
var _main: Node


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_review_options_require_one_paused_isolated_profile() -> void:
	for profile: String in ["selection", "ghost", "stamped"]:
		var options: Dictionary = REVIEW.options(PackedStringArray(["--blueprints=" + profile, "--speed=0", "--frames=30"]))
		assert_eq(options["error"], "")
		assert_eq(options["profile"], profile)
	for flags: PackedStringArray in [PackedStringArray(["--blueprints=wrong"]),
			PackedStringArray(["--blueprints=ghost", "--speed=4", "--frames=30"]),
			PackedStringArray(["--blueprints=ghost", "--speed=0", "--frames=2"]),
			PackedStringArray(["--blueprints=ghost", "--speed=0", "--frames=30", "--open"])]:
		assert_false(String(REVIEW.options(flags)["error"]).is_empty())


func test_selection_fixture_uses_original_table_and_new_rug_without_a_library_yet() -> void:
	_start()
	var result: Dictionary = REVIEW.prepare(_main, "selection")
	assert_eq(result.get("error"), "")
	var mode: BuildMode = _main.get("build_mode")
	assert_eq(mode.state, BuildMode.State.SELECT)
	assert_eq(mode.blueprint_selection.size(), 2)
	assert_eq((_main.get("blueprint_library") as BlueprintLibrary).blueprints.size(), 0)
	assert_true(REVIEW.valid(REVIEW.evidence(_main), "selection"))


func test_ghost_fixture_uses_valid_rotated_group() -> void:
	_start()
	assert_eq(REVIEW.prepare(_main, "ghost").get("error"), "")
	var mode: BuildMode = _main.get("build_mode")
	assert_eq(mode.state, BuildMode.State.BLUEPRINT)
	assert_eq(mode.quarter_turns, 1)
	assert_eq(mode.blueprint_cost(), 70)
	assert_true(mode.current_check.ok, mode.current_check.why)
	assert_true(REVIEW.valid(REVIEW.evidence(_main), "ghost"))


func test_stamped_fixture_places_the_pair_with_one_history_step_and_real_cash() -> void:
	_start()
	var cash: int = Economy.cash
	assert_eq(REVIEW.prepare(_main, "stamped").get("error"), "")
	assert_eq(Economy.cash, cash - 30 + 20 - 70, "rug buy, old table refund, then whole stamp")
	var history: ShopEditHistory = _main.get("edit_history")
	assert_eq(history.undo_count(), 3)
	assert_true(REVIEW.valid(REVIEW.evidence(_main), "stamped"))
	assert_true(_main.call("undo_edit"))
	var world: SimWorld = _main.get("world")
	assert_null(world.grid.item_at(REVIEW.TARGET))
	assert_eq(Economy.cash, cash - 30 + 20)


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_speed(0)
