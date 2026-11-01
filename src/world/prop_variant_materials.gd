class_name PropVariantMaterials
extends RefCounted
## Private colour overrides for exact named imported surfaces. No model mutation.
## The owner restores these before disposing/replacing the rendered model.

class Surface:
	extends RefCounted
	var mesh: MeshInstance3D
	var index: int
	var name: StringName
	var original_override: Material
	var source: BaseMaterial3D

var _surfaces: Array[Surface] = []


func _init(root: Node) -> void:
	_collect(root)


## Refuse the whole recipe before changing any surface if a name is unknown.
func apply(variant: ItemVariant) -> bool:
	if variant == null:
		restore()
		return true
	if not variant.valid():
		return false
	var palette: Dictionary[StringName, Color] = KitMaterialColours.colours()
	for name: StringName in variant.material_colours:
		if not palette.has(variant.material_colours[name]) or not _has_surface(name):
			return false
	restore()
	for surface: Surface in _surfaces:
		if not variant.material_colours.has(surface.name):
			continue
		var material: BaseMaterial3D = surface.source.duplicate() as BaseMaterial3D
		var colour: Color = palette[variant.material_colours[surface.name]]
		material.albedo_color = Color(colour.r, colour.g, colour.b, surface.source.albedo_color.a)
		surface.mesh.set_surface_override_material(surface.index, material)
	return true


func restore() -> void:
	for surface: Surface in _surfaces:
		if is_instance_valid(surface.mesh):
			surface.mesh.set_surface_override_material(surface.index, surface.original_override)


func _has_surface(name: StringName) -> bool:
	for surface: Surface in _surfaces:
		if surface.name == name:
			return true
	return false


func _collect(node: Node) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		for index: int in range(mesh_node.mesh.get_surface_count()):
			var imported: Material = mesh_node.mesh.surface_get_material(index)
			var active: BaseMaterial3D = mesh_node.get_active_material(index) as BaseMaterial3D
			if imported == null or active == null:
				continue
			var surface: Surface = Surface.new()
			surface.mesh = mesh_node
			surface.index = index
			surface.name = StringName(imported.resource_name)
			surface.source = active
			surface.original_override = mesh_node.get_surface_override_material(index)
			_surfaces.append(surface)
	for child: Node in node.get_children():
		_collect(child)
