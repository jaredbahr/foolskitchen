extends TestCase
## #293: the café order counter. Guests who came for a drink queue in front of
## it on real cells, order and pay there, then take a free table or leave with a
## takeaway. A café without the counter keeps its table service exactly.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const MAX_TICKS: int = 3000
## The counter's staff side and guest cells in the fixture below.
const STAFF_CELL: Vector2i = Vector2i(13, 6)
const ORDER_CELL: Vector2i = Vector2i(13, 8)
const PICKUP_CELL: Vector2i = Vector2i(14, 8)

var _content: ContentDB
var _sim: RestaurantSim
var _paid: Array[int] = []
var _left: Dictionary[int, StringName] = {}
var _tasks: Array[SimTask] = []


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_paid.clear()
	_paid_orders.clear()
	_left.clear()
	_tasks.clear()


func after_each() -> void:
	_sim = null
	_content = null


# --- The counter itself ---------------------------------------------------

func test_the_counter_projects_order_pickup_and_staff_cells() -> void:
	_build(true)
	var counter: PlacedItem = OrderCounter.counters(_sim.world.grid)[0]
	var definition: ItemDef = counter.def as ItemDef
	assert_eq(definition.station_type, OrderCounter.STATION)
	assert_eq(definition.category, ItemDef.Category.STATION)
	assert_eq(definition.catalogue_room, &"bar_cafe")
	assert_eq(definition.price, 120)
	assert_eq(OrderCounter.order_cell(counter), ORDER_CELL)
	assert_eq(OrderCounter.pickup_cells(counter), [PICKUP_CELL] as Array[Vector2i])
	assert_eq(counter.work_cells, [STAFF_CELL] as Array[Vector2i], "the till's staff side")
	assert_eq(_sim.across_cell(counter.id, ORDER_CELL), STAFF_CELL, "the server stands across from the order cell")
	assert_eq(_sim.across_cell(counter.id, PICKUP_CELL), Vector2i(14, 6), "and hands a takeaway across from the pickup cell")
	assert_eq(_sim.seat_count(), _table_seats().size(), "the counter's cells are not dining seats")


func test_the_line_runs_straight_out_then_bends_along_the_wall_clear_of_the_door_lane() -> void:
	_build(true)
	var counter: PlacedItem = OrderCounter.counters(_sim.world.grid)[0]
	var line: Array[Vector2i] = OrderCounter.line_cells(_sim.world, counter)
	assert_eq(line, [Vector2i(13, 9), Vector2i(13, 11), Vector2i(11, 11)] as Array[Vector2i],
		"a clear cell between guests, bending along the south wall")
	var packed: Array[Vector2i] = OrderCounter.line_cells(_sim.world, counter, 1)
	assert_eq(packed, [Vector2i(13, 9), Vector2i(13, 10), Vector2i(13, 11), Vector2i(12, 11), Vector2i(11, 11),
		Vector2i(10, 11)] as Array[Vector2i], "packed close when the queue is long")
	assert_eq(OrderCounter.queue_cells(_sim.world, counter, 3), line, "a short queue stays spaced")
	assert_eq(OrderCounter.queue_cells(_sim.world, counter, 4), packed, "a long one packs")
	for cell: Vector2i in packed:
		assert_false(_sim.world.movement.in_door_lane(_sim.world, cell), "never in the door lane")
	for cell: Vector2i in line:
		assert_false(_sim.world.movement.in_door_lane(_sim.world, cell), "never in the door lane")
		assert_true(_sim.world.movement.standing_cell(_sim.world, cell))


func test_a_counter_with_no_clear_staff_side_is_not_used() -> void:
	_build(true, Vector2i(13, 5))
	var counter: PlacedItem = OrderCounter.counters(_sim.world.grid)[0]
	assert_eq(_sim.across_cell(counter.id, OrderCounter.order_cell(counter)), SimGrid.NO_CELL, "a wall is behind it")
	assert_true(OrderCounter.usable_counters(_sim, Vector2i(8, 12)).is_empty())
	var guests: Array[CustomerAgent] = _arrivals(1, 60, 5)
	assert_false(guests[0].counter_visit, "the guest looks for a table as before")
	assert_eq(guests[0].state, CustomerAgent.State.WALKING_TO_SEAT)


# --- The visit ------------------------------------------------------------

func test_counter_visits_never_create_a_table_order_task() -> void:
	_build(true)
	_arrivals(8, 100, 25)
	_run_until_gone()
	var orders: int = 0
	for task: SimTask in _tasks:
		if task.kind != &"take_order":
			continue
		orders += 1
		assert_eq(task.steps[0].cell, STAFF_CELL, "every order was taken at the till, never beside a table")
	assert_true(orders >= 5, "the till took the orders")
	assert_eq(_sim.served_today, _paid.size())


