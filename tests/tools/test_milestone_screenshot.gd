extends TestCase
## CLI, native controls and fixture validation; no image is captured here.

const CAPTURE: Script = preload("res://tools/screenshot.gd")
const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "milestone_review_fixture"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}
var _old_preferences: Dictionary = {}
var _window: Window
var _old_window_size: Vector2i
var _old_content_scale: float


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "milestone_screenshot")
	SaveSystem.save_dir = _save_dir
	_window = (Engine.get_main_loop() as SceneTree).root
	_old_preferences.clear()
	for key: String in ["_file_path", "_disk_enabled", "_pending_volume_save"]:
		_old_preferences[key] = Preferences.get(key)
	_old_window_size = _window.size
	_old_content_scale = _window.content_scale_factor
	Preferences.set("_file_path", _save_dir.path_join("preferences.cfg"))
	Preferences.set("_disk_enabled", false)
	Preferences.set("_pending_volume_save", false)
	_window.size = Vector2i(1600, 900)
	_window.content_scale_factor = 1.0


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	for key: String in _old_preferences:
		Preferences.set(key, _old_preferences[key])
	if _window.size != _old_window_size:
		_window.size = _old_window_size
	_window.content_scale_factor = _old_content_scale
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)
	if FileAccess.file_exists(_save_dir.path_join(SLOT + ".json")):
		DirAccess.remove_absolute(_save_dir.path_join(SLOT + ".json"))
	if FileAccess.file_exists(_save_dir.path_join(SLOT + ".json.bak")):
		DirAccess.remove_absolute(_save_dir.path_join(SLOT + ".json.bak"))
	if FileAccess.file_exists(_save_dir.path_join(SLOT + ".json.tmp")):
		DirAccess.remove_absolute(_save_dir.path_join(SLOT + ".json.tmp"))
	assert_false(FileAccess.file_exists(_save_dir.path_join("preferences.cfg")))
	DirAccess.remove_absolute(_save_dir)


func test_cli_guard_accepts_only_the_paused_two_frame_main_capture() -> void:
	var valid: PackedStringArray = PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90"])
	var accepted: Dictionary = CAPTURE.milestone_review_options(valid)
	assert_eq(accepted["error"], "")
	assert_true(accepted["enabled"])
	valid.append_array(["--out=screens/milestones", "--out=screens/milestones", "--scene=res://src/world/main.tscn"])
	assert_eq(CAPTURE.milestone_review_options(valid)["error"], "", "the shell may repeat --out")
	for arguments: PackedStringArray in [
		PackedStringArray(["--milestone-review"]),
		PackedStringArray(["--milestone-review=yes", "--speed=0", "--frames=12,90"]),
		PackedStringArray(["--milestone-review", "--milestone-review", "--speed=0", "--frames=12,90"]),
		PackedStringArray(["--milestone-review", "--speed=1", "--frames=12,90"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--speed=0", "--frames=12,90"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=12"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=90,12"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90", "--frames=12,90"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90", "--scene=res://other.tscn"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90", "--scene=res://src/world/main.tscn", "--scene=res://src/world/main.tscn"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90", "--open"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90", "--loan-review"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90", "--menu"]),
		PackedStringArray(["--milestone-review", "--speed=0", "--frames=12,90", "--window-size=1280x720"]),
	]:
		assert_false(String(CAPTURE.milestone_review_options(arguments)["error"]).is_empty(), str(arguments))
	var legacy: Dictionary = CAPTURE.milestone_review_options(PackedStringArray(["--speed=0", "--frames=12,90"]))
	assert_eq(legacy["error"], "")
	assert_false(legacy["enabled"])
	assert_false(String(CAPTURE.loan_review_options(PackedStringArray(["--loan-review", "--speed=0", "--frames=12,90", "--milestone-review"]))["error"]).is_empty())
	assert_false(String(CAPTURE.hud_layout_options(PackedStringArray(["--hud-layout", "--speed=0", "--frames=12,90", "--milestone-review"]))["error"]).is_empty())


func test_real_main_fixture_shows_goals_then_uses_real_close_and_read_only_evidence() -> void:
	var preference_snapshot: Dictionary = _preference_snapshot()
	var main: Node = await _start_main()
	var fixture: Dictionary = CAPTURE.prepare_milestone_review(main, (Engine.get_main_loop() as SceneTree).root)
	assert_eq(fixture.get("error"), "")
	if not String(fixture.get("error", "")).is_empty():
		return
	assert_true(int(fixture["starting_day_profit"]) < 0,
		"natural morning restock is already reflected in the fixture cash baseline")
	await _wait_frames(2)
	var before_goals: Dictionary = _main_snapshot(main)
	var providers_before_goals: Dictionary = SaveSystem._providers.duplicate()
	var goals_state: Dictionary = CAPTURE.milestone_review_evidence(main, (Engine.get_main_loop() as SceneTree).root, 12)
	assert_true(CAPTURE.milestone_review_valid(goals_state, 12, fixture))
	assert_eq(_main_snapshot(main), before_goals, "native evidence and validation never change Main or its ledgers")
	assert_eq(SaveSystem._providers, providers_before_goals, "read-only evidence leaves provider registration alone")
	assert_eq(SaveSystem.save_dir, _save_dir, "the capture test stays inside its private save path")
	assert_eq(_preference_snapshot(), preference_snapshot, "capture reads never write local settings")
	assert_false(Preferences._disk_enabled, "the test uses an isolated no-write settings fixture")
	assert_false(Preferences._pending_volume_save, "the fixture suspends deferred preference writes")
	var with_missing_goal: Dictionary = goals_state.duplicate(true)
	with_missing_goal["goals_panel"]["cards"].remove_at(2)
	assert_false(CAPTURE.milestone_review_valid(with_missing_goal, 12, fixture), "a missing active goal fails closed")
	var clipped_goal: Dictionary = goals_state.duplicate(true)
	clipped_goal["goals_panel"]["cards"][0]["fields"]["Title"]["inside_clip"] = false
	assert_false(CAPTURE.milestone_review_valid(clipped_goal, 12, fixture), "a clipped native goal title fails closed")
	var missing_panel: Dictionary = goals_state.duplicate(true)
	missing_panel["goals_panel"]["available"] = false
	assert_false(CAPTURE.milestone_review_valid(missing_panel, 12, fixture), "a missing native panel fails closed")

	fixture = CAPTURE.advance_milestone_review(main, (Engine.get_main_loop() as SceneTree).root, fixture)
	assert_eq(fixture.get("error"), "")
	if not String(fixture.get("error", "")).is_empty():
		return
	await _wait_frames(2)
	var before_report_query: Dictionary = _main_snapshot(main)
	var providers_before_report: Dictionary = SaveSystem._providers.duplicate()
	var report_state: Dictionary = CAPTURE.milestone_review_evidence(main, (Engine.get_main_loop() as SceneTree).root, 90)
	assert_true(CAPTURE.milestone_review_valid(report_state, 90, fixture))
	assert_eq(_main_snapshot(main), before_report_query, "report evidence and validation remain query-only")
	assert_eq(SaveSystem._providers, providers_before_report)
	var missing_reward: Dictionary = report_state.duplicate(true)
	missing_reward["milestone_bonus_entries"][0]["amount"] = 0
	assert_false(CAPTURE.milestone_review_valid(missing_reward, 90, fixture), "missing ledger reward evidence fails closed")
	var wrong_cash_baseline: Dictionary = fixture.duplicate(true)
	wrong_cash_baseline["starting_day_profit"] = 0
	assert_false(CAPTURE.milestone_review_valid(report_state, 90, wrong_cash_baseline),
		"cash parity includes the real morning restock already present before the fixture")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var tracker: MilestoneTracker = main.get("milestones") as MilestoneTracker
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	assert_eq(sim.served_today, 10, "only the explicit synthetic close counter reaches the authored threshold")
	assert_eq(sim.customers().size(), 0, "the capture fixture does not fabricate paid guests")
	assert_true(tracker.is_completed(&"first_rush"), "Main's actual close path awards the authored first goal")
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.MILESTONE_BONUS), 10)
	assert_eq(owner.total_xp, int(fixture["starting_xp"]) + int(report_state["report"]["total_xp"]))
	assert_false(FileAccess.file_exists(_save_dir.path_join(SLOT + ".json")), "use_saves=false performs no test save")
	assert_eq(_preference_snapshot(), preference_snapshot)

	var uid_before: Array[Dictionary] = _uid_snapshot(CAPTURE.MILESTONE_UID_SOURCES)
	var uid_evidence: Dictionary = CAPTURE.generated_uid_evidence(CAPTURE.MILESTONE_UID_SOURCES)
	assert_true(uid_evidence["read_only"])
	assert_eq(uid_evidence["entries"].size(), 13)
	assert_eq(uid_evidence["entries"].map(func(entry: Dictionary) -> String: return entry["source"]),
		CAPTURE.MILESTONE_UID_SOURCES)
	assert_eq(_uid_snapshot(CAPTURE.MILESTONE_UID_SOURCES), uid_before, "UID provenance never generates or registers sidecars")


