extends TestCase
## Synthetic exact mesh-local inventories; no seat-fit measurements are claimed.

const CLASSIFIER: Script = preload("res://tools/seated_head_backrests.gd")
const SOURCE_SHA: String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"


func test_all_eight_reviewed_sources_match_their_actual_imported_mesh_inventory() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLASSIFIER.MANIFEST_PATH))
	var sources: Dictionary = manifest["sources"]
	assert_eq(sources.size(), 16, "every reviewed kit source and its derived lowered-backrest seat is exercised")
	for path: String in sources:
		var scene: PackedScene = load(path) as PackedScene
		assert_not_null(scene, path)
		if scene == null:
			continue
		var imported: Node = scene.instantiate()
		var meshes: Array[Node] = imported.find_children("*", "MeshInstance3D", true, false)
		assert_eq(meshes.size(), 1, path + " has its reviewed single mesh")
		for node: Node in meshes:
			var mesh: MeshInstance3D = node as MeshInstance3D
			var result: Dictionary = CLASSIFIER.select(mesh)
			assert_true(result["available"], path)
			assert_eq(result["error"], "", path)
			assert_eq((result["triangles"] as PackedVector3Array).size(),
				(sources[path]["backrest_faces"] as Array).size() * 3, path)
			assert_true(String(result["identity"]).begins_with(String(sources[path]["sha256"]) + ":"), path)
		imported.free()


func test_float32_source_bits_survive_json_and_engine_face_snapping() -> void:
	var source: Dictionary = _source()
	source["faces"][0] = _face([0.030000001192092896, 0, 0, 1, 0, 0, 0, 1, 0])
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(source))
	assert_eq(parsed["faces"], source["faces"], "JSON retains every source float32 bit")
	var native: PackedVector3Array = _native_faces(source)
	for index: int in native.size():
		native[index] = native[index].snappedf(0.0001)
	_assert_valid(CLASSIFIER.validate_and_select(native, SOURCE_SHA, parsed))
	var changed_native: PackedVector3Array = native.duplicate()
	changed_native[0] += Vector3(0.0001, 0.0, 0.0)
	_assert_rejected(CLASSIFIER.validate_and_select(changed_native, SOURCE_SHA, parsed))
	var forged: Dictionary = source.duplicate(true)
	forged["faces"][0] = _face([0.031, 0, 0, 1, 0, 0, 0, 1, 0])
	_assert_rejected(CLASSIFIER.validate_and_select(native, SOURCE_SHA, forged))


func test_source_resolution_accepts_native_resource_or_nearest_imported_root_and_rejects_conflicts() -> void:
	var sources: Dictionary = {"res://a.glb": {}, "res://b.glb": {}}
	var native: Dictionary = CLASSIFIER.resolve_source_paths("res://a.glb::ArrayMesh_example", "", sources)
	assert_true(native["available"])
	assert_eq(native["source"], "res://a.glb")
	var imported: Dictionary = CLASSIFIER.resolve_source_paths("res://.godot/imported/a.scn::ArrayMesh", "res://a.glb", sources)
	assert_true(imported["available"])
	assert_eq(imported["source"], "res://a.glb")
	var same: Dictionary = CLASSIFIER.resolve_source_paths("res://a.glb::ArrayMesh", "res://a.glb", sources)
	assert_eq(same["error"], "")
	var unknown: Dictionary = CLASSIFIER.resolve_source_paths("res://unknown.glb::ArrayMesh", "res://unknown.glb", sources)
	assert_false(unknown["available"])
	assert_eq(unknown["error"], "")
	var conflict: Dictionary = CLASSIFIER.resolve_source_paths("res://a.glb::ArrayMesh", "res://b.glb", sources)
	assert_true(conflict["available"])
	assert_false(String(conflict["error"]).is_empty())
	assert_eq(conflict["source"], "")
	var unknown_mesh: Dictionary = CLASSIFIER.resolve_source_paths("res://unknown.glb::ArrayMesh", "res://a.glb", sources)
	assert_true(unknown_mesh["available"])
	assert_false(String(unknown_mesh["error"]).is_empty(), "a known ancestor cannot authorize another actual GLB")
	assert_eq(unknown_mesh["source"], "")
	var unknown_ancestor: Dictionary = CLASSIFIER.resolve_source_paths("res://a.glb::ArrayMesh", "res://unknown.glb", sources)
	assert_true(unknown_ancestor["available"])
	assert_false(String(unknown_ancestor["error"]).is_empty())
	assert_eq(unknown_ancestor["source"], "")


