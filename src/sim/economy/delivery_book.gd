class_name DeliveryBook
extends RefCounted
## Ingredient orders that are paid for and not yet delivered (FK-087), and
## the delivery schedule. Pure data: the session charges, refunds and stocks.
##
## Schedule (EconomyTuning): morning orders (the auto-reorder, the standing
## order, and hand orders) arrive at once and never wait here. During service
## a delivery comes every delivery_interval_minutes of opening hours; an
## order arrives with the first one after it is placed, and orders after the
## last one (or once closed) with the next morning's delivery, which is
## unloaded before the morning save.
##
## A due time is Vector2i(day, tick): tick MORNING is the morning delivery
## and a positive tick is that many service ticks after opening.

const VERSION: int = 1
const MORNING: int = -1
const MAX_ORDERS: int = 256
const MAX_LINES: int = 64

## {due: Vector2i, lines: [{id, qty, unit_cost}], cost: int, standing: bool}
var _orders: Array[Dictionary] = []


## Service ticks (after opening) of today's daytime deliveries, in order.
## Scales with the clock's service length, so a shortened test day keeps them.
static func slot_ticks(clock: SimClock, tuning: EconomyTuning) -> Array[int]:
	var out: Array[int] = []
	if clock == null or tuning == null or tuning.delivery_interval_minutes <= 0:
		return out
	var minutes: int = clock.display_close_minute - clock.display_open_minute
	if minutes <= 0 or clock.open_ticks <= 0:
		return out
	var step: int = tuning.delivery_interval_minutes
	var offset: int = step
	while offset < minutes:
		@warning_ignore("integer_division")
		var tick: int = offset * clock.open_ticks / minutes
		if tick > 0 and tick < clock.open_ticks and (out.is_empty() or tick > out[-1]):
			out.append(tick)
		offset += step
	return out


## The delivery an order placed now would come with.
static func next_due(clock: SimClock, tuning: EconomyTuning) -> Vector2i:
	if clock == null:
		return Vector2i(1, MORNING)
	var tomorrow: Vector2i = Vector2i(clock.day + 1, MORNING)
	match clock.phase:
		SimClock.Phase.MORNING:
			# Morning orders arrive at once: today's morning delivery.
			return Vector2i(clock.day, MORNING)
		SimClock.Phase.OPEN:
			for tick: int in slot_ticks(clock, tuning):
				if tick > clock.phase_tick:
					return Vector2i(clock.day, tick)
	return tomorrow


## Minutes since midnight of a daytime delivery tick on this clock.
static func minute_of(clock: SimClock, tick: int) -> int:
	if clock == null or clock.open_ticks <= 0:
		return 0
	var minutes: int = clock.display_close_minute - clock.display_open_minute
	@warning_ignore("integer_division")
	return clock.display_open_minute + tick * minutes / clock.open_ticks


## The Next delivery bar: {when: &"now" | &"today" | &"tomorrow", minute,
## fraction}. In the morning orders arrive at once (`now`, with the first
## daytime delivery's minute, or -1). `fraction` is how far the wait since the
## previous delivery has run (1.0 when orders arrive now or tomorrow).
static func countdown(clock: SimClock, tuning: EconomyTuning) -> Dictionary:
	var due: Vector2i = next_due(clock, tuning)
	if clock == null:
		return {"when": &"now", "minute": -1, "fraction": 1.0}
	if clock.phase == SimClock.Phase.MORNING:
		var slots: Array[int] = slot_ticks(clock, tuning)
		return {"when": &"now", "minute": minute_of(clock, slots[0]) if not slots.is_empty() else -1, "fraction": 1.0}
	if due.x == clock.day and due.y > 0:
		var previous: int = 0
		for tick: int in slot_ticks(clock, tuning):
			if tick <= clock.phase_tick:
				previous = tick
		var span: int = maxi(1, due.y - previous)
		return {"when": &"today", "minute": minute_of(clock, due.y),
			"fraction": clampf(float(clock.phase_tick - previous) / float(span), 0.0, 1.0)}
	return {"when": &"tomorrow", "minute": -1, "fraction": 1.0}


## Records a paid order. Lines: [{id: StringName, qty: int, unit_cost: int}].
func place(lines: Array[Dictionary], cost: int, standing: bool, due: Vector2i) -> bool:
	if lines.is_empty() or lines.size() > MAX_LINES or cost < 0 or _orders.size() >= MAX_ORDERS:
		return false
	var copied: Array[Dictionary] = []
	for line: Dictionary in lines:
		var id: StringName = StringName(line.get("id", &""))
		var qty: int = int(line.get("qty", 0))
		var unit_cost: int = int(line.get("unit_cost", -1))
		if id.is_empty() or qty <= 0 or unit_cost < 0:
			return false
		copied.append({"id": id, "qty": qty, "unit_cost": unit_cost})
	_orders.append({"due": due, "lines": copied, "cost": cost, "standing": standing})
	return true


