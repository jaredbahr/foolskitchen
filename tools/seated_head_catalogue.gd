class_name SeatedHeadCatalogue
extends RefCounted
## Read-only native ShopView fixture. Production code chooses seat position,
## height and facing; this harness never compensates for clipping itself.

const GEOMETRY: GDScript = preload("res://tools/seated_head_geometry.gd")
const SIT_FRACTIONS: Array[float] = [0.0, 0.37, 0.91]
## Director 6404820766: unchanged kit items only. Every listed item must retain
## at least one measured physical violation; unknown classification is not proof.
const KNOWN_KIT_FAILURE_IDS: PackedStringArray = ["bench", "cushioned_bench", "lounge_chair",
	"modern_chair", "modern_frame_chair", "rounded_chair", "table_2", "table_4", "wooden_chair"]


static func run(parent: Node, native_bake: bool = false) -> Dictionary:
	var report: Dictionary = {"errors": PackedStringArray(), "samples": [], "seats": 0,
		"required_clearance": GEOMETRY.REQUIRED_CLEARANCE, "native_bake": native_bake,
		"native_bake_upload_waits": 0, "native_bake_poses": {}, "known_kit_offset_trials": []}
	var errors: PackedStringArray = report["errors"]
	var poses: Dictionary[String, PackedVector3Array] = {}
	var parity: Dictionary[String, Dictionary] = {}
	var comparisons: Dictionary = {}
	var expected: Dictionary[String, bool] = {}
	var content: ContentDB = ContentDB.new()
	errors.append_array(content.load_all())
	if not errors.is_empty():
		report["errors"] = errors
		return report
	for definition: ItemDef in content.items():
		if definition.seat_cells.is_empty() or not definition.catalogue_visible:
			continue
		report["seats"] += 1
		for turns: int in range(4):
			_expect_item_cases(expected, definition, turns)
			await _sample_item(parent, definition, turns, native_bake, poses, parity, comparisons, report)
	report["native_bake_poses"] = parity
	_validate_case_coverage(report, expected)
	_apply_known_failure_policy(report)
	return report


static func _expect_item_cases(expected: Dictionary[String, bool], definition: ItemDef, turns: int) -> void:
	for authored: Vector2i in definition.seat_cells:
		var cell: Vector2i = Vector2i(4, 4) + GridMath.rotate_cell(authored, definition.footprint, turns)
		for model: StringName in PersonPresentation.GUEST_MODELS:
			for fraction: float in SIT_FRACTIONS:
				expected[_case_key(String(definition.id), turns, cell, String(model), fraction)] = true


static func _case_key(item: String, turns: int, cell: Vector2i, model: String, fraction: float) -> String:
	return "%s turns=%d cell=%d,%d model=%s sit_fraction=%.9f" % [item, turns, cell.x, cell.y, model, fraction]


## Cached skinning and native parity must describe the same articulated pose.
## Variant bytes retain float identity instead of rounding authored leans.
static func _pose_key(model: StringName, time: float, lean_degrees: float) -> String:
	return String(model) + ":" + var_to_bytes([time, lean_degrees]).hex_encode()


## Count identities independently of returned rows: an aborted item sampler or
## a duplicate row cannot turn an incomplete diagnostic into a passing report.
static func _validate_case_coverage(report: Dictionary, expected: Dictionary[String, bool]) -> void:
	var errors: PackedStringArray = report["errors"]
	var counts: Dictionary[String, int] = {}
	var complete: bool = not expected.is_empty()
	for sample: Dictionary in report["samples"]:
		var cell: Variant = sample.get("seat_cell")
		var fraction: Variant = sample.get("sit_fraction")
		var duration: Variant = sample.get("sit_duration")
		var time: Variant = sample.get("sit_time")
		if not sample.get("item") is String or not sample.get("model") is String \
				or not sample.get("turns") is int or not cell is Array or cell.size() != 2 \
				or not cell[0] is int or not cell[1] is int \
				or not fraction is float or not SIT_FRACTIONS.has(fraction) \
				or not duration is float or not is_finite(duration) or duration <= 0.0 \
				or not time is float or not is_finite(time) or time != duration * fraction:
			errors.append("catalogue sample has an invalid definition/cell/rotation/model/sit-time identity")
			complete = false
			continue
		var key: String = _case_key(sample["item"], sample["turns"], Vector2i(cell[0], cell[1]), sample["model"], fraction)
		counts[key] = counts.get(key, 0) + 1
		if not expected.has(key):
			errors.append("unexpected catalogue case: " + key)
			complete = false
		if not String(sample.get("error", "missing measurement")).is_empty():
			errors.append("catalogue case measurement failed: " + key)
			complete = false
	for key: String in expected:
		if counts.get(key, 0) != 1:
			errors.append("catalogue case needs exactly one sample, found %d: %s" % [counts.get(key, 0), key])
			complete = false
	if expected.is_empty():
		errors.append("catalogue has no expected seated cases")
	report["expected_samples"] = expected.size()
	report["coverage_complete"] = complete
	report["errors"] = errors


