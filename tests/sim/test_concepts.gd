extends TestCase
## FK-083: Café and Bar themes, drinks and their stations, drinks-only visits,
## counter seats served across, time-of-day visit weights and opening hours.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const VIBE: VibeTuning = preload("res://data/balance/vibe.tres")
const VISITS: VisitTuning = preload("res://data/balance/visits.tres")
const HOURS: OpeningHoursTuning = preload("res://data/balance/hours.tres")
const MAX_TICKS: int = 4000

var _content: ContentDB
var _sim: RestaurantSim
var _paid: Array[StringName] = []
var _left: Dictionary[int, StringName] = {}
var _tasks: Dictionary[StringName, int] = {}
var _pour_cells: Array[Vector2i] = []


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_paid.clear()
	_left.clear()
	_tasks.clear()
	_pour_cells.clear()


func after_each() -> void:
	_sim = null
	_content = null


# --- Café and Bar themes -------------------------------------------------

func test_cafe_and_bar_are_vibe_themes_in_order() -> void:
	assert_true(VIBE.is_valid())
	assert_true(VibeTuning.KNOWN_THEMES.has(&"cafe") and VibeTuning.KNOWN_THEMES.has(&"bar"))
	assert_eq(VIBE.theme_labels[&"cafe"], "Café")
	assert_eq(VIBE.theme_labels[&"bar"], "Bar")
	assert_eq(VIBE.theme_order.slice(5), [&"cafe", &"bar"] as Array[StringName], "the old themes keep their tie order")


func test_cafe_tagged_room_scores_as_a_cafe() -> void:
	var items: Array[ItemDef] = [_content.item(&"round_table"), _content.item(&"rounded_chair"),
		_content.item(&"rounded_chair"), _content.item(&"coffee_machine")]
	var result: VibeModel.Result = _vibe(items, [&"plant_small_2", &"plant_small_2", &"side_table", &"side_table"],
		[&"coffee", &"tea", &"croissant"])
	assert_true(result.valid, result.reason)
	assert_eq(result.active_theme, &"cafe")
	assert_eq(result.theme_label, "Café")
	assert_true(result.theme_points > 0.0)


func test_bar_tagged_room_scores_as_a_bar_and_equipment_votes_through_item_weights() -> void:
	var items: Array[ItemDef] = [_content.item(&"bar_section"), _content.item(&"bar_section"),
		_content.item(&"bar_end_right"), _content.item(&"bar_stool"), _content.item(&"bar_stool"),
		_content.item(&"drinks_shelf"), _content.item(&"drinks_fridge")]
	var result: VibeModel.Result = _vibe(items, [&"speaker", &"speaker"], [&"beer", &"wine"])
	assert_true(result.valid, result.reason)
	assert_eq(result.active_theme, &"bar")
	# A coffee machine is a station (category weight 0), yet its own weight votes.
	assert_eq(VIBE.theme_category_weights[ItemDef.Category.STATION], 0.0)
	assert_eq(VIBE.theme_item_weights[&"coffee_machine"], 1.0)
	var only_machine: VibeModel.Result = _vibe([_content.item(&"coffee_machine")] as Array[ItemDef], [], [])
	assert_true(only_machine.theme_share > 0.0, "the machine's café tag counts")


func test_the_starter_shop_keeps_its_old_vibe() -> void:
	var inputs: VibeModel.Inputs = VibeInputs.capture(_build(LAYOUT).world.grid, _content,
		_sim.menu, &"", &"")
	var result: VibeModel.Result = VibeModel.evaluate(inputs, VIBE)
	assert_true(result.valid)
	assert_true(result.active_theme != &"cafe" and result.active_theme != &"bar")
	assert_eq(result.score, 0.0, "the starter allowance stays neutral")


# --- Drinks and their stations -------------------------------------------

