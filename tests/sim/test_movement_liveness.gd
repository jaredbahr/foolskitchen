extends TestCase
## #306: nobody may stay stuck forever. Each fixture deadlocked permanently
## before the liveness backstop; each now resolves through real claimed steps
## (no teleports), and every tick keeps the movement safety invariants.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _previous: Dictionary = {}


class Walker extends SimAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


class StaffWalker extends StaffAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


class GuestWalker extends CustomerAgent:
	var gave_up_at: int = -1

	func tick(world: SimWorld) -> void:
		step_move(world)

	func give_up_blocked(world: SimWorld) -> void:
		if gave_up_at < 0:
			gave_up_at = world.now

	## No restaurant behind this fixture: movement pauses run no visit logic.
	func maintain_movement_pause(_world: SimWorld) -> void:
		pass


class InspectorWalker extends InspectorAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


func after_each() -> void:
	_previous.clear()
	GameState.new_run(1)


## A boxed blocker: S cannot pass B, B is boxed in by S and C, and C blocks
## nobody's next step directly, so the old local rules never asked C to move.
func test_people_between_a_boxed_blocker_and_free_floor_clear_first() -> void:
	var world: SimWorld = _service_world([".......", "##.####", "##.####"])
	var stuck: Walker = _walker(world, Vector2i(0, 0), Vector2i(6, 0))
	var boxed: SimAgent = _standing(world, Vector2i(1, 0))
	var between: SimAgent = _standing(world, Vector2i(2, 0))
	var moved: Dictionary[int, bool] = {}
	for tick: int in 600:
		if not _advance(world):
			return
		for agent: SimAgent in [boxed, between]:
			if agent.cell != Vector2i(1, 0) and agent.cell != Vector2i(2, 0):
				moved[agent.id] = true
		if stuck.cell == Vector2i(6, 0):
			break
	assert_eq(stuck.cell, Vector2i(6, 0), "the stuck person reaches its real goal")
	assert_true(moved.has(between.id), "the person between steps into the side aisle")
	assert_true(world.now < world.movement_tuning.squeeze_after_ticks,
		"clearing resolves it before any squeeze (%d ticks)" % world.now)
	assert_true(int(world.movement.escape_counts.get(&"line", 0)) >= 1)


## A dead end with no free cell for the guest: the worker squeezes past over
## one ordinary step (drawn bowing sideways), never teleporting.
func test_staff_squeezes_past_a_stationary_guest_in_a_dead_end() -> void:
	var world: SimWorld = _service_world(["...."])
	var guest: GuestWalker = _guest(world, Vector2i(3, 0))
	var staff: StaffWalker = StaffWalker.new(&"server", 3)
	staff.cell = Vector2i(0, 0)
	world.add_agent(staff)
	assert_true(staff.set_destination(world.grid, Vector2i(3, 0)))
	var squeeze_ticks: int = 0
	var bowed: bool = false
	for tick: int in 800:
		if not _advance(world):
			return
		if world.movement.is_squeezing(staff.id):
			squeeze_ticks += 1
			assert_true(world.movement.is_squeezing(guest.id), "both partners squeeze together")
			assert_eq(staff.move_progress, guest.move_progress, "they cross in lockstep")
			var straight: Vector3 = GridMath.cell_to_world(staff.cell).lerp(
				GridMath.cell_to_world(staff.next_cell()), staff.move_progress)
			bowed = bowed or not staff.movement_position().is_equal_approx(straight)
		if staff.cell == Vector2i(3, 0):
			break
	assert_eq(staff.cell, Vector2i(3, 0), "the worker gets through")
	assert_eq(guest.cell, Vector2i(2, 0), "the guest swapped one cell, not teleported away")
	assert_eq(squeeze_ticks, 3, "the swap takes one ordinary 4-tick step (3 partial ticks)")
	assert_true(bowed, "the squeeze is drawn passing to the side, never overlapping")
	assert_eq(int(world.movement.escape_counts.get(&"squeeze", 0)), 1)
	var tuning: MovementTuning = world.movement_tuning
	assert_true(world.now <= tuning.squeeze_after_ticks + tuning.escape_after_ticks,
		"squeezes soon after the limit (tick %d)" % world.now)
	assert_eq(guest.gave_up_at, -1)


