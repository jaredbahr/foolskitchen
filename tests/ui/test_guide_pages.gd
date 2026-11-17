extends "res://tests/test_case.gd"

const BOOK: GDScript = preload("res://src/ui/guide_book.gd")
const EXPECTED_TITLES: PackedStringArray = [
	"Menu and prices", "Stock", "Staff and priorities", "Build and paint",
	"Vibe and themes", "Reviews and reputation", "Cleanliness", "Loans", "Events",
]


func test_pages_are_ordered_player_safe_and_sized_for_the_guide() -> void:
	var pages: Array[GuidePage] = BOOK.load_pages()
	assert_eq(pages.size(), EXPECTED_TITLES.size())
	for index: int in range(mini(pages.size(), EXPECTED_TITLES.size())):
		var page: GuidePage = pages[index]
		assert_eq(page.title, EXPECTED_TITLES[index])
		var words: PackedStringArray = page.body.replace("\n", " ").strip_edges().split(" ", false)
		assert_true(words.size() >= 80 and words.size() <= 200,
			"%s has %d words" % [page.title, words.size()])
		assert_false(page.body.contains("{"), "%s has an unresolved data marker" % page.title)
		assert_false(page.body.contains("data/"), "%s exposes a file path" % page.title)
		assert_false(page.body.contains("_"), "%s may expose an internal name" % page.title)


func test_numeric_guide_facts_match_independently_loaded_authoritative_resources() -> void:
	var pages: Array[GuidePage] = BOOK.load_pages()
	var menu: String = pages[0].body
	var build: String = pages[3].body
	var loans: String = pages[7].body
	var career: String = pages[5].body
	var events: String = pages[8].body
	var fries: RecipeDef = load("res://data/recipes/fries.tres") as RecipeDef
	var fish: RecipeDef = load("res://data/recipes/fish_and_chips.tres") as RecipeDef
	var menu_tuning: MenuTuning = load("res://data/balance/menu.tres") as MenuTuning
	var signature_tuning: SignatureTuning = load("res://data/balance/signature.tres") as SignatureTuning
	var loan_tuning: LoanTuning = load("res://data/balance/loans.tres") as LoanTuning
	var career_tuning: CareerTierTuning = load("res://data/balance/career_tiers.tres") as CareerTierTuning
	var tier_two: CareerTier = career_tuning.rung_for(2)
	var tier_three: CareerTier = career_tuning.rung_for(3)
	var floor: FloorStyleDef = load("res://data/floors/small_tile.tres") as FloorStyleDef
	var wall: WallStyleDef = load("res://data/wall_finishes/brick.tres") as WallStyleDef
	var critic: ServiceEventDef = load("res://data/events/critic_rumour.tres") as ServiceEventDef
	var rush: RushTuning = load("res://data/balance/rush_hour.tres") as RushTuning
	var fries_unlock: String = "owner level %d" % fries.unlock_level if fries.unlock_tier <= 1 else \
		"Tier %d and owner level %d" % [fries.unlock_tier, fries.unlock_level]
	var fish_unlock: String = "owner level %d" % fish.unlock_level if fish.unlock_tier <= 1 else \
		"Tier %d and owner level %d" % [fish.unlock_tier, fish.unlock_level]
	var recipe_example: String = "%s opens at %s, and %s follows at %s" % [
		fries.display_name, fries_unlock, fish.display_name, fish_unlock]
	assert_true(menu.contains(recipe_example), "recipe names and unlock levels match their resources")
	assert_true(menu.contains("receives a %d%% price discount" % roundi(menu_tuning.special_discount * 100.0)),
		"special discount matches menu tuning")
	assert_true(menu.contains("eligible as your signature after %d paid sales" % signature_tuning.signature_unlock_sales),
		"signature sales gate matches signature tuning")
	assert_true(menu.contains("change it after %d days" % signature_tuning.change_cooldown_days),
		"signature cooldown matches signature tuning")
	var floor_unlock: String = "owner level %d" % floor.unlock_level if floor.unlock_tier <= 1 else \
		"Tier %d and owner level %d" % [floor.unlock_tier, floor.unlock_level]
	var wall_unlock: String = "owner level %d" % wall.unlock_level if wall.unlock_tier <= 1 else \
		"Tier %d and owner level %d" % [wall.unlock_tier, wall.unlock_level]
	var build_example: String = "For example, %s unlock at %s, and %s at %s" % [
		floor.display_name, floor_unlock, wall.display_name, wall_unlock]
	assert_true(build.contains(build_example), "floor and wall unlocks match their resources")
	assert_true(loans.contains("%.0f%% interest each day" % (loan_tuning.daily_interest * 100.0)),
		"interest matches loan tuning")
	assert_true(loans.contains("%.0f%% of positive operating profit" % (loan_tuning.repay_share * 100.0)),
		"repayment share matches loan tuning")
	assert_true(loans.contains("$%d" % loan_tuning.borrowing_step), "borrowing step matches loan tuning")
	var career_example: String = "Tier 2 requires owner level %d and Tier 3 requires level %d" % [
		tier_two.min_level, tier_three.min_level]
	if tier_three.min_reputation > 0.0:
		career_example += " and %.1f stars" % tier_three.min_reputation
	assert_true(career.contains(career_example), "career level and reputation gates match tier data")
	var event_requirement: String = "Tier %d" % critic.min_tier
	if critic.min_level > 1:
		event_requirement += " and owner level %d" % critic.min_level
	assert_true(events.contains("%s becomes eligible at %s" % [critic.title, event_requirement]),
		"event trigger matches event data")
	assert_true(events.contains("rush hours unlock at owner level %d" % rush.unlock_level),
		"rush hour gate matches its tuning")
