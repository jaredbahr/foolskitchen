class_name NeighbourhoodRival
extends RefCounted
## Chef Copley's side of the street (#701), view only. Two things the street can show:
##
## * his shop: a neighbour in the RIVAL state wears his gaudy sign (the made `copley_sign`:
##   gold frame, a smug little Copley face and a blank name plate the view paints the
##   knock-off name on), a string of purple, gold and cream bunting under the eave and a
##   cluster of balloons by the door (`look`);
## * his food truck, parked by a lot that has no shopfronts (`truck`), with the name on its
##   blank panel and a toque on the roof.
##
## The models are built by tools/build_copley_art.py (assets/made/copley/); their sizes and
## the name areas below match copley.metrics.json, which a test compares. Colours are the
## Mini Characters kit's gold, purple, cream and red, the same swatches the models use. No
## random draws: the bunting and balloons are plain functions of the building's plan.

const MADE_ROOT: String = "res://assets/made/copley/"
const TRUCK_MODEL: String = MADE_ROOT + "copley_truck.glb"
const SIGN_MODEL: String = MADE_ROOT + "copley_sign.glb"
const CLOSING_SIGN_MODEL: String = MADE_ROOT + "copley_closing_sign.glb"

## The truck's footprint on the ground (metres, long side along x) and its name panel on the
## -z (serving hatch) side: the text's centre in the truck's space and its size.
const TRUCK_SIZE: Vector2 = Vector2(1.3, 0.62)
const TRUCK_TEXT_CENTRE: Vector3 = Vector3(0.18, 0.75, -0.3125)
const TRUCK_TEXT_SIZE: Vector2 = Vector2(0.70, 0.13)
## The sign's name plate (the sign's space: origin at the middle of the frame's bottom edge on
## its back plane, the face looking to -z).
const SIGN_SIZE: Vector2 = Vector2(0.96, 0.50)
const SIGN_TEXT_CENTRE: Vector3 = Vector3(-0.155, 0.25, -0.0415)
const SIGN_TEXT_SIZE: Vector2 = Vector2(0.46, 0.22)

## Copley's swatches (the kit colormap's gold, purple, cream and red).
const GOLD: Color = Color(1.0, 0.753, 0.267)
const GOLD_LIGHT: Color = Color(1.0, 0.827, 0.388)
const PURPLE: Color = Color(0.494, 0.337, 0.808)
const PURPLE_DARK: Color = Color(0.361, 0.224, 0.722)
const CREAM: Color = Color(0.992, 0.894, 0.78)
const RED: Color = Color(0.812, 0.325, 0.31)
const INK: Color = Color(0.231, 0.243, 0.29)
const NAME_INK: Color = Color(0.29, 0.17, 0.5)
const BUNTING: Array[Color] = [PURPLE, GOLD, CREAM, RED]
const BALLOONS: Array[Color] = [GOLD, PURPLE, RED]

## Where a truck stands when the street offers a kerb of its own: a ground height just under
## the open land's floor so the wheels sit on it.
const TRUCK_GROUND: float = -0.04


