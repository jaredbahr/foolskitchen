class_name NeighbourhoodDressing
extends Node3D
## A bounded, read-only street view. No simulation agents, random draws,
## physics, save state, lights or camera control belong to this presenter.

const PERSON: PackedScene = preload("res://assets/people/person.tscn")
## Bought patio paving reads as the shop's own: the street paving warmed
## toward clay, framed by a darker edge of the same stone (#269).
const PATIO_WARM_SWATCH: SwatchDef = preload("res://data/swatches/clay.tres")
const PATIO_WARM_MIX: float = 0.45
const PATIO_EDGE_DARKEN: float = 0.25
const PATIO_EDGE_WIDTH: float = 0.035
const MADE_ROOT: String = "res://assets/made/neighbourhood/"
const ASSETS: Array[String] = ["road_segment", "crossing_segment", "kerb_segment", "compact_car", "street_lamp"]
const GUEST_IDS: Array[int] = [1, 4, 6]
const PHASES: Array[float] = [0.0, 0.33, 0.67]
const WALK_LANES: Array[float] = [2.755, 6.455, 7.555]
const WALK_SPEED: float = 0.65
const WALK_HALF: float = 0.50
const WALK_BOTTOM: float = -0.05
const WALK_TOP: float = 1.10
const MARGIN: float = 0.05
## How far from the lot's edge (in u) street furniture may stand.
const FURNITURE_REACH: float = 15.0
## The lamp bulb's centre height on the model, and its colours by day and night (#423).
const LAMP_BULB_Y: float = 1.565
const LAMP_DAY: Color = Color(0.93, 0.83, 0.5)
const LAMP_NIGHT: Color = Color(1.0, 0.8, 0.42)
const LAMP_BULB_ENERGY: float = 2.4
## Lit windows (#440): the dim multiplier a window quad has by day (it is hidden then), and
## the faint emission a lit one adds on top of its warm tint.
const WINDOW_DAY: Color = Color(0.45, 0.52, 0.6)
const WINDOW_NIGHT: Color = Color(1.0, 0.78, 0.4)
const WINDOW_ENERGY: float = 0.3
const SIDE_MARGIN: float = 6.0
const CAR_SPEED: float = 2.8
const CAR_REST: float = 14.0
const CAR_LANE: float = 4.005
const PAVING_START: float = 0.005
const PAVING_DEPTH: float = 3.30
const ROAD_START: float = 3.405
const ROAD_END: float = 5.805
const FAR_START: float = 5.905
const FAR_DEPTH: float = 2.20
## Boardwalk seams (GroundSkin.plank_seam): one plank wide, a hair above the paving.
const PLANK_STEP: float = 0.32
const PLANK_SEAM: float = 0.022
const PLANK_LIFT: float = 0.004
## The promenade's walking lanes (v), nearest the shops first (#596): one walker each,
## each sweeping this far either side of its lane.
const PROMENADE_LANES: Array[float] = [2.72, 3.58, 5.62, 6.5, 7.36]
const PROMENADE_HALF: float = 0.38
## How fast each kind of promenade walker goes (m/s) and how fast their legs move.
const WALKER_SPEEDS: Dictionary[StringName, float] = {&"stroll": 0.65, &"dog": 0.6, &"pram": 0.5, &"jog": 1.35, &"cycle": 1.9, &"hike": 0.55}
const WALKER_STRIDES: Dictionary[StringName, float] = {&"stroll": 1.0, &"dog": 1.0, &"pram": 0.85, &"jog": 1.9, &"cycle": 1.0, &"hike": 0.9}
## The woodland track's walkers (#607): their guest looks, and a cyclist's pace on dirt.
const FOREST_GUESTS: Array[int] = [2, 5, 8, 3, 10]
const FOREST_CYCLE_SPEED: float = 1.5
const PROMENADE_GUESTS: Array[int] = [1, 3, 6, 4, 7]
## The country lane's walkers (#613): their guest looks, and a cyclist's pace on a lane.
const COUNTRY_GUESTS: Array[int] = [9, 4, 11, 6]
const COUNTRY_CYCLE_SPEED: float = 1.7
## The cyclist's seat height, how far ahead the dog trots (path metres) and its leash.
const BIKE_SEAT: float = 0.3
const DOG_LEAD: float = 0.75
const DOG_SIDE: float = 0.2
const LEASH_HAND: Vector3 = Vector3(0.14, 0.42, 0.06)
## How a terrace neighbour shows (#596): trading, or closed with a for-sale board.
## A neighbour the player has bought and knocked through is #597's (TODO).
enum NeighbourState { OCCUPIED, FOR_SALE }
const SALE_TEXT: String = "FOR SALE"
const SIGN_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const SIGN_FONT_SIZE: int = 48

## Far street and ground meshes by street signature, shared by every dressing
## (a new game or a loaded save re-uses them instead of re-batching ~100k triangles).
static var _mesh_cache: Dictionary[String, Array] = {}
## The lit-window meshes of a street by the same kind of key (#440), kept apart from `_mesh_cache`
## so they do not count against its size limit.
static var _window_cache: Dictionary[String, Array] = {}
static var _cache_exit_bound: bool = false
var static_root: Node3D
## The grass, planting and tree line under and around everything (#421, #424).
## Kept apart from static_root: it deliberately lies under the whole lot.
var ground_root: Node3D
## The street's far runs, out past the actors' span to the tree line. Cached:
## they never depend on purchases, so a rebuild keeps them.
var far_root: Node3D
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
## The terrace's paved block beside and behind the lot (#600), street-local (u, z); empty
## on a street without a terrace.
var _paved: Rect2 = Rect2()
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
## Re-skin a street by setting this before `configure` (null = standard meadow).
## `use_preset` sets it from the site's StreetPreset (#425).
var ground_skin: GroundSkin
## Re-style a street's buildings by setting this before `configure` (null = the standard row).
var street_set: StreetSet
## The street recipe the two halves above came from (null until `use_preset`).
var preset: StreetPreset
var _ground_key: Array = []
var _far_key: Array = []
var _building_boxes: Array[AABB] = []
var _lot_boxes: Array[AABB] = []
var _building_casters: Array[AABB] = []
var _shadow_casters: Array[AABB] = []
var _light_shift: Vector2 = Vector2.ZERO
var _visual_half: float = 0.0
var _configured: bool = false
## Street furniture, night lamps and small life (#423).
var _life_root: Node3D
var _life: NeighbourhoodLife
## The beach and sea behind the back lane (#588), when the street has a shore.
var _shore_root: Node3D
var _shore: NeighbourhoodShore
var _furniture: Array[NeighbourhoodFurniture.Placed] = []
var _crowns: Array[Vector3] = []
var _building_signs: Array[Dictionary] = []
var _shop_doors: Array[float] = []
var _shop_spans: Array[Vector2] = []
var _lamp_feet: Array[Vector2] = []
## The street lamps' bulbs (street-local), for their reflections on a wet street.
var _lamp_spots: Array[Vector3] = []
var _lamp_bulbs: MeshInstance3D
var _lamp_glow: MeshInstance3D
var _bulb_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _lamp_halos: Array[MeshInstance3D] = []
var _halo_material: StandardMaterial3D
var _night: float = 0.0
## 0 until the late hours, 1 when the last windows have gone dark (#440).
var _late: float = 0.0
## How dark the sky is (set_night): 0 through the golden dusk, 1 by night.
var _dark: float = 1.0
var _window_nodes: Array[MeshInstance3D] = []
var _window_materials: Array[StandardMaterial3D] = []
## True when cars drive past; a promenade (#596) has none.
var _traffic: bool = true
## The people out walking, one entry per pedestrian: kind, lane (v), speed, stride rate and phase.
var _walk_kinds: Array[StringName] = []
var _walk_lanes: Array[float] = []
var _walk_speeds: Array[float] = []
var _walk_strides: Array[float] = []
var _walk_phases: Array[float] = []
## What each walker has with them (a bike, a pram, a dog), or null.
var _walk_props: Array[Node3D] = []
var _promenade: NeighbourhoodPromenade
## The named terrace neighbours (#596): their nodes, plans and the state each shows.
var _neighbours: Dictionary[StringName, Node3D] = {}
var _neighbour_plans: Dictionary[StringName, NeighbourhoodBuildings.Plan] = {}
var _neighbour_states: Dictionary[StringName, int] = {}
## The woodland clearing (#607), when the street's preset names a forest: its root,
## its builder and the state each named stand of trees shows (kept across rebuilds).
var _forest_root: Node3D
var _forest: NeighbourhoodForest
var _stand_states: Dictionary[StringName, int] = {}
## The country lane (#613), when the street's preset names one: its root, its builder
## and the state each named land plot shows (kept across rebuilds).
var _country_root: Node3D
var _country: NeighbourhoodCountry
var _plot_states: Dictionary[StringName, int] = {}
## The lot's current lease and its first, unexpanded one (#611), in grid cells: a
## woodland grows land stands on the maximum lot's land outside the first lease, and
## fells them once the current lease covers it. Empty: no land stands.
var _lease: Rect2i = Rect2i()
var _first_lease: Rect2i = Rect2i()
## The shop's built cells' bounding rect (walls, floor and entrance), for the porch.
var _built_rect: Rect2i = Rect2i()
## The shop's built cells themselves (#619): the country's wheel house meets the wall they make.
var _built_cells: Array[Vector2i] = []
## Where the street's people walk (their feet): the paving, or a forest track.
var _walk_y: float = 0.055
## Each neighbour's own bulbs (#600), by id, for the ones that have any.
var _neighbour_lamps: Dictionary[StringName, MeshInstance3D] = {}
## The city rooftop (#614), when the street's preset names one: its root and builder.
var _rooftop_root: Node3D
var _rooftop: NeighbourhoodRooftop
## The cliff top (#380), when the street's preset names one: its root and builder.
var _cliff_root: Node3D
var _cliff: NeighbourhoodCliff
## The day's weather on the street (WeatherState.Kind): rain wets it and keeps some people
## in; sunny leaves everything exactly as built.
var _weather: int = WeatherState.Kind.SUNNY
## A gloomy afternoon's early lamplight (WeatherLook.gloom), 0 on a fair day.
var _gloom: float = 0.0
var _wet: WeatherWet = WeatherWet.new()


func _init() -> void:
	name = "NeighbourhoodDressing"


func _ready() -> void:
	_initialize_players()
	_apply_time(_effective_time())


## Builds the street from `value` (#425): its ground and its building set,
## palette and furniture. Call before `configure`; a later `rebuild` applies it.
func use_preset(value: StreetPreset) -> void:
	preset = value
	ground_skin = value.ground if value != null else null
	street_set = value.buildings if value != null else null


## True when the street's preset is a car-free promenade (#596).
func has_promenade() -> bool:
	return preset != null and preset.promenade != null


## True when the street's preset is a woodland clearing with a forest track (#607).
func has_forest() -> bool:
	return preset != null and preset.forest != null


## True when the street's preset is an old watermill on a country lane (#613).
func has_country() -> bool:
	return preset != null and preset.country != null


## True for open land with no street: a woodland clearing or a country lane. Neither has
## a road, pavements, kerbs, neighbouring buildings, street lamps or street furniture.
func _open_land() -> bool:
	return has_forest() or has_country()
## True when the street's preset is a city rooftop (#614).
func has_rooftop() -> bool:
	return preset != null and preset.rooftop != null
## True when the street's preset is a cliff top over the sea (#380).
func has_cliff() -> bool:
	return preset != null and preset.cliff != null


## The lot's current lease and first lease (#611), for a woodland's land stands. Takes
## effect at the next `configure` or `rebuild`; other streets ignore it.
func set_lease(current: Rect2i, first: Rect2i) -> void:
	_lease = current
	_first_lease = first


func configure(grid: SimGrid, maximum_lot: Rect2i, frontage_runs: Array[Dictionary],
		native_pavement: Array[AABB]) -> void:
	_grid = grid
	_maximum_lot = maximum_lot
	_frontages.assign(frontage_runs.duplicate(true))
	_native_pavement = native_pavement.duplicate()
	rebuild()


