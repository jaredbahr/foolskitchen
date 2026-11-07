extends RefCounted
## Fixed, disclosed manual experiment. No successful-seed selection and no
## patience, meal duration, gap, stock grant or staff-speed changes.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const JOINED: Script = preload("res://tools/joined_tables_review.gd")
const SLOT_MINUTE: int = 14 * 60
const CASES: int = 24
const BATCH_TICKS: int = 100
const MAX_BATCHES: int = 100


class PaidTrace extends RefCounted:
	var party: Party
	var paid_members: Dictionary[int, bool] = {}
	var paid_orders: Dictionary[int, bool] = {}
	var bill: int = 0
	var duplicate_orders: int = 0


	func on_arrived(customer: CustomerAgent) -> void:
		if customer.party != null and customer.party.booking_owned:
			party = customer.party


	func on_paid(customer: CustomerAgent, order: Order, amount: int) -> void:
		if customer.party == null or not customer.party.booking_owned:
			return
		party = customer.party
		if paid_orders.has(order.id):
			duplicate_orders += 1
			return
		paid_orders[order.id] = true
		paid_members[customer.id] = true
		bill += amount


static func run_cli(tree: SceneTree) -> int:
	print("BOOKING SOAK CONFIG ", JSON.stringify({"seeds": range(1, CASES + 1),
		"scope": "forced six-person booking; three real joined starter tables; ordinary service settings",
		"setup": "unsaved fresh Main; move existing tables through shop_move; fixture owner level 2; normal initial stock purchased by Main; accept real offer; explicit next-day morning without simulating prior service",
		"booking_offer_seed": 463316, "slot_minute": SLOT_MINUTE,
		"unchanged": ["arrival gaps", "queue patience", "food patience", "eating duration", "staff", "kitchen", "rush chance"],
		"no_claim": "not proof for every 6–10-person layout or a natural multi-day playthrough"}))
	var totals: Dictionary = {"cases": CASES, "settled": 0, "refunded": 0,
		"no_seat": 0, "seated": 0, "paid_all_six": 0, "fully_served_settled": 0, "errors": 0}
	for seed_value: int in range(1, CASES + 1):
		var row: Dictionary = run_case(tree, seed_value)
		print("BOOKING SOAK CASE ", JSON.stringify(row))
		if row.has("error"):
			totals["errors"] = int(totals["errors"]) + 1
			continue
		for field: String in ["settled", "refunded", "no_seat", "seated", "paid_all_six", "fully_served_settled"]:
			if bool(row[field]):
				totals[field] = int(totals[field]) + 1
	var majority_served: bool = int(totals["fully_served_settled"]) * 2 > CASES
	totals["majority_fully_served_settled"] = majority_served
	print("BOOKING SOAK SUMMARY ", JSON.stringify(totals))
	return 0 if int(totals["errors"]) == 0 and majority_served else 1


static func prepare(tree: SceneTree, seed_value: int, slot_minute: int = SLOT_MINUTE) -> Dictionary:
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", seed_value)
	tree.root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	var fixture: Dictionary = JOINED.prepare(main, tree.root)
	if not String(fixture.get("error", "")).is_empty():
		_free(main)
		return {"error": fixture["error"], "seed": seed_value}
	var booking: GroupBooking = main.get("group_booking") as GroupBooking
	booking.offer["slot_minute"] = slot_minute
	main.call("_refresh_booking_offer")
	var accept: Button = main.get_node("Overlay/MenuPanel/Panel/Content/BookingOffer/Buttons/Accept") as Button
	accept.pressed.emit()
	if not booking.has_active_booking():
		_free(main)
		return {"error": "Real booking acceptance refused", "seed": seed_value}
	Clock.sim.day = int(booking.booking["service_day"])
	main.call("_begin_morning")
	main.call("set_menu_visible", false)
	var starting_stock: Dictionary = {}
	for id: StringName in Economy.stock.ids():
		starting_stock[String(id)] = Economy.stock.count(id)
	var staff: Array[Dictionary] = []
	for member: StaffMember in (main.get("staff_roster") as StaffRoster).members():
		staff.append({"role": String(member.role), "skill": member.skill, "wage": member.wage})
	return {"main": main, "booking": booking, "fixture": fixture, "seed": seed_value,
		"starting_stock": starting_stock, "staff": staff, "owner_mode": main.call("_capture_owner")["mode"]}


