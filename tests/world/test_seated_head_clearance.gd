extends TestCase
## Director 6404820766: actual head/backrest surfaces >=0.02, no penetration
## into any seat part, supported hips and <=0.05 offset. Kit exceptions are
## explicit item IDs with measured physical violations, never skipped geometry.

const GEOMETRY: GDScript = preload("res://tools/seated_head_geometry.gd")
const CATALOGUE: GDScript = preload("res://tools/seated_head_catalogue.gd")
const PERSON: PackedScene = preload("res://assets/people/person.tscn")


func test_every_catalogue_seat_is_measured_and_only_explicit_kit_failures_are_allowed() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var report: Dictionary = await CATALOGUE.run(tree.root)
	assert_eq(report["errors"], PackedStringArray())
	assert_true(report["coverage_complete"], "every expected case was measured exactly once without an error")
	assert_eq(report["expected_samples"], (report["samples"] as Array).size())
	assert_true(int(report["seats"]) >= 13, "includes standalone seats and every built-in table seat")
	assert_true((report["samples"] as Array).size() >= 1632)
	assert_eq(report["failures"], 0)
	assert_eq((report["known_kit_failures"] as Array).size(), CATALOGUE.KNOWN_KIT_FAILURE_IDS.size())
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
		assert_eq(sample["clearance_metric"], GEOMETRY.CLEARANCE_METRIC, context)
		assert_true(sample["accepted"], context)
		assert_true(float(sample["seated_forward_offset"]) <= 0.05 + GEOMETRY.EPSILON, context)
		if sample["known_kit_failure"]:
			assert_true(CATALOGUE.KNOWN_KIT_FAILURE_IDS.has(String(sample["item"])), context)
			continue
		assert_true(sample["passes"], context)
		assert_eq(sample["head_vertices_inside_count"], 0, context)
		assert_eq(sample["head_seat_surface_crossings"], 0, context)
		if sample["backrest_status"] == "backless":
			assert_null(sample["backrest_clearance"], context)
		else:
			assert_true(is_finite(float(sample["backrest_clearance"])), context)
			assert_true(float(sample["backrest_clearance"]) + GEOMETRY.EPSILON >= GEOMETRY.REQUIRED_CLEARANCE, context)
		if sample["item"] in ["diner_booth", "diner_stool"]:
			assert_true(sample["hips_supported"], context)
			assert_eq((sample["hip_support_points"] as Array).size(), 2, context)
	for required: String in ["chair", "wooden_chair", "rounded_chair", "modern_chair", "modern_frame_chair",
		"bar_stool", "square_bar_stool", "bench", "cushioned_bench", "lounge_chair", "diner_booth", "diner_stool", "table_2", "table_4"]:
		assert_true(coverage.has(required), required + " was actually measured")
	for finding: Dictionary in report["known_kit_failures"]:
		assert_true(int(finding["physical_violation_samples"]) > 0, String(finding["item"]))


## FK-083: every stool facing a serve-across counter piece is a seat, and the
## seated head must clear the counter itself (no head vertex inside any counter
## part, no head surface crossing one). Every counter, every rotation, every
## guest side, every guest model and sit time; each stool type at one rotation.
func test_heads_clear_the_counter_top_from_every_facing_stool() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var counters: Array[ItemDef] = []
	for definition: ItemDef in content.items():
		if definition.serve_across:
			counters.append(definition)
	assert_eq(counters.size(), 5, "the long counter plus section, both ends and the corner")
	var measured: int = 0
	var stools: Array[StringName] = [&"bar_stool", &"square_bar_stool", &"diner_stool"]
	for counter: ItemDef in counters:
		for turns: int in range(4):
			for stool_id: StringName in stools:
				if stool_id != &"bar_stool" and turns != 0:
					continue
				measured += await _measure_counter_heads(tree.root, counter, content.item(stool_id), turns)
	assert_true(measured >= 5 * 4 * 3 * PersonPresentation.GUEST_MODELS.size(), "every case was measured (%d)" % measured)


