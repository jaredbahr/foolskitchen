extends "res://src/world/main.gd"
## Explicit unsaved frontage/Build presentation, not ordinary play or a probe.
## Free construction and editor-only unlocks are declared separately from costs.

const FRONT_REVIEW: Script = preload("res://tools/street_front_review.gd")
const REVIEW_SCENE: String = "res://tools/curb_appeal_review.tscn"

var _review_ready: bool = false
var _review_frames: int = 0
var _review_out: String = ""
var _review_construction: Dictionary = {}
var _review_state: Dictionary = {}


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_review_out = argument.trim_prefix("--out=")
	if _review_out.is_empty() or FileAccess.file_exists(_review_out.path_join("shot_0060.png")) \
			or FileAccess.file_exists(_review_out.path_join("shot_0060.json")):
		_review_fail("a fresh capture output is required")
		return
	super._ready()
	Clock.set_speed(0)
	var cash_before: int = Economy.cash
	var progression_before: Dictionary = owner_progress.to_dict()
	if not ProbeSetups.apply("curb_appeal", self) or Economy.cash != cash_before \
			or owner_progress.to_dict() != progression_before:
		_review_fail("the declared free frontage setup changed cash or progression")
		return
	_review_construction = ProbeSetups.curb_appeal_construction(self)
	if not String(_review_construction.get("error", "missing cost declaration")).is_empty():
		_review_fail("the authored construction costs are unavailable")
		return
	# Existing person and entry only: a declared presentation pose, never used
	# by the named service probe and never a new customer, task or RNG draw.
	var owner: OwnerAgent = sim.owner_agent()
	if owner == null or world.grid.entries().is_empty():
		_review_fail("the real owner or street entry is missing")
		return
	owner.cell = world.grid.entries()[-1]
	owner.path.clear()
	owner.move_progress = 0.0
	if not set_build_active(true):
		_review_fail("the normal Build catalogue did not open")
		return
	_review_state = _review_snapshot()
	_review_ready = true


func _process(delta: float) -> void:
	# Retain Main's actual camera-facing visibility refresh. It must be pure.
	super._process(delta)
	if not _review_ready:
		return
	_review_frames += 1
	if _review_state != _review_snapshot() or use_saves:
		_review_fail("presentation changed the real morning, countdown, RNG or shop")
		return
	if _review_frames == 10:
		FRONT_REVIEW.focus(self)
		var camera: Camera3D = get_node("CameraRig/Camera3D") as Camera3D
		camera.size = 6.5
		# Leave the front above the real bottom-left Build panel. This changes
		# only the camera pose, after screenshot.gd has settled its initial rig.
		camera.global_position -= camera.global_basis.y
	elif _review_frames >= 25:
		RenderingServer.frame_post_draw.connect(_review_validate, CONNECT_ONE_SHOT)


