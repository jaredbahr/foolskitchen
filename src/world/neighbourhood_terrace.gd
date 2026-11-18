class_name NeighbourhoodTerrace
extends RefCounted
## A named terrace of neighbours beside the lot (#596, D39): the shops in a
## StreetSet's `terrace_left` and `terrace_right`, in order outward from the lot,
## each its own piece the view can show trading or closed and for sale (and later,
## #597, bought and knocked through). NeighbourhoodBuildings plans and meshes the
## shells; this class adds what is particular to a terrace: the four building forms
## (a shop, a hatch kiosk, a beach hut and an arcade front), the stock each sets out
## (kept in its own mesh so a closed shop can take it in) and the closed, for-sale
## dressing. Same rules as the rest of the street: vertex-coloured boxes, integer
## hashes, no random draws, authored in building-local space (facade at z = 0 facing
## +z, body behind it).

## The gap between two terrace pieces when either is a hut or a kiosk (they stand apart).
const LOOSE_GAP: float = 0.36
## The roller shutter's slat pitch and the whitewash streaks' spacing.
const SLAT: float = 0.06
const STREAK: float = 0.11
## Where a SHOP form's painted name sits: the sign board above the awning (see `_shop_front`).
const BOARD_LO: float = 1.38
const BOARD_TOP_MAX: float = 1.64
## The for-sale board on its post: the face's centre height and how far out it stands.
const SALE_POST_Y: float = 1.02
const SALE_POST_Z: float = 0.46
## The terrace stands wall to wall with the lot (#600): the next-door walls sit this far
## outside the maximum lot, just enough that their eaves (and bounds) clear it.
const SNUG: float = NeighbourhoodBuildings.EAVE + 0.04
## The walled back yards behind the shops that share the lot's row (#600).
const YARD_WALL_H: float = 0.62
const YARD_WALL_T: float = 0.1
const YARD_GATE: float = 0.5
## The lot's own side strips meet the street with a taller wall and gate (#600), just
## outside the lot on the paving, so the frontage runs on unbroken from door to door.
const FRONT_WALL_H: float = 0.92
const FRONT_WALL_T: float = 0.08

var b: NeighbourhoodBuildings


func _init(builder: NeighbourhoodBuildings) -> void:
	b = builder


func _street() -> StreetSet:
	return b.street


# --- planning ---------------------------------------------------------------

## Plans both rows of the terrace into the builder's `plans`.
func plan_rows() -> void:
	var street: StreetSet = _street()
	for side_index: int in 2:
		var side: float = -1.0 if side_index == 0 else 1.0
		var row: Array[ShopStyle] = street.terrace_left if side_index == 0 else street.terrace_right
		var edge: float = b.local_reserve.position.x - SNUG if side < 0.0 else b.local_reserve.end.x + SNUG
		var recent_h: Array[int] = []
		# The shops that run on unbroken from the lot share its back line: each gets a
		# walled yard back to it, so no grass shows between the lot and the row.
		var joined: bool = true
		var recent_roof: Array[int] = []
		for slot: int in row.size():
			var style: ShopStyle = row[slot]
			var index: int = 40 + side_index * 10 + slot
			var p: NeighbourhoodBuildings.Plan = NeighbourhoodBuildings.Plan.new()
			p.id = "Shop%d" % index
			p.neighbour_id = style.id
			p.is_shop = true
			p.style = style
			p.form = style.form
			p.seed_value = index
			p.wall = style.wall
			p.door_col = style.door
			p.roof_col = street.roof_colors[b._pick(street.roof_colors.size(), index, 5)]
			_size(p, style, index, recent_h, recent_roof)
			var centre: float = edge + side * p.width * 0.5
			var next_gap: float = _gap(style, row[slot + 1] if slot + 1 < row.size() else null)
			edge += side * (p.width + next_gap)
			p.xf = Transform3D(Basis.IDENTITY, Vector3(centre, 0.0, b.shift - NeighbourhoodBuildings.FRONT_INSET))
			var toward_lot: int = 1 if side < 0.0 else 2
			var outward: int = 2 if side < 0.0 else 1
			# Next door's wall facing the lot is a blank party wall (#600).
			var before_gap: float = _gap(row[slot - 1], style) if slot > 0 else 0.0
			p.exposed = 0
			if before_gap > NeighbourhoodBuildings.ROW_GAP + 0.01:
				p.exposed |= toward_lot
			joined = joined and before_gap <= NeighbourhoodBuildings.ROW_GAP + 0.01 \
				and (p.form == ShopStyle.Form.SHOP or p.form == ShopStyle.Form.ARCADE)
			var back: float = b.local_reserve.position.z - p.xf.origin.z
			if joined and back < -p.depth - 0.4:
				p.yard_back = back
			if slot == row.size() - 1 or next_gap > NeighbourhoodBuildings.ROW_GAP + 0.01:
				p.exposed |= outward
			p.bounds = b._bounds_of(p)
			b.plans.append(p)


func _gap(a: ShopStyle, c: ShopStyle) -> float:
	if c == null:
		return 0.0
	var loose: Array[int] = [ShopStyle.Form.HUT, ShopStyle.Form.KIOSK]
	return LOOSE_GAP if loose.has(int(a.form)) or loose.has(int(c.form)) else NeighbourhoodBuildings.ROW_GAP


