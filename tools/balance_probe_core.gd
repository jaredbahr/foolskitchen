class_name BalanceProbe
extends RefCounted
## Autoload-aware implementation of the manual balance probe. The SceneTree
## entry waits one frame before loading this script.

const MAX_TICK_BATCHES: int = 30
const TICKS_PER_BATCH: int = 1000
## Six staff, three skills, at most four queued level-ups per skill.
const MAX_MORNING_RAISE_CHOICES: int = 72


## A read-only manual trace. It stores IDs and counts, never the world/board,
## and the caller disconnects its method at the end of each bounded day.
class StaffTrace:
	extends RefCounted
	var _members: Dictionary[int, StringName] = {}
	var _counts: Dictionary[StringName, Dictionary] = {}
	var _earned: Dictionary[StringName, Dictionary] = {}

	func _init(world: SimWorld) -> void:
		for agent: SimAgent in world.agents:
			if agent is StaffAgent and not agent is OwnerAgent:
				_members[agent.id] = (agent as StaffAgent).member_id


	func on_task_completed(task: SimTask) -> void:
		if task == null or task.state != SimTask.State.DONE or not _members.has(task.claimed_by):
			return
		var skill: StringName = StaffRoster.GROWTH_TUNING.skill_for_task(task.kind)
		var amount: int = StaffRoster.GROWTH_TUNING.xp_for_task(task.kind)
		if not StaffGrowth.SKILLS.has(skill) or amount <= 0:
			return
		var member: StringName = _members[task.claimed_by]
		var counts: Dictionary = _counts.get(member, {})
		var earned: Dictionary = _earned.get(member, {})
		counts[skill] = int(counts.get(skill, 0)) + 1
		earned[skill] = int(earned.get(skill, 0)) + amount
		_counts[member] = counts
		_earned[member] = earned


	## Capture after service_closed has applied XP. Zero-task primary skills
	## remain visible so a missing first level-up is explicit in the table.
	func capture(roster: StaffRoster, day: int) -> Array[Dictionary]:
		var rows: Array[Dictionary] = []
		for member: StaffMember in roster.members():
			var growth: StaffGrowth = member.growth_state()
			var counts: Dictionary = _counts.get(member.id, {})
			var earned: Dictionary = _earned.get(member.id, {})
			for skill: StringName in StaffGrowth.SKILLS:
				if skill != StaffMember._primary_skill(member.role) and not counts.has(skill):
					continue
				rows.append({"day": day, "member": member.display_name, "skill": String(skill),
					"tasks": int(counts.get(skill, 0)), "earned": int(earned.get(skill, 0)),
					"level": growth.skill_level(skill), "xp": growth.progress_xp(skill),
					"pending": growth.pending_raise_count(), "mood": growth.mood, "wage": member.wage})
		return rows


