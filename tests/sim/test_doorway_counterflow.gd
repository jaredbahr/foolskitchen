extends TestCase
## #468: people passing each other in tight places, as stated guarantees
## rather than one fix per symptom. Each fixture is hand-made (a crossing of
## one-cell aisles, a one-cell corridor, the starter shop with a one-cell way
## in behind its door) so the proof does not depend on a seeded day reaching
## the state. The numbers quoted are for the commit before this change.
##
## What the sim promises, and the test that holds it to it:
## 1. Who goes first is one strict order: among people reaching for the same
##    free cell exactly one goes (no ring of people each waiting for another).
## 2. At the door: out before in, a seat before a wait. A guest who is only
##    waiting never outranks, and never asks room from, someone going somewhere.
## 3. A guest with a table is held on the street like one without (bounded by
##    door_hold_max_ticks, which does not spend the seat walk's own limit, and
##    during which it does not count as stuck).
## 4. Someone leaving waits behind another leaver ahead of it, and swaps past
##    waiting guests who cannot step aside, at the door or short of it.
## 5. The door rules run in service only, where their timers are kept.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const SETTLE_TICKS: int = 160

var _content: ContentDB
var _phantoms: Dictionary[Vector2i, int] = {}


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


class InspectorWalker extends InspectorAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	_phantoms.clear()
	GameState.new_run(1)


# --- 1. One strict order ----------------------------------------------------

## Every kind of person the door rules tell apart, with and without right of
## way. For any two exactly one goes first, and going first carries over
## (a before b, b before c: a before c). Before, someone leaving went before
## a waiting guest, a waiting guest with right of way before a guest walking
## to a seat, and that guest before the leaver on its lower ID: a ring.
func test_who_goes_first_is_one_strict_order() -> void:
	var world: SimWorld = _ascii_world(["#########", "#.......#", "#.......#", "#.......#", "###EE####"])
	var movement: MovementCoordinator = world.movement
	for cell: Vector2i in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 2), Vector2i(4, 2)]:
		assert_true(movement.in_door_lane(world, cell), "premise: %s is door lane" % cell)
	assert_false(movement.in_door_lane(world, Vector2i(2, 2)))
	var names: Dictionary[int, String] = {}
	var zoo: Array[SimAgent] = []
	var add: Callable = func(agent: SimAgent, label: String, way: bool) -> void:
		names[agent.id] = label
		zoo.append(agent)
		if way:
			movement._right_of_way[agent.id] = world.now + 100
	var walking: int = CustomerAgent.State.WALKING_TO_SEAT
	var queued: int = CustomerAgent.State.QUEUED
	add.call(_guest(world, Vector2i(1, 1), walking), "seat-walker", false)
	add.call(_guest(world, Vector2i(2, 1), queued), "waiting", false)
	add.call(_guest(world, Vector2i(3, 1), queued), "waiting+way", true)
	add.call(_guest(world, Vector2i(4, 3), queued), "waiting at the door", false)
	add.call(_guest(world, Vector2i(3, 3), queued), "waiting at the door+way", true)
	add.call(_guest(world, Vector2i(3, 2), walking), "seat-walker at the door", false)
	add.call(_guest(world, Vector2i(5, 1), walking), "seat-walker+way", true)
	add.call(_guest(world, Vector2i(6, 1), CustomerAgent.State.EATING), "eating", false)
	add.call(_staff(world, Vector2i(7, 1), false), "staff", false)
	add.call(_staff(world, Vector2i(1, 2), false), "staff+way", true)
	add.call(_staff(world, Vector2i(2, 2), true), "food in hand", false)
	var inspector: InspectorWalker = InspectorWalker.new()
	inspector.cell = Vector2i(6, 2)
	world.add_agent(inspector)
	inspector.state = InspectorAgent.State.LEAVING
	add.call(inspector, "inspector leaving", false)
	add.call(_guest(world, Vector2i(7, 2), CustomerAgent.State.LEAVING), "leaver", false)
	add.call(_guest(world, Vector2i(4, 2), CustomerAgent.State.LEAVING), "leaver at the door", false)
	add.call(_guest(world, Vector2i(5, 2), CustomerAgent.State.LEAVING), "leaver+way", true)
	add.call(_guest(world, Vector2i(3, 4), walking), "seat-walker at the door+way", true)
	for first: SimAgent in zoo:
		for second: SimAgent in zoo:
			if first == second:
				continue
			assert_true(movement._before(world, first, second) != movement._before(world, second, first),
				"exactly one of %s and %s goes first" % [names[first.id], names[second.id]])
			for third: SimAgent in zoo:
				if third == first or third == second:
					continue
				if movement._before(world, first, second) and movement._before(world, second, third):
					assert_true(movement._before(world, first, third), "%s before %s before %s, so %s before %s" % [
						names[first.id], names[second.id], names[third.id], names[first.id], names[third.id]])
	var order: Array[SimAgent] = zoo.duplicate()
	order.sort_custom(func(a: SimAgent, b: SimAgent) -> bool: return movement._before(world, a, b))
	var listed: Array[String] = []
	for agent: SimAgent in order:
		listed.append(names[agent.id])
	# People of one rank go by ID (the order they were added in above).
	assert_eq(listed, ["food in hand", "staff+way", "seat-walker+way", "leaver+way",
		"seat-walker at the door+way", "staff",
		"seat-walker", "eating", "inspector leaving", "leaver", "leaver at the door",
		"seat-walker at the door", "waiting+way", "waiting", "waiting at the door+way",
		"waiting at the door"] as Array[String])


