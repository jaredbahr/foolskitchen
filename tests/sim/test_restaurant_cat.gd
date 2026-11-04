extends TestCase
## The restaurant cat (#119): a sim-side pet that is never a person.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: CatTuning = preload("res://data/balance/cat.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const REVIEWS: ReviewTuning = preload("res://data/balance/reviews.tres")


func after_each() -> void:
	GameState.new_run(1)


# --- Data and the offer ---------------------------------------------------------

func test_data_unlocks_at_level_four_for_forty_dollars_and_two_a_day() -> void:
	assert_true(TUNING.is_valid())
	assert_eq(TUNING.unlock_level, 4)
	assert_eq(TUNING.adoption_price, 40)
	assert_eq(TUNING.daily_food_cost, 2)
	assert_eq(TUNING.default_name, "Biscuit")
	assert_eq(TUNING.charm_radius, 2)
	assert_almost_eq(TUNING.charm_patience_bonus, 0.10)
	assert_eq(TUNING.pet_radius, 1)


func test_offer_is_one_time_morning_only_and_needs_level_and_cash() -> void:
	var cat: RestaurantCat = RestaurantCat.new(TUNING)
	assert_eq(cat.cat_name, "Biscuit")
	assert_false(cat.offered(3, SimClock.Phase.MORNING))
	assert_true(cat.offered(4, SimClock.Phase.MORNING))
	assert_false(cat.offered(4, SimClock.Phase.OPEN))
	assert_eq(cat.refusal(3, SimClock.Phase.MORNING, 1000), "Unlocks at owner level 4")
	assert_eq(cat.refusal(4, SimClock.Phase.OPEN, 1000), "Adopt a cat in the morning")
	assert_eq(cat.refusal(4, SimClock.Phase.MORNING, 39), "Not enough cash to adopt a cat")
	assert_eq(cat.refusal(4, SimClock.Phase.MORNING, 40), "")
	assert_true(cat.adopt(_sim().world.grid))
	assert_false(cat.offered(9, SimClock.Phase.MORNING), "adopted: the offer never returns")
	assert_false(cat.adopt(_sim().world.grid), "adopting twice does nothing")
	assert_eq(cat.refusal(9, SimClock.Phase.MORNING, 1000), "You already have a cat")


# --- Where the cat goes ---------------------------------------------------------

func test_cat_never_leaves_guest_rooms_or_stands_on_furniture() -> void:
	var sim: RestaurantSim = _sim()
	var grid: SimGrid = sim.world.grid
	var rooms: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in grid.cells():
		if grid.terrain(cell) == SimGrid.Terrain.FLOOR and cell.x >= 9:
			rooms[cell] = SimGrid.Room.KITCHEN
		elif grid.terrain(cell) == SimGrid.Terrain.FLOOR and cell.y >= 10 and cell.x <= 3:
			rooms[cell] = SimGrid.Room.RESTROOM
	assert_true(grid.set_rooms(rooms))
	GameState.new_run(3)
	sim.cat.use_rng(GameState.rng(&"cat"))
	sim.cat.adopt(grid)
	var seen: Dictionary[Vector2i, bool] = {}
	var moved: bool = false
	var last: Vector2i = sim.cat.cell
	for tick: int in 12000:
		sim.cat.advance(grid, [])
		var cell: Vector2i = sim.cat.cell
		seen[cell] = true
		moved = moved or cell != last
		last = cell
		assert_eq(grid.terrain(cell), SimGrid.Terrain.FLOOR, "tick %d" % tick)
		assert_true(grid.is_walkable(cell), "tick %d: walkable floor" % tick)
		assert_null(grid.item_on_layer(cell, ItemDef.PlacementLayer.NORMAL), "tick %d: never on furniture" % tick)
		var room: int = grid.room(cell)
		assert_true(room == SimGrid.Room.DINING or room == SimGrid.Room.RESTROOM, "tick %d: guest rooms only" % tick)
		assert_false(grid.is_back_door(cell))
		if not grid.is_guest_walkable(cell) or not (room == SimGrid.Room.DINING or room == SimGrid.Room.RESTROOM):
			break
	assert_true(moved, "the cat wanders")
	assert_true(seen.size() > 8, "it covers a good part of the dining room (%d cells)" % seen.size())


