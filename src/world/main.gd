extends Node3D
## The game session for the Tier 1 shop: builds the restaurant, drives it from
## Clock, keeps the books, shows the evening report at closing and autosaves
## each new morning.
##
## Day loop:
##   MORNING  -> expired stock thrown out, the morning delivery brings the
##               auto-reorder (the standing order), "Open shop" (HUD) starts service
##   OPEN / LAST_ORDERS -> RestaurantSim runs (guests, staff, kitchen)
##   CLOSED   -> wages and rent charged, evening report shown
##   "Next day" -> MORNING of the next day, autosave
## F10 starts a new game (deletes the autosave).

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
## Camera fit (FK-080): this zoom frames this many cells; bigger shops zoom out.
const SHOP_ZOOM: float = 12.0
const SHOP_FRAME_CELLS: Vector2 = Vector2(14.0, 12.0)
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const MESS_TUNING: MessTuning = preload("res://data/balance/messes.tres")
const CLEANLINESS_TUNING: CleanlinessTuning = preload("res://data/balance/cleanliness.tres")
const REVIEW_TUNING: ReviewTuning = preload("res://data/balance/reviews.tres")
const REVIEW_QUOTES: ReviewQuotes = preload("res://data/reviews/quotes.tres")
const PROGRESSION_TUNING: ProgressionTuning = preload("res://data/balance/progression.tres")
const VIBE_TUNING: VibeTuning = preload("res://data/balance/vibe.tres")
const CUSTOMER_TYPES: CustomerTypeCatalogue = preload("res://data/customers/types.tres")
const MILESTONES: MilestoneSet = preload("res://data/milestones/starter.tres")
const HOURS_TUNING: OpeningHoursTuning = preload("res://data/balance/hours.tres")
const AUTOSAVE_SLOT: String = "autosave"
const LOAN_LOCK_REASON: String = "Pay off your bank loan first"

## Save slot used by autosave and the startup load. Tests change it.
var save_slot: String = AUTOSAVE_SLOT
## When false, _ready() neither loads nor writes saves (used by tests).
var use_saves: bool = true
## Title backdrop only: build the default view without starting a run.
var display_only: bool = false
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
## Undo/redo of this morning's (or evening's) edits (FK-085). Cleared at every
## phase change, so it never reaches across opening or into the save.
var edit_history: ShopEditHistory = ShopEditHistory.new()
var build_mode: BuildMode = BuildMode.new()
## Player library is independent of the per-shop snapshot (FK-045).
var blueprint_library: BlueprintLibrary = BlueprintLibrary.new()
var _loaded_blueprints: BlueprintLibrary
var _blueprint_load_notes: Array[String] = []
## Cookable dishes/prices belong to this shop, never to shared recipe resources.
var menu_settings: MenuSettings
var staff_roster: StaffRoster
var _staff_notice_day: int = 0
var _staff_notices: Array[Dictionary] = []
## Last thirty eligible reviews, including five virtual three-star starters.
var reputation: ReputationBook = ReputationBook.new()
var owner_progress: OwnerProgress = OwnerProgress.new(PROGRESSION_TUNING)
## Authored arrivals; tests may inject an explicit neutral Regular-only catalogue.
var customer_type_catalogue: CustomerTypeCatalogue = CUSTOMER_TYPES
## Durable once-only career state; the catalogue is authored, never saved.
var milestones: MilestoneTracker = MilestoneTracker.new()
var milestone_catalogue: MilestoneSet = MILESTONES
## Zero is one plate; the two purchased levels carry two and four.
var tray_level: int = 0
## Per-ingredient morning auto-reorder choices, saved in the "reorder" section.
var reorder_settings: ReorderSettings = ReorderSettings.new(TUNING)
## Auto-order premium. Tests that are not about reorder pricing may set 0.
var auto_reorder_premium: float = TUNING.auto_reorder_premium
## Paid ingredient orders waiting for a delivery (FK-087), saved in the
## "deliveries" section at the morning autosave only. An order placed after
## that save is lost on reload together with its payment and everything else
## since the save: the game goes back to the morning, money and goods both.
var deliveries: DeliveryBook = DeliveryBook.new()
## Delivery schedule; tests may use another tuning resource.
var delivery_tuning: EconomyTuning = TUNING
## The Stock panel's order cart (ingredient id -> units), not yet ordered.
var stock_cart: Dictionary[StringName, int] = {}

