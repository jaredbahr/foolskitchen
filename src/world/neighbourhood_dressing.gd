class_name NeighbourhoodDressing
extends Node3D
## A bounded, read-only street view. No simulation agents, random draws,
## physics, save state, lights or camera control belong to this presenter.

const PERSON: PackedScene = preload("res://assets/people/person.tscn")
const MADE_ROOT: String = "res://assets/made/neighbourhood/"
const ASSETS: Array[String] = ["road_segment", "crossing_segment", "kerb_segment", "shopfront",
	"house_body", "gable_roof", "compact_car", "street_lamp"]
const GUEST_IDS: Array[int] = [1, 4, 6]
const PHASES: Array[float] = [0.0, 0.33, 0.67]
const WALK_LANES: Array[float] = [2.755, 6.455, 7.555]
const WALK_SPEED: float = 0.65
const WALK_HALF: float = 0.50
const WALK_BOTTOM: float = -0.05
const WALK_TOP: float = 1.10
const MARGIN: float = 0.05
const SIDE_MARGIN: float = 6.0
const BUILDING_GAP: float = 1.25
const CAR_SPEED: float = 2.8
const CAR_REST: float = 14.0
const CAR_LANE: float = 4.005
const PAVING_START: float = 0.005
const PAVING_DEPTH: float = 3.30
const ROAD_START: float = 3.405
const ROAD_END: float = 5.805
const FAR_START: float = 5.905
const FAR_DEPTH: float = 2.20

var static_root: Node3D
var pedestrians: Array[PersonView] = []
var car: PropView
var display_seconds: float:
	get:
		return _display_seconds
var build_error: String = ""
var _display_seconds: float = 0.0
var _review_time: float = -1.0
var _grid: SimGrid
var _maximum_lot: Rect2i
var _frontages: Array[Dictionary] = []
var _native_pavement: Array[AABB] = []
var _geometry_key: Array = []
var _scenes: Dictionary[String, PackedScene] = {}
var _groups: Dictionary[String, Node3D] = {}
var _actors_root: Node3D
var _traffic_root: Node3D
var _players: Array[AnimationPlayer] = []
var _animation_lengths: Array[float] = []
var _directions: Array[Vector3] = []
var _routes: Array[Vector2] = []
var _pedestrian_sweeps: Array[AABB] = []
var _door_approaches: Array[AABB] = []
var _static_meshes: Array[MeshInstance3D] = []
var _frame: Transform3D = Transform3D.IDENTITY
var _outward: Vector3 = Vector3.FORWARD
var _tangent: Vector3 = Vector3.RIGHT
var _reserve: AABB
var _local_reserve: AABB
var _near_pavement: AABB
var _road: AABB
var _far_pavement: AABB
var _car_sweep: AABB
var _car_route: Vector2 = Vector2.ZERO
var _car_bounds: AABB
var _car_rotation: Basis = Basis.IDENTITY
var _street_half: float = 0.0
var _shift: float = 0.0
var _paving_top: float = 0.055
var _generation: int = 0
var _configured: bool = false


func _init() -> void:
	name = "NeighbourhoodDressing"


func _ready() -> void:
	_initialize_players()
	_apply_time(_effective_time())


func configure(grid: SimGrid, maximum_lot: Rect2i, frontage_runs: Array[Dictionary],
		native_pavement: Array[AABB]) -> void:
	_grid = grid
	_maximum_lot = maximum_lot
	_frontages.assign(frontage_runs.duplicate(true))
	_native_pavement = native_pavement.duplicate()
	rebuild()


