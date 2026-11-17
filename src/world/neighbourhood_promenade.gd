class_name NeighbourhoodPromenade
extends RefCounted
## The car-free promenade in front of a seaside terrace (#596, D39): the paving's
## pattern (slab joints, a centre band edged in a darker stone with a wave inlaid down
## it), the double-lantern lamp posts along that band, and the little things the
## people out walking have with them (a bike, a pram, a dog). Colours come from the
## street's PromenadeSkin. Like the rest of the street it is view-only and built from
## vertex-coloured boxes in the street's local frame (u along the street, v across the
## paving from the shop fronts); no random draws, so a rebuild is identical.

## The centre band's middle (v) and half width: the lamps, benches and planters stand on it.
const BAND_V: float = 4.6
const BAND_HALF: float = 0.55
const BAND_EDGE: float = 0.07
## The wave inlaid down the band: its swing, wavelength and stroke.
const WAVE_SWING: float = 0.2
const WAVE_LENGTH: float = 1.7
const WAVE_STROKE: float = 0.07
const WAVE_STEP: float = 0.17
## Slab joints across the walking paving: their pitch and width.
const JOINT_STEP: float = 0.92
const JOINT_WIDTH: float = 0.018
const LIFT: float = 0.004
## The lamp post: the lanterns' centre height and their spread either side of the post.
const LANTERN_Y: float = 1.6
const LANTERN_SPREAD: float = 0.24
const LAMP_FOOT: Vector2 = Vector2(0.34, 0.34)

var skin: PromenadeSkin
var street: StreetSet


func _init(promenade: PromenadeSkin, building_set: StreetSet) -> void:
	skin = promenade
	street = building_set


## The paving's pattern from `u_from` to `u_to`, between v 0 and `depth`, at height `y`.
## `holes` (u, v rects) are left bare: the lot's own entrance pads.
func pattern(u_from: float, u_to: float, depth: float, y: float, holes: Array[Rect2]) -> ArrayMesh:
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var top: float = y + LIFT
	# Joints across the two walking strips either side of the band.
	var strips: Array[Vector2] = [Vector2(0.0, BAND_V - BAND_HALF), Vector2(BAND_V + BAND_HALF, depth)]
	var joints: int = int((u_to - u_from) / JOINT_STEP)
	for index: int in joints:
		var u: float = u_from + (float(index) + 0.5) * JOINT_STEP
		for strip: Vector2 in strips:
			var rect: Rect2 = Rect2(u - JOINT_WIDTH * 0.5, strip.x, JOINT_WIDTH, strip.y - strip.x)
			if _clear(rect, holes):
				_rect(soup, rect, top, skin.joint)
	# A long joint down each walking strip, so the slabs read as a grid.
	for v: float in [(BAND_V - BAND_HALF) * 0.5, (BAND_V + BAND_HALF + depth) * 0.5]:
		var rect: Rect2 = Rect2(u_from, v - JOINT_WIDTH * 0.5, u_to - u_from, JOINT_WIDTH)
		_rect(soup, rect, top, skin.joint)
	# The centre band, its edging and the wave.
	_rect(soup, Rect2(u_from, BAND_V - BAND_HALF, u_to - u_from, BAND_HALF * 2.0), top + 0.0005, skin.band)
	for edge: float in [BAND_V - BAND_HALF, BAND_V + BAND_HALF - BAND_EDGE]:
		_rect(soup, Rect2(u_from, edge, u_to - u_from, BAND_EDGE), top + 0.001, skin.band_edge)
	var steps: int = int((u_to - u_from) / WAVE_STEP)
	var last: Vector2 = _wave(u_from)
	for index: int in range(1, steps + 1):
		var point: Vector2 = _wave(u_from + float(index) * WAVE_STEP)
		var along: Vector2 = (point - last).normalized()
		var side: Vector2 = Vector2(-along.y, along.x) * WAVE_STROKE * 0.5
		var corners: Array[Vector2] = [last - side, point - side, point + side, last + side]
		soup.flat(corners, top + 0.0015, skin.wave)
		last = point
	return soup.to_mesh()


func _wave(u: float) -> Vector2:
	return Vector2(u, BAND_V + sin(u * TAU / WAVE_LENGTH) * WAVE_SWING)


static func _clear(rect: Rect2, holes: Array[Rect2]) -> bool:
	for hole: Rect2 in holes:
		if rect.intersects(hole):
			return false
	return true


static func _rect(soup: NeighbourhoodGround.Soup, rect: Rect2, y: float, colour: Color) -> void:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	soup.flat(corners, y, colour)


