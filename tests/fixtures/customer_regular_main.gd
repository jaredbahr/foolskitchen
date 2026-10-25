extends RefCounted
## Frozen compatibility oracle for issue #111. Only methods changed by customer
## types are copied from official main 34f8fde46e55a0b0af96a5b15bbc9698254ab206.
## The golden runs still use the real world, staff, pathfinding and Kitchen.
## Do not refresh these methods from feature code: they represent pre-type main.

class MainSpawner extends CustomerSpawner:
	func _init(random: RandomNumberGenerator) -> void:
		super(random)
	func advance(sim: RestaurantSim) -> void:
		if sim.world.clock.phase != SimClock.Phase.OPEN:
			return
		if _remaining < 0:
			reset()
		_remaining -= 1
		if _remaining > 0:
			return
		var entries: Array[Vector2i] = sim.world.grid.entries()
		if not entries.is_empty():
			var entry: Vector2i = entries[rng.randi_range(0, entries.size() - 1)]
			var customer_rng: RandomNumberGenerator = RandomNumberGenerator.new()
			customer_rng.seed = rng.randi()
			sim.add_customer(entry, customer_rng)
		_remaining = _gap()

class MainCustomer extends CustomerAgent:
	func _init(restaurant: RestaurantSim, random: RandomNumberGenerator) -> void:
		super(restaurant, random)

	func review_visit(standard_price: int, dirt_fraction: float = 0.0) -> ReviewVisit:
		var visit: ReviewVisit = ReviewVisit.new()
		visit.served = paid
		visit.closing = leave_reason == &"closing"
		visit.queue_wait_fraction = float(maxi(0, _queue_wait)) / float(maxi(1, queue_patience))
		visit.food_wait_fraction = float(maxi(0, _food_wait)) / float(maxi(1, food_patience))
		if order != null and standard_price > 0:
			visit.price_ratio = float(order.price) / float(standard_price)
		visit.dirt_fraction = dirt_fraction
		visit.vibe_review_bonus = vibe_review_bonus
		return visit

	func _take_order(server: SimAgent) -> bool:
		var sim: RestaurantSim = _restaurant.get_ref() as RestaurantSim
		if sim == null:
			return false
		# A dropped task can replay its callback; a ticket is only placed once.
		if order != null:
			return order.state != Order.State.CANCELLED
		if state != State.ORDERING:
			return false
		if sim.menu.is_empty():
			return false
		var recipe: RecipeDef = sim.menu[rng.randi_range(0, sim.menu.size() - 1)]
		var price: int = sim.price_of(recipe)
		var chance: float = sim.price_walkout_chance(recipe)
		# Standard/cheaper prices preserve the existing guest stream exactly.
		if chance > 0.0 and rng.randf() < chance:
			_leave(sim.world, sim, &"too_expensive")
			return true
		order = Order.new()
		order.customer_id = id
		order.table_item_id = table_item_id
		order.seat_cell = seat_cell
		order.recipe_id = recipe.id
		order.price = price
		# Apply once, after the ticket replay guard, while food patience still matters.
		if server is StaffAgent:
			food_patience = roundi(food_patience * (server as StaffAgent).food_patience_multiplier)
		state = State.WAITING_FOOD
		sim.orders.place(order, sim.world.now)
		return true

class MainRestaurant extends RestaurantSim:
	func add_customer(entry: Vector2i, random: RandomNumberGenerator, _kind: CustomerType = null) -> CustomerAgent:
		var customer: CustomerAgent = MainCustomer.new(self, random)
		customer.cell = entry
		# Only a real service arrival can dirty the floor or consume its stream.
		if cleanliness != null and world.clock.phase == SimClock.Phase.OPEN:
			customer.arrival_dirt_fraction = cleanliness.dirt_fraction()
			var patience_scale: float = cleanliness.patience_multiplier()
			customer.queue_patience = maxi(1, roundi(float(customer.queue_patience) * patience_scale))
			customer.food_patience = maxi(1, roundi(float(customer.food_patience) * patience_scale))
			var spot: Vector2i = cleanliness.try_spawn_on_arrival(entry)
			if spot != SimGrid.NO_CELL and clean_tasks != null:
				clean_tasks.sync_spots()
		if world.clock.phase == SimClock.Phase.OPEN:
			customer.queue_patience = _vibe_patience(customer.queue_patience, _vibe_result.patience_multiplier)
			customer.food_patience = _vibe_patience(customer.food_patience, _vibe_result.patience_multiplier)
			customer.vibe_review_bonus = _vibe_result.raw_review_bonus
			if _vibe_result.score > 0.0 and not _vibe_result.active_theme.is_empty():
				customer.vibe_theme_label = _vibe_result.theme_label
		world.add_agent(customer)
		world.log_event("Guest #%d arrived" % customer.id)
		customer_arrived.emit(customer)
		return customer


	## Current guests in stable agent-id order.

	func price_walkout_chance(recipe: RecipeDef, _budget_multiplier: float = 1.0) -> float:
		if recipe == null or recipe.standard_price <= 0 or pricing_tuning == null:
			return 0.0
		var ratio: float = float(price_of(recipe)) / float(recipe.standard_price)
		if ratio <= 1.0:
			return 0.0
		var sensitivity: float = pricing_tuning.price_sensitivity
		var maximum: float = pricing_tuning.max_price_walkout
		if not is_finite(sensitivity) or not is_finite(maximum):
			return 0.0
		return clampf((ratio - 1.0) * maxf(sensitivity, 0.0), 0.0, clampf(maximum, 0.0, 1.0))


	## Adds a guest using an independent random stream (also useful for scenarios).