func rebuild() -> void:
	_ensure_roots()
	# A dressing given no street gets the starter street's parts, so its cache keys
	# match a dressing that was handed the starter preset.
	if street_set == null:
		street_set = StreetPreset.starter().buildings
	if ground_skin == null:
		ground_skin = StreetPreset.starter().ground
	var built: Array[Vector2i] = []
	var patio: Array[Vector2i] = []
	if _grid != null:
		for cell: Vector2i in _grid.cells():
			if _grid.is_outdoor_floor(cell):
				patio.append(cell)
			elif _grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
				built.append(cell)
	var key: Array = [_grid.get_instance_id() if _grid != null else 0, _maximum_lot,
		_frontages, _native_pavement, built, ground_skin.signature() if ground_skin != null else "standard",
		street_set.signature(), preset.shore.signature() if has_shore() else ""]
	if has_promenade():
		key.append(preset.promenade.signature())
	if has_forest():
		key.append(preset.forest.signature())
		key.append([_lease, _first_lease])
	if has_country():
		key.append(preset.country.signature())
		key.append([_lease, _first_lease])
	if has_rooftop():
		key.append(preset.rooftop.signature())
	if has_cliff():
		key.append(preset.cliff.signature())
	if not patio.is_empty():
		key.append(patio)
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
	_built_rect = Rect2i()
	_built_cells = built
	for cell: Vector2i in built:
		area = area.merge(Rect2i(cell, Vector2i.ONE)) if area.has_area() else Rect2i(cell, Vector2i.ONE)
		_built_rect = _built_rect.merge(Rect2i(cell, Vector2i.ONE)) if _built_rect.has_area() else Rect2i(cell, Vector2i.ONE)
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
	# A street may lay its own pavement colour (a boardwalk); none keeps the grey paving.
	if ground_skin.pavement.a > 0.0:
		paving.set_body_tint(ground_skin.pavement)
	var road_prop: PropView = _made_prop("road_segment")
	var road_box: AABB = road_prop.get_combined_aabb()
	var count: int = ceili((maxf(absf(_local_reserve.position.x), absf(_local_reserve.end.x)) + SIDE_MARGIN) * 2.0 / road_box.size.x)
	if count % 2 == 0:
		count += 1
	_street_half = float(count) * road_box.size.x * 0.5
	# The street itself runs on past the actors' span, out to the tree line.
	var far_count: int = ceili((NeighbourhoodGround.WORLD_HALF + NeighbourhoodGround.BEYOND * 0.5) * 2.0 / road_box.size.x)
	if far_count % 2 == 0:
		far_count += 1
	far_count = maxi(far_count, count)
	_visual_half = float(far_count) * road_box.size.x * 0.5
	_traffic = not has_promenade() and not _open_land() and not has_rooftop() and not has_cliff()
	_promenade = NeighbourhoodPromenade.new(preset.promenade, street_set) if has_promenade() else null
	_walk_y = _paving_top
	if _open_land():
		# A woodland clearing (#607) or a country lane (#613): no road, pavement, kerbs or
		# neighbours; a dirt track or a narrow lane.
		_walk_y = NeighbourhoodForest.WALK_Y if has_forest() else NeighbourhoodCountry.WALK_Y
		_clear_street_ground()
	elif has_rooftop() or has_cliff():
		# A city rooftop (#614) or a cliff top (#380): no road, pavement, kerbs or neighbours.
		_clear_street_ground()
	elif _traffic:
		_build_road(road_prop, road_box, count)
		_build_paving(paving, paving_box, PAVING_START, PAVING_DEPTH, "NearPavement")
		_build_paving(paving, paving_box, FAR_START, FAR_DEPTH, "FarPavement")
	else:
		# A promenade: one sweep of paving from the shop fronts to the far edge, no road.
		_build_paving(paving, paving_box, PAVING_START, FAR_START + FAR_DEPTH - PAVING_START, "NearPavement", true)
		_far_pavement = _near_pavement
	if not _open_land() and not has_rooftop() and not has_cliff():
		_build_far_street(road_prop, road_box, paving, paving_box, count, far_count)
	_build_planks()
	_build_promenade_pattern()
	road_prop.free()
	# A woodland's patio is the cabin's porch deck, which the forest draws (#596).
	if not patio.is_empty() and not has_forest():
		paving.set_body_tint(patio_color())
		_build_patio_paving(paving, paving_box, patio)
	paving.clear_body_tint()
	paving.free()
	if has_forest():
		_build_forest()
	elif has_country():
		_build_country()
	elif has_rooftop():
		_build_rooftop()
	elif has_cliff():
		_build_cliff()
	else:
		_build_kerbs(road_box.size.x, count)
		_build_buildings()
		_build_yard_fronts(built)
		_build_ground()
	_ensure_actors()
	_build_routes()
	if not _open_land() and not has_rooftop() and not has_cliff():
		_build_lamps()
		_build_furniture()
		_build_life()
	_build_shore()
	_initialize_players()
	_configured = build_error.is_empty()
	static_root.visible = _configured
	ground_root.visible = _configured
	far_root.visible = _configured
	_actors_root.visible = _configured
	_traffic_root.visible = _configured and _traffic
	_life_root.visible = _configured
	_shore_root.visible = _configured
	_forest_root.visible = _configured
	_country_root.visible = _configured
	_rooftop_root.visible = _configured
	_cliff_root.visible = _configured
	_apply_night()
	_apply_weather()
	_apply_time(_effective_time())


func _ensure_roots() -> void:
	if static_root != null:
		return
	static_root = Node3D.new()
	static_root.name = "Static"
	add_child(static_root)
	for label: String in ["Road", "Pavement", "Kerbs", "Buildings", "StreetLamps", "Furniture", "Neighbours"]:
		var group: Node3D = Node3D.new()
		group.name = label
		static_root.add_child(group)
		_groups[label] = group
	ground_root = Node3D.new()
	ground_root.name = "Ground"
	add_child(ground_root)
	far_root = Node3D.new()
	far_root.name = "FarStreet"
	add_child(far_root)
	_actors_root = Node3D.new()
	_actors_root.name = "PassersBy"
	add_child(_actors_root)
	_traffic_root = Node3D.new()
	_traffic_root.name = "Traffic"
	add_child(_traffic_root)
	_life_root = Node3D.new()
	_life_root.name = "Life"
	add_child(_life_root)
	_shore_root = Node3D.new()
	_shore_root.name = "Shore"
	add_child(_shore_root)
	_forest_root = Node3D.new()
	_forest_root.name = "Forest"
	add_child(_forest_root)
	_country_root = Node3D.new()
	_country_root.name = "Country"
	add_child(_country_root)
	_rooftop_root = Node3D.new()
	_rooftop_root.name = "Rooftop"
	add_child(_rooftop_root)
	_cliff_root = Node3D.new()
	_cliff_root.name = "Cliff"
	add_child(_cliff_root)


func _clear_static() -> void:
	_static_meshes.clear()
	for group: Node3D in _groups.values():
		for child: Node in group.get_children():
			group.remove_child(child)
			child.free()
	for child: Node in _life_root.get_children():
		_life_root.remove_child(child)
		child.free()
	_life = null
	for child: Node in _shore_root.get_children():
		_shore_root.remove_child(child)
		child.free()
	_shore = null
	for child: Node in _forest_root.get_children():
		_forest_root.remove_child(child)
		child.free()
	_forest = null
	for child: Node in _country_root.get_children():
		_country_root.remove_child(child)
		child.free()
	_country = null
	for child: Node in _rooftop_root.get_children():
		_rooftop_root.remove_child(child)
		child.free()
	_rooftop = null
	for child: Node in _cliff_root.get_children():
		_cliff_root.remove_child(child)
		child.free()
	_cliff = null
	_lamp_bulbs = null
	_lamp_glow = null
	_bulb_material = null
	_glow_material = null
	_lamp_halos.clear()
	_halo_material = null
	_window_nodes.clear()
	_window_materials.clear()
	_furniture.clear()
	_neighbours.clear()
	_neighbour_plans.clear()
	_neighbour_lamps.clear()
	_crowns.clear()
	_building_signs.clear()
	_shop_doors.clear()
	_shop_spans.clear()
	_lamp_feet.clear()
	_lamp_spots.clear()
	_routes.clear()
	_pedestrian_sweeps.clear()
	_door_approaches.clear()
	_building_boxes.clear()
	_lot_boxes.clear()
	_building_casters.clear()
	_frame = Transform3D.IDENTITY
	_outward = Vector3.FORWARD
	_tangent = Vector3.RIGHT
	_reserve = AABB()
	_paved = Rect2()
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
	ground_root.hide()
	far_root.hide()
	_actors_root.hide()
	_traffic_root.hide()
	_life_root.hide()
	_shore_root.hide()
	_forest_root.hide()
	_country_root.hide()
	_rooftop_root.hide()
	_cliff_root.hide()
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


## The seams of a boardwalk (GroundSkin.plank_seam): thin lines across the near and
## far pavement, one plank apart, out to the street's visual ends. None when the
## street has no boardwalk. One flat, lit, vertex-coloured mesh.
func _build_planks() -> void:
	if ground_skin.plank_seam.a <= 0.0:
		return
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var planks: int = int(floorf(_visual_half * 2.0 / PLANK_STEP))
	var bands: Array[Vector2] = [Vector2(PAVING_START, PAVING_START + PAVING_DEPTH), Vector2(FAR_START, FAR_START + FAR_DEPTH)]
	for band: Vector2 in bands:
		for index: int in planks:
			var u: float = -_visual_half + (float(index) + 0.5) * PLANK_STEP
			var corners: Array[Vector2] = [Vector2(u - PLANK_SEAM * 0.5, _shift + band.x), Vector2(u + PLANK_SEAM * 0.5, _shift + band.x),
				Vector2(u + PLANK_SEAM * 0.5, _shift + band.y), Vector2(u - PLANK_SEAM * 0.5, _shift + band.y)]
			soup.flat(corners, _paving_top + PLANK_LIFT, ground_skin.plank_seam)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.disable_receive_shadows = true
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "PlankSeams"
	mesh.mesh = soup.to_mesh()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.transform = _frame
	_groups["Pavement"].add_child(mesh)
	_static_meshes.append(mesh)


## The promenade's paving pattern (#596): slab joints, the centre band and its wave,
## out to the street's visual ends. None on a street with a road.
func _build_promenade_pattern() -> void:
	if _promenade == null:
		return
	var holes: Array[Rect2] = []
	var inverse: Transform3D = _frame.affine_inverse()
	for bounds: AABB in _native_pavement:
		var local: AABB = inverse * bounds
		holes.append(Rect2(local.position.x, local.position.z - _shift, local.size.x, local.size.z))
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.disable_receive_shadows = true
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "PromenadePattern"
	mesh.mesh = _promenade.pattern(-_visual_half, _visual_half, FAR_START + FAR_DEPTH, _paving_top, holes)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.transform = _frame * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, _shift))
	_groups["Pavement"].add_child(mesh)
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


## `fit` stretches the slabs across the street so a whole number of rows fills `depth`
## exactly (the promenade's one wide band).
func _build_paving(source: PropView, bounds: AABB, start: float, depth: float, label: String, fit: bool = false) -> void:
	var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
	var holes: Array[AABB] = _native_pavement.duplicate()
	holes.append(_reserve)
	var columns: int = ceili(_street_half * 2.0 / bounds.size.x)
	var rows: int = roundi(depth / bounds.size.z)
	var row_depth: float = depth / float(rows) if fit else bounds.size.z
	var stretch: Basis = Basis.from_scale(Vector3(1.0, 1.0, row_depth / bounds.size.z))
	for row: int in rows:
		for column: int in columns:
			var u: float = -_street_half + (float(column) + 0.5) * bounds.size.x
			var v: float = start + (float(row) + 0.5) * row_depth
			var placement: Transform3D = _placement(u, _paving_top - bounds.end.y, v, PI)
			if fit:
				placement.basis = placement.basis * stretch
			batch.add_prop(source, placement, holes)
	_add_batch(batch, label, "Pavement")
	var box: AABB = _frame * AABB(Vector3(-_street_half, _paving_top - bounds.size.y, _shift + start),
		Vector3(_street_half * 2.0, bounds.size.y, depth))
	if label == "NearPavement":
		_near_pavement = box
	else:
		_far_pavement = box


## The public pavement starts beyond the reserved entrance row. Fill only
## purchased gaps with the same native-scale paving, leaving the street's
## frame, reserve and existing tiles untouched. Clipping preserves source
## materials/UVs and removes every coplanar overlap with those existing tiles.
func _build_patio_paving(source: PropView, bounds: AABB, cells: Array[Vector2i]) -> void:
	var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
	for cell: Vector2i in cells:
		var center: Vector3 = GridMath.cell_to_world(cell)
		center.y = _paving_top - bounds.end.y
		var placement: Transform3D = Transform3D(_frame.basis * Basis(Vector3.UP, PI), center)
		var copied: AABB = placement * bounds
		var tile: AABB = AABB(Vector3(cell.x * GridMath.CELL_SIZE, copied.position.y,
			cell.y * GridMath.CELL_SIZE), Vector3(GridMath.CELL_SIZE, copied.size.y, GridMath.CELL_SIZE))
		var holes: Array[AABB] = _native_pavement.duplicate()
		holes.append(_near_pavement)
		holes.append(_far_pavement)
		# Subtract the source copy's four overhanging strips, retaining exactly
		# this owned square. No model is stretched to fit the simulation grid.
		if copied.position.x < tile.position.x:
			holes.append(AABB(copied.position, Vector3(tile.position.x - copied.position.x, copied.size.y, copied.size.z)))
		if copied.end.x > tile.end.x:
			holes.append(AABB(Vector3(tile.end.x, copied.position.y, copied.position.z),
				Vector3(copied.end.x - tile.end.x, copied.size.y, copied.size.z)))
		if copied.position.z < tile.position.z:
			holes.append(AABB(copied.position, Vector3(copied.size.x, copied.size.y, tile.position.z - copied.position.z)))
		if copied.end.z > tile.end.z:
			holes.append(AABB(Vector3(copied.position.x, copied.position.y, tile.end.z),
				Vector3(copied.size.x, copied.size.y, copied.end.z - tile.end.z)))
		batch.add_prop(source, placement, holes)
	_add_batch(batch, "PatioPavement", "Pavement")
	_build_patio_edge(cells)