## Guest sides in unrotated cells: in front (-y) of every piece; the corner
## also on its +x side; the long counter on both long sides.
func _guest_sides(counter: ItemDef) -> Array[Vector2i]:
	if counter.id == &"bar_corner":
		return [Vector2i(0, -1), Vector2i(1, 0)] as Array[Vector2i]
	if counter.footprint == Vector2i(2, 1):
		return [Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 1), Vector2i(1, 1)] as Array[Vector2i]
	return [Vector2i(0, -1)] as Array[Vector2i]


func _measure_counter_heads(parent: Node, counter: ItemDef, stool: ItemDef, turns: int) -> int:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(12, 12)))
	var restaurant: RestaurantSim = RestaurantSim.new()
	restaurant.world = world
	var origin: Vector2i = Vector2i(4, 4)
	var placed: PlacedItem = world.grid.place_def(counter, origin, turns)
	assert_not_null(placed, "%s turns %d" % [counter.id, turns])
	if placed == null:
		return 0
	var guests: Array[CustomerAgent] = []
	for side: Vector2i in _guest_sides(counter):
		var cell: Vector2i = origin + GridMath.rotate_cell(side, counter.footprint, turns)
		var front: Vector2i = Vector2i.ZERO
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if placed.cells.has(cell + direction):
				front = direction
		var stool_turns: int = 0
		while GridMath.rotate_cell(Vector2i.UP, Vector2i.ONE, stool_turns) != front:
			stool_turns += 1
		assert_not_null(world.grid.place_def(stool, cell, stool_turns), "%s stool at %s" % [counter.id, cell])
		assert_true(placed.seat_cells.has(cell), "%s turns %d: the facing stool is a seat" % [counter.id, turns])
		var guest: CustomerAgent = world.add_agent(CustomerAgent.new(restaurant, RandomNumberGenerator.new())) as CustomerAgent
		guest.state = CustomerAgent.State.WAITING_FOOD
		guest.table_item_id = placed.id
		guest.cell = cell
		guest.seat_cell = cell
		assert_true(placed.reserve(cell, guest.id))
		guests.append(guest)
	var view: ShopView = load("res://src/world/shop_view.tscn").instantiate() as ShopView
	parent.add_child(view)
	view.set_process(false)
	view.show_world(world)
	var visual: ItemVisual = view.item_nodes.get(placed.id) as ItemVisual
	assert_true(visual != null and visual.prop != null, "%s has its native wrapper" % counter.id)
	var count: int = 0
	if visual != null and visual.prop != null:
		for look: int in range(PersonPresentation.GUEST_MODELS.size()):
			for guest: CustomerAgent in guests:
				var person: PersonView = view.agent_nodes.get(guest.id) as PersonView
				assert_true(person != null and person.set_look(&"customer", look) and person.current_clip() == &"sit")
				if person == null:
					continue
				person._player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				var animation: Animation = person._player.get_animation(&"sit")
				var parts: Array[Dictionary] = GEOMETRY.seat_parts(visual.prop, person)
				for fraction: float in CATALOGUE.SIT_FRACTIONS:
					person._player.seek(animation.length * fraction, true)
					person._skeleton.force_update_all_bone_transforms()
					var head: Dictionary = GEOMETRY.prepare_head(person)
					var result: Dictionary = GEOMETRY.measure_surfaces(head["vertices"], head["triangles"], parts, "backless")
					var context: String = "%s turns=%d %s %s t=%.2f" % [counter.id, turns, stool.id, person.model_name(), fraction]
					assert_eq(result["error"], "", context)
					assert_eq(result["head_vertices_inside_count"], 0, context + ": head inside the counter")
					assert_eq(result["head_seat_surface_crossings"], 0, context + ": head crosses the counter")
					count += 1
	view.free()
	return count


