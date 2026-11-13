extends TestCase
## Buying a lot and choosing a site each morning, in a real session (FK-087
## part 1b, #464): the Property screen's Buy button pays and adds a site built
## from the lot's own layout, the tier limit and other refusals keep cash and
## sites as they were, a fixer-upper counts down at each close and cannot be
## switched to until it is ready, and the morning card switches sites in the
## morning only and never shows with one site.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const SLOT: String = "lot_purchase_session"
const FIXER: StringName = &"town_fixer_upper"
const SEASIDE: StringName = &"seaside_cliff"
var _main: Node
var _old_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


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


func _close() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null


func _book() -> SiteBook:
	return _main.get("site_book")


func _owner() -> OwnerProgress:
	return _main.get("owner_progress")


func _card() -> SiteCard:
	return _main.get_node("Overlay/SiteCard") as SiteCard


func _panel() -> PropertyPanel:
	return _main.get_node("Overlay/PropertyPanel") as PropertyPanel


func _set_cash(amount: int) -> void:
	Economy.add_cash(amount - Economy.cash, Ledger.OTHER, "test cash")


func _buy_button(lot: StringName) -> Button:
	return _panel().card_for(lot).get_node("Body/Top/Buy") as Button


func _pick(site: StringName) -> Button:
	return _card().row_for(site).get_node("Body/Pick") as Button


func _row_text(site: StringName, line: String) -> String:
	return (_card().row_for(site).get_node("Body/Lines/" + line) as Label).text


func _entries(day: int, category: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in Economy.ledger.entries_for_day(day, SiteBook.HOME_ID):
		if entry["category"] == category:
			found.append(entry)
	return found


func _play_to_close() -> DayReport:
	var day: int = Clock.sim.day
	assert_true(Clock.sim.start_service())
	_main.call("run_ticks", 30000)
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	var report: DayReport = _main.get("shown_report")
	assert_true(report != null and report.day == day)
	return report


func _next_morning() -> void:
	_main.call("_on_next_day_pressed")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)


## A synthetic morning (no service): the morning setup runs again a day on.
func _jump_a_morning() -> void:
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")


func test_buying_the_fixer_upper_pays_and_adds_a_renovating_site_from_its_layout() -> void:
	_start()
	var day: int = Clock.sim.day
	_owner().career_tier = 3
	_set_cash(9000)
	assert_true(is_nan(float(_main.call("closing_reputation"))), "no close yet: no closing reputation")
	assert_true(_main.call("set_menu_visible", true))
	assert_true(_main.call("set_property_visible", true))
	var buy: Button = _buy_button(FIXER)
	assert_false(buy.disabled, "enough cash at Tier 3: buyable")
	assert_eq(buy.text, "Buy for $8,500")
	assert_eq((_panel().card_for(SEASIDE).get_node("Body/Lock") as Label).text, "Locked: needs 4.2 stars",
		"a first-morning star lock quotes no starting reviews")
	buy.pressed.emit()
	assert_true(_book().has_site(FIXER), "the Buy button bought it")
	assert_eq(Economy.cash, 500)
	var bought: Array[Dictionary] = _entries(day, Ledger.LOT_PURCHASE)
	var renovation: Array[Dictionary] = _entries(day, Ledger.RENOVATION)
	assert_eq(bought.size(), 1)
	assert_eq(int(bought[0]["amount"]), -6000)
	assert_eq(renovation.size(), 1)
	assert_eq(int(renovation[0]["amount"]), -2500)
	assert_eq(_book().site_count(), 2)
	assert_eq(_book().active_id, SiteBook.HOME_ID, "buying does not move the owner")
	assert_eq(_book().site_name(FIXER), "Old Mill Street")
	assert_eq(_book().lot_id(FIXER), FIXER)
	assert_eq(_book().frozen_day(FIXER), day)
	assert_eq(_book().renovation_days_left(FIXER), 3)
	var shop: Dictionary = _book().frozen_sections(FIXER)["shop"]
	assert_eq(shop["layout_id"], "lot_town_fixer_upper", "built from the lot's own layout")
	assert_false(shop["lease_expanded"])
	var lot: LotDef = (_main.get("content") as ContentDB).lot(FIXER)
	assert_true(_main.call("_base_for_saved_shop", shop) == lot.base_layout, "the lot layout resolves")
	# The screen now shows it owned.
	buy = _buy_button(FIXER)
	assert_true(buy.disabled)
	assert_eq(buy.text, "Owned")
	assert_eq((_panel().card_for(FIXER).get_node("Body/Reason") as Label).text, "You own this lot.")
	assert_false(_main.call("buy_lot", FIXER), "a lot is bought once")
	assert_eq(Economy.cash, 500)
	# It saves and round-trips (a test save; the game saves each morning).
	assert_eq(SaveSystem.save_game(SLOT), OK)
	var saved: Dictionary = _book().to_dict()
	_close()
	_start()
	assert_eq(JSON.stringify(_book().to_dict()), JSON.stringify(saved),
		"the sites section reloads as it was saved")
	assert_eq(_book().renovation_days_left(FIXER), 3)
	assert_eq(Economy.cash, 500)


