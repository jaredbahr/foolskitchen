class_name NeighbourhoodForest
extends RefCounted
## A woodland clearing instead of a street (#607). The shop stands in a clearing
## ringed by tall pines. A dirt track winds past its front and on through the trees
## at both ends, with hikers and cyclists on it. Beside the door: a porch deck with
## rocking chairs, a woodpile and chopping block, and a fire pit with log benches
## under string lights. Across the track a glade runs down to a stream with a
## footbridge on a side trail, and deer and rabbits come out at the trees' edge.
## Ferns, mushrooms, mossy rocks and fallen logs fill the undergrowth. At night the
## fire burns, the bulbs glow and fireflies drift over the glade and the water.
##
## The trees beside and behind the lot are named stands (#597): each can show the
## forest, the stumps after felling, or cleared ground, without a rebuild. The lot's
## land not leased yet is wooded too (#611): land stands, one per strip of it, stand
## right up to the leased land and are felled flush once the lease covers them.
##
## Like the rest of the neighbourhood it is view-only: no colliders, sim agents,
## saves, lights or random draws. Everything placed comes from an integer hash, and
## every motion is a closed-form function of the street's display clock, so a paused
## capture always shows the same frame. Authored in the street's local frame (u along
## the front, z outward past the door), under one root the dressing places on that
## frame. Draw cost: a handful of batched vertex-coloured meshes (the static ones
## cached per street), one stream shader strip, one glow-sprite mesh for the bulbs and
## one for the fireflies, and a few small nodes for the animals, chairs and flames.

const GLOW_SHADER: Shader = preload("res://src/world/forest_glow.gdshader")
const STREAM_SHADER: Shader = preload("res://src/world/forest_stream.gdshader")

enum StandState { FOREST, STUMPS, CLEARED }

## Ground layers sit 4 mm or more apart, all under the shop floor (y 0).
const FLOOR_Y: float = -0.062
const GRASS_Y: float = -0.054
const PATCH_Y: float = -0.048
const STAND_Y: float = -0.044
const EDGE_Y: float = -0.040
const TRACK_Y: float = -0.036
const DUST_Y: float = -0.032
const BANK_Y: float = -0.040
const WATER_Y: float = -0.028
const SHADOW_Y: float = -0.022
## Where people walk on the track (their feet).
const WALK_Y: float = -0.034
## The track's centre (v past the lot's front) and half width.
const TRACK_V: float = 4.3
const TRACK_HALF: float = 0.95
## The walking lanes across the track (offsets from its centre line).
const LANES: Array[float] = [-0.42, 0.38, -0.1, 0.2, -0.3]
## The stream's centre (v past the lot's front) and half width.
const STREAM_V: float = 10.6
const STREAM_HALF: float = 0.6
## The glade across the track runs this far past the lot's front at its deepest.
const GLADE_V: float = 15.5
## Gap between the lot (its maximum footprint) and the named stands.
const STAND_GAP: float = 0.45
## The yard in front of the shop: the porch, the woodpile and the fire pit stand in it.
const YARD_V: float = 3.0
const PORCH_TOP: float = 0.14
const FIRE_RING: float = 0.42
## How far the track's walkers go either way from the lot's middle before turning back
## (deep in the trees, out of sight).
const WALK_REACH: float = 21.0
const NIGHT_HIDE: float = 0.5
## The forest's trees are batched in squares this wide (metres).
const CHUNK: float = 12.0
## Deer are drawn at person scale: a shoulder about two thirds of a person's height.
const DEER_SCALE: float = 1.4
const RABBIT_SCALE: float = 1.6
## The shop's own porch (#596): its rail is at a person's waist, and the post by the
## door steps stands taller to hang the lantern.
const PATIO_RAIL: float = 0.36
const PATIO_LANTERN_POST: float = 0.62

## One named stand of trees (#597): its id, the local rect it fills and its three looks.
class Stand extends RefCounted:
	var id: StringName
	var rect: Rect2
	var crowns: Rect2
	var node: Node3D
	var trees: Array[Vector3] = []
	## True for the stand behind the lot (its trees keep clear of the lot along z),
	## false for the two beside it (along u).
	var behind: bool = false
	## A land stand (#611): it grows on the lot's own land outside the first lease
	## (`land`, local cells), not round the lot.
	var is_land: bool = false
	var land: Rect2 = Rect2()
	## True when the current lease covers its land: the land is the player's to build
	## on, so it can show only its flush stumps or cleared ground, never trees.
	var leased: bool = false

## Inputs, set by the owner before build().
var skin: ForestSkin
var local_reserve: AABB = AABB()
var shift: float = 0.0
var world_centre: Vector2 = Vector2.ZERO
var light_shift: Vector2 = Vector2.ZERO
var salt: int = 0
## The street frame's basis: names the stands by compass (east is world +x, north -z).
var compass: Basis = Basis.IDENTITY
## Local (u, z) rects the yard props keep off: the door approaches and entrance pads.
var keep_clear: Array[Rect2] = []
## The lot's leases (#611), local (u, z): the first, unexpanded lease and the current
## one. The maximum lot's land outside the first lease grows land stands; empty rects
## mean no land stands. The current lease's front is the shop's facade.
var first_lease: Rect2 = Rect2()
var lease: Rect2 = Rect2()
## The shop building's local (u, z) extent, walls included: the porch runs along its
## front and stops at its corner. Empty: the lot stands in for it.
var building: Rect2 = Rect2()
## The shop's own patio cells (local u, z rects, one per cell) and the patio floor's
## height (#596). Patio in front of the facade is the cabin's porch: the deck frame,
## rail and lantern wrap it instead of the drawn deck with its rocking chairs, so the
## player's porch tables stand on it. Empty keeps the drawn deck.
var patio: Array[Rect2] = []
var patio_top: float = 0.055

var root: Node3D
var stands: Array[Stand] = []
var deer: Array[Node3D] = []
var rabbits: Array[Node3D] = []
var chairs: Array[Node3D] = []
var flames: Array[Node3D] = []
var _deer_spots: Array[Vector3] = []
var _rabbit_spots: Array[Vector4] = []
var _chair_spots: Array[Transform3D] = []
var _lantern_at: Vector3 = Vector3.ZERO
var _stream_material: ShaderMaterial
var _bulb_material: ShaderMaterial
var _fly_material: ShaderMaterial
var _glass_material: StandardMaterial3D
var _flame_material: StandardMaterial3D
var _fire_glow_material: StandardMaterial3D
var _fire_glow: MeshInstance3D
var _bulb_glow: MeshInstance3D
var _fireflies: MeshInstance3D
var _material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _night: float = 0.0
var _weather: int = WeatherState.Kind.SUNNY
var _gloom: float = 0.0
var _late: float = 0.0
var _seconds: float = 0.0
var _applied_at: float = -1.0
## Where the yard's pieces went (local), for tools and tests.
var porch: Rect2 = Rect2()
## The patio cells in front of the facade (local rects): the porch when not empty.
var porch_cells: Array[Rect2] = []
var woodpile: Rect2 = Rect2()
var fire_pit: Vector2 = Vector2.ZERO
var bridge: Vector2 = Vector2.ZERO
var trail_u: float = 0.0
var _blocked: Array[Rect2] = []
var _chunks: Dictionary[Vector2i, NeighbourhoodGround.Soup] = {}

## Built static meshes by street key, shared by every forest (a rebuild after a
## purchase or a reload reuses them instead of re-planting thousands of trees).
static var _cache: Dictionary[String, Dictionary] = {}
## The land stands' meshes by their own key (a few dozen young trees each).
static var _land_cache: Dictionary[String, Dictionary] = {}
static var _templates: Dictionary[String, Array] = {}


static func clear_cache() -> void:
	_land_cache.clear()
	_cache.clear()


func _r(a: int, b: int) -> float:
	return NeighbourhoodGround.hash01(a, b, salt + 607)


func _centre_u() -> float:
	return local_reserve.get_center().x


func _half_lot() -> float:
	return local_reserve.size.x * 0.5


# --- the shape of the clearing ------------------------------------------------

## The track's centre line (local z) at `u`: almost straight past the lot, winding
## more and more as it runs off into the trees.
func track_z(u: float) -> float:
	var away: float = clampf((absf(u - _centre_u()) - (_half_lot() + 3.0)) / 16.0, 0.0, 1.0)
	var bend: float = 0.16 * sin(u * 0.21 + 0.6) + away * away * (1.15 * sin(u * 0.083 + 1.9) + 0.45 * sin(u * 0.19 + 0.4))
	return shift + TRACK_V + bend


## The track's slope dz/du at `u` (for walkers' headings).
func track_slope(u: float) -> float:
	return (track_z(u + 0.05) - track_z(u - 0.05)) / 0.1


