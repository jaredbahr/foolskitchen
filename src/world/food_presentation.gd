class_name FoodPresentation
extends Node3D
## Read-only restaurant dressing. Nodes are created at bind/layout boundaries,
## never in sync(): carried dishes inherit the actual smoothed person's transform.

const CREAM: SwatchDef = preload("res://data/swatches/cream.tres")
## Plate spacing, sized for ArtScale.FOOD_SCALE (a plate is about 0.29 across;
## every vessel stays inside the plate's footprint, DishVessels).
## Pass: along the counter. Tray: across and along the carried tray.
const PASS_PLATE_STEP: float = 0.33
## The carried tray, sized to hold four plates in two rows with small gaps.
const TRAY_SIZE: Vector3 = Vector3(0.72, 0.045, 0.62)
const TRAY_PLATE_STEP: Vector2 = Vector2(0.34, 0.30)
const TRAY_PLATE_LIFT: float = 0.025
## The tray sits this far in front of the hands, so its back edge stays clear
## of the server's chest (the same back edge as the old, smaller tray).
const TRAY_FORWARD: Vector3 = Vector3(0.0, 0.0, -0.12)
const PASS_STACK_STEP: float = 0.0375
const SINK_STACK_STEP: float = 0.027
## Sideways shift of the dirty stack on the sink; the basin is only 0.32 across.
const SINK_STACK_OFFSET: float = 0.02
## A drink sits this far to the side of its plate; the table clamp keeps it on the top.
const DRINK_SIDE_OFFSET: float = 0.24
## Steam from hot servings (RecipeDef.hot): at most this many emitters, all
## made at bind, given to the hot servings nearest the camera.
const DISH_STEAM_CAP: int = 12
## A hot meal steams for its first ticks of eating (a meal is 270), fading
## out over the last DISH_STEAM_FADE of them. It steams all the while on the pass.
const DISH_STEAM_TICKS: int = 120
const DISH_STEAM_FADE: int = 50
## Steam rises from just above the top of the food.
const DISH_STEAM_LIFT: float = 0.01

class Surface extends RefCounted:
	var point: Vector3
	var bounds: AABB
	var outlines: Array[PackedVector2Array] = []
	var safe: Array[PackedVector2Array] = []

class Ticket extends RefCounted:
	var order: Order
	var recipe: RecipeDef
	var dish: DishVisual
	var retired: bool = false
	var carrier_id: int = 0
	var carry_index: int = 0
	## World tick the guest started eating this serving; -1 before that.
	var eating_since: int = -1

var restaurant: RestaurantSim
var content: ContentDB
var pool: Array[DishVisual] = []
var stack: Array[DishVisual] = []
var steam: Dictionary[int, CPUParticles3D] = {}
## Sound loop for each station that makes one while worked (#117).
const STATION_LOOPS: Dictionary[StringName, StringName] = {
	&"stove": &"stove_sizzle", &"fryer": &"fryer_bubble", &"coffee_machine": &"coffee_steam",
}
var _station_loops: Dictionary[int, StringName] = {}
## Stations being worked this frame, counted per sound loop (read-only view state).
var busy_loops: Dictionary[StringName, int] = {}
var surfaces: Dictionary[int, Vector3] = {}
var surface_bounds: Dictionary[int, AABB] = {}
var _tops: Dictionary[int, Surface] = {}
var _bases: Dictionary[int, Basis] = {}
var tickets: Dictionary[int, Ticket] = {}
## The menu the pool was last warmed for, compared each sync without allocating.
var _menu_seen: Array[RecipeDef] = []
var _sink_id: int = 0
## The plate steam emitters (DISH_STEAM_CAP of them) and the order each
## serves (0 when free). Candidates are gathered in fixed-size arrays.
var dish_steam: Array[CPUParticles3D] = []
var _steam_order: PackedInt32Array = PackedInt32Array()
var _hot_orders: PackedInt32Array = PackedInt32Array()
var _hot_rank: PackedFloat32Array = PackedFloat32Array()
var _hot_alpha: PackedFloat32Array = PackedFloat32Array()
var _hot_count: int = 0
## Customers taking their order away, gathered once per sync.
var _away: Dictionary[int, bool] = {}
var _pass_id: int = 0


