extends RefCounted
## Photo-only neighbourhood observation. This tool never creates actors, moves
## sim agents, advances the world, changes lights, or replaces the normal clock.
const PHOTO_TIME: float = 4.0
const FRAME: int = 60
const ROAD_CENTRE: float = 4.605
const STREET_EXTENSION: float = 3.0
# Independent AABB transform paths can round one FP32 ULP apart. Only the
# containment comparison gets this metre tolerance; all clearances stay strict.
const CAR_CONTAINMENT_ALLOWANCE: float = 0.00001
const IDS: Array[int] = [1, 4, 6]


## Existing plain default/quarter capture shapes become reproducible photos.
## Every unrelated legacy mode passes through unchanged. Only street is new.
static func options(arguments: PackedStringArray) -> Dictionary:
	var street: bool = false
	for argument: String in arguments:
		if argument.begins_with("--neighbourhood-review"):
			if street or argument != "--neighbourhood-review=street":
				return {"mode": "", "error": "Use --neighbourhood-review=street once"}
			street = true
	var frames: int = 0
	var speeds: int = 0
	var scenes: int = 0
	var quarters: int = 0
	var compatible: bool = true
	for argument: String in arguments:
		if argument.begins_with("--out=") or argument == "--neighbourhood-review=street":
			continue
		if argument == "--frames=60":
			frames += 1
		elif argument in ["--speed=0", "--speed=1"]:
			speeds += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		elif argument in ["--quarter=0", "--quarter=1", "--quarter=2", "--quarter=3"]:
			quarters += 1
		else:
			compatible = false
	compatible = compatible and frames == 1 and speeds == 1 and scenes <= 1 and quarters <= 1
	if street:
		if not compatible or quarters != 0 or not arguments.has("--speed=0"):
			return {"mode": "", "error": "Street review requires only Main --speed=0 --frames=60"}
		return {"mode": "street", "error": ""}
	return {"mode": ("quarter" if quarters == 1 else "default") if compatible else "", "error": ""}


static func prepare(main: Node, root: Window, mode: String) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var view: ShopView = main.get_node("ShopView") as ShopView
	var node: Node = view.get("neighbourhood_dressing") as Node
	var result: Dictionary = {"error": "", "kind": "unsaved_neighbourhood_photo", "mode": mode,
		"photo_time": PHOTO_TIME, "description": "Seed 1; real neighbourhood nodes and walk animation at authored photo time4s. Simulation stays at its real day-one morning. Performance uses a separate normal-process harness and never enables this override."}
	if world == null or node == null or main.get("use_saves") != false or world.now != 0 \
			or world.clock.day != 1 or world.clock.phase != SimClock.Phase.MORNING:
		result["error"] = "Neighbourhood photo requires the real fresh unsaved Main morning and controller"
		return result
	result["sim_state_before"] = sim_state(main, root)
	result["original_camera"] = camera_state(main)
	if not node.call("set_review_time", PHOTO_TIME):
		result["error"] = "The real neighbourhood controller refused photo time4s"
		return result
	if mode == "street":
		var observed: Dictionary = node.call("capture_state")
		var frame: Dictionary = observed.get("frame", {})
		if not frame.has("origin") or not frame.has("normal") or not frame.has("reserve_shift"):
			result["error"] = "Street photo has no observed real frontage frame"
			return result
		var normal: Vector3 = vector3(frame["normal"])
		if not is_equal_approx(absf(normal.x) + absf(normal.z), 1.0) or not is_zero_approx(normal.y):
			result["error"] = "Street photo requires the actual cardinal frontage normal"
			return result
		var target: Vector3 = view.to_global(vector3(frame["origin"]) + normal * (float(frame["reserve_shift"]) + ROAD_CENTRE))
		var rig: CameraRig = main.get_node("CameraRig") as CameraRig
		var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
		var movement: Vector3 = target - rig.global_position
		movement.y = 0.0
		var local: Vector3 = Basis(Vector3.UP, rig.rotation.y).inverse() * movement
		var metres_per_pixel: float = camera.size / root.get_visible_rect().size.y * rig.drag_sensitivity
		var drag: Vector2 = Vector2(-local.x, -local.z * sin(deg_to_rad(rig.pitch_degrees))) / metres_per_pixel
		var low: Vector2 = rig.pan_center - rig.pan_limits.abs()
		var high: Vector2 = rig.pan_center + rig.pan_limits.abs()
		low += Vector2(minf(normal.x, 0.0), minf(normal.z, 0.0)) * STREET_EXTENSION
		high += Vector2(maxf(normal.x, 0.0), maxf(normal.z, 0.0)) * STREET_EXTENSION
		var expected: Vector2 = Vector2(target.x, target.z).clamp(low, high)
		rig.pan_by_drag(drag, root.get_visible_rect().size.y)
		result["street_focus"] = {"definition": "Observed frontage origin + outward*(reserve shift +4.605m), through the real camera drag/clamp; original zoom/yaw retained.",
			"requested": [target.x, target.z], "expected_clamped": [expected.x, expected.y],
			"actual": [rig.position.x, rig.position.z], "clamp_low": [low.x, low.y], "clamp_high": [high.x, high.y]}
		if not Vector2(rig.position.x, rig.position.z).is_equal_approx(expected):
			result["error"] = "The real street-only camera clamp did not produce the predeclared focus"
			return result
	result["photo_pose"] = poses(node)
	result["camera_after_prepare"] = camera_state(main)
	if result["sim_state_before"] != sim_state(main, root):
		result["error"] = "The photo override or view pan changed real simulation state"
	return result