class MainBook extends ReputationBook:
	func record_visit(visit: ReviewVisit, tuning: ReviewTuning, quotes: ReviewQuotes,
			random: RandomNumberGenerator, vibe_tuning: VibeTuning = VIBE_TUNING) -> Dictionary:
		if visit == null or visit.closing or tuning == null or not tuning.is_valid() \
				or quotes == null or random == null:
			return {}
		if random.randf() >= tuning.review_chance:
			return {}
		var before: float = average()
		var stars: int = _legacy_score(visit, tuning, vibe_tuning)
		var cause: StringName = _legacy_cause(visit, tuning, vibe_tuning)
		var quote: String = quotes.pick(cause, random, _quotes_used_today)
		if not quote.is_empty():
			_quotes_used_today[quote] = true
		_scores.append(stars)
		if _scores.size() > WINDOW:
			_scores.pop_front()
		return {"stars": stars, "cause": cause, "quote": quote,
			"before": before, "after": average()}


	## Four penalties remain authored in reviews.tres. The optional raw ambience
	## term is bounded by vibe.tres before rounding; it is not fractional-star storage.
	## The final rating remains in the physical one-to-five-star range.
	## Unserved guests always score one star; a closing guest is not scored.

	static func _legacy_score(visit: ReviewVisit, tuning: ReviewTuning, vibe_tuning: VibeTuning = VIBE_TUNING) -> int:
		if visit == null or visit.closing or tuning == null or not tuning.is_valid():
			return 0
		if not visit.served:
			return 1
		var penalty: float = _unit(visit.queue_wait_fraction) * tuning.queue_wait_weight \
			+ _unit(visit.food_wait_fraction) * tuning.food_wait_weight \
			+ _unit(visit.price_ratio - 1.0) * tuning.overprice_weight \
			+ _unit(visit.dirt_fraction) * tuning.dirt_weight
		var maximum: float = vibe_tuning.max_review_bonus if vibe_tuning != null and vibe_tuning.is_valid() else 0.0
		var vibe_bonus: float = clampf(visit.vibe_review_bonus, 0.0, maximum) if is_finite(visit.vibe_review_bonus) else 0.0
		# Keep the physical star domain before integer conversion, even for large
		# finite authored caps. Ordinary rounding and final-score quote policy agree.
		return roundi(clampf(5.0 - penalty + vibe_bonus, 1.0, 5.0))


	## High ratings and visits without a substantial single complaint get a
	## positive quote. For lower ratings, stable ties keep this explicit order.

	static func _legacy_cause(visit: ReviewVisit, tuning: ReviewTuning, vibe_tuning: VibeTuning = VIBE_TUNING) -> StringName:
		if visit == null or visit.closing or tuning == null or not tuning.is_valid():
			return &""
		if not visit.served:
			return &"never_served"
		var causes: Array[StringName] = [&"slow_seating", &"slow_food", &"too_pricey", &"dirty_floor"]
		var penalties: Array[float] = [
			_unit(visit.queue_wait_fraction) * tuning.queue_wait_weight,
			_unit(visit.food_wait_fraction) * tuning.food_wait_weight,
			_unit(visit.price_ratio - 1.0) * tuning.overprice_weight,
			_unit(visit.dirt_fraction) * tuning.dirt_weight,
		]
		var best: int = -1
		var largest: float = 0.0
		for index: int in range(penalties.size()):
			if penalties[index] > largest:
				largest = penalties[index]
				best = index
		if _legacy_score(visit, tuning, vibe_tuning) >= 4 or largest < tuning.positive_penalty_threshold:
			return &"great_value" if is_finite(visit.price_ratio) and visit.price_ratio < 0.9 else &"lovely_place"
		if best >= 0:
			return causes[best]
		return &"great_value" if is_finite(visit.price_ratio) and visit.price_ratio < 0.9 else &"lovely_place"
