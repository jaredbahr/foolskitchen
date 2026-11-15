extends TestCase
## #536: a head-on in a dead-end aisle away from the door. The one coming out
## cannot step aside: every cell behind it lies on the way of the one walking
## in. The ordinary yield sent it back all the same (the nearest free cell),
## the other followed, and at the end of the aisle the two traded places until
## the stall backstop. Now the one with the open way out backs out of the
## aisle, whoever goes first by rank or ID, and waits beside its mouth until
## the other is through. Hand-made fixtures: a room with a wide door and a
## one-cell aisle four cells deep. The numbers quoted are for the commit
## before this change.

const AISLE: Array[String] = [
	"#########",
	"E.......#",
	"E.......#",
	"####.####",
	"####.####",
	"####.####",
	"####.####",
]
## The same aisle with a one-cell nook beside it, three cells in.
const AISLE_WITH_NOOK: Array[String] = [
	"#########",
	"E.......#",
	"E.......#",
	"####.####",
	"####.####",
	"####..###",
	"####.####",
]
const MOUTH: Vector2i = Vector2i(4, 2)
const DEEP: Vector2i = Vector2i(4, 6)
const STREET: Vector2i = Vector2i(0, 1)
const LIMIT: int = 60


class GuestWalker extends CustomerAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)

	func give_up_blocked(_world: SimWorld) -> void:
		pass

	## No restaurant behind this fixture: movement pauses run no visit logic.
	func maintain_movement_pause(_world: SimWorld) -> void:
		pass


class StaffWalker extends StaffAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


func after_each() -> void:
	GameState.new_run(1)


## Someone leaves the seat at the end of the aisle while the guest given that
## seat walks in, and the guest goes first on its lower ID. Before: the
## leaver stepped back to the end, then asked for room, and the two went back
## and forth until the backstop (leaver out after 161 ticks, guest seated
## after 165).
func test_a_leaver_gets_out_of_a_dead_end_when_the_guest_walking_in_goes_first() -> void:
	_leaver_meets_guest(true)


## The same with the IDs the other way round. Before: the guest gave way one
## cell at a time, each after a full wait, and came back in between (out after
## 60 ticks, seated after 69).
func test_a_leaver_gets_out_of_a_dead_end_when_the_leaver_goes_first() -> void:
	_leaver_meets_guest(false)


## A server comes out of the dead end against two guests walking in behind
## one another. The first guest is boxed in between the server and the second
## guest. Before, it asked the server for room, the server stepped back in,
## and they traded places until the backstop (server out after 165 ticks,
## guests seated after 177 and 183). Now the second guest is sent out of the
## aisle too, and both wait beside its mouth.
func test_a_server_gets_out_of_a_dead_end_past_two_guests_walking_in() -> void:
	var world: SimWorld = _world(AISLE)
	var server: StaffWalker = StaffWalker.new(&"server", 3)
	server.cell = DEEP
	world.add_agent(server)
	var station: Vector2i = Vector2i(1, 2)
	assert_true(server.set_destination(world.grid, station))
	var first: GuestWalker = _guest(world, MOUTH, DEEP)
	var second: GuestWalker = _guest(world, Vector2i(4, 1), Vector2i(4, 5))
	var deepest: int = server.cell.y
	var done: Dictionary[int, int] = {}
	for tick: int in 2 * LIMIT:
		if not _advance(world):
			return
		assert_true(server.cell.y <= deepest, "the server never steps back into the dead end (tick %d)" % (tick + 1))
		deepest = server.cell.y
		_note_arrivals(world, {server.id: station, first.id: DEEP, second.id: Vector2i(4, 5)}, done, tick + 1)
	for agent: SimAgent in [server, first, second]:
		var ticks: int = done.get(agent.id, -1)
		assert_true(ticks > 0 and ticks < LIMIT, "#%d is there after %d ticks, under %d" % [agent.id, ticks, LIMIT])
	assert_true(int(world.movement.escape_counts.get(&"dead_end", 0)) >= 1)
	assert_eq(int(world.movement.escape_counts.get(&"escape", 0)), 0, "the stall backstop was not needed")
	assert_false(world.movement.escape_counts.has(&"pocket"), "and its counts stay its own")


