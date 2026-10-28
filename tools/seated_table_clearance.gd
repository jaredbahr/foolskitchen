class_name SeatedTableClearance
extends RefCounted
## Offline review only. ShopView supplies the actual reserved-chair positions,
## seat heights and facing. Real tables and the opposite guest stay visible.

const GEOMETRY: GDScript = preload("res://tools/seated_head_geometry.gd")
const TABLE_IDS: Array[StringName] = [&"cross_table", &"glass_table", &"cloth_table", &"round_table"]
const SIT_FRACTIONS: Array[float] = [0.0, 0.37, 0.91]
## Implementation regression guard, not a Director-specified taste threshold:
## the chosen 10-degree pose measured >=0.236 m in the initial all-look sweep.
## Keep a generous margin above the rejected ~0.03 m face-to-face result.
const OPPOSITE_HEAD_REGRESSION_FLOOR: float = 0.20


static func run(parent: Node, leans: Array[float], turns: Array[int], looks: Array[int],
		fractions: Array[float], native_bake: bool = false, capture_directory: String = "",
		table_ids: Array[StringName] = TABLE_IDS) -> Dictionary:
	var report: Dictionary = {"errors": PackedStringArray(), "samples": [], "pairs": [],
		"table_ids": table_ids, "native_bake": native_bake, "native_bake_poses": {}, "captures": [],
		"head_gap_metric": "minimum distance between both indexed posed-head triangle surfaces",
		"forward_offset": 0.0, "coverage_complete": false, "failures": 0,
		"opposite_head_regressions": 0, "opposite_head_regression_floor": OPPOSITE_HEAD_REGRESSION_FLOOR}
	var errors: PackedStringArray = report["errors"]
	if leans.is_empty() or turns.is_empty() or looks.is_empty() or fractions.is_empty() or table_ids.is_empty():
		errors.append("table review requires a nonempty lean/rotation/look/time matrix")
		report["errors"] = errors
		return report
	var content: ContentDB = ContentDB.new()
	errors.append_array(content.load_all())
	if not errors.is_empty():
		report["errors"] = errors
		return report
	for lean: float in leans:
		if not PersonPresentation.seated_lean_valid(lean):
			errors.append("table review lean must satisfy production pose limits")
			report["errors"] = errors
			continue
		for table_id: StringName in table_ids:
			if not TABLE_IDS.has(table_id):
				errors.append("table review requested an unsupported real-table identity")
				report["errors"] = errors
				continue
			for quarter: int in turns:
				if quarter < 0 or quarter > 3:
					errors.append("table review rotation outside 0..3")
					report["errors"] = errors
					continue
				await _sample_fixture(parent, content, table_id, quarter, looks, fractions,
					lean, native_bake, capture_directory, report)
				errors = report["errors"]
	# Coverage is independent of successful measurements; every pair has two
	# actual reserved guests and every requested combination must occur once.
	var expected_pairs: int = leans.size() * table_ids.size() * turns.size() * looks.size() * fractions.size()
	report["expected_pairs"] = expected_pairs
	report["expected_samples"] = expected_pairs * 2
	var identities: Dictionary[String, bool] = {}
	for pair: Dictionary in report["pairs"]:
		var identity: String = "%s/%d/%d/%.9f/%.9f" % [pair["table"], pair["turns"], pair["look"], pair["sit_fraction"], pair["lean_degrees"]]
		if identities.has(identity):
			errors.append("duplicate table-pair identity: " + identity)
		identities[identity] = true
	report["coverage_complete"] = errors.is_empty() and identities.size() == expected_pairs \
		and (report["samples"] as Array).size() == expected_pairs * 2
	if not report["coverage_complete"]:
		errors.append("table review did not measure the complete requested pair matrix")
	report["errors"] = errors
	return report