## How much of the yard or glade reaches `u`: 1 near the lot, falling to 0 in the trees.
func _bump(u: float, half: float, fall: float) -> float:
	var t: float = clampf((absf(u - _centre_u()) - half) / fall, 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## The open ground's near edge (local z) at `u`: the yard by the lot, a verge by the track.
func open_near(u: float) -> float:
	var verge: float = track_z(u) - TRACK_HALF - 0.75 - 0.25 * sin(u * 0.9 + 1.0)
	return lerpf(verge, shift - 0.2, _bump(u, _half_lot() + 4.2, 4.0))


## The open ground's far edge (local z) at `u`: the glade's tree line across the track.
func open_far(u: float) -> float:
	var verge: float = track_z(u) + TRACK_HALF + 0.75 + 0.25 * sin(u * 0.7 + 2.0)
	var glade: float = shift + GLADE_V + 1.1 * sin(u * 0.29 + 0.5) + 0.6 * sin(u * 0.83)
	return lerpf(verge, glade, _bump(u, _half_lot() + 7.0, 7.0))


## The stream's centre line (local z) at `u`.
func stream_z(u: float) -> float:
	return shift + STREAM_V + 0.95 * sin(u * 0.16 + 0.8) + 0.4 * sin(u * 0.43 + 2.0)


func _stream_half(u: float) -> float:
	return STREAM_HALF + 0.1 * sin(u * 0.61 + 0.3)


## The side trail's line (local u) at `z`: off the track, over the footbridge, into the trees.
func _trail_at(z: float) -> float:
	return trail_u + 0.35 * sin((z - shift) * 0.55)


## The shop's facade (local z): the current lease's front, else the lot's front.
func _facade() -> float:
	return minf(lease.end.y, shift) if lease.has_area() else shift


func _reserve_rect() -> Rect2:
	return Rect2(local_reserve.position.x, local_reserve.position.z, local_reserve.size.x, shift - local_reserve.position.z)


func _is_open(point: Vector2, margin: float) -> bool:
	if point.y > open_near(point.x) - margin and point.y < open_far(point.x) + margin:
		return true
	return _reserve_rect().grow(STAND_GAP + margin).has_point(point)


func _on_track(point: Vector2, margin: float) -> bool:
	return absf(point.y - track_z(point.x)) < TRACK_HALF + margin


func _on_stream(point: Vector2, margin: float) -> bool:
	return absf(point.y - stream_z(point.x)) < _stream_half(point.x) + margin


func _on_trail(point: Vector2, margin: float) -> bool:
	return point.y > track_z(point.x) and point.y < open_far(trail_u) + 7.0 and absf(point.x - _trail_at(point.y)) < 0.38 + margin


func _in_stand(point: Vector2, margin: float) -> bool:
	for stand: Stand in stands:
		if stand.rect.grow(margin).has_point(point):
			return true
	return false


func _is_blocked(point: Vector2, margin: float) -> bool:
	for rect: Rect2 in _blocked:
		if rect.grow(margin).has_point(point):
			return true
	return false


## The distance from `point` to the lot's maximum footprint.
func _distance_to_lot(point: Vector2) -> float:
	var lot: Rect2 = _reserve_rect()
	var dx: float = maxf(maxf(lot.position.x - point.x, point.x - lot.end.x), 0.0)
	var dz: float = maxf(maxf(lot.position.y - point.y, point.y - lot.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


## True at the open ground's edge (forest within `reach` one way, open ground the other).
func _near_edge(point: Vector2, reach: float) -> bool:
	var open: bool = _is_open(point, 0.0)
	for offset: Vector2 in [Vector2(reach, 0.0), Vector2(-reach, 0.0), Vector2(0.0, reach), Vector2(0.0, -reach)]:
		if _is_open(point + offset, 0.0) != open:
			return true
	return false


# --- the named stands (#597) ---------------------------------------------------

## The stands on the lot's two sides and its back, named by compass.
func _plan_stands() -> void:
	stands.clear()
	var lot: Rect2 = _reserve_rect()
	var depth: float = skin.stand_depth
	var rects: Array[Rect2] = [
		Rect2(lot.position.x - STAND_GAP - depth, lot.position.y - STAND_GAP, depth, lot.size.y + STAND_GAP - 0.2),
		Rect2(lot.end.x + STAND_GAP, lot.position.y - STAND_GAP, depth, lot.size.y + STAND_GAP - 0.2),
		Rect2(lot.position.x - STAND_GAP - depth, lot.position.y - STAND_GAP - depth, lot.size.x + (STAND_GAP + depth) * 2.0, depth)]
	var outward: Array[Vector3] = [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]
	for index: int in 3:
		var stand: Stand = Stand.new()
		stand.id = _compass_name(compass * outward[index])
		stand.rect = rects[index]
		stand.behind = index == 2
		stands.append(stand)


static func _compass_name(direction: Vector3) -> StringName:
	if absf(direction.x) >= absf(direction.z):
		return &"east" if direction.x > 0.0 else &"west"
	return &"south" if direction.z > 0.0 else &"north"


## The lot's land outside the first lease (#611), as land stands: a strip down each
## side the lease does not reach and one across its back, named by compass with
## `_land` (`east_land`). Their trees fill the strip from the first lease's edge (less
## the stand gap) out to the stands round the lot, so the forest meets the cabin.
func _plan_land() -> void:
	if not first_lease.has_area():
		return
	var lot: Rect2 = _reserve_rect()
	var start: Rect2 = first_lease.intersection(lot)
	if not start.has_area():
		return
	var top: float = lot.position.y - STAND_GAP
	var front: float = lot.end.y - 0.2
	var pieces: Array[Rect2] = []
	var lands: Array[Rect2] = []
	var outward: Array[Vector3] = []
	if start.position.x > lot.position.x + 0.01:
		pieces.append(Rect2(lot.position.x - STAND_GAP, top, start.position.x - lot.position.x, front - top))
		lands.append(Rect2(lot.position.x, lot.position.y, start.position.x - lot.position.x, start.end.y - lot.position.y))
		outward.append(Vector3.LEFT)
	if start.end.x < lot.end.x - 0.01:
		pieces.append(Rect2(start.end.x + STAND_GAP, top, lot.end.x - start.end.x, front - top))
		lands.append(Rect2(start.end.x, lot.position.y, lot.end.x - start.end.x, start.end.y - lot.position.y))
		outward.append(Vector3.RIGHT)
	if start.position.y > lot.position.y + 0.01:
		pieces.append(Rect2(start.position.x - STAND_GAP, top, start.size.x + STAND_GAP * 2.0, start.position.y - lot.position.y))
		lands.append(Rect2(start.position.x, lot.position.y, start.size.x, start.position.y - lot.position.y))
		outward.append(Vector3.FORWARD)
	for index: int in pieces.size():
		var entry: Stand = Stand.new()
		entry.id = StringName(String(_compass_name(compass * outward[index])) + "_land")
		entry.rect = pieces[index]
		entry.behind = outward[index] == Vector3.FORWARD
		entry.is_land = true
		entry.land = lands[index]
		entry.leased = lease.has_area() and lease.grow(0.01).encloses(lands[index])
		stands.append(entry)


## The ids of the stands, in build order (left side, right side, back, then the land
## stands).
func stand_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for stand: Stand in stands:
		ids.append(stand.id)
	return ids


func stand(id: StringName) -> Stand:
	for entry: Stand in stands:
		if entry.id == id:
			return entry
	return null


## Shows a stand as forest, stumps or cleared ground. Leased land never shows trees.
func show_stand(id: StringName, state: int) -> void:
	var entry: Stand = stand(id)
	if entry == null or entry.node == null:
		return
	if entry.is_land and entry.leased and state == StandState.FOREST:
		state = StandState.STUMPS
	(entry.node.get_node(^"Forest") as Node3D).visible = state == StandState.FOREST
	(entry.node.get_node(^"Stumps") as Node3D).visible = state == StandState.STUMPS
	(entry.node.get_node(^"Cleared") as Node3D).visible = state == StandState.CLEARED


# --- building ---------------------------------------------------------------

## Builds every node under `parent` (the dressing's forest root, placed on the street frame).
func build(parent: Node3D) -> void:
	root = parent
	_materials()
	_plan_stands()
	_plan_yard()
	var key: String = var_to_str([local_reserve, shift, world_centre, light_shift, salt, compass, keep_clear, _facade(), building, skin.signature()])
	if not porch_cells.is_empty():
		key += var_to_str([porch_cells, patio_top])
	var meshes: Dictionary = _cache.get(key, {})
	if meshes.is_empty():
		meshes = _build_static()
		if _cache.size() > 4:
			_cache.clear()
		_cache[key] = meshes
	else:
		# The plan still has to know where the stands' trees stand (crowns, for bounds).
		for stand_entry: Stand in stands:
			stand_entry.crowns = meshes["crowns:" + String(stand_entry.id)]
	# The land stands come after the cached forest (it never covers the lot's land).
	_plan_land()
	var land_key: String = var_to_str([key, first_lease])
	var land_meshes: Dictionary = _land_cache.get(land_key, {})
	if land_meshes.is_empty():
		for stand_entry: Stand in stands:
			if stand_entry.is_land:
				_build_land(stand_entry, land_meshes)
				land_meshes["crowns:" + String(stand_entry.id)] = stand_entry.crowns
				land_meshes["trees:" + String(stand_entry.id)] = stand_entry.trees.duplicate()
		if _land_cache.size() > 8:
			_land_cache.clear()
		_land_cache[land_key] = land_meshes
	else:
		for stand_entry: Stand in stands:
			if stand_entry.is_land:
				stand_entry.crowns = land_meshes["crowns:" + String(stand_entry.id)]
				stand_entry.trees.assign(land_meshes["trees:" + String(stand_entry.id)])
	meshes = meshes.merged(land_meshes)
	_add(_instance("Ground", meshes["ground"], _material))
	# The forest comes in square chunks, so the view culls the ones out of sight and
	# the shop's night light only lights the few near it.
	var woods: Node3D = Node3D.new()
	woods.name = "Forest"
	root.add_child(woods)
	var chunks: Array = meshes["forest"]
	for index: int in chunks.size():
		woods.add_child(_instance("Chunk%d" % index, chunks[index], _material))
	_add(_instance("Props", meshes["props"], _material))
	_add(_instance("Shadows", meshes["shadows"], _shadow_material))
	_add(_instance("Stream", meshes["stream"], _stream_material))
	var holder: Node3D = Node3D.new()
	holder.name = "Stands"
	root.add_child(holder)
	for stand_entry: Stand in stands:
		stand_entry.node = Node3D.new()
		stand_entry.node.name = String(stand_entry.id)
		holder.add_child(stand_entry.node)
		for look: String in ["Forest", "Stumps", "Cleared"]:
			var group: Node3D = Node3D.new()
			group.name = look
			stand_entry.node.add_child(group)
			var body: MeshInstance3D = _instance("Body", meshes["%s:%s" % [stand_entry.id, look]], _material)
			group.add_child(body)
			var shade: MeshInstance3D = _instance("Shade", meshes["%s:%s:shade" % [stand_entry.id, look]], _shadow_material)
			group.add_child(shade)
		show_stand(stand_entry.id, StandState.FOREST)
	_build_lights(meshes)
	_build_fire()
	_build_chairs()
	_build_animals()
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
	_stream_material = ShaderMaterial.new()
	_stream_material.shader = STREAM_SHADER
	_stream_material.set_shader_parameter(&"deep", skin.water_deep)
	_stream_material.set_shader_parameter(&"shallow", skin.water_shallow)
	_stream_material.set_shader_parameter(&"ripple", skin.ripple)
	_bulb_material = ShaderMaterial.new()
	_bulb_material.shader = GLOW_SHADER
	_bulb_material.set_shader_parameter(&"tint", skin.lamp_glow)
	_fly_material = ShaderMaterial.new()
	_fly_material.shader = GLOW_SHADER
	_fly_material.set_shader_parameter(&"tint", skin.firefly)
	_fly_material.set_shader_parameter(&"drift", 1.0)
	_glass_material = StandardMaterial3D.new()
	_glass_material.vertex_color_use_as_albedo = true
	_glass_material.emission_enabled = true
	_glass_material.emission = skin.lamp_glow
	_glass_material.emission_energy_multiplier = 0.0
	_glass_material.disable_receive_shadows = true
	_flame_material = StandardMaterial3D.new()
	_flame_material.vertex_color_use_as_albedo = true
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.disable_receive_shadows = true
	_fire_glow_material = StandardMaterial3D.new()
	_fire_glow_material.vertex_color_use_as_albedo = true
	_fire_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fire_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fire_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fire_glow_material.disable_receive_shadows = true


func _instance(label: String, mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _add(node: Node3D) -> void:
	root.add_child(node)


## Where the porch, woodpile, fire pit, trail and footbridge go, clear of the door.
func _plan_yard() -> void:
	_blocked.clear()
	var lot: Rect2 = _reserve_rect()
	var door: Rect2 = Rect2(_centre_u() - 0.6, shift, 1.2, 2.2)
	var doors: Array[Rect2] = []
	for rect: Rect2 in keep_clear:
		if rect.end.y > shift - 0.05:
			doors.append(rect)
	if not doors.is_empty():
		door = doors[0]
		for rect: Rect2 in doors:
			door = door.merge(rect)
	# The front patio: from the entrance row (the building's last built row) outward.
	porch_cells.clear()
	var front_row: float = minf(_facade(), (building.end.y if building.has_area() else shift) - GridMath.CELL_SIZE)
	for cell: Rect2 in patio:
		if cell.position.y >= front_row - 0.05:
			porch_cells.append(cell)
	if not porch_cells.is_empty():
		_plan_patio_yard(door)
		return
	# The porch runs along the shop's front on the roomier side of the door; the fire
	# pit sits out in the yard on the other side, and the woodpile past the porch's end.
	var front: Rect2 = building if building.has_area() else lot
	var left_room: float = door.position.x - front.position.x + 0.1
	var right_room: float = front.end.x - door.end.x + 0.1
	var porch_left: bool = left_room >= right_room
	var room: float = maxf(left_room, right_room) - 0.25
	var length: float = clampf(room, 1.6, 4.4)
	# The deck runs back over the entrance row to the facade (#611), so it reads as the
	# cabin's own porch; the row stays the grid's (the deck is only drawn).
	var back: float = _facade()
	var deep: float = shift + 1.49 - back
	if porch_left:
		porch = Rect2(door.position.x - 0.15 - length, back, length, deep)
		woodpile = Rect2(porch.position.x - 1.65, shift + 0.12, 1.35, 0.62)
		fire_pit = Vector2(maxf(door.end.x + 1.9, lot.end.x - 0.6), shift + 1.65)
	else:
		porch = Rect2(door.end.x + 0.15, back, length, deep)
		woodpile = Rect2(porch.end.x + 0.3, shift + 0.12, 1.35, 0.62)
		fire_pit = Vector2(minf(door.position.x - 1.9, lot.position.x + 0.6), shift + 1.65)
	_blocked.append(porch.grow(0.2))
	_blocked.append(woodpile.grow_individual(0.2, 0.2, 0.2, 1.0))
	_blocked.append(Rect2(fire_pit - Vector2(1.7, 1.45), Vector2(3.4, 2.9)))
	for rect: Rect2 in keep_clear:
		_blocked.append(rect.grow(0.1))
	_blocked.append(Rect2(door.get_center().x - 0.5, shift, 1.0, track_z(door.get_center().x) - shift))
	# The trail leaves the track on the fire pit's side, a little way along.
	trail_u = fire_pit.x + (2.6 if porch_left else -2.6)
	bridge = Vector2(_trail_at(stream_z(trail_u)), stream_z(trail_u))
	_blocked.append(Rect2(bridge - Vector2(0.75, 1.6), Vector2(1.5, 3.2)))
	_blocked.append(Rect2(trail_u - 1.1, track_z(trail_u) + TRACK_HALF - 0.1, 0.8, 0.9))
	# Two rocking chairs facing out on the porch, and the lantern on the post by the door.
	var middle: float = porch.get_center().x
	var spacing: float = minf(0.7, porch.size.x * 0.25)
	_chair_spots.clear()
	for side: float in [-1.0, 1.0]:
		_chair_spots.append(Transform3D(Basis(Vector3.UP, side * 0.18), Vector3(middle + side * spacing, PORCH_TOP, porch.end.y - 0.75)))
	var posts: Array[float] = _porch_posts()
	var lantern_post: float = posts[posts.size() - 1] if porch.end.x < _door_u() else posts[0]
	_lantern_at = Vector3(lantern_post - 0.1, PORCH_TOP + 0.47, porch.end.y - 0.035)


## The yard round the shop's own porch (its front patio cells, #596): the woodpile past
## the porch's far end from the door, the fire pit out past the other end, the lantern
## on the post by the door and no rocking chairs (the porch is the player's to furnish).
func _plan_patio_yard(door: Rect2) -> void:
	porch = porch_cells[0]
	for cell: Rect2 in porch_cells:
		porch = porch.merge(cell)
		_blocked.append(cell.grow(0.15))
	var front: float = porch.end.y
	# The woodpile goes beyond the end of the porch farther from the door; the fire pit
	# out past the other end, clear of the porch and the door's approach.
	var woodpile_right: bool = porch.end.x - door.end.x >= door.position.x - porch.position.x
	if woodpile_right:
		woodpile = Rect2(porch.end.x + 0.45, shift + 0.12, 1.35, 0.62)
		fire_pit = Vector2(minf(porch.position.x - 1.9, door.position.x - 1.9), maxf(shift + 1.65, front - 0.4))
	else:
		woodpile = Rect2(porch.position.x - 1.8, shift + 0.12, 1.35, 0.62)
		fire_pit = Vector2(maxf(porch.end.x + 1.9, door.end.x + 1.9), maxf(shift + 1.65, front - 0.4))
	_blocked.append(woodpile.grow_individual(0.2, 0.2, 0.2, 1.0))
	_blocked.append(Rect2(fire_pit - Vector2(1.7, 1.45), Vector2(3.4, 2.9)))
	for rect: Rect2 in keep_clear:
		_blocked.append(rect.grow(0.1))
	_blocked.append(Rect2(door.get_center().x - 0.5, shift, 1.0, track_z(door.get_center().x) - shift))
	trail_u = fire_pit.x + (-2.6 if woodpile_right else 2.6)
	bridge = Vector2(_trail_at(stream_z(trail_u)), stream_z(trail_u))
	_blocked.append(Rect2(bridge - Vector2(0.75, 1.6), Vector2(1.5, 3.2)))
	_blocked.append(Rect2(trail_u - 1.1, track_z(trail_u) + TRACK_HALF - 0.1, 0.8, 0.9))
	_chair_spots.clear()
	# The lantern hangs from the tall post at the porch's corner by the door steps.
	var by_door: Rect2 = porch_cells[0]
	for cell: Rect2 in porch_cells:
		if absf(cell.get_center().x - door.get_center().x) < absf(by_door.get_center().x - door.get_center().x) \
				or (is_equal_approx(cell.get_center().x, by_door.get_center().x) and cell.position.y < by_door.position.y):
			by_door = cell
	var corner_u: float = by_door.end.x if by_door.get_center().x < door.get_center().x else by_door.position.x
	var inward: float = -1.0 if by_door.get_center().x < door.get_center().x else 1.0
	_lantern_at = Vector3(corner_u - inward * 0.1, patio_top + PATIO_LANTERN_POST - 0.15, by_door.end.y - 0.04)


func _porch_posts() -> Array[float]:
	var posts: Array[float] = []
	var count: int = maxi(2, int(porch.size.x / 1.1) + 1)
	for index: int in count:
		posts.append(lerpf(porch.position.x + 0.05, porch.end.x - 0.05, float(index) / float(count - 1)))
	return posts


func _build_static() -> Dictionary:
	var meshes: Dictionary = {}
	var ground: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var props: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var shadows: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	_chunks.clear()
	_ground(ground)
	_track(ground, props)
	_stream_banks(ground, props)
	_trees(shadows)
	_undergrowth(props, shadows)
	_porch(props, shadows)
	_woodpile(props, shadows)
	_fire_pit(props, shadows)
	_footbridge(props, shadows)
	_trail_sign(props, shadows)
	_glade_trees(shadows)
	meshes["ground"] = ground.soup.to_mesh()
	var keys: Array[Vector2i] = _chunks.keys()
	keys.sort()
	var chunk_meshes: Array[ArrayMesh] = []
	for chunk: Vector2i in keys:
		chunk_meshes.append(_chunks[chunk].to_mesh())
	meshes["forest"] = chunk_meshes
	_chunks.clear()
	meshes["props"] = props.soup.to_mesh()
	meshes["shadows"] = shadows.to_mesh()
	meshes["stream"] = _stream_mesh()
	for stand_entry: Stand in stands:
		_build_stand(stand_entry, meshes)
		meshes["crowns:" + String(stand_entry.id)] = stand_entry.crowns
	_light_meshes(meshes)
	return meshes


# --- ground ---------------------------------------------------------------

func _ground(pen: NeighbourhoodBuildings.Pen) -> void:
	var outer: float = NeighbourhoodGround.WORLD_HALF + NeighbourhoodGround.BEYOND
	var c: Vector2 = world_centre
	pen.flat(c.x - outer, c.y - outer, c.x + outer, c.y + outer, FLOOR_Y, skin.forest_floor)
	# The open band: the yard, the track's verges and the glade, as one strip across the
	# world, over a mossy fringe where the grass gives way to the forest floor.
	var step: float = 0.8
	var lot: Rect2 = _reserve_rect().grow(STAND_GAP)
	for layer: int in 2:
		var fringe: float = 0.75 if layer == 0 else 0.0
		var y: float = GRASS_Y - 0.004 if layer == 0 else GRASS_Y
		var colour: Color = skin.moss.lerp(skin.grass_dark, 0.5) if layer == 0 else skin.grass
		var u: float = c.x - outer
		while u < c.x + outer:
			var u1: float = u + step
			var w0: float = fringe * (0.7 + 0.5 * _r(int(u * 2.0), 7))
			var w1: float = fringe * (0.7 + 0.5 * _r(int(u1 * 2.0), 7))
			pen.quad(Vector3(u, y, open_near(u) - w0), Vector3(u1, y, open_near(u1) - w1),
				Vector3(u1, y, open_far(u1) + w1), Vector3(u, y, open_far(u) + w0), Vector3.UP, colour)
			u = u1
		# The lot itself, and the gap round it, is clearing too.
		var area: Rect2 = lot.grow(fringe)
		pen.flat(area.position.x, area.position.y, area.end.x, area.end.y, y, colour)
	# Grass patches in the open, needle litter, moss and sun flecks under the trees.
	var span: float = 30.0
	for index: int in 420:
		var at: Vector2 = Vector2(_centre_u() + (_r(index, 1) * 2.0 - 1.0) * span, shift + (_r(index, 2) * 2.0 - 1.0) * span)
		var size: float = 0.4 + _r(index, 3) * 1.1
		var open: bool = _is_open(at, -size * 0.6)
		var colour: Color
		if open:
			if _on_track(at, size) or _on_stream(at, size):
				continue
			colour = skin.grass_light if _r(index, 4) < 0.5 else skin.grass_dark
			if _reserve_rect().grow(STAND_GAP).has_point(at):
				# Gentler over the lot, where the player builds.
				colour = skin.grass.lerp(colour, 0.5)
		elif not _is_open(at, size + 0.2):
			var roll: float = _r(index, 4)
			if roll < 0.4:
				colour = skin.floor_dark
			elif roll < 0.72:
				colour = skin.moss
			elif _near_edge(at, 4.0):
				colour = skin.sun_fleck
				size *= 0.6
			else:
				colour = skin.moss.lerp(skin.forest_floor, 0.5)
		else:
			continue
		_blob(pen, at, size, size * (0.55 + _r(index, 5) * 0.4), _r(index, 6) * PI, 7, PATCH_Y + _r(index, 7) * 0.002, colour)


func _blob(pen: NeighbourhoodBuildings.Pen, at: Vector2, rx: float, rz: float, spin: float, sides: int, y: float, colour: Color) -> void:
	var points: Array[Vector3] = []
	for index: int in sides:
		var angle: float = spin + TAU * float(index) / float(sides)
		var wobble: float = 0.85 + 0.3 * _r(int(at.x * 37.0) + index, int(at.y * 41.0))
		points.append(Vector3(at.x + cos(angle) * rx * wobble, y, at.y + sin(angle) * rz * wobble))
	for index: int in sides:
		pen.tri(Vector3(at.x, y, at.y), points[index], points[(index + 1) % sides], Vector3.UP, colour)


## The dirt track: a darker rim, packed earth, dusty patches and stones, winding out
## through the trees at both ends.
func _track(ground: NeighbourhoodBuildings.Pen, props: NeighbourhoodBuildings.Pen) -> void:
	var outer: float = NeighbourhoodGround.WORLD_HALF + NeighbourhoodGround.BEYOND
	_ribbon(ground, world_centre.x - outer, world_centre.x + outer, 0.5, TRACK_HALF + 0.2, EDGE_Y, skin.track_edge, false)
	_ribbon(ground, world_centre.x - outer, world_centre.x + outer, 0.5, TRACK_HALF, TRACK_Y, skin.track, true)
	# Worn, paler patches of dust and darker damp ones along the track.
	for index: int in 160:
		var u: float = world_centre.x + (_r(index, 61) * 2.0 - 1.0) * (NeighbourhoodGround.WORLD_HALF + 4.0)
		var across: float = (_r(index, 62) - 0.5) * TRACK_HALF * 1.2
		var size: float = 0.22 + _r(index, 63) * 0.4
		var tone: Color = skin.track.lightened(0.07) if _r(index, 64) < 0.65 else skin.track.darkened(0.06)
		_blob(ground, Vector2(u, track_z(u) + across), size * 1.6, size * 0.7, _r(index, 65) * 0.5, 7, DUST_Y + _r(index, 66) * 0.002, tone)
	# The path from the door down to the track: flat stepping stones.
	var door_u: float = _door_u()
	var z: float = shift + 0.35
	var index: int = 0
	while z < track_z(door_u) - TRACK_HALF:
		var at: Vector2 = Vector2(door_u + (_r(index, 71) - 0.5) * 0.22, z)
		_blob(ground, at, 0.2 + _r(index, 72) * 0.06, 0.16, _r(index, 73) * PI, 6, DUST_Y, skin.stone.lightened(0.08))
		z += 0.48
		index += 1
	# Stones along the edges.
	for stone_index: int in 90:
		var u: float = _centre_u() + (_r(stone_index, 81) * 2.0 - 1.0) * 30.0
		var side: float = -1.0 if _r(stone_index, 82) < 0.5 else 1.0
		var at: Vector2 = Vector2(u, track_z(u) + side * (TRACK_HALF + 0.05 + _r(stone_index, 83) * 0.25))
		if _is_blocked(at, 0.1):
			continue
		var size: float = 0.05 + _r(stone_index, 84) * 0.07
		props.lump(Vector3(at.x, TRACK_Y + size * 0.3, at.y), size, size * 0.6, size * 0.8, _r(stone_index, 85) * TAU,
			skin.pebble, skin.stone_dark)


func _door_u() -> float:
	for rect: Rect2 in keep_clear:
		if rect.end.y > shift - 0.05:
			return rect.get_center().x
	return _centre_u()


## A strip following the track's centre line, `half` either side (its rough edge wobbles).
func _ribbon(pen: NeighbourhoodBuildings.Pen, from: float, to: float, step: float, half: float, y: float, colour: Color, rough: bool) -> void:
	var u: float = from
	while u < to:
		var u1: float = minf(u + step, to)
		var w0: float = half + (0.06 * sin(u * 1.7) + 0.04 * sin(u * 4.3) if rough else 0.0)
		var w1: float = half + (0.06 * sin(u1 * 1.7) + 0.04 * sin(u1 * 4.3) if rough else 0.0)
		var z0: float = track_z(u)
		var z1: float = track_z(u1)
		pen.quad(Vector3(u, y, z0 - w0), Vector3(u1, y, z1 - w1), Vector3(u1, y, z1 + w1), Vector3(u, y, z0 + w0), Vector3.UP, colour)
		u = u1


## The stream's muddy banks, the side trail, and stones and reeds at the water's edge.
func _stream_banks(ground: NeighbourhoodBuildings.Pen, props: NeighbourhoodBuildings.Pen) -> void:
	var outer: float = NeighbourhoodGround.WORLD_HALF + NeighbourhoodGround.BEYOND
	var u: float = world_centre.x - outer
	while u < world_centre.x + outer:
		var u1: float = u + 0.5
		var w0: float = _stream_half(u) + 0.24 + 0.06 * sin(u * 2.3)
		var w1: float = _stream_half(u1) + 0.24 + 0.06 * sin(u1 * 2.3)
		ground.quad(Vector3(u, BANK_Y, stream_z(u) - w0), Vector3(u1, BANK_Y, stream_z(u1) - w1),
			Vector3(u1, BANK_Y, stream_z(u1) + w1), Vector3(u, BANK_Y, stream_z(u) + w0), Vector3.UP, skin.bank)
		u = u1
	# The side trail: off the track, over the footbridge and on into the trees.
	var z: float = track_z(trail_u)
	var end: float = open_far(trail_u) + 7.0
	while z < end:
		var z1: float = z + 0.5
		var a: float = _trail_at(z)
		var b: float = _trail_at(z1)
		ground.quad(Vector3(a - 0.4, TRACK_Y, z), Vector3(a + 0.4, TRACK_Y, z), Vector3(b + 0.4, TRACK_Y, z1),
			Vector3(b - 0.4, TRACK_Y, z1), Vector3.UP, skin.track_edge)
		ground.quad(Vector3(a - 0.3, DUST_Y, z), Vector3(a + 0.3, DUST_Y, z), Vector3(b + 0.3, DUST_Y, z1),
			Vector3(b - 0.3, DUST_Y, z1), Vector3.UP, skin.track)
		z = z1
	# Stones in and beside the water, and reeds.
	for index: int in 140:
		var su: float = _centre_u() + (_r(index, 91) * 2.0 - 1.0) * 34.0
		var side: float = -1.0 if _r(index, 92) < 0.5 else 1.0
		var at: Vector2 = Vector2(su, stream_z(su) + side * (_stream_half(su) + (_r(index, 93) - 0.35) * 0.5))
		if _is_blocked(at, 0.2):
			continue
		if _r(index, 94) < 0.55:
			var size: float = 0.06 + _r(index, 95) * 0.1
			props.lump(Vector3(at.x, WATER_Y + size * 0.25, at.y), size * 1.2, size * 0.7, size, _r(index, 96) * TAU,
				skin.stone if _r(index, 97) < 0.6 else skin.pebble, skin.stone_dark)
		else:
			_tuft(props, Vector3(at.x, BANK_Y, at.y), 0.35 + _r(index, 98) * 0.25, skin.fern_colors[index % skin.fern_colors.size()].lerp(skin.grass_dark, 0.4), index)


## The water: one strip with UVs along and across, for the stream shader.
func _stream_mesh() -> ArrayMesh:
	var outer: float = NeighbourhoodGround.WORLD_HALF + NeighbourhoodGround.BEYOND
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var u: float = world_centre.x - outer
	var along: float = 0.0
	while u < world_centre.x + outer:
		var u1: float = u + 0.5
		var a: float = stream_z(u)
		var b: float = stream_z(u1)
		var length: float = Vector2(0.5, b - a).length()
		var corners: Array[Vector3] = [Vector3(u, a - _stream_half(u), -1.0), Vector3(u1, b - _stream_half(u1), -1.0),
			Vector3(u1, b + _stream_half(u1), 1.0), Vector3(u, a + _stream_half(u), 1.0)]
		var alongs: Array[float] = [along, along + length, along + length, along]
		for corner: int in [0, 1, 2, 0, 2, 3]:
			vertices.append(Vector3(corners[corner].x, WATER_Y, corners[corner].y))
			normals.append(Vector3.UP)
			uvs.append(Vector2(alongs[corner], corners[corner].z))
		along += length
		u = u1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- trees ----------------------------------------------------------------

## The forest past the clearing: dense pines to the world's edge, smaller near the lot,
## tall along the track as it leaves, with a few birches at the glade's edge.
func _trees(shadows: NeighbourhoodGround.Soup) -> void:
	var cell: float = 1.75
	var half: float = NeighbourhoodGround.WORLD_HALF + 1.0
	var steps: int = int(half * 2.0 / cell)
	var origin: Vector2 = world_centre - Vector2.ONE * half
	for ix: int in steps:
		for iz: int in steps:
			var at: Vector2 = origin + Vector2((float(ix) + 0.15 + _r(ix, iz) * 0.7) * cell, (float(iz) + 0.15 + _r(iz, ix + 999) * 0.7) * cell)
			var seed_value: int = ix * 1031 + iz
			var size: float = 0.95 + _r(seed_value, 11) * 0.55
			var crown: float = size * 0.95
			if _is_open(at, crown * 0.75 + 0.2) or _in_stand(at, crown * 0.6) or _on_stream(at, 0.55 + crown * 0.4) \
					or _on_trail(at, 0.3 + crown * 0.5) or _on_track(at, 0.5 + crown * 0.6):
				continue
			var soup: NeighbourhoodGround.Soup = _chunk(at)
			var edge: bool = _near_edge(at, 3.0)
			var lot_distance: float = _distance_to_lot(at)
			size *= clampf(0.55 + lot_distance / 12.0, 0.6, 1.0)
			if edge and _r(seed_value, 12) < 0.16:
				_birch(soup, at, size * 0.85, seed_value)
			else:
				_pine(soup, at, size, seed_value, lot_distance < 26.0)
			if edge:
				_tree_shadow(shadows, at, size)


## A few lone trees out in the glade beyond the stream, and one by the yard.
func _glade_trees(shadows: NeighbourhoodGround.Soup) -> void:
	var spots: Array[Vector2] = []
	for index: int in 5:
		var u: float = _centre_u() + (float(index) - 2.0) * 5.2 + (_r(index, 221) - 0.5) * 2.0
		var z: float = lerpf(stream_z(u) + _stream_half(u) + 1.3, open_far(u) - 0.6, 0.3 + _r(index, 222) * 0.5)
		spots.append(Vector2(u, z))
	for index: int in spots.size():
		var at: Vector2 = spots[index]
		if _on_trail(at, 1.2) or _is_blocked(at, 1.0) or not _is_open(at, -0.5):
			continue
		var size: float = 0.85 + _r(index, 223) * 0.3
		var soup: NeighbourhoodGround.Soup = _chunk(at)
		if index % 2 == 0:
			_birch(soup, at, size, index + 4000)
		else:
			_pine(soup, at, size * 1.05, index + 4000, true)
		_tree_shadow(shadows, at, size)


## The forest chunk a tree at `at` goes in.
func _chunk(at: Vector2) -> NeighbourhoodGround.Soup:
	var key: Vector2i = Vector2i(floori((at.x - world_centre.x) / CHUNK), floori((at.y - world_centre.y) / CHUNK))
	if not _chunks.has(key):
		_chunks[key] = NeighbourhoodGround.Soup.new()
	return _chunks[key]


## A pine: a trunk and four stacked cones, darker low down, lighter at the tip.
func _pine(soup: NeighbourhoodGround.Soup, at: Vector2, size: float, seed_value: int, detailed: bool) -> void:
	var keep: float = soup.sway
	soup.sway = 1.0
	_pine_body(soup, at, size, seed_value, detailed)
	soup.sway = keep


func _pine_body(soup: NeighbourhoodGround.Soup, at: Vector2, size: float, seed_value: int, detailed: bool) -> void:
	var yaw: float = _r(seed_value, 21) * TAU
	var tone: Color = skin.pine_colors[int(_r(seed_value, 22) * 97.0) % skin.pine_colors.size()]
	var base: Vector3 = Vector3(at.x, FLOOR_Y, at.y)
	var trunk_height: float = 0.55 * size
	soup.add(_template("trunk"), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.085 * size, trunk_height + 0.4 * size, 0.085 * size)), base), skin.trunk)
	var tiers: int = 4 if detailed else 3
	for tier: int in tiers:
		var radius: float = size * (0.9 - 0.2 * float(tier)) * (1.0 if detailed else 1.08)
		var lift: float = trunk_height + size * 0.56 * float(tier) * (1.0 if detailed else 1.25)
		var shade: Color = tone.darkened(0.12 - 0.08 * float(tier)) if tier < 2 else tone.lightened(0.07 * float(tier - 1))
		soup.add(_template("cone"), Transform3D(Basis(Vector3.UP, yaw + float(tier) * 0.7).scaled(Vector3.ONE * radius), base + Vector3(0.0, lift, 0.0)), shade)


## A birch: a pale trunk and two lumpy rounded crowns.
func _birch(soup: NeighbourhoodGround.Soup, at: Vector2, size: float, seed_value: int) -> void:
	var keep: float = soup.sway
	soup.sway = 1.0
	_birch_body(soup, at, size, seed_value)
	soup.sway = keep


func _birch_body(soup: NeighbourhoodGround.Soup, at: Vector2, size: float, seed_value: int) -> void:
	var yaw: float = _r(seed_value, 31) * TAU
	var leaf: Color = skin.leaf_colors[int(_r(seed_value, 32) * 97.0) % skin.leaf_colors.size()]
	var base: Vector3 = Vector3(at.x, FLOOR_Y, at.y)
	soup.add(_template("trunk"), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.06 * size, 1.5 * size, 0.06 * size)), base), skin.birch_bark)
	soup.add(_template("ball"), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.62, 0.75, 0.62) * size), base + Vector3(0.0, 1.55 * size, 0.0)), leaf)
	soup.add(_template("ball"), Transform3D(Basis(Vector3.UP, yaw + 1.0).scaled(Vector3(0.42, 0.5, 0.42) * size),
		base + Vector3(0.18 * size, 2.05 * size, -0.12 * size)), leaf.lightened(0.08))