static func patio_color() -> Color:
	return RoomDressing.pavement_color().lerp(PATIO_WARM_SWATCH.color, PATIO_WARM_MIX)


## A thin flat border wherever owned patio meets anything else.
func _build_patio_edge(cells: Array[Vector2i]) -> void:
	var owned: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		owned[cell] = true
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size: float = GridMath.CELL_SIZE
	var width: float = PATIO_EDGE_WIDTH
	var height: float = _paving_top + 0.003
	for cell: Vector2i in cells:
		var low: Vector2 = Vector2(cell) * size
		var strips: Array[Rect2] = []
		if not owned.has(cell + Vector2i.LEFT):
			strips.append(Rect2(low, Vector2(width, size)))
		if not owned.has(cell + Vector2i.RIGHT):
			strips.append(Rect2(low + Vector2(size - width, 0.0), Vector2(width, size)))
		if not owned.has(cell + Vector2i.UP):
			strips.append(Rect2(low, Vector2(size, width)))
		if not owned.has(cell + Vector2i.DOWN):
			strips.append(Rect2(low + Vector2(0.0, size - width), Vector2(size, width)))
		for strip: Rect2 in strips:
			var corners: Array[Vector3] = [Vector3(strip.position.x, height, strip.position.y),
				Vector3(strip.end.x, height, strip.position.y), Vector3(strip.end.x, height, strip.end.y),
				Vector3(strip.position.x, height, strip.end.y)]
			for index: int in [0, 1, 2, 0, 2, 3]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(corners[index])
	var edge: MeshInstance3D = MeshInstance3D.new()
	edge.name = "PatioEdge"
	edge.mesh = surface.commit()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = patio_color().darkened(PATIO_EDGE_DARKEN)
	edge.material_override = material
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_groups["Pavement"].add_child(edge)
	_static_meshes.append(edge)


## Road, pavement and kerbs for every run beyond the actors' span, to the tree
## line. They lie far from the lot and the entrance pads, so they need no holes.
## Built once per street frame (see far_root) and kept across rebuilds.
func _build_far_street(road: PropView, road_box: AABB, paving: PropView, paving_box: AABB,
		count: int, far_count: int) -> void:
	var key: Array = [_frame, _street_half, _shift, _paving_top, far_count, ground_skin.pavement]
	if not _traffic:
		key.append("promenade")
	if key == _far_key and far_root.get_child_count() > 0:
		far_root.transform = _frame
		return
	_far_key = key.duplicate(true)
	for child: Node in far_root.get_children():
		far_root.remove_child(child)
		child.free()
	far_root.transform = _frame
	if _restore_cached(far_root, "far" + str(_far_key)):
		return
	var width: float = road_box.size.x
	var middle: int = far_count >> 1
	var inner: int = count >> 1
	var road_batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
	var kerb_batches: Array[NeighbourhoodMeshBatch] = [NeighbourhoodMeshBatch.new(), NeighbourhoodMeshBatch.new(),
		NeighbourhoodMeshBatch.new(), NeighbourhoodMeshBatch.new()]
	var kerb: PropView = _made_prop("kerb_segment")
	for index: int in far_count:
		if absi(index - middle) <= inner:
			continue
		var u: float = (float(index) - float(far_count - 1) * 0.5) * width
		if _traffic:
			road_batch.add_prop(road, _far_placement(u, -road_box.end.y, (ROAD_START + ROAD_END) * 0.5))
	# Kerbs are long straight runs: each piece is stretched along the street to
	# cover several tile widths, so far runs cost a fraction of the triangles.
	var chunk: int = 6
	for run: Vector2i in [Vector2i(0, middle - inner - 1), Vector2i(middle + inner + 1, far_count - 1)]:
		var start: int = run.x
		while start <= run.y:
			var last: int = mini(start + chunk - 1, run.y)
			var n: int = last - start + 1
			var u: float = (float(start + last) * 0.5 - float(far_count - 1) * 0.5) * width
			var stretch: Basis = Basis.from_scale(Vector3(float(n), 1.0, 1.0))
			var specs: Array[Vector2] = [Vector2(0.0, 3.355), Vector2(0.0, 5.855), Vector2(-0.03, PAVING_START - 0.05),
				Vector2(-0.03, FAR_START + FAR_DEPTH + 0.05)]
			for side: int in 4:
				if side < 2 and not _traffic:
					continue
				kerb_batches[side].add_prop(kerb, Transform3D(stretch, Vector3(u, specs[side].x, _shift + specs[side].y)))
			start = last + 1
	kerb.free()
	_add_far(road_batch, "FarRoad")
	var kerb_names: Array[String] = ["FarNearKerb", "FarFarKerb", "FarNearEdgeKerb", "FarFarEdgeKerb"]
	for index: int in 4:
		_add_far(kerb_batches[index], kerb_names[index])
	var columns: int = ceili(_street_half * 2.0 / paving_box.size.x)
	var rows_near: int = roundi(PAVING_DEPTH / paving_box.size.z)
	var rows_far: int = roundi(FAR_DEPTH / paving_box.size.z)
	var outer: int = ceili((_visual_half - _street_half) / paving_box.size.x)
	var pave: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
	var span: int = 5
	for run: Vector2i in [Vector2i(-outer, -1), Vector2i(columns, columns + outer - 1)]:
		var first: int = run.x
		while first <= run.y:
			var last: int = mini(first + span - 1, run.y)
			var u: float = -_street_half + (float(first + last) * 0.5 + 0.5) * paving_box.size.x
			var stretch: Basis = Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(float(last - first + 1), 1.0, 1.0))
			if not _traffic:
				# The promenade's one wide band, its slabs stretched to fill it exactly.
				var whole: float = FAR_START + FAR_DEPTH - PAVING_START
				var rows: int = roundi(whole / paving_box.size.z)
				var row_depth: float = whole / float(rows)
				var fitted: Basis = stretch * Basis.from_scale(Vector3(1.0, 1.0, row_depth / paving_box.size.z))
				for row: int in rows:
					var v: float = PAVING_START + (float(row) + 0.5) * row_depth
					pave.add_prop(paving, Transform3D(fitted, Vector3(u, _paving_top - paving_box.end.y, _shift + v)))
				first = last + 1
				continue
			for spec: Vector3i in [Vector3i(0, rows_near, 0), Vector3i(1, rows_far, 1)]:
				var start_v: float = PAVING_START if spec.x == 0 else FAR_START
				for row: int in spec.y:
					var v: float = start_v + (float(row) + 0.5) * paving_box.size.z
					pave.add_prop(paving, Transform3D(stretch, Vector3(u, _paving_top - paving_box.end.y, _shift + v)))
			first = last + 1
	_add_far(pave, "FarPavement")
	_store_cached(far_root, "far" + str(_far_key))


func _far_placement(u: float, y: float, v: float, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(u, y, _shift + v))


func _add_far(batch: NeighbourhoodMeshBatch, label: String) -> void:
	if batch.triangles == 0:
		return
	var mesh: MeshInstance3D = batch.finish(label)
	far_root.add_child(mesh)


func _build_kerbs(width: float, count: int) -> void:
	var prop: PropView = _made_prop("kerb_segment")
	for side: int in (2 if _traffic else 0):
		var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
		for index: int in count:
			var u: float = (float(index) - float(count - 1) * 0.5) * width
			batch.add_prop(prop, _placement(u, 0.0, 3.355 if side == 0 else 5.855))
		_add_batch(batch, "NearKerb" if side == 0 else "FarKerb", "Kerbs")
	# A low kerb step where the pavement meets the grass, skipping the shop's own
	# frontage, its entrance pads and the door approaches.
	var box: AABB = prop.get_combined_aabb()
	for side: int in 2:
		var batch: NeighbourhoodMeshBatch = NeighbourhoodMeshBatch.new()
		var v: float = PAVING_START - 0.05 if side == 0 else FAR_START + FAR_DEPTH + 0.05
		for index: int in count:
			var u: float = (float(index) - float(count - 1) * 0.5) * width
			var placement: Transform3D = _placement(u, -0.03, v)
			if _clear_bounds(placement * box):
				batch.add_prop(prop, placement)
		_add_batch(batch, "NearEdgeKerb" if side == 0 else "FarEdgeKerb", "Kerbs")
	prop.free()


## The row of shopfronts beside the lot and the houses across the road, built by
## NeighbourhoodBuildings from the street's StreetSet. Planned every rebuild (cheap),
## meshed once per street frame and reused from the shared cache afterwards.
func _build_buildings() -> void:
	var builder: NeighbourhoodBuildings = NeighbourhoodBuildings.new()
	builder.street = street_set
	builder.local_reserve = _local_reserve
	builder.shift = _shift
	builder.paving_top = _paving_top
	builder.light_shift = _compute_light_shift()
	builder.lawn_shadow = (ground_skin.lawn if ground_skin != null else GroundSkin.standard().lawn).darkened(0.3)
	builder.plan()
	_building_boxes = builder.footprints()
	_paved = NeighbourhoodTerrace.paved_block(builder)
	_lot_boxes = builder.lots()
	_building_casters = builder.casters()
	_building_signs = builder.signs()
	_shop_doors = builder.shop_doors()
	for box: AABB in _building_boxes:
		if box.position.z + box.size.z * 0.5 < _shift:
			_shop_spans.append(Vector2(box.position.x, box.end.x))
	for plan: NeighbourhoodBuildings.Plan in builder.plans:
		if not _clear_bounds(_frame * plan.bounds):
			build_error = "A neighbouring building has no clear outside position"
			return
	var group: Node3D = _groups["Buildings"]
	var key: String = "buildings" + str([_frame, _local_reserve, _shift, _paving_top, street_set.signature(),
		builder.light_shift, builder.lawn_shadow])
	if _restore_cached(group, key):
		for child: Node in group.get_children():
			(child as MeshInstance3D).transform = _frame
			_static_meshes.append(child as MeshInstance3D)
		if not _window_cache.has(key):
			# The window meshes were dropped on their own: regenerate them without the buildings.
			for plan: NeighbourhoodBuildings.Plan in builder.plans:
				if String(plan.neighbour_id).is_empty():
					builder.build_mesh(plan).free()
				else:
					for part: MeshInstance3D in builder.build_parts(plan):
						part.free()
			_store_windows(builder, key)
		_add_windows(_window_cache[key])
		_collect_neighbours(builder)
		return
	for plan: NeighbourhoodBuildings.Plan in builder.plans:
		var parts: Array[MeshInstance3D] = []
		if String(plan.neighbour_id).is_empty():
			parts.append(builder.build_mesh(plan))
		else:
			parts = builder.build_parts(plan)
		for mesh: MeshInstance3D in parts:
			mesh.transform = _frame
			group.add_child(mesh)
			_static_meshes.append(mesh)
	_store_cached(group, key)
	_store_windows(builder, key)
	_add_windows(_window_cache[key])
	_collect_neighbours(builder)


## On a terrace (#600): where the lot's side strips meet the street, a wall and gate just
## outside the lot, across every front cell nobody has built on yet, so the row of
## frontages runs on from the shop to next door. A strip the player builds over loses
## its wall (the street rebuilds when the built cells change).
func _build_yard_fronts(built: Array[Vector2i]) -> void:
	if not street_set.has_terrace() or not build_error.is_empty():
		return
	var inverse: Transform3D = _frame.affine_inverse()
	var half: float = GridMath.CELL_SIZE * 0.5
	var taken: Array[Vector2] = []
	for cell: Vector2i in built:
		var centre: Vector3 = inverse * GridMath.cell_to_world(cell)
		# The front two rows: the shop's own frontage and the cells just inside it.
		if centre.z > _shift - GridMath.CELL_SIZE * 2.0:
			taken.append(Vector2(centre.x - half, centre.x + half))
	taken.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
	var free: Array[Vector2] = []
	var cursor: float = _local_reserve.position.x
	for span: Vector2 in taken:
		if span.x > cursor + 0.01:
			free.append(Vector2(cursor, span.x))
		cursor = maxf(cursor, span.y)
	if _local_reserve.end.x > cursor + 0.01:
		free.append(Vector2(cursor, _local_reserve.end.x))
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var render: Color = street_set.stone.lerp(street_set.trim, 0.55)
	var t: float = NeighbourhoodTerrace.FRONT_WALL_T
	for span: Vector2 in free:
		var width: float = span.y - span.x
		if width < GridMath.CELL_SIZE - 0.01:
			continue
		var box: AABB = _frame * AABB(Vector3(span.x, 0.0, _shift), Vector3(width, NeighbourhoodTerrace.FRONT_WALL_H, t))
		if not _clear_front(box):
			continue
		# A single gate into a narrow passage, a double gate into a wider yard.
		var gate: float = minf(width - 0.3, 0.5 if width < 2.0 else 1.0)
		NeighbourhoodTerrace.wall_run(pen, street_set, span.x, span.y, _shift, t, NeighbourhoodTerrace.FRONT_WALL_H,
			(span.x + span.y) * 0.5, gate, render)
	if pen.soup.is_empty():
		return
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "YardFronts"
	mesh.mesh = pen.soup.to_mesh()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.disable_receive_shadows = true
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.transform = _frame
	_groups["Buildings"].add_child(mesh)
	_static_meshes.append(mesh)