static func _sample_fixture(parent: Node, content: ContentDB, table_id: StringName, turns: int,
		looks: Array[int], fractions: Array[float], lean: float, native_bake: bool,
		capture_directory: String, report: Dictionary) -> void:
	var errors: PackedStringArray = report["errors"]
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(14, 14)))
	var restaurant: RestaurantSim = RestaurantSim.new()
	restaurant.world = world
	var table_definition: ItemDef = content.item(table_id)
	var chair_definition: ItemDef = content.item(&"chair").duplicate(true) as ItemDef
	chair_definition.seated_lean_degrees = lean
	chair_definition.seated_forward_offset = 0.0
	var origin: Vector2i = Vector2i(5, 5)
	var table: PlacedItem = world.grid.place_def(table_definition, origin, turns)
	if table == null:
		errors.append("cannot place real table " + String(table_id))
		report["errors"] = errors
		return
	var guests: Array[CustomerAgent] = []
	var chairs: Array[PlacedItem] = []
	var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, table_definition.footprint.y)]
	for side: Vector2i in sides:
		var cell: Vector2i = origin + GridMath.rotate_cell(side, table_definition.footprint, turns)
		var direction: Vector2i = Vector2i.DOWN if side.y < 0 else Vector2i.UP
		var rotated_origin: Vector2i = GridMath.rotate_cell(Vector2i.ZERO, table_definition.footprint, turns)
		var front: Vector2i = GridMath.rotate_cell(direction, table_definition.footprint, turns) - rotated_origin
		var chair_turns: int = 0
		while chair_turns < 4 and GridMath.rotate_cell(Vector2i.UP, Vector2i.ONE, chair_turns) != front:
			chair_turns += 1
		var chair: PlacedItem = world.grid.place_def(chair_definition, cell, chair_turns)
		if chair == null or not table.seat_cells.has(cell):
			errors.append("actual opposing chair is not a dining seat: %s turns=%d cell=%s" % [table_id, turns, cell])
			break
		chairs.append(chair)
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 147 + guests.size()
		var guest: CustomerAgent = world.add_agent(CustomerAgent.new(restaurant, random)) as CustomerAgent
		guest.state = CustomerAgent.State.WAITING_FOOD
		guest.table_item_id = table.id
		guest.cell = cell
		guest.seat_cell = cell
		if not table.reserve(cell, guest.id):
			errors.append("cannot reserve the real table for opposite guests")
		guests.append(guest)
	if guests.size() != 2:
		report["errors"] = errors
		return
	# A normal standing staff view gives the native review a consistent scale
	# reference beside the furniture, as required by ART_STYLE.
	var standing: StaffAgent = world.add_agent(StaffAgent.new(&"server")) as StaffAgent
	standing.cell = origin + Vector2i(3, 0)
	var view: ShopView = (load("res://src/world/shop_view.tscn") as PackedScene).instantiate() as ShopView
	parent.add_child(view)
	view.set_process(false)
	view.show_world(world)
	var table_visual: ItemVisual = view.item_nodes.get(table.id) as ItemVisual
	if table_visual == null or table_visual.prop == null or not table_visual.visible:
		errors.append("real table wrapper is unavailable or hidden")
		view.free()
		report["errors"] = errors
		return
	var camera: Camera3D = _add_camera(view, table_visual) if not capture_directory.is_empty() else null
	for look: int in looks:
		var people: Array[PersonView] = []
		for guest: CustomerAgent in guests:
			var person: PersonView = view.agent_nodes.get(guest.id) as PersonView
			if person == null or not person.set_look(&"customer", look) or person.current_clip() != &"sit":
				errors.append("real reserved guest does not have the seated look/clip")
				break
			person._player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			people.append(person)
		if people.size() != 2:
			continue
		for fraction: float in fractions:
			if not is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
				errors.append("table review sit fraction outside 0..1")
				continue
			for person: PersonView in people:
				var animation: Animation = person._player.get_animation(&"sit")
				person._player.seek(animation.length * fraction, true)
				person._skeleton.force_update_all_bone_transforms()
			if native_bake:
				# A real rendering frame uploads Skeleton3D buffers. Headless Dummy
				# rendering is never substituted for a native bake comparison.
				await (Engine.get_main_loop() as SceneTree).process_frame
				await RenderingServer.frame_post_draw
			var heads: Array[Dictionary] = []
			for side_index: int in range(2):
				var person: PersonView = people[side_index]
				var head: Dictionary = GEOMETRY.prepare_head(person)
				if not String(head.get("error", "missing head result")).is_empty():
					errors.append(String(head.get("error", "missing head result")))
					break
				heads.append(head)
				var result: Dictionary = GEOMETRY.measure(person, table_visual.prop)
				var chair_visual: ItemVisual = view.item_nodes.get(chairs[side_index].id) as ItemVisual
				var backrest: Dictionary = GEOMETRY.measure(person, chair_visual.prop) if chair_visual != null and chair_visual.prop != null else {"error": "chair wrapper missing"}
				var sample: Dictionary = {"table": String(table_id), "turns": turns,
					"look": look, "model": String(person.model_name()), "side": side_index,
					"seat_cell": [guests[side_index].cell.x, guests[side_index].cell.y],
					"sit_fraction": fraction, "lean_degrees": lean, "forward_offset": 0.0,
					"actual_lean_degrees": person.current_seated_lean_degrees(),
					"table_visible": table_visual.is_visible_in_tree(), "error": result.get("error", "missing table result"),
					"table_triangles": result.get("seat_triangles", 0),
					"head_vertices": result.get("head_vertices", 0),
					"head_vertices_inside_count": result.get("head_vertices_inside_count", -1),
					"max_head_vertex_penetration": result.get("max_head_vertex_penetration", null),
					"head_table_surface_crossings": result.get("head_seat_surface_crossings", -1),
					"chair_backrest_clearance": backrest.get("backrest_clearance", null),
					"chair_head_vertices_inside_count": backrest.get("head_vertices_inside_count", -1),
					"chair_head_surface_crossings": backrest.get("head_seat_surface_crossings", -1),
					"chair_max_head_vertex_penetration": backrest.get("max_head_vertex_penetration", null)}
				if not String(sample["error"]).is_empty() or not String(backrest.get("error", "missing chair result")).is_empty():
					errors.append("table/chair measurement failed: %s look=%d" % [table_id, look])
				if int(sample["table_triangles"]) <= 0 or int(sample["head_vertices"]) <= 0:
					errors.append("table/head geometry was empty")
				if not is_equal_approx(float(sample["actual_lean_degrees"]), lean):
					errors.append("ShopView did not apply the requested chair articulation")
				if int(sample["head_vertices_inside_count"]) != 0 or int(sample["head_table_surface_crossings"]) != 0:
					report["failures"] = int(report["failures"]) + 1
				if native_bake:
					var mesh: MeshInstance3D = GEOMETRY.head_mesh(person)
					var posed: Dictionary = GEOMETRY.skin_vertices(mesh, person._skeleton)
					var parity: Dictionary = GEOMETRY.native_bake_error(mesh, posed["vertices"])
					sample["native_bake_max_error"] = parity["max_error"]
					if not String(parity["error"]).is_empty() or float(parity["max_error"]) > 0.00001:
						errors.append("native bake parity failed")
					var pose_key: String = "%s/%.9f/%.9f" % [person.model_name(), fraction, lean]
					var pose_parity: Dictionary = report["native_bake_poses"]
					if not pose_parity.has(pose_key) or float(parity["max_error"]) > float(pose_parity[pose_key]["max_error"]):
						pose_parity[pose_key] = parity
				(report["samples"] as Array).append(sample)
			if heads.size() == 2:
				var gap: float = head_surface_gap(people[0], heads[0], people[1], heads[1])
				if not is_finite(gap) or gap <= 0.0:
					errors.append("opposite head-surface distance unavailable or heads intersect")
				if table_definition.footprint == Vector2i(2, 1) and gap < OPPOSITE_HEAD_REGRESSION_FLOOR:
					report["opposite_head_regressions"] = int(report["opposite_head_regressions"]) + 1
				(report["pairs"] as Array).append({"table": String(table_id), "turns": turns,
					"look": look, "model": String(people[0].model_name()), "sit_fraction": fraction,
					"lean_degrees": lean, "head_surface_gap": gap,
					"table_footprint": [table_definition.footprint.x, table_definition.footprint.y]})
			if camera != null and turns == 0 and look == PersonPresentation.GUEST_MODELS.find(&"character-female-e") and fraction == 0.0:
				await (Engine.get_main_loop() as SceneTree).process_frame
				await RenderingServer.frame_post_draw
				var path: String = capture_directory.path_join("%s-lean-%s.png" % [table_id, String.num(lean).replace(".", "_")])
				if (Engine.get_main_loop() as SceneTree).root.get_texture().get_image().save_png(path) != OK:
					errors.append("cannot save real-table review image")
				else:
					var image: Image = Image.load_from_file(path)
					(report["captures"] as Array).append({"image_file": path.get_file(),
						"image_sha256": FileAccess.get_sha256(path), "width": image.get_width(),
						"height": image.get_height(), "table": String(table_id),
						"lean_degrees": lean, "table_visible": table_visual.is_visible_in_tree(),
						"opposite_guest_visible": people[0].is_visible_in_tree() and people[1].is_visible_in_tree(),
						"standing_reference_visible": (view.agent_nodes[standing.id] as PersonView).is_visible_in_tree(),
						"capture_timing": "frame_post_draw"})
	view.free()
	report["errors"] = errors