## A crossing of one-cell aisles with the middle cell free and three people
## reaching for it: a leaver, a guest walking to a seat (lower ID) and a
## waiting guest holding right of way. Each was vetoed by one of the others,
## so the free cell stayed empty until the stall backstop (first taken at
## tick 121). Now exactly one of them is ahead of both others and steps.
func test_three_people_at_a_crossing_never_all_wait_for_the_free_cell() -> void:
	var world: SimWorld = _ascii_world(["###.###", "###.###", "E......", "###.###", "###.###"])
	var middle: Vector2i = Vector2i(3, 2)
	var walker: GuestWalker = _guest(world, Vector2i(3, 1), CustomerAgent.State.WALKING_TO_SEAT, Vector2i(3, 4))
	var waiting: GuestWalker = _guest(world, Vector2i(2, 2), CustomerAgent.State.QUEUED, Vector2i(6, 2))
	var leaver: GuestWalker = _guest(world, Vector2i(4, 2), CustomerAgent.State.LEAVING, Vector2i(0, 2))
	world.movement._right_of_way[waiting.id] = world.now + 1000
	assert_true(_advance(world))
	assert_not_null(world.movement._holder(world, middle), "somebody steps into the free cell at once")
	var done: Dictionary[int, bool] = {}
	for tick: int in 80:
		if not _advance(world):
			return
		if walker.cell == Vector2i(3, 4) and walker.move_progress == 0.0:
			done[walker.id] = true
		if leaver.cell == Vector2i(0, 2) and leaver.move_progress == 0.0:
			done[leaver.id] = true
	assert_eq(done.size(), 2, "the leaver is out and the guest is at its seat within 80 ticks")


# --- 2. Out before in, a seat before a wait ---------------------------------

## The starter shop with a one-cell way in, guests waiting in and around the
## door, one or two people leaving from the back and two seats coming free.
## Before: the guests given those seats could not get past the waiting crowd
## (the boxed-in waiting guests behind them kept asking them to step back, and
## waiting guests holding right of way took each free cell). With ten waiting
## and one leaving, one guest lost its table at the 200-tick seat walk limit,
## the other sat down after 209 ticks and the leaver took 215. With six
## waiting and two leaving: seated after 63 and 196, out after 100 and 150.
## With ten waiting and two leaving a guest lost its table as well.
func test_guests_with_tables_and_leavers_pass_a_waiting_crowd_at_a_narrow_door() -> void:
	for scenario: Array in [[10, 1], [6, 2]]:
		var label: String = "%d waiting, %d leaving" % scenario
		var result: Dictionary = _door_scenario(scenario[0], 2, scenario[1])
		assert_eq(int(result["lost_seat"]), 0, "nobody walking to a seat loses it (%s)" % label)
		assert_eq((result["seated"] as Array).size(), 2, "both guests with a table sit down (%s)" % label)
		for ticks: int in result["seated"]:
			assert_true(ticks <= 120, "seated after %d ticks, at most 120 (%s)" % [ticks, label])
		assert_eq((result["out"] as Array).size(), int(scenario[1]), "everyone leaving gets out (%s)" % label)
		for ticks: int in result["out"]:
			assert_true(ticks <= 120, "out after %d ticks, at most 120 (%s)" % [ticks, label])
	var crowded: Dictionary = _door_scenario(10, 2, 2)
	assert_eq(int(crowded["lost_seat"]), 0, "nobody walking to a seat loses it (10 waiting, 2 leaving)")
	assert_eq((crowded["seated"] as Array).size(), 2)
	assert_eq((crowded["out"] as Array).size(), 2)


