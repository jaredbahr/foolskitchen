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
const BOOKING_TUNING: BookingTuning = preload("res://data/balance/bookings.tres")
const JOINED_BOOKING_REVIEW: Script = preload("res://tools/joined_tables_review.gd")

var _mains: Array[Node] = []
var _old_save_dir: String
var _save_dir: String
var _old_providers: Dictionary = {}
var _capture_window_size: Vector2i = Vector2i.ZERO
var _capture_content_scale: float = 1.0
var _booking_cash_events: Array[Dictionary] = []
var _lifecycle_paid_total: int = 0
var _lifecycle_paid_count: int = 0
var _lifecycle_departure_count: int = 0


func before_each() -> void:
	_booking_cash_events.clear()
	_lifecycle_paid_total = 0
	_lifecycle_paid_count = 0
	_lifecycle_departure_count = 0
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
	var notice: Label = main.get_node("Overlay/EveningReport/Panel/Column/Scroll/Content/LoanNotice") as Label
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


func test_close_profit_basis_preserves_prior_financing_and_posts_close_finance_once() -> void:
	var main: Node = await _start()
	_fresh_books(0, 200)
	Economy.add_cash(-13, Ledger.LOAN_INTEREST, "Prior financing movement")
	var close_profit_basis: int = 187
	Economy.add_cash(_closing_cost(main) + 200, Ledger.SALE)
	var expected_interest: int = roundi(200.0 * TERMS.daily_interest)
	var expected_repayment: int = mini(200, maxi(1, floori(float(close_profit_basis) * TERMS.repay_share)))
	var expected_owner: OwnerProgress = OwnerProgress.new(PROGRESSION)
	var award: Dictionary = expected_owner.award_day(1, 0, close_profit_basis)
	_close_service(main)
	var report: DayReport = main.get("shown_report") as DayReport
	var milestone_rewards: Dictionary = _milestone_rewards(report)
	if int(milestone_rewards["xp"]) > 0:
		expected_owner.award_bonus(int(milestone_rewards["xp"]))
	assert_eq(report.costs.get(Ledger.LOAN_INTEREST, 0), expected_interest + 13,
		"report preserves both the prior interest movement and this close's charge")
	assert_eq(report.costs.get(Ledger.LOAN_REPAYMENT, 0), expected_repayment)
	assert_false(report.income.has(Ledger.BANK_LOAN))
	assert_eq(Economy.loan.principal, 200 - expected_repayment)
	assert_eq(report.operating_profit(), 200, "the report's shop-performance basis remains separate")
	assert_eq(report.income.get(Ledger.MILESTONE_BONUS, 0), milestone_rewards["cash"])
	assert_eq(report.profit(), close_profit_basis - expected_interest - expected_repayment + int(milestone_rewards["cash"]),
		"cash profit includes the authored award while preserving financing flows")
	assert_eq(report.profit(), Economy.cash)
	assert_eq(report.owner_xp_breakdown["profit_xp"], award["profit_xp"],
		"finance posted during close does not change the captured pre-settlement basis")
	assert_eq(report.owner_xp_breakdown.get("milestone_xp", 0), milestone_rewards["xp"])
	assert_eq((main.get("owner_progress") as OwnerProgress).to_dict(), expected_owner.to_dict())
	var books: Dictionary = Economy.ledger.to_dict()
	main.call("_on_service_closed", 1)
	assert_eq(Economy.ledger.to_dict(), books, "interest, repayment and wages each apply once")


