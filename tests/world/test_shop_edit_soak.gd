extends TestCase
## FK-031: five real session days with seeded moves, purchases and sales.
## Keep FK-023's accounting/visit invariants; never replace the kitchen or guests.

const MAIN_SCENE: PackedScene = preload("res://src/world/main.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const SLOT: String = "test_shop_edit_soak"
const DAYS: int = 5
const RELOAD_BEFORE_DAY: int = 3
const EDIT_SEED: int = 531905
const CUSTOMER_SEED: int = 530317
const MAX_EDIT_CHECKS: int = 512
const MAX_DAY_BATCHES: int = 30
const EDITS_PER_MORNING: int = 4
const TEMP_ITEM_ID: StringName = &"chair"

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _edit_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fixed_items: Array[Dictionary] = []
var _arrivals_today: int = 0
var _paid_today: int = 0
var _left_today: int = 0
var _sales_today: int = 0
var _arrival_ids: Dictionary[int, bool] = {}
var _paid_ids: Dictionary[int, bool] = {}
var _left_ids: Dictionary[int, bool] = {}
var _ticket_ids: Dictionary[int, bool] = {}
var _guest_tickets: Dictionary[int, int] = {}
var _paid_tickets: Dictionary[int, bool] = {}
var _departure_reasons: Dictionary[StringName, int] = {}
var _dishes_paid: Dictionary[StringName, int] = {}
var _upgrade_delta_today: int = 0
var _edit_actions_today: int = 0


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "shop_edit_soak")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_edit_rng.seed = EDIT_SEED