func test_refusals_keep_cash_and_sites() -> void:
	_start()
	var day: int = Clock.sim.day
	_owner().career_tier = 3
	_set_cash(8499)
	assert_eq(_main.call("lot_purchase_refusal", FIXER), "Not enough cash: you need $1 more.")
	assert_false(_main.call("buy_lot", FIXER))
	assert_true(_main.call("set_property_visible", true))
	assert_true(_buy_button(FIXER).disabled)
	assert_eq(_buy_button(FIXER).text, "Buy")
	assert_eq((_panel().card_for(FIXER).get_node("Body/Reason") as Label).text, "Not enough cash: you need $1 more.")
	_set_cash(100000)
	assert_eq(_main.call("lot_purchase_refusal", SEASIDE), "Locked: needs 4.2 stars")
	assert_false(_main.call("buy_lot", SEASIDE))
	assert_eq(_main.call("lot_purchase_refusal", &"skyscraper_rooftop"), "Locked: needs Tier 4 and 4.3 stars")
	assert_eq(_main.call("lot_purchase_refusal", &"nowhere"), "That lot is not on the market.")
	assert_eq(_book().site_count(), 1)
	assert_eq(Economy.cash, 100000)
	assert_eq(_entries(day, Ledger.LOT_PURCHASE).size(), 0)
	# Buying is a morning action.
	assert_true(Clock.sim.start_service())
	assert_eq(_main.call("lot_purchase_refusal", FIXER), "Buy property in the morning.")
	assert_false(_main.call("buy_lot", FIXER))
	assert_eq(_book().site_count(), 1)


func test_the_tier_site_limit_refuses_a_purchase_over_the_cap() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(100000)
	# A second site already (Tier 3 allows two).
	assert_true(_book().add_site(&"second", &"second_lot", "Second", Clock.sim.day,
		SaveSystem.capture_sections(SiteSections.PER_SITE)))
	assert_eq(_main.call("lot_purchase_refusal", FIXER), "Your tier allows 2 restaurants. Reach Tier 5 to run more.")
	assert_false(_main.call("buy_lot", FIXER))
	assert_true(_main.call("set_property_visible", true))
	assert_true(_buy_button(FIXER).disabled)
	assert_eq(_book().site_count(), 2)
	assert_eq(Economy.cash, 100000)
	_owner().career_tier = 5
	assert_eq(_main.call("lot_purchase_refusal", FIXER), "")
	assert_true(_main.call("buy_lot", FIXER), "Tier 5 allows a third")
	assert_eq(_book().site_count(), 3)
	assert_eq(_buy_button(FIXER).text, "Owned", "the open screen refreshes after a buy")


