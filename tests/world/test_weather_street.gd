extends TestCase
## The weather's look on every street: cloudy and rain shade the light (softer, dimmer,
## cooler; a sunny look is returned untouched), rain wets each preset's street (wet
## materials, puddles, a rough grey sea, thicker city haze, swaying wheat, fewer people
## out), cloudy only fades the baked shadows, and sunny puts back exactly what was built.
## Everything is deterministic.

const DRESSING: PackedScene = preload("res://src/world/neighbourhood_dressing.tscn")
const DAY_LIGHT: DayLightTuning = preload("res://data/look/day_light.tres")
const RESERVE: Rect2i = Rect2i(-2, -2, 12, 9)
const PRESETS: Array[String] = ["res://data/streets/starter.tres", "res://data/streets/seaside.tres",
	"res://data/streets/promenade.tres", "res://data/streets/woodland.tres", "res://data/streets/country.tres",
	"res://data/streets/rooftop.tres", "res://data/streets/cliff.tres"]
## Day, the golden dusk and night (data/look/day_light.tres minutes).
const MINUTES: Array[float] = [780.0, 1230.0, 1410.0]

var _viewport: SubViewport


func after_each() -> void:
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	NeighbourhoodDressing.clear_mesh_cache()


func _host() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)


func _grid() -> SimGrid:
	return SimGrid.from_ascii(PackedStringArray([
		"########", "#......#", "#......#", "#......#", "#......#", "#......#", "###..###", "   EE   "]))


func _dressing(path: String) -> NeighbourhoodDressing:
	var dressing: NeighbourhoodDressing = DRESSING.instantiate() as NeighbourhoodDressing
	_viewport.add_child(dressing)
	dressing.set_process(false)
	dressing.use_preset(load(path) as StreetPreset)
	var grid: SimGrid = _grid()
	dressing.configure(grid, RESERVE, [{"cells": grid.entries().duplicate(), "normal": Vector2i.DOWN}] as Array[Dictionary],
		[] as Array[AABB])
	return dressing


func _free(dressing: NeighbourhoodDressing) -> void:
	dressing.get_parent().remove_child(dressing)
	dressing.free()