## A leaving guest still on its own stool (placed in the only way out) can be
## passed only over that seat: the partner takes the booking while it stands
## there, so nobody ever stands on a seat that is not theirs.
func test_a_leaving_guest_on_its_own_seat_hands_the_seat_to_its_squeeze_partner() -> void:
	var world: SimWorld = _service_world(["...."], false)
	var stool: PlacedItem = world.grid.place(Vector2i.ONE, Vector2i(1, 0), 0, false,
		[] as Array[Vector2i], [Vector2i.ZERO] as Array[Vector2i])
	assert_not_null(stool)
	var leaving: GuestWalker = _guest(world, Vector2i(1, 0))
	assert_true(stool.reserve(Vector2i(1, 0), leaving.id))
	var waiting: GuestWalker = _guest(world, Vector2i(0, 0))
	assert_true(world.clock.start_service())
	leaving.state = CustomerAgent.State.LEAVING
	assert_true(leaving.set_destination(world.grid, Vector2i(0, 0)))
	var handed: bool = false
	for tick: int in 800:
		if not _advance(world):
			return
		handed = handed or stool.reserved_by(Vector2i(1, 0)) == waiting.id
		if leaving.cell == Vector2i(0, 0):
			break
	assert_eq(leaving.cell, Vector2i(0, 0), "the leaving guest gets out")
	assert_true(handed, "the waiting guest held the stool while standing on it")
	assert_eq(int(world.movement.escape_counts.get(&"squeeze", 0)), 1)


## Nothing can clear a guest's way and a guest who is not leaving never
## squeezes: it gives up at the authored limit instead of waiting forever.
func test_a_guest_who_still_cannot_move_gives_up() -> void:
	var world: SimWorld = _service_world(["...."])
	var guest: GuestWalker = _guest(world, Vector2i(0, 0))
	guest.state = CustomerAgent.State.WALKING_TO_SEAT
	_standing(world, Vector2i(1, 0))
	assert_true(guest.set_destination(world.grid, Vector2i(3, 0)))
	for tick: int in 700:
		if not _advance(world):
			return
		if guest.gave_up_at >= 0:
			break
	var tuning: MovementTuning = world.movement_tuning
	assert_true(guest.gave_up_at > tuning.give_up_after_ticks \
			and guest.gave_up_at <= tuning.give_up_after_ticks + tuning.escape_after_ticks,
		"gives up soon after the limit, never waiting forever (at %d)" % guest.gave_up_at)
	assert_eq(int(world.movement.escape_counts.get(&"squeeze", 0)), 0, "a guest on its way in never squeezes")


## The real departure: a give-up is an ordinary visible leave with its reason.
func test_giving_up_is_a_counted_departure_through_the_door() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 306, errors, null, false)
	assert_eq(errors, [] as Array[String])
	sim.spawner.min_gap = 1000000
	sim.spawner.max_gap = 1000000
	sim.spawner.reset()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 306
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random)
	assert_true(sim.world.clock.start_service())
	sim.advance()
	guest.give_up_blocked(sim.world)
	assert_eq(guest.state, CustomerAgent.State.LEAVING)
	assert_eq(guest.leave_reason, &"no_way_through")
	for tick: int in 200:
		sim.advance()
		if sim.world.agent(guest.id) == null:
			break
	assert_null(sim.world.agent(guest.id), "walks out like any leaving guest")
	assert_eq(int(sim.leave_reasons_today.get(&"no_way_through", 0)), 1)
	assert_eq(CustomerAgent.player_reason(&"no_way_through"), &"no_way_through", "shown as-is to the player")


## A stop whose edge never started (an idle busser stepping off a cleaned
## seat) used to wait forever on a diagonal whose corner a seated guest holds.
## It now stands still and plans afresh.
func test_a_never_started_stop_on_a_blocked_diagonal_is_abandoned() -> void:
	var world: SimWorld = _service_world(["..", ".."], false)
	var seat: PlacedItem = world.grid.place(Vector2i.ONE, Vector2i(1, 0), 0, false,
		[] as Array[Vector2i], [Vector2i.ZERO] as Array[Vector2i])
	assert_not_null(seat)
	var seated: GuestWalker = _guest(world, Vector2i(0, 1))
	seated.state = CustomerAgent.State.ORDERING
	seated.table_item_id = seat.id
	seated.seat_cell = Vector2i(1, 0)
	assert_true(seat.reserve(Vector2i(1, 0), seated.id))
	assert_true(world.reset_agent_position(seated, Vector2i(1, 0)), "staged before service")
	var worker: StaffWalker = StaffWalker.new(&"server", 3)
	worker.cell = Vector2i(0, 0)
	world.add_agent(worker)
	assert_true(world.clock.start_service())
	worker.install_movement_route([Vector2i(0, 0), Vector2i(1, 1)] as Array[Vector2i])
	world.movement.stop_motion(worker.id)
	# The pre-fix step itself breaks the corner rule, so this fixture cannot
	# pass the per-tick safety check; it only proves the wait is bounded.
	for tick: int in 60:
		world.advance()
	assert_false(world.movement.is_stopping(worker.id), "the stop does not wait forever")
	assert_true(worker.has_arrived())
	assert_eq(worker.cell, Vector2i(0, 0), "never cuts past the seated guest's corner")
	assert_eq(seated.cell, Vector2i(1, 0), "the seated guest is never moved")


