extends SceneTree
## Renders the main scene and saves PNG screenshots, for reviews and PRs.
## Run through tools/screenshot.sh (it provides a virtual display).
## User args (after --): --out=<dir> --frames=120,400,900 --speed=4 --scene=res://...
## Optional --quarter=0..3 selects an exact cutaway camera quarter for review.
##   --open      press "Open shop" at the start
##   --fast=N    also run N extra sim ticks per frame (via the scene's run_ticks)
##   --select=guest|owner  inspect a live agent through the scene's selection API
##   --assign-owner=kitchen  use the normal selected-owner command (requires --open)
##   --f3        show the scene's read-only debug overlay
##   --menu      show the real menu panel in MORNING (cannot combine with --open)
##   --staff     show the real morning Staff panel, paused, with no altered roster
##   --report    require a closed-day report with at least two real review cards
##   --build=green|red  hold a checked buy preview through the production input API
##   --paint     show a painted morning shop using the production paint controls
## Metadata records actual waiting moods/visible markers and seeds, with no fixture.

const MAX_CAPTURE_WAIT_FRAMES: int = 8
const MAX_OWNER_WARMUP_TICKS: int = 900

var _frames: int = 0
var _shots: Array[int] = [120, 400, 900]
var _out: String = "screens"
var _speed: int = 4
var _quarter: int = -1
var _main: Node
var _scene_path: String = "res://src/world/main.tscn"
var _failed: bool = false
var _finished: bool = false
var _errors: ErrorCounter = ErrorCounter.new()
var _open: bool = false
var _fast: int = 0
var _selection: StringName = &""
var _assign_owner: bool = false
var _owner_warmup_ticks: int = 0
var _f3: bool = false
var _menu: bool = false
var _staff: bool = false
var _report_requested: bool = false
var _build: String = ""
var _paint: bool = false
var _build_pointer: Vector2 = Vector2.ZERO
var _selected_agent_id: int = -1
var _capture_pending: bool = false
var _capture_frame: int = 0
var _capture_wait_frames: int = 0
var _finish_requested: bool = false


