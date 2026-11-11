class_name NeighbourhoodFurniture
extends RefCounted
## Cosy street furniture on the near pavement (#423): planter trees, benches, bins, a
## bike rack, a hydrant, a bus stop and a postbox. View-only: generated vertex-coloured
## boxes in the street's local frame (u along the street, v across the pavement from the
## lot's street line), one flat-shaded shadowless mesh for all of them and one flat
## translucent mesh of baked contact shadows, so every prop stands on its own shadow.
##
## Planning is pure and deterministic: integer hashes of the prop's number and the
## StreetSet seed pick each spot, never an RNG. Props only ever stand in the free band
## between the shop fronts and the pedestrian lane: never in front of the player's lot,
## its door approach or entrance pads, a neighbour's door, a walking lane or another prop.
## The StreetSet's `furniture` list says what and how many, so a seaside street swaps it.

## The pavement band props may occupy, in v: past the awnings and shop stock, short of
## the near pedestrian lane (which starts at 2.255).
const BAND_LO: float = 0.56
const BAND_HI: float = 2.14
const STEP: float = 0.25
## Clear metres kept round every prop (the door corridors, the lot and each other).
const SPACING: float = 0.3
const SHADOW_COLOUR: Color = Color(0.13, 0.09, 0.12, 0.30)
const SHADOW_LIFT: float = 0.004
const DOOR_HALF: float = 0.75
const DOOR_DEPTH: float = 2.3
const LOT_MARGIN: float = 0.5

class Placed extends RefCounted:
	var kind: int = 0
	var u: float = 0.0
	var v: float = 0.0
	var size: Vector3 = Vector3.ONE
	var seed_value: int = 0

	## The footprint in (u, v).
	func rect() -> Rect2:
		return Rect2(u - size.x * 0.5, v - size.z * 0.5, size.x, size.z)

var street: StreetSet
## The street's u range props may use (clamped to the built street).
var u_range: Vector2 = Vector2(-14.0, 14.0)
## The maximum lot's u extent: nothing stands in front of it.
var lot_u: Vector2 = Vector2.ZERO
## Rectangles (u, v) nothing may overlap: native pavement, door approaches, walking sweeps.
var exclusions: Array[Rect2] = []
## Street-local x of every neighbour's front door.
var doors: Array[float] = []
## u spans of the neighbouring buildings (wall props prefer to stand in front of them).
var building_spans: Array[Vector2] = []
var placed: Array[Placed] = []
var _material: StandardMaterial3D


func _r(a: int, b: int) -> float:
	return NeighbourhoodGround.hash01(a, b, street.seed_salt + 311)


# --- planning ---------------------------------------------------------------

func plan() -> void:
	placed.clear()
	if street == null:
		street = StreetSet.standard()
	var blocked: Array[Rect2] = exclusions.duplicate()
	blocked.append(Rect2(lot_u.x - LOT_MARGIN, -2.0, lot_u.y - lot_u.x + LOT_MARGIN * 2.0, BAND_HI + 3.0))
	for door: float in doors:
		blocked.append(Rect2(door - DOOR_HALF, -0.5, DOOR_HALF * 2.0, DOOR_DEPTH + 0.5))
	var lot_mid: float = (lot_u.x + lot_u.y) * 0.5
	var lot_half: float = (lot_u.y - lot_u.x) * 0.5
	var number: int = 0
	for spec: StreetPropSpec in street.furniture:
		var size: Vector3 = StreetPropSpec.size_of(spec.kind)
		var centre_v: float = BAND_HI - size.z * 0.5 if spec.zone == StreetPropSpec.Zone.KERB else BAND_LO + size.z * 0.5
		for copy: int in spec.count:
			number += 1
			var best: Placed = null
			var best_score: float = INF
			var steps: int = int((u_range.y - u_range.x) / STEP)
			for step: int in steps + 1:
				var u: float = u_range.x + float(step) * STEP
				var candidate: Placed = Placed.new()
				candidate.kind = spec.kind
				candidate.u = u
				candidate.v = centre_v
				candidate.size = size
				var rect: Rect2 = candidate.rect()
				if rect.position.x < u_range.x or rect.end.x > u_range.y or not _free(rect, blocked):
					continue
				var score: float = _r(number, step) * 1.6 + 0.1 * maxf(0.0, absf(u - lot_mid) - lot_half)
				score += _crowding(candidate, spec, lot_mid)
				if score < best_score:
					best_score = score
					best = candidate
			if best != null:
				best.seed_value = number
				placed.append(best)


