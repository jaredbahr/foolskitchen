extends SceneTree
## Hand-run timing of people passing at the front door (#468, #536). Never a
## CI job.
##   godot --headless --path . --script tools/door_exit_timing.gd
## The door scenario of tests/sim/test_doorway_counterflow.gd on the starter
## shop, 128 times: a crowd of 2, 4, 6 or 10 patient guests waits inside the
## door, then 1 or 2 people get up to leave from the back and 0, 1, 2 or 4
## seats come free; with the shop's own wide door and with a one-cell way in
## walled in behind it; with the leavers' IDs above the crowd's and below.
## Prints one DOOR_CASE row per scenario and a mean per group of 32:
## - out: ticks until each leaver is on the street;
## - seated: ticks until each guest given a seat sits down;
## - lost: guests who lost their table on the way to it;
## - stall: the longest anyone with a route went without getting closer.
## Compare two commits by running it on each: every number is deterministic.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const SETTLE_TICKS: int = 160
const CROWDS: Array[int] = [2, 4, 6, 10]
const FREED: Array[int] = [0, 1, 2, 4]
const LEAVERS: Array[int] = [1, 2]
const RUN_TICKS: int = 400

var _content: ContentDB
var _phantoms: Dictionary[Vector2i, int] = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_content = ContentDB.new()
	if not _content.load_all().is_empty():
		print("Content failed to load")
		quit(1)
		return
	for narrow: bool in [true, false]:
		for lower: bool in [false, true]:
			var out_sum: float = 0.0
			var out_count: int = 0
			var seated_sum: float = 0.0
			var seated_count: int = 0
			var lost: int = 0
			var stall: int = 0
			var not_out: int = 0
			for crowd: int in CROWDS:
				for free: int in FREED:
					for leavers: int in LEAVERS:
						var row: Dictionary = _scenario(narrow, lower, crowd, free, leavers)
						print("DOOR_CASE door=%s ids=%s crowd=%d free=%d leaving=%d out=%s seated=%s lost=%d stall=%d" % [
							"narrow" if narrow else "wide", "lower" if lower else "higher", crowd, free, leavers,
							row["out"], row["seated"], row["lost"], row["stall"]])
						for ticks: int in row["out"]:
							out_sum += ticks
							out_count += 1
						for ticks: int in row["seated"]:
							seated_sum += ticks
							seated_count += 1
						not_out += leavers - (row["out"] as Array).size()
						lost += int(row["lost"])
						stall = maxi(stall, int(row["stall"]))
			print("DOOR_GROUP door=%s ids=%s out_mean=%.1f seated_mean=%.1f lost=%d not_out=%d longest_stall=%d" % [
				"narrow" if narrow else "wide", "lower" if lower else "higher",
				out_sum / maxf(1.0, out_count), seated_sum / maxf(1.0, seated_count), lost, not_out, stall])
	quit(0)


func _scenario(narrow: bool, lower: bool, crowd: int, free: int, leavers: int) -> Dictionary:
	# The autoload by path: this script compiles before autoloads exist.
	root.get_node("/root/GameState").call("new_run", 1)
	var sim: RestaurantSim = _shop(narrow)
	var world: SimWorld = sim.world
	var entries: Array[Vector2i] = world.grid.entries()
	# Lower IDs for the leavers: keep two IDs back before the crowd comes in.
	var kept: int = world._next_agent_id
	if lower:
		world._next_agent_id += 2
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
	var after: int = world._next_agent_id
	for spot: Vector2i in [Vector2i(3, 5), Vector2i(11, 5)].slice(0, leavers):
		if lower:
			world._next_agent_id = kept + going.size()
		var leaver: CustomerAgent = _customer(sim, spot)
		if lower:
			# People take their turn in ID order: first in the list as well.
			world.agents.erase(leaver)
			world.agents.insert(going.size(), leaver)
		going.append(leaver)
	world._next_agent_id = maxi(after, world._next_agent_id)
	for leaver: CustomerAgent in going:
		leaver._leave(world, sim, &"no_table")
	_free_seats(world, free)
	var out: Dictionary[int, int] = {}
	var seated: Dictionary[int, int] = {}
	var walking: Dictionary[int, bool] = {}
	var lost: int = 0
	var stall: int = 0
	for tick: int in RUN_TICKS:
		sim.advance()
		for id: int in world.movement._stall:
			stall = maxi(stall, world.now - int(world.movement._stall[id]["since"]))
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
	return {"out": out.values(), "seated": seated.values(), "lost": lost, "stall": stall}


## The starter shop with every dining seat held by a stand-in, so arrivals
## queue; `narrow` walls in a one-cell way in, (7, 11), behind its door.
func _shop(narrow: bool) -> RestaurantSim:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 305, errors, null, false)
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
	sim.world.clock.start_service()
	if narrow:
		var walls: Dictionary[Vector2i, int] = {Vector2i(7, 10): SimGrid.Terrain.WALL, Vector2i(8, 10): SimGrid.Terrain.WALL}
		for x: int in range(9, 15):
			walls[Vector2i(x, 11)] = SimGrid.Terrain.WALL
		sim.world.grid.set_terrains(walls)
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
