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
const CLEANLINESS_TUNING: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")
const REVIEW_TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const REVIEW_QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const PROGRESSION_TUNING: ProgressionTuning = preload("res://data/balance/progression.tres")
const VIBE_TUNING: VibeTuning = preload("res://data/balance/vibe.tres")
const AUTOSAVE_SLOT: String = "autosave"
const LOAN_LOCK_REASON: String = "Pay off your bank loan first"

## Save slot used by autosave and the startup load. Tests change it.
var save_slot: String = AUTOSAVE_SLOT
## When false, _ready() neither loads nor writes saves (used by tests).
var use_saves: bool = true
## Test/capture override only; zero keeps the normal wall-clock new-game seed.
var new_game_seed_override: int = 0
var sim: RestaurantSim
var world: SimWorld
var content: ContentDB
## Read-only, detached derived state for native UI and capture callers.
var vibe_result: VibeModel.Result:
	get:
		return sim.vibe_result if sim != null else VibeModel.Result.new()
signal vibe_changed(result: VibeModel.Result)
var _vibe_grid: SimGrid
## Today's paid departures, grouped by their captured arrival theme label.
var _vibe_experiences: Dictionary[String, int] = {}
## The last evening report put on screen (for tests and tools).
var shown_report: DayReport = null
## Dishes sold today (recipe id -> count), for the evening report.
var dishes_sold_today: Dictionary[StringName, int] = {}
## Closed-phase edits are persisted by the next normal morning autosave.
var shop_editor: ShopEditor
var build_mode: BuildMode = BuildMode.new()
## Cookable dishes/prices belong to this shop, never to shared recipe resources.
var menu_settings: MenuSettings
var staff_roster: StaffRoster
var _staff_notice_day: int = 0
var _staff_notices: Array[Dictionary] = []
## Last thirty eligible reviews, including five virtual three-star starters.
var reputation: ReputationBook = ReputationBook.new()
var owner_progress: OwnerProgress = OwnerProgress.new(PROGRESSION_TUNING)
## Zero is one plate; the two purchased levels carry two and four.
var tray_level: int = 0

var _previous_clock: SimClock = null
var _started: bool = false
var _skip_next_autosave: bool = false
var _owner_preferences: OwnerModeSettings = OwnerModeSettings.new()
var _loaded_layout: ShopLayout = null
var _loaded_menu: MenuSettings = null
var _loaded_staff: StaffRoster = null
var _loaded_plates: PlateLedger = null
var _loaded_reputation: ReputationBook = null
var _loaded_tray_level: int = 0
var _owner_award_today: Dictionary = {}
var _owner_unlocks_today: Array[String] = []
var _owner_award_day: int = 0
var _closed_report_day: int = 0
var _loan_notice_day: int = 0
var _report: Control
var _inspect_panel: InspectPanel
var _debug_overlay: DebugOverlay
var _debug_geometry: DebugGeometry
var _build_preview: BuildPreview
var _build_catalogue: BuildCatalogue
var _build_ready: bool = false
var _was_build_active: bool = false
var _build_phase: int = -1
var _build_ui_phase: int = -1
var _paint_active: bool = false
var _paint_swatch_id: StringName = &"butter"
var _menu_panel: MenuPanel
var _staff_panel: StaffPanel
var _settings_panel: SettingsPanel
var _settings_return_to_menu: bool = false
var _settings_previous_speed: int = 0


## Builds the restaurant and the read-only view. Safe before tree readiness.
## HUD binding reads Clock/Economy; session and save registration wait for start().
func initialize() -> void:
	if sim != null:
		return
	content = ContentDB.new()
	var load_errors: PackedStringArray = content.load_all()
	if not load_errors.is_empty():
		push_error("Cannot load shop content: %s" % [load_errors])
		return
	var errors: Array[String] = []
	staff_roster = StaffRoster.new(TUNING)
	sim = RestaurantSim.create(LAYOUT, content, 1, errors, null, true, false, staff_roster.members())
	if not errors.is_empty():
		push_error("Cannot build shop: %s" % [errors])
		sim = null
		return
	world = sim.world
	menu_settings = MenuSettings.new(_cookable_recipes(LAYOUT), owner_progress.level)
	_apply_menu(sim, menu_settings)
	_bind_world_presentation()


## Also runs after startup replaces the layout: no inspector keeps the old world.
func _bind_world_presentation() -> void:
	_disconnect_vibe_grid()
	# Release the hidden original BEFORE ShopView frees/replaces its meshes.
	_build_ready = false
	_build_preview = $BuildPreview
	_build_preview.clear()
	build_mode.bind_session(null, null, null, Callable(), Callable(), Callable())
	_was_build_active = false
	_paint_active = false
	var view: ShopView = $ShopView
	view.clear_paint_preview()
	view.show_world(world)
	view.bind_cleanliness(sim.cleanliness)
	var painted_layout: ShopLayout = _loaded_layout if _loaded_layout != null else LAYOUT
	view.set_paint(content, painted_layout.wall_swatch_id, painted_layout.floor_swatch_id)
	var camera: CameraRig = $CameraRig
	camera.set_grid_forced(false)
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
	$HUD.bind_preferences(Preferences)
	_refresh_loan_hud()
	if not $HUD.is_connected(&"header_layout_changed", _on_header_layout_changed):
		$HUD.connect(&"header_layout_changed", _on_header_layout_changed)
	if not $HUD.is_connected(&"settings_pressed", _on_hud_settings_requested):
		$HUD.connect(&"settings_pressed", _on_hud_settings_requested)
	_report = $Overlay/EveningReport
	# The full-viewport root must leave the HUD reachable at CLOSED. Its
	# panel, scroll area and buttons retain their own blocking input filters.
	_report.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_report.hide()
	_inspect_panel = $Overlay/InspectPanel
	_debug_overlay = $Overlay/DebugOverlay
	_debug_geometry = $DebugGeometry
	_build_catalogue = $Overlay/BuildCatalogue
	_build_catalogue.bind_content(content)
	_build_catalogue.set_owner_level(owner_progress.level)
	_build_catalogue.set_build_visible(false)
	_build_catalogue.set_paint_visible(false)
	_paint_swatch_id = _build_catalogue.selected_swatch_id
	if not _build_catalogue.buy_requested.is_connected(_on_build_buy_requested):
		_build_catalogue.buy_requested.connect(_on_build_buy_requested)
	if not _build_catalogue.swatch_requested.is_connected(_on_swatch_requested):
		_build_catalogue.swatch_requested.connect(_on_swatch_requested)
	if not $HUD.build_toggled.is_connected(_on_build_toggled):
		$HUD.build_toggled.connect(_on_build_toggled)
	if not $HUD.paint_toggled.is_connected(_on_paint_toggled):
		$HUD.paint_toggled.connect(_on_paint_toggled)
	$HUD.set_build_state(false, false)
	$HUD.set_reputation(reputation.average(), reputation.scores().size())
	$HUD.set_paint_state(false)
	_menu_panel = $Overlay/MenuPanel
	_menu_panel.bind_menu(menu_settings)
	_menu_panel.set_phase(Clock.sim.phase)
	if not _menu_panel.enable_requested.is_connected(_on_menu_enable_requested):
		_menu_panel.enable_requested.connect(_on_menu_enable_requested)
		_menu_panel.price_requested.connect(_on_menu_price_requested)
		_menu_panel.settings_requested.connect(_on_menu_settings_requested)
	if not $HUD.is_connected(&"menu_pressed", toggle_menu):
		$HUD.connect(&"menu_pressed", toggle_menu)
	_settings_panel = $Overlay/SettingsPanel
	_settings_panel.bind_preferences(Preferences)
	if not _settings_panel.close_requested.is_connected(_on_settings_close_requested):
		_settings_panel.close_requested.connect(_on_settings_close_requested)
	_staff_panel = $Overlay/StaffPanel
	_staff_panel.bind_roster(staff_roster)
	_staff_panel.set_phase(Clock.sim.phase)
	_staff_panel.set_trays(tray_level, TUNING.tray_prices, Economy.cash, _loan_upgrade_refusal())
	if not _staff_panel.hire_requested.is_connected(_on_staff_hire_requested):
		_staff_panel.hire_requested.connect(_on_staff_hire_requested)
		_staff_panel.let_go_requested.connect(_on_staff_let_go_requested)
		_staff_panel.tray_requested.connect(_on_tray_requested)
		_staff_panel.close_requested.connect(_on_staff_close_requested)
	if not _staff_panel.raise_accept_requested.is_connected(_on_staff_raise_accept_requested):
		_staff_panel.raise_accept_requested.connect(_on_staff_raise_accept_requested)
		_staff_panel.raise_decline_requested.connect(_on_staff_raise_decline_requested)
	if not _staff_panel.job_priority_requested.is_connected(_on_staff_job_priority_requested):
		_staff_panel.job_priority_requested.connect(_on_staff_job_priority_requested)
	if not $HUD.is_connected(&"staff_pressed", toggle_staff):
		$HUD.connect(&"staff_pressed", toggle_staff)
	_inspect_panel.bind_world(world)
	_debug_overlay.bind_world(world)
	_debug_overlay.bind_cleanliness(sim.cleanliness)
	_on_header_layout_changed()
	refresh_presentation()


