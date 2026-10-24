class_name BalanceProbe
extends RefCounted
## Autoload-aware implementation of the manual balance probe. The SceneTree
## entry waits one frame before loading this script.

const MAX_TICK_BATCHES: int = 30
const TICKS_PER_BATCH: int = 1000


static func run_cli(tree: SceneTree, args: PackedStringArray) -> int:
	var options: Dictionary = _parse_args(args)
	if options.has("error"):
		printerr(options["error"])
		return 2
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Godot: %s" % str(Engine.get_version_info().get("string", "unknown")))
	lines.append("Git SHA: %s" % _git_sha())
	lines.append("| Set-up | Seed | Arrivals | Served | Lost (top 2 reasons) | Sales | Wages | Rent | Ingredients | Profit | Ending cash |")
	lines.append("|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|")
	var setups: Array[String] = []
	for name: Variant in options["setups"]:
		setups.append(String(name))
	var seeds: Array[int] = []
	for value: Variant in options["seeds"]:
		seeds.append(int(value))
	for setup_name: String in setups:
		var combined: Dictionary = _empty_stats()
		for seed_value: int in seeds:
			var row: Dictionary = run_case(tree, seed_value, setup_name, options["days"],
				options["extra_cook_skill"], options["gap"], options["price"])
			if row.has("error"):
				printerr("%s, seed %d: %s" % [setup_name, seed_value, row["error"]])
				return 2
			lines.append(_format_row(setup_name, str(seed_value), row, 1))
			_add_stats(combined, row)
		lines.append(_format_row(setup_name, "mean", combined, seeds.size()))
	print("\n".join(lines))
	return 0


## Runs the production Main scene with saving disabled, like the multi-day
## invariant test. Returned values are five-day totals except ending cash.
static func run_case(tree: SceneTree, seed_value: int, setup_name: String, days: int,
		extra_cook_skill: int = 3, gap: Vector2i = Vector2i(-1, -1),
		price: float = 1.0) -> Dictionary:
	if tree == null or days < 1 or not ProbeSetups.names().has(setup_name):
		return {"error": "Invalid probe case"}
	var scene: PackedScene = load("res://src/world/main.tscn") as PackedScene
	if scene == null:
		return {"error": "The game scene did not load"}
	var main: Node = scene.instantiate()
	main.set("use_saves", false)
	tree.root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null:
		_free_main(main)
		return {"error": "The game session did not start"}
	# Main has prepared the real morning, including stock, before this override.
	# Reset the customer stream and first gap for this independent seed.
	GameState.new_run(seed_value)
	sim.use_rng(GameState.rng(&"customers"))
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
	for day_index: int in range(days):
		if not Clock.sim.start_service():
			_free_main(main)
			return {"error": "The shop did not open on day %d" % (day_index + 1)}
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < MAX_TICK_BATCHES:
			main.call("run_ticks", TICKS_PER_BATCH)
			batches += 1
		if Clock.sim.phase != SimClock.Phase.CLOSED:
			_free_main(main)
			return {"error": "The shop did not close on day %d" % (day_index + 1)}
		var report: DayReport = main.get("shown_report") as DayReport
		if report == null:
			_free_main(main)
			return {"error": "No evening report on day %d" % (day_index + 1)}
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
		if day_index + 1 < days and not Clock.sim.next_day():
			_free_main(main)
			return {"error": "The next morning did not start"}
	_free_main(main)
	return totals


static func _empty_stats() -> Dictionary:
	return {"arrivals": 0, "served": 0, "lost": 0, "sales": 0,
		"wages": 0, "rent": 0, "ingredients": 0, "profit": 0,
		"cash": 0, "reasons": {}}


static func _add_stats(target: Dictionary, source: Dictionary) -> void:
	for key: String in ["arrivals", "served", "lost", "sales", "wages", "rent",
			"ingredients", "profit", "cash"]:
		target[key] = int(target[key]) + int(source[key])
	var reasons: Dictionary = target["reasons"]
	var source_reasons: Dictionary = source["reasons"]
	for reason: StringName in source_reasons:
		reasons[reason] = int(reasons.get(reason, 0)) + int(source_reasons[reason])
	target["reasons"] = reasons


static func _format_row(setup_name: String, seed_label: String, stats: Dictionary,
		divisor: int) -> String:
	return "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [
		setup_name, seed_label, _number(int(stats["arrivals"]), divisor),
		_number(int(stats["served"]), divisor), _lost_text(stats, divisor),
		_number(int(stats["sales"]), divisor), _number(int(stats["wages"]), divisor),
		_number(int(stats["rent"]), divisor), _number(int(stats["ingredients"]), divisor),
		_number(int(stats["profit"]), divisor), _number(int(stats["cash"]), divisor)]


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