func test_cat_steps_only_between_neighbouring_open_cells() -> void:
	var sim: RestaurantSim = _sim()
	var grid: SimGrid = sim.world.grid
	GameState.new_run(8)
	sim.cat.use_rng(GameState.rng(&"cat"))
	sim.cat.adopt(grid)
	var previous: Vector2i = sim.cat.cell
	for tick: int in 8000:
		sim.cat.advance(grid, [])
		var cell: Vector2i = sim.cat.cell
		if cell != previous:
			assert_true(grid.guest_neighbours(previous).has(cell), "%s -> %s is a legal step" % [previous, cell])
		previous = cell


func test_same_seed_gives_the_same_cat_path() -> void:
	var first: Array[Vector2i] = _path(41, 20000)
	var again: Array[Vector2i] = _path(41, 20000)
	var other: Array[Vector2i] = _path(42, 20000)
	assert_eq(first, again)
	assert_ne(first, other)
	assert_true(first.size() > 60, "a real walk: %d steps" % first.size())


func test_the_cat_draws_only_from_its_own_named_stream() -> void:
	GameState.new_run(5)
	var customers_before: int = GameState.rng(&"customers").state
	var sim: RestaurantSim = _sim()
	sim.cat.use_rng(GameState.rng(&"cat"))
	sim.cat.adopt(sim.world.grid)
	var cat_before: int = GameState.rng(&"cat").state
	for tick: int in 3000:
		sim.cat.advance(sim.world.grid, [])
	assert_ne(GameState.rng(&"cat").state, cat_before, "the cat uses its stream")
	assert_eq(GameState.rng(&"customers").state, customers_before, "and nobody else's")


func test_morning_start_is_the_bed_spot_and_draws_nothing() -> void:
	GameState.new_run(6)
	var sim: RestaurantSim = _sim()
	sim.cat.use_rng(GameState.rng(&"cat"))
	sim.cat.adopt(sim.world.grid)
	var stream: int = GameState.rng(&"cat").state
	var bed: Vector2i = sim.cat.bed()
	assert_ne(bed, SimGrid.NO_CELL)
	assert_eq(sim.cat.cell, bed)
	assert_eq(sim.cat.state, RestaurantCat.State.NAPPING)
	for tick: int in 4000:
		sim.cat.advance(sim.world.grid, [])
	assert_ne(GameState.rng(&"cat").state, stream, "the day's walking drew numbers")
	var before: Dictionary = {"state": GameState.rng(&"cat").state, "seed": GameState.rng(&"cat").seed}
	sim.start_day()
	sim.cat.begin_day(sim.world.grid)
	assert_eq(sim.cat.cell, bed, "every morning begins on the bed")
	assert_eq(sim.cat.state, RestaurantCat.State.NAPPING)
	assert_eq(GameState.rng(&"cat").state, before["state"], "beginning the day draws nothing")
	assert_eq(GameState.rng(&"cat").seed, before["seed"])


func test_naps_next_to_a_window_else_next_to_a_wall() -> void:
	var grid: SimGrid = _box(8, 6)
	var cat: RestaurantCat = RestaurantCat.new(TUNING)
	var walled: Array[Vector2i] = cat.nap_spots(grid)
	assert_false(cat.naps_in_sun(grid), "no window: wall spots")
	assert_true(walled.has(Vector2i(1, 1)))
	assert_true(walled.has(Vector2i(6, 4)))
	assert_false(walled.has(Vector2i(3, 2)), "the middle of the room is not next to a wall")
	assert_true(grid.set_segment(Vector3i(3, 2, SimGrid.EDGE_NORTH), SimGrid.Segment.WINDOW))
	var sunny: Array[Vector2i] = cat.nap_spots(grid)
	assert_true(cat.naps_in_sun(grid))
	assert_eq(sunny, [Vector2i(3, 1), Vector2i(3, 2)] as Array[Vector2i], "only the cells either side of the window")
	assert_eq(cat.bed_spot(grid), Vector2i(3, 1))