## Lamp posts along the band, `skin.lamp_spacing` apart, centred on `centre_u`, from
## `u_from` to `u_to`, skipping any whose foot would land in `holes`.
func lamp_spots(centre_u: float, u_from: float, u_to: float, holes: Array[Rect2]) -> Array[float]:
	var spots: Array[float] = []
	var first: int = ceili((u_from - centre_u) / skin.lamp_spacing - 0.5)
	var last: int = floori((u_to - centre_u) / skin.lamp_spacing - 0.5)
	for index: int in range(first, last + 1):
		var u: float = centre_u + (float(index) + 0.5) * skin.lamp_spacing
		var foot: Rect2 = Rect2(u - LAMP_FOOT.x * 0.5, BAND_V - LAMP_FOOT.y * 0.5, LAMP_FOOT.x, LAMP_FOOT.y)
		if _clear(foot, holes):
			spots.append(u)
	return spots


## One double-lantern lamp post standing at the pen's origin, lanterns along u.
## Returns the lanterns' local centres (the bulbs the night level lights).
func lamp_post(pen: NeighbourhoodBuildings.Pen) -> Array[Vector3]:
	var iron: Color = skin.iron
	var trim: Color = skin.iron_trim
	# A fluted base, the column, a collar and the scrolled crossbar.
	pen.box(Vector3(-0.13, 0.0, -0.13), Vector3(0.13, 0.08, 0.13), iron.darkened(0.1))
	pen.box(Vector3(-0.1, 0.08, -0.1), Vector3(0.1, 0.3, 0.1), iron)
	pen.box(Vector3(-0.115, 0.28, -0.115), Vector3(0.115, 0.32, 0.115), trim)
	pen.box(Vector3(-0.04, 0.32, -0.04), Vector3(0.04, 1.42, 0.04), iron)
	pen.box(Vector3(-0.06, 0.8, -0.06), Vector3(0.06, 0.84, 0.06), trim)
	pen.box(Vector3(-0.06, 1.4, -0.06), Vector3(0.06, 1.45, 0.06), trim)
	pen.box(Vector3(-LANTERN_SPREAD - 0.02, 1.45, -0.025), Vector3(LANTERN_SPREAD + 0.02, 1.49, 0.025), iron)
	for side: float in [-1.0, 1.0]:
		pen.box(Vector3(side * 0.13 - 0.012, 1.38, -0.012), Vector3(side * 0.13 + 0.012, 1.45, 0.012), iron)
	pen.lump(Vector3(0.0, 1.53, 0.0), 0.04, 0.05, 0.04, 0.4, trim, trim.darkened(0.2))
	var lanterns: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var x: float = side * LANTERN_SPREAD
		pen.box(Vector3(x - 0.012, 1.49, -0.012), Vector3(x + 0.012, 1.53, 0.012), iron)
		# The lantern: a cap, four thin posts round the glass and a little finial.
		pen.box(Vector3(x - 0.08, 1.71, -0.08), Vector3(x + 0.08, 1.75, 0.08), iron)
		pen.box(Vector3(x - 0.05, 1.75, -0.05), Vector3(x + 0.05, 1.79, 0.05), iron)
		pen.box(Vector3(x - 0.012, 1.79, -0.012), Vector3(x + 0.012, 1.83, 0.012), trim)
		pen.box(Vector3(x - 0.065, 1.52, -0.065), Vector3(x + 0.065, 1.55, 0.065), iron)
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			pen.box(Vector3(x + corner.x * 0.06 - 0.01, 1.55, corner.y * 0.06 - 0.01), Vector3(x + corner.x * 0.06 + 0.01, 1.71, corner.y * 0.06 + 0.01), iron)
		lanterns.append(Vector3(x, LANTERN_Y + 0.03, 0.0))
	return lanterns


# --- what the walkers have with them ---------------------------------------------

## A bicycle, built along +z (the way it rides), wheels on the ground at y 0.
func bike(colour: Color) -> ArrayMesh:
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var tyre: Color = Color("45342b")
	var metal: Color = street.metal
	for z: float in [-0.27, 0.27]:
		_wheel(pen, z, 0.15, tyre, metal)
	# The frame: a down tube, a top tube, the seat and the bars.
	pen.box(Vector3(-0.015, 0.15, -0.27), Vector3(0.015, 0.18, 0.05), colour)
	pen.box(Vector3(-0.015, 0.16, -0.05), Vector3(0.015, 0.36, -0.02), colour)
	pen.box(Vector3(-0.015, 0.32, -0.04), Vector3(0.015, 0.35, 0.24), colour)
	pen.box(Vector3(-0.015, 0.15, 0.22), Vector3(0.015, 0.42, 0.25), colour)
	pen.box(Vector3(-0.04, 0.36, -0.1), Vector3(0.04, 0.39, 0.0), Color("45342b"))
	pen.box(Vector3(-0.11, 0.42, 0.21), Vector3(0.11, 0.44, 0.24), metal)
	pen.box(Vector3(-0.05, 0.2, 0.25), Vector3(0.05, 0.27, 0.33), street.trim)
	return pen.soup.to_mesh()


