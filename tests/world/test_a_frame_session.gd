extends TestCase
## Real Main: the street A-frame sign is bought through the ordinary hang
## request, shows the live name and special, never touches the grid, and a real
## service still brings guests in and out of the door.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const GROUND: int = ExteriorSupport.Band.GROUND

var _main: Node3D
var _viewport: SubViewport
var _arrived: Array[int] = []
var _departed: Array[int] = []
var _old_save_dir: String
var _save_dir: String
const SLOT: String = "a_frame_session"


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "a_frame_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)
	_arrived.clear()
	_departed.clear()


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_buying_follows_the_level_the_cash_and_the_pavement_rules() -> void:
	await _start()
	_editor().set_owner_level(1)
	var beside: Vector3i = _front(-1)
	assert_false(_main.call("shop_hang", &"a_frame_sign", beside))
	assert_eq(_editor().last_check.why, "Unlocks at level 2")
	_editor().set_owner_level(2)
	var cash: int = Economy.cash
	assert_false(_main.call("shop_hang", &"a_frame_sign", _front(0)), "straight in front of the door")
	assert_eq(_editor().last_check.why, ExteriorSupport.DOORWAY_CLEAR)
	assert_false(_main.call("shop_hang", &"a_frame_sign", _front(-3)), "far from the door")
	assert_eq(Economy.cash, cash)
	assert_true(_main.call("shop_hang", &"a_frame_sign", beside))
	assert_eq(Economy.cash, cash - 35)
	assert_false(_main.call("shop_hang", &"a_frame_sign", _front(2)), "only one per shop")
	assert_eq(_editor().last_check.why, WallDecor.UNIQUE)
	assert_eq(Economy.cash, cash - 35)


func test_it_stands_on_the_pavement_beside_the_door_and_shows_name_and_special() -> void:
	await _start()
	var beside: Vector3i = _front(2)
	assert_true(_main.call("shop_hang", &"a_frame_sign", beside))
	var visual: ItemVisual = _view().wall_finish_view.item_nodes[beside]
	assert_true(visual.is_visible_in_tree())
	var box: AABB = visual.global_transform * visual.get_aabb()
	assert_almost_eq(box.position.y, 0.0, 0.01, "it stands on the ground")
	var cell_centre: Vector3 = GridMath.cell_to_world(Vector2i(beside.x, beside.y))
	assert_true(absf(box.get_center().x - cell_centre.x) <= 0.05 and absf(box.get_center().z - cell_centre.z) <= 0.05,
		"centred in the pavement cell beside the entrance")
	assert_true(box.size.x <= GridMath.CELL_SIZE + 0.05 and box.size.z <= GridMath.CELL_SIZE + 0.05, "inside its cell")
	for entry: Vector2i in _world().grid.entries():
		assert_false(box.intersects(AABB(GridMath.cell_to_world(entry) - Vector3(0.25, 0.0, 0.25), Vector3(0.5, 1.0, 0.5))),
			"it never overlaps an entry cell")
	assert_eq(_sign_text(beside), "%s\nToday: Burger" % MenuSettings.DEFAULT_NAME)


func test_text_follows_a_rename_a_price_change_and_a_menu_change() -> void:
	await _start()
	var beside: Vector3i = _front(-1)
	assert_true(_main.call("shop_hang", &"a_frame_sign", beside))
	var settings: MenuSettings = _main.get("menu_settings") as MenuSettings
	# Starter menu margins (price minus ingredients): burger 8, tomato soup 6,
	# grilled cheese 5.
	var starter: Array[StringName] = []
	for recipe: RecipeDef in settings.enabled_recipes():
		starter.append(recipe.id)
	assert_eq(starter.size(), 3)
	for id: StringName in [&"burger", &"grilled_cheese", &"tomato_soup"]:
		assert_true(starter.has(id), String(id))
	assert_eq(_sign_text(beside), "%s\nToday: Burger" % MenuSettings.DEFAULT_NAME)
	assert_true(_main.call("menu_set_restaurant_name", "  Copper & Thyme  "))
	assert_eq(_sign_text(beside), "Copper & Thyme\nToday: Burger")
	# Burger at its lowest price earns 6 - 4 = 2, so tomato soup (6) takes over.
	assert_true(_main.call("menu_set_price", &"burger", settings.minimum_price(&"burger")))
	assert_eq(settings.price_of(settings.recipe(&"burger")), 6)
	assert_eq(_sign_text(beside), "Copper & Thyme\nToday: Tomato soup")
	# Soup off the menu: grilled cheese (5) beats the cheap burger (2).
	assert_true(_main.call("menu_set_enabled", &"tomato_soup", false))
	assert_eq(_sign_text(beside), "Copper & Thyme\nToday: Grilled cheese")
	# Raising the burger's price brings it back as the special.
	assert_true(_main.call("menu_set_price", &"burger", settings.maximum_price(&"burger")))
	assert_eq(_sign_text(beside), "Copper & Thyme\nToday: Burger")


func test_undo_and_redo_of_placing_the_sign() -> void:
	await _start()
	var beside: Vector3i = _front(-1)
	var cash: int = Economy.cash
	assert_true(_main.call("shop_hang", &"a_frame_sign", beside))
	assert_eq(Economy.cash, cash - 35)
	assert_true(_view().wall_finish_view.item_nodes.has(beside))
	var history: ShopEditHistory = _main.get("edit_history") as ShopEditHistory
	assert_true(history.undo())
	assert_null(_editor().decor.item(beside))
	assert_eq(Economy.cash, cash)
	assert_false(_view().wall_finish_view.item_nodes.has(beside))
	assert_true(history.redo())
	assert_eq(Economy.cash, cash - 35)
	assert_eq(_editor().decor.item(beside).def_id, &"a_frame_sign")
	assert_eq(_sign_text(beside), "%s\nToday: Burger" % MenuSettings.DEFAULT_NAME)


