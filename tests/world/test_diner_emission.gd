extends TestCase
## The OPEN sign uses the source carpet red as its emissive colour at 35% strength.

const SOURCE_CARPET: String = "res://assets/kenney/furniture/benchCushion.glb"
const OPEN_SIGN: String = "res://assets/made/diner/diner_open_sign.glb"
const STRENGTH_EXTENSION: String = "KHR_materials_emissive_strength"
const PUNCTUAL_LIGHTS_EXTENSION: String = "KHR_lights_punctual"
const EMISSION_STRENGTH: float = 0.35


func test_open_sign_emission_preserves_source_carpet_red_at_35_percent() -> void:
	var source: Dictionary = _read_glb_json(SOURCE_CARPET)
	var sign: Dictionary = _read_glb_json(OPEN_SIGN)
	if source.is_empty() or sign.is_empty():
		return
	var source_material: Dictionary = _material_named(source, "carpet")
	var sign_material: Dictionary = _material_named(sign, "carpet_emissive")
	assert_false(source_material.is_empty(), "source GLB contains the carpet material")
	assert_false(sign_material.is_empty(), "OPEN GLB contains the carpet_emissive material")
	if source_material.is_empty() or sign_material.is_empty():
		return
	var source_rgb: Array[float] = _factor_rgb(source_material, "baseColorFactor", "source carpet")
	var emission_rgb: Array[float] = _factor_rgb(sign_material, "emissiveFactor", "OPEN sign emission")
	if source_rgb.size() != 3 or emission_rgb.size() != 3:
		return
	var extensions: Variant = sign_material.get("extensions", {})
	var strength_data: Variant = extensions.get(STRENGTH_EXTENSION) if extensions is Dictionary else null
	assert_true(strength_data is Dictionary, "emission strength is authored with KHR_materials_emissive_strength")
	if not strength_data is Dictionary:
		return
	var strength_value: Variant = strength_data.get("emissiveStrength")
	assert_true(_is_number(strength_value), "emissiveStrength is a finite number")
	if not _is_number(strength_value):
		return
	var strength: float = float(strength_value)
	assert_almost_eq(strength, EMISSION_STRENGTH, 0.000001, "emission energy remains modest at 35%")
	var extensions_used: Variant = sign.get("extensionsUsed", [])
	assert_true(extensions_used is Array and extensions_used.has(STRENGTH_EXTENSION),
		"the sign declares its material-strength extension")
	for channel: int in range(3):
		assert_almost_eq(emission_rgb[channel], source_rgb[channel], 0.000001,
			"emissive channel %d keeps the source carpet colour without a white blend" % channel)
		assert_almost_eq(emission_rgb[channel] * strength, source_rgb[channel] * EMISSION_STRENGTH,
			0.000001, "effective emissive channel %d equals source carpet at 35%%" % channel)
	assert_false(_contains_token(sign, PUNCTUAL_LIGHTS_EXTENSION),
		"the OPEN sign adds no KHR_lights_punctual component")


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
	assert_eq(bytes.decode_u32(4, false), 2, "GLB version 2: " + path)
	assert_eq(bytes.decode_u32(8, false), bytes.size(), "GLB declared length matches file: " + path)
	var json_length: int = int(bytes.decode_u32(12, false))
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
