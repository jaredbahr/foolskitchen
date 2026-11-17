extends Node3D
## Contact sheet for the #589 models (art only; nothing is bought or wired).
## A standalone stage with the game's own lighting rig and orthographic camera
## angle: every new model stands next to its nearest kit piece, the walk-up
## hatch is shown open and closed in a shell wall run (the shop's default wall
## paint), and a kit table is dressed for the evening beside a plain one.
## Capture with
##   bash tools/screenshot.sh --scene=res://tools/walkup_models_review.tscn --speed=0 --frames=20,40,60,80,100,120,140,160,180
## Frame 20: the hatch wall from the street, shutters open, people for scale.
## Frame 40: the same wall, shutters closed (beside a kit window cell).
## Frame 60: the wall from the room side (the inner ledges).
## Frame 80: the soft-serve machine and shaved-ice cart beside the kit pieces.
## Frame 100: the dishes beside the Food Kit pieces, close up.
## Frame 120: the evening dress kit on kit tables beside plain ones.
## Frame 140: the same at night (the rig dimmed, a warm light at each candle), shutters down.
## Frame 160: the whole stage at the game's closest play zoom, by day.
## Frame 180: the same at night.

const WALKUP: String = "res://assets/made/walkup/"
const KIT: String = "res://assets/kenney/furniture/"
const FOOD: String = "res://assets/kenney/food/"
const LIGHTING: String = "res://src/world/lighting_rig.tscn"
const CELL: float = 0.5
## The shop's default wall paint and wall top (ShopView.wall_color / wall_top_color).
const WALL_COLOR: Color = Color("e6d5b8")
const WALL_TOP_COLOR: Color = Color("b9a789")
## The game's camera: orthographic, true isometric pitch (CameraRig).
const PITCH_DEGREES: float = 54.7356
const ORBIT: float = 40.0

var _review_frame: int = 0
var _showroom: Node3D
var _camera: Camera3D
var _rig: Node3D
var _wall_material: StandardMaterial3D
var _top_material: StandardMaterial3D
var _night_lights: Array[OmniLight3D] = []
var _evidence: Dictionary = {}


func _ready() -> void:
	_rig = (load(LIGHTING) as PackedScene).instantiate() as Node3D
	add_child(_rig)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.far = 200.0
	add_child(_camera)
	_camera.current = true
	_wall_material = _flat(WALL_COLOR)
	_top_material = _flat(WALL_TOP_COLOR)
	_showroom = Node3D.new()
	_showroom.name = "WalkupShowroom"
	add_child(_showroom)
	_ground(Vector3(1.5, 0.0, 2.0), Vector2(14.0, 12.0), Color("6b5a48"))
	_build_hatch_wall(Vector3(0.0, 0.0, 0.0))
	_build_treats(Vector3(0.0, 0.0, 2.2))
	_build_dishes(Vector3(4.2, 0.0, 2.2))
	_build_evening(Vector3(0.0, 0.0, 4.4))
	_frame(Vector3(0.0, 0.6, 0.2), 3.0, 45.0)
	_set_open(true)
	print("WALKUP_REVIEW ", JSON.stringify(_evidence))


func _process(_delta: float) -> void:
	_review_frame += 1
	match _review_frame:
		30:
			_set_open(false)
		50:
			_set_open(true)
			_frame(Vector3(0.0, 0.6, -0.2), 3.0, 225.0)
		70:
			_frame(Vector3(0.15, 0.4, 2.2), 2.6, 45.0)
		90:
			_frame(Vector3(4.15, 0.55, 2.2), 1.05, 45.0)
		110:
			_frame(Vector3(0.1, 0.3, 4.95), 3.5, 45.0)
		130:
			_night(true)
			_set_open(false)
		150:
			_night(false)
			_set_open(true)
			_frame(Vector3(1.2, 0.4, 2.2), 8.0, 45.0)
		170:
			_night(true)
			_set_open(false)


# ---------------------------------------------------------------- the hatch wall

