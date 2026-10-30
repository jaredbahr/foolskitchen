extends TestCase
## Forecast UI and outdoor upload geometry preserve every indoor receiver.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const LIGHTING: PackedScene = preload("res://src/world/lighting_rig.tscn")

class PanOnce extends Node:
	var rig: CameraRig
	var movement: Vector3 = Vector3(4.0, 0.0, 0.0)
	var moved: bool = false

	func _process(_delta: float) -> void:
		if not moved:
			rig.position += movement
			moved = true
		set_process(false)

var _main: Node3D
var _subviewport: SubViewport
var _root_window: Window
var _old_window_size: Vector2i
var _old_scale: float
var _old_disk_enabled: bool
var _old_providers: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_root_window = (Engine.get_main_loop() as SceneTree).root
	_old_window_size = _root_window.size
	_old_scale = _root_window.content_scale_factor
	_old_disk_enabled = Preferences._disk_enabled
	Preferences._disk_enabled = false
	_old_providers = SaveSystem._providers.duplicate(true)
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if is_instance_valid(_subviewport):
		_subviewport.get_parent().remove_child(_subviewport)
		_subviewport.free()
	_subviewport = null
	_root_window.size = _old_window_size
	_root_window.content_scale_factor = _old_scale
	Preferences._disk_enabled = _old_disk_enabled
	SaveSystem._providers = _old_providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_weather_words_forecasts_and_three_named_icons_use_the_approved_style() -> void:
	for row: Array in [[0, "Sunny", "Sunny today", &"weather_sunny"],
		[1, "Cloudy", "Cloudy today", &"weather_cloudy"], [2, "Rain", "Rain today", &"weather_rain"]]:
		assert_eq(WeatherText.name_for(row[0]), row[1])
		assert_eq(WeatherText.forecast_for(row[0]), row[2])
		assert_false(WeatherText.forecast_for(row[0]).to_lower().contains("patio"))
		assert_eq(WeatherText.icon_for(row[0]), row[3])
		assert_eq(IconCatalogue.path_for(row[3]), "res://assets/made/icons/%s.png" % row[3])
		var texture: Texture2D = IconCatalogue.texture_for(row[3])
		assert_not_null(texture)
		if texture == null:
			continue
		var image: Image = texture.get_image()
		assert_eq(image.get_size(), Vector2i(100, 100))
		assert_eq(image.get_format(), Image.FORMAT_RGBA8)
		var visible: int = 0
		for y: int in 100:
			for x: int in 100:
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a > 0.0:
					visible += 1
					assert_eq(Color(pixel.r, pixel.g, pixel.b, 1.0), Color.WHITE)
		assert_true(visible > 0 and visible < 10000, "the icon is a transparent rounded white silhouette")


func test_hud_day_weather_group_and_morning_forecast_fit_both_windows_and_all_ui_scales() -> void:
	await _start(true)
	var hud: Node = _main.get_node("HUD")
	var day: Label = hud.get_node("Top/Row/Day") as Label
	var weather: Label = hud.get_node("Top/Row/Weather") as Label
	var panel: MenuPanel = _main.get_node("Overlay/MenuPanel") as MenuPanel
	var forecast: Label = panel.get_node("Panel/Content/WeatherForecast") as Label
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		_root_window.size = dimensions
		for scale: float in [1.0, 1.25, 1.5]:
			_root_window.content_scale_factor = scale
			_world().weather.kind = WeatherState.Kind.RAIN
			_main.call("refresh_presentation")
			assert_true(_main.call("set_menu_visible", true))
			await _frames(4)
			assert_eq(weather.text, "Rain")
			assert_true(weather.is_visible_in_tree())
			assert_true(_root_window.get_visible_rect().grow(1.0).encloses((hud.get_node("Top") as Control).get_global_rect()))
			assert_almost_eq(day.get_global_rect().position.y, weather.get_global_rect().position.y, 1.0,
				"day and weather stay in the same explicit HUD group")
			assert_true(weather.get_global_rect().position.x >= day.get_global_rect().end.x - 0.5)
			var icon: TextureRect = weather.get_node("ThemeIcon") as TextureRect
			assert_true(icon.visible)
			assert_true(weather.get_global_rect().grow(1.0).encloses(icon.get_global_rect()))
			assert_eq(forecast.text, "Rain today")
			assert_true(forecast.is_visible_in_tree())
			assert_true((panel.get_node("Panel") as Control).get_global_rect().grow(1.0).encloses(forecast.get_global_rect()))
			panel.set_phase(SimClock.Phase.OPEN)
			assert_false(forecast.visible, "the forecast line is morning-only")
			assert_true(_main.call("set_menu_visible", false))


