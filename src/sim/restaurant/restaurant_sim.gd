class_name RestaurantSim
extends RefCounted
## Owns one service's guests and tickets, independently of rendering or economy.

const VIBE_TUNING: VibeTuning = preload("res://data/balance/vibe.tres")

signal customer_arrived(customer: CustomerAgent)
signal customer_paid(customer: CustomerAgent, order: Order, amount: int)
signal customer_left(customer: CustomerAgent, reason: StringName)
## A detached, player-facing row without the scorer's internal cause id.
signal review_recorded(row: Dictionary)
## Emitted once service has closed and every guest's departure is recorded,
## so the day's numbers are final. Listen to this, not the clock, for reports.
signal service_closed(day: int)

var world: SimWorld
var orders: OrderBook = OrderBook.new()
var menu: Array[RecipeDef] = []
## Per-shop overrides; recipe resources and their standard prices stay unchanged.
var prices: Dictionary[StringName, int] = {}
var pricing_tuning: EconomyTuning = EconomyTuning.new()
## Shop-wide server capacity. Morning upgrades select one of these three values.
var carry_capacity: int:
	get:
		return _carry_capacity
	set(value):
		_carry_capacity = value if value == 1 or value == 2 or value == 4 else 1
var _carry_capacity: int = 1
## Ingredient stock shared with the game session. Replacing it also updates
## the live kitchen; direct construction retains an empty default inventory.
var stock: Stock = Stock.new():
	set(value):
		stock = value if value != null else Stock.new()
		if kitchen != null:
			kitchen.stock = stock
var kitchen: Kitchen
## Optional day-local dirt and its board poster. Main supplies the separate
## named cleanliness RNG when constructing the state; legacy sims stay inert.
var cleanliness: CleanlinessState = null
var clean_tasks: CleanTaskController = null
var spawner: CustomerSpawner
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Opt-in catalogue. An unconfigured sim retains the exact Regular arrival stream.
var customer_types: CustomerTypeCatalogue = null
var customer_level: int = 1
var served_today: int = 0
var lost_today: int = 0
var leave_reasons_today: Dictionary[StringName, int] = {}
## Optional review dependencies are injected by the game session. Keeping the
## stream separate leaves arrivals and individual guest choices unchanged.
var review_book: ReputationBook = ReputationBook.new()
var review_tuning: ReviewTuning
var review_quotes: ReviewQuotes
var review_rng: RandomNumberGenerator
var reviews_today: Array[Dictionary] = []
var reputation_before_day: float = 3.0
## Detached derived snapshot. Existing guests retain their own arrival effects.
var vibe_result: VibeModel.Result:
	get:
		return _copy_vibe(_vibe_result)
var _vibe_result: VibeModel.Result = VibeModel.Result.new()
## Where each staff role starts the day (from the layout).
var staff_spawns: Dictionary[StringName, Vector2i] = {}

var _departed: Dictionary[int, bool] = {}
## Dishes that ran out during today's service; they stay sold out until morning.
var sold_out_today: Dictionary[StringName, bool] = {}
## Ingredients that sold dishes out today, in the order it happened:
## {ingredient: StringName, minute: int (display clock), dishes: Array[StringName]}.
var stock_outs_today: Array[Dictionary] = []


