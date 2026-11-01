class_name Stock
extends RefCounted
## Dated ingredient lots, with optional actual purchase values. Takes are
## atomic and FIFO. An old lot without a value is explicitly unrecorded.

const MAX_QUANTITY: int = 9223372036854775807
const MIN_DAY: int = -9223372036854775807 - 1

var _batches: Dictionary[StringName, Array] = {}
var _spoilage_day: int = 0
var _spoilage: Dictionary = PurchaseBasis.zero()


## total_cost is the entire lot's charged cost, including allocated premium.
## The default preserves legacy callers without inventing a historic price.
func add(id: StringName, qty: int, day: int, total_cost: int = -1) -> void:
	if id.is_empty() or qty <= 0 or qty > MAX_QUANTITY - count(id) or total_cost < -1:
		return
	var batches: Array = _batches.get(id, [])
	var insertion: int = batches.size()
	for index: int in range(batches.size()):
		if int(batches[index]["bought_day"]) > day:
			insertion = index
			break
	var batch: Dictionary = {"qty": qty, "bought_day": day}
	if total_cost >= 0:
		batch["total_cost"] = total_cost
	batches.insert(insertion, batch)
	_batches[id] = batches


func count(id: StringName) -> int:
	var total: int = 0
	for batch: Dictionary in _batches.get(id, []):
		total += int(batch["qty"])
	return total


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_batches.keys())
	return out


func has(id: StringName, qty: int) -> bool:
	return qty >= 0 and count(id) >= qty


## Existing quantity APIs retain their all-or-nothing behavior.
func take(id: StringName, qty: int) -> bool:
	if not has(id, qty):
		return false
	_take_value(id, qty)
	return true


func take_many(needs: Dictionary) -> bool:
	return bool(take_many_valued(needs)["taken"])


## Cost is captured in the same successful mutation that takes ingredients.
## Unavailable or oversized cost aggregates do not refuse physical stock.
func take_many_valued(needs: Dictionary) -> Dictionary:
	var normalized: Dictionary[StringName, int] = {}
	for raw_id: Variant in needs:
		if typeof(raw_id) != TYPE_STRING and typeof(raw_id) != TYPE_STRING_NAME:
			return {"taken": false, "cost": 0, "recorded": false}
		if typeof(needs[raw_id]) != TYPE_INT:
			return {"taken": false, "cost": 0, "recorded": false}
		var id: StringName = StringName(raw_id)
		var qty: int = int(needs[raw_id])
		var previous: int = normalized.get(id, 0)
		if qty < 0 or qty > count(id) - previous:
			return {"taken": false, "cost": 0, "recorded": false}
		normalized[id] = previous + qty
	var result: Dictionary = PurchaseBasis.zero()
	result["taken"] = true
	for id: StringName in normalized:
		PurchaseBasis.combine(result, _take_value(id, normalized[id]))
	return result


## The first remainder units cost one more whole unit. Recomputing from the
## remainder lot gives the same result for any fragmentation of FIFO takes.
@warning_ignore("integer_division")
func _take_value(id: StringName, qty: int) -> Dictionary:
	var result: Dictionary = PurchaseBasis.zero()
	if qty == 0:
		return result
	var batches: Array = _batches[id]
	var remaining: int = qty
	while remaining > 0:
		var batch: Dictionary = batches[0]
		var units: int = int(batch["qty"])
		var used: int = mini(remaining, units)
		if batch.has("total_cost"):
			var cost: int = int(batch["total_cost"])
			var used_cost: int = (cost / units) * used + mini(used, cost % units)
			batch["total_cost"] = cost - used_cost
			PurchaseBasis.combine(result, {"cost": used_cost, "recorded": true})
		else:
			result["recorded"] = false
		batch["qty"] = units - used
		remaining -= used
		if int(batch["qty"]) == 0:
			batches.pop_front()
	if batches.is_empty():
		_batches.erase(id)
	return result


## Inventory is valued at the remaining lot costs, never current list prices.
func value() -> Dictionary:
	var result: Dictionary = PurchaseBasis.zero()
	for id: StringName in _batches:
		for batch: Dictionary in _batches[id]:
			PurchaseBasis.combine(result, _batch_value(batch))
	return result


func expiring_on(today: int, shelf_life_days: Dictionary) -> Dictionary:
	var expiring: Dictionary = {}
	for id: StringName in _batches:
		if not shelf_life_days.has(id) and not shelf_life_days.has(String(id)):
			continue
		var lifetime: int = int(shelf_life_days.get(id, shelf_life_days.get(String(id), 0)))
		var qty: int = 0
		for batch: Dictionary in _batches[id]:
			if _expired(today, int(batch["bought_day"]), lifetime):
				qty += int(batch["qty"])
		if qty > 0:
			expiring[id] = qty
	return expiring


func expire(today: int, shelf_life_days: Dictionary) -> Dictionary:
	return expire_valued(today, shelf_life_days)["quantities"]


