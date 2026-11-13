extends SceneTree
## Renders the main scene and saves PNG screenshots, for reviews and PRs.
## Run through tools/screenshot.sh (it provides a virtual display).
## User args (after --): --out=<dir> --frames=120,400,900 --speed=4 --scene=res://...
## Optional --quarter=0..3 selects an exact cutaway camera quarter for review.
##   --open      press "Open shop" at the start
##   --fast=N    also run N extra sim ticks per frame (via the scene's run_ticks)
##   --select=guest|owner  inspect a live agent through the scene's selection API
##   --assign-owner=kitchen  use the normal selected-owner command (requires --open)
##   --f3        show the scene's read-only debug overlay
##   --menu      show the real menu panel in MORNING (cannot combine with --open)
##   --staff     show the real morning Staff panel, paused, with no altered roster
##   --stock     show the real morning Stock panel, paused. With --open, start a
##               sold-out fixture (no soup stock, its auto-reorder off) and show
##               the HUD Sold out tag; add --report to scroll the closed-day
##               report to its Low stock section instead
##   --settings  open Main -> Menu -> Settings at the usual 1600x900 / 100%
##   --settings-world  use the gear, select 150%, keyboard Close, show the world
##   --hud-layout --window-size=1280x720|1600x900 --speed=0 --frames=12,90
##             use the gear and keyboard Close; capture native HUD at 125%, then 150%
##   --report    require a closed-day report and real review cards at the top of the report
##   --report-slowest  scroll the real closed-day report to its native slowest seller line
##   --build=green|red|pinch  hold a checked buy preview through the production input API
##             (pinch: a valid fourth table that squeezes an aisle to one cell, #389)
##   --paint     show a painted morning shop using the production paint controls
##   --paint-slots  --paint, then paint second parts (cloths, cushions) with Shift
##               and hover a table so the Paint panel names its parts (#431)
##   --walls=place|room  FK-070 walls: a dragged run with its ghost and cost, or a
##             built room (interior wall, doorway, windows inside and out). Room
##             is Walls Up unless --quarter selects the cutaway; add --open --fast=N for guests.
##   --expand=drag|shop  FK-080 floor expansion: a dragged floor rectangle on the
##             lot with ghost, cost and lot outline, or the finished L-shaped shop
##             with tables in the new floor (Walls Up unless --quarter selects the
##             cutaway; add --open --fast=N for seated guests).
##   --rooms=tool|refused|restroom  FK-101 rooms on the expanded shop (a back room
##             behind the kitchen, reached round it by an east wing, with a
##             restroom in the back room): the Rooms tool's tints and labels, a
##             refused seat in the kitchen with its sentence, or (with --open
##             --fast=N --speed=1) a guest walking round the kitchen to the
##             restroom; the clock pauses on the first such guest.
##   --door-queue  zoom the existing camera onto a real queue, or its empty entry
##   --lease-review=offer|short|expand --speed=0 --frames=12; offer/short also require --menu
##   --loan-review --speed=0 --frames=12,90  explicit financial-fixture UI evidence
##   --milestone-review --speed=0 --frames=12,90  authored goals and close reward evidence
##   --collections-review --speed=0 --frames=240  unsaved placed-item/floor fixture,
##             real Main collection progress and native Goals rows after the toast clears
##   --catalogue-review=rustic|modern --speed=0 --frames=90,120  furnishing fixture
##   --diner-review --speed=0 --frames=12,90  six native comparisons, then seated diner fixture
##   --property-review --speed=0 --frames=12  the browse-only property market
##             (tools/property_review.gd): Tier 3 on the seed-1 morning, opened
##             from the Menu's Property button (FK-087 part 2)
##   --floors-review --speed=0 --frames=12,30  D25 floor types fixture (tools/floors_review.gd):
##             the laid floors (including hex tile and terracotta) with thresholds and both doors, then Build > Floors
##             holding a herringbone drag over the planks
##   --walls-review --speed=0 --frames=12,30 [--quarter=N]  D26 wall finishes and wall decor
##             (tools/walls_review.gd): Cutaway, then Walls Up with Build > Wall finish
##             holding a striped wallpaper drag (--quarter turns the camera for both frames)
##   Plain Main default/quarter frame60 photos use seed1 and neighbourhood time4s.
##   --neighbourhood-review=street --speed=0 --frames=60 pans to the real road centre
##             through the normal street-only clamp; photo override never runs in performance.
##   --weather-review=sunny --menu --speed=0 --frames=60, or rain without --menu:
##             explicit unsaved weather override after the real seed-1 morning selection
##   --joined-tables-review --speed=0 --frames=12,90 shows a real offer and held six-person party
##             after normal table moves, opening and bounded walking (unsaved fixture).
##   --restroom-review --speed=0 --frames=12,30 shows the complete two-toilet
##             restroom, then a close wall-fitting view with the owner for scale.
##   --street-front-review --speed=0 --frames=60 shows a purchased, finished
##             street front in daylight, with its live name and owner for scale.
##   --blueprints=selection|ghost|stamped --speed=0 --frames=30
##             FK-045 original table + rug selection, rotated ghost, or stamped pair.
##   --menu-boards-review --speed=0 --frames=12,30  #161 placed chalk board
##             with real inspector section choice, then Menu theme readout.
##   --signature-review=menu|demand --speed=0 --frames=60  seeded unsaved signature UI
##             fixture: menu plus star board, or one real service and demand report.
## Ordinary captures record real moods, markers and seeds without a fixture.

const MAX_CAPTURE_WAIT_FRAMES: int = 8
const MAX_OWNER_WARMUP_TICKS: int = 900
const SETTINGS_CAPTURE_SIZE: Vector2i = Vector2i(1600, 900)
const NEIGHBOURHOOD_REVIEW: Script = preload("res://tools/neighbourhood_review.gd")
const WEATHER_REVIEW: Script = preload("res://tools/weather_review.gd")
const JOINED_TABLES_REVIEW: Script = preload("res://tools/joined_tables_review.gd")
const LEASE_REVIEW: Script = preload("res://tools/lease_review.gd")
const DINER_REVIEW: Script = preload("res://tools/diner_review.gd")
const FLOORS_REVIEW: Script = preload("res://tools/floors_review.gd")
const PROPERTY_REVIEW: Script = preload("res://tools/property_review.gd")
const RESTROOM_REVIEW: Script = preload("res://tools/restroom_review.gd")
const BLUEPRINT_REVIEW: Script = preload("res://tools/blueprint_review.gd")
const WALLS_REVIEW: Script = preload("res://tools/walls_review.gd")
const MENU_BOARDS_REVIEW: Script = preload("res://tools/menu_boards_review.gd")
const STREET_FRONT_REVIEW: Script = preload("res://tools/street_front_review.gd")
## --floors-review: the frame Build > Floors opens with its drag held.
const FLOORS_DRAG_FRAME: int = 20
const LOAN_TERMS: LoanTuning = preload("res://data/balance/loans.tres")
const VIBE_TERMS: VibeTuning = preload("res://data/balance/vibe.tres")
const LOAN_NOTICE: String = "The bank covered your shortfall. It'll take a share of your profits until it's paid back."
const GENERATED_UID_SOURCES: Array[String] = [
	"res://src/sim/economy/loan_account.gd", "res://src/sim/economy/loan_tuning.gd",
	"res://tests/sim/test_loan_account.gd", "res://tests/world/test_loan_session.gd",
	"res://tests/tools/test_screenshot_options.gd",
]
const CATALOGUE_UID_SOURCES: Array[String] = [
	"res://src/sim/shop/dining_seats.gd", "res://src/ui/item_thumbnail_cache.gd",
	"res://tests/sim/test_dining_seats.gd", "res://tests/sim/test_dining_grid.gd",
	"res://tests/sim/test_dining_editor.gd", "res://tests/sim/test_dining_kitchen.gd",
	"res://tests/world/test_catalogue_decor.gd", "res://tests/world/test_catalogue_seating_props.gd",
	"res://tests/ui/test_item_thumbnail_cache.gd",
]
const STAFF_PRIORITY_UID_SOURCES: Array[String] = [
	"res://src/sim/staff/staff_job_priorities.gd", "res://tests/sim/test_staff_job_priorities.gd",
	"res://tests/fixtures/frozen_main_staff_picker.gd", "res://tests/world/test_staff_priorities_golden.gd",
	"res://tests/sim/test_staff_priority_persistence.gd", "res://tests/world/test_staff_priority_session.gd",
]
const VIBE_UID_SOURCES: Array[String] = [
	"res://src/sim/vibe/vibe_model.gd", "res://src/sim/vibe/vibe_tuning.gd",
	"res://tests/sim/test_vibe_model.gd", "res://src/sim/vibe/vibe_inputs.gd",
	"res://tests/sim/test_vibe_effects.gd", "res://tests/sim/test_vibe_swatches.gd",
	"res://src/ui/vibe_meter.gd", "res://tests/ui/test_vibe_meter.gd", "res://tests/world/test_vibe_session.gd",
]
const MILESTONE_UID_SOURCES: Array[String] = [
	"res://src/sim/progression/milestone.gd",
	"res://src/sim/progression/milestone_day.gd",
	"res://src/sim/progression/milestone_set.gd",
	"res://src/sim/progression/milestone_tracker.gd",
	"res://src/sim/progression/milestone_settlement.gd",
	"res://src/sim/progression/weekly_challenge.gd",
	"res://src/sim/progression/weekly_challenge_pool.gd",
	"res://src/sim/progression/weekly_challenge_state.gd",
	"res://src/sim/progression/weekly_challenge_settlement.gd",
	"res://src/ui/goals_panel.gd",
	"res://tests/core/test_milestone_loan_accounting.gd",
	"res://tests/sim/test_milestone_settlement.gd",
	"res://tests/sim/test_milestone_tracker.gd",
	"res://tests/ui/test_goals_panel.gd",
	"res://tests/world/test_milestone_session.gd",
	"res://tests/sim/test_weekly_challenge.gd",
	"res://tests/ui/test_evening_report.gd",
	"res://tests/tools/test_milestone_screenshot.gd",
	"res://tools/screenshot.gd",
]

var _frames: int = 0
var _shots: Array[int] = [120, 400, 900]
var _out: String = "screens"
var _speed: int = 4
var _quarter: int = -1
var _main: Node
var _scene_path: String = "res://src/world/main.tscn"
var _failed: bool = false
var _finished: bool = false
var _errors: ErrorCounter = ErrorCounter.new()
var _open: bool = false
var _fast: int = 0
var _selection: StringName = &""
var _assign_owner: bool = false
var _owner_warmup_ticks: int = 0
var _f3: bool = false
var _menu: bool = false
var _staff: bool = false
var _stock: bool = false
var _settings: bool = false
var _settings_from_menu: bool = false
var _settings_world: bool = false
var _settings_scale: int = 100
var _settings_keyboard: Dictionary = {}
var _shortcuts: bool = false
var _shortcuts_input: Dictionary = {}
var _hud_layout: bool = false
var _hud_window_size: Vector2i = Vector2i(1600, 900)
var _hud_layout_scale: int = 125
var _report_requested: bool = false
var _report_slowest_requested: bool = false
var _build: String = ""
var _paint: bool = false
var _paint_slots: bool = false
var _walls: String = ""
var _walls_initial: Dictionary[Vector3i, int] = {}
var _expand: String = ""
var _blueprint_profile: String = ""
var _blueprint_fixture: Dictionary = {}
var _rooms: String = ""
var _rooms_paused: bool = false
var _door_queue: bool = false
var _neighbourhood_mode: String = ""
var _neighbourhood_fixture: Dictionary = {}
var _weather_mode: String = ""
var _weather_fixture: Dictionary = {}
var _joined_tables_review: bool = false
var _joined_tables_fixture: Dictionary = {}
var _lease_mode: String = ""
var _lease_fixture: Dictionary = {}
var _loan_review: bool = false
var _loan_fixture: Dictionary = {}
var _milestone_review: bool = false
var _milestone_fixture: Dictionary = {}
var _collections_review: bool = false
var _collections_fixture: Dictionary = {}
var _catalogue_profile: StringName = &""
var _catalogue_fixture: Dictionary = {}
var _diner_review: bool = false
var _diner_fixture: Dictionary = {}
var _floors_review: bool = false
var _property_review: bool = false
var _property_fixture: Dictionary = {}
var _restroom_review: bool = false
var _walls_review: bool = false
var _walls_fixture: Dictionary = {}
var _street_front_review: bool = false
var _street_front_fixture: Dictionary = {}
var _floors_fixture: Dictionary = {}
var _menu_boards_review: bool = false
var _menu_boards_fixture: Dictionary = {}
var _signature_review: String = ""
var _signature_fixture: Dictionary = {}
var _build_pointer: Vector2 = Vector2.ZERO
var _selected_agent_id: int = -1
var _capture_pending: bool = false
var _capture_frame: int = 0
var _capture_wait_frames: int = 0
var _finish_requested: bool = false


func _initialize() -> void:
	OS.add_logger(_errors)
	var menu_boards_options: Dictionary = MENU_BOARDS_REVIEW.options(OS.get_cmdline_user_args())
	if not String(menu_boards_options["error"]).is_empty():
		_fail_capture(menu_boards_options["error"])
		return
	_menu_boards_review = menu_boards_options["enabled"]
	var signature_options: Dictionary = signature_review_options(OS.get_cmdline_user_args())
	if not String(signature_options["error"]).is_empty():
		_fail_capture(signature_options["error"])
		return
	_signature_review = signature_options["mode"]
	var neighbourhood_options: Dictionary = NEIGHBOURHOOD_REVIEW.options(OS.get_cmdline_user_args())
	if not String(neighbourhood_options["error"]).is_empty():
		_fail_capture(neighbourhood_options["error"])
		return
	_neighbourhood_mode = neighbourhood_options["mode"]
	var street_options: Dictionary = STREET_FRONT_REVIEW.options(OS.get_cmdline_user_args())
	if not String(street_options["error"]).is_empty():
		_fail_capture(street_options["error"])
		return
	_street_front_review = street_options["enabled"]
	var weather_options: Dictionary = WEATHER_REVIEW.options(OS.get_cmdline_user_args())
	if not String(weather_options["error"]).is_empty():
		_fail_capture(weather_options["error"])
		return
	_weather_mode = weather_options["mode"]
	var joined_options: Dictionary = JOINED_TABLES_REVIEW.options(OS.get_cmdline_user_args())
	if not String(joined_options["error"]).is_empty():
		_fail_capture(joined_options["error"])
		return
	_joined_tables_review = joined_options["enabled"]
	var lease_options: Dictionary = LEASE_REVIEW.options(OS.get_cmdline_user_args())
	if not String(lease_options["error"]).is_empty():
		_fail_capture(lease_options["error"])
		return
	_lease_mode = lease_options["mode"]
	var diner_options: Dictionary = DINER_REVIEW.options(OS.get_cmdline_user_args())
	if not String(diner_options["error"]).is_empty():
		_fail_capture(diner_options["error"])
		return
	_diner_review = diner_options["enabled"]
	var loan_options: Dictionary = loan_review_options(OS.get_cmdline_user_args())
	if not String(loan_options["error"]).is_empty():
		_fail_capture(loan_options["error"])
		return
	_loan_review = loan_options["enabled"]
	var milestone_options: Dictionary = milestone_review_options(OS.get_cmdline_user_args())
	if not String(milestone_options["error"]).is_empty():
		_fail_capture(milestone_options["error"])
		return
	_milestone_review = milestone_options["enabled"]
	var collections_options: Dictionary = collections_review_options(OS.get_cmdline_user_args())
	if not String(collections_options["error"]).is_empty():
		_fail_capture(collections_options["error"])
		return
	_collections_review = collections_options["enabled"]
	var blueprint_options: Dictionary = BLUEPRINT_REVIEW.options(OS.get_cmdline_user_args())
	if not String(blueprint_options["error"]).is_empty():
		_fail_capture(blueprint_options["error"])
		return
	_blueprint_profile = blueprint_options["profile"]
	var catalogue_options: Dictionary = catalogue_review_options(OS.get_cmdline_user_args())
	if not String(catalogue_options["error"]).is_empty():
		_fail_capture(catalogue_options["error"])
		return
	_catalogue_profile = catalogue_options["profile"]
	var layout_options: Dictionary = hud_layout_options(OS.get_cmdline_user_args())
	if not String(layout_options["error"]).is_empty():
		_fail_capture(layout_options["error"])
		return
	_hud_layout = layout_options["enabled"]
	_hud_window_size = layout_options["window_size"]
	var shortcuts_options: Dictionary = shortcuts_capture_options(OS.get_cmdline_user_args())
	if not String(shortcuts_options["error"]).is_empty():
		_fail_capture(shortcuts_options["error"])
		return
	_shortcuts = shortcuts_options["enabled"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--speed="):
			_speed = int(arg.trim_prefix("--speed="))
		elif arg == "--open":
			_open = true
		elif arg.begins_with("--fast="):
			_fast = int(arg.trim_prefix("--fast="))
		elif arg.begins_with("--select"):
			if arg not in ["--select=guest", "--select=owner"]:
				_fail_capture("--select only supports guest or owner")
				return
			_selection = StringName(arg.trim_prefix("--select="))
		elif arg.begins_with("--assign-owner"):
			if arg != "--assign-owner=kitchen":
				_fail_capture("--assign-owner only supports kitchen")
				return
			_assign_owner = true
		elif arg.begins_with("--f3"):
			if arg != "--f3":
				_fail_capture("--f3 does not accept a value")
				return
			_f3 = true
		elif arg.begins_with("--signature-review="):
			pass # Parsed and strictly validated above.
		elif arg == "--menu-boards-review":
			# Parsed and validated above, before the generic --menu prefix.
			pass
		elif arg.begins_with("--menu"):
			if arg != "--menu":
				_fail_capture("--menu does not accept a value")
				return
			_menu = true
		elif arg.begins_with("--stock"):
			if arg != "--stock":
				_fail_capture("--stock does not accept a value")
				return
			_stock = true
		elif arg.begins_with("--staff"):
			if arg != "--staff":
				_fail_capture("--staff does not accept a value")
				return
			_staff = true
		elif arg.begins_with("--settings"):
			if arg not in ["--settings", "--settings-world"]:
				_fail_capture("Settings capture supports --settings or --settings-world")
				return
			_settings = true
			_settings_world = _settings_world or arg == "--settings-world"
			_settings_scale = 150 if _settings_world else 100
		elif arg == "--shortcuts":
			pass # Parsed and strictly validated above.
		elif arg == "--report":
			_report_requested = true
		elif arg == "--report-slowest":
			_report_requested = true
			_report_slowest_requested = true
		elif arg.begins_with("--build"):
			var requested: String = arg.trim_prefix("--build=")
			if not ["green", "red", "pinch"].has(requested):
				_fail_capture("--build supports green, red or pinch")
				return
			_build = requested
		elif arg == "--paint":
			_paint = true
		elif arg == "--paint-slots":
			_paint = true
			_paint_slots = true
		elif arg == "--restroom-review":
			_restroom_review = true
		elif arg == "--street-front-review":
			_street_front_review = true
		elif arg.begins_with("--walls-review"):
			if arg != "--walls-review":
				_fail_capture("--walls-review does not accept a value")
				return
			_walls_review = true
		elif arg.begins_with("--walls"):
			var requested_walls: String = arg.trim_prefix("--walls=")
			if not ["place", "room"].has(requested_walls):
				_fail_capture("--walls supports place or room")
				return
			_walls = requested_walls
		elif arg.begins_with("--expand"):
			var requested_expand: String = arg.trim_prefix("--expand=")
			if not ["drag", "shop"].has(requested_expand):
				_fail_capture("--expand supports drag or shop")
				return
			_expand = requested_expand
		elif arg.begins_with("--rooms"):
			var requested_rooms: String = arg.trim_prefix("--rooms=")
			if not ["tool", "refused", "restroom"].has(requested_rooms):
				_fail_capture("--rooms supports tool, refused or restroom")
				return
			_rooms = requested_rooms
		elif arg.begins_with("--property-review"):
			if arg != "--property-review":
				_fail_capture("--property-review does not accept a value")
				return
			_property_review = true
		elif arg.begins_with("--floors-review"):
			if arg != "--floors-review":
				_fail_capture("--floors-review does not accept a value")
				return
			_floors_review = true
		elif arg.begins_with("--door-queue"):
			if arg != "--door-queue":
				_fail_capture("--door-queue does not accept a value")
				return
			_door_queue = true
		elif arg.begins_with("--scene="):
			_scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--quarter="):
			var requested: String = arg.trim_prefix("--quarter=")
			if not ["0", "1", "2", "3"].has(requested):
				_fail_capture("--quarter must be 0, 1, 2 or 3")
				return
			_quarter = int(requested)
		elif arg.begins_with("--frames="):
			_shots.clear()
			for f in arg.trim_prefix("--frames=").split(","):
				_shots.append(int(f))
	if _assign_owner and (_selection != &"owner" or not _open):
		_fail_capture("--assign-owner=kitchen requires --select=owner and --open")
		return
	if _door_queue and (_scene_path != "res://src/world/main.tscn" or not _open or _fast <= 0 \
			or not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff or _settings \
			or _report_requested or not _build.is_empty() or _paint or _quarter >= 0):
		_fail_capture("--door-queue requires a fast-forwarded Main service without other view options")
		return
	if not _build.is_empty() and (_open or _fast != 0 or not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff):
		_fail_capture("--build requires a fresh morning without other view/service flags")
		return
	if _paint and (_open or _fast != 0 or not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff or not _build.is_empty() or _speed != 0):
		_fail_capture("--paint requires a paused morning without other view/service flags")
		return
	if not _walls.is_empty() and (_scene_path != "res://src/world/main.tscn" or not _build.is_empty() or _paint \
			or _menu or _staff or _settings or not _selection.is_empty() or _f3 or _report_requested \
			or (_walls == "place" and (_open or _fast != 0 or _quarter >= 0))):
		_fail_capture("--walls requires Main without other panels; place also needs a fresh morning")
		return
	if not _expand.is_empty() and (_scene_path != "res://src/world/main.tscn" or not _build.is_empty() or _paint \
			or not _walls.is_empty() or _menu or _staff or _settings or not _selection.is_empty() or _f3 \
			or _report_requested or (_expand == "drag" and (_open or _fast != 0 or _quarter >= 0))):
		_fail_capture("--expand requires Main without other panels; drag also needs a fresh morning")
		return
	if not _rooms.is_empty() and (_scene_path != "res://src/world/main.tscn" or not _build.is_empty() or _paint \
			or not _walls.is_empty() or not _expand.is_empty() or _menu or _staff or _settings \
			or not _selection.is_empty() or _f3 or _report_requested \
			or (_rooms != "restroom" and (_open or _fast != 0)) or (_rooms == "restroom" and not _open)):
		_fail_capture("--rooms requires Main without other panels; tool and refused need a fresh morning, restroom --open")
		return
	if _floors_review and (_scene_path != "res://src/world/main.tscn" or _open or _fast != 0 or _speed != 0 \
			or not _build.is_empty() or _paint or not _walls.is_empty() or not _expand.is_empty() \
			or not _rooms.is_empty() or _menu or _staff or _settings or not _selection.is_empty() or _f3 \
			or _report_requested or _shots.min() < 4 or _shots.max() <= FLOORS_DRAG_FRAME):
		_fail_capture("--floors-review requires a paused fresh morning without other options, and a frame after %d" \
			% FLOORS_DRAG_FRAME)
		return
	if _property_review and (_scene_path != "res://src/world/main.tscn" or _open or _fast != 0 or _speed != 0 \
			or not _build.is_empty() or _paint or not _walls.is_empty() or not _expand.is_empty() \
			or not _rooms.is_empty() or _menu or _staff or _stock or _settings or not _selection.is_empty() or _f3 \
			or _report_requested or _floors_review or _walls_review or _quarter >= 0 or _shots.min() < 4):
		_fail_capture("--property-review requires a paused fresh morning without other options, frames 4 or later")
		return
	if _restroom_review and (_scene_path != "res://src/world/main.tscn" or _speed != 0 or _open or _fast != 0
			or _walls_review or _floors_review or _diner_review or not _rooms.is_empty() or not _walls.is_empty()
			or not _expand.is_empty() or not _build.is_empty() or _paint or _menu or _staff or _stock or _settings
			or _report_requested or _milestone_review or _loan_review or not _catalogue_profile.is_empty()
			or not _selection.is_empty() or _assign_owner or _door_queue or _f3 or _quarter >= 0):
		_fail_capture("--restroom-review requires a paused fresh morning without other view options")
		return
	if _walls_review and (_scene_path != "res://src/world/main.tscn" or _open or _fast != 0 or _speed != 0 \
			or not _build.is_empty() or _paint or not _walls.is_empty() or not _expand.is_empty() or _floors_review \
			or not _rooms.is_empty() or _menu or _staff or _settings or not _selection.is_empty() or _f3 \
			or _report_requested or _shots.min() < 4 or _shots.max() <= WALLS_REVIEW.WALL_UP_FRAME):
		_fail_capture("--walls-review requires a paused fresh morning without other options (but --quarter), and a frame after %d" \
			% WALLS_REVIEW.WALL_UP_FRAME)
		return
	if _menu and (_open or not _selection.is_empty()):
		_fail_capture("--menu requires morning and cannot combine with --open or --select")
		return
	if _staff and (_open or _fast != 0 or not _selection.is_empty() or _assign_owner or _f3 or _menu or _speed != 0):
		_fail_capture("--staff requires a paused morning without other service/panel options")
		return
	if _stock and not _open and (_fast != 0 or not _selection.is_empty() or _assign_owner \
			or _f3 or _menu or _staff or _speed != 0 or not _build.is_empty() or _paint):
		_fail_capture("--stock requires a paused morning without other service/panel options, or --open")
		return
	if _stock and _open and (not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff \
			or not _build.is_empty() or _paint):
		_fail_capture("--stock --open cannot combine with other view or panel options")
		return
	if _report_requested and (not _open or _fast <= 0 or _speed != 0 or _menu or _staff or not _build.is_empty()):
		_fail_capture("--report requires a fast-forwarded, paused-clock service view")
		return
	if _report_slowest_requested and _stock:
		_fail_capture("--report-slowest cannot be combined with --stock")
		return
	if _settings and (_scene_path != "res://src/world/main.tscn" or _open or _fast != 0 \
			or not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff \
			or _report_requested or not _build.is_empty() or _paint or _quarter >= 0 \
			or _speed != 0 or _shots.size() != 1):
		_fail_capture("--settings requires one paused Main capture without other view/service flags")
		return
	if _shortcuts and (_scene_path != "res://src/world/main.tscn" or _open or _fast != 0 \
			or not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff or _stock \
			or _settings or _report_requested or not _build.is_empty() or _paint or _quarter >= 0 \
			or not _walls.is_empty() or not _expand.is_empty() or not _rooms.is_empty() \
			or _door_queue or _loan_review or _milestone_review or not _catalogue_profile.is_empty() \
			or _diner_review or _floors_review or _restroom_review or _walls_review or _street_front_review \
			or _menu_boards_review or not _weather_mode.is_empty() or _joined_tables_review \
			or not _lease_mode.is_empty() or not _blueprint_profile.is_empty() or _neighbourhood_mode != "" \
			or _hud_layout or _speed != 0 or _shots.size() != 1):
		_fail_capture("--shortcuts requires one paused Main capture without other view/service flags")
		return
	if _shots.is_empty() or _shots.min() < 1 or ((_quarter >= 0 or not _selection.is_empty() or _f3 or _menu or _staff or _settings or not _build.is_empty() or _paint or _door_queue or not _walls.is_empty() or not _expand.is_empty() or not _rooms.is_empty()) and _shots.min() < 4):
		_fail_capture("capture frames must be positive, and at least 4 for requested view/UI options")
		return
	if _settings_world and _shots.min() < 90:
		_fail_capture("--settings-world requires frame 90 or later after the native 150% change")
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail_capture("cannot create output directory")
		return
	var scene: PackedScene = load(_scene_path)
	if scene == null:
		_fail_capture("cannot load scene: " + _scene_path)
		return
	_main = scene.instantiate()
	# Preserve capture isolation when the integrated game session supports saves.
	if "use_saves" in _main:
		_main.set("use_saves", false)
	if (not _lease_mode.is_empty() or _report_requested or _milestone_review or _collections_review or _diner_review or _expand == "shop" or not _rooms.is_empty() \
			or _floors_review or _property_review or _walls_review or _restroom_review or _street_front_review or _menu_boards_review or _signature_review != "" or _assign_owner or not _weather_mode.is_empty() or _joined_tables_review or not _neighbourhood_mode.is_empty()) \
			and "new_game_seed_override" in _main:
		_main.set("new_game_seed_override", 1)
	root.add_child(_main)


## A separate signature fixture; legacy review modes retain their exact arguments.
static func signature_review_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"mode": "", "error": ""}
	for argument: String in arguments:
		if argument.begins_with("--signature-review"):
			if argument not in ["--signature-review=menu", "--signature-review=demand"] or not String(result["mode"]).is_empty():
				result["error"] = "--signature-review supports one menu or demand mode"
				return result
			result["mode"] = argument.trim_prefix("--signature-review=")
	if String(result["mode"]).is_empty():
		return result
	var speeds: int = 0
	var frames: int = 0
	for argument: String in arguments:
		if argument == "--signature-review=menu" or argument == "--signature-review=demand" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=60":
			frames += 1
		else:
			result["error"] = "--signature-review requires only --speed=0 --frames=60 and optional --out"
			return result
	if speeds != 1 or frames != 1:
		result["error"] = "--signature-review requires one --speed=0 and one --frames=60"
	return result


## Pure CLI guard; the shell wrapper may supply the same --out twice.
static func loan_review_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"enabled": false, "error": ""}
	for argument: String in arguments:
		if argument.begins_with("--loan-review"):
			if argument != "--loan-review" or result["enabled"]:
				result["error"] = "--loan-review is a single flag without a value"
				return result
			result["enabled"] = true
	if not result["enabled"]:
		return result
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in arguments:
		if argument == "--loan-review" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=12,90":
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		else:
			result["error"] = "--loan-review requires paused Main frames 12,90 without other options"
			return result
	if speeds != 1 or frames != 1 or scenes > 1:
		result["error"] = "--loan-review requires one --speed=0 and one --frames=12,90"
	return result


## Milestone review has exactly two images and one deterministic Main scene.
## `--out` may repeat because the shell wrapper supplies it too.
static func milestone_review_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"enabled": false, "error": ""}
	for argument: String in arguments:
		if argument.begins_with("--milestone-review"):
			if argument != "--milestone-review" or result["enabled"]:
				result["error"] = "--milestone-review is a single flag without a value"
				return result
			result["enabled"] = true
	if not result["enabled"]:
		return result
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in arguments:
		if argument == "--milestone-review" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=12,90":
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		else:
			result["error"] = "--milestone-review requires paused Main frames 12,90 without other options"
			return result
	if speeds != 1 or frames != 1 or scenes > 1:
		result["error"] = "--milestone-review requires one --speed=0 and one --frames=12,90"
	return result


## A single paused Main capture. The shell wrapper may repeat --out.
static func collections_review_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"enabled": false, "error": ""}
	for argument: String in arguments:
		if argument.begins_with("--collections-review"):
			if argument != "--collections-review" or result["enabled"]:
				result["error"] = "--collections-review is a single flag without a value"
				return result
			result["enabled"] = true
	if not result["enabled"]:
		return result
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in arguments:
		if argument == "--collections-review" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=240":
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		else:
			result["error"] = "--collections-review requires paused Main frame 240 without other options"
			return result
	if speeds != 1 or frames != 1 or scenes > 1:
		result["error"] = "--collections-review requires one --speed=0 and one --frames=240"
	return result


