extends TestCase
## Focused CLI and native Main fixture checks. Pixel review uses the separate
## screenshot command and its post-draw PNG/JSON output.

const REVIEW: Script = preload("res://tools/menu_boards_review.gd")
const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "menu_boards_review_fixture"

var _main: Node
var _viewport: SubViewport
var _save_dir: String
var _old_save_dir: String
var _old_providers: Dictionary = {}
var _old_preferences: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "menu_boards_review")
	SaveSystem.save_dir = _save_dir
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save"]:
		_old_preferences[key] = Preferences.get(key)
	Preferences.set("_file_path", _save_dir.path_join("preferences.cfg"))
	Preferences.set("_disk_enabled", false)
	Preferences.set("_pending_volume_save", false)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	_viewport = null
	assert_false(FileAccess.file_exists(_save_dir.path_join(SLOT + ".json")), "review fixture must not save")
	assert_false(FileAccess.file_exists(_save_dir.path_join("preferences.cfg")), "review fixture must not persist preferences")
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	for key: String in _old_preferences:
		Preferences.set(key, _old_preferences[key])
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_menu_boards_cli_requires_one_exact_paused_two_frame_sequence() -> void:
	var valid: PackedStringArray = ["--menu-boards-review", "--speed=0", "--frames=12,30"]
	assert_true(REVIEW.options(valid)["enabled"])
	assert_eq(REVIEW.options(valid)["error"], "")
	valid.append_array(["--out=screens/boards", "--out=screens/boards", "--scene=res://src/world/main.tscn"])
	assert_eq(REVIEW.options(valid)["error"], "")
	for extra: String in ["--open", "--fast=1", "--select=owner", "--assign-owner=kitchen", "--f3",
			"--menu", "--staff", "--stock", "--report", "--build=green", "--paint", "--quarter=0",
			"--door-queue", "--settings", "--settings-world", "--hud-layout", "--loan-review",
			"--milestone-review", "--diner-review", "--catalogue-review=rustic", "--walls-review",
			"--floors-review", "--blueprints=ghost", "--speed=0", "--frames=12,30",
			"--window-size=1600x900", "--scene=res://src/world/main.tscn"]:
		var rejected: PackedStringArray = valid.duplicate()
		rejected.append(extra)
		assert_false(String(REVIEW.options(rejected)["error"]).is_empty(), extra)
	for rejected: PackedStringArray in [
		PackedStringArray(["--menu-boards-review"]),
		PackedStringArray(["--menu-boards-review=yes", "--speed=0", "--frames=12,30"]),
		PackedStringArray(["--menu-boards-review", "--menu-boards-review", "--speed=0", "--frames=12,30"]),
		PackedStringArray(["--menu-boards-review", "--speed=1", "--frames=12,30"]),
		PackedStringArray(["--menu-boards-review", "--speed=0", "--frames=30,12"]),
		PackedStringArray(["--menu-boards-review", "--speed=0", "--frames=12"]),
		PackedStringArray(["--menu-boards-review", "--speed=0", "--frames=12,30", "--scene=res://other.tscn"]),
	]:
		assert_false(String(REVIEW.options(rejected)["error"]).is_empty(), str(rejected))
	assert_false(REVIEW.options(PackedStringArray(["--menu", "--speed=0", "--frames=12"]))["enabled"])


func test_real_paused_board_inspector_and_menu_theme_are_distinct_native_views() -> void:
	await _start()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var fixture: Dictionary = REVIEW.prepare(_main, root)
	assert_eq(fixture.get("error"), "")
	if not String(fixture.get("error", "")).is_empty():
		return
	await _wait_frames(2)
	var before: Dictionary = _snapshot()
	var board_state: Dictionary = REVIEW.evidence(_main, root, 12)
	assert_true(REVIEW.valid(board_state, 12, fixture), JSON.stringify(board_state))
	assert_eq(board_state["owner"]["id"], fixture["owner_id"], "the fixture keeps the existing owner")
	assert_eq(board_state["owner"]["agent_count"], fixture["agent_count"], "the fixture spawns no character")
	assert_eq(board_state["owner"]["cell"], REVIEW.OWNER_CELL)
	assert_true(board_state["owner"]["native_person"])
	assert_eq(_snapshot(), before, "evidence must not change world, menu, decor, cash or RNG")
	var mutated: Dictionary = board_state.duplicate(true)
	mutated["board"]["text"] = "fake text"
	assert_false(REVIEW.valid(mutated, 12, fixture))
	mutated = board_state.duplicate(true)
	mutated["inspector"]["choice_section"] = RecipeDef.Section.DRINKS
	assert_false(REVIEW.valid(mutated, 12, fixture))
	assert_eq(REVIEW.show_menu_theme(_main)["error"], "")
	await _wait_frames(2)
	var menu_state: Dictionary = REVIEW.evidence(_main, root, 30)
	assert_true(REVIEW.valid(menu_state, 30, fixture), JSON.stringify(menu_state))
	assert_eq(menu_state["board"]["text"], board_state["board"]["text"], "opening Menu does not rewrite the board")
	mutated = menu_state.duplicate(true)
	mutated["menu_panel"]["theme_text"] = "invented"
	assert_false(REVIEW.valid(mutated, 30, fixture))
	assert_false(REVIEW.valid(board_state, 30, fixture), "frame identity cannot be swapped")


func _start() -> void:
	await _wait_frames(2)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	(Engine.get_main_loop() as SceneTree).root.add_child(_viewport)
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	await _wait_frames(2)


func _snapshot() -> Dictionary:
	return {"world_tick": (_main.get("world") as SimWorld).now,
		"menu": (_main.get("menu_settings") as MenuSettings).to_dict(),
		"decor": (_main.get("shop_editor") as ShopEditor).decor.to_rows(),
		"cash": Economy.cash, "ledger": Economy.ledger.to_dict(),
		"seed": str(GameState.master_seed), "rng": str((_main.get("sim") as RestaurantSim).rng.state)}


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await (Engine.get_main_loop() as SceneTree).process_frame