func _free(rect: Rect2, blocked: Array[Rect2]) -> bool:
	for box: Rect2 in blocked:
		if rect.intersects(box):
			return false
	for other: Placed in placed:
		if rect.intersects(other.rect().grow(SPACING)):
			return false
	return true


## Costs that spread props out and put them where they read well.
func _crowding(candidate: Placed, spec: StreetPropSpec, lot_mid: float) -> float:
	var score: float = 0.0
	for other: Placed in placed:
		if other.kind == candidate.kind and absf(other.u - candidate.u) < StreetPropSpec.spacing_of(candidate.kind):
			score += 50.0
		elif candidate.kind == StreetPropSpec.Kind.BIN and (other.kind == StreetPropSpec.Kind.BENCH or other.kind == StreetPropSpec.Kind.BUS_STOP) \
				and absf(other.u - candidate.u) < other.size.x * 0.5 + 0.9:
			score -= 1.8
	if spec.zone == StreetPropSpec.Zone.WALL:
		for span: Vector2 in building_spans:
			if candidate.u - candidate.size.x * 0.5 >= span.x and candidate.u + candidate.size.x * 0.5 <= span.y:
				score -= 1.5
				break
	return score


## Planter trees' crown centres (u, v, height), where the drifting leaves start.
func tree_crowns() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for item: Placed in placed:
		if item.kind == StreetPropSpec.Kind.TREE_PLANTER:
			result.append(Vector3(item.u, item.v, 0.7))
	return result


# --- meshing ----------------------------------------------------------------

## The furniture mesh and its contact shadows, in the street's local frame. `lamps` are
## the street lamps' (u, v) feet: they get a shadow too.
func build_meshes(paving_top: float, shift: float, light_shift: Vector2, lamps: Array[Vector2]) -> Array[MeshInstance3D]:
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var shadows: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	for item: Placed in placed:
		pen.xf = Transform3D(Basis.IDENTITY, Vector3(item.u, paving_top, shift + item.v))
		_prop(pen, item)
		_shadow(shadows, item, paving_top + SHADOW_LIFT, shift, light_shift)
	for foot: Vector2 in lamps:
		_lamp_shadow(shadows, foot, paving_top + SHADOW_LIFT, shift, light_shift)
	var result: Array[MeshInstance3D] = []
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "PropBody"
	if not pen.soup.is_empty():
		if _material == null:
			_material = StandardMaterial3D.new()
			_material.vertex_color_use_as_albedo = true
			_material.roughness = 1.0
			_material.metallic_specular = 0.0
			_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			_material.disable_receive_shadows = true
		body.mesh = pen.soup.to_mesh()
		body.material_override = _material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.append(body)
	var shade: MeshInstance3D = MeshInstance3D.new()
	shade.name = "PropShadows"
	if not shadows.is_empty():
		var flat: StandardMaterial3D = StandardMaterial3D.new()
		flat.vertex_color_use_as_albedo = true
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flat.disable_receive_shadows = true
		shade.mesh = shadows.to_mesh()
		shade.material_override = flat
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.append(shade)
	return result


func _prop(pen: NeighbourhoodBuildings.Pen, item: Placed) -> void:
	match item.kind:
		StreetPropSpec.Kind.TREE_PLANTER:
			_tree(pen, item)
		StreetPropSpec.Kind.BENCH:
			_bench(pen, item)
		StreetPropSpec.Kind.BIN:
			_bin(pen, item)
		StreetPropSpec.Kind.BIKE_RACK:
			_bike_rack(pen)
		StreetPropSpec.Kind.HYDRANT:
			_hydrant(pen)
		StreetPropSpec.Kind.BUS_STOP:
			_bus_stop(pen, item)
		_:
			_postbox(pen)


