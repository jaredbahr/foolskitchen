class_name CatView
extends Node3D
## Draws the shop cat (#119) from RestaurantCat: view only, it reads the sim and
## never writes it. The cat moves smoothly between cells (the same one-tick-
## behind blend the people use), plays `walk` while it moves, `nap` while it
## sleeps and `idle` otherwise, and is hidden until it is adopted.

const MODEL: PackedScene = preload("res://assets/made/cat/cat.glb")
## Metres the model's legs cover in one walk cycle (so the paws don't skate).
const WALK_STRIDE: float = 0.30
## Radians per second the cat turns towards a new heading.
const TURN_SPEED: float = 9.0
const CLIPS: Array[StringName] = [&"idle", &"walk", &"nap"]

var _model: Node3D
var _player: AnimationPlayer
var _clip: StringName = &""
var _yaw: float = 0.0
var _has_yaw: bool = false


func _ready() -> void:
	name = "Cat"
	visible = false
	scale = Vector3.ONE * ArtScale.CAT_SCALE
	_model = MODEL.instantiate() as Node3D
	if _model == null:
		return
	add_child(_model)
	_player = _first_player(_model)
	if _player == null:
		return
	for clip: StringName in CLIPS:
		if _player.has_animation(clip):
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


## Follows the sim for one drawn frame. `alpha` is the world clock's fraction
## towards the next tick; `speed` the game speed (0 holds the pose).
func sync(cat: RestaurantCat, alpha: float, speed: float, delta: float) -> void:
	if cat == null or not cat.adopted or cat.cell == SimGrid.NO_CELL or _player == null:
		visible = false
		return
	visible = true
	position = cat.floor_position(alpha)
	var target_yaw: float = cat.yaw()
	if not _has_yaw:
		_yaw = target_yaw
		_has_yaw = true
	elif delta > 0.0:
		_yaw = rotate_toward(_yaw, _yaw + angle_difference(_yaw, target_yaw), TURN_SPEED * delta)
	else:
		_yaw = target_yaw
	rotation.y = _yaw
	var wanted: StringName = &"idle"
	var tempo: float = 1.0
	if cat.state == RestaurantCat.State.NAPPING:
		wanted = &"nap"
	elif cat.state == RestaurantCat.State.WALKING:
		wanted = &"walk"
		var metres_per_second: float = GridMath.CELL_SIZE * float(SimClock.TICKS_PER_SECOND) / float(maxi(cat.step_total, 1))
		if cat.from_cell.x != cat.cell.x and cat.from_cell.y != cat.cell.y:
			metres_per_second *= GridMath.DIAGONAL_COST
		tempo = metres_per_second / WALK_STRIDE * _player.get_animation(wanted).length
	if wanted != _clip and _player.has_animation(wanted):
		_clip = wanted
		_player.play(wanted, 0.15)
	_player.speed_scale = speed * tempo


## The clip playing now (for tests and captures).
func current_clip() -> StringName:
	return _clip


func player() -> AnimationPlayer:
	return _player


func _first_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _first_player(child)
		if found != null:
			return found
	return null
