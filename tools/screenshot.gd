extends SceneTree
## Renders the main scene and saves PNG screenshots, for reviews and PRs.
## Run through tools/screenshot.sh (it provides a virtual display).
## User args (after --): --out=<dir> --frames=120,400,900 --speed=4 --scene=res://...
## Optional --quarter=0..3 selects an exact cutaway camera quarter for review.
##   --open      press "Open shop" at the start
##   --fast=N    also run N extra sim ticks per frame (via the scene's run_ticks)
##   --select=guest  inspect a live guest through the scene's selection API
##   --f3        show the scene's read-only debug overlay
##   --build=green|red|warning|catalogue  use the actual closed-shop build APIs
## Mood metadata records actual markers/seeds with no waiting fixture; build
## metadata explicitly discloses its one checked purchase in warning mode.

const MAX_CAPTURE_WAIT_FRAMES: int = 8

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
var _select_guest: bool = false
var _f3: bool = false
var _selected_guest_id: int = -1
var _capture_pending: bool = false
var _capture_frame: int = 0
var _capture_wait_frames: int = 0
var _finish_requested: bool = false
var _build: String = ""
var _build_pointer: Vector2 = Vector2.ZERO
var _build_setup: Dictionary = {}


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
			if arg != "--select=guest":
				_fail_capture("--select only supports --select=guest")
				return
			_select_guest = true
		elif arg.begins_with("--f3"):
			if arg != "--f3":
				_fail_capture("--f3 does not accept a value")
				return
			_f3 = true
		elif arg.begins_with("--build"):
			var requested: String = arg.trim_prefix("--build=")
			if not ["green", "red", "warning", "catalogue"].has(requested):
				_fail_capture("--build supports green, red, warning or catalogue")
				return
			_build = requested
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
	if not _build.is_empty() and (_open or _fast != 0 or _select_guest or _f3):
		_fail_capture("--build requires the ordinary closed scene without --open, --fast, --select or --f3")
		return
	if _shots.is_empty() or _shots.min() < 1 or ((_quarter >= 0 or _select_guest or _f3 or not _build.is_empty()) and _shots.min() < 4):
		_fail_capture("capture frames must be positive, and at least 4 for --quarter, --select, --f3 or --build")
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
		_configure_build()
		if _failed:
			return true
	if not _build.is_empty() and _frames >= 3:
		_hold_build_pointer()
	if _fast > 0 and _frames > 3 and _main.has_method("run_ticks"):
		_main.call("run_ticks", _fast)
	if _select_guest and _frames >= 3:
		_select_live_guest()
		if _failed:
			return true
	_finish_requested = _frames >= _shots.max()
	if _shots.has(_frames):
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
	if not _select_guest and not _f3:
		return
	if not _main.has_method("inspection_state") or _capture_world() == null:
		_fail_capture("requested inspection requires the scene's inspection state and live world APIs")
		return
	if _select_guest and not _main.has_method("select_agent"):
		_fail_capture("--select=guest requires the scene's select_agent API")
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


