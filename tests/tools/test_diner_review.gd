extends TestCase
## Native Main fixtures and fail-closed metadata checks; no screenshot capture.

const REVIEW: Script = preload("res://tools/diner_review.gd")
const CAPTURE: Script = preload("res://tools/screenshot.gd")
const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "diner_review_fixture"

var _main: Node
var _viewport: SubViewport
var _save_dir: String
var _old_save_dir: String
var _old_providers: Dictionary = {}
var _old_preferences: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "diner_review")
	SaveSystem.save_dir = _save_dir
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save"]:
		_old_preferences[key] = Preferences.get(key)
	Preferences.set("_file_path", _save_dir.path_join("preferences.cfg"))
	Preferences.set("_disk_enabled", false)
	Preferences.set("_pending_volume_save", false)


func after_each() -> void:
	if is_instance_valid(_main):
		if _main.is_inside_tree():
			_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if is_instance_valid(_viewport):
		if _viewport.is_inside_tree():
			_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	_viewport = null
	assert_false(FileAccess.file_exists(_save_dir.path_join(SLOT + ".json")), "fixture never saves")
	assert_false(FileAccess.file_exists(_save_dir.path_join("preferences.cfg")), "fixture never writes preferences")
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


func test_cli_accepts_exactly_two_paused_main_frames_and_rejects_other_modes() -> void:
	var valid: PackedStringArray = ["--diner-review", "--speed=0", "--frames=12,90"]
	assert_true(REVIEW.options(valid)["enabled"])
	assert_eq(REVIEW.options(valid)["error"], "")
	valid.append_array(["--out=screens/diner", "--out=screens/diner", "--scene=res://src/world/main.tscn"])
	assert_eq(REVIEW.options(valid)["error"], "")
	for extra: String in ["--open", "--fast=1", "--select=guest", "--assign-owner=kitchen", "--f3", "--menu",
			"--staff", "--report", "--build=green", "--paint", "--quarter=1", "--door-queue", "--settings",
			"--settings-world", "--hud-layout", "--loan-review", "--milestone-review", "--catalogue-review=rustic",
			"--speed=0", "--frames=12,90", "--window-size=1600x900", "--scene=res://src/world/main.tscn"]:
		var rejected: PackedStringArray = valid.duplicate()
		rejected.append(extra)
		assert_false(String(REVIEW.options(rejected)["error"]).is_empty(), extra)
	for rejected: PackedStringArray in [
		PackedStringArray(["--diner-review"]),
		PackedStringArray(["--diner-review=yes", "--speed=0", "--frames=12,90"]),
		PackedStringArray(["--diner-review", "--diner-review", "--speed=0", "--frames=12,90"]),
		PackedStringArray(["--diner-review", "--speed=1", "--frames=12,90"]),
		PackedStringArray(["--diner-review", "--speed=0", "--frames=90,12"]),
		PackedStringArray(["--diner-review", "--speed=0", "--frames=12"]),
		PackedStringArray(["--diner-review", "--speed=0", "--frames=12,90", "--scene=res://other.tscn"]),
	]:
		assert_false(String(REVIEW.options(rejected)["error"]).is_empty(), str(rejected))
	assert_false(REVIEW.options(PackedStringArray(["--speed=0"]))["enabled"])
	assert_false(String(CAPTURE.loan_review_options(PackedStringArray(["--loan-review", "--speed=0", "--frames=12,90", "--diner-review"]))["error"]).is_empty())
	assert_false(String(CAPTURE.milestone_review_options(PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90", "--diner-review"]))["error"]).is_empty())
	assert_false(String(CAPTURE.catalogue_review_options(PackedStringArray(["--catalogue-review=modern", "--speed=0", "--frames=90,120", "--diner-review"]))["error"]).is_empty())


func test_comparison_reads_six_real_models_refs_bounds_and_mini_without_mutation() -> void:
	await _start()
	var fixture: Dictionary = REVIEW.prepare(_main, _root())
	assert_eq(fixture.get("error"), "")
	if not String(fixture.get("error", "")).is_empty():
		return
	await _wait_frames(3)
	var before: Dictionary = _snapshot()
	var state: Dictionary = REVIEW.evidence(_main, _root(), 12)
	assert_true(REVIEW.valid(state, 12, fixture), JSON.stringify(state))
	assert_eq(_snapshot(), before, "evidence and validation leave clock, RNG, ledger, providers and preferences alone")
	assert_eq(state["pairs"].size(), 6)
	for change: String in ["model", "reference", "hash", "dimensions", "triangles", "bounds", "label", "mini", "lights", "clock", "rng"]:
		var broken: Dictionary = state.duplicate(true)
		match change:
			"model":
				broken["pairs"][0]["made"]["models"][0]["path"] = "res://mock.glb"
			"reference":
				broken["pairs"][5]["reference"]["models"][0]["path"] = "res://wrong.glb"
			"hash":
				broken["assets"][1]["reference_hash"] = "modified kit"
			"dimensions":
				broken["pairs"][0]["made"]["models"][0]["dimensions"][0] = 99.0
			"triangles":
				broken["pairs"][0]["made"]["models"][0]["triangles"] = 0
			"bounds":
				broken["pairs"][2]["made"]["bounds"]["inside"] = false
			"label":
				broken["pairs"][3]["made_label"]["text"] = ""
			"mini":
				broken["scale_mini"]["source"] = "res://mock.glb"
			"lights":
				broken["lights"].append("invented light")
			"clock":
				broken["snapshot"]["world_tick"] = 1
			"rng":
				broken["snapshot"]["restaurant_rng"][1] = "1"
		assert_false(REVIEW.valid(broken, 12, fixture), change + " fails closed")
	assert_false(REVIEW.valid(state, 90, fixture))


func test_furnished_guests_walk_to_reserved_booths_and_stools_and_use_native_sit() -> void:
	await _start()
	var fixture: Dictionary = REVIEW.prepare(_main, _root())
	assert_eq(fixture.get("error"), "")
	if not String(fixture.get("error", "")).is_empty():
		return
	fixture = REVIEW.furnish(_main, _root(), fixture)
	assert_eq(fixture.get("error"), "")
	if not String(fixture.get("error", "")).is_empty():
		return
	await _wait_frames(3)
	var before: Dictionary = _snapshot()
	var state: Dictionary = REVIEW.evidence(_main, _root(), 90)
	assert_true(REVIEW.valid(state, 90, fixture), JSON.stringify(state))
	assert_eq(_snapshot(), before)
	assert_eq(state["snapshot"]["world_tick"], 0, "guest-only fixture walks do not advance the clock or run service")
	assert_eq(state["snapshot"]["clock"]["phase"], int(SimClock.Phase.MORNING))
	assert_eq(state["snapshot"]["restaurant_rng"], fixture["baseline"]["restaurant_rng"])
	assert_eq(state["snapshot"]["run"], fixture["baseline"]["run"])
	for ticks: int in fixture["guest_ticks"]:
		assert_true(ticks > 0 and ticks <= REVIEW.WALK_BUDGET)
	for change: String in ["reservation", "role", "cell", "clip", "player", "lift", "source", "hidden", "furnishing", "link", "walls", "dining"]:
		var broken: Dictionary = state.duplicate(true)
		match change:
			"reservation":
				broken["actors"][0]["reservation"] = -1
			"role":
				broken["actors"][0]["role"] = "owner"
			"cell":
				broken["actors"][0]["cell"] = [6, 11]
			"clip":
				broken["actors"][0]["clip"] = "idle"
			"player":
				broken["actors"][0]["player_clip"] = "walk"
			"lift":
				broken["actors"][0]["seat_lift"] = 9.0
			"source":
				broken["actors"][0]["model_source"] = "res://fake.glb"
			"hidden":
				broken["actors"][0]["visible"] = false
			"furnishing":
				broken["actors"][0]["furnishing_definition"] = "table_2"
			"link":
				broken["actors"][0]["linked_table"] = -1
			"walls":
				broken["walls"].pop_back()
			"dining":
				broken["dining_failures"][1] = "missing seating"
		assert_false(REVIEW.valid(broken, 90, fixture), change + " fails closed")
	var content: ContentDB = _main.get("content") as ContentDB
	for id: StringName in [&"diner_open_sign", &"diner_chalkboard", &"diner_wall_art_a", &"diner_wall_art_b"]:
		assert_null(content.item(id), "view-only wall staging never registers player wall placement")
	assert_eq((_main.get("sim") as RestaurantSim).served_today, 0, "fixture is not a natural service or balance result")


func test_prepare_refuses_nonfresh_or_saving_main_before_staging_any_nodes() -> void:
	await _start()
	_main.set("use_saves", true)
	var before: Dictionary = _snapshot()
	assert_false(String(REVIEW.prepare(_main, _root()).get("error", "")).is_empty())
	assert_false(_main.has_node(REVIEW.COMPARISON))
	assert_eq(_snapshot(), before)
	_main.set("use_saves", false)
	var world: SimWorld = _main.get("world") as SimWorld
	world.now = 1
	before = _snapshot()
	assert_false(String(REVIEW.prepare(_main, _root()).get("error", "")).is_empty())
	assert_false(_main.has_node(REVIEW.COMPARISON))
	assert_eq(_snapshot(), before)


func _start() -> void:
	await _wait_frames(2)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_root().add_child(_viewport)
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	await _wait_frames(2)


func _snapshot() -> Dictionary:
	var progress: OwnerProgress = _main.get("owner_progress") as OwnerProgress
	return {"sim": REVIEW.snapshot(_main, _root()), "ledger": Economy.ledger.to_dict(),
		"progress": progress.to_dict(), "providers": SaveSystem._providers.duplicate(),
		"preferences": [Preferences._file_path, Preferences._disk_enabled, Preferences._pending_volume_save,
			Preferences.ui_scale_percent, Preferences.default_open_speed, Preferences.fullscreen_enabled,
			Preferences.edge_pan_enabled, Preferences.master_volume_percent, Preferences.music_volume_percent,
			Preferences.effects_volume_percent]}


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await (Engine.get_main_loop() as SceneTree).process_frame
