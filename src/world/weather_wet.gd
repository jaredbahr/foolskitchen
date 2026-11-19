class_name WeatherWet
extends RefCounted
## Puts the day's weather on the neighbourhood's own meshes by swapping materials, never
## the meshes: rain wets the ground, paths, roads, roofs and decks (wet_ground.gdshader:
## darker, a touch richer and faintly glossy; grass only a touch darker), and an overcast
## sky fades the baked ground shadows. Every swap is recorded and undone exactly, so a
## sunny day shows the very materials it always had. View-only, no random draws.

const WET_SHADER: Shader = preload("res://src/world/wet_ground.gdshader")
## Only batched scenery this wide (metres, x or z) takes the rain: the ground, the
## buildings, the trees. Small moving things (people, animals, birds) keep their look.
const MIN_SPAN: float = 1.5
## Plain-coloured street meshes (road, paving, kerbs) take the rain only under these names.
const PAVED_GROUPS: Array[StringName] = [&"Road", &"Pavement", &"Kerbs", &"FarStreet"]
## How much darker soaked ground gets by day (wet_ground.gdshader's default).
const DARKEN: float = 0.27
const RENDER_MODE_LINE: String = "render_mode vertex_lighting, specular_disabled, shadows_disabled;"

## What a swap replaced: the node, the surface (-1 for material_override) and the old value.
var _swaps: Array[Array] = []
var _kind: int = WeatherState.Kind.SUNNY
## Variant shaders by render modes, and the wet and faded materials made, by key.
var _shaders: Dictionary[String, Shader] = {}
var _wet: Dictionary[String, ShaderMaterial] = {}
var _faded: Dictionary[Material, Material] = {}
var _sheen_color: Color = Color(0.6, 0.66, 0.75)
var _view_dir: Vector2 = Vector2(0.57, -0.82)
var _wetness: float = 1.0
var _darken: float = DARKEN


func kind() -> int:
	return _kind


## How many surfaces currently show weather materials (0 on a sunny day).
func swap_count() -> int:
	return _swaps.size()


## Undoes every swap, then wets (or fades) everything under `root` for `kind`.
func apply(root: Node, kind_value: int) -> void:
	restore()
	_faded.clear()
	_kind = kind_value
	if root == null or _kind == WeatherState.Kind.SUNNY:
		return
	_visit(root, false)


## Puts every swapped surface back as it was.
func restore() -> void:
	for swap: Array in _swaps:
		var node: GeometryInstance3D = swap[0] as GeometryInstance3D if is_instance_valid(swap[0]) else null
		if node == null:
			continue
		var surface: int = swap[1]
		if surface < 0:
			node.material_override = swap[2]
		else:
			(node as MeshInstance3D).set_surface_override_material(surface, swap[2])
	_swaps.clear()


## The wet sheen's colour (the sky's light now), the camera's forward on the ground and how
## much darker soaked ground gets (less by night, so the dark street still reads).
func set_light(sheen_color: Color, view_dir: Vector2, darken: float = DARKEN) -> void:
	if sheen_color.is_equal_approx(_sheen_color) and view_dir.is_equal_approx(_view_dir) and is_equal_approx(darken, _darken):
		return
	_sheen_color = sheen_color
	_view_dir = view_dir
	_darken = darken
	for material: ShaderMaterial in _wet.values():
		material.set_shader_parameter(&"sheen_color", _sheen_color)
		material.set_shader_parameter(&"view_dir", _view_dir)
		material.set_shader_parameter(&"darken", _darken)


func wet_materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	result.assign(_wet.values())
	return result


func _visit(node: Node, paved: bool) -> void:
	if node is PersonView:
		return
	var inside_paved: bool = paved or PAVED_GROUPS.has(StringName(node.name))
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		_wet_mesh(mesh, inside_paved)
	for child: Node in node.get_children():
		_visit(child, inside_paved)


func _wet_mesh(node: MeshInstance3D, paved: bool) -> void:
	var box: AABB = node.get_aabb()
	var wide: bool = maxf(box.size.x, box.size.z) >= MIN_SPAN
	var shadow: bool = String(node.name).contains("Shadow") or node.name == &"Shade"
	if node.material_override != null:
		var replacement: Material = _replacement(node.material_override, wide, paved, shadow)
		if replacement != null:
			_swaps.append([node, -1, node.material_override])
			node.material_override = replacement
		return
	for surface: int in node.mesh.get_surface_count():
		var material: Material = node.get_active_material(surface)
		var replacement: Material = _replacement(material, wide, paved, shadow)
		if replacement != null:
			_swaps.append([node, surface, node.get_surface_override_material(surface)])
			node.set_surface_override_material(surface, replacement)


## `shadow`: the mesh is a baked shadow (by its name), which only fades.
func _replacement(material: Material, wide: bool, paved: bool, shadow: bool) -> Material:
	var standard: StandardMaterial3D = material as StandardMaterial3D
	if standard == null:
		return null
	var rainy: bool = _kind == WeatherState.Kind.RAIN
	if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		# A baked shadow (vertex alpha): fainter under an overcast sky. Glows keep their look.
		if not shadow or not standard.vertex_color_use_as_albedo:
			return null
		return _faded_shadow(standard)
	if not rainy or standard.emission_enabled or standard.albedo_texture != null:
		return null
	if standard.vertex_color_use_as_albedo:
		if not wide or standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return null
		return _wet_material(standard, false)
	if paved:
		return _wet_material(standard, true)
	return null


func _faded_shadow(source: StandardMaterial3D) -> Material:
	if _faded.has(source):
		return _faded[source]
	var faded: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	faded.albedo_color.a = source.albedo_color.a * WeatherLook.baked_shadow(_kind)
	_faded[source] = faded
	return faded


func _wet_material(source: StandardMaterial3D, flat_colour: bool) -> ShaderMaterial:
	var per_vertex: bool = source.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX
	var key: String = "%s|%s|%s|%d|%s" % [flat_colour, per_vertex, source.disable_receive_shadows, source.cull_mode,
		source.albedo_color.to_html() if flat_colour else ""]
	if _wet.has(key):
		return _wet[key]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _shader(flat_colour, per_vertex, source.disable_receive_shadows, source.cull_mode)
	material.set_shader_parameter(&"wet", _wetness)
	material.set_shader_parameter(&"sheen_color", _sheen_color)
	material.set_shader_parameter(&"view_dir", _view_dir)
	material.set_shader_parameter(&"darken", _darken)
	if flat_colour:
		material.set_shader_parameter(&"base_color", source.albedo_color)
	_wet[key] = material
	return material


## The wet shader with the source material's own lighting, shadows and culling, and, for a
## plain-coloured mesh, its colour from a uniform instead of the vertices.
func _shader(flat_colour: bool, per_vertex: bool, no_shadows: bool, cull: int) -> Shader:
	var key: String = "%s|%s|%s|%d" % [flat_colour, per_vertex, no_shadows, cull]
	if _shaders.has(key):
		return _shaders[key]
	var modes: Array[String] = ["specular_disabled"]
	if per_vertex:
		modes.append("vertex_lighting")
	if no_shadows:
		modes.append("shadows_disabled")
	modes.append(["cull_back", "cull_front", "cull_disabled"][clampi(cull, 0, 2)])
	var code: String = WET_SHADER.code.replace(RENDER_MODE_LINE, "render_mode %s;" % ", ".join(modes))
	if flat_colour:
		code = code.replace("shader_type spatial;", "shader_type spatial;\n#define FLAT_COLOUR")
	var shader: Shader = Shader.new()
	shader.code = code
	_shaders[key] = shader
	return shader
