extends TestCase
## Source-level scene tests; live layout/readability still needs rendered review.

const SCENE: PackedScene = preload("res://src/ui/debug_overlay.tscn")

var _overlay: DebugOverlay
var _world: SimWorld
var _host: Control


func before_each() -> void:
	_overlay = SCENE.instantiate() as DebugOverlay
	_world = SimWorld.new(SimGrid.new(Vector2i(4, 4)))


func after_each() -> void:
	_overlay.free()
	if is_instance_valid(_host):
		_host.free()
	_host = null
	_world = null


func test_default_hidden_empty_world_shared_theme_and_mouse_passthrough() -> void:
	assert_false(_overlay.visible)
	assert_false(_overlay.is_enabled())
	_overlay.bind_world(_world)
	_overlay.refresh()
	assert_eq(_label("Tasks").text, "No active tasks")
	assert_eq(_label("Log").text, "No events yet")
	assert_eq(_overlay.theme, load("res://src/ui/theme/main_theme.tres"))
	assert_almost_eq(_overlay.anchor_right, 1.0)
	assert_almost_eq(_overlay.anchor_bottom, 1.0)
	assert_eq(_overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE, "fullscreen space passes world input through")
	var panel: Control = _overlay.get_node("Panel") as Control
	var scroll: ScrollContainer = _overlay.get_node("Panel/Margin/Scroll") as ScrollContainer
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(panel.mouse_force_pass_scroll_events)
	assert_eq(scroll.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(scroll.mouse_force_pass_scroll_events)
	_assert_mouse_ignored(scroll.get_node("Content"))
	_overlay.set_enabled(true)
	_overlay.set_enabled(true)
	assert_true(_overlay.is_enabled())
	assert_true(_overlay.visible)
	_overlay.set_enabled(false)
	assert_false(_overlay.visible)
	_overlay.bind_world(null)
	assert_eq(_label("Tasks").text, "No world attached")


func test_busy_world_tasks_are_sorted_together_with_claimant_and_posted_age() -> void:
	var first: SimTask = SimTask.new(&"cook", &"cook", "Cook burger")
	var second: SimTask = SimTask.new(&"bus_table", &"server", "Clear table")
	_world.board.post(first, 2)
	_world.board.post(second, 10)
	assert_true(_world.board.claim(first, 7, 20))
	_world.now = 30
	_overlay.bind_world(_world)
	assert_eq(_label("Tasks").text, "#1 Cook burger | claimed | claimant #7 | age 28 ticks\n#2 Clear table | open | claimant - | age 20 ticks")
	_world.now = 35
	_overlay.refresh()
	assert_true(_label("Tasks").text.contains("age 33 ticks"))
	_world.board.cancel(first)
	_world.board.cancel(second)
	_overlay.refresh()
	assert_eq(_label("Tasks").text, "No active tasks")


func test_last_fifteen_events_keep_chronological_order() -> void:
	for index: int in range(20):
		_world.log_event("Event %02d" % index)
	_overlay.bind_world(_world)
	var rows: PackedStringArray = _label("Log").text.split("\n")
	assert_eq(rows.size(), 15)
	assert_eq(rows[0], "[0] Event 05")
	assert_eq(rows[14], "[0] Event 19")


func test_overflow_keeps_all_diagnostics_in_a_bounded_scrollable_panel() -> void:
	for index: int in range(80):
		_world.board.post(SimTask.new(&"cook", &"cook", "Overflow task %02d" % index), 0)
	var long_detail: String = " A worker is waiting for a station while another job holds its work cell.".repeat(6)
	for index: int in range(15):
		_world.log_event("Overflow event %02d%s" % [index, long_detail])
	var log_before: PackedStringArray = _world.event_log.duplicate()
	_host = Control.new()
	_host.size = Vector2(1600.0, 900.0)
	(Engine.get_main_loop() as SceneTree).root.add_child(_host)
	_host.add_child(_overlay)
	_overlay.bind_world(_world)
	_overlay.set_enabled(true)
	var panel: Control = _overlay.get_node("Panel") as Control
	var scroll: ScrollContainer = _overlay.get_node("Panel/Margin/Scroll") as ScrollContainer
	var content: Control = scroll.get_node("Content") as Control
	# The synchronous runner never delivers deferred container sorting. Deliver
	# the normal layout notification in parent-first passes, including wrapping.
	for height: int in [900, 640]:
		_host.size = Vector2(1600.0, float(height))
		_overlay.size = _host.size
		for _pass_index: int in range(3):
			_sort_containers(_overlay)
		assert_almost_eq(panel.position.y, 112.0)
		assert_almost_eq(panel.size.y, float(height) - 124.0)
		assert_almost_eq(panel.get_rect().end.y, float(height) - 12.0)
		assert_true(scroll.size.y < panel.size.y)
		assert_true(content.get_combined_minimum_size().y > scroll.size.y, "overflow does not enlarge the panel")
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		assert_true(bar.visible, "overflow exposes a usable scrollbar")
		assert_true(bar.max_value > bar.page)
		scroll.scroll_vertical = ceili(bar.max_value)
		_sort_containers(_overlay)
		assert_true(scroll.scroll_vertical > 0, "the diagnostic content can be scrolled")
		assert_true(content.position.y < 0.0)
	assert_eq(_label("Tasks").text.split("\n").size(), 80)
	assert_true(_label("Tasks").text.contains("Overflow task 00"))
	assert_true(_label("Tasks").text.contains("Overflow task 79"))
	assert_eq(_label("Log").text.split("\n").size(), 15)
	assert_true(_label("Log").text.ends_with("Overflow event 14%s" % long_detail))
	assert_eq(_world.now, 0)
	assert_eq(_world.board.active_count(), 80)
	assert_eq(_world.event_log, log_before)


func test_rates_measure_world_ticks_over_elapsed_windows_and_reach_zero_paused() -> void:
	_world.now = 100
	_overlay.bind_world(_world)
	_overlay.sample_rates(5.0, 60.0)
	_world.now = 125
	_overlay.sample_rates(5.5, 58.0)
	assert_almost_eq(_overlay.ticks_per_second, 0.0, 0.0001, "no completed sample window yet")
	_world.now = 140
	_overlay.sample_rates(7.0, 55.0)
	assert_almost_eq(_overlay.ticks_per_second, 20.0)
	assert_almost_eq(_overlay.frames_per_second, 55.0)
	assert_eq(_world.clock.tick, 0, "rate measurement uses world.now rather than clock.tick")
	_overlay.sample_rates(8.25, 61.0)
	assert_almost_eq(_overlay.ticks_per_second, 0.0, 0.0001, "paused worlds reach zero")
	assert_true(_label("Rates").text.contains("0.0 ticks/s"))


func test_rebind_and_backward_time_or_ticks_restart_the_rate_baseline() -> void:
	_overlay.bind_world(_world)
	_overlay.sample_rates(10.0, 60.0)
	_world.now = 20
	_overlay.sample_rates(11.0, 60.0)
	assert_almost_eq(_overlay.ticks_per_second, 20.0)
	_overlay.bind_world(_world)
	assert_almost_eq(_overlay.ticks_per_second, 0.0)
	_overlay.sample_rates(20.0, 60.0)
	_world.now = 4
	_overlay.sample_rates(21.0, 60.0)
	assert_almost_eq(_overlay.ticks_per_second, 0.0)
	_world.now = 14
	_overlay.sample_rates(22.0, 60.0)
	assert_almost_eq(_overlay.ticks_per_second, 10.0)
	_overlay.sample_rates(2.0, 60.0)
	assert_almost_eq(_overlay.ticks_per_second, 0.0)
	_world.now = 19
	_overlay.sample_rates(3.0, 60.0)
	assert_almost_eq(_overlay.ticks_per_second, 5.0)
	_overlay.bind_world(SimWorld.new(SimGrid.new()))
	assert_almost_eq(_overlay.frames_per_second, 0.0)
	_overlay.sample_rates(4.0, 60.0)
	_overlay.sample_rates(5.0, 60.0)
	assert_almost_eq(_overlay.ticks_per_second, 0.0)


func test_refresh_toggle_and_sampling_leave_the_simulation_unchanged() -> void:
	var task: SimTask = SimTask.new(&"cook", &"cook", "Cook soup")
	_world.board.post(task, 0)
	_world.board.claim(task, 9, 0)
	_world.log_event("Waiting for stove")
	var clock_before: Dictionary = _world.clock.to_dict().duplicate(true)
	var log_before: PackedStringArray = _world.event_log.duplicate()
	_overlay.bind_world(_world)
	_overlay.set_enabled(true)
	_overlay.sample_rates(0.0, 60.0)
	_overlay.sample_rates(1.5, 59.0)
	_overlay.refresh()
	_overlay.set_enabled(false)
	assert_eq(_world.now, 0)
	assert_eq(_world.clock.to_dict(), clock_before)
	assert_eq(_world.event_log, log_before)
	assert_eq(_world.board.active_count(), 1)
	assert_eq(task.state, SimTask.State.CLAIMED)
	assert_eq(task.claimed_by, 9)
	assert_eq(task.claimed_tick, 0)
	assert_eq(task.drops, 0)
	_overlay.bind_world(null)
	_overlay.sample_rates(2.0, 60.0)
	assert_almost_eq(_overlay.ticks_per_second, 0.0)


func _label(name: String) -> Label:
	return _overlay.get_node("Panel/Margin/Scroll/Content/" + name) as Label


func _sort_containers(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children():
		_sort_containers(child)


func _assert_mouse_ignored(node: Node) -> void:
	if node is Control:
		assert_eq((node as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, str(node.name))
	for child: Node in node.get_children():
		_assert_mouse_ignored(child)