func test_drinks_are_drinks_with_station_steps_and_cheap_high_margins() -> void:
	for id: StringName in [&"coffee", &"tea", &"soft_drink", &"beer", &"wine"]:
		var recipe: RecipeDef = _content.recipe(id)
		assert_true(recipe.is_drink(), String(id))
		assert_true(recipe.standard_price <= 7, String(id) + " is cheap")
		assert_true(recipe.ingredient_cost() * 2 <= recipe.standard_price, String(id) + " has a high margin")
		assert_true(recipe.total_ticks() <= 30, String(id) + " is fast")
	assert_eq(_content.recipe(&"coffee").order_type, RecipeDef.COFFEE)
	assert_eq(_content.recipe(&"tea").order_type, RecipeDef.COFFEE)
	for id: StringName in [&"soft_drink", &"beer", &"wine"]:
		assert_eq(_content.recipe(id).order_type, RecipeDef.DRINKS)
	assert_eq(_content.recipe(&"coffee").steps[0].station_type, &"coffee")
	assert_eq(_content.recipe(&"soft_drink").steps[0].station_type, &"drinks_fridge")
	assert_eq(_content.recipe(&"beer").steps[0].station_type, &"drinks_shelf")
	assert_eq(_content.item(&"coffee_machine").station_type, &"coffee")
	assert_false(_content.recipe(&"croissant").is_drink(), "the pastry is food, warmed at the coffee machine")


func test_the_starter_shop_menu_has_no_drinks_and_no_pastry() -> void:
	_build(LAYOUT)
	var ids: Array[StringName] = []
	for recipe: RecipeDef in _sim.menu:
		ids.append(recipe.id)
	assert_eq(ids, [&"burger", &"grilled_cheese", &"tomato_soup"] as Array[StringName])
	assert_eq(_sim.visit_kinds(), [RecipeDef.FOOD] as Array[StringName])


func test_a_drink_without_its_station_is_cancelled_not_served() -> void:
	_build(LAYOUT)
	_sim.menu = [_content.recipe(&"coffee")] as Array[RecipeDef]
	var guest: CustomerAgent = _guest(RecipeDef.COFFEE, 41)
	assert_true(_sim.world.clock.start_service())
	_run_until_gone()
	assert_eq(_left.get(guest.id), &"kitchen_failed", "no coffee machine, no coffee")
	assert_eq(guest.order.cancellation_reason, &"missing_station")
	assert_eq(_sim.served_today, 0)


# --- Drinks-only visits and counter seats --------------------------------

func test_a_stool_facing_each_counter_piece_is_a_seat_and_is_served_across() -> void:
	_build(_bar_layout())
	for x: int in range(9, 13):
		var counter: PlacedItem = _sim.world.grid.item_at(Vector2i(x, 7))
		assert_true((counter.def as ItemDef).serve_across, "counter at %d" % x)
		assert_eq(counter.seat_cells, [Vector2i(x, 8)] as Array[Vector2i], "the facing stool is its seat")
		assert_eq(_sim.across_cell(counter.id, Vector2i(x, 8)), Vector2i(x, 6), "served from behind")
		assert_eq(_sim.service_cells(counter.id, Vector2i(x, 8)), [Vector2i(x, 6)] as Array[Vector2i])
	var table: PlacedItem = _sim.world.grid.item_at(Vector2i(2, 6))
	assert_eq(_sim.across_cell(table.id, table.seat_cells[0]), SimGrid.NO_CELL, "ordinary tables are served beside the seat")


