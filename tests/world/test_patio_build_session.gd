extends TestCase
## The real catalogue, projected drag input and morning session own patio edits.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "patio_build_session"

var _main: Node3D
var _viewport: SubViewport
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate(true)
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


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
	SaveSystem._providers = _old_providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_catalogue_drag_refund_undo_refusal_and_cancel_never_save() -> void:
	await _start()
	var checkpoint: String = _checkpoint()
	assert_false(checkpoint.is_empty(), "the ordinary morning checkpoint exists")
	var rng_before: Dictionary = GameState.call("_capture_save")
	var cash: int = Economy.cash
	assert_true(_main.call("set_build_active", true))
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.PATIO)
	assert_true(catalogue.patio_button.visible)
	assert_eq(catalogue.patio_button.text, "Build patio\n$15 a tile")
	catalogue.patio_button.pressed.emit()
	assert_eq(_mode().state, BuildMode.State.PATIO)
	var preview: BuildPreview = _main.get("_build_preview") as BuildPreview
	assert_not_null(preview.patio_lot)
	assert_false(_mode().patio_open_cells().has(_street(0, 1)), "the street door approach is public")
	# The authored entry at (6, 11) reaches this 2×2 patch through (5, 11).
	# Four tiles preserve the purchase/refund arithmetic without a path fixture.
	_press(_street(-2, 0))
	_pointer(_street(-1, 1))
	assert_eq(_mode().patio_summary(), "Add 4 patio tiles  $60")
	assert_true(_mode().current_check.ok)
	assert_eq(preview.floor_ghost_cells.size(), 4)
	_release(_street(-1, 1))
	assert_eq(_editor().bought_patio().size(), 4)
	if _editor().bought_patio().size() != 4:
		return  # Keep the setup assertion; avoid misleading follow-on refusals.
	assert_eq(Economy.cash, cash - 60)
	assert_eq(_forecast(), WeatherText.forecast_for(_world().weather.kind, true))
	_press(_street(-1, 1), true)
	assert_eq(_mode().patio_summary(), "Remove 1 patio tile  (refund $7)")
	_release(_street(-1, 1))
	assert_eq(_editor().bought_patio().size(), 3)
	assert_eq(Economy.cash, cash - 53)
	_key(KEY_Z, true)
	assert_eq(_editor().bought_patio().size(), 4)
	assert_eq(Economy.cash, cash - 60, "undo restores exact cash, including odd cell prices")
	_key(KEY_Z, true)
	assert_eq(_editor().bought_patio().size(), 0)
	assert_eq(Economy.cash, cash)
	assert_eq(_forecast(), WeatherText.forecast_for(_world().weather.kind), "selling the last patio clears its status")
	assert_true(_main.call("begin_patio_tool"))
	_press(_street(0, 0))
	assert_false(_mode().current_check.ok)
	assert_false(_mode().current_check.why.is_empty(), "the refusal is readable")
	assert_eq(preview.floor_ghost.get_meta("valid"), false)
	_release(_street(0, 0))
	assert_eq(Economy.cash, cash)
	assert_true(_editor().bought_patio().is_empty())
	_press(_street(-1, 0))
	_key(KEY_ESCAPE)
	assert_eq(_mode().state, BuildMode.State.PATIO, "first Esc cancels the drag")
	assert_false(_mode().patio_dragging)
	_key(KEY_ESCAPE)
	assert_eq(_mode().state, BuildMode.State.IDLE, "second Esc closes the tool")
	assert_eq(_checkpoint(), checkpoint, "purchase, sale, undo and refusal add no save point")
	assert_eq(GameState.call("_capture_save"), rng_before, "previews and forecast refresh never draw RNG")


