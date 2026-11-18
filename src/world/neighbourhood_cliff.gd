class_name NeighbourhoodCliff
extends RefCounted
## A cliff-top café instead of a street (#380). The shop is a white cottage on a grassy
## cliff top, high above the sea. Behind the lot and along one side (local +u) the land
## ends at a sheer cliff of layered rock: turf and soil at the lip, then strata of rock
## stepping in and out in ledges (sea pinks grow on some), boulders at the foot where
## the surf breaks, and a little cove with a sandy beach and sea stacks off its mouth.
## The open sea runs out to the horizon far below (sea.gdshader, the beach's water seen
## from high up); the cliff casts its shadow on it, and the lower rock and the far water
## fade into the air between, so the drop reads as high from every quarter.
##
## A timber rail on white posts runs along the edge round the lot, outside its maximum
## footprint, with a lifebuoy and a bench at the cove. Guests come up the cliff path: a
## winding gravel footpath from a small car park and bus stop far off, over a stile in a
## dry-stone wall and past a finger post where the coast path turns off along the top.
## Wind-bent grass, sea pinks (thrift) and gorse grow on the top, a windswept thorn leans
## by the stile and sheep graze the fields inland. A lighthouse with its keeper's cottage
## stands on a headland across the bay, a fishing boat works the water below and gulls
## glide on the updraft level with the cliff top. At night the lighthouse beam sweeps
## round, the boat's lamp and the windows glow and the sea takes the moonlight.
##
## Like the rest of the neighbourhood it is view-only: no colliders, sim agents, saves,
## lights or random draws. Everything placed comes from an integer hash, and every motion
## is a closed-form function of the street's display clock, so a paused capture always
## shows the same frame. Authored in the street's local frame (u along the front, z
## outward past the door), under one root the dressing places on that frame. Draw cost:
## a handful of batched vertex-coloured meshes, one sea mesh under the sea shader, one
## glow-sprite mesh, the beam, and a few small nodes for the gulls and the boat.

const SEA_SHADER: Shader = preload("res://src/world/sea.gdshader")
const GLOW_SHADER: Shader = preload("res://src/world/city_glow.gdshader")

## Ground layers on the cliff top, 4 mm or more apart, all under the shop floor (y 0).
const FLOOR_Y: float = -0.062
const PATCH_Y: float = -0.056
const PATH_EDGE_Y: float = -0.050
const PATH_Y: float = -0.046
const PEBBLE_Y: float = -0.041
const SHADOW_Y: float = -0.030
## The cliff edge stands this far from the lot's maximum footprint behind it and beside
## it, and never nearer than EDGE_MIN anywhere.
const EDGE_GAP: float = 2.35
const EDGE_MIN: float = 2.0
## The coast is sampled about this often (metres along the edge).
const COAST_STEP: float = 0.9
## The rail stands this far in from the edge; its posts' spacing and its height.
const RAIL_IN: float = 0.7
const POST_STEP: float = 1.1
const RAIL_H: float = 0.56
## Keep everything that stands up at least this far off the lot.
const LOT_GAP: float = 0.35
## The cliff path's half width.
const PATH_HALF: float = 0.42
const COAST_PATH_HALF: float = 0.27
## Distance queries bucket the coast in cells this wide.
const BUCKET: float = 6.0
## The sea: a fine grid this far each way round the world's middle, then a ring out to
## SEA_OUTER; the swash's wet band.
const SEA_CELL: float = 1.6
const SEA_INNER: float = 64.0
const SEA_OUTER: float = 230.0
const WET_WIDTH: float = 0.9
## The sea's pattern (surf, bands, glints) is drawn this much smaller than at the beach,
## so from up here the water reads as far below.
const SEA_SCALE: float = 1.7
## How much of the air's colour lies over the rock at the foot of the cliff.
const HAZE: float = 0.55
## The cove's beach: its widest (metres from the cliff foot to the waterline).
const BEACH: float = 2.6
## Gulls are drawn this much larger than life, so they read from the camera.
const GULL_SCALE: float = 1.35
## The lighthouse: its tower's height above the top and the beam's reach and turn rate.
const TOWER_H: float = 3.6
const BEAM_LENGTH: float = 18.0
const BEAM_TURN: float = 0.45
## Gulls roost after dark.
const NIGHT_HIDE: float = 0.5
## The prevailing wind blows in off the sea; grass and gorse lean away from it (local u, z).
const WIND: Vector2 = Vector2(-0.72, 0.69)

## A polyline with a bucketed signed distance (positive on the side its normals face).
class Line extends RefCounted:
	var points: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector2Array = PackedVector2Array()
	var vertex_normals: PackedVector2Array = PackedVector2Array()
	var cell: float = 6.0
	var buckets: Dictionary[Vector2i, PackedInt32Array] = {}
	var coarse: Line

	func _init(line: PackedVector2Array, bucket: float, decimate: int = 0) -> void:
		points = line
		cell = bucket
		for index: int in points.size() - 1:
			var along: Vector2 = (points[index + 1] - points[index]).normalized()
			normals.append(Vector2(along.y, -along.x))
		for index: int in points.size():
			var a: Vector2 = normals[maxi(index - 1, 0)]
			var b: Vector2 = normals[mini(index, normals.size() - 1)]
			vertex_normals.append((a + b).normalized())
		for index: int in points.size() - 1:
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			var lo: Vector2i = Vector2i(floori(minf(a.x, b.x) / cell), floori(minf(a.y, b.y) / cell))
			var hi: Vector2i = Vector2i(floori(maxf(a.x, b.x) / cell), floori(maxf(a.y, b.y) / cell))
			for x: int in range(lo.x, hi.x + 1):
				for y: int in range(lo.y, hi.y + 1):
					var key: Vector2i = Vector2i(x, y)
					var list: PackedInt32Array = buckets.get(key, PackedInt32Array())
					list.append(index)
					buckets[key] = list
		if decimate > 1:
			var sparse: PackedVector2Array = PackedVector2Array()
			for index: int in range(0, points.size(), decimate):
				sparse.append(points[index])
			if sparse[sparse.size() - 1] != points[points.size() - 1]:
				sparse.append(points[points.size() - 1])
			coarse = Line.new(sparse, cell * 4.0)

	## Signed distance to the line: positive on its normals' side.
	func signed(point: Vector2) -> float:
		var best: float = INF
		var sign: float = 1.0
		var centre: Vector2i = Vector2i(floori(point.x / cell), floori(point.y / cell))
		for x: int in range(centre.x - 2, centre.x + 3):
			for y: int in range(centre.y - 2, centre.y + 3):
				var list: PackedInt32Array = buckets.get(Vector2i(x, y), PackedInt32Array())
				for index: int in list:
					var hit: Vector2 = _segment(point, index)
					if hit.x < best:
						best = hit.x
						sign = hit.y
		if best > cell * 2.0:
			if coarse != null:
				return coarse.signed(point)
			for index: int in points.size() - 1:
				var hit: Vector2 = _segment(point, index)
				if hit.x < best:
					best = hit.x
					sign = hit.y
		return best * sign

	## (distance, side) from `point` to segment `index`.
	func _segment(point: Vector2, index: int) -> Vector2:
		var a: Vector2 = points[index]
		var ab: Vector2 = points[index + 1] - a
		var length: float = ab.length_squared()
		var t: float = clampf((point - a).dot(ab) / length, 0.0, 1.0) if length > 0.0 else 0.0
		var closest: Vector2 = a + ab * t
		var normal: Vector2 = normals[index]
		if t <= 0.0:
			normal = vertex_normals[index]
		elif t >= 1.0:
			normal = vertex_normals[index + 1]
		return Vector2(point.distance_to(closest), 1.0 if (point - closest).dot(normal) >= 0.0 else -1.0)

## Inputs, set by the owner before build().
var skin: CliffSkin
var local_reserve: AABB = AABB()
var shift: float = 0.0
var light_shift: Vector2 = Vector2.ZERO
var salt: int = 0
var world_centre: Vector2 = Vector2.ZERO
## Local (u, z) rects nothing may stand on: the door approaches and entrance pads.
var keep_clear: Array[Rect2] = []
## The shop building's local (u, z) extent, walls included.
var building: Rect2 = Rect2()

var root: Node3D
## Where things went (local u, z), for tools and tests.
var lot: Rect2 = Rect2()
var door: Rect2 = Rect2()
var coast: Line
var waterline: Line
var rail_points: PackedVector2Array = PackedVector2Array()
var path_points: PackedVector2Array = PackedVector2Array()
var coast_path_points: PackedVector2Array = PackedVector2Array()
var stile: Vector2 = Vector2.ZERO
var finger_post: Vector2 = Vector2.ZERO
var car_park: Rect2 = Rect2()
var lane_points: PackedVector2Array = PackedVector2Array()
## Each path's bounds, so most planting checks skip it at once.
var _path_boxes: Array[Rect2] = []
var lighthouse: Vector2 = Vector2.ZERO
var cove: Vector2 = Vector2.ZERO
var stacks: Array[Vector4] = []
var gulls: Array[Node3D] = []
var boat: Node3D
var beam: MeshInstance3D
var sea: MeshInstance3D
var sea_material: ShaderMaterial
var _feet: PackedVector2Array = PackedVector2Array()
var _coast_normals: PackedVector2Array = PackedVector2Array()
var _bands: Array[float] = []
var _ledges: Array[Vector3] = []
var _gull_wings: Array[Array] = []
var _gull_paths: Array[Dictionary] = []
var _boat_path: Dictionary = {}
var _boat_lamp: MeshInstance3D
var _lamp: Vector3 = Vector3.ZERO
var _lamp_on_sea: Vector2 = Vector2.ZERO
var _lights: Array[Vector3] = []
var _light_sizes: Array[float] = []
var _blocked: Array[Rect2] = []
var _material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _glass_material: StandardMaterial3D
var _beam_material: StandardMaterial3D
var _glow_material: ShaderMaterial
var _boat_glow: ShaderMaterial
var _glow: MeshInstance3D
var _pools: MeshInstance3D
var _pool_material: StandardMaterial3D
var _pool_soup: NeighbourhoodGround.Soup
var _night: float = 0.0
var _late: float = 0.0
var _seconds: float = 0.0
var _applied_at: float = -1.0

## Built static meshes by street key, shared by every cliff (a rebuild after a purchase
## or a reload reuses them instead of planning the coast and sea again).
static var _cache: Dictionary[String, Dictionary] = {}


static func clear_cache() -> void:
	_cache.clear()


func _r(a: int, b: int) -> float:
	return NeighbourhoodGround.hash01(a, b, salt + 380)


func drop() -> float:
	return skin.drop


func sea_y() -> float:
	return -skin.drop


# --- the plan ---------------------------------------------------------------

## Where the coast, the cove, the rail, the paths and the far things go.
func _plan() -> void:
	lot = Rect2(local_reserve.position.x, local_reserve.position.z, local_reserve.size.x, shift - local_reserve.position.z)
	door = Rect2(lot.get_center().x - 0.6, shift, 1.2, 1.6)
	var doors: Array[Rect2] = []
	for rect: Rect2 in keep_clear:
		if rect.end.y > shift - 0.05:
			doors.append(rect)
	if not doors.is_empty():
		door = doors[0]
		for rect: Rect2 in doors:
			door = door.merge(rect)
	_blocked.clear()
	_blocked.append(lot.grow(LOT_GAP))
	for rect: Rect2 in keep_clear:
		_blocked.append(rect.grow(0.2))
	_plan_coast()
	_plan_rail()
	_plan_paths()