static func evidence(main: Node, root: Window, fixture: Dictionary) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var view: ShopView = main.get_node("ShopView") as ShopView
	var node: Node = view.get("neighbourhood_dressing") as Node
	if node == null:
		return {"available": false}
	var observed: Dictionary = node.call("capture_state")
	var actors: Array[Dictionary] = []
	var people: Array = node.get("pedestrians")
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	for index: int in people.size():
		var person: PersonView = people[index] as PersonView
		if person == null:
			return {"available": false}
		var head: Vector3 = person.global_transform * person.head_anchor_position()
		var screen: Vector2 = camera.unproject_position(head)
		actors.append({"id": person.guest_id, "role": String(person.role), "model": String(person.model_name()),
			"expected_model": String(PersonPresentation.model_for(&"guest", person.guest_id)),
			"model_scene": person._model.scene_file_path if person._model != null else "",
			"expected_model_scene": PersonPresentation.model_path_for(&"guest", person.guest_id),
			"visible": person.is_visible_in_tree() and person._model != null and person._model.is_visible_in_tree(),
			"skeleton_ready": person._skeleton != null, "clip": String(person.current_clip()),
			"player_clip": String(person._player.current_animation) if person._player != null else "",
			"animation_position": person._player.current_animation_position if person._player != null else -1.0,
			"head": [head.x, head.y, head.z], "head_screen": [screen.x, screen.y],
			"head_in_view": camera.is_position_in_frustum(head) and root.get_visible_rect().has_point(screen),
			"in_sim_view_map": view.agent_nodes.values().has(person)})
	var car: PropView = node.get("car") as PropView
	if car == null:
		return {"available": false}
	var car_world: AABB = car.global_transform * car.get_combined_aabb()
	var car_local: AABB = view.global_transform.affine_inverse() * car_world
	var bounds: Dictionary = observed.get("bounds", {})
	var sweeps: Array = bounds.get("pedestrian_sweeps", [])
	var reserve: AABB = aabb(bounds.get("reserve", {}))
	var approaches: Array = bounds.get("door_approaches", [])
	var safe_sweeps: bool = bounds.has("reserve") and bounds.has("car_sweep") and bounds.has("door_approaches")
	for entry: Dictionary in sweeps:
		var sweep: AABB = aabb(entry)
		safe_sweeps = safe_sweeps and outside(world.grid, sweep) and not overlaps_xz(sweep, reserve)
		for approach: Dictionary in approaches:
			safe_sweeps = safe_sweeps and not overlaps_xz(sweep, aabb(approach))
	var car_sweep: AABB = aabb(bounds.get("car_sweep", {}))
	var actual_car_safe: bool = outside(world.grid, car_local) and not overlaps_xz(car_local, reserve)
	var car_sweep_safe: bool = outside(world.grid, car_sweep) and not overlaps_xz(car_sweep, reserve) and car_sweep.grow(CAR_CONTAINMENT_ALLOWANCE).encloses(car_local)
	for approach: Dictionary in approaches:
		actual_car_safe = actual_car_safe and not overlaps_xz(car_local, aabb(approach))
		car_sweep_safe = car_sweep_safe and not overlaps_xz(car_sweep, aabb(approach))
	var static_root: Node = node.get("static_root") as Node
	var hazards: Dictionary = {"colliders": [], "navigation": [], "lights": [], "static_shadow_casters": []}
	inspect_nodes(node, node, static_root, hazards)
	return {"available": true, "mode": fixture.get("mode"), "observed": observed,
		"viewport": [root.size.x, root.size.y], "sim_state": sim_state(main, root),
		"camera": camera_state(main), "actual_photo_pose": poses(node), "actors": actors,
		"car_visible": car.is_visible_in_tree(), "actual_car_bounds": box(car_local),
		"declared_car_sweep": box(car_sweep), "car_containment_allowance_metres": CAR_CONTAINMENT_ALLOWANCE,
		"actual_car_safe": actual_car_safe, "declared_car_sweep_safe": car_sweep_safe,
		"declared_complete_sweeps_safe": safe_sweeps,
		"sweep_count": sweeps.size(), "static_root_present": static_root != null, "hazards": hazards,
		"visibility_scope": "Actual real models, animation players and controller poses are observed. Screen/frustum data alone do not prove occlusion or style; inspect the whole PNG."}


