extends TestCase
## Traits exercised through real movement, order callbacks and kitchen tasks.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const CATALOGUE: StaffCatalogue = preload("res://data/staff/traits.tres")

var _content: ContentDB


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())


func after_each() -> void:
	_content = null


func test_quick_advances_real_walk_progress_fifteen_percent_faster() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.from_ascii(PackedStringArray(["............", "............"])))
	var steady: StaffAgent = _employee(&"walker_steady", &"cook", &"steady")
	var quick: StaffAgent = _employee(&"walker_quick", &"cook", &"quick")
	for staff: StaffAgent in [steady, quick]:
		world.add_agent(staff)
		assert_true(staff.set_destination(world.grid, Vector2i(10, 0)))
	for tick: int in range(3):
		assert_eq(steady.step_move(world), SimAgent.MoveResult.MOVING)
		assert_eq(quick.step_move(world), SimAgent.MoveResult.MOVING)
	var start: float = GridMath.cell_to_world(Vector2i.ZERO).x
	var steady_distance: float = _drawn_x(steady) - start
	var quick_distance: float = _drawn_x(quick) - start
	assert_true(quick_distance > steady_distance)
	assert_almost_eq(quick_distance / steady_distance, 1.15, 0.000001)
	assert_almost_eq(quick.work_speed(&"cook"), steady.work_speed(&"cook"))


func test_default_factory_keeps_legacy_order_stats_and_customer_random_draws() -> void:
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 72, errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(sim.world.agents.size(), 3)
	for index: int in range(3):
		var agent: StaffAgent = sim.world.agents[index] as StaffAgent
		assert_eq(agent.id, index + 1)
		assert_eq(agent.role, [&"cook", &"server", &"owner"][index])
		assert_eq(agent.skill_for(agent.role), 3)
		assert_almost_eq(agent.move_speed, 0.25)
		assert_almost_eq(agent.cook_quality_bonus, 0.0)
		assert_almost_eq(agent.food_patience_multiplier, 1.0)
		assert_eq(agent.wage, [30, 25, 0][index])
	assert_eq(sim.owner_agent().current_mode(), &"rest")
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 72
	random.randi_range(sim.spawner.min_gap, sim.spawner.max_gap)
	assert_eq(sim.rng.state, random.state, "default construction draws only the existing first customer gap")


func test_reapplying_quick_never_compounds_and_steady_restores_the_base_speed() -> void:
	var member: StaffMember = _member(&"reconfigured", &"cook", &"quick")
	var staff: StaffAgent = StaffAgent.new(&"cook", 3)
	staff.move_speed = 0.4
	for refresh: int in range(10):
		staff.configure_member(member, CATALOGUE.trait(&"quick"))
	assert_almost_eq(staff.move_speed, 0.4 * 1.15)
	member.trait_id = &"steady"
	staff.configure_member(member, CATALOGUE.trait(&"steady"))
	assert_almost_eq(staff.move_speed, 0.4)
	assert_almost_eq(staff.cook_quality_bonus, 0.0)
	assert_almost_eq(staff.food_patience_multiplier, 1.0)


func test_careful_quality_comes_from_the_person_who_really_completes_cooking() -> void:
	var baseline: Dictionary = _cook_meal(&"steady", 3, false)
	var careful: Dictionary = _cook_meal(&"careful", 3, false)
	assert_true(baseline["completed"])
	assert_true(careful["completed"])
	assert_eq(careful["claimed_by"], careful["cook_id"], "the added cook, not the first cook, finishes the task")
	assert_ne(careful["cook_id"], careful["idle_cook_id"])
	assert_almost_eq(float(careful["quality"]) - float(baseline["quality"]), 0.05)


func test_careful_quality_and_equipment_bonuses_still_clamp_at_one() -> void:
	var result: Dictionary = _cook_meal(&"careful", 5, true)
	assert_true(result["completed"])
	assert_almost_eq(float(result["quality"]), 1.0)


