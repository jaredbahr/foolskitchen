extends TestCase
## Explicit close-data fixtures drive the real session, loan and morning save
## paths. They do not claim to be a full served-guest or balance playthrough.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "milestone_session"
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const TERMS: LoanTuning = preload("res://data/balance/loans.tres")
const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}


func before_each() -> void:
	_old_save_dir = SaveSystem.save_dir
	_old_providers = SaveSystem._providers.duplicate()
	_save_dir = SaveTestPaths.case_dir(OS.get_process_id(), "milestone_session")
	SaveSystem.save_dir = _save_dir
	SaveSystem.delete_slot(SLOT)


func after_each() -> void:
	for main: Node in _mains.duplicate():
		_close(main)
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


func test_real_menu_goals_close_and_escape_do_not_award_save_or_advance_rng() -> void:
	var main: Node = await _start(true, _catalogue())
	var morning_file: String = _saved_text()
	var books: Dictionary = Economy.ledger.to_dict()
	var career: Dictionary = (main.get("milestones") as MilestoneTracker).to_dict()
	var owner: Dictionary = (main.get("owner_progress") as OwnerProgress).to_dict()
	var clock: Dictionary = Clock.sim.to_dict()
	var rng: Dictionary = _rng_states()
	assert_true(main.call("set_menu_visible", true))
	var menu: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	(menu.get_node("%GoalsButton") as Button).pressed.emit()
	assert_true(main.call("is_goals_visible"))
	assert_false(menu.visible)
	var goals: GoalsPanel = main.get_node("Overlay/GoalsPanel") as GoalsPanel
	assert_eq(goals.active_goal_ids(), [&"one_guest"] as Array[StringName])
	(goals.get_node("Panel/Content/Header/Close") as Button).pressed.emit()
	assert_false(goals.visible)
	assert_true(menu.visible, "Close returns to the menu that opened Goals")
	(menu.get_node("%GoalsButton") as Button).pressed.emit()
	var escape: InputEventKey = InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	main.call("_unhandled_input", escape)
	assert_false(goals.visible)
	assert_true(menu.visible)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq((main.get("milestones") as MilestoneTracker).to_dict(), career)
	assert_eq((main.get("owner_progress") as OwnerProgress).to_dict(), owner)
	assert_eq(Clock.sim.to_dict(), clock)
	assert_eq(_rng_states(), rng)
	assert_eq(_saved_text(), morning_file)
	assert_true(main.call("set_goals_visible", true))
	assert_true(main.call("set_staff_visible", true))
	assert_false(goals.visible, "Staff and Goals never compete for input")


