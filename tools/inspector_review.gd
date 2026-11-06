extends "res://src/world/main.gd"
## Explicit, unsaved review of the health inspector (#302): the real shop in
## service with a real inspector walking the dining room with their clipboard
## (frame 30, close), the grade card in the street window (frame 70) and a paused
## pose lineup of the inspector beside a guest and a server (frame 110).
## Capture with
##   bash tools/screenshot.sh --scene=res://tools/inspector_review.tscn --speed=0 --frames=30,70,110
## The shop runs on its real, seeded sim; only the visit's plan, the camera and
## the paused clip pose are set here. INSPECTOR_REVIEW_GRADE (A, B or C) picks
## the card's grade. Nothing is saved.

const WALK_FRAME: int = 10
const CARD_FRAME: int = 50
const LINEUP_FRAME: int = 90
const PERSON: PackedScene = preload("res://assets/people/person.tscn")
const SEARCH_TICKS: int = 4000
const WARMUP_TICKS: int = 500
const CLOSE_ZOOM: float = 2.6

var _review_frame: int = 0


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 302
	super._ready()
	if sim == null:
		return
	Clock.set_speed(0)
	for level: int in [1, 2, 3]:
		owner_progress.award_bonus(owner_progress.threshold_for(level))
	sim.set_customer_level(owner_progress.level)
	$HUD.set_owner_progress(owner_progress.level, owner_progress.xp_into_level(), owner_progress.xp_in_level())
	if not Clock.sim.start_service():
		push_error("Inspector review could not open service")
		return
	var rig: CameraRig = $CameraRig as CameraRig
	rig.edge_pan_enabled = false
	rig.minimum_zoom = 1.0
	# A few minutes of ordinary service so the dining room has guests in it.
	for tick: int in WARMUP_TICKS:
		sim.advance()
		EventBus.sim_ticked.emit(Clock.sim.tick)
	sim.inspection.planned_day = Clock.sim.day
	sim.inspection.planned_tick = Clock.sim.phase_tick + 1


func _process(delta: float) -> void:
	super._process(delta)
	if sim == null:
		return
	_review_frame += 1
	if _review_frame == WALK_FRAME:
		_run_until(func() -> bool: return sim.inspector != null and sim.inspector.movement_admitted \
			and sim.inspector.state == InspectorAgent.State.WALKING and sim.inspector.move_progress > 0.4 \
			and sim.inspector.started_tick >= 0 and sim.world.now - sim.inspector.started_tick > 120)
		_frame_inspector()
	elif _review_frame == LINEUP_FRAME:
		_lineup()
	elif _review_frame == CARD_FRAME:
		_run_until(func() -> bool: return sim.inspector == null and sim.inspection.last_day == Clock.sim.day)
		_frame_card()


func _run_until(done: Callable) -> void:
	for tick: int in SEARCH_TICKS:
		if done.call():
			return
		sim.advance()
		EventBus.sim_ticked.emit(Clock.sim.tick)
	push_error("Inspector review never reached its fixture state")


## Camera on the inspector, the walk paused in mid-stride.
func _frame_inspector() -> void:
	var inspector: InspectorAgent = sim.inspector
	var spot: Vector3 = inspector.movement_position()
	var rig: CameraRig = $CameraRig as CameraRig
	rig.initial_focus = Vector2(spot.x, spot.z)
	rig.initial_zoom = CLOSE_ZOOM
	# Look at him from the front, a little to the side: the camera faces the
	# way they are not heading.
	var heading: Vector3 = GridMath.cell_to_world(inspector.next_cell()) - GridMath.cell_to_world(inspector.cell)
	rig.initial_yaw_degrees = rad_to_deg(atan2(heading.x, heading.z)) + float(OS.get_environment("INSPECTOR_REVIEW_YAW") if OS.has_environment("INSPECTOR_REVIEW_YAW") else "35")
	rig.reset_view()
	rig.set_process(false)
	refresh_presentation()
	var view: ShopView = $ShopView as ShopView
	view.set_wall_mode(ShopView.WallMode.DOWN)
	view._process(0.0)
	var node: PersonView = view.agent_nodes.get(inspector.id) as PersonView
	if node != null and node._player != null:
		node._player.seek(node._player.current_animation_length * 0.3, true)
	print("INSPECTOR_REVIEW ", JSON.stringify({"shot": "walking", "cell": [inspector.cell.x, inspector.cell.y],
		"clip": String(node.current_clip()) if node != null else "", "clipboard": node != null and node._clipboard.visible,
		"stops": inspector.stops.size(), "world_tick": world.now}))


