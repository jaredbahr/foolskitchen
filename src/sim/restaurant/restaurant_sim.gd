class_name RestaurantSim
extends RefCounted
## Owns one service's guests and tickets, independently of rendering or economy.

const VIBE_TUNING: VibeTuning = preload("res://data/balance/vibe.tres")
const VISIT_TUNING: VisitTuning = preload("res://data/balance/visits.tres")
const RESTROOM_TUNING: RestroomTuning = preload("res://data/balance/restroom.tres")

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
## Who visits when, and how long a drinks-only visit lasts (FK-083).
var visit_tuning: VisitTuning = VISIT_TUNING
## Session-latched deterministic growth, independent of visit-kind/hour weights.
var demand_factor: float = 1.0
var demand_tuning: DemandTuning = null
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
		if dock != null:
			dock.stock = stock
var kitchen: Kitchen
## Visible daytime deliveries (FK-099): the delivery person, crates and the
## staff work of putting them away. Idle (and invisible) until Main hands it a
## delivery due during service.
var dock: DeliveryDock
## Optional day-local dirt and its board poster. Main supplies the separate
## named cleanliness RNG when constructing the state; legacy sims stay inert.
var cleanliness: CleanlinessState = null
var clean_tasks: CleanTaskController = null
var spawner: CustomerSpawner
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Opt-in catalogue. An unconfigured sim retains the exact Regular arrival stream.
var customer_types: CustomerTypeCatalogue = null
var customer_level: int = 1
## Optional persistent cast. A null cast preserves all earlier simulation callers.
var regulars: RegularCast = null
## The session supplies a lazy named stream; no stream is created before promotion.
var regular_rng_provider: Callable
var regular_recipe_labels: Dictionary[StringName, String] = {}
var _regular_cohort_index: int = 0
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
## Restrooms (FK-101): the threshold, visit length and review terms.
var restroom_tuning: RestroomTuning = RESTROOM_TUNING
## Where each staff role starts the day (from the layout).
var staff_spawns: Dictionary[StringName, Vector2i] = {}

var _departed: Dictionary[int, bool] = {}
## Restroom toilets and dining seats, recounted after a layout change.
var _layout_counted: bool = false
var _toilets: Array[int] = []
var _seats: int = 0
## Dishes that ran out during today's service; they stay sold out until a
## delivery covers them again or the next morning.
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
	sim.world.grid.cells_changed.connect(sim._on_layout_changed)
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
		# Drinks join only through the session's menu, once their station
		# stands; a dish needing a station type no item provides (a croissant
		# warmed at the coffee machine) waits for it the same way (FK-083).
		if recipe.unlock_tier == 1 and recipe.unlock_level <= 1 and not recipe.is_drink() \
				and not _needs_absent_station(recipe, sim.world):
			sim.menu.append(recipe)
	sim.stock = stock if stock != null else Stock.new()
	if with_kitchen:
		sim.kitchen = Kitchen.new(sim, content, sim.stock)
	sim.dock = DeliveryDock.new(sim.world, sim.stock, StorageSpace.kinds_of(content))
	sim.dock.stored.connect(sim._on_dock_stored)
	sim.start_day()
	return sim


## A recipe step at a station type this world has never placed. Worlds built
## without any stations (customer-only fixtures) keep their full default menu.
static func _needs_absent_station(recipe: RecipeDef, built: SimWorld) -> bool:
	var stations: Dictionary[StringName, bool] = {}
	for placed: PlacedItem in built.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition != null and definition.category == ItemDef.Category.STATION:
			stations[definition.station_type] = true
	if stations.is_empty():
		return false
	for step: RecipeStep in recipe.steps:
		if step != null and not stations.has(step.station_type):
			return true
	return false


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
	_regular_cohort_index = 0
	if regulars != null:
		regulars.begin_day(world.clock.day)
	served_today = 0
	lost_today = 0
	leave_reasons_today.clear()
	reviews_today.clear()
	sold_out_today.clear()
	stock_outs_today.clear()
	reputation_before_day = review_book.average()
	review_book.begin_day()
	_departed.clear()
	# Nothing stays in transit overnight: a delivery still waiting is stored.
	if dock != null:
		dock.store_all()
	orders.prune_finished()
	if kitchen != null:
		kitchen.tidy_overnight()
	if clean_tasks != null:
		clean_tasks.tidy_overnight()
	elif cleanliness != null:
		cleanliness.tidy_overnight()
	_staff_to_posts()
	spawner.reset(arrival_rate())


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
	if dock != null:
		dock.advance()
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
		# Anything not put away by closing is stored, before the day's books.
		if dock != null:
			dock.store_all()
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


