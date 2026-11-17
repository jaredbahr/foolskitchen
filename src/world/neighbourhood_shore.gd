class_name NeighbourhoodShore
extends RefCounted
## The beach behind a seaside street (#588): past the back lane, low dunes with
## marram grass and a plank path down to the sand, a beach with umbrellas, towels,
## sunbathers, a lifeguard hut, a sandcastle and a ball, people paddling in the
## surf, then open sea to the world's edge with sailboats, a lighthouse on its rocks
## and gulls wheeling overhead. Colours and counts come from the street's ShoreSkin.
##
## Like the rest of the neighbourhood it is view-only: no colliders, sim agents,
## saves or random draws. Everything placed comes from an integer hash, and every
## motion is a closed-form function of the street's display clock, so a paused
## capture or a review time always shows the same frame. Authored in the street's
## local frame (u along the street, z outward to the road), under one root the
## dressing places on that frame. Draw cost: the sand, dunes and props are a few
## batched vertex-coloured meshes, the sea one shader quad, plus a handful of
## gulls, boats and people.

const PERSON: PackedScene = preload("res://assets/people/person.tscn")
const SEA_SHADER: Shader = preload("res://src/world/sea.gdshader")

## Distances behind the back lane's centre line (metres, toward the sea).
const DUNE_NEAR: float = 0.75
const DUNE_FAR: float = 2.1
const WATERLINE: float = 6.6
const WET_WIDTH: float = 1.0
## Heights: the sand lies over the meadow (and under the lane), the sea just over the sand.
const SAND_Y: float = -0.034
const DRIFT_Y: float = -0.031
const SHADOW_Y: float = -0.028
const SEA_Y: float = -0.024
## How far the sand and sea run past the world's sides and out to sea.
const REACH: float = NeighbourhoodGround.WORLD_HALF + NeighbourhoodGround.BEYOND + 30.0
const PATH_WIDTH: float = 1.0
## The lighthouse stands on rocks this far along the beach from the path.
const LIGHTHOUSE_U: float = 13.5
const LIGHTHOUSE_HEIGHT: float = 3.1
const BEAM_LENGTH: float = 11.0
const BEAM_TURN: float = 0.55
const GULL_SPAN: float = 0.8
const GULL_SCALE: float = 1.3
const CASTLE_SCALE: float = 1.5
const BALL_RADIUS: float = 0.16
## Guest looks for the people on the beach (the street's pedestrians use 1, 4 and 6).
const BEACH_GUESTS: Array[int] = [2, 3, 5, 7, 8, 9, 10, 11]
const NIGHT_HIDE: float = 0.5

## One beach person: where and how they rest, and what part of the day they stay for.
class Bather extends RefCounted:
	var person: PersonView
	var player: AnimationPlayer
	var clip: StringName = &"idle"
	## lie, sit, stand or wade
	var pose: StringName = &"lie"
	var at: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	## Waders pace this far either way along the shore.
	var pace: float = 0.0
	var phase: float = 0.0
	## Stays on into the sunset (dusk) while the others have gone home.
	var stays_for_sunset: bool = false

## Inputs, set by the owner before build().
var skin: ShoreSkin
## The back lane's centre line (local z) and the lot's middle along the street.
var lane_v: float = 0.0
var path_u: float = 0.0
var world_centre: Vector2 = Vector2.ZERO
## The key light's ground run per metre of height (local u, z), for baked shadows.
var light_shift: Vector2 = Vector2.ZERO
var salt: int = 0

var root: Node3D
var sea: MeshInstance3D
var sea_material: ShaderMaterial
var day_props: MeshInstance3D
var night_props: MeshInstance3D
var lamp: MeshInstance3D
var beam: MeshInstance3D
var gulls: Array[Node3D] = []
var boats: Array[Node3D] = []
var bathers: Array[Bather] = []
var _gull_wings: Array[Array] = []
var _gull_paths: Array[Dictionary] = []
var _boat_paths: Array[Dictionary] = []
var _boat_lamps: Array[MeshInstance3D] = []
var _material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _lamp_material: StandardMaterial3D
var _beam_material: StandardMaterial3D
var _night: float = 0.0
var _late: float = 0.0
var _seconds: float = 0.0
var _applied_at: float = -1.0
var _lighthouse_lamp: Vector3 = Vector3.ZERO


func _r(a: int, b: int) -> float:
	return NeighbourhoodGround.hash01(a, b, salt + 588)


## The still waterline's local z.
func waterline_z() -> float:
	return lane_v - WATERLINE


# --- building ---------------------------------------------------------------

## Builds every node under `parent` (the dressing's shore root, placed on the street frame).
func build(parent: Node3D) -> void:
	root = parent
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
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.albedo_color = skin.lamp_glow
	_lamp_material.emission_enabled = true
	_lamp_material.emission = skin.lamp_glow
	_lamp_material.emission_energy_multiplier = 0.0
	_lamp_material.disable_receive_shadows = true
	var ground: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var props: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var day: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var night: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var shadows: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	_sand(ground)
	_dunes(ground, props)
	_path(props, shadows)
	_lifeguard_hut(props, shadows, Vector2(path_u + 4.6, lane_v - DUNE_FAR - 1.0))
	_sandcastle(props, shadows, Vector2(path_u - 1.7, waterline_z() + WET_WIDTH + 0.55))
	_lighthouse(props)
	_rocks(props, Vector2(world_centre.x - NeighbourhoodGround.WORLD_HALF + 2.5, waterline_z() + 0.3), 31)
	_rocks(props, Vector2(world_centre.x + NeighbourhoodGround.WORLD_HALF - 2.5, waterline_z() + 0.3), 37)
	_umbrellas(day, night, shadows)
	_add(_mesh("ShoreGround", ground.soup, _material))
	_add(_mesh("ShoreProps", props.soup, _material))
	day_props = _mesh("BeachDay", day.soup, _material)
	_add(day_props)
	night_props = _mesh("BeachEvening", night.soup, _material)
	_add(night_props)
	_add(_mesh("ShoreShadows", shadows, _shadow_material))
	_build_sea()
	_build_lighthouse_light()
	_build_boats()
	_build_gulls()
	_build_bathers()
	_apply_night()


func _add(node: Node3D) -> void:
	if node != null:
		root.add_child(node)


func _mesh(label: String, soup: NeighbourhoodGround.Soup, material: Material) -> MeshInstance3D:
	if soup.is_empty():
		return null
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = soup.to_mesh()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A flat shadow on the sand: the footprint and the same footprint pushed along the light.
func _shadow(shadows: NeighbourhoodGround.Soup, footprint: Array[Vector2], height: float, alpha: float = 1.0) -> void:
	var corners: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in footprint:
		corners.append(point)
		corners.append(point + light_shift * height)
	var hull: PackedVector2Array = Geometry2D.convex_hull(corners)
	var points: Array[Vector2] = []
	for index: int in hull.size() - 1:
		points.append(hull[index])
	if points.size() < 3:
		return
	var centre: Vector2 = Vector2.ZERO
	for point: Vector2 in points:
		centre += point
	centre /= float(points.size())
	var colour: Color = NeighbourhoodFurniture.SHADOW_COLOUR
	colour.a *= alpha
	shadows.star(centre, points, SHADOW_Y, colour)


