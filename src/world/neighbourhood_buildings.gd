class_name NeighbourhoodBuildings
extends RefCounted
## The street's buildings (#422): a row of little shopfronts on each side of the
## player's lot, and a row of houses across the road, each on its own lot with a
## path, yard and low fence. View-only: generated vertex-coloured boxes (one mesh
## per building, one shared flat-shaded material, no shadows, lights, colliders or
## random draws). Every choice is an integer hash of the building's index and a
## StreetSet seed, so a rebuild is identical. Geometry is authored in the street's
## local frame (u along the street, z outward from the shop); the owner parents it
## under that frame. All colours, shapes and shops come from the StreetSet.
##
## Shops never shade the lot: the gap to the lot is at least half the tallest
## roof (the camera looks down at 54.7 degrees, so a point h metres up hides
## ground h * cos(pitch) = 0.5 h per axis along a diagonal view).

## Clear ground between the player's maximum lot and the nearest shop's wall.
const GAP: float = 1.4
## Shops sit this far inside the street line so their awnings hang over the paving.
const FRONT_INSET: float = 0.05
## A hairline between row neighbours (roof eaves overhang less than half of it).
const ROW_GAP: float = 0.22
## The tallest a near shop or its roof may stand: GAP / 0.5 less a margin.
const MAX_NEAR_HEIGHT: float = 2.7
## Street-edge distance of every house lot's front fence line.
const FENCE_V: float = 8.7
const PAVEMENT_EDGE_V: float = 8.22
const FLAT_Y: float = -0.026
const AWNING_REACH: float = 0.36
const DOOR_H: float = 1.0
const EAVE: float = 0.08

class Plan extends RefCounted:
	var id: String = ""
	var is_shop: bool = false
	var style: ShopStyle
	## Building-local (facade centre on the ground, facade facing +z, body behind it) to street-local.
	var xf: Transform3D = Transform3D.IDENTITY
	var width: float = 3.0
	var depth: float = 3.0
	var wall_h: float = 1.5
	var roof_h: float = 0.5
	var roof: int = 0
	var wall: Color = Color.WHITE
	var roof_col: Color = Color.WHITE
	var door_col: Color = Color.WHITE
	var door_x: float = 0.0
	var seed_value: int = 0
	## Local sides with a free wall: bit 1 = +x, bit 2 = -x.
	var exposed: int = 3
	var fence: int = 0
	var chimney: bool = false
	var hood: bool = false
	var flowers: bool = false
	var shutters: bool = false
	var mailbox: bool = false
	## Street-local box of the whole building including its roof, awning and steps.
	var bounds: AABB = AABB()
	var lot: Rect2 = Rect2()
	var lot_index: int = 0

	func total_height() -> float:
		return wall_h + roof_h


var street: StreetSet
var local_reserve: AABB = AABB()
var shift: float = 0.0
## Top of the pavement the awnings' stock stands on.
var paving_top: float = 0.055
var plans: Array[Plan] = []


func _r(index: int, attribute: int) -> float:
	return NeighbourhoodGround.hash01(index, attribute, street.seed_salt)


func _pick(count: int, index: int, attribute: int) -> int:
	return mini(count - 1, int(_r(index, attribute) * float(count)))


## A palette index that differs from the previous building's.
func _pick_distinct(count: int, index: int, attribute: int, previous: Array[int]) -> int:
	var choice: int = _pick(count, index, attribute)
	var guard: int = 0
	while count > previous.size() and previous.has(choice) and guard < count:
		choice = (choice + 1) % count
		guard += 1
	return choice


# --- planning ---------------------------------------------------------------

func plan() -> void:
	plans.clear()
	if street == null:
		street = StreetSet.standard()
	_plan_shops()
	_plan_houses()


func _shop_order() -> Array[int]:
	var order: Array[int] = []
	for index: int in street.shops.size():
		order.append(index)
	# A hashed shuffle, so which business stands where is stable but not alphabetical.
	for index: int in range(order.size() - 1, 0, -1):
		var other: int = int(_r(index, 90) * float(index + 1))
		var swap: int = order[index]
		order[index] = order[other]
		order[other] = swap
	return order


func _plan_shops() -> void:
	var order: Array[int] = _shop_order()
	var recent_h: Array[int] = []
	var recent_roof: Array[int] = []
	for side_index: int in 2:
		var side: float = -1.0 if side_index == 0 else 1.0
		var edge: float = local_reserve.position.x - GAP if side < 0.0 else local_reserve.end.x + GAP
		recent_h.clear()
		recent_roof.clear()
		for slot: int in street.shops_per_side:
			var index: int = side_index * street.shops_per_side + slot
			var p: Plan = Plan.new()
			p.id = "Shop%d" % index
			p.is_shop = true
			p.seed_value = index
			p.style = street.shops[order[index % order.size()]] if not order.is_empty() else null
			p.width = 2.6 + 0.1 * float(int(_r(index, 1) * 9.0))
			p.depth = 3.2 + 0.2 * float(int(_r(index, 2) * 7.0))
			var height_choice: int = _pick_distinct(street.shop_heights.size(), index, 3, recent_h)
			recent_h = [height_choice]
			p.wall_h = street.shop_heights[height_choice]
			var roof_choice: int = _pick_distinct(street.shop_roofs.size(), index, 4, recent_roof)
			recent_roof = [roof_choice]
			p.roof = street.shop_roofs[roof_choice]
			p.roof_h = _roof_height(p.roof, index)
			while p.total_height() > MAX_NEAR_HEIGHT and p.roof_h > 0.2:
				p.roof_h -= 0.05
			p.wall = p.style.wall if p.style != null else street.wall_colors[0]
			p.roof_col = street.roof_colors[_pick(street.roof_colors.size(), index, 5)]
			p.door_col = p.style.door if p.style != null else street.door_colors[0]
			p.door_x = (-1.0 if _r(index, 6) < 0.5 else 1.0) * (p.width * 0.5 - 0.42)
			var centre: float = edge + side * p.width * 0.5
			edge += side * (p.width + ROW_GAP)
			p.xf = Transform3D(Basis.IDENTITY, Vector3(centre, 0.0, shift - FRONT_INSET))
			# The wall facing the lot is free, the one touching the next shop is not,
			# and the far end of the row is free again.
			var toward_lot: int = 1 if side < 0.0 else 2
			var outward: int = 2 if side < 0.0 else 1
			p.exposed = toward_lot if slot == 0 else 0
			if slot == street.shops_per_side - 1:
				p.exposed |= outward
			p.flowers = _r(index, 7) < 0.4
			p.bounds = _bounds_of(p)
			plans.append(p)


