extends TestCase
## Real Main close, purchase boundaries and the existing morning Economy save.
## These short empty-service fixtures do not sample long-run loan balance.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const TERMS: LoanTuning = preload("res://data/balance/loans.tres")
const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")
const SLOT: String = "loan_session"
const LOAN_HINT: String = "Pay off your bank loan first"
const CAPTURE_SCRIPT: GDScript = preload("res://tools/screenshot.gd")

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}
var _capture_window_size: Vector2i = Vector2i.ZERO
var _capture_content_scale: float = 1.0


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "loan_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)
	_old_providers = SaveSystem._providers.duplicate()
	Clock.set_speed(0)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
	if _capture_window_size != Vector2i.ZERO:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		tree.root.size = _capture_window_size
		tree.root.content_scale_factor = _capture_content_scale
		_capture_window_size = Vector2i.ZERO
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(_save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_save_dir
	SaveSystem._providers.clear()
	for key: String in _old_providers:
		var provider: Dictionary = _old_providers[key]
		SaveSystem.register(key, provider["capture"], provider["restore"])
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_real_close_covers_wages_and_rent_before_report_once_without_bank_xp_or_save() -> void:
	var main: Node = await _start()
	var morning_file: String = _saved_text()
	_fresh_books(0)
	var closing_cost: int = _closing_cost(main)
	var expected_advance: int = ceili(float(closing_cost) / float(TERMS.borrowing_step)) * TERMS.borrowing_step
	_close_service(main)
	var report: DayReport = main.get("shown_report") as DayReport
	assert_not_null(report)
	if report == null:
		return
	assert_eq(Economy.loan.principal, expected_advance)
	assert_eq(Economy.loan.last_settled_day, 1)
	assert_eq(Economy.cash, expected_advance - closing_cost)
	assert_true(Economy.cash >= 0)
	assert_eq(report.income.get(Ledger.BANK_LOAN, 0), expected_advance)
	assert_eq(report.costs.get(Ledger.WAGES, 0), (main.get("staff_roster") as StaffRoster).total_wages())
	assert_eq(report.costs.get(Ledger.RENT, 0), TUNING.daily_rent)
	assert_false(report.costs.has(Ledger.LOAN_INTEREST), "a new advance starts interest tomorrow")
	assert_eq(report.profit(), Economy.ledger.day_profit(1))
	assert_eq(report.profit(), Economy.cash, "all close movements are present in the report")
	assert_eq(report.owner_xp_breakdown["profit_xp"], 0, "the rounded bank advance earns no owner XP")
	assert_true(report.loan_first_advance, "both close-time report builds retain the first introduction")
	assert_true((main.call("build_report", 1) as DayReport).loan_first_advance)
	var notice: Label = main.get_node("Overlay/EveningReport/Panel/Scroll/Content/LoanNotice") as Label
	assert_true(notice.visible)
	assert_eq(notice.text, "The bank covered your shortfall. It'll take a share of your profits until it's paid back.")
	var chip: Label = main.get_node("HUD/Top/Row/Loan") as Label
	assert_true(chip.visible)
	assert_eq(chip.text, "Loan %s" % Fmt.money(expected_advance))
	assert_eq(_saved_text(), morning_file, "closing does not add a save point")
	var books: Dictionary = Economy.ledger.to_dict()
	var loan: Dictionary = Economy.loan.to_dict()
	var owner: Dictionary = (main.get("owner_progress") as OwnerProgress).to_dict()
	var shown: Dictionary = report.to_dict()
	main.call("_on_service_closed", 1)
	main.call("_on_service_closed", 2)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.loan.to_dict(), loan)
	assert_eq((main.get("owner_progress") as OwnerProgress).to_dict(), owner)
	assert_eq((main.get("shown_report") as DayReport).to_dict(), shown)
	assert_eq(_saved_text(), morning_file)