func test_catalogue_coverage_rejects_a_missing_case_instead_of_accepting_retained_rows() -> void:
	var fixture: Dictionary = _coverage_fixture()
	var report: Dictionary = fixture["report"]
	CATALOGUE._validate_case_coverage(report, fixture["expected"])
	assert_true(report["coverage_complete"], "the detached complete pair is valid")
	assert_eq(report["errors"], PackedStringArray())
	(report["samples"] as Array).pop_back()
	CATALOGUE._validate_case_coverage(report, fixture["expected"])
	assert_false(report["coverage_complete"])
	assert_eq(report["expected_samples"], 2)
	assert_eq((report["errors"] as PackedStringArray).size(), 1)


func test_catalogue_coverage_rejects_duplicate_identity_even_when_total_count_matches() -> void:
	var fixture: Dictionary = _coverage_fixture()
	var report: Dictionary = fixture["report"]
	report["samples"][1] = (report["samples"][0] as Dictionary).duplicate(true)
	CATALOGUE._validate_case_coverage(report, fixture["expected"])
	assert_false(report["coverage_complete"])
	assert_eq((report["samples"] as Array).size(), report["expected_samples"])
	assert_eq((report["errors"] as PackedStringArray).size(), 2, "one duplicate and one missing time slot")


func test_catalogue_coverage_rejects_an_errored_or_wrong_time_case() -> void:
	for change: String in ["error", "time"]:
		var fixture: Dictionary = _coverage_fixture()
		var report: Dictionary = fixture["report"]
		var sample: Dictionary = report["samples"][0]
		if change == "error":
			sample["error"] = "native head measurement aborted"
		else:
			sample["sit_time"] = 0.37
		CATALOGUE._validate_case_coverage(report, fixture["expected"])
		assert_false(report["coverage_complete"], change)
		assert_true(not (report["errors"] as PackedStringArray).is_empty(), change)


func _coverage_fixture() -> Dictionary:
	var samples: Array[Dictionary] = []
	var expected: Dictionary[String, bool] = {}
	for fraction: float in [0.0, 0.37]:
		samples.append({"item": "chair", "turns": 0, "seat_cell": [4, 4], "model": "character-female-a",
			"sit_fraction": fraction, "sit_duration": 1.0, "sit_time": fraction, "error": ""})
		expected[CATALOGUE._case_key("chair", 0, Vector2i(4, 4), "character-female-a", fraction)] = true
	return {"expected": expected, "report": {"samples": samples, "errors": PackedStringArray()}}


func test_actual_head_surfaces_do_not_fill_empty_aabb_corners() -> void:
	var head: PackedVector3Array = _box_faces(Vector3(0, 0.6, -0.15), Vector3.ONE * 0.1)
	head.append_array(_box_faces(Vector3(0, 0.9, 0.15), Vector3.ONE * 0.1))
	var back: PackedVector3Array = _box_faces(Vector3(0, 0.6, 0.15), Vector3.ONE * 0.1)
	var parts: Array[Dictionary] = [_part("actual_backrest", back, true)]
	var result: Dictionary = GEOMETRY.measure_surfaces(_unique_points(head), head, parts, "named_parts")
	assert_true(result["passes"])
	assert_almost_eq(float(result["backrest_clearance"]), 0.2, 0.000001)
	var withdrawn: Dictionary = GEOMETRY.measure_triangles(AABB(Vector3(-0.05, 0.55, -0.2), Vector3(0.1, 0.4, 0.4)), back)
	assert_false(withdrawn["passes"], "the withdrawn box intersects empty space between real head pieces")
	assert_true(withdrawn["withdrawn_criterion"])


