class_name MenuSettings
extends RefCounted
## Per-shop choices over an injected cookable catalog. Recipe resources stay unchanged.

const MAX_PRICE: int = 9223372036854775807
const MAX_JSON_INTEGER: int = 9007199254740991
const MAX_PRICE_DIV_TEN: int = 922337203685477580

var _valid: bool = false
var _recipes: Array[RecipeDef] = []
var _by_id: Dictionary[StringName, RecipeDef] = {}
var _standards: Dictionary[StringName, int] = {}
var _enabled: Dictionary[StringName, bool] = {}
var _prices: Dictionary[StringName, int] = {}


func _init(cookable_recipes: Array[RecipeDef] = []) -> void:
	if cookable_recipes.is_empty():
		return
	var seen: Dictionary[StringName, bool] = {}
	for definition: RecipeDef in cookable_recipes:
		if definition == null or String(definition.id).strip_edges().is_empty() \
				or seen.has(definition.id) or definition.standard_price < 0:
			return
		seen[definition.id] = true
	_recipes.assign(cookable_recipes)
	_recipes.sort_custom(_recipe_before)
	for definition: RecipeDef in _recipes:
		_by_id[definition.id] = definition
		_standards[definition.id] = definition.standard_price
		_enabled[definition.id] = true
		_prices[definition.id] = definition.standard_price
	_valid = true


func is_valid() -> bool:
	return _valid


## New arrays in lexical ID order; callers cannot reorder the model's catalog.
func recipes() -> Array[RecipeDef]:
	return _recipes.duplicate()


func recipe(id: StringName) -> RecipeDef:
	return _by_id.get(id) as RecipeDef


func is_enabled(id: StringName) -> bool:
	return _enabled.has(id)


func enabled_count() -> int:
	return _enabled.size()


func enabled_recipes() -> Array[RecipeDef]:
	var result: Array[RecipeDef] = []
	for definition: RecipeDef in _recipes:
		if _enabled.has(definition.id):
			result.append(definition)
	return result


func price_of(definition: RecipeDef) -> int:
	if definition == null:
		return 0
	return _prices.get(definition.id, maxi(definition.standard_price, 0))


func standard_price(id: StringName) -> int:
	return _standards.get(id, 0)


func minimum_price(id: StringName) -> int:
	var standard: int = standard_price(id)
	# Exact ceil(standard / 2), without overflowing standard + 1 or using floats.
	return (standard >> 1) + (standard & 1)


func maximum_price(id: StringName) -> int:
	var standard: int = standard_price(id)
	return MAX_PRICE if standard > (MAX_PRICE >> 1) else standard * 2


func set_enabled(id: StringName, enabled: bool) -> bool:
	if not _by_id.has(id):
		return false
	if enabled:
		_enabled[id] = true
	elif _enabled.has(id):
		if _enabled.size() == 1:
			return false
		_enabled.erase(id)
	return true


## Known dishes accept a whole-dollar request and clamp it to their bounds.
func set_price(id: StringName, price: int) -> bool:
	if not _by_id.has(id):
		return false
	_prices[id] = clampi(price, minimum_price(id), maximum_price(id))
	return true


## Decimal strings preserve every int64 price through JSON's float parser.
func to_dict() -> Dictionary:
	if not _valid:
		return {}
	var enabled: Array[String] = []
	var prices: Dictionary[String, String] = {}
	for definition: RecipeDef in _recipes:
		var id: String = String(definition.id)
		if _enabled.has(definition.id):
			enabled.append(id)
		prices[id] = str(_prices[definition.id])
	return {"enabled": enabled, "prices": prices}


## Validate the entire save section before replacing either set of choices.
## Integral JSON numbers are also accepted when their precision is unambiguous.
func from_dict(data: Variant) -> bool:
	if not _valid or typeof(data) != TYPE_DICTIONARY:
		return false
	var section: Dictionary = data
	if section.size() != 2 or not section.has("enabled") or not section.has("prices"):
		return false
	for key: Variant in section:
		if typeof(key) != TYPE_STRING or (key != "enabled" and key != "prices"):
			return false
	if typeof(section["enabled"]) != TYPE_ARRAY or typeof(section["prices"]) != TYPE_DICTIONARY:
		return false
	var enabled_data: Array = section["enabled"]
	var price_data: Dictionary = section["prices"]
	if enabled_data.is_empty() or price_data.size() != _recipes.size():
		return false
	var next_enabled: Dictionary[StringName, bool] = {}
	for value: Variant in enabled_data:
		if typeof(value) != TYPE_STRING:
			return false
		var id: StringName = StringName(value)
		if not _by_id.has(id) or next_enabled.has(id):
			return false
		next_enabled[id] = true
	var next_prices: Dictionary[StringName, int] = {}
	for key: Variant in price_data:
		if typeof(key) != TYPE_STRING:
			return false
		var id: StringName = StringName(key)
		if not _by_id.has(id) or next_prices.has(id):
			return false
		var price: int = _decode_price(price_data[key])
		if price < minimum_price(id) or price > maximum_price(id):
			return false
		next_prices[id] = price
	_enabled = next_enabled
	_prices = next_prices
	return true


static func _decode_price(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return value if value >= 0 else -1
	if typeof(value) == TYPE_FLOAT:
		var float_price: float = float(value)
		if not is_finite(float_price) or float_price < 0.0 or float_price > MAX_JSON_INTEGER or floor(float_price) != float_price:
			return -1
		return int(float_price)
	if typeof(value) != TYPE_STRING:
		return -1
	var text: String = value
	if text.is_empty() or text.length() > 19 or (text.length() > 1 and text.begins_with("0")):
		return -1
	var parsed_price: int = 0
	for index: int in range(text.length()):
		var digit: int = text.unicode_at(index) - 48
		if digit < 0 or digit > 9 or parsed_price > MAX_PRICE_DIV_TEN \
				or (parsed_price == MAX_PRICE_DIV_TEN and digit > 7):
			return -1
		parsed_price = parsed_price * 10 + digit
	return parsed_price


static func _recipe_before(first: RecipeDef, second: RecipeDef) -> bool:
	return String(first.id) < String(second.id)
