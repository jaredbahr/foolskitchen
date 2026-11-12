extends TestCase
## #305: guests waiting for a table stand beside the front door, never in its
## lane, and a leaving guest gets through a waiting crowd. Real starter shop.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const SETTLE_TICKS: int = 160
const EXIT_WATCHDOG: int = 90

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func test_door_lane_is_derived_from_the_entries() -> void:
	var sim: RestaurantSim = _full_shop()
	var world: SimWorld = sim.world
	for entry: Vector2i in world.grid.entries():
		assert_true(world.movement.in_door_lane(world, entry))
		var inside: Array[Vector2i] = []
		for neighbour: Vector2i in world.grid.walkable_neighbours(entry):
			if world.grid.terrain(neighbour) == SimGrid.Terrain.FLOOR:
				assert_true(world.movement.in_door_lane(world, neighbour), "the cell inside a door is lane")
				inside.append(neighbour)
		assert_false(inside.is_empty())


func test_queued_guest_in_the_door_lane_yields_to_a_leaver() -> void:
	var sim: RestaurantSim = _full_shop()
	var world: SimWorld = sim.world
	var entry: Vector2i = world.grid.entries()[0]
	var queued: CustomerAgent = _guest(sim, entry)
	queued.state = CustomerAgent.State.QUEUED
	var leaving: CustomerAgent = _guest(sim, world.grid.entries()[1])
	leaving.state = CustomerAgent.State.LEAVING
	assert_true(world.movement.priority(world, queued) < world.movement.priority(world, leaving))
	assert_true(world.movement._before(world, leaving, queued))
	assert_true(world.movement._before(world, leaving, queued), "even though the queued guest has the lower ID")


func test_waiting_guests_settle_clear_of_the_door_lane() -> void:
	var sim: RestaurantSim = _full_shop()
	# Four is what the cells beside the starter door hold; a bigger crowd
	# queues deeper (a boxed-in latecomer may still stand in the lane).
	var guests: Array[CustomerAgent] = _crowd(sim, 4)
	for tick: int in SETTLE_TICKS:
		_advance(sim)
	var standing: int = 0
	for guest: CustomerAgent in guests:
		if guest.state != CustomerAgent.State.QUEUED:
			continue
		standing += 1
		assert_false(sim.world.movement.in_door_lane(sim.world, guest.cell),
			"queued guest %d stands in the door lane at %s" % [guest.id, guest.cell])
		assert_eq(sim.world.grid.terrain(guest.cell), SimGrid.Terrain.FLOOR)
		for item: PlacedItem in sim.world.grid.items():
			assert_false(item.work_cells.has(guest.cell), "no waiter blocks a work cell")
	assert_eq(standing, 4, "the whole crowd is still waiting")


func test_leaver_exits_through_a_waiting_crowd() -> void:
	var sim: RestaurantSim = _full_shop()
	var guests: Array[CustomerAgent] = _crowd(sim, 6)
	for tick: int in SETTLE_TICKS:
		_advance(sim)
	var entries: Array[Vector2i] = sim.world.grid.entries()
	var leaver: CustomerAgent = null
	for guest: CustomerAgent in guests:
		if guest.state == CustomerAgent.State.QUEUED and (leaver == null \
				or GridMath.octile(guest.cell, entries[0]) > GridMath.octile(leaver.cell, entries[0])):
			leaver = guest
	assert_not_null(leaver)
	if leaver == null:
		return
	leaver._leave(sim.world, sim, &"no_table")
	var id: int = leaver.id
	var out: bool = false
	for tick: int in EXIT_WATCHDOG:
		_advance(sim)
		if sim.world.agent(id) == null:
			out = true
			break
	assert_true(out, "the leaver reaches the street within %d ticks" % EXIT_WATCHDOG)


func test_waiting_is_deterministic() -> void:
	var first: String = _fingerprint()
	var second: String = _fingerprint()
	assert_eq(first, second)


func _fingerprint() -> String:
	var sim: RestaurantSim = _full_shop()
	var guests: Array[CustomerAgent] = _crowd(sim, 6)
	for tick: int in SETTLE_TICKS:
		_advance(sim)
	var parts: PackedStringArray = PackedStringArray()
	for guest: CustomerAgent in guests:
		parts.append("%d:%d:%s" % [guest.id, guest.state, guest.cell])
	return ",".join(parts)


