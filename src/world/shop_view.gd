class_name ShopView
extends Node3D
## Read-only restaurant view. Simulation ownership stays with the caller.

const GRID_SHADER: Shader = preload("res://src/world/build_grid.gdshader")
const PERSON_SCENE: PackedScene = preload("res://assets/people/person.tscn")
const HEIGHTS: Dictionary[int, float] = {
	ItemDef.Category.TABLE: 0.75, ItemDef.Category.CHAIR: 0.45,
	ItemDef.Category.STATION: 0.9, ItemDef.Category.STORAGE: 0.9,
	ItemDef.Category.PASS: 1.0, ItemDef.Category.DECOR: 0.6,
}
const CUSTOMER_COLORS: Array[Color] = [Color("c8743a"), Color("b89568"), Color("986357")]
## Reuse a curated placeholder swatch rather than introduce a one-off art colour.
const DIRT_SWATCH: SwatchDef = preload("res://data/swatches/walnut.tres")
const CLEANER_SWATCH: SwatchDef = preload("res://data/swatches/sage.tres")
const DIRT_OUTLINE: Array[Vector2] = [
	Vector2(-0.20, -0.09), Vector2(-0.13, 0.14), Vector2(0.03, 0.20),
	Vector2(0.20, 0.04), Vector2(0.12, -0.15),
]

enum WallMode { UP, CUTAWAY, DOWN }

signal wall_mode_changed(mode: int)

const WALL_HEIGHT: float = ArtScale.WALL_HEIGHT
## Distinct from -1 (no model hit), so Main must not select floor furniture through a wall.
const OCCLUDED_ITEM: int = -2
const LOWERED_HEIGHT: float = 0.35
const AWAY_FROM_CAMERA: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1),
]

@export var wall_color: Color = Color("e6d5b8")
@export var wall_top_color: Color = Color("b9a789")
@export var floor_material: ShaderMaterial

var wall_mode: WallMode = WallMode.CUTAWAY
var _camera_quarter: int = 0
var _wall_nodes: Dictionary[Vector2i, MeshInstance3D] = {}

var world: SimWorld
var floor_mesh: MeshInstance3D
var room_dressing: RoomDressing
var item_nodes: Dictionary[int, ItemVisual] = {}
var agent_nodes: Dictionary[int, Node3D] = {}
var dirt_nodes: Dictionary[Vector2i, MeshInstance3D] = {}
var mood_nodes: Dictionary[int, GuestMoodIndicator] = {}
var _mood_states: Dictionary[int, int] = {}
var _mood_bands: Dictionary[int, int] = {}
var _materials: Dictionary[Color, StandardMaterial3D] = {}
var _paint_materials: Dictionary[StringName, StandardMaterial3D] = {}
var _paint_content: ContentDB
var _cleanliness: CleanlinessState
var _shared_dirt_mesh: ArrayMesh
var _shared_dirt_material: StandardMaterial3D
var _wall_swatch_id: StringName = &""
var _floor_swatch_id: StringName = &""
var _floor_base_color: Color = Color("7d5533")
var _preview_kind: StringName = &""
var _preview_item_id: int = -1
var _preview_swatch_id: StringName = &""
var _walls: Node3D
var selection_outline: BoundsOutline
var _selected_item_id: int = -1
var _selection_bounds: AABB


## Replaces a previous world and its signal bindings without modifying either.
func show_world(value: SimWorld) -> void:
	var previous_world: SimWorld = world
	_disconnect_grid()
	mood_nodes.clear()
	_mood_states.clear()
	_mood_bands.clear()
	for child: Node in get_children():
		if child.has_meta("shop_geometry"):
			remove_child(child)
			child.free()
	item_nodes.clear()
	agent_nodes.clear()
	dirt_nodes.clear()
	_wall_nodes.clear()
	floor_mesh = null
	room_dressing = null
	selection_outline = null
	_selected_item_id = -1
	world = value
	if previous_world != value:
		_cleanliness = null
	if world == null:
		return
	floor_mesh = MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.set_meta("shop_geometry", true)
	var material: ShaderMaterial = ShaderMaterial.new()
	if floor_material != null:
		material = floor_material.duplicate() as ShaderMaterial
	if material.shader == null:
		material.shader = GRID_SHADER
	var base: Variant = material.get_shader_parameter("floor_color")
	if base is Color:
		_floor_base_color = base
	floor_mesh.material_override = material
	add_child(floor_mesh)
	_walls = Node3D.new()
	_walls.name = "Walls"
	_walls.set_meta("shop_geometry", true)
	add_child(_walls)
	room_dressing = RoomDressing.new()
	room_dressing.name = "RoomDressing"
	room_dressing.set_meta("shop_geometry", true)
	add_child(room_dressing)
	_build_terrain()
	for item: PlacedItem in world.grid.items():
		_build_item(item)
	_apply_paint()
	_connect_grid()
	_process(0.0)


