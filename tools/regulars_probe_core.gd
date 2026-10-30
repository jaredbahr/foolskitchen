extends RefCounted
## Compares the production café with/without named regulars, same seeds and
## authored thresholds. Equipment is the existing coffee_shop probe fixture;
## stock/operating costs are paid normally. Morning raise requests are accepted.


static func run(tree: SceneTree, args: PackedStringArray) -> int:
	var seeds: PackedStringArray = ["1", "3"]
	if not args.is_empty():
		seeds = args[0].split(",")
	print("25 days; coffee_shop; ordinary authored promotion gates; morning raises accepted; equipment free as in ProbeSetups")
	print("| Seed | Named regulars | Days | Cast / active | Visits | New | Left | Served | Tips |")
	print("|---|---|---|---|---:|---:|---:|---:|---:|")
	for seed_text: String in seeds:
		if not seed_text.is_valid_int():
			return 2
		for enabled: bool in [false, true]:
			if not _case(tree, seed_text.to_int(), enabled):
				return 1
	return 0


static func _case(tree: SceneTree, seed_value: int, enabled: bool) -> bool:
	var scene: PackedScene = load("res://src/world/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", seed_value)
	tree.root.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	GameState.new_run(seed_value)
	sim.use_rng(GameState.rng(&"customers"))
	sim.configure_reviews(sim.review_book, sim.review_tuning, sim.review_quotes, GameState.rng(&"reviews"))
	if not enabled:
		sim.regulars = null
	if not ProbeSetups.apply("coffee_shop", main):
		_free(main)
		return false
	sim.start_day()
	var served: int = 0
	var tips: int = 0
	var visits: int = 0
	var promoted: int = 0
	var left: int = 0
	for day: int in range(1, 26):
		if not ProbeSetups.morning("coffee_shop", main) \
				or BalanceProbe._accept_morning_raises(main).has("error") \
				or not Clock.sim.start_service():
			_free(main)
			return false
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < BalanceProbe.MAX_TICK_BATCHES:
			main.call("run_ticks", BalanceProbe.TICKS_PER_BATCH)
			batches += 1
		if Clock.sim.phase != SimClock.Phase.CLOSED:
			_free(main)
			return false
		served += sim.served_today
		tips += int(Economy.ledger.day_totals(day).get(Ledger.TIP, 0))
		if sim.regulars != null:
			visits += sim.regulars.visited_today.size()
			promoted += sim.regulars.new_today.size()
			left += sim.regulars.left_today.size()
		if day % 5 == 0:
			print("| %d | %s | %d–%d | %d / %d | %d | %d | %d | %d | %d |" % [seed_value,
				"on" if enabled else "off", day - 4, day,
				sim.regulars.profiles.size() if sim.regulars != null else 0,
				sim.regulars.active_count() if sim.regulars != null else 0,
				visits, promoted, left, served, tips])
			served = 0
			tips = 0
			visits = 0
			promoted = 0
			left = 0
		if day < 25 and not Clock.sim.next_day():
			_free(main)
			return false
	_free(main)
	return true


static func _free(main: Node) -> void:
	Clock.set_speed(0)
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()
