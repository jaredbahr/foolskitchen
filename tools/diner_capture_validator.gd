extends SceneTree
## Read-only identity checks for the two published Diner review captures.

const CAPTURE_DIRECTORY: String = "res://screens/visual-review/diner-review"
const MAIN_SCENE: String = "res://src/world/main.tscn"
const CAPTURE_TIMING: String = "frame_post_draw"
const PNG_SIGNATURE: PackedByteArray = PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
const EXPECTED_FRAMES: Array[int] = [12, 90]
const BOOTH_CROP_FILENAME: String = "shot_0090_booth_3x.png"
const SEAT_CLEARANCE_PROVENANCE: String = "native Mini head-mesh POSITION/JOINTS/WEIGHTS, imported Skin inverse binds, current Skeleton3D global poses, actual node transforms"
const SEAT_CLEARANCE_METRIC: String = "minimum Euclidean seat-triangle to conservative posed-head AABB separation"


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
	if image_bytes_width(image_bytes) != 1600 or image_bytes_height(image_bytes) != 900:
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
	if not _integer_equals(metadata.get("width"), 1600, 1, 1600) \
			or not _integer_equals(metadata.get("height"), 900, 1, 900) \
			or not _integer_equals(metadata.get("frame"), frame, 12, 90):
		messages.append("diner-review: wrong viewport or frame identity for frame %d" % frame)
	if not _integer_equals(metadata.get("engine_errors"), 0, 0, 0):
		messages.append("diner-review: engine/script errors in frame %d metadata" % frame)
	var adapter: Variant = metadata.get("video_adapter")
	if not adapter is String or not String(adapter).to_lower().contains("llvmpipe"):
		messages.append("diner-review: not the requested software Mesa adapter for frame %d" % frame)
	var review: Variant = metadata.get("diner_review")
	var review_state: Variant = review.get("state") if review is Dictionary else null
	if not review is Dictionary or not review_state is Dictionary \
			or not _integer_equals(review_state.get("frame"), frame, 12, 90):
		messages.append("diner-review: missing GDScript-validated frame identity for frame %d" % frame)
	var valid: bool = messages.is_empty()
	if valid and frame == 90:
		var crop_result: Dictionary = validate_booth_crop(directory, metadata, png_path)
		valid = bool(crop_result["valid"])
		messages.append_array(crop_result["messages"])
	if valid:
		messages.append("diner-review: frame=%d, 1600x900, sha256=%s" % [frame, FileAccess.get_sha256(png_path)])
	return {"valid": valid, "messages": messages}


