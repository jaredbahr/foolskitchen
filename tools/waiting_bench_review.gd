extends "res://src/world/main.gd"
## Explicit visual fixture: all dining seats are held so a real party waits
## on the new bench. No save is read or written; no meal or patience is faked.
## Capture with tools/screenshot.sh --scene=res://tools/waiting_bench_review.tscn
## --speed=0 --frames=60. The ordinary --door-queue capture stays unchanged.


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null or not shop_editor.buy(&"waiting_bench", Vector2i(6, 10)):
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
	var party: Party = sim.add_party(Vector2i(6, 10), streams)
	run_ticks(30)
	var members: Array[CustomerAgent] = PartySeating.members(party, world)
	for guest: CustomerAgent in members:
		if not guest.is_waiting_seated(world):
			push_error("Waiting-bench review guest never reached its seat")
			return
	print("WAITING_BENCH_REVIEW fixture=occupied_dining_tables seated_waiters=%d dining_seats=%d" % [
		members.size(), sim.seat_count()])
