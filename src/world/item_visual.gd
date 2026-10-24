class_name ItemVisual
extends Node3D
## Shared model/box adapter. Its origin is the footprint centre on the floor.
## Bounds belong to this root, so callers never assume a single furniture mesh.

var prop: PropView
var fallback: MeshInstance3D
var _fallback_material: Material


static func create(definition: ItemDef, fallback_height: float, material: Material) -> ItemVisual:
	var result: ItemVisual = ItemVisual.new()
	if definition.view_scene != null:
		var instance: Node = definition.view_scene.instantiate()
		result.prop = instance as PropView
		if result.prop != null:
			result.add_child(result.prop)
			result.prop.prepare()
		else:
			instance.free()
	if result.prop == null:
		result.fallback = MeshInstance3D.new()
		result.fallback.name = "Box"
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(definition.footprint.x * GridMath.CELL_SIZE,
			fallback_height, definition.footprint.y * GridMath.CELL_SIZE)
		result.fallback.mesh = box
		result.fallback.position.y = fallback_height * 0.5
		result._fallback_material = material
		result.fallback.material_override = material
		result.add_child(result.fallback)
	return result


func get_aabb() -> AABB:
	if prop != null:
		return prop.transform * prop.get_combined_aabb()
	if fallback != null:
		return fallback.transform * fallback.get_aabb()
	return AABB()


func apply_paint(color: Color, material: Material) -> void:
	if prop != null:
		prop.set_body_tint(color)
	elif fallback != null:
		fallback.material_override = material


func clear_paint() -> void:
	if prop != null:
		prop.clear_body_tint()
	elif fallback != null:
		fallback.material_override = _fallback_material


func rendered_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_meshes(self, result)
	return result


func primary_body_material() -> BaseMaterial3D:
	if prop != null:
		return prop.active_body_material()
	return fallback.get_active_material(0) as BaseMaterial3D if fallback != null else null


## A build ghost is a separate instance; tint every surface without replacing
## kit textures or mutating the live item's materials. Glass keeps its opacity.
func set_ghost_tint(color: Color) -> void:
	for mesh_node: MeshInstance3D in rendered_meshes():
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh_node.material_override is BaseMaterial3D:
			mesh_node.material_override = _ghost_material(mesh_node.material_override as BaseMaterial3D, color)
		else:
			for index: int in range(mesh_node.mesh.get_surface_count()):
				var source: BaseMaterial3D = mesh_node.get_active_material(index) as BaseMaterial3D
				if source != null:
					mesh_node.set_surface_override_material(index, _ghost_material(source, color))


static func placed_transform(definition: ItemDef, origin: Vector2i, turns: int) -> Transform3D:
	var footprint: Vector2i = GridMath.rotated_footprint(definition.footprint, turns)
	return Transform3D(Basis(Vector3.UP, -turns * PI * 0.5),
		Vector3((origin.x + footprint.x * 0.5) * GridMath.CELL_SIZE, 0.0,
			(origin.y + footprint.y * 0.5) * GridMath.CELL_SIZE))


static func _ghost_material(source: BaseMaterial3D, color: Color) -> BaseMaterial3D:
	var tinted: BaseMaterial3D = source.duplicate() as BaseMaterial3D
	tinted.albedo_color = Color(color.r, color.g, color.b, color.a * source.albedo_color.a)
	tinted.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return tinted


static func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		result.append(mesh_node)
	for child: Node in node.get_children():
		_collect_meshes(child, result)
