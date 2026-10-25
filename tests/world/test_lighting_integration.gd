extends TestCase
## Native scene/resource contracts; rendered appearance and Web FPS need captures.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const RIG: PackedScene = preload("res://src/world/lighting_rig.tscn")
const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const CAMERA: PackedScene = preload("res://src/world/camera_rig.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")


func test_playable_main_owns_one_rig_and_shop_view_has_no_second_environment() -> void:
	var main: Node = MAIN.instantiate()
	assert_eq(main.find_children("*", "WorldEnvironment", true, false).size(), 1)
	assert_eq(main.find_children("*", "DirectionalLight3D", true, false).size(), 2)
	assert_not_null(main.get_node_or_null("LightingRig/Environment"))
	assert_eq(main.get_node("ShopView").find_children("*", "WorldEnvironment", true, false).size(), 0)
	assert_eq(main.get_node("ShopView").find_children("*", "Light3D", true, false).size(), 0)
	main.free()


func test_thumbnail_uses_same_light_settings_with_detached_transparent_environment() -> void:
	var playable: Node3D = RIG.instantiate() as Node3D
	var preview: Node3D = ItemThumbnailCache.create_preview_lighting()
	assert_not_null(preview)
	if preview == null:
		playable.free()
		return
	var world_env: Environment = (playable.get_node("Environment") as WorldEnvironment).environment
	var preview_env: Environment = (preview.get_node("Environment") as WorldEnvironment).environment
	assert_eq(preview_env.get_local_scene(), preview,
		"preview keeps its native scene-local environment instead of discarding it for another copy")
	assert_eq(preview_env.sky.get_local_scene(), preview)
	assert_eq(preview_env.sky.sky_material.get_local_scene(), preview)
	assert_true(world_env != preview_env)
	assert_true(world_env.sky != preview_env.sky)
	assert_true(world_env.sky.sky_material != preview_env.sky.sky_material)
	assert_eq(world_env.background_mode, Environment.BG_SKY)
	assert_eq(preview_env.background_mode, Environment.BG_CLEAR_COLOR)
	assert_eq(preview_env.ambient_light_color, world_env.ambient_light_color)
	assert_almost_eq(preview_env.ambient_light_energy, world_env.ambient_light_energy)
	assert_almost_eq(preview_env.tonemap_exposure, world_env.tonemap_exposure)
	for path: String in ["KeyLight", "FillLight"]:
		var original: DirectionalLight3D = playable.get_node(path) as DirectionalLight3D
		var copied: DirectionalLight3D = preview.get_node(path) as DirectionalLight3D
		assert_eq(copied.light_color, original.light_color)
		assert_almost_eq(copied.light_energy, original.light_energy)
		assert_eq(copied.transform, original.transform)
		assert_eq(copied.sky_mode, DirectionalLight3D.SKY_MODE_LIGHT_ONLY)
	preview_env.ambient_light_energy = 0.0
	assert_true(world_env.ambient_light_energy > 0.0)
	var preview_sky_material: ProceduralSkyMaterial = preview_env.sky.sky_material as ProceduralSkyMaterial
	var world_sky_material: ProceduralSkyMaterial = world_env.sky.sky_material as ProceduralSkyMaterial
	preview_sky_material.energy_multiplier = 0.0
	assert_true(world_sky_material.energy_multiplier > 0.0, "preview sky changes never mutate playable lighting")
	preview.free()
	playable.free()


func test_real_painted_floor_retains_camera_grid_toggle_and_dressing_rebind_cleanup() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(LAYOUT, content, errors)
	assert_eq(errors, [] as Array[String])
	var view: ShopView = VIEW.instantiate() as ShopView
	view.show_world(world)
	assert_not_null(view.room_dressing)
	view.set_paint(content, &"sage", &"honey")
	var material: ShaderMaterial = view.floor_mesh.material_override as ShaderMaterial
	assert_eq(material.get_shader_parameter("floor_color"), content.swatch(&"honey").color)
	var camera: CameraRig = CAMERA.instantiate() as CameraRig
	camera.grid_floor = view.floor_mesh
	camera.set_grid_forced(false)
	var before: bool = camera.grid_visible
	assert_eq(camera.toggle_grid(), not before)
	assert_eq(material.get_shader_parameter("grid_visible"), not before)
	assert_eq(camera.toggle_grid(), before)
	assert_eq(material.get_shader_parameter("grid_visible"), before)
	assert_eq(material.get_shader_parameter("floor_color"), content.swatch(&"honey").color)
	assert_eq(world.now, 0)
	var old_dressing: WeakRef = weakref(view.room_dressing)
	view.show_world(null)
	assert_null(view.room_dressing)
	assert_null(old_dressing.get_ref(), "replacing the world releases its view-only dressing")
	assert_eq(view.get_child_count(), 0)
	camera.free()
	view.free()