func _configure_build() -> void:
	if _build.is_empty():
		return
	var world: SimWorld = _capture_world()
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	var preview: BuildPreview = _main.get_node_or_null("BuildPreview") as BuildPreview
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	if world == null or rig == null or preview == null or catalogue == null or not ("shop_editor" in _main) \
			or not ("build_mode" in _main) or not _main.has_method("set_build_active") \
			or not _main.has_method("begin_buy_item") or not _main.has_method("update_build_pointer") \
			or not _main.has_method("route_build_input") or not preview.has_method("visual_state"):
		_fail_capture("--build requires the live shop/controller, build visual state and production input APIs")
		return
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	if editor == null or not editor.can_edit() or world.clock.phase != SimClock.Phase.MORNING:
		_fail_capture("--build requires the fresh editable morning scene")
		return
	var before: Dictionary = _build_snapshot()
	if not bool(_main.call("set_build_active", true)):
		_fail_capture("scene refused build mode entry")
		return
	var proposal: Dictionary = {}
	var purchased_id: int = -1
	if _build == "catalogue":
		_build_pointer = (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(GridMath.cell_to_world(Vector2i(7, 8)))
		_hold_build_pointer()
	else:
		proposal = _find_build_proposal(editor)
		if proposal.is_empty():
			_fail_capture("no bounded real editor proposal fits the requested build capture and visible UI bounds")
			return
		_build_pointer = Vector2(proposal["screen"][0], proposal["screen"][1])
		_hold_build_pointer()
		if not bool(_main.call("begin_buy_item", StringName(proposal["def_id"]))):
			_fail_capture("scene refused the checked buy ghost")
			return
		for turn: int in range(int(proposal["quarter_turns"])):
			var rotate: InputEventKey = InputEventKey.new()
			rotate.physical_keycode = KEY_R
			rotate.pressed = true
			if not bool(_main.call("route_build_input", rotate)):
				_fail_capture("scene refused build rotation input")
				return
		_main.call("update_build_pointer", _build_pointer)
		if _build == "warning":
			var click: InputEventMouseButton = InputEventMouseButton.new()
			click.position = _build_pointer
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			if not bool(_main.call("route_build_input", click)):
				_fail_capture("scene refused the checked warning purchase click")
				return
			var cell: Vector2i = Vector2i(proposal["origin"][0], proposal["origin"][1])
			var item: PlacedItem = world.grid.item_at(cell)
			if item == null or not editor.check_current().unreachable.has(item.id):
				_fail_capture("warning purchase did not produce a real unreachable item ID")
				return
			purchased_id = item.id
	_build_setup = {"fixture": "checked_unreachable_purchase" if _build == "warning" else "none",
		"proposal": proposal, "purchased_id": purchased_id, "before": before, "after": _build_snapshot()}


## Aim with the same native viewport pointer that Main reprojects each frame.
## No controller origin/state field is assigned by the capture tool.
func _hold_build_pointer() -> void:
	root.warp_mouse(_build_pointer)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _build_pointer
	motion.global_position = _build_pointer
	root.push_input(motion, true)


## Fixed preferred origins, then at most 32 floor origins, all checked against
## actual content/editor rules. No trial placements or books changes here.
func _find_build_proposal(editor: ShopEditor) -> Dictionary:
	var content: ContentDB = _main.get("content") as ContentDB
	var world: SimWorld = _capture_world()
	var definition: ItemDef = content.item(&"table_2" if _build == "green" else &"fridge")
	if definition == null:
		return {}
	var origins: Array[Vector2i] = [Vector2i(8, 8), Vector2i(10, 8), Vector2i(4, 9), Vector2i(7, 7)]
	if _build == "red":
		origins = [Vector2i(7, 7), Vector2i(3, 7), Vector2i(11, 7), Vector2i(4, 1)]
	elif _build == "warning":
		origins = [Vector2i(10, 1), Vector2i(11, 1), Vector2i(9, 1), Vector2i(2, 3)]
	for y: int in range(world.grid.size.y):
		for x: int in range(world.grid.size.x):
			var cell: Vector2i = Vector2i(x, y)
			if origins.size() < 36 and world.grid.terrain(cell) == SimGrid.Terrain.FLOOR and not origins.has(cell):
				origins.append(cell)
	for cell: Vector2i in origins:
		for turns: int in range(4):
			if not _proposal_screen_safe(definition, cell, turns):
				continue
			# A red footprint may overlap, but keep its work marker on exposed
			# floor for review rather than underneath an opaque existing table.
			var exposed_work: bool = true
			for offset: Vector2i in definition.work_cells:
				if not world.grid.is_walkable(cell + GridMath.rotate_cell(offset, definition.footprint, turns)):
					exposed_work = false
			if _build == "red" and not exposed_work:
				continue
			if _build == "green":
				for offset: Vector2i in definition.seat_cells:
					if not world.grid.is_walkable(cell + GridMath.rotate_cell(offset, definition.footprint, turns)):
						exposed_work = false
				if not exposed_work:
					continue
			var check: EditCheck = editor.check_buy(definition.id, cell, turns)
			if (_build == "green" and check.ok and check.unreachable.is_empty()) \
					or (_build == "red" and not check.ok and not check.why.is_empty()) \
					or (_build == "warning" and check.ok and check.unreachable.has(0)):
				var screen: Vector2 = (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(GridMath.cell_to_world(cell))
				return {"def_id": String(definition.id), "price": definition.price,
					"origin": [cell.x, cell.y], "quarter_turns": turns, "screen": [screen.x, screen.y],
					"check": _check_state(check)}
	return {}


func _proposal_screen_safe(definition: ItemDef, cell: Vector2i, turns: int) -> bool:
	var footprint: Vector2i = GridMath.rotated_footprint(definition.footprint, turns)
	var box: AABB = AABB(Vector3(cell.x * GridMath.CELL_SIZE, 0.0, cell.y * GridMath.CELL_SIZE),
		Vector3(footprint.x * GridMath.CELL_SIZE, ShopView.HEIGHTS.get(definition.category, 0.6), footprint.y * GridMath.CELL_SIZE))
	var camera: Camera3D = _main.get_node("CameraRig/Camera3D") as Camera3D
	var points: Array[Vector3] = []
	for index: int in range(8):
		points.append(box.get_endpoint(index))
	return _screen_bounds_safe(_project_points(points, camera))


func _build_snapshot() -> Dictionary:
	var world: SimWorld = _capture_world()
	var restaurant: RestaurantSim = _main.get("sim") as RestaurantSim
	var ledger: Ledger = root.get_node("Economy").get("ledger") as Ledger
	return {"shop": (_main.get("shop_editor") as ShopEditor).to_dict(), "books": ledger.to_dict(),
		"clock": world.clock.to_dict(), "world_tick": world.now,
		"rng": {"seed": str(restaurant.rng.seed), "state": str(restaurant.rng.state)}}


func _select_live_guest() -> void:
	var world: SimWorld = _capture_world()
	if world == null:
		_fail_capture("--select=guest requires a live simulation world")
		return
	if world.agent(_selected_guest_id) is CustomerAgent:
		return
	# Wait only within the requested frame budget for normal/--fast arrivals.
	# If a previous guest departed, select the next live guest in stable id order.
	_selected_guest_id = -1
	for agent: SimAgent in world.agents:
		if agent is CustomerAgent:
			if not bool(_main.call("select_agent", agent.id)):
				_fail_capture("scene rejected selection of a live guest")
				return
			_selected_guest_id = agent.id
			return


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
	var selected_id: int = int(inspection.get("selected_agent_id", -1))
	var selected_live: bool = world != null and world.agent(selected_id) is CustomerAgent
	if _select_guest:
		if _selected_guest_id < 1 or selected_id != _selected_guest_id or not selected_live or inspection.get("selected_role") != "guest" or inspection.get("panel_visible") != true:
			_fail_capture("requested live guest selection/panel was not present in the rendered frame")
			return
	if _f3 and inspection.get("debug_visible") != true:
		_fail_capture("requested F3 overlay was not visible in the rendered frame")
		return
	if (_select_guest or _f3) and (world == null or inspection.get("world_tick", -1) != world.now):
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
	var build: Dictionary = _build_evidence()
	if not _build.is_empty() and not _validate_build_capture(build):
		_fail_capture("requested build capture did not match actual editor, pointer, visible native bounds or UI")
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
		"requested_selection": "guest" if _select_guest else "",
		"requested_debug_visible": _f3,
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
		"requested_build": _build, "build": build,
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


func _build_evidence() -> Dictionary:
	var preview: BuildPreview = _main.get_node_or_null("BuildPreview") as BuildPreview
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	if not ("build_mode" in _main) or preview == null or catalogue == null or rig == null \
			or not preview.has_method("visual_state"):
		return {"available": false}
	var mode: BuildMode = _main.get("build_mode") as BuildMode
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	if mode == null or editor == null:
		return {"available": false}
	var camera: Camera3D = _main.get_node("CameraRig/Camera3D") as Camera3D
	var check: EditCheck = editor.check_current()
	if mode.state == BuildMode.State.BUY:
		check = editor.check_buy(mode.selected_definition.id, mode.origin, mode.quarter_turns)
	elif mode.state == BuildMode.State.MOVE:
		check = editor.check_move(mode.selected_item_id, mode.origin, mode.quarter_turns)
	var ghost_projection: Dictionary = {}
	if is_instance_valid(preview.ghost_mesh):
		ghost_projection = _project_meshes([preview.ghost_mesh] as Array[MeshInstance3D], camera)
	var outline_projections: Array[Dictionary] = []
	var warning_items: Array[Dictionary] = []
	for id: int in preview.displayed_warning_ids():
		var node: Node3D = preview.warning_nodes[id]
		var meshes: Array[MeshInstance3D] = []
		for child: Node in node.get_children():
			if child is MeshInstance3D:
				meshes.append(child as MeshInstance3D)
		outline_projections.append({"id": id, "projection": _project_meshes(meshes, camera)})
		var placed: PlacedItem = _capture_world().grid.item(id)
		if placed != null:
			warning_items.append({"id": id, "definition": _definition_state(placed.def as ItemDef),
				"origin": [placed.origin.x, placed.origin.y], "quarter_turns": placed.quarter_turns})
	var marker_projections: Array[Dictionary] = []
	for kind: String in ["work", "seat"]:
		var markers: Array[MeshInstance3D] = preview.work_markers if kind == "work" else preview.seat_markers
		for index: int in range(markers.size()):
			marker_projections.append({"kind": kind, "index": index,
				"projection": _project_meshes([markers[index]] as Array[MeshInstance3D], camera)})
	var buttons: Array[Dictionary] = []
	var content: ContentDB = _main.get("content") as ContentDB
	for id: StringName in catalogue.ordered_ids():
		var button: Button = catalogue.item_buttons[id]
		var definition: ItemDef = content.item(id)
		var row: Dictionary = _control_state(button)
		row["id"] = String(id)
		row["text"] = button.text
		row["disabled"] = button.disabled
		row["mouse_filter"] = button.mouse_filter
		row["price"] = definition.price
		row["display_name"] = definition.display_name
		var clipped: Rect2 = button.get_global_rect().intersection((catalogue.get_node("Panel/Margin/Rows/Scroll") as Control).get_global_rect())
		row["clipped_rect"] = _rect_array(clipped)
		buttons.append(row)
	var material: ShaderMaterial = rig.grid_material
	var pointer: Vector2 = root.get_mouse_position()
	var actual_cell: Variant = _main.call("build_cell_at_screen_position", pointer) if _main.has_method("build_cell_at_screen_position") else null
	return {"available": true, "requested": _build, "active": mode.is_active(), "state": mode.state,
		"has_ghost": mode.has_ghost(), "item_id": mode.selected_item_id,
		"definition": _definition_state(mode.selected_definition), "origin": [mode.origin.x, mode.origin.y],
		"quarter_turns": mode.quarter_turns, "preview_check": _check_state(mode.current_check),
		"editor_check": _check_state(check), "current_check": _check_state(editor.check_current()),
		"warning_ids": mode.warning_ids(), "committed_warning_ids": mode.committed_warning_ids.duplicate(),
		"native": preview.call("visual_state"), "ghost_projection": ghost_projection, "outline_projections": outline_projections,
		"warning_items": warning_items, "marker_projections": marker_projections,
		"pointer": {"requested": [_build_pointer.x, _build_pointer.y], "actual": [pointer.x, pointer.y],
			"actual_cell": [actual_cell.x, actual_cell.y] if actual_cell is Vector2i else null},
		"grid": {"preference": rig.grid_visible, "forced": rig.is_grid_forced(), "effective": rig.effective_grid_visible(),
			"shader": material.get_shader_parameter("grid_visible") if material != null else null},
		"catalogue": {"root": _control_state(catalogue), "panel": _control_state(catalogue.get_node("Panel") as Control),
			"scroll": _control_state(catalogue.get_node("Panel/Margin/Rows/Scroll") as Control), "buttons": buttons},
		"reason": {"panel": _control_state(_main.get_node("HUD/BuildHints") as Control),
			"label": _control_state(_main.get_node("HUD/BuildHints/Text") as Control),
			"text": (_main.get_node("HUD/BuildHints/Text") as Label).text},
		"hud": _control_state(_main.get_node("HUD/Top") as Control),
		"setup": _build_setup.duplicate(true), "actual_snapshot": _build_snapshot()}


func _validate_build_capture(build: Dictionary) -> bool:
	if build.get("available") != true or build.get("active") != true or build.get("requested") != _build \
			or build["grid"]["forced"] != true or build["grid"]["effective"] != true or build["grid"]["shader"] != true:
		return false
	if build["setup"].get("after") != build["actual_snapshot"] or build["catalogue"]["root"]["visible"] != true \
			or build["catalogue"]["panel"]["visible"] != true or build["reason"]["panel"]["visible"] != true:
		return false
	if not _rect_inside_image(build["catalogue"]["panel"]["rect"]) or not _rect_inside_image(build["reason"]["label"]["rect"]):
		return false
	var preview: BuildPreview = _main.get_node("BuildPreview") as BuildPreview
	if preview.displayed_warning_ids() != build["warning_ids"]:
		return false
	if _build == "green" or _build == "red":
		if not build["has_ghost"] or build["state"] != BuildMode.State.BUY or build["preview_check"] != build["editor_check"]:
			return false
		if build["editor_check"]["ok"] != (_build == "green") or build["pointer"]["actual_cell"] != build["origin"]:
			return false
		if not _screen_bounds_safe(build["ghost_projection"]):
			return false
		if _build == "red" and (build["editor_check"]["why"].is_empty() or not build["reason"]["text"].contains(build["editor_check"]["why"])):
			return false
	else:
		if build["has_ghost"] or build["state"] != BuildMode.State.IDLE or is_instance_valid(preview.ghost_mesh):
			return false
	if _build == "warning":
		var purchased: int = build["setup"]["purchased_id"]
		if purchased <= 0 or not build["warning_ids"].has(purchased) or build["warning_ids"].has(0):
			return false
	for row: Dictionary in build["outline_projections"]:
		if not _screen_bounds_safe(row["projection"]):
			return false
	for row: Dictionary in build["marker_projections"]:
		if not _screen_bounds_safe(row["projection"]):
			return false
	return true


func _screen_bounds_safe(projection: Dictionary) -> bool:
	if projection.get("all_in_frustum") != true or not _rect_inside_image(projection.get("rect", [])):
		return false
	var row: Array = projection["rect"]
	var bounds: Rect2 = Rect2(row[0], row[1], row[2], row[3]).grow(6.0)
	for path: String in ["HUD/Top", "HUD/BuildHints", "Overlay/BuildCatalogue/Panel"]:
		var control: Control = _main.get_node(path) as Control
		if control.is_visible_in_tree() and bounds.intersects(control.get_global_rect()):
			return false
	return true


func _rect_inside_image(row: Array) -> bool:
	return row.size() == 4 and row[2] > 0 and row[3] > 0 and row[0] >= 6 and row[1] >= 6 \
		and row[0] + row[2] <= root.size.x - 6 and row[1] + row[3] <= root.size.y - 6


static func _definition_state(definition: ItemDef) -> Dictionary:
	if definition == null:
		return {}
	var work: Array = []
	var seats: Array = []
	for cell: Vector2i in definition.work_cells:
		work.append([cell.x, cell.y])
	for cell: Vector2i in definition.seat_cells:
		seats.append([cell.x, cell.y])
	return {"id": String(definition.id), "footprint": [definition.footprint.x, definition.footprint.y],
		"height": ShopView.HEIGHTS.get(definition.category, 0.6), "price": definition.price,
		"work_cells": work, "seat_cells": seats,
		"color": [definition.placeholder_color.r, definition.placeholder_color.g, definition.placeholder_color.b, definition.placeholder_color.a]}


static func _check_state(check: EditCheck) -> Dictionary:
	return {"ok": check.ok, "why": check.why, "unreachable": check.unreachable.duplicate()}


static func _control_state(control: Control) -> Dictionary:
	return {"visible": control.is_visible_in_tree(), "rect": _rect_array(control.get_global_rect())}


static func _rect_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## Project actual native mesh corners, never a copied model pose.
static func _project_meshes(meshes: Array[MeshInstance3D], camera: Camera3D) -> Dictionary:
	var points: Array[Vector3] = []
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var box: AABB = mesh.mesh.get_aabb()
		for index: int in range(8):
			points.append(mesh.global_transform * box.get_endpoint(index))
	return _project_points(points, camera)


static func _project_points(points: Array[Vector3], camera: Camera3D) -> Dictionary:
	if points.is_empty() or camera == null:
		return {}
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	var in_frustum: bool = true
	for point: Vector3 in points:
		var screen: Vector2 = camera.unproject_position(point)
		low = low.min(screen)
		high = high.max(screen)
		in_frustum = in_frustum and camera.is_position_in_frustum(point)
	return {"rect": [low.x, low.y, high.x - low.x, high.y - low.y], "all_in_frustum": in_frustum, "corners": points.size()}


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