## Who may ask whom to step back and open a gap (the cooperative vacancy).
func test_only_someone_going_somewhere_asks_for_room() -> void:
	var world: SimWorld = _ascii_world(["#########", "#.......#", "#.......#", "#.......#", "###EE####"])
	var movement: MovementCoordinator = world.movement
	var waiting: GuestWalker = _guest(world, Vector2i(2, 1), CustomerAgent.State.QUEUED)
	var other_waiting: GuestWalker = _guest(world, Vector2i(3, 1), CustomerAgent.State.QUEUED)
	var walker: GuestWalker = _guest(world, Vector2i(5, 1), CustomerAgent.State.WALKING_TO_SEAT)
	var walker_at_door: GuestWalker = _guest(world, Vector2i(4, 3), CustomerAgent.State.WALKING_TO_SEAT)
	var staff: StaffWalker = _staff(world, Vector2i(6, 1), false)
	var leaver: GuestWalker = _guest(world, Vector2i(7, 1), CustomerAgent.State.LEAVING)
	assert_false(movement._asks_for_room(world, waiting, walker), "a waiting guest never asks a guest with a table")
	assert_false(movement._asks_for_room(world, waiting, staff), "nor staff")
	assert_false(movement._asks_for_room(world, waiting, leaver), "nor someone leaving (#459)")
	assert_true(movement._asks_for_room(world, waiting, other_waiting), "waiting guests still make room for each other")
	assert_false(movement._asks_for_room(world, walker_at_door, leaver), "in the door lane a leaver never steps back")
	assert_true(movement._asks_for_room(world, walker, leaver), "further in a guest with a table may ask")
	assert_true(movement._asks_for_room(world, walker_at_door, staff), "and anyone going somewhere may ask staff")


## A queued guest with nowhere left to wait used to stop where it was, even
## part way through a step: it then held the cell it was stepping into for as
## long as the crowd lasted, and a leaver whose diagonal step needed that
## cell as a corner stood there until the stall backstop. A step already
## begun now finishes.
func test_a_waiting_guest_finishes_a_step_it_has_begun() -> void:
	var sim: RestaurantSim = _shop(true)
	var world: SimWorld = sim.world
	var guest: CustomerAgent = _customer(sim, Vector2i(5, 10))
	guest.state = CustomerAgent.State.QUEUED
	assert_true(guest.set_destination(world.grid, Vector2i(4, 10)))
	assert_eq(guest.step_move(world), SimAgent.MoveResult.MOVING)
	assert_true(guest.move_progress > 0.0, "premise: part way through a step")
	guest._wait_spot = guest.cell
	assert_true(guest._wait_spot_ok(world), "premise: it stands on its waiting spot, so it has no reason to walk")
	for tick: int in 8:
		guest._queue_inside(world)
	assert_eq(guest.cell, Vector2i(4, 10), "the step is finished, not held part way")
	assert_eq(guest.move_progress, 0.0)


# --- 3. A guest with a table waits on the street too ------------------------

