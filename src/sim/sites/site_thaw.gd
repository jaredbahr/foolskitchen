class_name SiteThaw
extends RefCounted
## Step 2 of a site switch (FK-087, docs/TECH.md "Switching (part 1)"): ages a
## frozen site's per-site save sections from the morning it was frozen to
## today's morning, as if the site had sat closed in between. Pure and node
## free: no clock, autoload or random draw; the caller passes the days.
##
## Input and output sections are shaped like a decoded JSON save file
## (numbers as floats, no StringNames). The input is never changed. Sections
## that are rewritten come from their class's own to_dict (or, where a class
## has no API for the change, a copy with only the day fields moved) and then
## go through JSON, so they reach SaveSystem.restore_sections in the same
## shape as everything else. Missing sections stay missing.
##
## SiteThaw checks the day conditions of main.gd's morning load
## (_load_autosave_sections) for every section it can decode without the
## content catalogue. It is not the whole gate: the restore providers and the
## morning load still validate everything when step 3 installs the result.
##
## Per-section decisions (gap = today - frozen_day):
## - demand: decays one day at a time, exactly as DemandState.begin_morning
##   does each morning, with no award (the site served nobody).
## - daily_special: cleared; a fresh special for today.
## - rush_hour: the event rolled for the frozen morning lapses; its stamps and
##   cooldown stay on the calendar, so today's morning rolls again.
## - bookings: pending offers clear. An accepted booking whose service day has
##   passed (the site was closed then) lapses, and its customer deposit is
##   returned as a refund movement for the caller to pay. One for today stays.
## - deliveries: due days move forward by the gap (paid orders wait, once).
## - pantry: stock lots do not age while frozen (bought days move forward).
## - aquarium: tanks do not cloud while frozen (cleaning days move forward).
## - critic: the plan rolled for the frozen morning lapses; cooldown stays.
## - everything else is unchanged (see DECISIONS for the reasons).

const MAX_DAY: int = 9007199254740991
## Delivery due days are stored in a Vector2i (32-bit).
const MAX_DELIVERY_DAY: int = 2147483647
const REFUND_NOTE: String = "Booking refunded: the restaurant was closed that day"

## Every per-site section and what the thaw does to it. A test checks this
## covers SiteSections.PER_SITE, so a new section must choose.
const DECISIONS: Dictionary[String, String] = {
	"shop": "unchanged: the layout has no day stamps",
	"menu": "unchanged: no day stamps",
	"daily_special": "clear: a special is chosen for one day",
	"signature": "unchanged: the change cooldown runs on the calendar",
	"staff": "unchanged: hiring pool and quit days run on the calendar; today's morning draws a new pool",
	"plates": "unchanged: no day stamps",
	"reviews": "unchanged: no day stamps",
	"regulars": "unchanged: visits are on the calendar; regulars who are due return when the site reopens",
	"reorder": "unchanged: no day stamps",
	"deliveries": "shift: paid orders arrive the gap later",
	"demand": "decay: renown fades over the closed days, as each morning",
	"viral": "unchanged: the boost counts open services, which closed days do not use; cooldown on the calendar",
	"business_history": "unchanged: past days stay past",
	"shop_records": "unchanged: past days stay past",
	"cat": "unchanged: no day stamps",
	"inspection": "unchanged: grade effect and cooldown on the calendar; today's morning plans a new visit",
	"critic": "lapse: the frozen morning's planned visit is dropped; cooldown on the calendar",
	"bookings": "lapse: offers clear; past accepted bookings refund their deposit",
	"rush_hour": "lapse: the frozen morning's rush is dropped; cooldown on the calendar",
	"aquarium": "shift: tanks do not cloud while the site is frozen",
	"pantry": "shift: stock does not spoil while the site is frozen",
}


## Returns {"sections": Dictionary, "refunds": Array[Dictionary]}, or {} when
## the days are impossible or a section cannot be thawed. Each refund is a
## ledger movement {"amount": int (negative), "category": StringName,
## "note": String}; SiteThaw cannot touch the ledger, so the switch (step 3)
## pays them with Economy.add_cash once the thawed site is installed.
## A gap of 0 returns an exact copy of the input (switching away and back on
## the same morning loses nothing).
static func thaw(sections: Dictionary, frozen_day: int, today: int,
		tunings: SiteThawTunings) -> Dictionary:
	if frozen_day < 1 or today < frozen_day or today > MAX_DAY \
			or tunings == null or not tunings.is_valid():
		return {}
	var gap: int = today - frozen_day
	var out: Dictionary = {}
	var refunds: Array[Dictionary] = []
	for key: Variant in sections:
		if typeof(key) != TYPE_STRING or not SiteSections.is_per_site(key) \
				or not sections[key] is Dictionary:
			return {}
		var source: Dictionary = sections[key]
		var thawed: Variant = _thaw_section(key, source, frozen_day, today, gap, tunings, refunds)
		if not thawed is Dictionary:
			return {}
		out[key] = thawed
	if gap == 0:
		return {"sections": sections.duplicate(true), "refunds": [] as Array[Dictionary]}
	return {"sections": out, "refunds": refunds}