func after_each() -> void:
	for main: Node in _mains:
		_free(main)
	_mains.clear()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_five_days_of_seeded_morning_edits_keep_real_session_invariants() -> void:
	var main: Node = _start()
	if main == null:
		return
	# New-game startup uses wall time. Replace only its random stream before any
	# visit, then draw the normal first gap through the public spawner API.
	# Subsequent normal morning autosaves capture this deterministic stream.
	GameState.new_run(CUSTOMER_SEED)
	var sim: RestaurantSim = main.get("sim")
	sim.use_rng(GameState.rng(&"customers"))
	sim.spawner.reset()
	_fixed_items = _fixed_snapshot(sim.world.grid)
	var total_served: int = 0
	var edited_mornings: int = 0
	var total_edit_actions: int = 0
	for day: int in range(1, DAYS + 1):
		assert_eq(Clock.sim.day, day)
		assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
		_assert_clean_morning(main, day)
		_assert_morning_autosave(main, day)
		if day == RELOAD_BEFORE_DAY:
			# Yesterday's edited layout reached this normal morning's autosave.
			# Reload BEFORE today's unsaved furniture edits.
			main = _reload_morning_autosave(main)
			if main == null:
				return
			_assert_clean_morning(main, day)
		if not _edit_morning(main, day):
			return
		edited_mornings += 1
		total_edit_actions += _edit_actions_today
		_assert_clean_morning(main, day)
		if not _run_day(main, day):
			return
		_assert_closed_books(main, day)
		total_served += (main.get("sim") as RestaurantSim).served_today
		(main.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
		assert_eq(Clock.sim.day, day + 1, "the report advances exactly one day")
		assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
		_assert_clean_morning(main, day + 1)
		_assert_morning_autosave(main, day + 1)
	assert_eq(edited_mornings, DAYS, "every morning includes real accepted edits")
	assert_eq(total_edit_actions, DAYS * EDITS_PER_MORNING)
	assert_true(total_served > DAYS * 5, "the edited shop serves real guests (%d in %d days)" % [total_served, DAYS])


func _start() -> Node:
	var main: Node = MAIN_SCENE.instantiate()
	main.set("use_saves", true)
	main.set("save_slot", SLOT)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")  # Idempotent before or after SceneTree readiness.
	var sim: RestaurantSim = main.get("sim")
	assert_not_null(sim, "the production session builds")
	assert_not_null(main.get("shop_editor"), "the production editor is available")
	if sim == null or main.get("shop_editor") == null:
		return null
	assert_not_null(sim.kitchen, "the soak requires the real kitchen")
	if sim.kitchen == null:
		return null
	Clock.set_speed(0)
	sim.customer_arrived.connect(_on_arrived)
	sim.customer_paid.connect(_on_paid)
	sim.customer_left.connect(_on_left)
	sim.orders.order_placed.connect(_on_order_placed)
	return main


## Exercise different furniture and both money directions every morning. The
## temporary level-one chair is sold again so the six-seat service remains useful.
func _edit_morning(main: Node, day: int) -> bool:
	_upgrade_delta_today = 0
	_edit_actions_today = 0
	for category: ItemDef.Category in [ItemDef.Category.TABLE, ItemDef.Category.DECOR]:
		if not _move_furniture(main, day, category):
			return false
	if not _buy_and_sell_furniture(main, day):
		return false
	assert_eq(_edit_actions_today, EDITS_PER_MORNING, "two moves, one purchase and one sale each morning")
	return true


## A local seeded shuffle chooses among a finite set of nearby legal moves.
## Required kitchen/door placements stay fixed; every move changes its origin.
func _move_furniture(main: Node, day: int, category: ItemDef.Category) -> bool:
	var editor: ShopEditor = main.get("shop_editor")
	var world: SimWorld = main.get("world")
	assert_true(editor.can_edit())
	var candidates: Array[Dictionary] = []
	for item: PlacedItem in world.grid.items():
		var definition: ItemDef = item.def as ItemDef
		if definition == null or definition.category != category:
			continue
		for y: int in range(-1, 2):
			for x: int in range(-1, 2):
				if x == 0 and y == 0:
					continue
				for turns: int in range(4):
					candidates.append({"id": item.id, "origin": item.origin + Vector2i(x, y), "turns": turns})
	for index: int in range(candidates.size() - 1, 0, -1):
		var other: int = _edit_rng.randi_range(0, index)
		var temporary: Dictionary = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = temporary
	var before: Dictionary = editor.to_dict().duplicate(true)
	var state_before: Dictionary = _edit_state()
	var checked: int = 0
	for candidate: Dictionary in candidates:
		if checked >= MAX_EDIT_CHECKS:
			break
		checked += 1
		var item_id: int = candidate["id"]
		var origin: Vector2i = candidate["origin"]
		var turns: int = candidate["turns"]
		var check: EditCheck = editor.check_move(item_id, origin, turns)
		if not check.ok or not check.unreachable.is_empty():
			continue
		if not _candidate_keeps_access(world.grid, item_id, origin, turns):
			continue
		var moved: bool = main.call("shop_move", item_id, origin, turns)
		assert_true(moved, "day %d: a prechecked legal move succeeds" % day)
		if not moved:
			return false
		assert_ne(editor.to_dict(), before, "day %d: the edited snapshot actually changes" % day)
		assert_true(editor.last_check.unreachable.is_empty())
		_assert_book_delta(state_before, 0)
		_assert_edit_context(main, state_before)
		_edit_actions_today += 1
		print("EDIT_SOAK_MOVE day=%d item=%d origin=%s turns=%d checked=%d" % [day, item_id, origin, turns, checked])
		return true
	fail("day %d: no warning-free, access-preserving move in %d bounded checks" % [day, checked])
	return false


func _buy_and_sell_furniture(main: Node, day: int) -> bool:
	var editor: ShopEditor = main.get("shop_editor")
	var world: SimWorld = main.get("world")
	var content: ContentDB = main.get("content")
	var definition: ItemDef = content.item(TEMP_ITEM_ID)
	assert_not_null(definition)
	if definition == null:
		return false
	var candidates: Array[Vector2i] = []
	for y: int in range(world.grid.size.y):
		for x: int in range(world.grid.size.x):
			candidates.append(Vector2i(x, y))
	for index: int in range(candidates.size() - 1, 0, -1):
		var other: int = _edit_rng.randi_range(0, index)
		var temporary: Vector2i = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = temporary
	var before_pair: Dictionary = editor.to_dict().duplicate(true)
	var previous_ids: Dictionary[int, bool] = {}
	for item: PlacedItem in world.grid.items():
		previous_ids[item.id] = true
	var checked: int = 0
	for origin: Vector2i in candidates:
		if checked >= MAX_EDIT_CHECKS:
			break
		checked += 1
		var turns: int = _edit_rng.randi_range(0, 3)
		var check: EditCheck = editor.check_buy(TEMP_ITEM_ID, origin, turns)
		if not check.ok or not check.unreachable.is_empty():
			continue
		if not _buy_keeps_access(world.grid, definition, origin, turns):
			continue
		var before_buy: Dictionary = _edit_state()
		var bought: bool = main.call("shop_buy", TEMP_ITEM_ID, origin, turns)
		assert_true(bought, "day %d: a prechecked purchase succeeds" % day)
		if not bought:
			return false
		_assert_book_delta(before_buy, -definition.price)
		_assert_edit_context(main, before_buy)
		_upgrade_delta_today -= definition.price
		_edit_actions_today += 1
		var purchased: PlacedItem = null
		var additions: int = 0
		for item: PlacedItem in world.grid.items():
			if not previous_ids.has(item.id):
				purchased = item
				additions += 1
		assert_eq(additions, 1, "a purchase adds exactly one real item")
		assert_eq(world.grid.items().size(), previous_ids.size() + 1)
		if additions != 1 or purchased == null:
			return false
		assert_eq((purchased.def as ItemDef).id, TEMP_ITEM_ID)
		assert_eq(purchased.origin, origin)
		assert_eq(purchased.quarter_turns, turns)
		var sell_check: EditCheck = editor.check_sell(purchased.id)
		assert_true(sell_check.ok, "the added chair can be sold")
		assert_true(sell_check.unreachable.is_empty())
		if not sell_check.ok or not sell_check.unreachable.is_empty():
			return false
		var before_sell: Dictionary = _edit_state()
		var expected_refund: int = floori(float(definition.price) / 2.0)
		var refund: int = main.call("shop_sell", purchased.id)
		assert_eq(refund, expected_refund, "the sale refunds exactly half the unit price, rounded down")
		if refund < 0:
			return false
		_assert_book_delta(before_sell, expected_refund)
		_assert_edit_context(main, before_sell)
		_upgrade_delta_today += expected_refund
		_edit_actions_today += 1
		assert_null(world.grid.item(purchased.id))
		assert_eq(editor.to_dict(), before_pair, "buy/sell preserves every existing placement and its order")
		print("EDIT_SOAK_TRADE day=%d price=%d refund=%d checked=%d" % [day, definition.price, refund, checked])
		return true
	fail("day %d: no legal, affordable, access-preserving decor purchase in %d checks" % [day, checked])
	return false


func _edit_state() -> Dictionary:
	return {"cash": Economy.cash, "ledger": Economy.ledger.to_dict().duplicate(true),
		"clock": Clock.sim.to_dict().duplicate(true), "customer_rng": GameState.rng(&"customers").state,
		"autosave": FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))}