func _initialize() -> void:
	OS.add_logger(_errors)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--speed="):
			_speed = int(arg.trim_prefix("--speed="))
		elif arg == "--open":
			_open = true
		elif arg.begins_with("--fast="):
			_fast = int(arg.trim_prefix("--fast="))
		elif arg.begins_with("--select"):
			if arg not in ["--select=guest", "--select=owner"]:
				_fail_capture("--select only supports guest or owner")
				return
			_selection = StringName(arg.trim_prefix("--select="))
		elif arg.begins_with("--assign-owner"):
			if arg != "--assign-owner=kitchen":
				_fail_capture("--assign-owner only supports kitchen")
				return
			_assign_owner = true
		elif arg.begins_with("--f3"):
			if arg != "--f3":
				_fail_capture("--f3 does not accept a value")
				return
			_f3 = true
		elif arg.begins_with("--menu"):
			if arg != "--menu":
				_fail_capture("--menu does not accept a value")
				return
			_menu = true
		elif arg.begins_with("--staff"):
			if arg != "--staff":
				_fail_capture("--staff does not accept a value")
				return
			_staff = true
		elif arg == "--report":
			_report_requested = true
		elif arg.begins_with("--build"):
			var requested: String = arg.trim_prefix("--build=")
			if not ["green", "red"].has(requested):
				_fail_capture("--build supports green or red")
				return
			_build = requested
		elif arg == "--paint":
			_paint = true
		elif arg.begins_with("--scene="):
			_scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--quarter="):
			var requested: String = arg.trim_prefix("--quarter=")
			if not ["0", "1", "2", "3"].has(requested):
				_fail_capture("--quarter must be 0, 1, 2 or 3")
				return
			_quarter = int(requested)
		elif arg.begins_with("--frames="):
			_shots.clear()
			for f in arg.trim_prefix("--frames=").split(","):
				_shots.append(int(f))
	if _assign_owner and (_selection != &"owner" or not _open):
		_fail_capture("--assign-owner=kitchen requires --select=owner and --open")
		return
	if not _build.is_empty() and (_open or _fast != 0 or not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff):
		_fail_capture("--build requires a fresh morning without other view/service flags")
		return
	if _paint and (_open or _fast != 0 or not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff or not _build.is_empty() or _speed != 0):
		_fail_capture("--paint requires a paused morning without other view/service flags")
		return
	if _menu and (_open or not _selection.is_empty()):
		_fail_capture("--menu requires morning and cannot combine with --open or --select")
		return
	if _staff and (_open or _fast != 0 or not _selection.is_empty() or _assign_owner or _f3 or _menu or _speed != 0):
		_fail_capture("--staff requires a paused morning without other service/panel options")
		return
	if _report_requested and (not _open or _fast <= 0 or _speed != 0 or _menu or _staff or not _build.is_empty()):
		_fail_capture("--report requires a fast-forwarded, paused-clock service view")
		return
	if _shots.is_empty() or _shots.min() < 1 or ((_quarter >= 0 or not _selection.is_empty() or _f3 or _menu or _staff or not _build.is_empty() or _paint) and _shots.min() < 4):
		_fail_capture("capture frames must be positive, and at least 4 for requested view/UI options")
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail_capture("cannot create output directory")
		return
	var scene: PackedScene = load(_scene_path)
	if scene == null:
		_fail_capture("cannot load scene: " + _scene_path)
		return
	_main = scene.instantiate()
	# Preserve capture isolation when the integrated game session supports saves.
	if "use_saves" in _main:
		_main.set("use_saves", false)
	if _report_requested and "new_game_seed_override" in _main:
		_main.set("new_game_seed_override", 1)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _finished:
		return true
	if _capture_pending:
		# A disabled/non-drawing viewport must fail instead of waiting forever.
		_capture_wait_frames += 1
		if _capture_wait_frames > MAX_CAPTURE_WAIT_FRAMES:
			_fail_capture("viewport did not finish drawing the pending capture")
		return _finished
	_frames += 1
	if _frames == 3:
		# Autoloads aren't compile-time identifiers in a --script main loop.
		var clock: Node = root.get_node("Clock")
		if _open:
			(clock.get("sim") as SimClock).start_service()
		clock.call("set_speed", _speed)
		_configure_camera()
		if _failed:
			return true
		_configure_inspection()
		if _failed:
			return true
		if _menu:
			if not _main.has_method("set_menu_visible") or not _main.has_method("is_menu_visible") or not bool(_main.call("set_menu_visible", true)):
				_fail_capture("--menu requires the scene's morning menu APIs")
				return true
		if _staff:
			if not _main.has_method("set_staff_visible") or not bool(_main.call("set_staff_visible", true)):
				_fail_capture("--staff requires the scene's morning staff API")
				return true
		if not _build.is_empty():
			_configure_build()
			if _failed:
				return true
		if _paint:
			_configure_paint()
			if _failed:
				return true
	if not _build.is_empty() and _frames >= 3:
		_hold_build_pointer()
	if _fast > 0 and _frames > 3 and _main.has_method("run_ticks"):
		_main.call("run_ticks", _fast)
	if not _selection.is_empty() and _frames >= 3:
		_select_live_agent()
		if _failed:
			return true
	_finish_requested = _frames >= _shots.max()
	if _shots.has(_frames):
		if _assign_owner:
			_prepare_owner_capture()
			if _failed:
				return true
		_queue_capture()
	if _finish_requested and not _capture_pending:
		_finish_capture()
	return _finished


func _configure_camera() -> void:
	var rig: Node3D = _main.get_node_or_null("CameraRig") as Node3D
	if rig != null and rig.has_method("reset_view"):
		# Main has configured the shop focus/zoom by now. Undo any virtual-display
		# edge pan from the first two frames before fixing the review pose.
		rig.call("reset_view")
	if _quarter >= 0:
		var view: Node = _main.get_node_or_null("ShopView")
		if rig == null or not rig.has_method("camera_quarter") or view == null or not view.has_method("set_wall_mode"):
			_fail_capture("requested quarter requires the shop camera and cutaway APIs")
			return
		# ShopView.WallMode is UP=0, CUTAWAY=1, DOWN=2. Use calls so the tool
		# also remains loadable for other scenes without those newer APIs.
		view.call("set_wall_mode", 1)
		rig.call("rotate_quarter", _quarter - int(rig.call("camera_quarter")))
		rig.call("step_view", 10.0, Vector2.ZERO)
	if rig != null:
		# Virtual-display focus/mouse position must not pan a review capture.
		rig.set_process(false)


