extends TestCase
## Fish tank upkeep (#125): cloudiness from the day, its charm, the "Clean
## tank" task and its saved cleaning days. No random draws are involved.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const CLEAN: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")
const TUNING: AquariumTuning = preload("res://data/balance/aquarium.tres")
const VIBE: VibeTuning = preload("res://data/balance/vibe.tres")
const TANK: ItemDef = preload("res://data/items/aquarium.tres")
const LARGE: ItemDef = preload("res://data/items/aquarium_large.tres")
var _sim: RestaurantSim
var _content: ContentDB
var _changes: int = 0


func after_each() -> void:
	if _sim != null:
		_sim.start_day()
	_sim = null
	_content = null
	_changes = 0


func test_both_tanks_load_as_high_charm_cosy_seafood_decor() -> void:
	for entry: Array in [[TANK, &"aquarium", "Aquarium", 180, 3, Vector2i(2, 1)],
			[LARGE, &"aquarium_large", "Large aquarium", 320, 5, Vector2i(3, 1)]]:
		var definition: ItemDef = entry[0]
		assert_eq(definition.id, entry[1])
		assert_eq(definition.display_name, entry[2])
		assert_eq(definition.price, entry[3])
		assert_eq(definition.unlock_level, entry[4])
		assert_eq(definition.footprint, entry[5])
		assert_eq(definition.category, ItemDef.Category.DECOR)
		assert_eq(definition.theme_tags, [&"cosy", &"seafood"] as Array[StringName])
		assert_true(definition.fish_tank)
		assert_true(definition.solid)
		assert_true(definition.work_cells.is_empty() and definition.seat_cells.is_empty())
		assert_eq(definition.glow_color.a, 0.0, "the glow is emissive only: no light")
		var highest_other: int = 0
		var content: ContentDB = ContentDB.new()
		assert_eq(content.load_all(), PackedStringArray())
		for other: ItemDef in content.items():
			if not other.fish_tank and other.category == ItemDef.Category.DECOR:
				highest_other = maxi(highest_other, other.charm)
		assert_true(definition.charm > highest_other, "%s has the highest decor charm" % definition.id)
	assert_true(LARGE.charm > TANK.charm)
	assert_true(TUNING.is_valid())
	assert_true(TUNING.maintenance, "maintenance is on by default")
	assert_eq(TUNING.cloudy_after_days, 4)
	assert_almost_eq(TUNING.cloudy_charm_factor, 0.5)


func test_a_tank_clouds_after_four_days_and_a_clean_clears_it() -> void:
	_make()
	var tank: PlacedItem = _place(TANK)
	var care: AquariumCare = _sim.aquarium
	var placed_day: int = _sim.world.clock.day
	assert_eq(care.cleaned_day(tank.id), placed_day, "a new tank starts clean")
	care.changed.connect(_on_changed)
	for day: int in range(placed_day, placed_day + TUNING.cloudy_after_days):
		assert_false(care.is_cloudy(tank.id, day), "clear on day %d" % day)
		assert_false(care.clean(tank.id, day), "nothing to clean while clear")
	var cloudy_day: int = placed_day + TUNING.cloudy_after_days
	assert_true(care.is_cloudy(tank.id, cloudy_day))
	assert_eq(care.cloudy_ids(_sim.world.grid, cloudy_day), [tank.id] as Array[int])
	assert_eq(care.charm_factors(_sim.world.grid, cloudy_day), {tank.id: 0.5} as Dictionary[int, float])
	assert_true(care.is_cloudy(tank.id, cloudy_day + 20), "it stays cloudy until cleaned")
	assert_true(care.clean(tank.id, cloudy_day))
	assert_eq(_changes, 1)
	assert_eq(care.cleaned_today, 1)
	assert_false(care.is_cloudy(tank.id, cloudy_day))
	assert_true(care.charm_factors(_sim.world.grid, cloudy_day).is_empty())
	assert_true(care.is_cloudy(tank.id, cloudy_day + TUNING.cloudy_after_days), "and clouds again later")


func test_moving_keeps_a_tank_record_and_removing_forgets_it() -> void:
	_make()
	var tank: PlacedItem = _place(TANK)
	_sim.aquarium.restore(_sim.world.grid, {"version": 1, "tanks": [
		{"def_id": "aquarium", "origin": [tank.origin.x, tank.origin.y], "cleaned_day": 0}]}, 9)
	assert_eq(_sim.aquarium.cleaned_day(tank.id), 0)
	_sim.world.clock.day = 9
	for cell: Vector2i in _sim.world.grid.cells():
		if cell != tank.origin and _sim.world.grid.relocate_def(tank.id, cell, 0):
			break
	assert_eq(_sim.aquarium.cleaned_day(tank.id), 0, "a move is not a clean")
	assert_true(_sim.world.grid.remove(tank.id))
	assert_false(_sim.aquarium.has_tank(tank.id))