func _ring(centre: Vector2, radius: float, sides: int, spin: float = 0.0) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for index: int in sides:
		var angle: float = spin + TAU * float(index) / float(sides)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


## The beach's sand from the lane out under the sea, with soft drifts.
func _sand(pen: NeighbourhoodBuildings.Pen) -> void:
	var left: float = world_centre.x - REACH
	var right: float = world_centre.x + REACH
	var top: float = lane_v - 0.6
	pen.flat(left, waterline_z() - 3.0, right, top, SAND_Y, skin.sand)
	# Drifts: low lighter and darker blobs across the dry sand, never touching.
	var placed: Array[Vector3] = []
	for index: int in 70:
		var u: float = world_centre.x + (_r(index, 1) - 0.5) * NeighbourhoodGround.WORLD_HALF * 2.0
		var z: float = lerpf(lane_v - DUNE_NEAR - 0.4, waterline_z() + WET_WIDTH + 0.9, _r(index, 2))
		var size: float = 0.7 + _r(index, 3) * 1.1
		var clear: bool = absf(u - path_u) > PATH_WIDTH * 0.5 + size
		for other: Vector3 in placed:
			if Vector2(u, z).distance_to(Vector2(other.x, other.y)) < (size + other.z) * 1.1:
				clear = false
				break
		if not clear:
			continue
		placed.append(Vector3(u, z, size))
		var colour: Color = skin.sand.lerp(skin.sand_light if _r(index, 4) < 0.6 else skin.sand_dark, 0.45)
		var ring: Array[Vector2] = []
		for step: int in 9:
			var angle: float = TAU * float(step) / 9.0
			var wobble: float = 0.8 + 0.35 * _r(index * 9 + step, 5)
			ring.append(Vector2(cos(angle) * size, sin(angle) * size * 0.45) * wobble)
		for step: int in 9:
			var a: Vector2 = ring[step]
			var b: Vector2 = ring[(step + 1) % 9]
			pen.tri(Vector3(u, DRIFT_Y, z), Vector3(u + a.x, DRIFT_Y, z + a.y), Vector3(u + b.x, DRIFT_Y, z + b.y), Vector3.UP, colour)


## A low dune: a squashed lump of sand; marram tufts stand on its crest.
func _dunes(ground: NeighbourhoodBuildings.Pen, props: NeighbourhoodBuildings.Pen) -> void:
	var u: float = world_centre.x - NeighbourhoodGround.WORLD_HALF - 4.0
	var index: int = 0
	while u < world_centre.x + NeighbourhoodGround.WORLD_HALF + 4.0:
		var width: float = 1.3 + _r(index, 11) * 1.4
		var centre_u: float = u + width * 0.5
		u += width * (0.62 + _r(index, 12) * 0.2)
		index += 1
		# The path runs down through a gap in the dunes.
		if absf(centre_u - path_u) < PATH_WIDTH * 0.5 + width * 0.55:
			continue
		var depth: float = DUNE_FAR - DUNE_NEAR
		var z: float = lane_v - DUNE_NEAR - depth * (0.3 + _r(index, 13) * 0.4)
		var height: float = 0.12 + _r(index, 14) * 0.12
		var tone: Color = skin.sand.lerp(skin.sand_light, _r(index, 15) * 0.7)
		ground.lump(Vector3(centre_u, SAND_Y, z), width * 0.66, height, depth * (0.5 + _r(index, 16) * 0.15),
			_r(index, 17) * PI, tone, tone)
		var tufts: int = 2 + int(_r(index, 18) * 3.0)
		for tuft: int in tufts:
			var at: Vector2 = Vector2(centre_u + (_r(index * 7 + tuft, 19) - 0.5) * width * 0.9,
				z + (_r(index * 7 + tuft, 20) - 0.5) * depth * 0.6)
			var rise: float = height * (1.0 - clampf(absf(at.x - centre_u) / (width * 0.62), 0.0, 1.0)) * 0.7
			_tuft(props, Vector3(at.x, SAND_Y + rise, at.y), index * 7 + tuft)
	# A few tufts along the lane's beach edge and on the flat sand behind the dunes.
	for step: int in 60:
		var at: Vector2 = Vector2(world_centre.x + (_r(step, 21) - 0.5) * NeighbourhoodGround.WORLD_HALF * 2.0,
			lane_v - 0.75 - _r(step, 22) * (DUNE_FAR - 0.4))
		if absf(at.x - path_u) < PATH_WIDTH * 0.5 + 0.25:
			continue
		_tuft(props, Vector3(at.x, SAND_Y, at.y), 500 + step)


## Marram grass: five thin blades leaning out from one root.
func _tuft(pen: NeighbourhoodBuildings.Pen, at: Vector3, seed_value: int) -> void:
	var colour: Color = skin.grass_colors[int(_r(seed_value, 23) * float(skin.grass_colors.size())) % skin.grass_colors.size()]
	var tall: float = 0.2 + _r(seed_value, 24) * 0.14
	for blade: int in 5:
		var angle: float = TAU * float(blade) / 5.0 + _r(seed_value, 25) * TAU
		var lean: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * tall * (0.25 + 0.35 * _r(seed_value * 5 + blade, 26))
		var side: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * 0.022
		var tip: Vector3 = at + lean + Vector3.UP * tall * (0.75 + 0.3 * _r(seed_value * 5 + blade, 27))
		pen.tri(at - side, at + side, tip, Vector3(cos(angle), 0.3, sin(angle)), colour.darkened(0.08 * float(blade % 2)))