func test_a_fixer_upper_can_be_designed_counts_down_and_opens_once_ready_and_staffed() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(9000)
	assert_true(_main.call("buy_lot", FIXER))
	assert_true(_main.call("can_switch_site", FIXER), "a renovating site can be visited to design (D28)")
	assert_true(_main.call("set_site_card_visible", true))
	assert_eq(_row_text(FIXER, "Status"), "Renovating: 3 days")
	assert_false(_pick(FIXER).disabled)
	assert_eq(_pick(FIXER).text, "Design here")
	_pick(SiteBook.HOME_ID).pressed.emit()
	# A day at home: the fixer-upper counts down while away.
	var report: DayReport = _play_to_close()
	assert_eq(_book().renovation_days_left(FIXER), 2)
	assert_true(report.away_site_lines[0].begins_with("Old Mill Street (closed)"), report.away_site_lines[0])
	assert_true(report.away_site_lines[0].ends_with("renovating, 2 days left"), report.away_site_lines[0])
	_next_morning()
	assert_true(_main.call("is_site_card_visible"), "two sites: the card shows each morning")
	assert_eq(_row_text(FIXER, "Status"), "Renovating: 2 days")
	_pick(FIXER).pressed.emit()
	assert_eq(_book().active_id, FIXER, "switched there to design")
	assert_eq((_main.get("_base_layout") as ShopLayout).save_layout_id, &"lot_town_fixer_upper")
	assert_eq((_main.get("staff_roster") as StaffRoster).members().size(), 0, "a new site starts with nobody")
	# It cannot open, but Build works and the day can be closed.
	assert_eq(_main.call("site_opening_refusal"), "Still renovating: 2 days left")
	assert_false(Clock.sim.start_service(), "no guests while renovating")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	var hud: Node = _main.get_node("HUD")
	assert_eq(hud.call("closed_day_reason"), "Still renovating: 2 days left")
	assert_eq((hud.get_node("Top/Row/Context") as Button).text, "Close for today")
	assert_false((hud.get_node("Top/Row/Context") as Button).disabled)
	assert_true(_main.call("set_build_active", true), "designing is allowed")
	assert_true(_main.call("set_build_active", false))
	var xp_before: int = _owner().total_xp
	assert_true(_main.call("close_for_today"))
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED)
	# A closed day is no business day: no history row, no XP, no closing stars.
	assert_eq((_main.get("business_history") as BusinessHistory).recent(1).size(), 0, "no history row")
	assert_true(is_nan(float(_main.call("closing_reputation"))), "still no closing reputation")
	assert_eq(_owner().total_xp, xp_before, "no owner XP")
	assert_eq(_book().renovation_days_left(FIXER), 1, "the active site counts down too")
	var closed: DayReport = _main.get("shown_report")
	assert_true(closed != null and closed.day == Clock.sim.day, "the evening report shows")
	assert_eq(closed.customers_served, 0)
	_next_morning()
	# The morning autosave keeps the count and the site: a reload reads them.
	_close()
	_start()
	hud = _main.get_node("HUD")
	assert_eq(_book().active_id, FIXER)
	assert_eq(_book().renovation_days_left(FIXER), 1, "the days left reload")
	assert_true(_main.call("close_for_today"))
	assert_eq(_book().renovation_days_left(FIXER), 0)
	_next_morning()
	# Ready, but nobody to cook and serve: hire first.
	assert_eq(_main.call("site_opening_refusal"), "Hire a cook and a server before you open")
	assert_false(Clock.sim.start_service())
	var roster: StaffRoster = _main.get("staff_roster")
	var roles: Array[StringName] = []
	for member: StaffMember in roster.candidates():
		roles.append(member.role)
	assert_true(roles.has(&"cook") and roles.has(&"server"), "the pool offers a cook and a server")
	for role: StringName in [&"cook", &"server"]:
		for member: StaffMember in (_main.get("staff_roster") as StaffRoster).candidates():
			if member.role == role:
				assert_true(_main.call("staff_hire", member.id), "hired a %s" % role)
				break
	assert_eq(_main.call("site_opening_refusal"), "")
	assert_eq(hud.call("closed_day_reason"), "")
	var opened: DayReport = _play_to_close()
	assert_true(opened.customers_served > 0, "the finished, staffed site serves guests")


func test_closing_a_day_needs_a_reason() -> void:
	_start()
	assert_false(_main.call("close_for_today"), "a staffed, finished site opens instead")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING)
	assert_eq(Clock.sim.opening_refusal, "")


