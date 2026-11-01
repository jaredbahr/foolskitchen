extends RefCounted
## Unsaved review override after the real seed-1 morning selection. No seed
## search, tuning change or RNG draw. Forced sunny shows the morning forecast;
## rain keeps that panel closed for the predeclared opaque interior controls.

const FRAME: int = 60
const OUTDOOR_MASK: int = 1 << 18

static func options(arguments: PackedStringArray) -> Dictionary:
	var mode: String = ""
	for argument: String in arguments:
		if argument.begins_with("--weather-review"):
			if not mode.is_empty() or argument not in ["--weather-review=sunny", "--weather-review=rain"]:
				return {"mode": "", "error": "Use --weather-review=sunny or --weather-review=rain once"}
			mode = argument.trim_prefix("--weather-review=")
	if mode.is_empty():
		return {"mode": "", "error": ""}
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	var menus: int = 0
	for argument: String in arguments:
		if argument.begins_with("--weather-review=") or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=%d" % FRAME:
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		elif argument == "--menu":
			menus += 1
		else:
			return {"mode": "", "error": "Weather review requires a paused fresh morning without other view options"}
	if speeds != 1 or frames != 1 or scenes > 1 or menus != (1 if mode == "sunny" else 0):
		return {"mode": "", "error": "Use --speed=0 --frames=60; sunny also needs --menu, rain keeps it closed"}
	return {"mode": mode, "error": ""}

static func prepare(main: Node, root: Window, mode: String) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	if world == null or world.weather == null or world.clock.phase != SimClock.Phase.MORNING \
			or not world.weather.is_for_day(world.clock.day) or bool(main.get("use_saves")):
		return {"error": "Weather review requires a selected, unsaved morning"}
	var game: Node = root.get_node("GameState")
	var streams: Dictionary = (game.call("_capture_save") as Dictionary).duplicate(true)
	var selected: Dictionary = world.weather.to_dict()
	if mode == "rain":
		world.weather.kind = WeatherState.Kind.RAIN
	else:
		world.weather.kind = WeatherState.Kind.SUNNY
	main.call("refresh_presentation")
	if streams != game.call("_capture_save"):
		return {"error": "The visual review override changed a named RNG stream"}
	return {"error": "", "mode": mode, "unsaved_review_override": true,
		"description": "Seed 1; real initial morning selection, then explicitly forced unsaved weather for review; no seed hunting or tuning changes",
		"initial_selected_weather": selected, "forced_kind": int(world.weather.kind),
		"rng_state_after_initial_selection": streams, "forecast_panel_requested": mode == "sunny"}