static func _sample_item(parent: Node, definition: ItemDef, turns: int, native_bake: bool,
		poses: Dictionary[String, PackedVector3Array], parity: Dictionary[String, Dictionary], comparisons: Dictionary, report: Dictionary) -> void:
	var errors: PackedStringArray = report["errors"]
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(12, 12)))
	var restaurant: RestaurantSim = RestaurantSim.new()
	restaurant.world = world
	var origin: Vector2i = Vector2i(4, 4)
	var table_def: ItemDef = ItemDef.new()
	table_def.category = ItemDef.Category.TABLE
	table_def.footprint = Vector2i.ONE
	var tables: Array[PlacedItem] = []
	if definition.category != ItemDef.Category.TABLE:
		for authored: Vector2i in definition.seat_cells:
			var front: Vector2i = origin + GridMath.rotate_cell(authored + Vector2i.UP, definition.footprint, turns)
			var table: PlacedItem = world.grid.place_def(table_def, front)
			if table == null:
				errors.append("%s rotation %d: cannot place facing table" % [definition.id, turns])
				report["errors"] = errors
				return
			tables.append(table)
	var placed: PlacedItem = world.grid.place_def(definition, origin, turns)
	if placed == null or definition.seat_cells.is_empty():
		errors.append("%s rotation %d: cannot place catalogue seat" % [definition.id, turns])
		report["errors"] = errors
		return
	if definition.category == ItemDef.Category.TABLE:
		for authored: Vector2i in definition.seat_cells:
			tables.append(placed)
	var guests: Array[CustomerAgent] = []
	for index: int in range(definition.seat_cells.size()):
		var cell: Vector2i = origin + GridMath.rotate_cell(definition.seat_cells[index], definition.footprint, turns)
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 147 + index
		var guest: CustomerAgent = world.add_agent(CustomerAgent.new(restaurant, random)) as CustomerAgent
		guest.state = CustomerAgent.State.WAITING_FOOD
		guest.table_item_id = tables[index].id
		guest.cell = cell
		guest.seat_cell = cell
		if not tables[index].reserve(cell, guest.id):
			errors.append("%s rotation %d: table did not project/reserve the native seat" % [definition.id, turns])
		guests.append(guest)
	# Load after autoload initialization; entry-script scene preloads retained
	# the scene/script resource graph at diagnostic shutdown on current main.
	var view: ShopView = (load("res://src/world/shop_view.tscn") as PackedScene).instantiate() as ShopView
	parent.add_child(view)
	view.set_process(false)
	view.show_world(world)
	var visual: ItemVisual = view.item_nodes.get(placed.id) as ItemVisual
	if visual == null or visual.prop == null:
		errors.append("%s: missing native seat wrapper" % definition.id)
	else:
		var parts: Dictionary[int, Array] = {}
		for look: int in range(PersonPresentation.GUEST_MODELS.size()):
			for guest: CustomerAgent in guests:
				var person: PersonView = view.agent_nodes.get(guest.id) as PersonView
				if person == null or not person.set_look(&"customer", look) or person.current_clip() != &"sit":
					errors.append("%s: native seated PersonView is unavailable" % definition.id)
					continue
				# Stop automatic advancement, then seek the actual imported sit clip.
				person._player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				var animation: Animation = person._player.get_animation(&"sit")
				for fraction: float in SIT_FRACTIONS:
					person._player.seek(animation.length * fraction, true)
					# Bone pose queries calculate dirty transforms synchronously.
					person._skeleton.force_update_all_bone_transforms()
					var pose_key: String = _pose_key(person.model_name(), animation.length * fraction,
						person.current_seated_lean_degrees())
					if not poses.has(pose_key):
						var posed: Dictionary = GEOMETRY.skin_vertices(GEOMETRY.head_mesh(person), person._skeleton)
						if not String(posed["error"]).is_empty():
							errors.append(String(posed["error"]))
							continue
						poses[pose_key] = posed["vertices"]
					var reused_parity: bool = parity.has(pose_key)
					if native_bake and not reused_parity:
						# Native bake is mesh-local: only this model/time's first
						# encounter needs a renderer upload and vertex comparison.
						# All placements still use their real node transforms below.
						await RenderingServer.frame_post_draw
						report["native_bake_upload_waits"] += 1
						var comparison: Dictionary = GEOMETRY.native_bake_error(GEOMETRY.head_mesh(person), poses[pose_key])
						comparison["provenance"] = "MeshInstance3D.bake_mesh_from_current_skeleton_pose; mesh-local model/time comparison"
						comparison["head_vertices"] = poses[pose_key].size()
						parity[pose_key] = comparison
					if not parts.has(guest.id):
						parts[guest.id] = GEOMETRY.seat_parts(visual.prop, person)
					var prepared: Array[Dictionary] = []
					prepared.assign(parts[guest.id])
					var sample: Dictionary = GEOMETRY.measure(person, visual.prop, false, poses[pose_key], prepared, comparisons)
					if KNOWN_KIT_FAILURE_IDS.has(String(definition.id)) and turns == 0 \
							and person.model_name() == &"character-female-e" and guest == guests[0] and fraction == 0.0:
						var trial: Dictionary = GEOMETRY.supported_offset_trial(person, visual.prop, prepared, definition.seated_forward_offset)
						trial["item"] = String(definition.id)
						trial["model"] = String(person.model_name())
						trial["seat_cell"] = [guest.cell.x, guest.cell.y]
						(report["known_kit_offset_trials"] as Array).append(trial)
					if native_bake:
						var cached_comparison: Dictionary = parity[pose_key]
						sample["native_bake_pose_key"] = pose_key
						sample["native_bake_reused"] = reused_parity
						sample["native_bake_max_error"] = cached_comparison["max_error"]
						sample["native_bake_provenance"] = cached_comparison["provenance"]
						if not String(cached_comparison["error"]).is_empty():
							sample["error"] = cached_comparison["error"]
							sample["passes"] = false
					sample["item"] = String(definition.id)
					sample["turns"] = turns
					sample["seat_cell"] = [guest.cell.x, guest.cell.y]
					sample["model"] = String(person.model_name())
					sample["sit_time"] = animation.length * fraction
					sample["sit_fraction"] = fraction
					sample["sit_duration"] = animation.length
					sample["seat_height"] = person._seat_height
					sample["seated_forward_offset"] = definition.seated_forward_offset
					sample["seated_lean_degrees"] = person.current_seated_lean_degrees()
					var zero: Vector2i = GridMath.rotate_cell(Vector2i.ZERO, definition.footprint, turns)
					var front: Vector2i = GridMath.rotate_cell(Vector2i.UP, definition.footprint, turns) - zero
					var palm: Vector3 = person.to_global(person.carry_anchor_position())
					var table_item: PlacedItem = tables[guests.find(guest)]
					var table_center: Vector3 = ItemVisual.placed_transform(table_item.def as ItemDef, table_item.origin, turns if definition.category == ItemDef.Category.TABLE else 0).origin
					var direction: Vector3 = Vector3(front.x, 0.0, front.y)
					if definition.category == ItemDef.Category.TABLE:
						direction = (table_center - GridMath.cell_to_world(guest.cell)).normalized()
					sample["facing_dot"] = (-person.global_basis.z).normalized().dot(direction)
					sample["palms_to_table_horizontal"] = Vector2(palm.x - table_center.x, palm.z - table_center.z).length()
					sample["palms_world_y"] = palm.y
					(report["samples"] as Array).append(sample)
	view.free()
	report["errors"] = errors


