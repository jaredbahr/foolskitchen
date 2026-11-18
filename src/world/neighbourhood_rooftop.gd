class_name NeighbourhoodRooftop
extends RefCounted
## A city rooftop instead of a street (#614). The shop stands on the roof of the
## tallest tower in town, behind a parapet with a rail. Guests come up by lift: the
## lift and stair lobby stands in front of the shop with its doors facing the shop's
## entrance, and a paved path runs from them to the door. Either side of the path is a
## deck terrace with planters along the parapet, potted trees, a bench, a parasol and
## string lights. Round the back and sides stands the roof's plant: a timber water
## tower, air handlers with turning fans, vents and a mast with a red aircraft light.
##
## Beyond the parapet the city falls away: other rooftops a few storeys down (one with
## a helipad, others with gardens and plant), office towers and blocks out to the
## haze, and the streets at the bottom. Clouds drift past below the roof, pigeons sit
## on the parapet, birds wheel over the city and now and then a plane goes by. At
## night the windows light up across the city, red lights blink on the tallest masts,
## the streets glow and cars' lights run along them.
##
## Like the rest of the neighbourhood it is view-only: no colliders, sim agents, saves,
## lights or random draws. Everything placed comes from an integer hash, and every
## motion is a closed-form function of the street's display clock, so a paused
## capture always shows the same frame. Authored in the street's local frame (u along
## the front, z outward past the door), under one root the dressing places on that
## frame. Draw cost: the roof and its props in a few batched vertex-coloured meshes,
## the city in a few chunks of flat boxes under one shader (windows and haze are drawn
## by the shader, not modelled), one cloud mesh, four glow-sprite meshes, and a few
## small nodes for the pigeons, birds, fans and the plane. The city is levelled by
## distance: roofs near the tower carry their clutter, farther ones only a rim, and
## the far ones are bare boxes.

const CITY_SHADER: Shader = preload("res://src/world/city.gdshader")
const GLOW_SHADER: Shader = preload("res://src/world/city_glow.gdshader")
const CLOUD_SHADER: Shader = preload("res://src/world/city_cloud.gdshader")

## Roof layers sit 4 mm or more apart, all under the shop floor (y 0).
const ROOF_Y: float = -0.062
const GRAVEL_Y: float = -0.056
const SEAM_Y: float = -0.052
const PAVER_Y: float = -0.048
const SHADOW_Y: float = -0.040
const POOL_Y: float = -0.034
## The terrace deck's top.
const DECK_TOP: float = 0.06
## The parapet: its height to the coping, thickness, the coping's lip and the rail.
const PARAPET_H: float = 0.42
const PARAPET_T: float = 0.28
const COPING: float = 0.05
const RAIL_H: float = 0.66
## How far the roof runs past the lot's maximum footprint: each side, behind it, and at
## least this far out in front (the lobby and terrace stand there).
const SIDE_PAD: float = 3.1
const BACK_PAD: float = 2.9
const FRONT_MIN: float = 7.6
## Keep everything that stands up at least this far off the lot.
const LOT_GAP: float = 0.4
## The lift and stair lobby: width (u), depth (z), wall height and the lift overrun.
const LOBBY_W: float = 3.1
const LOBBY_D: float = 2.1
const LOBBY_H: float = 1.95
const OVERRUN_H: float = 2.45
## The terrace decks reach at most this far in from the front parapet and out from the path.
const TERRACE_DEEP: float = 4.6
const TERRACE_WIDE: float = 5.4
## The path from the lobby to the door is this wide.
const WALK_W: float = 1.5
## The city: streets this wide between blocks; the city's chunks are this wide.
const STREET_W: float = 8.0
const CHUNK: float = 80.0
## Distances (from the tower's middle) that level the city's detail.
const NEAR: float = 34.0
const MID: float = 72.0
## The highest any other building's roof reaches (we are the tallest tower in town);
## the tallest of them carry a mast with an aircraft light.
const TOWER_TOP: float = -0.6
## Clouds lie far off only (#618): deep down among the city's roofs (top and bottom of
## their band, metres below the roof), in two bands either side of the tower that keep
## at least CLOUD_GAP clear of its faces across their whole drift and run CLOUD_BAND
## deep, so none drifts just under the roof or through the tower; CLOUD_HAZE of the
## haze colour lies over them so they read as far off.
const CLOUD_HIGH: float = -24.0
const CLOUD_LOW: float = -40.0
const CLOUD_GAP: float = 10.0
const CLOUD_BAND: float = 30.0
const CLOUD_HAZE: float = 0.45
## The plane's height and its path's closest pass to the tower.
const PLANE_Y: float = 6.0
const PLANE_PASS: float = 27.0
const PLANE_SPEED: float = 11.0
const PLANE_PERIOD: float = 75.0
## Pigeons are drawn this much larger than life, so they read from the camera.
const PIGEON_SCALE: float = 1.6
## Pigeons roost and birds go home after dark: past this far into the evening (0.5 is
## the golden dusk, when they are still out).
const NIGHT_HIDE: float = 0.75
## By weather (sunny, cloudy, rain): how much of the clouds below the roof show, and how
## thick the grey murk lies over the city (city.gdshader).
const CLOUD_SHARE: Array[float] = [1.0, 0.75, 0.35]
const MURK: Array[float] = [0.0, 0.4, 1.0]
## At the golden dusk only this share of the night's lit windows is on, and the streets
## far below are this far lit; both fill in as the dark comes.
const DUSK_WINDOW_SHARE: float = 0.25
const DUSK_STREET_SHARE: float = 0.5

## One building of the city: its footprint (local u, z), roof height and look.
class Lot extends RefCounted:
	var rect: Rect2
	## The roof the clutter stands on: the whole rect, or the crown above a setback.
	var cap: Rect2
	## How far below the top the setback steps in (0: a plain box).
	var step: float = 0.0
	var top: float = 0.0
	var colour: Color
	var roof: Color
	var style: int = 1
	var tone_seed: float = 0.0
	var detail: int = 2
	## &"helipad", &"garden", &"plant", &"tower" or &"" (bare).
	var kind: StringName = &""

## Inputs, set by the owner before build().
var skin: RooftopSkin
var local_reserve: AABB = AABB()
var shift: float = 0.0
var light_shift: Vector2 = Vector2.ZERO
var salt: int = 0
## Local (u, z) rects nothing may stand on: the door approaches and entrance pads.
var keep_clear: Array[Rect2] = []
## The shop building's local (u, z) extent, walls included (its baked shadow).
var building: Rect2 = Rect2()

var root: Node3D
## Where the roof's pieces went (local u, z), for tools and tests.
var roof: Rect2 = Rect2()
var lobby: Rect2 = Rect2()
var walkway: Rect2 = Rect2()
var terraces: Array[Rect2] = []
var door: Rect2 = Rect2()
var water_tower: Vector2 = Vector2.ZERO
var mast: Vector2 = Vector2.ZERO
var lots: Array[Lot] = []
var pigeons: Array[Node3D] = []
var birds: Array[Node3D] = []
var fans: Array[Node3D] = []
var plane: Node3D
var _pigeon_spots: Array[Vector4] = []
var _fan_spots: Array[Vector3] = []
var _material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _glass_material: StandardMaterial3D
var _pool_material: StandardMaterial3D
var _city_material: ShaderMaterial
var _cloud_material: ShaderMaterial
var _bulb_material: ShaderMaterial
var _beacon_material: ShaderMaterial
var _street_material: ShaderMaterial
var _traffic_material: ShaderMaterial
var _plane_light_material: ShaderMaterial
var _bulb_glow: MeshInstance3D
var _beacons: MeshInstance3D
var _street_lights: MeshInstance3D
var _traffic: MeshInstance3D
var _pools: MeshInstance3D
var _night: float = 0.0
var _late: float = 0.0
var _weather: int = WeatherState.Kind.SUNNY
## 0 through the golden dusk, 1 once the sun has gone (set_night).
var _dark: float = 1.0
var _seconds: float = 0.0
var _applied_at: float = -1.0
var _blocked: Array[Rect2] = []

## Built static meshes by street key, shared by every rooftop (a rebuild after a
## purchase or a reload reuses them instead of re-planning the city).
static var _cache: Dictionary[String, Dictionary] = {}


static func clear_cache() -> void:
	_cache.clear()


func _r(a: int, b: int) -> float:
	return NeighbourhoodGround.hash01(a, b, salt + 614)


func _reserve_rect() -> Rect2:
	return Rect2(local_reserve.position.x, local_reserve.position.z, local_reserve.size.x, shift - local_reserve.position.z)


## The middle of the roof (local u, z): the city is laid out round it.
func centre() -> Vector2:
	return roof.get_center()


# --- the plan of the roof ---------------------------------------------------

## Where the roof's edge, the lobby, the path and the terraces go, clear of the door.
func _plan_roof() -> void:
	_blocked.clear()
	terraces.clear()
	var lot: Rect2 = _reserve_rect()
	door = Rect2(lot.get_center().x - 0.6, shift, 1.2, 2.2)
	var doors: Array[Rect2] = []
	for rect: Rect2 in keep_clear:
		if rect.end.y > shift - 0.05:
			doors.append(rect)
	if not doors.is_empty():
		door = doors[0]
		for rect: Rect2 in doors:
			door = door.merge(rect)
	var door_u: float = door.get_center().x
	var lobby_z: float = maxf(door.end.y + 0.95, shift + 3.1)
	lobby = Rect2(door_u - LOBBY_W * 0.5, lobby_z, LOBBY_W, LOBBY_D)
	var front: float = maxf(shift + FRONT_MIN, lobby.end.y + 1.5)
	roof = Rect2(lot.position.x - SIDE_PAD, lot.position.y - BACK_PAD, lot.size.x + SIDE_PAD * 2.0, front - lot.position.y + BACK_PAD)
	walkway = Rect2(door_u - WALK_W * 0.5, shift, WALK_W, lobby.position.y - shift)
	_blocked.append(lot.grow(LOT_GAP))
	for rect: Rect2 in keep_clear:
		_blocked.append(rect.grow(0.15))
	_blocked.append(lobby.grow(0.25))
	_blocked.append(walkway.grow(0.25))
	# The terrace: a deck each side of the path, from the shop's front out to the
	# parapet, kept clear of the door's approach and the lobby.
	var inner: float = PARAPET_T + 0.22
	var near: float = shift + 0.3
	var far: float = roof.end.y - inner
	var left_edge: float = minf(door.position.x, lobby.position.x) - 0.3
	var right_edge: float = maxf(door.end.x, lobby.end.x) + 0.3
	near = maxf(near, far - TERRACE_DEEP)
	var left_outer: float = maxf(roof.position.x + inner, left_edge - TERRACE_WIDE)
	var right_outer: float = minf(roof.end.x - inner, right_edge + TERRACE_WIDE)
	var left: Rect2 = Rect2(left_outer, near, left_edge - left_outer, far - near)
	var right: Rect2 = Rect2(right_edge, near, right_outer - right_edge, far - near)
	for deck: Rect2 in [left, right]:
		if deck.size.x >= 1.2 and deck.size.y >= 1.5:
			terraces.append(deck)
			_blocked.append(deck)
	# Plant round the back: the water tower in one back corner, the mast in the other.
	var tower_left: bool = _r(1, 1) < 0.5
	var back: float = roof.position.y + PARAPET_T + 1.05
	water_tower = Vector2(roof.position.x + PARAPET_T + 1.05 if tower_left else roof.end.x - PARAPET_T - 1.05, back)
	mast = Vector2(roof.end.x - PARAPET_T - 0.45 if tower_left else roof.position.x + PARAPET_T + 0.45, roof.position.y + PARAPET_T + 0.45)


func _is_blocked(point: Vector2, margin: float) -> bool:
	for rect: Rect2 in _blocked:
		if rect.grow(margin).has_point(point):
			return true
	return false


# --- building ---------------------------------------------------------------

## Builds every node under `parent` (the dressing's rooftop root, placed on the street frame).
func build(parent: Node3D) -> void:
	root = parent
	_plan_roof()
	_materials()
	var key: String = var_to_str([local_reserve, shift, light_shift, salt, keep_clear, building, skin.signature()])
	var meshes: Dictionary = _cache.get(key, {})
	if meshes.is_empty():
		meshes = _build_static()
		if _cache.size() > 4:
			_cache.clear()
		_cache[key] = meshes
	else:
		_plan_city()
		_lamp_spots.assign(meshes.get("lamp_spots", []))
	_add(_instance("Roof", meshes["roof"], _material))
	_add(_instance("Props", meshes["props"], _material))
	_add(_instance("Shadows", meshes["shadows"], _shadow_material))
	_add(_instance("Glass", meshes["glass"], _glass_material))
	_pools = _instance("Pools", meshes["pools"], _pool_material)
	_add(_pools)
	var tower: MeshInstance3D = _instance("Tower", meshes["tower"], _city_material)
	tower.extra_cull_margin = 4.0
	_add(tower)
	# The city in square chunks, so the view culls the ones out of sight.
	var city: Node3D = Node3D.new()
	city.name = "City"
	root.add_child(city)
	var chunks: Array = meshes["city"]
	for index: int in chunks.size():
		var chunk: MeshInstance3D = _instance("Chunk%d" % index, chunks[index], _city_material)
		chunk.extra_cull_margin = 2.0
		city.add_child(chunk)
	var clouds: MeshInstance3D = _instance("Clouds", meshes["clouds"], _cloud_material)
	# Each puff drifts in the shader, far from where its mesh says it is.
	var reach: float = roof.size.y * 0.5 + CLOUD_GAP + CLOUD_BAND + 2.0
	clouds.custom_aabb = AABB(Vector3(centre().x - 120.0, CLOUD_LOW - 4.0, centre().y - reach),
		Vector3(240.0, CLOUD_HIGH - CLOUD_LOW + 16.0, reach * 2.0))
	_add(clouds)
	_bulb_glow = _instance("BulbGlow", meshes["bulbs"], _bulb_material)
	_bulb_glow.extra_cull_margin = 1.0
	_add(_bulb_glow)
	_beacons = _instance("Beacons", meshes["beacons"], _beacon_material)
	_beacons.extra_cull_margin = 2.0
	_add(_beacons)
	_street_lights = _instance("StreetLights", meshes["street_lights"], _street_material)
	_street_lights.extra_cull_margin = 2.0
	_add(_street_lights)
	_traffic = _instance("Traffic", meshes["traffic"], _traffic_material)
	_traffic.custom_aabb = AABB(Vector3(centre().x - skin.city_reach, -skin.street_depth - 2.0, centre().y - skin.city_reach),
		Vector3(skin.city_reach * 2.0, 4.0, skin.city_reach * 2.0))
	_add(_traffic)
	_build_fans()
	_build_pigeons()
	_build_birds()
	_build_plane()
	_apply_night()


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
	_glass_material = StandardMaterial3D.new()
	_glass_material.vertex_color_use_as_albedo = true
	_glass_material.roughness = 1.0
	_glass_material.metallic_specular = 0.0
	_glass_material.emission_enabled = true
	_glass_material.emission = skin.lamp_glow
	_glass_material.emission_energy_multiplier = 0.0
	_glass_material.disable_receive_shadows = true
	_pool_material = StandardMaterial3D.new()
	_pool_material.vertex_color_use_as_albedo = true
	_pool_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_material.disable_receive_shadows = true
	_city_material = ShaderMaterial.new()
	_city_material.shader = CITY_SHADER
	_city_material.set_shader_parameter(&"street_depth", skin.street_depth)
	_city_material.set_shader_parameter(&"centre", centre())
	_city_material.set_shader_parameter(&"haze_day", skin.haze_day)
	_city_material.set_shader_parameter(&"haze_dusk", skin.haze_dusk)
	_city_material.set_shader_parameter(&"haze_night", skin.haze_night)
	_city_material.set_shader_parameter(&"window_day", skin.window_day)
	_city_material.set_shader_parameter(&"window_dark", skin.window_dark)
	_city_material.set_shader_parameter(&"window_warm", skin.window_warm)
	_city_material.set_shader_parameter(&"window_cool", skin.window_cool)
	_city_material.set_shader_parameter(&"street_glow", skin.street_glow)
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = CLOUD_SHADER
	_cloud_material.set_shader_parameter(&"centre_u", centre().x)
	_bulb_material = _glow_material(0)
	_beacon_material = _glow_material(1)
	_street_material = _glow_material(0)
	_traffic_material = _glow_material(2)
	_traffic_material.set_shader_parameter(&"span", skin.city_reach * 2.0)
	_plane_light_material = _glow_material(1)