static func run_cli(tree: SceneTree, args: PackedStringArray) -> int:
	var options: Dictionary = _parse_args(args)
	if options.has("error"):
		printerr(options["error"])
		return 2
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Godot: %s" % str(Engine.get_version_info().get("string", "unknown")))
	lines.append("Git SHA: %s" % _git_sha())
	lines.append("| Set-up | Seed | Arrivals | Served | Lost (top 2 reasons) | Sales | Wages | Rent | Ingredients | Profit | Ending cash | Owner XP | Final level | Level days | Out of stock |")
	lines.append("|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|")
	var staff_lines: PackedStringArray = PackedStringArray()
	var summary_lines: PackedStringArray = PackedStringArray()
	var failed: bool = false
	var observe_staff: bool = options["staff_growth"] or options["auto_accept_raises"]
	if observe_staff:
		staff_lines.append("\nStaff growth at service close (%s):" % (
			"all morning requests accepted through Main" if options["auto_accept_raises"]
			else "raises left pending; no automatic choices"))
		staff_lines.append("| Set-up | Seed | Day | Member | Job | Completed | Earned XP | Skill | XP left | Pending requests | Mood | Wage |")
		staff_lines.append("|---|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---:|")
		summary_lines.append("\nPer-seed staff skill-up days and final wages:")
		summary_lines.append("| Set-up | Seed | Member | Job | Skill-up days | Final skill | Final wage |")
		summary_lines.append("|---|---:|---|---|---|---:|---:|")
	var setups: Array[String] = []
	for name: Variant in options["setups"]:
		setups.append(String(name))
	var seeds: Array[int] = []
	for value: Variant in options["seeds"]:
		seeds.append(int(value))
	for setup_name: String in setups:
		var combined: Dictionary = _empty_stats()
		var completed: int = 0
		for seed_value: int in seeds:
			var row: Dictionary = run_case(tree, seed_value, setup_name, options["days"],
				options["extra_cook_skill"], options["gap"], options["price"], options["staff_growth"],
				options["auto_accept_raises"], options["daily"])
			if row.has("error"):
				printerr("%s, seed %d: %s" % [setup_name, seed_value, row["error"]])
				if not options["daily"]:
					return 2
				failed = true
				print("PROBE_CASE ", JSON.stringify({"setup": setup_name, "seed": seed_value,
					"days": options["days"], "error": row["error"]}))
				lines.append("| %s | %d | FAILED: %s |" % [setup_name, seed_value, row["error"]])
				continue
			completed += 1
			if options["daily"]:
				print("PROBE_CASE ", JSON.stringify({"setup": setup_name, "seed": seed_value,
					"days": options["days"], "stats": row}))
			lines.append(_format_row(setup_name, str(seed_value), row, 1))
			if observe_staff:
				for staff_row: Dictionary in row["staff_growth"]:
					staff_lines.append(_format_staff_row(setup_name, seed_value, staff_row))
				for summary: Dictionary in row["staff_summary"]:
					summary_lines.append(_format_staff_summary(setup_name, seed_value, summary))
			_add_stats(combined, row)
		if completed == seeds.size():
			lines.append(_format_row(setup_name, "mean", combined, seeds.size()))
		else:
			lines.append("| %s | mean | UNAVAILABLE: %d/%d cases completed |" % [
				setup_name, completed, seeds.size()])
	lines.append_array(staff_lines)
	lines.append_array(summary_lines)
	print("\n".join(lines))
	return 2 if failed else 0