func test_a_napping_cat_sleeps_in_a_sunny_spot() -> void:
	var grid: SimGrid = _box(8, 6)
	assert_true(grid.set_segment(Vector3i(3, 2, SimGrid.EDGE_NORTH), SimGrid.Segment.WINDOW))
	var cat: RestaurantCat = RestaurantCat.new(TUNING, _rng(77))
	cat.adopt(grid)
	var slept_at: Dictionary[Vector2i, bool] = {}
	for tick: int in 20000:
		cat.advance(grid, [])
		if cat.state == RestaurantCat.State.NAPPING:
			slept_at[cat.cell] = true
	assert_eq(slept_at.keys().size(), 2)
	for cell: Vector2i in slept_at:
		assert_true(cell == Vector2i(3, 1) or cell == Vector2i(3, 2), "naps only beside the window, not at %s" % cell)


func test_a_build_edit_under_the_cat_sends_it_back_to_bed() -> void:
	var grid: SimGrid = _box(8, 6)
	var cat: RestaurantCat = RestaurantCat.new(TUNING, _rng(5))
	cat.adopt(grid)
	cat.cell = Vector2i(4, 3)
	cat.from_cell = cat.cell
	assert_true(grid.set_terrain(Vector2i(4, 3), SimGrid.Terrain.WALL))
	cat.layout_changed(grid)
	assert_true(cat.cell_ok(grid, cat.cell))
	assert_eq(cat.cell, cat.bed())


# --- Charm ----------------------------------------------------------------------

func test_patience_bonus_applies_only_within_range() -> void:
	var near: int = _queue_wait_after(200, 2)
	var far: int = _queue_wait_after(200, 3)
	assert_eq(far, 200, "outside the charm range waiting costs a tick a tick")
	assert_true(near < far, "within two cells the wait is gentler")
	# +10% patience: 200 ticks of waiting use about 200 / 1.1 of the budget.
	assert_true(near >= 180 and near <= 183, "about 182 ticks used, got %d" % near)
	assert_eq(_queue_wait_after(200, 0), near, "any distance up to the radius counts the same")
	assert_eq(_queue_wait_after(200, 1), near)


func test_a_guest_near_the_cat_outlasts_an_identical_guest_far_away() -> void:
	var near: int = _food_wait_after(300, 1)
	var far: int = _food_wait_after(300, 5)
	assert_eq(far, 300, "away from the cat each tick of waiting counts in full")
	# +10% patience: 300 ticks of waiting use about 300 / 1.1 = 273 of the budget.
	assert_true(near >= 271 and near <= 275, "about 273 ticks used near the cat, got %d" % near)
	assert_true(far - near >= 25, "the near guest outlasts the far one by about 27 ticks")


func test_charm_needs_the_same_room_and_shop_floor() -> void:
	var sim: RestaurantSim = _empty_sim()
	var grid: SimGrid = sim.world.grid
	sim.cat.adopted = true
	sim.cat.cell = Vector2i(5, 5)
	assert_true(sim.cat.charms(grid, Vector2i(6, 5)))
	assert_false(sim.cat.charms(grid, Vector2i(8, 5)), "three cells away")
	assert_true(grid.set_rooms({Vector2i(6, 5): SimGrid.Room.RESTROOM}))
	assert_false(sim.cat.charms(grid, Vector2i(6, 5)), "another room, even through a wall-thin gap")
	assert_false(sim.cat.charms(grid, Vector2i(0, 1)), "a guest in the street entry is not in the shop")
	assert_false(sim.cat.charms(grid, Vector2i(-1, 1)), "nor one outside the grid")
	var guest: CustomerAgent = sim.add_customer(Vector2i(0, 1), _rng(3))
	guest.state = CustomerAgent.State.QUEUED
	guest.cell = Vector2i(6, 5)
	sim.cat.cell = Vector2i(5, 5)
	sim.cat.from_cell = sim.cat.cell
	sim.cat.advance(grid, [guest])
	assert_false(guest.petted_cat, "no petting across rooms")