func _size(p: NeighbourhoodBuildings.Plan, style: ShopStyle, index: int, recent_h: Array[int], recent_roof: Array[int]) -> void:
	var street: StreetSet = _street()
	match style.form:
		ShopStyle.Form.KIOSK:
			p.width = style.width if style.width > 0.0 else 1.9
			p.depth = 1.7
			p.wall_h = 1.45
			p.roof = StreetSet.Roof.FLAT
			p.roof_h = 0.2
			p.door_x = 0.0
		ShopStyle.Form.HUT:
			p.width = style.width if style.width > 0.0 else 1.2
			p.depth = 1.35
			p.wall_h = 1.02
			p.roof = StreetSet.Roof.GABLE_FRONT
			p.roof_h = 0.46
			p.door_x = 0.0
		ShopStyle.Form.ARCADE:
			p.width = style.width if style.width > 0.0 else 3.6
			p.depth = 3.6
			p.wall_h = 1.72
			p.roof = StreetSet.Roof.FALSE_FRONT
			p.roof_h = 0.66
			p.door_x = 0.0
		_:
			p.width = style.width if style.width > 0.0 else 2.6 + 0.1 * float(int(b._r(index, 1) * 9.0))
			p.depth = 3.2 + 0.2 * float(int(b._r(index, 2) * 7.0))
			var height_choice: int = b._pick_distinct(street.shop_heights.size(), index, 3, recent_h)
			recent_h.assign([height_choice])
			p.wall_h = street.shop_heights[height_choice]
			var roof_choice: int = b._pick_distinct(street.shop_roofs.size(), index, 4, recent_roof)
			recent_roof.assign([roof_choice])
			p.roof = street.shop_roofs[roof_choice]
			p.roof_h = b._roof_height(p.roof, index)
			p.door_x = (-1.0 if b._r(index, 6) < 0.5 else 1.0) * (p.width * 0.5 - 0.42)
			p.flowers = b._r(index, 7) < 0.4
			p.sign_x = signf(p.door_x) * (p.width * 0.5 - 0.09)
	if p.roof == StreetSet.Roof.FLAT or p.roof == StreetSet.Roof.FALSE_FRONT:
		# A flat roof is felt and gravel, not a painted roof's colour.
		p.roof_col = street.metal.lightened(0.22)
	while p.total_height() > NeighbourhoodBuildings.MAX_NEAR_HEIGHT + 0.0001 and p.roof_h > 0.2:
		p.roof_h -= 0.05
	p.wall_h = minf(p.wall_h, NeighbourhoodBuildings.MAX_NEAR_HEIGHT - p.roof_h)


## A SHOP form's shop window, in building-local x (the same rule as `_shop_front`).
static func window_span(p: NeighbourhoodBuildings.Plan) -> Vector2:
	var hw: float = p.width * 0.5
	var side: float = signf(p.door_x)
	var x0: float = -hw + 0.2 if side > 0.0 else p.door_x + 0.42
	var x1: float = p.door_x - 0.42 if side > 0.0 else hw - 0.2
	return Vector2(x0, x1)


## Where the neighbour's painted name goes (building-local centre on the board face, and
## its size), or an empty dictionary when it has none.
static func sign_board(p: NeighbourhoodBuildings.Plan) -> Dictionary:
	if p.style == null or p.style.sign_text.is_empty():
		return {}
	var hw: float = p.width * 0.5
	match p.form:
		ShopStyle.Form.KIOSK:
			return {"centre": Vector3(0.0, p.wall_h + 0.16, 0.075), "size": Vector2(p.width - 0.2, 0.22)}
		ShopStyle.Form.ARCADE:
			return {"centre": Vector3(0.0, p.wall_h + p.roof_h * 0.31, 0.065), "size": Vector2(p.width - 0.6, 0.27)}
		ShopStyle.Form.HUT:
			return {"centre": Vector3(0.0, p.wall_h - 0.08, 0.03), "size": Vector2(p.width - 0.3, 0.08)}
		_:
			var top: float = minf(p.wall_h - 0.08, BOARD_TOP_MAX)
			return {"centre": Vector3(0.0, (BOARD_LO + top) * 0.5, 0.045), "size": Vector2((hw - 0.28) * 2.0 - 0.1, top - BOARD_LO - 0.04)}


## Where the FOR SALE board's face is (building-local centre and size): an agent's
## board on a post out on the paving, or on a beach hut's door.
static func sale_board(p: NeighbourhoodBuildings.Plan) -> Dictionary:
	if p.form == ShopStyle.Form.HUT:
		return {"centre": Vector3(0.0, 0.62, 0.07), "size": Vector2(0.44, 0.16)}
	return {"centre": Vector3(sale_post_x(p), SALE_POST_Y, SALE_POST_Z + 0.03), "size": Vector2(0.56, 0.2)}


## The agent's board stands at the end of the facade away from the door.
static func sale_post_x(p: NeighbourhoodBuildings.Plan) -> float:
	var side: float = -signf(p.door_x) if p.door_x != 0.0 else 1.0
	return side * (p.width * 0.5 - 0.42)


# --- facades ----------------------------------------------------------------

## The facade of a kiosk, hut or arcade (a SHOP form uses the builder's own shop front).
## `stock` takes what the neighbour sets out, so it can be taken in when it closes.
func front(pen: NeighbourhoodBuildings.Pen, stock: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan) -> void:
	match p.form:
		ShopStyle.Form.KIOSK:
			_kiosk(pen, stock, p)
		ShopStyle.Form.HUT:
			_hut(pen, stock, p)
		ShopStyle.Form.ARCADE:
			_arcade(pen, stock, p)