func _glow_material(mode: int) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter(&"mode", mode)
	material.set_shader_parameter(&"street_depth", skin.street_depth)
	return material


func _instance(label: String, mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _add(node: Node3D) -> void:
	root.add_child(node)


func _build_static() -> Dictionary:
	var meshes: Dictionary = {}
	var ground: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var props: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var glass: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var shadows: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var pools: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var bulbs: Array[Vector3] = []
	var bulb_sizes: Array[float] = []
	_fan_spots.clear()
	_pad_lights.clear()
	_lamp_spots.clear()
	_roof_surface(ground)
	_parapet(props, shadows)
	_lobby(props, glass, shadows, pools)
	_terraces(props, glass, shadows, pools, bulbs, bulb_sizes)
	_water_tower(props, shadows)
	_plant(props, shadows)
	_mast(props, shadows)
	if building.has_area():
		_shade_rect(shadows, building, ArtScale.WALL_HEIGHT, 0.26)
	meshes["roof"] = ground.soup.to_mesh()
	meshes["props"] = props.soup.to_mesh()
	meshes["glass"] = glass.soup.to_mesh()
	meshes["shadows"] = shadows.to_mesh()
	meshes["pools"] = pools.to_mesh()
	meshes["lamp_spots"] = _lamp_spots.duplicate()
	meshes["bulbs"] = _sprites(bulbs, bulb_sizes, [] as Array[Color], [] as Array[float])
	_plan_city()
	var tower: CitySoup = CitySoup.new()
	_our_tower(tower)
	meshes["tower"] = tower.to_mesh()
	var chunks: Dictionary[Vector2i, CitySoup] = {}
	var beacons: Array[Vector3] = [Vector3(mast.x, 4.62, mast.y)]
	for lot: Lot in lots:
		var at: Vector2 = lot.rect.get_center()
		var chunk: Vector2i = Vector2i(floori(at.x / CHUNK), floori(at.y / CHUNK))
		if not chunks.has(chunk):
			chunks[chunk] = CitySoup.new()
		_city_lot(chunks[chunk], lot, beacons)
	var ground_soup: CitySoup = CitySoup.new()
	_streets(ground_soup)
	var keys: Array[Vector2i] = chunks.keys()
	keys.sort()
	var city: Array[ArrayMesh] = [ground_soup.to_mesh()]
	for chunk: Vector2i in keys:
		city.append(chunks[chunk].to_mesh())
	meshes["city"] = city
	var beacon_sizes: Array[float] = []
	var beacon_tints: Array[Color] = []
	for point: Vector3 in beacons:
		beacon_sizes.append(0.9 if point.y > 0.0 else 1.4)
		beacon_tints.append(skin.aircraft_red)
	meshes["beacons"] = _sprites(beacons, beacon_sizes, beacon_tints, [] as Array[float])
	meshes["street_lights"] = _street_light_sprites()
	meshes["traffic"] = _traffic_sprites()
	meshes["clouds"] = _clouds()
	return meshes


# --- the roof ---------------------------------------------------------------

## The membrane in metre squares (so the shop's night light falls on it smoothly), its
## seams, a gravel border along the parapet with a few drains, and the paved path.
func _roof_surface(pen: NeighbourhoodBuildings.Pen) -> void:
	var cols: int = ceili(roof.size.x)
	var rows: int = ceili(roof.size.y)
	for i: int in cols:
		for j: int in rows:
			var x0: float = roof.position.x + roof.size.x * float(i) / float(cols)
			var x1: float = roof.position.x + roof.size.x * float(i + 1) / float(cols)
			var z0: float = roof.position.y + roof.size.y * float(j) / float(rows)
			var z1: float = roof.position.y + roof.size.y * float(j + 1) / float(rows)
			var tone: Color = skin.membrane.darkened(0.025 * _r(i * 7 + 3, j * 11 + 5))
			pen.flat(x0, z0, x1, z1, ROOF_Y, tone)
	# Membrane strips run across the roof (along u), welded at the seams.
	var step: float = 1.25
	var seam: float = roof.position.y + 1.0
	while seam < roof.end.y - 0.6:
		pen.flat(roof.position.x + PARAPET_T, seam - 0.012, roof.end.x - PARAPET_T, seam + 0.012, SEAM_Y, skin.membrane_seam)
		seam += step
	# The gravel border inside the parapet, speckled.
	var band: float = 0.42
	var inner: Rect2 = roof.grow(-PARAPET_T)
	var strips: Array[Rect2] = [Rect2(inner.position, Vector2(inner.size.x, band)),
		Rect2(inner.position.x, inner.end.y - band, inner.size.x, band),
		Rect2(inner.position.x, inner.position.y + band, band, inner.size.y - band * 2.0),
		Rect2(inner.end.x - band, inner.position.y + band, band, inner.size.y - band * 2.0)]
	for strip: Rect2 in strips:
		pen.flat(strip.position.x, strip.position.y, strip.end.x, strip.end.y, GRAVEL_Y, skin.gravel)
		var count: int = int(strip.size.x * strip.size.y * 14.0)
		for index: int in count:
			var p: Vector2 = strip.position + Vector2(_r(index, int(strip.position.x * 13.0) + 41), _r(index, int(strip.position.y * 17.0) + 43)) * strip.size
			var s: float = 0.025 + 0.025 * _r(index, 47)
			pen.flat(p.x - s, p.y - s, p.x + s, p.y + s, GRAVEL_Y + 0.002, skin.gravel_dark if index % 3 != 0 else skin.gravel.lightened(0.12))
	# Drains in the gravel at the four corners.
	for corner: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		var c: Vector2 = corner + (inner.get_center() - corner).normalized() * 0.3
		pen.flat(c.x - 0.09, c.y - 0.09, c.x + 0.09, c.y + 0.09, GRAVEL_Y + 0.004, skin.trim)
	# The paved path from the lobby doors to the shop's door: slabs with dark joints.
	var slab: float = 0.5
	var across: int = maxi(1, roundi(walkway.size.x / slab))
	var along: int = maxi(1, ceili(walkway.size.y / slab))
	var w: float = walkway.size.x / float(across)
	var d: float = walkway.size.y / float(along)
	pen.flat(walkway.position.x - 0.03, walkway.position.y, walkway.end.x + 0.03, walkway.end.y, PAVER_Y - 0.002, skin.paver_seam)
	for i: int in across:
		for j: int in along:
			var x0: float = walkway.position.x + w * float(i) + 0.012
			var z0: float = walkway.position.y + d * float(j) + 0.012
			var tone: Color = skin.paver.darkened(0.04 * _r(i + 31, j + 37))
			pen.flat(x0, z0, x0 + w - 0.024, z0 + d - 0.024, PAVER_Y, tone)
	# A doormat of slabs fanning out in front of the lobby.
	var apron: Rect2 = Rect2(lobby.position.x - 0.2, lobby.position.y - 0.55, lobby.size.x + 0.4, 0.55)
	pen.flat(apron.position.x, apron.position.y, apron.end.x, apron.end.y, PAVER_Y - 0.002, skin.paver_seam)
	var tiles: int = maxi(1, roundi(apron.size.x / slab))
	for i: int in tiles:
		var x0: float = apron.position.x + apron.size.x * float(i) / float(tiles) + 0.012
		var x1: float = apron.position.x + apron.size.x * float(i + 1) / float(tiles) - 0.012
		pen.flat(x0, apron.position.y + 0.012, x1, apron.end.y - 0.012, PAVER_Y, skin.paver.darkened(0.04 * _r(i + 51, 53)))


## The parapet round the roof's edge with its coping, and a slim rail on posts above it.
func _parapet(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var r: Rect2 = roof
	var t: float = PARAPET_T
	var walls: Array[Rect2] = [Rect2(r.position.x, r.position.y, r.size.x, t), Rect2(r.position.x, r.end.y - t, r.size.x, t),
		Rect2(r.position.x, r.position.y + t, t, r.size.y - t * 2.0), Rect2(r.end.x - t, r.position.y + t, t, r.size.y - t * 2.0)]
	for wall: Rect2 in walls:
		pen.box(Vector3(wall.position.x, ROOF_Y - 0.4, wall.position.y), Vector3(wall.end.x, PARAPET_H, wall.end.y), skin.parapet)
		var lip: Rect2 = wall.grow(0.035)
		pen.box(Vector3(lip.position.x, PARAPET_H, lip.position.y), Vector3(lip.end.x, PARAPET_H + COPING, lip.end.y), skin.coping)
	# The parapet's inner faces cast onto the gravel (the key light comes from the upper left).
	for wall: Rect2 in walls:
		_shade_rect(shadows, wall, PARAPET_H + COPING, 0.2)
	# The rail: posts along the coping's middle line and a top rail between them.
	var top: float = PARAPET_H + COPING
	var line: Rect2 = r.grow(-t * 0.5)
	var corners: Array[Vector2] = [line.position, Vector2(line.end.x, line.position.y), line.end, Vector2(line.position.x, line.end.y)]
	for index: int in 4:
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % 4]
		var length: float = a.distance_to(b)
		var posts: int = maxi(2, ceili(length / 1.4) + 1)
		for post: int in posts:
			var p: Vector2 = a.lerp(b, float(post) / float(posts - 1))
			pen.box(Vector3(p.x - 0.018, top, p.y - 0.018), Vector3(p.x + 0.018, RAIL_H, p.y + 0.018), skin.railing)
		var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(0.025, 0.025)
		var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(0.025, 0.025)
		pen.box(Vector3(lo.x, RAIL_H, lo.y), Vector3(hi.x, RAIL_H + 0.035, hi.y), skin.railing)
		pen.box(Vector3(lo.x + 0.01, top + 0.1, lo.y + 0.01), Vector3(hi.x - 0.01, top + 0.115, hi.y - 0.01), skin.railing)


## The lift and stair lobby: a box with the lift overrun rising at its back, its doors
## facing the shop (lift doors with lit glass either side, a stair door), a canopy and
## a board above them, and a warm spill of light in front at night.
func _lobby(pen: NeighbourhoodBuildings.Pen, glass: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup,
		pools: NeighbourhoodGround.Soup) -> void:
	var l: Rect2 = lobby
	var face: float = l.position.y
	pen.box(Vector3(l.position.x, ROOF_Y, l.position.y), Vector3(l.end.x, LOBBY_H, l.end.y), skin.lobby_wall)
	# A coping round its roof and a plinth at its foot.
	pen.flat(l.position.x, l.position.y, l.end.x, l.end.y, LOBBY_H + 0.002, skin.membrane.darkened(0.12))
	_rim(pen, l.grow(0.04), LOBBY_H, LOBBY_H + 0.09, 0.1, skin.coping)
	pen.box(Vector3(l.position.x - 0.025, ROOF_Y, l.position.y - 0.025), Vector3(l.end.x + 0.025, 0.08, l.end.y + 0.025), skin.trim)
	# Cladding panels: vertical joints on the three plain faces and a band at door height.
	var joint: Color = skin.lobby_wall.darkened(0.16)
	var x: float = l.position.x + 0.52
	while x < l.end.x - 0.3:
		pen.box(Vector3(x - 0.008, 0.08, l.end.y), Vector3(x + 0.008, LOBBY_H, l.end.y + 0.008), joint)
		x += 0.52
	var z: float = l.position.y + 0.52
	while z < l.end.y - 0.3:
		for side: float in [l.position.x - 0.008, l.end.x]:
			pen.box(Vector3(side, 0.08, z - 0.008), Vector3(side + 0.008, LOBBY_H, z + 0.008), joint)
		z += 0.52
	for face_rect: Array in [[Vector3(l.position.x, 1.3, l.end.y), Vector3(l.end.x, 1.33, l.end.y + 0.012)],
			[Vector3(l.position.x - 0.012, 1.3, l.position.y), Vector3(l.position.x, 1.33, l.end.y)],
			[Vector3(l.end.x, 1.3, l.position.y), Vector3(l.end.x + 0.012, 1.33, l.end.y)]]:
		pen.box(face_rect[0], face_rect[1], joint)
	# A high strip of glass round the three plain faces, lit from inside at night.
	glass.box(Vector3(l.position.x + 0.15, 1.5, l.end.y), Vector3(l.end.x - 0.15, 1.72, l.end.y + 0.015), skin.glass)
	glass.box(Vector3(l.position.x - 0.015, 1.5, l.position.y + 0.15), Vector3(l.position.x, 1.72, l.end.y - 0.15), skin.glass)
	glass.box(Vector3(l.end.x, 1.5, l.position.y + 0.15), Vector3(l.end.x + 0.015, 1.72, l.end.y - 0.15), skin.glass)
	# The lift overrun over the back half, with louvres on its sides.
	var overrun: Rect2 = Rect2(l.position.x + 0.35, l.position.y + l.size.y * 0.45, l.size.x - 0.7, l.size.y * 0.55 - 0.05)
	pen.box(Vector3(overrun.position.x, LOBBY_H, overrun.position.y), Vector3(overrun.end.x, OVERRUN_H, overrun.end.y), skin.lobby_wall.darkened(0.06))
	pen.flat(overrun.position.x, overrun.position.y, overrun.end.x, overrun.end.y, OVERRUN_H + 0.002, skin.membrane.darkened(0.08))
	_rim(pen, overrun.grow(0.03), OVERRUN_H, OVERRUN_H + 0.06, 0.07, skin.coping)
	# A vent on the lobby's roof beside the overrun.
	_mushroom_vent(pen, NeighbourhoodGround.Soup.new(), Vector2(l.position.x + 0.55, l.position.y + 0.5), LOBBY_H - ROOF_Y)
	for index: int in 4:
		var y: float = LOBBY_H + 0.17 + float(index) * 0.06
		pen.box(Vector3(overrun.position.x + 0.2, y, overrun.position.y - 0.012), Vector3(overrun.end.x - 0.2, y + 0.025, overrun.position.y), skin.plant_dark)
	# The lift: a dark frame, two brushed doors with a seam, glass sidelights either side.
	var lift_u: float = l.get_center().x - 0.25
	var half: float = 0.36
	var door_top: float = 1.22
	pen.box(Vector3(lift_u - half - 0.07, 0.0, face - 0.03), Vector3(lift_u + half + 0.07, door_top + 0.08, face), skin.trim)
	pen.box(Vector3(lift_u - half, 0.02, face - 0.045), Vector3(lift_u - 0.006, door_top, face - 0.03), skin.lift_door)
	pen.box(Vector3(lift_u + 0.006, 0.02, face - 0.045), Vector3(lift_u + half, door_top, face - 0.03), skin.lift_door)
	for side: float in [-1.0, 1.0]:
		var x0: float = lift_u + side * (half + 0.12)
		var x1: float = lift_u + side * (half + 0.36)
		pen.box(Vector3(minf(x0, x1) - 0.03, 0.0, face - 0.03), Vector3(maxf(x0, x1) + 0.03, door_top + 0.08, face), skin.trim)
		glass.box(Vector3(minf(x0, x1), 0.06, face - 0.04), Vector3(maxf(x0, x1), door_top, face - 0.03), skin.glass)
	# The call button and the floor display above the doors (lit at night).
	glass.box(Vector3(lift_u + half + 0.4, 0.5, face - 0.045), Vector3(lift_u + half + 0.44, 0.56, face - 0.03), skin.lamp_glow)
	glass.box(Vector3(lift_u - 0.16, door_top + 0.12, face - 0.045), Vector3(lift_u + 0.16, door_top + 0.2, face - 0.03), skin.lamp_glow)
	# The stair door, plain and dark, at the side.
	var stair_u: float = l.end.x - 0.42
	pen.box(Vector3(stair_u - 0.26, 0.0, face - 0.03), Vector3(stair_u + 0.26, door_top + 0.06, face), skin.trim)
	pen.box(Vector3(stair_u - 0.22, 0.02, face - 0.045), Vector3(stair_u + 0.22, door_top, face - 0.03), skin.plant_dark)
	pen.box(Vector3(stair_u + 0.12, 0.55, face - 0.07), Vector3(stair_u + 0.17, 0.58, face - 0.045), skin.coping)
	# A canopy over the doors on two brackets, and the lit board above it.
	var canopy: Rect2 = Rect2(l.position.x + 0.12, face - 0.32, l.size.x - 0.24, 0.32)
	pen.box(Vector3(canopy.position.x, door_top + 0.3, canopy.position.y), Vector3(canopy.end.x, door_top + 0.36, canopy.end.y), skin.lift_door)
	pen.box(Vector3(canopy.position.x, door_top + 0.28, canopy.position.y), Vector3(canopy.end.x, door_top + 0.3, canopy.position.y + 0.03), skin.trim)
	for bracket: float in [canopy.position.x + 0.15, canopy.end.x - 0.15]:
		pen.box(Vector3(bracket - 0.015, door_top + 0.22, canopy.position.y + 0.05), Vector3(bracket + 0.015, door_top + 0.3, face), skin.trim)
	pen.box(Vector3(l.get_center().x - 0.8, door_top + 0.42, face - 0.05), Vector3(l.get_center().x + 0.8, door_top + 0.66, face), skin.sign_board)
	glass.box(Vector3(l.get_center().x - 0.7, door_top + 0.46, face - 0.065), Vector3(l.get_center().x + 0.7, door_top + 0.5, face - 0.05), skin.lamp_glow)
	_shade_rect(shadows, l, OVERRUN_H, 0.3)
	_shade_rect(shadows, canopy, 0.12, 0.12)
	# The warm spill of light on the slabs in front of the doors (night only).
	_pool(pools, Vector2(lift_u, face - 0.7), Vector2(1.6, 0.9), skin.lamp_glow, 0.6)


## The two terrace decks either side of the path: planks, a planter run along the
## parapet, a potted tree, a bench, a parasol on the larger one and string lights.
func _terraces(pen: NeighbourhoodBuildings.Pen, glass: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup,
		pools: NeighbourhoodGround.Soup, bulbs: Array[Vector3], sizes: Array[float]) -> void:
	var largest: int = 0
	for index: int in terraces.size():
		if terraces[index].get_area() > terraces[largest].get_area():
			largest = index
	for index: int in terraces.size():
		var deck: Rect2 = terraces[index]
		var outer_left: bool = deck.get_center().x < walkway.get_center().x
		_deck(pen, deck, index)
		_shade_rect(shadows, deck, DECK_TOP, 0.12)
		# Planters along the parapet at the front, and down the outer side.
		var run: Rect2 = Rect2(deck.position.x + 0.1, deck.end.y - 0.5, deck.size.x - 0.2, 0.42)
		_planters(pen, shadows, run, true, index * 10)
		var side_x: float = deck.position.x + 0.08 if outer_left else deck.end.x - 0.5
		var side: Rect2 = Rect2(side_x, deck.position.y + 0.9, 0.42, maxf(deck.size.y - 1.9, 0.0))
		if side.size.y > 0.9:
			_planters(pen, shadows, side, false, index * 10 + 5)
		# The potted tree by the path, near the lobby.
		var tree_at: Vector2 = Vector2(deck.end.x - 0.45 if outer_left else deck.position.x + 0.45, deck.end.y - 1.0)
		_potted_tree(pen, shadows, tree_at, 1.0 + 0.2 * _r(index, 61), index)
		# A bench facing the view and, on the larger deck, a parasol.
		var bench_x: float = deck.get_center().x
		var bench: Vector2 = Vector2(bench_x, deck.end.y - 1.0)
		if absf(bench.x - tree_at.x) > 1.2:
			_bench(pen, shadows, bench)
		if index == largest and deck.size.x > 2.4:
			var at: Vector2 = Vector2(deck.position.x + deck.size.x * (0.35 if outer_left else 0.65), deck.position.y + deck.size.y * 0.42)
			_parasol(pen, shadows, at)
		# String lights: posts at the deck's corners, strung corner to corner and across.
		var inset: Rect2 = deck.grow(-0.18)
		var posts: Array[Vector2] = [inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]
		for post: Vector2 in posts:
			pen.box(Vector3(post.x - 0.025, DECK_TOP, post.y - 0.025), Vector3(post.x + 0.025, 1.55, post.y + 0.025), skin.trim)
			pen.box(Vector3(post.x - 0.06, DECK_TOP, post.y - 0.06), Vector3(post.x + 0.06, DECK_TOP + 0.08, post.y + 0.06), skin.trim)
		var strings: Array[Array] = [[posts[0], posts[2]], [posts[1], posts[3]], [posts[0], posts[1]], [posts[3], posts[2]]]
		for pair: Array in strings:
			_string_lights(pen, glass, pair[0], pair[1], bulbs, sizes)
		_pool(pools, deck.get_center(), deck.size * 0.6, skin.lamp_glow, 0.45, DECK_TOP + 0.004)


func _deck(pen: NeighbourhoodBuildings.Pen, deck: Rect2, index: int) -> void:
	# A dark frame under the planks, then planks running along u.
	pen.box(Vector3(deck.position.x, ROOF_Y, deck.position.y), Vector3(deck.end.x, DECK_TOP - 0.01, deck.end.y), skin.deck_dark)
	var plank: float = 0.16
	var count: int = maxi(1, floori(deck.size.y / plank))
	var width: float = deck.size.y / float(count)
	for row: int in count:
		var z0: float = deck.position.y + width * float(row) + 0.008
		var tone: Color = skin.deck.darkened(0.06 * _r(row + index * 97, 71)) if row % 3 != 1 else skin.deck.lightened(0.03)
		# Each row is two or three boards butted end to end.
		var cut: float = deck.position.x + deck.size.x * (0.3 + 0.4 * _r(row + index * 97, 72))
		pen.flat(deck.position.x + 0.01, z0, cut - 0.008, z0 + width - 0.016, DECK_TOP, tone)
		pen.flat(cut + 0.008, z0, deck.end.x - 0.01, z0 + width - 0.016, DECK_TOP, tone.darkened(0.03))


## Corten planter boxes in a run (along u when `along_u`, else along z), with soil,
## grasses, shrubs and flowers.
func _planters(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, run: Rect2, along_u: bool, seed_value: int) -> void:
	var length: float = run.size.x if along_u else run.size.y
	var boxes: int = maxi(1, roundi(length / 1.3))
	var each: float = length / float(boxes)
	var height: float = 0.36
	for index: int in boxes:
		var box: Rect2
		if along_u:
			box = Rect2(run.position.x + each * float(index) + 0.03, run.position.y, each - 0.06, run.size.y)
		else:
			box = Rect2(run.position.x, run.position.y + each * float(index) + 0.03, run.size.x, each - 0.06)
		pen.box(Vector3(box.position.x, DECK_TOP, box.position.y), Vector3(box.end.x, DECK_TOP + height, box.end.y), skin.planter)
		var inner: Rect2 = box.grow(-0.035)
		pen.flat(inner.position.x, inner.position.y, inner.end.x, inner.end.y, DECK_TOP + height - 0.04, skin.soil)
		_shade_rect(shadows, box, DECK_TOP + height, 0.22)
		var plants: int = maxi(2, int((box.size.x * box.size.y) * 9.0))
		for plant: int in plants:
			var s: int = seed_value * 131 + index * 17 + plant
			var p: Vector2 = inner.position + Vector2(_r(s, 81), _r(s, 82)) * inner.size
			var base: Vector3 = Vector3(p.x, DECK_TOP + height - 0.04, p.y)
			var leaf: Color = skin.leaf_colors[int(_r(s, 83) * 97.0) % skin.leaf_colors.size()]
			if plant % 3 == 0:
				pen.lump(base + Vector3.UP * 0.1, 0.13, 0.13, 0.12, _r(s, 84) * TAU, leaf.lightened(0.05), leaf.darkened(0.12))
			elif plant % 3 == 1:
				for blade: int in 4:
					var angle: float = _r(s + blade, 85) * TAU
					var lean: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * 0.08
					var across: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * 0.025
					pen.tri(base - across, base + across, base + lean + Vector3.UP * (0.22 + 0.1 * _r(s + blade, 86)), lean + Vector3.UP * 0.2,
						leaf if blade % 2 == 0 else leaf.lightened(0.1))
			else:
				var bloom: Color = skin.bloom_colors[int(_r(s, 87) * 97.0) % skin.bloom_colors.size()]
				pen.lump(base + Vector3.UP * 0.06, 0.08, 0.07, 0.08, _r(s, 88) * TAU, leaf, leaf.darkened(0.1))
				for head: int in 3:
					var angle: float = TAU * float(head) / 3.0 + _r(s, 89)
					var at: Vector3 = base + Vector3(cos(angle) * 0.05, 0.13 + 0.03 * float(head % 2), sin(angle) * 0.05)
					pen.box(at - Vector3(0.022, 0.018, 0.022), at + Vector3(0.022, 0.018, 0.022), bloom)


## A big round pot with a small tree: a slim trunk and a few chunky crown lumps.
func _potted_tree(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2, size: float, seed_value: int) -> void:
	var pot: Color = skin.pot_colors[seed_value % skin.pot_colors.size()]
	var base: Vector3 = Vector3(at.x, DECK_TOP, at.y)
	_drum(pen, base, 0.2, 0.25, 0.34, 10, pot, skin.soil)
	_drum(pen, base + Vector3.UP * 0.34, 0.255, 0.255, 0.035, 10, pot.lightened(0.08), skin.soil)
	pen.box(base + Vector3(-0.03, 0.34, -0.03), base + Vector3(0.03, 0.34 + 0.7 * size, 0.03), skin.trunk)
	var leaf: Color = skin.leaf_colors[(seed_value + 1) % skin.leaf_colors.size()]
	var crown: Vector3 = base + Vector3.UP * (0.34 + 0.85 * size)
	pen.lump(crown, 0.36 * size, 0.34 * size, 0.34 * size, _r(seed_value, 91), leaf.lightened(0.06), leaf.darkened(0.14))
	for index: int in 3:
		var angle: float = TAU * float(index) / 3.0 + _r(seed_value, 92) * 2.0
		var offset: Vector3 = Vector3(cos(angle) * 0.22, -0.1 + 0.12 * float(index % 2), sin(angle) * 0.22) * size
		pen.lump(crown + offset, 0.22 * size, 0.2 * size, 0.22 * size, angle, leaf.lightened(0.1 if index == 0 else 0.0), leaf.darkened(0.16))
	_shade_disc(shadows, at + light_shift * 0.2, 0.3, 0.3)
	_shade_disc(shadows, at + light_shift * (0.34 + 0.85 * size), 0.42 * size, 0.18)


## A bench facing out over the parapet: two concrete blocks, timber slats, two cushions.
func _bench(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2) -> void:
	var half: float = 0.55
	for side: float in [-1.0, 1.0]:
		var x: float = at.x + side * (half - 0.08)
		pen.box(Vector3(x - 0.06, DECK_TOP, at.y - 0.15), Vector3(x + 0.06, DECK_TOP + 0.24, at.y + 0.15), skin.parapet)
	for slat: int in 3:
		var z: float = at.y - 0.15 + float(slat) * 0.105
		pen.box(Vector3(at.x - half, DECK_TOP + 0.24, z), Vector3(at.x + half, DECK_TOP + 0.27, z + 0.09), skin.deck.darkened(0.05))
	for side: float in [-1.0, 1.0]:
		var x: float = at.x + side * 0.24
		pen.box(Vector3(x - 0.2, DECK_TOP + 0.27, at.y - 0.13), Vector3(x + 0.2, DECK_TOP + 0.33, at.y + 0.13), skin.cushion if side < 0.0 else skin.cushion.darkened(0.08))
	_shade_rect(shadows, Rect2(at.x - half, at.y - 0.16, half * 2.0, 0.32), DECK_TOP + 0.3, 0.25)


## A striped parasol on a pole, its canopy eight panels of two colours.
func _parasol(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2) -> void:
	var base: Vector3 = Vector3(at.x, DECK_TOP, at.y)
	_drum(pen, base, 0.16, 0.14, 0.05, 8, skin.trim, skin.trim)
	pen.box(base + Vector3(-0.015, 0.0, -0.015), base + Vector3(0.015, 1.32, 0.015), skin.railing)
	var radius: float = 0.78
	var rim: float = 1.12
	var peak: Vector3 = base + Vector3.UP * 1.36
	for index: int in 8:
		var a0: float = TAU * float(index) / 8.0 + 0.2
		var a1: float = TAU * float(index + 1) / 8.0 + 0.2
		var p0: Vector3 = base + Vector3(cos(a0) * radius, rim, sin(a0) * radius)
		var p1: Vector3 = base + Vector3(cos(a1) * radius, rim, sin(a1) * radius)
		var colour: Color = skin.parasol_a if index % 2 == 0 else skin.parasol_b
		pen.tri(p0, p1, peak, (p0 + p1) * 0.5 - base, colour)
		# A short scalloped valance hangs from the rim.
		pen.quad(p0, p1, p1 - Vector3.UP * 0.07, p0 - Vector3.UP * 0.07, (p0 + p1) * 0.5 - base - Vector3.UP * rim, colour.darkened(0.06))
	_shade_disc(shadows, at + light_shift * 1.1, 0.8, 0.22)


## A string of bulbs sagging between two posts: dark wire, glass bulbs, glow sprites.
func _string_lights(pen: NeighbourhoodBuildings.Pen, glass: NeighbourhoodBuildings.Pen, from: Vector2, to: Vector2,
		bulbs: Array[Vector3], sizes: Array[float]) -> void:
	var a: Vector3 = Vector3(from.x, 1.5, from.y)
	var b: Vector3 = Vector3(to.x, 1.5, to.y)
	var segments: int = maxi(4, roundi(a.distance_to(b) / 0.3))
	var sag: float = minf(0.28, a.distance_to(b) * 0.07)
	var previous: Vector3 = a
	for step: int in range(1, segments + 1):
		var t: float = float(step) / float(segments)
		var p: Vector3 = a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
		var side: Vector3 = (p - previous).cross(Vector3.UP).normalized() * 0.007
		pen.quad(previous - side, p - side, p + side + Vector3.UP * 0.008, previous + side + Vector3.UP * 0.008, Vector3.UP, skin.trim)
		if step < segments and step % 2 == 1:
			var bulb: Vector3 = p - Vector3.UP * 0.04
			bulbs.append(bulb)
			sizes.append(0.3)
			glass.box(bulb - Vector3(0.02, 0.028, 0.02), bulb + Vector3(0.02, 0.028, 0.02), Color.WHITE)
		previous = p


# --- the roof's plant --------------------------------------------------------

## A timber water tower on a steel stand: four legs with braces, a platform, the tank
## with its hoops, a conical roof with a finial, and a ladder.
func _water_tower(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var c: Vector3 = Vector3(water_tower.x, ROOF_Y, water_tower.y)
	var leg: float = 0.55
	var deck_y: float = 0.95
	for dx: float in [-leg, leg]:
		for dz: float in [-leg, leg]:
			pen.box(c + Vector3(dx - 0.035, 0.0, dz - 0.035), c + Vector3(dx + 0.035, deck_y, dz + 0.035), skin.trim)
			pen.box(c + Vector3(dx - 0.07, 0.0, dz - 0.07), c + Vector3(dx + 0.07, 0.08, dz + 0.07), skin.parapet)
	for y: float in [0.38, 0.72]:
		pen.box(c + Vector3(-leg, y, -leg - 0.015), c + Vector3(leg, y + 0.03, -leg + 0.015), skin.trim)
		pen.box(c + Vector3(-leg, y, leg - 0.015), c + Vector3(leg, y + 0.03, leg + 0.015), skin.trim)
		pen.box(c + Vector3(-leg - 0.015, y, -leg), c + Vector3(-leg + 0.015, y + 0.03, leg), skin.trim)
		pen.box(c + Vector3(leg - 0.015, y, -leg), c + Vector3(leg + 0.015, y + 0.03, leg), skin.trim)
	pen.box(c + Vector3(-0.72, deck_y, -0.72), c + Vector3(0.72, deck_y + 0.06, 0.72), skin.plant_dark)
	var tank: Vector3 = c + Vector3.UP * (deck_y + 0.06)
	var height: float = 1.2
	_drum(pen, tank, 0.66, 0.62, height, 14, skin.tank_wood, skin.tank_roof)
	for y: float in [0.12, 0.5, 0.9]:
		_drum(pen, tank + Vector3.UP * y, 0.675 - y * 0.035, 0.675 - y * 0.035, 0.045, 14, skin.trim, skin.trim)
	# Stave lines down the tank.
	for index: int in 14:
		var angle: float = TAU * (float(index) + 0.5) / 14.0
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		pen.box(tank + out * 0.655 + Vector3(-0.008, 0.0, -0.008), tank + out * 0.64 + Vector3(0.008, height - 0.02, 0.008), skin.tank_wood.darkened(0.18))
	var roof_base: Vector3 = tank + Vector3.UP * height
	_cone(pen, roof_base, 0.7, 0.5, 14, skin.tank_roof)
	pen.box(roof_base + Vector3(-0.025, 0.48, -0.025), roof_base + Vector3(0.025, 0.66, 0.025), skin.trim)
	pen.lump(roof_base + Vector3.UP * 0.68, 0.045, 0.045, 0.045, 0.0, skin.trim, skin.trim)
	# A ladder up the side facing the roof's middle.
	var toward: Vector2 = (centre() - water_tower).normalized()
	var face: Vector3 = Vector3(toward.x, 0.0, toward.y)
	var across: Vector3 = Vector3(-face.z, 0.0, face.x)
	var foot: Vector3 = c + face * 0.7
	for side: float in [-0.12, 0.12]:
		var rail: Vector3 = foot + across * side
		pen.box(rail - Vector3(0.012, 0.0, 0.012), rail + Vector3(0.012, deck_y + height + 0.1, 0.012), skin.trim)
	for rung: int in 10:
		var y: float = 0.2 + float(rung) * 0.2
		var mid: Vector3 = foot + Vector3.UP * y
		var a: Vector3 = mid - across * 0.12
		var b: Vector3 = mid + across * 0.12
		pen.box(Vector3(minf(a.x, b.x) - 0.008, y, minf(a.z, b.z) - 0.008), Vector3(maxf(a.x, b.x) + 0.008, y + 0.016, maxf(a.z, b.z) + 0.008), skin.trim)
	_shade_disc(shadows, water_tower + light_shift * 1.6, 0.75, 0.24)
	_shade_rect(shadows, Rect2(water_tower - Vector2(leg, leg), Vector2(leg, leg) * 2.0), deck_y, 0.12)


## Air handlers with fans on top and a duct into the roof, vent stacks, mushroom vents,
## a skylight and a satellite dish, all in the strips beside and behind the lot.
func _plant(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var lot: Rect2 = _reserve_rect()
	var inner: Rect2 = roof.grow(-PARAPET_T - 0.5)
	var tower_left: bool = water_tower.x < centre().x
	# Air handlers in the side strip opposite the water tower, running along z.
	var strip_x: float = (lot.end.x + LOT_GAP + inner.end.x) * 0.5 if tower_left else (inner.position.x + lot.position.x - LOT_GAP) * 0.5
	var strip_w: float = (inner.end.x - lot.end.x - LOT_GAP) if tower_left else (lot.position.x - LOT_GAP - inner.position.x)
	var unit: Vector2 = Vector2(minf(1.0, strip_w - 0.3), 1.45)
	var units: int = 0
	var z: float = lot.position.y + 0.4
	while units < 2 and z + unit.y < shift - 0.6 and unit.x > 0.6:
		var rect: Rect2 = Rect2(strip_x - unit.x * 0.5, z, unit.x, unit.y)
		_air_handler(pen, shadows, rect)
		z += unit.y + 0.7
		units += 1
	# Vent stacks and mushroom vents behind the lot.
	var back: Rect2 = Rect2(lot.position.x - 0.5, inner.position.y, lot.size.x + 1.0, lot.position.y - LOT_GAP - inner.position.y)
	var count: int = maxi(3, int(back.size.x / 1.6))
	for index: int in count:
		var p: Vector2 = Vector2(lerpf(back.position.x + 0.3, back.end.x - 0.3, (float(index) + 0.5) / float(count)) + (_r(index, 141) - 0.5) * 0.4,
			back.position.y + back.size.y * (0.3 + 0.4 * _r(index, 142)))
		if p.distance_to(water_tower) < 1.2 or p.distance_to(mast) < 0.6 or _is_blocked(p, 0.2):
			continue
		match index % 3:
			0:
				_mushroom_vent(pen, shadows, p)
			1:
				_stack(pen, shadows, p, 0.45 + 0.35 * _r(index, 143))
			_:
				_gooseneck(pen, shadows, p, _r(index, 144) * TAU)
	# A skylight and a dish in the tower's side strip, in front of the water tower.
	var side_x: float = (inner.position.x + lot.position.x - LOT_GAP) * 0.5 if tower_left else (lot.end.x + LOT_GAP + inner.end.x) * 0.5
	var sky: Rect2 = Rect2(side_x - 0.4, water_tower.y + 1.4, 0.8, 1.1)
	if sky.end.y < shift - 0.4 and not _is_blocked(sky.get_center(), 0.3):
		pen.box(Vector3(sky.position.x, ROOF_Y, sky.position.y), Vector3(sky.end.x, 0.14, sky.end.y), skin.plant)
		pen.box(Vector3(sky.position.x + 0.05, 0.14, sky.position.y + 0.05), Vector3(sky.end.x - 0.05, 0.17, sky.end.y - 0.05), skin.glass)
		for bar: int in 2:
			var y0: float = sky.position.y + sky.size.y * float(bar + 1) / 3.0
			pen.box(Vector3(sky.position.x + 0.04, 0.17, y0 - 0.015), Vector3(sky.end.x - 0.04, 0.18, y0 + 0.015), skin.plant)
		_shade_rect(shadows, sky, 0.17, 0.22)
	var dish: Vector2 = Vector2(side_x, sky.end.y + 0.8)
	if dish.y < shift - 0.4 and not _is_blocked(dish, 0.3):
		_satellite_dish(pen, shadows, dish)
	# A run of pipe on blocks along the back parapet.
	var pipe_z: float = inner.position.y - 0.2
	for x: int in range(ceili(inner.position.x + 0.5), floori(inner.end.x - 0.5)):
		pen.box(Vector3(float(x) - 0.05, ROOF_Y, pipe_z - 0.07), Vector3(float(x) + 0.05, 0.06, pipe_z + 0.07), skin.parapet.darkened(0.1))
	var pipe_lo: float = inner.position.x + 0.3
	var pipe_hi: float = inner.end.x - 0.3
	if tower_left:
		pipe_lo = water_tower.x + 0.85
	else:
		pipe_hi = water_tower.x - 0.85
	pen.box(Vector3(pipe_lo, 0.06, pipe_z - 0.04), Vector3(pipe_hi, 0.14, pipe_z + 0.04), skin.duct.darkened(0.15))


func _air_handler(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, rect: Rect2) -> void:
	var height: float = 0.62
	pen.box(Vector3(rect.position.x, ROOF_Y, rect.position.y), Vector3(rect.end.x, 0.05, rect.end.y), skin.plant_dark)
	pen.box(Vector3(rect.position.x + 0.03, 0.05, rect.position.y + 0.03), Vector3(rect.end.x - 0.03, height, rect.end.y - 0.03), skin.plant)
	pen.box(Vector3(rect.position.x + 0.01, height, rect.position.y + 0.01), Vector3(rect.end.x - 0.01, height + 0.03, rect.end.y - 0.01), skin.plant.lightened(0.08))
	# Louvres down both long sides.
	for side: float in [rect.position.x + 0.025, rect.end.x - 0.025]:
		for index: int in 5:
			var y: float = 0.14 + float(index) * 0.08
			pen.box(Vector3(side - 0.012, y, rect.position.y + 0.15), Vector3(side + 0.012, y + 0.03, rect.end.y - 0.15), skin.plant_dark)
	# Two fan housings on top; the fans turn (nodes, see _build_fans).
	for index: int in 2:
		var c: Vector3 = Vector3(rect.get_center().x, height + 0.03, rect.position.y + rect.size.y * (0.27 + 0.46 * float(index)))
		var radius: float = minf(rect.size.x, rect.size.y * 0.5) * 0.4
		_drum(pen, c, radius + 0.03, radius + 0.03, 0.06, 12, skin.plant.darkened(0.05), skin.plant_dark.darkened(0.2))
		_fan_spots.append(Vector3(c.x, c.y + 0.065, c.z))
		pen.box(Vector3(c.x - 0.03, c.y + 0.06, c.z - 0.03), Vector3(c.x + 0.03, c.y + 0.085, c.z + 0.03), skin.plant_dark)
	# A duct down into the roof at its outer end.
	var duct: Rect2 = Rect2(rect.get_center().x - 0.17, rect.end.y, 0.34, 0.45)
	pen.box(Vector3(duct.position.x, ROOF_Y, duct.position.y), Vector3(duct.end.x, 0.4, duct.end.y), skin.duct)
	pen.box(Vector3(duct.position.x - 0.03, ROOF_Y, duct.end.y - 0.06), Vector3(duct.end.x + 0.03, 0.08, duct.end.y + 0.04), skin.parapet)
	_shade_rect(shadows, rect, height, 0.28)
	_shade_rect(shadows, duct, 0.4, 0.2)


func _mushroom_vent(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2, lift: float = 0.0) -> void:
	var base: Vector3 = Vector3(at.x, ROOF_Y + lift, at.y)
	_drum(pen, base, 0.14, 0.14, 0.08, 8, skin.parapet, skin.parapet)
	_drum(pen, base + Vector3.UP * 0.08, 0.09, 0.09, 0.22, 8, skin.duct, skin.duct)
	_drum(pen, base + Vector3.UP * 0.3, 0.2, 0.08, 0.1, 8, skin.duct.lightened(0.06), skin.duct.lightened(0.1))
	_shade_disc(shadows, at + light_shift * 0.3, 0.2, 0.25)


func _stack(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2, height: float) -> void:
	var base: Vector3 = Vector3(at.x, ROOF_Y, at.y)
	_drum(pen, base, 0.07, 0.07, height, 8, skin.duct.darkened(0.08), skin.plant_dark)
	_cone(pen, base + Vector3.UP * (height + 0.05), 0.13, 0.07, 8, skin.duct)
	pen.box(base + Vector3(-0.015, height, -0.015), base + Vector3(0.015, height + 0.05, 0.015), skin.duct)
	_shade_disc(shadows, at + light_shift * height * 0.5, 0.1, 0.22)


func _gooseneck(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2, spin: float) -> void:
	var xf: Transform3D = pen.xf
	pen.xf = xf * Transform3D(Basis(Vector3.UP, spin), Vector3(at.x, ROOF_Y, at.y))
	pen.box(Vector3(-0.09, 0.0, -0.09), Vector3(0.09, 0.32, 0.09), skin.duct)
	pen.box(Vector3(-0.09, 0.32, -0.09), Vector3(0.09, 0.5, 0.26), skin.duct.lightened(0.05))
	pen.box(Vector3(-0.1, 0.22, 0.12), Vector3(0.1, 0.4, 0.28), skin.duct.darkened(0.06))
	pen.xf = xf
	_shade_disc(shadows, at + light_shift * 0.35, 0.2, 0.24)


func _satellite_dish(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2) -> void:
	var base: Vector3 = Vector3(at.x, ROOF_Y, at.y)
	pen.box(base + Vector3(-0.15, 0.0, -0.15), base + Vector3(0.15, 0.08, 0.15), skin.parapet)
	pen.box(base + Vector3(-0.02, 0.08, -0.02), base + Vector3(0.02, 0.4, 0.02), skin.trim)
	# The dish tips up and away from the roof's middle (to the satellite).
	var away: Vector2 = (at - centre()).normalized()
	var aim: Vector3 = Vector3(away.x, 1.1, away.y).normalized()
	var side: Vector3 = aim.cross(Vector3.UP).normalized()
	var up: Vector3 = side.cross(aim).normalized()
	var mid: Vector3 = base + Vector3.UP * 0.45
	var radius: float = 0.24
	for index: int in 10:
		var a0: float = TAU * float(index) / 10.0
		var a1: float = TAU * float(index + 1) / 10.0
		var p0: Vector3 = mid + (side * cos(a0) + up * sin(a0)) * radius
		var p1: Vector3 = mid + (side * cos(a1) + up * sin(a1)) * radius
		pen.tri(mid - aim * 0.06, p0, p1, aim, skin.coping)
		pen.tri(mid - aim * 0.07, p1, p0, -aim, skin.plant)
	pen.box(mid + aim * 0.14 - Vector3(0.02, 0.02, 0.02), mid + aim * 0.14 + Vector3(0.02, 0.02, 0.02), skin.trim)
	_shade_disc(shadows, at + light_shift * 0.4, 0.26, 0.22)


## A slim mast in the corner opposite the water tower, its red light blinking at night.
func _mast(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var base: Vector3 = Vector3(mast.x, ROOF_Y, mast.y)
	pen.box(base + Vector3(-0.14, 0.0, -0.14), base + Vector3(0.14, 0.12, 0.14), skin.parapet)
	pen.box(base + Vector3(-0.03, 0.12, -0.03), base + Vector3(0.03, 4.5, 0.03), skin.coping)
	for y: float in [1.6, 2.8, 3.8]:
		pen.box(base + Vector3(-0.22, y, -0.012), base + Vector3(0.22, y + 0.025, 0.012), skin.coping)
	for y: float in [1.0, 2.0, 3.0, 4.0]:
		pen.box(base + Vector3(-0.035, y, -0.035), base + Vector3(0.035, y + 0.25, 0.035), skin.aircraft_red.darkened(0.15))
	pen.box(base + Vector3(-0.05, 4.5, -0.05), base + Vector3(0.05, 4.58, 0.05), skin.trim)
	_shade_rect(shadows, Rect2(mast - Vector2(0.03, 0.03), Vector2(0.06, 0.06)), 4.5, 0.18)


# --- the city ---------------------------------------------------------------

## A vertex-coloured triangle soup with a UV per vertex (the building's seed and window
## style for city.gdshader), turned into one mesh.
class CitySoup extends RefCounted:
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var uv: Vector2 = Vector2.ZERO

	func tri(a: Vector3, b: Vector3, c: Vector3, hint: Vector3, colour: Color) -> void:
		var cross: Vector3 = (b - a).cross(c - a)
		if cross.length_squared() < 0.0000000001:
			return
		var outward: Vector3 = cross.normalized()
		if outward.dot(hint) < 0.0:
			outward = -outward
		else:
			var swap: Vector3 = b
			b = c
			c = swap
		for point: Vector3 in [a, b, c]:
			positions.append(point)
			normals.append(outward)
			colors.append(colour)
			uvs.append(uv)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3, colour: Color) -> void:
		tri(a, b, c, hint, colour)
		tri(a, c, d, hint, colour)

	## An axis-aligned box: its sides in `side` (with `style` windows) and its top in `top`.
	func block(lo: Vector3, hi: Vector3, side: Color, top: Color, style: int, key: float) -> void:
		uv = Vector2(key, float(style))
		quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3.FORWARD, side)
		quad(Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.BACK, side)
		quad(Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3.RIGHT, side.darkened(0.04))
		quad(Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3.LEFT, side.darkened(0.04))
		uv = Vector2(key, 0.0)
		quad(Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, top)

	## A plain box with no windows, all one colour (clutter).
	func box(lo: Vector3, hi: Vector3, colour: Color) -> void:
		block(lo, hi, colour, colour.lightened(0.05), 0, 0.0)

	func flat(x0: float, z0: float, x1: float, z1: float, y: float, colour: Color) -> void:
		uv = Vector2.ZERO
		quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, colour)

	func lump(centre: Vector3, rx: float, ry: float, rz: float, spin: float, top: Color, bottom: Color) -> void:
		uv = Vector2.ZERO
		var ring: Array[Vector3] = []
		for index: int in 6:
			var angle: float = spin + TAU * float(index) / 6.0
			ring.append(centre + Vector3(cos(angle) * rx, 0.0, sin(angle) * rz))
		var peak: Vector3 = centre + Vector3.UP * ry
		var base: Vector3 = centre - Vector3.UP * ry * 0.55
		for index: int in 6:
			var next: int = (index + 1) % 6
			var middle: Vector3 = (ring[index] + ring[next]) * 0.5 - centre
			tri(ring[index], ring[next], peak, middle + Vector3.UP * 0.5, top)
			tri(ring[next], ring[index], base, middle - Vector3.UP * 0.5, bottom)

	func drum(base: Vector3, radius: float, height: float, sides: int, side: Color, top: Color) -> void:
		uv = Vector2.ZERO
		for index: int in sides:
			var a0: float = TAU * float(index) / float(sides)
			var a1: float = TAU * float(index + 1) / float(sides)
			var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0)) * radius
			var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1)) * radius
			quad(base + d0, base + d1, base + d1 + Vector3.UP * height, base + d0 + Vector3.UP * height, d0 + d1, side)
			tri(base + Vector3.UP * height, base + d0 + Vector3.UP * height, base + d1 + Vector3.UP * height, Vector3.UP, top)

	func to_mesh() -> ArrayMesh:
		var mesh: ArrayMesh = ArrayMesh.new()
		if positions.is_empty():
			return mesh
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## The tower under the roof: its four faces of glass curtain wall from the parapet down
## to the street, a cornice band under the parapet, and a plinth at the bottom.
func _our_tower(soup: CitySoup) -> void:
	var depth: float = skin.street_depth
	var r: Rect2 = roof
	var glass: Color = skin.tower_glass[0]
	soup.block(Vector3(r.position.x + 0.02, -depth, r.position.y + 0.02), Vector3(r.end.x - 0.02, -0.55, r.end.y - 0.02), glass, glass, 2, 0.731)
	# Spandrel bands every few floors, and the cornice: the parapet's face carried down.
	soup.block(Vector3(r.position.x - 0.06, -0.55, r.position.y - 0.06), Vector3(r.end.x + 0.06, -0.3, r.end.y + 0.06), skin.parapet.darkened(0.08), skin.parapet, 0, 0.0)
	var band: float = -0.55 - 1.4 * 4.0
	while band > -depth + 3.0:
		soup.block(Vector3(r.position.x - 0.03, band - 0.18, r.position.y - 0.03), Vector3(r.end.x + 0.03, band, r.end.y + 0.03), skin.parapet.darkened(0.12), skin.parapet, 0, 0.0)
		band -= 1.4 * 6.0
	soup.block(Vector3(r.position.x - 0.5, -depth, r.position.y - 0.5), Vector3(r.end.x + 0.5, -depth + 2.6, r.end.y + 0.5), skin.parapet.darkened(0.1), skin.parapet, 0, 0.0)