static func evidence(main: Node, root: Window, fixture: Dictionary) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var view: ShopView = main.get_node("ShopView") as ShopView
	var weather: WeatherView = view.weather_view
	var hud: Label = main.get_node("HUD/Top/Row/Weather") as Label
	var forecast: Label = main.get_node("Overlay/MenuPanel/Panel/Content/WeatherForecast") as Label
	var hud_icon: TextureRect = hud.get_node_or_null("ThemeIcon") as TextureRect
	var forecast_icon: TextureRect = forecast.get_node_or_null("ThemeIcon") as TextureRect
	var expected_icon: String = IconCatalogue.path_for(WeatherText.icon_for(world.weather.kind))
	var rain_count: int = weather.rain.multimesh.instance_count if weather != null and weather.rain != null else 0
	var outside: bool = true
	var projection_clear: bool = true
	var packet_matches: bool = weather != null and weather.rain_transforms.size() == rain_count
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	var occupied: Array[Rect2] = []
	for cell: Vector2i in world.grid.cells():
		if world.grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			var base: Vector3 = Vector3(cell.x * GridMath.CELL_SIZE, 0.0, cell.y * GridMath.CELL_SIZE)
			occupied.append(projected_bounds(camera, view.global_transform * AABB(base, Vector3(GridMath.CELL_SIZE, ArtScale.WALL_HEIGHT, GridMath.CELL_SIZE))))
	if weather != null and weather.rain != null:
		for index: int in rain_count:
			# Native readback is checked independently of the headless upload packet.
			var drawn: Transform3D = weather.rain.multimesh.get_instance_transform(index)
			packet_matches = packet_matches and index < weather.rain_transforms.size() and drawn.is_equal_approx(weather.rain_transforms[index])
			var box: AABB = weather.rain.global_transform * (drawn * weather.rain.multimesh.mesh.get_aabb())
			outside = outside and outside_bounds(world.grid, box)
			var projected: Rect2 = projected_bounds(camera, box)
			for building: Rect2 in occupied:
				projection_clear = projection_clear and not projected.intersects(building)
	var layer_state: Dictionary = {"indoor_receivers": [], "outdoor_receivers": [], "invalid_receivers": []}
	collect_receivers(view, view, world.grid, layer_state)
	return {"kind": int(world.weather.kind), "day": world.weather.day, "phase": int(world.clock.phase), "world_tick": world.now,
		"hud_word": hud.text, "hud_visible": hud.is_visible_in_tree() and root.get_visible_rect().encloses(hud.get_global_rect()),
		"hud_icon_visible": hud_icon != null and hud_icon.is_visible_in_tree() and hud_icon.texture != null,
		"hud_icon_correct": hud_icon != null and hud_icon.texture != null and hud_icon.texture.resource_path == expected_icon,
		"forecast": forecast.text, "forecast_visible": forecast.is_visible_in_tree() and root.get_visible_rect().encloses(forecast.get_global_rect()),
		"forecast_icon_visible": forecast_icon != null and forecast_icon.is_visible_in_tree() and forecast_icon.texture != null,
		"forecast_icon_correct": forecast_icon != null and forecast_icon.texture != null and forecast_icon.texture.resource_path == expected_icon,
		"menu_visible": bool(main.call("is_menu_visible")), "rain_visible": weather != null and weather.rain.is_visible_in_tree(),
		"rain_instances": rain_count, "rendered_streak_bounds_outside": outside,
		"native_transform_readback_matches_upload_packet": packet_matches,
		"upload_packet_count": weather.rain_transforms.size() if weather != null else -1,
		"rendered_streaks_clear_projected_building": projection_clear,
		"outdoor_light_visible": weather != null and weather.outdoor_light.is_visible_in_tree(),
		"outdoor_light_energy": weather.outdoor_light.light_energy if weather != null else 0.0,
		"outdoor_light_mask": weather.outdoor_light.light_cull_mask if weather != null else 0,
		"receiver_layers": layer_state,
		"rng_unchanged_since_override": fixture.get("rng_state_after_initial_selection") == root.get_node("GameState").call("_capture_save"),
		"lighting_and_materials": lighting_snapshot(main)}

static func valid(state: Dictionary, mode: String) -> bool:
	var rainy: bool = mode == "rain"
	var kind: int = WeatherState.Kind.RAIN if rainy else WeatherState.Kind.SUNNY
	var layers: Dictionary = state.get("receiver_layers", {})
	if state.get("kind") != kind or state.get("day") != 1 or state.get("phase") != SimClock.Phase.MORNING \
			or state.get("world_tick") != 0 or state.get("hud_word") != WeatherText.name_for(kind) \
			or state.get("forecast") != WeatherText.forecast_for(kind) or state.get("hud_visible") != true \
			or state.get("hud_icon_visible") != true or state.get("hud_icon_correct") != true \
			or state.get("forecast_icon_correct") != true or state.get("rng_unchanged_since_override") != true \
			or state.get("native_transform_readback_matches_upload_packet") != true \
			or state.get("upload_packet_count") != state.get("rain_instances") \
			or not (layers.get("indoor_receivers", []) as Array).is_empty() \
			or not (layers.get("invalid_receivers", []) as Array).is_empty():
		return false
	if rainy:
		return state.get("menu_visible") == false and state.get("rain_visible") == true \
			and int(state.get("rain_instances", 0)) > 0 and state.get("rendered_streak_bounds_outside") == true \
			and state.get("rendered_streaks_clear_projected_building") == true \
			and state.get("outdoor_light_visible") == true and float(state.get("outdoor_light_energy", 0.0)) > 0.0 \
			and state.get("outdoor_light_mask") == OUTDOOR_MASK \
			and not (layers.get("outdoor_receivers", []) as Array).is_empty()
	return state.get("menu_visible") == true and state.get("forecast_visible") == true \
		and state.get("forecast_icon_visible") == true and state.get("rain_visible") == false \
		and state.get("rain_instances") == 0 and state.get("outdoor_light_visible") == false