func _tree_shadow(shadows: NeighbourhoodGround.Soup, at: Vector2, size: float) -> void:
	var centre: Vector2 = at + light_shift * size * 0.9
	var points: Array[Vector2] = []
	for index: int in 9:
		var angle: float = TAU * float(index) / 9.0
		points.append(centre + Vector2(cos(angle) * size * 0.85, sin(angle) * size * 0.62))
	shadows.star(centre, points, SHADOW_Y, Color(0.08, 0.1, 0.06, 0.32))


static func _template(key: String) -> Array:
	if _templates.has(key):
		return _templates[key]
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	match key:
		"cone":
			# Unit radius, 1.5 high: one pine tier.
			var sides: int = 7
			for index: int in sides:
				var a0: float = TAU * float(index) / float(sides)
				var a1: float = TAU * float(index + 1) / float(sides)
				var p0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
				var p1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
				var hint: Vector3 = (p0 + p1) * 0.5 + Vector3.UP * 0.6
				soup.tri(p0, p1, Vector3(0.0, 1.5, 0.0), hint, Color.WHITE)
				soup.tri(p1, p0, Vector3(0.0, 0.0, 0.0), Vector3.DOWN, Color.WHITE)
		"trunk":
			# Unit radius, 1 high, six sides, no caps.
			for index: int in 6:
				var a0: float = TAU * float(index) / 6.0
				var a1: float = TAU * float(index + 1) / 6.0
				var p0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
				var p1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
				var hint: Vector3 = (p0 + p1) * 0.5
				soup.tri(p0, p1, p1 + Vector3.UP, hint, Color.WHITE)
				soup.tri(p0, p1 + Vector3.UP, p0 + Vector3.UP, hint, Color.WHITE)
		_:
			# "ball": a lumpy low-poly ball of unit radius.
			var rings: Array[Array] = []
			for row: int in 4:
				var lat: float = -PI * 0.5 + PI * float(row) / 3.0
				var ring: Array[Vector3] = []
				for index: int in 6:
					var lon: float = TAU * float(index) / 6.0 + (0.5 if row % 2 == 1 else 0.0)
					ring.append(Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)))
				rings.append(ring)
			for row: int in 3:
				for index: int in 6:
					var a: Vector3 = rings[row][index]
					var b: Vector3 = rings[row][(index + 1) % 6]
					var c: Vector3 = rings[row + 1][index]
					var d: Vector3 = rings[row + 1][(index + 1) % 6]
					soup.tri(a, b, d, (a + b + d) / 3.0, Color.WHITE)
					soup.tri(a, d, c, (a + d + c) / 3.0, Color.WHITE)
	_templates[key] = [soup.positions, soup.normals]
	return _templates[key]


