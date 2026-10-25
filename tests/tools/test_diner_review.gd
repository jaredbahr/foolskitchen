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
	for change: String in ["model", "reference", "hash", "dimensions", "triangles", "bounds", "label", "billboard", "mini", "mini_scale", "lights", "clock", "rng", "notice_background", "notice_contrast", "notice_clipped"]:
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
			"billboard":
				broken["pairs"][3]["made_label"]["billboard"] = int(BaseMaterial3D.BILLBOARD_ENABLED)
			"mini":
				broken["scale_mini"]["source"] = "res://mock.glb"
			"mini_scale":
				broken["scale_mini"]["scale"] = 1.2
			"lights":
				broken["lights"].append("invented light")
			"clock":
				broken["snapshot"]["world_tick"] = 1
			"rng":
				broken["snapshot"]["restaurant_rng"][1] = "1"
			"notice_background":
				broken["notice"]["background_drawn"] = false
			"notice_contrast":
				broken["notice"]["contrast"] = 1.0
			"notice_clipped":
				broken["notice"]["visible_lines"] = 1
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
	var world: SimWorld = _main.get("world") as SimWorld
	var shop: ShopView = _main.get_node("ShopView") as ShopView
	for actor: Dictionary in state["actors"]:
		var furnishing: PlacedItem = world.grid.item(int(actor["furnishing"]))
		var definition: ItemDef = furnishing.def as ItemDef
		var person: PersonView = shop.agent_nodes[int(actor["id"])] as PersonView
		var guest: CustomerAgent = world.agent(int(actor["id"])) as CustomerAgent
		var raw_position: Vector3 = GridMath.cell_to_world(guest.seat_cell)
		if "seated_forward_offset" in definition:
			var offset: float = float(definition.get("seated_forward_offset"))
			assert_almost_eq(float(actor["forward_offset"]), offset)
			if not is_zero_approx(offset):
				assert_false(person.position.is_equal_approx(raw_position), "authored nonzero offset changes the actual native draw position")
				assert_almost_eq(person.position.distance_to(raw_position), absf(offset), 0.0001)
		var values: Array = actor["expected_position"]
		assert_true(person.position.is_equal_approx(Vector3(float(values[0]), float(values[1]), float(values[2]))))
	# A geometry correction may legitimately keep a zero authored offset. The
	# detached native bench tests exercise nonzero offsets without forcing data.
	# Move an actual native node without altering its arrived sim seat or frame.
	# Independent evidence must catch this even though its current pose is valid.
	var altered: PersonView = shop.agent_nodes[int(state["actors"][0]["id"])] as PersonView
	var saved_position: Vector3 = altered.position
	altered.position += Vector3(0.01, 0.0, 0.0)
	var moved: Dictionary = REVIEW.evidence(_main, _root(), 90)
	assert_false(moved["actors"][0]["position_matches"], "native position mutation cannot redefine the expected position")
	assert_false(REVIEW.valid(moved, 90, fixture))
	altered.position = saved_position
	assert_eq(_snapshot(), before, "position evidence and the restored visual do not mutate simulation state")
	for ticks: int in fixture["guest_ticks"]:
		assert_true(ticks > 0 and ticks <= REVIEW.WALK_BUDGET)
	for change: String in ["reservation", "role", "cell", "clip", "player", "lift", "source", "hidden", "furnishing", "link", "walls", "dining", "head_clearance"]:
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
			"head_clearance":
				broken["actors"][0]["seat_clearance"]["backrest_clearance"] = 0.019
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


func test_derivative_crop_preserves_each_source_pixel_in_exact_three_by_three_blocks() -> void:
	# Tiny colour grids are test inputs, never rendered or published proof art.
	var source: Image = Image.create(4, 3, false, Image.FORMAT_RGBA8)
	for y: int in range(3):
		for x: int in range(4):
			source.set_pixel(x, y, Color(float(x) / 3.0, float(y) / 2.0, 0.25, 1.0))
	var before: PackedByteArray = source.get_data().duplicate()
	var cropped: Image = REVIEW.seated_crop_image(source, Rect2i(1, 1, 2, 2))
	assert_not_null(cropped)
	if cropped == null:
		return
	assert_eq(cropped.get_size(), Vector2i(6, 6))
	for y: int in range(6):
		for x: int in range(6):
			assert_eq(cropped.get_pixel(x, y), source.get_pixel(1 + x / 3, 1 + y / 3), "exact source pixels, no smoothing or invented gap")
	assert_eq(source.get_data(), before, "derivation leaves the source image untouched")
	assert_null(REVIEW.seated_crop_image(source, Rect2i(-1, 0, 2, 2)))
	assert_null(REVIEW.seated_crop_image(source, Rect2i(3, 2, 2, 2)))
	assert_null(REVIEW.seated_crop_image(source, Rect2i(1, 1, 0, 2)))


