extends TestCase
## The lifecycle fixture changes only public ticket/ledger state. The final case
## runs a real service day, checking reuse without allocating more scene nodes.

var _content: ContentDB
var _sim: RestaurantSim
var _view: ShopView


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(load("res://data/layouts/tier1_hole_in_the_wall.tres"), _content, 99, errors)
	assert_eq(errors.size(), 0)
	_view = (load("res://src/world/shop_view.tscn") as PackedScene).instantiate() as ShopView
	_view.show_world(_sim.world)
	_view.bind_restaurant(_sim, _content)


func after_each() -> void:
	_view.free()
	_sim = null
	_content = null


func test_every_current_recipe_uses_the_approved_food_kit_model() -> void:
	var expected: Dictionary[StringName, String] = {
		&"burger": "burger-cheese", &"tomato_soup": "bowl-soup",
		&"grilled_cheese": "sandwich", &"tomato_melt": "sandwich",
		&"fries": "fries", &"bar_fries": "fries", &"savoury_pie": "pie",
		&"croissant": "croissant", &"coffee": "cup-coffee", &"tea": "cup-tea",
		&"soft_drink": "soda-glass", &"beer": "glass", &"wine": "glass-wine",
		&"fish_and_chips": "fish", &"mussels_broth": "mussel-open", &"salmon_maki": "sushi-salmon",
		&"seafood_stew": "bowl-broth", &"shrimp_skewer": "skewer",
	}
	var paths: PackedStringArray = _recipe_resource_paths("res://data/recipes")
	var recipes: Array[RecipeDef] = _content.recipes()
	assert_false(paths.is_empty())
	assert_eq(recipes.size(), paths.size(), "every actual recipe resource is loaded, without a fixed total")
	for recipe: RecipeDef in recipes:
		assert_true(paths.has(recipe.resource_path))
		assert_not_null(recipe.view_model, String(recipe.id) + " has its authored presentation mapping")
		if recipe.view_model != null:
			assert_true(recipe.view_model.resource_path.begins_with("res://assets/kenney/food/"))
		assert_true(_view.food.pool[0].models.has(recipe.id), "the warmed pool covers every loaded recipe")
		assert_not_null(_view.food.pool[0].models.get(recipe.id))
	# Preserve every existing exact model choice; new content is discovered above.
	for id: StringName in expected:
		var recipe: RecipeDef = _content.recipe(id)
		assert_not_null(recipe)
		if recipe == null:
			continue
		assert_not_null(recipe.view_model)
		if recipe.view_model != null:
			assert_eq(recipe.view_model.resource_path, "res://assets/kenney/food/%s.glb" % expected[id])


