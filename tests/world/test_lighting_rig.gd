extends TestCase
## Structural checks for the single scene-owned lighting setup.

const RIG: PackedScene = preload("res://src/world/lighting_rig.tscn")


func test_rig_has_one_environment_warm_key_and_low_cool_fill() -> void:
	var rig: Node3D = RIG.instantiate() as Node3D
	var environments: Array[Node] = rig.find_children("*", "WorldEnvironment", true, false)
	var lights: Array[Node] = rig.find_children("*", "DirectionalLight3D", true, false)
	assert_eq(environments.size(), 1)
	assert_eq(lights.size(), 2)
	var environment_node: WorldEnvironment = environments[0] as WorldEnvironment
	assert_not_null(environment_node.environment.sky)
	assert_eq(environment_node.environment.ambient_light_sky_contribution, 0.0)
	assert_almost_eq(environment_node.environment.tonemap_exposure, 0.65, 0.0001)
	assert_almost_eq(environment_node.environment.tonemap_white, 4.0, 0.0001)
	var key: DirectionalLight3D = rig.get_node("KeyLight") as DirectionalLight3D
	var fill: DirectionalLight3D = rig.get_node("FillLight") as DirectionalLight3D
	assert_true(key.light_color.r > key.light_color.b)
	assert_true(fill.light_color.b > fill.light_color.r)
	assert_true(fill.light_energy < key.light_energy)
	assert_eq(key.sky_mode, DirectionalLight3D.SKY_MODE_LIGHT_ONLY)
	assert_eq(fill.sky_mode, DirectionalLight3D.SKY_MODE_LIGHT_ONLY)
	assert_true(key.shadow_enabled, "the key light keeps main's form shadows")
	assert_false(fill.shadow_enabled, "only the key light casts shadows")
	var sky: ProceduralSkyMaterial = environment_node.environment.sky.sky_material as ProceduralSkyMaterial
	assert_eq(sky.sky_horizon_color, sky.ground_horizon_color, "no hard horizon line in the background")
	for color: Color in [sky.sky_top_color, sky.sky_horizon_color, sky.ground_bottom_color]:
		assert_true(color.r > color.g and color.g > color.b, "the background gradient stays warm")
		assert_true(color.get_luminance() > 0.15, "the lower background never falls to black")
	rig.free()


func test_scene_instances_do_not_share_mutable_environment_or_sky_resources() -> void:
	var first: Node3D = RIG.instantiate() as Node3D
	var second: Node3D = RIG.instantiate() as Node3D
	var first_env: Environment = (first.get_node("Environment") as WorldEnvironment).environment
	var second_env: Environment = (second.get_node("Environment") as WorldEnvironment).environment
	assert_eq(first_env.get_local_scene(), first)
	assert_eq(second_env.get_local_scene(), second)
	assert_eq(first_env.sky.get_local_scene(), first)
	assert_eq(second_env.sky.get_local_scene(), second)
	assert_eq(first_env.sky.sky_material.get_local_scene(), first)
	assert_eq(second_env.sky.sky_material.get_local_scene(), second)
	assert_true(first_env != second_env)
	assert_true(first_env.sky != second_env.sky)
	assert_true(first_env.sky.sky_material != second_env.sky.sky_material)
	first.free()
	second.free()
