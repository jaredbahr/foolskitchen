extends TestCase
## FK-141: a real Creative game. Everything is open on day 1, nothing costs
## money, no loan opens, career goals stay hidden and the mode is saved.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const LEASE: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
const CAT: CatTuning = preload("res://data/balance/cat.tres")
const SLOT: String = "creative_session"

var _mains: Array[Node] = []
var _old_dir: String
var _providers: Dictionary


func before_each() -> void:
	_old_dir = SaveSystem.save_dir
	_providers = SaveSystem._providers.duplicate(true)
	SaveSystem.save_dir = SaveTestPaths.case_dir(OS.get_process_id(), SLOT)
	SaveSystem.delete_slot(SLOT)
	Clock.set_speed(0)


func after_each() -> void:
	for main: Node in _mains:
		if is_instance_valid(main):
			main.get_parent().remove_child(main)
			main.free()
	_mains.clear()
	SaveSystem.delete_slot(SLOT)
	DirAccess.remove_absolute(SaveSystem.save_dir)
	DirAccess.remove_absolute(SaveTestPaths.process_dir(OS.get_process_id()))
	SaveSystem.save_dir = _old_dir
	SaveSystem._providers = _providers
	GameMode.set_creative(false)
	GameMode.request_new_game(false)
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _start(creative: bool, saves: bool = false) -> Node:
	GameMode.request_new_game(creative)
	var main: Node = MAIN.instantiate()
	main.set("use_saves", saves)
	main.set("save_slot", SLOT)
	main.set("new_game_seed_override", 1)
	_mains.append(main)
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	return main


func _close(main: Node) -> void:
	_mains.erase(main)
	main.get_parent().remove_child(main)
	main.free()


func _run_day(main: Node) -> void:
	assert_true(Clock.sim.start_service(), "shop opens from the morning")
	var guard: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and guard < 20:
		main.call("run_ticks", 1000)
		guard += 1
	assert_eq(Clock.sim.phase, SimClock.Phase.CLOSED, "the day ends")


func test_every_unlock_is_open_on_day_one() -> void:
	var main: Node = _start(true)
	assert_true(GameMode.is_creative())
	var progress: OwnerProgress = main.get("owner_progress")
	var level: int = progress.effective_level()
	var tier: int = progress.effective_tier()
	assert_eq(progress.level, 1, "no XP is invented")
	var content: ContentDB = main.get("content")
	for item: ItemDef in content.items():
		assert_true(item.unlock_level <= level, "%s is unlocked" % item.id)
	for style: FloorStyleDef in content.floor_styles():
		assert_true(style.unlocked(level, tier), "%s floor is unlocked" % style.id)
	for recipe: RecipeDef in content.recipes():
		assert_true(recipe.unlock_level <= level and recipe.unlock_tier <= tier, "%s is unlocked" % recipe.id)
	var editor: ShopEditor = main.get("shop_editor")
	assert_eq(editor._owner_level, level)
	assert_eq(editor._career_tier, tier)
	var catalogue: BuildCatalogue = main.get_node("Overlay/BuildCatalogue")
	assert_eq(catalogue._owner_level, level)
	assert_eq((main.get("menu_settings") as MenuSettings).owner_level(), level)
	assert_true(LEASE.offered(progress, SimClock.Phase.MORNING), "the lease upgrade is open")
	assert_eq(main.call("lease_refusal"), "")
	assert_eq(main.call("cat_refusal"), "", "the cat can be adopted")
	var sim: RestaurantSim = main.get("sim")
	assert_eq(sim.customer_level, level, "every guest type and event uses the open level")
	assert_true(sim.inspection.tuning.unlock_level <= level)
	assert_true(sim.critic.tuning.unlock_level <= level)


