extends "res://src/world/main.gd"
## Explicit, unsaved display fixture, not a normal service or balance claim.
## Prepare a restroom through normal morning edits, hold one table dirty and
## add two floor spots through the existing seeded dirt API. Frame 12 shows
## the same slightly messy shop with Hygiene off; frame 60 shows it on.

var _review_frame: int = 0


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null:
		push_error("Hygiene review needs a fresh shop")
		return
	var plant: PlacedItem = ShopBuilder.items_with_def(world, &"potted_plant")[0]
	if not shop_move(plant.id, Vector2i(11, 9), 0) \
			or not shop_rooms({Vector2i(12, 8): SimGrid.Room.RESTROOM,
			Vector2i(12, 9): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int]) \
			or not shop_buy(&"toilet", Vector2i(12, 9), 0):
		push_error("Hygiene review could not prepare its restroom")
		return
	# Keep the problems above the catalogue in the fixed quarter-2 capture.
	var table: PlacedItem = ShopBuilder.items_with_def(world, &"table_2")[2]
	sim.kitchen.mark_table_dirty(table.id)
	sim.restroom_used(Vector2i(12, 8))
	var floor_cells: Array[Vector2i] = [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8),
		Vector2i(9, 9), Vector2i(10, 9), Vector2i(8, 9), Vector2i(8, 8), Vector2i(9, 5)]
	for attempt: int in range(32):
		sim.cleanliness.try_spawn_at_departed_seat(floor_cells[attempt % floor_cells.size()])
		if sim.cleanliness.spot_count() == 2:
			break
	if sim.cleanliness.spot_count() != 2 or not set_build_active(true):
		push_error("Hygiene review could not prepare its two floor spots and Build view")
		return
	var state: HygieneOverview.Snapshot = HygieneOverview.capture(sim)
	print("HYGIENE_REVIEW ", JSON.stringify({"fixture": "seed 1; unsaved morning restroom edits, one held dirty table and two seeded floor spots",
		"lines": HygieneOverview.lines(state), "use_saves": use_saves, "world_tick": world.now}))


func _process(delta: float) -> void:
	super._process(delta)
	_review_frame += 1
	if _review_frame == 20:
		_build_catalogue.set_hygiene_enabled(true)
		if not _build_catalogue.hygiene_panel.visible or _build_preview.displayed_hygiene_cells().is_empty():
			push_error("Hygiene review did not show its native list and problem cells")