## A thawed copy of one section, or null when it cannot be thawed.
static func _thaw_section(key: String, data: Dictionary, frozen_day: int, today: int,
		gap: int, tunings: SiteThawTunings, refunds: Array[Dictionary]) -> Variant:
	match key:
		"demand":
			return _thaw_demand(data, frozen_day, today, tunings.demand)
		"daily_special":
			return _thaw_daily_special(data, frozen_day, today)
		"signature":
			return _check_signature(data, frozen_day, tunings.signature)
		"viral":
			return _check_viral(data, frozen_day, tunings.viral)
		"rush_hour":
			return _thaw_rush_hour(data, frozen_day, today, tunings.rush)
		"deliveries":
			return _thaw_deliveries(data, gap)
		"bookings":
			return _thaw_bookings(data, frozen_day, today, tunings.booking, refunds)
		"business_history":
			var history: BusinessHistory = BusinessHistory.new()
			return data.duplicate(true) if history.restore(data) and history.valid_before(frozen_day) else null
		"shop_records":
			var records: ShopRecords = ShopRecords.new()
			return data.duplicate(true) if records.restore(data) and records.valid_before(frozen_day) else null
		"staff":
			return _check_staff(data, frozen_day)
		"inspection":
			var inspection: InspectionBook = InspectionBook.new()
			return data.duplicate(true) if inspection.from_dict(data) \
				and inspection.planned_day <= frozen_day else null
		"critic":
			return _thaw_critic(data, frozen_day, today)
		"aquarium":
			return _thaw_aquarium(data, gap)
		"pantry":
			return _thaw_pantry(data, gap)
	# Sections without day stamps (DECISIONS) are copied as they are.
	return data.duplicate(true)


## Decays across the closed days in one step, as begin_morning does for any
## gap (pow(1 - decay, gap)); a per-day loop would cost one step per day.
## No close ran, so last_award_day stays before today.
static func _thaw_demand(data: Dictionary, frozen_day: int, today: int,
		tuning: DemandTuning) -> Variant:
	var state: DemandState = DemandState.new()
	if not state.from_dict(data) or state.day != frozen_day or state.last_award_day >= frozen_day:
		return null
	if not state.begin_morning(today, tuning):
		return null
	if state.day != today or state.last_decay_day != today:
		return null
	return _json(state.to_dict())


## A special is a choice for one day, so the frozen one clears.
static func _thaw_daily_special(data: Dictionary, frozen_day: int, today: int) -> Variant:
	var saved_day: Variant = data.get("day")
	if data.size() != 3 or not _whole(data.get("version"), 1, 1) \
			or not _whole(saved_day, 1, frozen_day) or not data.get("recipe") is String:
		return null
	var special: DailySpecial = DailySpecial.new()
	if not special.begin_morning(today):
		return null
	return _json(special.to_dict())


## Unchanged: the change cooldown is a limit on the player's choices that runs
## on the calendar, like the critic's. Checked with the morning load's call.
static func _check_signature(data: Dictionary, frozen_day: int, tuning: SignatureTuning) -> Variant:
	# The catalogue is not known here: accept the ids the section names, so
	# only the shape and the day are checked (the provider checks the ids).
	var ids: Array[StringName] = []
	var sales: Variant = data.get("sales")
	if sales is Dictionary:
		for id: Variant in sales:
			if typeof(id) == TYPE_STRING:
				ids.append(StringName(id))
	if data.get("signature_id") is String:
		ids.append(StringName(data["signature_id"]))
	var state: SignatureState = SignatureState.new(ids)
	return data.duplicate(true) if state.from_dict(data, frozen_day, tuning) else null


## Unchanged: days_left counts open services, and a closed day uses none, so a
## boost waits for the reopening. The cooldown is calendar days by design
## (ViralTuning.cooldown_days). last_close_day is before the frozen morning.
static func _check_viral(data: Dictionary, frozen_day: int, tuning: ViralTuning) -> Variant:
	var viral: ViralReview = ViralReview.new(tuning)
	if not viral.from_dict(data) or not viral.valid_before_morning(frozen_day):
		return null
	return data.duplicate(true)