func _roof_height(roof: int, index: int) -> float:
	match roof:
		StreetSet.Roof.GABLE_FRONT, StreetSet.Roof.GABLE_SIDE:
			return 0.42 + 0.06 * float(int(_r(index, 8) * 4.0))
		StreetSet.Roof.HIP:
			return 0.36 + 0.05 * float(int(_r(index, 8) * 3.0))
		StreetSet.Roof.PYRAMID:
			return 0.42 + 0.04 * float(int(_r(index, 8) * 3.0))
		StreetSet.Roof.SHED:
			return 0.32
		StreetSet.Roof.FLAT:
			return 0.2
		_:
			return 0.56


func _plan_houses() -> void:
	var widths: Array[float] = []
	var total: float = 0.0
	for index: int in street.house_count:
		var lot_width: float = 4.0 + 0.2 * float(int(_r(20 + index, 1) * 5.0))
		widths.append(lot_width)
		total += lot_width
	var centre_u: float = local_reserve.position.x + local_reserve.size.x * 0.5
	var cursor: float = centre_u - total * 0.5
	var recent_wall: Array[int] = []
	var recent_roof: Array[int] = []
	var recent_h: Array[int] = []
	for index: int in street.house_count:
		var key: int = 20 + index
		var p: Plan = Plan.new()
		p.id = "House%d" % index
		p.lot_index = index
		p.seed_value = key
		var lot_width: float = widths[index]
		p.width = lot_width - 1.3
		p.depth = 2.4 + 0.15 * float(int(_r(key, 2) * 5.0))
		var height_choice: int = _pick_distinct(street.house_heights.size(), key, 3, recent_h)
		recent_h = [height_choice]
		p.wall_h = street.house_heights[height_choice]
		var roof_choice: int = _pick_distinct(street.house_roofs.size(), key, 4, recent_roof)
		recent_roof = [roof_choice]
		p.roof = street.house_roofs[roof_choice]
		p.roof_h = _roof_height(p.roof, key)
		var wall_choice: int = _pick_distinct(street.wall_colors.size(), key, 5, recent_wall)
		recent_wall.append(wall_choice)
		if recent_wall.size() > 2:
			recent_wall.pop_front()
		p.wall = street.wall_colors[wall_choice]
		p.roof_col = street.roof_colors[_pick(street.roof_colors.size(), key, 9)]
		p.door_col = street.door_colors[_pick(street.door_colors.size(), key, 10)]
		p.door_x = 0.0 if _r(key, 11) < 0.5 else (-1.0 if _r(key, 12) < 0.5 else 1.0) * p.width * 0.22
		p.chimney = _r(key, 13) < 0.55 and p.roof != StreetSet.Roof.PYRAMID
		p.hood = _r(key, 14) < 0.45
		p.flowers = _r(key, 15) < 0.55
		p.shutters = _r(key, 16) < 0.4
		p.mailbox = _r(key, 17) < 0.6
		p.fence = street.fences[_pick(street.fences.size(), key, 18)]
		var front_yard: float = 1.4 + 0.1 * float(int(_r(key, 19) * 6.0))
		var door_plane: float = shift + FENCE_V + front_yard
		var lot_centre: float = cursor + lot_width * 0.5
		var offset: float = (_r(key, 20) - 0.5) * 0.3
		# Facing the street (-z): local +z maps to street -z, local +x to street -u.
		p.xf = Transform3D(Basis(Vector3.UP, PI), Vector3(lot_centre + offset, 0.0, door_plane))
		p.lot = Rect2(cursor, shift + FENCE_V, lot_width, front_yard + p.depth + 0.95)
		cursor += lot_width
		p.bounds = _bounds_of(p)
		plans.append(p)


func _bounds_of(p: Plan) -> AABB:
	var half: float = p.width * 0.5 + EAVE + 0.02
	var front: float = AWNING_REACH + 0.04 if p.is_shop else 0.34
	var height: float = p.total_height() + (0.22 if p.chimney else 0.0)
	var local: AABB = AABB(Vector3(-half, 0.0, -p.depth - EAVE), Vector3(half * 2.0, height, p.depth + EAVE + front))
	return p.xf * local


## Every building's street-local box, with its true height in y (awnings and steps included).
func footprints() -> Array[AABB]:
	var result: Array[AABB] = []
	for p: Plan in plans:
		result.append(p.bounds)
	return result


## House lots, flat: the yard, fence and path run to their edges.
func lots() -> Array[AABB]:
	var result: Array[AABB] = []
	for p: Plan in plans:
		if not p.is_shop:
			result.append(AABB(Vector3(p.lot.position.x, 0.0, p.lot.position.y), Vector3(p.lot.size.x, 0.0, p.lot.size.y)))
	return result


## Boxes whose baked shadow lands on the lawn: each wall block at wall height and
## a narrower core at the full roof height.
func casters() -> Array[AABB]:
	var result: Array[AABB] = []
	for p: Plan in plans:
		result.append(p.xf * AABB(Vector3(-p.width * 0.5, 0.0, -p.depth), Vector3(p.width, p.wall_h, p.depth)))
		var core: Vector2 = Vector2(p.width, p.depth)
		match p.roof:
			StreetSet.Roof.GABLE_FRONT:
				core.x *= 0.3
			StreetSet.Roof.GABLE_SIDE:
				core.y *= 0.3
			StreetSet.Roof.HIP, StreetSet.Roof.PYRAMID:
				core *= 0.3
		result.append(p.xf * AABB(Vector3(-core.x * 0.5, 0.0, -p.depth * 0.5 - core.y * 0.5), Vector3(core.x, p.total_height(), core.y)))
	return result


# --- geometry ---------------------------------------------------------------