## A frustum round (cx, cz), open at the bottom, closed on top.
func _drum(pen: NeighbourhoodBuildings.Pen, cx: float, cz: float, y0: float, y1: float, r0: float, r1: float,
		sides: int, colour: Color) -> void:
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var b0: Vector3 = Vector3(cx + cos(a0) * r0, y0, cz + sin(a0) * r0)
		var b1: Vector3 = Vector3(cx + cos(a1) * r0, y0, cz + sin(a1) * r0)
		var t0: Vector3 = Vector3(cx + cos(a0) * r1, y1, cz + sin(a0) * r1)
		var t1: Vector3 = Vector3(cx + cos(a1) * r1, y1, cz + sin(a1) * r1)
		var middle: Vector3 = (b0 + b1 + t0 + t1) * 0.25 - Vector3(cx, (y0 + y1) * 0.5, cz)
		pen.quad(b0, b1, t1, t0, middle, colour)
		pen.tri(Vector3(cx, y1, cz), t0, t1, Vector3.UP, colour)


func _tree(pen: NeighbourhoodBuildings.Pen, item: Placed) -> void:
	var wood: Color = street.wood
	pen.box(Vector3(-0.22, 0.0, -0.22), Vector3(0.22, 0.2, 0.22), wood)
	pen.box(Vector3(-0.25, 0.17, -0.25), Vector3(0.25, 0.22, 0.25), wood.lightened(0.16))
	pen.box(Vector3(-0.2, 0.22, -0.2), Vector3(0.2, 0.235, 0.2), wood.darkened(0.45))
	_drum(pen, 0.0, 0.0, 0.235, 0.5, 0.045, 0.035, 6, wood.darkened(0.25))
	var leaf: Color = street.hedge_colors[int(_r(item.seed_value, 3) * float(street.hedge_colors.size())) % street.hedge_colors.size()].lightened(0.14)
	var spin: float = _r(item.seed_value, 4) * TAU
	pen.lump(Vector3(0.0, 0.74, 0.0), 0.34, 0.3, 0.34, spin, leaf.lightened(0.05), leaf.darkened(0.2))
	pen.lump(Vector3(0.08, 0.98, -0.04), 0.23, 0.2, 0.23, spin + 0.6, leaf.lightened(0.16), leaf.darkened(0.08))
	pen.lump(Vector3(-0.17, 0.66, 0.11), 0.2, 0.17, 0.2, spin + 1.1, leaf, leaf.darkened(0.18))


func _bench(pen: NeighbourhoodBuildings.Pen, item: Placed) -> void:
	var paint: Color = street.wood
	if street.bin_colors.size() > 0 and _r(item.seed_value, 5) < 0.5:
		paint = street.bin_colors[int(_r(item.seed_value, 6) * float(street.bin_colors.size())) % street.bin_colors.size()].lightened(0.1)
	var metal: Color = street.metal
	for x: float in [-0.43, 0.43]:
		pen.box(Vector3(x - 0.035, 0.0, -0.15), Vector3(x + 0.035, 0.2, -0.1), metal)
		pen.box(Vector3(x - 0.035, 0.0, 0.1), Vector3(x + 0.035, 0.2, 0.15), metal)
		pen.box(Vector3(x - 0.035, 0.18, -0.17), Vector3(x + 0.035, 0.21, 0.17), metal)
		pen.box(Vector3(x - 0.035, 0.2, -0.2), Vector3(x + 0.035, 0.42, -0.17), metal)
	pen.box(Vector3(-0.5, 0.2, -0.17), Vector3(0.5, 0.245, -0.01), paint)
	pen.box(Vector3(-0.5, 0.2, 0.01), Vector3(0.5, 0.245, 0.17), paint)
	pen.box(Vector3(-0.5, 0.26, -0.2), Vector3(0.5, 0.33, -0.17), paint)
	pen.box(Vector3(-0.5, 0.35, -0.2), Vector3(0.5, 0.42, -0.17), paint)


func _bin(pen: NeighbourhoodBuildings.Pen, item: Placed) -> void:
	var tone: Color = street.bin_colors[int(_r(item.seed_value, 7) * float(street.bin_colors.size())) % street.bin_colors.size()] \
		if street.bin_colors.size() > 0 else street.metal
	_drum(pen, 0.0, 0.0, 0.0, 0.3, 0.095, 0.115, 8, tone)
	_drum(pen, 0.0, 0.0, 0.3, 0.335, 0.125, 0.115, 8, tone.darkened(0.2))
	pen.box(Vector3(-0.025, 0.335, -0.025), Vector3(0.025, 0.36, 0.025), tone.darkened(0.3))
	pen.box(Vector3(-0.09, 0.15, 0.1), Vector3(0.09, 0.2, 0.116), tone.lightened(0.2))


