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
##   --settings  open Main -> Menu -> Settings at the usual 1600x900 / 100%
##   --settings-world  use the gear, select 150%, keyboard Close, show the world
##   --hud-layout --window-size=1280x720|1600x900 --speed=0 --frames=12,90
##             use the gear and keyboard Close; capture native HUD at 125%, then 150%
##   --report    require a closed-day report with at least two real review cards
##   --build=green|red  hold a checked buy preview through the production input API
##   --paint     show a painted morning shop using the production paint controls
##   --door-queue  zoom the existing camera onto a real queue, or its empty entry
##   --loan-review --speed=0 --frames=12,90  explicit financial-fixture UI evidence
##   --catalogue-review=rustic|modern --speed=0 --frames=90,120  furnishing fixture
## Ordinary captures record real moods, markers and seeds without a fixture.

const MAX_CAPTURE_WAIT_FRAMES: int = 8
const MAX_OWNER_WARMUP_TICKS: int = 900
const SETTINGS_CAPTURE_SIZE: Vector2i = Vector2i(1600, 900)
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
var _settings: bool = false
var _settings_from_menu: bool = false
var _settings_world: bool = false
var _settings_scale: int = 100
var _settings_keyboard: Dictionary = {}
var _hud_layout: bool = false
var _hud_window_size: Vector2i = Vector2i(1600, 900)
var _hud_layout_scale: int = 125
var _report_requested: bool = false
var _build: String = ""
var _paint: bool = false
var _door_queue: bool = false
var _loan_review: bool = false
var _loan_fixture: Dictionary = {}
var _catalogue_profile: StringName = &""
var _catalogue_fixture: Dictionary = {}
var _build_pointer: Vector2 = Vector2.ZERO
var _selected_agent_id: int = -1
var _capture_pending: bool = false
var _capture_frame: int = 0
var _capture_wait_frames: int = 0
var _finish_requested: bool = false