func test_a_tank_put_back_at_the_same_spot_the_same_day_keeps_its_water() -> void:
	_make()
	var tank: PlacedItem = _place(TANK)
	_cloud(tank)
	var day: int = _sim.world.clock.day
	var cleaned: int = _sim.aquarium.cleaned_day(tank.id)
	var origin: Vector2i = tank.origin
	assert_true(_sim.world.grid.remove(tank.id))
	var again: PlacedItem = _sim.world.grid.place_def(TANK, origin, 0)
	assert_ne(again.id, tank.id)
	assert_eq(_sim.aquarium.cleaned_day(again.id), cleaned, "Undo of a sale is not a clean")
	assert_true(_sim.aquarium.is_cloudy(again.id, day))
	# Next morning the memory is gone: a tank bought there then starts clean.
	assert_true(_sim.world.grid.remove(again.id))
	_sim.world.clock.day = day + 1
	_sim.start_day()
	var fresh: PlacedItem = _sim.world.grid.place_def(TANK, origin, 0)
	assert_eq(_sim.aquarium.cleaned_day(fresh.id), day + 1)


func test_maintenance_off_never_clouds() -> void:
	var tuning: AquariumTuning = TUNING.duplicate() as AquariumTuning
	tuning.maintenance = false
	var care: AquariumCare = AquariumCare.new(tuning)
	_make()
	var tank: PlacedItem = _place(TANK)
	care.track(_sim.world.grid, 1)
	assert_false(care.is_cloudy(tank.id, 400))
	assert_true(care.charm_factors(_sim.world.grid, 400).is_empty())


func test_a_cloudy_tank_counts_half_its_charm_and_a_clean_one_all_of_it() -> void:
	# A charm above the free allowance, so both halves show in the points.
	var clear: VibeModel.Result = VibeModel.evaluate(_tank_inputs(6.0, [1.0]), VIBE)
	var cloudy: VibeModel.Result = VibeModel.evaluate(_tank_inputs(6.0, [0.5]), VIBE)
	var half: VibeModel.Result = VibeModel.evaluate(_tank_inputs(3.0, [1.0]), VIBE)
	assert_true(clear.valid and cloudy.valid)
	assert_true(cloudy.decor_points > 0.0 and cloudy.decor_points < clear.decor_points)
	assert_almost_eq(cloudy.decor_points, half.decor_points, 0.000001, "cloudy = half the charm")
	assert_almost_eq(cloudy.score, half.score, 0.000001)
	# Two copies: the clear one counts first, then the cloudy one decays.
	var mixed: VibeModel.Result = VibeModel.evaluate(_tank_inputs(6.0, [0.5, 1.0]), VIBE)
	var expected: float = 6.0 * (1.0 + 0.5 * VIBE.repeat_decay)
	var reference: VibeModel.Result = VibeModel.evaluate(_tank_inputs(expected, [1.0]), VIBE)
	assert_almost_eq(mixed.decor_points, reference.decor_points, 0.000001)
	assert_false(VibeModel.evaluate(_tank_inputs(6.0, [1.5]), VIBE).valid, "a share over 1 is invalid")
	# The real capture carries the tank's share from AquariumCare.
	_make()
	var tank: PlacedItem = _place(TANK)
	var day: int = _sim.world.clock.day + TUNING.cloudy_after_days
	var factors: Dictionary[int, float] = _sim.aquarium.charm_factors(_sim.world.grid, day)
	var captured: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, [] as Array[RecipeDef], &"", &"",
		[] as Array[ItemDef], factors)
	var plain: VibeModel.Inputs = VibeInputs.capture(_sim.world.grid, _content, [] as Array[RecipeDef])
	for item: VibeModel.Item in captured.items:
		assert_almost_eq(item.charm_scale, 0.5 if item.definition_id == &"aquarium" else 1.0)
	for item: VibeModel.Item in plain.items:
		assert_almost_eq(item.charm_scale, 1.0)
	assert_true(VibeModel.evaluate(captured, VIBE).decor_points < VibeModel.evaluate(plain, VIBE).decor_points)
	assert_not_null(tank)