## The plank path from the back lane down through the dunes to the sand, roped either side.
func _path(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	var half: float = PATH_WIDTH * 0.5
	var top: float = lane_v - 0.55
	var bottom: float = lane_v - DUNE_FAR - 0.5
	var timber: Color = skin.timber
	# Two bearers under the planks, then the planks across with a narrow gap.
	for side: float in [-half + 0.08, half - 0.08]:
		pen.box(Vector3(path_u + side - 0.04, SAND_Y, bottom), Vector3(path_u + side + 0.04, SAND_Y + 0.035, top), timber.darkened(0.25))
	var z: float = top
	var index: int = 0
	while z - 0.15 > bottom:
		var tone: Color = timber.lerp(skin.sand_light, _r(index, 31) * 0.35)
		pen.box(Vector3(path_u - half, SAND_Y + 0.035, z - 0.15), Vector3(path_u + half, SAND_Y + 0.06, z - 0.01), tone)
		z -= 0.17
		index += 1
	# Rope posts every metre or so, with a sagging rope between their tops.
	var posts: Array[float] = []
	var post_z: float = top - 0.3
	while post_z > bottom + 0.2:
		posts.append(post_z)
		post_z -= 1.05
	for side: float in [-half - 0.08, half + 0.08]:
		for index_post: int in posts.size():
			var pz: float = posts[index_post]
			pen.box(Vector3(path_u + side - 0.035, SAND_Y, pz - 0.035), Vector3(path_u + side + 0.035, SAND_Y + 0.3, pz + 0.035), timber.darkened(0.15))
			pen.box(Vector3(path_u + side - 0.045, SAND_Y + 0.3, pz - 0.045), Vector3(path_u + side + 0.045, SAND_Y + 0.33, pz + 0.045), timber.darkened(0.3))
			_shadow(shadows, _ring(Vector2(path_u + side, pz), 0.04, 4, PI * 0.25), 0.3, 0.8)
			if index_post + 1 < posts.size():
				var next: float = posts[index_post + 1]
				var sag: Vector3 = Vector3(path_u + side, SAND_Y + 0.22, (pz + next) * 0.5)
				_rope(pen, Vector3(path_u + side, SAND_Y + 0.29, pz), sag)
				_rope(pen, sag, Vector3(path_u + side, SAND_Y + 0.29, next))


func _rope(pen: NeighbourhoodBuildings.Pen, from: Vector3, to: Vector3) -> void:
	var rope: Color = skin.sand_dark.darkened(0.15)
	var across: Vector3 = Vector3(0.012, 0.0, 0.0)
	var up: Vector3 = Vector3(0.0, 0.014, 0.0)
	pen.quad(from - across, to - across, to + across, from + across, Vector3.UP, rope)
	pen.quad(from - up, to - up, to + up, from + up, Vector3.RIGHT, rope)


## The lifeguard's hut: a little cabin on stilts, a ramp to its door, a flag on a pole.
func _lifeguard_hut(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2) -> void:
	var timber: Color = skin.timber.darkened(0.12)
	var floor_y: float = SAND_Y + 0.62
	var w: float = 0.5
	var d: float = 0.42
	for corner: Vector2 in [Vector2(-w, -d), Vector2(w, -d), Vector2(w, d), Vector2(-w, d)]:
		var leg: Vector2 = at + corner * 0.86
		pen.box(Vector3(leg.x - 0.045, SAND_Y, leg.y - 0.045), Vector3(leg.x + 0.045, floor_y, leg.y + 0.045), timber)
	# Deck, cabin with a white band and a dark window facing the sea, an overhanging roof.
	pen.box(Vector3(at.x - w - 0.12, floor_y - 0.05, at.y - d - 0.18), Vector3(at.x + w + 0.12, floor_y, at.y + d + 0.06), skin.timber)
	pen.box(Vector3(at.x - w * 0.8, floor_y, at.y - d * 0.6), Vector3(at.x + w * 0.8, floor_y + 0.62, at.y + d * 0.85), skin.hut_body)
	pen.box(Vector3(at.x - w * 0.8 - 0.01, floor_y + 0.3, at.y - d * 0.6 - 0.01), Vector3(at.x + w * 0.8 + 0.01, floor_y + 0.4, at.y + d * 0.85 + 0.01), skin.hut_trim)
	pen.box(Vector3(at.x - w * 0.5, floor_y + 0.42, at.y - d * 0.6 - 0.02), Vector3(at.x + w * 0.5, floor_y + 0.56, at.y - d * 0.6), Color(0.2, 0.17, 0.2))
	var roof_y: float = floor_y + 0.62
	var eave: float = 0.16
	var ridge: Vector3 = Vector3(at.x, roof_y + 0.26, at.y + d * 0.12)
	var corners: Array[Vector3] = [Vector3(at.x - w - eave, roof_y, at.y - d - eave), Vector3(at.x + w + eave, roof_y, at.y - d - eave),
		Vector3(at.x + w + eave, roof_y, at.y + d + eave), Vector3(at.x - w - eave, roof_y, at.y + d + eave)]
	for index: int in 4:
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % 4]
		var tone: Color = skin.hut_body if index % 2 == 0 else skin.hut_trim
		pen.tri(a, b, ridge, (a + b) * 0.5 - Vector3(at.x, roof_y - 0.5, at.y), tone)
	# A ramp down toward the path and a flagpole with the red-and-yellow lifeguard flag.
	var ramp_top: Vector3 = Vector3(at.x - w - 0.1, floor_y - 0.03, at.y + 0.05)
	pen.quad(Vector3(ramp_top.x, ramp_top.y, at.y - 0.18), Vector3(ramp_top.x, ramp_top.y, at.y + 0.18),
		Vector3(ramp_top.x - 0.95, SAND_Y + 0.02, at.y + 0.18), Vector3(ramp_top.x - 0.95, SAND_Y + 0.02, at.y - 0.18), Vector3(-0.5, 1.0, 0.0), skin.timber)
	var pole: Vector2 = at + Vector2(w + 0.05, -d - 0.12)
	pen.box(Vector3(pole.x - 0.018, floor_y, pole.y - 0.018), Vector3(pole.x + 0.018, floor_y + 1.15, pole.y + 0.018), skin.hut_trim)
	pen.quad(Vector3(pole.x, floor_y + 1.12, pole.y), Vector3(pole.x + 0.3, floor_y + 1.12, pole.y), Vector3(pole.x + 0.3, floor_y + 1.0, pole.y),
		Vector3(pole.x, floor_y + 1.0, pole.y), Vector3.FORWARD, skin.hut_body)
	pen.quad(Vector3(pole.x, floor_y + 1.0, pole.y), Vector3(pole.x + 0.3, floor_y + 1.0, pole.y), Vector3(pole.x + 0.3, floor_y + 0.9, pole.y),
		Vector3(pole.x, floor_y + 0.9, pole.y), Vector3.FORWARD, skin.ball_colors[mini(2, skin.ball_colors.size() - 1)])
	var footprint: Array[Vector2] = [at + Vector2(-w - 0.12, -d - 0.18), at + Vector2(w + 0.12, -d - 0.18), at + Vector2(w + 0.12, d + 0.06), at + Vector2(-w - 0.12, d + 0.06)]
	_shadow(shadows, footprint, roof_y - SAND_Y, 0.9)


