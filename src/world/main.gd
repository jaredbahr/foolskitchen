extends Node3D
## The game session for the Tier 1 shop: builds the restaurant, drives it from
## Clock, keeps the books, shows the evening report at closing and autosaves
## each new morning and after completed closed-shop furniture edits.
##
## Day loop:
##   MORNING  -> fridge topped up, "Open shop" (HUD) starts service
##   OPEN / LAST_ORDERS -> RestaurantSim runs (guests, staff, kitchen)
##   CLOSED   -> wages and rent charged, evening report shown
##   "Next day" -> MORNING of the next day, autosave
## F10 starts a new game (deletes the autosave).

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const AUTOSAVE_SLOT: String = "autosave"
const SHOP_CHECKPOINT_VERSION: int = 1
const MAX_CHECKPOINT_COUNT: int = 1000000000

## Save slot used by autosave and the startup load. Tests change it.
var save_slot: String = AUTOSAVE_SLOT
## When false, _ready() neither loads nor writes saves (used by tests).
var use_saves: bool = true
var sim: RestaurantSim
var world: SimWorld
var content: ContentDB
## The last evening report put on screen (for tests and tools).
var shown_report: DayReport = null
## Dishes sold today (recipe id -> count), for the evening report.
var dishes_sold_today: Dictionary[StringName, int] = {}
## All furniture mutations go through the wrappers below so autosave follows books.
var shop_editor: ShopEditor
## Save-only retries never replay the furniture mutation or its cash movement.
var last_shop_save_error: Error = OK
## A failed/unsupported startup slot stays protected until explicit F10 new game.
var shop_save_blocked: bool:
	get:
		return _shop_save_blocked

var _previous_clock: SimClock = null
var _started: bool = false
var _shop_save_blocked: bool = false
var _startup_load_error: Error = OK
var _loaded_layout: ShopLayout = null
var _loaded_checkpoint: Dictionary = {}
var _report: Control
var _inspect_panel: InspectPanel
var _debug_overlay: DebugOverlay
var _debug_geometry: DebugGeometry


## Builds the restaurant and the read-only view. Safe before tree readiness.
## HUD binding reads Clock/Economy; session and save registration wait for start().
func initialize() -> void:
	if sim != null:
		return
	content = ContentDB.new()
	var load_errors: PackedStringArray = content.load_all()
	if not load_errors.is_empty():
		push_error("Cannot load shop content: %s" % load_errors)
		return
	var errors: Array[String] = []
	sim = RestaurantSim.create(LAYOUT, content, 1, errors)
	if not errors.is_empty():
		push_error("Cannot build shop: %s" % errors)
		sim = null
		return
	world = sim.world
	_bind_world_presentation()


## Also runs after startup replaces the layout: no inspector keeps the old world.
func _bind_world_presentation() -> void:
	var view: ShopView = $ShopView
	view.show_world(world)
	var camera: CameraRig = $CameraRig
	camera.grid_floor = view.floor_mesh
	var shop_half: Vector2 = Vector2(world.grid.size) * GridMath.CELL_SIZE * 0.5
	camera.initial_focus = shop_half
	# Pan around the shop itself, with a 2 m margin on every side.
	camera.pan_center = shop_half
	camera.pan_limits = shop_half + Vector2(2.0, 2.0)
	camera.initial_zoom = 12.0
	camera.reset_view()
	if not camera.yaw_snapped.is_connected(view.set_camera_quarter):
		camera.yaw_snapped.connect(view.set_camera_quarter)
	view.set_camera_quarter(camera.camera_quarter())
	$HUD.bind_shop_view(view)
	_report = $Overlay/EveningReport
	_report.hide()
	_inspect_panel = $Overlay/InspectPanel
	_debug_overlay = $Overlay/DebugOverlay
	_debug_geometry = $DebugGeometry
	_inspect_panel.bind_world(world)
	_debug_overlay.bind_world(world)
	refresh_presentation()


func _ready() -> void:
	start()


