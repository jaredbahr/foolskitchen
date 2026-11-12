extends TestCase
## Switching the active site in the morning (FK-087 step C3, #408): the
## departing site freezes, the target thaws and loads through the morning-load
## code, and a refused switch leaves the session exactly as it was.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "site_switch_session"
const BOOKINGS: BookingTuning = preload("res://data/balance/bookings.tres")
var _main: Node
var _old_dir: String
var _providers: Dictionary
var _saves: int = 0


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)
	_saves = 0


func after_each() -> void:
	_close()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", true)
	_main.set("save_slot", SLOT)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	# Every save captures every section once: this one counts the saves.
	SaveSystem.register("zz_save_counter", _count_save, _accept)


func _count_save() -> Dictionary:
	_saves += 1
	return {}


func _accept(_data: Dictionary) -> bool:
	return true


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _book() -> SiteBook:
	return _main.get("site_book")


func _sim() -> RestaurantSim:
	return _main.get("sim")


func _captures() -> Dictionary:
	return SaveSystem.capture_sections(SiteSections.PER_SITE)


## Every per-site section, compared as text so a changed number type shows.
func _assert_sections(actual: Dictionary, expected: Dictionary, msg: String) -> void:
	var have: Array = actual.keys()
	var want: Array = expected.keys()
	have.sort()
	want.sort()
	assert_eq(have, want, msg + ": same sections")
	for key: String in expected:
		assert_eq(JSON.stringify(actual.get(key)), JSON.stringify(expected[key]), "%s: %s" % [msg, key])


func _menu_recipe() -> StringName:
	return (_main.get("menu_settings") as MenuSettings).enabled_recipes()[0].id


func _price(id: StringName) -> int:
	var menu: MenuSettings = _main.get("menu_settings")
	return menu.price_of(menu.recipe(id))


## The whole live session a refused switch must leave alone.
func _session() -> Dictionary:
	return {"sections": JSON.stringify(_captures()), "books": JSON.stringify(Economy._capture_books()),
		"rng": JSON.stringify(GameState._capture_save()), "clock": JSON.stringify(Clock.sim.to_dict()),
		"sites": JSON.stringify(_book().to_dict()), "file": FileAccess.get_file_as_string(
			SaveSystem.save_dir.path_join(SLOT + ".json"))}


func _assert_session_kept(before: Dictionary, sim: RestaurantSim, world: SimWorld, stock: Stock) -> void:
	assert_eq(_session(), before, "nothing changed")
	assert_true(_sim() == sim, "the same restaurant runs")
	assert_true(_main.get("world") == world, "the same world")
	assert_true(Economy.stock == stock and _sim().stock == stock, "the kitchen still shares the pantry")
	assert_true(Clock.attached_world == world, "the clock still drives it")
	assert_eq(_saves, 0, "a refused switch never saves")


