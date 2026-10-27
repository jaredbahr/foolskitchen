extends TestCase
## Sold-out dishes (#54): guests order what the fridge can still cook and only
## walk out when every dish on the menu has run out.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
var _content: ContentDB
var _sim: RestaurantSim
var _left: Dictionary[int, StringName] = {}


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_left.clear()


func after_each() -> void:
	_sim = null
	_content = null


func _start(stock: Stock, menu: Array[StringName]) -> void:
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 5401, errors, stock)
	assert_eq(errors, [] as Array[String])
	_sim.customer_left.connect(_on_left)
	var recipes: Array[RecipeDef] = []
	for id: StringName in menu:
		recipes.append(_content.recipe(id))
	_sim.menu = recipes
	_sim.spawner.min_gap = 100000
	_sim.spawner.max_gap = 100000
	_sim.start_day()


func _full_stock(except: Dictionary = {}) -> Stock:
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		var qty: int = int(except.get(ingredient.id, 100))
		if qty > 0:
			stock.add(ingredient.id, qty, 1)
	return stock


func _guest(seed: int) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	var guest: CustomerAgent = _sim.add_customer(_sim.world.grid.entries()[0], random)
	guest.eat_ticks = 3
	guest.food_patience = 5000
	return guest


## Asks a seated guest for an order directly, as a server's work step does.
func _ordering_guest(seed: int) -> CustomerAgent:
	var guest: CustomerAgent = _guest(seed)
	guest.state = CustomerAgent.State.ORDERING
	return guest


func test_sold_out_dish_is_never_ordered_and_guests_pick_another() -> void:
	_start(_full_stock({&"beef_patty": 0}), [&"burger", &"grilled_cheese"] as Array[StringName])
	assert_true(_sim.world.clock.start_service())
	_sim.advance()
	assert_true(_sim.is_sold_out(&"burger"), "no beef: burgers are sold out from the start")
	assert_false(_sim.is_sold_out(&"grilled_cheese"))
	for seed: int in range(20):
		var guest: CustomerAgent = _ordering_guest(700 + seed)
		assert_true(guest._take_order(SimAgent.new()))
		assert_not_null(guest.order, "guest %d still orders" % seed)
		if guest.order != null:
			assert_eq(guest.order.recipe_id, &"grilled_cheese", "a sold-out dish is never ordered")
		assert_ne(guest.leave_reason, &"out_of_stock")
	assert_eq(_sim.stock_outs_today.size(), 1)
	var event: Dictionary = _sim.stock_outs_today[0]
	assert_eq(event["ingredient"], &"beef_patty")
	assert_eq(event["minute"], _sim.world.clock.display_open_minute)
	assert_eq(event["dishes"], [&"burger"] as Array[StringName])


func test_walkout_happens_only_when_every_dish_is_sold_out() -> void:
	_start(Stock.new(), [&"burger", &"grilled_cheese"] as Array[StringName])
	assert_true(_sim.world.clock.start_service())
	var guest: CustomerAgent = _guest(42)
	for tick: int in range(3000):
		_sim.advance()
		if _left.has(guest.id):
			break
	assert_null(guest.order, "no ticket is placed for food the kitchen cannot cook")
	assert_eq(_left.get(guest.id, &""), &"out_of_stock")
	assert_true(_sim.is_sold_out(&"burger"))
	assert_true(_sim.is_sold_out(&"grilled_cheese"))
	assert_eq(_sim.lost_today, 1)
	# Each dish is attributed to the first ingredient it lacks.
	assert_eq(_sim.stock_outs_today.size(), 2)
	assert_eq(_sim.stock_outs_today[0]["ingredient"], &"bun")
	assert_eq(_sim.stock_outs_today[1]["ingredient"], &"bread")


## A ticket already accepted holds its ingredients, so the next guest cannot
## order the same last portion and be sent home from the stove.
func test_accepted_tickets_hold_their_ingredients() -> void:
	var stock: Stock = _full_stock({&"bun": 1, &"beef_patty": 1, &"lettuce": 1})
	_start(stock, [&"burger"] as Array[StringName])
	assert_true(_sim.world.clock.start_service())
	_sim.advance()
	var first: CustomerAgent = _ordering_guest(11)
	assert_true(first._take_order(SimAgent.new()))
	assert_eq(first.order.recipe_id, &"burger")
	assert_eq(stock.count(&"bun"), 1, "the cook has not fetched anything yet")
	_sim.menu = [_content.recipe(&"burger"), _content.recipe(&"grilled_cheese")] as Array[RecipeDef]
	var second: CustomerAgent = _ordering_guest(12)
	assert_true(second._take_order(SimAgent.new()))
	assert_true(_sim.is_sold_out(&"burger"), "the last burger is promised to the first guest")
	assert_eq(second.order.recipe_id, &"grilled_cheese")
	_sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	var third: CustomerAgent = _ordering_guest(13)
	assert_true(third._take_order(SimAgent.new()))
	assert_null(third.order)
	assert_eq(third.leave_reason, &"out_of_stock", "nothing this guest would order is left")


## While nothing is sold out the guest makes the same single draw over the
## same menu as before #54; afterwards one draw covers the shorter list.
func test_order_choice_draw_is_stable() -> void:
	_start(_full_stock(), [&"burger", &"grilled_cheese", &"tomato_soup"] as Array[StringName])
	assert_true(_sim.world.clock.start_service())
	for seed: int in range(10):
		var oracle: RandomNumberGenerator = RandomNumberGenerator.new()
		oracle.seed = 900 + seed
		var expected: RecipeDef = _sim.menu[oracle.randi_range(0, _sim.menu.size() - 1)]
		var guest: CustomerAgent = _ordering_guest(900 + seed)
		assert_true(guest._take_order(SimAgent.new()))
		assert_eq(guest.order.recipe_id, expected.id)
		assert_eq(guest.rng.state, oracle.state, "exactly one draw at standard prices")
	assert_true(_sim.stock.take(&"soup_stock", _sim.stock.count(&"soup_stock")))
	var available: Array[RecipeDef] = _sim.available_menu()
	assert_eq(available.size(), 2)
	var later: RandomNumberGenerator = RandomNumberGenerator.new()
	later.seed = 950
	var choice: RecipeDef = available[later.randi_range(0, available.size() - 1)]
	var guest: CustomerAgent = _ordering_guest(950)
	assert_true(guest._take_order(SimAgent.new()))
	assert_eq(guest.order.recipe_id, choice.id)
	assert_eq(guest.rng.state, later.state)


## Morning buying can still refill the fridge, so nothing latches before service.
func test_nothing_sells_out_outside_service_and_mornings_reset() -> void:
	_start(Stock.new(), [&"burger"] as Array[StringName])
	_sim.refresh_sold_out()
	assert_false(_sim.is_sold_out(&"burger"))
	assert_eq(_sim.available_menu().size(), 1)
	assert_true(_sim.world.clock.start_service())
	_sim.advance()
	assert_true(_sim.is_sold_out(&"burger"))
	_sim.start_day()
	assert_false(_sim.is_sold_out(&"burger"))
	assert_true(_sim.stock_outs_today.is_empty())


func _on_left(guest: CustomerAgent, reason: StringName) -> void:
	_left[guest.id] = reason