func _process(_delta: float) -> void:
	if world == null:
		return
	_debug_overlay.sample_rates(float(Time.get_ticks_usec()) / 1000000.0, Engine.get_frames_per_second())
	# Run after ShopView's interpolation, including while the sim is paused.
	refresh_presentation()


## Wires the session to the autoloads and starts or resumes a closed checkpoint.
## Runs once; _ready() calls it, and tests call it
## directly because the test runner never delivers _ready().
func start() -> void:
	if _started:
		return
	initialize()
	if sim == null:
		return
	_started = true
	_previous_clock = Clock.sim
	# Providers may replace Clock.sim. Do not let that replacement rewrite an old
	# attached world while the startup candidate is still being validated.
	Clock.attach_world(null)
	for autoload: Node in [Clock, GameState, Economy]:
		autoload.call(&"register_save_provider")
	SaveSystem.register("shop", _capture_shop, _restore_shop)
	SaveSystem.register("shop_session", _capture_shop_session, _restore_shop_session)
	var had_save: bool = use_saves and SaveSystem.list_slots().has(save_slot)
	var loaded: bool = use_saves and _load_autosave()
	if not loaded:
		_shop_save_blocked = had_save
		_new_game()
		if not _install_restaurant(LAYOUT, false):
			push_error("Cannot build the default shop")
			return
		world.log_event("New game: $%d to start" % TUNING.starting_cash)
		if had_save:
			last_shop_save_error = ERR_UNAVAILABLE
			world.log_event("Autosave could not be loaded (%s); it is protected. F10 starts a new saved game" % error_string(_startup_load_error))
	_connect_session()
	Clock.attach_world(world, sim.advance)
	Clock.set_speed(0)
	if loaded:
		if Clock.sim.phase == SimClock.Phase.MORNING:
			# Preserve the tested single arrival-gap draw after restoring GameState.
			# Stock and purchases are already saved: do not restock or autosave again.
			sim.start_day()
			dishes_sold_today.clear()
			shown_report = null
			_report.hide()
		else:
			_resume_closed_checkpoint()
		refresh_presentation()
	else:
		_begin_morning()


func _connect_session() -> void:
	if not _report.is_connected(&"next_day_pressed", _on_next_day_pressed):
		_report.connect(&"next_day_pressed", _on_next_day_pressed)
	sim.customer_paid.connect(_on_customer_paid)
	sim.service_closed.connect(_on_service_closed)
	if not EventBus.day_phase_changed.is_connected(_on_day_phase_changed):
		EventBus.day_phase_changed.connect(_on_day_phase_changed)
	if not EventBus.sim_ticked.is_connected(_on_inspection_tick):
		EventBus.sim_ticked.connect(_on_inspection_tick)


## Startup-only installation, after all save validation/provider restores succeed.
func _install_restaurant(layout: ShopLayout, edited_layout: bool) -> bool:
	var errors: Array[String] = []
	var candidate: RestaurantSim = RestaurantSim.create(layout, content, 1, errors, Economy.stock, true, edited_layout)
	if not errors.is_empty():
		return false
	if sim != null and sim.customer_paid.is_connected(_on_customer_paid):
		sim.customer_paid.disconnect(_on_customer_paid)
	if sim != null and sim.service_closed.is_connected(_on_service_closed):
		sim.service_closed.disconnect(_on_service_closed)
	sim = candidate
	world = candidate.world
	world.clock = Clock.sim
	sim.stock = Economy.stock
	sim.use_rng(GameState.rng(&"customers"))
	sim.spawner.min_gap = TUNING.arrival_gap_min
	sim.spawner.max_gap = TUNING.arrival_gap_max
	shop_editor = ShopEditor.new(sim, content, ShopEditBooks.new(Economy.can_spend_without_loan, Economy.add_cash))
	_bind_world_presentation()
	return true