func test_only_backrest_requires_point_zero_two_but_every_part_forbids_penetration() -> void:
	var head: PackedVector3Array = _box_faces(Vector3(0, 0.6, 0), Vector3.ONE * 0.2)
	var arm: PackedVector3Array = _box_faces(Vector3(0, 0.49, 0), Vector3(0.4, 0.01, 0.4))
	var parts: Array[Dictionary] = [_part("arm_top", arm, false)]
	var result: Dictionary = GEOMETRY.measure_surfaces(_unique_points(head), head, parts, "backless")
	assert_true(result["passes"], "a nonpenetrating arm 0.005 from the real head is allowed")
	assert_null(result["backrest_clearance"])
	for front: float in [0.119, 0.12, 0.121]:
		parts = [_part("backrest", _box_faces(Vector3(0, 0.6, front + 0.05), Vector3(0.8, 0.8, 0.1)), true)]
		result = GEOMETRY.measure_surfaces(_unique_points(head), head, parts, "named_parts")
		assert_almost_eq(float(result["backrest_clearance"]), front - 0.1, 0.000001)
		assert_eq(result["passes"], front >= 0.12)
	parts = [_part("thin_non_backrest_bar", _box_faces(Vector3(0, 0.6, 0), Vector3(0.8, 0.8, 0.01)), false)]
	result = GEOMETRY.measure_surfaces(_unique_points(head), head, parts, "backless")
	assert_eq(result["head_vertices_inside_count"], 0)
	assert_true(int(result["head_seat_surface_crossings"]) > 0, "a thin part can cross between head vertices")
	assert_false(result["passes"])
	parts = [_part("enclosing_non_backrest_part", _box_faces(Vector3(0, 0.6, 0), Vector3.ONE * 2.0), false)]
	result = GEOMETRY.measure_surfaces(_unique_points(head), head, parts, "backless")
	assert_eq(result["head_vertices_inside_count"], 8)
	assert_true(float(result["max_head_vertex_penetration"]) > 0.89)
	assert_false(result["passes"])


func test_unknown_backrest_does_not_invent_a_gap_or_waive_new_seat_failures() -> void:
	var head: PackedVector3Array = _box_faces(Vector3(0, 0.6, 0), Vector3.ONE * 0.2)
	var parts: Array[Dictionary] = [_part("unclassified_seat", _box_faces(Vector3(0, 0.1, 0), Vector3.ONE * 0.1), false)]
	var result: Dictionary = GEOMETRY.measure_surfaces(_unique_points(head), head, parts, "unclassified")
	assert_null(result["backrest_clearance"])
	assert_false(result["measurement_complete"])
	assert_false(result["passes"])
	var samples: Array = []
	var trials: Array = []
	for id: String in CATALOGUE.KNOWN_KIT_FAILURE_IDS:
		samples.append(_policy_sample(id))
		var trial: Dictionary = _policy_sample(id)
		trial["trial_supported"] = true
		trial["trial_forward_offset"] = 0.05
		trials.append(trial)
	var new_seat: Dictionary = _policy_sample("new_chair")
	var made_seat: Dictionary = _policy_sample("diner_booth")
	var parity_error: Dictionary = _policy_sample("chair")
	parity_error["native_bake_max_error"] = 0.1
	samples.append_array([new_seat, made_seat, parity_error])
	var report: Dictionary = {"samples": samples, "errors": PackedStringArray(), "known_kit_offset_trials": trials}
	CATALOGUE._apply_known_failure_policy(report)
	assert_false(new_seat["accepted"])
	assert_false(made_seat["accepted"])
	assert_false(parity_error["accepted"], "an item exception cannot waive native parity")
	assert_true((samples[0] as Dictionary)["accepted"])
	var missing: Dictionary = {"samples": [], "errors": PackedStringArray()}
	CATALOGUE._apply_known_failure_policy(missing)
	assert_eq((missing["errors"] as PackedStringArray).size(), CATALOGUE.KNOWN_KIT_FAILURE_IDS.size(), "each allowlisted ID needs physical evidence")


func _policy_sample(id: String) -> Dictionary:
	return {"item": id, "error": "", "passes": false, "head_vertices": 8, "head_triangles": 12, "seat_triangles": 12,
		"head_vertices_inside_count": 1, "head_seat_surface_crossings": 0, "max_head_vertex_penetration": 0.003,
		"backrest_clearance": null, "backrest_status": "unclassified", "facing_dot": 1.0, "seated_forward_offset": 0.0}