func _bike_rack(pen: NeighbourhoodBuildings.Pen) -> void:
	var metal: Color = street.bin_colors[0].darkened(0.1) if street.bin_colors.size() > 0 else street.metal
	for x: float in [-0.32, -0.1, 0.12, 0.34]:
		pen.box(Vector3(x - 0.014, 0.0, -0.1), Vector3(x + 0.014, 0.19, -0.072), metal)
		pen.box(Vector3(x - 0.014, 0.0, 0.072), Vector3(x + 0.014, 0.19, 0.1), metal)
		pen.box(Vector3(x - 0.014, 0.17, -0.1), Vector3(x + 0.014, 0.205, 0.1), metal)
	pen.box(Vector3(-0.4, 0.0, -0.115), Vector3(0.42, 0.02, 0.115), street.stone)


func _hydrant(pen: NeighbourhoodBuildings.Pen) -> void:
	var red: Color = street.signal_red
	var cap: Color = street.trim
	_drum(pen, 0.0, 0.0, 0.0, 0.07, 0.085, 0.08, 8, street.stone)
	_drum(pen, 0.0, 0.0, 0.07, 0.21, 0.062, 0.058, 8, red)
	_drum(pen, 0.0, 0.0, 0.21, 0.235, 0.075, 0.07, 8, red.darkened(0.2))
	pen.lump(Vector3(0.0, 0.235, 0.0), 0.05, 0.05, 0.05, 0.4, red.lightened(0.1), red)
	pen.box(Vector3(0.05, 0.12, -0.03), Vector3(0.095, 0.17, 0.03), cap)
	pen.box(Vector3(-0.095, 0.12, -0.03), Vector3(-0.05, 0.17, 0.03), cap)
	pen.box(Vector3(-0.03, 0.115, 0.05), Vector3(0.03, 0.17, 0.09), cap)


func _postbox(pen: NeighbourhoodBuildings.Pen) -> void:
	var red: Color = street.signal_red
	pen.box(Vector3(-0.11, 0.0, -0.11), Vector3(0.11, 0.04, 0.11), red.darkened(0.35))
	pen.box(Vector3(-0.1, 0.04, -0.1), Vector3(0.1, 0.38, 0.1), red)
	pen.box(Vector3(-0.11, 0.35, -0.11), Vector3(0.11, 0.4, 0.11), red.darkened(0.15))
	pen.lump(Vector3(0.0, 0.4, 0.0), 0.1, 0.11, 0.1, 0.785, red.lightened(0.1), red)
	pen.box(Vector3(-0.065, 0.27, 0.1), Vector3(0.065, 0.3, 0.115), Color("2b1f22"))
	pen.box(Vector3(-0.075, 0.1, 0.1), Vector3(0.075, 0.16, 0.112), street.trim)


func _bus_stop(pen: NeighbourhoodBuildings.Pen, item: Placed) -> void:
	var metal: Color = street.metal
	var roof: Color = street.bin_colors[0] if street.bin_colors.size() > 0 else street.roof_colors[0]
	# The sign pole stands at the shelter's right end, the shelter itself 1.4 m wide.
	for x: float in [-0.66, 0.66]:
		for z: float in [-0.3, 0.3]:
			pen.box(Vector3(x - 0.03, 0.0, z - 0.03), Vector3(x + 0.03, 0.96, z + 0.03), metal)
	pen.box(Vector3(-0.78, 0.96, -0.38), Vector3(0.78, 1.02, 0.38), roof)
	pen.box(Vector3(-0.8, 0.98, 0.34), Vector3(0.8, 1.06, 0.4), roof.lightened(0.18))
	pen.box(Vector3(-0.8, 0.98, -0.4), Vector3(0.8, 1.06, -0.34), roof.lightened(0.18))
	# A glass back and a bench inside.
	pen.box(Vector3(-0.63, 0.12, -0.3), Vector3(0.63, 0.9, -0.285), street.glass)
	pen.box(Vector3(-0.63, 0.48, -0.31), Vector3(0.63, 0.5, -0.28), metal)
	pen.box(Vector3(-0.5, 0.2, -0.27), Vector3(0.5, 0.24, -0.05), street.wood)
	for x: float in [-0.45, 0.45]:
		pen.box(Vector3(x - 0.025, 0.0, -0.24), Vector3(x + 0.025, 0.2, -0.08), metal)
	# The stop sign: a round blue plate on a pole, a lighter rim and a white bus-shaped bar.
	var pole_x: float = 0.9
	pen.box(Vector3(pole_x - 0.02, 0.0, 0.2), Vector3(pole_x + 0.02, 0.92, 0.24), metal)
	var plate: Color = street.glass.lerp(Color("4f78a8"), 0.6)
	pen.disc(pole_x, 0.98, 0.15, 0.2, 0.245, street.trim)
	pen.disc(pole_x, 0.98, 0.125, 0.2, 0.26, plate)
	pen.box(Vector3(pole_x - 0.08, 0.95, 0.2), Vector3(pole_x + 0.08, 1.01, 0.27), street.trim)


