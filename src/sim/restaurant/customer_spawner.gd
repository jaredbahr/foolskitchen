class_name CustomerSpawner
extends RefCounted
## Seeded arrivals count down only while the service is open.

var min_gap: int = 150
var max_gap: int = 400
var rng: RandomNumberGenerator
var _remaining: int = -1
## Fractional countdown work accumulated only during a planned rush.
var _rush_extra_ticks: float = 0.0


## Uses only the injected random stream.
func _init(random: RandomNumberGenerator) -> void:
	rng = random


## Starts a fresh service with a newly drawn first arrival gap, scaled by the
## opening arrival rate (FK-083; exactly the drawn gap at 1.0).
func reset(rate: float = 1.0) -> void:
	_remaining = scaled_gap(_gap(), rate)
	_rush_extra_ticks = 0.0


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
	if not countdown_tick(sim.rush_multiplier()):
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
				count = maxi(1, mini(drawn_count, DiningSeats.largest_usable_capacity(
					sim.world.grid, entry, sim.world.weather.kind)))
			# Retain every private-seed draw, including clamped-away members. Layout
			# edits must not shift the next arrival's type, gap or private streams.
			var randoms: Array[RandomNumberGenerator] = []
			for index: int in drawn_count:
				var customer_rng: RandomNumberGenerator = RandomNumberGenerator.new()
				customer_rng.seed = rng.randi()
				if index < count:
					randoms.append(customer_rng)
			if count == 1:
				var guest: CustomerAgent = sim.add_visitor(entry, randoms[0], kind, visit)
				sim.try_disguise_critic(guest)
				if guest != null:
					sim.record_rush_arrivals([guest.id])
			elif count > 1:
				var party: Party = sim.add_party(entry, randoms, kind, visit)
				if party != null:
					sim.record_rush_arrivals(party.member_ids)
			arrived = count
	# Headcount-neutral: a party of N waits N drawn gaps (one draw, scaled), so
	# groups bring the same guests per hour as singles did.
	# Preserve overrun from the faster tick countdown across this arrival. No
	# draw or spacing changes: only the remaining time on the already-drawn next
	# gap is reduced, and one party per tick remains the existing contract.
	reset_after_arrival(sim.arrival_rate(), arrived)


## Advance the already-drawn integer gap once, with fractional rush progress.
## A factor of exactly 1 leaves the legacy integer path unchanged.
func countdown_tick(rush_factor: float) -> bool:
	if is_finite(rush_factor) and rush_factor > 1.0:
		_rush_extra_ticks += rush_factor - 1.0
		var whole_extra: int = floori(_rush_extra_ticks)
		_rush_extra_ticks -= float(whole_extra)
		_remaining -= 1 + whole_extra
	else:
		_rush_extra_ticks = 0.0
		_remaining -= 1
	return _remaining <= 0


## Draw exactly one normal next gap. Accelerated work is saturated at one
## arrival per tick and never leaves a negative value for the reset sentinel.
func reset_after_arrival(rate: float, arrived: int) -> void:
	var next_gap: int = scaled_gap(_gap(), rate) * maxi(1, arrived)
	_remaining = maxi(0, next_gap + _remaining)


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
