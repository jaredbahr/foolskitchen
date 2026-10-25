extends TestCase
## Queue/lifetime and mathematical framing checks never require a GPU.
## Actual wrapper thumbnails and their appearance are verified by scene captures.

class TimeoutCache extends ItemThumbnailCache:
	## Exercise the timeout branch without creating a viewport or GPU resource.
	func rendering_supported() -> bool:
		return true

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


func test_missing_post_draw_cancels_the_active_wrapper_and_remaining_queue_once() -> void:
	_cache.free()
	_cache = TimeoutCache.new()
	var scene: PackedScene = _wrapper()
	_cache.request(scene)
	_cache.request(_wrapper())
	_cache.set("_active_scene", scene)
	var active: PropView = PropView.new()
	var reference: WeakRef = weakref(active)
	_cache.set("_active", active)
	_cache.set("_wait_frames", ItemThumbnailCache.MAX_DRAW_WAIT_FRAMES - 1)
	_cache.call("_process", 0.0)
	assert_null(reference.get_ref(), "the timed-out wrapper is released")
	assert_eq(_cache.pending_count(), 0)
	assert_eq(_cache.cached_count(), 0)
	assert_true(_cache.last_error.contains("frame budget"))
	assert_false(_cache.is_processing())
	assert_eq(_cache.get_child_count(), 0, "this timeout fixture creates no graphics stage")
	assert_null(_cache.request(scene), "failed rendering never becomes a blind retry loop")
	assert_eq(_cache.pending_count(), 0)


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