## A shell wall run along X (outside towards +Z, the camera at yaw 45): plain
## cell, a kit window cell, then each hatch open and closed, a plain cell.
func _build_hatch_wall(at: Vector3) -> void:
	var cells: Array[String] = ["wall", "window", "wall", "wood", "wall", "painted", "wall", "seaside", "wall"]
	var start: float = -float(cells.size() - 1) * CELL * 0.5
	var hatches: Array[Dictionary] = []
	for index: int in cells.size():
		var centre: Vector3 = at + Vector3(start + index * CELL, 0.0, 0.0)
		match cells[index]:
			"wall":
				_wall_box(centre, 0.0, ArtScale.WALL_HEIGHT)
			"window":
				_shell_window(centre)
			_:
				hatches.append(_hatch(centre, cells[index], true))
		_cap(centre)
	# Floor inside, pavement outside, a customer at two hatches, staff inside.
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(cells.size() * CELL, 1.5)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _flat(Color("7d5533"))
	floor_mesh.position = at + Vector3(0.0, 0.003, -1.0)
	_showroom.add_child(floor_mesh)
	_ground(at + Vector3(0.0, 0.002, 0.9), Vector2(cells.size() * CELL + 1.0, 1.3), RoomDressing.pavement_color())
	_person(at + Vector3(start + 3 * CELL + 0.05, 0.0, 0.72), &"customer", 3, Vector3(-0.2, 0.0, -1.0))
	_person(at + Vector3(start + 7 * CELL + 0.05, 0.0, 0.72), &"customer", 5, Vector3(-0.2, 0.0, -1.0))
	_person(at + Vector3(start + 5 * CELL, 0.0, -0.6), &"server", 0, Vector3.BACK)
	_person(at + Vector3(start + 7 * CELL, 0.0, -0.6), &"cook", 0, Vector3.BACK)
	_evidence["hatches"] = hatches


## Every hatch's shutter: rolled up (open) or down (closed). View only.
func _set_open(open: bool) -> void:
	for node: Node in _showroom.find_children("Hatch_*", "Node3D", false, false):
		var art: Node3D = node.get_child(0) as Node3D
		(art.find_child("ShutterOpen", true, false) as Node3D).visible = open
		(art.find_child("ShutterClosed", true, false) as Node3D).visible = not open
		var dish: Node3D = _showroom.get_node_or_null("LedgeDish_" + String(node.name).trim_prefix("Hatch_")) as Node3D
		if dish != null:
			dish.visible = open


func _hatch(centre: Vector3, style: String, open: bool) -> Dictionary:
	var holder: Node3D = _model(WALKUP + "walkup_hatch_%s.glb" % style, ArtScale.FURNITURE_SCALE, centre, PI, false)
	holder.name = "Hatch_" + style
	var art: Node3D = holder.get_child(0) as Node3D
	(art.find_child("ShutterOpen", true, false) as Node3D).visible = open
	(art.find_child("ShutterClosed", true, false) as Node3D).visible = not open
	var body: MeshInstance3D = art.find_child("WallBody", true, false) as MeshInstance3D
	body.material_override = _wall_material
	var inner: Node3D = art.find_child("InnerLedgeTop", true, false) as Node3D
	var outer: Node3D = art.find_child("OuterLedgeTop", true, false) as Node3D
	# A dish on each open hatch's inner ledge marks the anchor the game will use.
	if open:
		var cup: Node3D = _model(FOOD + "ice-cream.glb", ArtScale.FOOD_SCALE, inner.global_position - _showroom.global_position, 0.0, true)
		cup.name = "LedgeDish_" + style
	return {"style": style, "open": open, "inner_ledge": _v(inner.global_position - centre - _showroom.global_position),
		"outer_ledge": _v(outer.global_position - centre - _showroom.global_position)}


func _shell_window(centre: Vector3) -> void:
	var sill: float = 0.35
	var head: float = 1.05
	_wall_box(centre, 0.0, sill)
	_wall_box(centre, head, ArtScale.WALL_HEIGHT)
	var pane: Node3D = _model(KIT + "wallWindow.glb", ArtScale.FURNITURE_SCALE, centre + Vector3(0.0, sill, 0.22), PI, true)
	var bounds: AABB = _bounds(pane)
	# The kit pane is one unit wide: show it at a cell's width (view only).
	var fit: float = CELL / maxf(bounds.size.x, 0.01)
	pane.scale = Vector3.ONE * fit
	pane.position.y = sill + ((head - sill) - bounds.size.y * fit) * 0.5


func _wall_box(centre: Vector3, bottom: float, top: float) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(CELL, top - bottom, CELL)
	mesh.mesh = box
	mesh.material_override = _wall_material
	mesh.position = centre + Vector3(0.0, (top + bottom) * 0.5, 0.0)
	_showroom.add_child(mesh)


func _cap(centre: Vector3) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(CELL, 0.02, CELL)
	mesh.mesh = box
	mesh.material_override = _top_material
	mesh.position = centre + Vector3(0.0, ArtScale.WALL_HEIGHT + 0.01, 0.0)
	_showroom.add_child(mesh)


# ---------------------------------------------------------------- treats

