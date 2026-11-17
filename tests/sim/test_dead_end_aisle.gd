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
	var food: bool = false
	var works: bool = false

	func tick(world: SimWorld) -> void:
		step_move(world)
		if works and has_arrived():
			last_progress_tick = world.now  # As StaffAgent does while it works.

	func carries_food() -> bool:
		return food

	func maintain_movement_pause(_world: SimWorld) -> void:
		pass


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
	var station: Vector2i = Vector2i(1, 2)
	var server: StaffWalker = _staff(world, DEEP, station)
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


# --- When nobody can be let out: never worse than the ordinary rules ----------
# Fixtures from the review of #545. The limits are what the commit before
# this change takes.

## A shop that is one corridor straight to the door, before opening (no
## stall backstop runs). The only cell off the leaver's way is the second
## street cell, where nobody may stand aside, so this is a dead end at both
## ends and the ordinary rules decide. A first version counted the street
## cell as the guest's way out, found no pocket there and asked nobody else:
## both stood for good.
func test_a_corridor_to_the_door_is_left_to_the_ordinary_rules() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["E.........#", "E##########"])))
	assert_eq(world.clock.phase, SimClock.Phase.MORNING, "premise: before opening, no stall backstop")
	var leaver: GuestWalker = _guest(world, Vector2i(9, 0), Vector2i(0, 0), CustomerAgent.State.LEAVING)
	var guest: GuestWalker = _guest(world, Vector2i(5, 0), Vector2i(9, 0))
	var asked: bool = false
	var done: Dictionary[int, int] = {}
	for tick: int in 130:
		if not _advance(world):
			return
		if not asked and leaver.next_cell() == guest.cell and guest.next_cell() == leaver.cell \
				and leaver.move_progress == 0.0 and guest.move_progress == 0.0:
			asked = true
			assert_null(world.movement._trapped_in_dead_end(world, leaver, guest), "the street is nowhere to stand aside")
		_note_arrivals(world, {leaver.id: Vector2i(0, 0), guest.id: Vector2i(9, 0)}, done, tick + 1)
	assert_true(asked, "premise: the two met head-on in the corridor")
	var out: int = done.get(leaver.id, -1)
	assert_true(out > 0 and out <= 106, "the leaver is out after %d ticks, at most the 106 of before" % out)
	assert_false(world.movement.escape_counts.has(&"dead_end"))


## A guest walking in with a server carrying food right behind it, and a
## leaver coming out. The server is busy (food in hand), so the line behind
## the guest cannot be sent out: the ordinary rules run that same tick.
func test_a_carrier_behind_the_guest_falls_back_to_the_ordinary_rules() -> void:
	var world: SimWorld = _world(AISLE)
	var guest: GuestWalker = _guest(world, Vector2i(4, 3), DEEP)
	var carrier: StaffWalker = _staff(world, MOUTH, Vector2i(4, 5))
	carrier.food = true
	var leaver: GuestWalker = _guest(world, DEEP, STREET, CustomerAgent.State.LEAVING)
	var goals: Dictionary = {guest.id: DEEP, carrier.id: Vector2i(4, 5), leaver.id: STREET}
	var done: Dictionary[int, int] = {}
	var failed: bool = false
	for tick: int in 200:
		if not failed and guest.cell == Vector2i(4, 4) and leaver.cell == Vector2i(4, 5) \
				and carrier.cell == Vector2i(4, 3) and not world.movement._mid_move(guest) \
				and not world.movement._mid_move(carrier):
			assert_eq(world.movement._trapped_in_dead_end(world, guest, leaver), leaver, "premise: a dead end")
			assert_false(world.movement._let_out(world, guest, leaver), "the guest cannot be let past the carrier")
			failed = true
		if not _advance(world):
			return
		_note_arrivals(world, goals, done, tick + 1)
	assert_true(failed, "premise: the three met in the aisle")
	for row: Array in [[guest, 129], [carrier, 137], [leaver, 165]]:
		var ticks: int = done.get((row[0] as SimAgent).id, -1)
		assert_true(ticks > 0 and ticks <= int(row[1]),
			"#%d is there after %d ticks, at most the %d of before" % [(row[0] as SimAgent).id, ticks, row[1]])


