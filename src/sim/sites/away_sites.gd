class_name AwaySites
extends RefCounted
## What the owner's inactive sites earn and pay at each close of the active
## site (FK-087, docs/TECH.md "Managers and away sites", "Bookings"). Pure and
## node free, with no random draw (D24 amended: a deterministic summary of a
## site's own recent results, never a seeded sim). The session books the
## returned movements to each earning site and writes back the bookings.
##
## - A site with a valid manager earns min(rate * mean, mean) over its last
##   `history_days` recorded in-person business_history days; none means 0.
##   That mean is already net of its wages and rent, so it pays nothing else.
##   A negative mean is paid as a loss: the formula is applied as written, and
##   min() then takes the whole mean (a manager never does better than the
##   owner did in person, on a bad run as on a good one).
## - A site without one stays closed and pays only its rent. A lot whose rent
##   is unknown here (no LotDef yet, #405) is charged nothing, with a warning.
## - An accepted group booking whose day has come lapses at this close with
##   its deposit refunded and no reputation change, managed or not.
## Away days are never written into a site's history.

const MANAGED: StringName = &"managed"
const CLOSED: StringName = &"closed"
## lot_rent's answer for a lot it cannot price.
const UNKNOWN_RENT: int = -1
const INCOME_NOTE: String = "Earned by the manager while you were away"
const RENT_NOTE: String = "Rent while the restaurant was closed"


## The away earnings for one site: min(rate * mean, mean) of its last
## `tuning.history_days` rows with a recorded dish profit (fewer rows use
## what there is; none gives 0). `rows` are BusinessHistory rows, oldest first.
static func earnings(rows: Array[Dictionary], skill: int, tuning: SiteManagerTuning) -> int:
	if tuning == null or not tuning.is_valid():
		return 0
	var recorded: Array[int] = []
	for row: Dictionary in rows:
		if bool(row.get("dish_profit_recorded", false)):
			recorded.append(int(row.get("dish_profit", 0)))
	var count: int = mini(recorded.size(), tuning.history_days)
	if count == 0:
		return 0
	var total: int = 0
	for index: int in range(recorded.size() - count, recorded.size()):
		total += recorded[index]
	var mean: float = float(total) / float(count)
	return roundi(minf(tuning.rate_for(skill) * mean, mean))


## The earnings read from a site's saved business_history section, or 0 when
## it has none or does not decode.
static func earnings_from_section(history: Dictionary, skill: int, tuning: SiteManagerTuning) -> int:
	var decoded: BusinessHistory = BusinessHistory.new()
	if not decoded.restore(history):
		return 0
	return earnings(decoded.summaries(), skill, tuning)


## The service skill of `member_id` when that person is a Manager in the
## saved staff section, else 0 (no valid manager).
static func manager_skill(staff: Dictionary, member_id: StringName) -> int:
	if member_id.is_empty() or staff.is_empty():
		return 0
	var roster: StaffRoster = StaffRoster.new()
	if not roster.from_dict(staff):
		return 0
	for member: StaffMember in roster.members():
		if member.id == member_id:
			return member.skill if member.role == StaffMember.MANAGER else 0
	return 0


## A closed site's daily rent: the home lot pays `home_rent` (today's rent
## rule, which the caller reads from the home lease). Other lots have no
## rent source yet (LotDef.daily_rent, #405): UNKNOWN_RENT.
static func lot_rent(lot: StringName, home_rent: int) -> int:
	if lot == SiteBook.HOME_LOT:
		return maxi(0, home_rent)
	return UNKNOWN_RENT


## Lapses an accepted booking due on or before `day` in a saved bookings
## section. Returns {"section": Dictionary, "refund": int (the deposit)}
## when one lapsed, {} when nothing changes (no booking due, an empty
## section, or one that does not decode, which the thaw then refuses).
static func lapse_booking(section: Dictionary, day: int, tuning: BookingTuning) -> Dictionary:
	if section.is_empty():
		return {}
	var booking: GroupBooking = GroupBooking.new(tuning)
	if not booking.from_dict(section) or not booking.has_active_booking() \
			or int(booking.booking["service_day"]) > day:
		return {}
	var deposit: int = maxi(0, int(booking.booking["deposit_amount"]))
	booking.booking.clear()
	return {"section": JSON.parse_string(JSON.stringify(booking.to_dict())), "refund": deposit}