func test_close_pays_once_before_loan_but_keeps_pre_bonus_profit_and_report() -> void:
	var main: Node = await _start(true, _catalogue(6, 500))
	var live_owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var morning_file: String = _saved_text()
	_fresh_books(main, 30, 1000, 30)
	_close_day(main, 1)
	assert_true(main.get("owner_progress") == live_owner, "bonus settlement preserves the live owner model")
	assert_eq(live_owner.last_awarded_day, 1)
	var interest: int = roundi(1000.0 * TERMS.daily_interest)
	var repayment: int = maxi(1, floori(30.0 * TERMS.repay_share))
	var expected_cash: int = 30 + 30 + 500 - interest - repayment
	assert_eq(Economy.cash, expected_cash)
	assert_eq(Economy.loan.principal, 1000 - repayment)
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.MILESTONE_BONUS), 500)
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.LOAN_REPAYMENT), -repayment)
	var report: DayReport = main.get("shown_report") as DayReport
	assert_eq(report.operating_profit(), 30, "a career reward is not business profit")
	assert_eq(report.profit(), Economy.cash - 30, "all actual money still matches the ledger")
	assert_eq(report.milestones_reached, [{"title": "One happy lunch", "reward_xp": 6, "reward_cash": 500}] as Array[Dictionary])
	assert_eq(report.owner_xp_breakdown["milestone_xp"], 6)
	var expected_owner: OwnerProgress = OwnerProgress.new(PROGRESSION)
	var ordinary: Dictionary = expected_owner.award_day(1, 0, 30)
	expected_owner.award_bonus(6)
	assert_eq((main.get("owner_progress") as OwnerProgress).to_dict(), expected_owner.to_dict())
	assert_eq(live_owner.to_dict(), expected_owner.to_dict(), "existing readers see ordinary and bonus XP together")
	assert_eq(report.owner_xp_breakdown["profit_xp"], ordinary["profit_xp"])
	assert_eq(_saved_text(), morning_file, "closing never writes an extra save")
	var books: Dictionary = Economy.ledger.to_dict()
	var owner: Dictionary = (main.get("owner_progress") as OwnerProgress).to_dict()
	var career: Dictionary = (main.get("milestones") as MilestoneTracker).to_dict()
	var shown: Dictionary = report.to_dict()
	main.call("_on_service_closed", 1)
	main.call("build_report", 1)
	assert_true(main.call("set_goals_visible", true))
	assert_true(main.call("set_goals_visible", false))
	assert_true(main.get("owner_progress") == live_owner, "repeated close and presentation keep the same owner model")
	assert_eq(live_owner.to_dict(), owner)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq((main.get("owner_progress") as OwnerProgress).to_dict(), owner)
	assert_eq((main.get("milestones") as MilestoneTracker).to_dict(), career)
	assert_eq((main.get("shown_report") as DayReport).to_dict(), shown)
	assert_eq(_saved_text(), morning_file)


func test_earned_cash_prevents_an_avoidable_advance() -> void:
	var main: Node = await _start(false, _catalogue(0, 50))
	_fresh_books(main, 0, 0, -20)
	_close_day(main, 1)
	assert_eq(Economy.cash, 30)
	assert_eq(Economy.loan.principal, 0)
	assert_false(Economy.ledger.day_totals(1).has(Ledger.BANK_LOAN))
	assert_eq((main.get("shown_report") as DayReport).operating_profit(), -20)


func test_completion_persists_only_at_next_morning_and_cannot_pay_after_load() -> void:
	var catalogue: MilestoneSet = _catalogue()
	var first: Node = await _start(true, catalogue)
	var first_owner: OwnerProgress = first.get("owner_progress") as OwnerProgress
	var morning_file: String = _saved_text()
	_fresh_books(first, 100, 0, 0)
	_close_day(first, 1)
	assert_true(first.get("owner_progress") == first_owner)
	assert_eq(first_owner.total_xp, 6, "the retained owner receives the actual milestone bonus")
	assert_eq(first_owner.last_awarded_day, 1)
	var career: Dictionary = (first.get("milestones") as MilestoneTracker).to_dict()
	assert_eq(_saved_text(), morning_file)
	assert_true(Clock.sim.next_day())
	assert_true(first.get("owner_progress") == first_owner, "next-morning setup preserves the live owner model")
	assert_eq(first_owner.last_awarded_day, 1)
	assert_eq(int(_document()["data"]["owner"]["progress"]["total_xp"]), first_owner.total_xp)
	assert_eq(int(_document()["data"]["owner"]["progress"]["last_awarded_day"]), first_owner.last_awarded_day)
	assert_eq(int(_document()["data"]["milestones"]["last_evaluated_day"]), 1)
	assert_eq(_document()["data"]["milestones"]["completed"], ["one_guest"])
	_close(first)
	var second: Node = await _start(true, catalogue)
	var second_owner: OwnerProgress = second.get("owner_progress") as OwnerProgress
	assert_eq(Clock.sim.day, 2)
	assert_eq(second_owner.to_dict(), first_owner.to_dict(), "the next session restores the complete awarded owner state")
	assert_eq((second.get("milestones") as MilestoneTracker).to_dict(), career)
	_fresh_books(second, 100, 0, 0)
	_close_day(second, 1)
	assert_true(second.get("owner_progress") == second_owner, "a close without new rewards also preserves owner identity")
	assert_eq(second_owner.last_awarded_day, 2, "a retained reader sees the next ordinary day-close guard")
	assert_eq(second_owner.total_xp, first_owner.total_xp, "an already completed goal adds no further XP")
	assert_eq(Economy.ledger.day_totals(2).get(Ledger.MILESTONE_BONUS, 0), 0)
	assert_true((second.get("shown_report") as DayReport).milestones_reached.is_empty())
	assert_eq((second.get("milestones") as MilestoneTracker).completed_ids(), [&"one_guest"] as Array[StringName])


