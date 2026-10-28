extends TestCase
## FK-099 (#187) presentation: the back door's Kenney leaf and path, the door
## swinging with the delivery person, and crates on the floor and in hands.
## View only: nothing here changes the sim.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const DOOR: Vector2i = Vector2i(13, 6)
const DROP: Vector2i = Vector2i(12, 6)

var _view: ShopView
var _sim: RestaurantSim
var _old_speed: int = 0


func before_each() -> void:
	_old_speed = Clock.speed
	Clock.set_speed(0)
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var stock: Stock = Stock.new()
	_sim = RestaurantSim.create(LAYOUT, content, 1, errors, stock)
	assert_eq(errors, [] as Array[String])
	assert_true(_sim.world.grid.set_segment(SimGrid.edge_between(DROP, DOOR), SimGrid.Segment.DOORWAY))
	_view = VIEW.instantiate() as ShopView


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()
	_sim = null
	Clock.set_speed(_old_speed)


func _enter_view() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	tree.root.add_child(_view)
	_view.set_process(false)
	_view.show_world(_sim.world)
	_view.bind_dock(_sim.dock)
	_view.set_wall_mode(ShopView.WallMode.UP)


func _open_quiet() -> void:
	assert_true(_sim.world.clock.start_service())
	_sim.spawner.min_gap = 1000000
	_sim.spawner.max_gap = 1000000
	_sim.spawner.reset()


func _courier() -> CourierAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent is CourierAgent:
			return agent as CourierAgent
	return null


func _tick(count: int = 1) -> void:
	for index: int in count:
		_sim.advance()
	_view._process(0.0)


## Alpha of every surface drawn for a person (1 for their own materials).
func _alphas(node: Node3D) -> Array[float]:
	var out: Array[float] = []
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = found as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: BaseMaterial3D = mesh.get_active_material(surface) as BaseMaterial3D
			out.append(material.albedo_color.a if material != null \
				and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA else 1.0)
	return out


func _leaf_angle() -> float:
	return absf(_view.segment_view.door_leaf(DOOR).rotation.y)


func test_the_back_door_is_a_kenney_door_with_a_path_outside() -> void:
	await _enter_view()
	var leaf: Node3D = _view.segment_view.door_leaf(DOOR)
	assert_not_null(leaf, "the kit doorway's own door leaf")
	assert_eq(leaf.rotation.y, 0.0, "shut while nobody passes")
	var shut: Vector3 = leaf.global_transform * Vector3(0.4, 0.5, 0.0)
	_view.segment_view.set_door_open(DOOR, 1.0)
	assert_almost_eq(rad_to_deg(absf(leaf.rotation.y)), WallSegmentView.DOOR_OPEN_DEGREES, 0.01)
	var open: Vector3 = leaf.global_transform * Vector3(0.4, 0.5, 0.0)
	assert_true(open.x > shut.x + 0.2, "it swings out, onto the path (east, like a service door)")
	# Open, the leaf lies against its jamb: nothing of it in the 0.5 m opening.
	var leaf_bounds: AABB = leaf.global_transform * (leaf as MeshInstance3D).get_aabb()
	var center_z: float = GridMath.cell_to_world(DOOR).z
	var half: float = GridMath.CELL_SIZE * 0.5
	assert_true(leaf_bounds.position.z >= center_z + half - 0.001 or leaf_bounds.end.z <= center_z - half + 0.001,
		"clear of the opening: %s" % leaf_bounds)
	assert_true(leaf_bounds.position.x >= 7.0 - 0.01, "flat against the outside wall: %s" % leaf_bounds)
	assert_true(leaf_bounds.end.x <= 7.0 + 0.15)
	var tiles: Array[PropView] = _view.segment_view.path_tiles()
	for tile: PropView in tiles:
		# The alley hugs the wall here (no lot): the leaf stands against the wall
		# at the inner lane's edge; the delivery person walks the outer lane.
		var path_bounds: AABB = tile.global_transform * tile.get_combined_aabb()
		if leaf_bounds.position.z < path_bounds.end.z and leaf_bounds.end.z > path_bounds.position.z:
			assert_true(leaf_bounds.end.x <= path_bounds.position.x + 0.15, "only along the wall, not over the alley")
	_view.segment_view.set_door_open(DOOR, 0.0)
	assert_true((leaf.global_transform * Vector3(0.4, 0.5, 0.0)).is_equal_approx(shut), "shuts exactly where it was")
	_view.segment_view.set_door_open(DOOR, 1.0)
	_view.segment_view.set_door_open(DOOR, 0.0)
	# No lot given: the alley runs along the building's east edge, two lanes
	# wide (x 14 and 15), from the back down to the shop's front.
	assert_true(tiles.size() > 2 * WallRules.ALLEY_REACH, "the alley")
	var tints: Dictionary[Color, bool] = {}
	for tile: PropView in tiles:
		var bounds: AABB = tile.global_transform * tile.get_combined_aabb()
		assert_almost_eq(bounds.end.y, 0.001, 0.002, "level with the floor, so feet never sink")
		assert_true(bounds.size.y < 0.02, "flush: no side face to show")
		assert_true(bounds.size.x < GridMath.CELL_SIZE, "a joint between stones")
		var cell: Vector2i = tile.get_meta(&"cell")
		assert_true(cell.x == 14 or cell.x == 15, "on the alley: %s" % cell)
		assert_true(cell.y <= 11, "never past the shop's front into the street")
		tints[tile.active_body_material().albedo_color] = true
	assert_true(tints.size() > 3, "the stones vary")
	_view.set_wall_mode(ShopView.WallMode.DOWN)
	assert_null(_view.segment_view.door_leaf(DOOR), "lowered walls show posts, no floating leaf")
	assert_eq(_view.segment_view.path_tiles().size(), tiles.size(), "the path stays")