## Check the entire ledger: a move adds nothing, while a buy/sell adds exactly
## one current-day upgrades entry for its price/refund, retaining all old rows.
func _assert_book_delta(before: Dictionary, delta: int) -> void:
	assert_eq(Economy.cash, int(before["cash"]) + delta)
	var expected: Dictionary = before["ledger"].duplicate(true)
	if delta == 0:
		assert_eq(Economy.ledger.to_dict(), expected, "moves never book a transaction")
		return
	expected["cash"] = str(int(before["cash"]) + delta)
	var entries: Array = expected["entries"]
	var actual: Dictionary = Economy.ledger.to_dict()
	var actual_entries: Array = actual["entries"]
	assert_eq(actual_entries.size(), entries.size() + 1, "exactly one transaction per furniture action")
	if actual_entries.size() != entries.size() + 1:
		return
	var added: Dictionary = actual_entries.back()
	assert_eq(added["day"], str(Clock.sim.day))
	assert_eq(added["amount"], str(delta))
	assert_eq(added["category"], String(Ledger.UPGRADES))
	entries.append(added.duplicate(true))
	assert_eq(actual, expected, "only the exact furniture transaction changes the books")


func _assert_edit_context(main: Node, before: Dictionary) -> void:
	var world: SimWorld = main.get("world")
	assert_eq(Clock.sim.to_dict(), before["clock"], "edits never advance the day")
	assert_eq(GameState.rng(&"customers").state, before["customer_rng"], "edits use a separate RNG")
	assert_eq(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")), before["autosave"],
		"furniture edits wait for the next normal morning autosave")
	assert_eq(_fixed_snapshot(world.grid), _fixed_items, "the kitchen line and doors stay fixed")
	assert_true(_service_access_ok(world.grid), "all real work/seat cells and staff posts remain reachable")