## A crowd of waiting guests stands around the mouth of the aisle behind the
## guest walking in. They are not following it in, so they are not pushed
## about to let the leaver out; the ordinary rules and the backstop decide.
func test_a_waiting_crowd_at_the_mouth_is_not_pushed_about() -> void:
	var world: SimWorld = _world(AISLE)
	var guest: GuestWalker = _guest(world, Vector2i(4, 3), DEEP)
	var crowd: Array[GuestWalker] = []
	for cell: Vector2i in [MOUTH, Vector2i(3, 2), Vector2i(5, 2), Vector2i(4, 1), Vector2i(3, 1), Vector2i(5, 1)]:
		var waiting: GuestWalker = _guest(world, cell, cell, CustomerAgent.State.QUEUED)
		waiting.clear_path()
		crowd.append(waiting)
	var leaver: GuestWalker = _guest(world, DEEP, STREET, CustomerAgent.State.LEAVING)
	var done: Dictionary[int, int] = {}
	var failed: bool = false
	for tick: int in 200:
		if not failed and guest.cell == Vector2i(4, 4) and leaver.cell == Vector2i(4, 5) \
				and not world.movement._mid_move(guest):
			assert_eq(world.movement._trapped_in_dead_end(world, guest, leaver), leaver, "premise: a dead end")
			assert_false(world.movement._let_out(world, guest, leaver), "nobody behind the guest is following it in")
			failed = true
		if not _advance(world):
			return
		for waiting: GuestWalker in crowd:
			assert_false(world.movement._letting_out.has(waiting.id), "nobody in the crowd is sent aside for the leaver")
		_note_arrivals(world, {guest.id: DEEP, leaver.id: STREET}, done, tick + 1)
	assert_true(failed, "premise: the two met in the aisle")
	var seated: int = done.get(guest.id, -1)
	var out: int = done.get(leaver.id, -1)
	assert_true(seated > 0 and seated <= 133, "the guest is seated after %d ticks, at most the 133 of before" % seated)
	assert_true(out > 0 and out <= 177, "the leaver is out after %d ticks, at most the 177 of before" % out)


# --- The wait beside the aisle ------------------------------------------------

## A worker comes out of the dead end and stops to work in its mouth, on the
## guest's way back. Staff refresh last_progress_tick every tick they work,
## so reading that kept the guest in its pocket for escape_after_ticks (120).
## The wait is read from the passer's cell: yield_after_ticks after it stops.
func test_the_wait_ends_when_a_worker_stops_on_the_way() -> void:
	var world: SimWorld = _world(AISLE)
	var movement: MovementCoordinator = world.movement
	var guest: GuestWalker = _guest(world, Vector2i(4, 3), DEEP)
	var worker: StaffWalker = _staff(world, DEEP, MOUTH)
	worker.works = true
	var limit: int = world.movement_tuning.yield_after_ticks
	var stopped: int = -1
	var released: int = -1
	var waited: bool = false
	for tick: int in LIMIT + 3 * limit:
		if not _advance(world):
			return
		waited = waited or (movement._letting_out.has(guest.id) and guest.has_arrived())
		if stopped < 0 and worker.has_arrived() and worker.cell == MOUTH:
			stopped = tick
			assert_true(movement._letting_out.has(guest.id), "premise: the guest is still waiting when the worker stops")
		if stopped >= 0 and released < 0 and not movement._letting_out.has(guest.id):
			released = tick
	assert_true(waited and stopped >= 0, "premise: the guest stood aside and the worker stopped in the mouth")
	assert_true(worker.last_progress_tick >= world.now - 1, "premise: the worker keeps reporting progress")
	assert_true(released >= 0 and released - stopped <= limit + 2,
		"the guest stops waiting %d ticks after the worker stopped, about the yield limit" % (released - stopped))


