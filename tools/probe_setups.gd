class_name ProbeSetups
extends RefCounted
## Explicit morning scenarios for the manual balance probe. Add new scenarios
## here so the runner and its output format stay unchanged.


static func names() -> Array[String]:
	return ["default", "extra_cook", "extra_server", "owner_kitchen", "owner_floor",
		"trays_2", "trays_4", "extra_cleaner", "expanded_tables", "coffee_shop", "bar", "fryer_coffee", "joined_tables",
		"grown", "neglected", "curb_appeal", "expanded_staffed", "coffee_counter", "patio", "opening_week"]


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
		"coffee_counter":
			return _coffee_shop(main, true)
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
		"patio":
			return _patio(main)
		"opening_week":
			return _opening_week(main)
		"expanded_staffed":
			# #85: grow the floor and hire for it, the player's "expand" move.
			return _expand_with_tables(main) and _add_staff(main, &"cook", 3) and _add_staff(main, &"server", 3)
	return false


## Each later morning, before opening: a concept switches on the drinks it
## has newly unlocked (wine at level 2), as a player running it would.
static func morning(name: String, main: Node) -> bool:
	match name:
		"neglected":
			return _neglected(main)
		"coffee_shop", "coffee_counter":
			return _enable(main, [&"coffee", &"tea", &"croissant"])
		"fryer_coffee":
			return _enable(main, [&"burger", &"grilled_cheese", &"fries", &"coffee"])
		"bar":
			return _enable(main, [&"beer", &"wine", &"soft_drink", &"burger", &"grilled_cheese"])
		"opening_week":
			return _opening_week(main)
	return true


## #494: a player following the opening-week goals through real, paid
## commands. Day 1: prices up about 10%, a floor lamp, the owner on the floor.
## Day 2: a drinks shelf (beer goes on the menu). Day 3: a table and a hired
## server on the same morning. Later mornings change nothing.
static func _opening_week(main: Node) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	if sim == null or settings == null or editor == null:
		return false
	match sim.world.clock.day:
		1:
			for recipe: RecipeDef in settings.enabled_recipes():
				if not main.call("menu_set_price", recipe.id, settings.ten_percent_price(recipe.id, 1)):
					return false
			return main.call("shop_buy", &"lamp_floor_round", Vector2i(1, 5), 0) \
				and editor.last_check.unreachable.is_empty() and sim.assign_owner(&"floor")
		2:
			return main.call("shop_buy", &"drinks_shelf", Vector2i(12, 1), 2) \
				and editor.last_check.unreachable.is_empty()
		3:
			if not main.call("shop_buy", &"table_2", Vector2i(3, 12), 0) \
					or not editor.last_check.unreachable.is_empty():
				return false
			for member: StaffMember in (main.get("staff_roster") as StaffRoster).candidates():
				if member.role == &"server":
					return main.call("staff_hire", member.id)
			# No server applied this morning: the probe hires a skill-3 one.
			return _add_staff(main, &"server", 3)
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
##
## With `counter` (#293, coffee_counter) the same shop also has an order counter
## continuing the bar's line along its row (7, or 8 in the deeper room; x 13 and 14): the till's staff side is
## the end of the bar's back row, three steps from the coffee machines, its guests
## stand on the row below and the queue runs down column 13 and along the south wall.
static func _coffee_shop(main: Node, counter: bool = false) -> bool:
	var editor: ShopEditor = _free_editor(main)
	if editor == null or not _clear_east_table(main, editor) or not _concept_west_table(main, editor):
		return false
	var deeper: bool = _probe_layout(main).rows.size() >= 17
	# On the original layout the lane past the turned middle table at (5, 8)
	# is the only way to the pass that is not through a seat (#320), so the
	# small plant stands one cell west, beside the round table.
	var plant: Vector2i = Vector2i(5, 8) if _probe_layout(main).save_layout_id != &"" else Vector2i(4, 8)
	for placement: Array in [[&"coffee_machine", Vector2i(9, 5), 2], [&"coffee_machine", Vector2i(10, 5), 2],
			[&"round_table", Vector2i(2, 8), 0], [&"rounded_chair", Vector2i(1, 8), 1],
			[&"rounded_chair", Vector2i(4, 9), 3], [&"plant_small_2", plant, 0],
			[&"side_table", Vector2i(11, 5), 2], [&"plant_small_2", Vector2i(12, 5), 0]]:
		if not editor.buy(placement[0], placement[1], placement[2]):
			return false
	# In the deeper starter room the counter sits one row further from the
	# machines, leaving the two-cell aisle a player is warned to keep (#390):
	# a one-cell gap had staff looping round the full counter (#400).
	var row: int = 8 if deeper else 7
	if counter and not editor.buy(&"order_counter", Vector2i(13, row), 0):
		return false
	if not _counter_with_stools(editor, 9, 12, row) or not _storage_shelves(editor) \
			or not editor.last_check.unreachable.is_empty():
		return false
	return _finish(main, 7 * 60, 15 * 60, [&"coffee", &"tea", &"croissant"],
		[&"burger", &"grilled_cheese", &"tomato_soup"])


