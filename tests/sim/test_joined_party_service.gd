extends TestCase
## Real physical reservations, lifecycle and kitchen work for joined dining.

const TABLE: ItemDef = preload("res://data/items/cloth_table.tres")
const CHAIR: ItemDef = preload("res://data/items/chair.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const REVIEWS: ReviewTuning = preload("res://data/balance/reviews.tres")
const QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")

class RefusingGuest extends CustomerAgent:
	func _init(sim: RestaurantSim, random: RandomNumberGenerator) -> void:
		super(sim, random)

	func set_destination(_grid: SimGrid, _goal: Vector2i) -> bool:
		return false

var _sim: RestaurantSim
var _content: ContentDB
var _tables: Array[PlacedItem] = []
var _paid: Dictionary[int, bool] = {}
var _left: Dictionary[int, bool] = {}
var _bus_members: Dictionary[int, bool] = {}
var _bus_completed: Dictionary[int, bool] = {}
var _saw_bus_work: bool = false
var _saw_partial_cleanup: bool = false


func after_each() -> void:
	_tables.clear()
	_sim = null
	_content = null
	_paid.clear()
	_left.clear()
	_bus_members.clear()
	_bus_completed.clear()
	_saw_bus_work = false
	_saw_partial_cleanup = false


func test_real_six_person_party_eats_pays_and_busses_three_physical_tables_without_moving_plate_owners() -> void:
	_real_kitchen()
	var tuning: ReviewTuning = REVIEWS.duplicate() as ReviewTuning
	tuning.review_chance = 1.0
	_sim.configure_reviews(ReputationBook.new(), tuning, QUOTES, _rng(24699))
	_sim.customer_paid.connect(_on_paid)
	_sim.customer_left.connect(_on_left)
	_sim.world.board.task_posted.connect(_on_task_posted)
	_sim.world.board.task_completed.connect(_on_task_completed)
	assert_true(_sim.world.clock.start_service())
	var party: Party = _sim.add_party(_sim.world.grid.entries()[0], _randoms(6))
	assert_not_null(party)
	if party == null:
		return
	var guests: Array[CustomerAgent] = PartySeating.members(party, _sim.world)
	for guest: CustomerAgent in guests:
		guest.food_patience = 5000
		guest.eat_ticks = 3
	var owners: Dictionary[int, int] = {}
	var drained: bool = false
	var saw_first_dirty_release: bool = false
	for tick: int in 4000:
		_sim.advance()
		if not saw_first_dirty_release and not _paid.is_empty():
			for table: PlacedItem in _tables:
				assert_true(_sim.kitchen.is_table_dirty(table.id), "the first completed meal dirties every original member immediately")
			saw_first_dirty_release = true
		var plates: PlateLedger = _sim.kitchen.plates
		assert_eq(plates.clean + plates.dirty + plates.in_use, 6)
		for guest: CustomerAgent in guests:
			if guest.state >= CustomerAgent.State.WALKING_TO_SEAT and guest.state <= CustomerAgent.State.PAYING:
				assert_eq(guest.table_item_id, _sim.world.grid.dining_table_id(guest.seat_cell))
				assert_eq(_sim.world.grid.item(guest.table_item_id).reserved_by(guest.seat_cell), guest.id)
				owners[guest.id] = guest.table_item_id
			if guest.order != null and plates._tables_by_order.has(guest.order.id):
				assert_eq(plates._tables_by_order[guest.order.id], guest.order.table_item_id,
					"the actual plate token remains on its physical order table")
		var dirty: int = _sim.kitchen.dirty_tables.size()
		_saw_partial_cleanup = _saw_partial_cleanup or (dirty > 0 and dirty < 3 and not _bus_completed.is_empty())
		for agent: SimAgent in _sim.world.agents:
			var worker: StaffAgent = agent as StaffAgent
			if worker != null and worker.task != null and worker.task.kind == &"bus_table" \
					and worker.step_index < worker.task.steps.size() \
					and worker.task.steps[worker.step_index].kind == TaskStep.Kind.WORK \
					and worker._step_started and worker.work_left > 0.0:
				assert_true(_table_ids().has(worker._held_item_id))
				assert_eq(_sim.world.grid.item(worker._held_item_id).reserved_by(worker.cell), worker.id)
				_saw_bus_work = true
		if _sim.customers().is_empty() and _sim.kitchen.is_clean() and _sim.world.board.active_count() == 0:
			drained = true
			break
	assert_true(drained, "six real meals and physical-table cleanup finish in the same-day kitchen budget")
	assert_true(party.seated)
	assert_eq(_sim.world.clock.day, 1)
	assert_eq(_sim.served_today, 6)
	assert_eq(_sim.lost_today, 0)
	assert_eq(_paid.size(), 6)
	assert_eq(_left.size(), 6)
	assert_eq(owners.size(), 6)
	assert_eq(_sim.reviews_today.size(), 6)
	assert_eq(_bus_members.size(), 3)
	assert_eq(_bus_completed.size(), 3)
	assert_true(_saw_bus_work)
	assert_true(saw_first_dirty_release)
	assert_true(_saw_partial_cleanup, "real tasks clear members individually rather than silently cleaning the group")
	var unique_orders: Array[int] = []
	for guest: CustomerAgent in guests:
		assert_true(guest.paid)
		assert_eq(guest.leave_reason, &"happy")
		assert_not_null(guest.order)
		if guest.order == null:
			continue
		assert_eq(guest.order.state, Order.State.DELIVERED)
		assert_eq(guest.order.customer_id, guest.id)
		assert_eq(guest.order.table_item_id, owners[guest.id])
		assert_false(unique_orders.has(guest.order.id))
		unique_orders.append(guest.order.id)
	assert_eq(_sim.kitchen.plates.clean, 6)
	assert_eq(_sim.kitchen.plates.dirty, 0)
	assert_eq(_sim.kitchen.plates.in_use, 0)
	assert_eq(DiningSeats.largest_usable_capacity(_sim.world.grid), 6)
	for ingredient: IngredientDef in _content.recipe(&"burger").ingredients:
		assert_eq(_sim.stock.count(ingredient.id), 94)


func test_party_route_failure_rolls_back_holds_on_every_physical_member() -> void:
	_plain()
	var ids: Array[int] = []
	for index: int in 6:
		var guest: CustomerAgent
		if index == 4:
			guest = RefusingGuest.new(_sim, _rng(100 + index))
			_sim.world.add_agent(guest)
		else:
			guest = _sim.add_customer(Vector2i.ZERO, _rng(100 + index))
		ids.append(guest.id)
	var party: Party = Party.new(ids)
	for id: int in ids:
		(_sim.world.agent(id) as CustomerAgent).party = party
	assert_false(PartySeating.try_seat(party, _sim.world))
	assert_eq(party.table_item_id, 0)
	for table: PlacedItem in _tables:
		for seat: Vector2i in table.seat_cells:
			assert_eq(table.reserved_by(seat), -1)
	for id: int in ids:
		var guest: CustomerAgent = _sim.world.agent(id) as CustomerAgent
		assert_true(guest.path.is_empty())
		assert_eq(guest.table_item_id, 0)
		assert_eq(guest.state, CustomerAgent.State.ARRIVING)


func test_forced_split_before_seating_requeues_all_members_without_dirtying_unfinished_meals() -> void:
	_plain()
	var party: Party = _sim.add_party(Vector2i.ZERO, _randoms(6))
	assert_true(PartySeating.try_seat(party, _sim.world))
	var guests: Array[CustomerAgent] = PartySeating.members(party, _sim.world)
	assert_eq(party.booked_table_ids, _table_ids())
	assert_true(_sim.world.grid.remove(_tables[1].id))
	for guest: CustomerAgent in guests:
		guest.cell = guest.seat_cell
	PartySeating.finish_seating(party, _sim.world, _sim)
	assert_false(party.seated)
	assert_eq(party.table_item_id, 0)
	assert_true(party.booked_table_ids.is_empty())
	for guest: CustomerAgent in guests:
		assert_eq(guest.state, CustomerAgent.State.QUEUED)
		assert_true(guest.booked_table_ids.is_empty())
		assert_eq(guest.table_item_id, 0)
		assert_true(guest.path.is_empty())
	for table: PlacedItem in [_tables[0], _tables[2]]:
		for seat: Vector2i in table.seat_cells:
			assert_eq(table.reserved_by(seat), -1)


func test_favourite_on_nonleader_member_keeps_physical_seat_and_rng_unchanged() -> void:
	_plain()
	var guest: CustomerAgent = _sim.add_customer(Vector2i.ZERO, _rng(246))
	var profile: RegularProfile = RegularProfile.new()
	profile.favourite_seat = Vector2i(7, 5)
	guest.regular_profile = profile
	var state: int = guest.rng.state
	assert_true(guest._try_seat(_sim.world))
	assert_eq(guest.seat_cell, profile.favourite_seat)
	assert_eq(guest.table_item_id, _tables[2].id)
	assert_eq(_tables[2].reserved_by(guest.seat_cell), guest.id)
	assert_eq(guest.booked_table_ids, _table_ids())
	assert_eq(guest.rng.state, state)
	assert_eq(_sim.world.now, 0)


func test_group_shares_spare_seats_with_singles_but_one_dirty_member_blocks_the_whole_group() -> void:
	_real_kitchen()
	var party: Party = _sim.add_party(_sim.world.grid.entries()[0], _randoms(4))
	assert_true(PartySeating.try_seat(party, _sim.world, _sim.kitchen))
	var first: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], _rng(88))
	var second: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], _rng(89))
	assert_true(first._try_seat(_sim.world))
	assert_true(second._try_seat(_sim.world))
	var third: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], _rng(90))
	assert_false(third._try_seat(_sim.world))
	for guest: CustomerAgent in PartySeating.members(party, _sim.world):
		guest._release_seat(_sim.world, false)
	first._release_seat(_sim.world, false)
	second._release_seat(_sim.world, false)
	_sim.kitchen.mark_table_dirty(_tables[2].id)
	assert_false(_sim.kitchen.is_table_dirty(_tables[0].id), "the primitive remains physical")
	assert_true(_sim.kitchen.is_dining_group_dirty(_tables[0].id))
	assert_false(third._try_seat(_sim.world), "a clean leader cannot bypass a dirty nonleader")


