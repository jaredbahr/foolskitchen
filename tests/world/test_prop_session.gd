extends TestCase
## Production picking/inspection routing. Model import and runtime remain gates.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "prop_session"
const PROVIDERS: Array[String] = ["owner", "shop", "menu", "staff", "plates", "reviews"]

var _main: Node3D
var _viewport: SubViewport
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)
	for key: String in PROVIDERS:
		if SaveSystem._providers.has(key):
			_old_providers[key] = SaveSystem._providers[key].duplicate()


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	for key: String in PROVIDERS:
		if _old_providers.has(key):
			var provider: Dictionary = _old_providers[key]
			SaveSystem.register(key, provider["capture"], provider["restore"])
		else:
			SaveSystem._providers.erase(key)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_native_model_hit_drives_outline_and_keeps_floor_and_agent_selection() -> void:
	await _start()
	var before: Dictionary = _snapshot()
	var fridge: PlacedItem = _item(&"fridge")
	_view().set_wall_mode(ShopView.WallMode.DOWN)
	var top: Vector3 = _top(fridge)
	var screen: Vector2 = _aim(top, top + Vector3(0.0, 2.0, -2.0))
	var floor_hit: Vector3 = _floor_at(screen)
	assert_false(fridge.cells.has(GridMath.world_to_cell(floor_hit)),
		"an oblique click on the model top projects outside its sim footprint")
	assert_eq(_ray_item(screen), fridge.id)
	_main.call("pick_screen_position", screen)
	assert_eq(_panel().selected_item_id, fridge.id)
	assert_true(_view().selection_outline.visible)
	assert_eq(_view().selection_outline.get_meta("item_id"), fridge.id)
	assert_eq(_view().selection_outline.transform, _view().item_nodes[fridge.id].transform)
	var empty_floor: Vector3 = GridMath.cell_to_world(Vector2i(11, 8))
	assert_null(_world().grid.item_at(GridMath.world_to_cell(empty_floor)))
	screen = _aim(empty_floor, empty_floor + Vector3(0.0, 4.0, -0.1))
	assert_eq(_ray_item(screen), -1, "an empty floor click retains the fallback route")
	_main.call("pick_screen_position", screen)
	assert_eq(_panel().selected_item_id, -1)
	assert_eq(_panel().selected_agent_id, -1)
	assert_false(_view().selection_outline.visible)
	_main.call("select_at_world_position", GridMath.cell_to_world(fridge.origin))
	assert_eq(_panel().selected_item_id, fridge.id, "one-argument callers keep cell picking")
	assert_true(_view().selection_outline.visible)
	var cook: StaffAgent = _world().agents[0] as StaffAgent
	var drawn: Dictionary[int, Vector3] = _view().drawn_agent_positions()
	assert_eq(Picker.pick_agent(drawn[cook.id], drawn), cook.id)
	_main.call("select_at_world_position", drawn[cook.id], fridge.id)
	assert_eq(_panel().selected_agent_id, cook.id, "drawn agents precede a preferred item")
	assert_false(_view().selection_outline.visible)
	assert_eq(_snapshot(), before, "selection changes no simulation state or morning save")


func test_selected_owner_uses_visible_station_before_projected_table_or_drawn_agent() -> void:
	await _start()
	var before: Dictionary = _snapshot()
	var fridge: PlacedItem = _item(&"fridge")
	var table: PlacedItem = _item(&"table_2")
	var owner: OwnerAgent = (_main.get("sim") as RestaurantSim).owner_agent()
	_view().set_wall_mode(ShopView.WallMode.DOWN)
	var top: Vector3 = _top(fridge)
	var table_floor: Vector3 = GridMath.cell_to_world(table.origin)
	var screen: Vector2 = _aim(top, top + (top - table_floor) * 2.0)
	var floor_hit: Vector3 = _floor_at(screen)
	assert_true(table.cells.has(GridMath.world_to_cell(floor_hit)))
	assert_eq(OwnerAssignment.resolve(floor_hit, _world().grid)["mode"], &"floor",
		"floor-only assignment would choose the unrelated dining table")
	assert_eq(_ray_item(screen), fridge.id)
	assert_true(_main.call("select_agent", owner.id))
	_main.call("pick_screen_position", screen)
	assert_eq(owner.current_mode(), &"kitchen", "the visible fridge is the work target")
	assert_eq(_panel().selected_agent_id, owner.id)
	assert_eq(_panel().selected_item_id, -1)
	var cook: StaffAgent = _world().agents[0] as StaffAgent
	var drawn: Dictionary[int, Vector3] = _view().drawn_agent_positions()
	assert_eq(Picker.pick_agent(drawn[cook.id], drawn), cook.id)
	_main.call("select_at_world_position", drawn[cook.id], table.id)
	assert_eq(owner.current_mode(), &"floor", "owner work commands precede drawn-agent selection")
	assert_eq(_panel().selected_agent_id, owner.id)
	assert_false(is_instance_valid(_view().selection_outline) and _view().selection_outline.visible)
	assert_eq(_snapshot(), before,
		"the requested owner mode changes no layout, clock, books, stock, RNG or save")


