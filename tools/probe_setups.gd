class_name ProbeSetups
extends RefCounted
## Explicit morning scenarios for the manual balance probe. Add new scenarios
## here so the runner and its output format stay unchanged.


static func names() -> Array[String]:
	return ["default", "extra_cook", "extra_server", "owner_kitchen", "owner_floor",
		"trays_2", "trays_4", "extra_cleaner", "expanded_tables", "coffee_shop", "bar", "fryer_coffee", "joined_tables",
		"grown", "neglected", "curb_appeal"]


static func apply(name: String, main: Node, extra_cook_skill: int = 3) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null or sim.world.clock.phase != SimClock.Phase.MORNING or not names().has(name) \
			or sim.cleanliness == null \
			or not sim.cleanliness.use_rng(GameState.rng(&"cleanliness")):
		return false
	if sim.mishaps != null and not sim.mishaps.use_rng(GameState.rng(&"cleanliness")):
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
		"joined_tables":
			return _joined_tables(main)
		"coffee_shop":
			return _coffee_shop(main)
		"bar":
			return _bar(main)
		"fryer_coffee":
			return _fryer_coffee(main)
		"grown":
			return _grown(main)
		"neglected":
			return _neglected(main)
		"curb_appeal":
			return _curb_appeal(main)
	return false


## Each later morning, before opening: a concept switches on the drinks it
## has newly unlocked (wine at level 2), as a player running it would.
static func morning(name: String, main: Node) -> bool:
	match name:
		"neglected":
			return _neglected(main)
		"coffee_shop":
			return _enable(main, [&"coffee", &"tea", &"croissant"])
		"fryer_coffee":
			return _enable(main, [&"burger", &"grilled_cheese", &"fries", &"coffee"])
		"bar":
			return _enable(main, [&"beer", &"wine", &"soft_drink", &"burger", &"grilled_cheese"])
	return true


## Demand comparison: the existing free expanded layout plus a reachable
## coffee machine and storage, with all five unlocked dishes enabled through
## Main. Construction is free, as in expanded_tables; supplies and daily costs
## are paid normally. No XP, reputation, renown or stock is granted.
static func _grown(main: Node) -> bool:
	if not _expand_with_tables(main):
		return false
	var editor: ShopEditor = _free_editor(main)
	if editor == null or not editor.buy(&"coffee_machine", Vector2i(12, 3), 0) \
			or not _storage_shelves(editor) or not editor.last_check.unreachable.is_empty():
		return false
	main.call("_refresh_menu_catalogue")
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	if settings == null:
		return false
	for id: StringName in [&"burger", &"grilled_cheese", &"tomato_soup", &"coffee", &"tea"]:
		if settings.recipe(id) == null or not main.call("menu_set_enabled", id, true):
			return false
	return settings.enabled_recipes().size() == 5


## Ordinary maximum menu prices, with genuine reviews earned during service.
## Repeating the command each morning also covers later enabled dishes.
static func _neglected(main: Node) -> bool:
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	if settings == null:
		return false
	for recipe: RecipeDef in settings.enabled_recipes():
		if not main.call("menu_set_price", recipe.id, recipe.standard_price * 2):
			return false
	return true


## FK-083 coffee shop: open 07:00-15:00 serving coffee, tea and croissants.
## Two coffee machines behind a four-stool café counter, the two starter
## tables, a round table with two rounded chairs, and café plants and a side
## table (the room reads as a Café), and two storage shelves for the
## supplies (FK-087). Built free of charge (like
## expanded_tables, so level-two pieces too), stocked at the normal price.
static func _coffee_shop(main: Node) -> bool:
	var editor: ShopEditor = _free_editor(main)
	if editor == null or not _clear_east_table(main, editor):
		return false
	for placement: Array in [[&"coffee_machine", Vector2i(9, 5), 2], [&"coffee_machine", Vector2i(10, 5), 2],
			[&"round_table", Vector2i(2, 8), 0], [&"rounded_chair", Vector2i(1, 8), 1],
			[&"rounded_chair", Vector2i(4, 9), 3], [&"plant_small_2", Vector2i(12, 9), 0],
			[&"side_table", Vector2i(11, 5), 2], [&"plant_small_2", Vector2i(12, 5), 0]]:
		if not editor.buy(placement[0], placement[1], placement[2]):
			return false
	if not _counter_with_stools(editor, 9, 12) or not _storage_shelves(editor) \
			or not editor.last_check.unreachable.is_empty():
		return false
	return _finish(main, 7 * 60, 15 * 60, [&"coffee", &"tea", &"croissant"],
		[&"burger", &"grilled_cheese", &"tomato_soup"])


