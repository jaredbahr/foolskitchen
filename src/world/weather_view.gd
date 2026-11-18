class_name WeatherView
extends Node3D
## Read-only weather: isolated pavement receivers, deterministic outdoor rain over the whole
## view, splashes and puddles on the street's paving, paths and roofs, lamplight shining on
## the wet ground at night, and the street's own weather (NeighbourhoodDressing.set_weather).
## Rain never falls inside the shop: no streak column touches a built cell or crosses the
## shop's projected volume on screen.

const OUTDOOR_LAYER: int = 1 << 18
const COOL_SWATCH: SwatchDef = preload("res://data/swatches/slate_blue.tres")
const CREAM_SWATCH: SwatchDef = preload("res://data/swatches/cream.tres")
const RAIN_SHADER: Shader = preload("res://src/world/rain.gdshader")
const SPLASH_SHADER: Shader = preload("res://src/world/rain_splash.gdshader")
const PUDDLE_SHADER: Shader = preload("res://src/world/puddle.gdshader")
const REFLECTION_SHADER: Shader = preload("res://src/world/lamp_reflection.gdshader")
## A streak's width and its column's span: from just above the ground to well above the roofs.
const DROP_WIDTH: float = 0.016
const RAIN_TOP: float = 2.1
const RAIN_BOTTOM: float = 0.12
## Columns per second (a drop falls its column about this often), with some spread.
const RAIN_RATE: float = 0.85
## The wind's slant: how far a drop drifts sideways (x, z) per metre it falls.
const WIND: Vector2 = Vector2(0.16, 0.07)
## The rain's columns stand on a world lattice this far apart, or farther when the view is
## wide, so at most MAX_COLUMNS ever fall at once.
const MIN_SPACING: float = 0.42
const MAX_COLUMNS: int = 3200
## Screen tiles (pixels) for the shop's projected volume mask.
const MASK_TILE: float = 8.0
## Puddles and splashes on the street near the shop.
const PUDDLES: int = 11
const SPLASHES: int = 140
const SPLASH_SIZE: float = 0.16
## Lamps whose light shines in the wet street and the puddles (the puddle shader's limit).
const LAMP_LIMIT: int = 6
const REFLECTION_LENGTH: float = 2.2
const REFLECTION_WIDTH: float = 0.38
## The wet sheen's colour by night: the street's warm lamplight.
const NIGHT_SHEEN: Color = Color(0.62, 0.5, 0.36)

## Exact CPU packet sent to MultiMesh; Dummy headless has no transform readback.
var rain_transforms: Array[Transform3D] = []
var rain: MultiMeshInstance3D
var splashes: MultiMeshInstance3D
var puddles: MeshInstance3D
var reflections: MeshInstance3D
var outdoor_light: OmniLight3D
var _view: ShopView
var _receivers: Array[PropView] = []
var _original_colors: Array[Color] = []
var _receiver_meshes: Array[MeshInstance3D] = []
var _original_layers: Array[int] = []
var _columns: Array[Transform3D] = []
var _elapsed: float = 0.0
var _kind: int = -1
var _shown_world: SimWorld
var _shown_dressing: RoomDressing
var _camera_transform: Transform3D = Transform3D()
var _camera_projection: Projection = Projection()
var _rain_material: ShaderMaterial
var _splash_material: ShaderMaterial
var _puddle_material: ShaderMaterial
var _reflection_material: ShaderMaterial
var _lamps: Array[Vector4] = []
var _night: float = 0.0
var _view_dir: Vector2 = Vector2(0.57, -0.82)
var _reflection_dir: Vector2 = Vector2.ZERO


func bind(view: ShopView) -> void:
	# Mask the camera pose drawn THIS frame, after CameraRig (0), before Main (10).
	process_priority = 1
	_restore_receivers()
	_view = view
	_prepare_nodes()
	refresh(true)


