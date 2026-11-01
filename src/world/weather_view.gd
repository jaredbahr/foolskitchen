class_name WeatherView
extends Node3D
## Read-only weather: isolated pavement receivers and deterministic outdoor rain.

const OUTDOOR_LAYER: int = 1 << 18
const COOL_SWATCH: SwatchDef = preload("res://data/swatches/slate_blue.tres")
const CREAM_SWATCH: SwatchDef = preload("res://data/swatches/cream.tres")
const DROP_WIDTH: float = 0.012
const DROP_LENGTH: float = 0.16
const RAIN_TOP: float = 2.1
const RAIN_BOTTOM: float = 0.12
const RAIN_SPEED: float = 1.6
const RAIN_MARGIN_CELLS: int = 8

## Exact CPU packet sent to MultiMesh; Dummy headless has no transform readback.
var rain_transforms: Array[Transform3D] = []
var rain: MultiMeshInstance3D
var outdoor_light: OmniLight3D
var _view: ShopView
var _receivers: Array[PropView] = []
var _original_colors: Array[Color] = []
var _receiver_meshes: Array[MeshInstance3D] = []
var _original_layers: Array[int] = []
var _columns: Array[Vector2] = []
var _elapsed: float = 0.0
var _kind: int = -1
var _shown_world: SimWorld
var _shown_dressing: RoomDressing
var _camera_transform: Transform3D = Transform3D()
var _camera_projection: Projection = Projection()


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
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(DROP_WIDTH, DROP_LENGTH, DROP_WIDTH)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COOL_SWATCH.color.lerp(CREAM_SWATCH.color, 0.65)
	mesh.material = material
	var instances: MultiMesh = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	rain.multimesh = instances
	add_child(rain)
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
	if _view == null or _view.world == null or _view.world.weather == null:
		_shown_world = null
		_shown_dressing = null
		_kind = -1
		outdoor_light.hide()
		rain.hide()
		return
	_shown_world = _view.world
	_shown_dressing = _view.room_dressing
	_kind = _view.world.weather.kind
	_collect_receivers()
	_apply_outdoor_cue()
	rain.visible = _kind == WeatherState.Kind.RAIN
	if rain.visible:
		_rebuild_rain()


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
		var tint: Color = original.lerp(COOL_SWATCH.color, 0.24 if rainy else 0.12)
		tint = tint.darkened(0.24 if rainy else 0.12)
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
			if _view.world.grid.terrain(Vector2i(x, y)) != SimGrid.Terrain.OUTSIDE:
				return false
	return true


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _rebuild_rain() -> void:
	_columns.clear()
	var camera: Camera3D = _camera()
	var occupied: Array[Rect2] = []
	if camera != null:
		_camera_transform = camera.global_transform
		_camera_projection = camera.get_camera_projection()
		for cell: Vector2i in _view.world.grid.cells():
			if _view.world.grid.terrain(cell) == SimGrid.Terrain.OUTSIDE:
				continue
			var base: Vector3 = Vector3(cell.x * GridMath.CELL_SIZE, 0.0, cell.y * GridMath.CELL_SIZE)
			occupied.append(_screen_rect(camera, AABB(base, Vector3(GridMath.CELL_SIZE, ArtScale.WALL_HEIGHT, GridMath.CELL_SIZE))))
	var area: Rect2i = _view.world.grid.bounds.grow(RAIN_MARGIN_CELLS)
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			# Fixed, bounded index arithmetic is display-only, not an RNG stream.
			var offset: Vector2 = Vector2(0.2 + float(posmod(x * 7 + y * 11, 7)) * 0.1,
				0.2 + float(posmod(x * 13 + y * 3, 7)) * 0.1)
			var point: Vector2 = (Vector2(x, y) + offset) * GridMath.CELL_SIZE
			var column: AABB = AABB(Vector3(point.x - DROP_WIDTH * 0.5, RAIN_BOTTOM - DROP_LENGTH * 0.5, point.y - DROP_WIDTH * 0.5),
				Vector3(DROP_WIDTH, RAIN_TOP - RAIN_BOTTOM + DROP_LENGTH, DROP_WIDTH))
			if not _outside_bounds(column):
				continue
			if camera != null and not _clear_projection(camera, column, occupied):
				continue
			_columns.append(point)
	rain.multimesh.instance_count = _columns.size()
	_update_drops()


## A full-height column must not overlap the projected building volume. This
## also protects the interior when cutaway/down walls cannot occlude rain.
func _clear_projection(camera: Camera3D, column: AABB, occupied: Array[Rect2]) -> bool:
	var projected: Rect2 = _screen_rect(camera, column)
	for rectangle: Rect2 in occupied:
		if projected.intersects(rectangle):
			return false
	return true


func _screen_rect(camera: Camera3D, box: AABB) -> Rect2:
	var result: Rect2 = Rect2()
	for index: int in range(8):
		var point: Vector2 = camera.unproject_position(to_global(box.get_endpoint(index)))
		result = Rect2(point, Vector2.ZERO) if index == 0 else result.expand(point)
	return result.grow(1.0)


func _process(delta: float) -> void:
	if rain == null or not rain.visible or _view == null or _view.world == null:
		return
	_elapsed += maxf(delta, 0.0)
	var camera: Camera3D = _camera()
	if camera != null and (camera.global_transform != _camera_transform or camera.get_camera_projection() != _camera_projection):
		_rebuild_rain()
	_update_drops()


func _update_drops() -> void:
	rain_transforms.resize(_columns.size())
	var travel: float = RAIN_TOP - RAIN_BOTTOM
	for index: int in range(_columns.size()):
		var column: Vector2 = _columns[index]
		var phase: float = float(posmod(roundi(column.x * 100.0) * 17 + roundi(column.y * 100.0) * 31, 997)) / 997.0
		var height: float = RAIN_TOP - fposmod(_elapsed * RAIN_SPEED + phase * travel, travel)
		rain_transforms[index] = Transform3D(Basis.IDENTITY, Vector3(column.x, height, column.y))
		rain.multimesh.set_instance_transform(index, rain_transforms[index])


func _exit_tree() -> void:
	_restore_receivers()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore_receivers()