var _previous_clock: SimClock = null
var _started: bool = false
var _skip_next_autosave: bool = false
var _owner_preferences: OwnerModeSettings = OwnerModeSettings.new()
var _loaded_layout: ShopLayout = null
var _loaded_menu: MenuSettings = null
var _loaded_staff: StaffRoster = null
var _loaded_plates: PlateLedger = null
var _loaded_reputation: ReputationBook = null
var _loaded_milestones: MilestoneTracker = null
var _loaded_tray_level: int = 0
var _loaded_reorder: ReorderSettings = null
var _loaded_deliveries: DeliveryBook = null
## Today's last daytime delivery ({lines, minute}), for the Stock notes.
var _last_delivery: Dictionary = {}
var _storage_fill_key: String = ""
## Stock thrown out by hand today (id -> units), for the Stock notes.
var _thrown_today: Dictionary[StringName, int] = {}
var _thrown_day: int = 0
## What the morning cut from a cart that no longer fit (id -> units).
var _cart_trimmed: Dictionary[StringName, int] = {}
## This morning's automatic order and expiry, for the Stock panel notes.
var _morning_order: Dictionary = {}
var _expired_this_morning: Dictionary = {}
var _sold_out_shown: int = -1
var _owner_award_today: Dictionary = {}
var _owner_unlocks_today: Array[String] = []
var _owner_tips_today: Array[String] = []
var _owner_award_day: int = 0
var _closed_report_day: int = 0
var _loan_notice_day: int = 0
var _milestones_reached_today: Array[Milestone] = []
var _milestone_award_day: int = 0
var _milestone_xp_today: int = 0
var _report: Control
var _inspect_panel: InspectPanel
var _debug_overlay: DebugOverlay
var _debug_geometry: DebugGeometry
var _build_preview: BuildPreview
var _build_catalogue: BuildCatalogue
## Wall paint hover cache (D26), like the floor's.
var _wall_paint_key: Array = []
var _wall_paint_changes_cache: Dictionary[Vector3i, FloorFinishes.Finish] = {}
## Paint hover cache (see _floor_paint_preview).
var _paint_preview_key: Array = []
var _paint_preview_changes: Dictionary[Vector2i, FloorFinishes.Finish] = {}
## Where Build or Paint last saw the pointer (null before any), for Shift.
var _last_pointer: Variant = null
var _build_ready: bool = false
var _was_build_active: bool = false
var _build_phase: int = -1
var _build_ui_phase: int = -1
var _paint_active: bool = false
var _paint_swatch_id: StringName = &"butter"
## Paint was opened from Build mode's Paint tab: Esc goes back to Build.
var _paint_from_build: bool = false
## The last undo/redo refusal or result, shown in the hint strip until the
## next edit, tool change or mode change.
var _edit_notice: String = ""
## FK-101: an older save's kitchen could not be marked; asked once that morning.
const ROOMS_NOTE: String = "Mark your kitchen in Build → Rooms."
var _rooms_note: bool = false
var _menu_quality: Dictionary[StringName, Dictionary] = {}
## Day-local advice only: these choices were enabled before a layout edit
## made their station unavailable. Undo removes restored dishes from the note.
var _menu_access_losses: Dictionary[StringName, RecipeDef] = {}
var _menu_access_day: int = 0
var _menu_access_error: String = ""
var _menu_panel: MenuPanel
var _staff_panel: StaffPanel
var _settings_panel: SettingsPanel
var _settings_return_to_menu: bool = false
var _settings_previous_speed: int = 0
var _quit_title_previous_speed: int = 0
var _goals_panel: GoalsPanel
var _goals_return_to_menu: bool = false
var _goals_snapshot: Dictionary = {}
var _stock_panel: StockPanel


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
	build_mode.bind_blueprints(null, Callable())
	_was_build_active = false
	_paint_active = false
	var view: ShopView = $ShopView
	view.clear_paint_preview()
	# The back alley runs along the lot's outer edge (FK-099).
	var lot_layout: ShopLayout = _loaded_layout if _loaded_layout != null else LAYOUT
	var lot: Rect2i = ShopFootprint.from_layout(lot_layout).lot
	view.set_lot(lot)
	if sim.dock != null:
		sim.dock.lot = lot
	view.show_world(world)
	view.bind_cleanliness(sim.cleanliness)
	view.bind_dock(sim.dock)
	var painted_layout: ShopLayout = _loaded_layout if _loaded_layout != null else LAYOUT
	view.set_paint(content, painted_layout.wall_swatch_id, painted_layout.floor_swatch_id)
	var camera: CameraRig = $CameraRig
	camera.set_grid_forced(false)
	camera.grid_floor = view.floor_mesh
	_frame_shop(true)
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
	if _build_catalogue != null and not _build_catalogue.blueprint_requested.is_connected(_on_blueprint_requested):
		_build_catalogue.blueprint_selection_requested.connect(_on_blueprint_selection_requested)
		_build_catalogue.blueprint_save_requested.connect(_on_blueprint_save_requested)
		_build_catalogue.blueprint_requested.connect(_on_blueprint_requested)
		_build_catalogue.blueprint_rename_requested.connect(_on_blueprint_rename_requested)
		_build_catalogue.blueprint_delete_requested.connect(_on_blueprint_delete_requested)
	if not _build_catalogue.wall_tool_requested.is_connected(_on_wall_tool_requested):
		_build_catalogue.wall_tool_requested.connect(_on_wall_tool_requested)
	if not _build_catalogue.floor_tool_requested.is_connected(_on_floor_tool_requested):
		_build_catalogue.floor_tool_requested.connect(_on_floor_tool_requested)
	if not _build_catalogue.rooms_tool_requested.is_connected(_on_rooms_tool_requested):
		_build_catalogue.rooms_tool_requested.connect(_on_rooms_tool_requested)
	if not _build_catalogue.floors_tool_requested.is_connected(_on_floors_tool_requested):
		_build_catalogue.floors_tool_requested.connect(_on_floors_tool_requested)
	if not _build_catalogue.wall_finish_tool_requested.is_connected(_on_wall_finish_tool_requested):
		_build_catalogue.wall_finish_tool_requested.connect(_on_wall_finish_tool_requested)
	_build_catalogue.set_floor_base_color(view.floor_base_color())
	_build_catalogue.set_wall_base_color(view.shop_wall_colour())
	if not _build_catalogue.swatch_requested.is_connected(_on_swatch_requested):
		_build_catalogue.swatch_requested.connect(_on_swatch_requested)
	if not _build_catalogue.mode_requested.is_connected(_on_catalogue_mode_requested):
		_build_catalogue.mode_requested.connect(_on_catalogue_mode_requested)
		_build_catalogue.paint_requested.connect(_on_catalogue_paint_requested)
		_build_catalogue.tool_requested.connect(_on_catalogue_tool_requested)
		_build_catalogue.undo_requested.connect(undo_edit)
		_build_catalogue.redo_requested.connect(redo_edit)
		_build_catalogue.grid_requested.connect(_on_catalogue_grid_requested)
	if not camera.grid_shown_changed.is_connected(_on_grid_shown_changed):
		camera.grid_shown_changed.connect(_on_grid_shown_changed)
	_build_catalogue.set_grid_shown(camera.build_grid_visible)
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
	if not _menu_panel.restaurant_name_requested.is_connected(_on_restaurant_name_requested):
		_menu_panel.restaurant_name_requested.connect(_on_restaurant_name_requested)
	if not _menu_panel.goals_requested.is_connected(_on_menu_goals_requested):
		_menu_panel.goals_requested.connect(_on_menu_goals_requested)
	if not _menu_panel.hours_requested.is_connected(_on_hours_requested):
		_menu_panel.hours_requested.connect(_on_hours_requested)
	if not _menu_panel.quit_to_title_requested.is_connected(request_quit_to_title):
		_menu_panel.quit_to_title_requested.connect(request_quit_to_title)
	_menu_panel.set_hours(Clock.sim.display_open_minute, Clock.sim.display_close_minute, HOURS_TUNING)
	_goals_panel = $Overlay/GoalsPanel
	_dismiss_goals()
	if not _goals_panel.close_requested.is_connected(_on_goals_close_requested):
		_goals_panel.close_requested.connect(_on_goals_close_requested)
	if not $HUD.is_connected(&"menu_pressed", toggle_menu):
		$HUD.connect(&"menu_pressed", toggle_menu)
	_settings_panel = $Overlay/SettingsPanel
	_settings_panel.bind_preferences(Preferences)
	_settings_panel.set_quit_to_title_available(true)
	if not _settings_panel.close_requested.is_connected(_on_settings_close_requested):
		_settings_panel.close_requested.connect(_on_settings_close_requested)
	if not _settings_panel.quit_to_title_requested.is_connected(request_quit_to_title):
		_settings_panel.quit_to_title_requested.connect(request_quit_to_title)
	var quit_dialog: ConfirmationDialog = $Overlay/QuitToTitle
	# Keep native dialog padding, but use the shared palette in this dialog only.
	var dialog_theme: Theme = _menu_panel.theme.duplicate() as Theme
	var dialog_panel: StyleBoxFlat = quit_dialog.get_theme_stylebox("panel", "AcceptDialog").duplicate() as StyleBoxFlat
	dialog_panel.bg_color = (_menu_panel.theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color
	dialog_theme.set_stylebox("panel", "AcceptDialog", dialog_panel)
	dialog_theme.set_color("font_focus_color", "Button", _menu_panel.theme.get_color("font_color", "Button"))
	quit_dialog.theme = dialog_theme
	quit_dialog.title = TitleText.QUIT_TO_TITLE
	quit_dialog.dialog_text = TitleText.LOST_PROGRESS
	quit_dialog.ok_button_text = TitleText.QUIT_TO_TITLE
	quit_dialog.cancel_button_text = TitleText.KEEP_PLAYING
	if not quit_dialog.confirmed.is_connected(_quit_to_title):
		quit_dialog.confirmed.connect(_quit_to_title)
		quit_dialog.canceled.connect(_cancel_quit_to_title)
	_staff_panel = $Overlay/StaffPanel
	_staff_panel.bind_roster(staff_roster)
	_staff_panel.set_phase(Clock.sim.phase)
	_staff_panel.set_wage_factor(OpeningHours.wage_factor(Clock.sim, HOURS_TUNING))
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
	_stock_panel = $Overlay/StockPanel
	if not _stock_panel.cart_requested.is_connected(_on_stock_cart_requested):
		_stock_panel.cart_requested.connect(_on_stock_cart_requested)
		_stock_panel.order_requested.connect(_on_stock_order_requested)
		_stock_panel.clear_requested.connect(_on_stock_clear_requested)
		_stock_panel.cancel_requested.connect(_on_stock_cancel_requested)
		_stock_panel.throw_requested.connect(_on_stock_throw_requested)
		_stock_panel.auto_requested.connect(_on_stock_auto_requested)
		_stock_panel.target_requested.connect(_on_stock_target_requested)
		_stock_panel.close_requested.connect(_on_stock_close_requested)
	if not $HUD.is_connected(&"stock_pressed", toggle_stock):
		$HUD.connect(&"stock_pressed", toggle_stock)
	_refresh_stock_panel()
	_inspect_panel.bind_world(world)
	_debug_overlay.bind_world(world)
	_debug_overlay.bind_cleanliness(sim.cleanliness)
	_on_header_layout_changed()
	refresh_presentation()


## Centres the camera on the whole building and zooms so it fits (FK-080).
## The starting shell keeps exactly its old framing: zoom 12 for 14 x 12 cells.
## `reset` restores the default view; otherwise the view glides to the new fit.
func _frame_shop(reset: bool) -> void:
	var camera: CameraRig = $CameraRig
	var area: Rect2i = Rect2i()
	for cell: Vector2i in world.grid.cells():
		if world.grid.terrain(cell) != SimGrid.Terrain.OUTSIDE:
			area = Rect2i(cell, Vector2i.ONE) if area.size == Vector2i.ZERO else area.merge(Rect2i(cell, Vector2i.ONE))
	var low: Vector2 = Vector2(area.position) * GridMath.CELL_SIZE
	var half: Vector2 = Vector2(area.size) * GridMath.CELL_SIZE * 0.5
	var zoom: float = SHOP_ZOOM * maxf(1.0, maxf(float(area.size.x) / SHOP_FRAME_CELLS.x, float(area.size.y) / SHOP_FRAME_CELLS.y))
	# Pan around the shop itself, with a 2 m margin on every side.
	camera.frame_area(low + half, half + Vector2(2.0, 2.0), zoom, reset)


func _on_header_layout_changed() -> void:
	var top: float = float($HUD.call("panel_top"))
	for path: NodePath in [^"Overlay/MenuPanel/Panel", ^"Overlay/StaffPanel/Panel", ^"Overlay/StockPanel/Panel",
			^"Overlay/EveningReport/Panel", ^"Overlay/DebugOverlay/Panel", ^"Overlay/GoalsPanel/Panel"]:
		var panel: Control = get_node(path) as Control
		if path == ^"Overlay/GoalsPanel/Panel":
			panel.anchor_top = 0.0
		panel.offset_top = top
	if _settings_panel != null:
		_settings_panel.set_panel_top(top)


func _ready() -> void:
	if display_only:
		initialize()
		$HUD.hide()
		$Overlay.hide()
		process_mode = Node.PROCESS_MODE_DISABLED
	else:
		start()


func _process(_delta: float) -> void:
	if world == null:
		return
	_debug_overlay.sample_rates(float(Time.get_ticks_usec()) / 1000000.0, Engine.get_frames_per_second())
	_guard_build_phase()
	if build_mode.blueprint_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		build_mode.blueprint_release(SimGrid.NO_CELL)
	if build_mode.wall_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# A release over a panel never reaches _unhandled_input (the GUI consumes
		# it); end that wall drag instead of leaving it stuck to the pointer.
		build_mode.cancel()
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
	if display_only:
		return
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
	SaveSystem.register("blueprints", _capture_blueprints, _restore_blueprints)
	SaveSystem.register("menu", _capture_menu, _restore_menu)
	SaveSystem.register("staff", _capture_staff, _restore_staff)
	SaveSystem.register("plates", _capture_plates, _restore_plates)
	SaveSystem.register("reviews", _capture_reviews, _restore_reviews)
	SaveSystem.register("milestones", _capture_milestones, _restore_milestones)
	SaveSystem.register("reorder", _capture_reorder, _restore_reorder)
	SaveSystem.register("deliveries", _capture_deliveries, _restore_deliveries)
	var loaded: bool = use_saves and _load_autosave()
	_rooms_note = loaded and _loaded_layout != null and _loaded_layout.rooms_unmarked
	$HUD.set_rooms_note(ROOMS_NOTE if _rooms_note else "")
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
	if not sim.configure_messes(MESS_TUNING, GameState.rng(&"cleanliness")):
		push_error("Cannot initialize everyday messes")
		return
	sim.plate_broken.connect(_on_plate_broken)
	# The loaded layout can replace both world and view during _load_autosave().
	($ShopView as ShopView).bind_cleanliness(cleanliness)
	_debug_overlay.bind_cleanliness(cleanliness)
	sim.configure_reviews(reputation, REVIEW_TUNING, REVIEW_QUOTES, GameState.rng(&"reviews"))
	# Configure only after the complete restore/new-game decision, using its
	# real reputation and owner level. This consumes no customer RNG draw.
	if not sim.configure_customer_types(customer_type_catalogue, owner_progress.level):
		push_error("Cannot initialize customer preferences")
		return
	sim.spawner.min_gap = TUNING.arrival_gap_min
	sim.spawner.max_gap = TUNING.arrival_gap_max
	shop_editor = ShopEditor.new(sim, content, ShopEditBooks.new(Economy.can_buy_discretionary,
		Economy.add_cash, _furniture_purchase_refusal),
		_loaded_layout if _loaded_layout != null else LAYOUT)
	shop_editor.set_owner_level(owner_progress.level)
	shop_editor.storage_need = _storage_need
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
	if not EventBus.sim_ticked.is_connected(_on_delivery_tick):
		EventBus.sim_ticked.connect(_on_delivery_tick)
	if sim.dock != null and not sim.dock.stored.is_connected(_on_dock_stored):
		sim.dock.stored.connect(_on_dock_stored)
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
	build_mode.bind_blueprints(null, Callable())
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
	if EventBus.sim_ticked.is_connected(_on_delivery_tick):
		EventBus.sim_ticked.disconnect(_on_delivery_tick)
	if sim != null and sim.dock != null and sim.dock.stored.is_connected(_on_dock_stored):
		sim.dock.stored.disconnect(_on_dock_stored)
	if EventBus.cash_changed.is_connected(_on_build_cash_changed):
		EventBus.cash_changed.disconnect(_on_build_cash_changed)
	if world != null and Clock.attached_world == world:
		Clock.attach_world(null)
		if _previous_clock != null:
			Clock.sim = _previous_clock


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and _build_catalogue != null and _build_catalogue.blueprint_name_has_focus():
		return
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
	if key != null and not key.echo:
		_on_shift_changed(key)
	if route_paint_input(event) or route_build_input(event):
		_mark_input_handled()
		return
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_ESCAPE:
			if is_goals_visible():
				set_goals_visible(false)
			elif is_menu_visible():
				set_menu_visible(false)
			elif _staff_panel != null and _staff_panel.visible:
				set_staff_visible(false)
			elif is_stock_visible():
				set_stock_visible(false)
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
	if event is InputEventKey and _build_catalogue != null and _build_catalogue.blueprint_name_has_focus():
		return false
	_guard_build_phase()
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_B:
			return set_build_active(not is_build_active())
		if is_build_active():
			if _undo_key(key):
				return true
			match code:
				KEY_R, KEY_PERIOD:
					build_mode.rotate(1)
					return true
				KEY_COMMA:
					build_mode.rotate(-1)
					return true
				KEY_DELETE:
					if build_mode.state == BuildMode.State.WALLS:
						build_mode.wall_remove_hovered()
					elif build_mode.state == BuildMode.State.HANG:
						build_mode.sell_held_wall_item()
					elif build_mode.state == BuildMode.State.IDLE and build_mode.hover_anchor != WallFaces.NO_FACE:
						build_mode.take_down_hovered()
					elif build_mode.state == BuildMode.State.IDLE and build_mode.tool == BuildMode.Tool.SELL:
						build_mode.sell_hovered()
					else:
						build_mode.sell_selected()
					return true
				KEY_ESCAPE:
					build_mode.cancel()
					return true
	if not is_build_active():
		return false
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		update_build_pointer(motion.position, motion.shift_pressed)
		return false  # Camera drag/edge tracking still receives motion.
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click drops the ghost (or a drag); it never leaves the mode.
		return build_mode.cancel_ghost()
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and build_mode.state == BuildMode.State.SELECT:
		var selection_cell: Variant = build_cell_at_screen_position(mouse.position)
		if mouse.pressed and selection_cell is Vector2i:
			build_mode.blueprint_press(selection_cell)
		elif not mouse.pressed:
			build_mode.blueprint_release(selection_cell if selection_cell is Vector2i else SimGrid.NO_CELL)
		return true
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and build_mode.state == BuildMode.State.WALLS:
		var point: Variant = build_point_at_screen_position(mouse.position)
		if point is Vector2:
			if mouse.pressed:
				build_mode.wall_press(point)
			else:
				build_mode.wall_release(point)
		return true
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and build_mode.state == BuildMode.State.FLOOR:
		var floor_cell: Variant = build_cell_at_screen_position(mouse.position)
		if floor_cell is Vector2i:
			if mouse.pressed:
				build_mode.floor_press(floor_cell, mouse.shift_pressed)
			else:
				build_mode.floor_release(floor_cell)
		return true
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and build_mode.state == BuildMode.State.FLOORS:
		var floors_cell: Variant = build_cell_at_screen_position(mouse.position)
		if floors_cell is Vector2i:
			if mouse.pressed and mouse.alt_pressed:
				# The eyedropper: copy a floor's look into the tool and the tab.
				if build_mode.floors_pick(floors_cell) and _build_catalogue != null:
					_build_catalogue.select_floor(build_mode.floor_style, build_mode.floor_swatch, build_mode.floor_accent)
			elif mouse.pressed:
				build_mode.floors_press(floors_cell, mouse.shift_pressed)
			else:
				build_mode.floors_release(floors_cell)
		return true
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and build_mode.state == BuildMode.State.WALL_FINISH:
		var face: Vector3i = wall_face_at_screen_position(mouse.position).get("face", WallFaces.NO_FACE)
		if mouse.pressed and mouse.alt_pressed:
			if build_mode.wall_finish_pick(face) and _build_catalogue != null:
				_build_catalogue.select_wall_finish(build_mode.wall_style, build_mode.wall_swatch, build_mode.wall_accent)
		elif mouse.pressed:
			build_mode.wall_finish_press(face, mouse.shift_pressed)
		else:
			build_mode.wall_finish_release(face)
		return true
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and build_mode.state == BuildMode.State.HANG:
		update_build_pointer(mouse.position)
		build_mode.hang_commit()
		return true
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and build_mode.state == BuildMode.State.IDLE:
		var hung: Vector3i = wall_item_at_screen_position(mouse.position)
		if hung != WallFaces.NO_FACE:
			build_mode.hover_wall_item(hung)
			match build_mode.tool:
				BuildMode.Tool.EYEDROPPER:
					var copied: ItemDef = shop_editor.hung_definition(hung)
					if copied != null and build_mode.begin_hang(copied.id) and _build_catalogue != null:
						_build_catalogue.set_category(BuildCatalogue.category_for(copied))
				BuildMode.Tool.SELL:
					build_mode.take_down_hovered()
				_:
					build_mode.begin_rehang(hung)
			update_build_pointer(mouse.position)
			return true
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and build_mode.state == BuildMode.State.ROOMS:
		var room_cell: Variant = build_cell_at_screen_position(mouse.position)
		if room_cell is Vector2i:
			if mouse.pressed:
				build_mode.rooms_press(room_cell)
			else:
				build_mode.rooms_release(room_cell)
		return true
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
					match build_mode.tool:
						BuildMode.Tool.EYEDROPPER:
							if build_mode.eyedrop(item.id, cell):
								_set_catalogue_room_for(item)
						BuildMode.Tool.SELL:
							build_mode.hover_item(item.id)
							build_mode.sell_hovered()
						_:
							build_mode.pick_up_at(item.id, cell)
		return true
	return false


## Ctrl+Z undoes, Ctrl+Y or Ctrl+Shift+Z redoes (Cmd on macOS).
func _undo_key(key: InputEventKey) -> bool:
	if not key.is_command_or_control_pressed():
		return false
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_Z and not key.shift_pressed:
		undo_edit()
		return true
	if code == KEY_Y or (code == KEY_Z and key.shift_pressed):
		redo_edit()
		return true
	return false


## Shift pressed or released over a still mouse: the Floors tool's room fill
## and Paint's whole-room preview follow at once. Never consumes the key.
func _on_shift_changed(key: InputEventKey) -> void:
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code != KEY_SHIFT or _last_pointer == null:
		return
	if _paint_active:
		update_paint_pointer(_last_pointer, key.pressed)
	elif is_build_active() and (build_mode.state == BuildMode.State.FLOORS or build_mode.state == BuildMode.State.WALL_FINISH):
		update_build_pointer(_last_pointer, key.pressed)


## Paint has its own input path so service-time recolouring cannot move items.
func route_paint_input(event: InputEvent) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_P:
			return set_paint_active(not _paint_active)
		if _paint_active and _undo_key(key):
			return true
		if _paint_active and code == KEY_ESCAPE:
			# One level back: to Build mode when Paint was opened from there.
			var back_to_build: bool = _paint_from_build
			set_paint_active(false)
			if back_to_build:
				set_build_active(true)
				_build_catalogue.set_mode(BuildCatalogue.BUILD)
			return true
		if _paint_active and code == KEY_B:
			set_paint_active(false)
	if not _paint_active:
		return false
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		update_paint_pointer(motion.position, motion.shift_pressed)
		return false
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		var face: Vector3i = paint_face_at_screen_position(mouse.position)
		if face != WallFaces.NO_FACE:
			paint_face(face, mouse.shift_pressed)
			return true
		if wall_item_at_screen_position(mouse.position) != WallFaces.NO_FACE:
			return true  # Wall decor takes no paint (yet); never the wall behind it.
		var cell: Variant = paint_cell_at_screen_position(mouse.position)
		if cell is Vector2i:
			paint_cell(cell, mouse.shift_pressed)
		return true
	return false


## The wall face a paint click would recolour (D26): the room side of a wall
## hit before any furniture; NO_FACE otherwise (the outside of the shell
## still paints the shop's own wall colour, as before).
func paint_face_at_screen_position(screen_position: Vector2) -> Vector3i:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return WallFaces.NO_FACE
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var view: ShopView = $ShopView as ShopView
	var hit: Dictionary = view.wall_face_at_ray(origin, direction)
	if hit.is_empty() or hit["face"] == WallFaces.NO_FACE:
		return WallFaces.NO_FACE
	if view.nearest_item_distance(origin, direction) < float(hit["distance"]) \
			or view.wall_item_at_ray(origin, direction) != WallFaces.NO_FACE:
		return WallFaces.NO_FACE
	return hit["face"]


## A wall paint click (D26): the connected run of walls that look like `face`
## (inside its room), or with Shift every wall of the room, takes the paint
## colour and keeps its finish. Free at any time, like all paint.
func paint_face(face: Vector3i, whole_room: bool = false) -> bool:
	if not _paint_active or shop_editor == null:
		return false
	var accepted: bool = edit_history.apply_wall_finishes(_wall_paint_changes(face, whole_room))
	if accepted:
		_edit_notice = ""
		_update_build_controls()
	return accepted or shop_editor.last_check.why == ShopEditor.WALL_FINISH_ALREADY


func _wall_paint_changes(face: Vector3i, whole_room: bool) -> Dictionary[Vector3i, FloorFinishes.Finish]:
	if shop_editor == null:
		return {}
	var faces: Array[Vector3i] = shop_editor.wall_room_faces(face) if whole_room else shop_editor.wall_area_faces(face)
	return shop_editor.wall_recolour_changes(faces, _paint_swatch_id)


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
		_dismiss_goals()
		set_menu_visible(false)
		set_staff_visible(false)
		set_stock_visible(false)
		clear_selection()
		_report.hide()
	_paint_active = active
	if not active:
		_paint_from_build = false
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


## `whole_room` (Shift) recolours the pointed floor's whole room (D25).
func update_paint_pointer(screen_position: Vector2, whole_room: bool = false) -> void:
	if not _paint_active:
		return
	_last_pointer = screen_position
	var face: Vector3i = paint_face_at_screen_position(screen_position)
	if face != WallFaces.NO_FACE:
		var view: ShopView = $ShopView as ShopView
		view.preview_paint(&"", -1, &"")
		view.clear_floor_preview()
		var key: Array = [face, whole_room, _paint_swatch_id, world.grid.get_instance_id(), world.grid.version,
			shop_editor.walls.get_instance_id(), shop_editor.walls.revision]
		if key != _wall_paint_key:
			_wall_paint_key = key
			_wall_paint_changes_cache = _wall_paint_changes(face, whole_room)
		view.preview_wall_finishes(_wall_paint_changes_cache)
		return
	if wall_item_at_screen_position(screen_position) != WallFaces.NO_FACE:
		($ShopView as ShopView).clear_paint_preview()
		return
	var cell: Variant = paint_cell_at_screen_position(screen_position)
	preview_paint_cell(cell, whole_room)


func paint_cell_at_screen_position(screen_position: Vector2) -> Variant:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return null
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var mesh_cell: Variant = ($ShopView as ShopView).paint_cell_at_ray(ray_origin, ray_direction)
	return mesh_cell if mesh_cell is Vector2i else build_cell_at_screen_position(screen_position)


func preview_paint_cell(cell: Variant, whole_room: bool = false) -> void:
	var view: ShopView = $ShopView as ShopView
	if not _paint_active or not cell is Vector2i:
		view.clear_paint_preview()
		return
	view.clear_wall_preview()
	var target: Dictionary = _paint_target(cell)
	var kind: StringName = target.get("kind", &"")
	var item_id: int = target.get("item_id", -1)
	if kind == &"floor":
		# The floor recolours per area (D25): show just the cells a click changes.
		view.preview_paint(&"", -1, &"")
		view.preview_floor_finishes(_floor_paint_preview(cell, whole_room))
		return
	view.clear_floor_preview()
	view.preview_paint(kind, item_id, _paint_swatch_id)


## A floor paint click (D25): the connected floor that looks like `cell`, or
## with Shift its whole room, takes the paint colour and keeps its floor type.
func _floor_paint_changes(cell: Vector2i, whole_room: bool) -> Dictionary[Vector2i, FloorFinishes.Finish]:
	if shop_editor == null:
		return {}
	var cells: Array[Vector2i] = shop_editor.floor_room_cells(cell) if whole_room else shop_editor.floor_area_cells(cell)
	return shop_editor.recolour_changes(cells, _paint_swatch_id)


## The hover preview's area, re-filled only when the cell, Shift, the colour,
## the floor looks or the grid changed (not on every mouse move in one cell).
func _floor_paint_preview(cell: Vector2i, whole_room: bool) -> Dictionary[Vector2i, FloorFinishes.Finish]:
	if shop_editor == null or world == null:
		return {}
	var key: Array = [cell, whole_room, _paint_swatch_id, world.grid.get_instance_id(), world.grid.version,
		shop_editor.floors.get_instance_id(), shop_editor.floors.revision]
	if key != _paint_preview_key:
		_paint_preview_key = key
		_paint_preview_changes = _floor_paint_changes(cell, whole_room)
	return _paint_preview_changes


func paint_cell(cell: Vector2i, whole_room: bool = false) -> bool:
	if not _paint_active or shop_editor == null:
		return false
	var target: Dictionary = _paint_target(cell)
	var kind: StringName = target.get("kind", &"")
	if kind == &"floor":
		# Free at any time; recorded for undo while editing is allowed.
		var recoloured: bool = edit_history.apply_flooring(_floor_paint_changes(cell, whole_room))
		if recoloured:
			_edit_notice = ""
			_update_build_controls()
		# Painting a floor its own colour again is fine, like any paint.
		return recoloured or shop_editor.last_check.why == ShopEditor.FLOORS_ALREADY
	var previous: StringName = shop_editor.wall_swatch_id if kind == &"wall" else (
		shop_editor.floor_swatch_id if kind == &"floor" else (
			world.grid.item(target["item_id"]).swatch_id if kind == &"item" else &""))
	var accepted: bool = not kind.is_empty() and edit_history.paint(kind, _paint_swatch_id, target.get("item_id", -1))
	if accepted:
		_edit_notice = ""
		_update_build_controls()
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
		shop_editor.wall_vibe_swatch(), shop_editor.floor_vibe_swatch(), shop_editor.decor_vibe_items())
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
		_dismiss_goals()
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