func test_a_switch_and_back_is_lossless() -> void:
	_start()
	var day: int = Clock.sim.day
	var second: Dictionary = _captures()
	assert_eq(second.size(), SiteSections.PER_SITE.size())
	assert_true(_book().add_site(&"second", &"second_lot", "Second", day, second))
	var dish: StringName = _menu_recipe()
	var second_price: int = _price(dish)
	assert_true(_main.call("menu_set_price", dish, second_price + 3))
	var home: Dictionary = _captures()
	var cash: int = Economy.cash
	var home_sim: RestaurantSim = _sim()
	var home_editor: ShopEditor = _main.get("shop_editor")

	assert_true(_main.call("switch_site", &"second"))
	for old: Object in [home_sim, home_sim.world.grid, home_sim.world.board, home_sim.kitchen,
			home_editor.floors, home_editor.walls, home_editor.decor]:
		_assert_not_linked_to_session(old)
	assert_eq(_saves, 1, "the switch autosaves once")
	assert_eq(_book().active_id, &"second")
	assert_eq(_book().frozen_day(SiteBook.HOME_ID), day)
	assert_false(_book().is_frozen(&"second"))
	assert_true(_sim() != home_sim, "the second site's restaurant replaced the home one")
	assert_eq(_price(dish), second_price, "the second site's own menu")
	_assert_sections(_captures(), second, "the second site as it was frozen")
	_assert_sections(_book().frozen_sections(SiteBook.HOME_ID), home, "the home site frozen whole")
	assert_eq(Economy.cash, cash, "a same-morning switch costs nothing")
	assert_true(_sim().stock == Economy.stock)
	assert_eq(Economy.active_site, &"second", "money now goes to the arriving site's books")
	assert_true(Clock.attached_world == _main.get("world"), "the clock drives the new world")
	assert_true(_main.get("world") == _sim().world)
	var view: ShopView = _main.get_node("ShopView")
	assert_true(view.world == _main.get("world"), "the view shows the second site")

	assert_true(_main.call("switch_site", SiteBook.HOME_ID))
	assert_eq(_saves, 2, "one autosave per switch")
	assert_eq(_book().active_id, SiteBook.HOME_ID)
	_assert_sections(_captures(), home, "a switch and back is lossless")
	assert_eq(_price(dish), second_price + 3)
	assert_eq(Economy.cash, cash, "a lossless round trip costs nothing")
	assert_true(_sim().stock == Economy.stock)
	assert_eq(Economy.active_site, SiteBook.HOME_ID, "and back to the home site's books")

	# The day still plays on the switched-back session.
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(int(Economy.ledger.day_totals(day).get(Ledger.SALE, 0)) > 0, "guests paid")
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.day, day + 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(_saves, 3, "the next morning saves as usual")


func test_the_return_morning_records_away_stock_spoilage() -> void:
	_start()
	var frozen_day: int = Clock.sim.day
	var frozen: Dictionary = _captures()
	var stock: Stock = Stock.new()
	stock.add(&"mussels", 2, frozen_day, 6)
	frozen["pantry"] = {"stock": stock.to_dict()}
	assert_true(_book().add_site(&"second", &"second_lot", "Second", frozen_day, frozen))
	# Nine days away age these lots by three days, their authored shelf life.
	for _step: int in 9:
		reset_weekly_for_synthetic_day_jump(_main)
		Clock.sim.day += 1
		_main.call("_begin_morning")
	assert_true(_main.call("switch_site", &"second"))
	assert_eq(Economy.stock.count(&"mussels"), 0)
	var notes: Array[String] = _main.call("stock_notes")
	assert_true(notes.has("Thrown out this morning (too old): 2 Mussels."), str(notes))
	var report: DayReport = _main.call("build_report", Clock.sim.day)
	assert_eq(report.spoiled_stock, 6)
	assert_true(report.spoiled_stock_recorded)


func test_a_refused_restore_leaves_the_session_whole() -> void:
	_start()
	var frozen: Dictionary = _captures()
	frozen["shop"]["tray_level"] = 9 # the shop provider refuses this
	frozen["pantry"] = {"stock": Stock.new().to_dict()}
	assert_true(_book().add_site(&"second", &"second_lot", "Second", Clock.sim.day, frozen))
	var before: Dictionary = _session()
	var sim: RestaurantSim = _sim()
	var world: SimWorld = _main.get("world")
	var stock: Stock = Economy.stock
	assert_false(_main.call("switch_site", &"second"))
	_assert_session_kept(before, sim, world, stock)
	assert_eq(_main.get("_loaded_menu"), null, "no staging is left behind")


func test_a_site_that_fails_the_morning_check_leaves_the_session_whole() -> void:
	_start()
	var frozen: Dictionary = _captures()
	# Restores (staged as is), then the morning check refuses it, after the
	# pantry was already filled in place: that must be put back too.
	frozen["daily_special"]["recipe"] = "no_such_dish"
	frozen["pantry"] = {"stock": Stock.new().to_dict()}
	assert_true(_book().add_site(&"second", &"second_lot", "Second", Clock.sim.day, frozen))
	var before: Dictionary = _session()
	var sim: RestaurantSim = _sim()
	var world: SimWorld = _main.get("world")
	var stock: Stock = Economy.stock
	var layout: ShopLayout = _main.get("_loaded_layout")
	assert_true(stock.count(&"bun") > 0, "the home pantry has stock to lose")
	assert_false(_main.call("switch_site", &"second"))
	_assert_session_kept(before, sim, world, stock)
	assert_eq(_main.get("_loaded_daily_special"), null, "no staging is left behind")
	assert_true(_main.get("_loaded_layout") == layout, "the live layout is kept")
	# Still a whole session: the day plays.
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)