func _on_header_layout_changed() -> void:
	var top: float = float($HUD.call("panel_top"))
	for path: NodePath in [^"Overlay/MenuPanel/Panel", ^"Overlay/StaffPanel/Panel",
			^"Overlay/EveningReport/Panel", ^"Overlay/DebugOverlay/Panel"]:
		var panel: Control = get_node(path) as Control
		panel.offset_top = top
	if _settings_panel != null:
		_settings_panel.set_panel_top(top)


func _ready() -> void:
	start()


func _process(_delta: float) -> void:
	if world == null:
		return
	_debug_overlay.sample_rates(float(Time.get_ticks_usec()) / 1000000.0, Engine.get_frames_per_second())
	_guard_build_phase()
	if is_build_active() and is_inside_tree():
		# The pointer may be stationary while Q/E/zoom/pan is still smoothing.
		update_build_pointer(get_viewport().get_mouse_position())
	if _paint_active and is_inside_tree():
		update_paint_pointer(get_viewport().get_mouse_position())
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
	SaveSystem.register("owner", _capture_owner, _restore_owner)
	SaveSystem.register("shop", _capture_shop, _restore_shop)
	SaveSystem.register("menu", _capture_menu, _restore_menu)
	SaveSystem.register("staff", _capture_staff, _restore_staff)
	SaveSystem.register("plates", _capture_plates, _restore_plates)
	SaveSystem.register("reviews", _capture_reviews, _restore_reviews)
	var loaded: bool = use_saves and _load_autosave()
	if not loaded:
		_skip_next_autosave = use_saves and SaveSystem.list_slots().has(save_slot)
		_new_game()
	world.clock = Clock.sim
	sim.stock = Economy.stock
	sim.use_rng(GameState.rng(&"customers"))
	var cleanliness: CleanlinessState = CleanlinessState.new(
		world.grid, CLEANLINESS_TUNING, GameState.rng(&"cleanliness"))
	if not sim.configure_cleanliness(cleanliness, CLEANLINESS_TUNING):
		push_error("Cannot initialize shop cleanliness")
		return
	# The loaded layout can replace both world and view during _load_autosave().
	($ShopView as ShopView).bind_cleanliness(cleanliness)
	_debug_overlay.bind_cleanliness(cleanliness)
	sim.configure_reviews(reputation, REVIEW_TUNING, REVIEW_QUOTES, GameState.rng(&"reviews"))
	sim.spawner.min_gap = TUNING.arrival_gap_min
	sim.spawner.max_gap = TUNING.arrival_gap_max
	shop_editor = ShopEditor.new(sim, content, ShopEditBooks.new(Economy.can_buy_discretionary,
		Economy.add_cash, _furniture_purchase_refusal),
		_loaded_layout if _loaded_layout != null else LAYOUT)
	shop_editor.set_owner_level(owner_progress.level)
	_connect_session()
	Clock.attach_world(world, sim.advance)
	_begin_morning()
	_bind_build_session()
	_bind_vibe_grid()


func _connect_session() -> void:
	if not _report.is_connected(&"next_day_pressed", _on_next_day_pressed):
		_report.connect(&"next_day_pressed", _on_next_day_pressed)
	sim.customer_paid.connect(_on_customer_paid)
	if not sim.customer_left.is_connected(_on_vibe_customer_left):
		sim.customer_left.connect(_on_vibe_customer_left)
	sim.review_recorded.connect(_on_review_recorded)
	sim.service_closed.connect(_on_service_closed)
	if not world.board.task_completed.is_connected(_on_staff_task_completed):
		world.board.task_completed.connect(_on_staff_task_completed)
	if sim.kitchen != null:
		sim.kitchen.plates_changed.connect(_on_plates_changed)
		_on_plates_changed(sim.kitchen.clean_plates, sim.kitchen.plates.total,
			sim.kitchen.dirty_plates, sim.kitchen.in_use_plates)
	if not EventBus.day_phase_changed.is_connected(_on_day_phase_changed):
		EventBus.day_phase_changed.connect(_on_day_phase_changed)
	if not EventBus.sim_ticked.is_connected(_on_inspection_tick):
		EventBus.sim_ticked.connect(_on_inspection_tick)
	if not EventBus.cash_changed.is_connected(_on_build_cash_changed):
		EventBus.cash_changed.connect(_on_build_cash_changed)
	if not _inspect_panel.owner_mode_requested.is_connected(_on_owner_mode_requested):
		_inspect_panel.owner_mode_requested.connect(_on_owner_mode_requested)