## The city's blocks between its streets, each split into a few buildings, laid out
## round the tower's own block. Fills `lots`. Deterministic from the salt and the roof.
func _plan_city() -> void:
	lots.clear()
	var c: Vector2 = centre()
	var reach: float = skin.city_reach
	# The tower's own block runs a few metres past it on every side.
	var block0: Rect2 = roof.grow_individual(3.5 + 5.0 * _r(201, 1), 3.5 + 5.0 * _r(201, 2), 3.5 + 5.0 * _r(201, 3), 3.5 + 5.0 * _r(201, 4))
	var columns: Array[Vector2] = _intervals(block0.position.x, block0.end.x, c.x - reach, c.x + reach, 211)
	var rows: Array[Vector2] = _intervals(block0.position.y, block0.end.y, c.y - reach, c.y + reach, 223)
	for i: int in columns.size():
		for j: int in rows.size():
			var block: Rect2 = Rect2(columns[i].x, rows[j].x, columns[i].y - columns[i].x, rows[j].y - rows[j].x)
			if block.is_equal_approx(block0):
				_split_round_tower(block)
			else:
				_split_block(block, i * 53 + j * 7 + 1)
	_choose_kinds()


## Block intervals along one axis: the tower's own block, then blocks of 16 to 28 m with
## a street between, out to the city's reach on both sides.
func _intervals(start: float, end: float, low: float, high: float, seed_value: int) -> Array[Vector2]:
	var result: Array[Vector2] = [Vector2(start, end)]
	var at: float = end + STREET_W
	var index: int = 0
	while at < high:
		var width: float = 16.0 + 12.0 * _r(seed_value, index)
		result.append(Vector2(at, at + width))
		at += width + STREET_W + 2.0 * _r(seed_value + 1, index)
		index += 1
	at = start - STREET_W
	while at > low:
		var width: float = 16.0 + 12.0 * _r(seed_value + 2, index)
		result.append(Vector2(at - width, at))
		at -= width + STREET_W + 2.0 * _r(seed_value + 3, index)
		index += 1
	return result