## FK-083 bar: open 16:00-24:00 with beer, wine and soft drinks from a drinks
## shelf and fridge behind a four-stool bar, plus burgers and grilled cheese,
## and two storage shelves (FK-087).
static func _bar(main: Node) -> bool:
	var editor: ShopEditor = _free_editor(main)
	if editor == null or not _clear_east_table(main, editor) or not _concept_west_table(main, editor):
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
	var layout: ShopLayout = _probe_layout(main)
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
	var tables: Array[PlacedItem] = _starter_tables(sim.world.grid)
	if tables.is_empty() or editor.sell(tables[-1].id) < 0:
		return false
	# The authored starter has one potted plant; its position moves with the
	# roomier shell. Remove that real instance, never a coordinate guess.
	for placed: PlacedItem in sim.world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition != null and definition.id == &"potted_plant":
			return editor.sell(placed.id) >= 0
	return false


## FK-087: a concept's supplies need storage beyond the starter pantry, as a
## player building one would add: two storage shelves in the kitchen's
## north-east corner, beside the sink.
static func _storage_shelves(editor: ShopEditor) -> bool:
	return editor.buy(&"storage_shelf", Vector2i(11, 1), 2) and editor.buy(&"storage_shelf", Vector2i(12, 1), 2)


## A counter along `row` from x0 to x1 (guests to the south on stools at row + 1,
## staff behind it on row - 1): an end piece at the open west end.
static func _counter_with_stools(editor: ShopEditor, x0: int, x1: int, row: int = 7) -> bool:
	for x: int in range(x0, x1 + 1):
		var piece: StringName = &"bar_end_right" if x == x0 else &"bar_section"
		if not editor.buy(piece, Vector2i(x, row), 2) or not editor.buy(&"bar_stool", Vector2i(x, row + 1), 0):
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
	var layout: ShopLayout = _probe_layout(main)
	var books: ShopEditBooks = ShopEditBooks.new(func(_amount: int) -> bool: return true,
		func(_amount: int, _category: StringName) -> void: pass)
	var editor: ShopEditor = ShopEditor.new(sim, content, books, layout)
	var building: Rect2i = ShopFootprint.from_layout(layout).building
	var tables: Array[PlacedItem] = _starter_tables(sim.world.grid)
	if tables.is_empty():
		return false
	var dining_y: int = building.end.y
	for cell: Vector2i in sim.world.grid.cells():
		if sim.world.grid.terrain(cell) == SimGrid.Terrain.FLOOR \
				and sim.world.grid.room(cell) == SimGrid.Room.DINING:
			dining_y = mini(dining_y, cell.y)
	# One-cell side wings stop before the street wall on either authored base.
	# Geometry changes with the larger starter; the extra two tables and free
	# construction convention do not change.
	var front_y: int = building.end.y - 1
	for rect: Rect2i in [Rect2i(building.end.x, building.position.y, 1, front_y - building.position.y),
			Rect2i(building.position.x - 1, dining_y, 1, front_y - dining_y)]:
		var cells: Array[Vector2i] = []
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
		if not editor.apply_floor(cells, true):
			return false
	return editor.buy(&"table_2", Vector2i(building.end.x - 1, tables[0].origin.y), 1) \
		and editor.buy(&"table_2", Vector2i(building.position.x - 1, tables[0].origin.y), 1) \
		and editor.last_check.unreachable.is_empty()



## FK-081: an explicitly level-two diner with a fryer and coffee machine.
## Like the existing concept probes, equipment is free; stock is bought by
## the production opening top-up at its normal price. Default is untouched.
static func _fryer_coffee(main: Node) -> bool:
	var progress: OwnerProgress = main.get("owner_progress") as OwnerProgress
	var settings: MenuSettings = main.get("menu_settings") as MenuSettings
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if progress == null or settings == null or sim == null:
		return false
	if not _stage_fryer_owner(sim):
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
	var tables: Array[PlacedItem] = _starter_tables(sim.world.grid)
	if tables.size() < 2:
		return false
	# Keep the six-seat joined fixture one row below the starter-table line:
	# its northern seats must not double as either base's pass work cells.
	var targets: Array[Vector2i] = [tables[0].origin + Vector2i(1, 1),
		tables[0].origin + Vector2i(3, 1)]
	var ids: Array[int] = [tables[0].id, tables[1].id]
	for index: int in ids.size():
		if not main.call("shop_move", ids[index], targets[index], 1):
			return false
	if not main.call("shop_buy", &"chair", targets[0] + Vector2i(1, -1), 2) \
			or not main.call("shop_buy", &"chair", targets[1] + Vector2i(1, 2), 0):
		return false
	return sim.world.grid.dining_group_members(ids[0]) == ids \
		and DiningSeats.usable_cells(sim.world.grid, sim.world.grid.item(ids[0])).size() == 6