## The truck, built as `Name` text on its panel: Node3D "CopleyTruck" with the model and a Label3D.
static func truck(text: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "CopleyTruck"
	root.add_child(_model(TRUCK_MODEL, "Model", 1.0))
	var words: Label3D = NeighbourhoodDressing.painted_label("Name", text,
		{"centre": TRUCK_TEXT_CENTRE, "size": TRUCK_TEXT_SIZE}, NAME_INK)
	# The panel is on the truck's -z side, so the lettering turns to face it.
	words.rotation = Vector3(0.0, PI, 0.0)
	words.position = TRUCK_TEXT_CENTRE + Vector3(0.0, 0.0, -0.0015)
	root.add_child(words)
	return root


## Changes the words on a truck built by `truck`.
static func rename_truck(root: Node3D, text: String) -> void:
	var words: Label3D = root.get_node_or_null(^"Name") as Label3D
	if words != null:
		NeighbourhoodDressing.fit_label(words, text, TRUCK_TEXT_SIZE)


## A made model at the shared furniture scale, `scale` bigger.
static func _model(path: String, label: String, factor: float) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = label
	holder.scale = Vector3.ONE * ArtScale.FURNITURE_SCALE * factor
	var scene: PackedScene = load(path) as PackedScene
	if scene != null:
		holder.add_child(scene.instantiate())
	return holder


## The trophy model, for tools and tests: Copley's sign with the CLOSED board hung across it.
static func closing_sign() -> Node3D:
	return _model(CLOSING_SIGN_MODEL, "ClosingSign", 1.0)


# --- the shop ----------------------------------------------------------------

## Where the sign hangs on a neighbour, in the building's own space (facade centre on the
## ground, +z toward the street): the middle of the sign's bottom edge on its back plane, how
## much bigger than the made model it is drawn, and the height its two gold posts stand from
## ("post_from": 0 stands on the ground, -1 for none). Bigger buildings get a bigger sign, and
## it is always too big. A house, too small a front to carry one, gets it on posts in its front yard.
static func sign_mount(p: NeighbourhoodBuildings.Plan) -> Dictionary:
	var fit: float = (p.width - 0.4) / SIGN_SIZE.x
	if not p.is_shop:
		var x: float = -signf(p.door_x) * 0.95 if absf(p.door_x) > 0.01 else 0.95
		return {"position": Vector3(x, 0.42, 0.95), "scale": clampf(fit, 0.8, 1.3), "post_from": 0.0}
	match p.form:
		ShopStyle.Form.KIOSK:
			return {"position": Vector3(0.0, p.wall_h + p.roof_h + 0.1, 0.12), "scale": 0.95, "post_from": p.wall_h + p.roof_h - 0.02}
		ShopStyle.Form.HUT:
			return {"position": Vector3(0.0, p.wall_h + 0.04, 0.05), "scale": 0.7, "post_from": -1.0}
		ShopStyle.Form.ARCADE:
			return {"position": Vector3(0.0, p.wall_h + 0.02, 0.1), "scale": clampf(fit, 0.8, 1.2), "post_from": -1.0}
	return {"position": Vector3(0.0, 1.32, 0.12), "scale": clampf(fit, 0.7, 1.5), "post_from": -1.0}


## The rival look for a neighbour: Node3D "Rival" (bunting and balloons, the sign, its name),
## in the building's own space. `text` is the knock-off name.
static func look(p: NeighbourhoodBuildings.Plan, text: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Rival"
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var mount: Dictionary = sign_mount(p)
	var at: Vector3 = mount["position"]
	var factor: float = mount["scale"]
	_bunting(pen, p)
	_balloons(pen, p, at, factor)
	if float(mount["post_from"]) >= 0.0:
		for side: float in [-1.0, 1.0]:
			var x: float = at.x + side * SIGN_SIZE.x * factor * 0.34
			pen.box(Vector3(x - 0.03, float(mount["post_from"]), at.z - 0.06), Vector3(x + 0.03, at.y + 0.02, at.z), GOLD.darkened(0.2))
	var decor: MeshInstance3D = MeshInstance3D.new()
	decor.name = "Decor"
	decor.mesh = pen.soup.to_mesh()
	decor.material_override = material()
	decor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(decor)
	var sign: Node3D = sign_node(text, factor)
	# The sign's face looks to -z; the facade's looks to +z.
	sign.transform = Transform3D(Basis(Vector3.UP, PI), at)
	root.add_child(sign)
	return root


## Changes the words on a look built by `look`.
static func rename(root: Node3D, p: NeighbourhoodBuildings.Plan, text: String) -> void:
	var words: Label3D = root.get_node_or_null(^"Sign/Name") as Label3D
	if words != null:
		NeighbourhoodDressing.fit_label(words, text, SIGN_TEXT_SIZE * float(sign_mount(p)["scale"]))


## The sign on its own, `factor` times the made model's size: Node3D "Sign" with the model and the
## name on its plate, face looking to -z.
static func sign_node(text: String, factor: float = 1.0) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Sign"
	root.add_child(_model(SIGN_MODEL, "Model", factor))
	var words: Label3D = NeighbourhoodDressing.painted_label("Name", text,
		{"centre": SIGN_TEXT_CENTRE * factor, "size": SIGN_TEXT_SIZE * factor}, NAME_INK)
	words.rotation = Vector3(0.0, PI, 0.0)
	words.position = SIGN_TEXT_CENTRE * factor + Vector3(0.0, 0.0, -0.0015)
	root.add_child(words)
	return root


## The street's flat vertex-colour material (two-sided, so pennants and balloon strings show from both sides).
static func material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Pennants on a sagging string just under the eave, purple, gold, cream and red in turn.
static func _bunting(pen: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan) -> void:
	var half: float = p.width * 0.5 - 0.06
	var count: int = maxi(int(floor(half * 2.0 / 0.2)), 3)
	var z: float = 0.07
	var top: float = minf(p.wall_h - 0.06, 1.62) if p.is_shop and p.form != ShopStyle.Form.HUT else p.wall_h - 0.06
	if p.is_shop and p.form == ShopStyle.Form.SHOP:
		z = 0.42
		top = 1.22
	var sag: float = 0.07
	var step: float = half * 2.0 / float(count)
	for index: int in count:
		var x0: float = -half + step * float(index)
		var x1: float = x0 + step
		var y0: float = top - sag * sin(PI * float(index) / float(count))
		var y1: float = top - sag * sin(PI * float(index + 1) / float(count))
		var colour: Color = BUNTING[index % BUNTING.size()]
		var tip: Vector3 = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5 - 0.17, z)
		pen.tri(Vector3(x0 + 0.012, y0, z), Vector3(x1 - 0.012, y1, z), tip, Vector3.BACK, colour)
		# The string: a thin tilted strip.
		pen.quad(Vector3(x0, y0 + 0.008, z), Vector3(x1, y1 + 0.008, z), Vector3(x1, y1 - 0.008, z),
			Vector3(x0, y0 - 0.008, z), Vector3.BACK, INK)


## Three balloons on strings tied to a little gold weight: beside the door on a shop, beside the
## sign's post on a house.
static func _balloons(pen: NeighbourhoodBuildings.Pen, p: NeighbourhoodBuildings.Plan, sign_at: Vector3, factor: float) -> void:
	var hw: float = p.width * 0.5
	var side: float = -signf(p.door_x) if absf(p.door_x) > 0.01 else 1.0
	var x: float = side * (hw - 0.3)
	var z: float = 0.5 if p.is_shop and p.form == ShopStyle.Form.SHOP else 0.34
	var ground: float = 0.0
	if not p.is_shop:
		x = sign_at.x + signf(sign_at.x) * (SIGN_SIZE.x * factor * 0.5 + 0.32)
		z = sign_at.z + 0.15
	pen.box(Vector3(x - 0.07, ground, z - 0.07), Vector3(x + 0.07, ground + 0.06, z + 0.07), GOLD.darkened(0.2))
	var heights: Array[float] = [1.12, 1.38, 1.22]
	var offsets: Array[float] = [-0.13, 0.02, 0.14]
	for index: int in 3:
		var bx: float = x + offsets[index]
		var by: float = heights[index]
		pen.quad(Vector3(x - 0.005, ground + 0.06, z), Vector3(x + 0.005, ground + 0.06, z), Vector3(bx + 0.005, by - 0.12, z),
			Vector3(bx - 0.005, by - 0.12, z), Vector3.BACK, INK)
		var colour: Color = BALLOONS[index % BALLOONS.size()]
		pen.lump(Vector3(bx, by, z + 0.03 * float(index)), 0.11, 0.14, 0.11, 0.3 * float(index), colour.lightened(0.12), colour.darkened(0.18))