func is_empty() -> bool:
	return _orders.is_empty()


func size() -> int:
	return _orders.size()


## Units on order by ingredient id.
func pending_by_id() -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for order: Dictionary in _orders:
		for line: Dictionary in order["lines"]:
			out[line["id"]] = int(out.get(line["id"], 0)) + int(line["qty"])
	return out


## What every pending order cost (the full refund if all are cancelled).
func paid_total() -> int:
	var total: int = 0
	for order: Dictionary in _orders:
		total += int(order["cost"])
	return total


## The earliest due time among pending orders, or Vector2i(-1, -1).
func earliest_due() -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	for order: Dictionary in _orders:
		var due: Vector2i = order["due"]
		if best.x < 0 or due.x < best.x or (due.x == best.x and due.y < best.y):
			best = due
	return best


## Whether an order due at `due` arrives at the clock's current moment.
## `morning_setup` is true only while the morning delivery is unloaded.
static func is_due(due: Vector2i, clock: SimClock, morning_setup: bool = false) -> bool:
	if due.x < clock.day:
		return true
	if due.x > clock.day:
		return false
	match clock.phase:
		SimClock.Phase.MORNING:
			return due.y == MORNING and morning_setup
		SimClock.Phase.OPEN:
			return due.y <= clock.phase_tick
	return true


## Removes and returns the lines of every order due now, merged by id in
## first-placed order: [{id, qty}].
func take_due(clock: SimClock, morning_setup: bool = false) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	var merged: Dictionary[StringName, int] = {}
	var order_ids: Array[StringName] = []
	for order: Dictionary in _orders:
		if not is_due(order["due"], clock, morning_setup):
			kept.append(order)
			continue
		for line: Dictionary in order["lines"]:
			var id: StringName = line["id"]
			if not merged.has(id):
				order_ids.append(id)
				merged[id] = 0
			merged[id] += int(line["qty"])
	_orders = kept
	var out: Array[Dictionary] = []
	for id: StringName in order_ids:
		out.append({"id": id, "qty": merged[id]})
	return out


## Cancels every pending order and returns the full amount paid for them.
func cancel_all() -> int:
	var refund: int = paid_total()
	_orders.clear()
	return refund


## Detached copies of the pending orders, for the panel and tests.
func orders() -> Array[Dictionary]:
	return _orders.duplicate(true)


func to_dict() -> Dictionary:
	var rows: Array = []
	for order: Dictionary in _orders:
		var lines: Array = []
		for line: Dictionary in order["lines"]:
			lines.append({"id": String(line["id"]), "qty": int(line["qty"]), "unit_cost": int(line["unit_cost"])})
		var due: Vector2i = order["due"]
		rows.append({"day": due.x, "tick": due.y, "lines": lines,
			"cost": int(order["cost"]), "standing": bool(order["standing"])})
	return {"version": VERSION, "orders": rows}


## Validates everything before replacing anything.
func from_dict(data: Dictionary) -> bool:
	var version: Variant = data.get("version", null)
	if not _is_whole(version) or int(version) < 1 or int(version) > VERSION:
		return false
	var rows: Variant = data.get("orders", null)
	if not rows is Array or (rows as Array).size() > MAX_ORDERS:
		return false
	var restored: DeliveryBook = DeliveryBook.new()
	for row: Variant in rows:
		if not row is Dictionary:
			return false
		var order: Dictionary = row
		var day: Variant = order.get("day", null)
		var tick: Variant = order.get("tick", null)
		var cost: Variant = order.get("cost", null)
		var standing: Variant = order.get("standing", null)
		var lines: Variant = order.get("lines", null)
		if not _is_whole(day) or int(day) < 1 or not _is_whole(tick) or int(tick) < MORNING \
				or not _is_whole(cost) or int(cost) < 0 or typeof(standing) != TYPE_BOOL or not lines is Array:
			return false
		var parsed: Array[Dictionary] = []
		for value: Variant in lines:
			if not value is Dictionary:
				return false
			var line: Dictionary = value
			var id: Variant = line.get("id", null)
			var qty: Variant = line.get("qty", null)
			var unit_cost: Variant = line.get("unit_cost", null)
			if typeof(id) != TYPE_STRING or (id as String).is_empty() or not _is_whole(qty) or int(qty) <= 0 \
					or not _is_whole(unit_cost) or int(unit_cost) < 0:
				return false
			parsed.append({"id": StringName(id), "qty": int(qty), "unit_cost": int(unit_cost)})
		if not restored.place(parsed, int(cost), bool(standing), Vector2i(int(day), int(tick))):
			return false
	_orders = restored._orders
	return true


static func _is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and floorf(float(value)) == float(value)