## A pen draws boxes, slabs and flats through one transform into a shared soup.
class Pen extends RefCounted:
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var xf: Transform3D = Transform3D.IDENTITY

	func tri(a: Vector3, b: Vector3, c: Vector3, hint: Vector3, colour: Color) -> void:
		soup.tri(xf * a, xf * b, xf * c, xf.basis * hint, colour)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3, colour: Color) -> void:
		tri(a, b, c, hint, colour)
		tri(a, c, d, hint, colour)

	## An axis-aligned box without a floor.
	func box(lo: Vector3, hi: Vector3, colour: Color) -> void:
		var a: Vector3 = Vector3(lo.x, lo.y, lo.z)
		var b: Vector3 = Vector3(hi.x, lo.y, lo.z)
		var c: Vector3 = Vector3(hi.x, hi.y, lo.z)
		var d: Vector3 = Vector3(lo.x, hi.y, lo.z)
		var e: Vector3 = Vector3(lo.x, lo.y, hi.z)
		var f: Vector3 = Vector3(hi.x, lo.y, hi.z)
		var g: Vector3 = Vector3(hi.x, hi.y, hi.z)
		var h: Vector3 = Vector3(lo.x, hi.y, hi.z)
		quad(d, c, g, h, Vector3.UP, colour)
		quad(a, b, c, d, Vector3.FORWARD, colour)
		quad(e, f, g, h, Vector3.BACK, colour)
		quad(b, f, g, c, Vector3.RIGHT, colour)
		quad(e, a, d, h, Vector3.LEFT, colour)

	## A thin plate: a base quad pushed along `off` (the roof slabs and awning stripes).
	func slab(base: Array[Vector3], off: Vector3, colour: Color) -> void:
		var top: Array[Vector3] = []
		var centre: Vector3 = Vector3.ZERO
		for point: Vector3 in base:
			top.append(point + off)
			centre += point + off * 0.5
		centre /= float(base.size())
		quad(top[0], top[1], top[2], top[3], off, colour)
		for index: int in 4:
			var next: int = (index + 1) % 4
			var middle: Vector3 = (base[index] + base[next] + top[index] + top[next]) * 0.25
			quad(base[index], base[next], top[next], top[index], middle - centre, colour)

	func flat(x0: float, z0: float, x1: float, z1: float, y: float, colour: Color) -> void:
		quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, colour)

	## A short eight-sided disc facing +z (portholes, round windows).
	func disc(cx: float, cy: float, radius: float, z0: float, z1: float, colour: Color) -> void:
		var ring: Array[Vector2] = []
		for index: int in 8:
			var angle: float = TAU * (float(index) + 0.5) / 8.0
			ring.append(Vector2(cos(angle), sin(angle)) * radius)
		for index: int in 8:
			var next: int = (index + 1) % 8
			var a: Vector2 = ring[index]
			var b: Vector2 = ring[next]
			tri(Vector3(cx, cy, z1), Vector3(cx + a.x, cy + a.y, z1), Vector3(cx + b.x, cy + b.y, z1), Vector3.BACK, colour)
			var middle: Vector3 = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0.0)
			quad(Vector3(cx + a.x, cy + a.y, z0), Vector3(cx + b.x, cy + b.y, z0), Vector3(cx + b.x, cy + b.y, z1),
				Vector3(cx + a.x, cy + a.y, z1), middle, colour)

	## A chunky low-poly lump (bushes, treetops, flower heads): two fans round a ring.
	func lump(centre: Vector3, rx: float, ry: float, rz: float, spin: float, top: Color, bottom: Color) -> void:
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


func build_mesh(p: Plan) -> MeshInstance3D:
	var pen: Pen = Pen.new()
	pen.xf = p.xf
	_body(pen, p)
	if p.is_shop:
		_shop_front(pen, p)
	else:
		_house_front(pen, p)
	_side_and_back(pen, p)
	_roof(pen, p)
	if p.chimney:
		_chimney(pen, p)
	if not p.is_shop:
		_yard(pen, p)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = p.id
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.disable_receive_shadows = true
	instance.mesh = pen.soup.to_mesh()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _body(pen: Pen, p: Plan) -> void:
	var hw: float = p.width * 0.5
	pen.box(Vector3(-hw, 0.0, -p.depth), Vector3(hw, p.wall_h, 0.0), p.wall)
	# A low stone plinth on every side.
	var plinth: Color = street.stone
	pen.box(Vector3(-hw - 0.015, 0.0, -p.depth - 0.015), Vector3(hw + 0.015, 0.1, 0.015), plinth)


# --- facades ----------------------------------------------------------------

func _door(pen: Pen, x: float, width: float, colour: Color, glazed: bool) -> void:
	var half: float = width * 0.5
	pen.box(Vector3(x - half - 0.05, 0.0, 0.0), Vector3(x + half + 0.05, DOOR_H + 0.05, 0.015), street.trim)
	pen.box(Vector3(x - half, 0.0, 0.0), Vector3(x + half, DOOR_H, 0.03), colour)
	var pane: Color = street.glass if glazed else colour.lightened(0.14)
	pen.box(Vector3(x - half + 0.07, DOOR_H * 0.48, 0.0), Vector3(x + half - 0.07, DOOR_H - 0.1, 0.04), pane)
	pen.box(Vector3(x + half - 0.11, DOOR_H * 0.38, 0.0), Vector3(x + half - 0.06, DOOR_H * 0.38 + 0.05, 0.055), Color("c9a23a"))
	pen.box(Vector3(x - half - 0.07, 0.0, 0.0), Vector3(x + half + 0.07, 0.045, 0.2), street.stone.lightened(0.08))