func rebuild() -> void:
	_ensure_roots()
	var built: Array[Vector2i] = []
	if _grid != null:
		for cell: Vector2i in _grid.cells():
			if _grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
				built.append(cell)
	var key: Array = [_grid.get_instance_id() if _grid != null else 0, _maximum_lot,
		_frontages, _native_pavement, built]
	if key == _geometry_key:
		return
	_geometry_key = key.duplicate(true)
	_clear_static()
	_configured = false
	build_error = ""
	if _grid == null or not _select_frame():
		_hide_actors()
		return
	if not _load_scenes():
		_hide_actors()
		return
	var area: Rect2i = _maximum_lot
	for cell: Vector2i in built:
		area = area.merge(Rect2i(cell, Vector2i.ONE)) if area.has_area() else Rect2i(cell, Vector2i.ONE)
	_reserve = AABB(Vector3(area.position.x * GridMath.CELL_SIZE, 0.0, area.position.y * GridMath.CELL_SIZE),
		Vector3(area.size.x * GridMath.CELL_SIZE, ArtScale.WALL_HEIGHT, area.size.y * GridMath.CELL_SIZE))
	_local_reserve = _frame.affine_inverse() * _reserve
	_shift = maxf(0.0, _local_reserve.end.z)
	_build_approaches()
	var paving: PropView = RoomDressing.make_asset(RoomDressing.PAVEMENT, "PavingSource", false, true)
	if paving == null:
		build_error = "Pavement source is unavailable"
		_hide_actors()
		return
	var paving_box: AABB = paving.get_combined_aabb()
	_paving_top = paving_box.end.y
	for bounds: AABB in _native_pavement:
		if bounds.size.y >= paving_box.size.y * 0.9:
			_paving_top = bounds.end.y
			break
	var road_prop: PropView = _made_prop("road_segment")
	var road_box: AABB = road_prop.get_combined_aabb()
	var count: int = ceili((maxf(absf(_local_reserve.position.x), absf(_local_reserve.end.x)) + SIDE_MARGIN) * 2.0 / road_box.size.x)
	if count % 2 == 0:
		count += 1
	_street_half = float(count) * road_box.size.x * 0.5
	_build_road(road_prop, road_box, count)
	road_prop.free()
	_build_paving(paving, paving_box, PAVING_START, PAVING_DEPTH, "NearPavement")
	_build_paving(paving, paving_box, FAR_START, FAR_DEPTH, "FarPavement")
	paving.clear_body_tint()
	paving.free()
	_build_kerbs(road_box.size.x, count)
	_build_buildings()
	_ensure_actors()
	_build_routes()
	_build_lamps()
	_initialize_players()
	_configured = build_error.is_empty()
	static_root.visible = _configured
	_actors_root.visible = _configured
	_traffic_root.visible = _configured
	_apply_time(_effective_time())


func _ensure_roots() -> void:
	if static_root != null:
		return
	static_root = Node3D.new()
	static_root.name = "Static"
	add_child(static_root)
	for label: String in ["Road", "Pavement", "Kerbs", "Buildings", "StreetLamps"]:
		var group: Node3D = Node3D.new()
		group.name = label
		static_root.add_child(group)
		_groups[label] = group
	_actors_root = Node3D.new()
	_actors_root.name = "PassersBy"
	add_child(_actors_root)
	_traffic_root = Node3D.new()
	_traffic_root.name = "Traffic"
	add_child(_traffic_root)


func _clear_static() -> void:
	_static_meshes.clear()
	for group: Node3D in _groups.values():
		for child: Node in group.get_children():
			group.remove_child(child)
			child.free()
	_routes.clear()
	_pedestrian_sweeps.clear()
	_door_approaches.clear()
	_frame = Transform3D.IDENTITY
	_outward = Vector3.FORWARD
	_tangent = Vector3.RIGHT
	_reserve = AABB()
	_local_reserve = AABB()
	_near_pavement = AABB()
	_road = AABB()
	_far_pavement = AABB()
	_car_sweep = AABB()
	_car_route = Vector2.ZERO
	_shift = 0.0
	_generation += 1


func _hide_actors() -> void:
	static_root.hide()
	_actors_root.hide()
	_traffic_root.hide()
	if car != null:
		car.hide()