func _exit_tree() -> void:
	_unregister_shop_providers()
	if sim != null and sim.customer_paid.is_connected(_on_customer_paid):
		sim.customer_paid.disconnect(_on_customer_paid)
	if sim != null and sim.service_closed.is_connected(_on_service_closed):
		sim.service_closed.disconnect(_on_service_closed)
	if EventBus.day_phase_changed.is_connected(_on_day_phase_changed):
		EventBus.day_phase_changed.disconnect(_on_day_phase_changed)
	if EventBus.sim_ticked.is_connected(_on_inspection_tick):
		EventBus.sim_ticked.disconnect(_on_inspection_tick)
	if world != null and Clock.attached_world == world:
		Clock.attach_world(null)
		if _previous_clock != null:
			Clock.sim = _previous_clock


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPARENTED:
		_unregister_shop_providers()


func _unregister_shop_providers() -> void:
	SaveSystem.unregister("shop", _capture_shop)
	SaveSystem.unregister("shop_session", _capture_shop_session)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.physical_keycode == KEY_F10:
			start_over()
		elif key.physical_keycode == KEY_F3:
			set_debug_visible(not is_debug_visible())
			if is_inside_tree():
				get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_ESCAPE:
			clear_selection()
			if is_inside_tree():
				get_viewport().set_input_as_handled()
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		pick_screen_position(mouse.position)
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## Uses the same floor-plane selection path for real clicks and capture tools.
func pick_screen_position(screen_position: Vector2) -> void:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return
	var hit: Variant = Picker.floor_intersection(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if hit is Vector3:
		select_at_world_position(hit)


## Chooses the nearest drawn agent, otherwise the item at the clicked cell.
func select_at_world_position(world_position: Vector3) -> void:
	if world == null:
		return
	var view: ShopView = $ShopView
	var agent_id: int = Picker.pick_agent(world_position, view.drawn_agent_positions())
	if agent_id >= 0:
		select_agent(agent_id)
		return
	var item: PlacedItem = world.grid.item_at(GridMath.world_to_cell(world_position))
	if item != null:
		_inspect_panel.show_item(item.id)
		refresh_presentation()
	else:
		clear_selection()


## Selects a live agent through the production inspector API.
func select_agent(agent_id: int) -> bool:
	_inspect_panel.show_agent(agent_id)
	refresh_presentation()
	return _inspect_panel.selected_agent_id == agent_id


func clear_selection() -> void:
	_inspect_panel.clear()
	refresh_presentation()


func set_debug_visible(value: bool) -> void:
	_debug_overlay.set_enabled(value)
	refresh_presentation()


func is_debug_visible() -> bool:
	return _debug_overlay != null and _debug_overlay.is_enabled()


## Read-only diagnostic state used by integration tests and real captures.
func inspection_state() -> Dictionary:
	var role: String = ""
	for agent: SimAgent in world.agents:
		if agent.id == _inspect_panel.selected_agent_id:
			role = "guest" if agent is CustomerAgent else str(agent.role)
	return {
		"selected_agent_id": _inspect_panel.selected_agent_id,
		"selected_item_id": _inspect_panel.selected_item_id,
		"selected_role": role, "panel_visible": _inspect_panel.visible,
		"debug_visible": is_debug_visible(), "world_tick": world.now,
	}


## Refreshes after completed morning setup, removals and paused grid edits too.
func refresh_presentation() -> void:
	if _inspect_panel == null or _debug_overlay == null or _debug_geometry == null:
		return
	_inspect_panel.refresh()
	if _debug_overlay.is_enabled():
		_debug_overlay.refresh()
	var view: ShopView = $ShopView
	_debug_geometry.update_geometry(world, view.drawn_agent_positions(), view.drawn_agent_colors(), _inspect_panel.selected_agent_id, _debug_overlay.is_enabled())


func _on_inspection_tick(_tick: int) -> void:
	# Text follows every tick; geometry follows the drawn agents once per frame.
	_inspect_panel.refresh()
	if _debug_overlay.is_enabled():
		_debug_overlay.refresh()


## Deletes the autosave and restarts the scene from day 1.
func start_over() -> void:
	if use_saves:
		SaveSystem.delete_slot(save_slot)
	get_tree().reload_current_scene()


## Advances the restaurant by `ticks` sim ticks right now (tests and tools).
func run_ticks(ticks: int) -> void:
	for i in ticks:
		if Clock.sim.phase != SimClock.Phase.OPEN and Clock.sim.phase != SimClock.Phase.LAST_ORDERS:
			break
		sim.advance()
		EventBus.sim_ticked.emit(Clock.sim.tick)
	refresh_presentation()


## Builds the current service day's report from retained entry flows and counters.
## A category may contain both purchases and refunds; neither flow is netted out.
func build_report(day: int) -> DayReport:
	var report := DayReport.new()
	report.day = day
	for entry: Dictionary in Economy.ledger.entries_for_day(day):
		var category: StringName = entry["category"]
		var amount: int = entry["amount"]
		if amount > 0:
			report.income[category] = int(report.income.get(category, 0)) + amount
		elif amount < 0:
			report.costs[category] = int(report.costs.get(category, 0)) - amount
	report.dishes_sold = dishes_sold_today.duplicate()
	report.customers_served = sim.served_today
	report.customers_lost = sim.lost_today
	for reason: StringName in sim.leave_reasons_today:
		if reason != &"happy":
			report.leave_reasons[reason] = sim.leave_reasons_today[reason]
	return report


func _new_game() -> void:
	# A fresh clock and seed too, so a half-loaded save can't leave its day
	# or random state behind.
	Clock.sim = SimClock.new()
	Clock.set_speed(1)
	Clock.set_speed(0)
	GameState.new_run(int(Time.get_unix_time_from_system()))
	Economy.reset(TUNING.starting_cash)
	_loaded_layout = null
	_loaded_checkpoint.clear()
	dishes_sold_today.clear()
	shown_report = null


func _load_autosave() -> bool:
	_startup_load_error = ERR_FILE_NOT_FOUND
	if not SaveSystem.list_slots().has(save_slot):
		return false
	_loaded_layout = null
	_loaded_checkpoint.clear()
	_startup_load_error = SaveSystem.load_game(save_slot, _validate_shop_sections)
	if _startup_load_error != OK:
		return false
	var layout: ShopLayout = _loaded_layout if _loaded_layout != null else LAYOUT
	if not _install_restaurant(layout, _loaded_layout != null):
		_startup_load_error = ERR_INVALID_DATA
		return false
	return true


func _capture_shop() -> Dictionary:
	return shop_editor.to_dict() if shop_editor != null else {}


## Restore callbacks only stage decoded data. Live replacement waits for OK.
func _restore_shop(data: Dictionary) -> bool:
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, content, errors)
	if layout == null:
		return false
	_loaded_layout = layout
	return true