func test_the_lease_upgrade_is_offered_only_at_the_home_lot() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(100000)
	assert_eq(_main.call("lease_refusal"), "", "home can expand at Tier 2+")
	assert_true(_book().add_site(&"second", &"second_lot", "Second", Clock.sim.day,
		SaveSystem.capture_sections(SiteSections.PER_SITE)))
	assert_true(_main.call("switch_site", &"second"))
	assert_eq(_main.call("lease_refusal"), "Only your first restaurant can expand its lease for now")
	var cash: int = Economy.cash
	assert_false(_main.call("lease_buy"), "a bought site cannot buy the home lease (#465)")
	assert_eq(Economy.cash, cash)
	assert_false(_main.get("lease_expanded"))
	assert_true(_main.call("set_menu_visible", true))
	assert_false((_main.get_node("Overlay/MenuPanel/Panel/Content/LeaseOffer") as Control).visible,
		"no lease offer on the Menu")


func test_buying_asks_to_go_there_today() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(20000)
	assert_true(_main.call("set_property_visible", true))
	_buy_button(FIXER).pressed.emit()
	assert_true(_main.call("is_site_card_visible"))
	assert_true(_card().is_prompting())
	assert_eq((_card().get_node("Center/Panel/Content/Title") as Label).text, "Design it today?")
	assert_false(_main.call("is_property_visible"))
	(_card().get_node("Center/Panel/Content/List/Answers/Accept") as Button).pressed.emit()
	assert_eq(_book().active_id, FIXER, "yes switches now")
	assert_false(_main.call("is_site_card_visible"))
	# A move-in-ready site asks "Work at your new place today?"; No stays.
	assert_true(_book().add_site(SEASIDE, SEASIDE, "Seaside Cliff", Clock.sim.day,
		SaveSystem.capture_sections(SiteSections.PER_SITE)))
	assert_true(_main.call("offer_new_site", SEASIDE))
	assert_eq((_card().get_node("Center/Panel/Content/Title") as Label).text, "Work at your new place today?")
	(_card().get_node("Center/Panel/Content/List/Answers/Decline") as Button).pressed.emit()
	assert_eq(_book().active_id, FIXER, "no stays")
	assert_true(_main.call("is_property_visible"), "back to the market")


func test_the_card_holds_build_and_owner_keys() -> void:
	_start()
	assert_true(_book().add_site(&"second", &"second_lot", "Second", Clock.sim.day,
		SaveSystem.capture_sections(SiteSections.PER_SITE)))
	assert_true(_main.call("set_site_card_visible", true))
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_B
	key.physical_keycode = KEY_B
	key.pressed = true
	_main.call("_unhandled_input", key)
	assert_false(_main.call("is_build_active"), "B does nothing under the card")
	assert_true(_main.call("is_site_card_visible"))
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	_main.call("_unhandled_input", escape)
	assert_false(_main.call("is_site_card_visible"), "Escape keeps the current site")
	assert_eq(_book().active_id, SiteBook.HOME_ID)
	# A refused pick names its reason on the button.
	assert_true(_main.call("set_build_active", true))
	assert_true(_main.call("set_site_card_visible", true))
	assert_eq(_pick(&"second").text, "Close Build first")
	assert_true(_pick(&"second").disabled)


func test_photo_keys_wait_for_the_site_choice() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(20000)
	assert_true(_main.call("set_property_visible", true))
	_buy_button(FIXER).pressed.emit()
	assert_true(_card().is_prompting())
	_assert_photo_keys_leave_site_choice_visible()
	_press_key(KEY_ESCAPE)
	assert_false(_main.call("is_site_card_visible"), "Escape declines the purchase prompt")
	assert_eq(_book().active_id, SiteBook.HOME_ID)
	assert_true(_main.call("is_property_visible"), "declining returns to the market")

	_main.call("set_property_visible", false)
	assert_true(_main.call("set_site_card_visible", true))
	assert_false(_card().is_prompting())
	_assert_photo_keys_leave_site_choice_visible()
	_press_key(KEY_ESCAPE)
	assert_false(_main.call("is_site_card_visible"), "Escape keeps the current restaurant")
	assert_eq(_book().active_id, SiteBook.HOME_ID)


func _assert_photo_keys_leave_site_choice_visible() -> void:
	var photo: PhotoMode = _main.get_node("PhotoMode") as PhotoMode
	for shift: bool in [false, true]:
		_press_key(KEY_F12, shift)
		assert_false(photo.held, "photo keys do not enter held mode under the site choice")
		assert_false(photo.capture_pending(), "photo keys do not start a capture under the site choice")
		assert_true(_card().is_visible_in_tree(), "the site choice stays visible")