func test_selection_returns_actual_native_winding_after_full_inventory_order_changes() -> void:
	var source: Dictionary = _source()
	var native: PackedVector3Array = _native_faces(source)
	var reordered: PackedVector3Array = []
	for triangle: int in [2, 1, 0] as Array[int]:
		for vertex: int in [2, 1, 0] as Array[int]:
			reordered.append(native[triangle * 3 + vertex])
	var result: Dictionary = CLASSIFIER.validate_and_select(reordered, SOURCE_SHA, source)
	_assert_valid(result)
	assert_eq(result["triangles"], reordered.slice(3, 6), "selected geometry retains native winding, not manifest triangles")
	var original: Dictionary = CLASSIFIER.validate_and_select(native, SOURCE_SHA, source)
	assert_eq(result["identity"], original["identity"], "native enumeration does not change source/selection identity")
	assert_eq(source, _source(), "classification never edits its manifest input")


func test_full_inventory_detects_unselected_mutation_missing_selection_and_different_triangulation() -> void:
	var source: Dictionary = _source()
	var native: PackedVector3Array = _native_faces(source)
	var unselected: PackedVector3Array = native.duplicate()
	unselected[8] += Vector3(0.125, 0.0, 0.0)
	_assert_rejected(CLASSIFIER.validate_and_select(unselected, SOURCE_SHA, source))
	var missing_selected: PackedVector3Array = native.slice(0, 3)
	missing_selected.append_array(native.slice(6, 9))
	_assert_rejected(CLASSIFIER.validate_and_select(missing_selected, SOURCE_SHA, source))
	var replaced_selected: PackedVector3Array = native.duplicate()
	for vertex: int in 3:
		replaced_selected[3 + vertex] = native[6 + vertex]
	_assert_rejected(CLASSIFIER.validate_and_select(replaced_selected, SOURCE_SHA, source))
	var changed_topology: PackedVector3Array = native.duplicate()
	var swap: Vector3 = changed_topology[2]
	changed_topology[2] = changed_topology[5]
	changed_topology[5] = swap
	_assert_rejected(CLASSIFIER.validate_and_select(changed_topology, SOURCE_SHA, source))


func test_duplicate_geometry_is_counted_exactly_and_selection_indices_stay_unique() -> void:
	var source: Dictionary = _source()
	source["faces"] = [source["faces"][0], source["faces"][0], source["faces"][2]]
	var native: PackedVector3Array = _native_faces(source)
	_assert_valid(CLASSIFIER.validate_and_select(native, SOURCE_SHA, source))
	var wrong_multiplicity: PackedVector3Array = native.duplicate()
	for vertex: int in 3:
		wrong_multiplicity[3 + vertex] = native[6 + vertex]
	_assert_rejected(CLASSIFIER.validate_and_select(wrong_multiplicity, SOURCE_SHA, source))
	var second: Dictionary = CLASSIFIER.validate_and_select(native, SOURCE_SHA, source)
	source["backrest_faces"] = [0]
	var first: Dictionary = CLASSIFIER.validate_and_select(native, SOURCE_SHA, source)
	assert_eq(first["triangles"], second["triangles"])
	assert_ne(first["identity"], second["identity"], "selection identity retains exact original face indices")
	source["backrest_faces"] = [0, 0]
	_assert_rejected(CLASSIFIER.validate_and_select(native, SOURCE_SHA, source))


