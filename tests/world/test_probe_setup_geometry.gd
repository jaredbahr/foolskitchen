extends TestCase
## Real accepted setup edits and reachable dining capacity; no service loop.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const ORIGINAL: ShopLayout = preload("res://data/layouts/tier1_original.tres")
## A fresh Main: the deeper starter (#389), which the probes run on.
const ROOMIER: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")
const SLOT: String = "probe_setup_geometry"

var _main: Node
var _old_dir: String
var _dir: String
var _providers: Dictionary[String, Dictionary] = {}
var _old_clock_processing: bool
var _old_speed: int


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.save_dir = _dir
	SaveSystem.delete_slot(SLOT)
	_old_clock_processing = Clock.is_processing()
	_old_speed = Clock.speed
	Clock.set_process(false)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_process(_old_clock_processing)
	Clock.set_speed(_old_speed)


func test_original_coffee_constructs_ten_reachable_seats() -> void:
	_assert_profile("coffee_shop", true)


func test_roomier_coffee_constructs_ten_reachable_seats() -> void:
	_assert_profile("coffee_shop", false)


func test_original_bar_constructs_ten_reachable_seats() -> void:
	_assert_profile("bar", true)


func test_roomier_bar_constructs_ten_reachable_seats() -> void:
	_assert_profile("bar", false)


