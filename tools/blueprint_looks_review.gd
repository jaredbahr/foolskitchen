extends "res://src/world/main.gd"
## Explicit unsaved layout fixture, not an earned or paid four-booth run.
## Source booths and four supporting tables are free preplaced authored items;
## owner level 3 is staged. Starting cash and the normal morning stock order
## stay real. Starter table sales and the $210 stamp use Main's edit commands.
## tools/screenshot.sh --scene=res://tools/blueprint_looks_review.tscn
## --speed=0 --frames=12,60 captures the rotated ghost, then the paid stamp.

const REVIEW_SCENE: String = "res://tools/blueprint_looks_review.tscn"
const SOURCE_CELLS: Array[Vector2i] = [Vector2i(2, 7), Vector2i(5, 7)]
const LOOKS: Array[StringName] = [&"booth_white", &"booth_walnut"]
const TARGET: Vector2i = Vector2i(10, 5)
## Keep the complete native booth bounds clear of HUD, instructions, catalogue
## and the fixture notice. Derived from the v2 native projected AABBs.
const REVIEW_FOCUS: Vector2 = Vector2(2.65, 4.24)
const REVIEW_ZOOM: float = 7.1
const WORLD_SAFE_RECT: Rect2 = Rect2(620, 210, 920, 570)
const RESERVED_UI: Array[NodePath] = [^"HUD/Top", ^"HUD/BuildHints",
	^"Overlay/BuildCatalogue/Panel", ^"DinerReviewNotice/Panel"]
const SUPPORTS: Array[Dictionary] = [
	{"cell": Vector2i(2, 6), "turns": 0}, {"cell": Vector2i(5, 6), "turns": 0},
	{"cell": Vector2i(12, 5), "turns": 1}, {"cell": Vector2i(12, 8), "turns": 1},
]
const NOTICE: String = "Unsaved review: free source booths + table supports; level 3 staged; no cash grant."