## The floor-plane point in shop metres (x, z), for the Walls tool's grid lines.
func build_point_at_screen_position(screen_position: Vector2) -> Variant:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return null
	var hit: Variant = Picker.floor_intersection(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	return Vector2((hit as Vector3).x, (hit as Vector3).z) if hit is Vector3 else null


## Walls tool (FK-070): new edges get `kind`; see BuildMode.begin_walls.
func begin_wall_tool(kind: SimGrid.Segment) -> bool:
	if not is_build_active():
		return false
	var started: bool = build_mode.begin_walls(kind)
	if started and is_inside_tree():
		update_build_pointer(get_viewport().get_mouse_position())
	return started


func update_build_pointer(screen_position: Vector2, shift: bool = false) -> bool:
	if not is_build_active():
		return false
	_last_pointer = screen_position
	if build_mode.state == BuildMode.State.SELECT:
		var selection_cell: Variant = build_cell_at_screen_position(screen_position)
		if selection_cell is Vector2i:
			build_mode.blueprint_pointer(selection_cell)
		return selection_cell is Vector2i
	if build_mode.state == BuildMode.State.FLOOR:
		var floor_cell: Variant = build_cell_at_screen_position(screen_position)
		if floor_cell is Vector2i:
			build_mode.floor_pointer(floor_cell, shift)
		return floor_cell is Vector2i
	if build_mode.state == BuildMode.State.ROOMS:
		var room_cell: Variant = build_cell_at_screen_position(screen_position)
		if room_cell is Vector2i:
			build_mode.rooms_pointer(room_cell)
		return room_cell is Vector2i
	if build_mode.state == BuildMode.State.FLOORS:
		var floors_cell: Variant = build_cell_at_screen_position(screen_position)
		if floors_cell is Vector2i:
			build_mode.floors_pointer(floors_cell, shift)
		return floors_cell is Vector2i
	if build_mode.state == BuildMode.State.WALLS:
		var point: Variant = build_point_at_screen_position(screen_position)
		if point is Vector2:
			build_mode.wall_pointer(point)
		return point is Vector2
	if build_mode.state == BuildMode.State.WALL_FINISH:
		build_mode.wall_finish_pointer(wall_face_at_screen_position(screen_position).get("face", WallFaces.NO_FACE), shift)
		return true
	if build_mode.state == BuildMode.State.HANG:
		var hit: Dictionary = {}
		if build_mode.hang_definition != null and build_mode.hang_definition.hangs_in_window():
			hit = window_at_screen_position(screen_position)
		if hit.is_empty():
			hit = wall_face_at_screen_position(screen_position)
		build_mode.hang_pointer(hit.get("face", WallFaces.NO_FACE), float(hit.get("offset", 0.0)))
		return true
	if build_mode.state == BuildMode.State.IDLE:
		var hung: Vector3i = wall_item_at_screen_position(screen_position)
		build_mode.hover_wall_item(hung)
		if hung != WallFaces.NO_FACE:
			build_mode.hover_item(-1)
			return true
	var cell: Variant = build_cell_at_screen_position(screen_position)
	if not cell is Vector2i:
		build_mode.hover_item(-1)
		return false
	if build_mode.has_ghost():
		build_mode.update_origin(cell)
	elif build_mode.state == BuildMode.State.IDLE:
		var hovered: PlacedItem = world.grid.item_at(cell)
		build_mode.hover_item(hovered.id if hovered != null else -1)
	return true


## Floor tool (FK-080): drag to buy lot floor, Shift-drag to remove bought floor.
func begin_floor_tool() -> bool:
	if not is_build_active():
		return false
	var started: bool = build_mode.begin_floor()
	if started and is_inside_tree():
		update_build_pointer(get_viewport().get_mouse_position())
	return started


## Rooms tool (FK-101): drag to paint `kind` (SimGrid.Room) onto the floor.
func begin_rooms_tool(kind: int) -> bool:
	if not is_build_active():
		return false
	var started: bool = build_mode.begin_rooms(kind)
	if started and is_inside_tree():
		update_build_pointer(get_viewport().get_mouse_position())
	return started


## Floors tool (D25): lay `style_id` in these colours; while the tool runs,
## another card or colour changes what it lays.
func begin_floors_tool(style_id: StringName, swatch_id: StringName, accent_id: StringName = &"") -> bool:
	if not is_build_active():
		return false
	var started: bool = true
	if build_mode.state == BuildMode.State.FLOORS:
		build_mode.set_floor_finish(style_id, swatch_id, accent_id)
	else:
		started = build_mode.begin_floors(style_id, swatch_id, accent_id)
	if started and is_inside_tree():
		update_build_pointer(get_viewport().get_mouse_position())
	return started


func _on_floors_tool_requested(style_id: StringName, swatch_id: StringName, accent_id: StringName) -> void:
	begin_floors_tool(style_id, swatch_id, accent_id)


## Wall decor (D26): hold a wall item to hang on the hovered wall face.
func begin_hang_item(def_id: StringName) -> bool:
	if not is_build_active():
		return false
	var started: bool = build_mode.begin_hang(def_id)
	if started and is_inside_tree():
		update_build_pointer(get_viewport().get_mouse_position())
	return started


## Wall finish tool (D26): put `style_id` up in these colours; while the tool
## runs, another card or colour changes what it puts up.
func begin_wall_finish_tool(style_id: StringName, swatch_id: StringName, accent_id: StringName = &"") -> bool:
	if not is_build_active():
		return false
	var started: bool = true
	if build_mode.state == BuildMode.State.WALL_FINISH:
		build_mode.set_wall_finish(style_id, swatch_id, accent_id)
	else:
		started = build_mode.begin_wall_finish(style_id, swatch_id, accent_id)
	if started and is_inside_tree():
		update_build_pointer(get_viewport().get_mouse_position())
	return started


func _on_wall_finish_tool_requested(style_id: StringName, swatch_id: StringName, accent_id: StringName) -> void:
	begin_wall_finish_tool(style_id, swatch_id, accent_id)


## The wall face under the pointer ({face, offset}, see ShopView.wall_face_at_ray).
func wall_face_at_screen_position(screen_position: Vector2, floor_fallback: bool = true) -> Dictionary:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return {}
	return ($ShopView as ShopView).wall_face_at_ray(camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position), floor_fallback)


## The outside window under the pointer ({face, offset}, see ShopView.window_at_ray).
func window_at_screen_position(screen_position: Vector2) -> Dictionary:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return {}
	return ($ShopView as ShopView).window_at_ray(camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position))


## The hung wall item under the pointer, or NO_FACE.
func wall_item_at_screen_position(screen_position: Vector2) -> Vector3i:
	var camera: Camera3D = $CameraRig/Camera3D
	if world == null or not camera.is_inside_tree():
		return WallFaces.NO_FACE
	return ($ShopView as ShopView).wall_item_at_ray(camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position))


func begin_buy_item(def_id: StringName) -> bool:
	if not is_build_active():
		return false
	var cell: Variant = build_cell_at_screen_position(get_viewport().get_mouse_position()) if is_inside_tree() else null
	return build_mode.begin_buy(def_id, cell if cell is Vector2i else Vector2i.ZERO)


func _on_blueprint_selection_requested() -> void:
	if is_build_active():
		build_mode.begin_blueprint_selection()


func _on_blueprint_save_requested(name: String) -> void:
	if is_build_active():
		build_mode.save_blueprint(name)


func _on_blueprint_requested(blueprint: Blueprint) -> void:
	if not is_build_active() or not blueprint_library.blueprints.has(blueprint):
		return
	var cell: Variant = build_cell_at_screen_position(get_viewport().get_mouse_position()) if is_inside_tree() else null
	build_mode.begin_blueprint(blueprint, cell if cell is Vector2i else Vector2i.ZERO)


func _on_blueprint_rename_requested(blueprint: Blueprint, name: String) -> void:
	if is_build_active() and shop_editor.can_edit():
		blueprint_library.rename(blueprint, name)
		_update_build_controls()


func _on_blueprint_delete_requested(blueprint: Blueprint) -> void:
	if is_build_active() and shop_editor.can_edit():
		if build_mode.selected_blueprint == blueprint:
			build_mode.cancel_ghost()
		blueprint_library.remove(blueprint)


func _bind_build_session() -> void:
	if not build_mode.changed.is_connected(_on_build_changed):
		build_mode.changed.connect(_on_build_changed)
	edit_history = ShopEditHistory.new(shop_editor, world.grid)
	build_mode.bind_session(shop_editor, world, content, shop_move, shop_buy, shop_sell, shop_walls, shop_floor,
		shop_rooms, shop_flooring)
	($ShopView as ShopView).set_paint(content, shop_editor.wall_swatch_id, shop_editor.floor_swatch_id)
	($ShopView as ShopView).bind_floor_finishes(shop_editor.floors)
	if not shop_editor.floors.changed.is_connected(_on_floor_looks_changed):
		shop_editor.floors.changed.connect(_on_floor_looks_changed)
	# Wall finishes and wall decor (D26): drawn by ShopView, felt by the vibe.
	build_mode.bind_walls(shop_wall_finishes, shop_hang, shop_rehang, shop_take_down)
	build_mode.bind_blueprints(blueprint_library, shop_stamp)
	if _build_catalogue != null:
		_build_catalogue.bind_blueprints(blueprint_library)
	($ShopView as ShopView).bind_wall_finishes(shop_editor.walls, shop_editor.decor)
	if _build_catalogue != null:
		_build_catalogue.set_wall_base_color(($ShopView as ShopView).shop_wall_colour())
	if not shop_editor.walls.changed.is_connected(_on_wall_looks_changed):
		shop_editor.walls.changed.connect(_on_wall_looks_changed)
	if not shop_editor.decor.changed.is_connected(_on_wall_decor_changed):
		shop_editor.decor.changed.connect(_on_wall_decor_changed)
	_build_preview.bind_build_mode(build_mode, $ShopView as ShopView)
	if _build_catalogue != null and not _build_catalogue.hygiene_toggled.is_connected(_on_hygiene_toggled):
		_build_catalogue.hygiene_toggled.connect(_on_hygiene_toggled)
	var lot: ShopFootprint = shop_editor.footprint()
	if _build_catalogue != null:
		_build_catalogue.set_floor_price(lot.cell_price if lot != null and lot.has_lot() else 0)
		_build_catalogue.set_rooms_enabled(true)
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


## The Build bar's Grid button: like G while building.
func _on_catalogue_grid_requested() -> void:
	var camera: CameraRig = $CameraRig
	if is_build_active():
		camera.toggle_grid()
	_build_catalogue.set_grid_shown(camera.build_grid_visible)


func _on_hygiene_toggled(_active: bool) -> void:
	_refresh_hygiene_overview()


func _refresh_hygiene_overview() -> void:
	if _build_catalogue == null or _build_preview == null:
		return
	var active: bool = is_build_active() and _build_catalogue.hygiene_enabled
	if active:
		var state: HygieneOverview.Snapshot = HygieneOverview.capture(sim)
		_build_catalogue.set_hygiene_lines(HygieneOverview.lines(state))
		_build_preview.set_hygiene_cells(state.problem_cells, true)
	else:
		_build_preview.set_hygiene_cells([] as Array[Vector2i], false)


