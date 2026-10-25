class_name SeatedHeadGeometry
extends RefCounted
## Offline review geometry, never used to fit or move a person at runtime.
## Skinning follows Skeleton3D's pose_global * inverse_bind and MeshInstance3D's
## weighted vertex bake. get_aabb() is deliberately never used for a person.
## See Godot scene/3d/{skeleton_3d,mesh_instance_3d}.cpp and class_meshinstance3d.

const REQUIRED_CLEARANCE: float = 0.02
const EPSILON: float = 0.000001
const PROVENANCE: String = "native Mini head-mesh POSITION/JOINTS/WEIGHTS, imported Skin inverse binds, current Skeleton3D global poses, actual node transforms"


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


## Clip triangles, not their AABBs: vertices outside the head's X/Y span can
## still form a face through its middle. Two-sided geometry ignores winding.
## The bounds are conservative: all real head geometry lies inside them.
static func measure_triangles(head: AABB, triangles: PackedVector3Array) -> Dictionary:
	var clearance: float = INF
	var intersections: int = 0
	var solid_angle: float = 0.0
	var center: Vector3 = head.get_center()
	for index: int in range(0, triangles.size(), 3):
		var triangle: PackedVector3Array = [triangles[index], triangles[index + 1], triangles[index + 2]]
		var polygon: PackedVector3Array = triangle
		for axis: int in [0, 1]:
			polygon = _clip(polygon, axis, head.position[axis], true)
			polygon = _clip(polygon, axis, head.end[axis], false)
		if not polygon.is_empty():
			var rear: PackedVector3Array = _clip(polygon, 2, center.z, true)
			for point: Vector3 in rear:
				clearance = minf(clearance, point.z - head.end.z)
			var inside: PackedVector3Array = _clip(polygon, 2, head.position.z, true)
			inside = _clip(inside, 2, head.end.z, false)
			if not inside.is_empty():
				intersections += 1
		# Winding detects a head wholly enclosed by a closed part even when
		# no boundary touches its bounds. Unlike ray parity, overlapping closed
		# parts with the same winding do not cancel out in pairs.
		var a: Vector3 = triangle[0] - center
		var b: Vector3 = triangle[1] - center
		var c: Vector3 = triangle[2] - center
		var denominator: float = a.length() * b.length() * c.length() \
			+ a.dot(b) * c.length() + b.dot(c) * a.length() + c.dot(a) * b.length()
		solid_angle += 2.0 * atan2(a.dot(b.cross(c)), denominator)
	var enclosed: bool = absf(solid_angle) > TAU
	return {"clearance": clearance, "intersecting_triangles": intersections,
		"head_center_inside_seat": enclosed,
		"passes": intersections == 0 and not enclosed and clearance + EPSILON >= REQUIRED_CLEARANCE}


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