func _window(pen: Pen, cx: float, cy: float, width: float, height: float, shutters: bool, flowers: bool, seed_value: int) -> void:
	var hw: float = width * 0.5
	var hh: float = height * 0.5
	pen.box(Vector3(cx - hw - 0.045, cy - hh - 0.045, 0.0), Vector3(cx + hw + 0.045, cy + hh + 0.045, 0.014), street.trim)
	pen.box(Vector3(cx - hw, cy - hh, 0.0), Vector3(cx + hw, cy + hh, 0.026), street.glass)
	pen.box(Vector3(cx - 0.012, cy - hh, 0.0), Vector3(cx + 0.012, cy + hh, 0.036), street.trim)
	pen.box(Vector3(cx - hw, cy - 0.012, 0.0), Vector3(cx + hw, cy + 0.012, 0.034), street.trim)
	pen.box(Vector3(cx - hw - 0.07, cy - hh - 0.08, 0.0), Vector3(cx + hw + 0.07, cy - hh - 0.045, 0.07), street.trim)
	if shutters:
		var tone: Color = street.door_colors[seed_value % street.door_colors.size()]
		pen.box(Vector3(cx - hw - 0.17, cy - hh - 0.045, 0.0), Vector3(cx - hw - 0.045, cy + hh + 0.045, 0.02), tone)
		pen.box(Vector3(cx + hw + 0.045, cy - hh - 0.045, 0.0), Vector3(cx + hw + 0.17, cy + hh + 0.045, 0.02), tone)
	if flowers:
		var box_top: float = cy - hh - 0.05
		pen.box(Vector3(cx - hw, box_top - 0.11, 0.01), Vector3(cx + hw, box_top, 0.1), street.wood)
		pen.box(Vector3(cx - hw + 0.02, box_top, 0.02), Vector3(cx + hw - 0.02, box_top + 0.04, 0.09), street.hedge_colors[0])
		for index: int in 4:
			var along: float = cx - hw + 0.07 + float(index) * (width - 0.14) / 3.0
			var bloom: Color = street.bloom_colors[(seed_value + index) % street.bloom_colors.size()]
			pen.box(Vector3(along - 0.03, box_top + 0.04, 0.035), Vector3(along + 0.03, box_top + 0.1, 0.085), bloom)


func _house_front(pen: Pen, p: Plan) -> void:
	var hw: float = p.width * 0.5
	_door(pen, p.door_x, 0.5, p.door_col, false)
	var cy: float = minf(0.85, p.wall_h * 0.56)
	var placed: int = 0
	for side: float in [-1.0, 1.0]:
		var cx: float = side * (hw - 0.55)
		if absf(cx - p.door_x) < 0.62:
			continue
		_window(pen, cx, cy, 0.42, 0.42, p.shutters, p.flowers, p.seed_value + placed)
		placed += 1
	if placed == 0:
		_window(pen, -signf(p.door_x) * (hw - 0.55), cy, 0.42, 0.42, p.shutters, p.flowers, p.seed_value)
	if p.hood:
		var x0: float = p.door_x - 0.42
		var x1: float = p.door_x + 0.42
		var base: Array[Vector3] = [Vector3(x0, DOOR_H + 0.16, 0.0), Vector3(x1, DOOR_H + 0.16, 0.0),
			Vector3(x1, DOOR_H + 0.05, 0.34), Vector3(x0, DOOR_H + 0.05, 0.34)]
		pen.slab(base, Vector3(0.0, 0.04, 0.02), p.roof_col)
		for post: float in [x0 + 0.03, x1 - 0.03]:
			pen.box(Vector3(post - 0.025, 0.0, 0.29), Vector3(post + 0.025, DOOR_H + 0.05, 0.34), street.trim)
	if p.wall_h >= 1.7:
		var upper: float = p.wall_h - 0.38
		_window(pen, p.door_x, upper, 0.36, 0.34, false, false, p.seed_value + 3)
	if p.roof == StreetSet.Roof.GABLE_FRONT:
		pen.disc(0.0, p.wall_h + p.roof_h * 0.38, 0.15, 0.0, 0.03, street.trim)
		pen.disc(0.0, p.wall_h + p.roof_h * 0.38, 0.1, 0.0, 0.045, street.glass)


func _shop_front(pen: Pen, p: Plan) -> void:
	var style: ShopStyle = p.style
	var hw: float = p.width * 0.5
	var side: float = signf(p.door_x)
	_door(pen, p.door_x, 0.5, p.door_col, true)
	# The shop window fills the rest of the ground floor.
	var x0: float = -hw + 0.2 if side > 0.0 else p.door_x + 0.42
	var x1: float = p.door_x - 0.42 if side > 0.0 else hw - 0.2
	var centre_x: float = (x0 + x1) * 0.5
	var porthole: bool = style != null and style.accent == ShopStyle.Accent.PORTHOLE
	pen.box(Vector3(x0 - 0.05, 0.1, 0.0), Vector3(x1 + 0.05, 0.3, 0.03), street.wood)
	if porthole:
		pen.box(Vector3(x0 - 0.05, 0.3, 0.0), Vector3(x1 + 0.05, 1.13, 0.012), street.trim)
		var spread: float = (x1 - x0) * 0.25
		for dx: float in [-spread, spread]:
			pen.disc(centre_x + dx, 0.72, 0.3, 0.0, 0.03, street.trim)
			pen.disc(centre_x + dx, 0.72, 0.23, 0.0, 0.05, street.glass)
			pen.disc(centre_x + dx, 0.72, 0.09, 0.0, 0.065, street.glass.lightened(0.3))
	else:
		pen.box(Vector3(x0 - 0.05, 0.3, 0.0), Vector3(x1 + 0.05, 1.13, 0.016), street.trim)
		pen.box(Vector3(x0, 0.35, 0.0), Vector3(x1, 1.08, 0.03), street.glass)
		var panes: int = maxi(1, roundi((x1 - x0) / 0.6))
		for index: int in range(1, panes):
			var mx: float = x0 + (x1 - x0) * float(index) / float(panes)
			pen.box(Vector3(mx - 0.014, 0.35, 0.0), Vector3(mx + 0.014, 1.08, 0.04), street.trim)
	_awning(pen, p)
	# Blank sign board above the awning, framed in trim.
	var board_top: float = minf(p.wall_h - 0.08, 1.64)
	var board_lo: float = 1.38
	var board_half: float = hw - 0.28
	pen.box(Vector3(-board_half - 0.04, board_lo - 0.04, 0.0), Vector3(board_half + 0.04, board_top + 0.04, 0.02), street.trim)
	pen.box(Vector3(-board_half, board_lo, 0.0), Vector3(board_half, board_top, 0.04), style.sign_board if style != null else street.trim)
	# Upper-floor windows when the building is tall enough.
	var win_lo: float = board_top + 0.14
	var win_hi: float = p.wall_h - 0.1
	if win_hi - win_lo >= 0.22:
		var count: int = 2 if p.width >= 2.9 else 1
		for index: int in count:
			var wx: float = 0.0 if count == 1 else (-1.0 if index == 0 else 1.0) * (hw * 0.45)
			_window(pen, wx, (win_lo + win_hi) * 0.5, 0.36, win_hi - win_lo, p.shutters, p.flowers, p.seed_value + index)
	if style != null:
		_accent(pen, p, style, centre_x)