## The terrace's shared yard paving (#600): the street's stone, lifted toward its pavement,
## so the yards read as the buildings' own ground and not the promenade.
func _paved_colour() -> Color:
	var pavement: Color = ground_skin.pavement if ground_skin != null and ground_skin.pavement.a > 0.0 else street_set.path
	return street_set.stone.lerp(pavement, 0.62)


## A front wall stays off the shop's door approaches and its own paving.
func _clear_front(bounds: AABB) -> bool:
	for excluded: AABB in _native_pavement:
		if NeighbourhoodMeshBatch.xz_intersects(bounds, excluded):
			return false
	for excluded: AABB in _door_approaches:
		if NeighbourhoodMeshBatch.xz_intersects(bounds, excluded):
			return false
	return true


## Gathers each named terrace neighbour's parts under its own node (#596):
## Neighbours/<id> holds Shell, Trade, ForSale and the painted Sign, placed on the
## building's facade (local +z faces the street), then shows the state it was given.
func _collect_neighbours(builder: NeighbourhoodBuildings) -> void:
	var buildings: Node3D = _groups["Buildings"]
	var group: Node3D = _groups["Neighbours"]
	for plan: NeighbourhoodBuildings.Plan in builder.plans:
		if String(plan.neighbour_id).is_empty():
			continue
		var node: Node3D = Node3D.new()
		node.name = String(plan.neighbour_id)
		node.transform = _frame * plan.xf
		group.add_child(node)
		var inverse: Transform3D = plan.xf.affine_inverse()
		for part: Array in [["", "Shell"], ["_Trade", "Trade"], ["_ForSale", "ForSale"]]:
			var mesh: Node3D = buildings.get_node_or_null(NodePath(plan.id + String(part[0]))) as Node3D
			if mesh != null:
				buildings.remove_child(mesh)
				mesh.transform = inverse
			else:
				mesh = Node3D.new()
			mesh.name = String(part[1])
			node.add_child(mesh)
		# Its bulbs and lit screens (#600) light with the night and go dark when it closes.
		var lamps: MeshInstance3D = buildings.get_node_or_null(NodePath(plan.id + "_Lamps")) as MeshInstance3D
		if lamps != null:
			buildings.remove_child(lamps)
			lamps.transform = inverse
			lamps.name = "Lamps"
			lamps.material_override = _lit_material()
			node.add_child(lamps)
			_neighbour_lamps[plan.neighbour_id] = lamps
		var board: Dictionary = NeighbourhoodTerrace.sign_board(plan)
		if not board.is_empty():
			var ink: Color = plan.style.sign_ink
			var sign: Label3D = _painted_label("Sign", plan.style.sign_text, board, ink)
			# An arcade's name is lit; the others are paint and darken with the night.
			sign.shaded = plan.form != ShopStyle.Form.ARCADE
			node.add_child(sign)
		var sale: Dictionary = NeighbourhoodTerrace.sale_board(plan)
		var sale_node: Node3D = node.get_node(^"ForSale") as Node3D
		var words: Label3D = _painted_label("Words", SALE_TEXT, sale, street_set.signal_red.darkened(0.15))
		words.transform = sale_node.transform.affine_inverse() * words.transform
		sale_node.add_child(words)
		_neighbours[plan.neighbour_id] = node
		_neighbour_plans[plan.neighbour_id] = plan
		_show_neighbour(plan.neighbour_id)


## A line of painted lettering filling `board` (its building-local centre and size).
func _painted_label(label: String, text: String, board: Dictionary, ink: Color) -> Label3D:
	var words: Label3D = Label3D.new()
	words.name = label
	words.text = text
	words.font = SIGN_THEME.default_font if SIGN_THEME.default_font != null else ThemeDB.fallback_font
	words.font_size = SIGN_FONT_SIZE
	words.outline_size = 0
	words.modulate = ink
	words.double_sided = false
	words.shaded = true
	words.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var size: Vector2 = board["size"]
	var width: float = words.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_FONT_SIZE).x
	var height: float = words.font.get_height(SIGN_FONT_SIZE)
	words.pixel_size = minf(size.x / maxf(width, 1.0), size.y / maxf(height, 1.0))
	words.position = board["centre"] + Vector3(0.0, 0.0, 0.004)
	return words


# --- the terrace neighbours' API (#596, for #597) ------------------------------

## The ids of the street's named terrace neighbours, nearest the lot first, left side
## (-u) then right. Empty on a street without a named terrace (the starter street).
func neighbour_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _neighbours:
		ids.append(id)
	return ids


## The neighbour's node (Neighbours/<id>: Shell, Trade, ForSale, Sign), or null. Its
## transform is the facade's centre on the ground, +z facing the street.
func neighbour(id: StringName) -> Node3D:
	return _neighbours.get(id, null)


## What a neighbour is (for tools and #597): its display name (the sign), the side of the
## lot it stands on (-1 left, +1 right), its slot outward from the lot, its building form,
## its width and its facade transform in the dressing's space.
func neighbour_info(id: StringName) -> Dictionary:
	if not _neighbour_plans.has(id):
		return {}
	var plan: NeighbourhoodBuildings.Plan = _neighbour_plans[id]
	var side: float = signf(plan.xf.origin.x - _local_reserve.get_center().x)
	var slot: int = (plan.seed_value - 40) % 10
	return {"name": plan.style.sign_text, "side": int(side), "slot": slot, "form": plan.form, "width": plan.width,
		"facade": _frame * plan.xf, "state": neighbour_state(id)}


func neighbour_state(id: StringName) -> NeighbourState:
	return _neighbour_states.get(id, NeighbourState.OCCUPIED) as NeighbourState


## Shows a neighbour trading (the default) or closed with a for-sale board. The state is
## kept across rebuilds. False when the street has no such neighbour.
## TODO(#597): a KNOCKED_THROUGH state once a neighbour can be bought and joined to the shop.
func set_neighbour_state(id: StringName, state: NeighbourState) -> bool:
	if not _neighbours.has(id):
		return false
	_neighbour_states[id] = state
	_show_neighbour(id)
	return true


func _show_neighbour(id: StringName) -> void:
	var node: Node3D = _neighbours.get(id, null)
	if node == null:
		return
	var for_sale: bool = neighbour_state(id) == NeighbourState.FOR_SALE
	(node.get_node(^"Trade") as Node3D).visible = not for_sale
	(node.get_node(^"ForSale") as Node3D).visible = for_sale
	# A closed arcade's bulb sign goes dark (#600): no bulbs, and its name is only paint.
	var sign: Label3D = node.get_node_or_null(^"Sign") as Label3D
	if sign != null:
		sign.shaded = for_sale or _neighbour_plans[id].form != ShopStyle.Form.ARCADE
	_light_neighbour(id)


## A neighbour's bulbs follow the night while it trades and stay dark while it is closed.
func _light_neighbour(id: StringName) -> void:
	var lamps: MeshInstance3D = _neighbour_lamps.get(id, null)
	if lamps == null:
		return
	var level: float = 0.0 if neighbour_state(id) == NeighbourState.FOR_SALE else _lamplight()
	lamps.visible = level > 0.01
	var material: StandardMaterial3D = lamps.material_override as StandardMaterial3D
	material.albedo_color = WINDOW_DAY.lerp(Color.WHITE, level)
	material.emission_energy_multiplier = level * WINDOW_ENERGY


## Whether a neighbour's bulbs are lit now (false when it has none), for tests and tools.
func neighbour_lit(id: StringName) -> bool:
	var lamps: MeshInstance3D = _neighbour_lamps.get(id, null)
	return lamps != null and lamps.visible and (lamps.material_override as StandardMaterial3D).emission_energy_multiplier > 0.0


func _store_windows(builder: NeighbourhoodBuildings, key: String) -> void:
	if _window_cache.size() > 6:
		_window_cache.clear()
	var glows: Array = []
	var tier: int = 0
	for mesh: ArrayMesh in builder.glow_meshes():
		glows.append(["WindowGlow%d" % tier, mesh, null])
		tier += 1
	_window_cache[key] = glows


## A fresh unlit, emissive material for lit windows and bulbs, dark until the night lights it.
static func _lit_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = WINDOW_DAY
	material.emission_enabled = true
	material.emission = WINDOW_NIGHT
	material.emission_energy_multiplier = 0.0
	material.disable_receive_shadows = true
	return material


## The warm window quads, one emissive unlit mesh per light tier (#440). Their materials belong
## to this dressing so the night level never leaks into another street; the meshes are shared.
func _add_windows(entries: Array) -> void:
	_window_nodes.clear()
	_window_materials.clear()
	for entry: Array in entries:
		var mesh: ArrayMesh = entry[1] as ArrayMesh
		if mesh == null:
			continue
		var material: StandardMaterial3D = _lit_material()
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = String(entry[0])
		node.mesh = mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.transform = _frame
		node.visible = false
		_life_root.add_child(node)
		_window_nodes.append(node)
		_window_materials.append(material)


## Local-frame footprints (height in y) of every building and, flat, the house lots.
func building_footprints() -> Array[AABB]:
	return _building_boxes.duplicate()


func lot_footprints() -> Array[AABB]:
	return _lot_boxes.duplicate()


## The same boxes in the dressing's own space (the shop view's space), for clearance checks.
func building_boxes_in_view() -> Array[AABB]:
	var result: Array[AABB] = []
	for box: AABB in _building_boxes:
		result.append(_frame * box)
	return result


## The world square the camera is held inside, in world metres on the XZ plane.
func world_rect() -> Rect2:
	if not _maximum_lot.has_area():
		return Rect2()
	return NeighbourhoodGround.world_rect(_maximum_lot)


## Grass, planting and the tree line, rebuilt only when the street frame or lot
## changes (they never depend on purchases, patios or the clock).
func _build_ground() -> void:
	_shadow_casters = _compute_shadow_casters()
	_light_shift = _compute_light_shift()
	var key: Array = [_frame, _local_reserve, _shift, _maximum_lot, _building_boxes, _lot_boxes, _shadow_casters, _light_shift,
			ground_skin.signature() if ground_skin != null else "standard", has_shore()]
	if _paved.has_area():
		key.append(_paved)
		key.append(_paved_colour())
	if key == _ground_key and ground_root.get_child_count() > 0:
		ground_root.transform = _frame
		return
	_ground_key = key.duplicate(true)
	for child: Node in ground_root.get_children():
		ground_root.remove_child(child)
		child.free()
	ground_root.transform = _frame
	var cache_key: String = "ground" + str(_ground_key)
	if _restore_cached(ground_root, cache_key):
		return
	var builder: NeighbourhoodGround = NeighbourhoodGround.new()
	builder.local_reserve = _local_reserve
	builder.shift = _shift
	builder.buildings = _building_boxes
	builder.lots = _lot_boxes
	builder.skin = ground_skin
	builder.shadow_casters = _shadow_casters
	builder.light_shift = _light_shift
	builder.shore = has_shore()
	builder.paved = _paved
	builder.paved_colour = _paved_colour()
	var rect: Rect2 = world_rect()
	var centre: Vector3 = _frame.affine_inverse() * Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	builder.world_centre = Vector2(centre.x, centre.z)
	for node: MeshInstance3D in builder.build():
		ground_root.add_child(node)
	_store_cached(ground_root, cache_key)


## Drops the shared meshes (also done when the game's window closes, so they do
## not show up as leaked resources at exit).
static func clear_mesh_cache() -> void:
	_mesh_cache.clear()
	_window_cache.clear()
	NeighbourhoodForest.clear_cache()
	NeighbourhoodCountry.clear_cache()
	NeighbourhoodRooftop.clear_cache()
	NeighbourhoodCliff.clear_cache()


## The key light's ground run per metre of height, in the street's local (u, z).
## Baked at the rig's authored light (lighting_rig.tscn KeyLight, -55 / -35 degrees).
func _compute_light_shift() -> Vector2:
	var aim: Vector3 = Basis.from_euler(Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)) * Vector3.FORWARD
	var local: Vector3 = _frame.basis.inverse() * Vector3(aim.x, 0.0, aim.z)
	return Vector2(local.x, local.z) / maxf(-aim.y, 0.2)


## Boxes whose baked shadows plant them on the lawn: the shop's built floor at
## wall height and every neighbouring building and house.
func _compute_shadow_casters() -> Array[AABB]:
	var casters: Array[AABB] = []
	var inverse: Transform3D = _frame.affine_inverse()
	if _grid != null:
		var low: Vector3 = Vector3(INF, 0.0, INF)
		var high: Vector3 = Vector3(-INF, 0.0, -INF)
		var half: float = GridMath.CELL_SIZE * 0.5
		for cell: Vector2i in _grid.cells():
			if _grid.terrain(cell) == SimGrid.Terrain.OUTSIDE:
				continue
			var centre: Vector3 = GridMath.cell_to_world(cell)
			low = Vector3(minf(low.x, centre.x - half), 0.0, minf(low.z, centre.z - half))
			high = Vector3(maxf(high.x, centre.x + half), 0.0, maxf(high.z, centre.z + half))
		if low.x <= high.x:
			casters.append(inverse * AABB(low, Vector3(high.x - low.x, ArtScale.WALL_HEIGHT, high.z - low.z)))
	casters.append_array(_building_casters)
	return casters


