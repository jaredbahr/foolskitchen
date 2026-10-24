extends TestCase
## Mood is a query of existing patience, never an additional guest timer.

var _sim: RestaurantSim
var _guest: CustomerAgent


func before_each() -> void:
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(SimGrid.new(Vector2i(4, 4)))
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 5137
	_guest = CustomerAgent.new(_sim, random)
	_guest.queue_patience = 100
	_guest.food_patience = 100
	_guest.order = Order.new()
	_guest.order.recipe_id = &"tomato_soup"
	_sim.world.add_agent(_guest)


func test_each_state_uses_only_its_specified_budget_and_walking_is_content() -> void:
	_guest._queue_wait = 94
	_guest._food_wait = 88
	_guest._walk_wait = 999
	for state: int in range(CustomerAgent.State.LEFT + 1):
		_guest.state = state as CustomerAgent.State
		if state == CustomerAgent.State.QUEUED:
			assert_almost_eq(_guest.mood(), 0.06)
			assert_eq(_guest.mood_band(), CustomerAgent.MoodBand.ABOUT_TO_LEAVE)
		elif state == CustomerAgent.State.ORDERING or state == CustomerAgent.State.WAITING_FOOD:
			assert_almost_eq(_guest.mood(), 0.12)
			assert_eq(_guest.mood_band(), CustomerAgent.MoodBand.ABOUT_TO_LEAVE)
		else:
			assert_eq(_guest.mood(), 1.0, "state %d has no active mood budget" % state)
			assert_eq(_guest.mood_band(), CustomerAgent.MoodBand.HAPPY)


func test_all_waiting_states_keep_the_exact_inclusive_band_edges() -> void:
	var elapsed: Array[int] = [0, 40, 41, 65, 66, 85, 86, 100]
	var fractions: Array[float] = [1.0, 0.6, 0.59, 0.35, 0.34, 0.15, 0.14, 0.0]
	var bands: Array[int] = [0, 0, 1, 1, 2, 2, 3, 3]
	assert_eq(CustomerAgent.MOOD_HAPPY_THRESHOLD, 0.6)
	assert_eq(CustomerAgent.MOOD_WAITING_THRESHOLD, 0.35)
	assert_eq(CustomerAgent.MOOD_IMPATIENT_THRESHOLD, 0.15)
	for state: int in [CustomerAgent.State.QUEUED, CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD]:
		_guest.state = state as CustomerAgent.State
		for index: int in range(elapsed.size()):
			_guest._queue_wait = elapsed[index]
			_guest._food_wait = elapsed[index]
			assert_almost_eq(_guest.mood(), fractions[index])
			assert_eq(_guest.mood_band(), bands[index], "state %d elapsed %d" % [state, elapsed[index]])


func test_zero_negative_and_exhausted_budgets_are_safe_and_clamped() -> void:
	for state: int in [CustomerAgent.State.QUEUED, CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD]:
		_guest.state = state as CustomerAgent.State
		for budget: int in [0, -1]:
			_guest.queue_patience = budget
			_guest.food_patience = budget
			_guest._queue_wait = 0
			_guest._food_wait = 0
			assert_eq(_guest.mood(), 0.0)
			assert_eq(_guest.mood_band(), CustomerAgent.MoodBand.ABOUT_TO_LEAVE)
		_guest.queue_patience = 100
		_guest.food_patience = 100
		for elapsed: int in [-9223372036854775807 - 1, -10, 0, 200, 9223372036854775807]:
			_guest._queue_wait = elapsed
			_guest._food_wait = elapsed
			assert_eq(_guest.mood(), 1.0 if elapsed <= 0 else 0.0)
	_guest.state = CustomerAgent.State.WALKING_TO_SEAT
	_guest.queue_patience = 0
	_guest.food_patience = 0
	assert_eq(_guest.mood(), 1.0)
	_guest.state = CustomerAgent.State.QUEUED
	_guest.queue_patience = 9223372036854775807
	_guest._queue_wait = -9223372036854775807 - 1
	assert_eq(_guest.mood(), 1.0, "clamp before subtracting extreme counters")
	_guest._queue_wait = 9223372036854775807
	assert_eq(_guest.mood(), 0.0)


