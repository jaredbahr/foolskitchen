extends SceneTree
## Plays whole days of the real game session headlessly and prints each day's
## books, for balancing. Nothing is saved. Usage:
##   godot --headless --path . --script tools/balance_probe.gd -- --days=5
##     [--gap=150,400] [--price=1.0] [--seed=1]
## --gap overrides the guest arrival gap (ticks), --price multiplies every
## per-shop price override. Recipe standard prices remain unchanged.

func _initialize() -> void:
	var days := 5
	var gap := Vector2i(-1, -1)
	var price := 1.0
	var seed_value := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = int(arg.trim_prefix("--days="))
		elif arg.begins_with("--gap="):
			var p := arg.trim_prefix("--gap=").split(",")
			gap = Vector2i(int(p[0]), int(p[1]))
		elif arg.begins_with("--price="):
			price = float(arg.trim_prefix("--price="))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
	var main: Node = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", false)
	root.add_child(main)
	main.call("start")
	root.get_node("GameState").call("new_run", seed_value)
	var sim: RestaurantSim = main.get("sim")
	sim.use_rng(root.get_node("GameState").call("rng", &"customers"))
	if gap.x > 0:
		sim.spawner.min_gap = gap.x
		sim.spawner.max_gap = gap.y
	if price != 1.0:
		for recipe: RecipeDef in sim.menu:
			sim.prices[recipe.id] = maxi(0, roundi(recipe.standard_price * price))
	var clock: Node = root.get_node("Clock")
	var economy: Node = root.get_node("Economy")
	var total := 0
	for d in days:
		sim.start_day()
		(clock.get("sim") as SimClock).start_service()
		for i in 40:
			main.call("run_ticks", 500)
			if (clock.get("sim") as SimClock).phase == SimClock.Phase.CLOSED:
				break
		var r: DayReport = main.get("shown_report")
		total += r.profit()
		print("PROBE day=%d served=%d lost=%d income=%d costs=%d profit=%d cash=%d reasons=%s dishes=%s" % [
			r.day, r.customers_served, r.customers_lost, r.total_income(), r.total_costs(), r.profit(),
			economy.get("cash"), r.leave_reasons, r.dishes_sold])
		(clock.get("sim") as SimClock).next_day()
	print("PROBE total_profit=%d over %d days" % [total, days])
	quit()
