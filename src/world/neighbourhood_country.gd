class_name NeighbourhoodCountry
extends RefCounted
## An old watermill on a country lane instead of a street (#613). A narrow lane runs
## past the shop's front, between hedgerows, with a grass strip down its middle; a slow
## tractor and a cyclist come along it now and then. A gravel forecourt behind a low
## dry-stone wall opens on the lane. The mill stream runs past the shop's side: over a
## little weir below the mill pond behind, under a turning waterwheel on the shop's
## wall, and under the lane's stone bridge. Beside the shop a wildflower meadow runs
## down to a farm gate with a produce stand (crates of veg and an honesty box) on the
## verge; a cornfield stands out back. Beyond, a patchwork of fields between hedgerows
## and dry-stone walls, oaks, a willow by the water, far cottages, sheep and swallows.
## At night the lanterns and the cottages' windows glow.
##
## The meadow and the cornfield beside and behind the lot are named land plots (#597,
## mirroring the woodland's stands): each can show its crop, mown or cleared without a
## rebuild. The lot's land not leased yet is meadow or corn too (`east_land`, ...), right
## up to the leased land, and is mown flat once the lease covers it.
##
## View-only, like the rest of the neighbourhood: no colliders, sim agents, saves,
## lights or random draws. Everything placed comes from an integer hash and every motion
## (the wheel, the tractor, the sheep, the birds) is a closed-form function of the
## street's display clock, so a paused capture always shows the same frame. Authored in
## the street's local frame (u along the front, z outward past the door), under one root
## the dressing places on that frame. The static meshes are cached per street.

const GLOW_SHADER: Shader = preload("res://src/world/forest_glow.gdshader")
const STREAM_SHADER: Shader = preload("res://src/world/forest_stream.gdshader")
const WHEAT_SHADER: Shader = preload("res://src/world/country_wheat.gdshader")
const FIELD_SHADER: Shader = preload("res://src/world/country_field.gdshader")

enum PlotState { GROWN, MOWN, CLEARED }

## Ground layers sit 3 mm or more apart, all under the shop floor (y 0).
const FLOOR_Y: float = -0.062
const PATCH_Y: float = -0.058
const FIELD_Y: float = -0.054
const PLOT_Y: float = -0.047
const PLOT_TOP: float = -0.044
const GRAVEL_Y: float = -0.044
const BANK_Y: float = -0.041
const EDGE_Y: float = -0.039
const LANE_Y: float = -0.036
const MARK_Y: float = -0.033
const WATER_Y: float = -0.028
const FOAM_Y: float = -0.025
const SHADOW_Y: float = -0.021
## Where people walk on the lane (their feet).
const WALK_Y: float = -0.034
## The lane's centre (v past the lot's front) and half width: one tractor wide.
const LANE_V: float = 3.95
const LANE_HALF: float = 0.85
## The verge between the lane and the hedgerows on the shop's side, and the far side.
const NEAR_VERGE: float = 0.95
const FAR_VERGE: float = 0.7
## The walking lanes across the lane (offsets from its centre line): the cyclist on
## one side, walkers on the other, the tractor down the middle.
const LANES: Array[float] = [0.52, -0.58, 0.6, -0.5]
const TRACTOR_LANE: float = -0.04
## How far walkers and the tractor go either way from the lot's middle before turning.
const WALK_REACH: float = 24.0
## The mill stream: its centre's distance outside the lot's side and its half width.
const STREAM_GAP: float = 0.66
const STREAM_HALF: float = 0.5
## Gap between the lot (its maximum footprint) and the plots round it.
const PLOT_GAP: float = 0.12
## The waterwheel: radius, width and turning speed (radians a second).
const WHEEL_RADIUS: float = 0.82
const WHEEL_WIDTH: float = 0.3
const WHEEL_SPEED: float = 0.55
## The wheel house (#619): a slate lean-to over the wheel, off the lot. Half its length
## along the stream, how far its roof reaches out from the lot's edge, and the roof's
## height there and at its eaves over the water.
const HOUSE_HALF: float = 1.02
const HOUSE_REACH: float = 0.8
const HOUSE_HIGH: float = 1.66
const HOUSE_LOW: float = 1.4
## The axle housing's half width (along z) and its top; it runs from the wheel house
## across any strip of the lot to the shop's wall.
const CASING_HALF: float = 0.17
const CASING_TOP: float = 0.62
## The wheat's canopy: its cell (metres) and its height over the earth.
const WHEAT_CELL: float = 0.3
const WHEAT_HEIGHT: float = 0.43
## The tractor's speed (m/s), its rest off-screen between runs (s), and the hour it goes home.
const TRACTOR_SPEED: float = 1.05
const TRACTOR_REST: float = 26.0
const NIGHT_HIDE: float = 0.5
## Sheep are drawn at person scale: a back about half a person's height.
const SHEEP_SCALE: float = 1.45
## Far fields: the patchwork's column width and row depth (metres).
const FIELD_W: float = 11.0
const FIELD_D: float = 9.5
## Far crop fields are drawn on a grid this coarse (metres), soft tones blending across it.
const FIELD_CELL: float = 0.9
## The far crops by distance from the lot, nearest first, in an order that keeps
## neighbours apart (skin.field_colors: pale barley beside the golden cornfield, then a
## young green crop, wheat, ploughed earth, ripe gold and a second green).
const CROP_ORDER: Array[int] = [1, 4, 0, 3, 2, 5]
## Boundaries farther than this from the lot are drawn plain (a low box, no stones).
const DETAIL_REACH: float = 19.0

## One named land plot (#597): its id, the local rect it fills, its crop and its looks.
class Plot extends RefCounted:
	var id: StringName
	var rect: Rect2
	## &"meadow" or &"corn".
	var crop: StringName = &"meadow"
	var node: Node3D
	## True for the plot behind the lot, false for those beside it.
	var behind: bool = false
	## A land plot: it grows on the lot's own land outside the first lease (`land`).
	var is_land: bool = false
	var land: Rect2 = Rect2()
	## True when the current lease covers its land: it can show only flat looks.
	var leased: bool = false

## Inputs, set by the owner before build().
var skin: CountrySkin
var local_reserve: AABB = AABB()
var shift: float = 0.0
var world_centre: Vector2 = Vector2.ZERO
var light_shift: Vector2 = Vector2.ZERO
var salt: int = 0
## The street frame's basis: names the plots by compass (east is world +x, north -z).
var compass: Basis = Basis.IDENTITY
## Local (u, z) rects nothing stands on: the door approaches and entrance pads.
var keep_clear: Array[Rect2] = []
## The lot's leases (#611), local (u, z): the first, unexpanded lease and the current one.
var first_lease: Rect2 = Rect2()
var lease: Rect2 = Rect2()
## The shop building's local (u, z) extent, walls included: the wheel turns on its side.
var building: Rect2 = Rect2()
## The shop's built cells, local (u, z) (#619): the axle housing runs to the wall they make.
var built: Array[Rect2] = []

var root: Node3D
var plots: Array[Plot] = []
var sheep: Array[Node3D] = []
var birds: Array[Node3D] = []
var tractor: Node3D
var wheel: Node3D
## Which side of the lot (in u) the mill stream runs down: -1 or +1. The meadow is on
## the other side.
var stream_side: float = -1.0
## Where things went (local), for tools and tests.
var wheel_at: Vector3 = Vector3.ZERO
var weir_z: float = 0.0
## The shop's wall face (local u) on the stream's side at the wheel's axle: the axle
## housing runs from the lot's edge to here, and is gone once the shop is built out to it.
var mill_wall: float = 0.0
var bridge_z: float = 0.0
var stand: Rect2 = Rect2()
var gate: Rect2 = Rect2()
var forecourt: Rect2 = Rect2()
var _sheep_spots: Array[Vector4] = []
var _bird_paths: Array[Vector4] = []
var _tractor_wheels: Array[Node3D] = []
var _stream_material: ShaderMaterial
var _wheat_material: ShaderMaterial
## The far crop fields: crop texture over their soft colour patches.
var _field_material: ShaderMaterial
var _glow_material: ShaderMaterial
var _glass_material: StandardMaterial3D
var _pool_material: StandardMaterial3D
var _headlamp_material: ShaderMaterial
var _material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _glow: MeshInstance3D
var _pools: MeshInstance3D
var _night: float = 0.0
## How far the wheat's ears lean (country_wheat.gdshader) and how fast the gusts come, by
## weather (sunny, cloudy, rain): a blustery rainy day bends the field.
const WHEAT_REACH: Array[float] = [0.035, 0.045, 0.08]
const WHEAT_PACE: Array[float] = [1.0, 1.15, 1.6]
var _weather: int = WeatherState.Kind.SUNNY
var _gloom: float = 0.0
var _late: float = 0.0
var _seconds: float = 0.0
var _applied_at: float = -1.0
var _blocked: Array[Rect2] = []
var _lights: Array[Vector3] = []
var _light_sizes: Array[float] = []
var _pool_spots: Array[Vector3] = []
var _wall_keys: Dictionary[String, bool] = {}
## The patchwork's fields (rect, seed, kind, colour, rows across, which edges each draws),
## the pasture opposite the mill where the sheep graze, the cottages' spots (u, z, yaw)
## and the lot's block the patchwork leaves alone.
var _fields: Array[Dictionary] = []
var _pasture: Rect2 = Rect2()
var _cottage_spots: Array[Vector3] = []
var _block_rect: Rect2 = Rect2()

## Built static meshes by street key (a rebuild after a purchase or a reload reuses them).
static var _cache: Dictionary[String, Dictionary] = {}
static var _land_cache: Dictionary[String, Dictionary] = {}


static func clear_cache() -> void:
	_land_cache.clear()
	_cache.clear()


func _r(a: int, b: int) -> float:
	return NeighbourhoodGround.hash01(a, b, salt + 613)


func _centre_u() -> float:
	return local_reserve.get_center().x


func _half_lot() -> float:
	return local_reserve.size.x * 0.5


func _lot() -> Rect2:
	return Rect2(local_reserve.position.x, local_reserve.position.z, local_reserve.size.x, shift - local_reserve.position.z)


func _outer() -> float:
	return NeighbourhoodGround.WORLD_HALF + NeighbourhoodGround.BEYOND


# --- the shape of the land ----------------------------------------------------

## The lane's centre line (local z) at `u`: straight past the lot, curving gently as it
## runs off between the fields.
func lane_z(u: float) -> float:
	var away: float = clampf((absf(u - _centre_u()) - (_half_lot() + 4.0)) / 18.0, 0.0, 1.0)
	return shift + LANE_V + away * away * (0.7 * sin(u * 0.071 + 1.3) + 0.25 * sin(u * 0.19 + 0.4))


## The lane's slope dz/du at `u` (for headings along it).
func lane_slope(u: float) -> float:
	return (lane_z(u + 0.05) - lane_z(u - 0.05)) / 0.1


func _near_hedge(u: float) -> float:
	return lane_z(u) - LANE_HALF - NEAR_VERGE


func _far_hedge(u: float) -> float:
	return lane_z(u) + LANE_HALF + FAR_VERGE


## The lot's edge (local u) on the stream's side, and on the meadow's.
func _stream_edge() -> float:
	return local_reserve.position.x if stream_side < 0.0 else local_reserve.end.x


func _meadow_edge() -> float:
	return local_reserve.end.x if stream_side < 0.0 else local_reserve.position.x


## The stream's centre line (local u) at `z`: close beside the mill, wandering more as
## it runs off across the fields either way.
func stream_u(z: float) -> float:
	var lot: Rect2 = _lot()
	var away: float = clampf((maxf(lot.position.y - 3.0 - z, z - (shift + LANE_V + 2.0))) / 14.0, 0.0, 1.0)
	var wander: float = away * away * (1.6 * sin(z * 0.11 + 0.7) + 0.5 * sin(z * 0.29 + 2.1))
	return _stream_edge() + stream_side * (STREAM_GAP + _pond(z) * 0.5) + wander


## 1 across the mill pond above the weir, 0 elsewhere: the pond spreads away from the lot.
func _pond(z: float) -> float:
	return smoothstep(weir_z - 0.1, weir_z - 0.6, z) * (1.0 - smoothstep(weir_z - 4.5, weir_z - 6.5, z))


## The stream's half width at `z`: the mill pond above the weir is wider.
func stream_half(z: float) -> float:
	return STREAM_HALF + 0.06 * sin(z * 0.9 + 0.3) + _pond(z) * 0.5


func _on_stream(point: Vector2, margin: float) -> bool:
	return absf(point.x - stream_u(point.y)) < stream_half(point.y) + margin


func _on_lane(point: Vector2, margin: float) -> bool:
	return absf(point.y - lane_z(point.x)) < LANE_HALF + margin


func _is_blocked(point: Vector2, margin: float) -> bool:
	for rect: Rect2 in _blocked:
		if rect.grow(margin).has_point(point):
			return true
	return false


func _in_plot(point: Vector2, margin: float) -> bool:
	for entry: Plot in plots:
		if entry.rect.grow(margin).has_point(point):
			return true
	return false