func test_the_cat_keeps_out_of_the_doorway() -> void:
	var sim: RestaurantSim = _empty_sim()
	var grid: SimGrid = sim.world.grid
	var cat: RestaurantCat = sim.cat
	for blocked: Vector2i in [Vector2i(1, 1), Vector2i(0, 0), Vector2i(0, 2), Vector2i(2, 1)]:
		assert_false(cat.cell_ok(grid, blocked), "%s is the door or just inside it" % blocked)
	assert_true(cat.cell_ok(grid, Vector2i(3, 3)))
	cat.use_rng(_rng(21))
	cat.adopt(grid)
	for tick: int in 12000:
		cat.advance(grid, [])
		assert_true(cat.cell_ok(grid, cat.cell), "tick %d: %s" % [tick, cat.cell])


func test_naps_avoid_the_front_wall_when_another_side_has_one() -> void:
	var grid: SimGrid = _box(8, 6)
	assert_true(grid.set_terrain(Vector2i(4, 5), SimGrid.Terrain.ENTRY))
	assert_true(grid.set_segment(Vector3i(2, 5, SimGrid.EDGE_NORTH), SimGrid.Segment.WINDOW))
	var cat: RestaurantCat = RestaurantCat.new(TUNING)
	var spots: Array[Vector2i] = cat.nap_spots(grid)
	assert_false(spots.has(Vector2i(2, 4)), "a window in the front wall is not chosen while side walls exist")
	assert_false(spots.has(Vector2i(3, 4)), "nor the front wall itself")
	assert_true(spots.has(Vector2i(1, 2)), "a side wall will do")
	assert_false(cat.naps_in_sun(grid), "no side window: wall spots")
	assert_true(grid.set_segment(Vector3i(7, 2, SimGrid.EDGE_WEST), SimGrid.Segment.WINDOW))
	assert_eq(cat.nap_spots(grid), [Vector2i(6, 2)] as Array[Vector2i], "a side window beats everything")
	assert_true(cat.naps_in_sun(grid))


func test_naps_use_the_front_wall_only_when_nothing_else_exists() -> void:
	var grid: SimGrid = SimGrid.new(Vector2i(7, 4))
	for x: int in 7:
		grid.set_terrain(Vector2i(x, 3), SimGrid.Terrain.WALL)
	assert_true(grid.set_terrain(Vector2i(3, 3), SimGrid.Terrain.ENTRY))
	var cat: RestaurantCat = RestaurantCat.new(TUNING)
	var spots: Array[Vector2i] = cat.nap_spots(grid)
	# Only the street wall exists: its panes either side of the door are the sunny spots.
	assert_eq(spots, [Vector2i(2, 2), Vector2i(4, 2)] as Array[Vector2i], "never in the doorway itself")
	assert_true(cat.naps_in_sun(grid))


func test_a_cat_with_nowhere_to_stand_does_not_rescan_every_tick() -> void:
	var grid: SimGrid = _box(3, 3)
	var cat: RestaurantCat = RestaurantCat.new(TUNING, _rng(1))
	cat.adopt(grid)
	assert_eq(cat.cell, Vector2i(1, 1))
	assert_true(grid.set_terrain(Vector2i(1, 1), SimGrid.Terrain.WALL))
	cat.layout_changed(grid)
	assert_eq(cat.cell, SimGrid.NO_CELL)
	var version: int = grid.version
	for tick: int in 50:
		cat.advance(grid, [])
	assert_eq(grid.version, version)
	assert_eq(cat.cell, SimGrid.NO_CELL)
	assert_true(grid.set_terrain(Vector2i(1, 1), SimGrid.Terrain.FLOOR))
	cat.advance(grid, [])
	assert_eq(cat.cell, Vector2i(1, 1), "it comes back once the layout changes")


func test_relief_is_off_without_an_adopted_cat() -> void:
	var sim: RestaurantSim = _empty_sim()
	var guest: CustomerAgent = sim.add_customer(Vector2i(0, 1), _rng(3))
	sim.cat.cell = guest.cell
	var refunds: int = 0
	for tick: int in 500:
		refunds += guest.cat_relief(sim)
	assert_eq(refunds, 0)


