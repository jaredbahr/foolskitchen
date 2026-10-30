extends TestCase
## Ordered contextual hints are optional, one-shot and JSON-safe.

const Guide := preload("res://src/ui/hints.gd")


func test_day_one_and_two_hints_fire_in_order_only_once() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	assert_eq(guide.observe(context), Guide.Step.MENU)
	assert_eq(guide.observe(context), Guide.Step.MENU, "an active bubble stays the same")
	guide.acknowledge()
	assert_eq(guide.observe(context), -1, "Got it does not force the Menu to open")
	context.menu_open = true
	assert_eq(guide.observe(context), -1)
	context.menu_open = false
	assert_eq(guide.observe(context), Guide.Step.STOCK)
	guide.acknowledge()
	assert_eq(guide.observe(context), Guide.Step.BUILD)
	guide.acknowledge()
	assert_eq(guide.observe(context), Guide.Step.OPEN)
	guide.acknowledge()
	context.phase = SimClock.Phase.OPEN
	assert_eq(guide.observe(context), -1)
	context.queued_guest = true
	assert_eq(guide.observe(context), Guide.Step.QUEUE)
	guide.acknowledge()
	assert_eq(guide.observe(context), -1, "the same queue does not repeat its hint")
	context.dirty_table = true
	assert_eq(guide.observe(context), Guide.Step.DIRTY)
	guide.acknowledge()
	assert_eq(guide.observe(context), -1, "the same dirty table does not repeat its hint")
	context.phase = SimClock.Phase.CLOSED
	context.report_visible = true
	assert_eq(guide.observe(context), Guide.Step.REPORT)
	guide.acknowledge()
	assert_eq(guide.observe(context), -1)
	context.day = 2
	context.phase = SimClock.Phase.MORNING
	context.report_visible = false
	assert_eq(guide.observe(context), Guide.Step.DAY_TWO)
	guide.acknowledge()
	assert_eq(guide.next_hint, Guide.Step.COMPLETE)
	assert_eq(guide.observe(context), -1)
	context.day = 3
	assert_eq(guide.observe(context), -1)


func test_acknowledging_menu_waits_for_an_actual_menu_visit_and_close() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	assert_eq(guide.observe(context), Guide.Step.MENU)
	guide.acknowledge()
	for observation: int in 3:
		assert_eq(guide.observe(context), -1)
	assert_false(guide.menu_finished)
	context.menu_open = true
	assert_eq(guide.observe(context), -1, "Stock cannot cover the open Menu")
	context.menu_open = false
	assert_eq(guide.observe(context), Guide.Step.STOCK)
	assert_true(guide.menu_finished)


func test_hidden_targets_are_skipped_and_never_reappear() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	context.targets_visible[Guide.Step.MENU] = false
	context.targets_visible[Guide.Step.STOCK] = false
	assert_eq(guide.observe(context), Guide.Step.BUILD)
	guide.acknowledge()
	context.targets_visible[Guide.Step.MENU] = true
	context.targets_visible[Guide.Step.STOCK] = true
	assert_eq(guide.observe(context), Guide.Step.OPEN)


func test_hiding_the_active_target_clears_it_and_moves_on() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	assert_eq(guide.observe(context), Guide.Step.MENU)
	context.targets_visible[Guide.Step.MENU] = false
	assert_eq(guide.observe(context), Guide.Step.STOCK)
	context.targets_visible[Guide.Step.MENU] = true
	assert_ne(guide.observe(context), Guide.Step.MENU)


func test_service_events_seen_during_an_earlier_hint_keep_the_required_order() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	for step: int in [Guide.Step.MENU, Guide.Step.STOCK, Guide.Step.BUILD, Guide.Step.OPEN]:
		context.targets_visible[step] = false
	assert_eq(guide.observe(context), -1)
	context.phase = SimClock.Phase.OPEN
	context.dirty_table = true
	assert_eq(guide.observe(context), -1, "a dirty table waits for the first queued guest")
	context.dirty_table = false
	context.queued_guest = true
	assert_eq(guide.observe(context), Guide.Step.QUEUE)
	guide.acknowledge()
	context.queued_guest = false
	assert_eq(guide.observe(context), Guide.Step.DIRTY,
		"the first dirty table is remembered while the earlier hint is pending")


func test_day_two_discards_unfinished_day_one_and_later_days_stay_quiet() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	assert_eq(guide.observe(context), Guide.Step.MENU)
	context.day = 2
	assert_eq(guide.observe(context), Guide.Step.DAY_TWO)
	guide.acknowledge()
	assert_eq(guide.observe(context), -1)
	var missed: Guide = Guide.new()
	context.day = 3
	assert_eq(missed.observe(context), -1)
	assert_eq(missed.next_hint, Guide.Step.COMPLETE)