## Whoever stepped aside waits for the passer and no longer: when the person
## coming out stops getting anywhere (here it simply stops), the one beside
## the aisle goes back to its own errand after yield_after_ticks.
func test_stepping_aside_for_someone_in_a_dead_end_is_bounded() -> void:
	var world: SimWorld = _world(AISLE)
	var guest: GuestWalker = _guest(world, MOUTH, DEEP)
	var leaver: GuestWalker = _guest(world, DEEP, STREET, CustomerAgent.State.LEAVING)
	var movement: MovementCoordinator = world.movement
	for tick: int in LIMIT:
		if guest.has_arrived() and movement._letting_out.has(guest.id):
			break
		if not _advance(world):
			return
	assert_true(guest.has_arrived() and movement._letting_out.has(guest.id), "premise: the guest stands aside")
	assert_true(guest.cell.y <= MOUTH.y and guest.cell != MOUTH, "outside the aisle and off its mouth")
	assert_true(leaver.cell.y > MOUTH.y, "premise: the leaver is still in the aisle")
	leaver.clear_path()
	var limit: int = world.movement_tuning.yield_after_ticks
	var held: int = 0
	for tick: int in 3 * limit:
		if not _advance(world):
			return
		if not movement._letting_out.has(guest.id):
			break
		held += 1
	assert_true(held >= 1, "the guest waits while the leaver could still be coming")
	assert_true(held <= limit + 4, "and for no longer than the yield limit after it last moved (%d ticks)" % held)
	assert_false(guest.has_arrived(), "then it is on its way to its seat again")


## The rule is for a real dead end only. Everywhere else the ordinary order
## (rank, then ID) still decides who steps aside.
func test_only_a_real_dead_end_changes_who_steps_aside() -> void:
	var world: SimWorld = _world(AISLE)
	var movement: MovementCoordinator = world.movement
	var guest: GuestWalker = _guest(world, Vector2i(4, 4), DEEP)
	var leaver: GuestWalker = _guest(world, Vector2i(4, 5), STREET, CustomerAgent.State.LEAVING)
	assert_eq(movement._trapped_in_dead_end(world, guest, leaver), leaver, "the one coming out is let out")
	assert_eq(movement._trapped_in_dead_end(world, leaver, guest), leaver, "whichever of the two asks")
	# The guest's seat is not at the very end: the cell behind the leaver is
	# off the guest's way, so the leaver can step back there.
	assert_true(guest.set_destination(world.grid, Vector2i(4, 5)))
	assert_null(movement._trapped_in_dead_end(world, guest, leaver), "room behind the leaver: no dead end")
	# Not a head-on: the guest is going the same way out.
	assert_true(guest.set_destination(world.grid, Vector2i(1, 1)))
	assert_null(movement._trapped_in_dead_end(world, leaver, guest), "someone ahead going the same way")
	# Someone standing still is asked to move by the ordinary rules.
	guest.clear_path()
	assert_null(movement._trapped_in_dead_end(world, leaver, guest), "nobody coming the other way")
	# A nook beside the aisle is somewhere to step aside to.
	var nook: SimWorld = _world(AISLE_WITH_NOOK)
	var walker: GuestWalker = _guest(nook, Vector2i(4, 4), DEEP)
	var going: GuestWalker = _guest(nook, Vector2i(4, 5), STREET, CustomerAgent.State.LEAVING)
	assert_null(nook.movement._trapped_in_dead_end(nook, walker, going), "a nook beside the leaver: no dead end")
	# Closed at both ends: neither has anywhere to go, the ordinary rules decide.
	var closed: SimWorld = _open(["E..#######", "E..#.....#", "##########"])
	var east: GuestWalker = _guest(closed, Vector2i(6, 1), Vector2i(4, 1))
	var west: GuestWalker = _guest(closed, Vector2i(5, 1), Vector2i(8, 1))
	assert_null(closed.movement._trapped_in_dead_end(closed, east, west), "both in a dead end")
	# At the door the door rules decide (out before in, #459).
	var door: SimWorld = _open(["E......"])
	var incoming: GuestWalker = _guest(door, Vector2i(1, 0), Vector2i(6, 0))
	var outgoing: GuestWalker = _guest(door, Vector2i(2, 0), Vector2i(0, 0), CustomerAgent.State.LEAVING)
	assert_true(door.movement.in_door_lane(door, incoming.cell), "premise: in the door lane")
	assert_null(door.movement._trapped_in_dead_end(door, incoming, outgoing), "the door lane keeps its own rules")


