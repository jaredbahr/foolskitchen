class_name DailySpecialText
extends RefCounted
## All offer wording uses the recipe's player-facing name.


static func name_for(id: StringName, menu: Array[RecipeDef]) -> String:
	for recipe: RecipeDef in menu:
		if recipe != null and recipe.id == id:
			return recipe.display_name
	return ""


static func board(name: String) -> String:
	return "Today's special: " + name if not name.is_empty() else ""


static func selection_hint() -> String:
	return "Choose one enabled dish for %.0f%% off your set price today, or None." \
		% (MenuSettings.DEFAULT_TUNING.special_discount * 100.0)


static func hud(name: String) -> String:
	return "Special: " + name if not name.is_empty() else ""


static func report(name: String, sold: int) -> String:
	return "Today's special: %s, %d sold" % [name, sold] if not name.is_empty() else ""
