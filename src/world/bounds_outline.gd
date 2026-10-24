class_name BoundsOutline
extends Node3D
## Twelve rails around caller-supplied combined bounds, in the caller's space.

const WIDTH: float = 0.025


func draw_bounds(bounds: AABB, color: Color) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	var start: Vector3 = bounds.position
	var finish: Vector3 = bounds.end
	for y: float in [start.y, finish.y]:
		for z: float in [start.z, finish.z]:
			_rail(Vector3(bounds.size.x + WIDTH, WIDTH, WIDTH), Vector3(bounds.get_center().x, y, z), material)
		for x: float in [start.x, finish.x]:
			_rail(Vector3(WIDTH, WIDTH, bounds.size.z + WIDTH), Vector3(x, y, bounds.get_center().z), material)
	for x: float in [start.x, finish.x]:
		for z: float in [start.z, finish.z]:
			_rail(Vector3(WIDTH, bounds.size.y, WIDTH), Vector3(x, bounds.get_center().y, z), material)


func _rail(size: Vector3, centre: Vector3, material: StandardMaterial3D) -> void:
	var rail: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	rail.mesh = box
	rail.material_override = material
	rail.position = centre
	rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rail)
