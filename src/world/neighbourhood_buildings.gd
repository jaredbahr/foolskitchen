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
## The tallest a near shop may stand, roof included: the real clearance (GAP less
## the eave overhang and a margin) over the 0.5 m of hidden ground per metre of height.
const MAX_NEAR_HEIGHT: float = (GAP - EAVE - 0.02) / 0.5
## Street-edge distance of every house lot's front fence line.
const FENCE_V: float = 8.7
const PAVEMENT_EDGE_V: float = 8.22
const FLAT_Y: float = -0.026
const AWNING_REACH: float = 0.36
const DOOR_H: float = 1.0
const EAVE: float = 0.08
## A shop's hanging sign: the bracket's height on the facade and how far it reaches (#423).
const SIGN_Y: float = 1.6
const SIGN_LEN: float = 0.32
## Lot ground behind each house's back wall: the back garden (#440).
const BACK_YARD: float = 2.6
## Keep-out inside a lot for the side hedges (half a hedge plus a margin), the back hedge, the eave.
const GARDEN_SIDE: float = 0.3
const GARDEN_HEDGE: float = 0.3
const GARDEN_EAVE: float = 0.16
## Baked garden contact shadows lie just above the lawn's own baked shadows.
const GARDEN_SHADOW_Y: float = -0.021
## A lit window quad stands this far proud of the glass.
const GLOW_Z: float = 0.0275
## The shopfront glass is a thicker box (to z 0.03) under 0.04 mullions: its glow stands between.
const SHOP_GLOW_Z: float = 0.034
## Window light tiers: 0 stays lit all night, 1 goes dark early in the late hours, 2 later still.
const GLOW_TIERS: int = 3

enum Garden { VEG, SHED, LINE, SWING, SLIDE, TABLE, BENCH, TREE, BIRDBATH, BORDER, STONES }

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
	## Building-local x of the hanging sign's bracket (shops only).
	var sign_x: float = 0.0
	## Houses: the back door's street offset from the house centre (#440).
	var back_u: float = 0.0
	## Street-local garden ground (u, z) and the doorstep patch the garden keeps clear.
	var garden_zone: Rect2 = Rect2()
	var doorstep: Rect2 = Rect2()
	## What stands in the garden: {kind, rect (street-local u, z), height, seed}.
	var garden: Array[Dictionary] = []
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
## The key light's ground run per metre of height (street-local u, z) and the lawn's shadow tone,
## for the gardens' baked contact shadows. Set by the owner before meshing; part of its cache key.
var light_shift: Vector2 = Vector2(-0.4, 0.5)
var lawn_shadow: Color = Color(0.3, 0.4, 0.2)
## Window glow quads gathered while the buildings are meshed, one soup per light tier (#440).
var _glow_soups: Array[NeighbourhoodGround.Soup] = []
var _glow_key: int = 0
var _glow_count: int = 0
## One flat-shaded vertex-colour material shared by every building this builder meshes.
var _material: StandardMaterial3D


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
	_glow_soups.clear()
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
		var recent_tone: Array[int] = []
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
			while p.total_height() > MAX_NEAR_HEIGHT + 0.0001 and p.roof_h > 0.2:
				p.roof_h -= 0.05
			p.wall_h = minf(p.wall_h, MAX_NEAR_HEIGHT - p.roof_h)
			p.wall = p.style.wall if p.style != null else street.wall_colors[0]
			var tone_choice: int = _pick_distinct(street.roof_colors.size(), index, 5, recent_tone)
			recent_tone = [tone_choice]
			p.roof_col = street.roof_colors[tone_choice]
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
			p.sign_x = signf(p.door_x) * (p.width * 0.5 - 0.09)
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
	var recent_tone: Array[int] = []
	var recent_kinds: Array[int] = []
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
		var tone_choice: int = _pick_distinct(street.roof_colors.size(), key, 9, recent_tone)
		recent_tone = [tone_choice]
		p.roof_col = street.roof_colors[tone_choice]
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
		p.lot = Rect2(cursor, shift + FENCE_V, lot_width, front_yard + p.depth + BACK_YARD)
		cursor += lot_width
		p.bounds = _bounds_of(p)
		# The back door sits to one side of the back wall, the back window to the other.
		p.back_u = (-1.0 if _r(key, 28) < 0.5 else 1.0) * (p.width * 0.5 - 0.62)
		_plan_garden(p, lot_centre + offset, door_plane + p.depth, recent_kinds)
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


## Where each shop's hanging sign swings (#423): the pivot on its bracket in street-local
## space and the shop's own colours. The board itself is built by NeighbourhoodLife.
func signs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p: Plan in plans:
		if p.is_shop and p.style != null:
			result.append({"pivot": p.xf * Vector3(p.sign_x, SIGN_Y, 0.0), "main": p.style.awning_a,
				"accent": p.style.awning_b, "seed": p.seed_value})
	return result


## The street-local x of each shop's front door: pavement furniture keeps clear of them.
func shop_doors() -> Array[float]:
	var result: Array[float] = []
	for p: Plan in plans:
		if p.is_shop:
			result.append((p.xf * Vector3(p.door_x, 0.0, 0.0)).x)
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
	_glow_key = p.seed_value
	_glow_count = 0
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
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0
		_material.metallic_specular = 0.0
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_material.disable_receive_shadows = true
	instance.mesh = pen.soup.to_mesh()
	instance.material_override = _material
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
	_glow(pen, cx, cy, hw, hh)
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
		_glow(pen, centre_x, 0.715, (x1 - x0) * 0.5, 0.365, SHOP_GLOW_Z)
		var panes: int = maxi(1, roundi((x1 - x0) / 0.6))
		for index: int in range(1, panes):
			var mx: float = x0 + (x1 - x0) * float(index) / float(panes)
			pen.box(Vector3(mx - 0.014, 0.35, 0.0), Vector3(mx + 0.014, 1.08, 0.04), street.trim)
	_awning(pen, p)
	var displays: bool = style != null and (style.accent == ShopStyle.Accent.TOYS or style.accent == ShopStyle.Accent.PETS)
	if displays:
		_window_display(pen, p, style, x0, x1)
	elif not porthole:
		_window_box(pen, x0, x1, p)
	_sign_bracket(pen, p)
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


