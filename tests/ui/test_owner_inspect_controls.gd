extends TestCase
## Request-only owner controls. Real input routing, factory creation and
## checkpoint persistence remain session integration work.

const PANEL: PackedScene = preload("res://src/ui/inspect_panel.tscn")

var _panel: InspectPanel
var _world: SimWorld
var _owner: OwnerAgent
var _restaurant: RestaurantSim
var _requests: Array[StringName] = []
var _viewport: SubViewport


func before_each() -> void:
	_world = SimWorld.new(SimGrid.new(Vector2i(10, 10)))
	_restaurant = RestaurantSim.new()
	_restaurant.world = _world
	_owner = OwnerAgent.new(Vector2i(1, 1))
	_world.add_agent(_owner)
	_panel = PANEL.instantiate() as InspectPanel
	_panel.owner_mode_requested.connect(_record_request)
	_panel.bind_world(_world)


func after_each() -> void:
	_panel.free()
	if _viewport != null:
		_viewport.free()
	for agent: SimAgent in _world.agents.duplicate():
		_world.remove_agent(agent)


func test_controls_are_hidden_themed_and_mouse_contained_before_ready() -> void:
	assert_false(_panel.is_node_ready())
	assert_false(_panel.visible)
	assert_false(_modes().visible)
	assert_eq(_modes().columns, 2)
	assert_eq(_modes().mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var frame: Control = _panel.get_node("Panel") as Control
	assert_eq(frame.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(frame.mouse_force_pass_scroll_events)
	for mode: StringName in OwnerAgent.MODES:
		var button: Button = _button(mode)
		assert_eq(button.text, String(mode).capitalize())
		assert_true(button.disabled)
		assert_true(button.toggle_mode)
		assert_false(button.button_pressed)
		assert_eq(button.focus_mode, Control.FOCUS_NONE)
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)
		assert_false(button.mouse_force_pass_scroll_events)
		# Detached Controls have not resolved their effective theme cache yet.
		# Check assignment here, then native lookup after tree entry below.
		assert_eq(button.theme, _panel.theme)
		assert_false(button.has_theme_stylebox_override("pressed"))
	assert_true(_button(&"kitchen").tooltip_text.contains("(K)"))
	assert_true(_button(&"floor").tooltip_text.contains("(F)"))
	assert_true(_button(&"help").tooltip_text.contains("(H)"))
	assert_true(_button(&"rest").tooltip_text.contains("(R)"))
	assert_eq(_requests.size(), 0)


func test_selected_owner_modes_highlight_committed_state_and_keep_readouts() -> void:
	_panel.show_agent(_owner.id)
	assert_true(_panel.visible)
	assert_true(_modes().visible)
	assert_eq(_panel.selected_agent_id, _owner.id)
	assert_eq(_panel.selected_item_id, -1)
	assert_eq((_panel.get_node("Panel/Rows/Why") as Label).text, _owner.why())
	assert_true((_panel.get_node("Panel/Rows/Details") as Label).text.contains("Task: Standing back"))
	for committed: StringName in OwnerAgent.MODES:
		assert_true(_owner.assign_mode(committed))
		_panel.refresh()
		for mode: StringName in OwnerAgent.MODES:
			assert_false(_button(mode).disabled)
			assert_eq(_button(mode).button_pressed, mode == committed)
		assert_eq((_panel.get_node("Panel/Rows/Why") as Label).text, _owner.why())
	assert_eq(_requests.size(), 0)
	assert_eq(_world.now, 0)


func test_buttons_emit_only_primitive_requests_and_restore_committed_highlight() -> void:
	_panel.show_agent(_owner.id)
	var before: Dictionary = _owner.priorities.duplicate()
	for mode: StringName in [&"kitchen", &"floor", &"help"]:
		_button(mode).pressed.emit()
	assert_eq(_requests, [&"kitchen", &"floor", &"help"] as Array[StringName])
	assert_eq(_owner.current_mode(), &"rest")
	assert_eq(_owner.priorities, before)
	assert_true(_button(&"rest").button_pressed)
	assert_false(_button(&"help").button_pressed)
	_button(&"rest").pressed.emit()
	assert_eq(_requests.size(), 3, "already committed mode is idempotent")
	assert_true(_owner.assign_mode(&"kitchen"))
	_panel.refresh()
	_button(&"rest").pressed.emit()
	assert_eq(_requests, [&"kitchen", &"floor", &"help", &"rest"] as Array[StringName])
	assert_eq(_owner.current_mode(), &"kitchen", "view never applies a request")
	assert_true(_button(&"kitchen").button_pressed)
	assert_eq(_panel.selected_agent_id, _owner.id)
	assert_eq(_panel.selected_item_id, -1)
	assert_eq(_world.now, 0)


func test_controls_only_show_for_owner_agent_not_other_staff_guests_or_items() -> void:
	_panel.show_agent(_owner.id)
	var staff: StaffAgent = StaffAgent.new(&"cook", 4)
	_world.add_agent(staff)
	_panel.show_agent(staff.id)
	assert_false(_modes().visible)
	assert_true((_panel.get_node("Panel/Rows/Details") as Label).text.contains("Cook skill: 4/5"))
	_button(&"kitchen").pressed.emit()
	var named_owner: StaffAgent = StaffAgent.new(&"owner", 3)
	_world.add_agent(named_owner)
	_panel.show_agent(named_owner.id)
	assert_false(_modes().visible, "a role string alone does not make an assignable owner")
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	var guest: CustomerAgent = CustomerAgent.new(_restaurant, random)
	guest.state = CustomerAgent.State.QUEUED
	_world.add_agent(guest)
	_panel.show_agent(guest.id)
	assert_false(_modes().visible)
	assert_true((_panel.get_node("Panel/Rows/Patience") as Control).visible)
	assert_eq((_panel.get_node("Panel/Rows/Why") as Label).text, guest.why())
	var item: PlacedItem = _station()
	_panel.show_item(item.id)
	assert_false(_modes().visible)
	assert_eq(_panel.selected_agent_id, -1)
	assert_eq(_panel.selected_item_id, item.id)
	assert_true((_panel.get_node("Panel/Rows/Reservations") as Label).visible)
	assert_false((_panel.get_node("Panel/Rows/Why") as Label).visible)
	for mode: StringName in OwnerAgent.MODES:
		assert_true(_button(mode).disabled)
		_button(mode).pressed.emit()
	assert_eq(_requests.size(), 0)


func test_removed_selection_and_world_rebinding_cannot_emit_stale_owner_request() -> void:
	_panel.show_agent(_owner.id)
	_world.remove_agent(_owner)
	_button(&"floor").pressed.emit()
	assert_eq(_requests.size(), 0)
	assert_false(_panel.visible)
	assert_false(_modes().visible)
	assert_eq(_panel.selected_agent_id, -1)
	var replacement: SimWorld = SimWorld.new(SimGrid.new(Vector2i(10, 10)))
	var new_owner: OwnerAgent = OwnerAgent.new(Vector2i(2, 2))
	replacement.add_agent(new_owner)
	assert_eq(new_owner.id, _owner.id, "fixture reuses an id in another world")
	_panel.bind_world(replacement)
	_button(&"floor").pressed.emit()
	assert_eq(_requests.size(), 0)
	_panel.show_agent(new_owner.id)
	assert_true(_modes().visible)
	assert_true(_button(&"rest").button_pressed)
	_panel.bind_world(null)
	assert_false(_panel.visible)
	assert_false(_modes().visible)
	_button(&"help").pressed.emit()
	assert_eq(_requests.size(), 0)


func test_hidden_panel_and_invalid_mode_requests_are_ignored() -> void:
	_panel.show_agent(_owner.id)
	_panel._on_owner_mode_pressed(&"invalid")
	assert_eq(_requests.size(), 0)
	_panel.hide()
	_button(&"floor").pressed.emit()
	assert_false(_panel.visible, "a hidden button signal cannot reopen the inspector")
	assert_eq(_requests.size(), 0)
	_panel.clear()
	_panel._on_owner_mode_pressed(&"kitchen")
	assert_eq(_requests.size(), 0)
	assert_eq(_owner.current_mode(), &"rest")


func test_refresh_binding_and_ready_are_idempotent_without_duplicate_callbacks() -> void:
	_panel.show_agent(_owner.id)
	for repeat: int in 3:
		_panel.refresh()
		_panel.bind_world(_world)
		_panel._ready()
	for mode: StringName in OwnerAgent.MODES:
		assert_eq(_button(mode).pressed.get_connections().size(), 1)
	_button(&"floor").pressed.emit()
	assert_eq(_requests, [&"floor"] as Array[StringName])
	assert_eq(_owner.current_mode(), &"rest")
	assert_true(_button(&"rest").button_pressed)


func test_native_mouse_press_survives_frame_refresh_until_release() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(800, 700)
	_viewport.handle_input_locally = true
	tree.root.add_child(_viewport)
	_viewport.add_child(_panel)
	_panel.show_agent(_owner.id)
	await tree.process_frame
	await tree.process_frame
	assert_true(_panel.is_node_ready())
	for mode: StringName in OwnerAgent.MODES:
		assert_eq(_button(mode).get_theme_stylebox("pressed"), _panel.theme.get_stylebox("pressed", "Button"))
		assert_false(_button(mode).has_theme_stylebox_override("pressed"))
	var button: Button = _button(&"kitchen")
	var center: Vector2 = button.get_global_rect().get_center()
	assert_true(button.is_visible_in_tree())
	assert_true(button.size.x > 0.0 and button.size.y > 0.0)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	_viewport.push_input(motion, true)
	_mouse_button(center, true)
	assert_eq(_requests.size(), 0, "normal buttons activate on release")
	_panel.refresh()
	await tree.process_frame
	_panel.refresh()
	_mouse_button(center, false)
	assert_eq(_requests, [&"kitchen"] as Array[StringName], "native press/refresh/release emits once")
	assert_eq(_owner.current_mode(), &"rest", "the presenter only requests a change")
	assert_true(_button(&"rest").button_pressed)


func _mouse_button(position: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	_viewport.push_input(event, true)


func test_owner_inspection_and_button_requests_do_not_change_real_held_work() -> void:
	var item: PlacedItem = _station()
	var work: SimTask = SimTask.new(&"cook", &"cook", "Real held work")
	work.steps.append(TaskStep.go_to_item(item.id, "walking to counter"))
	work.steps.append(TaskStep.work(300, "preparing food"))
	_world.board.post(work, _world.now)
	assert_true(_owner.assign_mode(&"kitchen"))
	for tick: int in 100:
		_world.advance()
		if _owner.task == work and _owner.step_index == 1:
			break
	assert_eq(item.reserved_by(item.work_cells[0]), _owner.id)
	assert_eq(_owner.task, work)
	var before: Dictionary = _snapshot(item, work)
	_panel.show_agent(_owner.id)
	for repeat: int in 3:
		_panel.refresh()
		_button(&"floor").pressed.emit()
		_button(&"rest").pressed.emit()
	assert_eq(_snapshot(item, work), before)
	assert_eq(_panel.selected_agent_id, _owner.id)
	assert_true(_button(&"kitchen").button_pressed)


func _modes() -> GridContainer:
	return _panel.get_node("Panel/Rows/OwnerModes") as GridContainer


func _button(mode: StringName) -> Button:
	return _modes().get_node(String(mode).capitalize()) as Button


func _station() -> PlacedItem:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"prep_counter"
	definition.display_name = "Prep counter"
	definition.category = ItemDef.Category.STATION
	definition.station_type = &"prep_counter"
	definition.work_cells = [Vector2i(0, -1)] as Array[Vector2i]
	return _world.grid.place_def(definition, Vector2i(4, 4))


func _snapshot(item: PlacedItem, work: SimTask) -> Dictionary:
	return {"clock": _world.clock.to_dict(), "tick": _world.now,
		"mode": _owner.current_mode(), "role": _owner.role,
		"skills": _owner.skills.duplicate(), "priorities": _owner.priorities.duplicate(),
		"cell": _owner.cell, "path": _owner.path.duplicate(),
		"path_index": _owner.path_index, "progress": _owner.move_progress,
		"task": _owner.task, "step": _owner.step_index, "work_left": _owner.work_left,
		"held_item": _owner._held_item_id, "held_cell": _owner._held_cell,
		"task_state": work.state, "claimant": work.claimed_by, "drops": work.drops,
		"payload": work.payload.duplicate(true), "holder": item.reserved_by(item.work_cells[0]),
		"open": _world.board.open_tasks(), "claimed": _world.board.claimed_tasks(),
		"log": _world.event_log.duplicate()}


func _record_request(mode: StringName) -> void:
	_requests.append(mode)
