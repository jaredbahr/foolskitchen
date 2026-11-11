class_name NeighbourhoodGround
extends RefCounted
## The ground the neighbourhood stands on (#421) and the deliberate edge of the
## world (#424). View-only: flat-shaded vertex-coloured meshes, no colliders,
## lights, shadows, simulation state or random draws. Everything that varies
## comes from an integer hash of its own position, so a rebuild is identical.
##
## Geometry is authored in the street's local frame (u along the street, z
## outward from the shop), then the owner parents it under that frame. The world
## is a square of WORLD_HALF metres either side of the maximum lot's centre,
## walled by a tree line; the camera rig is told the same square and never pans
## or zooms past it.

## Half the side of the dressed world square, in metres.
const WORLD_HALF: float = 46.0
## Dark forest floor that carries on past the tree line, never reachable.
const BEYOND: float = 16.0
## Flat layers sit 7 mm or more apart so none z-fights at full zoom-out, and all
## stay under the road (top 0) and shop floor.
const BASE_Y: float = -0.062
const GRASS_Y: float = -0.054
const PATCH_Y: float = -0.046
const LAWN_Y: float = -0.038
const LANE_Y: float = -0.030
const SHADOW_Y: float = -0.022
const PLANT_Y: float = -0.032
const BLOCK_V: float = 8.105

## One accumulating vertex-coloured triangle soup, turned into a single mesh.
class Soup extends RefCounted:
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()

	func add(template: Array, xf: Transform3D, colour: Color) -> void:
		var pos: PackedVector3Array = template[0]
		var nrm: PackedVector3Array = template[1]
		positions.append_array(xf * pos)
		normals.append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * nrm)
		var tint: PackedColorArray = PackedColorArray()
		tint.resize(pos.size())
		tint.fill(colour)
		colors.append_array(tint)

	## One triangle with a flat normal; `hint` is any vector on its outer side.
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

	## A flat convex polygon facing up, fanned from its first vertex.
	func flat(points: Array[Vector2], y: float, colour: Color) -> void:
		for index: int in range(1, points.size() - 1):
			tri(Vector3(points[0].x, y, points[0].y), Vector3(points[index].x, y, points[index].y),
				Vector3(points[index + 1].x, y, points[index + 1].y), Vector3.UP, colour)

	## A star-shaped polygon facing up, fanned from `centre`.
	func star(centre: Vector2, points: Array[Vector2], y: float, colour: Color) -> void:
		for index: int in points.size():
			var next: Vector2 = points[(index + 1) % points.size()]
			tri(Vector3(centre.x, y, centre.y), Vector3(points[index].x, y, points[index].y),
				Vector3(next.x, y, next.y), Vector3.UP, colour)

	func is_empty() -> bool:
		return positions.is_empty()

	func to_mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static var _templates: Dictionary[String, Array] = {}

## Street-frame inputs, set by the owner before build().
var local_reserve: AABB = AABB()
var shift: float = 0.0
var world_centre: Vector2 = Vector2.ZERO
var buildings: Array[AABB] = []
## The street's look; null means the standard meadow.
var skin: GroundSkin

var _soup: Soup = Soup.new()
var _shadows: Soup = Soup.new()
var _blocked: Array[Rect2] = []
var _lane_v: float = 0.0
var _grass: Color
var _patch_light: Color
var _patch_dark: Color
var _lawn: Color
var _forest: Color
var _lane: Color
var _lane_edge: Color
var _shade: Color


## The world square on the XZ plane for a maximum lot (cells).
static func world_rect(maximum_lot: Rect2i) -> Rect2:
	var centre: Vector2 = (Vector2(maximum_lot.position) + Vector2(maximum_lot.size) * 0.5) * GridMath.CELL_SIZE
	return Rect2(centre - Vector2.ONE * WORLD_HALF, Vector2.ONE * WORLD_HALF * 2.0)


## Deterministic 0..1 value for an integer pair and a salt.
static func hash01(a: int, b: int, salt: int) -> float:
	var x: int = (a * 73856093) ^ (b * 19349663) ^ (salt * 83492791)
	x = x & 0x7fffffff
	x = ((x >> 13) ^ x) & 0x7fffffff
	x = (x * 1274126177) & 0x7fffffff
	x = ((x >> 16) ^ x) & 0x7fffffff
	return float(x & 0xffff) / 65535.0