static func lighting_snapshot(main: Node) -> Dictionary:
	var environment: Environment = (main.get_node("LightingRig/Environment") as WorldEnvironment).environment
	var view: ShopView = main.get_node("ShopView") as ShopView
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	var lights: Dictionary = {}
	for name: String in ["KeyLight", "FillLight"]:
		lights[name] = properties(main.get_node("LightingRig/" + name), ["rotation_degrees", "light_color", "light_energy", "light_indirect_energy", "light_specular", "light_cull_mask", "shadow_enabled", "sky_mode", "light_bake_mode"])
	var materials: Dictionary = {}
	collect_materials(view, view, materials)
	var floor: ShaderMaterial = view.floor_mesh.material_override as ShaderMaterial
	var uniforms: Dictionary = {}
	for uniform: Dictionary in floor.shader.get_shader_uniform_list():
		var name: String = uniform["name"]
		uniforms[name] = serial(floor.get_shader_parameter(name))
	return {"environment": properties(environment, ["background_mode", "background_color", "background_energy_multiplier", "ambient_light_source", "ambient_light_color", "ambient_light_energy", "ambient_light_sky_contribution", "reflected_light_source", "tonemap_mode", "tonemap_exposure", "tonemap_white", "glow_enabled", "fog_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled"]),
		"sky": properties(environment.sky, ["radiance_size", "process_mode"]),
		"sky_material": properties(environment.sky.sky_material, ["sky_top_color", "sky_horizon_color", "sky_curve", "ground_bottom_color", "ground_horizon_color", "ground_curve", "energy_multiplier", "sun_angle_max"]),
		"lights": lights, "camera": properties(camera, ["global_transform", "projection", "size", "fov", "near", "far", "cull_mask"]),
		"materials": materials, "shader": properties(floor, ["shader"]), "floor_shader_parameters": uniforms}

static func properties(object: Object, wanted: Array[String]) -> Dictionary:
	var names: Dictionary[String, bool] = {}
	for property: Dictionary in object.get_property_list():
		names[property["name"]] = true
	var result: Dictionary = {}
	for name: String in wanted:
		result[name] = serial(object.get(name)) if names.has(name) else {"property_absent": true}
	return result

static func collect_materials(node: Node, base: Node, result: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: MeshInstance3D = node as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface)
			if material is BaseMaterial3D:
				result[String(base.get_path_to(node)) + ":" + str(surface)] = properties(material, ["albedo_color", "metallic", "metallic_specular", "roughness", "emission_enabled", "emission", "shading_mode", "transparency", "albedo_texture", "normal_enabled", "uv1_scale", "uv1_offset"])
	for child: Node in node.get_children():
		collect_materials(child, base, result)

static func collect_receivers(node: Node, base: Node, grid: SimGrid, result: Dictionary) -> void:
	if node is GeometryInstance3D and ((node as GeometryInstance3D).layers & OUTDOOR_MASK) != 0:
		var parent: Node = node
		var pavement: PropView = null
		while parent != null and parent != base:
			if parent is PropView and parent.get_meta(&"kind", &"") == &"pavement":
				pavement = parent as PropView
				break
			parent = parent.get_parent()
		var path: String = String(base.get_path_to(node))
		if pavement == null:
			(result["indoor_receivers"] as Array).append(path)
		elif outside_bounds(grid, pavement.global_transform * pavement.get_combined_aabb()):
			(result["outdoor_receivers"] as Array).append(path)
		else:
			(result["invalid_receivers"] as Array).append(path)
	for child: Node in node.get_children():
		collect_receivers(child, base, grid, result)

static func projected_bounds(camera: Camera3D, bounds: AABB) -> Rect2:
	var projected: Rect2 = Rect2()
	for corner: int in 8:
		var point: Vector2 = camera.unproject_position(bounds.get_endpoint(corner))
		projected = Rect2(point, Vector2.ZERO) if corner == 0 else projected.expand(point)
	return projected.grow(1.0)

static func outside_bounds(grid: SimGrid, bounds: AABB) -> bool:
	var low: Vector2i = GridMath.world_to_cell(bounds.position + Vector3.ONE * 0.00001)
	var high: Vector2i = GridMath.world_to_cell(bounds.end - Vector3.ONE * 0.00001)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			if grid.terrain(Vector2i(x, y)) != SimGrid.Terrain.OUTSIDE:
				return false
	return true

static func serial(value: Variant) -> Variant:
	match typeof(value):
		TYPE_COLOR:
			var c: Color = value
			return [c.r, c.g, c.b, c.a]
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_TRANSFORM3D:
			var t: Transform3D = value
			return [serial(t.basis.x), serial(t.basis.y), serial(t.basis.z), serial(t.origin)]
		TYPE_OBJECT:
			if value is Resource:
				var resource: Resource = value
				return {"class": resource.get_class(), "path": resource.resource_path}
			return null
		TYPE_STRING_NAME:
			return String(value)
	return value