## A sandcastle: a keep with four round corner towers and a flag, a bucket and a spade.
func _sandcastle(pen: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup, at: Vector2) -> void:
	var sand: Color = skin.sand_dark
	# Built at toy size, then scaled up about its own foot so it reads from the street.
	var foot: Vector3 = Vector3(at.x, SAND_Y, at.y)
	pen.xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * CASTLE_SCALE), foot) * Transform3D(Basis.IDENTITY, -foot)
	pen.box(Vector3(at.x - 0.3, SAND_Y, at.y - 0.24), Vector3(at.x + 0.3, SAND_Y + 0.08, at.y + 0.24), sand.lightened(0.05))
	pen.box(Vector3(at.x - 0.18, SAND_Y + 0.08, at.y - 0.14), Vector3(at.x + 0.18, SAND_Y + 0.22, at.y + 0.14), sand)
	for corner: Vector2 in [Vector2(-0.2, -0.16), Vector2(0.2, -0.16), Vector2(0.2, 0.16), Vector2(-0.2, 0.16)]:
		_drum(pen, at + corner, SAND_Y + 0.08, SAND_Y + 0.27, 0.075, 0.065, sand.lightened(0.04))
		for notch: int in 3:
			var angle: float = TAU * float(notch) / 3.0 + 0.4
			var tip: Vector2 = at + corner + Vector2(cos(angle), sin(angle)) * 0.05
			pen.box(Vector3(tip.x - 0.016, SAND_Y + 0.27, tip.y - 0.016), Vector3(tip.x + 0.016, SAND_Y + 0.3, tip.y + 0.016), sand.lightened(0.04))
	_drum(pen, at, SAND_Y + 0.22, SAND_Y + 0.36, 0.07, 0.05, sand.lightened(0.08))
	pen.box(Vector3(at.x - 0.006, SAND_Y + 0.36, at.y - 0.006), Vector3(at.x + 0.006, SAND_Y + 0.5, at.y + 0.006), skin.timber)
	pen.quad(Vector3(at.x, SAND_Y + 0.5, at.y), Vector3(at.x + 0.12, SAND_Y + 0.47, at.y), Vector3(at.x, SAND_Y + 0.44, at.y), Vector3(at.x, SAND_Y + 0.44, at.y),
		Vector3.FORWARD, skin.ball_colors[0])
	var bucket: Vector2 = at + Vector2(0.48, 0.12)
	_drum(pen, bucket, SAND_Y, SAND_Y + 0.13, 0.065, 0.085, skin.ball_colors[1 % skin.ball_colors.size()])
	pen.box(Vector3(bucket.x + 0.12, SAND_Y, bucket.y - 0.02), Vector3(bucket.x + 0.36, SAND_Y + 0.02, bucket.y + 0.02), skin.ball_colors[0])
	pen.box(Vector3(bucket.x + 0.32, SAND_Y, bucket.y - 0.05), Vector3(bucket.x + 0.42, SAND_Y + 0.025, bucket.y + 0.05), skin.ball_colors[0])
	pen.xf = Transform3D.IDENTITY
	_shadow(shadows, _ring(at, 0.32 * CASTLE_SCALE, 8), 0.3 * CASTLE_SCALE, 0.7)
	_shadow(shadows, _ring(at + (bucket - at) * CASTLE_SCALE, 0.08 * CASTLE_SCALE, 6), 0.13 * CASTLE_SCALE, 0.7)


## A tapered six-sided post (towers, buckets, umbrella poles).
func _drum(pen: NeighbourhoodBuildings.Pen, at: Vector2, y0: float, y1: float, r0: float, r1: float, colour: Color, sides: int = 6) -> void:
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var b0: Vector3 = Vector3(at.x + cos(a0) * r0, y0, at.y + sin(a0) * r0)
		var b1: Vector3 = Vector3(at.x + cos(a1) * r0, y0, at.y + sin(a1) * r0)
		var t0: Vector3 = Vector3(at.x + cos(a0) * r1, y1, at.y + sin(a0) * r1)
		var t1: Vector3 = Vector3(at.x + cos(a1) * r1, y1, at.y + sin(a1) * r1)
		var hint: Vector3 = Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		pen.quad(b0, b1, t1, t0, hint, colour)
		pen.tri(Vector3(at.x, y1, at.y), t0, t1, Vector3.UP, colour)


## The lighthouse on its rocks at the water's edge, banded in two colours.
func _lighthouse(pen: NeighbourhoodBuildings.Pen) -> void:
	var at: Vector2 = Vector2(path_u + LIGHTHOUSE_U, waterline_z() - 0.6)
	_rocks(pen, at, 17)
	var base_y: float = SAND_Y + 0.32
	var bands: int = 5
	for band: int in bands:
		var y0: float = base_y + LIGHTHOUSE_HEIGHT * float(band) / float(bands)
		var y1: float = base_y + LIGHTHOUSE_HEIGHT * float(band + 1) / float(bands)
		var r0: float = lerpf(0.5, 0.34, float(band) / float(bands))
		var r1: float = lerpf(0.5, 0.34, float(band + 1) / float(bands))
		_drum(pen, at, y0, y1, r0, r1, skin.lighthouse_colors[band % skin.lighthouse_colors.size()], 8)
	var top: float = base_y + LIGHTHOUSE_HEIGHT
	_drum(pen, at, top, top + 0.06, 0.46, 0.46, skin.timber.darkened(0.4), 8)
	for post: int in 8:
		var angle: float = TAU * float(post) / 8.0
		var p: Vector2 = at + Vector2(cos(angle), sin(angle)) * 0.24
		pen.box(Vector3(p.x - 0.018, top + 0.06, p.y - 0.018), Vector3(p.x + 0.018, top + 0.42, p.y + 0.018), skin.timber.darkened(0.4))
	_drum(pen, at, top + 0.42, top + 0.5, 0.3, 0.3, skin.lighthouse_colors[0], 8)
	_drum(pen, at, top + 0.5, top + 0.78, 0.3, 0.02, skin.lighthouse_colors[0], 8)
	_lighthouse_lamp = Vector3(at.x, top + 0.24, at.y)


## A cluster of grey rocks half in the water.
func _rocks(pen: NeighbourhoodBuildings.Pen, at: Vector2, seed_value: int) -> void:
	for index: int in 7:
		var angle: float = TAU * _r(seed_value, index + 40)
		var reach: float = 0.2 + _r(seed_value, index + 50) * 0.75
		var centre: Vector2 = at + Vector2(cos(angle), sin(angle) * 0.8) * reach
		var size: float = 0.32 + _r(seed_value, index + 60) * 0.32
		var tone: Color = skin.rock.lerp(skin.rock.lightened(0.18), _r(seed_value, index + 70))
		pen.lump(Vector3(centre.x, SAND_Y, centre.y), size, size * (0.6 + 0.4 * _r(seed_value, index + 80)), size * 0.85,
			_r(seed_value, index + 90) * PI, tone, tone.darkened(0.2))