## Builds the meshes (all in the street frame). Returns the nodes to add.
func build() -> Array[MeshInstance3D]:
	_palette()
	_soup = Soup.new()
	_shadows = Soup.new()
	_blocked.clear()
	var half: float = WORLD_HALF
	var base: Soup = Soup.new()
	# Forest floor under and past the tree line, then the bright meadow on it.
	var outer: float = half + BEYOND
	base.flat(_rect_points(Rect2(world_centre - Vector2.ONE * outer, Vector2.ONE * outer * 2.0), 0.0), BASE_Y, _forest)
	base.flat(_rect_points(Rect2(world_centre - Vector2.ONE * (half - 1.0), Vector2.ONE * (half - 1.0) * 2.0), 6.0), GRASS_Y, _grass)
	_plan_exclusions()
	_patches(base)
	_lawn_and_lane(base)
	_hedges()
	_scatter()
	_forest_edge()
	var nodes: Array[MeshInstance3D] = []
	nodes.append(_node("Meadow", base))
	nodes.append(_node("Planting", _soup))
	nodes.append(_node("ContactShadows", _shadows))
	return nodes


func _palette() -> void:
	if skin == null:
		skin = GroundSkin.standard()
	_grass = skin.grass
	_patch_light = skin.patch_light
	_patch_dark = skin.patch_dark
	_lawn = skin.lawn
	_forest = skin.forest
	_lane = skin.lane
	_lane_edge = skin.lane_edge
	_shade = _grass.darkened(0.30)


## Foliage: a richer green than the meadow, varying tree to tree.
func _leaf(tone: float) -> Color:
	return skin.leaf_dark.lerp(skin.leaf_light, tone * 0.55)


func _node(label: String, soup: Soup) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = label
	if not soup.is_empty():
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.metallic_specular = 0.0
		# Flat-shaded triangles own their vertices, so per-vertex light looks the same
		# and is far cheaper to fill across a full screen of ground.
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		material.disable_receive_shadows = true
		instance.mesh = soup.to_mesh()
		instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Local rectangles (u, z) nothing may be planted on.
func _plan_exclusions() -> void:
	var lot: Rect2 = Rect2(local_reserve.position.x, local_reserve.position.z,
		local_reserve.size.x, shift - local_reserve.position.z)
	_blocked.append(lot.grow(0.4))
	for box: AABB in buildings:
		_blocked.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(0.35))
	# The street itself, pavements and road, reaches the full width of the world.
	_blocked.append(Rect2(world_centre.x - WORLD_HALF - BEYOND, shift - 0.9,
		(WORLD_HALF + BEYOND) * 2.0, BLOCK_V + 0.9 + 0.45))
	_lane_v = shift - lot.size.y - 3.1
	_blocked.append(Rect2(world_centre.x - WORLD_HALF - BEYOND, _lane_v - 1.0,
		(WORLD_HALF + BEYOND) * 2.0, 2.0))


func _is_blocked(point: Vector2, margin: float) -> bool:
	for rect: Rect2 in _blocked:
		if rect.grow(margin).has_point(point):
			return true
	return false


# --- flat ground detail ---------------------------------------------------

func _patches(base: Soup) -> void:
	var centre: Vector2 = world_centre
	# Patches never overlap, so no two coplanar faces can fight for the pixel.
	var placed: Array[Vector3] = []
	for index: int in 90:
		var angle: float = hash01(index, 1, 11) * TAU
		var radius: float = sqrt(hash01(index, 2, 11)) * (WORLD_HALF - 8.0)
		var at: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
		var size: float = 2.2 + hash01(index, 3, 11) * 4.0
		var clear: bool = true
		for other: Vector3 in placed:
			if at.distance_to(Vector2(other.x, other.y)) < (size + other.z) * 1.12:
				clear = false
				break
		if not clear:
			continue
		placed.append(Vector3(at.x, at.y, size))
		var colour: Color = _patch_light if hash01(index, 4, 11) < 0.55 else _patch_dark
		base.star(at, _blob(at, size, size * (0.65 + hash01(index, 5, 11) * 0.3), hash01(index, 6, 11) * PI, 9), PATCH_Y, colour)


