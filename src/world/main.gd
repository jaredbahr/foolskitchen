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

var _previous_clock: SimClock = null
var _started: bool = false
var _skip_next_autosave: bool = false
var _report: Control


## Builds the restaurant and the read-only view. Safe before tree readiness and
## without touching the Clock, Economy or SaveSystem autoloads.
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


func _ready() -> void:
	start()


## Wires the session to the autoloads and opens the first morning (loading the
## autosave if there is one). Runs once; _ready() calls it, and tests call it
## directly because the test runner never delivers _ready().
func start() -> void:
	if _started:
		return
	initialize()
	if sim == null:
		return
	_started = true
	for autoload: Node in [Clock, GameState, Economy]:
		autoload.call(&"register_save_provider")
	_report.connect(&"next_day_pressed", _on_next_day_pressed)
	sim.customer_paid.connect(_on_customer_paid)
	sim.service_closed.connect(_on_service_closed)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_previous_clock = Clock.sim
	Clock.attach_world(world, sim.advance)
	sim.stock = Economy.stock
	var loaded: bool = use_saves and _load_autosave()
	if not loaded:
		# Don't autosave over a save that exists but failed to load: its
		# backup may still be recoverable.
		_skip_next_autosave = use_saves and SaveSystem.list_slots().has(save_slot)
		_new_game()
	sim.use_rng(GameState.rng(&"customers"))
	_begin_morning()


func _exit_tree() -> void:
	if sim != null and sim.service_closed.is_connected(_on_service_closed):
		sim.service_closed.disconnect(_on_service_closed)
	if EventBus.day_phase_changed.is_connected(_on_day_phase_changed):
		EventBus.day_phase_changed.disconnect(_on_day_phase_changed)
	if world != null and Clock.attached_world == world:
		Clock.attach_world(null)
		if _previous_clock != null:
			Clock.sim = _previous_clock


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F10:
		start_over()


## Deletes the autosave and restarts the scene from day 1.
func start_over() -> void:
	if use_saves:
		SaveSystem.delete_slot(save_slot)
	get_tree().reload_current_scene()


## Advances the restaurant by `ticks` sim ticks right now (tests and tools).
func run_ticks(ticks: int) -> void:
	for i in ticks:
		if Clock.sim.phase != SimClock.Phase.OPEN and Clock.sim.phase != SimClock.Phase.LAST_ORDERS:
			return
		sim.advance()
		EventBus.sim_ticked.emit(Clock.sim.tick)


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
	sim.stock = Economy.stock
	world.log_event("New game: $%d to start" % TUNING.starting_cash)


func _load_autosave() -> bool:
	if not SaveSystem.list_slots().has(save_slot):
		return false
	if SaveSystem.load_game(save_slot) != OK:
		world.log_event("Autosave could not be loaded; starting a new game")
		return false
	if Clock.sim.phase != SimClock.Phase.MORNING:
		# Saves are only written in the morning; anything else is not ours.
		world.log_event("Autosave is not from a morning; starting a new game")
		return false
	# Economy replaced its stock on load; the kitchen must use the new one.
	sim.stock = Economy.stock
	return true


## Morning setup: new counters, a stocked fridge, and an autosave.
func _begin_morning() -> void:
	sim.start_day()
	dishes_sold_today.clear()
	_restock()
	Economy.ledger.prune_before(Clock.sim.day - Ledger.HISTORY_DAYS)
	_report.hide()
	if use_saves and not _skip_next_autosave:
		SaveSystem.save_game(save_slot)
	_skip_next_autosave = false


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