# --- the named stands ---------------------------------------------------------

## A stand's three looks: its trees and ferns; their stumps, felled logs and
## churned earth; and cleared ground with young grass and one neat stack of logs.
func _build_stand(stand_entry: Stand, meshes: Dictionary) -> void:
	var forest: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var forest_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var fern_pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	fern_pen.soup = forest
	var stumps: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var stumps_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var cleared: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var cleared_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var rect: Rect2 = stand_entry.rect
	var crowns: Rect2 = rect
	var cell: float = 1.3
	var columns: int = maxi(1, int(rect.size.x / cell))
	var rows: int = maxi(1, int(rect.size.y / cell))
	var salt_id: int = String(stand_entry.id).hash() & 0xffff
	stand_entry.trees.clear()
	for ix: int in columns:
		for iz: int in rows:
			var seed_value: int = salt_id * 7 + ix * 131 + iz
			var at: Vector2 = rect.position + Vector2((float(ix) + 0.2 + _r(seed_value, 41) * 0.6) * rect.size.x / float(columns),
				(float(iz) + 0.2 + _r(seed_value, 42) * 0.6) * rect.size.y / float(rows))
			var distance: float = _distance_to_lot(at)
			# Young pines at the lot's edge, tall ones further in. A crown never reaches
			# past the line of the lot's edge it faces, so the stand's box stays clear of it.
			var size: float = (0.5 + clampf(distance / 5.5, 0.0, 1.0) * 0.75) * (0.9 + _r(seed_value, 43) * 0.25)
			var lot: Rect2 = _reserve_rect()
			var clear: float = lot.position.y - at.y if stand_entry.behind else maxf(lot.position.x - at.x, at.x - lot.end.x)
			if clear < size * 0.95 + 0.05:
				size = (clear - 0.05) / 0.95
			if size < 0.35:
				# Too close for a tree: a fern or a bush instead.
				_fern(fern_pen, Vector3(at.x, FLOOR_Y, at.y), 0.3, skin.fern_colors[seed_value % skin.fern_colors.size()], seed_value)
				continue
			_pine(forest, at, size, seed_value, true)
			stand_entry.trees.append(Vector3(at.x, at.y, size))
			crowns = crowns.merge(Rect2(at - Vector2.ONE * size * 0.95, Vector2.ONE * size * 1.9))
			var inner: bool = distance < 3.2
			if inner:
				_tree_shadow(forest_shade, at, size)
			# Stumps: every tree cut to a stump, some felled trunks left lying.
			_stump(stumps, at, size, seed_value)
			if _r(seed_value, 44) < 0.22:
				var angle: float = _r(seed_value, 45) * TAU
				var start: Vector3 = Vector3(at.x + cos(angle) * 0.25, FLOOR_Y + 0.09 * size, at.y + sin(angle) * 0.25)
				var end: Vector3 = start + Vector3(cos(angle), 0.0, sin(angle)) * 1.5 * size
				if rect.has_point(Vector2(end.x, end.z)):
					_log(stumps, start + Vector3.UP * 0.03 * size, end + Vector3.UP * 0.03 * size, 0.12 * size, skin.trunk, skin.log_end)
			# Undergrowth stays in the forest look.
			if _r(seed_value, 46) < 0.4:
				var fern_at: Vector3 = Vector3(at.x + 0.5, FLOOR_Y, at.y + 0.35)
				_fern(fern_pen, fern_at, 0.28 + _r(seed_value, 47) * 0.15, skin.fern_colors[seed_value % skin.fern_colors.size()], seed_value)
	stand_entry.crowns = crowns
	# Stumps: churned earth and sawdust under them.
	for index: int in 22:
		var at: Vector2 = rect.position + Vector2(_r(salt_id + index, 51), _r(salt_id + index, 52)) * rect.size
		_blob(stumps, at, 0.5 + _r(salt_id + index, 53) * 0.9, 0.4 + _r(salt_id + index, 54) * 0.6, _r(salt_id + index, 55) * PI, 7,
			STAND_Y + _r(salt_id + index, 56) * 0.002, skin.bank if index % 3 == 0 else skin.floor_dark)
	for tree: Vector3 in stand_entry.trees:
		_blob(stumps, Vector2(tree.x, tree.y) + Vector2(0.12, 0.08), 0.16 * tree.z + 0.06, 0.12 * tree.z + 0.05, 0.3, 6, STAND_Y + 0.003, skin.log_end.darkened(0.25))
		_shade_disc(stumps_shade, Vector2(tree.x, tree.y) + light_shift * 0.12, 0.14 * tree.z + 0.06, 0.3)
	# Cleared: the clearing's grass spreads over the stand (its edge against the trees
	# left ragged), with a few bare and darker patches, tufts, and a log stack.
	var lot_side: Rect2 = _reserve_rect().grow(STAND_GAP + 0.05)
	var grass: Rect2 = rect.grow(0.35).merge(rect.grow(0.35).intersection(lot_side))
	cleared.flat(grass.position.x, grass.position.y, grass.end.x, grass.end.y, STAND_Y, skin.grass)
	var perimeter: float = (rect.size.x + rect.size.y) * 2.0
	var steps: int = int(perimeter / 0.9)
	for index: int in steps:
		var t: float = float(index) / float(steps) * perimeter
		var edge_at: Vector2
		if t < rect.size.x:
			edge_at = rect.position + Vector2(t, 0.0)
		elif t < rect.size.x + rect.size.y:
			edge_at = rect.position + Vector2(rect.size.x, t - rect.size.x)
		elif t < rect.size.x * 2.0 + rect.size.y:
			edge_at = rect.end - Vector2(t - rect.size.x - rect.size.y, 0.0)
		else:
			edge_at = rect.end - Vector2(rect.size.x, t - rect.size.x * 2.0 - rect.size.y)
		if lot_side.grow(0.6).has_point(edge_at):
			continue
		var size: float = 0.45 + _r(salt_id + index, 67) * 0.5
		_blob(cleared, edge_at, size, size * 0.8, _r(salt_id + index, 68) * PI, 7, STAND_Y - 0.001, skin.grass)
	for index: int in 14:
		var at: Vector2 = rect.position + Vector2(_r(salt_id + index, 61), _r(salt_id + index, 62)) * rect.size
		var bare: bool = index % 4 == 0
		var size: float = 0.25 + _r(salt_id + index, 63) * (0.3 if bare else 0.6)
		_blob(cleared, at, size, size * 0.75, _r(salt_id + index, 65) * PI, 7,
			STAND_Y + 0.003 + _r(salt_id + index, 66) * 0.002, skin.track_edge if bare else (skin.grass_dark if index % 2 == 0 else skin.grass_light))
		_tuft(cleared, Vector3(at.x + 0.3, STAND_Y, at.y), 0.22, skin.grass_dark, salt_id + index)
	var stack_at: Vector2 = rect.get_center()
	_log_stack(cleared, cleared_shade, stack_at, 1.2, 3)
	meshes["%s:Forest" % stand_entry.id] = forest.to_mesh()
	meshes["%s:Forest:shade" % stand_entry.id] = forest_shade.to_mesh()
	meshes["%s:Stumps" % stand_entry.id] = stumps.soup.to_mesh()
	meshes["%s:Stumps:shade" % stand_entry.id] = stumps_shade.to_mesh()
	meshes["%s:Cleared" % stand_entry.id] = cleared.soup.to_mesh()
	meshes["%s:Cleared:shade" % stand_entry.id] = cleared_shade.to_mesh()


## A land stand's three looks (#611). Forest: young pines on a forest floor that
## spreads from the first lease's edge out over the fringe to the woods round the lot,
## its edge ragged with moss, with ferns where a tree would not fit. Stumps (the land
## once leased): every tree felled flush, its cut face at ground level, in churned
## earth and sawdust, so nothing stands above the ground where the player builds.
## Cleared: the lot's grass with a few worn patches. Every crown keeps off the first
## lease, the door's approach and the yard's pieces.
func _build_land(stand_entry: Stand, meshes: Dictionary) -> void:
	var forest: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var forest_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var stumps: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var stumps_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var cleared: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var cleared_shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var rect: Rect2 = stand_entry.rect
	var start: Rect2 = first_lease.intersection(_reserve_rect())
	var salt_id: int = String(stand_entry.id).hash() & 0xffff
	# The forest floor, out over the grass fringe to meet the woods round the lot.
	var fringe: float = 0.85
	var outward: Rect2 = rect
	if stand_entry.behind:
		outward = rect.grow_individual(0.0, fringe, 0.0, 0.0)
	elif rect.get_center().x < start.get_center().x:
		outward = rect.grow_individual(fringe, fringe, 0.0, 0.0)
	else:
		outward = rect.grow_individual(0.0, fringe, fringe, 0.0)
	forest.flat(outward.position.x, outward.position.y, outward.end.x, outward.end.y, STAND_Y, skin.forest_floor)
	# A ragged mossy edge along the sides that face the lease and the yard.
	var edges: Array[PackedVector2Array] = []
	if stand_entry.behind:
		edges.append(PackedVector2Array([Vector2(rect.position.x, rect.end.y), rect.end]))
	else:
		var inner: float = rect.end.x if rect.get_center().x < start.get_center().x else rect.position.x
		edges.append(PackedVector2Array([Vector2(inner, rect.position.y), Vector2(inner, rect.end.y)]))
		edges.append(PackedVector2Array([Vector2(outward.position.x, rect.end.y), Vector2(outward.end.x, rect.end.y)]))
	var blob_index: int = 0
	for edge: PackedVector2Array in edges:
		var length: float = edge[0].distance_to(edge[1])
		var count: int = maxi(2, int(length / 0.55))
		for index: int in count:
			var at: Vector2 = edge[0].lerp(edge[1], (float(index) + 0.5) / float(count))
			var seed_value: int = salt_id + blob_index * 17
			blob_index += 1
			var size: float = 0.28 + _r(seed_value, 71) * 0.22
			_blob(forest, at, size, size * 0.8, _r(seed_value, 72) * PI, 7, STAND_Y + 0.001,
				skin.moss.lerp(skin.grass_dark, 0.5) if index % 2 == 0 else skin.moss)
	# Needle litter and moss under the trees.
	var patches: int = int(rect.get_area() / 1.2) + 2
	for index: int in patches:
		var at: Vector2 = rect.position + Vector2(_r(salt_id + index, 73), _r(salt_id + index, 74)) * rect.size
		var size: float = 0.25 + _r(salt_id + index, 75) * 0.4
		var roll: float = _r(salt_id + index, 76)
		var colour: Color = skin.floor_dark if roll < 0.45 else (skin.moss if roll < 0.85 else skin.sun_fleck)
		_blob(forest, at, size, size * 0.7, _r(salt_id + index, 77) * PI, 7, STAND_Y + 0.002, colour)
	# Young pines, a little taller away from the lease, on a jittered grid.
	var cell: float = 1.0
	var columns: int = maxi(1, int(rect.size.x / cell))
	var rows: int = maxi(1, int(rect.size.y / cell))
	var crowns: Rect2 = Rect2()
	stand_entry.trees.clear()
	for ix: int in columns:
		for iz: int in rows:
			var seed_value: int = salt_id * 7 + ix * 131 + iz
			var at: Vector2 = rect.position + Vector2((float(ix) + 0.25 + _r(seed_value, 81) * 0.5) * rect.size.x / float(columns),
				(float(iz) + 0.25 + _r(seed_value, 82) * 0.5) * rect.size.y / float(rows))
			var dx: float = maxf(maxf(start.position.x - at.x, at.x - start.end.x), 0.0)
			var dz: float = maxf(maxf(start.position.y - at.y, at.y - start.end.y), 0.0)
			var clear: float = sqrt(dx * dx + dz * dz)
			var size: float = (0.6 + clampf(clear / 3.0, 0.0, 1.0) * 0.5) * (0.9 + _r(seed_value, 83) * 0.25)
			# The crown keeps off the lease, and off the yard in front of the lot.
			var room: float = minf(clear, shift + 0.25 - at.y)
			if room < size * 0.95 + 0.05:
				size = (room - 0.05) / 0.95
			while size >= 0.35 and _is_blocked(at, size * 0.95):
				size -= 0.1
			if size < 0.35:
				if not _is_blocked(at, 0.3) and at.y < shift - 0.3:
					_fern(forest, Vector3(at.x, FLOOR_Y, at.y), 0.3, skin.fern_colors[seed_value % skin.fern_colors.size()], seed_value)
				continue
			var soup: NeighbourhoodGround.Soup = forest.soup
			_pine(soup, at, size, seed_value, true)
			stand_entry.trees.append(Vector3(at.x, at.y, size))
			var crown: Rect2 = Rect2(at - Vector2.ONE * size * 0.95, Vector2.ONE * size * 1.9)
			crowns = crown if not crowns.has_area() else crowns.merge(crown)
			_tree_shadow(forest_shade, at, size)
			if _r(seed_value, 84) < 0.45:
				var fern_at: Vector2 = at + Vector2(0.38, 0.3)
				if rect.has_point(fern_at) and not _is_blocked(fern_at, 0.3):
					_fern(forest, Vector3(fern_at.x, FLOOR_Y, fern_at.y), 0.26 + _r(seed_value, 85) * 0.12,
						skin.fern_colors[(seed_value + 1) % skin.fern_colors.size()], seed_value + 1)
			# Felled: a stump cut flush, its face just under the floor line.
			var radius: float = 0.1 * size + 0.04
			_drum(stumps, Vector3(at.x, STAND_Y, at.y), radius * 1.12, radius, 0.034, 7, skin.trunk, skin.log_end, _r(seed_value, 86))
			_disc_top(stumps, Vector3(at.x, STAND_Y + 0.0345, at.y), radius * 0.5, 7, skin.log_end.darkened(0.18))
			_shade_disc(stumps_shade, at + light_shift * 0.05, radius * 1.25, 0.18)
	stand_entry.crowns = crowns if crowns.has_area() else rect
	# Felled ground: churned earth, sawdust and a few wood chips (all flat).
	for index: int in patches + 4:
		var at: Vector2 = rect.position + Vector2(_r(salt_id + index, 91), _r(salt_id + index, 92)) * rect.size
		var size: float = 0.14 + _r(salt_id + index, 93) * 0.26
		var roll: float = _r(salt_id + index, 94)
		var colour: Color = skin.bank.lerp(skin.grass_dark, 0.35) if roll < 0.45 else (skin.grass_dark if roll < 0.75 else skin.log_end.lerp(skin.grass, 0.45))
		_blob(stumps, at, size, size * 0.75, _r(salt_id + index, 95) * PI, 7, STAND_Y + 0.001 + _r(salt_id + index, 96) * 0.002, colour)
	# Cleared: the grass, worn in a few places.
	for index: int in maxi(2, int(patches / 3.0)):
		var at: Vector2 = rect.position + Vector2(_r(salt_id + index, 97), _r(salt_id + index, 98)) * rect.size
		var size: float = 0.2 + _r(salt_id + index, 99) * 0.3
		_blob(cleared, at, size, size * 0.7, _r(salt_id + index, 100) * PI, 7, STAND_Y + 0.001,
			skin.grass_dark if index % 2 == 0 else skin.grass_light)
	meshes["%s:Forest" % stand_entry.id] = _mesh_of(forest.soup)
	meshes["%s:Forest:shade" % stand_entry.id] = _mesh_of(forest_shade)
	meshes["%s:Stumps" % stand_entry.id] = _mesh_of(stumps.soup)
	meshes["%s:Stumps:shade" % stand_entry.id] = _mesh_of(stumps_shade)
	meshes["%s:Cleared" % stand_entry.id] = _mesh_of(cleared.soup)
	meshes["%s:Cleared:shade" % stand_entry.id] = _mesh_of(cleared_shade)


