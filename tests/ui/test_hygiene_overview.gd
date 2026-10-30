extends TestCase
## Actual cleaning state is read without changing tasks, dirt, layout or RNG.

var _sim: RestaurantSim
var _random: RandomNumberGenerator
var _catalogue: BuildCatalogue
var _host: Control
var _toggled: Array[bool] = []


func before_each() -> void:
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	_sim.kitchen = Kitchen.new(_sim, ContentDB.new(), Stock.new())
	_random = RandomNumberGenerator.new()
	_random.seed = 179
	var tuning: CleanlinessTuning = CleanlinessTuning.new()
	tuning.seat_departure_chance = 1.0
	_sim.cleanliness = CleanlinessState.new(_sim.world.grid, tuning, _random)
	_toggled.clear()


func after_each() -> void:
	if is_instance_valid(_catalogue):
		_catalogue.free()
	if is_instance_valid(_host):
		_host.free()
	_catalogue = null
	_host = null
	_sim = null
	_random = null


func test_without_a_restroom_lists_dirty_tables_floor_spots_and_existing_day_rating() -> void:
	var table: PlacedItem = _table()
	_sim.kitchen.mark_table_dirty(table.id)
	assert_true(_sim.cleanliness.try_spawn_at_departed_seat(Vector2i(4, 4)))
	assert_true(_sim.cleanliness.try_spawn_at_departed_seat(Vector2i(5, 4)))
	var state: HygieneOverview.Snapshot = HygieneOverview.capture(_sim)
	assert_eq(HygieneOverview.lines(state), PackedStringArray([
		"Dirty tables: 1", "Floor spots: 2", "Today's cleanliness: A bit messy"]))
	assert_false(state.has_restroom)
	assert_eq(state.restroom_spots, 0)
	assert_true(state.problem_cells.has(table.cells[0]))
	assert_true(state.problem_cells.has(table.seat_cells[0]))
	assert_true(state.problem_cells.has(Vector2i(4, 4)))


func test_restroom_separates_used_toilets_from_upkeep_spots_and_deduplicates_tint_cells() -> void:
	var toilet: PlacedItem = _toilet()
	var used: Vector2i = toilet.work_cells[0]
	_sim.restroom_used(used)
	assert_true(_sim.cleanliness.add_use_spot(Vector2i(6, 4)))
	assert_true(_sim.cleanliness.try_spawn_at_departed_seat(used))
	var state: HygieneOverview.Snapshot = HygieneOverview.capture(_sim)
	assert_eq(state.floor_spots, 1, "restroom upkeep is not extra floor dirt")
	assert_eq(state.toilets_needing_tidy, 1, "one used toilet, despite two upkeep spots")
	assert_eq(state.restroom_spots, 2)
	assert_eq(HygieneOverview.lines(state), PackedStringArray([
		"Dirty tables: 0", "Floor spots: 1", "Restroom: 1 toilet needs a tidy · 2 upkeep spots",
		"Today's cleanliness: A bit messy"]))
	assert_eq(state.problem_cells.count(used), 1, "overlapping problems tint their cell once")
	assert_true(state.problem_cells.has(toilet.cells[0]))
	assert_true(state.problem_cells.has(Vector2i(6, 4)))
	_sim.cleanliness.clear_spot(used)
	state = HygieneOverview.capture(_sim)
	assert_eq(state.toilets_needing_tidy, 0)
	assert_eq(state.restroom_spots, 1)
	assert_eq(state.floor_spots, 0)
	assert_eq(state.today_label, "A bit messy", "cleaning does not erase today's report rating")


func test_reading_and_mutating_the_detached_result_cannot_change_cleaning_or_random_streams() -> void:
	_sim.kitchen.mark_table_dirty(_table().id)
	_sim.restroom_used(_toilet().work_cells[0])
	assert_true(_sim.cleanliness.try_spawn_at_departed_seat(Vector2i(4, 4)))
	var random_before: int = _random.state
	var sim_random_before: int = _sim.rng.state
	var version: int = _sim.world.grid.version
	var tasks: Array[SimTask] = _sim.world.board.open_tasks()
	var floor: Array[Vector2i] = _sim.cleanliness.spots()
	var restroom: Array[Vector2i] = _sim.cleanliness.restroom_spots()
	var dirty: Dictionary[int, bool] = _sim.kitchen.dirty_tables.duplicate()
	for iteration: int in range(3):
		var state: HygieneOverview.Snapshot = HygieneOverview.capture(_sim)
		HygieneOverview.lines(state)
		state.problem_cells.clear()
		state.dirty_tables = 99
	assert_eq(_random.state, random_before)
	assert_eq(_sim.rng.state, sim_random_before)
	assert_eq(_sim.world.grid.version, version)
	assert_eq(_sim.world.board.open_tasks(), tasks)
	assert_eq(_sim.cleanliness.spots(), floor)
	assert_eq(_sim.cleanliness.restroom_spots(), restroom)
	assert_eq(_sim.kitchen.dirty_tables, dirty)
	assert_eq(_sim.world.now, 0)
	assert_eq(HygieneOverview.capture(_sim).dirty_tables, 1)