func test_the_door_swings_open_for_the_delivery_and_shuts_after() -> void:
	await _enter_view()
	_open_quiet()
	assert_true(_sim.dock.arrive([{"id": &"cheese", "qty": 4}, {"id": &"bread", "qty": 6}] as Array[Dictionary]))
	_tick()
	var courier: CourierAgent = _courier()
	assert_eq(_leaf_angle(), 0.0, "far up the path: shut")
	var start_node: Node3D = _view.agent_nodes[courier.id]
	assert_true(_alphas(start_node).all(func(alpha: float) -> bool: return alpha < 0.3),
		"faded in at the far end of her path, never popping in")
	var opened: bool = false
	var held: bool = false
	var bent: bool = false
	for tick: int in (WallRules.ALLEY_REACH + 8) * 4 + 12:
		_tick()
		var person: Node3D = _view.agent_nodes[courier.id]
		var crates: Node3D = person.get_node_or_null("Crates") as Node3D
		if courier.state == CourierAgent.State.ARRIVING:
			held = held or (crates != null and crates.visible and crates.get_child_count() == 1)
		if courier.cell == DOOR:
			opened = true
			assert_true(_alphas(person).all(func(alpha: float) -> bool: return alpha == 1.0), "solid near the shop")
			assert_almost_eq(rad_to_deg(_leaf_angle()), WallSegmentView.DOOR_OPEN_DEGREES, 0.01, "open as they pass")
		if courier.state == CourierAgent.State.UNLOADING:
			bent = true
			assert_eq(crates.visible, courier.carrying, "in her hands until the bottom of the bend")
			assert_eq((person as PersonView).current_clip(), &"pick-up")
			assert_true(person.position.is_equal_approx(GridMath.cell_to_world(DOOR)), "in the doorway")
		if courier.state == CourierAgent.State.LEAVING:
			break
	assert_true(opened)
	assert_true(bent)
	assert_true(held, "one crate in hand on the way in (a stack would hide her face)")
	assert_eq(_view.crate_nodes.size(), 1, "the one from her hands, while she stands over it")
	_tick()
	assert_eq(_view.crate_nodes.size(), 2, "both crates on the floor once she steps away")
	var spot: Vector3 = AgentPresentationController.crate_spot(_sim.world.grid, DROP)
	var layers: Array[float] = []
	for id: int in _view.crate_nodes:
		var node: Node3D = _view.crate_nodes[id]
		assert_almost_eq(node.position.x, spot.x, 0.001, "one stack")
		assert_almost_eq(node.position.x - GridMath.cell_to_world(DOOR).x, -AgentPresentationController.CRATE_REACH,
			0.001, "in front of her, at arm's reach")
		layers.append(node.position.y)
	layers.sort()
	assert_almost_eq(layers[0], 0.0, 0.001, "on the floor")
	assert_almost_eq(layers[1], _view.crate_height(), 0.001, "and on top of it")
	for tick: int in (WallRules.ALLEY_REACH + 8) * 4 + 40:
		_tick()
		if not _sim.world.agents.has(courier):
			break
	assert_false(_sim.world.agents.has(courier))
	_view._process(0.0)
	assert_eq(_leaf_angle(), 0.0, "shut behind them")