func _on_grid_shown_changed(_shown: bool) -> void:
	if _build_catalogue != null:
		_build_catalogue.set_grid_shown(($CameraRig as CameraRig).build_grid_visible)


func _on_build_changed() -> void:
	var active: bool = is_build_active()
	($CameraRig as CameraRig).set_grid_forced(active)
	if active and not _was_build_active:
		_build_phase = world.clock.phase
		_clear_rooms_note()
		_dismiss_goals()
		set_menu_visible(false)
		set_staff_visible(false)
		set_stock_visible(false)
		clear_selection()
		_report.hide()
	elif not active and _was_build_active:
		_edit_notice = ""
	if not active and _was_build_active and _build_ready and world.clock.phase == SimClock.Phase.CLOSED:
		# Rebuild from current books; do not run closing charges or day setup.
		shown_report = build_report(world.clock.day)
		_report.call(&"show_report", shown_report)
	_was_build_active = active
	_update_build_controls()


func _update_build_controls() -> void:
	_sync_wall_build_preview()
	var active: bool = is_build_active()
	var available: bool = _build_ready and shop_editor != null and shop_editor.can_edit()
	var reason: String = build_mode.feedback_text()
	var summary: String = ""
	if build_mode.state == BuildMode.State.WALLS:
		summary = build_mode.wall_summary()
	elif build_mode.state == BuildMode.State.FLOOR:
		summary = build_mode.floor_summary()
	elif build_mode.state == BuildMode.State.ROOMS:
		summary = build_mode.rooms_summary()
	elif build_mode.state == BuildMode.State.FLOORS:
		summary = build_mode.floors_summary()
	elif build_mode.state == BuildMode.State.WALL_FINISH:
		summary = build_mode.wall_finish_summary()
	elif build_mode.state == BuildMode.State.HANG:
		summary = build_mode.hang_summary()
	elif build_mode.state in [BuildMode.State.SELECT, BuildMode.State.BLUEPRINT]:
		summary = build_mode.blueprint_summary()
	elif build_mode.state == BuildMode.State.IDLE:
		# The sell/eyedropper hover text, or why an idle tool click was refused.
		summary = build_mode.hover_summary()
		if summary.is_empty() and not build_mode.current_check.ok:
			summary = build_mode.current_check.why
	if not summary.is_empty():
		# An invalid wall or floor check already put its reason in the summary.
		reason = summary if reason.is_empty() or not build_mode.current_check.ok else summary + "\n" + reason
	if build_mode.has_ghost() and reason.is_empty():
		# The ghost's markers: a square for each work tile, a circle per seat.
		reason = BuildCatalogue.FURNITURE_HINT
	if not _edit_notice.is_empty():
		reason = _edit_notice if reason.is_empty() else _edit_notice + "\n" + reason
	if not _menu_access_error.is_empty():
		reason = _menu_access_error if reason.is_empty() else reason + "\n" + _menu_access_error
	# Menu and restock advice share the existing amber line under the cost.
	$HUD.set_build_state(available, active, reason, int(build_mode.state), int(build_mode.tool),
		build_warning())
	$HUD.set_paint_state(_paint_active)
	if _build_catalogue != null:
		_build_catalogue.set_paint_visible(_paint_active)
		var editable: bool = available
		_build_catalogue.set_tool_state(int(build_mode.tool), edit_history.can_undo(), edit_history.can_redo(),
			edit_history.undo_label(), edit_history.redo_label(), editable)
		_build_catalogue.set_build_visible(active or _paint_active)
		_build_catalogue.set_blueprint_selection(0 if build_mode.blueprint_dragging else build_mode.blueprint_selection.size())
	_build_ui_phase = world.clock.phase if world != null else -1
	_refresh_hygiene_overview()


## The Wall finish tool's proposal and a held wall item's ghost (D26), drawn
## by ShopView; nothing changes until a commit.
func _sync_wall_build_preview() -> void:
	var view: ShopView = $ShopView as ShopView
	if view == null or view.wall_finish_view == null:
		return
	if build_mode.state == BuildMode.State.WALL_FINISH and build_mode.current_check.ok:
		view.preview_wall_finishes(build_mode.current_check.wall_finishes)
	elif not _paint_active:
		view.clear_wall_preview()
	if build_mode.state == BuildMode.State.HANG:
		view.wall_finish_view.show_ghost(build_mode.hang_definition, build_mode.hang_anchor,
			build_mode.current_check.ok, build_mode.hang_moving)
	else:
		view.wall_finish_view.hide_ghost()

## The preview remains buyable. A morning budget conservatively allows for
## refilling enabled targets after service; at closing the existing expiry /
## paid-delivery forecast gives the next morning's actual full-order estimate.
func build_restock_estimate() -> int:
	if world == null or content == null:
		return 0
	var kinds: Dictionary[StringName, int] = StorageSpace.kinds_of(content)
	# Paid, not stocked: the same source the real morning order plans with.
	var pending: Dictionary[StringName, int] = _on_the_way()
	if world.clock.phase == SimClock.Phase.CLOSED:
		return int(StockAlerts.forecast(Economy.stock, _reorder(), _shelf_lives(),
			world.clock.day + 1, _unit_costs(), 2147483647, auto_reorder_premium,
			_storage_capacity(), kinds, pending)["order_cost"])
	var empty: Stock = Stock.new()
	var space: StorageSpace = StorageSpace.new(_storage_capacity(), empty, pending, kinds)
	return int(_reorder().plan(empty, _unit_costs(), 2147483647,
		auto_reorder_premium, false, space)["cost"])


func build_restock_warning() -> String:
	if not is_build_active() or not build_mode.current_check.ok:
		return ""
	var cost: int = 0
	if build_mode.state == BuildMode.State.BUY and build_mode.selected_definition != null:
		cost = build_mode.selected_definition.price
	elif build_mode.state == BuildMode.State.BLUEPRINT:
		cost = build_mode.blueprint_cost()
	elif build_mode.state in [BuildMode.State.WALLS, BuildMode.State.FLOOR, BuildMode.State.FLOORS,
			BuildMode.State.WALL_FINISH, BuildMode.State.HANG]:
		# D26: a wall finish drag's price less its refund; a new wall item's
		# price (moving one costs nothing).
		cost = maxi(0, build_mode.current_check.cost - build_mode.current_check.refund)
	if cost <= 0:
		return ""
	return RestockBudgetWarning.text(Economy.cash, cost, build_restock_estimate())


func build_warning() -> String:
	if not is_build_active():
		return ""
	var lines: PackedStringArray = []
	if not build_mode.current_check.menu_warning.is_empty():
		lines.append(build_mode.current_check.menu_warning)
	var budget: String = build_restock_warning()
	if not budget.is_empty():
		lines.append(budget)
	return "\n".join(lines)


func _on_build_toggled() -> void:
	set_build_active(not is_build_active())


func _on_build_buy_requested(def_id: StringName) -> void:
	var definition: ItemDef = content.item(def_id)
	if definition != null and definition.hangs_on_wall():
		begin_hang_item(def_id)
	else:
		begin_buy_item(def_id)


func _on_wall_tool_requested(kind: int) -> void:
	begin_wall_tool(kind as SimGrid.Segment)


func _on_floor_tool_requested() -> void:
	begin_floor_tool()


func _on_rooms_tool_requested(kind: int) -> void:
	begin_rooms_tool(kind)


## Floor looks changed (laid, recoloured, undone): their colours feed the vibe.
func _on_floor_looks_changed(_cells: Array[Vector2i]) -> void:
	_recompute_vibe()


## An empty list is the shop's own wall colour changing (the legacy wall
## paint), which recomputes the vibe itself.
func _on_wall_looks_changed(faces: Array[Vector3i]) -> void:
	if not faces.is_empty():
		_recompute_vibe()


func _on_wall_decor_changed() -> void:
	_recompute_vibe()


func _on_build_cash_changed(_cash: int, _delta: int, _reason: StringName) -> void:
	_refresh_loan_hud()
	if _build_ready and is_build_active():
		build_mode.refresh()
		_update_build_controls()
	if _staff_panel != null:
		_staff_panel.set_trays(tray_level, TUNING.tray_prices, Economy.cash, _loan_upgrade_refusal())
	if is_stock_visible():
		_refresh_stock_panel()
	_refresh_goals()


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
	_refresh_hygiene_overview()
	if _debug_overlay.is_enabled():
		_debug_overlay.refresh()
	var view: ShopView = $ShopView
	view.set_selected_item(_inspect_panel.selected_item_id)
	_refresh_storage_view()
	_debug_geometry.update_geometry(world, view.drawn_agent_positions(), view.drawn_agent_colors(), _inspect_panel.selected_agent_id, _debug_overlay.is_enabled())


func _on_inspection_tick(_tick: int) -> void:
	# Text follows every tick; geometry follows the drawn agents once per frame.
	_refresh_sold_out_hud()
	_inspect_panel.refresh()
	if _debug_overlay.is_enabled():
		_debug_overlay.refresh()
	_refresh_goals()


## Deletes the autosave and restarts the scene from day 1.
func start_over() -> void:
	start_fresh_run(get_tree(), save_slot, use_saves)


## The title's New game and the existing F10 route share replacement semantics.
static func start_fresh_run(tree: SceneTree, slot: String = AUTOSAVE_SLOT, with_saves: bool = true) -> Error:
	if with_saves:
		var error: Error = SaveSystem.delete_slot(slot)
		if error != OK and error != ERR_FILE_NOT_FOUND:
			return error
	return tree.change_scene_to_file("res://src/world/main.tscn")


## Returning discards only unsaved changes; the existing morning save is intact.
func request_quit_to_title() -> void:
	if not _started or display_only:
		return
	if Clock.sim.phase == SimClock.Phase.MORNING:
		_quit_to_title()
	else:
		_quit_title_previous_speed = Clock.speed
		Clock.set_speed(0)
		($Overlay/QuitToTitle as ConfirmationDialog).popup_centered(Vector2i(480, 160))


func _cancel_quit_to_title() -> void:
	Clock.set_speed(_quit_title_previous_speed)


func _quit_to_title() -> void:
	if _settings_panel != null and not _settings_panel.flush_pending_changes():
		return
	Clock.set_speed(0)
	get_tree().change_scene_to_file("res://src/ui/title_screen.tscn")


## Advances the restaurant by `ticks` sim ticks right now (tests and tools).
func run_ticks(ticks: int) -> void:
	for i in ticks:
		if Clock.sim.phase != SimClock.Phase.OPEN and Clock.sim.phase != SimClock.Phase.LAST_ORDERS:
			break
		sim.advance()
		EventBus.sim_ticked.emit(Clock.sim.tick)
	refresh_presentation()


## Paid replacements arrive during the existing overnight tidy.
func _on_plate_broken(cost: int) -> void:
	Economy.add_cash(-cost, Ledger.BREAKAGES, "Replacement plate, delivered tomorrow morning")


## Builds the evening report for `day` from the ledger and today's counters.
func build_report(day: int) -> DayReport:
	var report := DayReport.new()
	report.day = day
	report.restaurant_name = menu_settings.restaurant_name() if menu_settings != null else MenuSettings.DEFAULT_NAME
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
	if sim.mishaps != null:
		report.mishaps_text = MishapText.daily(sim.mishaps.spills_today,
			sim.mishaps.broken_plates_today, sim.mishaps.degreases_today)
	report.record_dish_quality(sim.orders.orders_in_state(Order.State.DELIVERED))
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
		report.owner_tips = _owner_tips_today.duplicate()
		if _milestone_xp_today > 0:
			report.owner_xp_breakdown["milestone_xp"] = _milestone_xp_today
	report.low_stock = StockAlerts.sell_out_lines(sim.stock_outs_today, content)
	var incoming: Dictionary[StringName, int] = deliveries.pending_by_id()
	report.low_stock.append_array(StockAlerts.forecast_lines(StockAlerts.forecast(Economy.stock,
		_reorder(), _shelf_lives(), day + 1, _unit_costs(), Economy.cash, auto_reorder_premium,
		_storage_capacity(), StorageSpace.kinds_of(content), incoming), content))
	if _milestone_award_day == day:
		for goal: Milestone in _milestones_reached_today:
			report.milestones_reached.append({"title": goal.title,
				"reward_xp": goal.reward_xp, "reward_cash": goal.reward_cash})
	return report


func _new_game() -> void:
	_menu_access_losses.clear()
	_menu_access_day = 0
	_menu_access_error = ""
	$HUD.set_menu_notice("")
	blueprint_library = BlueprintLibrary.new()
	_loaded_blueprints = null
	_blueprint_load_notes.clear()
	# A fresh clock and seed too, so a half-loaded save can't leave its day
	# or random state behind.
	Clock.sim = SimClock.new()
	GameState.new_run(new_game_seed_override if new_game_seed_override != 0
		else int(Time.get_unix_time_from_system()))
	Economy.reset(TUNING.starting_cash)
	_loaded_layout = null
	_owner_preferences.reset()
	owner_progress = OwnerProgress.new(PROGRESSION_TUNING)
	milestones = MilestoneTracker.new()
	_loaded_milestones = null
	_milestones_reached_today.clear()
	_milestone_award_day = 0
	_milestone_xp_today = 0
	_dismiss_goals()
	_owner_award_today.clear()
	_owner_unlocks_today.clear()
	_owner_tips_today.clear()
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
	_loaded_reorder = null
	reorder_settings = ReorderSettings.new(TUNING)
	_loaded_deliveries = null
	deliveries = DeliveryBook.new()
	stock_cart.clear()
	_last_delivery.clear()
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
	_loaded_blueprints = null
	_blueprint_load_notes.clear()
	_loaded_layout = null
	_loaded_menu = null
	_loaded_staff = null
	_loaded_plates = null
	_loaded_reputation = null
	_loaded_milestones = null
	_loaded_tray_level = 0
	_loaded_reorder = null
	_loaded_deliveries = null
	if not SaveSystem.list_slots().has(save_slot):
		return false
	if SaveSystem.load_game(save_slot) != OK:
		world.log_event("Autosave could not be loaded; starting a new game")
		return false
	if Clock.sim.phase != SimClock.Phase.MORNING:
		world.log_event("Autosave is not from a morning; starting a new game")
		return false
	if not OpeningHours.clock_valid(Clock.sim, HOURS_TUNING):
		# Keep the game; only the hours go back to the default day.
		OpeningHours.apply(Clock.sim, HOURS_TUNING.default_open_minute, HOURS_TUNING.default_close_minute, HOURS_TUNING)
		world.log_event("Saved opening hours were outside the limits; reset to the default hours")
	if owner_progress.last_awarded_day >= Clock.sim.day:
		world.log_event("Autosave owner progress is ahead of this morning; starting a new game")
		return false
	var career: MilestoneTracker = _loaded_milestones if _loaded_milestones != null else MilestoneTracker.new()
	if career.last_evaluated_day >= Clock.sim.day:
		world.log_event("Autosave career goals are ahead of this morning; starting a new game")
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
	# The saved layout lists every station; drinks at a station staff cannot
	# reach stay off the live menu (and out of the next save), as in play.
	var enabled: Array[RecipeDef] = menu_settings.enabled_recipes()
	var cookable: Array[RecipeDef] = _cookable_live()
	menu_settings.set_catalogue(cookable)
	_track_menu_access_losses(enabled, cookable)
	menu_settings.clear_stash()
	_apply_menu(sim, menu_settings)
	if sim.kitchen == null or not sim.kitchen.configure_plates(
			_loaded_plates.total if _loaded_plates != null else TUNING.starting_plates):
		return false
	_bind_world_presentation()
	if not sim.assign_owner(_owner_preferences.current_mode()):
		return false
	milestones = career
	# Saves from before the Stock panel have no section: today's defaults.
	reorder_settings = _loaded_reorder if _loaded_reorder != null else ReorderSettings.new(TUNING)
	# Saves from before deliveries have nothing on order.
	deliveries = _loaded_deliveries if _loaded_deliveries != null else DeliveryBook.new()
	stock_cart.clear()
	_last_delivery.clear()
	blueprint_library = _loaded_blueprints if _loaded_blueprints != null else BlueprintLibrary.new()
	for note: String in _blueprint_load_notes:
		world.log_event(note)
	if _loaded_layout != null:
		for note: String in _loaded_layout.load_notes:
			world.log_event(note)
	return true


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


