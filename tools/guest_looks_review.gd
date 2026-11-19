extends "res://src/world/main.gd"
## Explicit, unsaved visual fixture for the tourist and office-crowd looks (#661).
## Pick the shot with GUEST_LOOKS_MODE, then capture with
##   GUEST_LOOKS_MODE=shop bash tools/screenshot.sh --scene=res://tools/guest_looks_review.tscn --speed=0 --frames=60
## shop  - the real shop, ten guests of mixed types seated and walking in, sunny.
## close - eight stand-ins (tourists, then office guests, two ids per model)
##         standing in a row; GUEST_LOOKS_POSE=idle|walk picks the pose.
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
	var walking: bool = OS.get_environment("GUEST_LOOKS_POSE") == "walk"
	var looks: Array = [[&"tourist", 0], [&"tourist", 1], [&"tourist", 2], [&"tourist", 3],
		[&"office", 0], [&"office", 1], [&"office", 2], [&"office", 3]]
	match OS.get_environment("GUEST_LOOKS_SET"):
		"tourist":
			looks = looks.slice(0, 4)
		"office":
			looks = looks.slice(4, 8)
		"survey":
			# The eight stock guest models, no type look (to pick model pairs).
			looks = [[&"regular", 0], [&"regular", 1], [&"regular", 2], [&"regular", 3],
				[&"regular", 4], [&"regular", 5], [&"regular", 6], [&"regular", 7]]
	for index: int in looks.size():
		var person: PersonView = PERSON.instantiate() as PersonView
		$ShopView.add_child(person)
		person.set_look(&"customer", looks[index][1], looks[index][0])
		person.position = entry + across * (float(index) - (looks.size() - 1) / 2.0) * 0.85 + Vector3(0.0, 0.0, 2.2)
		person.face_direction(-across.cross(Vector3.UP) if false else Vector3(0.0, 0.0, 1.0))
		person.set_pose(walking, false, false, false)
		person.set_playback_speed(0.0)
		if walking:
			person._player.seek(0.3, true)
		_stand_ins.append(person)


## Camera-only stills: the HUD and its popups are not part of the look.
func _hide_interface() -> void:
	for child: Node in get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
		elif child is Control:
			(child as Control).visible = false