func bind(value: RestaurantSim, definitions: ContentDB, items: Dictionary[int, ItemVisual]) -> void:
	restaurant = value
	content = definitions
	_menu_seen.assign(restaurant.menu)
	restaurant.orders.order_placed.connect(_remember)
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY, Order.State.DELIVERED]:
		for order: Order in restaurant.orders.orders_in_state(state):
			_remember(order)
	# A pool kept from an earlier restaurant is warmed for this one's menu.
	var recipes: Array[RecipeDef] = served_recipes()
	for dish: DishVisual in pool:
		dish.rebuild(recipes)
	while dish_steam.size() < DISH_STEAM_CAP:
		var puff: CPUParticles3D = _dish_steam(dish_steam.size())
		add_child(puff)
		dish_steam.append(puff)
	_steam_order.resize(DISH_STEAM_CAP)
	_steam_order.fill(0)
	_hot_orders.resize(DISH_STEAM_CAP)
	_hot_rank.resize(DISH_STEAM_CAP)
	_hot_alpha.resize(DISH_STEAM_CAP)
	refresh_layout(items)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for dish: DishVisual in pool:
			if is_instance_valid(dish) and dish.get_parent() != self:
				dish.free()


func _exit_tree() -> void:
	if restaurant != null and restaurant.orders.order_placed.is_connected(_remember):
		restaurant.orders.order_placed.disconnect(_remember)


func _remember(order: Order) -> void:
	# Morning pruning is observed at the next ticket event, outside frame sync.
	for id: int in tickets.keys():
		if restaurant.orders.get_order(id) == null:
			_retire(tickets[id])
			tickets.erase(id)
	var ticket: Ticket = Ticket.new()
	ticket.order = order
	ticket.recipe = content.recipe(order.recipe_id)
	tickets[order.id] = ticket


## Called by ShopView after build events have updated its real prop nodes.
func refresh_layout(items: Dictionary[int, ItemVisual]) -> void:
	surfaces.clear()
	surface_bounds.clear()
	_tops.clear()
	_bases.clear()
	_sink_id = 0
	_pass_id = 0
	var seats: int = 0
	_station_loops.clear()
	for id: int in steam.keys():
		if not items.has(id):
			steam[id].free()
			steam.erase(id)
	for item: PlacedItem in restaurant.world.grid.items():
		seats += item.seat_cells.size()
		if not items.has(item.id):
			continue
		var visual: ItemVisual = items[item.id]
		var definition: ItemDef = item.def as ItemDef
		if STATION_LOOPS.has(definition.id):
			_station_loops[item.id] = STATION_LOOPS[definition.id]
		var serving_surface: bool = definition.category == ItemDef.Category.TABLE or definition.category == ItemDef.Category.PASS
		var surface: Surface = measure_surface(visual, serving_surface)
		surfaces[item.id] = surface.point
		surface_bounds[item.id] = surface.bounds
		if serving_surface:
			_tops[item.id] = surface
			_bases[item.id] = visual.basis
		if _pass_id == 0 and definition.category == ItemDef.Category.PASS and item.work_cells.size() >= 2:
			_pass_id = item.id
		elif _sink_id == 0 and definition.category == ItemDef.Category.STATION and definition.station_type == &"sink":
			_sink_id = item.id
		if definition.id in [&"stove", &"fryer"] and not steam.has(item.id):
			var puff: CPUParticles3D = _steam()
			add_child(puff)
			steam[item.id] = puff
		if steam.has(item.id):
			steam[item.id].position = surfaces[item.id] + Vector3(0.0, 0.07, 0.0)
	# At most two simultaneous servings per seat (a drink and its food), plus
	# a bounded pass allowance. Dirty sink crockery uses its own small stack.
	while pool.size() < seats * 2 + 16:
		var dish: DishVisual = DishVisual.new()
		add_child(dish)
		dish.prepare(served_recipes())
		pool.append(dish)
	while stack.size() < 6:
		var dish: DishVisual = DishVisual.new()
		add_child(dish)
		dish.prepare([])
		dish.dirty_plate.visible = true
		stack.append(dish)
	# Polygon operations and plate measurement stay at layout boundaries.
	# Inset the real outline, including round edges and counter cutouts.
	for id: int in _tops:
		for outline: PackedVector2Array in _tops[id].outlines:
			_tops[id].safe.append_array(Geometry2D.offset_polygon(outline,
				-pool[0].footprint_radius - 0.001, Geometry2D.JOIN_MITER))


