class_name FoodPresentation
extends Node3D
## Read-only restaurant dressing. Nodes are created at bind/layout boundaries,
## never in sync(): carried dishes inherit the actual smoothed person's transform.

const CREAM: SwatchDef = preload("res://data/swatches/cream.tres")

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

var restaurant: RestaurantSim
var content: ContentDB
var pool: Array[DishVisual] = []
var stack: Array[DishVisual] = []
var steam: Dictionary[int, CPUParticles3D] = {}
var surfaces: Dictionary[int, Vector3] = {}
var surface_bounds: Dictionary[int, AABB] = {}
var _tops: Dictionary[int, Surface] = {}
var _bases: Dictionary[int, Basis] = {}
var tickets: Dictionary[int, Ticket] = {}
var _recipes: Array[RecipeDef] = []
var _sink_id: int = 0
var _pass_id: int = 0


func bind(value: RestaurantSim, definitions: ContentDB, items: Dictionary[int, ItemVisual]) -> void:
	restaurant = value
	content = definitions
	_recipes = content.recipes()
	restaurant.orders.order_placed.connect(_remember)
	for state: Order.State in [Order.State.PLACED, Order.State.COOKING, Order.State.READY, Order.State.DELIVERED]:
		for order: Order in restaurant.orders.orders_in_state(state):
			_remember(order)
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
		var serving_surface: bool = definition.category == ItemDef.Category.TABLE or definition.category == ItemDef.Category.PASS
		var surface: Surface = _surface(visual, serving_surface)
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
		dish.prepare(_recipes)
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


func sync(frames: Dictionary[int, AgentPresentationController.Frame], people: Dictionary[int, Node3D]) -> void:
	for id: int in tickets:
		tickets[id].carrier_id = 0
		tickets[id].carry_index = 0
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
	for id: int in tickets:
		var ticket: Ticket = tickets[id]
		var order: Order = ticket.order
		if ticket.retired or ticket.recipe == null or ticket.recipe.view_model == null:
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
				spot = frame.tray_anchor + Vector3.UP * (0.025 if frame.show_tray else 0.0)
				if frame.show_tray:
					var index: int = ticket.carry_index
					spot += Vector3((index % 2 - 0.5) * 0.24, 0.0, (index / 2 - 0.5) * 0.18)
				stage = &"carried"
			elif not ticket.recipe.is_drink() and surfaces.has(_pass_id):
				# One centered row fits the measured counter depth. Additional
				# groups of three retain the existing 0.025 m stacking convention.
				spot = _inset_spot(_pass_id, surfaces[_pass_id]
					+ _bases[_pass_id] * Vector3((pass_index % 3 - 1) * 0.24, 0.0, 0.0))
				spot.y += float(pass_index / 3) * 0.025
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
				spot += Vector3(-toward.z, 0.0, toward.x).normalized() * 0.16
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
		dish.show_dish(ticket.recipe, stage == &"dirty")
	for item_id: int in steam:
		steam[item_id].emitting = false
	var washing_sink: int = _sink_id
	for agent: SimAgent in restaurant.world.agents:
		if agent is StaffAgent and frames.has(agent.id) and frames[agent.id].working:
			var staff: StaffAgent = agent as StaffAgent
			if steam.has(staff._held_item_id) and staff.task != null and staff.task.kind == &"cook":
				steam[staff._held_item_id].emitting = true
			if staff.task != null and staff.task.kind == &"wash":
				var active_sink: int = int(staff.task.payload.get("sink_id", 0))
				if surfaces.has(active_sink):
					washing_sink = active_sink
	for index: int in range(stack.size()):
		var dish: DishVisual = stack[index]
		dish.visible = washing_sink > 0 and restaurant.kitchen.plate_cycle_enabled and index < restaurant.kitchen.plates.dirty
		if dish.visible:
			dish.position = surfaces[washing_sink] + Vector3(0.12, index * 0.018, 0.0)


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
		ticket.dish.visible = false
		ticket.dish.order_id = 0
		ticket.dish.reparent(self, false)
	ticket.dish = null


func _available() -> DishVisual:
	for dish: DishVisual in pool:
		if dish.order_id == 0:
			return dish
	return null


## Find the broad horizontal surface of the real model, excluding seat parts.
## Measuring once avoids chair backs and sink taps becoming a table/counter top.
static func _surface(visual: ItemVisual, serving: bool = false) -> Surface:
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