## The tower's block: lower buildings in the strips round it, a gap between.
func _split_round_tower(block: Rect2) -> void:
	var t: Rect2 = roof.grow(0.7)
	var strips: Array[Rect2] = [Rect2(block.position.x, block.position.y, t.position.x - block.position.x, block.size.y),
		Rect2(t.end.x, block.position.y, block.end.x - t.end.x, block.size.y),
		Rect2(t.position.x, block.position.y, t.size.x, t.position.y - block.position.y),
		Rect2(t.position.x, t.end.y, t.size.x, block.end.y - t.end.y)]
	for index: int in strips.size():
		var strip: Rect2 = strips[index]
		if strip.size.x < 2.5 or strip.size.y < 2.5:
			continue
		var long_u: bool = strip.size.x > strip.size.y
		var length: float = strip.size.x if long_u else strip.size.y
		var pieces: int = clampi(int(length / 9.0), 1, 3)
		for piece: int in pieces:
			var a: float = float(piece) / float(pieces)
			var b: float = float(piece + 1) / float(pieces)
			var part: Rect2 = Rect2(strip.position.x + strip.size.x * a, strip.position.y, strip.size.x * (b - a), strip.size.y) if long_u \
				else Rect2(strip.position.x, strip.position.y + strip.size.y * a, strip.size.x, strip.size.y * (b - a))
			_add_lot(part.grow(-0.2), index * 11 + piece + 900, true)