## A chip kiosk: a serving hatch with a counter under a striped awning and a tall
## painted fascia on the roof.
func _kiosk(pen: NeighbourhoodBuildings.Pen, stock: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan) -> void:
	var street: StreetSet = _street()
	var style: ShopStyle = p.style
	var hw: float = p.width * 0.5
	var hatch: float = minf(0.62, hw - 0.22)
	var lo: float = 0.52
	var hi: float = 1.08
	# A wooden apron below, the hatch's frame and its dim interior with a lit back.
	pen.box(Vector3(-hw + 0.04, 0.1, 0.0), Vector3(hw - 0.04, lo - 0.06, 0.02), style.awning_b.darkened(0.06))
	for index: int in 3:
		var x: float = -hw + 0.04 + (p.width - 0.08) * float(index + 1) / 4.0
		pen.box(Vector3(x - 0.01, 0.12, 0.0), Vector3(x + 0.01, lo - 0.08, 0.028), style.awning_b.darkened(0.2))
	pen.box(Vector3(-hatch - 0.05, lo - 0.05, 0.0), Vector3(hatch + 0.05, hi + 0.05, 0.016), street.trim)
	pen.box(Vector3(-hatch, lo, 0.0), Vector3(hatch, hi, 0.022), street.glass.darkened(0.45))
	pen.box(Vector3(-hatch, hi - 0.16, 0.0), Vector3(hatch, hi - 0.1, 0.028), street.metal)
	b._glow(pen, 0.0, (lo + hi) * 0.5, hatch - 0.02, (hi - lo) * 0.5 - 0.02, 0.025)
	# The counter.
	pen.box(Vector3(-hatch - 0.08, lo - 0.05, 0.0), Vector3(hatch + 0.08, lo, 0.2), street.wood.lightened(0.12))
	pen.box(Vector3(-hatch - 0.08, lo - 0.08, 0.17), Vector3(hatch + 0.08, lo - 0.05, 0.2), street.wood.darkened(0.15))
	b._awning(stock, p)
	# The fascia: a tall board on the roof's front edge, framed in the stripe colour.
	var top: float = p.wall_h + 0.32
	pen.box(Vector3(-hw - 0.03, p.wall_h - 0.02, 0.0), Vector3(hw + 0.03, top, 0.05), style.awning_a)
	pen.box(Vector3(-hw + 0.04, p.wall_h + 0.04, 0.0), Vector3(hw - 0.04, top - 0.05, 0.065), style.sign_board)
	if style.accent == ShopStyle.Accent.CHIPS:
		_chips(stock, p, hatch, lo)


func _chips(pen: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan, hatch: float, lo: float) -> void:
	var street: StreetSet = _street()
	var paper: Color = street.trim
	var chip: Color = Color("e6c876")
	# Paper cones of chips on the counter, a salt shaker and a vinegar bottle.
	for index: int in 3:
		var x: float = -hatch + 0.14 + 0.13 * float(index)
		pen.box(Vector3(x - 0.04, lo, 0.07), Vector3(x + 0.04, lo + 0.09, 0.15), paper)
		pen.lump(Vector3(x, lo + 0.1, 0.11), 0.045, 0.035, 0.04, float(index), chip, chip.darkened(0.15))
	pen.box(Vector3(hatch - 0.2, lo, 0.08), Vector3(hatch - 0.16, lo + 0.08, 0.12), street.trim.darkened(0.05))
	pen.box(Vector3(hatch - 0.13, lo, 0.08), Vector3(hatch - 0.09, lo + 0.13, 0.12), Color("7c3843"))
	pen.box(Vector3(hatch - 0.12, lo + 0.13, 0.09), Vector3(hatch - 0.1, lo + 0.16, 0.11), street.trim)
	# A chalk A-board on the paving: today's fish.
	_a_board(pen, Vector3(-p.width * 0.5 + 0.25, b.paving_top, 0.48), street)


## A little chalk A-board standing on the paving, face to the street.
func _a_board(pen: NeighbourhoodBuildings.Pen, at: Vector3, street: StreetSet) -> void:
	var frame: Color = street.wood
	var slate: Color = Color("45342b").lerp(Color("41604a"), 0.5)
	var saved: Transform3D = pen.xf
	pen.xf = saved * Transform3D(Basis(Vector3.RIGHT, -0.22), at)
	pen.box(Vector3(-0.16, 0.0, -0.02), Vector3(0.16, 0.44, 0.0), frame)
	pen.box(Vector3(-0.13, 0.04, 0.0), Vector3(0.13, 0.41, 0.008), slate)
	for row: int in 4:
		var y: float = 0.33 - 0.07 * float(row)
		var reach: float = 0.1 - 0.025 * float(row % 2)
		pen.box(Vector3(-0.1, y, 0.008), Vector3(-0.1 + reach * 2.0 * 0.85, y + 0.018, 0.012), street.trim)
	pen.xf = saved * Transform3D(Basis(Vector3.RIGHT, 0.22), at + Vector3(0.0, 0.0, -0.17))
	pen.box(Vector3(-0.16, 0.0, 0.0), Vector3(0.16, 0.44, 0.02), frame.darkened(0.1))
	pen.xf = saved