# --- Fixtures ----------------------------------------------------------------

func _leaver_meets_guest(guest_first: bool) -> void:
	var world: SimWorld = _world(AISLE)
	var guest: GuestWalker = null
	if guest_first:
		guest = _guest(world, MOUTH, DEEP)
	var leaver: GuestWalker = _guest(world, DEEP, STREET, CustomerAgent.State.LEAVING)
	if not guest_first:
		guest = _guest(world, MOUTH, DEEP)
	assert_eq(guest.id < leaver.id, guest_first, "premise: the ID order")
	assert_eq(world.movement._before(world, guest, leaver), guest_first, "premise: who goes first by rank and ID")
	var deepest: int = leaver.cell.y
	var stepped_out: bool = false
	var done: Dictionary[int, int] = {}
	for tick: int in 2 * LIMIT:
		if not _advance(world):
			return
		assert_true(leaver.cell.y <= deepest, "the leaver never steps back into the dead end (tick %d)" % (tick + 1))
		deepest = leaver.cell.y
		stepped_out = stepped_out or (world.movement.is_yielding(guest.id) and guest.cell.y < MOUTH.y + 1)
		if stepped_out and leaver.cell.y > MOUTH.y:
			assert_true(guest.cell.y <= MOUTH.y and guest.next_cell().y <= MOUTH.y,
				"the guest stays out of the aisle until the leaver is out of it (tick %d)" % (tick + 1))
		_note_arrivals(world, {leaver.id: STREET, guest.id: DEEP}, done, tick + 1)
	var out: int = done.get(leaver.id, -1)
	var seated: int = done.get(guest.id, -1)
	assert_true(out > 0 and out < LIMIT, "the leaver is on the street after %d ticks, under %d" % [out, LIMIT])
	assert_true(seated > 0 and seated < LIMIT, "the guest is at its seat after %d ticks, under %d" % [seated, LIMIT])
	assert_true(stepped_out, "the guest backed out of the aisle")
	assert_eq(int(world.movement.escape_counts.get(&"escape", 0)), 0, "the stall backstop was not needed")


func _open(rows: Array[String]) -> SimWorld:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(rows)))
	assert_true(world.clock.start_service())
	return world


func _world(rows: Array[String]) -> SimWorld:
	var world: SimWorld = _open(rows)
	assert_false(world.movement.narrow_way_in(world), "premise: a wide door, so no door rule applies")
	assert_false(world.movement.in_door_lane(world, MOUTH), "premise: away from the door")
	return world


## Added while still arriving (so nobody is kept on the street by a leaver
## added earlier), then given its state and a place to go.
func _guest(world: SimWorld, at: Vector2i, goal: Vector2i,
		state: CustomerAgent.State = CustomerAgent.State.WALKING_TO_SEAT) -> GuestWalker:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 536
	var guest: GuestWalker = GuestWalker.new(RestaurantSim.new(), random)
	guest.cell = at
	world.add_agent(guest)
	assert_true(guest.movement_admitted, "fixture guest admitted at %s" % at)
	guest.state = state
	assert_true(guest.set_destination(world.grid, goal))
	return guest


func _advance(world: SimWorld) -> bool:
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	var problem: String = MovementInvariants.problem(world, before)
	assert_eq(problem, "", "tick %d keeps movement safety" % world.now)
	return problem.is_empty()


## The first tick each person stands on its own goal, its errand resumed.
func _note_arrivals(world: SimWorld, goals: Dictionary, done: Dictionary[int, int], tick: int) -> void:
	for agent: SimAgent in world.agents:
		if not done.has(agent.id) and agent.cell == goals[agent.id] and agent.move_progress == 0.0 \
				and not world.movement.is_yielding(agent.id):
			done[agent.id] = tick