func test_ready_carried_eating_dirty_bussed_and_sink_stack_lifecycle() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_view)
	_view.set_process(false)
	await tree.process_frame
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], RandomNumberGenerator.new())
	guest.table_item_id = table.id
	guest.seat_cell = table.seat_cells[0]
	guest.cell = guest.seat_cell
	guest.state = CustomerAgent.State.WAITING_FOOD
	var order: Order = Order.new()
	order.recipe_id = &"burger"
	order.customer_id = guest.id
	order.table_item_id = table.id
	order.seat_cell = guest.seat_cell
	_sim.orders.place(order, 0)
	assert_true(_sim.kitchen.plates.take(order.id, table.id))
	_sim.orders.set_state(order, Order.State.READY)
	_view._sync_agents()
	var dish: DishVisual = _view.food.tickets[order.id].dish
	assert_not_null(dish)
	assert_eq(dish.stage, &"ready")
	var pass_item: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	assert_true(dish.position.distance_to(_view.food.surfaces[pass_item.id]) < 0.3)
	assert_true(dish.plate.visible)
	assert_true(dish.models[&"burger"].visible)

	var server: StaffAgent = _staff(&"server")
	var deliver: SimTask = SimTask.new(&"deliver", &"server", "Serve fixture")
	deliver.payload = {"order_ids": [order.id], "carried_count": 1}
	_sim.world.board.post(deliver, 0)
	assert_true(_sim.world.board.claim(deliver, server.id, 0))
	server.task = deliver
	_view._sync_agents()
	assert_eq(dish.stage, &"carried")
	assert_true(dish.get_parent() == _view.agent_nodes[server.id])
	var person: PersonView = _view.agent_nodes[server.id] as PersonView
	assert_true(bool(person.get_meta("person_ready")))
	assert_false(person.model_name().is_empty())
	assert_not_null(person._skeleton)
	assert_true(person.carry_anchor_position().y > 0.2)
	assert_true(dish.position.is_equal_approx(person.carry_anchor_position()))
	# Moving the drawn person moves its dish, with no reference to sim cells.
	var before: Vector3 = person.position + person.basis * dish.position
	person.position += Vector3.RIGHT * 0.125
	assert_true((person.position + person.basis * dish.position).is_equal_approx(before + Vector3.RIGHT * 0.125))

	# A real rig carries the plate through both the smoother and display nudge.
	var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(server, _sim.world)
	frame.display_offset = Vector3(0.1, 0.0, 0.0)
	var smoother: MotionSmoother = MotionSmoother.new()
	smoother.observe(server.id, 0, frame)
	frame.floor_position += Vector3.RIGHT * 0.5
	smoother.observe(server.id, 1, frame)
	var newest: Vector3 = frame.floor_position + frame.display_offset
	smoother.blend(server.id, 0.5, frame)
	assert_true(AgentPresentationController.apply(frame, person, 1.0))
	assert_true(frame.anchors_ready)
	_view.food.sync({server.id: frame}, _view.agent_nodes)
	assert_true(person.position.distance_to(newest) > 0.2)
	assert_true(dish.global_position.is_equal_approx(person.global_transform * frame.tray_anchor))

	# A second meal is spread across the existing tray; neither serving is
	# allowed to stay behind on the pass or be placed at the server's feet.
	var second: Order = Order.new()
	second.recipe_id = &"grilled_cheese"
	second.table_item_id = table.id
	second.seat_cell = table.seat_cells[1]
	_sim.orders.place(second, 0)
	_sim.orders.set_state(second, Order.State.READY)
	deliver.payload["order_ids"] = [order.id, second.id]
	deliver.payload["carried_count"] = 2
	_view._sync_agents()
	var other: DishVisual = _view.food.tickets[second.id].dish
	assert_not_null(other)
	assert_true((person.get_node("Tray") as Node3D).visible)
	assert_true(other.get_parent() == person)
	assert_true(other.position.distance_to(dish.position) > 0.2)
	assert_true(dish.position.y > 0.2 and other.position.y > 0.2)

	deliver.payload["carried_count"] = 1
	_sim.orders.set_state(order, Order.State.DELIVERED)
	guest.state = CustomerAgent.State.EATING
	_view._sync_agents()
	assert_eq(dish.stage, &"eating")
	assert_true(dish.get_parent() == _view.food)
	assert_true(absf(dish.position.y - _view.food.surfaces[table.id].y) < 0.001)
	assert_true(dish.position.is_equal_approx(_view.food._seat_spot(table.id, order.seat_cell)))

	guest.state = CustomerAgent.State.LEAVING
	_sim.kitchen.dirty_tables[table.id] = true
	assert_true(_sim.kitchen.plates.return_to_table(order.id, table.id))
	_view._sync_agents()
	assert_eq(dish.stage, &"dirty")
	assert_true(dish.dirty_plate.visible)
	assert_false(dish.plate.visible)
	assert_false(dish.models[&"burger"].visible)
	assert_eq(_sim.kitchen.plates.collect_table(table.id), 1)
	_sim.kitchen.dirty_tables.erase(table.id)
	_view._sync_agents()
	assert_false(dish.visible)
	assert_eq(dish.order_id, 0)
	assert_true(_view.food.stack[0].visible)
	assert_false(_view.food.stack[1].visible)
	assert_true(_sim.kitchen.plates.wash_one())
	_view._sync_agents()
	assert_false(_view.food.stack[0].visible)


func test_pour_frame_carries_unplated_drink_only_after_ready() -> void:
	assert_not_null(_sim.world.grid.place_def(_content.item(&"coffee_machine"), Vector2i(1, 3), 0))
	var server: StaffAgent = _staff(&"server")
	var order: Order = Order.new()
	order.recipe_id = &"coffee"
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	order.table_item_id = table.id
	order.seat_cell = table.seat_cells[0]
	_sim.orders.place(order, 0)
	var pour: SimTask = SimTask.new(&"pour", &"server", "Pour fixture")
	pour.payload = {"order_id": order.id}
	_sim.world.board.post(pour, 0)
	assert_true(_sim.world.board.claim(pour, server.id, 0))
	server.task = pour
	assert_false(AgentPresentationController.frame_for(server, _sim.world, 0.27, 0.0, Vector3.ZERO, 0.0, _sim.orders).carrying)
	_sim.orders.set_state(order, Order.State.READY)
	_view._sync_agents()
	var dish: DishVisual = _view.food.tickets[order.id].dish
	assert_eq(dish.stage, &"carried")
	assert_false(dish.plate.visible)
	assert_false(dish.dirty_plate.visible)
	assert_true(dish.models[&"coffee"].visible)
	assert_false((_view.agent_nodes[server.id].get_node("Tray") as Node3D).visible)


