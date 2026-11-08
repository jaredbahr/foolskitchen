class_name BlueprintCode
extends RefCounted
## Clipboard-only FK1 transport. The larger, lenient saved-library decoder
## remains separate. Never deserialize Godot objects from a shared code.

const PREFIX: String = "FK1:"
const MAX_ENTRIES: int = 40
const BOX_SIZE: int = 20
## Forty compact entry records plus escaped names/known content ids fit well
## below this transport bound. Bound work before base64 or JSON allocation.
const MAX_CODE_LENGTH: int = 32768
const BASE64: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


static func encode(blueprint: Blueprint) -> String:
	if blueprint == null or blueprint.entries.is_empty() or blueprint.entries.size() > MAX_ENTRIES \
			or not _name_valid(blueprint.display_name):
		return ""
	for entry: ShopPlacement in blueprint.entries:
		if entry == null:
			return ""
	var result: String = PREFIX + Marshalls.utf8_to_base64(JSON.stringify(blueprint.to_dict()))
	return result if result.length() <= MAX_CODE_LENGTH else ""


## Copy validates against current content before touching the clipboard. This
## companion API can explain a legacy blueprint too large for sharing.
static func validate(blueprint: Blueprint, content: ContentDB, reasons: Array[String] = []) -> bool:
	if blueprint == null:
		_fail(reasons, BlueprintCodeText.INVALID)
		return false
	if blueprint.entries.is_empty() or blueprint.entries.size() > MAX_ENTRIES:
		_fail(reasons, BlueprintCodeText.COUNT)
		return false
	for entry: ShopPlacement in blueprint.entries:
		if entry == null:
			_fail(reasons, BlueprintCodeText.INVALID)
			return false
	return _from_dict(blueprint.to_dict(), content, reasons) != null


static func decode(text: String, content: ContentDB, reasons: Array[String] = []) -> Blueprint:
	if text.length() > MAX_CODE_LENGTH:
		return _fail(reasons, BlueprintCodeText.TOO_LONG)
	var code: String = text.strip_edges()
	if code.is_empty():
		return _fail(reasons, BlueprintCodeText.EMPTY)
	if not code.begins_with(PREFIX):
		return _fail(reasons, BlueprintCodeText.INVALID)
	var payload: String = code.substr(PREFIX.length())
	if not _base64_valid(payload):
		return _fail(reasons, BlueprintCodeText.INVALID)
	var bytes: PackedByteArray = Marshalls.base64_to_raw(payload)
	if not _utf8_valid(bytes):
		return _fail(reasons, BlueprintCodeText.INVALID)
	var json_text: String = bytes.get_string_from_utf8()
	# Godot's JSON parser accepts trailing commas/raw string controls, and logs
	# invalid Unicode escapes. Reject those before entering the native parser.
	if not _json_safe(json_text):
		return _fail(reasons, BlueprintCodeText.INVALID)
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK:
		return _fail(reasons, BlueprintCodeText.INVALID)
	return _from_dict(json.data, content, reasons)


static func _from_dict(value: Variant, content: ContentDB, reasons: Array[String]) -> Blueprint:
	if content == null or not value is Dictionary:
		return _fail(reasons, BlueprintCodeText.INVALID)
	var data: Dictionary = value
	if data.size() != 2 or not data.has("name") or not data.has("entries"):
		return _fail(reasons, BlueprintCodeText.INVALID)
	if not data["name"] is String or not _name_valid(data["name"]):
		return _fail(reasons, BlueprintCodeText.NAME)
	if not data["entries"] is Array:
		return _fail(reasons, BlueprintCodeText.INVALID)
	var rows: Array = data["entries"]
	if rows.is_empty() or rows.size() > MAX_ENTRIES:
		return _fail(reasons, BlueprintCodeText.COUNT)
	var result: Blueprint = Blueprint.new()
	result.display_name = data["name"]
	for raw: Variant in rows:
		if not raw is Dictionary:
			return _fail(reasons, BlueprintCodeText.INVALID)
		var row: Dictionary = raw
		if row.size() != 5 or not row.get("item_id") is String or not row.get("offset") is Array \
				or not row.get("swatch_id") is String or not row.get("variant_id") is String:
			return _fail(reasons, BlueprintCodeText.INVALID)
		var definition: ItemDef = content.item(StringName(row["item_id"]))
		if definition == null:
			return _fail(reasons, BlueprintCodeText.ITEM)
		if not Blueprint.eligible(definition):
			return _fail(reasons, BlueprintCodeText.UNSUPPORTED)
		if not _integer(row.get("rotation"), 0, 3):
			return _fail(reasons, BlueprintCodeText.ROTATION)
		var offset: Array = row["offset"]
		if offset.size() != 2 or not _integer(offset[0], 0, BOX_SIZE - 1) \
				or not _integer(offset[1], 0, BOX_SIZE - 1):
			return _fail(reasons, BlueprintCodeText.POSITION)
		var entry: ShopPlacement = ShopPlacement.new()
		entry.item_id = definition.id
		entry.origin = Vector2i(int(offset[0]), int(offset[1]))
		entry.quarter_turns = int(row["rotation"])
		var extent: Vector2i = entry.origin + GridMath.rotated_footprint(definition.footprint, entry.quarter_turns)
		if extent.x > BOX_SIZE or extent.y > BOX_SIZE:
			return _fail(reasons, BlueprintCodeText.POSITION)
		entry.variant_id = StringName(row["variant_id"])
		entry.swatch_id = StringName(row["swatch_id"])
		if not entry.variant_id.is_empty() and definition.known_variant_id(entry.variant_id) != entry.variant_id:
			return _fail(reasons, BlueprintCodeText.LOOK)
		if not entry.swatch_id.is_empty() and (not definition.paintable or content.swatch(entry.swatch_id) == null):
			return _fail(reasons, BlueprintCodeText.LOOK)
		result.entries.append(entry)
	return result