func _capture_shop_session() -> Dictionary:
	var reasons: Dictionary = {}
	for reason: StringName in sim.leave_reasons_today:
		reasons[String(reason)] = sim.leave_reasons_today[reason]
	var dishes: Dictionary = {}
	for recipe: StringName in dishes_sold_today:
		dishes[String(recipe)] = dishes_sold_today[recipe]
	return {"version": SHOP_CHECKPOINT_VERSION, "day": Clock.sim.day,
		"phase": int(Clock.sim.phase), "served": sim.served_today, "lost": sim.lost_today,
		"reasons": reasons, "dishes": dishes}


func _restore_shop_session(data: Dictionary) -> bool:
	var checkpoint: Dictionary = _decode_shop_checkpoint(data)
	if checkpoint.is_empty():
		return false
	_loaded_checkpoint = checkpoint
	return true


## Called on deep-copied sections before ANY providers restore. No live writes.
func _validate_shop_sections(sections: Dictionary) -> bool:
	var clock_value: Variant = sections.get("clock")
	if not clock_value is Dictionary:
		return false
	var clock_data: Dictionary = clock_value
	var day: Variant = clock_data.get("day", 1)
	var phase: Variant = clock_data.get("phase", SimClock.Phase.MORNING)
	if not _checkpoint_integer(day, 1) or not _checkpoint_integer(phase):
		return false
	if int(phase) != SimClock.Phase.MORNING and int(phase) != SimClock.Phase.CLOSED:
		return false
	if sections.has("shop"):
		if not sections["shop"] is Dictionary:
			return false
		var errors: Array[String] = []
		if ShopEditor.from_dict(sections["shop"], LAYOUT, content, errors) == null:
			return false
	if not sections.has("shop_session"):
		return int(phase) == SimClock.Phase.MORNING
	if not sections["shop_session"] is Dictionary:
		return false
	var checkpoint: Dictionary = _decode_shop_checkpoint(sections["shop_session"])
	if checkpoint.is_empty() or checkpoint["day"] != int(day) or checkpoint["phase"] != int(phase):
		return false
	return int(phase) == SimClock.Phase.MORNING or sections.has("shop")