## One entry per inactive site, in SiteBook order:
## {"site": StringName, "status": MANAGED or CLOSED, "amount": int (signed
## earnings, or minus the rent; 0 for an unknown rent), "rent_known": bool,
## "refund": int (a lapsed booking's deposit, else 0), "bookings": Dictionary
## (the rewritten section; only when a booking lapsed), "movements":
## Array[Dictionary] of {"amount", "category", "note"} for Economy}.
static func plan_close(book: SiteBook, day: int, home_rent: int, tuning: SiteManagerTuning,
		booking_tuning: BookingTuning) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	if book == null:
		return plans
	for id: StringName in book.site_ids():
		if id == book.active_id or not book.is_frozen(id):
			continue
		var sections: Dictionary = book.frozen_sections(id)
		var plan: Dictionary = {"site": id, "status": CLOSED, "amount": 0, "rent_known": true,
			"refund": 0, "movements": [] as Array[Dictionary]}
		var movements: Array[Dictionary] = plan["movements"]
		var staff: Dictionary = sections.get("staff", {}) if sections.get("staff") is Dictionary else {}
		var skill: int = manager_skill(staff, book.manager(id))
		if skill > 0:
			plan["status"] = MANAGED
			var history: Dictionary = sections.get("business_history", {}) \
				if sections.get("business_history") is Dictionary else {}
			var earned: int = earnings_from_section(history, skill, tuning)
			plan["amount"] = earned
			if earned != 0:
				movements.append({"amount": earned, "category": Ledger.AWAY_SITE_INCOME, "note": INCOME_NOTE})
		else:
			var rent: int = lot_rent(book.lot_id(id), home_rent)
			if rent == UNKNOWN_RENT:
				plan["rent_known"] = false
			else:
				plan["amount"] = -rent
				if rent > 0:
					movements.append({"amount": -rent, "category": Ledger.AWAY_SITE_RENT, "note": RENT_NOTE})
		if sections.get("bookings") is Dictionary:
			var lapsed: Dictionary = lapse_booking(sections["bookings"], day, booking_tuning)
			if not lapsed.is_empty():
				plan["bookings"] = lapsed["section"]
				plan["refund"] = int(lapsed["refund"])
				if int(lapsed["refund"]) > 0:
					movements.append({"amount": -int(lapsed["refund"]), "category": Ledger.BOOKING_REFUND,
						"note": SiteThaw.REFUND_NOTE})
		plans.append(plan)
	return plans


## The site's name for player text: its own name, else the restaurant name
## saved in its menu, else a plain fallback. Never an id.
static func display_name(book: SiteBook, id: StringName) -> String:
	var own: String = book.site_name(id) if book != null else ""
	if not own.is_empty():
		return own
	var sections: Dictionary = book.frozen_sections(id) if book != null else {}
	var menu: Variant = sections.get("menu")
	if menu is Dictionary and (menu as Dictionary).get("name") is String \
			and not String((menu as Dictionary)["name"]).strip_edges().is_empty():
		return String((menu as Dictionary)["name"]).strip_edges()
	return "Your other restaurant"


## One evening report line for a plan: "Pier Shack (managed): +$84",
## "Pier Shack (closed): rent -$40".
static func report_line(name: String, plan: Dictionary) -> String:
	var amount: int = int(plan.get("amount", 0))
	var line: String
	if plan.get("status") == MANAGED:
		line = "%s (managed): %s" % [name, _signed_money(amount)]
	elif not bool(plan.get("rent_known", true)):
		line = "%s (closed): no rent charged" % name
	else:
		line = "%s (closed): rent %s" % [name, _signed_money(amount) if amount != 0 else "$0"]
	var refund: int = int(plan.get("refund", 0))
	if refund > 0:
		line += "; a group booking there was refunded (%s)" % _signed_money(-refund)
	return line


static func _signed_money(amount: int) -> String:
	var digits: String = str(absi(amount))
	var grouped: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += ","
		grouped += digits[index]
	return ("-$" if amount < 0 else "+$") + grouped