func test_missing_leg_bone_returns_complete_unsupported_hip_schema() -> void:
	var person: PersonView = PersonView.new()
	var skeleton: Skeleton3D = Skeleton3D.new()
	skeleton.add_bone("leg-left")
	person.add_child(skeleton)
	person._skeleton = skeleton
	var no_parts: Array[Dictionary] = []
	var result: Dictionary = GEOMETRY._hip_support(person, no_parts, "diner_booth")
	assert_false(result["hips_supported"], "one missing leg must fail support closed")
	assert_eq((result["hip_bone_positions"] as Array).size(), 1, "available leg position remains useful diagnostic data")
	assert_eq((result["hip_support_points"] as Array).size(), 0, "no cushion was supplied to support the remaining leg")
	assert_eq((result["hip_support_parts"] as PackedStringArray).size(), 0)
	for key: String in ["hips_supported", "hip_support_parts", "hip_bone_positions", "hip_support_points"]:
		assert_true(result.has(key), "serializer contract always provides " + key)
	person.free()


func _box_faces(center: Vector3, size: Vector3) -> PackedVector3Array:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var faces: PackedVector3Array = []
	for point: Vector3 in box.get_faces():
		faces.append(point + center)
	return faces


func _unique_points(faces: PackedVector3Array) -> PackedVector3Array:
	var seen: Dictionary[Vector3, bool] = {}
	var points: PackedVector3Array = []
	for point: Vector3 in faces:
		if not seen.has(point):
			seen[point] = true
			points.append(point)
	return points


func _part(path: String, faces: PackedVector3Array, backrest: bool) -> Dictionary:
	var bounds: AABB = AABB(faces[0], Vector3.ZERO)
	for point: Vector3 in faces:
		bounds = bounds.expand(point)
	return {"path": path, "triangles": faces, "triangle_bounds": GEOMETRY._triangle_bounds(faces), "bounds": bounds,
		"is_backrest": backrest, "is_cushion": false}


func test_indexed_head_geometry_keeps_surface_offsets_and_ignores_unused_positions() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var person: PersonView = PERSON.instantiate() as PersonView
	tree.root.add_child(person)
	var instance: MeshInstance3D = GEOMETRY.head_mesh(person)
	var mesh: ArrayMesh = ArrayMesh.new()
	var first: PackedVector3Array = [Vector3(-0.1, 0.5, 0), Vector3(0.1, 0.5, 0), Vector3(0, 0.7, 0), Vector3(100, 100, 100)]
	var second: PackedVector3Array = [Vector3(-0.1, 0.5, 0.1), Vector3(0.1, 0.5, 0.1), Vector3(0, 0.7, 0.1)]
	for points: PackedVector3Array in [first, second]:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([2, 1, 0])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = mesh # Private instance assignment; imported resources remain intact.
	var posed: PackedVector3Array = first.duplicate()
	posed.append_array(second)
	var result: Dictionary = GEOMETRY.prepare_head(person, posed)
	assert_eq(result["error"], "")
	assert_eq((result["triangles"] as PackedVector3Array).size(), 6)
	assert_eq((result["vertices"] as PackedVector3Array).size(), 6)
	var bounds: AABB = result["snapshot"]["person_bounds"]
	assert_true(bounds.end.y < 2.0, "the unused extreme position must not inflate real head bounds")
	person.free()


func test_exact_geometry_cache_reuses_identical_data_and_invalidates_relative_mutation() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var person: PersonView = PERSON.instantiate() as PersonView
	var seat_scene: PackedScene = load("res://assets/props/diner_booth.tscn") as PackedScene
	var seat: PropView = seat_scene.instantiate() as PropView
	tree.root.add_child(person)
	tree.root.add_child(seat)
	assert_true(person.set_pose(false, true, false, false, seat.seat_surface_height()))
	var comparisons: Dictionary = {}
	var no_parts: Array[Dictionary] = []
	var first: Dictionary = GEOMETRY.measure(person, seat, false, PackedVector3Array(), no_parts, comparisons)
	var same: Dictionary = GEOMETRY.measure(person, seat, false, PackedVector3Array(), no_parts, comparisons)
	assert_eq(first["error"], "")
	assert_false(first["geometry_cache_reused"])
	assert_true(same["geometry_cache_reused"])
	person.position.z -= 0.01
	var changed: Dictionary = GEOMETRY.measure(person, seat, false, PackedVector3Array(), no_parts, comparisons)
	assert_eq(changed["error"], "")
	assert_false(changed["geometry_cache_reused"], "actual relative geometry, not an item ID, owns the cache key")
	person.free()
	seat.free()


