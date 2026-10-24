class_name CameraRig
extends Node3D
## Camera-only navigation over the XZ build plane. Keyboard/edge motion uses
## seconds; mouse drag uses its pixel displacement and must not multiply delta.

## Emitted once when the rotation target changes, before visual smoothing.
signal yaw_snapped(quarter: int)

@export_group("View")
@export var use_orthographic: bool = true
@export_range(10.0, 45.0, 1.0) var perspective_fov: float = 30.0
@export_range(20.0, 80.0, 0.1) var pitch_degrees: float = 54.7356
@export var initial_yaw_degrees: float = 45.0
@export var initial_focus: Vector2 = Vector2.ZERO
@export_range(1.0, 100.0, 0.5) var orbit_distance: float = 40.0

@export_group("Pan")
@export_range(0.0, 40.0, 0.1) var pan_speed: float = 8.0
## Centre of the pannable area on the world X/Z plane, in metres.
@export var pan_center: Vector2 = Vector2.ZERO
## Maximum focus distance from pan_center on the world X and Z axes, in metres.
@export var pan_limits: Vector2 = Vector2(12.0, 12.0)
@export var edge_pan_enabled: bool = true
@export_range(0.0, 100.0, 1.0) var edge_margin_pixels: float = 24.0
@export_range(0.1, 4.0, 0.1) var drag_sensitivity: float = 1.0

@export_group("Zoom and rotation")
## Zoom is the visible vertical span, in metres, at the focus distance.
@export var initial_zoom: float = 26.0
@export var minimum_zoom: float = 8.0
@export var maximum_zoom: float = 40.0
@export_range(0.1, 10.0, 0.1) var zoom_step: float = 2.0
@export_range(0.1, 30.0, 0.1) var zoom_response: float = 12.0
@export_range(0.1, 30.0, 0.1) var rotation_response: float = 10.0

@export_group("Test floor")
## The containing scene supplies its actual floor node. Exporting the material
## itself would duplicate a scene-local Resource across the rig scene boundary.
@export var grid_floor: MeshInstance3D:
	set(value):
		grid_floor = value
		_apply_grid()

## Always use the material rendered by this floor instance, never a copied one.
var grid_material: ShaderMaterial:
	get:
		if not is_instance_valid(grid_floor):
			return null
		return grid_floor.material_override as ShaderMaterial

var grid_visible: bool = true
var _grid_forced: bool = false
var _camera: Camera3D
var _yaw: float = 0.0
var _target_yaw: float = 0.0
var _zoom: float = 26.0
var _target_zoom: float = 26.0
var _dragging: bool = false
var _pointer_inside: bool = false
var _pointer_position_valid: bool = false
var _has_panned: bool = false
var _view_viewport: Viewport


func _enter_tree() -> void:
	_view_viewport = get_viewport()
	if not _view_viewport.size_changed.is_connected(_on_viewport_resized):
		_view_viewport.size_changed.connect(_on_viewport_resized)


func _exit_tree() -> void:
	if _view_viewport != null and _view_viewport.size_changed.is_connected(_on_viewport_resized):
		_view_viewport.size_changed.disconnect(_on_viewport_resized)
	_view_viewport = null
	_pointer_inside = false
	_pointer_position_valid = false
	_dragging = false


func _ready() -> void:
	reset_view()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_ENTER:
		_pointer_inside = true
		_pointer_position_valid = false
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		_pointer_inside = false
		_pointer_position_valid = false
		_dragging = false
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_pointer_position_valid = false
		_dragging = false


## Re-applies exported defaults. Also works on an instantiated, unparented rig.
func reset_view() -> void:
	var previous_target: float = _target_yaw
	_camera = get_node_or_null("Camera3D") as Camera3D
	_yaw = deg_to_rad(initial_yaw_degrees)
	_target_yaw = _yaw
	_zoom = _clamp_zoom(initial_zoom)
	_target_zoom = _zoom
	_has_panned = false
	_pointer_position_valid = false
	position = Vector3(initial_focus.x, 0.0, initial_focus.y)
	_clamp_focus()
	rotation.y = _yaw
	_apply_camera()
	_apply_grid()
	if not is_equal_approx(previous_target, _target_yaw):
		yaw_snapped.emit(camera_quarter())


func _process(delta: float) -> void:
	if not get_window().has_focus():
		_dragging = false
		_pointer_position_valid = false
		return
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_dragging = false
	var pan_input: Vector2 = Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	pan_input += _edge_pan_input(get_viewport().get_mouse_position(), get_viewport().get_visible_rect())
	step_view(delta, pan_input)


## Exponential response keeps rotation/zoom damping independent of frame rate.
## pan_input is screen-relative: right is +X and down is +Y.
func step_view(delta: float, pan_input: Vector2) -> void:
	if delta <= 0.0:
		return
	_yaw = lerpf(_yaw, _target_yaw, 1.0 - exp(-rotation_response * delta))
	_zoom = lerpf(_zoom, _target_zoom, 1.0 - exp(-zoom_response * delta))
	rotation.y = _yaw
	var input: Vector2 = pan_input.limit_length(1.0)
	var offset: Vector3 = Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y)
	var movement: Vector3 = offset * pan_speed * delta
	var previous_focus: Vector3 = position
	position += movement
	_clamp_focus()
	if not movement.is_zero_approx() and not position.is_equal_approx(previous_focus):
		_has_panned = true
	_apply_camera()