## #468 item 1. A guest on the street is given a table while someone is on
## the way out of a shop with a one-cell way in. Before, only a guest without
## a table was held: this one walked in at once and met the leaver head-on.
func test_a_guest_with_a_table_lets_a_leaver_out_before_stepping_in() -> void:
	var sim: RestaurantSim = _shop(true)
	var world: SimWorld = sim.world
	# The street cell the people leaving from the west side do not head for.
	var entry: Vector2i = world.grid.entries()[1]
	var guest: CustomerAgent = _customer(sim, entry)
	var leaver: CustomerAgent = _customer(sim, Vector2i(3, 5))
	leaver._leave(world, sim, &"no_table")
	_free_seats(world, 1)
	# Won earlier, while stuck in the queue; a held guest gives it up.
	world.movement._right_of_way[guest.id] = world.now + 1000
	if not _tick(sim):
		return
	assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT, "premise: seated from the street")
	var held: int = 0
	for tick: int in 200:
		if not _tick(sim):
			return
		if leaver.state != CustomerAgent.State.LEAVING:
			break
		held += 1
		assert_eq(guest.cell, entry, "waits on the street while someone is leaving (tick %d)" % tick)
		assert_eq(guest.move_progress, 0.0)
		assert_eq(guest.why(), "Letting someone out before I go in")
		assert_true(guest.has_arrived(), "keeps no route while it waits")
		assert_false(world.movement._right_of_way.has(guest.id), "and no right of way from earlier")
	assert_eq(leaver.state, CustomerAgent.State.LEFT, "the leaver gets out")
	assert_true(held >= 20, "premise: the leaver took a while to reach the door (%d ticks)" % held)
	assert_true(guest._walk_wait <= 1, "the wait outside does not spend the seat walk's own limit")
	var seat: Vector2i = guest.seat_cell
	for tick: int in 120:
		if guest.state >= CustomerAgent.State.ORDERING:
			break
		if not _tick(sim):
			return
	assert_true(guest.state >= CustomerAgent.State.ORDERING and guest.state <= CustomerAgent.State.PAYING,
		"then walks in and sits down")
	assert_eq(guest.cell, seat, "at the table it was given on the street")


## The stall backstop can send a held guest with a table to a pocket inside
## (it has no route, so it counts as standing). From there it must plan to its
## seat again, not stand in the pocket until the seat walk runs out (#535 review).
func test_a_held_guest_sent_to_a_pocket_still_reaches_its_table() -> void:
	var sim: RestaurantSim = _shop(true)
	var world: SimWorld = sim.world
	var entry: Vector2i = world.grid.entries()[1]
	var guest: CustomerAgent = _customer(sim, entry)
	var leaver: CustomerAgent = _customer(sim, Vector2i(3, 5))
	leaver._leave(world, sim, &"no_table")
	_free_seats(world, 1)
	for tick: int in 5:
		if not _tick(sim):
			return
	assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT, "premise: seated from the street")
	assert_eq(guest.cell, entry, "premise: held on the street")
	var avoid: Dictionary[Vector2i, bool] = {}
	assert_true(world.movement._clear_to_pocket(world, guest, avoid), "premise: the backstop sends it aside")
	var seat: Vector2i = guest.seat_cell
	# About 20 ticks to the pocket and about 20 more on to the seat; without
	# the re-plan it stood in the pocket for about 100 ticks.
	for tick: int in 60:
		if guest.state >= CustomerAgent.State.ORDERING:
			break
		if not _tick(sim):
			return
	assert_true(guest.state >= CustomerAgent.State.ORDERING and guest.state <= CustomerAgent.State.PAYING,
		"the guest sits down rather than waiting in the pocket")
	assert_eq(guest.cell, seat, "at its own table")