func _exit_tree() -> void:
	_disconnect_vibe_grid()
	_build_ready = false
	if build_mode.changed.is_connected(_on_build_changed):
		build_mode.changed.disconnect(_on_build_changed)
	if _build_preview != null:
		_build_preview.clear()
	_paint_active = false
	build_mode.bind_session(null, null, null, Callable(), Callable(), Callable())
	($CameraRig as CameraRig).set_grid_forced(false)
	if _inspect_panel != null and _inspect_panel.owner_mode_requested.is_connected(_on_owner_mode_requested):
		_inspect_panel.owner_mode_requested.disconnect(_on_owner_mode_requested)
	if sim != null and sim.customer_paid.is_connected(_on_customer_paid):
		sim.customer_paid.disconnect(_on_customer_paid)
	if sim != null and sim.customer_left.is_connected(_on_vibe_customer_left):
		sim.customer_left.disconnect(_on_vibe_customer_left)
	if sim != null and sim.review_recorded.is_connected(_on_review_recorded):
		sim.review_recorded.disconnect(_on_review_recorded)
	if sim != null and sim.kitchen != null and sim.kitchen.plates_changed.is_connected(_on_plates_changed):
		sim.kitchen.plates_changed.disconnect(_on_plates_changed)
	if sim != null and sim.service_closed.is_connected(_on_service_closed):
		sim.service_closed.disconnect(_on_service_closed)
	if world != null and world.board != null \
			and world.board.task_completed.is_connected(_on_staff_task_completed):
		world.board.task_completed.disconnect(_on_staff_task_completed)
	if EventBus.day_phase_changed.is_connected(_on_day_phase_changed):
		EventBus.day_phase_changed.disconnect(_on_day_phase_changed)
	if EventBus.sim_ticked.is_connected(_on_inspection_tick):
		EventBus.sim_ticked.disconnect(_on_inspection_tick)
	if EventBus.cash_changed.is_connected(_on_build_cash_changed):
		EventBus.cash_changed.disconnect(_on_build_cash_changed)
	if world != null and Clock.attached_world == world:
		Clock.attach_world(null)
		if _previous_clock != null:
			Clock.sim = _previous_clock


func _unhandled_input(event: InputEvent) -> void:
	if is_settings_visible():
		var settings_key: InputEventKey = event as InputEventKey
		if settings_key != null and settings_key.pressed and not settings_key.echo:
			var settings_code: Key = settings_key.physical_keycode if settings_key.physical_keycode != KEY_NONE else settings_key.keycode
			if settings_code == KEY_ESCAPE:
				set_settings_visible(false)
		_mark_input_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_F10:
			start_over()
			return
		elif code == KEY_F3:
			set_debug_visible(not is_debug_visible())
			_mark_input_handled()
			return
	if route_paint_input(event) or route_build_input(event):
		_mark_input_handled()
		return
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_ESCAPE:
			if is_menu_visible():
				set_menu_visible(false)
			elif _staff_panel != null and _staff_panel.visible:
				set_staff_visible(false)
			elif _inspect_panel.selected_agent_id >= 0 or _inspect_panel.selected_item_id >= 0:
				clear_selection()
			else:
				set_settings_visible(true)
			_mark_input_handled()
		else:
			var mode: StringName = _owner_mode_for_key(code)
			if not mode.is_empty() and assign_owner_mode(mode):
				_mark_input_handled()
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		pick_screen_position(mouse.position)
		_mark_input_handled()


## The single Main input owner calls this before normal inspection. Inactive
## build mode deliberately leaves R and service input unhandled.
func route_build_input(event: InputEvent) -> bool:
	_guard_build_phase()
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_B:
			return set_build_active(not is_build_active())
		if is_build_active():
			match code:
				KEY_R:
					build_mode.rotate()
					return true
				KEY_DELETE:
					build_mode.sell_selected()
					return true
				KEY_ESCAPE:
					build_mode.cancel()
					return true
	if not is_build_active():
		return false
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		update_build_pointer(motion.position)
		return false  # Camera drag/edge tracking still receives motion.
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		if update_build_pointer(mouse.position):
			if build_mode.has_ghost():
				build_mode.commit()
			elif build_mode.state == BuildMode.State.IDLE:
				var cell: Variant = build_cell_at_screen_position(mouse.position)
				# Alt explicitly picks the floor layer. A miss cannot accidentally
				# grab the furniture above it; normal clicks keep their old order.
				var item: PlacedItem = world.grid.item_on_layer(cell, ItemDef.PlacementLayer.FLOOR_DECOR) \
					if mouse.alt_pressed else world.grid.item_at(cell)
				if item != null:
					build_mode.pick_up_at(item.id, cell)
		return true
	return false


## Paint has its own input path so service-time recolouring cannot move items.
func route_paint_input(event: InputEvent) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_P:
			return set_paint_active(not _paint_active)
		if _paint_active and code == KEY_ESCAPE:
			set_paint_active(false)
			return true
		if _paint_active and code == KEY_B:
			set_paint_active(false)
	if not _paint_active:
		return false
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		update_paint_pointer(motion.position)
		return false
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		var cell: Variant = paint_cell_at_screen_position(mouse.position)
		if cell is Vector2i:
			paint_cell(cell)
		return true
	return false


func _mark_input_handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func is_build_active() -> bool:
	return build_mode.is_active()


func is_paint_active() -> bool:
	return _paint_active


func set_paint_active(active: bool) -> bool:
	if not _build_ready or shop_editor == null:
		return false
	if active == _paint_active:
		return true
	if active:
		build_mode.exit()
		set_menu_visible(false)
		set_staff_visible(false)
		clear_selection()
		_report.hide()
	_paint_active = active
	if not active:
		($ShopView as ShopView).clear_paint_preview()
		if world.clock.phase == SimClock.Phase.CLOSED and shown_report != null:
			_report.call(&"show_report", build_report(world.clock.day))
	# Painting is cosmetic: keep the player's existing G preference. Only
	# furniture building needs the temporarily forced placement grid.
	($CameraRig as CameraRig).set_grid_forced(is_build_active())
	_update_build_controls()
	return true


func _paint_target(cell: Vector2i) -> Dictionary:
	if world == null:
		return {}
	var item: PlacedItem = world.grid.item_at(cell)
	if item != null and item.def is ItemDef:
		return {"kind": &"item", "item_id": item.id} if (item.def as ItemDef).paintable else {}
	match world.grid.terrain(cell):
		SimGrid.Terrain.WALL:
			return {"kind": &"wall", "item_id": -1}
		SimGrid.Terrain.FLOOR, SimGrid.Terrain.ENTRY:
			return {"kind": &"floor", "item_id": -1}
	return {}


func update_paint_pointer(screen_position: Vector2) -> void:
	if not _paint_active:
		return
	var cell: Variant = paint_cell_at_screen_position(screen_position)
	preview_paint_cell(cell)


func paint_cell_at_screen_position(screen_position: Vector2) -> Variant:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return null
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var mesh_cell: Variant = ($ShopView as ShopView).paint_cell_at_ray(ray_origin, ray_direction)
	return mesh_cell if mesh_cell is Vector2i else build_cell_at_screen_position(screen_position)


func preview_paint_cell(cell: Variant) -> void:
	var view: ShopView = $ShopView as ShopView
	if not _paint_active or not cell is Vector2i:
		view.clear_paint_preview()
		return
	var target: Dictionary = _paint_target(cell)
	var kind: StringName = target.get("kind", &"")
	var item_id: int = target.get("item_id", -1)
	view.preview_paint(kind, item_id, _paint_swatch_id)


