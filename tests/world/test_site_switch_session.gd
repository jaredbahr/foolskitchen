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

	assert_true(_main.call("switch_site", &"second"))
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

	# The day still plays on the switched-back session.
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	assert_true(int(Economy.ledger.day_totals(day).get(Ledger.SALE, 0)) > 0, "guests paid")
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.day, day + 1)
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(_saves, 3, "the next morning saves as usual")


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
