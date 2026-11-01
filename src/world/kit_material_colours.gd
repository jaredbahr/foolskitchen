class_name KitMaterialColours
extends RefCounted
## Read colours from unchanged approved kit resources; never invent a palette.

const DONORS: Array[String] = [
	"res://assets/kenney/furniture/bathroomCabinet.glb",
	"res://assets/kenney/furniture/bathroomCabinetDrawer.glb",
	"res://assets/kenney/furniture/bedBunk.glb",
]
static var _colours: Dictionary[StringName, Color] = {}
static var _loaded: bool = false


static func colours() -> Dictionary[StringName, Color]:
	if not _loaded:
		_loaded = true
		for path: String in DONORS:
			var scene: PackedScene = load(path) as PackedScene
			if scene == null:
				continue
			var root: Node = scene.instantiate()
			_collect(root)
			root.free()
	return _colours.duplicate()


static func _collect(node: Node) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		for index: int in range(mesh_node.mesh.get_surface_count()):
			var material: BaseMaterial3D = mesh_node.mesh.surface_get_material(index) as BaseMaterial3D
			if material != null and not _colours.has(StringName(material.resource_name)):
				_colours[StringName(material.resource_name)] = material.albedo_color
	for child: Node in node.get_children():
		_collect(child)