func paint_cell(cell: Vector2i) -> bool:
	if not _paint_active or shop_editor == null:
		return false
	var target: Dictionary = _paint_target(cell)
	var kind: StringName = target.get("kind", &"")
	var previous: StringName = shop_editor.wall_swatch_id if kind == &"wall" else (
		shop_editor.floor_swatch_id if kind == &"floor" else (
			world.grid.item(target["item_id"]).swatch_id if kind == &"item" else &""))
	var accepted: bool = false
	match kind:
		&"wall": accepted = shop_editor.paint_wall(_paint_swatch_id)
		&"floor": accepted = shop_editor.paint_floor(_paint_swatch_id)
		&"item": accepted = shop_editor.paint_item(target["item_id"], _paint_swatch_id)
	if accepted:
		($ShopView as ShopView).set_paint(content, shop_editor.wall_swatch_id, shop_editor.floor_swatch_id)
		if previous != _paint_swatch_id:
			_recompute_vibe()
	return accepted


## Subscribe only after the final loaded world, menu and editor are installed.
func _bind_vibe_grid() -> void:
	_disconnect_vibe_grid()
	_vibe_grid = world.grid
	_vibe_grid.cells_changed.connect(_on_vibe_cells_changed)
	_recompute_vibe()


func _disconnect_vibe_grid() -> void:
	if _vibe_grid != null and _vibe_grid.cells_changed.is_connected(_on_vibe_cells_changed):
		_vibe_grid.cells_changed.disconnect(_on_vibe_cells_changed)
	_vibe_grid = null


func _on_vibe_cells_changed(_cells: Array[Vector2i]) -> void:
	_recompute_vibe()


func _recompute_vibe() -> void:
	if sim == null or world == null or shop_editor == null or menu_settings == null:
		return
	var inputs: VibeModel.Inputs = VibeInputs.capture(world.grid, content, menu_settings.enabled_recipes(),
		shop_editor.wall_swatch_id, shop_editor.floor_swatch_id)
	sim.set_vibe(VibeModel.evaluate(inputs, VIBE_TUNING))
	var result: VibeModel.Result = vibe_result
	_build_catalogue.set_vibe(result)
	$HUD.set_vibe(result)
	_report.call(&"set_vibe", result, _experienced_vibe_theme())
	vibe_changed.emit(vibe_result)


## The sim emits each departure once. Observe only its captured presentation
## evidence; review calculation and its random stream remain in RestaurantSim.
func _on_vibe_customer_left(customer: CustomerAgent, _reason: StringName) -> void:
	if customer == null or not customer.paid or not is_finite(customer.vibe_review_bonus) \
			or customer.vibe_review_bonus <= 0.0 \
			or not VIBE_TUNING.theme_labels.values().has(customer.vibe_theme_label):
		return
	var label: String = customer.vibe_theme_label
	_vibe_experiences[label] = _vibe_experiences.get(label, 0) + 1
	_report.call(&"set_vibe", vibe_result, _experienced_vibe_theme())


func _experienced_vibe_theme() -> String:
	var labels: Array[String] = []
	for label: String in _vibe_experiences:
		labels.append(label)
	labels.sort()
	var selected: String = ""
	var most: int = 0
	for label: String in labels:
		if _vibe_experiences[label] > most:
			selected = label
			most = _vibe_experiences[label]
	return selected


func _on_paint_toggled() -> void:
	set_paint_active(not _paint_active)


func _on_swatch_requested(id: StringName) -> void:
	_paint_swatch_id = id
	if _paint_active and is_inside_tree():
		update_paint_pointer(get_viewport().get_mouse_position())


func set_build_active(active: bool) -> bool:
	if not _build_ready:
		return false
	if active:
		if _paint_active:
			set_paint_active(false)
		return build_mode.enter()
	build_mode.exit()
	return true


