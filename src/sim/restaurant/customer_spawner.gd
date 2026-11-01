class_name CustomerSpawner
extends RefCounted
## Seeded arrivals count down only while the service is open.

var min_gap: int = 150
var max_gap: int = 400
var rng: RandomNumberGenerator
var _remaining: int = -1


## Uses only the injected random stream.
func _init(random: RandomNumberGenerator) -> void:
	rng = random


## Starts a fresh service with a newly drawn first arrival gap, scaled by the
## opening arrival rate (FK-083; exactly the drawn gap at 1.0).
func reset(rate: float = 1.0) -> void:
	_remaining = scaled_gap(_gap(), rate)


## A drawn gap at an arrival rate. Rate 1.0 returns it unchanged, so default
## play keeps its exact gaps; busier hours shorten it, quiet ones stretch it.
static func scaled_gap(gap: int, rate: float) -> int:
	if rate == 1.0 or not is_finite(rate) or rate <= 0.0:
		return gap
	return maxi(1, roundi(float(gap) / rate))


## Creates at most one party, and never outside OPEN or without a street entry.
func advance(sim: RestaurantSim) -> void:
	if sim.world.clock.phase != SimClock.Phase.OPEN:
		return
	if _remaining < 0:
		reset()
	_remaining -= 1
	if _remaining > 0:
		return
	var entries: Array[Vector2i] = sim.world.grid.entries()
	var arrived: int = 1
	if not entries.is_empty():
		var kind: CustomerType = null
		var vibe: VibeModel.Result = sim.vibe_result
		if sim.customer_types != null:
			kind = CustomerTypePicker.choose(sim.customer_types, sim.customer_level,
				sim.review_book.average(), rng, vibe.active_theme, vibe.arrival_theme_strength)
		if sim.customer_types == null or kind != null:
			# Food-only menus have one kind and draw nothing here (FK-083).
			var visit: StringName = choose_visit(sim.visit_kinds(), kind, sim, rng)
			var entry: Vector2i = entries[rng.randi_range(0, entries.size() - 1)]
			# A type whose groups are still locked draws exactly what a single
			# guest draws: no size draw and one private seed.
			var drawn_count: int = kind.draw_party_size_for_demand(rng, sim.customer_level,
				sim.demand_factor, sim.demand_tuning) if kind != null else 1
			var count: int = drawn_count
			if drawn_count > 1:
				# Parties clamp after every draw to the largest usable table, but
				# never below one: with no usable table a single guest still
				# arrives and is counted as "no table", as any single would be.
				count = maxi(1, mini(drawn_count, DiningSeats.largest_usable_capacity(sim.world.grid, entry)))
			# Retain every private-seed draw, including clamped-away members. Layout
			# edits must not shift the next arrival's type, gap or private streams.
			var randoms: Array[RandomNumberGenerator] = []
			for index: int in drawn_count:
				var customer_rng: RandomNumberGenerator = RandomNumberGenerator.new()
				customer_rng.seed = rng.randi()
				if index < count:
					randoms.append(customer_rng)
			if count == 1:
				sim.add_visitor(entry, randoms[0], kind, visit)
			elif count > 1:
				sim.add_party(entry, randoms, kind, visit)
			arrived = count
	# Headcount-neutral: a party of N waits N drawn gaps (one draw, scaled), so
	# groups bring the same guests per hour as singles did.
	_remaining = scaled_gap(_gap(), sim.arrival_rate()) * maxi(1, arrived)


## What an arriving guest came for. One available kind draws nothing; with
## several, one draw weighs each kind's hourly weight by the type's liking.
static func choose_visit(kinds: Array[StringName], kind: CustomerType, sim: RestaurantSim,
		random: RandomNumberGenerator) -> StringName:
	if kinds.size() <= 1:
		return kinds[0] if not kinds.is_empty() else RecipeDef.FOOD
	var minute: int = sim.world.clock.display_minutes()
	var weights: Array[float] = []
	var total: float = 0.0
	for visit: StringName in kinds:
		var weight: float = sim.visit_tuning.weight(visit, minute) if sim.visit_tuning != null else 0.0
		if kind != null:
			weight *= kind.visit_weight(visit)
		weights.append(maxf(weight, 0.0))
		total += maxf(weight, 0.0)
	if total <= 0.0 or not is_finite(total):
		return kinds[0]
	var ticket: float = random.randf() * total
	for index: int in kinds.size():
		ticket -= weights[index]
		if ticket < 0.0:
			return kinds[index]
	return kinds.back()


func _gap() -> int:
	return rng.randi_range(maxi(1, min_gap), maxi(maxi(1, min_gap), max_gap))