func test_solvent_close_with_no_principal_has_no_financing_entries() -> void:
	var main: Node = await _start(false)
	_fresh_books(0)
	Economy.add_cash(_closing_cost(main) + 100, Ledger.SALE)
	var expected_owner: OwnerProgress = OwnerProgress.new(PROGRESSION)
	expected_owner.award_day(1, 0, 100)
	_close_service(main)
	var totals: Dictionary = Economy.ledger.day_totals(1)
	assert_false(totals.has(Ledger.BANK_LOAN))
	assert_false(totals.has(Ledger.LOAN_INTEREST))
	assert_false(totals.has(Ledger.LOAN_REPAYMENT))
	assert_eq(Economy.loan.principal, 0)
	assert_eq(Economy.loan.last_settled_day, 1)
	var report: DayReport = main.get("shown_report") as DayReport
	var milestone_rewards: Dictionary = _milestone_rewards(report)
	if int(milestone_rewards["xp"]) > 0:
		expected_owner.award_bonus(int(milestone_rewards["xp"]))
	assert_eq(report.income.get(Ledger.MILESTONE_BONUS, 0), milestone_rewards["cash"])
	assert_eq(report.operating_profit(), 100)
	assert_eq(report.profit(), 100 + int(milestone_rewards["cash"]))
	assert_eq(Economy.cash, report.profit())
	assert_eq(report.owner_xp_breakdown.get("milestone_xp", 0), milestone_rewards["xp"])
	assert_eq((main.get("owner_progress") as OwnerProgress).to_dict(), expected_owner.to_dict())


func test_booking_deposit_is_excluded_at_close_and_full_bill_enters_operating_profit_once() -> void:
	var main: Node = await _start(false)
	_fresh_books(10000)
	var booking: GroupBooking = _accepted_booking()
	main.set("group_booking", booking)
	(main.get("sim") as RestaurantSim).configure_booking(booking)
	var deposit: int = int(booking.booking["deposit_amount"])
	Economy.add_cash(deposit, Ledger.BOOKING_DEPOSIT, "Customer booking deposit")
	var day_one_cost: int = _closing_cost(main)
	main.call("_on_service_closed", 1)
	var deposit_report: DayReport = main.get("shown_report") as DayReport
	assert_eq(deposit_report.income.get(Ledger.BOOKING_DEPOSIT, 0), deposit)
	assert_eq(deposit_report.purchase_basis_operating_profit(), -day_one_cost,
		"cash advances do not count as operating income, owner profit XP or repayment base")
	assert_eq(deposit_report.owner_xp_breakdown["profit_xp"], 0)
	assert_eq(Economy.loan.principal, 0, "a customer advance never creates repayment profit")

	Clock.sim.day = 2
	(main.get("sim") as RestaurantSim).world.clock.day = 2
	var bill: int = 120
	main.set("_booking_paid_total", bill)
	var review: Dictionary = {"no_seat": false, "good_service": false, "stars": 3}
	EventBus.cash_changed.connect(_record_booking_cash_event)
	var events_before_settlement: int = _booking_cash_events.size()
	main.call("_settle_booking", int(booking.booking["booking_id"]), review)
	EventBus.cash_changed.disconnect(_record_booking_cash_event)
	var settlement_events: Array[Dictionary] = _booking_cash_events.slice(events_before_settlement)
	assert_true(settlement_events.has({"delta": bill, "reason": Ledger.SALE}))
	assert_true(settlement_events.has({"delta": -deposit, "reason": Ledger.BOOKING_DEPOSIT}))
	assert_eq(Economy.ledger.day_totals(2)[Ledger.SALE], bill)
	assert_eq(Economy.ledger.day_totals(2)[Ledger.BOOKING_DEPOSIT], -deposit)
	main.call("_on_service_closed", 2)
	var service_report: DayReport = main.get("shown_report") as DayReport
	assert_eq(service_report.purchase_basis_operating_profit(), bill - _closing_cost(main),
		"the full earned bill appears once after applying the advance")
	assert_eq(service_report.profit(), Economy.ledger.day_profit(2))
	var settled_books: Dictionary = Economy.ledger.to_dict()
	main.call("_on_service_closed", 2)
	assert_eq(Economy.ledger.to_dict(), settled_books, "repeat close cannot post a second sale")


