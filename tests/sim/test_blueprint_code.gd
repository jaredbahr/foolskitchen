extends TestCase
## FK-332: portable, strictly validated blueprint codes.

const CODEC = preload("res://src/sim/shop/blueprint_code.gd")
const CODE_PREFIX: String = "FK1:"

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	_content = null


func test_round_trip_matches_blueprint_to_dict_including_looks_and_rotations() -> void:
	var source: Blueprint = Blueprint.new()
	source.display_name = "Café 🥐 booths and walnut"
	var plant: ShopPlacement = _entry(&"potted_plant", Vector2i(1, 2), 3)
	plant.swatch_id = &"sage"
	var booth: ShopPlacement = _entry(&"diner_booth", Vector2i(5, 1), 1)
	booth.variant_id = &"booth_walnut"
	source.entries = [plant, booth]
	var corner: Blueprint = source.copy()
	corner.display_name = "Quiet corner"
	corner.entries[0].quarter_turns = 0
	corner.entries[1].quarter_turns = 2
	var simple: Blueprint = source.copy()
	simple.display_name = "Tables at dusk"
	simple.entries[0].quarter_turns = 1
	simple.entries[0].swatch_id = &""
	simple.entries[1].quarter_turns = 0
	simple.entries[1].variant_id = &""
	var profiles: Array[Blueprint] = [source, corner, simple]
	for blueprint: Blueprint in profiles:
		var encoded: String = CODEC.encode(blueprint)
		assert_true(encoded.begins_with(CODE_PREFIX))
		var reasons: Array[String] = ["keep caller notes"]
		var restored: Blueprint = CODEC.decode(encoded, _content, reasons)
		assert_not_null(restored)
		if restored == null:
			continue
		assert_eq(restored.to_dict(), blueprint.to_dict())
		assert_eq(reasons, ["keep caller notes"] as Array[String], "success leaves caller diagnostics alone")
		assert_eq(restored.entries[0].swatch_id, blueprint.entries[0].swatch_id)
		assert_eq(restored.entries[1].variant_id, blueprint.entries[1].variant_id)
		assert_eq(restored.entries[0].quarter_turns, blueprint.entries[0].quarter_turns)
		assert_eq(restored.entries[1].quarter_turns, blueprint.entries[1].quarter_turns)


func test_entry_limit_accepts_forty_and_rejects_forty_one() -> void:
	var accepted: Dictionary = {"name": "Forty", "entries": []}
	var rejected: Dictionary = {"name": "Forty one", "entries": []}
	for index: int in 41:
		var row: Dictionary = _row("potted_plant", Vector2i(index % 20, floori(float(index) / 20)))
		if index < 40:
			accepted.entries.append(row)
		rejected.entries.append(row)
	assert_not_null(_decode(_json_code(accepted)), "the documented maximum is inclusive")
	_assert_rejected(_json_code(rejected), "one over the entry limit")


func test_rotated_footprints_may_touch_each_twenty_by_twenty_edge_but_not_cross() -> void:
	var cases: Array[Dictionary] = [
		{"rotation": 0, "offset": [0, 0], "label": "top-left"},
		{"rotation": 0, "offset": [16, 18], "label": "unrotated right and bottom"},
		{"rotation": 1, "offset": [18, 16], "label": "rotated right and bottom"},
	]
	for item: Dictionary in cases:
		var row: Dictionary = _row("rug_rectangle", Vector2i(item.offset[0], item.offset[1]), item.rotation)
		assert_not_null(_decode(_json_code({"name": "Edge", "entries": [row]})), item.label)
	_assert_rejected(_json_code({"name": "Left", "entries": [_row("rug_rectangle", Vector2i(-1, 0))]}),
		"negative x offset")
	_assert_rejected(_json_code({"name": "Top", "entries": [_row("rug_rectangle", Vector2i(0, -1))]}),
		"negative y offset")
	_assert_rejected(_json_code({"name": "Past right", "entries": [_row("rug_rectangle", Vector2i(17, 18))]}),
		"unrotated width crosses the right edge")
	_assert_rejected(_json_code({"name": "Past bottom", "entries": [_row("rug_rectangle", Vector2i(16, 19))]}),
		"unrotated depth crosses the bottom edge")
	_assert_rejected(_json_code({"name": "Rotated past right", "entries": [_row("rug_rectangle", Vector2i(19, 16), 1)]}),
		"rotated width crosses the right edge")
	_assert_rejected(_json_code({"name": "Rotated past bottom", "entries": [_row("rug_rectangle", Vector2i(18, 17), 1)]}),
		"rotated depth crosses the bottom edge")