## Hover and click share this exact camera-ray/floor-plane/grid conversion.
func build_cell_at_screen_position(screen_position: Vector2) -> Variant:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return null
	var hit: Variant = Picker.floor_intersection(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	return GridMath.world_to_cell(hit) if hit is Vector3 else null


func update_build_pointer(screen_position: Vector2) -> bool:
	if not is_build_active():
		return false
	var cell: Variant = build_cell_at_screen_position(screen_position)
	if not cell is Vector2i:
		return false
	if build_mode.has_ghost():
		build_mode.update_origin(cell)
	return true


func begin_buy_item(def_id: StringName) -> bool:
	if not is_build_active():
		return false
	var cell: Variant = build_cell_at_screen_position(get_viewport().get_mouse_position()) if is_inside_tree() else null
	return build_mode.begin_buy(def_id, cell if cell is Vector2i else Vector2i.ZERO)


func _bind_build_session() -> void:
	if not build_mode.changed.is_connected(_on_build_changed):
		build_mode.changed.connect(_on_build_changed)
	build_mode.bind_session(shop_editor, world, content, shop_move, shop_buy, shop_sell)
	($ShopView as ShopView).set_paint(content, shop_editor.wall_swatch_id, shop_editor.floor_swatch_id)
	_build_preview.bind_build_mode(build_mode, $ShopView as ShopView)
	_build_ready = true
	_build_ui_phase = -1
	_on_build_changed()


func _guard_build_phase() -> void:
	if not _build_ready:
		return
	if is_build_active() and (world.clock.phase != _build_phase or not shop_editor.can_edit()):
		build_mode.exit()
	if _build_ui_phase != world.clock.phase:
		_update_build_controls()


func _on_build_changed() -> void:
	var active: bool = is_build_active()
	($CameraRig as CameraRig).set_grid_forced(active)
	if active and not _was_build_active:
		_build_phase = world.clock.phase
		set_menu_visible(false)
		set_staff_visible(false)
		clear_selection()
		_report.hide()
	elif not active and _was_build_active and _build_ready and world.clock.phase == SimClock.Phase.CLOSED:
		# Rebuild from current books; do not run closing charges or day setup.
		shown_report = build_report(world.clock.day)
		_report.call(&"show_report", shown_report)
	_was_build_active = active
	_update_build_controls()


func _update_build_controls() -> void:
	var active: bool = is_build_active()
	var available: bool = _build_ready and shop_editor != null and shop_editor.can_edit()
	var reason: String = build_mode.current_check.why if build_mode.has_ghost() and not build_mode.current_check.ok else ""
	$HUD.set_build_state(available, active, reason, int(build_mode.state))
	$HUD.set_paint_state(_paint_active)
	if _build_catalogue != null:
		_build_catalogue.set_paint_visible(_paint_active)
		_build_catalogue.set_build_visible(active or _paint_active)
	_build_ui_phase = world.clock.phase if world != null else -1


func _on_build_toggled() -> void:
	set_build_active(not is_build_active())


func _on_build_buy_requested(def_id: StringName) -> void:
	begin_buy_item(def_id)


func _on_build_cash_changed(_cash: int, _delta: int, _reason: StringName) -> void:
	_refresh_loan_hud()
	if _build_ready and is_build_active():
		build_mode.refresh()
	if _staff_panel != null:
		_staff_panel.set_trays(tray_level, TUNING.tray_prices, Economy.cash, _loan_upgrade_refusal())


## Visual item bounds choose the furniture hit; the floor still locates agents
## and preserves world-position selection for callers without a camera ray.
func pick_screen_position(screen_position: Vector2) -> void:
	if is_build_active() or _paint_active:
		return
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var view: ShopView = $ShopView
	var preferred_item_id: int = view.item_at_ray(ray_origin, ray_direction)
	var hit: Variant = Picker.floor_intersection(ray_origin, ray_direction)
	if hit is Vector3:
		select_at_world_position(hit, preferred_item_id)


## Owner commands precede drawn agents, then the preferred visual item. -1
## retains the legacy cell fallback; a wall hit must never pick through it.
func select_at_world_position(world_position: Vector3, preferred_item_id: int = -1) -> void:
	if world == null or is_build_active() or _paint_active:
		return
	# Resolve owner work targets before nearby agents or ordinary item picking.
	if _selected_owner() != null:
		var target: Dictionary = {"mode": &""}
		if preferred_item_id >= 0:
			var preferred: PlacedItem = world.grid.item(preferred_item_id)
			if preferred != null:
				if preferred.placement_layer == ItemDef.PlacementLayer.FLOOR_DECOR:
					# A visible rug cannot hide an external normal work cell.
					target = OwnerAssignment.resolve(world_position, world.grid)
				else:
					# Classify the visible normal item with its pass-side geometry.
					# A covered non-target still takes precedence over hidden work.
					target = OwnerAssignment._for_item(preferred, world_position, -1)
		elif preferred_item_id == -1:
			target = OwnerAssignment.resolve(world_position, world.grid)
		var mode: StringName = target["mode"]
		if not mode.is_empty() and assign_owner_mode(mode):
			return
	var view: ShopView = $ShopView
	var agent_id: int = Picker.pick_agent(world_position, view.drawn_agent_positions())
	if agent_id >= 0:
		select_agent(agent_id)
		return
	var item: PlacedItem = world.grid.item(preferred_item_id) if preferred_item_id >= 0 else (
		world.grid.item_at(GridMath.world_to_cell(world_position)) if preferred_item_id == -1 else null)
	if item != null:
		_inspect_panel.show_item(item.id)
		refresh_presentation()
	else:
		clear_selection()


## Selects a live agent through the production inspector API.
func select_agent(agent_id: int) -> bool:
	if is_build_active():
		return false
	_inspect_panel.show_agent(agent_id)
	refresh_presentation()
	return _inspect_panel.selected_agent_id == agent_id


func _selected_owner() -> OwnerAgent:
	if sim == null or world == null or _inspect_panel == null:
		return null
	var selected_owner: OwnerAgent = sim.owner_agent()
	return selected_owner if selected_owner != null and _inspect_panel.selected_agent_id == selected_owner.id else null


## The sole player command used by keys, inspector buttons and capture tools.
## Changes are included in the next normal MORNING checkpoint.
func assign_owner_mode(mode: StringName) -> bool:
	if is_build_active():
		return false
	var selected_owner: OwnerAgent = _selected_owner()
	if selected_owner == null or not OwnerAgent.MODES.has(mode):
		return false
	if not sim.assign_owner(mode):
		return false
	_owner_preferences.assign_mode(mode)
	_inspect_panel.show_agent(selected_owner.id)
	refresh_presentation()
	return true


func _on_owner_mode_requested(mode: StringName) -> void:
	assign_owner_mode(mode)


func _owner_mode_for_key(keycode: Key) -> StringName:
	match keycode:
		KEY_K: return &"kitchen"
		KEY_F: return &"floor"
		KEY_H: return &"help"
		KEY_R: return &"rest"
	return &""


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
	var selected_staff: StaffAgent = null
	for agent: SimAgent in world.agents:
		if agent.id == _inspect_panel.selected_agent_id:
			role = "guest" if agent is CustomerAgent else str(agent.role)
			selected_staff = agent as StaffAgent
	var task: SimTask = selected_staff.task if selected_staff != null else null
	return {
		"selected_agent_id": _inspect_panel.selected_agent_id,
		"selected_item_id": _inspect_panel.selected_item_id,
		"selected_role": role, "panel_visible": _inspect_panel.visible,
		"debug_visible": is_debug_visible(), "world_tick": world.now,
		"owner_mode": String((selected_staff as OwnerAgent).current_mode()) if selected_staff is OwnerAgent else "",
		"selected_task_id": task.id if task != null else -1,
		"selected_task_role": String(task.role) if task != null else "",
		"selected_task_label": task.label if task != null else "",
		"selected_task_state": int(task.state) if task != null else -1,
		"selected_task_claimant": task.claimed_by if task != null else -1,
		"selected_task_step": selected_staff.step_index if task != null else -1,
	}


## Refreshes after completed morning setup, removals and paused grid edits too.
func refresh_presentation() -> void:
	if _inspect_panel == null or _debug_overlay == null or _debug_geometry == null:
		return
	_inspect_panel.refresh()
	if _debug_overlay.is_enabled():
		_debug_overlay.refresh()
	var view: ShopView = $ShopView
	view.set_selected_item(_inspect_panel.selected_item_id)
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
	report.loan_first_advance = _loan_notice_day == day
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
	if sim.cleanliness != null:
		report.cleanliness_label = sim.cleanliness.worst_category_label()
	var star_total: int = 0
	for row: Dictionary in sim.reviews_today:
		var stars: int = int(row.get("stars", 0))
		star_total += stars
		report.review_cards.append({"stars": stars, "quote": String(row.get("quote", ""))})
	report.today_review_average = float(star_total) / float(report.review_cards.size()) \
		if not report.review_cards.is_empty() else 0.0
	report.reputation_before = sim.reputation_before_day
	report.reputation_after = reputation.average()
	report.owner_level_before = owner_progress.level
	report.owner_level_after = owner_progress.level
	if _owner_award_day == day:
		report.owner_xp_breakdown = {
			"happy_xp": int(_owner_award_today["happy_xp"]),
			"profit_xp": int(_owner_award_today["profit_xp"]),
			"review_xp": int(_owner_award_today["review_xp"]),
			"total_xp": int(_owner_award_today["total_xp"]),
		}
		report.owner_level_before = int(_owner_award_today.get("level_before", owner_progress.level))
		report.owner_level_after = owner_progress.level
		report.owner_unlocks = _owner_unlocks_today.duplicate()
	return report


func _new_game() -> void:
	# A fresh clock and seed too, so a half-loaded save can't leave its day
	# or random state behind.
	Clock.sim = SimClock.new()
	GameState.new_run(new_game_seed_override if new_game_seed_override != 0
		else int(Time.get_unix_time_from_system()))
	Economy.reset(TUNING.starting_cash)
	_loaded_layout = null
	_owner_preferences.reset()
	owner_progress = OwnerProgress.new(PROGRESSION_TUNING)
	_owner_award_today.clear()
	_owner_unlocks_today.clear()
	_owner_award_day = 0
	_closed_report_day = 0
	_loan_notice_day = 0
	sim.assign_owner(&"rest")
	_loaded_menu = null
	_loaded_staff = null
	_loaded_reputation = null
	reputation = ReputationBook.new()
	_loaded_tray_level = 0
	tray_level = 0
	sim.carry_capacity = 1
	staff_roster = StaffRoster.new(TUNING)
	_staff_notice_day = 0
	_staff_notices.clear()
	if not sim.set_staff_roster(staff_roster.members()):
		push_error("Cannot install the new game's starting staff roster")
	_staff_panel.bind_roster(staff_roster)
	_loaded_plates = null
	if sim.kitchen != null:
		sim.kitchen.configure_plates(TUNING.starting_plates)
	sim.stock = Economy.stock
	world.log_event("New game: $%d to start" % TUNING.starting_cash)


func _load_autosave() -> bool:
	_loaded_layout = null
	_loaded_menu = null
	_loaded_staff = null
	_loaded_plates = null
	_loaded_reputation = null
	_loaded_tray_level = 0
	if not SaveSystem.list_slots().has(save_slot):
		return false
	if SaveSystem.load_game(save_slot) != OK:
		world.log_event("Autosave could not be loaded; starting a new game")
		return false
	if Clock.sim.phase != SimClock.Phase.MORNING:
		world.log_event("Autosave is not from a morning; starting a new game")
		return false
	if owner_progress.last_awarded_day >= Clock.sim.day:
		world.log_event("Autosave owner progress is ahead of this morning; starting a new game")
		return false
	var layout: ShopLayout = _loaded_layout if _loaded_layout != null else LAYOUT
	var choices: MenuSettings = _loaded_menu if _loaded_menu != null else MenuSettings.new(_cookable_recipes(layout), owner_progress.level)
	if not choices.is_valid():
		return false
	var employees: StaffRoster = _loaded_staff if _loaded_staff != null else StaffRoster.new(TUNING)
	if employees.candidate_day > Clock.sim.day:
		return false
	if _loaded_layout != null or _loaded_staff != null:
		var errors: Array[String] = []
		var candidate: RestaurantSim = RestaurantSim.create(layout, content, 1, errors, Economy.stock, true, _loaded_layout != null, employees.members())
		if not errors.is_empty():
			return false
		sim = candidate
		world = candidate.world
	staff_roster = employees
	reputation = _loaded_reputation if _loaded_reputation != null else ReputationBook.new()
	tray_level = _loaded_tray_level
	sim.carry_capacity = 1 << tray_level
	menu_settings = choices
	_apply_menu(sim, menu_settings)
	if sim.kitchen == null or not sim.kitchen.configure_plates(
			_loaded_plates.total if _loaded_plates != null else TUNING.starting_plates):
		return false
	_bind_world_presentation()
	return sim.assign_owner(_owner_preferences.current_mode())


func _capture_plates() -> Dictionary:
	return sim.kitchen.plates.to_dict() if sim != null and sim.kitchen != null else {}


## Stage only durable stock. Installation waits for complete MORNING success.
func _restore_plates(data: Dictionary) -> bool:
	var restored: PlateLedger = PlateLedger.from_dict(data)
	if restored == null:
		return false
	_loaded_plates = restored
	return true


func _capture_reviews() -> Dictionary:
	return reputation.to_dict()


## Stage the rolling window. Install it only after the full morning load works.
func _restore_reviews(data: Dictionary) -> bool:
	var restored: ReputationBook = ReputationBook.new()
	if not restored.from_dict(data):
		return false
	_loaded_reputation = restored
	return true


func _on_plates_changed(clean: int, total: int, dirty: int, in_use: int) -> void:
	$HUD.set_plate_counts(clean, total, dirty, in_use, sim.kitchen.plate_cycle_enabled)


func _capture_owner() -> Dictionary:
	return {"mode": String(_owner_preferences.current_mode()),
		"progress": owner_progress.to_dict()}


## Accept old mode-only sections; validate mode and XP before staging either.
func _restore_owner(data: Dictionary) -> bool:
	if not data.has("mode") or data.size() > 2:
		return false
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or (key != "mode" and key != "progress"):
			return false
	var preferences: OwnerModeSettings = OwnerModeSettings.new()
	if not preferences.restore({"mode": data["mode"]}):
		return false
	var progress: OwnerProgress = OwnerProgress.new(PROGRESSION_TUNING)
	if data.has("progress") and not progress.from_dict(data["progress"]):
		return false
	_owner_preferences = preferences
	owner_progress = progress
	return true


func _capture_shop() -> Dictionary:
	if shop_editor == null:
		return {}
	var snapshot: Dictionary = shop_editor.to_dict()
	snapshot["tray_level"] = tray_level
	return snapshot


## Restore callbacks only stage decoded data. Live replacement waits for OK.
func _restore_shop(data: Dictionary) -> bool:
	var saved_level: Variant = data.get("tray_level", 0)
	if (typeof(saved_level) != TYPE_INT and typeof(saved_level) != TYPE_FLOAT) \
			or not is_finite(float(saved_level)) or floor(float(saved_level)) != float(saved_level) \
			or saved_level < 0 or saved_level > 2:
		return false
	var errors: Array[String] = []
	var layout: ShopLayout = ShopEditor.from_dict(data, LAYOUT, content, errors)
	if layout == null:
		return false
	_loaded_layout = layout
	_loaded_tray_level = int(saved_level)
	return true


## A morning purchase joins the next ordinary morning save and ledger entry.
func tray_buy(level: int) -> bool:
	if not _started or sim == null or Clock.sim.phase != SimClock.Phase.MORNING \
			or level != tray_level + 1 or level < 1 or level > 2 \
			or TUNING.tray_prices.size() < 2:
		return false
	var price: int = TUNING.tray_prices[level - 1]
	if price < 0 or not Economy.can_buy_upgrade(price):
		return false
	tray_level = level
	sim.carry_capacity = 1 << level
	Economy.add_cash(-price, Ledger.UPGRADES)
	_staff_panel.set_trays(tray_level, TUNING.tray_prices, Economy.cash, _loan_upgrade_refusal())
	return true


func _on_tray_requested(level: int) -> void:
	tray_buy(level)


func _capture_menu() -> Dictionary:
	return menu_settings.to_dict() if menu_settings != null else {}


func _restore_menu(data: Dictionary) -> bool:
	var layout: ShopLayout = _loaded_layout if _loaded_layout != null else LAYOUT
	var choices: MenuSettings = MenuSettings.new(_cookable_recipes(layout), owner_progress.level)
	if not choices.from_dict(data):
		return false
	_loaded_menu = choices
	return true


func _capture_staff() -> Dictionary:
	return staff_roster.to_dict()


## Like shop/menu, restore only stages choices; no live agent or RNG mutations.
func _restore_staff(data: Dictionary) -> bool:
	var choices: StaffRoster = StaffRoster.new(TUNING)
	if not choices.from_dict(data):
		return false
	_loaded_staff = choices
	return true


func can_view_staff() -> bool:
	return _started and staff_roster != null and sim != null and world != null \
		and Clock.sim.phase in [SimClock.Phase.MORNING, SimClock.Phase.OPEN,
			SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]


func can_edit_staff() -> bool:
	return can_view_staff() and Clock.sim.phase == SimClock.Phase.MORNING


## Selection changes apply at the next pick. Install a detached row on the
## existing employee before committing saved choices; never reinstall staff.
## The runtime copy also retains XP earned during the current service.
func staff_set_job_priority(id: StringName, job: StringName, value: int) -> bool:
	if not can_view_staff():
		return false
	var choices: StaffRoster = staff_roster.copy()
	if choices == null or not choices.set_job_priority(id, job, value):
		return false
	var priorities: StaffJobPriorities = choices.job_priorities(id)
	if priorities == null or not sim.apply_staff_job_priorities(id, priorities):
		return false
	staff_roster = choices
	_staff_panel.bind_roster(staff_roster)
	refresh_presentation()
	return true


func staff_hire(id: StringName) -> bool:
	return _change_staff(id, true)


func staff_let_go(id: StringName) -> bool:
	return _change_staff(id, false)


## Morning choices never save immediately; accepted wages update live agents
## before service, while yesterday's closing ledger remains untouched.
func staff_accept_raise(id: StringName) -> bool:
	if not can_edit_staff():
		return false
	var choices: StaffRoster = StaffRoster.new(TUNING)
	if not choices.from_dict(staff_roster.to_dict()) \
			or not choices.accept_raise(id, Clock.sim.phase) \
			or not sim.set_staff_roster(choices.members()):
		return false
	staff_roster = choices
	_staff_panel.bind_roster(staff_roster)
	refresh_presentation()
	return true


func staff_decline_raise(id: StringName) -> bool:
	if not can_edit_staff():
		return false
	var choices: StaffRoster = StaffRoster.new(TUNING)
	if not choices.from_dict(staff_roster.to_dict()) \
			or not choices.decline_raise(id, Clock.sim.day, Clock.sim.phase):
		return false
	staff_roster = choices
	_staff_panel.bind_roster(staff_roster)
	return true


func _change_staff(id: StringName, hiring: bool) -> bool:
	if not can_edit_staff():
		return false
	var choices: StaffRoster = StaffRoster.new(TUNING)
	if not choices.from_dict(staff_roster.to_dict()):
		return false
	if not (choices.hire(id) if hiring else choices.let_go(id)):
		return false
	if not sim.set_staff_roster(choices.members()):
		return false
	staff_roster = choices
	_staff_panel.bind_roster(staff_roster)
	refresh_presentation()
	return true


func toggle_staff() -> void:
	set_staff_visible(not is_staff_visible())


func set_staff_visible(value: bool) -> bool:
	if _staff_panel == null or (value and not can_view_staff()):
		return false
	if value:
		if is_settings_visible():
			_settings_return_to_menu = false
			if not set_settings_visible(false):
				return false
		if _paint_active:
			set_paint_active(false)
		build_mode.exit()
		set_menu_visible(false)
		clear_selection()
		_report.hide()
	_staff_panel.set_phase(Clock.sim.phase)
	_staff_panel.set_trays(tray_level, TUNING.tray_prices, Economy.cash, _loan_upgrade_refusal())
	_staff_panel.visible = value
	if not value and Clock.sim.phase == SimClock.Phase.CLOSED and shown_report != null:
		_report.call(&"show_report", build_report(Clock.sim.day))
	return true


func is_staff_visible() -> bool:
	return _staff_panel != null and _staff_panel.visible


func _on_staff_hire_requested(id: StringName) -> void:
	staff_hire(id)
	_staff_panel.refresh()


func _on_staff_let_go_requested(id: StringName) -> void:
	staff_let_go(id)
	_staff_panel.refresh()


func _on_staff_raise_accept_requested(id: StringName) -> void:
	staff_accept_raise(id)
	_staff_panel.refresh()


func _on_staff_raise_decline_requested(id: StringName) -> void:
	staff_decline_raise(id)
	_staff_panel.refresh()


func _on_staff_job_priority_requested(id: StringName, job: StringName, value: int) -> void:
	staff_set_job_priority(id, job, value)
	_staff_panel.refresh()


func _on_staff_close_requested() -> void:
	set_staff_visible(false)


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
		# Phase 3: replace with the unlocked tier.
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
	var was_enabled: bool = menu_settings.is_enabled(recipe_id)
	if not menu_settings.set_enabled(recipe_id, enabled):
		return false
	_apply_menu(sim, menu_settings)
	_menu_panel.refresh()
	if was_enabled != menu_settings.is_enabled(recipe_id):
		_recompute_vibe()
	return true


func menu_set_price(recipe_id: StringName, price: int) -> bool:
	if not can_edit_menu() or menu_settings.recipe(recipe_id) == null:
		return false
	menu_settings.set_price(recipe_id, price)
	_apply_menu(sim, menu_settings)
	_menu_panel.refresh()
	return true


func toggle_menu() -> void:
	if is_settings_visible():
		set_settings_visible(false)
		return
	if _menu_panel != null:
		set_menu_visible(not _menu_panel.visible)


## Idempotent production path for the HUD and genuine review captures.
func set_menu_visible(value: bool) -> bool:
	if _menu_panel == null or (value and not can_edit_menu()):
		return false
	if value:
		if is_settings_visible():
			_settings_return_to_menu = false
			if not set_settings_visible(false):
				return false
		if _paint_active:
			set_paint_active(false)
		build_mode.exit()
		set_staff_visible(false)
	_menu_panel.set_phase(Clock.sim.phase)
	_menu_panel.visible = value
	return true


func is_menu_visible() -> bool:
	return _menu_panel != null and _menu_panel.visible


func set_settings_visible(value: bool) -> bool:
	if _settings_panel == null:
		return false
	if _settings_panel.visible == value:
		return true
	if value:
		_settings_return_to_menu = is_menu_visible()
		_settings_previous_speed = Clock.speed
		Clock.set_speed(0)
		set_menu_visible(false)
		set_staff_visible(false)
		if _paint_active:
			set_paint_active(false)
		build_mode.exit()
		clear_selection()
		_settings_panel.refresh()
	else:
		if not _settings_panel.flush_pending_changes():
			return false
	_settings_panel.visible = value
	if not value:
		Clock.set_speed(_settings_previous_speed)
	if not value and _settings_return_to_menu:
		_settings_return_to_menu = false
		set_menu_visible(true)
	return true


func is_settings_visible() -> bool:
	return _settings_panel != null and _settings_panel.visible


func _on_menu_settings_requested() -> void:
	set_settings_visible(true)


func _on_hud_settings_requested() -> void:
	set_settings_visible(not is_settings_visible())


func _on_settings_close_requested() -> void:
	set_settings_visible(false)


func _on_menu_enable_requested(recipe_id: StringName, enabled: bool) -> void:
	menu_set_enabled(recipe_id, enabled)
	_menu_panel.refresh()


func _on_menu_price_requested(recipe_id: StringName, price: int) -> void:
	menu_set_price(recipe_id, price)
	_menu_panel.refresh()


func shop_move(item_id: int, origin: Vector2i, quarter_turns: int) -> bool:
	var accepted: bool = shop_editor != null and shop_editor.move(item_id, origin, quarter_turns)
	if _build_ready:
		build_mode.refresh()
	return accepted


func shop_buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0) -> bool:
	var accepted: bool = shop_editor != null and shop_editor.buy(def_id, origin, quarter_turns)
	if _build_ready:
		build_mode.refresh()
	return accepted


