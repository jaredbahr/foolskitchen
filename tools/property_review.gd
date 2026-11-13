extends RefCounted
## Property market review fixture (FK-087), for
## `tools/screenshot.sh --property-review --speed=0 --frames=12`. The seed-1
## first morning with the career tier raised to 3 and enough cash for the
## fixer-upper put on the live owner (nothing saved), then the Menu's own
## Property button opens the market: three lots cheapest first, the
## fixer-upper's Buy button enabled with its cost, the seaside lot locked by
## stars (no closing reputation yet), the rooftop by tier.

const TIER: int = 3
## Enough for the fixer-upper ($8,500 to open), not for the seaside lot.
const CASH: int = 9000


static func prepare(main: Node, _root: Window) -> Dictionary:
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	if owner == null or not main.has_method("set_property_visible") or not bool(main.call("can_edit_menu")):
		return {"error": "property review needs Main's morning Menu"}
	owner.career_tier = TIER
	# Autoloads are looked up at run time: screenshot.gd preloads this file
	# before they exist.
	var economy: Node = main.get_node("/root/Economy")
	economy.call("add_cash", CASH - int(economy.get("cash")), Ledger.OTHER, "Property review fixture")
	if not bool(main.call("set_menu_visible", true)):
		return {"error": "the morning Menu did not open"}
	var menu: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	var button: Button = menu.get_node("%PropertyButton") as Button
	if not button.visible:
		return {"error": "the Menu has no Property button at Tier %d" % TIER}
	button.pressed.emit()
	if not bool(main.call("is_property_visible")):
		return {"error": "the Property button did not open the market"}
	return {"tier": TIER, "cash": CASH}


static func evidence(main: Node) -> Dictionary:
	var panel: PropertyPanel = main.get_node_or_null("Overlay/PropertyPanel") as PropertyPanel
	if panel == null:
		return {}
	var enabled: Array[String] = []
	var locked: Array[String] = []
	var labels: Dictionary = {}
	for id: StringName in panel.lot_ids():
		var card: Control = panel.card_for(id)
		var buy: Button = card.get_node_or_null("Body/Top/Buy") as Button
		if buy != null and not buy.disabled:
			enabled.append(String(id))
		labels[String(id)] = buy.text if buy != null else ""
		if bool(card.get_meta(&"locked", false)):
			locked.append(String(id))
	return {"visible": bool(main.call("is_property_visible")), "menu_visible": bool(main.call("is_menu_visible")),
		"lots": panel.lot_ids().map(func(id: StringName) -> String: return String(id)),
		"locked": locked, "enabled": enabled, "buy_labels": labels}


static func valid(state: Dictionary) -> bool:
	return state.get("visible") == true and state.get("menu_visible") == false \
		and state.get("enabled") == ["town_fixer_upper"] \
		and str((state.get("buy_labels", {}) as Dictionary).get("town_fixer_upper", "")).begins_with("Buy for") \
		and state.get("lots") == ["town_fixer_upper", "seaside_cliff", "skyscraper_rooftop"] \
		and (state.get("locked", []) as Array).has("skyscraper_rooftop") \
		and (state.get("locked", []) as Array).has("seaside_cliff")
