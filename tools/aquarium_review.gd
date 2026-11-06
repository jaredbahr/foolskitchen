extends "res://src/world/main.gd"
## Explicit, unsaved display fixture for the fish tanks (#125), not a balance
## claim. A fresh seed-1 shop at owner level 5 buys, through the real Buy
## command, an Aquarium against the back wall with the Kenney low open
## bookcase and side table beside it (the style proof), and a Large aquarium
## along the side wall. Capture with
##   bash tools/screenshot.sh --scene=res://tools/aquarium_review.tscn --speed=0 --frames=30,60,90
## Frame 30: the proof row close up at the game's camera angle. Frame 60: the
## proof row at a normal play zoom. Frame 90: service running, guests seated
## near the tanks in the furnished room. AQUARIUM_REVIEW_CLOUDY=1 shows the
## Aquarium cloudy (its last clean five days back) for the same frames.

const TANK_AT: Vector2i = Vector2i(3, 5)
const LARGE_AT: Vector2i = Vector2i(1, 8)
const CLOSE_FRAME: int = 25
const PLAY_FRAME: int = 55
const ROOM_FRAME: int = 85
const SERVICE_TICKS: int = 2600
## Fish pinned to one moment, so every capture shows the same swim.
const FISH_TIME: float = 7.0

var _review_frame: int = 0
var _tank: PlacedItem
var _large: PlacedItem


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null:
		push_error("Aquarium review needs a fresh shop")
		return
	Economy.add_cash(2000, Ledger.OTHER)
	shop_editor.set_owner_level(5)
	# Against the kitchen wall, facing the room, with the style proof beside
	# it: the kit's low open bookcase and side table.
	_tank = _buy(&"aquarium", TANK_AT, 2)
	if _tank == null:
		return
	_buy(&"bookcase_open_low", TANK_AT + Vector2i(-2, 0), 2)
	_buy(&"side_table", TANK_AT + Vector2i.LEFT, 2)
	# The large tank along the left wall, facing the tables.
	_large = _buy(&"aquarium_large", LARGE_AT, 1)
	if OS.get_environment("AQUARIUM_REVIEW_CLOUDY") == "1":
		sim.aquarium.restore(world.grid, {"version": AquariumCare.SAVE_VERSION, "tanks": [
			{"def_id": "aquarium", "origin": [_tank.origin.x, _tank.origin.y], "cleaned_day": 0}]}, Clock.sim.day + 5)
		Clock.sim.day += 5
		_recompute_vibe()
	($ShopView as ShopView).set_wall_mode(ShopView.WallMode.CUTAWAY)
	Clock.set_speed(0)
	_pin_fish()
	refresh_presentation()
	_frame(_tank, 2.6, Vector2(-0.55, 0.15))
	print("AQUARIUM_REVIEW ", JSON.stringify({"tank": [_tank.origin.x, _tank.origin.y],
		"large": [_large.origin.x, _large.origin.y] if _large != null else [],
		"cloudy": sim.aquarium.cloudy_ids(world.grid, Clock.sim.day),
		"vibe_score": vibe_result.score, "vibe_theme": vibe_result.theme_label, "use_saves": use_saves}))


func _process(delta: float) -> void:
	super._process(delta)
	_review_frame += 1
	if _review_frame == PLAY_FRAME:
		_frame(_tank, 5.0, Vector2(-0.5, 1.2))
	elif _review_frame == ROOM_FRAME:
		if Clock.sim.start_service():
			run_ticks(SERVICE_TICKS)
		_pin_fish()
		var guests: int = sim.customers().size()
		_frame(_tank, 5.2, Vector2(0.6, 1.4))
		print("AQUARIUM_ROOM ", JSON.stringify({"guests": guests, "tick": world.now}))
	if _review_frame >= PLAY_FRAME:
		_pin_fish()


## Holds every tank's fish at FISH_TIME so captures repeat exactly.
func _pin_fish() -> void:
	for node: ItemVisual in ($ShopView as ShopView).item_nodes.values():
		var tank: AquariumView = node.prop as AquariumView
		if tank != null:
			tank.set_review_time(FISH_TIME)


## The real Buy command at a fixed spot of the seed-1 starter dining room.
func _buy(def_id: StringName, origin: Vector2i, turns: int) -> PlacedItem:
	if not shop_buy(def_id, origin, turns):
		push_error("Aquarium review could not place %s at %s: %s" % [def_id, origin, shop_editor.last_check.why])
		return null
	return world.grid.item(shop_editor.last_item_id)


func _frame(placed: PlacedItem, zoom: float, shift: Vector2) -> void:
	var rig: CameraRig = $CameraRig as CameraRig
	var at: Vector3 = GridMath.cell_to_world(placed.origin)
	var centre: Vector2 = Vector2(at.x + 0.25, at.z) + shift
	rig.edge_pan_enabled = false
	rig.minimum_zoom = 1.0
	rig.initial_yaw_degrees = 45.0
	rig.initial_focus = centre
	rig.initial_zoom = zoom
	rig.reset_view()
	rig.set_process(false)
	refresh_presentation()