func test_rejects_bad_prefix_base64_padding_and_raw_utf8() -> void:
	var valid_payload: String = JSON.stringify({"name": "Pad!", "entries": []})
	var padded: String = Marshalls.utf8_to_base64(valid_payload)
	assert_true(padded.ends_with("="), "fixture must exercise strict padding")
	_assert_rejected("", "empty code")
	_assert_rejected("FK0:" + padded, "unsupported version prefix")
	_assert_rejected("fk1:" + padded, "prefix is case sensitive")
	_assert_rejected(CODE_PREFIX + "%%%", "invalid base64 alphabet")
	_assert_rejected(CODE_PREFIX + padded.trim_suffix("="), "missing required base64 padding")
	_assert_rejected(CODE_PREFIX + padded + "=", "extra base64 padding")
	var invalid_utf8: PackedByteArray = _bytes("{\"name\":\"")
	invalid_utf8.append_array(PackedByteArray([0xC3, 0x28]))
	invalid_utf8.append_array(_bytes("\",\"entries\":[]}"))
	_assert_rejected(CODE_PREFIX + Marshalls.raw_to_base64(invalid_utf8), "invalid UTF-8")
	_assert_rejected(_raw_code(_surrogate_json()), "unpaired JSON surrogate")


func test_rejects_malformed_json_and_non_finite_numbers() -> void:
	_assert_rejected(_json_code_text("{"), "truncated JSON")
	_assert_rejected(_json_code_text("{\"name\":\"Trailing\",\"entries\":[],}"), "trailing comma")
	_assert_rejected(_json_code_text("{\"name\":\"Leading zero\",\"entries\":[{\"item_id\":\"rug_rectangle\",\"offset\":[01,0],\"rotation\":0,\"swatch_id\":\"\",\"variant_id\":\"\"}]}"), "leading-zero number")
	_assert_rejected(_json_code_text("{\"name\":\"Exponent\",\"entries\":[{\"item_id\":\"rug_rectangle\",\"offset\":[1e999,0],\"rotation\":0,\"swatch_id\":\"\",\"variant_id\":\"\"}]}"), "out-of-range exponent")
	_assert_rejected(_json_code_text("{\"name\":\"Number\",\"entries\":[{\"item_id\":\"rug_rectangle\",\"offset\":[0,0],\"rotation\":NaN,\"swatch_id\":\"\",\"variant_id\":\"\"}]}"), "NaN is not JSON")
	_assert_rejected(_json_code_text("{\"name\":\"Number\",\"entries\":[{\"item_id\":\"rug_rectangle\",\"offset\":[0,0],\"rotation\":Infinity,\"swatch_id\":\"\",\"variant_id\":\"\"}]}"), "Infinity is not JSON")
	_assert_rejected(_json_code_text("[]"), "root must be an object")
	_assert_rejected(_raw_code(_bytes("{\"name\":\"Raw newline\n\",\"entries\":[]}")), "raw newline inside JSON string")
	_assert_rejected(_raw_code(_bytes("{\"name\":\"Raw tab\t\",\"entries\":[]}")), "raw tab inside JSON string")
	var raw_control: PackedByteArray = _bytes("{\"name\":\"")
	raw_control.append(1)
	raw_control.append_array(_bytes("\",\"entries\":[]}"))
	_assert_rejected(_raw_code(raw_control), "raw control byte inside JSON string")
	var overlong_utf8: PackedByteArray = _bytes("{\"name\":\"")
	overlong_utf8.append_array(PackedByteArray([0xC0, 0xAF]))
	overlong_utf8.append_array(_bytes("\",\"entries\":[]}"))
	_assert_rejected(_raw_code(overlong_utf8), "overlong UTF-8")
	_assert_rejected(_json_code_text("{\"name\":\"\\udc00\",\"entries\":[]}"), "unpaired low surrogate")
	_assert_rejected(_json_code_text("{\"name\":\"\\ud800\\ud800\",\"entries\":[]}"), "high surrogate must pair with a low surrogate")
	var paired_surrogate: String = "{\"name\":\"\\ud83e\\udd55\",\"entries\":[{\"item_id\":\"potted_plant\",\"offset\":[0,0],\"rotation\":0,\"swatch_id\":\"\",\"variant_id\":\"\"}]}"
	var paired_code: String = _json_code_text(paired_surrogate)
	var paired_result: Blueprint = _decode(paired_code)
	assert_not_null(paired_result, "a valid escaped surrogate pair decodes without a warning")
	if paired_result != null:
		assert_eq(paired_result.display_name, "🥕")
	var whole_float_text: String = "{\"name\":\"Whole JSON numbers\",\"entries\":[{\"item_id\":\"potted_plant\",\"offset\":[1.0,0.0],\"rotation\":1.0,\"swatch_id\":\"\",\"variant_id\":\"\"}]}"
	var whole_float: Blueprint = _decode(_json_code_text(whole_float_text))
	assert_not_null(whole_float, "finite whole JSON floats preserve the integer schema values")
	if whole_float != null:
		assert_eq(whole_float.entries[0].origin, Vector2i(1, 0))
		assert_eq(whole_float.entries[0].quarter_turns, 1)