# --- Petting --------------------------------------------------------------------

func test_a_waiting_guest_within_one_cell_pets_the_cat_once_per_visit() -> void:
	var sim: RestaurantSim = _empty_sim()
	var grid: SimGrid = sim.world.grid
	var guest: CustomerAgent = sim.add_customer(Vector2i(0, 1), _rng(3))
	guest.state = CustomerAgent.State.QUEUED
	guest.cell = Vector2i(5, 5)
	var cat: RestaurantCat = sim.cat
	cat.adopt(grid)
	cat.cell = Vector2i(7, 5)
	cat.from_cell = cat.cell
	cat.advance(grid, [guest])
	assert_false(guest.petted_cat, "two cells away is too far to reach")
	assert_ne(cat.state, RestaurantCat.State.PETTED)
	cat.cell = Vector2i(6, 6)
	cat.from_cell = cat.cell
	cat.advance(grid, [guest])
	assert_true(guest.petted_cat)
	assert_eq(cat.state, RestaurantCat.State.PETTED)
	assert_eq(cat.petted_by, [guest.id] as Array[int])
	assert_eq(cat.heading, Vector2i(-1, -1), "the cat turns to the guest")
	var still: Vector2i = cat.cell
	for tick: int in TUNING.pet_pause_ticks - 1:
		cat.advance(grid, [guest])
		assert_eq(cat.state, RestaurantCat.State.PETTED)
		assert_eq(cat.cell, still, "a short pause: it stays put")
	cat.advance(grid, [guest])
	assert_ne(cat.state, RestaurantCat.State.PETTED)
	cat.advance(grid, [guest])
	assert_eq(cat.petted_by.size(), 1, "never twice in one visit")
	assert_true(guest.petted_cat)


func test_only_waiting_guests_pet_it() -> void:
	var sim: RestaurantSim = _empty_sim()
	var grid: SimGrid = sim.world.grid
	var eating: CustomerAgent = sim.add_customer(Vector2i(0, 1), _rng(3))
	eating.state = CustomerAgent.State.EATING
	eating.cell = Vector2i(5, 5)
	sim.cat.adopt(grid)
	sim.cat.cell = Vector2i(5, 6)
	sim.cat.from_cell = sim.cat.cell
	sim.cat.advance(grid, [eating])
	assert_false(eating.petted_cat)
	var waiting: CustomerAgent = sim.add_customer(Vector2i(0, 1), _rng(4))
	waiting.state = CustomerAgent.State.WAITING_FOOD
	waiting.cell = Vector2i(4, 6)
	sim.cat.advance(grid, [eating, waiting])
	assert_true(waiting.petted_cat)


func test_petting_gives_a_positive_review_with_its_own_three_quotes() -> void:
	var lines: PackedStringArray = QUOTES.groups[&"petted_cat"]
	assert_eq(lines.size(), 3)
	assert_true(QUOTES.is_valid())
	var sim: RestaurantSim = _empty_sim()
	var guest: CustomerAgent = sim.add_customer(Vector2i(0, 1), _rng(3))
	guest.paid = true
	guest.petted_cat = true
	var visit: ReviewVisit = guest.review_visit(12)
	assert_true(visit.petted_cat)
	assert_eq(ReputationBook.cause_of(visit, REVIEWS), &"petted_cat")
	assert_true(lines.has(QUOTES.pick(&"petted_cat", _rng(1), {})))
	guest.petted_cat = false
	assert_ne(ReputationBook.cause_of(guest.review_visit(12), REVIEWS), &"petted_cat")
	# A real complaint still wins over the cat.
	guest.petted_cat = true
	guest._food_wait = 1200
	visit = guest.review_visit(12)
	visit.food_wait_fraction = 1.0
	visit.queue_wait_fraction = 1.0
	assert_eq(ReputationBook.cause_of(visit, REVIEWS), &"slow_food")