## A soup's mesh, or an empty mesh when nothing was drawn.
static func _mesh_of(soup: NeighbourhoodGround.Soup) -> ArrayMesh:
	return soup.to_mesh() if soup.positions.size() > 0 else ArrayMesh.new()


func _stump(pen: NeighbourhoodBuildings.Pen, at: Vector2, size: float, seed_value: int) -> void:
	var radius: float = 0.1 * size + 0.03
	var height: float = 0.12 + _r(seed_value, 48) * 0.1
	_drum(pen, Vector3(at.x, FLOOR_Y, at.y), radius * 1.15, radius, height, 7, skin.trunk, skin.log_end, _r(seed_value, 49))
	# The cut face's darker heart.
	_disc_top(pen, Vector3(at.x, FLOOR_Y + height + 0.003, at.y), radius * 0.45, 7, skin.log_end.darkened(0.18))


# --- small pieces -----------------------------------------------------------

## An upright drum: `r0` at the foot, `r1` at the top, with a capped top.
func _drum(pen: NeighbourhoodBuildings.Pen, base: Vector3, r0: float, r1: float, height: float, sides: int, side: Color, top: Color, spin: float = 0.0) -> void:
	for index: int in sides:
		var a0: float = spin + TAU * float(index) / float(sides)
		var a1: float = spin + TAU * float(index + 1) / float(sides)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		pen.quad(base + d0 * r0, base + d1 * r0, base + d1 * r1 + Vector3.UP * height, base + d0 * r1 + Vector3.UP * height,
			(d0 + d1) * 0.5, side)
		pen.tri(base + Vector3.UP * height, base + d0 * r1 + Vector3.UP * height, base + d1 * r1 + Vector3.UP * height, Vector3.UP, top)


func _disc_top(pen: NeighbourhoodBuildings.Pen, centre: Vector3, radius: float, sides: int, colour: Color) -> void:
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		pen.tri(centre, centre + Vector3(cos(a0), 0.0, sin(a0)) * radius, centre + Vector3(cos(a1), 0.0, sin(a1)) * radius, Vector3.UP, colour)


## A log between two points: six bark sides and pale cut ends.
func _log(pen: NeighbourhoodBuildings.Pen, a: Vector3, b: Vector3, radius: float, bark: Color, end: Color) -> void:
	var axis: Vector3 = (b - a).normalized()
	var side: Vector3 = axis.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up: Vector3 = side.cross(axis).normalized()
	var ring: Array[Vector3] = []
	for index: int in 6:
		var angle: float = TAU * float(index) / 6.0 + 0.26
		ring.append(side * cos(angle) * radius + up * sin(angle) * radius)
	for index: int in 6:
		var next: int = (index + 1) % 6
		pen.quad(a + ring[index], b + ring[index], b + ring[next], a + ring[next], (ring[index] + ring[next]) * 0.5, bark)
		pen.tri(a, a + ring[index], a + ring[next], -axis, end)
		pen.tri(b, b + ring[next], b + ring[index], axis, end)


## A fern: fronds arching out from the middle.
func _fern(pen: NeighbourhoodBuildings.Pen, at: Vector3, size: float, colour: Color, seed_value: int) -> void:
	var keep: float = pen.soup.sway
	pen.soup.sway = 0.8
	_fern_body(pen, at, size, colour, seed_value)
	pen.soup.sway = keep


func _fern_body(pen: NeighbourhoodBuildings.Pen, at: Vector3, size: float, colour: Color, seed_value: int) -> void:
	var fronds: int = 6 + int(_r(seed_value, 101) * 3.0)
	var spin: float = _r(seed_value, 102) * TAU
	for index: int in fronds:
		var angle: float = spin + TAU * float(index) / float(fronds) + _r(seed_value + index, 103) * 0.3
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var across: Vector3 = Vector3(-out.z, 0.0, out.x) * size * 0.16
		var length: float = size * (0.8 + _r(seed_value + index, 104) * 0.4)
		var mid: Vector3 = at + out * length * 0.5 + Vector3.UP * size * 0.55
		var tip: Vector3 = at + out * length + Vector3.UP * size * 0.18
		var tone: Color = colour.lightened(0.06) if index % 2 == 0 else colour.darkened(0.05)
		pen.tri(at + Vector3.UP * 0.02, mid + across, mid - across, Vector3.UP, tone)
		pen.tri(mid + across, tip, mid - across, Vector3.UP, tone.lightened(0.05))


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
		var across: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * 0.035
		pen.tri(at - across, at + across, at + lean + Vector3.UP * height * (0.7 + 0.3 * _r(seed_value + index, 112)), lean + Vector3.UP * 0.2,
			colour if index % 2 == 0 else colour.lightened(0.08))


## A cluster of toadstools: stems and round caps.
func _mushrooms(pen: NeighbourhoodBuildings.Pen, at: Vector3, seed_value: int) -> void:
	var cap: Color = skin.mushroom_caps[int(_r(seed_value, 121) * 97.0) % skin.mushroom_caps.size()]
	var count: int = 2 + int(_r(seed_value, 122) * 3.0)
	for index: int in count:
		var angle: float = TAU * float(index) / float(count) + _r(seed_value, 123)
		var p: Vector3 = at + Vector3(cos(angle), 0.0, sin(angle)) * (0.04 + 0.06 * float(index % 2))
		var height: float = 0.05 + _r(seed_value + index, 124) * 0.06
		var radius: float = 0.035 + _r(seed_value + index, 125) * 0.03
		pen.box(p + Vector3(-0.012, 0.0, -0.012), p + Vector3(0.012, height, 0.012), skin.mushroom_stem)
		_cap(pen, p + Vector3.UP * height, radius, cap)
		if cap.r > cap.g * 1.6:
			# Spotted red caps get two pale spots.
			pen.box(p + Vector3(-0.012, height + radius * 0.55, -0.012), p + Vector3(0.008, height + radius * 0.62, 0.008), skin.mushroom_stem)


func _cap(pen: NeighbourhoodBuildings.Pen, centre: Vector3, radius: float, colour: Color) -> void:
	var peak: Vector3 = centre + Vector3.UP * radius * 0.75
	for index: int in 6:
		var a0: float = TAU * float(index) / 6.0
		var a1: float = TAU * float(index + 1) / 6.0
		var p0: Vector3 = centre + Vector3(cos(a0), 0.0, sin(a0)) * radius
		var p1: Vector3 = centre + Vector3(cos(a1), 0.0, sin(a1)) * radius
		pen.tri(p0, p1, peak, (p0 + p1) * 0.5 - centre + Vector3.UP * 0.5, colour)
		pen.tri(p1, p0, centre - Vector3.UP * 0.01, Vector3.DOWN, skin.mushroom_stem.darkened(0.1))


func _shade_disc(shadows: NeighbourhoodGround.Soup, at: Vector2, radius: float, alpha: float) -> void:
	var points: Array[Vector2] = []
	for index: int in 8:
		var angle: float = TAU * float(index) / 8.0
		points.append(at + Vector2(cos(angle), sin(angle) * 0.8) * radius)
	shadows.star(at, points, SHADOW_Y, Color(0.08, 0.08, 0.05, alpha))


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
	var centre: Vector2 = rect.get_center() + push * 0.5
	shadows.star(centre, points, SHADOW_Y, Color(0.08, 0.08, 0.05, alpha))