## Latches every menu dish the fridge itself can no longer cover. It stays
## sold out until a delivery during service covers it again
## (restock_sold_out, FK-087) or the next morning.
func refresh_sold_out() -> void:
	if not _in_service():
		return
	for recipe: RecipeDef in menu:
		if recipe == null or sold_out_today.has(recipe.id):
			continue
		var short: StringName = _short_ingredient(recipe, {})
		if not short.is_empty():
			_mark_sold_out(recipe.id, short)


## A delivery during service (FK-087) brings dishes back: those the stock
## can cover again leave today's sold-out list. Returns how many came back.
func restock_sold_out() -> int:
	var back: Array[StringName] = []
	for recipe: RecipeDef in menu:
		if recipe != null and sold_out_today.has(recipe.id) and _short_ingredient(recipe, {}).is_empty():
			back.append(recipe.id)
	for id: StringName in back:
		sold_out_today.erase(id)
	return back.size()


## Goods put away (or stored at closing) can bring sold-out dishes back.
func _on_dock_stored(_lines: Array[Dictionary]) -> void:
	if _in_service():
		restock_sold_out()


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


## Today's available dishes of one order type, in menu order (FK-083).
func available_of(order_type: StringName, available: Array[RecipeDef] = []) -> Array[RecipeDef]:
	var source: Array[RecipeDef] = available if not available.is_empty() else available_menu()
	var out: Array[RecipeDef] = []
	for recipe: RecipeDef in source:
		if recipe.order_type == order_type:
			out.append(recipe)
	return out


## Today's available drinks of any kind, in menu order.
func available_drinks() -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for recipe: RecipeDef in available_menu():
		if recipe.is_drink():
			out.append(recipe)
	return out


## The visit kinds a guest can come for right now, in RecipeDef.ORDER_TYPES
## order. A menu with nothing available still offers food, so that guest
## leaves "out of stock" exactly as before.
## It reads today's menu and sold-out marks without refreshing them.
func visit_kinds() -> Array[StringName]:
	var kinds: Array[StringName] = []
	for kind: StringName in RecipeDef.ORDER_TYPES:
		for recipe: RecipeDef in menu:
			if recipe != null and recipe.order_type == kind and not sold_out_today.has(recipe.id):
				kinds.append(kind)
				break
	if kinds.is_empty():
		kinds.append(RecipeDef.FOOD)
	return kinds


## Arrivals relative to the default rate at the current shop minute: exactly
## 1.0 for a food-only menu at a full-weight hour (all default opening hours).
func arrival_rate() -> float:
	var base: float = 1.0
	if visit_tuning != null and visit_tuning.is_valid() and world != null:
		base = visit_tuning.arrival_rate(visit_kinds(), world.clock.display_minutes())
	return base * demand_factor


## Configuration and live menu edits never redraw the current countdown.
func configure_demand(tuning: DemandTuning) -> void:
	demand_tuning = tuning if tuning != null and tuning.is_valid() else null
	demand_factor = 1.0


func set_demand_factor(value: float) -> bool:
	if demand_tuning == null or not demand_tuning.is_valid() or not is_finite(value) \
			or value <= 0.0 or value > demand_tuning.total_cap:
		return false
	demand_factor = value
	return true