## Builds the layout, its starting staff, and its tier-one menu.
## Only validated edited layouts opt into furniture covering a staff spawn.
static func create(layout: ShopLayout, content: ContentDB, seed: int, errors: Array[String],
		stock: Stock = null, with_kitchen: bool = true, allow_blocked_spawns: bool = false,
		roster: Array[StaffMember] = [], catalogue: StaffCatalogue = StaffRoster.CATALOGUE) -> RestaurantSim:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = ShopBuilder.build(layout, content, errors, allow_blocked_spawns)
	sim.rng.seed = seed
	sim.spawner = CustomerSpawner.new(sim.rng)
	for role: StringName in [&"cook", &"server", &"owner", &"cleaner"]:
		if not layout.staff_spawns.has(role):
			if role != &"cleaner":
				errors.append("%s: missing %s spawn" % [layout.id, role])
			continue
		sim.staff_spawns[role] = layout.staff_spawns[role]
	var people: Array[StaffMember] = roster if not roster.is_empty() else StaffRoster.new().members()
	# Default order remains cook, server, owner, preserving existing agent IDs.
	if not sim.set_staff_roster(people, catalogue):
		errors.append("Invalid staff roster")
	if sim.staff_spawns.has(&"owner"):
		var owner: OwnerAgent = OwnerAgent.new(sim.staff_spawns[&"owner"])
		owner.cell = sim.staff_spawns[&"owner"]
		sim.world.add_agent(owner)
	for recipe: RecipeDef in content.recipes():
		if recipe.unlock_tier == 1 and recipe.unlock_level <= 1:
			sim.menu.append(recipe)
	sim.stock = stock if stock != null else Stock.new()
	if with_kitchen:
		sim.kitchen = Kitchen.new(sim, content, sim.stock)
	sim.start_day()
	return sim


## Morning-only staffing changes retain existing people and the exact owner.
func set_staff_roster(people: Array[StaffMember], catalogue: StaffCatalogue = StaffRoster.CATALOGUE) -> bool:
	if world == null or world.clock.phase != SimClock.Phase.MORNING or people.size() < 2 or people.size() > StaffRoster.CAPACITY:
		return false
	var by_id: Dictionary[StringName, StaffMember] = {}
	var roles: Array[StringName] = []
	for member: StaffMember in people:
		if member == null or member.id.is_empty() or by_id.has(member.id) \
				or not StaffMember.ROLES.has(member.role) or not staff_spawns.has(member.role) \
				or catalogue.find_trait(member.trait_id) == null or member.skill < 1 or member.skill > 5 or member.wage < 0:
			return false
		by_id[member.id] = member
		roles.append(member.role)
	if not roles.has(&"cook") or not roles.has(&"server"):
		return false
	var retained: Dictionary[StringName, bool] = {}
	for agent: SimAgent in world.agents.duplicate():
		if not agent is StaffAgent or agent is OwnerAgent:
			continue
		var employee: StaffAgent = agent as StaffAgent
		if not by_id.has(employee.member_id):
			world.remove_agent(employee)
		else:
			var member: StaffMember = by_id[employee.member_id]
			employee.configure_member(member, catalogue.find_trait(member.trait_id))
			retained[employee.member_id] = true
	for member: StaffMember in people:
		if retained.has(member.id):
			continue
		var employee: StaffAgent = StaffAgent.new(member.role, member.skill)
		employee.configure_member(member, catalogue.find_trait(member.trait_id))
		employee.cell = staff_spawns[member.role]
		world.add_agent(employee)
	return true


## Any-phase selection update for an existing employee. The roster owns the
## saved state; this only copies next-pick choices onto the same live agent.
func apply_staff_job_priorities(member_id: StringName, choices: StaffJobPriorities) -> bool:
	if world == null or member_id.is_empty():
		return false
	for agent: SimAgent in world.agents:
		if agent is StaffAgent and not agent is OwnerAgent:
			var employee: StaffAgent = agent as StaffAgent
			if employee.member_id == member_id:
				return employee.set_job_priorities(choices)
	return false


## The factory's one live owner, or null for a manually constructed world.
func owner_agent() -> OwnerAgent:
	if world != null:
		for agent: SimAgent in world.agents:
			if agent is OwnerAgent:
				return agent as OwnerAgent
	return null


## Assignment changes priorities; the next owner tick releases disabled work.
func assign_owner(mode: StringName) -> bool:
	var selected_owner: OwnerAgent = owner_agent()
	return selected_owner != null and selected_owner.assign_mode(mode)


