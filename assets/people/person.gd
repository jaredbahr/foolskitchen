class_name PersonView
extends Node3D
## Reusable Mini Character view. The caller owns movement, state and attachments.
## ArtScale is the shared dependency authored by FK-052 (#97).

@export var role: StringName = &"customer"
@export var guest_id: int = 0
@export var customer_type: StringName = &"regular"

var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _hat: Node3D
var _model_name: StringName = &""
var _clip: StringName = &""
var _requested_clip: StringName = &"idle"
var _seat_height: float = 0.0
var _initialized: bool = false
var _playback_speed: float = 1.0
var _seated_lean_degrees: float = 0.0
var _sit_lean_track: int = -1
var _sit_base_rotations: Array[Quaternion] = []


func _ready() -> void:
	_hat = get_node("ChefHat") as Node3D
	_initialized = true
	set_look(role, guest_id, customer_type)


## False means the role has no approved look or the required source is missing.
## Calling before ready records the requested look for normal scene creation.
func set_look(value: StringName, id: int = 0, kind: StringName = &"regular") -> bool:
	role = value
	guest_id = id
	customer_type = kind
	var desired_model: StringName = PersonPresentation.model_for(role, guest_id, customer_type)
	if not _initialized:
		return desired_model != &""
	if desired_model == _model_name and _model != null:
		return true
	var seated_time: float = _player.current_animation_position if _player != null and _clip == &"sit" else 0.0
	_clear_model()
	if desired_model == &"":
		return false
	var path: String = PersonPresentation.model_path_for(role, guest_id, customer_type)
	if not ResourceLoader.exists(path, "PackedScene"):
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false
	var instance: Node = packed.instantiate()
	_model = instance as Node3D
	if _model == null:
		instance.free()
		return false
	var pivot: Node3D = get_node("ModelPivot") as Node3D
	pivot.scale = Vector3.ONE * ArtScale.CHARACTER_SCALE
	pivot.add_child(_model)
	_player = _first_descendant(_model, "AnimationPlayer") as AnimationPlayer
	_skeleton = _first_descendant(_model, "Skeleton3D") as Skeleton3D
	if _player == null or _skeleton == null or not _prepare_clips():
		_clear_model()
		return false
	_player.speed_scale = _playback_speed
	if PersonPresentation.has_chef_hat(role):
		var head: int = _skeleton.find_bone("head")
		if head < 0:
			_clear_model()
			return false
		var attachment: BoneAttachment3D = BoneAttachment3D.new()
		attachment.name = "ChefHatAttachment"
		attachment.bone_name = "head"
		_skeleton.add_child(attachment)
		_hat.reparent(attachment, false)
		_hat.visible = true
	_model_name = desired_model
	var played: bool = _play_requested_clip()
	if played and _clip == &"sit" and seated_time > 0.0:
		_player.seek(minf(seated_time, _player.get_animation(&"sit").length), true)
	return played


## The caller passes the actual chair seat's world height after seat arrival.
## It also positions the person at the chair and supplies that chair's facing.
func set_pose(moving: bool, seated: bool, carrying: bool, working: bool, seat_height: float = 0.0,
		seated_lean_degrees: float = 0.0) -> bool:
	if not PersonPresentation.seated_lean_valid(seated_lean_degrees):
		return false
	var lean: float = seated_lean_degrees if seated else 0.0
	var lean_changed: bool = lean != _seated_lean_degrees
	_requested_clip = PersonPresentation.clip_for_state(moving, seated, carrying, working)
	_seat_height = maxf(seat_height, 0.0) if seated else 0.0
	_seated_lean_degrees = lean
	var pivot: Node3D = get_node_or_null("ModelPivot") as Node3D
	if pivot != null:
		pivot.position.y = _seat_height
	if lean_changed and _player != null:
		_update_seated_lean()
		if _clip == &"sit":
			# Re-evaluate the private track without restarting a paused/live pose.
			_player.seek(_player.current_animation_position, true)
	return _play_requested_clip()


## Keeps the last facing while stationary. Only this view's rotation changes.
func face_direction(direction: Vector3) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.000001:
		rotation.y = atan2(-flat.x, -flat.z)


## The world caller supplies its current speed, including zero while paused.
func set_playback_speed(value: float) -> void:
	_playback_speed = maxf(value, 0.0) if is_finite(value) else 0.0
	if _player != null:
		_player.speed_scale = _playback_speed


func model_name() -> StringName:
	return _model_name


func current_clip() -> StringName:
	return _clip


func current_seated_lean_degrees() -> float:
	return _seated_lean_degrees


## Person-local animated head top, including seat lift and shared scale.
## The source bounds include the model's hair. Pixel fit is checked separately.
func head_anchor_position() -> Vector3:
	if _skeleton == null:
		return Vector3.ZERO
	var head: int = _skeleton.find_bone("head")
	if head < 0:
		return Vector3.ZERO
	var rest: Transform3D = _skeleton.get_bone_global_rest(head)
	var crown: Vector3 = Vector3(0.0, PersonPresentation.source_head_top(_model_name) - rest.origin.y, 0.0)
	return _skeleton_point_to_person(_skeleton.get_bone_global_pose(head) * crown)