func test_corner_seats_on_both_sides_and_a_walled_counter_falls_back_to_the_seat_side() -> void:
	var layout: ShopLayout = _base_layout()
	layout.placements.append(_placement(&"bar_corner", Vector2i(10, 6), 0))
	layout.placements.append(_placement(&"bar_stool", Vector2i(10, 5), 2))
	layout.placements.append(_placement(&"bar_stool", Vector2i(11, 6), 3))
	layout.placements.append(_placement(&"bar_section", Vector2i(12, 9), 0))
	layout.placements.append(_placement(&"bar_stool", Vector2i(12, 8), 2))
	_build(layout)
	var corner: PlacedItem = _sim.world.grid.item_at(Vector2i(10, 6))
	assert_eq(corner.seat_cells.size(), 2, "both guest sides of the corner seat a stool")
	assert_eq(_sim.across_cell(corner.id, Vector2i(10, 5)), Vector2i(10, 7))
	assert_eq(_sim.across_cell(corner.id, Vector2i(11, 6)), Vector2i(9, 6))
	var walled: PlacedItem = _sim.world.grid.item_at(Vector2i(12, 9))
	assert_eq(walled.seat_cells, [Vector2i(12, 8)] as Array[Vector2i])
	assert_eq(_sim.across_cell(walled.id, Vector2i(12, 8)), SimGrid.NO_CELL, "the wall is behind it")
	assert_eq(_sim.service_cells(walled.id, Vector2i(12, 8)), _sim.world.grid.walkable_neighbours(Vector2i(12, 8)))


func test_drinks_only_guests_take_a_counter_seat_get_their_drink_across_it_and_leave_it_clean() -> void:
	_build(_bar_layout())
	_sim.menu = [_content.recipe(&"burger"), _content.recipe(&"beer"), _content.recipe(&"soft_drink")] as Array[RecipeDef]
	var guests: Array[CustomerAgent] = []
	for index: int in range(3):
		guests.append(_guest(RecipeDef.DRINKS, 900 + index))
	assert_true(_sim.world.clock.start_service())
	_run_until_gone()
	assert_eq(_sim.served_today, 3)
	for guest: CustomerAgent in guests:
		assert_eq(_left.get(guest.id), &"happy")
		assert_true(_content.recipe(guest.order.recipe_id).order_type == RecipeDef.DRINKS, "ordered a drink")
		assert_true((_sim.world.grid.item(guest.table_item_id).def as ItemDef).serve_across, "sat at the counter")
		assert_eq(guest.eat_ticks, VISITS.drink_visit_ticks, "a quick visit")
	assert_eq(_paid.size(), 3)
	assert_eq(int(_tasks.get(&"pour", 0)), 3, "front-of-house staff poured each drink")
	assert_eq(int(_tasks.get(&"cook", 0)), 0, "the kitchen cooked nothing")
	assert_eq(int(_tasks.get(&"bus_table", 0)), 0, "drinks leave no table to clear")
	for cell: Vector2i in _pour_cells:
		assert_eq(cell.y, 6, "each drink was handed over from behind the counter")
	assert_true(_sim.kitchen.dirty_tables.is_empty())
	assert_eq(_sim.kitchen.in_use_plates, 0, "drinks take no plates")


func test_a_meal_guest_may_add_a_drink_and_pays_for_both() -> void:
	_build(_bar_layout())
	_sim.menu = [_content.recipe(&"grilled_cheese"), _content.recipe(&"beer")] as Array[RecipeDef]
	var kind: CustomerType = CustomerType.new()
	kind.id = &"thirsty"
	kind.display_name = "Thirsty"
	kind.drink_add_chance = 1.0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 77
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random, kind)
	guest.eat_ticks = 5
	guest.food_patience = 5000
	assert_true(_sim.world.clock.start_service())
	_run_until_gone()
	assert_eq(_left.get(guest.id), &"happy")
	assert_eq(guest.order.recipe_id, &"grilled_cheese", "a meal guest orders food")
	assert_not_null(guest.extra_order)
	assert_eq(guest.extra_order.recipe_id, &"beer")
	assert_eq(guest.extra_order.state, Order.State.DELIVERED)
	assert_eq(_paid, [&"grilled_cheese", &"beer"] as Array[StringName], "the drink is paid with the meal")
	assert_eq(_sim.served_today, 1, "still one guest served")


