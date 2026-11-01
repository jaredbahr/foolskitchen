extends "res://src/world/main.gd"
## Explicit unsaved native view fixture, never a balance sample. Capture either
## patio_review_sunny.tscn or patio_review_rain.tscn with --speed=0 --frames=60.
## The real morning weather is disclosed, then overridden without a draw.

const WARMUP_TICKS: int = 120
const ADMITTED_GUESTS: int = 10
const FIXTURE_CASH: int = 2000

@export var review_weather: int = WeatherState.Kind.SUNNY

var _review_ready: bool = false
var _review_initial_weather: Dictionary = {}
var _review_override_rng_unchanged: bool = false
var _review_tick: int = 0
var _review_rng: Dictionary = {}
var _review_table_ids: Array[int] = []
var _review_guest_ids: Array[int] = []
var _review_cash_before: int = 0
var _review_construction_charge: int = 0


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 243
	super._ready()
	Clock.set_speed(0)
	if sim == null or shop_editor == null or Clock.sim.phase != SimClock.Phase.MORNING \
			or not world.weather.is_for_day(Clock.sim.day) \
			or review_weather not in [WeatherState.Kind.SUNNY, WeatherState.Kind.RAIN]:
		_review_fail("requires a fresh selected morning and sunny or rain fixture")
		return
	_review_initial_weather = world.weather.to_dict()
	var before: Dictionary = GameState._capture_save().duplicate(true)
	world.weather.kind = review_weather as WeatherState.Kind
	_review_override_rng_unchanged = before == GameState._capture_save()
	# Explicit review funding, separate from the free-construction probe. Main's
	# normal editor/history commands pay for all cells, both tables and a bench.
	Economy.add_cash(FIXTURE_CASH, Ledger.OTHER, "Patio visual review funding")
	_review_cash_before = Economy.cash
	if not shop_patio(shop_editor.patio_area().cells(), true):
		_review_fail("could not buy patio cells: " + shop_editor.last_check.why)
		return
	for origin: Vector2i in ProbeSetups.patio_table_origins():
		if not shop_buy(&"patio_table_2", origin):
			_review_fail("could not buy outdoor table: " + shop_editor.last_check.why)
			return
		_review_table_ids.append(world.grid.item_at(origin).id)
	if not shop_buy(&"patio_waiting_bench", Vector2i(8, 11)):
		_review_fail("could not buy outdoor bench: " + shop_editor.last_check.why)
		return
	_review_construction_charge = _review_cash_before - Economy.cash
	if review_weather == WeatherState.Kind.SUNNY:
		if not Clock.sim.start_service():
			_review_fail("could not open the real service")
			return
		for index: int in ADMITTED_GUESTS:
			var random: RandomNumberGenerator = RandomNumberGenerator.new()
			random.seed = 243001 + index
			var guest: CustomerAgent = sim.add_customer(world.grid.entries()[0], random)
			_review_guest_ids.append(guest.id)
		# Exactly one declared admission/walking budget; no pose, reservation,
		# task, meal-duration, payment or completion is assigned by this fixture.
		run_ticks(WARMUP_TICKS)
	else:
		if not set_menu_visible(true):
			_review_fail("could not show the real morning weather status")
			return
	_configure_review_camera()
	_refresh_weather()
	($ShopView as ShopView)._process(0.0)
	_review_tick = world.now
	_review_rng = GameState._capture_save().duplicate(true)
	_review_ready = true


func _configure_review_camera() -> void:
	var rig: CameraRig = $CameraRig
	rig.minimum_zoom = 3.0
	rig.edge_pan_enabled = false
	rig.initial_yaw_degrees = 0.0
	rig.initial_focus = Vector2(3.5, 5.9) if review_weather == WeatherState.Kind.SUNNY else Vector2(1.8, 6.1)
	rig.initial_zoom = 5.0
	rig.reset_view()
	rig.set_process(false)
	($ShopView as ShopView).set_wall_mode(ShopView.WallMode.UP)


