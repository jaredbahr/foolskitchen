class_name ProbeSetups
extends RefCounted
## Explicit morning scenarios for the manual balance probe. Add new scenarios
## here so the runner and its output format stay unchanged.


static func names() -> Array[String]:
	return ["default", "extra_cook", "extra_server", "owner_kitchen", "owner_floor",
		"trays_2", "trays_4", "extra_cleaner", "expanded_tables"]


static func apply(name: String, main: Node, extra_cook_skill: int = 3) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null or sim.world.clock.phase != SimClock.Phase.MORNING or not names().has(name) \
			or sim.cleanliness == null \
			or not sim.cleanliness.use_rng(GameState.rng(&"cleanliness")):
		return false
	match name:
		"default":
			return true
		"extra_cook":
			return _add_staff(main, &"cook", extra_cook_skill)
		"extra_server":
			return _add_staff(main, &"server", 3)
		"extra_cleaner":
			return _add_staff(main, &"cleaner", 3)
		"owner_kitchen":
			return sim.assign_owner(&"kitchen")
		"owner_floor":
			return sim.assign_owner(&"floor")
		"trays_2":
			return main.call("tray_buy", 1)
		"trays_4":
			return main.call("tray_buy", 1) and main.call("tray_buy", 2)
		"expanded_tables":
			return _expand_with_tables(main)
	return false


static func _add_staff(main: Node, role: StringName, skill: int) -> bool:
	if skill < 1 or skill > 5:
		return false
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var roster: StaffRoster = main.get("staff_roster") as StaffRoster
	if sim == null or roster == null:
		return false
	var snapshot: Dictionary = roster.to_dict()
	var members: Array = snapshot["members"]
	var member: StaffMember = StaffMember.new()
	member.id = StringName("probe_extra_%s" % String(role))
	member.display_name = "Extra %s" % String(role)
	member.role = role
	member.skill = skill
	member.wage = sim.pricing_tuning.staff_wage(role, skill)
	member.trait_id = &"steady"
	members.append(member.to_dict())
	snapshot["members"] = members
	return roster.from_dict(snapshot) and sim.set_staff_roster(roster.members())


## FK-080: side wings on both sides of the dining room (the east one full
## depth), each with one turned table_2. Built free of charge through an
## editor with open books, so the rows compare the layout itself with
## "default", not the purchase.
static func _expand_with_tables(main: Node) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var content: ContentDB = main.get("content") as ContentDB
	var layout: ShopLayout = load("res://data/layouts/tier1_hole_in_the_wall.tres") as ShopLayout
	var books: ShopEditBooks = ShopEditBooks.new(func(_amount: int) -> bool: return true,
		func(_amount: int, _category: StringName) -> void: pass)
	var editor: ShopEditor = ShopEditor.new(sim, content, books, layout)
	for rect: Rect2i in [Rect2i(14, 0, 1, 10), Rect2i(-1, 5, 1, 5)]:
		var cells: Array[Vector2i] = []
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
		if not editor.apply_floor(cells, true):
			return false
	return editor.buy(&"table_2", Vector2i(13, 6), 1) and editor.buy(&"table_2", Vector2i(-1, 6), 1)