func test_cheerful_order_taking_increases_waiting_budget_once_without_rng_or_counter_reset() -> void:
	var sim: RestaurantSim = _restaurant([] as Array[StaffMember], false)
	var cheerful: StaffAgent = _employee(&"cheerful", &"server", &"cheerful")
	var steady: StaffAgent = _employee(&"steady", &"server", &"steady")
	var guest: CustomerAgent = _ordering_guest(sim, 720081)
	var control: CustomerAgent = _ordering_guest(sim, 720081)
	assert_true(guest.call("_take_order", cheerful))
	assert_true(control.call("_take_order", steady))
	assert_eq(guest.state, CustomerAgent.State.WAITING_FOOD)
	assert_eq(guest.order.state, Order.State.PLACED, "the bonus is already useful before delivery")
	assert_eq(guest.food_patience, 550)
	assert_eq(control.food_patience, 500)
	assert_eq(guest._food_wait, 137)
	assert_eq(guest._queue_wait, 11)
	assert_eq(guest.rng.state, control.rng.state, "the trait adds no guest random draw")
	var ticket: Order = guest.order
	var state: int = guest.rng.state
	assert_true(guest.call("_take_order", cheerful))
	assert_true(guest.order == ticket)
	assert_eq(guest.food_patience, 550, "a replayed task cannot stack the bonus")
	assert_eq(guest._food_wait, 137)
	assert_eq(guest.rng.state, state)


func test_real_cheerful_service_keeps_the_order_time_bonus_unchanged_at_delivery() -> void:
	var people: Array[StaffMember] = CATALOGUE.defaults(TUNING)
	people[1].trait_id = &"cheerful"
	var sim: RestaurantSim = _restaurant(people)
	var guest: CustomerAgent = _guest(sim)
	assert_true(sim.world.clock.start_service())
	var waiting_seen: bool = false
	for tick: int in range(3000):
		sim.advance()
		if guest.order != null and guest.state == CustomerAgent.State.WAITING_FOOD:
			waiting_seen = true
			assert_eq(guest.food_patience, 5500)
			break
	assert_true(waiting_seen, "the real server takes an order before food arrives")
	for tick: int in range(3000):
		sim.advance()
		if guest.order != null and guest.order.state == Order.State.DELIVERED:
			break
	assert_not_null(guest.order)
	if guest.order == null:
		return
	assert_eq(guest.order.state, Order.State.DELIVERED)
	assert_eq(guest.food_patience, 5500, "delivery adds no second patience bonus")


func test_roster_traits_leave_the_exact_owner_neutral_and_preserve_their_assignment() -> void:
	var people: Array[StaffMember] = CATALOGUE.defaults(TUNING)
	people[0].trait_id = &"quick"
	people[1].trait_id = &"cheerful"
	var sim: RestaurantSim = _restaurant(people, false)
	var owner: OwnerAgent = sim.owner_agent()
	assert_not_null(owner)
	if owner == null:
		return
	assert_eq(sim.world.agents.size(), 3)
	assert_eq(owner.member_id, &"")
	assert_eq(owner.wage, 0)
	assert_eq(owner.trait_id, &"steady")
	assert_almost_eq(owner.move_speed, 0.25)
	assert_almost_eq(owner.cook_quality_bonus, 0.0)
	assert_almost_eq(owner.food_patience_multiplier, 1.0)
	assert_true(owner.assign_mode(&"kitchen"))
	people.append(_member(&"another_cook", &"cook", &"careful"))
	assert_true(sim.set_staff_roster(people, CATALOGUE))
	assert_true(sim.owner_agent() == owner)
	assert_eq(owner.current_mode(), &"kitchen")
	assert_eq(owner.role, &"owner")
	assert_eq(owner.skill_for(&"cook"), 3)
	assert_eq(owner.skill_for(&"server"), 3)
	assert_eq(owner.wage, 0)
	assert_almost_eq(owner.move_speed, 0.25)
	assert_almost_eq(owner.cook_quality_bonus, 0.0)
	assert_almost_eq(owner.food_patience_multiplier, 1.0)