func test_unfulfilled_booking_refunds_once_with_one_bad_review_at_service_close() -> void:
	var main: Node = await _start(false)
	_fresh_books(10000)
	var booking: GroupBooking = _accepted_booking()
	booking.booking["occasion"] = "Birthday"
	main.set("group_booking", booking)
	(main.get("sim") as RestaurantSim).configure_booking(booking)
	var deposit: int = int(booking.booking["deposit_amount"])
	Economy.add_cash(deposit, Ledger.BOOKING_DEPOSIT, "Customer booking deposit")
	main.call("_on_service_closed", 1)
	Clock.sim.day = 2
	(main.get("sim") as RestaurantSim).world.clock.day = 2
	main.call("_on_service_closed", 2)
	assert_eq(Economy.ledger.day_totals(2)[Ledger.BOOKING_REFUND], -deposit)
	assert_eq(booking.booking["status"], String(GroupBooking.STATUS_REFUNDED))
	var report: DayReport = main.get("shown_report") as DayReport
	assert_eq(report.booking_lines.size(), 1)
	assert_eq(report.booking_lines[0], "Booking: the birthday group couldn't be seated. Deposit refunded.")
	assert_eq(report.review_cards.size(), 1)
	assert_eq(report.review_cards[0]["stars"], 1)
	var ledger_after_close: Dictionary = Economy.ledger.to_dict()
	main.call("_on_service_closed", 2)
	assert_eq(Economy.ledger.to_dict(), ledger_after_close)


func test_real_decline_and_accept_persist_only_at_the_next_morning_autosave() -> void:
	var main: Node = await _start()
	var initial_save: String = _saved_text()
	var decline_offer: GroupBooking = _offered_booking()
	main.set("group_booking", decline_offer)
	(main.get("sim") as RestaurantSim).configure_booking(decline_offer)
	main.call("_refresh_booking_offer")
	var decline: Button = main.get_node("Overlay/MenuPanel/Panel/Content/BookingOffer/Buttons/Decline") as Button
	decline.pressed.emit()
	assert_true(decline_offer.offer.is_empty())
	assert_true(decline_offer.booking.is_empty())
	assert_eq(Economy.ledger.day_totals(1).get(Ledger.BOOKING_DEPOSIT, 0), 0,
		"declining the actual morning offer takes no deposit")
	assert_eq(_saved_text(), initial_save, "decline does not add a save point")

	var accepted: GroupBooking = _offered_booking()
	main.set("group_booking", accepted)
	(main.get("sim") as RestaurantSim).configure_booking(accepted)
	main.call("_refresh_booking_offer")
	var offer_button: Button = main.get_node("Overlay/MenuPanel/Panel/Content/BookingOffer/Buttons/Accept") as Button
	offer_button.pressed.emit()
	var booking_id: int = int(accepted.booking["booking_id"])
	var deposit: int = int(accepted.booking["deposit_amount"])
	assert_true(accepted.has_active_booking())
	assert_eq(Economy.ledger.day_totals(1)[Ledger.BOOKING_DEPOSIT], deposit)
	assert_eq(_saved_text(), initial_save, "acceptance is persisted only by the existing morning save")
	_close_service(main)
	assert_true(Clock.sim.next_day())
	var saved_document: Dictionary = _document()
	assert_true(saved_document["data"].has("bookings"))
	assert_eq(int(saved_document["data"]["bookings"]["booking"]["booking_id"]), booking_id)
	assert_eq(saved_document["data"]["bookings"]["booking"]["status"], String(GroupBooking.STATUS_ACCEPTED))
	_close(main)
	Economy.reset(98765)
	var loaded: Node = await _start()
	var restored: GroupBooking = loaded.get("group_booking") as GroupBooking
	assert_not_null(restored)
	if restored != null:
		assert_true(restored.has_active_booking())
		assert_eq(int(restored.booking["booking_id"]), booking_id)
		assert_eq(Economy.ledger.day_totals(1)[Ledger.BOOKING_DEPOSIT], deposit)