func _plan_coast() -> void:
	var l: float = lot.position.x
	var r: float = lot.end.x
	var b: float = lot.position.y
	var f: float = lot.end.y
	var cu: float = lot.get_center().x
	var zb: float = b - EDGE_GAP
	var ue: float = r + EDGE_GAP
	cove = Vector2(ue - 4.0, f + 9.0)
	var zawn: float = minf(l - 6.8, cu - 12.0)
	# The sea lies on each point's normal side: north (-z) behind the lot, east (+u) beside it.
	var controls: Array[Vector2] = [
		Vector2(cu - 110.0, zb - 5.0), Vector2(cu - 74.0, zb - 2.6), Vector2(cu - 50.0, zb - 1.0),
		# The headland across the bay, with the lighthouse at its tip.
		Vector2(cu - 41.0, zb - 2.6), Vector2(cu - 37.5, zb - 9.0), Vector2(cu - 35.5, zb - 17.5),
		Vector2(cu - 32.0, zb - 24.5), Vector2(cu - 27.0, zb - 27.5), Vector2(cu - 22.0, zb - 25.0),
		Vector2(cu - 20.0, zb - 17.0), Vector2(cu - 18.6, zb - 8.5), Vector2(cu - 17.6, zb - 3.4),
		# A zawn: a narrow cleft the sea has cut into the top west of the café.
		Vector2(zawn - 3.4, zb - 0.6), Vector2(zawn - 1.5, zb + 0.4), Vector2(zawn - 1.0, zb + 2.9),
		Vector2(zawn - 0.35, zb + 4.7), Vector2(zawn + 0.55, zb + 4.5), Vector2(zawn + 1.0, zb + 2.5),
		Vector2(zawn + 1.6, zb + 0.3), Vector2(zawn + 3.4, zb - 0.5),
		Vector2(l - 1.2, zb + 0.2), Vector2(cu + 0.5, zb - 0.45),
		Vector2(r - 0.8, zb + 0.15), Vector2(r + 1.95, b - 1.95), Vector2(ue + 0.2, b + 0.9),
		Vector2(ue - 0.25, (b + f) * 0.5), Vector2(ue + 0.3, f - 0.6), Vector2(ue + 0.15, f + 2.6),
		# The cove.
		Vector2(ue - 1.5, f + 4.9), Vector2(ue - 4.6, f + 5.8), Vector2(ue - 6.7, f + 8.2),
		Vector2(ue - 6.3, f + 11.1), Vector2(ue - 3.6, f + 12.9), Vector2(ue - 0.5, f + 14.3),
		Vector2(ue + 1.7, f + 17.0), Vector2(ue + 2.1, f + 22.5), Vector2(ue + 1.0, f + 32.0),
		Vector2(ue + 3.6, f + 48.0), Vector2(ue + 2.0, f + 72.0), Vector2(ue + 4.5, f + 110.0)]
	var top: PackedVector2Array = _spline(controls, COAST_STEP)
	# Wobble the edge a little, then keep it clear of the lot.
	for index: int in top.size():
		var p: Vector2 = top[index]
		var nearest: Vector2 = Vector2(clampf(p.x, l, r), clampf(p.y, b, f))
		var away: float = p.distance_to(nearest)
		if away < EDGE_MIN:
			var push: Vector2 = (p - nearest).normalized() if away > 0.001 else Vector2(0.0, -1.0)
			top[index] = nearest + push * EDGE_MIN
	coast = Line.new(top, BUCKET, 4)
	_coast_normals = coast.vertex_normals.duplicate()
	# Smooth the normals so the strata do not fold at the bends.
	for pass_index: int in 3:
		var smooth: PackedVector2Array = _coast_normals.duplicate()
		for index: int in range(1, _coast_normals.size() - 1):
			smooth[index] = (_coast_normals[index - 1] + _coast_normals[index] * 2.0 + _coast_normals[index + 1]).normalized()
		_coast_normals = smooth
	_plan_strata()
	# The foot of the cliff, and the waterline (out past the cove's beach).
	_feet.clear()
	var water: PackedVector2Array = PackedVector2Array()
	for index: int in top.size():
		var foot: Vector2 = top[index] + _coast_normals[index] * _foot_offset(index)
		_feet.append(foot)
		water.append(foot + _coast_normals[index] * _beach(top[index]))
	waterline = Line.new(water, BUCKET, 4)
	# Sea stacks off the cove's mouth: (u, z, radius, top below the cliff top).
	stacks.clear()
	for spec: Vector4 in [Vector4(ue + 1.9, f + 8.6, 1.15, 2.7), Vector4(ue + 4.1, f + 11.6, 0.85, 5.2),
			Vector4(ue + 0.9, f + 12.2, 0.5, 8.6)]:
		var at: Vector2 = Vector2(spec.x, spec.y)
		for step: int in 12:
			if waterline.signed(at) > spec.z + 0.9:
				break
			at += Vector2(0.45, 0.0)
		stacks.append(Vector4(at.x, at.y, spec.z, spec.w))
	lighthouse = Vector2(cu - 27.0, zb - 23.8)
	_lamp = Vector3(lighthouse.x, TOWER_H + 0.42, lighthouse.y)
	_lamp_on_sea = lighthouse + Vector2(6.0, 4.0)


## The rock's strata (thickness of each band, top down) and the turf and soil above.
func _plan_strata() -> void:
	_bands.clear()
	_bands.append(0.28)
	_bands.append(0.42)
	var depth: float = 0.7
	var index: int = 0
	while depth < skin.drop:
		var thick: float = 1.0 + 1.7 * _r(index, 11)
		if depth + thick > skin.drop - 0.8:
			thick = skin.drop - depth + 0.5
		_bands.append(thick)
		depth += thick
		index += 1


## The base heights of the strata's boundaries (0 at the top, falling).
func _boundaries() -> Array[float]:
	var heights: Array[float] = [FLOOR_Y]
	var y: float = 0.0
	for thick: float in _bands:
		y -= thick
		heights.append(y)
	return heights


## How far out each stratum's top stands (from the edge, along the normal) and how far
## its bottom leans out: x top, y bottom, for stratum `band` (shared along the coast).
func _band_offsets() -> Array[Vector2]:
	var result: Array[Vector2] = [Vector2(0.0, 0.03), Vector2(-0.1, -0.1)]
	var bottom: float = -0.1
	for band: int in range(2, _bands.size()):
		var roll: float = _r(band, 21)
		var step: float = 0.05
		if band == 2:
			step = 0.06
		elif roll < 0.42:
			step = 0.22 + 0.25 * _r(band, 22)
		elif roll < 0.66:
			step = -0.14 - 0.14 * _r(band, 23)
		var top: float = bottom + step
		bottom = top + 0.06 + 0.16 * _r(band, 24)
		result.append(Vector2(top, bottom))
	return result


func _foot_offset(index: int) -> float:
	var offsets: Array[Vector2] = _band_offsets()
	return offsets[offsets.size() - 1].y + 0.2 * _r(index, 31)


## How wide the cove's beach is at a point of the edge (0 away from the cove).
func _beach(point: Vector2) -> float:
	return BEACH * (1.0 - smoothstep(2.6, 6.0, point.distance_to(cove)))


## The rail: inside the edge round the back and side of the lot and the cove's top.
func _plan_rail() -> void:
	rail_points.clear()
	var points: PackedVector2Array = coast.points
	var first: int = -1
	var last: int = -1
	for index: int in points.size():
		var p: Vector2 = points[index]
		var behind: bool = p.y < lot.position.y and p.x >= lot.position.x - 6.0
		var beside: bool = p.x > lot.position.x and p.y <= lot.end.y + 17.2
		if (behind or beside) and p.x > lot.position.x - 8.0:
			if first < 0:
				first = index
			last = index
	if first < 0:
		return
	var inner: PackedVector2Array = PackedVector2Array()
	for index: int in range(first, last + 1):
		inner.append(points[index] - _coast_normals[index] * RAIL_IN)
	rail_points = _resample(inner, POST_STEP)


## The cliff path from the door to the car park, the coast path, the stile and post.
func _plan_paths() -> void:
	var du: float = door.get_center().x
	var f: float = lot.end.y
	var start: float = maxf(door.end.y - 0.2, f)
	var controls: Array[Vector2] = [Vector2(du, f), Vector2(du, start + 0.6), Vector2(du - 0.6, f + 3.4),
		Vector2(du - 2.9, f + 6.6), Vector2(du - 6.0, f + 10.0), Vector2(du - 8.6, f + 14.6), Vector2(du - 10.4, f + 19.0),
		Vector2(du - 12.6, f + 22.8), Vector2(du - 15.6, f + 27.0), Vector2(du - 19.4, f + 31.4), Vector2(du - 21.5, f + 33.2)]
	path_points = _spline(controls, 0.5)
	stile = _point_at_z(path_points, f + 19.0)
	finger_post = _point_at_z(path_points, f + 22.4) + Vector2(0.95, 0.25)
	var junction: Vector2 = _point_at_z(path_points, f + 22.0)
	var ue: float = lot.end.x + EDGE_GAP
	coast_path_points = _spline([junction, junction + Vector2(2.4, 1.6), Vector2(du - 3.0, f + 24.8),
		Vector2(ue - 4.2, f + 25.8), Vector2(ue - 3.0, f + 32.0), Vector2(ue - 2.4, f + 46.0), Vector2(ue - 2.2, f + 75.0)], 0.5)
	car_park = Rect2(du - 25.5, f + 32.6, 8.0, 5.4)
	var rect: Rect2 = car_park
	lane_points = _spline([rect.position + Vector2(0.0, rect.size.y * 0.55), rect.position + Vector2(-6.0, rect.size.y * 0.7),
		rect.position + Vector2(-16.0, rect.size.y + 2.0), rect.position + Vector2(-30.0, rect.size.y + 3.0),
		rect.position + Vector2(-60.0, rect.size.y + 8.0)], 0.8)
	_blocked.append(car_park.grow(0.25))
	_path_boxes.clear()
	for line: PackedVector2Array in [path_points, coast_path_points, lane_points]:
		var box: Rect2 = Rect2(line[0], Vector2.ZERO)
		for point: Vector2 in line:
			box = box.expand(point)
		_path_boxes.append(box)


static func _point_at_z(line: PackedVector2Array, z: float) -> Vector2:
	for index: int in line.size() - 1:
		var a: Vector2 = line[index]
		var b: Vector2 = line[index + 1]
		if (a.y - z) * (b.y - z) <= 0.0 and absf(b.y - a.y) > 0.0001:
			return a.lerp(b, (z - a.y) / (b.y - a.y))
	return line[line.size() - 1]