## Umbrellas with their towels by day; furled umbrellas once the beach empties.
func _umbrellas(day: NeighbourhoodBuildings.Pen, night: NeighbourhoodBuildings.Pen, shadows: NeighbourhoodGround.Soup) -> void:
	for index: int in skin.umbrellas:
		var spot: Vector2 = umbrella_spot(index)
		var stripe_a: Color = skin.umbrella_colors[(index * 2) % skin.umbrella_colors.size()]
		var stripe_b: Color = skin.umbrella_colors[(index * 2 + 1) % skin.umbrella_colors.size()]
		var tilt: Vector2 = Vector2(0.1, -0.06)
		var pole_top: Vector3 = Vector3(spot.x + tilt.x, SAND_Y + 0.92, spot.y + tilt.y)
		_pole(day, Vector3(spot.x, SAND_Y, spot.y), pole_top + Vector3.UP * 0.12)
		var canopy: Vector3 = pole_top
		var ring: Array[Vector3] = []
		for step: int in 8:
			var angle: float = TAU * float(step) / 8.0 + _r(index, 33)
			ring.append(canopy + Vector3(cos(angle) * 0.56, -0.18, sin(angle) * 0.56))
		for step: int in 8:
			var a: Vector3 = ring[step]
			var b: Vector3 = ring[(step + 1) % 8]
			var colour: Color = stripe_a if step % 2 == 0 else stripe_b
			day.tri(a, b, canopy + Vector3.UP * 0.1, (a + b) * 0.5 - canopy + Vector3.UP * 0.8, colour)
			day.tri(a, b, canopy + Vector3.UP * 0.1, (a + b) * 0.5 - canopy + Vector3.UP * 0.8, colour)
			# A short valance below each panel.
			day.quad(a, b, b + Vector3.DOWN * 0.05, a + Vector3.DOWN * 0.05, (a + b) * 0.5 - canopy, colour.darkened(0.1))
		# Its shadow on the sand: the canopy pushed along the light by its height.
		var cast: Array[Vector2] = []
		for point: Vector3 in ring:
			cast.append(Vector2(point.x, point.z) + light_shift * (point.y - SAND_Y))
		_shade_disc(shadows, cast)
		# Furled: the canopy rolled tight round the pole.
		_pole(night, Vector3(spot.x, SAND_Y, spot.y), pole_top + Vector3.UP * 0.12)
		for step: int in 6:
			var angle: float = TAU * float(step) / 6.0
			var next: float = TAU * float(step + 1) / 6.0
			var low: Vector3 = canopy + Vector3.DOWN * 0.55
			var a: Vector3 = canopy + Vector3(cos(angle) * 0.07, -0.12, sin(angle) * 0.07)
			var b: Vector3 = canopy + Vector3(cos(next) * 0.07, -0.12, sin(next) * 0.07)
			night.tri(a, b, low, Vector3(cos(angle), 0.0, sin(angle)), stripe_a if step % 2 == 0 else stripe_b)
			night.tri(a, b, canopy + Vector3.UP * 0.06, Vector3(cos(angle), 1.0, sin(angle)), stripe_a)
		# A towel by each umbrella, its far end in the shade; a cool box by some.
		var towel: Color = skin.towel_colors[index % skin.towel_colors.size()]
		var towel_at: Vector2 = towel_spot(index)
		day.box(Vector3(towel_at.x - 0.2, SAND_Y, towel_at.y - 0.45), Vector3(towel_at.x + 0.2, SAND_Y + 0.012, towel_at.y + 0.45), towel)
		for stripe: float in [-0.3, 0.3]:
			day.box(Vector3(towel_at.x - 0.201, SAND_Y + 0.001, towel_at.y + stripe - 0.05), Vector3(towel_at.x + 0.201, SAND_Y + 0.014, towel_at.y + stripe + 0.05),
				skin.towel_colors[(index + 2) % skin.towel_colors.size()])
		if index % 2 == 1:
			var box_at: Vector2 = spot + Vector2(-0.45, 0.25)
			day.box(Vector3(box_at.x - 0.13, SAND_Y, box_at.y - 0.09), Vector3(box_at.x + 0.13, SAND_Y + 0.15, box_at.y + 0.09), skin.ball_colors[1 % skin.ball_colors.size()])
			day.box(Vector3(box_at.x - 0.135, SAND_Y + 0.15, box_at.y - 0.095), Vector3(box_at.x + 0.135, SAND_Y + 0.18, box_at.y + 0.095), skin.hut_trim)
	# The beach ball, between two towels.
	if skin.umbrellas > 1:
		var ball: Vector2 = (towel_spot(0) + towel_spot(1)) * 0.5 + Vector2(0.0, -0.9)
		_ball(day, Vector3(ball.x, SAND_Y + BALL_RADIUS, ball.y), BALL_RADIUS)
		var shade: Array[Vector2] = _ring(ball + light_shift * BALL_RADIUS, BALL_RADIUS * 0.9, 8)
		_shade_disc(shadows, shade)


func _shade_disc(shadows: NeighbourhoodGround.Soup, points: Array[Vector2]) -> void:
	var centre: Vector2 = Vector2.ZERO
	for point: Vector2 in points:
		centre += point
	centre /= float(points.size())
	shadows.star(centre, points, SHADOW_Y, NeighbourhoodFurniture.SHADOW_COLOUR)


func _pole(pen: NeighbourhoodBuildings.Pen, from: Vector3, to: Vector3) -> void:
	var across: Vector3 = Vector3(0.018, 0.0, 0.0)
	var deep: Vector3 = Vector3(0.0, 0.0, 0.018)
	var colour: Color = skin.hut_trim.darkened(0.1)
	pen.quad(from - across, to - across, to + across, from + across, Vector3.FORWARD, colour)
	pen.quad(from - deep, to - deep, to + deep, from + deep, Vector3.RIGHT, colour)


## A beach ball: six coloured wedges from pole to pole.
func _ball(pen: NeighbourhoodBuildings.Pen, centre: Vector3, radius: float) -> void:
	var rings: int = 4
	for wedge: int in 6:
		var colour: Color = skin.ball_colors[wedge % skin.ball_colors.size()]
		for ring: int in rings:
			var p0: float = PI * float(ring) / float(rings)
			var p1: float = PI * float(ring + 1) / float(rings)
			var a0: float = TAU * float(wedge) / 6.0
			var a1: float = TAU * float(wedge + 1) / 6.0
			var points: Array[Vector3] = []
			for corner: Vector2 in [Vector2(p0, a0), Vector2(p0, a1), Vector2(p1, a1), Vector2(p1, a0)]:
				points.append(centre + Vector3(sin(corner.x) * cos(corner.y), cos(corner.x), sin(corner.x) * sin(corner.y)) * radius)
			var hint: Vector3 = (points[0] + points[1] + points[2] + points[3]) * 0.25 - centre
			pen.quad(points[0], points[1], points[2], points[3], hint, colour)


## Where the index-th umbrella stands (local u, z): spread along the beach either side of the path.
func umbrella_spot(index: int) -> Vector2:
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var rank: int = index >> 1
	var u: float = path_u + side * (2.2 + float(rank) * 3.4 + _r(index, 34) * 1.2)
	var z: float = lerpf(lane_v - DUNE_FAR - 0.7, waterline_z() + WET_WIDTH + 1.6, _r(index, 35))
	return Vector2(u, z)


func towel_spot(index: int) -> Vector2:
	return umbrella_spot(index) + Vector2(0.5 if index % 2 == 0 else -0.5, -0.35)


# --- the sea and its lights -------------------------------------------------

