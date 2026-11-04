extends "res://src/world/main.gd"
## Explicit, unsaved review of the restaurant cat (#119): the real shop with an
## adopted cat and a Mini Character beside it for scale. Capture with
##   bash tools/screenshot.sh --scene=res://tools/cat_review.tscn --speed=0 --frames=30,70,110
## Frame 30 is the cat walking, 70 napping in its sunny spot, 110 the ordinary
## game zoom. The shop runs on its real, seeded sim; only the camera, the
## stand-in guest and the paused clip pose are set here. Nothing is saved.

const PERSON: PackedScene = preload("res://assets/people/person.tscn")
const WALK_FRAME: int = 10
const NAP_FRAME: int = 50
const WIDE_FRAME: int = 90
const CLOSE_ZOOM: float = 2.6
const SEARCH_TICKS: int = 4000

var _review_frame: int = 0
var _person: PersonView


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 119
	super._ready()
	if sim == null:
		return
	sim.cat.adopt(world.grid)
	Clock.set_speed(0)
	if not Clock.sim.start_service():
		push_error("Cat review could not open service")
		return
	var rig: CameraRig = $CameraRig as CameraRig
	rig.edge_pan_enabled = false
	rig.minimum_zoom = 1.0
	_person = PERSON.instantiate() as PersonView
	$ShopView.add_child(_person)
	_person.set_look(&"customer", 6, &"regular")
	_person.set_playback_speed(0.0)
	# The cat's first morning nap is a fixture of its own: show it at the bed.
	_place_cat_shot(false)


func _process(delta: float) -> void:
	super._process(delta)
	_review_frame += 1
	# The two close shots show the cat and the stand-in guest alone; the wide
	# shot shows the shop as played.
	for node: Node3D in ($ShopView as ShopView).agent_nodes.values():
		node.visible = node.visible and _review_frame >= WIDE_FRAME
	if _review_frame == WALK_FRAME:
		_run_until(func() -> bool: return sim.cat.state == RestaurantCat.State.WALKING \
			and sim.cat.step_done == sim.cat.step_total / 2 and sim.cat.step_total > 6)
		_place_cat_shot(true)
		_pose_cat(0.30)
	elif _review_frame == NAP_FRAME:
		_run_until(func() -> bool: return sim.cat.state == RestaurantCat.State.NAPPING \
			and sim.cat.cell != sim.cat.bed() and sim.cat.nap_spots(world.grid).has(sim.cat.cell))
		_place_cat_shot(true)
		_pose_cat(0.0)
	elif _review_frame == WIDE_FRAME:
		var rig: CameraRig = $CameraRig as CameraRig
		rig.initial_focus = Vector2(sim.cat.floor_position().x, sim.cat.floor_position().z)
		rig.initial_zoom = 10.0
		rig.reset_view()
		rig.set_process(false)
		_person.visible = false
		_note("wide")


func _run_until(done: Callable) -> void:
	for tick: int in SEARCH_TICKS:
		if done.call():
			return
		sim.advance()
		EventBus.sim_ticked.emit(Clock.sim.tick)
	push_error("Cat review never reached its fixture state")


## Camera on the cat, and the stand-in guest a step beside it, facing it.
func _place_cat_shot(close: bool) -> void:
	var cat: RestaurantCat = sim.cat
	var spot: Vector3 = cat.floor_position()
	var rig: CameraRig = $CameraRig as CameraRig
	var yaw: float = deg_to_rad(rig.initial_yaw_degrees)
	var beside: Vector3 = spot + Vector3(cos(yaw), 0.0, -sin(yaw)) * 1.25
	_person.position = beside
	_person.face_direction(spot - beside)
	_person.set_pose(false, false, false, false)
	var focus: Vector3 = spot.lerp(beside, 0.5)
	rig.initial_focus = Vector2(focus.x, focus.z)
	rig.initial_zoom = CLOSE_ZOOM if close else 9.0
	rig.reset_view()
	rig.set_process(false)
	refresh_presentation()
	($ShopView as ShopView)._process(0.0)


## Holds the paused walk or nap at a chosen point of its clip, for the still.
func _pose_cat(fraction: float) -> void:
	var view: CatView = ($ShopView as ShopView).cat_view
	if view == null or view.player() == null:
		return
	var animation: StringName = view.current_clip()
	var player: AnimationPlayer = view.player()
	player.play(animation)
	player.seek(player.current_animation_length * fraction, true)
	player.pause()
	_note(String(animation))


func _note(label: String) -> void:
	var cat: RestaurantCat = sim.cat
	print("CAT_REVIEW ", JSON.stringify({"shot": label, "state": cat.state, "cell": [cat.cell.x, cat.cell.y],
		"bed": [cat.bed().x, cat.bed().y], "sunny": cat.naps_in_sun(world.grid), "world_tick": world.now}))