func test_a_takeaway_guest_pays_leaves_with_the_drink_and_never_sits() -> void:
	_build(true)
	var seeds: Array[int] = [_seed_with_draw(true, 200), _seed_with_draw(true, 300)]
	var guests: Array[CustomerAgent] = []
	for index: int in seeds.size():
		guests.append(_guest(seeds[index], 0))
	var table_seats: Dictionary[Vector2i, bool] = _table_seats()
	for tick: int in range(MAX_TICKS):
		_advance()
		for guest: CustomerAgent in guests:
			assert_false(table_seats.has(guest.cell), "a takeaway guest never walks to a table")
			assert_true(guest.state != CustomerAgent.State.EATING, "and never sits to eat")
		if _sim.customers().is_empty():
			break
	for guest: CustomerAgent in guests:
		assert_true(guest.takeaway)
		assert_true(guest.paid, "paid at the counter")
		assert_eq(_left[guest.id], &"happy")
		assert_eq(guest.order.state, Order.State.DELIVERED)
		assert_true(guest.seat_cell == PICKUP_CELL or guest.seat_cell == ORDER_CELL, "collected at the counter")
	assert_eq(_sim.takeaways_today, 2)
	assert_eq(_sim.served_today, 2)
	assert_true(_sim.kitchen.dirty_tables.is_empty(), "a takeaway leaves nothing to clear")


func test_a_guest_who_wants_to_stay_takes_a_free_table_and_drinks_there() -> void:
	_build(true)
	var guest: CustomerAgent = _guest(_seed_with_draw(false, 400), 0)
	var seated_at: Vector2i = SimGrid.NO_CELL
	var ate: bool = false
	for tick: int in range(MAX_TICKS):
		_advance()
		if guest.state == CustomerAgent.State.EATING:
			ate = true
			seated_at = guest.cell
		if _sim.customers().is_empty():
			break
	assert_false(guest.takeaway)
	assert_true(ate, "drank at the table")
	assert_true(_table_seats().has(seated_at), "on a dining seat")
	assert_eq(_left[guest.id], &"happy")
	assert_true(guest.paid)
	assert_eq(_sim.takeaways_today, 0)
	for task: SimTask in _tasks:
		if task.kind == &"take_order":
			assert_eq(task.steps[0].cell, STAFF_CELL, "no table order task")


func test_a_guest_who_finds_every_table_taken_leaves_with_a_takeaway() -> void:
	_build(true)
	var holder: int = 900000
	for item: PlacedItem in _sim.world.grid.items():
		if item.def is ItemDef and (item.def as ItemDef).category == ItemDef.Category.TABLE:
			for seat: Vector2i in item.seat_cells:
				holder += 1
				item.reserve(seat, holder)
	var guest: CustomerAgent = _guest(_seed_with_draw(false, 500), 0)
	_run_until_gone()
	assert_true(guest.takeaway, "no free table: takeaway")
	assert_true(guest.paid)
	assert_eq(_left[guest.id], &"happy")


func test_a_takeaway_pastry_takes_no_plate_and_leaves_nothing_to_clear() -> void:
	_build(true)
	_sim.menu = [_content.recipe(&"coffee"), _content.recipe(&"croissant")] as Array[RecipeDef]
	var guest: CustomerAgent = _guest(_seed_with_draw(true, 600), 0)
	guest.pastry_add_chance = 1.0
	_run_until_gone()
	assert_not_null(guest.extra_order, "added a pastry")
	assert_eq(guest.extra_order.state, Order.State.DELIVERED)
	assert_eq(_left[guest.id], &"happy")
	assert_eq(_sim.kitchen.in_use_plates, 0, "no plate left the shelf")
	assert_true(_sim.kitchen.dirty_tables.is_empty())
	assert_eq(_paid_orders.size(), 2, "coffee and pastry were both paid")


func test_the_queue_never_shares_a_cell_and_waits_clear_of_the_door() -> void:
	_build(true)
	var guests: Array[CustomerAgent] = _arrivals(9, 700, 8)
	var counter: PlacedItem = OrderCounter.counters(_sim.world.grid)[0]
	var line: Array[Vector2i] = OrderCounter.line_cells(_sim.world, counter, 1)
	for tick: int in range(60):
		_advance()
	var seen: Dictionary[Vector2i, int] = {}
	var in_line: int = 0
	for guest: CustomerAgent in guests:
		if guest.state != CustomerAgent.State.QUEUED:
			continue
		assert_false(seen.has(guest.cell), "two guests share %s" % guest.cell)
		seen[guest.cell] = guest.id
		if guest.cell != Vector2i(8, 12) and guest.has_arrived():
			assert_false(_sim.world.movement.in_door_lane(_sim.world, guest.cell), "queued guest in the door lane")
		if line.has(guest.cell):
			in_line += 1
	assert_true(in_line >= 3, "guests line up on the line's cells")
	_run_until_gone()


