extends TestCase
## FK-087: another site's money on the same day stays out of the active site's
## evening report, business history, records, XP, goals and weekly challenge,
## while the owner's cash still holds it.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const OTHER_SITE: StringName = &"pier"

var _main: Node
var _clock_processing: bool
var _speed: int


func before_each() -> void:
	_clock_processing = Clock.is_processing()
	_speed = Clock.speed
	Clock.set_process(false)
	Clock.set_speed(0)


func after_each() -> void:
	_close()
	Economy.reset(0)
	GameState.new_run(1)
	Clock.set_speed(_speed)
	Clock.set_process(_clock_processing)


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


## Plays day 1 to its close; with `away_money`, another site books a sale and
## spending (netting to zero cash) during this morning first.
func _play_day(away_money: bool) -> Dictionary:
	_start()
	assert_eq(Economy.active_site, SiteBook.HOME_ID, "a new game books to the home site")
	var day: int = Clock.sim.day
	var notes_before: Array[String] = _main.call("stock_notes")
	if away_money:
		var cash_before: int = Economy.cash
		assert_true(Economy.set_active_site(OTHER_SITE))
		Economy.add_cash(500, Ledger.SALE)
		Economy.add_cash(-40, Ledger.INGREDIENTS, Economy.AUTO_LINE_PREFIX + "bun")
		Economy.add_cash(-460, Ledger.LOT_PURCHASE)
		assert_eq(Economy.cash, cash_before, "the owner's cash holds the other site's money")
		assert_eq(Economy.ledger.day_income(day), Economy.ledger.day_income(day, SiteBook.HOME_ID) + 500)
		assert_true(Economy.set_active_site(SiteBook.HOME_ID))
		assert_eq(_main.call("stock_notes"), notes_before, "the other site's auto-order is not this morning's")
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 6000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = _main.get("shown_report") as DayReport
	assert_not_null(report)
	if report == null:
		return {}
	var owner: OwnerProgress = _main.get("owner_progress")
	var result: Dictionary = {
		"income": report.income.duplicate(), "costs": report.costs.duplicate(),
		"stock_bought": report.stock_bought, "operating": report.purchase_basis_operating_profit(),
		"served": report.customers_served,
		"history": JSON.stringify((_main.get("business_history") as BusinessHistory).capture()),
		"records": JSON.stringify((_main.get("shop_records") as ShopRecords).capture()),
		"xp": owner.total_xp, "owner": JSON.stringify(owner.to_dict()),
		"milestones": JSON.stringify((_main.get("milestones") as MilestoneTracker).to_dict()),
		"weekly": JSON.stringify((_main.get("weekly_challenge") as WeeklyChallengeState).to_dict()),
		"cash": Economy.cash, "whole_income": Economy.ledger.day_income(day),
	}
	_close()
	return result


func test_another_sites_entries_stay_out_of_the_active_sites_books() -> void:
	var alone: Dictionary = _play_day(false)
	Economy.reset(0)
	GameState.new_run(1)
	var shared: Dictionary = _play_day(true)
	if alone.is_empty() or shared.is_empty():
		return
	assert_true(int(alone["served"]) > 0, "the day had real service")
	assert_eq(shared["whole_income"], int(alone["whole_income"]) + 500, "the whole books hold the other site's sale")
	assert_eq(shared["cash"], alone["cash"])
	for key: String in ["income", "costs", "stock_bought", "operating", "served", "history",
			"records", "xp", "owner", "milestones", "weekly"]:
		assert_eq(shared[key], alone[key], key)
	assert_false((shared["income"] as Dictionary).has(Ledger.LOT_PURCHASE))
