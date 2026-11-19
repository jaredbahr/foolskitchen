extends "res://src/world/main.gd"
## Explicit, unsaved display fixture for the premium decor tier (#206), not a
## balance claim. A fresh seed-1 shop at owner level 13 buys, through the real
## Buy command, the dessert display case, gramophone, deluxe jukebox and chef
## statue in a row of the dining room. PREMIUM_STAGE picks the lighting:
## day (sunny morning, the default), night (closed), or service (the shop
## open for a few minutes so guests sit near the pieces). PREMIUM_ZOOM sets
## the camera zoom (12 is the game's default, 4 is 3x), PREMIUM_FOCUS which
## piece it centres on (display_case, gramophone, jukebox_neon, chef_statue,
## or row). Nothing is saved.

const PIECES: Array[StringName] = [&"display_case", &"gramophone", &"jukebox_neon", &"chef_statue"]
const SERVICE_TICKS: int = 1500

var _spots: Dictionary[StringName, PlacedItem] = {}


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null:
		push_error("Premium decor review needs a fresh shop")
		return
	world.weather.kind = WeatherState.Kind.SUNNY
	Economy.add_cash(5000, Ledger.OTHER)
	shop_editor.set_owner_level(13)
	var dump: PackedStringArray = []
	for cell: Vector2i in world.grid.cells():
		if world.grid.terrain(cell) == SimGrid.Terrain.FLOOR:
			dump.append("%d,%d:%s%s" % [cell.x, cell.y, world.grid.room(cell), "*" if world.grid.item_at(cell) != null else ""])
	print("PREMIUM_CELLS ", " ".join(dump))
	var cells: Dictionary = JSON.parse_string(OS.get_environment("PREMIUM_CELLS")) if not OS.get_environment("PREMIUM_CELLS").is_empty() else {}
	for id: StringName in PIECES:
		var origin: Array = cells.get(String(id), [])
		if origin.size() == 2:
			var placed: PlacedItem = _buy(id, Vector2i(int(origin[0]), int(origin[1])), int(cells.get(String(id) + "_turns", 0)))
			if placed != null:
				_spots[id] = placed
	($ShopView as ShopView).set_wall_mode(ShopView.WallMode.CUTAWAY)
	var stage: String = OS.get_environment("PREMIUM_STAGE")
	if stage == "night":
		world.clock.phase = SimClock.Phase.CLOSED
	elif stage == "service":
		if Clock.sim.start_service():
			run_ticks(SERVICE_TICKS)
	Clock.set_speed(0)
	refresh_presentation()
	_frame()
	if OS.get_environment("PREMIUM_HUD") != "1":
		($HUD as CanvasLayer).hide()
	print("PREMIUM_REVIEW ", JSON.stringify({"stage": stage, "placed": _spots.keys(), "guests": sim.customers().size(),
		"lamps": lamp_visuals().size(), "use_saves": use_saves}))


func _process(delta: float) -> void:
	super._process(delta)
	if _morning_paper != null and _morning_paper.visible:
		_morning_paper.dismiss()


func _buy(def_id: StringName, origin: Vector2i, turns: int) -> PlacedItem:
	if not shop_buy(def_id, origin, turns):
		push_error("Premium review could not place %s at %s: %s" % [def_id, origin, shop_editor.last_check.why])
		return null
	return world.grid.item(shop_editor.last_item_id)


func _frame() -> void:
	var focus: String = OS.get_environment("PREMIUM_FOCUS")
	var zoom: float = OS.get_environment("PREMIUM_ZOOM").to_float() if not OS.get_environment("PREMIUM_ZOOM").is_empty() else 12.0
	var centre: Vector2 = Vector2(5.0, 3.6)
	if _spots.has(StringName(focus)):
		var placed: PlacedItem = _spots[StringName(focus)]
		var at: Vector3 = GridMath.cell_to_world(placed.origin)
		centre = Vector2(at.x, at.z)
	elif not _spots.is_empty() and focus == "row":
		var sum: Vector2 = Vector2.ZERO
		for placed: PlacedItem in _spots.values():
			var at: Vector3 = GridMath.cell_to_world(placed.origin)
			sum += Vector2(at.x, at.z)
		centre = sum / float(_spots.size())
	var rig: CameraRig = $CameraRig as CameraRig
	rig.edge_pan_enabled = false
	rig.minimum_zoom = 1.0
	rig.initial_yaw_degrees = OS.get_environment("PREMIUM_YAW").to_float() if not OS.get_environment("PREMIUM_YAW").is_empty() else 45.0
	rig.frame_area(centre, Vector2(40.0, 40.0), zoom, true)
	rig.set_process(false)
	refresh_presentation()