func _capture_milestones() -> Dictionary:
	return milestones.to_dict()


## Decode into an isolated candidate. Installation waits for full morning success.
func _restore_milestones(data: Dictionary) -> bool:
	var candidate: MilestoneTracker = MilestoneTracker.new()
	if not candidate.from_dict(data):
		return false
	_loaded_milestones = candidate
	return true


func _capture_reorder() -> Dictionary:
	return reorder_settings.to_dict()


## Stage like the other sections; installed only after a complete morning load.
func _restore_reorder(data: Dictionary) -> bool:
	var candidate: ReorderSettings = ReorderSettings.new(TUNING)
	if not candidate.from_dict(data):
		return false
	_loaded_reorder = candidate
	return true


func _capture_deliveries() -> Dictionary:
	return deliveries.to_dict()


## Staged like the reorder section; installed after a complete morning load.
func _restore_deliveries(data: Dictionary) -> bool:
	var candidate: DeliveryBook = DeliveryBook.new()
	if not candidate.from_dict(data):
		return false
	_loaded_deliveries = candidate
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


func _capture_blueprints() -> Dictionary:
	return blueprint_library.to_dict()


func _restore_blueprints(data: Dictionary) -> bool:
	var restored: BlueprintLibrary = BlueprintLibrary.new()
	var notes: Array[String] = []
	if not restored.restore(data, content, notes):
		return false
	_loaded_blueprints = restored
	_blueprint_load_notes = notes
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
	_refresh_goals()
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
		set_stock_visible(false)
		_dismiss_goals()
		clear_selection()
		_report.hide()
	_staff_panel.set_phase(Clock.sim.phase)
	_staff_panel.set_wage_factor(OpeningHours.wage_factor(Clock.sim, HOURS_TUNING))
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
	var definitions: Array[ItemDef] = []
	for placement: ShopPlacement in layout.placements:
		var definition: ItemDef = content.item(placement.item_id)
		if definition != null:
			definitions.append(definition)
	return _cookable_from(definitions)


## The dishes the live shop's stations can make right now (FK-083).
## A station staff cannot reach (a bar or a fryer walled in on every side)
## does not count, so its dishes never go on sale only to be cancelled.
func _cookable_live() -> Array[RecipeDef]:
	return MenuAccess.cookable(world.grid, content.recipes())


func _station_reachable(placed: PlacedItem) -> bool:
	var entries: Array[Vector2i] = world.grid.entries()
	for cell: Vector2i in placed.work_cells:
		if world.grid.is_walkable(cell) and not world.grid.find_path_to_any(cell, entries).is_empty():
			return true
	return false


func _cookable_from(definitions: Array[ItemDef]) -> Array[RecipeDef]:
	var stations: Dictionary[StringName, bool] = {}
	var fridge: bool = false
	var pass_counter: bool = false
	for definition: ItemDef in definitions:
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


## After a station is bought, sold or undone, the menu offers what the shop
## can now make: buying a coffee machine puts Coffee and Tea on the menu.
func _refresh_menu_catalogue() -> void:
	if menu_settings == null or world == null:
		return
	var cookable: Array[RecipeDef] = _cookable_live()
	if MenuAccess.cookable(world.grid, content.recipes(), menu_settings.owner_level()).is_empty():
		# An older or externally edited layout can already be broken. Explain
		# why it cannot open rather than silently leaving stale dishes on sale.
		_menu_access_error = MenuAccess.NO_DISH
		$HUD.set_menu_notice(_menu_access_error, true)
		return
	_menu_access_error = ""
	_track_menu_access_losses(menu_settings.enabled_recipes(), cookable)
	if menu_settings.set_catalogue(cookable):
		_apply_menu(sim, menu_settings)
		if _menu_panel != null:
			_refresh_menu_details()
		_recompute_vibe()
		_refresh_stock_panel()
	$HUD.set_menu_notice(menu_open_note())


## Load filters the saved choices before normal morning setup. Retain those
## losses for this morning too, without saving a notice or adding a save point.
func _track_menu_access_losses(enabled: Array[RecipeDef], cookable: Array[RecipeDef]) -> void:
	if _menu_access_day != Clock.sim.day:
		_menu_access_losses.clear()
	_menu_access_day = Clock.sim.day
	for id: StringName in _menu_access_losses.keys():
		if cookable.has(_menu_access_losses[id]):
			_menu_access_losses.erase(id)
	for recipe: RecipeDef in enabled:
		if not cookable.has(recipe):
			_menu_access_losses[recipe.id] = recipe


## The Open-shop note survives Build closing but never becomes save data.
func menu_open_note() -> String:
	var recipes: Array[RecipeDef] = []
	for recipe: RecipeDef in _menu_access_losses.values():
		recipes.append(recipe)
	return MenuAccess.warning(recipes, world.grid, content, true) \
		if world != null and world.clock.phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS] else ""


## Station-only ingredients (coffee beans, beer...) are ordered and listed
## only while a dish on the menu uses them; everyday ones always are.
func _reorder() -> ReorderSettings:
	var used: Array[StringName] = []
	if menu_settings != null and menu_settings.is_valid():
		for recipe: RecipeDef in menu_settings.enabled_recipes():
			for ingredient: IngredientDef in recipe.ingredients:
				if ingredient != null and not used.has(ingredient.id):
					used.append(ingredient.id)
	reorder_settings.set_in_use(used)
	return reorder_settings


## The Drinks hints explain what each missing drink needs, by name. Food
## waiting on the same station joins that line ("Coffee, tea and croissant: ...").
## Food-only equipment is shown in the unlock tree and the dish's Equipment slot.
func drink_station_hints() -> Array[String]:
	var hints: Array[String] = []
	if content == null or world == null:
		return hints
	var station_state: Dictionary = _menu_station_state()
	var present: Dictionary[StringName, bool] = station_state["reachable"]
	var walled_in: Dictionary[StringName, bool] = station_state["installed"]
	var needs: Dictionary[StringName, Array] = {}
	var order: Array[StringName] = []
	var drink_stations: Dictionary[StringName, bool] = {}
	# Drinks first, so a shared station's line names them before the food.
	var waiting: Array[RecipeDef] = []
	for drinks_pass: bool in [true, false]:
		for kind: StringName in RecipeDef.ORDER_TYPES:
			for recipe: RecipeDef in content.recipes():
				if recipe.order_type == kind and recipe.is_drink() == drinks_pass and recipe.unlock_tier == 1 \
						and recipe.unlock_level <= owner_progress.level:
					waiting.append(recipe)
	for recipe: RecipeDef in waiting:
		for step: RecipeStep in recipe.steps:
			if present.has(step.station_type):
				continue
			if not needs.has(step.station_type):
				needs[step.station_type] = []
				order.append(step.station_type)
			(needs[step.station_type] as Array).append(recipe.display_name)
			if recipe.is_drink():
				drink_stations[step.station_type] = true
			break
	for station: StringName in order:
		if not drink_stations.has(station):
			continue
		var names: Array[String] = []
		for index: int in range(needs[station].size()):
			var dish: String = needs[station][index]
			names.append(dish if index == 0 else dish.to_lower())
		hints.append("%s: %s." % [StockAlerts.join_names(names),
			_equipment_advice(_station_item_name(station), walled_in.has(station))])
	if menu_settings != null:
		for drink: RecipeDef in menu_settings.crowded_out_drinks():
			hints.append("%s is ready to serve; make room on the menu to add it." % drink.display_name)
	return hints


## One wording for every missing-equipment reason (Drinks hints, tree and
## Equipment slots): "buy a fryer", "buy an oven", "staff can't reach the fryer".
static func _equipment_advice(item_name: String, walled_in: bool) -> String:
	var lower: String = item_name.to_lower()
	if walled_in:
		return "staff can't reach the %s" % lower
	return "buy %s %s" % ["an" if not lower.is_empty() and "aeiou".contains(lower.left(1)) else "a", lower]


## The item a hint names for a station: the one whose id is the station type
## (the prep counter, not the level-4 prep cabinet), else the earliest unlock.
func _station_item_name(station: StringName) -> String:
	var exact: ItemDef = content.item(station)
	if exact != null and exact.category == ItemDef.Category.STATION and exact.station_type == station:
		return exact.display_name
	var best: ItemDef = null
	for definition: ItemDef in content.items():
		if definition.category == ItemDef.Category.STATION and definition.station_type == station \
				and (best == null or definition.unlock_level < best.unlock_level):
			best = definition
	return best.display_name if best != null else String(CatalogueText.STATION_NAMES.get(station, "Equipment"))


## Morning only. Hours join the clock, so the next morning autosave keeps them.
func set_opening_hours(open_minute: int, close_minute: int) -> bool:
	if not _started or Clock.sim.phase != SimClock.Phase.MORNING \
			or not OpeningHours.apply(Clock.sim, open_minute, close_minute, HOURS_TUNING):
		return false
	if _menu_panel != null:
		_menu_panel.set_hours(Clock.sim.display_open_minute, Clock.sim.display_close_minute, HOURS_TUNING)
	$HUD.refresh()
	_staff_panel.set_wage_factor(OpeningHours.wage_factor(Clock.sim, HOURS_TUNING))
	refresh_presentation()
	return true


func _on_hours_requested(open_minute: int, close_minute: int) -> void:
	set_opening_hours(open_minute, close_minute)


func _apply_menu(restaurant: RestaurantSim, choices: MenuSettings) -> void:
	restaurant.menu = choices.enabled_recipes()
	$HUD.set_restaurant_name(choices.restaurant_name())
	($ShopView as ShopView).set_restaurant_name(choices.restaurant_name())
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
	_refresh_menu_details()
	if was_enabled != menu_settings.is_enabled(recipe_id):
		_recompute_vibe()
		_refresh_stock_panel()
	return true


## A morning choice joins the existing menu section at the next morning save.
func menu_set_restaurant_name(value: String) -> bool:
	if not can_edit_menu() or not menu_settings.set_restaurant_name(value):
		return false
	$HUD.set_restaurant_name(menu_settings.restaurant_name())
	($ShopView as ShopView).set_restaurant_name(menu_settings.restaurant_name())
	_refresh_menu_details()
	return true


func _on_restaurant_name_requested(value: String) -> void:
	menu_set_restaurant_name(value)


func menu_set_price(recipe_id: StringName, price: int) -> bool:
	if not can_edit_menu() or menu_settings.recipe(recipe_id) == null:
		return false
	menu_settings.set_price(recipe_id, price)
	_apply_menu(sim, menu_settings)
	_refresh_menu_details()
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
		_dismiss_goals()
		if is_settings_visible():
			_settings_return_to_menu = false
			if not set_settings_visible(false):
				return false
		if _paint_active:
			set_paint_active(false)
		build_mode.exit()
		set_staff_visible(false)
		set_stock_visible(false)
		_refresh_menu_details()
		_menu_panel.set_drink_hints(drink_station_hints())
		_menu_panel.set_hours(Clock.sim.display_open_minute, Clock.sim.display_close_minute, HOURS_TUNING)
	_menu_panel.set_phase(Clock.sim.phase)
	_menu_panel.visible = value
	return true


func is_menu_visible() -> bool:
	return _menu_panel != null and _menu_panel.visible


## A view-only panel: opening it neither completes goals nor changes the clock.
func set_goals_visible(value: bool) -> bool:
	if _goals_panel == null or (value and (not _started or sim == null)):
		return false
	if _goals_panel.visible == value:
		if value:
			_refresh_goals(true)
		return true
	if value:
		if is_settings_visible():
			_settings_return_to_menu = false
			if not set_settings_visible(false):
				return false
		var from_menu: bool = is_menu_visible()
		if _paint_active:
			set_paint_active(false)
		build_mode.exit()
		set_staff_visible(false)
		set_menu_visible(false)
		set_stock_visible(false)
		clear_selection()
		_report.hide()
		_goals_return_to_menu = from_menu
		_goals_panel.show()
		_refresh_goals(true)
	else:
		var return_to_menu: bool = _goals_return_to_menu and can_edit_menu()
		_dismiss_goals()
		if return_to_menu:
			set_menu_visible(true)
		elif Clock.sim.phase == SimClock.Phase.CLOSED and shown_report != null:
			_report.call(&"show_report", build_report(Clock.sim.day))
	return true


func is_goals_visible() -> bool:
	return _goals_panel != null and _goals_panel.visible


func _dismiss_goals() -> void:
	if _goals_panel != null:
		_goals_panel.hide()
	_goals_return_to_menu = false
	_goals_snapshot.clear()


func _on_menu_goals_requested() -> void:
	set_goals_visible(true)


func _on_goals_close_requested() -> void:
	set_goals_visible(false)


func _milestone_observation(operating_profit: int) -> MilestoneDay:
	var observation: MilestoneDay = MilestoneDay.new()
	observation.day = Clock.sim.day
	observation.served_today = sim.served_today
	observation.lost_today = sim.lost_today
	observation.reputation = reputation.average()
	observation.operating_profit = operating_profit
	observation.owner_level = owner_progress.level
	observation.staff_count = staff_roster.members().size()
	return observation


func _refresh_goals(force: bool = false) -> void:
	if not is_goals_visible() or sim == null:
		return
	var observation: MilestoneDay = _milestone_observation(build_report(Clock.sim.day).operating_profit())
	var progress: Dictionary[StringName, float] = milestones.progress_values(milestone_catalogue, observation)
	var completed: Array[StringName] = milestones.completed_ids()
	var snapshot: Dictionary = {"catalogue": milestone_catalogue.get_instance_id() if milestone_catalogue != null else 0,
		"completed": completed, "progress": progress, "level": owner_progress.level}
	if force or snapshot != _goals_snapshot:
		_goals_panel.set_goals(milestone_catalogue, completed, progress, owner_progress.level)
		_goals_snapshot = snapshot.duplicate(true)


func set_settings_visible(value: bool) -> bool:
	if _settings_panel == null:
		return false
	if _settings_panel.visible == value:
		return true
	if value:
		_dismiss_goals()
		_settings_return_to_menu = is_menu_visible()
		_settings_previous_speed = Clock.speed
		Clock.set_speed(0)
		set_menu_visible(false)
		set_staff_visible(false)
		set_stock_visible(false)
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
	# menu_set_enabled refreshes the dish details once when it accepts.
	menu_set_enabled(recipe_id, enabled)
	_menu_panel.set_drink_hints(drink_station_hints())


func _on_menu_price_requested(recipe_id: StringName, price: int) -> void:
	menu_set_price(recipe_id, price)


func shop_move(item_id: int, origin: Vector2i, quarter_turns: int) -> bool:
	var accepted: bool = shop_editor != null and edit_history.move(item_id, origin, quarter_turns)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