func _prepare_nodes() -> void:
	if rain != null:
		return
	rain = MultiMeshInstance3D.new()
	rain.name = "Rain"
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = RAIN_SHADER
	_rain_material.set_shader_parameter(&"tint", Color(COOL_SWATCH.color.lerp(CREAM_SWATCH.color, 0.65), 0.42))
	var instances: MultiMesh = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = _quad(Vector2(-0.5, 0.0), Vector2(0.5, 1.0), false)
	rain.multimesh = instances
	rain.material_override = _rain_material
	add_child(rain)
	splashes = MultiMeshInstance3D.new()
	splashes.name = "Splashes"
	splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash_material = ShaderMaterial.new()
	_splash_material.shader = SPLASH_SHADER
	var rings: MultiMesh = MultiMesh.new()
	rings.transform_format = MultiMesh.TRANSFORM_3D
	rings.use_custom_data = true
	rings.mesh = _quad(Vector2(-0.5, -0.5), Vector2(0.5, 0.5), true)
	splashes.multimesh = rings
	splashes.material_override = _splash_material
	add_child(splashes)
	puddles = MeshInstance3D.new()
	puddles.name = "Puddles"
	puddles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puddle_material = ShaderMaterial.new()
	_puddle_material.shader = PUDDLE_SHADER
	puddles.material_override = _puddle_material
	add_child(puddles)
	reflections = MeshInstance3D.new()
	reflections.name = "LampReflections"
	reflections.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reflection_material = ShaderMaterial.new()
	_reflection_material.shader = REFLECTION_SHADER
	reflections.material_override = _reflection_material
	add_child(reflections)
	outdoor_light = OmniLight3D.new()
	outdoor_light.name = "OutdoorWeatherLight"
	outdoor_light.light_color = COOL_SWATCH.color
	outdoor_light.light_energy = 0.08
	outdoor_light.light_specular = 0.0
	outdoor_light.light_cull_mask = OUTDOOR_LAYER
	outdoor_light.light_bake_mode = Light3D.BAKE_DISABLED
	outdoor_light.shadow_enabled = false
	outdoor_light.omni_range = 20.0
	add_child(outdoor_light)