func test_a_pour_frees_its_station_before_carrying_the_drink() -> void:
	_build(_bar_layout())
	_sim.menu = [_content.recipe(&"beer")] as Array[RecipeDef]
	for index: int in range(2):
		_guest(RecipeDef.DRINKS, 300 + index)
	assert_true(_sim.world.clock.start_service())
	var carrying: int = 0
	var held: int = 0
	for tick: int in range(MAX_TICKS):
		_sim.advance()
		for agent: SimAgent in _sim.world.agents:
			var staff: StaffAgent = agent as StaffAgent
			if staff == null or staff.task == null or staff.task.kind != &"pour" \
					or staff.task.steps[staff.step_index].kind != TaskStep.Kind.GO_TO_CELL:
				continue
			carrying += 1
			for id: int in staff.task.payload["station_ids"]:
				var station: PlacedItem = _sim.world.grid.item(id)
				for cell: Vector2i in station.work_cells:
					if station.reserved_by(cell) == staff.id:
						held += 1
		if _sim.customers().is_empty() and _sim.world.board.active_count() == 0:
			break
	assert_true(carrying > 0, "drinks were carried")
	assert_eq(held, 0, "nobody holds the shelf while walking to a guest")
	assert_eq(_sim.served_today, 2)


func test_a_coffee_guest_may_add_a_pastry_and_has_it_with_the_coffee() -> void:
	_build(_bar_layout())
	_sim.menu = [_content.recipe(&"coffee"), _content.recipe(&"croissant")] as Array[RecipeDef]
	var kind: CustomerType = CustomerType.new()
	kind.id = &"peckish"
	kind.display_name = "Peckish"
	kind.pastry_add_chance = 1.0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 12
	var guest: CustomerAgent = _sim.add_visitor(_sim.world.grid.entries()[0], random, kind, RecipeDef.COFFEE)
	guest.food_patience = 5000
	assert_true(_sim.world.clock.start_service())
	var ate_before_pastry: bool = false
	for tick: int in range(MAX_TICKS):
		_sim.advance()
		if guest.state == CustomerAgent.State.EATING and guest.extra_order != null \
				and guest.extra_order.state != Order.State.DELIVERED:
			ate_before_pastry = true
		if _sim.customers().is_empty() and _sim.world.board.active_count() == 0:
			break
	assert_eq(guest.order.recipe_id, &"coffee")
	assert_not_null(guest.extra_order)
	assert_eq(guest.extra_order.recipe_id, &"croissant")
	assert_false(ate_before_pastry, "the coffee waits for its croissant")
	assert_eq(_paid, [&"coffee", &"croissant"] as Array[StringName])
	assert_true(_sim.kitchen.is_clean(), "the plate came back and the seat was cleared")


func test_no_pastry_on_the_menu_means_no_pastry_draw() -> void:
	_build(_bar_layout())
	_sim.menu = [_content.recipe(&"coffee"), _content.recipe(&"burger")] as Array[RecipeDef]
	var kind: CustomerType = CustomerType.new()
	kind.id = &"peckish"
	kind.display_name = "Peckish"
	kind.pastry_add_chance = 1.0
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 5
	var guest: CustomerAgent = _sim.add_visitor(_sim.world.grid.entries()[0], random, kind, RecipeDef.COFFEE)
	guest.state = CustomerAgent.State.ORDERING
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = 5
	expected.randi_range(0, 0)
	assert_true(guest._take_order(null))
	assert_null(guest.extra_order, "a burger is not a pastry")
	assert_eq(random.state, expected.state, "one drink draw only")


func test_no_drink_on_the_menu_means_no_extra_draw_for_a_meal_guest() -> void:
	_build(LAYOUT)
	var kind: CustomerType = CustomerType.new()
	kind.id = &"thirsty"
	kind.display_name = "Thirsty"
	kind.drink_add_chance = 1.0
	var plain: RandomNumberGenerator = RandomNumberGenerator.new()
	plain.seed = 5
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], plain, kind)
	guest.state = CustomerAgent.State.ORDERING
	var before: int = plain.state
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = 5
	expected.randi_range(0, _sim.available_menu().size() - 1)
	assert_true(guest._take_order(null))
	assert_null(guest.extra_order)
	assert_eq(plain.state, expected.state, "one dish draw only (from %d)" % before)