## A guest walking to the restroom used to be protected from yielding like a
## seated guest, so a worker meeting one in a one-cell aisle waited forever.
func test_a_guest_walking_to_the_restroom_yields_like_anyone_else() -> void:
	var world: SimWorld = _service_world([".......", "###.###"])
	var guest: GuestWalker = _guest(world, Vector2i(5, 0))
	guest.state = CustomerAgent.State.WAITING_FOOD
	guest.seat_cell = Vector2i(6, 0)
	guest.restroom = CustomerAgent.Restroom.WALKING
	assert_true(guest.set_destination(world.grid, Vector2i(1, 0)))
	var staff: StaffWalker = StaffWalker.new(&"server", 3)
	staff.cell = Vector2i(0, 0)
	world.add_agent(staff)
	assert_true(staff.set_destination(world.grid, Vector2i(6, 0)))
	var yielded: bool = false
	for tick: int in 400:
		if not _advance(world):
			return
		# Before the liveness backstop could act: the ordinary yield rules.
		yielded = yielded or (world.movement.is_yielding(guest.id) \
			and world.now < world.movement_tuning.escape_after_ticks)
		if staff.cell == Vector2i(6, 0) and guest.cell == Vector2i(1, 0):
			break
	assert_true(yielded, "the guest off their seat takes an ordinary sidestep")
	assert_eq(staff.cell, Vector2i(6, 0), "the worker gets through")
	assert_eq(guest.cell, Vector2i(1, 0), "and so does the guest")


## A stuck person given right of way keeps the cells of the step it waits
## for: a passer-by may not slip into one, and a passer-by kept out cannot
## win the cell from the person who must clear it (that pair locked forever).
func test_a_held_way_keeps_passers_out_but_lets_the_blocker_clear() -> void:
	var world: SimWorld = _service_world(["...", "...", "..."])
	var passer: Walker = _walker(world, Vector2i(0, 0), Vector2i(1, 0))
	var blocker: Walker = _walker(world, Vector2i(1, 1), Vector2i(1, 0))
	var stuck: Walker = _walker(world, Vector2i(2, 0), Vector2i(1, 1))
	assert_true(passer.id < blocker.id, "the passer would win an ordinary lowest-ID tie")
	# What an escape grants: right of way and the held way.
	world.movement._right_of_way[stuck.id] = 1000000
	world.movement._way_holder = stuck.id
	var passer_entered: bool = false
	for tick: int in 40:
		if not _advance(world):
			return
		passer_entered = passer_entered or passer.cell == Vector2i(1, 0) \
			or (passer.move_progress > 0.0 and passer.next_cell() == Vector2i(1, 0))
		if blocker.cell == Vector2i(1, 0):
			break
	assert_false(passer_entered, "nobody slips into a held corner")
	assert_eq(blocker.cell, Vector2i(1, 0), "the person standing in the held step clears it")