func _buy_keeps_access(live: SimGrid, definition: ItemDef, origin: Vector2i, turns: int) -> bool:
	var preview: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	for item: PlacedItem in live.items():
		if preview.place_def(item.def as ItemDef, item.origin, item.quarter_turns) == null:
			return false
	if preview.place_def(definition, origin, turns) == null:
		return false
	return _service_access_ok(preview)


## This isolated grid only rejects harmful fixture proposals; the actual edit
## still has to pass ShopEditor and the session wrapper on the real restaurant.
func _candidate_keeps_access(live: SimGrid, item_id: int, origin: Vector2i, turns: int) -> bool:
	var preview: SimGrid = SimGrid.from_ascii(LAYOUT.rows)
	for item: PlacedItem in live.items():
		var target: Vector2i = origin if item.id == item_id else item.origin
		var rotation: int = turns if item.id == item_id else item.quarter_turns
		if preview.place_def(item.def as ItemDef, target, rotation) == null:
			return false
	return _service_access_ok(preview)


func _service_access_ok(grid: SimGrid) -> bool:
	if grid.entries().is_empty():
		return false
	for entry: Vector2i in grid.entries():
		if not grid.is_walkable(entry):
			return false
	for role: StringName in LAYOUT.staff_spawns:
		if not _reachable_from_entry(grid, LAYOUT.staff_spawns[role]):
			return false
	for item: PlacedItem in grid.items():
		for cell: Vector2i in item.work_cells + item.seat_cells:
			if not _reachable_from_entry(grid, cell):
				return false
	return true


func _reachable_from_entry(grid: SimGrid, cell: Vector2i) -> bool:
	if not grid.is_walkable(cell):
		return false
	for entry: Vector2i in grid.entries():
		if grid.is_walkable(entry) and grid.is_reachable(entry, cell):
			return true
	return false


func _fixed_snapshot(grid: SimGrid) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	for item: PlacedItem in grid.items():
		var definition: ItemDef = item.def as ItemDef
		if definition.category != ItemDef.Category.TABLE and definition.category != ItemDef.Category.CHAIR \
				and definition.category != ItemDef.Category.DECOR:
			placements.append({"def_id": definition.id, "origin": item.origin, "turns": item.quarter_turns})
	return placements


func _reload_morning_autosave(old: Node) -> Node:
	var editor: ShopEditor = old.get("shop_editor")
	var snapshot: Dictionary = editor.to_dict().duplicate(true)
	var cash: int = Economy.cash
	var day: int = Clock.sim.day
	var clock: Dictionary = Clock.sim.to_dict().duplicate(true)
	var stock: Dictionary = Economy.stock.to_dict().duplicate(true)
	var ledger: Dictionary = Economy.ledger.to_dict().duplicate(true)
	var ingredients: int = Economy.ledger.day_totals(day).get(Ledger.INGREDIENTS, 0)
	var customer_rng: RandomNumberGenerator = GameState.rng(&"customers")
	var saved_seed: int = customer_rng.seed
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = saved_seed
	expected.state = customer_rng.state
	_mains.erase(old)
	_free(old)
	Economy.reset(98765)
	GameState.new_run(4242)
	var main: Node = _start()
	if main == null:
		return null
	var restored: ShopEditor = main.get("shop_editor")
	var sim: RestaurantSim = main.get("sim")
	assert_eq(Clock.sim.day, day, "reload resumes day 3 before its new edits")
	assert_eq(Clock.sim.to_dict(), clock, "reload preserves the complete morning clock")
	assert_eq(restored.to_dict(), snapshot, "the previous day's edited layout survives the morning autosave")
	assert_eq(Economy.cash, cash, "cash survives the scramble and reload")
	assert_eq(Economy.stock.to_dict(), stock, "all dated stock batches survive reload")
	assert_eq(Economy.ledger.to_dict(), ledger, "morning top-up adds no duplicate cost to already stocked shelves")
	assert_eq(int(Economy.ledger.day_totals(day).get(Ledger.INGREDIENTS, 0)), ingredients, "restock cost is not repeated")
	assert_true(sim.stock == Economy.stock)
	assert_true(sim.kitchen.stock == Economy.stock)
	assert_true(sim.rng == GameState.rng(&"customers"))
	assert_true(sim.spawner.rng == sim.rng)
	assert_eq(sim.rng.seed, saved_seed)
	# MORNING resume performs exactly the same one arrival-gap draw as FK-024.
	expected.randi_range(maxi(1, sim.spawner.min_gap), maxi(maxi(1, sim.spawner.min_gap), sim.spawner.max_gap))
	assert_eq(sim.rng.state, expected.state, "customer RNG resumes with exactly one morning gap draw")
	assert_eq(_fixed_snapshot(sim.world.grid), _fixed_items)
	_assert_morning_autosave(main, day)
	return main


