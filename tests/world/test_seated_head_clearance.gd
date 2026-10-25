extends TestCase
## PR147 native measurement and catalogue regressions. A failure is an authored
## seat/pose defect to fix; never weaken the 0.02 rule or auto-fit the fixture.

const GEOMETRY: GDScript = preload("res://tools/seated_head_geometry.gd")
const CATALOGUE: GDScript = preload("res://tools/seated_head_catalogue.gd")
const PERSON: PackedScene = preload("res://assets/people/person.tscn")


func test_every_catalogue_seat_clears_real_sitting_head_in_all_rotations_and_guest_looks() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var report: Dictionary = await CATALOGUE.run(tree.root)
	assert_eq(report["errors"], PackedStringArray())
	assert_true(int(report["seats"]) >= 13, "includes standalone seats and every built-in table seat")
	var coverage: Dictionary[String, bool] = {}
	for sample: Dictionary in report["samples"]:
		var context: String = "%s %s turns=%d cell=%s sit_t=%.5f" % [sample["item"], sample["model"], sample["turns"], sample["seat_cell"], sample["sit_time"]]
		assert_eq(sample.get("error", "missing result"), "", context)
		if not String(sample.get("error", "missing result")).is_empty():
			continue
		coverage[String(sample["item"])] = true
		assert_true(int(sample["head_vertices"]) > 0, context)
		assert_true(int(sample["seat_triangles"]) > 0, context)
		assert_true(float(sample["facing_dot"]) > 0.9999, context + " faces its table")
		assert_eq(sample["intersecting_triangles"], 0, context + " head bounds intersect seat geometry")
		assert_false(sample["head_center_inside_seat"], context + " head is enclosed by seat geometry")
		assert_true(float(sample["clearance"]) + GEOMETRY.EPSILON >= GEOMETRY.REQUIRED_CLEARANCE,
			context + " rear clearance %.6f must be >=0.02" % sample["clearance"])
	for required: String in ["chair", "wooden_chair", "rounded_chair", "modern_chair", "modern_frame_chair",
		"bar_stool", "square_bar_stool", "bench", "cushioned_bench", "lounge_chair", "diner_booth", "diner_stool", "table_2"]:
		assert_true(coverage.has(required), required + " was actually measured")


func test_triangle_clipping_catches_face_crossing_head_with_all_vertices_outside() -> void:
	var head: AABB = AABB(Vector3(-0.1, 0.5, -0.1), Vector3(0.2, 0.2, 0.2))
	var crossing: PackedVector3Array = [Vector3(-1, 0, 0.05), Vector3(1, 0, 0.05), Vector3(0, 2, 0.05)]
	var result: Dictionary = GEOMETRY.measure_triangles(head, crossing)
	assert_true(int(result["intersecting_triangles"]) > 0)
	assert_true(float(result["clearance"]) < 0.0)
	assert_false(result["passes"], "checking only seat vertices misses this clipping face")


func test_clearance_threshold_and_enclosed_head_cannot_pass_without_boundary_contact() -> void:
	var head: AABB = AABB(Vector3(-0.1, 0.5, -0.1), Vector3(0.2, 0.2, 0.2))
	var backrest: BoxMesh = BoxMesh.new()
	backrest.size = Vector3(0.8, 1.0, 0.1)
	for front: float in [0.119, 0.12, 0.121]:
		var triangles: PackedVector3Array = []
		for vertex: Vector3 in backrest.get_faces():
			triangles.append(vertex + Vector3(0.0, 0.6, front + 0.05))
		var result: Dictionary = GEOMETRY.measure_triangles(head, triangles)
		assert_almost_eq(float(result["clearance"]), front - head.end.z, 0.000001)
		assert_eq(result["passes"], front >= 0.12, "0.02 is a measured geometric threshold")
	var enclosing: BoxMesh = BoxMesh.new()
	enclosing.size = Vector3.ONE * 2.0
	var enclosing_triangles: PackedVector3Array = []
	for vertex: Vector3 in enclosing.get_faces():
		enclosing_triangles.append(vertex + head.get_center())
	var enclosed: Dictionary = GEOMETRY.measure_triangles(head, enclosing_triangles)
	assert_eq(enclosed["intersecting_triangles"], 0)
	assert_true(enclosed["head_center_inside_seat"])
	assert_false(enclosed["passes"], "a head fully inside a closed seat part is still clipping")


func test_skinning_resolves_bind_names_and_applies_inverse_bind_before_current_pose() -> void:
	var skeleton: Skeleton3D = Skeleton3D.new()
	skeleton.add_bone("unrelated")
	skeleton.add_bone("head")
	var pose: Transform3D = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 2, 0))
	skeleton.set_bone_pose_position(1, pose.origin)
	skeleton.set_bone_pose_rotation(1, pose.basis.get_rotation_quaternion())
	var bind: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0, -1, 0))
	var skin: Skin = Skin.new()
	skin.add_named_bind("head", bind)
	skin.set_bind_bone(0, 0) # Must not win over the named bind to head=1.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var original: PackedVector3Array = [Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(-1, 1, 0)]
	arrays[Mesh.ARRAY_VERTEX] = original
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.skin = skin
	var result: Dictionary = GEOMETRY.skin_vertices(instance, skeleton)
	assert_eq(result["error"], "")
	var vertices: PackedVector3Array = result["vertices"]
	assert_eq(vertices.size(), original.size())
	for index: int in range(vertices.size()):
		assert_true(vertices[index].distance_to(pose * bind * original[index]) < 0.00001,
			"bone pose, inverse bind, and vertex multiply in render order")
	instance.free()
	skeleton.free()


func test_native_sit_changes_measured_head_vertices_instead_of_reusing_rest_aabb() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var person: PersonView = PERSON.instantiate() as PersonView
	tree.root.add_child(person)
	assert_true(person.set_look(&"customer", 0))
	var mesh: MeshInstance3D = GEOMETRY.head_mesh(person)
	var standing: Dictionary = GEOMETRY.skin_vertices(mesh, person._skeleton)
	assert_eq(standing["error"], "")
	assert_true(person.set_pose(false, true, false, false, 0.264))
	person._player.seek(0.37, true)
	var sitting: Dictionary = GEOMETRY.skin_vertices(mesh, person._skeleton)
	assert_eq(sitting["error"], "")
	var before: PackedVector3Array = standing["vertices"]
	var after: PackedVector3Array = sitting["vertices"]
	assert_eq(before.size(), after.size())
	assert_true(before.size() > 0)
	if not before.is_empty() and not after.is_empty():
		assert_true(before[0].distance_to(after[0]) > 0.01, "real sit root translation changes the head geometry")
	assert_eq((person.get_node("ModelPivot") as Node3D).scale, Vector3.ONE * ArtScale.CHARACTER_SCALE)
	person.free()