## Unsaved fixture: place real content in the shop, then let Main derive the
## collection result and open the normal Menu -> Goals controls.
static func prepare_collections_review(main: Node, context_root: Node) -> Dictionary:
	var fixture: Dictionary = {"kind": "unsaved_placed_collection_review_not_balance_proof",
		"error": "", "disclosure": "Unsaved placed-item/floor fixture; not a played purchase or balance proof."}
	var clock: Node = context_root.get_node_or_null("Clock")
	var time: SimClock = clock.get("sim") as SimClock if clock != null else null
	var world: SimWorld = main.get("world") as SimWorld if "world" in main else null
	var content: ContentDB = main.get("content") as ContentDB if "content" in main else null
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor if "shop_editor" in main else null
	var goals: GoalsPanel = main.get_node_or_null("Overlay/GoalsPanel") as GoalsPanel
	var menu: MenuPanel = main.get_node_or_null("Overlay/MenuPanel") as MenuPanel
	if time == null or world == null or content == null or editor == null or goals == null or menu == null \
			or world.clock != time or world.now != 0 or time.day != 1 or time.phase != SimClock.Phase.MORNING \
			or clock.get("speed") != 0 or main.get("use_saves") != false:
		fixture["error"] = "collections review requires fresh paused unsaved Main"
		return fixture
	var coffee: CollectionDef = content.collection(&"coffee_break")
	var cozy: CollectionDef = content.collection(&"cozy_corner")
	if coffee == null or cozy == null or coffee.floor_id != &"small_tile" \
			or not cozy.item_ids.has(&"rug_round"):
		fixture["error"] = "collections review content no longer matches the authored fixture"
		return fixture
	var grid: SimGrid = world.grid
	var floor_cell: Vector2i = Vector2i.ZERO
	var found_floor: bool = false
	for cell: Vector2i in grid.cells():
		if grid.terrain(cell) == SimGrid.Terrain.FLOOR and not grid.is_outdoor_floor(cell):
			floor_cell = cell
			found_floor = true
			break
	if not found_floor:
		fixture["error"] = "collections review has no interior floor cell"
		return fixture
	var floor_changes: Dictionary[Vector2i, FloorFinishes.Finish] = {}
	floor_changes[floor_cell] = FloorFinishes.Finish.new(coffee.floor_id)
	if editor.floors.set_finishes(floor_changes).size() != 1:
		fixture["error"] = "collections review could not lay the authored floor in the real shop"
		return fixture
	var item_ids: Array[StringName] = coffee.item_ids.duplicate()
	item_ids.append(&"rug_round")
	for item_id: StringName in item_ids:
		var item: ItemDef = content.item(item_id)
		var placed: PlacedItem = null
		if item == null:
			fixture["error"] = "collections review item is missing: %s" % item_id
			return fixture
		for cell: Vector2i in grid.cells():
			if grid.terrain(cell) == SimGrid.Terrain.FLOOR and not grid.is_outdoor_floor(cell) \
					and grid.can_place_def(item, cell, 0) == SimGrid.PlaceResult.OK:
				placed = grid.place_def(item, cell)
			if placed != null:
				break
		if placed == null:
			fixture["error"] = "collections review could not place real item: %s" % item_id
			return fixture
	var toast_started_ms: int = Time.get_ticks_msec()
	main.call("_recompute_vibe")
	var vibe: VibeModel.Result = main.get("vibe_result") as VibeModel.Result
	var result: CollectionModel.Result = vibe.collection_result if vibe != null else null
	var expected_completed: Array[StringName] = [&"coffee_break"]
	if result == null or not result.valid or result.completed_ids != expected_completed:
		fixture["error"] = "Main did not derive exactly the completed Coffee Break collection"
		return fixture
	var cozy_entry: CollectionModel.Entry = null
	for entry: CollectionModel.Entry in result.entries:
		if entry.definition.id == &"cozy_corner":
			cozy_entry = entry
			break
	if cozy_entry == null or cozy_entry.completed or cozy_entry.has_floor:
		fixture["error"] = "Main did not derive the partial Cozy Corner collection"
		return fixture
	var menu_opened: bool = bool(main.call("set_menu_visible", true))
	var goals_button: Button = menu.get_node_or_null("%GoalsButton") as Button
	if not menu_opened or goals_button == null or goals_button.disabled or not goals_button.visible:
		fixture["error"] = "collections review could not open the native Menu Goals button"
		return fixture
	goals_button.pressed.emit()
	if not bool(main.call("is_goals_visible")) or menu.visible:
		fixture["error"] = "collections review did not open Goals through Menu"
		return fixture
	fixture.merge({"toast_started_ms": toast_started_ms,
		"placed_item_ids": item_ids.map(func(id: StringName) -> String: return String(id)),
		"floor_cell": [floor_cell.x, floor_cell.y], "floor_style_id": String(coffee.floor_id)})
	return fixture


## Frame 240 is a minimum. The toast's real three-second timer, not a frame
## estimate or a changed shown-state, decides when the final image is taken.
func _collections_review_ready() -> bool:
	var elapsed_ms: int = Time.get_ticks_msec() - int(_collections_fixture.get("toast_started_ms", -1))
	var hud: Node = _main.get_node_or_null("HUD")
	var toast: Control = hud.get_node_or_null("CollectionToast") as Control if hud != null else null
	var timer: Timer = hud.get_node_or_null("CollectionToastTimer") as Timer if hud != null else null
	if toast == null or timer == null:
		_fail_capture("collections review did not use the real HUD toast")
		return false
	if elapsed_ms >= 3000 and timer.is_stopped() and not toast.visible:
		return true
	if elapsed_ms > 10000:
		_fail_capture("collections review toast did not finish within ten real seconds")
	return false


## Read the displayed native rows after Main has recomputed its pure result.
static func collections_review_evidence(main: Node, context_root: Node, fixture: Dictionary,
		frame: int) -> Dictionary:
	var clock: Node = context_root.get_node_or_null("Clock")
	var time: SimClock = clock.get("sim") as SimClock if clock != null else null
	var goals: GoalsPanel = main.get_node_or_null("Overlay/GoalsPanel") as GoalsPanel
	var scroll: ScrollContainer = goals.get_node_or_null("Panel/Content/Scroll") as ScrollContainer \
		if goals != null else null
	var heading: Label = goals.get_node_or_null("Panel/Content/Scroll/List/CollectionsHeading") as Label \
		if goals != null else null
	var rows: VBoxContainer = goals.get_node_or_null("Panel/Content/Scroll/List/CollectionsRows") as VBoxContainer \
		if goals != null else null
	var hud: Node = main.get_node_or_null("HUD")
	var toast: Control = hud.get_node_or_null("CollectionToast") as Control if hud != null else null
	var timer: Timer = hud.get_node_or_null("CollectionToastTimer") as Timer if hud != null else null
	var vibe: VibeModel.Result = main.get("vibe_result") as VibeModel.Result
	var result: CollectionModel.Result = vibe.collection_result if vibe != null else null
	if time == null or goals == null or scroll == null or heading == null or rows == null \
			or toast == null or timer == null or result == null or not result.valid or result.entries.size() < 2:
		return {"available": false}
	var coffee: CollectionModel.Entry = result.entries[0]
	var cozy: CollectionModel.Entry = result.entries[1]
	if coffee.definition.id != &"coffee_break" or cozy.definition.id != &"cozy_corner" \
			or coffee.requirements.size() != 3 or cozy.requirements.size() != 3:
		return {"available": false}
	# GoalsPanel names each title from CollectionsRows.get_child_count(), not
	# from the collection's position in the result array.
	var cozy_index: int = 2 + coffee.requirements.size()
	if coffee.floor_required:
		cozy_index += 1
	if coffee.completed:
		cozy_index += 1
	if rows.get_child_count() <= cozy_index or String(rows.get_child(0).name) != "Collection0" \
			or String(rows.get_child(cozy_index).name) != "Collection%d" % cozy_index:
		return {"available": false}
	var expected: Dictionary = {"Collection0": coffee.definition.display_name,
		"CollectionShort0": coffee.definition.short_line,
		"Collection0Floor": "✓ Floor: %s" % coffee.floor_name,
		"Collection0Complete": "Complete!"}
	expected["Collection%d" % cozy_index] = cozy.definition.display_name
	expected["CollectionShort%d" % cozy_index] = cozy.definition.short_line
	expected["Collection%dFloor" % cozy_index] = "□ Floor: %s" % cozy.floor_name
	for index: int in range(3):
		var first: CollectionModel.Entry.Requirement = coffee.requirements[index]
		var second: CollectionModel.Entry.Requirement = cozy.requirements[index]
		expected["Collection0Item%d" % index] = "%s %s" % ["✓" if first.present else "□", first.display_name]
		expected["Collection%dItem%d" % [cozy_index, index]] = "%s %s" % ["✓" if second.present else "□", second.display_name]
	var visible_rows: Dictionary = {}
	for name: String in expected:
		var label: Label = rows.get_node_or_null(name) as Label
		visible_rows[name] = _loan_control_evidence(label) if label != null else {}
	var completed: Array[String] = []
	for id: StringName in result.completed_ids:
		completed.append(String(id))
	var coffee_present: Array[bool] = []
	var cozy_present: Array[bool] = []
	for requirement: CollectionModel.Entry.Requirement in coffee.requirements:
		coffee_present.append(requirement.present)
	for requirement: CollectionModel.Entry.Requirement in cozy.requirements:
		cozy_present.append(requirement.present)
	return {"available": true, "frame": frame, "elapsed_ms": Time.get_ticks_msec() - int(fixture["toast_started_ms"]),
		"day": time.day, "phase": int(time.phase), "clock_speed": clock.get("speed"),
		"use_saves": main.get("use_saves"), "goals_visible": goals.is_visible_in_tree(),
		"menu_visible": (goals.get_parent().get_node("MenuPanel") as Control).visible,
		"scroll_vertical": scroll.scroll_vertical, "heading": _loan_control_evidence(heading),
		"expected_text": expected, "rows": visible_rows, "collection_title_indices": [0, cozy_index],
		"completed_ids": completed,
		"coffee_present": coffee_present, "coffee_has_floor": coffee.has_floor,
		"cozy_present": cozy_present, "cozy_has_floor": cozy.has_floor,
		"collection_points": vibe.collection_points, "toast_visible": toast.visible,
		"toast_timer_stopped": timer.is_stopped(),
		"toast_shown": (main.get("_shown_collection_toast_ids") as Array).has(&"coffee_break"),
		"toast_pending": (main.get("_pending_collection_toast_ids") as Array).has(&"coffee_break")}


static func collections_review_valid(state: Dictionary, fixture: Dictionary) -> bool:
	if fixture.get("kind") != "unsaved_placed_collection_review_not_balance_proof" \
			or fixture.get("error") != "" or state.get("available") != true \
			or int(state.get("frame", 0)) < 240 or int(state.get("elapsed_ms", 0)) < 3000 \
			or state.get("day") != 1 or state.get("phase") != SimClock.Phase.MORNING \
			or state.get("clock_speed") != 0 or state.get("use_saves") != false \
			or state.get("goals_visible") != true or state.get("menu_visible") != false \
			or int(state.get("scroll_vertical", 0)) <= 0 \
			or state.get("completed_ids") != ["coffee_break"] \
			or state.get("coffee_present") != [true, true, true] or state.get("coffee_has_floor") != true \
			or state.get("cozy_present") != [false, true, false] or state.get("cozy_has_floor") != false \
			or state.get("collection_points") != 2.0 or state.get("toast_visible") != false \
			or state.get("toast_timer_stopped") != true or state.get("toast_shown") != true \
			or state.get("toast_pending") != false:
		return false
	var heading: Dictionary = state.get("heading", {})
	if heading.get("text") != "Decor collections" or not _milestone_native_rect_valid(heading):
		return false
	var expected: Dictionary = state.get("expected_text", {})
	var rows: Dictionary = state.get("rows", {})
	if expected.size() != 13 or rows.size() != expected.size():
		return false
	for name: String in expected:
		var row: Dictionary = rows.get(name, {})
		if row.get("text") != expected[name] or not _milestone_native_rect_valid(row):
			return false
	return true


## Uses the real Menu -> Goals native controls; the queried UI never awards state.
static func prepare_milestone_review(main: Node, context_root: Node) -> Dictionary:
	var fixture: Dictionary = {"kind": "goals_close_data_fixture_not_playthrough_or_balance_proof",
		"error": "", "requested_service_ticks": 3, "advance_frame": 24}
	var clock: Node = context_root.get_node_or_null("Clock")
	var time: SimClock = clock.get("sim") as SimClock if clock != null else null
	var world: SimWorld = main.get("world") as SimWorld if "world" in main else null
	var sim: RestaurantSim = main.get("sim") as RestaurantSim if "sim" in main else null
	var goals: GoalsPanel = main.get_node_or_null("Overlay/GoalsPanel") as GoalsPanel
	var menu: MenuPanel = main.get_node_or_null("Overlay/MenuPanel") as MenuPanel
	var catalogue: MilestoneSet = main.get("milestone_catalogue") as MilestoneSet if "milestone_catalogue" in main else null
	var career: MilestoneTracker = main.get("milestones") as MilestoneTracker if "milestones" in main else null
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress if "owner_progress" in main else null
	var ledger: Ledger = null
	var economy: Node = context_root.get_node_or_null("Economy")
	if economy != null:
		ledger = economy.get("ledger") as Ledger
	if time == null or world == null or sim == null or goals == null or menu == null \
			or catalogue == null or career == null or owner == null or ledger == null \
			or not catalogue.is_valid() or world.clock != time or time.day != 1 \
			or time.phase != SimClock.Phase.MORNING or time.tick != 0 or world.now != 0 \
			or clock.get("speed") != 0 or owner.level != 1 or not career.completed_ids().is_empty() \
			or sim.served_today != 0 or sim.lost_today != 0 \
			or not ("use_saves" in main) or main.get("use_saves") != false \
			or not main.has_method("set_menu_visible") or not main.has_method("is_goals_visible"):
		fixture["error"] = "milestone review requires fresh paused unsaved Main at day-one morning"
		return fixture
	if not main.call("set_menu_visible", true) or not menu.visible:
		fixture["error"] = "milestone review could not open the native morning Menu"
		return fixture
	var goals_button: Button = menu.get_node_or_null("%GoalsButton") as Button
	if goals_button == null or goals_button.disabled or not goals_button.visible:
		fixture["error"] = "milestone review could not find the enabled native Menu Goals button"
		return fixture
	goals_button.pressed.emit()
	if not main.call("is_goals_visible") or menu.visible:
		fixture["error"] = "milestone review did not open Goals through Menu"
		return fixture
	var expected: Array[String] = []
	var goals_data: Array[Dictionary] = []
	var target_goal: Milestone = null
	for goal: Milestone in catalogue.milestones:
		if goal == null or not goal.is_valid():
			continue
		goals_data.append(_milestone_definition_record(goal))
		if target_goal == null and goal.condition == Milestone.Condition.SERVED_TODAY \
				and is_equal_approx(goal.target, 10.0):
			target_goal = goal
		if goal.unlock_level <= owner.level and expected.size() < GoalsPanel.ACTIVE_GOAL_LIMIT:
			expected.append(String(goal.id))
	if expected.size() != GoalsPanel.ACTIVE_GOAL_LIMIT or target_goal == null \
			or target_goal.id != StringName(expected[0]) \
			or not goals.active_goal_ids().has(StringName(expected[0])):
		fixture["error"] = "milestone review requires three authored unlocked goals and a served-today target of ten"
		return fixture
	fixture.merge({"expected_active_ids": expected, "catalogue": goals_data,
		"target_goal": _milestone_definition_record(target_goal),
		"starting_cash": ledger.cash, "starting_xp": owner.total_xp,
		"starting_day_profit": ledger.day_profit(time.day),
		"starting_tracker": career.to_dict(), "starting_tick": world.now})
	return fixture


## Seeds only the authored close counter, then runs the real Main service close.
## This synthetic counter fixture is not a served-guest playthrough or balance proof.
static func advance_milestone_review(main: Node, context_root: Node, fixture: Dictionary) -> Dictionary:
	var result: Dictionary = fixture.duplicate(true)
	var clock: Node = context_root.get_node_or_null("Clock")
	var time: SimClock = clock.get("sim") as SimClock if clock != null else null
	var world: SimWorld = main.get("world") as SimWorld if "world" in main else null
	var sim: RestaurantSim = main.get("sim") as RestaurantSim if "sim" in main else null
	var menu: MenuPanel = main.get_node_or_null("Overlay/MenuPanel") as MenuPanel
	var goals: GoalsPanel = main.get_node_or_null("Overlay/GoalsPanel") as GoalsPanel
	if fixture.get("kind") != "goals_close_data_fixture_not_playthrough_or_balance_proof" \
			or fixture.get("error") != "" or time == null or world == null or sim == null \
			or menu == null or goals == null or time.phase != SimClock.Phase.MORNING \
			or world.now != 0 or clock.get("speed") != 0 or not ("use_saves" in main) \
			or main.get("use_saves") != false or fixture.get("advance_frame") != 24:
		result["error"] = "milestone review close fixture requires fresh paused unsaved Main"
		return result
	var goal_data: Dictionary = fixture.get("target_goal", {})
	var catalogue: MilestoneSet = main.get("milestone_catalogue") as MilestoneSet if "milestone_catalogue" in main else null
	var goal: Milestone = catalogue.by_id(StringName(goal_data.get("id", ""))) if catalogue != null else null
	if goal == null or String(goal.id) != String(fixture.get("expected_active_ids", [""])[0]) \
			or goal.condition != Milestone.Condition.SERVED_TODAY \
			or not is_equal_approx(goal.target, 10.0) or goals.active_goal_ids().is_empty():
		result["error"] = "milestone close fixture no longer matches the authored served-today goal"
		return result
	if goals.visible:
		var close_button: Button = goals.get_node_or_null("Panel/Content/Header/Close") as Button
		if close_button == null:
			result["error"] = "milestone review cannot close the real Goals panel"
			return result
		close_button.pressed.emit()
	if menu.visible and not bool(main.call("set_menu_visible", false)):
		result["error"] = "milestone review cannot close the Menu before service"
		return result
	if goals.visible or menu.visible or sim.customers().size() != 0:
		result["error"] = "milestone review requires no active customer or blocking panel before its close fixture"
		return result
	var before_tick: int = world.now
	var before_xp: int = (main.get("owner_progress") as OwnerProgress).total_xp
	var before_completed: Array[StringName] = (main.get("milestones") as MilestoneTracker).completed_ids()
	var before_cash: int = (context_root.get_node("Economy").get("ledger") as Ledger).cash
	# Synthetic close-data only: no guest is paid, no shared goal Resource is edited,
	# and no tracker/reward is assigned. Main settles this through its ordinary close.
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	sim.served_today = roundi(goal.target)
	sim.lost_today = 0
	time.open_ticks = 1
	time.last_orders_max_ticks = 1
	if not time.start_service():
		result["error"] = "milestone review fixture could not start the real short service"
		return result
	main.call("run_ticks", 3)
	var actual_ticks: int = world.now - before_tick
	result.merge({"fixture_served_counter": sim.served_today,
		"fixture_lost_counter": sim.lost_today, "actual_ticks": actual_ticks,
		"close_phase": int(time.phase), "closed_day": time.day,
		"before_xp": before_xp, "before_cash": before_cash,
		"before_completed": before_completed, "actual_close_frame": 24,
		"fixture_disclosure": "Synthetic close-data fixture; this is not a served-guest playthrough or balance proof."})
	if time.phase != SimClock.Phase.CLOSED or actual_ticks < 1 or actual_ticks > 3:
		result["error"] = "real short Main service did not close within three simulation ticks"
	return result


static func _milestone_definition_record(goal: Milestone) -> Dictionary:
	return {"id": String(goal.id), "title": goal.title, "description": goal.description,
		"condition": goal.condition, "target": goal.target, "reward_xp": goal.reward_xp,
		"reward_cash": goal.reward_cash, "unlock_level": goal.unlock_level}


static func milestone_review_evidence(main: Node, context_root: Node, frame: int) -> Dictionary:
	var clock: Node = context_root.get_node_or_null("Clock")
	var economy: Node = context_root.get_node_or_null("Economy")
	var time: SimClock = clock.get("sim") as SimClock if clock != null else null
	var world: SimWorld = main.get("world") as SimWorld if "world" in main else null
	var sim: RestaurantSim = main.get("sim") as RestaurantSim if "sim" in main else null
	var tracker: MilestoneTracker = main.get("milestones") as MilestoneTracker if "milestones" in main else null
	var catalogue: MilestoneSet = main.get("milestone_catalogue") as MilestoneSet if "milestone_catalogue" in main else null
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress if "owner_progress" in main else null
	var ledger: Ledger = economy.get("ledger") as Ledger if economy != null else null
	var goals: GoalsPanel = main.get_node_or_null("Overlay/GoalsPanel") as GoalsPanel
	var report_panel: Control = main.get_node_or_null("Overlay/EveningReport") as Control
	if time == null or world == null or sim == null or tracker == null or catalogue == null or owner == null \
			or ledger == null or goals == null or report_panel == null:
		return {"available": false}
	var completed: Array[String] = []
	for id: StringName in tracker.completed_ids():
		completed.append(String(id))
	var expected: Array[String] = []
	for goal: Milestone in catalogue.milestones:
		if goal != null and goal.is_valid() and not tracker.is_completed(goal.id) \
				and goal.unlock_level <= owner.level and expected.size() < GoalsPanel.ACTIVE_GOAL_LIMIT:
			expected.append(String(goal.id))
	var goals_panel: Dictionary = _milestone_goals_panel_evidence(goals)
	var weekly: WeeklyChallengeState = main.get("weekly_challenge") as WeeklyChallengeState \
		if "weekly_challenge" in main else null
	var report: DayReport = main.get("shown_report") as DayReport if "shown_report" in main else null
	var report_evidence: Dictionary = _milestone_report_evidence(main, report_panel, report, ledger)
	return {"available": true, "frame": frame, "day": time.day, "phase": int(time.phase),
		"viewport_size": [int(main.get_viewport().get_visible_rect().size.x), int(main.get_viewport().get_visible_rect().size.y)],
		"clock_tick": time.tick, "clock_speed": clock.get("speed"), "world_tick": world.now,
		"served_today": sim.served_today, "lost_today": sim.lost_today,
		"live_customers": sim.customers().size(),
		"use_saves": main.get("use_saves") if "use_saves" in main else null,
		"owner_level": owner.level, "owner_xp": owner.total_xp,
		"tracker": tracker.to_dict(), "completed_ids": completed,
		"catalogue": _milestone_catalogue_records(catalogue), "expected_active_ids": expected,
		"goals_panel": goals_panel,
		"weekly_challenge": weekly.to_dict() if weekly != null else {}, "report": report_evidence,
		"ledger_cash": ledger.cash, "ledger_day_totals": _milestone_ledger_totals(ledger, time.day),
		"ledger_day_profit": ledger.day_profit(time.day),
		"milestone_bonus_entries": _milestone_bonus_entries(ledger, time.day)}


static func _milestone_catalogue_records(catalogue: MilestoneSet) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for goal: Milestone in catalogue.milestones:
		if goal != null and goal.is_valid():
			records.append(_milestone_definition_record(goal))
	return records


static func _milestone_goals_panel_evidence(goals: GoalsPanel) -> Dictionary:
	var panel: Control = goals.get_node_or_null("Panel") as Control
	var scroll: ScrollContainer = goals.get_node_or_null("Panel/Content/Scroll") as ScrollContainer
	var active_heading: Label = goals.get_node_or_null("Panel/Content/Scroll/List/ActiveHeading") as Label
	var rows: VBoxContainer = goals.get_node_or_null("Panel/Content/Scroll/List/ActiveRows") as VBoxContainer
	var list: VBoxContainer = goals.get_node_or_null("Panel/Content/Scroll/List") as VBoxContainer
	if panel == null or scroll == null or active_heading == null or rows == null or list == null:
		return {"available": false}
	var weekly_node: Control = list.get_node_or_null("WeeklyChallenge") as Control
	var weekly_card: Dictionary = {"available": weekly_node != null}
	if weekly_node != null:
		var weekly_fields: Dictionary = {}
		for field: String in ["Title", "ProgressText", "DaysLeft", "Reward"]:
			var path: String = "Body/Title" if field == "Title" else "Body/Details/" + field
			var control: Control = weekly_node.get_node_or_null(path) as Control
			weekly_fields[field] = _loan_control_evidence(control) if control != null else {"visible": false}
		weekly_card = {"available": true, "visible": weekly_node.is_visible_in_tree(),
			"first_in_list": list.get_child_count() > 0 and list.get_child(0) == weekly_node,
			"native": _loan_control_evidence(weekly_node), "fields": weekly_fields}
	var cards: Array[Dictionary] = []
	for card_node: Node in rows.get_children():
		var card: Control = card_node as Control
		if card == null:
			return {"available": false}
		var fields: Dictionary = {}
		for field: String in ["Title", "Description", "ProgressText", "ProgressBar", "Reward"]:
			var control: Control = card.get_node_or_null("Body/" + field) as Control
			fields[field] = _loan_control_evidence(control) if control != null else {"visible": false}
		cards.append({"name": card.name, "goal_id": String(card.get_meta(&"goal_id", &"")),
			"completed": bool(card.get_meta(&"completed", false)), "native": _loan_control_evidence(card),
			"fields": fields})
	return {"available": true, "visible": goals.is_visible_in_tree(),
		"menu_visible": (goals.get_parent().get_node("MenuPanel") as Control).visible,
		"panel": _loan_control_evidence(panel), "scroll": _loan_control_evidence(scroll),
		"active_heading": {"text": active_heading.text, "visible": active_heading.is_visible_in_tree(),
			"native": _loan_control_evidence(active_heading)}, "cards": cards,
		"active_ids": goals.active_goal_ids().map(func(id: StringName) -> String: return String(id)),
		"completed_ids": goals.completed_goal_ids().map(func(id: StringName) -> String: return String(id)),
		"scroll_vertical": scroll.scroll_vertical, "weekly_card": weekly_card}


static func _milestone_report_evidence(_main: Node, panel: Control, report: DayReport, ledger: Ledger) -> Dictionary:
	var heading: Label = panel.get_node_or_null("Panel/Scroll/Content/MilestoneHeading") as Label
	var rows: VBoxContainer = panel.get_node_or_null("Panel/Scroll/Content/MilestoneRows") as VBoxContainer
	var income: GridContainer = panel.get_node_or_null("Panel/Scroll/Content/Finances/Income/IncomeRows") as GridContainer
	var xp_rows: GridContainer = panel.get_node_or_null("Panel/Scroll/Content/OwnerXPRows") as GridContainer
	var title_evidence: Dictionary = {"available": false}
	var reward_evidence: Dictionary = {"available": false}
	if rows != null and rows.get_child_count() > 0:
		var row: Control = rows.get_child(0) as Control
		if row != null and row.get_child_count() >= 2:
			var title: Label = row.get_child(0) as Label
			var reward: Label = row.get_child(1) as Label
			if title != null and reward != null:
				title_evidence = {"text": title.text, "visible": title.is_visible_in_tree(),
					"native": _loan_control_evidence(title)}
				reward_evidence = {"text": reward.text, "visible": reward.is_visible_in_tree(),
					"native": _loan_control_evidence(reward)}
	var bonus: Dictionary = {"available": false}
	if income != null:
		for index: int in range(0, income.get_child_count() - 1, 2):
			var label: Label = income.get_child(index) as Label
			var amount: Label = income.get_child(index + 1) as Label
			if label != null and amount != null and label.text == "Milestone bonus":
				bonus = {"title": _loan_control_evidence(label), "amount": _loan_control_evidence(amount)}
	var xp: Dictionary = {"available": false}
	if xp_rows != null:
		for index: int in range(0, xp_rows.get_child_count() - 1, 2):
			var label: Label = xp_rows.get_child(index) as Label
			var amount: Label = xp_rows.get_child(index + 1) as Label
			if label != null and amount != null and label.text == "Career goals":
				xp = {"title": _loan_control_evidence(label), "amount": _loan_control_evidence(amount)}
	return {"visible": panel.is_visible_in_tree(), "report_present": report != null,
		"report_day": report.day if report != null else 0,
		"report_milestones": report.milestones_reached.duplicate(true) if report != null else [],
		"milestone_xp": int(report.owner_xp_breakdown.get("milestone_xp", 0)) if report != null else 0,
		"total_xp": int(report.owner_xp_breakdown.get("total_xp", 0)) if report != null else 0,
		"heading": {"text": heading.text, "visible": heading.is_visible_in_tree(),
			"native": _loan_control_evidence(heading)} if heading != null else {"visible": false},
		"row_count": rows.get_child_count() if rows != null else 0,
		"row": _loan_control_evidence(rows.get_child(0) as Control) if rows != null and rows.get_child_count() > 0 else {},
		"title": title_evidence, "reward": reward_evidence,
		"milestone_bonus": bonus, "career_xp": xp,
		"ledger_bonus": _milestone_bonus_total(ledger, report.day) if report != null else 0}


static func _milestone_ledger_totals(ledger: Ledger, day: int) -> Dictionary:
	var totals: Dictionary = {}
	for category: StringName in ledger.day_totals(day):
		totals[String(category)] = int(ledger.day_totals(day)[category])
	return totals