## The selected authored base, including the preserved original-save template.
static func _probe_layout(main: Node) -> ShopLayout:
	var loaded: ShopLayout = main.get("_loaded_layout") as ShopLayout
	return loaded if loaded != null else main.call("_lease_layout") as ShopLayout


static func _starter_tables(grid: SimGrid) -> Array[PlacedItem]:
	var result: Array[PlacedItem] = []
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition != null and definition.id == &"table_2":
			result.append(placed)
	result.sort_custom(_table_before)
	return result


static func _table_before(left: PlacedItem, right: PlacedItem) -> bool:
	if left.origin.x != right.origin.x:
		return left.origin.x < right.origin.x
	if left.origin.y != right.origin.y:
		return left.origin.y < right.origin.y
	return left.id < right.id


## Preserve real aisles around the concepts' ten seats. Empty seats still
## cannot be used as paths: the original narrow shell needs both side
## bypasses, while the roomier shop already has the eastern floor. As with
## the existing concept equipment, the ordinary editor builds these strips
## with the same free construction books; stock and service remain paid.
static func _concept_access_floor(main: Node, editor: ShopEditor) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var building: Rect2i = editor.footprint().building
	var columns: Array[int] = [building.position.x - 1]
	if not sim.world.grid.is_walkable(Vector2i(13, 8)):
		columns.append(building.end.x)
	for x: int in columns:
		var cells: Array[Vector2i] = []
		for y: int in range(6, 10):
			cells.append(Vector2i(x, y))
		if not editor.apply_floor(cells, true):
			return false
	return true


## These concepts retain the original four-seat left dining group. Restore
## its complete pose before adding the unchanged lower table/chairs: merely
## turning the roomier starter in place overlaps that lower table. On the
## original layout the middle table turns for an aisle (#320); otherwise the
## other starter table, item counts and default play remain untouched.
static func _concept_west_table(main: Node, editor: ShopEditor) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var tables: Array[PlacedItem] = _starter_tables(sim.world.grid)
	if tables.is_empty() or not _concept_access_floor(main, editor):
		return false
	var west: PlacedItem = tables[0]
	var target: Vector2i = Vector2i(2, 6)
	if not ((west.origin == target and west.quarter_turns == 0) or editor.move(west.id, target, 0)):
		return false
	# On the original layout that restores its row of seats, which nobody walks
	# through (#320): the middle table turns where it stands for the aisle.
	if not _probe_layout(main).save_layout_id.is_empty() or tables.size() < 2:
		return true
	var middle: PlacedItem = tables[1]
	return middle.quarter_turns == 1 or editor.move(middle.id, middle.origin, 1)


## Declared fryer-fixture construction pose, not a service-policy change.
## The owner starts on the planned fryer at (9,3). In the closed morning,
## legally step aside to (8,3), outside the fryer (9/10,3), coffee (12,3)
## and shelf (11/12,1) placements. The canonical probe's ordinary
## sim.start_day() still resets everyone to their authored posts afterward.
static func _stage_fryer_owner(sim: RestaurantSim) -> bool:
	if sim == null or sim.world.clock.phase != SimClock.Phase.MORNING:
		return false
	var owner: OwnerAgent = sim.owner_agent()
	var target: Vector2i = Vector2i(8, 3)
	if owner == null or owner.task != null or not sim.world.grid.is_walkable(target) \
			or not sim.world.movement.can_enter(sim.world, owner, target):
		return false
	return sim.world.reset_agent_position(owner, target) and owner.cell == target


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


## Default plus two outdoor two-seat tables. As with expanded_tables, this
## explicit probe builds for free through the actual editor; ordinary stock
## and daily service costs are paid. Weather is the real morning's selection.
## All purchasable side cells are connected to the existing street entries; their two
## public approach columns remain untouched. No cash, XP or stock is granted.
static func _patio(main: Node) -> bool:
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var free: ShopEditor.Exact = ShopEditor.Exact.new(0, "Declared free patio probe construction")
	# Keep ownership on the session's real editor, so its next morning and
	# snapshot retain the same purchased cells as the live simulation grid.
	if editor == null or not editor.apply_patio(editor.patio_area().cells(), true, free):
		return false
	for origin: Vector2i in patio_table_origins((main.get("sim") as RestaurantSim).world.grid):
		if not editor.buy(&"patio_table_2", origin, 0, free):
			return false
	main.call("refresh_presentation")
	return editor.last_check.unreachable.is_empty()


static func patio_table_origins(grid: SimGrid) -> Array[Vector2i]:
	var entry: Vector2i = grid.entries()[0]
	return [entry + Vector2i(-4, 1), entry + Vector2i(3, 1)]