## Exact indexed surface distance, with conservative triangle-box pruning.
## Neither a head AABB nor a vertex-only nearest-neighbour distance is the oracle.
static func head_surface_gap(first: PersonView, first_head: Dictionary,
		second: PersonView, second_head: Dictionary) -> float:
	var a: PackedVector3Array = []
	var b: PackedVector3Array = []
	for vertex: Vector3 in first_head["triangles"]:
		a.append(first.to_global(vertex))
	for vertex: Vector3 in second_head["triangles"]:
		b.append(second.to_global(vertex))
	if a.is_empty() or b.is_empty():
		return INF
	var a_bounds: Array[AABB] = GEOMETRY._triangle_bounds(a)
	var b_bounds: Array[AABB] = GEOMETRY._triangle_bounds(b)
	var best_squared: float = INF
	for ai: int in a_bounds.size():
		for bi: int in b_bounds.size():
			if GEOMETRY._box_distance_squared(a_bounds[ai], b_bounds[bi]) >= best_squared:
				continue
			best_squared = minf(best_squared, GEOMETRY._triangle_distance_squared(a, ai * 3, b, bi * 3))
	return sqrt(best_squared)


static func _add_camera(view: ShopView, table: ItemVisual) -> Camera3D:
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.75, 0.77, 0.78)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	view.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	view.add_child(light)
	var camera: Camera3D = Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	var target: Vector3 = table.global_position + Vector3(0, 0.35, 0)
	camera.global_position = target + Vector3(2.5, 1.8, 2.5)
	camera.look_at(target)
	camera.make_current()
	return camera