func test_a_switch_is_refused_outside_its_morning() -> void:
	_start()
	var day: int = Clock.sim.day
	assert_true(_book().add_site(&"second", &"second_lot", "Second", day, _captures()))
	var before: Dictionary = _session()
	var sim: RestaurantSim = _sim()
	var world: SimWorld = _main.get("world")
	var stock: Stock = Economy.stock
	assert_false(_main.call("switch_site", &"nowhere"), "an unknown site")
	assert_false(_main.call("switch_site", SiteBook.HOME_ID), "the site already active")
	assert_true(_main.call("set_build_active", true))
	assert_false(_main.call("switch_site", &"second"), "not while building")
	_main.call("set_build_active", false)
	_assert_session_kept(before, sim, world, stock)
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("switch_site", &"second"), "not once the shop is open")
	assert_true(_sim() == sim)
	assert_eq(_book().active_id, SiteBook.HOME_ID)
	# A site frozen after today cannot be entered.
	assert_true(_book().add_site(&"later", &"later_lot", "Later", day + 1, {}))
	Clock.sim.phase = SimClock.Phase.MORNING
	assert_false(_main.call("switch_site", &"later"), "a site frozen after today")
	assert_eq(_saves, 0)


func test_a_switch_after_a_gap_thaws_the_site() -> void:
	_start()
	var frozen_day: int = Clock.sim.day
	var frozen: Dictionary = _captures()
	frozen["demand"]["renown"] = 2.0
	# A booking accepted on the frozen morning for the next day, which the
	# site missed: its deposit is refunded when the site is entered again.
	var offer: Dictionary = SiteThawFixture.sections()["bookings"]["offer"]
	offer["offer_day"] = float(frozen_day)
	offer["service_day"] = float(frozen_day + 1)
	var booking: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(booking.from_dict({"version": 1.0, "planned_day": float(frozen_day), "offer": offer, "booking": {}}))
	assert_false(booking.accept_offer(frozen_day).is_empty())
	var deposit: int = int(booking.booking["deposit_amount"])
	assert_true(deposit > 0)
	frozen["bookings"] = JSON.parse_string(JSON.stringify(booking.to_dict()))
	assert_true(_book().add_site(&"second", &"second_lot", "Second", frozen_day, frozen))
	for step: int in 2:
		reset_weekly_for_synthetic_day_jump(_main)
		Clock.sim.day += 1
		_main.call("_begin_morning")
	var today: int = Clock.sim.day
	var expected: Dictionary = SiteThaw.thaw(_book().frozen_sections(&"second"), frozen_day, today,
		SiteThawTunings.authored())
	var cash: int = Economy.cash
	_saves = 0
	assert_true(_main.call("switch_site", &"second"))
	assert_eq(_saves, 1)
	var demand: DemandState = _main.get("demand_state")
	assert_eq(demand.day, today)
	assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(demand.to_dict()))),
		JSON.stringify(expected["sections"]["demand"]),
		"the thawed renown is installed")
	assert_true(demand.renown < 2.0, "renown faded over the closed days")
	var refunds: int = int(Economy.ledger.day_totals(today).get(Ledger.BOOKING_REFUND, 0))
	assert_eq(refunds, -deposit, "the missed booking's deposit is returned")
	assert_false((_main.get("group_booking") as GroupBooking).has_active_booking())
	assert_true(Economy.cash <= cash - deposit, "the refund (and any restock) is paid")
	assert_eq(_book().frozen_day(SiteBook.HOME_ID), today)