func _start_main() -> Node:
	await _wait_frames(2)
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 1)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	await _wait_frames(2)
	return main


func _wait_frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for _index: int in range(count):
		await tree.process_frame


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _main_snapshot(main: Node) -> Dictionary:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var world: SimWorld = main.get("world") as SimWorld
	var tracker: MilestoneTracker = main.get("milestones") as MilestoneTracker
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var catalogue: MilestoneSet = main.get("milestone_catalogue") as MilestoneSet
	var definitions: Array[Dictionary] = []
	for goal: Milestone in catalogue.milestones:
		definitions.append(CAPTURE._milestone_definition_record(goal))
	return {"world_tick": world.now, "clock": Clock.sim.to_dict(), "served": sim.served_today,
		"lost": sim.lost_today, "tracker": tracker.to_dict(), "owner": owner.to_dict(),
		"ledger": Economy.ledger.to_dict(), "catalogue": definitions,
		"goals_visible": bool(main.call("is_goals_visible")),
		"menu_visible": bool(main.call("is_menu_visible")),
		"report_visible": (main.get_node("Overlay/EveningReport") as Control).visible}


func _preference_snapshot() -> Dictionary:
	return {"master": Preferences.master_volume_percent, "music": Preferences.music_volume_percent,
		"effects": Preferences.effects_volume_percent, "scale": Preferences.ui_scale_percent,
		"speed": Preferences.default_open_speed, "fullscreen": Preferences.fullscreen_enabled,
		"edge_pan": Preferences.edge_pan_enabled, "path": Preferences._file_path,
		"disk_enabled": Preferences._disk_enabled,
		"pending_volume_save": Preferences._pending_volume_save}


func _uid_snapshot(sources: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: String in sources:
		var sidecar: String = source + ".uid"
		result.append({"source": source, "exists": FileAccess.file_exists(sidecar),
			"text": FileAccess.get_file_as_string(sidecar) if FileAccess.file_exists(sidecar) else "",
			"registered": str(ResourceLoader.get_resource_uid(source))})
	return result
