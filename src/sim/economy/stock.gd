class_name Stock
extends RefCounted
## Dated ingredient batches. Takes are atomic and consume the oldest first.

const MAX_QUANTITY: int = 9223372036854775807

var _batches: Dictionary[StringName, Array] = {}


## Adds a positive batch, ordered by purchase day; invalid additions do nothing.
func add(id: StringName, qty: int, day: int) -> void:
	if id.is_empty() or qty <= 0 or qty > MAX_QUANTITY - count(id):
		return
	var batches: Array = _batches.get(id, [])
	var insertion: int = batches.size()
	for index: int in range(batches.size()):
		if int(batches[index]["bought_day"]) > day:
			insertion = index
			break
	batches.insert(insertion, {"qty": qty, "bought_day": day})
	_batches[id] = batches


## Returns the total units available for an ingredient.
func count(id: StringName) -> int:
	var total: int = 0
	for batch: Dictionary in _batches.get(id, []):
		total += int(batch["qty"])
	return total


## Reports whether a nonnegative quantity can be taken; zero needs no stock.
func has(id: StringName, qty: int) -> bool:
	return qty >= 0 and count(id) >= qty


## Takes all requested units, oldest first, or leaves every batch unchanged.
func take(id: StringName, qty: int) -> bool:
	if not has(id, qty):
		return false
	if qty == 0:
		return true
	var batches: Array = _batches[id]
	var remaining: int = qty
	while remaining > 0:
		var batch: Dictionary = batches[0]
		var used: int = mini(remaining, int(batch["qty"]))
		batch["qty"] = int(batch["qty"]) - used
		remaining -= used
		if int(batch["qty"]) == 0:
			batches.pop_front()
	if batches.is_empty():
		_batches.erase(id)
	return true


## Atomically takes id -> quantity needs; malformed or short requests fail.
func take_many(needs: Dictionary) -> bool:
	var normalized: Dictionary[StringName, int] = {}
	for raw_id: Variant in needs:
		if typeof(raw_id) != TYPE_STRING and typeof(raw_id) != TYPE_STRING_NAME:
			return false
		if typeof(needs[raw_id]) != TYPE_INT:
			return false
		var id: StringName = StringName(raw_id)
		var qty: int = int(needs[raw_id])
		var previous: int = normalized.get(id, 0)
		if qty < 0 or qty > count(id) - previous:
			return false
		normalized[id] = previous + qty
	for id: StringName in normalized:
		take(id, normalized[id])
	return true


## Removes batches at bought_day + shelf life; unspecified ids never expire.
func expire(today: int, shelf_life_days: Dictionary) -> Dictionary:
	var expired: Dictionary = {}
	for id: StringName in _batches.keys():
		if not shelf_life_days.has(id) and not shelf_life_days.has(String(id)):
			continue
		var lifetime: int = int(shelf_life_days.get(id, shelf_life_days.get(String(id), 0)))
		var retained: Array[Dictionary] = []
		var expired_qty: int = 0
		for batch: Dictionary in _batches[id]:
			if today - int(batch["bought_day"]) >= lifetime:
				expired_qty += int(batch["qty"])
			else:
				retained.append(batch)
		if expired_qty > 0:
			expired[id] = expired_qty
		if retained.is_empty():
			_batches.erase(id)
		else:
			_batches[id] = retained
	return expired


## Returns independent batches; decimal strings preserve int64 values through JSON.
func to_dict() -> Dictionary:
	var batches: Dictionary = {}
	for id: StringName in _batches:
		var saved: Array[Dictionary] = []
		for batch: Dictionary in _batches[id]:
			saved.append({"qty": str(batch["qty"]), "bought_day": str(batch["bought_day"])})
		batches[String(id)] = saved
	return {"batches": batches}


## Restores batches without sharing the snapshot's arrays or dictionaries.
static func from_dict(d: Dictionary) -> Stock:
	var stock: Stock = Stock.new()
	var batches: Dictionary = d.get("batches", {})
	for id: Variant in batches:
		for batch: Dictionary in batches[id]:
			stock.add(StringName(id), int(batch["qty"]), int(batch["bought_day"]))
	return stock