## The swap finishes inside the first partner's turn; the later partner has
## then already moved this tick and only holds, instead of starting its next
## step early.
func test_both_partners_hold_on_the_tick_their_squeeze_finishes() -> void:
	# A guest at its place never takes an ordinary sidestep, and every free
	# cell is on the worker's route: only the squeeze can resolve this.
	var world: SimWorld = _service_world(["....."])
	var guest: GuestWalker = _guest(world, Vector2i(3, 0))
	guest.state = CustomerAgent.State.ORDERING
	guest.seat_cell = Vector2i(3, 0)
	var staff: StaffWalker = StaffWalker.new(&"server", 3)
	staff.cell = Vector2i(0, 0)
	world.add_agent(staff)
	assert_true(guest.id < staff.id, "the guest's turn completes the swap")
	assert_true(staff.set_destination(world.grid, Vector2i(4, 0)))
	var was_squeezing: bool = false
	var finished: bool = false
	for tick: int in 800:
		if not _advance(world):
			return
		var squeezing: bool = world.movement.is_squeezing(staff.id)
		if was_squeezing and not squeezing:
			finished = true
			assert_eq(staff.cell, Vector2i(3, 0), "the swap is done")
			assert_eq(staff.move_progress, 0.0, "the worker does not start its next step in the same tick")
			assert_eq(guest.move_progress, 0.0)
		was_squeezing = squeezing
		if staff.cell == Vector2i(4, 0):
			break
	assert_true(finished, "the worker squeezed past")
	assert_eq(staff.cell, Vector2i(4, 0), "and then walked on")


## A pocket is the nearest free floor cell clear of the door lane and of
## station work cells, so an idle worker is not parked where work happens.
## Only when nothing else is free does it take such a cell.
func test_a_pocket_prefers_cells_clear_of_work_spots() -> void:
	var world: SimWorld = _service_world(["...", "..."])
	var station: PlacedItem = world.grid.place(Vector2i.ONE, Vector2i(1, 0), 0, false,
		[Vector2i.ZERO] as Array[Vector2i])
	assert_not_null(station)
	assert_true(station.work_cells.has(Vector2i(1, 0)))
	var idle: SimAgent = _standing(world, Vector2i(0, 0))
	var none: Dictionary[Vector2i, bool] = {}
	var path: Array[Vector2i] = world.movement._pocket_path(world, idle, none)
	assert_eq(path, [Vector2i(0, 0), Vector2i(0, 1)] as Array[Vector2i], "skips the nearer work cell")
	var off_route: Dictionary[Vector2i, bool] = {Vector2i(0, 1): true, Vector2i(1, 1): true,
		Vector2i(2, 0): true, Vector2i(2, 1): true}
	path = world.movement._pocket_path(world, idle, off_route)
	assert_eq(path, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], "falls back to it when nothing else is free")
	# The work-cell set is cached per grid version: a station placed later counts.
	assert_true(world.grid.place(Vector2i.ONE, Vector2i(0, 1), 0, false, [Vector2i.ZERO] as Array[Vector2i]) != null)
	assert_true(world.movement._work_cells(world).has(Vector2i(0, 1)), "the cache rebuilds after an edit")


## A leaving guest drops its path whenever a step is blocked, so between
## tries it looks arrived. The watchdog still follows it and leads it to the
## nearer street cell (in a doorway crowd it used to shuffle for good).
func test_a_leaving_guest_without_a_path_is_still_led_out() -> void:
	var world: SimWorld = _service_world(["E...", "#.##"])
	var leaving: GuestWalker = _guest(world, Vector2i(2, 0))
	leaving.state = CustomerAgent.State.LEAVING
	var standing: SimAgent = _standing(world, Vector2i(1, 0))
	assert_true(leaving.has_arrived(), "no path between tries")
	for tick: int in 400:
		if not _advance(world):
			return
		if leaving.cell == Vector2i(0, 0):
			break
	assert_eq(leaving.cell, Vector2i(0, 0), "reaches the street")
	assert_eq(standing.cell, Vector2i(1, 1), "the person in the way steps aside, not out of the door")
	assert_true(world.now <= world.movement_tuning.escape_after_ticks + 20,
		"led out at the first escape (tick %d)" % world.now)


## The health inspector on its way out is followed the same way, and never
## sent home by the guest give-up.
func test_a_leaving_inspector_without_a_path_is_led_out_too() -> void:
	var world: SimWorld = _service_world(["E...", "#.##"])
	var inspector: InspectorWalker = InspectorWalker.new()
	inspector.cell = Vector2i(2, 0)
	world.add_agent(inspector)
	inspector.state = InspectorAgent.State.LEAVING
	var standing: SimAgent = _standing(world, Vector2i(1, 0))
	for tick: int in 400:
		if not _advance(world):
			return
		if inspector.cell == Vector2i(0, 0):
			break
	assert_eq(inspector.cell, Vector2i(0, 0), "reaches the street")
	assert_eq(standing.cell, Vector2i(1, 1))
	assert_eq(int(world.movement.escape_counts.get(&"give_up", 0)), 0)


