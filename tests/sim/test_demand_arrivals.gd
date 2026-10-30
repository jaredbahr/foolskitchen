extends TestCase
## Demand changes draw probabilities, preserving private streams and real seats.

const TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const TABLE: ItemDef = preload("res://data/items/table_4.tres")
const AUTHORED: DemandTuning = preload("res://data/balance/demand.tres")


func test_neutral_demand_delegates_the_original_exact_range_fixed_and_locked_paths() -> void:
	for fixed: bool in [false, true]:
		var kind: CustomerType = TYPES.find_type(&"family").duplicate(true) as CustomerType
		kind.party_size_min = 2
		kind.party_size_max = 2 if fixed else 4
		kind.party_unlock_level = 4
		for level: int in [1, 4]:
			for factor: float in [0.54, 1.0]:
				var original: RandomNumberGenerator = _rng(519)
				var actual: RandomNumberGenerator = _rng(519)
				for draw: int in 40:
					assert_eq(kind.draw_party_size_for_demand(actual, level, factor, AUTHORED),
						kind.draw_party_size_at(original, level))
					assert_eq(actual.state, original.state, "neutral draw schedule remains exact")


func test_full_and_partial_growth_match_independent_literal_weight_bins() -> void:
	var kind: CustomerType = TYPES.find_type(&"regular").duplicate(true) as CustomerType
	kind.party_unlock_level = 1
	var seen: Dictionary = {}
	for factor: float in [2.0, 3.0, 100.0]:
		for seed_value: int in range(1, 257):
			var oracle: RandomNumberGenerator = _rng(seed_value)
			var actual: RandomNumberGenerator = _rng(seed_value)
			var blend: float = 0.5 if factor == 2.0 else 1.0
			var ticket: float = oracle.randf()
			# The full authored distribution sums to 3.35. At factor 2,
			# half remains the original uniform 1..2, half is the six bins.
			var expected: int = _literal_bin(ticket, blend)
			var size: int = kind.draw_party_size_for_demand(actual, 1, factor, AUTHORED)
			assert_eq(size, expected, "literal CDF seed %d factor %.1f" % [seed_value, factor])
			assert_eq(actual.state, oracle.state, "growth draws one ticket")
			seen[size] = true
	for size: int in range(1, 7):
		assert_true(seen.has(size), "the deterministic sample reaches all six size bins")


func test_growth_honors_authored_minimum_unlock_and_invalid_fallback_without_extra_draws() -> void:
	var kind: CustomerType = TYPES.find_type(&"family").duplicate(true) as CustomerType
	kind.party_unlock_level = 4
	for seed_value: int in range(1, 65):
		var locked: RandomNumberGenerator = _rng(seed_value)
		var before: int = locked.state
		assert_eq(kind.draw_party_size_for_demand(locked, 3, 3.0, AUTHORED), 1)
		assert_eq(locked.state, before)
		var random: RandomNumberGenerator = _rng(seed_value)
		var size: int = kind.draw_party_size_for_demand(random, 4, 3.0, AUTHORED)
		assert_true(size >= 2 and size <= 6)
	for factor: float in [NAN, INF, -1.0, 0.0]:
		var actual: RandomNumberGenerator = _rng(92)
		var original: RandomNumberGenerator = _rng(92)
		assert_eq(kind.draw_party_size_for_demand(actual, 4, factor, AUTHORED), kind.draw_party_size_at(original, 4))
		assert_eq(actual.state, original.state)
	var invalid: DemandTuning = AUTHORED.duplicate(true) as DemandTuning
	invalid.party_size_weights = PackedFloat32Array([0, 0, 0, 0, 0, 0])
	for tuning: DemandTuning in [null, invalid]:
		var actual: RandomNumberGenerator = _rng(93)
		var original: RandomNumberGenerator = _rng(93)
		assert_eq(kind.draw_party_size_for_demand(actual, 4, 3.0, tuning), kind.draw_party_size_at(original, 4))
		assert_eq(actual.state, original.state)


func test_live_factor_change_scales_arrival_rate_without_resetting_countdown_or_rng() -> void:
	var sim: RestaurantSim = _service(43)
	var countdown: int = sim.spawner._remaining
	var random_state: int = sim.rng.state
	assert_true(sim.set_demand_factor(2.0))
	assert_almost_eq(sim.arrival_rate(), 2.0)
	assert_eq(sim.spawner._remaining, countdown)
	assert_eq(sim.rng.state, random_state)
	for invalid: float in [0.0, -1.0, NAN, INF, 3.1]:
		assert_false(sim.set_demand_factor(invalid))
	assert_almost_eq(sim.arrival_rate(), 2.0)
	assert_eq(sim.spawner._remaining, countdown)
	assert_eq(sim.rng.state, random_state)