static func _milestone_bonus_entries(ledger: Ledger, day: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in ledger.entries_for_day(day):
		if entry["category"] == Ledger.MILESTONE_BONUS:
			entries.append({"day": int(entry["day"]), "category": String(entry["category"]), "amount": int(entry["amount"])})
	return entries


static func _milestone_bonus_total(ledger: Ledger, day: int) -> int:
	return int(ledger.day_totals(day).get(Ledger.MILESTONE_BONUS, 0))


static func _milestone_native_rect_valid(control: Dictionary) -> bool:
	if control.get("visible") != true or control.get("inside_clip") != true:
		return false
	var rect: Variant = control.get("rect")
	if not rect is Array or rect.size() != 4:
		return false
	for value: Variant in rect:
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	return float(rect[2]) > 0.0 and float(rect[3]) > 0.0


static func milestone_review_valid(state: Dictionary, frame: int, fixture: Dictionary) -> bool:
	if fixture.get("kind") != "goals_close_data_fixture_not_playthrough_or_balance_proof" \
			or fixture.get("error") != "" or state.get("available") != true \
			or not state.has("goals_panel") or not state["goals_panel"] is Dictionary \
			or not state.has("report") or not state["report"] is Dictionary \
			or not state.has("catalogue") or not state["catalogue"] is Array \
			or not state.has("completed_ids") or not state["completed_ids"] is Array \
			or not state.has("tracker") or not state["tracker"] is Dictionary \
			or not state.has("ledger_day_totals") or not state["ledger_day_totals"] is Dictionary \
			or not state.has("milestone_bonus_entries") or not state["milestone_bonus_entries"] is Array \
			or state.get("frame") != frame or state.get("clock_speed") != 0 \
			or state.get("viewport_size") != [SETTINGS_CAPTURE_SIZE.x, SETTINGS_CAPTURE_SIZE.y] \
			or state.get("use_saves") != false or state.get("owner_level") < 1:
		return false
	var expected_catalogue: Array[Dictionary] = fixture.get("catalogue", [])
	var actual_catalogue: Array[Dictionary] = state.get("catalogue", [])
	if expected_catalogue.size() != actual_catalogue.size() or expected_catalogue.size() < 3:
		return false
	for index: int in range(expected_catalogue.size()):
		if expected_catalogue[index] != actual_catalogue[index]:
			return false
	if frame == 12:
		var goals: Dictionary = state["goals_panel"]
		if not state.get("weekly_challenge", {}) is Dictionary:
			return false
		var weekly_state: Dictionary = state["weekly_challenge"]
		if not goals.has("active_heading") or not goals["active_heading"] is Dictionary \
				or not goals.has("cards") or not goals["cards"] is Array \
				or not goals.has("active_ids") or not goals["active_ids"] is Array \
				or not goals.has("completed_ids") or not goals["completed_ids"] is Array \
				or not goals.has("weekly_card") or not goals["weekly_card"] is Dictionary \
				or weekly_state.get("status") != WeeklyChallengeState.Status.ACTIVE \
				or String(weekly_state.get("challenge_id", "")).is_empty() \
				or weekly_state.get("start_day") != 1 or weekly_state.get("end_day") != 7 \
				or int(weekly_state.get("target", 0)) < 1:
			return false
		var weekly: Dictionary = goals["weekly_card"]
		if not weekly.get("fields", {}) is Dictionary:
			return false
		var weekly_fields: Dictionary = weekly["fields"]
		if weekly.get("available") != true or weekly.get("visible") != true \
				or weekly.get("first_in_list") != true \
				or not _milestone_native_rect_valid(weekly.get("native", {})) \
				or not weekly_fields.get("Title") is Dictionary \
				or not weekly_fields.get("ProgressText") is Dictionary \
				or not weekly_fields.get("DaysLeft") is Dictionary \
				or not weekly_fields.get("Reward") is Dictionary:
			return false
		for field: String in ["Title", "ProgressText", "DaysLeft", "Reward"]:
			if not weekly_fields[field].get("visible", false) \
					or String(weekly_fields[field].get("text", "")).strip_edges().is_empty() \
					or not _milestone_native_rect_valid(weekly_fields[field]):
				return false
		if weekly_fields["Title"].get("text") != weekly_state.get("text") \
				or weekly_fields["Reward"].get("text") != "Cash reward: $%d" % int(weekly_state.get("reward_cash", 0)):
			return false
		if state["phase"] != SimClock.Phase.MORNING or state["world_tick"] != 0 \
				or state["day"] != 1 or not state["completed_ids"].is_empty() \
				or state["tracker"] != fixture.get("starting_tracker") \
				or state["owner_xp"] != int(fixture.get("starting_xp", -1)) \
				or state["ledger_cash"] != int(fixture.get("starting_cash", -1)) \
				or not state["milestone_bonus_entries"].is_empty() \
				or goals.get("available") != true or goals.get("visible") != true \
				or goals.get("menu_visible") != false or goals.get("scroll_vertical") != 0 \
				or goals["active_heading"].get("visible") != true \
				or goals["active_heading"].get("text") != "Next goals" \
				or goals["active_ids"] != fixture.get("expected_active_ids") \
				or goals["completed_ids"].size() != 0 or goals["cards"].size() != 3 \
				or state["report"].get("visible") != false \
				or not _milestone_native_rect_valid(goals["panel"]) \
				or not _milestone_native_rect_valid(goals["scroll"]) \
				or not _milestone_native_rect_valid(goals["active_heading"]["native"]):
			return false
		for index: int in range(3):
			var card: Dictionary = goals["cards"][index]
			if card.get("completed") != false or card.get("goal_id") != fixture["expected_active_ids"][index] \
					or not _milestone_native_rect_valid(card["native"]):
				return false
			var definition: Dictionary = {}
			for row: Dictionary in expected_catalogue:
				if row.get("id") == card.get("goal_id"):
					definition = row
					break
			if definition.is_empty() or card["fields"]["Title"].get("text") != definition.get("title") \
					or card["fields"]["Description"].get("text") != definition.get("description") \
					or card["fields"]["Reward"].get("text") != "Reward: %d XP   Cash: $%d" % [int(definition.get("reward_xp", -1)), int(definition.get("reward_cash", -1))] \
					or String(card["fields"]["ProgressText"].get("text", "")).is_empty():
				return false
			for field: String in ["Title", "Description", "ProgressText", "ProgressBar", "Reward"]:
				if not _milestone_native_rect_valid(card["fields"][field]):
					return false
		return true
	if frame != 90:
		return false
	var goal: Dictionary = fixture.get("target_goal", {})
	var goals_panel: Dictionary = state["goals_panel"]
	var report: Dictionary = state["report"]
	if not report.has("report_milestones") or not report["report_milestones"] is Array \
			or not report.has("heading") or not report["heading"] is Dictionary \
			or not report.has("title") or not report["title"] is Dictionary \
			or not report.has("reward") or not report["reward"] is Dictionary \
			or not report.has("milestone_bonus") or not report["milestone_bonus"] is Dictionary \
			or not report.has("career_xp") or not report["career_xp"] is Dictionary:
		return false
	if int(fixture.get("actual_close_frame", -1)) != 24 \
			or int(fixture.get("actual_ticks", 0)) < 1 or int(fixture.get("actual_ticks", 0)) > 3 \
			or fixture.get("fixture_served_counter") != 10 or fixture.get("fixture_lost_counter") != 0 \
			or fixture.get("fixture_disclosure") != "Synthetic close-data fixture; this is not a served-guest playthrough or balance proof." \
			or int(goal.get("condition", -1)) != Milestone.Condition.SERVED_TODAY \
			or not is_equal_approx(float(goal.get("target", 0.0)), 10.0):
		return false
	var expected_reward: Dictionary = {"title": goal.get("title", ""),
		"reward_xp": goal.get("reward_xp", 0), "reward_cash": goal.get("reward_cash", 0)}
	var actual_milestone: Dictionary = report["report_milestones"][0] if report["report_milestones"].size() == 1 else {}
	var earned: int = int(goal.get("reward_cash", -1))
	var report_total_xp: int = int(report.get("total_xp", -1))
	if state["phase"] != SimClock.Phase.CLOSED or state["day"] != 1 \
			or state["clock_tick"] < 1 or state["world_tick"] < 1 \
			or state["served_today"] != 10 or state["lost_today"] != 0 or state["live_customers"] != 0 \
			or goals_panel.get("available") != true or goals_panel.get("visible") != false \
			or goals_panel.get("menu_visible") != false \
			or report.get("visible") != true or report.get("report_present") != true \
			or report.get("report_day") != 1 or report.get("heading", {}).get("visible") != true \
			or report.get("heading", {}).get("text") != "Milestone reached!" \
			or actual_milestone != expected_reward or report.get("row_count") != 1 \
			or report.get("title", {}).get("text") != goal.get("title") \
			or report.get("reward", {}).get("text") != "Reward: +%d XP, %s" % [int(goal.get("reward_xp", 0)), Fmt.money(int(goal.get("reward_cash", 0)))] \
			or report.get("milestone_xp") != int(goal.get("reward_xp", 0)) \
			or report_total_xp < int(goal.get("reward_xp", 0)) \
			or report.get("ledger_bonus") != earned \
			or int(state["ledger_day_totals"].get(String(Ledger.MILESTONE_BONUS), 0)) != earned \
			or not state["completed_ids"].has(String(goal.get("id", ""))) \
			or state["owner_xp"] != int(fixture.get("starting_xp", 0)) + report_total_xp \
			or report.get("total_xp") < 0 \
			or state["ledger_cash"] != int(fixture.get("starting_cash", 0)) \
				+ int(state["ledger_day_profit"]) - int(fixture.get("starting_day_profit", 0)):
		return false
	if not _milestone_native_rect_valid(report["heading"]["native"]) \
			or not _milestone_native_rect_valid(report["row"]) \
			or not _milestone_native_rect_valid(report["title"]["native"]) \
			or not _milestone_native_rect_valid(report["reward"]["native"]):
		return false
	var bonus: Dictionary = report["milestone_bonus"]
	var career_xp: Dictionary = report["career_xp"]
	var bonus_entries: Array[Dictionary] = state.get("milestone_bonus_entries", [])
	return bonus_entries.size() == 1 and bonus_entries[0].get("amount") == earned \
		and bonus.get("available") != false and bonus.get("title", {}).get("text") == "Milestone bonus" \
		and bonus.get("amount", {}).get("text") == Fmt.money(earned) \
		and _milestone_native_rect_valid(bonus["title"]) and _milestone_native_rect_valid(bonus["amount"]) \
		and career_xp.get("available") != false and career_xp.get("title", {}).get("text") == "Career goals" \
		and career_xp.get("amount", {}).get("text") == "+%d XP" % int(goal.get("reward_xp", 0)) \
		and career_xp.get("title", {}).get("visible") == true \
		and career_xp.get("amount", {}).get("visible") == true


## Explicit financial fixture, never a playable balance sample. Real commands
## produce the loan, report and HUD; no account or presentation value is assigned.
static func prepare_loan_review(main: Node, context_root: Node) -> Dictionary:
	var result: Dictionary = {"kind": "financial_fixture", "error": "", "requested_ticks": 3}
	var clock: Node = context_root.get_node_or_null("Clock")
	var economy: Node = context_root.get_node_or_null("Economy")
	var world: SimWorld = main.get("world") as SimWorld if "world" in main else null
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim if "sim" in main else null
	var time: SimClock = clock.get("sim") as SimClock if clock != null else null
	var account: LoanAccount = economy.get("loan") as LoanAccount if economy != null else null
	var ledger: Ledger = economy.get("ledger") as Ledger if economy != null else null
	if world == null or restaurant == null or time == null or account == null or ledger == null \
			or world.clock != time or restaurant.world != world or time.day != 1 \
			or time.phase != SimClock.Phase.MORNING or clock.get("speed") != 0 \
			or not ("use_saves" in main) or main.get("use_saves") != false \
			or not main.has_method("run_ticks") or not economy.has_method("add_cash") \
			or account.principal != 0 or account.last_settled_day != 0 or account.has_borrowed \
			or ledger.cash < 0 or ledger.cash > LoanAccount.MAX_CURRENCY - LOAN_TERMS.borrowing_step:
		result["error"] = "loan review requires a fresh paused, unsaved Main session"
		return result
	var before_tick: int = world.now
	var debit: int = ledger.cash + LOAN_TERMS.borrowing_step
	result.merge({"debit": -debit, "debit_category": String(Ledger.OTHER), "starting_cash": str(ledger.cash),
		"service_open_ticks": 1, "service_last_orders_ticks": 1, "arrival_gap": 100000})
	economy.call("add_cash", -debit, Ledger.OTHER)
	restaurant.spawner.min_gap = 100000
	restaurant.spawner.max_gap = 100000
	restaurant.spawner.reset()
	time.open_ticks = 1
	time.last_orders_max_ticks = 1
	if not time.start_service():
		result["error"] = "loan fixture could not start the real short service"
		return result
	main.call("run_ticks", 3)
	result.merge({"actual_ticks": world.now - before_tick, "closed_day": time.day,
		"closed_principal": str(account.principal)})
	if time.phase != SimClock.Phase.CLOSED or account.principal <= 0:
		result["error"] = "real short service did not close with a bank advance"
	return result


## Read actual model and native controls; queries never run a command or refresh.
static func loan_review_evidence(main: Node, context_root: Node) -> Dictionary:
	var clock: Node = context_root.get_node_or_null("Clock")
	var economy: Node = context_root.get_node_or_null("Economy")
	var time: SimClock = clock.get("sim") as SimClock if clock != null else null
	var account: LoanAccount = economy.get("loan") as LoanAccount if economy != null else null
	var ledger: Ledger = economy.get("ledger") as Ledger if economy != null else null
	var panel: Control = main.get_node_or_null("Overlay/EveningReport") as Control
	var notice: Label = main.get_node_or_null("Overlay/EveningReport/Panel/Scroll/Content/LoanNotice") as Label
	var headline: Label = main.get_node_or_null("Overlay/EveningReport/Panel/Scroll/Content/Profit") as Label
	var hud: Label = main.get_node_or_null("HUD/Top/Row/Loan") as Label
	if time == null or account == null or ledger == null or panel == null or notice == null or headline == null or hud == null:
		return {"available": false}
	var report: DayReport = main.get("shown_report") as DayReport
	var flows: Array[Dictionary] = []
	for entry: Dictionary in ledger.entries_for_day(account.last_settled_day):
		if entry["category"] in [Ledger.BANK_LOAN, Ledger.LOAN_INTEREST, Ledger.LOAN_REPAYMENT]:
			flows.append({"day": entry["day"], "category": String(entry["category"]), "amount": entry["amount"]})
	var labels: Array[Dictionary] = []
	for path: String in ["Panel/Scroll/Content/Finances/Income/IncomeRows", "Panel/Scroll/Content/Finances/Costs/CostRows"]:
		var rows: Node = panel.get_node_or_null(path)
		if rows == null:
			return {"available": false}
		for index: int in range(0, rows.get_child_count() - 1, 2):
			var title: Label = rows.get_child(index) as Label
			var amount: Label = rows.get_child(index + 1) as Label
			if title == null or amount == null:
				return {"available": false}
			if title.text in ["Bank loan", "Loan interest", "Loan repayment"]:
				labels.append({"title": _loan_control_evidence(title), "amount": _loan_control_evidence(amount)})
	return {"available": true, "day": time.day, "phase": int(time.phase), "clock_tick": time.tick,
		"clock_speed": clock.get("speed"), "use_saves": main.get("use_saves"),
		"principal": str(account.principal), "last_settled_day": account.last_settled_day,
		"has_borrowed": account.has_borrowed, "cash": str(ledger.cash), "bank_flows": flows,
		"report_present": report != null, "report_day": report.day if report != null else null,
		"report_first_advance": report.loan_first_advance if report != null else false,
		"report_bank_advance": report.income.get(Ledger.BANK_LOAN, 0) if report != null else 0,
		"report_cash_change": report.profit() if report != null else null,
		"settled_day_cash_change": ledger.day_profit(account.last_settled_day),
		"report_operating_profit": report.operating_profit() if report != null else null,
		"report_purchase_basis_operating_profit": report.purchase_basis_operating_profit() if report != null else null,
		"report_ingredient_net": int(report.income.get(Ledger.INGREDIENTS, 0)) - int(report.costs.get(Ledger.INGREDIENTS, 0)) if report != null else null,
		"report_food_cost": report.food_cost if report != null else null,
		"report_food_cost_recorded": report.food_cost_recorded if report != null else false,
		"operating_headline": _loan_control_evidence(headline),
		"report": _loan_control_evidence(panel), "notice": _loan_control_evidence(notice),
		"loan_hud": _loan_control_evidence(hud), "bank_labels": labels}


## Provenance only. Read real sidecars and the runtime UID cache; never create,
## import, register or repair an ID. Missing evidence does not alter UI gates.
static func generated_uid_evidence(sources: Array[String] = GENERATED_UID_SOURCES) -> Dictionary:
	var entries: Array[Dictionary] = []
	var complete_match: bool = true
	for source: String in sources:
		var uid_path: String = source + ".uid"
		var source_exists: bool = FileAccess.file_exists(source)
		var sidecar_exists: bool = FileAccess.file_exists(uid_path)
		var sidecar_readable: bool = false
		var sidecar_text: String = ""
		var read_error: Error = OK
		if sidecar_exists:
			var file: FileAccess = FileAccess.open(uid_path, FileAccess.READ)
			if file != null:
				sidecar_text = file.get_as_text()
				read_error = file.get_error()
				sidecar_readable = read_error == OK or read_error == ERR_FILE_EOF
				file.close()
			else:
				read_error = FileAccess.get_open_error()
		var registered_id: int = ResourceLoader.get_resource_uid(source) if source_exists else ResourceUID.INVALID_ID
		var registered_text: String = ResourceUID.id_to_text(registered_id) if registered_id >= 0 else ""
		var registered_known: bool = registered_id >= 0 and ResourceUID.has_id(registered_id)
		var matches: bool = sidecar_readable and not sidecar_text.strip_edges().is_empty() \
			and registered_id >= 0 and sidecar_text.strip_edges() == registered_text
		var status: String = "match"
		if not source_exists:
			status = "missing_source"
		elif not sidecar_exists:
			status = "missing_sidecar"
		elif not sidecar_readable:
			status = "unreadable_sidecar"
		elif sidecar_text.strip_edges().is_empty():
			status = "empty_sidecar"
		elif registered_id < 0:
			status = "unregistered"
		elif not registered_known:
			status = "not_cached"
		elif not matches:
			status = "mismatch"
		complete_match = complete_match and status == "match"
		entries.append({"source": source, "source_exists": source_exists, "uid_path": uid_path,
			"sidecar_exists": sidecar_exists, "sidecar_readable": sidecar_readable,
			"sidecar_text": sidecar_text, "read_error": int(read_error),
			"registered_id": str(registered_id), "registered_text": registered_text,
			"registered_known": registered_known, "matches_registered": matches, "status": status})
	return {"read_only": true, "complete_match": complete_match, "entries": entries}


static func catalogue_review_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"profile": &"", "error": ""}
	for argument: String in arguments:
		if argument.begins_with("--catalogue-review"):
			if not String(result["profile"]).is_empty() or argument not in ["--catalogue-review=rustic", "--catalogue-review=modern"]:
				result["error"] = "--catalogue-review requires one rustic or modern profile"
				return result
			result["profile"] = StringName(argument.trim_prefix("--catalogue-review="))
	if String(result["profile"]).is_empty():
		return result
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in arguments:
		if argument.begins_with("--catalogue-review=") or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=90,120":
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		else:
			result["error"] = "catalogue review requires paused Main frames 90,120 without other options"
			return result
	if speeds != 1 or frames != 1 or scenes > 1:
		result["error"] = "catalogue review requires one --speed=0 and one --frames=90,120"
	return result


## Positions and styles belong only to this declared visual fixture. Definitions,
## prices, tags, unlock thresholds, wrapper art and paint come from real content.
static func catalogue_review_profile(profile: StringName) -> Dictionary:
	if profile not in [&"rustic", &"modern"]:
		return {}
	var rustic: bool = profile == &"rustic"
	var table: StringName = &"cross_table" if rustic else &"glass_table"
	var items: Array[Dictionary] = [
		{"id": table, "origin": Vector2i(2, 6)}, {"id": table, "origin": Vector2i(6, 6)},
		{"id": &"bookcase_open_low" if rustic else &"speaker", "origin": Vector2i(11, 6)},
		{"id": &"rug_rectangle" if rustic else &"rug_square", "origin": Vector2i(5, 6) if rustic else Vector2i(9, 8)},
	]
	if rustic:
		items.append({"id": &"bench", "origin": Vector2i(2, 7)})
	else:
		items.append({"id": &"modern_frame_chair", "origin": Vector2i(2, 7)})
		items.append({"id": &"modern_frame_chair", "origin": Vector2i(3, 7)})
	for cell: Vector2i in [Vector2i(6, 7), Vector2i(7, 7)]:
		items.append({"id": &"wooden_chair" if rustic else &"modern_chair", "origin": cell})
	return {"items": items, "category": &"dining" if rustic else &"decor",
		"wall": &"cream" if rustic else &"slate_blue", "floor": &"honey" if rustic else &"cream",
		"body": &"walnut" if rustic else &"charcoal"}


## Validated memory progress and real ledger funding are explicit fixture inputs,
## not earned progression or a playable balance result. No save or phase changes.
static func prepare_catalogue_review(main: Node, context_root: Node, profile: StringName) -> Dictionary:
	var result: Dictionary = {"kind": "furnishing_fixture", "profile": String(profile), "error": ""}
	var recipe: Dictionary = catalogue_review_profile(profile)
	var world: SimWorld = main.get("world") as SimWorld if "world" in main else null
	var content: ContentDB = main.get("content") as ContentDB if "content" in main else null
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress if "owner_progress" in main else null
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor if "shop_editor" in main else null
	var catalogue: BuildCatalogue = main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var clock: Node = context_root.get_node_or_null("Clock")
	var economy: Node = context_root.get_node_or_null("Economy")
	if recipe.is_empty() or world == null or content == null or progress == null or editor == null \
			or catalogue == null or clock == null or economy == null or main.get("use_saves") != false \
			or world.clock.phase != SimClock.Phase.MORNING or world.clock.day != 1 or world.now != 0 \
			or clock.get("speed") != 0 or clock.get("sim") != world.clock:
		result["error"] = "catalogue review requires fresh paused unsaved Main"
		return result
	var snapshot: Dictionary = progress.to_dict()
	snapshot["total_xp"] = progress.threshold_for(6)
	snapshot["level"] = 6
	snapshot["last_awarded_day"] = 0
	if not progress.from_dict(snapshot):
		result["error"] = "catalogue progress fixture did not validate"
		return result
	editor.set_owner_level(progress.level)
	catalogue.set_owner_level(progress.level)
	(main.get("menu_settings") as MenuSettings).set_owner_level(progress.level)
	main.get_node("HUD").call("set_owner_progress", progress.level, progress.xp_into_level(), progress.xp_in_level())
	var refund: int = 0
	var removed: int = 0
	for item: PlacedItem in world.grid.items():
		if (item.def as ItemDef).id == &"table_2":
			var amount: int = int(main.call("shop_sell", item.id))
			if amount < 0:
				result["error"] = "starter table sale was refused"
				return result
			refund += amount
			removed += 1
	var total: int = 0
	for row: Dictionary in recipe["items"]:
		var definition: ItemDef = content.item(row["id"])
		if definition == null or not definition.catalogue_visible:
			result["error"] = "catalogue fixture requires visible content"
			return result
		total += definition.price
	var cash: int = int(economy.get("cash"))
	var grant: int = maxi(0, total - cash)
	if grant > 0:
		economy.call("add_cash", grant, Ledger.OTHER)
	var bought: Array[int] = []
	for row: Dictionary in recipe["items"]:
		if not bool(main.call("shop_buy", row["id"], row["origin"], 0)):
			result["error"] = "catalogue fixture purchase was refused: " + String(row["id"])
			return result
		var definition: ItemDef = content.item(row["id"])
		var purchased: PlacedItem = world.grid.item_on_layer(row["origin"], definition.placement_layer)
		if purchased == null or (purchased.def as ItemDef).id != definition.id:
			result["error"] = "catalogue fixture purchase is missing from its placement layer"
			return result
		bought.append(purchased.id)
	if not bool(main.call("set_paint_active", true)):
		result["error"] = "catalogue fixture paint mode was refused"
		return result
	var targets: Array[Dictionary] = [{"swatch": recipe["wall"], "cell": Vector2i(0, 6)},
			{"swatch": recipe["floor"], "cell": Vector2i(1, 9)}]
	# A floor paint click stops at its room (D25), so the kitchen floor takes
	# the recipe colour with its own click, as the whole-floor paint once did.
	for cell: Vector2i in editor.floor_room_cells(Vector2i(6, 4)):
		if world.grid.item_at(cell) == null:
			targets.append({"swatch": recipe["floor"], "cell": cell})
			break
	for target: Dictionary in targets:
		(catalogue.swatch_buttons[target["swatch"]] as Button).pressed.emit()
		if not bool(main.call("paint_cell", target["cell"])):
			result["error"] = "catalogue fixture room paint was refused"
			return result
	(catalogue.swatch_buttons[recipe["body"]] as Button).pressed.emit()
	for id: int in bought:
		var item: PlacedItem = world.grid.item(id)
		if (item.def as ItemDef).paintable and not bool(main.call("paint_cell", item.origin)):
			result["error"] = "catalogue fixture body paint was refused"
			return result
	main.call("set_paint_active", false)
	if not bool(main.call("set_build_active", true)):
		result["error"] = "catalogue fixture build mode was refused"
		return result
	(catalogue.category_buttons[recipe["category"]] as Button).pressed.emit()
	result.merge({"owner_progress": snapshot, "cash_grant": grant, "grant_category": String(Ledger.OTHER),
		"refund": refund, "removed_tables": removed, "purchase_total": total, "purchased_ids": bought,
		"simulation_ticks": 0, "category": String(recipe["category"])})
	return result


## Expected identities come from all valid visible data, including locked cards
## and other categories, independently of the catalogue's actual button list.
static func _catalogue_content_expectations(content: ContentDB, selected: Dictionary[StringName, StringName] = {}) -> Dictionary:
	var cards: Array[Dictionary] = []
	var wrappers: Array[String] = []
	for definition: ItemDef in content.items():
		if definition == null or not definition.catalogue_visible or definition.id.is_empty() \
				or definition.display_name.strip_edges().is_empty() or definition.price < 0 or definition.unlock_level < 1 \
				or definition.footprint.x < 1 or definition.footprint.y < 1 or not definition.placement_layer_valid() \
				or not [ItemDef.Category.TABLE, ItemDef.Category.CHAIR, ItemDef.Category.STATION,
					ItemDef.Category.STORAGE, ItemDef.Category.PASS, ItemDef.Category.DECOR,
					ItemDef.Category.RESTROOM, ItemDef.Category.WAITING].has(definition.category):
			continue
		var path: String = definition.view_scene.resource_path if definition.view_scene != null else ""
		cards.append({"id": String(definition.id), "name": definition.display_name, "price": definition.variant_price(selected.get(definition.id, &"")),
			"unlock_level": definition.unlock_level, "scene": path, "room": String(definition.buy_room())})
		if not path.is_empty() and not wrappers.has(path):
			wrappers.append(path)
	# The Walls tab (FK-070) previews its Kenney pieces in the same cache.
	var wall_scenes: Array[String] = []
	for wall: WallKindDef in content.wall_kinds():
		var wall_path: String = wall.thumbnail_scene.resource_path if wall.thumbnail_scene != null else ""
		if not wall_path.is_empty() and not wall_scenes.has(wall_path):
			wall_scenes.append(wall_path)
			if not wrappers.has(wall_path):
				wrappers.append(wall_path)
	# The Floor card (FK-080) previews its Kenney tile in the same cache.
	var floor_path: String = BuildCatalogue.FLOOR_THUMBNAIL.resource_path
	if not wall_scenes.has(floor_path):
		wall_scenes.append(floor_path)
	if not wrappers.has(floor_path):
		wrappers.append(floor_path)
	wrappers.sort()
	return {"cards": cards, "wrappers": wrappers, "wall_scenes": wall_scenes}


## Look up the exact selected scene/look without scheduling a missing render.
static func catalogue_cached_thumbnail(cache: ItemThumbnailCache, definition: ItemDef,
		variant_id: StringName = &"") -> Texture2D:
	if definition.view_scene == null:
		return null
	var request: ItemThumbnailCache.Request = ItemThumbnailCache.Request.new(definition.view_scene, definition.variant(variant_id))
	return cache._textures.get(request.key) as Texture2D


## Validate each rendered request, then report unique wrapper coverage separately:
## multiple looks of one wrapper are legitimate cache entries.
static func catalogue_cached_evidence(cache: ItemThumbnailCache) -> Dictionary:
	var scenes: Array[String] = []
	var valid: bool = true
	for key: String in cache._textures:
		var request: ItemThumbnailCache.Request = cache._scenes.get(key)
		var texture: Texture2D = cache._textures[key]
		if request == null or request.scene == null:
			valid = false
			continue
		var identity: ItemThumbnailCache.Request = ItemThumbnailCache.Request.new(request.scene, request.look)
		valid = valid and key == request.key and key == identity.key \
			and texture is ImageTexture and texture.get_size() == Vector2(96, 96)
		if not scenes.has(request.scene.resource_path):
			scenes.append(request.scene.resource_path)
	scenes.sort()
	return {"scenes": scenes, "valid": valid}


## Read existing cache entries only: request() would queue missing thumbnails.
## Visibility here means native clipping geometry, not an aesthetic verdict.
static func catalogue_review_evidence(main: Node, context_root: Node) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var content: ContentDB = main.get("content") as ContentDB
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var catalogue: BuildCatalogue = main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var shop: ShopView = main.get_node_or_null("ShopView") as ShopView
	var clock: Node = context_root.get_node_or_null("Clock")
	if world == null or sim == null or not sim.staff_spawns.has(&"server") \
			or editor == null or content == null or progress == null or catalogue == null or shop == null or clock == null:
		return {"available": false}
	var cache: ItemThumbnailCache = catalogue._thumbnails
	var expected: Dictionary = _catalogue_content_expectations(content, catalogue.selected_variants)
	var cached: Dictionary = catalogue_cached_evidence(cache)
	var cards: Array[Dictionary] = []
	var icons_match: bool = true
	var onscreen: int = 0
	for id: StringName in catalogue.ordered_ids():
		var definition: ItemDef = content.item(id)
		if definition == null or not catalogue.item_buttons.has(id):
			return {"available": false}
		var scene: PackedScene = definition.view_scene
		var button: Button = catalogue.item_buttons[id]
		var texture: Texture2D = null
		if scene != null:
			texture = catalogue_cached_thumbnail(cache, definition, catalogue.selected_variants.get(id, &""))
		var matches: bool = texture is ImageTexture and button.icon == texture and texture.get_size() == Vector2(96, 96)
		icons_match = icons_match and matches
		var control: Dictionary = _loan_control_evidence(button)
		if control["visible"] and control["inside_clip"]:
			onscreen += 1
		cards.append({"id": String(id), "text": button.text, "disabled": button.disabled,
			"catalogue_visible": definition.catalogue_visible,
			"category": String(BuildCatalogue.category_for(definition)), "unlock_level": definition.unlock_level,
			"scene": scene.resource_path if scene != null else "", "native": control,
			"icon_matches_cache": matches, "icon_width_limit": button.get_theme_constant("icon_max_width"),
			"texture_id": texture.get_instance_id() if texture != null else null,
			"icon_id": button.icon.get_instance_id() if button.icon != null else null,
			"texture_size": [texture.get_width(), texture.get_height()] if texture != null else []})
	var tabs: Array[Dictionary] = []
	for id: StringName in BuildCatalogue.CATEGORY_IDS:
		var button: Button = catalogue.category_buttons[id]
		tabs.append({"id": String(id), "text": button.text, "pressed": button.button_pressed,
			"shown": button.visible, "native": _loan_control_evidence(button)})
	var items: Array[Dictionary] = []
	for item: PlacedItem in world.grid.items():
		var definition: ItemDef = item.def as ItemDef
		var visual: ItemVisual = shop.item_nodes.get(item.id) as ItemVisual
		var prop: PropView = visual.prop if visual != null else null
		var cells: Array = []
		for cell: Vector2i in item.cells:
			cells.append([cell.x, cell.y])
		var record: Dictionary = {"id": item.id, "definition": String(definition.id),
			"origin": [item.origin.x, item.origin.y], "turns": item.quarter_turns,
			"category": int(definition.category), "placement_layer": int(item.placement_layer), "solid": item.solid,
			"definition_layer": int(definition.placement_layer), "definition_solid": definition.solid,
			"catalogue_visible": definition.catalogue_visible, "cells": cells,
			"paint": String(item.swatch_id), "paintable": definition.paintable, "tags": definition.theme_tags,
			"expected_wrapper": definition.view_scene.resource_path if definition.view_scene != null else "",
			"wrapper": prop.scene_file_path if prop != null else "", "rendered": prop != null and prop.is_visible_in_tree()}
		if item.placement_layer == ItemDef.PlacementLayer.FLOOR_DECOR:
			var coverage: Array[Dictionary] = []
			var covered: Array[int] = []
			for cell: Vector2i in item.cells:
				var normal: PlacedItem = world.grid.item_on_layer(cell, ItemDef.PlacementLayer.NORMAL)
				var floor_decor: PlacedItem = world.grid.item_on_layer(cell, ItemDef.PlacementLayer.FLOOR_DECOR)
				coverage.append({"cell": [cell.x, cell.y], "normal": normal.id if normal != null else 0,
					"floor_decor": floor_decor.id if floor_decor != null else 0, "walkable": world.grid.is_walkable(cell)})
				if normal != null and not covered.has(normal.id):
					covered.append(normal.id)
			covered.sort()
			record.merge({"coverage": coverage, "covered_normal_ids": covered})
		if prop != null:
			var bounds: AABB = prop.global_transform * prop.get_combined_aabb()
			var footprint: Vector2i = GridMath.rotated_footprint(definition.footprint, item.quarter_turns)
			var allowed: Rect2 = Rect2(Vector2(item.origin) * GridMath.CELL_SIZE, Vector2(footprint) * GridMath.CELL_SIZE).grow(0.05)
			record.merge({"aabb": [bounds.position.x, bounds.position.y, bounds.position.z, bounds.size.x, bounds.size.y, bounds.size.z],
				"floor_y": bounds.position.y, "seat_surface_height": prop.seat_surface_height(),
				"fits_footprint": allowed.encloses(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)))})
		items.append(record)
	var dining: DiningSeats.Plan = DiningSeats.derive(world.grid)
	var links: Array[Dictionary] = []
	for link: DiningSeats.SeatLink in dining.links:
		var furnishing: PlacedItem = world.grid.item(link.furnishing_item_id)
		var definition: ItemDef = furnishing.def as ItemDef
		var forward: Vector2i = GridMath.rotate_cell(Vector2i.UP, definition.footprint, furnishing.quarter_turns) \
			- GridMath.rotate_cell(Vector2i.ZERO, definition.footprint, furnishing.quarter_turns)
		var surface: PlacedItem = world.grid.item_at(link.cell + forward)
		links.append({"cell": [link.cell.x, link.cell.y], "table": link.table_item_id, "furnishing": link.furnishing_item_id,
			"built_in": link.built_in, "front_table": surface.id if surface != null else 0,
			"linked_table": world.grid.dining_table_id(link.cell), "linked_furnishing": world.grid.dining_furnishing_id(link.cell)})
	var check: EditCheck = editor.check_current()
	return {"available": true, "use_saves": main.get("use_saves"), "world_tick": world.now,
		"day": world.clock.day, "phase": int(world.clock.phase), "clock_speed": clock.get("speed"),
		"owner_level": progress.level, "build_active": main.call("is_build_active"), "paint_active": main.call("is_paint_active"),
		"catalogue_visible": catalogue.is_visible_in_tree(), "category": String(catalogue.selected_category),
		"wall": String(editor.wall_swatch_id), "floor": String(editor.floor_vibe_swatch()),
		"cache": {"supported": cache.rendering_supported(), "pending": cache.pending_count(), "cached": cache.cached_count(),
			"expected": expected["wrappers"].size(), "expected_scenes": expected["wrappers"], "cached_scenes": cached.scenes, "requests_valid": cached.valid,
			"active": cache._active_scene != null, "failed": cache._failed.size(),
			"error": cache.last_error, "icons_match": icons_match},
		"expected_cards": expected["cards"], "expected_wall_scenes": expected["wall_scenes"], "cards": cards, "onscreen_cards": onscreen, "tabs": tabs, "items": items,
		"server": _catalogue_server_evidence(world, shop, main.get_node_or_null("CameraRig/Camera3D") as Camera3D, sim.staff_spawns[&"server"]),
		"vibe": catalogue_vibe_evidence(main, world, content, editor, catalogue),
		"generated_vibe_uids": generated_uid_evidence(VIBE_UID_SOURCES),
		"dining_failures": dining.failures, "dining_links": links, "edit_ok": check.ok, "unreachable": check.unreachable}