func _select_frame() -> bool:
	for run: Dictionary in _frontages:
		var normal: Variant = run.get("normal")
		var cells: Array = run.get("cells", [])
		if not normal is Vector2i or absi(normal.x) + absi(normal.y) != 1 or cells.is_empty():
			continue
		var center: Vector3 = Vector3.ZERO
		var usable: bool = true
		for cell: Variant in cells:
			if not cell is Vector2i:
				usable = false
				break
			center += GridMath.cell_to_world(cell)
		if not usable:
			continue
		center /= float(cells.size())
		_outward = Vector3(normal.x, 0.0, normal.y)
		_tangent = Vector3(normal.y, 0.0, -normal.x)
		_frame = Transform3D(Basis(_tangent, Vector3.UP, _outward), center + _outward * GridMath.CELL_SIZE * 0.5)
		return true
	return false


func _load_scenes() -> bool:
	for asset: String in ASSETS:
		if _scenes.has(asset):
			continue
		var path: String = MADE_ROOT + asset + ".glb"
		if not ResourceLoader.exists(path, "PackedScene"):
			build_error = "Neighbourhood model is unavailable: " + asset
			return false
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			build_error = "Neighbourhood model could not load: " + asset
			return false
		_scenes[asset] = scene
	return true


func _made_prop(asset: String) -> PropView:
	var prop: PropView = PropView.new()
	prop.name = asset.to_pascal_case()
	var part: Node3D = Node3D.new()
	part.name = "Body"
	var art: Node3D = Node3D.new()
	art.name = "Art"
	# Made models already face -Z; only the shared uniform scale is applied.
	art.add_child(_scenes[asset].instantiate())
	part.add_child(art)
	prop.add_child(part)
	prop.prepare()
	return prop


func _placement(u: float, y: float, v: float, yaw: float = 0.0) -> Transform3D:
	return _frame * Transform3D(Basis(Vector3.UP, yaw), Vector3(u, y, _shift + v))


func _add_batch(batch: NeighbourhoodMeshBatch, label: String, category: String) -> void:
	if batch.triangles == 0:
		return
	var mesh: MeshInstance3D = batch.finish(label)
	_groups[category].add_child(mesh)
	_static_meshes.append(mesh)


func _build_road(source: PropView, bounds: AABB, count: int) -> void:
	var crossing: PropView = _made_prop("crossing_segment")
	var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
	for index: int in count:
		var u: float = (float(index) - float(count - 1) * 0.5) * bounds.size.x
		batch.add_prop(crossing if index == (count >> 1) else source, _placement(u, -bounds.end.y, (ROAD_START + ROAD_END) * 0.5))
	_add_batch(batch, "Road", "Road")
	crossing.free()
	_road = _frame * AABB(Vector3(-_street_half, -bounds.size.y, _shift + ROAD_START),
		Vector3(_street_half * 2.0, bounds.size.y, ROAD_END - ROAD_START))


func _build_paving(source: PropView, bounds: AABB, start: float, depth: float, label: String) -> void:
	var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
	var holes: Array[AABB] = _native_pavement.duplicate()
	holes.append(_reserve)
	var columns: int = ceili(_street_half * 2.0 / bounds.size.x)
	var rows: int = roundi(depth / bounds.size.z)
	for row: int in rows:
		for column: int in columns:
			var u: float = -_street_half + (float(column) + 0.5) * bounds.size.x
			var v: float = start + (float(row) + 0.5) * bounds.size.z
			batch.add_prop(source, _placement(u, _paving_top - bounds.end.y, v, PI), holes)
	_add_batch(batch, label, "Pavement")
	var box: AABB = _frame * AABB(Vector3(-_street_half, _paving_top - bounds.size.y, _shift + start),
		Vector3(_street_half * 2.0, bounds.size.y, depth))
	if label == "NearPavement":
		_near_pavement = box
	else:
		_far_pavement = box


func _build_kerbs(width: float, count: int) -> void:
	var prop: PropView = _made_prop("kerb_segment")
	for side: int in 2:
		var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
		for index: int in count:
			var u: float = (float(index) - float(count - 1) * 0.5) * width
			batch.add_prop(prop, _placement(u, 0.0, 3.355 if side == 0 else 5.855))
		_add_batch(batch, "NearKerb" if side == 0 else "FarKerb", "Kerbs")
	prop.free()