## Runs the production Main scene with saving disabled, like the multi-day
## invariant test. Returned values cover the requested days; cash is the ending balance.
static func run_case(tree: SceneTree, seed_value: int, setup_name: String, days: int,
		extra_cook_skill: int = 3, gap: Vector2i = Vector2i(-1, -1),
		price: float = 1.0, trace_staff_growth: bool = false,
		auto_accept_raises: bool = false, observe_daily: bool = false,
		capture_control: bool = false) -> Dictionary:
	if tree == null or days < 1 or not ProbeSetups.names().has(setup_name):
		return {"error": "Invalid probe case"}
	var scene: PackedScene = load("res://src/world/main.tscn") as PackedScene
	if scene == null:
		return {"error": "The game scene did not load"}
	var main: Node = scene.instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", seed_value)
	tree.root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null:
		_free_main(main)
		return {"error": "The game session did not start"}
	# Main prepared the real morning, including stock, with the probe seed.
	# Reset before the first gap so each independent case starts identically.
	GameState.new_run(seed_value)
	sim.use_rng(GameState.rng(&"customers"))
	# new_run replaced the RNG objects Main had bound; rebind the reviews too.
	sim.configure_reviews(sim.review_book, sim.review_tuning, sim.review_quotes,
		GameState.rng(&"reviews"))
	if gap.x > 0:
		sim.spawner.min_gap = gap.x
		sim.spawner.max_gap = gap.y
	if price != 1.0:
		for recipe: RecipeDef in sim.menu:
			sim.prices[recipe.id] = maxi(0, roundi(recipe.standard_price * price))
	if not ProbeSetups.apply(setup_name, main, extra_cook_skill):
		_free_main(main)
		return {"error": "Cannot apply the requested set-up"}
	sim.start_day()
	var totals: Dictionary = _empty_stats()
	if observe_daily:
		totals["daily"] = []
	var observe_staff: bool = trace_staff_growth or auto_accept_raises
	var staff_level_ups: Array[Dictionary] = []
	var accepted_requests: int = 0
	if observe_staff:
		totals["staff_growth"] = []
	for day_index: int in range(days):
		if day_index > 0 and not ProbeSetups.morning(setup_name, main):
			_free_main(main)
			return {"error": "The set-up's morning failed on day %d" % (day_index + 1)}
		if auto_accept_raises:
			var choices: Dictionary = _accept_morning_raises(main)
			if choices.has("error"):
				_free_main(main)
				return choices
			accepted_requests += int(choices["accepted"])
		var starting_levels: Dictionary = _staff_levels(main.get("staff_roster") as StaffRoster) \
			if observe_staff else {}
		if not Clock.sim.start_service():
			_free_main(main)
			return {"error": "The shop did not open on day %d" % (day_index + 1)}
		var staff_trace: StaffTrace = null
		if observe_staff:
			staff_trace = StaffTrace.new(sim.world)
			sim.world.board.task_completed.connect(staff_trace.on_task_completed)
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < MAX_TICK_BATCHES:
			main.call("run_ticks", TICKS_PER_BATCH)
			batches += 1
		if staff_trace != null:
			sim.world.board.task_completed.disconnect(staff_trace.on_task_completed)
		if Clock.sim.phase != SimClock.Phase.CLOSED:
			_free_main(main)
			return {"error": "The shop did not close on day %d" % (day_index + 1)}
		if staff_trace != null:
			var staff_rows: Array = totals["staff_growth"]
			staff_rows.append_array(staff_trace.capture(main.get("staff_roster") as StaffRoster, Clock.sim.day))
			staff_level_ups.append_array(_staff_level_ups(starting_levels,
				main.get("staff_roster") as StaffRoster, Clock.sim.day))
		var report: DayReport = main.get("shown_report") as DayReport
		if report == null:
			_free_main(main)
			return {"error": "No evening report on day %d" % (day_index + 1)}
		var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
		if progress == null:
			_free_main(main)
			return {"error": "Owner progression was not installed"}
		totals["owner_xp"] = progress.total_xp
		totals["owner_level"] = progress.level
		var level_days: Dictionary = totals["level_days"]
		for reached: int in range(2, mini(progress.level, 6) + 1):
			if not level_days.has(reached):
				level_days[reached] = day_index + 1
		totals["level_days"] = level_days
		var book: Dictionary = Economy.ledger.day_totals(report.day)
		totals["arrivals"] = int(totals["arrivals"]) + sim.served_today + sim.lost_today
		totals["served"] = int(totals["served"]) + report.customers_served
		totals["lost"] = int(totals["lost"]) + report.customers_lost
		totals["sales"] = int(totals["sales"]) + int(book.get(Ledger.SALE, 0))
		totals["wages"] = int(totals["wages"]) - int(book.get(Ledger.WAGES, 0))
		totals["rent"] = int(totals["rent"]) - int(book.get(Ledger.RENT, 0))
		totals["ingredients"] = int(totals["ingredients"]) - int(book.get(Ledger.INGREDIENTS, 0))
		totals["profit"] = int(totals["profit"]) + Economy.ledger.day_profit(report.day)
		var reasons: Dictionary = totals["reasons"]
		for reason: StringName in sim.leave_reasons_today:
			if reason != &"happy":
				reasons[reason] = int(reasons.get(reason, 0)) + sim.leave_reasons_today[reason]
		totals["reasons"] = reasons
		totals["cash"] = Economy.cash
		# Observe settled books before the next morning expires stock or prunes
		# terminal orders. No stock operation, RNG lookup or planner runs here.
		if observe_daily:
			var before: Dictionary = _control_snapshot(main, sim) if capture_control else {}
			var daily: Dictionary = _daily_snapshot(sim, report, book)
			if capture_control and before != _control_snapshot(main, sim):
				_free_main(main)
				return {"error": "Daily observer changed session state on day %d" % report.day}
			if daily.has("error"):
				_free_main(main)
				return daily
			var daily_rows: Array = totals["daily"]
			daily_rows.append(daily)
		if day_index + 1 < days and not Clock.sim.next_day():
			_free_main(main)
			return {"error": "The next morning did not start"}
	if observe_staff:
		totals["staff_level_ups"] = staff_level_ups
		totals["staff_summary"] = _staff_summary(main.get("staff_roster") as StaffRoster, staff_level_ups)
		totals["accepted_requests"] = accepted_requests
	if capture_control:
		totals["control_state"] = _control_snapshot(main, sim)
	_free_main(main)
	return totals