## A flower box on the shop window's sill, blooms from the street's bloom palette (#423).
func _window_box(pen: Pen, x0: float, x1: float, p: Plan) -> void:
	var lo: float = x0 + 0.02
	var hi: float = x1 - 0.02
	var top: float = 0.46
	pen.box(Vector3(lo, 0.34, 0.0), Vector3(hi, top, 0.12), street.wood)
	pen.box(Vector3(lo - 0.012, top - 0.03, 0.0), Vector3(hi + 0.012, top, 0.132), street.wood.lightened(0.14))
	pen.box(Vector3(lo + 0.02, top, 0.02), Vector3(hi - 0.02, top + 0.04, 0.1), street.hedge_colors[0])
	var count: int = maxi(3, roundi((hi - lo) / 0.2))
	for index: int in count:
		var along: float = lo + 0.08 + float(index) * (hi - lo - 0.16) / float(count - 1)
		var bloom: Color = street.bloom_colors[(p.seed_value + index) % street.bloom_colors.size()]
		var lift: float = 0.02 * float(index % 2)
		pen.lump(Vector3(along, top + 0.075 + lift, 0.06 + lift), 0.065, 0.065, 0.065, float(index), bloom, bloom.darkened(0.2))


## The bracket a hanging sign swings from (the board is NeighbourhoodLife's).
func _sign_bracket(pen: Pen, p: Plan) -> void:
	var x: float = p.sign_x
	pen.box(Vector3(x - 0.035, SIGN_Y - 0.05, 0.0), Vector3(x + 0.035, SIGN_Y + 0.07, 0.025), street.metal)
	pen.box(Vector3(x - 0.015, SIGN_Y, 0.0), Vector3(x + 0.015, SIGN_Y + 0.035, SIGN_LEN), street.metal)
	pen.box(Vector3(x - 0.01, SIGN_Y - 0.06, 0.0), Vector3(x + 0.01, SIGN_Y, 0.03), street.metal)


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
		ShopStyle.Accent.TOYS:
			_rocking_horse(pen, p, ax, y0, reach)
		ShopStyle.Accent.PETS:
			_dog_bed(pen, p, ax, y0, reach)
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
	if p.is_shop:
		_window(pen, -p.door_x * 0.6, cy, 0.4, 0.4, p.shutters, false, p.seed_value + 9)
		_door(pen, p.door_x * 0.5, 0.46, street.wood, false)
	else:
		_house_back(pen, p, cy)
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
	var bed_half: float = p.width * 0.5 - 0.1
	for side: float in [-1.0, 1.0]:
		var inner: float = p.xf.origin.x + side * (bed_half - 0.5)
		var outer: float = p.xf.origin.x + side * bed_half
		var low: float = minf(inner, outer)
		var high: float = maxf(inner, outer)
		# A bed never crosses the path or its step.
		if high > door_u - 0.36 and low < door_u + 0.36:
			continue
		pen.box(Vector3(low, 0.0, bed_z), Vector3(high, 0.07, door_z - 0.02), street.wood.darkened(0.35))
		for index: int in 3:
			var bloom: Color = street.bloom_colors[(seed_value + index + (3 if side > 0.0 else 0)) % street.bloom_colors.size()]
			pen.lump(Vector3(low + 0.1 + 0.15 * float(index), 0.11, door_z - 0.14), 0.06, 0.06, 0.06, float(index), bloom, bloom.darkened(0.2))
	var corner: float = -1.0 if _r(seed_value, 22) < 0.5 else 1.0
	var tx: float = lot.get_center().x + corner * (lot.size.x * 0.5 - 0.5)
	if _r(seed_value, 23) < 0.6:
		pen.box(Vector3(tx - 0.045, 0.0, fence_z + 0.55), Vector3(tx + 0.045, 0.4, fence_z + 0.65), street.wood.darkened(0.2))
		var leaf: Color = street.hedge_colors[_pick(street.hedge_colors.size(), seed_value, 24)]
		pen.lump(Vector3(tx, 0.62, fence_z + 0.6), 0.3, 0.3, 0.3, 0.3, leaf.lightened(0.05), leaf.darkened(0.2))
	else:
		var leaf: Color = street.hedge_colors[_pick(street.hedge_colors.size(), seed_value, 25)]
		pen.lump(Vector3(tx, 0.14, fence_z + 0.6), 0.22, 0.2, 0.22, 0.5, leaf, leaf.darkened(0.2))
	_garden(pen, p)
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


# --- windows that light at night (#440) --------------------------------------

## A warm quad just proud of a window's glass. By hash a window is dark all night (curtains
## drawn), lit all night, or lit until one of two bedtimes in the late hours: the owner
## draws each tier as its own mesh and fades it with the night level. Never a Light3D.
func _glow(pen: Pen, cx: float, cy: float, hw: float, hh: float, z: float = GLOW_Z) -> void:
	_glow_count += 1
	var roll: float = _r(_glow_key * 41 + _glow_count, 61)
	if roll < 0.12:
		return
	var tier: int = 0
	if roll >= 0.875:
		tier = 2
	elif roll >= 0.75:
		tier = 1
	while _glow_soups.size() < GLOW_TIERS:
		_glow_soups.append(NeighbourhoodGround.Soup.new())
	var tint: Color = Color(1.0, 0.8, 0.45)
	if not street.window_glows.is_empty():
		tint = street.window_glows[_pick(street.window_glows.size(), _glow_key * 41 + _glow_count, 62)]
	var soup: NeighbourhoodGround.Soup = _glow_soups[tier]
	var hint: Vector3 = pen.xf.basis * Vector3.BACK
	# Two bands, the lower a touch deeper, so the pane reads as lit from above.
	for band: int in 2:
		var y0: float = cy - hh if band == 0 else cy
		var colour: Color = tint.darkened(0.16) if band == 0 else tint
		var a: Vector3 = pen.xf * Vector3(cx - hw, y0, z)
		var b: Vector3 = pen.xf * Vector3(cx + hw, y0, z)
		var c: Vector3 = pen.xf * Vector3(cx + hw, y0 + hh, z)
		var d: Vector3 = pen.xf * Vector3(cx - hw, y0 + hh, z)
		soup.tri(a, b, c, hint, colour)
		soup.tri(a, c, d, hint, colour)


## The lit-window meshes, one per light tier (null when a tier has no window), in the
## street-local frame. Call after every building has been meshed.
func glow_meshes() -> Array[ArrayMesh]:
	var result: Array[ArrayMesh] = []
	for tier: int in GLOW_TIERS:
		if tier < _glow_soups.size() and not _glow_soups[tier].is_empty():
			result.append(_glow_soups[tier].to_mesh())
		else:
			result.append(null)
	return result


# --- shop window displays and the little things set out in front ------------------