## A beach hut: tongue-and-groove boards, double doors under a front gable, a little
## deck, and its number on the lintel.
func _hut(pen: NeighbourhoodBuildings.Pen, stock: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan) -> void:
	var street: StreetSet = _street()
	var style: ShopStyle = p.style
	var hw: float = p.width * 0.5
	var seam: Color = p.wall.darkened(0.14)
	var striped: bool = style.awning_a != style.wall
	var boards: int = int((p.width - 0.04) / 0.12)
	for index: int in boards:
		var x0: float = -hw + 0.02 + float(index) * (p.width - 0.04) / float(boards)
		var x1: float = x0 + (p.width - 0.04) / float(boards)
		if striped and index % 2 == 1:
			pen.box(Vector3(x0, 0.1, 0.0), Vector3(x1, p.wall_h, 0.006), style.awning_a)
		pen.box(Vector3(x1 - 0.006, 0.1, 0.0), Vector3(x1 + 0.006, p.wall_h, 0.01), seam)
	# Corner boards and the lintel.
	for x: float in [-hw - 0.01, hw - 0.04]:
		pen.box(Vector3(x, 0.08, 0.0), Vector3(x + 0.05, p.wall_h, 0.03), street.trim)
	var door_w: float = minf(0.66, p.width - 0.36)
	var door_h: float = 0.8
	pen.box(Vector3(-door_w * 0.5 - 0.05, 0.1, 0.0), Vector3(door_w * 0.5 + 0.05, door_h + 0.15, 0.022), street.trim)
	for half: float in [-1.0, 1.0]:
		var x0: float = 0.0 if half > 0.0 else -door_w * 0.5
		var x1: float = door_w * 0.5 if half > 0.0 else 0.0
		pen.box(Vector3(x0 + 0.008, 0.1, 0.0), Vector3(x1 - 0.008, door_h + 0.1, 0.034), style.door)
		pen.box(Vector3(x0 + 0.05, door_h * 0.62, 0.0), Vector3(x1 - 0.05, door_h + 0.04, 0.042), style.door.lightened(0.16))
		pen.box(Vector3(x0 + 0.05, 0.2, 0.0), Vector3(x1 - 0.05, door_h * 0.5, 0.042), style.door.lightened(0.1))
	pen.box(Vector3(0.04, door_h * 0.5, 0.0), Vector3(0.07, door_h * 0.5 + 0.06, 0.05), Color("c9a23a"))
	# A round window in the gable.
	pen.disc(0.0, p.wall_h + p.roof_h * 0.36, 0.11, 0.0, 0.03, street.trim)
	pen.disc(0.0, p.wall_h + p.roof_h * 0.36, 0.075, 0.0, 0.045, street.glass)
	# The deck it stands on.
	var deck: Color = street.wood.lightened(0.06)
	pen.box(Vector3(-hw - 0.06, 0.0, -0.02), Vector3(hw + 0.06, 0.1, 0.32), deck)
	for index: int in 4:
		var z: float = 0.32 * float(index + 1) / 4.0
		pen.box(Vector3(-hw - 0.06, 0.1, z - 0.006), Vector3(hw + 0.06, 0.104, z + 0.006), deck.darkened(0.18))
	if style.accent == ShopStyle.Accent.DECKCHAIRS:
		_deckchair(stock, Vector3(hw + 0.02, b.paving_top, 0.62), style, p.seed_value)


## A striped deckchair beside a hut, facing the street.
func _deckchair(pen: NeighbourhoodBuildings.Pen, at: Vector3, style: ShopStyle, seed_value: int) -> void:
	var street: StreetSet = _street()
	var frame: Color = street.wood
	var saved: Transform3D = pen.xf
	pen.xf = saved * Transform3D(Basis(Vector3.UP, 0.35 if seed_value % 2 == 0 else -0.35), at)
	for x: float in [-0.17, 0.17]:
		pen.box(Vector3(x - 0.015, 0.0, -0.2), Vector3(x + 0.015, 0.03, 0.2), frame)
	pen.xf = pen.xf * Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(0.0, 0.03, 0.15))
	for x: float in [-0.17, 0.17]:
		pen.box(Vector3(x - 0.015, 0.0, -0.015), Vector3(x + 0.015, 0.5, 0.015), frame)
	var stripes: int = 6
	for index: int in stripes:
		var x0: float = -0.155 + 0.31 * float(index) / float(stripes)
		var x1: float = -0.155 + 0.31 * float(index + 1) / float(stripes)
		pen.box(Vector3(x0, 0.05, -0.012), Vector3(x1, 0.46, 0.0), style.awning_a if index % 2 == 0 else style.awning_b)
	pen.xf = saved


## An amusement arcade: a wide open front between piers with the machines glowing inside,
## a striped awning, and a tall parapet with its name ringed in bulbs.
func _arcade(pen: NeighbourhoodBuildings.Pen, stock: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan) -> void:
	var street: StreetSet = _street()
	var style: ShopStyle = p.style
	var hw: float = p.width * 0.5
	var open: float = hw - 0.42
	var top: float = 1.12
	pen.box(Vector3(-open, 0.08, 0.0), Vector3(open, top, 0.01), Color("2b2230").lerp(style.awning_a, 0.12))
	pen.box(Vector3(-open, 0.06, 0.0), Vector3(open, 0.1, 0.16), street.stone.lightened(0.1))
	for x: float in [-hw, open]:
		pen.box(Vector3(x - 0.01, 0.0, 0.0), Vector3(x + hw - open + 0.01, 0.12, 0.07), street.stone)
		pen.box(Vector3(x + 0.04, 0.12, 0.0), Vector3(x + hw - open - 0.04, top, 0.03), p.wall.lightened(0.08))
	pen.box(Vector3(-open - 0.02, top, 0.0), Vector3(open + 0.02, top + 0.06, 0.04), street.trim)
	b._awning(stock, p)
	# The parapet board, its rim and a ring of bulbs.
	var board: Dictionary = sign_board(p)
	var centre: Vector3 = board["centre"] if not board.is_empty() else Vector3(0.0, p.wall_h + p.roof_h * 0.31, 0.065)
	var half: Vector2 = (board["size"] if not board.is_empty() else Vector2(p.width - 0.6, 0.27)) * 0.5 + Vector2(0.08, 0.06)
	pen.box(Vector3(-half.x - 0.03, centre.y - half.y - 0.03, 0.0), Vector3(half.x + 0.03, centre.y + half.y + 0.03, 0.05), style.awning_a)
	pen.box(Vector3(-half.x, centre.y - half.y, 0.0), Vector3(half.x, centre.y + half.y, 0.06), style.sign_board)
	var bulbs: Array[Vector2] = []
	var across: int = int(half.x * 2.0 / 0.16)
	for index: int in across + 1:
		var x: float = -half.x + half.x * 2.0 * float(index) / float(across)
		bulbs.append(Vector2(x, centre.y + half.y + 0.0))
		bulbs.append(Vector2(x, centre.y - half.y))
	for y: float in [centre.y - half.y * 0.33, centre.y + half.y * 0.33]:
		bulbs.append(Vector2(-half.x, y))
		bulbs.append(Vector2(half.x, y))
	for bulb: Vector2 in bulbs:
		pen.box(Vector3(bulb.x - 0.022, bulb.y - 0.022, 0.0), Vector3(bulb.x + 0.022, bulb.y + 0.022, 0.08), Color("f2ebdd"))
		b._glow_lamp(pen, bulb.x, bulb.y, 0.024, 0.081)
	if style.accent == ShopStyle.Accent.PRIZES:
		_machines(stock, p, open, top)


