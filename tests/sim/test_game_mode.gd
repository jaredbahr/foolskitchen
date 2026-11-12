extends TestCase
## FK-141: the one Creative flag, its save section and the unlock helper.

const PROGRESSION: ProgressionTuning = preload("res://data/balance/progression.tres")


func after_each() -> void:
	GameMode.set_creative(false)
	GameMode.request_new_game(false)


func test_new_game_takes_the_requested_mode_once() -> void:
	GameMode.request_new_game(true)
	GameMode.begin_new_game()
	assert_true(GameMode.is_creative())
	GameMode.begin_new_game()
	assert_false(GameMode.is_creative(), "the request is used up: the next new game is career")


func test_section_round_trips_and_refuses_bad_data() -> void:
	GameMode.set_creative(true)
	var saved: Dictionary = GameMode.capture()
	assert_eq(saved, {"creative": true})
	GameMode.reset_for_load()
	assert_false(GameMode.is_creative(), "a save without the section is a career game")
	assert_true(GameMode.restore(saved))
	assert_true(GameMode.is_creative())
	for bad: Dictionary in [{}, {"creative": 1}, {"creative": "yes"}, {"creative": true, "extra": 1}]:
		assert_false(GameMode.restore(bad))
	assert_true(GameMode.is_creative(), "a refused section changes nothing")
	assert_true(GameMode.is_creative_save({"game_mode": {"creative": true}}))
	assert_false(GameMode.is_creative_save({"game_mode": {"creative": false}}))
	assert_false(GameMode.is_creative_save({}))
	assert_false(GameMode.is_creative_save({"game_mode": {"creative": "true"}}))


func test_effective_level_and_tier_open_everything_only_in_creative() -> void:
	var progress: OwnerProgress = OwnerProgress.new(PROGRESSION)
	assert_eq(progress.effective_level(), 1)
	assert_eq(progress.effective_tier(), 1)
	GameMode.set_creative(true)
	assert_eq(progress.effective_level(), GameMode.CREATIVE_LEVEL)
	assert_eq(progress.effective_tier(), CareerTierTuning.TOP_TIER)
	assert_eq(progress.level, 1, "the earned level is untouched")
	assert_eq(progress.to_dict(), OwnerProgress.new(PROGRESSION).to_dict())
	var content: ContentDB = ContentDB.new()
	assert_true(content.load_all().is_empty())
	for item: ItemDef in content.items():
		assert_true(item.unlock_level <= progress.effective_level(), String(item.id))
	for recipe: RecipeDef in content.recipes():
		assert_true(recipe.unlock_level <= progress.effective_level() \
			and recipe.unlock_tier <= progress.effective_tier(), String(recipe.id))
	for style: FloorStyleDef in content.floor_styles():
		assert_true(style.unlocked(progress.effective_level(), progress.effective_tier()), String(style.id))
	for wall: WallStyleDef in content.wall_styles():
		assert_true(wall.unlock_level <= progress.effective_level() \
			and wall.unlock_tier <= progress.effective_tier(), String(wall.id))


func test_money_is_off_in_creative() -> void:
	var cash: int = Economy.cash
	GameMode.set_creative(true)
	Economy.add_cash(-500, Ledger.UPGRADES)
	assert_true(Economy.add_cash_for_site(-50, Ledger.RENT, "", Ledger.HOME_SITE))
	assert_true(Economy.can_spend_without_loan(Economy.MAX_CURRENCY))
	assert_true(Economy.can_buy_discretionary(100000))
	assert_true(Economy.can_buy_upgrade(100000))
	assert_eq(Economy.settle_loan_day(1, -1000), {})
	assert_eq(Economy.cash, cash)
	assert_eq(Economy.loan.principal, 0)
	assert_eq(Fmt.price(40), "Free")
	GameMode.set_creative(false)
	assert_eq(Fmt.price(40), "$40", "career prices are unchanged")
	assert_eq(Fmt.for_price_each(4, "tile"), "for $4 a tile")