## Read the real normal autosave; never invoke an extra save from the soak.
func _assert_morning_autosave(main: Node, day: int) -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json")))
	assert_true(saved is Dictionary, "the normal morning autosave exists and parses")
	if not saved is Dictionary:
		return
	var sections: Dictionary = saved.get("data", {})
	var clock: Dictionary = sections.get("clock", {})
	assert_eq(int(clock.get("day", -1)), day)
	assert_eq(int(clock.get("phase", -1)), int(SimClock.Phase.MORNING))
	var editor: ShopEditor = main.get("shop_editor")
	var expected: Dictionary = editor.to_dict()
	var shop: Dictionary = sections.get("shop", {})
	assert_eq(int(shop.get("version", -1)), int(expected["version"]))
	var stored_items: Array = shop.get("items", [])
	var current_items: Array = expected["items"]
	assert_eq(stored_items.size(), current_items.size())
	for index: int in range(mini(stored_items.size(), current_items.size())):
		var stored: Dictionary = stored_items[index]
		var current: Dictionary = current_items[index]
		assert_eq(String(stored.get("def_id", "")), String(current["def_id"]))
		var origin: Array = stored.get("origin", [])
		assert_eq(origin.size(), 2)
		if origin.size() == 2:
			assert_eq(Vector2i(int(origin[0]), int(origin[1])), Vector2i(int(current["origin"][0]), int(current["origin"][1])))
		assert_eq(int(stored.get("quarter_turns", -1)), int(current["quarter_turns"]))


func _assert_clean_morning(main: Node, day: int) -> void:
	var sim: RestaurantSim = main.get("sim")
	var world: SimWorld = main.get("world")
	assert_eq(sim.customers().size(), 0, "day %d: no guests before opening" % day)
	assert_eq(world.board.active_count(), 0, "day %d: no jobs carried over" % day)
	assert_eq(sim.kitchen.dirty_tables.size(), 0, "day %d: tables clean" % day)
	assert_eq(sim.served_today + sim.lost_today, 0, "day %d: counters reset" % day)
	assert_true(sim.leave_reasons_today.is_empty())
	assert_true((main.get("dishes_sold_today") as Dictionary).is_empty())
	for agent: SimAgent in world.agents:
		if agent is StaffAgent:
			assert_null((agent as StaffAgent).task)
			assert_eq(agent.cell, LAYOUT.staff_spawns[agent.role], "day %d: %s at its post" % [day, agent.role])
			assert_true(agent.path.is_empty())
			assert_almost_eq(agent.move_progress, 0.0)
	for item: PlacedItem in world.grid.items():
		for cell: Vector2i in item.work_cells + item.seat_cells:
			assert_eq(item.reserved_by(cell), -1, "day %d: nothing reserved overnight" % day)
	for id: StringName in TUNING.morning_stock:
		assert_true(Economy.stock.count(id) >= TUNING.morning_stock[id], "day %d: %s restocked" % [day, id])
	assert_true(sim.stock == Economy.stock, "day %d: the kitchen uses the books' stock" % day)
	assert_true(sim.kitchen.stock == Economy.stock)
	assert_true(sim.rng == GameState.rng(&"customers"))
	assert_true(_service_access_ok(world.grid))
	assert_eq(_fixed_snapshot(world.grid), _fixed_items)


func _run_day(main: Node, day: int) -> bool:
	_arrivals_today = 0
	_paid_today = 0
	_left_today = 0
	_sales_today = 0
	_arrival_ids.clear()
	_paid_ids.clear()
	_left_ids.clear()
	_ticket_ids.clear()
	_guest_tickets.clear()
	_paid_tickets.clear()
	_departure_reasons.clear()
	_dishes_paid.clear()
	var report: Control = main.get_node("Overlay/EveningReport")
	assert_false(report.visible, "day %d: no report before opening" % day)
	var opened: bool = Clock.sim.start_service()
	assert_true(opened, "day %d: the real shop opens" % day)
	if not opened:
		return false
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < MAX_DAY_BATCHES:
		main.call("run_ticks", 1000)
		guard += 1
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED, "day %d ends within the tick guard" % day)
	assert_true(report.visible, "day %d: the evening report is shown" % day)
	return Clock.sim.phase == SimClock.Phase.CLOSED