func test_existing_loan_interest_and_repayment_reach_report_but_owner_uses_operating_profit() -> void:
	var main: Node = await _start()
	_fresh_books(0, 200)
	var operating_profit: int = 200
	Economy.add_cash(_closing_cost(main) + operating_profit, Ledger.SALE)
	var expected_interest: int = roundi(200.0 * TERMS.daily_interest)
	var expected_repayment: int = mini(200, maxi(1, floori(float(operating_profit) * TERMS.repay_share)))
	var expected_owner: OwnerProgress = OwnerProgress.new(PROGRESSION)
	var award: Dictionary = expected_owner.award_day(1, 0, operating_profit)
	_close_service(main)
	var report: DayReport = main.get("shown_report") as DayReport
	assert_eq(report.costs.get(Ledger.LOAN_INTEREST, 0), expected_interest)
	assert_eq(report.costs.get(Ledger.LOAN_REPAYMENT, 0), expected_repayment)
	assert_false(report.income.has(Ledger.BANK_LOAN))
	assert_eq(Economy.loan.principal, 200 - expected_repayment)
	assert_eq(report.profit(), operating_profit - expected_interest - expected_repayment)
	assert_eq(report.profit(), Economy.cash)
	assert_eq(report.owner_xp_breakdown["profit_xp"], award["profit_xp"], "repayment and interest do not reduce owner profit XP")
	assert_eq((main.get("owner_progress") as OwnerProgress).to_dict(), expected_owner.to_dict())
	var books: Dictionary = Economy.ledger.to_dict()
	main.call("_on_service_closed", 1)
	assert_eq(Economy.ledger.to_dict(), books, "interest, repayment and wages each apply once")


func test_solvent_close_with_no_principal_has_no_financing_entries() -> void:
	var main: Node = await _start(false)
	_fresh_books(0)
	Economy.add_cash(_closing_cost(main) + 100, Ledger.SALE)
	_close_service(main)
	var totals: Dictionary = Economy.ledger.day_totals(1)
	assert_false(totals.has(Ledger.BANK_LOAN))
	assert_false(totals.has(Ledger.LOAN_INTEREST))
	assert_false(totals.has(Ledger.LOAN_REPAYMENT))
	assert_eq(Economy.loan.principal, 0)
	assert_eq(Economy.loan.last_settled_day, 1)
	assert_eq((main.get("shown_report") as DayReport).profit(), 100)
	assert_eq(Economy.cash, 100)