func test_the_cleaner_cleans_a_cloudy_tank_and_servers_never_do() -> void:
	_make()
	var tank: PlacedItem = _place(TANK)
	_cloud(tank)
	var task: SimTask = _sim.clean_tasks.tank_task_for(tank.id)
	assert_not_null(task, "a cloudy tank posts one Clean tank task")
	assert_eq(task.kind, AquariumCare.TASK_KIND)
	assert_eq(task.label, "Clean the fish tank")
	assert_eq(StaffJobPriorities.job_for_task(task.kind, &"cleaner"), &"cleaning")
	var server: StaffAgent = _role(&"server")
	server.tick(_sim.world)
	assert_null(server.task, "with no cleaner the server still never cleans a tank")
	var cleaner: StaffAgent = StaffAgent.new(&"cleaner", 3)
	cleaner.cell = server.cell
	_sim.world.add_agent(cleaner)
	var owner: OwnerAgent = _sim.owner_agent()
	assert_true(owner.assign_mode(&"floor"))
	owner.tick(_sim.world)
	assert_null(owner.task, "a cleaner on the team keeps the owner off it")
	cleaner.tick(_sim.world)
	assert_eq(cleaner.task, task)
	_sim.aquarium.changed.connect(_on_changed)
	_work_until_clear(tank)
	assert_false(_sim.aquarium.is_cloudy(tank.id, _sim.world.clock.day))
	assert_eq(_changes, 1)
	assert_null(_sim.clean_tasks.tank_task_for(tank.id))


func test_with_no_cleaner_the_owner_on_floor_cleans_it_but_not_resting() -> void:
	_make()
	var tank: PlacedItem = _place(TANK)
	_sim.world.remove_agent(_role(&"server"))
	_cloud(tank)
	var owner: OwnerAgent = _sim.owner_agent()
	assert_true(owner.assign_mode(&"rest"))
	owner.tick(_sim.world)
	assert_null(owner.task)
	assert_true(owner.assign_mode(&"floor"))
	owner.tick(_sim.world)
	assert_eq(owner.task, _sim.clean_tasks.tank_task_for(tank.id))
	_work_until_clear(tank)
	assert_false(_sim.aquarium.is_cloudy(tank.id, _sim.world.clock.day))
	assert_eq(_sim.aquarium.cleaned_day(tank.id), _sim.world.clock.day)


func test_a_tank_moved_with_its_task_open_is_cleaned_at_its_new_spot() -> void:
	_make()
	var tank: PlacedItem = _place(TANK)
	_cloud(tank)
	var old_task: SimTask = _sim.clean_tasks.tank_task_for(tank.id)
	assert_not_null(old_task)
	var old_sides: Array[Vector2i] = old_task.steps[0].candidate_cells.duplicate()
	var cleaner: StaffAgent = StaffAgent.new(&"cleaner", 3)
	cleaner.cell = _role(&"server").cell
	_sim.world.add_agent(cleaner)
	cleaner.tick(_sim.world)
	assert_eq(cleaner.task, old_task, "the cleaner is on its way")
	var moved: bool = false
	var cells: Array[Vector2i] = _sim.world.grid.cells()
	for cell: Vector2i in cells:
		if cell == tank.origin or not _sim.world.grid.relocate_def(tank.id, cell, 0):
			continue
		var sides: Array[Vector2i] = CleanTaskController.tank_sides(_sim.world.grid, tank)
		if sides != old_sides and not sides.is_empty() \
				and _sim.world.grid.is_reachable(_role(&"server").cell, sides[0]):
			moved = true
			break
	assert_true(moved, "the tank found a new spot")
	assert_true(_sim.aquarium.is_cloudy(tank.id, _sim.world.clock.day), "a move is not a clean")
	_sim.clean_tasks.sync_spots()
	var new_task: SimTask = _sim.clean_tasks.tank_task_for(tank.id)
	assert_not_null(new_task)
	assert_ne(new_task, old_task, "the old route was withdrawn and the task posted again")
	assert_eq(new_task.steps[0].candidate_cells, CleanTaskController.tank_sides(_sim.world.grid, tank))
	_work_until_clear(tank)
	assert_false(_sim.aquarium.is_cloudy(tank.id, _sim.world.clock.day))
	var beside: bool = false
	for side: Vector2i in CleanTaskController.tank_sides(_sim.world.grid, tank):
		beside = beside or cleaner.cell == side
	assert_true(beside, "cleaned from beside its new spot")


func test_a_shop_without_tanks_posts_no_tank_tasks() -> void:
	_make()
	_sim.clean_tasks.sync_spots()
	assert_eq(_sim.aquarium.tank_count(), 0)
	assert_eq(_sim.clean_tasks.active_task_count(), 0)


func test_overnight_withdraws_the_task_and_a_still_cloudy_tank_posts_it_again() -> void:
	_make()
	var tank: PlacedItem = _place(TANK)
	_cloud(tank)
	assert_not_null(_sim.clean_tasks.tank_task_for(tank.id))
	_sim.start_day()
	assert_null(_sim.clean_tasks.tank_task_for(tank.id))
	assert_eq(_sim.aquarium.cleaned_today, 0)
	_sim.clean_tasks.sync_spots()
	assert_not_null(_sim.clean_tasks.tank_task_for(tank.id), "still cloudy, so asked for again")


