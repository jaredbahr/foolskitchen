class_name SeatedHeadGeometry
extends RefCounted
## Offline review geometry, never used to fit or move a person at runtime.
## Skinning follows Skeleton3D's pose_global * inverse_bind and MeshInstance3D's
## weighted vertex bake. get_aabb() is deliberately never used for a person.
## See Godot scene/3d/{skeleton_3d,mesh_instance_3d}.cpp and class_meshinstance3d.

const REQUIRED_CLEARANCE: float = 0.02
const EPSILON: float = 0.000001
const PROVENANCE: String = "native Mini head-mesh POSITION/JOINTS/WEIGHTS, imported Skin inverse binds, current Skeleton3D global poses, actual node transforms"
const CLEARANCE_METRIC: String = "indexed posed-head mesh to identified backrest surfaces"
const WITHDRAWN_AABB_METRIC: String = "minimum Euclidean seat-triangle to conservative posed-head AABB separation"
const BOOTH_BACKREST_NAMES: PackedStringArray = ["Left back cushion", "Right back cushion", "Tall back shell"]
const BOOTH_CUSHION_NAMES: PackedStringArray = ["Left seat cushion", "Right seat cushion"]
const BACKLESS_SCENES: PackedStringArray = ["bar_stool", "square_bar_stool", "diner_stool"]
const KIT_BACKREST_SCENES: PackedStringArray = ["bench", "chair", "cushioned_bench", "lounge_chair",
	"modern_chair", "modern_frame_chair", "rounded_chair", "table_2", "table_4", "wooden_chair"]


static func head_mesh(person: PersonView) -> MeshInstance3D:
	if person == null or person._model == null:
		return null
	var matches: Array[Node] = person._model.find_children("head-mesh", "MeshInstance3D", true, false)
	return matches[0] as MeshInstance3D if matches.size() == 1 else null