func _build_buildings() -> void:
	for index: int in 5:
		var body: PropView = _made_prop("shopfront" if index < 3 else "house_body")
		var roof: PropView = _made_prop("gable_roof")
		var body_box: AABB = body.get_combined_aabb()
		var roof_box: AABB = roof.get_combined_aabb()
		var full: AABB = body_box.merge(AABB(roof_box.position + Vector3.UP * body_box.end.y, roof_box.size))
		var u: float = 0.0
		var v: float = 8.355 + full.size.z * 0.5
		var yaw: float = 0.0
		if index < 2:
			u = _local_reserve.position.x - BUILDING_GAP - full.size.x * 0.5 if index == 0 \
				else _local_reserve.end.x + BUILDING_GAP + full.size.x * 0.5
			v = -full.size.z * 0.5 - 0.15
			yaw = PI
		else:
			u = float(index - 3) * 3.3
		var placement: Transform3D = _placement(u, 0.0, v, yaw)
		var actual: AABB = placement * full
		if _clear_bounds(actual):
			var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
			batch.add_prop(body, placement)
			batch.add_prop(roof, placement * Transform3D(Basis.IDENTITY, Vector3.UP * body_box.end.y))
			_add_batch(batch, "Building%d" % index, "Buildings")
		else:
			build_error = "A neighbouring building has no clear outside position"
		body.free()
		roof.free()


func _build_approaches() -> void:
	for run: Dictionary in _frontages:
		var normal: Variant = run.get("normal")
		var cells: Array = run.get("cells", [])
		if not normal is Vector2i or absi(normal.x) + absi(normal.y) != 1 or cells.is_empty():
			continue
		var center: Vector3 = Vector3.ZERO
		for cell: Vector2i in cells:
			center += GridMath.cell_to_world(cell)
		center /= float(cells.size())
		var outward: Vector3 = Vector3(normal.x, 0.0, normal.y)
		var tangent: Vector3 = Vector3(normal.y, 0.0, -normal.x)
		var frame: Transform3D = Transform3D(Basis(tangent, Vector3.UP, outward), center + outward * GridMath.CELL_SIZE * 0.5)
		var width: float = float(cells.size()) * GridMath.CELL_SIZE + 1.0
		_door_approaches.append(frame * AABB(Vector3(-width * 0.5, 0.0, 0.0), Vector3(width, 1.2, 2.2)))


func _clear_bounds(bounds: AABB) -> bool:
	if NeighbourhoodMeshBatch.xz_intersects(bounds, _reserve):
		return false
	for excluded: AABB in _native_pavement:
		if NeighbourhoodMeshBatch.xz_intersects(bounds, excluded):
			return false
	for excluded: AABB in _door_approaches:
		if NeighbourhoodMeshBatch.xz_intersects(bounds, excluded):
			return false
	return true