## A real switch's books (#408 D2): the departing site's morning spending (a
## haggled order, a list-price order, a hand throw-out) stays its own, and the
## arriving site's report, stock bought, operating profit and the thaw's
## booking refund are only the arriving site's.
func test_a_switch_keeps_each_sites_morning_books() -> void:
	_start()
	var frozen_day: int = Clock.sim.day
	var frozen: Dictionary = _captures()
	# A booking for the day after the freeze, which the site misses (as in
	# the gap test): entering it again refunds the deposit.
	var offer: Dictionary = SiteThawFixture.sections()["bookings"]["offer"]
	offer["offer_day"] = float(frozen_day)
	offer["service_day"] = float(frozen_day + 1)
	var booking: GroupBooking = GroupBooking.new(BOOKINGS)
	assert_true(booking.from_dict({"version": 1.0, "planned_day": float(frozen_day), "offer": offer, "booking": {}}))
	assert_false(booking.accept_offer(frozen_day).is_empty())
	var deposit: int = int(booking.booking["deposit_amount"])
	frozen["bookings"] = JSON.parse_string(JSON.stringify(booking.to_dict()))
	assert_true(_book().add_site(&"second", &"second_lot", "Second", frozen_day, frozen))
	for step: int in 2:
		reset_weekly_for_synthetic_day_jump(_main)
		Clock.sim.day += 1
		_main.call("_begin_morning")
	var day: int = Clock.sim.day

	# The home site's morning: throw stock out by hand, then a haggled order
	# (the owner's one haggle, won at 10%) and a list-price order.
	for id: StringName in Economy.stock.ids():
		_main.call("stock_throw_out", id)
	_main.set("_haggle_day", day)
	_main.set("_haggle_attempted", true)
	_main.set("_haggle_percent", 10)
	assert_true(_main.call("stock_cart_set", &"tomato", 20))
	assert_true(_main.call("stock_place_order"))
	assert_true(_main.call("stock_cart_set", &"tomato", 15))
	assert_true(_main.call("stock_place_order"))
	var home_report: DayReport = _main.call("build_report", day)
	assert_eq(home_report.haggle_percent, 10, "the home site's own report has its haggle")
	assert_true(home_report.haggle_saved > 0)
	var home_bought: int = home_report.stock_bought
	assert_true(home_bought >= 33, "the home site bought both orders")
	assert_true((_main.call("stock_notes") as Array).any(_thrown_note), "the throw-out is noted at home")
	var home_entries: String = JSON.stringify(Economy.ledger.entries_for_day(day, SiteBook.HOME_ID))

	assert_true(_main.call("switch_site", &"second"))
	assert_eq(JSON.stringify(Economy.ledger.entries_for_day(day, SiteBook.HOME_ID)), home_entries,
		"the departing site's entries keep its id")
	var refunds: Array[Dictionary] = []
	for entry: Dictionary in Economy.ledger.entries_for_day(day):
		if entry["category"] == Ledger.BOOKING_REFUND:
			refunds.append(entry)
	assert_eq(refunds.size(), 1, "one thaw refund")
	assert_eq(int(refunds[0]["amount"]), -deposit)
	assert_eq(refunds[0]["site"], &"second", "the thaw refund is the arriving site's")
	var report: DayReport = _main.call("build_report", day)
	assert_eq(report.haggle_percent, 0, "no haggle on the arriving site's report")
	assert_eq(report.haggle_saved, 0)
	assert_eq(report.stock_bought, _bought(day, &"second"), "only the arriving site's purchases")
	assert_eq(_bought(day, Ledger.ALL_SITES), report.stock_bought + home_bought)
	assert_eq(int(report.costs.get(Ledger.BOOKING_REFUND, 0)), deposit)
	assert_false((_main.call("stock_notes") as Array).any(_thrown_note),
		"the departing site's throw-out is not the arriving site's note")
	# The haggle is the owner's, once a morning, whichever site.
	assert_true(_main.call("stock_cart_set", &"tomato", 1))
	assert_false(_main.call("can_start_haggle"), "one haggle a morning, across sites")
	_main.call("stock_clear_cart")

	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var closed: DayReport = _main.get("shown_report")
	assert_true(closed != null and closed.day == day, "the arriving site closed its day")
	assert_eq(closed.haggle_saved, 0, "the evening report has no departing haggle")
	assert_eq(closed.stock_bought, _bought(day, &"second"))
	assert_eq(int(closed.costs.get(Ledger.INGREDIENTS, 0)), -_net(day, &"second", Ledger.INGREDIENTS),
		"ingredient costs are only the arriving site's")
	assert_true(closed.food_cost_recorded and closed.food_cost > 0, "food cost is today's sales here")
	# The close adds only the closed home site's rent (#408 D2) to its books.
	var home_after: Array[Dictionary] = Economy.ledger.entries_for_day(day, SiteBook.HOME_ID)
	var home_rent: Dictionary = home_after.pop_back()
	assert_eq(home_rent["category"], Ledger.AWAY_SITE_RENT, "the closed home site pays its rent")
	assert_eq(int(home_rent["amount"]), -int(_main.call("_home_rent")))
	assert_eq(JSON.stringify(home_after), home_entries,
		"the home site's morning stays in its books after the close")
	# The close's operating profit (owner XP) is the arriving site's alone.
	var operating: int = _operating(day, &"second")
	var award: Dictionary = _main.get("_owner_award_today")
	var tuning: ProgressionTuning = (_main.get("owner_progress") as OwnerProgress).tuning
	assert_true(operating >= tuning.profit_step, "the arriving site made a profit to tell apart")
	assert_eq(int(award["profit_xp"]), maxi(0, operating) / tuning.profit_step * tuning.profit_step_xp)
	assert_true(maxi(0, _operating(day, Ledger.ALL_SITES)) / tuning.profit_step
		!= maxi(0, operating) / tuning.profit_step, "the departing spending would have changed it")