func test_source_hash_audit_shape_coordinate_and_subset_errors_fail_closed() -> void:
	var source: Dictionary = _source()
	var native: PackedVector3Array = _native_faces(source)
	_assert_rejected(CLASSIFIER.validate_and_select(native, "f".repeat(64), source))
	for value: Variant in [null, "", "not-a-sha", true]:
		var malformed: Dictionary = source.duplicate(true)
		malformed["sha256"] = value
		_assert_rejected(CLASSIFIER.validate_and_select(native, SOURCE_SHA, malformed))
	for value: Variant in [null, "", " ", true]:
		var malformed: Dictionary = source.duplicate(true)
		malformed["audit"] = value
		_assert_rejected(CLASSIFIER.validate_and_select(native, SOURCE_SHA, malformed))
	for value: Variant in [null, [], [0, 1, 2], [-1], [3], [0.5], [true], [NAN], [INF]]:
		var malformed: Dictionary = source.duplicate(true)
		malformed["backrest_faces"] = value
		_assert_rejected(CLASSIFIER.validate_and_select(native, SOURCE_SHA, malformed))
	for value: Variant in [null, [], [0, 1, 2], true]:
		var malformed: Dictionary = source.duplicate(true)
		malformed["faces"] = value
		_assert_rejected(CLASSIFIER.validate_and_select(native, SOURCE_SHA, malformed))
	for value: Variant in [null, true, "0", NAN, INF]:
		var malformed: Dictionary = source.duplicate(true)
		malformed["faces"][0] = value
		_assert_rejected(CLASSIFIER.validate_and_select(native, SOURCE_SHA, malformed))
	for value: String in ["00", "g".repeat(72), _face([NAN, 0, 0, 1, 0, 0, 0, 1, 0]), _face([INF, 0, 0, 1, 0, 0, 0, 1, 0])]:
		var malformed: Dictionary = source.duplicate(true)
		malformed["faces"][0] = value
		_assert_rejected(CLASSIFIER.validate_and_select(native, SOURCE_SHA, malformed))
	var invalid_native: PackedVector3Array = native.duplicate()
	invalid_native[0] = Vector3(NAN, 0.0, 0.0)
	_assert_rejected(CLASSIFIER.validate_and_select(invalid_native, SOURCE_SHA, source))


func test_validation_is_mesh_local_and_applies_no_instance_transform() -> void:
	var source: Dictionary = _source()
	var native: PackedVector3Array = _native_faces(source)
	var result: Dictionary = CLASSIFIER.validate_and_select(native, SOURCE_SHA, source)
	_assert_valid(result)
	assert_eq(result["triangles"], native.slice(3, 6))
	var moved: PackedVector3Array = []
	var transform: Transform3D = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(9.0, 2.0, -4.0))
	for vertex: Vector3 in native:
		moved.append(transform * vertex)
	_assert_rejected(CLASSIFIER.validate_and_select(moved, SOURCE_SHA, source))


func _source() -> Dictionary:
	return {"sha256": SOURCE_SHA, "audit": "synthetic selection only; no physical fit claim",
		"faces": [_face([0, 0, 0, 1, 0, 0, 0, 1, 0]),
			_face([0, 0, 1, 1, 0, 1, 0, 1, 1]), _face([0, 0, 2, 1, 0, 2, 0, 1, 2])],
		"backrest_faces": [1]}


func _face(coordinates: Array) -> String:
	return PackedFloat32Array(coordinates).to_byte_array().hex_encode()


func _native_faces(source: Dictionary) -> PackedVector3Array:
	var result: PackedVector3Array = []
	for encoded: String in source["faces"]:
		var face: PackedFloat32Array = encoded.hex_decode().to_float32_array()
		for offset: int in [0, 3, 6] as Array[int]:
			result.append(Vector3(face[offset], face[offset + 1], face[offset + 2]))
	return result


func _assert_valid(result: Dictionary) -> void:
	assert_true(result["available"])
	assert_eq(result["error"], "")
	assert_false((result["triangles"] as PackedVector3Array).is_empty())
	assert_true(String(result["identity"]).begins_with(SOURCE_SHA + ":"))


func _assert_rejected(result: Dictionary) -> void:
	assert_true(result["available"])
	assert_false(String(result["error"]).is_empty())
	assert_eq(result["triangles"], PackedVector3Array())
	assert_eq(result["identity"], "")