## Centripetal Catmull-Rom through `controls`, a point about every `step` metres.
static func _spline(controls: Array[Vector2], step: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var count: int = controls.size()
	for index: int in count - 1:
		var p1: Vector2 = controls[index]
		var p2: Vector2 = controls[index + 1]
		var p0: Vector2 = controls[index - 1] if index > 0 else p1 * 2.0 - p2
		var p3: Vector2 = controls[index + 2] if index + 2 < count else p2 * 2.0 - p1
		var pieces: int = maxi(1, ceili(p1.distance_to(p2) / step))
		for piece: int in pieces:
			result.append(_centripetal(p0, p1, p2, p3, float(piece) / float(pieces)))
	result.append(controls[count - 1])
	return result


static func _centripetal(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t0: float = 0.0
	var t1: float = t0 + maxf(sqrt(p0.distance_to(p1)), 0.001)
	var t2: float = t1 + maxf(sqrt(p1.distance_to(p2)), 0.001)
	var t3: float = t2 + maxf(sqrt(p2.distance_to(p3)), 0.001)
	var at: float = lerpf(t1, t2, t)
	var a1: Vector2 = p0 * ((t1 - at) / (t1 - t0)) + p1 * ((at - t0) / (t1 - t0))
	var a2: Vector2 = p1 * ((t2 - at) / (t2 - t1)) + p2 * ((at - t1) / (t2 - t1))
	var a3: Vector2 = p2 * ((t3 - at) / (t3 - t2)) + p3 * ((at - t2) / (t3 - t2))
	var b1: Vector2 = a1 * ((t2 - at) / (t2 - t0)) + a2 * ((at - t0) / (t2 - t0))
	var b2: Vector2 = a2 * ((t3 - at) / (t3 - t1)) + a3 * ((at - t1) / (t3 - t1))
	return b1 * ((t2 - at) / (t2 - t1)) + b2 * ((at - t1) / (t2 - t1))


## Points along `line` every `step` metres (its ends included).
static func _resample(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if line.size() < 2:
		return line
	var total: float = 0.0
	for index: int in line.size() - 1:
		total += line[index].distance_to(line[index + 1])
	var count: int = maxi(1, roundi(total / step))
	var gap: float = total / float(count)
	var walked: float = 0.0
	var segment: int = 0
	var into: float = 0.0
	result.append(line[0])
	for piece: int in range(1, count):
		var want: float = gap * float(piece)
		while segment < line.size() - 2 and walked + line[segment].distance_to(line[segment + 1]) < want:
			walked += line[segment].distance_to(line[segment + 1])
			segment += 1
		var length: float = line[segment].distance_to(line[segment + 1])
		into = (want - walked) / length if length > 0.0 else 0.0
		result.append(line[segment].lerp(line[segment + 1], clampf(into, 0.0, 1.0)))
	result.append(line[line.size() - 1])
	return result


## True where something standing would sit on the lot, the door's approach, a path or
## too near the edge (`margin` is its radius).
func _is_blocked(point: Vector2, margin: float) -> bool:
	for rect: Rect2 in _blocked:
		if rect.grow(margin).has_point(point):
			return true
	return false


func _on_path(point: Vector2, margin: float) -> bool:
	var lines: Array[PackedVector2Array] = [path_points, coast_path_points, lane_points]
	var halves: Array[float] = [PATH_HALF, COAST_PATH_HALF, 1.15]
	for index: int in lines.size():
		var reach: float = halves[index] + margin
		if _path_boxes.size() > index and not _path_boxes[index].grow(reach).has_point(point):
			continue
		if _near_line(lines[index], point, reach):
			return true
	return false


static func _near_line(line: PackedVector2Array, point: Vector2, reach: float) -> bool:
	for index: int in line.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, line[index], line[index + 1])
		if closest.distance_to(point) < reach:
			return true
	return false


## Land a prop of radius `margin` may stand on: inland of the edge (and of the rail by
## the lot), off the lot, the approach and the paths.
func _free_land(point: Vector2, margin: float, inland: float = 0.5) -> bool:
	if coast.signed(point) > -(inland + margin):
		return false
	return not _is_blocked(point, margin) and not _on_path(point, margin)


# --- building ---------------------------------------------------------------

## Builds every node under `parent` (the dressing's cliff root, placed on the street frame).
func build(parent: Node3D) -> void:
	root = parent
	_plan()
	_materials()
	var key: String = var_to_str([local_reserve, shift, light_shift, salt, keep_clear, building, world_centre, skin.signature()])
	var meshes: Dictionary = _cache.get(key, {})
	if meshes.is_empty():
		meshes = _build_static()
		if _cache.size() > 4:
			_cache.clear()
		_cache[key] = meshes
	_add(_instance("Ground", meshes["ground"], _material))
	_add(_instance("Cliff", meshes["cliff"], _material))
	_add(_instance("Props", meshes["props"], _material))
	_add(_instance("Shadows", meshes["shadows"], _shadow_material))
	_add(_instance("SeaShadows", meshes["sea_shadows"], _shadow_material))
	_add(_instance("Windows", meshes["windows"], _glass_material))
	sea = _instance("Sea", meshes["sea"], sea_material)
	sea.extra_cull_margin = 8.0
	_add(sea)
	_glow = _instance("Glow", meshes["glow"], _glow_material)
	_glow.extra_cull_margin = 2.0
	_add(_glow)
	_pools = _instance("LightPools", meshes["pools"], _pool_material)
	_add(_pools)
	_build_beam()
	_build_gulls()
	_build_boat()
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
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.vertex_color_use_as_albedo = true
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_material.albedo_color = Color(skin.lamp_glow, 0.0)
	_beam_material.disable_receive_shadows = true
	_glow_material = _new_glow()
	_pool_material = StandardMaterial3D.new()
	_pool_material.vertex_color_use_as_albedo = true
	_pool_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_material.disable_receive_shadows = true
	_boat_glow = _new_glow()
	sea_material = ShaderMaterial.new()
	sea_material.shader = SEA_SHADER
	sea_material.set_shader_parameter(&"shore_z", 0.0)
	sea_material.set_shader_parameter(&"wet_width", WET_WIDTH)
	sea_material.set_shader_parameter(&"sand_wet", skin.sand_wet)
	sea_material.set_shader_parameter(&"shallow", skin.sea_shallow)
	sea_material.set_shader_parameter(&"mid", skin.sea_mid)
	sea_material.set_shader_parameter(&"deep", skin.sea_deep)
	sea_material.set_shader_parameter(&"foam", skin.foam)
	sea_material.set_shader_parameter(&"light_color", skin.lamp_glow)


func _new_glow() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter(&"mode", 0)
	material.set_shader_parameter(&"street_depth", skin.drop * 2.0)
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


static func _mesh_of(soup: NeighbourhoodGround.Soup) -> ArrayMesh:
	return soup.to_mesh() if not soup.is_empty() else ArrayMesh.new()


func _build_static() -> Dictionary:
	var ground: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var cliff: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var props: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var windows: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var shadows: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var sea_shadows: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	_lights.clear()
	_light_sizes.clear()
	_ledges.clear()
	_pool_soup = NeighbourhoodGround.Soup.new()
	_land(ground)
	_paths(ground)
	_cliff_face(cliff)
	_foot(cliff)
	_stacks(cliff, sea_shadows)
	_cliff_shadow(sea_shadows)
	_rail(props, shadows)
	_walls(props, shadows)
	_stile(props, shadows)
	_finger_post(props, shadows)
	_bench(props, shadows)
	_lifebuoy(props, shadows)
	_lanterns(props, windows, shadows)
	_festoon(props, windows, shadows)
	_thorn(props, shadows)
	_plants(props, shadows)
	_ledge_flowers(props)
	_lighthouse(props, windows, shadows)
	_car_park(ground, props, windows, shadows)
	_sheep(props, shadows)
	return {"ground": _mesh_of(ground.soup), "cliff": _mesh_of(cliff.soup), "props": _mesh_of(props.soup),
		"windows": _mesh_of(windows.soup), "shadows": _mesh_of(shadows), "sea_shadows": _mesh_of(sea_shadows),
		"sea": _sea_mesh(), "glow": _sprites(_lights, _light_sizes), "pools": _mesh_of(_pool_soup)}


# --- the cliff top ------------------------------------------------------------

## The land: one flat polygon from the edge back to well past the world's edge, with
## lighter and darker patches (gentler over the lot, where the player builds).
func _land(pen: NeighbourhoodBuildings.Pen) -> void:
	var points: PackedVector2Array = coast.points
	var first: Vector2 = points[0]
	var last: Vector2 = points[points.size() - 1]
	var reach: float = 140.0
	var c: Vector2 = world_centre
	var outline: PackedVector2Array = points.duplicate()
	outline.append(Vector2(last.x, c.y + reach))
	outline.append(Vector2(c.x - reach, c.y + reach))
	outline.append(Vector2(c.x - reach, first.y))
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for index: int in range(0, triangles.size(), 3):
		var a: Vector2 = outline[triangles[index]]
		var b: Vector2 = outline[triangles[index + 1]]
		var d: Vector2 = outline[triangles[index + 2]]
		pen.tri(Vector3(a.x, FLOOR_Y, a.y), Vector3(b.x, FLOOR_Y, b.y), Vector3(d.x, FLOOR_Y, d.y), Vector3.UP, skin.grass)
	var span: float = 46.0
	for index: int in 900:
		var at: Vector2 = c + Vector2((_r(index, 1) * 2.0 - 1.0) * span, (_r(index, 2) * 2.0 - 1.0) * span)
		var size: float = 0.35 + _r(index, 3) * 0.9
		if coast.signed(at) > -(size + 0.3):
			continue
		var colour: Color = skin.grass_light if _r(index, 4) < 0.5 else skin.grass_dark
		if lot.grow(0.6).has_point(at):
			colour = skin.grass.lerp(colour, 0.45)
		_blob(pen, at, size, size * (0.55 + _r(index, 5) * 0.4), _r(index, 6) * PI, 8, PATCH_Y + _r(index, 7) * 0.002,
			skin.grass.lerp(colour, 0.7))


func _blob(pen: NeighbourhoodBuildings.Pen, at: Vector2, rx: float, rz: float, spin: float, sides: int, y: float, colour: Color) -> void:
	var points: Array[Vector3] = []
	for index: int in sides:
		var angle: float = spin + TAU * float(index) / float(sides)
		var wobble: float = 0.85 + 0.3 * _r(int(at.x * 37.0) + index, int(at.y * 41.0))
		points.append(Vector3(at.x + cos(angle) * rx * wobble, y, at.y + sin(angle) * rz * wobble))
	for index: int in sides:
		pen.tri(Vector3(at.x, y, at.y), points[index], points[(index + 1) % sides], Vector3.UP, colour)


## A ribbon along `line` from `-half` to `half`, its width wobbling by `rough`.
func _ribbon(pen: NeighbourhoodBuildings.Pen, line: PackedVector2Array, half: float, y: float, colour: Color, rough: float) -> void:
	for index: int in line.size() - 1:
		var a: Vector2 = line[index]
		var b: Vector2 = line[index + 1]
		var before: Vector2 = line[maxi(index - 1, 0)]
		var after: Vector2 = line[mini(index + 2, line.size() - 1)]
		var na: Vector2 = (b - before).normalized().orthogonal()
		var nb: Vector2 = (after - a).normalized().orthogonal()
		var wa: float = half + rough * (0.6 * sin(float(index) * 0.9) + 0.4 * sin(float(index) * 2.3))
		var wb: float = half + rough * (0.6 * sin(float(index + 1) * 0.9) + 0.4 * sin(float(index + 1) * 2.3))
		pen.quad(Vector3(a.x - na.x * wa, y, a.y - na.y * wa), Vector3(b.x - nb.x * wb, y, b.y - nb.y * wb),
			Vector3(b.x + nb.x * wb, y, b.y + nb.y * wb), Vector3(a.x + na.x * wa, y, a.y + na.y * wa), Vector3.UP, colour)


## The cliff path (gravel on a darker worn edge, with pebbles) and the narrower coast path.
func _paths(pen: NeighbourhoodBuildings.Pen) -> void:
	_ribbon(pen, path_points, PATH_HALF + 0.11, PATH_EDGE_Y, skin.gravel_dark, 0.05)
	_ribbon(pen, path_points, PATH_HALF, PATH_Y, skin.gravel, 0.04)
	_ribbon(pen, coast_path_points, COAST_PATH_HALF + 0.1, PATH_EDGE_Y, skin.grass_dark.lerp(skin.gravel_dark, 0.5), 0.05)
	_ribbon(pen, coast_path_points, COAST_PATH_HALF, PATH_Y, skin.gravel_dark.lerp(skin.gravel, 0.45), 0.04)
	for index: int in range(0, path_points.size(), 2):
		var p: Vector2 = path_points[index]
		var along: Vector2 = (path_points[mini(index + 1, path_points.size() - 1)] - path_points[maxi(index - 1, 0)]).normalized()
		for pebble: int in 2:
			var side: float = (_r(index, 41 + pebble) - 0.5) * PATH_HALF * 1.6
			var at: Vector2 = p + along.orthogonal() * side + along * (_r(index, 43 + pebble) - 0.5) * 0.4
			var size: float = 0.025 + 0.03 * _r(index, 45 + pebble)
			_blob(pen, at, size, size * 0.8, _r(index, 47) * PI, 5, PEBBLE_Y, skin.gravel_dark if pebble == 0 else skin.gravel.lightened(0.12))


# --- the cliff ------------------------------------------------------------------

## Height of stratum boundary `band` at coast point `index` (rock boundaries wander a little).
func _boundary_y(index: int, band: int, base: Array[float]) -> float:
	if band <= 2 or band >= base.size() - 1:
		return base[band]
	return base[band] + (_r(index, 50 + band) - 0.5) * 0.2 + 0.16 * sin(float(index) * 0.17 + float(band) * 1.7)


## How a stratum looks at a depth: its rock colour faded into the air with depth.
func _hazed(colour: Color, y: float) -> Color:
	return colour.lerp(skin.haze, clampf(-y / skin.drop, 0.0, 1.0) * HAZE)


func _band_colour(band: int) -> Color:
	if band == 0:
		return skin.turf
	if band == 1:
		return skin.soil
	return skin.strata[(band - 2 + salt) % skin.strata.size()]


## The sheer face: each stratum a ring of flat facets standing out or stepping in from the
## one above, with lit ledges (some grassy) and dark overhangs where they change.
func _cliff_face(pen: NeighbourhoodBuildings.Pen) -> void:
	var points: PackedVector2Array = coast.points
	var base: Array[float] = _boundaries()
	var offsets: Array[Vector2] = _band_offsets()
	var bands: int = _bands.size()
	var count: int = points.size()
	# Per point and boundary: the boundary's height, and each stratum's top and bottom offsets.
	var heights: Array[PackedFloat32Array] = []
	var tops: Array[PackedFloat32Array] = []
	var bottoms: Array[PackedFloat32Array] = []
	for index: int in count:
		var h: PackedFloat32Array = PackedFloat32Array()
		var t: PackedFloat32Array = PackedFloat32Array()
		var b: PackedFloat32Array = PackedFloat32Array()
		for band: int in bands + 1:
			h.append(_boundary_y(index, band, base))
		for band: int in bands:
			var jitter: float = 0.0 if band < 2 else (_r(index, 60 + band) - 0.5) * 0.16 + 0.12 * sin(float(index) * 0.31 + float(band) * 2.3)
			var lean: float = 0.0 if band < 2 else (_r(index, 80 + band) - 0.5) * 0.08
			t.append(offsets[band].x + jitter)
			b.append(offsets[band].y + jitter + lean)
		heights.append(h)
		tops.append(t)
		bottoms.append(b)
	for index: int in count - 1:
		var p0: Vector2 = points[index]
		var p1: Vector2 = points[index + 1]
		var n0: Vector2 = _coast_normals[index]
		var n1: Vector2 = _coast_normals[index + 1]
		var out: Vector3 = Vector3((n0.x + n1.x) * 0.5, 0.0, (n0.y + n1.y) * 0.5)
		var crack: bool = _r(index, 71) < 0.08
		for band: int in bands:
			var y0a: float = heights[index][band]
			var y1a: float = heights[index + 1][band]
			var y0b: float = heights[index][band + 1]
			var y1b: float = heights[index + 1][band + 1]
			var a0: Vector2 = p0 + n0 * tops[index][band]
			var a1: Vector2 = p1 + n1 * tops[index + 1][band]
			var b0: Vector2 = p0 + n0 * bottoms[index][band]
			var b1: Vector2 = p1 + n1 * bottoms[index + 1][band]
			var colour: Color = _band_colour(band)
			var tone: float = 0.95 + 0.08 * _r(index * 7 + band, 72)
			colour = Color(colour.r * tone, colour.g * tone, colour.b * tone)
			if crack and band >= 2:
				colour = colour.lerp(skin.rock_dark, 0.45)
			var mid: float = (y0a + y0b) * 0.5
			var shade: Color = _hazed(colour, mid)
			var va: Vector3 = Vector3(a0.x, y0a, a0.y)
			var vb: Vector3 = Vector3(a1.x, y1a, a1.y)
			var vc: Vector3 = Vector3(b1.x, y1b, b1.y)
			var vd: Vector3 = Vector3(b0.x, y0b, b0.y)
			pen.tri(va, vb, vc, out, shade)
			pen.tri(va, vc, vd, out, Color(shade.r * 0.97, shade.g * 0.97, shade.b * 0.97))
			if band + 1 >= bands:
				continue
			# The step to the next stratum: a ledge where it stands out, an overhang where it is set in.
			var c0: Vector2 = p0 + n0 * tops[index][band + 1]
			var c1: Vector2 = p1 + n1 * tops[index + 1][band + 1]
			var step0: float = tops[index][band + 1] - bottoms[index][band]
			var step1: float = tops[index + 1][band + 1] - bottoms[index + 1][band]
			if absf(step0) < 0.02 and absf(step1) < 0.02:
				continue
			var ledge: bool = step0 + step1 > 0.0
			var next: Color = _band_colour(band + 1)
			var lip: Color = next.lightened(0.1) if ledge else skin.rock_dark
			if ledge and band >= 2 and step0 + step1 > 0.5 and _r(index, 90 + band) < 0.3 and y0b < -1.5:
				lip = skin.grass_dark.lerp(skin.turf, 0.4)
				if _r(index, 110 + band) < 0.5:
					_ledges.append(Vector3((b0.x + c0.x) * 0.5, y0b, (b0.y + c0.y) * 0.5))
			lip = _hazed(lip, y0b)
			pen.quad(Vector3(b0.x, y0b, b0.y), Vector3(b1.x, y1b, b1.y), Vector3(c1.x, y1b, c1.y), Vector3(c0.x, y0b, c0.y),
				Vector3.UP if ledge else Vector3.DOWN, lip)


## Boulders along the foot where the surf breaks (fewer on the cove's beach), and the beach.
func _foot(pen: NeighbourhoodBuildings.Pen) -> void:
	var y: float = sea_y()
	var count: int = _feet.size()
	for index: int in count - 1:
		var beach: float = _beach(coast.points[index])
		if beach > 0.05:
			# The cove's sand, from the foot down under the water.
			var w0: Vector2 = waterline.points[index]
			var w1: Vector2 = waterline.points[index + 1]
			var f0: Vector2 = _feet[index] - _coast_normals[index] * 0.3
			var f1: Vector2 = _feet[index + 1] - _coast_normals[index + 1] * 0.3
			var o0: Vector2 = w0 + _coast_normals[index] * 1.2
			var o1: Vector2 = w1 + _coast_normals[index + 1] * 1.2
			var sand: Color = _hazed(skin.sand, y)
			pen.quad(Vector3(f0.x, y + 0.16, f0.y), Vector3(f1.x, y + 0.16, f1.y), Vector3(w1.x, y + 0.01, w1.y), Vector3(w0.x, y + 0.01, w0.y),
				Vector3.UP, sand)
			pen.quad(Vector3(w0.x, y + 0.01, w0.y), Vector3(w1.x, y + 0.01, w1.y), Vector3(o1.x, y - 0.3, o1.y), Vector3(o0.x, y - 0.3, o0.y),
				Vector3.UP, _hazed(skin.sand_wet, y))
		if index % 2 == 1:
			continue
		var roll: float = _r(index, 120)
		if roll < (0.75 if beach > 0.4 else 0.18):
			continue
		var out: float = -0.2 + 1.4 * _r(index, 121) * (1.0 - beach / BEACH)
		var at: Vector2 = _feet[index] + _coast_normals[index] * out + (coast.points[mini(index + 1, count - 1)] - coast.points[index]) * _r(index, 122)
		var size: float = 0.28 + 0.5 * _r(index, 123)
		var tone: Color = skin.strata[int(_r(index, 124) * 97.0) % skin.strata.size()].lerp(skin.rock_dark, 0.25 * _r(index, 125))
		tone = _hazed(tone, y)
		pen.lump(Vector3(at.x, y + size * 0.15, at.y), size, size * (0.5 + 0.4 * _r(index, 126)), size * 0.85, _r(index, 127) * PI,
			tone, tone.darkened(0.15))
		if _r(index, 128) < 0.4:
			var near: Vector2 = at + _coast_normals[index] * (size + 0.2)
			var small: float = size * 0.5
			pen.lump(Vector3(near.x, y + small * 0.1, near.y), small, small * 0.6, small, _r(index, 129) * PI, tone, tone.darkened(0.15))


## Sea stacks off the cove: columns of the same strata as the cliff, lower than the top,
## with a grassy cap where gulls sit.
func _stacks(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var base: Array[float] = _boundaries()
	var sides: int = 7
	for stack: int in stacks.size():
		var spec: Vector4 = stacks[stack]
		var centre: Vector2 = Vector2(spec.x, spec.y)
		var top_y: float = -spec.w
		var rings: Array[PackedVector2Array] = []
		var heights: Array[float] = [top_y]
		for band: int in range(1, base.size()):
			if base[band] < top_y - 0.3:
				heights.append(base[band])
		heights[heights.size() - 1] = sea_y() - 0.5
		for level: int in heights.size():
			var ring: PackedVector2Array = PackedVector2Array()
			var grow: float = 1.0 + 0.1 * float(level) * (_r(stack, 130 + level) - 0.2)
			for side: int in sides:
				var angle: float = TAU * float(side) / float(sides) + _r(stack, 131) * TAU
				var radius: float = spec.z * grow * (0.82 + 0.3 * _r(stack * 13 + side, 132 + level))
				ring.append(centre + Vector2(cos(angle), sin(angle)) * radius)
			rings.append(ring)
		for level: int in heights.size() - 1:
			var y0: float = heights[level]
			var y1: float = heights[level + 1]
			var band_colour: Color = _band_colour(level + 2 + int(spec.w))
			for side: int in sides:
				var next: int = (side + 1) % sides
				var a: Vector2 = rings[level][side]
				var b: Vector2 = rings[level][next]
				var c: Vector2 = rings[level + 1][next]
				var d: Vector2 = rings[level + 1][side]
				var middle: Vector2 = (a + b + c + d) * 0.25 - centre
				var tone: float = 0.9 + 0.16 * _r(stack * 31 + side, 133 + level)
				var colour: Color = _hazed(Color(band_colour.r * tone, band_colour.g * tone, band_colour.b * tone), (y0 + y1) * 0.5)
				pen.quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y1, c.y), Vector3(d.x, y1, d.y),
					Vector3(middle.x, 0.0, middle.y), colour)
		# The cap: turf, a few tufts and sea pinks, and gulls nesting (white dots).
		var cap: Array[Vector2] = []
		for point: Vector2 in rings[0]:
			cap.append(point)
		pen.soup.star(centre, cap, top_y, _hazed(skin.turf, top_y))
		for dot: int in 3 + stack:
			var angle: float = _r(stack * 5 + dot, 140) * TAU
			var at: Vector2 = centre + Vector2(cos(angle), sin(angle)) * spec.z * 0.5 * _r(stack * 5 + dot, 141)
			if dot % 2 == 0:
				pen.lump(Vector3(at.x, top_y + 0.04, at.y), 0.07, 0.06, 0.09, angle, skin.gull_body, skin.gull_wing)
			else:
				pen.lump(Vector3(at.x, top_y + 0.03, at.y), 0.11, 0.07, 0.1, angle, _hazed(skin.thrift, top_y), _hazed(skin.thrift_leaf, top_y))
		# Its shadow on the water.
		var cast: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in rings[rings.size() - 1]:
			cast.append(point)
		for point: Vector2 in rings[0]:
			cast.append(point + light_shift * (top_y - sea_y()))
		var hull: PackedVector2Array = Geometry2D.convex_hull(cast)
		var outline: Array[Vector2] = []
		for index: int in hull.size() - 1:
			outline.append(hull[index])
		shadows.star(centre + light_shift * (top_y - sea_y()) * 0.5, outline, sea_y() + 0.02, Color(0.06, 0.1, 0.16, 0.32))


static func _v3(point: Vector2, y: float) -> Vector3:
	return Vector3(point.x, y, point.y)


## The cliff's shadow on the water, on the side away from the light.
func _cliff_shadow(shadows: NeighbourhoodGround.Soup) -> void:
	var y: float = sea_y() + 0.02
	var push: Vector2 = light_shift * skin.drop
	var shade: Color = Color(0.06, 0.1, 0.16, 0.34)
	var count: int = _feet.size()
	# Where the top edge's shadow falls: the edge pushed along the light, but never back
	# under the cliff (on a lit face the shadow shrinks to the foot).
	var ends: PackedVector2Array = PackedVector2Array()
	var cast: PackedFloat32Array = PackedFloat32Array()
	for index: int in count:
		var end: Vector2 = coast.points[index] + push
		var out: float = (end - _feet[index]).dot(_coast_normals[index])
		cast.append(out)
		ends.append(end if out > 0.0 else _feet[index])
	for index: int in count - 1:
		if cast[index] <= 0.0 and cast[index + 1] <= 0.0:
			continue
		if _feet[index].distance_to(world_centre) > SEA_INNER + 20.0:
			continue
		var f0: Vector2 = _feet[index] - _coast_normals[index] * 0.4
		var f1: Vector2 = _feet[index + 1] - _coast_normals[index + 1] * 0.4
		var e0: Vector2 = ends[index]
		var e1: Vector2 = ends[index + 1]
		shadows.tri(Vector3(f0.x, y, f0.y), Vector3(f1.x, y, f1.y), Vector3(e1.x, y, e1.y), Vector3.UP, shade)
		shadows.tri(Vector3(f0.x, y, f0.y), Vector3(e1.x, y, e1.y), Vector3(e0.x, y, e0.y), Vector3.UP, shade)


# --- the sea --------------------------------------------------------------------

## The water: a fine grid round the world's middle and a ring out to the horizon, its UV
## the (along, -distance) from the waterline that sea.gdshader expects (its waterline at
## z 0, falling toward the sea), so the surf follows the foot of the cliff and the cove.
func _sea_mesh() -> ArrayMesh:
	var y: float = sea_y()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var cells: int = ceili(SEA_INNER * 2.0 / SEA_CELL)
	var origin: Vector2 = world_centre - Vector2.ONE * SEA_INNER
	var grid: PackedFloat32Array = PackedFloat32Array()
	for row: int in cells + 1:
		for column: int in cells + 1:
			grid.append(waterline.signed(origin + Vector2(column, row) * SEA_CELL))
	var keep: float = -(WET_WIDTH / SEA_SCALE + 1.2)
	for row: int in cells:
		for column: int in cells:
			var i00: int = row * (cells + 1) + column
			var d00: float = grid[i00]
			var d10: float = grid[i00 + 1]
			var d01: float = grid[i00 + cells + 1]
			var d11: float = grid[i00 + cells + 2]
			if maxf(maxf(d00, d10), maxf(d01, d11)) < keep:
				continue
			var p00: Vector2 = origin + Vector2(column, row) * SEA_CELL
			var p10: Vector2 = p00 + Vector2(SEA_CELL, 0.0)
			var p01: Vector2 = p00 + Vector2(0.0, SEA_CELL)
			var p11: Vector2 = p00 + Vector2(SEA_CELL, SEA_CELL)
			for corner: Array in [[p00, d00], [p11, d11], [p10, d10], [p00, d00], [p01, d01], [p11, d11]]:
				var p: Vector2 = corner[0]
				vertices.append(Vector3(p.x, y, p.y))
				normals.append(Vector3.UP)
				uvs.append(Vector2(p.x + p.y, -float(corner[1])) * SEA_SCALE)
	# The ring out to the horizon: each edge of the grid's border joined to the far border.
	var border: Array[Vector2] = []
	for step: int in cells:
		border.append(origin + Vector2(step, 0) * SEA_CELL)
	for step: int in cells:
		border.append(origin + Vector2(cells, step) * SEA_CELL)
	for step: int in cells:
		border.append(origin + Vector2(cells - step, cells) * SEA_CELL)
	for step: int in cells:
		border.append(origin + Vector2(0, cells - step) * SEA_CELL)
	var scale: float = SEA_OUTER / SEA_INNER
	for index: int in border.size():
		var a: Vector2 = border[index]
		var b: Vector2 = border[(index + 1) % border.size()]
		var fa: Vector2 = world_centre + (a - world_centre) * scale
		var fb: Vector2 = world_centre + (b - world_centre) * scale
		var da: float = waterline.signed(a)
		var db: float = waterline.signed(b)
		var dfa: float = waterline.signed(fa)
		var dfb: float = waterline.signed(fb)
		if maxf(maxf(da, db), maxf(dfa, dfb)) < keep:
			continue
		for corner: Array in [[a, da], [b, db], [fb, dfb], [a, da], [fb, dfb], [fa, dfa]]:
			var p: Vector2 = corner[0]
			vertices.append(Vector3(p.x, y, p.y))
			normals.append(Vector3.UP)
			uvs.append(Vector2(p.x + p.y, -float(corner[1])) * SEA_SCALE)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- along the edge ----------------------------------------------------------------

## The rail: white posts and two timber rails, inside the edge all round the lot.
func _rail(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	for index: int in rail_points.size():
		var p: Vector2 = rail_points[index]
		pen.box(Vector3(p.x - 0.04, FLOOR_Y, p.y - 0.04), Vector3(p.x + 0.04, RAIL_H, p.y + 0.04), skin.rail_post)
		pen.box(Vector3(p.x - 0.05, RAIL_H, p.y - 0.05), Vector3(p.x + 0.05, RAIL_H + 0.03, p.y + 0.05), skin.rail_post.darkened(0.06))
		_shade_disc(shadows, p + light_shift * RAIL_H * 0.5, 0.06, 0.24)
		if index + 1 >= rail_points.size():
			continue
		var q: Vector2 = rail_points[index + 1]
		var along: Vector2 = (q - p).normalized()
		var side: Vector2 = along.orthogonal() * 0.022
		for height: float in [RAIL_H - 0.07, 0.27]:
			var lo: float = height - 0.025
			var hi: float = height + 0.025
			var a: Vector2 = p + along * 0.04
			var b: Vector2 = q - along * 0.04
			pen.quad(_v3(a - side, hi), _v3(b - side, hi), _v3(b + side, hi), _v3(a + side, hi), Vector3.UP, skin.rail)
			pen.quad(_v3(a - side, lo), _v3(b - side, lo), _v3(b - side, hi), _v3(a - side, hi), Vector3(-side.x, 0.0, -side.y), skin.rail.darkened(0.08))
			pen.quad(_v3(a + side, lo), _v3(b + side, lo), _v3(b + side, hi), _v3(a + side, hi), Vector3(side.x, 0.0, side.y), skin.rail.darkened(0.08))
		_shade_line(shadows, p, q, 0.03, RAIL_H * 0.8, 0.14)


## A tapered six-sided post.
func _drum(pen: NeighbourhoodBuildings.Pen, at: Vector2, y0: float, y1: float, r0: float, r1: float, colour: Color, sides: int = 6, cap: bool = true) -> void:
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var b0: Vector3 = Vector3(at.x + cos(a0) * r0, y0, at.y + sin(a0) * r0)
		var b1: Vector3 = Vector3(at.x + cos(a1) * r0, y0, at.y + sin(a1) * r0)
		var t0: Vector3 = Vector3(at.x + cos(a0) * r1, y1, at.y + sin(a0) * r1)
		var t1: Vector3 = Vector3(at.x + cos(a1) * r1, y1, at.y + sin(a1) * r1)
		var hint: Vector3 = Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		pen.quad(b0, b1, t1, t0, hint, colour)
		if cap:
			pen.tri(Vector3(at.x, y1, at.y), t0, t1, Vector3.UP, colour)


## A bench by the rail at the cove, facing out to sea.
func _bench(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var best: int = -1
	var target: Vector2 = cove + Vector2(-3.4, 0.6)
	for index: int in rail_points.size():
		if best < 0 or rail_points[index].distance_to(target) < rail_points[best].distance_to(target):
			best = index
	if best < 1 or best + 1 >= rail_points.size():
		return
	var along: Vector2 = (rail_points[best + 1] - rail_points[best - 1]).normalized()
	var out: Vector2 = -along.orthogonal()
	if coast.signed(rail_points[best] + out) < coast.signed(rail_points[best]):
		out = -out
	var at: Vector2 = rail_points[best] - out * 0.75
	if not _free_land(at, 0.5, 0.0):
		return
	var basis: Basis = Basis(Vector3.UP, atan2(out.x, out.y))
	pen.xf = Transform3D(basis, _v3(at, 0.0))
	# Seat planks, a back toward the land, two cast legs at each end.
	for plank: int in 3:
		var z: float = -0.12 + float(plank) * 0.09
		pen.box(Vector3(-0.55, 0.25, z - 0.035), Vector3(0.55, 0.28, z + 0.035), skin.timber)
	for plank: int in 2:
		var y: float = 0.36 + float(plank) * 0.11
		pen.box(Vector3(-0.55, y, -0.22), Vector3(0.55, y + 0.07, -0.19), skin.timber)
	for x: float in [-0.48, 0.48]:
		pen.box(Vector3(x - 0.03, FLOOR_Y, -0.18), Vector3(x + 0.03, 0.25, -0.13), skin.timber_dark)
		pen.box(Vector3(x - 0.03, FLOOR_Y, 0.1), Vector3(x + 0.03, 0.25, 0.15), skin.timber_dark)
		pen.box(Vector3(x - 0.03, 0.25, -0.24), Vector3(x + 0.03, 0.55, -0.19), skin.timber_dark)
	pen.xf = Transform3D.IDENTITY
	_shade_rect(shadows, Rect2(at - Vector2(0.5, 0.18), Vector2(1.0, 0.36)), 0.3, 0.22)


## A lifebuoy in its stand by the rail at the corner behind the lot.
func _lifebuoy(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var best: int = -1
	var target: Vector2 = Vector2(lot.end.x + 1.6, lot.position.y - 1.6)
	for index: int in rail_points.size():
		if best < 0 or rail_points[index].distance_to(target) < rail_points[best].distance_to(target):
			best = index
	if best < 0:
		return
	var p: Vector2 = rail_points[best]
	var at: Vector2 = p + _inland_of(p) * 0.4
	if _is_blocked(at, 0.2):
		return
	pen.box(Vector3(at.x - 0.05, FLOOR_Y, at.y - 0.05), Vector3(at.x + 0.05, 0.86, at.y + 0.05), skin.timber_dark)
	pen.box(Vector3(at.x - 0.24, 0.82, at.y - 0.06), Vector3(at.x + 0.24, 0.86, at.y + 0.06), skin.timber_dark)
	var facing: Vector2 = _inland_of(p)
	var basis: Basis = Basis(Vector3.UP, atan2(facing.x, facing.y))
	pen.xf = Transform3D(basis, _v3(at, 0.0))
	var segments: int = 12
	for index: int in segments:
		var a0: float = TAU * float(index) / float(segments)
		var a1: float = TAU * float(index + 1) / float(segments)
		var colour: Color = skin.buoy_a if (index / 3) % 2 == 0 else skin.buoy_b
		var outer0: Vector3 = Vector3(cos(a0) * 0.22, 0.56 + sin(a0) * 0.22, 0.07)
		var outer1: Vector3 = Vector3(cos(a1) * 0.22, 0.56 + sin(a1) * 0.22, 0.07)
		var inner0: Vector3 = Vector3(cos(a0) * 0.12, 0.56 + sin(a0) * 0.12, 0.07)
		var inner1: Vector3 = Vector3(cos(a1) * 0.12, 0.56 + sin(a1) * 0.12, 0.07)
		var back: Vector3 = Vector3(0.0, 0.0, -0.08)
		pen.quad(inner0, outer0, outer1, inner1, Vector3.BACK, colour)
		pen.quad(outer0, outer1, outer1 + back, outer0 + back, Vector3(cos(a0), sin(a0), 0.0), colour.darkened(0.1))
		pen.quad(inner0, inner1, inner1 + back, inner0 + back, Vector3(-cos(a0), -sin(a0), 0.0), colour.darkened(0.2))
	pen.xf = Transform3D.IDENTITY
	_shade_disc(shadows, at + light_shift * 0.45, 0.12, 0.22)


## The way inland from an edge point (the opposite of the sea).
func _inland_of(point: Vector2) -> Vector2:
	var best: int = 0
	var points: PackedVector2Array = coast.points
	for index: int in points.size():
		if points[index].distance_squared_to(point) < points[best].distance_squared_to(point):
			best = index
	return -_coast_normals[best]


# --- walls, the stile and the finger post ----------------------------------------------

## The dry-stone wall across the headland (the stile in it, where the path crosses) and
## a field wall inland, with gaps.
func _walls(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var f: float = lot.end.y
	var z: float = stile.y
	var wall: Array[Vector2] = []
	var u: float = stile.x + 0.55
	# East from the stile to just short of the edge.
	while coast.signed(Vector2(u + 0.7, z + 0.05 * sin(u))) < -1.0:
		wall.append(Vector2(u, z + 0.08 * sin(u * 0.7)))
		u += 0.7
	_wall_run(pen, shadows, wall, 301)
	wall.clear()
	u = stile.x - 0.55
	while u > world_centre.x - 70.0:
		wall.append(Vector2(u, z + 0.1 * sin(u * 0.5) + (u - stile.x) * 0.03))
		u -= 0.7
	_wall_run(pen, shadows, wall, 401)
	# A field wall running back toward the edge west of the café, with a gap halfway.
	wall.clear()
	var x: float = lot.position.x - 12.5
	var zz: float = z - 0.5
	while coast.signed(Vector2(x, zz - 0.7)) < -1.2:
		if absf(zz - (lot.position.y + f) * 0.5) > 0.9:
			wall.append(Vector2(x + 0.15 * sin(zz * 0.6), zz))
		else:
			_wall_run(pen, shadows, wall, 501)
			wall.clear()
		zz -= 0.7
	_wall_run(pen, shadows, wall, 601)


## One run of dry-stone wall through `points` (a piece between each pair).
func _wall_run(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, points: Array[Vector2], seed_value: int) -> void:
	for index: int in points.size() - 1:
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		if _is_blocked((a + b) * 0.5, 0.2) or _near_line(path_points, (a + b) * 0.5, PATH_HALF + 0.3):
			continue
		_wall_piece(pen, shadows, a, b, seed_value + index)


func _wall_piece(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, a: Vector2, b: Vector2, seed_value: int) -> void:
	var along: Vector2 = (b - a).normalized()
	var normal: Vector2 = Vector2(-along.y, along.x)
	var base: float = 0.15
	var top: float = 0.1
	var height: float = 0.34
	var mid: float = 0.17
	for side: float in [-1.0, 1.0]:
		var split: float = 0.3 + 0.4 * _r(seed_value, 341 + int(side))
		for course: int in 2:
			var y0: float = FLOOR_Y if course == 0 else mid
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
	var lift: float = height + 0.03 + 0.03 * _r(seed_value, 345)
	var w: float = top + 0.015
	var c: Array[Vector2] = [a - normal * w, b - normal * w, b + normal * w, a + normal * w]
	pen.quad(_v3(c[0], lift), _v3(c[1], lift), _v3(c[2], lift), _v3(c[3], lift), Vector3.UP, skin.stone_light.darkened(0.06 * _r(seed_value, 346)))
	for side: float in [-1.0, 1.0]:
		var p: Vector2 = a + normal * side * w
		var q: Vector2 = b + normal * side * w
		pen.quad(_v3(p, height), _v3(q, height), _v3(q, lift), _v3(p, lift), Vector3(normal.x * side, 0.0, normal.y * side), skin.stone_dark)
	pen.quad(_v3(c[1], height), _v3(c[2], height), _v3(c[2], lift), _v3(c[1], lift), Vector3(along.x, 0.0, along.y), skin.stone_dark)
	pen.quad(_v3(c[0], height), _v3(c[3], height), _v3(c[3], lift), _v3(c[0], lift), Vector3(-along.x, 0.0, -along.y), skin.stone_dark)
	_shade_line(shadows, a, b, base, height * 0.8, 0.26)


## A wooden step stile in the wall's gap: two stout posts, a step either side and a rail.
func _stile(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var at: Vector2 = stile
	var along: Vector2 = Vector2(1.0, 0.0)
	pen.xf = Transform3D(Basis.IDENTITY, _v3(at, 0.0))
	for x: float in [-0.5, 0.5]:
		pen.box(Vector3(x - 0.06, FLOOR_Y, -0.06), Vector3(x + 0.06, 0.62, 0.06), skin.timber_dark)
		pen.box(Vector3(x - 0.07, 0.62, -0.07), Vector3(x + 0.07, 0.65, 0.07), skin.timber_dark.darkened(0.1))
	# The fence rails it crosses, and its tread on each side.
	for y: float in [0.2, 0.42]:
		pen.box(Vector3(-0.44, y, -0.02), Vector3(0.44, y + 0.05, 0.02), skin.timber)
	for z: float in [-0.24, 0.24]:
		pen.box(Vector3(-0.42, 0.16, z - 0.09), Vector3(0.42, 0.2, z + 0.09), skin.timber.lightened(0.08))
		for x: float in [-0.38, 0.38]:
			pen.box(Vector3(x - 0.03, FLOOR_Y, z - 0.03), Vector3(x + 0.03, 0.16, z + 0.03), skin.timber_dark)
	pen.xf = Transform3D.IDENTITY
	_shade_line(shadows, at - along * 0.5, at + along * 0.5, 0.25, 0.4, 0.2)


## The finger post where the coast path turns off: three white arms on a dark post.
func _finger_post(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var at: Vector2 = finger_post
	pen.box(Vector3(at.x - 0.045, FLOOR_Y, at.y - 0.045), Vector3(at.x + 0.045, 1.02, at.y + 0.045), skin.timber_dark)
	pen.box(Vector3(at.x - 0.06, 1.02, at.y - 0.06), Vector3(at.x + 0.06, 1.06, at.y + 0.06), skin.timber_dark.darkened(0.1))
	var targets: Array[Vector2] = [Vector2(door.get_center().x, lot.end.y), car_park.get_center(),
		coast_path_points[mini(14, coast_path_points.size() - 1)]]
	for arm: int in targets.size():
		var direction: Vector2 = (targets[arm] - at).normalized()
		var y: float = 0.94 - float(arm) * 0.12
		pen.xf = Transform3D(Basis(Vector3.UP, atan2(direction.x, direction.y) - PI * 0.5), Vector3(at.x, y, at.y))
		pen.box(Vector3(0.04, -0.035, -0.012), Vector3(0.36, 0.035, 0.012), skin.rail_post)
		# The pointed end, and the painted finger.
		pen.tri(Vector3(0.36, -0.035, 0.0121), Vector3(0.36, 0.035, 0.0121), Vector3(0.42, 0.0, 0.0121), Vector3.BACK, skin.rail_post)
		pen.tri(Vector3(0.36, -0.035, -0.0121), Vector3(0.36, 0.035, -0.0121), Vector3(0.42, 0.0, -0.0121), Vector3.FORWARD, skin.rail_post)
		pen.box(Vector3(0.1, -0.018, -0.0135), Vector3(0.3, 0.018, 0.0135), skin.timber_dark if arm != 0 else skin.buoy_a.darkened(0.1))
	pen.xf = Transform3D.IDENTITY
	_shade_disc(shadows, at + light_shift * 0.5, 0.08, 0.22)


## A windswept thorn by the stile, its trunk and crown leaning away from the sea.
func _thorn(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var at: Vector2 = stile + Vector2(2.4, -1.6)
	for tries: int in 8:
		if _free_land(at, 0.6):
			break
		at += Vector2(0.6, -0.5)
	var lean: Vector3 = Vector3(WIND.x, 0.0, WIND.y)
	var base: Vector3 = _v3(at, FLOOR_Y)
	var knee: Vector3 = base + Vector3.UP * 0.55 + lean * 0.22
	var head: Vector3 = base + Vector3.UP * 0.95 + lean * 0.75
	for part: Array in [[base, knee, 0.07, 0.055], [knee, head, 0.055, 0.035]]:
		var from: Vector3 = part[0]
		var to: Vector3 = part[1]
		var r0: float = part[2]
		var r1: float = part[3]
		for side: int in 5:
			var a0: float = TAU * float(side) / 5.0
			var a1: float = TAU * float(side + 1) / 5.0
			var o0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
			var o1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
			pen.quad(from + o0 * r0, from + o1 * r0, to + o1 * r1, to + o0 * r1, (o0 + o1) * 0.5, skin.trunk)
	for clump: int in 4:
		var t: float = float(clump) / 3.0
		var centre: Vector3 = knee.lerp(head, 0.3 + 0.7 * t) + lean * (0.15 + 0.3 * t) + Vector3.UP * (0.12 - 0.05 * t)
		var size: float = 0.36 - 0.05 * float(clump)
		var colour: Color = skin.thorn_leaf.lerp(skin.thorn_leaf.lightened(0.12), _r(clump, 151))
		pen.lump(centre, size * 1.25, size * 0.42, size, atan2(WIND.y, WIND.x), colour, colour.darkened(0.25))
	_shade_disc(shadows, at + Vector2(WIND.x, WIND.y) * 0.5 + light_shift * 0.9, 0.55, 0.24)


# --- plants -----------------------------------------------------------------------

## Wind-bent grass tufts all over the top, sea pinks along the edge and gorse in clumps.
func _plants(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var c: Vector2 = world_centre
	var span: float = 44.0
	for index: int in 2600:
		var at: Vector2 = c + Vector2((_r(index, 201) * 2.0 - 1.0) * span, (_r(index, 202) * 2.0 - 1.0) * span)
		if not _free_land(at, 0.12, 0.1):
			continue
		var colour: Color = skin.tuft_colors[int(_r(index, 203) * 97.0) % skin.tuft_colors.size()]
		_tuft(pen, _v3(at, FLOOR_Y), 0.2 + 0.14 * _r(index, 204), colour, index)
	# Sea pinks: cushions of leaves dotted pink, thickest near the edge.
	for index: int in coast.points.size():
		var p: Vector2 = coast.points[index]
		if p.distance_to(c) > span + 6.0:
			continue
		for clump: int in 2:
			if _r(index * 3 + clump, 211) < 0.2:
				continue
			var at: Vector2 = p - _coast_normals[index] * (0.2 + 2.0 * _r(index * 3 + clump, 212) * _r(index * 3 + clump, 213))
			at += (_r(index * 3 + clump, 214) - 0.5) * Vector2(0.6, 0.6)
			if _is_blocked(at, 0.12) or _on_path(at, 0.1) or coast.signed(at) > -0.12 or _near_line(rail_points, at, 0.12):
				continue
			_thrift(pen, at, 0.11 + 0.08 * _r(index * 3 + clump, 215), index * 3 + clump)
	# Gorse in clumps: by the walls, along the path's landward side, and on the headland.
	var homes: Array[Vector2] = [stile + Vector2(-3.0, -1.2), stile + Vector2(-6.5, 1.8), stile + Vector2(4.5, -3.5),
		Vector2(lot.position.x - 5.5, lot.get_center().y + 1.0), Vector2(lot.position.x - 4.0, lot.end.y + 4.0),
		lighthouse + Vector2(4.0, 6.0), lighthouse + Vector2(-2.5, 9.0), Vector2(lot.position.x - 14.0, lot.position.y - 1.0),
		finger_post + Vector2(-3.0, 3.5), car_park.position + Vector2(-2.0, -2.0), Vector2(lot.end.x - 2.0, lot.end.y + 22.0)]
	for home: int in homes.size():
		for bush: int in 7:
			var angle: float = _r(home * 11 + bush, 221) * TAU
			var at: Vector2 = homes[home] + Vector2(cos(angle), sin(angle)) * (0.4 + 2.2 * _r(home * 11 + bush, 222))
			var size: float = 0.26 + 0.22 * _r(home * 11 + bush, 223)
			if not _free_land(at, size + 0.1, 0.6):
				continue
			_gorse(pen, shadows, at, size, home * 11 + bush)
	# Rocks poking through the turf here and there.
	for index: int in 60:
		var at: Vector2 = c + Vector2((_r(index, 231) * 2.0 - 1.0) * span, (_r(index, 232) * 2.0 - 1.0) * span)
		var size: float = 0.12 + 0.2 * _r(index, 233)
		if not _free_land(at, size + 0.1, 0.4):
			continue
		var tone: Color = skin.stone.lerp(skin.stone_light, _r(index, 234))
		pen.lump(Vector3(at.x, FLOOR_Y, at.y), size, size * 0.45, size * 0.8, _r(index, 235) * PI, tone, tone.darkened(0.2))


func _tuft(pen: NeighbourhoodBuildings.Pen, at: Vector3, height: float, colour: Color, seed_value: int) -> void:
	var wind: Vector3 = Vector3(WIND.x, 0.0, WIND.y)
	for index: int in 4:
		var angle: float = _r(seed_value + index, 111) * TAU
		var lean: Vector3 = wind * height * (0.45 + 0.3 * _r(seed_value + index, 113)) + Vector3(cos(angle), 0.0, sin(angle)) * height * 0.12
		var across: Vector3 = Vector3(-WIND.y, 0.0, WIND.x) * 0.045 + Vector3(cos(angle), 0.0, sin(angle)) * 0.015
		pen.tri(at - across, at + across, at + lean + Vector3.UP * height * (0.65 + 0.3 * _r(seed_value + index, 112)), lean + Vector3.UP * 0.2,
			colour if index % 2 == 0 else colour.lightened(0.08))


## A sea-pink cushion: a low mound of leaves with pink flower heads on top.
func _thrift(pen: NeighbourhoodBuildings.Pen, at: Vector2, size: float, seed_value: int, y: float = FLOOR_Y, fade: float = 0.0) -> void:
	var leaf: Color = skin.thrift_leaf.lerp(skin.haze, fade)
	var bloom: Color = skin.thrift.lerp(skin.haze, fade)
	pen.lump(Vector3(at.x, y + size * 0.2, at.y), size, size * 0.5, size * 0.9, _r(seed_value, 241) * PI, leaf, leaf.darkened(0.2))
	for head: int in 4:
		var angle: float = _r(seed_value + head, 242) * TAU
		var p: Vector2 = at + Vector2(cos(angle), sin(angle)) * size * 0.55 * (0.3 + 0.7 * _r(seed_value + head, 243))
		var lift: float = y + size * 0.55 + 0.05 * _r(seed_value + head, 244)
		pen.lump(Vector3(p.x, lift, p.y), size * 0.38, size * 0.26, size * 0.38, angle, bloom, bloom.darkened(0.15))


## A gorse bush: a dark spiny mound leaning from the wind, dotted with yellow flowers.
func _gorse(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2, size: float, seed_value: int) -> void:
	var lean: Vector3 = Vector3(WIND.x, 0.0, WIND.y) * size * 0.25
	var centre: Vector3 = Vector3(at.x, FLOOR_Y + size * 0.55, at.y) + lean
	var spin: float = atan2(WIND.y, WIND.x)
	pen.lump(centre, size * 1.15, size * 0.75, size, spin, skin.gorse, skin.gorse.darkened(0.25))
	pen.lump(centre + Vector3.UP * size * 0.35 + lean, size * 0.7, size * 0.5, size * 0.65, spin + 0.5, skin.gorse.lightened(0.06), skin.gorse)
	for bloom: int in 7:
		var angle: float = _r(seed_value + bloom, 251) * TAU
		var height: float = 0.25 + 0.75 * _r(seed_value + bloom, 252)
		var reach: float = size * (1.05 - 0.55 * height)
		var p: Vector3 = centre + Vector3(cos(angle) * reach, size * 0.75 * height + 0.02, sin(angle) * reach * 0.9) + lean * height
		pen.box(p - Vector3(0.028, 0.02, 0.028), p + Vector3(0.028, 0.03, 0.028), skin.gorse_bloom)
	_shade_disc(shadows, at + light_shift * size * 0.8, size * 1.05, 0.24)


## Sea pinks on the grassy ledges down the cliff face, fading into the air with depth.
func _ledge_flowers(pen: NeighbourhoodBuildings.Pen) -> void:
	for index: int in _ledges.size():
		var spot: Vector3 = _ledges[index]
		var fade: float = clampf(-spot.y / skin.drop, 0.0, 1.0) * HAZE
		_thrift(pen, Vector2(spot.x, spot.z), 0.12, 700 + index, spot.y, fade)


# --- the headland's lighthouse and the car park ------------------------------------------

## The lighthouse on the far headland (white, with a band, a gallery and lantern), and
## the keeper's cottage beside it inside a low wall.
func _lighthouse(pen: NeighbourhoodBuildings.Pen, windows: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var at: Vector2 = lighthouse
	_drum(pen, at, FLOOR_Y, 0.22, 0.95, 0.92, skin.stone_light, 8)
	var bands: int = 6
	for band: int in bands:
		var y0: float = 0.22 + (TOWER_H - 0.22) * float(band) / float(bands)
		var y1: float = 0.22 + (TOWER_H - 0.22) * float(band + 1) / float(bands)
		var r0: float = lerpf(0.72, 0.5, float(band) / float(bands))
		var r1: float = lerpf(0.72, 0.5, float(band + 1) / float(bands))
		_drum(pen, at, y0, y1, r0, r1, skin.lighthouse_band if band == 3 else skin.lighthouse, 8, false)
	_drum(pen, at, TOWER_H, TOWER_H + 0.08, 0.66, 0.66, skin.lighthouse_band.darkened(0.2), 10)
	for post: int in 10:
		var angle: float = TAU * float(post) / 10.0
		var p: Vector2 = at + Vector2(cos(angle), sin(angle)) * 0.62
		pen.box(Vector3(p.x - 0.018, TOWER_H + 0.08, p.y - 0.018), Vector3(p.x + 0.018, TOWER_H + 0.3, p.y + 0.018), skin.lighthouse_band)
	_drum(pen, at, TOWER_H + 0.28, TOWER_H + 0.31, 0.64, 0.64, skin.lighthouse_band, 10, false)
	_drum(windows, at, TOWER_H + 0.08, TOWER_H + 0.72, 0.36, 0.36, skin.window, 8)
	_drum(pen, at, TOWER_H + 0.72, TOWER_H + 0.8, 0.42, 0.42, skin.lighthouse_band, 8)
	_drum(pen, at, TOWER_H + 0.8, TOWER_H + 1.08, 0.42, 0.04, skin.lighthouse_band, 8)
	pen.box(Vector3(at.x - 0.015, TOWER_H + 1.05, at.y - 0.015), Vector3(at.x + 0.015, TOWER_H + 1.3, at.y + 0.015), skin.lighthouse_band)
	# A door and two little windows up the tower, facing the café.
	var toward: Vector2 = (Vector2(lot.get_center().x, lot.position.y) - at).normalized()
	for level: float in [0.22, 1.5, 2.6]:
		var p: Vector2 = at + toward * (lerpf(0.72, 0.5, (level - 0.22) / (TOWER_H - 0.22)) + 0.01)
		var tall: float = 0.55 if level < 0.5 else 0.26
		var wide: float = 0.15 if level < 0.5 else 0.1
		var side: Vector2 = toward.orthogonal() * wide
		var colour: Color = skin.lighthouse_band if level < 0.5 else skin.window
		var target: NeighbourhoodBuildings.Pen = pen if level < 0.5 else windows
		target.quad(_v3(p - side, level), _v3(p + side, level), _v3(p + side, level + tall), _v3(p - side, level + tall), Vector3(toward.x, 0.0, toward.y), colour)
	_add_light(_lamp, 2.2)
	_shade_disc(shadows, at + light_shift * TOWER_H * 0.5, 0.75, 0.2)
	var push: Vector2 = light_shift * TOWER_H
	var cast: Array[Vector2] = [at + toward.orthogonal() * 0.6, at - toward.orthogonal() * 0.6,
		at - toward.orthogonal() * 0.45 + push, at + toward.orthogonal() * 0.45 + push]
	shadows.flat(cast, SHADOW_Y, Color(0.08, 0.1, 0.05, 0.22))
	# The keeper's cottage: white walls, a slate roof, a chimney, windows that light at night.
	var cottage: Vector2 = at + Vector2(-2.6, 3.4)
	var basis: Basis = Basis(Vector3.UP, 0.35)
	pen.xf = Transform3D(basis, _v3(cottage, 0.0))
	windows.xf = pen.xf
	var hw: float = 1.3
	var hd: float = 0.75
	var wall: float = 1.05
	pen.box(Vector3(-hw, FLOOR_Y, -hd), Vector3(hw, wall, hd), skin.lighthouse)
	pen.box(Vector3(-hw - 0.02, FLOOR_Y, -hd - 0.02), Vector3(hw + 0.02, 0.12, hd + 0.02), skin.stone_light)
	var ridge: float = wall + 0.62
	for side: float in [-1.0, 1.0]:
		pen.quad(Vector3(-hw - 0.08, wall - 0.05, side * (hd + 0.1)), Vector3(hw + 0.08, wall - 0.05, side * (hd + 0.1)),
			Vector3(hw + 0.08, ridge, 0.0), Vector3(-hw - 0.08, ridge, 0.0), Vector3(0.0, 1.0, side), skin.slate)
	for end: float in [-1.0, 1.0]:
		pen.tri(Vector3(end * hw, wall, -hd), Vector3(end * hw, wall, hd), Vector3(end * hw, ridge - 0.05, 0.0), Vector3(end, 0.0, 0.0), skin.lighthouse)
	pen.box(Vector3(hw - 0.45, ridge - 0.3, -0.12), Vector3(hw - 0.2, ridge + 0.25, 0.12), skin.stone_light)
	pen.box(Vector3(-0.17, FLOOR_Y, hd), Vector3(0.17, 0.62, hd + 0.02), skin.lighthouse_band.lightened(0.15))
	for x: float in [-0.75, 0.75]:
		windows.box(Vector3(x - 0.17, 0.42, hd), Vector3(x + 0.17, 0.72, hd + 0.02), skin.window)
		pen.box(Vector3(x - 0.2, 0.39, hd), Vector3(x + 0.2, 0.42, hd + 0.05), skin.stone_light)
		_add_light(Vector3(cottage.x, 0.0, cottage.y) + basis * Vector3(x, 0.57, hd + 0.06), 0.55)
	pen.xf = Transform3D.IDENTITY
	windows.xf = Transform3D.IDENTITY
	var corners: Array[Vector2] = []
	for corner: Vector3 in [Vector3(-hw, 0.0, -hd), Vector3(hw, 0.0, -hd), Vector3(hw, 0.0, hd), Vector3(-hw, 0.0, hd)]:
		var p: Vector3 = basis * corner
		corners.append(cottage + Vector2(p.x, p.z))
	var hull_points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in corners:
		hull_points.append(point)
		hull_points.append(point + light_shift * 1.3)
	var hull: PackedVector2Array = Geometry2D.convex_hull(hull_points)
	var outline: Array[Vector2] = []
	for index: int in hull.size() - 1:
		outline.append(hull[index])
	shadows.star(cottage + light_shift * 0.65, outline, SHADOW_Y, Color(0.08, 0.1, 0.05, 0.26))


func _add_light(at: Vector3, size: float) -> void:
	_lights.append(at)
	_light_sizes.append(size)


## A soft pool of lamplight on the grass (drawn additively, at night only).
func _pool(at: Vector2, radius: float, strength: float) -> void:
	var rings: int = 5
	var sides: int = 14
	var y: float = SHADOW_Y + 0.004
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		for ring: int in rings:
			var r0: float = float(ring) / float(rings)
			var r1: float = float(ring + 1) / float(rings)
			var c0: Color = Color(skin.lamp_glow, pow(1.0 - r0, 1.6) * strength)
			var c1: Color = Color(skin.lamp_glow, pow(1.0 - r1, 1.6) * strength)
			var p: Array[Vector3] = [Vector3(at.x + cos(a0) * radius * r0, y, at.y + sin(a0) * radius * r0),
				Vector3(at.x + cos(a1) * radius * r0, y, at.y + sin(a1) * radius * r0),
				Vector3(at.x + cos(a1) * radius * r1, y, at.y + sin(a1) * radius * r1),
				Vector3(at.x + cos(a0) * radius * r1, y, at.y + sin(a0) * radius * r1)]
			var colours: Array[Color] = [c0, c0, c1, c1]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				_pool_soup.positions.append(p[corner])
				_pool_soup.normals.append(Vector3.UP)
				_pool_soup.colors.append(colours[corner])


## A lantern on a short post: an iron cage round a glass that glows at night.
func _lantern_post(pen: NeighbourhoodBuildings.Pen, windows: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2, height: float) -> void:
	pen.box(Vector3(at.x - 0.035, FLOOR_Y, at.y - 0.035), Vector3(at.x + 0.035, height, at.y + 0.035), skin.timber_dark)
	pen.box(Vector3(at.x - 0.075, height, at.y - 0.075), Vector3(at.x + 0.075, height + 0.025, at.y + 0.075), skin.rock_dark)
	windows.box(Vector3(at.x - 0.055, height + 0.025, at.y - 0.055), Vector3(at.x + 0.055, height + 0.17, at.y + 0.055), skin.window)
	for corner: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var c: Vector2 = at + corner * 0.06
		pen.box(Vector3(c.x - 0.012, height + 0.025, c.y - 0.012), Vector3(c.x + 0.012, height + 0.17, c.y + 0.012), skin.rock_dark)
	_drum(pen, at, height + 0.17, height + 0.25, 0.09, 0.02, skin.rock_dark, 4)
	_add_light(Vector3(at.x, height + 0.1, at.y), 0.75)
	_pool(at, 1.3, 0.3)
	_shade_disc(shadows, at + light_shift * height * 0.5, 0.06, 0.22)


## Lanterns where the path leaves the café, at the stile and by the bench.
func _lanterns(pen: NeighbourhoodBuildings.Pen, windows: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var spots: Array[Vector2] = []
	var start: int = mini(9, path_points.size() - 2)
	var along: Vector2 = (path_points[start + 1] - path_points[start - 1]).normalized() if start > 0 else Vector2(0.0, 1.0)
	for side: float in [-1.0, 1.0]:
		spots.append(path_points[start] + along.orthogonal() * side * (PATH_HALF + 0.35))
	spots.append(stile + Vector2(0.75, 0.4))
	for at: Vector2 in spots:
		if _is_blocked(at, 0.1) or coast.signed(at) > -0.6:
			continue
		_lantern_post(pen, windows, shadows, at, 0.62)


## Festoon lights strung from tall posts along the rail behind and beside the café.
func _festoon(pen: NeighbourhoodBuildings.Pen, windows: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var poles: Array[Vector2] = []
	for index: int in rail_points.size():
		var p: Vector2 = rail_points[index]
		var near: Vector2 = Vector2(clampf(p.x, lot.position.x, lot.end.x), clampf(p.y, lot.position.y, lot.end.y))
		if p.distance_to(near) < 3.2 and index % 3 == 0:
			poles.append(p + _inland_of(p) * 0.12)
	var top: float = 1.32
	for index: int in poles.size():
		var p: Vector2 = poles[index]
		pen.box(Vector3(p.x - 0.03, FLOOR_Y, p.y - 0.03), Vector3(p.x + 0.03, top + 0.05, p.y + 0.03), skin.timber_dark)
		_shade_disc(shadows, p + light_shift * top * 0.5, 0.05, 0.18)
		if index + 1 >= poles.size() or poles[index + 1].distance_to(p) > 4.2:
			continue
		var a: Vector3 = _v3(p, top)
		var b: Vector3 = _v3(poles[index + 1], top)
		var segments: int = maxi(4, roundi(a.distance_to(b) / 0.28))
		var sag: float = minf(0.24, a.distance_to(b) * 0.07)
		var previous: Vector3 = a
		for step: int in range(1, segments + 1):
			var t: float = float(step) / float(segments)
			var q: Vector3 = a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
			var side: Vector3 = (q - previous).cross(Vector3.UP).normalized() * 0.007
			pen.quad(previous - side, q - side, q + side + Vector3.UP * 0.008, previous + side + Vector3.UP * 0.008, Vector3.UP, skin.rock_dark)
			if step < segments and step % 2 == 1:
				var bulb: Vector3 = q - Vector3.UP * 0.04
				windows.box(bulb - Vector3(0.02, 0.028, 0.02), bulb + Vector3(0.02, 0.028, 0.02), skin.window)
				_add_light(bulb, 0.32)
			previous = q
		_pool((p + poles[index + 1]) * 0.5, 1.4, 0.16)


## The small car park at the end of the lane, far off: gravel, a few parked cars, a bus
## stop and a lamp, with the lane running away inland.
func _car_park(ground: NeighbourhoodBuildings.Pen, props: NeighbourhoodBuildings.Pen, windows: NeighbourhoodBuildings.Pen,
		shadows: NeighbourhoodGround.Soup) -> void:
	var rect: Rect2 = car_park
	var lane: PackedVector2Array = lane_points
	_ribbon(ground, lane, 1.05, PATH_EDGE_Y, skin.tarmac.darkened(0.1), 0.03)
	_ribbon(ground, lane, 0.95, PATH_Y, skin.tarmac, 0.02)
	ground.flat(rect.position.x - 0.12, rect.position.y - 0.12, rect.end.x + 0.12, rect.end.y + 0.12, PATH_EDGE_Y, skin.gravel_dark)
	ground.flat(rect.position.x, rect.position.y, rect.end.x, rect.end.y, PATH_Y, skin.gravel)
	# Parking lines of timber sleepers along the back.
	for bay: int in 4:
		var x: float = rect.position.x + 0.6 + float(bay) * 1.85
		props.box(Vector3(x - 0.05, FLOOR_Y, rect.position.y + 0.15), Vector3(x + 0.05, 0.05, rect.position.y + 1.6), skin.timber_dark)
	for car: int in skin.cars:
		var bay: int = [0, 2, 3, 1, 4, 5][car % 6]
		var x: float = rect.position.x + 1.52 + float(bay) * 1.85
		_car(props, windows, shadows, Vector2(x, rect.position.y + 1.1 + 0.15 * _r(car, 261)), skin.car_colors[car % skin.car_colors.size()], car)
	# The bus stop by the lane, and a lamp at the path's end.
	var stop: Vector2 = rect.position + Vector2(-2.6, rect.size.y * 0.7 - 1.5)
	props.box(Vector3(stop.x - 0.03, FLOOR_Y, stop.y - 0.03), Vector3(stop.x + 0.03, 1.15, stop.y + 0.03), skin.rail.darkened(0.2))
	props.xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(stop.x, 1.0, stop.y))
	props.disc(0.0, 0.0, 0.17, -0.02, 0.02, skin.bus_sign)
	props.xf = Transform3D.IDENTITY
	props.box(Vector3(stop.x - 0.12, 0.55, stop.y - 0.02), Vector3(stop.x + 0.12, 0.8, stop.y + 0.05), skin.rail_post)
	_shade_disc(shadows, stop + light_shift * 0.6, 0.06, 0.2)
	var lamp: Vector2 = rect.end - Vector2(0.4, 0.3)
	props.box(Vector3(lamp.x - 0.035, FLOOR_Y, lamp.y - 0.035), Vector3(lamp.x + 0.035, 1.3, lamp.y + 0.035), skin.rail.darkened(0.3))
	props.box(Vector3(lamp.x - 0.035, 1.27, lamp.y - 0.035), Vector3(lamp.x + 0.035, 1.3, lamp.y + 0.3), skin.rail.darkened(0.3))
	windows.box(Vector3(lamp.x - 0.07, 1.19, lamp.y + 0.2), Vector3(lamp.x + 0.07, 1.27, lamp.y + 0.34), skin.window)
	_add_light(Vector3(lamp.x, 1.2, lamp.y + 0.27), 0.8)


## A parked car: a low body, a cabin with glass, four wheels.
func _car(pen: NeighbourhoodBuildings.Pen, windows: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2, colour: Color, index: int) -> void:
	var basis: Basis = Basis(Vector3.UP, (_r(index, 262) - 0.5) * 0.12)
	pen.xf = Transform3D(basis, _v3(at, 0.0))
	windows.xf = pen.xf
	pen.box(Vector3(-0.42, 0.12, -0.78), Vector3(0.42, 0.42, 0.78), colour)
	pen.box(Vector3(-0.36, 0.42, -0.38), Vector3(0.36, 0.68, 0.32), colour.lightened(0.05))
	windows.box(Vector3(-0.37, 0.46, -0.39), Vector3(0.37, 0.64, 0.33), skin.window.darkened(0.35))
	pen.box(Vector3(-0.3, 0.68, -0.32), Vector3(0.3, 0.7, 0.26), colour)
	for wheel: Vector3 in [Vector3(-0.42, 0.13, -0.5), Vector3(0.42, 0.13, -0.5), Vector3(-0.42, 0.13, 0.5), Vector3(0.42, 0.13, 0.5)]:
		pen.box(wheel - Vector3(0.05, 0.13, 0.13), wheel + Vector3(0.05, 0.13, 0.13), skin.tarmac.darkened(0.45))
	pen.box(Vector3(-0.3, 0.26, -0.79), Vector3(0.3, 0.33, -0.775), skin.rail_post)
	pen.xf = Transform3D.IDENTITY
	windows.xf = Transform3D.IDENTITY
	_shade_rect(shadows, Rect2(at - Vector2(0.45, 0.8), Vector2(0.9, 1.6)), 0.55, 0.26)


## Sheep grazing in the fields inland, west of the field wall.
func _sheep(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var field: Vector2 = Vector2(lot.position.x - 18.5, lot.get_center().y + 2.0)
	var placed: int = 0
	for tries: int in skin.sheep * 6:
		if placed >= skin.sheep:
			break
		var at: Vector2 = field + Vector2((_r(tries, 271) - 0.5) * 9.0, (_r(tries, 272) - 0.5) * 9.0)
		if not _free_land(at, 0.4, 1.5):
			continue
		placed += 1
		var heading: float = _r(tries, 273) * TAU
		pen.xf = Transform3D(Basis(Vector3.UP, heading), _v3(at, 0.0))
		pen.lump(Vector3(0.0, 0.26, 0.0), 0.22, 0.15, 0.3, 0.0, skin.fleece, skin.fleece.darkened(0.15))
		pen.lump(Vector3(0.0, 0.33, 0.04), 0.16, 0.08, 0.2, 0.4, skin.fleece.lightened(0.04), skin.fleece)
		pen.box(Vector3(-0.055, 0.22, 0.27), Vector3(0.055, 0.36, 0.42), skin.sheep_face)
		for leg: Vector3 in [Vector3(-0.1, 0.0, -0.16), Vector3(0.1, 0.0, -0.16), Vector3(-0.1, 0.0, 0.16), Vector3(0.1, 0.0, 0.16)]:
			pen.box(leg + Vector3(-0.025, FLOOR_Y, -0.025), leg + Vector3(0.025, 0.16, 0.025), skin.sheep_face)
		pen.xf = Transform3D.IDENTITY
		_shade_disc(shadows, at + light_shift * 0.3, 0.3, 0.22)


# --- shadows on the top --------------------------------------------------------------

func _shade_line(shadows: NeighbourhoodGround.Soup, a: Vector2, b: Vector2, half: float, height: float, alpha: float) -> void:
	var push: Vector2 = light_shift * height
	var along: Vector2 = (b - a).normalized()
	var normal: Vector2 = Vector2(-along.y, along.x) * half
	var corners: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in [a - normal, b - normal, b + normal, a + normal]:
		corners.append(point)
		corners.append(point + push)
	var hull: PackedVector2Array = Geometry2D.convex_hull(corners)
	var ring: Array[Vector2] = []
	for index: int in hull.size() - 1:
		ring.append(hull[index])
	shadows.star((a + b) * 0.5 + push * 0.5, ring, SHADOW_Y, Color(0.08, 0.1, 0.05, alpha))


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


## One quad per light, all four corners at its centre; the glow shader spreads them.
func _sprites(points: Array[Vector3], sizes: Array[float]) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var uv2s: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colours: PackedColorArray = PackedColorArray()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for index: int in points.size():
		for corner: Vector2 in corners:
			vertices.append(points[index])
			normals.append(Vector3.UP)
			uvs.append(corner)
			uv2s.append(Vector2(sizes[index], float(index) * 0.618 + 0.13))
			colours.append(skin.lamp_glow)
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


# --- life: the beam, gulls and the boat ---------------------------------------------------

## The lighthouse beam: two long faint fans either side of the lamp, turned by the clock.
func _build_beam() -> void:
	var fan: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var spread: float = deg_to_rad(4.5)
	var steps: int = 5
	for direction: float in [1.0, -1.0]:
		for step: int in steps:
			var near: float = 0.4 + BEAM_LENGTH * float(step) / float(steps)
			var far: float = 0.4 + BEAM_LENGTH * float(step + 1) / float(steps)
			var fade0: float = 1.0 - float(step) / float(steps)
			var fade1: float = 1.0 - float(step + 1) / float(steps)
			var a: Vector3 = Vector3(sin(-spread) * near, 0.0, -cos(spread) * near * direction)
			var b: Vector3 = Vector3(sin(spread) * near, 0.0, -cos(spread) * near * direction)
			var c: Vector3 = Vector3(sin(spread) * far, 0.0, -cos(spread) * far * direction)
			var d: Vector3 = Vector3(sin(-spread) * far, 0.0, -cos(spread) * far * direction)
			for point: Vector3 in [a, b, c, a, c, d]:
				fan.positions.append(point)
				fan.normals.append(Vector3.UP)
				fan.colors.append(Color(1.0, 1.0, 1.0, fade0 if point == a or point == b else fade1))
	beam = _instance("LighthouseBeam", fan.to_mesh(), _beam_material)
	_add(beam)


func _build_gulls() -> void:
	gulls.clear()
	_gull_wings.clear()
	_gull_paths.clear()
	var points: PackedVector2Array = coast.points
	var near: Array[int] = []
	for index: int in points.size():
		if points[index].distance_to(lot.get_center()) < 15.0:
			near.append(index)
	if near.is_empty():
		return
	for index: int in skin.gulls:
		var body: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		body.lump(Vector3.ZERO, 0.06, 0.05, 0.16, 0.0, skin.gull_body, skin.gull_body.darkened(0.08))
		body.lump(Vector3(0.0, 0.04, 0.14), 0.045, 0.04, 0.05, 0.3, skin.gull_body, skin.gull_body)
		body.box(Vector3(-0.012, 0.03, 0.18), Vector3(0.012, 0.045, 0.23), skin.gorse_bloom.darkened(0.15))
		body.tri(Vector3(-0.05, 0.0, -0.12), Vector3(0.05, 0.0, -0.12), Vector3(0.0, 0.01, -0.24), Vector3.UP, skin.gull_wing)
		var node: MeshInstance3D = _instance("Gull%d" % index, body.soup.to_mesh(), _material)
		var wings: Array[MeshInstance3D] = []
		for side: float in [-1.0, 1.0]:
			var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
			var half: float = 0.42
			pen.quad(Vector3(0.0, 0.0, 0.07), Vector3(side * half * 0.55, 0.03, 0.06), Vector3(side * half * 0.55, 0.03, -0.06),
				Vector3(0.0, 0.0, -0.06), Vector3.UP, skin.gull_wing)
			pen.tri(Vector3(side * half * 0.55, 0.03, 0.06), Vector3(side * half, 0.0, -0.08), Vector3(side * half * 0.55, 0.03, -0.06), Vector3.UP, skin.gull_tip)
			var wing: MeshInstance3D = _instance("WingL" if side < 0.0 else "WingR", pen.soup.to_mesh(), _material)
			wing.position = Vector3(0.0, 0.03, 0.02)
			node.add_child(wing)
			wings.append(wing)
		_add(node)
		gulls.append(node)
		_gull_wings.append(wings)
		# Each glides round its own loose loop over the drop, level with the top.
		var spot: int = near[int(_r(index, 281) * float(near.size()) * 0.999)]
		var centre: Vector2 = points[spot] + _coast_normals[spot] * (4.2 + 4.5 * _r(index, 282))
		_gull_paths.append({"centre": centre, "rx": 2.4 + 2.2 * _r(index, 283), "rz": 1.6 + 1.6 * _r(index, 284),
			"rate": (0.16 + 0.1 * _r(index, 285)) * (1.0 if _r(index, 286) < 0.55 else -1.0), "phase": _r(index, 287) * TAU,
			"height": -0.6 + 2.6 * _r(index, 288)})


## A gull's place (local), heading, bank and wing lift at `seconds`: it rides the updraft
## round its loop on still wings, and now and then gives a few beats.
func gull_pose(index: int, seconds: float) -> Dictionary:
	var path: Dictionary = _gull_paths[index]
	var rate: float = float(path["rate"])
	var angle: float = seconds * rate + float(path["phase"])
	var centre: Vector2 = path["centre"]
	var rx: float = float(path["rx"])
	var rz: float = float(path["rz"])
	var drift: Vector2 = Vector2(sin(seconds * 0.05 + float(index)) * 1.2, cos(seconds * 0.04 + float(index) * 2.0) * 0.8)
	var at: Vector2 = centre + drift + Vector2(cos(angle) * rx, sin(angle) * rz)
	var velocity: Vector2 = Vector2(-sin(angle) * rx, cos(angle) * rz) * rate
	var burst: float = smoothstep(0.75, 0.92, sin(seconds * 0.31 + float(index) * 1.9))
	return {"u": at.x, "z": at.y, "y": float(path["height"]) + 0.35 * sin(seconds * 0.27 + float(index)),
		"heading": atan2(velocity.x, velocity.y), "bank": -0.3 * signf(rate),
		"wing": 0.06 + burst * 0.55 * sin(seconds * 9.0 + float(index))}


## The fishing boat working the bay below: a red hull, a wheelhouse, a mast with a lamp
## and a short white wake.
func _build_boat() -> void:
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var deck: Array[Vector3] = [Vector3(-0.8, 0.2, -0.32), Vector3(0.55, 0.2, -0.32), Vector3(1.1, 0.24, 0.0),
		Vector3(0.55, 0.2, 0.32), Vector3(-0.8, 0.2, 0.32)]
	var keel: Array[Vector3] = [Vector3(-0.72, -0.08, -0.22), Vector3(0.5, -0.08, -0.2), Vector3(0.95, 0.0, 0.0),
		Vector3(0.5, -0.08, 0.2), Vector3(-0.72, -0.08, 0.22)]
	for side: int in 5:
		var next: int = (side + 1) % 5
		var middle: Vector3 = (deck[side] + deck[next]) * 0.5
		pen.quad(keel[side], keel[next], deck[next], deck[side], Vector3(middle.x, 0.0, middle.z), skin.hull)
	pen.tri(deck[0], deck[1], deck[4], Vector3.UP, skin.boat_trim)
	pen.tri(deck[1], deck[3], deck[4], Vector3.UP, skin.boat_trim)
	pen.tri(deck[1], deck[2], deck[3], Vector3.UP, skin.boat_trim)
	for side: int in 5:
		var next: int = (side + 1) % 5
		var a: Vector3 = deck[side]
		var b: Vector3 = deck[next]
		pen.quad(a, b, b + Vector3.UP * 0.06, a + Vector3.UP * 0.06, Vector3((a.x + b.x) * 0.5, 0.0, (a.z + b.z) * 0.5), skin.boat_trim.darkened(0.1))
	pen.box(Vector3(-0.15, 0.2, -0.22), Vector3(0.3, 0.62, 0.22), skin.wheelhouse)
	pen.box(Vector3(-0.2, 0.62, -0.26), Vector3(0.35, 0.67, 0.26), skin.hull.darkened(0.1))
	pen.box(Vector3(0.3, 0.4, -0.16), Vector3(0.31, 0.55, 0.16), skin.window.darkened(0.3))
	pen.box(Vector3(-0.62, 0.2, -0.025), Vector3(-0.57, 1.25, 0.025), skin.timber_dark)
	pen.box(Vector3(-0.85, 0.85, -0.02), Vector3(-0.25, 0.88, 0.02), skin.timber_dark)
	pen.box(Vector3(-0.7, 0.2, -0.18), Vector3(-0.42, 0.3, 0.18), skin.buoy_a)
	# The wake: a short white V behind it.
	for side: float in [-1.0, 1.0]:
		pen.quad(Vector3(-0.75, 0.005, side * 0.2), Vector3(-2.4, 0.005, side * 0.75), Vector3(-2.4, 0.005, side * 0.62),
			Vector3(-0.75, 0.005, side * 0.12), Vector3.UP, skin.foam)
	boat = _instance("FishingBoat", pen.soup.to_mesh(), _material)
	_add(boat)
	_boat_lamp = _instance("Lamp", _sprites([Vector3(-0.6, 1.28, 0.0)], [0.9]), _boat_glow)
	_boat_lamp.extra_cull_margin = 1.0
	boat.add_child(_boat_lamp)
	var points: PackedVector2Array = coast.points
	var best: int = 0
	var target: Vector2 = Vector2(lot.get_center().x - 7.0, lot.position.y)
	for index: int in points.size():
		if points[index].distance_to(target) < points[best].distance_to(target):
			best = index
	var along: Vector2 = -_coast_normals[best].orthogonal()
	_boat_path = {"centre": _feet[best] + _coast_normals[best] * 13.0, "along": along, "span": 7.0, "rate": 0.035, "phase": 0.6}


## The boat's place (local u, z), heading and bob at `seconds`: it works slowly back and
## forth along the bay and comes about at each end.
func boat_pose(seconds: float) -> Dictionary:
	var angle: float = seconds * float(_boat_path["rate"]) + float(_boat_path["phase"])
	var along: Vector2 = _boat_path["along"]
	var centre: Vector2 = _boat_path["centre"]
	var at: Vector2 = centre + along * float(_boat_path["span"]) * sin(angle) + along.orthogonal() * 0.8 * sin(angle * 0.5)
	# The bow (+x) points along its way, swinging round as it comes about.
	var heading: float = atan2(-along.y, along.x) + PI * (1.0 - smoothstep(-0.25, 0.25, cos(angle)))
	return {"u": at.x, "z": at.y, "heading": heading, "bob": 0.03 * sin(seconds * 1.2), "roll": 0.05 * sin(seconds * 1.05),
		"pitch": 0.04 * sin(seconds * 0.85 + 1.0)}


# --- motion and time of day -------------------------------------------------------

## 0 by day, 1 from dusk; `late` rises after the shop closes.
func set_night(level: float, late: float) -> void:
	_night = level
	_late = late
	_apply_night()


func is_lit() -> bool:
	return _night > 0.01


func _apply_night() -> void:
	if root == null:
		return
	_glow_material.set_shader_parameter(&"level", _night)
	_boat_glow.set_shader_parameter(&"level", _night)
	_glass_material.emission_energy_multiplier = _night * 2.2
	_pool_material.albedo_color = Color(1.0, 1.0, 1.0, _night)
	_pools.visible = _night > 0.05
	_glass_material.albedo_color = Color.WHITE
	_beam_material.albedo_color = Color(skin.lamp_glow, 0.2 * _night)
	beam.visible = _night > 0.01
	_boat_lamp.visible = _night > 0.01
	for gull: Node3D in gulls:
		gull.visible = _late < NIGHT_HIDE
	sea_material.set_shader_parameter(&"dusk", _night * (1.0 - _late))
	sea_material.set_shader_parameter(&"moon", _night * _late)
	_applied_at = -1.0
	apply(_seconds)


## Moves everything to the street clock's `seconds`; skipped when nothing changed.
func apply(seconds: float) -> void:
	_seconds = seconds
	if root == null or is_equal_approx(seconds, _applied_at):
		return
	_applied_at = seconds
	sea_material.set_shader_parameter(&"sea_time", seconds)
	_glow_material.set_shader_parameter(&"glow_time", seconds)
	_boat_glow.set_shader_parameter(&"glow_time", seconds)
	var pose: Dictionary = boat_pose(seconds)
	var at: Vector2 = Vector2(float(pose["u"]), float(pose["z"]))
	var basis: Basis = Basis(Vector3.UP, float(pose["heading"])) * Basis(Vector3.RIGHT, float(pose["roll"])) * Basis(Vector3.BACK, float(pose["pitch"]))
	boat.transform = Transform3D(basis, Vector3(at.x, sea_y() + 0.02 + float(pose["bob"]), at.y))
	var lights: PackedVector4Array = PackedVector4Array([
		Vector4((_lamp_on_sea.x + _lamp_on_sea.y) * SEA_SCALE, -waterline.signed(_lamp_on_sea) * SEA_SCALE, 0.8 * _night, 0.0),
		Vector4((at.x + at.y) * SEA_SCALE, (-waterline.signed(at) + 0.6) * SEA_SCALE, 0.45 * _night, 0.0), Vector4.ZERO, Vector4.ZERO])
	sea_material.set_shader_parameter(&"lights", lights)
	beam.transform = Transform3D(Basis(Vector3.UP, seconds * BEAM_TURN), _lamp)
	for index: int in gulls.size():
		var gull: Dictionary = gull_pose(index, seconds)
		var turn: Basis = (Basis(Vector3.UP, float(gull["heading"])) * Basis(Vector3.BACK, float(gull["bank"]))).scaled(Vector3.ONE * GULL_SCALE)
		gulls[index].transform = Transform3D(turn, Vector3(float(gull["u"]), float(gull["y"]), float(gull["z"])))
		var wings: Array = _gull_wings[index]
		(wings[0] as MeshInstance3D).rotation = Vector3(0.0, 0.0, -float(gull["wing"]))
		(wings[1] as MeshInstance3D).rotation = Vector3(0.0, 0.0, float(gull["wing"]))


## What the cliff shows now, for tests and captures.
func capture_state() -> Dictionary:
	return {"drop": skin.drop, "coast_points": coast.points.size(), "rail_posts": rail_points.size(), "gulls": gulls.size(),
		"stacks": stacks.size(), "beam": beam != null and beam.visible, "night": _night, "late": _late}