static func validate_booth_crop(directory: String, source_metadata: Dictionary, source_path: String) -> Dictionary:
	var messages: PackedStringArray = []
	var review: Variant = source_metadata.get("diner_review")
	var descriptor: Variant = review.get("booth_crop") if review is Dictionary else null
	if not descriptor is Dictionary:
		return _invalid("diner-review: missing seated booth crop metadata")
	var crop_path: String = directory.path_join(BOOTH_CROP_FILENAME)
	var crop_metadata_path: String = directory.path_join("shot_0090_booth_3x.json")
	if not FileAccess.file_exists(crop_path) or not FileAccess.file_exists(crop_metadata_path):
		return _invalid("diner-review: missing seated booth crop image or metadata")
	var crop_file: FileAccess = FileAccess.open(crop_path, FileAccess.READ)
	var crop_json_file: FileAccess = FileAccess.open(crop_metadata_path, FileAccess.READ)
	if crop_file == null or crop_json_file == null:
		if crop_file != null:
			crop_file.close()
		if crop_json_file != null:
			crop_json_file.close()
		return _invalid("diner-review: could not read seated booth crop image or metadata")
	var crop_bytes: PackedByteArray = crop_file.get_buffer(crop_file.get_length())
	crop_file.close()
	var crop_json_text: String = crop_json_file.get_as_text()
	crop_json_file.close()
	var crop_parsed: Variant = JSON.parse_string(crop_json_text)
	if not crop_parsed is Dictionary or crop_parsed != descriptor:
		return _invalid("diner-review: seated crop JSON does not match frame-90 crop metadata")
	if crop_bytes.size() < 24 or crop_bytes.slice(0, 8) != PNG_SIGNATURE:
		return _invalid("diner-review: missing or corrupt seated booth crop PNG")
	var rect_result: Dictionary = _crop_rect(descriptor.get("source_rect"))
	if not bool(rect_result["valid"]):
		return _invalid("diner-review: seated crop has an invalid source rectangle")
	var source_rect: Rect2i = rect_result["rect"]
	var source_image: Image = Image.load_from_file(source_path)
	if source_image == null or source_image.is_empty() or source_image.get_size() != Vector2i(1600, 900):
		return _invalid("diner-review: could not decode the frame-90 source PNG")
	source_image.convert(Image.FORMAT_RGBA8)
	if source_rect.position.x < 0 or source_rect.position.y < 0 or source_rect.size.x <= 0 \
			or source_rect.size.y <= 0 or source_rect.end.x > source_image.get_width() \
			or source_rect.end.y > source_image.get_height():
		return _invalid("diner-review: seated crop source rectangle is outside frame 90")
	var expected_width: int = source_rect.size.x * 3
	var expected_height: int = source_rect.size.y * 3
	if descriptor.get("source_image_file") != "shot_0090.png" \
			or descriptor.get("source_image_sha256") != FileAccess.get_sha256(source_path) \
			or descriptor.get("error") != "" \
			or not _integer_equals(descriptor.get("source_frame"), 90, 90, 90) \
			or not _integer_equals(descriptor.get("scale"), 3, 3, 3) \
			or descriptor.get("interpolation") != "nearest" \
			or descriptor.get("kind") != "source_pixel_derivative" \
			or descriptor.get("image_file") != BOOTH_CROP_FILENAME \
			or not _integer_equals(descriptor.get("width"), expected_width, 1, 4800) \
			or not _integer_equals(descriptor.get("height"), expected_height, 1, 2700) \
			or image_bytes_width(crop_bytes) != expected_width or image_bytes_height(crop_bytes) != expected_height \
			or descriptor.get("image_sha256") != FileAccess.get_sha256(crop_path):
		return _invalid("diner-review: seated booth crop metadata identity, size or digest mismatch")
	var booth_result: Dictionary = _booth_measurement(source_metadata, descriptor, source_rect)
	if not bool(booth_result["valid"]):
		return _invalid(String(booth_result["error"]))
	var expected_crop: Image = source_image.get_region(source_rect)
	expected_crop.resize(expected_width, expected_height, Image.INTERPOLATE_NEAREST)
	var actual_crop: Image = Image.load_from_file(crop_path)
	if actual_crop == null or actual_crop.is_empty() or actual_crop.get_data() != expected_crop.get_data():
		return _invalid("diner-review: seated booth crop pixels are not the exact 3x nearest source crop")
	messages.append("diner-review: seated booth crop=3x nearest, guest=%d, source_sha256=%s, crop_sha256=%s" % [
		int(descriptor["guest_id"]), FileAccess.get_sha256(source_path), FileAccess.get_sha256(crop_path)])
	return {"valid": true, "messages": messages}