func test_crop_selection_requires_current_posed_head_and_keeps_backrest_and_table_context() -> void:
	# Detached projection inputs test selection only; no synthetic metadata or
	# image produced here is acceptance evidence for a native scene.
	var state: Dictionary = _crop_selection_fixture()
	var before: Dictionary = state.duplicate(true)
	var selected: Dictionary = REVIEW.seated_crop_selection(state)
	assert_eq(selected.get("error"), "")
	assert_eq(selected.get("guest_id"), 9, "greatest head bottom-y chooses the nearest booth guest")
	assert_eq(selected.get("source_rect"), [88, 148, 214, 164], "full head, backrest and table with twelve source pixels of context")
	assert_eq(selected.get("measurement"), state["actors"][0]["seat_clearance"])
	assert_eq(state, before, "selection is a read-only metadata query")
	var tied: Dictionary = state.duplicate(true)
	tied["actors"][1]["seat_clearance"]["head_screen_bounds"]["y"] = 210.0
	assert_eq(REVIEW.seated_crop_selection(tied).get("guest_id"), 4, "equal bottom-y uses the smallest guest ID")
	for change: String in ["bind_pose", "small_gap", "inside_vertex", "crossing", "depth", "intrusion_part", "unsupported_hips", "wrong_cushion", "wrong_guest", "offscreen", "missing_table", "provenance", "metric", "no_backrest"]:
		var broken: Dictionary = state.duplicate(true)
		match change:
			"bind_pose":
				broken["actors"][0]["seat_clearance"].erase("head_screen_bounds")
				broken["actors"][0]["bounds"] = {"rect": [140, 190, 50, 80], "inside": true, "in_front": true}
			"small_gap":
				broken["actors"][0]["seat_clearance"]["backrest_clearance"] = 0.019
			"inside_vertex":
				broken["actors"][0]["seat_clearance"]["head_vertices_inside_count"] = 1
			"crossing":
				broken["actors"][0]["seat_clearance"]["head_seat_surface_crossings"] = 1
			"depth":
				broken["actors"][0]["seat_clearance"]["max_head_vertex_penetration"] = 0.001
			"intrusion_part":
				broken["actors"][0]["seat_clearance"]["intrusion_parts"] = ["Model/Tall back shell"]
			"unsupported_hips":
				broken["actors"][0]["seat_clearance"]["hips_supported"] = false
			"wrong_cushion":
				broken["actors"][0]["seat_clearance"]["hip_support_parts"][0] = "Model/Wood foot plinth"
			"wrong_guest":
				broken["actors"][0]["seat_clearance"]["guest_id"] = 4
			"offscreen":
				broken["actors"][0]["seat_clearance"]["head_screen_bounds"]["x"] = -1.0
			"missing_table":
				broken["items"].pop_back()
			"provenance":
				broken["actors"][0]["seat_clearance"]["measurement_provenance"] = "rest pose estimate"
			"metric":
				broken["actors"][0]["seat_clearance"]["clearance_metric"] = "minimum Euclidean seat-triangle to conservative posed-head AABB separation"
			"no_backrest":
				broken["actors"][0]["seat_clearance"]["backrest_status"] = "backless"
				broken["actors"][0]["seat_clearance"]["backrest_clearance"] = null
				broken["actors"][0]["seat_clearance"]["backrest_parts"] = []
		assert_false(String(REVIEW.seated_crop_selection(broken).get("error", "")).is_empty(), change + " fails closed")


func _crop_selection_fixture() -> Dictionary:
	var actors: Array[Dictionary] = []
	for row: Dictionary in [{"id": 9, "seat": 11, "x": 150.0, "y": 210.0}, {"id": 4, "seat": 12, "x": 400.0, "y": 120.0}]:
		actors.append({"id": row["id"], "furnishing": row["seat"], "furnishing_definition": "diner_booth",
			"table": 10, "linked_table": 10, "role": "customer", "seated": true, "visible": true,
			"clip": "sit", "player_clip": "sit", "reservation": row["id"],
			"seat_clearance": {"guest_id": row["id"], "furnishing_id": row["seat"], "table_item_id": 10,
				"head_world_bounds": {"min": [0.0, 0.0, 0.0], "max": [0.2, 0.2, 0.2]},
				"head_screen_bounds": {"x": row["x"], "y": row["y"], "width": 30.0, "height": 40.0},
				"backrest_clearance": 0.025, "backrest_status": "named_parts", "backrest_parts": ["Model/Tall back shell"],
				"measurement_complete": true, "head_vertices_inside_count": 0, "max_head_vertex_penetration": 0.0,
				"head_seat_surface_crossings": 0, "intrusion_parts": [], "hips_supported": true,
				"hip_support_parts": ["Model/Left seat cushion", "Model/Left seat cushion"],
				"hip_bone_positions": [[-0.1, 0.3, 0.0], [0.1, 0.3, 0.0]],
				"hip_support_points": [[-0.1, 0.264, 0.0], [0.1, 0.264, 0.0]],
				"head_vertices": 8, "measurement_provenance": REVIEW.POSED_HEAD_PROVENANCE,
				"clearance_metric": REVIEW.POSED_CLEARANCE_METRIC}})
	var items: Array[Dictionary] = []
	for row: Dictionary in [{"id": 11, "definition": "diner_booth", "rect": [100, 180, 140, 120]},
			{"id": 12, "definition": "diner_booth", "rect": [350, 100, 140, 120]},
			{"id": 10, "definition": "cross_table", "rect": [130, 160, 160, 60]}]:
		items.append({"id": row["id"], "definition": row["definition"],
			"prop": {"bounds": {"rect": row["rect"], "inside": true, "in_front": true}}})
	return {"actors": actors, "items": items}


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