## What the pool warms: today's menu plus every recipe still in flight (an
## order not yet eaten, or a dirty serving still on its table).
func served_recipes() -> Array[RecipeDef]:
	var recipes: Array[RecipeDef] = []
	for recipe: RecipeDef in restaurant.menu:
		if recipe != null and not recipes.has(recipe):
			recipes.append(recipe)
	for id: int in tickets:
		var recipe: RecipeDef = tickets[id].recipe
		if not tickets[id].retired and recipe != null and not recipes.has(recipe):
			recipes.append(recipe)
	return recipes


## The pool is warmed for the menu, not the whole recipe book. A menu changed
## between services (the morning, or Build/Menu while closed) rebuilds it;
## during service a newly listed dish is built on demand, once per serving.
func _follow_menu() -> void:
	var menu: Array[RecipeDef] = restaurant.menu
	var same: bool = menu.size() == _menu_seen.size()
	if same:
		for index: int in range(menu.size()):
			if menu[index] != _menu_seen[index]:
				same = false
				break
	if same:
		return
	_menu_seen.assign(menu)
	var clock: SimClock = restaurant.world.clock
	if clock == null or clock.phase == SimClock.Phase.MORNING or clock.phase == SimClock.Phase.CLOSED:
		var recipes: Array[RecipeDef] = served_recipes()
		for dish: DishVisual in pool:
			dish.rebuild(recipes)