func _configure_inspection() -> void:
	if _selection.is_empty() and not _f3:
		return
	if not _main.has_method("inspection_state") or _capture_world() == null:
		_fail_capture("requested inspection requires the scene's inspection state and live world APIs")
		return
	if not _selection.is_empty() and not _main.has_method("select_agent"):
		_fail_capture("--select requires the scene's select_agent API")
		return
	if _assign_owner and (not _main.has_method("assign_owner_mode") or not _main.has_method("run_ticks")):
		_fail_capture("owner assignment requires the scene's normal command and tick APIs")
		return
	if _f3:
		if not _main.has_method("set_debug_visible"):
			_fail_capture("--f3 requires the scene's set_debug_visible API")
			return
		_main.call("set_debug_visible", true)


func _capture_world() -> SimWorld:
	if "world" in _main:
		return _main.get("world") as SimWorld
	return null


func _configure_paint() -> void:
	var world: SimWorld = _capture_world()
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	if world == null or world.clock.phase != SimClock.Phase.MORNING or world.now != 0 \
			or catalogue == null or rig == null or not _main.has_method("set_paint_active") or not _main.has_method("paint_cell"):
		_fail_capture("--paint requires the production paused morning paint APIs")
		return
	# Present the colours without grid lines, as a player can by pressing G.
	if rig.grid_visible:
		rig.toggle_grid()
	if not bool(_main.call("set_paint_active", true)):
		_fail_capture("scene refused paint entry")
		return
	var samples: Array[Dictionary] = [
		{"swatch": &"sage", "cell": Vector2i(0, 5)},
		{"swatch": &"honey", "cell": Vector2i(8, 8)},
		{"swatch": &"terracotta", "cell": Vector2i(2, 6)},
		{"swatch": &"sage", "cell": Vector2i(12, 9)},
	]
	for sample: Dictionary in samples:
		var button: Button = catalogue.swatch_buttons.get(sample["swatch"]) as Button
		if button == null:
			_fail_capture("paint capture cannot find the requested native swatch")
			return
		button.pressed.emit()
		if not bool(_main.call("paint_cell", sample["cell"])):
			_fail_capture("paint capture could not colour its requested shop surface")
			return


func _paint_state() -> Dictionary:
	var world: SimWorld = _capture_world()
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	var view: ShopView = _main.get_node_or_null("ShopView") as ShopView
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	if world == null or editor == null or view == null or catalogue == null or rig == null:
		return {}
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	var plants: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"potted_plant")
	if tables.is_empty() or plants.is_empty() or view.get_node("Walls").get_child_count() == 0:
		return {}
	var wall: MeshInstance3D = view.get_node("Walls").get_child(0) as MeshInstance3D
	var floor_shader: ShaderMaterial = view.floor_mesh.material_override as ShaderMaterial
	var table_material: StandardMaterial3D = view.item_nodes[tables[0].id].material_override as StandardMaterial3D
	var plant_material: StandardMaterial3D = view.item_nodes[plants[0].id].material_override as StandardMaterial3D
	var content: ContentDB = _main.get("content") as ContentDB
	return {"active": _main.call("is_paint_active"), "catalogue_visible": catalogue.is_visible_in_tree(),
		"swatch_count": catalogue.swatch_buttons.size(), "grid_forced": rig.is_grid_forced(),
		"grid_visible": rig.effective_grid_visible(), "wall": String(editor.wall_swatch_id),
		"floor": String(editor.floor_swatch_id), "table": String(tables[0].swatch_id),
		"plant": String(plants[0].swatch_id),
		"rendered": (wall.material_override as StandardMaterial3D).albedo_color == content.swatch(&"sage").color \
			and floor_shader.get_shader_parameter("floor_color") == content.swatch(&"honey").color \
			and table_material.albedo_color == content.swatch(&"terracotta").color \
			and plant_material.albedo_color == content.swatch(&"sage").color}


