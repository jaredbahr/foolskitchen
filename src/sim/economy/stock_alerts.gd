class_name StockAlerts
extends RefCounted
## The evening report's "Low stock" facts and their player-facing sentences.
## All player text about running out lives here (rule 11: names, never ids).


## Tomorrow morning as it will happen: tonight's expiry, then the auto-order
## planned with today's closing cash (nothing changes cash overnight).
## Rows list ingredients below target after expiry, or expiring:
## {id, usable, target, expiring, enabled, buys, short}, in the fixed order.
static func forecast(stock: Stock, settings: ReorderSettings, shelf_life_days: Dictionary,
		tomorrow: int, unit_costs: Dictionary, cash: int, premium: float) -> Dictionary:
	var rows: Array[Dictionary] = []
	if stock == null or settings == null:
		return {"rows": rows, "order_cost": 0}
	var after: Stock = Stock.from_dict(stock.to_dict())
	var expiring: Dictionary = after.expire(tomorrow, shelf_life_days)
	var plan: Dictionary = settings.plan(after, unit_costs, cash, premium)
	var buys: Dictionary = {}
	for line: Dictionary in plan["lines"]:
		buys[line["id"]] = int(line["qty"])
	var short: Dictionary = plan["short"]
	for id: StringName in settings.ids():
		var going: int = int(expiring.get(id, 0))
		var usable: int = after.count(id)
		var target: int = settings.target(id)
		if usable < target or going > 0:
			rows.append({"id": id, "usable": usable, "target": target, "expiring": going,
				"enabled": settings.is_enabled(id), "buys": int(buys.get(id, 0)),
				"short": int(short.get(id, 0))})
	return {"rows": rows, "order_cost": int(plan["cost"])}


## One sentence per ingredient that sold dishes out today, in the order it
## happened: "Tomato ran out at 19:40: Tomato soup and Tomato melt sold out".
static func sell_out_lines(events: Array[Dictionary], content: ContentDB) -> Array[String]:
	var lines: Array[String] = []
	for event: Dictionary in events:
		var names: Array[String] = []
		for recipe_id: StringName in event.get("dishes", []):
			names.append(_recipe_name(recipe_id, content))
		if names.is_empty():
			continue
		lines.append("%s ran out at %s: %s sold out" % [
			_ingredient_name(event.get("ingredient", &""), content),
			clock_text(int(event.get("minute", 0))), join_names(names)])
	return lines


## Only what needs the player: expiring units, ingredients the auto-order
## will not cover (switched off, or not enough cash), then one line with
## tomorrow's order cost. Plain top-ups to target are part of that order.
## "Tomato: 3 expire tomorrow, 2 left, target 16. Auto-reorder is off."
static func forecast_lines(forecast_data: Dictionary, content: ContentDB) -> Array[String]:
	var lines: Array[String] = []
	for row: Dictionary in forecast_data.get("rows", []):
		var going: int = int(row.get("expiring", 0))
		var usable: int = int(row.get("usable", 0))
		var target: int = int(row.get("target", 0))
		var enabled: bool = bool(row.get("enabled", false))
		var short: int = int(row.get("short", 0))
		var low: bool = usable < target
		if going <= 0 and not (low and (not enabled or short > 0)):
			continue
		var parts: Array[String] = []
		if going > 0:
			parts.append("%d expire tomorrow" % going)
		if low:
			parts.append("%d left, target %d" % [usable, target])
		var text: String = "%s: %s." % [_ingredient_name(row.get("id", &""), content), ", ".join(parts)]
		if low and not enabled:
			text += " Auto-reorder is off."
		elif short > 0:
			text += " Not enough cash to reorder %d." % short
		elif going > 0:
			text += " Auto-reorder replaces them."
		lines.append(text)
	var cost: int = int(forecast_data.get("order_cost", 0))
	if cost > 0:
		lines.append("With tonight's cash, tomorrow morning's auto-order will cost $%d." % cost)
	return lines


## "A", "A and B", "A, B and C".
static func join_names(names: Array[String]) -> String:
	if names.size() <= 1:
		return "" if names.is_empty() else names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## Minutes since midnight as a 24-hour clock.
static func clock_text(minutes: int) -> String:
	var normalized: int = maxi(minutes, 0) % (24 * 60)
	@warning_ignore("integer_division")
	var hours: int = normalized / 60
	return "%02d:%02d" % [hours, normalized % 60]


static func _ingredient_name(id: Variant, content: ContentDB) -> String:
	var definition: IngredientDef = content.ingredient(StringName(str(id))) if content != null else null
	return definition.display_name if definition != null and not definition.display_name.is_empty() \
		else "An ingredient"


static func _recipe_name(id: StringName, content: ContentDB) -> String:
	var definition: RecipeDef = content.recipe(id) if content != null else null
	return definition.display_name if definition != null and not definition.display_name.is_empty() \
		else "A dish"
