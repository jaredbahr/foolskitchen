class_name ItemThumbnailCache
extends Node
## One private, bounded render stage. Each unchanged wrapper is drawn once,
## copied to an ImageTexture after frame_post_draw, then removed from the stage.
## Headless tests retain queue contracts without creating rendering resources.

signal thumbnail_ready(scene: PackedScene, texture: Texture2D)

const IMAGE_SIZE: Vector2i = Vector2i(96, 96)
const MAX_DRAW_WAIT_FRAMES: int = 30
const VIEW_SCENE_PATH: String = "res://src/world/shop_view.tscn"

var _textures: Dictionary[int, Texture2D] = {}
var _scenes: Dictionary[int, PackedScene] = {}
var _queued: Dictionary[int, bool] = {}
var _failed: Dictionary[int, bool] = {}
var _queue: Array[PackedScene] = []
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _active: PropView
var _active_scene: PackedScene
var _wait_frames: int = 0
var _render_unavailable: bool = false
var last_error: String = ""


func _ready() -> void:
	set_process(rendering_supported() and not _queue.is_empty())


## Native callers receive the same cached texture for the same PackedScene.
## Holding the scene also prevents an instance ID from being reused mid-cache.
func request(scene: PackedScene) -> Texture2D:
	if scene == null:
		return null
	var key: int = scene.get_instance_id()
	if _textures.has(key):
		return _textures[key]
	if _queued.has(key) or _failed.has(key) or _render_unavailable:
		return null
	_scenes[key] = scene
	_queued[key] = true
	_queue.append(scene)
	if is_inside_tree() and rendering_supported():
		set_process(true)
	return null


func pending_count() -> int:
	return _queued.size()


func cached_count() -> int:
	return _textures.size()


func rendering_supported() -> bool:
	return DisplayServer.get_name() != "headless"


func _process(_delta: float) -> void:
	if not rendering_supported() or _render_unavailable:
		set_process(false)
		return
	if _active_scene != null:
		_wait_frames += 1
		if _wait_frames >= MAX_DRAW_WAIT_FRAMES:
			# A slow wrapper falls back to its text card; later scenes still render.
			_fail_active("Thumbnail rendering did not finish within its frame budget")
			set_process(not _queue.is_empty())
		return
	if _queue.is_empty():
		set_process(false)
		return
	if not _ensure_stage():
		last_error = "The shared shop lighting is unavailable for thumbnails"
		_render_unavailable = true
		_queue.clear()
		_queued.clear()
		set_process(false)
		return
	_start_next()


func _ensure_stage() -> bool:
	if _viewport != null:
		return true
	# Reuse the approved scene's actual environment and light nodes. Never
	# instantiate it in a tree: the shop's gameplay/view bindings do not run.
	var source_scene: PackedScene = load(VIEW_SCENE_PATH) as PackedScene
	if source_scene == null:
		return false
	var source: Node = source_scene.instantiate()
	var warm: WorldEnvironment = source.get_node_or_null("Environment") as WorldEnvironment
	var key: DirectionalLight3D = source.get_node_or_null("KeyLight") as DirectionalLight3D
	var fill: DirectionalLight3D = source.get_node_or_null("FillLight") as DirectionalLight3D
	if warm == null or warm.environment == null or key == null or fill == null:
		source.free()
		return false
	_viewport = SubViewport.new()
	_viewport.name = "ThumbnailViewport"
	_viewport.size = IMAGE_SIZE
	_viewport.transparent_bg = true
	_viewport.world_3d = World3D.new()
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = warm.environment.duplicate() as Environment
	# Transparency is a viewport concern; ambient light and tone mapping stay
	# exactly as authored in ShopView, without baking its brown background.
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	_stage.add_child(environment)
	_stage.add_child(key.duplicate())
	_stage.add_child(fill.duplicate())
	source.free()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_stage.add_child(_camera)
	_camera.current = true
	return true


func _start_next() -> void:
	_active_scene = _queue.pop_front()
	var instance: Node = _active_scene.instantiate()
	_active = instance as PropView
	if _active == null:
		instance.free()
		_fail_active("The item has no supported wrapper scene")
		return
	_stage.add_child(_active)
	_active.prepare()
	var frame: Dictionary = framing_for(_active.get_combined_aabb(), IMAGE_SIZE)
	if frame.is_empty():
		_fail_active("The item wrapper has no finite visible bounds")
		return
	_camera.transform = frame["transform"]
	_camera.size = float(frame["size"])
	_camera.near = float(frame["near"])
	_camera.far = float(frame["far"])
	_wait_frames = 0
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_frame_post_draw() -> void:
	if _active_scene == null or not is_inside_tree() or _viewport == null:
		return
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail_active("The thumbnail viewport returned no image")
		return
	var scene: PackedScene = _active_scene
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_textures[scene.get_instance_id()] = texture
	_cancel_active()
	thumbnail_ready.emit(scene, texture)


func _fail_active(reason: String) -> void:
	last_error = reason
	if _active_scene != null:
		_failed[_active_scene.get_instance_id()] = true
	_cancel_active()


func _cancel_active() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	if _active_scene != null:
		_queued.erase(_active_scene.get_instance_id())
	if is_instance_valid(_active):
		_active.free()
	_active = null
	_active_scene = null
	_wait_frames = 0
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Exiting cancels the server callback before freeing its private world.
func _exit_tree() -> void:
	_cancel_active()
	_queue.clear()
	_queued.clear()
	_textures.clear()
	_scenes.clear()
	_failed.clear()
	if is_instance_valid(_viewport):
		_viewport.free()
	_viewport = null
	_stage = null
	_camera = null
	set_process(false)


## Pure orthographic framing of every transformed AABB corner, with a margin.
## Bounds come from the real uniformly scaled wrapper, never guessed geometry.
static func framing_for(bounds: AABB, image_size: Vector2i = IMAGE_SIZE) -> Dictionary:
	if image_size.x < 1 or image_size.y < 1 or not bounds.position.is_finite() \
			or not bounds.size.is_finite() or bounds.size.x <= 0.0 \
			or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return {}
	var centre: Vector3 = bounds.get_center()
	var direction: Vector3 = Vector3(1.0, 0.8, 1.0).normalized()
	var distance: float = bounds.size.length() * 2.0 + 1.0
	var camera_transform: Transform3D = Transform3D(Basis.looking_at(-direction), centre + direction * distance)
	var inverse: Transform3D = camera_transform.affine_inverse()
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	for index: int in range(8):
		var corner: Vector3 = bounds.position + Vector3(
			bounds.size.x if (index & 1) != 0 else 0.0,
			bounds.size.y if (index & 2) != 0 else 0.0,
			bounds.size.z if (index & 4) != 0 else 0.0)
		var projected: Vector3 = inverse * corner
		minimum = minimum.min(Vector2(projected.x, projected.y))
		maximum = maximum.max(Vector2(projected.x, projected.y))
	var span: Vector2 = maximum - minimum
	var aspect: float = float(image_size.x) / float(image_size.y)
	return {"transform": camera_transform, "size": maxf(span.y, span.x / aspect) * 1.15,
		"near": 0.01, "far": distance + bounds.size.length() + 1.0}
