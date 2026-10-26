extends TestCase
## The OPEN sign uses the approved dedicated linear neon red material.

const SOURCE_DARK: String = "res://assets/kenney/furniture/wall.glb"
const SOURCE_CHROME: String = "res://assets/kenney/furniture/lampWall.glb"
const OPEN_SIGN: String = "res://assets/made/diner/diner_open_sign.glb"
const STRENGTH_EXTENSION: String = "KHR_materials_emissive_strength"
const PUNCTUAL_LIGHTS_EXTENSION: String = "KHR_lights_punctual"
const NEON_ALBEDO: Array[float] = [0.70, 0.015, 0.02]
const NEON_EMISSION: Array[float] = [0.35, 0.0075, 0.01]


func test_open_sign_uses_dedicated_linear_neon_red_and_preserves_kit_accents() -> void:
	var dark_source: Dictionary = _read_glb_json(SOURCE_DARK)
	var chrome_source: Dictionary = _read_glb_json(SOURCE_CHROME)
	var sign: Dictionary = _read_glb_json(OPEN_SIGN)
	if dark_source.is_empty() or chrome_source.is_empty() or sign.is_empty():
		return
	var neon_material: Dictionary = _material_named(sign, "carpet_emissive")
	var dark_source_material: Dictionary = _material_named(dark_source, "metalDark")
	var dark_sign_material: Dictionary = _material_named(sign, "metalDark")
	var chrome_source_material: Dictionary = _material_named(chrome_source, "metal")
	var chrome_sign_material: Dictionary = _material_named(sign, "metal")
	assert_false(neon_material.is_empty(), "OPEN GLB contains the carpet_emissive tube material")
	assert_false(dark_source_material.is_empty(), "wall kit GLB contains the metalDark material")
	assert_false(dark_sign_material.is_empty(), "OPEN GLB contains its unchanged metalDark housing")
	assert_false(chrome_source_material.is_empty(), "lamp kit GLB contains the metal material")
	assert_false(chrome_sign_material.is_empty(), "OPEN GLB contains its unchanged metal brackets")
	if neon_material.is_empty() or dark_source_material.is_empty() or dark_sign_material.is_empty() \
			or chrome_source_material.is_empty() or chrome_sign_material.is_empty():
		return
	var albedo_rgb: Array[float] = _factor_rgb(neon_material, "baseColorFactor", "OPEN sign neon albedo")
	var emission_rgb: Array[float] = _factor_rgb(neon_material, "emissiveFactor", "OPEN sign neon emission")
	var dark_source_rgb: Array[float] = _factor_rgb(dark_source_material, "baseColorFactor", "wall kit metalDark")
	var dark_sign_rgb: Array[float] = _factor_rgb(dark_sign_material, "baseColorFactor", "sign metalDark housing")
	var chrome_source_rgb: Array[float] = _factor_rgb(chrome_source_material, "baseColorFactor", "lamp kit metal")
	var chrome_sign_rgb: Array[float] = _factor_rgb(chrome_sign_material, "baseColorFactor", "sign metal brackets")
	if albedo_rgb.size() != 3 or emission_rgb.size() != 3 or dark_source_rgb.size() != 3 \
			or dark_sign_rgb.size() != 3 or chrome_source_rgb.size() != 3 or chrome_sign_rgb.size() != 3:
		return
	for channel: int in range(3):
		assert_almost_eq(albedo_rgb[channel], NEON_ALBEDO[channel], 0.000001,
			"neon albedo channel %d is the approved linear value" % channel)
		assert_almost_eq(emission_rgb[channel], NEON_EMISSION[channel], 0.000001,
			"neon emission channel %d is the approved linear value" % channel)
		assert_almost_eq(dark_sign_rgb[channel], dark_source_rgb[channel], 0.000001,
			"non-glowing housing channel %d retains its kit colour" % channel)
		assert_almost_eq(chrome_sign_rgb[channel], chrome_source_rgb[channel], 0.000001,
			"non-glowing bracket channel %d retains its kit colour" % channel)
	var extensions: Variant = neon_material.get("extensions", {})
	assert_true(extensions is Dictionary, "material extensions, when present, are an object")
	if not extensions is Dictionary:
		return
	var strength_data: Variant = extensions.get(STRENGTH_EXTENSION)
	if strength_data != null:
		assert_true(strength_data is Dictionary, "KHR emissive strength is an object when present")
		if not strength_data is Dictionary:
			return
		var strength_value: Variant = strength_data.get("emissiveStrength")
		assert_true(_is_number(strength_value), "emissiveStrength is a finite number")
		if not _is_number(strength_value):
			return
		assert_almost_eq(float(strength_value), 1.0, 0.000001,
			"the approved emission vector is used directly at default strength")
		var extensions_used: Variant = sign.get("extensionsUsed", [])
		assert_true(extensions_used is Array and extensions_used.has(STRENGTH_EXTENSION),
			"the sign declares its material-strength extension")
	assert_false(_contains_token(sign, PUNCTUAL_LIGHTS_EXTENSION),
		"the OPEN sign adds no KHR_lights_punctual component")