## Arcade cabinets inside the open front, and a little rocket ride on the paving outside.
func _machines(pen: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan, open: float, top: float) -> void:
	var street: StreetSet = _street()
	var style: ShopStyle = p.style
	var tones: Array[Color] = [style.awning_a, Color("62a0cc"), style.door, Color("e8bc45")]
	var count: int = maxi(3, int(open * 2.0 / 0.42))
	for index: int in count:
		var x: float = -open + 0.24 + (open * 2.0 - 0.48) * float(index) / float(count - 1)
		var tone: Color = tones[(index + p.seed_value) % tones.size()]
		var tall: float = 0.86 + 0.08 * float(index % 2)
		pen.box(Vector3(x - 0.15, 0.08, 0.01), Vector3(x + 0.15, tall, 0.06), tone.darkened(0.25))
		pen.box(Vector3(x - 0.12, tall - 0.34, 0.01), Vector3(x + 0.12, tall - 0.1, 0.07), Color("afc6d6").lerp(tone, 0.25))
		b._glow_lamp(pen, x, tall - 0.22, 0.11, 0.071)
		pen.box(Vector3(x - 0.15, tall - 0.06, 0.01), Vector3(x + 0.15, tall, 0.075), tone.lightened(0.15))
		pen.box(Vector3(x - 0.13, 0.44, 0.06), Vector3(x + 0.13, 0.5, 0.13), tone)
	# The rocket ride.
	var at: Vector3 = Vector3(p.width * 0.5 - 0.62, b.paving_top, 0.42)
	var body: Color = style.door
	pen.box(at + Vector3(-0.17, 0.0, -0.17), at + Vector3(0.17, 0.08, 0.17), street.metal)
	pen.box(at + Vector3(-0.1, 0.08, -0.1), at + Vector3(0.1, 0.42, 0.1), body)
	pen.box(at + Vector3(-0.07, 0.42, -0.07), at + Vector3(0.07, 0.5, 0.07), body.lightened(0.12))
	pen.box(at + Vector3(-0.035, 0.5, -0.035), at + Vector3(0.035, 0.58, 0.035), street.signal_red)
	pen.disc(at.x, at.y + 0.3, 0.05, at.z + 0.1, at.z + 0.115, Color("afc6d6"))
	for fin: Vector2 in [Vector2(-0.16, 0.0), Vector2(0.16, 0.0), Vector2(0.0, -0.16), Vector2(0.0, 0.16)]:
		pen.box(at + Vector3(fin.x - 0.03 if fin.x != 0.0 else -0.012, 0.08, fin.y - 0.03 if fin.y != 0.0 else -0.012),
			at + Vector3(fin.x + 0.03 if fin.x != 0.0 else 0.012, 0.22, fin.y + 0.03 if fin.y != 0.0 else 0.012), street.signal_red)


# --- the back yards (#600) -----------------------------------------------------

