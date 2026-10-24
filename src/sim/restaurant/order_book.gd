class_name OrderBook
extends RefCounted
## Deterministic tickets shared by guests and the kitchen.

signal order_placed(order: Order)
signal order_ready(order: Order)
signal order_delivered(order: Order)
signal order_cancelled(order: Order)

var _orders: Dictionary[int, Order] = {}
var _next_id: int = 1


## Registers a ticket once and returns its never-reused id.
func place(order: Order, now: int) -> int:
	if order.id != 0 and _orders.get(order.id) == order:
		return order.id
	order.id = _next_id
	_next_id += 1
	order.placed_tick = now
	order.state = Order.State.PLACED
	_orders[order.id] = order
	order_placed.emit(order)
	return order.id


## Finds a ticket, including completed tickets until morning pruning, or null.
func get_order(id: int) -> Order:
	return _orders.get(id, null)


## Terminal tickets cannot be changed; repeated states do not emit again.
func set_state(order: Order, state: Order.State) -> void:
	if order == null or _orders.get(order.id) != order or order.state == state:
		return
	if order.state == Order.State.DELIVERED or order.state == Order.State.CANCELLED:
		return
	order.state = state
	match state:
		Order.State.READY:
			order_ready.emit(order)
		Order.State.DELIVERED:
			order_delivered.emit(order)
		Order.State.CANCELLED:
			order_cancelled.emit(order)


## Returns matching tickets in id order.
func orders_in_state(state: Order.State) -> Array[Order]:
	var out: Array[Order] = []
	var ids: Array[int] = []
	ids.assign(_orders.keys())
	ids.sort()
	for id: int in ids:
		if _orders[id].state == state:
			out.append(_orders[id])
	return out


## Discards terminal tickets at the next morning; active ids are never reused.
func prune_finished() -> void:
	for id: int in _orders.keys():
		var state: Order.State = _orders[id].state
		if state == Order.State.DELIVERED or state == Order.State.CANCELLED:
			_orders.erase(id)