func test_real_scheduled_party_payment_departure_and_main_settlement_are_connected() -> void:
	var main: Node = await _start(false)
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var fixture: Dictionary = JOINED_BOOKING_REVIEW.prepare(main, root)
	assert_eq(fixture.get("error", ""), "")
	if not String(fixture.get("error", "")).is_empty():
		return
	fixture = JOINED_BOOKING_REVIEW.begin_booking_service(main, root, fixture)
	assert_eq(fixture.get("error", ""), "")
	if not String(fixture.get("error", "")).is_empty():
		return
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var booking: GroupBooking = main.get("group_booking") as GroupBooking
	var booking_id: int = int(booking.booking["booking_id"])
	assert_true(sim.customer_paid.is_connected(Callable(main, "_on_customer_paid")))
	assert_true(sim.customer_left.is_connected(Callable(main, "_on_vibe_customer_left")))
	sim.customer_paid.connect(_record_lifecycle_paid)
	sim.customer_left.connect(_record_lifecycle_departure)
	for _tick: int in 4000:
		if not booking.has_active_booking():
			break
		main.call("run_ticks", 1)
	sim.customer_paid.disconnect(_record_lifecycle_paid)
	sim.customer_left.disconnect(_record_lifecycle_departure)
	assert_false(booking.has_active_booking(), "the scheduled party settles via its real final departure")
	assert_eq(String(booking.booking["status"]), String(GroupBooking.STATUS_SETTLED))
	assert_eq(_lifecycle_paid_count, 6)
	assert_eq(_lifecycle_departure_count, 6)
	var result: Dictionary = sim.booking_review_results.get(booking_id, {})
	assert_false(result.get("no_seat", true))
	assert_true(result.get("good_service", false), "all six actually served members meet the good-service rule")
	assert_eq(result.get("weight", 0), booking.tuning.review_weight)
	assert_eq(sim.reviews_today.size(), 1)
	var service_totals: Dictionary = Economy.ledger.day_totals(int(fixture["service_day"]))
	assert_eq(int(service_totals.get(Ledger.SALE, 0)), _lifecycle_paid_total,
		"Main gathers real paid orders and recognizes the whole meal bill once")
	assert_eq(int(service_totals.get(Ledger.BOOKING_DEPOSIT, 0)), -int(booking.booking["deposit_amount"]),
		"the accepted advance is credited once against the sale")
	assert_eq(int(service_totals.get(Ledger.TIP, 0)),
		BookingSettlement.good_service_tip(_lifecycle_paid_total, int(result["stars"]), BOOKING_TUNING))
	_close(main)


func test_unseatable_scheduled_party_expires_patience_then_refunds_through_real_departures() -> void:
	var main: Node = await _start(false)
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	progress.award_bonus(progress.threshold_for(2) - progress.total_xp)
	(main.get_node("HUD") as Node).call("set_owner_progress", progress.level,
		progress.xp_into_level(), progress.xp_in_level())
	(main.get("menu_settings") as MenuSettings).set_owner_level(2)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	sim.set_customer_level(2)
	var tuning: BookingTuning = BOOKING_TUNING.duplicate() as BookingTuning
	tuning.offer_chance = 1.0
	tuning.min_party_size = 6
	tuning.max_party_size = 6
	var booking: GroupBooking = GroupBooking.new(tuning)
	main.set("group_booking", booking)
	sim.configure_booking(booking)
	main.call("_plan_morning_booking")
	assert_false(booking.offer.is_empty(), "the eligible morning gets a real offer")
	booking.offer["slot_minute"] = 690
	main.call("_refresh_booking_offer")
	var accept: Button = main.get_node("Overlay/MenuPanel/Panel/Content/BookingOffer/Buttons/Accept") as Button
	accept.pressed.emit()
	var booking_id: int = int(booking.booking["booking_id"])
	var deposit: int = int(booking.booking["deposit_amount"])
	assert_true(booking.has_active_booking())
	_close_service(main)
	assert_true(Clock.sim.next_day())
	Clock.sim.open_ticks = 3600
	Clock.sim.last_orders_max_ticks = 900
	assert_true(DiningSeats.largest_usable_capacity(sim.world.grid) < 6,
		"the unmodified starter layout cannot seat the booked six-person group")
	sim.spawner._remaining = 100000
	assert_true(Clock.sim.start_service())
	main.call("run_ticks", 60)
	assert_eq(int(booking.booking.get("held_group_id", 0)), 0,
		"no joined group receives a false hold when every group is too small")
	main.call("run_ticks", 120)
	assert_eq(sim.customers().size(), 6, "normal scheduled arrival creates the six real booked guests")
	for _tick: int in 1800:
		if not booking.has_active_booking():
			break
		main.call("run_ticks", 1)
	assert_false(booking.has_active_booking(), "the party refunds only after ordinary no-table patience expires")
	assert_eq(Clock.sim.phase, SimClock.Phase.OPEN, "normal guest patience, not service close, ended the booking")
	assert_eq(sim.leave_reasons_today.get(&"no_table", 0), 6)
	assert_eq(String(booking.booking["status"]), String(GroupBooking.STATUS_REFUNDED))
	assert_true(booking.booking["effects"].has(String(GroupBooking.EFFECT_NO_SEAT)))
	var result: Dictionary = sim.booking_review_results.get(booking_id, {})
	assert_true(result.get("no_seat", false))
	assert_eq(result.get("stars", 0), 1)
	assert_eq(result.get("weight", 0), 1)
	assert_eq(Economy.ledger.day_totals(2).get(Ledger.BOOKING_REFUND, 0), -deposit)
	assert_eq(Economy.ledger.day_totals(2).get(Ledger.SALE, 0), 0)
	assert_eq(sim.booking_report_lines.size(), 1)
	assert_eq(sim.reviews_today.size(), 1)
	_close(main)


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
	assert_false((second.get_node("Overlay/EveningReport/Panel/Column/Scroll/Content/LoanNotice") as Label).visible)


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
	assert_true(main.call("shop_buy", &"chair", ShopBuilder.items_with_def(main.get("world") as SimWorld, &"table_2")[0].origin + Vector2i(1, 2)))
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