func test_departure_uses_original_member_snapshot_after_forced_split_and_keeps_plate_physical() -> void:
	_real_kitchen()
	var party: Party = _sim.add_party(_sim.world.grid.entries()[0], _randoms(6))
	assert_true(PartySeating.try_seat(party, _sim.world, _sim.kitchen))
	var guest: CustomerAgent = PartySeating.members(party, _sim.world)[0]
	var original_members: Array[int] = guest.booked_table_ids.duplicate()
	assert_eq(original_members, _table_ids())
	assert_true(_sim.world.grid.remove(_tables[1].id))
	var order: Order = Order.new()
	order.id = 24601
	order.table_item_id = guest.table_item_id
	assert_true(_sim.kitchen.plates.take(order.id, order.table_item_id))
	_sim.kitchen.mark_dining_group_dirty(order.table_item_id, order.id, original_members)
	for table: PlacedItem in [_tables[0], _tables[2]]:
		assert_true(_sim.kitchen.is_table_dirty(table.id))
	assert_false(_sim.kitchen.is_table_dirty(_tables[1].id))
	assert_eq(_sim.kitchen.plates._tables_by_order[order.id], order.table_item_id)
	assert_eq(_sim.kitchen.plates.returned_at_table(order.table_item_id), 1)
	var other_member: int = 0
	for table: PlacedItem in _tables:
		if _sim.world.grid.item(table.id) != null and table.id != order.table_item_id:
			other_member = table.id
			break
	assert_ne(other_member, 0, "a different surviving physical member exists")
	assert_ne(other_member, order.table_item_id)
	assert_eq(_sim.kitchen.plates.collect_table(other_member), 0,
		"a different member's bus cannot collect this physical plate")


