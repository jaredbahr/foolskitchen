class_name StreetSignText
extends RefCounted
## The two lines on the street A-frame: the restaurant name (the same
## normalized name the menu boards and the HUD use) and today's special.
## The special is the enabled dish with the best margin (its price minus its
## ingredient cost), or Coffee when the menu leans to a cafe. Read-only: no
## RNG, no menu or price change.

const COFFEE_ID: StringName = &"coffee"
const CAFE_THEME: StringName = &"cafe"
const SPECIAL_PREFIX: String = "Today: "


## `prices` maps a recipe id to its current price; a missing dish sells at
## its standard price. Ties go to the lower id so the sign never flickers.
static func special(menu: Array[RecipeDef], prices: Dictionary = {}) -> RecipeDef:
	var best: RecipeDef = null
	var best_margin: int = 0
	var cafe: bool = MenuThemeText.leading_theme(menu) == CAFE_THEME
	for recipe: RecipeDef in menu:
		if recipe == null:
			continue
		if cafe and recipe.id == COFFEE_ID:
			return recipe
		var margin: int = int(prices.get(recipe.id, recipe.standard_price)) - recipe.ingredient_cost()
		if best == null or margin > best_margin or margin == best_margin and String(recipe.id) < String(best.id):
			best = recipe
			best_margin = margin
	return best


## The sign's name line; an empty or odd name falls back to the default one.
static func name_line(restaurant_name: String) -> String:
	var normalized: String = MenuSettings.normalized_restaurant_name(restaurant_name)
	return normalized if not normalized.is_empty() else MenuSettings.DEFAULT_NAME


## The special's line, or empty when no dish is enabled.
static func special_line(menu: Array[RecipeDef], prices: Dictionary = {}) -> String:
	var recipe: RecipeDef = special(menu, prices)
	return "" if recipe == null else SPECIAL_PREFIX + recipe.display_name


## Both lines as one text, for inspection and tests.
static func text(restaurant_name: String, menu: Array[RecipeDef], prices: Dictionary = {}) -> String:
	var line: String = special_line(menu, prices)
	return name_line(restaurant_name) if line.is_empty() else name_line(restaurant_name) + "\n" + line