func test_removed_tables_and_empty_restroom_rooms_show_current_problem_counts() -> void:
	var table: PlacedItem = _table()
	_sim.kitchen.mark_table_dirty(table.id)
	_sim.world.grid.remove(table.id)
	assert_eq(HygieneOverview.capture(_sim).dirty_tables, 0)
	_sim.world.grid.set_rooms({Vector2i(6, 6): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	var state: HygieneOverview.Snapshot = HygieneOverview.capture(_sim)
	assert_true(state.has_restroom)
	assert_true(HygieneOverview.lines(state).has("Restroom: 0 toilets need a tidy · 0 upkeep spots"))
	_sim.world.grid.set_rooms({Vector2i(6, 6): SimGrid.Room.DINING} as Dictionary[Vector2i, int])
	assert_eq(HygieneOverview.lines(HygieneOverview.capture(_sim)).size(), 3)


func test_catalogue_toggle_is_beside_the_shared_readout_and_lists_only_the_captured_state() -> void:
	_catalogue = (load("res://src/ui/build_catalogue.tscn") as PackedScene).instantiate() as BuildCatalogue
	_catalogue.bind_content(ContentDB.new())
	_catalogue.set_build_visible(true)
	_catalogue.hygiene_toggled.connect(_record_toggle)
	assert_eq(_catalogue.hygiene_button.get_parent(), _catalogue.theme_label.get_parent())
	assert_eq(_catalogue.hygiene_button.text, "Hygiene")
	assert_eq(_catalogue.hygiene_button.tooltip_text, HygieneOverview.TOGGLE_TIP)
	assert_false(_catalogue.hygiene_panel.visible)
	_catalogue.set_hygiene_lines(HygieneOverview.lines(HygieneOverview.capture(_sim)))
	_catalogue.hygiene_button.button_pressed = true
	_catalogue.hygiene_button.pressed.emit()
	assert_true(_catalogue.hygiene_enabled)
	assert_true(_catalogue.hygiene_panel.visible)
	assert_eq(_catalogue.hygiene_summary.text, "Dirty tables: 0\nFloor spots: 0\nToday's cleanliness: Spotless")
	assert_eq(_toggled, [true] as Array[bool])
	_catalogue.set_paint_visible(true)
	assert_false(_catalogue.hygiene_button.visible)
	assert_false(_catalogue.hygiene_panel.visible)
	_catalogue.set_paint_visible(false)
	assert_true(_catalogue.hygiene_panel.visible)
	_catalogue.set_build_visible(false)
	assert_false(_catalogue.hygiene_panel.visible)
	_catalogue.set_build_visible(true)
	_catalogue.set_hygiene_enabled(false)
	assert_false(_catalogue.hygiene_panel.visible)
	assert_eq(_toggled, [true, false] as Array[bool])


func test_hygiene_readout_wraps_inside_the_catalogue_at_supported_ui_sizes() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.size = Vector2(853, 480)  # 1280×720 at 150% UI size.
	tree.root.add_child(_host)
	_catalogue = (load("res://src/ui/build_catalogue.tscn") as PackedScene).instantiate() as BuildCatalogue
	_host.add_child(_catalogue)
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	_catalogue.bind_content(content)
	_catalogue.bind_blueprints(BlueprintLibrary.new())
	var vibe: VibeModel.Result = VibeModel.Result.new()
	vibe.valid = true
	vibe.active_theme = &"diner"
	vibe.theme_label = "Diner"
	_catalogue.set_vibe(vibe)
	_catalogue.set_build_visible(true)
	_sim.restroom_used(_toilet().work_cells[0])
	_catalogue.set_hygiene_lines(HygieneOverview.lines(HygieneOverview.capture(_sim)))
	_catalogue.set_hygiene_enabled(true)
	for frame: int in range(5):
		await tree.process_frame
	var panel: Control = _catalogue.get_node("Panel") as Control
	var scroll: ScrollContainer = _catalogue.get_node("Panel/Margin/Rows/Scroll") as ScrollContainer
	assert_true(_host.get_global_rect().grow(-11.5).encloses(panel.get_global_rect()))
	assert_false(scroll.get_h_scroll_bar().visible, "the added toggle wraps instead of widening the shop panel")
	assert_true(_catalogue.hygiene_button.size.x > 0.0)
	assert_true(_catalogue.hygiene_summary.size.y > 0.0)
	_host.size = Vector2(1600, 900)
	for frame: int in range(5):
		await tree.process_frame
	assert_true(panel.size.x >= 900.0, "a roomy viewport keeps the usual wide catalogue: panel=%s root=%s columns=%d" % [
		panel.size, _catalogue.size, (_catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Items") as GridContainer).columns])
	assert_true(_catalogue.category_buttons[&"dining"].size.y <= 45.0,
		"the readout never stretches room buttons into tall tiles")


func _table() -> PlacedItem:
	var definition: ItemDef = ItemDef.new()
	definition.category = ItemDef.Category.TABLE
	definition.footprint = Vector2i.ONE
	definition.solid = true
	definition.seat_cells = [Vector2i.RIGHT]
	return _sim.world.grid.place_def(definition, Vector2i(1, 1))


func _toilet() -> PlacedItem:
	var grid: SimGrid = _sim.world.grid
	grid.set_rooms({Vector2i(6, 6): SimGrid.Room.RESTROOM,
		Vector2i(6, 5): SimGrid.Room.RESTROOM, Vector2i(6, 4): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int])
	var definition: ItemDef = ItemDef.new()
	definition.category = ItemDef.Category.RESTROOM
	definition.station_type = &"toilet"
	definition.solid = true
	definition.work_cells = [Vector2i.UP]
	return grid.place_def(definition, Vector2i(6, 6))


func _record_toggle(active: bool) -> void:
	_toggled.append(active)
