extends "res://src/world/main.gd"
## Explicit, unsaved visual fixture for the guest-type looks: tourists and the
## office crowd (#661), farmers, walkers, surfers and foragers (#663 #657 #658 #659).
## Pick the shot with GUEST_LOOKS_MODE, then capture with
##   GUEST_LOOKS_MODE=shop bash tools/screenshot.sh --scene=res://tools/guest_looks_review.tscn --speed=0 --frames=60
## shop  - the real shop, ten guests of mixed types seated and walking in, sunny.
## close - stand-ins in a row, forced to a type look whether or not the type is
##         in the catalogue yet. GUEST_LOOKS_SET picks who: one type (tourist,
##         office, farmer, walker, surfer or forager: four ids), location (the
##         last four types), all (every type look) or survey (the stock models);
##         location and all show ids 0 and 3 of each type (both models, both palettes).
##         GUEST_LOOKS_POSE=idle|walk|sit|carry picks the pose (sit on stools),
##         GUEST_LOOKS_ZOOM the zoom and GUEST_LOOKS_FACE the facing in degrees.
## seat  - the seated guests of the shop, close up.
## The shop runs on its real, seeded sim; only the camera, the stand-ins and
## the forced weather are set here. Nothing is saved.

const PERSON: PackedScene = preload("res://assets/people/person.tscn")
const TYPES: Array[StringName] = [&"tourist", &"office", &"student", &"tourist", &"office", &"foodie",
	&"tourist", &"family", &"office", &"tourist"]
const ARRIVAL_GAP_TICKS: int = 10
const SETTLE_TICKS: int = 330

var _mode: String = "shop"
var _frame: int = 0
var _stand_ins: Array[PersonView] = []


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 661
	super._ready()
	if sim == null:
		return
	_mode = OS.get_environment("GUEST_LOOKS_MODE") if not OS.get_environment("GUEST_LOOKS_MODE").is_empty() else "shop"
	world.weather.kind = WeatherState.Kind.SUNNY
	refresh_presentation()
	Clock.set_speed(0)
	if _mode == "close":
		_build_stand_ins()
		return
	if not Clock.sim.start_service():
		push_error("Guest looks review could not open service")
		return
	sim.spawner._remaining = 0
	for index: int in TYPES.size():
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 900 + index
		sim.add_customer(world.grid.entries()[0], random, _kind(TYPES[index]))
		run_ticks(ARRIVAL_GAP_TICKS)
	run_ticks(SETTLE_TICKS)
	refresh_presentation()
	print("GUEST_LOOKS_REVIEW mode=%s guests=%d" % [_mode, TYPES.size()])


func _kind(id: StringName) -> CustomerType:
	for kind: CustomerType in customer_type_catalogue.types:
		if kind.id == id:
			return kind
	return null


func _process(delta: float) -> void:
	super._process(delta)
	_frame += 1
	if _frame != 5:
		return
	var rig: CameraRig = $CameraRig as CameraRig
	rig.edge_pan_enabled = false
	rig.minimum_zoom = 1.0
	if OS.get_environment("GUEST_LOOKS_HUD") != "1":
		_hide_interface()
	if _mode == "close":
		var middle: Vector3 = _stand_ins[0].position.lerp(_stand_ins[_stand_ins.size() - 1].position, 0.5)
		rig.initial_focus = Vector2(middle.x, middle.z)
		rig.initial_zoom = float(OS.get_environment("GUEST_LOOKS_ZOOM")) if not OS.get_environment("GUEST_LOOKS_ZOOM").is_empty() else 5.0
	elif _mode == "seat":
		var best: Vector3 = Vector3.ZERO
		var count: int = 0
		var wanted: StringName = StringName(OS.get_environment("GUEST_LOOKS_FOCUS"))
		var skip: int = int(OS.get_environment("GUEST_LOOKS_SKIP"))
		for agent: SimAgent in world.agents:
			var guest: CustomerAgent = agent as CustomerAgent
			var node: Node3D = ($ShopView as ShopView).agent_nodes.get(agent.id)
			if guest == null or node == null or (wanted != &"" and guest.customer_type_id != wanted):
				continue
			if wanted != &"" and skip > 0:
				skip -= 1
				continue
			best += node.position
			count += 1
			if wanted != &"":
				break
		best /= maxf(1.0, count)
		rig.initial_focus = Vector2(best.x, best.z)
		rig.initial_zoom = float(OS.get_environment("GUEST_LOOKS_ZOOM")) if not OS.get_environment("GUEST_LOOKS_ZOOM").is_empty() else 7.0
	else:
		return
	rig.reset_view()
	rig.set_process(false)


