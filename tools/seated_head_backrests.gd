class_name SeatedHeadBackrests
extends RefCounted
## Exact, source-pinned face classification. Numerical clearance stays in the
## geometry oracle. Selected triangles always come from the actual native mesh.

const MANIFEST_PATH: String = "res://tools/seated_head_backrests.json"


static func select(instance: MeshInstance3D) -> Dictionary:
	if instance == null or instance.mesh == null:
		return _result(false, "Native seat mesh is unavailable")
	if not FileAccess.file_exists(MANIFEST_PATH):
		return _result(false, "Backrest classification manifest is unavailable")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not manifest is Dictionary:
		return _result(false, "Invalid backrest classification manifest")
	var schema: Variant = manifest.get("schema")
	if (typeof(schema) != TYPE_INT and typeof(schema) != TYPE_FLOAT) or schema != 2 \
			or not manifest.get("sources") is Dictionary:
		return _result(false, "Invalid backrest classification manifest")
	var sources: Dictionary = manifest["sources"]
	var scene_source: String = ""
	var cursor: Node = instance
	while cursor != null:
		if cursor.scene_file_path.to_lower().ends_with(".glb"):
			scene_source = cursor.scene_file_path
			break
		cursor = cursor.get_parent()
	var resolution: Dictionary = resolve_source_paths(instance.mesh.resource_path, scene_source, sources)
	if not resolution["available"] or not String(resolution["error"]).is_empty():
		return _result(resolution["available"], resolution["error"])
	var source: String = resolution["source"]
	if not source.begins_with("res://") or not source.to_lower().ends_with(".glb"):
		return _result(true, "Classified source must be a native res:// GLB")
	if not sources[source] is Dictionary:
		return _result(true, "Invalid backrest source entry")
	if not FileAccess.file_exists(source):
		return _result(true, "Classified GLB is unavailable")
	return validate_and_select(instance.mesh.get_faces(), FileAccess.get_sha256(source), sources[source])


## Resource subpaths and nearest imported GLB ancestors are independently
## useful provenance. Two different known sources may never pick a winner.
static func resolve_source_paths(mesh_resource_path: String, scene_file_path: String,
		sources: Dictionary) -> Dictionary:
	var mesh_source: String = mesh_resource_path.get_slice("::", 0)
	var known_mesh: bool = sources.has(mesh_source)
	var known_scene: bool = sources.has(scene_file_path)
	var explicit_mesh_glb: bool = mesh_source.begins_with("res://") and mesh_source.to_lower().ends_with(".glb")
	var explicit_scene_glb: bool = scene_file_path.begins_with("res://") and scene_file_path.to_lower().ends_with(".glb")
	if explicit_mesh_glb and explicit_scene_glb and mesh_source != scene_file_path:
		return {"available": true, "error": "Native mesh and imported scene identify different GLB sources", "source": ""}
	if known_mesh and known_scene and mesh_source != scene_file_path:
		return {"available": true, "error": "Native mesh and imported scene identify different classified sources", "source": ""}
	return {"available": known_mesh or known_scene, "error": "",
		"source": mesh_source if known_mesh else (scene_file_path if known_scene else "")}