func test_rejects_wrong_types_unknown_items_and_unknown_looks() -> void:
	var base: Dictionary = _row("potted_plant", Vector2i.ZERO)
	for bad_name: Variant in [17, true, null, ["name"], {"text": "name"}]:
		_assert_rejected(_json_code({"name": bad_name, "entries": []}), "name type %s" % typeof(bad_name))
	for bad_entries: Variant in [17, true, null, {}, "entries"]:
		_assert_rejected(_json_code({"name": "Shape", "entries": bad_entries}), "entries type %s" % typeof(bad_entries))
	for bad_row: Variant in [17, true, null, [], "entry"]:
		_assert_rejected(_json_code({"name": "Shape", "entries": [bad_row]}), "entry type %s" % typeof(bad_row))
	var wrong_field: Dictionary = base.duplicate(true)
	wrong_field.offset = "0,0"
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "offset must be a pair")
	wrong_field = base.duplicate(true)
	wrong_field.offset = [0, 0.5]
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "fractional offset")
	wrong_field = base.duplicate(true)
	wrong_field.offset = [false, 0]
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "boolean offset")
	wrong_field = base.duplicate(true)
	wrong_field.rotation = 1.25
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "fractional rotation")
	wrong_field = base.duplicate(true)
	wrong_field.rotation = false
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "boolean rotation")
	wrong_field = base.duplicate(true)
	wrong_field.rotation = 4
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "rotation outside zero through three")
	wrong_field = base.duplicate(true)
	wrong_field.item_id = "future_item"
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "unknown item")
	wrong_field = base.duplicate(true)
	wrong_field.item_id = 17
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "item id must be text")
	wrong_field = _row("door", Vector2i.ZERO)
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "known but ineligible item")
	wrong_field = base.duplicate(true)
	wrong_field.swatch_id = "removed_swatch"
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "unknown swatch")
	wrong_field = base.duplicate(true)
	wrong_field.swatch_id = 17
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "swatch id must be text")
	wrong_field = base.duplicate(true)
	wrong_field.variant_id = "removed_variant"
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "unknown variant")
	wrong_field = base.duplicate(true)
	wrong_field.variant_id = 17
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "variant id must be text")
	wrong_field = _row("rug_rectangle", Vector2i.ZERO)
	wrong_field.swatch_id = "sage"
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "a known swatch cannot paint a non-paintable item")
	wrong_field = base.duplicate(true)
	wrong_field.erase("variant_id")
	_assert_rejected(_json_code({"name": "Shape", "entries": [wrong_field]}), "all codec fields are required")