## Camera on the street window with the grade card, in daylight.
func _frame_card() -> void:
	var grade: String = OS.get_environment("INSPECTOR_REVIEW_GRADE")
	sim.inspection.record(Clock.sim.day, {"grade": StringName(grade if ["A", "B", "C"].has(grade) else "B"), "findings": []})
	var view: ShopView = $ShopView as ShopView
	view.set_wall_mode(ShopView.WallMode.UP)
	view._process(0.0)
	var card: Node3D = view.wall_finish_view.grade_card()
	var camera: Camera3D = get_node("CameraRig/Camera3D") as Camera3D
	var rig: CameraRig = $CameraRig as CameraRig
	rig.set_process(false)
	for node: Node3D in view.agent_nodes.values():
		node.visible = false
	if card == null:
		push_error("Inspector review: no grade card was drawn")
		return
	var into: Vector2i = -WallRules.street_side(world.grid)
	var along: Vector2i = WallFaces.DIRS[posmod(WallFaces.DIRS.find(into) + 1, 4)]
	var outward: Vector3 = Vector3(-into.x, 0.0, -into.y)
	var right: Vector3 = Vector3(along.x, 0.0, along.y)
	var target: Vector3 = card.global_position
	camera.global_position = target + outward * 7.0 + right * 1.2 + Vector3.UP * 2.6
	camera.look_at(target)
	camera.size = 2.6
	print("INSPECTOR_REVIEW ", JSON.stringify({"shot": "card", "grade": String(sim.inspection.last_grade),
		"card_position": [card.global_position.x, card.global_position.y, card.global_position.z]}))


## Pose lineup on bare floor, paused: the inspector walking and standing with
## the clipboard beside an ordinary guest and a server carrying (their poses
## must be exactly the game's own).
func _lineup() -> void:
	var view: ShopView = $ShopView as ShopView
	view.set_wall_mode(ShopView.WallMode.DOWN)
	for node: Node3D in view.agent_nodes.values():
		node.visible = false
	var rig: CameraRig = $CameraRig as CameraRig
	var base: Vector3 = GridMath.cell_to_world(Vector2i(7, 15))
	var yaw: float = deg_to_rad(rig.initial_yaw_degrees)
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	var specs: Array[Array] = [[&"inspector", &"clipboard-walk"], [&"inspector", &"clipboard-hold"],
		[&"customer", &"idle"], [&"customer", &"walk"], [&"server", &"holding-both"], [&"customer", &"sit"]]
	for index: int in specs.size():
		var person: PersonView = PERSON.instantiate() as PersonView
		# As ShopView does: the look is recorded before the node enters the tree.
		person.set_look(specs[index][0], 6, &"regular")
		view.add_child(person)
		person.position = base + right * (0.7 * (float(index) - 2.5))
		person.face_direction(Vector3(sin(yaw), 0.0, cos(yaw)))
		person.set_playback_speed(0.0)
		person.set_pose(specs[index][1] in [&"walk", &"clipboard-walk"], specs[index][1] == &"sit",
			specs[index][1] in [&"holding-both", &"clipboard-walk", &"clipboard-hold"], false, 0.27 if specs[index][1] == &"sit" else 0.0)
		person._player.seek(0.25, true)
	rig.initial_focus = Vector2(base.x, base.z)
	rig.initial_zoom = 4.2
	rig.reset_view()
	rig.set_process(false)
	print("INSPECTOR_REVIEW ", JSON.stringify({"shot": "lineup"}))