## Ferns, bushes, toadstools, mossy rocks and fallen logs along the trees' edge; wild
## flowers and grass tufts out in the clearing.
func _undergrowth(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var cell: float = 0.85
	var span: float = 26.0
	var steps: int = int(span * 2.0 / cell)
	var origin: Vector2 = Vector2(_centre_u() - span, shift - span * 0.75)
	for ix: int in steps:
		for iz: int in steps:
			var seed_value: int = ix * 977 + iz
			var at: Vector2 = origin + Vector2((float(ix) + _r(seed_value, 131)) * cell, (float(iz) + _r(seed_value, 132)) * cell)
			if _is_blocked(at, 0.25) or _in_stand(at, 0.1) or _on_track(at, 0.12) or _on_stream(at, 0.3) or _on_trail(at, 0.1):
				continue
			if _reserve_rect().grow(0.45).has_point(at):
				continue
			var roll: float = _r(seed_value, 133)
			var p: Vector3 = Vector3(at.x, GRASS_Y, at.y)
			var open: bool = _is_open(at, 0.0)
			var edge: bool = _near_edge(at, 1.3)
			if open and not edge:
				if _reserve_rect().grow(STAND_GAP + 0.1).has_point(at):
					continue
				if roll < 0.08:
					_flowers(pen, p, seed_value)
				elif roll < 0.2:
					_tuft(pen, p, 0.16 + _r(seed_value, 134) * 0.1, skin.grass_dark, seed_value)
				continue
			if roll < (0.42 if edge else 0.2):
				_fern(pen, p, 0.26 + _r(seed_value, 135) * 0.2, skin.fern_colors[seed_value % skin.fern_colors.size()], seed_value)
			elif roll < (0.55 if edge else 0.26):
				var colour: Color = skin.bush_colors[seed_value % skin.bush_colors.size()]
				var size: float = 0.22 + _r(seed_value, 136) * 0.2
				pen.lump(p + Vector3.UP * size * 0.5, size, size * 0.8, size * 0.9, _r(seed_value, 137) * TAU, colour, colour.darkened(0.25))
				if edge:
					_shade_disc(shadows, at + light_shift * size * 0.6, size * 0.9, 0.25)
			elif roll < (0.63 if edge else 0.31):
				_mushrooms(pen, p, seed_value)
			elif roll < (0.67 if edge else 0.33):
				var size: float = 0.12 + _r(seed_value, 138) * 0.16
				pen.lump(p + Vector3.UP * size * 0.3, size * 1.3, size * 0.75, size, _r(seed_value, 139) * TAU, skin.stone, skin.stone_dark)
				pen.lump(p + Vector3(0.0, size * 0.62, 0.0), size * 0.9, size * 0.25, size * 0.7, _r(seed_value, 140) * TAU, skin.moss, skin.moss.darkened(0.2))
			elif edge and roll < 0.69:
				var angle: float = _r(seed_value, 141) * PI
				var dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
				var a: Vector3 = p + Vector3.UP * 0.09 - dir * 0.6
				var b: Vector3 = p + Vector3.UP * 0.09 + dir * 0.6
				var ends: Array[Vector2] = [Vector2(a.x, a.z), Vector2(b.x, b.z)]
				var fits: bool = true
				for end: Vector2 in ends:
					fits = fits and not _is_blocked(end, 0.2) and not _on_track(end, 0.1) and not _on_stream(end, 0.1) \
						and not _reserve_rect().grow(0.3).has_point(end) and not _in_stand(end, 0.0)
				if fits:
					_log(pen, a, b, 0.09, skin.trunk, skin.log_end)
					_mushrooms(pen, p + dir * 0.25 + Vector3(0.0, 0.0, 0.12), seed_value + 3)
	# A few extra toadstool rings in the glade's shade, and flowers by the stream.
	for index: int in 24:
		var u: float = _centre_u() + (_r(index, 151) * 2.0 - 1.0) * 14.0
		var at: Vector2 = Vector2(u, stream_z(u) + (1.0 if _r(index, 152) < 0.5 else -1.0) * (_stream_half(u) + 0.55 + _r(index, 153) * 0.8))
		if _is_blocked(at, 0.3) or _on_track(at, 0.2) or _on_trail(at, 0.2):
			continue
		_flowers(pen, Vector3(at.x, GRASS_Y, at.y), index * 7 + 5)


func _flowers(pen: NeighbourhoodBuildings.Pen, at: Vector3, seed_value: int) -> void:
	var count: int = 3 + int(_r(seed_value, 161) * 3.0)
	var colour: Color = skin.flower_colors[int(_r(seed_value, 162) * 97.0) % skin.flower_colors.size()]
	for index: int in count:
		var p: Vector3 = at + Vector3((_r(seed_value + index, 163) - 0.5) * 0.4, 0.0, (_r(seed_value + index, 164) - 0.5) * 0.4)
		var height: float = 0.07 + _r(seed_value + index, 165) * 0.06
		pen.tri(p + Vector3(-0.01, 0.0, 0.0), p + Vector3(0.01, 0.0, 0.0), p + Vector3(0.0, height, 0.0), Vector3.BACK, skin.grass_dark)
		pen.lump(p + Vector3.UP * height, 0.03, 0.02, 0.03, float(index), colour, colour.darkened(0.2))


# --- the yard ---------------------------------------------------------------

## A timber porch deck along the shop's front: planks, a fascia, posts and a rail, two
## rocking chairs (their own nodes, they rock) and a crate table with a lantern.
func _porch(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	if not porch_cells.is_empty():
		_patio_porch(pen, shadows)
		return
	var r: Rect2 = porch
	var top: float = PORCH_TOP
	# Frame and fascia.
	pen.box(Vector3(r.position.x, -0.04, r.position.y), Vector3(r.end.x, top - 0.03, r.end.y), skin.timber_dark)
	# Planks across the deck, alternating tones, with dark gaps between.
	var plank: float = 0.16
	var count: int = int(r.size.x / plank)
	for index: int in count:
		var x0: float = r.position.x + float(index) * r.size.x / float(count)
		var x1: float = x0 + r.size.x / float(count) - 0.012
		var tone: Color = skin.timber if index % 3 != 1 else skin.timber.darkened(0.08)
		pen.box(Vector3(x0, top - 0.03, r.position.y), Vector3(x1, top, r.end.y + 0.02), tone)
	# A step down at the front, by the door end.
	var step_u: float = r.end.x - 0.55 if r.end.x < _door_u() else r.position.x + 0.05
	pen.box(Vector3(step_u, -0.04, r.end.y), Vector3(step_u + 0.5, top * 0.5, r.end.y + 0.22), skin.timber)
	# Posts and the rail along the front (gap at the step) and the far end.
	var far_end: float = r.position.x if r.end.x < _door_u() else r.end.x
	var posts: Array[float] = _porch_posts()
	var post_count: int = posts.size()
	for u: float in posts:
		pen.box(Vector3(u - 0.035, top, r.end.y - 0.07), Vector3(u + 0.035, top + 0.62, r.end.y), skin.timber_dark)
	pen.box(Vector3(far_end - 0.035, top, r.position.y + 0.05), Vector3(far_end + 0.035, top + 0.62, r.position.y + 0.12), skin.timber_dark)
	for index: int in post_count - 1:
		var a: float = posts[index]
		var b: float = posts[index + 1]
		if step_u + 0.25 > minf(a, b) and step_u + 0.25 < maxf(a, b):
			continue
		pen.box(Vector3(a, top + 0.5, r.end.y - 0.06), Vector3(b, top + 0.56, r.end.y - 0.01), skin.timber)
		pen.box(Vector3(a, top + 0.24, r.end.y - 0.055), Vector3(b, top + 0.27, r.end.y - 0.02), skin.timber)
	pen.box(Vector3(far_end - 0.03, top + 0.5, r.position.y + 0.05), Vector3(far_end + 0.03, top + 0.56, r.end.y), skin.timber)
	_shade_rect(shadows, Rect2(r.position.x, r.end.y - 0.02, r.size.x, 0.05), top + 0.2, 0.3)
	# A crate table between the two rocking chairs (built apart: they rock), with a mug.
	var table: Vector3 = Vector3(r.get_center().x, top, r.end.y - 0.83)
	pen.box(table + Vector3(-0.13, 0.0, -0.11), table + Vector3(0.13, 0.22, 0.11), skin.timber_dark)
	pen.box(table + Vector3(-0.14, 0.2, -0.12), table + Vector3(0.14, 0.23, 0.12), skin.timber)
	# A mug on the crate.
	pen.box(table + Vector3(0.04, 0.23, -0.02), table + Vector3(0.08, 0.28, 0.02), skin.blanket.lightened(0.3))
	# The lantern hangs on the post nearest the door end.
	var lantern_post: float = _lantern_at.x + 0.1
	pen.box(Vector3(lantern_post - 0.13, top + 0.58, r.end.y - 0.05), Vector3(lantern_post - 0.035, top + 0.6, r.end.y - 0.02), skin.timber_dark)
	pen.box(_lantern_at + Vector3(-0.04, 0.07, -0.04), _lantern_at + Vector3(0.04, 0.1, 0.04), skin.timber_dark)
	pen.box(_lantern_at + Vector3(-0.045, -0.08, -0.045), _lantern_at + Vector3(0.045, -0.06, 0.045), skin.timber_dark)



## The shop's own porch (#596): a plank deck on each of the shop's patio cells (any
## floor finish the player lays goes over it), a timber skirt round its open edges down
## to the ground, a waist-high rail on posts along the front and the far sides, open
## where it meets the door's path (steps up from the path), and a taller post by the
## door with the lantern.
func _patio_porch(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var top: float = patio_top
	var door: Rect2 = Rect2(_door_u() - 0.05, shift, 0.1, 1.0)
	for rect: Rect2 in keep_clear:
		if rect.end.y > shift - 0.05:
			door = door.merge(rect)
	var size: float = porch_cells[0].size.x
	var cells: Dictionary[Vector2i, Rect2] = {}
	var origin: Vector2 = porch.position
	for cell: Rect2 in porch_cells:
		cells[Vector2i(roundi((cell.position.x - origin.x) / size), roundi((cell.position.y - origin.y) / size))] = cell
	var first_row: float = porch.position.y
	var steps: Array[Rect2] = []
	for key: Vector2i in cells:
		var r: Rect2 = cells[key]
		# The deck: a frame under three planks a cell, running out from the facade
		# in alternating tones, just under any floor finish the player lays on it.
		pen.box(Vector3(r.position.x, -0.04, r.position.y), Vector3(r.end.x, top - 0.03, r.end.y), skin.timber_dark)
		for plank: int in 3:
			var x0: float = r.position.x + float(plank) * r.size.x / 3.0
			var x1: float = x0 + r.size.x / 3.0 - 0.012
			var tone: Color = skin.timber if (key.x * 3 + plank) % 3 != 1 else skin.timber.darkened(0.08)
			pen.box(Vector3(x0, top - 0.03, r.position.y), Vector3(x1, top - 0.003, r.end.y), tone)
		# Which edges are open: no porch beyond them.
		var open_front: bool = not cells.has(key + Vector2i(0, 1))
		var open_left: bool = not cells.has(key + Vector2i(-1, 0))
		var open_right: bool = not cells.has(key + Vector2i(1, 0))
		var on_path_left: bool = open_left and r.position.x - door.end.x < size * 0.6 and r.position.x > door.position.x
		var on_path_right: bool = open_right and door.position.x - r.end.x < size * 0.6 and r.end.x < door.end.x
		var skirt: float = 0.03
		if open_front:
			pen.box(Vector3(r.position.x, -0.04, r.end.y - 0.02), Vector3(r.end.x, top - 0.004, r.end.y + skirt), skin.timber_dark)
		if open_left:
			pen.box(Vector3(r.position.x - skirt, -0.04, r.position.y), Vector3(r.position.x + 0.02, top - 0.004, r.end.y), skin.timber_dark)
		if open_right:
			pen.box(Vector3(r.end.x - 0.02, -0.04, r.position.y), Vector3(r.end.x + skirt, top - 0.004, r.end.y), skin.timber_dark)
		# The rail: along the front and the outer sides, and along the door's path
		# except the first row (where the path steps up onto the porch).
		var rails: Array[Array] = []
		if open_front:
			rails.append([Vector2(r.position.x, r.end.y - 0.04), Vector2(r.end.x, r.end.y - 0.04)])
		for side: Array in [[open_left, on_path_left, r.position.x + 0.04], [open_right, on_path_right, r.end.x - 0.04]]:
			if not side[0]:
				continue
			if side[1] and r.position.y - first_row < size * 0.5:
				steps.append(r)
				continue
			rails.append([Vector2(side[2], r.position.y), Vector2(side[2], r.end.y)])
		for rail: Array in rails:
			var a: Vector2 = rail[0]
			var b: Vector2 = rail[1]
			for end: Vector2 in [a, b]:
				pen.box(Vector3(end.x - 0.03, top, end.y - 0.03), Vector3(end.x + 0.03, top + PATIO_RAIL, end.y + 0.03), skin.timber_dark)
			var lo: Vector2 = a.min(b) - Vector2(0.02, 0.02)
			var hi: Vector2 = a.max(b) + Vector2(0.02, 0.02)
			pen.box(Vector3(lo.x, top + PATIO_RAIL - 0.05, lo.y), Vector3(hi.x, top + PATIO_RAIL, hi.y), skin.timber)
			pen.box(Vector3(lo.x + 0.005, top + PATIO_RAIL * 0.45, lo.y + 0.005), Vector3(hi.x - 0.005, top + PATIO_RAIL * 0.45 + 0.03, hi.y - 0.005), skin.timber)
		if open_front:
			_shade_rect(shadows, Rect2(r.position.x, r.end.y - 0.04, r.size.x, 0.08), top, 0.3)
	# A wide step up from the door's path onto each wing of the porch.
	for r: Rect2 in steps:
		var into_path: float = -1.0 if r.position.x > door.get_center().x else 1.0
		var edge: float = r.position.x if into_path < 0.0 else r.end.x
		var x0: float = minf(edge, edge + into_path * 0.16)
		var x1: float = maxf(edge, edge + into_path * 0.16)
		pen.box(Vector3(x0, -0.04, r.position.y + 0.06), Vector3(x1, top * 0.5, r.end.y - 0.06), skin.timber)
	# The tall post by the door steps, its arm and the lantern.
	var post: Vector2 = Vector2(_lantern_at.x + (0.1 if _lantern_at.x < _door_u() else -0.1), _lantern_at.z)
	pen.box(Vector3(post.x - 0.04, top, post.y - 0.04), Vector3(post.x + 0.04, top + PATIO_LANTERN_POST, post.y + 0.04), skin.timber_dark)
	pen.box(Vector3(minf(post.x, _lantern_at.x) - 0.01, top + PATIO_LANTERN_POST - 0.06, post.y - 0.015),
		Vector3(maxf(post.x, _lantern_at.x) + 0.01, top + PATIO_LANTERN_POST - 0.03, post.y + 0.015), skin.timber_dark)
	pen.box(_lantern_at + Vector3(-0.04, 0.07, -0.04), _lantern_at + Vector3(0.04, 0.1, 0.04), skin.timber_dark)
	pen.box(_lantern_at + Vector3(-0.045, -0.08, -0.045), _lantern_at + Vector3(0.045, -0.06, 0.045), skin.timber_dark)
	_shade_rect(shadows, Rect2(post - Vector2(0.05, 0.05), Vector2(0.1, 0.1)), top + PATIO_LANTERN_POST, 0.3)


## Split logs stacked against a low lean-to, a chopping block with an axe in it.
func _woodpile(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var r: Rect2 = woodpile
	# Two pairs of stakes hold the stack's ends, on a low pallet of planks.
	var back: float = r.position.y
	pen.box(Vector3(r.position.x, GRASS_Y, back), Vector3(r.end.x, GRASS_Y + 0.03, r.end.y), skin.timber_dark)
	for u: float in [r.position.x + 0.02, r.end.x - 0.02]:
		for z: float in [back + 0.06, r.end.y - 0.06]:
			pen.box(Vector3(u - 0.025, GRASS_Y, z - 0.025), Vector3(u + 0.025, 0.5, z + 0.025), skin.timber_dark)
	_log_stack(pen, shadows, r.get_center(), r.size.x - 0.08, 5, false)
	_shade_rect(shadows, r.grow(0.03), 0.45, 0.3)
	# The chopping block and its axe, out in front.
	var block: Vector3 = Vector3(r.get_center().x + 0.2, GRASS_Y, r.end.y + 0.55)
	_drum(pen, block, 0.17, 0.15, 0.24, 8, skin.trunk, skin.log_end)
	_disc_top(pen, block + Vector3.UP * 0.243, 0.07, 8, skin.log_end.darkened(0.15))
	var head: Vector3 = block + Vector3(0.02, 0.29, 0.0)
	pen.box(head + Vector3(-0.015, -0.03, -0.07), head + Vector3(0.015, 0.03, 0.03), skin.stone.darkened(0.2))
	_log(pen, head + Vector3(0.0, 0.0, -0.03), head + Vector3(0.0, 0.2, 0.24), 0.014, skin.timber, skin.timber)
	_shade_disc(shadows, Vector2(block.x, block.z) + light_shift * 0.1, 0.2, 0.3)
	# A few split pieces lying beside it.
	for index: int in 3:
		var p: Vector3 = block + Vector3(-0.35 + float(index) * 0.12, 0.05, 0.25 + float(index % 2) * 0.08)
		_log(pen, p, p + Vector3(0.18, 0.0, 0.08 * float(index - 1)), 0.04, skin.trunk, skin.log_end)


## Logs stacked in rows, `rows` high, `length` along u, centred on `at`.
func _log_stack(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2, length: float, rows: int, shade: bool = true) -> void:
	var radius: float = 0.065
	var depth: float = 0.42
	for row: int in rows:
		var count: int = int(length / (radius * 2.05)) - row
		var start: float = at.x - float(count) * radius * 1.02 + radius
		for index: int in count:
			var u: float = start + float(index) * radius * 2.04
			var y: float = GRASS_Y + radius + float(row) * radius * 1.75
			var jut: float = (_r(index, row + 171) - 0.5) * 0.05
			_log(pen, Vector3(u, y, at.y - depth * 0.5 + jut), Vector3(u, y, at.y + depth * 0.5 + jut), radius, skin.trunk, skin.log_end)
	if shade:
		_shade_rect(shadows, Rect2(at.x - length * 0.5, at.y - depth * 0.5, length, depth), float(rows) * radius * 1.75, 0.3)


## The fire pit: a ring of stones round an ash bed and crossed logs, three log benches
## round it, and four poles carrying the string lights (their bulbs are built apart).
func _fire_pit(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var c: Vector3 = Vector3(fire_pit.x, GRASS_Y, fire_pit.y)
	_disc_top(pen, c + Vector3.UP * 0.006, FIRE_RING * 1.05, 10, skin.track_edge.darkened(0.15))
	_disc_top(pen, c + Vector3.UP * 0.012, FIRE_RING * 0.82, 10, skin.ash)
	for index: int in 11:
		var angle: float = TAU * float(index) / 11.0
		var p: Vector3 = c + Vector3(cos(angle), 0.0, sin(angle)) * FIRE_RING
		var size: float = 0.085 + _r(index, 181) * 0.03
		pen.lump(p + Vector3.UP * size * 0.45, size * 1.1, size * 0.8, size * 0.9, angle, skin.stone if index % 3 != 0 else skin.stone.darkened(0.1), skin.stone_dark)
	# Crossed logs, blackened at their ends.
	for index: int in 4:
		var angle: float = TAU * float(index) / 4.0 + 0.4
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		_log(pen, c + out * 0.26 + Vector3.UP * 0.04, c + out * 0.02 + Vector3.UP * 0.16, 0.04, skin.trunk.darkened(0.25), skin.ash.darkened(0.5))
	# Log benches round the fire, split side up, clear of the light poles at the corners.
	for index: int in 3:
		var angle: float = PI * 0.5 * float(index)
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var across: Vector3 = Vector3(-out.z, 0.0, out.x)
		var mid: Vector3 = c + out * 1.05
		_log(pen, mid - across * 0.45 + Vector3.UP * 0.075, mid + across * 0.45 + Vector3.UP * 0.075, 0.13, skin.trunk, skin.log_end)
		pen.quad(mid - across * 0.43 - out * 0.08 + Vector3.UP * 0.2, mid + across * 0.43 - out * 0.08 + Vector3.UP * 0.2,
			mid + across * 0.43 + out * 0.08 + Vector3.UP * 0.2, mid - across * 0.43 + out * 0.08 + Vector3.UP * 0.2, Vector3.UP, skin.log_end)
		_shade_disc(shadows, Vector2(mid.x, mid.z) + light_shift * 0.12, 0.38, 0.25)
	# The string-light poles at the corners of the light's rectangle.
	for corner: Vector2 in _light_corners():
		pen.box(Vector3(corner.x - 0.03, GRASS_Y, corner.y - 0.03), Vector3(corner.x + 0.03, 1.55, corner.y + 0.03), skin.timber_dark)
		pen.box(Vector3(corner.x - 0.05, 1.55, corner.y - 0.05), Vector3(corner.x + 0.05, 1.58, corner.y + 0.05), skin.timber_dark)
		_shade_disc(shadows, Vector2(corner.x, corner.y) + light_shift * 0.6, 0.06, 0.25)


func _light_corners() -> Array[Vector2]:
	return [fire_pit + Vector2(-1.6, -1.2), fire_pit + Vector2(1.6, -1.2), fire_pit + Vector2(1.6, 1.2), fire_pit + Vector2(-1.6, 1.2)]


## The bulbs along the four strings between the poles: little glass boxes on dark
## wire, each with a glow sprite. One extra sprite for the porch lantern.
func _light_meshes(meshes: Dictionary) -> void:
	var wire: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var glass: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var bulbs: Array[Vector3] = []
	var corners: Array[Vector2] = _light_corners()
	for index: int in 4:
		var a: Vector3 = Vector3(corners[index].x, 1.53, corners[index].y)
		var b: Vector3 = Vector3(corners[(index + 1) % 4].x, 1.53, corners[(index + 1) % 4].y)
		var segments: int = 10
		var previous: Vector3 = a
		for step: int in range(1, segments + 1):
			var t: float = float(step) / float(segments)
			var p: Vector3 = a.lerp(b, t) - Vector3.UP * 0.32 * 4.0 * t * (1.0 - t)
			var side: Vector3 = (p - previous).cross(Vector3.UP).normalized() * 0.008
			wire.quad(previous - side, p - side, p + side + Vector3.UP * 0.01, previous + side + Vector3.UP * 0.01, Vector3.UP, skin.timber_dark.darkened(0.3))
			if step < segments and step % 2 == 1:
				var bulb: Vector3 = p - Vector3.UP * 0.045
				bulbs.append(bulb)
				glass.box(bulb - Vector3(0.022, 0.03, 0.022), bulb + Vector3(0.022, 0.03, 0.022), Color.WHITE)
				wire.box(bulb + Vector3(-0.012, 0.03, -0.012), bulb + Vector3(0.012, 0.045, 0.012), skin.timber_dark.darkened(0.3))
			previous = p
	glass.box(_lantern_at - Vector3(0.035, 0.06, 0.035), _lantern_at + Vector3(0.035, 0.07, 0.035), Color.WHITE)
	meshes["wire"] = wire.soup.to_mesh()
	meshes["glass"] = glass.soup.to_mesh()
	var sizes: Array[float] = []
	for bulb: Vector3 in bulbs:
		sizes.append(0.34)
	bulbs.append(_lantern_at)
	sizes.append(0.62)
	# The fire's own bloom over the pit.
	bulbs.append(Vector3(fire_pit.x, GRASS_Y + 0.45, fire_pit.y))
	sizes.append(1.2)
	meshes["bulbs"] = _sprites(bulbs, sizes)
	# Fireflies: over the glade, along the stream, by the trees' edge and round the yard.
	var flies: Array[Vector3] = []
	var fly_sizes: Array[float] = []
	for index: int in skin.fireflies:
		var u: float = _centre_u() + (_r(index, 191) * 2.0 - 1.0) * 15.0
		var z: float
		match index % 4:
			0:
				z = stream_z(u) + (_r(index, 192) - 0.5) * 2.5
			1:
				z = lerpf(track_z(u) + 1.4, open_far(u) - 0.5, _r(index, 192))
			2:
				z = open_far(u) + (_r(index, 192) - 0.3) * 2.0
			_:
				z = shift + 0.6 + _r(index, 192) * 2.4
				u = _centre_u() + (_r(index, 193) * 2.0 - 1.0) * (_half_lot() + 4.0)
		flies.append(Vector3(u, 0.35 + _r(index, 194) * 0.9, z))
		fly_sizes.append(0.3 + _r(index, 195) * 0.14)
	meshes["flies"] = _sprites(flies, fly_sizes)


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


## A plank footbridge over the stream on the side trail: a low arch, posts and rails.
func _footbridge(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var c: Vector2 = bridge
	var half_length: float = STREAM_HALF + 0.75
	var width: float = 0.42
	var segments: int = 8
	var rise: float = 0.2
	for index: int in segments:
		var t0: float = float(index) / float(segments)
		var t1: float = float(index + 1) / float(segments)
		var z0: float = c.y - half_length + t0 * half_length * 2.0
		var z1: float = c.y - half_length + t1 * half_length * 2.0
		var y0: float = TRACK_Y + 0.05 + rise * sin(t0 * PI)
		var y1: float = TRACK_Y + 0.05 + rise * sin(t1 * PI)
		var tone: Color = skin.timber if index % 2 == 0 else skin.timber.darkened(0.07)
		pen.slab([Vector3(c.x - width, y0, z0 + 0.01), Vector3(c.x + width, y0, z0 + 0.01), Vector3(c.x + width, y1, z1 - 0.01),
			Vector3(c.x - width, y1, z1 - 0.01)], Vector3(0.0, 0.04, 0.0), tone)
		# Stringers under the planks.
		for side: float in [-1.0, 1.0]:
			pen.quad(Vector3(c.x + side * (width - 0.02), y0 - 0.06, z0), Vector3(c.x + side * (width - 0.02), y1 - 0.06, z1),
				Vector3(c.x + side * (width - 0.02), y1 + 0.01, z1), Vector3(c.x + side * (width - 0.02), y0 + 0.01, z0), Vector3(side, 0.0, 0.0), skin.timber_dark)
	for side: float in [-1.0, 1.0]:
		var rail: Array[Vector3] = []
		for t: float in [0.06, 0.5, 0.94]:
			var z: float = c.y - half_length + t * half_length * 2.0
			var y: float = TRACK_Y + 0.05 + rise * sin(t * PI)
			var x: float = c.x + side * (width - 0.03)
			pen.box(Vector3(x - 0.03, y, z - 0.03), Vector3(x + 0.03, y + 0.46, z + 0.03), skin.timber_dark)
			rail.append(Vector3(x, y + 0.44, z))
		for index: int in 2:
			var a: Vector3 = rail[index]
			var b: Vector3 = rail[index + 1]
			pen.quad(a + Vector3(-0.025, 0.0, 0.0), b + Vector3(-0.025, 0.0, 0.0), b + Vector3(0.025, 0.0, 0.0), a + Vector3(0.025, 0.0, 0.0), Vector3.UP, skin.timber)
			pen.quad(a + Vector3(side * 0.025, -0.04, 0.0), b + Vector3(side * 0.025, -0.04, 0.0), b + Vector3(side * 0.025, 0.0, 0.0),
				a + Vector3(side * 0.025, 0.0, 0.0), Vector3(side, 0.0, 0.0), skin.timber)
	_shade_rect(shadows, Rect2(c.x - width, c.y - half_length, width * 2.0, half_length * 2.0), 0.25, 0.25)


## A finger post where the side trail leaves the track.
func _trail_sign(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var foot: Vector3 = Vector3(trail_u - 0.75, GRASS_Y, track_z(trail_u) + TRACK_HALF + 0.35)
	pen.box(foot + Vector3(-0.04, 0.0, -0.04), foot + Vector3(0.04, 0.95, 0.04), skin.timber_dark)
	pen.box(foot + Vector3(-0.05, 0.94, -0.05), foot + Vector3(0.05, 0.98, 0.05), skin.timber_dark)
	# Two arrow boards: one along the track, one up the trail.
	pen.box(foot + Vector3(-0.32, 0.76, -0.045), foot + Vector3(0.24, 0.88, -0.02), skin.sign_paint)
	pen.tri(foot + Vector3(0.24, 0.73, -0.035), foot + Vector3(0.34, 0.82, -0.035), foot + Vector3(0.24, 0.91, -0.035), Vector3.FORWARD, skin.sign_paint)
	pen.box(foot + Vector3(0.02, 0.58, -0.02), foot + Vector3(0.045, 0.7, 0.42), skin.sign_paint.darkened(0.08))
	_shade_disc(shadows, Vector2(foot.x, foot.z) + light_shift * 0.45, 0.07, 0.25)


# --- lights, fire, chairs and animals -----------------------------------------

func _build_lights(meshes: Dictionary) -> void:
	_add(_instance("Wire", meshes["wire"], _material))
	_add(_instance("Bulbs", meshes["glass"], _glass_material))
	_bulb_glow = _instance("BulbGlow", meshes["bulbs"], _bulb_material)
	_bulb_glow.extra_cull_margin = 1.0
	_add(_bulb_glow)
	_fireflies = _instance("Fireflies", meshes["flies"], _fly_material)
	_fireflies.extra_cull_margin = 2.0
	_add(_fireflies)


## The fire's flames (unlit by day) and the warm pool of light round the pit.
func _build_fire() -> void:
	flames.clear()
	var holder: Node3D = Node3D.new()
	holder.name = "Fire"
	root.add_child(holder)
	var centre: Vector3 = Vector3(fire_pit.x, GRASS_Y + 0.05, fire_pit.y)
	for index: int in 4:
		var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		var radius: float = 0.16 if index == 0 else 0.1
		var height: float = 0.7 if index == 0 else 0.42
		_flame(pen, radius, height, skin.flame)
		_flame(pen, radius * 0.55, height * 0.6, skin.flame_tip)
		var flame: MeshInstance3D = _instance("Flame%d" % index, pen.soup.to_mesh(), _flame_material)
		var angle: float = TAU * float(index) / 3.0 + 0.3
		flame.position = centre + (Vector3.ZERO if index == 0 else Vector3(cos(angle), 0.0, sin(angle)) * 0.09)
		holder.add_child(flame)
		flames.append(flame)
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var rings: int = 6
	var radius: float = 2.6
	for index: int in 14:
		var a0: float = TAU * float(index) / 14.0
		var a1: float = TAU * float(index + 1) / 14.0
		for ring: int in rings:
			var r0: float = radius * float(ring) / float(rings)
			var r1: float = radius * float(ring + 1) / float(rings)
			var k0: float = pow(1.0 - float(ring) / float(rings), 1.6) * 0.8
			var k1: float = pow(1.0 - float(ring + 1) / float(rings), 1.6) * 0.8
			var c0: Color = Color(skin.lamp_glow, k0)
			var c1: Color = Color(skin.lamp_glow, k1)
			var p: Array[Vector3] = [Vector3(cos(a0) * r0, 0.0, sin(a0) * r0), Vector3(cos(a1) * r0, 0.0, sin(a1) * r0),
				Vector3(cos(a1) * r1, 0.0, sin(a1) * r1), Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)]
			var colours: Array[Color] = [c0, c0, c1, c1]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				soup.positions.append(p[corner])
				soup.normals.append(Vector3.UP)
				soup.colors.append(colours[corner])
	_fire_glow = _instance("FireGlow", soup.to_mesh(), _fire_glow_material)
	_fire_glow.position = Vector3(fire_pit.x, SHADOW_Y + 0.004, fire_pit.y)
	root.add_child(_fire_glow)


func _flame(pen: NeighbourhoodBuildings.Pen, radius: float, height: float, colour: Color) -> void:
	for index: int in 5:
		var a0: float = TAU * float(index) / 5.0
		var a1: float = TAU * float(index + 1) / 5.0
		var p0: Vector3 = Vector3(cos(a0), 0.0, sin(a0)) * radius
		var p1: Vector3 = Vector3(cos(a1), 0.0, sin(a1)) * radius
		pen.tri(p0, p1, Vector3.UP * height, (p0 + p1) * 0.5, colour)


func _build_chairs() -> void:
	chairs.clear()
	for index: int in _chair_spots.size():
		var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		_rocking_chair(pen, index == 0)
		var chair: MeshInstance3D = _instance("RockingChair%d" % index, pen.soup.to_mesh(), _material)
		chair.transform = _chair_spots[index]
		root.add_child(chair)
		chairs.append(chair)


## A rocking chair facing +z (out from the porch): curved rockers, slatted back, arms.
## Its seat is at person height (0.27); the one on the left wears a folded blanket.
func _rocking_chair(pen: NeighbourhoodBuildings.Pen, blanket: bool) -> void:
	var wood: Color = skin.timber.darkened(0.05)
	var dark: Color = skin.timber_dark
	for side: float in [-0.13, 0.13]:
		# The rocker: three short pieces along a curve.
		var points: Array[Vector3] = []
		for index: int in 5:
			var t: float = float(index) / 4.0
			var z: float = lerpf(-0.24, 0.22, t)
			points.append(Vector3(side, 0.035 * pow((t - 0.5) * 2.0, 2.0) * 1.6, z))
		for index: int in 4:
			pen.quad(points[index] + Vector3(-0.018, 0.0, 0.0), points[index + 1] + Vector3(-0.018, 0.0, 0.0),
				points[index + 1] + Vector3(-0.018, 0.035, 0.0), points[index] + Vector3(-0.018, 0.035, 0.0), Vector3.LEFT, dark)
			pen.quad(points[index] + Vector3(0.018, 0.0, 0.0), points[index + 1] + Vector3(0.018, 0.0, 0.0),
				points[index + 1] + Vector3(0.018, 0.035, 0.0), points[index] + Vector3(0.018, 0.035, 0.0), Vector3.RIGHT, dark)
			pen.quad(points[index] + Vector3(-0.018, 0.035, 0.0), points[index + 1] + Vector3(-0.018, 0.035, 0.0),
				points[index + 1] + Vector3(0.018, 0.035, 0.0), points[index] + Vector3(0.018, 0.035, 0.0), Vector3.UP, dark)
		# Legs, the arm and its front post.
		pen.box(Vector3(side - 0.018, 0.03, 0.1), Vector3(side + 0.018, 0.27, 0.13), wood)
		pen.box(Vector3(side - 0.018, 0.03, -0.12), Vector3(side + 0.018, 0.27, -0.09), wood)
		pen.box(Vector3(side - 0.025, 0.38, -0.14), Vector3(side + 0.025, 0.405, 0.15), wood)
		pen.box(Vector3(side - 0.015, 0.27, 0.11), Vector3(side + 0.015, 0.38, 0.135), wood)
		# The back's uprights lean back a little.
		pen.quad(Vector3(side - 0.02, 0.27, -0.13), Vector3(side + 0.02, 0.27, -0.13), Vector3(side + 0.02, 0.66, -0.21),
			Vector3(side - 0.02, 0.66, -0.21), Vector3.FORWARD, dark)
		pen.quad(Vector3(side - 0.02, 0.27, -0.1), Vector3(side + 0.02, 0.27, -0.1), Vector3(side + 0.02, 0.66, -0.18),
			Vector3(side - 0.02, 0.66, -0.18), Vector3.BACK, dark)
	pen.box(Vector3(-0.15, 0.25, -0.13), Vector3(0.15, 0.28, 0.14), wood)
	for index: int in 4:
		var x: float = -0.09 + float(index) * 0.06
		pen.quad(Vector3(x - 0.018, 0.29, -0.115), Vector3(x + 0.018, 0.29, -0.115), Vector3(x + 0.018, 0.62, -0.185),
			Vector3(x - 0.018, 0.62, -0.185), Vector3.BACK, wood)
	pen.box(Vector3(-0.15, 0.6, -0.21), Vector3(0.15, 0.65, -0.17), dark)
	if blanket:
		pen.slab([Vector3(-0.14, 0.42, -0.17), Vector3(0.14, 0.42, -0.17), Vector3(0.14, 0.282, -0.06), Vector3(-0.14, 0.282, -0.06)],
			Vector3(0.0, 0.02, 0.02), skin.blanket)
		pen.box(Vector3(-0.12, 0.28, -0.05), Vector3(0.12, 0.3, 0.12), skin.blanket.darkened(0.08))


func _build_animals() -> void:
	deer.clear()
	rabbits.clear()
	_deer_spots.clear()
	_rabbit_spots.clear()
	var holder: Node3D = Node3D.new()
	holder.name = "Wildlife"
	root.add_child(holder)
	# Deer graze where the glade meets the trees, beyond the stream.
	for index: int in skin.deer:
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var u: float = _centre_u() + side * (2.5 + float(index) * 2.2 + _r(index, 201) * 1.5)
		if absf(u - trail_u) < 1.6:
			u += 3.2 * side
		var at: Vector2 = Vector2(u, lerpf(stream_z(u) + _stream_half(u) + 0.9, open_far(u) - 0.9, 0.35 + _r(index, 202) * 0.4))
		var yaw: float = (0.5 + _r(index, 203)) * (PI if side > 0.0 else -PI) * 0.5
		_deer_spots.append(Vector3(at.x, at.y, yaw))
		holder.add_child(_deer_node(index, index == 0))
		deer.append(holder.get_child(holder.get_child_count() - 1) as Node3D)
	# Rabbits at the clearing's near edges and on the glade.
	for index: int in skin.rabbits:
		var u: float = _centre_u() + (_r(index, 211) * 2.0 - 1.0) * (_half_lot() + 6.0)
		var z: float
		if index % 2 == 0:
			z = lerpf(track_z(u) + TRACK_HALF + 0.9, stream_z(u) - _stream_half(u) - 0.6, _r(index, 212))
		else:
			z = lerpf(stream_z(u) + _stream_half(u) + 0.8, open_far(u) - 0.6, _r(index, 212))
		var at: Vector2 = Vector2(u, z)
		if _is_blocked(at, 0.4) or _on_trail(at, 0.5):
			at.x += 2.0
		_rabbit_spots.append(Vector4(at.x, at.y, _r(index, 213) * TAU, _r(index, 214) * 9.0))
		var rabbit: Node3D = _rabbit_node(index)
		holder.add_child(rabbit)
		rabbits.append(rabbit)


## A deer facing +z: body, legs, white tail and rump; its neck and head are a child
## (`Neck`) that lowers to graze. The first is a stag with antlers.
func _deer_node(index: int, stag: bool) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Deer%d" % index
	var model: Node3D = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * DEER_SCALE
	node.add_child(model)
	var body: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var coat: Color = skin.deer_coat.darkened(0.06 * float(index % 2))
	body.lump(Vector3(0.0, 0.38, 0.0), 0.11, 0.1, 0.24, 0.0, coat, skin.deer_pale)
	for x: float in [-0.055, 0.055]:
		for z: float in [-0.15, 0.15]:
			body.box(Vector3(x - 0.016, 0.0, z - 0.016), Vector3(x + 0.016, 0.34, z + 0.016), coat.darkened(0.15))
			body.box(Vector3(x - 0.018, 0.0, z - 0.018), Vector3(x + 0.018, 0.03, z + 0.018), skin.trunk.darkened(0.3))
	body.lump(Vector3(0.0, 0.42, -0.22), 0.05, 0.05, 0.04, 0.0, skin.deer_pale, skin.deer_pale)
	body.box(Vector3(-0.022, 0.42, -0.26), Vector3(0.022, 0.48, -0.22), skin.deer_pale.lightened(0.2))
	var mesh: MeshInstance3D = _instance("Body", body.soup.to_mesh(), _material)
	model.add_child(mesh)
	var neck: Node3D = Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, 0.43, 0.17)
	var head: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	head.quad(Vector3(-0.04, -0.04, -0.03), Vector3(0.04, -0.04, -0.03), Vector3(0.035, 0.2, 0.07), Vector3(-0.035, 0.2, 0.07), Vector3.BACK, coat)
	head.quad(Vector3(-0.04, -0.04, 0.05), Vector3(0.04, -0.04, 0.05), Vector3(0.035, 0.2, 0.13), Vector3(-0.035, 0.2, 0.13), Vector3.BACK, skin.deer_pale)
	head.quad(Vector3(-0.04, -0.04, -0.03), Vector3(-0.04, -0.04, 0.05), Vector3(-0.035, 0.2, 0.13), Vector3(-0.035, 0.2, 0.07), Vector3.LEFT, coat)
	head.quad(Vector3(0.04, -0.04, -0.03), Vector3(0.04, -0.04, 0.05), Vector3(0.035, 0.2, 0.13), Vector3(0.035, 0.2, 0.07), Vector3.RIGHT, coat)
	head.lump(Vector3(0.0, 0.22, 0.13), 0.045, 0.045, 0.08, 0.0, coat, coat.darkened(0.1))
	head.box(Vector3(-0.018, 0.2, 0.2), Vector3(0.018, 0.23, 0.22), skin.trunk.darkened(0.4))
	for side: float in [-1.0, 1.0]:
		head.tri(Vector3(side * 0.03, 0.25, 0.08), Vector3(side * 0.1, 0.31, 0.06), Vector3(side * 0.04, 0.27, 0.12), Vector3(side, 0.4, 0.0), coat.darkened(0.08))
		if stag:
			var base: Vector3 = Vector3(side * 0.025, 0.26, 0.1)
			_log(head, base, base + Vector3(side * 0.05, 0.14, -0.02), 0.008, skin.log_end.darkened(0.2), skin.log_end)
			_log(head, base + Vector3(side * 0.03, 0.08, -0.01), base + Vector3(side * 0.09, 0.12, 0.04), 0.007, skin.log_end.darkened(0.2), skin.log_end)
	neck.add_child(_instance("Head", head.soup.to_mesh(), _material))
	model.add_child(neck)
	var shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	_shade_disc(shade, light_shift * 0.2, 0.22 * DEER_SCALE, 0.28)
	var shadow: MeshInstance3D = _instance("Shadow", shade.to_mesh(), _shadow_material)
	shadow.position = Vector3(0.0, SHADOW_Y - GRASS_Y, 0.0)
	node.add_child(shadow)
	return node


## A rabbit facing +z: round body, head, long ears and a white scut.
func _rabbit_node(index: int) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Rabbit%d" % index
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var coat: Color = skin.rabbit_coat.lightened(0.05 * float(index % 3))
	pen.lump(Vector3(0.0, 0.06, 0.0), 0.06, 0.06, 0.08, 0.0, coat, coat.darkened(0.15))
	pen.lump(Vector3(0.0, 0.11, 0.07), 0.04, 0.04, 0.045, 0.0, coat, coat.darkened(0.1))
	for side: float in [-0.015, 0.015]:
		pen.box(Vector3(side - 0.01, 0.13, 0.06), Vector3(side + 0.01, 0.22, 0.075), coat.darkened(0.08))
	pen.lump(Vector3(0.0, 0.08, -0.08), 0.022, 0.022, 0.02, 0.0, skin.deer_pale.lightened(0.3), skin.deer_pale)
	var mesh: MeshInstance3D = _instance("Body", pen.soup.to_mesh(), _material)
	# Rabbits are drawn a little large, like the street's birds, so they read at play zoom.
	mesh.scale = Vector3.ONE * RABBIT_SCALE
	node.add_child(mesh)
	var shade: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	_shade_disc(shade, Vector2(0.0, 0.0), 0.08 * RABBIT_SCALE, 0.25)
	var shadow: MeshInstance3D = _instance("Shadow", shade.to_mesh(), _shadow_material)
	shadow.position = Vector3(0.0, SHADOW_Y - GRASS_Y, 0.0)
	node.add_child(shadow)
	return node


# --- walkers' kit -------------------------------------------------------------

## A hiker's backpack with a rolled mat on top, for a walker facing +z (its prop
## follows the walker's position and heading).
func backpack(colour: Color) -> ArrayMesh:
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	pen.box(Vector3(-0.1, 0.2, -0.2), Vector3(0.1, 0.44, -0.08), colour)
	pen.box(Vector3(-0.085, 0.22, -0.225), Vector3(0.085, 0.34, -0.2), colour.darkened(0.12))
	pen.box(Vector3(-0.1, 0.42, -0.19), Vector3(0.1, 0.45, -0.09), colour.darkened(0.2))
	_log(pen, Vector3(-0.12, 0.49, -0.14), Vector3(0.12, 0.49, -0.14), 0.04, skin.blanket, skin.blanket.lightened(0.15))
	return pen.soup.to_mesh()


# --- motion and time of day -------------------------------------------------

## 0 by day, 1 from dusk; `late` rises after the shop closes. The fire burns and the
## bulbs glow from dusk, fireflies come out, the rabbits go home and the deer by late night.
## The day's weather (WeatherState.Kind): wind in the rain sways the crops and trees more.
func set_weather(kind: int) -> void:
	if kind == _weather:
		return
	_weather = kind
	_apply_night()


## A gloomy afternoon's early lamplight (WeatherLook.gloom): the lamps, windows and the
## campfire come on dimly, everything else keeps the clock's time of day.
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
	_glass_material.emission_energy_multiplier = lamps * 2.6
	_glass_material.albedo_color = skin.lamp_glow.lerp(skin.ripple, 1.0 - lamps)
	_bulb_material.set_shader_parameter(&"level", lamps)
	_fly_material.set_shader_parameter(&"level", smoothstep(0.35, 0.9, _night))
	_stream_material.set_shader_parameter(&"moon", _night * _late)
	var lit: bool = is_fire_lit()
	# Unlit glows still cost a blended pass: hide them by day.
	_bulb_glow.visible = lamps > 0.05
	_fireflies.visible = _night > 0.35
	for flame: Node3D in flames:
		flame.visible = lit
	_fire_glow.visible = lit
	for rabbit: Node3D in rabbits:
		rabbit.visible = _night < NIGHT_HIDE
	for animal: Node3D in deer:
		animal.visible = _late < NIGHT_HIDE
	_applied_at = -1.0
	apply(_seconds)


func is_fire_lit() -> bool:
	return _fire() > 0.05


## How brightly the fire burns: by night, or on a gloomy afternoon (lit with the lanterns).
func _fire() -> float:
	return maxf(_night, _gloom)


## Moves everything to the street clock's `seconds`; skipped when nothing changed.
func apply(seconds: float) -> void:
	_seconds = seconds
	if root == null or is_equal_approx(seconds, _applied_at):
		return
	_applied_at = seconds
	_stream_material.set_shader_parameter(&"stream_time", seconds)
	_fly_material.set_shader_parameter(&"glow_time", seconds)
	for index: int in flames.size():
		var t: float = seconds * (7.0 + float(index)) + float(index) * 1.7
		var flicker: float = 0.85 + 0.12 * sin(t) + 0.08 * sin(t * 2.3 + 0.5)
		var sway: float = 0.12 * sin(seconds * 3.1 + float(index))
		var scale: float = _fire() * flicker
		flames[index].basis = Basis(Vector3.UP, seconds * 0.7 + float(index)) * Basis(Vector3.BACK, sway) \
			* Basis.from_scale(Vector3(maxf(_fire(), 0.05), maxf(scale, 0.05), maxf(_fire(), 0.05)))
	_fire_glow_material.albedo_color = Color(1.0, 1.0, 1.0, _fire() * (0.9 + 0.1 * sin(seconds * 6.3) * sin(seconds * 2.9)))
	for index: int in chairs.size():
		var rock: float = 0.035 * sin(seconds * 0.9 + float(index) * 2.1) * (0.6 + 0.4 * sin(seconds * 0.13 + float(index)))
		chairs[index].transform = _chair_spots[index] * Transform3D(Basis(Vector3.RIGHT, rock), Vector3.ZERO)
	for index: int in deer.size():
		deer[index].transform = deer_transform(index)
		var neck: Node3D = deer[index].get_node(^"Model/Neck") as Node3D
		neck.rotation = Vector3(deer_graze(index, seconds), 0.0, 0.0)
	for index: int in rabbits.size():
		rabbits[index].transform = rabbit_transform(index, seconds)


func deer_transform(index: int) -> Transform3D:
	var spot: Vector3 = _deer_spots[index]
	return Transform3D(Basis(Vector3.UP, spot.z), Vector3(spot.x, GRASS_Y, spot.y))


## The deer's neck angle: down grazing most of the time, up to look round now and then.
func deer_graze(index: int, seconds: float) -> float:
	var period: float = 11.0 + float(index) * 2.3
	var phase: float = fposmod(seconds + float(index) * 4.1, period) / period
	var up: float = smoothstep(0.55, 0.62, phase) * (1.0 - smoothstep(0.85, 0.92, phase))
	return lerpf(1.25, -0.05, up)


## A rabbit sits, then hops a few times along a short line and back again.
func rabbit_transform(index: int, seconds: float) -> Transform3D:
	var spot: Vector4 = _rabbit_spots[index]
	var period: float = 7.0
	var cycle: float = fposmod(seconds + spot.w, period * 2.0)
	var outward: bool = cycle < period
	var local: float = fposmod(cycle, period)
	var hops: float = clampf(local / 1.2, 0.0, 1.0) * 3.0
	var travelled: float = (hops if outward else 3.0 - hops) * 0.22
	var hop_phase: float = fposmod(hops, 1.0)
	var lift: float = sin(hop_phase * PI) * 0.08 if local < 1.2 else 0.0
	var heading: Vector3 = Vector3(sin(spot.z), 0.0, cos(spot.z))
	var facing: float = spot.z if outward else spot.z + PI
	return Transform3D(Basis(Vector3.UP, facing), Vector3(spot.x, GRASS_Y + lift, spot.y) + heading * travelled)


## What the forest shows now, for tests and captures.
func capture_state() -> Dictionary:
	return {"stands": stand_ids(), "fire_lit": is_fire_lit(), "night": _night, "late": _late,
		"deer": deer.size(), "rabbits": rabbits.size(), "fireflies": skin.fireflies,
		"porch": porch, "woodpile": woodpile, "fire_pit": fire_pit, "bridge": bridge}