func _initialize() -> void:
	OS.add_logger(_errors)
	var loan_options: Dictionary = loan_review_options(OS.get_cmdline_user_args())
	if not String(loan_options["error"]).is_empty():
		_fail_capture(loan_options["error"])
		return
	_loan_review = loan_options["enabled"]
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
		elif arg.begins_with("--menu"):
			if arg != "--menu":
				_fail_capture("--menu does not accept a value")
				return
			_menu = true
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
		elif arg == "--report":
			_report_requested = true
		elif arg.begins_with("--build"):
			var requested: String = arg.trim_prefix("--build=")
			if not ["green", "red"].has(requested):
				_fail_capture("--build supports green or red")
				return
			_build = requested
		elif arg == "--paint":
			_paint = true
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
	if _menu and (_open or not _selection.is_empty()):
		_fail_capture("--menu requires morning and cannot combine with --open or --select")
		return
	if _staff and (_open or _fast != 0 or not _selection.is_empty() or _assign_owner or _f3 or _menu or _speed != 0):
		_fail_capture("--staff requires a paused morning without other service/panel options")
		return
	if _report_requested and (not _open or _fast <= 0 or _speed != 0 or _menu or _staff or not _build.is_empty()):
		_fail_capture("--report requires a fast-forwarded, paused-clock service view")
		return
	if _settings and (_scene_path != "res://src/world/main.tscn" or _open or _fast != 0 \
			or not _selection.is_empty() or _assign_owner or _f3 or _menu or _staff \
			or _report_requested or not _build.is_empty() or _paint or _quarter >= 0 \
			or _speed != 0 or _shots.size() != 1):
		_fail_capture("--settings requires one paused Main capture without other view/service flags")
		return
	if _shots.is_empty() or _shots.min() < 1 or ((_quarter >= 0 or not _selection.is_empty() or _f3 or _menu or _staff or _settings or not _build.is_empty() or _paint or _door_queue) and _shots.min() < 4):
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
	if _report_requested and "new_game_seed_override" in _main:
		_main.set("new_game_seed_override", 1)
	root.add_child(_main)


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
	return {"items": items, "category": &"seating" if rustic else &"decor",
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
	for target: Dictionary in [{"swatch": recipe["wall"], "cell": Vector2i(0, 6)},
			{"swatch": recipe["floor"], "cell": Vector2i(1, 9)}]:
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
static func _catalogue_content_expectations(content: ContentDB) -> Dictionary:
	var cards: Array[Dictionary] = []
	var wrappers: Array[String] = []
	for definition: ItemDef in content.items():
		if definition == null or not definition.catalogue_visible or definition.id.is_empty() \
				or definition.display_name.strip_edges().is_empty() or definition.price < 0 or definition.unlock_level < 1 \
				or definition.footprint.x < 1 or definition.footprint.y < 1 or not definition.placement_layer_valid() \
				or not [ItemDef.Category.TABLE, ItemDef.Category.CHAIR, ItemDef.Category.STATION,
					ItemDef.Category.STORAGE, ItemDef.Category.PASS, ItemDef.Category.DECOR].has(definition.category):
			continue
		var path: String = definition.view_scene.resource_path if definition.view_scene != null else ""
		cards.append({"id": String(definition.id), "name": definition.display_name, "price": definition.price,
			"unlock_level": definition.unlock_level, "scene": path})
		if not path.is_empty() and not wrappers.has(path):
			wrappers.append(path)
	wrappers.sort()
	return {"cards": cards, "wrappers": wrappers}


## Read existing cache entries only: request() would queue missing thumbnails.
## Visibility here means native clipping geometry, not an aesthetic verdict.
static func catalogue_review_evidence(main: Node, context_root: Node) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var content: ContentDB = main.get("content") as ContentDB
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var catalogue: BuildCatalogue = main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var shop: ShopView = main.get_node_or_null("ShopView") as ShopView
	var clock: Node = context_root.get_node_or_null("Clock")
	if world == null or editor == null or content == null or progress == null or catalogue == null or shop == null or clock == null:
		return {"available": false}
	var cache: ItemThumbnailCache = catalogue._thumbnails
	var expected: Dictionary = _catalogue_content_expectations(content)
	var cached_scenes: Array[String] = []
	for key: int in cache._textures:
		var scene: PackedScene = cache._scenes.get(key) as PackedScene
		cached_scenes.append(scene.resource_path if scene != null else "")
	cached_scenes.sort()
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
			texture = cache._textures.get(scene.get_instance_id()) as Texture2D
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
			"native": _loan_control_evidence(button)})
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
		"wall": String(editor.wall_swatch_id), "floor": String(editor.floor_swatch_id),
		"cache": {"supported": cache.rendering_supported(), "pending": cache.pending_count(), "cached": cache.cached_count(),
			"expected": expected["wrappers"].size(), "expected_scenes": expected["wrappers"], "cached_scenes": cached_scenes,
			"active": cache._active_scene != null, "failed": cache._failed.size(),
			"error": cache.last_error, "icons_match": icons_match},
		"expected_cards": expected["cards"], "cards": cards, "onscreen_cards": onscreen, "tabs": tabs, "items": items,
		"server": _catalogue_server_evidence(world, shop, main.get_node_or_null("CameraRig/Camera3D") as Camera3D),
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
	if state["tabs"].size() != BuildCatalogue.CATEGORY_IDS.size():
		return false
	for tab: Dictionary in state["tabs"]:
		var id: StringName = StringName(tab["id"])
		if tab["text"] != BuildCatalogue.CATEGORY_LABELS.get(id, "") or tab["pressed"] != (id == profile["category"]) \
				or tab["native"]["visible"] != true or tab["native"]["inside_clip"] != true:
			return false
	var cache: Dictionary = state["cache"]
	return cache["supported"] == true and cache["pending"] == 0 and cache["active"] == false \
		and cache["failed"] == 0 and cache["error"] == "" and cache["icons_match"] == true and cache["cached"] == cache["expected"] \
		and cache["cached_scenes"] == cache["expected_scenes"]