func test_same_seed_gives_the_same_takeaway_split_from_the_guests_own_stream() -> void:
	var first: Dictionary[int, bool] = _split()
	var second: Dictionary[int, bool] = _split()
	assert_eq(first, second)
	assert_true(first.size() >= 8, "most of the crowd reached the line")
	assert_true(first.values().has(true) and first.values().has(false), "both kinds of guest appear")
	for offset: int in first:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 800 + offset
		assert_eq(first[offset], random.randf() < _sim.visit_tuning.takeaway_share,
			"the draw is the guest's own first draw")


func test_the_takeaway_draw_is_one_draw_on_the_guests_own_stream() -> void:
	_build(true)
	var guest: CustomerAgent = _guest(900, 0)
	_advance()
	var reference: RandomNumberGenerator = RandomNumberGenerator.new()
	reference.seed = 900
	reference.randf()
	assert_eq(guest.rng.state, reference.state, "exactly one draw, and nothing from any shared stream")
	assert_true(guest.counter_visit)


func test_a_cafe_without_a_counter_keeps_its_table_service_exactly() -> void:
	_build(false)
	var guests: Array[CustomerAgent] = []
	var ticks: Dictionary[int, Dictionary] = {}
	var entries: Array[Vector2i] = _sim.world.grid.entries()
	for index: int in 14:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 100 + index
		var guest: CustomerAgent = _sim.add_visitor(entries[index % entries.size()], random, null, RecipeDef.COFFEE)
		guests.append(guest)
		ticks[guest.id] = {"arr": _sim.world.now}
		for tick: int in 30:
			_sim.advance()
			_note_times(guests, ticks)
	for tick: int in 1500:
		_sim.advance()
		_note_times(guests, ticks)
	var parts: PackedStringArray = PackedStringArray()
	for guest: CustomerAgent in guests:
		var row: Dictionary = ticks[guest.id]
		parts.append("%d:%d:%d:%d:%d:%s" % [guest.id, row["arr"], row.get("ord", -1), row.get("del", -1),
			row.get("gone", -1), _left.get(guest.id)])
		assert_false(guest.counter_visit)
		assert_false(guest.takeaway)
	assert_eq("|".join(parts), GOLDEN_NO_COUNTER, "recorded on main before the order counter existed")
	assert_eq(_sim.served_today, 7)
	assert_eq(_sim.takeaways_today, 0)


# --- Report and tuning ------------------------------------------------------

func test_takeaways_reach_the_day_report_only_when_there_were_some() -> void:
	var quiet: DayReport = DayReport.new()
	assert_false(quiet.to_dict().has("takeaways"), "other days keep their exact shape")
	var report: DayReport = DayReport.new()
	report.customers_served = 9
	report.takeaways = 4
	assert_eq(DayReport.from_dict(report.to_dict()).takeaways, 4)
	assert_eq(DayReport.from_dict({"customers_served": 2, "takeaways": 50}).takeaways, 2, "never more than were served")


func test_takeaway_tuning_is_data_and_validated() -> void:
	var tuning: VisitTuning = load("res://data/balance/visits.tres") as VisitTuning
	assert_true(tuning.is_valid())
	assert_almost_eq(tuning.takeaway_share, 0.3)
	var broken: VisitTuning = tuning.duplicate() as VisitTuning
	broken.takeaway_share = 1.5
	assert_false(broken.is_valid())
	broken = tuning.duplicate() as VisitTuning
	broken.counter_patience_multiplier = 0.5
	assert_false(broken.is_valid())



const GOLDEN_NO_COUNTER: String = "4:0:104:368:478:happy|5:30:161:548:658:happy|6:60:214:433:543:happy|7:90:261:662:772:happy|8:120:-1:-1:421:no_table|9:150:-1:-1:451:no_table|10:180:-1:-1:481:no_table|11:210:733:926:1036:happy|12:240:-1:-1:541:no_table|13:270:776:999:1109:happy|14:300:-1:-1:601:no_table|15:330:-1:-1:631:no_table|16:360:-1:-1:661:no_table|17:390:829:1082:1192:happy"

var _paid_orders: Array[Order] = []


## A guest whose own first random draw falls on the wanted side of the takeaway share.
func _seed_with_draw(takeaway: bool, from: int) -> int:
	for candidate: int in range(from, from + 1000):
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = candidate
		if (random.randf() < 0.3) == takeaway:
			return candidate
	return from


