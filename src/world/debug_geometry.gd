class_name DebugGeometry
extends Node3D
## Presentation-only geometry in the shop's local, origin-zero coordinate space.
## Positions are drawn foot positions supplied by ShopView, never agent cells.

const PATH_HEIGHT: float = 0.025
const RING_HEIGHT: float = 0.03
const RING_COLOR: Color = Color("F8D77A")

var _ring: MeshInstance3D
var _paths: Node3D
var _path_nodes: Dictionary[int, MeshInstance3D] = {}
var _materials: Dictionary[Color, StandardMaterial3D] = {}


## Rebuilds remaining segments without advancing or otherwise editing the world.
## Missing agents/positions, null worlds and hidden paths clear stale geometry.
func update_geometry(world: SimWorld, positions: Dictionary[int, Vector3],
		colors: Dictionary[int, Color], selected_agent_id: int, paths_visible: bool) -> void:
	_ensure_nodes()
	_ring.hide()
	if world == null:
		_clear_paths()
		return
	if world.agent(selected_agent_id) != null and positions.has(selected_agent_id):
		var selected: Vector3 = positions[selected_agent_id]
		if selected.is_finite():
			_ring.position = Vector3(selected.x, RING_HEIGHT, selected.z)
			_ring.show()
	var alive: Dictionary[int, bool] = {}
	if paths_visible:
		for agent: SimAgent in world.agents:
			if not positions.has(agent.id) or not positions[agent.id].is_finite():
				continue
			var vertices: PackedVector3Array = _remaining_segments(agent, positions[agent.id])
			if vertices.is_empty():
				continue
			alive[agent.id] = true
			var node: MeshInstance3D = _path_node(agent.id)
			var mesh: ImmediateMesh = node.mesh as ImmediateMesh
			mesh.clear_surfaces()
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			for vertex: Vector3 in vertices:
				mesh.surface_add_vertex(vertex)
			mesh.surface_end()
			node.material_override = _material(colors.get(agent.id, Color.WHITE))
	for id: int in _path_nodes.keys():
		if not alive.has(id):
			_remove_path(id)


func _remaining_segments(agent: SimAgent, drawn: Vector3) -> PackedVector3Array:
	var vertices: PackedVector3Array = []
	var previous: Vector3 = Vector3(drawn.x, PATH_HEIGHT, drawn.z)
	for index: int in range(maxi(0, agent.path_index), agent.path.size()):
		var next: Vector3 = GridMath.cell_to_world(agent.path[index])
		next.y = PATH_HEIGHT
		if not previous.is_equal_approx(next):
			vertices.append(previous)
			vertices.append(next)
		previous = next
	return vertices


func _ensure_nodes() -> void:
	if _ring != null:
		return
	_ring = MeshInstance3D.new()
	_ring.name = "SelectionRing"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.30
	torus.outer_radius = 0.34
	torus.rings = 32
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.material_override = _material(RING_COLOR)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.hide()
	add_child(_ring)
	_paths = Node3D.new()
	_paths.name = "Paths"
	add_child(_paths)


func _path_node(id: int) -> MeshInstance3D:
	if not _path_nodes.has(id):
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "Agent%d" % id
		node.mesh = ImmediateMesh.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_paths.add_child(node)
		_path_nodes[id] = node
	return _path_nodes[id]


func _remove_path(id: int) -> void:
	var node: MeshInstance3D = _path_nodes[id]
	_paths.remove_child(node)
	node.free()
	_path_nodes.erase(id)


func _clear_paths() -> void:
	for id: int in _path_nodes.keys():
		_remove_path(id)


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		_materials[color] = material
	return _materials[color]