func test_skip_stops_active_and_all_future_hints_until_restarted() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	guide.observe(context)
	guide.skip()
	assert_eq(guide.active_hint, -1)
	assert_eq(guide.next_hint, Guide.Step.COMPLETE)
	context.queued_guest = true
	context.dirty_table = true
	context.report_visible = true
	for day: int in [1, 2, 3]:
		context.day = day
		assert_eq(guide.observe(context), -1)
	guide.restart()
	context.day = 1
	assert_eq(guide.observe(context), Guide.Step.MENU)


func test_json_round_trip_keeps_progress_and_menu_visit_before_closing() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	guide.observe(context)
	guide.acknowledge()
	context.menu_open = true
	guide.observe(context)
	var snapshot: Dictionary = guide.capture()
	var restored: Guide = Guide.new()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	assert_true(restored.restore(parsed))
	assert_eq(restored.capture(), snapshot)
	context.menu_open = false
	assert_eq(restored.observe(context), Guide.Step.STOCK)
	restored.acknowledge()
	assert_eq(restored.observe(context), Guide.Step.BUILD)
	assert_eq(guide.next_hint, Guide.Step.STOCK, "restoring another guide does not alias it")


func test_json_round_trip_preserves_an_active_hint_and_skipped_completion() -> void:
	var guide: Guide = Guide.new()
	var context: Guide.Context = _context()
	guide.observe(context)
	var restored: Guide = Guide.new()
	assert_true(restored.restore(JSON.parse_string(JSON.stringify(guide.capture()))))
	assert_eq(restored.observe(context), Guide.Step.MENU)
	restored.skip()
	assert_true(guide.restore(JSON.parse_string(JSON.stringify(restored.capture()))))
	assert_eq(guide.observe(context), -1)


func test_malformed_restore_is_rejected_without_changing_existing_progress() -> void:
	var guide: Guide = Guide.new()
	guide.observe(_context())
	var before: Dictionary = guide.capture()
	for field: String in ["next_hint", "active_hint", "first_day"]:
		for invalid: Variant in ["1", true, 0.5, 1e30, INF, NAN, {}, []]:
			var malformed: Dictionary = before.duplicate(true)
			malformed[field] = invalid
			assert_false(guide.restore(malformed), field)
			assert_eq(guide.capture(), before, field)
	for field: String in ["menu_finished", "menu_seen", "queued_seen", "dirty_seen", "report_seen"]:
		var malformed: Dictionary = before.duplicate(true)
		malformed[field] = 1
		assert_false(guide.restore(malformed), field)
		assert_eq(guide.capture(), before, field)
	for bounds: Dictionary in [{"next_hint": -1}, {"next_hint": Guide.Step.COMPLETE + 1},
		{"active_hint": -2}, {"active_hint": Guide.Step.COMPLETE}, {"first_day": 0}]:
		var malformed: Dictionary = before.duplicate(true)
		malformed.merge(bounds, true)
		assert_false(guide.restore(malformed))
		assert_eq(guide.capture(), before)
	assert_false(guide.restore({}), "an incomplete section cannot reset the guide")
	assert_eq(guide.capture(), before)
	var mismatched: Dictionary = before.duplicate(true)
	mismatched["active_hint"] = Guide.Step.BUILD
	assert_false(guide.restore(mismatched), "active hints cannot be ahead of their progress")
	assert_eq(guide.capture(), before)


func test_replay_can_start_from_a_later_morning_and_get_its_following_day_hint() -> void:
	var guide: Guide = Guide.new()
	guide.restart(7)
	var context: Guide.Context = _context()
	context.day = 7
	assert_eq(guide.observe(context), Guide.Step.MENU)
	context.day = 8
	assert_eq(guide.observe(context), Guide.Step.DAY_TWO)


func test_required_hint_copy_uses_player_facing_words() -> void:
	assert_eq(Guide.text_for(Guide.Step.MENU), "Plan today's dishes and prices")
	assert_eq(Guide.text_for(Guide.Step.STOCK), "Check your fridge and shelves; order what you need")
	assert_eq(Guide.text_for(Guide.Step.BUILD), "Move or buy furniture; paint rooms in Build")
	assert_eq(Guide.text_for(Guide.Step.DAY_TWO), "Hire and plan in the mornings. You're on your own now")
	for step: int in range(Guide.Step.COMPLETE):
		assert_false(Guide.text_for(step).is_empty())
		assert_false(Guide.text_for(step).contains("Mark your kitchen"))


func _context() -> Guide.Context:
	var context: Guide.Context = Guide.Context.new()
	context.day = 1
	context.phase = SimClock.Phase.MORNING
	for step: int in range(Guide.Step.COMPLETE):
		context.targets_visible[step] = true
	return context