func _build_stand_ins() -> void:
	var entry: Vector3 = GridMath.cell_to_world(world.grid.entries()[0])
	var yaw: float = deg_to_rad(($CameraRig as CameraRig).initial_yaw_degrees)
	var across: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	var pose: String = OS.get_environment("GUEST_LOOKS_POSE")
	var face_env: String = OS.get_environment("GUEST_LOOKS_FACE")
	var face: float = deg_to_rad(float(face_env) if not face_env.is_empty() else 0.0)
	var looks: Array = [[&"tourist", 0], [&"tourist", 1], [&"tourist", 2], [&"tourist", 3],
		[&"office", 0], [&"office", 1], [&"office", 2], [&"office", 3]]
	match OS.get_environment("GUEST_LOOKS_SET"):
		"tourist":
			looks = looks.slice(0, 4)
		"office":
			looks = looks.slice(4, 8)
		"farmer", "walker", "surfer", "forager":
			var kind: StringName = StringName(OS.get_environment("GUEST_LOOKS_SET"))
			looks = [[kind, 0], [kind, 1], [kind, 2], [kind, 3]]
		"location":
			looks = _pairs([&"farmer", &"walker", &"surfer", &"forager"])
		"all":
			looks = _pairs([&"tourist", &"office", &"farmer", &"walker", &"surfer", &"forager"])
		"survey":
			# The eight stock guest models, no type look (to pick model pairs).
			looks = [[&"regular", 0], [&"regular", 1], [&"regular", 2], [&"regular", 3],
				[&"regular", 4], [&"regular", 5], [&"regular", 6], [&"regular", 7]]
	for index: int in looks.size():
		var person: PersonView = PERSON.instantiate() as PersonView
		$ShopView.add_child(person)
		person.set_look(&"customer", looks[index][1], looks[index][0])
		person.position = entry + across * (float(index) - (looks.size() - 1) / 2.0) * 0.85 + Vector3(0.0, 0.0, 3.0)
		person.face_direction(Vector3(sin(face), 0.0, cos(face)))
		match pose:
			"walk":
				person.set_pose(true, false, false, false)
			"sit":
				person.set_pose(false, true, false, false, AgentPresentationController.NOMINAL_CHAIR_SEAT_HEIGHT)
				_add_stool(person.position)
			"carry":
				person.set_pose(true, false, true, false)
			_:
				person.set_pose(false, false, false, false)
		person.set_playback_speed(0.0)
		if pose == "walk" or pose == "carry":
			person._player.seek(0.3, true)
		_stand_ins.append(person)


## Ids 0 and 3 of each type: both models of its pair and both palettes.
func _pairs(types: Array[StringName]) -> Array:
	var looks: Array = []
	for kind: StringName in types:
		looks.append([kind, 0])
		looks.append([kind, 3])
	return looks


## A plain block to sit on (the fixture has no chairs on the pavement).
func _add_stool(at: Vector3) -> void:
	var stool: MeshInstance3D = MeshInstance3D.new()
	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3(0.3, AgentPresentationController.NOMINAL_CHAIR_SEAT_HEIGHT, 0.3)
	stool.mesh = block
	stool.position = at + Vector3(0.0, block.size.y / 2.0, 0.0)
	$ShopView.add_child(stool)


## Camera-only stills: the HUD and its popups are not part of the look.
func _hide_interface() -> void:
	for child: Node in get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
		elif child is Control:
			(child as Control).visible = false