func _assert_closed_books(main: Node, day: int) -> void:
	var sim: RestaurantSim = main.get("sim")
	assert_eq(sim.customers().size(), 0, "day %d: everyone left at closing" % day)
	assert_eq(sim.served_today + sim.lost_today, _arrivals_today, "day %d: every guest counted once" % day)
	assert_eq(sim.served_today, _paid_today, "day %d: served means paid" % day)
	assert_eq(_left_today, _arrivals_today, "day %d: every guest departs exactly once" % day)
	assert_eq(_arrival_ids.size(), _arrivals_today)
	assert_eq(_paid_ids.size(), _paid_today)
	assert_eq(_paid_tickets.size(), _paid_today)
	assert_eq(_left_ids.size(), _left_today)
	for id: int in _arrival_ids:
		assert_true(_left_ids.has(id), "day %d: guest #%d has a departure" % [day, id])
	var reasons: int = 0
	for reason: StringName in sim.leave_reasons_today:
		reasons += sim.leave_reasons_today[reason]
		assert_true(reason == &"happy" or reason == &"no_menu" or reason == &"too_expensive"
			or CustomerAgent.PLAYER_REASONS.has(reason) or reason == &"kitchen_failed",
			"day %d: '%s' is a player-facing reason" % [day, reason])
	assert_eq(reasons, _arrivals_today, "day %d: every guest has a reason" % day)
	assert_eq(sim.leave_reasons_today, _departure_reasons)
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY]:
		assert_eq(sim.orders.orders_in_state(state).size(), 0, "day %d: no open tickets" % day)
	for id: int in _ticket_ids:
		var ticket: Order = sim.orders.get_order(id)
		assert_not_null(ticket, "tickets remain available until morning")
		if ticket != null:
			assert_true(ticket.state == Order.State.DELIVERED or ticket.state == Order.State.CANCELLED,
				"day %d: every actual ticket is terminal" % day)
	assert_true(sim.served_today > 0, "day %d: the real kitchen serves guests" % day)
	var totals: Dictionary = Economy.ledger.day_totals(day)
	assert_eq(int(totals.get(Ledger.SALE, 0)), _sales_today, "day %d: every sale is in the books" % day)
	var wages: int = 0
	for role: StringName in TUNING.wages:
		wages += TUNING.wages[role]
	assert_eq(int(totals.get(Ledger.WAGES, 0)), -wages, "day %d: wages once" % day)
	assert_eq(int(totals.get(Ledger.RENT, 0)), -TUNING.daily_rent, "day %d: rent once" % day)
	assert_eq(int(totals.get(Ledger.UPGRADES, 0)), _upgrade_delta_today, "day %d: exact net furniture cost" % day)
	assert_eq(int(totals.get(Ledger.OTHER, 0)), 0, "day %d: no unexplained money" % day)
	var since_start: int = 0
	for previous_day: int in range(1, day + 1):
		since_start += Economy.ledger.day_profit(previous_day)
	assert_eq(Economy.cash, TUNING.starting_cash + since_start, "day %d: cash = start + every recorded change" % day)
	var batches: Dictionary = Economy.stock.to_dict()["batches"]
	for raw_id: Variant in batches:
		var id: StringName = StringName(raw_id)
		assert_true(Economy.stock.count(id) >= 0, "day %d: %s never goes negative" % [day, id])
	var shown: DayReport = main.get("shown_report")
	assert_not_null(shown)
	if shown == null:
		return
	assert_eq(shown.day, day)
	assert_eq(shown.customers_served, sim.served_today)
	assert_eq(shown.customers_lost, sim.lost_today)
	assert_eq(int(shown.income.get(Ledger.SALE, 0)), _sales_today)
	assert_eq(shown.dishes_sold, _dishes_paid)
	var dishes: int = 0
	for recipe: StringName in shown.dishes_sold:
		dishes += shown.dishes_sold[recipe]
	assert_eq(dishes, sim.served_today, "day %d: one dish per served guest" % day)
	var income: Dictionary[StringName, int] = {}
	var costs: Dictionary[StringName, int] = {}
	var net_income: int = 0
	var net_costs: int = 0
	for category: StringName in totals:
		var amount: int = totals[category]
		if amount > 0:
			income[category] = amount
			net_income += amount
		elif amount < 0:
			costs[category] = -amount
			net_costs -= amount
	assert_eq(shown.income, income, "all report income agrees with the ledger")
	assert_eq(shown.costs, costs, "all report costs agree with the ledger")
	# Reports intentionally split NET category totals, including purchase/refund
	# within upgrades; they do not display the ledger's separate gross flows.
	assert_eq(shown.total_income(), net_income)
	assert_eq(shown.total_costs(), net_costs)
	assert_eq(shown.profit(), Economy.ledger.day_profit(day))
	var unhappy: Dictionary[StringName, int] = _departure_reasons.duplicate()
	unhappy.erase(&"happy")
	assert_eq(shown.leave_reasons, unhappy)
	var ledger_before: Dictionary = Economy.ledger.to_dict().duplicate(true)
	var cash_before: int = Economy.cash
	main.call("run_ticks", 25)
	assert_eq(Economy.ledger.to_dict(), ledger_before, "closed ticks cannot charge closing costs again")
	assert_eq(Economy.cash, cash_before)
	print("EDIT_SOAK_DAY day=%d edits=%d upgrades=%d arrivals=%d served=%d lost=%d departures=%d profit=%d cash=%d reasons=%s" % [
		day, _edit_actions_today, _upgrade_delta_today, _arrivals_today, sim.served_today, sim.lost_today, _left_today,
		Economy.ledger.day_profit(day), Economy.cash, sim.leave_reasons_today])