func _window_display(pen: Pen, p: Plan, style: ShopStyle, x0: float, x1: float) -> void:
	var mid: float = (x0 + x1) * 0.5
	var span: float = (x1 - x0) * 0.5 - 0.1
	var play: Array[Color] = street.play_colors
	var shelf: float = 0.38
	pen.box(Vector3(x0 - 0.02, 0.34, 0.0), Vector3(x1 + 0.02, shelf, 0.19), street.wood)
	pen.box(Vector3(x0 - 0.03, shelf - 0.012, 0.17), Vector3(x1 + 0.03, shelf, 0.2), street.wood.lightened(0.14))
	if style.accent == ShopStyle.Accent.TOYS:
		# A pyramid of building blocks, a teddy and a ball, with bunting across the top.
		var left: float = mid - span * 0.62
		var size: float = 0.13
		for row: int in 2:
			for col: int in 2 - row:
				var bx: float = left + float(col) * size + float(row) * size * 0.5
				var colour: Color = play[(p.seed_value + row * 2 + col) % play.size()]
				pen.box(Vector3(bx - size * 0.5, shelf + float(row) * size, 0.05),
					Vector3(bx + size * 0.5, shelf + float(row + 1) * size, 0.05 + size), colour)
		var bear: Color = street.wood.lightened(0.3)
		pen.lump(Vector3(mid + span * 0.08, shelf + 0.07, 0.11), 0.1, 0.1, 0.07, 0.3, bear, bear.darkened(0.2))
		pen.lump(Vector3(mid + span * 0.08, shelf + 0.24, 0.11), 0.07, 0.07, 0.06, 0.6, bear.lightened(0.05), bear.darkened(0.15))
		for ear: float in [-0.055, 0.055]:
			pen.lump(Vector3(mid + span * 0.08 + ear, shelf + 0.31, 0.11), 0.03, 0.03, 0.03, 0.0, bear, bear.darkened(0.2))
		var ball: Color = play[(p.seed_value + 3) % play.size()]
		pen.lump(Vector3(mid + span * 0.62, shelf + 0.08, 0.12), 0.08, 0.08, 0.08, 0.2, ball, ball.darkened(0.25))
		var flags: int = maxi(4, roundi(span * 2.0 / 0.2))
		for index: int in flags:
			var fx0: float = x0 + 0.06 + (x1 - x0 - 0.12) * float(index) / float(flags)
			var fx1: float = fx0 + (x1 - x0 - 0.12) / float(flags) * 0.8
			var sag: float = 1.0 - 0.06 * sin(PI * float(index) / float(flags - 1))
			pen.tri(Vector3(fx0, 1.02 * sag, 0.034), Vector3(fx1, 1.02 * sag, 0.034),
				Vector3((fx0 + fx1) * 0.5, 0.9 * sag, 0.034), Vector3.BACK, play[(index + p.seed_value) % play.size()])
	else:
		# A fish tank with weed and three fish, and a cat asleep on the shelf.
		var tank_x: float = mid + span * 0.2
		var half: float = minf(0.3, span * 0.5)
		var water: Color = street.glass.lerp(style.awning_a, 0.45).lightened(0.2)
		pen.box(Vector3(tank_x - half - 0.02, shelf, 0.04), Vector3(tank_x + half + 0.02, shelf + 0.05, 0.19), street.metal)
		pen.box(Vector3(tank_x - half, shelf + 0.05, 0.05), Vector3(tank_x + half, shelf + 0.4, 0.18), water)
		pen.box(Vector3(tank_x - half - 0.02, shelf + 0.4, 0.04), Vector3(tank_x + half + 0.02, shelf + 0.44, 0.19), street.metal)
		pen.box(Vector3(tank_x - half, shelf + 0.05, 0.05), Vector3(tank_x + half, shelf + 0.09, 0.18), street.path)
		var weed: Color = street.hedge_colors[1 % street.hedge_colors.size()]
		pen.lump(Vector3(tank_x - half * 0.55, shelf + 0.2, 0.12), 0.05, 0.13, 0.05, 0.0, weed, weed.darkened(0.2))
		pen.lump(Vector3(tank_x + half * 0.6, shelf + 0.17, 0.12), 0.045, 0.1, 0.045, 1.0, weed.lightened(0.1), weed.darkened(0.2))
		var fish: Array[Color] = [street.bloom_colors[3 % street.bloom_colors.size()], street.bloom_colors[1 % street.bloom_colors.size()],
			street.bloom_colors[4 % street.bloom_colors.size()]]
		for index: int in 3:
			var fx: float = tank_x - half * 0.45 + float(index) * half * 0.45
			var fy: float = shelf + 0.18 + 0.07 * float(index % 2)
			pen.lump(Vector3(fx, fy, 0.185), 0.05, 0.035, 0.02, 0.0, fish[index], fish[index].darkened(0.2))
			pen.box(Vector3(fx + 0.045, fy - 0.025, 0.178), Vector3(fx + 0.075, fy + 0.025, 0.19), fish[index].darkened(0.1))
		var fur: Color = street.wall_colors[1 % street.wall_colors.size()].darkened(0.18).lerp(street.wood, 0.3)
		var cat_x: float = mid - span * 0.65
		pen.lump(Vector3(cat_x, shelf + 0.07, 0.11), 0.12, 0.08, 0.075, 0.2, fur, fur.darkened(0.2))
		pen.lump(Vector3(cat_x + 0.1, shelf + 0.1, 0.11), 0.055, 0.05, 0.05, 0.5, fur.lightened(0.05), fur.darkened(0.2))
		for ear: float in [-0.03, 0.03]:
			pen.box(Vector3(cat_x + 0.1 + ear - 0.012, shelf + 0.14, 0.095), Vector3(cat_x + 0.1 + ear + 0.012, shelf + 0.18, 0.125), fur.darkened(0.1))


## A small rocking horse on the paving in front of the toy shop (#440).
func _rocking_horse(pen: Pen, p: Plan, ax: float, y0: float, reach: float) -> void:
	var coat: Color = street.play_colors[p.seed_value % street.play_colors.size()]
	var mane: Color = street.wood.darkened(0.15)
	var z0: float = reach + 0.06
	var z1: float = reach + 0.24
	for z: float in [z0, z1]:
		# A rocker is a flat plank with its ends curled up.
		pen.box(Vector3(ax - 0.17, y0, z - 0.015), Vector3(ax + 0.17, y0 + 0.03, z + 0.015), street.wood)
		pen.box(Vector3(ax - 0.23, y0 + 0.03, z - 0.015), Vector3(ax - 0.17, y0 + 0.06, z + 0.015), street.wood)
		pen.box(Vector3(ax + 0.17, y0 + 0.03, z - 0.015), Vector3(ax + 0.23, y0 + 0.06, z + 0.015), street.wood)
		for leg: float in [-0.12, 0.12]:
			pen.box(Vector3(ax + leg - 0.02, y0 + 0.03, z - 0.015), Vector3(ax + leg + 0.02, y0 + 0.15, z + 0.015), coat.darkened(0.12))
	pen.box(Vector3(ax - 0.15, y0 + 0.15, z0 - 0.03), Vector3(ax + 0.12, y0 + 0.26, z1 + 0.03), coat)
	pen.box(Vector3(ax + 0.08, y0 + 0.22, z0), Vector3(ax + 0.17, y0 + 0.4, z1), coat)
	pen.box(Vector3(ax + 0.17, y0 + 0.3, (z0 + z1) * 0.5 - 0.03), Vector3(ax + 0.25, y0 + 0.39, (z0 + z1) * 0.5 + 0.03), coat.lightened(0.08))
	pen.box(Vector3(ax + 0.06, y0 + 0.26, (z0 + z1) * 0.5 - 0.012), Vector3(ax + 0.09, y0 + 0.42, (z0 + z1) * 0.5 + 0.012), mane)
	pen.box(Vector3(ax - 0.19, y0 + 0.16, (z0 + z1) * 0.5 - 0.012), Vector3(ax - 0.15, y0 + 0.28, (z0 + z1) * 0.5 + 0.012), mane)
	pen.box(Vector3(ax - 0.05, y0 + 0.26, z0 + 0.02), Vector3(ax + 0.02, y0 + 0.285, z1 - 0.02), street.trim)