## A walled back yard behind a shop that shares the lot's row, from its back wall to the
## lot's back line: rendered walls in the shop's own colour with a coping, a plank gate
## in the back wall, a bin and a stack of crates. Authored in building-local space.
func yard(pen: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan) -> void:
	if p.yard_back >= 0.0:
		return
	var street: StreetSet = _street()
	var hw: float = p.width * 0.5
	var z0: float = p.yard_back
	var z1: float = -p.depth
	var render: Color = p.wall.darkened(0.06)
	var coping: Color = street.trim.darkened(0.04)
	var t: float = YARD_WALL_T
	var h: float = YARD_WALL_H
	# The gate sits off-centre, the side picked from the shop's hash.
	var gate_side: float = -1.0 if b._r(p.seed_value, 71) < 0.5 else 1.0
	var gate_x: float = gate_side * (hw * 0.45)
	# Side walls run back from the shop's corners; the back wall closes them, gate between.
	for x: float in [-hw, hw - t]:
		wall_box(pen, street, Vector3(x, 0.0, z0), Vector3(x + t, h, z1), render, coping)
	wall_run(pen, street, -hw, hw, z0, t, h, gate_x, YARD_GATE, render)
	# A wheelie bin in the far corner away from the gate, crates against the shop's back.
	var bin_tone: Color = street.bin_colors[b._pick(street.bin_colors.size(), p.seed_value, 72)] \
		if not street.bin_colors.is_empty() else street.metal
	var bx: float = -gate_side * (hw - t - 0.2)
	var bz: float = z0 + t + 0.2
	pen.box(Vector3(bx - 0.14, 0.0, bz - 0.15), Vector3(bx + 0.14, 0.4, bz + 0.15), bin_tone)
	pen.box(Vector3(bx - 0.16, 0.4, bz - 0.17), Vector3(bx + 0.16, 0.45, bz + 0.17), bin_tone.darkened(0.18))
	var cx: float = gate_side * (hw - t - 0.26)
	var cz: float = z1 - 0.24
	var stack: int = 1 + int(b._r(p.seed_value, 73) * 3.0)
	for level: int in stack:
		var lean: float = 0.03 * float(level % 2) * gate_side
		var crate: Color = street.wood.lightened(0.08) if level % 2 == 0 else street.wood.darkened(0.04)
		var y: float = 0.2 * float(level)
		pen.box(Vector3(cx - 0.17 + lean, y, cz - 0.15), Vector3(cx + 0.17 + lean, y + 0.19, cz + 0.15), crate)
		pen.box(Vector3(cx - 0.17 + lean, y + 0.07, cz + 0.15), Vector3(cx + 0.17 + lean, y + 0.11, cz + 0.16), crate.darkened(0.2))


## A rendered wall from x0 to x1 (its back face at z, `t` thick toward +z, `h` high) with
## a plank gate `gate` wide centred at gate_x (no gate when `gate` is 0). In the pen's space.
static func wall_run(pen: NeighbourhoodBuildings.Pen, street: StreetSet, x0: float, x1: float, z: float, t: float, h: float,
		gate_x: float, gate: float, render: Color) -> void:
	var coping: Color = street.trim.darkened(0.04)
	if gate <= 0.0:
		wall_box(pen, street, Vector3(x0, 0.0, z), Vector3(x1, h, z + t), render, coping)
		return
	var lo: float = gate_x - gate * 0.5
	var hi: float = gate_x + gate * 0.5
	wall_box(pen, street, Vector3(x0, 0.0, z), Vector3(lo, h, z + t), render, coping)
	wall_box(pen, street, Vector3(hi, 0.0, z), Vector3(x1, h, z + t), render, coping)
	# The gate: vertical planks a touch shorter than the wall, a ledge across them, and
	# a centre post when it is a double gate.
	var planks: int = maxi(3, int(round(gate / 0.1)))
	for index: int in planks:
		var p0: float = lo + 0.02 + (gate - 0.04) * float(index) / float(planks)
		var p1: float = lo + 0.02 + (gate - 0.04) * float(index + 1) / float(planks) - 0.008
		var tone: Color = street.wood if index % 2 == 0 else street.wood.darkened(0.06)
		pen.box(Vector3(p0, 0.03, z + t * 0.3), Vector3(p1, h - 0.06, z + t * 0.6), tone)
	pen.box(Vector3(lo + 0.02, h * 0.45, z + t * 0.6), Vector3(hi - 0.02, h * 0.45 + 0.05, z + t * 0.8), street.wood.darkened(0.2))
	if gate > 0.8:
		pen.box(Vector3(gate_x - 0.012, 0.03, z + t * 0.6), Vector3(gate_x + 0.012, h - 0.06, z + t * 0.82), street.wood.darkened(0.25))


## One stretch of rendered wall: the render, a coping along the top and a stone plinth.
static func wall_box(pen: NeighbourhoodBuildings.Pen, street: StreetSet, lo: Vector3, hi: Vector3, render: Color, coping: Color) -> void:
	pen.box(lo, Vector3(hi.x, hi.y - 0.04, hi.z), render)
	pen.box(Vector3(lo.x - 0.015, hi.y - 0.04, lo.z - 0.015), Vector3(hi.x + 0.015, hi.y, hi.z + 0.015), coping)
	pen.box(Vector3(lo.x - 0.01, 0.0, lo.z - 0.01), Vector3(hi.x + 0.01, 0.07, hi.z + 0.01), street.stone)


## The paved ground the terrace shares with the lot (#600), street-local (u, z): from the
## outer end of each row's walled yards (or the lot's edge) across, and from the lot's
## back line to the street. Empty without a terrace.
static func paved_block(builder: NeighbourhoodBuildings) -> Rect2:
	if builder.street == null or not builder.street.has_terrace():
		return Rect2()
	var lo: float = builder.local_reserve.position.x - SNUG
	var hi: float = builder.local_reserve.end.x + SNUG
	for p: NeighbourhoodBuildings.Plan in builder.plans:
		if p.yard_back < 0.0:
			lo = minf(lo, p.xf.origin.x - p.width * 0.5)
			hi = maxf(hi, p.xf.origin.x + p.width * 0.5)
	return Rect2(lo, builder.local_reserve.position.z, hi - lo, builder.shift - builder.local_reserve.position.z)


# --- the stock a SHOP form sets out (#596) ------------------------------------

