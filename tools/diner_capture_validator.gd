extends SceneTree
## Read-only identity checks for the two published Diner review captures.

const CAPTURE_DIRECTORY: String = "res://screens/visual-review/diner-review"
const MAIN_SCENE: String = "res://src/world/main.tscn"
const CAPTURE_TIMING: String = "frame_post_draw"
const PNG_SIGNATURE: PackedByteArray = PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
const EXPECTED_FRAMES: Array[int] = [12, 90]


func _initialize() -> void:
	var result: Dictionary = validate_capture_directory(CAPTURE_DIRECTORY)
	for message: String in result["messages"]:
		print(message)
	if not bool(result["valid"]):
		quit(1)
		return
	quit(0)


## Validates only the named image/metadata pairs. The caller may supply a
## private fixture directory in tests; this function never writes files.
static func validate_capture_directory(directory: String) -> Dictionary:
	var messages: PackedStringArray = []
	var valid: bool = true
	for frame: int in EXPECTED_FRAMES:
		var result: Dictionary = validate_capture_pair(directory, frame)
		messages.append_array(result["messages"])
		valid = valid and bool(result["valid"])
	return {"valid": valid, "messages": messages}


static func validate_capture_pair(directory: String, frame: int) -> Dictionary:
	var messages: PackedStringArray = []
	if frame not in EXPECTED_FRAMES:
		messages.append("diner-review: unexpected frame %d" % frame)
		return {"valid": false, "messages": messages}
	var filename: String = "shot_%04d.png" % frame
	var png_path: String = directory.path_join(filename)
	var metadata_path: String = directory.path_join("shot_%04d.json" % frame)
	if not FileAccess.file_exists(png_path):
		messages.append("diner-review: missing image %s" % filename)
		return {"valid": false, "messages": messages}
	if not FileAccess.file_exists(metadata_path):
		messages.append("diner-review: missing metadata for %s" % filename)
		return {"valid": false, "messages": messages}
	var png: FileAccess = FileAccess.open(png_path, FileAccess.READ)
	if png == null:
		messages.append("diner-review: could not read image %s" % filename)
		return {"valid": false, "messages": messages}
	var image_bytes: PackedByteArray = png.get_buffer(png.get_length())
	png.close()
	if image_bytes.size() <= 1000 or image_bytes.size() < 24 or image_bytes.slice(0, 8) != PNG_SIGNATURE:
		messages.append("diner-review: missing or corrupt PNG %s" % filename)
		return {"valid": false, "messages": messages}
	if image_bytes.decode_u32(16, true) != 1600 or image_bytes.decode_u32(20, true) != 900:
		messages.append("diner-review: wrong PNG dimensions in %s" % filename)
		return {"valid": false, "messages": messages}
	var metadata_file: FileAccess = FileAccess.open(metadata_path, FileAccess.READ)
	if metadata_file == null:
		messages.append("diner-review: could not read metadata for %s" % filename)
		return {"valid": false, "messages": messages}
	var metadata_text: String = metadata_file.get_as_text()
	metadata_file.close()
	var parsed: Variant = JSON.parse_string(metadata_text)
	if not parsed is Dictionary:
		messages.append("diner-review: invalid JSON metadata for %s" % filename)
		return {"valid": false, "messages": messages}
	var metadata: Dictionary = parsed
	if metadata.get("image_file") != filename:
		messages.append("diner-review: metadata names another image for frame %d" % frame)
	if metadata.get("image_sha256") != FileAccess.get_sha256(png_path):
		messages.append("diner-review: image/metadata digest mismatch for frame %d" % frame)
	if metadata.get("scene") != MAIN_SCENE or metadata.get("capture_timing") != CAPTURE_TIMING:
		messages.append("diner-review: wrong image source for frame %d" % frame)
	if typeof(metadata.get("width")) != TYPE_INT or typeof(metadata.get("height")) != TYPE_INT \
			or typeof(metadata.get("frame")) != TYPE_INT \
			or metadata.get("width") != 1600 or metadata.get("height") != 900 or metadata.get("frame") != frame:
		messages.append("diner-review: wrong viewport or frame identity for frame %d" % frame)
	if typeof(metadata.get("engine_errors")) != TYPE_INT or metadata.get("engine_errors") != 0:
		messages.append("diner-review: engine/script errors in frame %d metadata" % frame)
	var adapter: Variant = metadata.get("video_adapter")
	if not adapter is String or not String(adapter).to_lower().contains("llvmpipe"):
		messages.append("diner-review: not the requested software Mesa adapter for frame %d" % frame)
	var review: Variant = metadata.get("diner_review")
	var review_state: Variant = review.get("state") if review is Dictionary else null
	if not review is Dictionary or not review_state is Dictionary or review_state.get("frame") != frame:
		messages.append("diner-review: missing GDScript-validated frame identity for frame %d" % frame)
	if messages.is_empty():
		messages.append("diner-review: frame=%d, 1600x900, sha256=%s" % [frame, FileAccess.get_sha256(png_path)])
	return {"valid": messages.size() == 1 and messages[0].begins_with("diner-review: frame="),
		"messages": messages}