## A colour (the eyedropper's copy) is applied as a free repaint with the buy.
func shop_buy(def_id: StringName, origin: Vector2i, quarter_turns: int = 0, swatch_id: StringName = &"") -> bool:
	var accepted: bool = shop_editor != null and edit_history.buy(def_id, origin, quarter_turns, swatch_id)
	if accepted and not swatch_id.is_empty():
		($ShopView as ShopView).set_paint(content, shop_editor.wall_swatch_id, shop_editor.floor_swatch_id)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


func shop_stamp(blueprint: Blueprint, anchor: Vector2i, rotation: int = 0) -> bool:
	var accepted: bool = shop_editor != null and edit_history.stamp(blueprint, anchor, rotation)
	if accepted:
		($ShopView as ShopView).set_paint(content, shop_editor.wall_swatch_id, shop_editor.floor_swatch_id)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


## Wall segment changes (FK-070), checked and booked by ShopEditor.
func shop_walls(changes: Dictionary[Vector3i, int]) -> bool:
	var accepted: bool = shop_editor != null and edit_history.apply_segments(changes)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


## Floor expansion (FK-080), checked and booked by ShopEditor. The camera
## then glides to fit the new outline; nothing is saved until next morning.
func shop_floor(cells: Array[Vector2i], adding: bool) -> bool:
	var accepted: bool = shop_editor != null and edit_history.apply_floor(cells, adding)
	_after_edit(accepted)
	if accepted:
		_frame_shop(false)
	if _build_ready:
		build_mode.refresh()
	return accepted


func _clear_rooms_note() -> void:
	if _rooms_note:
		_rooms_note = false
		$HUD.set_rooms_note("")


## Floor types (D25): lay or recolour floor looks (cell -> Finish), checked
## and booked by ShopEditor, undoable.
func shop_flooring(changes: Dictionary[Vector2i, FloorFinishes.Finish]) -> bool:
	var accepted: bool = shop_editor != null and edit_history.apply_flooring(changes)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


## Wall finishes (D26): put up or recolour wall looks (face -> Finish),
## checked and booked by ShopEditor, undoable.
func shop_wall_finishes(changes: Dictionary[Vector3i, FloorFinishes.Finish]) -> bool:
	var accepted: bool = shop_editor != null and edit_history.apply_wall_finishes(changes)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


## Wall decor (D26): hang, move and sell, checked and booked by ShopEditor.
func shop_hang(def_id: StringName, anchor: Vector3i) -> bool:
	var accepted: bool = shop_editor != null and edit_history.hang(def_id, anchor)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


func shop_rehang(anchor: Vector3i, to_anchor: Vector3i) -> bool:
	var accepted: bool = shop_editor != null and edit_history.rehang(anchor, to_anchor)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


func shop_take_down(anchor: Vector3i) -> int:
	var refund: int = edit_history.take_down(anchor) if shop_editor != null else -1
	_after_edit(refund >= 0)
	if _build_ready:
		build_mode.refresh()
	return refund


## Room painting (FK-101): free, checked by ShopEditor, undoable.
func shop_rooms(changes: Dictionary[Vector2i, int]) -> bool:
	var accepted: bool = shop_editor != null and edit_history.apply_rooms(changes)
	_after_edit(accepted)
	if _build_ready:
		build_mode.refresh()
	return accepted


## A new edit replaces any old undo notice.
func _after_edit(accepted: bool) -> void:
	if accepted:
		_edit_notice = ""
		_refresh_menu_catalogue()


## Undoes the newest edit of this session (Ctrl+Z or the Undo button). A held
## ghost is dropped first. A refusal is shown and the history is kept.
func undo_edit() -> bool:
	return _step_history(true)


func redo_edit() -> bool:
	return _step_history(false)


func _step_history(undoing: bool) -> bool:
	if not _build_ready or shop_editor == null or (not is_build_active() and not _paint_active):
		return false
	if is_build_active():
		build_mode.cancel_ghost()
	var label: String = edit_history.undo_label() if undoing else edit_history.redo_label()
	var floor_before: int = shop_editor.bought_floor().size()
	var accepted: bool = edit_history.undo() if undoing else edit_history.redo()
	if accepted:
		_edit_notice = ("Undid " if undoing else "Redid ") + label
		($ShopView as ShopView).set_paint(content, shop_editor.wall_swatch_id, shop_editor.floor_swatch_id)
		_refresh_menu_catalogue()
		_recompute_vibe()
		if shop_editor.bought_floor().size() != floor_before:
			_frame_shop(false)
	else:
		_edit_notice = ("Can't undo: " if undoing else "Can't redo: ") + edit_history.last_refusal \
			if not label.is_empty() else edit_history.last_refusal
	if _build_ready:
		build_mode.refresh()
		# The hovered item may be gone or back under a new id: look again.
		build_mode.hover_item(-1)
		if is_build_active() and is_inside_tree():
			update_build_pointer(get_viewport().get_mouse_position())
	_update_build_controls()
	return accepted


func _on_catalogue_mode_requested(mode: StringName) -> void:
	if _paint_active:
		set_paint_active(false)
	if not is_build_active():
		set_build_active(true)
	if not is_build_active():
		return
	# Switching side drops a held piece or tool that belongs to the other side.
	var buying: bool = mode == BuildCatalogue.BUY
	var state: BuildMode.State = build_mode.state
	if (buying and (state == BuildMode.State.WALLS or state == BuildMode.State.FLOOR or state == BuildMode.State.ROOMS
			or state == BuildMode.State.FLOORS or state == BuildMode.State.WALL_FINISH)) \
			or (not buying and (state == BuildMode.State.BUY or state == BuildMode.State.MOVE or state == BuildMode.State.HANG)):
		build_mode.cancel_ghost()
	_build_catalogue.set_mode(mode)


func _on_catalogue_paint_requested() -> void:
	var from_build: bool = is_build_active()
	if set_paint_active(true):
		_paint_from_build = from_build


func _on_catalogue_tool_requested(tool: int) -> void:
	if is_build_active():
		_edit_notice = ""
		build_mode.set_tool(tool as BuildMode.Tool)


## The eyedropper opens the copied item's room in Buy mode.
func _set_catalogue_room_for(item: PlacedItem) -> void:
	var definition: ItemDef = item.def as ItemDef if item != null else null
	if _build_catalogue != null and definition != null:
		_build_catalogue.set_category(BuildCatalogue.category_for(definition))


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
	var refund: int = edit_history.sell(item_id) if shop_editor != null else -1
	_after_edit(refund >= 0)
	if _build_ready:
		build_mode.refresh()
	return refund


## Morning setup: new counters, a stocked fridge, and an autosave.
func _begin_morning() -> void:
	if _menu_access_day != Clock.sim.day:
		_menu_access_losses.clear()
	_menu_access_day = Clock.sim.day
	_menu_access_error = ""
	$HUD.set_menu_notice("")
	# The preceding close may unlock a new type; current guests are unaffected.
	sim.set_customer_level(owner_progress.level)
	_dismiss_goals()
	_milestones_reached_today.clear()
	_milestone_award_day = 0
	_milestone_xp_today = 0
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
	_owner_tips_today.clear()
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
	_sold_out_shown = -1
	_refresh_sold_out_hud()
	_expire_stock()
	_restock()
	Economy.ledger.prune_before(Clock.sim.day - Ledger.HISTORY_DAYS)
	_report.hide()
	if use_saves and not _skip_next_autosave:
		SaveSystem.save_game(save_slot)
	_skip_next_autosave = false
	_refresh_loan_hud()
	$HUD.set_owner_progress(owner_progress.level, owner_progress.xp_into_level(), owner_progress.xp_in_level())
	# The morning report of an auto-order that did not fit is the Stock panel.
	if not (_morning_order.get("unfit", {}) as Dictionary).is_empty():
		set_stock_visible(true)
	# A new raise or departure must be visible without making the player find
	# the Staff button. Ordinary mornings still leave the panel closed.
	if not _staff_notices.is_empty() \
			or not staff_roster.morning_raise_offers(Clock.sim.day, Clock.sim.phase).is_empty():
		set_staff_visible(true)
	# A legacy layout may already have every cooking station blocked. The
	# normal editor prevents new empty catalogues; opening still explains old ones.
	_refresh_menu_catalogue()
	_refresh_stock_panel()
	refresh_presentation()


func _shelf_lives() -> Dictionary:
	var lives: Dictionary = {}
	for ingredient: IngredientDef in content.ingredients():
		lives[ingredient.id] = ingredient.shelf_life_days
		# The freezer keeps food much longer (FK-087).
		if ingredient.storage == IngredientDef.Storage.FREEZER:
			lives[ingredient.id] = maxi(ingredient.shelf_life_days, TUNING.freezer_shelf_life_days)
	return lives


func _unit_costs() -> Dictionary:
	var costs: Dictionary = {}
	for ingredient: IngredientDef in content.ingredients():
		costs[ingredient.id] = ingredient.unit_cost
	return costs


## Ingredients past their shelf life go before the fridge is topped up. A
## reloaded morning finds nothing more to remove, so this never repeats.
func _expire_stock() -> void:
	_expired_this_morning = Economy.stock.expire(Clock.sim.day, _shelf_lives())
	for id: StringName in _expired_this_morning:
		world.log_event("Threw out %d %s past its shelf life" % [_expired_this_morning[id], id])


## Storage units per kind: the layout's pantry plus placed storage (FK-087).
func _storage_capacity() -> Dictionary[int, int]:
	var pantry: int = shop_editor.pantry_units if shop_editor != null else LAYOUT.pantry_units
	return StorageSpace.capacities(world.grid if world != null else null, pantry)


## What the shop's storage holds and has on order, right now.
func storage_space() -> StorageSpace:
	return StorageSpace.new(_storage_capacity(), Economy.stock, _on_the_way(),
		StorageSpace.kinds_of(content))


## Units each kind must keep room for; Build refuses to sell storage below it.
func _storage_need() -> Dictionary:
	var space: StorageSpace = storage_space()
	var need: Dictionary = {}
	for kind: int in StorageSpace.KINDS:
		need[kind] = space.committed(kind)
	return need


## The morning delivery (FK-087): orders placed after yesterday's last
## daytime delivery arrive first, then the standing order. The standing order
## is the auto-reorder: enabled ingredients are topped up to their targets in
## one order priced at list total plus the premium. It buys no more than the
## free storage space, and with short cash what fits in the fixed order; it
## never borrows. Like every morning order it arrives at once, as before.
func _restock() -> void:
	_last_delivery.clear()
	_deliver_due(true)
	var order: Dictionary = _reorder().plan(Economy.stock, _unit_costs(), Economy.cash,
		auto_reorder_premium, false, storage_space())
	_morning_order = {"short": order["short"], "unfit": order["unfit"]}
	_buy_standing(order, "The morning auto-order could not be paid")
	var short: Dictionary = order["short"]
	for id: StringName in short:
		world.log_event("Couldn't afford %d %s this morning" % [short[id], id])
	var unfit: Dictionary = order["unfit"]
	for id: StringName in unfit:
		world.log_event("No storage space for %d %s this morning" % [unfit[id], id])
	_trim_cart()


## A standing order (the morning auto-order, or #183's opening top-up) is
## paid with its premium and stocked at once.
func _buy_standing(order: Dictionary, failure: String) -> void:
	var lines: Array[Dictionary] = []
	lines.assign(order["lines"])
	if not lines.is_empty() and not Economy.buy_auto_order(lines, int(order["cost"])):
		world.log_event(failure)


## A cart left from yesterday may no longer fit after the morning delivery:
## it is cut to the free space (in panel order) and the Stock notes say so.
func _trim_cart() -> void:
	_cart_trimmed.clear()
	if stock_cart.is_empty():
		return
	var space: StorageSpace = storage_space()
	for id: StringName in _cart_order():
		var kind: int = space.kind_of(id)
		var keep: int = mini(int(stock_cart[id]), space.free_units(kind))
		if keep < int(stock_cart[id]):
			_cart_trimmed[id] = int(stock_cart[id]) - keep
		space.reserve(id, keep)
		if keep <= 0:
			stock_cart.erase(id)
		else:
			stock_cart[id] = keep


## Unloads every order due now into the stock. Dishes that sold out come
## back once the delivery covers them. `morning_setup` only for the morning.
func _deliver_due(morning_setup: bool = false) -> bool:
	if deliveries.is_empty() or Clock.sim == null:
		return false
	var lines: Array[Dictionary] = deliveries.take_due(Clock.sim, morning_setup)
	if lines.is_empty():
		return false
	# During service a delivery person brings it in through the back door and
	# staff put the crates away (FK-099): goods become stock as they are put
	# away. Morning orders, and anything landing once closed, arrive at once.
	var visible: bool = not morning_setup and sim != null and sim.dock != null and sim.dock.arrive(lines)
	if not visible:
		Economy.receive(lines)
	if not morning_setup:
		_last_delivery = {"lines": lines, "minute": Clock.sim.display_minutes()}
	if not visible and sim != null and sim.restock_sold_out() > 0:
		_refresh_sold_out_hud()
	var parts: Array[String] = []
	for line: Dictionary in lines:
		parts.append("%d %s" % [int(line["qty"]), line["id"]])
	world.log_event("Delivery arrived: %s" % ", ".join(parts))
	_refresh_stock_panel()
	return true


## Goods a delivery person brought were put away (or stored at closing).
func _on_dock_stored(_lines: Array[Dictionary]) -> void:
	_refresh_sold_out_hud()
	_refresh_stock_panel()
	_refresh_storage_view()


## Paid and not in stock yet: orders on their way plus crates waiting to be
## put away. Both hold their storage space.
func _on_the_way() -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = deliveries.pending_by_id()
	if sim != null and sim.dock != null:
		var waiting: Dictionary[StringName, int] = sim.dock.pending_by_id()
		for id: StringName in waiting:
			out[id] = int(out.get(id, 0)) + waiting[id]
	return out


func _on_delivery_tick(_tick: int) -> void:
	if Clock.sim == null or Clock.sim.phase != SimClock.Phase.OPEN:
		return
	if not deliveries.is_empty():
		var due: Vector2i = deliveries.earliest_due()
		if due.x < Clock.sim.day or (due.x == Clock.sim.day and due.y >= 0 and due.y <= Clock.sim.phase_tick):
			_deliver_due()
	# The countdown bar follows the clock while the panel is open.
	if is_stock_visible() and Clock.sim.phase_tick % maxi(1, HOURS_TUNING.ticks_per_minute) == 0:
		_refresh_stock_panel()


## The panel opens in every phase; orders are paid now and delivered later.
func can_edit_stock() -> bool:
	return _started and sim != null and reorder_settings != null


## Sets one cart amount (0..99 units). Refused when it would not fit in
## storage. Nothing is paid until the order is placed.
func stock_cart_set(id: StringName, qty: int) -> bool:
	if not can_edit_stock() or content.ingredient(id) == null or qty < 0 or qty > ReorderSettings.MAX_TARGET:
		return false
	var trial: Dictionary[StringName, int] = stock_cart.duplicate()
	if qty == 0:
		trial.erase(id)
	else:
		trial[id] = qty
	# Only the added ingredient's own kind must fit: a cart left over in
	# another kind never blocks it.
	if qty > int(stock_cart.get(id, 0)):
		var space: StorageSpace = storage_space()
		var kind: int = space.kind_of(id)
		var same_kind: int = 0
		for other: StringName in trial:
			if space.kind_of(other) == kind:
				same_kind += int(trial[other])
		if same_kind > space.free_units(kind):
			return false
	stock_cart = trial
	_cart_trimmed.clear()
	_refresh_stock_panel()
	return true