func _lawn_and_lane(base: Soup) -> void:
	var left: float = local_reserve.position.x
	var right: float = local_reserve.end.x
	for box: AABB in buildings:
		if box.position.z + box.size.z * 0.5 < shift:
			left = minf(left, box.position.x)
			right = maxf(right, box.end.x)
	# The shop's own block: mown lawn from the back lane to the pavement.
	var near: Rect2 = Rect2(left - 2.6, _lane_v + 1.15, right - left + 5.2, shift - 0.16 - (_lane_v + 1.15))
	base.flat(_rect_points(near, 1.1), LAWN_Y, _lawn)
	# Across the street: gardens behind the three shopfronts.
	var far_front: float = shift + 8.2
	var far: Rect2 = Rect2(-7.4, far_front, 14.8, 5.8)
	base.flat(_rect_points(far, 1.0), LAWN_Y, _lawn)
	# A grass verge: a deeper strip hugging the pavement's outer edges.
	for edge: Vector2 in [Vector2(shift - 0.52, shift - 0.16), Vector2(shift + BLOCK_V + 0.24, shift + BLOCK_V + 0.52)]:
		var verge: Rect2 = Rect2(world_centre.x - 30.0, edge.x, 60.0, edge.y - edge.x)
		for piece: Rect2 in _split_around(verge):
			base.flat(_rect_points(piece, 0.12), LAWN_Y + 0.004, _patch_dark.lerp(_grass, 0.35))
	# The back lane: warm packed earth with a darker edge, running out to the trees.
	var lane: Rect2 = Rect2(world_centre.x - WORLD_HALF + 0.5, _lane_v - 0.62,
		WORLD_HALF * 2.0 - 1.0, 1.24)
	base.flat(_rect_points(lane, 0.0), LANE_Y, _lane_edge)
	base.flat(_rect_points(lane.grow_individual(0.0, -0.1, 0.0, -0.1), 0.0), LANE_Y + 0.004, _lane)


## The verge skips the shop's own frontage and its neighbours' footprints.
func _split_around(strip: Rect2) -> Array[Rect2]:
	var cuts: Array[Vector2] = [Vector2(local_reserve.position.x - 0.5, local_reserve.end.x + 0.5)]
	for box: AABB in buildings:
		if box.position.z < strip.end.y and box.end.z > strip.position.y:
			cuts.append(Vector2(box.position.x - 0.3, box.end.x + 0.3))
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var pieces: Array[Rect2] = []
	var cursor: float = strip.position.x
	for cut: Vector2 in cuts:
		if cut.x > cursor:
			pieces.append(Rect2(cursor, strip.position.y, cut.x - cursor, strip.size.y))
		cursor = maxf(cursor, cut.y)
	if cursor < strip.end.x:
		pieces.append(Rect2(cursor, strip.position.y, strip.end.x - cursor, strip.size.y))
	return pieces


# --- planting ---------------------------------------------------------------

func _hedges() -> void:
	var span: float = 30.0
	var rows: Array[float] = [shift - 0.34, shift + BLOCK_V + 0.7, _lane_v - 1.18, _lane_v + 1.18 + 0.0]
	for row_index: int in rows.size():
		var z: float = rows[row_index]
		var u: float = world_centre.x - span
		var step: int = 0
		while u < world_centre.x + span:
			var wobble: float = (hash01(step, row_index, 21) - 0.5) * 0.08
			var point: Vector2 = Vector2(u, z + wobble)
			if not _is_blocked_hedge(point, row_index):
				var size: float = 0.40 + hash01(step, row_index, 22) * 0.12
				_bush(point, size, step * 7 + row_index, 0.62, false)
			u += 0.62
			step += 1


## A hedge may stand on the street's edge lines, so only the lot and buildings block it.
func _is_blocked_hedge(point: Vector2, row_index: int) -> bool:
	for index: int in _blocked.size():
		var rect: Rect2 = _blocked[index]
		# Skip the street-wide and lane-wide strips: hedges run along their edges.
		if rect.size.x > WORLD_HALF:
			continue
		if rect.grow(0.15).has_point(point):
			return true
	# Keep the hedge out of the back lane itself.
	if absf(point.y - _lane_v) < 0.78 and row_index < 2:
		return true
	return false