func sync(frames: Dictionary[int, AgentPresentationController.Frame], people: Dictionary[int, Node3D]) -> void:
	_follow_menu()
	for id: int in tickets:
		tickets[id].carrier_id = 0
		tickets[id].carry_index = 0
	# A guest taking the order away at the counter gets the to-go serving.
	_away.clear()
	for agent: SimAgent in restaurant.world.agents:
		if agent is CustomerAgent and (agent as CustomerAgent).takeaway:
			_away[agent.id] = true
	for agent: SimAgent in restaurant.world.agents:
		if not agent is StaffAgent or not frames.has(agent.id) or not frames[agent.id].carrying:
			continue
		var task: SimTask = (agent as StaffAgent).task
		if task == null:
			continue
		var order_ids: Variant = task.payload.get("order_ids")
		if task.kind == &"pour":
			var ticket: Ticket = tickets.get(int(task.payload.get("order_id", 0))) as Ticket
			if ticket != null:
				ticket.carrier_id = agent.id
		elif task.kind == &"deliver" and order_ids != null:
			var index: int = 0
			for order_id: int in order_ids:
				var order: Order = restaurant.orders.get_order(order_id)
				if order != null and order.state == Order.State.READY:
					var ticket: Ticket = tickets.get(order_id) as Ticket
					if ticket != null:
						ticket.carrier_id = agent.id
						ticket.carry_index = index
					index += 1
	var pass_index: int = 0
	_hot_count = 0
	for id: int in tickets:
		var ticket: Ticket = tickets[id]
		var order: Order = ticket.order
		if ticket.retired:
			continue
		if ticket.recipe == null or ticket.recipe.id.is_empty():
			_release(ticket)
			continue
		if restaurant.orders.get_order(id) != order or order.state == Order.State.CANCELLED:
			_retire(ticket)
			continue
		var stage: StringName = &""
		var parent: Node3D = self
		var spot: Vector3 = Vector3.ZERO
		if order.state == Order.State.READY:
			if ticket.carrier_id > 0 and people.has(ticket.carrier_id):
				var frame: AgentPresentationController.Frame = frames[ticket.carrier_id]
				parent = people[ticket.carrier_id]
				spot = frame.tray_anchor + Vector3.UP * (TRAY_PLATE_LIFT if frame.show_tray else 0.0)
				if frame.show_tray:
					spot += TRAY_FORWARD
					var index: int = ticket.carry_index
					spot += Vector3((index % 2 - 0.5) * TRAY_PLATE_STEP.x, 0.0, (index / 2 - 0.5) * TRAY_PLATE_STEP.y)
				stage = &"carried"
			elif not ticket.recipe.is_drink() and surfaces.has(_pass_id):
				# One centered row fits the measured counter depth. Additional
				# groups of three retain the existing 0.025 m stacking convention.
				spot = _inset_spot(_pass_id, surfaces[_pass_id]
					+ _bases[_pass_id] * Vector3((pass_index % 3 - 1) * PASS_PLATE_STEP, 0.0, 0.0))
				spot.y += float(pass_index / 3) * PASS_STACK_STEP
				pass_index += 1
				stage = &"ready"
		elif order.state == Order.State.DELIVERED and surfaces.has(order.table_item_id):
			var customer: CustomerAgent = restaurant.world.agent(order.customer_id) as CustomerAgent
			var dirty: bool = restaurant.kitchen.dirty_tables.has(order.table_item_id)
			var ledger: bool = restaurant.kitchen.plate_cycle_enabled
			if not ticket.recipe.is_drink() and ledger and not restaurant.kitchen.plates.has_order(id):
				_retire(ticket)
				continue
			if customer != null and customer.state != CustomerAgent.State.LEAVING \
					and customer.state != CustomerAgent.State.LEFT:
				stage = &"eating"
			elif dirty and not ticket.recipe.is_drink():
				stage = &"dirty"
			else:
				_retire(ticket)
				continue
			var center: Vector3 = surfaces[order.table_item_id]
			var toward: Vector3 = GridMath.cell_to_world(order.seat_cell) - center
			toward.y = 0.0
			spot = _seat_spot(order.table_item_id, order.seat_cell)
			if ticket.recipe.is_drink():
				spot += Vector3(-toward.z, 0.0, toward.x).normalized() * DRINK_SIDE_OFFSET
				spot = _inset_spot(order.table_item_id, spot)
		if stage.is_empty():
			_release(ticket)
			continue
		if ticket.dish == null:
			ticket.dish = _available()
		if ticket.dish == null:
			continue
		var dish: DishVisual = ticket.dish
		if dish.get_parent() != parent:
			dish.reparent(parent, false)
		dish.position = spot
		dish.rotation = Vector3.ZERO
		dish.order_id = id
		dish.stage = stage
		dish.show_dish(ticket.recipe, stage == &"dirty", _away.has(order.customer_id))
		if stage == &"eating" and ticket.eating_since < 0:
			ticket.eating_since = restaurant.world.now
		_consider_steam(ticket, stage)
	_place_steam()
	for item_id: int in steam:
		steam[item_id].emitting = false
	busy_loops.clear()
	var washing_sink: int = _sink_id
	for agent: SimAgent in restaurant.world.agents:
		if agent is StaffAgent and frames.has(agent.id) and frames[agent.id].working:
			var staff: StaffAgent = agent as StaffAgent
			if steam.has(staff._held_item_id) and staff.task != null and staff.task.kind == &"cook":
				steam[staff._held_item_id].emitting = true
			if _station_loops.has(staff._held_item_id) and staff.task != null \
					and (staff.task.kind == &"cook" or staff.task.kind == &"pour"):
				var loop: StringName = _station_loops[staff._held_item_id]
				busy_loops[loop] = int(busy_loops.get(loop, 0)) + 1
			if staff.task != null and staff.task.kind == &"wash":
				var active_sink: int = int(staff.task.payload.get("sink_id", 0))
				if surfaces.has(active_sink):
					washing_sink = active_sink
	for index: int in range(stack.size()):
		var dish: DishVisual = stack[index]
		dish.visible = washing_sink > 0 and restaurant.kitchen.plate_cycle_enabled and index < restaurant.kitchen.plates.dirty
		if dish.visible:
			dish.position = surfaces[washing_sink] + Vector3(SINK_STACK_OFFSET, index * SINK_STACK_STEP, 0.0)


## A hot serving on the pass, or early in its meal, asks for steam. The
## DISH_STEAM_CAP nearest the camera (ticket order without one) keep it.
func _consider_steam(ticket: Ticket, stage: StringName) -> void:
	if not ticket.recipe.hot or ticket.dish == null or _away.has(ticket.order.customer_id):
		return
	var alpha: float = 1.0
	if stage == &"eating":
		var eaten: int = restaurant.world.now - ticket.eating_since
		if eaten >= DISH_STEAM_TICKS:
			return
		alpha = clampf(float(DISH_STEAM_TICKS - eaten) / float(DISH_STEAM_FADE), 0.0, 1.0)
	elif stage != &"ready":
		return
	var rank: float = float(_hot_count)
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		rank = camera.global_position.distance_squared_to(ticket.dish.global_position)
	var slot: int = _hot_count
	if _hot_count >= DISH_STEAM_CAP:
		# Replace the farthest candidate, if this one is nearer.
		slot = 0
		for index: int in range(1, DISH_STEAM_CAP):
			if _hot_rank[index] > _hot_rank[slot]:
				slot = index
		if rank >= _hot_rank[slot]:
			return
	else:
		_hot_count += 1
	_hot_orders[slot] = ticket.order.id
	_hot_rank[slot] = rank
	_hot_alpha[slot] = alpha