## A cosy dog bed with a sleepy dog, a bone and a bowl in front of the pet shop (#440).
func _dog_bed(pen: Pen, p: Plan, ax: float, y0: float, reach: float) -> void:
	var cushion: Color = street.play_colors[(p.seed_value + 2) % street.play_colors.size()]
	var rim: Color = street.wood.lightened(0.1)
	var x0: float = ax - 0.22
	var x1: float = ax + 0.14
	var z0: float = reach + 0.02
	var z1: float = reach + 0.3
	pen.box(Vector3(x0, y0, z0), Vector3(x1, y0 + 0.03, z1), rim.darkened(0.15))
	pen.box(Vector3(x0, y0 + 0.03, z0), Vector3(x1, y0 + 0.1, z0 + 0.035), rim)
	pen.box(Vector3(x0, y0 + 0.03, z1 - 0.035), Vector3(x1, y0 + 0.1, z1), rim)
	pen.box(Vector3(x0, y0 + 0.03, z0 + 0.035), Vector3(x0 + 0.035, y0 + 0.1, z1 - 0.035), rim)
	pen.box(Vector3(x1 - 0.035, y0 + 0.03, z0 + 0.035), Vector3(x1, y0 + 0.1, z1 - 0.035), rim)
	pen.box(Vector3(x0 + 0.035, y0 + 0.03, z0 + 0.035), Vector3(x1 - 0.035, y0 + 0.07, z1 - 0.035), cushion)
	var fur: Color = street.wall_colors[2 % street.wall_colors.size()].darkened(0.22).lerp(street.wood, 0.25)
	pen.lump(Vector3(ax - 0.06, y0 + 0.12, (z0 + z1) * 0.5), 0.1, 0.07, 0.08, 0.2, fur, fur.darkened(0.2))
	pen.lump(Vector3(ax + 0.05, y0 + 0.12, (z0 + z1) * 0.5), 0.05, 0.045, 0.045, 0.4, fur.lightened(0.06), fur.darkened(0.2))
	for ear: float in [-0.035, 0.035]:
		pen.box(Vector3(ax + 0.03 - 0.012, y0 + 0.14, (z0 + z1) * 0.5 + ear - 0.012), Vector3(ax + 0.03 + 0.012, y0 + 0.19, (z0 + z1) * 0.5 + ear + 0.012), fur.darkened(0.3))
	pen.box(Vector3(ax + 0.2, y0, reach + 0.1), Vector3(ax + 0.34, y0 + 0.012, reach + 0.14), street.trim)
	pen.box(Vector3(ax + 0.19, y0, reach + 0.095), Vector3(ax + 0.21, y0 + 0.02, reach + 0.145), street.trim)
	pen.box(Vector3(ax + 0.33, y0, reach + 0.095), Vector3(ax + 0.35, y0 + 0.02, reach + 0.145), street.trim)
	pen.box(Vector3(ax + 0.22, y0, reach + 0.2), Vector3(ax + 0.34, y0 + 0.05, reach + 0.3), street.signal_red.lightened(0.1))
	pen.box(Vector3(ax + 0.235, y0 + 0.05, reach + 0.215), Vector3(ax + 0.325, y0 + 0.056, reach + 0.285), street.wood.darkened(0.3))


# --- the back of a house and its garden (#440) ---------------------------------------

## A glazed back door with a pair of pots on its step, a window to the other side and,
## on taller houses, one above the door. Back-local x is the street's u from the house centre.
func _house_back(pen: Pen, p: Plan, cy: float) -> void:
	_door(pen, p.back_u, 0.46, p.door_col.darkened(0.04), true)
	for side: float in [-1.0, 1.0]:
		var px: float = p.back_u + side * 0.4
		if absf(px) > p.width * 0.5 - 0.12:
			continue
		var bloom: Color = street.bloom_colors[(p.seed_value + int(side) + 3) % street.bloom_colors.size()]
		pen.box(Vector3(px - 0.06, 0.0, 0.07), Vector3(px + 0.06, 0.1, 0.19), street.stone.lerp(p.door_col, 0.3))
		pen.lump(Vector3(px, 0.15, 0.13), 0.075, 0.07, 0.075, side + 2.0, bloom, bloom.darkened(0.2))
	_window(pen, -p.back_u, cy, 0.4, 0.4, p.shutters, false, p.seed_value + 9)
	if p.wall_h >= 1.7:
		_window(pen, p.back_u, p.wall_h - 0.38, 0.36, 0.34, false, false, p.seed_value + 10)


static func garden_size(kind: int) -> Vector2:
	match kind:
		Garden.VEG:
			return Vector2(1.3, 0.7)
		Garden.SHED:
			return Vector2(0.85, 0.65)
		Garden.LINE:
			return Vector2(1.7, 0.16)
		Garden.SWING:
			return Vector2(1.3, 0.62)
		Garden.SLIDE:
			return Vector2(0.55, 1.0)
		Garden.TABLE:
			return Vector2(0.95, 0.6)
		Garden.BENCH:
			return Vector2(0.95, 0.36)
		Garden.TREE:
			return Vector2(0.7, 0.7)
		Garden.BIRDBATH:
			return Vector2(0.36, 0.36)
		_:
			return Vector2(0.3, 0.3)


static func garden_height(kind: int) -> float:
	match kind:
		Garden.VEG:
			return 0.18
		Garden.SHED:
			return 0.95
		Garden.LINE:
			return 1.0
		Garden.SWING:
			return 0.95
		Garden.SLIDE:
			return 0.55
		Garden.TABLE:
			return 0.45
		Garden.BENCH:
			return 0.42
		Garden.TREE:
			return 1.1
		Garden.BIRDBATH:
			return 0.42
		Garden.BORDER:
			return 0.15
		_:
			return 0.0