## Every mesh under the dressing: its path, vertex count and active materials.
func _snapshot(dressing: NeighbourhoodDressing) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in dressing.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var entry: Array = [mesh.material_override]
		if mesh.mesh != null:
			for surface: int in mesh.mesh.get_surface_count():
				entry.append((mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
				entry.append(mesh.get_active_material(surface))
		result[String(dressing.get_path_to(mesh))] = entry
	return result


func _looks_equal(a: DayLight.Look, b: DayLight.Look) -> bool:
	return a.key_color == b.key_color and a.key_energy == b.key_energy and a.key_pitch == b.key_pitch \
		and a.fill_energy == b.fill_energy and a.ambient_color == b.ambient_color and a.ambient_energy == b.ambient_energy \
		and a.sky_top == b.sky_top and a.sky_horizon == b.sky_horizon and a.sky_ground == b.sky_ground \
		and a.glow == b.glow and a.interior_energy == b.interior_energy


func test_sunny_light_is_untouched_and_an_overcast_sky_is_softer_dimmer_and_cooler() -> void:
	for minute: float in MINUTES:
		var clear: DayLight.Look = DayLight.sample(minute, DAY_LIGHT)
		assert_true(WeatherLook.apply(clear, WeatherState.Kind.SUNNY) == clear, "sunny returns the very same look")
		var cloudy: DayLight.Look = WeatherLook.apply(clear, WeatherState.Kind.CLOUDY)
		var rain: DayLight.Look = WeatherLook.apply(clear, WeatherState.Kind.RAIN)
		assert_true(cloudy.key_energy < clear.key_energy and rain.key_energy < cloudy.key_energy, "cloud and rain dim the sun")
		assert_true(cloudy.fill_energy > clear.fill_energy and rain.fill_energy > cloudy.fill_energy, "the soft fill rises")
		assert_true(rain.ambient_color.b - rain.ambient_color.r > clear.ambient_color.b - clear.ambient_color.r, "the ambient cools")
		assert_true(rain.ambient_energy >= clear.ambient_energy, "the ambient keeps the scene readable")
		assert_true(rain.sky_horizon.get_luminance() <= clear.sky_horizon.get_luminance() + 0.01, "the sky never brightens")
		assert_eq(rain.interior_energy, clear.interior_energy, "the shop's own lights follow the clock")
		assert_eq(rain.glow, clear.glow)
		assert_true(_looks_equal(rain, WeatherLook.apply(DayLight.sample(minute, DAY_LIGHT), WeatherState.Kind.RAIN)), "deterministic")
	assert_eq(WeatherLook.shadow_opacity(WeatherState.Kind.SUNNY), 1.0)
	assert_true(WeatherLook.shadow_opacity(WeatherState.Kind.CLOUDY) < 1.0)
	assert_true(WeatherLook.shadow_opacity(WeatherState.Kind.RAIN) < WeatherLook.shadow_opacity(WeatherState.Kind.CLOUDY))


func test_rain_wets_every_street_and_sunny_puts_back_exactly_what_was_built() -> void:
	await _host()
	for path: String in PRESETS:
		var dressing: NeighbourhoodDressing = _dressing(path)
		var built: Dictionary = _snapshot(dressing)
		assert_eq(int(dressing.wet_state()["swaps"]), 0, "%s: a new street is dry" % path)
		dressing.set_weather(WeatherState.Kind.RAIN)
		var wet: Dictionary = dressing.wet_state()
		assert_true(int(wet["swaps"]) > 0, "%s: the rain wets the street" % path)
		var materials: Array = wet["materials"]
		assert_false(materials.is_empty(), "%s: wet materials are in use" % path)
		for material: ShaderMaterial in materials:
			assert_eq(float(material.get_shader_parameter(&"wet")), 1.0)
		assert_true(_snapshot(dressing) != built, "%s: the rain changed the street's materials" % path)
		var puddles: Array[Vector4] = dressing.wet_spots(11, 1, 1.0)
		assert_false(puddles.is_empty(), "%s: the rain leaves puddles" % path)
		assert_eq(dressing.wet_spots(11, 1, 1.0), puddles, "%s: the puddles are the same every time" % path)
		for spot: Vector4 in puddles:
			var cell: Vector2i = GridMath.world_to_cell(Vector3(spot.x, 0.0, spot.z))
			assert_false(_grid().bounds.has_point(cell) and _grid().terrain(cell) != SimGrid.Terrain.OUTSIDE,
				"%s: no puddle inside the shop" % path)
		dressing.set_weather(WeatherState.Kind.CLOUDY)
		dressing.set_weather(WeatherState.Kind.SUNNY)
		assert_eq(int(dressing.wet_state()["swaps"]), 0, "%s: a sunny street is dry again" % path)
		assert_eq(_snapshot(dressing), built, "%s: sunny shows exactly what was built" % path)
		_free(dressing)


func test_cloudy_only_fades_the_baked_shadows() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing("res://data/streets/starter.tres")
	dressing.set_weather(WeatherState.Kind.CLOUDY)
	assert_true(int(dressing.wet_state()["swaps"]) > 0, "the baked shadows fade")
	for node: Node in dressing.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			assert_false(mesh.get_active_material(surface) is ShaderMaterial and (mesh.get_active_material(surface) as ShaderMaterial).shader != null \
				and (mesh.get_active_material(surface) as ShaderMaterial).shader.code.contains("uniform float wet"),
				"nothing is wet on a dry cloudy day")
	_free(dressing)


func test_each_place_takes_its_own_weather() -> void:
	await _host()
	var promenade: NeighbourhoodDressing = _dressing("res://data/streets/promenade.tres")
	var shore: NeighbourhoodShore = promenade.shore()
	assert_not_null(shore)
	for row: Array in [[WeatherState.Kind.SUNNY, 0.0, true], [WeatherState.Kind.CLOUDY, 0.4, true], [WeatherState.Kind.RAIN, 1.0, false]]:
		promenade.set_weather(row[0])
		assert_almost_eq(float(shore.sea_material.get_shader_parameter(&"storm")), float(row[1]), 0.0001, "the sea's roughness")
		assert_eq(shore.beach_open(), row[2], "the beach empties and its umbrellas are furled in the rain")
		if row[0] == WeatherState.Kind.RAIN:
			var out: int = 0
			for gull: Node3D in shore.gulls:
				out += 1 if gull.visible else 0
			assert_true(out < shore.gulls.size(), "fewer gulls in the rain")
	_free(promenade)
	var cliff_street: NeighbourhoodDressing = _dressing("res://data/streets/cliff.tres")
	cliff_street.set_weather(WeatherState.Kind.RAIN)
	assert_eq(float(cliff_street.cliff().sea_material.get_shader_parameter(&"storm")), 1.0, "the cliff's sea runs rough")
	cliff_street.set_weather(WeatherState.Kind.SUNNY)
	assert_eq(float(cliff_street.cliff().sea_material.get_shader_parameter(&"storm")), 0.0)
	_free(cliff_street)
	var roof: NeighbourhoodDressing = _dressing("res://data/streets/rooftop.tres")
	roof.set_weather(WeatherState.Kind.RAIN)
	assert_eq(float(roof.rooftop()._city_material.get_shader_parameter(&"murk")), 1.0, "the city's haze thickens")
	assert_false(roof.lamp_spots().is_empty(), "the roof's lamps shine on the wet roof")
	roof.set_weather(WeatherState.Kind.SUNNY)
	assert_eq(float(roof.rooftop()._city_material.get_shader_parameter(&"murk")), 0.0)
	_free(roof)
	var lane: NeighbourhoodDressing = _dressing("res://data/streets/country.tres")
	lane.set_weather(WeatherState.Kind.RAIN)
	var reach: float = float(lane.country()._wheat_material.get_shader_parameter(&"reach"))
	lane.set_weather(WeatherState.Kind.SUNNY)
	assert_true(reach > float(lane.country()._wheat_material.get_shader_parameter(&"reach")), "the wheat sways more in the rain")
	_free(lane)


func test_fewer_people_are_out_in_the_rain() -> void:
	await _host()
	var dressing: NeighbourhoodDressing = _dressing("res://data/streets/starter.tres")
	dressing.set_review_time(7.0)
	var visible: Array[int] = []
	for kind: int in [WeatherState.Kind.SUNNY, WeatherState.Kind.RAIN]:
		dressing.set_weather(kind)
		var count: int = 0
		for person: PersonView in dressing.pedestrians:
			count += 1 if person.visible else 0
		visible.append(count)
	assert_true(visible[1] > 0 and visible[1] < visible[0], "some stay in, but the street is never empty")
	dressing.set_weather(WeatherState.Kind.SUNNY)
	_free(dressing)
