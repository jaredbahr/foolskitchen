class_name GuestUrgency
extends RefCounted
## Reads how close the guests behind a task are to leaving (#307). Pure reads:
## no RNG, no writes, so the same world always scores the same.


## Largest patience fraction used by any guest this task serves: an order to
## take, a ticket to cook, a meal or drink to deliver. 0 when none is waiting.
static func of_task(world: SimWorld, task: SimTask) -> float:
	match task.kind:
		&"take_order":
			return _of_customer(world, int(task.payload.get("customer_id", 0)))
		&"cook", &"pour", &"deliver":
			return _of_orders(world, task)
	return 0.0


## True for the task kinds whose urgency is a waiting party, not one guest.
static func is_table_task(task: SimTask) -> bool:
	return task.kind == &"bus_table"


## The most impatient guest still waiting for a table (0 when nobody is).
static func waiting_for_table(world: SimWorld) -> float:
	var worst: float = 0.0
	for agent: SimAgent in world.agents:
		var guest: CustomerAgent = agent as CustomerAgent
		if guest != null and guest.state == CustomerAgent.State.QUEUED:
			worst = maxf(worst, guest.urgency())
	return worst


static func _of_orders(world: SimWorld, task: SimTask) -> float:
	var order_ids: Array = task.payload.get("order_ids", [])
	var worst: float = 0.0
	if order_ids.is_empty():
		return _of_order_id(world, int(task.payload.get("order_id", 0)))
	for order_id: Variant in order_ids:
		worst = maxf(worst, _of_order_id(world, int(order_id)))
	return worst


static func _of_order_id(world: SimWorld, order_id: int) -> float:
	return _of_customer(world, world.order_customer_id(order_id))


static func _of_customer(world: SimWorld, customer_id: int) -> float:
	var guest: CustomerAgent = world.agent(customer_id) as CustomerAgent
	return 0.0 if guest == null else guest.urgency()


## Plain sentence for the guest inspector when a staff member has claimed work
## for this guest ("Sam is coming to take my order"), or "" when nobody has.
static func staff_line(world: SimWorld, guest: CustomerAgent) -> String:
	for agent: SimAgent in world.agents:
		var staff: StaffAgent = agent as StaffAgent
		if staff == null or staff.task == null or staff.task.state != SimTask.State.CLAIMED:
			continue
		var name: String = staff.display_name if not staff.display_name.is_empty() else "A staff member"
		match staff.task.kind:
			&"take_order":
				if int(staff.task.payload.get("customer_id", 0)) == guest.id:
					return "%s is coming to take my order" % name
			&"deliver", &"pour":
				if _serves(world, staff.task, guest.id):
					return "%s is bringing my %s" % [name, "drink" if staff.task.kind == &"pour" else "food"]
	return ""


static func _serves(world: SimWorld, task: SimTask, customer_id: int) -> bool:
	var order_ids: Array = task.payload.get("order_ids", [])
	if order_ids.is_empty():
		order_ids = [int(task.payload.get("order_id", 0))]
	for order_id: Variant in order_ids:
		if world.order_customer_id(int(order_id)) == customer_id:
			return true
	return false