func test_morning_status_refreshes_for_rain_sun_and_last_cell_undo() -> void:
	await _start()
	_world().weather.kind = WeatherState.Kind.RAIN
	_main.call("_refresh_weather")
	assert_eq(_forecast(), "Rain today", "an older shop keeps its exact plain forecast")
	assert_true(_main.call("set_build_active", true))
	# This one tile borders the real public entry, rather than an isolated lot cell.
	var purchased: bool = _main.call("shop_patio", [_street(-1, 0)] as Array[Vector2i], true)
	assert_true(purchased, "the entry-adjacent patio cell must be buyable")
	if not purchased:
		return
	assert_eq(_forecast(), "Rain today  |  Patio closed in rain")
	_world().weather.kind = WeatherState.Kind.CLOUDY
	_main.call("_refresh_weather")
	assert_eq(_forecast(), "Cloudy today  |  Patio open today")
	assert_true(_main.call("undo_edit"))
	assert_eq(_forecast(), "Cloudy today")
	assert_true(_main.call("redo_edit"))
	assert_eq(_forecast(), "Cloudy today  |  Patio open today")
	assert_eq(WeatherText.forecast_for(WeatherState.Kind.SUNNY, true), "Sunny today  |  Patio open today")
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
	catalogue.set_category(BuildCatalogue.ROOMS)
	assert_eq(catalogue.room_buttons.size(), SimGrid.Room.STORAGE + 1, "patio must be bought, never free room paint")
	assert_false(_mode().begin_rooms(SimGrid.Room.PATIO))


func test_owned_pavement_keeps_street_anchor_facade_and_outdoor_rain_mask() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var street_before: Dictionary = view.neighbourhood_dressing.capture_state()
	var windows_before: Array[Vector2i] = ExteriorSupport.window_cells(_world().grid)
	var door_before: Array[Vector2i] = _world().grid.entries()
	var floor_before: int = view.floor_mesh.mesh.get_surface_count()
	var vertices_before: int = view.floor_mesh.mesh.surface_get_array_len(0)
	# Connect the rendered test cell (2, 12) to the real entry (6, 11):
	# four cells along row 11, then one step down. This costs $75 from the
	# unchanged starter cash and does not require a disconnected floor island.
	var cells: Array[Vector2i] = [_street(-4, 0), _street(-3, 0), _street(-2, 0),
		_street(-1, 0), _street(-4, 1)]
	var purchased: bool = _main.call("shop_patio", cells, true)
	assert_true(purchased, "the connected pavement chain must be buyable from starter cash")
	if not purchased:
		return
	var street_after: Dictionary = view.neighbourhood_dressing.capture_state()
	assert_eq(street_after["frame"], street_before["frame"], "patio never pushes the road or pedestrian lanes forward")
	assert_eq(street_after["bounds"], street_before["bounds"], "the original pavement and road remain in place")
	assert_eq(ExteriorSupport.window_cells(_world().grid), windows_before)
	assert_eq(_world().grid.entries(), door_before, "buying pavement creates no new entry")
	assert_eq(view.floor_mesh.mesh.get_surface_count(), floor_before)
	assert_eq(view.floor_mesh.mesh.surface_get_array_len(0), vertices_before, "unpainted patio adds no wooden indoor tiles")
	assert_null(view.patio_floor_mesh)
	assert_eq(view.room_dressing.name_sign_nodes().size(), 1, "the existing sign keeps its facade support")
	_world().weather.kind = WeatherState.Kind.RAIN
	_main.call("_refresh_weather")
	var drop: AABB = AABB(Vector3(1.1, 0.2, 6.1), Vector3(0.01, 1.0, 0.01))
	assert_true(view.weather_view.call("_outside_bounds", drop), "patio remains outside the built-roof rain mask")
	var indoors: AABB = AABB(Vector3(1.1, 0.2, 3.1), Vector3(0.01, 1.0, 0.01))
	assert_false(view.weather_view.call("_outside_bounds", indoors))
	var changes: Dictionary[Vector2i, FloorFinishes.Finish] = _editor().lay_changes(
		[_street(-4, 1)] as Array[Vector2i], &"herringbone", &"honey")
	assert_true(_main.call("shop_flooring", changes))
	assert_not_null(view.patio_floor_mesh, "explicitly painted patio reuses the existing floor shader")
	if view.patio_floor_mesh == null:
		return  # The failed setup assertion is sufficient; do not raise a Nil error.
	assert_eq(view.patio_floor_mesh.material_override, view.floor_mesh.material_override)
	assert_true((view.patio_floor_mesh.layers & WeatherView.OUTDOOR_LAYER) != 0)