## #322: an edited shop whose door opens onto a one-cell way in, (7, 11),
## with the dead-end cell (8, 11) beside it and open floor only to its west.
## The cells beside that way are where queued guests wait, so they stand on
## the only way out, and arrivals from the street pack the door cells.
func test_arrivals_wait_on_the_street_while_a_leaver_is_stuck_at_a_narrow_door() -> void:
	var sim: RestaurantSim = _narrow_door_shop()
	var world: SimWorld = sim.world
	var leaving: CustomerAgent = _guest(sim, Vector2i(6, 11))
	leaving.state = CustomerAgent.State.LEAVING
	assert_false(world.movement.in_door_lane(world, leaving.cell), "stuck one step short of the lane")
	var entry: Vector2i = world.grid.entries()[0]
	var arriving: CustomerAgent = _guest(sim, entry)
	assert_true(arriving.movement_admitted, "the old street hold only covers a leaver inside the lane")
	arriving.state = CustomerAgent.State.QUEUED
	_stall(world, leaving)
	assert_true(world.movement.door_outflow_stalled(world))
	arriving._queue_inside(world)
	assert_eq(arriving.cell, entry)
	assert_true(arriving.path.is_empty(), "stays on the street instead of stepping into the door")
	world.movement._stall.erase(leaving.id)
	assert_false(world.movement.door_outflow_stalled(world))
	arriving._queue_inside(world)
	assert_false(arriving.path.is_empty(), "steps in once the leaver is moving again")


func test_a_waiting_guest_never_heads_for_a_stuck_leavers_way_out() -> void:
	var sim: RestaurantSim = _narrow_door_shop()
	var world: SimWorld = sim.world
	var leaving: CustomerAgent = _guest(sim, Vector2i(5, 10))
	leaving.state = CustomerAgent.State.LEAVING
	var waiting: CustomerAgent = _guest(sim, Vector2i(3, 11))
	waiting.state = CustomerAgent.State.QUEUED
	# Cleared off the leaver's way by the backstop, it is walking back.
	waiting._wait_spot = Vector2i(6, 11)
	assert_true(waiting.set_destination(world.grid, waiting._wait_spot))
	_stall(world, leaving)
	assert_true(world.movement.on_stalled_exit_way(world, Vector2i(6, 11)), "the cell beside the way in")
	assert_true(world.movement.on_stalled_exit_way(world, Vector2i(7, 11)))
	waiting._queue_inside(world)
	assert_ne(waiting._wait_spot, Vector2i(6, 11), "gives up the spot on the way out")
	assert_ne(waiting._wait_spot, SimGrid.NO_CELL, "and waits somewhere else")
	assert_false(world.movement.on_stalled_exit_way(world, waiting._wait_spot))
	assert_false(world.movement.in_door_lane(world, waiting._wait_spot))
	# One already waiting on that way moves off it too.
	var standing: CustomerAgent = _guest(sim, Vector2i(6, 11))
	standing.state = CustomerAgent.State.QUEUED
	standing._wait_spot = standing.cell
	standing._queue_inside(world)
	assert_ne(standing._wait_spot, Vector2i(6, 11))
	assert_ne(standing._wait_spot, SimGrid.NO_CELL)
	assert_false(world.movement.on_stalled_exit_way(world, standing._wait_spot))
	assert_eq(standing.destination(), standing._wait_spot, "and walks to a spot off it")


## The starter shop with every dining seat held, so arrivals must queue.
func _full_shop() -> RestaurantSim:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 305, errors, null, false)
	assert_eq(errors, [] as Array[String])
	sim.spawner.min_gap = 1000000
	sim.spawner.max_gap = 1000000
	sim.spawner.reset()
	var holder: int = 900000
	for item: PlacedItem in sim.world.grid.items():
		for seat: Vector2i in item.seat_cells:
			holder += 1
			item.reserve(seat, holder)
	assert_true(sim.world.clock.start_service())
	return sim


## The starter shop with walls behind its door: (7, 11) is the one way in.
func _narrow_door_shop() -> RestaurantSim:
	var sim: RestaurantSim = _full_shop()
	var walls: Dictionary[Vector2i, int] = {Vector2i(7, 10): SimGrid.Terrain.WALL, Vector2i(8, 10): SimGrid.Terrain.WALL}
	for x: int in range(9, 15):
		walls[Vector2i(x, 11)] = SimGrid.Terrain.WALL
	assert_true(sim.world.grid.set_terrains(walls))
	return sim


## Stuck on the way out for the escape limit, as the movement watchdog records it.
func _stall(world: SimWorld, leaving: CustomerAgent) -> void:
	world.movement._stall[leaving.id] = {"goal": MovementCoordinator.EXIT_GOAL, "best": 0.0,
		"since": world.now - world.movement_tuning.escape_after_ticks, "next": world.now + 1000}
	world.movement._exit_ways_tick = -1


func _guest(sim: RestaurantSim, cell: Vector2i) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 305 + sim.world.agents.size()
	return sim.add_customer(cell, random)


## Arrivals trickle in at the door, as real ones do.
func _crowd(sim: RestaurantSim, count: int) -> Array[CustomerAgent]:
	var guests: Array[CustomerAgent] = []
	var entries: Array[Vector2i] = sim.world.grid.entries()
	for index: int in count:
		guests.append(_guest(sim, entries[index % entries.size()]))
		for tick: int in 12:
			_advance(sim)
	return guests


func _advance(sim: RestaurantSim) -> void:
	var before: Dictionary = MovementInvariants.capture(sim.world)
	sim.advance()
	var problem: String = MovementInvariants.problem(sim.world, before)
	assert_eq(problem, "", "every tick preserves occupied/next/edge safety")
