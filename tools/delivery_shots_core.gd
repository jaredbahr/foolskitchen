extends RefCounted
## Driver for tools/delivery_shots.gd (manual captures only).

const NORTH_DOOR: Vector2i = Vector2i(9, 0)
const EAST_DOOR: Vector2i = Vector2i(13, 6)
## Close-up zoom: the starter shop is framed at 12, so this is 3x.
const CLOSE_ZOOM: float = 4.0

var tree: SceneTree
var out: String
var main: Node
var sim: RestaurantSim
var camera: CameraRig
var door: Vector2i


func _frames(n: int) -> void:
	for i: int in range(n):
		await tree.process_frame


func _save(name: String) -> void:
	await tree.process_frame
	await tree.process_frame
	var image: Image = tree.root.get_viewport().get_texture().get_image()
	image.save_png(out.path_join(name))
	print("saved ", name, " tick ", Clock.sim.phase_tick)


func _courier() -> CourierAgent:
	for agent: SimAgent in sim.world.agents:
		if agent is CourierAgent:
			return agent as CourierAgent
	return null


func _carried() -> int:
	for crate: Dictionary in sim.dock.crates():
		if int(crate["state"]) == DeliveryDock.CrateState.CARRIED:
			return int(crate["carrier_id"])
	return -1


func _focus(cell: Vector2i, zoom: float) -> void:
	var at: Vector3 = GridMath.cell_to_world(cell)
	camera.frame_area(Vector2(at.x, at.z), Vector2(20, 20), zoom, true)


## Ticks one at a time (paused clock) until `condition` holds; false on timeout.
func _tick_until(condition: Callable, limit: int) -> bool:
	for i: int in limit:
		if condition.call():
			return true
		main.call("run_ticks", 1)
		await tree.process_frame
	return condition.call()


func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var east: bool = args.has("east")
	var cutaway: bool = args.has("cutaway")
	door = EAST_DOOR if east else NORTH_DOOR
	main = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", 1)
	tree.root.add_child(main)
	main.call("start")
	await _frames(5)
	sim = main.get("sim") as RestaurantSim
	camera = main.get_node("CameraRig") as CameraRig
	# Review close-ups go nearer than players can (3x the shop framing).
	camera.minimum_zoom = 2.0
	var view: ShopView = main.get_node("ShopView") as ShopView
	var inside: Vector2i = door + (Vector2i.LEFT if east else Vector2i.DOWN)
	var changes: Dictionary[Vector3i, int] = {SimGrid.edge_between(inside, door): SimGrid.Segment.DOORWAY}
	if not bool(main.call("shop_walls", changes)):
		push_error("could not build the back door")
		return
	view.set_wall_mode(ShopView.WallMode.CUTAWAY if cutaway else ShopView.WallMode.UP)
	var prefix: String = "%s_%s_" % ["east" if east else "north", "cutaway" if cutaway else "up"]
	Clock.set_speed(0)
	Clock.sim.start_service()
	main.call("run_ticks", 200)
	main.call("stock_cart_set", &"cheese", 6)
	main.call("stock_cart_set", &"bread", 6)
	if not bool(main.call("stock_place_order")):
		push_error("order refused: %s" % main.call("stock_cart_refusal"))
		return
	main.call("run_ticks", 1078 - Clock.sim.phase_tick)
	await _frames(10)
	await _save(prefix + "00_before.png")
	if not await _tick_until(func() -> bool: return _courier() != null, 20):
		push_error("no delivery person")
		return
	var courier: CourierAgent = _courier()
	var out_dir: Vector2i = courier.route[courier.route.size() - 3] - door if courier.route.size() >= 3 else Vector2i.ZERO
	await _tick_until(func() -> bool: return courier.cell == door + out_dir * 3, 200)
	_focus(door, 8.0)
	await _frames(20)
	await _save(prefix + "01_approach_wide.png")
	_focus(door, CLOSE_ZOOM)
	await _frames(20)
	await _save(prefix + "02_approach_close.png")
	# Door swing, one sim tick per image, from three cells out until unloading.
	var index: int = 0
	while courier.state == CourierAgent.State.ARRIVING and index < 80:
		await _save(prefix + "seq_door_%02d.png" % index)
		main.call("run_ticks", 1)
		index += 1
	await _frames(3)
	await _save(prefix + "03_unloading_close.png")
	_focus(door, 8.0)
	await _frames(20)
	await _save(prefix + "04_unloading_wide.png")
	_focus(door, CLOSE_ZOOM)
	await _frames(20)
	await _tick_until(func() -> bool: return courier.state == CourierAgent.State.LEAVING, 40)
	# Leaving: the door opens again and swings shut behind them.
	index = 0
	while sim.world.agents.has(courier) and index < 40:
		await _save(prefix + "seq_leave_%02d.png" % index)
		main.call("run_ticks", 1)
		index += 1
	await _save(prefix + "05_door_shut_close.png")
	await _tick_until(func() -> bool: return _carried() >= 0, 600)
	main.call("run_ticks", 3)
	var carrier: SimAgent = sim.world.agent(_carried())
	if carrier == null:
		push_error("nobody carried a crate")
		return
	_focus(carrier.cell, 8.0)
	await _frames(20)
	await _save(prefix + "06_carrying_wide.png")
	# Close-ups from the opposite side with every wall down, so the crate held
	# in front shows while they walk away from the default camera.
	var mode: int = view.wall_mode
	view.set_wall_mode(ShopView.WallMode.DOWN)
	camera.initial_yaw_degrees += 180.0
	_focus(carrier.cell, CLOSE_ZOOM)
	await _frames(20)
	await _save(prefix + "07_carrying_close.png")
	# A carried crate at 1x, every captured frame, the camera on the carrier.
	Clock.set_speed(1)
	for step: int in 30:
		_focus(carrier.cell, CLOSE_ZOOM)
		await _save(prefix + "seq_carry_%02d.png" % step)
	Clock.set_speed(0)
	camera.initial_yaw_degrees -= 180.0
	view.set_wall_mode(mode as ShopView.WallMode)
	await _tick_until(func() -> bool: return sim.dock.is_idle(), 2000)
	_focus(door, 8.0)
	await _frames(20)
	await _save(prefix + "08_after.png")
	print("stock cheese ", Economy.stock.count(&"cheese"), " bread ", Economy.stock.count(&"bread"))