## The hold is bounded like a queued guest's: door_hold_max_ticks, however
## many people keep leaving. A wide door never holds anyone this way.
func test_the_hold_on_a_guest_with_a_table_has_its_limit_and_spares_wide_doors() -> void:
	var sim: RestaurantSim = _shop(true)
	var world: SimWorld = sim.world
	# The street cell the people leaving from the west side do not head for.
	var entry: Vector2i = world.grid.entries()[1]
	var guest: CustomerAgent = _customer(sim, entry)
	_free_seats(world, 1)
	var limit: int = world.movement_tuning.door_hold_max_ticks
	# A busy shop: before one leaver is out, the next one gets up.
	var stayed: bool = true
	var stalled: bool = false
	for tick: int in limit:
		if tick % 30 == 0:
			_customer(sim, Vector2i(3, 5))._leave(world, sim, &"no_table")
		if not _tick(sim):
			return
		stayed = stayed and guest.cell == entry and guest.move_progress == 0.0
		# The stall backstop must not count the wait: from 120 ticks it would
		# grant right of way, and from 450 send the guest home. (A record of
		# one tick exists between being seated and the first held tick.)
		stalled = stalled or (world.movement._stall.has(guest.id) \
			and world.now - int(world.movement._stall[guest.id]["since"]) > 2)
	assert_eq(guest.state, CustomerAgent.State.WALKING_TO_SEAT, "still has its table")
	assert_true(stayed, "held on the street for the whole limit while people keep leaving")
	assert_false(stalled, "and never counted as stuck while held")
	assert_true(world.movement.door_counterflow(world), "premise: someone is still leaving")
	for tick: int in 40:
		if guest.cell != entry:
			break
		if tick % 30 == 0:
			_customer(sim, Vector2i(3, 5))._leave(world, sim, &"no_table")
		if not _tick(sim):
			return
	assert_ne(guest.cell, entry, "and steps in once the limit is over, leavers or not")
	for tick: int in 200:
		if guest.state >= CustomerAgent.State.ORDERING:
			break
		if not _tick(sim):
			return
	assert_true(guest.state >= CustomerAgent.State.ORDERING and guest.state <= CustomerAgent.State.PAYING,
		"then sits down: the long wait did not send it home (state %d, %s)" % [guest.state, guest.leave_reason])
	var wide: RestaurantSim = _shop(false)
	var arrival: CustomerAgent = _customer(wide, wide.world.grid.entries()[0])
	var going: CustomerAgent = _customer(wide, Vector2i(3, 5))
	going._leave(wide.world, wide, &"no_table")
	_free_seats(wide.world, 1)
	for tick: int in 8:
		if not _tick(wide):
			return
	assert_eq(arrival.state, CustomerAgent.State.WALKING_TO_SEAT)
	assert_ne(arrival.cell, wide.world.grid.entries()[0], "a wide door: walks straight in")


# --- 4. The line out, and waiting guests who cannot step aside --------------

## Two people leave the narrow-door shop while two guests wait beside the way
## in. Before: the leaver with the lower ID asked the leaver ahead of it to
## step back out of its diagonal corner, a waiting guest walked into the cell
## that opened, the leaver came back, and the three went round like that
## until the stall backstop: 148 and 156 ticks to get out.
func test_two_leavers_get_out_past_guests_waiting_beside_a_narrow_door() -> void:
	var result: Dictionary = _door_scenario(2, 0, 2)
	assert_eq((result["out"] as Array).size(), 2, "both get out")
	for ticks: int in result["out"]:
		assert_true(ticks <= 115, "out after %d ticks, at most 115" % ticks)


func test_a_leaver_waits_its_turn_behind_the_leaver_ahead() -> void:
	var world: SimWorld = _ascii_world(["E......", "......."])
	var movement: MovementCoordinator = world.movement
	var ahead: GuestWalker = _guest(world, Vector2i(3, 0), CustomerAgent.State.LEAVING, Vector2i(0, 0))
	var behind: GuestWalker = _guest(world, Vector2i(4, 0), CustomerAgent.State.LEAVING, Vector2i(0, 0))
	var oncoming: GuestWalker = _guest(world, Vector2i(2, 0), CustomerAgent.State.LEAVING, Vector2i(6, 0))
	var walker: GuestWalker = _guest(world, Vector2i(5, 0), CustomerAgent.State.WALKING_TO_SEAT, Vector2i(0, 1))
	assert_true(movement._behind_in_line_out(behind, ahead), "behind someone going the same way out")
	assert_false(movement._behind_in_line_out(ahead, oncoming), "a head-on is not a line: one of them yields")
	assert_false(movement._behind_in_line_out(walker, behind), "only between people who are leaving")
	assert_false(movement._behind_in_line_out(behind, walker))
	# A diagonal step needs both corner cells: a leaver in one of them is in its way.
	var cutting: GuestWalker = _guest(world, Vector2i(5, 1), CustomerAgent.State.LEAVING, Vector2i(4, 0))
	assert_true(world.movement._step_cells(cutting.cell, cutting.next_cell()).has(walker.cell), "premise: a corner cell")
	var in_corner: GuestWalker = _guest(world, Vector2i(4, 1), CustomerAgent.State.LEAVING, Vector2i(0, 1))
	assert_true(movement._behind_in_line_out(cutting, in_corner), "the leaver in its corner is going its own way")
	assert_false(movement._behind_in_line_out(in_corner, cutting), "the one cutting the corner comes through its cell")
	var stopped: GuestWalker = _guest(world, Vector2i(6, 1), CustomerAgent.State.LEAVING)
	assert_true(stopped.has_arrived())
	assert_true(movement._behind_in_line_out(cutting, stopped), "a leaver between routes is still ahead in the line")