static func _booth_measurement(source_metadata: Dictionary, descriptor: Dictionary, source_rect: Rect2i) -> Dictionary:
	var review: Variant = source_metadata.get("diner_review")
	var state: Variant = review.get("state") if review is Dictionary else null
	var actors: Variant = state.get("actors") if state is Dictionary else null
	var items: Variant = state.get("items") if state is Dictionary else null
	var measurement: Variant = descriptor.get("measurement")
	if not actors is Array or not items is Array or not measurement is Dictionary:
		return {"valid": false, "error": "diner-review: seated crop lacks actual booth actor measurement evidence"}
	var selected: Dictionary = {}
	var selected_actor: Dictionary = {}
	var lowest_head_bottom: float = -INF
	var selected_guest_id: int = 0
	for value: Variant in actors:
		if not value is Dictionary or value.get("furnishing_definition") != "diner_booth":
			continue
		var actor: Dictionary = value
		var clearance: Variant = actor.get("seat_clearance")
		if not clearance is Dictionary or not _valid_clearance(clearance):
			return {"valid": false, "error": "diner-review: a booth guest lacks valid posed-head measurement evidence"}
		var head_bounds: Dictionary = clearance["head_screen_bounds"]
		var guest_id: int = int(clearance["guest_id"])
		if actor.get("role") != "customer" or actor.get("seated") != true or actor.get("visible") != true \
				or actor.get("clip") != "sit" or actor.get("player_clip") != "sit" \
				or actor.get("reservation") != actor.get("id") or actor.get("linked_table") != actor.get("table") \
				or clearance.get("guest_id") != actor.get("id") \
				or clearance.get("furnishing_id") != actor.get("furnishing") \
				or clearance.get("table_item_id") != actor.get("table"):
			return {"valid": false, "error": "diner-review: booth measurement is not bound to a seated reserved guest"}
		var head_bottom: float = float(head_bounds["y"]) + float(head_bounds["height"])
		if head_bottom > lowest_head_bottom or (head_bottom == lowest_head_bottom \
				and (selected_guest_id == 0 or guest_id < selected_guest_id)):
			lowest_head_bottom = head_bottom
			selected_guest_id = guest_id
			selected = clearance
			selected_actor = actor
	if selected.is_empty() or selected != measurement:
		return {"valid": false, "error": "diner-review: seated crop measurement is not the lowest-screen booth guest"}
	var guest_id: Variant = descriptor.get("guest_id")
	if not _integer_value(guest_id, 1, 2147483647) or guest_id != selected.get("guest_id") \
			or guest_id != selected_actor.get("id") \
			or not _integer_equals(descriptor.get("furnishing_id"), int(selected_actor.get("furnishing", -1)), 1, 2147483647) \
			or not _integer_equals(descriptor.get("table_item_id"), int(selected_actor.get("table", -1)), 1, 2147483647):
		return {"valid": false, "error": "diner-review: seated crop guest identity does not match measured booth guest"}
	var head_bounds: Rect2 = _screen_rect(selected["head_screen_bounds"])
	var furnishing_item: Dictionary = _item_by_id(items, int(selected_actor.get("furnishing", -1)))
	var table_item: Dictionary = _item_by_id(items, int(selected_actor.get("table", -1)))
	if furnishing_item.get("definition") != "diner_booth":
		return {"valid": false, "error": "diner-review: selected booth guest has no native booth evidence"}
	var furnishing_rect: Rect2 = _item_screen_rect(furnishing_item)
	var table_rect: Rect2 = _item_screen_rect(table_item)
	if furnishing_rect.size == Vector2.ZERO or table_rect.size == Vector2.ZERO:
		return {"valid": false, "error": "diner-review: seated crop lacks native booth or table screen bounds"}
	var bounds: Rect2 = head_bounds.merge(furnishing_rect).merge(table_rect)
	if not Rect2(Vector2.ZERO, Vector2(1600, 900)).encloses(bounds):
		return {"valid": false, "error": "diner-review: measured seated booth context lies outside frame 90"}
	var left: int = maxi(0, floori(bounds.position.x - 12.0))
	var top: int = maxi(0, floori(bounds.position.y - 12.0))
	var right: int = mini(1600, ceili(bounds.end.x + 12.0))
	var bottom: int = mini(900, ceili(bounds.end.y + 12.0))
	if source_rect != Rect2i(left, top, right - left, bottom - top):
		return {"valid": false, "error": "diner-review: seated crop rectangle does not match measured guest and furniture bounds"}
	return {"valid": true, "error": ""}