func _furniture_purchase_refusal(amount: int) -> String:
	if Economy.loan.principal > 0 and amount > Economy.LOAN_TERMS.large_purchase_limit:
		return LOAN_LOCK_REASON
	return ShopEditBooks.CASH_REFUSAL


func _loan_upgrade_refusal() -> String:
	return LOAN_LOCK_REASON if Economy.loan.principal > 0 else ""


func _refresh_loan_hud() -> void:
	$HUD.set_loan_state(Economy.loan.principal, Economy.LOAN_TERMS.repay_share,
		Economy.LOAN_TERMS.daily_interest)


func shop_sell(item_id: int) -> int:
	var refund: int = shop_editor.sell(item_id) if shop_editor != null else -1
	if _build_ready:
		build_mode.refresh()
	return refund


## Morning setup: new counters, a stocked fridge, and an autosave.
func _begin_morning() -> void:
	_vibe_experiences.clear()
	_report.call(&"set_vibe", vibe_result)
	# Direct sim drivers may finish cleanup after service_closed. Apply that
	# newly completed work before the saved-state clone drops transient XP.
	# An ordinary morning or repeated setup has no staged XP to apply again.
	staff_roster.close_growth_day()
	var choices: StaffRoster = StaffRoster.new(TUNING)
	if not choices.from_dict(staff_roster.to_dict()):
		push_error("Cannot restore the morning staff roster")
		return
	var notices: Array[Dictionary] = choices.process_morning_quits(Clock.sim.day, Clock.sim.phase)
	# The morning install removes departures and applies skills earned at the
	# previous close before any staff are sent to their posts.
	if not sim.set_staff_roster(choices.members()):
		push_error("Cannot install the morning staff roster")
		return
	staff_roster = choices
	_staff_panel.bind_roster(staff_roster)
	if _staff_notice_day != Clock.sim.day:
		_staff_notice_day = Clock.sim.day
		_staff_notices.assign(notices)
	elif not notices.is_empty():
		_staff_notices.assign(notices)
	# Sample the rating once, before start_day resets the first guest's gap.
	# Positive stars increase arrivals, so their time between arrivals shrinks.
	var rate: float = reputation.arrival_multiplier(REVIEW_TUNING)
	sim.spawner.min_gap = maxi(1, roundi(float(TUNING.arrival_gap_min) / rate))
	sim.spawner.max_gap = maxi(sim.spawner.min_gap, roundi(float(TUNING.arrival_gap_max) / rate))
	sim.start_day()
	$HUD.set_reputation(reputation.average(), reputation.scores().size())
	_owner_award_today.clear()
	_owner_unlocks_today.clear()
	_owner_award_day = 0
	_closed_report_day = 0
	_loan_notice_day = 0
	# Loading today's persisted pool must not advance the saved hiring stream.
	if staff_roster.candidate_day != Clock.sim.day:
		staff_roster.draw_candidates(Clock.sim.day, GameState.rng(&"hiring"))
	_staff_panel.set_phase(Clock.sim.phase)
	_staff_panel.set_morning(Clock.sim.day, _staff_notices)
	dishes_sold_today.clear()
	shown_report = null
	_restock()
	Economy.ledger.prune_before(Clock.sim.day - Ledger.HISTORY_DAYS)
	_report.hide()
	if use_saves and not _skip_next_autosave:
		SaveSystem.save_game(save_slot)
	_skip_next_autosave = false
	_refresh_loan_hud()
	$HUD.set_owner_progress(owner_progress.level, owner_progress.xp_into_level(), owner_progress.xp_in_level())
	# A new raise or departure must be visible without making the player find
	# the Staff button. Ordinary mornings still leave the panel closed.
	if not _staff_notices.is_empty() \
			or not staff_roster.morning_raise_offers(Clock.sim.day, Clock.sim.phase).is_empty():
		set_staff_visible(true)
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
	for agent: SimAgent in world.agents:
		if agent is StaffAgent and not agent is OwnerAgent:
			Economy.add_cash(-(agent as StaffAgent).wage, Ledger.WAGES)
	if TUNING.daily_rent > 0:
		Economy.add_cash(-TUNING.daily_rent, Ledger.RENT)