## In a crowd heading out, two leaving guests swapping gets neither closer to
## the street (it only reset their stall counts and churned): a leaving guest
## squeezes past someone coming in or standing about, and past another leaver
## only in a real head-on (that leaver's own way out runs through its cell).
func test_a_leaving_guest_squeezes_past_another_leaver_only_head_on() -> void:
	var world: SimWorld = _service_world(["E..."])
	var first: GuestWalker = _guest(world, Vector2i(1, 0))
	var second: GuestWalker = _guest(world, Vector2i(2, 0))
	var arriving: GuestWalker = _guest(world, Vector2i(3, 0))
	first.state = CustomerAgent.State.LEAVING
	second.state = CustomerAgent.State.LEAVING
	arriving.state = CustomerAgent.State.QUEUED
	assert_false(world.movement._may_squeeze(world, second, first), "never past the one ahead in the same line")
	assert_true(world.movement._may_squeeze(world, second, arriving))
	assert_false(world.movement._may_squeeze(world, arriving, second), "only the one leaving squeezes")
	# Head-on: the inspector keeps to the far door, the guest to the near one.
	var corridor: SimWorld = _service_world(["E......E"])
	var inspector: InspectorWalker = InspectorWalker.new()
	inspector.cell = Vector2i(2, 0)
	corridor.add_agent(inspector)
	inspector.state = InspectorAgent.State.LEAVING
	inspector._avoid_entry = Vector2i(0, 0)
	var guest: GuestWalker = _guest(corridor, Vector2i(3, 0))
	guest.state = CustomerAgent.State.LEAVING
	assert_true(corridor.movement._may_squeeze(corridor, inspector, guest), "both get closer to their door")
	assert_true(corridor.movement._may_squeeze(corridor, guest, inspector))


## A line of guests on the way out: the one at the back cannot be helped by
## moving the leavers ahead of it, so its escape (and its wait) goes to the
## head of the line, which squeezes past whoever really blocks the door.
func test_an_escape_at_the_back_of_a_leaving_line_goes_to_its_head() -> void:
	var world: SimWorld = _service_world(["E...."])
	var queued: GuestWalker = _guest(world, Vector2i(1, 0))
	var head: GuestWalker = _guest(world, Vector2i(2, 0))
	var back: GuestWalker = _guest(world, Vector2i(3, 0))
	queued.state = CustomerAgent.State.QUEUED
	head.state = CustomerAgent.State.LEAVING
	back.state = CustomerAgent.State.LEAVING
	var outcome: int = world.movement._escape(world, back, world.movement_tuning.squeeze_after_ticks)
	assert_eq(outcome, MovementCoordinator.ESCAPE_SQUEEZED, "the next swap down the line is due soon")
	assert_eq(int(world.movement.escape_counts.get(&"line_head", 0)), 1)
	assert_true(world.movement.is_squeezing(head.id), "the head of the line squeezes past")
	assert_true(world.movement.is_squeezing(queued.id))
	assert_false(world.movement.is_squeezing(back.id), "the back waits its turn")


## The head of a leaving line is mid-step: nothing is handed on this tick;
## the back looks again next tick, but that counts as one of the tick's
## searched tries, so a long line is not searched without limit.
func test_an_escape_handed_to_a_moving_head_waits_for_it() -> void:
	var world: SimWorld = _service_world(["E...."])
	var queued: GuestWalker = _guest(world, Vector2i(1, 0))
	var head: GuestWalker = _guest(world, Vector2i(2, 0))
	var back: GuestWalker = _guest(world, Vector2i(3, 0))
	queued.state = CustomerAgent.State.QUEUED
	head.state = CustomerAgent.State.LEAVING
	back.state = CustomerAgent.State.LEAVING
	head.move_progress = 0.5
	var outcome: int = world.movement._escape(world, back, world.movement_tuning.squeeze_after_ticks)
	head.move_progress = 0.0
	assert_eq(outcome, MovementCoordinator.ESCAPE_WAITING)
	assert_eq(int(world.movement.escape_counts.get(&"line_head", 0)), 0, "nothing handed on")
	assert_false(world.movement.is_squeezing(queued.id))