# --- Who visits when -----------------------------------------------------

func test_visit_weights_put_coffee_in_the_morning_and_drinks_in_the_evening() -> void:
	assert_true(VISITS.is_valid())
	var morning: int = 8 * 60
	var evening: int = 21 * 60
	assert_true(VISITS.weight(RecipeDef.COFFEE, morning) > VISITS.weight(RecipeDef.DRINKS, morning) * 4.0)
	assert_true(VISITS.weight(RecipeDef.DRINKS, evening) > VISITS.weight(RecipeDef.COFFEE, evening) * 4.0)
	for hour: int in range(11, 21):
		assert_eq(VISITS.weight(RecipeDef.FOOD, hour * 60 + 30), 1.0, "default hours keep the food rate")
		assert_eq(VISITS.arrival_rate([RecipeDef.FOOD] as Array[StringName], hour * 60), 1.0)
	assert_true(VISITS.arrival_rate([RecipeDef.FOOD, RecipeDef.COFFEE] as Array[StringName], morning) > 1.0)
	assert_eq(CustomerSpawner.scaled_gap(180, 1.0), 180)
	assert_eq(CustomerSpawner.scaled_gap(180, 2.0), 90)


func test_arriving_guests_follow_the_hour_and_types_keep_their_preferences() -> void:
	_build(_bar_layout())
	_sim.menu = [_content.recipe(&"burger"), _content.recipe(&"coffee"), _content.recipe(&"beer")] as Array[RecipeDef]
	var kinds: Array[StringName] = _sim.visit_kinds()
	assert_eq(kinds, [RecipeDef.FOOD, RecipeDef.COFFEE, RecipeDef.DRINKS] as Array[StringName])
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 4
	var morning: Dictionary[StringName, int] = _visits_at(kinds, 8 * 60, null, random)
	var evening: Dictionary[StringName, int] = _visits_at(kinds, 21 * 60, null, random)
	assert_true(morning[RecipeDef.COFFEE] > morning[RecipeDef.DRINKS] * 3, str(morning))
	assert_true(evening[RecipeDef.DRINKS] > evening[RecipeDef.COFFEE] * 3, str(evening))
	var catalogue: CustomerTypeCatalogue = load("res://data/customers/types.tres") as CustomerTypeCatalogue
	var student: CustomerType = catalogue.find_type(&"student")
	var regular: CustomerType = catalogue.find_type(&"regular")
	assert_true(student.visit_weight(RecipeDef.COFFEE) > regular.visit_weight(RecipeDef.COFFEE))
	assert_true(regular.visit_weight(RecipeDef.DRINKS) > student.visit_weight(RecipeDef.DRINKS))
	var students: Dictionary[StringName, int] = _visits_at(kinds, 13 * 60, student, random)
	var regulars: Dictionary[StringName, int] = _visits_at(kinds, 13 * 60, regular, random)
	assert_true(students[RecipeDef.COFFEE] > regulars[RecipeDef.COFFEE], "%s vs %s" % [students, regulars])
	var one: Array[StringName] = [RecipeDef.FOOD]
	var untouched: int = random.state
	assert_eq(CustomerSpawner.choose_visit(one, regular, _sim, random), RecipeDef.FOOD)
	assert_eq(random.state, untouched, "one kind on the menu draws nothing")