func _build_sea() -> void:
	var near: float = waterline_z() + WET_WIDTH + 0.35
	var far: float = waterline_z() - REACH
	var left: float = world_centre.x - REACH
	var right: float = world_centre.x + REACH
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	# A coarse grid so the vertex light stays even across the water.
	var columns: int = 12
	var rows: int = 8
	var depths: Array[float] = [near, waterline_z() - 2.0, waterline_z() - 6.0, waterline_z() - 12.0, waterline_z() - 20.0,
		waterline_z() - 32.0, waterline_z() - 50.0, waterline_z() - 75.0, far]
	for row: int in rows:
		for column: int in columns:
			var u0: float = lerpf(left, right, float(column) / float(columns))
			var u1: float = lerpf(left, right, float(column + 1) / float(columns))
			var z0: float = depths[row]
			var z1: float = depths[row + 1]
			for corner: Vector2 in [Vector2(u0, z0), Vector2(u1, z1), Vector2(u1, z0), Vector2(u0, z0), Vector2(u0, z1), Vector2(u1, z1)]:
				vertices.append(Vector3(corner.x, SEA_Y, corner.y))
				normals.append(Vector3.UP)
				uvs.append(corner)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	sea_material = ShaderMaterial.new()
	sea_material.shader = SEA_SHADER
	sea_material.set_shader_parameter(&"shore_z", waterline_z())
	sea_material.set_shader_parameter(&"wet_width", WET_WIDTH)
	sea_material.set_shader_parameter(&"sand_wet", skin.sand_wet)
	sea_material.set_shader_parameter(&"shallow", skin.sea_shallow)
	sea_material.set_shader_parameter(&"mid", skin.sea_mid)
	sea_material.set_shader_parameter(&"deep", skin.sea_deep)
	sea_material.set_shader_parameter(&"foam", skin.foam)
	sea_material.set_shader_parameter(&"light_color", skin.lamp_glow)
	sea = MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = mesh
	sea.material_override = sea_material
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad's bounds reach far out; never let it be culled at a corner of the view.
	sea.extra_cull_margin = 4.0
	root.add_child(sea)


func _build_lighthouse_light() -> void:
	var glass: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	_drum(glass, Vector2(_lighthouse_lamp.x, _lighthouse_lamp.z), _lighthouse_lamp.y - 0.17, _lighthouse_lamp.y + 0.17, 0.2, 0.2, Color.WHITE, 8)
	lamp = MeshInstance3D.new()
	lamp.name = "LighthouseLamp"
	lamp.mesh = glass.soup.to_mesh()
	lamp.material_override = _lamp_material
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lamp)
	# The beam: a long, faint fan that sweeps round over the water at night.
	var fan: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var spread: float = deg_to_rad(7.0)
	var steps: int = 4
	for step: int in steps:
		var near: float = BEAM_LENGTH * float(step) / float(steps)
		var far: float = BEAM_LENGTH * float(step + 1) / float(steps)
		var fade0: float = 1.0 - float(step) / float(steps)
		var fade1: float = 1.0 - float(step + 1) / float(steps)
		var a: Vector3 = Vector3(sin(-spread) * near, 0.0, -cos(spread) * near)
		var b: Vector3 = Vector3(sin(spread) * near, 0.0, -cos(spread) * near)
		var c: Vector3 = Vector3(sin(spread) * far, 0.0, -cos(spread) * far)
		var d: Vector3 = Vector3(sin(-spread) * far, 0.0, -cos(spread) * far)
		for point: Vector3 in [a, b, c, a, c, d]:
			fan.positions.append(point)
			fan.normals.append(Vector3.UP)
			var fade: float = fade0 if point == a or point == b else fade1
			fan.colors.append(Color(1.0, 1.0, 1.0, fade))
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.vertex_color_use_as_albedo = true
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_material.albedo_color = Color(skin.lamp_glow, 0.0)
	_beam_material.disable_receive_shadows = true
	beam = MeshInstance3D.new()
	beam.name = "LighthouseBeam"
	beam.mesh = fan.to_mesh()
	beam.material_override = _beam_material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)


# --- boats ------------------------------------------------------------------

func _build_boats() -> void:
	for index: int in skin.boats:
		var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		var hull: Color = skin.hull_colors[index % skin.hull_colors.size()]
		var sail: Color = skin.sail_colors[index % skin.sail_colors.size()]
		var size: float = 1.0 + _r(index, 61) * 0.3
		pen.xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), Vector3.ZERO)
		# Hull: a pointed tub, bow toward +x; a cream deck; mast; main and jib.
		var deck: Array[Vector3] = [Vector3(-0.75, 0.16, -0.26), Vector3(0.45, 0.16, -0.26), Vector3(0.95, 0.16, 0.0),
			Vector3(0.45, 0.16, 0.26), Vector3(-0.75, 0.16, 0.26)]
		var keel: Array[Vector3] = [Vector3(-0.68, -0.08, -0.18), Vector3(0.4, -0.08, -0.16), Vector3(0.8, 0.0, 0.0),
			Vector3(0.4, -0.08, 0.16), Vector3(-0.68, -0.08, 0.18)]
		for side: int in 5:
			var next: int = (side + 1) % 5
			var middle: Vector3 = (deck[side] + deck[next]) * 0.5
			pen.quad(keel[side], keel[next], deck[next], deck[side], Vector3(middle.x, 0.0, middle.z), hull)
		pen.tri(deck[0], deck[1], deck[4], Vector3.UP, skin.hut_trim)
		pen.tri(deck[1], deck[3], deck[4], Vector3.UP, skin.hut_trim)
		pen.tri(deck[1], deck[2], deck[3], Vector3.UP, skin.hut_trim)
		pen.box(Vector3(0.08, 0.16, -0.025), Vector3(0.13, 2.0, 0.025), skin.timber.darkened(0.3))
		pen.box(Vector3(-0.65, 0.42, -0.02), Vector3(0.1, 0.45, 0.02), skin.timber.darkened(0.3))
		pen.tri(Vector3(0.08, 1.95, 0.0), Vector3(0.08, 0.46, 0.0), Vector3(-0.62, 0.46, 0.0), Vector3.FORWARD, skin.foam)
		pen.tri(Vector3(0.13, 1.85, 0.0), Vector3(0.13, 0.3, 0.0), Vector3(0.9, 0.22, 0.0), Vector3.FORWARD, sail)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "Sailboat%d" % index
		node.mesh = pen.soup.to_mesh()
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mast_lamp: MeshInstance3D = MeshInstance3D.new()
		mast_lamp.name = "MastLamp"
		var bulb: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		bulb.box(Vector3(0.06, 2.0, -0.05), Vector3(0.15, 2.09, 0.05), Color.WHITE)
		mast_lamp.mesh = bulb.soup.to_mesh()
		mast_lamp.material_override = _lamp_material
		mast_lamp.scale = Vector3.ONE * size
		mast_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mast_lamp)
		_boat_lamps.append(mast_lamp)
		root.add_child(node)
		boats.append(node)
		var out: float = 7.0 + float(index) * 6.0 + _r(index, 62) * 3.0
		_boat_paths.append({"u": path_u + (float(index) - float(skin.boats - 1) * 0.5) * 9.0 + (_r(index, 63) - 0.5) * 4.0,
			"z": waterline_z() - out, "span": 3.0 + _r(index, 64) * 3.0, "rate": 0.018 + 0.012 * _r(index, 65),
			"phase": _r(index, 66) * TAU})


