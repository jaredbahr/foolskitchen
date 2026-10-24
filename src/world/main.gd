extends Node3D
## The game session for the Tier 1 shop: builds the restaurant, drives it from
## Clock, keeps the books, shows the evening report at closing and autosaves
## each new morning.
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
## Closed-phase edits are persisted by the next normal morning autosave.
var shop_editor: ShopEditor
## Cookable dishes/prices belong to this shop, never to shared recipe resources.
var menu_settings: MenuSettings
var last_menu_save_error: Error = OK

var _previous_clock: SimClock = null
var _started: bool = false
var _skip_next_autosave: bool = false
var _loaded_layout: ShopLayout = null
var _loaded_menu: MenuSettings = null
var _report: Control
var _inspect_panel: InspectPanel
var _debug_overlay: DebugOverlay
var _debug_geometry: DebugGeometry
var _menu_panel: MenuPanel


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
	menu_settings = MenuSettings.new(_cookable_recipes(LAYOUT))
	_apply_menu(sim, menu_settings)
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
	_menu_panel = $Overlay/MenuPanel
	_menu_panel.bind_menu(menu_settings)
	_menu_panel.set_phase(Clock.sim.phase)
	if not _menu_panel.enable_requested.is_connected(_on_menu_enable_requested):
		_menu_panel.enable_requested.connect(_on_menu_enable_requested)
		_menu_panel.price_requested.connect(_on_menu_price_requested)
	if not $HUD.is_connected(&"menu_pressed", toggle_menu):
		$HUD.connect(&"menu_pressed", toggle_menu)
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


## Wires the session to the autoloads and opens the first morning.
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
	# Keep the old world detached while save providers restore the new session.
	Clock.attach_world(null)
	for autoload: Node in [Clock, GameState, Economy]:
		autoload.call(&"register_save_provider")
	SaveSystem.register("shop", _capture_shop, _restore_shop)
	SaveSystem.register("menu", _capture_menu, _restore_menu)
	var loaded: bool = use_saves and _load_autosave()
	if not loaded:
		_skip_next_autosave = use_saves and SaveSystem.list_slots().has(save_slot)
		_new_game()
	world.clock = Clock.sim
	sim.stock = Economy.stock
	sim.use_rng(GameState.rng(&"customers"))
	sim.spawner.min_gap = TUNING.arrival_gap_min
	sim.spawner.max_gap = TUNING.arrival_gap_max
	shop_editor = ShopEditor.new(sim, content, ShopEditBooks.new(Economy.can_spend_without_loan, Economy.add_cash))
	_connect_session()
	Clock.attach_world(world, sim.advance)
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


func _exit_tree() -> void:
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
			if _menu_panel != null and _menu_panel.visible:
				_menu_panel.hide()
			else:
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


## Builds the evening report for `day` from the ledger and today's counters.
func build_report(day: int) -> DayReport:
	var report := DayReport.new()
	report.day = day
	var totals: Dictionary = Economy.ledger.day_totals(day)
	for category: StringName in totals:
		var amount: int = totals[category]
		if amount > 0:
			report.income[category] = amount
		elif amount < 0:
			report.costs[category] = -amount
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
	GameState.new_run(int(Time.get_unix_time_from_system()))
	Economy.reset(TUNING.starting_cash)
	_loaded_layout = null
	_loaded_menu = null
	sim.stock = Economy.stock
	world.log_event("New game: $%d to start" % TUNING.starting_cash)


func _load_autosave() -> bool:
	_loaded_layout = null
	_loaded_menu = null
	if not SaveSystem.list_slots().has(save_slot):
		return false
	if SaveSystem.load_game(save_slot) != OK:
		world.log_event("Autosave could not be loaded; starting a new game")
		return false
	if Clock.sim.phase != SimClock.Phase.MORNING:
		world.log_event("Autosave is not from a morning; starting a new game")
		return false
	var layout: ShopLayout = _loaded_layout if _loaded_layout != null else LAYOUT
	var choices: MenuSettings = _loaded_menu if _loaded_menu != null else MenuSettings.new(_cookable_recipes(layout))
	if not choices.is_valid():
		return false
	if _loaded_layout != null:
		var errors: Array[String] = []
		var candidate: RestaurantSim = RestaurantSim.create(_loaded_layout, content, 1, errors, Economy.stock, true, true)
		if not errors.is_empty():
			return false
		sim = candidate
		world = candidate.world
	menu_settings = choices
	_apply_menu(sim, menu_settings)
	_bind_world_presentation()
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


func _capture_menu() -> Dictionary:
	return menu_settings.to_dict() if menu_settings != null else {}


func _restore_menu(data: Dictionary) -> bool:
	var layout: ShopLayout = _loaded_layout if _loaded_layout != null else LAYOUT
	var choices: MenuSettings = MenuSettings.new(_cookable_recipes(layout))
	if not choices.from_dict(data):
		return false
	_loaded_menu = choices
	return true


