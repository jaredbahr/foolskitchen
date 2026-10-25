extends TestCase
## Focused read-only capture identity tests using private user:// files.

const VALIDATOR: Script = preload("res://tools/diner_capture_validator.gd")

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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fixture_directory))


func test_accepts_both_actual_png_metadata_identity_pairs_in_private_fixture_dir() -> void:
	var result: Dictionary = VALIDATOR.validate_capture_directory(_fixture_directory)
	assert_true(result["valid"], str(result["messages"]))
	assert_eq(result["messages"].size(), 2)


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


func _write_pair(frame: int) -> void:
	var image: Image = Image.create(1600, 900, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var png_path: String = _fixture_directory.path_join("shot_%04d.png" % frame)
	assert_eq(image.save_png(png_path), OK)
	_write_metadata(frame, {"image_file": "shot_%04d.png" % frame,
		"image_sha256": FileAccess.get_sha256(png_path), "scene": "res://src/world/main.tscn",
		"capture_timing": "frame_post_draw", "width": 1600, "height": 900, "frame": frame,
		"engine_errors": 0, "video_adapter": "Mesa llvmpipe (LLVM)",
		"diner_review": {"state": {"frame": frame}}})


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