func _free(main: Node) -> void:
	if not is_instance_valid(main):
		return
	var sim: RestaurantSim = main.get("sim")
	if sim != null:
		if sim.customer_arrived.is_connected(_on_arrived):
			sim.customer_arrived.disconnect(_on_arrived)
		if sim.customer_paid.is_connected(_on_paid):
			sim.customer_paid.disconnect(_on_paid)
		if sim.customer_left.is_connected(_on_left):
			sim.customer_left.disconnect(_on_left)
		if sim.orders.order_placed.is_connected(_on_order_placed):
			sim.orders.order_placed.disconnect(_on_order_placed)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _on_arrived(guest: CustomerAgent) -> void:
	assert_false(_arrival_ids.has(guest.id), "each guest arrives once")
	_arrival_ids[guest.id] = true
	_arrivals_today += 1


func _on_paid(guest: CustomerAgent, order: Order, amount: int) -> void:
	assert_true(_arrival_ids.has(guest.id), "a paid guest actually arrived")
	assert_false(_paid_ids.has(guest.id), "each guest pays once")
	assert_false(_paid_tickets.has(order.id), "each ticket is paid once")
	assert_eq(order.customer_id, guest.id)
	assert_eq(order.state, Order.State.DELIVERED)
	assert_eq(amount, order.price, "payment uses the captured ticket price")
	assert_true(guest.paid)
	_paid_ids[guest.id] = true
	_paid_tickets[order.id] = true
	_paid_today += 1
	_sales_today += amount
	_dishes_paid[order.recipe_id] = int(_dishes_paid.get(order.recipe_id, 0)) + 1


func _on_left(guest: CustomerAgent, reason: StringName) -> void:
	assert_true(_arrival_ids.has(guest.id), "a departed guest actually arrived")
	assert_false(_left_ids.has(guest.id), "each guest departs once")
	assert_true(guest.departure_recorded)
	assert_eq(reason == &"happy", _paid_ids.has(guest.id), "happy departures match paid visits")
	_left_ids[guest.id] = true
	_left_today += 1
	_departure_reasons[reason] = int(_departure_reasons.get(reason, 0)) + 1


func _on_order_placed(order: Order) -> void:
	assert_true(_arrival_ids.has(order.customer_id))
	assert_false(_ticket_ids.has(order.id), "each ticket is posted once")
	assert_false(_guest_tickets.has(order.customer_id), "each visit places one ticket")
	_ticket_ids[order.id] = true
	_guest_tickets[order.customer_id] = order.id