## A flat quad from `low` to `high`: upright in x, y (a rain streak), or lying in x, z.
## UV runs -1..1 across a lying quad (its centre at 0).
static func _quad(low: Vector2, high: Vector2, lying: bool) -> ArrayMesh:
	var corners: Array[Vector2] = [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for index: int in [0, 1, 2, 0, 2, 3]:
		var corner: Vector2 = corners[index]
		vertices.append(Vector3(corner.x, 0.0, corner.y) if lying else Vector3(corner.x, corner.y, 0.0))
		uvs.append((corner - (low + high) * 0.5) / ((high - low) * 0.5) if lying else corner)
		normals.append(Vector3.UP if lying else Vector3.BACK)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Called after world/terrain/dressing replacement, as well as a forecast change.
func refresh(force: bool = false) -> void:
	if not force and _view != null and _view.world != null and _view.world.weather != null \
			and _shown_world == _view.world and _shown_dressing == _view.room_dressing \
			and _kind == _view.world.weather.kind:
		return
	_prepare_nodes()
	_restore_receivers()
	_columns.clear()
	rain_transforms.clear()
	rain.multimesh.instance_count = 0
	splashes.multimesh.instance_count = 0
	puddles.mesh = null
	reflections.mesh = null
	_lamps.clear()
	_reflection_dir = Vector2.ZERO
	if _view == null or _view.world == null or _view.world.weather == null:
		_shown_world = null
		_shown_dressing = null
		_kind = -1
		outdoor_light.hide()
		_hide_rain()
		_street_weather(WeatherState.Kind.SUNNY)
		return
	_shown_world = _view.world
	_shown_dressing = _view.room_dressing
	_kind = _view.world.weather.kind
	_collect_receivers()
	_apply_outdoor_cue()
	_street_weather(_kind)
	if _kind != WeatherState.Kind.RAIN:
		_hide_rain()
		return
	rain.show()
	splashes.show()
	puddles.show()
	_rebuild_rain()
	_build_ground_water()


func _hide_rain() -> void:
	rain.hide()
	splashes.hide()
	puddles.hide()
	reflections.hide()


func _street_weather(kind: int) -> void:
	var dressing: NeighbourhoodDressing = _view.neighbourhood_dressing if _view != null else null
	if dressing != null and is_instance_valid(dressing):
		dressing.set_weather(kind)


## The light now (after the weather's shading) and how lit the street's lamps are: the wet
## sheen and the puddles mirror the sky's light, and the lamps shine in the wet at night.
func set_light(look: DayLight.Look, night: float) -> void:
	if look == null or _view == null:
		return
	var sky: Color = (look.ambient_color * look.ambient_energy + look.key_color * look.key_energy * 0.6) * 1.9
	_night = clampf(night, 0.0, 1.0)
	# By night the wet ground catches the warm lamps and windows more than the dark sky.
	sky = sky.lerp(NIGHT_SHEEN, _night * 0.7)
	sky.a = 1.0
	var camera: Camera3D = _camera()
	if camera != null:
		var forward: Vector3 = -camera.global_transform.basis.z
		var flat: Vector2 = Vector2(forward.x, forward.z)
		if flat.length() > 0.001:
			_view_dir = flat.normalized()
	var dressing: NeighbourhoodDressing = _view.neighbourhood_dressing
	if dressing != null and is_instance_valid(dressing):
		dressing.set_weather_light(sky, _view_dir)
	if _kind != WeatherState.Kind.RAIN or _puddle_material == null:
		return
	_puddle_material.set_shader_parameter(&"sky", sky)
	_puddle_material.set_shader_parameter(&"view_dir", -_view_dir)
	var lights: PackedVector4Array = PackedVector4Array()
	for lamp: Vector4 in _lamps:
		lights.append(Vector4(lamp.x, lamp.z, 1.4 * _night, 0.0))
	lights.resize(LAMP_LIMIT)
	_puddle_material.set_shader_parameter(&"lights", lights)
	_reflection_material.set_shader_parameter(&"level", _night)
	reflections.visible = _night > 0.02 and not _lamps.is_empty()
	if reflections.visible and not _reflection_dir.is_equal_approx(_view_dir):
		_build_reflections()


func _collect_receivers() -> void:
	if _view.room_dressing == null:
		return
	for child: Node in _view.room_dressing.get_children():
		var prop: PropView = child as PropView
		if prop == null or prop.get_meta(&"kind", &"") != &"pavement":
			continue
		# Recheck the full transformed bounds against the CURRENT bought layout.
		var box: AABB = prop.transform * prop.get_combined_aabb()
		if not _outside_bounds(box):
			continue
		var body: BaseMaterial3D = prop.active_body_material()
		if body == null:
			continue
		_receivers.append(prop)
		_original_colors.append(body.albedo_color)
		for node: Node in prop.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			_receiver_meshes.append(mesh)
			_original_layers.append(mesh.layers)


func _apply_outdoor_cue() -> void:
	var rainy: bool = _kind == WeatherState.Kind.RAIN
	var changed: bool = _kind != WeatherState.Kind.SUNNY
	outdoor_light.visible = changed and not _receivers.is_empty()
	if not changed:
		return
	var center: Vector3 = Vector3.ZERO
	for index: int in range(_receivers.size()):
		var original: Color = _original_colors[index]
		# Rain darkens the shop's own paving like the wet street round it (wet_ground.gdshader).
		var tint: Color = original.lerp(COOL_SWATCH.color, 0.06 if rainy else 0.12)
		tint = tint.darkened(0.18 if rainy else 0.12)
		_receivers[index].set_body_tint(tint)
		center += _receivers[index].position
	for index: int in range(_receiver_meshes.size()):
		_receiver_meshes[index].layers = _original_layers[index] | OUTDOOR_LAYER
	if not _receivers.is_empty():
		outdoor_light.position = center / float(_receivers.size()) + Vector3.UP * 2.0


func _restore_receivers() -> void:
	for index: int in range(_receivers.size()):
		if is_instance_valid(_receivers[index]):
			_receivers[index].set_body_tint(_original_colors[index])
	for index: int in range(_receiver_meshes.size()):
		if is_instance_valid(_receiver_meshes[index]):
			_receiver_meshes[index].layers = _original_layers[index]
	_receivers.clear()
	_original_colors.clear()
	_receiver_meshes.clear()
	_original_layers.clear()


func _outside_bounds(box: AABB) -> bool:
	if _view == null or _view.world == null:
		return false
	var low: Vector2i = GridMath.world_to_cell(box.position + Vector3.ONE * 0.00001)
	var high: Vector2i = GridMath.world_to_cell(box.end - Vector3.ONE * 0.00001)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			if _view.world.grid.terrain(Vector2i(x, y)) != SimGrid.Terrain.OUTSIDE \
					and not _view.world.grid.is_outdoor_floor(Vector2i(x, y)):
				return false
	return true


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## The rain's columns over everything the camera sees (and, without a camera, round the
## grid), each a thin quad turned to the camera and slanted with the wind. A column is
## dropped when it touches a built cell or its projection overlaps the shop's.
func _rebuild_rain() -> void:
	_columns.clear()
	var camera: Camera3D = _camera()
	var area: Rect2 = _rain_area(camera)
	var spacing: float = maxf(MIN_SPACING, sqrt(area.get_area() / float(MAX_COLUMNS)))
	var right: Vector3 = Vector3.RIGHT
	var mask: ProjectionMask = null
	if camera != null:
		_camera_transform = camera.global_transform
		_camera_projection = camera.get_camera_projection()
		right = global_transform.basis.inverse() * camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized() if right.length() > 0.001 else Vector3.RIGHT
		mask = ProjectionMask.new(self, camera, _view.world.grid)
	var height: float = RAIN_TOP - RAIN_BOTTOM
	var basis: Basis = Basis(right * DROP_WIDTH, Vector3(-WIND.x, 1.0, -WIND.y) * height, right.cross(Vector3.UP) * DROP_WIDTH)
	var built: Rect2 = _built_rect()
	var first: Vector2i = Vector2i(floori(area.position.x / spacing), floori(area.position.y / spacing))
	var last: Vector2i = Vector2i(ceili(area.end.x / spacing), ceili(area.end.y / spacing))
	var low_corner: Vector3 = Vector3(minf(0.0, -WIND.x * height), 0.0, minf(0.0, -WIND.y * height))
	var reach: Vector3 = Vector3(absf(WIND.x * height), height, absf(WIND.y * height))
	for y: int in range(first.y, last.y):
		for x: int in range(first.x, last.x):
			# Fixed, bounded index arithmetic is display-only, not an RNG stream.
			var offset: Vector2 = Vector2(NeighbourhoodGround.hash01(x, y, 31), NeighbourhoodGround.hash01(x, y, 47)) * 0.8 + Vector2(0.1, 0.1)
			var point: Vector2 = (Vector2(x, y) + offset) * spacing
			var base: Vector3 = Vector3(point.x, RAIN_BOTTOM, point.y)
			var column: AABB = AABB(base + low_corner - Vector3(DROP_WIDTH, 0.0, DROP_WIDTH), reach + Vector3(DROP_WIDTH, 0.0, DROP_WIDTH) * 2.0)
			if built.has_area() and built.intersects(Rect2(column.position.x, column.position.z, column.size.x, column.size.z)) \
					and not _outside_bounds(column):
				continue
			var xf: Transform3D = Transform3D(basis, base)
			if mask != null and not mask.clear(xf * rain.multimesh.mesh.get_aabb()):
				continue
			_columns.append(xf)
	var count: int = _columns.size()
	rain.multimesh.instance_count = count
	rain_transforms.resize(count)
	for index: int in count:
		var xf: Transform3D = _columns[index]
		rain_transforms[index] = xf
		rain.multimesh.set_instance_transform(index, xf)
		var seed_x: int = roundi(xf.origin.x * 100.0)
		var seed_z: int = roundi(xf.origin.z * 100.0)
		rain.multimesh.set_instance_custom_data(index, Color(NeighbourhoodGround.hash01(seed_x, seed_z, 7),
			RAIN_RATE * (0.85 + 0.3 * NeighbourhoodGround.hash01(seed_x, seed_z, 11)), 0.0, 0.0))
	_update_time()


## The ground the camera sees (on the planes at the rain's foot and top), or the grid with
## a margin when there is no camera; in this node's space (x, z).
func _rain_area(camera: Camera3D) -> Rect2:
	var bounds: Rect2i = _view.world.grid.bounds.grow(8)
	var fallback: Rect2 = Rect2(Vector2(bounds.position) * GridMath.CELL_SIZE, Vector2(bounds.size) * GridMath.CELL_SIZE)
	if camera == null or not camera.is_inside_tree():
		return fallback
	var size: Vector2 = get_viewport().get_visible_rect().size
	var result: Rect2 = Rect2()
	var found: bool = false
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		var origin: Vector3 = to_local(camera.project_ray_origin(corner))
		var direction: Vector3 = global_transform.basis.inverse() * camera.project_ray_normal(corner)
		if absf(direction.y) < 0.01:
			return fallback
		for plane_y: float in [0.0, RAIN_TOP]:
			var hit: Vector3 = origin + direction * ((plane_y - origin.y) / direction.y)
			var point: Vector2 = Vector2(hit.x, hit.z)
			result = result.expand(point) if found else Rect2(point, Vector2.ZERO)
			found = true
	return result.grow(0.5)


## The built (non-outside) cells' bounding rectangle in this node's space (x, z).
func _built_rect() -> Rect2:
	var grid: SimGrid = _view.world.grid
	var result: Rect2 = Rect2()
	var found: bool = false
	for cell: Vector2i in grid.cells():
		if grid.terrain(cell) == SimGrid.Terrain.OUTSIDE or grid.is_outdoor_floor(cell):
			continue
		var rect: Rect2 = Rect2(Vector2(cell) * GridMath.CELL_SIZE, Vector2.ONE * GridMath.CELL_SIZE)
		result = result.merge(rect) if found else rect
		found = true
	return result.grow(0.01)


## The shop's volume as the camera sees it: every built cell's projected box, marked on a
## coarse grid of screen tiles, so a column's projection is checked against a few tiles.
class ProjectionMask extends RefCounted:
	var _owner: Node3D
	var _camera: Camera3D
	var _tiles: Dictionary[Vector2i, bool] = {}
	var _bounds: Rect2 = Rect2()
	var _any: bool = false

	func _init(owner: Node3D, camera: Camera3D, grid: SimGrid) -> void:
		_owner = owner
		_camera = camera
		for cell: Vector2i in grid.cells():
			if grid.terrain(cell) == SimGrid.Terrain.OUTSIDE or grid.is_outdoor_floor(cell):
				continue
			var base: Vector3 = Vector3(cell.x * GridMath.CELL_SIZE, 0.0, cell.y * GridMath.CELL_SIZE)
			var rect: Rect2 = project(AABB(base, Vector3(GridMath.CELL_SIZE, ArtScale.WALL_HEIGHT, GridMath.CELL_SIZE)))
			_bounds = _bounds.merge(rect) if _any else rect
			_any = true
			var low: Vector2i = Vector2i(floori(rect.position.x / WeatherView.MASK_TILE), floori(rect.position.y / WeatherView.MASK_TILE))
			var high: Vector2i = Vector2i(floori(rect.end.x / WeatherView.MASK_TILE), floori(rect.end.y / WeatherView.MASK_TILE))
			for y: int in range(low.y, high.y + 1):
				for x: int in range(low.x, high.x + 1):
					_tiles[Vector2i(x, y)] = true

	func project(box: AABB) -> Rect2:
		var result: Rect2 = Rect2()
		for index: int in range(8):
			var point: Vector2 = _camera.unproject_position(_owner.to_global(box.get_endpoint(index)))
			result = Rect2(point, Vector2.ZERO) if index == 0 else result.expand(point)
		return result.grow(1.0)

	## True when `box` (this node's space) projects clear of the shop's volume.
	func clear(box: AABB) -> bool:
		if not _any:
			return true
		var rect: Rect2 = project(box)
		if not rect.intersects(_bounds):
			return true
		var low: Vector2i = Vector2i(floori(rect.position.x / WeatherView.MASK_TILE), floori(rect.position.y / WeatherView.MASK_TILE))
		var high: Vector2i = Vector2i(floori(rect.end.x / WeatherView.MASK_TILE), floori(rect.end.y / WeatherView.MASK_TILE))
		for y: int in range(low.y, high.y + 1):
			for x: int in range(low.x, high.x + 1):
				if _tiles.has(Vector2i(x, y)):
					return false
		return true


## Puddles and splash rings on the street's paving, paths or roof near the shop.
func _build_ground_water() -> void:
	var dressing: NeighbourhoodDressing = _view.neighbourhood_dressing
	if dressing == null or not is_instance_valid(dressing):
		return
	var to_here: Transform3D = global_transform.affine_inverse() * dressing.get_parent().global_transform \
		if dressing.is_inside_tree() and is_inside_tree() else Transform3D.IDENTITY
	var soup: SurfaceTool = SurfaceTool.new()
	soup.begin(Mesh.PRIMITIVE_TRIANGLES)
	var made: int = 0
	for spot: Vector4 in dressing.wet_spots(PUDDLES, 1, 1.0):
		_puddle(soup, to_here * Vector3(spot.x, spot.y + 0.006, spot.z), spot.w, made)
		made += 1
	if made > 0:
		puddles.mesh = soup.commit()
	var rings: Array[Vector4] = dressing.wet_spots(SPLASHES, 2, 0.0)
	splashes.multimesh.instance_count = rings.size()
	for index: int in rings.size():
		var at: Vector3 = to_here * Vector3(rings[index].x, rings[index].y + 0.008, rings[index].z)
		var size: float = SPLASH_SIZE * (0.7 + 0.6 * NeighbourhoodGround.hash01(index, 3, 19))
		splashes.multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(size, 1.0, size)), at))
		splashes.multimesh.set_instance_custom_data(index, Color(NeighbourhoodGround.hash01(index, 5, 23),
			1.1 + 0.6 * NeighbourhoodGround.hash01(index, 7, 29), 0.0, 0.0))
	# The lamps nearest the shop are the ones in view.
	_lamps.clear()
	var built: Vector2 = _built_rect().get_center()
	for lamp: Vector4 in dressing.lamp_spots():
		var at: Vector3 = to_here * Vector3(lamp.x, lamp.y, lamp.z)
		_lamps.append(Vector4(at.x, at.y, at.z, (to_here * Vector3(lamp.x, lamp.w, lamp.z)).y))
	_lamps.sort_custom(func(a: Vector4, b: Vector4) -> bool:
		var da: float = Vector2(a.x, a.z).distance_squared_to(built)
		var db: float = Vector2(b.x, b.z).distance_squared_to(built)
		return da < db if not is_equal_approx(da, db) else a.x < b.x)
	_lamps.resize(mini(_lamps.size(), LAMP_LIMIT))
	_update_time()