## A surf-hire shop's boards on a rack beside the window and wetsuits hung inside it.
func surf(pen: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan, x0: float, x1: float) -> void:
	var street: StreetSet = _street()
	var style: ShopStyle = p.style
	var tones: Array[Color] = [style.awning_a, Color("e8bc45"), Color("e07f68"), style.awning_b]
	# Wetsuits on hangers in the window.
	var suits: int = maxi(2, int((x1 - x0) / 0.34))
	for index: int in suits:
		var x: float = x0 + (x1 - x0) * (float(index) + 0.5) / float(suits)
		var suit: Color = Color("3a4b6c") if index % 2 == 0 else Color("45342b").lerp(Color("3a4b6c"), 0.4)
		pen.box(Vector3(x - 0.07, 0.98, 0.04), Vector3(x + 0.07, 1.0, 0.05), street.metal)
		pen.box(Vector3(x - 0.07, 0.66, 0.035), Vector3(x + 0.07, 0.97, 0.05), suit)
		pen.box(Vector3(x - 0.12, 0.8, 0.035), Vector3(x - 0.07, 0.96, 0.048), suit.lightened(0.05))
		pen.box(Vector3(x + 0.07, 0.8, 0.035), Vector3(x + 0.12, 0.96, 0.048), suit.lightened(0.05))
		pen.box(Vector3(x - 0.065, 0.43, 0.035), Vector3(x - 0.01, 0.66, 0.048), suit)
		pen.box(Vector3(x + 0.01, 0.43, 0.035), Vector3(x + 0.065, 0.66, 0.048), suit)
		pen.box(Vector3(x - 0.07, 0.84, 0.05), Vector3(x + 0.07, 0.87, 0.052), tones[index % tones.size()])
	# Three boards stood on end in front of the window, leaning back on it.
	var saved: Transform3D = pen.xf
	for index: int in 3:
		var x: float = x0 + 0.16 + 0.17 * float(index)
		if x > x1 - 0.1:
			continue
		pen.xf = saved * Transform3D(Basis(Vector3.RIGHT, -0.16) * Basis(Vector3.FORWARD, 0.06 * float(index - 1)),
			Vector3(x, b.paving_top, 0.3))
		var tone: Color = tones[(index + p.seed_value) % tones.size()]
		pen.box(Vector3(-0.065, 0.0, -0.018), Vector3(0.065, 1.0, 0.018), tone)
		pen.box(Vector3(-0.045, 1.0, -0.016), Vector3(0.045, 1.09, 0.016), tone)
		pen.box(Vector3(-0.025, 1.09, -0.014), Vector3(0.025, 1.13, 0.014), tone)
		pen.box(Vector3(-0.014, 0.05, 0.016), Vector3(0.014, 1.05, 0.024), street.trim)
		pen.box(Vector3(-0.065, 0.0, -0.03), Vector3(0.065, 0.04, 0.03), tone.darkened(0.25))
	pen.xf = saved


## A bucket-and-spade shop's stall: a stand of bright buckets with spades in them, beach
## balls in a net and a rubber ring hung by the door; buckets and balls in the window.
func beach_goods(pen: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan, x0: float, x1: float) -> void:
	var street: StreetSet = _street()
	var play: Array[Color] = street.play_colors
	var y0: float = b.paving_top
	# The window: a shelf with buckets and a beach ball.
	pen.box(Vector3(x0 - 0.02, 0.34, 0.0), Vector3(x1 + 0.02, 0.38, 0.19), street.wood)
	var count: int = maxi(3, int((x1 - x0) / 0.2))
	for index: int in count:
		var x: float = x0 + (x1 - x0) * (float(index) + 0.5) / float(count)
		var tone: Color = play[(index + p.seed_value) % play.size()]
		if index % 3 == 1:
			pen.lump(Vector3(x, 0.47, 0.1), 0.08, 0.08, 0.08, 0.3, tone, tone.darkened(0.2))
		else:
			_bucket(pen, Vector3(x, 0.38, 0.1), 0.06, tone, play[(index + 2) % play.size()])
	# The stand on the paving: two tiers of buckets.
	var mid: float = (x0 + x1) * 0.5
	var half: float = minf(0.42, (x1 - x0) * 0.5)
	for tier: int in 2:
		var y: float = y0 + 0.16 + 0.2 * float(tier)
		var z: float = 0.36 - 0.12 * float(tier)
		pen.box(Vector3(mid - half, y - 0.03, z - 0.08), Vector3(mid + half, y, z + 0.08), street.wood.lightened(0.08))
		for index: int in 4:
			var x: float = mid - half + 0.1 + (half * 2.0 - 0.2) * float(index) / 3.0
			var tone: Color = play[(index + tier * 2 + p.seed_value) % play.size()]
			_bucket(pen, Vector3(x, y, z), 0.055, tone, play[(index + 3) % play.size()])
	for leg: float in [mid - half + 0.03, mid + half - 0.03]:
		pen.box(Vector3(leg - 0.02, y0, 0.2), Vector3(leg + 0.02, y0 + 0.36, 0.44), street.wood.darkened(0.2))
	# Beach balls in a net bag by the door, and a rubber ring hung beside it.
	var side: float = signf(p.door_x)
	var bag_x: float = p.door_x + side * 0.38
	if absf(bag_x) < p.width * 0.5 - 0.12:
		for index: int in 3:
			var tone: Color = play[(index * 2 + p.seed_value) % play.size()]
			pen.lump(Vector3(bag_x + 0.07 * float(index - 1), y0 + 0.09 + 0.1 * float(index % 2), 0.16), 0.075, 0.075, 0.075, float(index),
				tone, tone.darkened(0.2))
		var ring: Color = play[(p.seed_value + 1) % play.size()]
		pen.disc(bag_x, 0.95, 0.13, 0.02, 0.06, ring)
		pen.disc(bag_x, 0.95, 0.06, 0.02, 0.065, p.wall)