func test_students_like_a_cafe_and_regulars_like_a_bar() -> void:
	var catalogue: CustomerTypeCatalogue = load("res://data/customers/types.tres") as CustomerTypeCatalogue
	assert_true(catalogue.is_valid())
	var student: CustomerType = catalogue.find_type(&"student")
	var regular: CustomerType = catalogue.find_type(&"regular")
	assert_eq(student.liked_themes, [&"cafe"] as Array[StringName])
	assert_eq(regular.liked_themes, [&"bar"] as Array[StringName])
	assert_true(student.theme_multiplier(&"cafe", 0.4) > 1.0 and student.theme_multiplier(&"cafe", 0.4) < 1.5,
		"a small bonus")
	assert_eq(student.theme_multiplier(&"bar", 0.4), 1.0)
	assert_eq(regular.theme_multiplier(&"diner", 1.0), 1.0)
	# The picker's draw is unchanged unless a liked theme is active.
	var a: RandomNumberGenerator = RandomNumberGenerator.new()
	var b: RandomNumberGenerator = RandomNumberGenerator.new()
	var students_plain: int = 0
	var students_cafe: int = 0
	a.seed = 9
	b.seed = 9
	for index: int in range(400):
		var plain: CustomerType = CustomerTypePicker.choose(catalogue, 1, 3.0, a, &"diner", 1.0)
		var cafe: CustomerType = CustomerTypePicker.choose(catalogue, 1, 3.0, b, &"cafe", 1.0)
		students_plain += 1 if plain.id == &"student" else 0
		students_cafe += 1 if cafe.id == &"student" else 0
	assert_true(students_cafe > students_plain, "%d vs %d" % [students_cafe, students_plain])


# --- Opening hours -------------------------------------------------------

func test_opening_hours_keep_to_their_limits() -> void:
	assert_true(HOURS.is_valid())
	assert_true(OpeningHours.allowed(11 * 60, 21 * 60, HOURS), "the default")
	assert_true(OpeningHours.allowed(7 * 60, 15 * 60, HOURS), "a coffee shop")
	assert_true(OpeningHours.allowed(16 * 60, 24 * 60, HOURS), "a bar")
	assert_false(OpeningHours.allowed(5 * 60, 15 * 60, HOURS), "too early")
	assert_false(OpeningHours.allowed(12 * 60, 14 * 60, HOURS), "too short")
	assert_false(OpeningHours.allowed(7 * 60, 23 * 60, HOURS), "too long")
	assert_false(OpeningHours.allowed(7 * 60 + 15, 15 * 60, HOURS), "off the step")
	var clock: SimClock = SimClock.new()
	assert_true(OpeningHours.clock_valid(clock, HOURS), "a new clock has the default hours")
	assert_eq(OpeningHours.wage_for_day(30, clock, HOURS), 30, "default hours pay the daily wage")
	assert_true(OpeningHours.apply(clock, 7 * 60, 15 * 60, HOURS))
	assert_eq(clock.open_ticks, 8 * 60 * HOURS.ticks_per_minute)
	assert_eq(clock.display_minutes(), 7 * 60)
	assert_eq(OpeningHours.wage_for_day(30, clock, HOURS), 24, "eight of ten hours")
	assert_false(OpeningHours.apply(clock, 4 * 60, 15 * 60, HOURS))
	assert_eq(clock.display_open_minute, 7 * 60, "a refused change changes nothing")
	assert_true(clock.start_service())
	assert_false(OpeningHours.apply(clock, 8 * 60, 15 * 60, HOURS), "mornings only")
	var restored: SimClock = SimClock.from_dict(clock.to_dict())
	assert_eq([restored.display_open_minute, restored.display_close_minute, restored.open_ticks],
		[7 * 60, 15 * 60, 2880], "the clock section carries the hours")


# --- Helpers -------------------------------------------------------------

func _visits_at(kinds: Array[StringName], minute: int, kind: CustomerType,
		random: RandomNumberGenerator) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {RecipeDef.FOOD: 0, RecipeDef.COFFEE: 0, RecipeDef.DRINKS: 0}
	var clock: SimClock = _sim.world.clock
	clock.display_open_minute = minute
	clock.display_close_minute = minute + 60
	for index: int in range(600):
		var visit: StringName = CustomerSpawner.choose_visit(kinds, kind, _sim, random)
		counts[visit] += 1
	return counts