func test_next_morning_saves_loan_inside_economy_and_reload_preserves_guard_and_books() -> void:
	var first: Node = await _start()
	var original: String = _saved_text()
	_fresh_books(0)
	_close_service(first)
	var closed_loan: Dictionary = Economy.loan.to_dict()
	assert_eq(_saved_text(), original)
	assert_true(Clock.sim.next_day())
	var document: Dictionary = _document()
	assert_false(document["data"].has("loan"), "loan state uses the existing Economy section")
	assert_eq(document["data"]["economy"]["loan"], JSON.parse_string(JSON.stringify(closed_loan)))
	assert_true(document["data"]["economy"]["loan"]["has_borrowed"])
	assert_false((first.call("build_report", 2) as DayReport).loan_first_advance)
	assert_eq(int(document["data"]["clock"]["day"]), 2)
	var books: Dictionary = Economy.ledger.to_dict()
	var stock: Dictionary = Economy.stock.to_dict()
	_close(first)
	Economy.reset(98765)
	var second: Node = await _start()
	assert_eq(Clock.sim.day, 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(Economy.loan.to_dict(), closed_loan)
	assert_eq(Economy.ledger.to_dict(), books, "loading a full morning fridge adds no duplicate costs")
	assert_eq(Economy.stock.to_dict(), stock)
	assert_true(Economy.settle_loan_day(1).is_empty(), "the saved close guard rejects a replay")
	assert_eq(Economy.ledger.to_dict(), books)
	assert_true((second.get("sim") as RestaurantSim).stock == Economy.stock)
	assert_true((second.get_node("HUD/Top/Row/Loan") as Label).visible)
	assert_eq((second.get_node("HUD/Top/Row/Loan") as Label).text, "Loan %s" % Fmt.money(Economy.loan.principal))
	_close_service(second)
	assert_false((second.get("shown_report") as DayReport).loan_first_advance,
		"a later close after morning reload does not repeat the introduction")
	assert_false((second.get_node("Overlay/EveningReport/Panel/Scroll/Content/LoanNotice") as Label).visible)


func test_old_economy_save_without_loan_loads_debt_free_and_new_game_resets_debt() -> void:
	var first: Node = await _start()
	var document: Dictionary = _document()
	document["data"]["economy"].erase("loan")
	_write(document)
	_close(first)
	Economy.loan.principal = 500
	Economy.loan.last_settled_day = 3
	var loaded: Node = await _start()
	assert_eq(Economy.loan.principal, 0)
	assert_eq(Economy.loan.last_settled_day, 0)
	assert_true(_document()["data"]["economy"].has("loan"), "the normal morning save upgrades the old section")
	_close(loaded)
	Economy.loan.principal = 500
	var fresh: Node = await _start(false)
	assert_eq(Economy.loan.principal, 0, "new game uses Economy.reset")
	assert_eq(Economy.loan.last_settled_day, 0)
	assert_eq(Clock.sim.day, 1)
	assert_not_null(fresh.get("sim"))


func test_loan_refuses_large_furniture_and_all_trays_without_mutation_but_allows_small_items_and_food() -> void:
	var main: Node = await _start()
	_fresh_books(1000, 100)
	var original: String = _saved_text()
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var snapshot: Dictionary = editor.to_dict()
	var books: Dictionary = Economy.ledger.to_dict()
	var loan: Dictionary = Economy.loan.to_dict()
	var check: EditCheck = editor.check_buy(&"fridge", Vector2i(4, 9))
	assert_false(check.ok)
	assert_eq(check.why, LOAN_HINT)
	assert_false(main.call("shop_buy", &"fridge", Vector2i(4, 9)))
	assert_eq(editor.last_check.why, LOAN_HINT)
	assert_false(main.call("tray_buy", 1))
	assert_eq(main.get("tray_level"), 0)
	assert_eq((main.get("sim") as RestaurantSim).carry_capacity, 1)
	assert_eq(editor.to_dict(), snapshot)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.loan.to_dict(), loan)
	assert_true(main.call("set_staff_visible", true))
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var trays: Button = panel.get_node("Panel/Content/Scroll/List/TraysRow/TraysBuy") as Button
	assert_true(trays.disabled)
	assert_eq(trays.tooltip_text, LOAN_HINT)
	var big_trays: Button = panel.get_node("Panel/Content/Scroll/List/BigTraysRow/BigTraysBuy") as Button
	assert_eq(big_trays.tooltip_text, "Buy Trays first.", "purchase order keeps its existing explanation")
	assert_true(main.call("shop_buy", &"chair", Vector2i(2, 8)))
	var content: ContentDB = main.get("content") as ContentDB
	var ingredient_id: StringName = TUNING.morning_stock.keys()[0]
	var ingredient: IngredientDef = content.ingredient(ingredient_id)
	var quantity: int = Economy.stock.count(ingredient_id)
	assert_true(Economy.buy_ingredient(ingredient_id, 1, ingredient.unit_cost))
	assert_eq(Economy.stock.count(ingredient_id), quantity + 1)
	assert_eq(Economy.loan.to_dict(), loan, "ordinary purchases do not borrow or settle")
	assert_eq(_saved_text(), original, "neither a refusal nor a purchase adds a save point")
	Economy.loan.principal = 0
	assert_true(main.call("set_staff_visible", true))
	assert_false(trays.disabled)
	assert_true(main.call("tray_buy", 1))
	assert_eq(trays.tooltip_text, "Owned")
	Economy.loan.principal = 100
	assert_true(main.call("set_staff_visible", true))
	assert_eq(trays.tooltip_text, "Owned", "loan hints do not replace ownership")
	assert_true(big_trays.disabled)
	assert_eq(big_trays.tooltip_text, LOAN_HINT)
	assert_false(main.call("tray_buy", 2))
	assert_eq(_saved_text(), original)