## Counts are bounded integers; totals, successful visits and sold dishes agree.
func _decode_shop_checkpoint(data: Dictionary) -> Dictionary:
	if not _checkpoint_integer(data.get("version"), SHOP_CHECKPOINT_VERSION) or int(data["version"]) != SHOP_CHECKPOINT_VERSION:
		return {}
	for field: String in ["day", "phase", "served", "lost"]:
		if not _checkpoint_integer(data.get(field), 1 if field == "day" else 0):
			return {}
	var phase: int = int(data["phase"])
	if phase != SimClock.Phase.MORNING and phase != SimClock.Phase.CLOSED:
		return {}
	if not data.get("reasons") is Dictionary or not data.get("dishes") is Dictionary:
		return {}
	var served: int = int(data["served"])
	var lost: int = int(data["lost"])
	var reasons: Dictionary[StringName, int] = {}
	var reason_total: int = 0
	var raw_reasons: Dictionary = data["reasons"]
	for key: Variant in raw_reasons:
		if not key is String or not _checkpoint_integer(raw_reasons[key]):
			return {}
		var reason: StringName = StringName(key)
		if not CustomerAgent.PLAYER_REASONS.has(reason) and not [ &"happy", &"kitchen_failed", &"no_menu", &"too_expensive" ].has(reason):
			return {}
		reasons[reason] = int(raw_reasons[key])
		reason_total += reasons[reason]
		if reason_total > served + lost:
			return {}
	var dishes: Dictionary[StringName, int] = {}
	var dish_total: int = 0
	var raw_dishes: Dictionary = data["dishes"]
	for key: Variant in raw_dishes:
		if not key is String or content.recipe(StringName(key)) == null or not _checkpoint_integer(raw_dishes[key]):
			return {}
		dishes[StringName(key)] = int(raw_dishes[key])
		dish_total += int(raw_dishes[key])
		if dish_total > served:
			return {}
	if reason_total != served + lost or int(reasons.get(&"happy", 0)) != served or dish_total != served:
		return {}
	if phase == SimClock.Phase.MORNING and (served != 0 or lost != 0):
		return {}
	return {"day": int(data["day"]), "phase": phase, "served": served, "lost": lost,
		"reasons": reasons, "dishes": dishes}


func _checkpoint_integer(value: Variant, minimum: int = 0) -> bool:
	if value is int:
		return value >= minimum and value <= MAX_CHECKPOINT_COUNT
	if value is float:
		return is_finite(value) and value >= minimum and value <= MAX_CHECKPOINT_COUNT and floorf(value) == value
	return false


## CLOSED checkpoints intentionally rebuild clean paused staff/tasks, not old
## bussing reservations. The saved counters/report survive; costs are not replayed.
func _resume_closed_checkpoint() -> void:
	sim.served_today = _loaded_checkpoint["served"]
	sim.lost_today = _loaded_checkpoint["lost"]
	sim.leave_reasons_today.clear()
	for reason: StringName in _loaded_checkpoint["reasons"]:
		sim.leave_reasons_today[reason] = _loaded_checkpoint["reasons"][reason]
	dishes_sold_today.clear()
	for recipe: StringName in _loaded_checkpoint["dishes"]:
		dishes_sold_today[recipe] = _loaded_checkpoint["dishes"][recipe]
	_refresh_closed_report()