## Plans one house's back garden from integer hashes: a flower border and stepping stones
## sometimes, then three or four things from a small set, each at the best free spot in the
## garden ground (behind the house, inside the side and back hedges), never on the doorstep
## and never repeating the previous house's choices if there is a different one.
func _plan_garden(p: Plan, centre_u: float, back_z: float, recent_kinds: Array[int]) -> void:
	var lot: Rect2 = p.lot
	var zone: Rect2 = Rect2(lot.position.x + GARDEN_SIDE, back_z + GARDEN_EAVE, lot.size.x - GARDEN_SIDE * 2.0,
		lot.end.y - GARDEN_HEDGE - back_z - GARDEN_EAVE)
	p.garden_zone = zone
	var door_u: float = centre_u + p.back_u
	p.doorstep = Rect2(door_u - 0.4, back_z, 0.8, 0.8)
	p.garden.clear()
	var key: int = p.seed_value
	var placed: Array[Rect2] = [p.doorstep]
	var border: bool = _r(key, 72) < 0.55
	var strip: Rect2 = Rect2(zone.position.x, zone.end.y - 0.3, zone.size.x, 0.3)
	if border:
		p.garden.append({"kind": Garden.BORDER, "rect": strip, "height": garden_height(Garden.BORDER), "seed": key})
		placed.append(strip)
	if _r(key, 70) < 0.6:
		var stones: int = 3 + int(_r(key, 71) * 2.0)
		var limit: float = (strip.position.y if border else zone.end.y) - 0.1
		var chain: Rect2 = Rect2(door_u - 0.22, back_z + 0.85, 0.44, float(stones) * 0.34)
		while stones > 2 and chain.end.y > limit:
			stones -= 1
			chain.size.y = float(stones) * 0.34
		if zone.encloses(chain) and chain.end.y <= limit:
			p.garden.append({"kind": Garden.STONES, "rect": chain, "height": 0.0, "seed": key, "count": stones})
			placed.append(chain)
	var pool: Array[int] = [Garden.VEG, Garden.SHED, Garden.LINE, Garden.SWING, Garden.SLIDE, Garden.TABLE, Garden.BENCH,
		Garden.TREE, Garden.BIRDBATH]
	var scores: Array[float] = []
	for kind: int in pool:
		scores.append(_r(key, 60 + kind) + (0.6 if recent_kinds.has(kind) else 0.0))
	var wanted: int = 3 + (1 if _r(key, 59) < 0.5 else 0)
	var chosen: Array[int] = []
	while chosen.size() < pool.size():
		var best: int = -1
		for index: int in pool.size():
			if not chosen.has(pool[index]) and (best < 0 or scores[index] < scores[best]):
				best = index
		chosen.append(pool[best])
		scores[best] = INF
	var taken: Array[int] = []
	for kind: int in chosen:
		if taken.size() >= wanted:
			break
		if (kind == Garden.SWING and taken.has(Garden.SLIDE)) or (kind == Garden.SLIDE and taken.has(Garden.SWING)):
			continue
		if (kind == Garden.TABLE and taken.has(Garden.BENCH)) or (kind == Garden.BENCH and taken.has(Garden.TABLE)):
			continue
		var rect: Variant = _best_garden_spot(p, zone, kind, placed, door_u)
		if rect == null:
			continue
		var spot: Rect2 = rect as Rect2
		p.garden.append({"kind": kind, "rect": spot, "height": garden_height(kind), "seed": key * 13 + kind})
		placed.append(spot)
		taken.append(kind)
	recent_kinds.assign(taken)


func _best_garden_spot(p: Plan, zone: Rect2, kind: int, placed: Array[Rect2], door_u: float) -> Variant:
	var size: Vector2 = garden_size(kind)
	var steps_u: int = int((zone.size.x - size.x) / 0.1)
	var steps_z: int = int((zone.size.y - size.y) / 0.1)
	if steps_u < 0 or steps_z < 0:
		return null
	var best: Variant = null
	var best_score: float = INF
	for iu: int in steps_u + 1:
		for iz: int in steps_z + 1:
			var rect: Rect2 = Rect2(zone.position.x + float(iu) * 0.1, zone.position.y + float(iz) * 0.1, size.x, size.y)
			var free: bool = true
			for other: Rect2 in placed:
				if rect.intersects(other.grow(0.14)):
					free = false
					break
			if not free:
				continue
			var score: float = _garden_preference(kind, rect, zone, door_u) + 0.45 * _r(p.seed_value * 977 + iu * 53 + iz, 80 + kind)
			if score < best_score:
				best_score = score
				best = rect
	return best


## Lower is better. Sheds and trees like the back corners, play sets the back and away from
## the door, tables the house wall beside the door, a washing line the middle.
func _garden_preference(kind: int, rect: Rect2, zone: Rect2, door_u: float) -> float:
	var centre_u: float = rect.position.x + rect.size.x * 0.5
	var back: float = (zone.end.y - rect.end.y) / maxf(zone.size.y, 0.1)
	var edge: float = minf(rect.position.x - zone.position.x, zone.end.x - rect.end.x) / maxf(zone.size.x, 0.1)
	var door_gap: float = minf(absf(centre_u - door_u) / maxf(zone.size.x, 0.1), 1.0)
	match kind:
		Garden.SHED, Garden.TREE:
			return back * 0.9 + edge * 3.0
		Garden.SWING:
			return back * 0.6 + (1.0 - door_gap) * 0.7
		Garden.SLIDE:
			return back * 0.5 + edge * 1.5
		Garden.VEG:
			return back * 0.5 + edge * 1.2
		Garden.TABLE:
			return (1.0 - back) * 1.0 + door_gap * 0.6
		Garden.BENCH:
			return back * 0.4 + edge * 0.8
		Garden.LINE:
			return absf(back - 0.5)
		_:
			return absf(centre_u - (zone.position.x + zone.size.x * 0.5)) / maxf(zone.size.x, 0.1) * 0.8 + (1.0 - back) * 0.2


## Everything planned for this house's back garden, drawn in street-local space.
func _garden(pen: Pen, p: Plan) -> void:
	for item: Dictionary in p.garden:
		var rect: Rect2 = item["rect"]
		var seed_value: int = item["seed"]
		var height: float = item["height"]
		match int(item["kind"]):
			Garden.VEG:
				_g_veg(pen, rect, seed_value)
			Garden.SHED:
				_g_shed(pen, p, rect, seed_value)
			Garden.LINE:
				_g_line(pen, rect, seed_value)
			Garden.SWING:
				_g_swing(pen, rect, seed_value)
			Garden.SLIDE:
				_g_slide(pen, rect, seed_value)
			Garden.TABLE:
				_g_table(pen, rect, seed_value)
			Garden.BENCH:
				_g_bench(pen, rect, seed_value)
			Garden.TREE:
				_g_tree(pen, rect, seed_value)
			Garden.BIRDBATH:
				_g_birdbath(pen, rect, seed_value)
			Garden.BORDER:
				_g_border(pen, rect, seed_value)
			Garden.STONES:
				_g_stones(pen, rect, seed_value, int(item["count"]))
		if height > 0.0 and int(item["kind"]) != Garden.BORDER:
			_garden_shadow(pen, rect, height, p.garden_zone)