static func run_case(tree: SceneTree, seed_value: int) -> Dictionary:
	var prepared: Dictionary = prepare(tree, seed_value)
	if prepared.has("error"):
		return prepared
	var main: Node = prepared["main"]
	var booking: GroupBooking = prepared["booking"]
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var trace: PaidTrace = PaidTrace.new()
	sim.customer_arrived.connect(trace.on_arrived)
	sim.customer_paid.connect(trace.on_paid)
	var id: int = int(booking.booking["booking_id"])
	var deposit: int = int(booking.booking["deposit_amount"])
	if not Clock.sim.start_service():
		_free(main)
		return {"error": "Real service refused to open", "seed": seed_value}
	var batches: int = 0
	while Clock.sim.phase != SimClock.Phase.CLOSED and batches < MAX_BATCHES:
		main.call("run_ticks", BATCH_TICKS)
		batches += 1
	var review: Dictionary = sim.booking_review_results.get(id, {})
	var status: String = String(booking.booking.get("status", ""))
	var book: Dictionary = Economy.ledger.day_totals(Clock.sim.day)
	var applied: int = -int(book.get(Ledger.BOOKING_DEPOSIT, 0))
	var refunded: int = -int(book.get(Ledger.BOOKING_REFUND, 0))
	var paid_all: bool = trace.paid_members.size() == 6
	var seated: bool = trace.party != null and trace.party.seated
	var settled: bool = status == String(GroupBooking.STATUS_SETTLED)
	var rush: Variant = sim.get("rush_hour") if "rush_hour" in sim else null
	var row: Dictionary = {"seed": seed_value, "service_day": Clock.sim.day,
		"slot_minute": SLOT_MINUTE, "occasion": booking.booking.get("occasion", ""),
		"hold_before_minutes": booking.tuning.hold_before_minutes,
		"grace_minutes": booking.tuning.get("reserved_queue_grace_minutes") \
			if "reserved_queue_grace_minutes" in booking.tuning else 0,
		"party_size": 6, "capacity": DiningSeats.largest_usable_capacity(sim.world.grid),
		"guest_seeds": booking.booking.get("guest_seeds", []).duplicate(),
		"starting_stock": prepared["starting_stock"], "staff": prepared["staff"], "owner_mode": prepared["owner_mode"],
		"seated": seated, "paid_members": trace.paid_members.size(), "paid_all_six": paid_all,
		"paid_orders": trace.paid_orders.size(), "duplicate_paid_orders": trace.duplicate_orders,
		"booked_bill": trace.bill, "no_seat": bool(review.get("no_seat", false)),
		"review_stars": int(review.get("stars", 0)), "good_service": bool(review.get("good_service", false)),
		"advance_received": deposit, "advance_applied": applied, "advance_refunded": refunded,
		"terminal_state": status, "settled": settled, "refunded": status == String(GroupBooking.STATUS_REFUNDED),
		"fully_served_settled": settled and seated and paid_all and not bool(review.get("no_seat", false)),
		"all_guests_served": sim.served_today, "all_guests_lost": sim.lost_today,
		"rush": rush.call("to_dict") if rush != null else {}, "tick_batches": batches}
	if Clock.sim.phase != SimClock.Phase.CLOSED or booking.has_active_booking():
		row["error"] = "Service or booking did not reach a terminal state"
	elif applied < 0 or refunded < 0 or applied + refunded != deposit:
		row["error"] = "Advance conservation failed"
	elif trace.duplicate_orders != 0:
		row["error"] = "Duplicate booked payment signal"
	_free(main)
	return row


static func _free(main: Node) -> void:
	main.get_parent().remove_child(main)
	main.free()
	Clock.set_speed(0)