func test_native_furniture_walking_feet_and_seated_pose_follow_the_pavement_once() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var indoor_table: PlacedItem = _world().grid.item_at(ShopBuilder.items_with_def(_world(), &"table_2")[0].origin)
	var indoor_visual: ItemVisual = view.item_nodes[indoor_table.id]
	var indoor_transform: Transform3D = indoor_visual.global_transform
	var indoor_base: float = _native_minimum_y(indoor_visual)
	if not _buy_left_patio():
		return
	assert_true(_main.call("shop_buy", &"patio_table_2", _street(-4, 1), 0))
	assert_true(_main.call("shop_buy", &"patio_waiting_bench", _street(-6, 0), 0))
	var table: PlacedItem = _world().grid.item_at(_street(-4, 1))
	var bench: PlacedItem = _world().grid.item_at(_street(-6, 0))
	assert_not_null(table)
	assert_not_null(bench)
	if table == null or bench == null:
		return
	var pavement: float = _measured_pavement(view)
	assert_true(pavement > 0.0, "the native paving has a raised top surface")
	assert_almost_eq(view.ground_height(_street(-1, 0)), pavement)
	assert_almost_eq(view.ground_height(_street(0, 0)), 0.0, 0.00001, "the public entry keeps its authored height")
	assert_almost_eq(view.ground_height(ShopBuilder.items_with_def(_world(), &"table_2")[0].origin), 0.0)
	assert_eq(indoor_visual.global_transform, indoor_transform, "purchasing pavement leaves indoor furniture in place")
	assert_almost_eq(_native_minimum_y(view.item_nodes[table.id]) - indoor_base, pavement, 0.00001,
		"the identical imported table wrapper rises exactly to the measured pavement")
	var staff: StaffAgent = null
	for agent: SimAgent in _world().agents:
		if agent is StaffAgent:
			staff = agent as StaffAgent
			break
	assert_not_null(staff)
	if staff == null:
		return
	var indoor_cell: Vector2i = staff.cell
	view._process(0.0)
	var person: PersonView = view.agent_nodes.get(staff.id) as PersonView
	assert_not_null(person)
	if person == null:
		return
	assert_almost_eq(person.position.y, 0.0, 0.00001, "indoor actor feet keep the old floor plane")
	staff.cell = _street(-1, 0)
	staff.path.clear()
	staff.move_progress = 0.0
	view._process(0.0)
	assert_almost_eq(person.position.y, pavement, 0.00001, "standing feet sit on the pavement surface")
	# Use a real legal step across the street entry boundary without advancing
	# the simulation: the rendered foot plane must cross the height difference.
	staff.cell = _street(0, 0)
	assert_true(staff.set_destination(_world().grid, _street(-1, 0)))
	assert_eq(staff.next_cell(), _street(-1, 0))
	staff.move_progress = 0.25
	view._process(0.0)
	assert_almost_eq(person.position.y, pavement * 0.25, 0.00001)
	staff.cell = _street(-1, 0)
	assert_true(staff.set_destination(_world().grid, _street(0, 0)))
	staff.move_progress = 0.75
	view._process(0.0)
	assert_almost_eq(person.position.y, pavement * 0.25, 0.00001, "returning indoors lowers the feet along the same step")
	staff.cell = indoor_cell
	staff.path.clear()
	staff.move_progress = 0.0
	_world().weather.kind = WeatherState.Kind.SUNNY
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var private_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	private_rng.seed = 243
	var guest: CustomerAgent = _world().add_agent(CustomerAgent.new(sim, private_rng)) as CustomerAgent
	guest.state = CustomerAgent.State.QUEUED
	guest.cell = bench.seat_cells[0]
	guest.waiting_cell = guest.cell
	guest.waiting_item_id = bench.id
	assert_true(bench.reserve(guest.cell, guest.id))
	assert_true(guest.is_waiting_seated(_world()), "the pose uses a real owned and reserved outdoor bench seat")
	view._process(0.0)
	var seated: PersonView = view.agent_nodes.get(guest.id) as PersonView
	assert_not_null(seated)
	if seated == null:
		return
	var bench_visual: ItemVisual = view.item_nodes[bench.id]
	assert_not_null(bench_visual.prop)
	if bench_visual.prop == null:
		return
	var relative_seat: float = bench_visual.prop.seat_surface_height()
	assert_true(relative_seat > 0.0, "the shipped bench supplies a measured seat surface")
	var pivot: Node3D = seated.get_node("ModelPivot") as Node3D
	assert_eq(seated.current_clip(), &"sit")
	assert_almost_eq(seated.position.y, pavement, 0.00001)
	assert_almost_eq(pivot.position.y, relative_seat, 0.00001, "the seated pose keeps its relative lift")
	assert_almost_eq(pivot.global_position.y, pavement + relative_seat, 0.00001,
		"the seat surface receives the pavement height exactly once")
	assert_eq(indoor_visual.global_transform, indoor_transform)
	assert_almost_eq(person.position.y, 0.0, 0.00001)
	assert_eq(_world().now, 0, "all height synchronization is presentation only")