func _review_validate() -> void:
	if not _review_ready:
		return
	var meter: CurbAppealMeter = _build_catalogue.curb_appeal_meter
	var state: Dictionary = meter.view_state()
	var front: Dictionary = FRONT_REVIEW.evidence(self, get_tree().root)
	var panel: Control = _build_catalogue.get_node("Panel") as Control
	var scroll: ScrollContainer = _build_catalogue.get_node("Panel/Margin/Rows/Scroll") as ScrollContainer
	var viewport: Rect2 = get_viewport().get_visible_rect()
	if not is_build_active() or not meter.is_visible_in_tree() or state.get("available") != true \
			or not is_finite(curb_appeal_score) or curb_appeal_score <= 0.0 or curb_appeal_score > 100.0 \
			or curb_appeal_factor <= 1.0 or curb_appeal_factor > 1.100001 \
			or state.get("value") != curb_appeal_score or state.get("multiplier") != curb_appeal_factor \
			or meter.score_bar.value != curb_appeal_score \
			or meter.caption_label.text != CurbAppealText.caption(curb_appeal_score) \
			or meter.bonus_label.text != CurbAppealText.bonus(curb_appeal_factor):
		_review_fail("the real street-facing meter does not show the derived score and factor")
		return
	for control: Control in [meter, meter.caption_label, meter.bonus_label, meter.score_bar]:
		if not control.is_visible_in_tree() or not viewport.encloses(control.get_global_rect()) \
				or not panel.get_global_rect().grow(1.0).encloses(control.get_global_rect()) \
				or not scroll.get_global_rect().grow(1.0).encloses(control.get_global_rect()):
			_review_fail("the native curb meter or labels are clipped")
			return
	for label: Label in [meter.caption_label, meter.bonus_label]:
		var font: Font = label.get_theme_font("font")
		var text_width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size("font_size")).x
		if text_width > label.size.x + 1.0:
			_review_fail("the actual meter wording is clipped")
			return
	if front.get("all_visible") != true or front.get("stored_items") != 5 \
			or front.get("outside_finishes") != 4 or front.get("inside_decor_vibe_empty") != true \
			or front.get("purchased_sign_visible") != true \
			or front.get("purchased_sign_text") != menu_settings.restaurant_name() \
			or float(front.get("owner_height_pixels", 0.0)) < 60.0 \
			or front.get("wall_mode") != ShopView.WallMode.UP or not _review_front_unobscured(panel):
		_review_fail("the supported decorated front, real sign or person is hidden by Build")
		return
	if _review_state != _review_snapshot() or use_saves:
		_review_fail("native validation changed the RNG, arrival countdown or shop")
		return
	var png: String = _review_out.path_join("shot_0060.png")
	if not FileAccess.file_exists(png):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(png.get_basename() + ".json"))
	if not parsed is Dictionary:
		_review_fail("the actual screenshot sidecar is missing")
		return
	var metadata: Dictionary = parsed
	var image_hash: String = FileAccess.get_sha256(png)
	if metadata.get("scene") != REVIEW_SCENE or metadata.get("frame") != 60 \
			or metadata.get("image_file") != "shot_0060.png" or metadata.get("image_sha256") != image_hash \
			or image_hash.length() != 64 or metadata.get("capture_timing") != "frame_post_draw" \
			or metadata.get("width") != 1600 or metadata.get("height") != 900 \
			or metadata.get("engine_errors") != 0 or metadata.get("master_seed") != "1" \
			or metadata.get("world_tick") != world.now or _review_state != _review_snapshot():
		_review_fail("the actual saved PNG differs from this unchanged staged morning")
		return
	var source_hashes: Dictionary = {}
	for path: String in ["tools/curb_appeal_review.gd", "tools/probe_setups.gd", "tools/street_front_review.gd",
			"src/world/main.gd", "src/ui/curb_appeal_meter.gd", "src/ui/curb_appeal_text.gd",
			"data/balance/curb_appeal.tres", "tools/screenshot.gd"]:
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
	print("CURB_APPEAL_REVIEW ", JSON.stringify({"scene": REVIEW_SCENE,
		"fixture": "Unsaved seed1 morning; free front construction with temporary editor-only level4; no cash or progression grant; real owner posed at existing entry; street-facing camera and normal Build",
		"ordinary_play_or_probe_result": false, "construction": _review_construction,
		"seed": str(GameState.master_seed), "day": Clock.sim.day, "phase": int(Clock.sim.phase),
		"world_tick": world.now, "score": curb_appeal_score, "multiplier": curb_appeal_factor,
		"meter": {"caption": meter.caption_label.text, "bonus": meter.bonus_label.text,
			"value": meter.score_bar.value, "tooltip": meter.tooltip_text},
		"meter_rect": _review_rect(meter), "caption_rect": _review_rect(meter.caption_label),
		"bonus_rect": _review_rect(meter.bonus_label), "bar_rect": _review_rect(meter.score_bar),
		"catalogue_rect": _review_rect(panel), "scroll_rect": _review_rect(scroll),
		"front": front, "snapshot": _review_state, "unchanged": true,
		"player_meaning": "A decorated street front contributes a small walk-in multiplier through the existing demand breakdown. Actual arrivals vary; construction cost is not part of this service comparison.",
		"frame": 60, "validation_timing": "frame_post_draw", "image_file": "shot_0060.png",
		"image_sha256": image_hash, "image_metadata_sha256": FileAccess.get_sha256(png.get_basename() + ".json"),
		"source_files_sha256": source_hashes}))
	_review_ready = false


func _review_snapshot() -> Dictionary:
	var result: Dictionary = BalanceProbe._control_snapshot(self, sim)
	result["shop"] = shop_editor.to_dict()
	result["arrival_countdown"] = sim.spawner.get("_remaining")
	result["curb_score"] = curb_appeal_score
	result["curb_factor"] = curb_appeal_factor
	result["owner_cell"] = [sim.owner_agent().cell.x, sim.owner_agent().cell.y]
	return result


func _review_front_unobscured(panel: Control) -> bool:
	var camera: Camera3D = get_node("CameraRig/Camera3D") as Camera3D
	var view: ShopView = get_node("ShopView") as ShopView
	for piece: Dictionary in FRONT_REVIEW._pieces(world.grid):
		var visual: ItemVisual = view.wall_finish_view.item_nodes.get(piece["anchor"]) as ItemVisual
		if visual == null:
			return false
		var bounds: AABB = visual.global_transform * visual.get_aabb()
		for index: int in range(8):
			var point: Vector3 = bounds.position + Vector3(bounds.size.x if (index & 1) != 0 else 0.0,
				bounds.size.y if (index & 2) != 0 else 0.0, bounds.size.z if (index & 4) != 0 else 0.0)
			if panel.get_global_rect().has_point(camera.unproject_position(point)):
				return false
	return true


func _review_rect(control: Control) -> Array[float]:
	var rect: Rect2 = control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _review_fail(reason: String) -> void:
	_review_ready = false
	push_error("Curb appeal review: " + reason)