## Main binds day-local dirt after show_world(). A changed world drops the old
## binding; unchanged spots retain their mesh nodes across rendered frames.
func bind_cleanliness(value: CleanlinessState) -> void:
	_cleanliness = value
	_sync_dirt_spots()


func _enter_tree() -> void:
	_connect_grid()


## Snapshot of the interpolated positions actually drawn, projected to the floor.
func drawn_agent_positions() -> Dictionary[int, Vector3]:
	var positions: Dictionary[int, Vector3] = {}
	if world == null:
		return positions
	for agent: SimAgent in world.agents:
		if agent_nodes.has(agent.id) and is_instance_valid(agent_nodes[agent.id]):
			var position: Vector3 = agent_nodes[agent.id].position
			positions[agent.id] = Vector3(position.x, 0.0, position.z)
	return positions


## Role colours used by the rendered bodies and the read-only debug paths.
func drawn_agent_colors() -> Dictionary[int, Color]:
	var colors: Dictionary[int, Color] = {}
	if world != null:
		for agent: SimAgent in world.agents:
			colors[agent.id] = _agent_color(agent)
	return colors


func _exit_tree() -> void:
	_disconnect_grid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPARENTED:
		_disconnect_grid()


func _connect_grid() -> void:
	if world == null:
		return
	if not world.grid.cells_changed.is_connected(_on_cells_changed):
		world.grid.cells_changed.connect(_on_cells_changed)
	if not world.grid.item_removed.is_connected(_on_item_removed):
		world.grid.item_removed.connect(_on_item_removed)


func _disconnect_grid() -> void:
	if world == null:
		return
	if world.grid.cells_changed.is_connected(_on_cells_changed):
		world.grid.cells_changed.disconnect(_on_cells_changed)
	if world.grid.item_removed.is_connected(_on_item_removed):
		world.grid.item_removed.disconnect(_on_item_removed)


func _build_terrain() -> void:
	for child: Node in _walls.get_children():
		_walls.remove_child(child)
		child.free()
	_wall_nodes.clear()
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = 0
	for y: int in range(world.grid.size.y):
		for x: int in range(world.grid.size.x):
			var cell: Vector2i = Vector2i(x, y)
			var terrain: SimGrid.Terrain = world.grid.terrain(cell)
			if terrain == SimGrid.Terrain.WALL:
				var wall: MeshInstance3D = _box(Vector3(0.5, WALL_HEIGHT, 0.5), wall_color)
				wall.position = GridMath.cell_to_world(cell)
				wall.set_meta("wall_cell", cell)
				var top: MeshInstance3D = _box(Vector3(0.5, 0.02, 0.5), wall_top_color)
				top.name = "Top"
				wall.add_child(top)
				_wall_nodes[cell] = wall
				_walls.add_child(wall)
			elif terrain == SimGrid.Terrain.FLOOR or terrain == SimGrid.Terrain.ENTRY:
				var corner: Vector3 = Vector3(x * GridMath.CELL_SIZE, 0.0, y * GridMath.CELL_SIZE)
				var corners: Array[Vector3] = [corner, corner + Vector3(0.5, 0, 0), corner + Vector3(0.5, 0, 0.5), corner + Vector3(0, 0, 0.5)]
				for index: int in [0, 1, 2, 0, 2, 3]:
					surface.set_normal(Vector3.UP)
					surface.add_vertex(corners[index])
				count += 1
	floor_mesh.mesh = surface.commit() if count > 0 else null
	_apply_wall_heights()
	_apply_paint()
	if room_dressing != null:
		room_dressing.rebuild(world, lowered_wall_cells())


