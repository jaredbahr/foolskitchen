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


func test_a_fixer_upper_counts_down_at_each_close_and_opens_when_ready() -> void:
	_start()
	_owner().career_tier = 3
	_set_cash(9000)
	assert_true(_main.call("buy_lot", FIXER))
	assert_false(_main.call("can_switch_site", FIXER), "renovating: no switch")
	assert_false(_main.call("switch_site", FIXER))
	assert_true(_main.call("set_site_card_visible", true))
	assert_eq(_row_text(FIXER, "Status"), "Renovating: 3 days")
	assert_true(_pick(FIXER).disabled)
	assert_eq(_pick(FIXER).text, "Renovating")
	_pick(FIXER).pressed.emit()
	assert_eq(_book().active_id, SiteBook.HOME_ID, "a disabled pick does nothing")
	assert_true(_main.call("set_site_card_visible", false))
	for left: int in [2, 1]:
		var report: DayReport = _play_to_close()
		assert_eq(_book().renovation_days_left(FIXER), left)
		assert_eq(report.away_site_lines.size(), 1)
		assert_true(report.away_site_lines[0].begins_with("Old Mill Street (closed)"), report.away_site_lines[0])
		assert_true(report.away_site_lines[0].ends_with("renovating, %d %s left" % [left, "day" if left == 1 else "days"]),
			report.away_site_lines[0])
		_next_morning()
		assert_true(_main.call("is_site_card_visible"), "two sites: the card shows each morning")
		assert_eq(_row_text(FIXER, "Status"), "Renovating: %d %s" % [left, "day" if left == 1 else "days"])
		assert_false(_main.call("can_switch_site", FIXER))
		_pick(SiteBook.HOME_ID).pressed.emit()
		assert_false(_main.call("is_site_card_visible"))
		# The morning autosave keeps the count: a reload reads it back.
		_close()
		_start()
		assert_eq(_book().renovation_days_left(FIXER), left, "the days left reload")
	var last: DayReport = _play_to_close()
	assert_true(last.away_site_lines[0].ends_with("renovation done, ready to open"), last.away_site_lines[0])
	_next_morning()
	assert_eq(_book().renovation_days_left(FIXER), 0)
	assert_true(_main.call("is_site_card_visible"))
	assert_false(_pick(FIXER).disabled)
	assert_eq(_pick(FIXER).text, "Work here")
	_pick(FIXER).pressed.emit()
	assert_eq(_book().active_id, FIXER, "the card switched to the finished site")
	assert_false(_main.call("is_site_card_visible"), "not shown again by the switch's own morning")
	var base: ShopLayout = _main.get("_base_layout")
	assert_eq(base.save_layout_id, &"lot_town_fixer_upper", "the site runs on its lot's layout")
	# The switch's autosave reloads at the new site.
	_close()
	_start()
	assert_eq(_book().active_id, FIXER)
	assert_eq((_main.get("_base_layout") as ShopLayout).save_layout_id, &"lot_town_fixer_upper")
	assert_true(Clock.sim.start_service(), "the finished site opens")


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
	assert_eq(_row_text(&"second", "Status"), "Yesterday's takings: $0")
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