func _awning(pen: Pen, p: Plan) -> void:
	var style: ShopStyle = p.style
	var hw: float = p.width * 0.5 + 0.04
	var stripes: int = maxi(6, roundi(p.width / 0.22))
	var step: float = hw * 2.0 / float(stripes)
	var high: float = 1.3
	var low: float = 1.16
	var normal: Vector3 = Vector3(0.0, AWNING_REACH, high - low).normalized()
	for index: int in stripes:
		var a: float = -hw + step * float(index)
		var b: float = a + step
		var colour: Color = (style.awning_a if index % 2 == 0 else style.awning_b) if style != null else street.trim
		var base: Array[Vector3] = [Vector3(a, high, 0.02), Vector3(b, high, 0.02), Vector3(b, low, AWNING_REACH), Vector3(a, low, AWNING_REACH)]
		pen.slab(base, normal * 0.03, colour)
		pen.box(Vector3(a, low - 0.08, AWNING_REACH - 0.02), Vector3(b, low, AWNING_REACH + 0.02), colour)


func _accent(pen: Pen, p: Plan, style: ShopStyle, ax: float) -> void:
	var y0: float = paving_top
	var reach: float = 0.1
	match style.accent:
		ShopStyle.Accent.CRATE:
			pen.box(Vector3(ax - 0.3, y0, reach), Vector3(ax + 0.3, y0 + 0.17, reach + 0.26), street.wood)
			for index: int in 3:
				var lx: float = ax - 0.18 + 0.18 * float(index)
				pen.lump(Vector3(lx, y0 + 0.22, reach + 0.13), 0.09, 0.06, 0.1, 0.4 * float(index), Color("d9a24c"), Color("a8742e"))
		ShopStyle.Accent.BUCKETS:
			for index: int in 2:
				var bx: float = ax + (-0.22 if index == 0 else 0.22)
				pen.box(Vector3(bx - 0.1, y0, reach), Vector3(bx + 0.1, y0 + 0.2, reach + 0.2), street.stone.lerp(style.awning_a, 0.4))
				for bloom: int in 3:
					var colour: Color = street.bloom_colors[(p.seed_value + index * 3 + bloom) % street.bloom_colors.size()]
					pen.lump(Vector3(bx - 0.06 + 0.06 * float(bloom), y0 + 0.27 + 0.02 * float(bloom % 2), reach + 0.08 + 0.04 * float(bloom % 2)),
						0.06, 0.06, 0.06, float(bloom), colour, colour.darkened(0.2))
		ShopStyle.Accent.PORTHOLE:
			pen.box(Vector3(ax - 0.17, y0, reach), Vector3(ax + 0.17, y0 + 0.2, reach + 0.24), street.wood)
			pen.box(Vector3(ax - 0.14, y0 + 0.2, reach + 0.02), Vector3(ax + 0.14, y0 + 0.29, reach + 0.22), street.trim)
		ShopStyle.Accent.JARS:
			var tones: Array[Color] = [style.awning_a, street.bloom_colors[0], style.awning_b]
			for index: int in 3:
				var jx: float = ax - 0.2 + 0.2 * float(index)
				pen.box(Vector3(jx - 0.07, y0, reach), Vector3(jx + 0.07, y0 + 0.16, reach + 0.14), tones[index])
				pen.box(Vector3(jx - 0.05, y0 + 0.16, reach + 0.02), Vector3(jx + 0.05, y0 + 0.2, reach + 0.12), street.trim)
		_:
			pen.box(Vector3(ax - 0.15, y0, reach + 0.08), Vector3(ax + 0.15, y0 + 0.04, reach + 0.38), street.wood)
			pen.box(Vector3(ax - 0.03, y0 + 0.04, reach + 0.21), Vector3(ax + 0.03, y0 + 0.24, reach + 0.25), street.wood)
			pen.box(Vector3(ax - 0.2, y0 + 0.24, reach + 0.06), Vector3(ax + 0.2, y0 + 0.28, reach + 0.4), style.awning_b)
			for stool: float in [-0.3, 0.3]:
				pen.box(Vector3(ax + stool - 0.07, y0, reach + 0.18), Vector3(ax + stool + 0.07, y0 + 0.15, reach + 0.32), style.awning_a)


## One window on each free side wall and a small back window: the building is
## seen from every rotation, so no wall is blank.
func _side_and_back(pen: Pen, p: Plan) -> void:
	var hw: float = p.width * 0.5
	var saved: Transform3D = pen.xf
	var cy: float = 1.0 if p.is_shop else minf(0.85, p.wall_h * 0.56)
	for side: int in 2:
		var bit: int = 1 if side == 0 else 2
		if p.exposed & bit == 0:
			continue
		var sign_x: float = 1.0 if side == 0 else -1.0
		pen.xf = saved * Transform3D(Basis(Vector3.UP, PI * 0.5 * sign_x), Vector3(sign_x * hw, 0.0, -p.depth * 0.5))
		_window(pen, 0.0, cy, 0.4, 0.4, false, p.flowers and not p.is_shop, p.seed_value + 5 + side)
		if p.is_shop and p.depth > 3.8:
			_window(pen, -p.depth * 0.28, cy, 0.4, 0.4, false, false, p.seed_value + 7)
	pen.xf = saved * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -p.depth))
	_window(pen, -p.door_x * 0.6, cy, 0.4, 0.4, p.shutters, false, p.seed_value + 9)
	if p.is_shop:
		_door(pen, p.door_x * 0.5, 0.46, street.wood, false)
	pen.xf = saved