## One puddle: a soft, slightly lopsided blob lying flat at `centre`. UV runs from 0 at its
## middle to 1 at its rim.
func _puddle(soup: SurfaceTool, centre: Vector3, radius: float, index: int) -> void:
	var sides: int = 14
	var stretch: float = 1.0 + 0.6 * NeighbourhoodGround.hash01(index, 1, 61)
	var turn: float = TAU * NeighbourhoodGround.hash01(index, 2, 67)
	var rim: Array[Vector3] = []
	for side: int in sides:
		var angle: float = TAU * float(side) / float(sides)
		var wobble: float = 0.85 + 0.3 * NeighbourhoodGround.hash01(index, side, 71)
		var local: Vector2 = Vector2(cos(angle) * stretch, sin(angle)).rotated(turn) * radius * wobble / sqrt(stretch)
		rim.append(centre + Vector3(local.x, 0.0, local.y))
	for side: int in sides:
		for corner: Array in [[centre, Vector2.ZERO], [rim[side], Vector2(cos(TAU * float(side) / float(sides)), sin(TAU * float(side) / float(sides)))],
				[rim[(side + 1) % sides], Vector2(cos(TAU * float(side + 1) / float(sides)), sin(TAU * float(side + 1) / float(sides)))]]:
			soup.set_normal(Vector3.UP)
			soup.set_uv(corner[1])
			soup.add_vertex(corner[0])


