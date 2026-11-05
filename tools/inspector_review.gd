extends "res://src/world/main.gd"
## Explicit, unsaved review of the health inspector (#302): the real shop in
## service with a real inspector walking the dining room with his clipboard
## (frame 30, close), and the grade card in the street window (frame 70).
## Capture with
##   bash tools/screenshot.sh --scene=res://tools/inspector_review.tscn --speed=0 --frames=30,70
## The shop runs on its real, seeded sim; only the visit's plan, the camera and
## the paused clip pose are set here. INSPECTOR_REVIEW_GRADE (A, B or C) picks
## the card's grade. Nothing is saved.

const WALK_FRAME: int = 10
const CARD_FRAME: int = 50
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
	# way he is not heading.
	var heading: Vector3 = GridMath.cell_to_world(inspector.next_cell()) - GridMath.cell_to_world(inspector.cell)
	rig.initial_yaw_degrees = rad_to_deg(atan2(heading.x, heading.z)) + 35.0
	rig.reset_view()
	rig.set_process(false)
	refresh_presentation()
	var view: ShopView = $ShopView as ShopView
	view.set_wall_mode(ShopView.WallMode.DOWN)
	view._process(0.0)
	var node: PersonView = view.agent_nodes.get(inspector.id) as PersonView
	if node != null and node._player != null:
		node._player.seek(node._player.current_animation_length * 0.3, true)
		node._player.pause()
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