## FK-083 bar: open 16:00-24:00 with beer, wine and soft drinks from a drinks
## shelf and fridge behind a four-stool bar, plus burgers and grilled cheese,
## and two storage shelves (FK-087).
static func _bar(main: Node) -> bool:
	var editor: ShopEditor = _free_editor(main)
	if editor == null or not _clear_east_table(main, editor):
		return false
	for placement: Array in [[&"drinks_shelf", Vector2i(10, 5), 2], [&"drinks_fridge", Vector2i(11, 5), 2],
			[&"table_2", Vector2i(2, 8), 0]]:
		if not editor.buy(placement[0], placement[1], placement[2]):
			return false
	if not _counter_with_stools(editor, 9, 12) or not _storage_shelves(editor) \
			or not editor.last_check.unreachable.is_empty():
		return false
	return _finish(main, 16 * 60, 24 * 60, [&"beer", &"wine", &"soft_drink", &"burger", &"grilled_cheese"],
		[&"tomato_soup"])


static func _free_editor(main: Node) -> ShopEditor:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var content: ContentDB = main.get("content") as ContentDB
	var layout: ShopLayout = load("res://data/layouts/tier1_hole_in_the_wall.tres") as ShopLayout
	if sim == null or content == null:
		return null
	var books: ShopEditBooks = ShopEditBooks.new(func(_amount: int) -> bool: return true,
		func(_amount: int, _category: StringName) -> void: pass)
	var editor: ShopEditor = ShopEditor.new(sim, content, books, layout)
	editor.set_owner_level(2)
	return editor


## The east two-seat table and the plant make room for the counter.
static func _clear_east_table(main: Node, editor: ShopEditor) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	for placed: PlacedItem in sim.world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if (definition.id == &"table_2" and placed.origin == Vector2i(10, 6)) \
				or (definition.id == &"potted_plant" and placed.origin == Vector2i(12, 9)):
			if editor.sell(placed.id) < 0:
				return false
	return true


## FK-087: a concept's supplies need storage beyond the starter pantry, as a
## player building one would add: two storage shelves in the kitchen's
## north-east corner, beside the sink.
static func _storage_shelves(editor: ShopEditor) -> bool:
	return editor.buy(&"storage_shelf", Vector2i(11, 1), 2) and editor.buy(&"storage_shelf", Vector2i(12, 1), 2)


## A counter along row 7 from x0 to x1 (guests to the south on stools at row
## 8, staff behind it on row 6): an end piece at the open west end.
static func _counter_with_stools(editor: ShopEditor, x0: int, x1: int) -> bool:
	for x: int in range(x0, x1 + 1):
		var piece: StringName = &"bar_end_right" if x == x0 else &"bar_section"
		if not editor.buy(piece, Vector2i(x, 7), 2) or not editor.buy(&"bar_stool", Vector2i(x, 8), 0):
			return false
	return true


static func _finish(main: Node, open_minute: int, close_minute: int, menu_on: Array[StringName],
		menu_off: Array[StringName]) -> bool:
	main.call("_refresh_menu_catalogue")
	if not main.call("set_opening_hours", open_minute, close_minute) or not _enable(main, menu_on):
		return false
	for id: StringName in menu_off:
		if not main.call("menu_set_enabled", id, false):
			return false
	# As a player would in the Stock panel: stop auto-buying what the menu no
	# longer uses. The new drinks' supplies are bought at opening.
	var used: Dictionary[StringName, bool] = {}
	for recipe: RecipeDef in (main.get("menu_settings") as MenuSettings).enabled_recipes():
		for ingredient: IngredientDef in recipe.ingredients:
			used[ingredient.id] = true
	# Only the ingredients auto-reorder lists (the Stock panel also shows
	# unused station-only ones, greyed out, FK-087; they are never auto-bought).
	for id: StringName in (main.call("_reorder") as ReorderSettings).ids():
		if not used.has(id) and not main.call("stock_set_auto", id, false):
			return false
	return true


## Switches on each listed dish that is cookable and unlocked; others wait.
static func _enable(main: Node, ids: Array[StringName]) -> bool:
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	for id: StringName in ids:
		var recipe: RecipeDef = settings.recipe(id)
		if recipe != null and recipe.unlock_level <= settings.owner_level() and not settings.is_enabled(id):
			main.call("menu_set_enabled", id, true)
	return true


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