## A block split into one to four buildings, by hash.
func _split_block(block: Rect2, seed_value: int) -> void:
	var pick: float = _r(seed_value, 301)
	var parts: Array[Rect2] = []
	if pick < 0.18:
		parts.append(block)
	elif pick < 0.55:
		var t: float = 0.35 + 0.3 * _r(seed_value, 302)
		if block.size.x > block.size.y:
			parts.append(Rect2(block.position, Vector2(block.size.x * t, block.size.y)))
			parts.append(Rect2(block.position.x + block.size.x * t, block.position.y, block.size.x * (1.0 - t), block.size.y))
		else:
			parts.append(Rect2(block.position, Vector2(block.size.x, block.size.y * t)))
			parts.append(Rect2(block.position.x, block.position.y + block.size.y * t, block.size.x, block.size.y * (1.0 - t)))
	else:
		var tx: float = 0.35 + 0.3 * _r(seed_value, 303)
		var tz: float = 0.35 + 0.3 * _r(seed_value, 304)
		var x: float = block.position.x + block.size.x * tx
		var z: float = block.position.y + block.size.y * tz
		parts.append(Rect2(block.position.x, block.position.y, x - block.position.x, z - block.position.y))
		parts.append(Rect2(x, block.position.y, block.end.x - x, z - block.position.y))
		parts.append(Rect2(block.position.x, z, x - block.position.x, block.end.y - z))
		parts.append(Rect2(x, z, block.end.x - x, block.end.y - z))
	for index: int in parts.size():
		var gap: float = 0.25 if _r(seed_value + index, 305) < 0.5 else 0.0
		_add_lot(parts[index].grow(-gap), seed_value * 5 + index, false)


