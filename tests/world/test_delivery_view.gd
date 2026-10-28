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
	assert_true(open.x < shut.x - 0.2, "it swings into the shop (west, away from the east door)")
	_view.segment_view.set_door_open(DOOR, 0.0)
	var tiles: Array[PropView] = _view.segment_view.path_tiles()
	assert_eq(tiles.size(), 2, "pavement over the four approach cells")
	for tile: PropView in tiles:
		var bounds: AABB = tile.global_transform * tile.get_combined_aabb()
		assert_almost_eq(bounds.end.y, 0.001, 0.002, "level with the floor, so feet never sink")
		assert_true(bounds.position.x > 13.5 * GridMath.CELL_SIZE - 0.01, "all outside the shell")
		assert_true(absf(bounds.get_center().z - GridMath.cell_to_world(DOOR).z) < 0.01, "in line with the door")
	_view.set_wall_mode(ShopView.WallMode.DOWN)
	assert_null(_view.segment_view.door_leaf(DOOR), "lowered walls show posts, no floating leaf")
	assert_eq(_view.segment_view.path_tiles().size(), 2, "the path stays")


func test_the_door_swings_open_for_the_delivery_and_shuts_after() -> void:
	await _enter_view()
	_open_quiet()
	assert_true(_sim.dock.arrive([{"id": &"cheese", "qty": 4}, {"id": &"bread", "qty": 6}] as Array[Dictionary]))
	_tick()
	var courier: CourierAgent = _courier()
	assert_eq(_leaf_angle(), 0.0, "far up the path: shut")
	var opened: bool = false
	var held: bool = false
	for tick: int in 40:
		_tick()
		var person: Node3D = _view.agent_nodes[courier.id]
		var crates: Node3D = person.get_node_or_null("Crates") as Node3D
		if courier.state == CourierAgent.State.ARRIVING:
			held = held or (crates != null and crates.visible and crates.get_child(1).visible)
		if courier.cell == DOOR:
			opened = true
			assert_almost_eq(rad_to_deg(_leaf_angle()), WallSegmentView.DOOR_OPEN_DEGREES, 0.01, "open as they pass")
		if courier.state == CourierAgent.State.UNLOADING:
			assert_false(crates.visible, "set down")
			assert_eq((person as PersonView).current_clip(), &"pick-up")
	assert_true(opened)
	assert_true(held, "two crates in hand on the way in")
	assert_eq(_view.crate_nodes.size(), 2, "both crates on the floor")
	for id: int in _view.crate_nodes:
		var node: Node3D = _view.crate_nodes[id]
		assert_true(node.position.x < GridMath.cell_to_world(DROP).x, "on the far side from the door")
	for tick: int in 120:
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
	for tick: int in 600:
		_tick()
		for crate: Dictionary in _sim.dock.crates():
			if int(crate["state"]) == DeliveryDock.CrateState.CARRIED:
				carrier_id = int(crate["carrier_id"])
		if carrier_id >= 0:
			break
	assert_true(carrier_id >= 0)
	_tick(2)
	var person: PersonView = _view.agent_nodes[carrier_id] as PersonView
	var crates: Node3D = person.get_node("Crates") as Node3D
	assert_true(crates.visible)
	assert_true(crates.get_child(0).visible and not crates.get_child(1).visible, "one crate each trip")
	assert_eq(person.current_clip(), PersonPresentation.CARRY_WALK, "walking legs under carrying arms")
	assert_eq(_view.crate_nodes.size(), 0, "no longer on the floor")
	for tick: int in 600:
		_tick()
		if _sim.dock.is_idle():
			break
	assert_true(_sim.dock.is_idle())
	assert_false(crates.visible, "put away")
