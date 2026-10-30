extends TestCase
## Queue/lifetime and mathematical framing checks never require a GPU.
## Actual wrapper thumbnails and their appearance are verified by scene captures.

class TimeoutCache extends ItemThumbnailCache:
	## Exercise the timeout branch without creating a viewport or GPU resource.
	var completed_scenes: Array[PackedScene] = []
	var successful_texture: Texture2D

	func rendering_supported() -> bool:
		return true

	func _ensure_stage() -> bool:
		return true

	## Simulate one later scene completing its draw callback without graphics.
	func _start_next() -> void:
		if _queue.is_empty():
			return
		_active_request = _queue.pop_front()
		_active_scene = _active_request.scene
		var scene: PackedScene = _active_scene
		successful_texture = GradientTexture2D.new()
		_textures[_active_request.key] = successful_texture
		completed_scenes.append(scene)
		_cancel_active()
		thumbnail_ready.emit(scene, successful_texture)

var _cache: ItemThumbnailCache


func before_each() -> void:
	_cache = ItemThumbnailCache.new()


func after_each() -> void:
	if is_instance_valid(_cache):
		_cache.free()
	_cache = null


func test_queue_is_unique_per_unchanged_scene_and_null_has_no_placeholder() -> void:
	var first: PackedScene = _wrapper()
	var second: PackedScene = _wrapper()
	assert_null(_cache.request(null))
	assert_eq(_cache.pending_count(), 0)
	for index: int in range(4):
		assert_null(_cache.request(first))
	assert_eq(_cache.pending_count(), 1)
	assert_null(_cache.request(second))
	assert_eq(_cache.pending_count(), 2, "distinct PackedScenes cannot share an unrelated preview")
	assert_eq(_cache.cached_count(), 0, "queueing never fabricates a texture")
	assert_eq(_cache.get_child_count(), 0, "an off-tree request does not create a viewport")


func test_headless_mount_keeps_queue_without_starting_graphics_and_exit_cancels_it() -> void:
	if DisplayServer.get_name() != "headless":
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_cache.request(_wrapper())
	tree.root.add_child(_cache)
	for frame: int in range(3):
		await tree.process_frame
	assert_eq(_cache.pending_count(), 1)
	assert_eq(_cache.cached_count(), 0)
	assert_false(_cache.is_processing())
	assert_eq(_cache.get_child_count(), 0, "headless mode creates no render world or viewport")
	assert_false(RenderingServer.frame_post_draw.is_connected(Callable(_cache, "_on_frame_post_draw")))
	tree.root.remove_child(_cache)
	assert_eq(_cache.pending_count(), 0)
	assert_eq(_cache.cached_count(), 0)
	assert_eq(_cache.get_child_count(), 0)
	assert_false(RenderingServer.frame_post_draw.is_connected(Callable(_cache, "_on_frame_post_draw")))


func test_missing_post_draw_fails_only_active_item_then_next_scene_completes() -> void:
	_cache.free()
	_cache = TimeoutCache.new()
	var timeout_cache: TimeoutCache = _cache as TimeoutCache
	var slow_scene: PackedScene = _wrapper()
	var later_scene: PackedScene = _wrapper()
	_cache.request(slow_scene)
	_cache.request(later_scene)
	timeout_cache._active_request = timeout_cache._queue.pop_front()
	assert_eq(timeout_cache._active_request.scene, slow_scene,
		"starting the slow scene removes it from the pending queue")
	_cache.set("_active_scene", slow_scene)
	var active: PropView = PropView.new()
	var reference: WeakRef = weakref(active)
	_cache.set("_active", active)
	_cache.set("_wait_frames", ItemThumbnailCache.MAX_DRAW_WAIT_FRAMES - 1)
	_cache.call("_process", 0.0)
	assert_null(reference.get_ref(), "the timed-out wrapper is released")
	assert_eq(_cache.pending_count(), 1, "the unrelated queued scene remains available")
	assert_eq(_cache.cached_count(), 0)
	assert_true(_cache.last_error.contains("frame budget"))
	assert_false(_cache.get("_render_unavailable"), "one slow scene does not disable rendering")
	assert_true(_cache.is_processing(), "the remaining queue continues")
	assert_eq(_cache.get_child_count(), 0, "this timeout fixture creates no graphics stage")
	assert_null(_cache.request(slow_scene), "the slow item cannot become a retry loop")
	assert_eq(_cache.pending_count(), 1)
	_cache.call("_process", 0.0)
	assert_eq(timeout_cache.completed_scenes, [later_scene], "the next item completes after the timeout")
	assert_eq(_cache.cached_count(), 1)
	assert_eq(_cache.request(later_scene), timeout_cache.successful_texture,
		"a successful later thumbnail remains cached")
	assert_eq(_cache.pending_count(), 0)
	_cache.call("_process", 0.0)
	assert_false(_cache.is_processing(), "processing stops when the queue completes")