func test_native_mess_and_build_overlays_clear_pavement_without_lifting_indoor_tiles() -> void:
	await _start()
	if not _buy_left_patio():
		return
	assert_true(_main.call("shop_buy", &"patio_waiting_bench", _street(-6, 0), 0))
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var pavement: float = _measured_pavement(view)
	var tuning: CleanlinessTuning = (load("res://data/balance/cleanliness.tres") as CleanlinessTuning).duplicate() as CleanlinessTuning
	tuning.seat_departure_chance = 1.0
	var private_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	private_rng.seed = 243
	var mess: CleanlinessState = CleanlinessState.new(_world().grid, tuning, private_rng)
	var dirt_cell: Vector2i = _street(-2, 1)
	var spill_cell: Vector2i = _street(-1, 1)
	var indoor_cell: Vector2i = Vector2i(11, 8)
	assert_true(mess.try_spawn_at_departed_seat(dirt_cell))
	assert_true(mess.add_spill(spill_cell))
	assert_true(mess.add_spill(indoor_cell))
	view.bind_cleanliness(mess)
	for cell: Vector2i in [dirt_cell, spill_cell, indoor_cell]:
		assert_true(view.dirt_nodes.has(cell))
		if not view.dirt_nodes.has(cell):
			return
		var ground: float = 0.0 if cell == indoor_cell else pavement
		_assert_flat_mesh_height(view.dirt_nodes[cell], ground + 0.015, "mess decal at %s" % cell)
		var outline: MeshInstance3D = view.dirt_nodes[cell].get_node("Outline") as MeshInstance3D
		_assert_flat_mesh_height(outline, ground + 0.014, "mess outline at %s" % cell)
	assert_eq(mess.floor_mess_kind(dirt_cell), CleanlinessState.MessKind.DIRT)
	assert_eq(mess.floor_mess_kind(spill_cell), CleanlinessState.MessKind.SPILL)
	assert_true(_main.call("set_build_active", true))
	var preview: BuildPreview = _main.get("_build_preview") as BuildPreview
	var random_before: Dictionary = GameState.call("_capture_save")
	var checkpoint: String = _checkpoint()
	assert_true(_mode().begin_buy(&"patio_table_2", _street(-4, 1)))
	assert_true(_mode().current_check.ok, _mode().current_check.why)
	assert_not_null(preview.ghost_mesh)
	if preview.ghost_mesh == null:
		return
	var indoor_table: PlacedItem = _world().grid.item_at(ShopBuilder.items_with_def(_world(), &"table_2")[0].origin)
	assert_almost_eq(_native_minimum_y(preview.ghost_mesh) - _native_minimum_y(view.item_nodes[indoor_table.id]),
		pavement, 0.00001, "the actual furniture ghost clears the existing paving")
	assert_eq(preview.seat_markers.size(), 2)
	for marker: MeshInstance3D in preview.seat_markers:
		var bounds: AABB = marker.global_transform * marker.get_aabb()
		assert_true(bounds.position.y > pavement, "the seat marker's bottom is above the pavement")
		assert_almost_eq(marker.global_position.y, pavement + 0.04, 0.00001)
	_mode().cancel()
	var bench: PlacedItem = _world().grid.item_at(_street(-6, 0))
	_mode().hover_item(bench.id)
	assert_not_null(preview.hover_mesh)
	if preview.hover_mesh == null:
		return
	_assert_flat_mesh_height(preview.hover_mesh, pavement + 0.035, "outdoor furniture hover")
	_mode().hover_item(indoor_table.id)
	assert_not_null(preview.hover_mesh)
	if preview.hover_mesh == null:
		return
	_assert_flat_mesh_height(preview.hover_mesh, 0.035, "indoor furniture hover keeps its old height")
	preview.set_hygiene_cells([dirt_cell, spill_cell, indoor_cell] as Array[Vector2i], true)
	assert_not_null(preview.hygiene_mesh)
	if preview.hygiene_mesh == null:
		return
	var indoor_vertices: int = 0
	var outdoor_vertices: int = 0
	for local: Vector3 in preview.hygiene_mesh.mesh.get_faces():
		var vertex: Vector3 = preview.hygiene_mesh.global_transform * local
		var cell: Vector2i = GridMath.world_to_cell(vertex)
		if cell == indoor_cell:
			indoor_vertices += 1
			assert_almost_eq(vertex.y, 0.04, 0.00001)
		else:
			assert_true(cell == dirt_cell or cell == spill_cell, "every overlay vertex belongs to an actual problem cell")
			outdoor_vertices += 1
			assert_almost_eq(vertex.y, pavement + 0.04, 0.00001)
	assert_true(indoor_vertices > 0 and outdoor_vertices > 0, "one native mesh includes both floor planes")
	assert_eq(GameState.call("_capture_save"), random_before)
	assert_eq(_checkpoint(), checkpoint, "presentation and overlay changes add no save point")
	assert_eq(_world().now, 0)