## Today's removed value survives the morning checkpoint. Repeating expiry
## after loading that morning adds no removed lots and retains the receipt.
func expire_valued(today: int, shelf_life_days: Dictionary) -> Dictionary:
	var result: Dictionary = PurchaseBasis.zero()
	var expired: Dictionary = {}
	for id: StringName in _batches.keys():
		if not shelf_life_days.has(id) and not shelf_life_days.has(String(id)):
			continue
		var lifetime: int = int(shelf_life_days.get(id, shelf_life_days.get(String(id), 0)))
		var retained: Array[Dictionary] = []
		var expired_qty: int = 0
		for batch: Dictionary in _batches[id]:
			if _expired(today, int(batch["bought_day"]), lifetime):
				expired_qty += int(batch["qty"])
				PurchaseBasis.combine(result, _batch_value(batch))
			else:
				retained.append(batch)
		if expired_qty > 0:
			expired[id] = expired_qty
		if retained.is_empty():
			_batches.erase(id)
		else:
			_batches[id] = retained
	if _spoilage_day != today:
		_spoilage_day = today
		_spoilage = PurchaseBasis.zero()
	PurchaseBasis.combine(_spoilage, result)
	result["quantities"] = expired
	return result


func spoilage_value(day: int) -> Dictionary:
	return _spoilage.duplicate() if day == _spoilage_day else PurchaseBasis.zero()


static func _batch_value(batch: Dictionary) -> Dictionary:
	return {"cost": int(batch.get("total_cost", 0)), "recorded": batch.has("total_cost")}


## Compare today >= bought + lifetime without overflowing signed dates.
static func _expired(today: int, bought: int, lifetime: int) -> bool:
	if lifetime > 0 and bought > MAX_QUANTITY - lifetime:
		return false
	if lifetime < 0 and bought < MIN_DAY - lifetime:
		return true
	return today >= bought + lifetime


func to_dict() -> Dictionary:
	var batches: Dictionary = {}
	for id: StringName in _batches:
		var saved: Array[Dictionary] = []
		for batch: Dictionary in _batches[id]:
			var row: Dictionary = {"qty": str(batch["qty"]), "bought_day": str(batch["bought_day"])}
			if batch.has("total_cost"):
				row["total_cost"] = str(batch["total_cost"])
			saved.append(row)
		batches[String(id)] = saved
	var result: Dictionary = {"batches": batches}
	if _spoilage_day != 0:
		result["spoilage"] = {"day": str(_spoilage_day), "cost": str(_spoilage["cost"]),
			"recorded": bool(_spoilage["recorded"])}
	return result


## Every candidate is checked before a stock can be installed. Old lots have
## no total_cost key and retain unknown basis; no current price is substituted.
static func from_dict(d: Dictionary) -> Stock:
	var stock: Stock = Stock.new()
	var raw_batches: Variant = d.get("batches", {})
	if not raw_batches is Dictionary:
		return null
	var batches: Dictionary = raw_batches
	for raw_id: Variant in batches:
		if not raw_id is String or (raw_id as String).is_empty() or not batches[raw_id] is Array:
			return null
		for raw_batch: Variant in batches[raw_id]:
			if not raw_batch is Dictionary:
				return null
			var batch: Dictionary = raw_batch
			var qty: int = PurchaseBasis.decode(batch.get("qty", null))
			var day_value: Variant = batch.get("bought_day", null)
			var parsed_day: Variant = _decode_day(day_value)
			if qty <= 0 or parsed_day == null or qty > MAX_QUANTITY - stock.count(StringName(raw_id)):
				return null
			var day: int = int(parsed_day)
			var cost: int = -1
			if batch.has("total_cost"):
				cost = PurchaseBasis.decode(batch["total_cost"])
				if cost < 0:
					return null
			stock.add(StringName(raw_id), qty, day, cost)
	if d.has("spoilage"):
		var raw_spoilage: Variant = d["spoilage"]
		if not raw_spoilage is Dictionary:
			return null
		var saved: Dictionary = raw_spoilage
		var parsed_day: Variant = _decode_day(saved.get("day", null))
		var cost: int = PurchaseBasis.decode(saved.get("cost", null))
		if parsed_day == null or cost < 0 or not saved.get("recorded", null) is bool:
			return null
		stock._spoilage_day = int(parsed_day)
		stock._spoilage = {"cost": cost, "recorded": saved["recorded"]}
	return stock


static func _decode_day(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		var number: float = value
		return int(number) if is_finite(number) and absf(number) <= 9007199254740991.0 \
			and floorf(number) == number else null
	if value is String and (value as String).begins_with("-"):
		if value == "-9223372036854775808":
			return MIN_DAY
		var magnitude: int = PurchaseBasis.decode((value as String).substr(1))
		return -magnitude if magnitude >= 0 else null
	var day: int = PurchaseBasis.decode(value)
	return day if day >= 0 else null