## Review proposals only: no trial placements, transactions or save writes.
func _configure_build() -> void:
	var world: SimWorld = _capture_world()
	if world == null or world.clock.phase != SimClock.Phase.MORNING \
			or not _main.has_method("set_build_active") or not _main.has_method("begin_buy_item") \
			or not _main.has_method("update_build_pointer") or not _main.has_method("route_build_input"):
		_fail_capture("--build requires the production morning build APIs")
		return
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var def_id: StringName = &"table_2" if _build == "green" else &"fridge"
	var cell: Vector2i = Vector2i(8, 8) if _build == "green" else Vector2i(7, 7)
	var turns: int = 0 if _build == "green" else 1
	if editor == null or camera == null or not editor.can_edit() \
			or editor.check_buy(def_id, cell, turns).ok != (_build == "green"):
		_fail_capture("review proposal does not match the actual editor result")
		return
	_build_pointer = camera.unproject_position(GridMath.cell_to_world(cell))
	if not bool(_main.call("set_build_active", true)):
		_fail_capture("scene refused build entry")
		return
	_hold_build_pointer()
	if not bool(_main.call("begin_buy_item", def_id)):
		_fail_capture("scene refused buy preview")
		return
	for turn: int in range(turns):
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = KEY_R
		key.pressed = true
		_main.call("route_build_input", key)
	_main.call("update_build_pointer", _build_pointer)


func _hold_build_pointer() -> void:
	root.warp_mouse(_build_pointer)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _build_pointer
	motion.global_position = _build_pointer
	root.push_input(motion, true)


func _build_state() -> Dictionary:
	if not ("build_mode" in _main):
		return {}
	var mode: BuildMode = _main.get("build_mode") as BuildMode
	var preview: BuildPreview = _main.get_node_or_null("BuildPreview") as BuildPreview
	if mode == null or preview == null:
		return {}
	var ghost: MeshInstance3D = preview.ghost_mesh
	var pointer_cell: Variant = _main.call("build_cell_at_screen_position", root.get_mouse_position())
	return {"active": mode.is_active(), "state": int(mode.state), "has_ghost": mode.has_ghost(),
		"definition": String(mode.selected_definition.id) if mode.selected_definition != null else "",
		"origin": [mode.origin.x, mode.origin.y], "quarter_turns": mode.quarter_turns,
		"pointer_cell": [pointer_cell.x, pointer_cell.y] if pointer_cell is Vector2i else null,
		"ok": mode.current_check.ok, "why": mode.current_check.why,
		"ghost_visible": is_instance_valid(ghost) and ghost.is_visible_in_tree(),
		"ghost_valid": ghost.get_meta("valid", null) if is_instance_valid(ghost) else null}


func _select_live_agent() -> void:
	var world: SimWorld = _capture_world()
	if world == null:
		_fail_capture("--select requires a live simulation world")
		return
	var selected: SimAgent = world.agent(_selected_agent_id)
	if (_selection == &"guest" and selected is CustomerAgent) or (_selection == &"owner" and selected is OwnerAgent):
		return
	# Wait only within the requested frame budget for normal/--fast arrivals.
	# If a previous guest departed, select the next live guest in stable id order.
	_selected_agent_id = -1
	for agent: SimAgent in world.agents:
		if (_selection == &"guest" and agent is CustomerAgent) or (_selection == &"owner" and agent is OwnerAgent):
			if not bool(_main.call("select_agent", agent.id)):
				_fail_capture("scene rejected selection of a live " + String(_selection))
				return
			_selected_agent_id = agent.id
			if _assign_owner and not bool(_main.call("assign_owner_mode", &"kitchen")):
				_fail_capture("scene rejected the normal owner kitchen command")
			return