## Emitters keep the serving they already steam (no restart); a freed emitter
## stops emitting, so its last puffs fade, and is given to a new hot serving.
func _place_steam() -> void:
	for index: int in range(dish_steam.size()):
		var owner: int = _steam_order[index]
		var kept: bool = false
		for candidate: int in range(_hot_count):
			if _hot_orders[candidate] == owner and owner != 0:
				kept = true
				_aim_steam(index, candidate)
				_hot_orders[candidate] = 0
				break
		if not kept and owner != 0:
			_steam_order[index] = 0
			if dish_steam[index].emitting:
				dish_steam[index].emitting = false
	for candidate: int in range(_hot_count):
		if _hot_orders[candidate] == 0:
			continue
		for index: int in range(dish_steam.size()):
			if _steam_order[index] == 0:
				_steam_order[index] = _hot_orders[candidate]
				_aim_steam(index, candidate)
				if dish_steam[index].is_inside_tree():
					dish_steam[index].restart()
					dish_steam[index].emitting = true
				break


func _aim_steam(index: int, candidate: int) -> void:
	var ticket: Ticket = tickets.get(_steam_order[index]) as Ticket
	var puff: CPUParticles3D = dish_steam[index]
	# Pass and table servings are children of this node, like the emitters.
	puff.position = ticket.dish.position + Vector3.UP * (DISH_STEAM_LIFT
		+ float(ticket.dish.steam_heights.get(ticket.recipe.id, 0.06)))
	puff.color = Color(1.0, 1.0, 1.0, _hot_alpha[candidate])
	# World-space puffs need the tree; a detached view only keeps the slot.
	puff.emitting = puff.is_inside_tree()


## Keep the dish beside its own seat, including the end of a long table.
## The native tabletop bounds exclude chair backs and survive quarter turns.
func _seat_spot(item_id: int, seat: Vector2i) -> Vector3:
	return _inset_spot(item_id, GridMath.cell_to_world(seat))


func _inset_spot(item_id: int, spot: Vector3) -> Vector3:
	var bounds: AABB = surface_bounds[item_id]
	var inset_x: float = minf(0.12, bounds.size.x * 0.45)
	var inset_z: float = minf(0.12, bounds.size.z * 0.45)
	var result: Vector3 = Vector3(clampf(spot.x, bounds.position.x + inset_x, bounds.end.x - inset_x),
		surfaces[item_id].y, clampf(spot.z, bounds.position.z + inset_z, bounds.end.z - inset_z))
	if not _tops.has(item_id) or _tops[item_id].safe.is_empty():
		return result  # Preserve the bounds fallback for degenerate/small surfaces.
	var point: Vector2 = Vector2(result.x, result.z)
	var closest: Vector2 = point
	var distance: float = INF
	for polygon: PackedVector2Array in _tops[item_id].safe:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return result
		for index: int in range(polygon.size()):
			var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(point,
				polygon[index], polygon[(index + 1) % polygon.size()])
			var squared: float = point.distance_squared_to(candidate)
			if squared < distance:
				distance = squared
				closest = candidate
	return Vector3(closest.x, result.y, closest.y)


func _retire(ticket: Ticket) -> void:
	ticket.retired = true
	_release(ticket)


func _release(ticket: Ticket) -> void:
	if is_instance_valid(ticket.dish):
		ticket.dish.clear_dish()
		ticket.dish.reparent(self, false)
	ticket.dish = null


func _available() -> DishVisual:
	for dish: DishVisual in pool:
		if dish.order_id == 0:
			return dish
	return null