static func catalogue_review_valid(state: Dictionary, frame: int, fixture: Dictionary) -> bool:
	var profile: Dictionary = catalogue_review_profile(StringName(fixture.get("profile", "")))
	if profile.is_empty() or fixture.get("error") != "" or fixture.get("kind") != "furnishing_fixture" \
			or state.get("available") != true or state.get("use_saves") != false or state.get("world_tick") != 0 \
			or state.get("day") != 1 or state.get("phase") != SimClock.Phase.MORNING or state.get("clock_speed") != 0 \
			or state.get("owner_level") != 6 or state.get("paint_active") != false \
			or state.get("wall") != String(profile["wall"]) or state.get("floor") != String(profile["floor"]) \
			or not _catalogue_cards_valid(state) \
			or not catalogue_vibe_valid(state.get("vibe", {}), frame) \
			or not catalogue_vibe_uids_valid(state.get("generated_vibe_uids", {})) \
			or state.get("edit_ok") != true or not (state["unreachable"] as Array).is_empty() \
			or not (state["dining_failures"] as Dictionary).is_empty() or state["dining_links"].size() != 4:
		return false
	for link: Dictionary in state["dining_links"]:
		if link["built_in"] or link["table"] == link["furnishing"] or link["front_table"] != link["table"] \
				or link["linked_table"] != link["table"] or link["linked_furnishing"] != link["furnishing"]:
			return false
	var found: int = 0
	for item: Dictionary in state["items"]:
		var index: int = (fixture["purchased_ids"] as Array).find(item["id"])
		if index < 0:
			continue
		found += 1
		if index >= (profile["items"] as Array).size():
			return false
		var wanted: Dictionary = profile["items"][index]
		var origin: Vector2i = wanted["origin"]
		if item["definition"] != String(wanted["id"]) or item["origin"] != [origin.x, origin.y] or item["turns"] != 0 \
				or item.get("catalogue_visible") != true or item.get("placement_layer") != item.get("definition_layer") \
				or item.get("solid") != item.get("definition_solid") \
				or item["rendered"] != true or item["wrapper"] != item["expected_wrapper"] or item.get("fits_footprint") != true \
				or absf(float(item.get("floor_y", INF))) > 0.0001 \
				or item["paint"] != (String(profile["body"]) if item["paintable"] else ""):
			return false
	if found != (profile["items"] as Array).size():
		return false
	if fixture["profile"] == "rustic" and not _catalogue_rug_context_valid(state, fixture):
		return false
	if frame == 120:
		return state["catalogue_visible"] == false and state["build_active"] == false \
			and (fixture["profile"] != "rustic" or _catalogue_server_valid(state["server"]))
	if frame != 90 or state["catalogue_visible"] != true or state["build_active"] != true \
			or state["category"] != String(profile["category"]) or state["onscreen_cards"] < 1:
		return false
	if not catalogue_tabs_valid(state, profile):
		return false
	var cache: Dictionary = state["cache"]
	return cache["supported"] == true and cache["pending"] == 0 and cache["active"] == false \
		and cache["failed"] == 0 and cache["error"] == "" and cache["icons_match"] == true and cache.get("requests_valid") == true and cache["cached"] >= cache["expected"] \
		and cache["cached_scenes"] == cache["expected_scenes"]


## Native tab validation is independent of thumbnail rendering, so headless
## real-Main tests can guard visible tabs without fabricating preview pixels.
static func catalogue_tabs_valid(state: Dictionary, profile: Dictionary) -> bool:
	if state["tabs"].size() != BuildCatalogue.CATEGORY_IDS.size():
		return false
	# Buy mode shows each room with items plus the player blueprint library.
	# The library is not an ItemDef room. Build tabs still stay hidden.
	var rooms: Array[String] = []
	for card: Dictionary in state.get("expected_cards", []):
		if not rooms.has(String(card.get("room", ""))):
			rooms.append(String(card.get("room", "")))
	for tab: Dictionary in state["tabs"]:
		var id: StringName = StringName(tab["id"])
		var expected_shown: bool = id == BuildCatalogue.BLUEPRINTS or rooms.has(String(id))
		if tab["text"] != BuildCatalogue.CATEGORY_LABELS.get(id, "") or tab["pressed"] != (id == profile["category"]) \
				or tab.get("shown") != expected_shown:
			return false
		if expected_shown and (tab["native"]["visible"] != true or tab["native"]["inside_clip"] != true):
			return false
	return true


## Re-evaluate the actual layout/menu/paint independently of Main's cached
## result, then read the already-created native meter without repairing it.
static func catalogue_vibe_evidence(main: Node, world: SimWorld, content: ContentDB,
		editor: ShopEditor, catalogue: BuildCatalogue) -> Dictionary:
	var menu: MenuSettings = main.get("menu_settings") as MenuSettings
	var meter: VibeMeter = catalogue.get_node_or_null("Panel/Margin/Rows/Scroll/Content/Categories/Readout/VibeMeter") as VibeMeter
	var panel: Control = catalogue.get_node_or_null("Panel") as Control
	var scroll: ScrollContainer = catalogue.get_node_or_null("Panel/Margin/Rows/Scroll") as ScrollContainer
	if not ("vibe_result" in main) or menu == null or meter == null or panel == null or scroll == null:
		return {"available": false}
	var inputs: VibeModel.Inputs = VibeInputs.capture(world.grid, content, menu.enabled_recipes(),
		editor.wall_swatch_id, editor.floor_vibe_swatch())
	var expected: VibeModel.Result = VibeModel.evaluate(inputs, VIBE_TERMS)
	var actual: VibeModel.Result = main.get("vibe_result") as VibeModel.Result
	var caption: Label = meter.caption_label
	var bar: ProgressBar = meter.score_bar
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat if bar != null else null
	var background: StyleBoxFlat = bar.get_theme_stylebox("background") as StyleBoxFlat if bar != null else null
	if caption == null or bar == null or fill == null or background == null:
		return {"available": false}
	var view: Dictionary = meter.view_state()
	var view_caption_rect: Rect2 = view.get("caption_rect", Rect2())
	var view_bar_rect: Rect2 = view.get("bar_rect", Rect2())
	var recipes: Array[String] = []
	for recipe: RecipeDef in menu.enabled_recipes():
		recipes.append(String(recipe.id))
	recipes.sort()
	return {"available": true, "expected": _vibe_result_record(expected), "main": _vibe_result_record(actual),
		"inputs": {"wall": String(editor.wall_swatch_id), "floor": String(editor.floor_vibe_swatch()),
			"menu_ids": recipes, "item_count": world.grid.items().size()},
		"meter": {"visible": meter.is_visible_in_tree(), "caption_visible": caption.is_visible_in_tree(),
			"bar_visible": bar.is_visible_in_tree(), "caption": caption.text, "value": bar.value,
			"tooltip": meter.tooltip_text, "caption_tooltip": caption.tooltip_text, "bar_tooltip": bar.tooltip_text,
			"minimum": bar.min_value, "maximum": bar.max_value, "step": bar.step, "show_percentage": bar.show_percentage,
			"native_children_match": meter.get_node_or_null("CaptionLabel") == caption and meter.get_node_or_null("ScoreBar") == bar,
			"mouse_filter": int(meter.mouse_filter), "caption_mouse_filter": int(caption.mouse_filter),
			"bar_mouse_filter": int(bar.mouse_filter), "shared_theme": meter.theme == VibeMeter.SHARED_THEME,
			"caption_color": _staff_rgba(caption.get_theme_color("font_color")),
			"fill_color": _staff_rgba(fill.bg_color), "background_color": _staff_rgba(background.bg_color),
			"panel_bounds": _staff_rect_data(_staff_pixel_rect(panel)),
			"window_bounds": _staff_rect_data(meter.get_viewport().get_final_transform() * meter.get_viewport().get_visible_rect()),
			"scroll_viewport_bounds": _staff_rect_data(_staff_scroll_viewport(scroll)),
			"bounds": _staff_rect_data(_staff_pixel_rect(meter)),
			"caption_bounds": _staff_rect_data(_staff_pixel_rect(caption)),
			"bar_bounds": _staff_rect_data(_staff_pixel_rect(bar)),
			"caption_minimum_bounds": _staff_rect_data(_staff_pixel_rect(caption, caption.get_combined_minimum_size())),
			"bar_minimum_bounds": _staff_rect_data(_staff_pixel_rect(bar, bar.get_combined_minimum_size())),
			"caption_logical_rect": _staff_rect_data(caption.get_global_rect()),
			"bar_logical_rect": _staff_rect_data(bar.get_global_rect()),
			"view_state": {"caption": view.get("caption"), "value": view.get("value"), "tooltip": view.get("tooltip"),
				"caption_rect": _staff_rect_data(view_caption_rect), "bar_rect": _staff_rect_data(view_bar_rect)}}}


static func _vibe_result_record(result: VibeModel.Result) -> Dictionary:
	if result == null:
		return {}
	return {"valid": result.valid, "reason": result.reason, "score": result.score,
		"decor_points": result.decor_points, "variety_points": result.variety_points,
		"theme_points": result.theme_points, "lamp_points": result.lamp_points, "crowding_penalty": result.crowding_penalty,
		"active_theme": String(result.active_theme), "theme_label": result.theme_label, "theme_share": result.theme_share,
		"patience_multiplier": result.patience_multiplier, "raw_review_bonus": result.raw_review_bonus,
		"arrival_theme_strength": result.arrival_theme_strength, "interior_cells": result.interior_cells,
		"occupied_normal_cells": result.occupied_normal_cells, "crowding_density": result.crowding_density}


static func _vibe_result_finite(result: Dictionary) -> bool:
	if result.get("valid") != true or result.get("reason") != "":
		return false
	if typeof(result.get("active_theme")) != TYPE_STRING or typeof(result.get("theme_label")) != TYPE_STRING \
			or typeof(result.get("interior_cells")) != TYPE_INT or typeof(result.get("occupied_normal_cells")) != TYPE_INT \
			or int(result["interior_cells"]) < 0 or int(result["occupied_normal_cells"]) < 0:
		return false
	for key: String in ["score", "decor_points", "variety_points", "theme_points", "lamp_points", "crowding_penalty",
			"theme_share", "patience_multiplier", "raw_review_bonus", "arrival_theme_strength", "crowding_density"]:
		var value: Variant = result.get(key)
		if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)):
			return false
	return float(result["score"]) >= 0.0 and float(result["score"]) <= VIBE_TERMS.score_cap


## Native content, cached view_state and Main must all agree with the fresh pure
## evaluation. Hidden frame-120 controls retain values but need not be onscreen.
static func catalogue_vibe_valid(state: Dictionary, frame: int) -> bool:
	if frame not in [90, 120]:
		return false
	var expected: Dictionary = state.get("expected", {})
	var actual: Dictionary = state.get("main", {})
	if state.get("available") != true or not _vibe_result_finite(expected) or not _vibe_result_finite(actual) or actual != expected:
		return false
	var meter: Dictionary = state.get("meter", {})
	var view: Dictionary = meter.get("view_state", {})
	var caption: String = "Vibe %d / 100" % roundi(float(expected["score"]))
	var theme: String = String(expected["theme_label"]).strip_edges()
	if String(expected["active_theme"]).is_empty() or theme.is_empty():
		theme = "No active theme"
	var tooltip: String = "Decor %d, Variety %d, Theme: %s +%d, Lamps %d, Crowding %d" % [
		roundi(float(expected["decor_points"])), roundi(float(expected["variety_points"])), theme,
		roundi(float(expected["theme_points"])), roundi(float(expected["lamp_points"])), -roundi(float(expected["crowding_penalty"]))]
	var value: Variant = meter.get("value")
	var cached_value: Variant = view.get("value")
	if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)) \
			or (typeof(cached_value) != TYPE_FLOAT and typeof(cached_value) != TYPE_INT) or not is_finite(float(cached_value)) \
			or float(value) != float(expected["score"]) or float(cached_value) != float(expected["score"]) \
			or meter.get("caption") != caption or view.get("caption") != caption \
			or meter.get("tooltip") != tooltip or meter.get("caption_tooltip") != tooltip or meter.get("bar_tooltip") != tooltip \
			or view.get("tooltip") != tooltip or meter.get("minimum") != 0.0 or meter.get("maximum") != 100.0 \
			or meter.get("step") != 0.0 or meter.get("show_percentage") != false or meter.get("native_children_match") != true \
			or meter.get("mouse_filter") != Control.MOUSE_FILTER_PASS or meter.get("caption_mouse_filter") != Control.MOUSE_FILTER_IGNORE \
			or meter.get("bar_mouse_filter") != Control.MOUSE_FILTER_IGNORE or meter.get("shared_theme") != true \
			or view.get("caption_rect") != meter.get("caption_logical_rect") or view.get("bar_rect") != meter.get("bar_logical_rect"):
		return false
	var fill: StyleBoxFlat = VibeMeter.SHARED_THEME.get_stylebox("fill", "ProgressBar") as StyleBoxFlat
	var background: StyleBoxFlat = VibeMeter.SHARED_THEME.get_stylebox("background", "ProgressBar") as StyleBoxFlat
	if meter.get("caption_color") != _staff_rgba(VibeMeter.SHARED_THEME.get_color("font_color", "Label")) \
			or meter.get("fill_color") != _staff_rgba(fill.bg_color) or meter.get("background_color") != _staff_rgba(background.bg_color):
		return false
	if frame != 90:
		return true
	var panel: Rect2 = _staff_rect(meter, "panel_bounds")
	var window: Rect2 = _staff_rect(meter, "window_bounds")
	var viewport: Rect2 = _staff_rect(meter, "scroll_viewport_bounds")
	var bounds: Rect2 = _staff_rect(meter, "bounds")
	if meter.get("visible") != true or meter.get("caption_visible") != true or meter.get("bar_visible") != true \
			or not window.has_area() or not panel.has_area() or not viewport.has_area() or not bounds.has_area() \
			or not window.grow(0.5).encloses(panel) \
			or not panel.grow(0.5).encloses(viewport) or not panel.grow(0.5).encloses(bounds) or not viewport.grow(0.5).encloses(bounds):
		return false
	for key: String in ["caption", "bar"]:
		var control: Rect2 = _staff_rect(meter, key + "_bounds")
		var minimum: Rect2 = _staff_rect(meter, key + "_minimum_bounds")
		if not control.has_area() or not minimum.has_area() or not bounds.grow(0.5).encloses(control) \
				or not viewport.grow(0.5).encloses(control) or control.size.x < minimum.size.x - 0.5 or control.size.y < minimum.size.y - 0.5:
			return false
	return true


## Provenance is read-only and scoped separately from old catalogue/loan/staff
## records. A complete import must supply all nine real sidecars and cache IDs.
static func catalogue_vibe_uids_valid(evidence: Dictionary) -> bool:
	var entries: Array = evidence.get("entries", [])
	if evidence.get("read_only") != true or evidence.get("complete_match") != true or entries.size() != VIBE_UID_SOURCES.size():
		return false
	var seen: Dictionary[String, bool] = {}
	for index: int in range(VIBE_UID_SOURCES.size()):
		var row: Dictionary = entries[index]
		var registered: String = row.get("registered_id", "")
		var sidecar: String = row.get("sidecar_text", "")
		if row.get("source") != VIBE_UID_SOURCES[index] or row.get("uid_path") != VIBE_UID_SOURCES[index] + ".uid" \
				or row.get("source_exists") != true or row.get("sidecar_exists") != true or row.get("sidecar_readable") != true \
				or row.get("registered_known") != true or row.get("matches_registered") != true or row.get("status") != "match" \
				or not [OK, ERR_FILE_EOF].has(row.get("read_error")) \
				or not registered.is_valid_int() or int(registered) < 0 or seen.has(registered) or sidecar.strip_edges().is_empty() \
				or sidecar.strip_edges() != row.get("registered_text") or row.get("registered_text") != ResourceUID.id_to_text(int(registered)):
			return false
		seen[registered] = true
	return true


static func _catalogue_cards_valid(state: Dictionary) -> bool:
	var expected: Dictionary[String, Dictionary] = {}
	var wrappers: Array[String] = []
	for definition: Dictionary in state.get("expected_cards", []):
		var id: String = definition.get("id", "")
		if id.is_empty() or expected.has(id):
			return false
		expected[id] = definition
		var scene: String = definition.get("scene", "")
		if not scene.is_empty() and not wrappers.has(scene):
			wrappers.append(scene)
	for scene: Variant in state.get("expected_wall_scenes", []):
		if not wrappers.has(String(scene)):
			wrappers.append(String(scene))
	wrappers.sort()
	var cards: Array = state.get("cards", [])
	if expected.is_empty() or cards.size() != expected.size():
		return false
	var seen: Dictionary[String, bool] = {}
	for card: Dictionary in cards:
		var id: String = card.get("id", "")
		if not expected.has(id) or seen.has(id) or card.get("catalogue_visible") != true:
			return false
		seen[id] = true
		var definition: Dictionary = expected[id]
		var locked: bool = int(definition["unlock_level"]) > int(state["owner_level"])
		# FK-085 tiles show the price (or unlock level) under the picture.
		var text: String = "Level %d" % definition["unlock_level"] if locked else Fmt.money(int(definition["price"]))
		if card.get("scene") != definition["scene"] or String(card.get("text", "")).strip_edges() != text or card.get("disabled") != locked:
			return false
	var cache: Dictionary = state.get("cache", {})
	return cache.get("expected") == wrappers.size() and cache.get("expected_scenes") == wrappers


## Verify both captured item footprints and the actual per-cell layer index.
## The rug owns no blocking; the normal table/chairs retain their own solidity.
static func _catalogue_rug_context_valid(state: Dictionary, fixture: Dictionary) -> bool:
	var rug: Dictionary = {}
	for item: Dictionary in state["items"]:
		if item["definition"] == "rug_rectangle" and (fixture["purchased_ids"] as Array).has(item["id"]):
			if not rug.is_empty():
				return false
			rug = item
	if rug.is_empty() or rug.get("placement_layer") != ItemDef.PlacementLayer.FLOOR_DECOR or rug.get("solid") != false:
		return false
	var cells: Array = rug.get("cells", [])
	var coverage: Array = rug.get("coverage", [])
	if cells.is_empty() or coverage.size() != cells.size():
		return false
	var normals: Dictionary[Vector2i, Dictionary] = {}
	var ids: Array[int] = []
	var tables: int = 0
	var chairs: int = 0
	for item: Dictionary in state["items"]:
		if item.get("placement_layer") != ItemDef.PlacementLayer.NORMAL:
			continue
		var overlaps: bool = false
		var all_covered: bool = true
		for cell: Array in item["cells"]:
			overlaps = overlaps or cells.has(cell)
			all_covered = all_covered and cells.has(cell)
		if not overlaps:
			continue
		if not all_covered or not (fixture["purchased_ids"] as Array).has(item["id"]):
			return false
		if item["category"] == ItemDef.Category.TABLE:
			tables += 1
		elif item["category"] == ItemDef.Category.CHAIR:
			chairs += 1
		else:
			return false
		ids.append(int(item["id"]))
		for cell: Array in item["cells"]:
			var key: Vector2i = Vector2i(int(cell[0]), int(cell[1]))
			if normals.has(key):
				return false
			normals[key] = item
	ids.sort()
	if tables != 1 or chairs != 2 or rug.get("covered_normal_ids") != ids:
		return false
	var seen: Dictionary[Vector2i, bool] = {}
	for row: Dictionary in coverage:
		var cell: Array = row["cell"]
		var key: Vector2i = Vector2i(int(cell[0]), int(cell[1]))
		if not cells.has(cell) or seen.has(key) or row.get("floor_decor") != rug["id"]:
			return false
		seen[key] = true
		var normal: Dictionary = normals.get(key, {})
		if row.get("normal") != normal.get("id", 0) or row.get("walkable") != (not bool(normal.get("solid", false))):
			return false
	return true


## Read the existing server and native rig without moving, animating or warming
## up the simulation. Visibility/frustum fields still require image review.
static func _catalogue_server_evidence(world: SimWorld, shop: ShopView, camera: Camera3D, post: Vector2i) -> Dictionary:
	for agent: SimAgent in world.agents:
		if not agent is StaffAgent or agent is OwnerAgent or agent.role != &"server":
			continue
		var person: PersonView = shop.agent_nodes.get(agent.id) as PersonView
		var record: Dictionary = {"available": true, "id": agent.id, "role": String(agent.role),
			"cell": [agent.cell.x, agent.cell.y], "expected_post": [post.x, post.y], "native_person": person != null,
			"expected_model": String(PersonPresentation.model_for(agent.role, agent.id))}
		if person != null:
			record.merge({"visible": person.is_visible_in_tree(), "native_role": String(person.role),
				"model": String(person.model_name()), "clip": String(person.current_clip()),
				"model_visible": person._model != null and person._model.is_visible_in_tree(),
				"feet": _point_evidence(person.global_position, camera),
				"head": _point_evidence(person.global_transform * person.head_anchor_position(), camera)})
		if camera != null:
			var size: Vector2 = camera.get_viewport().get_visible_rect().size
			record["viewport_size"] = [size.x, size.y]
		return record
	return {"available": false}


static func _catalogue_server_valid(server: Dictionary) -> bool:
	var post: Variant = server.get("expected_post")
	if not post is Array or post.size() != 2 or not post[0] is int or not post[1] is int:
		return false
	if server.get("available") != true or server.get("native_person") != true \
			or server.get("visible") != true or server.get("model_visible") != true \
			or server.get("role") != "server" or server.get("native_role") != "server" or server.get("cell") != post \
			or server.get("clip") != "idle" or String(server.get("model", "")).is_empty() \
			or server.get("model") != server.get("expected_model"):
		return false
	var extent: Array = server.get("viewport_size", [])
	if extent.size() != 2 or float(extent[0]) <= 0.0 or float(extent[1]) <= 0.0:
		return false
	for name: String in ["feet", "head"]:
		var point: Dictionary = server.get(name, {})
		var screen: Variant = point.get("screen")
		if point.get("in_frustum") != true or not screen is Array or screen.size() != 2 \
				or not is_finite(float(screen[0])) or not is_finite(float(screen[1])) \
				or float(screen[0]) < 0.0 or float(screen[1]) < 0.0 \
				or float(screen[0]) >= float(extent[0]) or float(screen[1]) >= float(extent[1]):
			return false
	return true


static func _loan_control_evidence(control: Control) -> Dictionary:
	var viewport: Viewport = control.get_viewport()
	var bounds: Rect2 = viewport.get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	var clip: Rect2 = Rect2(Vector2.ZERO, Vector2(viewport.get_visible_rect().size))
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			var parent: Control = ancestor as Control
			clip = clip.intersection(viewport.get_final_transform() * parent.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, parent.size))
		ancestor = ancestor.get_parent()
	return {"text": (control as Label).text if control is Label else "", "visible": control.is_visible_in_tree(),
		"rect": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"inside_clip": bounds.has_area() and clip.grow(1.0).encloses(bounds)}


static func loan_review_valid(state: Dictionary, frame: int, fixture: Dictionary) -> bool:
	if fixture.get("kind") != "financial_fixture" or fixture.get("error") != "" \
			or fixture.get("requested_ticks") != 3 or int(fixture.get("actual_ticks", 0)) not in range(1, 4) \
			or state.get("available") != true or state.get("clock_speed") != 0 or state.get("use_saves") != false \
			or int(state.get("principal", "0")) <= 0 or state.get("has_borrowed") != true \
			or state.get("last_settled_day") != fixture.get("closed_day") \
			or state.get("principal") != fixture.get("closed_principal"):
		return false
	var hud: Dictionary = state["loan_hud"]
	if hud["visible"] != true or hud["inside_clip"] != true or hud["text"] != "Loan %s" % Fmt.money(int(state["principal"])):
		return false
	if frame == 90:
		return state["day"] == 2 and state["phase"] == SimClock.Phase.MORNING \
			and state["report_present"] == false and state["report"]["visible"] == false \
			and state["notice"]["visible"] == false and state["operating_headline"]["visible"] == false
	# Keep the original cash bridge and check the served-food bridge separately.
	# Optional/malformed new evidence fails closed before financial arithmetic.
	for field: String in ["report_purchase_basis_operating_profit", "report_ingredient_net", "report_food_cost"]:
		var value: Variant = state.get(field, null)
		if not value is int:
			if not value is float or not is_finite(float(value)) \
					or absf(float(value)) > 9007199254740991.0 or floorf(float(value)) != float(value):
				return false
		if field == "report_food_cost" and float(value) < 0.0:
			return false
	if frame != 12 or state["day"] != 1 or state["phase"] != SimClock.Phase.CLOSED \
			or state["report_present"] != true or state["report_day"] != 1 or state["report_first_advance"] != true \
			or state["report"]["visible"] != true or state["notice"]["visible"] != true \
			or state["notice"]["inside_clip"] != true or state["notice"]["text"] != LOAN_NOTICE \
			or state.get("report_food_cost_recorded", false) != true \
			or not state.has("report_purchase_basis_operating_profit") \
			or not state.has("report_ingredient_net") or not state.has("report_food_cost") \
			or state["report_bank_advance"] != int(state["principal"]) \
			or state["report_cash_change"] != state["settled_day_cash_change"] \
			or state["report_cash_change"] != state["report_purchase_basis_operating_profit"] + state["report_bank_advance"] \
			or state["report_operating_profit"] != state["report_purchase_basis_operating_profit"] \
				- state["report_ingredient_net"] - state["report_food_cost"] \
			or state["operating_headline"]["visible"] != true or state["operating_headline"]["inside_clip"] != true \
			or state["operating_headline"]["text"] != "%s operating profit" % Fmt.money(int(state["report_operating_profit"])):
		return false
	var bank_flow: bool = false
	for flow: Dictionary in state["bank_flows"]:
		bank_flow = bank_flow or (flow["category"] == String(Ledger.BANK_LOAN) and flow["amount"] == state["report_bank_advance"])
	for row: Dictionary in state["bank_labels"]:
		if bank_flow and row["title"]["text"] == "Bank loan" and row["title"]["visible"] == true \
				and row["title"]["inside_clip"] == true and row["amount"]["visible"] == true \
				and row["amount"]["inside_clip"] == true and row["amount"]["text"] == Fmt.money(int(state["principal"])):
			return true
	return false


## The HUD sequence reserves its window-size option and two-frame schedule.
## Legacy options pass through unchanged and do not instantiate a SceneTree here.
static func hud_layout_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"enabled": false, "window_size": Vector2i(1600, 900), "error": ""}
	var window_seen: bool = false
	for argument: String in arguments:
		if argument.begins_with("--hud-layout"):
			if argument != "--hud-layout" or result["enabled"]:
				result["error"] = "--hud-layout is a single flag without a value"
				return result
			result["enabled"] = true
		elif argument.begins_with("--window-size"):
			if window_seen or argument not in ["--window-size=1280x720", "--window-size=1600x900"]:
				result["error"] = "--window-size supports one 1280x720 or 1600x900 value"
				return result
			window_seen = true
			result["window_size"] = Vector2i(1280, 720) if argument.ends_with("1280x720") else Vector2i(1600, 900)
	if not result["enabled"]:
		if window_seen:
			result["error"] = "--window-size requires --hud-layout"
		return result
	var speed_count: int = 0
	var frames_count: int = 0
	for argument: String in arguments:
		if argument.begins_with("--speed"):
			speed_count += 1
			if argument != "--speed=0":
				result["error"] = "--hud-layout requires --speed=0"
		elif argument.begins_with("--frames"):
			frames_count += 1
			if argument != "--frames=12,90":
				result["error"] = "--hud-layout requires --frames=12,90"
		elif argument.begins_with("--scene") and argument != "--scene=res://src/world/main.tscn":
			result["error"] = "--hud-layout requires the actual Main scene"
		for prefix: String in ["--open", "--fast", "--select", "--assign-owner", "--f3", "--menu", "--staff", "--stock", "--settings", "--report", "--build", "--paint", "--quarter", "--door-queue", "--loan-review", "--catalogue-review", "--milestone-review"]:
			if argument.begins_with(prefix):
				result["error"] = "--hud-layout cannot combine with other view or service options"
	if speed_count != 1 or frames_count != 1:
		result["error"] = "--hud-layout requires one --speed=0 and one --frames=12,90"
	return result


## One paused screenshot of the production F1 shortcuts path. Only the output
## directory may repeat because screenshot.sh supplies it as well.
static func shortcuts_capture_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"enabled": false, "error": ""}
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	for argument: String in arguments:
		if argument == "--shortcuts":
			if result["enabled"]:
				result["error"] = "--shortcuts is a single flag without a value"
				return result
			result["enabled"] = true
	if not result["enabled"]:
		return result
	for argument: String in arguments:
		if argument == "--shortcuts" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=12":
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		else:
			result["error"] = "--shortcuts requires paused Main frame 12 without other options"
			return result
	if speeds != 1 or frames != 1 or scenes > 1:
		result["error"] = "--shortcuts requires one --speed=0 and one --frames=12"
	return result