func test_reclaimed_production_delivery_waits_for_pickup_before_carrying_again() -> void:
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	var pass_item: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	var order: Order = Order.new()
	order.recipe_id = &"burger"
	order.table_item_id = table.id
	order.seat_cell = table.seat_cells[0]
	_sim.orders.place(order, 0)
	assert_true(_sim.kitchen.plates.take(order.id, table.id))
	_sim.orders.set_state(order, Order.State.READY)
	var delivery: SimTask = _open_kitchen_task(&"deliver", order.id)
	assert_not_null(delivery)
	if delivery == null:
		return
	var server: StaffAgent = _staff(&"server")
	assert_true(_sim.world.board.claim(delivery, server.id, _sim.world.now))
	server.task = delivery
	_view._sync_agents()
	var dish: DishVisual = _view.food.tickets[order.id].dish
	assert_not_null(dish)
	if dish == null:
		return
	assert_eq(dish.stage, &"ready")
	assert_true(dish.get_parent() == _view.food)
	# Invoke the real pass-pickup callback, then advance to the first carry step.
	server.cell = pass_item.work_cells[1]
	server.step_index = 1
	assert_true(pass_item.reserve(server.cell, server.id))
	assert_true(bool(delivery.steps[1].on_done.call(server)))
	assert_true(bool(delivery.payload.get("batch_prepared", false)))
	server.step_index = 2
	_view._sync_agents()
	assert_eq(dish.stage, &"carried")
	assert_true(dish.get_parent() == _view.agent_nodes[server.id])
	server.call(&"_drop", _sim.world, &"stuck")
	assert_eq(delivery.state, SimTask.State.OPEN)
	_view._sync_agents()
	assert_eq(dish.stage, &"ready")
	assert_true(dish.get_parent() == _view.food)
	assert_true(_sim.world.board.claim(delivery, server.id, _sim.world.now))
	server.task = delivery
	assert_eq(server.step_index, 0)
	_view._sync_agents()
	assert_eq(dish.stage, &"ready", "the new claimant has not reached the pass")
	assert_true(dish.get_parent() == _view.food)
	# Replaying the same production pickup now puts the dish back in the hands.
	server.cell = pass_item.work_cells[1]
	server.step_index = 1
	assert_true(pass_item.reserve(server.cell, server.id))
	assert_true(bool(delivery.steps[1].on_done.call(server)))
	server.step_index = 2
	_view._sync_agents()
	assert_eq(dish.stage, &"carried")
	assert_true(dish.get_parent() == _view.agent_nodes[server.id])


func test_reclaimed_production_pour_waits_for_drink_ready_step() -> void:
	var machine: PlacedItem = _sim.world.grid.place_def(_content.item(&"coffee_machine"), Vector2i(1, 3), 0)
	assert_not_null(machine)
	if machine == null:
		return
	_sim.stock.add(&"coffee_beans", 1, 1)
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	var order: Order = Order.new()
	order.recipe_id = &"coffee"
	order.table_item_id = table.id
	order.seat_cell = table.seat_cells[0]
	_sim.orders.place(order, 0)
	var pour: SimTask = _open_kitchen_task(&"pour", order.id)
	assert_not_null(pour)
	if pour == null:
		return
	var server: StaffAgent = _staff(&"server")
	assert_true(_sim.world.board.claim(pour, server.id, _sim.world.now))
	server.task = pour
	server.cell = machine.work_cells[0]
	server._held_item_id = machine.id
	server._held_cell = server.cell
	assert_true(machine.reserve(server.cell, server.id))
	assert_true(bool(pour.steps[1].on_done.call(server)))
	_view._sync_agents()
	assert_null(_view.food.tickets[order.id].dish)
	# The production drink-ready callback is three steps from the end;
	# the following walk is the first step that carries the finished drink.
	server.step_index = pour.steps.size() - 3
	assert_true(bool(pour.steps[server.step_index].on_done.call(server)))
	assert_eq(order.state, Order.State.READY)
	server.step_index = pour.steps.size() - 2
	_view._sync_agents()
	var dish: DishVisual = _view.food.tickets[order.id].dish
	assert_not_null(dish)
	if dish == null:
		return
	assert_eq(dish.stage, &"carried")
	assert_true(dish.get_parent() == _view.agent_nodes[server.id])
	server.call(&"_drop", _sim.world, &"stuck")
	assert_eq(pour.state, SimTask.State.OPEN)
	_view._sync_agents()
	assert_false(dish.visible)
	assert_true(_sim.world.board.claim(pour, server.id, _sim.world.now))
	server.task = pour
	assert_eq(server.step_index, 0)
	_view._sync_agents()
	assert_false(dish.visible, "the new claimant has not made the drink")
	assert_null(_view.food.tickets[order.id].dish)
	server.step_index = pour.steps.size() - 3
	assert_true(bool(pour.steps[server.step_index].on_done.call(server)))
	server.step_index = pour.steps.size() - 2
	_view._sync_agents()
	assert_true(dish.visible)
	assert_eq(dish.stage, &"carried")
	assert_true(dish.get_parent() == _view.agent_nodes[server.id])


func test_steam_only_during_cooking_and_turns_off_when_station_is_idle() -> void:
	var stove: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"stove")[0]
	var cook: StaffAgent = _staff(&"cook")
	var task: SimTask = SimTask.new(&"cook", &"cook", "Steam fixture")
	task.steps = [TaskStep.work(50, "cooking")] as Array[TaskStep]
	_sim.world.board.post(task, 0)
	assert_true(_sim.world.board.claim(task, cook.id, 0))
	cook.task = task
	cook.step_index = 0
	cook._step_started = true
	cook.work_left = 50.0
	cook._held_item_id = stove.id
	cook._held_cell = stove.work_cells[0]
	cook.cell = cook._held_cell
	assert_true(stove.reserve(cook._held_cell, cook.id))
	_view._sync_agents()
	assert_true(_view.food.steam[stove.id].emitting)
	assert_eq(_view.food.steam[stove.id].amount, 12)
	cook.work_left = 0.0
	_view._sync_agents()
	assert_false(_view.food.steam[stove.id].emitting)