## Read-only menu-kind hours for the same service as expected_demand_guests.
## Keep the typed visit resource beside its owning sim; callers receive only
## detached primitive weights, including partial opening hours.
func expected_visit_weights() -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	if world == null:
		return result
	var clock: SimClock = world.clock
	for kind: StringName in RecipeDef.ORDER_TYPES:
		var weight: float = 0.0
		for hour: int in range(24):
			var minutes: int = maxi(0, mini(clock.display_close_minute, (hour + 1) * 60)
				- maxi(clock.display_open_minute, hour * 60))
			weight += minutes * (visit_tuning.weight(kind, hour * 60) if visit_tuning != null else 0.0)
		result[kind] = weight
	return result


## Read-only approximation from this restaurant's actual opening hours, menu
## weights and authored base gaps. Parties already space arrivals by headcount.
func expected_demand_guests(factor: float) -> int:
	if world == null or not is_finite(factor) or factor <= 0.0:
		return 0
	var clock: SimClock = world.clock
	var minutes: int = clock.display_close_minute - clock.display_open_minute
	var mean_gap: float = float(spawner.min_gap + spawner.max_gap) / 2.0
	if minutes <= 0 or clock.open_ticks <= 0 or mean_gap <= 0.0:
		return 0
	var weight: float = 0.0
	var kinds: Array[StringName] = visit_kinds()
	var valid_visits: bool = visit_tuning != null and visit_tuning.is_valid()
	for minute: int in range(clock.display_open_minute, clock.display_close_minute):
		weight += visit_tuning.arrival_rate(kinds, minute) if valid_visits else 1.0
	return maxi(0, roundi(float(clock.open_ticks) * weight / float(minutes) * factor / mean_gap))


## Where staff stand to take an order or hand over a meal or drink at a seat.
## A stool facing a serve-across counter is served from the far side when
## that cell is clear and connected; otherwise from the seat's neighbours.
func service_cells(table_item_id: int, seat_cell: Vector2i) -> Array[Vector2i]:
	var across: Vector2i = across_cell(table_item_id, seat_cell)
	if across != SimGrid.NO_CELL:
		return [across] as Array[Vector2i]
	return world.grid.walkable_neighbours(seat_cell)


## The cell behind a serve-across counter, opposite this seat, or NO_CELL.
func across_cell(table_item_id: int, seat_cell: Vector2i) -> Vector2i:
	var table: PlacedItem = world.grid.item(table_item_id)
	var definition: ItemDef = table.def as ItemDef if table != null else null
	if definition == null or not definition.serve_across or seat_cell == SimGrid.NO_CELL:
		return SimGrid.NO_CELL
	for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var front: Vector2i = seat_cell + direction
		if not table.cells.has(front):
			continue
		var behind: Vector2i = front + direction
		# A stool on the far side is another guest's seat, not the bartender's spot.
		if table.cells.has(behind) or table.seat_cells.has(behind):
			continue
		if world.grid.in_bounds(behind) and world.grid.is_walkable(behind) \
				and not world.grid.edge_blocked(front, behind) and world.grid.is_reachable(seat_cell, behind):
			return behind
	return SimGrid.NO_CELL


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
	return _install_customer(entry, random, kind)


## A guest who came for `visit` (RecipeDef.FOOD, COFFEE or DRINKS; FK-083).
## A food visit is exactly add_customer.
func add_visitor(entry: Vector2i, random: RandomNumberGenerator, kind: CustomerType,
		visit: StringName) -> CustomerAgent:
	if visit == RecipeDef.FOOD:
		return add_customer(entry, random, kind)
	return _install_customer(entry, random, kind, true, visit)