func test_optional_tray_lock_reason_preserves_legacy_three_argument_binding() -> void:
	var main: Node = await _start(false)
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var trays: Button = panel.get_node("Panel/Content/Scroll/List/TraysRow/TraysBuy") as Button
	panel.set_trays(0, PackedInt32Array([10, 20]), 1000, LOAN_HINT)
	assert_true(trays.disabled, "all upgrades lock, even a price below the furniture limit")
	assert_eq(trays.tooltip_text, LOAN_HINT)
	panel.set_phase(SimClock.Phase.OPEN)
	assert_eq(trays.tooltip_text, StaffPanel.MORNING_HINT)
	panel.set_phase(SimClock.Phase.MORNING)
	panel.set_trays(0, PackedInt32Array([10, 20]), 1000)
	assert_false(trays.disabled, "omitting the optional reason clears a previous lock")
	assert_eq(trays.tooltip_text, "Servers can carry more plates.")


func test_loan_capture_cli_requires_exact_paused_main_schedule_and_no_other_modes() -> void:
	var valid: PackedStringArray = ["--loan-review", "--speed=0", "--frames=12,90"]
	var options: Dictionary = CAPTURE_SCRIPT.loan_review_options(valid)
	assert_true(options["enabled"])
	assert_eq(options["error"], "")
	var wrapped: PackedStringArray = valid.duplicate()
	wrapped.append_array(["--out=screens/loan", "--out=screens/loan", "--scene=res://src/world/main.tscn"])
	assert_eq(CAPTURE_SCRIPT.loan_review_options(wrapped)["error"], "")
	for argument: String in ["--loan-review", "--loan-review=true", "--speed=0", "--speed=1",
			"--frames=12,90", "--frames=12", "--open", "--fast=1", "--select=owner", "--assign-owner=kitchen",
			"--menu", "--staff", "--settings", "--settings-world", "--hud-layout", "--door-queue",
			"--window-size=1600x900", "--quarter=0", "--f3", "--report", "--paint", "--build=green",
			"--scene=res://another.tscn", "--unknown"]:
		var invalid: PackedStringArray = valid.duplicate()
		invalid.append(argument)
		assert_false(String(CAPTURE_SCRIPT.loan_review_options(invalid)["error"]).is_empty(), argument)
	assert_false(String(CAPTURE_SCRIPT.loan_review_options(["--loan-review", "--speed=0"])["error"]).is_empty())
	assert_false(String(CAPTURE_SCRIPT.loan_review_options(["--loan-review", "--frames=12,90"])["error"]).is_empty())
	options = CAPTURE_SCRIPT.loan_review_options(["--report", "--open", "--fast=100", "--speed=0", "--frames=60"])
	assert_false(options["enabled"], "the existing real-review capture keeps its own policy")
	assert_eq(options["error"], "")
	assert_false(String(CAPTURE_SCRIPT.hud_layout_options([
		"--hud-layout", "--speed=0", "--frames=12,90", "--loan-review"])["error"]).is_empty())


