class_name PersonView
extends Node3D
## Reusable Mini Character view. The caller owns movement, state and attachments.
## ArtScale is the shared dependency authored by FK-052 (#97).

@export var role: StringName = &"customer"
@export var guest_id: int = 0
@export var customer_type: StringName = &"regular"
@export var owner_model: StringName = OwnerAppearance.DEFAULT_MODEL

const REGULAR_SWATCHES: Dictionary[StringName, SwatchDef] = {
	&"honey": preload("res://data/swatches/honey.tres"),
	&"slate_blue": preload("res://data/swatches/slate_blue.tres"),
	&"sage": preload("res://data/swatches/sage.tres"),
	&"cream": preload("res://data/swatches/cream.tres"),
}

## Clothing ramps measured from each kit body-mesh's torso UVs (see PersonPresentation).
const REGULAR_CLOTHING_RAMPS: Dictionary[StringName, Rect2i] = PersonPresentation.CLOTHING_RAMPS
static var _regular_materials: Dictionary[StringName, Material] = {}

var _regular_model: StringName = &""
var _regular_tint: StringName = &""
var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _hat: Node3D
var _cap: Node3D
var _clipboard: Node3D
var _model_name: StringName = &""
## Which tourist or office look the current model wears (see PersonPresentation.type_look_key).
var _piece_key: StringName = &""
var _clip: StringName = &""
var _requested_clip: StringName = &"idle"
var _seat_height: float = 0.0
var _initialized: bool = false
var _playback_speed: float = 1.0
var _seated_lean_degrees: float = 0.0
var _sit_lean_track: int = -1
var _sit_base_rotations: Array[Quaternion] = []
## Where the clipboard sits from the midpoint of the two palms (person-local).
const CLIPBOARD_OFFSET: Vector3 = Vector3(0.0, 0.0, -0.1)
## Made pieces for guest types (#661), built by tools/build_guest_props.py.
const SUN_HAT_SCENE: PackedScene = preload("res://assets/made/people/sun_hat.glb")
const LANYARD_SCENE: PackedScene = preload("res://assets/made/people/lanyard.glb")
## Location guests' pieces (#663 #657 #659), from the same generator.
const FARM_HAT_SCENE: PackedScene = preload("res://assets/made/people/farm_hat.glb")
const OVERALL_BIB_SCENE: PackedScene = preload("res://assets/made/people/overall_bib.glb")
const BEANIE_SCENE: PackedScene = preload("res://assets/made/people/beanie.glb")
const BASKET_SCENE: PackedScene = preload("res://assets/made/people/basket.glb")
## Uniform materials by role, built once from the vendored colormap.
static var _uniform_materials: Dictionary[StringName, Material] = {}
## Tourist shirts and office jackets, by model and look.
static var _type_materials: Dictionary[String, Material] = {}


func _ready() -> void:
	_hat = get_node("ChefHat") as Node3D
	_cap = get_node("CourierCap") as Node3D
	_clipboard = get_node("Clipboard") as Node3D
	_initialized = true
	set_look(role, guest_id, customer_type)


## False means the role has no approved look or the required source is missing.
## Calling before ready records the requested look for normal scene creation.
func set_look(value: StringName, id: int = 0, kind: StringName = &"regular") -> bool:
	role = value
	guest_id = id
	customer_type = kind
	var regular: bool = role in [&"customer", &"guest"] and not _regular_model.is_empty()
	var desired_model: StringName = _regular_model if regular else PersonPresentation.model_for(role, guest_id, customer_type, owner_model)
	if not _initialized:
		return desired_model != &""
	var piece_key: StringName = PersonPresentation.type_look_key(role, guest_id, customer_type)
	if desired_model == _model_name and _model != null and piece_key == _piece_key:
		return true
	var seated_time: float = _player.current_animation_position if _player != null and _clip == &"sit" else 0.0
	_clear_model()
	if desired_model == &"":
		return false
	var path: String = PersonPresentation.MODEL_DIRECTORY + String(desired_model) + ".glb"
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
	# Repaint the kit meshes before any head piece joins the model's tree.
	if not _apply_uniform():
		_clear_model()
		return false
	if PersonPresentation.has_chef_hat(role) and not _attach_to_head(_hat, "ChefHatAttachment"):
		_clear_model()
		return false
	if PersonPresentation.has_courier_cap(role) and not _attach_to_head(_cap, "CourierCapAttachment"):
		_clear_model()
		return false
	if not _attach_guest_type_pieces(regular, desired_model):
		_clear_model()
		return false
	if _clipboard != null:
		_clipboard.visible = PersonPresentation.has_clipboard(role)
	if regular and not _apply_regular_clothing(desired_model):
		_clear_model()
		return false
	_model_name = desired_model
	_piece_key = piece_key
	var played: bool = _play_requested_clip()
	if played and _clip == &"sit" and seated_time > 0.0:
		_player.seek(minf(seated_time, _player.get_animation(&"sit").length), true)
	return played