## A one-cell corridor to the door with two waiting guests standing in it,
## short of the door lane, and someone leaving behind them. The first is
## boxed in between the other two and cannot step aside. Before, the leaver
## only swapped past waiting guests at the lane itself, so here it stood until
## the stall backstop (not out within these 120 ticks).
func test_a_leaver_swaps_past_boxed_in_waiting_guests_short_of_the_door() -> void:
	var world: SimWorld = _ascii_world(["E........"])
	assert_false(world.movement.in_door_lane(world, Vector2i(3, 0)), "premise: beyond the door lane")
	_guest(world, Vector2i(3, 0), CustomerAgent.State.QUEUED)
	var boxed: GuestWalker = _guest(world, Vector2i(4, 0), CustomerAgent.State.QUEUED)
	var leaver: GuestWalker = _guest(world, Vector2i(5, 0), CustomerAgent.State.LEAVING, Vector2i(0, 0))
	assert_eq(world.movement._yield(world, boxed, leaver), MovementCoordinator.YieldAttempt.NO_POCKET,
		"premise: the guest in the leaver's way cannot step aside")
	var out: int = -1
	for tick: int in 120:
		if not _advance(world):
			return
		if leaver.cell == Vector2i(0, 0) and leaver.move_progress == 0.0:
			out = tick + 1
			break
	assert_true(out > 0, "the leaver reaches the street within 120 ticks")
	assert_true(int(world.movement.escape_counts.get(&"counterflow", 0)) >= 1, "by swapping past them")


## A guest walking to a seat is met in the door lane by someone leaving, with
## the street cell behind it taken: it cannot step aside. Before, the leaver
## (who goes first here on its lower ID) stepped back to open a gap, and the
## doorway filled up behind the guest; a swap was only for guests without a
## table. Now the leaver holds its ground and swaps past.
func test_a_leaver_swaps_past_a_boxed_in_guest_with_a_table_in_the_door_lane() -> void:
	var world: SimWorld = _ascii_world(["E....."])
	assert_true(world.movement.in_door_lane(world, Vector2i(1, 0)))
	var leaver: GuestWalker = _guest(world, Vector2i(2, 0), CustomerAgent.State.ARRIVING)
	_guest(world, Vector2i(0, 0), CustomerAgent.State.QUEUED)
	var walker: GuestWalker = _guest(world, Vector2i(1, 0), CustomerAgent.State.WALKING_TO_SEAT, Vector2i(5, 0))
	leaver.state = CustomerAgent.State.LEAVING
	assert_true(leaver.set_destination(world.grid, Vector2i(0, 0)))
	var furthest: int = leaver.cell.x
	for tick: int in 40:
		if not _advance(world):
			return
		furthest = maxi(furthest, leaver.cell.x)
		if leaver.cell.x < walker.cell.x:
			break
	assert_eq(furthest, 2, "the leaver never steps back from the door")
	assert_true(leaver.cell.x < walker.cell.x, "and is past the guest within 40 ticks")
	assert_true(int(world.movement.escape_counts.get(&"counterflow", 0)) >= 1, "by swapping")


# --- 5. Service only ---------------------------------------------------------

