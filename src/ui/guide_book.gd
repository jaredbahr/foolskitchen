class_name GuideBook
extends RefCounted
## Ordered, data-backed guide pages for an F1/HUD presentation.
## `load_pages()` returns ready-to-display pages with live balance terms filled in.

const PAGE_PATHS: PackedStringArray = [
	"res://data/guide/01_menu_and_prices.tres",
	"res://data/guide/02_stock.tres",
	"res://data/guide/03_staff_and_priorities.tres",
	"res://data/guide/04_build_and_paint.tres",
	"res://data/guide/05_vibe_and_themes.tres",
	"res://data/guide/06_reviews_and_reputation.tres",
	"res://data/guide/07_cleanliness.tres",
	"res://data/guide/08_loans.tres",
	"res://data/guide/09_events.tres",
]

const LOAN_TUNING: LoanTuning = preload("res://data/balance/loans.tres")
const MENU_TUNING: MenuTuning = preload("res://data/balance/menu.tres")
const SIGNATURE_TUNING: SignatureTuning = preload("res://data/balance/signature.tres")
const CAREER_TUNING: CareerTierTuning = preload("res://data/balance/career_tiers.tres")
const STARTER_RECIPE: RecipeDef = preload("res://data/recipes/fries.tres")
const FOLLOWUP_RECIPE: RecipeDef = preload("res://data/recipes/fish_and_chips.tres")
const FLOOR_UNLOCK_SAMPLE: FloorStyleDef = preload("res://data/floors/small_tile.tres")
const WALL_UNLOCK_SAMPLE: WallStyleDef = preload("res://data/wall_finishes/brick.tres")
const EVENT_UNLOCK_SAMPLE: ServiceEventDef = preload("res://data/events/critic_rumour.tres")
const RUSH_TUNING: RushTuning = preload("res://data/balance/rush_hour.tres")


static func load_pages() -> Array[GuidePage]:
	var pages: Array[GuidePage] = []
	for path: String in PAGE_PATHS:
		var page: GuidePage = load(path) as GuidePage
		if page == null:
			push_error("Guide page could not be loaded: %s" % path)
			continue
		var ready_page: GuidePage = page.duplicate() as GuidePage
		ready_page.body = _fill_facts(ready_page.body)
		pages.append(ready_page)
	return pages


static func _fill_facts(body: String) -> String:
	var result: String = body
	result = result.replace("{menu_unlock_example}", _menu_unlock_example())
	result = result.replace("{menu_special_rule}", _menu_special_rule())
	result = result.replace("{signature_rule}", _signature_rule())
	result = result.replace("{career_unlock_example}", _career_unlock_example())
	result = result.replace("{build_unlock_example}", _build_unlock_example())
	result = result.replace("{event_unlock_example}", _event_unlock_example())
	result = result.replace("{loan_interest}", "%.0f%%" % (LOAN_TUNING.daily_interest * 100.0))
	result = result.replace("{loan_repay_share}", "%.0f%%" % (LOAN_TUNING.repay_share * 100.0))
	result = result.replace("{loan_step}", "$%d" % LOAN_TUNING.borrowing_step)
	return result


static func _menu_unlock_example() -> String:
	if STARTER_RECIPE == null or FOLLOWUP_RECIPE == null \
			or FOLLOWUP_RECIPE.unlock_from != STARTER_RECIPE.id:
		return "New dishes appear as you gain owner levels."
	return "%s opens at %s, and %s follows at %s" % [
		STARTER_RECIPE.display_name, _recipe_unlock_terms(STARTER_RECIPE),
		FOLLOWUP_RECIPE.display_name, _recipe_unlock_terms(FOLLOWUP_RECIPE)]


static func _career_unlock_example() -> String:
	var tier_two: CareerTier = CAREER_TUNING.rung_for(2)
	var tier_three: CareerTier = CAREER_TUNING.rung_for(3)
	if tier_two == null or tier_three == null:
		return "The Goals panel shows the requirements for your next career tier."
	var result: String = "Tier 2 requires owner level %d" % tier_two.min_level
	result += " and Tier 3 requires level %d" % tier_three.min_level
	if tier_three.min_reputation > 0.0:
		result += " and %.1f stars" % tier_three.min_reputation
	return result + "."


static func _menu_special_rule() -> String:
	return "Any enabled dish can be selected as today's special each morning. It receives a %d%% price discount." % \
		roundi(MENU_TUNING.special_discount * 100.0)


static func _signature_rule() -> String:
	return "A dish becomes eligible as your signature after %d paid sales. You can change it after %d days." % [
		SIGNATURE_TUNING.signature_unlock_sales, SIGNATURE_TUNING.change_cooldown_days]


static func _build_unlock_example() -> String:
	return "For example, %s unlock at %s, and %s at %s" % [
		FLOOR_UNLOCK_SAMPLE.display_name, _style_unlock_terms(FLOOR_UNLOCK_SAMPLE.unlock_level,
			FLOOR_UNLOCK_SAMPLE.unlock_tier),
		WALL_UNLOCK_SAMPLE.display_name, _style_unlock_terms(WALL_UNLOCK_SAMPLE.unlock_level,
			WALL_UNLOCK_SAMPLE.unlock_tier)]


static func _event_unlock_example() -> String:
	var event_requirement: String = "Tier %d" % EVENT_UNLOCK_SAMPLE.min_tier
	if EVENT_UNLOCK_SAMPLE.min_level > 1:
		event_requirement += " and owner level %d" % EVENT_UNLOCK_SAMPLE.min_level
	var rush_requirement: String = "owner level %d" % RUSH_TUNING.unlock_level
	return "%s becomes eligible at %s, and rush hours unlock at %s." % [
		EVENT_UNLOCK_SAMPLE.title, event_requirement, rush_requirement]


static func _recipe_unlock_terms(recipe: RecipeDef) -> String:
	return "owner level %d" % recipe.unlock_level if recipe.unlock_tier <= 1 else \
		"Tier %d and owner level %d" % [recipe.unlock_tier, recipe.unlock_level]


static func _style_unlock_terms(level: int, tier: int) -> String:
	return "owner level %d" % level if tier <= 1 else "Tier %d and owner level %d" % [tier, level]