# --- roofs ------------------------------------------------------------------

func _roof(pen: Pen, p: Plan) -> void:
	match p.roof:
		StreetSet.Roof.GABLE_FRONT:
			_gable(pen, p, true)
		StreetSet.Roof.GABLE_SIDE:
			_gable(pen, p, false)
		StreetSet.Roof.HIP:
			_hip(pen, p, p.depth > p.width, false)
		StreetSet.Roof.PYRAMID:
			_hip(pen, p, false, true)
		StreetSet.Roof.SHED:
			_shed(pen, p)
		StreetSet.Roof.FLAT:
			_flat(pen, p, false)
		_:
			_flat(pen, p, true)


func _map(p: Plan, ridge_z: bool, along: float, across: float, y: float) -> Vector3:
	if ridge_z:
		return Vector3(across, y, -p.depth * 0.5 + along)
	return Vector3(along, y, -p.depth * 0.5 + across)


func _outward_normal(base: Array[Vector3]) -> Vector3:
	var normal: Vector3 = (base[1] - base[0]).cross(base[3] - base[0])
	if normal.length_squared() < 0.0000001:
		normal = (base[1] - base[0]).cross(base[2] - base[0])
	normal = normal.normalized()
	return normal if normal.y >= 0.0 else -normal


func _gable(pen: Pen, p: Plan, ridge_z: bool) -> void:
	var half_span: float = p.width * 0.5 if ridge_z else p.depth * 0.5
	var half_len: float = p.depth * 0.5 if ridge_z else p.width * 0.5
	var over_across: float = EAVE
	var over_along: float = 0.06 if ridge_z else 0.05
	var rise: float = p.roof_h
	var eave_y: float = p.wall_h - over_across * rise / half_span
	var peak: float = p.wall_h + rise
	for side: float in [-1.0, 1.0]:
		var base: Array[Vector3] = [
			_map(p, ridge_z, -half_len - over_along, side * (half_span + over_across), eave_y),
			_map(p, ridge_z, half_len + over_along, side * (half_span + over_across), eave_y),
			_map(p, ridge_z, half_len + over_along, 0.0, peak),
			_map(p, ridge_z, -half_len - over_along, 0.0, peak)]
		pen.slab(base, _outward_normal(base) * 0.05, p.roof_col)
	for end: float in [-1.0, 1.0]:
		var a: Vector3 = _map(p, ridge_z, end * half_len, -half_span, p.wall_h)
		var b: Vector3 = _map(p, ridge_z, end * half_len, half_span, p.wall_h)
		var c: Vector3 = _map(p, ridge_z, end * half_len, 0.0, peak)
		pen.tri(a, b, c, _map(p, ridge_z, end, 0.0, 0.0) - _map(p, ridge_z, 0.0, 0.0, 0.0), p.wall)
	# Ridge cap.
	var cap_a: Vector3 = _map(p, ridge_z, -half_len - over_along, 0.0, peak)
	var cap_b: Vector3 = _map(p, ridge_z, half_len + over_along, 0.0, peak)
	var lo: Vector3 = Vector3(minf(cap_a.x, cap_b.x), peak + 0.035, minf(cap_a.z, cap_b.z))
	var hi: Vector3 = Vector3(maxf(cap_a.x, cap_b.x), peak + 0.075, maxf(cap_a.z, cap_b.z))
	if ridge_z:
		lo.x -= 0.035
		hi.x += 0.035
	else:
		lo.z -= 0.035
		hi.z += 0.035
	pen.box(lo, hi, p.roof_col.darkened(0.12))


func _hip(pen: Pen, p: Plan, ridge_z: bool, pyramid: bool) -> void:
	var half_span: float = p.width * 0.5 if ridge_z else p.depth * 0.5
	var half_len: float = p.depth * 0.5 if ridge_z else p.width * 0.5
	if pyramid:
		half_span = p.width * 0.5
		half_len = p.depth * 0.5
		ridge_z = true
	var over: float = EAVE
	var rise: float = p.roof_h
	var eave_y: float = p.wall_h - over * rise / half_span
	var peak: float = p.wall_h + rise
	var ridge_half: float = 0.0 if pyramid else maxf(half_len - half_span, 0.0)
	for side: float in [-1.0, 1.0]:
		var base: Array[Vector3] = [
			_map(p, ridge_z, -half_len - over, side * (half_span + over), eave_y),
			_map(p, ridge_z, half_len + over, side * (half_span + over), eave_y),
			_map(p, ridge_z, ridge_half, 0.0, peak),
			_map(p, ridge_z, -ridge_half, 0.0, peak)]
		pen.slab(base, _outward_normal(base) * 0.05, p.roof_col)
	for end: float in [-1.0, 1.0]:
		var base: Array[Vector3] = [
			_map(p, ridge_z, end * (half_len + over), half_span + over, eave_y),
			_map(p, ridge_z, end * (half_len + over), -(half_span + over), eave_y),
			_map(p, ridge_z, end * ridge_half, 0.0, peak),
			_map(p, ridge_z, end * ridge_half, 0.0, peak)]
		pen.slab(base, _outward_normal(base) * 0.05, p.roof_col.darkened(0.06))


func _shed(pen: Pen, p: Plan) -> void:
	var hw: float = p.width * 0.5 + EAVE
	var back: float = p.wall_h + p.roof_h
	var front: float = p.wall_h + p.roof_h * 0.12
	var base: Array[Vector3] = [Vector3(-hw, front, 0.12), Vector3(hw, front, 0.12),
		Vector3(hw, back, -p.depth - 0.05), Vector3(-hw, back, -p.depth - 0.05)]
	pen.slab(base, _outward_normal(base) * 0.05, p.roof_col)
	for side: float in [-1.0, 1.0]:
		var x: float = side * p.width * 0.5
		pen.quad(Vector3(x, p.wall_h, 0.0), Vector3(x, p.wall_h, -p.depth), Vector3(x, back, -p.depth), Vector3(x, p.wall_h + p.roof_h * 0.12 + 0.0, 0.0),
			Vector3(side, 0.0, 0.0), p.wall)
	# A low flashing along the back edge.
	pen.box(Vector3(-hw, back, -p.depth - 0.05), Vector3(hw, back + 0.05, -p.depth + 0.04), p.roof_col.darkened(0.15))