func _scatter() -> void:
	var cell: float = 2.3
	var centre: Vector2 = world_centre
	var steps: int = int(WORLD_HALF * 2.0 / cell)
	for ix: int in steps:
		for iz: int in steps:
			var at: Vector2 = centre - Vector2.ONE * WORLD_HALF + Vector2((float(ix) + hash01(ix, iz, 31)) * cell,
				(float(iz) + hash01(ix, iz, 32)) * cell)
			if _is_blocked(at, 0.2):
				continue
			var reach: float = maxf(absf(at.x - centre.x), absf(at.y - centre.y))
			if reach > WORLD_HALF - 6.5:
				continue
			var dist_lot: float = _distance_to_lot(at)
			var roll: float = hash01(ix, iz, 33)
			var tree_chance: float = clampf((dist_lot - 5.0) / 32.0, 0.0, 1.0) * 0.5 * skin.tree_density
			# The wood thickens toward the edge, so the world ends in forest, not a line.
			tree_chance = maxf(tree_chance, clampf((reach - (WORLD_HALF - 22.0)) / 14.0, 0.0, 1.0) * 0.8)
			if roll < tree_chance and dist_lot > 5.0:
				_tree(at, 0.85 + hash01(ix, iz, 34) * 0.5 + clampf((dist_lot - 14.0) / 60.0, 0.0, 0.3), ix * 131 + iz,
						reach > WORLD_HALF - 18.0)
			elif roll < tree_chance + 0.2 * skin.flower_density and dist_lot > 1.5:
				_bush(at, 0.34 + hash01(ix, iz, 35) * 0.3, ix * 17 + iz, 0.7)
			elif roll < tree_chance + 0.2 * skin.flower_density + 0.32 * skin.flower_density:
				_flowers(at, 2 + int(hash01(ix, iz, 36) * 3.0), ix * 29 + iz)


func _distance_to_lot(point: Vector2) -> float:
	var lot: Rect2 = Rect2(local_reserve.position.x, local_reserve.position.z,
		local_reserve.size.x, shift - local_reserve.position.z)
	var dx: float = maxf(maxf(lot.position.x - point.x, point.x - lot.end.x), 0.0)
	var dz: float = maxf(maxf(lot.position.y - point.y, point.y - lot.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


## The tree line: two dense rows with the street and the back lane running out
## through gaps, so the world reads as a clearing in woodland, not a cut-off.
func _forest_edge() -> void:
	var centre: Vector2 = world_centre
	var step: float = 2.5
	var count: int = int(WORLD_HALF * 2.0 / step)
	for row: int in 2:
		var inset: float = 1.6 + float(row) * 2.2
		for index: int in count:
			var along: float = -WORLD_HALF + (float(index) + hash01(index, row, 41) * 0.8) * step
			for side: int in 4:
				var at: Vector2 = Vector2.ZERO
				var distance: float = WORLD_HALF - inset - hash01(index, row * 4 + side, 42) * 0.9
				match side:
					0:
						at = centre + Vector2(along, -distance)
					1:
						at = centre + Vector2(along, distance)
					2:
						at = centre + Vector2(-distance, along)
					_:
						at = centre + Vector2(distance, along)
				# Road and lane exits are left open on the two street-facing ends.
				if side >= 2 and ((at.y > shift - 1.2 and at.y < shift + BLOCK_V + 1.2) or absf(at.y - _lane_v) < 1.7):
					continue
				var size: float = 1.7 + hash01(index, row * 4 + side, 43) * 0.6
				_tree(at, size, index * 53 + row * 7 + side, true)


func _tree(at: Vector2, size: float, seed_value: int, ring: bool = false) -> void:
	var yaw: float = hash01(seed_value, 1, 51) * TAU
	var pine: bool = hash01(seed_value, 2, 51) < (skin.ring_pine_share if ring else skin.pine_share)
	var tone: float = hash01(seed_value, 3, 51)
	var leaf: Color = _leaf(tone)
	if ring:
		leaf = leaf.darkened(0.14)
	var position: Vector3 = Vector3(at.x, PLANT_Y, at.y)
	# Far trees are one chunky shape each: nobody sees their trunks.
	if not ring:
		_soup.add(_template("trunk"), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), position), skin.trunk)
	if pine:
		for tier: int in 2 if ring else 3:
			var scale: float = size * (1.0 - float(tier) * 0.28)
			var lift: Vector3 = position + Vector3(0.0, size * ((0.2 if ring else 0.45) + float(tier) * 0.55), 0.0)
			_soup.add(_template("cone"), Transform3D(Basis(Vector3.UP, yaw + float(tier)).scaled(Vector3.ONE * scale), lift), leaf.darkened(0.06 * float(tier)))
	elif ring:
		_soup.add(_template("farblob%d" % (seed_value % 3)), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size * 0.95),
			position + Vector3(0.0, size * 0.85, 0.0)), leaf)
	else:
		var lift: Vector3 = position + Vector3(0.0, size * 1.15, 0.0)
		_soup.add(_template("blob%d" % (seed_value % 3)), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size * 0.92), lift), leaf)
		_soup.add(_template("dome"), Transform3D(Basis(Vector3.UP, yaw + 1.3).scaled(Vector3.ONE * size * 0.6),
			lift + Vector3(0.12 * size, size * 0.5, -0.1 * size)), leaf.lightened(0.07))
	if not ring:
		_blob_shadow(at, size * (0.95 if not pine else 0.8))