func _distance_to_lot(point: Vector2) -> float:
	var lot: Rect2 = _lot()
	var dx: float = maxf(maxf(lot.position.x - point.x, point.x - lot.end.x), 0.0)
	var dz: float = maxf(maxf(lot.position.y - point.y, point.y - lot.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


static func _compass_name(direction: Vector3) -> StringName:
	if absf(direction.x) >= absf(direction.z):
		return &"east" if direction.x > 0.0 else &"west"
	return &"south" if direction.z > 0.0 else &"north"


# --- the named land plots (#597) -------------------------------------------------

## The meadow beside the lot (on the side away from the stream, running down to the
## lane's hedge) and the cornfield behind it, named by compass.
func _plan_plots() -> void:
	plots.clear()
	var lot: Rect2 = _lot()
	var depth: float = skin.plot_depth
	var front: float = _near_hedge(_meadow_edge()) - 0.3
	var side: Rect2
	if stream_side < 0.0:
		side = Rect2(lot.end.x + PLOT_GAP, lot.position.y - PLOT_GAP, depth, front - lot.position.y + PLOT_GAP)
	else:
		side = Rect2(lot.position.x - PLOT_GAP - depth, lot.position.y - PLOT_GAP, depth, front - lot.position.y + PLOT_GAP)
	# The cornfield runs from the stream's bank across the back to the meadow's far side.
	var bank: float = _stream_edge() + stream_side * 0.1
	var far: float = side.end.x if stream_side < 0.0 else side.position.x
	var back: Rect2 = Rect2(minf(bank, far), lot.position.y - PLOT_GAP - depth, absf(far - bank), depth)
	var entries: Array = [[side, Vector3.RIGHT * -stream_side, &"meadow", false], [back, Vector3.FORWARD, &"corn", true]]
	for item: Array in entries:
		var entry: Plot = Plot.new()
		entry.rect = item[0]
		entry.id = _compass_name(compass * (item[1] as Vector3))
		entry.crop = item[2]
		entry.behind = item[3]
		plots.append(entry)


## The lot's land outside the first lease (#611), as land plots: a strip down each side
## the lease does not reach (meadow) and one across its back (corn), named by compass
## with `_land` (`east_land`). Each fills its land up to the lease's edge.
func _plan_land() -> void:
	if not first_lease.has_area():
		return
	var lot: Rect2 = _lot()
	var start: Rect2 = first_lease.intersection(lot)
	if not start.has_area():
		return
	var lands: Array[Rect2] = []
	var outward: Array[Vector3] = []
	if start.position.x > lot.position.x + 0.01:
		lands.append(Rect2(lot.position.x, lot.position.y, start.position.x - lot.position.x, start.end.y - lot.position.y))
		outward.append(Vector3.LEFT)
	if start.end.x < lot.end.x - 0.01:
		lands.append(Rect2(start.end.x, lot.position.y, lot.end.x - start.end.x, start.end.y - lot.position.y))
		outward.append(Vector3.RIGHT)
	if start.position.y > lot.position.y + 0.01:
		lands.append(Rect2(start.position.x, lot.position.y, start.size.x, start.position.y - lot.position.y))
		outward.append(Vector3.FORWARD)
	for index: int in lands.size():
		var entry: Plot = Plot.new()
		entry.id = StringName(String(_compass_name(compass * outward[index])) + "_land")
		entry.is_land = true
		entry.land = lands[index]
		entry.behind = outward[index] == Vector3.FORWARD
		entry.crop = &"corn" if entry.behind else &"meadow"
		# The crop stands a little in from the lease's edge, on the land itself.
		entry.rect = lands[index]
		entry.leased = lease.has_area() and lease.grow(0.01).encloses(lands[index])
		plots.append(entry)


## The ids of the plots, in build order (the side meadow, the back cornfield, then the
## land plots).
func plot_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Plot in plots:
		ids.append(entry.id)
	return ids


func plot(id: StringName) -> Plot:
	for entry: Plot in plots:
		if entry.id == id:
			return entry
	return null


## Shows a plot grown, mown or cleared. Leased land never shows its standing crop.
func show_plot(id: StringName, state: int) -> void:
	var entry: Plot = plot(id)
	if entry == null or entry.node == null:
		return
	if entry.is_land and entry.leased and state == PlotState.GROWN:
		state = PlotState.MOWN
	(entry.node.get_node(^"Grown") as Node3D).visible = state == PlotState.GROWN
	(entry.node.get_node(^"Mown") as Node3D).visible = state == PlotState.MOWN
	(entry.node.get_node(^"Cleared") as Node3D).visible = state == PlotState.CLEARED


# --- building ---------------------------------------------------------------

## Builds every node under `parent` (the dressing's country root, on the street frame).
func build(parent: Node3D) -> void:
	root = parent
	_choose_stream_side()
	_materials()
	_plan_mill()
	_plan_plots()
	_plan_yard()
	_block_rect = _block()
	_plan_fields()
	var key: String = var_to_str([local_reserve, shift, world_centre, light_shift, salt, compass, keep_clear, building,
		stream_side, mill_wall, skin.signature()])
	var meshes: Dictionary = _cache.get(key, {})
	if meshes.is_empty():
		meshes = _build_static()
		if _cache.size() > 4:
			_cache.clear()
		_cache[key] = meshes
	_plan_land()
	var land_key: String = var_to_str([key, first_lease])
	var land_meshes: Dictionary = _land_cache.get(land_key, {})
	if land_meshes.is_empty():
		for entry: Plot in plots:
			if entry.is_land:
				_build_plot(entry, land_meshes)
		if _land_cache.size() > 8:
			_land_cache.clear()
		_land_cache[land_key] = land_meshes
	meshes = meshes.merged(land_meshes)
	_add(_instance("Ground", meshes["ground"], _material))
	_add(_instance("Fields", meshes["fields"], _field_material))
	_add(_instance("Bounds", meshes["bounds"], _material))
	_add(_instance("Props", meshes["props"], _material))
	_add(_instance("AxleHousing", meshes["housing"], _material))
	_add(_instance("Shadows", meshes["shadows"], _shadow_material))
	_add(_instance("Stream", meshes["stream"], _stream_material))
	_add(_instance("Windows", meshes["windows"], _glass_material))
	var holder: Node3D = Node3D.new()
	holder.name = "Plots"
	root.add_child(holder)
	for entry: Plot in plots:
		entry.node = Node3D.new()
		entry.node.name = String(entry.id)
		holder.add_child(entry.node)
		for look: String in ["Grown", "Mown", "Cleared"]:
			var group: Node3D = Node3D.new()
			group.name = look
			entry.node.add_child(group)
			var standing: bool = entry.crop == &"corn" and look == "Grown"
			group.add_child(_instance("Body", meshes["%s:%s" % [entry.id, look]], _wheat_material if standing else _material))
			group.add_child(_instance("Shade", meshes["%s:%s:shade" % [entry.id, look]], _shadow_material))
		show_plot(entry.id, PlotState.GROWN)
	_glow = _instance("Glow", meshes["glow"], _glow_material)
	_glow.extra_cull_margin = 1.0
	_add(_glow)
	_pools = _instance("LightPools", meshes["pools"], _pool_material)
	_add(_pools)
	_build_wheel()
	_build_tractor()
	_build_sheep()
	_build_birds()
	_apply_night()


func _choose_stream_side() -> void:
	# The stream runs down the side with less of the lot's land outside its first lease
	# (the meadow grows on the other); a lot without one keeps it on the left.
	stream_side = -1.0
	if first_lease.has_area():
		var lot: Rect2 = _lot()
		var left: float = first_lease.position.x - lot.position.x
		var right: float = lot.end.x - first_lease.end.x
		if right < left - 0.01:
			stream_side = 1.0


func _materials() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.metallic_specular = 0.0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_material.disable_receive_shadows = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_material = StandardMaterial3D.new()
	_shadow_material.vertex_color_use_as_albedo = true
	_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_material.disable_receive_shadows = true
	_stream_material = ShaderMaterial.new()
	_stream_material.shader = STREAM_SHADER
	_stream_material.set_shader_parameter(&"deep", skin.water_deep)
	_stream_material.set_shader_parameter(&"shallow", skin.water_shallow)
	_stream_material.set_shader_parameter(&"ripple", skin.ripple)
	_wheat_material = ShaderMaterial.new()
	_wheat_material.shader = WHEAT_SHADER
	_wheat_material.set_shader_parameter(&"base_y", PLOT_Y)
	_field_material = ShaderMaterial.new()
	_field_material.shader = FIELD_SHADER
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = GLOW_SHADER
	_glow_material.set_shader_parameter(&"tint", skin.lamp_glow)
	_headlamp_material = ShaderMaterial.new()
	_headlamp_material.shader = GLOW_SHADER
	_headlamp_material.set_shader_parameter(&"tint", skin.lamp_glow.lightened(0.2))
	_glass_material = StandardMaterial3D.new()
	_glass_material.vertex_color_use_as_albedo = true
	_glass_material.emission_enabled = true
	_glass_material.emission = skin.window_glow
	_glass_material.emission_energy_multiplier = 0.0
	_glass_material.disable_receive_shadows = true
	_pool_material = StandardMaterial3D.new()
	_pool_material.vertex_color_use_as_albedo = true
	_pool_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pool_material.disable_receive_shadows = true


func _instance(label: String, mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _add(node: Node3D) -> void:
	root.add_child(node)


## A soup's mesh, or an empty mesh when nothing was drawn.
static func _mesh_of(soup: NeighbourhoodGround.Soup) -> ArrayMesh:
	return soup.to_mesh() if soup.positions.size() > 0 else ArrayMesh.new()


## Where the wheel turns, and the weir and bridge on the stream.
func _plan_mill() -> void:
	var lot: Rect2 = _lot()
	var front: Rect2 = building if building.has_area() else lot
	# The wheel turns on the building's side, a little forward of its middle.
	var wheel_z: float = clampf(front.end.y - front.size.y * 0.4, front.position.y + WHEEL_RADIUS + 0.3, front.end.y - WHEEL_RADIUS - 0.2)
	wheel_at = Vector3(_stream_edge() + stream_side * (0.17 + WHEEL_WIDTH * 0.5), 0.44, wheel_z)
	mill_wall = _wall_at(wheel_z)
	weir_z = lot.position.y - 2.2
	bridge_z = lane_z(stream_u(lane_z(_stream_edge())))


## The shop's wall face (local u) on the stream's side across the line at `z`: the outer
## edge of the built cells the axle housing would meet there, else the building's side,
## else the lot's edge. Never outside the lot.
func _wall_at(z: float) -> float:
	var edge: float = _stream_edge()
	var face: float = NAN
	for cell: Rect2 in built:
		if cell.end.y <= z - CASING_HALF or cell.position.y >= z + CASING_HALF:
			continue
		var outer: float = cell.position.x if stream_side < 0.0 else cell.end.x
		if is_nan(face) or (outer - face) * stream_side > 0.0:
			face = outer
	if is_nan(face):
		face = (building.position.x if stream_side < 0.0 else building.end.x) if building.has_area() else edge
	# Inside the lot: never past its edge on the stream's side.
	return maxf(face, edge) if stream_side < 0.0 else minf(face, edge)


## Where the forecourt, its wall, the farm gate and the produce stand go, clear of the door.
func _plan_yard() -> void:
	_blocked.clear()
	_lights.clear()
	_light_sizes.clear()
	_pool_spots.clear()
	var lot: Rect2 = _lot()
	forecourt = Rect2(lot.position.x - 0.05, shift - 0.02, lot.size.x + 0.1, _near_hedge(_centre_u()) - shift + 0.02)
	for rect: Rect2 in keep_clear:
		_blocked.append(rect.grow(0.1))
	_blocked.append(Rect2(_door_u() - 0.55, shift, 1.1, lane_z(_door_u()) - shift))
	# The farm gate into the meadow and the produce stand beside it on the verge.
	var meadow_u: float = _meadow_edge() - stream_side * 1.15
	var hedge: float = _near_hedge(meadow_u)
	gate = Rect2(meadow_u - 0.6, hedge - 0.1, 1.2, 0.2)
	var stand_u: float = meadow_u - stream_side * 1.35
	stand = Rect2(stand_u - 0.48, hedge + 0.2, 0.96, 0.46)
	_blocked.append(stand.grow(0.25))
	_blocked.append(gate.grow_individual(0.0, 0.4, 0.0, 0.4))


func _door_u() -> float:
	for rect: Rect2 in keep_clear:
		if rect.end.y > shift - 0.05:
			return rect.get_center().x
	return _centre_u()


func _build_static() -> Dictionary:
	var meshes: Dictionary = {}
	var ground: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var fields: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var bounds: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var props: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var windows: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var shadows: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var housing: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	_wall_keys.clear()
	_ground(ground)
	_lane(ground, props)
	_stream_banks(ground, props, shadows)
	_patchwork(fields, bounds, shadows)
	_lane_hedges(bounds, shadows)
	_forecourt(ground, props, shadows)
	_farm_gate(props, shadows)
	_produce_stand(props, shadows)
	_bridge(props, shadows)
	_weir(props, shadows)
	_wheel_pit(props, shadows)
	_wheel_house(props, housing, shadows)
	_trees(props, shadows)
	_cottages(props, windows, shadows)
	meshes["ground"] = _mesh_of(ground.soup)
	meshes["fields"] = _mesh_of(fields.soup)
	meshes["bounds"] = _mesh_of(bounds.soup)
	meshes["props"] = _mesh_of(props.soup)
	meshes["windows"] = _mesh_of(windows.soup)
	meshes["housing"] = _mesh_of(housing.soup)
	meshes["shadows"] = _mesh_of(shadows)
	meshes["stream"] = _stream_mesh()
	for entry: Plot in plots:
		_build_plot(entry, meshes)
	meshes["glow"] = _sprites(_lights, _light_sizes)
	meshes["pools"] = _pool_mesh()
	return meshes


# --- ground, lane and stream ---------------------------------------------------

func _ground(pen: NeighbourhoodBuildings.Pen) -> void:
	var outer: float = _outer()
	var c: Vector2 = world_centre
	pen.flat(c.x - outer, c.y - outer, c.x + outer, c.y + outer, FLOOR_Y, skin.grass)
	# Lighter and darker patches in the grass, gentler over the lot where the player builds.
	var span: float = 34.0
	for index: int in 450:
		var at: Vector2 = Vector2(_centre_u() + (_r(index, 1) * 2.0 - 1.0) * span, shift + (_r(index, 2) * 2.0 - 1.0) * span)
		var size: float = 0.3 + _r(index, 3) * 0.7
		if _on_lane(at, size) or _on_stream(at, size):
			continue
		var colour: Color = skin.grass_light if _r(index, 4) < 0.5 else skin.grass_dark
		if _lot().grow(0.6).has_point(at):
			colour = skin.grass.lerp(colour, 0.45)
		_blob(pen, at, size, size * (0.55 + _r(index, 5) * 0.4), _r(index, 6) * PI, 8, PATCH_Y + _r(index, 7) * 0.002, skin.grass.lerp(colour, 0.65))


func _blob(pen: NeighbourhoodBuildings.Pen, at: Vector2, rx: float, rz: float, spin: float, sides: int, y: float, colour: Color) -> void:
	var points: Array[Vector3] = []
	for index: int in sides:
		var angle: float = spin + TAU * float(index) / float(sides)
		var wobble: float = 0.85 + 0.3 * _r(int(at.x * 37.0) + index, int(at.y * 41.0))
		points.append(Vector3(at.x + cos(angle) * rx * wobble, y, at.y + sin(angle) * rz * wobble))
	for index: int in sides:
		pen.tri(Vector3(at.x, y, at.y), points[index], points[(index + 1) % sides], Vector3.UP, colour)


## A strip following the lane's centre line from `offset - half` to `offset + half`.
func _ribbon(pen: NeighbourhoodBuildings.Pen, offset: float, half: float, y: float, colour: Color, rough: float) -> void:
	var outer: float = _outer()
	var u: float = world_centre.x - outer
	while u < world_centre.x + outer:
		var u1: float = u + 0.5
		var w0: float = half + rough * (0.6 * sin(u * 1.7) + 0.4 * sin(u * 4.3))
		var w1: float = half + rough * (0.6 * sin(u1 * 1.7) + 0.4 * sin(u1 * 4.3))
		var z0: float = lane_z(u) + offset
		var z1: float = lane_z(u1) + offset
		pen.quad(Vector3(u, y, z0 - w0), Vector3(u1, y, z1 - w1), Vector3(u1, y, z1 + w1), Vector3(u, y, z0 + w0), Vector3.UP, colour)
		u = u1


## The lane: worn tarmac on a darker crumbling edge, a strip of grass down its middle,
## patched and paler where the wheels run.
func _lane(ground: NeighbourhoodBuildings.Pen, props: NeighbourhoodBuildings.Pen) -> void:
	_ribbon(ground, 0.0, LANE_HALF + 0.12, EDGE_Y, skin.lane_edge, 0.05)
	_ribbon(ground, 0.0, LANE_HALF, LANE_Y, skin.lane, 0.04)
	_ribbon(ground, 0.0, 0.1, MARK_Y, skin.grass_dark.lerp(skin.lane, 0.25), 0.03)
	for index: int in 170:
		var u: float = world_centre.x + (_r(index, 11) * 2.0 - 1.0) * (NeighbourhoodGround.WORLD_HALF + 4.0)
		var across: float = (0.32 + _r(index, 12) * 0.3) * (-1.0 if _r(index, 13) < 0.5 else 1.0)
		var size: float = 0.2 + _r(index, 14) * 0.35
		var tone: Color = skin.lane.lightened(0.06) if _r(index, 15) < 0.6 else skin.lane.darkened(0.07)
		_blob(ground, Vector2(u, lane_z(u) + across), size * 1.7, size * 0.45, _r(index, 16) * 0.3, 7, MARK_Y - 0.0015, tone)
	# Grass tufts creeping in at the edges.
	for index: int in 120:
		var u: float = _centre_u() + (_r(index, 21) * 2.0 - 1.0) * 34.0
		var side: float = -1.0 if _r(index, 22) < 0.5 else 1.0
		var at: Vector2 = Vector2(u, lane_z(u) + side * (LANE_HALF + 0.06 + _r(index, 23) * 0.12))
		if _is_blocked(at, 0.1) or _on_stream(at, 0.4):
			continue
		_tuft(props, Vector3(at.x, EDGE_Y, at.y), 0.12 + _r(index, 24) * 0.08, skin.grass_dark, index * 5 + 3)


## The stream's muddy banks, the reeds and stones at its edge, a little foam where the
## wheel churns it and below the weir.
func _stream_banks(ground: NeighbourhoodBuildings.Pen, props: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var outer: float = _outer()
	var z: float = world_centre.y - outer
	while z < world_centre.y + outer:
		var z1: float = z + 0.5
		var w0: float = stream_half(z) + 0.22 + 0.05 * sin(z * 2.3)
		var w1: float = stream_half(z1) + 0.22 + 0.05 * sin(z1 * 2.3)
		ground.quad(Vector3(stream_u(z) - w0, BANK_Y, z), Vector3(stream_u(z1) - w1, BANK_Y, z1),
			Vector3(stream_u(z1) + w1, BANK_Y, z1), Vector3(stream_u(z) + w0, BANK_Y, z), Vector3.UP, skin.bank)
		z = z1
	for index: int in 150:
		var sz: float = shift + (_r(index, 31) * 2.0 - 1.0) * 34.0
		if absf(sz - bridge_z) < LANE_HALF + 0.6 or absf(sz - wheel_at.z) < WHEEL_RADIUS + 0.5 or absf(sz - weir_z) < 0.5:
			continue
		var side: float = -1.0 if _r(index, 32) < 0.5 else 1.0
		var at: Vector2 = Vector2(stream_u(sz) + side * (stream_half(sz) + (_r(index, 33) - 0.3) * 0.4), sz)
		if _is_blocked(at, 0.2) or _lot().grow(0.1).has_point(at):
			continue
		if _r(index, 34) < 0.45:
			var size: float = 0.05 + _r(index, 35) * 0.09
			props.lump(Vector3(at.x, WATER_Y + size * 0.25, at.y), size * 1.2, size * 0.7, size, _r(index, 36) * TAU,
				skin.stone if _r(index, 37) < 0.6 else skin.stone_light, skin.stone_dark)
		else:
			_tuft(props, Vector3(at.x, BANK_Y, at.y), 0.3 + _r(index, 38) * 0.22, skin.grass_dark.lerp(skin.willow, 0.4), index * 3 + 1)
	# White water: churned below the wheel, and a fringe under the weir's lip.
	for index: int in 9:
		var t: float = float(index) / 8.0
		var at: Vector2 = Vector2(lerpf(wheel_at.x - stream_side * 0.05, stream_u(wheel_at.z), 0.35 + 0.3 * _r(index, 41)),
			wheel_at.z + 0.1 + t * 1.3)
		var size: float = 0.16 - t * 0.09
		_blob(ground, at, size * 1.3, size, _r(index, 42) * PI, 6, FOAM_Y, skin.ripple.lerp(skin.water_shallow, t * 0.6))
	var weir_u: float = stream_u(weir_z)
	var half: float = stream_half(weir_z + 0.2)
	for index: int in 10:
		var across: float = lerpf(-half * 0.85, half * 0.85, float(index) / 9.0)
		var size: float = 0.12 + 0.05 * _r(index, 43)
		_blob(ground, Vector2(weir_u + across, weir_z + 0.2 + 0.1 * _r(index, 44)), size, size * 0.8, _r(index, 45), 6, FOAM_Y, skin.ripple)
	_blob(ground, Vector2(weir_u, weir_z + 0.62), half * 0.55, 0.16, 0.0, 7, FOAM_Y - 0.001, skin.ripple.lerp(skin.water_shallow, 0.5))
	# The bridge throws the water under it into shade.
	var bridge_u: float = stream_u(bridge_z)
	_shade_rect(shadows, Rect2(bridge_u - 0.75, bridge_z + LANE_HALF + 0.05, 1.5, 0.35), 0.0, 0.35)


## The water: one strip down the stream with UVs along and across, for the stream
## shader; it stops at the bridge, where the lane runs over it.
func _stream_mesh() -> ArrayMesh:
	var outer: float = _outer()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var z: float = world_centre.y - outer
	var along: float = 0.0
	var span: Vector2 = Vector2(bridge_z - LANE_HALF - 0.12, bridge_z + LANE_HALF + 0.12)
	while z < world_centre.y + outer:
		var z1: float = z + 0.5
		if z1 > span.x and z < span.x:
			z1 = span.x
		elif z >= span.x and z < span.y:
			z = span.y
			z1 = z + 0.5
		var a: float = stream_u(z)
		var b: float = stream_u(z1)
		var length: float = Vector2(b - a, z1 - z).length()
		var corners: Array[Vector3] = [Vector3(a - stream_half(z), z, -1.0), Vector3(a + stream_half(z), z, 1.0),
			Vector3(b + stream_half(z1), z1, 1.0), Vector3(b - stream_half(z1), z1, -1.0)]
		var alongs: Array[float] = [along, along, along + length, along + length]
		for corner: int in [0, 1, 2, 0, 2, 3]:
			vertices.append(Vector3(corners[corner].x, WATER_Y, corners[corner].y))
			normals.append(Vector3.UP)
			uvs.append(Vector2(alongs[corner], corners[corner].z))
		along += length
		z = z1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- the patchwork of fields ---------------------------------------------------

## Lays out the fields round the lot's block: rows across the lane, rows behind the
## cornfield, and a row each side of the block. Cheap and run every build (the sheep
## graze in the pasture it names, the cottages stand in fields it picks).
func _plan_fields() -> void:
	_fields.clear()
	_cottage_spots.clear()
	var outer: float = _outer()
	var left: float = world_centre.x - outer
	var right: float = world_centre.x + outer
	var block: Rect2 = _block()
	# Across the lane: rows outward to the world's edge.
	var far_start: float = shift + LANE_V + LANE_HALF + FAR_VERGE + 1.3
	var z: float = far_start
	var row: int = 0
	while z < world_centre.y + outer:
		var depth: float = FIELD_D * (0.8 + 0.5 * _r(row, 301))
		_plan_row(left, right, z, minf(z + depth, world_centre.y + outer), row + 10, row == 0, [2, 3])
		z += depth
		row += 1
	# Behind the cornfield: rows back to the world's edge.
	z = block.position.y
	row = 0
	while z > world_centre.y - outer:
		var depth: float = FIELD_D * (0.8 + 0.5 * _r(row, 302))
		_plan_row(left, right, maxf(z - depth, world_centre.y - outer), z, row + 40, false, [0, 3])
		z -= depth
		row += 1
	# Beside the block, between the cornfield's back and the lane's hedges.
	var band_end: float = shift + 1.2
	var u: float = block.end.x
	var index: int = 0
	while u < right:
		var width: float = FIELD_W * (0.75 + 0.5 * _r(index, 303))
		_fields.append(_field_entry(Rect2(u, block.position.y, minf(width, right - u), band_end - block.position.y), 70 + index, [1]))
		u += width
		index += 1
	u = block.position.x
	index = 0
	while u > left:
		var width: float = FIELD_W * (0.75 + 0.5 * _r(index, 304))
		_fields.append(_field_entry(Rect2(maxf(u - width, left), block.position.y, minf(width, u - left), band_end - block.position.y), 90 + index, [3]))
		u -= width
		index += 1
	_vary_crops()
	# Far cottages, in pasture or by a field's corner, well out from the lot.
	var spots: Array[Vector2] = []
	for entry: Dictionary in _fields:
		var rect: Rect2 = entry["rect"]
		var seed_value: int = entry["seed"]
		var corner: Vector2 = Vector2(rect.position.x + rect.size.x * (0.25 + 0.5 * _r(seed_value, 305)),
			rect.position.y + rect.size.y * (0.3 + 0.4 * _r(seed_value, 306)))
		var distance: float = corner.distance_to(Vector2(_centre_u(), shift))
		if distance < 13.0 or distance > 30.0 or rect.size.x < 6.0 or rect.size.y < 5.0 or _on_stream(corner, 3.0):
			continue
		var too_close: bool = false
		for other: Vector2 in spots:
			if other.distance_to(corner) < 9.0:
				too_close = true
		if too_close or _r(seed_value, 307) > 0.55:
			continue
		spots.append(corner)
		entry["kind"] = 0
		_cottage_spots.append(Vector3(corner.x, corner.y, (PI * 0.5 * float(int(_r(seed_value, 308) * 4.0))) + 0.15 * (_r(seed_value, 309) - 0.5)))
		if _cottage_spots.size() >= skin.cottages:
			break


## The far crops' colours by distance from the lot (CROP_ORDER).
func _vary_crops() -> void:
	var crops: Array[Dictionary] = []
	for entry: Dictionary in _fields:
		if int(entry["kind"]) != 0:
			crops.append(entry)
	var home: Vector2 = Vector2(_centre_u(), shift)
	crops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = (a["rect"] as Rect2).get_center().distance_squared_to(home)
		var db: float = (b["rect"] as Rect2).get_center().distance_squared_to(home)
		return da < db if not is_equal_approx(da, db) else int(a["seed"]) < int(b["seed"]))
	var order: Array[int] = []
	for index: int in CROP_ORDER:
		if index < skin.field_colors.size():
			order.append(index)
	if order.is_empty():
		return
	for index: int in crops.size():
		crops[index]["colour"] = skin.field_colors[order[index % order.size()]]


## The lot's block: the lot, its plots and the stream beside it, which the patchwork
## leaves alone.
func _block() -> Rect2:
	var area: Rect2 = _lot().grow(PLOT_GAP)
	for entry: Plot in plots:
		if not entry.is_land:
			area = area.merge(entry.rect)
	var bank: float = _stream_edge() + stream_side * (STREAM_GAP + STREAM_HALF + 1.6)
	area = area.merge(Rect2(bank, area.position.y, 0.0, area.size.y))
	return area.grow_individual(0.0, 0.35, 0.0, 0.0)


## One row of fields between `z0` and `z1`, split into columns of varied width. The
## first row across the lane keeps a pasture opposite the mill for the sheep.
func _plan_row(left: float, right: float, z0: float, z1: float, row: int, sheep_row: bool, edges: Array[int]) -> void:
	var u: float = _centre_u() - FIELD_W * (0.3 + 0.6 * _r(row, 311))
	while u > left:
		u -= FIELD_W * (0.75 + 0.5 * _r(int(u), row))
	var column: int = 0
	while u < right:
		var width: float = FIELD_W * (0.75 + 0.5 * _r(column, row + 500))
		var rect: Rect2 = Rect2(maxf(u, left), z0, minf(u + width, right) - maxf(u, left), z1 - z0)
		var entry: Dictionary = _field_entry(rect, row * 37 + column, edges)
		if sheep_row and rect.position.x <= _centre_u() and rect.end.x > _centre_u():
			entry["kind"] = 0
			_pasture = rect
		_fields.append(entry)
		u += width
		column += 1


## A field: 0 pasture (two in five), else a crop in one of the skin's field colours,
## its rows running across or along.
func _field_entry(rect: Rect2, seed_value: int, edges: Array[int]) -> Dictionary:
	var kind: int = 0 if _r(seed_value, 321) < 0.4 else 1
	return {"rect": rect, "seed": seed_value, "kind": kind, "edges": edges,
		"colour": skin.field_colors[int(_r(seed_value, 322) * 97.0) % skin.field_colors.size()],
		"across": _r(seed_value, 323) < 0.5}


## Draws the fields and their boundaries: hedges and dry-stone walls, plain far out.
func _patchwork(fields: NeighbourhoodBuildings.Pen, bounds: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	for entry: Dictionary in _fields:
		var rect: Rect2 = entry["rect"]
		var seed_value: int = entry["seed"]
		var inner: Rect2 = rect.grow(-0.45)
		if not inner.has_area():
			continue
		if int(entry["kind"]) == 0:
			# Pasture: the grass, a few darker tussocky patches.
			for index: int in int(inner.get_area() / 4.0) + 2:
				var at: Vector2 = inner.position + Vector2(_r(seed_value + index, 331), _r(seed_value + index, 332)) * inner.size
				var size: float = 0.2 + _r(seed_value + index, 333) * 0.35
				_blob(fields, at, size, size * 0.75, _r(seed_value + index, 334) * PI, 8, FIELD_Y,
					skin.grass.lerp(skin.grass_dark, 0.6) if index % 3 != 0 else skin.grass.lerp(skin.grass_light, 0.6))
			continue
		_soft_field(fields.soup, inner, entry["colour"], seed_value, entry["across"])
	# Boundaries: each field draws its far edge and one side, so a shared line is drawn
	# once; the block's back and its sides are drawn here.
	for entry: Dictionary in _fields:
		var rect: Rect2 = entry["rect"]
		var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for edge: int in entry["edges"]:
			_boundary(bounds, shadows, corners[edge], corners[(edge + 1) % 4])
	var block: Rect2 = _block_rect
	var outer: float = _outer()
	var u: float = world_centre.x - outer
	while u < world_centre.x + outer:
		var u1: float = minf(u + FIELD_W * 0.5, world_centre.x + outer)
		_boundary(bounds, shadows, Vector2(u, block.position.y), Vector2(u1, block.position.y))
		u = u1
	for x: float in [block.position.x, block.end.x]:
		_boundary(bounds, shadows, Vector2(x, block.position.y), Vector2(x, _near_hedge(x) - 0.05))


## A far crop field: one soft sheet in its colour, drifting between a deeper and a paler
## tone in broad patches (as the near wheat does), a touch darker at the headland:
## per-vertex colour on a coarse grid, so nothing reads as a hard stripe. The field
## shader adds the crop's fine texture (flecks and faint drill rows) by its style.
func _soft_field(soup: NeighbourhoodGround.Soup, inner: Rect2, colour: Color, seed_value: int, across: bool) -> void:
	var columns: int = maxi(1, ceili(inner.size.x / FIELD_CELL))
	var rows: int = maxi(1, ceili(inner.size.y / FIELD_CELL))
	var step: Vector2 = Vector2(inner.size.x / float(columns), inner.size.y / float(rows))
	var phase: Vector2 = Vector2(_r(seed_value, 324), _r(seed_value, 325)) * TAU
	# The field shader's code (country_field.gdshader): the crop's style by its colour
	# (green young crop, brown ploughed earth, else grain) and its rows' direction.
	var style: int = 2 if colour.g > colour.r else (1 if colour.r < 0.7 else 0)
	var code: float = (float(style * 2 + (0 if across else 1)) + 0.5) / 8.0
	var deep: Color = colour.darkened(0.09)
	var pale: Color = colour.lerp(colour.lightened(0.2), 0.4)
	var tones: Array[Color] = []
	for iz: int in rows + 1:
		for ix: int in columns + 1:
			var at: Vector2 = inner.position + Vector2(float(ix) * step.x, float(iz) * step.y)
			var broad: float = 0.5 + 0.32 * sin(at.x * 0.33 + phase.x) * sin(at.y * 0.41 + phase.y) \
				+ 0.18 * sin((at.x + at.y) * 0.19 + phase.x - phase.y)
			var tone: Color = deep.lerp(pale, clampf(broad, 0.0, 1.0))
			# A soft mottle, vertex by vertex, so the sheet has a grain like the near wheat's.
			var mottle: float = _r(seed_value * 53 + ix * 31, iz * 977 + 326) - 0.5
			tone = tone.lightened(0.07 * mottle) if mottle > 0.0 else tone.darkened(-0.06 * mottle)
			# The headland, where the tractor turns, a shade darker.
			var edge: float = minf(minf(at.x - inner.position.x, inner.end.x - at.x), minf(at.y - inner.position.y, inner.end.y - at.y))
			tones.append(tone.darkened(0.05 * (1.0 - clampf(edge / 1.2, 0.0, 1.0))))
	for iz: int in rows:
		for ix: int in columns:
			var i00: int = iz * (columns + 1) + ix
			var corners: Array[int] = [i00, i00 + 1, i00 + columns + 2, i00 + columns + 1]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for index: int in tri:
					var corner: int = corners[index]
					soup.positions.append(Vector3(inner.position.x + float(corner % (columns + 1)) * step.x, FIELD_Y,
						inner.position.y + float(corner / (columns + 1)) * step.y))
					soup.normals.append(Vector3.UP)
					soup.colors.append(Color(tones[corner], code))


## A field boundary from `a` to `b`, cut where it meets another already drawn, the
## stream, the lane, the lot's block or the world's edge. A hedge or a dry-stone wall
## by hash; plain far out.
func _boundary(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, a: Vector2, b: Vector2) -> void:
	var length: float = a.distance_to(b)
	if length < 0.5:
		return
	var key: String = "%d,%d,%d,%d" % [roundi(minf(a.x, b.x) * 10.0), roundi(minf(a.y, b.y) * 10.0), roundi(maxf(a.x, b.x) * 10.0), roundi(maxf(a.y, b.y) * 10.0)]
	if _wall_keys.has(key):
		return
	_wall_keys[key] = true
	var hedge: bool = _r(roundi(a.x * 3.0 + b.y), roundi(a.y * 3.0 + b.x)) < 0.5
	var block: Rect2 = _block_rect.grow(-0.05)
	var step: float = 0.44
	var count: int = maxi(1, int(length / step))
	for index: int in count:
		var p0: Vector2 = a.lerp(b, float(index) / float(count))
		var p1: Vector2 = a.lerp(b, float(index + 1) / float(count))
		var mid: Vector2 = (p0 + p1) * 0.5
		if _on_stream(mid, 0.25) or _on_lane(mid, 0.3) or block.has_point(mid) or _is_blocked(mid, 0.2):
			continue
		var plain: bool = _distance_to_lot(mid) > DETAIL_REACH
		if plain and index % 5 != 0:
			continue
		if plain:
			var far: Vector2 = a.lerp(b, minf(float(index + 5) / float(count), 1.0))
			_plain_bound(pen, p0, far, hedge)
		elif hedge:
			_hedge_piece(pen, shadows, p0, p1, int(mid.x * 13.0) * 7 + int(mid.y * 11.0))
		else:
			_wall_piece(pen, shadows, p0, p1, int(mid.x * 13.0) * 7 + int(mid.y * 11.0))


## A far boundary: one low box, hedge green or wall grey.
func _plain_bound(pen: NeighbourhoodBuildings.Pen, a: Vector2, b: Vector2, hedge: bool) -> void:
	var along: Vector2 = (b - a).normalized()
	var side: Vector2 = Vector2(-along.y, along.x) * (0.22 if hedge else 0.13)
	var height: float = 0.5 if hedge else 0.32
	var colour: Color = skin.hedge_colors[0] if hedge else skin.stone
	var corners: Array[Vector2] = [a - side, b - side, b + side, a + side]
	var y0: float = FIELD_Y
	pen.quad(Vector3(corners[0].x, height, corners[0].y), Vector3(corners[1].x, height, corners[1].y),
		Vector3(corners[2].x, height, corners[2].y), Vector3(corners[3].x, height, corners[3].y), Vector3.UP, colour.lightened(0.05))
	for index: int in 4:
		var p: Vector2 = corners[index]
		var q: Vector2 = corners[(index + 1) % 4]
		var out: Vector2 = (p + q) * 0.5 - (a + b) * 0.5
		pen.quad(Vector3(p.x, y0, p.y), Vector3(q.x, y0, q.y), Vector3(q.x, height, q.y), Vector3(p.x, height, p.y),
			Vector3(out.x, 0.0, out.y), colour.darkened(0.08))


## One length of dry-stone wall: battered sides laid in two courses of stones, each its
## own tone, under a row of coping stones set on edge.
func _wall_piece(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, a: Vector2, b: Vector2, seed_value: int) -> void:
	var along: Vector2 = (b - a).normalized()
	var normal: Vector2 = Vector2(-along.y, along.x)
	var base: float = 0.14
	var top: float = 0.1
	var height: float = 0.3
	var mid: float = 0.15
	for side: float in [-1.0, 1.0]:
		var split: float = 0.3 + 0.4 * _r(seed_value, 341 + int(side))
		for course: int in 2:
			var y0: float = FIELD_Y if course == 0 else mid
			var y1: float = mid if course == 0 else height
			var w0: float = lerpf(base, top, maxf(y0, 0.0) / height)
			var w1: float = lerpf(base, top, y1 / height)
			var cut: float = split if course == 0 else 1.0
			for part: int in (2 if course == 0 else 1):
				var t0: float = 0.0 if part == 0 else cut
				var t1: float = cut if part == 0 else 1.0
				var p0: Vector2 = a.lerp(b, t0)
				var p1: Vector2 = a.lerp(b, t1)
				var tone: float = 0.84 + 0.26 * _r(seed_value + part * 3 + course * 7, 343 + int(side))
				var colour: Color = Color(skin.stone.r * tone, skin.stone.g * tone, skin.stone.b * tone)
				var o0: Vector2 = normal * side * w0
				var o1: Vector2 = normal * side * w1
				pen.quad(Vector3(p0.x + o0.x, y0, p0.y + o0.y), Vector3(p1.x + o0.x, y0, p1.y + o0.y),
					Vector3(p1.x + o1.x, y1, p1.y + o1.y), Vector3(p0.x + o1.x, y1, p0.y + o1.y), Vector3(normal.x * side, 0.25, normal.y * side), colour)
	# The coping: stones on edge, a little ragged along the top.
	var lift: float = height + 0.03 + 0.03 * _r(seed_value, 345)
	var w: float = top + 0.015
	var c: Array[Vector2] = [a - normal * w, b - normal * w, b + normal * w, a + normal * w]
	pen.quad(Vector3(c[0].x, lift, c[0].y), Vector3(c[1].x, lift, c[1].y), Vector3(c[2].x, lift, c[2].y), Vector3(c[3].x, lift, c[3].y),
		Vector3.UP, skin.stone_light.darkened(0.06 * _r(seed_value, 346)))
	for side: float in [-1.0, 1.0]:
		var p: Vector2 = a + normal * side * w
		var q: Vector2 = b + normal * side * w
		pen.quad(Vector3(p.x, height, p.y), Vector3(q.x, height, q.y), Vector3(q.x, lift, q.y), Vector3(p.x, lift, p.y),
			Vector3(normal.x * side, 0.0, normal.y * side), skin.stone_dark)
	pen.quad(Vector3(c[1].x, height, c[1].y), Vector3(c[2].x, height, c[2].y), Vector3(c[2].x, lift, c[2].y), Vector3(c[1].x, lift, c[1].y),
		Vector3(along.x, 0.0, along.y), skin.stone_dark)
	_shade_line(shadows, a, b, base, height * 0.8, 0.26)


## One length of hedgerow: two or three lumpy bushes, now and then hawthorn in blossom.
func _hedge_piece(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, a: Vector2, b: Vector2, seed_value: int) -> void:
	var keep: float = pen.soup.sway
	pen.soup.sway = 0.35
	_hedge_piece_body(pen, shadows, a, b, seed_value)
	pen.soup.sway = keep


func _hedge_piece_body(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, a: Vector2, b: Vector2, seed_value: int) -> void:
	var mid: Vector2 = (a + b) * 0.5
	var along: Vector2 = (b - a).normalized()
	var spin: float = atan2(along.y, along.x)
	var colour: Color = skin.hedge_colors[int(_r(seed_value, 351) * 97.0) % skin.hedge_colors.size()]
	var height: float = 0.27 + 0.07 * _r(seed_value, 352)
	var p: Vector3 = Vector3(mid.x, height, mid.y)
	pen.lump(p, 0.32, height, 0.25, spin, colour, colour.darkened(0.3))
	if _r(seed_value, 353) < 0.4:
		var top: Color = colour.lightened(0.07)
		pen.lump(p + Vector3(along.x * 0.06, height * 0.75, along.y * 0.06), 0.18, 0.17, 0.16, spin + 0.5, top, colour)
	if _r(seed_value, 354) < 0.18:
		for index: int in 3:
			var off: Vector3 = Vector3((_r(seed_value + index, 355) - 0.5) * 0.3, height * 1.35 + 0.05 * float(index), (_r(seed_value + index, 356) - 0.5) * 0.25)
			pen.lump(Vector3(mid.x, 0.0, mid.y) + off, 0.04, 0.03, 0.04, float(index), skin.blossom, skin.blossom.darkened(0.15))
	_shade_line(shadows, a, b, 0.2, height * 1.4, 0.24)


## A strip of shade beside a boundary, cast away from the light.
func _shade_line(shadows: NeighbourhoodGround.Soup, a: Vector2, b: Vector2, half: float, height: float, alpha: float) -> void:
	var push: Vector2 = light_shift * height
	var along: Vector2 = (b - a).normalized()
	var normal: Vector2 = Vector2(-along.y, along.x) * half
	var points: Array[Vector2] = [a - normal, b - normal, b + normal, a + normal]
	var corners: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		corners.append(point)
		corners.append(point + push)
	var hull: PackedVector2Array = Geometry2D.convex_hull(corners)
	var ring: Array[Vector2] = []
	for index: int in hull.size() - 1:
		ring.append(hull[index])
	var centre: Vector2 = (a + b) * 0.5 + push * 0.5
	shadows.star(centre, ring, SHADOW_Y, Color(0.08, 0.1, 0.05, alpha))


func _shade_rect(shadows: NeighbourhoodGround.Soup, rect: Rect2, height: float, alpha: float) -> void:
	var push: Vector2 = light_shift * height
	var corners: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		corners.append(corner)
		corners.append(corner + push)
	var hull: PackedVector2Array = Geometry2D.convex_hull(corners)
	var points: Array[Vector2] = []
	for index: int in hull.size() - 1:
		points.append(hull[index])
	shadows.star(rect.get_center() + push * 0.5, points, SHADOW_Y, Color(0.08, 0.08, 0.05, alpha))


func _shade_disc(shadows: NeighbourhoodGround.Soup, at: Vector2, radius: float, alpha: float) -> void:
	var points: Array[Vector2] = []
	for index: int in 8:
		var angle: float = TAU * float(index) / 8.0
		points.append(at + Vector2(cos(angle), sin(angle) * 0.8) * radius)
	shadows.star(at, points, SHADOW_Y, Color(0.08, 0.08, 0.05, alpha))


## The hedgerows down both sides of the lane, a low dry-stone wall in front of the
## forecourt (open at the door's path) and gaps at the stream and the farm gate.
func _lane_hedges(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var outer: float = _outer()
	var step: float = 0.44
	var u: float = world_centre.x - outer
	var court: Rect2 = Rect2(forecourt.position.x, forecourt.position.y, forecourt.size.x, forecourt.size.y + 0.4)
	var index: int = 0
	while u < world_centre.x + outer:
		var u1: float = u + step
		for side: float in [-1.0, 1.0]:
			var z0: float = _near_hedge(u) if side < 0.0 else _far_hedge(u)
			var z1: float = _near_hedge(u1) if side < 0.0 else _far_hedge(u1)
			var a: Vector2 = Vector2(u, z0)
			var b: Vector2 = Vector2(u1, z1)
			var mid: Vector2 = (a + b) * 0.5
			if _on_stream(mid, 0.45) or _is_blocked(mid, 0.15) or gate.grow(0.05).has_point(mid):
				continue
			var plain: bool = _distance_to_lot(mid) > DETAIL_REACH
			var seed_value: int = index * 2 + (1 if side > 0.0 else 0)
			if side < 0.0 and mid.x > court.position.x and mid.x < court.end.x:
				_wall_piece(pen, shadows, a, b, seed_value)
			elif plain:
				if index % 5 == 0:
					var far: Vector2 = Vector2(u + step * 5.0, _near_hedge(u + step * 5.0) if side < 0.0 else _far_hedge(u + step * 5.0))
					_plain_bound(pen, a, far, true)
			else:
				_hedge_piece(pen, shadows, a, b, seed_value + 9000)
		u = u1
		index += 1


# --- the mill's yard -----------------------------------------------------------

## The gravel forecourt between the mill and its wall on the lane: flagstones from the
## door to the lane, two lantern posts at the wall's gap, an old millstone propped by
## the wall, half-barrel tubs of flowers, a bench and a little cart of flour sacks.
func _forecourt(ground: NeighbourhoodBuildings.Pen, props: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var court: Rect2 = forecourt
	var door_u: float = _door_u()
	# A gravel apron before the door, wide at the mill and narrowing to the wall's gap,
	# its edges ragged into the grass.
	var depth: float = court.end.y - shift
	var steps: int = 8
	var points_left: Array[Vector2] = []
	var points_right: Array[Vector2] = []
	for index: int in steps + 1:
		var t: float = float(index) / float(steps)
		var z: float = shift - 0.02 + t * depth
		var half: float = lerpf(2.5, 0.75, smoothstep(0.0, 1.0, t)) + 0.12 * sin(float(index) * 2.1)
		points_left.append(Vector2(maxf(door_u - half, court.position.x), z))
		points_right.append(Vector2(minf(door_u + half, court.end.x), z))
	for index: int in steps:
		var a: Vector2 = points_left[index]
		var b: Vector2 = points_right[index]
		var c: Vector2 = points_right[index + 1]
		var d: Vector2 = points_left[index + 1]
		ground.quad(Vector3(a.x, GRAVEL_Y, a.y), Vector3(b.x, GRAVEL_Y, b.y), Vector3(c.x, GRAVEL_Y, c.y), Vector3(d.x, GRAVEL_Y, d.y), Vector3.UP, skin.gravel)
		for edge: Vector2 in [a, b]:
			_blob(ground, edge, 0.2 + 0.08 * _r(index, 407), 0.22, _r(index, 408), 7, GRAVEL_Y - 0.001, skin.gravel)
	var specks: int = int(depth * 5.0 * 30.0)
	for index: int in specks:
		var t: float = _r(index, 402)
		var half: float = lerpf(2.4, 0.7, smoothstep(0.0, 1.0, t))
		var at: Vector2 = Vector2(door_u + (_r(index, 401) * 2.0 - 1.0) * half, shift + t * depth)
		var size: float = 0.03 + _r(index, 403) * 0.05
		_blob(ground, at, size, size * 0.8, _r(index, 404) * PI, 5, GRAVEL_Y + 0.0015,
			skin.gravel.darkened(0.1) if index % 3 != 0 else skin.gravel.lightened(0.08))
	# A cottage-garden border along the wall's inside, either side of the apron.
	var hedge_line: float = _near_hedge(door_u)
	var border_u: float = court.position.x + 0.2
	var index_border: int = 0
	while border_u < court.end.x - 0.2:
		var at: Vector2 = Vector2(border_u, hedge_line - 0.24 - 0.08 * _r(index_border, 409))
		border_u += 0.17 + 0.06 * _r(index_border, 410)
		index_border += 1
		if absf(at.x - door_u) < 1.1 or _keep_clear_hit(at, 0.15):
			continue
		var p: Vector3 = Vector3(at.x, GRAVEL_Y, at.y)
		_tuft(props, p, 0.2 + 0.08 * _r(index_border, 414), skin.meadow.lerp(skin.grass_dark, 0.3), index_border * 3)
		if index_border % 2 == 0:
			var colour: Color = skin.flower_colors[(index_border >> 1) % skin.flower_colors.size()]
			_flower(props, p + Vector3(0.04, 0.0, 0.03), 0.22 + 0.06 * _r(index_border, 415), colour, index_border)
			_flower(props, p + Vector3(-0.05, 0.0, -0.02), 0.18 + 0.06 * _r(index_border, 416), colour, index_border + 1)
		if index_border % 5 == 0:
			var leaf: Color = skin.hedge_colors[index_border % skin.hedge_colors.size()].lightened(0.1)
			props.lump(p + Vector3(0.0, 0.12, -0.05), 0.15, 0.12, 0.12, float(index_border), leaf, leaf.darkened(0.25))
	# Flagstones from the door to the lane.
	var z: float = shift + 0.3
	var index: int = 0
	while z < lane_z(door_u) - LANE_HALF - 0.1:
		var at: Vector2 = Vector2(door_u + (_r(index, 411) - 0.5) * 0.16, z)
		var size: float = 0.21 + _r(index, 412) * 0.05
		_blob(ground, at, size + 0.025, 0.19, _r(index, 413) * PI, 6, GRAVEL_Y + 0.0025, skin.stone_dark)
		_blob(ground, at, size, 0.165, _r(index, 413) * PI, 6, GRAVEL_Y + 0.0035, skin.stone_light)
		z += 0.46
		index += 1
	# The wall's gap at the path: two lantern posts.
	var hedge: float = _near_hedge(door_u)
	for side: float in [-1.0, 1.0]:
		var foot: Vector3 = Vector3(door_u + side * 0.62, GRAVEL_Y, hedge - 0.2)
		if _keep_clear_hit(Vector2(foot.x, foot.z), 0.05):
			foot.z = hedge + 0.12
		props.box(foot + Vector3(-0.05, 0.0, -0.05), foot + Vector3(0.05, 0.62, 0.05), skin.timber_dark)
		props.box(foot + Vector3(-0.07, 0.62, -0.07), foot + Vector3(0.07, 0.65, 0.07), skin.timber_dark)
		_lantern(props, foot + Vector3(0.0, 0.65, 0.0))
		_add_light(foot + Vector3(0.0, 0.73, 0.0), 0.55, true)
		_shade_disc(shadows, Vector2(foot.x, foot.z) + light_shift * 0.4, 0.07, 0.25)
	# Pieces along the wall, on the roomier side of the path: the millstone, a bench,
	# tubs of flowers; the flour cart on the other side.
	var left_room: float = door_u - court.position.x
	var right_room: float = court.end.x - door_u
	var roomy: float = -1.0 if left_room >= right_room else 1.0
	var spots: Array[float] = [0.95, 1.75, 2.45]
	var kinds: Array[StringName] = [&"tub", &"millstone", &"bench"]
	for index_spot: int in spots.size():
		var u: float = door_u + roomy * spots[index_spot]
		var at: Vector2 = Vector2(u, hedge - 0.66)
		if at.x < court.position.x + 0.3 or at.x > court.end.x - 0.3 or _keep_clear_hit(at, 0.35):
			continue
		match kinds[index_spot]:
			&"tub":
				_flower_tub(props, shadows, Vector3(at.x, GRAVEL_Y, at.y + 0.1), index_spot)
			&"millstone":
				_millstone(props, shadows, Vector3(at.x, GRAVEL_Y, at.y + 0.08))
			_:
				_bench(props, shadows, Vector3(at.x, GRAVEL_Y, at.y), roomy)
	var cart_at: Vector2 = Vector2(door_u - roomy * 1.5, hedge - 0.7)
	if cart_at.x > court.position.x + 0.4 and cart_at.x < court.end.x - 0.4 and not _keep_clear_hit(cart_at, 0.4):
		_flour_cart(props, shadows, Vector3(cart_at.x, GRAVEL_Y, cart_at.y))
	var tub_at: Vector2 = Vector2(door_u - roomy * 0.95, hedge - 0.5)
	if not _keep_clear_hit(tub_at, 0.3) and tub_at.x > court.position.x + 0.3 and tub_at.x < court.end.x - 0.3:
		_flower_tub(props, shadows, Vector3(tub_at.x, GRAVEL_Y, tub_at.y), 7)


func _keep_clear_hit(point: Vector2, margin: float) -> bool:
	for rect: Rect2 in keep_clear:
		if rect.grow(margin).has_point(point):
			return true
	return point.x > _door_u() - 0.45 - margin and point.x < _door_u() + 0.45 + margin and point.y > shift - 0.1


## A square lantern: a dark cap and base round a glass box (the glass glows at night).
func _lantern(pen: NeighbourhoodBuildings.Pen, base: Vector3) -> void:
	pen.box(base + Vector3(-0.05, 0.0, -0.05), base + Vector3(0.05, 0.02, 0.05), skin.iron)
	for corner: Vector2 in [Vector2(-0.04, -0.04), Vector2(0.04, -0.04), Vector2(0.04, 0.04), Vector2(-0.04, 0.04)]:
		pen.box(base + Vector3(corner.x - 0.008, 0.02, corner.y - 0.008), base + Vector3(corner.x + 0.008, 0.14, corner.y + 0.008), skin.iron)
	pen.box(base + Vector3(-0.034, 0.02, -0.034), base + Vector3(0.034, 0.14, 0.034), skin.lamp_glow.lerp(skin.ripple, 0.5))
	pen.box(base + Vector3(-0.06, 0.14, -0.06), base + Vector3(0.06, 0.165, 0.06), skin.iron)
	pen.box(base + Vector3(-0.02, 0.165, -0.02), base + Vector3(0.02, 0.2, 0.02), skin.iron)


## A warm light at night: a glow sprite and, when `pool`, a pool of light on the ground.
func _add_light(at: Vector3, size: float, pool: bool) -> void:
	_lights.append(at)
	_light_sizes.append(size)
	if pool:
		_pool_spots.append(Vector3(at.x, at.z, 1.1))


func _flower_tub(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector3, seed_value: int) -> void:
	_drum(pen, at, 0.17, 0.2, 0.2, 8, skin.timber, skin.soil)
	for ring: float in [0.04, 0.15]:
		_drum(pen, at + Vector3.UP * ring, 0.19 + ring * 0.1, 0.195 + ring * 0.1, 0.025, 8, skin.iron, skin.iron)
	var leaf: Color = skin.hedge_colors[seed_value % skin.hedge_colors.size()].lightened(0.08)
	pen.lump(at + Vector3.UP * 0.25, 0.17, 0.1, 0.17, float(seed_value), leaf, leaf.darkened(0.2))
	for index: int in 7:
		var angle: float = TAU * float(index) / 7.0 + float(seed_value)
		var colour: Color = skin.flower_colors[(seed_value + index) % skin.flower_colors.size()]
		pen.lump(at + Vector3(cos(angle) * 0.11, 0.33 + 0.03 * float(index % 2), sin(angle) * 0.11), 0.035, 0.025, 0.035, angle, colour, colour.darkened(0.2))
	_shade_disc(shadows, Vector2(at.x, at.z) + light_shift * 0.15, 0.2, 0.28)


## An old millstone propped upright against the wall, its eye and dressing grooves.
func _millstone(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector3) -> void:
	var radius: float = 0.3
	var thick: float = 0.1
	var lean: Basis = Basis(Vector3.RIGHT, -0.18)
	var centre: Vector3 = at + Vector3(0.0, radius, 0.0)
	var sides: int = 12
	var ring: Array[Vector3] = []
	for index: int in sides:
		var angle: float = TAU * float(index) / float(sides)
		ring.append(Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))
	for index: int in sides:
		var a: Vector3 = ring[index]
		var b: Vector3 = ring[(index + 1) % sides]
		var front: Vector3 = Vector3(0.0, 0.0, thick * 0.5)
		pen.tri(centre + lean * front, centre + lean * (a + front), centre + lean * (b + front), lean * Vector3.BACK, skin.stone_light)
		pen.tri(centre - lean * front, centre + lean * (b - front), centre + lean * (a - front), lean * Vector3.FORWARD, skin.stone)
		pen.quad(centre + lean * (a - front), centre + lean * (b - front), centre + lean * (b + front), centre + lean * (a + front),
			lean * ((a + b) * 0.5), skin.stone.darkened(0.05))
	# The eye and four grooves on the face.
	var face: Vector3 = Vector3(0.0, 0.0, thick * 0.5 + 0.004)
	pen.quad(centre + lean * (face + Vector3(-0.05, -0.05, 0.0)), centre + lean * (face + Vector3(0.05, -0.05, 0.0)),
		centre + lean * (face + Vector3(0.05, 0.05, 0.0)), centre + lean * (face + Vector3(-0.05, 0.05, 0.0)), lean * Vector3.BACK, skin.stone_dark)
	for index: int in 4:
		var angle: float = TAU * float(index) / 4.0 + 0.4
		var out: Vector3 = Vector3(cos(angle), sin(angle), 0.0)
		var across: Vector3 = Vector3(-sin(angle), cos(angle), 0.0) * 0.012
		pen.quad(centre + lean * (face + out * 0.08 - across), centre + lean * (face + out * 0.27 - across),
			centre + lean * (face + out * 0.27 + across), centre + lean * (face + out * 0.08 + across), lean * Vector3.BACK, skin.stone)
	_shade_rect(shadows, Rect2(at.x - radius, at.z - 0.1, radius * 2.0, 0.2), 0.4, 0.28)


func _bench(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector3, roomy: float) -> void:
	var half: float = 0.36
	for x: float in [-half + 0.06, half - 0.06]:
		pen.box(at + Vector3(x - 0.03, 0.0, -0.1), at + Vector3(x + 0.03, 0.26, 0.1), skin.timber_dark)
	for slat: int in 3:
		var z: float = -0.1 + float(slat) * 0.075
		pen.box(at + Vector3(-half, 0.25, z), at + Vector3(half, 0.28, z + 0.06), skin.timber)
	pen.box(at + Vector3(-half, 0.3, 0.12), at + Vector3(half, 0.5, 0.15), skin.timber)
	pen.box(at + Vector3(-half + 0.04, 0.26, 0.11), at + Vector3(-half + 0.08, 0.52, 0.14), skin.timber_dark)
	pen.box(at + Vector3(half - 0.08, 0.26, 0.11), at + Vector3(half - 0.04, 0.52, 0.14), skin.timber_dark)
	_shade_rect(shadows, Rect2(at.x - half, at.z - 0.15, half * 2.0, 0.27), 0.3, 0.26)


## A two-wheeled hand cart with flour sacks.
func _flour_cart(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector3) -> void:
	pen.box(at + Vector3(-0.3, 0.2, -0.18), at + Vector3(0.3, 0.24, 0.18), skin.timber)
	for side: float in [-0.18, 0.18]:
		pen.box(at + Vector3(-0.3, 0.24, side - 0.015), at + Vector3(0.3, 0.33, side + 0.015), skin.timber_dark)
		_wheel_disc(pen, at + Vector3(0.0, 0.17, side + signf(side) * 0.04), 0.17, skin.timber_dark, skin.iron)
	pen.box(at + Vector3(0.3, 0.22, -0.13), at + Vector3(0.62, 0.25, -0.1), skin.timber_dark)
	pen.box(at + Vector3(0.3, 0.22, 0.1), at + Vector3(0.62, 0.25, 0.13), skin.timber_dark)
	pen.box(at + Vector3(-0.28, 0.0, -0.02), at + Vector3(-0.24, 0.2, 0.02), skin.timber_dark)
	var sack: Color = skin.stone_light.lerp(Color.WHITE, 0.35)
	for index: int in 3:
		var p: Vector3 = at + Vector3(-0.15 + float(index) * 0.15, 0.32 + 0.04 * float(index % 2), 0.0)
		pen.lump(p, 0.08, 0.1, 0.12, float(index), sack, sack.darkened(0.15))
	_shade_rect(shadows, Rect2(at.x - 0.3, at.z - 0.2, 0.9, 0.4), 0.3, 0.26)


## A wheel facing along x (its axle along x): a rim of `radius` and four spokes.
func _wheel_disc(pen: NeighbourhoodBuildings.Pen, centre: Vector3, radius: float, rim: Color, hub: Color) -> void:
	var sides: int = 10
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var p0: Vector3 = centre + Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1: Vector3 = centre + Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		var q0: Vector3 = centre + Vector3(cos(a0) * radius * 0.82, sin(a0) * radius * 0.82, 0.0)
		var q1: Vector3 = centre + Vector3(cos(a1) * radius * 0.82, sin(a1) * radius * 0.82, 0.0)
		pen.quad(p0, p1, q1, q0, Vector3.BACK, rim)
	for index: int in 4:
		var angle: float = TAU * float(index) / 4.0
		var out: Vector3 = Vector3(cos(angle), sin(angle), 0.0)
		var across: Vector3 = Vector3(-sin(angle), cos(angle), 0.0) * 0.012
		pen.quad(centre - across, centre + out * radius * 0.85 - across, centre + out * radius * 0.85 + across, centre + across, Vector3.BACK, rim)
	pen.box(centre - Vector3(0.03, 0.03, 0.02), centre + Vector3(0.03, 0.03, 0.02), hub)


## An upright drum: `r0` at the foot, `r1` at the top, with a capped top.
func _drum(pen: NeighbourhoodBuildings.Pen, base: Vector3, r0: float, r1: float, height: float, sides: int, side: Color, top: Color) -> void:
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		pen.quad(base + d0 * r0, base + d1 * r0, base + d1 * r1 + Vector3.UP * height, base + d0 * r1 + Vector3.UP * height, (d0 + d1) * 0.5, side)
		pen.tri(base + Vector3.UP * height, base + d0 * r1 + Vector3.UP * height, base + d1 * r1 + Vector3.UP * height, Vector3.UP, top)


## A cylinder lying along `axis` (a hay bale, a log): `radius`, `length`, flat ends.
func _roll(pen: NeighbourhoodBuildings.Pen, centre: Vector3, axis: Vector3, radius: float, length: float, side: Color, end: Color) -> void:
	var a: Vector3 = centre - axis * length * 0.5
	var b: Vector3 = centre + axis * length * 0.5
	var across: Vector3 = axis.cross(Vector3.UP).normalized()
	var up: Vector3 = across.cross(axis).normalized()
	var ring: Array[Vector3] = []
	for index: int in 8:
		var angle: float = TAU * float(index) / 8.0 + 0.2
		ring.append(across * cos(angle) * radius + up * sin(angle) * radius)
	for index: int in 8:
		var next: int = (index + 1) % 8
		pen.quad(a + ring[index], b + ring[index], b + ring[next], a + ring[next], (ring[index] + ring[next]) * 0.5,
			side if index % 2 == 0 else side.darkened(0.05))
		pen.tri(a, a + ring[index], a + ring[next], -axis, end)
		pen.tri(b, b + ring[next], b + ring[index], axis, end)


## A tuft of grass or reeds: a few thin leaning blades.
func _tuft(pen: NeighbourhoodBuildings.Pen, at: Vector3, height: float, colour: Color, seed_value: int) -> void:
	var keep: float = pen.soup.sway
	pen.soup.sway = 1.0
	_tuft_body(pen, at, height, colour, seed_value)
	pen.soup.sway = keep


func _tuft_body(pen: NeighbourhoodBuildings.Pen, at: Vector3, height: float, colour: Color, seed_value: int) -> void:
	for index: int in 4:
		var angle: float = _r(seed_value + index, 111) * TAU
		var lean: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * height * 0.35
		var across: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * 0.03
		pen.tri(at - across, at + across, at + lean + Vector3.UP * height * (0.7 + 0.3 * _r(seed_value + index, 112)), lean + Vector3.UP * 0.2,
			colour if index % 2 == 0 else colour.lightened(0.08))


# --- the farm gate and the produce stand ----------------------------------------

## A five-bar gate in the hedge gap into the meadow, between two stout posts.
func _farm_gate(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var z: float = gate.get_center().y
	var a: float = gate.position.x
	var b: float = gate.end.x
	for u: float in [a, b]:
		pen.box(Vector3(u - 0.06, FIELD_Y, z - 0.06), Vector3(u + 0.06, 0.6, z + 0.06), skin.timber_dark)
		pen.box(Vector3(u - 0.07, 0.6, z - 0.07), Vector3(u + 0.07, 0.63, z + 0.07), skin.timber_dark.darkened(0.1))
		_shade_disc(shadows, Vector2(u, z) + light_shift * 0.35, 0.08, 0.26)
	var wood: Color = skin.timber.lightened(0.08)
	var x0: float = a + 0.07
	var x1: float = b - 0.07
	for bar: int in 5:
		var y: float = 0.12 + float(bar) * 0.1
		pen.box(Vector3(x0, y, z - 0.015), Vector3(x1, y + 0.04, z + 0.015), wood)
	for x: float in [x0, x0 + 0.04, x1 - 0.04]:
		pen.box(Vector3(x, 0.1, z - 0.02), Vector3(x + 0.04, 0.56, z + 0.02), wood)
	# The brace, corner to corner.
	var low: Vector3 = Vector3(x0 + 0.05, 0.13, z)
	var high: Vector3 = Vector3(x1 - 0.05, 0.53, z)
	var lift: Vector3 = Vector3(0.0, 0.035, 0.0)
	var depth: Vector3 = Vector3(0.0, 0.0, 0.018)
	pen.quad(low - depth, high - depth, high - depth + lift, low - depth + lift, Vector3.FORWARD, wood.darkened(0.05))
	pen.quad(low + depth, high + depth, high + depth + lift, low + depth + lift, Vector3.BACK, wood.darkened(0.05))
	pen.quad(low - depth + lift, high - depth + lift, high + depth + lift, low + depth + lift, Vector3.UP, wood)
	pen.box(Vector3(x1 - 0.1, 0.42, z - 0.03), Vector3(x1 + 0.02, 0.45, z + 0.03), skin.iron)
	_shade_line(shadows, Vector2(a, z), Vector2(b, z), 0.03, 0.5, 0.18)


## The farm's produce stand on the verge: a table under a little shingled roof with
## crates of vegetables and apples, more crates below, a chalkboard and an honesty box
## on a post. A lantern hangs under the roof's edge.
func _produce_stand(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var r: Rect2 = stand
	var top: float = 0.4
	# Legs and the table top.
	for x: float in [r.position.x + 0.04, r.end.x - 0.08]:
		for z: float in [r.position.y + 0.04, r.end.y - 0.08]:
			pen.box(Vector3(x, FIELD_Y, z), Vector3(x + 0.04, top, z + 0.04), skin.timber_dark)
	pen.box(Vector3(r.position.x, top, r.position.y), Vector3(r.end.x, top + 0.04, r.end.y), skin.timber)
	pen.box(Vector3(r.position.x + 0.02, 0.1, r.position.y + 0.02), Vector3(r.end.x - 0.02, 0.12, r.end.y - 0.02), skin.timber_dark)
	# The roof posts at the back, rising to a pent roof sloping toward the lane.
	var back: float = r.position.y + 0.02
	for x: float in [r.position.x + 0.02, r.end.x - 0.06]:
		pen.box(Vector3(x, top, back), Vector3(x + 0.04, 0.98, back + 0.04), skin.timber_dark)
	var eave: float = r.end.y + 0.14
	var roof: Array[Vector3] = [Vector3(r.position.x - 0.08, 1.0, back - 0.06), Vector3(r.end.x + 0.08, 1.0, back - 0.06),
		Vector3(r.end.x + 0.08, 0.8, eave), Vector3(r.position.x - 0.08, 0.8, eave)]
	pen.slab(roof, Vector3(0.0, 0.035, 0.0), skin.timber_dark.lightened(0.1))
	# Shingle courses on the roof.
	for course: int in 3:
		var t: float = (float(course) + 0.5) / 3.0
		var y: float = lerpf(1.0, 0.8, t) + 0.037
		var z: float = lerpf(back - 0.06, eave, t)
		pen.box(Vector3(r.position.x - 0.08, y, z - 0.012), Vector3(r.end.x + 0.08, y + 0.012, z + 0.012), skin.timber_dark.lightened(0.02))
	# Crates on the table: produce heaped in each.
	var crate_count: int = 3
	for index: int in crate_count:
		var w: float = (r.size.x - 0.1) / float(crate_count)
		var x0: float = r.position.x + 0.05 + float(index) * w
		_crate(pen, Vector3(x0 + w * 0.5, top + 0.04, r.get_center().y + 0.03), w - 0.04, 0.3, index)
	# Two more crates on the ground in front, one stacked.
	_crate(pen, Vector3(r.position.x - 0.22, FIELD_Y + 0.01, r.end.y - 0.05), 0.26, 0.26, 3)
	_crate(pen, Vector3(r.end.x + 0.2, FIELD_Y + 0.01, r.end.y - 0.08), 0.26, 0.26, 4)
	# The chalkboard on the front edge, and the honesty box on a post.
	var board: Vector3 = Vector3(r.get_center().x, top + 0.05, r.end.y + 0.01)
	pen.box(board + Vector3(-0.18, 0.14, -0.012), board + Vector3(0.18, 0.18, 0.012), skin.timber_dark)
	pen.box(board + Vector3(-0.16, -0.03, 0.0), board + Vector3(0.16, 0.0, 0.012), skin.timber_dark)
	var post: Vector3 = Vector3(r.end.x + 0.45, FIELD_Y, r.get_center().y + 0.1)
	pen.box(post + Vector3(-0.03, 0.0, -0.03), post + Vector3(0.03, 0.45, 0.03), skin.timber_dark)
	pen.box(post + Vector3(-0.09, 0.45, -0.07), post + Vector3(0.09, 0.6, 0.07), skin.sign_paint.lerp(skin.timber, 0.25))
	pen.box(post + Vector3(-0.1, 0.6, -0.08), post + Vector3(0.1, 0.62, 0.08), skin.timber_dark)
	pen.box(post + Vector3(-0.04, 0.62, -0.006), post + Vector3(0.04, 0.625, 0.006), skin.iron)
	pen.box(post + Vector3(-0.03, 0.51, 0.071), post + Vector3(0.03, 0.56, 0.075), skin.iron)
	_shade_disc(shadows, Vector2(post.x, post.z) + light_shift * 0.3, 0.1, 0.24)
	# The A-board chalkboard by the lane: its face to the passers-by.
	var foot: Vector3 = Vector3(r.position.x - 0.45, FIELD_Y, r.end.y + 0.12)
	var legs: Array[Vector3] = [foot + Vector3(-0.13, 0.0, -0.1), foot + Vector3(0.13, 0.0, -0.1), foot + Vector3(0.13, 0.0, 0.1), foot + Vector3(-0.13, 0.0, 0.1)]
	var peak: float = 0.5
	pen.quad(legs[3], legs[2], foot + Vector3(0.13, peak, 0.0), foot + Vector3(-0.13, peak, 0.0), Vector3(0.0, 0.2, 1.0), skin.timber_dark)
	pen.quad(legs[0], legs[1], foot + Vector3(0.13, peak, 0.0), foot + Vector3(-0.13, peak, 0.0), Vector3(0.0, 0.2, -1.0), skin.timber_dark)
	pen.quad(foot + Vector3(-0.1, 0.06, 0.087), foot + Vector3(0.1, 0.06, 0.087), foot + Vector3(0.1, 0.44, 0.015), foot + Vector3(-0.1, 0.44, 0.015),
		Vector3(0.0, 0.2, 1.0), skin.chalkboard)
	# Chalk lines: a heading and two prices.
	for line: int in 3:
		var y: float = 0.36 - float(line) * 0.09
		var t: float = (0.44 - y) / 0.38
		var z: float = lerpf(0.016, 0.087, 1.0 - t) + 0.003
		var width: float = 0.07 if line == 0 else 0.05
		pen.quad(foot + Vector3(-width, y, z), foot + Vector3(width, y, z), foot + Vector3(width, y + 0.018, z - 0.004), foot + Vector3(-width, y + 0.018, z - 0.004),
			Vector3(0.0, 0.2, 1.0), skin.sign_paint)
	_shade_disc(shadows, Vector2(foot.x, foot.z) + light_shift * 0.25, 0.16, 0.24)
	# A lantern hanging at the roof's front corner.
	var hook: Vector3 = Vector3(r.end.x - 0.02, 0.62, eave - 0.06)
	pen.box(hook + Vector3(-0.006, 0.08, -0.006), hook + Vector3(0.006, 0.2, 0.006), skin.iron)
	_lantern(pen, hook - Vector3(0.0, 0.1, 0.0))
	_add_light(hook + Vector3(0.0, 0.0, 0.0), 0.5, false)
	_pool_spots.append(Vector3(r.get_center().x, r.end.y + 0.2, 1.0))
	_shade_rect(shadows, Rect2(r.position.x - 0.08, back - 0.06, r.size.x + 0.16, eave - back + 0.06), 0.9, 0.24)


## A slatted crate `width` by `depth`, heaped with one kind of produce.
func _crate(pen: NeighbourhoodBuildings.Pen, base: Vector3, width: float, depth: float, index: int) -> void:
	var height: float = 0.13
	var lo: Vector3 = base + Vector3(-width * 0.5, 0.0, -depth * 0.5)
	var hi: Vector3 = base + Vector3(width * 0.5, height, depth * 0.5)
	pen.box(lo, Vector3(hi.x, lo.y + 0.02, hi.z), skin.crate.darkened(0.1))
	for slat: int in 2:
		var y: float = lo.y + 0.03 + float(slat) * 0.05
		pen.box(Vector3(lo.x, y, lo.z), Vector3(hi.x, y + 0.035, lo.z + 0.015), skin.crate)
		pen.box(Vector3(lo.x, y, hi.z - 0.015), Vector3(hi.x, y + 0.035, hi.z), skin.crate)
		pen.box(Vector3(lo.x, y, lo.z), Vector3(lo.x + 0.015, y + 0.035, hi.z), skin.crate)
		pen.box(Vector3(hi.x - 0.015, y, lo.z), Vector3(hi.x, y + 0.035, hi.z), skin.crate)
	for corner: Vector2 in [Vector2(lo.x, lo.z), Vector2(hi.x - 0.025, lo.z), Vector2(hi.x - 0.025, hi.z - 0.025), Vector2(lo.x, hi.z - 0.025)]:
		pen.box(Vector3(corner.x, lo.y, corner.y), Vector3(corner.x + 0.025, hi.y, corner.y + 0.025), skin.crate.darkened(0.12))
	var colour: Color = skin.produce_colors[index % skin.produce_colors.size()]
	# A heap: rows of round produce, the middle row higher.
	var columns: int = maxi(2, int(width / 0.07))
	var rows: int = maxi(2, int(depth / 0.07))
	for ix: int in columns:
		for iz: int in rows:
			var fx: float = (float(ix) + 0.5) / float(columns)
			var fz: float = (float(iz) + 0.5) / float(rows)
			var mound: float = 1.0 - absf(fx - 0.5) * 1.2 - absf(fz - 0.5) * 1.2
			var p: Vector3 = Vector3(lerpf(lo.x + 0.03, hi.x - 0.03, fx), lo.y + 0.08 + mound * 0.06, lerpf(lo.z + 0.03, hi.z - 0.03, fz))
			var size: float = 0.034 + 0.008 * _r(ix * 7 + index, iz + 420)
			var tone: Color = colour.lightened(0.06) if (ix + iz) % 2 == 0 else colour.darkened(0.05)
			pen.lump(p, size, size * 0.85, size, float(ix + iz), tone, tone.darkened(0.2))


# --- the stream's stonework ------------------------------------------------------

## The lane's little stone bridge over the stream: a parapet each side of the lane,
## coped and slightly humped, with a stone at each end.
func _bridge(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var u: float = stream_u(bridge_z)
	var half_span: float = stream_half(bridge_z) + 0.45
	for side: float in [-1.0, 1.0]:
		var z: float = lane_z(u) + side * (LANE_HALF + 0.12)
		var segments: int = 6
		for index: int in segments:
			var t0: float = float(index) / float(segments)
			var t1: float = float(index + 1) / float(segments)
			var a: float = u - half_span + t0 * half_span * 2.0
			var b: float = u - half_span + t1 * half_span * 2.0
			var h0: float = 0.28 + 0.05 * sin(t0 * PI)
			var h1: float = 0.28 + 0.05 * sin(t1 * PI)
			var tone: Color = skin.stone if index % 2 == 0 else skin.stone.darkened(0.06)
			var za: float = lane_z(a) + side * (LANE_HALF + 0.12)
			var zb: float = lane_z(b) + side * (LANE_HALF + 0.12)
			for face: float in [-1.0, 1.0]:
				pen.quad(Vector3(a, EDGE_Y, za + face * 0.09), Vector3(b, EDGE_Y, zb + face * 0.09), Vector3(b, h1, zb + face * 0.08),
					Vector3(a, h0, za + face * 0.08), Vector3(0.0, 0.0, face), tone)
			pen.quad(Vector3(a, h0 + 0.035, za - 0.1), Vector3(b, h1 + 0.035, zb - 0.1), Vector3(b, h1 + 0.035, zb + 0.1),
				Vector3(a, h0 + 0.035, za + 0.1), Vector3.UP, skin.stone_light)
			for face: float in [-1.0, 1.0]:
				pen.quad(Vector3(a, h0, za + face * 0.1), Vector3(b, h1, zb + face * 0.1), Vector3(b, h1 + 0.035, zb + face * 0.1),
					Vector3(a, h0 + 0.035, za + face * 0.1), Vector3(0.0, 0.0, face), skin.stone_dark)
		# End stones.
		for end: float in [u - half_span, u + half_span]:
			var ze: float = lane_z(end) + side * (LANE_HALF + 0.12)
			pen.box(Vector3(end - 0.1, EDGE_Y, ze - 0.11), Vector3(end + 0.1, 0.36, ze + 0.11), skin.stone.darkened(0.04))
			pen.box(Vector3(end - 0.12, 0.36, ze - 0.12), Vector3(end + 0.12, 0.4, ze + 0.12), skin.stone_light)
			_shade_disc(shadows, Vector2(end, ze) + light_shift * 0.3, 0.15, 0.24)
			if side < 0.0 and (end - u) * stream_side < 0.0:
				_lantern(pen, Vector3(end, 0.4, ze))
				_add_light(Vector3(end, 0.48, ze), 0.5, true)
		_shade_line(shadows, Vector2(u - half_span, z), Vector2(u + half_span, z), 0.09, 0.3, 0.22)
	# The arch's dark mouth on the water, upstream and down.
	for side: float in [-1.0, 1.0]:
		var z: float = lane_z(u) + side * (LANE_HALF + 0.24)
		_blob_soup(shadows, Vector2(u, z), stream_half(z) * 0.9, 0.13, 0.0, 8, SHADOW_Y, Color(0.04, 0.06, 0.06, 0.5))


func _blob_soup(soup: NeighbourhoodGround.Soup, at: Vector2, rx: float, rz: float, spin: float, sides: int, y: float, colour: Color) -> void:
	var points: Array[Vector2] = []
	for index: int in sides:
		var angle: float = spin + TAU * float(index) / float(sides)
		points.append(at + Vector2(cos(angle) * rx, sin(angle) * rz))
	soup.star(at, points, y, colour)


## The weir below the mill pond: a lip of squared stones across the stream, with a
## stone wing at each bank.
func _weir(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var u: float = stream_u(weir_z)
	var half: float = stream_half(weir_z) + 0.08
	var count: int = 7
	for index: int in count:
		var a: float = u - half + float(index) * half * 2.0 / float(count)
		var b: float = a + half * 2.0 / float(count) - 0.015
		var top: float = 0.035 + 0.012 * _r(index, 501)
		pen.box(Vector3(a, WATER_Y - 0.02, weir_z - 0.09), Vector3(b, top, weir_z + 0.09), skin.stone if index % 2 == 0 else skin.stone_light.darkened(0.08))
	for side: float in [-1.0, 1.0]:
		var x: float = u + side * (half + 0.12)
		pen.box(Vector3(x - 0.13, BANK_Y, weir_z - 0.2), Vector3(x + 0.13, 0.14, weir_z + 0.2), skin.stone.darkened(0.05))
		pen.box(Vector3(x - 0.15, 0.14, weir_z - 0.22), Vector3(x + 0.15, 0.17, weir_z + 0.22), skin.stone_light)
		_shade_disc(shadows, Vector2(x, weir_z) + light_shift * 0.15, 0.2, 0.22)


## The wheel pit on the mill's side: a stone pier carries the axle's outer end in the
## stream, a dark wet patch on the wall behind the wheel, and a wooden trough (the
## launder) brings the race's water down onto the wheel.
func _wheel_pit(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var s: float = stream_side
	var out: float = wheel_at.x + s * (WHEEL_WIDTH * 0.5 + 0.05)
	var z: float = wheel_at.z
	# The pit's inner wall along the bank, carrying the axle's inner end.
	var bank: float = _stream_edge() + s * 0.03
	var pit: Rect2 = Rect2(minf(bank, bank + s * 0.15), z - WHEEL_RADIUS - 0.45, 0.15, WHEEL_RADIUS * 2.0 + 0.9)
	pen.box(Vector3(pit.position.x, BANK_Y, pit.position.y), Vector3(pit.end.x, 0.22, pit.end.y), skin.stone)
	pen.box(Vector3(pit.position.x - 0.02, 0.22, pit.position.y - 0.02), Vector3(pit.end.x + 0.02, 0.26, pit.end.y + 0.02), skin.stone_light)
	for course: int in 1:
		var y: float = 0.1 + float(course) * 0.15
		for side_face: float in [bank + s * 0.152]:
			var part: float = 0.25 + 0.3 * _r(course, 515)
			pen.quad(Vector3(side_face, y, pit.position.y + part), Vector3(side_face, y, pit.end.y - part * 0.5),
				Vector3(side_face, y + 0.01, pit.end.y - part * 0.5), Vector3(side_face, y + 0.01, pit.position.y + part), Vector3(signf(side_face - bank) * s * s, 0.0, 0.0), skin.stone_dark)
	# A lantern on a post at the pit's downstream end lights the wheel at night.
	var post: Vector3 = Vector3(bank + s * 0.075, 0.26, pit.end.y - 0.12)
	pen.box(post + Vector3(-0.04, 0.0, -0.04), post + Vector3(0.04, 0.55, 0.04), skin.timber_dark)
	pen.box(post + Vector3(-0.05, 0.55, -0.05), post + Vector3(0.05, 0.58, 0.05), skin.timber_dark)
	_lantern(pen, post + Vector3(0.0, 0.58, 0.0))
	_add_light(post + Vector3(0.0, 0.66, 0.0), 0.5, false)
	_pool_spots.append(Vector3(wheel_at.x, wheel_at.z, 1.2))
	_shade_rect(shadows, pit, 0.5, 0.26)
	# The pier.
	pen.box(Vector3(minf(out, out + s * 0.16), WATER_Y - 0.02, z - 0.16), Vector3(maxf(out, out + s * 0.16), wheel_at.y - 0.03, z + 0.16), skin.stone)
	pen.box(Vector3(minf(out, out + s * 0.16) - 0.02, wheel_at.y - 0.03, z - 0.18), Vector3(maxf(out, out + s * 0.16) + 0.02, wheel_at.y, z + 0.18), skin.stone_light)
	# The bearing block on top of the pier.
	pen.box(Vector3(minf(out, out + s * 0.1), wheel_at.y, z - 0.07), Vector3(maxf(out, out + s * 0.1), wheel_at.y + 0.08, z + 0.07), skin.timber_dark)
	# The launder: a trough on legs, from upstream over the wheel's top-back.
	var inner: float = _stream_edge() + s * 0.16
	var x0: float = minf(inner, wheel_at.x + s * (WHEEL_WIDTH * 0.5 + 0.02))
	var x1: float = maxf(inner, wheel_at.x + s * (WHEEL_WIDTH * 0.5 + 0.02))
	var start: float = z - WHEEL_RADIUS - 1.5
	var end: float = z - WHEEL_RADIUS * 0.55
	var y: float = wheel_at.y + WHEEL_RADIUS * 0.82
	pen.box(Vector3(x0, y - 0.04, start), Vector3(x1, y, end), skin.timber_dark)
	for x: float in [x0, x1 - 0.03]:
		pen.box(Vector3(x, y, start), Vector3(x + 0.03, y + 0.09, end), skin.timber)
	pen.box(Vector3(x0 + 0.03, y - 0.005, start), Vector3(x1 - 0.03, y + 0.005, end - 0.02), skin.water_shallow)
	for leg_z: float in [start + 0.1, start + 0.8]:
		for x: float in [x0 + 0.02, x1 - 0.05]:
			pen.box(Vector3(x, WATER_Y - 0.02, leg_z), Vector3(x + 0.04, y - 0.04, leg_z + 0.04), skin.timber_dark)
	# Water spilling off the launder's end onto the paddles.
	pen.quad(Vector3(x0 + 0.04, y, end - 0.01), Vector3(x1 - 0.04, y, end - 0.01), Vector3(x1 - 0.05, y - 0.22, end + 0.08),
		Vector3(x0 + 0.05, y - 0.22, end + 0.08), Vector3(0.0, 0.3, 1.0), skin.ripple.lerp(skin.water_shallow, 0.3))
	_shade_rect(shadows, Rect2(x0, start, x1 - x0, end - start), y, 0.22)


## A box on the mill's side, `d0`..`d1` metres out from the lot's edge (negative is in
## over the lot), `y0`..`y1` high and `z0`..`z1` along the stream.
func _side_box(pen: NeighbourhoodBuildings.Pen, d0: float, d1: float, y0: float, y1: float, z0: float, z1: float, colour: Color) -> void:
	var a: float = _stream_edge() + stream_side * d0
	var b: float = _stream_edge() + stream_side * d1
	pen.box(Vector3(minf(a, b), y0, z0), Vector3(maxf(a, b), y1, z1), colour)


## The wheel house roof's height `d` metres out from the lot's edge.
func _house_roof(d: float) -> float:
	return lerpf(HOUSE_HIGH, HOUSE_LOW, d / HOUSE_REACH)


## The wheel house (#619): a slate lean-to over the wheel on four timber posts, its high
## side on the pit's wall at the lot's edge and its eaves out over the stream, so the wheel
## turns under the mill's own roof. A boarded casing carries the axle from the wheel's
## inner face to the lot's edge, and on (`housing`, its own mesh) across any strip of the
## lot to the shop's wall; once the shop is built out to the edge, that part is gone and
## the wheel house meets the wall. Nothing of it stands taller than the casing on the lot.
func _wheel_house(pen: NeighbourhoodBuildings.Pen, housing: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var s: float = stream_side
	var edge: float = _stream_edge()
	var z: float = wheel_at.z
	var z0: float = z - HOUSE_HALF
	var z1: float = z + HOUSE_HALF
	var slate: Color = skin.cottage_roofs[1 % skin.cottage_roofs.size()]
	# Posts: the inner pair on the pit's wall, the outer pair on stone footings in the water.
	for post_z: float in [z0 + 0.03, z1 - 0.13]:
		_side_box(pen, 0.03, 0.13, 0.26, _house_roof(0.13) - 0.02, post_z, post_z + 0.1, skin.timber_dark)
		_side_box(pen, 0.6, 0.78, WATER_Y - 0.02, 0.16, post_z - 0.04, post_z + 0.14, skin.stone)
		_side_box(pen, 0.6, 0.78, 0.16, 0.19, post_z - 0.04, post_z + 0.14, skin.stone_light)
		_side_box(pen, 0.64, 0.74, 0.19, _house_roof(0.74) - 0.02, post_z, post_z + 0.1, skin.timber_dark)
		# A knee brace from each post up to its plate.
		for d: float in [0.08, 0.69]:
			var inward: float = 1.0 if post_z < z else -1.0
			var foot: Vector3 = Vector3(edge + s * d, _house_roof(d) - 0.36, post_z + 0.05 + inward * 0.05)
			var head: Vector3 = Vector3(edge + s * d, _house_roof(d) - 0.1, post_z + 0.05 + inward * 0.3)
			var thick: Vector3 = Vector3(0.025, 0.0, 0.0)
			pen.quad(foot - thick, head - thick, head + thick, foot + thick, Vector3(0.0, 1.0, -inward), skin.timber_dark)
			pen.quad(foot - thick + Vector3(0.0, 0.05, 0.0), head - thick + Vector3(0.0, 0.05, 0.0), head - thick, foot - thick,
				Vector3(-1.0, 0.0, 0.0), skin.timber_dark)
			pen.quad(foot + thick + Vector3(0.0, 0.05, 0.0), head + thick + Vector3(0.0, 0.05, 0.0), head + thick, foot + thick,
				Vector3(1.0, 0.0, 0.0), skin.timber_dark)
	# The plates along the top of each pair of posts.
	_side_box(pen, 0.02, 0.14, _house_roof(0.14) - 0.12, _house_roof(0.14) - 0.02, z0, z1, skin.timber)
	_side_box(pen, 0.63, 0.75, _house_roof(0.75) - 0.12, _house_roof(0.75) - 0.02, z0, z1, skin.timber)
	# The roof: courses of slate stepping down to the eaves, a lead flashing at the top.
	var courses: int = 5
	var lap: float = 0.035
	for course: int in courses:
		var d0: float = HOUSE_REACH * float(course) / float(courses)
		var d1: float = minf(HOUSE_REACH * float(course + 1) / float(courses) + lap, HOUSE_REACH + 0.02)
		var y0: float = _house_roof(d0) + 0.012 * float(courses - course)
		var y1: float = _house_roof(d1) + 0.012 * float(courses - course - 1)
		var tone: Color = slate.darkened(0.04) if course % 2 == 1 else slate
		var base: Array[Vector3] = [Vector3(edge + s * d0, y0, z0 - 0.1), Vector3(edge + s * d1, y1, z0 - 0.1),
			Vector3(edge + s * d1, y1, z1 + 0.1), Vector3(edge + s * d0, y0, z1 + 0.1)]
		pen.slab(base, Vector3(0.0, 0.035, 0.0), tone)
	_side_box(pen, 0.0, 0.07, HOUSE_HIGH + 0.06, HOUSE_HIGH + 0.11, z0 - 0.11, z1 + 0.11, skin.iron.lightened(0.15))
	_shade_rect(shadows, Rect2(minf(edge, edge + s * (HOUSE_REACH + 0.02)), z0 - 0.1, HOUSE_REACH + 0.02, z1 - z0 + 0.2), 1.1, 0.2)
	# The axle's casing from the wheel's inner face to the lot's edge, on the pit's wall.
	_casing(pen, 0.0, 0.16, true)
	# And on across the strip of the lot to the shop's wall, while there is one.
	var gap: float = (edge - mill_wall) * s
	if gap > 0.02:
		_casing(housing, -gap, 0.0, false)
		_shade_rect(shadows, Rect2(minf(edge, mill_wall), z - CASING_HALF, gap, CASING_HALF * 2.0), 0.4, 0.2)


## A stretch of the axle's casing `d0`..`d1` out from the lot's edge: a boarded box with
## a slate cap on a stone footing, and an end board where it leaves the wheel.
func _casing(pen: NeighbourhoodBuildings.Pen, d0: float, d1: float, at_wheel: bool) -> void:
	var z: float = wheel_at.z
	var slate: Color = skin.cottage_roofs[1 % skin.cottage_roofs.size()]
	var foot: float = 0.24 if at_wheel else 0.14
	if not at_wheel:
		_side_box(pen, d0, d1, PLOT_Y, foot, z - CASING_HALF - 0.03, z + CASING_HALF + 0.03, skin.stone)
		_side_box(pen, d0, d1, foot - 0.02, foot, z - CASING_HALF - 0.04, z + CASING_HALF + 0.04, skin.stone_light)
	_side_box(pen, d0, d1, foot, CASING_TOP - 0.04, z - CASING_HALF, z + CASING_HALF, skin.timber_dark)
	# Boards: a lighter batten every so often along it.
	var length: float = d1 - d0
	var battens: int = maxi(1, int(length / 0.32))
	for index: int in battens:
		var d: float = d0 + length * (float(index) + 0.5) / float(battens)
		_side_box(pen, d - 0.02, d + 0.02, foot + 0.02, CASING_TOP - 0.05, z - CASING_HALF - 0.012, z + CASING_HALF + 0.012, skin.timber)
	# The cap: two slate slopes meeting over the axle.
	var a: float = _stream_edge() + stream_side * d0
	var b: float = _stream_edge() + stream_side * d1
	var lo: float = minf(a, b)
	var hi: float = maxf(a, b)
	for side: float in [-1.0, 1.0]:
		var base: Array[Vector3] = [Vector3(lo, CASING_TOP - 0.05, z + side * (CASING_HALF + 0.05)), Vector3(hi, CASING_TOP - 0.05, z + side * (CASING_HALF + 0.05)),
			Vector3(hi, CASING_TOP + 0.07, z), Vector3(lo, CASING_TOP + 0.07, z)]
		pen.slab(base, Vector3(0.0, 0.03, 0.0), slate if side > 0.0 else slate.darkened(0.06))
	if at_wheel:
		# The end board round the axle where it leaves the casing for the wheel.
		_side_box(pen, d1 - 0.02, d1, foot, CASING_TOP - 0.02, z - CASING_HALF - 0.02, z + CASING_HALF + 0.02, skin.timber)

# --- trees and cottages -----------------------------------------------------------

## Oaks along the hedgerows and the lane, a willow by the stream below the bridge and
## another by the mill pond, a few copses far out.
func _trees(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var spots: Array[Vector3] = []
	# Along the lane, in the hedges, now and then.
	for index: int in 22:
		var u: float = _centre_u() + (float(index) - 10.5) * 3.6 + (_r(index, 601) - 0.5) * 2.0
		var side: float = -1.0 if _r(index, 602) < 0.45 else 1.0
		var z: float = (_near_hedge(u) - 0.1) if side < 0.0 else (_far_hedge(u) + 0.15)
		var at: Vector2 = Vector2(u, z)
		if _r(index, 603) < 0.35 or _forecourt_band(at, 2.0) or _on_stream(at, 1.4) or _is_blocked(at, 1.2) \
				or stand.grow(1.4).has_point(at) or gate.grow(1.2).has_point(at):
			continue
		spots.append(Vector3(at.x, at.y, 0.9 + 0.35 * _r(index, 604)))
	# In the field boundaries.
	for entry: Dictionary in _fields:
		var rect: Rect2 = entry["rect"]
		var seed_value: int = entry["seed"]
		if _r(seed_value, 605) < 0.2:
			continue
		var at: Vector2 = Vector2(rect.position.x + rect.size.x * (0.2 + 0.6 * _r(seed_value, 606)), rect.end.y if _r(seed_value, 607) < 0.5 else rect.position.y)
		if _on_stream(at, 1.2) or _on_lane(at, 1.6) or _block_rect.grow(1.0).has_point(at) or at.distance_to(world_centre) > NeighbourhoodGround.WORLD_HALF:
			continue
		spots.append(Vector3(at.x, at.y, 1.0 + 0.4 * _r(seed_value, 608)))
	for index: int in spots.size():
		var spot: Vector3 = spots[index]
		_oak(pen, Vector2(spot.x, spot.y), spot.z, index)
		_tree_shadow(shadows, Vector2(spot.x, spot.y), spot.z)
	# Willows: below the bridge on the far bank, and by the mill pond.
	var below: float = bridge_z + 3.2
	var willow_at: Vector2 = Vector2(stream_u(below) + stream_side * (stream_half(below) + 0.7), below)
	_willow(pen, willow_at, 1.15, 1)
	_tree_shadow(shadows, willow_at, 1.15)
	var pond: float = weir_z - 3.0
	var pond_at: Vector2 = Vector2(stream_u(pond) + stream_side * (stream_half(pond) + 0.8), pond)
	_willow(pen, pond_at, 1.0, 2)
	_tree_shadow(shadows, pond_at, 1.0)


func _forecourt_band(point: Vector2, margin: float) -> bool:
	return point.x > forecourt.position.x - margin and point.x < forecourt.end.x + margin and point.y < lane_z(point.x)


## An oak: a stout trunk and a broad crown of lumpy balls.
func _oak(pen: NeighbourhoodBuildings.Pen, at: Vector2, size: float, seed_value: int) -> void:
	var keep: float = pen.soup.sway
	pen.soup.sway = 1.0
	_oak_body(pen, at, size, seed_value)
	pen.soup.sway = keep


func _oak_body(pen: NeighbourhoodBuildings.Pen, at: Vector2, size: float, seed_value: int) -> void:
	var leaf: Color = skin.leaf_colors[int(_r(seed_value, 611) * 97.0) % skin.leaf_colors.size()]
	var base: Vector3 = Vector3(at.x, FIELD_Y, at.y)
	var soup: NeighbourhoodGround.Soup = pen.soup
	var yaw: float = _r(seed_value, 612) * TAU
	soup.add(NeighbourhoodForest._template("trunk"), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.11 * size, 1.25 * size, 0.11 * size)), base), skin.trunk)
	var balls: Array[Vector4] = [Vector4(0.0, 1.55, 0.0, 0.85), Vector4(0.5, 1.35, 0.15, 0.6), Vector4(-0.42, 1.4, -0.2, 0.62),
		Vector4(0.1, 2.0, -0.1, 0.6), Vector4(-0.15, 1.3, 0.45, 0.5)]
	for index: int in balls.size():
		var ball: Vector4 = balls[index]
		var offset: Vector3 = Basis(Vector3.UP, yaw) * Vector3(ball.x, ball.y, ball.z) * size
		var tone: Color = leaf.darkened(0.08) if index == 0 else (leaf.lightened(0.07) if ball.y > 1.8 else leaf)
		soup.add(NeighbourhoodForest._template("ball"), Transform3D(Basis(Vector3.UP, yaw + float(index)).scaled(Vector3(1.0, 0.8, 1.0) * ball.w * size),
			base + offset), tone)


## A weeping willow: a leaning trunk and long drooping crown, by the water.
func _willow(pen: NeighbourhoodBuildings.Pen, at: Vector2, size: float, seed_value: int) -> void:
	var base: Vector3 = Vector3(at.x, BANK_Y, at.y)
	var soup: NeighbourhoodGround.Soup = pen.soup
	soup.add(NeighbourhoodForest._template("trunk"), Transform3D(Basis(Vector3.BACK, 0.12 * -stream_side).scaled(Vector3(0.09 * size, 1.2 * size, 0.09 * size)), base), skin.trunk)
	for index: int in 7:
		var angle: float = TAU * float(index) / 7.0 + float(seed_value)
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * 0.55 * size
		soup.add(NeighbourhoodForest._template("ball"), Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(0.42, 0.75, 0.42) * size),
			base + out + Vector3(0.0, 0.95 * size, 0.0)), skin.willow.darkened(0.05 * float(index % 3)))
	soup.add(NeighbourhoodForest._template("ball"), Transform3D(Basis.IDENTITY.scaled(Vector3(0.7, 0.55, 0.7) * size), base + Vector3(0.0, 1.45 * size, 0.0)), skin.willow.lightened(0.06))


func _tree_shadow(shadows: NeighbourhoodGround.Soup, at: Vector2, size: float) -> void:
	var centre: Vector2 = at + light_shift * size * 1.1
	var points: Array[Vector2] = []
	for index: int in 9:
		var angle: float = TAU * float(index) / 9.0
		points.append(centre + Vector2(cos(angle) * size * 0.95, sin(angle) * size * 0.7))
	shadows.star(centre, points, SHADOW_Y, Color(0.08, 0.1, 0.06, 0.3))


## A far cottage: whitewashed walls under thatch or slate, a chimney, a door and small
## windows (lit at night), a garden wall in front.
func _cottages(pen: NeighbourhoodBuildings.Pen, windows: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	for index: int in _cottage_spots.size():
		var spot: Vector3 = _cottage_spots[index]
		var at: Vector3 = Vector3(spot.x, FIELD_Y, spot.y)
		var basis: Basis = Basis(Vector3.UP, spot.z)
		var wall: Color = skin.cottage_walls[index % skin.cottage_walls.size()]
		var roof: Color = skin.cottage_roofs[int(_r(index, 701) * 97.0) % skin.cottage_roofs.size()]
		var door: Color = skin.door_colors[index % skin.door_colors.size()]
		var w: float = 1.5 + 0.5 * _r(index, 702)
		var d: float = 1.05
		var h: float = 0.95
		var xf: Transform3D = Transform3D(basis, at)
		pen.xf = xf
		windows.xf = xf
		pen.box(Vector3(-w * 0.5, 0.0, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), wall)
		# The roof: a thick ridge running along the cottage, gables at the ends.
		var eave: float = 0.12
		var ridge: float = h + 0.75
		var thick: Vector3 = Vector3(0.0, 0.07, 0.0)
		for side: float in [-1.0, 1.0]:
			pen.slab([Vector3(-w * 0.5 - eave, h - 0.05, side * (d * 0.5 + eave)), Vector3(w * 0.5 + eave, h - 0.05, side * (d * 0.5 + eave)),
				Vector3(w * 0.5 + eave, ridge, 0.0), Vector3(-w * 0.5 - eave, ridge, 0.0)], thick, roof if side < 0.0 else roof.darkened(0.08))
			pen.tri(Vector3(side * w * 0.5, h, -d * 0.5), Vector3(side * w * 0.5, h, d * 0.5), Vector3(side * w * 0.5, ridge - 0.04, 0.0),
				Vector3(side, 0.0, 0.0), wall)
		pen.box(Vector3(-w * 0.5 - eave, ridge, -0.05), Vector3(w * 0.5 + eave, ridge + 0.06, 0.05), roof.darkened(0.15))
		var chimney: float = w * 0.5 - 0.25
		pen.box(Vector3(chimney - 0.1, h + 0.3, -0.12), Vector3(chimney + 0.1, ridge + 0.25, 0.12), skin.stone)
		pen.box(Vector3(chimney - 0.12, ridge + 0.25, -0.14), Vector3(chimney + 0.12, ridge + 0.29, 0.14), skin.stone_dark)
		# The door and windows on the front (+z).
		pen.box(Vector3(-0.13, 0.0, d * 0.5), Vector3(0.13, 0.5, d * 0.5 + 0.02), door)
		for x: float in [-w * 0.5 + 0.32, w * 0.5 - 0.32]:
			pen.box(Vector3(x - 0.15, 0.36, d * 0.5), Vector3(x + 0.15, 0.66, d * 0.5 + 0.015), wall.darkened(0.25))
			windows.box(Vector3(x - 0.12, 0.39, d * 0.5 + 0.012), Vector3(x + 0.12, 0.63, d * 0.5 + 0.02), Color.WHITE)
			pen.box(Vector3(x - 0.01, 0.39, d * 0.5 + 0.02), Vector3(x + 0.01, 0.63, d * 0.5 + 0.024), wall)
		for x: float in [-w * 0.25, w * 0.25]:
			windows.box(Vector3(x - 0.11, 0.38, -d * 0.5 - 0.02), Vector3(x + 0.11, 0.62, -d * 0.5 - 0.012), Color.WHITE)
		# A low garden wall in front, with a gap at the path.
		pen.xf = Transform3D.IDENTITY
		windows.xf = Transform3D.IDENTITY
		for side: float in [-1.0, 1.0]:
			var a: Vector3 = xf * Vector3(side * 0.28, 0.0, d * 0.5 + 1.0)
			var b: Vector3 = xf * Vector3(side * (w * 0.5 + 0.5), 0.0, d * 0.5 + 1.0)
			_wall_piece(pen, shadows, Vector2(a.x, a.z), Vector2(b.x, b.z), index * 11 + int(side))
		_add_light(xf * Vector3(0.27, 0.62, d * 0.5 + 0.08), 0.32, false)
		_add_light(xf * Vector3(-w * 0.5 + 0.32, 0.5, d * 0.5 + 0.1), 0.45, false)
		_add_light(xf * Vector3(w * 0.5 - 0.32, 0.5, d * 0.5 + 0.1), 0.45, false)
		var corners: Array[Vector2] = []
		for corner: Vector3 in [Vector3(-w * 0.5, 0.0, -d * 0.5), Vector3(w * 0.5, 0.0, -d * 0.5), Vector3(w * 0.5, 0.0, d * 0.5), Vector3(-w * 0.5, 0.0, d * 0.5)]:
			var world: Vector3 = xf * corner
			corners.append(Vector2(world.x, world.z))
		var push: Vector2 = light_shift * 1.2
		var hull_points: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in corners:
			hull_points.append(corner)
			hull_points.append(corner + push)
		var hull: PackedVector2Array = Geometry2D.convex_hull(hull_points)
		var ring: Array[Vector2] = []
		for point: int in hull.size() - 1:
			ring.append(hull[point])
		shadows.star(Vector2(at.x, at.z) + push * 0.5, ring, SHADOW_Y, Color(0.08, 0.08, 0.05, 0.3))


# --- the plots' looks -----------------------------------------------------------

## A plot's three looks. Meadow: long grass and wild flowers; mown into rows of hay
## (with round bales off the lot's own land); cleared to a striped lawn. Corn: a soft,
## swaying canopy of ripe wheat on brown earth; cut to stubble (with straw bales off the lot's land);
## cleared to ploughed furrows. A land plot's crop keeps off the first lease and the
## door's approach, and its mown and cleared looks lie flat, so nothing stands above
## the ground where the player builds.
func _build_plot(entry: Plot, meshes: Dictionary) -> void:
	var grown: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var grown_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var mown: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var mown_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var cleared: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var cleared_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var salt_id: int = String(entry.id).hash() & 0xffff
	if entry.crop == &"corn":
		_corn(entry, salt_id, grown, grown_shade)
		_stubble(entry, salt_id, mown, mown_shade)
		_ploughed(entry, salt_id, cleared)
	else:
		_meadow(entry, salt_id, grown, grown_shade)
		_hay(entry, salt_id, mown, mown_shade)
		_lawn(entry, salt_id, cleared)
	meshes["%s:Grown" % entry.id] = _mesh_of(grown.soup)
	meshes["%s:Grown:shade" % entry.id] = _mesh_of(grown_shade)
	meshes["%s:Mown" % entry.id] = _mesh_of(mown.soup)
	meshes["%s:Mown:shade" % entry.id] = _mesh_of(mown_shade)
	meshes["%s:Cleared" % entry.id] = _mesh_of(cleared.soup)
	meshes["%s:Cleared:shade" % entry.id] = _mesh_of(cleared_shade)


## True where a plot may stand something up: off the door's approach and the yard's
## pieces, and (on a land plot) clear of the first lease.
func _plot_free(entry: Plot, point: Vector2, margin: float) -> bool:
	if _is_blocked(point, margin):
		return false
	if entry.is_land and first_lease.grow(margin).has_point(point):
		return false
	if not entry.is_land and _lot().grow(margin).has_point(point):
		return false
	return true


## The plot's ground with a ragged outer edge (not along the lot's side).
func _plot_ground(entry: Plot, pen: NeighbourhoodBuildings.Pen, colour: Color, salt_id: int) -> void:
	var r: Rect2 = entry.rect
	if entry.is_land:
		# Out over the gap to the plot round the lot, so the two read as one field.
		var lot: Rect2 = _lot()
		var reach: float = PLOT_GAP + 0.02
		r = r.grow_individual(reach if r.position.x <= lot.position.x + 0.01 else 0.0, reach if r.position.y <= lot.position.y + 0.01 else 0.0,
			reach if r.end.x >= lot.end.x - 0.01 else 0.0, 0.0)
		pen.flat(r.position.x, r.position.y, r.end.x, r.end.y, PLOT_Y, colour)
		return
	pen.flat(r.position.x, r.position.y, r.end.x, r.end.y, PLOT_Y, colour)
	var steps: int = int((r.size.x + r.size.y) * 2.0 / 0.6)
	var perimeter: float = (r.size.x + r.size.y) * 2.0
	for index: int in steps:
		var t: float = float(index) / float(steps) * perimeter
		var at: Vector2
		if t < r.size.x:
			at = r.position + Vector2(t, 0.0)
		elif t < r.size.x + r.size.y:
			at = r.position + Vector2(r.size.x, t - r.size.x)
		elif t < r.size.x * 2.0 + r.size.y:
			at = r.end - Vector2(t - r.size.x - r.size.y, 0.0)
		else:
			at = r.end - Vector2(r.size.x, t - r.size.x * 2.0 - r.size.y)
		if _lot().grow(PLOT_GAP + 0.05).has_point(at):
			continue
		var size: float = 0.22 + _r(salt_id + index, 801) * 0.2
		_blob(pen, at, size, size * 0.8, _r(salt_id + index, 802) * PI, 6, PLOT_Y - 0.001, colour)


## Wild flowers on a short stalk: a small head in one of the skin's colours.
func _flower(pen: NeighbourhoodBuildings.Pen, at: Vector3, height: float, colour: Color, seed_value: int) -> void:
	pen.tri(at + Vector3(-0.008, 0.0, 0.0), at + Vector3(0.008, 0.0, 0.0), at + Vector3(0.0, height, 0.0), Vector3.BACK, skin.grass_dark)
	# The head: a little four-petalled cross, a lit top and a shaded rim.
	var top: Vector3 = at + Vector3.UP * (height + 0.012)
	var spin: float = float(seed_value % 7) * 0.4
	var a: Vector3 = Vector3(cos(spin), 0.0, sin(spin)) * 0.032
	var b: Vector3 = Vector3(-sin(spin), 0.0, cos(spin)) * 0.032
	pen.quad(top + a, top + b, top - a, top - b, Vector3.UP, colour)
	pen.tri(top + a - Vector3.UP * 0.014, top + b, top - a, Vector3(0.0, 0.2, 1.0), colour.darkened(0.2))


func _meadow(entry: Plot, salt_id: int, pen: NeighbourhoodBuildings.Pen, _shade: NeighbourhoodGround.Soup) -> void:
	_plot_ground(entry, pen, skin.meadow.darkened(0.05), salt_id)
	var r: Rect2 = entry.rect
	var cell: float = 0.34
	var columns: int = maxi(1, int(r.size.x / cell))
	var rows: int = maxi(1, int(r.size.y / cell))
	for ix: int in columns:
		for iz: int in rows:
			var seed_value: int = salt_id * 5 + ix * 211 + iz
			var at: Vector2 = r.position + Vector2((float(ix) + 0.15 + _r(seed_value, 811) * 0.7) * r.size.x / float(columns),
				(float(iz) + 0.15 + _r(seed_value, 812) * 0.7) * r.size.y / float(rows))
			if not _plot_free(entry, at, 0.12):
				continue
			var p: Vector3 = Vector3(at.x, PLOT_Y, at.y)
			var roll: float = _r(seed_value, 813)
			var tall: float = 0.2 + 0.12 * _r(seed_value, 814)
			var tone: Color = skin.meadow if roll < 0.5 else skin.meadow.lerp(skin.grass_dark, 0.4)
			_tuft(pen, p, tall, tone, seed_value)
			if roll > 0.62:
				var colour: Color = skin.flower_colors[int(_r(seed_value, 815) * 97.0) % skin.flower_colors.size()]
				for bloom: int in 2 + int(_r(seed_value, 816) * 2.0):
					var off: Vector3 = Vector3((_r(seed_value + bloom, 817) - 0.5) * 0.24, 0.0, (_r(seed_value + bloom, 818) - 0.5) * 0.24)
					_flower(pen, p + off, tall * (0.85 + 0.35 * _r(seed_value + bloom, 819)), colour, seed_value + bloom)
			elif roll > 0.5:
				pen.lump(p + Vector3(0.05, tall + 0.02, 0.0), 0.02, 0.035, 0.02, 0.0, skin.meadow_seed, skin.meadow_seed.darkened(0.2))
	# Drifts of colour in the grass.
	for index: int in int(r.get_area() / 3.5) + 2:
		var at: Vector2 = r.position + Vector2(_r(salt_id + index, 821), _r(salt_id + index, 822)) * r.size
		var colour: Color = skin.flower_colors[(salt_id + index) % skin.flower_colors.size()]
		_blob(pen, at, 0.25 + 0.2 * _r(salt_id + index, 823), 0.2, _r(salt_id + index, 824) * PI, 7, PLOT_TOP, skin.meadow.darkened(0.05).lerp(colour, 0.1))


## The meadow mown: short pale grass in long rows of hay; off the lot's land, round bales.
func _hay(entry: Plot, salt_id: int, pen: NeighbourhoodBuildings.Pen, shade: NeighbourhoodGround.Soup) -> void:
	_plot_ground(entry, pen, skin.grass_light, salt_id)
	var r: Rect2 = entry.rect
	var along_z: bool = r.size.y >= r.size.x
	var span: float = r.size.x if along_z else r.size.y
	var count: int = maxi(1, int(span / 0.7))
	for index: int in count:
		var t: float = (float(index) + 0.5) * span / float(count)
		if along_z:
			pen.flat(r.position.x + t - 0.14, r.position.y + 0.15, r.position.x + t + 0.14, r.end.y - 0.15, PLOT_TOP, skin.hay)
			pen.flat(r.position.x + t - 0.08, r.position.y + 0.2, r.position.x + t + 0.08, r.end.y - 0.2, PLOT_TOP + 0.002, skin.hay.lightened(0.08))
		else:
			pen.flat(r.position.x + 0.15, r.position.y + t - 0.14, r.end.x - 0.15, r.position.y + t + 0.14, PLOT_TOP, skin.hay)
			pen.flat(r.position.x + 0.2, r.position.y + t - 0.08, r.end.x - 0.2, r.position.y + t + 0.08, PLOT_TOP + 0.002, skin.hay.lightened(0.08))
	if entry.is_land:
		return
	for index: int in 3:
		var at: Vector2 = r.position + Vector2(0.25 + 0.5 * _r(salt_id + index, 831), 0.2 + 0.6 * _r(salt_id + index, 832)) * r.size
		if not _plot_free(entry, at, 0.4):
			continue
		var axis: Vector3 = Vector3(cos(_r(salt_id + index, 833) * PI), 0.0, sin(_r(salt_id + index, 833) * PI))
		_roll(pen, Vector3(at.x, PLOT_Y + 0.21, at.y), axis, 0.21, 0.36, skin.hay, skin.hay.lightened(0.1))
		_shade_disc(shade, at + light_shift * 0.25, 0.28, 0.28)


## The meadow cleared: a mown lawn in two-tone stripes.
func _lawn(entry: Plot, salt_id: int, pen: NeighbourhoodBuildings.Pen) -> void:
	_plot_ground(entry, pen, skin.grass, salt_id)
	var r: Rect2 = entry.rect
	var count: int = maxi(1, int(r.size.x / 0.5))
	for index: int in count:
		if index % 2 == 1:
			continue
		var x0: float = r.position.x + float(index) * r.size.x / float(count)
		pen.flat(x0, r.position.y + 0.05, x0 + r.size.x / float(count), r.end.y - 0.05, PLOT_TOP, skin.grass_light)


## Ripe wheat (#619): one soft canopy over the earth instead of rows, rolling gently in
## height and drifting between warmer and paler gold in broad patches, with ears pricking
## up through it and darker stalks at its edges; poppies along the front. The canopy's
## heights and tones come from the street's own coordinates, so neighbouring plots meet
## seamlessly. Vertex alpha marks what sways on the display clock (the wheat shader).
func _corn(entry: Plot, salt_id: int, pen: NeighbourhoodBuildings.Pen, shade: NeighbourhoodGround.Soup) -> void:
	_plot_ground(entry, pen, skin.soil, salt_id)
	var r: Rect2 = entry.rect.grow(-0.08)
	var columns: int = maxi(1, ceili(r.size.x / WHEAT_CELL))
	var rows: int = maxi(1, ceili(r.size.y / WHEAT_CELL))
	var step: Vector2 = Vector2(r.size.x / float(columns), r.size.y / float(rows))
	# Which cells stand: all four corners clear of the yard, the lot or the first lease.
	var standing: Dictionary[Vector2i, bool] = {}
	for ix: int in columns:
		for iz: int in rows:
			var lo: Vector2 = r.position + Vector2(float(ix) * step.x, float(iz) * step.y)
			var clear: bool = true
			for corner: Vector2 in [lo, lo + Vector2(step.x, 0.0), lo + step, lo + Vector2(0.0, step.y)]:
				if not _plot_free(entry, corner, 0.06):
					clear = false
					break
			if clear:
				standing[Vector2i(ix, iz)] = true
	var soup: NeighbourhoodGround.Soup = pen.soup
	for cell: Vector2i in standing:
		var lo: Vector2 = r.position + Vector2(float(cell.x) * step.x, float(cell.y) * step.y)
		var corners: Array[Vector2] = [lo, lo + Vector2(step.x, 0.0), lo + step, lo + Vector2(0.0, step.y)]
		var tops: Array[Vector3] = []
		var tones: Array[Color] = []
		var normals: Array[Vector3] = []
		for corner: Vector2 in corners:
			tops.append(Vector3(corner.x, _wheat_height(corner), corner.y))
			tones.append(_wheat_tone(corner))
			normals.append(_wheat_normal(corner))
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for index: int in tri:
				soup.positions.append(tops[index])
				soup.normals.append(normals[index])
				soup.colors.append(Color(tones[index], 0.0))
		# The canopy's sides where no wheat stands next to it: stalks, darker at the foot.
		var neighbours: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		for side: int in 4:
			if standing.has(cell + neighbours[side]):
				continue
			var a: int = side
			var b: int = (side + 1) % 4
			var out: Vector3 = Vector3(float(neighbours[side].x), 0.25, float(neighbours[side].y)).normalized()
			var foot_a: Vector3 = Vector3(tops[a].x, PLOT_Y, tops[a].z)
			var foot_b: Vector3 = Vector3(tops[b].x, PLOT_Y, tops[b].z)
			var low: Color = Color(skin.wheat.darkened(0.3), 1.0)
			for point: Array in [[foot_a, low], [foot_b, low], [tops[b], Color(tones[b].darkened(0.1), 0.0)],
					[foot_a, low], [tops[b], Color(tones[b].darkened(0.1), 0.0)], [tops[a], Color(tones[a].darkened(0.1), 0.0)]]:
				soup.positions.append(point[0])
				soup.normals.append(out)
				soup.colors.append(point[1])
			# A bristly fringe: stalks standing just proud of the side, their ears over the top.
			var along: Vector3 = (tops[b] - tops[a]).normalized() * 0.014
			var push: Vector3 = Vector3(float(neighbours[side].x), 0.0, float(neighbours[side].y)) * 0.015
			for stalk: int in 3:
				var t: float = (float(stalk) + 0.2 + 0.6 * _r(int(floorf(lo.x * 13.0)) + side * 31 + stalk, int(floorf(lo.y * 13.0)) + 848)) / 3.0
				var top: Vector3 = tops[a].lerp(tops[b], t) + push
				var tall: float = 0.06 + 0.06 * _r(int(floorf(top.x * 17.0)) + stalk, int(floorf(top.z * 17.0)) + 849)
				var base: Vector3 = Vector3(top.x, PLOT_Y + 0.08, top.z)
				soup.tri(base - along, base + along, top + Vector3.UP * tall * 0.4, out, Color(skin.wheat.darkened(0.18), 0.5))
				var tip: Vector3 = top + Vector3(0.0, tall, 0.0) + push
				for face: Array in [[top - along * 1.6, skin.wheat_ear.lightened(0.18)], [top + along * 1.6, skin.wheat_ear.lightened(0.06)]]:
					for point: Vector3 in [face[0], top + Vector3.UP * tall * 0.45 + push * 0.5, tip]:
						soup.positions.append(point)
						soup.normals.append((out + Vector3.UP * 2.0).normalized())
						soup.colors.append(Color(face[1] as Color, 0.0))
		# Ears pricking up through the canopy, leaning a little with the wind.
		var seed_value: int = salt_id * 7 + int(floorf(lo.x * 3.3)) * 7919 + int(floorf(lo.y * 3.3)) * 131
		for ear: int in 4:
			var at: Vector2 = lo + Vector2((float(ear % 2) + 0.15 + 0.7 * _r(seed_value + ear, 841)) * 0.5,
				(float(ear / 2) + 0.15 + 0.7 * _r(seed_value + ear, 842)) * 0.5) * step
			var base: float = _wheat_height(at) - 0.04
			var lift: float = 0.1 + 0.07 * _r(seed_value + ear, 843)
			var spin: float = _r(seed_value + ear, 844) * PI
			var across: Vector3 = Vector3(cos(spin), 0.0, sin(spin)) * 0.04
			var foot: Vector3 = Vector3(at.x, base, at.y)
			var tip: Vector3 = foot + Vector3(0.025, lift, 0.01)
			var middle: Vector3 = foot + Vector3(0.012, lift * 0.45, 0.0) + Vector3(-across.z, 0.0, across.x) * 0.6
			var tone: Color = skin.wheat_ear.lightened(0.1).lerp(skin.wheat_ear.lightened(0.28), _r(seed_value + ear, 845))
			# A lit face and a softer shaded one, lit as the canopy is (mostly from above), so
			# the ears catch the light like a fine grain instead of reading as dark specks.
			for face: Array in [[foot - across, Vector3(-0.35, 1.0, 0.25), tone], [foot + across, Vector3(0.3, 1.0, -0.2), tone.darkened(0.06)]]:
				for point: Vector3 in [face[0], middle, tip]:
					soup.positions.append(point)
					soup.normals.append((face[1] as Vector3).normalized())
					soup.colors.append(Color(face[2] as Color, 0.0))
	if not entry.is_land:
		var front: float = entry.rect.end.y
		for index: int in int(r.size.x / 0.6):
			var seed_value: int = salt_id * 3 + index
			if _r(seed_value, 846) > 0.3:
				continue
			var u: float = r.position.x + (float(index) + _r(seed_value, 847)) * 0.6
			if _plot_free(entry, Vector2(u, front - 0.02), 0.1):
				_flower(pen, Vector3(u, PLOT_Y, front - 0.02), 0.32, skin.flower_colors[0], seed_value)
		_shade_line(shade, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), 0.02, 0.45, 0.2)


## The canopy's top (local y) at a point: gentle swells and a fine tousle, the same at
## any plot so neighbouring plots join.
func _wheat_height(at: Vector2) -> float:
	return PLOT_Y + WHEAT_HEIGHT + 0.03 * sin(at.x * 0.9 + at.y * 0.35 + 0.4) + 0.02 * sin(at.y * 1.7 - at.x * 0.6 + 1.1) \
		+ 0.016 * sin(at.x * 7.3 + at.y * 5.1) * sin(at.y * 6.7 - at.x * 2.9)


## The canopy's slope-lit normal at a point.
func _wheat_normal(at: Vector2) -> Vector3:
	var e: float = 0.05
	var dx: float = (_wheat_height(at + Vector2(e, 0.0)) - _wheat_height(at - Vector2(e, 0.0))) / (2.0 * e)
	var dz: float = (_wheat_height(at + Vector2(0.0, e)) - _wheat_height(at - Vector2(0.0, e))) / (2.0 * e)
	return Vector3(-dx * 2.5, 1.0, -dz * 2.5).normalized()


## The wheat's colour at a point: broad soft patches between the skin's wheat, a warmer
## deeper gold and its paler ears, and a faint fine grain.
func _wheat_tone(at: Vector2) -> Color:
	var broad: float = 0.5 + 0.3 * sin(at.x * 0.37 + 0.8) * sin(at.y * 0.53 + 2.0) + 0.2 * sin((at.x - at.y) * 0.21 + 0.3)
	var fine: float = 0.5 + 0.5 * sin(at.x * 3.7 + at.y * 2.9) * sin(at.y * 4.3 - at.x * 1.3)
	var tone: Color = skin.wheat.darkened(0.07).lerp(skin.wheat.lerp(skin.wheat_ear, 0.4), clampf(broad, 0.0, 1.0))
	return tone.lerp(skin.wheat.darkened(0.04), 0.3 * fine)


## The wheat cut: stubble lines on the earth; off the lot's land, small straw bales.
func _stubble(entry: Plot, salt_id: int, pen: NeighbourhoodBuildings.Pen, shade: NeighbourhoodGround.Soup) -> void:
	_plot_ground(entry, pen, skin.soil.lerp(skin.stubble, 0.45), salt_id)
	var r: Rect2 = entry.rect
	var count: int = maxi(1, int(r.size.y / 0.2))
	for index: int in count:
		var z: float = r.position.y + (float(index) + 0.5) * r.size.y / float(count)
		pen.flat(r.position.x + 0.08, z - 0.045, r.end.x - 0.08, z + 0.045, PLOT_TOP, skin.stubble if index % 2 == 0 else skin.stubble.darkened(0.06))
	if entry.is_land:
		return
	for index: int in 7:
		var at: Vector2 = r.position + Vector2(0.12 + 0.76 * _r(salt_id + index, 851), 0.2 + 0.6 * _r(salt_id + index, 852)) * r.size
		if not _plot_free(entry, at, 0.3):
			continue
		var yaw: float = _r(salt_id + index, 853) * 0.6 - 0.3
		var basis: Basis = Basis(Vector3.UP, yaw)
		var lo: Vector3 = Vector3(-0.17, 0.0, -0.1)
		var hi: Vector3 = Vector3(0.17, 0.17, 0.1)
		pen.xf = Transform3D(basis, Vector3(at.x, PLOT_Y, at.y))
		pen.box(lo, hi, skin.hay.lightened(0.04))
		pen.box(Vector3(-0.06, 0.0, -0.105), Vector3(-0.045, 0.172, 0.105), skin.hay.darkened(0.12))
		pen.box(Vector3(0.045, 0.0, -0.105), Vector3(0.06, 0.172, 0.105), skin.hay.darkened(0.12))
		if index % 3 == 0:
			pen.box(lo + Vector3(0.04, 0.17, 0.0), hi + Vector3(0.04, 0.17, 0.0), skin.hay.lightened(0.02))
		pen.xf = Transform3D.IDENTITY
		_shade_disc(shade, at + light_shift * 0.2, 0.22, 0.26)


## Ploughed: furrows of turned earth in two tones.
func _ploughed(entry: Plot, salt_id: int, pen: NeighbourhoodBuildings.Pen) -> void:
	_plot_ground(entry, pen, skin.soil, salt_id)
	var r: Rect2 = entry.rect
	var count: int = maxi(1, int(r.size.y / 0.24))
	for index: int in count:
		if index % 2 == 1:
			continue
		var z: float = r.position.y + (float(index) + 0.5) * r.size.y / float(count)
		pen.flat(r.position.x + 0.05, z - 0.07, r.end.x - 0.05, z + 0.07, PLOT_TOP, skin.soil_dark)


# --- lights -------------------------------------------------------------------------

## One quad per light, all four corners at its centre; the glow shader spreads them.
func _sprites(points: Array[Vector3], sizes: Array[float]) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var uv2s: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for index: int in points.size():
		for corner: Vector2 in corners:
			vertices.append(points[index])
			normals.append(Vector3.UP)
			uvs.append(corner)
			uv2s.append(Vector2(sizes[index], float(index) * 0.618 + 0.13))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var mesh: ArrayMesh = ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Soft warm pools of light on the ground under the lanterns (additive, faded in at night).
func _pool_mesh() -> ArrayMesh:
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var rings: int = 5
	for spot: Vector3 in _pool_spots:
		var radius: float = spot.z
		for index: int in 12:
			var a0: float = TAU * float(index) / 12.0
			var a1: float = TAU * float(index + 1) / 12.0
			for ring: int in rings:
				var r0: float = radius * float(ring) / float(rings)
				var r1: float = radius * float(ring + 1) / float(rings)
				var k0: float = pow(1.0 - float(ring) / float(rings), 1.7) * 0.55
				var k1: float = pow(1.0 - float(ring + 1) / float(rings), 1.7) * 0.55
				var c0: Color = Color(skin.lamp_glow, k0)
				var c1: Color = Color(skin.lamp_glow, k1)
				var p: Array[Vector3] = [Vector3(spot.x + cos(a0) * r0, SHADOW_Y + 0.004, spot.y + sin(a0) * r0),
					Vector3(spot.x + cos(a1) * r0, SHADOW_Y + 0.004, spot.y + sin(a1) * r0),
					Vector3(spot.x + cos(a1) * r1, SHADOW_Y + 0.004, spot.y + sin(a1) * r1),
					Vector3(spot.x + cos(a0) * r1, SHADOW_Y + 0.004, spot.y + sin(a0) * r1)]
				var colours: Array[Color] = [c0, c0, c1, c1]
				for corner: int in [0, 1, 2, 0, 2, 3]:
					soup.positions.append(p[corner])
					soup.normals.append(Vector3.UP)
					soup.colors.append(colours[corner])
	return _mesh_of(soup)


# --- the waterwheel ---------------------------------------------------------------

## The wheel: two rims on eight spokes each, sixteen paddles between them, a hub on an
## axle into the mill's wall. Its own node (`Wheel`) turns about the axle.
func _build_wheel() -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "Waterwheel"
	holder.position = wheel_at
	root.add_child(holder)
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var half: float = WHEEL_WIDTH * 0.5
	var radius: float = WHEEL_RADIUS
	var sides: int = 16
	var wood: Color = skin.timber
	var dark: Color = skin.timber_dark
	for face: float in [-half, half]:
		for index: int in sides:
			var a0: float = TAU * float(index) / float(sides)
			var a1: float = TAU * float(index + 1) / float(sides)
			var o0: Vector3 = Vector3(0.0, sin(a0), cos(a0))
			var o1: Vector3 = Vector3(0.0, sin(a1), cos(a1))
			var x0: float = face - 0.025
			var x1: float = face + 0.025
			# The rim: a flat band, its outer and inner faces and its two sides.
			pen.quad(Vector3(x0, 0.0, 0.0) + o0 * radius, Vector3(x0, 0.0, 0.0) + o1 * radius, Vector3(x1, 0.0, 0.0) + o1 * radius,
				Vector3(x1, 0.0, 0.0) + o0 * radius, (o0 + o1) * 0.5, dark)
			for x: float in [x0, x1]:
				pen.quad(Vector3(x, 0.0, 0.0) + o0 * radius, Vector3(x, 0.0, 0.0) + o1 * radius, Vector3(x, 0.0, 0.0) + o1 * radius * 0.86,
					Vector3(x, 0.0, 0.0) + o0 * radius * 0.86, Vector3(signf(x), 0.0, 0.0), wood)
		for index: int in 8:
			var angle: float = TAU * float(index) / 8.0 + 0.2
			var out: Vector3 = Vector3(0.0, sin(angle), cos(angle))
			var across: Vector3 = Vector3(0.0, cos(angle), -sin(angle)) * 0.022
			for x: float in [face - 0.018, face + 0.018]:
				pen.quad(Vector3(x, 0.0, 0.0) - across, Vector3(x, 0.0, 0.0) + out * radius * 0.88 - across,
					Vector3(x, 0.0, 0.0) + out * radius * 0.88 + across, Vector3(x, 0.0, 0.0) + across, Vector3(signf(x), 0.0, 0.0), wood)
	# Paddles (floats) between the rims, each tilted a little.
	for index: int in sides:
		var angle: float = TAU * (float(index) + 0.5) / float(sides)
		var out: Vector3 = Vector3(0.0, sin(angle), cos(angle))
		var tangent: Vector3 = Vector3(0.0, cos(angle), -sin(angle))
		var inner: Vector3 = out * radius * 0.7
		var outer: Vector3 = out * radius * 1.02 + tangent * 0.04
		for side: float in [-1.0, 1.0]:
			var thick: Vector3 = tangent * 0.012 * side
			pen.quad(Vector3(-half, 0.0, 0.0) + inner + thick, Vector3(half, 0.0, 0.0) + inner + thick, Vector3(half, 0.0, 0.0) + outer + thick,
				Vector3(-half, 0.0, 0.0) + outer + thick, tangent * side, wood.lightened(0.05) if side > 0.0 else dark)
		pen.quad(Vector3(-half, 0.0, 0.0) + outer - tangent * 0.012, Vector3(half, 0.0, 0.0) + outer - tangent * 0.012,
			Vector3(half, 0.0, 0.0) + outer + tangent * 0.012, Vector3(-half, 0.0, 0.0) + outer + tangent * 0.012, out, dark)
	# The hub.
	pen.box(Vector3(-half - 0.04, -0.08, -0.08), Vector3(half + 0.04, 0.08, 0.08), skin.iron)
	var turning: MeshInstance3D = _instance("Wheel", pen.soup.to_mesh(), _material)
	holder.add_child(turning)
	wheel = turning
	# The axle (fixed): from the pier on the outside to the mill's wall.
	var axle: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var wall: float = _stream_edge() + stream_side * 0.15 - wheel_at.x
	var out_end: float = stream_side * (half + 0.16)
	axle.box(Vector3(minf(wall, out_end), -0.035, -0.035), Vector3(maxf(wall, out_end), 0.035, 0.035), skin.iron.darkened(0.2))
	# A damp, darker patch on the wall's plinth behind the wheel.
	holder.add_child(_instance("Axle", axle.soup.to_mesh(), _material))


## The wheel's angle (radians about the axle) at the street clock's `seconds`: its
## bottom moves downstream with the water.
func wheel_angle(seconds: float) -> float:
	return -fposmod(seconds * WHEEL_SPEED, TAU)


# --- the tractor -------------------------------------------------------------------

## A little tractor towing a trailer of hay bales: body, bonnet, cab frame and roof,
## big back wheels and small front ones (their own nodes, they turn), an exhaust stack
## and headlamps (glowing at dusk). Built facing +z; `tractor_transform` drives it.
func _build_tractor() -> void:
	tractor = Node3D.new()
	tractor.name = "Tractor"
	root.add_child(tractor)
	_tractor_wheels.clear()
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var paint: Color = skin.tractor
	var trim: Color = skin.tractor_trim
	# The chassis and bonnet.
	pen.box(Vector3(-0.17, 0.2, -0.32), Vector3(0.17, 0.3, 0.42), trim.darkened(0.2))
	pen.box(Vector3(-0.15, 0.3, 0.02), Vector3(0.15, 0.5, 0.46), paint)
	pen.box(Vector3(-0.16, 0.5, 0.0), Vector3(0.16, 0.53, 0.46), paint.lightened(0.08))
	pen.box(Vector3(-0.12, 0.3, 0.46), Vector3(0.12, 0.47, 0.48), trim)
	for x: float in [-0.155, 0.155]:
		pen.box(Vector3(x - 0.004, 0.34, 0.08), Vector3(x + 0.004, 0.46, 0.4), trim.darkened(0.1))
	# The seat and the cab: four posts and a roof.
	pen.box(Vector3(-0.2, 0.3, -0.36), Vector3(0.2, 0.42, 0.02), paint.darkened(0.08))
	pen.box(Vector3(-0.1, 0.42, -0.26), Vector3(0.1, 0.47, -0.1), skin.tyre.lightened(0.15))
	pen.box(Vector3(-0.1, 0.47, -0.3), Vector3(0.1, 0.65, -0.26), skin.tyre.lightened(0.15))
	pen.box(Vector3(-0.02, 0.5, 0.0), Vector3(0.02, 0.62, 0.04), trim)
	pen.box(Vector3(-0.08, 0.62, -0.02), Vector3(0.08, 0.64, 0.06), skin.tyre)
	for x: float in [-0.19, 0.17]:
		for z: float in [-0.36, -0.02]:
			pen.box(Vector3(x, 0.42, z), Vector3(x + 0.02, 0.95, z + 0.02), trim.darkened(0.2))
	pen.box(Vector3(-0.22, 0.95, -0.4), Vector3(0.22, 0.99, 0.03), paint)
	# The exhaust stack and the headlamps.
	pen.box(Vector3(0.07, 0.53, 0.3), Vector3(0.1, 0.78, 0.33), skin.iron.darkened(0.3))
	for x: float in [-0.1, 0.1]:
		pen.box(Vector3(x - 0.03, 0.42, 0.48), Vector3(x + 0.03, 0.47, 0.5), skin.lamp_glow.lerp(Color.WHITE, 0.5))
	# The drawbar and trailer with three bales.
	pen.box(Vector3(-0.02, 0.18, -0.62), Vector3(0.02, 0.21, -0.32), trim.darkened(0.3))
	pen.box(Vector3(-0.22, 0.2, -1.32), Vector3(0.22, 0.24, -0.62), skin.timber)
	for x: float in [-0.22, 0.2]:
		pen.box(Vector3(x, 0.24, -1.32), Vector3(x + 0.02, 0.34, -0.62), skin.timber_dark)
	pen.box(Vector3(-0.22, 0.24, -1.34), Vector3(0.22, 0.34, -1.32), skin.timber_dark)
	for index: int in 3:
		var z: float = -1.2 + float(index) * 0.22
		pen.box(Vector3(-0.17, 0.24, z - 0.09), Vector3(0.17, 0.38, z + 0.09), skin.hay)
		pen.box(Vector3(-0.17, 0.38, z - 0.09), Vector3(0.17, 0.381, z + 0.09), skin.hay.lightened(0.08))
	pen.box(Vector3(-0.15, 0.38, -1.08), Vector3(0.15, 0.51, -0.9), skin.hay.lightened(0.04))
	tractor.add_child(_instance("Body", pen.soup.to_mesh(), _material))
	# Wheels: big at the back, small at the front, and two on the trailer.
	var specs: Array[Vector4] = [Vector4(-0.25, 0.27, -0.18, 0.08), Vector4(0.25, 0.27, -0.18, 0.08),
		Vector4(-0.2, 0.15, 0.33, 0.06), Vector4(0.2, 0.15, 0.33, 0.06), Vector4(-0.26, 0.14, -1.0, 0.05), Vector4(0.26, 0.14, -1.0, 0.05)]
	for index: int in specs.size():
		var spec: Vector4 = specs[index]
		var wheel_pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		_tyre(wheel_pen, spec.y, spec.w, index < 4)
		var node: MeshInstance3D = _instance("Wheel%d" % index, wheel_pen.soup.to_mesh(), _material)
		node.position = Vector3(spec.x, spec.y, spec.z)
		node.set_meta(&"radius", spec.y)
		tractor.add_child(node)
		_tractor_wheels.append(node)
	var lamps: Array[Vector3] = [Vector3(-0.1, 0.445, 0.53), Vector3(0.1, 0.445, 0.53)]
	var glow: MeshInstance3D = _instance("Headlamps", _sprites(lamps, [0.36, 0.36] as Array[float]), _headlamp_material)
	glow.extra_cull_margin = 0.5
	tractor.add_child(glow)
	var shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	_shade_rect(shade, Rect2(-0.24, -1.32, 0.48, 1.8), 0.0, 0.32)
	var shadow: MeshInstance3D = _instance("Shadow", _mesh_of(shade), _shadow_material)
	shadow.position = Vector3(0.0, SHADOW_Y - WALK_Y, 0.0)
	tractor.add_child(shadow)


## A tyre with chunky treads facing along x, of `radius` and half width `half`, and a
## painted hub (the tractor's trim on the tractor, iron on the trailer).
func _tyre(pen: NeighbourhoodBuildings.Pen, radius: float, half: float, painted: bool) -> void:
	var sides: int = 12
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var o0: Vector3 = Vector3(0.0, sin(a0), cos(a0))
		var o1: Vector3 = Vector3(0.0, sin(a1), cos(a1))
		var tread: float = radius * (1.0 if index % 2 == 0 else 0.94)
		pen.quad(Vector3(-half, 0.0, 0.0) + o0 * tread, Vector3(-half, 0.0, 0.0) + o1 * tread, Vector3(half, 0.0, 0.0) + o1 * tread,
			Vector3(half, 0.0, 0.0) + o0 * tread, (o0 + o1) * 0.5, skin.tyre)
		for x: float in [-half, half]:
			pen.quad(Vector3(x, 0.0, 0.0) + o0 * tread, Vector3(x, 0.0, 0.0) + o1 * tread, Vector3(x, 0.0, 0.0) + o1 * radius * 0.6,
				Vector3(x, 0.0, 0.0) + o0 * radius * 0.6, Vector3(signf(x), 0.0, 0.0), skin.tyre.lightened(0.05))
			pen.tri(Vector3(x * 1.05, 0.0, 0.0), Vector3(x * 1.05, 0.0, 0.0) + o0 * radius * 0.6, Vector3(x * 1.05, 0.0, 0.0) + o1 * radius * 0.6,
				Vector3(signf(x), 0.0, 0.0), skin.tractor_trim if painted else skin.iron)
	pen.box(Vector3(-half * 1.1, -0.02, -radius * 0.5), Vector3(half * 1.1, 0.02, radius * 0.5), skin.tyre.lightened(0.12))


## Where the tractor is along its run at `seconds` (local u), its heading (+1 or -1 in
## u) and whether it is out on the lane at all: it drives the length of the lane one
## way, rests out of sight, then comes back.
func tractor_run(seconds: float) -> Vector3:
	var middle: float = _centre_u()
	var length: float = WALK_REACH * 2.0 + 6.0
	var travel: float = length / TRACTOR_SPEED
	var period: float = travel + TRACTOR_REST
	var cycle: float = fposmod(seconds + 31.0, period * 2.0)
	var outward: bool = cycle < period
	var local: float = fposmod(cycle, period)
	var progress: float = clampf(local / travel, 0.0, 1.0)
	var start: float = middle - length * 0.5
	var u: float = start + progress * length if outward else start + (1.0 - progress) * length
	var out: float = 1.0 if local < travel else 0.0
	return Vector3(u, 1.0 if outward else -1.0, out)


## The tractor's transform (local) at `seconds`: on the lane's crown, keeping to the
## middle, turned along the lane's bends.
func tractor_transform(seconds: float) -> Transform3D:
	var run: Vector3 = tractor_run(seconds)
	var u: float = run.x
	var heading: Vector2 = Vector2(1.0, lane_slope(u)).normalized() * run.y
	var yaw: float = atan2(heading.x, heading.y)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(u, WALK_Y, lane_z(u) + TRACTOR_LANE))


# --- sheep and birds ------------------------------------------------------------

## Sheep grazing in the pasture across the lane (a lamb among them): woolly bodies on
## dark legs, a dark face that dips to the grass and lifts to look round.
func _build_sheep() -> void:
	sheep.clear()
	_sheep_spots.clear()
	var holder: Node3D = Node3D.new()
	holder.name = "Sheep"
	root.add_child(holder)
	var field: Rect2 = _pasture if _pasture.has_area() else Rect2(_centre_u() - 4.0, shift + LANE_V + 3.0, 8.0, 6.0)
	for index: int in skin.sheep:
		var at: Vector2 = Vector2(lerpf(field.position.x + 1.0, field.end.x - 1.0, 0.2 + 0.6 * _r(index, 901)),
			lerpf(field.position.y + 0.9, minf(field.end.y - 0.8, field.position.y + 5.5), 0.15 + 0.7 * _r(index, 902)))
		if absf(at.x - _centre_u()) < 1.0:
			at.x += 1.6
		var yaw: float = _r(index, 903) * TAU
		_sheep_spots.append(Vector4(at.x, at.y, yaw, _r(index, 904) * 13.0))
		var node: Node3D = _sheep_node(index, index == skin.sheep - 1 and skin.sheep > 2)
		holder.add_child(node)
		sheep.append(node)


## A sheep facing +z; its head is a child (`Head`) that lowers to graze.
func _sheep_node(index: int, lamb: bool) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Sheep%d" % index
	var model: Node3D = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * (SHEEP_SCALE * (0.7 if lamb else 1.0))
	node.add_child(model)
	var body: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var wool: Color = skin.fleece.darkened(0.04 * float(index % 2))
	body.lump(Vector3(0.0, 0.22, 0.0), 0.13, 0.11, 0.19, 0.3, wool, wool.darkened(0.18))
	body.lump(Vector3(0.0, 0.29, -0.03), 0.1, 0.06, 0.14, 0.8, wool.lightened(0.05), wool)
	for x: float in [-0.06, 0.06]:
		for z: float in [-0.11, 0.11]:
			body.box(Vector3(x - 0.016, 0.0, z - 0.016), Vector3(x + 0.016, 0.17, z + 0.016), skin.sheep_face)
	body.lump(Vector3(0.0, 0.24, -0.19), 0.035, 0.03, 0.03, 0.0, wool, wool.darkened(0.1))
	model.add_child(_instance("Body", body.soup.to_mesh(), _material))
	var neck: Node3D = Node3D.new()
	neck.name = "Head"
	neck.position = Vector3(0.0, 0.25, 0.15)
	var head: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	head.lump(Vector3(0.0, 0.03, 0.06), 0.05, 0.055, 0.075, 0.0, skin.sheep_face, skin.sheep_face.darkened(0.2))
	head.lump(Vector3(0.0, 0.075, 0.03), 0.055, 0.035, 0.05, 0.4, wool, wool.darkened(0.1))
	for side: float in [-1.0, 1.0]:
		head.tri(Vector3(side * 0.04, 0.05, 0.03), Vector3(side * 0.11, 0.03, 0.01), Vector3(side * 0.045, 0.02, 0.07), Vector3(side, 0.3, 0.0), skin.sheep_face)
	neck.add_child(_instance("Face", head.soup.to_mesh(), _material))
	model.add_child(neck)
	var shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	_shade_disc(shade, light_shift * 0.15, 0.2 * model.scale.x, 0.28)
	var shadow: MeshInstance3D = _instance("Shadow", shade.to_mesh(), _shadow_material)
	shadow.position = Vector3(0.0, SHADOW_Y - FIELD_Y, 0.0)
	node.add_child(shadow)
	return node


## A sheep's place at `seconds`: it ambles a short way, grazes, and ambles back.
func sheep_transform(index: int, seconds: float) -> Transform3D:
	var spot: Vector4 = _sheep_spots[index]
	var period: float = 23.0 + float(index) * 3.7
	var cycle: float = fposmod(seconds + spot.w, period * 2.0)
	var outward: bool = cycle < period
	var local: float = fposmod(cycle, period)
	var walk: float = smoothstep(0.0, 5.0, local)
	var travelled: float = (walk if outward else 1.0 - walk) * 0.45
	var heading: Vector3 = Vector3(sin(spot.z), 0.0, cos(spot.z))
	var facing: float = spot.z if outward else spot.z + PI
	if local > 5.0:
		facing += 0.25 * sin(local * 0.3 + float(index))
	return Transform3D(Basis(Vector3.UP, facing), Vector3(spot.x, FIELD_Y, spot.y) + heading * travelled)


## The sheep's head angle: down grazing most of the time, up now and then.
func sheep_graze(index: int, seconds: float) -> float:
	var period: float = 9.0 + float(index) * 1.9
	var phase: float = fposmod(seconds + float(index) * 3.3, period) / period
	var up: float = smoothstep(0.6, 0.66, phase) * (1.0 - smoothstep(0.86, 0.92, phase))
	return lerpf(0.75, -0.25, up)


## Swallows looping over the meadow and the stream: a dark body and two wings that beat.
func _build_birds() -> void:
	birds.clear()
	_bird_paths.clear()
	var holder: Node3D = Node3D.new()
	holder.name = "Birds"
	root.add_child(holder)
	var meadow: Plot = plots[0] if not plots.is_empty() else null
	for index: int in skin.birds:
		var centre: Vector2
		if index % 2 == 0 and meadow != null:
			centre = meadow.rect.get_center() + Vector2(_r(index, 911) - 0.5, _r(index, 912) - 0.5) * 2.0
		else:
			centre = Vector2(stream_u(shift) + (_r(index, 911) - 0.5) * 3.0, shift + (_r(index, 912) - 0.3) * 6.0)
		_bird_paths.append(Vector4(centre.x, centre.y, 1.4 + 1.2 * _r(index, 913), _r(index, 914) * TAU))
		var node: Node3D = Node3D.new()
		node.name = "Bird%d" % index
		var body: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		body.lump(Vector3.ZERO, 0.025, 0.02, 0.06, 0.0, skin.bird, skin.bird.lightened(0.3))
		body.tri(Vector3(-0.02, 0.0, -0.05), Vector3(0.02, 0.0, -0.05), Vector3(0.0, 0.0, -0.13), Vector3.UP, skin.bird)
		node.add_child(_instance("Body", body.soup.to_mesh(), _material))
		for side: float in [-1.0, 1.0]:
			var wing: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
			wing.tri(Vector3(0.0, 0.0, 0.03), Vector3(side * 0.16, 0.0, -0.04), Vector3(0.0, 0.0, -0.04), Vector3.UP, skin.bird)
			var wing_node: MeshInstance3D = _instance("Wing%s" % ("L" if side < 0.0 else "R"), wing.soup.to_mesh(), _material)
			node.add_child(wing_node)
		node.scale = Vector3.ONE * 1.5
		holder.add_child(node)
		birds.append(node)


## A swallow's place at `seconds`: a looping figure-of-eight, swooping low and up.
func bird_transform(index: int, seconds: float) -> Transform3D:
	var path: Vector4 = _bird_paths[index]
	var speed: float = 0.55 + 0.1 * float(index % 3)
	var t: float = seconds * speed + path.w
	var radius: float = path.z
	var at: Vector3 = Vector3(path.x + sin(t) * radius, 1.6 + 0.5 * sin(t * 2.0 + float(index)) + 0.25 * float(index % 2),
		path.y + sin(t * 2.0) * radius * 0.5)
	var ahead: Vector3 = Vector3(cos(t) * radius, 0.0, cos(t * 2.0) * radius)
	var yaw: float = atan2(ahead.x, ahead.z)
	var bank: float = -sin(t) * 0.5
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, bank), at)


# --- motion and time of day -------------------------------------------------------

## 0 by day, 1 from dusk; `late` rises after the shop closes. The lanterns and the
## cottages' windows light from dusk; the swallows and sheep's wandering stop at night
## and the tractor goes home.
## The warm lights low enough to stand over the ground (lamps, lit windows), street-local.
func lamp_spots() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for at: Vector3 in _lights:
		if at.y < 2.2:
			result.append(at)
	return result


## The day's weather (WeatherState.Kind): wind in the rain sways the crops and trees more.
func set_weather(kind: int) -> void:
	if kind == _weather:
		return
	_weather = kind
	_apply_night()


## A gloomy afternoon's early lamplight (WeatherLook.gloom): the lamps and windows come on
## dimly, everything else keeps the clock's time of day.
func set_gloom(level: float) -> void:
	var value: float = clampf(level, 0.0, 1.0) if is_finite(level) else 0.0
	if is_equal_approx(value, _gloom):
		return
	_gloom = value
	_apply_night()


func set_night(level: float, late: float) -> void:
	_night = level
	_late = late
	_apply_night()


func _apply_night() -> void:
	if root == null:
		return
	var lamps: float = maxf(_night, _gloom)
	_glass_material.emission_energy_multiplier = lamps * 2.4 * (1.0 - 0.6 * smoothstep(0.7, 1.0, _late))
	_glass_material.albedo_color = skin.window_glow.lerp(skin.ripple.darkened(0.35), 1.0 - lamps)
	_glow_material.set_shader_parameter(&"level", lamps)
	_headlamp_material.set_shader_parameter(&"level", _night)
	_stream_material.set_shader_parameter(&"moon", _night * _late)
	_pool_material.albedo_color = Color(1.0, 1.0, 1.0, lamps)
	# Unlit glows still cost a blended pass: hide them by day.
	_glow.visible = lamps > 0.05
	_pools.visible = lamps > 0.05
	for bird: Node3D in birds:
		bird.visible = _night < NIGHT_HIDE and _weather != WeatherState.Kind.RAIN
	_wheat_material.set_shader_parameter(&"reach", WHEAT_REACH[clampi(_weather, 0, 2)])
	_applied_at = -1.0
	apply(_seconds)


func is_lit() -> bool:
	return _night > 0.05


## Moves everything to the street clock's `seconds`; skipped when nothing changed.
func apply(seconds: float) -> void:
	_seconds = seconds
	if root == null or is_equal_approx(seconds, _applied_at):
		return
	_applied_at = seconds
	_stream_material.set_shader_parameter(&"stream_time", seconds)
	if wheel != null:
		wheel.basis = Basis(Vector3.RIGHT, wheel_angle(seconds))
	_wheat_material.set_shader_parameter(&"sway_time", seconds * WHEAT_PACE[clampi(_weather, 0, 2)])
	if tractor != null:
		var run: Vector3 = tractor_run(seconds)
		tractor.visible = run.z > 0.5 and _late < NIGHT_HIDE
		tractor.transform = tractor_transform(seconds)
		var travelled: float = seconds * TRACTOR_SPEED
		for node: Node3D in _tractor_wheels:
			node.basis = Basis(Vector3.RIGHT, travelled / float(node.get_meta(&"radius")))
	for index: int in sheep.size():
		sheep[index].transform = sheep_transform(index, seconds)
		var head: Node3D = sheep[index].get_node(^"Model/Head") as Node3D
		head.rotation = Vector3(sheep_graze(index, seconds), 0.0, 0.0)
	for index: int in birds.size():
		birds[index].transform = bird_transform(index, seconds) * Transform3D(Basis.from_scale(Vector3.ONE * 1.5), Vector3.ZERO)
		var beat: float = sin(seconds * 14.0 + float(index) * 1.3) * 0.6
		(birds[index].get_node(^"WingL") as Node3D).rotation = Vector3(0.0, 0.0, -beat)
		(birds[index].get_node(^"WingR") as Node3D).rotation = Vector3(0.0, 0.0, beat)


## What the country shows now, for tests and captures.
func capture_state() -> Dictionary:
	return {"plots": plot_ids(), "lit": is_lit(), "night": _night, "late": _late, "sheep": sheep.size(),
		"birds": birds.size(), "cottages": _cottage_spots.size(), "stream_side": stream_side, "wheel": wheel_at, "mill_wall": mill_wall,
		"weir": weir_z, "bridge": bridge_z, "stand": stand, "gate": gate, "forecourt": forecourt,
		"tractor": tractor.visible if tractor != null else false}