func _flat(pen: Pen, p: Plan, false_front: bool) -> void:
	var hw: float = p.width * 0.5
	var top: float = p.wall_h
	pen.box(Vector3(-hw - 0.04, top, -p.depth - 0.04), Vector3(hw + 0.04, top + 0.07, 0.06), p.roof_col)
	var trim: Color = street.trim
	pen.box(Vector3(-hw - 0.04, top + 0.07, -p.depth - 0.04), Vector3(hw + 0.04, top + 0.17, -p.depth + 0.04), trim)
	pen.box(Vector3(-hw - 0.04, top + 0.07, -p.depth), Vector3(-hw, top + 0.17, 0.06), trim)
	pen.box(Vector3(hw, top + 0.07, -p.depth), Vector3(hw + 0.04, top + 0.17, 0.06), trim)
	if not false_front:
		pen.box(Vector3(-hw - 0.04, top + 0.07, 0.02), Vector3(hw + 0.04, top + 0.17, 0.06), trim)
		return
	var rise: float = p.roof_h
	pen.box(Vector3(-hw - 0.03, top, -0.13), Vector3(hw + 0.03, top + rise * 0.62, 0.035), p.wall)
	pen.box(Vector3(-hw - 0.05, top + rise * 0.55, -0.14), Vector3(hw + 0.05, top + rise * 0.65, 0.07), trim)
	var step: float = minf(0.5, hw * 0.6)
	pen.box(Vector3(-step, top + rise * 0.65, -0.1), Vector3(step, top + rise, 0.035), p.wall)
	pen.box(Vector3(-step - 0.04, top + rise * 0.95, -0.12), Vector3(step + 0.04, top + rise + 0.03, 0.06), trim)


func _chimney(pen: Pen, p: Plan) -> void:
	var ridge_z: bool = p.roof == StreetSet.Roof.GABLE_FRONT or (p.roof == StreetSet.Roof.HIP and p.depth > p.width)
	var half_len: float = (p.depth if ridge_z else p.width) * 0.5
	var reach: float = 0.45 * half_len
	if p.roof == StreetSet.Roof.HIP:
		reach = minf(reach, maxf(half_len - (p.width if ridge_z else p.depth) * 0.5, 0.0) * 0.8)
	var at: Vector3 = _map(p, ridge_z, reach * (1.0 if _r(p.seed_value, 21) < 0.5 else -1.0), 0.0, 0.0)
	var peak: float = p.wall_h + p.roof_h
	var brick: Color = street.stone.lerp(p.wall, 0.3).darkened(0.1)
	pen.box(Vector3(at.x - 0.1, p.wall_h + p.roof_h * 0.5, at.z - 0.1), Vector3(at.x + 0.1, peak + 0.17, at.z + 0.1), brick)
	pen.box(Vector3(at.x - 0.13, peak + 0.17, at.z - 0.13), Vector3(at.x + 0.13, peak + 0.22, at.z + 0.13), brick.darkened(0.2))


# --- house lots -------------------------------------------------------------

func _yard(pen: Pen, p: Plan) -> void:
	var saved: Transform3D = pen.xf
	pen.xf = Transform3D.IDENTITY
	var seed_value: int = p.seed_value
	var lot: Rect2 = p.lot
	var door_u: float = (p.xf * Vector3(p.door_x, 0.0, 0.0)).x
	var door_z: float = p.xf.origin.z
	var fence_z: float = lot.position.y
	# The path from the pavement to the step, with a darker edge.
	pen.flat(door_u - 0.24, PAVEMENT_EDGE_V + shift, door_u + 0.24, door_z - 0.18, FLAT_Y, street.path.darkened(0.14))
	pen.flat(door_u - 0.2, PAVEMENT_EDGE_V + shift + 0.04, door_u + 0.2, door_z - 0.18, FLAT_Y + 0.003, street.path)
	_front_fence(pen, p, door_u, fence_z)
	# Side dividers (the left one of each lot, plus the last lot's right one) and the back.
	_hedge_line(pen, Vector2(lot.position.x, fence_z), Vector2(lot.position.x, lot.end.y), seed_value, 0)
	if p.lot_index == street.house_count - 1:
		_hedge_line(pen, Vector2(lot.end.x, fence_z), Vector2(lot.end.x, lot.end.y), seed_value, 1)
	_hedge_line(pen, Vector2(lot.position.x, lot.end.y), Vector2(lot.end.x, lot.end.y), seed_value, 2)
	# Front-yard details: a mailbox, a flower bed under the windows and a small tree or bush.
	if p.mailbox:
		var mx: float = door_u + (0.5 if door_u < lot.get_center().x else -0.5)
		pen.box(Vector3(mx - 0.02, 0.0, fence_z + 0.2), Vector3(mx + 0.02, 0.32, fence_z + 0.24), street.wood)
		pen.box(Vector3(mx - 0.07, 0.32, fence_z + 0.17), Vector3(mx + 0.07, 0.42, fence_z + 0.28), p.door_col)
		pen.box(Vector3(mx + 0.07, 0.34, fence_z + 0.18), Vector3(mx + 0.09, 0.42, fence_z + 0.2), Color("c8412f"))
	var bed_z: float = door_z - 0.26
	var bed_u: float = p.xf.origin.x
	var bed_half: float = p.width * 0.5 - 0.1
	pen.box(Vector3(bed_u - bed_half, 0.0, bed_z), Vector3(bed_u - bed_half + 0.5, 0.07, door_z - 0.02), street.wood.darkened(0.35))
	pen.box(Vector3(bed_u + bed_half - 0.5, 0.0, bed_z), Vector3(bed_u + bed_half, 0.07, door_z - 0.02), street.wood.darkened(0.35))
	for index: int in 6:
		var bloom: Color = street.bloom_colors[(seed_value + index) % street.bloom_colors.size()]
		var bx: float = bed_u - bed_half + 0.1 + 0.15 * float(index % 3) if index < 3 else bed_u + bed_half - 0.4 + 0.15 * float(index % 3)
		pen.lump(Vector3(bx, 0.11, door_z - 0.14), 0.06, 0.06, 0.06, float(index), bloom, bloom.darkened(0.2))
	var corner: float = -1.0 if _r(seed_value, 22) < 0.5 else 1.0
	var tx: float = lot.get_center().x + corner * (lot.size.x * 0.5 - 0.5)
	if _r(seed_value, 23) < 0.6:
		pen.box(Vector3(tx - 0.045, 0.0, fence_z + 0.55), Vector3(tx + 0.045, 0.4, fence_z + 0.65), street.wood.darkened(0.2))
		var leaf: Color = street.hedge_colors[_pick(street.hedge_colors.size(), seed_value, 24)]
		pen.lump(Vector3(tx, 0.62, fence_z + 0.6), 0.3, 0.3, 0.3, 0.3, leaf.lightened(0.05), leaf.darkened(0.2))
	else:
		var leaf: Color = street.hedge_colors[_pick(street.hedge_colors.size(), seed_value, 25)]
		pen.lump(Vector3(tx, 0.14, fence_z + 0.6), 0.22, 0.2, 0.22, 0.5, leaf, leaf.darkened(0.2))
	# Back garden: a bush against the rear hedge.
	var back_leaf: Color = street.hedge_colors[_pick(street.hedge_colors.size(), seed_value, 26)]
	var back_u: float = lot.get_center().x + (_r(seed_value, 27) - 0.5) * (lot.size.x - 1.2)
	pen.lump(Vector3(back_u, 0.15, lot.end.y - 0.45), 0.24, 0.22, 0.22, 0.8, back_leaf, back_leaf.darkened(0.2))
	pen.xf = saved


