extends TestCase
## Presenter tests run before tree readiness and never advance the simulation.

const PANEL_SCENE: PackedScene = preload("res://src/ui/inspect_panel.tscn")

var _panel: InspectPanel
var _world: SimWorld
var _restaurant: RestaurantSim
var _clears: int = 0


func before_each() -> void:
	_world = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	_restaurant = RestaurantSim.new()
	_restaurant.world = _world
	_panel = PANEL_SCENE.instantiate() as InspectPanel
	_panel.bind_world(_world)
	_panel.selection_cleared.connect(_record_clear)


func after_each() -> void:
	_panel.free()


func test_type_name_is_authored_text_and_inspection_does_not_draw() -> void:
	var kind: CustomerType = preload("res://data/customers/types.tres").find_type(&"foodie").duplicate() as CustomerType
	kind.id = &"internal_profile_key"
	kind.display_name = "Food lover"
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 117
	var guest: CustomerAgent = _restaurant.add_customer(Vector2i.ONE, random, kind)
	var before: int = random.state
	_panel.show_agent(guest.id)
	_panel.refresh()
	assert_true(_label("Details").text.contains("Type: Food lover"))
	assert_false(_label("Details").text.contains("internal_profile_key"))
	assert_eq(random.state, before)
	assert_eq(_world.now, 0)