## Re-evaluate the actual layout/menu/paint independently of Main's cached
## result, then read the already-created native meter without repairing it.
static func catalogue_vibe_evidence(main: Node, world: SimWorld, content: ContentDB,
		editor: ShopEditor, catalogue: BuildCatalogue) -> Dictionary:
	var menu: MenuSettings = main.get("menu_settings") as MenuSettings
	var meter: VibeMeter = catalogue.get_node_or_null("Panel/Margin/Rows/Scroll/Content/VibeMeter") as VibeMeter
	var panel: Control = catalogue.get_node_or_null("Panel") as Control
	var scroll: ScrollContainer = catalogue.get_node_or_null("Panel/Margin/Rows/Scroll") as ScrollContainer
	if not ("vibe_result" in main) or menu == null or meter == null or panel == null or scroll == null:
		return {"available": false}
	var inputs: VibeModel.Inputs = VibeInputs.capture(world.grid, content, menu.enabled_recipes(),
		editor.wall_swatch_id, editor.floor_swatch_id)
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
		"inputs": {"wall": String(editor.wall_swatch_id), "floor": String(editor.floor_swatch_id),
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
		var text: String = "%s\nLevel %d" % [definition["name"], definition["unlock_level"]] if locked \
			else "%s\n$%d" % [definition["name"], definition["price"]]
		if card.get("scene") != definition["scene"] or card.get("text") != text or card.get("disabled") != locked:
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
static func _catalogue_server_evidence(world: SimWorld, shop: ShopView, camera: Camera3D) -> Dictionary:
	for agent: SimAgent in world.agents:
		if not agent is StaffAgent or agent is OwnerAgent or agent.role != &"server":
			continue
		var person: PersonView = shop.agent_nodes.get(agent.id) as PersonView
		var record: Dictionary = {"available": true, "id": agent.id, "role": String(agent.role),
			"cell": [agent.cell.x, agent.cell.y], "native_person": person != null,
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
	if server.get("available") != true or server.get("native_person") != true \
			or server.get("visible") != true or server.get("model_visible") != true \
			or server.get("role") != "server" or server.get("native_role") != "server" or server.get("cell") != [8, 8] \
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
	if frame != 12 or state["day"] != 1 or state["phase"] != SimClock.Phase.CLOSED \
			or state["report_present"] != true or state["report_day"] != 1 or state["report_first_advance"] != true \
			or state["report"]["visible"] != true or state["notice"]["visible"] != true \
			or state["notice"]["inside_clip"] != true or state["notice"]["text"] != LOAN_NOTICE \
			or state["report_bank_advance"] != int(state["principal"]) \
			or state["report_cash_change"] != state["settled_day_cash_change"] \
			or state["report_cash_change"] != state["report_operating_profit"] + state["report_bank_advance"] \
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
		for prefix: String in ["--open", "--fast", "--select", "--assign-owner", "--f3", "--menu", "--staff", "--settings", "--report", "--build", "--paint", "--quarter", "--door-queue", "--loan-review", "--catalogue-review"]:
			if argument.begins_with(prefix):
				result["error"] = "--hud-layout cannot combine with other view or service options"
	if speed_count != 1 or frames_count != 1:
		result["error"] = "--hud-layout requires one --speed=0 and one --frames=12,90"
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
	if _frames == 3:
		# Autoloads aren't compile-time identifiers in a --script main loop.
		var clock: Node = root.get_node("Clock")
		if _open:
			(clock.get("sim") as SimClock).start_service()
		clock.call("set_speed", _speed)
		_configure_camera()
		if _failed:
			return true
		if _loan_review:
			_loan_fixture = prepare_loan_review(_main, root)
			if not String(_loan_fixture["error"]).is_empty():
				_fail_capture(_loan_fixture["error"])
				return true
		if not _catalogue_profile.is_empty():
			_catalogue_fixture = prepare_catalogue_review(_main, root, _catalogue_profile)
			if not String(_catalogue_fixture["error"]).is_empty():
				_fail_capture(_catalogue_fixture["error"])
				return true
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
	if not _build.is_empty() and _frames >= 3:
		_hold_build_pointer()
	if _fast > 0 and _frames > 3 and _main.has_method("run_ticks"):
		_main.call("run_ticks", _fast)
	if not _selection.is_empty() and _frames >= 3:
		_select_live_agent()
		if _failed:
			return true
	_finish_requested = _frames >= _shots.max()
	if _shots.has(_frames):
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


func _open_settings_control(from_gear: bool, percent: int) -> void:
	if not _main.has_method("set_menu_visible") or not _main.has_method("is_menu_visible") \
			or not _main.has_method("is_settings_visible"):
		_fail_capture("Settings capture requires Main's production panel APIs")
		return
	var button_path: NodePath = ^"HUD/Top/Row/Settings" if from_gear else ^"Overlay/MenuPanel/Panel/Content/SettingsButton"
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
	var edge: CheckButton = panel.get_node("Panel/Column/Scroll/Content/EdgePanToggle") as CheckButton
	var close: Button = panel.get_node("Panel/Column/CloseButton") as Button
	var scroll: ScrollContainer = panel.get_node("Panel/Column/Scroll") as ScrollContainer
	scroll.ensure_control_visible(edge)
	edge.grab_focus()
	var from_edge: bool = root.gui_get_focus_owner() == edge
	_settings_key(KEY_TAB, true)
	_settings_key(KEY_TAB, false)
	_settings_keyboard = {"tab_from_edge_pan": from_edge, "tab_to_close": root.gui_get_focus_owner() == close,
		"close_visible": _settings_card_bounded(panel), "accept_key": "Enter", "input_frame": _frames}
	if not from_edge or _settings_keyboard["tab_to_close"] != true or _settings_keyboard["close_visible"] != true:
		_fail_capture("native Tab did not focus the visible pinned Close button")
		return
	_settings_key(KEY_ENTER, true)
	_settings_key(KEY_ENTER, false)


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
	for y: int in range(view.world.grid.size.y):
		for x: int in range(view.world.grid.size.x):
			var cell: Vector2i = Vector2i(x, y)
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
					witnesses.append({"cell": [x, y], "pixel": [at.x, at.y], "rgb": [average.r, average.g, average.b]})
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
	var samples: Array[Dictionary] = [
		{"swatch": &"sage", "cell": Vector2i(0, 5)},
		{"swatch": &"honey", "cell": Vector2i(8, 8)},
		{"swatch": &"terracotta", "cell": Vector2i(2, 6)},
		{"swatch": &"sage", "cell": Vector2i(12, 9)},
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
	if tables.is_empty() or plants.is_empty() or view.get_node("Walls").get_child_count() == 0:
		return {}
	var wall: MeshInstance3D = view.get_node("Walls").get_child(0) as MeshInstance3D
	var floor_shader: ShaderMaterial = view.floor_mesh.material_override as ShaderMaterial
	var table_material: BaseMaterial3D = view.item_nodes[tables[0].id].primary_body_material()
	var plant_material: BaseMaterial3D = view.item_nodes[plants[0].id].primary_body_material()
	var content: ContentDB = _main.get("content") as ContentDB
	return {"active": _main.call("is_paint_active"), "catalogue_visible": catalogue.is_visible_in_tree(),
		"swatch_count": catalogue.swatch_buttons.size(), "grid_forced": rig.is_grid_forced(),
		"grid_visible": rig.effective_grid_visible(), "wall": String(editor.wall_swatch_id),
		"floor": String(editor.floor_swatch_id), "table": String(tables[0].swatch_id),
		"plant": String(plants[0].swatch_id),
		"rendered": (wall.material_override as StandardMaterial3D).albedo_color == content.swatch(&"sage").color \
			and floor_shader.get_shader_parameter("floor_color") == content.swatch(&"honey").color \
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
	var def_id: StringName = &"table_2" if _build == "green" else &"fridge"
	var cell: Vector2i = Vector2i(8, 8) if _build == "green" else Vector2i(7, 7)
	var turns: int = 0 if _build == "green" else 1
	if editor == null or camera == null or not editor.can_edit() \
			or editor.check_buy(def_id, cell, turns).ok != (_build == "green"):
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
		"ghost_valid": ghost.get_meta("valid", null) if is_instance_valid(ghost) else null}


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
	var loan_state: Dictionary = loan_review_evidence(_main, root) if _loan_review else {}
	if _loan_review and not loan_review_valid(loan_state, _capture_frame, _loan_fixture):
		_fail_capture("loan review did not match its real account, phase and visible native controls")
		return
	var catalogue_state: Dictionary = catalogue_review_evidence(_main, root) if not _catalogue_profile.is_empty() else {}
	if not _catalogue_profile.is_empty() and not catalogue_review_valid(catalogue_state, _capture_frame, _catalogue_fixture):
		_fail_capture("catalogue review did not match its fixture, real previews, seating links or bounds: " + JSON.stringify({
			"cache": catalogue_state.get("cache", {}), "vibe": catalogue_state.get("vibe", {}),
			"generated_vibe_uids": catalogue_state.get("generated_vibe_uids", {})}))
		return
	var settings_state: Dictionary = _settings_state() if _settings else {}
	var hud_layout_state: Dictionary = _hud_layout_state() if _hud_layout else {}
	if _settings and not _settings_capture_valid(settings_state, world):
		_fail_capture("requested Settings view, UI scale or usual 1600x900 window did not match the rendered morning frame")
		return
	if _hud_layout and not _hud_layout_capture_valid(hud_layout_state, world):
		_fail_capture("HUD layout capture did not match its actual paused scale, window, frame or native Close path")
		return
	var build: Dictionary = _build_state()
	if not _build.is_empty() and (build.get("active") != true or build.get("has_ghost") != true \
			or build.get("ghost_visible") != true or build.get("ok") != (_build == "green") \
			or build.get("ghost_valid") != (_build == "green") or build.get("origin") != build.get("pointer_cell")):
		_fail_capture("requested build preview was not present in the rendered frame")
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
	if _report_requested and not _report_capture_valid(world):
		_fail_capture("requested report did not show visible native reviews after service closed")
		return
	var paint: Dictionary = _paint_state() if _paint else {}
	if _paint and (paint.get("active") != true or paint.get("catalogue_visible") != true \
			or paint.get("swatch_count") != 12 or paint.get("grid_forced") != false \
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
		if actual_quarter != _quarter or wall_mode != 1 or yaw_degrees == null or absf(float(yaw_degrees) - expected_yaw) > 0.01:
			_fail_capture("requested camera quarter/cutaway mode did not match the rendered scene")
			return
	var path: String = _out.path_join("shot_%04d.png" % _capture_frame)
	var image: Image = root.get_viewport().get_texture().get_image()
	if _settings and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("Settings viewport image did not match the usual 1600x900 dimensions")
		return
	if _hud_layout and (image == null or image.get_size() != _hud_window_size):
		_fail_capture("HUD layout viewport image did not match its requested window size")
		return
	if _loan_review and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("loan review image did not match the usual 1600x900 dimensions")
		return
	if not _catalogue_profile.is_empty() and (image == null or image.get_size() != SETTINGS_CAPTURE_SIZE):
		_fail_capture("catalogue review image did not match 1600x900")
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
		"requested_report": _report_requested,
		"report_review_count": (_main.get("shown_report") as DayReport).review_cards.size()
			if _report_requested else 0,
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
	if _hud_layout:
		metadata.merge({"requested_hud_layout": true, "hud_layout": hud_layout_state,
			"requested_ui_scale_percent": 125 if _capture_frame == 12 else 150,
			"requested_window_size": [_hud_window_size.x, _hud_window_size.y]})
	if _loan_review:
		metadata["loan_review"] = {"fixture": _loan_fixture, "state": loan_state,
			"generated_uids": generated_uid_evidence()}
	if not _catalogue_profile.is_empty():
		metadata["catalogue_review"] = {"fixture": _catalogue_fixture, "state": catalogue_state,
			"generated_uids": generated_uid_evidence(CATALOGUE_UID_SOURCES)}
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