func _restore_cached(parent: Node3D, key: String) -> bool:
	if not _mesh_cache.has(key):
		return false
	for entry: Array in _mesh_cache[key]:
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = entry[0]
		node.mesh = entry[1]
		if entry[2] != null:
			node.material_override = entry[2]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
	return true


func _store_cached(parent: Node3D, key: String) -> void:
	var entries: Array = []
	for child: Node in parent.get_children():
		var node: MeshInstance3D = child as MeshInstance3D
		if node != null and node.mesh != null:
			entries.append([String(node.name), node.mesh, node.material_override])
	if _mesh_cache.size() > 6:
		_mesh_cache.clear()
	if not _cache_exit_bound:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.tree_exiting.connect(clear_mesh_cache)
			_cache_exit_bound = true
	_mesh_cache[key] = entries


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
	_plan_walkers()
	# Reconcile the walkers with the street's list: a site switch can change it.
	while pedestrians.size() > _walk_kinds.size():
		var spare: PersonView = pedestrians.pop_back()
		_actors_root.remove_child(spare)
		spare.free()
		_directions.pop_back()
	var guests: Array[int] = GUEST_IDS if _traffic else (FOREST_GUESTS if has_forest() else (COUNTRY_GUESTS if has_country() else PROMENADE_GUESTS))
	for index: int in _walk_kinds.size():
		if index >= pedestrians.size():
			var person: PersonView = PERSON.instantiate() as PersonView
			person.name = "Pedestrian%d" % index
			person.role = &"guest"
			person.guest_id = guests[index % guests.size()]
			_actors_root.add_child(person)
			pedestrians.append(person)
			_directions.append(_tangent)
		elif pedestrians[index].guest_id != guests[index % guests.size()]:
			pedestrians[index].guest_id = guests[index % guests.size()]
			pedestrians[index].set_look(&"guest", pedestrians[index].guest_id)
	_players.clear()
	_animation_lengths.clear()
	_build_walk_props()
	if car == null:
		car = _made_prop("compact_car")
		car.name = "Car"
		_traffic_root.add_child(car)
		_car_bounds = car.get_combined_aabb()
		for node: Node in car.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Who walks the street: three strollers on a road (#423); on a promenade (#596) the
## preset's walkers, one per lane.
func _plan_walkers() -> void:
	_walk_kinds.clear()
	_walk_lanes.clear()
	_walk_speeds.clear()
	_walk_strides.clear()
	_walk_phases.clear()
	if has_rooftop() or has_cliff():
		# Nobody strolls past at roof level: guests come up in the lift (#614). On a cliff
		# top (#380) the path winds off to the car park; no street runs past.
		return
	if _traffic:
		for index: int in 3:
			_walk_kinds.append(&"stroll")
			_walk_lanes.append(WALK_LANES[index])
			_walk_speeds.append(WALK_SPEED)
			_walk_strides.append(1.0)
			_walk_phases.append(PHASES[index])
		return
	if has_forest():
		for index: int in mini(preset.forest.walkers.size(), NeighbourhoodForest.LANES.size()):
			var kind: StringName = preset.forest.walkers[index]
			_walk_kinds.append(kind)
			_walk_lanes.append(NeighbourhoodForest.TRACK_V + NeighbourhoodForest.LANES[index])
			_walk_speeds.append(FOREST_CYCLE_SPEED if kind == &"cycle" else WALKER_SPEEDS.get(kind, WALK_SPEED))
			_walk_strides.append(WALKER_STRIDES.get(kind, 1.0))
			_walk_phases.append(NeighbourhoodGround.hash01(index, 6, street_set.seed_salt))
		return
	if has_country():
		for index: int in mini(preset.country.walkers.size(), NeighbourhoodCountry.LANES.size()):
			var kind: StringName = preset.country.walkers[index]
			_walk_kinds.append(kind)
			_walk_lanes.append(NeighbourhoodCountry.LANE_V + NeighbourhoodCountry.LANES[index])
			_walk_speeds.append(COUNTRY_CYCLE_SPEED if kind == &"cycle" else WALKER_SPEEDS.get(kind, WALK_SPEED))
			_walk_strides.append(WALKER_STRIDES.get(kind, 1.0))
			_walk_phases.append(NeighbourhoodGround.hash01(index, 7, street_set.seed_salt))
		return
	for index: int in mini(preset.promenade.walkers.size(), PROMENADE_LANES.size()):
		var kind: StringName = preset.promenade.walkers[index]
		_walk_kinds.append(kind)
		_walk_lanes.append(PROMENADE_LANES[index])
		_walk_speeds.append(WALKER_SPEEDS.get(kind, WALK_SPEED))
		_walk_strides.append(WALKER_STRIDES.get(kind, 1.0))
		_walk_phases.append(NeighbourhoodGround.hash01(index, 5, street_set.seed_salt))


## The bike, pram or dog that goes with each promenade walker, rebuilt with the street.
func _build_walk_props() -> void:
	for prop: Node3D in _walk_props:
		if prop != null:
			if prop.has_meta(&"leash"):
				var old_leash: Node = prop.get_meta(&"leash") as Node
				old_leash.get_parent().remove_child(old_leash)
				old_leash.free()
			prop.get_parent().remove_child(prop)
			prop.free()
	_walk_props.clear()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.disable_receive_shadows = true
	if has_forest():
		_build_forest_walk_props(material)
		return
	if has_country():
		_build_country_walk_props(material)
		return
	for index: int in _walk_kinds.size():
		var kind: StringName = _walk_kinds[index]
		var prop: Node3D = null
		if _promenade != null and (kind == &"cycle" or kind == &"pram" or kind == &"dog"):
			var skin: PromenadeSkin = preset.promenade
			prop = Node3D.new()
			prop.name = "%s%d" % [String(kind).capitalize(), index]
			var body: MeshInstance3D = MeshInstance3D.new()
			body.name = "Body"
			body.material_override = material
			body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			prop.add_child(body)
			match kind:
				&"cycle":
					body.mesh = _promenade.bike(skin.bike_colors[index % skin.bike_colors.size()])
				&"pram":
					body.mesh = _promenade.pram(skin.pram_colors[index % skin.pram_colors.size()])
				_:
					var coat: Color = skin.dog_colors[index % skin.dog_colors.size()]
					body.mesh = _promenade.dog_body(coat)
					var leg_mesh: ArrayMesh = _promenade.dog_leg(coat)
					for leg: int in 4:
						var limb: MeshInstance3D = MeshInstance3D.new()
						limb.name = "Leg%d" % leg
						limb.mesh = leg_mesh
						limb.material_override = material
						limb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						limb.position = Vector3(-0.04 if leg % 2 == 0 else 0.04, 0.12, 0.07 if leg < 2 else -0.09)
						prop.add_child(limb)
					var leash: MeshInstance3D = MeshInstance3D.new()
					leash.name = "Leash%d" % index
					var line: BoxMesh = BoxMesh.new()
					line.size = Vector3(0.012, 0.012, 1.0)
					leash.mesh = line
					var cord: StandardMaterial3D = StandardMaterial3D.new()
					cord.albedo_color = street_set.signal_red.darkened(0.2)
					cord.roughness = 1.0
					leash.material_override = cord
					leash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_actors_root.add_child(leash)
					prop.set_meta(&"leash", leash)
			_actors_root.add_child(prop)
		_walk_props.append(prop)


func _initialize_players() -> void:
	if pedestrians.is_empty() or pedestrians.size() != _walk_kinds.size():
		return
	if _players.size() == pedestrians.size() and not _players.has(null):
		return
	_players.clear()
	_animation_lengths.clear()
	for index: int in pedestrians.size():
		var person: PersonView = pedestrians[index]
		if not person.is_node_ready():
			_players.clear()
			_animation_lengths.clear()
			return
		var kind: StringName = _walk_kinds[index]
		if kind == &"cycle":
			person.set_pose(false, true, false, false, BIKE_SEAT)
		else:
			person.set_pose(true, false, kind == &"pram", false)
		person.set_playback_speed(1.0)
		var players: Array[Node] = person.find_children("*", "AnimationPlayer", true, false)
		var player: AnimationPlayer = players[0] as AnimationPlayer if not players.is_empty() else null
		if player == null or not player.has_animation(&"walk"):
			build_error = "A pedestrian walk animation is unavailable"
			return
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_players.append(player)
		var clip: StringName = player.current_animation if _walk_kinds[index] != &"stroll" and player.current_animation != &"" else &"walk"
		_animation_lengths.append(player.get_animation(clip).length)
		for node: Node in person.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_routes() -> void:
	_routes.clear()
	_pedestrian_sweeps.clear()
	var half_z: float = WALK_HALF if _traffic else PROMENADE_HALF
	for lane: float in _walk_lanes:
		var route: Vector2 = _safe_route(_shift + lane, WALK_HALF, half_z)
		if has_forest() and route.y > route.x:
			# The track runs on into the trees: walk well out of the clearing before turning.
			var middle: float = _local_reserve.get_center().x
			route = Vector2(minf(route.x, middle - NeighbourhoodForest.WALK_REACH), maxf(route.y, middle + NeighbourhoodForest.WALK_REACH))
		elif has_country() and route.y > route.x:
			# The lane runs on between the fields: walk well out of sight before turning.
			var middle: float = _local_reserve.get_center().x
			route = Vector2(minf(route.x, middle - NeighbourhoodCountry.WALK_REACH), maxf(route.y, middle + NeighbourhoodCountry.WALK_REACH))
		_routes.append(route)
		var box: AABB = AABB(Vector3(route.x - WALK_HALF, _paving_top + WALK_BOTTOM, _shift + lane - half_z),
			Vector3(maxf(route.y - route.x, 0.0) + WALK_HALF * 2.0, WALK_TOP - WALK_BOTTOM, half_z * 2.0))
		_pedestrian_sweeps.append(_frame * box)
	if not _traffic:
		_car_route = Vector2.ZERO
		_car_sweep = AABB()
		return
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
	var inverse: Transform3D = _frame.affine_inverse()
	var bulbs: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var glow: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var halo_at: Array[Vector3] = []
	for index: int in (2 if _promenade == null else 0):
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
			# The lamp's bulb sits just proud of its panel; the glow is a soft disc on the
			# pavement beside it. Both are unlit meshes the night level drives (no Light3D).
			var local: Transform3D = inverse * placement
			_lamp_feet.append(Vector2(local.origin.x, local.origin.z - _shift))
			bulbs.xf = local
			bulbs.box(Vector3(-0.117, LAMP_BULB_Y - 0.04, -0.075 - 0.127), Vector3(0.117, LAMP_BULB_Y + 0.04, -0.075 + 0.127), Color.WHITE)
			halo_at.append(local * Vector3(0.0, LAMP_BULB_Y, -0.075))
			var toward: float = -0.55 if index == 0 else 0.55
			_glow_disc(glow, Vector2(local.origin.x, local.origin.z + toward), _paving_top + 0.008)
		else:
			build_error = "A street lamp has no clear outside position"
	prop.free()
	if _promenade != null:
		_build_promenade_lamps(bulbs, glow, halo_at)
	_lamp_spots = halo_at.duplicate()
	if bulbs.soup.is_empty():
		return
	_bulb_material = StandardMaterial3D.new()
	_bulb_material.vertex_color_use_as_albedo = true
	_bulb_material.albedo_color = LAMP_DAY
	_bulb_material.emission_enabled = true
	_bulb_material.emission = LAMP_NIGHT
	_bulb_material.emission_energy_multiplier = 0.0
	_bulb_material.disable_receive_shadows = true
	_lamp_bulbs = MeshInstance3D.new()
	_lamp_bulbs.name = "LampBulbs"
	_lamp_bulbs.mesh = bulbs.soup.to_mesh()
	_lamp_bulbs.material_override = _bulb_material
	_lamp_bulbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_bulbs.transform = _frame
	_life_root.add_child(_lamp_bulbs)
	_glow_material = StandardMaterial3D.new()
	_glow_material.vertex_color_use_as_albedo = true
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.disable_receive_shadows = true
	_lamp_glow = MeshInstance3D.new()
	_lamp_glow.name = "LampGlow"
	_lamp_glow.mesh = glow.to_mesh()
	_lamp_glow.material_override = _glow_material
	_lamp_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_glow.transform = _frame
	_life_root.add_child(_lamp_glow)
	_halo_material = StandardMaterial3D.new()
	_halo_material.vertex_color_use_as_albedo = true
	_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_material.disable_receive_shadows = true
	var halo_mesh: ArrayMesh = _halo_mesh()
	for point: Vector3 in halo_at:
		var halo: MeshInstance3D = MeshInstance3D.new()
		halo.name = "LampHalo%d" % _lamp_halos.size()
		halo.mesh = halo_mesh
		halo.material_override = _halo_material
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.transform = _frame * Transform3D(Basis.IDENTITY, point)
		_life_root.add_child(halo)
		_lamp_halos.append(halo)


## The promenade's double-lantern lamp posts along its centre band (#596): one batched
## mesh, each lantern's bulb, pool of light and halo joining the street's night lights.
func _build_promenade_lamps(bulbs: NeighbourhoodBuildings.Pen, glow: NeighbourhoodGround.Soup, halo_at: Array[Vector3]) -> void:
	var holes: Array[Rect2] = []
	var inverse: Transform3D = _frame.affine_inverse()
	for bounds: AABB in _native_pavement + _door_approaches:
		var local: AABB = inverse * bounds
		holes.append(Rect2(local.position.x, local.position.z - _shift, local.size.x, local.size.z))
	var centre: float = _local_reserve.get_center().x
	var reach: float = FURNITURE_REACH + 6.0
	var spots: Array[float] = _promenade.lamp_spots(centre, maxf(-_visual_half + 1.0, centre - reach),
		minf(_visual_half - 1.0, centre + reach), holes)
	var posts: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	for u: float in spots:
		var local: Transform3D = Transform3D(Basis.IDENTITY, Vector3(u, _paving_top, _shift + NeighbourhoodPromenade.BAND_V))
		posts.xf = local
		var lanterns: Array[Vector3] = _promenade.lamp_post(posts)
		_lamp_feet.append(Vector2(u, NeighbourhoodPromenade.BAND_V))
		for lantern: Vector3 in lanterns:
			bulbs.xf = local
			bulbs.box(lantern - Vector3(0.045, 0.07, 0.045), lantern + Vector3(0.045, 0.07, 0.045), Color.WHITE)
			halo_at.append(local * lantern)
		_glow_disc(glow, Vector2(u, _shift + NeighbourhoodPromenade.BAND_V), _paving_top + 0.008)
	if posts.soup.is_empty():
		return
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.disable_receive_shadows = true
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "PromenadeLamps"
	mesh.mesh = posts.soup.to_mesh()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.transform = _frame
	_groups["StreetLamps"].add_child(mesh)
	_static_meshes.append(mesh)


## A little camera-facing bloom round the lit bulb: rings fading to nothing.
func _halo_mesh() -> ArrayMesh:
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var radii: Array[float] = [0.0, 0.14, 0.3, 0.46]
	var alphas: Array[float] = [0.85, 0.45, 0.15, 0.0]
	var sides: int = 12
	for ring: int in range(1, radii.size()):
		for side: int in sides:
			var a0: float = TAU * float(side) / float(sides)
			var a1: float = TAU * float(side + 1) / float(sides)
			var corners: Array[Array] = [[ring - 1, a0], [ring, a0], [ring, a1], [ring - 1, a1]]
			for order: Array in [[0, 1, 2], [0, 2, 3]]:
				if ring == 1 and order[1] == 2:
					continue
				for corner: int in order:
					var radius: float = radii[corners[corner][0]]
					var angle: float = corners[corner][1]
					soup.positions.append(Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))
					soup.normals.append(Vector3.BACK)
					soup.colors.append(Color(LAMP_NIGHT.r, LAMP_NIGHT.g, LAMP_NIGHT.b, alphas[corners[corner][0]]))
	return soup.to_mesh()


