extends "res://src/world/main.gd"
## Explicit visual fixture for the guest quirk badges (#661). Six ordinary
## guests arrive on a real service; the first three are handed the authored
## Shutterbug, Chatterbox and Lunch-breaker quirks, the rest have none. No save
## is read or written. Capture with
##   bash tools/screenshot.sh --scene=res://tools/quirk_badges_review.tscn --speed=0 --frames=60
## Set QUIRK_BADGES_REVIEW_PLAIN=1 to skip the quirks (the "before" picture).

const AUTHORED: GuestQuirkCatalogue = preload("res://data/customers/quirks.tres")
const GUESTS: int = 6
const ARRIVAL_GAP_TICKS: int = 12
## Long enough for everyone to be seated and ordering, short enough that nobody has left.
const SETTLE_TICKS: int = 330


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null or not Clock.sim.start_service():
		push_error("Quirk badge review could not open service")
		return
	sim.spawner._remaining = 0
	var plain: bool = OS.get_environment("QUIRK_BADGES_REVIEW_PLAIN") == "1"
	var given: Array[String] = []
	for index: int in GUESTS:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 700 + index
		var guest: CustomerAgent = sim.add_customer(world.grid.entries()[0], random)
		if guest != null and not plain and index < AUTHORED.quirks.size():
			if guest.apply_quirk(AUTHORED.quirks[index]):
				given.append(String(AUTHORED.quirks[index].id))
		run_ticks(ARRIVAL_GAP_TICKS)
	run_ticks(SETTLE_TICKS)
	print("QUIRK_BADGES_REVIEW fixture=unsaved guests=%d quirks=%s" % [GUESTS, ",".join(given)])