func test_malformed_and_future_milestone_sections_preserve_failed_slot() -> void:
	for malformed: bool in [true, false]:
		var first: Node = await _start(true, _catalogue())
		var document: Dictionary = _document()
		var saved: Dictionary = document["data"]["milestones"]
		if malformed:
			saved["completed"] = ["duplicate", "duplicate"]
		else:
			saved["last_evaluated_day"] = int(document["data"]["clock"]["day"])
		_write_document(document)
		_remove_backup()
		var broken: String = _saved_text()
		_close(first)
		var second: Node = await _start(true, _catalogue())
		assert_eq(Clock.sim.day, 1)
		assert_eq((second.get("milestones") as MilestoneTracker).last_evaluated_day, 0)
		assert_true((second.get("milestones") as MilestoneTracker).completed_ids().is_empty())
		assert_eq(_saved_text(), broken, "rejected startup skips its one morning write")
		assert_true(second.call("set_goals_visible", true))
		assert_true(second.call("set_goals_visible", false))
		assert_eq(_saved_text(), broken)
		_close(second)
		SaveSystem.delete_slot(SLOT)


func test_old_missing_section_and_restore_callback_keep_live_state_isolated() -> void:
	var first: Node = await _start(true, _catalogue())
	var live: MilestoneTracker = first.get("milestones") as MilestoneTracker
	var original: Dictionary = live.to_dict()
	var staged: Dictionary = original.duplicate(true)
	staged["completed"] = ["removed_goal"]
	assert_true(first.call("_restore_milestones", staged))
	assert_true(first.get("milestones") == live)
	assert_eq(live.to_dict(), original)
	staged["total_served"] = -1
	assert_false(first.call("_restore_milestones", staged))
	assert_eq(live.to_dict(), original)
	var document: Dictionary = _document()
	document["data"].erase("milestones")
	_write_document(document)
	_remove_backup()
	_close(first)
	var second: Node = await _start(true, _catalogue())
	assert_eq((second.get("milestones") as MilestoneTracker).to_dict(), original)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


func test_rejected_reward_batch_leaves_completion_and_cash_bonus_unchanged() -> void:
	var main: Node = await _start(false, _catalogue(10, 50))
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	assert_true(owner.from_dict({"version": 1, "total_xp": OwnerProgress.MAX_TOTAL_XP,
		"level": owner.level_at(OwnerProgress.MAX_TOTAL_XP), "last_awarded_day": 0}))
	var career: Dictionary = (main.get("milestones") as MilestoneTracker).to_dict()
	_fresh_books(main, 100, 0, 0)
	_close_day(main, 1)
	assert_eq((main.get("milestones") as MilestoneTracker).to_dict(), career)
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.MILESTONE_BONUS, 0), 0)
	assert_eq(Economy.cash, 100)
	assert_true((main.get("shown_report") as DayReport).milestones_reached.is_empty())


