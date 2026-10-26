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


## Starts a fresh service with a newly drawn first arrival gap.
func reset() -> void:
	_remaining = _gap()


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
	if not entries.is_empty():
		var kind: CustomerType = null
		if sim.customer_types != null:
			kind = CustomerTypePicker.choose(sim.customer_types, sim.customer_level,
				sim.review_book.average(), rng)
		if sim.customer_types == null or kind != null:
			var entry: Vector2i = entries[rng.randi_range(0, entries.size() - 1)]
			var count: int = kind.draw_party_size(rng) if kind != null else 1
			if count == 1:
				var customer_rng: RandomNumberGenerator = RandomNumberGenerator.new()
				customer_rng.seed = rng.randi()
				sim.add_customer(entry, customer_rng, kind)
			else:
				var randoms: Array[RandomNumberGenerator] = []
				for index: int in count:
					var customer_rng: RandomNumberGenerator = RandomNumberGenerator.new()
					customer_rng.seed = rng.randi()
					randoms.append(customer_rng)
				sim.add_party(entry, randoms, kind)
	_remaining = _gap()


func _gap() -> int:
	return rng.randi_range(maxi(1, min_gap), maxi(maxi(1, min_gap), max_gap))