func stock_cart_total() -> int:
	var total: int = 0
	for id: StringName in stock_cart:
		var ingredient: IngredientDef = content.ingredient(id)
		if ingredient != null:
			total += ingredient.unit_cost * int(stock_cart[id])
	return total


## Why the cart cannot be ordered now, as a player sentence, or "".
func stock_cart_refusal() -> String:
	if stock_cart.is_empty():
		return "Choose some ingredients first"
	var kind: int = storage_space().first_overflow(stock_cart)
	if kind >= 0:
		return StorageSpace.refusal(kind)
	if not Economy.can_spend_without_loan(stock_cart_total()):
		return "Not enough cash"
	if stock_cart.size() > DeliveryBook.MAX_LINES:
		return "Too many different ingredients in one order"
	if Clock.sim.phase != SimClock.Phase.MORNING and deliveries.size() >= DeliveryBook.MAX_ORDERS:
		return "Too many orders on the way: wait for a delivery"
	return ""


## Pays for the cart at list price. In the morning it arrives at once (as
## #156's buys did); otherwise it goes on the next delivery.
func stock_place_order() -> bool:
	if not can_edit_stock() or not stock_cart_refusal().is_empty():
		return false
	var lines: Array[Dictionary] = []
	for id: StringName in _cart_order():
		var ingredient: IngredientDef = content.ingredient(id)
		lines.append({"id": id, "qty": int(stock_cart[id]), "unit_cost": ingredient.unit_cost})
	var cost: int = stock_cart_total()
	if not Economy.pay_order(lines, cost, false):
		return false
	if Clock.sim.phase == SimClock.Phase.MORNING:
		Economy.receive(lines)
	elif not deliveries.place(lines, cost, false, DeliveryBook.next_due(Clock.sim, delivery_tuning)):
		Economy.refund_order(cost)
		return false
	stock_cart.clear()
	_refresh_stock_panel()
	return true


## Cancels every hand order still on its way for a full refund (standing
## orders arrive at once in the morning, so they never wait to be cancelled).
## Returns the refund, or -1 when nothing is on order.
func stock_cancel_orders() -> int:
	if not can_edit_stock() or deliveries.is_empty():
		return -1
	var refund: int = deliveries.cancel_all()
	Economy.refund_order(refund)
	_refresh_stock_panel()
	return refund


## Throws away all stock of one ingredient (a shop changing concept). No
## refund: like stock that goes off, it simply leaves the stock and the Stock
## notes list it. Returns the units thrown out, or -1 when there were none.
func stock_throw_out(id: StringName) -> int:
	if not can_edit_stock() or content.ingredient(id) == null:
		return -1
	var units: int = Economy.stock.count(id)
	if units <= 0 or not Economy.stock.take(id, units):
		return -1
	if _thrown_day != Clock.sim.day:
		_thrown_day = Clock.sim.day
		_thrown_today.clear()
	_thrown_today[id] = int(_thrown_today.get(id, 0)) + units
	world.log_event("Threw out %d %s by hand" % [units, id])
	_refresh_stock_panel()
	return units


func stock_clear_cart() -> void:
	_cart_trimmed.clear()
	stock_cart.clear()
	_refresh_stock_panel()


## Cart ids in the panel's order (fridge, freezer, dry; fixed order inside).
func _cart_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Dictionary in stock_rows():
		if stock_cart.has(row["id"]):
			out.append(row["id"])
	for id: StringName in stock_cart:
		if not out.has(id):
			out.append(id)
	return out


func stock_set_auto(id: StringName, enabled: bool) -> bool:
	if not can_edit_stock() or not reorder_settings.set_enabled(id, enabled):
		return false
	_refresh_stock_panel()
	return true


func stock_set_target(id: StringName, target: int) -> bool:
	if not can_edit_stock() or not reorder_settings.set_target(id, target):
		return false
	_refresh_stock_panel()
	return true


func toggle_stock() -> void:
	set_stock_visible(not is_stock_visible())


## Idempotent production path for the HUD and real captures, in any phase.
func set_stock_visible(value: bool) -> bool:
	if _stock_panel == null or (value and not can_edit_stock()):
		return false
	if value and not _stock_panel.visible:
		_dismiss_goals()
		if is_settings_visible():
			_settings_return_to_menu = false
			if not set_settings_visible(false):
				return false
		if _paint_active:
			set_paint_active(false)
		build_mode.exit()
		set_menu_visible(false)
		set_staff_visible(false)
		clear_selection()
		_report.hide()
	_stock_panel.visible = value
	if value:
		_refresh_stock_panel()
	elif Clock.sim.phase == SimClock.Phase.CLOSED and shown_report != null:
		# Back to the evening report, rebuilt so closed-phase orders show.
		_report.call(&"show_report", build_report(Clock.sim.day))
	return true


func is_stock_visible() -> bool:
	return _stock_panel != null and _stock_panel.visible


## Ingredients a dish on today's menu uses.
func _menu_ingredients() -> Dictionary[StringName, bool]:
	var used: Dictionary[StringName, bool] = {}
	if menu_settings != null and menu_settings.is_valid():
		for recipe: RecipeDef in menu_settings.enabled_recipes():
			for ingredient: IngredientDef in recipe.ingredients:
				if ingredient != null:
					used[ingredient.id] = true
	return used


## Ingredients some dish or drink in the game uses (frozen fries: none yet).
func _dish_ingredients() -> Dictionary[StringName, bool]:
	var used: Dictionary[StringName, bool] = {}
	for recipe: RecipeDef in content.recipes():
		for ingredient: IngredientDef in recipe.ingredients:
			if ingredient != null:
				used[ingredient.id] = true
	return used


## Rows hold display names only; the panel never sees a raw id as text.
## Grouped by storage kind (fridge, freezer, dry); inside a group the
## ingredients today's menu uses come first, in the fixed buying order.
## Ingredients nothing on the menu uses are listed too (in_use false).
func stock_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if content == null or reorder_settings == null:
		return rows
	_reorder()
	var expiring: Dictionary = Economy.stock.expiring_on(Clock.sim.day + 1, _shelf_lives())
	var used: Dictionary[StringName, bool] = _menu_ingredients()
	var in_dishes: Dictionary[StringName, bool] = _dish_ingredients()
	var pending: Dictionary[StringName, int] = _on_the_way()
	var space: StorageSpace = storage_space()
	for kind: int in StorageSpace.KINDS:
		# The freezer is listed once the shop has one (or anything frozen).
		if kind == StorageSpace.FREEZER and space.capacity(kind) <= 0 and space.committed(kind) <= 0:
			continue
		for in_use: bool in [true, false]:
			for id: StringName in reorder_settings.all_ids():
				var ingredient: IngredientDef = content.ingredient(id)
				if ingredient == null or int(ingredient.storage) != kind or used.has(id) != in_use:
					continue
				rows.append({"id": id, "name": ingredient.display_name, "count": Economy.stock.count(id),
					"expiring": int(expiring.get(id, 0)), "unit_cost": ingredient.unit_cost,
					"enabled": reorder_settings.is_enabled(id), "target": reorder_settings.target(id),
					"max_target": ReorderSettings.MAX_TARGET, "kind": kind, "in_use": in_use,
					"cart": int(stock_cart.get(id, 0)), "on_order": int(pending.get(id, 0)),
					"no_dish": not in_dishes.has(id)})
	return rows


## One entry per storage kind the shop has room for or stocks:
## {kind, label, in_stock, on_order, capacity, cart}.
func stock_groups() -> Array[Dictionary]:
	var space: StorageSpace = storage_space()
	var cart: Dictionary[int, int] = {}
	for id: StringName in stock_cart:
		var kind: int = space.kind_of(id)
		cart[kind] = int(cart.get(kind, 0)) + int(stock_cart[id])
	var listed: Dictionary[int, bool] = {}
	for row: Dictionary in stock_rows():
		listed[int(row["kind"])] = true
	var groups: Array[Dictionary] = []
	for kind: int in StorageSpace.KINDS:
		if space.capacity(kind) <= 0 and not listed.has(kind) and space.committed(kind) <= 0:
			continue
		groups.append({"kind": kind, "label": StorageSpace.label(kind), "in_stock": space.in_stock(kind),
			"on_order": space.on_order(kind), "capacity": space.capacity(kind), "cart": int(cart.get(kind, 0))})
	return groups


## The Next delivery bar: {text, fraction}.
func delivery_countdown() -> Dictionary:
	var info: Dictionary = DeliveryBook.countdown(Clock.sim, delivery_tuning)
	var text: String = "Next delivery: tomorrow morning"
	match info["when"]:
		&"now":
			text = "Morning orders arrive at once" + (
				". Next delivery at %s" % Fmt.clock(int(info["minute"])) if int(info["minute"]) >= 0 else "")
		&"today":
			text = "Next delivery at %s" % Fmt.clock(int(info["minute"]))
	return {"text": text, "fraction": float(info["fraction"])}


## What is on order, as one player sentence, or "".
func stock_pending_text() -> String:
	if deliveries.is_empty():
		return ""
	var parts: Array[String] = []
	var pending: Dictionary[StringName, int] = deliveries.pending_by_id()
	for id: StringName in pending:
		parts.append("%d %s" % [pending[id], _ingredient_name(id)])
	return "On order (paid %s): %s. %s." % [Fmt.money(deliveries.paid_total()), StockAlerts.join_names(parts),
		_due_text(deliveries.earliest_due())]


func _due_text(due: Vector2i) -> String:
	if due.x > Clock.sim.day or due.y == DeliveryBook.MORNING:
		return "It arrives tomorrow morning"
	if due.y <= 0:
		return "It arrives when you open"
	return "It arrives at %s" % Fmt.clock(DeliveryBook.minute_of(Clock.sim, due.y))


## Player sentences about this morning's automatic order and expiry.
func stock_notes() -> Array[String]:
	var notes: Array[String] = []
	# Read back from today's ledger, so a reloaded morning still shows it.
	var list_total: int = 0
	var premium: int = 0
	for entry: Dictionary in Economy.ledger.entries_for_day(Clock.sim.day):
		if entry["category"] != Ledger.INGREDIENTS:
			continue
		var note: String = String(entry["note"])
		if note == Economy.AUTO_PREMIUM_NOTE:
			premium -= int(entry["amount"])
		elif note.begins_with(Economy.AUTO_LINE_PREFIX):
			list_total -= int(entry["amount"])
	if list_total + premium > 0:
		notes.append(("This morning's auto-order cost %s (%s at list price + %s premium)." % [
			Fmt.money(list_total + premium), Fmt.money(list_total), Fmt.money(premium)]) if premium > 0
			else "This morning's auto-order cost %s." % Fmt.money(list_total))
	var space: StorageSpace = storage_space()
	for when: String in ["unfit", "opening_unfit"]:
		var unfit: Dictionary = _morning_order.get(when, {})
		for kind: int in StorageSpace.KINDS:
			var names: Array[String] = []
			for id: StringName in unfit:
				if space.kind_of(id) == kind:
					names.append("%d %s" % [int(unfit[id]), _ingredient_name(id)])
			if not names.is_empty():
				notes.append("%s for %s %s." % [StorageSpace.refusal(kind), StockAlerts.join_names(names),
					"this morning" if when == "unfit" else "at opening"])
	if not _last_delivery.is_empty():
		var brought: Array[String] = []
		for line: Dictionary in _last_delivery["lines"]:
			brought.append("%d %s" % [int(line["qty"]), _ingredient_name(line["id"])])
		notes.append("The %s delivery brought %s." % [Fmt.clock(int(_last_delivery["minute"])),
			StockAlerts.join_names(brought)])
	if sim != null and sim.dock != null:
		var waiting: Dictionary[StringName, int] = sim.dock.pending_by_id()
		var crates: Array[String] = []
		for id: StringName in waiting:
			crates.append("%d %s" % [waiting[id], _ingredient_name(id)])
		if not crates.is_empty():
			notes.append("Still to be put away: %s." % StockAlerts.join_names(crates))
	var short: Dictionary = _morning_order.get("short", {})
	var missed: Array[String] = []
	for id: StringName in short:
		missed.append("%d %s" % [int(short[id]), _ingredient_name(id)])
	if not missed.is_empty():
		notes.append("Not enough cash to auto-order %s." % StockAlerts.join_names(missed))
	var thrown: Array[String] = []
	for id: StringName in _expired_this_morning:
		thrown.append("%d %s" % [int(_expired_this_morning[id]), _ingredient_name(id)])
	if not thrown.is_empty():
		notes.append("Thrown out this morning (too old): %s." % StockAlerts.join_names(thrown))
	var by_hand: Array[String] = []
	if _thrown_day == Clock.sim.day:
		for id: StringName in _thrown_today:
			by_hand.append("%d %s" % [int(_thrown_today[id]), _ingredient_name(id)])
	if not by_hand.is_empty():
		notes.append("Thrown out today (no refund): %s." % StockAlerts.join_names(by_hand))
	var trimmed: Array[String] = []
	for id: StringName in _cart_trimmed:
		trimmed.append("%d %s" % [int(_cart_trimmed[id]), _ingredient_name(id)])
	if not trimmed.is_empty():
		notes.append("Your cart no longer fit your storage and was cut by %s." % StockAlerts.join_names(trimmed))
	for kind: int in StorageSpace.KINDS:
		if space.is_over(kind):
			notes.append("The %s is over its space: nothing more of it can be ordered until some is used." % (
				"dry storage" if kind == StorageSpace.DRY else StorageSpace.label(kind).to_lower()))
	return notes


func _ingredient_name(id: StringName) -> String:
	var ingredient: IngredientDef = content.ingredient(id) if content != null else null
	return ingredient.display_name if ingredient != null else "ingredient"


func _refresh_stock_panel() -> void:
	if _stock_panel == null or Clock.sim == null or content == null or world == null:
		return
	_stock_panel.set_view({"rows": stock_rows(), "groups": stock_groups(), "cash": Economy.cash,
		"editable": can_edit_stock(), "notes": stock_notes(), "premium": auto_reorder_premium,
		"cart_total": stock_cart_total(), "cart_refusal": stock_cart_refusal(),
		"pending": stock_pending_text(), "refund": deliveries.paid_total(),
		"delivery": delivery_countdown()})


## Shelves show crates in proportion to how full their kind is (view only).
func _refresh_storage_view() -> void:
	if world == null or content == null or shop_editor == null:
		return
	var space: StorageSpace = storage_space()
	var fill: Dictionary[int, float] = {}
	var key: String = ""
	for kind: int in StorageSpace.KINDS:
		fill[kind] = space.fill(kind)
		key += "%d:%d/%d;" % [kind, space.in_stock(kind), space.capacity(kind)]
	key += str(world.grid.items().size())
	if key == _storage_fill_key:
		return
	_storage_fill_key = key
	($ShopView as ShopView).set_storage_fill(fill)


func _refresh_sold_out_hud() -> void:
	if sim == null or sim.sold_out_today.size() == _sold_out_shown:
		return
	_sold_out_shown = sim.sold_out_today.size()
	var names: Array[String] = []
	for recipe: RecipeDef in sim.menu:
		if recipe != null and sim.is_sold_out(recipe.id):
			names.append(recipe.display_name)
	$HUD.set_sold_out(names)


func _on_stock_cart_requested(id: StringName, qty: int) -> void:
	stock_cart_set(id, qty)
	_refresh_stock_panel()