## A soft pool of lamplight: concentric rings fading to nothing, flat on the pavement.
func _glow_disc(soup: NeighbourhoodGround.Soup, centre: Vector2, y: float) -> void:
	var radii: Array[float] = [0.0, 0.4, 0.85, 1.25]
	var alphas: Array[float] = [0.34, 0.2, 0.07, 0.0]
	var sides: int = 16
	for ring: int in range(1, radii.size()):
		for side: int in sides:
			var a0: float = TAU * float(side) / float(sides)
			var a1: float = TAU * float(side + 1) / float(sides)
			var corners: Array[Vector3] = []
			var colours: Array[Color] = []
			for point: Array in [[ring - 1, a0], [ring, a0], [ring, a1], [ring - 1, a1]]:
				var radius: float = radii[point[0]]
				corners.append(Vector3(centre.x + cos(point[1]) * radius, y, centre.y + sin(point[1]) * radius))
				colours.append(Color(LAMP_NIGHT.r, LAMP_NIGHT.g, LAMP_NIGHT.b, alphas[point[0]]))
			for order: Array in [[0, 2, 1], [0, 3, 2]]:
				if ring == 1 and order[1] == 3:
					continue
				for corner: int in order:
					soup.positions.append(corners[corner])
					soup.normals.append(Vector3.UP)
					soup.colors.append(colours[corner])


## 0 by day, 1 at night: the street lamps' bulbs light and their pools of light fade in.
## Main sets it from the day's light (DayNightView.street_night), never the other way round.
## `dark` (DayNightView.street_dark) is 0 through the golden dusk and 1 once the sun has
## gone; the rooftop and the cliff keep a sunset look until it rises. It defaults to 1, the
## full night, so a caller that names only the level gets the night as before.
func set_night(level: float, late: float = 0.0, dark: float = 1.0) -> void:
	var clamped: float = clampf(level, 0.0, 1.0) if is_finite(level) else 0.0
	var late_clamped: float = clampf(late, 0.0, 1.0) if is_finite(late) else 0.0
	var dark_clamped: float = clampf(dark, 0.0, 1.0) if is_finite(dark) else 1.0
	if is_equal_approx(clamped, _night) and is_equal_approx(late_clamped, _late) and is_equal_approx(dark_clamped, _dark):
		return
	_night = clamped
	_late = late_clamped
	_dark = dark_clamped
	_apply_night()


## A gloomy afternoon's early lamplight (WeatherLook.gloom): the street's lamps, windows and
## festoons come on dimly; the sky, sea and city keep the clock's time of day.
func set_gloom(level: float) -> void:
	var value: float = clampf(level, 0.0, 1.0) if is_finite(level) else 0.0
	if is_equal_approx(value, _gloom):
		return
	_gloom = value
	_apply_night()


func gloom() -> float:
	return _gloom


## How lit the street's lamps and windows are: the night, or a gloomy afternoon's glow.
func _lamplight() -> float:
	return maxf(_night, _gloom)


## How lit a window tier is: tier 0 follows the night, tiers 1 and 2 go dark at their bedtimes
## in the late hours.
func _window_level(tier: int) -> float:
	match tier:
		1:
			return _lamplight() * (1.0 - smoothstep(0.3, 0.5, _late))
		2:
			return _lamplight() * (1.0 - smoothstep(0.8, 0.95, _late))
		_:
			return _lamplight()


func _apply_night() -> void:
	if _shore != null:
		_shore.set_night(_night, _late)
	if _forest != null:
		_forest.set_gloom(_gloom)
		_forest.set_night(_night, _late)
	if _country != null:
		_country.set_gloom(_gloom)
		_country.set_night(_night, _late)
	if _rooftop != null:
		_rooftop.set_gloom(_gloom)
		_rooftop.set_night(_night, _late, _dark)
	if _cliff != null:
		_cliff.set_gloom(_gloom)
		_cliff.set_night(_night, _late, _dark)
	for index: int in _window_nodes.size():
		var level: float = _window_level(_window_tier(index))
		_window_nodes[index].visible = level > 0.01
		_window_materials[index].albedo_color = WINDOW_DAY.lerp(Color.WHITE, level)
		_window_materials[index].emission_energy_multiplier = level * WINDOW_ENERGY
	for id: StringName in _neighbour_lamps:
		_light_neighbour(id)
	var lamps: float = _lamplight()
	if _bulb_material != null:
		_bulb_material.emission_energy_multiplier = lamps * LAMP_BULB_ENERGY
		_bulb_material.albedo_color = LAMP_DAY.lerp(LAMP_NIGHT, lamps)
	if _lamp_glow != null:
		_lamp_glow.visible = lamps > 0.01
		_glow_material.albedo_color = Color(1.0, 1.0, 1.0, lamps)
	if _halo_material != null:
		_halo_material.albedo_color = Color(1.0, 1.0, 1.0, lamps)
		for halo: MeshInstance3D in _lamp_halos:
			halo.visible = lamps > 0.01


## The light tier of the index-th window mesh (empty tiers are skipped, so read it from the name).
func _window_tier(index: int) -> int:
	return String(_window_nodes[index].name).trim_prefix("WindowGlow").to_int()