func test_rejects_names_outside_single_line_eighty_character_contract() -> void:
	_assert_rejected(_json_code({"name": "", "entries": []}), "empty name")
	_assert_rejected(_json_code({"name": "   ", "entries": []}), "whitespace-only name")
	_assert_rejected(_json_code({"name": "Line one\nLine two", "entries": []}), "multiline name")
	_assert_rejected(_json_code({"name": "x".repeat(81), "entries": []}), "name over 80 characters")
	_assert_rejected("FK1:" + "A".repeat(32769), "input over the 32768-character bound")


func test_two_hundred_seeded_fuzz_payloads_with_valid_prefix_and_base64_reject_cleanly() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 332_2026
	for index: int in 200:
		var raw: PackedByteArray = _bytes("{\"name\":")
		var payload_size: int = random.randi_range(1, 64)
		for _byte_index: int in payload_size:
			raw.append(random.randi_range(0, 255))
		# The invalid trailing token ensures every decoded byte stream is malformed,
		# while the randomized middle exercises UTF-8, number, and parser edges.
		raw.append(33)
		var code: String = CODE_PREFIX + Marshalls.raw_to_base64(raw)
		var reasons: Array[String] = []
		var decoded: Blueprint = CODEC.decode(code, _content, reasons)
		assert_null(decoded, "seeded malformed payload %d" % index)
		assert_eq(reasons.size(), 1, "one useful diagnostic for payload %d" % index)
		assert_false(reasons.is_empty() or reasons[0].strip_edges().is_empty(), "diagnostic for payload %d" % index)


func test_encode_refuses_invalid_blueprint_without_changing_legacy_restore_contract() -> void:
	var invalid: Blueprint = Blueprint.new()
	invalid.display_name = "No entry"
	assert_eq(CODEC.encode(invalid), "")
	var library: BlueprintLibrary = BlueprintLibrary.new()
	var old_data: Dictionary = {"version": BlueprintLibrary.VERSION, "blueprints": [{
		"name": "Legacy leniency", "entries": [{"item_id": "future_item", "offset": [0, 0], "rotation": 0}]}]}
	var notes: Array[String] = []
	assert_true(library.restore(old_data, _content, notes))
	assert_eq(library.blueprints.size(), 0, "legacy import still skips an unknown-only empty blueprint")


func _decode(code: String) -> Blueprint:
	var reasons: Array[String] = []
	var decoded: Blueprint = CODEC.decode(code, _content, reasons)
	assert_eq(reasons, [] as Array[String])
	return decoded


func _assert_rejected(code: String, label: String) -> void:
	var reasons: Array[String] = []
	var decoded: Blueprint = CODEC.decode(code, _content, reasons)
	assert_null(decoded, label)
	assert_eq(reasons.size(), 1, "%s returns one diagnostic" % label)
	if not reasons.is_empty():
		assert_false(reasons[0].strip_edges().is_empty(), "%s diagnostic is useful" % label)


func _entry(item_id: StringName, offset: Vector2i, rotation: int = 0) -> ShopPlacement:
	var result: ShopPlacement = ShopPlacement.new()
	result.item_id = item_id
	result.origin = offset
	result.quarter_turns = rotation
	return result


func _row(item_id: String, offset: Vector2i, rotation: int = 0) -> Dictionary:
	return {"item_id": item_id, "offset": [offset.x, offset.y], "rotation": rotation,
		"swatch_id": "", "variant_id": ""}


func _json_code(payload: Variant) -> String:
	return _json_code_text(JSON.stringify(payload))


func _json_code_text(payload: String) -> String:
	return CODE_PREFIX + Marshalls.utf8_to_base64(payload)


func _raw_code(payload: PackedByteArray) -> String:
	return CODE_PREFIX + Marshalls.raw_to_base64(payload)


func _bytes(value: String) -> PackedByteArray:
	return value.to_utf8_buffer()


func _surrogate_json() -> PackedByteArray:
	return _bytes("{\"name\":\"\\ud800\",\"entries\":[]}")