func _press_key(code: Key, shift: bool = false) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	key.shift_pressed = shift
	_main.call("_unhandled_input", key)


func test_the_card_never_shows_with_one_site() -> void:
	_start()
	assert_false(_main.call("is_site_card_visible"))
	assert_false(_main.call("set_site_card_visible", true))
	_jump_a_morning()
	assert_false(_main.call("is_site_card_visible"))


func test_the_card_switches_in_the_morning_only() -> void:
	_start()
	assert_true(_book().add_site(&"second", &"second_lot", "Second", Clock.sim.day,
		SaveSystem.capture_sections(SiteSections.PER_SITE)))
	_jump_a_morning()
	assert_true(_main.call("is_site_card_visible"), "the card shows with two sites")
	assert_eq(_card().site_ids(), [SiteBook.HOME_ID, &"second"] as Array[StringName])
	assert_eq(_pick(SiteBook.HOME_ID).text, "Stay here")
	assert_eq(_pick(&"second").text, "Work here")
	assert_eq(_row_text(&"second", "Name"), "Second")
	assert_eq(_row_text(&"second", "Status"), "Closed yesterday")
	assert_eq(_row_text(&"second", "Manager"), "No manager")
	assert_true(_card().row_for(SiteBook.HOME_ID).get_node_or_null("Body/Lines/Here") != null)
	# Keeping the current site.
	_pick(SiteBook.HOME_ID).pressed.emit()
	assert_false(_main.call("is_site_card_visible"))
	assert_eq(_book().active_id, SiteBook.HOME_ID)
	_main.call("_begin_morning")
	assert_false(_main.call("is_site_card_visible"), "once a morning")
	# The next morning: pick the other site.
	_jump_a_morning()
	assert_true(_main.call("is_site_card_visible"))
	_pick(&"second").pressed.emit()
	assert_eq(_book().active_id, &"second", "the card switched")
	assert_false(_main.call("is_site_card_visible"))
	# Opening closes the card, and it cannot come back or switch until morning.
	assert_true(_main.call("set_site_card_visible", true))
	assert_true(Clock.sim.start_service())
	assert_false(_main.call("is_site_card_visible"), "opening the restaurant closes the card")
	assert_false(_main.call("set_site_card_visible", true), "not during service")
	_card().site_chosen.emit(SiteBook.HOME_ID)
	assert_eq(_book().active_id, &"second", "no switch outside the morning")


func test_switching_to_a_new_site_and_back_keeps_each_sites_own_staff_and_shop() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(9000)
	var home_staff: String = JSON.stringify((_main.get("staff_roster") as StaffRoster).to_dict())
	var home_shop: String = JSON.stringify(SaveSystem.capture_sections(["shop"] as Array[String])["shop"])
	assert_true(_main.call("buy_lot", FIXER))
	assert_true(_main.call("switch_site", FIXER))
	assert_eq((_main.get("staff_roster") as StaffRoster).members().size(), 0, "nobody at the new site")
	assert_true(_main.call("switch_site", SiteBook.HOME_ID))
	assert_eq(JSON.stringify((_main.get("staff_roster") as StaffRoster).to_dict()), home_staff,
		"the home crew is back, unchanged")
	assert_eq(JSON.stringify(SaveSystem.capture_sections(["shop"] as Array[String])["shop"]), home_shop,
		"and the home shop")
	var frozen: Dictionary = _book().frozen_sections(FIXER)
	assert_eq((frozen["staff"]["members"] as Array).size(), 0, "the new site's empty roster stays its own")
	assert_eq(frozen["shop"]["layout_id"], "lot_town_fixer_upper")
	assert_eq(_main.call("site_opening_refusal"), "", "home opens as usual")