func _process(_delta: float) -> bool:
	if _finished:
		return true
	if _capture_pending:
		# A disabled/non-drawing viewport must fail instead of waiting forever.
		_capture_wait_frames += 1
		if _capture_wait_frames > MAX_CAPTURE_WAIT_FRAMES:
			_fail_capture("viewport did not finish drawing the pending capture")
		return _finished
	_frames += 1
	if _frames == 8 and not _signature_review.is_empty():
		_prepare_signature_review_layout()
		if _failed:
			return true
	if _frames == 2 and _stock and _open:
		# Explicit morning fixture: today's soup stock is gone and its
		# auto-reorder is off, so the real service sells Tomato soup out.
		var stock: Stock = root.get_node("Economy").get("stock") as Stock
		if stock == null or not bool(_main.call("stock_set_auto", &"soup_stock", false)) \
				or not stock.take(&"soup_stock", stock.count(&"soup_stock")):
			_fail_capture("--stock --report could not prepare its sold-out fixture")
			return true
	if _frames == 3:
		# Autoloads aren't compile-time identifiers in a --script main loop.
		var clock: Node = root.get_node("Clock")
		if _shortcuts:
			# Deliver the real F1 key through the viewport so Main's production
			# unhandled-input path opens the panel and gives it focus.
			_settings_key(KEY_F1, true)
			_settings_key(KEY_F1, false)
			_shortcuts_input = {"delivery": "Viewport.push_input", "key": "F1", "frame": _frames}
			if not bool(_main.call("is_shortcuts_visible")):
				_fail_capture("physical F1 did not open the actual Shortcuts panel")
				return true
		if not _walls.is_empty():
			# Walls are a closed-phase edit, so build them before any --open service.
			_configure_walls()
			if _failed:
				return true
		if not _expand.is_empty():
			# Floor is a closed-phase edit too: build it before any --open service.
			_configure_expand()
			if _failed:
				return true
		if not _rooms.is_empty():
			# Rooms, floor and the restroom are closed-phase edits too.
			_configure_rooms()
			if _failed:
				return true
		if _restroom_review:
			var refusal: String = RESTROOM_REVIEW.prepare(_main, root)
			if not refusal.is_empty():
				_fail_capture(refusal)
				return true
		if _street_front_review:
			_street_front_fixture = STREET_FRONT_REVIEW.prepare(_main, root)
			if not String(_street_front_fixture.get("error", "")).is_empty():
				_fail_capture(String(_street_front_fixture["error"]))
				return true
		if _walls_review:
			_walls_fixture = WALLS_REVIEW.prepare(_main, root)
			if not String(_walls_fixture.get("error", "")).is_empty():
				_fail_capture(String(_walls_fixture["error"]))
				return true
		if _floors_review:
			_floors_fixture = FLOORS_REVIEW.prepare(_main, root)
			if not String(_floors_fixture.get("error", "")).is_empty():
				_fail_capture(String(_floors_fixture["error"]))
				return true
		if _property_review:
			_property_fixture = PROPERTY_REVIEW.prepare(_main, root)
			if not String(_property_fixture.get("error", "")).is_empty():
				_fail_capture(String(_property_fixture["error"]))
				return true
		if _open:
			(clock.get("sim") as SimClock).start_service()
		clock.call("set_speed", _speed)
		_configure_camera()
		if not _signature_review.is_empty():
			_signature_fixture = _prepare_signature_review()
			if not String(_signature_fixture.get("error", "")).is_empty():
				_fail_capture(String(_signature_fixture["error"]))
				return true
		if _menu_boards_review:
			_menu_boards_fixture = MENU_BOARDS_REVIEW.prepare(_main, root)
			if not String(_menu_boards_fixture.get("error", "")).is_empty():
				_fail_capture(String(_menu_boards_fixture["error"]))
				return true
		if not _neighbourhood_mode.is_empty():
			_neighbourhood_fixture = NEIGHBOURHOOD_REVIEW.prepare(_main, root, _neighbourhood_mode)
			if not String(_neighbourhood_fixture["error"]).is_empty():
				_fail_capture(_neighbourhood_fixture["error"])
				return true
		if not _weather_mode.is_empty():
			_weather_fixture = WEATHER_REVIEW.prepare(_main, root, _weather_mode)
			if not String(_weather_fixture["error"]).is_empty():
				_fail_capture(_weather_fixture["error"])
				return true
		if _joined_tables_review:
			_joined_tables_fixture = JOINED_TABLES_REVIEW.prepare(_main, root)
			if not String(_joined_tables_fixture["error"]).is_empty():
				_fail_capture(_joined_tables_fixture["error"])
				return true
		if _restroom_review:
			RESTROOM_REVIEW.focus(_main, false)
		if _street_front_review:
			STREET_FRONT_REVIEW.focus(_main)
		if not _rooms.is_empty() and _quarter < 0:
			(_main.get_node("ShopView") as ShopView).set_wall_mode(ShopView.WallMode.UP)
		if _rooms == "tool" or _rooms == "refused":
			_begin_rooms_view()
			if _failed:
				return true
		if _walls == "room" and _quarter < 0:
			(_main.get_node("ShopView") as ShopView).set_wall_mode(ShopView.WallMode.UP)
		if _walls == "place":
			_begin_wall_drag()
			if _failed:
				return true
		if _expand == "shop" and _quarter < 0:
			(_main.get_node("ShopView") as ShopView).set_wall_mode(ShopView.WallMode.UP)
		if _expand == "drag":
			_begin_floor_drag()
			if _failed:
				return true
		if _failed:
			return true
		if _diner_review:
			_diner_fixture = DINER_REVIEW.prepare(_main, root)
			if not String(_diner_fixture.get("error", "")).is_empty():
				_fail_capture(String(_diner_fixture["error"]))
				return true
		if not _lease_mode.is_empty():
			_lease_fixture = LEASE_REVIEW.prepare(_main, root, _lease_mode)
			if not String(_lease_fixture["error"]).is_empty():
				_fail_capture(_lease_fixture["error"])
				return true
			_main.set_process(false)
		if _loan_review:
			_loan_fixture = prepare_loan_review(_main, root)
			if not String(_loan_fixture["error"]).is_empty():
				_fail_capture(_loan_fixture["error"])
				return true
		if _milestone_review:
			_milestone_fixture = prepare_milestone_review(_main, root)
			if not String(_milestone_fixture["error"]).is_empty():
				_fail_capture(String(_milestone_fixture["error"]))
				return true
		if _collections_review:
			_collections_fixture = prepare_collections_review(_main, root)
			if not String(_collections_fixture["error"]).is_empty():
				_fail_capture(String(_collections_fixture["error"]))
				return true
		if not _catalogue_profile.is_empty():
			_catalogue_fixture = prepare_catalogue_review(_main, root, _catalogue_profile)
			if not String(_catalogue_fixture["error"]).is_empty():
				_fail_capture(_catalogue_fixture["error"])
				return true
		if not _blueprint_profile.is_empty():
			_blueprint_fixture = BLUEPRINT_REVIEW.prepare(_main, _blueprint_profile)
			if not String(_blueprint_fixture.get("error", "")).is_empty():
				_fail_capture(_blueprint_fixture["error"])
				return true
			if _blueprint_profile == "ghost":
				var camera: Camera3D = _main.get_node("CameraRig/Camera3D") as Camera3D
				_build_pointer = camera.unproject_position(GridMath.cell_to_world(BLUEPRINT_REVIEW.target_origin()))
		_configure_inspection()
		if _failed:
			return true
		if _menu:
			if not _main.has_method("set_menu_visible") or not _main.has_method("is_menu_visible") or not bool(_main.call("set_menu_visible", true)):
				_fail_capture("--menu requires the scene's morning menu APIs")
				return true
		if _staff:
			if not _main.has_method("set_staff_visible") or not bool(_main.call("set_staff_visible", true)):
				_fail_capture("--staff requires the scene's morning staff API")
				return true
		if _stock and not _open:
			if not _main.has_method("set_stock_visible") or not bool(_main.call("set_stock_visible", true)):
				_fail_capture("--stock requires the scene's morning stock API")
				return true
		if _settings:
			_configure_settings()
			if _failed:
				return true
		if _hud_layout:
			_open_settings_control(true, _hud_layout_scale)
			if _failed:
				return true
		if not _build.is_empty():
			_configure_build()
			if _failed:
				return true
		if _paint:
			_configure_paint()
			if _failed:
				return true
	if _collections_review and _frames == 8:
		var goals_scroll: ScrollContainer = _main.get_node_or_null("Overlay/GoalsPanel/Panel/Content/Scroll") as ScrollContainer
		var collections_heading: Label = _main.get_node_or_null("Overlay/GoalsPanel/Panel/Content/Scroll/List/CollectionsHeading") as Label
		if goals_scroll == null or collections_heading == null or not collections_heading.visible:
			_fail_capture("collections review has no real visible Goals section to scroll to")
			return true
		goals_scroll.scroll_vertical = int(collections_heading.position.y)
	if _stock and _report_requested:
		_scroll_report_to_low_stock()
	if _report_slowest_requested:
		_scroll_report_to_slowest_seller()
	if _floors_review and _frames == 3:
		# The floors without grid lines first, as a player sees them with G.
		var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
		if rig != null and rig.grid_visible:
			rig.toggle_grid()
	if _floors_review and _frames == FLOORS_DRAG_FRAME:
		var drag: Dictionary = FLOORS_REVIEW.begin_drag(_main, root)
		if not String(drag.get("error", "")).is_empty():
			_fail_capture(String(drag["error"]))
			return true
		_build_pointer = drag["pointer"]
	if _floors_review and _frames > FLOORS_DRAG_FRAME:
		_hold_build_pointer()
	if _restroom_review and _frames == 20:
		RESTROOM_REVIEW.focus(_main, true)
	if _walls_review and _frames == WALLS_REVIEW.WALL_UP_FRAME:
		var wall_drag: Dictionary = WALLS_REVIEW.begin_drag(_main, root)
		if not String(wall_drag.get("error", "")).is_empty():
			_fail_capture(String(wall_drag["error"]))
			return true
		_build_pointer = wall_drag["pointer"]
	if _walls_review and _frames == WALLS_REVIEW.DOWN_FRAME:
		WALLS_REVIEW.walls_down(_main)
	if _walls_review and _frames == WALLS_REVIEW.HANG_FRAME:
		var hang: Dictionary = WALLS_REVIEW.begin_hang(_main, root)
		if not String(hang.get("error", "")).is_empty():
			_fail_capture(String(hang["error"]))
			return true
		_build_pointer = hang["pointer"]
	if _walls_review and _frames > WALLS_REVIEW.WALL_UP_FRAME and _frames < WALLS_REVIEW.DOWN_FRAME:
		_hold_build_pointer()
	if _menu_boards_review and _frames == 20:
		var theme_view: Dictionary = MENU_BOARDS_REVIEW.show_menu_theme(_main)
		if not String(theme_view.get("error", "")).is_empty():
			_fail_capture(String(theme_view["error"]))
			return true
	if _diner_review and _frames == 24:
		_diner_fixture = DINER_REVIEW.furnish(_main, root, _diner_fixture)
		if not String(_diner_fixture.get("error", "")).is_empty():
			_fail_capture(String(_diner_fixture["error"]))
			return true
	if not _catalogue_profile.is_empty() and _frames == 96:
		if not bool(_main.call("set_build_active", false)):
			_fail_capture("catalogue review could not return to the furnished world")
			return true
	if _hud_layout and _frames == 24:
		_hud_layout_scale = 150
		_open_settings_control(true, _hud_layout_scale)
		if _failed:
			return true
	if _loan_review and _frames == 24:
		var clock: Node = root.get_node_or_null("Clock")
		var time: SimClock = clock.get("sim") as SimClock if clock != null else null
		if time == null or not time.next_day():
			_fail_capture("loan review could not enter the real next morning")
			return true
		_loan_fixture["next_day_frame"] = _frames
	if _milestone_review and _frames == 24:
		_milestone_fixture = advance_milestone_review(_main, root, _milestone_fixture)
		if not String(_milestone_fixture.get("error", "")).is_empty():
			_fail_capture(String(_milestone_fixture["error"]))
			return true
	if ((_settings_world or _hud_layout) and _frames == 8) or (_hud_layout and _frames == 29):
		_close_settings_with_keyboard()
		if _failed:
			return true
	if ((_settings_world or _hud_layout) and _frames == 9) or (_hud_layout and _frames == 30):
		_settings_keyboard["settings_closed"] = not bool(_main.call("is_settings_visible"))
		_settings_keyboard["menu_visible"] = _main.call("is_menu_visible")
		_settings_keyboard["verification_frame"] = _frames
		if _settings_keyboard["settings_closed"] != true or _settings_keyboard["menu_visible"] != false:
			_fail_capture("native Close acceptance did not return from Settings to the world")
			return true
	if (not _build.is_empty() or _walls == "place" or _expand == "drag" or _rooms == "tool" or _rooms == "refused" or _blueprint_profile == "ghost") \
			and _frames >= 3:
		_hold_build_pointer()
	if _rooms == "restroom" and _frames > 3 and not _rooms_paused:
		_pause_on_restroom_walk()
	if _joined_tables_review and _frames == 24:
		_joined_tables_fixture = JOINED_TABLES_REVIEW.begin_booking_service(_main, root, _joined_tables_fixture)
		if not String(_joined_tables_fixture.get("error", "")).is_empty():
			_fail_capture(String(_joined_tables_fixture["error"]))
			return true
	if _fast > 0 and _frames > 3 and _main.has_method("run_ticks"):
		_main.call("run_ticks", _fast)
	if not _selection.is_empty() and _frames >= 3:
		_select_live_agent()
		if _failed:
			return true
	_finish_requested = _frames >= _shots.max()
	if _collections_review and _finish_requested:
		_finish_requested = _collections_review_ready()
		if _failed:
			return true
	if (_shots.has(_frames) and not _collections_review) or (_collections_review and _finish_requested):
		if _door_queue:
			_focus_door_queue()
			if _failed:
				return true
		if _assign_owner:
			_prepare_owner_capture()
			if _failed:
				return true
		_queue_capture()
	if _finish_requested and not _capture_pending:
		_finish_capture()
	return _finished


func _prepare_signature_review() -> Dictionary:
	var world: SimWorld = _capture_world()
	var menu: MenuSettings = _main.get("menu_settings") as MenuSettings if "menu_settings" in _main else null
	var signature_state: Object = _main.get("signature_state") as Object if "signature_state" in _main else null
	if world == null or menu == null or signature_state == null or world.clock.phase != SimClock.Phase.MORNING \
			 or world.now != 0 or bool(_main.get("use_saves")) or int(_main.get("new_game_seed_override")) != 1:
		return {"error": "signature review needs a fresh unsaved seed-1 morning and the Main signature API"}
	if not _main.has_method("menu_recipe_details") or not _main.has_method("menu_set_signature"):
		return {"error": "signature review needs Main menu_recipe_details and menu_set_signature"}
	var enabled: Array[RecipeDef] = menu.enabled_recipes()
	if enabled.is_empty():
		return {"error": "signature review needs one enabled recipe"}
	var recipe: RecipeDef = enabled[0]
	var all_details: Dictionary = _main.call("menu_recipe_details")
	var recipe_details: Dictionary = all_details.get(recipe.id, {})
	var signature_details: Dictionary = recipe_details.get("signature", {})
	var threshold: int = int(signature_details.get("unlock_sales", 0))
	var current_sales: int = int(signature_state.call("sales_for", recipe.id))
	if threshold < 1 or current_sales < 0:
		return {"error": "signature review cannot read the authored paid-sales threshold"}
	var seeded_sales: int = maxi(0, threshold - current_sales)
	if seeded_sales > 0 and not bool(signature_state.call("record_sale", recipe.id, seeded_sales)):
		return {"error": "signature review could not seed the explicit unsaved paid-sales fixture"}
	if not bool(_main.call("menu_set_signature", recipe.id)):
		return {"error": "Main refused the eligible signature fixture through its public request path"}
	if _main.has_method("refresh_presentation"):
		_main.call("refresh_presentation")
	var panel: MenuPanel = _main.get_node_or_null("Overlay/MenuPanel") as MenuPanel
	if panel == null or not panel.select_recipe(recipe.id):
		return {"error": "signature review could not select the dish in the actual Menu panel"}
	var fixture: Dictionary = {"recipe_id": String(recipe.id), "display_name": recipe.display_name,
		"seed": 1, "use_saves": false, "seeded_prior_paid_sales": seeded_sales,
		"sales_before_seed": current_sales, "unlock_sales": threshold,
		"selection_path": "Main.menu_set_signature", "counter_path": "SignatureState.record_sale",
		"selection_unsaved": true, "played_sales_claimed": false, "actual_service_days": 0}
	if _signature_review == "menu":
		var anchor: Vector3i = Vector3i(1, 6, 3)
		if not bool(_main.call("shop_hang", &"menu_board", anchor)) \
				 or not bool(_main.call("shop_menu_board_section", anchor, recipe.menu_section())):
			return {"error": "signature review could not place the real menu board in the recipe section"}
		var shop: ShopView = _main.get_node_or_null("ShopView") as ShopView
		if shop == null:
			return {"error": "signature menu fixture has no ShopView"}
		shop.set_wall_mode(ShopView.WallMode.CUTAWAY)
		_main.call("clear_selection")
		if not bool(_main.call("set_menu_visible", true)):
			return {"error": "signature review could not open the actual Menu panel"}
		var board: ItemVisual = shop.wall_finish_view.item_nodes.get(anchor) as ItemVisual if shop.wall_finish_view != null else null
		var label: Label3D = board.prop.get_node_or_null(^"WallMount/MenuText") as Label3D if board != null and board.prop != null else null
		var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
		if label == null or rig == null:
			return {"error": "signature menu fixture has no placed board label or camera"}
		rig.minimum_zoom = 2.4
		rig.initial_yaw_degrees = 90.0
		rig.pitch_degrees = 25.0
		rig.frame_area(Vector2(label.global_position.x, label.global_position.z), Vector2(12.0, 12.0), 2.4, true)
		rig.position.y = 0.4
		rig.set_process(false)
		fixture["anchor"] = [anchor.x, anchor.y, anchor.z]
		fixture["menu_snapshot"] = menu.to_dict()
		fixture["state_snapshot"] = signature_state.call("to_dict")
		fixture["world_tick_at_setup"] = world.now
		return fixture
	var clock_node: Node = root.get_node_or_null("Clock")
	var sim_clock: SimClock = clock_node.get("sim") as SimClock if clock_node != null else null
	if sim_clock == null or not sim_clock.start_service():
		return {"error": "signature demand fixture could not start one ordinary service day"}
	var batches: int = 0
	while world.clock.phase != SimClock.Phase.CLOSED and batches < 30:
		_main.call("run_ticks", 1000)
		batches += 1
	if world.clock.phase != SimClock.Phase.CLOSED or not ("shown_report" in _main):
		return {"error": "signature demand fixture did not close one ordinary service day within 30000 ticks"}
	var report: DayReport = _main.get("shown_report") as DayReport
	if report == null:
		return {"error": "signature demand fixture did not produce an actual DayReport"}
	var section: Control = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll/Content/DemandForecast") as Control
	var scroll: ScrollContainer = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll") as ScrollContainer
	if section == null or scroll == null or not section.visible:
		return {"error": "the real Evening Report did not show its demand section"}
	fixture["actual_service_days"] = 1
	fixture["report_day"] = report.day
	fixture["ticks"] = world.now
	fixture["selection_unsaved"] = true
	fixture["played_sales_claimed"] = false
	fixture["world_tick_at_setup"] = world.now
	fixture["report_snapshot"] = report.to_dict().duplicate(true)
	fixture["state_snapshot"] = signature_state.call("to_dict")
	fixture["menu_snapshot"] = menu.to_dict()
	return fixture


func _prepare_signature_review_layout() -> void:
	if _signature_review == "menu":
		var panel: MenuPanel = _main.get_node_or_null("Overlay/MenuPanel") as MenuPanel
		var panel_rect: Control = panel.get_node_or_null("Panel") as Control if panel != null else null
		var shop: ShopView = _main.get_node_or_null("ShopView") as ShopView
		var anchor: Vector3i = Vector3i(int(_signature_fixture.get("anchor", [1, 6, 3])[0]),
			int(_signature_fixture.get("anchor", [1, 6, 3])[1]), int(_signature_fixture.get("anchor", [1, 6, 3])[2]))
		var board: ItemVisual = shop.wall_finish_view.item_nodes.get(anchor) as ItemVisual \
				if shop != null and shop.wall_finish_view != null else null
		var label: Label3D = board.prop.get_node_or_null(^"WallMount/MenuText") as Label3D \
				if board != null and board.prop != null else null
		var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
		var camera: Camera3D = rig.get_node_or_null("Camera3D") as Camera3D if rig != null else null
		if panel_rect == null or label == null or camera == null or rig == null:
			_fail_capture("signature menu framing could not read the actual Menu rect, board or camera")
			return
		var viewport_rect: Rect2 = root.get_viewport().get_visible_rect()
		var menu_rect: Rect2 = panel_rect.get_global_rect()
		if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or viewport_rect.size.x <= 0.0 \
				or viewport_rect.size.y <= 0.0 or camera.size <= 0.0 \
				or menu_rect.position.x <= viewport_rect.position.x:
			_fail_capture("signature menu framing has no orthographic view or actual left margin")
			return
		var left_margin: Rect2 = Rect2(viewport_rect.position,
			Vector2(menu_rect.position.x - viewport_rect.position.x, viewport_rect.size.y))
		if not left_margin.has_area():
			_fail_capture("signature menu has no visible left margin for its board")
			return
		var board_screen: Vector2 = camera.unproject_position(label.global_position)
		var horizontal_span: float = camera.size
		if camera.keep_aspect == Camera3D.KEEP_HEIGHT:
			horizontal_span *= viewport_rect.size.x / viewport_rect.size.y
		var world_shift: float = (board_screen.x - left_margin.get_center().x) * horizontal_span / viewport_rect.size.x
		rig.global_position += camera.global_transform.basis.x.normalized() * world_shift
		rig.force_update_transform()
		return
	if _signature_review == "demand":
		var section: Control = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll/Content/DemandForecast") as Control
		var scroll: ScrollContainer = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll") as ScrollContainer
		if section == null or scroll == null or not section.visible:
			_fail_capture("signature demand framing could not find the real visible forecast section")
			return
		scroll.ensure_control_visible(section)


func _signature_review_evidence(world: SimWorld) -> Dictionary:
	var menu: MenuSettings = _main.get("menu_settings") as MenuSettings
	var signature_state: Object = _main.get("signature_state") as Object
	var recipe_id: StringName = StringName(_signature_fixture.get("recipe_id", ""))
	var panel: MenuPanel = _main.get_node_or_null("Overlay/MenuPanel") as MenuPanel
	if menu == null or signature_state == null or panel == null:
		return {}
	var details: Dictionary = _main.call("menu_recipe_details").get(recipe_id, {})
	var signature: Dictionary = details.get("signature", {})
	var row: Control = panel.row_for(recipe_id)
	var status: Label = row.get_node_or_null("Signature/Status") as Label if row != null else null
	var action: Button = row.get_node_or_null("Signature/MakeSignature") as Button if row != null else null
	var sales: Label = row.get_node_or_null("Signature/Sales") as Label if row != null else null
	var menu_panel: Control = panel.get_node_or_null("Panel") as Control
	var board_text: Label3D = null
	var board_point: Vector2 = Vector2(-1.0, -1.0)
	var board_visible: bool = false
	var board_text_value: String = ""
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	if _signature_review == "menu":
		var shop: ShopView = _main.get_node_or_null("ShopView") as ShopView
		var anchor: Vector3i = Vector3i(int(_signature_fixture.get("anchor", [1, 6, 3])[0]), int(_signature_fixture.get("anchor", [1, 6, 3])[1]), int(_signature_fixture.get("anchor", [1, 6, 3])[2]))
		var node: ItemVisual = shop.wall_finish_view.item_nodes.get(anchor) as ItemVisual if shop != null and shop.wall_finish_view != null else null
		board_text = node.prop.get_node_or_null(^"WallMount/MenuText") as Label3D if node != null and node.prop != null else null
		if board_text != null and camera != null:
			board_point = camera.unproject_position(board_text.global_position)
			board_visible = board_text.is_visible_in_tree() and not camera.is_position_behind(board_text.global_position)
			board_text_value = board_text.text
	var report: DayReport = _main.get("shown_report") as DayReport if "shown_report" in _main else null
	var section: Control = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll/Content/DemandForecast") as Control
	var factors: Label = section.get_node_or_null("Factors") as Label if section != null else null
	var forecast: Dictionary = report.demand_forecast if report != null else {}
	var state_after: Dictionary = signature_state.call("to_dict")
	var unchanged: bool = state_after == _signature_fixture.get("state_snapshot", {})
	if _signature_review == "menu":
		unchanged = unchanged and menu.to_dict() == _signature_fixture.get("menu_snapshot", {}) \
				and world.now == int(_signature_fixture.get("world_tick_at_setup", -1))
	else:
		unchanged = unchanged and report != null and report.to_dict() == _signature_fixture.get("report_snapshot", {}) \
				and menu.to_dict() == _signature_fixture.get("menu_snapshot", {}) \
				and world.now == int(_signature_fixture.get("world_tick_at_setup", -1))
	return {"mode": _signature_review, "world_phase": int(world.clock.phase) if world != null else -1,
		"world_tick": world.now if world != null else -1, "use_saves": bool(_main.get("use_saves")),
		"recipe_id": String(recipe_id), "display_name": String(_signature_fixture.get("display_name", "")),
		"model_signature_id": String(signature_state.call("signature_recipe_id")),
		"lifetime_sales": int(signature_state.call("sales_for", recipe_id)),
		"unlock_sales": int(_signature_fixture.get("unlock_sales", 0)),
		"menu_enabled": menu.is_enabled(recipe_id), "signature_details": signature,
		"menu_visible": bool(_main.call("is_menu_visible")), "status_text": status.text if status != null else "",
		"status_visible": status != null and status.is_visible_in_tree(),
		"action_visible": action != null and action.is_visible_in_tree(),
		"action_disabled": action.disabled if action != null else true,
		"sales_text": sales.text if sales != null else "",
		"menu_panel_rect": _signature_rect(menu_panel), "status_rect": _signature_rect(status),
		"board_present": board_text != null, "board_visible": board_visible,
		"board_text": board_text_value, "board_screen_point": [board_point.x, board_point.y],
		"report_visible": _main.get_node_or_null("Overlay/EveningReport") != null and _main.get_node("Overlay/EveningReport").is_visible_in_tree(),
		"report_day": report.day if report != null else -1, "forecast": forecast,
		"demand_section_rect": _signature_rect(section), "demand_factors_text": factors.text if factors != null else "",
		"demand_factors_visible": factors != null and factors.is_visible_in_tree(),
		"demand_factors_rect": _signature_rect(factors), "unchanged_after_draw": unchanged}


func _signature_review_valid(state: Dictionary, world: SimWorld) -> bool:
	if state.is_empty() or world == null or state.get("use_saves") != false \
			 or state.get("recipe_id") != _signature_fixture.get("recipe_id") \
			 or state.get("model_signature_id") != state.get("recipe_id") \
			 or int(state.get("lifetime_sales", 0)) < int(state.get("unlock_sales", 1)) \
			 or state.get("menu_enabled") != true or not state.get("signature_details", {}).get("eligible", false) \
			 or state.get("signature_details", {}).get("selected", false) != true \
			 or state.get("unchanged_after_draw") != true:
		return false
	if _signature_review == "menu":
		var menu_rect: Rect2 = _signature_rect_to_rect(state.get("menu_panel_rect", {}))
		var status_rect: Rect2 = _signature_rect_to_rect(state.get("status_rect", {}))
		var viewport: Rect2 = root.get_viewport().get_visible_rect()
		var board_point: Vector2 = Vector2(state.get("board_screen_point", [-1.0, -1.0])[0], state.get("board_screen_point", [-1.0, -1.0])[1])
		return world.clock.phase == SimClock.Phase.MORNING and state.get("menu_visible") == true \
				and state.get("status_text") == "Signature" and state.get("status_visible") == true \
				and state.get("action_visible") == false and state.get("board_present") == true \
				and state.get("board_visible") == true \
				and String(state.get("board_text", "")).contains("* " + String(state.get("display_name", ""))) \
				and viewport.has_point(board_point) and not menu_rect.has_point(board_point) \
				and menu_rect.has_area() and menu_rect.encloses(status_rect)
	var forecast: Dictionary = state.get("forecast", {})
	var name: String = String(forecast.get("signature_name", ""))
	var factor: float = float(forecast.get("signature", 0.0))
	var expected_line: String = "Signature dish: %s %s" % [name, DemandText.change_text(factor)]
	var demand_rect: Rect2 = _signature_rect_to_rect(state.get("demand_section_rect", {}))
	var factors_rect: Rect2 = _signature_rect_to_rect(state.get("demand_factors_rect", {}))
	return world.clock.phase == SimClock.Phase.CLOSED and state.get("report_visible") == true \
				and state.get("report_day") == int(_signature_fixture.get("report_day", -1)) \
				and int(forecast.get("day", 0)) == int(state.get("report_day", 0)) + 1 \
				and name == state.get("display_name") and factor > 1.0 \
				and String(state.get("demand_factors_text", "")).contains(expected_line) \
				and state.get("demand_factors_visible") == true \
				and demand_rect.has_area() and factors_rect.has_area() and demand_rect.encloses(factors_rect) \
				and root.get_viewport().get_visible_rect().encloses(demand_rect)


func _signature_rect(control: Control) -> Dictionary:
	if control == null:
		return {}
	var rect: Rect2 = control.get_global_rect()
	return {"position": [rect.position.x, rect.position.y], "size": [rect.size.x, rect.size.y]}


func _signature_rect_to_rect(value: Dictionary) -> Rect2:
	var position: Array = value.get("position", [])
	var size: Array = value.get("size", [])
	if position.size() != 2 or size.size() != 2:
		return Rect2()
	return Rect2(Vector2(float(position[0]), float(position[1])), Vector2(float(size[0]), float(size[1])))


func _configure_camera() -> void:
	var rig: Node3D = _main.get_node_or_null("CameraRig") as Node3D
	if rig != null and rig.has_method("reset_view"):
		# Main has configured the shop focus/zoom by now. Undo any virtual-display
		# edge pan from the first two frames before fixing the review pose.
		rig.call("reset_view")
	if _quarter >= 0:
		var view: Node = _main.get_node_or_null("ShopView")
		if rig == null or not rig.has_method("camera_quarter") or view == null or not view.has_method("set_wall_mode"):
			_fail_capture("requested quarter requires the shop camera and cutaway APIs")
			return
		# ShopView.WallMode is UP=0, CUTAWAY=1, DOWN=2. Use calls so the tool
		# also remains loadable for other scenes without those newer APIs.
		view.call("set_wall_mode", 1)
		rig.call("rotate_quarter", _quarter - int(rig.call("camera_quarter")))
		rig.call("step_view", 10.0, Vector2.ZERO)
	if rig != null:
		# Virtual-display focus/mouse position must not pan a review capture.
		rig.set_process(false)


## Camera only: no queue fixture, extra ticks, seed search or gameplay command.
## An empty queue still gets a doorway image and explicit absence in metadata.
func _focus_door_queue() -> void:
	var world: SimWorld = _capture_world()
	var shop: ShopView = _main.get_node_or_null("ShopView") as ShopView
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	if world == null or shop == null or rig == null or world.grid.entries().is_empty():
		_fail_capture("door queue view requires the real world, entry, ShopView and CameraRig")
		return
	shop._process(0.0)
	var positions: Dictionary[int, Vector3] = shop.drawn_agent_positions()
	var focus: Vector3 = GridMath.cell_to_world(world.grid.entries()[0])
	var queued_id: int = -1
	for agent: SimAgent in world.agents:
		if agent is CustomerAgent and (agent as CustomerAgent).state == CustomerAgent.State.QUEUED \
				and positions.has(agent.id) and (queued_id < 0 or agent.id < queued_id):
			queued_id = agent.id
			focus = positions[agent.id]
	rig.initial_focus = Vector2(focus.x, focus.z)
	rig.initial_zoom = rig.minimum_zoom
	rig.reset_view()
	rig.set_process(false)


func _configure_inspection() -> void:
	if _selection.is_empty() and not _f3:
		return
	if not _main.has_method("inspection_state") or _capture_world() == null:
		_fail_capture("requested inspection requires the scene's inspection state and live world APIs")
		return
	if not _selection.is_empty() and not _main.has_method("select_agent"):
		_fail_capture("--select requires the scene's select_agent API")
		return
	if _assign_owner and (not _main.has_method("assign_owner_mode") or not _main.has_method("run_ticks")):
		_fail_capture("owner assignment requires the scene's normal command and tick APIs")
		return
	if _f3:
		if not _main.has_method("set_debug_visible"):
			_fail_capture("--f3 requires the scene's set_debug_visible API")
			return
		_main.call("set_debug_visible", true)


func _capture_world() -> SimWorld:
	if "world" in _main:
		return _main.get("world") as SimWorld
	return null


func _configure_settings() -> void:
	_open_settings_control(_settings_world, _settings_scale)