## What the windows show now, for tests and captures: per tier the number of lit-window quads,
## whether it is drawn and its light level.
func window_state() -> Dictionary:
	var tiers: Array[Dictionary] = []
	var quads: int = 0
	for index: int in _window_nodes.size():
		var tier: int = _window_tier(index)
		var count: int = (_window_nodes[index].mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 12
		quads += count
		tiers.append({"tier": tier, "quads": count, "visible": _window_nodes[index].visible,
			"level": _window_level(tier), "energy": _window_materials[index].emission_energy_multiplier})
	return {"night": _night, "late": _late, "tiers": tiers, "quads": quads}


## What the lamps show now, for tests and captures.
func lamp_state() -> Dictionary:
	return {"night": _night, "lamps": _lamp_feet.size(),
		"bulb_energy": _bulb_material.emission_energy_multiplier if _bulb_material != null else -1.0,
		"glow_visible": _lamp_glow != null and _lamp_glow.visible,
		"halos_visible": _lamp_halos.size() > 0 and _lamp_halos[0].visible,
		"glow_alpha": _glow_material.albedo_color.a if _glow_material != null else -1.0}


## Planter trees, benches, bins and the rest on the near pavement, planned inside the free
## band and meshed once (#423).
func _build_furniture() -> void:
	var inverse: Transform3D = _frame.affine_inverse()
	var planner: NeighbourhoodFurniture = NeighbourhoodFurniture.new()
	planner.street = street_set
	planner.lot_u = Vector2(_local_reserve.position.x, _local_reserve.end.x)
	planner.u_range = Vector2(maxf(-_visual_half + 0.8, planner.lot_u.x - FURNITURE_REACH),
		minf(_visual_half - 0.8, planner.lot_u.y + FURNITURE_REACH))
	var margins: Array[Array] = [[_native_pavement, 0.2], [_door_approaches, 0.1], [_pedestrian_sweeps, 0.0]]
	for entry: Array in margins:
		for box: AABB in entry[0]:
			var local: AABB = inverse * box
			planner.exclusions.append(Rect2(local.position.x, local.position.z - _shift, local.size.x, local.size.z).grow(entry[1]))
	for box: AABB in _building_boxes:
		planner.exclusions.append(Rect2(box.position.x, box.position.z - _shift, box.size.x, box.size.z).grow(0.1))
	if _promenade != null:
		for foot: Vector2 in _lamp_feet:
			planner.exclusions.append(Rect2(foot - NeighbourhoodPromenade.LAMP_FOOT * 0.5, NeighbourhoodPromenade.LAMP_FOOT).grow(0.25))
	planner.doors = _shop_doors
	planner.building_spans = _shop_spans
	planner.plan()
	_furniture = planner.placed
	_crowns = planner.tree_crowns()
	for mesh: MeshInstance3D in planner.build_meshes(_paving_top, _shift, _compute_light_shift(), _lamp_feet):
		mesh.transform = _frame
		_groups["Furniture"].add_child(mesh)
		_static_meshes.append(mesh)


## The idle life: hanging signs, birds and leaves (#423).
func _build_life() -> void:
	_life = NeighbourhoodLife.new()
	_life.street = street_set
	_life.frame = _frame
	_life.shift = _shift
	_life.paving_top = _paving_top
	_life.crowns = _crowns
	_life.signs = _building_signs
	_life.lot_u = Vector2(_local_reserve.position.x, _local_reserve.end.x)
	_life.row_u = _life.lot_u
	for span: Vector2 in _shop_spans:
		_life.row_u = Vector2(minf(_life.row_u.x, span.x), maxf(_life.row_u.y, span.y))
	_life.build(_life_root)


## True when the street's preset has a beach behind its back lane (#588).
func has_shore() -> bool:
	return preset != null and preset.shore != null


## The beach and sea (#588): built on the street frame behind the back lane.
func _build_shore() -> void:
	_shore_root.transform = _frame
	if not has_shore():
		return
	_shore = NeighbourhoodShore.new()
	_shore.skin = preset.shore
	_shore.salt = street_set.seed_salt
	_shore.lane_v = NeighbourhoodGround.back_lane_v(_local_reserve, true)
	_shore.path_u = _local_reserve.get_center().x
	var rect: Rect2 = world_rect()
	var centre: Vector3 = _frame.affine_inverse() * Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	_shore.world_centre = Vector2(centre.x, centre.z)
	_shore.light_shift = _compute_light_shift()
	_shore.build(_shore_root)


func shore() -> NeighbourhoodShore:
	return _shore


## Local-frame footprints (u, v) and sizes of the street furniture, for tools and tests.
func furniture_plan() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: NeighbourhoodFurniture.Placed in _furniture:
		var rect: Rect2 = item.rect()
		result.append({"kind": item.kind, "u": item.u, "v": item.v, "rect": rect, "height": item.size.y})
	return result


## The street-local frame and shift: tests convert plan coordinates with these.
func local_frame() -> Transform3D:
	return _frame


func street_shift() -> float:
	return _shift


func life() -> NeighbourhoodLife:
	return _life


## Street-local x of each neighbouring shop's front door.
func shop_door_positions() -> Array[float]:
	return _shop_doors.duplicate()


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


## The street's clock as it is shown: the review time when one is set, else the display clock.
func shown_time() -> float:
	return _effective_time()


func _effective_time() -> float:
	return _review_time if _review_time >= 0.0 else _display_seconds


func _apply_time(seconds: float) -> void:
	if not _configured:
		return
	_wet.set_sway_time(seconds)
	if _life != null:
		_life.apply(seconds)
	if _shore != null:
		_shore.apply(seconds)
	if _forest != null:
		_forest.apply(seconds)
	if _country != null:
		_country.apply(seconds)
	if _rooftop != null:
		_rooftop.apply(seconds)
	if _cliff != null:
		_cliff.apply(seconds)
	var walkers: int = _walk_kinds.size()
	if walkers == 0 or pedestrians.size() != walkers or _routes.size() != walkers or car == null:
		return
	for index: int in walkers:
		var route: Vector2 = _routes[index]
		var length: float = route.y - route.x
		if length <= 0.0 or stays_in(index):
			pedestrians[index].hide()
			if _walk_props[index] != null:
				_walk_props[index].hide()
			continue
		var progress: float = fposmod(seconds * _walk_speeds[index] + _walk_phases[index] * length * 2.0, length * 2.0)
		var forward: bool = progress <= length
		var u: float = route.x + progress if forward else route.y - (progress - length)
		var person: PersonView = pedestrians[index]
		person.position = _frame * Vector3(u, _walk_y, _shift + _walk_lanes[index])
		_directions[index] = _tangent if forward else -_tangent
		if _forest != null:
			# The track winds: follow its bends and face along them.
			var bend: float = _forest.track_z(u) - _shift - NeighbourhoodForest.TRACK_V
			person.position = _frame * Vector3(u, _walk_y, _shift + _walk_lanes[index] + bend)
			var along: Vector3 = (_tangent + _outward * _forest.track_slope(u)).normalized()
			_directions[index] = along if forward else -along
		elif _country != null:
			# The lane bends gently away from the mill: follow it.
			var bend: float = _country.lane_z(u) - _shift - NeighbourhoodCountry.LANE_V
			person.position = _frame * Vector3(u, _walk_y, _shift + _walk_lanes[index] + bend)
			var along: Vector3 = (_tangent + _outward * _country.lane_slope(u)).normalized()
			_directions[index] = along if forward else -along
		person.face_direction(_directions[index])
		person.show()
		if _players.size() == walkers:
			_players[index].seek(fposmod(seconds * _walk_strides[index] + _walk_phases[index], _animation_lengths[index]), true)
		if _walk_props[index] != null:
			_place_walk_prop(index, seconds, route, progress)
	if not _traffic:
		car.hide()
		return
	var travel: float = (_car_route.y - _car_route.x) / CAR_SPEED
	var phase: float = fposmod(seconds, maxf(travel + CAR_REST, 1.0))
	car.visible = travel > 0.0 and phase >= 1.0 and phase <= travel + 1.0
	var u: float = _car_route.x + clampf(phase - 1.0, 0.0, maxf(travel, 0.0)) * CAR_SPEED
	car.transform = Transform3D(_car_rotation, _frame * Vector3(u, 0.0, _shift + CAR_LANE))


## A walker's bike, pram or dog (#596), placed from the same closed-form path: the bike
## under the rider, the pram ahead of the hands, and the dog trotting ahead on its leash
## (further along the walker's own back-and-forth path, so it turns first at the ends).
func _place_walk_prop(index: int, seconds: float, route: Vector2, progress: float) -> void:
	var prop: Node3D = _walk_props[index]
	var person: PersonView = pedestrians[index]
	var facing: Basis = Basis(Vector3.UP, atan2(_directions[index].x, _directions[index].z))
	prop.show()
	match _walk_kinds[index]:
		&"cycle":
			prop.transform = Transform3D(facing, person.position + _directions[index] * 0.06)
		&"pram":
			prop.transform = Transform3D(facing, person.position + _directions[index] * 0.12)
		&"hike":
			prop.transform = Transform3D(facing, person.position)
		&"dog":
			var length: float = route.y - route.x
			var lead: float = fposmod(progress + DOG_LEAD, length * 2.0)
			var ahead: bool = lead <= length
			var u: float = route.x + lead if ahead else route.y - (lead - length)
			var heading: Vector3 = _tangent if ahead else -_tangent
			var side: Vector3 = _outward * DOG_SIDE
			var hop: float = absf(sin(seconds * 9.0 + float(index))) * 0.012
			prop.transform = Transform3D(Basis(Vector3.UP, atan2(heading.x, heading.z)),
				_frame * Vector3(u, _paving_top + hop, _shift + _walk_lanes[index]) + side)
			for leg: int in 4:
				var limb: Node3D = prop.get_node(NodePath("Leg%d" % leg)) as Node3D
				var swing: float = sin(seconds * 9.0 + (PI if leg == 0 or leg == 3 else 0.0))
				limb.rotation = Vector3(swing * 0.55, 0.0, 0.0)
			var leash: MeshInstance3D = prop.get_meta(&"leash") as MeshInstance3D
			var hand: Vector3 = person.position + Basis(Vector3.UP, person.rotation.y) * Vector3(LEASH_HAND.x, LEASH_HAND.y, -LEASH_HAND.z)
			var collar: Vector3 = prop.transform * Vector3(0.0, 0.2, 0.08)
			var span: Vector3 = collar - hand
			if span.length() > 0.05:
				var look: Basis = Basis.looking_at(span.normalized(), Vector3.UP)
				leash.transform = Transform3D(look * Basis.from_scale(Vector3(1.0, 1.0, span.length())), (hand + collar) * 0.5)


# --- weather ------------------------------------------------------------------

## Puts the day's weather (WeatherState.Kind) on the street: a wet, glossy street and
## fewer people out in the rain, a fainter shadow under a cloudy sky, and each place's own
## weather (a rougher grey sea, swaying crops, thicker city haze). Sunny undoes it all.
func set_weather(kind: int) -> void:
	_weather = clampi(kind, WeatherState.Kind.SUNNY, WeatherState.Kind.RAIN)
	_apply_weather()
	_apply_time(_effective_time())


func weather() -> int:
	return _weather


## The wet sheen's light (the sky's light now), the camera's forward on the ground and how
## much darker the wet ground gets.
func set_weather_light(sheen_color: Color, view_dir: Vector2, darken: float = WeatherWet.DARKEN) -> void:
	_wet.set_light(sheen_color, view_dir, darken)


## The materials the rain put on the street (for tests): empty on a dry day.
func wet_state() -> Dictionary:
	return {"kind": _weather, "swaps": _wet.swap_count(), "materials": _wet.wet_materials(), "sway": _wet.sway_materials()}


func _apply_weather() -> void:
	# Every weather: the foliage sways in all of them, rain wets, cloud fades shadows.
	_wet.apply(self, _weather)
	_apply_place_weather()


func _apply_place_weather() -> void:
	if _shore != null:
		_shore.set_weather(_weather)
	if _forest != null:
		_forest.set_weather(_weather)
	if _country != null:
		_country.set_weather(_weather)
	if _rooftop != null:
		_rooftop.set_weather(_weather)
	if _cliff != null:
		_cliff.set_weather(_weather)


## The street's lamps (the dressing's parent's space): each one's light as (x, y, z) and the
## ground height under it in w, for the glow it casts on a wet street at night.
func lamp_spots() -> Array[Vector4]:
	var result: Array[Vector4] = []
	if not _configured:
		return result
	var local: Array[Vector3] = _lamp_spots.duplicate()
	var ground: float = _paving_top
	if _country != null:
		local = _country.lamp_spots()
		ground = NeighbourhoodCountry.LANE_Y
	elif _cliff != null:
		local = _cliff.lamp_spots()
		ground = NeighbourhoodCliff.PATH_Y
	if _rooftop != null:
		# The roof's pools of lamplight, each given on the ground under it.
		for spot: Vector3 in _rooftop.lamp_spots():
			var foot: Vector3 = transform * (_frame * spot)
			result.append(Vector4(foot.x, foot.y + 1.2, foot.z, foot.y))
		return result
	for spot: Vector3 in local:
		var at: Vector3 = transform * (_frame * spot)
		result.append(Vector4(at.x, at.y, at.z, (transform * (_frame * Vector3(spot.x, ground, spot.z))).y))
	return result


## In the rain every other passer-by stays indoors (the first one is always out).
func stays_in(index: int) -> bool:
	return _weather == WeatherState.Kind.RAIN and index % 2 == 1


## Up to `count` places for puddles or splashes on the street's paving, road, track or
## roof near the shop, as (x, y, z, radius) in the dressing's parent's space: each one's
## centre and the room it has (`size` scales the radius; 0 gives points). Seeded by
## position and `salt`, so the same street always gets the same puddles.
func wet_spots(count: int, salt: int, size: float = 1.0) -> Array[Vector4]:
	var result: Array[Vector4] = []
	if not _configured:
		return result
	var tries: int = count * 12
	for index: int in tries:
		if result.size() >= count:
			break
		var a: float = NeighbourhoodGround.hash01(index, salt, 811)
		var b: float = NeighbourhoodGround.hash01(index, salt, 977)
		var c: float = NeighbourhoodGround.hash01(index, salt, 433)
		var u: float = _local_reserve.get_center().x + (a * 2.0 - 1.0) * FURNITURE_REACH
		var radius: float = (0.22 + 0.4 * c * c) * size
		var spot: Vector3 = _wet_spot(u, b, radius)
		if is_nan(spot.y):
			continue
		var clear: bool = true
		for other: Vector4 in result:
			if Vector2(other.x, other.z).distance_to(Vector2(spot.x, spot.z)) < other.w + radius + 0.3:
				clear = false
				break
		if not clear:
			continue
		var at: Vector3 = transform * (_frame * spot)
		if not _wet_cell_clear(at, radius):
			continue
		result.append(Vector4(at.x, at.y, at.z, radius))
	return result


## A spot at `u` across the place's walkable band (`across` 0..1), in the street's local
## frame, or NaN in y when the place has nowhere wet there.
func _wet_spot(u: float, across: float, radius: float) -> Vector3:
	var none: Vector3 = Vector3(0.0, NAN, 0.0)
	var z: float = 0.0
	var y: float = 0.0
	if _forest != null:
		z = _forest.track_z(u) + (across * 2.0 - 1.0) * maxf(NeighbourhoodForest.TRACK_HALF - radius - 0.15, 0.0)
		y = NeighbourhoodForest.TRACK_Y
	elif _country != null:
		z = _country.lane_z(u) + (across * 2.0 - 1.0) * maxf(NeighbourhoodCountry.LANE_HALF - radius - 0.15, 0.0)
		y = NeighbourhoodCountry.LANE_Y
	elif _cliff != null:
		var on: Vector2 = _cliff.wet_spot(across, u, radius)
		if is_nan(on.x):
			return none
		return Vector3(on.x, NeighbourhoodCliff.PATH_Y, on.y)
	elif _rooftop != null:
		var roof: Vector2 = _rooftop.wet_spot(across, u, radius)
		if is_nan(roof.x):
			return none
		return Vector3(roof.x, NeighbourhoodRooftop.ROOF_Y, roof.y)
	elif _traffic:
		# Near pavement, road or far pavement, by thirds.
		var band: int = mini(int(across * 3.0), 2)
		var t: float = fposmod(across * 3.0, 1.0)
		var bands: Array[Vector2] = [Vector2(PAVING_START, PAVING_START + PAVING_DEPTH),
			Vector2(ROAD_START, ROAD_END), Vector2(FAR_START, FAR_START + FAR_DEPTH)]
		var span: Vector2 = bands[band]
		var inset: float = radius + 0.2
		if span.y - span.x <= inset * 2.0:
			return none
		z = _shift + lerpf(span.x + inset, span.y - inset, t)
		y = 0.0 if band == 1 else _paving_top
	elif _promenade != null:
		var inset: float = radius + 0.3
		z = _shift + lerpf(PAVING_START + inset, FAR_START + FAR_DEPTH - inset, across)
		y = _paving_top
	else:
		return none
	var point: Vector2 = Vector2(u, z - _shift)
	for placed: NeighbourhoodFurniture.Placed in _furniture:
		if placed.rect().grow(radius + 0.15).has_point(point):
			return none
	var local: Rect2 = Rect2(_local_reserve.position.x, _local_reserve.position.z, _local_reserve.size.x, _local_reserve.size.z)
	if local.grow(radius + 0.2).has_point(Vector2(u, z)):
		return none
	return Vector3(u, y, z)


## True when a spot of `radius` round `at` (the dressing's parent's space) lies wholly off
## the shop: every grid cell it touches is plain outside, never floor, wall or patio.
func _wet_cell_clear(at: Vector3, radius: float) -> bool:
	if _grid == null:
		return true
	var low: Vector2i = GridMath.world_to_cell(at - Vector3(radius, 0.0, radius))
	var high: Vector2i = GridMath.world_to_cell(at + Vector3(radius, 0.0, radius))
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if _grid.bounds.has_point(cell) and (_grid.terrain(cell) != SimGrid.Terrain.OUTSIDE or _grid.is_outdoor_floor(cell)):
				return false
	return true


# --- the woodland clearing (#607) and its stands of trees (for #597) -----------

## The street's own ground, tree line and far road belong to a street, not a clearing:
## a woodland preset drops them (their caches stay for the next street that needs them).
func _clear_street_ground() -> void:
	for root: Node3D in [ground_root, far_root]:
		for child: Node in root.get_children():
			root.remove_child(child)
			child.free()
	_ground_key = []
	_far_key = []
	_near_pavement = AABB()
	_far_pavement = AABB()


## The clearing, the track, the stream and the stands, built on the street frame.
func _build_forest() -> void:
	_forest_root.transform = _frame
	_forest = NeighbourhoodForest.new()
	_forest.skin = preset.forest
	_forest.salt = street_set.seed_salt
	_forest.local_reserve = _local_reserve
	_forest.shift = _shift
	_forest.light_shift = _compute_light_shift()
	_forest.compass = _frame.basis
	var inverse: Transform3D = _frame.affine_inverse()
	for box: AABB in _door_approaches + _native_pavement:
		var local: AABB = inverse * box
		_forest.keep_clear.append(Rect2(local.position.x, local.position.z, local.size.x, local.size.z))
	var rect: Rect2 = world_rect()
	var centre: Vector3 = inverse * Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	_forest.world_centre = Vector2(centre.x, centre.z)
	_forest.lease = _local_cells(_lease)
	_forest.first_lease = _local_cells(_first_lease)
	_forest.building = _local_cells(_built_rect)
	# The shop's own patio in front is the cabin's porch (#596).
	for cell: Vector2i in _grid.cells():
		if _grid.is_outdoor_floor(cell):
			_forest.patio.append(_local_cells(Rect2i(cell, Vector2i.ONE)))
	_forest.patio_top = _paving_top
	_forest.build(_forest_root)
	for id: StringName in _forest.stand_ids():
		_forest.show_stand(id, stand_state(id))


## A rect of grid cells in the street frame's local (u, z); empty stays empty.
func _local_cells(cells: Rect2i) -> Rect2:
	if not cells.has_area():
		return Rect2()
	var box: AABB = _frame.affine_inverse() * AABB(Vector3(cells.position.x * GridMath.CELL_SIZE, 0.0, cells.position.y * GridMath.CELL_SIZE),
		Vector3(cells.size.x * GridMath.CELL_SIZE, 1.0, cells.size.y * GridMath.CELL_SIZE))
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


## A hiker's backpack or a cyclist's bike for each walker on the forest track.
func _build_forest_walk_props(material: StandardMaterial3D) -> void:
	var kit: NeighbourhoodPromenade = NeighbourhoodPromenade.new(null, street_set)
	var forest: NeighbourhoodForest = NeighbourhoodForest.new()
	forest.skin = preset.forest
	for index: int in _walk_kinds.size():
		var kind: StringName = _walk_kinds[index]
		var prop: Node3D = null
		if kind == &"cycle" or kind == &"hike":
			prop = Node3D.new()
			prop.name = "%s%d" % [String(kind).capitalize(), index]
			var body: MeshInstance3D = MeshInstance3D.new()
			body.name = "Body"
			body.material_override = material
			body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if kind == &"cycle":
				body.mesh = kit.bike(preset.forest.bike_colors[index % preset.forest.bike_colors.size()])
			else:
				body.mesh = forest.backpack(preset.forest.pack_colors[index % preset.forest.pack_colors.size()])
			prop.add_child(body)
			_actors_root.add_child(prop)
		_walk_props.append(prop)


func forest() -> NeighbourhoodForest:
	return _forest


## The ids of the named stands of trees round the lot (#597): the two sides and the
## back, named by compass (`west`, `east`, `north`, `south`: east is world +x, north
## -z), then the land stands on the lot's land outside its first lease (#611), named
## the same way with `_land` (`east_land`). Empty on a street without a forest.
func stand_ids() -> Array[StringName]:
	return _forest.stand_ids() if _forest != null else [] as Array[StringName]


## What a stand shows. A land stand the current lease covers is the player's land:
## felled to stumps unless it was cleared, never trees.
func stand_state(id: StringName) -> NeighbourhoodForest.StandState:
	var state: NeighbourhoodForest.StandState = _stand_states.get(id, NeighbourhoodForest.StandState.FOREST) as NeighbourhoodForest.StandState
	var entry: NeighbourhoodForest.Stand = _forest.stand(id) if _forest != null else null
	if entry != null and entry.leased and state == NeighbourhoodForest.StandState.FOREST:
		return NeighbourhoodForest.StandState.STUMPS
	return state


## True for a land stand (#611) that the current lease covers.
func stand_leased(id: StringName) -> bool:
	var entry: NeighbourhoodForest.Stand = _forest.stand(id) if _forest != null else null
	return entry != null and entry.leased


## Shows a stand as forest (the default), felled to stumps, or cleared ground. The state
## is kept across rebuilds. False when the street has no such stand, or for trees on
## land the lease covers (#611).
func set_stand_state(id: StringName, state: NeighbourhoodForest.StandState) -> bool:
	if _forest == null or not _forest.stand_ids().has(id):
		return false
	if stand_leased(id) and state == NeighbourhoodForest.StandState.FOREST:
		return false
	_stand_states[id] = state
	_forest.show_stand(id, state)
	_apply_weather()
	return true


## Everything a stand's trees cover, crowns included, in the dressing's space (an empty
## box when there is no such stand). A stand round the lot never overlaps the lot's
## maximum footprint; a land stand never overlaps its first lease (#611).
func stand_bounds(id: StringName) -> AABB:
	var entry: NeighbourhoodForest.Stand = _forest.stand(id) if _forest != null else null
	if entry == null:
		return AABB()
	var area: Rect2 = entry.crowns
	return _frame * AABB(Vector3(area.position.x, 0.0, area.position.y), Vector3(area.size.x, 4.0, area.size.y))


# --- the city rooftop (#614) ---------------------------------------------------

## The roof, its lobby, terrace and plant, and the city below, built on the street frame.
func _build_rooftop() -> void:
	_rooftop_root.transform = _frame
	_rooftop = NeighbourhoodRooftop.new()
	_rooftop.skin = preset.rooftop
	_rooftop.salt = street_set.seed_salt
	_rooftop.local_reserve = _local_reserve
	_rooftop.shift = _shift
	_rooftop.light_shift = _compute_light_shift()
	var inverse: Transform3D = _frame.affine_inverse()
	for box: AABB in _door_approaches + _native_pavement:
		var local: AABB = inverse * box
		_rooftop.keep_clear.append(Rect2(local.position.x, local.position.z, local.size.x, local.size.z))
	_rooftop.building = _local_cells(_built_rect)
	_rooftop.build(_rooftop_root)


func rooftop() -> NeighbourhoodRooftop:
	return _rooftop


# --- the cliff top (#380) ------------------------------------------------------

## The cliff top, the drop, the sea below and the cliff path, built on the street frame.
func _build_cliff() -> void:
	_cliff_root.transform = _frame
	_cliff = NeighbourhoodCliff.new()
	_cliff.skin = preset.cliff
	_cliff.salt = street_set.seed_salt
	_cliff.local_reserve = _local_reserve
	_cliff.shift = _shift
	_cliff.light_shift = _compute_light_shift()
	var inverse: Transform3D = _frame.affine_inverse()
	for box: AABB in _door_approaches + _native_pavement:
		var local: AABB = inverse * box
		_cliff.keep_clear.append(Rect2(local.position.x, local.position.z, local.size.x, local.size.z))
	var rect: Rect2 = world_rect()
	var centre: Vector3 = inverse * Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	_cliff.world_centre = Vector2(centre.x, centre.z)
	_cliff.building = _local_cells(_built_rect)
	_cliff.build(_cliff_root)


func cliff() -> NeighbourhoodCliff:
	return _cliff


## Where the street's walkers are now (#596), for tests and tools: their kind, position
## and heading in the dressing's space.
func walker_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in mini(pedestrians.size(), _walk_kinds.size()):
		var entry: Dictionary = {"kind": _walk_kinds[index], "position": pedestrians[index].position,
			"direction": _directions[index], "visible": pedestrians[index].visible}
		if index < _walk_props.size() and _walk_props[index] != null:
			entry["prop"] = _walk_props[index].position
		result.append(entry)
	return result


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
		"static_mesh_count": _static_meshes.size(), "pedestrian_count": pedestrians.size(), "car_count": 1 if car != null and _traffic else 0,
		"frame": {"origin": _v(_frame.origin), "normal": _v(_outward), "tangent": _v(_tangent), "reserve_shift": _shift},
		"bounds": {"reserve": _box_state(_reserve), "near_pavement": _box_state(_near_pavement), "road": _box_state(_road),
			"far_pavement": _box_state(_far_pavement), "door_approaches": _boxes_state(_door_approaches),
			"native_pavement": _boxes_state(_native_pavement), "pedestrian_sweeps": _boxes_state(_pedestrian_sweeps),
			"car_sweep": _box_state(_car_sweep)}, "actors": actors,
		"car": {"visible": car.is_visible_in_tree(), "position": _v(car.position), "global_transform": _xf(car.global_transform if car.is_inside_tree() else car.transform)} if car != null and _traffic else {}}


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