func test_one_real_day_reuses_a_bounded_pool_and_never_changes_rng() -> void:
	for ingredient: IngredientDef in _content.ingredients():
		_sim.stock.add(ingredient.id, 1000, 1)
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	var count: int = _view.food.pool.size()
	var nodes: int = _dish_count(_view)
	_sim.start_day()
	assert_true(_sim.world.clock.start_service())
	var observed: Dictionary[StringName, bool] = {}
	for tick: int in range(6000):
		_sim.advance()
		var rng_before: int = _sim.rng.state
		_view._sync_agents()
		assert_eq(_sim.rng.state, rng_before)
		assert_eq(_view.food.pool.size(), count)
		for dish: DishVisual in _view.food.pool:
			if dish.visible:
				observed[dish.stage] = true
		if _sim.world.clock.phase == SimClock.Phase.CLOSED:
			break
	assert_eq(_sim.world.clock.phase, SimClock.Phase.CLOSED, "the complete real service day finished")
	assert_true(_sim.served_today > 0)
	assert_eq(_dish_count(_view), nodes, "the complete serving-node count stays bounded")
	for stage: StringName in [&"ready", &"carried", &"eating", &"dirty"]:
		assert_true(observed.has(stage), "real service showed %s" % stage)


func test_fryer_has_the_same_bounded_steam_and_removed_station_drops_emitter() -> void:
	var stove: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"stove")[0]
	var origin: Vector2i = stove.origin
	var turns: int = stove.quarter_turns
	_sim.world.grid.remove(stove.id)
	var fryer: PlacedItem = _sim.world.grid.place_def(_content.item(&"fryer"), origin, turns)
	assert_not_null(fryer)
	assert_false(_view.food.steam.has(stove.id))
	assert_true(_view.food.steam.has(fryer.id))
	assert_eq(_view.food.steam[fryer.id].amount, 12)
	assert_false(_view.food.steam[fryer.id].emitting)


func test_sink_stack_never_appears_in_a_shop_without_a_sink() -> void:
	var sink: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"sink")[0]
	_sim.world.grid.remove(sink.id)
	_view._sync_agents()
	for dish: DishVisual in _view.food.stack:
		assert_false(dish.visible)


func test_new_world_releases_held_dishes_and_old_order_signal() -> void:
	var old_food: FoodPresentation = _view.food
	var old_book: OrderBook = _sim.orders
	assert_true(old_book.order_placed.is_connected(old_food._remember))
	var held: DishVisual = old_food.pool[0]
	held.reparent(_view.agent_nodes[_staff(&"server").id], false)
	held.visible = true
	_view.show_world(null)
	assert_false(is_instance_valid(held), "held attachments outside the controller are released too")
	assert_false(is_instance_valid(old_food))
	assert_eq(old_book.order_placed.get_connections().size(), 1, "only the kitchen remains connected")


func test_rotated_long_table_servings_stay_inside_the_top_and_near_each_seat() -> void:
	for table: PlacedItem in ShopBuilder.items_with_def(_sim.world, &"table_2"):
		_sim.world.grid.remove(table.id)
	for turns: int in range(4):
		var table: PlacedItem = _sim.world.grid.place_def(_content.item(&"table_4"), Vector2i(2, 6), turns)
		assert_not_null(table)
		var bounds: AABB = _view.food.surface_bounds[table.id]
		var drawn: Array[Vector3] = []
		for seat: Vector2i in table.seat_cells:
			var spot: Vector3 = _view.food._seat_spot(table.id, seat)
			assert_true(spot.x >= bounds.position.x + 0.1 and spot.x <= bounds.end.x - 0.1)
			assert_true(spot.z >= bounds.position.z + 0.1 and spot.z <= bounds.end.z - 0.1)
			assert_true(spot.distance_to(GridMath.cell_to_world(seat) + Vector3.UP * spot.y) < 0.6,
				"food stays within reach of its own seat, including the ends")
			for other: Vector3 in drawn:
				assert_true(spot.distance_to(other) > 0.24, "distinct seats do not share a plate position")
			drawn.append(spot)
		_sim.world.grid.remove(table.id)


func test_ready_burger_rests_on_the_native_pass_top_at_every_rotation() -> void:
	var original: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	_sim.world.grid.remove(original.id)
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	for blocked_turns: int in [0, 2]:
		assert_eq(_sim.world.grid.can_place_def(_content.item(&"pass_counter"), Vector2i(8, 5), blocked_turns),
			SimGrid.PlaceResult.WALL_IN_WAY, "the old fixture crosses the current authored thin divider")
	for turns: int in range(4):
		assert_eq(_sim.world.grid.can_place_def(_content.item(&"pass_counter"), Vector2i(8, 8), turns), SimGrid.PlaceResult.OK)
		var counter: PlacedItem = _sim.world.grid.place_def(_content.item(&"pass_counter"), Vector2i(8, 8), turns)
		assert_not_null(counter)
		if counter == null:
			return
		assert_eq(counter.work_cells.size(), 2)
		for cell: Vector2i in counter.work_cells:
			assert_true(_sim.world.grid.is_walkable(cell), "each rotated pass work cell remains clear")
			assert_true(_sim.world.grid.is_reachable(_sim.staff_spawns[&"cook"], cell),
				"the real cook spawn can reach both sides of each rotated pass")
		var order: Order = Order.new()
		order.recipe_id = &"burger"
		order.table_item_id = table.id
		order.seat_cell = table.seat_cells[0]
		_sim.orders.place(order, 0)
		_sim.orders.set_state(order, Order.State.READY)
		_view._sync_agents()
		var dish: DishVisual = _view.food.tickets[order.id].dish
		assert_not_null(dish)
		if dish != null:
			assert_eq(dish.stage, &"ready")
			_assert_native_plate_support(counter, dish, "pass quarter turn %d" % turns)
		_sim.orders.set_state(order, Order.State.CANCELLED)
		_sim.world.grid.remove(counter.id)


