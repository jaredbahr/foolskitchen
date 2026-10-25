extends TestCase
## Focused read-only capture identity tests using private user:// files.

const VALIDATOR: Script = preload("res://tools/diner_capture_validator.gd")
const PROVENANCE: String = "native Mini head-mesh POSITION/JOINTS/WEIGHTS, imported Skin inverse binds, current Skeleton3D global poses, actual node transforms"

var _fixture_directory: String


func before_each() -> void:
	_fixture_directory = SaveTestPaths.case_dir(OS.get_process_id(), "diner_capture_validator")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_fixture_directory))
	_write_pair(12)
	_write_pair(90)


func after_each() -> void:
	for frame: int in [12, 90]:
		for suffix: String in ["png", "json"]:
			var path: String = _fixture_directory.path_join("shot_%04d.%s" % [frame, suffix])
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for suffix: String in ["png", "json"]:
		var crop_path: String = _fixture_directory.path_join("shot_0090_booth_3x.%s" % suffix)
		if FileAccess.file_exists(crop_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(crop_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fixture_directory))


func test_accepts_both_actual_png_metadata_identity_pairs_in_private_fixture_dir() -> void:
	var result: Dictionary = VALIDATOR.validate_capture_directory(_fixture_directory)
	assert_true(result["valid"], str(result["messages"]))
	assert_eq(result["messages"].size(), 3)


func test_json_round_trip_numeric_fields_remain_valid_integer_identities() -> void:
	var metadata: Dictionary = _read_metadata(12)
	assert_true(typeof(metadata["width"]) in [TYPE_INT, TYPE_FLOAT])
	assert_true(typeof(metadata["frame"]) in [TYPE_INT, TYPE_FLOAT])
	assert_true(typeof(metadata["engine_errors"]) in [TYPE_INT, TYPE_FLOAT])
	var result: Dictionary = VALIDATOR.validate_capture_pair(_fixture_directory, 12)
	assert_true(result["valid"], str(result["messages"]))


func test_missing_image_or_metadata_fails_closed() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fixture_directory.path_join("shot_0090.json")))
	var result: Dictionary = VALIDATOR.validate_capture_directory(_fixture_directory)
	assert_false(result["valid"])
	assert_true(_messages_contain(result["messages"], "missing metadata"))


func test_corrupt_png_fails_before_accepting_its_metadata() -> void:
	var png_path: String = _fixture_directory.path_join("shot_0012.png")
	var file: FileAccess = FileAccess.open(png_path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([0, 1, 2, 3]))
	file.close()
	var result: Dictionary = VALIDATOR.validate_capture_pair(_fixture_directory, 12)
	assert_false(result["valid"])
	assert_true(_messages_contain(result["messages"], "corrupt PNG"))


func test_metadata_digest_frame_and_identity_mismatches_fail_closed() -> void:
	var metadata: Dictionary = _read_metadata(12)
	metadata["image_sha256"] = "wrong-digest"
	metadata["frame"] = 90
	metadata["diner_review"]["state"]["frame"] = 90
	_write_metadata(12, metadata)
	var result: Dictionary = VALIDATOR.validate_capture_pair(_fixture_directory, 12)
	assert_false(result["valid"])
	assert_true(_messages_contain(result["messages"], "digest mismatch"))
	assert_true(_messages_contain(result["messages"], "frame identity"))


func test_non_diner_capture_pair_is_rejected() -> void:
	var metadata: Dictionary = _read_metadata(90)
	metadata.erase("diner_review")
	metadata["scene"] = "res://src/world/shop.tscn"
	_write_metadata(90, metadata)
	var result: Dictionary = VALIDATOR.validate_capture_pair(_fixture_directory, 90)
	assert_false(result["valid"])
	assert_true(_messages_contain(result["messages"], "wrong image source"))
	assert_true(_messages_contain(result["messages"], "GDScript-validated frame identity"))


func test_seated_crop_pixels_must_match_the_exact_nearest_source_derivative() -> void:
	var crop_path: String = _fixture_directory.path_join("shot_0090_booth_3x.png")
	var crop: Image = Image.load_from_file(crop_path)
	crop.set_pixel(0, 0, Color.BLACK)
	assert_eq(crop.save_png(crop_path), OK)
	var descriptor: Dictionary = _crop_descriptor()
	descriptor["image_sha256"] = FileAccess.get_sha256(crop_path)
	_write_crop_descriptor(descriptor)
	var metadata: Dictionary = _read_metadata(90)
	metadata["diner_review"]["booth_crop"] = descriptor
	_write_metadata(90, metadata)
	var result: Dictionary = VALIDATOR.validate_capture_pair(_fixture_directory, 90)
	assert_false(result["valid"])
	assert_true(_messages_contain(result["messages"], "not the exact 3x nearest source crop"))


func test_crop_measurement_must_remain_bound_to_the_current_booth_guest() -> void:
	var descriptor: Dictionary = _crop_descriptor()
	descriptor["measurement"]["seated_head_clearance"] = 0.04
	_write_crop_descriptor(descriptor)
	var metadata: Dictionary = _read_metadata(90)
	metadata["diner_review"]["booth_crop"] = descriptor
	_write_metadata(90, metadata)
	var result: Dictionary = VALIDATOR.validate_capture_pair(_fixture_directory, 90)
	assert_false(result["valid"])
	assert_true(_messages_contain(result["messages"], "not the lowest-screen booth guest"))