## A boat's place (local u, z), heading and bob at `seconds`: it beats slowly back and
## forth along the shore and turns about at each end.
func boat_pose(index: int, seconds: float) -> Dictionary:
	var path: Dictionary = _boat_paths[index]
	var angle: float = seconds * float(path["rate"]) + float(path["phase"])
	var u: float = float(path["u"]) + float(path["span"]) * sin(angle)
	var velocity: float = cos(angle)
	var heading: float = lerpf(PI, 0.0, smoothstep(-0.25, 0.25, velocity))
	var bob: float = 0.025 * sin(seconds * 1.3 + float(index) * 2.1)
	var roll: float = 0.05 * sin(seconds * 1.1 + float(index)) - 0.12
	var pitch: float = 0.04 * sin(seconds * 0.9 + float(index) * 1.7)
	return {"u": u, "z": float(path["z"]) + 0.3 * sin(angle * 0.5), "heading": heading, "bob": bob, "roll": roll, "pitch": pitch}


# --- gulls ------------------------------------------------------------------

func _build_gulls() -> void:
	for index: int in skin.gulls:
		var body: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		body.lump(Vector3(0.0, 0.0, 0.0), 0.06, 0.05, 0.16, 0.0, skin.gull_body, skin.gull_body.darkened(0.08))
		body.lump(Vector3(0.0, 0.04, 0.14), 0.045, 0.04, 0.05, 0.3, skin.gull_body, skin.gull_body)
		body.box(Vector3(-0.012, 0.03, 0.18), Vector3(0.012, 0.045, 0.23), Color("e0a53a"))
		body.tri(Vector3(-0.05, 0.0, -0.12), Vector3(0.05, 0.0, -0.12), Vector3(0.0, 0.01, -0.24), Vector3.UP, skin.gull_wing)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "Gull%d" % index
		node.mesh = body.soup.to_mesh()
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var wings: Array[MeshInstance3D] = []
		for side: float in [-1.0, 1.0]:
			var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
			var half: float = GULL_SPAN * 0.5
			var root_front: Vector3 = Vector3(0.0, 0.0, 0.07)
			var root_back: Vector3 = Vector3(0.0, 0.0, -0.06)
			var elbow_front: Vector3 = Vector3(side * half * 0.55, 0.02, 0.06)
			var elbow_back: Vector3 = Vector3(side * half * 0.55, 0.02, -0.06)
			var tip: Vector3 = Vector3(side * half, -0.01, -0.07)
			pen.quad(root_front, elbow_front, elbow_back, root_back, Vector3.UP, skin.gull_wing)
			pen.tri(elbow_front, tip, elbow_back, Vector3.UP, skin.gull_tip)
			var wing: MeshInstance3D = MeshInstance3D.new()
			wing.name = "WingL" if side < 0.0 else "WingR"
			wing.mesh = pen.soup.to_mesh()
			wing.material_override = _material
			wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wing.position = Vector3(0.0, 0.03, 0.02)
			node.add_child(wing)
			wings.append(wing)
		root.add_child(node)
		gulls.append(node)
		_gull_wings.append(wings)
		# Each gull wheels round its own loose ellipse: most over the beach, one over the street.
		var over_shop: bool = index == 1
		var centre: Vector2 = Vector2(path_u + (_r(index, 71) - 0.5) * 16.0,
			lane_v + 5.0 if over_shop else lerpf(lane_v - 3.0, waterline_z() - 3.0, _r(index, 72)))
		_gull_paths.append({"centre": centre, "rx": 2.5 + _r(index, 73) * 3.0, "rz": 1.6 + _r(index, 74) * 2.0,
			"rate": (0.22 + 0.12 * _r(index, 75)) * (1.0 if _r(index, 76) < 0.6 else -1.0), "phase": _r(index, 77) * TAU,
			"height": 2.3 + _r(index, 78) * 1.1})


## A gull's place (local), heading, bank and wing lift at `seconds`: it glides round its
## ellipse, and every so often flaps a few beats.
func gull_pose(index: int, seconds: float) -> Dictionary:
	var path: Dictionary = _gull_paths[index]
	var rate: float = float(path["rate"])
	var angle: float = seconds * rate + float(path["phase"])
	var centre: Vector2 = path["centre"]
	var rx: float = float(path["rx"])
	var rz: float = float(path["rz"])
	var drift: Vector2 = Vector2(sin(seconds * 0.05 + float(index)) * 1.5, cos(seconds * 0.04 + float(index) * 2.0) * 0.8)
	var at: Vector2 = centre + drift + Vector2(cos(angle) * rx, sin(angle) * rz)
	var velocity: Vector2 = Vector2(-sin(angle) * rx, cos(angle) * rz) * rate
	var heading: float = atan2(velocity.x, velocity.y)
	var bank: float = -0.35 * signf(rate)
	var height: float = float(path["height"]) + 0.25 * sin(seconds * 0.3 + float(index))
	var burst: float = smoothstep(0.55, 0.8, sin(seconds * 0.42 + float(index) * 1.9))
	var wing: float = 0.12 + burst * 0.62 * sin(seconds * 10.0 + float(index))
	return {"u": at.x, "z": at.y, "y": height, "heading": heading, "bank": bank, "wing": wing}


# --- people -----------------------------------------------------------------