func _shortcuts_state() -> Dictionary:
	var panel: ShortcutsPanel = _main.get_node_or_null("Overlay/ShortcutsPanel") as ShortcutsPanel
	var close_button: Button = _main.get_node_or_null("Overlay/ShortcutsPanel/Panel/Column/Header/Close") as Button
	var columns: HBoxContainer = _main.get_node_or_null("Overlay/ShortcutsPanel/Panel/Column/Columns") as HBoxContainer
	var content: VBoxContainer = _main.get_node_or_null("Overlay/ShortcutsPanel/Panel/Column/Scroll/Content") as VBoxContainer
	if panel == null or close_button == null or columns == null or content == null:
		return {"available": false}
	var group_headings: Array[String] = []
	var row_count: int = 0
	var two_cell_rows: bool = true
	for child: Node in content.get_children():
		if child is Label:
			group_headings.append((child as Label).text)
		elif child is HBoxContainer:
			row_count += 1
			var row: HBoxContainer = child as HBoxContainer
			if row.get_child_count() != 2 or not row.get_child(0) is Label or not row.get_child(1) is Label:
				two_cell_rows = false
		else:
			two_cell_rows = false
	var panel_card: PanelContainer = panel.get_node("Panel") as PanelContainer
	var bounds: Rect2 = panel_card.get_global_rect()
	var viewport_size: Vector2 = root.get_visible_rect().size
	var expected_row_count: int = 0
	for group_name: String in ShortcutsText.GROUPS:
		expected_row_count += ShortcutsText.rows_for(group_name).size()
	return {
		"available": true,
		"visible": panel.visible and panel.is_visible_in_tree() and bool(_main.call("is_shortcuts_visible")),
		"close_button_focused": root.gui_get_focus_owner() == close_button,
		"group_headings": group_headings,
		"expected_group_headings": ShortcutsText.GROUPS,
		"row_count": row_count,
		"expected_row_count": expected_row_count,
		"column_count": columns.get_child_count(),
		"two_cell_rows": two_cell_rows,
		"panel_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"viewport_bounds": [0.0, 0.0, viewport_size.x, viewport_size.y],
		"input": _shortcuts_input,
	}


func _shortcuts_capture_valid(state: Dictionary) -> bool:
	if state.get("available") != true or state.get("visible") != true or state.get("close_button_focused") != true \
			or state.get("group_headings") != ShortcutsText.GROUPS \
			or state.get("expected_group_headings") != ShortcutsText.GROUPS \
			or int(state.get("expected_row_count", 0)) <= 0 \
			or state.get("row_count") != state.get("expected_row_count") \
			or state.get("column_count") != 2 or state.get("two_cell_rows") != true:
		return false
	var bounds: Array = state["panel_bounds"]
	var viewport: Array = state["viewport_bounds"]
	var input: Dictionary = state.get("input", {})
	return bounds.size() == 4 and viewport.size() == 4 and bounds[2] > 0.0 and bounds[3] > 0.0 \
		and bounds[0] >= viewport[0] and bounds[1] >= viewport[1] \
		and bounds[0] + bounds[2] <= viewport[2] and bounds[1] + bounds[3] <= viewport[3] \
		and input.get("delivery") == "Viewport.push_input" \
		and input.get("key") == "F1" and input.get("frame") == 3


func _open_settings_control(from_gear: bool, percent: int) -> void:
	if not _main.has_method("set_menu_visible") or not _main.has_method("is_menu_visible") \
			or not _main.has_method("is_settings_visible"):
		_fail_capture("Settings capture requires Main's production panel APIs")
		return
	var button_path: NodePath = ^"HUD/Top/Row/Settings" if from_gear else ^"Overlay/MenuPanel/Panel/Content/Header/SettingsButton"
	if not from_gear and (not bool(_main.call("set_menu_visible", true)) or not bool(_main.call("is_menu_visible"))):
		_fail_capture("--settings requires Main's production morning Menu")
		return
	var button: Button = _main.get_node_or_null(button_path) as Button
	var panel: SettingsPanel = _main.get_node_or_null("Overlay/SettingsPanel") as SettingsPanel
	if button == null or button.disabled or not button.is_visible_in_tree() or panel == null:
		_fail_capture("Settings capture requires its native entry button and Settings panel")
		return
	_settings_from_menu = not from_gear
	button.pressed.emit()
	if not bool(_main.call("is_settings_visible")) or bool(_main.call("is_menu_visible")):
		_fail_capture("native Settings request did not open the production panel")
		return
	var scale: OptionButton = panel.get_node_or_null("Panel/Column/Scroll/Content/ScaleChoice") as OptionButton
	if scale == null or scale.get_item_index(percent) < 0:
		_fail_capture("Settings panel does not offer the requested UI scale")
		return
	# Use the player's control path: this applies and saves preferences normally.
	var index: int = scale.get_item_index(percent)
	scale.select(index)
	scale.item_selected.emit(index)


## Read the model, native control and actual window together after drawing.
func _settings_state() -> Dictionary:
	var preferences: SettingsPreferences = root.get_node_or_null("Preferences") as SettingsPreferences
	var panel: SettingsPanel = _main.get_node_or_null("Overlay/SettingsPanel") as SettingsPanel
	var scale: OptionButton = panel.get_node_or_null("Panel/Column/Scroll/Content/ScaleChoice") as OptionButton if panel != null else null
	if preferences == null or panel == null or scale == null:
		return {}
	var actual_size: Vector2i = DisplayServer.window_get_size()
	return {"visible": panel.is_visible_in_tree(), "entered_from_menu": _settings_from_menu,
		"menu_visible": _main.call("is_menu_visible"), "scale_control_visible": scale.is_visible_in_tree(),
		"ui_scale_percent": preferences.ui_scale_percent, "selected_ui_scale_percent": scale.get_selected_id(),
		"content_scale_factor": root.content_scale_factor, "window_mode": int(root.mode),
		"fullscreen_enabled": preferences.fullscreen_enabled,
		"window_size": [root.size.x, root.size.y], "display_size": [actual_size.x, actual_size.y],
		"card_and_close_bounded": _settings_card_bounded(panel), "hud_bounded": _settings_hud_bounded(),
		"keyboard": _settings_keyboard}


func _settings_capture_valid(state: Dictionary, world: SimWorld) -> bool:
	var expected_size: Array[int] = [SETTINGS_CAPTURE_SIZE.x, SETTINGS_CAPTURE_SIZE.y]
	var expected_visible: bool = not _settings_world
	return state.get("visible") == expected_visible and state.get("entered_from_menu") == expected_visible \
		and state.get("menu_visible") == false and state.get("hud_bounded") == true \
		and (_settings_world or state.get("card_and_close_bounded") == true) \
		and (not _settings_world or (_settings_keyboard.get("settings_closed") == true \
			and _settings_keyboard.get("tab_through_grid_controls") == true \
			and _settings_keyboard.get("tab_to_close") == true and _settings_keyboard.get("close_visible") == true)) \
		and state.get("ui_scale_percent") == _settings_scale \
		and state.get("selected_ui_scale_percent") == _settings_scale \
		and is_equal_approx(float(state.get("content_scale_factor", 0.0)), float(_settings_scale) / 100.0) \
		and state.get("window_mode") == Window.MODE_WINDOWED and state.get("fullscreen_enabled") == false \
		and state.get("window_size") == expected_size and state.get("display_size") == expected_size \
		and world != null and world.clock.phase == SimClock.Phase.MORNING and world.now == 0


func _hud_layout_state() -> Dictionary:
	var state: Dictionary = _settings_state()
	var header: Control = _main.get_node_or_null("HUD/Top") as Control
	if state.is_empty() or header == null:
		return {}
	var bounds: Rect2 = _settings_pixel_rect(header)
	var clock: Node = root.get_node_or_null("Clock")
	state.merge({"frame": _frames, "drawn_frame": Engine.get_frames_drawn(),
		"clock_speed": clock.get("speed") if clock != null else null,
		"header_visible": header.is_visible_in_tree(),
		"header_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]})
	return state


func _hud_layout_capture_valid(state: Dictionary, world: SimWorld) -> bool:
	var percent: int = 125 if _capture_frame == 12 else 150
	var close_frame: int = 9 if _capture_frame == 12 else 30
	var expected_size: Array[int] = [_hud_window_size.x, _hud_window_size.y]
	return _capture_frame in [12, 90] and state.get("frame") == _capture_frame \
		and state.get("ui_scale_percent") == percent and state.get("selected_ui_scale_percent") == percent \
		and is_equal_approx(float(state.get("content_scale_factor", 0.0)), float(percent) / 100.0) \
		and state.get("window_size") == expected_size and state.get("display_size") == expected_size \
		and state.get("window_mode") == Window.MODE_WINDOWED and state.get("fullscreen_enabled") == false \
		and state.get("visible") == false and state.get("menu_visible") == false \
		and state.get("header_visible") == true and state.get("entered_from_menu") == false \
		and _settings_keyboard.get("settings_closed") == true \
		and _settings_keyboard.get("tab_through_grid_controls") == true \
		and _settings_keyboard.get("tab_to_close") == true and _settings_keyboard.get("close_visible") == true \
		and _settings_keyboard.get("verification_frame") == close_frame \
		and state.get("clock_speed") == 0 \
		and world != null and world.clock.phase == SimClock.Phase.MORNING and world.now == 0


func _settings_pixel_rect(control: Control) -> Rect2:
	return root.get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _settings_card_bounded(panel: SettingsPanel) -> bool:
	var card: Control = panel.get_node("Panel") as Control
	var close: Button = panel.get_node("Panel/Column/CloseButton") as Button
	var header: Control = _main.get_node("HUD/Top") as Control
	var rect: Rect2 = _settings_pixel_rect(card)
	return panel.is_visible_in_tree() and close.is_visible_in_tree() \
		and Rect2(Vector2.ZERO, Vector2(root.size)).grow(1.0).encloses(rect) \
		and rect.grow(1.0).encloses(_settings_pixel_rect(close)) \
		and rect.position.y >= _settings_pixel_rect(header).end.y + 1.0


func _settings_hud_bounded() -> bool:
	var window: Rect2 = Rect2(Vector2.ZERO, Vector2(root.size)).grow(1.0)
	var top: Control = _main.get_node("HUD/Top") as Control
	if not window.encloses(_settings_pixel_rect(top)):
		return false
	for child: Node in _main.get_node("HUD/Top/Row").get_children():
		var control: Control = child as Control
		if control != null and control.is_visible_in_tree() and control.name not in [&"LeftSpace", &"RightSpace"]:
			var rect: Rect2 = _settings_pixel_rect(control)
			if not rect.has_area() or not window.encloses(rect):
				return false
	return true


func _close_settings_with_keyboard() -> void:
	var panel: SettingsPanel = _main.get_node("Overlay/SettingsPanel") as SettingsPanel
	_settings_keyboard = settings_tab_to_close(panel, root)
	_settings_keyboard.merge({"close_visible": _settings_card_bounded(panel), "accept_key": "Enter", "input_frame": _frames})
	if _settings_keyboard["tab_from_edge_pan"] != true or _settings_keyboard["tab_through_grid_controls"] != true \
			or _settings_keyboard["tab_to_close"] != true or _settings_keyboard["close_visible"] != true:
		_fail_capture("native Tab did not traverse the grid settings to the visible pinned Close button")
		return
	_settings_key(KEY_ENTER, true)
	_settings_key(KEY_ENTER, false)


## Follow native focus through both grid choices and the optional guide action,
## without jumping directly to Close or changing any preference or guide state.
static func settings_tab_to_close(panel: SettingsPanel, window: Window) -> Dictionary:
	var edge: CheckButton = panel.get_node("%EdgePanToggle") as CheckButton
	var play: CheckButton = panel.get_node("%PlayGridToggle") as CheckButton
	var build: CheckButton = panel.get_node("%BuildGridToggle") as CheckButton
	var close: Button = panel.get_node("%CloseButton") as Button
	var replay: Button = panel.get_node("%ShowGuideButton") as Button
	var targets: Array[Control] = [play, build]
	if replay.is_visible_in_tree():
		targets.append(replay)
	targets.append(panel.get_node("%WhatsNewButton") as Button)
	targets.append(close)
	var scroll: ScrollContainer = panel.get_node("Panel/Column/Scroll") as ScrollContainer
	scroll.ensure_control_visible(edge)
	edge.grab_focus()
	var result: Dictionary = {"tab_from_edge_pan": window.gui_get_focus_owner() == edge,
		"tab_through_grid_controls": true, "tab_through_guide_action": not replay.is_visible_in_tree(),
		"tab_to_close": false}
	for target: Control in targets:
		for pressed: bool in [true, false]:
			var event: InputEventKey = InputEventKey.new()
			event.keycode = KEY_TAB
			event.physical_keycode = KEY_TAB
			event.pressed = pressed
			window.push_input(event, true)
		if window.gui_get_focus_owner() != target:
			result["tab_through_grid_controls"] = false
			return result
		if target == replay:
			result["tab_through_guide_action"] = true
	result["tab_to_close"] = window.gui_get_focus_owner() == close
	return result


func _settings_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event, true)


## Actual post-draw pixels at projected floor cells distinguish world geometry
## from the brown clear colour. This does not manufacture a shop or alter it.
func _settings_world_evidence(image: Image) -> Dictionary:
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var camera: Camera3D = root.get_camera_3d()
	var expected: Camera3D = _main.get_node("CameraRig/Camera3D") as Camera3D
	var draws: int = root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	if camera != expected or view.world == null or view.floor_mesh == null:
		return {"verified": false, "draw_calls_3d": draws}
	var header: Rect2 = _settings_pixel_rect(_main.get_node("HUD/Top") as Control)
	var clear: Color = image.get_pixel(image.get_width() - 1, image.get_height() - 1)
	var candidates: int = 0
	var coloured: int = 0
	var witnesses: Array[Dictionary] = []
	for cell: Vector2i in view.world.grid.cells():
		if view.world.grid.terrain(cell) != SimGrid.Terrain.FLOOR:
			continue
		var point: Vector3 = GridMath.cell_to_world(cell)
		var pixel: Vector2 = root.get_final_transform() * camera.unproject_position(point)
		var at: Vector2i = Vector2i(pixel.round())
		if not camera.is_position_in_frustum(point) or header.has_point(pixel) \
				or at.x < 1 or at.y < 1 or at.x >= image.get_width() - 1 or at.y >= image.get_height() - 1:
			continue
		candidates += 1
		var average: Color = Color(0.0, 0.0, 0.0, 0.0)
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				average += image.get_pixel(at.x + dx, at.y + dy) / 9.0
		var difference: float = absf(average.r - clear.r) + absf(average.g - clear.g) + absf(average.b - clear.b)
		if difference > 0.08 and average.r + average.g + average.b > 0.12:
			coloured += 1
			if witnesses.size() < 12:
				witnesses.append({"cell": [cell.x, cell.y], "pixel": [at.x, at.y], "rgb": [average.r, average.g, average.b]})
	var visible_floor: bool = view.floor_mesh.is_visible_in_tree()
	return {"verified": draws > 0 and visible_floor and view.item_nodes.size() > 0 and candidates >= 16 and coloured >= 12,
		"draw_calls_3d": draws, "visible_floor": visible_floor, "native_item_count": view.item_nodes.size(),
		"floor_candidates": candidates, "coloured_floor_samples": coloured, "pixel_witnesses": witnesses,
		"clear_rgb": [clear.r, clear.g, clear.b]}


func _configure_paint() -> void:
	var world: SimWorld = _capture_world()
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	if world == null or world.clock.phase != SimClock.Phase.MORNING or world.now != 0 \
			or catalogue == null or rig == null or not _main.has_method("set_paint_active") or not _main.has_method("paint_cell"):
		_fail_capture("--paint requires the production paused morning paint APIs")
		return
	# Present the colours without grid lines, as a player can by pressing G.
	if rig.grid_visible:
		rig.toggle_grid()
	if not bool(_main.call("set_paint_active", true)):
		_fail_capture("scene refused paint entry")
		return
	# Item cells come from the real starter layout, so a roomier shop keeps
	# colouring the same first table and plant that _paint_state() reads.
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	var plants: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"potted_plant")
	var dining: Vector2i = _paint_dining_cell(world)
	if tables.is_empty() or plants.is_empty() or dining == Vector2i(-1, -1):
		_fail_capture("paint capture needs the starter table, plant and a clear dining floor cell")
		return
	var samples: Array[Dictionary] = [
		{"swatch": &"sage", "cell": Vector2i(0, 5)},
		{"swatch": &"honey", "cell": dining},
		# A floor click stays in its room (D25), so the kitchen takes its own.
		{"swatch": &"honey", "cell": Vector2i(3, 2)},
		{"swatch": &"terracotta", "cell": tables[0].origin},
		{"swatch": &"sage", "cell": plants[0].origin},
	]
	for sample: Dictionary in samples:
		var button: Button = catalogue.swatch_buttons.get(sample["swatch"]) as Button
		if button == null:
			_fail_capture("paint capture cannot find the requested native swatch")
			return
		button.pressed.emit()
		if not bool(_main.call("paint_cell", sample["cell"])):
			_fail_capture("paint capture could not colour its requested shop surface")
			return
	if _paint_slots:
		_configure_paint_slots(world, catalogue, tables[0])


## Paint slots (#431): every kind of piece with a second part gets it painted
## with Shift (the whole room's), cycling warm colours; then the first table
## is hovered so the panel names its parts. Production controls only.
func _configure_paint_slots(world: SimWorld, catalogue: BuildCatalogue, table: PlacedItem) -> void:
	var colours: Array[StringName] = [&"butter", &"tomato", &"mint", &"berry", &"sky"]
	var done: Dictionary[StringName, bool] = {}
	(catalogue.part_buttons[1] as Button).pressed.emit()
	for placed: PlacedItem in world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or definition.slots().size() < 2 or done.has(definition.id):
			continue
		(catalogue.swatch_buttons[colours[done.size() % colours.size()]] as Button).pressed.emit()
		if not bool(_main.call("paint_cell", placed.origin, true)):
			_fail_capture("paint slot capture could not paint a second part")
			return
		done[definition.id] = true
	(catalogue.swatch_buttons[&"butter"] as Button).pressed.emit()
	# Close enough to see the materials (photo framing only, like a player's zoom).
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	rig.frame_area(Vector2(table.origin) * GridMath.CELL_SIZE + Vector2(0.5, 0.9), Vector2(40.0, 40.0), 8.0, true)
	_main.call("preview_paint_cell", table.origin)
	if catalogue.paint_target() == null or table.paint.swatch(&"cushion").is_empty():
		_fail_capture("paint slot capture did not paint the table cloth or name its parts")


## The clear floor cell just inside the street door: dining floor in any
## starter size, never under a table, so its click paints the dining floor.
func _paint_dining_cell(world: SimWorld) -> Vector2i:
	var entries: Array[Vector2i] = world.grid.entries()
	if entries.is_empty():
		return Vector2i(-1, -1)
	var cell: Vector2i = entries[0] + Vector2i.UP
	if world.grid.terrain(cell) != SimGrid.Terrain.FLOOR or world.grid.item_at(cell) != null:
		return Vector2i(-1, -1)
	return cell


func _paint_state() -> Dictionary:
	var world: SimWorld = _capture_world()
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	var view: ShopView = _main.get_node_or_null("ShopView") as ShopView
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	if world == null or editor == null or view == null or catalogue == null or rig == null:
		return {}
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	var plants: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"potted_plant")
	var dining: Vector2i = _paint_dining_cell(world)
	if tables.is_empty() or plants.is_empty() or dining == Vector2i(-1, -1) or view.get_node("Walls").get_child_count() == 0:
		return {}
	var wall: MeshInstance3D = view.get_node("Walls").get_child(0) as MeshInstance3D
	var floor_shader: ShaderMaterial = view.floor_mesh.material_override as ShaderMaterial
	var table_material: BaseMaterial3D = view.item_nodes[tables[0].id].primary_body_material()
	var plant_material: BaseMaterial3D = view.item_nodes[plants[0].id].primary_body_material()
	var content: ContentDB = _main.get("content") as ContentDB
	return {"active": _main.call("is_paint_active"), "catalogue_visible": catalogue.is_visible_in_tree(),
		"swatch_count": catalogue.swatch_buttons.size(), "grid_forced": rig.is_grid_forced(),
		"grid_visible": rig.effective_grid_visible(), "wall": String(editor.wall_swatch_id),
		"floor": String(editor.floors.finish(dining).swatch), "table": String(tables[0].swatch_id),
		"plant": String(plants[0].swatch_id),
		# D25: a floor click recolours its own room's floor in the finish map;
		# the capture clicks the dining room and the kitchen, so the whole
		# starter floor turns honey as before.
		"rendered": (wall.material_override as StandardMaterial3D).albedo_color == content.swatch(&"sage").color \
			and floor_shader.get_shader_parameter("finish_map") == view.finish_texture \
			and view.finish_texel(dining).g8 == ShopView.FINISH_FIRST_SWATCH + content.swatches().find(content.swatch(&"honey")) \
			and view.finish_texel(Vector2i(3, 2)).g8 == view.finish_texel(dining).g8 \
			and table_material.albedo_color == content.swatch(&"terracotta").color \
			and plant_material.albedo_color == content.swatch(&"sage").color}


## Review proposals only: no trial placements, transactions or save writes.
func _configure_build() -> void:
	var world: SimWorld = _capture_world()
	if world == null or world.clock.phase != SimClock.Phase.MORNING \
			or not _main.has_method("set_build_active") or not _main.has_method("begin_buy_item") \
			or not _main.has_method("update_build_pointer") or not _main.has_method("route_build_input"):
		_fail_capture("--build requires the production morning build APIs")
		return
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var def_id: StringName = &"fridge" if _build == "red" else &"table_2"
	# Anchored to the real starter tables so a resized shop keeps the same
	# proposals in view above the catalogue panel: green turns a table like
	# the starters into the clear gap between the west and middle tables, one
	# row north; red puts the fridge across the middle table itself.
	var tables: Array[PlacedItem] = ShopBuilder.items_with_def(world, &"table_2")
	if tables.size() != 3:
		_fail_capture("--build review expects the three starter tables")
		return
	tables.sort_custom(func(a: PlacedItem, b: PlacedItem) -> bool: return a.origin.x < b.origin.x)
	var gap_x: int = floori((tables[0].origin.x + tables[1].origin.x) / 2.0)
	var cell: Vector2i = Vector2i(gap_x, tables[1].origin.y - 1) if _build == "green" else tables[1].origin + Vector2i(1, 1)
	var turns: int = tables[1].quarter_turns if _build == "green" else 1
	if _build == "pinch":
		# #389: a fourth table squeezed under the middle one, unturned, leaves
		# one cell between its seats and the tables above and the street wall.
		cell = tables[1].origin + Vector2i(-1, 4)
		turns = 0
	var check: EditCheck = editor.check_buy(def_id, cell, turns) if editor != null else null
	if editor == null or camera == null or not editor.can_edit() \
			or check.ok != (_build != "red") or check.aisle_pinches.is_empty() != (_build != "pinch"):
		_fail_capture("review proposal does not match the actual editor result")
		return
	_build_pointer = camera.unproject_position(GridMath.cell_to_world(cell))
	if not bool(_main.call("set_build_active", true)):
		_fail_capture("scene refused build entry")
		return
	_hold_build_pointer()
	if not bool(_main.call("begin_buy_item", def_id)):
		_fail_capture("scene refused buy preview")
		return
	for turn: int in range(turns):
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = KEY_R
		key.pressed = true
		_main.call("route_build_input", key)
	_main.call("update_build_pointer", _build_pointer)