## #468 item 2. The holds and the swap keep their promises with timers that
## only run in service: outside it a held guest's wait started again every
## tick (it never ran out) and nothing stopped two people swapping straight
## back. So outside service the door rules do not apply at all.
func test_the_door_rules_only_apply_during_service() -> void:
	var sim: RestaurantSim = _shop(true, false)
	var world: SimWorld = sim.world
	assert_eq(world.clock.phase, SimClock.Phase.MORNING)
	var entries: Array[Vector2i] = world.grid.entries()
	var waiting: CustomerAgent = _customer(sim, entries[0])
	waiting.state = CustomerAgent.State.QUEUED
	var leaver: CustomerAgent = _customer(sim, Vector2i(3, 5))
	leaver.state = CustomerAgent.State.LEAVING
	assert_true(world.movement.door_counterflow(world), "premise: someone is leaving a narrow-door shop")
	assert_false(world.movement.hold_at_door(world, waiting), "no hold on a queued guest outside service")
	assert_false(world.movement.hold_at_door(world, waiting, true), "nor on a guest with a table")
	assert_true(world.movement._held_since.is_empty(), "and no timer is started")
	assert_true(_customer(sim, entries[1]).movement_admitted, "an arrival is not kept pending either")
	assert_true(world.clock.start_service())
	assert_true(world.movement.hold_at_door(world, waiting), "in service the hold applies")
	var corridor: SimWorld = _ascii_world(["E.."], false)
	_guest(corridor, Vector2i(0, 0), CustomerAgent.State.QUEUED)
	var boxed: GuestWalker = _guest(corridor, Vector2i(1, 0), CustomerAgent.State.QUEUED)
	var going: GuestWalker = _guest(corridor, Vector2i(2, 0), CustomerAgent.State.LEAVING, Vector2i(0, 0))
	for tick: int in 40:
		if not _advance(corridor):
			return
	assert_eq(int(corridor.movement.escape_counts.get(&"counterflow", 0)), 0, "no swap outside service")
	assert_eq(going.cell, Vector2i(2, 0))
	assert_true(corridor.clock.start_service())
	for tick: int in 40:
		if not _advance(corridor):
			return
	assert_true(int(corridor.movement.escape_counts.get(&"counterflow", 0)) >= 1, "in service the leaver swaps past")
	assert_eq(boxed.cell, Vector2i(2, 0), "with the boxed-in guest")


# --- Fixtures ----------------------------------------------------------------

func _ascii_world(rows: Array[String], open: bool = true) -> SimWorld:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(rows)))
	if open:
		assert_true(world.clock.start_service())
	return world


## Added while still arriving (so nobody is kept on the street by a leaver
## added earlier), then given its state and, if any, a place to go.
func _guest(world: SimWorld, at: Vector2i, state: int, goal: Vector2i = SimGrid.NO_CELL) -> GuestWalker:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 468
	var guest: GuestWalker = GuestWalker.new(RestaurantSim.new(), random)
	guest.cell = at
	world.add_agent(guest)
	assert_true(guest.movement_admitted, "fixture guest admitted at %s" % at)
	guest.state = state as CustomerAgent.State
	if goal != SimGrid.NO_CELL:
		assert_true(guest.set_destination(world.grid, goal))
	return guest


func _staff(world: SimWorld, at: Vector2i, carrying: bool) -> StaffWalker:
	var staff: StaffWalker = StaffWalker.new(&"server", 3)
	staff.cell = at
	world.add_agent(staff)
	if carrying:
		var job: SimTask = SimTask.new(&"deliver", &"server")
		job.payload["carried_count"] = 1
		world.board.post(job, world.now)
		assert_true(world.board.claim(job, staff.id, world.now))
		staff.task = job
		assert_true(staff.carries_food())
	return staff


func _advance(world: SimWorld) -> bool:
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	var problem: String = MovementInvariants.problem(world, before)
	assert_eq(problem, "", "tick %d keeps movement safety" % world.now)
	return problem.is_empty()