func shop_move(item_id: int, origin: Vector2i, quarter_turns: int) -> bool:
	if shop_editor == null or not shop_editor.move(item_id, origin, quarter_turns):
		return false
	_after_shop_edit()
	return true


func shop_buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0) -> bool:
	if shop_editor == null or not shop_editor.buy(def_id, origin, quarter_turns):
		return false
	_after_shop_edit()
	return true


func shop_sell(item_id: int) -> int:
	if shop_editor == null:
		return -1
	var refund: int = shop_editor.sell(item_id)
	if refund >= 0:
		_after_shop_edit()
	return refund


func _after_shop_edit() -> void:
	save_shop_changes()
	refresh_presentation()


## A save failure does not undo an edit. Retry this method, not its mutation.
func save_shop_changes() -> Error:
	if shop_editor == null or not _started:
		last_shop_save_error = ERR_UNCONFIGURED
		return last_shop_save_error
	if not shop_editor.can_edit():
		last_shop_save_error = ERR_BUSY
		return last_shop_save_error
	_refresh_closed_report()
	if _shop_save_blocked:
		last_shop_save_error = ERR_UNAVAILABLE
		world.log_event("Autosave is protected after a failed load; F10 starts a new saved game")
		return last_shop_save_error
	last_shop_save_error = SaveSystem.save_game(save_slot) if use_saves else OK
	if last_shop_save_error != OK:
		world.log_event("Shop state kept, but autosave failed (%s). Retry saving without repeating the edit" % error_string(last_shop_save_error))
	return last_shop_save_error


func _refresh_closed_report() -> void:
	if Clock.sim.phase == SimClock.Phase.CLOSED:
		shown_report = build_report(Clock.sim.day)
		_report.call(&"show_report", shown_report)


## Morning setup: new counters, a stocked fridge, and an autosave.
func _begin_morning() -> void:
	sim.start_day()
	dishes_sold_today.clear()
	shown_report = null
	_restock()
	Economy.ledger.prune_before(Clock.sim.day - Ledger.HISTORY_DAYS)
	_report.hide()
	if use_saves and not _shop_save_blocked:
		save_shop_changes()
	refresh_presentation()


func _restock() -> void:
	for id: StringName in TUNING.morning_stock:
		var ingredient := content.ingredient(id)
		if ingredient == null:
			continue
		var missing: int = TUNING.morning_stock[id] - Economy.stock.count(id)
		if missing > 0 and not Economy.buy_ingredient(id, missing, ingredient.unit_cost):
			world.log_event("Couldn't afford %d %s this morning" % [missing, id])


func _charge_closing_costs() -> void:
	for role: StringName in TUNING.wages:
		for agent: SimAgent in world.agents:
			if agent.role == role:
				Economy.add_cash(-TUNING.wages[role], Ledger.WAGES)
	if TUNING.daily_rent > 0:
		Economy.add_cash(-TUNING.daily_rent, Ledger.RENT)


func _on_customer_paid(_customer: CustomerAgent, order: Order, amount: int) -> void:
	Economy.add_cash(amount, Ledger.SALE)
	dishes_sold_today[order.recipe_id] = dishes_sold_today.get(order.recipe_id, 0) + 1


## Service is over and every guest's departure is recorded: close the books.
func _on_service_closed(day: int) -> void:
	_charge_closing_costs()
	shown_report = build_report(day)
	_report.call(&"show_report", shown_report)


func _on_day_phase_changed(_day: int, phase: int) -> void:
	if phase == SimClock.Phase.MORNING:
		_begin_morning()


func _on_next_day_pressed() -> void:
	Clock.sim.next_day()