# --- Not a person ---------------------------------------------------------------

func test_the_cat_is_not_an_agent_and_reserves_nothing() -> void:
	var plain: RestaurantSim = _sim()
	var with_cat: RestaurantSim = _sim()
	with_cat.cat.adopt(with_cat.world.grid)
	assert_eq(with_cat.world.all_agents().size(), plain.world.all_agents().size(), "no extra agent")
	assert_true(with_cat.world.clock.start_service())
	for tick: int in 900:
		with_cat.advance()
		assert_eq(with_cat.world.agents.size() + with_cat.world.pending_agents().size(),
			with_cat.world.all_agents().size())
	var ids: Dictionary[int, bool] = {}
	for agent: SimAgent in with_cat.world.all_agents():
		ids[agent.id] = true
	for item: PlacedItem in with_cat.world.grid.items():
		for cell: Vector2i in item.seat_cells + item.work_cells:
			var holder: int = item.reserved_by(cell)
			assert_true(holder <= 0 or ids.has(holder), "every reservation belongs to a person")


func test_the_cat_never_changes_where_people_walk() -> void:
	# Charm off (it is the one thing the cat is allowed to change): every
	# person's cell and state on every tick is identical with and without it.
	var without: Array = _people_trace(false)
	var with_cat: Array = _people_trace(true)
	assert_true(without.size() > 1000)
	assert_eq(with_cat.size(), without.size())
	for tick: int in without.size():
		if without[tick] != with_cat[tick]:
			fail("people differ at tick %d: %s vs %s" % [tick, without[tick], with_cat[tick]])
			return
	var seated: bool = false
	for row: Variant in without:
		seated = seated or str(row).contains("customer")
	assert_true(seated, "the comparison included real guests")


func test_a_person_and_the_cat_can_stand_in_the_same_cell() -> void:
	var sim: RestaurantSim = _empty_sim()
	var guest: CustomerAgent = sim.add_customer(Vector2i(0, 1), _rng(3))
	sim.cat.adopt(sim.world.grid)
	sim.cat.cell = guest.cell
	sim.cat.from_cell = guest.cell
	var before: Vector2i = guest.cell
	for tick: int in 20:
		sim.cat.advance(sim.world.grid, [])
		guest.tick(sim.world)
	assert_true(guest.cell != before or guest.state != CustomerAgent.State.ARRIVING, "the guest carries on")


# --- Saving ---------------------------------------------------------------------

func test_save_keeps_adoption_and_name_but_not_where_it_stands() -> void:
	var cat: RestaurantCat = RestaurantCat.new(TUNING)
	assert_eq(cat.to_dict(), {"version": 1, "adopted": false, "name": "Biscuit"})
	cat.adopt(_sim().world.grid)
	cat.cat_name = "Mochi"
	var saved: Dictionary = JSON.parse_string(JSON.stringify(cat.to_dict()))
	var loaded: RestaurantCat = RestaurantCat.new(TUNING)
	assert_true(loaded.from_dict(saved))
	assert_true(loaded.adopted)
	assert_eq(loaded.cat_name, "Mochi")
	assert_eq(loaded.cell, SimGrid.NO_CELL, "position is not saved")
	assert_false(str(saved).contains("cell"))


func test_save_rejects_malformed_sections_and_changes_nothing() -> void:
	var cat: RestaurantCat = RestaurantCat.new(TUNING)
	for bad: Variant in [null, [], {}, {"version": 1, "adopted": true},
			{"version": 2, "adopted": true, "name": "Biscuit"},
			{"version": 1, "adopted": "yes", "name": "Biscuit"},
			{"version": 1, "adopted": true, "name": ""},
			{"version": 1, "adopted": true, "name": "x".repeat(TUNING.max_name_length + 1)},
			{"version": 1, "adopted": true, "name": 7}]:
		assert_false(cat.from_dict(bad), "rejects %s" % [bad])
		assert_false(cat.adopted)
		assert_eq(cat.cat_name, "Biscuit")


# --- Helpers --------------------------------------------------------------------