var _review_fixture: Dictionary = {}
var _review_sources: Array[int] = []
var _review_stamp_ids: Array[int] = []
var _review_blueprint: Blueprint
var _review_history_before: int = 0
var _review_cash_before: int = 0
var _review_ledger_before: int = 0
var _review_capture_frame: int = 0
var _review_captured: Array[int] = []
var _review_failed: bool = false


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	if world == null or world.now != 0 or world.clock.phase != SimClock.Phase.MORNING \
			or TUNING.starting_cash != 300 or not _review_options_valid():
		_review_fail("needs fresh seed-1 Main with paused frames 12,60")
		return
	var morning_ledger: Array[Dictionary] = Economy.ledger.entries_for_day(1)
	var morning_spending: int = 0
	for row: Dictionary in morning_ledger:
		if row["category"] != Ledger.INGREDIENTS or int(row["amount"]) > 0:
			_review_fail("unexpected cash movement before the fixture")
			return
		morning_spending -= int(row["amount"])
	if Economy.cash != 300 - morning_spending:
		_review_fail("starting cash does not reconcile with the real morning order")
		return
	_review_fixture = {"kind": "explicit_unsaved_free_source_layout", "notice": NOTICE,
		"starting_cash": TUNING.starting_cash, "morning_stock_spending": morning_spending,
		"morning_ledger": morning_ledger, "cash_after_morning_stock": Economy.cash,
		"cash_grant": 0, "owner_level_fixture": 3, "source_items_bought": false,
		"free_source_looks": ["booth_white", "booth_walnut"],
		"free_support_definition": "cross_table", "free_support_count": SUPPORTS.size(),
		"ghost_overlay": "unchanged standard green validity tint masks variant RGB; controller retains selected look"}
	var owner: Dictionary = owner_progress.to_dict()
	owner["total_xp"] = owner_progress.threshold_for(3)
	owner["level"] = 3
	if not owner_progress.from_dict(owner):
		_review_fail("level fixture was refused")
		return
	shop_editor.set_owner_level(3)
	menu_settings.set_owner_level(3)
	_build_catalogue.set_owner_level(3)
	$HUD.set_owner_progress(3, owner_progress.xp_into_level(), owner_progress.xp_in_level())
	var sale_receipts: Array[Dictionary] = []
	var sale_total: int = 0
	for table: PlacedItem in ShopBuilder.items_with_def(world, &"table_2"):
		var refund: int = shop_sell(table.id)
		if refund < 0:
			_review_fail("starter table sale was refused")
			return
		sale_total += refund
		sale_receipts.append({"item_id": table.id, "definition": "table_2", "refund": refund})
	var plant: PlacedItem = ShopBuilder.items_with_def(world, &"potted_plant")[0]
	if not shop_move(plant.id, Vector2i(1, 9), 0):
		_review_fail("could not clear the support-table position")
		return
	# These are declared free layout items, just as authored starting furniture
	# is preplaced. No zero-price edit, grant or offsetting ledger entry is used.
	for support: Dictionary in SUPPORTS:
		if world.grid.place_def(content.item(&"cross_table"), support["cell"], support["turns"]) == null:
			_review_fail("free supporting table does not fit")
			return
	for index: int in range(LOOKS.size()):
		var source: PlacedItem = world.grid.place_def(content.item(&"diner_booth"), SOURCE_CELLS[index], 0, LOOKS[index])
		if source == null:
			_review_fail("free source booth does not fit")
			return
		_review_sources.append(source.id)
	_review_fixture.merge({"starter_table_sales": sale_receipts, "sale_receipts_total": sale_total,
		"cash_after_layout": Economy.cash, "source_ids": _review_sources.duplicate()})
	if Economy.cash != 300 - morning_spending + sale_total or not set_build_active(true):
		_review_fail("free source layout changed cash or Build was refused")
		return
	_build_catalogue.set_category(BuildCatalogue.BLUEPRINTS)
	_build_catalogue.blueprint_select.pressed.emit()
	if not build_mode.blueprint_press(SOURCE_CELLS[0]) \
			or not build_mode.blueprint_release(SOURCE_CELLS[1] + Vector2i.ONE) \
			or build_mode.blueprint_selection != _review_sources:
		_review_fail("could not select exactly the two source booths")
		return
	_build_catalogue.blueprint_name.text = "White + Walnut"
	_build_catalogue.blueprint_save.pressed.emit()
	if blueprint_library.blueprints.size() != 1:
		_review_fail("could not capture the source pair")
		return
	# Exercise the real versioned in-memory save decoder without writing a save.
	var saved: Dictionary = blueprint_library.to_dict()
	var notes: Array[String] = []
	if not blueprint_library.restore(saved, content, notes) or not notes.is_empty() \
			or blueprint_library.to_dict() != saved:
		_review_fail("blueprint library did not round trip")
		return
	_review_blueprint = blueprint_library.blueprints[0]
	if _review_blueprint.entries.size() != 2:
		_review_fail("capture included something other than the two booths")
		return
	for index: int in range(LOOKS.size()):
		if _review_blueprint.entries[index].variant_id != LOOKS[index]:
			_review_fail("capture lost a furniture look")
			return
	_review_fixture["library"] = saved
	_build_catalogue.blueprint_buttons[0].pressed.emit()
	build_mode.update_origin(TARGET)
	if not build_mode.rotate(1) or not build_mode.current_check.ok \
			or build_mode.blueprint_cost() != 210:
		_review_fail("rotated pair preview refused: " + build_mode.current_check.why)
		return
	_review_history_before = edit_history.undo_count()
	_review_cash_before = Economy.cash
	_review_ledger_before = Economy.ledger.entries_for_day(1).size()
	_review_fixture.merge({"stamp_cost": build_mode.blueprint_cost(), "cash_before_stamp": _review_cash_before,
		"history_before_stamp": _review_history_before, "ledger_before_stamp": _review_ledger_before})
	DinerReview._notice(self, "White + Walnut: original pair and quarter-turned blueprint preview ($210).\n" + NOTICE)
	var rig: CameraRig = $CameraRig as CameraRig
	rig.minimum_zoom = 2.0
	rig.initial_focus = REVIEW_FOCUS
	rig.initial_zoom = REVIEW_ZOOM
	rig.reset_view()
	rig.set_process(false)
	($ShopView as ShopView).set_wall_mode(ShopView.WallMode.CUTAWAY)