func test_a_carried_crate_shows_in_hand_and_guests_never_open_the_door() -> void:
	await _enter_view()
	_open_quiet()
	var guest: CustomerAgent = _sim.add_customer(DROP, RandomNumberGenerator.new())
	guest.state = CustomerAgent.State.QUEUED
	_view._process(0.0)
	assert_eq(_leaf_angle(), 0.0, "a guest beside the door never opens it")
	_sim.world.remove_agent(guest)
	assert_true(_sim.dock.arrive([{"id": &"cheese", "qty": 4}] as Array[Dictionary]))
	var carrier_id: int = -1
	var beside: bool = false
	for tick: int in 600:
		_tick()
		for agent: SimAgent in _sim.world.agents:
			var staff: StaffAgent = agent as StaffAgent
			if staff == null or staff.task == null or staff.task.kind != DeliveryDock.TASK_KIND \
					or staff.step_index != DeliveryDock.STEP_PICK_UP or staff.cell != DROP:
				continue
			beside = true
			var drawn: Vector3 = _view.agent_nodes[staff.id].position
			assert_true(drawn.is_equal_approx(AgentPresentationController.picker_spot(_sim.world.grid, DROP)),
				"beside the stack, not in it")
			var spot: Vector3 = AgentPresentationController.crate_spot(_sim.world.grid, DROP)
			assert_almost_eq(Vector2(drawn.x - spot.x, drawn.z - spot.z).length(), AgentPresentationController.CRATE_REACH,
				0.001)
			assert_eq((_view.agent_nodes[staff.id] as PersonView).current_clip(), &"pick-up")
		for crate: Dictionary in _sim.dock.crates():
			if int(crate["state"]) == DeliveryDock.CrateState.CARRIED:
				carrier_id = int(crate["carrier_id"])
		if carrier_id >= 0:
			break
	assert_true(beside)
	assert_true(carrier_id >= 0)
	_tick(DeliveryDock.LIFT_TICKS + 2)
	var person: PersonView = _view.agent_nodes[carrier_id] as PersonView
	var crates: Node3D = person.get_node("Crates") as Node3D
	assert_true(crates.visible)
	assert_eq(crates.get_child_count(), 1, "one crate each trip")
	assert_true(crates.get_child(0).visible)
	assert_eq(person.current_clip(), PersonPresentation.CARRY_WALK, "walking legs under carrying arms")
	assert_eq(_view.crate_nodes.size(), 0, "no longer on the floor")
	for tick: int in 600:
		_tick()
		if _sim.dock.is_idle():
			break
	assert_true(_sim.dock.is_idle())
	assert_false(crates.visible, "put away")


func test_the_freezer_reads_cooler_than_the_fridge_and_keeps_it_after_paint() -> void:
	var freezer: PropView = (load("res://assets/props/freezer.tscn") as PackedScene).instantiate() as PropView
	var kit: Color = freezer.active_body_material().albedo_color
	assert_true(kit.b > kit.r, "a cool metal: %s" % kit)
	freezer.set_body_tint(Color(0.9, 0.5, 0.3))
	assert_eq(freezer.active_body_material().albedo_color, Color(0.9, 0.5, 0.3), "paint replaces it")
	freezer.clear_body_tint()
	assert_eq(freezer.active_body_material().albedo_color, kit, "and clearing paint brings it back")
	freezer.free()