## Hand-run evidence only. Missing basis remains null instead of presenting
## a legacy report's zero defaults as a measured cost or profit.
static func _daily_snapshot(sim: RestaurantSim, report: DayReport,
		book: Dictionary) -> Dictionary:
	var categories: Dictionary = {}
	var signed_sum: int = 0
	for category: Variant in book:
		categories[String(category)] = int(book[category])
		signed_sum += int(book[category])
	var cash_change: int = Economy.ledger.day_profit(report.day)
	if signed_sum != cash_change or report.profit() != cash_change:
		return {"error": "Cash accounting differs on day %d" % report.day}
	var orders: Array[Dictionary] = _order_snapshot(sim)
	var sold_cost: int = 0
	var sold_recorded: bool = true
	var paid_count: int = 0
	for order: Dictionary in orders:
		if order["paid"]:
			paid_count += 1
			sold_cost += int(order["ingredient_cost"])
			sold_recorded = sold_recorded and bool(order["ingredient_cost_recorded"])
	if report.stock_values_recorded and (report.food_cost != sold_cost \
			or report.food_cost_recorded != sold_recorded):
		return {"error": "Sold-order ingredient cost differs on day %d" % report.day}
	var op_recorded: bool = report.operating_profit_recorded()
	return {"day": report.day, "arrivals": sim.served_today + sim.lost_today,
		"served": report.customers_served, "lost": report.customers_lost,
		"ledger_categories": categories, "ledger_cash_profit": cash_change,
		"cash": Economy.cash, "report_cash_change": report.profit(),
		"purchase_based_operating_profit": report.purchase_basis_operating_profit(),
		"consumed_food_operating_profit": report.operating_profit() if op_recorded else null,
		"consumed_food_status": "recorded" if op_recorded else "not recorded",
		"operating_profit_recorded": op_recorded,
		"stock_values_recorded": report.stock_values_recorded,
		"sold_food_purchase_cost": report.food_cost if report.food_cost_recorded else null,
		"food_cost_recorded": report.food_cost_recorded,
		"stock_bought_today": report.stock_bought if report.stock_bought_recorded else null,
		"stock_bought_recorded": report.stock_bought_recorded,
		"spoilage_purchase_value": report.spoiled_stock if report.spoiled_stock_recorded else null,
		"spoiled_stock_recorded": report.spoiled_stock_recorded,
		"closing_inventory_purchase_value": report.stock_on_hand if report.stock_on_hand_recorded else null,
		"stock_on_hand_recorded": report.stock_on_hand_recorded,
		"paid_order_count": paid_count,
		"paid_order_cost_sum": sold_cost if sold_recorded else null,
		"paid_order_cost_recorded": sold_recorded,
		"orders": orders, "report": report.to_dict().duplicate(true),
		"stock": Economy.stock.to_dict().duplicate(true)}


static func _order_snapshot(sim: RestaurantSim) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING,
			Order.State.READY, Order.State.DELIVERED, Order.State.CANCELLED]:
		for order: Order in sim.orders.orders_in_state(state):
			rows.append({"id": order.id, "recipe": String(order.recipe_id),
				"customer": order.customer_id, "table": order.table_item_id,
				"seat": [order.seat_cell.x, order.seat_cell.y], "price": order.price,
				"placed_tick": order.placed_tick, "state": int(order.state),
				"paid": order.paid, "ingredient_cost": order.ingredient_cost,
				"ingredient_cost_recorded": order.ingredient_cost_recorded})
	return rows


