class_name ReorderSettings
extends RefCounted
## Per-ingredient morning auto-reorder choices {enabled, target} and the pure
## order plan built from them. The fixed ingredient order (EconomyTuning
## morning_stock key order) decides who is bought first when cash runs short.

const VERSION: int = 1
const MAX_TARGET: int = 99
## Integer basis points keep the premium free of float rounding (10 x $1 = $11).
const BASIS_POINTS: int = 10000

var _order: Array[StringName] = []
var _defaults: Dictionary[StringName, int] = {}
var _enabled: Dictionary[StringName, bool] = {}
var _target: Dictionary[StringName, int] = {}


## Defaults: every tuned ingredient is enabled with its morning_stock target,
## so a new game restocks exactly the same amounts as before this feature.
func _init(tuning: EconomyTuning = null) -> void:
	if tuning == null:
		return
	for id: StringName in tuning.morning_stock:
		var amount: int = clampi(int(tuning.morning_stock[id]), 0, MAX_TARGET)
		_order.append(id)
		_defaults[id] = amount
		_enabled[id] = true
		_target[id] = amount


## Ingredient ids in the fixed buying order.
func ids() -> Array[StringName]:
	return _order.duplicate()


func has(id: StringName) -> bool:
	return _defaults.has(id)


func is_enabled(id: StringName) -> bool:
	return bool(_enabled.get(id, false))


func target(id: StringName) -> int:
	return int(_target.get(id, 0))


func default_target(id: StringName) -> int:
	return int(_defaults.get(id, 0))


func set_enabled(id: StringName, enabled: bool) -> bool:
	if not has(id):
		return false
	_enabled[id] = enabled
	return true


func set_target(id: StringName, amount: int) -> bool:
	if not has(id) or amount < 0 or amount > MAX_TARGET:
		return false
	_target[id] = amount
	return true


## A detached copy for staged morning changes.
func copy() -> ReorderSettings:
	var other: ReorderSettings = ReorderSettings.new()
	other._order = _order.duplicate()
	other._defaults = _defaults.duplicate()
	other._enabled = _enabled.duplicate()
	other._target = _target.duplicate()
	return other


## Versioned plain data for the morning autosave.
func to_dict() -> Dictionary:
	var rows: Dictionary = {}
	for id: StringName in _order:
		rows[String(id)] = {"enabled": is_enabled(id), "target": target(id)}
	return {"version": VERSION, "ingredients": rows}


## Validates everything before changing anything. Ingredients the save does
## not mention keep their defaults; ids this shop no longer stocks are ignored.
func from_dict(data: Dictionary) -> bool:
	var version: Variant = data.get("version", null)
	if not _is_whole(version) or int(version) < 1 or int(version) > VERSION:
		return false
	var rows: Variant = data.get("ingredients", null)
	if not rows is Dictionary:
		return false
	var enabled: Dictionary[StringName, bool] = _enabled.duplicate()
	var targets: Dictionary[StringName, int] = _target.duplicate()
	for key: Variant in rows:
		if typeof(key) != TYPE_STRING:
			return false
		var row: Variant = rows[key]
		if not row is Dictionary:
			return false
		var on: Variant = (row as Dictionary).get("enabled", null)
		var amount: Variant = (row as Dictionary).get("target", null)
		if typeof(on) != TYPE_BOOL or not _is_whole(amount) \
				or int(amount) < 0 or int(amount) > MAX_TARGET:
			return false
		var id: StringName = StringName(key)
		if not has(id):
			continue
		enabled[id] = on
		targets[id] = int(amount)
	_enabled = enabled
	_target = targets
	return true


## The premium is charged once on a whole order: ceil(list_total * (1 + premium)).
static func auto_cost(list_total: int, premium: float) -> int:
	if list_total <= 0:
		return 0
	if not is_finite(premium) or premium <= 0.0:
		return list_total
	var points: int = roundi(premium * BASIS_POINTS)
	@warning_ignore("integer_division")
	var extra: int = (list_total * points + BASIS_POINTS - 1) / BASIS_POINTS
	return list_total + extra


## Plans one morning order without touching stock or cash. Each enabled
## ingredient is topped up to its target; when cash runs short, ingredients
## are taken in the fixed order and each gets as many units as still fit, the
## partial order being priced as its own total. Never plans to borrow.
## Returns {lines: [{id, qty, unit_cost}], list_total, cost, short: {id: qty}}.
func plan(stock: Stock, unit_costs: Dictionary, cash: int, premium: float) -> Dictionary:
	var lines: Array[Dictionary] = []
	var short: Dictionary[StringName, int] = {}
	var list_total: int = 0
	var budget: int = maxi(cash, 0)
	for id: StringName in _order:
		if not is_enabled(id) or not unit_costs.has(id):
			continue
		var missing: int = target(id) - stock.count(id)
		if missing <= 0:
			continue
		var unit_cost: int = maxi(0, int(unit_costs[id]))
		var qty: int = missing
		while qty > 0 and auto_cost(list_total + qty * unit_cost, premium) > budget:
			qty -= 1
		if qty > 0:
			lines.append({"id": id, "qty": qty, "unit_cost": unit_cost})
			list_total += qty * unit_cost
		if qty < missing:
			short[id] = missing - qty
	return {"lines": lines, "list_total": list_total,
		"cost": auto_cost(list_total, premium), "short": short}


static func _is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and floorf(float(value)) == float(value)