## Bounded normal simulation only: wait for actual owner cooking work rather
## than installing a capture fixture, task, inventory or altered staff priority.
func _prepare_owner_capture() -> void:
	var world: SimWorld = _capture_world()
	if world == null or not world.agent(_selected_agent_id) is OwnerAgent:
		_fail_capture("owner kitchen capture has no live selected owner")
		return
	for tick: int in range(MAX_OWNER_WARMUP_TICKS + 1):
		var selected_owner: OwnerAgent = world.agent(_selected_agent_id) as OwnerAgent
		if _owner_cook_task(selected_owner) and selected_owner.step_index == 0:
			return
		if tick == MAX_OWNER_WARMUP_TICKS:
			break
		var before: int = world.now
		_main.call("run_ticks", 1)
		if world.now != before + 1:
			break
		_owner_warmup_ticks += 1
	_fail_capture("normal owner did not claim fresh cooking work within the bounded capture warmup")


func _owner_cook_task(selected_owner: OwnerAgent) -> bool:
	return selected_owner != null and selected_owner.current_mode() == &"kitchen" and selected_owner.task != null \
		and selected_owner.task.role == &"cook" and selected_owner.task.state == SimTask.State.CLAIMED \
		and selected_owner.task.claimed_by == selected_owner.id and selected_owner.step_index >= 0 \
		and selected_owner.step_index < selected_owner.task.steps.size()


func _queue_capture() -> void:
	_capture_pending = true
	_capture_frame = _frames
	_capture_wait_frames = 0
	# MainLoop._process precedes node processing and rendering. Save pixels and
	# inspect the scene together only after this frame has actually been drawn.
	RenderingServer.frame_post_draw.connect(_capture, CONNECT_ONE_SHOT)