func _sim(seed_value: int = 1) -> RestaurantSim:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, seed_value, errors)
	assert_eq(errors, [] as Array[String])
	return sim


func _empty_sim() -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	var grid: SimGrid = SimGrid.new(Vector2i(12, 12))
	grid.set_terrain(Vector2i(0, 1), SimGrid.Terrain.ENTRY)
	sim.world = SimWorld.new(grid, SimClock.new())
	sim.spawner = CustomerSpawner.new(sim.rng)
	sim.spawner._remaining = 1000000
	assert_true(sim.world.clock.start_service())
	return sim


## A walled box: the border is WALL, the inside FLOOR.
func _box(width: int, height: int) -> SimGrid:
	var grid: SimGrid = SimGrid.new(Vector2i(width, height))
	for x: int in width:
		for y: int in height:
			if x == 0 or y == 0 or x == width - 1 or y == height - 1:
				grid.set_terrain(Vector2i(x, y), SimGrid.Terrain.WALL)
	return grid


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random


func _path(seed_value: int, ticks: int) -> Array[Vector2i]:
	GameState.new_run(seed_value)
	var sim: RestaurantSim = _sim()
	sim.cat.use_rng(GameState.rng(&"cat"))
	sim.cat.adopt(sim.world.grid)
	var out: Array[Vector2i] = []
	var last: Vector2i = SimGrid.NO_CELL
	for tick: int in ticks:
		sim.cat.advance(sim.world.grid, [])
		if sim.cat.cell != last:
			last = sim.cat.cell
			out.append(last)
	return out


## Waiting `ticks` in the queue with the cat parked `distance` cells away.
func _queue_wait_after(ticks: int, distance: int) -> int:
	var sim: RestaurantSim = _empty_sim()
	var guest: CustomerAgent = sim.add_customer(Vector2i(0, 1), _rng(3))
	guest.move_speed = 1.0
	guest.queue_patience = 100000
	for tick: int in 12:
		guest.tick(sim.world)
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	sim.cat.adopted = true
	sim.cat.cell = guest.cell + Vector2i(distance, 0)
	var before: int = guest._queue_wait
	for tick: int in ticks:
		guest.tick(sim.world)
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	return guest._queue_wait - before


## A real seated guest waiting for a meal that never comes (no kitchen), with
## the cat parked `distance` cells away; returns how much patience it used.
func _food_wait_after(ticks: int, distance: int) -> int:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 4, errors, null, false)
	assert_eq(errors, [] as Array[String])
	assert_true(sim.world.clock.start_service())
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], _rng(3))
	guest.food_patience = 100000
	guest.queue_patience = 100000
	for tick: int in 1500:
		if guest.state == CustomerAgent.State.ORDERING or guest.state == CustomerAgent.State.WAITING_FOOD:
			break
		sim.world.advance()
	assert_true(guest.state == CustomerAgent.State.ORDERING or guest.state == CustomerAgent.State.WAITING_FOOD)
	sim.cat.adopted = true
	sim.cat.cell = guest.cell + Vector2i(distance, 0)
	var before: int = guest._food_wait
	for tick: int in ticks:
		sim.world.advance()
	assert_true(guest.state == CustomerAgent.State.ORDERING or guest.state == CustomerAgent.State.WAITING_FOOD)
	return guest._food_wait - before


func _people_trace(with_cat: bool) -> Array:
	GameState.new_run(11)
	var sim: RestaurantSim = _sim(11)
	sim.use_rng(GameState.rng(&"customers"))
	if with_cat:
		var quiet: CatTuning = TUNING.duplicate() as CatTuning
		quiet.charm_patience_bonus = 0.0
		sim.cat.tuning = quiet
		sim.cat.use_rng(GameState.rng(&"cat"))
		sim.cat.adopt(sim.world.grid)
	assert_true(sim.world.clock.start_service())
	var rows: Array = []
	for tick: int in 2500:
		sim.advance()
		var row: Array = []
		for agent: SimAgent in sim.world.all_agents():
			row.append([agent.id, agent.role, agent.cell.x, agent.cell.y])
		rows.append(row)
	return rows