## One material per swatch is shared by every painted mesh, including previews.
func set_paint(content: ContentDB, wall_id: StringName, floor_id: StringName) -> void:
	if _paint_content != content:
		_paint_content = content
		_paint_materials.clear()
		if content != null:
			for swatch: SwatchDef in content.swatches():
				_paint_materials[swatch.id] = _material(swatch.color)
	_wall_swatch_id = wall_id
	_floor_swatch_id = floor_id
	_apply_paint()


func preview_paint(kind: StringName, item_id: int, swatch_id: StringName) -> void:
	if _preview_kind == kind and _preview_item_id == item_id and _preview_swatch_id == swatch_id:
		return
	_preview_kind = kind
	_preview_item_id = item_id
	_preview_swatch_id = swatch_id
	_apply_paint()


func clear_paint_preview() -> void:
	preview_paint(&"", -1, &"")


## Resolve the nearest visible shop mesh before using the floor plane. An item
## returns its origin even when its top projects over a different floor cell.
func paint_cell_at_ray(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	if world == null or ray_direction.y >= -0.00001:
		return null
	var nearest: float = -ray_origin.y / ray_direction.y
	var result: Variant = null
	for id: int in item_nodes:
		var node: ItemVisual = item_nodes[id]
		if not node.is_visible_in_tree():
			continue
		var distance: float = _ray_box_distance(ray_origin, ray_direction, node.global_transform * node.get_aabb())
		if distance >= 0.0 and distance < nearest:
			var item: PlacedItem = world.grid.item(id)
			if item != null:
				nearest = distance
				result = item.origin
	for cell: Vector2i in _wall_nodes:
		var wall: MeshInstance3D = _wall_nodes[cell]
		if not wall.is_visible_in_tree():
			continue
		var distance: float = _ray_box_distance(ray_origin, ray_direction, wall.global_transform * wall.get_aabb())
		if distance >= 0.0 and distance < nearest:
			nearest = distance
			result = cell
	return result


## Nearest combined item bounds before the floor, or -1 for floor fallback.
## OCCLUDED_ITEM means a wall is in front: callers retain agent priority but
## must not fall back to a furniture cell behind that wall.
func item_at_ray(ray_origin: Vector3, ray_direction: Vector3) -> int:
	if world == null or ray_direction.y >= -0.00001:
		return -1
	var nearest: float = -ray_origin.y / ray_direction.y
	var result: int = -1
	for wall: MeshInstance3D in _wall_nodes.values():
		if not wall.is_visible_in_tree():
			continue
		var distance: float = _ray_box_distance(ray_origin, ray_direction, wall.global_transform * wall.get_aabb())
		if distance >= 0.0 and distance < nearest:
			nearest = distance
			result = OCCLUDED_ITEM
	for id: int in item_nodes:
		var node: ItemVisual = item_nodes[id]
		if not node.is_visible_in_tree():
			continue
		var distance: float = _ray_box_distance(ray_origin, ray_direction, node.global_transform * node.get_aabb())
		if distance >= 0.0 and (distance < nearest or (distance == nearest and result >= 0 and id < result)):
			nearest = distance
			result = id
	return result


## Shop-local displayed bounds, shared by diagnostics and selection tests.
func item_bounds(id: int) -> AABB:
	var node: ItemVisual = item_nodes.get(id) as ItemVisual
	return node.transform * node.get_aabb() if is_instance_valid(node) else AABB()


func set_selected_item(id: int) -> void:
	_selected_item_id = id
	_sync_item_selection()


func refresh_item_selection() -> void:
	_sync_item_selection()


func _sync_item_selection() -> void:
	var node: ItemVisual = item_nodes.get(_selected_item_id) as ItemVisual
	if not is_instance_valid(node) or not node.visible:
		if is_instance_valid(selection_outline):
			selection_outline.hide()
		return
	var bounds: AABB = node.get_aabb()
	if not is_instance_valid(selection_outline):
		selection_outline = BoundsOutline.new()
		selection_outline.name = "ItemSelection"
		selection_outline.set_meta("shop_geometry", true)
		add_child(selection_outline)
		selection_outline.draw_bounds(bounds, DebugGeometry.RING_COLOR)
	elif bounds != _selection_bounds:
		selection_outline.draw_bounds(bounds, DebugGeometry.RING_COLOR)
	_selection_bounds = bounds
	selection_outline.transform = node.transform
	selection_outline.set_meta("item_id", _selected_item_id)
	selection_outline.show()


## Wall-only query retained for wall geometry diagnostics.
func wall_cell_at_ray(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	if world == null or ray_direction.y >= -0.00001:
		return null
	var nearest: float = -ray_origin.y / ray_direction.y
	var result: Variant = null
	for cell: Vector2i in _wall_nodes:
		var wall: MeshInstance3D = _wall_nodes[cell]
		if not wall.is_visible_in_tree():
			continue
		var bounds: AABB = wall.global_transform * wall.get_aabb()
		var distance: float = _ray_box_distance(ray_origin, ray_direction, bounds)
		if distance >= 0.0 and distance < nearest:
			nearest = distance
			result = cell
	return result


static func _ray_box_distance(ray_origin: Vector3, ray_direction: Vector3, bounds: AABB) -> float:
	var near: float = 0.0
	var far: float = INF
	for axis: int in 3:
		var start: float = ray_origin[axis]
		var direction: float = ray_direction[axis]
		var minimum: float = bounds.position[axis]
		var maximum: float = bounds.end[axis]
		if absf(direction) < 0.00001:
			if start < minimum or start > maximum:
				return -1.0
			continue
		var first: float = (minimum - start) / direction
		var last: float = (maximum - start) / direction
		near = maxf(near, minf(first, last))
		far = minf(far, maxf(first, last))
		if far < near:
			return -1.0
	return near


func _paint_color(id: StringName, fallback: Color) -> Color:
	var swatch: SwatchDef = _paint_content.swatch(id) if _paint_content != null else null
	return swatch.color if swatch != null else fallback


func _paint_material(id: StringName, fallback: Color) -> StandardMaterial3D:
	return _paint_materials[id] if _paint_materials.has(id) else _material(fallback)


func _apply_paint() -> void:
	if world == null or floor_mesh == null:
		return
	var wall_id: StringName = _preview_swatch_id if _preview_kind == &"wall" else _wall_swatch_id
	for wall: MeshInstance3D in _wall_nodes.values():
		wall.material_override = _paint_material(wall_id, wall_color)
	var floor_id: StringName = _preview_swatch_id if _preview_kind == &"floor" else _floor_swatch_id
	var floor_shader: ShaderMaterial = floor_mesh.material_override as ShaderMaterial
	if floor_shader != null:
		floor_shader.set_shader_parameter("floor_color", _paint_color(floor_id, _floor_base_color))
	for id: int in item_nodes:
		var placed: PlacedItem = world.grid.item(id)
		if placed == null or not placed.def is ItemDef:
			continue
		var definition: ItemDef = placed.def as ItemDef
		var swatch_id: StringName = _preview_swatch_id if _preview_kind == &"item" and id == _preview_item_id else placed.swatch_id
		var swatch: SwatchDef = _paint_content.swatch(swatch_id) if _paint_content != null else null
		if definition.paintable and swatch != null:
			item_nodes[id].apply_paint(swatch.color, _paint_material(swatch_id, definition.placeholder_color))
		else:
			item_nodes[id].clear_paint()


## Selects the wall presentation without changing terrain or pathfinding.
func set_wall_mode(mode: WallMode) -> void:
	if mode < WallMode.UP or mode > WallMode.DOWN or mode == wall_mode:
		return
	wall_mode = mode
	_apply_wall_heights()
	wall_mode_changed.emit(wall_mode)


## Cycles Up -> Cutaway -> Down -> Up; Cutaway is the initial mode.
func cycle_wall_mode() -> void:
	set_wall_mode((int(wall_mode) + 1) % 3)


## Matches the camera's rotation target rather than its interpolated angle.
func set_camera_quarter(quarter: int) -> void:
	_camera_quarter = posmod(quarter, 4)
	_apply_wall_heights()


## Returns the currently lowered cells in stable row order for diagnostics.
func lowered_wall_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if world == null:
		return cells
	for y: int in range(world.grid.size.y):
		for x: int in range(world.grid.size.x):
			var cell: Vector2i = Vector2i(x, y)
			if _wall_nodes.has(cell) and _wall_is_lowered(cell):
				cells.append(cell)
	return cells


func _wall_is_lowered(cell: Vector2i) -> bool:
	if wall_mode != WallMode.CUTAWAY:
		return wall_mode == WallMode.DOWN
	var direction: Vector2i = AWAY_FROM_CAMERA[_camera_quarter]
	for distance: int in range(1, 3):
		var terrain: SimGrid.Terrain = world.grid.terrain(cell + direction * distance)
		if terrain == SimGrid.Terrain.FLOOR:
			return true
	return false


func _apply_wall_heights() -> void:
	for cell: Vector2i in _wall_nodes:
		var wall: MeshInstance3D = _wall_nodes[cell]
		var height: float = LOWERED_HEIGHT if _wall_is_lowered(cell) else WALL_HEIGHT
		(wall.mesh as BoxMesh).size.y = height
		wall.position.y = height * 0.5
		(wall.get_node("Top") as MeshInstance3D).position.y = height * 0.5 + 0.005
	if room_dressing != null:
		room_dressing.set_lowered_walls(lowered_wall_cells())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if key.pressed and not key.echo and code == KEY_C:
			cycle_wall_mode()


func _build_item(item: PlacedItem) -> void:
	var definition: ItemDef = item.def as ItemDef
	if definition == null or (definition.category == ItemDef.Category.DOOR and definition.view_scene == null):
		return
	var node: ItemVisual = item_nodes.get(item.id) as ItemVisual
	if node == null:
		var height: float = HEIGHTS.get(definition.category, 0.6)
		node = ItemVisual.create(definition, height, _material(definition.placeholder_color))
		node.name = "Item%d" % item.id
		node.set_meta("item_id", item.id)
		node.set_meta("shop_geometry", true)
		item_nodes[item.id] = node
		add_child(node)
	# Relocation retains the item/definition. An edit on either shared layer
	# updates placement without replacing the surviving wrapper or its paint.
	node.transform = ItemVisual.placed_transform(definition, item.origin, item.quarter_turns)
	node.rotation.y = -item.quarter_turns * PI * 0.5
	_sync_item_selection()


func _remove_item(id: int) -> void:
	if item_nodes.has(id):
		var node: ItemVisual = item_nodes[id]
		remove_child(node)
		node.free()
		item_nodes.erase(id)
		_sync_item_selection()


func _on_cells_changed(cells: Array[Vector2i]) -> void:
	_build_terrain()
	var affected: Dictionary[int, bool] = {}
	for cell: Vector2i in cells:
		for item: PlacedItem in world.grid.items_at(cell):
			affected[item.id] = true
	for id: int in affected:
		_build_item(world.grid.item(id))
	_apply_paint()
	_sync_dirt_spots()


func _on_item_removed(item: PlacedItem) -> void:
	_remove_item(item.id)


func _process(_delta: float) -> void:
	if world == null:
		return
	_sync_dirt_spots()
	_sync_item_selection()
	_sync_agents()


func _sync_agents() -> void:
	var frames: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(
		world.agents, world, _dining_seat_heights(), _dining_seat_facings(), _dining_seat_offsets())
	var playback_speed: float = _agent_playback_speed()
	var alive: Dictionary[int, bool] = {}
	for agent: SimAgent in world.agents:
		alive[agent.id] = true
		var frame: AgentPresentationController.Frame = frames[agent.id]
		if agent_nodes.has(agent.id) and (agent_nodes[agent.id] is PersonView) != frame.look_supported:
			_remove_agent_visual(agent.id)
		if not agent_nodes.has(agent.id):
			var created: Node3D = PERSON_SCENE.instantiate() as PersonView if frame.look_supported else _legacy_person_fallback(agent)
			if created is PersonView:
				# _ready runs on add_child; record the real look before rig creation.
				(created as PersonView).set_look(frame.role, frame.id, frame.customer_type)
			created.name = "Agent%d" % agent.id
			created.set_meta("agent_id", agent.id)
			created.set_meta("shop_geometry", true)
			created.set_meta("unsupported_role", not frame.look_supported)
			# Keep FK-079's exact tray shape. Its size beside Mini Characters is
			# an open visual gate pending one coordinated uniform presentation scale.
			var tray: MeshInstance3D = _box(Vector3(0.68, 0.045, 0.38), Color("b89568"))
			tray.name = "Tray"
			tray.visible = false
			created.add_child(tray)
			agent_nodes[agent.id] = created
			add_child(created)
		var node: Node3D = agent_nodes[agent.id]
		var ready_person: bool = false
		if node is PersonView:
			ready_person = AgentPresentationController.apply(frame, node as PersonView, playback_speed)
		else:
			node.position = frame.floor_position + frame.display_offset + Vector3(0.0, 0.875, 0.0)
			if frame.facing_direction.length_squared() > 0.000001:
				node.rotation.y = atan2(-frame.facing_direction.x, -frame.facing_direction.z)
		node.set_meta("person_ready", ready_person)
		node.set_meta("display_separation_blocked", frame.separation_blocked)
		var tray: MeshInstance3D = node.get_node("Tray") as MeshInstance3D
		tray.visible = frame.show_tray and (ready_person or not frame.look_supported)
		tray.position = frame.tray_anchor if ready_person else Vector3(0.0, 0.02, -0.48)
		_update_guest_mood(agent, node, frame)
	for id: int in agent_nodes.keys():
		if not alive.has(id):
			_remove_agent_visual(id)


func _agent_playback_speed() -> float:
	if world == null or world.clock.phase not in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
		return 0.0
	# --script capture loads this class before autoload names are identifiers.
	# The same root Clock node owns speed in captures, tests and the game.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var clock_node: Node = tree.root.get_node_or_null("Clock") if tree != null else null
	if clock_node == null:
		return 0.0
	var speed: Variant = clock_node.get("speed")
	return maxf(float(speed), 0.0) if speed is int else 0.0


## ART_STYLE has no Cleaner mapping yet. Keep its old capsule visibly explicit;
## this temporary hook prevents claiming full visual readiness for FK-053.
func _legacy_person_fallback(agent: SimAgent) -> MeshInstance3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.height = 1.75
	capsule.radius = 0.25
	capsule.radial_segments = 12
	capsule.rings = 4
	mesh.mesh = capsule
	mesh.material_override = _material(_agent_color(agent))
	var nose: MeshInstance3D = _box(Vector3(0.16, 0.14, 0.22), _agent_color(agent).darkened(0.4))
	nose.name = "FacingMarker"
	nose.position = Vector3(0.0, 0.62, -0.28)
	mesh.add_child(nose)
	return mesh


func _remove_agent_visual(id: int) -> void:
	_remove_mood_icon(id)
	_mood_states.erase(id)
	_mood_bands.erase(id)
	var node: Node3D = agent_nodes[id]
	remove_child(node)
	node.free()
	agent_nodes.erase(id)


## The pure state has no scene signals. A bounded reconciliation observes its
## at-most-twelve spots without allocating replacement meshes every frame.
func _sync_dirt_spots() -> void:
	var wanted: Dictionary[Vector2i, bool] = {}
	if world != null and _cleanliness != null:
		for cell: Vector2i in _cleanliness.spots():
			if world.grid.terrain(cell) != SimGrid.Terrain.FLOOR or not world.grid.is_walkable(cell):
				continue
			wanted[cell] = true
			if dirt_nodes.has(cell):
				continue
			var node: MeshInstance3D = MeshInstance3D.new()
			node.name = "Dirt_%d_%d" % [cell.x, cell.y]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.mesh = _dirt_mesh()
			node.material_override = _dirt_material()
			node.position = GridMath.cell_to_world(cell) + Vector3(0.0, 0.015, 0.0)
			node.rotation.y = float(posmod(cell.x * 3 + cell.y, 4)) * PI * 0.5
			node.set_meta("shop_geometry", true)
			dirt_nodes[cell] = node
			add_child(node)
	for cell: Vector2i in dirt_nodes.keys():
		if wanted.has(cell):
			continue
		var node: MeshInstance3D = dirt_nodes[cell]
		remove_child(node)
		node.free()
		dirt_nodes.erase(cell)


func _dirt_mesh() -> ArrayMesh:
	if _shared_dirt_mesh != null:
		return _shared_dirt_mesh
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(DIRT_OUTLINE.size()):
		# Godot front faces wind clockwise. Keep the lit top on the front side
		# so the two-sided material does not flip its UP normals from above.
		for point: Vector2 in [Vector2.ZERO, DIRT_OUTLINE[(index + 1) % DIRT_OUTLINE.size()], DIRT_OUTLINE[index]]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(point.x, 0.0, point.y))
	_shared_dirt_mesh = surface.commit()
	return _shared_dirt_mesh


func _dirt_material() -> StandardMaterial3D:
	if _shared_dirt_material == null:
		_shared_dirt_material = StandardMaterial3D.new()
		_shared_dirt_material.albedo_color = DIRT_SWATCH.color
		_shared_dirt_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_shared_dirt_material.roughness = 1.0
		_shared_dirt_material.metallic_specular = 0.0
		_shared_dirt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shared_dirt_material


func _update_guest_mood(agent: SimAgent, body: Node3D, frame: AgentPresentationController.Frame) -> void:
	if not agent is CustomerAgent:
		return
	var guest: CustomerAgent = agent as CustomerAgent
	var state: int = int(guest.state)
	var band: int = frame.mood_band
	if frame.look_supported and not frame.anchors_ready:
		# Off-tree scene construction records people; rig anchors follow _ready.
		return
	_mood_states[agent.id] = state
	_mood_bands[agent.id] = band
	if not frame.mood_visible:
		_remove_mood_icon(agent.id)
		return
	if not is_instance_valid(mood_nodes.get(agent.id)):
		var icon: GuestMoodIndicator = GuestMoodIndicator.new()
		body.add_child(icon)
		mood_nodes[agent.id] = icon
	var indicator: GuestMoodIndicator = mood_nodes[agent.id]
	# set_band is idempotent; anchor positioning must still follow every frame.
	indicator.set_band(band)
	indicator.position = frame.mood_anchor if frame.anchors_ready else Vector3.UP * GuestMoodIndicator.HEAD_OFFSET


## Standalone seats supply their measured sitting surface. Accepted built-in
## table chairs and unavailable wrappers retain the presenter's legacy default.
func _dining_seat_heights() -> Dictionary[int, float]:
	var heights: Dictionary[int, float] = {}
	for agent: SimAgent in world.agents:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest == null:
			continue
		var source_id: int = world.grid.dining_furnishing_id(guest.seat_cell)
		if source_id == 0 or source_id == guest.table_item_id:
			continue
		var visual: ItemVisual = item_nodes.get(source_id) as ItemVisual
		if visual != null and visual.prop != null:
			var height: float = visual.prop.seat_surface_height()
			if height > 0.0:
				heights[guest.id] = height
	return heights


## A bench's guests face its authored forward surface, rather than turning
## diagonally toward the centre of a long table. No simulation cell is moved.
func _dining_seat_facings() -> Dictionary[int, Vector3]:
	var facings: Dictionary[int, Vector3] = {}
	for agent: SimAgent in world.agents:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest != null:
			facings[guest.id] = _dining_seat_facing(guest)
	return facings


## Content offsets affect only the drawn seated pose, never cells or reservations.
func _dining_seat_offsets() -> Dictionary[int, float]:
	var offsets: Dictionary[int, float] = {}
	for agent: SimAgent in world.agents:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest == null:
			continue
		var source: PlacedItem = world.grid.item(world.grid.dining_furnishing_id(guest.seat_cell))
		var definition: ItemDef = source.def as ItemDef if source != null else null
		if definition != null:
			offsets[guest.id] = definition.seated_forward_offset
	return offsets


func _dining_seat_facing(guest: CustomerAgent) -> Vector3:
	var source_id: int = world.grid.dining_furnishing_id(guest.seat_cell)
	if source_id == 0 or source_id == guest.table_item_id:
		return Vector3.ZERO
	var source: PlacedItem = world.grid.item(source_id)
	var definition: ItemDef = source.def as ItemDef if source != null else null
	if definition == null or definition.category != ItemDef.Category.CHAIR:
		return Vector3.ZERO
	var origin: Vector2i = GridMath.rotate_cell(Vector2i.ZERO, definition.footprint, source.quarter_turns)
	var forward: Vector2i = GridMath.rotate_cell(Vector2i.UP, definition.footprint, source.quarter_turns) - origin
	return Vector3(forward.x, 0.0, forward.y)


func _remove_mood_icon(id: int) -> void:
	if not mood_nodes.has(id):
		return
	var icon: GuestMoodIndicator = mood_nodes[id]
	if is_instance_valid(icon):
		var parent: Node = icon.get_parent()
		if parent != null:
			parent.remove_child(icon)
		icon.free()
	mood_nodes.erase(id)


func _agent_color(agent: SimAgent) -> Color:
	match agent.role:
		&"cook": return Color("f3e6cc")
		&"server": return Color("408b85")
		&"cleaner": return CLEANER_SWATCH.color
		&"owner": return Color("c9a346")
	return CUSTOMER_COLORS[posmod(agent.id, CUSTOMER_COLORS.size())]


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color)
	return node


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		_materials[color] = material
	return _materials[color]