## Every swap earns the quick retry, a corner swap too (in a doorway the way
## out turns: on an ordinary retry a leaving line in an edited shop stalled
## past 600 ticks), but the same two people never swap again within the
## cooldown, so nobody swaps back and forth.
func test_a_squeeze_is_retried_soon_but_pairs_cool_down() -> void:
	var world: SimWorld = _service_world(["..", ".."])
	var staff: StaffWalker = StaffWalker.new(&"server", 3)
	staff.cell = Vector2i(0, 0)
	world.add_agent(staff)
	var corner: GuestWalker = _guest(world, Vector2i(1, 0))
	_guest(world, Vector2i(0, 1))
	var route_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1)]
	var blockers: Array[SimAgent] = [corner]
	assert_eq(world.movement._try_squeeze(world, staff, route_cells, blockers), MovementCoordinator.ESCAPE_SQUEEZED,
		"a corner swap is retried soon too")
	var line: SimWorld = _service_world(["...."])
	var worker: StaffWalker = StaffWalker.new(&"server", 3)
	worker.cell = Vector2i(0, 0)
	line.add_agent(worker)
	var guest: GuestWalker = _guest(line, Vector2i(1, 0))
	var ahead: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var in_way: Array[SimAgent] = [guest]
	line.movement._pair_swapped[line.movement._pair(worker, guest)] = line.now
	assert_eq(line.movement._try_squeeze(line, worker, ahead, in_way), MovementCoordinator.ESCAPE_FUTILE,
		"no swap straight back")
	line.movement._pair_swapped.clear()
	assert_eq(line.movement._try_squeeze(line, worker, ahead, in_way), MovementCoordinator.ESCAPE_SQUEEZED,
		"once the cooldown is over they may swap")


## The inspector who gave up on one door after being blocked there is led to
## the other one, not back to the nearer door it avoids.
func test_the_backstop_keeps_the_inspector_off_the_door_it_avoids() -> void:
	var world: SimWorld = _service_world(["E......E"])
	var inspector: InspectorWalker = InspectorWalker.new()
	inspector.cell = Vector2i(2, 0)
	world.add_agent(inspector)
	inspector.state = InspectorAgent.State.LEAVING
	assert_eq(world.movement._escape_route(world, inspector).back(), Vector2i(0, 0), "the nearer door")
	inspector._avoid_entry = Vector2i(0, 0)
	assert_eq(world.movement._escape_route(world, inspector).back(), Vector2i(7, 0), "the door it chose")


## Let them out first: while someone on the way out has been stuck in the
## door lane for the escape limit, a guest arriving from the street waits
## outside (every lasting doorway crowd in the soak was arrivals stepping into
## a jammed door). A brisk exit never holds anyone up.
func test_arrivals_wait_outside_while_the_door_is_jammed_with_leavers() -> void:
	var world: SimWorld = _service_world(["E...."])
	var leaving: GuestWalker = _guest(world, Vector2i(1, 0))
	leaving.state = CustomerAgent.State.LEAVING
	assert_true(world.movement.in_door_lane(world, leaving.cell))
	var brisk: GuestWalker = _guest(world, Vector2i(0, 0))
	assert_false(world.pending_agents().has(brisk), "a leaver just passing holds nobody up")
	world.remove_agent(brisk)
	world.movement._stall[leaving.id] = {"goal": MovementCoordinator.EXIT_GOAL, "best": 1.0,
		"since": world.now - world.movement_tuning.escape_after_ticks, "next": world.now + 1000}
	var held: GuestWalker = _guest(world, Vector2i(0, 0))
	assert_true(world.pending_agents().has(held), "an arrival waits on the street while the door is jammed")
	world.movement._stall.erase(leaving.id)
	world.advance()
	assert_false(world.pending_agents().has(held), "and comes in once it clears")