static func _name_valid(value: String) -> bool:
	if value.length() > BlueprintLibrary.MAX_NAME_LENGTH or not BlueprintLibrary.valid_name(value):
		return false
	for i: int in value.length():
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127:
			return false
	return true


static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and floorf(float(value)) == float(value) and value >= low and value <= high


static func _fail(reasons: Array[String], message: String) -> Blueprint:
	reasons.append(message)
	return null


static func _base64_valid(text: String) -> bool:
	if text.is_empty() or text.length() % 4 != 0:
		return false
	var padding: int = 2 if text.ends_with("==") else 1 if text.ends_with("=") else 0
	var length: int = text.length() - padding
	for i: int in length:
		if BASE64.find(text[i]) < 0:
			return false
	if padding == 2 and (BASE64.find(text[length - 1]) & 15) != 0:
		return false
	if padding == 1 and (BASE64.find(text[length - 1]) & 3) != 0:
		return false
	return true


## Strict Unicode scalar decoding, before get_string_from_utf8 can log an
## invalid sequence. Embedded raw NUL is never part of this JSON format.
static func _utf8_valid(bytes: PackedByteArray) -> bool:
	var i: int = 0
	while i < bytes.size():
		var lead: int = bytes[i]
		if lead > 0 and lead < 128:
			i += 1
			continue
		var count: int = 1 if lead >= 194 and lead <= 223 else 2 if lead >= 224 and lead <= 239 \
			else 3 if lead >= 240 and lead <= 244 else 0
		if count == 0 or i + count >= bytes.size():
			return false
		var point: int = lead & (31 if count == 1 else 15 if count == 2 else 7)
		for j: int in range(1, count + 1):
			var next: int = bytes[i + j]
			if next < 128 or next > 191:
				return false
			point = (point << 6) | (next & 63)
		var minimum: int = 128 if count == 1 else 2048 if count == 2 else 65536
		if point < minimum or point > 1114111 or point >= 55296 and point <= 57343:
			return false
		i += count + 1
	return not bytes.is_empty()


## This is a lexical safety guard, not a second JSON value parser. Native
## JSON.parse still checks structure/types. Four levels cover this exact
## schema: object / entries array / entry object / offset array.
static func _json_safe(text: String) -> bool:
	var i: int = 0
	var stack: Array[String] = []
	var previous: String = ""
	while i < text.length():
		var ch: String = text[i]
		if ch in [" ", "\t", "\r", "\n"]:
			i += 1
			continue
		if ch == '"':
			i += 1
			var closed: bool = false
			while i < text.length():
				ch = text[i]
				if text.unicode_at(i) < 32:
					return false
				if ch == '"':
					i += 1
					closed = true
					break
				if ch == "\\":
					i += 1
					if i >= text.length():
						return false
					ch = text[i]
					if ch == "u":
						var point: int = _hex4(text, i + 1)
						if point <= 0:
							return false
						i += 5
						if point >= 55296 and point <= 56319:
							if text.substr(i, 2) != "\\u":
								return false
							var low: int = _hex4(text, i + 2)
							if low < 56320 or low > 57343:
								return false
							i += 6
						elif point >= 56320 and point <= 57343:
							return false
						continue
					if not ch in ['"', "\\", "/", "b", "f", "n", "r", "t"]:
						return false
				i += 1
			if not closed:
				return false
			previous = '"'
			continue
		if ch == "{" or ch == "[":
			stack.append(ch)
			if stack.size() > 4:
				return false
		elif ch == "}" or ch == "]":
			if previous == "," or stack.is_empty() or stack.pop_back() != ("{" if ch == "}" else "["):
				return false
		elif ch == "-" or ch in "0123456789":
			var start: int = i
			while i < text.length() and text[i] in "0123456789eE+.-":
				i += 1
			if not _json_number(text.substr(start, i - start)):
				return false
			previous = "0"
			continue
		elif ch in "tfn":
			var keyword: String = "true" if ch == "t" else "false" if ch == "f" else "null"
			if text.substr(i, keyword.length()) != keyword:
				return false
			i += keyword.length()
			previous = "0"
			continue
		elif ch != ":" and ch != ",":
			return false
		previous = ch
		i += 1
	return stack.is_empty()


static func _hex4(text: String, start: int) -> int:
	if start + 4 > text.length():
		return -1
	var result: int = 0
	for i: int in range(start, start + 4):
		var digit: int = "0123456789abcdef".find(text[i].to_lower())
		if digit < 0:
			return -1
		result = result * 16 + digit
	return result


static func _json_number(text: String) -> bool:
	if text.is_empty() or text.length() > 32:
		return false
	var i: int = 1 if text[0] == "-" else 0
	if i >= text.length():
		return false
	if text[i] == "0":
		i += 1
	else:
		if not text[i] in "123456789":
			return false
		while i < text.length() and text[i] in "0123456789":
			i += 1
	if i < text.length() and text[i] == ".":
		i += 1
		var start: int = i
		while i < text.length() and text[i] in "0123456789":
			i += 1
		if i == start:
			return false
	if i < text.length() and text[i] in "eE":
		i += 1
		if i < text.length() and text[i] in "+-":
			i += 1
		var start: int = i
		while i < text.length() and text[i] in "0123456789":
			i += 1
		# Schema numbers are tiny integers. This generous exponent bound keeps
		# even a 32-digit mantissa finite before native numeric conversion.
		if i == start or i - start > 2 or text.substr(start, i - start).to_int() > 32:
			return false
	return i == text.length()