## Find the broad horizontal surface of the real model, excluding seat parts.
## Measuring once avoids chair backs and sink taps becoming a table/counter top.
static func measure_surface(visual: ItemVisual, serving: bool = false) -> Surface:
	var areas: Dictionary[int, float] = {}
	var centers: Dictionary[int, Vector3] = {}
	var bounds: Dictionary[int, AABB] = {}
	var triangles: Dictionary[int, Array] = {}
	_collect_surfaces(visual, Transform3D.IDENTITY, areas, centers, bounds, triangles, serving)
	var best: int = 0
	var area: float = 0.0
	for height: int in areas:
		if areas[height] > area or (is_equal_approx(areas[height], area) and height > best):
			best = height
			area = areas[height]
	var local: Vector3 = centers[best] / area if area > 0.0 else Vector3(0.0, visual.get_aabb().end.y, 0.0)
	var surface: Surface = Surface.new()
	surface.point = visual.transform * (local + Vector3.UP * 0.003)
	surface.bounds = visual.transform * (bounds[best] if area > 0.0 else visual.get_aabb())
	if serving and area > 0.0:
		for triangle: PackedVector3Array in triangles[best]:
			var polygon: PackedVector2Array = PackedVector2Array()
			for vertex: Vector3 in triangle:
				var point: Vector3 = visual.transform * vertex
				polygon.append(Vector2(point.x, point.z))
			if Geometry2D.is_polygon_clockwise(polygon):
				polygon.reverse()
			_merge_top(surface.outlines, polygon)
	return surface


## Merge the selected native triangles, rather than inventing a convex top
## across an empty corner. All temporary polygons are built outside sync().
static func _merge_top(outlines: Array[PackedVector2Array], polygon: PackedVector2Array) -> void:
	var index: int = 0
	while index < outlines.size():
		var joined: Array[PackedVector2Array] = Geometry2D.merge_polygons(polygon, outlines[index])
		if joined.size() == 1:
			polygon = joined[0]
			outlines.remove_at(index)
			index = 0
		else:
			index += 1
	outlines.append(polygon)


static func _collect_surfaces(node: Node, transform: Transform3D, areas: Dictionary[int, float], centers: Dictionary[int, Vector3], bounds: Dictionary[int, AABB], triangles: Dictionary[int, Array], serving: bool) -> void:
	if node.has_meta("seat_cell") or node.get_meta("art_group", &"") == &"food":
		return
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for index: int in range(0, faces.size(), 3):
			var a: Vector3 = transform * faces[index]
			var b: Vector3 = transform * faces[index + 1]
			var c: Vector3 = transform * faces[index + 2]
			if absf(a.y - b.y) > 0.001 or absf(a.y - c.y) > 0.001 or a.y < 0.1:
				continue
			var area: float = (b - a).cross(c - a).length() * 0.5
			if area <= 0.000001:
				continue
			var height: int = roundi(a.y * 1000.0)
			areas[height] = areas.get(height, 0.0) + area
			centers[height] = centers.get(height, Vector3.ZERO) + (a + b + c) / 3.0 * area
			var box: AABB = bounds.get(height, AABB(a, Vector3.ZERO))
			bounds[height] = box.expand(a).expand(b).expand(c)
			if serving:
				if not triangles.has(height):
					triangles[height] = []
				triangles[height].append(PackedVector3Array([a, b, c]))
	for child: Node in node.get_children():
		var spatial: Node3D = child as Node3D
		_collect_surfaces(child, transform * spatial.transform if spatial != null else transform, areas, centers, bounds, triangles, serving)


## A plate's steam: the cooking steam's look, smaller, slower and sparser.
## Its seed is fixed per emitter, so the puffs are the same every run.
static func _dish_steam(index: int) -> CPUParticles3D:
	var puff: CPUParticles3D = _steam()
	puff.amount = 6
	puff.lifetime = 1.6
	puff.local_coords = false
	puff.spread = 8.0
	puff.initial_velocity_min = 0.05
	puff.initial_velocity_max = 0.08
	puff.scale_amount_min = 0.018
	puff.scale_amount_max = 0.034
	# A cup's few puffs must read against a pale plate: a touch more opaque.
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(CREAM.color, 0.0), Color(CREAM.color, 0.6), Color(CREAM.color, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	puff.color_ramp = fade
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.018
	puff.use_fixed_seed = true
	puff.seed = 7919 * (index + 1)
	puff.visible = true
	return puff


static func _steam() -> CPUParticles3D:
	var puff: CPUParticles3D = CPUParticles3D.new()
	puff.amount = 12
	puff.lifetime = 0.8
	puff.preprocess = 0.0
	puff.emitting = false
	puff.local_coords = true
	puff.direction = Vector3.UP
	puff.spread = 12.0
	puff.initial_velocity_min = 0.08
	puff.initial_velocity_max = 0.14
	puff.gravity = Vector3.ZERO
	puff.scale_amount_min = 0.025
	puff.scale_amount_max = 0.055
	puff.color = Color.WHITE
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(CREAM.color, 0.35), Color(CREAM.color, 0.0)])
	puff.color_ramp = fade
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	puff.mesh = mesh
	return puff