## A baked contact shadow on the lawn, the footprint swept along the key light's run.
func _garden_shadow(pen: Pen, rect: Rect2, height: float, zone: Rect2) -> void:
	var corners: PackedVector2Array = PackedVector2Array()
	var push: Vector2 = light_shift * height
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		corners.append(corner)
		corners.append(corner + push)
	var hull: PackedVector2Array = Geometry2D.convex_hull(corners)
	var bounds: Rect2 = zone.grow(0.1)
	var clip: PackedVector2Array = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(hull, clip):
		var points: Array[Vector2] = []
		points.assign(piece)
		if points.size() < 3:
			continue
		var centre: Vector2 = Vector2.ZERO
		for point: Vector2 in points:
			centre += point
		centre /= float(points.size())
		pen.soup.star(centre, points, GARDEN_SHADOW_Y, lawn_shadow)


func _leaf(seed_value: int, attribute: int) -> Color:
	return street.hedge_colors[_pick(street.hedge_colors.size(), seed_value, attribute)]


func _play(seed_value: int, offset: int) -> Color:
	return street.play_colors[(absi(seed_value) + offset) % street.play_colors.size()]


## A raised vegetable bed: three rows of lettuces, cabbages and tomato plants.
func _g_veg(pen: Pen, r: Rect2, seed_value: int) -> void:
	pen.box(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, 0.14, r.position.y + 0.05), street.wood)
	pen.box(Vector3(r.position.x, 0.0, r.end.y - 0.05), Vector3(r.end.x, 0.14, r.end.y), street.wood)
	pen.box(Vector3(r.position.x, 0.0, r.position.y + 0.05), Vector3(r.position.x + 0.05, 0.14, r.end.y - 0.05), street.wood)
	pen.box(Vector3(r.end.x - 0.05, 0.0, r.position.y + 0.05), Vector3(r.end.x, 0.14, r.end.y - 0.05), street.wood)
	pen.box(Vector3(r.position.x + 0.05, 0.0, r.position.y + 0.05), Vector3(r.end.x - 0.05, 0.11, r.end.y - 0.05), street.soil)
	for row: int in 3:
		var z: float = r.position.y + 0.14 + float(row) * (r.size.y - 0.28) * 0.5
		var crop: int = (absi(seed_value) + row) % 3
		var count: int = 3 if crop == 1 else 4
		for index: int in count:
			var x: float = r.position.x + 0.14 + (r.size.x - 0.28) * (float(index) + 0.5) / float(count)
			match crop:
				0:
					var green: Color = _leaf(seed_value, 100 + index).lightened(0.12)
					pen.lump(Vector3(x, 0.17, z), 0.085, 0.06, 0.085, float(index), green, green.darkened(0.2))
				1:
					var cabbage: Color = _leaf(seed_value, 110).lerp(street.glass, 0.35).lightened(0.1)
					pen.lump(Vector3(x, 0.18, z), 0.1, 0.075, 0.1, float(index), cabbage, cabbage.darkened(0.2))
				_:
					var stake: float = x
					pen.box(Vector3(stake - 0.008, 0.1, z - 0.008), Vector3(stake + 0.008, 0.3, z + 0.008), street.wood.lightened(0.2))
					pen.lump(Vector3(x, 0.2, z), 0.06, 0.07, 0.06, float(index), _leaf(seed_value, 120), _leaf(seed_value, 120).darkened(0.25))
					pen.lump(Vector3(x + 0.04, 0.17, z + 0.03), 0.032, 0.032, 0.032, 0.0, street.signal_red, street.signal_red.darkened(0.2))


## A garden shed in a pastel wall, a pitched roof, a door on the side facing the garden and a window.
func _g_shed(pen: Pen, p: Plan, r: Rect2, seed_value: int) -> void:
	var wall: Color = street.wall_colors[_pick(street.wall_colors.size(), seed_value, 130)].darkened(0.08)
	var roof: Color = p.roof_col.darkened(0.1)
	var zc: float = r.position.y + r.size.y * 0.5
	pen.box(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, 0.68, r.end.y), wall)
	pen.box(Vector3(r.position.x - 0.015, 0.0, r.position.y - 0.015), Vector3(r.end.x + 0.015, 0.06, r.end.y + 0.015), street.stone)
	for side: float in [-1.0, 1.0]:
		var zedge: float = r.position.y - 0.07 if side < 0.0 else r.end.y + 0.07
		var base: Array[Vector3] = [Vector3(r.position.x - 0.07, 0.62, zedge), Vector3(r.end.x + 0.07, 0.62, zedge),
			Vector3(r.end.x + 0.07, 0.94, zc), Vector3(r.position.x - 0.07, 0.94, zc)]
		pen.slab(base, _outward_normal(base) * 0.045, roof)
	for end: float in [r.position.x, r.end.x]:
		pen.tri(Vector3(end, 0.68, r.position.y), Vector3(end, 0.68, r.end.y), Vector3(end, 0.93, zc),
			Vector3(1.0 if end > r.position.x else -1.0, 0.0, 0.0), wall)
	pen.box(Vector3(r.position.x - 0.07, 0.93, zc - 0.02), Vector3(r.end.x + 0.07, 0.97, zc + 0.02), roof.darkened(0.12))
	# The door faces the middle of the garden; the window looks out at the hedge.
	var toward_left: bool = (r.position.x + r.size.x * 0.5) > p.garden_zone.position.x + p.garden_zone.size.x * 0.5
	var face: float = r.position.x if toward_left else r.end.x
	var out: float = -0.02 if toward_left else 0.02
	var lo: float = minf(face, face + out)
	var hi: float = maxf(face, face + out)
	var door: Color = street.door_colors[_pick(street.door_colors.size(), seed_value, 131)]
	pen.box(Vector3(lo, 0.0, zc - 0.16), Vector3(hi, 0.56, zc + 0.16), street.trim)
	lo = minf(face, face + out * 1.6)
	hi = maxf(face, face + out * 1.6)
	pen.box(Vector3(lo, 0.0, zc - 0.13), Vector3(hi, 0.53, zc + 0.13), door)
	pen.box(Vector3(r.position.x + 0.12, 0.3, r.end.y - 0.005), Vector3(r.end.x - 0.12, 0.54, r.end.y + 0.02), street.trim)
	pen.box(Vector3(r.position.x + 0.15, 0.33, r.end.y), Vector3(r.end.x - 0.15, 0.51, r.end.y + 0.03), street.glass)