## Fixed guest appearance survives changing runtime agent IDs. Only a private
## clothing-colormap copy is tinted; faces, hands and hair keep kit colours.
func set_regular_look(model: StringName = &"", tint: StringName = &"") -> bool:
	if not model.is_empty() and (not REGULAR_CLOTHING_RAMPS.has(model) or not REGULAR_SWATCHES.has(tint)):
		return false
	if model == _regular_model and tint == _regular_tint:
		return true
	_regular_model = model
	_regular_tint = tint
	if _initialized:
		_clear_model()
		return set_look(role, guest_id, customer_type)
	return true


func regular_tint() -> StringName:
	return _regular_tint


func _apply_regular_clothing(model: StringName) -> bool:
	var meshes: Array[Node] = _model.find_children("*", "MeshInstance3D", true, false)
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.name != &"body-mesh":
			continue
		var key: StringName = StringName(String(model) + ":" + String(_regular_tint))
		var material: Material = _regular_materials.get(key)
		if material == null:
			var recolors: Array[Dictionary] = [{"rect": REGULAR_CLOTHING_RAMPS[model],
				"color": REGULAR_SWATCHES[_regular_tint].color}]
			material = _uniform_material(mesh.mesh.surface_get_material(0), recolors)
			if material == null:
				return false
			_regular_materials[key] = material
		for surface: int in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, material)
		return true
	return false


## The tourist's sun hat and shirt, the office worker's lanyard and jacket
## (#661). Presentation only: the choice reads the guest id, never a random stream.
func _attach_guest_type_pieces(regular: bool, model: StringName) -> bool:
	if PersonPresentation.has_sun_hat(role, customer_type):
		var lift: float = _head_top_in_bone_space(model)
		if lift < 0.0:
			return false
		var hat: Node3D = SUN_HAT_SCENE.instantiate() as Node3D
		if hat == null or not _attach_made_piece(hat, "SunHatAttachment", "head",
				Vector3(0.0, lift - PersonPresentation.SUN_HAT_SINK, PersonPresentation.SUN_HAT_BACK),
				PersonPresentation.SUN_HAT_TILT_DEGREES):
			return false
	if PersonPresentation.has_lanyard(role, customer_type):
		var lanyard: Node3D = LANYARD_SCENE.instantiate() as Node3D
		if lanyard == null or not _attach_made_piece(lanyard, "LanyardAttachment", "torso", Vector3.ZERO):
			return false
	if PersonPresentation.has_farm_hat(role, customer_type) and not _attach_head_piece(FARM_HAT_SCENE,
			"FarmHatAttachment", model, PersonPresentation.FARM_HAT_SINK, PersonPresentation.FARM_HAT_BACK,
			PersonPresentation.FARM_HAT_TILT_DEGREES):
		return false
	if PersonPresentation.has_beanie(role, customer_type) and not _attach_head_piece(BEANIE_SCENE,
			"BeanieAttachment", model, PersonPresentation.BEANIE_SINK, PersonPresentation.BEANIE_BACK,
			PersonPresentation.BEANIE_TILT_DEGREES):
		return false
	if PersonPresentation.has_overall_bib(role, customer_type):
		var bib: Node3D = OVERALL_BIB_SCENE.instantiate() as Node3D
		if bib == null or not _attach_made_piece(bib, "OverallBibAttachment", "torso", Vector3.ZERO):
			return false
	if PersonPresentation.has_basket(role, customer_type):
		var basket: Node3D = BASKET_SCENE.instantiate() as Node3D
		if basket == null or not _attach_made_piece(basket, "BasketAttachment", "arm-left",
				PersonPresentation.BASKET_OFFSET):
			return false
		basket.rotation_degrees = PersonPresentation.BASKET_ROTATION_DEGREES
	if regular:
		return true
	var outfit: Dictionary = PersonPresentation.outfit(role, guest_id, customer_type)
	if not outfit.is_empty():
		return _apply_outfit(outfit, model)
	var recolors: Array[Dictionary] = PersonPresentation.type_recolors(role, guest_id, customer_type, model)
	if recolors.is_empty():
		return true
	return _apply_body_recolors(recolors, "%s:%s:%d" % [model, customer_type, PersonPresentation.type_variant(guest_id)])