## Party installation defers publication until every member has a shared visit.
func _install_customer(entry: Vector2i, random: RandomNumberGenerator,
		kind: CustomerType = null, publish: bool = true, visit: StringName = RecipeDef.FOOD) -> CustomerAgent:
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
	if world.clock.phase == SimClock.Phase.OPEN and has_restroom() and restroom_tuning != null:
		customer.restroom_bonus = restroom_tuning.restroom_review_bonus
	if world.clock.phase == SimClock.Phase.OPEN:
		customer.queue_patience = _vibe_patience(customer.queue_patience, _vibe_result.patience_multiplier)
		customer.food_patience = _vibe_patience(customer.food_patience, _vibe_result.patience_multiplier)
		customer.vibe_review_bonus = _vibe_result.raw_review_bonus
		if _vibe_result.score > 0.0 and not _vibe_result.active_theme.is_empty():
			customer.vibe_theme_label = _vibe_result.theme_label
	if publish:
		visit = _configure_regular_customer(customer, visit)
	# Set the duration once, after a returning regular has chosen their usual.
	customer.set_visit_kind(visit, visit_tuning)
	world.add_agent(customer)
	if publish:
		_publish_customer_arrival(customer)
	return customer


## A due cast member takes the place of an ordinary solo Regular arrival;
## neither the arrival clock nor its existing draws are changed.
func _configure_regular_customer(customer: CustomerAgent, visit: StringName) -> StringName:
	if regulars == null or customer.customer_type_id != &"regular" \
			or world.clock.phase != SimClock.Phase.OPEN:
		return visit
	var profile: RegularProfile = regulars.due_regular(world.clock.day)
	if profile == null:
		customer.repeat_guest_key = "guest_%d" % (_regular_cohort_index % 16)
		_regular_cohort_index += 1
		return visit
	if not regular_rng_provider.is_valid() or not regulars.mark_arrived(profile,
			world.clock.day, regular_rng_provider.call() as RandomNumberGenerator):
		return visit
	customer.regular_profile = profile
	customer.display_name = profile.display_name
	customer.regular_arrival_tick = world.now
	customer.regular_favourite_label = regular_recipe_labels.get(profile.favourite_dish, "Favourite dish")
	for recipe: RecipeDef in menu:
		if recipe.id == profile.favourite_dish:
			customer.regular_favourite_available = true
			customer.regular_favourite_label = recipe.display_name
			# A listed usual keeps its menu bonus, but must not replace a
			# stocked visit with an order type that cannot currently be cooked.
			if available_menu().has(recipe):
				visit = recipe.order_type
			break
	customer.vibe_review_bonus += regulars.menu_happiness(profile, customer.regular_favourite_available)
	return visit


func regular_tip(customer: CustomerAgent, order: Order) -> int:
	if regulars == null or customer == null or customer.regular_profile == null or order == null:
		return 0
	var amount: float = order.price * regulars.tip_rate(customer.regular_profile,
		customer.regular_favourite_available)
	# Cash is whole units. Rounding the favourite bonus up keeps a modest
	# drink's extra tip visible instead of rounding it away on every visit.
	return maxi(0, ceili(amount) if customer.regular_favourite_available else roundi(amount))


func _record_regular_visit(customer: CustomerAgent) -> void:
	if regulars == null:
		return
	var recipe: StringName = customer.order.recipe_id if customer.order != null else &""
	var quality: float = customer.order.quality if customer.order != null else 0.0
	var waited: float = maxf(float(customer._queue_wait) / maxi(1, customer.queue_patience),
		float(customer._food_wait) / maxi(1, customer.food_patience))
	if customer.regular_profile != null:
		var enjoyed: Array[StringName] = []
		if customer.paid and not recipe.is_empty():
			enjoyed.append(recipe)
		regulars.finish_visit(customer.regular_profile, world.clock.day, enjoyed,
			customer.seat_cell, customer.paid, quality, waited, customer.regular_favourite_available)
	elif not customer.repeat_guest_key.is_empty():
		regulars.observe_visit(customer.repeat_guest_key, customer.customer_type_id,
			world.clock.day, review_book.average(), _vibe_result.score, recipe,
			customer.seat_cell, quality, customer.paid and waited < regulars.tuning.long_wait_fraction,
			regular_rng_provider)