## Two poles, a line and a few pastel cloths hanging from it.
func _g_line(pen: Pen, r: Rect2, seed_value: int) -> void:
	var zc: float = r.position.y + r.size.y * 0.5
	for x: float in [r.position.x + 0.04, r.end.x - 0.04]:
		pen.box(Vector3(x - 0.02, 0.0, zc - 0.02), Vector3(x + 0.02, 1.0, zc + 0.02), street.wood)
		pen.box(Vector3(x - 0.035, 0.0, zc - 0.035), Vector3(x + 0.035, 0.04, zc + 0.035), street.stone)
		pen.box(Vector3(x - 0.03, 1.0, zc - 0.03), Vector3(x + 0.03, 1.035, zc + 0.03), street.wood.lightened(0.15))
	pen.box(Vector3(r.position.x + 0.04, 0.945, zc - 0.006), Vector3(r.end.x - 0.04, 0.96, zc + 0.006), street.metal)
	var x_cursor: float = r.position.x + 0.2
	var index: int = 0
	while x_cursor < r.end.x - 0.3:
		var wide: float = 0.1 + 0.07 * _r(seed_value, 140 + index)
		var drop: float = 0.16 + 0.14 * _r(seed_value, 150 + index)
		var colour: Color = street.laundry_colors[(absi(seed_value) + index) % street.laundry_colors.size()]
		pen.box(Vector3(x_cursor, 0.945 - drop, zc - 0.012), Vector3(x_cursor + wide, 0.955, zc + 0.012), colour)
		pen.box(Vector3(x_cursor, 0.945 - drop, zc - 0.012), Vector3(x_cursor + wide, 0.945 - drop + 0.025, zc + 0.014), colour.darkened(0.12))
		x_cursor += wide + 0.12 + 0.08 * _r(seed_value, 160 + index)
		index += 1


## A leg of a play set: a slanted strip from foot to top.
func _strip(pen: Pen, foot: Vector3, top: Vector3, across: Vector3, colour: Color) -> void:
	var base: Array[Vector3] = [foot - across, foot + across, top + across, top - across]
	var normal: Vector3 = (base[1] - base[0]).cross(base[3] - base[0]).normalized()
	pen.slab(base, normal * 0.04, colour)


## A little swing set: two A-frames, a top bar and two swings.
func _g_swing(pen: Pen, r: Rect2, seed_value: int) -> void:
	var zc: float = r.position.y + r.size.y * 0.5
	var frame: Color = _play(seed_value, 0)
	for x: float in [r.position.x + 0.07, r.end.x - 0.07]:
		_strip(pen, Vector3(x, 0.0, r.position.y + 0.04), Vector3(x, 0.94, zc), Vector3(0.025, 0.0, 0.0), frame)
		_strip(pen, Vector3(x, 0.0, r.end.y - 0.04), Vector3(x, 0.94, zc), Vector3(0.025, 0.0, 0.0), frame)
	pen.box(Vector3(r.position.x + 0.04, 0.9, zc - 0.025), Vector3(r.end.x - 0.04, 0.97, zc + 0.025), frame.darkened(0.12))
	for index: int in 2:
		var x: float = r.position.x + r.size.x * (0.34 + 0.32 * float(index))
		for rope: float in [-0.07, 0.07]:
			pen.box(Vector3(x + rope - 0.008, 0.26, zc - 0.008), Vector3(x + rope + 0.008, 0.9, zc + 0.008), street.trim.darkened(0.15))
		pen.box(Vector3(x - 0.1, 0.22, zc - 0.05), Vector3(x + 0.1, 0.26, zc + 0.05), _play(seed_value, 2 + index))


## A tiny slide: a platform with a ladder on the house side and a long slope.
func _g_slide(pen: Pen, r: Rect2, seed_value: int) -> void:
	var tower: Color = _play(seed_value, 1)
	var z1: float = r.position.y + 0.3
	for x: float in [r.position.x + 0.04, r.end.x - 0.04]:
		for z: float in [r.position.y + 0.04, z1 - 0.04]:
			pen.box(Vector3(x - 0.025, 0.0, z - 0.025), Vector3(x + 0.025, 0.5, z + 0.025), tower.darkened(0.1))
	pen.box(Vector3(r.position.x, 0.5, r.position.y), Vector3(r.end.x, 0.55, z1), tower)
	for rung: int in 3:
		var y: float = 0.1 + 0.13 * float(rung)
		pen.box(Vector3(r.position.x + 0.05, y, r.position.y - 0.012), Vector3(r.end.x - 0.05, y + 0.025, r.position.y + 0.012), street.wood.lightened(0.1))
	var slope: Color = _play(seed_value, 4)
	var inset: float = 0.07
	var base: Array[Vector3] = [Vector3(r.position.x + inset, 0.5, z1), Vector3(r.end.x - inset, 0.5, z1),
		Vector3(r.end.x - inset, 0.07, r.end.y), Vector3(r.position.x + inset, 0.07, r.end.y)]
	pen.slab(base, Vector3(0.0, 0.03, 0.0), slope)
	for lip: float in [r.position.x + inset, r.end.x - inset - 0.03]:
		var rail: Array[Vector3] = [Vector3(lip, 0.5, z1), Vector3(lip + 0.03, 0.5, z1), Vector3(lip + 0.03, 0.07, r.end.y), Vector3(lip, 0.07, r.end.y)]
		pen.slab(rail, Vector3(0.0, 0.07, 0.0), slope.darkened(0.14))


## A little table with two chairs and, sometimes, a parasol.
func _g_table(pen: Pen, r: Rect2, seed_value: int) -> void:
	var cx: float = r.position.x + r.size.x * 0.5
	var cz: float = r.position.y + r.size.y * 0.5
	var wood: Color = street.wood.lightened(0.1)
	pen.box(Vector3(cx - 0.21, 0.3, cz - 0.16), Vector3(cx + 0.21, 0.34, cz + 0.16), wood)
	pen.box(Vector3(cx - 0.035, 0.04, cz - 0.035), Vector3(cx + 0.035, 0.3, cz + 0.035), wood.darkened(0.15))
	pen.box(Vector3(cx - 0.12, 0.0, cz - 0.1), Vector3(cx + 0.12, 0.04, cz + 0.1), wood.darkened(0.15))
	for side: float in [-1.0, 1.0]:
		var x: float = cx + side * 0.36
		pen.box(Vector3(x - 0.085, 0.0, cz - 0.085), Vector3(x + 0.085, 0.19, cz + 0.085), wood.darkened(0.2))
		pen.box(Vector3(x - 0.1, 0.19, cz - 0.1), Vector3(x + 0.1, 0.23, cz + 0.1), _play(seed_value, int(side) + 3))
		var back_x: float = x + side * 0.085
		pen.box(Vector3(minf(back_x, back_x + side * 0.025), 0.23, cz - 0.1), Vector3(maxf(back_x, back_x + side * 0.025), 0.42, cz + 0.1), wood.darkened(0.1))
	if _r(seed_value, 170) < 0.5:
		pen.box(Vector3(cx - 0.008, 0.34, cz - 0.008), Vector3(cx + 0.008, 0.82, cz + 0.008), street.trim)
		var cloth: Color = _play(seed_value, 5)
		pen.lump(Vector3(cx, 0.78, cz), 0.36, 0.1, 0.36, 0.2, cloth.lightened(0.1), cloth.darkened(0.15))
	else:
		pen.box(Vector3(cx - 0.05, 0.34, cz - 0.04), Vector3(cx + 0.05, 0.37, cz + 0.04), street.trim)
		var jug: Color = _play(seed_value, 1)
		pen.box(Vector3(cx - 0.04, 0.34, cz - 0.03), Vector3(cx + 0.04, 0.44, cz + 0.03), jug)