func _process(_delta: float) -> void:
	if _review_failed or _review_blueprint == null:
		return
	# The screenshot MainLoop runs before nodes. Keep its requested ghost origin
	# stable without the desktop mouse changing the checked production preview.
	var harness: SceneTree = get_tree()
	var frame: int = int(harness.get("_frames"))
	if frame == 30:
		if not build_mode.commit():
			_review_fail("actual stamp was refused: " + shop_editor.last_check.why)
			return
		_review_stamp_ids = shop_editor.last_stamp_ids.duplicate()
		DinerReview._notice(self, "White + Walnut: paid rotated copy; $210 charged; one undo step.\n" + NOTICE)
	if build_mode.state == BuildMode.State.BLUEPRINT:
		build_mode.update_origin(TARGET)
	if bool(harness.get("_capture_pending")) and int(harness.get("_capture_frame")) == frame \
			and not RenderingServer.frame_post_draw.is_connected(_review_after_capture):
		_review_capture_frame = frame
		# Registered after the harness's callback: it has written the PNG and its
		# JSON before this read-only evidence callback runs for the same draw.
		RenderingServer.frame_post_draw.connect(_review_after_capture, CONNECT_ONE_SHOT)
	refresh_presentation()


func _review_after_capture() -> void:
	var frame: int = _review_capture_frame
	var state: Dictionary = _review_state(frame)
	if not _review_valid(state, frame):
		_review_fail("native captured state is inconsistent: " + JSON.stringify(state))
		return
	var directory: String = String(get_tree().get("_out"))
	var png: String = directory.path_join("shot_%04d.png" % frame)
	var metadata_path: String = png.get_basename() + ".json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not parsed is Dictionary:
		_review_fail("missing harness metadata")
		return
	var metadata: Dictionary = parsed
	if metadata.get("image_sha256") != FileAccess.get_sha256(png) \
			or metadata.get("image_file") != png.get_file() or metadata.get("frame") != frame \
			or metadata.get("scene") != REVIEW_SCENE or metadata.get("capture_timing") != "frame_post_draw" \
			or metadata.get("engine_errors") != 0 or metadata.get("world_tick") != 0 \
			or metadata.get("day_phase") != SimClock.Phase.MORNING \
			or metadata.get("width") != 1600 or metadata.get("height") != 900:
		_review_fail("PNG identity, actual clock or engine-error guard failed")
		return
	metadata["blueprint_looks"] = {"fixture": _review_fixture, "state": state, "validated": true}
	var file: FileAccess = FileAccess.open(metadata_path, FileAccess.WRITE)
	if file == null:
		_review_fail("cannot enrich capture metadata")
		return
	file.store_string(JSON.stringify(metadata, "\t"))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		_review_fail("cannot save enriched capture metadata")
		return
	_review_captured.append(frame)
	if frame == 60 and _review_captured != [12, 60]:
		_review_fail("the requested two captures did not both validate")
		return
	print("BLUEPRINT_LOOKS_REVIEW ", JSON.stringify({"frame": frame, "image_sha256": metadata["image_sha256"],
		"cash": state["cash"], "stamp_cost": _review_fixture["stamp_cost"], "validated": true}))


func _review_state(frame: int) -> Dictionary:
	var sources: Array[Dictionary] = []
	var stamped: Array[Dictionary] = []
	var ghosts: Array[Dictionary] = []
	var shop: ShopView = $ShopView as ShopView
	for id: int in _review_sources:
		sources.append(_review_item(world.grid.item(id), shop.item_nodes.get(id) as ItemVisual))
	for id: int in _review_stamp_ids:
		stamped.append(_review_item(world.grid.item(id), shop.item_nodes.get(id) as ItemVisual))
	for ghost: ItemVisual in _build_preview.blueprint_ghosts:
		ghosts.append(_review_visual(ghost))
	return {"frame": frame, "phase": int(world.clock.phase), "world_tick": world.now,
		"use_saves": use_saves, "owner_level": owner_progress.level, "cash": Economy.cash,
		"source_items": sources, "stamped_items": stamped, "ghosts": ghosts,
		"mode": int(build_mode.state), "check_ok": build_mode.current_check.ok,
		"history_steps": edit_history.undo_count(), "redo_steps": edit_history.redo_count(),
		"undo_label": edit_history.undo_label(), "ledger": Economy.ledger.entries_for_day(1),
		"library": blueprint_library.to_dict(), "reserved_ui": _review_reserved_ui(),
		"world_safe_rect": [WORLD_SAFE_RECT.position.x, WORLD_SAFE_RECT.position.y,
			WORLD_SAFE_RECT.size.x, WORLD_SAFE_RECT.size.y],
		"camera": {"focus": [($CameraRig as CameraRig).position.x, ($CameraRig as CameraRig).position.z],
			"orthographic_size": ($CameraRig/Camera3D as Camera3D).size}}


