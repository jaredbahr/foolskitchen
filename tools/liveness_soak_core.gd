class_name LivenessSoak
extends RefCounted
## Hand-run movement liveness soak (#306). Plays real production days headless,
## like the balance probe, and watches every admitted person each service
## tick. Someone who wants to move (a remaining path, a yield, a stop, a guest
## leaving or walking to a seat) but whose cell and edge progress do not change
## for longer than --limit ticks is reported once per episode with a full dump:
## every person, their movement state and an ASCII map of the shop.
## Observation only: it never draws RNG or touches the session, except the
## optional seeded morning edits (--edits true), which use their own stream.

const MAX_TICKS_PER_DAY: int = 30000
const PRESENT_EVERY: int = 1000
const MAX_DUMPS_PER_CASE: int = 3
const EDIT_TRIES: int = 400


static func run_cli(tree: SceneTree, args: PackedStringArray) -> int:
	var options: Dictionary = {"days": 14, "seeds": [1], "setups": ["default"],
		"limit": 600, "edits": false, "dumps": MAX_DUMPS_PER_CASE}
	var index: int = 0
	while index + 1 < args.size():
		var key: String = args[index]
		var value: String = args[index + 1]
		index += 2
		match key:
			"--days":
				options["days"] = int(value)
			"--limit":
				options["limit"] = int(value)
			"--dumps":
				options["dumps"] = int(value)
			"--edits":
				options["edits"] = value == "true"
			"--seeds":
				var seeds: Array = []
				for part: String in value.split(",", false):
					if part.contains("-"):
						var ends: PackedStringArray = part.split("-")
						for s: int in range(int(ends[0]), int(ends[1]) + 1):
							seeds.append(s)
					else:
						seeds.append(int(part))
				options["seeds"] = seeds
			"--setup", "--setups":
				options["setups"] = Array(value.split(",", false))
			_:
				printerr("Unknown option %s" % key)
				return 2
	var failed: bool = false
	for setup_name: Variant in options["setups"]:
		for seed_value: Variant in options["seeds"]:
			var row: Dictionary = run_case(tree, int(seed_value), String(setup_name), int(options["days"]),
				int(options["limit"]), bool(options["edits"]), int(options["dumps"]))
			print("SOAK_CASE ", JSON.stringify(row))
			if row.has("error") or int(row.get("stuck_episodes", 0)) > 0:
				failed = true
	return 1 if failed else 0