func _bush(at: Vector2, size: float, seed_value: int, squash: float, shadow: bool = true) -> void:
	var tone: float = hash01(seed_value, 4, 52)
	var leaf: Color = _leaf(tone * 0.6 + 0.2)
	var basis: Basis = Basis(Vector3.UP, hash01(seed_value, 5, 52) * TAU).scaled(Vector3(size, size * squash, size))
	_soup.add(_template("dome"), Transform3D(basis, Vector3(at.x, PLANT_Y, at.y)), leaf)
	if shadow and size > 0.45:
		_blob_shadow(at, size * 1.05)


func _flowers(at: Vector2, count: int, seed_value: int) -> void:
	var palette: Array[Color] = skin.flowers if not skin.flowers.is_empty() else [Color.WHITE]
	var pick: int = int(hash01(seed_value, 6, 53) * float(palette.size()))
	for index: int in count:
		var offset: Vector2 = Vector2(hash01(seed_value, index, 54) - 0.5, hash01(seed_value, index, 55) - 0.5) * 0.7
		var size: float = 0.05 + hash01(seed_value, index, 56) * 0.03
		var bloom: Color = palette[(pick + (1 if index == count - 1 else 0)) % palette.size()]
		_soup.add(_template("bloom"), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size * 1.1),
			Vector3(at.x + offset.x, PLANT_Y + size * 0.55, at.y + offset.y)), bloom)


func _blob_shadow(at: Vector2, radius: float) -> void:
	var points: Array[Vector2] = _blob(at + Vector2(radius * 0.18, radius * 0.22), radius, radius * 0.8, 0.0, 6)
	_shadows.star(at, points, SHADOW_Y, _shade)


# --- shapes -----------------------------------------------------------------