## Whoever waits in a pocket is an ordinary standing person to anyone else
## who needs that cell, and the wait ends as soon as something else moves it.
func test_someone_waiting_in_a_pocket_still_steps_aside_for_others() -> void:
	var world: SimWorld = _world(AISLE)
	var movement: MovementCoordinator = world.movement
	var guest: GuestWalker = _guest(world, MOUTH, DEEP)
	var leaver: GuestWalker = _guest(world, DEEP, STREET, CustomerAgent.State.LEAVING)
	for tick: int in LIMIT:
		if guest.has_arrived() and movement._letting_out.has(guest.id):
			break
		if not _advance(world):
			return
	assert_true(guest.has_arrived() and movement._letting_out.has(guest.id), "premise: the guest stands aside")
	var listed: Array = movement.snapshot()["letting_out"]
	assert_eq(listed.size(), 1, "the wait is in the movement snapshot")
	assert_eq(int(listed[0]["id"]), guest.id)
	assert_eq(int(listed[0]["passer"]), leaver.id)
	assert_eq(listed[0]["pocket"], guest.cell)
	assert_eq(movement._yield(world, guest, leaver), MovementCoordinator.YieldAttempt.IN_PROGRESS_PROTECTED,
		"the leaver it is waiting for has nothing more to ask")
	var server: StaffWalker = _staff(world, Vector2i(7, 1), Vector2i(1, 1))
	assert_eq(movement._yield(world, guest, server), MovementCoordinator.YieldAttempt.STARTED,
		"a third person who needs the pocket is given it")
	assert_false(movement._letting_out.has(guest.id), "and that ends the wait")
	assert_true(movement.snapshot()["letting_out"].is_empty())
	# Anything else that moves the giver ends it too (the backstop, a new errand).
	var again: SimWorld = _world(AISLE)
	var walker: GuestWalker = _guest(again, MOUTH, DEEP)
	_guest(again, DEEP, STREET, CustomerAgent.State.LEAVING)
	for tick: int in LIMIT:
		if walker.has_arrived() and again.movement._letting_out.has(walker.id):
			break
		if not _advance(again):
			return
	assert_true(again.movement._letting_out.has(walker.id), "premise: waiting in its pocket")
	walker.install_movement_route(again.movement.route(again, walker, walker.cell, Vector2i(7, 1), false))
	if not _advance(again):
		return
	assert_false(again.movement._letting_out.has(walker.id), "a new route out of the pocket ends the wait")


## At a wide door with pockets on both sides of the aisle's mouth, nobody
## stands aside in the door lane. In a corridor whose only free cell is in
## the lane, that cell is used rather than nobody being let out.
func test_the_door_lane_is_a_pocket_only_when_there_is_no_other() -> void:
	var near: SimWorld = _open(["#####", "E...#", "E...#", "##.##", "##.##", "##.##"])
	var guest: GuestWalker = _guest(near, Vector2i(2, 3), Vector2i(2, 5))
	var leaver: GuestWalker = _guest(near, Vector2i(2, 5), Vector2i(0, 1), CustomerAgent.State.LEAVING)
	assert_true(near.movement.in_door_lane(near, Vector2i(1, 2)), "premise: the nearest pocket is door lane")
	assert_false(near.movement.in_door_lane(near, Vector2i(3, 2)), "premise: a pocket further off is not")
	for tick: int in LIMIT:
		if guest.has_arrived() and near.movement._letting_out.has(guest.id):
			break
		if not _advance(near):
			return
	assert_true(near.movement._letting_out.has(guest.id), "premise: the guest stands aside")
	assert_false(near.movement.in_door_lane(near, guest.cell), "off the door lane (at %s)" % guest.cell)
	assert_ne(leaver.cell, Vector2i(2, 5), "and the leaver is on its way")
	var only: SimWorld = _open(["###########", "E.........#", "E.#########"])
	var walker: GuestWalker = _guest(only, Vector2i(5, 1), Vector2i(9, 1))
	var going: GuestWalker = _guest(only, Vector2i(9, 1), Vector2i(0, 1), CustomerAgent.State.LEAVING)
	var done: Dictionary[int, int] = {}
	for tick: int in 2 * LIMIT:
		if not _advance(only):
			return
		_note_arrivals(only, {walker.id: Vector2i(9, 1), going.id: Vector2i(0, 1)}, done, tick + 1)
	assert_true(int(only.movement.escape_counts.get(&"dead_end", 0)) >= 1, "the lane cell is used when it is the only one")
	assert_eq(done.size(), 2, "and both get where they are going")


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


func _staff(world: SimWorld, at: Vector2i, goal: Vector2i) -> StaffWalker:
	var staff: StaffWalker = StaffWalker.new(&"server", 3)
	staff.cell = at
	world.add_agent(staff)
	assert_true(staff.set_destination(world.grid, goal))
	return staff


func _advance(world: SimWorld) -> bool:
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	var problem: String = MovementInvariants.problem(world, before)
	assert_eq(problem, "", "tick %d keeps movement safety" % world.now)
	return problem.is_empty()


## The first tick each person stands on its own goal, its errand resumed.
func _note_arrivals(world: SimWorld, goals: Dictionary, done: Dictionary[int, int], tick: int) -> void:
	for agent: SimAgent in world.agents:
		if goals.has(agent.id) and not done.has(agent.id) and agent.cell == goals[agent.id] \
				and agent.move_progress == 0.0 \
				and not world.movement.is_yielding(agent.id):
			done[agent.id] = tick