func test_round_table_linked_chair_meals_fit_the_native_top_at_every_rotation() -> void:
	for existing: PlacedItem in ShopBuilder.items_with_def(_sim.world, &"table_2"):
		_sim.world.grid.remove(existing.id)
	for turns: int in range(4):
		var table: PlacedItem = _sim.world.grid.place_def(_content.item(&"round_table"), Vector2i(2, 6), turns)
		assert_not_null(table)
		if table == null:
			return
		var chairs: Array[PlacedItem] = []
		var spots: Array[Vector3] = []
		for relative: Vector2i in [Vector2i(0, -1), Vector2i(1, 2)]:
			var seat: Vector2i = table.origin + GridMath.rotate_cell(relative, Vector2i(2, 2), turns)
			var facing: int = (turns + (2 if relative.y < 0 else 0)) % 4
			var chair: PlacedItem = _sim.world.grid.place_def(_content.item(&"chair"), seat, facing)
			assert_not_null(chair)
			if chair == null:
				return
			chairs.append(chair)
			var plan: DiningSeats.Plan = DiningSeats.derive(_sim.world.grid)
			assert_eq(plan.failure_for(chair.id), "")
			assert_true(plan.seats_for(table.id).has(seat), "the actual chair must link to this table")
			assert_true(table.seat_cells.has(seat))
			var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], RandomNumberGenerator.new())
			guest.table_item_id = table.id
			guest.seat_cell = seat
			guest.cell = seat
			guest.state = CustomerAgent.State.EATING
			var order: Order = Order.new()
			order.recipe_id = &"burger"
			order.customer_id = guest.id
			order.table_item_id = table.id
			order.seat_cell = seat
			_sim.orders.place(order, 0)
			assert_true(_sim.kitchen.plates.take(order.id, table.id))
			_sim.orders.set_state(order, Order.State.DELIVERED)
			_view._sync_agents()
			var dish: DishVisual = _view.food.tickets[order.id].dish
			assert_not_null(dish)
			if dish != null:
				assert_eq(dish.stage, &"eating")
				_assert_native_plate_support(table, dish, "round table quarter turn %d seat %s" % [turns, seat])
				assert_true(dish.position.distance_to(GridMath.cell_to_world(seat) + Vector3.UP * dish.position.y) < 0.6)
				for other: Vector3 in spots:
					assert_true(dish.position.distance_to(other) > 0.24, "opposite chairs keep distinct servings")
				spots.append(dish.position)
		for chair: PlacedItem in chairs:
			_sim.world.grid.remove(chair.id)
		_sim.world.grid.remove(table.id)


# Independent geometry oracle: support comes from the actual imported triangles
# beneath the plate, never the presentation controller's bounds or inset helper.
func _assert_native_plate_support(item: PlacedItem, dish: DishVisual, context: String) -> void:
	var faces: PackedVector3Array = _native_faces(_view.item_nodes[item.id], Transform3D.IDENTITY)
	var top: PackedVector3Array = []
	for index: int in range(0, faces.size(), 3):
		var a: Vector3 = faces[index]
		var b: Vector3 = faces[index + 1]
		var c: Vector3 = faces[index + 2]
		if absf(a.y - b.y) < 0.0001 and absf(a.y - c.y) < 0.0001 \
				and absf(dish.position.y - a.y) < 0.01 \
				and (b - a).cross(c - a).length() > 0.000001:
			top.append_array(PackedVector3Array([a, b, c]))
	assert_false(top.is_empty(), "%s has native horizontal support at plate height" % context)
	assert_true(_point_on_native_top(dish.position, top), "%s serving center is over the native top" % context)
	var plate: PackedVector3Array = _native_faces(dish.plate, dish.transform)
	assert_false(plate.is_empty(), "%s measures the actual plate mesh" % context)
	var unsupported: int = 0
	for vertex: Vector3 in plate:
		if not _point_on_native_top(vertex, top):
			unsupported += 1
	assert_eq(unsupported, 0, "%s full plate footprint is supported (%d/%d unsupported vertices)" % [context, unsupported, plate.size()])


func _native_faces(node: Node, parent_transform: Transform3D) -> PackedVector3Array:
	var transform: Transform3D = parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	var result: PackedVector3Array = []
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for vertex: Vector3 in mesh.get_faces():
				result.append(transform * vertex)
	for child: Node in node.get_children():
		if not child.has_meta(&"seat_cell"):
			result.append_array(_native_faces(child, transform))
	return result


func _point_on_native_top(point: Vector3, faces: PackedVector3Array) -> bool:
	var p: Vector2 = Vector2(point.x, point.z)
	for index: int in range(0, faces.size(), 3):
		var a: Vector2 = Vector2(faces[index].x, faces[index].z)
		var b: Vector2 = Vector2(faces[index + 1].x, faces[index + 1].z)
		var c: Vector2 = Vector2(faces[index + 2].x, faces[index + 2].z)
		var ab: float = (b - a).cross(p - a)
		var bc: float = (c - b).cross(p - b)
		var ca: float = (a - c).cross(p - c)
		if minf(ab, minf(bc, ca)) >= -0.000001 or maxf(ab, maxf(bc, ca)) <= 0.000001:
			return true
	return false