## Screenshot reads this only after its actual frame_post_draw. The ordinary
## screenshot metadata owns the PNG path/hash; these are detached native reads.
func patio_review_evidence() -> Dictionary:
	var table_rows: Array[Dictionary] = []
	var seated: Array[Dictionary] = []
	var seated_tables: Dictionary[int, bool] = {}
	var view: ShopView = $ShopView
	var camera: Camera3D = $CameraRig/Camera3D
	for table_id: int in _review_table_ids:
		var table: PlacedItem = world.grid.item(table_id)
		var visual: ItemVisual = view.item_nodes.get(table_id) as ItemVisual
		table_rows.append({"id": table_id, "item": String((table.def as ItemDef).id) if table != null else "",
			"origin": [table.origin.x, table.origin.y] if table != null else [],
			"native_model": visual != null and visual.prop != null and visual.fallback == null,
			"visible": visual != null and visual.is_visible_in_tree()})
	for guest: CustomerAgent in sim.customers():
		if not _review_table_ids.has(guest.table_item_id):
			continue
		var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, world)
		var table: PlacedItem = world.grid.item(guest.table_item_id)
		var person: PersonView = view.agent_nodes.get(guest.id) as PersonView
		var actual_seated: bool = frame.seated and guest.has_arrived() and guest.cell == guest.seat_cell \
			and table != null and table.reserved_by(guest.seat_cell) == guest.id
		if actual_seated:
			seated_tables[guest.table_item_id] = true
		seated.append({"id": guest.id, "table": guest.table_item_id, "seated": actual_seated,
			"cell": [guest.cell.x, guest.cell.y], "state": int(guest.state),
			"seat_claimant": table.reserved_by(guest.seat_cell) if table != null else -1,
			"native_person": person != null and person.is_visible_in_tree(),
			"native_clip": String(person.current_clip()) if person != null else "",
			"head_in_view": person != null and _point_in_view(camera, person.global_transform * person.head_anchor_position())})
	var forecast: Label = $Overlay/MenuPanel/Panel/Content/WeatherForecast
	var expected_cost: int = shop_editor.patio_area().cells().size() * shop_editor.patio_area().cell_price \
		+ content.item(&"patio_table_2").price * 2 + content.item(&"patio_waiting_bench").price
	return {"tag": "PATIO_REVIEW", "ready": _review_ready,
		"fixture": "Explicit unsaved cash/weather/admission fixture; actual paid editor/history construction and real guest walking; not a natural-weather balance sample",
		"initial_selected_weather": _review_initial_weather, "kind": int(world.weather.kind), "day": world.weather.day,
		"weather_override_rng_unchanged": _review_override_rng_unchanged,
		"synthetic_cash_grant": FIXTURE_CASH, "nominal_construction_cost": expected_cost,
		"actual_construction_charge": _review_construction_charge, "capture_cash": Economy.cash,
		"admitted_guests": _review_guest_ids.size(), "admission_budget": ADMITTED_GUESTS,
		"warmup_ticks": WARMUP_TICKS if review_weather == WeatherState.Kind.SUNNY else 0,
		"world_tick": world.now, "paused_tick_unchanged": world.now == _review_tick,
		"named_streams_unchanged_while_paused": _review_rng == GameState._capture_save(),
		"phase": int(Clock.sim.phase), "speed": Clock.speed, "use_saves": use_saves,
		"patio_cells": shop_editor.bought_patio().size(), "tables": table_rows,
		"outdoor_guests": seated, "seated_tables": seated_tables.size(),
		"patio_seating_open": PatioRules.is_open(world.weather.kind), "live_guest_count": sim.customers().size(),
		"menu_visible": is_menu_visible(), "forecast": forecast.text,
		"forecast_visible": forecast.is_visible_in_tree() and get_viewport().get_visible_rect().encloses(forecast.get_global_rect()),
		"entries": [[world.grid.entries()[0].x, world.grid.entries()[0].y], [world.grid.entries()[1].x, world.grid.entries()[1].y]],
		"camera_position": str(camera.global_position), "camera_size": camera.size}


func patio_review_valid(state: Dictionary) -> bool:
	if state.get("tag") != "PATIO_REVIEW" or state.get("ready") != true \
			or state.get("kind") != review_weather or state.get("day") != 1 \
			or state.get("weather_override_rng_unchanged") != true or state.get("use_saves") != false \
			or state.get("paused_tick_unchanged") != true or state.get("named_streams_unchanged_while_paused") != true \
			or state.get("speed") != 0 or state.get("patio_cells") != 48 \
			or state.get("actual_construction_charge") != state.get("nominal_construction_cost") \
			or state.get("entries") != [[6, 11], [7, 11]]:
		return false
	var tables: Array = state.get("tables", [])
	if tables.size() != 2:
		return false
	for table: Dictionary in tables:
		if table.get("item") != "patio_table_2" or table.get("native_model") != true or table.get("visible") != true:
			return false
	var guests: Array = state.get("outdoor_guests", [])
	if review_weather == WeatherState.Kind.RAIN:
		return state.get("phase") == SimClock.Phase.MORNING and state.get("world_tick") == 0 \
			and guests.is_empty() and state.get("live_guest_count") == 0 and state.get("patio_seating_open") == false \
			and state.get("menu_visible") == true and state.get("forecast_visible") == true \
			and String(state.get("forecast", "")).contains("Patio closed in rain")
	if state.get("phase") != SimClock.Phase.OPEN or state.get("world_tick") != WARMUP_TICKS \
			or state.get("admitted_guests") != ADMITTED_GUESTS or state.get("seated_tables") != 2 or guests.size() < 2:
		return false
	for guest: Dictionary in guests:
		if guest.get("seated") != true or guest.get("seat_claimant") != guest.get("id") \
				or guest.get("native_person") != true or guest.get("native_clip") != "sit" or guest.get("head_in_view") != true:
			return false
	return true


func _point_in_view(camera: Camera3D, point: Vector3) -> bool:
	return not camera.is_position_behind(point) and get_viewport().get_visible_rect().has_point(camera.unproject_position(point))


func _review_fail(message: String) -> void:
	push_error("PATIO_REVIEW: " + message)