static func physical_violation(sample: Dictionary) -> bool:
	if not String(sample.get("error", "missing measurement")).is_empty():
		return false
	var gap: Variant = sample.get("backrest_clearance")
	return int(sample.get("head_vertices_inside_count", 0)) > 0 \
		or int(sample.get("head_seat_surface_crossings", 0)) > 0 \
		or (gap != null and is_finite(float(gap)) and float(gap) + GEOMETRY.EPSILON < GEOMETRY.REQUIRED_CLEARANCE)


static func _apply_known_failure_policy(report: Dictionary) -> void:
	var findings: Dictionary[String, Dictionary] = {}
	var eligible: Dictionary[String, Dictionary] = {}
	var errors: PackedStringArray = report["errors"]
	for trial: Dictionary in report.get("known_kit_offset_trials", []):
		var item: String = trial["item"]
		if KNOWN_KIT_FAILURE_IDS.has(item) and physical_violation(trial) \
				and trial.get("trial_supported", false) and float(trial.get("trial_forward_offset", 0.0)) == 0.05:
			eligible[item] = trial
	for sample: Dictionary in report["samples"]:
		var item: String = sample["item"]
		if not KNOWN_KIT_FAILURE_IDS.has(item) or not physical_violation(sample):
			continue
		if not findings.has(item):
			findings[item] = {"item": item, "physical_violation_samples": 0, "inside_vertex_samples": 0,
				"surface_crossing_samples": 0, "max_vertex_penetration": 0.0,
				"minimum_identified_backrest_gap": null, "backrest_status": sample["backrest_status"]}
		var finding: Dictionary = findings[item]
		finding["physical_violation_samples"] += 1
		if int(sample["head_vertices_inside_count"]) > 0:
			finding["inside_vertex_samples"] += 1
		if int(sample["head_seat_surface_crossings"]) > 0:
			finding["surface_crossing_samples"] += 1
		finding["max_vertex_penetration"] = maxf(float(finding["max_vertex_penetration"]), float(sample["max_head_vertex_penetration"]))
		var gap: Variant = sample["backrest_clearance"]
		if gap != null and (finding["minimum_identified_backrest_gap"] == null or float(gap) < float(finding["minimum_identified_backrest_gap"])):
			finding["minimum_identified_backrest_gap"] = gap
	for item: String in KNOWN_KIT_FAILURE_IDS:
		if not findings.has(item) or not eligible.has(item):
			errors.append("known kit failure %s needs a measured physical violation at a supported 0.05 offset; remove or investigate its exception" % item)
		elif findings.has(item):
			findings[item]["supported_offset_trial"] = eligible[item]
	var raw_failures: int = 0
	var failures: int = 0
	for sample: Dictionary in report["samples"]:
		var item: String = sample["item"]
		var offset: float = float(sample["seated_forward_offset"])
		var valid: bool = String(sample.get("error", "missing measurement")).is_empty() \
			and int(sample.get("head_vertices", 0)) > 0 and int(sample.get("head_triangles", 0)) > 0 \
			and int(sample.get("seat_triangles", 0)) > 0 and float(sample["facing_dot"]) > 0.9999 \
			and is_finite(offset) and offset >= 0.0 and offset <= 0.05 + GEOMETRY.EPSILON
		if sample.has("native_bake_max_error"):
			valid = valid and is_finite(float(sample["native_bake_max_error"])) and float(sample["native_bake_max_error"]) <= 0.00001
		sample["known_kit_failure"] = KNOWN_KIT_FAILURE_IDS.has(item) and findings.has(item) and eligible.has(item)
		sample["accepted"] = valid and (sample.get("passes", false) or sample["known_kit_failure"])
		if not sample.get("passes", false):
			raw_failures += 1
		if not sample["accepted"]:
			failures += 1
	var ordered: Array[Dictionary] = []
	for item: String in KNOWN_KIT_FAILURE_IDS:
		if findings.has(item):
			ordered.append(findings[item])
	report["known_kit_failures"] = ordered
	report["known_kit_failure_allowlist"] = KNOWN_KIT_FAILURE_IDS
	report["raw_failures"] = raw_failures
	report["failures"] = failures + errors.size()
	report["errors"] = errors