func test_owned_first_row_has_real_paving_triangles_and_sale_restores_the_street() -> void:
	await _start()
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var dressing: NeighbourhoodDressing = view.neighbourhood_dressing
	var before: Dictionary = dressing.capture_state()
	var pavement: float = _measured_pavement(view)
	var cell: Vector2i = _street(2, 0)
	# This first-row point is beside the original public door approach and
	# inside the old street reserve, where general neighbourhood paving stops.
	var point: Vector3 = GridMath.cell_to_world(cell) + Vector3(0.07, pavement, -0.06)
	assert_null(dressing.get_node_or_null("Static/Pavement/PatioPavement"))
	assert_true(_main.call("shop_patio", [cell] as Array[Vector2i], true))
	var paving: MeshInstance3D = dressing.get_node_or_null("Static/Pavement/PatioPavement") as MeshInstance3D
	assert_not_null(paving, "owned first-row pavement has real native paving geometry")
	if paving == null:
		return
	assert_true(_top_triangles_cover(paving, point), "actual horizontal paving triangles cover the owned cell")
	var unowned: Vector3 = point + Vector3(GridMath.CELL_SIZE, 0.0, 0.0)
	assert_false(_top_triangles_cover(paving, unowned), "the paving batch does not extend into unowned cells")
	var after: Dictionary = dressing.capture_state()
	assert_eq(after["frame"], before["frame"])
	assert_eq(after["bounds"], before["bounds"], "owning row 11 cannot move the street, reserve or existing pavement")
	assert_true(_main.call("shop_patio", [cell] as Array[Vector2i], false))
	assert_null(dressing.get_node_or_null("Static/Pavement/PatioPavement"), "selling the last cell removes its extra paving")
	var sold: Dictionary = dressing.capture_state()
	assert_eq(sold["frame"], before["frame"])
	assert_eq(sold["bounds"], before["bounds"])
	assert_eq(sold["static_mesh_count"], before["static_mesh_count"], "the no-patio native street returns exactly")
	assert_eq(_world().now, 0)