func test_loan_capture_fixture_and_queries_use_real_close_then_next_morning_without_saves() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	# Match the capture's actual viewport while retaining the runner's old setup.
	_capture_window_size = tree.root.size
	_capture_content_scale = tree.root.content_scale_factor
	tree.root.size = Vector2i(1600, 900)
	tree.root.content_scale_factor = 1.0
	var main: Node = await _start(false)
	var starting_cash: int = Economy.cash
	var fixture: Dictionary = CAPTURE_SCRIPT.prepare_loan_review(main, tree.root)
	assert_eq(fixture["error"], "")
	assert_eq(fixture["kind"], "financial_fixture")
	assert_eq(fixture["debit"], -(starting_cash + TERMS.borrowing_step))
	assert_eq(fixture["debit_category"], String(Ledger.OTHER))
	assert_eq(fixture["requested_ticks"], 3)
	assert_true(fixture["actual_ticks"] > 0 and fixture["actual_ticks"] <= 3,
		"the real tick driver stops when the short day closes")
	await tree.process_frame
	var before: Dictionary = _capture_snapshot(main)
	var closed: Dictionary = CAPTURE_SCRIPT.loan_review_evidence(main, tree.root)
	assert_true(CAPTURE_SCRIPT.loan_review_valid(closed, 12, fixture))
	assert_false(CAPTURE_SCRIPT.loan_review_valid(closed, 90, fixture))
	assert_eq(_capture_snapshot(main), before, "evidence queries preserve books, loan, clock and RNG")
	assert_true(closed["available"])
	assert_eq(closed["day"], 1)
	assert_eq(closed["phase"], int(SimClock.Phase.CLOSED))
	assert_eq(closed["clock_speed"], 0)
	assert_false(closed["use_saves"])
	assert_eq(closed["principal"], str(Economy.loan.principal))
	assert_true(Economy.loan.principal > 0)
	assert_eq(closed["last_settled_day"], 1)
	assert_true(closed["has_borrowed"])
	assert_true(closed["report_present"])
	assert_true(closed["report_first_advance"])
	assert_true(closed["report"]["visible"])
	assert_true(closed["notice"]["visible"])
	assert_eq(closed["notice"]["text"], CAPTURE_SCRIPT.LOAN_NOTICE)
	var report: DayReport = main.get("shown_report") as DayReport
	assert_eq(closed["report_cash_change"], report.profit())
	assert_eq(closed["report_cash_change"], Economy.ledger.day_profit(1))
	assert_eq(closed["report_operating_profit"], report.operating_profit())
	assert_true(report.operating_profit() < 0, "borrowing does not turn the operating loss into profit")
	assert_eq(report.profit(), report.operating_profit() + Economy.loan.principal)
	assert_eq(closed["operating_headline"]["text"], "%s operating profit" % Fmt.money(report.operating_profit()))
	assert_true(closed["operating_headline"]["visible"])
	assert_eq(closed["loan_hud"]["text"], "Loan %s" % Fmt.money(Economy.loan.principal))
	assert_true(closed["loan_hud"]["visible"])
	assert_eq(closed["bank_flows"], [{"day": 1, "category": String(Ledger.BANK_LOAN), "amount": Economy.loan.principal}])
	assert_eq(closed["bank_labels"].size(), 1)
	assert_eq(closed["bank_labels"][0]["title"]["text"], "Bank loan")
	assert_eq(closed["bank_labels"][0]["amount"]["text"], Fmt.money(Economy.loan.principal))
	var loans: Dictionary = Economy.loan.to_dict()
	assert_true(Clock.sim.next_day(), "use the production transition, not a hidden or resurrected report")
	await tree.process_frame
	before = _capture_snapshot(main)
	var morning: Dictionary = CAPTURE_SCRIPT.loan_review_evidence(main, tree.root)
	assert_true(CAPTURE_SCRIPT.loan_review_valid(morning, 90, fixture))
	assert_false(CAPTURE_SCRIPT.loan_review_valid(morning, 12, fixture))
	assert_eq(_capture_snapshot(main), before)
	assert_eq(Economy.loan.to_dict(), loans)
	assert_eq(morning["day"], 2)
	assert_eq(morning["phase"], int(SimClock.Phase.MORNING))
	assert_false(morning["report_present"])
	assert_false(morning["report"]["visible"])
	assert_false(morning["notice"]["visible"], "a locally visible child of the hidden report is not on screen")
	assert_null(morning["report_cash_change"])
	assert_null(morning["report_operating_profit"])
	assert_false(morning["operating_headline"]["visible"])
	assert_true(morning["loan_hud"]["visible"])
	assert_eq(morning["loan_hud"]["text"], closed["loan_hud"]["text"])
	assert_eq(morning["bank_flows"], closed["bank_flows"])
	assert_false(FileAccess.file_exists(_save_dir.path_join(SLOT + ".json")), "the capture never adds a save point")