func _add_lot(rect: Rect2, seed_value: int, beside_tower: bool) -> void:
	var lot: Lot = Lot.new()
	lot.rect = rect
	lot.tone_seed = _r(seed_value, 311)
	var distance: float = rect.get_center().distance_to(centre())
	var tall: bool = not beside_tower and distance > 36.0 and _r(seed_value, 312) < 0.17
	if beside_tower:
		lot.top = -3.2 - 10.0 * _r(seed_value, 313)
	elif tall:
		lot.top = TOWER_TOP - 3.5 * _r(seed_value, 313)
		lot.kind = &"tower"
	elif distance < NEAR:
		lot.top = -5.0 - 15.0 * _r(seed_value, 313)
	elif _r(seed_value, 318) < 0.22:
		# Mid-rise blocks that come up nearly to the roof, out past the near ring.
		lot.top = -2.5 - 5.0 * _r(seed_value, 313)
	else:
		lot.top = -6.0 - 24.0 * pow(_r(seed_value, 313), 0.8)
	lot.cap = rect
	if not tall and not beside_tower and rect.size.x > 9.0 and rect.size.y > 9.0 and _r(seed_value, 319) < 0.4:
		lot.step = 2.8 + 3.0 * _r(seed_value, 320)
		lot.cap = rect.grow(-(1.4 + 1.6 * _r(seed_value, 321)))
	lot.detail = 0 if distance < NEAR else (1 if distance < MID else 2)
	var glass: bool = tall or _r(seed_value, 314) < 0.25
	if glass:
		lot.colour = skin.tower_glass[int(_r(seed_value, 315) * 97.0) % skin.tower_glass.size()]
		lot.style = 2
	else:
		lot.colour = skin.facade_colors[int(_r(seed_value, 315) * 97.0) % skin.facade_colors.size()]
		lot.style = 1 if _r(seed_value, 316) < 0.6 else 3
	lot.roof = skin.roof_colors[int(_r(seed_value, 317) * 97.0) % skin.roof_colors.size()]
	lots.append(lot)


## What stands on the near roofs: one helipad (the smallest near roof well below us
## that fits one, so it never fills the view),
## gardens and plant on the rest.
func _choose_kinds() -> void:
	var best: int = -1
	for index: int in lots.size():
		var lot: Lot = lots[index]
		if lot.detail != 0 or lot.kind != &"" or lot.top > -5.0 or lot.cap.size.x < 7.0 or lot.cap.size.y < 7.0:
			continue
		if best < 0 or lot.cap.get_area() < lots[best].cap.get_area():
			best = index
	for index: int in lots.size():
		var lot: Lot = lots[index]
		if lot.kind != &"" or lot.detail > 0:
			continue
		if index == best:
			lot.kind = &"helipad"
		elif _r(index, 321) < 0.4 and lot.cap.size.x > 3.0 and lot.cap.size.y > 3.0:
			lot.kind = &"garden"
		else:
			lot.kind = &"plant"


## One building: its box with windows, then what its level of detail allows on top.
func _city_lot(soup: CitySoup, lot: Lot, beacons: Array[Vector3]) -> void:
	var r: Rect2 = lot.rect
	var top: float = lot.top
	var bottom: float = -skin.street_depth
	if lot.kind == &"tower":
		# Setbacks: the shaft, a narrower crown and a spire with an aircraft light.
		var crown: Rect2 = r.grow(-minf(r.size.x, r.size.y) * 0.18)
		var shaft_top: float = top - 5.0
		soup.block(Vector3(r.position.x, bottom, r.position.y), Vector3(r.end.x, shaft_top, r.end.y), lot.colour, lot.roof, lot.style, lot.tone_seed)
		soup.block(Vector3(crown.position.x, shaft_top, crown.position.y), Vector3(crown.end.x, top, crown.end.y), lot.colour.lightened(0.05), lot.roof, lot.style, lot.tone_seed)
		var c: Vector2 = crown.get_center()
		soup.block(Vector3(c.x - 1.2, top, c.y - 1.2), Vector3(c.x + 1.2, top + 1.2, c.y + 1.2), lot.roof.darkened(0.1), lot.roof, 0, 0.0)
		var spire: float = top + 3.0 + 4.0 * lot.tone_seed
		soup.box(Vector3(c.x - 0.12, top + 1.2, c.y - 0.12), Vector3(c.x + 0.12, spire, c.y + 0.12), skin.coping)
		beacons.append(Vector3(c.x, spire + 0.15, c.y))
		for corner: Vector2 in [crown.position, Vector2(crown.end.x, crown.position.y), crown.end, Vector2(crown.position.x, crown.end.y)]:
			beacons.append(Vector3(corner.x, top + 0.3, corner.y) + Vector3((c.x - corner.x) * 0.05, 0.0, (c.y - corner.y) * 0.05))
		return
	if lot.step > 0.0:
		# A setback: the block, a ledge with a rim, then the narrower crown above it.
		var ledge: float = top - lot.step
		soup.block(Vector3(r.position.x, bottom, r.position.y), Vector3(r.end.x, ledge, r.end.y), lot.colour, lot.roof, lot.style, lot.tone_seed)
		soup.block(Vector3(r.position.x - 0.08, ledge, r.position.y - 0.08), Vector3(r.end.x + 0.08, ledge + 0.3, r.end.y + 0.08), lot.roof.lightened(0.12), lot.roof.lightened(0.08), 0, 0.0)
		r = lot.cap
		soup.block(Vector3(r.position.x, ledge, r.position.y), Vector3(r.end.x, top, r.end.y), lot.colour.lightened(0.04), lot.roof, lot.style, lot.tone_seed)
	else:
		soup.block(Vector3(r.position.x, bottom, r.position.y), Vector3(r.end.x, top, r.end.y), lot.colour, lot.roof, lot.style, lot.tone_seed)
	if lot.detail >= 2:
		return
	# A rim round the roof, a patch of newer membrane, and the stair housing.
	var patch: Rect2 = r.grow(-0.5)
	if patch.size.x > 2.0 and patch.size.y > 2.0:
		var cut: float = 0.3 + 0.4 * _r(int(lot.tone_seed * 977.0), 335)
		if r.size.x > r.size.y:
			soup.flat(patch.position.x, patch.position.y, patch.position.x + patch.size.x * cut, patch.end.y, top + 0.02, lot.roof.darkened(0.05))
		else:
			soup.flat(patch.position.x, patch.position.y, patch.end.x, patch.position.y + patch.size.y * cut, top + 0.02, lot.roof.darkened(0.05))
	var rim: Color = lot.roof.lightened(0.1)
	var t: float = 0.22
	soup.box(Vector3(r.position.x, top, r.position.y), Vector3(r.end.x, top + 0.35, r.position.y + t), rim)
	soup.box(Vector3(r.position.x, top, r.end.y - t), Vector3(r.end.x, top + 0.35, r.end.y), rim)
	soup.box(Vector3(r.position.x, top, r.position.y + t), Vector3(r.position.x + t, top + 0.35, r.end.y - t), rim)
	soup.box(Vector3(r.end.x - t, top, r.position.y + t), Vector3(r.end.x, top + 0.35, r.end.y - t), rim)
	var corner: Vector2 = r.position + Vector2(0.6, 0.6) + Vector2(_r(int(lot.tone_seed * 1000.0), 331), _r(int(lot.tone_seed * 1000.0), 332)) * (r.size - Vector2(2.4, 2.0)).max(Vector2.ZERO)
	if r.size.x > 3.0 and r.size.y > 3.0 and lot.kind != &"helipad":
		soup.block(Vector3(corner.x, top, corner.y), Vector3(corner.x + 1.6, top + 1.25, corner.y + 1.2), lot.colour.lightened(0.06), lot.roof.darkened(0.08), 0, 0.0)
	var s: int = int(lot.tone_seed * 10000.0)
	if lot.detail >= 1:
		# Mid-distance roofs: a box of plant or two, no more.
		for index: int in clampi(int(r.get_area() / 40.0), 2, 6):
			var p: Vector2 = r.position + Vector2(0.5, 0.5) + Vector2(_r(s + index, 361), _r(s + index, 362)) * (r.size - Vector2(2.2, 1.8)).max(Vector2.ZERO)
			if not Rect2(corner, Vector2(1.6, 1.2)).grow(0.3).intersects(Rect2(p, Vector2(1.2, 0.9))):
				soup.box(Vector3(p.x, top, p.y), Vector3(p.x + 1.2, top + 0.6, p.y + 0.9), skin.plant)
		return
	match lot.kind:
		&"helipad":
			_helipad(soup, lot)
		&"garden":
			_garden(soup, lot, s)
		_:
			_rooftop_plant(soup, lot, s, corner)


func _helipad(soup: CitySoup, lot: Lot) -> void:
	var c: Vector2 = lot.cap.get_center()
	var top: float = lot.top
	var half: float = minf(minf(lot.cap.size.x, lot.cap.size.y) * 0.5 - 0.8, 4.6)
	soup.box(Vector3(c.x - half, top, c.y - half), Vector3(c.x + half, top + 0.12, c.y + half), skin.helipad)
	var y: float = top + 0.125
	# The yellow-white ring and the H.
	var ring_out: float = half * 0.82
	var ring_in: float = half * 0.72
	for index: int in 20:
		var a0: float = TAU * float(index) / 20.0
		var a1: float = TAU * float(index + 1) / 20.0
		soup.quad(Vector3(c.x + cos(a0) * ring_in, y, c.y + sin(a0) * ring_in), Vector3(c.x + cos(a1) * ring_in, y, c.y + sin(a1) * ring_in),
			Vector3(c.x + cos(a1) * ring_out, y, c.y + sin(a1) * ring_out), Vector3(c.x + cos(a0) * ring_out, y, c.y + sin(a0) * ring_out), Vector3.UP, skin.helipad_mark)
	var h: float = half * 0.38
	soup.flat(c.x - h, c.y - h, c.x - h * 0.62, c.y + h, y, skin.helipad_mark)
	soup.flat(c.x + h * 0.62, c.y - h, c.x + h, c.y + h, y, skin.helipad_mark)
	soup.flat(c.x - h * 0.62, c.y - h * 0.16, c.x + h * 0.62, c.y + h * 0.16, y, skin.helipad_mark)
	# Edge lights round the pad (glow at night through the street-light sprites).
	_pad_lights.append(Vector4(c.x, top + 0.25, c.y, half))


var _pad_lights: Array[Vector4] = []
## The pools of lamplight on the roof and decks (street-local, y on the ground under them).
var _lamp_spots: Array[Vector3] = []


## The roof's lamps (street-local, y on the ground they light): they shine on it when wet.
func lamp_spots() -> Array[Vector3]:
	return _lamp_spots.duplicate()


func _garden(soup: CitySoup, lot: Lot, s: int) -> void:
	var inner: Rect2 = lot.cap.grow(-0.5)
	var top: float = lot.top
	soup.flat(inner.position.x, inner.position.y, inner.end.x, inner.end.y, top + 0.03, skin.lawn)
	# A path across, then shrubs and small trees round the lawn's edge.
	var across_u: bool = inner.size.x > inner.size.y
	var mid: Vector2 = inner.get_center()
	if across_u:
		soup.flat(inner.position.x, mid.y - 0.4, inner.end.x, mid.y + 0.4, top + 0.05, skin.paver)
	else:
		soup.flat(mid.x - 0.4, inner.position.y, mid.x + 0.4, inner.end.y, top + 0.05, skin.paver)
	var count: int = clampi(int(inner.get_area() / 5.0), 3, 14)
	for index: int in count:
		var p: Vector2 = inner.position + Vector2(_r(s + index, 341), _r(s + index, 342)) * inner.size
		if (across_u and absf(p.y - mid.y) < 0.9) or (not across_u and absf(p.x - mid.x) < 0.9):
			continue
		var leaf: Color = skin.leaf_colors[(s + index) % skin.leaf_colors.size()]
		if index % 3 == 0:
			soup.box(Vector3(p.x - 0.06, top, p.y - 0.06), Vector3(p.x + 0.06, top + 1.0, p.y + 0.06), skin.trunk)
			soup.lump(Vector3(p.x, top + 1.25, p.y), 0.7, 0.6, 0.7, _r(s + index, 343), leaf.lightened(0.05), leaf.darkened(0.15))
		else:
			soup.lump(Vector3(p.x, top + 0.3, p.y), 0.45, 0.35, 0.45, _r(s + index, 343), leaf, leaf.darkened(0.12))


func _rooftop_plant(soup: CitySoup, lot: Lot, s: int, housing: Vector2) -> void:
	var inner: Rect2 = lot.cap.grow(-0.7)
	var top: float = lot.top
	var count: int = clampi(int(inner.get_area() / 4.0), 2, 14)
	for index: int in count:
		var p: Vector2 = inner.position + Vector2(_r(s + index, 351), _r(s + index, 352)) * (inner.size - Vector2(1.2, 1.0)).max(Vector2.ZERO)
		if Rect2(housing, Vector2(1.6, 1.2)).grow(0.4).intersects(Rect2(p, Vector2(1.2, 0.9))):
			continue
		if index % 3 == 2 and inner.size.x > 3.0:
			# A small water tank on legs.
			var c: Vector3 = Vector3(p.x + 0.6, top, p.y + 0.5)
			for dx: float in [-0.4, 0.4]:
				for dz: float in [-0.4, 0.4]:
					soup.box(c + Vector3(dx - 0.05, 0.0, dz - 0.05), c + Vector3(dx + 0.05, 0.8, dz + 0.05), skin.trim)
			soup.drum(c + Vector3.UP * 0.8, 0.6, 1.0, 10, skin.tank_wood, skin.tank_roof)
		else:
			soup.box(Vector3(p.x, top, p.y), Vector3(p.x + 1.2, top + 0.6, p.y + 0.9), skin.plant)
			soup.drum(Vector3(p.x + 0.6, top + 0.6, p.y + 0.45), 0.3, 0.04, 8, skin.plant_dark, skin.plant_dark.darkened(0.2))


## The streets and pavements at the bottom: one ground plane in street colour, and a
## low kerbed pavement round every block.
func _streets(soup: CitySoup) -> void:
	var c: Vector2 = centre()
	var reach: float = skin.city_reach + 80.0
	var y: float = -skin.street_depth
	soup.flat(c.x - reach, c.y - reach, c.x + reach, c.y + reach, y, skin.street)
	var blocks: Dictionary[Rect2, bool] = {}
	for lot: Lot in lots:
		blocks[lot.rect.grow(1.6)] = true
	for rect: Rect2 in blocks:
		soup.box(Vector3(rect.position.x, y, rect.position.y), Vector3(rect.end.x, y + 0.15, rect.end.y), skin.pavement)