func _wheel(pen: NeighbourhoodBuildings.Pen, z: float, radius: float, tyre: Color, hub: Color) -> void:
	var sides: int = 10
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var p0: Vector3 = Vector3(0.0, radius + sin(a0) * radius, z + cos(a0) * radius)
		var p1: Vector3 = Vector3(0.0, radius + sin(a1) * radius, z + cos(a1) * radius)
		var q0: Vector3 = Vector3(0.0, radius + sin(a0) * radius * 0.8, z + cos(a0) * radius * 0.8)
		var q1: Vector3 = Vector3(0.0, radius + sin(a1) * radius * 0.8, z + cos(a1) * radius * 0.8)
		for x: float in [-0.022, 0.022]:
			var out: Vector3 = Vector3(signf(x), 0.0, 0.0)
			pen.quad(p0 + Vector3(x, 0, 0), p1 + Vector3(x, 0, 0), q1 + Vector3(x, 0, 0), q0 + Vector3(x, 0, 0), out, tyre)
		var mid: Vector3 = (p0 + p1) * 0.5 - Vector3(0.0, radius, z)
		pen.quad(p0 + Vector3(-0.022, 0, 0), p1 + Vector3(-0.022, 0, 0), p1 + Vector3(0.022, 0, 0), p0 + Vector3(0.022, 0, 0), mid, tyre)
	pen.box(Vector3(-0.02, radius - 0.02, z - 0.02), Vector3(0.02, radius + 0.02, z + 0.02), hub)


## A pram, pushed along +z from its handle at z 0.
func pram(colour: Color) -> ArrayMesh:
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var metal: Color = street.metal
	var tyre: Color = Color("45342b")
	for z: float in [0.2, 0.46]:
		for x: float in [-0.12, 0.12]:
			pen.box(Vector3(x - 0.015, 0.0, z - 0.05), Vector3(x + 0.015, 0.1, z + 0.05), tyre)
	pen.box(Vector3(-0.13, 0.08, 0.2), Vector3(0.13, 0.11, 0.46), metal)
	# The body, its lining and the folded hood at the handle end.
	pen.box(Vector3(-0.12, 0.13, 0.18), Vector3(0.12, 0.33, 0.5), colour)
	pen.box(Vector3(-0.1, 0.32, 0.22), Vector3(0.1, 0.335, 0.46), street.trim)
	var hood: Array[Vector3] = [Vector3(-0.125, 0.33, 0.18), Vector3(0.125, 0.33, 0.18), Vector3(0.125, 0.5, 0.26), Vector3(-0.125, 0.5, 0.26)]
	pen.slab(hood, Vector3(0.0, 0.0, 0.08), colour.darkened(0.12))
	pen.box(Vector3(-0.125, 0.33, 0.26), Vector3(0.125, 0.5, 0.3), colour.darkened(0.12))
	# The handle reaches back to the walker's hands.
	for x: float in [-0.1, 0.1]:
		pen.box(Vector3(x - 0.012, 0.3, 0.02), Vector3(x + 0.012, 0.34, 0.2), metal)
	pen.box(Vector3(-0.13, 0.32, 0.0), Vector3(0.13, 0.35, 0.03), metal.darkened(0.3))
	return pen.soup.to_mesh()


## A small dog's body (head toward +z) and one leg, which the view swings as it trots.
func dog_body(colour: Color) -> ArrayMesh:
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var dark: Color = colour.darkened(0.25)
	pen.box(Vector3(-0.06, 0.1, -0.13), Vector3(0.06, 0.2, 0.11), colour)
	pen.box(Vector3(-0.055, 0.14, 0.08), Vector3(0.055, 0.26, 0.2), colour)
	pen.box(Vector3(-0.035, 0.15, 0.2), Vector3(0.035, 0.21, 0.26), colour.lightened(0.12))
	pen.box(Vector3(-0.015, 0.19, 0.255), Vector3(0.015, 0.215, 0.27), Color("2b1f22"))
	for x: float in [-0.04, 0.04]:
		pen.box(Vector3(x - 0.018, 0.22, 0.1), Vector3(x + 0.018, 0.3, 0.13), dark)
	pen.box(Vector3(-0.06, 0.19, 0.075), Vector3(0.06, 0.21, 0.09), street.signal_red)
	pen.box(Vector3(-0.012, 0.18, -0.2), Vector3(0.012, 0.29, -0.13), dark)
	return pen.soup.to_mesh()


func dog_leg(colour: Color) -> ArrayMesh:
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	pen.box(Vector3(-0.02, -0.12, -0.02), Vector3(0.02, 0.0, 0.02), colour.darkened(0.12))
	return pen.soup.to_mesh()