func test_a_layout_with_no_dish_still_refuses_after_hiring_a_crew() -> void:
	_start()
	_owner().career_tier = 3
	var lot: LotDef = (_main.get("content") as ContentDB).lot(FIXER)
	var sections: Dictionary = _main.call("_new_site_sections", lot)
	assert_true(_book().add_site(FIXER, FIXER, lot.display_name, Clock.sim.day, sections))
	assert_true(_main.call("switch_site", FIXER))
	assert_eq(_main.call("site_opening_refusal"), "Hire a cook and a server before you open")
	# Block the stove: no dish can be cooked.
	var world: SimWorld = _main.get("world")
	var stove: PlacedItem = null
	for placed: PlacedItem in world.grid.items():
		if (placed.def as ItemDef).id == &"stove":
			stove = placed
	assert_not_null(stove)
	var plant: ItemDef = (_main.get("content") as ContentDB).item(&"potted_plant")
	assert_not_null(world.grid.place_def(plant, stove.work_cells[0]))
	_main.call("_refresh_menu_catalogue")
	var notice: Label = _main.get_node("HUD/MenuNotice/Text") as Label
	assert_eq(notice.text, "Hire a cook and a server before you open", "the site's own reason first")
	for role: StringName in [&"cook", &"server"]:
		for member: StaffMember in (_main.get("staff_roster") as StaffRoster).candidates():
			if member.role == role:
				assert_true(_main.call("staff_hire", member.id))
				break
	assert_eq(_main.call("site_opening_refusal"), "")
	assert_eq(notice.text, MenuAccess.NO_DISH, "the no-dish block comes back, not a stale hiring note")
	var context: Button = _main.get_node("HUD/Top/Row/Context") as Button
	assert_true(context.disabled)
	assert_eq(context.text, "Open shop")
	(_main.get_node("HUD") as Node).call("_on_context_pressed")
	assert_eq(Clock.sim.phase, SimClock.Phase.MORNING, "the Open shop button cannot open past the no-dish block")
	assert_false(_main.call("close_for_today"), "and it is no closed day either")



## A home menu that lists dishes the lot's stations cannot make (a fryer's
## fries, a drinks fridge's soft drinks) used to be copied whole: the menu then
## failed to load and the bought site could never be switched to (#472 review).
func test_a_copied_menu_keeps_only_what_the_lot_can_cook() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(9000)
	var content: ContentDB = _main.get("content")
	var wide: MenuSettings = MenuSettings.new(content.recipes(), 99)
	assert_true(wide.from_dict(_main.call("_capture_menu")))
	assert_true((wide.to_dict()["prices"] as Dictionary).has("fries"), "home lists a dish the lot cannot cook")
	_main.set("menu_settings", wide)
	assert_true(_main.call("buy_lot", FIXER))
	var frozen: Dictionary = _book().frozen_sections(FIXER).get("menu", {})
	assert_false((frozen.get("prices", {}) as Dictionary).has("fries"), "only the lot's dishes are copied")
	assert_true(_main.call("switch_site", FIXER), "the new site can be switched to")
	assert_eq(_book().active_id, FIXER)


func test_a_new_site_starts_with_a_copy_of_the_menu_it_was_bought_from() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(9000)
	var dish: StringName = (_main.get("menu_settings") as MenuSettings).enabled_recipes()[0].id
	var menu: MenuSettings = _main.get("menu_settings")
	assert_true(_main.call("menu_set_price", dish, menu.price_of(menu.recipe(dish)) + 2))
	var home_dict: Dictionary = (_main.call("_capture_menu") as Dictionary).duplicate(true)
	var home_menu: String = JSON.stringify(home_dict)
	assert_true(_main.call("buy_lot", FIXER))
	assert_true(_main.call("switch_site", FIXER))
	var copied: MenuSettings = _main.get("menu_settings")
	assert_eq(copied.price_of(copied.recipe(dish)), menu.price_of(menu.recipe(dish)), "the same prices")
	var expected: Dictionary = home_dict.duplicate(true)
	expected["name"] = (_main.get("content") as ContentDB).lot(FIXER).display_name
	assert_eq(copied.restaurant_name(), expected["name"], "named after its lot")
	assert_eq(JSON.stringify(_main.call("_capture_menu")), JSON.stringify(expected), "the same dishes, flags and prices")
	assert_true(_main.call("menu_set_price", dish, copied.price_of(copied.recipe(dish)) + 5))
	assert_true(_main.call("switch_site", SiteBook.HOME_ID))
	assert_eq(JSON.stringify(_main.call("_capture_menu")), home_menu, "home's menu is unchanged")
	assert_ne(JSON.stringify(_book().frozen_sections(FIXER)["menu"]), home_menu, "the new site kept its own change")