func test_crop_scale_rejects_fractional_boolean_and_out_of_range_values_after_json_round_trip() -> void:
	var baseline: Dictionary = _crop_descriptor()
	for invalid_scale: Variant in [3.5, true, 0, 4]:
		var descriptor: Dictionary = baseline.duplicate(true)
		descriptor["scale"] = invalid_scale
		_write_crop_descriptor(descriptor)
		var metadata: Dictionary = _read_metadata(90)
		metadata["diner_review"]["booth_crop"] = descriptor
		_write_metadata(90, metadata)
		var result: Dictionary = VALIDATOR.validate_capture_pair(_fixture_directory, 90)
		assert_false(result["valid"], str(invalid_scale))
		assert_true(_messages_contain(result["messages"], "metadata identity, size or digest mismatch"), str(invalid_scale))


func _write_pair(frame: int) -> void:
	var image: Image = Image.create(1600, 900, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var png_path: String = _fixture_directory.path_join("shot_%04d.png" % frame)
	assert_eq(image.save_png(png_path), OK)
	var review: Dictionary = {"state": {"frame": frame}}
	if frame == 90:
		var measurement: Dictionary = {"guest_id": 7, "furnishing_id": 20, "table_item_id": 30,
			"head_world_bounds": {"min": [0.1, 0.9, 0.2], "max": [0.3, 1.1, 0.4]},
			"head_screen_bounds": {"x": 100.0, "y": 90.0, "width": 20.0, "height": 26.0},
			"seated_head_clearance": 0.03, "intersecting_triangles": 0,
			"head_center_inside_seat": false, "backrest_at_head_height": true, "head_vertices": 24,
			"measurement_provenance": PROVENANCE}
		var actor: Dictionary = {"id": 7, "role": "customer", "furnishing_definition": "diner_booth",
			"furnishing": 20, "table": 30, "linked_table": 30, "reservation": 7,
			"seated": true, "visible": true, "clip": "sit", "player_clip": "sit",
			"seat_clearance": measurement}
		var state: Dictionary = {"frame": 90, "actors": [actor], "items": [
			{"id": 20, "definition": "diner_booth", "prop": {"bounds": {"rect": [80.0, 80.0, 80.0, 120.0]}}},
			{"id": 30, "definition": "table_2", "prop": {"bounds": {"rect": [130.0, 130.0, 100.0, 80.0]}}}]}
		review["state"] = state
		var descriptor: Dictionary = _write_crop(image, measurement)
		review["booth_crop"] = descriptor
	_write_metadata(frame, {"image_file": "shot_%04d.png" % frame,
		"image_sha256": FileAccess.get_sha256(png_path), "scene": "res://src/world/main.tscn",
		"capture_timing": "frame_post_draw", "width": 1600, "height": 900, "frame": frame,
		"engine_errors": 0, "video_adapter": "Mesa llvmpipe (LLVM)",
		"diner_review": review})


func _write_crop(source: Image, measurement: Dictionary) -> Dictionary:
	var source_rect: Array[int] = [68, 68, 174, 154]
	var crop: Image = source.get_region(Rect2i(source_rect[0], source_rect[1], source_rect[2], source_rect[3]))
	crop.resize(source_rect[2] * 3, source_rect[3] * 3, Image.INTERPOLATE_NEAREST)
	var crop_path: String = _fixture_directory.path_join("shot_0090_booth_3x.png")
	assert_eq(crop.save_png(crop_path), OK)
	var descriptor: Dictionary = {"error": "", "guest_id": 7, "furnishing_id": 20, "table_item_id": 30,
		"source_rect": source_rect, "measurement": measurement.duplicate(true), "kind": "source_pixel_derivative",
		"source_image_file": "shot_0090.png", "source_image_sha256": FileAccess.get_sha256(_fixture_directory.path_join("shot_0090.png")),
		"source_frame": 90, "scale": 3, "interpolation": "nearest", "image_file": "shot_0090_booth_3x.png",
		"image_sha256": FileAccess.get_sha256(crop_path), "width": crop.get_width(), "height": crop.get_height(),
		"notice": "Exact 3x nearest-neighbour crop of paused, unsaved frame 90; no new scene or rendered frame.",
		"fixture_notice": "Diner review fixture - unsaved; wall pieces are view-only staging, not player wall placement."}
	_write_crop_descriptor(descriptor)
	return descriptor


func _crop_descriptor() -> Dictionary:
	var file: FileAccess = FileAccess.open(_fixture_directory.path_join("shot_0090_booth_3x.json"), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed


func _write_crop_descriptor(descriptor: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_fixture_directory.path_join("shot_0090_booth_3x.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(descriptor, "\t"))
	file.close()


func _read_metadata(frame: int) -> Dictionary:
	var path: String = _fixture_directory.path_join("shot_%04d.json" % frame)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value


func _write_metadata(frame: int, metadata: Dictionary) -> void:
	var path: String = _fixture_directory.path_join("shot_%04d.json" % frame)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata))
	file.close()


func _messages_contain(messages: PackedStringArray, expected: String) -> bool:
	for message: String in messages:
		if message.contains(expected):
			return true
	return false