func test_repayment_and_property_escape_preserve_each_panel_close_path() -> void:
	var main: Node = await _start()
	_fresh_books(40, 150)
	main.call("_refresh_loan_hud")
	(main.get("owner_progress") as OwnerProgress).career_tier = 3
	assert_true(main.call("set_menu_visible", true))
	assert_true(main.call("set_property_visible", true))
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var trigger: Button = hud.get_node("Top/Row/Loan/OpenRepayment") as Button
	var repayment: PanelContainer = hud.get_node("LoanPopover/Panel") as PanelContainer
	var escape: InputEventKey = InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	var original: String = _saved_text()

	trigger.pressed.emit()
	assert_true(repayment.is_visible_in_tree())
	main.call("_unhandled_input", escape)
	assert_false(repayment.visible)
	assert_true(trigger.has_focus())
	assert_true(main.call("is_property_visible"))
	assert_false(main.call("is_menu_visible"))

	main.call("_unhandled_input", escape)
	assert_false(main.call("is_property_visible"))
	assert_true(main.call("is_menu_visible"))
	assert_false(main.call("is_settings_visible"))

	assert_true(main.call("set_property_visible", true))
	trigger.pressed.emit()
	assert_true(repayment.is_visible_in_tree())
	assert_true(main.call("set_settings_visible", true))
	assert_false(repayment.visible)
	assert_false(main.call("is_property_visible"))
	assert_true(main.call("set_settings_visible", false))
	assert_false(main.call("is_menu_visible"))
	assert_eq(Economy.cash, 40)
	assert_eq(Economy.loan.principal, 150)
	assert_eq(_saved_text(), original)


func test_hud_full_repayment_unlocks_trays_and_rejects_stale_full_payment() -> void:
	var main: Node = await _start()
	_fresh_books(1000, 150)
	var original: String = _saved_text()
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var panel: StaffPanel = main.get_node("Overlay/StaffPanel") as StaffPanel
	var trays: Button = panel.get_node("Panel/Content/Scroll/List/TraysRow/TraysBuy") as Button
	assert_true(main.call("set_staff_visible", true))
	assert_true(trays.disabled)
	assert_eq(trays.tooltip_text, LOAN_HINT)
	Economy.ledger.cash = 149
	hud.loan_repayment_requested.emit(150, true)
	assert_eq(Economy.loan.principal, 150)
	assert_eq(Economy.cash, 149)
	assert_true(Economy.ledger.entries_for_day(Clock.day).is_empty())
	Economy.ledger.cash = 1000
	hud.loan_repayment_requested.emit(150, true)
	assert_eq(Economy.loan.principal, 0)
	assert_eq(Economy.cash, 850)
	assert_false(trays.disabled, "the already-visible tray control refreshes from the cash event")
	assert_true(Economy.can_buy_discretionary(Economy.LOAN_TERMS.large_purchase_limit + 1))
	assert_false((hud.get_node("Top/Row/Loan") as Label).visible)
	assert_eq(_saved_text(), original, "repayment uses the existing save timing")


