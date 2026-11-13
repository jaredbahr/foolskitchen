extends RefCounted
## Property market review fixture (FK-087 part 2), for
## `tools/screenshot.sh --property-review --speed=0 --frames=12`. The seed-1
## first morning with the career tier raised to 3 on the live owner (nothing
## saved), then the Menu's own Property button opens the browse-only screen:
## three lots cheapest first, the rooftop locked by tier, the seaside lot by
## the first day's stars, and every Buy button disabled ("Coming soon").

const TIER: int = 3


static func prepare(main: Node, _root: Window) -> Dictionary:
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	if owner == null or not main.has_method("set_property_visible") or not bool(main.call("can_edit_menu")):
		return {"error": "property review needs Main's morning Menu"}
	owner.career_tier = TIER
	if not bool(main.call("set_menu_visible", true)):
		return {"error": "the morning Menu did not open"}
	var menu: MenuPanel = main.get_node("Overlay/MenuPanel") as MenuPanel
	var button: Button = menu.get_node("%PropertyButton") as Button
	if not button.visible:
		return {"error": "the Menu has no Property button at Tier %d" % TIER}
	button.pressed.emit()
	if not bool(main.call("is_property_visible")):
		return {"error": "the Property button did not open the market"}
	return {"tier": TIER}


static func evidence(main: Node) -> Dictionary:
	var panel: PropertyPanel = main.get_node_or_null("Overlay/PropertyPanel") as PropertyPanel
	if panel == null:
		return {}
	var buys_disabled: bool = true
	var locked: Array[String] = []
	for id: StringName in panel.lot_ids():
		var card: Control = panel.card_for(id)
		var buy: Button = card.get_node_or_null("Body/Top/Buy") as Button
		buys_disabled = buys_disabled and buy != null and buy.disabled and buy.text == PropertyText.BUY_SOON
		if bool(card.get_meta(&"locked", false)):
			locked.append(String(id))
	return {"visible": bool(main.call("is_property_visible")), "menu_visible": bool(main.call("is_menu_visible")),
		"lots": panel.lot_ids().map(func(id: StringName) -> String: return String(id)),
		"locked": locked, "buys_disabled": buys_disabled}


static func valid(state: Dictionary) -> bool:
	return state.get("visible") == true and state.get("menu_visible") == false \
		and state.get("buys_disabled") == true \
		and state.get("lots") == ["town_fixer_upper", "seaside_cliff", "skyscraper_rooftop"] \
		and (state.get("locked", []) as Array).has("skyscraper_rooftop")
