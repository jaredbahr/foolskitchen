extends "res://src/world/main.gd"
## Explicit visual fixture: all dining seats are held so a real party waits
## on the new bench. No save is read or written; no meal or patience is faked.
## Capture with tools/screenshot.sh --scene=res://tools/waiting_bench_review.tscn
## --speed=0 --frames=60. The ordinary --door-queue capture stays unchanged.


## Beside the doorway of the roomier starter shop, out of the door lane.
const BENCH_ORIGIN: Vector2i = Vector2i(4, 11)
const WALK_TICKS: int = 120


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null or not shop_editor.buy(&"waiting_bench", BENCH_ORIGIN):
		push_error("Waiting-bench review could not buy its bench")
		return
	for item: PlacedItem in world.grid.items():
		if (item.def as ItemDef).category == ItemDef.Category.TABLE:
			for seat: Vector2i in item.seat_cells:
				item.reserve(seat, 900)
	if not Clock.sim.start_service():
		push_error("Waiting-bench review could not open service")
		return
	sim.spawner._remaining = 1000000
	var streams: Array[RandomNumberGenerator] = []
	for seed_value: int in [31, 32]:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = seed_value
		streams.append(random)
	var party: Party = sim.add_party(world.grid.entries()[0], streams)
	# Real walking: in from the street door to the bench beside it.
	run_ticks(WALK_TICKS)
	var members: Array[CustomerAgent] = PartySeating.members(party, world)
	for guest: CustomerAgent in members:
		if not guest.is_waiting_seated(world):
			push_error("Waiting-bench review guest never reached its seat")
			return
	print("WAITING_BENCH_REVIEW fixture=occupied_dining_tables seated_waiters=%d dining_seats=%d" % [
		members.size(), sim.seat_count()])