func _review_item(item: PlacedItem, visual: ItemVisual) -> Dictionary:
	if item == null:
		return {}
	var result: Dictionary = _review_visual(visual)
	result.merge({"id": item.id, "definition": String((item.def as ItemDef).id),
		"variant_id": String(item.variant_id), "origin": [item.origin.x, item.origin.y],
		"turns": item.quarter_turns, "authored_price": (item.def as ItemDef).variant_price(item.variant_id)})
	return result


func _review_visual(visual: ItemVisual) -> Dictionary:
	if visual == null or visual.prop == null:
		return {}
	var surfaces: Array[Dictionary] = []
	for mesh: MeshInstance3D in visual.rendered_meshes():
		for index: int in range(mesh.mesh.get_surface_count()):
			var imported: Material = mesh.mesh.surface_get_material(index)
			var active: BaseMaterial3D = mesh.get_active_material(index) as BaseMaterial3D
			if imported != null and active != null:
				var colour: Color = active.albedo_color
				surfaces.append({"mesh": String(visual.get_path_to(mesh)), "surface": index,
					"imported_material": imported.resource_name, "colour": [colour.r, colour.g, colour.b, colour.a]})
	return {"visible": visual.is_visible_in_tree(), "wrapper": visual.prop.scene_file_path,
		"position": [visual.position.x, visual.position.y, visual.position.z],
		"yaw_degrees": rad_to_deg(visual.rotation.y),
		"native_variant_id": String(visual.prop._variant.id) if visual.prop._variant != null else "",
		"look_controller_bound": visual.prop._variant_materials != null,
		"look_material_recipe": visual.prop._variant.material_colours.duplicate()
			if visual.prop._variant != null else {},
		"ghost_valid": visual.get_meta("valid", false), "surfaces": surfaces,
		"bounds": DinerReview._screen_bounds(visual.global_transform * visual.get_aabb(),
			$CameraRig/Camera3D as Camera3D)}


func _review_valid(state: Dictionary, frame: int) -> bool:
	if frame not in [12, 60] or state["phase"] != SimClock.Phase.MORNING or state["world_tick"] != 0 \
			or state["use_saves"] or state["owner_level"] != 3 or state["redo_steps"] != 0 \
			or state["library"] != _review_fixture["library"] \
			or state["camera"]["focus"] != [REVIEW_FOCUS.x, REVIEW_FOCUS.y] \
			or not is_equal_approx(float(state["camera"]["orthographic_size"]), REVIEW_ZOOM):
		return false
	var sources: Array = state["source_items"]
	var reserved: Array = state["reserved_ui"]
	if reserved.size() != RESERVED_UI.size() or not _review_pair_valid(sources, 0, reserved):
		return false
	var all_ledger: Array = state["ledger"]
	var reconciled_cash: int = int(_review_fixture["starting_cash"])
	for entry: Dictionary in all_ledger:
		if entry["category"] not in [Ledger.INGREDIENTS, Ledger.UPGRADES]:
			return false
		reconciled_cash += int(entry["amount"])
	if state["cash"] != reconciled_cash:
		return false
	if frame == 12:
		var ghosts: Array = state["ghosts"]
		if state["mode"] != BuildMode.State.BLUEPRINT or not state["check_ok"] \
				or state["cash"] != _review_cash_before or state["history_steps"] != _review_history_before \
				or not state["stamped_items"].is_empty() or ghosts.size() != 2 \
				or all_ledger.size() != _review_ledger_before:
			return false
		for index: int in range(LOOKS.size()):
			var expected_transform: Transform3D = ItemVisual.placed_transform(content.item(&"diner_booth"),
				TARGET + Vector2i(0, index * 3), 1)
			if ghosts[index].get("native_variant_id") != String(LOOKS[index]) \
					or not ghosts[index].get("look_controller_bound", false) \
					or not ghosts[index].get("visible", false) or not ghosts[index].get("ghost_valid", false) \
					or ghosts[index].get("position") != [expected_transform.origin.x, expected_transform.origin.y, expected_transform.origin.z] \
					or not is_equal_approx(float(ghosts[index].get("yaw_degrees", 0.0)), -90.0) \
					or not _review_unoccluded(ghosts[index].get("bounds", {}), reserved) \
					or not _review_material_valid(ghosts[index], index, true):
				return false
		return true
	var ledger: Array = state["ledger"]
	if state["mode"] != BuildMode.State.IDLE or state["cash"] != _review_cash_before - 210 \
			or state["history_steps"] != _review_history_before + 1 or not state["ghosts"].is_empty() \
			or not _review_pair_valid(state["stamped_items"], 1, reserved) or ledger.size() != _review_ledger_before + 2:
		return false
	for index: int in range(2):
		var entry: Dictionary = ledger[_review_ledger_before + index]
		if int(entry["amount"]) != -105 or entry["category"] != Ledger.UPGRADES:
			return false
	return true