## Pure validation for tests and audit tooling. Both native and manifest faces
## are mesh-local, without node transforms. Exact multisets retain duplicates;
## winding and face enumeration may differ after native import.
static func validate_and_select(native_faces: PackedVector3Array, source_sha256: String,
		source: Dictionary) -> Dictionary:
	var expected_hash: Variant = source.get("sha256")
	if not expected_hash is String or expected_hash.length() != 64 \
			or not expected_hash.is_valid_hex_number() or source_sha256.length() != 64 \
			or not source_sha256.is_valid_hex_number() or expected_hash.to_lower() != source_sha256.to_lower():
		return _result(true, "Classified GLB hash differs or is invalid")
	if not source.get("audit") is String or String(source["audit"]).strip_edges().is_empty():
		return _result(true, "Backrest source needs an audit description")
	if not source.get("faces") is Array or not source.get("backrest_faces") is Array:
		return _result(true, "Invalid backrest face manifest")
	var authored: Array = source["faces"]
	var selected: Array = source["backrest_faces"]
	if authored.is_empty() or selected.is_empty() or selected.size() >= authored.size():
		return _result(true, "Backrest selection must be a nonempty proper face subset")
	if native_faces.is_empty() or native_faces.size() % 3 != 0 or native_faces.size() / 3 != authored.size():
		return _result(true, "Native full face inventory differs")
	var native_by_key: Dictionary[String, Array] = {}
	for triangle: int in authored.size():
		var offset: int = triangle * 3
		for vertex: int in range(offset, offset + 3):
			if not native_faces[vertex].is_finite():
				return _result(true, "Native face coordinates must be finite")
		var key: String = _triangle_key(native_faces[offset], native_faces[offset + 1], native_faces[offset + 2])
		if not native_by_key.has(key):
			native_by_key[key] = []
		(native_by_key[key] as Array).append(triangle)
	var matched_native: Array[int] = []
	for value: Variant in authored:
		# IEEE-754 float32 bytes preserve the GLB positions exactly. Decimal JSON
		# parsing cannot reliably retain those source bits, especially near zero.
		if not value is String or value.length() != 72 or not value.is_valid_hex_number():
			return _result(true, "Every authored face must encode nine float32 coordinates")
		var face: PackedFloat32Array = value.hex_decode().to_float32_array()
		var a: Vector3 = Vector3(face[0], face[1], face[2])
		var b: Vector3 = Vector3(face[3], face[4], face[5])
		var c: Vector3 = Vector3(face[6], face[7], face[8])
		if not a.is_finite() or not b.is_finite() or not c.is_finite():
			return _result(true, "Authored coordinates must be finite")
		# Mesh.get_faces() uses TriangleMesh::create, which snaps source vertices
		# at exactly 0.0001 before welding. Match that engine conversion, not an
		# approximate distance tolerance. Clearance still uses actual native faces.
		# Godot ed1daf0bf core/math/triangle_mesh.cpp:127.
		var key: String = _triangle_key(a.snappedf(0.0001), b.snappedf(0.0001), c.snappedf(0.0001))
		if not native_by_key.has(key) or (native_by_key[key] as Array).is_empty():
			return _result(true, "Native full face topology differs from the pinned inventory")
		var matches: Array = native_by_key[key]
		matched_native.append(int(matches.pop_front()))
	for key: String in native_by_key:
		if not (native_by_key[key] as Array).is_empty():
			return _result(true, "Native full face topology has unmatched faces")
	var seen: Dictionary[int, bool] = {}
	var selection_bytes: PackedInt64Array = []
	var actual: PackedVector3Array = []
	for value: Variant in selected:
		# JSON.parse_string represents JSON integers as numeric floats as well as
		# native ints; accept only exact integral, finite, in-range values.
		if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) \
				or float(value) != floorf(float(value)) or value < 0 or value >= authored.size():
			return _result(true, "Backrest face index must be a unique in-range integer")
		var index: int = int(value)
		if seen.has(index):
			return _result(true, "Backrest face selection contains duplicate indices")
		seen[index] = true
		selection_bytes.append(index)
		var offset: int = matched_native[index] * 3
		actual.append_array(native_faces.slice(offset, offset + 3))
	return {"available": true, "error": "", "triangles": actual,
		"identity": source_sha256.to_lower() + ":" + selection_bytes.to_byte_array().hex_encode()}


static func _triangle_key(a: Vector3, b: Vector3, c: Vector3) -> String:
	var points: Array[Vector3] = [a, b, c]
	points.sort_custom(_point_before)
	var canonical: PackedVector3Array = []
	for point: Vector3 in points:
		# Signed zero is numerically equal; retain all other native float bits.
		canonical.append(Vector3(0.0 if point.x == 0.0 else point.x,
			0.0 if point.y == 0.0 else point.y, 0.0 if point.z == 0.0 else point.z))
	return canonical.to_byte_array().hex_encode()


static func _point_before(a: Vector3, b: Vector3) -> bool:
	return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))


static func _result(available: bool, error: String) -> Dictionary:
	return {"available": available, "error": error, "triangles": PackedVector3Array(), "identity": ""}