func _build_treats(at: Vector3) -> void:
	# Kit: the coffee machine on its cabinet, beside the soft-serve on one.
	_model(KIT + "kitchenCabinet.glb", ArtScale.FURNITURE_SCALE, at + Vector3(-1.5, 0.0, 0.0), PI, true)
	_model(KIT + "kitchenCoffeeMachine.glb", ArtScale.FURNITURE_SCALE, at + Vector3(-1.5, 0.495, -0.04), PI, true)
	_model(KIT + "kitchenCabinet.glb", ArtScale.FURNITURE_SCALE, at + Vector3(-1.0, 0.0, 0.0), PI, true)
	_model(WALKUP + "soft_serve_machine.glb", ArtScale.FURNITURE_SCALE, at + Vector3(-1.0, 0.495, -0.04), PI, false)
	_model(KIT + "kitchenBlender.glb", ArtScale.FURNITURE_SCALE, at + Vector3(-1.5, 0.495, 0.14), PI, true)
	# The cart (2x1) beside the kit bar counter.
	_model(KIT + "kitchenBar.glb", ArtScale.FURNITURE_SCALE, at + Vector3(-0.25, 0.0, 0.0), PI, true)
	_model(KIT + "kitchenBar.glb", ArtScale.FURNITURE_SCALE, at + Vector3(0.25, 0.0, 0.0), PI, true)
	_model(WALKUP + "shaved_ice_cart.glb", ArtScale.FURNITURE_SCALE, at + Vector3(1.1, 0.0, 0.0), PI, false)
	_person(at + Vector3(1.9, 0.0, 0.35), &"customer", 11, Vector3(-1.0, 0.0, -0.4))
	_person(at + Vector3(-0.5, 0.0, 0.55), &"cook", 0, Vector3(0.3, 0.0, 1.0))


# ---------------------------------------------------------------- dishes

## On a kit counter run: Food Kit pieces (left) beside the new dishes (right).
## The cones and shaved ice are the prop compositions in assets/props/; the
## strawberry cone is the kit's own `ice-cream`.
func _build_dishes(at: Vector3) -> void:
	for x: float in [-0.5, 0.0, 0.5]:
		_model(KIT + "kitchenBar.glb", ArtScale.FURNITURE_SCALE, at + Vector3(x, 0.0, 0.0), PI, true)
	var y: float = _bounds(_showroom.get_child(_showroom.get_child_count() - 1) as Node3D).end.y
	var dishes: Array[Array] = [
		[FOOD + "fries.glb", -0.62], [FOOD + "sundae.glb", -0.5], [FOOD + "cup.glb", -0.38],
		[FOOD + "ice-cream.glb", -0.2], ["res://assets/props/ice_cream_cone_chocolate.tscn", -0.08],
		["res://assets/props/ice_cream_cone_mint.tscn", 0.04],
		["res://assets/props/shaved_ice.tscn", 0.2], [WALKUP + "fries_cone.glb", 0.34],
	]
	for dish: Array in dishes:
		_model(String(dish[0]), ArtScale.FOOD_SCALE, at + Vector3(float(dish[1]), y, 0.0), PI, false)
	# The #558 sundae (the Food Kit cup and chocolate scoop), for reference.
	_model(FOOD + "ice-cream-cup.glb", ArtScale.FOOD_SCALE, at + Vector3(0.5, y, 0.0), PI, false)
	_model(FOOD + "ice-cream-scoop-chocolate.glb", ArtScale.FOOD_SCALE,
		at + Vector3(0.5, y + 0.14 * ArtScale.FOOD_SCALE, 0.0), PI, false)


# ---------------------------------------------------------------- evening dress kit

func _build_evening(at: Vector3) -> void:
	# Plain kit table with chairs, then the same table dressed for evening.
	_table(at + Vector3(-1.0, 0.0, 0.0), "table.glb", false)
	_table(at + Vector3(0.9, 0.0, 0.0), "table.glb", true)
	_table(at + Vector3(-1.0, 0.0, 1.3), "tableRound.glb", false)
	_table(at + Vector3(0.9, 0.0, 1.3), "tableRound.glb", true)
	# Nearest kit pieces for the small props, side by side on a side table.
	_model(KIT + "sideTable.glb", ArtScale.FURNITURE_SCALE, at + Vector3(2.4, 0.0, 0.6), PI, true)
	var top: float = 0.0
	for child: Node in _showroom.get_children():
		top = _bounds(child as Node3D).end.y
	_model(KIT + "lampRoundTable.glb", ArtScale.FURNITURE_SCALE, at + Vector3(2.28, top, 0.6), PI, true)
	_model(WALKUP + "candle_holder.glb", ArtScale.FURNITURE_SCALE, at + Vector3(2.37, top, 0.6), PI, false)
	_model(KIT + "plantSmall1.glb", ArtScale.FURNITURE_SCALE, at + Vector3(2.45, top, 0.6), PI, true)
	_model(WALKUP + "small_vase.glb", ArtScale.FURNITURE_SCALE, at + Vector3(2.53, top, 0.6), PI, false)