## A rounded rectangle outline as a convex polygon (counter-clockwise from the top left).
func _rect_points(rect: Rect2, radius: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var corner: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if corner <= 0.001:
		points.append(rect.position)
		points.append(Vector2(rect.end.x, rect.position.y))
		points.append(rect.end)
		points.append(Vector2(rect.position.x, rect.end.y))
		return points
	var centres: Array[Vector2] = [Vector2(rect.position.x + corner, rect.position.y + corner),
		Vector2(rect.end.x - corner, rect.position.y + corner), Vector2(rect.end.x - corner, rect.end.y - corner),
		Vector2(rect.position.x + corner, rect.end.y - corner)]
	for index: int in 4:
		for step: int in 5:
			var angle: float = PI + (float(index) * 5.0 + float(step)) * (PI * 0.5 / 4.0)
			points.append(centres[index] + Vector2(cos(angle), sin(angle)) * corner)
	return points


func _blob(at: Vector2, radius_x: float, radius_z: float, yaw: float, sides: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for index: int in sides:
		var angle: float = float(index) / float(sides) * TAU
		var wobble: float = 0.86 + hash01(index, int(at.x * 10.0), int(at.y * 10.0) + 61) * 0.28
		var local: Vector2 = Vector2(cos(angle) * radius_x, sin(angle) * radius_z) * wobble
		points.append(at + local.rotated(yaw))
	return points


static func _template(key: String) -> Array:
	if _templates.has(key):
		return _templates[key]
	var soup: Soup = Soup.new()
	var white: Color = Color.WHITE
	match key:
		"trunk":
			_prism(soup, 4, 0.1, 0.075, 0.62, white)
		"cone":
			_cone(soup, 6, 0.62, 0.95, white)
		"bloom":
			_bloom(soup, white)
		"dome":
			_dome(soup, white)
		_:
			if key.begins_with("far"):
				_lump(soup, int(key.trim_prefix("farblob")), white, 2, 7)
			else:
				_lump(soup, int(key.trim_prefix("blob")), white, 3, 7)
	var made: Array = [soup.positions, soup.normals]
	_templates[key] = made
	return made


## A flower head: a little double pyramid.
static func _bloom(soup: Soup, colour: Color) -> void:
	var ring: Array[Vector3] = []
	for index: int in 4:
		var angle: float = float(index) / 4.0 * TAU + 0.4
		ring.append(Vector3(cos(angle), 0.0, sin(angle)))
	for index: int in 4:
		var next: Vector3 = ring[(index + 1) % 4]
		soup.tri(ring[index], Vector3(0.0, 0.8, 0.0), next, (ring[index] + next) * 0.5 + Vector3.UP, colour)


## A squat six-sided dome: six triangles, for bushes, hedges and tree crowns.
static func _dome(soup: Soup, colour: Color) -> void:
	for index: int in 6:
		var a0: float = float(index) / 6.0 * TAU
		var a1: float = float(index + 1) / 6.0 * TAU
		var b0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var b1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		soup.tri(b0, Vector3(0.0, 1.0, 0.0), b1, Vector3((b0.x + b1.x) * 0.5, 0.7, (b0.z + b1.z) * 0.5), colour)


static func _prism(soup: Soup, sides: int, bottom: float, top: float, height: float, colour: Color) -> void:
	for index: int in sides:
		var a0: float = float(index) / float(sides) * TAU
		var a1: float = float(index + 1) / float(sides) * TAU
		var b0: Vector3 = Vector3(cos(a0) * bottom, 0.0, sin(a0) * bottom)
		var b1: Vector3 = Vector3(cos(a1) * bottom, 0.0, sin(a1) * bottom)
		var t0: Vector3 = Vector3(cos(a0) * top, height, sin(a0) * top)
		var t1: Vector3 = Vector3(cos(a1) * top, height, sin(a1) * top)
		var hint: Vector3 = Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		soup.tri(b0, t0, b1, hint, colour)
		soup.tri(b1, t0, t1, hint, colour)


static func _cone(soup: Soup, sides: int, radius: float, height: float, colour: Color) -> void:
	for index: int in sides:
		var a0: float = float(index) / float(sides) * TAU
		var a1: float = float(index + 1) / float(sides) * TAU
		var b0: Vector3 = Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var b1: Vector3 = Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var hint: Vector3 = Vector3(cos((a0 + a1) * 0.5), 0.5, sin((a0 + a1) * 0.5))
		soup.tri(b0, Vector3(0.0, height, 0.0), b1, hint, colour)


## A lumpy low-poly ball, unit radius, flat shaded. Variants differ in their lumps.
static func _lump(soup: Soup, variant: int, colour: Color, rings: int, segments: int) -> void:
	var grid: Array[Array] = []
	for ring: int in rings + 1:
		var polar: float = float(ring) / float(rings) * PI
		var row: Array[Vector3] = []
		for segment: int in segments:
			var azimuth: float = float(segment) / float(segments) * TAU + (0.2 if ring % 2 == 1 else 0.0)
			var radius: float = 0.88 + hash01(ring * 9 + segment, variant, 71) * 0.24
			if ring == 0 or ring == rings:
				radius = 1.0
			row.append(Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth)) * radius)
		grid.append(row)
	for ring: int in rings:
		for segment: int in segments:
			var next: int = (segment + 1) % segments
			var a: Vector3 = grid[ring][segment]
			var b: Vector3 = grid[ring][next]
			var c: Vector3 = grid[ring + 1][next]
			var d: Vector3 = grid[ring + 1][segment]
			var hint: Vector3 = (a + b + c + d) * 0.25
			soup.tri(a, d, b, hint, colour)
			soup.tri(b, d, c, hint, colour)