func _ensure_actors() -> void:
	if pedestrians.is_empty():
		for index: int in 3:
			var person: PersonView = PERSON.instantiate() as PersonView
			person.name = "Pedestrian%d" % index
			person.role = &"guest"
			person.guest_id = GUEST_IDS[index]
			_actors_root.add_child(person)
			pedestrians.append(person)
			_directions.append(_tangent)
	if car == null:
		car = _made_prop("compact_car")
		car.name = "Car"
		_traffic_root.add_child(car)
		_car_bounds = car.get_combined_aabb()
		for node: Node in car.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _initialize_players() -> void:
	if pedestrians.size() != 3:
		return
	if _players.size() == 3 and _players[0] != null and _players[1] != null and _players[2] != null:
		return
	_players.clear()
	_animation_lengths.clear()
	for person: PersonView in pedestrians:
		if not person.is_node_ready():
			_players.clear()
			_animation_lengths.clear()
			return
		person.set_pose(true, false, false, false)
		person.set_playback_speed(1.0)
		var players: Array[Node] = person.find_children("*", "AnimationPlayer", true, false)
		var player: AnimationPlayer = players[0] as AnimationPlayer if not players.is_empty() else null
		if player == null or not player.has_animation(&"walk"):
			build_error = "A pedestrian walk animation is unavailable"
			return
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_players.append(player)
		_animation_lengths.append(player.get_animation(&"walk").length)
		for node: Node in person.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_routes() -> void:
	_routes.clear()
	_pedestrian_sweeps.clear()
	for lane: float in WALK_LANES:
		var route: Vector2 = _safe_route(_shift + lane, WALK_HALF, WALK_HALF)
		_routes.append(route)
		var box: AABB = AABB(Vector3(route.x - WALK_HALF, _paving_top + WALK_BOTTOM, _shift + lane - WALK_HALF),
			Vector3(maxf(route.y - route.x, 0.0) + WALK_HALF * 2.0, WALK_TOP - WALK_BOTTOM, WALK_HALF * 2.0))
		_pedestrian_sweeps.append(_frame * box)
	_car_rotation = _frame.basis * Basis(Vector3.UP, -PI * 0.5)
	var rotated: AABB = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO) * _car_bounds
	_car_route = _safe_route(_shift + CAR_LANE, rotated.size.x * 0.5, rotated.size.z * 0.5)
	_car_sweep = _frame * AABB(Vector3(_car_route.x + rotated.position.x, 0.0, _shift + CAR_LANE + rotated.position.z),
		Vector3(maxf(_car_route.y - _car_route.x, 0.0) + rotated.size.x, rotated.size.y, rotated.size.z))


func _safe_route(lane: float, half_x: float, half_z: float) -> Vector2:
	var intervals: Array[Vector2] = [Vector2(-_street_half + half_x + MARGIN, _street_half - half_x - MARGIN)]
	var exclusions: Array[AABB] = [_reserve]
	exclusions.append_array(_native_pavement)
	exclusions.append_array(_door_approaches)
	for excluded: AABB in exclusions:
		var box: AABB = _frame.affine_inverse() * excluded
		if lane + half_z <= box.position.z - MARGIN or lane - half_z >= box.end.z + MARGIN:
			continue
		var next: Array[Vector2] = []
		var low: float = box.position.x - half_x - MARGIN
		var high: float = box.end.x + half_x + MARGIN
		for interval: Vector2 in intervals:
			if low >= interval.y or high <= interval.x:
				next.append(interval)
			else:
				if low > interval.x:
					next.append(Vector2(interval.x, minf(low, interval.y)))
				if high < interval.y:
					next.append(Vector2(maxf(high, interval.x), interval.y))
		intervals = next
	var chosen: Vector2 = Vector2.ZERO
	for interval: Vector2 in intervals:
		if interval.y - interval.x > chosen.y - chosen.x:
			chosen = interval
	if chosen.y - chosen.x < 1.0:
		build_error = "A street actor has no clear outside route"
		return Vector2.ZERO
	return chosen


func _build_lamps() -> void:
	var prop: PropView = _made_prop("street_lamp")
	var bounds: AABB = prop.get_combined_aabb()
	for index: int in 2:
		var placement: Transform3D = _placement(-4.0 if index == 0 else 4.0, 0.0,
			3.455 if index == 0 else 5.755, PI * 0.5)
		var actual: AABB = placement * bounds
		var clear: bool = _clear_bounds(actual) and not NeighbourhoodMeshBatch.xz_intersects(actual, _car_sweep)
		for sweep: AABB in _pedestrian_sweeps:
			clear = clear and not NeighbourhoodMeshBatch.xz_intersects(actual, sweep)
		if clear:
			var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
			batch.add_prop(prop, placement)
			_add_batch(batch, "StreetLamp%d" % index, "StreetLamps")
		else:
			build_error = "A street lamp has no clear outside position"
	prop.free()


func _process(delta: float) -> void:
	advance_display(delta)