func _plain() -> void:
	_sim = RestaurantSim.new()
	_sim.world = SimWorld.new(SimGrid.new(Vector2i(14, 12)), SimClock.new())
	_sim.world.grid.set_terrain(Vector2i.ZERO, SimGrid.Terrain.ENTRY)
	for x: int in [3, 5, 7]:
		_tables.append(_sim.world.grid.place_def(TABLE, Vector2i(x, 4)))
		assert_not_null(_sim.world.grid.place_def(CHAIR, Vector2i(x, 3), 2))
		assert_not_null(_sim.world.grid.place_def(CHAIR, Vector2i(x, 5), 0))


func _real_kitchen() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	layout.placements.clear()
	for placement: ShopPlacement in LAYOUT.placements:
		if _content.item(placement.item_id).category != ItemDef.Category.TABLE:
			layout.placements.append(placement.duplicate(true) as ShopPlacement)
	for x: int in [3, 5, 7]:
		layout.placements.append(_placement(&"cloth_table", Vector2i(x, 7)))
		layout.placements.append(_placement(&"chair", Vector2i(x, 6), 2))
		layout.placements.append(_placement(&"chair", Vector2i(x, 8)))
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(layout, _content, 24619, errors, stock)
	assert_eq(errors, [] as Array[String])
	assert_not_null(_sim.kitchen)
	if _sim.kitchen == null:
		return
	assert_true(_sim.kitchen.configure_plates(6))
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()
	_tables.assign(ShopBuilder.items_with_def(_sim.world, &"cloth_table"))
	assert_eq(_tables.size(), 3)
	assert_eq(DiningSeats.largest_usable_capacity(_sim.world.grid), 6)