func test_two_passes_and_sinks_follow_kitchen_order_and_refresh_after_removal() -> void:
	var first_pass: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	var first_sink: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"sink")[0]
	var other_pass: PlacedItem = _sim.world.grid.place_def(_content.item(&"pass_counter"), Vector2i(8, 3), 0)
	var other_sink: PlacedItem = _sim.world.grid.place_def(_content.item(&"sink"), Vector2i(12, 1), 2)
	assert_not_null(other_pass)
	assert_not_null(other_sink)
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	var order: Order = Order.new()
	order.recipe_id = &"burger"
	order.table_item_id = table.id
	order.seat_cell = table.seat_cells[0]
	_sim.orders.place(order, 0)
	_sim.orders.set_state(order, Order.State.READY)
	_view._sync_agents()
	var dish: DishVisual = _view.food.tickets[order.id].dish
	assert_true(dish.position.distance_to(_view.food.surfaces[first_pass.id]) < 0.3)
	assert_true(dish.position.distance_to(_view.food.surfaces[other_pass.id]) > 1.0)
	assert_true(_sim.kitchen.plates.take(9001, table.id))
	assert_true(_sim.kitchen.plates.return_to_table(9001, table.id))
	assert_eq(_sim.kitchen.plates.collect_table(table.id), 1)
	_view._sync_agents()
	assert_true(_view.food.stack[0].visible)
	assert_true(_view.food.stack[0].position.is_equal_approx(_view.food.surfaces[first_sink.id] + Vector3(0.12, 0, 0)))
	_sim.world.grid.remove(first_sink.id)
	_view._sync_agents()
	assert_true(_view.food.stack[0].position.is_equal_approx(_view.food.surfaces[other_sink.id] + Vector3(0.12, 0, 0)))
	_sim.world.grid.remove(other_sink.id)
	_view._sync_agents()
	assert_false(_view.food.stack[0].visible)
	_sim.world.grid.remove(first_pass.id)
	_view._sync_agents()
	assert_false(dish.visible, "the real kitchen cancels the removed pass's ready ticket")
	var next: Order = Order.new()
	next.recipe_id = &"burger"
	next.table_item_id = table.id
	next.seat_cell = table.seat_cells[0]
	_sim.orders.place(next, 0)
	_sim.orders.set_state(next, Order.State.READY)
	_view._sync_agents()
	var next_dish: DishVisual = _view.food.tickets[next.id].dish
	assert_not_null(next_dish)
	assert_true(next_dish.position.distance_to(_view.food.surfaces[other_pass.id]) < 0.3)


func test_recooking_hides_then_reuses_serving_and_cancelled_pruned_tickets_disappear() -> void:
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	var order: Order = Order.new()
	order.recipe_id = &"burger"
	order.table_item_id = table.id
	order.seat_cell = table.seat_cells[0]
	_sim.orders.place(order, 0)
	_sim.orders.set_state(order, Order.State.READY)
	_view._sync_agents()
	var dish: DishVisual = _view.food.tickets[order.id].dish
	assert_true(dish.visible)
	_sim.orders.set_state(order, Order.State.COOKING)
	_view._sync_agents()
	assert_false(dish.visible)
	assert_eq(dish.order_id, 0)
	assert_false(_view.food.tickets[order.id].retired)
	_sim.orders.set_state(order, Order.State.READY)
	_view._sync_agents()
	assert_true(dish.visible)
	assert_true(_view.food.tickets[order.id].dish == dish)
	_sim.orders.set_state(order, Order.State.CANCELLED)
	_view._sync_agents()
	assert_false(dish.visible)
	assert_true(_view.food.tickets[order.id].retired)
	_sim.orders.prune_finished()
	var next: Order = Order.new()
	next.recipe_id = &"burger"
	next.table_item_id = table.id
	next.seat_cell = table.seat_cells[0]
	_sim.orders.place(next, 0)
	assert_false(_view.food.tickets.has(order.id))
	assert_eq(_view.food.tickets.size(), 1)
	assert_true(_view.food.tickets.has(next.id))


func test_dirty_stack_follows_real_washing_at_a_reachable_second_sink() -> void:
	var first: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"sink")[0]
	assert_true(_sim.world.grid.set_terrain(first.work_cells[0], SimGrid.Terrain.WALL))
	var second: PlacedItem = _sim.world.grid.place_def(_content.item(&"sink"), Vector2i(11, 1), 2)
	assert_not_null(second)
	assert_true(_sim.kitchen.configure_plates(2))
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	for order_id: int in range(10000, 10002):
		assert_true(_sim.kitchen.plates.take(order_id, table.id))
		assert_true(_sim.kitchen.plates.recover_order(order_id))
	_sim.kitchen.advance()
	var server: StaffAgent = _staff(&"server")
	var saw_washing: bool = false
	for tick: int in range(500):
		_sim.advance()
		_view._sync_agents()
		if server.task != null and server.task.kind == &"wash" \
				and AgentPresentationController.frame_for(server, _sim.world).working:
			saw_washing = true
			assert_eq(server.task.payload["sink_id"], second.id)
			assert_eq(second.reserved_by(server.cell), server.id)
			assert_true(_view.food.stack[0].visible)
			assert_true(_view.food.stack[0].position.is_equal_approx(_view.food.surfaces[second.id] + Vector3(0.12, 0, 0)))
			break
	assert_true(saw_washing, "the real server worked the reachable second sink")