func advance_display(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0 or not is_finite(_display_seconds + delta):
		return
	_display_seconds += delta
	if _configured:
		_apply_time(_effective_time())


func set_review_time(seconds: float) -> bool:
	if not is_finite(seconds) or seconds < 0.0:
		return false
	_review_time = seconds
	_apply_time(seconds)
	return true


func clear_review_time() -> void:
	_review_time = -1.0
	_apply_time(_display_seconds)


func _effective_time() -> float:
	return _review_time if _review_time >= 0.0 else _display_seconds


func _apply_time(seconds: float) -> void:
	if not _configured:
		return
	if pedestrians.size() != 3 or _routes.size() != 3 or car == null:
		return
	for index: int in 3:
		var route: Vector2 = _routes[index]
		var length: float = route.y - route.x
		if length <= 0.0:
			pedestrians[index].hide()
			continue
		var progress: float = fposmod(seconds * WALK_SPEED + PHASES[index] * length * 2.0, length * 2.0)
		var forward: bool = progress <= length
		var u: float = route.x + progress if forward else route.y - (progress - length)
		var person: PersonView = pedestrians[index]
		person.position = _frame * Vector3(u, _paving_top, _shift + WALK_LANES[index])
		_directions[index] = _tangent if forward else -_tangent
		person.face_direction(_directions[index])
		person.show()
		if _players.size() == 3:
			_players[index].seek(fposmod(seconds + PHASES[index], _animation_lengths[index]), true)
			_players[index].advance(0.0)
	var travel: float = (_car_route.y - _car_route.x) / CAR_SPEED
	var phase: float = fposmod(seconds, maxf(travel + CAR_REST, 1.0))
	car.visible = travel > 0.0 and phase >= 1.0 and phase <= travel + 1.0
	var u: float = _car_route.x + clampf(phase - 1.0, 0.0, maxf(travel, 0.0)) * CAR_SPEED
	car.transform = Transform3D(_car_rotation, _frame * Vector3(u, 0.0, _shift + CAR_LANE))


func capture_state() -> Dictionary:
	var actors: Array[Dictionary] = []
	for index: int in range(pedestrians.size()):
		var person: PersonView = pedestrians[index]
		var player: AnimationPlayer = _players[index] if index < _players.size() else null
		actors.append({"guest_id": person.guest_id, "model": String(person.model_name()), "clip": String(person.current_clip()),
			"visible": person.is_visible_in_tree(), "position": _v(person.position), "global_transform": _xf(person.global_transform if person.is_inside_tree() else person.transform),
			"direction": _v(_directions[index]), "animation_position": player.current_animation_position if player != null else -1.0,
			"animation_length": _animation_lengths[index] if index < _animation_lengths.size() else 0.0,
			"animation_playing": player.is_playing() if player != null else false,
			"animation_callback_mode": player.callback_mode_process if player != null else -1,
			"playback_speed": player.speed_scale if player != null else 0.0})
	return {"display_seconds": _display_seconds, "review_time": _review_time, "is_processing": is_processing(),
		"process_mode": process_mode, "rebuild_generation": _generation, "build_error": build_error,
		"static_mesh_count": _static_meshes.size(), "pedestrian_count": pedestrians.size(), "car_count": 1 if car != null else 0,
		"frame": {"origin": _v(_frame.origin), "normal": _v(_outward), "tangent": _v(_tangent), "reserve_shift": _shift},
		"bounds": {"reserve": _box_state(_reserve), "near_pavement": _box_state(_near_pavement), "road": _box_state(_road),
			"far_pavement": _box_state(_far_pavement), "door_approaches": _boxes_state(_door_approaches),
			"native_pavement": _boxes_state(_native_pavement), "pedestrian_sweeps": _boxes_state(_pedestrian_sweeps),
			"car_sweep": _box_state(_car_sweep)}, "actors": actors,
		"car": {"visible": car.is_visible_in_tree(), "position": _v(car.position), "global_transform": _xf(car.global_transform if car.is_inside_tree() else car.transform)} if car != null else {}}


static func _v(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


static func _xf(value: Transform3D) -> Dictionary:
	return {"origin": _v(value.origin), "basis": [_v(value.basis.x), _v(value.basis.y), _v(value.basis.z)]}


static func _box_state(value: AABB) -> Dictionary:
	return {"position": _v(value.position), "size": _v(value.size)}


static func _boxes_state(values: Array[AABB]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: AABB in values:
		result.append(_box_state(value))
	return result
