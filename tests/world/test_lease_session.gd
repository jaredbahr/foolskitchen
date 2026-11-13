extends TestCase
## The real session owns the purchase, books, lot and morning checkpoint.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const LEASE: LeaseUpgrade = preload("res://data/balance/lease_upgrade.tres")
const CAREER: CareerTierTuning = preload("res://data/balance/career_tiers.tres")
const SLOT: String = "lease_session"
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


func _start(saves: bool = false) -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", saves)
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


func _progress() -> OwnerProgress:
	return _main.get("owner_progress")


func _editor() -> ShopEditor:
	return _main.get("shop_editor")


func _eligible() -> void:
	_progress().award_bonus(_progress().threshold_for(LEASE.owner_level))
	# The offer needs career Tier 2 (D30), which a real close grants at this level.
	assert_eq(_progress().raise_career_tier(CAREER, 3.0), 2)
	(_main.get("menu_settings") as MenuSettings).set_owner_level(_progress().level)
	_editor().set_owner_level(_progress().level)
	_editor().set_career_tier(_progress().career_tier)
	Economy.cash = LEASE.deposit + 10000
	_main.call("_refresh_lease_offer")


func _offer() -> VBoxContainer:
	return _main.get_node("Overlay/MenuPanel/Panel/Content/LeaseOffer")


func test_offer_and_refusals_are_morning_only_and_side_effect_free() -> void:
	_start()
	assert_false(_offer().visible)
	assert_false(_main.call("lease_buy"))
	_eligible()
	assert_true(_offer().visible)
	Economy.cash = LEASE.deposit - 1
	assert_eq(_main.call("lease_refusal"), "Not enough cash for the lease deposit")
	assert_true((_offer().get_node("Accept") as Button).disabled)
	var before: Dictionary = Economy._capture_save()
	var lot: Rect2i = _editor().footprint().lot
	assert_false(_main.call("lease_buy"))
	assert_eq(Economy._capture_save(), before)
	assert_eq(_editor().footprint().lot, lot)
	Economy.cash = LEASE.deposit + 1
	assert_false((_offer().get_node("Accept") as Button).disabled, "restock advice does not block")
	assert_true((_offer().get_node("Warning") as Label).visible)
	assert_eq((_offer().get_node("Warning") as Label).get_theme_color("font_color"), Color("7F5100"))
	Economy.loan.principal = 1
	assert_false(_main.call("lease_buy"))
	Economy.loan.principal = 0
	for phase: int in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]:
		Clock.sim.phase = phase
		_main.call("_refresh_lease_offer")
		assert_false(_offer().visible)
		assert_false(_main.call("lease_buy"))
	assert_false(_main.get("lease_expanded"))


func test_purchase_exact_books_preserves_build_and_moves_alley() -> void:
	_start()
	_eligible()
	var lot: Rect2i = _editor().footprint().lot
	var shop: Dictionary = _editor().to_dict()
	var rng: Dictionary = GameState._capture_save()
	var cash: int = Economy.cash
	var world: SimWorld = _main.get("world")
	# Query the actual east shell; the old (13, 6) point is now interior floor.
	var door: Vector2i = Vector2i(_editor().footprint().building.end.x - 1, 6)
	var old_route: Dictionary = WallRules.back_alley(world.grid, door, Vector2i.RIGHT, lot)
	assert_false(old_route.is_empty(), "the actual east shell has an unobstructed alley approach")
	if old_route.is_empty():
		return
	assert_true(_main.call("lease_buy"))
	assert_true(_main.get("lease_expanded"))
	assert_eq(Economy.cash, cash - LEASE.deposit)
	assert_eq(_editor().to_dict(), shop, "no floor, furniture, paint or room changes")
	assert_eq(GameState._capture_save(), rng)
	var expanded: Rect2i = _editor().footprint().lot
	assert_eq(expanded.position, lot.position - Vector2i(LEASE.extra_west, LEASE.extra_north))
	assert_eq(expanded.size, lot.size + Vector2i(LEASE.extra_west + LEASE.extra_east, LEASE.extra_north))
	assert_eq((_main.get("sim") as RestaurantSim).dock.lot, expanded)
	assert_eq((_main.get_node("ShopView") as ShopView).segment_view.lot, expanded)
	var route: Dictionary = WallRules.back_alley(world.grid, door, Vector2i.RIGHT, expanded)
	assert_false(route.is_empty(), "the expanded lot retains the same real shell approach")
	if route.is_empty():
		return
	assert_eq((route["junction"] as Vector2i).x, (old_route["junction"] as Vector2i).x + LEASE.extra_east)
	var entries: Array[Dictionary] = Economy.ledger.entries_for_day(Clock.sim.day)
	assert_eq(entries.back()["note"], "lease_deposit")
	assert_eq(entries.back()["category"], Ledger.UPGRADES)
	assert_eq(entries.back()["amount"], -LEASE.deposit)
	assert_false(_main.call("lease_buy"))
	assert_eq(Economy.cash, cash - LEASE.deposit)
	assert_false(_offer().visible)
	_main.call("_charge_closing_costs")
	assert_eq(Economy.ledger.day_totals(Clock.sim.day)[Ledger.RENT], -LEASE.daily_rent)