func _member(id: StringName, role: StringName, trait_id: StringName, skill: int = 3) -> StaffMember:
	var member: StaffMember = StaffMember.new()
	member.id = id
	member.display_name = String(id)
	member.role = role
	member.skill = skill
	member.wage = TUNING.staff_wage(role, skill)
	member.trait_id = trait_id
	return member


func _employee(id: StringName, role: StringName, trait_id: StringName) -> StaffAgent:
	var member: StaffMember = _member(id, role, trait_id)
	var staff: StaffAgent = StaffAgent.new(role, member.skill)
	staff.configure_member(member, CATALOGUE.trait(trait_id))
	return staff


func _drawn_x(agent: SimAgent) -> float:
	return GridMath.cell_to_world(agent.cell).lerp(GridMath.cell_to_world(agent.next_cell()), agent.move_progress).x


func _restaurant(people: Array[StaffMember] = [], with_kitchen: bool = true) -> RestaurantSim:
	var stock: Stock = Stock.new()
	for ingredient: IngredientDef in _content.ingredients():
		stock.add(ingredient.id, 100, 1)
	var errors: Array[String] = []
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, _content, 720072, errors, stock, with_kitchen, false, people, CATALOGUE)
	assert_eq(errors, [] as Array[String])
	sim.menu = [_content.recipe(&"burger")] as Array[RecipeDef]
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.start_day()
	return sim


func _ordering_guest(sim: RestaurantSim, seed: int) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random)
	guest.state = CustomerAgent.State.ORDERING
	guest.food_patience = 500
	guest._food_wait = 137
	guest._queue_wait = 11
	return guest


func _guest(sim: RestaurantSim) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 720082
	var guest: CustomerAgent = sim.add_customer(sim.world.grid.entries()[0], random)
	guest.food_patience = 5000
	guest.eat_ticks = 3
	return guest


func _cook_meal(trait_id: StringName, skill: int, upgraded: bool) -> Dictionary:
	var people: Array[StaffMember] = CATALOGUE.defaults(TUNING)
	people.append(_member(&"finishing_cook", &"cook", trait_id, skill))
	var sim: RestaurantSim = _restaurant(people)
	var idle: StaffAgent
	var cook: StaffAgent
	for agent: SimAgent in sim.world.agents:
		if agent is StaffAgent and agent.role == &"cook":
			var staff: StaffAgent = agent as StaffAgent
			if staff.member_id == &"finishing_cook":
				cook = staff
			else:
				idle = staff
	assert_not_null(cook)
	assert_not_null(idle)
	if cook == null or idle == null:
		return {"completed": false, "quality": 0.0, "claimed_by": -1, "cook_id": -2, "idle_cook_id": -3}
	idle.priorities[&"cook"] = 0
	idle.priorities[&"any"] = 0
	if upgraded:
		for id: StringName in [&"prep_counter", &"stove"]:
			var item: PlacedItem = ShopBuilder.items_with_def(sim.world, id)[0]
			var definition: ItemDef = item.def.duplicate() as ItemDef
			definition.quality_bonus = 0.4
			item.def = definition
	var guest: CustomerAgent = _guest(sim)
	var cooking: SimTask = null
	assert_true(sim.world.clock.start_service())
	for tick: int in range(3000):
		sim.advance()
		if cook.task != null and cook.task.kind == &"cook":
			cooking = cook.task
		if guest.order != null and guest.order.state == Order.State.DELIVERED:
			break
	assert_not_null(guest.order)
	assert_not_null(cooking, "ordinary staff claiming must produce the cook task")
	var completed: bool = guest.order != null and guest.order.state == Order.State.DELIVERED \
		and cooking != null and cooking.state == SimTask.State.DONE
	return {"completed": completed, "quality": guest.order.quality if guest.order != null else 0.0,
		"claimed_by": cooking.claimed_by if cooking != null else -1, "cook_id": cook.id, "idle_cook_id": idle.id}