## A bench along the back hedge with a pot of flowers on its end.
func _g_bench(pen: Pen, r: Rect2, seed_value: int) -> void:
	var wood: Color = street.wood.lightened(0.12)
	pen.box(Vector3(r.position.x + 0.03, 0.19, r.position.y + 0.04), Vector3(r.end.x - 0.03, 0.23, r.end.y - 0.1), wood)
	pen.box(Vector3(r.position.x + 0.03, 0.23, r.end.y - 0.1), Vector3(r.end.x - 0.03, 0.4, r.end.y - 0.07), wood.darkened(0.08))
	for x: float in [r.position.x + 0.07, r.end.x - 0.07]:
		pen.box(Vector3(x - 0.03, 0.0, r.position.y + 0.06), Vector3(x + 0.03, 0.19, r.end.y - 0.12), wood.darkened(0.25))
	var bloom: Color = street.bloom_colors[(absi(seed_value) + 2) % street.bloom_colors.size()]
	pen.box(Vector3(r.end.x - 0.2, 0.23, r.position.y + 0.08), Vector3(r.end.x - 0.08, 0.31, r.position.y + 0.2), street.stone.lerp(bloom, 0.3))
	pen.lump(Vector3(r.end.x - 0.14, 0.36, r.position.y + 0.14), 0.07, 0.06, 0.07, 0.0, bloom, bloom.darkened(0.2))


## A small fruit tree in blossom.
func _g_tree(pen: Pen, r: Rect2, seed_value: int) -> void:
	var cx: float = r.position.x + r.size.x * 0.5
	var cz: float = r.position.y + r.size.y * 0.5
	var leaf: Color = _leaf(seed_value, 180)
	pen.box(Vector3(cx - 0.04, 0.0, cz - 0.04), Vector3(cx + 0.04, 0.55, cz + 0.04), street.wood.darkened(0.25))
	pen.lump(Vector3(cx, 0.84, cz), 0.3, 0.3, 0.3, 0.3, leaf.lightened(0.06), leaf.darkened(0.22))
	pen.lump(Vector3(cx + 0.05, 1.07, cz - 0.03), 0.2, 0.2, 0.2, 0.9, leaf.lightened(0.12), leaf.darkened(0.15))
	var fruit: Color = street.signal_red.lightened(0.1) if _r(seed_value, 181) < 0.5 else street.bloom_colors[0]
	for index: int in 5:
		var angle: float = 1.3 * float(index) + float(seed_value % 5)
		pen.lump(Vector3(cx + cos(angle) * 0.27, 0.78 + 0.12 * float(index % 3), cz + sin(angle) * 0.27), 0.034, 0.034, 0.034, 0.0, fruit, fruit.darkened(0.2))


## A stone birdbath: foot, stem and a shallow bowl.
func _g_birdbath(pen: Pen, r: Rect2, _seed_value: int) -> void:
	var cx: float = r.position.x + r.size.x * 0.5
	var cz: float = r.position.y + r.size.y * 0.5
	var stone: Color = street.stone.lightened(0.1)
	pen.box(Vector3(cx - 0.1, 0.0, cz - 0.1), Vector3(cx + 0.1, 0.05, cz + 0.1), stone.darkened(0.12))
	pen.box(Vector3(cx - 0.04, 0.05, cz - 0.04), Vector3(cx + 0.04, 0.3, cz + 0.04), stone)
	pen.box(Vector3(cx - 0.17, 0.3, cz - 0.17), Vector3(cx + 0.17, 0.37, cz + 0.17), stone.lightened(0.06))
	pen.box(Vector3(cx - 0.14, 0.37, cz - 0.14), Vector3(cx + 0.14, 0.385, cz + 0.14), street.glass.lightened(0.2))
	var bird: Color = street.bird_colors[0] if not street.bird_colors.is_empty() else street.wood
	pen.lump(Vector3(cx + 0.05, 0.4, cz - 0.04), 0.04, 0.035, 0.03, 0.0, bird, bird.darkened(0.2))


## A bed of flowers along the back hedge.
func _g_border(pen: Pen, r: Rect2, seed_value: int) -> void:
	pen.box(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, 0.05, r.end.y), street.soil)
	var count: int = maxi(4, roundi(r.size.x / 0.3))
	for index: int in count:
		var x: float = r.position.x + (r.size.x - 0.2) * (float(index) + 0.5) / float(count) + 0.1
		var bloom: Color = street.bloom_colors[(absi(seed_value) + index) % street.bloom_colors.size()]
		var z: float = r.position.y + 0.1 + 0.1 * float(index % 2)
		if index % 3 == 0:
			pen.box(Vector3(x - 0.007, 0.05, z - 0.007), Vector3(x + 0.007, 0.26, z + 0.007), _leaf(seed_value, 190))
			pen.lump(Vector3(x, 0.29, z), 0.055, 0.05, 0.055, float(index), bloom, bloom.darkened(0.2))
		else:
			pen.lump(Vector3(x, 0.11, z), 0.07, 0.06, 0.07, float(index), bloom, bloom.darkened(0.2))


## Flat stepping stones leading from the back door out into the garden.
func _g_stones(pen: Pen, r: Rect2, seed_value: int, count: int) -> void:
	for index: int in count:
		var z: float = r.position.y + 0.17 + 0.34 * float(index)
		var x: float = r.position.x + r.size.x * 0.5 + (_r(seed_value, 200 + index) - 0.5) * 0.12
		var wide: float = 0.12 + 0.03 * _r(seed_value, 210 + index)
		var deep: float = 0.09 + 0.02 * _r(seed_value, 220 + index)
		var tone: Color = street.stone.lerp(street.path, 0.25 * _r(seed_value, 230 + index)).lightened(0.05)
		pen.box(Vector3(x - wide, 0.0, z - deep), Vector3(x + wide, 0.03, z + deep), tone)
		pen.box(Vector3(x - wide, 0.03, z - deep), Vector3(x + wide, 0.034, z + deep), tone.lightened(0.08))