## FK-070 room: an interior wall across the west dining room with a window and
## a doorway, a short return wall (T junction), and two windows in the west shell.
static func walls_fixture() -> Dictionary[Vector3i, int]:
	var changes: Dictionary[Vector3i, int] = {}
	for y: int in range(5, 10):
		changes[Vector3i(5, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.WALL
	changes[Vector3i(5, 6, SimGrid.EDGE_WEST)] = SimGrid.Segment.WINDOW
	changes[Vector3i(5, 8, SimGrid.EDGE_WEST)] = SimGrid.Segment.DOORWAY
	changes[Vector3i(3, 9, SimGrid.EDGE_NORTH)] = SimGrid.Segment.WALL
	changes[Vector3i(4, 9, SimGrid.EDGE_NORTH)] = SimGrid.Segment.WALL
	changes[Vector3i(1, 6, SimGrid.EDGE_WEST)] = SimGrid.Segment.WINDOW
	changes[Vector3i(1, 7, SimGrid.EDGE_WEST)] = SimGrid.Segment.WINDOW
	return changes


## The room is built through Main's production wrapper; the camera frames it.
func _configure_walls() -> void:
	var world: SimWorld = _capture_world()
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	if world == null or rig == null or world.clock.phase != SimClock.Phase.MORNING or not _main.has_method("shop_walls"):
		_fail_capture("--walls requires the production morning wall APIs")
		return
	_walls_initial.clear()
	for edge: Vector3i in world.grid.segment_edges():
		_walls_initial[edge] = world.grid.segment(edge)
	if _walls == "room" and not bool(_main.call("shop_walls", walls_fixture())):
		_fail_capture("the walls fixture was refused: " + (_main.get("shop_editor") as ShopEditor).last_check.why)
		return
	rig.initial_focus = Vector2(2.6, 3.6) if _walls == "room" else Vector2(4.4, 3.7)
	rig.initial_zoom = rig.minimum_zoom


## Press on one grid vertex and hold the pointer on another, through Main's input route.
func _begin_wall_drag() -> void:
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	if camera == null or catalogue == null or not bool(_main.call("set_build_active", true)):
		_fail_capture("scene refused build entry for the walls preview")
		return
	catalogue.set_category(BuildCatalogue.WALLS)
	if not bool(_main.call("begin_wall_tool", SimGrid.Segment.WALL)):
		_fail_capture("scene refused the Walls tool")
		return
	var start: Vector2 = camera.unproject_position(Vector3(4.5, 0.0, 2.5))
	_build_pointer = camera.unproject_position(Vector3(4.5, 0.0, 4.5))
	root.warp_mouse(start)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	# Through Input, so the held button is real state (Main ends drags whose
	# button is up) and the press takes the production _unhandled_input route.
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	_hold_build_pointer()
	_main.call("update_build_pointer", _build_pointer)


func _walls_capture_valid() -> bool:
	var world: SimWorld = _capture_world()
	var mode: BuildMode = _main.get("build_mode") as BuildMode
	var preview: BuildPreview = _main.get_node_or_null("BuildPreview") as BuildPreview
	if world == null or mode == null or preview == null:
		return false
	var expected: Dictionary[Vector3i, int] = _walls_initial.duplicate()
	if _walls == "place":
		if mode.state != BuildMode.State.WALLS or not mode.wall_dragging or not mode.current_check.ok \
				or mode.current_check.changes.size() != 4 or preview.wall_ghosts.size() != 4:
			return false
	else:
		expected.merge(walls_fixture(), true)
	for edge: Vector3i in expected:
		if world.grid.segment(edge) != expected[edge]:
			return false
	return world.grid.segment_edges().size() == expected.size()


## FK-080 shop: an L of new floor (an east wing beside the dining room and a
## back room behind the kitchen's east end), with tables in the new floor.
static func expand_fixture() -> Array[Rect2i]:
	return [Rect2i(14, 0, 1, 10), Rect2i(6, -3, 9, 3)]


## Table origins (x, y) and quarter turns (z).
static func expand_tables() -> Array[Vector3i]:
	return [Vector3i(8, -3, 0), Vector3i(12, -3, 0), Vector3i(13, 6, 1)]


## The floor is bought through Main's production wrapper. The fixture's floor
## costs more than a new game's cash, so the capture first grants the gap,
## and guests arrive faster so the new tables fill.
func _configure_expand() -> void:
	var world: SimWorld = _capture_world()
	var rig: CameraRig = _main.get_node_or_null("CameraRig") as CameraRig
	if world == null or rig == null or world.clock.phase != SimClock.Phase.MORNING or not _main.has_method("shop_floor"):
		_fail_capture("--expand requires the production morning floor APIs")
		return
	var economy: Node = root.get_node("Economy")
	economy.call("add_cash", 1200, Ledger.OTHER)
	if _expand == "drag":
		# Show the whole lot: its centre, a little further out than the shop fit.
		rig.initial_focus = Vector2(3.5, 1.75)
		rig.initial_zoom = 16.0
		return
	for rect: Rect2i in expand_fixture():
		var cells: Array[Vector2i] = []
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
		if not bool(_main.call("shop_floor", cells, true)):
			_fail_capture("the floor fixture was refused: " + (_main.get("shop_editor") as ShopEditor).last_check.why)
			return
	# A busy evening so the new tables fill: the three old tables would
	# otherwise take every guest of a quiet morning.
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	sim.spawner.min_gap = 25
	sim.spawner.max_gap = 45
	for table: Vector3i in expand_tables():
		if not bool(_main.call("shop_buy", &"table_2", Vector2i(table.x, table.y), table.z)):
			_fail_capture("a fixture table was refused: " + (_main.get("shop_editor") as ShopEditor).last_check.why)
			return


## FK-101: the expansion fixture's floor (back room plus east wing), its
## tables, and a restroom in the back room's west end behind a wall with a
## doorway: a toilet and a wash basin. All through Main's production wrappers.
static func rooms_restroom_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(-3, 0):
		for x: int in range(6, 8):
			cells.append(Vector2i(x, y))
	return cells


## A wall wrapping the kitchen (the opened old back wall row stays kitchen
## side, the east wing is the guests' way round) and the restroom's wall with
## a doorway.
static func rooms_walls() -> Dictionary[Vector3i, int]:
	var walls: Dictionary[Vector3i, int] = {Vector3i(8, -3, SimGrid.EDGE_WEST): SimGrid.Segment.WALL,
		Vector3i(8, -2, SimGrid.EDGE_WEST): SimGrid.Segment.WALL,
		Vector3i(8, -1, SimGrid.EDGE_WEST): SimGrid.Segment.DOORWAY}
	for x: int in range(6, 13):
		walls[Vector3i(x, 0, SimGrid.EDGE_NORTH)] = SimGrid.Segment.WALL
	for y: int in range(0, 4):
		walls[Vector3i(13, y, SimGrid.EDGE_WEST)] = SimGrid.Segment.WALL
	return walls


static func rooms_kitchen_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(6, 13):
		cells.append(Vector2i(x, 0))
	return cells


func _configure_rooms() -> void:
	var world: SimWorld = _capture_world()
	var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
	if world == null or editor == null or world.clock.phase != SimClock.Phase.MORNING or not _main.has_method("shop_rooms"):
		_fail_capture("--rooms requires the production morning room APIs")
		return
	root.get_node("Economy").call("add_cash", 2000, Ledger.OTHER)
	for rect: Rect2i in expand_fixture():
		var cells: Array[Vector2i] = []
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
		if not bool(_main.call("shop_floor", cells, true)):
			_fail_capture("the floor fixture was refused: " + editor.last_check.why)
			return
	# The opened back wall row is already kitchen (the back-wall rule).
	for cell: Vector2i in rooms_kitchen_cells():
		if world.grid.room(cell) != SimGrid.Room.KITCHEN:
			_fail_capture("the opened back wall should be kitchen at %s" % cell)
			return
	var steps: Array = [["shop_walls", rooms_walls()],
		["shop_rooms", editor.room_changes(rooms_restroom_cells(), SimGrid.Room.RESTROOM)],
		["shop_buy", &"toilet", Vector2i(6, -3), 2], ["shop_buy", &"bathroom_sink", Vector2i(7, -3), 2],
		["shop_buy", &"table_2", Vector2i(10, -3), 0], ["shop_buy", &"table_2", Vector2i(13, 6), 1]]
	for step: Array in steps:
		var accepted: Variant = _main.callv(step[0], step.slice(1))
		if not (accepted is bool and accepted):
			_fail_capture("a rooms fixture step was refused (%s): %s" % [step[0], editor.last_check.why])
			return
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	if not sim.has_restroom():
		_fail_capture("the rooms fixture has no restroom")
		return
	if _rooms == "restroom":
		# A busy service, and every guest needs the restroom, so one is seen
		# walking there soon: a capture fixture only, never game data.
		sim.spawner.min_gap = 25
		sim.spawner.max_gap = 45
		sim.customer_arrived.connect(_on_rooms_guest_arrived)


func _on_rooms_guest_arrived(guest: CustomerAgent) -> void:
	guest.restroom_chance = 1.0


## The Rooms tool (Dining hovered over the back room), or a held table in the
## kitchen that the edit checks refuse.
func _begin_rooms_view() -> void:
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	if camera == null or catalogue == null or not bool(_main.call("set_build_active", true)):
		_fail_capture("scene refused build entry for the rooms view")
		return
	if _rooms == "tool":
		_main.call("_on_catalogue_mode_requested", BuildCatalogue.BUILD)
		catalogue.set_category(BuildCatalogue.ROOMS)
		if not bool(_main.call("begin_rooms_tool", SimGrid.Room.RESTROOM)):
			_fail_capture("scene refused the Rooms tool")
			return
		_build_pointer = camera.unproject_position(GridMath.cell_to_world(Vector2i(14, 9)))
	else:
		_build_pointer = camera.unproject_position(GridMath.cell_to_world(Vector2i(3, 2)))
		_hold_build_pointer()
		if not bool(_main.call("begin_buy_item", &"table_2")):
			_fail_capture("scene refused the kitchen seat preview")
			return
	_hold_build_pointer()
	_main.call("update_build_pointer", _build_pointer)


## Freeze the clock on the first guest walking to the restroom once they are
## round the kitchen and into the back room, so the later frames show it.
func _pause_on_restroom_walk() -> void:
	var world: SimWorld = _capture_world()
	for agent: SimAgent in world.agents:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest != null and guest.restroom == CustomerAgent.Restroom.WALKING and guest.cell.x >= 11 and guest.cell.y <= -1:
			_fast = 0
			root.get_node("Clock").call("set_speed", 0)
			_rooms_paused = true
			print("ROOMS_RESTROOM_WALK guest=%d cell=%s" % [guest.id, guest.cell])
			return


## Before the drag: every sample cell draws its floor type, thresholds exist and
## Build is closed. After: the Floors tool holds an 8-tile herringbone drag
## drawn as the floor's own preview, priced in the hint.
func _walls_review_valid(state: Dictionary) -> bool:
	if state.is_empty() or int(state.get("stored_faces", 0)) < 20 or int(state.get("hung", 0)) != 4 \
			or int(state.get("drawn_faces", 0)) < int(state.get("stored_faces", 0)):
		return false
	print("WALLS_REVIEW frame=%d %s" % [_capture_frame, JSON.stringify(state)])
	if _capture_frame < WALLS_REVIEW.WALL_UP_FRAME:
		return int(state.get("state", -1)) == BuildMode.State.INACTIVE and int(state.get("preview_faces", -1)) == 0
	if _capture_frame >= WALLS_REVIEW.DOWN_FRAME:
		return int(state.get("wall_mode", -1)) == ShopView.WallMode.DOWN and int(state.get("hung_shown", -1)) == 0
	if _capture_frame >= WALLS_REVIEW.HANG_FRAME:
		return int(state.get("state", -1)) == BuildMode.State.HANG
	return int(state.get("state", -1)) == BuildMode.State.WALL_FINISH and state.get("dragging") == true \
		and state.get("check_ok") == true and int(state.get("proposal", 0)) > 0 \
		and int(state.get("hung_shown", 0)) == 4 and int(state.get("wall_mode", -1)) == ShopView.WallMode.UP \
		and String(state.get("summary", "")).begins_with("Put up Striped wallpaper")


func _floors_capture_valid(state: Dictionary) -> bool:
	if state.is_empty() or state.get("patterns_match") != true or int(state.get("threshold_cells", 0)) < 8 \
			or state.get("floor_material_shared") != true:
		return false
	print("FLOORS_REVIEW frame=%d %s" % [_capture_frame, JSON.stringify(state)])
	if _capture_frame < FLOORS_DRAG_FRAME:
		return int(state.get("state", -1)) == BuildMode.State.INACTIVE and int(state.get("preview_cells", -1)) == 0
	return int(state.get("state", -1)) == BuildMode.State.FLOORS and state.get("dragging") == true \
		and state.get("check_ok") == true and int(state.get("proposal", 0)) == 8 \
		and int(state.get("preview_cells", 0)) == 8 and String(state.get("summary", "")).begins_with("Lay 8 tiles of Herringbone")


func _rooms_capture_valid() -> bool:
	var world: SimWorld = _capture_world()
	var mode: BuildMode = _main.get("build_mode") as BuildMode
	var preview: BuildPreview = _main.get_node_or_null("BuildPreview") as BuildPreview
	if world == null or mode == null or preview == null:
		return false
	match _rooms:
		"tool":
			var labels: Array[String] = []
			for label: Label3D in preview.room_labels:
				labels.append(label.text)
			print("ROOMS_TOOL tints=%s labels=%s hint=%s" % [preview.room_tints.keys(), labels, mode.rooms_summary()])
			return mode.state == BuildMode.State.ROOMS and preview.room_tints.has(SimGrid.Room.KITCHEN) \
				and preview.room_tints.has(SimGrid.Room.DINING) and preview.room_tints.has(SimGrid.Room.RESTROOM) \
				and labels.has("Kitchen") and labels.has("Restroom")
		"refused":
			print("ROOMS_REFUSED why=%s" % mode.current_check.why)
			return mode.state == BuildMode.State.BUY and not mode.current_check.ok \
				and mode.current_check.why == RoomRules.SEAT_IN_KITCHEN
	for agent: SimAgent in world.agents:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest != null and guest.restroom == CustomerAgent.Restroom.WALKING:
			for cell: Vector2i in guest.path:
				if world.grid.is_staff_only(cell):
					return false
			print("ROOMS_RESTROOM guest=%d cell=%s path=%s" % [guest.id, guest.cell, guest.path])
			return true
	return false


## Press on a lot cell behind the kitchen and hold the pointer on another,
## dragging a 8 x 3 back room, through Main's input route.
func _begin_floor_drag() -> void:
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var catalogue: BuildCatalogue = _main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	if camera == null or catalogue == null or not bool(_main.call("set_build_active", true)):
		_fail_capture("scene refused build entry for the floor preview")
		return
	catalogue.set_category(BuildCatalogue.WALLS)
	if not bool(_main.call("begin_floor_tool")):
		_fail_capture("scene refused the Floor tool")
		return
	var start: Vector2 = camera.unproject_position(GridMath.cell_to_world(Vector2i(1, -1)))
	_build_pointer = camera.unproject_position(GridMath.cell_to_world(Vector2i(8, -3)))
	root.warp_mouse(start)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	_hold_build_pointer()
	_main.call("update_build_pointer", _build_pointer)


func _expand_capture_valid() -> bool:
	var world: SimWorld = _capture_world()
	var mode: BuildMode = _main.get("build_mode") as BuildMode
	var preview: BuildPreview = _main.get_node_or_null("BuildPreview") as BuildPreview
	if world == null or mode == null or preview == null:
		return false
	if _expand == "drag":
		print("EXPAND_DRAG cells=%d cost=%d hint=%s" % [mode.current_check.floor_cells.size(),
			mode.current_check.cost, mode.floor_summary()])
		return mode.state == BuildMode.State.FLOOR and mode.floor_dragging and mode.current_check.ok \
			and mode.current_check.floor_cells.size() == 24 and preview.floor_ghost_cells.size() == 24 \
			and is_instance_valid(preview.lot_outline) \
			and world.grid.terrain(Vector2i(1, -1)) != SimGrid.Terrain.FLOOR
	for cell: Vector2i in [Vector2i(14, -3), Vector2i(13, 5), Vector2i(14, 9)]:
		if world.grid.terrain(cell) != SimGrid.Terrain.FLOOR:
			return false
	var seated: int = 0
	for agent: SimAgent in world.agents:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest != null and guest.cell == guest.seat_cell and (guest.cell.x >= 13 or guest.cell.y < 1):
			seated += 1
	var seats: Array[String] = []
	for agent: SimAgent in world.agents:
		if agent is CustomerAgent:
			seats.append("%s@%s" % [(agent as CustomerAgent).seat_cell, agent.cell])
	print("EXPAND_SHOP seated_in_new_floor=%d guests=%s" % [seated, ", ".join(seats)])
	return not _open or seated > 0


func _hold_build_pointer() -> void:
	root.warp_mouse(_build_pointer)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = _build_pointer
	motion.global_position = _build_pointer
	root.push_input(motion, true)


func _build_state() -> Dictionary:
	if not ("build_mode" in _main):
		return {}
	var mode: BuildMode = _main.get("build_mode") as BuildMode
	var preview: BuildPreview = _main.get_node_or_null("BuildPreview") as BuildPreview
	if mode == null or preview == null:
		return {}
	var ghost: ItemVisual = preview.ghost_mesh
	var pointer_cell: Variant = _main.call("build_cell_at_screen_position", root.get_mouse_position())
	return {"active": mode.is_active(), "state": int(mode.state), "has_ghost": mode.has_ghost(),
		"definition": String(mode.selected_definition.id) if mode.selected_definition != null else "",
		"origin": [mode.origin.x, mode.origin.y], "quarter_turns": mode.quarter_turns,
		"pointer_cell": [pointer_cell.x, pointer_cell.y] if pointer_cell is Vector2i else null,
		"ok": mode.current_check.ok, "why": mode.current_check.why,
		"ghost_visible": is_instance_valid(ghost) and ghost.is_visible_in_tree(),
		"ghost_valid": ghost.get_meta("valid", null) if is_instance_valid(ghost) else null,
		"aisle_pinches": _cell_pairs(preview.displayed_aisle_pinches())}


static func _cell_pairs(cells: Array[Vector2i]) -> Array:
	var out: Array = []
	for cell: Vector2i in cells:
		out.append([cell.x, cell.y])
	return out


func _select_live_agent() -> void:
	var world: SimWorld = _capture_world()
	if world == null:
		_fail_capture("--select requires a live simulation world")
		return
	var selected: SimAgent = world.agent(_selected_agent_id)
	if (_selection == &"guest" and selected is CustomerAgent) or (_selection == &"owner" and selected is OwnerAgent):
		return
	# Wait only within the requested frame budget for normal/--fast arrivals.
	# If a previous guest departed, select the next live guest in stable id order.
	_selected_agent_id = -1
	for agent: SimAgent in world.agents:
		if (_selection == &"guest" and agent is CustomerAgent) or (_selection == &"owner" and agent is OwnerAgent):
			if not bool(_main.call("select_agent", agent.id)):
				_fail_capture("scene rejected selection of a live " + String(_selection))
				return
			_selected_agent_id = agent.id
			if _assign_owner and not bool(_main.call("assign_owner_mode", &"kitchen")):
				_fail_capture("scene rejected the normal owner kitchen command")
			return


## Bounded normal simulation only: wait for actual owner cooking work rather
## than installing a capture fixture, task, inventory or altered staff priority.
func _prepare_owner_capture() -> void:
	var world: SimWorld = _capture_world()
	if world == null or not world.agent(_selected_agent_id) is OwnerAgent:
		_fail_capture("owner kitchen capture has no live selected owner")
		return
	for tick: int in range(MAX_OWNER_WARMUP_TICKS + 1):
		var selected_owner: OwnerAgent = world.agent(_selected_agent_id) as OwnerAgent
		if _owner_cook_task(selected_owner) and selected_owner.step_index == 0:
			return
		if tick == MAX_OWNER_WARMUP_TICKS:
			break
		var before: int = world.now
		_main.call("run_ticks", 1)
		if world.now != before + 1:
			break
		_owner_warmup_ticks += 1
	_fail_capture("normal owner did not claim fresh cooking work within the bounded capture warmup")


func _owner_cook_task(selected_owner: OwnerAgent) -> bool:
	return selected_owner != null and selected_owner.current_mode() == &"kitchen" and selected_owner.task != null \
		and selected_owner.task.role == &"cook" and selected_owner.task.state == SimTask.State.CLAIMED \
		and selected_owner.task.claimed_by == selected_owner.id and selected_owner.step_index >= 0 \
		and selected_owner.step_index < selected_owner.task.steps.size()


func _queue_capture() -> void:
	_capture_pending = true
	_capture_frame = _frames
	_capture_wait_frames = 0
	# MainLoop._process precedes node processing and rendering. Save pixels and
	# inspect the scene together only after this frame has actually been drawn.
	RenderingServer.frame_post_draw.connect(_capture, CONNECT_ONE_SHOT)


## Brings the closed-day report's Low stock heading to the top of its scroll.
func _scroll_report_to_low_stock() -> void:
	var scroll: ScrollContainer = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll") as ScrollContainer
	var heading: Control = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll/Content/LowStockHeading") as Control
	if scroll != null and heading != null and scroll.is_visible_in_tree():
		scroll.scroll_vertical = int(heading.position.y)


## Bring the real seller label into the existing report viewport for a focused capture.
func _scroll_report_to_slowest_seller() -> void:
	var scroll: ScrollContainer = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll") as ScrollContainer
	var label: Label = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll/Content/SlowestSeller") as Label
	if scroll != null and label != null and label.visible and scroll.is_visible_in_tree():
		scroll.scroll_vertical = int(label.position.y)


func _low_stock_visible(world: SimWorld) -> bool:
	var scroll: ScrollContainer = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll") as ScrollContainer
	var heading: Control = _main.get_node_or_null("Overlay/EveningReport/Panel/Scroll/Content/LowStockHeading") as Control
	var report: DayReport = _main.get("shown_report") as DayReport
	return world != null and world.clock.phase == SimClock.Phase.CLOSED and report != null \
		and scroll != null and heading != null and scroll.is_visible_in_tree() \
		and scroll.get_global_rect().encloses(heading.get_global_rect())


func _capture() -> void:
	if _finished or _failed or not _capture_pending:
		return
	if _errors.count() > 0:
		_fail_capture("engine/script errors occurred before capture")
		return
	var inspection: Dictionary = {}
	if _main.has_method("inspection_state"):
		inspection = _main.call("inspection_state")
	var world: SimWorld = _capture_world()
	var patio_state: Dictionary = {}
	var patio_review: bool = _scene_path in ["res://tools/patio_review_sunny.tscn", "res://tools/patio_review_rain.tscn"]
	if patio_review:
		if not _main.has_method("patio_review_evidence") or not _main.has_method("patio_review_valid"):
			_fail_capture("patio review scene is missing its native validation")
			return
		patio_state = _main.call("patio_review_evidence")
		var expected_weather: int = WeatherState.Kind.RAIN if _scene_path.ends_with("_rain.tscn") else WeatherState.Kind.SUNNY
		if patio_state.get("kind") != expected_weather or not _main.call("patio_review_valid", patio_state):
			_fail_capture("patio review failed actual weather, ownership, paid construction, seating or visible status checks: " + JSON.stringify(patio_state))
			return
	var neighbourhood_state: Dictionary = NEIGHBOURHOOD_REVIEW.evidence(_main, root, _neighbourhood_fixture) if not _neighbourhood_mode.is_empty() else {}
	if not _neighbourhood_mode.is_empty() and not NEIGHBOURHOOD_REVIEW.valid(neighbourhood_state, _neighbourhood_fixture):
		_fail_capture("neighbourhood photo failed actual pose/player, outside-only, simulation isolation or camera checks: " + JSON.stringify(neighbourhood_state))
		return
	var weather_state: Dictionary = WEATHER_REVIEW.evidence(_main, root, _weather_fixture) if not _weather_mode.is_empty() else {}
	if not _weather_mode.is_empty() and not WEATHER_REVIEW.valid(weather_state, _weather_mode):
		_fail_capture("weather review failed its actual morning UI, stream, outside rain or isolated receiver checks: " + JSON.stringify(weather_state))
		return
	var joined_tables_state: Dictionary = JOINED_TABLES_REVIEW.evidence(
		_main, root, _joined_tables_fixture, _capture_frame) if _joined_tables_review else {}
	if _joined_tables_review and not JOINED_TABLES_REVIEW.valid(
		joined_tables_state, _joined_tables_fixture, _capture_frame):
		_fail_capture("joined-table review failed its actual six-person party, physical holds, group or native sit checks: " + JSON.stringify(joined_tables_state))
		return
	var diner_state: Dictionary = DINER_REVIEW.evidence(_main, root, _capture_frame) if _diner_review else {}
	if _diner_review and not DINER_REVIEW.valid(diner_state, _capture_frame, _diner_fixture):
		_fail_capture("diner review failed actual source, bounds, native actor or seat validation: " + JSON.stringify(diner_state))
		return
	var lease_state: Dictionary = LEASE_REVIEW.evidence(_main, root, _lease_fixture) if not _lease_mode.is_empty() else {}
	if not _lease_mode.is_empty() and not LEASE_REVIEW.valid(lease_state, _lease_fixture, _capture_frame):
		_fail_capture("lease review did not match its real Menu/Expand controls, purchase, lot or default recipe choices: " + JSON.stringify(lease_state))
		return
	var loan_state: Dictionary = loan_review_evidence(_main, root) if _loan_review else {}
	if _loan_review and not loan_review_valid(loan_state, _capture_frame, _loan_fixture):
		_fail_capture("loan review did not match its real account, phase and visible native controls")
		return
	var milestone_state: Dictionary = milestone_review_evidence(_main, root, _capture_frame) if _milestone_review else {}
	if _milestone_review and not milestone_review_valid(milestone_state, _capture_frame, _milestone_fixture):
		_fail_capture("milestone review did not match authored goals, the real close reward, ledger, XP or visible native rows")
		return
	var collections_state: Dictionary = collections_review_evidence(_main, root,
		_collections_fixture, _capture_frame) if _collections_review else {}
	if _collections_review and not collections_review_valid(collections_state, _collections_fixture):
		_fail_capture("collections review did not show Main-derived completion, missing ticks and visible native Goals rows: " \
			+ JSON.stringify(collections_state))
		return
	var catalogue_state: Dictionary = catalogue_review_evidence(_main, root) if not _catalogue_profile.is_empty() else {}
	if not _catalogue_profile.is_empty() and not catalogue_review_valid(catalogue_state, _capture_frame, _catalogue_fixture):
		_fail_capture("catalogue review did not match its fixture, real previews, seating links or bounds: " + JSON.stringify({
			"cache": catalogue_state.get("cache", {}), "vibe": catalogue_state.get("vibe", {}),
			"generated_vibe_uids": catalogue_state.get("generated_vibe_uids", {})}))
		return
	var blueprint_state: Dictionary = BLUEPRINT_REVIEW.evidence(_main) if not _blueprint_profile.is_empty() else {}
	if not _blueprint_profile.is_empty() and not BLUEPRINT_REVIEW.valid(blueprint_state, _blueprint_profile):
		_fail_capture("blueprint review did not match its native selection, ghost or stamped pair: " + JSON.stringify(blueprint_state))
		return
	var walls_state: Dictionary = WALLS_REVIEW.evidence(_main) if _walls_review else {}
	if _walls_review and not _walls_review_valid(walls_state):
		_fail_capture("walls review did not match its fixture or Wall finish tool state: " + JSON.stringify(walls_state))
		return
	var street_front_state: Dictionary = STREET_FRONT_REVIEW.evidence(_main, root) if _street_front_review else {}
	if _street_front_review and not STREET_FRONT_REVIEW.valid(street_front_state):
		_fail_capture("street-front review did not show its purchased items, finish, live name and owner: " \
			+ JSON.stringify(street_front_state))
		return
	var property_state: Dictionary = PROPERTY_REVIEW.evidence(_main) if _property_review else {}
	if _property_review and not PROPERTY_REVIEW.valid(property_state):
		_fail_capture("property review did not show the browse-only market: " + JSON.stringify(property_state))
		return
	var floors_state: Dictionary = FLOORS_REVIEW.evidence(_main) if _floors_review else {}
	if _floors_review and not _floors_capture_valid(floors_state):
		_fail_capture("floors review did not match its fixture or Floors tool state: " + JSON.stringify(floors_state))
		return
	var menu_boards_state: Dictionary = MENU_BOARDS_REVIEW.evidence(_main, root, _capture_frame) if _menu_boards_review else {}
	if _menu_boards_review and not MENU_BOARDS_REVIEW.valid(menu_boards_state, _capture_frame, _menu_boards_fixture):
		_fail_capture("menu boards review did not match its placed label or native inspector/Menu controls: " + JSON.stringify(menu_boards_state))
		return
	var signature_review_state: Dictionary = _signature_review_evidence(world) if not _signature_review.is_empty() else {}
	if not _signature_review.is_empty() and not _signature_review_valid(signature_review_state, world):
		_fail_capture("signature review did not match the actual Menu/board or demand report: " + JSON.stringify(signature_review_state))
		return
	var settings_state: Dictionary = _settings_state() if _settings else {}
	var hud_layout_state: Dictionary = _hud_layout_state() if _hud_layout else {}
	var shortcuts_state: Dictionary = _shortcuts_state() if _shortcuts else {}
	if _settings and not _settings_capture_valid(settings_state, world):
		_fail_capture("requested Settings view, UI scale or usual 1600x900 window did not match the rendered morning frame")
		return
	if _hud_layout and not _hud_layout_capture_valid(hud_layout_state, world):
		_fail_capture("HUD layout capture did not match its actual paused scale, window, frame or native Close path")
		return
	if _shortcuts and (world == null or world.now != 0 or world.clock.phase != SimClock.Phase.MORNING \
			or not _shortcuts_capture_valid(shortcuts_state)):
		_fail_capture("shortcuts capture did not show the actual focused F1 panel in the paused morning viewport")
		return
	var build: Dictionary = _build_state()
	if not _build.is_empty() and (build.get("active") != true or build.get("has_ghost") != true \
			or build.get("ghost_visible") != true or build.get("ok") != (_build != "red") \
			or build.get("ghost_valid") != (_build != "red") or build.get("origin") != build.get("pointer_cell") \
			or (_build == "pinch" and (build.get("aisle_pinches", []) as Array).is_empty())):
		_fail_capture("requested build preview was not present in the rendered frame")
		return
	if not _walls.is_empty() and not _walls_capture_valid():
		_fail_capture("requested walls view did not match the rendered shop")
		return
	if not _expand.is_empty() and not _expand_capture_valid():
		_fail_capture("requested floor expansion view did not match the rendered shop")
		return
	if not _rooms.is_empty() and not _rooms_capture_valid():
		_fail_capture("requested rooms view did not match the rendered shop")
		return
	var menu_visible: Variant = _main.call("is_menu_visible") if _main.has_method("is_menu_visible") else null
	if _menu and (menu_visible != true or world == null or world.clock.phase != SimClock.Phase.MORNING):
		_fail_capture("requested menu was not visible in the rendered morning frame")
		return
	var staff_state: Dictionary = _staff_state()
	if _staff and (staff_state.get("visible") != true or world == null or world.clock.phase != SimClock.Phase.MORNING \
			or world.now != 0 or not _staff_capture_valid(staff_state)):
		_fail_capture("requested Staff panel did not show the real paused morning roster and pool")
		return
	if _report_requested and not _stock:
		var report_valid: bool = _report_slowest_capture_valid(world) if _report_slowest_requested \
			else _report_capture_valid(world)
		if not report_valid:
			_fail_capture("requested report view did not match its real closed-day content and rendered bounds")
			return
	var stock_visible: Variant = _main.call("is_stock_visible") if _main.has_method("is_stock_visible") else null
	if _stock and not _open and (stock_visible != true or world == null \
			or world.clock.phase != SimClock.Phase.MORNING or world.now != 0):
		_fail_capture("requested Stock panel was not visible in the paused morning frame")
		return
	if _stock and _report_requested and not _low_stock_visible(world):
		_fail_capture("requested report did not show its Low stock section after service closed")
		return
	var sold_out_tag: Label = _main.get_node_or_null("HUD/Top/Row/SoldOut") as Label
	if _stock and _open and not _report_requested and (world == null or world.clock.phase == SimClock.Phase.CLOSED \
			or sold_out_tag == null or not sold_out_tag.is_visible_in_tree()):
		_fail_capture("requested service view did not show the HUD Sold out tag")
		return
	var paint: Dictionary = _paint_state() if _paint else {}
	if _paint and (paint.get("active") != true or paint.get("catalogue_visible") != true \
			or paint.get("swatch_count") != 40 or paint.get("grid_forced") != false \
			or paint.get("grid_visible") != false or paint.get("wall") != "sage" \
			or paint.get("floor") != "honey" or paint.get("table") != "terracotta" \
			or paint.get("plant") != "sage" or paint.get("rendered") != true \
			or world == null or world.now != 0 or world.clock.phase != SimClock.Phase.MORNING):
		_fail_capture("painted shop state did not match the rendered morning frame")
		return
	var selected_id: int = int(inspection.get("selected_agent_id", -1))
	var selected: SimAgent = world.agent(selected_id) if world != null else null
	var selected_live: bool = (_selection == &"guest" and selected is CustomerAgent) or (_selection == &"owner" and selected is OwnerAgent)
	if not _selection.is_empty():
		if _selected_agent_id < 1 or selected_id != _selected_agent_id or not selected_live or inspection.get("selected_role") != String(_selection) or inspection.get("panel_visible") != true:
			_fail_capture("requested live selection/panel was not present in the rendered frame")
			return
	if _assign_owner:
		var selected_owner: OwnerAgent = selected as OwnerAgent
		if not _owner_cook_task(selected_owner):
			_fail_capture("rendered owner is not actually assigned and claiming kitchen work")
			return
		if inspection.get("owner_mode") != "kitchen" or inspection.get("selected_task_id") != selected_owner.task.id or inspection.get("selected_task_claimant") != selected_id or inspection.get("selected_task_role") != "cook" or inspection.get("selected_task_state") != int(SimTask.State.CLAIMED) or inspection.get("selected_task_step") != selected_owner.step_index:
			_fail_capture("owner inspection/task metadata differs from the rendered simulation")
			return
	if _f3 and inspection.get("debug_visible") != true:
		_fail_capture("requested F3 overlay was not visible in the rendered frame")
		return
	if (not _selection.is_empty() or _f3) and (world == null or inspection.get("world_tick", -1) != world.now):
		_fail_capture("inspection world tick did not match the rendered simulation")
		return
	var rig: Node3D = _main.get_node_or_null("CameraRig") as Node3D
	var view: Node = _main.get_node_or_null("ShopView")
	var actual_quarter: Variant = null
	var yaw_degrees: Variant = null
	var wall_mode: Variant = null
	var lowered: Array = []
	if rig != null:
		yaw_degrees = fposmod(rad_to_deg(rig.rotation.y), 360.0)
		if rig.has_method("camera_quarter"):
			actual_quarter = rig.call("camera_quarter")
	if view != null and "wall_mode" in view:
		wall_mode = view.get("wall_mode")
		if view.has_method("lowered_wall_cells"):
			var cells: Array = view.call("lowered_wall_cells")
			for cell: Vector2i in cells:
				lowered.append([cell.x, cell.y])
	if _quarter >= 0:
		var expected_yaw: float = 45.0 + 90.0 * _quarter
		# The walls review puts the walls Up itself from WALL_UP_FRAME (its
		# --quarter covers the camera there, the Cutaway only before).
		var cutaway_expected: bool = not (_walls_review and _capture_frame >= WALLS_REVIEW.WALL_UP_FRAME)
		if actual_quarter != _quarter or (cutaway_expected and wall_mode != 1) or yaw_degrees == null \
				or absf(float(yaw_degrees) - expected_yaw) > 0.01:
			_fail_capture("requested camera quarter/cutaway mode did not match the rendered scene")
			return
	var path: String = _out.path_join("shot_%04d.png" % _capture_frame)
	var image: Image = root.get_viewport().get_texture().get_image()
	if _diner_review and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("diner review image did not match 1600x900")
		return
	if _settings and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("Settings viewport image did not match the usual 1600x900 dimensions")
		return
	if _hud_layout and (image == null or image.get_size() != _hud_window_size):
		_fail_capture("HUD layout viewport image did not match its requested window size")
		return
	if _loan_review and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("loan review image did not match the usual 1600x900 dimensions")
		return
	if _milestone_review and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("milestone review image did not match the usual 1600x900 dimensions")
		return
	if _property_review and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("property review image did not match the usual 1600x900 dimensions")
		return
	if _collections_review and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("collections review image did not match the usual 1600x900 dimensions")
		return
	if _menu_boards_review and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("menu boards review image did not match 1600x900")
		return
	if not _catalogue_profile.is_empty() and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("catalogue review image did not match 1600x900")
		return
	if not _lease_mode.is_empty() and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE \
			or OS.get_environment("FK_LEASE_CAPTURE_SHA").length() != 40 or OS.get_environment("FK_LEASE_CAPTURE_TREE").length() != 40):
		_fail_capture("lease review requires a 1600x900 image and committed source identity from screenshot.sh")
		return
	var world_render: Dictionary = _settings_world_evidence(image) if _settings_world else {}
	if image == null or image.is_empty() or image.save_png(path) != OK:
		_fail_capture("cannot save viewport image: " + path)
		return
	var image_hash: String = FileAccess.get_sha256(path)
	if image_hash.length() != 64:
		_fail_capture("cannot hash saved viewport image: " + path)
		return
	var master_seed: Variant = null
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state != null and "master_seed" in game_state:
		master_seed = str(game_state.get("master_seed"))
	var restaurant_rng: Dictionary = {}
	if "sim" in _main:
		var restaurant: RestaurantSim = _main.get("sim") as RestaurantSim
		if restaurant != null and restaurant.rng != null:
			restaurant_rng = {"seed": str(restaurant.rng.seed), "state": str(restaurant.rng.state)}
	var seed_override: int = int(_main.get("new_game_seed_override")) if "new_game_seed_override" in _main else 0
	var seed_source: String = "unavailable"
	if "new_game_seed_override" in _main:
		seed_source = "explicit_override" if seed_override != 0 else "wallclock_default"
	var metadata: Dictionary = {
		"image_file": path.get_file(), "image_sha256": image_hash,
		"scene": _scene_path, "frame": _capture_frame, "requested_quarter": _quarter,
		"actual_quarter": actual_quarter, "yaw_degrees": yaw_degrees,
		"wall_mode": wall_mode, "lowered_wall_cells": lowered,
		"width": image.get_width(), "height": image.get_height(),
		"godot_version": Engine.get_version_info()["string"],
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"engine_errors": _errors.count(),
		"capture_timing": "frame_post_draw",
		"requested_selection": String(_selection),
		"requested_owner_mode": "kitchen" if _assign_owner else "",
		"owner_mode": inspection.get("owner_mode", ""),
		"owner_warmup_ticks": _owner_warmup_ticks,
		"selected_task_id": inspection.get("selected_task_id", -1),
		"selected_task_role": inspection.get("selected_task_role", ""),
		"selected_task_label": inspection.get("selected_task_label", ""),
		"selected_task_state": inspection.get("selected_task_state", -1),
		"selected_task_claimant": inspection.get("selected_task_claimant", -1),
		"selected_task_step": inspection.get("selected_task_step", -1),
		"requested_debug_visible": _f3,
		"requested_menu_visible": _menu, "menu_visible": menu_visible,
		"requested_staff_visible": _staff, "staff": staff_state,
		"requested_stock": _stock, "stock_visible": stock_visible,
		"sold_out_tag": sold_out_tag.text if sold_out_tag != null and sold_out_tag.is_visible_in_tree() else "",
		"low_stock": (_main.get("shown_report") as DayReport).low_stock
			if _stock and _report_requested and _main.get("shown_report") != null else [],
		"requested_report": _report_requested,
		"requested_report_mode": "slowest-seller" if _report_slowest_requested else ("reviews" if _report_requested else ""),
		"report_review_count": (_main.get("shown_report") as DayReport).review_cards.size()
			if _report_requested else 0,
		"slowest_seller": _slowest_seller_capture_evidence() if _report_requested else {},
		"requested_build": _build, "build": build,
		"requested_paint": _paint, "paint": paint,
		"day_phase": int(world.clock.phase) if world != null else null,
		"selected_agent_id": inspection.get("selected_agent_id"),
		"selected_item_id": inspection.get("selected_item_id"),
		"selected_role": inspection.get("selected_role"),
		"selected_agent_live": selected_live,
		"panel_visible": inspection.get("panel_visible"),
		"debug_visible": inspection.get("debug_visible"),
		"world_tick": inspection.get("world_tick", world.now if world != null else null),
		"capture_parameters": {"open": _open, "fast_ticks_per_frame": _fast, "speed": _speed},
		"master_seed": master_seed, "restaurant_rng": restaurant_rng,
		"new_game_seed_override": str(seed_override),
		"seed_source": seed_source,
		"display_minutes": world.clock.display_minutes() if world != null else null,
		"requested_door_queue": _door_queue,
		"people": people_evidence(world, view, root.get_viewport().get_camera_3d()),
		"mood": mood_evidence(world, view, root.get_viewport().get_camera_3d()),
	}
	if _settings:
		metadata.merge({"requested_settings_visible": not _settings_world, "settings": settings_state,
			"requested_ui_scale_percent": _settings_scale,
			"requested_window_size": [SETTINGS_CAPTURE_SIZE.x, SETTINGS_CAPTURE_SIZE.y],
			"requested_clear_world": _settings_world, "world_render": world_render})
	if _shortcuts:
		metadata["requested_shortcuts_visible"] = true
		metadata["shortcuts"] = shortcuts_state
	if _hud_layout:
		metadata.merge({"requested_hud_layout": true, "hud_layout": hud_layout_state,
			"requested_ui_scale_percent": 125 if _capture_frame == 12 else 150,
			"requested_window_size": [_hud_window_size.x, _hud_window_size.y]})
	if not _lease_mode.is_empty():
		metadata["lease_review"] = {"fixture": _lease_fixture, "state": lease_state,
			"source_commit": OS.get_environment("FK_LEASE_CAPTURE_SHA"), "source_tree": OS.get_environment("FK_LEASE_CAPTURE_TREE")}
	if _loan_review:
		metadata["loan_review"] = {"fixture": _loan_fixture, "state": loan_state,
			"generated_uids": generated_uid_evidence()}
	if _milestone_review:
		metadata["milestone_review"] = {"fixture": _milestone_fixture, "state": milestone_state,
			"generated_uids": generated_uid_evidence(MILESTONE_UID_SOURCES)}
	if _collections_review:
		metadata["collections_review"] = {"fixture": _collections_fixture, "state": collections_state}
	if not _catalogue_profile.is_empty():
		metadata["catalogue_review"] = {"fixture": _catalogue_fixture, "state": catalogue_state,
			"generated_uids": generated_uid_evidence(CATALOGUE_UID_SOURCES)}
	if not _neighbourhood_mode.is_empty():
		metadata["neighbourhood_review"] = {"fixture": _neighbourhood_fixture, "state": neighbourhood_state}
	if not _weather_mode.is_empty():
		metadata["weather_review"] = {"fixture": _weather_fixture, "state": weather_state}
	if _joined_tables_review:
		metadata["joined_tables_review"] = {"fixture": _joined_tables_fixture, "state": joined_tables_state}
	if patio_review:
		metadata["patio_review"] = {"state": patio_state}
	if _property_review:
		metadata["property_review"] = {"fixture": _property_fixture, "state": property_state}
	if _floors_review:
		metadata["floors_review"] = {"fixture": _floors_fixture, "state": floors_state}
	if _restroom_review:
		metadata["restroom_review"] = {"fixture": "two-toilet restroom with standing owner",
			"close_view": _capture_frame >= 20}
	if not _blueprint_profile.is_empty():
		metadata["blueprints"] = {"fixture": _blueprint_fixture, "state": blueprint_state}
	if _walls_review:
		metadata["walls_review"] = {"fixture": _walls_fixture, "state": walls_state}
	if _menu_boards_review:
		metadata["menu_boards_review"] = {"fixture": _menu_boards_fixture, "state": menu_boards_state}
	if not _signature_review.is_empty():
		metadata["signature_review"] = {"mode": _signature_review, "fixture": _signature_fixture,
			"state": signature_review_state}
	if _street_front_review:
		metadata["street_front_review"] = {"fixture": _street_front_fixture, "state": street_front_state}
	if _diner_review:
		metadata["diner_review"] = {"fixture": _diner_fixture, "state": diner_state}
		if _capture_frame == 90:
			var crop: Dictionary = DINER_REVIEW.write_seated_crop(image, path, metadata, _out)
			if not String(crop.get("error", "missing crop result")).is_empty():
				_fail_capture(String(crop.get("error", "missing crop result")))
				return
			metadata["diner_review"]["booth_crop"] = crop
	if _staff:
		metadata["staff_priority_review"] = {"generated_uids": generated_uid_evidence(STAFF_PRIORITY_UID_SOURCES)}
	var file: FileAccess = FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if file == null:
		_fail_capture("cannot write capture metadata")
		return
	file.store_string(JSON.stringify(metadata, "\t"))
	file.flush()
	var metadata_error: Error = file.get_error()
	file.close()
	if metadata_error != OK:
		_fail_capture("cannot save capture metadata")
		return
	print("saved ", path)
	print("capture ", JSON.stringify(metadata))
	_capture_pending = false
	if _settings_world and world_render.get("verified") != true:
		# Retain this intended PNG and metadata for review, but fail the capture.
		_fail_capture("150% capture did not prove visible rendered shop pixels at frame 90 or later")
		return
	if _finish_requested:
		_finish_capture()


## This reads the live report and its native card labels after the frame draw.
## It does not add review fixtures or force a rating in the captured game.
func _report_capture_valid(world: SimWorld) -> bool:
	if world == null or world.clock.phase != SimClock.Phase.CLOSED or not "shown_report" in _main:
		return false
	var report: DayReport = _main.get("shown_report") as DayReport
	var panel: Control = _main.get_node_or_null("Overlay/EveningReport") as Control
	if report == null or report.review_cards.size() < 2 or panel == null or not panel.is_visible_in_tree():
		return false
	var rows: Node = panel.get_node_or_null("%ReviewRows")
	var scroll: ScrollContainer = panel.get_node_or_null("Panel/Scroll") as ScrollContainer
	if rows == null or rows.get_child_count() < 2 or scroll == null or scroll.scroll_vertical != 0:
		return false
	var viewport: Rect2 = scroll.get_global_rect()
	for index: int in range(mini(report.review_cards.size(), 3)):
		var card: Dictionary = report.review_cards[index]
		var native: Label = rows.get_child(index) as Label
		if native == null or String(card.get("quote", "")).is_empty() \
				or native.text != '%d stars - "%s"' % [int(card.get("stars", 0)), String(card["quote"])]:
			return false
		var rect: Rect2 = native.get_global_rect()
		if not native.is_visible_in_tree() or rect.size.x <= 0.0 or rect.size.y <= 0.0 \
				or rect.position.x < viewport.position.x - 1.0 or rect.end.x > viewport.end.x + 1.0 \
				or rect.position.y < viewport.position.y - 1.0 or rect.end.y > viewport.end.y + 1.0:
			return false
	return true


## Validate the real closing report while its native seller row is scrolled into view.
func _report_slowest_capture_valid(world: SimWorld) -> bool:
	if world == null or world.clock.phase != SimClock.Phase.CLOSED or not "shown_report" in _main:
		return false
	var report: DayReport = _main.get("shown_report") as DayReport
	var panel: Control = _main.get_node_or_null("Overlay/EveningReport") as Control
	if report == null or report.review_cards.size() < 2 or panel == null or not panel.is_visible_in_tree():
		return false
	var seller: Dictionary = report.slowest_dish_details()
	var label: Label = panel.get_node_or_null("%SlowestSeller") as Label
	var scroll: ScrollContainer = panel.get_node_or_null("Panel/Scroll") as ScrollContainer
	var sale_total: int = 0
	for count: int in report.dishes_sold.values():
		sale_total += count
	if seller.is_empty() or sale_total <= 0 or int(report.income.get(Ledger.SALE, 0)) <= 0 \
			or label == null or not label.is_visible_in_tree() or scroll == null or scroll.scroll_vertical <= 0:
		return false
	var hint: String = "Try a lower price" if int(seller["price"]) > int(seller["standard_price"]) \
		else "Guests may not fancy it; try another dish"
	var expected_text: String = "Slowest seller: %s (%d sold). %s or take it off the menu." % [
		String(seller["display_name"]), int(seller["sold"]), hint]
	var label_rect: Rect2 = label.get_global_rect()
	var viewport: Rect2 = scroll.get_global_rect()
	return label.text == expected_text and label_rect.size.x > 0.0 and label_rect.size.y > 0.0 \
		and label_rect.position.x >= viewport.position.x - 1.0 \
		and label_rect.end.x <= viewport.end.x + 1.0 \
		and label_rect.position.y >= viewport.position.y - 1.0 \
		and label_rect.end.y <= viewport.end.y + 1.0


## Evidence comes from the closed Main report and its rendered native label.
func _slowest_seller_capture_evidence() -> Dictionary:
	if not "shown_report" in _main:
		return {}
	var report: DayReport = _main.get("shown_report") as DayReport
	var panel: Control = _main.get_node_or_null("Overlay/EveningReport") as Control
	if report == null or panel == null:
		return {}
	var label: Label = panel.get_node_or_null("%SlowestSeller") as Label
	if label == null:
		return {}
	var scroll: ScrollContainer = panel.get_node_or_null("Panel/Scroll") as ScrollContainer
	var sales: int = 0
	for count: int in report.dishes_sold.values():
		sales += count
	return {
		"menu_count": report.slowest_seller_snapshot.get("menu_count", 0),
		"eligible_count": report.slowest_seller_snapshot.get("eligible_dishes", []).size(),
		"paid_dish_count": sales,
		"sale_total": int(report.income.get(Ledger.SALE, 0)),
		"selected": report.slowest_dish_details(),
		"label_visible": label.is_visible_in_tree(),
		"label_text": label.text,
		"scroll_vertical": scroll.scroll_vertical if scroll != null else null,
		"label_rect": _staff_rect_data(label.get_global_rect()),
		"capture_viewport": _staff_rect_data(
			(panel.get_node("Panel/Scroll") as ScrollContainer).get_global_rect()),
	}


## Read model records and actual native rows together, after the image draw.
func _staff_state() -> Dictionary:
	var panel: StaffPanel = _main.get_node_or_null("Overlay/StaffPanel") as StaffPanel
	if panel == null or not ("staff_roster" in _main):
		return {}
	var roster: StaffRoster = _main.get("staff_roster")
	if roster == null:
		return {}
	var rows: Array[Dictionary] = []
	var members: Array[StaffMember] = roster.members()
	var candidates: Array[StaffMember] = roster.candidates()
	for member: StaffMember in members + candidates:
		var row: Control = panel.row_for(member.id)
		if row == null:
			continue
		var button: Button = row.get_node("Top/Action") as Button
		rows.append({"id": String(member.id), "name_and_wage": (row.get_node("Top/Name") as Label).text,
			"trait": (row.get_node("Trait") as Label).text, "action": button.text,
			"disabled": button.disabled, "visible_in_tree": row.is_visible_in_tree()})
	var state: Dictionary = {"visible": panel.is_visible_in_tree(), "roster": roster.to_dict(), "rows": rows,
		"member_count": members.size(), "candidate_count": candidates.size()}
	if _staff:
		state["priority_grid"] = staff_priority_grid_evidence(panel, roster)
	return state


## Semantic state checks belong beside the captured native reads, not in CI.
func _staff_capture_valid(state: Dictionary) -> bool:
	var roster: Dictionary = state.get("roster", {})
	var members: Array = roster.get("members", [])
	var candidates: Array = roster.get("candidates", [])
	if members.size() != 2 or candidates.size() != 3 \
			or state.get("member_count") != 2 or state.get("candidate_count") != 3:
		return false
	var native_rows: Array = state.get("rows", [])
	var rows: Dictionary[String, Dictionary] = {}
	for row: Dictionary in native_rows:
		var id: String = row.get("id", "")
		if id.is_empty() or rows.has(id):
			return false
		rows[id] = row
	if rows.size() != 5:
		return false
	for person: Dictionary in members + candidates:
		var row: Dictionary = rows.get(person["id"], {})
		var title: String = row.get("name_and_wage", "")
		var definition: StaffTrait = StaffRoster.CATALOGUE.find_trait(StringName(person["trait"]))
		var action: String = "Let go" if members.has(person) else "Hire"
		if row.get("visible_in_tree") != true or not title.contains(person["name"]) \
				or not title.contains("skill %d" % int(person["skill"])) \
				or not title.contains("$%d/day" % int(person["wage"])) \
				or row.get("action") != action or definition == null \
				or not String(row.get("trait", "")).begins_with(definition.display_name + ":"):
			return false
	return staff_priority_grid_valid(state.get("priority_grid", {}), members)


## Read the real cells after drawing. This does not refresh the panel, change a
## choice, advance time or install a roster; missing integration fails closed.
static func staff_priority_grid_evidence(panel: StaffPanel, roster: StaffRoster) -> Dictionary:
	var grid: GridContainer = panel.get_node_or_null("%PriorityGrid") as GridContainer
	var scroll: ScrollContainer = panel.get_node_or_null("Panel/Content/Scroll") as ScrollContainer
	var card: Control = panel.get_node_or_null("Panel") as Control
	var close: Button = panel.get_node_or_null("%Close") as Button
	var note: Label = panel.get_node_or_null("%MainJobNote") as Label
	if grid == null or scroll == null or card == null or close == null or note == null or roster == null \
			or not panel.is_inside_tree() or grid.get_child_count() < StaffJobPriorities.JOBS.size() + 1:
		return {"available": false}
	var headers: Array[Dictionary] = []
	for index: int in range(StaffJobPriorities.JOBS.size() + 1):
		var label: Label = grid.get_child(index) as Label
		if label == null:
			return {"available": false}
		headers.append({"text": label.text, "visible": label.is_visible_in_tree(),
			"bounds": _staff_rect_data(_staff_pixel_rect(label))})
	var names: Array[Dictionary] = []
	var cells: Array[Dictionary] = []
	for member: StaffMember in roster.members():
		var row_index: int = (names.size() + 1) * (StaffJobPriorities.JOBS.size() + 1)
		if row_index >= grid.get_child_count():
			return {"available": false}
		var label: Label = grid.get_child(row_index) as Label
		if label == null:
			return {"available": false}
		names.append({"id": String(member.id), "text": label.text,
			"visible": label.is_visible_in_tree(), "bounds": _staff_rect_data(_staff_pixel_rect(label))})
		for job: StringName in StaffJobPriorities.JOBS:
			var button: Button = panel.priority_button_for(member.id, job)
			if button == null:
				return {"available": false}
			var style_name: StringName = &"disabled" if button.disabled else &"normal"
			var style: StyleBoxFlat = button.get_theme_stylebox(style_name) as StyleBoxFlat
			if style == null:
				return {"available": false}
			var color_name: StringName = &"font_disabled_color" if button.disabled else &"font_color"
			cells.append({"id": String(member.id), "job": String(job), "text": button.text,
				"disabled": button.disabled, "tooltip": button.tooltip_text,
				"style_state": String(style_name), "font_state": String(color_name),
				"style_override": button.has_theme_stylebox_override(style_name),
				"font_override": button.has_theme_color_override(color_name),
				"visible": button.is_visible_in_tree(), "clip_text": button.clip_text,
				"parent_is_grid": button.get_parent() == grid, "grid_index": button.get_index(),
				"bounds": _staff_rect_data(_staff_pixel_rect(button)),
				"minimum_bounds": _staff_rect_data(_staff_pixel_rect(button, button.get_combined_minimum_size())),
				"foreground": _staff_rgba(button.get_theme_color(color_name)),
				"background": _staff_rgba(style.bg_color), "border": _staff_rgba(style.border_color)})
	return {"available": true, "columns": grid.columns, "child_count": grid.get_child_count(),
		"headers": headers, "names": names, "cells": cells,
		"main_job_note": {"path": String(panel.get_path_to(note)), "text": note.text,
			"visible": note.is_visible_in_tree(), "bounds": _staff_rect_data(_staff_pixel_rect(note)),
			"minimum_bounds": _staff_rect_data(_staff_pixel_rect(note, note.get_combined_minimum_size())),
			"autowrap_mode": note.autowrap_mode, "size_flags_horizontal": note.size_flags_horizontal,
			"mouse_filter": note.mouse_filter, "focus_mode": note.focus_mode,
			"foreground": _staff_rgba(note.get_theme_color("font_color"))},
		"window_bounds": _staff_rect_data(Rect2(Vector2.ZERO, Vector2(panel.get_window().size))),
		"panel_bounds": _staff_rect_data(_staff_pixel_rect(card)),
		"close_bounds": _staff_rect_data(_staff_pixel_rect(close)), "close_visible": close.is_visible_in_tree(),
		"grid_bounds": _staff_rect_data(_staff_pixel_rect(grid)),
		"grid_minimum_bounds": _staff_rect_data(_staff_pixel_rect(grid, grid.get_combined_minimum_size())),
		"scroll_bounds": _staff_rect_data(_staff_pixel_rect(scroll)),
		"scroll_viewport_bounds": _staff_rect_data(_staff_scroll_viewport(scroll)),
		"scrollbars": [{"visible": scroll.get_v_scroll_bar().is_visible_in_tree(),
			"bounds": _staff_rect_data(_staff_pixel_rect(scroll.get_v_scroll_bar()))},
			{"visible": scroll.get_h_scroll_bar().is_visible_in_tree(),
			"bounds": _staff_rect_data(_staff_pixel_rect(scroll.get_h_scroll_bar()))}],
		"horizontal_scroll_mode": scroll.horizontal_scroll_mode}


## One pixel coordinate space, including the window's content scale. Use the
## native scrollbar positions rather than treating the outer Scroll as content.
static func _staff_pixel_rect(control: Control, extent: Vector2 = Vector2(-1.0, -1.0)) -> Rect2:
	var size: Vector2 = control.size if extent.x < 0.0 else extent
	return control.get_viewport().get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)