## Clears daily reports and redraws the first arrival; the caller opens the clock.
func start_day() -> void:
	served_today = 0
	lost_today = 0
	leave_reasons_today.clear()
	reviews_today.clear()
	sold_out_today.clear()
	stock_outs_today.clear()
	reputation_before_day = review_book.average()
	review_book.begin_day()
	_departed.clear()
	orders.prune_finished()
	if kitchen != null:
		kitchen.tidy_overnight()
	if clean_tasks != null:
		clean_tasks.tidy_overnight()
	elif cleanliness != null:
		cleanliness.tidy_overnight()
	_staff_to_posts()
	spawner.reset()


## Each morning staff start at their posts, with nothing in hand.
func _staff_to_posts() -> void:
	for agent: SimAgent in world.agents:
		if staff_spawns.has(agent.role) and agent is StaffAgent:
			var staff := agent as StaffAgent
			if staff.task != null:
				staff.on_removed(world)
			staff.cell = staff_spawns[agent.role]
			staff.clear_path()


## One fixed world tick, arrivals, then departed-guest cleanup.
func advance() -> void:
	var was_closed: bool = world.clock.phase == SimClock.Phase.CLOSED
	if clean_tasks != null:
		clean_tasks.sync_spots()
	world.advance()
	if kitchen != null:
		kitchen.advance()
	refresh_sold_out()
	spawner.advance(self)
	for customer: CustomerAgent in customers():
		if world.clock.phase == SimClock.Phase.CLOSED:
			# Guests who already paid are walking out happy; don't relabel them.
			if not customer.paid:
				customer.leave_reason = &"closing"
		elif customer.state != CustomerAgent.State.LEFT:
			continue
		world.remove_agent(customer)
		record_departure(customer)
	if world.clock.phase == SimClock.Phase.LAST_ORDERS and customers().is_empty():
		world.clock.notify_restaurant_empty()
	if not was_closed and world.clock.phase == SimClock.Phase.CLOSED:
		service_closed.emit(world.clock.day)


## Uses `random` for arrivals (the spawner and future guests). The game session
## passes GameState.rng(&"customers") so the stream is saved and seeded per run.
func use_rng(random: RandomNumberGenerator) -> void:
	rng = random
	spawner.rng = random


## Session installs authored content after loading owner progression. Deep-copy
## resources so authoring changes cannot rewrite the current world's configuration.
## No random draw or guest is changed by configuration or level updates.
func configure_customer_types(catalogue: CustomerTypeCatalogue, owner_level: int) -> bool:
	if catalogue == null or not catalogue.is_valid() or owner_level < 1:
		return false
	customer_types = catalogue.duplicate(true) as CustomerTypeCatalogue
	customer_level = owner_level
	return true


func set_customer_level(owner_level: int) -> bool:
	if owner_level < 1:
		return false
	customer_level = owner_level
	return true


## Install once for this world; the caller builds state with the named seeded
## cleanliness stream. No spot or extra draw exists in legacy sessions.
func configure_cleanliness(state: CleanlinessState, tuning: CleanlinessTuning) -> bool:
	if world == null or state == null or tuning == null or not tuning.is_valid() or cleanliness != null:
		return false
	cleanliness = state
	clean_tasks = CleanTaskController.new(world, state, tuning)
	clean_tasks.sync_spots()
	return true


## Enables departure reviews with a persistent book and a dedicated named RNG.
## Invalid or absent dependencies leave the existing visit lifecycle untouched.
func configure_reviews(book: ReputationBook, tuning: ReviewTuning,
		quotes: ReviewQuotes, random: RandomNumberGenerator) -> void:
	if book == null or tuning == null or not tuning.is_valid() \
			or quotes == null or not quotes.is_valid() or random == null:
		return
	review_book = book
	review_tuning = tuning
	review_quotes = quotes
	review_rng = random