## Street lights along every street far below, and the helipads' edge lights.
func _street_light_sprites() -> ArrayMesh:
	var points: Array[Vector3] = []
	var sizes: Array[float] = []
	var tints: Array[Color] = []
	var c: Vector2 = centre()
	var reach: float = skin.city_reach * 0.85
	var y: float = -skin.street_depth + 1.4
	for line: Vector3 in _street_lines():
		var along_u: bool = line.z > 0.5
		var at: float = (c.x if along_u else c.y) - reach
		while at < (c.x if along_u else c.y) + reach:
			for side: float in [-1.0, 1.0]:
				var across: float = line.x + side * (STREET_W * 0.5 - 0.6)
				points.append(Vector3(at, y, across) if along_u else Vector3(across, y, at))
				sizes.append(2.6)
				tints.append(skin.street_glow)
			at += 9.0
	for pad: Vector4 in _pad_lights:
		for index: int in 12:
			var angle: float = TAU * float(index) / 12.0
			points.append(Vector3(pad.x + cos(angle) * pad.w, pad.y, pad.z + sin(angle) * pad.w))
			sizes.append(0.7)
			tints.append(skin.lamp_glow if index % 2 == 0 else skin.headlight)
	return _sprites(points, sizes, tints, [] as Array[float])


## The streets' centre lines: x is the line's across position, z 1 for a street along u
## (its across is z) and 0 for one along z.
func _street_lines() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var block0: Rect2 = roof.grow_individual(3.5 + 5.0 * _r(201, 1), 3.5 + 5.0 * _r(201, 2), 3.5 + 5.0 * _r(201, 3), 3.5 + 5.0 * _r(201, 4))
	var c: Vector2 = centre()
	var reach: float = skin.city_reach * 0.85
	var columns: Array[Vector2] = _intervals(block0.position.x, block0.end.x, c.x - skin.city_reach, c.x + skin.city_reach, 211)
	var rows: Array[Vector2] = _intervals(block0.position.y, block0.end.y, c.y - skin.city_reach, c.y + skin.city_reach, 223)
	for column: Vector2 in columns:
		for edge: float in [column.x - STREET_W * 0.5, column.y + STREET_W * 0.5]:
			if absf(edge - c.x) < reach:
				result.append(Vector3(edge, 0.0, 0.0))
	for row: Vector2 in rows:
		for edge: float in [row.x - STREET_W * 0.5, row.y + STREET_W * 0.5]:
			if absf(edge - c.y) < reach:
				result.append(Vector3(edge, 0.0, 1.0))
	# Each street lies between two blocks: drop the doubles.
	var unique: Array[Vector3] = []
	for line: Vector3 in result:
		var seen: bool = false
		for other: Vector3 in unique:
			if is_equal_approx(other.z, line.z) and absf(other.x - line.x) < STREET_W * 0.6:
				seen = true
				break
		if not seen:
			unique.append(line)
	return unique


## Cars on the streets far below: a pair of headlights or tail lights each, driving
## both ways (the glow shader moves them).
func _traffic_sprites() -> ArrayMesh:
	var points: Array[Vector3] = []
	var sizes: Array[float] = []
	var tints: Array[Color] = []
	var axes: Array[float] = []
	var c: Vector2 = centre()
	var y: float = -skin.street_depth + 0.45
	var lines: Array[Vector3] = _street_lines()
	for index: int in lines.size():
		var line: Vector3 = lines[index]
		var along_u: bool = line.z > 0.5
		for car: int in 6:
			var forward: bool = car % 2 == 0
			var lane: float = line.x + (1.2 if forward else -1.2)
			var base: Vector3 = Vector3(c.x, y, lane) if along_u else Vector3(lane, y, c.y)
			var axis: float = (0.1 if forward else 0.4) if along_u else (0.6 if forward else 0.9)
			var tint: Color = skin.headlight if car % 4 < 2 else skin.taillight
			for lamp: int in 2:
				var offset: Vector3 = (Vector3(0.0, 0.0, 0.3) if along_u else Vector3(0.3, 0.0, 0.0)) * (float(lamp) * 2.0 - 1.0)
				points.append(base + offset)
				sizes.append(1.3)
				tints.append(tint)
				axes.append(axis)
	return _sprites(points, sizes, tints, axes)


## Distant clouds (#618): a few chunky puffs each, drifting along u (UV2: home, speed),
## in two bands far off on either side of the tower (z), never under the roof itself.
func _clouds() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var colours: PackedColorArray = PackedColorArray()
	var uv2s: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var c: Vector2 = centre()
	for index: int in skin.clouds:
		var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		var home: float = c.x + (_r(index, 401) - 0.5) * 160.0
		var size: float = 2.2 + 1.8 * _r(index, 404)
		# Alternate sides; the puffs reach about `size` across, so keep that inside the band.
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var near: float = roof.size.y * 0.5 + CLOUD_GAP + size
		var z: float = c.y + side * lerpf(near, near + CLOUD_BAND - size * 2.0, _r(index, 402))
		var y: float = lerpf(CLOUD_HIGH, CLOUD_LOW, _r(index, 403))
		var puffs: int = 7 + int(_r(index, 405) * 5.0)
		for puff: int in puffs:
			var t: float = float(puff) / float(puffs - 1) - 0.5
			var k: int = index * 13 + puff
			var at: Vector3 = Vector3(home + t * size * 2.2 + (_r(k, 409) - 0.5) * size * 0.3, y,
				z + (_r(k, 406) - 0.5) * size * 0.9 * (1.0 - absf(t)))
			var r: float = size * (0.5 - absf(t) * 0.42) * (0.75 + 0.5 * _r(k, 407))
			_puff(pen, at, r, _r(k, 408) * TAU)
		var speed: float = 0.35 + 0.4 * _r(index, 409)
		vertices.append_array(pen.soup.positions)
		normals.append_array(pen.soup.normals)
		colours.append_array(pen.soup.colors)
		for vertex: int in pen.soup.positions.size():
			uv2s.append(Vector2(home, speed))
	var mesh: ArrayMesh = ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- small pieces -----------------------------------------------------------

## A rounded cloud puff: a flat shaded belly, two rings of sides and a lit dome.
func _puff(pen: NeighbourhoodBuildings.Pen, at: Vector3, r: float, spin: float) -> void:
	var sides: int = 8
	var rings: Array[Vector3] = [Vector3(0.82, 0.0, 0.0), Vector3(1.0, 0.32, 0.0), Vector3(0.78, 0.68, 0.0), Vector3(0.38, 0.92, 0.0)]
	var tones: Array[Color] = [skin.cloud_shade, skin.cloud_shade.lerp(skin.cloud, 0.6), skin.cloud, skin.cloud]
	for index: int in sides:
		var a0: float = spin + TAU * float(index) / float(sides)
		var a1: float = spin + TAU * float(index + 1) / float(sides)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0) * 0.8)
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1) * 0.8)
		pen.tri(at, at + d1 * r * rings[0].x, at + d0 * r * rings[0].x, Vector3.DOWN, skin.cloud_shade.darkened(0.04))
		for ring: int in rings.size() - 1:
			var lo: Vector3 = rings[ring]
			var hi: Vector3 = rings[ring + 1]
			pen.quad(at + d0 * r * lo.x + Vector3.UP * r * lo.y, at + d1 * r * lo.x + Vector3.UP * r * lo.y,
				at + d1 * r * hi.x + Vector3.UP * r * hi.y, at + d0 * r * hi.x + Vector3.UP * r * hi.y, d0 + d1 + Vector3.UP * float(ring), tones[ring + 1])
		var top: Vector3 = at + Vector3.UP * r
		pen.tri(at + d0 * r * rings[3].x + Vector3.UP * r * rings[3].y, at + d1 * r * rings[3].x + Vector3.UP * r * rings[3].y, top, Vector3.UP, skin.cloud)

## A rim of four low walls round `rect`, `t` thick, from `y0` to `y1`.
func _rim(pen: NeighbourhoodBuildings.Pen, rect: Rect2, y0: float, y1: float, t: float, colour: Color) -> void:
	pen.box(Vector3(rect.position.x, y0, rect.position.y), Vector3(rect.end.x, y1, rect.position.y + t), colour)
	pen.box(Vector3(rect.position.x, y0, rect.end.y - t), Vector3(rect.end.x, y1, rect.end.y), colour)
	pen.box(Vector3(rect.position.x, y0, rect.position.y + t), Vector3(rect.position.x + t, y1, rect.end.y - t), colour)
	pen.box(Vector3(rect.end.x - t, y0, rect.position.y + t), Vector3(rect.end.x, y1, rect.end.y - t), colour)


func _drum(pen: NeighbourhoodBuildings.Pen, base: Vector3, r0: float, r1: float, height: float, sides: int, side: Color, top: Color) -> void:
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		pen.quad(base + d0 * r0, base + d1 * r0, base + d1 * r1 + Vector3.UP * height, base + d0 * r1 + Vector3.UP * height, (d0 + d1) * 0.5, side)
		pen.tri(base + Vector3.UP * height, base + d0 * r1 + Vector3.UP * height, base + d1 * r1 + Vector3.UP * height, Vector3.UP, top)


func _cone(pen: NeighbourhoodBuildings.Pen, base: Vector3, radius: float, height: float, sides: int, colour: Color) -> void:
	var peak: Vector3 = base + Vector3.UP * height
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var p0: Vector3 = base + Vector3(cos(a0), 0.0, sin(a0)) * radius
		var p1: Vector3 = base + Vector3(cos(a1), 0.0, sin(a1)) * radius
		pen.tri(p0, p1, peak, (p0 + p1) * 0.5 - base + Vector3.UP * radius, colour if index % 2 == 0 else colour.darkened(0.05))
		pen.tri(p1, p0, base, Vector3.DOWN, colour.darkened(0.2))


func _shade_disc(shadows: NeighbourhoodGround.Soup, at: Vector2, radius: float, alpha: float) -> void:
	var points: Array[Vector2] = []
	for index: int in 8:
		var angle: float = TAU * float(index) / 8.0
		points.append(at + Vector2(cos(angle), sin(angle) * 0.8) * radius)
	shadows.star(at, points, SHADOW_Y, Color(0.08, 0.08, 0.1, alpha))


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
	var middle: Vector2 = rect.get_center() + push * 0.5
	# Shadows stay on the roof: clip the far side at the parapet.
	for index: int in points.size():
		points[index] = points[index].clamp(roof.position, roof.end)
	shadows.star(middle.clamp(roof.position, roof.end), points, SHADOW_Y, Color(0.08, 0.08, 0.1, alpha))


## A soft additive pool of light on the floor, brightest in the middle (night only).
func _pool(soup: NeighbourhoodGround.Soup, at: Vector2, half: Vector2, colour: Color, strength: float, y: float = POOL_Y) -> void:
	_lamp_spots.append(Vector3(at.x, y, at.y))
	var rings: int = 5
	var sides: int = 14
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		for ring: int in rings:
			var r0: float = float(ring) / float(rings)
			var r1: float = float(ring + 1) / float(rings)
			var c0: Color = Color(colour, pow(1.0 - r0, 1.6) * strength)
			var c1: Color = Color(colour, pow(1.0 - r1, 1.6) * strength)
			var p: Array[Vector3] = [Vector3(at.x + cos(a0) * half.x * r0, y, at.y + sin(a0) * half.y * r0),
				Vector3(at.x + cos(a1) * half.x * r0, y, at.y + sin(a1) * half.y * r0),
				Vector3(at.x + cos(a1) * half.x * r1, y, at.y + sin(a1) * half.y * r1),
				Vector3(at.x + cos(a0) * half.x * r1, y, at.y + sin(a0) * half.y * r1)]
			var colours: Array[Color] = [c0, c0, c1, c1]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				soup.positions.append(p[corner])
				soup.normals.append(Vector3.UP)
				soup.colors.append(colours[corner])


## One quad per light, all four corners at its centre; the glow shader spreads them.
## `tints` (COLOR.rgb) and `axes` (COLOR.a, a car's direction) may be empty.
func _sprites(points: Array[Vector3], sizes: Array[float], tints: Array[Color], axes: Array[float]) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var uv2s: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colours: PackedColorArray = PackedColorArray()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for index: int in points.size():
		var tint: Color = tints[index] if index < tints.size() else skin.lamp_glow
		tint.a = axes[index] if index < axes.size() else 1.0
		for corner: Vector2 in corners:
			vertices.append(points[index])
			normals.append(Vector3.UP)
			uvs.append(corner)
			uv2s.append(Vector2(sizes[index], float(index) * 0.618 + 0.13))
			colours.append(tint)
	var mesh: ArrayMesh = ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- life: fans, pigeons, birds and the plane --------------------------------

func _build_fans() -> void:
	fans.clear()
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	for blade: int in 4:
		var angle: float = TAU * float(blade) / 4.0
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var across: Vector3 = Vector3(-out.z, 0.0, out.x)
		pen.quad(out * 0.03 - across * 0.035, out * 0.2 - across * 0.05, out * 0.2 + across * 0.05 + Vector3.UP * 0.01,
			out * 0.03 + across * 0.035 + Vector3.UP * 0.01, Vector3.UP, skin.plant_dark.darkened(0.1))
	var mesh: ArrayMesh = pen.soup.to_mesh()
	var holder: Node3D = Node3D.new()
	holder.name = "Fans"
	root.add_child(holder)
	# The spots are found while the static meshes are built; a cached build re-plans them.
	if _fan_spots.is_empty():
		var scratch: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		_plant(scratch, NeighbourhoodGround.Soup.new())
	for index: int in _fan_spots.size():
		var fan: MeshInstance3D = _instance("Fan%d" % index, mesh, _material)
		fan.position = _fan_spots[index]
		holder.add_child(fan)
		fans.append(fan)