func _on_stock_order_requested() -> void:
	stock_place_order()
	_refresh_stock_panel()


func _on_stock_clear_requested() -> void:
	stock_clear_cart()


func _on_stock_throw_requested(id: StringName) -> void:
	stock_throw_out(id)
	_refresh_stock_panel()


func _on_stock_cancel_requested() -> void:
	stock_cancel_orders()
	_refresh_stock_panel()


func _on_stock_auto_requested(id: StringName, enabled: bool) -> void:
	stock_set_auto(id, enabled)
	_refresh_stock_panel()


func _on_stock_target_requested(id: StringName, target: int) -> void:
	stock_set_target(id, target)
	_refresh_stock_panel()


func _on_stock_close_requested() -> void:
	set_stock_visible(false)


## At opening, every station-only ingredient a dish on today's menu uses is
## topped up to its target, like the morning order (so supplies for a coffee
## machine bought this morning arrive before service), within the free
## storage space. Edits and undo never buy stock, so undo stays exact.
## Nothing station-only is in use on a default menu, so default play buys
## nothing here. Like #183's top-up it arrives at once.
func _restock_station_supplies() -> void:
	var order: Dictionary = _reorder().plan(Economy.stock, _unit_costs(), Economy.cash,
		auto_reorder_premium, true, storage_space())
	_buy_standing(order, "The opening top-up could not be paid")
	var short: Dictionary = order["short"]
	for id: StringName in short:
		world.log_event("Couldn't afford %d %s at opening" % [short[id], id])
	var unfit: Dictionary = order["unfit"]
	_morning_order["opening_unfit"] = unfit
	for id: StringName in unfit:
		world.log_event("No storage space for %d %s at opening" % [unfit[id], id])


func _charge_closing_costs() -> void:
	for agent: SimAgent in world.agents:
		if agent is StaffAgent and not agent is OwnerAgent:
			# Paid by the hour: the default day keeps the exact daily wage.
			Economy.add_cash(-OpeningHours.wage_for_day((agent as StaffAgent).wage, Clock.sim, HOURS_TUNING), Ledger.WAGES)
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
	_refresh_goals()


## Service is over and every guest's departure is recorded: close the books.
func _on_service_closed(day: int) -> void:
	if day != Clock.sim.day or _closed_report_day == day:
		return
	_closed_report_day = day
	_remember_menu_quality()
	_charge_closing_costs()
	# Capture business profit before milestone cash or financing enters the books.
	var operating_profit: int = Economy.ledger.day_profit(day)
	staff_roster.close_growth_day()
	var five_star_reviews: int = 0
	for row: Dictionary in sim.reviews_today:
		if int(row.get("stars", 0)) == 5:
			five_star_reviews += 1
	var level_before: int = owner_progress.level
	_owner_award_today = owner_progress.award_day(day,
		int(sim.leave_reasons_today.get(&"happy", 0)), operating_profit, five_star_reviews)
	if not _owner_award_today.is_empty():
		_owner_award_day = day
	# The goal snapshot sees ordinary day XP, but not its own rewards. Stage
	# every goal/bonus before installing any milestone completion or paying cash.
	_award_milestones(day, operating_profit)
	# Earned bonus cash is available to avoid needless borrowing, while the
	# repayment share still uses the captured pre-bonus business profit.
	var settlement: Dictionary = Economy.settle_loan_day(day, operating_profit)
	if settlement.get("first_advance", false):
		_loan_notice_day = day
	if _owner_award_day == day:
		_owner_unlocks_today = _unlocked_at_levels(level_before, owner_progress.level)
		_owner_tips_today = customer_type_catalogue.level_up_tips(level_before, owner_progress.level) \
			if customer_type_catalogue != null else [] as Array[String]
		menu_settings.set_owner_level(owner_progress.level)
		sim.set_customer_level(owner_progress.level)
		shop_editor.set_owner_level(owner_progress.level)
		_build_catalogue.set_owner_level(owner_progress.level)
		$HUD.set_owner_progress(owner_progress.level, owner_progress.xp_into_level(), owner_progress.xp_in_level())
	shown_report = build_report(day)
	_report.call(&"show_report", shown_report)
	if _paint_active or is_staff_visible() or is_goals_visible():
		_report.hide()
	if is_staff_visible():
		_staff_panel.refresh()
	_refresh_goals()


func _award_milestones(day: int, operating_profit: int) -> void:
	var staged: MilestoneSettlement = MilestoneSettlement.prepare(milestones,
		milestone_catalogue, _milestone_observation(operating_profit), owner_progress, Economy.cash)
	if staged == null:
		world.log_event("Career goal rewards could not be applied today")
		return
	# Keep the live progress model stable for existing session consumers. The
	# detached batch is already validated; refuse installation before any goal
	# completion or payment if its owner snapshot cannot be applied.
	if not owner_progress.from_dict(staged.owner_progress.to_dict()):
		world.log_event("Career goal rewards could not be applied today")
		return
	milestones = staged.tracker
	_milestones_reached_today.assign(staged.reached)
	_milestone_award_day = day
	_milestone_xp_today = staged.xp_reward
	if staged.xp_reward > 0:
		if _owner_award_today.is_empty():
			_owner_award_today = {"happy_xp": 0, "profit_xp": 0, "review_xp": 0,
				"total_xp": 0, "level_before": int(staged.owner_xp_result["level_before"])}
		_owner_award_today["total_xp"] = int(_owner_award_today["total_xp"]) + staged.xp_reward
		_owner_award_today["level_after"] = owner_progress.level
		_owner_award_day = day
	if staged.cash_reward > 0:
		Economy.add_cash(staged.cash_reward, Ledger.MILESTONE_BONUS)


## Only authored display names enter the public level-up banner.
func _unlocked_at_levels(previous_level: int, current_level: int) -> Array[String]:
	var unlocked: Array[String] = []
	for recipe: RecipeDef in content.recipes():
		if recipe.unlock_tier == 1 and recipe.unlock_level > previous_level and recipe.unlock_level <= current_level:
			unlocked.append(recipe.display_name + " recipe")
	for item: ItemDef in content.items():
		if item.catalogue_visible and item.unlock_level > previous_level and item.unlock_level <= current_level:
			unlocked.append(item.display_name)
	for style: FloorStyleDef in content.floor_styles():
		if style.unlock_tier == 1 and style.unlock_level > previous_level and style.unlock_level <= current_level:
			unlocked.append(style.display_name + " floor")
	for wall_style: WallStyleDef in content.wall_styles():
		if wall_style.unlock_tier == 1 and wall_style.unlock_level > previous_level and wall_style.unlock_level <= current_level:
			unlocked.append(wall_style.display_name + " walls")
	unlocked.sort()
	return unlocked


func _on_day_phase_changed(_day: int, phase: int) -> void:
	_dismiss_goals()
	_clear_rooms_note()
	# Undo never reaches back across opening (or into a new morning).
	edit_history.clear()
	if menu_settings != null:
		menu_settings.clear_stash()
	_edit_notice = ""
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
	# The evening report takes the screen at closing; Stock stays open otherwise.
	if phase == SimClock.Phase.CLOSED:
		set_stock_visible(false)
	if phase == SimClock.Phase.MORNING:
		_begin_morning()
	elif phase == SimClock.Phase.OPEN:
		$HUD.set_menu_notice(menu_open_note())
		_restock_station_supplies()
		# Morning orders arrive at once; this only lands overdue orders from older saves.
		_deliver_due()
	else:
		$HUD.set_menu_notice("")
		# A delivery slot never falls after opening hours; anything overdue lands now.
		_deliver_due()
	_refresh_stock_panel()


func _on_next_day_pressed() -> void:
	Clock.sim.next_day()


## Read-only presentation snapshot: all dishes, even those missing equipment.
## Stock uses the same ledger as #156; no buy, save or random draw happens here.
func menu_recipe_details() -> Dictionary[StringName, Dictionary]:
	var rows: Dictionary[StringName, Dictionary] = {}
	if content == null or world == null or menu_settings == null:
		return rows
	var station_state: Dictionary = _menu_station_state()
	var present: Dictionary[StringName, bool] = station_state["reachable"]
	var installed: Dictionary[StringName, bool] = station_state["installed"]
	var support: Array[Dictionary] = station_state["support"]
	var freezer_ready: bool = int(_storage_capacity().get(StorageSpace.FREEZER, 0)) > 0
	for recipe: RecipeDef in content.recipes():
		var equipment: Array[Dictionary] = []
		var required: Dictionary[StringName, bool] = {}
		for step: RecipeStep in recipe.steps:
			if required.has(step.station_type):
				continue
			required[step.station_type] = true
			equipment.append(_equipment_slot(_station_item_name(step.station_type),
				present.has(step.station_type), installed.has(step.station_type)))
		# Every dish also needs a fridge and a pass; they are listed only when missing or walled in.
		equipment.append_array(support)
		# Storage advice belongs to dishes that actually use frozen ingredients.
		for ingredient: IngredientDef in recipe.ingredients:
			if ingredient.storage == IngredientDef.Storage.FREEZER:
				equipment.append(_equipment_slot("Freezer", freezer_ready, freezer_ready))
				break
		var amounts: Dictionary[StringName, int] = {}
		for ingredient: IngredientDef in recipe.ingredients:
			amounts[ingredient.id] = amounts.get(ingredient.id, 0) + 1
		var ingredients: Array[Dictionary] = []
		for id: StringName in amounts:
			var ingredient: IngredientDef = content.ingredient(id)
			var count: int = Economy.stock.count(id)
			ingredients.append({"text": "%s: %d in stock / %d needed" % [ingredient.display_name, count, amounts[id]],
				"met": count >= amounts[id]})
		var other: Array[Dictionary] = []
		other.append({"text": "Owner level %d (you are level %d)" % [recipe.unlock_level, menu_settings.owner_level()],
			"met": menu_settings.owner_level() >= recipe.unlock_level})
		if not recipe.unlock_from.is_empty():
			var parent: RecipeDef = content.recipe(recipe.unlock_from)
			if parent != null:
				other.append({"text": "Learn %s at owner level %d" % [parent.display_name, parent.unlock_level],
					"met": menu_settings.owner_level() >= parent.unlock_level})
		var room: bool = menu_settings.is_enabled(recipe.id) or menu_settings.enabled_count() < menu_settings.menu_limit()
		other.append({"text": "Menu space: %d / %d dishes" % [menu_settings.enabled_count(), menu_settings.menu_limit()], "met": room})
		var quality: Dictionary = _menu_quality.get(recipe.id, {})
		var expected: DishQuality = _expected_dish_quality(recipe)
		rows[recipe.id] = {"equipment": equipment, "ingredients": ingredients, "other": other,
			"quality_breakdown": expected.explanation() if expected != null else "No available worker or reachable station",
			"quality": quality.get("quality", recipe.base_quality),
			"quality_source": "%d served dishes on day %d" % [quality.get("count", 0), quality.get("day", 0)]
				if not quality.is_empty() else "Recipe base quality; no served-dish sample",
			"reviews": "Shop reviews: %.1f / 5 (%d ratings)" % [reputation.average(), reputation.scores().size()]}
	return rows


## A read-only best-case estimate, using today's eligible team and reachable stations.
func _expected_dish_quality(recipe: RecipeDef) -> DishQuality:
	var stations: Array[ItemDef] = []
	var seen: Dictionary[int, bool] = {}
	for step: RecipeStep in recipe.steps:
		var best_station: PlacedItem = null
		for placed: PlacedItem in world.grid.items():
			var definition: ItemDef = placed.def as ItemDef
			if definition == null or definition.category != ItemDef.Category.STATION \
					or definition.station_type != step.station_type or not _station_reachable(placed):
				continue
			if best_station == null or definition.quality_bonus > (best_station.def as ItemDef).quality_bonus:
				best_station = placed
		if best_station == null:
			return null
		if not seen.has(best_station.id):
			seen[best_station.id] = true
			stations.append(best_station.def as ItemDef)
	var best: DishQuality = null
	var role: StringName = &"server" if recipe.is_drink() else &"cook"
	for agent: SimAgent in world.agents:
		var worker: StaffAgent = agent as StaffAgent
		if worker == null or int(worker.priorities.get(role, 0)) <= 0:
			continue
		var candidate: DishQuality = DishQuality.breakdown(recipe, worker, stations)
		if best == null or candidate.quality > best.quality:
			best = candidate
	return best


func _refresh_menu_details() -> void:
	if _menu_panel != null and content != null:
		_menu_panel.set_recipe_details(content.recipes(), menu_recipe_details())


## Keep the last service's measured dish quality for the morning view. This
## transient display cache is not game state and is never written to a save.
func _remember_menu_quality() -> void:
	var samples: Dictionary[StringName, Dictionary] = {}
	for order: Order in sim.orders.orders_in_state(Order.State.DELIVERED):
		var row: Dictionary = samples.get(order.recipe_id, {"total": 0.0, "count": 0})
		row["total"] += order.quality
		row["count"] += 1
		samples[order.recipe_id] = row
	_menu_quality.clear()
	for id: StringName in samples:
		var row: Dictionary = samples[id]
		_menu_quality[id] = {"quality": float(row["total"]) / float(row["count"]),
			"count": row["count"], "day": Clock.sim.day}


## The same reachable station facts feed #183 hints and dish requirements.
func _menu_station_state() -> Dictionary:
	var present: Dictionary[StringName, bool] = {}
	var installed: Dictionary[StringName, bool] = {}
	# The fridge and pass every dish needs (see _cookable_from): 0 missing, 1 walled in, 2 ready.
	var fridge: int = 0
	var pass_counter: int = 0
	for placed: PlacedItem in world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or placed.removed:
			continue
		if definition.category == ItemDef.Category.STATION:
			installed[definition.station_type] = true
			if _station_reachable(placed):
				present[definition.station_type] = true
		elif definition.category == ItemDef.Category.STORAGE and definition.station_type == &"fridge" \
				and not definition.work_cells.is_empty():
			fridge = maxi(fridge, 2 if _station_reachable(placed) else 1)
		elif definition.category == ItemDef.Category.PASS and definition.work_cells.size() >= 2:
			pass_counter = maxi(pass_counter, 2 if _station_reachable(placed) else 1)
	var support: Array[Dictionary] = []
	for row: Array in [[&"fridge", fridge], [&"pass", pass_counter]]:
		if int(row[1]) < 2:
			support.append(_equipment_slot(_support_item_name(row[0]), false, int(row[1]) == 1))
	return {"reachable": present, "installed": installed, "support": support}


## An Equipment slot for the dish detail: "Fryer ready", "Buy a fryer" or
## "Staff can't reach the fryer" (the Drinks hints use the same words).
static func _equipment_slot(item_name: String, ready: bool, walled_in: bool) -> Dictionary:
	if ready:
		return {"text": "%s ready" % item_name, "met": true}
	var advice: String = _equipment_advice(item_name, walled_in)
	return {"text": advice.left(1).to_upper() + advice.substr(1), "met": false}


## The fridge or pass item's own name, from data (the earliest unlock).
func _support_item_name(kind: StringName) -> String:
	var best: ItemDef = null
	for definition: ItemDef in content.items():
		var matches: bool = definition.category == ItemDef.Category.PASS if kind == &"pass" \
				else (definition.category == ItemDef.Category.STORAGE and definition.station_type == &"fridge")
		if matches and (best == null or definition.unlock_level < best.unlock_level):
			best = definition
	return best.display_name if best != null else String(kind).capitalize()
