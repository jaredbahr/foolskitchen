class_name OwnerCharacterPreview
extends SubViewportContainer
## An isolated, live Mini Character preview. It never owns a sim or RNG.

var _models: Array[StringName] = []
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _people: Array[PersonView] = []


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(_fit_camera):
		resized.connect(_fit_camera)
	_build_stage()


func set_models(models: Array[StringName]) -> void:
	if models == _models:
		return
	_models.assign(models)
	if is_inside_tree():
		_build_stage()


func models() -> Array[StringName]:
	return _models.duplicate()


func live_model_count() -> int:
	return _people.size()


func _build_stage() -> void:
	# Headless UI tests exercise choices without allocating native render state.
	if DisplayServer.get_name() == "headless":
		return
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "CharacterViewport"
		_viewport.transparent_bg = true
		_viewport.world_3d = World3D.new()
		_viewport.gui_disable_input = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(_viewport)
		_stage = Node3D.new()
		_viewport.add_child(_stage)
		var lighting: Node3D = ItemThumbnailCache.create_preview_lighting()
		if lighting == null:
			push_error("Owner previews need the shared shop lighting")
			return
		_stage.add_child(lighting)
		_camera = Camera3D.new()
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_stage.add_child(_camera)
		_camera.position = Vector3(0.0, 0.55, 4.0)
		_camera.look_at(Vector3(0.0, 0.42, 0.0))
		_camera.current = true
	for person: PersonView in _people:
		person.free()
	_people.clear()
	var packed: PackedScene = load("res://assets/people/person.tscn") as PackedScene
	for index: int in _models.size():
		var person: PersonView = packed.instantiate() as PersonView
		person.owner_model = _models[index]
		person.set_look(&"owner")
		person.position.x = (float(index) - float(_models.size() - 1) * 0.5) * 0.8
		_stage.add_child(person)
		if person.model_name() != _models[index]:
			push_error("Owner previews need the approved Mini Character model")
		person.face_direction(Vector3.BACK)
		person.set_pose(false, false, false, false)
		_people.append(person)
	_fit_camera()


func _fit_camera() -> void:
	if _viewport == null or _camera == null:
		return
	var width: float = maxf(0.8, float(_models.size()) * 0.8)
	# SubViewportContainer owns the viewport size while stretch is enabled.
	_camera.size = maxf(1.05, width * maxf(size.y, 1.0) / maxf(size.x, 1.0))