## The rush rolled for the frozen morning was a town event on that day: it
## lapses. rolled_day and last_rush_day stay, so the cooldown counts calendar
## days and today's morning rolls afresh (rolled_day is before today).
static func _thaw_rush_hour(data: Dictionary, frozen_day: int, today: int,
		tuning: RushTuning) -> Variant:
	var rush: RushHour = RushHour.new(tuning)
	if not rush.from_dict(data) or rush.rolled_day > frozen_day:
		return null
	rush.begin_day(today)
	return _json(rush.to_dict())


## Paid orders keep waiting: each due day moves forward by the gap, once,
## here only. An order due the frozen morning's afternoon arrives this
## afternoon; one due the next morning arrives the morning after today.
static func _thaw_deliveries(data: Dictionary, gap: int) -> Variant:
	var book: DeliveryBook = DeliveryBook.new()
	if not book.from_dict(data):
		return null
	var moved: DeliveryBook = DeliveryBook.new()
	for order: Dictionary in book.orders():
		var due: Vector2i = order["due"]
		# Vector2i holds 32-bit days.
		if due.x > MAX_DELIVERY_DAY - gap:
			return null
		var lines: Array[Dictionary] = []
		lines.assign(order["lines"])
		if not moved.place(lines, int(order["cost"]), bool(order["standing"]),
				Vector2i(due.x + gap, due.y)):
			return null
	return _json(moved.to_dict())


## New offers come only to the active site, so a pending offer clears. An
## accepted booking whose service day is before today fell on a day the site
## was closed: it lapses with its deposit refunded and no reputation change
## (design: "Bookings"). A booking for today stays: the site opens today.
static func _thaw_bookings(data: Dictionary, frozen_day: int, today: int,
		tuning: BookingTuning, refunds: Array[Dictionary]) -> Variant:
	if data.is_empty():
		return {} # Below the unlock level the section is saved empty.
	var booking: GroupBooking = GroupBooking.new(tuning)
	if not booking.from_dict(data) or booking.planned_day > frozen_day:
		return null
	booking.offer.clear()
	if booking.has_active_booking() and int(booking.booking["service_day"]) < today:
		var deposit: int = int(booking.booking["deposit_amount"])
		if deposit > 0:
			refunds.append({"amount": -deposit, "category": Ledger.BOOKING_REFUND,
				"note": REFUND_NOTE})
		booking.booking.clear()
	return _json(booking.to_dict())


## Unchanged; the pool was drawn no later than the frozen morning, so today's
## morning can draw a new one (the load needs candidate_day <= today).
static func _check_staff(data: Dictionary, frozen_day: int) -> Variant:
	return data.duplicate(true) if _whole(data.get("candidate_day"), 0, frozen_day) else null


## The visit planned for the frozen morning lapses (that day is gone). Asking
## for a plan with no stream only clears it: nothing is rolled or marked, so
## today's morning rolls as usual. last_visit_day keeps the calendar cooldown.
static func _thaw_critic(data: Dictionary, frozen_day: int, today: int) -> Variant:
	var critic: FoodCritic = FoodCritic.new()
	if not critic.from_dict(data) or critic.rolled_day > frozen_day:
		return null
	critic.plan_day(today, 0, Callable())
	return _json(critic.to_dict())


## Tanks do not cloud while the site is frozen, like the pantry. The section
## is keyed by tank position (to_dict needs the live grid), so only the days
## move; the shape is checked before and after.
static func _thaw_aquarium(data: Dictionary, gap: int) -> Variant:
	if not AquariumCare.valid_dict(data):
		return null
	var out: Dictionary = data.duplicate(true)
	for row: Dictionary in out["tanks"]:
		row["cleaned_day"] = int(row["cleaned_day"]) + gap
	return _json(out) if AquariumCare.valid_dict(out) else null


## Frozen stock does not age: every lot's bought day moves forward by the gap.
## A switch must not cost the player a pantry they could not use while away,
## and paid deliveries wait the same way. The spoilage receipt keeps its day:
## it belongs to the frozen morning's report, never today's.
static func _thaw_pantry(data: Dictionary, gap: int) -> Variant:
	if not data.get("stock") is Dictionary:
		return null
	var stock: Stock = Stock.from_dict(data["stock"])
	if stock == null:
		return null
	var encoded: Dictionary = stock.to_dict()
	var batches: Dictionary = encoded["batches"]
	for id: String in batches:
		for row: Dictionary in batches[id]:
			var bought: int = String(row["bought_day"]).to_int()
			if bought > MAX_DAY - gap:
				return null
			row["bought_day"] = str(bought + gap)
	if Stock.from_dict(encoded) == null:
		return null
	var out: Dictionary = data.duplicate(true)
	out["stock"] = encoded
	return _json(out)


static func _json(section: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(section))


static func _whole(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high and floor(number) == number