func test_rain_upload_packet_stays_outside_before_and_after_floor_expansion_in_every_view() -> void:
	await _start()
	_world().weather.kind = WeatherState.Kind.RAIN
	for expanded: bool in [false, true]:
		if expanded:
			assert_true(_main.call("shop_floor", [Vector2i(14, 7), Vector2i(14, 8), Vector2i(14, 9)] as Array[Vector2i], true))
			assert_eq(_world().grid.terrain(Vector2i(14, 8)), SimGrid.Terrain.FLOOR)
		for quarter: int in 4:
			_rig().initial_yaw_degrees = 45.0 + float(quarter) * 90.0
			_rig().reset_view()
			_view().set_camera_quarter(quarter)
			for mode: int in [ShopView.WallMode.UP, ShopView.WallMode.CUTAWAY, ShopView.WallMode.DOWN]:
				_view().set_wall_mode(mode)
				_weather_view().refresh()
				_weather_view()._process(0.0)  # Drive the normal current-camera invalidation path.
				_assert_rain_upload_outside()
				_assert_rain_upload_clear_of_projected_building()


func test_current_camera_pan_rebuilds_the_rain_upload_mask_in_the_same_frame() -> void:
	await _start()
	_world().weather.kind = WeatherState.Kind.RAIN
	_view().set_wall_mode(ShopView.WallMode.DOWN)
	_weather_view().refresh()
	_weather_view().set_process(true)
	assert_true(_weather_view().process_priority > _rig().process_priority)
	assert_true(_weather_view().process_priority < _main.process_priority)
	var pan: PanOnce = PanOnce.new()
	pan.rig = _rig()
	pan.process_priority = _rig().process_priority
	var previous: Vector3 = _rig().position
	_subviewport.add_child(pan)
	# The zero timer runs after the normal node process pass, including the pan and rain rebuild.
	await (Engine.get_main_loop() as SceneTree).create_timer(0.0).timeout
	assert_true(pan.moved)
	assert_true(_rig().position.is_equal_approx(previous + pan.movement))
	_assert_rain_upload_outside()
	_assert_rain_upload_clear_of_projected_building()
	pan.get_parent().remove_child(pan)
	pan.free()


func test_original_lights_sky_and_all_nonpavement_materials_remain_unchanged() -> void:
	await _start()
	var original: Node3D = LIGHTING.instantiate() as Node3D
	var expected_lighting: Dictionary = _lighting_snapshot(original)
	original.free()
	_world().weather.kind = WeatherState.Kind.SUNNY
	_main.call("refresh_presentation")
	assert_eq(_lighting_snapshot(_main.get_node("LightingRig")), expected_lighting,
		"the live interior rig equals the unchanged authored scene")
	var materials: Dictionary = _interior_material_snapshot()
	var random: Dictionary = GameState.call("_capture_save")
	for kind: int in [WeatherState.Kind.CLOUDY, WeatherState.Kind.RAIN, WeatherState.Kind.SUNNY]:
		_world().weather.kind = kind as WeatherState.Kind
		_main.call("refresh_presentation")
		await _frames(2)
		assert_eq(_lighting_snapshot(_main.get_node("LightingRig")), expected_lighting)
		assert_eq(_interior_material_snapshot(), materials)
		assert_eq(GameState.call("_capture_save"), random)