func test_money_never_moves_through_building_stock_hiring_and_a_full_day() -> void:
	var main: Node = _start(true)
	var cash: int = Economy.cash
	assert_true(Economy.ledger.entries_for_day(1).is_empty(), "the morning restock is free")
	assert_true(main.call("set_build_active", true))
	var mode: BuildMode = main.get("build_mode")
	assert_true(mode.begin_buy(&"potted_plant", Vector2i(4, 10)))
	assert_true(mode.commit())
	assert_eq((main.get("world") as SimWorld).grid.item_at(Vector2i(4, 10)).def.id, &"potted_plant")
	assert_true(main.call("set_build_active", false))
	assert_true(main.call("stock_cart_set", &"bun", 5))
	assert_eq(main.call("stock_cart_refusal"), "")
	var buns: int = Economy.stock.count(&"bun")
	assert_true(main.call("stock_place_order"))
	assert_eq(Economy.stock.count(&"bun"), buns + 5, "the free order still arrives")
	var roster: StaffRoster = main.get("staff_roster")
	var hired: int = roster.members().size()
	assert_true(main.call("staff_hire", roster.candidates()[0].id))
	assert_eq((main.get("staff_roster") as StaffRoster).members().size(), hired + 1)
	assert_true(main.call("lease_buy"))
	assert_true(main.call("tray_buy", 1))
	assert_true(main.call("adopt_cat"))
	assert_eq(Economy.cash, cash)
	_run_day(main)
	assert_eq(Economy.cash, cash, "no sales, wages, rent or cat food move cash")
	assert_eq(Economy.loan.principal, 0, "no loan opens")
	assert_true(Economy.ledger.entries_for_day(1).is_empty())
	var report: DayReport = main.get("shown_report")
	assert_not_null(report)
	assert_true(report.milestones_reached.is_empty())
	assert_eq(report.weekly_challenge_line, "")
	assert_eq(report.career_tier_line, "")
	assert_true((main.get("milestones") as MilestoneTracker).completed_ids().is_empty())
	var content: Node = main.get_node("Overlay/EveningReport/Panel/Scroll/Content")
	for hidden: String in ["Profit", "Finances", "CashChange", "OwnerLevel", "BusinessTrendSection"]:
		assert_false((content.get_node(hidden) as CanvasItem).visible, "%s is hidden" % hidden)
	assert_true((content.get_node("Guests") as CanvasItem).visible, "guests stay")
	(main.get_node("Overlay/EveningReport") as Control).emit_signal(&"next_day_pressed")
	assert_eq(Clock.sim.day, 2)
	assert_eq(Economy.cash, cash)
	assert_true(Economy.ledger.entries_for_day(2).is_empty())


func test_hud_shows_the_tag_and_hides_money_and_goals() -> void:
	var main: Node = _start(true)
	var row: Node = main.get_node("HUD/Top/Row")
	main.get_node("HUD").call("refresh")
	assert_true((row.get_node("Creative") as Label).visible)
	assert_eq((row.get_node("Creative") as Label).text, "Creative")
	assert_false((row.get_node("Cash") as Label).visible)
	assert_false((row.get_node("OwnerProgress") as Control).visible)
	assert_true(main.call("set_goals_visible", true))
	var goals: GoalsPanel = main.get("_goals_panel")
	assert_true(goals.active_goal_ids().is_empty(), "career goals are hidden")
	assert_false((goals.get_node("%CareerTier") as Label).visible)
	assert_null((goals.get_node("%List") as Node).get_node_or_null("WeeklyChallenge"))
	var catalogue: BuildCatalogue = main.get_node("Overlay/BuildCatalogue")
	assert_eq(CatalogueText.tile_text((main.get("content") as ContentDB).item(&"chair"), catalogue._owner_level), "Free")


func test_the_flag_survives_save_and_load() -> void:
	var first: Node = _start(true, true)
	assert_true(SaveSystem.list_slots().has(SLOT), "the first morning autosaves")
	_close(first)
	GameMode.set_creative(false)
	var second: Node = _start(false, true)
	assert_true(GameMode.is_creative(), "the save restores the Creative flag")
	assert_eq((second.get("owner_progress") as OwnerProgress).effective_level(), GameMode.CREATIVE_LEVEL)
	assert_eq((second.get("shop_editor") as ShopEditor)._owner_level, GameMode.CREATIVE_LEVEL)


func test_a_career_game_is_unchanged() -> void:
	var main: Node = _start(false)
	assert_false(GameMode.is_creative())
	var progress: OwnerProgress = main.get("owner_progress")
	assert_eq(progress.effective_level(), progress.level)
	assert_eq(progress.effective_tier(), progress.career_tier)
	assert_false(LEASE.offered(progress, SimClock.Phase.MORNING))
	var row: Node = main.get_node("HUD/Top/Row")
	assert_false((row.get_node("Creative") as Label).visible)
	assert_true((row.get_node("Cash") as Label).visible)
	assert_false(Economy.ledger.entries_for_day(1).is_empty(), "career pays for the morning stock")