func _capture() -> void:
	if _finished or _failed or not _capture_pending:
		return
	if _errors.count() > 0:
		_fail_capture("engine/script errors occurred before capture")
		return
	var inspection: Dictionary = {}
	if _main.has_method("inspection_state"):
		inspection = _main.call("inspection_state")
	var world: SimWorld = _capture_world()
	var build: Dictionary = _build_state()
	if not _build.is_empty() and (build.get("active") != true or build.get("has_ghost") != true \
			or build.get("ghost_visible") != true or build.get("ok") != (_build == "green") \
			or build.get("ghost_valid") != (_build == "green") or build.get("origin") != build.get("pointer_cell")):
		_fail_capture("requested build preview was not present in the rendered frame")
		return
	var menu_visible: Variant = _main.call("is_menu_visible") if _main.has_method("is_menu_visible") else null
	if _menu and (menu_visible != true or world == null or world.clock.phase != SimClock.Phase.MORNING):
		_fail_capture("requested menu was not visible in the rendered morning frame")
		return
	var staff_state: Dictionary = _staff_state()
	if _staff and (staff_state.get("visible") != true or world == null or world.clock.phase != SimClock.Phase.MORNING \
			or world.now != 0 or not _staff_capture_valid(staff_state)):
		_fail_capture("requested Staff panel did not show the real paused morning roster and pool")
		return
	if _report_requested and not _report_capture_valid(world):
		_fail_capture("requested report did not show at least two actual reviews after service closed")
		return
	var paint: Dictionary = _paint_state() if _paint else {}
	if _paint and (paint.get("active") != true or paint.get("catalogue_visible") != true \
			or paint.get("swatch_count") != 12 or paint.get("grid_forced") != false \
			or paint.get("grid_visible") != false or paint.get("wall") != "sage" \
			or paint.get("floor") != "honey" or paint.get("table") != "terracotta" \
			or paint.get("plant") != "sage" or paint.get("rendered") != true \
			or world == null or world.now != 0 or world.clock.phase != SimClock.Phase.MORNING):
		_fail_capture("painted shop state did not match the rendered morning frame")
		return
	var selected_id: int = int(inspection.get("selected_agent_id", -1))
	var selected: SimAgent = world.agent(selected_id) if world != null else null
	var selected_live: bool = (_selection == &"guest" and selected is CustomerAgent) or (_selection == &"owner" and selected is OwnerAgent)
	if not _selection.is_empty():
		if _selected_agent_id < 1 or selected_id != _selected_agent_id or not selected_live or inspection.get("selected_role") != String(_selection) or inspection.get("panel_visible") != true:
			_fail_capture("requested live selection/panel was not present in the rendered frame")
			return
	if _assign_owner:
		var selected_owner: OwnerAgent = selected as OwnerAgent
		if not _owner_cook_task(selected_owner):
			_fail_capture("rendered owner is not actually assigned and claiming kitchen work")
			return
		if inspection.get("owner_mode") != "kitchen" or inspection.get("selected_task_id") != selected_owner.task.id or inspection.get("selected_task_claimant") != selected_id or inspection.get("selected_task_role") != "cook" or inspection.get("selected_task_state") != int(SimTask.State.CLAIMED) or inspection.get("selected_task_step") != selected_owner.step_index:
			_fail_capture("owner inspection/task metadata differs from the rendered simulation")
			return
	if _f3 and inspection.get("debug_visible") != true:
		_fail_capture("requested F3 overlay was not visible in the rendered frame")
		return
	if (not _selection.is_empty() or _f3) and (world == null or inspection.get("world_tick", -1) != world.now):
		_fail_capture("inspection world tick did not match the rendered simulation")
		return
	var rig: Node3D = _main.get_node_or_null("CameraRig") as Node3D
	var view: Node = _main.get_node_or_null("ShopView")
	var actual_quarter: Variant = null
	var yaw_degrees: Variant = null
	var wall_mode: Variant = null
	var lowered: Array = []
	if rig != null:
		yaw_degrees = fposmod(rad_to_deg(rig.rotation.y), 360.0)
		if rig.has_method("camera_quarter"):
			actual_quarter = rig.call("camera_quarter")
	if view != null and "wall_mode" in view:
		wall_mode = view.get("wall_mode")
		if view.has_method("lowered_wall_cells"):
			var cells: Array = view.call("lowered_wall_cells")
			for cell: Vector2i in cells:
				lowered.append([cell.x, cell.y])
	if _quarter >= 0:
		var expected_yaw: float = 45.0 + 90.0 * _quarter
		if actual_quarter != _quarter or wall_mode != 1 or yaw_degrees == null or absf(float(yaw_degrees) - expected_yaw) > 0.01:
			_fail_capture("requested camera quarter/cutaway mode did not match the rendered scene")
			return
	var path: String = _out.path_join("shot_%04d.png" % _capture_frame)
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		_fail_capture("cannot save viewport image: " + path)
		return
	var image_hash: String = FileAccess.get_sha256(path)
	if image_hash.length() != 64:
		_fail_capture("cannot hash saved viewport image: " + path)
		return
	var master_seed: Variant = null
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state != null and "master_seed" in game_state:
		master_seed = str(game_state.get("master_seed"))
	var restaurant_rng: Dictionary = {}
	if "sim" in _main:
		var restaurant: RestaurantSim = _main.get("sim") as RestaurantSim
		if restaurant != null and restaurant.rng != null:
			restaurant_rng = {"seed": str(restaurant.rng.seed), "state": str(restaurant.rng.state)}
	var metadata: Dictionary = {
		"image_file": path.get_file(), "image_sha256": image_hash,
		"scene": _scene_path, "frame": _capture_frame, "requested_quarter": _quarter,
		"actual_quarter": actual_quarter, "yaw_degrees": yaw_degrees,
		"wall_mode": wall_mode, "lowered_wall_cells": lowered,
		"width": image.get_width(), "height": image.get_height(),
		"godot_version": Engine.get_version_info()["string"],
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"engine_errors": _errors.count(),
		"capture_timing": "frame_post_draw",
		"requested_selection": String(_selection),
		"requested_owner_mode": "kitchen" if _assign_owner else "",
		"owner_mode": inspection.get("owner_mode", ""),
		"owner_warmup_ticks": _owner_warmup_ticks,
		"selected_task_id": inspection.get("selected_task_id", -1),
		"selected_task_role": inspection.get("selected_task_role", ""),
		"selected_task_label": inspection.get("selected_task_label", ""),
		"selected_task_state": inspection.get("selected_task_state", -1),
		"selected_task_claimant": inspection.get("selected_task_claimant", -1),
		"selected_task_step": inspection.get("selected_task_step", -1),
		"requested_debug_visible": _f3,
		"requested_menu_visible": _menu, "menu_visible": menu_visible,
		"requested_staff_visible": _staff, "staff": staff_state,
		"requested_report": _report_requested,
		"report_review_count": (_main.get("shown_report") as DayReport).review_cards.size()
			if _report_requested else 0,
		"requested_build": _build, "build": build,
		"requested_paint": _paint, "paint": paint,
		"day_phase": int(world.clock.phase) if world != null else null,
		"selected_agent_id": inspection.get("selected_agent_id"),
		"selected_item_id": inspection.get("selected_item_id"),
		"selected_role": inspection.get("selected_role"),
		"selected_agent_live": selected_live,
		"panel_visible": inspection.get("panel_visible"),
		"debug_visible": inspection.get("debug_visible"),
		"world_tick": inspection.get("world_tick", world.now if world != null else null),
		"capture_parameters": {"open": _open, "fast_ticks_per_frame": _fast, "speed": _speed},
		"master_seed": master_seed, "restaurant_rng": restaurant_rng,
		"mood": mood_evidence(world, view, root.get_viewport().get_camera_3d()),
	}
	var file: FileAccess = FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if file == null:
		_fail_capture("cannot write capture metadata")
		return
	file.store_string(JSON.stringify(metadata, "\t"))
	file.flush()
	var metadata_error: Error = file.get_error()
	file.close()
	if metadata_error != OK:
		_fail_capture("cannot save capture metadata")
		return
	print("saved ", path)
	print("capture ", JSON.stringify(metadata))
	_capture_pending = false
	if _finish_requested:
		_finish_capture()