func test_neon_albedo_is_deeper_than_emission_for_two_tone_tube_shading() -> void:
	for channel: int in range(3):
		assert_true(NEON_ALBEDO[channel] > NEON_EMISSION[channel],
			"tube albedo channel %d stays deeper than its emission" % channel)


func _read_glb_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "GLB opens: " + path)
	if file == null:
		return {}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 20:
		assert_true(false, "GLB has a complete binary header: " + path)
		return {}
	assert_eq(bytes.slice(0, 4), PackedByteArray([0x67, 0x6c, 0x54, 0x46]), "GLB magic: " + path)
	assert_eq(bytes.decode_u32(4), 2, "GLB version 2: " + path)
	assert_eq(bytes.decode_u32(8), bytes.size(), "GLB declared length matches file: " + path)
	var json_length: int = int(bytes.decode_u32(12))
	assert_eq(bytes.slice(16, 20), PackedByteArray([0x4a, 0x53, 0x4f, 0x4e]), "first GLB chunk is JSON: " + path)
	if json_length <= 0 or 20 + json_length > bytes.size():
		assert_true(false, "GLB JSON chunk fits inside the file: " + path)
		return {}
	var json_chunk: PackedByteArray = bytes.slice(20, 20 + json_length)
	var parsed: Variant = JSON.parse_string(json_chunk.get_string_from_utf8())
	assert_true(parsed is Dictionary, "GLB JSON chunk parses: " + path)
	return parsed if parsed is Dictionary else {}


func _material_named(document: Dictionary, expected_name: String) -> Dictionary:
	var materials: Variant = document.get("materials", [])
	assert_true(materials is Array, "GLB declares a materials array")
	if not materials is Array:
		return {}
	for value: Variant in materials:
		if value is Dictionary and value.get("name") == expected_name:
			return value
	return {}


func _factor_rgb(material: Dictionary, factor_name: String, label: String) -> Array[float]:
	var raw: Variant
	if factor_name == "baseColorFactor":
		var pbr: Variant = material.get("pbrMetallicRoughness", {})
		raw = pbr.get(factor_name) if pbr is Dictionary else null
	else:
		raw = material.get(factor_name)
	assert_true(raw is Array and raw.size() >= 3, label + " has an RGB factor")
	var result: Array[float] = []
	if not raw is Array or raw.size() < 3:
		return result
	for channel: int in range(3):
		assert_true(_is_number(raw[channel]), label + " channel %d is finite" % channel)
		if not _is_number(raw[channel]):
			return []
		result.append(float(raw[channel]))
	return result


func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _contains_token(value: Variant, token: String) -> bool:
	if value is String:
		return value == token
	if value is Dictionary:
		if value.has(token):
			return true
		for child: Variant in value.values():
			if _contains_token(child, token):
				return true
	elif value is Array:
		for child: Variant in value:
			if _contains_token(child, token):
				return true
	return false