func test_orthographic_frame_encloses_every_corner_of_wide_tall_and_offset_wrappers() -> void:
	for bounds: AABB in [
		AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.7, 1.0)),
		AABB(Vector3(-1.5, 0.0, -0.1), Vector3(3.0, 0.01, 0.2)),
		AABB(Vector3(0.6, 0.0, -2.0), Vector3(0.2, 2.5, 0.8)),
	]:
		for image_size: Vector2i in [Vector2i(96, 96), Vector2i(128, 72)]:
			var original: AABB = bounds
			var frame: Dictionary = ItemThumbnailCache.framing_for(bounds, image_size)
			assert_false(frame.is_empty())
			if frame.is_empty():
				continue
			var transform: Transform3D = frame["transform"]
			var inverse: Transform3D = transform.affine_inverse()
			var half_height: float = float(frame["size"]) * 0.5
			var half_width: float = half_height * float(image_size.x) / float(image_size.y)
			for index: int in range(8):
				var corner: Vector3 = bounds.position + Vector3(
					bounds.size.x if (index & 1) != 0 else 0.0,
					bounds.size.y if (index & 2) != 0 else 0.0,
					bounds.size.z if (index & 4) != 0 else 0.0)
				var projected: Vector3 = inverse * corner
				assert_true(absf(projected.x) < half_width)
				assert_true(absf(projected.y) < half_height)
				assert_true(-projected.z > float(frame["near"]))
				assert_true(-projected.z < float(frame["far"]))
			assert_eq(bounds, original, "framing never moves the actual item")
			assert_almost_eq(transform.basis.determinant(), 1.0, 0.0001, "camera framing never stretches the wrapper")


func test_empty_nonfinite_bounds_and_invalid_target_sizes_have_no_frame() -> void:
	assert_true(ItemThumbnailCache.framing_for(AABB()).is_empty())
	assert_true(ItemThumbnailCache.framing_for(AABB(Vector3.ZERO, Vector3(-1.0, 1.0, 1.0))).is_empty())
	assert_true(ItemThumbnailCache.framing_for(AABB(Vector3(INF, 0.0, 0.0), Vector3.ONE)).is_empty())
	assert_true(ItemThumbnailCache.framing_for(AABB(Vector3.ZERO, Vector3.ONE), Vector2i.ZERO).is_empty())


func _wrapper() -> PackedScene:
	var wrapper: PropView = PropView.new()
	var part: Node3D = Node3D.new()
	part.name = "Part"
	wrapper.add_child(part)
	part.owner = wrapper
	var art: Node3D = Node3D.new()
	art.name = "Art"
	part.add_child(art)
	art.owner = wrapper
	var model: MeshInstance3D = MeshInstance3D.new()
	model.mesh = BoxMesh.new()
	art.add_child(model)
	model.owner = wrapper
	var packed: PackedScene = PackedScene.new()
	assert_eq(packed.pack(wrapper), OK)
	wrapper.free()
	return packed


func test_variants_of_one_wrapper_have_independent_bounded_queue_entries() -> void:
	var scene: PackedScene = load("res://assets/props/diner_stool.tscn") as PackedScene
	var red: ItemVariant = load("res://data/variants/stool_chrome_red.tres") as ItemVariant
	var teal: ItemVariant = load("res://data/variants/stool_chrome_teal.tres") as ItemVariant
	assert_null(_cache.request(scene, red))
	assert_null(_cache.request(scene, teal))
	assert_null(_cache.request(scene, red))
	assert_eq(_cache.pending_count(), 2)
	assert_ne(_cache._queue[0].key, _cache._queue[1].key)


func test_capture_reads_only_selected_look_without_queuing() -> void:
	var capture: GDScript = load("res://tools/screenshot.gd")
	var definition: ItemDef = load("res://data/items/diner_stool.tres")
	var cache: ItemThumbnailCache = ItemThumbnailCache.new()
	var first: ItemThumbnailCache.Request = ItemThumbnailCache.Request.new(definition.view_scene, definition.variants[0])
	var second: ItemThumbnailCache.Request = ItemThumbnailCache.Request.new(definition.view_scene, definition.variants[1])
	var image: Image = Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	cache._textures[first.key] = texture
	cache._scenes[first.key] = first
	assert_eq(capture.catalogue_cached_thumbnail(cache, definition), texture)
	assert_null(capture.catalogue_cached_thumbnail(cache, definition, definition.variants[1].id))
	assert_eq(cache.pending_count(), 0, "capture must not repair missing selected-look renders")
	cache._textures[second.key] = texture
	cache._scenes[second.key] = second
	assert_eq(capture.catalogue_cached_thumbnail(cache, definition, definition.variants[1].id), texture)
	var evidence: Dictionary = capture.catalogue_cached_evidence(cache)
	assert_true(evidence.valid)
	assert_eq(evidence.scenes, [definition.view_scene.resource_path], "two looks still cover one wrapper")
	cache._textures[second.key] = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	assert_false(capture.catalogue_cached_evidence(cache).valid, "wrong render dimensions fail")
	cache._textures[second.key] = texture
	cache._scenes[second.key] = first
	assert_false(capture.catalogue_cached_evidence(cache).valid, "mismatched look identity fails")
	cache._scenes.erase(second.key)
	assert_false(capture.catalogue_cached_evidence(cache).valid, "missing source identity fails")
	cache.free()