## This reads the live report and its native card labels after the frame draw.
## It does not add review fixtures or force a rating in the captured game.
func _report_capture_valid(world: SimWorld) -> bool:
	if world == null or world.clock.phase != SimClock.Phase.CLOSED or not "shown_report" in _main:
		return false
	var report: DayReport = _main.get("shown_report") as DayReport
	var panel: Control = _main.get_node_or_null("Overlay/EveningReport") as Control
	if report == null or report.review_cards.size() < 2 or panel == null or not panel.is_visible_in_tree():
		return false
	var rows: Node = panel.get_node_or_null("%ReviewRows")
	if rows == null or rows.get_child_count() < 2:
		return false
	for index: int in range(mini(report.review_cards.size(), 3)):
		var card: Dictionary = report.review_cards[index]
		var native: Label = rows.get_child(index) as Label
		if native == null or String(card.get("quote", "")).is_empty() \
				or native.text != '%d stars - "%s"' % [int(card.get("stars", 0)), String(card["quote"])]:
			return false
	return true


## Read model records and actual native rows together, after the image draw.
func _staff_state() -> Dictionary:
	var panel: StaffPanel = _main.get_node_or_null("Overlay/StaffPanel") as StaffPanel
	if panel == null or not ("staff_roster" in _main):
		return {}
	var roster: StaffRoster = _main.get("staff_roster")
	if roster == null:
		return {}
	var rows: Array[Dictionary] = []
	var members: Array[StaffMember] = roster.members()
	var candidates: Array[StaffMember] = roster.candidates()
	for member: StaffMember in members + candidates:
		var row: Control = panel.row_for(member.id)
		if row == null:
			continue
		var button: Button = row.get_node("Top/Action") as Button
		rows.append({"id": String(member.id), "name_and_wage": (row.get_node("Top/Name") as Label).text,
			"trait": (row.get_node("Trait") as Label).text, "action": button.text,
			"disabled": button.disabled, "visible_in_tree": row.is_visible_in_tree()})
	return {"visible": panel.is_visible_in_tree(), "roster": roster.to_dict(), "rows": rows,
		"member_count": members.size(), "candidate_count": candidates.size()}