func _top_triangles_cover(mesh: MeshInstance3D, point: Vector3) -> bool:
	var faces: PackedVector3Array = mesh.mesh.get_faces()
	for index: int in range(0, faces.size(), 3):
		var first: Vector3 = mesh.global_transform * faces[index]
		var second: Vector3 = mesh.global_transform * faces[index + 1]
		var third: Vector3 = mesh.global_transform * faces[index + 2]
		if absf(first.y - point.y) > 0.00001 or absf(second.y - point.y) > 0.00001 \
				or absf(third.y - point.y) > 0.00001:
			continue
		var triangle: PackedVector2Array = PackedVector2Array([
			Vector2(first.x, first.z), Vector2(second.x, second.z), Vector2(third.x, third.z)])
		if Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), triangle):
			return true
	return false


func _buy_left_patio() -> bool:
	# Explicit construction budget for the geometry fixture; the original UI
	# purchase tests above continue to use the untouched starter cash.
	Economy.add_cash(1000, Ledger.OTHER)
	var cells: Array[Vector2i] = []
	for row: int in range(_street(0, 0).y, _street(0, 0).y + _editor().patio_area().area.size.y):
		for column: int in range(0, _street(0, 0).x):
			cells.append(Vector2i(column, row))
	var purchased: bool = _main.call("shop_patio", cells, true)
	assert_true(purchased, "the real street entry connects the full left patio fixture")
	return purchased


func _measured_pavement(view: ShopView) -> float:
	var bounds: Array[AABB] = view.room_dressing.native_pavement_bounds()
	assert_false(bounds.is_empty(), "the shipped scene has actual native pavement geometry")
	return bounds[0].end.y if not bounds.is_empty() else 0.0


func _native_minimum_y(visual: ItemVisual) -> float:
	var minimum: float = INF
	var meshes: Array[MeshInstance3D] = visual.rendered_meshes()
	assert_false(meshes.is_empty(), "height checks include imported furniture surfaces")
	for mesh: MeshInstance3D in meshes:
		minimum = minf(minimum, (mesh.global_transform * mesh.get_aabb()).position.y)
	assert_true(is_finite(minimum))
	return minimum


func _assert_flat_mesh_height(node: MeshInstance3D, height: float, context: String) -> void:
	var vertices: PackedVector3Array = node.mesh.get_faces()
	assert_false(vertices.is_empty(), context)
	for local: Vector3 in vertices:
		assert_almost_eq((node.global_transform * local).y, height, 0.00001, context)


func _start() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = _street(1594, 889)
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 243)
	_viewport.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	Clock.set_speed(0)
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	rig.edge_pan_enabled = false
	(_main.get_node("ShopView") as ShopView).set_process(false)
	for frame: int in range(3):
		await tree.process_frame


func _world() -> SimWorld:
	return _main.get("world") as SimWorld


func _mode() -> BuildMode:
	return _main.get("build_mode") as BuildMode


func _editor() -> ShopEditor:
	return _main.get("shop_editor") as ShopEditor


func _forecast() -> String:
	return (_main.get_node("Overlay/MenuPanel/Panel/Content/WeatherForecast") as Label).text


func _checkpoint() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _project(cell: Vector2i) -> Vector2:
	return (_main.get_node("CameraRig/Camera3D") as Camera3D).unproject_position(GridMath.cell_to_world(cell))


func _pointer(cell: Vector2i, shift: bool = false) -> void:
	assert_true(_main.call("update_build_pointer", _project(cell), shift))


func _press(cell: Vector2i, shift: bool = false) -> void:
	_pointer(cell, shift)
	_mouse(cell, true, shift)


func _release(cell: Vector2i) -> void:
	_mouse(cell, false)


func _mouse(cell: Vector2i, pressed: bool, shift: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = _project(cell)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.shift_pressed = shift
	assert_true(_main.call("route_build_input", event))


func _key(code: Key, control: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = control
	assert_true(_main.call("route_build_input", event))


func _street(x: int, y: int) -> Vector2i:
	return _world().grid.entries()[0] + Vector2i(x, y)