static func _thrown_note(note: Variant) -> bool:
	return String(note).begins_with("Thrown out today")


func _bought(day: int, site: StringName) -> int:
	var total: int = 0
	for entry: Dictionary in Economy.ledger.entries_for_day(day, site):
		if entry["category"] == Ledger.INGREDIENTS and int(entry["amount"]) < 0:
			total -= int(entry["amount"])
	return total


func _net(day: int, site: StringName, category: StringName) -> int:
	return int(Economy.ledger.day_totals(day, site).get(category, 0))


func _operating(day: int, site: StringName) -> int:
	var total: int = 0
	for entry: Dictionary in Economy.ledger.entries_for_day(day, site):
		if not DayReport.NON_OPERATING_CATEGORIES.has(entry["category"]):
			total += int(entry["amount"])
	return total


func test_a_save_after_a_switch_reloads_the_switched_site() -> void:
	_start()
	var day: int = Clock.sim.day
	var second: Dictionary = _captures()
	assert_true(_book().add_site(&"second", &"second_lot", "Second", day, second))
	var dish: StringName = _menu_recipe()
	var second_price: int = _price(dish)
	assert_true(_main.call("menu_set_price", dish, second_price + 3))
	var home: Dictionary = _captures()
	assert_true(_main.call("switch_site", &"second"))
	var switched: Dictionary = _captures()
	_close()
	_start()
	assert_eq(Clock.sim.day, day, "the saved game loaded")
	assert_eq(_book().active_id, &"second")
	assert_eq(_book().frozen_day(SiteBook.HOME_ID), day)
	_assert_sections(_book().frozen_sections(SiteBook.HOME_ID), home, "the home site stays frozen")
	assert_eq(_price(dish), second_price)
	_assert_sections(_captures(), switched, "the second site reloads as it was")


## The departing site's objects keep no signal connections into the session
## (main, its view or its sound), so nothing of the old site keeps reacting.
func _assert_not_linked_to_session(old: Object) -> void:
	if old == null:
		return
	var view: Node = _main.get_node("ShopView")
	for signal_info: Dictionary in old.get_signal_list():
		for connection: Dictionary in old.get_signal_connection_list(signal_info["name"]):
			var target: Object = (connection["callable"] as Callable).get_object()
			assert_false(target == _main or target == view or target == _main.get("sound"),
				"%s.%s still reaches the session after the switch" % [old.get_class(), signal_info["name"]])