## FK-081: an explicitly level-two diner with a fryer and coffee machine.
## Like the existing concept probes, equipment is free; stock is bought by
## the production opening top-up at its normal price. Default is untouched.
static func _fryer_coffee(main: Node) -> bool:
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if progress == null or settings == null or sim == null:
		return false
	if progress.award_bonus(maxi(0, progress.threshold_for(2) - progress.total_xp)).is_empty() \
			or not settings.set_owner_level(progress.level) or not sim.set_customer_level(progress.level):
		return false
	var editor: ShopEditor = _free_editor(main)
	if editor == null or not editor.buy(&"fryer", Vector2i(9, 3), 0) \
			or not editor.buy(&"coffee_machine", Vector2i(12, 3), 0) \
			or not _storage_shelves(editor) or not editor.last_check.unreachable.is_empty():
		return false
	return _finish(main, 11 * 60, 21 * 60, [&"burger", &"grilled_cheese", &"fries", &"coffee"],
		[&"tea", &"tomato_soup"])


## Joined-table fixture: two starter tables joined, plus two real cushioned chairs bought
## for $20 through normal morning commands. Third table, menu, stock and staff
## remain as shipped; service pays its ordinary running costs.
static func _joined_tables(main: Node) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null:
		return false
	var starts: Array[Vector2i] = [Vector2i(2, 6), Vector2i(6, 6)]
	var targets: Array[Vector2i] = [Vector2i(3, 6), Vector2i(5, 6)]
	var ids: Array[int] = []
	for origin: Vector2i in starts:
		var found: int = 0
		for item: PlacedItem in sim.world.grid.items():
			var definition: ItemDef = item.def as ItemDef
			if definition != null and definition.id == &"table_2" and item.origin == origin:
				found = item.id
		if found == 0:
			return false
		ids.append(found)
	for index: int in ids.size():
		if not main.call("shop_move", ids[index], targets[index], 1):
			return false
	if not main.call("shop_buy", &"chair", Vector2i(4, 5), 2) \
			or not main.call("shop_buy", &"chair", Vector2i(6, 8), 0):
		return false
	return sim.world.grid.dining_group_members(ids[0]) == ids \
		and DiningSeats.usable_cells(sim.world.grid, sim.world.grid.item(ids[0])).size() == 6


## Default service with a decorated front. Like the existing expanded-layout
## probe, construction is free: only this temporary editor unlocks level four.
## No owner XP, cash, stock or service settings are granted or reset. Nominal
## catalogue/finish costs remain available separately; this is not an ROI test.
static func _curb_appeal(main: Node) -> bool:
	var live: ShopEditor = main.get("shop_editor") as ShopEditor
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if live == null or progress == null or sim == null or live.decor.count() != 0:
		return false
	var front: Script = load("res://tools/street_front_review.gd")
	var pieces: Array[Dictionary] = front._pieces(sim.world.grid)
	var faces: Array[Vector3i] = front._finish_faces(sim.world.grid)
	var editor: ShopEditor = _free_editor(main)
	if editor == null or pieces.size() != 5 or faces.size() != 4:
		return false
	# Share the real, signal-connected frontage objects. The temporary free
	# books and unlock never replace Main's production editor or progression.
	editor.walls = live.walls
	editor.decor = live.decor
	editor.set_owner_level(4)
	var ok: bool = editor.apply_wall_finishes(editor.wall_lay_changes(faces, &"brick", &"terracotta", &"cream"))
	for piece: Dictionary in pieces:
		if ok:
			ok = editor.hang(piece["id"], piece["anchor"], null, piece["swatch"])
	editor.set_owner_level(progress.level)
	return ok


## Read-only setup declaration, separate from every existing probe report row.
static func curb_appeal_construction(main: Node) -> Dictionary:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var content: ContentDB = main.get("content") as ContentDB
	if sim == null or content == null:
		return {"error": "The real shop content is missing"}
	var front: Script = load("res://tools/street_front_review.gd")
	var items: Array[Dictionary] = []
	var total: int = 0
	for piece: Dictionary in front._pieces(sim.world.grid):
		var definition: ItemDef = content.item(piece["id"])
		if definition == null:
			return {"error": "A supported street item is missing"}
		total += definition.price
		items.append({"item": String(definition.id), "catalogue_price": definition.price})
	var style: WallStyleDef = content.wall_style(&"brick")
	if style == null:
		return {"error": "The authored brick finish is missing"}
	var faces: int = front._finish_faces(sim.world.grid).size()
	total += faces * style.price
	return {"error": "", "profile": "curb_appeal", "items": items,
		"finish": {"style": "brick", "faces": faces, "price_per_face": style.price},
		"nominal_construction_cost": total, "actual_construction_charge": 0,
		"convention": "Free frontage construction; temporary editor-only level4 restored; no cash or owner-XP grants. Normal paid stock and service.",
		"comparison_scope": "Appeal and service comparison, not purchase return on investment"}