## Pigeons sit along the parapet's coping: a body, a neck with its sheen, a head that
## pecks and looks round, and tail feathers.
func _build_pigeons() -> void:
	pigeons.clear()
	_pigeon_spots.clear()
	var holder: Node3D = Node3D.new()
	holder.name = "Pigeons"
	root.add_child(holder)
	var line: Rect2 = roof.grow(-PARAPET_T * 0.5)
	var y: float = PARAPET_H + COPING
	for index: int in skin.pigeons:
		# Front parapet first (the terrace side), then the two sides.
		var spot: Vector2
		var facing: float
		match index % 3:
			0:
				spot = Vector2(lerpf(line.position.x + 0.6, line.end.x - 0.6, _r(index, 501)), line.end.y)
				facing = PI * 0.5
			1:
				spot = Vector2(line.position.x, lerpf(shift + 0.5, line.end.y - 0.5, _r(index, 501)))
				facing = 0.0
			_:
				spot = Vector2(line.end.x, lerpf(shift + 0.5, line.end.y - 0.5, _r(index, 501)))
				facing = PI
		_pigeon_spots.append(Vector4(spot.x, y, spot.y, facing + (_r(index, 502) - 0.5) * 1.2))
		var bird_node: Node3D = Node3D.new()
		bird_node.name = "Pigeon%d" % index
		var body: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		body.lump(Vector3(0.0, 0.055, 0.0), 0.045, 0.05, 0.075, 0.0, skin.pigeon, skin.pigeon.darkened(0.15))
		body.tri(Vector3(-0.03, 0.06, -0.06), Vector3(0.03, 0.06, -0.06), Vector3(0.0, 0.05, -0.14), Vector3.UP, skin.pigeon.darkened(0.25))
		body.box(Vector3(-0.012, 0.0, -0.005), Vector3(-0.004, 0.025, 0.005), skin.taillight.darkened(0.3))
		body.box(Vector3(0.004, 0.0, -0.005), Vector3(0.012, 0.025, 0.005), skin.taillight.darkened(0.3))
		var body_mesh: MeshInstance3D = _instance("Body", body.soup.to_mesh(), _material)
		bird_node.add_child(body_mesh)
		var head: Node3D = Node3D.new()
		head.name = "Head"
		head.position = Vector3(0.0, 0.085, 0.045)
		var head_pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		head_pen.box(Vector3(-0.02, -0.02, -0.015), Vector3(0.02, 0.02, 0.02), skin.pigeon_neck)
		head_pen.box(Vector3(-0.018, 0.02, -0.01), Vector3(0.018, 0.045, 0.03), skin.pigeon.lightened(0.05))
		head_pen.box(Vector3(-0.006, 0.024, 0.03), Vector3(0.006, 0.034, 0.05), skin.trim)
		head.add_child(_instance("Head", head_pen.soup.to_mesh(), _material))
		bird_node.add_child(head)
		# A touch larger than life, like the kit's chunky props, so it reads from the camera.
		bird_node.scale = Vector3.ONE * PIGEON_SCALE
		holder.add_child(bird_node)
		pigeons.append(bird_node)


## A few birds wheeling in a loose ring over the city beside the tower.
func _build_birds() -> void:
	birds.clear()
	var holder: Node3D = Node3D.new()
	holder.name = "Birds"
	root.add_child(holder)
	var wing: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	wing.tri(Vector3(0.0, 0.0, 0.06), Vector3(0.0, 0.0, -0.06), Vector3(0.3, 0.0, -0.02), Vector3.UP, skin.bird)
	var wing_mesh: ArrayMesh = wing.soup.to_mesh()
	var body: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	body.box(Vector3(-0.035, -0.03, -0.14), Vector3(0.035, 0.03, 0.12), skin.bird)
	var body_mesh: ArrayMesh = body.soup.to_mesh()
	for index: int in skin.birds:
		var bird_node: Node3D = Node3D.new()
		bird_node.name = "Bird%d" % index
		bird_node.add_child(_instance("Body", body_mesh, _material))
		for side: float in [-1.0, 1.0]:
			var limb: MeshInstance3D = _instance("Wing" if side > 0.0 else "WingL", wing_mesh, _material)
			limb.scale = Vector3(side, 1.0, 1.0)
			bird_node.add_child(limb)
		holder.add_child(bird_node)
		birds.append(bird_node)


## A small plane high over the city, crossing now and then on a line well clear of the
## tower, with blinking navigation lights.
func _build_plane() -> void:
	plane = Node3D.new()
	plane.name = "Plane"
	root.add_child(plane)
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	pen.box(Vector3(-0.14, -0.13, -1.0), Vector3(0.14, 0.13, 1.1), skin.plane)
	pen.box(Vector3(-0.1, -0.1, 1.1), Vector3(0.1, 0.08, 1.3), skin.plane.darkened(0.1))
	pen.box(Vector3(-1.4, -0.03, 0.05), Vector3(1.4, 0.02, 0.5), skin.plane)
	pen.box(Vector3(-0.5, -0.02, -0.95), Vector3(0.5, 0.02, -0.7), skin.plane)
	pen.box(Vector3(-0.02, 0.0, -1.0), Vector3(0.02, 0.5, -0.65), skin.plane_tail)
	pen.box(Vector3(-0.15, 0.06, 0.55), Vector3(0.15, 0.13, 0.9), skin.window_day)
	plane.add_child(_instance("Body", pen.soup.to_mesh(), _material))
	var lights: Array[Vector3] = [Vector3(-1.4, 0.0, 0.25), Vector3(1.4, 0.0, 0.25), Vector3(0.0, 0.5, -0.95)]
	var tints: Array[Color] = [skin.aircraft_red, Color(0.35, 1.0, 0.45), skin.headlight]
	var glow: MeshInstance3D = _instance("NavLights", _sprites(lights, [0.7, 0.7, 0.8] as Array[float], tints, [] as Array[float]), _plane_light_material)
	glow.extra_cull_margin = 1.0
	plane.add_child(glow)


# --- motion and time of day -------------------------------------------------

## 0 by day, 1 from dusk; `late` rises after the shop closes; `dark` is 0 through the
## golden dusk and 1 once the sun has gone (DayNightView.street_dark). At dusk the city
## lies under a sunset haze in the warm low sun, with only a scattering of windows lit
## and the red lights blinking; as the dark comes the haze turns to night and the
## windows fill in. The bulbs and beacons glow from dusk; the pigeons and birds go home.
## The day's weather (WeatherState.Kind): the city's haze thickens toward a grey murk and
## fewer clouds show below the roof (cloudy a little, rain more); pigeons shelter in the rain.
func set_weather(kind: int) -> void:
	if kind == _weather:
		return
	_weather = kind
	_apply_night()


## A place for a puddle on the roof's membrane round `u` (`across` 0..1 picks how far
## back), clear of the shop, its doors, the lobby, the walkway and the terraces; NaN when
## there is no room there.
func wet_spot(across: float, u: float, radius: float) -> Vector2:
	var inner: float = PARAPET_T + radius + 0.25
	if u < roof.position.x + inner or u > roof.end.x - inner:
		return Vector2(NAN, NAN)
	var point: Vector2 = Vector2(u, lerpf(roof.position.y + inner, roof.end.y - inner, across))
	if _is_blocked(point, radius + 0.1):
		return Vector2(NAN, NAN)
	return point


func set_night(level: float, late: float, dark: float = 1.0) -> void:
	_night = level
	_late = late
	_dark = dark
	_apply_night()


## Where the evening is: 0 by day, 0.5 at the golden dusk, 1 by night (the city's haze
## and the clouds run day, dusk, night along it).
func evening() -> float:
	return 0.5 * _night * (1.0 + _dark)


func _apply_night() -> void:
	if root == null:
		return
	var evening_level: float = evening()
	_city_material.set_shader_parameter(&"level", evening_level)
	_city_material.set_shader_parameter(&"window_level", _night)
	_city_material.set_shader_parameter(&"window_share", lerpf(DUSK_WINDOW_SHARE, 1.0, _dark))
	_city_material.set_shader_parameter(&"late", _late)
	_glass_material.emission_energy_multiplier = _night * 1.3
	_glass_material.albedo_color = skin.lamp_glow.lerp(Color.WHITE, 1.0 - _night)
	_pool_material.albedo_color = Color(1.0, 1.0, 1.0, _night)
	_pools.visible = _night > 0.05
	_bulb_material.set_shader_parameter(&"level", _night)
	_beacon_material.set_shader_parameter(&"level", smoothstep(0.2, 0.7, _night))
	_street_material.set_shader_parameter(&"level", smoothstep(0.1, 0.6, _night) * lerpf(DUSK_STREET_SHARE, 1.0, _dark))
	_traffic_material.set_shader_parameter(&"level", smoothstep(0.2, 0.7, _night))
	_plane_light_material.set_shader_parameter(&"level", maxf(_night, 0.35))
	var dusk: Color = skin.cloud.lerp(skin.haze_dusk, 0.55)
	var tint: Color = skin.cloud.lerp(dusk, clampf(evening_level * 2.0, 0.0, 1.0)) if evening_level < 0.5 else dusk.lerp(skin.haze_night.lightened(0.25), evening_level * 2.0 - 1.0)
	_cloud_material.set_shader_parameter(&"tint", tint)
	var haze: Color = skin.haze_day.lerp(skin.haze_dusk, evening_level * 2.0) if evening_level < 0.5 else skin.haze_dusk.lerp(skin.haze_night, evening_level * 2.0 - 1.0)
	_cloud_material.set_shader_parameter(&"haze", haze)
	_cloud_material.set_shader_parameter(&"haze_mix", CLOUD_HAZE)
	_cloud_material.set_shader_parameter(&"opacity", lerpf(0.82, 0.2, evening_level) * CLOUD_SHARE[clampi(_weather, 0, 2)])
	_city_material.set_shader_parameter(&"murk", MURK[clampi(_weather, 0, 2)])
	# Unlit glows still cost a blended pass: hide them by day.
	var lit: bool = _night > 0.05
	_bulb_glow.visible = lit
	_beacons.visible = lit
	_street_lights.visible = lit
	_traffic.visible = lit
	for pigeon: Node3D in pigeons:
		pigeon.visible = evening_level < NIGHT_HIDE and _weather != WeatherState.Kind.RAIN
	for bird_node: Node3D in birds:
		bird_node.visible = evening_level < NIGHT_HIDE
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
	_city_material.set_shader_parameter(&"city_time", seconds)
	_cloud_material.set_shader_parameter(&"cloud_time", seconds)
	for material: ShaderMaterial in [_bulb_material, _beacon_material, _street_material, _traffic_material, _plane_light_material]:
		material.set_shader_parameter(&"glow_time", seconds)
	for index: int in fans.size():
		fans[index].rotation = Vector3(0.0, seconds * (5.0 + float(index) * 0.7) + float(index), 0.0)
	for index: int in pigeons.size():
		pigeons[index].transform = pigeon_transform(index, seconds)
		var head: Node3D = pigeons[index].get_node(^"Head") as Node3D
		head.rotation = Vector3(pigeon_peck(index, seconds), 0.5 * sin(seconds * 0.7 + float(index) * 2.0) * step_wave(seconds * 0.23 + float(index)), 0.0)
	for index: int in birds.size():
		birds[index].transform = bird_transform(index, seconds)
		var flap: float = 0.5 * sin(seconds * 9.0 + float(index) * 1.3) * (0.4 + 0.6 * step_wave(seconds * 0.4 + float(index) * 0.7))
		(birds[index].get_child(1) as Node3D).rotation = Vector3(0.0, 0.0, flap)
		(birds[index].get_child(2) as Node3D).rotation = Vector3(0.0, 0.0, -flap)
	plane.transform = plane_transform(seconds)
	plane.visible = plane_flying(seconds)


## 1 for half of each unit of `t`, 0 for the rest, with soft edges.
static func step_wave(t: float) -> float:
	var f: float = fposmod(t, 1.0)
	return smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.5, 0.58, f))


## A pigeon sits, turns now and then, and shuffles a step along the coping and back.
func pigeon_transform(index: int, seconds: float) -> Transform3D:
	var spot: Vector4 = _pigeon_spots[index]
	var beat: float = floorf((seconds + float(index) * 3.7) / 6.5)
	var turn: float = (NeighbourhoodGround.hash01(index, int(beat), salt + 515) - 0.5) * 1.4
	var shuffle: float = 0.12 * sin((seconds + float(index) * 5.0) * 0.21)
	var along: Vector3 = Vector3(sin(spot.w), 0.0, cos(spot.w))
	return Transform3D(Basis(Vector3.UP, spot.w + turn).scaled(Vector3.ONE * PIGEON_SCALE), Vector3(spot.x, spot.y, spot.z) + along * shuffle)


## The head dips to peck for a moment every few seconds.
func pigeon_peck(index: int, seconds: float) -> float:
	var period: float = 3.1 + float(index) * 0.53
	var phase: float = fposmod(seconds + float(index) * 1.9, period) / period
	return 0.9 * smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.14, 0.22, phase))


## The birds' ring: beside the tower, below the roof, each on its own phase.
func bird_transform(index: int, seconds: float) -> Transform3D:
	var c: Vector2 = Vector2(roof.end.x + 14.0, roof.position.y - 6.0)
	var radius: float = 8.0 + float(index % 3) * 1.6
	var angle: float = seconds * 0.32 + float(index) * TAU / float(maxi(skin.birds, 1)) * 0.6
	var at: Vector3 = Vector3(c.x + cos(angle) * radius, -7.5 + 0.8 * sin(seconds * 0.5 + float(index)), c.y + sin(angle) * radius * 0.7)
	var heading: Vector3 = Vector3(-sin(angle), 0.0, cos(angle) * 0.7).normalized()
	var bank: float = -0.35
	return Transform3D(Basis.looking_at(heading, Vector3.UP, true) * Basis(Vector3.BACK, bank), at)


## Where the plane is on its crossing: one pass every PLANE_PERIOD seconds.
func plane_transform(seconds: float) -> Transform3D:
	var c: Vector2 = centre()
	var direction: Vector2 = Vector2(0.86, -0.51)
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var t: float = fposmod(seconds + 18.0, PLANE_PERIOD) * PLANE_SPEED - 120.0
	var at: Vector2 = c + normal * PLANE_PASS + direction * t
	var heading: Vector3 = Vector3(direction.x, 0.0, direction.y)
	return Transform3D(Basis.looking_at(heading, Vector3.UP, true) * Basis(Vector3.BACK, 0.06), Vector3(at.x, PLANE_Y, at.y))


func plane_flying(seconds: float) -> bool:
	var t: float = fposmod(seconds + 18.0, PLANE_PERIOD) * PLANE_SPEED - 120.0
	return absf(t) < 115.0


## What the rooftop shows now, for tests and captures.
func capture_state() -> Dictionary:
	return {"roof": roof, "lobby": lobby, "walkway": walkway, "terraces": terraces, "water_tower": water_tower,
		"mast": mast, "lots": lots.size(), "night": _night, "late": _late, "lit": is_lit(), "pigeons": pigeons.size(),
		"birds": birds.size(), "fans": fans.size(), "plane": plane_flying(_seconds), "dark": _dark, "evening": evening(),
		"window_share": float(_city_material.get_shader_parameter(&"window_share")) if _city_material != null else 1.0,
		"beacons": float(_beacon_material.get_shader_parameter(&"level")) if _beacon_material != null else 0.0}