## Station definitions decide availability; temporary path/stock problems do not
## rewrite the player's menu. Tier 1 remains the currently unlocked recipe set.
func _cookable_recipes(layout: ShopLayout) -> Array[RecipeDef]:
	var stations: Dictionary[StringName, bool] = {}
	var fridge: bool = false
	var pass_counter: bool = false
	for placement: ShopPlacement in layout.placements:
		var definition: ItemDef = content.item(placement.item_id)
		if definition == null:
			continue
		if definition.category == ItemDef.Category.STORAGE and definition.station_type == &"fridge" and not definition.work_cells.is_empty():
			fridge = true
		elif definition.category == ItemDef.Category.PASS and definition.work_cells.size() >= 2:
			pass_counter = true
		elif definition.category == ItemDef.Category.STATION and not definition.work_cells.is_empty():
			stations[definition.station_type] = true
	var recipes: Array[RecipeDef] = []
	if not fridge or not pass_counter:
		return recipes
	for definition: RecipeDef in content.recipes():
		if definition.unlock_tier != 1:
			continue
		var cookable: bool = true
		for step: RecipeStep in definition.steps:
			if not stations.has(step.station_type):
				cookable = false
				break
		if cookable:
			recipes.append(definition)
	return recipes


func _apply_menu(restaurant: RestaurantSim, choices: MenuSettings) -> void:
	restaurant.menu = choices.enabled_recipes()
	restaurant.prices.clear()
	restaurant.pricing_tuning = TUNING
	for definition: RecipeDef in choices.recipes():
		var price: int = choices.price_of(definition)
		if price != definition.standard_price:
			restaurant.prices[definition.id] = price


func can_edit_menu() -> bool:
	return _started and menu_settings != null and menu_settings.is_valid() and Clock.sim.phase == SimClock.Phase.MORNING


func menu_set_enabled(recipe_id: StringName, enabled: bool) -> bool:
	if not can_edit_menu():
		return false
	var before: bool = menu_settings.is_enabled(recipe_id)
	if not menu_settings.set_enabled(recipe_id, enabled):
		return false
	_apply_menu(sim, menu_settings)
	_menu_panel.refresh()
	if before != menu_settings.is_enabled(recipe_id):
		save_menu_changes()
	return true


func menu_set_price(recipe_id: StringName, price: int) -> bool:
	if not can_edit_menu() or menu_settings.recipe(recipe_id) == null:
		return false
	var definition: RecipeDef = menu_settings.recipe(recipe_id)
	var before: int = menu_settings.price_of(definition)
	menu_settings.set_price(recipe_id, price)
	_apply_menu(sim, menu_settings)
	_menu_panel.refresh()
	if before != menu_settings.price_of(definition):
		save_menu_changes()
	return true


func save_menu_changes() -> Error:
	if not can_edit_menu():
		last_menu_save_error = ERR_BUSY
		return last_menu_save_error
	# A user menu change is an explicit MORNING persistence boundary for #52.
	# It saves committed settings without running day setup or restocking again.
	last_menu_save_error = SaveSystem.save_game(save_slot) if use_saves else OK
	if last_menu_save_error != OK:
		world.log_event("Menu choices kept, but autosave failed (%s). Retry saving without repeating the edit" % error_string(last_menu_save_error))
	return last_menu_save_error


func toggle_menu() -> void:
	if _menu_panel != null:
		set_menu_visible(not _menu_panel.visible)


## Idempotent production path for the HUD and genuine review captures.
func set_menu_visible(value: bool) -> bool:
	if _menu_panel == null or (value and not can_edit_menu()):
		return false
	_menu_panel.set_phase(Clock.sim.phase)
	_menu_panel.visible = value
	return true


func is_menu_visible() -> bool:
	return _menu_panel != null and _menu_panel.visible


func _on_menu_enable_requested(recipe_id: StringName, enabled: bool) -> void:
	menu_set_enabled(recipe_id, enabled)
	_menu_panel.refresh()


func _on_menu_price_requested(recipe_id: StringName, price: int) -> void:
	menu_set_price(recipe_id, price)
	_menu_panel.refresh()


func shop_move(item_id: int, origin: Vector2i, quarter_turns: int) -> bool:
	return shop_editor != null and shop_editor.move(item_id, origin, quarter_turns)


func shop_buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0) -> bool:
	return shop_editor != null and shop_editor.buy(def_id, origin, quarter_turns)


func shop_sell(item_id: int) -> int:
	return shop_editor.sell(item_id) if shop_editor != null else -1


## Morning setup: new counters, a stocked fridge, and an autosave.
func _begin_morning() -> void:
	sim.start_day()
	dishes_sold_today.clear()
	shown_report = null
	_restock()
	Economy.ledger.prune_before(Clock.sim.day - Ledger.HISTORY_DAYS)
	_report.hide()
	if use_saves and not _skip_next_autosave:
		SaveSystem.save_game(save_slot)
	_skip_next_autosave = false
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
	if _menu_panel != null:
		_menu_panel.set_phase(phase)
		if phase != SimClock.Phase.MORNING:
			_menu_panel.hide()
	if phase == SimClock.Phase.MORNING:
		_begin_morning()


func _on_next_day_pressed() -> void:
	Clock.sim.next_day()