func _front_fence(pen: Pen, p: Plan, door_u: float, z: float) -> void:
	var lot: Rect2 = p.lot
	var x0: float = lot.position.x
	var x1: float = lot.end.x
	var gate: float = 0.36
	var fence_col: Color = street.trim
	var seed_value: int = p.seed_value
	match p.fence:
		StreetSet.Fence.HEDGE:
			_hedge_line(pen, Vector2(x0, z), Vector2(door_u - gate, z), seed_value, 3)
			_hedge_line(pen, Vector2(door_u + gate, z), Vector2(x1, z), seed_value, 4)
		StreetSet.Fence.WALL:
			for span: Vector2 in [Vector2(x0, door_u - gate), Vector2(door_u + gate, x1)]:
				pen.box(Vector3(span.x, 0.0, z - 0.07), Vector3(span.y, 0.24, z + 0.07), street.stone.lerp(p.wall, 0.25))
				pen.box(Vector3(span.x - 0.015, 0.24, z - 0.09), Vector3(span.y + 0.015, 0.285, z + 0.09), street.stone.lightened(0.18))
		StreetSet.Fence.RAIL:
			var post_x: float = x0
			var posts: Array[float] = []
			while post_x <= x1 + 0.01:
				posts.append(post_x)
				post_x += 0.9
			if posts.back() < x1 - 0.1:
				posts.append(x1)
			for px: float in posts:
				if absf(px - door_u) < gate - 0.02:
					continue
				pen.box(Vector3(px - 0.035, 0.0, z - 0.035), Vector3(px + 0.035, 0.36, z + 0.035), street.wood)
			for span: Vector2 in [Vector2(x0, door_u - gate), Vector2(door_u + gate, x1)]:
				pen.box(Vector3(span.x, 0.14, z - 0.015), Vector3(span.y, 0.18, z + 0.015), street.wood)
				pen.box(Vector3(span.x, 0.27, z - 0.015), Vector3(span.y, 0.31, z + 0.015), street.wood)
		_:
			var count: int = int((x1 - x0) / 0.22)
			for index: int in count + 1:
				var px: float = x0 + 0.05 + float(index) * (x1 - x0 - 0.1) / float(count)
				if absf(px - door_u) < gate:
					continue
				pen.box(Vector3(px - 0.035, 0.0, z - 0.02), Vector3(px + 0.035, 0.34, z + 0.02), fence_col)
			for span: Vector2 in [Vector2(x0, door_u - gate), Vector2(door_u + gate, x1)]:
				pen.box(Vector3(span.x, 0.09, z + 0.02), Vector3(span.y, 0.13, z + 0.045), fence_col.darkened(0.08))
				pen.box(Vector3(span.x, 0.22, z + 0.02), Vector3(span.y, 0.26, z + 0.045), fence_col.darkened(0.08))
	for post: float in [door_u - gate, door_u + gate]:
		pen.box(Vector3(post - 0.05, 0.0, z - 0.05), Vector3(post + 0.05, 0.44, z + 0.05), street.wood)
		pen.box(Vector3(post - 0.065, 0.44, z - 0.065), Vector3(post + 0.065, 0.48, z + 0.065), street.wood.lightened(0.15))


## A hedge of chunky segments along a street-local line, each its own height and tone.
func _hedge_line(pen: Pen, from: Vector2, to: Vector2, seed_value: int, line: int) -> void:
	var length: float = from.distance_to(to)
	if length < 0.1:
		return
	var count: int = maxi(1, roundi(length / 0.8))
	var direction: Vector2 = (to - from) / length
	for index: int in count:
		var a: Vector2 = from + direction * length * float(index) / float(count)
		var b: Vector2 = from + direction * length * float(index + 1) / float(count)
		var tone: Color = street.hedge_colors[_pick(street.hedge_colors.size(), seed_value * 7 + index, 30 + line)]
		var height: float = 0.3 + 0.1 * _r(seed_value * 7 + index, 40 + line)
		var half: float = 0.15
		var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		if absf(direction.x) > 0.5:
			lo.y -= half
			hi.y += half
		else:
			lo.x -= half
			hi.x += half
		var shoulder: float = height * 0.65
		var inset: float = 0.06
		pen.box(Vector3(lo.x, 0.0, lo.y), Vector3(hi.x, shoulder, hi.y), tone.darkened(0.08))
		pen.box(Vector3(lo.x + inset, shoulder, lo.y + inset), Vector3(hi.x - inset, height, hi.y - inset), tone)