func _assert_profile(profile: String, original: bool) -> void:
	_start(original)
	if original:
		# Exercise the actual legacy load route, as the original-save tests do.
		# Removing these optional sections selects the preserved original shop.
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join(SLOT + ".json"))) as Dictionary
		document["data"].erase("shop")
		document["data"].erase("staff")
		var file: FileAccess = FileAccess.open(_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
		assert_not_null(file)
		if file == null:
			return
		file.store_string(JSON.stringify(document))
		file.close()
		DirAccess.remove_absolute(_dir.path_join(SLOT + ".json.bak"))
		_close()
		_start(true)
	var expected: ShopLayout = ORIGINAL if original else ROOMIER
	assert_eq((_main.get("_base_layout") as ShopLayout).save_layout_id, expected.save_layout_id)
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var cash: int = Economy.cash
	var progress: Dictionary = (_main.get("owner_progress") as OwnerProgress).to_dict()
	var rng_before: Dictionary = GameState._capture_save()
	var countdown_before: int = sim.spawner.get("_remaining")
	assert_true(ProbeSetups.apply(profile, _main), "the complete actual profile must construct successfully")
	assert_eq(Economy.cash, cash, "the concept retains free construction")
	assert_eq(GameState._capture_save(), rng_before, "construction neither draws nor resets a stream")
	assert_eq(sim.spawner.get("_remaining"), countdown_before, "construction leaves the current arrival countdown")
	assert_eq((_main.get("owner_progress") as OwnerProgress).to_dict(), progress, "no progression grant")
	var seen_groups: Dictionary[int, bool] = {}
	var unique_seats: Dictionary[Vector2i, bool] = {}
	var largest: int = 0
	for table: PlacedItem in sim.world.grid.items():
		var group: int = sim.world.grid.dining_group_id(table.id)
		if group == 0 or seen_groups.has(group):
			continue
		seen_groups[group] = true
		var usable: Array[Vector2i] = DiningSeats.usable_cells(sim.world.grid, table)
		largest = maxi(largest, usable.size())
		for seat: Vector2i in usable:
			assert_false(unique_seats.has(seat), "seat catalogue groups cannot double-count a seat")
			unique_seats[seat] = true
	assert_eq(unique_seats.size(), 10, "all ten seats must be usable and guest-reachable, not merely nominal or any-reachable")
	assert_eq(largest, 4, "the original four-person dining group remains available")
	var west: PlacedItem = sim.world.grid.item_at(Vector2i(2, 6))
	assert_not_null(west)
	if west != null:
		assert_eq(west.quarter_turns, 0, "only this concept restores the west table's original seating orientation")
		assert_eq(DiningSeats.usable_cells(sim.world.grid, west).size(), 4, "the left dining group retains four usable seats")
	_assert_actor_access(sim)


func _start(with_saves: bool) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", with_saves)
	_main.set("save_slot", SLOT)
	_main.set("skip_owner_picker", true)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	_main.set_process(false)
	(_main.get_node("CameraRig") as CameraRig).set_process(false)
	(_main.get_node("ShopView") as ShopView).set_process(false)
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


## Thirty-four cheap real setup applications, with no service tick. These report
## actual actors and claims, never treating an unused authored post as a person.
func test_original_all_setups_apply_before_service() -> void:
	_assert_all_setups(true)


func test_roomier_all_setups_apply_before_service() -> void:
	_assert_all_setups(false)


func _assert_all_setups(original: bool) -> void:
	var profiles: Array[String] = ProbeSetups.names()
	assert_eq(profiles.size(), 19)
	assert_true(profiles.has("coffee_counter"))
	assert_true(profiles.has("patio"))
	assert_true(profiles.has("expanded_staffed"))
	for profile: String in profiles:
		_close()
		SaveSystem.delete_slot(SLOT)
		_start_profile_base(original)
		var expected: ShopLayout = ORIGINAL if original else ROOMIER
		assert_eq((_main.get("_base_layout") as ShopLayout).save_layout_id, expected.save_layout_id)
		var sim: RestaurantSim = _main.get("sim") as RestaurantSim
		var initial: Dictionary = _profile_people(sim)
		var accepted: bool = ProbeSetups.apply(profile, _main)
		var after_apply: Dictionary = _profile_people(sim)
		if accepted:
			_assert_work_cells_not_seats(sim, profile)
			_assert_seats_stop_paths(sim, profile, original)
			if profile == "joined_tables":
				_assert_joined_fixture(sim, original)
		# This is the same ordinary boundary used immediately after apply by
		# BalanceProbe. A refusal remains a test failure; record all profiles.
		sim.start_day()
		var after_start_day: Dictionary = _profile_people(sim)
		print("PROBE_SETUP_GEOMETRY ", JSON.stringify({"profile": profile,
			"base": "original" if original else "roomier", "accepted": accepted,
			"initial": initial, "after_apply": after_apply, "after_start_day": after_start_day}))
		assert_true(accepted, "%s on %s must accept the complete actual setup" % [profile, expected.save_layout_id])
		for snapshot: Dictionary in [initial, after_apply, after_start_day]:
			assert_eq(snapshot["phase"], int(SimClock.Phase.MORNING), profile + " stays in the actual morning")
			assert_eq(snapshot["world_tick"], 0, profile + " does not advance service")
			assert_eq(snapshot["customers"], 0, profile + " has no arrived customer")
			assert_eq(snapshot["served"], 0, profile + " has no served arrivals")
			assert_eq(snapshot["lost"], 0, profile + " has no departed arrivals")
		_close()
		SaveSystem.delete_slot(SLOT)
		if profile == "fryer_coffee":
			_assert_fryer_staging_only(original)


## #315: every setup still validates with no path warning (on the roomier
## starter no seat warning either; a legacy setup's own placement may carry
## one until the next change). Walking as
## people do (a seat ends a walk), nothing is cut off on the roomier starter,
## joined tables included. The preserved original layout's middle row is all
## tables and seats, so real people there reach the kitchen only by squeezing
## through: for every pass, the seat rule and the server's real route agree
## on whether its guest side can be reached.
func _assert_seats_stop_paths(sim: RestaurantSim, profile: String, original: bool) -> void:
	var check: EditCheck = (_main.get("shop_editor") as ShopEditor).check_current()
	assert_true(check.ok, profile)
	assert_eq(check.unreachable, [] as Array[int], profile + " has no path warning")
	if not original:
		assert_true(check.seat_warnings.is_empty(), profile + " has no seat warning")
	var ids: Dictionary[int, int] = {}
	for item: PlacedItem in sim.world.grid.items():
		ids[item.id] = item.id
	var cut: Array[int] = ShopEditor._unreachable(sim.world.grid, ids, true)
	if not original:
		assert_eq(cut, [] as Array[int], profile + " leaves everything reachable for real people")
		return
	var server: SimAgent = null
	for actor: SimAgent in sim.world.agents:
		if actor is StaffAgent and actor.role == &"server":
			server = actor
	assert_not_null(server, profile + " has a server to route")
	if server == null:
		return
	var checked: int = 0
	for item: PlacedItem in sim.world.grid.items():
		if (item.def as ItemDef).category != ItemDef.Category.PASS:
			continue
		checked += 1
		var route: Array[Vector2i] = sim.world.movement.route(sim.world, server, server.cell, item.work_cells[1], false)
		assert_eq(route.is_empty(), cut.has(item.id), profile + ": the seat rule matches real routing")
	assert_true(checked > 0, profile + " checked a pass against real routing")


func _start_profile_base(original: bool) -> void:
	_start(original)
	if not original:
		return
	# Real legacy load, matching the four existing capacity fixtures above.
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join(SLOT + ".json"))) as Dictionary
	document["data"].erase("shop")
	document["data"].erase("staff")
	var file: FileAccess = FileAccess.open(_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(JSON.stringify(document))
	file.close()
	DirAccess.remove_absolute(_dir.path_join(SLOT + ".json.bak"))
	_close()
	_start(true)


func _profile_people(sim: RestaurantSim) -> Dictionary:
	var active: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	var customers: int = 0
	for agent: SimAgent in sim.world.all_agents():
		var row: Dictionary = {"id": agent.id, "role": String(agent.role),
			"cell": [agent.cell.x, agent.cell.y], "admitted": agent.movement_admitted}
		if agent is StaffAgent:
			row["member_id"] = String((agent as StaffAgent).member_id)
		if agent is CustomerAgent:
			customers += 1
		if sim.world.agents.has(agent):
			active.append(row)
		else:
			pending.append(row)
	var claims: Dictionary = sim.world.movement.snapshot()
	var occupied: Array[Dictionary] = []
	var next: Array[Dictionary] = []
	for cell: Vector2i in claims["occupied"]:
		occupied.append({"cell": [cell.x, cell.y], "actor": claims["occupied"][cell]})
	for cell: Vector2i in claims["next"]:
		next.append({"cell": [cell.x, cell.y], "actor": claims["next"][cell]})
	var roster: Array[Dictionary] = []
	for member: StaffMember in (_main.get("staff_roster") as StaffRoster).members():
		roster.append(member.to_dict())
	return {"active": active, "pending": pending, "active_count": active.size(),
		"pending_count": pending.size(), "occupied": occupied, "next": next,
		"roster": roster, "customers": customers, "served": sim.served_today,
		"lost": sim.lost_today, "world_tick": sim.world.now, "phase": int(sim.world.clock.phase)}


## Check only the isolated staging operation: the full fryer apply above
## starts from the original pose and retains its pre-existing level-two grant.
func _assert_fryer_staging_only(original: bool) -> void:
	_start_profile_base(original)
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var before: Dictionary = _profile_people(sim)
	var rng_before: Dictionary = GameState._capture_save()
	var economy_before: Dictionary = Economy._capture_save()
	var progress_before: Dictionary = (_main.get("owner_progress") as OwnerProgress).to_dict()
	var countdown_before: int = sim.spawner.get("_remaining")
	var staged: bool = ProbeSetups._stage_fryer_owner(sim)
	var after: Dictionary = _profile_people(sim)
	print("PROBE_FRYER_STAGING ", JSON.stringify({"base": "original" if original else "roomier",
		"accepted": staged, "before": before, "after": after}))
	assert_true(staged, "the isolated morning construction pose must be legal")
	assert_eq(sim.owner_agent().cell, Vector2i(8, 3))
	assert_eq(GameState._capture_save(), rng_before, "staging neither draws nor resets any stream")
	assert_eq(Economy._capture_save(), economy_before, "staging changes no cash, stock, ledger or loan")
	assert_eq((_main.get("owner_progress") as OwnerProgress).to_dict(), progress_before, "staging grants no XP")
	assert_eq(sim.spawner.get("_remaining"), countdown_before, "staging preserves arrival countdown")
	assert_eq(sim.world.now, 0)
	assert_eq(after["customers"], 0)
	_close()
	SaveSystem.delete_slot(SLOT)


## Static editor reachability alone does not prove legal actor access: an
## empty dining seat is still forbidden as an aisle or a station work cell.
## Serve-across counters are TABLEs; their intentional customer seats are
## checked through their behind-counter stations, not treated as work cells.
func _assert_work_cells_not_seats(sim: RestaurantSim, profile: String) -> void:
	var seats: Dictionary[Vector2i, bool] = {}
	for placed: PlacedItem in sim.world.grid.items():
		for seat: Vector2i in placed.seat_cells:
			seats[seat] = true
	for placed: PlacedItem in sim.world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition.category not in [ItemDef.Category.PASS, ItemDef.Category.STATION, ItemDef.Category.STORAGE]:
			continue
		for work: Vector2i in placed.work_cells:
			assert_false(seats.has(work), "%s: %s work cell %s must not be a reserved-only seat" % [profile, definition.id, work])


func _assert_joined_fixture(sim: RestaurantSim, original: bool) -> void:
	var origin: Vector2i = Vector2i(3, 7) if original else Vector2i(4, 9)
	var west: PlacedItem = sim.world.grid.item_at(origin)
	var east: PlacedItem = sim.world.grid.item_at(origin + Vector2i(2, 0))
	assert_not_null(west)
	assert_not_null(east)
	if west == null or east == null:
		return
	assert_eq(west.quarter_turns, 1)
	assert_eq(east.quarter_turns, 1)
	var ids: Array[int] = [west.id, east.id]
	assert_eq(sim.world.grid.dining_group_members(west.id), ids, "the same two tables form one joined group")
	assert_eq(DiningSeats.usable_cells(sim.world.grid, west).size(), 6, "the translated group retains six usable seats")


## Static actor-aware routes ignore temporary people, never private seats.
## A real admitted guest borrows exactly its destination's normal booking;
## no one moves and every booking is released after the individual query.
func _assert_actor_access(sim: RestaurantSim) -> void:
	var world: SimWorld = sim.world
	var streams: Dictionary = GameState._capture_save()
	var staff_checked: int = 0
	for actor: SimAgent in world.agents:
		if not actor is StaffAgent or actor.role not in [&"cook", &"server"]:
			continue
		staff_checked += 1
		for item: PlacedItem in world.grid.items():
			for work: Vector2i in item.work_cells:
				var path: Array[Vector2i] = world.movement.route(world, actor, actor.cell, work, false)
				assert_false(path.is_empty(), "each real staff member reaches every authored work cell without any seat")
				for cell: Vector2i in path:
					assert_eq(MovementInvariants._cell_problem(world, actor, cell), "")
				for index: int in range(1, path.size()):
					assert_eq(MovementInvariants._edge_problem(world, actor, path[index - 1], path[index]), "")
	assert_eq(staff_checked, 2)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 263
	var guest: CustomerAgent = CustomerAgent.new(sim, random)
	guest.cell = world.grid.entries()[0]
	world.add_agent(guest)
	assert_true(guest.movement_admitted, "the route witness is a real street admission")
	if not guest.movement_admitted:
		world.remove_agent(guest)
		return
	var checked: Dictionary[Vector2i, bool] = {}
	for item: PlacedItem in world.grid.items():
		for seat: Vector2i in item.seat_cells:
			if checked.has(seat):
				continue
			checked[seat] = true
			var table: PlacedItem = world.grid.item(world.grid.dining_table_id(seat))
			assert_not_null(table)
			if table == null:
				continue
			var booked: bool = table.reserve(seat, guest.id)
			assert_true(booked)
			if not booked:
				continue
			var path: Array[Vector2i] = world.movement.route(world, guest, guest.cell, seat, false)
			assert_false(path.is_empty(), "each of the ten seats has a route that avoids every foreign seat")
			for cell: Vector2i in path:
				assert_eq(MovementInvariants._cell_problem(world, guest, cell), "")
			for index: int in range(1, path.size()):
				assert_eq(MovementInvariants._edge_problem(world, guest, path[index - 1], path[index]), "")
			assert_true(table.release(seat, guest.id))
	assert_eq(checked.size(), 10)
	assert_eq(world.now, 0, "route inspection never advances service")
	assert_eq(GameState._capture_save(), streams, "the independent route witness draws no named stream")
	world.remove_agent(guest)
