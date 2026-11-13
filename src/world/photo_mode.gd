class_name PhotoMode
extends Node
## Desktop viewport capture and temporary presentation state for the live shop.

const DIRECTORY: String = "user://photos"

@onready var _hud: CanvasLayer = $"../HUD"
@onready var _overlay: CanvasLayer = $"../Overlay"
@onready var _camera: CameraRig = $"../CameraRig"
@onready var _debug: Node3D = $"../DebugGeometry"
@onready var _preview: Node3D = $"../BuildPreview"
@onready var _toast: PanelContainer = $"../Overlay/PhotoToast"
@onready var _notice: Label = $"../Overlay/PhotoToast/Row/Notice"
@onready var _folder: Button = $"../Overlay/PhotoToast/Row/OpenFolder"
@onready var _timer: Timer = $"../Overlay/PhotoToast/Timer"

var held: bool = false
var _pending_path: String = ""
var _last_photo: String = ""
var _pending_notice: bool = false
var _hud_visible: bool
var _overlay_visible: bool
var _debug_visible: bool
var _preview_visible: bool


static func available(is_web: bool = OS.has_feature("web")) -> bool:
	return not is_web


static func file_name(day: int, minute: int) -> String:
	return "fools_kitchen_%d_%02d%02d.png" % [day, floori(minute / 60.0), minute % 60]


func _ready() -> void:
	_folder.pressed.connect(_open_folder)
	_timer.timeout.connect(_toast.hide)


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_capture_frame):
		RenderingServer.frame_post_draw.disconnect(_capture_frame)


func capture_pending() -> bool:
	return not _pending_path.is_empty()


func toggle_held() -> void:
	if held:
		leave()
	else:
		if not capture_pending():
			_hide_presentation()
		held = true


func leave() -> void:
	if not held:
		return
	held = false
	if not capture_pending():
		_restore_presentation()
		if _pending_notice:
			_show_notice()


func capture(day: int, minute: int) -> void:
	if capture_pending() or DisplayServer.get_name() == "headless":
		return
	_pending_path = DIRECTORY.path_join(file_name(day, minute))
	if not held:
		_hide_presentation()
	RenderingServer.frame_post_draw.connect(_capture_frame, CONNECT_ONE_SHOT)


func _hide_presentation() -> void:
	_hud_visible = _hud.visible
	_overlay_visible = _overlay.visible
	_debug_visible = _debug.visible
	_preview_visible = _preview.visible
	_hud.hide()
	_overlay.hide()
	_debug.hide()
	_preview.hide()
	_camera.set_photo_mode(true)


func _restore_presentation() -> void:
	_hud.visible = _hud_visible
	_overlay.visible = _overlay_visible
	_debug.visible = _debug_visible
	_preview.visible = _preview_visible
	_camera.set_photo_mode(false)


func _capture_frame() -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _pending_path
	_pending_path = ""
	if not held:
		_restore_presentation()
	_last_photo = _save(image, path)
	_pending_notice = true
	if not held:
		_show_notice()


func _save(image: Image, path: String) -> String:
	if image == null or image.is_empty() or FileAccess.file_exists(DIRECTORY):
		return ""
	if DirAccess.make_dir_recursive_absolute(DIRECTORY) != OK:
		return ""
	var next_path: String = path
	var number: int = 2
	while FileAccess.file_exists(next_path):
		next_path = "%s_%d.png" % [path.get_basename(), number]
		number += 1
	return next_path if image.save_png(next_path) == OK else ""


func _show_notice() -> void:
	_pending_notice = false
	_folder.visible = not _last_photo.is_empty()
	_notice.text = "Photo saved to photos/%s" % _last_photo.get_file() if _folder.visible else "Couldn't save the photo"
	_toast.show()
	_timer.start()


func _open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(DIRECTORY))