static func _valid_clearance(clearance: Dictionary) -> bool:
	var guest_id: Variant = clearance.get("guest_id")
	var furnishing_id: Variant = clearance.get("furnishing_id")
	var table_item_id: Variant = clearance.get("table_item_id")
	var head_bounds: Variant = clearance.get("head_world_bounds")
	var head_screen: Variant = clearance.get("head_screen_bounds")
	var min_bounds: Variant = head_bounds.get("min") if head_bounds is Dictionary else null
	var max_bounds: Variant = head_bounds.get("max") if head_bounds is Dictionary else null
	if not _integer_value(guest_id, 1, 2147483647) \
			or not _integer_value(furnishing_id, 1, 2147483647) \
			or not _integer_value(table_item_id, 1, 2147483647) \
			or not _finite_vector3(min_bounds) or not _finite_vector3(max_bounds) \
			or not head_screen is Dictionary or not _screen_values_valid(head_screen) \
			or typeof(clearance.get("seated_head_clearance")) not in [TYPE_INT, TYPE_FLOAT] \
			or not is_finite(float(clearance["seated_head_clearance"])) \
			or float(clearance["seated_head_clearance"]) < 0.02 \
			or not _integer_equals(clearance.get("intersecting_triangles"), 0, 0, 0) \
			or clearance.get("head_center_inside_seat") != false \
			or clearance.get("seat_geometry_measured") != true \
			or not _integer_value(clearance.get("head_vertices"), 1, 1000000) \
			or clearance.get("measurement_provenance") != SEAT_CLEARANCE_PROVENANCE \
			or clearance.get("clearance_metric") != SEAT_CLEARANCE_METRIC:
		return false
	var low: Array = min_bounds
	var high: Array = max_bounds
	for axis: int in range(3):
		if float(high[axis]) <= float(low[axis]):
			return false
	return true


static func _finite_vector3(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
			return false
	return true


static func _screen_values_valid(value: Dictionary) -> bool:
	for key: String in ["x", "y", "width", "height"]:
		if typeof(value.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[key])):
			return false
	return float(value["width"]) > 0.0 and float(value["height"]) > 0.0


static func _screen_rect(value: Dictionary) -> Rect2:
	return Rect2(float(value["x"]), float(value["y"]), float(value["width"]), float(value["height"]))


static func _item_by_id(items: Array, item_id: int) -> Dictionary:
	for value: Variant in items:
		if value is Dictionary and value.get("id") == item_id:
			return value
	return {}


static func _item_screen_rect(item: Dictionary) -> Rect2:
	var prop: Variant = item.get("prop")
	var bounds: Variant = prop.get("bounds") if prop is Dictionary else null
	var rect: Variant = bounds.get("rect") if bounds is Dictionary else null
	if not rect is Array or rect.size() != 4:
		return Rect2()
	for coordinate: Variant in rect:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
			return Rect2()
	var result: Rect2 = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	return result if result.size.x > 0.0 and result.size.y > 0.0 else Rect2()


static func _crop_rect(value: Variant) -> Dictionary:
	if not value is Array or value.size() != 4:
		return {"valid": false, "rect": Rect2i()}
	for coordinate: Variant in value:
		if not _integer_value(coordinate, -2147483647, 2147483647):
			return {"valid": false, "rect": Rect2i()}
	if float(value[0]) < 0.0 or float(value[0]) >= 1600.0 or float(value[1]) < 0.0 \
			or float(value[1]) >= 900.0 or float(value[2]) < 1.0 or float(value[2]) > 1600.0 \
			or float(value[3]) < 1.0 or float(value[3]) > 900.0:
		return {"valid": false, "rect": Rect2i()}
	return {"valid": true, "rect": Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))}


static func _integer_value(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= float(minimum) and number <= float(maximum) \
		and number == floorf(number)


static func _integer_equals(value: Variant, expected: int, minimum: int, maximum: int) -> bool:
	return _integer_value(value, minimum, maximum) and float(value) == float(expected)


static func image_bytes_width(bytes: PackedByteArray) -> int:
	return _png_u32_be(bytes, 16) if bytes.size() >= 24 else -1


static func image_bytes_height(bytes: PackedByteArray) -> int:
	return _png_u32_be(bytes, 20) if bytes.size() >= 24 else -1


## PNG chunk lengths and dimensions are four-byte unsigned big-endian values.
static func _png_u32_be(bytes: PackedByteArray, byte_offset: int) -> int:
	if byte_offset < 0 or byte_offset > bytes.size() - 4:
		return -1
	return (int(bytes[byte_offset]) << 24) | (int(bytes[byte_offset + 1]) << 16) \
		| (int(bytes[byte_offset + 2]) << 8) | int(bytes[byte_offset + 3])


static func _invalid(message: String) -> Dictionary:
	return {"valid": false, "messages": PackedStringArray([message])}
