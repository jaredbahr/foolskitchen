class_name SignatureState
extends RefCounted
## Lifetime paid dishes and one house signature. The caller supplies the full
## known catalogue, current phase/day and enabled menu; no session is consulted.

const VERSION: int = 1
const MAX_EXACT_INTEGER: int = SignatureTuning.MAX_EXACT_INTEGER

var _known_ids: Dictionary[StringName, bool] = {}
var _sales: Dictionary[StringName, int] = {}
var _signature_id: StringName = &""
var _last_change_day: int = 0


func _init(known_recipe_ids: Array[StringName] = []) -> void:
	# Copy IDs rather than retaining a caller-owned catalogue or menu dictionary.
	for recipe_id: StringName in known_recipe_ids:
		if not recipe_id.is_empty():
			_known_ids[recipe_id] = true


## Call for paid dishes only, never merely placed, cooked or delivered orders.
func record_sale(recipe_id: StringName, quantity: int = 1) -> bool:
	if not _known_ids.has(recipe_id) or quantity < 1 or quantity > MAX_EXACT_INTEGER:
		return false
	var previous: int = sales_for(recipe_id)
	if quantity > MAX_EXACT_INTEGER - previous:
		return false
	_sales[recipe_id] = previous + quantity
	return true


func sales_for(recipe_id: StringName) -> int:
	return _sales.get(recipe_id, 0)


func lifetime_sales() -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for recipe_id: StringName in _sales:
		result[recipe_id] = _sales[recipe_id]
	return result


func signature_recipe_id() -> StringName:
	return _signature_id


func last_changed_day() -> int:
	return _last_change_day


func eligible(recipe_id: StringName, tuning: SignatureTuning) -> bool:
	return tuning != null and tuning.is_valid() and _known_ids.has(recipe_id) \
		and sales_for(recipe_id) >= tuning.signature_unlock_sales


func can_select(recipe_id: StringName, day: int, phase: int,
		tuning: SignatureTuning) -> bool:
	if phase != SimClock.Phase.MORNING or day < 1 or day > MAX_EXACT_INTEGER \
			or day < _last_change_day or not eligible(recipe_id, tuning):
		return false
	return _signature_id.is_empty() or recipe_id == _signature_id \
		or day - _last_change_day >= tuning.change_cooldown_days


func select(recipe_id: StringName, day: int, phase: int,
		tuning: SignatureTuning) -> bool:
	if not can_select(recipe_id, day, phase, tuning):
		return false
	if recipe_id != _signature_id:
		_signature_id = recipe_id
		_last_change_day = day
	return true


## Disabling a dish does not erase the choice or restart its cooldown.
func demand_factor(enabled_recipe_ids: Array[StringName], tuning: SignatureTuning) -> float:
	if _signature_id.is_empty() or tuning == null or not tuning.is_valid() \
			or not enabled_recipe_ids.has(_signature_id):
		return 1.0
	return tuning.signature_demand_bonus


## New game/reset keeps the known catalogue, never aliases caller-owned state.
func clear() -> void:
	_sales.clear()
	_signature_id = &""
	_last_change_day = 0


func to_dict() -> Dictionary:
	var counts: Dictionary = {}
	var ids: Array[StringName] = []
	for recipe_id: StringName in _sales:
		ids.append(recipe_id)
	ids.sort()
	for recipe_id: StringName in ids:
		counts[String(recipe_id)] = _sales[recipe_id]
	return {"version": VERSION, "sales": counts, "signature_id": String(_signature_id),
		"last_change_day": _last_change_day}


## Missing legacy sections use a fresh object. A present section must be fully
## valid; Main stages this candidate until every section of the save is valid.
func from_dict(value: Variant, saved_day: int, tuning: SignatureTuning) -> bool:
	if not value is Dictionary or saved_day < 1 or saved_day > MAX_EXACT_INTEGER \
			or tuning == null or not tuning.is_valid():
		return false
	var row: Dictionary = value
	if row.size() != 4 or not _whole(row.get("version"), VERSION, VERSION) \
			or not row.get("sales") is Dictionary \
			or not row.get("signature_id") is String \
			or not _whole(row.get("last_change_day"), 0, saved_day):
		return false
	var next_sales: Dictionary[StringName, int] = {}
	var source_sales: Dictionary = row["sales"]
	for key: Variant in source_sales:
		if typeof(key) != TYPE_STRING or not _known_ids.has(StringName(key)) \
				or not _whole(source_sales[key], 0, MAX_EXACT_INTEGER):
			return false
		next_sales[StringName(key)] = int(source_sales[key])
	var next_id: StringName = StringName(row["signature_id"])
	var next_day: int = int(row["last_change_day"])
	if next_id.is_empty():
		if next_day != 0:
			return false
	# A signature chosen under an older, lower unlock threshold stays chosen:
	# a balance change must never make an old save unloadable.
	elif not _known_ids.has(next_id) or next_day < 1:
		return false
	_sales = next_sales
	_signature_id = next_id
	_last_change_day = next_day
	return true


static func _whole(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high and floor(number) == number