func test_new_floor_is_buyable_and_survives_the_next_morning_save() -> void:
	_start(true)
	_eligible()
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var original: String = FileAccess.get_file_as_string(path)
	var lot: Rect2i = _editor().footprint().lot
	# A connected strip crosses the old north lot edge into the new area.
	var cells: Array[Vector2i] = []
	for y: int in range(lot.position.y - 1, 0):
		cells.append(Vector2i(2, y))
	assert_false(_main.call("shop_floor", cells, true))
	assert_true(_main.call("lease_buy"))
	assert_eq(FileAccess.get_file_as_string(path), original, "purchase creates no save point")
	assert_true(_main.call("shop_floor", cells, true))
	var floor: Array[Vector2i] = _editor().bought_floor()
	var upgraded_lot: Rect2i = _editor().footprint().lot
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")
	_close()
	_start(true)
	assert_true(_main.get("lease_expanded"))
	assert_eq(_editor().footprint().lot, upgraded_lot)
	assert_eq(_editor().bought_floor(), floor)
	assert_false(_main.call("lease_buy"))


func test_legacy_owner_progress_loads_as_tier_one() -> void:
	_start(true)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_false(document["data"]["owner"]["progress"].has("property_tier"),
		"the lease is no longer saved on the owner (#408)")
	assert_eq(document["data"]["shop"]["lease_expanded"], false, "it is the site's own")
	document["data"]["shop"].erase("lease_expanded")
	_write(path, document)
	_close()
	_start(true)
	assert_false(_main.get("lease_expanded"))
	var base: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")
	assert_eq(_editor().footprint().lot, ShopFootprint.from_layout(base).lot)


## A save from before #408 part 1 kept an expanded lease as the owner's
## property_tier 2: it loads as the home site's own expanded lease, and the
## next save keeps it in the shop section only.
func test_a_legacy_expanded_lease_moves_to_the_site() -> void:
	_start(true)
	var path: String = SaveSystem.save_dir.path_join(SLOT + ".json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	document["data"]["owner"]["progress"]["property_tier"] = 2
	document["data"]["shop"].erase("lease_expanded")
	_write(path, document)
	_close()
	_start(true)
	assert_true(_main.get("lease_expanded"), "the old owner field still opens the lease")
	assert_eq(_progress().property_tier, 1, "and is consumed by the load")
	var base: ShopLayout = preload("res://data/layouts/tier1_deeper.tres")
	assert_eq(_editor().footprint().lot, ShopFootprint.from_layout(LEASE.layout_for(base, 2)).lot)
	assert_false(_main.call("lease_buy"), "already expanded")
	_main.call("_charge_closing_costs")
	assert_eq(Economy.ledger.day_totals(Clock.sim.day)[Ledger.RENT], -LEASE.daily_rent)
	var saved: Dictionary = SaveSystem.capture_sections(PackedStringArray(["owner", "shop"]))
	assert_false(saved["owner"]["progress"].has("property_tier"))
	assert_eq(saved["shop"]["lease_expanded"], true)


func _write(path: String, document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	DirAccess.remove_absolute(path + ".bak")


func test_reloading_before_next_morning_rolls_back_deposit_and_tier_together() -> void:
	_start(true)
	_eligible()
	# Establish a legitimate morning checkpoint with the eligible owner.
	reset_weekly_for_synthetic_day_jump(_main)
	Clock.sim.day += 1
	_main.call("_begin_morning")
	var cash: int = Economy.cash
	var lot: Rect2i = _editor().footprint().lot
	assert_true(_main.call("lease_buy"))
	_close()
	_start(true)
	assert_false(_main.get("lease_expanded"))
	assert_eq(Economy.cash, cash)
	assert_eq(_editor().footprint().lot, lot)
	assert_true(_main.call("lease_buy"), "the rolled-back purchase can be made once again")


## Content gates read the career tier (D30), not the lease: buying the lease
## at Tier 1 opens nothing, and Tier 2 opens the dish without the lease.
func test_recipe_gate_follows_career_tier_not_the_lease() -> void:
	_start()
	var content: ContentDB = _main.get("content")
	# Restore the cached definition before leaving this fixture.
	var recipe: RecipeDef = content.recipe(&"tomato_melt")
	var old_tier: int = recipe.unlock_tier
	recipe.unlock_tier = 2
	_main.call("_refresh_menu_catalogue")
	var menu: MenuSettings = _main.get("menu_settings")
	assert_null(menu.recipe(recipe.id))
	assert_false(_main.call("menu_set_enabled", recipe.id, true))
	_eligible()
	_main.call("_refresh_menu_catalogue")
	assert_false(_main.get("lease_expanded"))
	assert_true(menu.recipe(recipe.id) != null)
	assert_false(menu.is_enabled(recipe.id), "new food remains a player choice")
	assert_true(_main.call("menu_set_enabled", recipe.id, true))
	recipe.unlock_tier = old_tier