## Recomputed by the session on layout, paint, menu or load changes, never ticks.
## Invalid inputs install a neutral result; neither this argument nor guests mutate.
func set_vibe(result: VibeModel.Result) -> void:
	_vibe_result = _copy_vibe(result)


static func _copy_vibe(source: VibeModel.Result, tuning: VibeTuning = VIBE_TUNING) -> VibeModel.Result:
	var copy: VibeModel.Result = VibeModel.Result.new()
	if source == null or not source.valid or tuning == null or not tuning.is_valid():
		return copy
	for value: float in [source.score, source.decor_points, source.variety_points,
			source.theme_points, source.lamp_points, source.crowding_penalty,
			source.theme_share, source.patience_multiplier, source.raw_review_bonus,
			source.arrival_theme_strength, source.crowding_density]:
		if not is_finite(value) or value < 0.0:
			return copy
	for component: float in [source.decor_points, source.variety_points,
			source.theme_points, source.lamp_points, source.crowding_penalty]:
		if component > 100.0:
			return copy
	if source.score > tuning.score_cap or source.patience_multiplier < 1.0 \
			or source.patience_multiplier > 1.0 + tuning.max_patience_bonus or source.raw_review_bonus > tuning.max_review_bonus \
			or source.theme_share > 1.0 or source.arrival_theme_strength > 1.0 \
			or source.crowding_density > 1.0 or source.interior_cells < 0 \
			or source.occupied_normal_cells < 0 or source.occupied_normal_cells > source.interior_cells \
			or (not source.active_theme.is_empty() and not VibeTuning.KNOWN_THEMES.has(source.active_theme)):
		return copy
	if (source.score == 0.0 and (source.patience_multiplier != 1.0 \
			or source.raw_review_bonus != 0.0 or source.arrival_theme_strength != 0.0)) \
			or (source.active_theme.is_empty() and source.arrival_theme_strength != 0.0) \
			or (not source.active_theme.is_empty() and source.theme_label.strip_edges().is_empty()):
		return copy
	copy.valid = true
	copy.score = source.score
	copy.decor_points = source.decor_points
	copy.variety_points = source.variety_points
	copy.theme_points = source.theme_points
	copy.lamp_points = source.lamp_points
	copy.crowding_penalty = source.crowding_penalty
	copy.active_theme = source.active_theme
	copy.theme_label = source.theme_label
	copy.theme_share = source.theme_share
	copy.patience_multiplier = source.patience_multiplier
	copy.raw_review_bonus = source.raw_review_bonus
	copy.arrival_theme_strength = source.arrival_theme_strength
	copy.interior_cells = source.interior_cells
	copy.occupied_normal_cells = source.occupied_normal_cells
	copy.crowding_density = source.crowding_density
	return copy


## Neutral/disabled budgets stay exact. Saturating protects int64 rounding.
static func _vibe_patience(budget: int, multiplier: float, tuning: VibeTuning = VIBE_TUNING) -> int:
	if budget <= 0 or not is_finite(multiplier) or multiplier <= 1.0:
		return budget
	if tuning == null or not tuning.is_valid():
		return budget
	var maximum: float = 1.0 + tuning.max_patience_bonus
	if maximum <= 1.0:
		return budget
	var scaled: float = float(budget) * minf(multiplier, maximum)
	if scaled >= float(9223372036854775807):
		return 9223372036854775807
	return roundi(scaled)


## Latches every menu dish the fridge itself can no longer cover. Stock only
## falls during service, so this lasts for the day. Only a real kitchen's
## service changes it: morning buying can still refill the fridge.
func refresh_sold_out() -> void:
	if not _in_service():
		return
	for recipe: RecipeDef in menu:
		if recipe == null or sold_out_today.has(recipe.id):
			continue
		var short: StringName = _short_ingredient(recipe, {})
		if not short.is_empty():
			_mark_sold_out(recipe.id, short)


func is_sold_out(recipe_id: StringName) -> bool:
	return sold_out_today.has(recipe_id)