static func run_case(tree: SceneTree, seed_value: int, setup_name: String, days: int,
		limit: int, edits: bool, max_dumps: int) -> Dictionary:
	var result: Dictionary = {"setup": setup_name, "seed": seed_value, "days": days, "edits": edits,
		"agent_days": 0, "max_no_progress": 0, "max_goal_wait": 0, "stuck_episodes": 0, "served": 0,
		"lost": 0, "reasons": {}, "edit_actions": 0}
	if not ProbeSetups.names().has(setup_name):
		result["error"] = "unknown setup"
		return result
	var scene: PackedScene = load("res://src/world/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", seed_value)
	tree.root.add_child(main)
	main.call("start")
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	GameState.new_run(seed_value)
	sim.use_rng(GameState.rng(&"customers"))
	sim.configure_reviews(sim.review_book, sim.review_tuning, sim.review_quotes, GameState.rng(&"reviews"))
	if not ProbeSetups.apply(setup_name, main, 3):
		_free(main)
		result["error"] = "setup failed"
		return result
	sim.start_day()
	var edit_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	edit_rng.seed = 7919 * seed_value + 306
	var dumps: int = 0
	var reasons: Dictionary = {}
	for day_index: int in range(days):
		if day_index > 0 and not ProbeSetups.morning(setup_name, main):
			result["error"] = "morning failed day %d" % (day_index + 1)
			break
		if edits:
			result["edit_actions"] = int(result["edit_actions"]) + _edit_morning(main, edit_rng)
		if not Clock.sim.start_service():
			result["error"] = "did not open day %d" % (day_index + 1)
			break
		var world: SimWorld = sim.world
		var last_key: Dictionary = {}
		var still: Dictionary = {}
		var goal_key: Dictionary = {}
		var goal_age: Dictionary = {}
		var dumped: Dictionary = {}
		var seen: Dictionary = {}
		var ticks: int = 0
		while Clock.sim.phase in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS] and ticks < MAX_TICKS_PER_DAY:
			sim.advance()
			EventBus.sim_ticked.emit(Clock.sim.tick)
			ticks += 1
			if ticks % PRESENT_EVERY == 0:
				main.call("refresh_presentation")
			if Clock.sim.phase == SimClock.Phase.CLOSED:
				break
			for agent: SimAgent in world.agents:
				seen[agent.id] = true
				var wants: bool = wants_to_move(world, agent)
				var key: Array = [agent.cell, agent.move_progress]
				if not wants or last_key.get(agent.id, []) != key:
					still[agent.id] = 0
					dumped.erase(agent.id)
				else:
					still[agent.id] = int(still.get(agent.id, 0)) + 1
				last_key[agent.id] = key
				var goal: Array = [agent.destination(), wants]
				if wants and goal_key.get(agent.id, []) == goal:
					goal_age[agent.id] = int(goal_age.get(agent.id, 0)) + 1
				else:
					goal_age[agent.id] = 0
				goal_key[agent.id] = goal
				result["max_goal_wait"] = maxi(int(result["max_goal_wait"]), int(goal_age[agent.id]))
				var count: int = int(still[agent.id])
				if count > int(result["max_no_progress"]):
					result["max_no_progress"] = count
					if count >= 250 and (count == 250 or count % 50 == 0):
						result["worst"] = "day %d tick %d stalled %d: %s" % [Clock.sim.day, Clock.sim.tick,
							count, describe(world, agent)]
				if count > limit and not dumped.has(agent.id):
					dumped[agent.id] = true
					result["stuck_episodes"] = int(result["stuck_episodes"]) + 1
					if dumps < max_dumps:
						dumps += 1
						print(dump(world, agent, "seed=%d setup=%s edits=%s day=%d tick=%d phase=%d" % [
							seed_value, setup_name, edits, Clock.sim.day, Clock.sim.tick, Clock.sim.phase]))
		if Clock.sim.phase != SimClock.Phase.CLOSED:
			result["error"] = "did not close day %d" % (day_index + 1)
			break
		result["agent_days"] = int(result["agent_days"]) + seen.size()
		result["served"] = int(result["served"]) + sim.served_today
		result["lost"] = int(result["lost"]) + sim.lost_today
		for reason: StringName in sim.leave_reasons_today:
			if reason != &"happy":
				reasons[String(reason)] = int(reasons.get(String(reason), 0)) + int(sim.leave_reasons_today[reason])
		if day_index + 1 < days and not Clock.sim.next_day():
			result["error"] = "next morning failed"
			break
	result["reasons"] = reasons
	var counts: Variant = sim.world.movement.get("escape_counts")
	if counts is Dictionary:
		var escapes: Dictionary = {}
		for key: Variant in counts:
			escapes[String(key)] = counts[key]
		result["escapes"] = escapes
	_free(main)
	return result


## Someone who is trying to get somewhere. Seated, working, waiting for a
## station and idle-at-post people are stationary by design.
static func wants_to_move(world: SimWorld, agent: SimAgent) -> bool:
	if world.movement.is_stopping(agent.id) or world.movement.is_yielding(agent.id):
		return true
	if agent is CustomerAgent:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest.state == CustomerAgent.State.LEAVING or guest.state == CustomerAgent.State.WALKING_TO_SEAT:
			return true
	return not agent.has_arrived()


static func describe(world: SimWorld, agent: SimAgent) -> String:
	var kind: String = "staff"
	var state: String = ""
	if agent is OwnerAgent:
		kind = "owner"
	elif agent is CourierAgent:
		kind = "courier"
		state = CourierAgent.State.keys()[(agent as CourierAgent).state]
	elif agent is CustomerAgent:
		var guest: CustomerAgent = agent as CustomerAgent
		kind = "guest"
		state = "%s party=%d seat=%s bench=%d" % [CustomerAgent.State.keys()[guest.state],
			guest.party.size() if guest.party != null else 1, guest.seat_cell, guest.waiting_item_id]
	if agent is StaffAgent:
		var staff: StaffAgent = agent as StaffAgent
		if staff.task == null:
			state = "idle"
		else:
			var step: String = "-"
			if staff.step_index < staff.task.steps.size():
				step = TaskStep.Kind.keys()[staff.task.steps[staff.step_index].kind]
			state = "task=%s step=%d:%s started=%s waiting='%s' food=%s" % [staff.task.label, staff.step_index,
				step, staff._step_started, staff._waiting_for, staff.carries_food()]
	var remaining: Array = agent.path.slice(agent.path_index, agent.path_index + 6)
	return "#%d %s/%s cell=%s prog=%.2f next=%s goal=%s path=%s blockedwaits=%d yielding=%s resume=%s returning=%s stopping=%s last_progress=%d | %s" % [
		agent.id, kind, agent.role, agent.cell, agent.move_progress, agent.next_cell(), agent.destination(),
		remaining, int(world.movement._blocked.get(agent.id, 0)), world.movement.is_yielding(agent.id),
		world.movement._resume.get(agent.id, SimGrid.NO_CELL), world.movement._returning.has(agent.id),
		world.movement.is_stopping(agent.id), agent.last_progress_tick, state]