## Existing named streams are captured, never looked up through rng(), which
## could lazily create one. Returned data has no live session references.
static func _control_snapshot(main: Node, sim: RestaurantSim) -> Dictionary:
	var result: Dictionary = {"rng": GameState._capture_save(), "clock": Clock._capture_save(),
		"economy": Economy._capture_save(), "world_tick": sim.world.now,
		"events": sim.world.event_log.duplicate(), "reputation": sim.review_book.to_dict(),
		"served": sim.served_today, "lost": sim.lost_today,
		"reasons": sim.leave_reasons_today.duplicate(true), "orders": _order_snapshot(sim)}
	for key: String in ["staff_roster", "menu_settings", "owner_progress", "regulars", "milestones"]:
		var value: Variant = main.get(key)
		if value is Object and value.has_method("to_dict"):
			result[key] = value.call("to_dict")
	var report: DayReport = main.get("shown_report") as DayReport
	if report != null:
		result["report"] = report.to_dict()
	return result.duplicate(true)


## Manual controls only, on the same real session driver used by the probe.
## A fixture overlay may supply grown; the shipped 13-setup list is unchanged.
static func run_observer_controls(tree: SceneTree) -> int:
	var checks: Array[Dictionary] = []
	var valid: bool = true
	var second_setup: String = "grown" if ProbeSetups.names().has("grown") else "fryer_coffee"
	for setup: String in ["default", second_setup]:
		for seed_value: int in [1, 5]:
			var plain: Dictionary = run_case(tree, seed_value, setup, 5,
				3, Vector2i(-1, -1), 1.0, false, false, false, true)
			var observed: Dictionary = run_case(tree, seed_value, setup, 5,
				3, Vector2i(-1, -1), 1.0, false, false, true, true)
			var days: Variant = observed.get("daily", [])
			var detached: bool = false
			if days is Array and days.size() == 5:
				var independent: Dictionary = (days[0] as Dictionary).duplicate(true)
				var prior: String = JSON.stringify(days)
				(independent["ledger_categories"] as Dictionary)["observer_copy_test"] = 1
				(independent["report"] as Dictionary)["food_cost"] = -1
				(independent["stock"] as Dictionary).clear()
				detached = JSON.stringify(days) == prior
			observed.erase("daily")
			var equal: bool = not plain.has("error") and not observed.has("error") \
				and plain == observed and detached
			checks.append({"setup": setup, "seed": seed_value, "days": 5,
				"equal": equal, "detached": detached, "plain": plain, "observed": observed})
			valid = valid and equal
	print("PROBE_OBSERVER_CONTROL ", JSON.stringify({"source": _git_sha(),
		"checks": checks, "passed": valid}))
	return 0 if valid else 1


## Manual probe policy only. Every request, including a no-pay acknowledgement,
## goes through Main so roster replacement and live wages match a player choice.
static func _accept_morning_raises(main: Node) -> Dictionary:
	if main == null or not main.has_method("staff_accept_raise") \
			or Clock.sim.phase != SimClock.Phase.MORNING:
		return {"error": "Automatic raises require a live morning Main session"}
	var accepted: int = 0
	for _index: int in range(MAX_MORNING_RAISE_CHOICES + 1):
		var roster: StaffRoster = main.get("staff_roster") as StaffRoster
		if roster == null:
			return {"error": "The morning staff roster is missing"}
		var offers: Array[Dictionary] = roster.morning_raise_offers(Clock.sim.day, Clock.sim.phase)
		if offers.is_empty():
			return {"accepted": accepted}
		if accepted == MAX_MORNING_RAISE_CHOICES:
			return {"error": "Morning raise requests exceeded the saved queue bound"}
		if not bool(main.call("staff_accept_raise", StringName(offers[0]["member_id"]))):
			return {"error": "Main refused an automatic morning raise"}
		accepted += 1
	return {"error": "Morning raise requests did not settle"}


static func _staff_levels(roster: StaffRoster) -> Dictionary:
	var levels: Dictionary = {}
	for member: StaffMember in roster.members():
		var skills: Dictionary = {}
		for skill: StringName in StaffGrowth.SKILLS:
			skills[skill] = member.growth_state().skill_level(skill)
		levels[member.id] = skills
	return levels