func _build_bathers() -> void:
	var plans: Array[Dictionary] = []
	for index: int in skin.sunbathers:
		var towel: int = index % maxi(skin.umbrellas, 1)
		var at: Vector2 = towel_spot(towel) if skin.umbrellas > 0 else Vector2(path_u + float(index) * 2.0, waterline_z() + 3.5)
		var pose: StringName = [&"lie", &"sit", &"lie", &"stand", &"sit", &"lie", &"sit", &"lie"][index % 8]
		if index >= skin.umbrellas:
			# A second person by an umbrella sits beside the first, on the sand.
			at += Vector2(0.45 if towel % 2 == 0 else -0.45, 0.1)
			pose = &"sit"
		plans.append({"pose": pose, "at": at, "sunset": pose == &"sit" and index % 2 == 0})
	for index: int in skin.waders:
		var u: float = path_u + (float(index) - float(skin.waders - 1) * 0.5) * 3.6 + (_r(index, 81) - 0.5) * 1.2
		plans.append({"pose": &"wade", "at": Vector2(u, waterline_z() - 0.55 - _r(index, 82) * 0.4), "sunset": index == 0})
	for index: int in plans.size():
		var plan: Dictionary = plans[index]
		var bather: Bather = Bather.new()
		bather.pose = plan["pose"]
		bather.stays_for_sunset = plan["sunset"]
		bather.phase = _r(index, 83) * 10.0
		var at: Vector2 = plan["at"]
		match bather.pose:
			&"lie":
				# Feet toward the sea, head toward the dunes, along the towel.
				bather.at = Vector3(at.x, SAND_Y + 0.11, at.y - 0.38)
				bather.yaw = 0.0
			&"sit":
				bather.at = Vector3(at.x, SAND_Y + 0.01, at.y)
				bather.yaw = PI + (_r(index, 84) - 0.5) * 0.6
				bather.clip = &"sit"
			&"stand":
				bather.at = Vector3(at.x + 0.35, SAND_Y, at.y - 0.2)
				bather.yaw = (_r(index, 85) - 0.5) * 2.0
			_:
				bather.at = Vector3(at.x, SEA_Y - 0.13, at.y)
				bather.yaw = PI
				bather.pace = 0.9 if index % 2 == 0 else 0.0
				bather.clip = &"walk" if bather.pace > 0.0 else &"idle"
		var person: PersonView = PERSON.instantiate() as PersonView
		person.name = "Beachgoer%d" % index
		person.role = &"guest"
		person.guest_id = BEACH_GUESTS[index % BEACH_GUESTS.size()]
		root.add_child(person)
		bather.person = person
		bathers.append(bather)


## Finds each person's animation player once their model is ready, and freezes it to
## the street clock (seeked by apply, never advanced by the engine).
func _ready_players() -> void:
	for bather: Bather in bathers:
		if bather.player != null or not bather.person.is_node_ready():
			continue
		bather.person.set_pose(bather.clip == &"walk", bather.clip == &"sit", false, false, 0.0)
		var players: Array[Node] = bather.person.find_children("*", "AnimationPlayer", true, false)
		if players.is_empty():
			continue
		bather.player = players[0] as AnimationPlayer
		bather.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for node: Node in bather.person.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A bather's local transform at `seconds`.
func bather_transform(bather: Bather, seconds: float) -> Transform3D:
	match bather.pose:
		&"lie":
			return Transform3D(Basis(Vector3.UP, bather.yaw) * Basis(Vector3.RIGHT, PI * 0.5), bather.at)
		&"wade":
			if bather.pace <= 0.0:
				return Transform3D(Basis(Vector3.UP, bather.yaw), bather.at)
			# Paddling up and down the shallows at a stroll, turning at each end.
			var length: float = bather.pace * 2.0
			var progress: float = fposmod(seconds * 0.22 + bather.phase, length * 2.0)
			var forward: bool = progress <= length
			var offset: float = (progress if forward else length * 2.0 - progress) - bather.pace
			return Transform3D(Basis(Vector3.UP, PI * 0.5 if forward else -PI * 0.5), bather.at + Vector3(offset, 0.0, 0.0))
		_:
			return Transform3D(Basis(Vector3.UP, bather.yaw), bather.at)


# --- motion and time of day -------------------------------------------------

## 0 by day, 1 from dusk; `late` rises after the shop closes. The beach empties at
## dusk but for a few who stay for the sunset, and is empty by night.
func set_night(level: float, late: float) -> void:
	_night = level
	_late = late
	_apply_night()


func is_day() -> bool:
	return _night < NIGHT_HIDE


## True while the sunset stragglers are still on the sand.
func is_sunset() -> bool:
	return not is_day() and _late < NIGHT_HIDE


func _apply_night() -> void:
	if root == null:
		return
	if day_props != null:
		day_props.visible = is_day()
	if night_props != null:
		night_props.visible = not is_day()
	for bather: Bather in bathers:
		bather.person.visible = is_day() or (is_sunset() and bather.stays_for_sunset)
	_lamp_material.emission_energy_multiplier = _night * 2.4
	_lamp_material.albedo_color = skin.lamp_glow.lerp(skin.hut_trim, 1.0 - _night)
	_beam_material.albedo_color = Color(skin.lamp_glow, 0.35 * _night)
	beam.visible = _night > 0.01
	# The gulls roost once it is properly dark.
	for gull: Node3D in gulls:
		gull.visible = _late < NIGHT_HIDE
	for mast_lamp: MeshInstance3D in _boat_lamps:
		mast_lamp.visible = _night > 0.01
	if sea_material != null:
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
	var lights: PackedVector4Array = PackedVector4Array([Vector4(_lighthouse_lamp.x, _lighthouse_lamp.z - 1.6, 0.9 * _night, 0.0)])
	for index: int in boats.size():
		var pose: Dictionary = boat_pose(index, seconds)
		var basis: Basis = Basis(Vector3.UP, float(pose["heading"])) * Basis(Vector3.RIGHT, float(pose["roll"])) * Basis(Vector3.BACK, float(pose["pitch"]))
		boats[index].transform = Transform3D(basis, Vector3(float(pose["u"]), SEA_Y - 0.02 + float(pose["bob"]), float(pose["z"])))
		lights.append(Vector4(float(pose["u"]), float(pose["z"]) - 0.6, 0.45 * _night, 0.0))
	while lights.size() < 4:
		lights.append(Vector4.ZERO)
	lights.resize(4)
	sea_material.set_shader_parameter(&"lights", lights)
	beam.transform = Transform3D(Basis(Vector3.UP, seconds * BEAM_TURN), _lighthouse_lamp)
	for index: int in gulls.size():
		var pose: Dictionary = gull_pose(index, seconds)
		var basis: Basis = (Basis(Vector3.UP, float(pose["heading"])) * Basis(Vector3.BACK, float(pose["bank"]))).scaled(Vector3.ONE * GULL_SCALE)
		gulls[index].transform = Transform3D(basis, Vector3(float(pose["u"]), float(pose["y"]), float(pose["z"])))
		var wings: Array = _gull_wings[index]
		(wings[0] as MeshInstance3D).rotation = Vector3(0.0, 0.0, -float(pose["wing"]))
		(wings[1] as MeshInstance3D).rotation = Vector3(0.0, 0.0, float(pose["wing"]))
	_ready_players()
	for bather: Bather in bathers:
		bather.person.transform = bather_transform(bather, seconds)
		if bather.player != null and bather.player.has_animation(bather.person.current_clip()):
			var length: float = bather.player.get_animation(bather.person.current_clip()).length
			var rate: float = 0.55 if bather.clip == &"walk" else 1.0
			bather.player.seek(fposmod(seconds * rate + bather.phase, maxf(length, 0.01)), true)


## What the shore shows now, for tests and captures.
func capture_state() -> Dictionary:
	var people: int = 0
	for bather: Bather in bathers:
		if bather.person.visible:
			people += 1
	return {"waterline_z": waterline_z(), "lane_v": lane_v, "gulls": gulls.size(), "boats": boats.size(),
		"bathers": bathers.size(), "visible_bathers": people, "day_props": day_props != null and day_props.visible,
		"beam": beam != null and beam.visible, "night": _night, "late": _late}