func test_early_payment_keeps_closing_basis_and_the_closed_report_updates() -> void:
	var main: Node = await _start(false)
	_fresh_books(60, 200)
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	hud.loan_repayment_requested.emit(60, false)
	assert_eq(Economy.cash, 0)
	assert_eq(Economy.loan.principal, 140)
	Economy.add_cash(_closing_cost(main) + 100, Ledger.SALE)
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	assert_true(Clock.sim.start_service())
	var books: Dictionary = Economy.ledger.to_dict()
	hud.loan_repayment_requested.emit(40, false)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.loan.principal, 140)
	Clock.sim.advance()
	assert_eq(Clock.sim.phase, SimClock.Phase.LAST_ORDERS)
	hud.loan_repayment_requested.emit(40, false)
	assert_eq(Economy.ledger.to_dict(), books)
	assert_eq(Economy.loan.principal, 140)
	main.call("run_ticks", 2)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = main.get("shown_report") as DayReport
	var expected_owner: OwnerProgress = OwnerProgress.new(PROGRESSION)
	var award: Dictionary = expected_owner.award_day(1, 0, 100)
	assert_eq(report.owner_xp_breakdown["profit_xp"], award["profit_xp"])
	assert_eq(report.operating_profit(), 100)
	assert_eq(report.costs.get(Ledger.EARLY_LOAN_REPAYMENT), 60)
	assert_eq(report.costs.get(Ledger.LOAN_INTEREST), roundi(140.0 * TERMS.daily_interest))
	assert_eq(report.costs.get(Ledger.LOAN_REPAYMENT), floori(100.0 * TERMS.repay_share))
	var principal: int = Economy.loan.principal
	var cash: int = Economy.cash
	assert_true(principal > 0 and cash > 0)
	hud.loan_repayment_requested.emit(10, false)
	assert_eq(Economy.cash, cash - 10)
	assert_eq(Economy.loan.principal, principal - 10)
	var updated: DayReport = main.get("shown_report") as DayReport
	assert_eq(updated.operating_profit(), 100)
	assert_eq(updated.profit(), report.profit() - 10)
	assert_eq(updated.costs.get(Ledger.EARLY_LOAN_REPAYMENT), 70)
	var cost_labels: PackedStringArray = []
	for row: Node in main.get_node("Overlay/EveningReport").get_node("%CostRows").get_children():
		var label: Label = row as Label
		if label != null:
			cost_labels.append(label.text)
	assert_true(cost_labels.has("Loan repaid early"))
	assert_eq(Economy.loan.last_settled_day, 1)


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
	assert_eq(closed["report_purchase_basis_operating_profit"], report.purchase_basis_operating_profit())
	assert_eq(closed["report_food_cost"], report.food_cost)
	assert_true(closed["report_food_cost_recorded"])
	assert_eq(closed["report_ingredient_net"],
		int(report.income.get(Ledger.INGREDIENTS, 0)) - int(report.costs.get(Ledger.INGREDIENTS, 0)))
	assert_true(report.operating_profit() < 0, "borrowing does not turn the operating loss into profit")
	assert_eq(report.profit(), report.purchase_basis_operating_profit() + Economy.loan.principal,
		"the original signed cash result still includes the exact bank advance")
	assert_eq(report.operating_profit(), report.purchase_basis_operating_profit()
		- int(closed["report_ingredient_net"]) - report.food_cost,
		"the served-food headline replaces stock-purchase cash with actual sold ingredient cost")
	var wrong_cash: Dictionary = closed.duplicate(true)
	wrong_cash["report_cash_change"] = int(wrong_cash["report_cash_change"]) + 1
	assert_false(CAPTURE_SCRIPT.loan_review_valid(wrong_cash, 12, fixture), "cash drift cannot pass capture validation")
	wrong_cash["settled_day_cash_change"] = int(wrong_cash["settled_day_cash_change"]) + 1
	assert_false(CAPTURE_SCRIPT.loan_review_valid(wrong_cash, 12, fixture),
		"matching wrong cash fields still fail the independent purchase-basis plus bank bridge")
	var wrong_food_cost: Dictionary = closed.duplicate(true)
	wrong_food_cost["report_food_cost"] = int(wrong_food_cost["report_food_cost"]) + 1
	assert_false(CAPTURE_SCRIPT.loan_review_valid(wrong_food_cost, 12, fixture), "an incorrect served-cost bridge cannot pass")
	var unknown_food_cost: Dictionary = closed.duplicate(true)
	unknown_food_cost["report_food_cost_recorded"] = false
	assert_false(CAPTURE_SCRIPT.loan_review_valid(unknown_food_cost, 12, fixture), "unknown costs cannot advertise an exact headline")
	for field: String in ["report_purchase_basis_operating_profit", "report_ingredient_net", "report_food_cost"]:
		for malformed: Variant in [null, "1", true, 1.5, NAN, INF, {}, [], 9007199254740992.0]:
			var bad: Dictionary = closed.duplicate(true)
			bad[field] = malformed
			assert_false(CAPTURE_SCRIPT.loan_review_valid(bad, 12, fixture),
				"malformed %s is rejected before arithmetic: %s" % [field, malformed])
		var missing: Dictionary = closed.duplicate(true)
		missing.erase(field)
		assert_false(CAPTURE_SCRIPT.loan_review_valid(missing, 12, fixture), "missing %s is not recorded evidence" % field)
	var negative_food: Dictionary = closed.duplicate(true)
	negative_food["report_food_cost"] = -1
	assert_false(CAPTURE_SCRIPT.loan_review_valid(negative_food, 12, fixture), "a negative served cost is invalid")
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
	assert_null(morning["report_purchase_basis_operating_profit"])
	assert_null(morning["report_ingredient_net"])
	assert_null(morning["report_food_cost"])
	assert_false(morning["report_food_cost_recorded"])
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


