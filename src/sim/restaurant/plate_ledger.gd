class_name PlateLedger
extends RefCounted
## Conserved plate stock. Held plates belong to one order until collection or recovery.

const MAX_TOTAL: int = 9223372036854775807
const _MAX_TOTAL_DIV_TEN: int = 922337203685477580

var total: int:
	get:
		return _total
var clean: int:
	get:
		return _clean
var dirty: int:
	get:
		return _dirty
var in_use: int:
	get:
		return _tables_by_order.size()

var _total: int = 0
var _clean: int = 0
var _dirty: int = 0
var _tables_by_order: Dictionary[int, int] = {}
var _returned: Dictionary[int, bool] = {}
var _retired: Dictionary[int, bool] = {}


func _init(count: int = 0) -> void:
	_total = maxi(count, 0)
	_clean = _total


## Replaying the same live order succeeds without taking another plate.
func take(order_id: int, table_id: int) -> bool:
	if order_id <= 0 or table_id <= 0:
		return false
	if _tables_by_order.has(order_id):
		return _tables_by_order[order_id] == table_id
	if _retired.has(order_id) or _clean == 0:
		return false
	_tables_by_order[order_id] = table_id
	_clean -= 1
	return true


## A returned plate stays held until a server collects this table.
func return_to_table(order_id: int, table_id: int) -> bool:
	if order_id <= 0 or table_id <= 0 or not _tables_by_order.has(order_id):
		return false
	if _tables_by_order[order_id] != table_id:
		return false
	_returned[order_id] = true
	return true


## Multiple seats remain distinct: an active diner's plate cannot be collected.
func collect_table(table_id: int) -> int:
	if table_id <= 0:
		return 0
	var collected: int = 0
	for order_id: int in _tables_by_order.keys():
		if _tables_by_order[order_id] == table_id and _returned.has(order_id):
			if _retire_order(order_id):
				collected += 1
	return collected


## Cancellation also retires a not-yet-plated order, sealing late take callbacks.
## False means that no held plate moved; the positive order ID stays retired.
func recover_order(order_id: int) -> bool:
	if order_id <= 0:
		return false
	_retired[order_id] = true
	return _retire_order(order_id)


## Removing a table recovers both returned plates and active diners' plates.
func recover_table(table_id: int) -> int:
	if table_id <= 0:
		return 0
	var recovered: int = 0
	for order_id: int in _tables_by_order.keys():
		if _tables_by_order[order_id] == table_id:
			if _retire_order(order_id):
				recovered += 1
	return recovered


func wash_one() -> bool:
	if _dirty == 0:
		return false
	_dirty -= 1
	_clean += 1
	return true


## Morning is the only boundary that permits reuse of retired order IDs.
func tidy_overnight() -> void:
	_tables_by_order.clear()
	_returned.clear()
	_retired.clear()
	_dirty = 0
	_clean = _total


func has_order(order_id: int) -> bool:
	return _tables_by_order.has(order_id)


## Detached diagnostic state, with live and retired order IDs in ascending order.
## This service snapshot is never part of the saved section.
func state() -> Dictionary:
	var orders: Dictionary[int, Dictionary] = {}
	var order_ids: Array[int] = []
	order_ids.assign(_tables_by_order.keys())
	order_ids.sort()
	for order_id: int in order_ids:
		orders[order_id] = {
			"table_id": _tables_by_order[order_id],
			"returned": _returned.has(order_id),
		}
	var retired_ids: Array[int] = []
	retired_ids.assign(_retired.keys())
	retired_ids.sort()
	return {
		"total": total,
		"clean": clean,
		"dirty": dirty,
		"in_use": in_use,
		"orders": orders,
		"retired": retired_ids,
	}


## Only owned stock survives a save; decimal text preserves every int64 value.
func to_dict() -> Dictionary:
	return {"version": 1, "total": str(_total)}


## Validate the complete section before constructing a fresh, all-clean ledger.
static func from_dict(data: Dictionary) -> PlateLedger:
	if data.size() != 2 or not data.has("version") or not data.has("total"):
		return null
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or (key != "version" and key != "total"):
			return null
	var version: Variant = data["version"]
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return null
	# Godot's JSON parser represents the writer's integer version as a float.
	if version != 1:
		return null
	if typeof(data["total"]) != TYPE_STRING:
		return null
	var decoded_total: int = _decode_total(data["total"])
	if decoded_total < 0:
		return null
	return PlateLedger.new(decoded_total)


func _retire_order(order_id: int) -> bool:
	if not _tables_by_order.has(order_id):
		return false
	_tables_by_order.erase(order_id)
	_returned.erase(order_id)
	_retired[order_id] = true
	# A held plate existed, so dirty is strictly below total before this increment.
	_dirty += 1
	return true


static func _decode_total(text: String) -> int:
	if text.is_empty() or text.length() > 19 or (text.length() > 1 and text.begins_with("0")):
		return -1
	var decoded: int = 0
	for index: int in range(text.length()):
		var digit: int = text.unicode_at(index) - 48
		if digit < 0 or digit > 9 or decoded > _MAX_TOTAL_DIV_TEN \
				or (decoded == _MAX_TOTAL_DIV_TEN and digit > 7):
			return -1
		decoded = decoded * 10 + digit
	return decoded
