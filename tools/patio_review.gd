extends "res://src/world/main.gd"
## Explicit unsaved view fixture, never a balance sample. Capture either
## patio_review_sunny.tscn or patio_review_rain.tscn with --speed=0 --frames=60.
## Pays for the whole patio, two outdoor tables and a bench through the real
## editor, forces the day's weather (no random draw), opens and admits ten
## guests who walk to their own seats. Sun: four guests sit outside. Rain: the
## patio stays empty while guests sit indoors.

const WARMUP_TICKS: int = 120
const ADMITTED_GUESTS: int = 10
const FIXTURE_CASH: int = 2000

@export var review_weather: int = WeatherState.Kind.SUNNY

var _review_ready: bool = false
var _review_table_ids: Array[int] = []


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 243
	super._ready()
	Clock.set_speed(0)
	if sim == null or shop_editor == null or Clock.sim.phase != SimClock.Phase.MORNING \
			or review_weather not in [WeatherState.Kind.SUNNY, WeatherState.Kind.RAIN]:
		_review_fail("requires a fresh morning and a sunny or rain fixture")
		return
	world.weather.kind = review_weather as WeatherState.Kind
	Economy.add_cash(FIXTURE_CASH, Ledger.OTHER, "Patio visual review funding")
	if not shop_patio(shop_editor.patio_area().cells(), true):
		_review_fail("could not buy patio cells: " + shop_editor.last_check.why)
		return
	for origin: Vector2i in ProbeSetups.patio_table_origins(world.grid):
		if not shop_buy(&"patio_table_2", origin):
			_review_fail("could not buy outdoor table: " + shop_editor.last_check.why)
			return
		_review_table_ids.append(world.grid.item_at(origin).id)
	# At the far end, so it never blocks the narrow walk to the right table.
	if not shop_buy(&"patio_waiting_bench", world.grid.entries()[0] + Vector2i(7, 0)):
		_review_fail("could not buy outdoor bench: " + shop_editor.last_check.why)
		return
	if not Clock.sim.start_service():
		_review_fail("could not open the real service")
		return
	for index: int in ADMITTED_GUESTS:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 243001 + index
		sim.add_customer(world.grid.entries()[0], random)
	run_ticks(WARMUP_TICKS)
	var rig: CameraRig = $CameraRig
	rig.minimum_zoom = 3.0
	rig.edge_pan_enabled = false
	rig.initial_yaw_degrees = 35.0
	var entry: Vector3 = GridMath.cell_to_world(world.grid.entries()[0])
	rig.initial_focus = Vector2(entry.x + 0.25, entry.z + 0.4)
	rig.initial_zoom = 4.0
	rig.reset_view()
	rig.set_process(false)
	($ShopView as ShopView).set_wall_mode(ShopView.WallMode.UP)
	_refresh_weather()
	($ShopView as ShopView)._process(0.0)
	_review_ready = true


## Read by tools/screenshot.gd after the frame is drawn.
func patio_review_evidence() -> Dictionary:
	var outdoor: Array[Dictionary] = []
	var tables: Dictionary[int, bool] = {}
	var indoor_seated: int = 0
	var view: ShopView = $ShopView
	for guest: CustomerAgent in sim.customers():
		var seated: bool = AgentPresentationController.frame_for(guest, world).seated \
			and guest.cell == guest.seat_cell
		if not _review_table_ids.has(guest.table_item_id):
			indoor_seated += 1 if seated else 0
			continue
		var person: PersonView = view.agent_nodes.get(guest.id) as PersonView
		if seated:
			tables[guest.table_item_id] = true
		outdoor.append({"id": guest.id, "cell": [guest.cell.x, guest.cell.y], "seated": seated,
			"clip": String(person.current_clip()) if person != null else ""})
	return {"ready": _review_ready, "kind": int(world.weather.kind), "world_tick": world.now,
		"patio_cells": shop_editor.bought_patio().size(), "outdoor_guests": outdoor,
		"seated_tables": tables.size(), "indoor_seated": indoor_seated}


func patio_review_valid(state: Dictionary) -> bool:
	if state.get("ready") != true or state.get("world_tick") != WARMUP_TICKS \
			or state.get("patio_cells") != shop_editor.patio_area().cells().size():
		return false
	var outdoor: Array = state.get("outdoor_guests", [])
	if review_weather == WeatherState.Kind.RAIN:
		return outdoor.is_empty() and int(state.get("indoor_seated", 0)) > 0
	if state.get("seated_tables") != 2 or outdoor.size() < 2:
		return false
	for guest: Dictionary in outdoor:
		if guest.get("seated") != true or guest.get("clip") != "sit":
			return false
	return true


func _review_fail(message: String) -> void:
	push_error("PATIO_REVIEW: " + message)