func _table(at: Vector3, kit: String, dressed: bool) -> void:
	var table: Node3D = _model(KIT + kit, ArtScale.FURNITURE_SCALE, at, PI, true)
	for side: float in [-1.0, 1.0]:
		var chair: Node3D = _model("res://assets/props/seats/derived/chairCushion_low_back.glb", ArtScale.FURNITURE_SCALE,
			at + Vector3(side * (0.75 if kit == "table.glb" else 0.7), 0.0, 0.0), -side * PI * 0.5, true)
		chair.name = "Chair"
	if not dressed:
		return
	var cloth: String = "tablecloth_rect.glb" if kit == "table.glb" else "tablecloth_round.glb"
	# The cloth's origin is the table's own base centre: same place, same turn.
	_model(WALKUP + cloth, ArtScale.FURNITURE_SCALE, at, PI, false, false)
	var top: float = _bounds(table).end.y + 0.004
	var candle: Node3D = _model(WALKUP + "candle_holder.glb", ArtScale.FURNITURE_SCALE, at + Vector3(-0.07, top, -0.03), 0.0, false)
	var glow: OmniLight3D = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.55)
	glow.light_energy = 0.6
	glow.omni_range = 0.9
	glow.position = Vector3(0.0, 0.14, 0.0)
	glow.visible = false
	candle.add_child(glow)
	_night_lights.append(glow)
	_model(WALKUP + "small_vase.glb", ArtScale.FURNITURE_SCALE, at + Vector3(0.09, top, 0.03), 0.0, false)


# ---------------------------------------------------------------- helpers

## A model at `at` (showroom space), turned `yaw`, scaled uniformly. Kit files
## (corner origins) are centred on their plan and stood on y = 0 like
## PropView does; made files keep their authored base-centre origin. With
## `stand` false a made model keeps its own origin height too (overlays).
func _model(path: String, scale_value: float, at: Vector3, yaw: float, kit: bool, _stand: bool = true) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.position = at
	# Kenney files face the other way: turned like the wrapper scenes, so one
	# yaw means the same facing for kit and made pieces.
	holder.rotation.y = yaw + (PI if kit else 0.0)
	_showroom.add_child(holder)
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Walk-up review cannot load " + path)
		return holder
	var art: Node3D = packed.instantiate() as Node3D
	art.scale = Vector3.ONE * scale_value
	holder.add_child(art)
	if kit:
		var bounds: AABB = _local_bounds(art)
		art.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	return holder


func _person(at: Vector3, role: StringName, id: int, facing: Vector3) -> void:
	var person: PersonView = (load("res://assets/people/person.tscn") as PackedScene).instantiate() as PersonView
	person.role = role
	person.guest_id = id
	person.position = at
	_showroom.add_child(person)
	person.face_direction(facing)
	person.set_pose(false, false, false, false)


## Combined mesh bounds of `node` in its parent's space (unrotated holder).
func _local_bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var to_parent: Transform3D = node.transform * (node.global_transform.affine_inverse() * mesh.global_transform)
		var box: AABB = to_parent * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Combined mesh bounds of `node` in showroom space.
func _bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = _showroom.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _v(value: Vector3) -> Array[float]:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]


## The game's camera angle at orthographic `size` (metres of screen height).
func _frame(focus: Vector3, size: float, yaw: float) -> void:
	var pitch: float = deg_to_rad(PITCH_DEGREES)
	var back: Vector3 = Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, deg_to_rad(yaw))
	_camera.size = size
	_camera.position = focus + back * ORBIT
	_camera.look_at(focus, Vector3.UP)


func _flat(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _ground(centre: Vector3, size: Vector2, color: Color) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = _flat(color)
	mesh.position = centre
	_showroom.add_child(mesh)


## Evening: the rig's lights turned down, a small warm light at each candle
## (view only; the game's night look and light cap belong to the wiring).
func _night(on: bool) -> void:
	for light: DirectionalLight3D in _rig.find_children("*", "DirectionalLight3D", true, false):
		light.light_energy = light.light_energy * (0.25 if on else 4.0)
	var environment: WorldEnvironment = _rig.find_child("Environment", true, false) as WorldEnvironment
	if environment != null:
		environment.environment.ambient_light_energy *= 0.45 if on else 1.0 / 0.45
	for light: OmniLight3D in _night_lights:
		light.visible = on
