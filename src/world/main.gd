extends Node3D
## Temporary staff-only demonstration; RestaurantSim integration replaces this.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
var world: SimWorld
var _demo_ticks: int = 0
## Clock state before this scene attached its world, restored on exit.
var _previous_clock: SimClock = null


func _ready() -> void:
	initialize()
	if world == null:
		return
	_previous_clock = Clock.sim
	Clock.attach_world(world)
	EventBus.sim_ticked.connect(_on_sim_ticked)
	world.clock.start_service()
	Clock.set_speed(1)


## Builds the read-only view even before tree readiness, without changing Clock.
func initialize() -> void:
	if world != null:
		return
	var content: ContentDB = ContentDB.new()
	var errors: PackedStringArray = content.load_all()
	if not errors.is_empty():
		push_error("Cannot load shop content: %s" % errors)
		return
	var build_errors: Array[String] = []
	world = ShopBuilder.build(LAYOUT, content, build_errors)
	if not build_errors.is_empty():
		push_error("Cannot build shop: %s" % build_errors)
		world = null
		return
	for role: StringName in [&"cook", &"server"]:
		var staff: StaffAgent = StaffAgent.new(role)
		staff.cell = LAYOUT.staff_spawns[role]
		world.add_agent(staff)
	var view: ShopView = $ShopView
	view.show_world(world)
	var camera: CameraRig = $CameraRig
	camera.grid_floor = view.floor_mesh
	var shop_half: Vector2 = Vector2(world.grid.size) * GridMath.CELL_SIZE * 0.5
	camera.initial_focus = shop_half
	# Pan around the shop itself, with a 2 m margin on every side.
	camera.pan_center = shop_half
	camera.pan_limits = shop_half + Vector2(2.0, 2.0)
	camera.initial_zoom = 12.0
	camera.reset_view()
	if not camera.yaw_snapped.is_connected(view.set_camera_quarter):
		camera.yaw_snapped.connect(view.set_camera_quarter)
	view.set_camera_quarter(camera.camera_quarter())
	$HUD.bind_shop_view(view)
	_post_demo_tasks()


func _exit_tree() -> void:
	if EventBus.sim_ticked.is_connected(_on_sim_ticked):
		EventBus.sim_ticked.disconnect(_on_sim_ticked)
	if world != null and Clock.attached_world == world:
		Clock.attach_world(null)
		if _previous_clock != null:
			Clock.sim = _previous_clock


func _on_sim_ticked(_tick: int) -> void:
	_demo_ticks += 1
	if _demo_ticks >= 30:
		_demo_ticks = 0
		_post_demo_tasks()


func _post_demo_tasks() -> void:
	# Temporary demo only: integration will own task posting. Never pile up jobs.
	if not world.board.open_tasks().is_empty() or not world.board.claimed_tasks().is_empty():
		return
	for role: StringName in [&"cook", &"server"]:
		var task: SimTask = SimTask.new(&"demo", role, "Temporary demo route")
		for id: StringName in [&"fridge", &"stove", &"pass_counter"]:
			var items: Array[PlacedItem] = ShopBuilder.items_with_def(world, id)
			if not items.is_empty():
				task.steps.append(TaskStep.go_to_item(items[0].id, "Walk to %s" % id))
				task.steps.append(TaskStep.work(10, "Demonstrating station"))
		world.board.post(task, world.now)
