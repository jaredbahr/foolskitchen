extends RefCounted
## Morning site card review fixture (FK-087, #464), for
## `tools/screenshot.sh --site-card-review --speed=0 --frames=12`. The seed-1
## first morning at Tier 5 (three sites allowed) with cash on the live owner
## (nothing saved): the fixer-upper is bought through main.gd `buy_lot` (so it
## is renovating), and the seaside lot joins the site list built the same way
## (its star lock cannot be met on a first morning). Then main.gd shows the
## card: the current shop with "Stay here", the seaside lot with "Work here"
## and the fixer-upper's disabled "Renovating" button.

const TIER: int = 5
## Enough for the fixer-upper; the seaside site is added, not bought.
const CASH: int = 9000


static func prepare(main: Node, _root: Window) -> Dictionary:
	var owner: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var book: SiteBook = main.get("site_book") as SiteBook
	if owner == null or book == null or not main.has_method("buy_lot") or not bool(main.call("can_edit_menu")):
		return {"error": "site card review needs Main's morning"}
	owner.career_tier = TIER
	# Autoloads are looked up at run time: screenshot.gd preloads this file
	# before they exist.
	var economy: Node = main.get_node("/root/Economy")
	economy.call("add_cash", CASH - int(economy.get("cash")), Ledger.OTHER, "Site card review fixture")
	var today: int = ((main.get_node("/root/Clock").get("sim")) as SimClock).day
	if not bool(main.call("buy_lot", &"town_fixer_upper")):
		return {"error": "the fixer-upper could not be bought: " + str(main.call("lot_purchase_refusal", &"town_fixer_upper"))}
	var seaside: LotDef = null
	for lot: LotDef in (main.get("content") as ContentDB).lots():
		if lot.id == &"seaside_cliff":
			seaside = lot
	var sections: Dictionary = main.call("_new_site_sections", seaside) if seaside != null else {}
	if sections.is_empty() or not book.add_site(&"seaside_cliff", &"seaside_cliff", seaside.display_name,
			today, sections):
		return {"error": "the seaside site could not be added"}
	if not bool(main.call("set_site_card_visible", true)):
		return {"error": "the site card did not open"}
	return {"tier": TIER, "sites": book.site_count()}


static func evidence(main: Node) -> Dictionary:
	var card: SiteCard = main.get_node_or_null("Overlay/SiteCard") as SiteCard
	if card == null:
		return {}
	var buttons: Dictionary = {}
	for id: StringName in card.site_ids():
		var pick: Button = card.row_for(id).get_node_or_null("Body/Pick") as Button
		buttons[String(id)] = [pick.text, pick.disabled] if pick != null else []
	return {"visible": bool(main.call("is_site_card_visible")),
		"sites": card.site_ids().map(func(id: StringName) -> String: return String(id)), "buttons": buttons}


static func valid(state: Dictionary) -> bool:
	var buttons: Dictionary = state.get("buttons", {})
	return state.get("visible") == true \
		and state.get("sites") == ["home", "seaside_cliff", "town_fixer_upper"] \
		and buttons.get("home") == [SiteCard.STAY, false] \
		and buttons.get("seaside_cliff") == [SiteCard.GO, false] \
		and buttons.get("town_fixer_upper") == [SiteCard.RENOVATING, true]