func test_native_wall_hit_never_falls_back_to_hidden_furniture_or_owner_assignment() -> void:
	await _start()
	var before: Dictionary = _snapshot()
	var fridge: PlacedItem = _item(&"fridge")
	var bounds: AABB = _view().item_bounds(fridge.id)
	var floor_point: Vector3 = bounds.get_center()
	floor_point.y = 0.0
	_view().set_wall_mode(ShopView.WallMode.UP)
	var screen: Vector2 = _aim(floor_point, Vector3(floor_point.x, 1.2, -1.0))
	assert_true(fridge.cells.has(GridMath.world_to_cell(_floor_at(screen))))
	assert_eq(_ray_item(screen), ShopView.OCCLUDED_ITEM)
	_main.call("select_at_world_position", GridMath.cell_to_world(fridge.origin))
	assert_eq(_panel().selected_item_id, fridge.id)
	_main.call("pick_screen_position", screen)
	assert_eq(_panel().selected_item_id, -1)
	assert_false(_view().selection_outline.visible, "a wall cannot select the floor's hidden item")
	var owner: OwnerAgent = (_main.get("sim") as RestaurantSim).owner_agent()
	assert_eq(owner.current_mode(), &"rest")
	assert_true(_main.call("select_agent", owner.id))
	_main.call("pick_screen_position", screen)
	assert_eq(owner.current_mode(), &"rest", "a wall blocks work assignment to the hidden fridge")
	assert_eq(_panel().selected_item_id, -1)
	var cook: StaffAgent = _world().agents[0] as StaffAgent
	var drawn: Dictionary[int, Vector3] = _view().drawn_agent_positions()
	_main.call("select_at_world_position", drawn[cook.id], ShopView.OCCLUDED_ITEM)
	assert_eq(_panel().selected_agent_id, cook.id, "the wall sentinel retains drawn-agent priority")
	assert_eq(_snapshot(), before)


func _start() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 97)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set_process(false)
	(_main.get_node("CameraRig") as CameraRig).set_process(false)
	_view().set_process(false)
	_view().call("_process", 0.0)
	await tree.process_frame
	assert_true(_camera().is_inside_tree())
	assert_true(FileAccess.file_exists(_path()))


func _aim(target: Vector3, origin: Vector3) -> Vector2:
	_camera().projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera().fov = 45.0
	_camera().global_position = origin
	_camera().look_at(target, Vector3.UP)
	return _camera().unproject_position(target)


func _ray_item(screen: Vector2) -> int:
	return _view().item_at_ray(_camera().project_ray_origin(screen), _camera().project_ray_normal(screen))


func _floor_at(screen: Vector2) -> Vector3:
	var hit: Variant = Picker.floor_intersection(_camera().project_ray_origin(screen),
		_camera().project_ray_normal(screen))
	assert_true(hit is Vector3)
	return hit if hit is Vector3 else Vector3.ZERO


func _top(item: PlacedItem) -> Vector3:
	var bounds: AABB = _view().item_bounds(item.id)
	var point: Vector3 = bounds.get_center()
	point.y = bounds.end.y
	return point


func _snapshot() -> Dictionary:
	return {"layout": (_main.get("shop_editor") as ShopEditor).to_dict(),
		"world_tick": _world().now, "clock": Clock.sim.to_dict(),
		"ledger": Economy.ledger.to_dict(), "stock": Economy.stock.to_dict(),
		"rng": GameState.call("_capture_save"),
		"save": FileAccess.get_file_as_string(_path())}


func _item(id: StringName) -> PlacedItem:
	return ShopBuilder.items_with_def(_world(), id)[0]


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _view() -> ShopView:
	return _main.get_node("ShopView") as ShopView


func _panel() -> InspectPanel:
	return _main.get_node("Overlay/InspectPanel") as InspectPanel


func _camera() -> Camera3D:
	return _main.get_node("CameraRig/Camera3D") as Camera3D


func _path() -> String:
	return _save_dir.path_join(SLOT + ".json")