func test_waiting_why_keeps_the_activity_and_adds_each_band_without_new_reasons() -> void:
	var elapsed: Array[int] = [0, 50, 80, 90]
	var suffixes: Array[String] = ["(content)", "(waiting patiently)", "(getting impatient)", "(about to leave)"]
	for state: int in [CustomerAgent.State.QUEUED, CustomerAgent.State.ORDERING, CustomerAgent.State.WAITING_FOOD]:
		_guest.state = state as CustomerAgent.State
		for index: int in range(elapsed.size()):
			_guest._queue_wait = elapsed[index]
			_guest._food_wait = elapsed[index]
			var why: String = _guest.why()
			assert_true(why.ends_with(suffixes[index]))
			match state:
				CustomerAgent.State.QUEUED:
					assert_true(why.begins_with("Waiting by the door for a free table"))
				CustomerAgent.State.ORDERING:
					assert_true(why.begins_with("Waiting for a server to take my order"))
				CustomerAgent.State.WAITING_FOOD:
					assert_true(why.begins_with("Waiting for food (tomato_soup),"))
					assert_true(why.contains("%ds of patience left" % ceili(float(100 - elapsed[index]) / SimClock.TICKS_PER_SECOND)))
	_guest.state = CustomerAgent.State.WALKING_TO_SEAT
	assert_eq(_guest.why(), "Walking to my seat")
	_guest.state = CustomerAgent.State.EATING
	assert_eq(_guest.why(), "Enjoying my meal")
	_guest.state = CustomerAgent.State.LEAVING
	_guest.leave_reason = &"waited_too_long"
	assert_eq(_guest.why(), "Leaving: waited too long")


func test_mood_band_and_why_queries_leave_all_guest_counters_and_rng_unchanged() -> void:
	_guest._queue_wait = 66
	_guest._food_wait = 80
	_guest._walk_wait = 27
	_guest.path = [Vector2i(1, 1), Vector2i(2, 1)]
	_guest.path_index = 1
	_guest.move_progress = 0.4
	for state: int in range(CustomerAgent.State.LEFT + 1):
		_guest.state = state as CustomerAgent.State
		var before: Dictionary = _snapshot()
		for _repeat: int in range(3):
			_guest.mood()
			_guest.mood_band()
			_guest.why()
		assert_eq(_snapshot(), before)


func _snapshot() -> Dictionary:
	return {
		"state": _guest.state, "queue": [_guest.queue_patience, _guest._queue_wait],
		"food": [_guest.food_patience, _guest._food_wait], "walk": _guest._walk_wait,
		"eat": [_guest.eat_ticks, _guest._eating], "exit": _guest._exit_unreachable,
		"seat": [_guest.table_item_id, _guest.seat_cell], "reason": _guest.leave_reason,
		"paid": _guest.paid, "departure": _guest.departure_recorded,
		"ordering_block_logged": _guest._ordering_block_logged,
		"path": _guest.path.duplicate(), "path_index": _guest.path_index,
		"move": _guest.move_progress, "cell": _guest.cell, "goal": _guest._goal,
		"repath": _guest.needs_repath, "progress": _guest.last_progress_tick,
		"rng": [_guest.rng.seed, _guest.rng.state], "restaurant_rng": [_sim.rng.seed, _sim.rng.state],
		"world": _sim.world.now, "clock": _sim.world.clock.to_dict(),
		"tasks": [_sim.world.board.active_count(), _guest._task],
		"order": [_guest.order.state, _guest.order.recipe_id, _guest.order.price],
		"served": _sim.served_today, "lost": _sim.lost_today,
		"reasons": _sim.leave_reasons_today.duplicate(), "log": _sim.world.event_log.duplicate(),
	}