func _on_customer_paid(_customer: CustomerAgent, order: Order, amount: int) -> void:
	Economy.add_cash(amount, Ledger.SALE)
	dishes_sold_today[order.recipe_id] = dishes_sold_today.get(order.recipe_id, 0) + 1


func _on_staff_task_completed(task: SimTask) -> void:
	StaffTaskCredit.credit_completed(task, world, staff_roster)


func _on_review_recorded(_row: Dictionary) -> void:
	# The display may change during service, but the day's arrival gap does not.
	$HUD.set_reputation(reputation.average(), reputation.scores().size())


## Service is over and every guest's departure is recorded: close the books.
func _on_service_closed(day: int) -> void:
	if day != Clock.sim.day or _closed_report_day == day:
		return
	_closed_report_day = day
	_charge_closing_costs()
	# Financing balances the books but never earns or removes owner profit XP.
	var operating_profit: int = Economy.ledger.day_profit(day)
	var settlement: Dictionary = Economy.settle_loan_day(day)
	if settlement.get("first_advance", false):
		_loan_notice_day = day
	staff_roster.close_growth_day()
	shown_report = build_report(day)
	var five_star_reviews: int = 0
	for row: Dictionary in sim.reviews_today:
		if int(row.get("stars", 0)) == 5:
			five_star_reviews += 1
	var level_before: int = owner_progress.level
	_owner_award_today = owner_progress.award_day(day,
		int(sim.leave_reasons_today.get(&"happy", 0)), operating_profit, five_star_reviews)
	if not _owner_award_today.is_empty():
		_owner_award_day = day
		_owner_unlocks_today = _unlocked_at_levels(level_before, owner_progress.level)
		menu_settings.set_owner_level(owner_progress.level)
		shop_editor.set_owner_level(owner_progress.level)
		_build_catalogue.set_owner_level(owner_progress.level)
		$HUD.set_owner_progress(owner_progress.level, owner_progress.xp_into_level(), owner_progress.xp_in_level())
		shown_report = build_report(day)
	_report.call(&"show_report", shown_report)
	if _paint_active or is_staff_visible():
		_report.hide()
	if is_staff_visible():
		_staff_panel.refresh()


## Only authored display names enter the public level-up banner.
func _unlocked_at_levels(previous_level: int, current_level: int) -> Array[String]:
	var unlocked: Array[String] = []
	for recipe: RecipeDef in content.recipes():
		if recipe.unlock_tier == 1 and recipe.unlock_level > previous_level and recipe.unlock_level <= current_level:
			unlocked.append(recipe.display_name + " recipe")
	for item: ItemDef in content.items():
		if item.catalogue_visible and item.unlock_level > previous_level and item.unlock_level <= current_level:
			unlocked.append(item.display_name)
	unlocked.sort()
	return unlocked


func _on_day_phase_changed(_day: int, phase: int) -> void:
	build_mode.exit()
	if _build_ready:
		_update_build_controls()
	if _menu_panel != null:
		_menu_panel.set_phase(phase)
		if phase != SimClock.Phase.MORNING:
			_menu_panel.hide()
			_settings_return_to_menu = false
	if _staff_panel != null:
		_staff_panel.set_phase(phase)
	if phase == SimClock.Phase.MORNING:
		_begin_morning()


func _on_next_day_pressed() -> void:
	Clock.sim.next_day()