func test_save_and_load_restore_the_sign_on_its_ground_key_and_its_text() -> void:
	await _start(true)
	var beside: Vector3i = _front(2)
	assert_true(beside.z >= 20 and beside.z <= 23, "a ground-band key")
	assert_true(_main.call("shop_hang", &"a_frame_sign", beside))
	assert_true(_main.call("menu_set_restaurant_name", "Copper & Thyme"))
	assert_true(_main.call("menu_set_price", &"burger", 6))
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.phase = SimClock.Phase.CLOSED
	assert_true(Clock.sim.next_day())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")))
	var rows: Array = saved["data"]["shop"]["wall_items"]
	assert_eq(rows, [[float(beside.x), float(beside.y), float(beside.z), "a_frame_sign", 2.0, ""]])
	_close()
	await _start(true)
	assert_eq(_editor().decor.item(beside).def_id, &"a_frame_sign")
	assert_eq(_editor().decor.item(beside).mount, ItemDef.WallMount.EXTERIOR)
	assert_eq(_sign_text(beside), "Copper & Thyme\nToday: Tomato soup")


func test_the_sign_changes_neither_the_grid_nor_the_guests_way_through_the_door() -> void:
	await _start()
	var grid: SimGrid = _world().grid
	var walkable: Array[Vector2i] = []
	for cell: Vector2i in grid.cells():
		if grid.is_walkable(cell):
			walkable.append(cell)
	var route: Array[Vector2i] = grid.find_guest_path(grid.entries()[0], Vector2i(9, 9))
	assert_true(_main.call("shop_hang", &"a_frame_sign", _front(-1)))
	var after: Array[Vector2i] = []
	for cell: Vector2i in grid.cells():
		if grid.is_walkable(cell):
			after.append(cell)
	assert_eq(after, walkable)
	assert_eq(grid.find_guest_path(grid.entries()[0], Vector2i(9, 9)), route)


func test_a_real_service_still_brings_guests_in_and_out_of_the_door() -> void:
	await _start()
	assert_true(_main.call("shop_hang", &"a_frame_sign", _front(-1)))
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	sim.customer_arrived.connect(_on_arrived)
	sim.customer_left.connect(_on_left)
	sim.spawner.min_gap = 40
	sim.spawner.max_gap = 70
	sim.spawner.reset()
	assert_true(Clock.sim.start_service())
	var inside: bool = false
	var guests: Dictionary[int, bool] = {}
	for tick: int in 2600:
		var before: Dictionary = MovementInvariants.capture(sim.world)
		sim.advance()
		var problem: String = MovementInvariants.problem(sim.world, before)
		if not problem.is_empty():
			assert_eq(problem, "", "tick %d" % tick)
			break
		for customer: CustomerAgent in sim.customers():
			guests[customer.id] = true
			if sim.world.grid.terrain(customer.cell) == SimGrid.Terrain.FLOOR:
				inside = true
		if _departed.size() >= 3 and inside:
			break
	assert_true(_arrived.size() >= 3, "guests keep arriving at the door")
	assert_true(inside, "guests walk through the doorway onto the floor")
	assert_true(_departed.size() >= 1, "guests leave through the door again")
	assert_eq(_world().grid.entries().size(), 2)


func _on_arrived(customer: CustomerAgent) -> void:
	_arrived.append(customer.id)


func _on_left(customer: CustomerAgent, _reason: StringName) -> void:
	_departed.append(customer.id)


func _sign_text(anchor: Vector3i) -> String:
	var visual: ItemVisual = _view().wall_finish_view.item_nodes[anchor]
	var mount: Node = visual.prop.get_node(^"BoardMount/Art/Board/WallMount")
	var title: Label3D = mount.get_node(^"MenuText") as Label3D
	var special: Label3D = mount.get_node(^"SpecialText") as Label3D
	return title.text if not special.visible else title.text + "\n" + special.text


func _front(offset: int) -> Vector3i:
	var grid: SimGrid = _world().grid
	var doors: Array[Vector2i] = ExteriorSupport.door_cells(grid)
	var into: Vector2i = -WallRules.street_side(grid)
	var direction: int = WallFaces.DIRS.find(into)
	var along: Vector2i = WallFaces.DIRS[posmod(direction + 1, 4)]
	var first: Vector2i = doors[0]
	for cell: Vector2i in doors:
		if cell.x * along.x + cell.y * along.y < first.x * along.x + first.y * along.y:
			first = cell
	return ExteriorSupport.key_for(WallFaces.make(first + along * offset - into, direction), GROUND)


func _start(with_saves: bool = false) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", with_saves)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 240)
	_viewport.add_child(_main)
	_main.call("start")
	# Exact books for this feature: no opening-week rewards (#494).
	retire_opening_week(_main)
	_editor().set_owner_level(6)
	Economy.add_cash(2000, Ledger.OTHER)
	_main.set_process(false)
	_view().set_process(false)
	Clock.set_speed(0)
	for frame: int in 4:
		await tree.process_frame


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	_viewport = null


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _view() -> ShopView:
	return _main.get_node("ShopView") as ShopView