## A hat-like piece fitted to the model's measured head top, sunk into the hair.
func _attach_head_piece(scene: PackedScene, attachment_name: String, model: StringName, sink: float,
		back: float, tilt_degrees: float) -> bool:
	var lift: float = _head_top_in_bone_space(model)
	if lift < 0.0:
		return false
	var piece: Node3D = scene.instantiate() as Node3D
	return piece != null and _attach_made_piece(piece, attachment_name, "head", Vector3(0.0, lift - sink, back),
		tilt_degrees)


## Dresses the body mesh in a location guest's outfit (PersonOutfit) and, for
## wet hair, darkens the head's hair block. Both are private, cached copies.
func _apply_outfit(outfit: Dictionary, model: StringName) -> bool:
	if not PersonPresentation.SKIN_COLUMNS.has(model):
		return false
	var key: String = "%s:%s:%d" % [model, customer_type, PersonPresentation.type_variant(guest_id)]
	var dressed: bool = false
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.name == &"body-mesh":
			var built: Array = PersonOutfit.dressed_body(mesh, outfit, PersonPresentation.SKIN_COLUMNS[model], key)
			if built.is_empty():
				return false
			mesh.mesh = built[0]
			dressed = true
		elif mesh.name == &"head-mesh" and outfit.has("hair") and PersonPresentation.HAIR_COLUMNS.has(model):
			var hair: Material = PersonOutfit.wet_hair_material(mesh, PersonPresentation.HAIR_COLUMNS[model],
				outfit["hair"], key + ":hair")
			if hair == null:
				return false
			mesh.set_surface_override_material(0, hair)
	return dressed


## Head top above the head bone's rest origin, in the bone's own space.
func _head_top_in_bone_space(model: StringName) -> float:
	var head: int = _skeleton.find_bone("head")
	if head < 0 or PersonPresentation.source_head_top(model) <= 0.0:
		return -1.0
	return PersonPresentation.source_head_top(model) - _skeleton.get_bone_global_rest(head).origin.y


func _attach_made_piece(piece: Node3D, attachment_name: String, bone: String, offset: Vector3,
		tilt_degrees: float = 0.0) -> bool:
	if piece == null or _skeleton.find_bone(bone) < 0:
		if piece != null:
			piece.free()
		return false
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = bone
	_skeleton.add_child(attachment)
	piece.position = offset
	piece.rotation_degrees.x = tilt_degrees
	attachment.add_child(piece)
	return true


## Repaints blocks of a private colormap copy on the body mesh only, so the
## head keeps the kit's skin and hair.
func _apply_body_recolors(recolors: Array[Dictionary], key: String) -> bool:
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.name != &"body-mesh":
			continue
		var material: Material = _type_materials.get(key)
		if material == null:
			material = _uniform_material(mesh.mesh.surface_get_material(0), recolors)
			if material == null:
				return false
			_type_materials[key] = material
		for surface: int in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, material)
		return true
	return false