func test_growth_spawner_clamps_after_all_private_seeds_and_uses_actual_headcount_gap() -> void:
	for capacity: int in [0, 2, 4]:
		var sim: RestaurantSim = _service(71)
		if capacity > 0:
			var seats: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0)]
			if capacity == 4:
				seats.append_array([Vector2i(0, -1), Vector2i(0, 1)] as Array[Vector2i])
			assert_not_null(sim.world.grid.place(Vector2i.ONE, Vector2i(5, 5), 0, true, [], seats))
		var catalogue: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
		var kind: CustomerType = TYPES.find_type(&"family").duplicate(true) as CustomerType
		# Deterministic six-member raw arrivals isolate capacity and private seeds.
		kind.party_size_min = 6
		kind.party_size_max = 6
		catalogue.types = [kind]
		assert_true(sim.configure_customer_types(catalogue, 4))
		assert_true(sim.set_demand_factor(3.0))
		var oracle: RandomNumberGenerator = _rng(71)
		oracle.state = sim.rng.state
		CustomerTypePicker.choose(catalogue, 4, sim.review_book.average(), oracle)
		oracle.randi_range(0, 0)
		var private_seeds: Array[int] = []
		for member: int in 6:
			private_seeds.append(oracle.randi())
		var gap: int = oracle.randi_range(90, 90)
		sim.spawner._remaining = 1
		sim.spawner.advance(sim)
		var count: int = maxi(1, capacity)
		assert_eq(sim.customers().size(), count)
		assert_eq(sim.rng.state, oracle.state, "all six seeds retained even after a clamp")
		assert_eq(sim.spawner._remaining, roundi(float(gap) / 3.0) * count)
		for member: int in count:
			var guest: CustomerAgent = sim.customers()[member]
			assert_eq(guest.rng.seed, private_seeds[member])
			if count == 1:
				assert_null(guest.party)
			else:
				assert_eq(guest.party, sim.customers()[0].party)
				assert_eq(guest.party.size(), count)


func test_grown_party_keeps_one_physical_table_distinct_seats_and_real_order_identity() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var original: ShopLayout = load("res://data/layouts/tier1_hole_in_the_wall.tres") as ShopLayout
	var layout: ShopLayout = ShopLayout.new()
	layout.id = &"demand_party_service"
	layout.display_name = "Demand party service"
	layout.rows = original.rows.duplicate()
	layout.staff_spawns = original.staff_spawns.duplicate()
	for placement: ShopPlacement in original.placements:
		if content.item(placement.item_id).category != ItemDef.Category.TABLE:
			layout.placements.append(placement.duplicate(true) as ShopPlacement)
	var placement: ShopPlacement = ShopPlacement.new()
	placement.item_id = &"table_4"
	placement.origin = Vector2i(3, 6)
	layout.placements.append(placement)
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(layout, content, 81, errors, stock)
	assert_eq(errors, [] as Array[String])
	sim.menu = [content.recipe(&"burger")] as Array[RecipeDef]
	sim.configure_demand(AUTHORED)
	var catalogue: CustomerTypeCatalogue = CustomerTypeCatalogue.new()
	var kind: CustomerType = TYPES.find_type(&"family").duplicate(true) as CustomerType
	kind.party_size_min = 6
	kind.party_size_max = 6
	catalogue.types = [kind]
	assert_true(sim.configure_customer_types(catalogue, 4))
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.start_day()
	assert_true(sim.set_demand_factor(3.0))
	assert_true(sim.world.clock.start_service())
	sim.spawner._remaining = 1
	sim.spawner.advance(sim)
	var guests: Array[CustomerAgent] = sim.customers()
	assert_eq(guests.size(), 4)
	for guest: CustomerAgent in guests:
		guest.queue_patience = 2000
		guest.food_patience = 2000
	for tick: int in 1200:
		sim.advance()
		var all_ordered: bool = true
		for guest: CustomerAgent in guests:
			all_ordered = all_ordered and guest.order != null
		if all_ordered:
			break
	var party: Party = guests[0].party
	assert_not_null(party)
	var table: PlacedItem = sim.world.grid.item(party.table_item_id)
	assert_not_null(table)
	if table == null:
		return
	var occupied: Dictionary = {}
	var order_ids: Dictionary = {}
	for guest: CustomerAgent in guests:
		assert_eq(guest.party, party)
		assert_eq(guest.table_item_id, table.id)
		assert_true(table.seat_cells.has(guest.seat_cell))
		assert_eq(table.reserved_by(guest.seat_cell), guest.id)
		assert_false(occupied.has(guest.seat_cell))
		occupied[guest.seat_cell] = guest.id
		assert_not_null(guest.order, "actual staff and kitchen placed each member's ticket")
		if guest.order == null:
			continue
		assert_eq(guest.order.customer_id, guest.id)
		assert_eq(guest.order.table_item_id, party.table_item_id)
		assert_eq(guest.order.seat_cell, guest.seat_cell)
		assert_eq(guest.order.recipe_id, &"burger")
		assert_false(order_ids.has(guest.order.id))
		order_ids[guest.order.id] = true
	assert_eq(occupied.size(), 4)
	assert_eq(order_ids.size(), 4)


func _literal_bin(ticket: float, blend: float) -> int:
	var literal: Array[float] = [1.0, 0.8, 0.6, 0.5, 0.3, 0.15]
	var cumulative: float = 0.0
	for index: int in 6:
		cumulative += (1.0 - blend) * (0.5 if index < 2 else 0.0) + blend * literal[index] / 3.35
		if ticket < cumulative:
			return index + 1
	return 6


func _service(seed_value: int) -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.ENTRY)
	sim.world = SimWorld.new(grid)
	sim.rng.seed = seed_value
	sim.spawner = CustomerSpawner.new(sim.rng)
	sim.spawner.min_gap = 90
	sim.spawner.max_gap = 90
	sim.configure_demand(AUTHORED)
	sim.start_day()
	assert_true(sim.world.clock.start_service())
	return sim


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random