## Result vertices are mesh-local, exactly as native bake returns them. Imported
## bind indices are NOT bone indices; named binds take precedence, as in Godot.
## Missing/unsupported data fails closed instead of falling back to rest bounds.
static func skin_vertices(instance: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var result: Dictionary = {"error": "", "vertices": PackedVector3Array()}
	if instance == null or instance.mesh == null or instance.skin == null or skeleton == null:
		result["error"] = "head requires a mesh, imported Skin and native Skeleton3D"
		return result
	if instance.mesh.get_blend_shape_count() != 0:
		result["error"] = "blend shapes require an explicit measurement implementation"
		return result
	var transforms: Array[Transform3D] = []
	for index: int in range(instance.skin.get_bind_count()):
		var name: StringName = instance.skin.get_bind_name(index)
		var bone: int = skeleton.find_bone(String(name)) if name != &"" else instance.skin.get_bind_bone(index)
		if bone < 0 or bone >= skeleton.get_bone_count():
			result["error"] = "head Skin contains an unresolved bone bind"
			return result
		transforms.append(skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(index))
	var posed: PackedVector3Array = []
	for surface: int in range(instance.mesh.get_surface_count()):
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var count: int = 8 if instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		if vertices.is_empty() or bones.size() != vertices.size() * count or weights.size() != bones.size():
			result["error"] = "head surface has incomplete skinning arrays"
			return result
		for vertex: int in range(vertices.size()):
			var point: Vector3 = Vector3.ZERO
			var total: float = 0.0
			for influence: int in range(count):
				var slot: int = vertex * count + influence
				var weight: float = weights[slot]
				if not is_finite(weight) or weight < 0.0:
					result["error"] = "head has invalid skin weights"
					return result
				if weight == 0.0:
					continue
				var bind: int = bones[slot]
				if bind < 0 or bind >= transforms.size():
					result["error"] = "head vertex refers to an absent Skin bind"
					return result
				point += (transforms[bind] * vertices[vertex]) * weight
				total += weight
			# Match the authored weights, never silently normalize broken content.
			if absf(total - 1.0) > 0.0001 or not point.is_finite():
				result["error"] = "head vertex weights must sum to one"
				return result
			posed.append(point)
	result["vertices"] = posed
	return result


## Optional rendered admission check. Dummy rendering cannot supply the native
## RenderingServer skeleton buffers; callers must explicitly request a real GPU.
static func native_bake_error(instance: MeshInstance3D, expected: PackedVector3Array) -> Dictionary:
	if instance.get_skin_reference() == null:
		return {"error": "native bake requires a registered skin", "max_error": INF}
	var baked: ArrayMesh = instance.bake_mesh_from_current_skeleton_pose()
	if baked == null:
		return {"error": "native bake returned no mesh", "max_error": INF}
	var actual: PackedVector3Array = []
	for surface: int in range(baked.get_surface_count()):
		var arrays: Array = baked.surface_get_arrays(surface)
		actual.append_array(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	if actual.size() != expected.size() or actual.is_empty():
		return {"error": "native bake vertex count differs", "max_error": INF}
	var maximum: float = 0.0
	for index: int in range(actual.size()):
		maximum = maxf(maximum, actual[index].distance_to(expected[index]))
	return {"error": "" if maximum <= 0.00001 else "CPU skin differs from native bake", "max_error": maximum}


## All geometry is expressed in the *person's* axes: forward -Z, rear +Z.
## Taking bounds AFTER transforming every posed vertex avoids rotating an AABB
## and inflating it. Hair belongs to the real native head-mesh and is included.
static func measure_person_head(person: PersonView) -> Dictionary:
	var head: Dictionary = prepare_head(person)
	if not String(head.get("error", "")).is_empty():
		return head
	return head["snapshot"]


static func _head_bounds(person: PersonView, instance: MeshInstance3D, vertices: PackedVector3Array) -> Dictionary:
	if vertices.is_empty():
		return {"error": "native head has no vertices"}
	var to_person: Transform3D = _between_nodes(instance, person)
	var local: AABB = AABB(to_person * vertices[0], Vector3.ZERO)
	var world: AABB = AABB(instance.global_transform * vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices:
		local = local.expand(to_person * vertex)
		world = world.expand(instance.global_transform * vertex)
	return {"error": "", "person_bounds": local, "world_bounds": world,
		"head_vertices": vertices.size(), "provenance": PROVENANCE}


## The all-vertex array is kept intact for native-bake parity. Only referenced
## INDEX topology supplies collision vertices/triangles and crop bounds.
static func prepare_head(person: PersonView, cached_vertices: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	if person == null:
		return {"error": "native person is unavailable"}
	var instance: MeshInstance3D = head_mesh(person)
	if instance == null:
		return {"error": "native indexed head mesh is unavailable"}
	var posed: Dictionary = skin_vertices(instance, person._skeleton) if cached_vertices.is_empty() else {"error": "", "vertices": cached_vertices}
	if not String(posed["error"]).is_empty():
		return posed
	var vertices: PackedVector3Array = posed["vertices"]
	var referenced: PackedVector3Array = []
	var unique: Dictionary[Vector3, bool] = {}
	var triangles: PackedVector3Array = []
	var offset: int = 0
	var to_person: Transform3D = _between_nodes(instance, person)
	for surface: int in range(instance.mesh.get_surface_count()):
		if instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return {"error": "head surface must contain triangles"}
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index: int in range(source.size()):
				indices.append(index)
		if indices.size() % 3 != 0 or offset + source.size() > vertices.size():
			return {"error": "head triangle indices do not match the posed vertex array"}
		for index: int in indices:
			if index < 0 or index >= source.size():
				return {"error": "head triangle index is outside its own surface"}
			var mesh_point: Vector3 = vertices[offset + index]
			var point: Vector3 = to_person * mesh_point
			triangles.append(point)
			if not unique.has(point):
				unique[point] = true
				referenced.append(mesh_point)
		offset += source.size()
	if offset != vertices.size() or triangles.is_empty():
		return {"error": "head has no complete indexed triangles"}
	var points: PackedVector3Array = []
	for point: Vector3 in unique:
		points.append(point)
	return {"error": "", "vertices": points, "triangles": triangles,
		"triangle_bounds": _triangle_bounds(triangles), "snapshot": _head_bounds(person, instance, referenced)}


## Optional caches contain actual immutable posed vertices and prepared parts.
## Cache hits require equality of the entire geometry payload after hashing;
## item IDs, nominal poses and AABBs cannot authorize a cached passing result.
static func measure(person: PersonView, seat: Node3D, native_bake: bool = false,
		cached_vertices: PackedVector3Array = PackedVector3Array(), cached_parts: Array[Dictionary] = [], comparisons: Dictionary = {}) -> Dictionary:
	var instance: MeshInstance3D = head_mesh(person)
	if person == null:
		return {"error": "native person is unavailable"}
	var head: Dictionary = prepare_head(person, cached_vertices)
	if not String(head["error"]).is_empty():
		return head
	var result: Dictionary = {}
	if native_bake:
		var posed: Dictionary = skin_vertices(instance, person._skeleton)
		if not String(posed["error"]).is_empty():
			return posed
		var comparison: Dictionary = native_bake_error(instance, posed["vertices"])
		result["native_bake_max_error"] = comparison["max_error"]
		if not String(comparison["error"]).is_empty():
			result["error"] = comparison["error"]
			return result
	var parts: Array[Dictionary] = seat_parts(seat, person) if cached_parts.is_empty() else cached_parts
	if parts.is_empty():
		return {"error": "seat has no native mesh parts"}
	var classification: String = _backrest_status(seat, parts)
	var key: Array = [head["triangles"], classification]
	for part: Dictionary in parts:
		key.append([part["path"], part["triangles"], part["is_backrest"]])
	var digest: int = hash(key)
	var metrics: Dictionary = {}
	var bucket: Array = comparisons.get(digest, [])
	for entry: Dictionary in bucket:
		if entry["geometry"] == key:
			metrics = (entry["metrics"] as Dictionary).duplicate(true)
			break
	result["geometry_cache_reused"] = not metrics.is_empty()
	if metrics.is_empty():
		metrics = measure_surfaces(head["vertices"], head["triangles"], parts, classification)
		bucket.append({"geometry": key, "metrics": metrics.duplicate(true)})
		comparisons[digest] = bucket
	result.merge(metrics)
	result.merge(head["snapshot"])
	result.merge(_hip_support(person, parts, seat.scene_file_path.get_file().get_basename()))
	if result.get("hips_supported") == false:
		result["passes"] = false
	return result


static func seat_triangles(seat: Node3D, relative_to: Node3D) -> PackedVector3Array:
	var triangles: PackedVector3Array = []
	for part: Dictionary in seat_parts(seat, relative_to):
		triangles.append_array(part["triangles"])
	return triangles


static func seat_parts(seat: Node3D, relative_to: Node3D) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var scene: String = seat.scene_file_path.get_file().get_basename()
	for node: Node in seat.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh == null:
			continue
		var faces: PackedVector3Array = instance.mesh.get_faces()
		var triangles: PackedVector3Array = []
		var transform: Transform3D = _between_nodes(instance, relative_to)
		for vertex: Vector3 in faces:
			triangles.append(transform * vertex)
		if triangles.is_empty() or triangles.size() % 3 != 0:
			return []
		var bounds: AABB = AABB(triangles[0], Vector3.ZERO)
		for point: Vector3 in triangles:
			bounds = bounds.expand(point)
		var backrest: bool = scene == "diner_booth" and BOOTH_BACKREST_NAMES.has(String(instance.name))
		var cushion: bool = (scene == "diner_booth" and BOOTH_CUSHION_NAMES.has(String(instance.name))) \
			or (scene == "diner_stool" and instance.name == &"Round red cushion")
		parts.append({"path": String(seat.get_path_to(instance)), "name": String(instance.name),
			"triangles": triangles, "triangle_bounds": _triangle_bounds(triangles), "bounds": bounds,
			"is_backrest": backrest, "is_cushion": cushion})
	return parts


static func _backrest_status(seat: Node3D, parts: Array[Dictionary]) -> String:
	var scene: String = seat.scene_file_path.get_file().get_basename()
	if BACKLESS_SCENES.has(scene):
		return "backless"
	if scene == "diner_booth":
		var found: PackedStringArray = []
		for part: Dictionary in parts:
			if part["is_backrest"]:
				found.append(part["name"])
		return "named_parts" if found.size() == BOOTH_BACKREST_NAMES.size() else "unclassified"
	# Joined kit seats, including table_4's chairCushion pieces, are still
	# measured for physical intrusion. Classification grants no policy exception.
	# Their joined mesh does not provide reliable semantic backrest annotations.
	# Never label the whole joined seat mesh as a measured backrest.
	return "unclassified_kit" if KIT_BACKREST_SCENES.has(scene) else "unclassified"


static func _between_nodes(node: Node3D, target: Node3D) -> Transform3D:
	var target_chain: Dictionary[Node, Transform3D] = {}
	var cursor: Node = target
	var accumulated: Transform3D = Transform3D.IDENTITY
	while cursor != null:
		target_chain[cursor] = accumulated
		if cursor is Node3D:
			accumulated = (cursor as Node3D).transform * accumulated
		cursor = cursor.get_parent()
	cursor = node
	accumulated = Transform3D.IDENTITY
	while cursor != null:
		if target_chain.has(cursor):
			return target_chain[cursor].affine_inverse() * accumulated
		if cursor is Node3D:
			accumulated = (cursor as Node3D).transform * accumulated
		cursor = cursor.get_parent()
	return target.global_transform.affine_inverse() * node.global_transform


static func _triangle_bounds(triangles: PackedVector3Array) -> Array[AABB]:
	var bounds: Array[AABB] = []
	for index: int in range(0, triangles.size(), 3):
		bounds.append(AABB(triangles[index], Vector3.ZERO).expand(triangles[index + 1]).expand(triangles[index + 2]))
	return bounds


## Actual indexed head geometry; AABBs are candidate pruning only. Surface
## crossings supplement the Director's vertex-inside rule so a thin seat part
## cannot pass between head vertices. Non-backrest proximity alone is allowed.
static func measure_surfaces(vertices: PackedVector3Array, head_triangles: PackedVector3Array,
		parts: Array[Dictionary], backrest_status: String) -> Dictionary:
	if vertices.is_empty() or head_triangles.is_empty() or head_triangles.size() % 3 != 0 or parts.is_empty():
		return {"error": "surface measurement needs referenced head triangles and seat parts", "passes": false}
	var head_boxes: Array[AABB] = _triangle_bounds(head_triangles)
	var inside: Dictionary[Vector3, bool] = {}
	var maximum_depth: float = 0.0
	var crossing_witnesses: int = 0
	var intrusion_parts: Array[Dictionary] = []
	var intrusion_paths: PackedStringArray = []
	var backrest_paths: PackedStringArray = []
	var nearest_path: String = ""
	var backrest_squared: float = INF
	var seat_triangle_count: int = 0
	for part: Dictionary in parts:
		var faces: PackedVector3Array = part["triangles"]
		if faces.is_empty() or faces.size() % 3 != 0:
			return {"error": "seat part has no complete triangles", "passes": false}
		var bounds: AABB = part["bounds"]
		var boxes: Array[AABB] = part["triangle_bounds"]
		seat_triangle_count += faces.size() / 3
		var part_inside: int = 0
		var part_depth: float = 0.0
		for vertex: Vector3 in vertices:
			# Strict AABB interior is necessary for strict solid interior. A
			# boundary point is not penetration; no positive gap is imposed here.
			if vertex.x <= bounds.position.x or vertex.x >= bounds.end.x \
					or vertex.y <= bounds.position.y or vertex.y >= bounds.end.y \
					or vertex.z <= bounds.position.z or vertex.z >= bounds.end.z:
				continue
			var depth: float = _inside_depth(vertex, faces, boxes)
			if depth > 0.0:
				inside[vertex] = true
				part_inside += 1
				part_depth = maxf(part_depth, depth)
		maximum_depth = maxf(maximum_depth, part_depth)
		var crosses: bool = false
		for head_index: int in range(head_boxes.size()):
			if _box_distance_squared(head_boxes[head_index], bounds) > 0.0:
				continue
			for seat_index: int in range(boxes.size()):
				if _box_distance_squared(head_boxes[head_index], boxes[seat_index]) > 0.0:
					continue
				if _triangles_cross(head_triangles, head_index * 3, faces, seat_index * 3):
					crosses = true
					break
			if crosses:
				break
		if crosses:
			crossing_witnesses += 1
		if part_inside > 0 or crosses:
			intrusion_paths.append(part["path"])
			intrusion_parts.append({"path": part["path"], "head_vertices_inside": part_inside,
				"max_vertex_penetration": part_depth, "surface_crossing_witness": crosses})
		if not part["is_backrest"]:
			continue
		backrest_paths.append(part["path"])
		for head_index: int in range(head_boxes.size()):
			if _box_distance_squared(head_boxes[head_index], bounds) >= backrest_squared:
				continue
			for seat_index: int in range(boxes.size()):
				if _box_distance_squared(head_boxes[head_index], boxes[seat_index]) >= backrest_squared:
					continue
				var squared: float = _triangle_distance_squared(head_triangles, head_index * 3, faces, seat_index * 3)
				if squared < backrest_squared:
					backrest_squared = squared
					nearest_path = part["path"]
	var classified: bool = backrest_status == "backless" or (backrest_status == "named_parts" and not backrest_paths.is_empty())
	var gap: Variant = sqrt(backrest_squared) if backrest_status == "named_parts" and is_finite(backrest_squared) else null
	var gap_passes: bool = backrest_status == "backless" or (gap != null and float(gap) + EPSILON >= REQUIRED_CLEARANCE)
	return {"error": "", "backrest_clearance": gap, "backrest_status": backrest_status,
		"backrest_parts": backrest_paths, "nearest_backrest_part": nearest_path,
		"clearance_metric": CLEARANCE_METRIC, "measurement_complete": classified,
		"head_vertices_inside_count": inside.size(), "max_head_vertex_penetration": maximum_depth,
		"head_seat_surface_crossings": crossing_witnesses, "intrusion_parts": intrusion_paths, "intrusion_details": intrusion_parts,
		"head_tested_vertices_unique": vertices.size(), "head_triangles": head_triangles.size() / 3,
		"seat_triangles": seat_triangle_count,
		"passes": classified and gap_passes and inside.is_empty() and crossing_witnesses == 0}


static func _inside_depth(point: Vector3, triangles: PackedVector3Array, boxes: Array[AABB]) -> float:
	var angle: float = 0.0
	for index: int in range(0, triangles.size(), 3):
		var a: Vector3 = triangles[index] - point
		var b: Vector3 = triangles[index + 1] - point
		var c: Vector3 = triangles[index + 2] - point
		if a.length_squared() == 0.0 or b.length_squared() == 0.0 or c.length_squared() == 0.0:
			return 0.0
		if (b - a).cross(c - a).length_squared() == 0.0:
			continue
		var denominator: float = a.length() * b.length() * c.length() \
			+ a.dot(b) * c.length() + b.dot(c) * a.length() + c.dot(a) * b.length()
		angle += 2.0 * atan2(a.dot(b.cross(c)), denominator)
	if absf(angle) <= TAU:
		return 0.0
	var squared: float = INF
	for index: int in range(boxes.size()):
		var box: AABB = boxes[index]
		var closest: Vector3 = point.clamp(box.position, box.end)
		if point.distance_squared_to(closest) >= squared:
			continue
		squared = minf(squared, _point_triangle_distance_squared(point, triangles[index * 3], triangles[index * 3 + 1], triangles[index * 3 + 2]))
	return sqrt(squared)


static func _triangles_cross(a: PackedVector3Array, ai: int, b: PackedVector3Array, bi: int) -> bool:
	for edge: int in range(3):
		if _edge_crosses_face(a[ai + edge], a[ai + (edge + 1) % 3], b[bi], b[bi + 1], b[bi + 2]) \
				or _edge_crosses_face(b[bi + edge], b[bi + (edge + 1) % 3], a[ai], a[ai + 1], a[ai + 2]):
			return true
	return false


static func _edge_crosses_face(p: Vector3, q: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var normal: Vector3 = (b - a).cross(c - a)
	var denominator: float = normal.dot(q - p)
	if denominator == 0.0:
		return false
	var fraction: float = normal.dot(a - p) / denominator
	if fraction <= 0.0 or fraction >= 1.0:
		return false
	return _inside_triangle(p.lerp(q, fraction), a, b, c, normal)


static func _inside_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> bool:
	return normal.dot((b - a).cross(point - a)) >= 0.0 \
		and normal.dot((c - b).cross(point - b)) >= 0.0 \
		and normal.dot((a - c).cross(point - c)) >= 0.0


static func _triangle_distance_squared(a: PackedVector3Array, ai: int, b: PackedVector3Array, bi: int) -> float:
	if _triangles_cross(a, ai, b, bi):
		return 0.0
	var squared: float = INF
	for vertex: int in range(3):
		squared = minf(squared, _point_triangle_distance_squared(a[ai + vertex], b[bi], b[bi + 1], b[bi + 2]))
		squared = minf(squared, _point_triangle_distance_squared(b[bi + vertex], a[ai], a[ai + 1], a[ai + 2]))
		for edge: int in range(3):
			squared = minf(squared, _segment_distance_squared(a[ai + vertex], a[ai + (vertex + 1) % 3], b[bi + edge], b[bi + (edge + 1) % 3]))
	return squared


static func _hip_support(person: PersonView, parts: Array[Dictionary], scene: String) -> Dictionary:
	var result: Dictionary = {"hips_supported": null, "hip_support_parts": PackedStringArray(),
		"hip_bone_positions": [], "hip_support_points": []}
	if scene != "diner_booth" and scene != "diner_stool":
		return result
	var paths: PackedStringArray = []
	var positions: Array = []
	var support_points: Array = []
	var supported: bool = true
	for name: String in ["leg-left", "leg-right"]:
		var bone: int = person._skeleton.find_bone(name)
		if bone < 0:
			supported = false
			continue
		var hip: Vector3 = _between_nodes(person._skeleton, person) * person._skeleton.get_bone_global_pose(bone).origin
		positions.append([hip.x, hip.y, hip.z])
		var hit: Dictionary = _downward_support(hip, parts, true)
		var path: String = hit["path"]
		if path.is_empty():
			supported = false
		else:
			paths.append(path)
			var point: Vector3 = hit["point"]
			support_points.append([point.x, point.y, point.z])
	result["hips_supported"] = supported
	result["hip_support_parts"] = paths
	result["hip_bone_positions"] = positions
	result["hip_support_points"] = support_points
	return result


## Nine representative exception-eligibility trials, not extra catalogue rows.
## This translates immutable actual pose geometry; no person/data/sim mutates.
## The maximum supported <=0.05 trial must still physically fail for a kit ID
## to qualify. Support is compared with the same native hip ray's baseline
## surface height, avoiding a guessed cushion height for joined kit meshes.
static func supported_offset_trial(person: PersonView, seat: Node3D, parts: Array[Dictionary], current_offset: float) -> Dictionary:
	var head: Dictionary = prepare_head(person)
	if not String(head["error"]).is_empty():
		return head
	var delta: Vector3 = Vector3.FORWARD * (0.05 - current_offset)
	var vertices: PackedVector3Array = []
	var faces: PackedVector3Array = []
	for point: Vector3 in head["vertices"]:
		vertices.append(point + delta)
	for point: Vector3 in head["triangles"]:
		faces.append(point + delta)
	var result: Dictionary = measure_surfaces(vertices, faces, parts, _backrest_status(seat, parts))
	var supported: bool = true
	var points: Array = []
	for name: String in ["leg-left", "leg-right"]:
		var bone: int = person._skeleton.find_bone(name)
		if bone < 0:
			supported = false
			continue
		var hip: Vector3 = _between_nodes(person._skeleton, person) * person._skeleton.get_bone_global_pose(bone).origin
		var before: Dictionary = _downward_support(hip, parts, false)
		var after: Dictionary = _downward_support(hip + delta, parts, false)
		if String(before["path"]).is_empty() or String(after["path"]).is_empty():
			supported = false
			continue
		var baseline_point: Vector3 = before["point"]
		var trial_point: Vector3 = after["point"]
		if absf(baseline_point.y - trial_point.y) > EPSILON:
			supported = false
		points.append([trial_point.x, trial_point.y, trial_point.z])
	result["trial_forward_offset"] = 0.05
	result["trial_supported"] = supported
	result["trial_support_points"] = points
	return result


static func _downward_support(hip: Vector3, parts: Array[Dictionary], cushions_only: bool) -> Dictionary:
	var nearest: float = INF
	var path: String = ""
	for part: Dictionary in parts:
		if cushions_only and not part["is_cushion"]:
			continue
		var faces: PackedVector3Array = part["triangles"]
		for index: int in range(0, faces.size(), 3):
			var a: Vector3 = faces[index]
			var b: Vector3 = faces[index + 1]
			var c: Vector3 = faces[index + 2]
			var normal: Vector3 = (b - a).cross(c - a)
			var denominator: float = normal.dot(Vector3.DOWN)
			if denominator == 0.0:
				continue
			var distance: float = normal.dot(a - hip) / denominator
			if distance >= 0.0 and distance < nearest and _inside_triangle(hip + Vector3.DOWN * distance, a, b, c, normal):
				nearest = distance
				path = part["path"]
	return {"path": path, "point": hip + Vector3.DOWN * nearest if not path.is_empty() else Vector3.ZERO}


## WITHDRAWN criterion: retained only to interpret the original receipt/source
## regressions. Never call this to accept a seat after Director 6404820766.
static func measure_triangles(head: AABB, triangles: PackedVector3Array) -> Dictionary:
	if triangles.is_empty() or triangles.size() % 3 != 0 or not head.position.is_finite() or not head.end.is_finite():
		return {"error": "clearance requires finite head bounds and complete seat triangles", "passes": false}
	var minimum_squared: float = INF
	var intersections: int = 0
	var solid_angle: float = 0.0
	var center: Vector3 = head.get_center()
	var corners: PackedVector3Array = []
	for corner: int in range(8):
		corners.append(Vector3(head.end.x if corner & 1 else head.position.x,
			head.end.y if corner & 2 else head.position.y, head.end.z if corner & 4 else head.position.z))
	for index: int in range(0, triangles.size(), 3):
		var triangle: PackedVector3Array = [triangles[index], triangles[index + 1], triangles[index + 2]]
		for point: Vector3 in triangle:
			if not point.is_finite():
				return {"error": "seat triangle has a non-finite vertex", "passes": false}
		var triangle_box: AABB = AABB(triangle[0], Vector3.ZERO).expand(triangle[1]).expand(triangle[2])
		var lower_bound: float = _box_distance_squared(head, triangle_box)
		if lower_bound == 0.0:
			var polygon: PackedVector3Array = triangle
			for axis: int in range(3):
				polygon = _clip(polygon, axis, head.position[axis], true)
				polygon = _clip(polygon, axis, head.end[axis], false)
			if not polygon.is_empty():
				intersections += 1
				minimum_squared = 0.0
		# Box-to-box distance is only a lower bound, never the reported gap.
		# Pruning distance work must not skip intersection or winding checks.
		if lower_bound < minimum_squared:
			minimum_squared = minf(minimum_squared, _triangle_box_distance_squared(head, corners, triangle))
		# Winding detects a head wholly enclosed by a closed part even when
		# no boundary touches its bounds. Unlike ray parity, overlapping closed
		# parts with the same winding do not cancel out in pairs.
		var a: Vector3 = triangle[0] - center
		var b: Vector3 = triangle[1] - center
		var c: Vector3 = triangle[2] - center
		var denominator: float = a.length() * b.length() * c.length() \
			+ a.dot(b) * c.length() + b.dot(c) * a.length() + c.dot(a) * b.length()
		if (b - a).cross(c - a).length_squared() > 0.0 \
				and a.length_squared() > 0.0 and b.length_squared() > 0.0 and c.length_squared() > 0.0:
			solid_angle += 2.0 * atan2(a.dot(b.cross(c)), denominator)
	var enclosed: bool = absf(solid_angle) > TAU
	var clearance: float = sqrt(minimum_squared)
	return {"clearance": clearance, "intersecting_triangles": intersections,
		"clearance_metric": WITHDRAWN_AABB_METRIC, "withdrawn_criterion": true,
		"head_center_inside_seat": enclosed,
		"passes": is_finite(clearance) and intersections == 0 and not enclosed and clearance + EPSILON >= REQUIRED_CLEARANCE}


static func _box_distance_squared(a: AABB, b: AABB) -> float:
	var separation: Vector3 = Vector3.ZERO
	for axis: int in range(3):
		separation[axis] = maxf(0.0, maxf(a.position[axis] - b.end[axis], b.position[axis] - a.end[axis]))
	return separation.length_squared()


## For separated convex polyhedra, a closest pair is vertex/face or edge/edge.
## The intersection case is handled by six-plane clipping before this call.
static func _triangle_box_distance_squared(box: AABB, corners: PackedVector3Array, triangle: PackedVector3Array) -> float:
	var minimum: float = INF
	for vertex: Vector3 in triangle:
		minimum = minf(minimum, vertex.distance_squared_to(vertex.clamp(box.position, box.end)))
	for corner: Vector3 in corners:
		minimum = minf(minimum, _point_triangle_distance_squared(corner, triangle[0], triangle[1], triangle[2]))
	for corner: int in range(8):
		for axis: int in range(3):
			var bit: int = 1 << axis
			if corner & bit:
				continue
			for edge: int in range(3):
				minimum = minf(minimum, _segment_distance_squared(
					corners[corner], corners[corner | bit], triangle[edge], triangle[(edge + 1) % 3]))
	return minimum


static func _segment_distance_squared(p: Vector3, q: Vector3, r: Vector3, s: Vector3) -> float:
	var u: Vector3 = q - p
	var v: Vector3 = s - r
	var w: Vector3 = p - r
	var a: float = u.dot(u)
	var b: float = u.dot(v)
	var c: float = v.dot(v)
	var d: float = u.dot(w)
	var e: float = v.dot(w)
	if a == 0.0:
		return _point_segment_distance_squared(p, r, s)
	if c == 0.0:
		return _point_segment_distance_squared(r, p, q)
	var determinant: float = a * c - b * b
	# Use no fixed parallel epsilon: short bevel edges still have meaningful
	# interior closest points at this art scale. Exact parallel segments start
	# with the first endpoint and clamp the other parameter below.
	var first: float = clampf((b * e - c * d) / determinant, 0.0, 1.0) if determinant > 0.0 else 0.0
	var second: float = (b * first + e) / c
	if second < 0.0:
		second = 0.0
		first = clampf(-d / a, 0.0, 1.0)
	elif second > 1.0:
		second = 1.0
		first = clampf((b - d) / a, 0.0, 1.0)
	return (w + u * first - v * second).length_squared()


static func _point_segment_distance_squared(point: Vector3, a: Vector3, b: Vector3) -> float:
	var edge: Vector3 = b - a
	var squared: float = edge.length_squared()
	var fraction: float = clampf((point - a).dot(edge) / squared, 0.0, 1.0) if squared > 0.0 else 0.0
	return point.distance_squared_to(a + edge * fraction)


static func _point_triangle_distance_squared(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal: Vector3 = (b - a).cross(c - a)
	var squared: float = normal.length_squared()
	# Degenerate triangles reduce to segments; no plane division in that case.
	if squared > 0.0:
		var height: float = (point - a).dot(normal)
		var projected: Vector3 = point - normal * (height / squared)
		if normal.dot((b - a).cross(projected - a)) >= 0.0 \
				and normal.dot((c - b).cross(projected - b)) >= 0.0 \
				and normal.dot((a - c).cross(projected - c)) >= 0.0:
			return height * height / squared
	return minf(_point_segment_distance_squared(point, a, b),
		minf(_point_segment_distance_squared(point, b, c), _point_segment_distance_squared(point, c, a)))


static func _clip(points: PackedVector3Array, axis: int, boundary: float, keep_greater: bool) -> PackedVector3Array:
	var output: PackedVector3Array = []
	if points.is_empty():
		return output
	var previous: Vector3 = points[points.size() - 1]
	var previous_inside: bool = previous[axis] >= boundary if keep_greater else previous[axis] <= boundary
	for current: Vector3 in points:
		var current_inside: bool = current[axis] >= boundary if keep_greater else current[axis] <= boundary
		if current_inside != previous_inside:
			var fraction: float = (boundary - previous[axis]) / (current[axis] - previous[axis])
			output.append(previous.lerp(current, fraction))
		if current_inside:
			output.append(current)
		previous = current
		previous_inside = current_inside
	return output