func _dish_count(node: Node) -> int:
	var count: int = 1 if node is DishVisual else 0
	for child: Node in node.get_children():
		count += _dish_count(child)
	return count


func _open_kitchen_task(kind: StringName, order_id: int) -> SimTask:
	for task: SimTask in _sim.world.board.open_tasks():
		if task.kind == kind and int(task.payload.get("order_id", 0)) == order_id:
			return task
	return null


func _staff(role: StringName) -> StaffAgent:
	for agent: SimAgent in _sim.world.agents:
		if agent.role == role:
			return agent as StaffAgent
	return null


func test_every_seafood_mapping_draws_its_actual_model_on_a_supported_pooled_plate() -> void:
	var expected: Dictionary[StringName, String] = {
		&"fish_and_chips": "fish", &"mussels_broth": "mussel-open", &"salmon_maki": "sushi-salmon",
		&"seafood_stew": "bowl-broth", &"shrimp_skewer": "skewer",
	}
	assert_not_null(_sim.world.grid.place_def(_content.item(&"fryer"), Vector2i(2, 3)))
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	var pass_item: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	var pool_count: int = _view.food.pool.size()
	var dish_count: int = _dish_count(_view)
	var first: DishVisual
	for id: StringName in expected:
		var recipe: RecipeDef = _content.recipe(id)
		assert_not_null(recipe)
		assert_not_null(recipe.view_model)
		if recipe.view_model == null:
			continue
		assert_eq(recipe.view_model.resource_path, "res://assets/kenney/food/%s.glb" % expected[id])
		var order: Order = Order.new()
		order.recipe_id = id
		order.table_item_id = table.id
		order.seat_cell = table.seat_cells[0]
		_sim.orders.place(order, 0)
		_sim.orders.set_state(order, Order.State.READY)
		assert_eq(order.state, Order.State.READY, String(id) + " has all real fixture stations")
		_view._sync_agents()
		var dish: DishVisual = _view.food.tickets[order.id].dish
		assert_not_null(dish, String(id) + " has an actual serving")
		if dish == null:
			continue
		if first == null:
			first = dish
		assert_true(dish == first, "successive seafood meals reuse the same released pool node")
		assert_true(dish.visible)
		assert_eq(dish.stage, &"ready")
		assert_true(dish.plate.visible)
		assert_false(dish.dirty_plate.visible)
		assert_true(dish.models[id].visible)
		assert_true(dish._shown == dish.models[id])
		assert_eq(dish.models[id].get_child(0).scene_file_path, recipe.view_model.resource_path)
		assert_eq((dish.models[id].get_child(0) as Node3D).scale, Vector3.ONE * ArtScale.FOOD_SCALE)
		_assert_native_plate_support(pass_item, dish, String(id) + " native pass support")
		_sim.orders.set_state(order, Order.State.CANCELLED)
		_view._sync_agents()
		assert_false(dish.visible)
		assert_eq(dish.order_id, 0)
		assert_eq(_view.food.pool.size(), pool_count)
		assert_eq(_dish_count(_view), dish_count)


func test_unmapped_valid_recipe_uses_a_prewarmed_real_plate_without_allocating_during_show_or_clear() -> void:
	var future: RecipeDef = _future_recipe()
	var definitions: Array[RecipeDef] = _content.recipes()
	definitions.append(future)
	assert_eq(ContentDB.validate_definitions(_content.ingredients(), definitions, _content.items()), PackedStringArray())
	for warm_future: bool in [false, true]:
		var dish: DishVisual = DishVisual.new()
		dish.prepare(definitions if warm_future else _content.recipes())
		var count: int = _food_node_count(dish)
		var plate_id: int = dish.plate.get_instance_id()
		var plate_faces: PackedVector3Array = _native_faces(dish.plate, Transform3D.IDENTITY)
		assert_false(plate_faces.is_empty(), "the fallback contains real approved plate mesh geometry")
		assert_true(dish.footprint_radius > 0.0)
		if warm_future:
			assert_not_null(dish.models.get(future.id))
		for iteration: int in 20:
			dish.show_dish(_content.recipe(&"burger"), false)
			assert_true(dish.models[&"burger"].visible)
			dish.show_dish(future, false)
			assert_true(dish.visible)
			assert_not_null(dish._shown)
			assert_true(dish._shown == dish.plate, "a valid unmapped dish has one actual generic plated serving")
			assert_true(dish.plate.visible)
			assert_false(dish.dirty_plate.visible)
			assert_false(dish.models[&"burger"].visible)
			assert_eq(dish.recipe_id, future.id)
			assert_eq(dish.plate.get_instance_id(), plate_id)
			dish.show_dish(future, true)
			assert_false(dish.plate.visible)
			assert_true(dish.dirty_plate.visible)
			assert_eq(_food_node_count(dish), count)
			dish.show_dish(_content.recipe(&"coffee"), false)
			assert_true(dish.models[&"coffee"].visible)
			assert_false(dish.plate.visible, "a mapped drink keeps its existing unplated presentation")
			assert_false(dish.dirty_plate.visible)
		dish.stage = &"carried"
		dish.order_id = 9236
		dish.show_dish(null, false)
		_assert_empty_serving(dish)
		dish.show_dish(future, false)
		dish.show_dish(RecipeDef.new(), false)
		_assert_empty_serving(dish)
		assert_eq(_food_node_count(dish), count)
		dish.free()