func test_triangle_clipping_catches_face_crossing_head_with_all_vertices_outside() -> void:
	var head: AABB = AABB(Vector3(-0.1, 0.5, -0.1), Vector3(0.2, 0.2, 0.2))
	var crossing: PackedVector3Array = [Vector3(-1, 0, 0.05), Vector3(1, 0, 0.05), Vector3(0, 2, 0.05)]
	var result: Dictionary = GEOMETRY.measure_triangles(head, crossing)
	assert_true(int(result["intersecting_triangles"]) > 0)
	assert_almost_eq(float(result["clearance"]), 0.0, 0.000001)
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


func test_near_backrest_top_and_side_edges_outside_head_span_still_require_clearance() -> void:
	var head: AABB = AABB(Vector3(-0.1, 0.5, -0.1), Vector3(0.2, 0.2, 0.2))
	var below: PackedVector3Array = [Vector3(-1, 0.495, -1), Vector3(1, 0.495, -1), Vector3(0, 0.495, 1)]
	var beside: PackedVector3Array = [Vector3(0.105, 0, -1), Vector3(0.105, 2, -1), Vector3(0.105, 1, 1)]
	for triangle: PackedVector3Array in [below, beside]:
		var result: Dictionary = GEOMETRY.measure_triangles(head, triangle)
		assert_eq(result["intersecting_triangles"], 0)
		assert_almost_eq(float(result["clearance"]), 0.005, 0.000001)
		assert_false(result["passes"], "a triangle 0.005 below/beside the real head bounds cannot pass")


func test_diagonal_edge_distance_uses_closest_edge_interiors_and_not_overlapping_bounds() -> void:
	var head: AABB = AABB(Vector3(-0.1, 0.5, -0.1), Vector3(0.2, 0.2, 0.2))
	# The nearest pair is inside the head's vertical Z edge and the triangle's
	# diagonal edge. Neither triangle vertices nor head corners attain it.
	for offset: float in [0.01, 0.06]:
		var sum: float = 0.8 + offset
		var triangle: PackedVector3Array = [Vector3(-1, sum + 1.0, 0), Vector3(1, sum - 1.0, 0), Vector3(1, 1, 0)]
		var result: Dictionary = GEOMETRY.measure_triangles(head, triangle)
		assert_eq(result["intersecting_triangles"], 0)
		assert_almost_eq(float(result["clearance"]), offset / sqrt(2.0), 0.000001)
		assert_eq(result["passes"], offset == 0.06, "true diagonal Euclidean gap sets the threshold")
	var point: Vector3 = Vector3(0.105, 0.495, 0.0)
	var degenerate: Dictionary = GEOMETRY.measure_triangles(head, PackedVector3Array([point, point, point]))
	assert_almost_eq(float(degenerate["clearance"]), sqrt(0.005 * 0.005 * 2.0), 0.000001)
	assert_false(degenerate["passes"], "zero-area triangles remain finite and cannot hide a close seat vertex")


func test_short_nonparallel_seat_edges_keep_their_interior_closest_pair() -> void:
	var head: AABB = AABB(Vector3(-0.1, 0.5, -0.1), Vector3(0.2, 0.2, 0.2))
	# The actual 0.019799 gap fails, although the triangle vertices are each
	# over 0.02 away. A fixed determinant epsilon misclassifies these short
	# bevel edges as parallel and misses the interior closest pair.
	var short_edge: PackedVector3Array = [Vector3(0.111, 0.717, 0), Vector3(0.117, 0.711, 0), Vector3(0.12, 0.72, 0)]
	var result: Dictionary = GEOMETRY.measure_triangles(head, short_edge)
	assert_eq(result["intersecting_triangles"], 0)
	assert_almost_eq(float(result["clearance"]), 0.028 / sqrt(2.0), 0.000001)
	assert_false(result["passes"])


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