static func _staff_level_ups(before: Dictionary, roster: StaffRoster, day: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for member: StaffMember in roster.members():
		if not before.has(member.id):
			continue
		var skills: Dictionary = before[member.id]
		for skill: StringName in StaffGrowth.SKILLS:
			for level: int in range(int(skills[skill]) + 1, member.growth_state().skill_level(skill) + 1):
				events.append({"member_id": member.id, "member": member.display_name,
					"skill": skill, "level": level, "day": day})
	return events


static func _staff_summary(roster: StaffRoster, events: Array[Dictionary]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for member: StaffMember in roster.members():
		for skill: StringName in StaffGrowth.SKILLS:
			var days: Array[Dictionary] = []
			for event: Dictionary in events:
				if event["member_id"] == member.id and event["skill"] == skill:
					days.append({"level": int(event["level"]), "day": int(event["day"])})
			if days.is_empty() and skill != StaffMember._primary_skill(member.role):
				continue
			rows.append({"member": member.display_name, "skill": String(skill), "days": days,
				"level": member.growth_state().skill_level(skill), "wage": member.wage})
	return rows


static func _format_staff_summary(setup_name: String, seed_value: int, row: Dictionary) -> String:
	var days: PackedStringArray = PackedStringArray()
	for reached: Dictionary in row["days"]:
		days.append("L%d: day %d" % [reached["level"], reached["day"]])
	return "| %s | %d | %s | %s | %s | %d | %d |" % [setup_name, seed_value,
		row["member"], String(row["skill"]).capitalize(), ", ".join(days) if not days.is_empty()
		else "No skill-up", row["level"], row["wage"]]


static func _empty_stats() -> Dictionary:
	return {"arrivals": 0, "served": 0, "lost": 0, "sales": 0,
		"wages": 0, "rent": 0, "ingredients": 0, "profit": 0,
		"cash": 0, "reasons": {}, "owner_xp": 0, "owner_level": 0,
		"level_days": {}}


static func _format_staff_row(setup_name: String, seed_value: int, row: Dictionary) -> String:
	return "| %s | %d | %d | %s | %s | %d | %d | %d | %d | %d | %d | %d |" % [
		setup_name, seed_value, row["day"], row["member"], String(row["skill"]).capitalize(),
		row["tasks"], row["earned"], row["level"], row["xp"], row["pending"], row["mood"], row["wage"]]


static func _add_stats(target: Dictionary, source: Dictionary) -> void:
	for key: String in ["arrivals", "served", "lost", "sales", "wages", "rent",
			"ingredients", "profit", "cash", "owner_xp", "owner_level"]:
		target[key] = int(target[key]) + int(source[key])
	var reasons: Dictionary = target["reasons"]
	var source_reasons: Dictionary = source["reasons"]
	for reason: StringName in source_reasons:
		reasons[reason] = int(reasons.get(reason, 0)) + int(source_reasons[reason])
	target["reasons"] = reasons


static func _format_row(setup_name: String, seed_label: String, stats: Dictionary,
		divisor: int) -> String:
	return "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [
		setup_name, seed_label, _number(int(stats["arrivals"]), divisor),
		_number(int(stats["served"]), divisor), _lost_text(stats, divisor),
		_number(int(stats["sales"]), divisor), _number(int(stats["wages"]), divisor),
		_number(int(stats["rent"]), divisor), _number(int(stats["ingredients"]), divisor),
		_number(int(stats["profit"]), divisor), _number(int(stats["cash"]), divisor),
		_number(int(stats["owner_xp"]), divisor), _number(int(stats["owner_level"]), divisor),
		_level_days_text(stats) if divisor == 1 else "see seeds",
		_number(int((stats["reasons"] as Dictionary).get(&"out_of_stock", 0)), divisor)]


static func _level_days_text(stats: Dictionary) -> String:
	var days: Dictionary = stats["level_days"]
	var labels: Array[String] = []
	for level: int in [2, 3, 6]:
		labels.append("L%d: day %d" % [level, int(days[level])] if days.has(level) else "L%d: pending" % level)
	return ", ".join(labels)


static func _number(value: int, divisor: int) -> String:
	return str(value) if divisor == 1 else "%.1f" % (float(value) / float(divisor))


static func _lost_text(stats: Dictionary, divisor: int) -> String:
	var amount: String = _number(int(stats["lost"]), divisor)
	var reasons: Dictionary = stats["reasons"]
	var remaining: Array[String] = []
	for reason: StringName in reasons:
		if int(reasons[reason]) > 0:
			remaining.append(String(reason))
	remaining.sort()
	var leading: PackedStringArray = PackedStringArray()
	for index: int in range(mini(2, remaining.size())):
		var best: String = ""
		var best_count: int = -1
		for reason: String in remaining:
			var count: int = int(reasons[StringName(reason)])
			if count > best_count:
				best = reason
				best_count = count
		leading.append("%s %s" % [best.replace("_", " "), _number(best_count, divisor)])
		remaining.erase(best)
	return amount if leading.is_empty() else "%s (%s)" % [amount, ", ".join(leading)]


static func _parse_args(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {
		"days": 5, "seeds": [1], "setups": ["default"],
		"gap": Vector2i(-1, -1), "price": 1.0, "extra_cook_skill": 3,
		"staff_growth": false,
		"auto_accept_raises": false,
		"daily": false,
	}
	var explicit_setup: bool = false
	var legacy_extra: bool = false
	var index: int = 0
	while index < args.size():
		var argument: String = args[index]
		var separator: int = argument.find("=")
		var key: String = argument.substr(0, separator) if separator >= 0 else argument
		var value: String = argument.substr(separator + 1) if separator >= 0 else ""
		if separator < 0:
			index += 1
			if index >= args.size():
				return {"error": "%s needs a value" % key}
			value = args[index]
		match key:
			"--daily":
				if value != "true" and value != "false":
					return {"error": "--daily must be true or false"}
				options["daily"] = value == "true"
			"--auto-accept-raises":
				if value != "true" and value != "false":
					return {"error": "--auto-accept-raises must be true or false"}
				options["auto_accept_raises"] = value == "true"
			"--staff-growth":
				if value != "true" and value != "false":
					return {"error": "--staff-growth must be true or false"}
				options["staff_growth"] = value == "true"
			"--days":
				if not value.is_valid_int() or int(value) < 1:
					return {"error": "--days must be a positive integer"}
				options["days"] = int(value)
			"--seed", "--seeds":
				var seeds: Array[int] = []
				for part: String in value.split(",", false):
					if not part.is_valid_int():
						return {"error": "--seeds needs comma-separated integers"}
					seeds.append(int(part))
				if seeds.is_empty():
					return {"error": "--seeds needs at least one seed"}
				options["seeds"] = seeds
			"--setup":
				var setups: Array[String] = []
				for part: String in value.split(",", false):
					if not ProbeSetups.names().has(part) or setups.has(part):
						return {"error": "Unknown or repeated set-up: %s" % part}
					setups.append(part)
				if setups.is_empty():
					return {"error": "--setup needs at least one set-up"}
				options["setups"] = setups
				explicit_setup = true
			"--extra-cook":
				if not value.is_valid_int() or int(value) < 1 or int(value) > 5:
					return {"error": "--extra-cook must be a skill from 1 to 5"}
				options["extra_cook_skill"] = int(value)
				options["setups"] = ["extra_cook"]
				legacy_extra = true
			"--gap":
				var pair: PackedStringArray = value.split(",", false)
				if pair.size() != 2 or not pair[0].is_valid_int() or not pair[1].is_valid_int():
					return {"error": "--gap needs min,max integers"}
				var minimum: int = int(pair[0])
				var maximum: int = int(pair[1])
				if minimum < 1 or maximum < minimum:
					return {"error": "--gap needs 1 <= min <= max"}
				options["gap"] = Vector2i(minimum, maximum)
			"--price":
				if not value.is_valid_float() or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 10.0:
					return {"error": "--price must be between 0 and 10"}
				options["price"] = float(value)
			_:
				return {"error": "Unknown option: %s" % key}
		index += 1
	if explicit_setup and legacy_extra:
		return {"error": "Use --setup extra_cook or --extra-cook, not both"}
	return options


static func _git_sha() -> String:
	var supplied: String = OS.get_environment("FK_PROBE_SHA").strip_edges()
	if not supplied.is_empty():
		return supplied
	var output: Array = []
	var status: int = OS.execute("git", PackedStringArray(["rev-parse", "HEAD"]), output, true)
	return String(output[0]).strip_edges() if status == 0 and not output.is_empty() else "unknown"


static func _free_main(main: Node) -> void:
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()