static func dump(world: SimWorld, stuck: SimAgent, header: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("STUCK_DUMP %s stuck=#%d" % [header, stuck.id])
	for agent: SimAgent in world.agents:
		lines.append("  " + describe(world, agent))
	for pending: SimAgent in world.pending_agents():
		lines.append("  pending #%d %s cell=%s" % [pending.id, pending.role, pending.cell])
	lines.append("  cooperative=%s" % str(world.movement.snapshot()["cooperative"]))
	lines.append_array(ascii_map(world))
	lines.append("END_DUMP")
	return "\n".join(lines)


## '#' wall, 'E' entry, '.' floor, 'x' solid item, 's' seat, ' ' outside.
## People are letters (legend printed) over their cell; '*' marks a next cell.
static func ascii_map(world: SimWorld) -> PackedStringArray:
	var grid: SimGrid = world.grid
	var marks: Dictionary = {}
	var legend: PackedStringArray = PackedStringArray()
	var letters: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	var index: int = 0
	for agent: SimAgent in world.agents:
		var letter: String = letters[index % letters.length()]
		index += 1
		legend.append("%s=#%d" % [letter, agent.id])
		marks[agent.cell] = letter
		if agent.next_cell() != agent.cell and not marks.has(agent.next_cell()):
			marks[agent.next_cell()] = "*"
	var rows: PackedStringArray = PackedStringArray()
	rows.append("  legend: " + " ".join(legend))
	var origin: Vector2i = Vector2i.ZERO
	var cells: Array[Vector2i] = grid.cells()
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c: Vector2i in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	origin = lo
	var header: String = "      "
	for x: int in range(lo.x, hi.x + 1):
		header += str(posmod(x, 10))
	rows.append(header)
	for y: int in range(lo.y, hi.y + 1):
		var row: String = "  %3d " % y
		for x: int in range(lo.x, hi.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if marks.has(cell):
				row += marks[cell]
				continue
			match grid.terrain(cell):
				SimGrid.Terrain.OUTSIDE:
					row += " "
				SimGrid.Terrain.WALL:
					row += "#"
				SimGrid.Terrain.ENTRY:
					row += "E"
				_:
					if not grid.seat_items_at(cell).is_empty():
						row += "s"
					elif not grid.is_walkable(cell):
						row += "x"
					else:
						row += "."
		rows.append(row)
	return rows


## Seeded player edits: a few legal table/decor moves the editor accepts
## without an unreachable warning, plus one kept chair purchase.
static func _edit_morning(main: Node, rng: RandomNumberGenerator) -> int:
	var editor: ShopEditor = main.get("shop_editor")
	var world: SimWorld = main.get("world")
	if editor == null or world == null or not editor.can_edit():
		return 0
	var done: int = 0
	for _round: int in range(3):
		var items: Array[PlacedItem] = []
		for item: PlacedItem in world.grid.items():
			var definition: ItemDef = item.def as ItemDef
			if definition != null and definition.category in [ItemDef.Category.TABLE, ItemDef.Category.DECOR]:
				items.append(item)
		if items.is_empty():
			break
		for _try: int in range(EDIT_TRIES):
			var item: PlacedItem = items[rng.randi_range(0, items.size() - 1)]
			var origin: Vector2i = item.origin + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			var turns: int = rng.randi_range(0, 3)
			if origin == item.origin and turns == item.quarter_turns:
				continue
			var check: EditCheck = editor.check_move(item.id, origin, turns)
			if not check.ok or not check.unreachable.is_empty():
				continue
			if main.call("shop_move", item.id, origin, turns):
				done += 1
				break
	var size: Vector2i = world.grid.size
	for _try: int in range(EDIT_TRIES):
		var origin: Vector2i = Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
		var turns: int = rng.randi_range(0, 3)
		var check: EditCheck = editor.check_buy(&"chair", origin, turns)
		if not check.ok or not check.unreachable.is_empty():
			continue
		if main.call("shop_buy", &"chair", origin, turns):
			done += 1
			break
	return done


static func _free(main: Node) -> void:
	if main.is_inside_tree():
		main.get_parent().remove_child(main)
	main.free()