static func valid(state: Dictionary, fixture: Dictionary) -> bool:
	if fixture.get("error") != "" or state.get("available") != true or state.get("viewport") != [1600, 900] \
			or state.get("sim_state") != fixture.get("sim_state_before") \
			or state.get("camera") != fixture.get("camera_after_prepare") \
			or state.get("actual_photo_pose") != fixture.get("photo_pose"):
		return false
	var observed: Dictionary = state["observed"]
	if not is_equal_approx(float(observed.get("review_time", -1.0)), PHOTO_TIME) \
			or observed.get("is_processing") != true or not String(observed.get("build_error", "")).is_empty() \
			or state.get("static_root_present") != true or int(observed.get("static_mesh_count", 0)) <= 0 \
			or state.get("sweep_count") != 3 or state.get("declared_complete_sweeps_safe") != true \
			or state.get("actual_car_safe") != true or state.get("declared_car_sweep_safe") != true:
		return false
	var hazards: Dictionary = state["hazards"]
	for key: String in hazards:
		if not (hazards[key] as Array).is_empty():
			return false
	var actors: Array = state["actors"]
	if actors.size() != IDS.size():
		return false
	var visible_heads: int = 0
	for index: int in actors.size():
		var actor: Dictionary = actors[index]
		if actor["id"] != IDS[index] or actor["role"] != "guest" or actor["model"] != actor["expected_model"] \
				or actor["model_scene"] != actor["expected_model_scene"] or actor["visible"] != true \
				or actor["skeleton_ready"] != true or actor["clip"] != "walk" or actor["player_clip"] != "walk" \
				or actor["in_sim_view_map"] != false:
			return false
		if actor["head_in_view"]:
			visible_heads += 1
	if fixture["mode"] == "street" and (state["car_visible"] != true or visible_heads == 0):
		return false
	return true


static func sim_state(main: Node, root: Window) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var agents: Array[Dictionary] = []
	for agent: SimAgent in world.agents:
		agents.append({"id": agent.id, "role": String(agent.role), "cell": [agent.cell.x, agent.cell.y]})
	return {"world_tick": world.now, "day": world.clock.day, "phase": int(world.clock.phase),
		"grid_version": world.grid.version, "agents": agents, "cash": root.get_node("Economy").get("cash"),
		"rng": root.get_node("GameState").call("_capture_save"), "use_saves": main.get("use_saves")}


static func poses(node: Node) -> Dictionary:
	var result: Array[Dictionary] = []
	var people: Array = node.get("pedestrians")
	for person: PersonView in people:
		result.append({"id": person.guest_id, "transform": matrix(person.global_transform),
			"clip": String(person.current_clip()),
			"animation": String(person._player.current_animation) if person._player != null else "",
			"phase": person._player.current_animation_position if person._player != null else -1.0})
	var car: PropView = node.get("car") as PropView
	return {"pedestrians": result, "car_transform": matrix(car.global_transform) if car != null else [],
		"car_visible": car != null and car.visible}


static func camera_state(main: Node) -> Dictionary:
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	return {"projection": camera.projection, "size": camera.size, "fov": camera.fov,
		"near": camera.near, "far": camera.far, "cull_mask": camera.cull_mask,
		"transform": matrix(camera.global_transform), "focus": [rig.position.x, rig.position.z]}


static func inspect_nodes(node: Node, base: Node, static_root: Node, result: Dictionary) -> void:
	var path: String = String(base.get_path_to(node))
	if node is CollisionObject3D or node is CollisionShape3D:
		(result["colliders"] as Array).append(path)
	if node is NavigationAgent3D or node is NavigationRegion3D:
		(result["navigation"] as Array).append(path)
	if node is Light3D:
		(result["lights"] as Array).append(path)
	if static_root != null and static_root.is_ancestor_of(node) and node is GeometryInstance3D \
			and (node as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		(result["static_shadow_casters"] as Array).append(path)
	for child: Node in node.get_children():
		inspect_nodes(child, base, static_root, result)


static func overlaps_xz(first: AABB, second: AABB) -> bool:
	return Rect2(Vector2(first.position.x, first.position.z), Vector2(first.size.x, first.size.z)).intersects(
		Rect2(Vector2(second.position.x, second.position.z), Vector2(second.size.x, second.size.z)))


static func outside(grid: SimGrid, bounds: AABB) -> bool:
	var low: Vector2i = GridMath.world_to_cell(bounds.position + Vector3.ONE * 0.00001)
	var high: Vector2i = GridMath.world_to_cell(bounds.end - Vector3.ONE * 0.00001)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			if grid.terrain(Vector2i(x, y)) != SimGrid.Terrain.OUTSIDE:
				return false
	return true


static func vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func aabb(value: Dictionary) -> AABB:
	return AABB(vector3(value.get("position", [0, 0, 0])), vector3(value.get("size", [0, 0, 0])))


static func box(value: AABB) -> Dictionary:
	return {"position": [value.position.x, value.position.y, value.position.z],
		"size": [value.size.x, value.size.y, value.size.z]}


static func matrix(value: Transform3D) -> Array:
	return [[value.basis.x.x, value.basis.x.y, value.basis.x.z],
		[value.basis.y.x, value.basis.y.y, value.basis.y.z],
		[value.basis.z.x, value.basis.z.y, value.basis.z.z],
		[value.origin.x, value.origin.y, value.origin.z]]