func _publish_customer_arrival(customer: CustomerAgent) -> void:
	world.log_event("Guest #%d arrived" % customer.id)
	customer_arrived.emit(customer)


## Members are installed in the same arrival tick and retain private RNGs.
## Singletons keep add_customer's exact path, including its signal order.
func add_party(entry: Vector2i, randoms: Array[RandomNumberGenerator], kind: CustomerType = null,
		visit: StringName = RecipeDef.FOOD) -> Party:
	if randoms.is_empty() or randoms.size() > Party.MAX_SIZE or (kind != null and not kind.is_valid()):
		return null
	for random: RandomNumberGenerator in randoms:
		if random == null:
			return null
	var ids: Array[int] = []
	var guests: Array[CustomerAgent] = []
	for random: RandomNumberGenerator in randoms:
		var guest: CustomerAgent = _install_customer(entry, random, kind, false, visit)
		ids.append(guest.id)
		guests.append(guest)
	var group: Party = Party.new(ids)
	for guest: CustomerAgent in guests:
		guest.party = group
	for guest: CustomerAgent in guests:
		_publish_customer_arrival(guest)
	return group


# --- Restrooms (FK-101) -------------------------------------------------------

## A restroom: a Restroom room with a toilet guests can reach.
func has_restroom() -> bool:
	_count_layout()
	return not _toilets.is_empty()


## Dining seats in the shop (every table's seat cells).
func seat_count() -> int:
	_count_layout()
	return _seats


## Guests start expecting a restroom once the shop seats enough of them.
func restrooms_expected() -> bool:
	return restroom_tuning != null and restroom_tuning.is_valid() and seat_count() >= restroom_tuning.seat_threshold


## Whether guests draw a restroom need at all. False keeps every guest's random
## stream exactly as it was before restrooms existed.
func restrooms_matter() -> bool:
	return restroom_tuning != null and restroom_tuning.is_valid() and (has_restroom() or restrooms_expected())


## The first restroom toilet (placement order) that is free and that this
## guest can walk to without entering a staff-only room, or null.
func free_toilet(guest: CustomerAgent) -> PlacedItem:
	_count_layout()
	for toilet_id: int in _toilets:
		var toilet: PlacedItem = world.grid.item(toilet_id)
		if toilet == null or toilet.work_cells.is_empty():
			continue
		var spot: Vector2i = toilet.work_cells[0]
		if toilet.reserved_by(spot) == -1 and world.grid.is_walkable(spot) \
				and world.grid.is_guest_reachable(guest.cell, spot):
			return toilet
	return null


## Each use leaves the restroom needing a tidy, if cleaning exists here.
func restroom_used(spot: Vector2i) -> void:
	if cleanliness != null and cleanliness.add_use_spot(spot) and clean_tasks != null:
		clean_tasks.sync_spots()


func _on_layout_changed(_cells: Array[Vector2i]) -> void:
	_layout_counted = false


func _count_layout() -> void:
	if _layout_counted or world == null:
		return
	_layout_counted = true
	_toilets.clear()
	for toilet: PlacedItem in RoomRules.restroom_toilets(world.grid):
		_toilets.append(toilet.id)
	_seats = 0
	for placed: PlacedItem in world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition != null and definition.category == ItemDef.Category.TABLE:
			_seats += placed.seat_cells.size()


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
	# A drink ordered with the meal is paid with it, once it reached the table.
	var drink: Order = customer.extra_order
	if drink != null and drink != order and drink.state == Order.State.DELIVERED:
		customer_paid.emit(customer, drink, drink.price)


## Accounts for a departure once, including direct world removal and repeated cleanup.
func record_departure(customer: CustomerAgent) -> void:
	if customer.departure_recorded or _departed.has(customer.id):
		return
	_departed[customer.id] = true
	customer.departure_recorded = true
	_record_regular_visit(customer)
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