func _review_pair_valid(pair: Array, turns: int, reserved: Array) -> bool:
	if pair.size() != 2:
		return false
	for index: int in range(LOOKS.size()):
		var item: Dictionary = pair[index]
		var expected_origin: Vector2i = SOURCE_CELLS[index] if turns == 0 else TARGET + Vector2i(0, index * 3)
		if item.get("definition") != "diner_booth" or item.get("variant_id") != String(LOOKS[index]) \
				or item.get("origin") != [expected_origin.x, expected_origin.y] \
				or item.get("native_variant_id") != String(LOOKS[index]) or item.get("turns") != turns \
				or not item.get("look_controller_bound", false) \
				or item.get("authored_price") != 105 or not item.get("visible", false) \
				or not _review_unoccluded(item.get("bounds", {}), reserved) \
				or not _review_material_valid(item, index, false):
			return false
	return true


func _review_reserved_ui() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for path: NodePath in RESERVED_UI:
		var control: Control = get_node_or_null(path) as Control
		if control == null or not control.is_visible_in_tree():
			return []
		var rect: Rect2 = control.get_global_rect()
		if not rect.has_area():
			return []
		result.append({"path": String(path), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	return result


func _review_unoccluded(bounds: Dictionary, reserved: Array) -> bool:
	if not DinerReview._bounds_valid(bounds):
		return false
	var values: Array = bounds["rect"]
	var rect: Rect2 = Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	if not WORLD_SAFE_RECT.encloses(rect):
		return false
	for control: Dictionary in reserved:
		var ui: Array = control["rect"]
		if rect.intersects(Rect2(float(ui[0]), float(ui[1]), float(ui[2]), float(ui[3]))):
			return false
	return true


func _review_material_valid(visual: Dictionary, index: int, ghost: bool) -> bool:
	if visual.get("look_material_recipe") != content.item(&"diner_booth").variant(LOOKS[index]).material_colours:
		return false
	var palette: Dictionary[StringName, Color] = KitMaterialColours.colours()
	var expected: Color = palette[&"carpetWhite" if index == 0 else &"woodDark"]
	if ghost:
		# The existing validity overlay replaces RGB on all surfaces, just as
		# normal Buy ghosts do. Look identity is checked on the real controller;
		# the original and committed pairs prove the distinct rendered finishes.
		expected = content.item(&"diner_booth").placeholder_color.lerp(BuildPreview.VALID_COLOR, 0.8)
		expected.a = BuildPreview.VALID_ALPHA
	var found: bool = false
	for surface: Dictionary in visual.get("surfaces", []):
		if surface["imported_material"] != "carpetWhite":
			continue
		found = true
		var colour: Array = surface["colour"]
		if not Color(float(colour[0]), float(colour[1]), float(colour[2]), float(colour[3])).is_equal_approx(expected):
			return false
	return found


func _review_options_valid() -> bool:
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=12,60":
			frames += 1
		elif argument == "--scene=" + REVIEW_SCENE:
			scenes += 1
		elif not argument.begins_with("--out="):
			return false
	return speeds == 1 and frames == 1 and scenes == 1


func _review_fail(reason: String) -> void:
	_review_failed = true
	push_error("Blueprint looks review: " + reason)
	get_tree().quit(1)


func _exit_tree() -> void:
	if not _review_failed and _review_captured != [12, 60]:
		_review_fail("exited without both validated native images")
	super._exit_tree()