# --- the country lane (#613) and its land plots ----------------------------------

## The lane, the mill stream, the fields and the plots, built on the street frame.
func _build_country() -> void:
	_country_root.transform = _frame
	_country = NeighbourhoodCountry.new()
	_country.skin = preset.country
	_country.salt = street_set.seed_salt
	_country.local_reserve = _local_reserve
	_country.shift = _shift
	_country.light_shift = _compute_light_shift()
	_country.compass = _frame.basis
	var inverse: Transform3D = _frame.affine_inverse()
	for box: AABB in _door_approaches + _native_pavement:
		var local: AABB = inverse * box
		_country.keep_clear.append(Rect2(local.position.x, local.position.z, local.size.x, local.size.z))
	var rect: Rect2 = world_rect()
	var centre: Vector3 = inverse * Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	_country.world_centre = Vector2(centre.x, centre.z)
	_country.lease = _local_cells(_lease)
	_country.first_lease = _local_cells(_first_lease)
	_country.building = _local_cells(_built_rect)
	for cell: Vector2i in _built_cells:
		_country.built.append(_local_cells(Rect2i(cell, Vector2i.ONE)))
	_country.build(_country_root)
	for id: StringName in _country.plot_ids():
		_country.show_plot(id, plot_state(id))


## A bike for each cyclist on the country lane; walkers go on foot.
func _build_country_walk_props(material: StandardMaterial3D) -> void:
	var kit: NeighbourhoodPromenade = NeighbourhoodPromenade.new(null, street_set)
	for index: int in _walk_kinds.size():
		var prop: Node3D = null
		if _walk_kinds[index] == &"cycle":
			prop = Node3D.new()
			prop.name = "Cycle%d" % index
			var body: MeshInstance3D = MeshInstance3D.new()
			body.name = "Body"
			body.material_override = material
			body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.mesh = kit.bike(preset.country.bike_colors[index % preset.country.bike_colors.size()])
			prop.add_child(body)
			_actors_root.add_child(prop)
		_walk_props.append(prop)


func country() -> NeighbourhoodCountry:
	return _country


## The ids of the named land plots round the lot (#613, for #597): the meadow beside it
## and the cornfield behind it, named by compass (`east`, `north`, ...: east is world
## +x, north -z), then the land plots on the lot's land outside its first lease, named
## the same way with `_land` (`east_land`). Empty on a street without a country lane.
func plot_ids() -> Array[StringName]:
	return _country.plot_ids() if _country != null else [] as Array[StringName]


## What a plot grows: &"meadow" or &"corn" (&"" when there is no such plot).
func plot_crop(id: StringName) -> StringName:
	var entry: NeighbourhoodCountry.Plot = _country.plot(id) if _country != null else null
	return entry.crop if entry != null else &""


## What a plot shows. A land plot the current lease covers is the player's land: mown
## flat unless it was cleared, never its standing crop.
func plot_state(id: StringName) -> NeighbourhoodCountry.PlotState:
	var state: NeighbourhoodCountry.PlotState = _plot_states.get(id, NeighbourhoodCountry.PlotState.GROWN) as NeighbourhoodCountry.PlotState
	var entry: NeighbourhoodCountry.Plot = _country.plot(id) if _country != null else null
	if entry != null and entry.leased and state == NeighbourhoodCountry.PlotState.GROWN:
		return NeighbourhoodCountry.PlotState.MOWN
	return state


## True for a land plot that the current lease covers.
func plot_leased(id: StringName) -> bool:
	var entry: NeighbourhoodCountry.Plot = _country.plot(id) if _country != null else null
	return entry != null and entry.leased


## Shows a plot grown (the default), mown or cleared. The state is kept across
## rebuilds. False when the street has no such plot, or for a standing crop on land the
## lease covers.
func set_plot_state(id: StringName, state: NeighbourhoodCountry.PlotState) -> bool:
	if _country == null or not _country.plot_ids().has(id):
		return false
	if plot_leased(id) and state == NeighbourhoodCountry.PlotState.GROWN:
		return false
	_plot_states[id] = state
	_country.show_plot(id, state)
	_apply_weather()
	return true


## The ground a plot covers, in the dressing's space (an empty box when there is no
## such plot). A plot round the lot never overlaps the lot's maximum footprint; a land
## plot never overlaps its first lease.
func plot_bounds(id: StringName) -> AABB:
	var entry: NeighbourhoodCountry.Plot = _country.plot(id) if _country != null else null
	if entry == null:
		return AABB()
	var area: Rect2 = entry.rect
	return _frame * AABB(Vector3(area.position.x, 0.0, area.position.y), Vector3(area.size.x, 1.0, area.size.y))