## Midpoint of the two palms in the source rig, in this person's coordinates.
## The arms are rigid pieces extending along local +/-X from their shoulders.
func carry_anchor_position() -> Vector3:
	if _skeleton == null:
		return Vector3.ZERO
	var left: int = _skeleton.find_bone("arm-left")
	var right: int = _skeleton.find_bone("arm-right")
	if left < 0 or right < 0:
		return Vector3.ZERO
	var left_palm: Vector3 = _skeleton.get_bone_global_pose(left) * Vector3(0.24, 0.0, 0.0)
	var right_palm: Vector3 = _skeleton.get_bone_global_pose(right) * Vector3(-0.24, 0.0, 0.0)
	return _skeleton_point_to_person((left_palm + right_palm) * 0.5)


func _skeleton_point_to_person(point: Vector3) -> Vector3:
	var transform_to_person: Transform3D = Transform3D.IDENTITY
	var cursor: Node = _skeleton
	while cursor != null and cursor != self:
		if cursor is Node3D:
			transform_to_person = (cursor as Node3D).transform * transform_to_person
		cursor = cursor.get_parent()
	return transform_to_person * point if cursor == self else Vector3.ZERO


## Duplicate only the approved clips. Never change imported, shared resources.
func _prepare_clips() -> bool:
	var library: AnimationLibrary = AnimationLibrary.new()
	for clip: StringName in PersonPresentation.CLIPS:
		var source: Animation = _source_clip(clip)
		if source == null:
			return false
		var animation: Animation = source.duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR
		if clip == &"sit" and not _prepare_seated_lean(animation):
			return false
		library.add_animation(clip, animation)
	for name: StringName in _player.get_animation_library_list():
		_player.remove_animation_library(name)
	_player.add_animation_library(&"", library)
	_update_seated_lean()
	return true


## The eight native guest rigs have identity torso rest rotation and sit keys
## only on root/arms/legs. The torso joint is a sibling of both hip/leg joints.
## Local +X pitches the upper body toward source +Z, person -Z after ModelPivot.
## Build the actual imported path and retain any source rotation keys rather
## than mutating the imported animation, root translation, legs or model scale.
func _prepare_seated_lean(animation: Animation) -> bool:
	var torso: int = _skeleton.find_bone("torso")
	var animation_root: Node = _player.get_node_or_null(_player.root_node)
	if torso < 0 or animation_root == null:
		return false
	var path: NodePath = NodePath(String(animation_root.get_path_to(_skeleton)) + ":torso")
	_sit_lean_track = animation.find_track(path, Animation.TYPE_ROTATION_3D)
	if _sit_lean_track < 0:
		_sit_lean_track = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(_sit_lean_track, path)
		var rest: Quaternion = _skeleton.get_bone_rest(torso).basis.get_rotation_quaternion()
		animation.track_insert_key(_sit_lean_track, 0.0, rest)
		animation.track_insert_key(_sit_lean_track, animation.length, rest)
	_sit_base_rotations.clear()
	for key: int in animation.track_get_key_count(_sit_lean_track):
		var rotation: Quaternion = animation.track_get_key_value(_sit_lean_track, key)
		_sit_base_rotations.append(rotation)
	return not _sit_base_rotations.is_empty()


func _update_seated_lean() -> void:
	var animation: Animation = _player.get_animation(&"sit")
	var lean: Quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(_seated_lean_degrees))
	for key: int in _sit_base_rotations.size():
		animation.track_set_key_value(_sit_lean_track, key, _sit_base_rotations[key] * lean)


func _source_clip(clip: StringName) -> Animation:
	if _player.has_animation(clip):
		return _player.get_animation(clip)
	for name: StringName in _player.get_animation_list():
		# Imported libraries may prefix the kit's clip name with a library path.
		if String(name).get_file() == String(clip):
			return _player.get_animation(name)
	return null


func _play_requested_clip() -> bool:
	if _player == null or not _player.has_animation(_requested_clip):
		return false
	if _clip == _requested_clip:
		return true
	_player.stop()
	# Holding and sitting only key part of the skeleton; clear the previous pose.
	_skeleton.reset_bone_poses()
	_player.play(_requested_clip)
	_player.advance(0.0)
	_clip = _requested_clip
	return true


func _clear_model() -> void:
	if _hat != null:
		_hat.visible = false
		if _hat.get_parent() != self:
			_hat.reparent(self, false)
	if _model != null:
		_model.get_parent().remove_child(_model)
		_model.free()
	_model = null
	_player = null
	_skeleton = null
	_model_name = &""
	_clip = &""
	_sit_lean_track = -1
	_sit_base_rotations.clear()


func _first_descendant(root: Node, type: String) -> Node:
	var matches: Array[Node] = root.find_children("*", type, true, false)
	return null if matches.is_empty() else matches[0]