## Today's menu without dishes that cannot be cooked for a new guest: the
## sold-out ones, and for now those whose last portions are promised to
## accepted tickets. A promised portion returns if its ticket is cancelled
## before the cook fetches it, so that dish is only held back, not sold out.
func available_menu() -> Array[RecipeDef]:
	refresh_sold_out()
	var committed: Dictionary[StringName, int] = {}
	if _in_service():
		committed = kitchen.committed_ingredients()
	var available: Array[RecipeDef] = []
	for recipe: RecipeDef in menu:
		if recipe != null and not sold_out_today.has(recipe.id) \
				and (committed.is_empty() or _short_ingredient(recipe, committed).is_empty()):
			available.append(recipe)
	return available


func _in_service() -> bool:
	return kitchen != null and stock != null and world != null \
		and (world.clock.phase == SimClock.Phase.OPEN or world.clock.phase == SimClock.Phase.LAST_ORDERS)


## The first ingredient, in recipe order, that stock less `reserved` lacks.
func _short_ingredient(recipe: RecipeDef, reserved: Dictionary[StringName, int]) -> StringName:
	var needs: Dictionary[StringName, int] = {}
	var order: Array[StringName] = []
	for ingredient: IngredientDef in recipe.ingredients:
		if ingredient == null:
			continue
		if not needs.has(ingredient.id):
			order.append(ingredient.id)
		needs[ingredient.id] = needs.get(ingredient.id, 0) + 1
	for id: StringName in order:
		if stock.count(id) - reserved.get(id, 0) < needs[id]:
			return id
	return &""


## The shop clock as a minute of the day, continuing past closing time while
## last orders run (the HUD clock stops at closing).
func service_minute() -> int:
	var clock: SimClock = world.clock
	if clock.phase != SimClock.Phase.LAST_ORDERS:
		return clock.display_minutes()
	var span: int = clock.display_close_minute - clock.display_open_minute
	return clock.display_close_minute + floori(float(clock.phase_tick) * float(span) / float(maxi(clock.open_ticks, 1)))


func _mark_sold_out(recipe_id: StringName, ingredient_id: StringName) -> void:
	sold_out_today[recipe_id] = true
	for event: Dictionary in stock_outs_today:
		if event["ingredient"] == ingredient_id:
			(event["dishes"] as Array[StringName]).append(recipe_id)
			world.log_event("%s sold out" % recipe_id)
			return
	var dishes: Array[StringName] = [recipe_id]
	stock_outs_today.append({"ingredient": ingredient_id,
		"minute": service_minute(), "dishes": dishes})
	world.log_event("%s ran out: %s sold out" % [ingredient_id, recipe_id])


## Missing overrides use the unchanged content price.
func price_of(recipe: RecipeDef) -> int:
	if recipe == null:
		return 0
	return maxi(0, prices.get(recipe.id, recipe.standard_price))


## No chance below/equal to standard; callers must not draw RNG when this is 0.
func price_walkout_chance(recipe: RecipeDef, budget_multiplier: float = 1.0) -> float:
	if recipe == null or recipe.standard_price <= 0 or pricing_tuning == null \
			or not is_finite(budget_multiplier) or budget_multiplier <= 0.0:
		return 0.0
	var ratio: float = float(price_of(recipe)) / float(recipe.standard_price)
	if ratio <= 1.0:
		return 0.0
	var sensitivity: float = pricing_tuning.price_sensitivity
	var maximum: float = pricing_tuning.max_price_walkout
	if not is_finite(sensitivity) or not is_finite(maximum):
		return 0.0
	return clampf(((ratio - 1.0) / budget_multiplier) * maxf(sensitivity, 0.0), 0.0, clampf(maximum, 0.0, 1.0))