func test_scene_is_hidden_themed_and_mouse_safe_before_ready() -> void:
	assert_false(_panel.is_node_ready())
	assert_false(_panel.visible)
	assert_eq(_panel.selected_agent_id, -1)
	assert_eq(_panel.selected_item_id, -1)
	assert_eq(_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_panel.anchor_right, 1.0)
	assert_eq(_panel.anchor_bottom, 1.0)
	assert_eq(_panel.theme, load("res://src/ui/theme/main_theme.tres"))
	var panel: Control = _panel.get_node("Panel") as Control
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(panel.anchor_left, 0.0)
	assert_eq(panel.anchor_top, 1.0)
	assert_eq(panel.anchor_bottom, 1.0)
	assert_eq((_panel.get_node("Panel/Rows") as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for path: String in ["Title", "Why", "Details", "Patience", "Patience/PatienceLabel", "Patience/PatienceBar", "Reservations"]:
		assert_eq(_control(path).mouse_filter, Control.MOUSE_FILTER_IGNORE, path)


func test_the_delivery_driver_has_a_plain_title() -> void:
	var courier: CourierAgent = CourierAgent.new([Vector2i(1, 1), Vector2i(2, 1)] as Array[Vector2i], 1, Vector2i(3, 1))
	_world.add_agent(courier)
	_panel.show_agent(courier.id)
	assert_eq(_label("Title").text, "Delivery driver", "no raw role or id (rule 11)")
	assert_eq(_label("Why").text, "Bringing a delivery")


func test_staff_why_skill_task_and_step_refresh_before_ready() -> void:
	var staff: StaffAgent = _staff()
	_panel.show_agent(staff.id)
	assert_true(_panel.visible)
	assert_true(_label("Title").text.contains("Ada"))
	assert_eq(_label("Why").text, staff.why())
	assert_true(_label("Details").text.contains("Cook skill: 4/5"))
	assert_true(_label("Details").text.contains("Task: Looking for work"))
	staff.skills[&"server"] = 2
	var task: SimTask = SimTask.new(&"deliver", &"server", "Serve soup")
	task.steps.append(TaskStep.go_to_cell(Vector2i(2, 1), "Collecting soup"))
	task.steps.append(TaskStep.work(20, "Serving soup"))
	_world.board.post(task, _world.now)
	assert_true(_world.board.claim(task, staff.id, _world.now))
	staff.task = task
	_panel.refresh()
	assert_eq(_label("Why").text, staff.why())
	assert_true(_label("Details").text.contains("Server skill: 2/5"))
	assert_true(_label("Details").text.contains("Task: Serve soup"))
	assert_true(_label("Details").text.contains("Step 1/2: Collecting soup"))
	staff.step_index = 1
	_panel.refresh()
	assert_eq(_label("Why").text, "Serve soup: Serving soup")
	assert_true(_label("Details").text.contains("Step 2/2: Serving soup"))
	_panel._ready()
	assert_eq(_panel.selected_agent_id, staff.id)
	assert_false(_control("Patience").visible)


func test_staff_step_bounds_are_display_only() -> void:
	var staff: StaffAgent = _staff()
	staff.task = SimTask.new(&"cook", &"any", "Cook soup")
	staff.task.steps.append(TaskStep.work(20, "Cooking"))
	staff.step_index = 99
	_panel.show_agent(staff.id)
	assert_eq(_label("Why").text, "Cook soup")
	assert_true(_label("Details").text.contains("Cook skill: 4/5"))
	assert_true(_label("Details").text.contains("Step: Completing task"))
	assert_eq(staff.step_index, 99)
	staff.step_index = -99
	_panel.refresh()
	assert_eq(_label("Why").text, "Cook soup")
	assert_true(_label("Details").text.contains("Step: No active step"))
	assert_eq(staff.step_index, -99)
	staff.step_index = 0
	staff.task.steps[0] = null
	_panel.refresh()
	assert_eq(_label("Why").text, "Cook soup")
	assert_null(staff.task.steps[0])


func test_guest_why_state_and_correct_patience_budget_refresh() -> void:
	var guest: CustomerAgent = _guest()
	guest.queue_patience = 50
	guest._queue_wait = 20
	_panel.show_agent(guest.id)
	assert_eq(_label("Why").text, guest.why())
	assert_eq(_label("Details").text, "Type: Regular\nState: Queued")
	assert_eq(_label("Patience/PatienceLabel").text, "Table patience: 3s left")
	assert_eq(_bar().max_value, 50.0)
	assert_eq(_bar().value, 30.0)
	guest.state = CustomerAgent.State.WAITING_FOOD
	guest.food_patience = 120
	guest._food_wait = 30
	_panel.refresh()
	assert_eq(_label("Why").text, guest.why())
	assert_eq(_label("Details").text, "Type: Regular\nState: Waiting for food")
	assert_eq(_label("Patience/PatienceLabel").text, "Food patience: 9s left")
	assert_eq(_bar().max_value, 120.0)
	assert_eq(_bar().value, 90.0)
	guest.state = CustomerAgent.State.EATING
	_panel.refresh()
	assert_eq(_label("Why").text, "Enjoying my meal")
	assert_eq(_label("Details").text, "Type: Regular\nState: Eating")
	assert_false(_control("Patience").visible)


func test_plate_departure_reason_is_plain_text_in_inspection_and_the_evening_report() -> void:
	var guest: CustomerAgent = _guest()
	guest.state = CustomerAgent.State.LEAVING
	guest.leave_reason = &"no_clean_plates"
	var before: Array = [guest.state, guest.leave_reason, guest.rng.state, _world.now]
	_panel.show_agent(guest.id)
	_panel.refresh()
	assert_eq(_label("Why").text, "Leaving: no clean plates")
	assert_false(_label("Why").text.contains("no_clean_plates"))
	assert_false(_control("Patience").visible)
	assert_eq([guest.state, guest.leave_reason, guest.rng.state, _world.now], before)
	var report: Control = load("res://src/ui/evening_report.tscn").instantiate() as Control
	var day: DayReport = DayReport.new()
	day.leave_reasons[&"no_clean_plates"] = 2
	report.call("show_report", day)
	var rows: GridContainer = report.get_node("%ReasonRows") as GridContainer
	assert_eq((rows.get_child(0) as Label).text, "No clean plates")
	assert_eq((rows.get_child(1) as Label).text, "2")
	report.free()


func test_walking_guest_shows_combined_search_budget_without_changing_counters() -> void:
	var guest: CustomerAgent = _guest()
	guest.state = CustomerAgent.State.WALKING_TO_SEAT
	guest.queue_patience = 100
	guest._queue_wait = 20
	guest._walk_wait = 30
	guest.food_patience = 900
	guest._food_wait = 899
	var before: Array[int] = [guest.state, guest.queue_patience, guest._queue_wait,
		guest._walk_wait, guest.food_patience, guest._food_wait, _world.now]
	_panel.show_agent(guest.id)
	assert_eq(_label("Why").text, guest.why())
	assert_eq(_label("Details").text, "Type: Regular\nState: Walking to seat")
	assert_true(_control("Patience").visible)
	assert_eq(_bar().max_value, 100.0)
	assert_eq(_bar().value, 50.0)
	assert_eq(_label("Patience/PatienceLabel").text, "Table search patience: 5s left")
	assert_eq([guest.state, guest.queue_patience, guest._queue_wait, guest._walk_wait,
		guest.food_patience, guest._food_wait, _world.now] as Array[int], before)
	for walking_time: int in [80, 130]:
		guest._walk_wait = walking_time
		var exhausted_before: Array[int] = [guest.state, guest.queue_patience, guest._queue_wait,
			guest._walk_wait, guest.food_patience, guest._food_wait, _world.now]
		_panel.refresh()
		assert_true(_control("Patience").visible)
		assert_eq(_bar().value, 0.0, "exactly exhausted or beyond the search budget")
		assert_eq(_label("Patience/PatienceLabel").text, "Table search patience: 0s left")
		assert_eq([guest.state, guest.queue_patience, guest._queue_wait, guest._walk_wait,
			guest.food_patience, guest._food_wait, _world.now] as Array[int], exhausted_before)


func test_guest_patience_states_and_limits_are_clamped_without_repairs() -> void:
	var guest: CustomerAgent = _guest()
	_panel.show_agent(guest.id)
	for state: int in range(CustomerAgent.State.LEFT + 1):
		guest.state = state as CustomerAgent.State
		_panel.refresh()
		var waiting: bool = state in [CustomerAgent.State.ARRIVING, CustomerAgent.State.QUEUED,
			CustomerAgent.State.WALKING_TO_SEAT, CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD]
		assert_eq(_control("Patience").visible, waiting, "state %d" % state)
	guest.state = CustomerAgent.State.QUEUED
	guest.queue_patience = 50
	for elapsed: int in [-10, 70]:
		guest._queue_wait = elapsed
		_panel.refresh()
		assert_eq(_bar().value, 50.0 if elapsed < 0 else 0.0)
		assert_eq(guest._queue_wait, elapsed)
	for limit: int in [0, -10]:
		guest.queue_patience = limit
		_panel.refresh()
		assert_eq(_bar().max_value, 1.0)
		assert_eq(_bar().value, 0.0)
		assert_eq(guest.queue_patience, limit)
	guest.state = CustomerAgent.State.ORDERING
	guest.food_patience = 100
	guest._food_wait = 200
	_panel.refresh()
	assert_eq(_bar().value, 0.0)
	assert_eq(guest._food_wait, 200)
	guest.state = CustomerAgent.State.WAITING_FOOD
	guest.order = null
	_panel.refresh()
	assert_eq(_label("Why").text, "Waiting for food")
	assert_null(guest.order)


func test_item_name_station_and_named_or_missing_reservation_holders() -> void:
	var staff: StaffAgent = _staff()
	var guest: CustomerAgent = _guest()
	guest.display_name = "Mia"
	var item: PlacedItem = _item()
	if item == null:
		return
	assert_true(item.reserve(item.work_cells[0], staff.id))
	assert_true(item.reserve(item.seat_cells[0], guest.id))
	_panel.show_item(item.id)
	assert_eq(_panel.selected_agent_id, -1)
	assert_eq(_panel.selected_item_id, item.id)
	assert_eq(_label("Title").text, "Prep counter #%d" % item.id)
	assert_eq(_label("Details").text, "Station: Prep counter")
	var text: String = _label("Reservations").text
	assert_true(text.contains("Work (3, 2): Ada (Cook #%d)" % staff.id))
	assert_true(text.contains("Work (4, 3): Free"))
	assert_true(text.contains("Seat (3, 4): Mia (Guest #%d)" % guest.id))
	assert_true(item.release(item.seat_cells[0], guest.id))
	assert_true(item.reserve(item.seat_cells[0], 77))
	_panel.refresh()
	assert_true(_label("Reservations").text.contains("Seat (3, 4): Agent #77 (not present)"))
	assert_false(_label("Why").visible)
	assert_false(_control("Patience").visible)


func test_missing_selections_and_world_rebinding_clear_once() -> void:
	var staff: StaffAgent = _staff()
	_panel.show_agent(staff.id)
	_panel.bind_world(_world)
	assert_eq(_panel.selected_agent_id, staff.id, "same-world binding keeps selection")
	assert_eq(_clears, 0)
	_world.remove_agent(staff)
	_panel.refresh()
	assert_false(_panel.visible)
	assert_eq(_panel.selected_agent_id, -1)
	assert_eq(_clears, 1)
	_panel.refresh()
	_panel.clear()
	assert_eq(_clears, 1, "already clear is idempotent")
	var item: PlacedItem = _item()
	if item == null:
		return
	_panel.show_item(item.id)
	assert_true(_world.grid.remove(item.id))
	_panel.refresh()
	assert_false(_panel.visible)
	assert_eq(_panel.selected_item_id, -1)
	assert_eq(_clears, 2)
	staff = _staff()
	_panel.show_agent(staff.id)
	var replacement: SimWorld = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	replacement.add_agent(StaffAgent.new())
	_panel.bind_world(replacement)
	assert_false(_panel.visible)
	assert_eq(_panel.selected_agent_id, -1, "new worlds never inherit a reused id")
	assert_eq(_clears, 3)
	_panel.show_agent(1)
	assert_true(_panel.visible)
	_panel.bind_world(null)
	assert_false(_panel.visible)
	assert_eq(_clears, 4)


func test_inspecting_refreshing_and_clearing_leave_sim_snapshots_unchanged() -> void:
	var staff: StaffAgent = _staff()
	var guest: CustomerAgent = _guest()
	var item: PlacedItem = _item()
	if item == null:
		return
	var task: SimTask = SimTask.new(&"cook", &"cook", "Prepare soup")
	task.steps.append(TaskStep.go_to_item(item.id, "Collecting ingredients"))
	_world.board.post(task, _world.now)
	assert_true(_world.board.claim(task, staff.id, _world.now))
	staff.task = task
	assert_true(item.reserve(item.work_cells[0], staff.id))
	assert_true(item.reserve(item.seat_cells[0], guest.id))
	guest._queue_wait = 17
	_world.log_event("A fixture event")
	var before: Dictionary = _snapshot(staff, guest, item, task)
	for _iteration: int in range(3):
		_panel.show_agent(staff.id)
		_panel.refresh()
		_panel.show_agent(guest.id)
		_panel.refresh()
		_panel.show_item(item.id)
		_panel.refresh()
		_panel.clear()
		_panel.bind_world(_world)
	assert_eq(_snapshot(staff, guest, item, task), before)


func _staff() -> StaffAgent:
	var staff: StaffAgent = StaffAgent.new(&"cook", 4)
	staff.display_name = "Ada"
	staff.cell = Vector2i(1, 1)
	_world.add_agent(staff)
	return staff


func _guest() -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 233
	var guest: CustomerAgent = CustomerAgent.new(_restaurant, random)
	guest.cell = Vector2i(1, 2)
	guest.state = CustomerAgent.State.QUEUED
	guest.order = Order.new()
	guest.order.recipe_id = &"tomato_soup"
	_world.add_agent(guest)
	return guest


func _item() -> PlacedItem:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"prep_counter"
	definition.display_name = "Prep counter"
	definition.category = ItemDef.Category.STATION
	definition.station_type = &"prep_counter"
	definition.work_cells = [Vector2i(0, -1), Vector2i(1, 0)]
	definition.seat_cells = [Vector2i(0, 1)]
	var item: PlacedItem = _world.grid.place_def(definition, Vector2i(3, 3))
	assert_not_null(item)
	return item


func _snapshot(staff: StaffAgent, guest: CustomerAgent, item: PlacedItem, task: SimTask) -> Dictionary:
	var reservations: Array[int] = []
	for cell: Vector2i in item.work_cells + item.seat_cells:
		reservations.append(item.reserved_by(cell))
	var steps: Array[Dictionary] = []
	for step: TaskStep in task.steps:
		steps.append({"kind": step.kind, "item_id": step.item_id, "use_seat": step.use_seat,
			"work_cell_index": step.work_cell_index, "cell": step.cell,
			"ticks": step.ticks, "label": step.label, "on_done": step.on_done})
	var definition: ItemDef = item.def as ItemDef
	return {
		"clock": _world.clock.to_dict(), "now": _world.now,
		"agents": _world.agents.duplicate(), "log": _world.event_log.duplicate(),
		"staff": [staff.id, staff.role, staff.display_name, staff.cell, staff.path.duplicate(),
			staff.path_index, staff.move_progress, staff.needs_repath, staff.last_progress_tick,
			staff.skills.duplicate(), staff.priorities.duplicate(), staff.task, staff.step_index,
			staff.work_left, staff._step_started, staff._held_item_id, staff._held_cell,
			staff._repaths, staff._waiting_for, staff._goal],
		"guest": [guest.id, guest.role, guest.display_name, guest.cell, guest.path.duplicate(),
			guest.path_index, guest.move_progress, guest.needs_repath, guest.last_progress_tick,
			guest.state, guest.queue_patience, guest.food_patience, guest.eat_ticks,
			guest.table_item_id, guest.seat_cell, guest.leave_reason, guest.paid,
			guest.departure_recorded, guest._queue_wait, guest._food_wait, guest._walk_wait,
			guest._eating, guest._exit_unreachable, guest._ordering_block_logged,
			guest.rng.seed, guest.rng.state, guest._goal],
		"order": [guest.order.state, guest.order.recipe_id, guest.order.price,
			guest.order.customer_id, guest.order.table_item_id, guest.order.seat_cell],
		"item": [item.id, item.origin, item.quarter_turns, item.solid, item.removed,
			item.cells.duplicate(), item.work_cells.duplicate(), item.seat_cells.duplicate(), reservations],
		"definition": [definition.id, definition.display_name, definition.category,
			definition.footprint, definition.solid, definition.station_type,
			definition.work_cells.duplicate(), definition.seat_cells.duplicate()],
		"task": [task.id, task.state, task.claimed_by, task.posted_tick, task.claimed_tick,
			task.label, task.priority, task.timeout_ticks, task.drops, task.payload.duplicate(true), steps],
		"open": _world.board.open_tasks(), "claimed": _world.board.claimed_tasks(),
	}


func _control(path: String) -> Control:
	return _panel.get_node("Panel/Rows/" + path) as Control


func _label(path: String) -> Label:
	return _control(path) as Label


func _bar() -> ProgressBar:
	return _control("Patience/PatienceBar") as ProgressBar


func _record_clear() -> void:
	_clears += 1