func test_future_valid_recipe_with_no_model_survives_ready_carry_cancel_and_pool_reuse() -> void:
	var future: RecipeDef = _future_recipe()
	var definitions: Array[RecipeDef] = _content.recipes()
	definitions.append(future)
	assert_eq(ContentDB.validate_definitions(_content.ingredients(), definitions, _content.items()), PackedStringArray())
	# ContentDB has no mutation API: add one validated in-memory future resource
	# to this test-owned catalogue so both Kitchen and presentation read it.
	_content._recipes[future.id] = future
	_view.bind_restaurant(_sim, _content)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_view)
	_view.set_process(false)
	await tree.process_frame
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	var pass_item: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"pass_counter")[0]
	var order: Order = Order.new()
	order.recipe_id = future.id
	order.table_item_id = table.id
	order.seat_cell = table.seat_cells[0]
	_sim.orders.place(order, 0)
	_sim.orders.set_state(order, Order.State.READY)
	assert_eq(order.state, Order.State.READY)
	_view._sync_agents()
	var dish: DishVisual = _view.food.tickets[order.id].dish
	assert_not_null(dish)
	if dish == null:
		return
	assert_true(dish.visible)
	assert_true(dish._shown == dish.plate)
	assert_true(dish.plate.visible)
	assert_eq(dish.stage, &"ready")
	_assert_native_plate_support(pass_item, dish, "future generic plate native pass support")
	var pool_count: int = _view.food.pool.size()
	var node_count: int = _dish_count(_view)
	var server: StaffAgent = _staff(&"server")
	var delivery: SimTask = SimTask.new(&"deliver", &"server", "Carry future serving")
	delivery.payload = {"order_ids": [order.id], "carried_count": 1}
	_sim.world.board.post(delivery, 0)
	assert_true(_sim.world.board.claim(delivery, server.id, 0))
	server.task = delivery
	_view._sync_agents()
	var person: PersonView = _view.agent_nodes[server.id] as PersonView
	assert_not_null(person._skeleton)
	assert_eq(dish.stage, &"carried")
	assert_true(dish.get_parent() == person)
	assert_true(person.carry_anchor_position().y > 0.2)
	assert_true(dish.position.is_equal_approx(person.carry_anchor_position()))
	assert_true(dish.global_position.is_equal_approx(person.global_transform * person.carry_anchor_position()))
	_sim.orders.set_state(order, Order.State.CANCELLED)
	_view._sync_agents()
	assert_null(_view.food.tickets[order.id].dish)
	_assert_empty_serving(dish)
	assert_true(dish.get_parent() == _view.food)
	assert_eq(_view.food.pool.size(), pool_count)
	assert_eq(_dish_count(_view), node_count)
	var next: Order = Order.new()
	next.recipe_id = future.id
	next.table_item_id = table.id
	next.seat_cell = table.seat_cells[0]
	_sim.orders.place(next, 0)
	_sim.orders.set_state(next, Order.State.READY)
	_view._sync_agents()
	assert_true(_view.food.tickets[next.id].dish == dish)
	assert_true(dish.plate.visible)
	assert_eq(_view.food.pool.size(), pool_count)
	assert_eq(_dish_count(_view), node_count)


func test_missing_or_empty_order_recipe_never_becomes_a_generic_meal() -> void:
	var before: int = _dish_count(_view)
	for id: StringName in [&"", &"not_a_catalogue_recipe"]:
		var order: Order = Order.new()
		order.recipe_id = id
		_sim.orders.place(order, 0)
		_view._sync_agents()
		assert_null(_view.food.tickets[order.id].recipe)
		assert_null(_view.food.tickets[order.id].dish)
	for dish: DishVisual in _view.food.pool:
		assert_false(dish.visible)
		assert_eq(dish.order_id, 0)
	assert_eq(_dish_count(_view), before)


func _future_recipe() -> RecipeDef:
	var future: RecipeDef = _content.recipe(&"burger").duplicate() as RecipeDef
	future.id = &"future_unmapped_special"
	future.display_name = "Future special"
	future.view_model = null
	return future


func _assert_empty_serving(dish: DishVisual) -> void:
	assert_false(dish.visible)
	assert_false(dish.plate.visible)
	assert_false(dish.dirty_plate.visible)
	assert_null(dish._shown)
	assert_eq(dish.recipe_id, &"")
	assert_eq(dish.stage, &"")
	assert_eq(dish.order_id, 0)


func _food_node_count(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _food_node_count(child)
	return count


func _recipe_resource_paths(folder: String) -> PackedStringArray:
	var directory: DirAccess = DirAccess.open(folder)
	assert_not_null(directory)
	var paths: PackedStringArray = PackedStringArray()
	if directory == null:
		return paths
	for file: String in directory.get_files():
		if file.ends_with(".tres"):
			paths.append(folder.path_join(file))
	for child: String in directory.get_directories():
		paths.append_array(_recipe_resource_paths(folder.path_join(child)))
	paths.sort()
	return paths