func test_weather_light_only_reaches_actual_outside_pavement_and_sunny_restores_it() -> void:
	await _start()
	_world().weather.kind = WeatherState.Kind.SUNNY
	_main.call("refresh_presentation")
	var pavement: Dictionary = _pavement_colors()
	assert_false(pavement.is_empty(), "the real scene supplies outdoor pavement receivers")
	assert_false(_weather_view().rain.visible)
	assert_false(_weather_view().outdoor_light.visible)
	_world().weather.kind = WeatherState.Kind.RAIN
	_main.call("refresh_presentation")
	assert_true(_weather_view().rain.visible)
	assert_true(_weather_view().outdoor_light.visible)
	assert_eq(_weather_view().outdoor_light.light_cull_mask, WeatherView.OUTDOOR_LAYER)
	var receivers: int = 0
	for node: Node in _view().find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if (mesh.layers & WeatherView.OUTDOOR_LAYER) == 0:
			continue
		receivers += 1
		assert_true(_pavement_ancestor(mesh) != null, "no indoor/whole-shop geometry receives the outdoor weather light")
		_assert_bounds_outside(mesh.global_transform * mesh.get_aabb())
	assert_true(receivers > 0)
	var rainy: Dictionary = _pavement_colors()
	var changed: bool = false
	for path: String in pavement:
		if rainy[path] != pavement[path]:
			changed = true
			assert_true((rainy[path] as Color).get_luminance() < (pavement[path] as Color).get_luminance())
	assert_true(changed, "rain makes an actual outdoor receiver darker")
	_world().weather.kind = WeatherState.Kind.CLOUDY
	_main.call("refresh_presentation")
	assert_false(_weather_view().rain.visible)
	_world().weather.kind = WeatherState.Kind.SUNNY
	_main.call("refresh_presentation")
	assert_eq(_pavement_colors(), pavement)
	assert_false(_weather_view().outdoor_light.visible)


func _start(on_root: bool = false) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var host: Node = _root_window
	if not on_root:
		_subviewport = SubViewport.new()
		_subviewport.size = Vector2i(1600, 900)
		_subviewport.own_world_3d = true
		_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		tree.root.add_child(_subviewport)
		host = _subviewport
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 241)
	host.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	_rig().set_process(false)
	_rig().edge_pan_enabled = false
	_view().set_process(false)
	_weather_view().set_process(false)
	Clock.set_speed(0)
	await _frames(4)


func _assert_rain_upload_outside() -> void:
	var rain: MultiMeshInstance3D = _weather_view().rain
	assert_true(rain.visible)
	var packet: Array[Transform3D] = _weather_view().rain_transforms
	assert_eq(packet.size(), rain.multimesh.instance_count, "every computed upload entry has a rendered instance")
	assert_true(packet.size() > 0, "rain has a real compute-once upload packet")
	for transform: Transform3D in packet:
		var xf: Transform3D = rain.global_transform * transform
		_assert_bounds_outside(xf * rain.multimesh.mesh.get_aabb())


func _assert_bounds_outside(bounds: AABB) -> void:
	var low: Vector2i = GridMath.world_to_cell(bounds.position + Vector3.ONE * 0.00001)
	var high: Vector2i = GridMath.world_to_cell(bounds.end - Vector3.ONE * 0.00001)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			assert_eq(_world().grid.terrain(Vector2i(x, y)), SimGrid.Terrain.OUTSIDE,
				"a rain-upload/light-receiver bound never overlaps floor, bought floor, walls or entry")


func _assert_rain_upload_clear_of_projected_building() -> void:
	var camera: Camera3D = _main.get_node("CameraRig/Camera3D") as Camera3D
	var building: Array[Rect2] = []
	for cell: Vector2i in _world().grid.cells():
		if _world().grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			building.append(_projected_rect(camera, AABB(Vector3(cell.x * GridMath.CELL_SIZE, 0.0, cell.y * GridMath.CELL_SIZE),
				Vector3(GridMath.CELL_SIZE, ArtScale.WALL_HEIGHT, GridMath.CELL_SIZE))))
	var rain: MultiMeshInstance3D = _weather_view().rain
	var packet: Array[Transform3D] = _weather_view().rain_transforms
	assert_eq(packet.size(), rain.multimesh.instance_count)
	assert_true(packet.size() > 0)
	for transform: Transform3D in packet:
		var xf: Transform3D = rain.global_transform * transform
		var rectangle: Rect2 = _projected_rect(camera, xf * rain.multimesh.mesh.get_aabb())
		for occupied: Rect2 in building:
			assert_false(rectangle.intersects(occupied), "rain upload geometry does not project across the current indoor volume")