## One coffee guest at the door with this seed.
func _guest(seed: int, settle: int) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	var guest: CustomerAgent = _sim.add_visitor(_sim.world.grid.entries()[0], random, null, RecipeDef.COFFEE)
	guest.food_patience = 5000
	for tick: int in settle:
		_advance()
	return guest


func _table_seats() -> Dictionary[Vector2i, bool]:
	var seats: Dictionary[Vector2i, bool] = {}
	for item: PlacedItem in _sim.world.grid.items():
		if item.def is ItemDef and (item.def as ItemDef).category == ItemDef.Category.TABLE:
			for seat: Vector2i in item.seat_cells:
				seats[seat] = true
	return seats


## Seed offset -> whether the guest wanted a takeaway, for those who joined the line.
func _split() -> Dictionary[int, bool]:
	_build(true)
	var guests: Array[CustomerAgent] = []
	for index: int in 12:
		guests.append(_guest(800 + index, 0))
	for tick: int in 150:
		_advance()
	var result: Dictionary[int, bool] = {}
	for index: int in guests.size():
		if guests[index].counter_visit:
			result[index] = guests[index].takeaway_wanted
	return result


func _run_until_gone() -> void:
	for tick: int in range(MAX_TICKS):
		_advance()
		if _sim.customers().is_empty() and _sim.world.board.active_count() == 0:
			return
	assert_true(false, "service did not settle within %d ticks" % MAX_TICKS)


func _note_times(guests: Array[CustomerAgent], ticks: Dictionary[int, Dictionary]) -> void:
	for guest: CustomerAgent in guests:
		var row: Dictionary = ticks[guest.id]
		if guest.order != null and not row.has("ord"):
			row["ord"] = _sim.world.now
		if guest.order != null and guest.order.state == Order.State.DELIVERED and not row.has("del"):
			row["del"] = _sim.world.now
		if guest.state >= CustomerAgent.State.LEAVING and not row.has("gone"):
			row["gone"] = _sim.world.now


func _build(counter: bool, counter_origin: Vector2i = Vector2i(13, 7)) -> RestaurantSim:
	var layout: ShopLayout = LAYOUT.duplicate(true) as ShopLayout
	var kept: Array[ShopPlacement] = []
	for placed: ShopPlacement in layout.placements:
		if placed.item_id == &"potted_plant" or placed.item_id == &"table_2" and placed.origin == Vector2i(11, 7):
			continue
		kept.append(placed)
	layout.placements = kept
	var extra: Array = [[&"coffee_machine", Vector2i(9, 5), 2], [&"coffee_machine", Vector2i(10, 5), 2]]
	if counter:
		extra.append([&"order_counter", counter_origin, 0])
	for row: Array in extra:
		var placement: ShopPlacement = ShopPlacement.new()
		placement.item_id = row[0]
		placement.origin = row[1]
		placement.quarter_turns = row[2]
		layout.placements.append(placement)
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 80, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(layout, _content, 293, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.menu = [_content.recipe(&"coffee"), _content.recipe(&"tea")] as Array[RecipeDef]
	_sim.spawner.min_gap = 1000000
	_sim.spawner.max_gap = 1000000
	_sim.spawner.reset()
	_sim.start_day()
	_sim.customer_paid.connect(_on_paid)
	_sim.customer_left.connect(_on_left)
	_sim.world.board.task_completed.connect(_on_task_completed)
	assert_true(_sim.world.clock.start_service())
	return _sim


## `count` drink guests arriving `gap` ticks apart, each with its own seeded stream.
func _arrivals(count: int, first_seed: int, gap: int) -> Array[CustomerAgent]:
	var guests: Array[CustomerAgent] = []
	var entries: Array[Vector2i] = _sim.world.grid.entries()
	for index: int in count:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = first_seed + index
		var guest: CustomerAgent = _sim.add_visitor(entries[index % entries.size()], random, null, RecipeDef.COFFEE)
		guest.food_patience = 5000
		guests.append(guest)
		for tick: int in gap:
			_advance()
	return guests


func _advance() -> void:
	var before: Dictionary = MovementInvariants.capture(_sim.world)
	_sim.advance()
	var problem: String = MovementInvariants.problem(_sim.world, before)
	assert_eq(problem, "", "every tick preserves occupied/next/edge safety")


func _on_paid(customer: CustomerAgent, order: Order, _amount: int) -> void:
	_paid.append(customer.id)
	_paid_orders.append(order)


func _on_left(customer: CustomerAgent, reason: StringName) -> void:
	_left[customer.id] = reason


func _on_task_completed(task: SimTask) -> void:
	_tasks.append(task)