func _tick(sim: RestaurantSim) -> bool:
	var before: Dictionary = MovementInvariants.capture(sim.world)
	sim.advance()
	var problem: String = MovementInvariants.problem(sim.world, before)
	assert_eq(problem, "", "tick %d keeps movement safety" % sim.world.now)
	return problem.is_empty()


## The starter shop with every dining seat held by a stand-in, so arrivals
## queue; `narrow` walls in a one-cell way in, (7, 11), behind its door.
func _shop(narrow: bool, open: bool = true) -> RestaurantSim:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 305, errors, null, false)
	assert_eq(errors, [] as Array[String])
	sim.spawner.min_gap = 1000000
	sim.spawner.max_gap = 1000000
	sim.spawner.reset()
	_phantoms.clear()
	var holder: int = 900000
	for item: PlacedItem in sim.world.grid.items():
		for seat: Vector2i in item.seat_cells:
			holder += 1
			item.reserve(seat, holder)
			_phantoms[seat] = holder
	if open:
		assert_true(sim.world.clock.start_service())
	if narrow:
		var walls: Dictionary[Vector2i, int] = {Vector2i(7, 10): SimGrid.Terrain.WALL, Vector2i(8, 10): SimGrid.Terrain.WALL}
		for x: int in range(9, 15):
			walls[Vector2i(x, 11)] = SimGrid.Terrain.WALL
		assert_true(sim.world.grid.set_terrains(walls))
		assert_true(sim.world.movement.narrow_way_in(sim.world))
	return sim


func _customer(sim: RestaurantSim, cell: Vector2i) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 305 + sim.world.agents.size()
	return sim.add_customer(cell, random)


## Lets go of `count` of the stand-ins' seats, in table order.
func _free_seats(world: SimWorld, count: int) -> void:
	var freed: int = 0
	for item: PlacedItem in world.grid.items():
		for seat: Vector2i in item.seat_cells:
			if freed < count and item.reserved_by(seat) == int(_phantoms.get(seat, -1)):
				item.release(seat, _phantoms[seat])
				freed += 1
	assert_eq(freed, count)


## `crowd` patient guests trickle in at the narrow door and settle; then
## `leavers` people start to leave from the back of the room and `free` seats
## come free. Returns the ticks each leaver took to get out ("out"), the ticks
## each guest took to sit down ("seated") and how many guests walking to a
## seat lost it again ("lost_seat").
func _door_scenario(crowd: int, free: int, leavers: int) -> Dictionary:
	var sim: RestaurantSim = _shop(true)
	var world: SimWorld = sim.world
	var entries: Array[Vector2i] = world.grid.entries()
	var guests: Array[CustomerAgent] = []
	for index: int in crowd:
		var guest: CustomerAgent = _customer(sim, entries[index % entries.size()])
		guest.queue_patience = 1000000
		guests.append(guest)
		for tick: int in 12:
			sim.advance()
	for tick: int in SETTLE_TICKS:
		sim.advance()
	var going: Array[CustomerAgent] = []
	for spot: Vector2i in [Vector2i(3, 5), Vector2i(11, 5)].slice(0, leavers):
		going.append(_customer(sim, spot))
	for leaver: CustomerAgent in going:
		leaver._leave(world, sim, &"no_table")
	_free_seats(world, free)
	var out: Dictionary[int, int] = {}
	var seated: Dictionary[int, int] = {}
	var walking: Dictionary[int, bool] = {}
	var lost: int = 0
	for tick: int in 400:
		if not _tick(sim):
			break
		for leaver: CustomerAgent in going:
			if world.agent(leaver.id) == null and not out.has(leaver.id):
				out[leaver.id] = tick + 1
		for guest: CustomerAgent in guests:
			if guest.state == CustomerAgent.State.WALKING_TO_SEAT:
				walking[guest.id] = true
			elif guest.state <= CustomerAgent.State.QUEUED and walking.has(guest.id):
				walking.erase(guest.id)
				lost += 1
			elif guest.state >= CustomerAgent.State.ORDERING and not seated.has(guest.id):
				seated[guest.id] = tick + 1
		if out.size() == going.size() and seated.size() >= mini(free, crowd):
			break
	return {"out": out.values(), "seated": seated.values(), "lost_seat": lost}