func _placement(id: StringName, origin: Vector2i, turns: int = 0) -> ShopPlacement:
	var value: ShopPlacement = ShopPlacement.new()
	value.item_id = id
	value.origin = origin
	value.quarter_turns = turns
	return value


func _randoms(count: int) -> Array[RandomNumberGenerator]:
	var result: Array[RandomNumberGenerator] = []
	for index: int in count:
		result.append(_rng(24600 + index))
	return result


func _rng(seed_value: int) -> RandomNumberGenerator:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return random


func _table_ids() -> Array[int]:
	var result: Array[int] = []
	for table: PlacedItem in _tables:
		result.append(table.id)
	return result


func _on_paid(guest: CustomerAgent, order: Order, amount: int) -> void:
	assert_false(_paid.has(guest.id))
	assert_eq(order.table_item_id, guest.table_item_id)
	assert_eq(order.state, Order.State.DELIVERED)
	assert_eq(amount, _content.recipe(&"burger").standard_price)
	_paid[guest.id] = true


func _on_left(guest: CustomerAgent, reason: StringName) -> void:
	assert_false(_left.has(guest.id))
	assert_eq(reason, &"happy")
	_left[guest.id] = true


func _on_task_posted(task: SimTask) -> void:
	if task.kind == &"bus_table":
		var member: int = int(task.payload["table_item_id"])
		assert_true(_table_ids().has(member))
		assert_eq(task.steps[0].item_id, member)
		assert_true(task.steps[0].use_seat)
		_bus_members[member] = true


func _on_task_completed(task: SimTask) -> void:
	if task.kind == &"bus_table":
		_bus_completed[int(task.payload["table_item_id"])] = true


func test_seated_guests_actual_forced_owner_removal_dirties_survivors_without_reassigning_a_plate() -> void:
	_real_kitchen()
	var party: Party = _sim.add_party(_sim.world.grid.entries()[0], _randoms(6))
	assert_true(PartySeating.try_seat(party, _sim.world, _sim.kitchen))
	var guests: Array[CustomerAgent] = PartySeating.members(party, _sim.world)
	for guest: CustomerAgent in guests:
		guest.cell = guest.seat_cell
	PartySeating.finish_seating(party, _sim.world, _sim)
	assert_true(party.seated)
	var departing: CustomerAgent = guests[0]
	assert_true(departing._take_order(SimAgent.new()))
	assert_not_null(departing.order)
	if departing.order == null:
		return
	var removed_owner: int = departing.table_item_id
	assert_true(_sim.kitchen.plates.take(departing.order.id, removed_owner))
	assert_true(_sim.world.grid.remove(removed_owner))
	departing.tick(_sim.world)
	assert_true(departing.state >= CustomerAgent.State.LEAVING)
	assert_true(departing.booked_table_ids.is_empty())
	for table: PlacedItem in _tables:
		if table.id != removed_owner:
			assert_true(_sim.kitchen.is_table_dirty(table.id))
	assert_false(_sim.kitchen.plates._tables_by_order.has(departing.order.id),
		"the removed physical table recovers its own token instead of moving it to a leader")
	assert_eq(_sim.kitchen.plates.clean + _sim.kitchen.plates.dirty + _sim.kitchen.plates.in_use, 6)