## The hold has limits: waiting arrivals do not tick and nobody else would
## end the wait, so it lifts once the oldest arrival has waited
## door_hold_max_ticks, or once the jammed leaver reaches the give-up limit.
func test_the_arrival_hold_never_lasts_past_its_limits() -> void:
	var world: SimWorld = _service_world(["E...."])
	var leaving: GuestWalker = _guest(world, Vector2i(1, 0))
	leaving.state = CustomerAgent.State.LEAVING
	var tuning: MovementTuning = world.movement_tuning
	var jam: Callable = func(stalled: int) -> void:
		world.movement._stall[leaving.id] = {"goal": MovementCoordinator.EXIT_GOAL, "best": 1.0,
			"since": world.now - stalled, "next": world.now + 1000}
	jam.call(tuning.escape_after_ticks)
	var arriving: GuestWalker = _guest(world, Vector2i(0, 0))
	assert_true(world.pending_agents().has(arriving), "held while the door is jammed")
	world.now += tuning.door_hold_max_ticks - 1
	jam.call(tuning.escape_after_ticks)
	assert_false(world.movement.register_agent(world, arriving), "still held just before the limit")
	world.now += 1
	jam.call(tuning.escape_after_ticks)
	assert_true(world.movement.register_agent(world, arriving), "comes in at the limit")
	assert_true(arriving.movement_admitted)
	var fresh: SimWorld = _service_world(["E...."])
	var stuck: GuestWalker = _guest(fresh, Vector2i(1, 0))
	stuck.state = CustomerAgent.State.LEAVING
	fresh.movement._stall[stuck.id] = {"goal": MovementCoordinator.EXIT_GOAL, "best": 1.0,
		"since": fresh.now - fresh.movement_tuning.give_up_after_ticks, "next": fresh.now + 1000}
	var late: GuestWalker = _guest(fresh, Vector2i(0, 0))
	assert_false(fresh.pending_agents().has(late), "a jam past the give-up limit holds nobody")


## Nobody stands in the stuck person's shortest way: nobody is moved and no
## way is held, but the stalled person gets right of way, so it wins a free
## step that someone else reaches for at the same moment (#317: in a busy bar
## corridor that was the cell it kept losing). The turn passes on.
func test_an_escape_with_nobody_in_the_way_only_grants_right_of_way() -> void:
	var world: SimWorld = _service_world(["...."])
	var walker: Walker = _walker(world, Vector2i(0, 0), Vector2i(3, 0))
	var before: Array[Vector2i] = walker.path.duplicate()
	var outcome: int = world.movement._escape(world, walker, world.movement_tuning.escape_after_ticks)
	assert_eq(outcome, MovementCoordinator.ESCAPE_FUTILE, "does not use up the turn")
	assert_true(world.movement._right_of_way.has(walker.id), "right of way for the contested step")
	assert_eq(world.movement._way_holder, -1, "no held way")
	assert_eq(walker.path, before, "the route is untouched")


## Two people stalled in the same crowd: a newer escape cannot take the held
## way from someone who has waited longer while their right of way lasts.
func test_the_held_way_stays_with_whoever_has_waited_longest() -> void:
	var world: SimWorld = _service_world(["......", "......"])
	var long_wait: Walker = _walker(world, Vector2i(0, 0), Vector2i(5, 0))
	_standing(world, Vector2i(1, 0))
	var short_wait: Walker = _walker(world, Vector2i(0, 1), Vector2i(5, 1))
	_standing(world, Vector2i(1, 1))
	var limit: int = world.movement_tuning.escape_after_ticks
	world.movement._escape(world, long_wait, limit + 200)
	assert_eq(world.movement._way_holder, long_wait.id)
	world.movement._escape(world, short_wait, limit)
	assert_eq(world.movement._way_holder, long_wait.id, "the longer wait keeps the held way")
	assert_true(world.movement._right_of_way.has(short_wait.id), "the newer one still gets right of way")
	world.movement._right_of_way[long_wait.id] = world.now - 1
	world.movement._escape(world, short_wait, limit)
	assert_eq(world.movement._way_holder, short_wait.id, "once that lapses the next in line takes it")


func _service_world(rows: Array[String], open: bool = true) -> SimWorld:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(rows)))
	if open:
		assert_true(world.clock.start_service())
	return world


func _walker(world: SimWorld, at: Vector2i, goal: Vector2i) -> Walker:
	var agent: Walker = Walker.new()
	agent.cell = at
	world.add_agent(agent)
	assert_true(agent.set_destination(world.grid, goal))
	return agent


func _standing(world: SimWorld, at: Vector2i) -> SimAgent:
	var agent: SimAgent = SimAgent.new()
	agent.cell = at
	world.add_agent(agent)
	return agent


func _guest(world: SimWorld, at: Vector2i) -> GuestWalker:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 306
	var guest: GuestWalker = GuestWalker.new(RestaurantSim.new(), random)
	guest.cell = at
	world.add_agent(guest)
	return guest


func _advance(world: SimWorld) -> bool:
	var before: Dictionary = MovementInvariants.capture(world)
	world.advance()
	var problem: String = MovementInvariants.problem(world, before)
	assert_eq(problem, "", "tick %d keeps movement safety" % world.now)
	return problem.is_empty()