func _bucket(pen: NeighbourhoodBuildings.Pen, at: Vector3, radius: float, tone: Color, spade: Color) -> void:
	var sides: int = 6
	for index: int in sides:
		var a0: float = TAU * float(index) / float(sides)
		var a1: float = TAU * float(index + 1) / float(sides)
		var b0: Vector3 = at + Vector3(cos(a0) * radius * 0.78, 0.0, sin(a0) * radius * 0.78)
		var b1: Vector3 = at + Vector3(cos(a1) * radius * 0.78, 0.0, sin(a1) * radius * 0.78)
		var t0: Vector3 = at + Vector3(cos(a0) * radius, radius * 1.6, sin(a0) * radius)
		var t1: Vector3 = at + Vector3(cos(a1) * radius, radius * 1.6, sin(a1) * radius)
		pen.quad(b0, b1, t1, t0, (b0 + b1 + t0 + t1) * 0.25 - at - Vector3(0.0, radius * 0.8, 0.0), tone)
	pen.box(at + Vector3(-radius * 0.8, radius * 1.45, -radius * 0.8), at + Vector3(radius * 0.8, radius * 1.5, radius * 0.8), tone.darkened(0.3))
	pen.box(at + Vector3(radius * 0.1, radius * 1.2, -0.008), at + Vector3(radius * 0.25, radius * 3.2, 0.008), spade)
	pen.box(at + Vector3(radius * 0.0, radius * 3.0, -0.02), at + Vector3(radius * 0.35, radius * 3.5, 0.02), spade)


# --- closed and for sale (#596) -----------------------------------------------

## What a closed, for-sale neighbour shows over its front: whitewashed windows on a
## shop, a roller shutter down on a kiosk or arcade, and the board's backing (its
## words are a Label3D the view adds at `sale_board`).
func for_sale(pen: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan) -> void:
	var street: StreetSet = _street()
	var hw: float = p.width * 0.5
	match p.form:
		ShopStyle.Form.KIOSK:
			var hatch: float = minf(0.62, hw - 0.22)
			_shutter(pen, -hatch, hatch, 0.52, 1.08, 0.03)
		ShopStyle.Form.ARCADE:
			_shutter(pen, -(hw - 0.42), hw - 0.42, 0.08, 1.12, 0.09)
		ShopStyle.Form.HUT:
			pass
		_:
			var span: Vector2 = window_span(p)
			var wash: Color = street.trim.lerp(Color.WHITE, 0.35)
			pen.box(Vector3(span.x, 0.35, 0.0), Vector3(span.y, 1.08, 0.045), wash)
			var streaks: int = int(0.7 / STREAK)
			for index: int in streaks:
				var y: float = 0.4 + STREAK * float(index)
				var inset: float = 0.05 + 0.04 * float(index % 3)
				pen.box(Vector3(span.x + inset, y, 0.0), Vector3(span.y - inset * 0.7, y + 0.03, 0.048), street.trim.darkened(0.06))
	var board: Dictionary = sale_board(p)
	var centre: Vector3 = board["centre"]
	var half: Vector2 = (board["size"] as Vector2) * 0.5 + Vector2(0.04, 0.04)
	var face: float = centre.z - 0.004
	if p.form != ShopStyle.Form.HUT:
		# The awning rolled up tight under the sign, and the agent's post.
		var style: ShopStyle = p.style
		var hw2: float = p.width * 0.5 + 0.04
		pen.box(Vector3(-hw2, 1.24, 0.0), Vector3(hw2, 1.33, 0.09), style.awning_a.darkened(0.08))
		pen.box(Vector3(-hw2, 1.255, 0.06), Vector3(hw2, 1.3, 0.1), style.awning_b.darkened(0.05))
		var x: float = centre.x
		pen.box(Vector3(x - 0.035, b.paving_top, SALE_POST_Z - 0.035), Vector3(x + 0.035, centre.y + half.y + 0.06, SALE_POST_Z + 0.035), street.wood)
		pen.box(Vector3(x - 0.07, b.paving_top, SALE_POST_Z - 0.07), Vector3(x + 0.07, b.paving_top + 0.04, SALE_POST_Z + 0.07), street.wood.darkened(0.2))
	pen.box(Vector3(centre.x - half.x, centre.y - half.y, face - 0.03), Vector3(centre.x + half.x, centre.y + half.y, face - 0.004), street.signal_red)
	pen.box(Vector3(centre.x - half.x + 0.03, centre.y - half.y + 0.03, face - 0.03), Vector3(centre.x + half.x - 0.03, centre.y + half.y - 0.03, face),
		street.trim.lerp(Color.WHITE, 0.4))


func _shutter(pen: NeighbourhoodBuildings.Pen, x0: float, x1: float, y0: float, y1: float, z: float) -> void:
	var street: StreetSet = _street()
	var steel: Color = street.metal.lightened(0.08)
	pen.box(Vector3(x0 - 0.03, y0, 0.0), Vector3(x1 + 0.03, y1 + 0.06, z), steel)
	pen.box(Vector3(x0 - 0.05, y1, 0.0), Vector3(x1 + 0.05, y1 + 0.1, z + 0.03), steel.darkened(0.12))
	var slats: int = int((y1 - y0) / SLAT)
	for index: int in slats:
		var y: float = y0 + SLAT * float(index)
		pen.box(Vector3(x0 - 0.03, y, 0.0), Vector3(x1 + 0.03, y + 0.012, z + 0.006), steel.darkened(0.16))
	pen.box(Vector3((x0 + x1) * 0.5 - 0.08, y0, 0.0), Vector3((x0 + x1) * 0.5 + 0.08, y0 + 0.04, z + 0.012), steel.darkened(0.3))