func set_owner_model(model: StringName) -> bool:
	if not OwnerAppearance.valid_model(model):
		return false
	owner_model = model
	return set_look(role, guest_id, customer_type)


func _attach_to_head(piece: Node3D, attachment_name: String) -> bool:
	var head: int = _skeleton.find_bone("head")
	if head < 0:
		return false
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = "head"
	_skeleton.add_child(attachment)
	piece.reparent(attachment, false)
	piece.visible = true
	return true


## Overrides this instance's surfaces with the role's repainted colormap copy.
## Roles without a uniform keep the imported, shared material untouched.
func _apply_uniform() -> bool:
	var recolors: Array[Dictionary] = PersonPresentation.uniform_recolors(role)
	if recolors.is_empty():
		return true
	var meshes: Array[Node] = _model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return false
	var material: Material = _uniform_materials.get(role)
	if material == null:
		material = _uniform_material((meshes[0] as MeshInstance3D).mesh.surface_get_material(0), recolors)
		if material == null:
			return false
		_uniform_materials[role] = material
	for node: Node in meshes:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		for surface: int in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)
	return true


static func _uniform_material(source: Material, recolors: Array[Dictionary]) -> Material:
	var base: StandardMaterial3D = source as StandardMaterial3D
	if base == null or base.albedo_texture == null:
		return null
	var image: Image = base.albedo_texture.get_image()
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	for recolor: Dictionary in recolors:
		var rect: Rect2i = recolor["rect"]
		var color: Color = recolor["color"]
		for x: int in range(rect.position.x, rect.end.x):
			var top: float = image.get_pixel(x, rect.position.y).get_luminance()
			for y: int in range(rect.position.y, rect.end.y):
				var shade: float = image.get_pixel(x, y).get_luminance() / top if top > 0.0 else 1.0
				image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, 1.0))
	if image.has_mipmaps():
		image.clear_mipmaps()
	image.generate_mipmaps()
	var material: StandardMaterial3D = base.duplicate() as StandardMaterial3D
	material.albedo_texture = ImageTexture.create_from_image(image)
	return material


## The caller passes the actual chair seat's world height after seat arrival.
## It also positions the person at the chair and supplies that chair's facing.
func set_pose(moving: bool, seated: bool, carrying: bool, working: bool, seat_height: float = 0.0,
		seated_lean_degrees: float = 0.0, bending: bool = false) -> bool:
	if not PersonPresentation.seated_lean_valid(seated_lean_degrees):
		return false
	var lean: float = seated_lean_degrees if seated else 0.0
	var lean_changed: bool = lean != _seated_lean_degrees
	_requested_clip = PersonPresentation.clip_for_role(role,
		PersonPresentation.clip_for_state(moving, seated, carrying, working, bending))
	_seat_height = maxf(seat_height, 0.0) if seated else 0.0
	_seated_lean_degrees = lean
	var pivot: Node3D = get_node_or_null("ModelPivot") as Node3D
	if pivot != null:
		pivot.position.y = _seat_height
	if lean_changed and _player != null:
		_update_seated_lean()
		if _clip == &"sit" and _player.has_animation(&"sit"):
			# Re-evaluate the private track without restarting a paused/live pose.
			_player.seek(_player.current_animation_position, true)
	var played: bool = _play_requested_clip()
	_place_clipboard()
	return played


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


## The inspector's clipboard rides in front of the held hands.
func _place_clipboard() -> void:
	if _clipboard == null or not _clipboard.visible or _skeleton == null:
		return
	_clipboard.position = carry_anchor_position() + CLIPBOARD_OFFSET


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
		animation.loop_mode = Animation.LOOP_NONE if PersonPresentation.ONE_SHOT_CLIPS.has(clip) \
			else Animation.LOOP_LINEAR
		if clip == &"sit" and not _prepare_seated_lean(animation):
			return false
		library.add_animation(clip, animation)
	var carry_walk: Animation = _carry_walk(library.get_animation(&"walk"), library.get_animation(&"holding-both"))
	if carry_walk == null:
		return false
	library.add_animation(PersonPresentation.CARRY_WALK, carry_walk)
	if PersonPresentation.has_clipboard(role):
		library.add_animation(PersonPresentation.CLIPBOARD_WALK, _clipboard_arms(library.get_animation(&"walk")))
		library.add_animation(PersonPresentation.CLIPBOARD_HOLD, _clipboard_arms(library.get_animation(&"idle")))
	for name: StringName in _player.get_animation_library_list():
		_player.remove_animation_library(name)
	_player.add_animation_library(&"", library)
	_update_seated_lean()
	return true