func _accepted_booking() -> GroupBooking:
	var tuning: BookingTuning = BOOKING_TUNING.duplicate() as BookingTuning
	tuning.offer_chance = 1.0
	tuning.min_party_size = 6
	tuning.max_party_size = 6
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 316
	var model: GroupBooking = GroupBooking.new(tuning)
	var provider: Callable = func() -> RandomNumberGenerator:
		return random
	assert_false(model.plan_offer(1, 2, [&"burger"] as Array[StringName], 660, 1260, provider).is_empty())
	assert_false(model.accept_offer(1).is_empty())
	return model


func _offered_booking() -> GroupBooking:
	var tuning: BookingTuning = BOOKING_TUNING.duplicate() as BookingTuning
	tuning.offer_chance = 1.0
	tuning.min_party_size = 6
	tuning.max_party_size = 6
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 316
	var model: GroupBooking = GroupBooking.new(tuning)
	var provider: Callable = func() -> RandomNumberGenerator:
		return random
	assert_false(model.plan_offer(1, 2, [&"burger"] as Array[StringName], 660, 1260, provider).is_empty())
	return model


func _record_booking_cash_event(_cash: int, delta: int, reason: StringName) -> void:
	_booking_cash_events.append({"delta": delta, "reason": reason})


func _record_lifecycle_paid(customer: CustomerAgent, _order: Order, amount: int) -> void:
	if customer.party != null and customer.party.booking_owned:
		_lifecycle_paid_total += amount
		_lifecycle_paid_count += 1


func _record_lifecycle_departure(customer: CustomerAgent, _reason: StringName) -> void:
	if customer.party != null and customer.party.booking_owned:
		_lifecycle_departure_count += 1


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


func _milestone_rewards(report: DayReport) -> Dictionary:
	var rewards: Dictionary = {"xp": 0, "cash": 0}
	for milestone: Dictionary in report.milestones_reached:
		rewards["xp"] = int(rewards["xp"]) + int(milestone.get("reward_xp", 0))
		rewards["cash"] = int(rewards["cash"]) + int(milestone.get("reward_cash", 0))
	return rewards


func _write(document: Dictionary) -> void:
	var path: String = _save_dir.path_join(SLOT + ".json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
