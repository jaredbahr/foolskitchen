class_name SeatedHeadGeometry
extends RefCounted
## Offline review geometry, never used to fit or move a person at runtime.
## Skinning follows Skeleton3D's pose_global * inverse_bind and MeshInstance3D's
## weighted vertex bake. get_aabb() is deliberately never used for a person.
## See Godot scene/3d/{skeleton_3d,mesh_instance_3d}.cpp and class_meshinstance3d.

const REQUIRED_CLEARANCE: float = 0.02
const EPSILON: float = 0.000001
const PROVENANCE: String = "native Mini head-mesh POSITION/JOINTS/WEIGHTS, imported Skin inverse binds, current Skeleton3D global poses, actual node transforms"
const CLEARANCE_METRIC: String = "minimum Euclidean seat-triangle to conservative posed-head AABB separation"


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
	var instance: MeshInstance3D = head_mesh(person)
	if person == null:
		return {"error": "native person is unavailable"}
	var result: Dictionary = skin_vertices(instance, person._skeleton)
	if not String(result["error"]).is_empty():
		return result
	return _head_bounds(person, instance, result["vertices"])


static func _head_bounds(person: PersonView, instance: MeshInstance3D, vertices: PackedVector3Array) -> Dictionary:
	if vertices.is_empty():
		return {"error": "native head has no vertices"}
	var to_person: Transform3D = person.global_transform.affine_inverse() * instance.global_transform
	var local: AABB = AABB(to_person * vertices[0], Vector3.ZERO)
	var world: AABB = AABB(instance.global_transform * vertices[0], Vector3.ZERO)
	for vertex: Vector3 in vertices:
		local = local.expand(to_person * vertex)
		world = world.expand(instance.global_transform * vertex)
	return {"error": "", "person_bounds": local, "world_bounds": world,
		"head_vertices": vertices.size(), "provenance": PROVENANCE}


## Optional caches contain immutable mesh-local posed vertices and person-local
## seat triangles from the same fixture; production/capture callers omit them.
static func measure(person: PersonView, seat: Node3D, native_bake: bool = false,
		cached_vertices: PackedVector3Array = PackedVector3Array(), cached_triangles: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	var instance: MeshInstance3D = head_mesh(person)
	if person == null:
		return {"error": "native person is unavailable"}
	var result: Dictionary = skin_vertices(instance, person._skeleton) if cached_vertices.is_empty() else {"error": "", "vertices": cached_vertices}
	if not String(result["error"]).is_empty():
		return result
	var vertices: PackedVector3Array = result["vertices"]
	if vertices.is_empty():
		return {"error": "native head has no vertices"}
	if native_bake:
		var comparison: Dictionary = native_bake_error(instance, vertices)
		result["native_bake_max_error"] = comparison["max_error"]
		if not String(comparison["error"]).is_empty():
			result["error"] = comparison["error"]
			return result
	var snapshot: Dictionary = _head_bounds(person, instance, vertices)
	var bounds: AABB = snapshot["person_bounds"]
	var triangles: PackedVector3Array = seat_triangles(seat, person) if cached_triangles.is_empty() else cached_triangles
	if triangles.is_empty():
		return {"error": "seat has no native triangles"}
	var clearance: Dictionary = measure_triangles(bounds, triangles)
	result.erase("vertices")
	result.merge(clearance)
	result.merge(snapshot)
	result["head_bounds"] = bounds
	result["head_vertices"] = vertices.size()
	result["seat_triangles"] = triangles.size() / 3
	return result


static func seat_triangles(seat: Node3D, relative_to: Node3D) -> PackedVector3Array:
	var triangles: PackedVector3Array = []
	for node: Node in seat.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh == null:
			continue
		var transform: Transform3D = relative_to.global_transform.affine_inverse() * instance.global_transform
		for vertex: Vector3 in instance.mesh.get_faces():
			triangles.append(transform * vertex)
	return triangles


## Exact triangle-to-AABB separation, conservative for the real head enclosed
## by that AABB. This includes nearby seat top/side edges outside the head's
## X/Y span. A rear-axis ray/gap cannot enforce their 0.02 clearance.
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
		"clearance_metric": CLEARANCE_METRIC,
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