func _vibe(items: Array[ItemDef], decor: Array[StringName], dishes: Array[StringName]) -> VibeModel.Result:
	var inputs: VibeModel.Inputs = VibeModel.Inputs.new()
	var x: int = 0
	var all: Array[ItemDef] = items.duplicate()
	for id: StringName in decor:
		all.append(_content.item(id))
	for definition: ItemDef in all:
		var item: VibeModel.Item = VibeModel.Item.new()
		item.definition_id = definition.id
		item.charm = float(definition.charm)
		item.category = definition.category
		item.theme_tags = definition.theme_tags.duplicate()
		item.cells = [Vector2i(x, 0)] as Array[Vector2i]
		inputs.items.append(item)
		x += 1
	for cell: int in range(60):
		inputs.floor_cells.append(Vector2i(cell % 10, floori(cell / 10.0)))
	for id: StringName in dishes:
		var dish: VibeModel.Dish = VibeModel.Dish.new()
		dish.id = id
		dish.theme_tags = _content.recipe(id).theme_tags.duplicate()
		inputs.menu.append(dish)
	return VibeModel.evaluate(inputs, VIBE)


func _base_layout() -> ShopLayout:
	var layout: ShopLayout = ShopLayout.new()
	layout.id = &"concept_fixture"
	layout.display_name = "Concept fixture"
	layout.rows = LAYOUT.rows.duplicate()
	layout.staff_spawns = LAYOUT.staff_spawns.duplicate()
	for placed: ShopPlacement in LAYOUT.placements:
		if placed.item_id == &"table_2" and placed.origin == Vector2i(10, 6):
			continue
		if placed.item_id == &"potted_plant":
			continue
		layout.placements.append(placed.duplicate(true) as ShopPlacement)
	return layout


## The probe's bar: four counter pieces on row 7 (staff behind on row 6,
## stools on row 8), a drinks shelf and fridge, and a coffee machine.
func _bar_layout() -> ShopLayout:
	var layout: ShopLayout = _base_layout()
	for x: int in range(9, 13):
		layout.placements.append(_placement(&"bar_end_right" if x == 9 else &"bar_section", Vector2i(x, 7), 2))
		layout.placements.append(_placement(&"bar_stool", Vector2i(x, 8), 0))
	layout.placements.append(_placement(&"drinks_shelf", Vector2i(10, 5), 2))
	layout.placements.append(_placement(&"drinks_fridge", Vector2i(11, 5), 2))
	layout.placements.append(_placement(&"coffee_machine", Vector2i(12, 5), 2))
	return layout


func _placement(id: StringName, origin: Vector2i, turns: int) -> ShopPlacement:
	var placement: ShopPlacement = ShopPlacement.new()
	placement.item_id = id
	placement.origin = origin
	placement.quarter_turns = turns
	return placement


func _build(layout: ShopLayout) -> RestaurantSim:
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 50, 1)
	var errors: Array[String] = []
	_sim = RestaurantSim.create(layout, _content, 83, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()
	_sim.customer_paid.connect(_on_paid)
	_sim.customer_left.connect(_on_left)
	_sim.world.board.task_completed.connect(_on_task_completed)
	return _sim


func _guest(visit: StringName, seed: int) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	var guest: CustomerAgent = _sim.add_visitor(_sim.world.grid.entries()[0], random, null, visit)
	guest.food_patience = 5000
	return guest


func _run_until_gone() -> void:
	for tick: int in range(MAX_TICKS):
		_sim.advance()
		if _sim.customers().is_empty() and _sim.world.board.active_count() == 0:
			return
	assert_true(false, "service did not settle within %d ticks" % MAX_TICKS)


func _on_paid(_customer: CustomerAgent, order: Order, _amount: int) -> void:
	_paid.append(order.recipe_id)


func _on_left(customer: CustomerAgent, reason: StringName) -> void:
	_left[customer.id] = reason


func _on_task_completed(task: SimTask) -> void:
	_tasks[task.kind] = int(_tasks.get(task.kind, 0)) + 1
	if task.kind == &"pour":
		var agent: SimAgent = _sim.world.agent(task.claimed_by)
		if agent != null:
			_pour_cells.append(agent.cell)
