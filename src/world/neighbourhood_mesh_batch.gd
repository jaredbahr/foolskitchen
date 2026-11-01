class_name NeighbourhoodMeshBatch
extends RefCounted
## Rebuild-only merging of existing meshes. Optional XZ holes remove copied
## pavement faces, preserving their interpolated normals, UVs and materials.

class Vertex extends RefCounted:
	var point: Vector3
	var normal: Vector3
	var uv: Vector2

	func _init(p: Vector3, n: Vector3, t: Vector2) -> void:
		point = p
		normal = n
		uv = t

var _materials: Array[Material] = []
var _signatures: Array[Array] = []
var _tools: Array[SurfaceTool] = []
var triangles: int = 0


func add_prop(prop: PropView, placement: Transform3D, holes: Array[AABB] = []) -> void:
	_append_node(prop, placement, holes)


func _append_node(node: Node3D, transform: Transform3D, holes: Array[AABB]) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		_append_mesh(mesh_node, transform, holes)
	for child: Node in node.get_children():
		var spatial: Node3D = child as Node3D
		if spatial != null:
			_append_node(spatial, transform * spatial.transform, holes)


func _append_mesh(node: MeshInstance3D, transform: Transform3D, holes: Array[AABB]) -> void:
	var mesh: ArrayMesh = node.mesh as ArrayMesh
	if mesh == null:
		return
	var relevant: Array[AABB] = []
	var bounds: AABB = transform * mesh.get_aabb()
	for hole: AABB in holes:
		if xz_intersects(bounds, hole):
			relevant.append(hole)
	for surface: int in mesh.get_surface_count():
		var material: Material = node.material_override if node.material_override != null else node.get_active_material(surface)
		if material == null:
			continue
		var tool: SurfaceTool = null
		var data: Array = mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
		var texcoords: PackedVector2Array = data[Mesh.ARRAY_TEX_UV] if data[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else positions.size()
		var normal_basis: Basis = transform.basis.inverse().transposed()
		for offset: int in range(0, count - 2, 3):
			var polygon: Array[Vertex] = []
			for corner: int in 3:
				var index: int = indices[offset + corner] if not indices.is_empty() else offset + corner
				polygon.append(Vertex.new(transform * positions[index],
					(normal_basis * normals[index]).normalized() if index < normals.size() else Vector3.UP,
					texcoords[index] if index < texcoords.size() else Vector2.ZERO))
			var fragments: Array[Array] = [polygon]
			for hole: AABB in relevant:
				var next: Array[Array] = []
				for fragment: Array in fragments:
					var typed: Array[Vertex] = []
					typed.assign(fragment)
					next.append_array(_subtract(typed, hole))
				fragments = next
			for fragment: Array in fragments:
				for corner: int in range(1, fragment.size() - 1):
					var a: Vertex = fragment[0]
					var b: Vertex = fragment[corner]
					var c: Vertex = fragment[corner + 1]
					if (b.point - a.point).cross(c.point - a.point).length_squared() < 0.000000000001:
						continue
					if tool == null:
						tool = _tool_for(material)
					for vertex: Vertex in [a, b, c]:
						tool.set_normal(vertex.normal)
						tool.set_uv(vertex.uv)
						tool.add_vertex(vertex.point)
					triangles += 1


func finish(node_name: String) -> MeshInstance3D:
	var mesh: ArrayMesh = ArrayMesh.new()
	for tool: SurfaceTool in _tools:
		tool.commit(mesh)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _tool_for(material: Material) -> SurfaceTool:
	# Imported repeats share materials. Private pavement tints have identical
	# render properties, so merge those too without changing a shared resource.
	var signature: Array = [material.get_class()]
	for property: Dictionary in material.get_property_list():
		var key: String = String(property["name"])
		if (int(property["usage"]) & PROPERTY_USAGE_STORAGE) != 0 and not key.begins_with("resource_"):
			signature.append(key)
			signature.append(material.get(key))
	for index: int in range(_signatures.size()):
		if signature == _signatures[index]:
			return _tools[index]
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(material)
	_materials.append(material)
	_signatures.append(signature)
	_tools.append(tool)
	return tool


static func xz_intersects(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x - 0.000001 and a.end.x > b.position.x + 0.000001 \
		and a.position.z < b.end.z - 0.000001 and a.end.z > b.position.z + 0.000001


static func _subtract(polygon: Array[Vertex], hole: AABB) -> Array[Array]:
	var result: Array[Array] = []
	var remaining: Array[Vertex] = polygon
	for plane: Vector3 in [Vector3(0, hole.position.x, 1), Vector3(0, hole.end.x, -1),
		Vector3(2, hole.position.z, 1), Vector3(2, hole.end.z, -1)]:
		if remaining.size() < 3:
			break
		var outside: Array[Vertex] = _clip(remaining, int(plane.x), plane.y, plane.z < 0.0)
		if outside.size() >= 3:
			result.append(outside)
		remaining = _clip(remaining, int(plane.x), plane.y, plane.z > 0.0)
	return result


static func _clip(polygon: Array[Vertex], axis: int, cut: float, keep_greater: bool) -> Array[Vertex]:
	var result: Array[Vertex] = []
	if polygon.is_empty():
		return result
	var previous: Vertex = polygon[-1]
	var before: float = previous.point[axis] - cut
	var before_inside: bool = before >= 0.0 if keep_greater else before <= 0.0
	for current: Vertex in polygon:
		var after: float = current.point[axis] - cut
		var after_inside: bool = after >= 0.0 if keep_greater else after <= 0.0
		if after_inside != before_inside:
			var weight: float = before / (before - after)
			result.append(Vertex.new(previous.point.lerp(current.point, weight),
				previous.normal.lerp(current.normal, weight).normalized(), previous.uv.lerp(current.uv, weight)))
		if after_inside:
			result.append(current)
		previous = current
		before = after
		before_inside = after_inside
	return result