# --- baked shadows ----------------------------------------------------------

func _shadow(soup: NeighbourhoodGround.Soup, item: Placed, y: float, shift: float, light_shift: Vector2) -> void:
	var rect: Rect2 = item.rect()
	var points: PackedVector2Array = PackedVector2Array()
	var height: float = item.size.y
	match item.kind:
		StreetPropSpec.Kind.TREE_PLANTER:
			rect = rect.grow(-0.03)
			_push_corners(points, rect, light_shift * 0.22)
			var crown: Vector2 = Vector2(item.u, item.v) + light_shift * 0.72
			for index: int in 8:
				var angle: float = TAU * float(index) / 8.0
				points.append(crown + Vector2(cos(angle), sin(angle)) * 0.3)
		StreetPropSpec.Kind.BUS_STOP:
			rect = Rect2(item.u - 0.8, item.v - 0.4, 1.6, 0.8)
			_push_corners(points, rect, light_shift * 0.96)
			points.append(Vector2(item.u + 0.9, item.v + 0.22))
			points.append(Vector2(item.u + 0.9, item.v + 0.22) + light_shift * 0.9)
		StreetPropSpec.Kind.BIN, StreetPropSpec.Kind.HYDRANT:
			var centre: Vector2 = Vector2(item.u, item.v)
			var radius: float = 0.12 if item.kind == StreetPropSpec.Kind.BIN else 0.09
			for index: int in 8:
				var angle: float = TAU * float(index) / 8.0
				points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
				points.append(centre + Vector2(cos(angle), sin(angle)) * radius * 0.6 + light_shift * height * 0.8)
		_:
			rect = rect.grow(-0.02)
			_push_corners(points, rect, light_shift * height * 0.8)
	_emit_hull(soup, points, y, shift)


func _push_corners(points: PackedVector2Array, rect: Rect2, push: Vector2) -> void:
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		points.append(corner)
		points.append(corner + push)


func _lamp_shadow(soup: NeighbourhoodGround.Soup, foot: Vector2, y: float, shift: float, light_shift: Vector2) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	_push_corners(points, Rect2(foot - Vector2(0.09, 0.1), Vector2(0.18, 0.2)), Vector2.ZERO)
	var tip: Vector2 = foot + light_shift * 1.5
	var side: Vector2 = light_shift.orthogonal().normalized() * 0.03
	points.append(foot + side)
	points.append(foot - side)
	points.append(tip + side)
	points.append(tip - side)
	_emit_hull(soup, points, y, shift)


## The convex hull of `points` (u, v), laid flat at height `y` in the street's local frame.
func _emit_hull(soup: NeighbourhoodGround.Soup, points: PackedVector2Array, y: float, shift: float) -> void:
	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	if hull.size() < 4:
		return
	hull.remove_at(hull.size() - 1)
	var polygon: Array[Vector2] = []
	var centroid: Vector2 = Vector2.ZERO
	for point: Vector2 in hull:
		polygon.append(Vector2(point.x, point.y + shift))
		centroid += polygon[polygon.size() - 1]
	centroid /= float(polygon.size())
	soup.star(centroid, polygon, y, SHADOW_COLOUR)