func _projected_rect(camera: Camera3D, bounds: AABB) -> Rect2:
	var result: Rect2 = Rect2()
	for index: int in 8:
		var point: Vector2 = camera.unproject_position(bounds.get_endpoint(index))
		result = Rect2(point, Vector2.ZERO) if index == 0 else result.expand(point)
	return result


func _lighting_snapshot(rig: Node) -> Dictionary:
	var result: Dictionary = {}
	for name: String in ["KeyLight", "FillLight"]:
		var light: DirectionalLight3D = rig.get_node(name) as DirectionalLight3D
		result[name] = [light.rotation, light.light_color, light.light_energy, light.light_specular,
			light.light_cull_mask, light.sky_mode, light.shadow_enabled]
	var environment: Environment = (rig.get_node("Environment") as WorldEnvironment).environment
	result["environment"] = [environment.background_mode, environment.background_color,
		environment.ambient_light_source, environment.ambient_light_color, environment.ambient_light_energy,
		environment.ambient_light_sky_contribution, environment.tonemap_mode, environment.tonemap_exposure,
		environment.tonemap_white, environment.glow_enabled]
	var sky: ProceduralSkyMaterial = environment.sky.sky_material as ProceduralSkyMaterial
	result["sky"] = [sky.sky_top_color, sky.sky_horizon_color, sky.ground_bottom_color,
		sky.ground_horizon_color, sky.energy_multiplier]
	return result


func _interior_material_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for node: Node in _view().find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if _weather_view().is_ancestor_of(mesh) or _pavement_ancestor(mesh) != null:
			continue
		assert_eq(mesh.layers & WeatherView.OUTDOOR_LAYER, 0)
		var materials: Array = []
		var surface_count: int = mesh.mesh.get_surface_count() if mesh.mesh != null else 0
		for index: int in surface_count:
			var material: Material = mesh.get_active_material(index)
			if material is BaseMaterial3D:
				var body: BaseMaterial3D = material as BaseMaterial3D
				materials.append([body.get_instance_id(), body.albedo_color, body.roughness,
					body.metallic, body.emission, body.transparency, body.shading_mode])
			elif material is ShaderMaterial:
				var shader: ShaderMaterial = material as ShaderMaterial
				var parameters: Dictionary = {}
				if shader.shader != null:
					for uniform: Dictionary in shader.shader.get_shader_uniform_list():
						parameters[uniform["name"]] = shader.get_shader_parameter(uniform["name"])
				materials.append([shader.get_instance_id(), shader.shader, parameters])
			else:
				materials.append(material)
		result[String(_view().get_path_to(mesh))] = [mesh.layers, mesh.material_override, materials]
	return result


func _pavement_ancestor(node: Node) -> PropView:
	var current: Node = node
	while current != null and current != _view():
		var prop: PropView = current as PropView
		if prop != null and prop.get_meta(&"kind", &"") == &"pavement":
			return prop
		current = current.get_parent()
	return null


func _pavement_colors() -> Dictionary:
	var result: Dictionary = {}
	for node: Node in _view().room_dressing.get_children():
		var prop: PropView = node as PropView
		if prop != null and prop.get_meta(&"kind", &"") == &"pavement":
			var material: BaseMaterial3D = prop.active_body_material()
			if material != null:
				result[String(prop.name)] = material.albedo_color
	return result


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _view() -> ShopView:
	return _main.get_node("ShopView") as ShopView


func _weather_view() -> WeatherView:
	return _view().weather_view


func _rig() -> CameraRig:
	return _main.get_node("CameraRig") as CameraRig


func _frames(count: int) -> void:
	for frame: int in count:
		await (Engine.get_main_loop() as SceneTree).process_frame