## Each lamp's long warm reflection, lying on the wet ground from under it toward the camera.
func _build_reflections() -> void:
	_reflection_dir = _view_dir
	if _lamps.is_empty():
		reflections.mesh = null
		return
	var soup: SurfaceTool = SurfaceTool.new()
	soup.begin(Mesh.PRIMITIVE_TRIANGLES)
	var toward: Vector3 = Vector3(-_view_dir.x, 0.0, -_view_dir.y)
	var side: Vector3 = toward.cross(Vector3.UP).normalized() * REFLECTION_WIDTH
	for lamp: Vector4 in _lamps:
		var foot: Vector3 = Vector3(lamp.x, lamp.w + 0.012, lamp.z) - toward * 0.15
		var tip: Vector3 = foot + toward * REFLECTION_LENGTH
		var corners: Array[Array] = [[foot - side, Vector2(-1.0, 0.0)], [foot + side, Vector2(1.0, 0.0)],
			[tip + side, Vector2(1.0, 1.0)], [tip - side, Vector2(-1.0, 1.0)]]
		for index: int in [0, 1, 2, 0, 2, 3]:
			soup.set_normal(Vector3.UP)
			soup.set_uv(corners[index][1])
			soup.add_vertex(corners[index][0])
	reflections.mesh = soup.commit()


func _process(delta: float) -> void:
	if rain == null or not rain.visible or _view == null or _view.world == null:
		return
	_elapsed += maxf(delta, 0.0)
	var camera: Camera3D = _camera()
	if camera != null and (camera.global_transform != _camera_transform or camera.get_camera_projection() != _camera_projection):
		_rebuild_rain()
	_update_time()


## The rain's clock: the street's display clock when there is one, so a paused review
## capture always shows the same frame.
func _update_time() -> void:
	var seconds: float = _elapsed
	var dressing: NeighbourhoodDressing = _view.neighbourhood_dressing if _view != null else null
	if dressing != null and is_instance_valid(dressing):
		seconds = dressing.shown_time()
	for material: ShaderMaterial in [_rain_material, _splash_material, _puddle_material, _reflection_material]:
		material.set_shader_parameter(&"rain_time", seconds)


func _exit_tree() -> void:
	_restore_receivers()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore_receivers()