static func _staff_scroll_viewport(scroll: ScrollContainer) -> Rect2:
	var style: StyleBox = scroll.get_theme_stylebox("panel")
	var content: Rect2 = Rect2(Vector2(style.get_margin(SIDE_LEFT), style.get_margin(SIDE_TOP)),
		scroll.size - style.get_minimum_size())
	var clip: Rect2 = scroll.get_viewport().get_final_transform() * scroll.get_global_transform_with_canvas() * content
	var vertical: VScrollBar = scroll.get_v_scroll_bar()
	if vertical.is_visible_in_tree():
		var bar: Rect2 = _staff_pixel_rect(vertical)
		if bar.get_center().x < clip.get_center().x:
			var right: float = clip.end.x
			clip.position.x = maxf(clip.position.x, bar.end.x)
			clip.end.x = right
		else:
			clip.end.x = minf(clip.end.x, bar.position.x)
	var horizontal: HScrollBar = scroll.get_h_scroll_bar()
	if horizontal.is_visible_in_tree():
		clip.end.y = minf(clip.end.y, _staff_pixel_rect(horizontal).position.y)
	return clip


static func _staff_rect_data(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _staff_rect(record: Dictionary, key: String) -> Rect2:
	var value: Variant = record.get(key)
	if not value is Array or value.size() != 4:
		return Rect2()
	for number: Variant in value:
		if (typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT) or not is_finite(float(number)):
			return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _staff_rgba(color: Color) -> Array[float]:
	return [color.r, color.g, color.b, color.a]


## Validate captured native reads against the independently captured roster.
## This is only a paused-morning screenshot check, not service-picking evidence.
static func staff_priority_grid_valid(state: Dictionary, members: Array) -> bool:
	var columns: int = StaffJobPriorities.JOBS.size() + 1
	if state.get("available") != true or state.get("columns") != columns \
			or state.get("child_count") != columns * (members.size() + 1) \
			or state.get("horizontal_scroll_mode") != ScrollContainer.SCROLL_MODE_DISABLED:
		return false
	var window: Rect2 = _staff_rect(state, "window_bounds")
	var card: Rect2 = _staff_rect(state, "panel_bounds")
	var scroll: Rect2 = _staff_rect(state, "scroll_bounds")
	var viewport: Rect2 = _staff_rect(state, "scroll_viewport_bounds")
	var grid: Rect2 = _staff_rect(state, "grid_bounds")
	var minimum: Rect2 = _staff_rect(state, "grid_minimum_bounds")
	var close: Rect2 = _staff_rect(state, "close_bounds")
	if not window.has_area() or not card.has_area() or not scroll.has_area() or not viewport.has_area() \
			or not grid.has_area() or not minimum.has_area() or not close.has_area() \
			or not window.grow(0.5).encloses(card) or not card.grow(0.5).encloses(scroll) \
			or not scroll.grow(0.5).encloses(viewport) \
			or not card.grow(0.5).encloses(close) or state.get("close_visible") != true \
			or not viewport.grow(0.5).encloses(grid) or minimum.size.x > viewport.size.x + 0.5 \
			or grid.size.x < minimum.size.x - 0.5 or grid.size.y < minimum.size.y - 0.5:
		return false
	var note: Dictionary = state.get("main_job_note", {})
	var note_bounds: Rect2 = _staff_rect(note, "bounds")
	var note_minimum: Rect2 = _staff_rect(note, "minimum_bounds")
	if note.get("path") != "Panel/Content/Scroll/List/Priorities/MainJobNote" \
			or note.get("text") != "Each role's main job cannot be turned off." or note.get("visible") != true \
			or note.get("autowrap_mode") != TextServer.AUTOWRAP_WORD_SMART \
			or note.get("size_flags_horizontal") != Control.SIZE_EXPAND_FILL \
			or note.get("mouse_filter") != Control.MOUSE_FILTER_IGNORE or note.get("focus_mode") != Control.FOCUS_NONE \
			or note.get("foreground") != _staff_rgba(StaffPanel.SHARED_THEME.get_color("font_color", "Label")) \
			or not note_bounds.has_area() or not note_minimum.has_area() \
			or not viewport.grow(0.5).encloses(note_bounds) or note_bounds.position.y < grid.end.y - 0.5 \
			or note_bounds.size.x < note_minimum.size.x - 0.5 or note_bounds.size.y < note_minimum.size.y - 0.5:
		return false
	var scrollbars: Array = state.get("scrollbars", [])
	if scrollbars.size() != 2:
		return false
	for scrollbar: Dictionary in scrollbars:
		if scrollbar.get("visible") == true:
			var bounds: Rect2 = _staff_rect(scrollbar, "bounds")
			if not bounds.has_area() or viewport.intersection(bounds).has_area():
				return false
	var headers: Array = state.get("headers", [])
	var names: Array = state.get("names", [])
	var cells: Array = state.get("cells", [])
	if headers.size() != columns or names.size() != members.size() \
			or cells.size() != members.size() * StaffJobPriorities.JOBS.size():
		return false
	for index: int in range(columns):
		var expected: String = "Team member" if index == 0 else StaffJobPriorities.job_label(StaffJobPriorities.JOBS[index - 1])
		var header: Dictionary = headers[index]
		var bounds: Rect2 = _staff_rect(header, "bounds")
		if header.get("text") != expected or header.get("visible") != true \
				or not bounds.has_area() or not viewport.grow(0.5).encloses(bounds) or not grid.grow(0.5).encloses(bounds):
			return false
	var normal: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("normal", "Button") as StyleBoxFlat
	var muted: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("disabled", "Button") as StyleBoxFlat
	var accent: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("pressed", "Button") as StyleBoxFlat
	var panel: StyleBoxFlat = StaffPanel.SHARED_THEME.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	if normal == null or muted == null or accent == null or panel == null:
		return false
	for index: int in range(members.size()):
		var member: Dictionary = members[index]
		var choices: StaffJobPriorities = StaffJobPriorities.new(StringName(member.get("role", "")))
		if not choices.from_dict(member.get("priorities")):
			return false
		var name: Dictionary = names[index]
		var name_bounds: Rect2 = _staff_rect(name, "bounds")
		if name.get("id") != member.get("id") or not String(name.get("text", "")).contains(member.get("name", "")) \
				or name.get("visible") != true or not name_bounds.has_area() or not viewport.grow(0.5).encloses(name_bounds) \
				or not grid.grow(0.5).encloses(name_bounds):
			return false
		for job_index: int in range(StaffJobPriorities.JOBS.size()):
			var job: StringName = StaffJobPriorities.JOBS[job_index]
			var cell: Dictionary = cells[index * StaffJobPriorities.JOBS.size() + job_index]
			var bounds: Rect2 = _staff_rect(cell, "bounds")
			var cell_minimum: Rect2 = _staff_rect(cell, "minimum_bounds")
			var value: int = choices.priority(job)
			var supported: bool = StaffJobPriorities.supports(choices.role, job)
			if cell.get("id") != member.get("id") or cell.get("job") != String(job) \
					or cell.get("text") != (StaffJobPriorities.level_label(value) if supported else "—") \
					or cell.get("disabled") != (not supported) \
					or cell.get("style_state") != ("normal" if supported else "disabled") \
					or cell.get("font_state") != ("font_color" if supported else "font_disabled_color") \
					or cell.get("style_override") != true or cell.get("font_override") != true \
					or cell.get("visible") != true or cell.get("clip_text") != false or cell.get("parent_is_grid") != true \
					or cell.get("grid_index") != (index + 1) * columns + job_index + 1 \
					or not bounds.has_area() or not cell_minimum.has_area() or not viewport.grow(0.5).encloses(bounds) \
					or not grid.grow(0.5).encloses(bounds) or not bounds.position.is_equal_approx(cell_minimum.position) \
					or bounds.size.x < cell_minimum.size.x - 0.5 or bounds.size.y < cell_minimum.size.y - 0.5:
				return false
			var tooltip: String = cell.get("tooltip", "")
			if not supported and (value != StaffJobPriorities.Level.OFF or not tooltip.contains("not available for this role")):
				return false
			if job == StaffJobPriorities.main_job(choices.role) and (choices.can_set(job, StaffJobPriorities.Level.OFF) \
					or not tooltip.contains("main job cannot be Off")):
				return false
			if supported and not tooltip.contains("next task pick; current work continues"):
				return false
			var foreground: Color = StaffPanel.SHARED_THEME.get_color("font_color", "Button")
			var background: Color = normal.bg_color
			var border: Color = normal.border_color
			if not supported:
				foreground = Color(foreground, StaffPanel.LOCKED_TEXT_ALPHA)
				background = panel.bg_color
				border = Color(muted.border_color, StaffPanel.LOCKED_BORDER_ALPHA)
			elif value == StaffJobPriorities.Level.HIGH:
				border = accent.bg_color
			elif value == StaffJobPriorities.Level.LOW:
				background = muted.bg_color
				border = muted.border_color
			elif value == StaffJobPriorities.Level.OFF:
				background = foreground
				border = foreground
				foreground = StaffPanel.SHARED_THEME.get_color("font_pressed_color", "Button")
			if cell.get("foreground") != _staff_rgba(foreground) or cell.get("background") != _staff_rgba(background) \
					or cell.get("border") != _staff_rgba(border):
				return false
	return true


## Records actual rendered rigs independently beside the sim-derived expectation.
## Frustum membership reports visibility limits; it does not prove no occlusion.
static func people_evidence(world: SimWorld, view: Node, camera: Camera3D = null) -> Dictionary:
	var actors: Array[Dictionary] = []
	var queued: Array[int] = []
	var shop: ShopView = view as ShopView
	if world == null or shop == null:
		return {"available": false, "fixture": "none", "queue_present": false, "queued_ids": queued, "actors": actors}
	for agent: SimAgent in world.agents:
		var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(agent, world)
		var record: Dictionary = {"id": agent.id, "role": String(agent.role),
			"cell": [agent.cell.x, agent.cell.y], "next_cell": [agent.next_cell().x, agent.next_cell().y],
			"move_progress": agent.move_progress, "path_index": agent.path_index, "path_size": agent.path.size(),
			"has_arrived": agent.has_arrived(), "expected_clip": String(frame.clip), "seated": frame.seated}
		if agent is CustomerAgent:
			var guest: CustomerAgent = agent as CustomerAgent
			var table: PlacedItem = world.grid.item(guest.table_item_id)
			record.merge({"state": int(guest.state), "table_id": guest.table_item_id,
				"seat_cell": [guest.seat_cell.x, guest.seat_cell.y],
				"seat_member": table != null and table.seat_cells.has(guest.seat_cell),
				"seat_claimant": table.reserved_by(guest.seat_cell) if table != null else -1})
			if guest.state == CustomerAgent.State.QUEUED:
				queued.append(guest.id)
		var person: PersonView = shop.agent_nodes.get(agent.id) as PersonView
		record["native_person"] = person != null
		if person != null:
			record.merge({"model": String(person.model_name()), "clip": String(person.current_clip()),
				"display_separation_blocked": person.get_meta("display_separation_blocked", false),
				"floor_position": _point_evidence(frame.floor_position, camera),
				"drawn_position": _point_evidence(person.global_position, camera),
				"head": _point_evidence(person.global_transform * person.head_anchor_position(), camera),
				"seat_lift": (person.get_node("ModelPivot") as Node3D).position.y})
			var up: Dictionary = {}
			if person._skeleton != null:
				for name: String in ["root", "torso"]:
					var bone: int = person._skeleton.find_bone(name)
					if bone >= 0:
						var pose: Transform3D = person._skeleton.global_transform * person._skeleton.get_bone_global_pose(bone)
						var direction: Vector3 = pose.basis.y.normalized()
						up[name] = [direction.x, direction.y, direction.z]
				record["player_clip"] = String(person._player.current_animation) if person._player != null else ""
			record["bone_up"] = up
			var mood: GuestMoodIndicator = shop.mood_nodes.get(agent.id) as GuestMoodIndicator
			if mood != null:
				record["mood"] = _point_evidence(mood.global_position, camera)
				record["mood_radius"] = (mood.dot.mesh as SphereMesh).radius
		actors.append(record)
	return {"available": true, "fixture": "none", "queue_present": not queued.is_empty(), "queued_ids": queued,
		"camera_size": camera.size if camera != null else null, "actors": actors}


static func _point_evidence(point: Vector3, camera: Camera3D) -> Dictionary:
	var projected: Vector2 = camera.unproject_position(point) if camera != null else Vector2.ZERO
	return {"world": [point.x, point.y, point.z],
		"screen": [projected.x, projected.y] if camera != null else null,
		"in_frustum": camera.is_position_in_frustum(point) if camera != null else null}


## Read actual marker nodes; never derive their reported band from the guest.
static func mood_evidence(world: SimWorld, view: Node, camera: Camera3D = null) -> Dictionary:
	var waiting: Array[Dictionary] = []
	var indicators: Array[Dictionary] = []
	var shop: ShopView = view as ShopView
	if world == null or shop == null:
		return {"available": false, "fixture": "none", "waiting_guests": waiting, "visible_indicators": indicators}
	for agent: SimAgent in world.agents:
		if agent is CustomerAgent:
			var guest: CustomerAgent = agent as CustomerAgent
			if CustomerAgent.MOOD_WAITING_STATES.has(int(guest.state)):
				waiting.append({"id": guest.id, "state": int(guest.state),
					"mood": guest.mood(), "band": guest.mood_band(),
					"queue_wait": guest._queue_wait, "queue_patience": guest.queue_patience,
					"food_wait": guest._food_wait, "food_patience": guest.food_patience,
					"rng_seed": str(guest.rng.seed), "rng_state": str(guest.rng.state)})
	var ids: Array[int] = []
	ids.assign(shop.mood_nodes.keys())
	ids.sort()
	for id: int in ids:
		var icon: GuestMoodIndicator = shop.mood_nodes[id]
		if not is_instance_valid(icon) or not icon.is_visible_in_tree() or not icon.dot.is_visible_in_tree():
			continue
		var color: Color = (icon.dot.material_override as StandardMaterial3D).albedo_color
		var screen: Variant = null
		var in_frustum: Variant = null
		if camera != null:
			var projected: Vector2 = camera.unproject_position(icon.global_position)
			screen = [projected.x, projected.y]
			in_frustum = camera.is_position_in_frustum(icon.global_position)
		indicators.append({"id": id, "band": icon.band,
			"parent_agent_id": icon.get_parent().get_meta("agent_id", -1),
			"visible_in_tree": icon.is_visible_in_tree(), "dot_visible": icon.dot.is_visible_in_tree(),
			"mark": icon.mark.text, "mark_visible": icon.mark.is_visible_in_tree(),
			"color": [color.r, color.g, color.b, color.a],
			"screen_position": screen, "in_camera_frustum": in_frustum})
	return {"available": true, "fixture": "none", "waiting_guests": waiting, "visible_indicators": indicators}


func _finish_capture() -> void:
	if _finished:
		return
	# quit() is deferred; a later process/render callback must not tear down twice.
	_finished = true
	_capture_pending = false
	if RenderingServer.frame_post_draw.is_connected(_capture):
		RenderingServer.frame_post_draw.disconnect(_capture)
	OS.remove_logger(_errors)
	quit(1 if _failed or _errors.count() > 0 else 0)


func _fail_capture(message: String) -> void:
	_failed = true
	printerr("ERROR: capture failed: ", message)
	_finish_capture()