## `walk` with both arm tracks taken from `holding-both` (a held pose), so the
## legs and body keep walking under arms that carry. Same rig, same bones.
static func _carry_walk(walk: Animation, holding: Animation) -> Animation:
	if walk == null or holding == null:
		return null
	var animation: Animation = walk.duplicate(true) as Animation
	for index: int in range(animation.get_track_count() - 1, -1, -1):
		if _is_arm_track(animation, index):
			animation.remove_track(index)
	var copied: int = 0
	for index: int in holding.get_track_count():
		if _is_arm_track(holding, index):
			holding.copy_track(index, animation)
			copied += 1
	if copied == 0:
		return null
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation


## `base` with both arms replaced by the clipboard hold: each rigid arm swung
## forward about the vertical axis and dropped a little, so the hands meet the
## sides of a board held at the chest. Only a copy is built.
static func _clipboard_arms(base: Animation) -> Animation:
	var animation: Animation = base.duplicate(true) as Animation
	var paths: Dictionary[String, NodePath] = {}
	for index: int in range(animation.get_track_count() - 1, -1, -1):
		if _is_arm_track(animation, index):
			var bone: String = String(animation.track_get_path(index)).get_slice(":", 1)
			paths[bone] = animation.track_get_path(index)
			animation.remove_track(index)
	var yaw: float = deg_to_rad(PersonPresentation.CLIPBOARD_ARM_YAW_DEGREES)
	var drop: float = deg_to_rad(PersonPresentation.CLIPBOARD_ARM_DROP_DEGREES)
	var poses: Dictionary[String, Quaternion] = {
		"arm-left": Quaternion(Vector3.UP, -yaw) * Quaternion(Vector3.BACK, -drop),
		"arm-right": Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.BACK, drop),
	}
	for bone: String in paths:
		var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, paths[bone])
		animation.track_insert_key(track, 0.0, poses[bone])
		animation.track_insert_key(track, animation.length, poses[bone])
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation


static func _is_arm_track(animation: Animation, index: int) -> bool:
	var bone: String = String(animation.track_get_path(index)).get_slice(":", 1)
	return bone == "arm-left" or bone == "arm-right"


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
	if _player == null or not _player.has_animation(&"sit"):
		return
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
	# Between carrying and bending to set down or pick up (FK-099), the arms
	# ease across instead of jumping (a crate in hand follows them).
	if PersonPresentation.CARRY_BLEND_CLIPS.has(_clip) and PersonPresentation.CARRY_BLEND_CLIPS.has(_requested_clip):
		_player.play(_requested_clip, PersonPresentation.CARRY_BLEND_SECONDS)
		_player.advance(0.0)
		_clip = _requested_clip
		return true
	_player.stop()
	# Holding and sitting only key part of the skeleton; clear the previous pose.
	_skeleton.reset_bone_poses()
	_player.play(_requested_clip)
	_player.advance(0.0)
	_clip = _requested_clip
	return true


func _clear_model() -> void:
	if _clipboard != null:
		_clipboard.visible = false
	for piece: Node3D in [_hat, _cap]:
		if piece != null:
			piece.visible = false
			if piece.get_parent() != self:
				piece.reparent(self, false)
	if _model != null:
		_model.get_parent().remove_child(_model)
		_model.free()
	_model = null
	_player = null
	_skeleton = null
	_model_name = &""
	_piece_key = &""
	_clip = &""
	_sit_lean_track = -1
	_sit_base_rotations.clear()


func _first_descendant(root: Node, type: String) -> Node:
	var matches: Array[Node] = root.find_children("*", type, true, false)
	return null if matches.is_empty() else matches[0]