func test_generated_uid_evidence_reads_actual_sidecars_and_cache_without_writing_or_registering() -> void:
	var sources: Array[String] = ["res://src/sim/economy/loan_account.gd", "res://src/sim/economy/loan_tuning.gd",
		"res://tests/sim/test_loan_account.gd", "res://tests/world/test_loan_session.gd",
		"res://tests/tools/test_screenshot_options.gd"]
	var before: Dictionary = {}
	for source: String in sources:
		var id: int = ResourceLoader.get_resource_uid(source) if FileAccess.file_exists(source) else ResourceUID.INVALID_ID
		before[source] = {"sidecar": _uid_sidecar_snapshot(source + ".uid"), "registered_id": id,
			"known": id >= 0 and ResourceUID.has_id(id)}
	var evidence: Dictionary = CAPTURE_SCRIPT.generated_uid_evidence()
	assert_true(evidence["read_only"])
	assert_eq(evidence["entries"].size(), sources.size())
	var all_matched: bool = true
	for index: int in range(sources.size()):
		var source: String = sources[index]
		var row: Dictionary = evidence["entries"][index]
		var original: Dictionary = before[source]
		var id: int = original["registered_id"]
		var text: String = ResourceUID.id_to_text(id) if id >= 0 else ""
		assert_eq(row["source"], source)
		assert_eq(row["uid_path"], source + ".uid")
		assert_eq(row["sidecar_exists"], original["sidecar"]["exists"])
		assert_eq(row["sidecar_text"], original["sidecar"]["text"])
		assert_eq(row["registered_id"], str(id))
		assert_eq(row["registered_text"], text)
		assert_eq(row["registered_known"], original["known"])
		assert_eq(row["matches_registered"], original["sidecar"]["readable"] \
			and not String(original["sidecar"]["text"]).strip_edges().is_empty() \
			and id >= 0 and String(original["sidecar"]["text"]).strip_edges() == text)
		if row["status"] != "match":
			all_matched = false
		assert_eq(_uid_sidecar_snapshot(source + ".uid"), original["sidecar"], "provenance never repairs a sidecar")
		assert_eq(ResourceLoader.get_resource_uid(source) if FileAccess.file_exists(source) else ResourceUID.INVALID_ID, id)
		assert_eq(id >= 0 and ResourceUID.has_id(id), original["known"], "provenance never registers an ID")
	assert_eq(evidence["complete_match"], all_matched, "missing or mismatched provenance remains explicit")


func _uid_sidecar_snapshot(path: String) -> Dictionary:
	var exists: bool = FileAccess.file_exists(path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ) if exists else null
	if file == null:
		return {"exists": exists, "readable": false, "text": ""}
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	return {"exists": true, "readable": read_error == OK or read_error == ERR_FILE_EOF, "text": text}


func _capture_snapshot(main: Node) -> Dictionary:
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	return {"loan": Economy.loan.to_dict(), "ledger": Economy.ledger.to_dict(), "stock": Economy.stock.to_dict(),
		"clock": Clock.sim.to_dict(), "world_tick": restaurant.world.now,
		"rng": [restaurant.rng.seed, restaurant.rng.state],
		"report": (main.get("shown_report") as DayReport).to_dict() if main.get("shown_report") != null else null}


func _start(saves: bool = true) -> Node:
	# The filtered suite may run first: enter the real SceneTree before Main.
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("save_slot", SLOT)
	main.set("use_saves", saves)
	main.set("new_game_seed_override", 8801)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	main.get_parent().remove_child(main)
	main.free()


func _fresh_books(cash: int, principal: int = 0) -> void:
	Economy.ledger = Ledger.new()
	Economy.ledger.cash = cash
	Economy.loan = LoanAccount.new()
	Economy.loan.principal = principal


func _closing_cost(main: Node) -> int:
	return (main.get("staff_roster") as StaffRoster).total_wages() + TUNING.daily_rent


func _close_service(main: Node) -> void:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _document() -> Dictionary:
	return JSON.parse_string(_saved_text())


func _write(document: Dictionary) -> void:
	var path: String = _save_dir.path_join(SLOT + ".json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