func rotate_quarter(turns: int) -> void:
	if turns == 0:
		return
	# Keep an unwrapped target so quick repeated presses retain their direction.
	_target_yaw += float(turns) * PI / 2.0
	yaw_snapped.emit(camera_quarter())


## Absolute camera quarter: 0 is 45 degrees, followed by 135, 225 and 315.
func camera_quarter() -> int:
	return posmod(roundi((_target_yaw - PI / 4.0) / (PI / 2.0)), 4)


## Positive steps zoom out. Only the target changes; step_view smooths the view.
func zoom_steps(steps: float) -> void:
	_target_zoom = _clamp_zoom(_target_zoom + steps * zoom_step)


## A middle-mouse grab translates screen pixels to ground-plane metres.
func pan_by_drag(relative: Vector2, viewport_height: float) -> void:
	if viewport_height <= 0.0:
		return
	var metres_per_pixel: float = _zoom / viewport_height * drag_sensitivity
	var pitch: float = deg_to_rad(clampf(pitch_degrees, 20.0, 80.0))
	var offset: Vector3 = Vector3(-relative.x, 0.0, -relative.y / sin(pitch)) * metres_per_pixel
	var movement: Vector3 = Basis(Vector3.UP, _yaw) * offset
	var previous_focus: Vector3 = position
	position += movement
	_clamp_focus()
	if not movement.is_zero_approx() and not position.is_equal_approx(previous_focus):
		_has_panned = true


## A browser can announce mouse entry before supplying a pointer position.
## Never treat its default/stale corner coordinate as the player's first pan.
func _edge_pan_input(mouse: Vector2, viewport_rect: Rect2) -> Vector2:
	if not _pointer_inside or not _pointer_position_valid or _dragging:
		return Vector2.ZERO
	return edge_pan_direction(mouse, viewport_rect)


## Keep the supplied floor focus through startup/canvas resizes until the player
## translates the view. Resize must not reset their rotation, zoom or grid.
func _on_viewport_resized() -> void:
	_pointer_position_valid = false
	if _view_viewport == null or not _view_viewport.get_visible_rect().has_area():
		return
	if not _has_panned:
		position = Vector3(initial_focus.x, 0.0, initial_focus.y)
		_clamp_focus()
	_apply_camera()


func edge_pan_direction(mouse: Vector2, viewport_rect: Rect2) -> Vector2:
	if not edge_pan_enabled or edge_margin_pixels <= 0.0 or not viewport_rect.has_point(mouse):
		return Vector2.ZERO
	var point: Vector2 = mouse - viewport_rect.position
	var margin: float = minf(edge_margin_pixels, minf(viewport_rect.size.x, viewport_rect.size.y) / 2.0)
	var direction: Vector2 = Vector2.ZERO
	if point.x < margin:
		direction.x = -1.0
	elif point.x > viewport_rect.size.x - margin:
		direction.x = 1.0
	if point.y < margin:
		direction.y = -1.0
	elif point.y > viewport_rect.size.y - margin:
		direction.y = 1.0
	return direction.limit_length(1.0)


func toggle_grid() -> bool:
	if not _grid_forced:
		grid_visible = not grid_visible
	_apply_grid()
	return grid_visible


## Build mode temporarily forces the rendered grid without changing the G
## preference. Replacing the floor or resetting the camera preserves both.
func set_grid_forced(value: bool) -> void:
	if _grid_forced == value:
		return
	_grid_forced = value
	_apply_grid()


func is_grid_forced() -> bool:
	return _grid_forced


func effective_grid_visible() -> bool:
	return grid_visible or _grid_forced


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if not key.pressed or key.echo:
			return
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		match code:
			KEY_Q:
				rotate_quarter(-1)
			KEY_E:
				rotate_quarter(1)
			KEY_G:
				toggle_grid()
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_steps(-button.factor)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_steps(button.factor)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_pointer_inside = get_viewport().get_visible_rect().has_point(motion.position)
		if not _pointer_inside:
			_pointer_position_valid = false
		elif not motion.relative.is_zero_approx():
			_pointer_position_valid = true
		if _dragging:
			pan_by_drag(motion.relative, get_viewport().get_visible_rect().size.y)


func _clamp_zoom(value: float) -> float:
	return clampf(value, maxf(0.1, minimum_zoom), maxf(maximum_zoom, maxf(0.1, minimum_zoom)))


func _clamp_focus() -> void:
	position.x = clampf(position.x, pan_center.x - absf(pan_limits.x), pan_center.x + absf(pan_limits.x))
	position.z = clampf(position.z, pan_center.y - absf(pan_limits.y), pan_center.y + absf(pan_limits.y))
	position.y = 0.0


func _apply_camera() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if use_orthographic else Camera3D.PROJECTION_PERSPECTIVE
	_camera.size = _zoom
	_camera.fov = clampf(perspective_fov, 10.0, 45.0)
	var distance: float = orbit_distance if use_orthographic else _zoom / (2.0 * tan(deg_to_rad(_camera.fov) / 2.0))
	var pitch: float = deg_to_rad(clampf(pitch_degrees, 20.0, 80.0))
	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * distance
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)


func _apply_grid() -> void:
	var material: ShaderMaterial = grid_material
	if material != null:
		material.set_shader_parameter("grid_visible", effective_grid_visible())