func test_bonus_level_unlocks_refresh_without_recursive_same_close_rewards() -> void:
	var catalogue: MilestoneSet = _catalogue(1000, 1)
	var later: Milestone = Milestone.new()
	later.id = &"level_three"
	later.title = "A bigger apron"
	later.description = "Reach owner level three."
	later.condition = Milestone.Condition.OWNER_LEVEL
	later.target = 3.0
	later.reward_xp = 5
	later.reward_cash = 1
	catalogue.milestones.append(later)
	var main: Node = await _start(false, catalogue)
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	_fresh_books(main, 100, 0, 0)
	_close_day(main, 1)
	assert_true(main.get("owner_progress") == owner, "a bonus level-up updates the retained owner model")
	assert_true(owner.level >= 3)
	var career: MilestoneTracker = main.get("milestones") as MilestoneTracker
	assert_true(career.is_completed(&"one_guest"))
	assert_false(career.is_completed(&"level_three"), "a reward cannot recursively trigger another goal")
	assert_eq((main.get("shown_report") as DayReport).milestones_reached.size(), 1)
	var choices: MenuSettings = main.get("menu_settings") as MenuSettings
	var content: ContentDB = main.get("content") as ContentDB
	assert_eq(choices.owner_level(), owner.level, "bonus XP refreshes the menu's unlock level")
	assert_true(choices.owner_level() >= content.recipe(&"tomato_melt").unlock_level)
	var hud_level: Label = main.get_node("HUD/Top/Row/OwnerProgress/OwnerLevel") as Label
	assert_eq(hud_level.text, "Lv %d" % owner.level)
	assert_true(Clock.sim.next_day())
	assert_true(main.get("owner_progress") == owner)
	_fresh_books(main, 100, 0, 0)
	_close_day(main, 0)
	assert_true(main.get("owner_progress") == owner, "the next reward batch keeps the same model")
	assert_eq(owner.last_awarded_day, 2)
	assert_true((main.get("milestones") as MilestoneTracker).is_completed(&"level_three"))
	assert_eq(Economy.ledger.day_totals(2).get(Ledger.MILESTONE_BONUS), 1)


func _start(saves: bool, catalogue: MilestoneSet) -> Node:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main: Node = MAIN.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 7)
	main.set("milestone_catalogue", catalogue)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	if not is_instance_valid(main):
		return
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()


func _catalogue(xp: int = 6, cash: int = 50) -> MilestoneSet:
	var goal: Milestone = Milestone.new()
	goal.id = &"one_guest"
	goal.title = "One happy lunch"
	goal.description = "Serve one guest today."
	goal.condition = Milestone.Condition.SERVED_TODAY
	goal.target = 1.0
	goal.reward_xp = xp
	goal.reward_cash = cash
	var catalogue: MilestoneSet = MilestoneSet.new()
	catalogue.milestones = [goal] as Array[Milestone]
	return catalogue


func _fresh_books(main: Node, opening_cash: int, principal: int, profit: int) -> void:
	Economy.ledger = Ledger.new()
	Economy.ledger.cash = opening_cash
	Economy.loan = LoanAccount.new()
	Economy.loan.principal = principal
	var closing_cost: int = (main.get("staff_roster") as StaffRoster).total_wages() + TUNING.daily_rent
	Economy.add_cash(closing_cost + profit, Ledger.SALE)


func _close_day(main: Node, served: int) -> void:
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	restaurant.spawner.min_gap = 100000
	restaurant.spawner.max_gap = 100000
	restaurant.start_day()
	restaurant.served_today = served
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 3)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)


func _rng_states() -> Dictionary:
	var states: Dictionary = {}
	for name: StringName in [&"customers", &"reviews", &"hiring", &"cleanliness"]:
		states[name] = GameState.rng(name).state
	return states


func _saved_text() -> String:
	return FileAccess.get_file_as_string(_save_dir.path_join(SLOT + ".json"))


func _document() -> Dictionary:
	return JSON.parse_string(_saved_text())


func _write_document(document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_save_dir.path_join(SLOT + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_backup() -> void:
	var path: String = _save_dir.path_join(SLOT + ".json.bak")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