## Adds a guest using an independent random stream (also useful for scenarios).
func add_customer(entry: Vector2i, random: RandomNumberGenerator, kind: CustomerType = null) -> CustomerAgent:
	if kind != null and not kind.is_valid():
		return null
	var customer: CustomerAgent = CustomerAgent.new(self, random)
	if kind != null:
		customer.configure_type(kind)
	customer.cell = entry
	# Only a real service arrival can dirty the floor or consume its stream.
	if cleanliness != null and world.clock.phase == SimClock.Phase.OPEN:
		customer.arrival_dirt_fraction = cleanliness.dirt_fraction()
		var patience_scale: float = cleanliness.patience_multiplier()
		customer.queue_patience = maxi(1, roundi(float(customer.queue_patience) * patience_scale))
		customer.food_patience = maxi(1, roundi(float(customer.food_patience) * patience_scale))
		var spot: Vector2i = cleanliness.try_spawn_on_arrival(entry)
		if spot != SimGrid.NO_CELL and clean_tasks != null:
			clean_tasks.sync_spots()
	if world.clock.phase == SimClock.Phase.OPEN:
		customer.queue_patience = _vibe_patience(customer.queue_patience, _vibe_result.patience_multiplier)
		customer.food_patience = _vibe_patience(customer.food_patience, _vibe_result.patience_multiplier)
		customer.vibe_review_bonus = _vibe_result.raw_review_bonus
		if _vibe_result.score > 0.0 and not _vibe_result.active_theme.is_empty():
			customer.vibe_theme_label = _vibe_result.theme_label
	world.add_agent(customer)
	world.log_event("Guest #%d arrived" % customer.id)
	customer_arrived.emit(customer)
	return customer


## Current guests in stable agent-id order.
func customers() -> Array[CustomerAgent]:
	var out: Array[CustomerAgent] = []
	for agent: SimAgent in world.agents:
		if agent is CustomerAgent:
			out.append(agent as CustomerAgent)
	return out


## Called once by a paying guest; listeners connect economy or reports here.
func pay(customer: CustomerAgent, order: Order) -> void:
	if customer.paid:
		return
	customer.paid = true
	served_today += 1
	customer_paid.emit(customer, order, order.price)


## Accounts for a departure once, including direct world removal and repeated cleanup.
func record_departure(customer: CustomerAgent) -> void:
	if customer.departure_recorded or _departed.has(customer.id):
		return
	_departed[customer.id] = true
	customer.departure_recorded = true
	if cleanliness != null and customer.paid and customer.seat_cell != SimGrid.NO_CELL:
		if cleanliness.try_spawn_at_departed_seat(customer.seat_cell) and clean_tasks != null:
			clean_tasks.sync_spots()
	if not customer.paid and customer.leave_reason == &"happy":
		customer.leave_reason = &"removed"
	var reason: StringName = customer.leave_reason
	leave_reasons_today[reason] = leave_reasons_today.get(reason, 0) + 1
	if not customer.paid:
		lost_today += 1
	world.log_event("Guest #%d left: %s" % [customer.id, reason])
	if review_book != null and review_tuning != null and review_quotes != null and review_rng != null:
		var standard_price: int = 0
		if customer.order != null:
			for recipe: RecipeDef in menu:
				if recipe.id == customer.order.recipe_id:
					standard_price = recipe.standard_price
					break
		var visit: ReviewVisit = customer.review_visit(standard_price, customer.arrival_dirt_fraction)
		# A paid guest removed at the closing cutoff retains their happy report
		# reason, but the forced departure must not sample a late review.
		visit.closing = visit.closing or world.clock.phase == SimClock.Phase.CLOSED
		var result: Dictionary = review_book.record_visit(visit, review_tuning, review_quotes, review_rng)
		if not result.is_empty():
			var row: Dictionary = {"stars": result["stars"], "quote": result["quote"],
				"before": result["before"], "after": result["after"]}
			reviews_today.append(row)
			review_recorded.emit(row.duplicate())
	customer_left.emit(customer, reason)