## Semantic state checks belong beside the captured native reads, not in CI.
func _staff_capture_valid(state: Dictionary) -> bool:
	var roster: Dictionary = state.get("roster", {})
	var members: Array = roster.get("members", [])
	var candidates: Array = roster.get("candidates", [])
	if members.size() != 2 or candidates.size() != 3 \
			or state.get("member_count") != 2 or state.get("candidate_count") != 3:
		return false
	var native_rows: Array = state.get("rows", [])
	var rows: Dictionary[String, Dictionary] = {}
	for row: Dictionary in native_rows:
		var id: String = row.get("id", "")
		if id.is_empty() or rows.has(id):
			return false
		rows[id] = row
	if rows.size() != 5:
		return false
	for person: Dictionary in members + candidates:
		var row: Dictionary = rows.get(person["id"], {})
		var title: String = row.get("name_and_wage", "")
		var definition: StaffTrait = StaffRoster.CATALOGUE.find_trait(StringName(person["trait"]))
		var action: String = "Let go" if members.has(person) else "Hire"
		if row.get("visible_in_tree") != true or not title.contains(person["name"]) \
				or not title.contains("skill %d" % int(person["skill"])) \
				or not title.contains("$%d/day" % int(person["wage"])) \
				or row.get("action") != action or definition == null \
				or not String(row.get("trait", "")).begins_with(definition.display_name + ":"):
			return false
	return true


## Snapshot model values and independently read actual marker nodes. In
## particular, never derive a marker's reported band from the guest's band.
static func mood_evidence(world: SimWorld, view: Node, camera: Camera3D = null) -> Dictionary:
	var waiting: Array[Dictionary] = []
	var indicators: Array[Dictionary] = []
	var shop: ShopView = view as ShopView
	if world == null or shop == null:
		return {"available": false, "fixture": "none", "waiting_guests": waiting, "visible_indicators": indicators}
	for agent: SimAgent in world.agents:
		if agent is CustomerAgent:
			var guest: CustomerAgent = agent as CustomerAgent
			if CustomerAgent.MOOD_WAITING_STATES.has(int(guest.state)):
				waiting.append({"id": guest.id, "state": int(guest.state),
					"mood": guest.mood(), "band": guest.mood_band(),
					"queue_wait": guest._queue_wait, "queue_patience": guest.queue_patience,
					"food_wait": guest._food_wait, "food_patience": guest.food_patience,
					"rng_seed": str(guest.rng.seed), "rng_state": str(guest.rng.state)})
	var ids: Array[int] = []
	ids.assign(shop.mood_nodes.keys())
	ids.sort()
	for id: int in ids:
		var icon: GuestMoodIndicator = shop.mood_nodes[id]
		if not is_instance_valid(icon) or not icon.is_visible_in_tree() or not icon.dot.is_visible_in_tree():
			continue
		var color: Color = (icon.dot.material_override as StandardMaterial3D).albedo_color
		var screen: Variant = null
		var in_frustum: Variant = null
		if camera != null:
			var projected: Vector2 = camera.unproject_position(icon.global_position)
			screen = [projected.x, projected.y]
			in_frustum = camera.is_position_in_frustum(icon.global_position)
		indicators.append({"id": id, "band": icon.band,
			"parent_agent_id": icon.get_parent().get_meta("agent_id", -1),
			"visible_in_tree": icon.is_visible_in_tree(), "dot_visible": icon.dot.is_visible_in_tree(),
			"mark": icon.mark.text, "mark_visible": icon.mark.is_visible_in_tree(),
			"color": [color.r, color.g, color.b, color.a],
			"screen_position": screen, "in_camera_frustum": in_frustum})
	return {"available": true, "fixture": "none", "waiting_guests": waiting, "visible_indicators": indicators}


func _finish_capture() -> void:
	if _finished:
		return
	# quit() is deferred; a later process/render callback must not tear down twice.
	_finished = true
	_capture_pending = false
	if RenderingServer.frame_post_draw.is_connected(_capture):
		RenderingServer.frame_post_draw.disconnect(_capture)
	OS.remove_logger(_errors)
	quit(1 if _failed or _errors.count() > 0 else 0)


func _fail_capture(message: String) -> void:
	_failed = true
	printerr("ERROR: capture failed: ", message)
	_finish_capture()