func test_cleaning_days_survive_a_save_round_trip_by_kind_and_position() -> void:
	_make()
	var tank: PlacedItem = _place(TANK)
	_cloud(tank)
	var day: int = _sim.world.clock.day
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_sim.aquarium.to_dict(_sim.world.grid)))
	assert_true(AquariumCare.valid_dict(saved), "JSON numbers still validate")
	var restored: AquariumCare = AquariumCare.new(TUNING)
	assert_true(restored.restore(_sim.world.grid, saved, day))
	assert_eq(restored.cleaned_day(tank.id), _sim.aquarium.cleaned_day(tank.id))
	assert_true(restored.is_cloudy(tank.id, day), "cloudy before saving, cloudy after loading")
	# A clear tank stays clear, and a tank missing from the save starts clean today.
	assert_true(restored.restore(_sim.world.grid, {"version": 1, "tanks": []}, day))
	assert_eq(restored.cleaned_day(tank.id), day)
	for broken: Variant in [null, {}, {"version": 2, "tanks": []}, {"version": 1, "tanks": {}},
			{"version": 1, "tanks": [{"def_id": "aquarium", "origin": [1], "cleaned_day": 0}]},
			{"version": 1, "tanks": [{"def_id": "aquarium", "origin": [1, 2], "cleaned_day": -1}]},
			{"version": 1, "tanks": [{"def_id": 4, "origin": [1, 2], "cleaned_day": 0}]},
			{"version": 1, "tanks": [], "extra": true}]:
		assert_false(AquariumCare.valid_dict(broken), str(broken))
		assert_false(restored.restore(_sim.world.grid, broken, day))


func _on_changed() -> void:
	_changes += 1


func _make() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 100, 1)
	_sim = RestaurantSim.create(LAYOUT, _content, 125, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	var dirt: CleanlinessState = CleanlinessState.new(_sim.world.grid, CLEAN, _rng(5))
	assert_true(_sim.configure_cleanliness(dirt, CLEAN))


## The first spot where the tank fits with a free floor cell beside it.
func _place(definition: ItemDef) -> PlacedItem:
	var cells: Array[Vector2i] = _sim.world.grid.cells()
	cells.reverse()
	for cell: Vector2i in cells:
		if _sim.world.grid.can_place_def(definition, cell, 0) != SimGrid.PlaceResult.OK:
			continue
		var placed: PlacedItem = _sim.world.grid.place_def(definition, cell, 0)
		if placed == null:
			continue
		var sides: Array[Vector2i] = CleanTaskController.tank_sides(_sim.world.grid, placed)
		var reachable: bool = false
		for side: Vector2i in sides:
			reachable = reachable or _sim.world.grid.is_reachable(_role(&"server").cell, side)
		if reachable:
			return placed
		_sim.world.grid.remove(placed.id)
	fail("no spot for %s" % definition.id)
	return null


## Makes the tank's last clean four days back and lets the controller see it.
func _cloud(tank: PlacedItem) -> void:
	var day: int = _sim.world.clock.day
	assert_true(_sim.aquarium.restore(_sim.world.grid, {"version": 1, "tanks": [{"def_id": String((tank.def as ItemDef).id),
		"origin": [tank.origin.x, tank.origin.y], "cleaned_day": maxi(0, day - TUNING.cloudy_after_days)}]}, day))
	if day < TUNING.cloudy_after_days:
		_sim.world.clock.day = TUNING.cloudy_after_days
	assert_true(_sim.aquarium.is_cloudy(tank.id, _sim.world.clock.day))
	_sim.clean_tasks.sync_spots()


func _work_until_clear(tank: PlacedItem) -> void:
	for tick: int in range(1500):
		_sim.advance()
		if not _sim.aquarium.is_cloudy(tank.id, _sim.world.clock.day):
			return
	fail("the tank was never cleaned")


func _role(role: StringName) -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent.role == role:
			return agent as StaffAgent
	return null


static func _tank_inputs(charm: float, scales: Array) -> VibeModel.Inputs:
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	for x: int in range(12):
		for y: int in range(8):
			inputs.floor_cells.append(Vector2i(x, y))
	for index: int in scales.size():
		var item: VibeModel.Item = VibeModel.Item.new()
		item.definition_id = &"aquarium"
		item.charm = charm
		item.charm_scale = float(scales[index])
		item.category = ItemDef.Category.DECOR
		item.theme_tags = [&"cosy", &"seafood"] as Array[StringName]
		item.cells = [Vector2i(index * 2, 0), Vector2i(index * 2 + 1, 0)] as Array[Vector2i]
		inputs.items.append(item)
	return inputs


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
