class_name MenuSettings
extends RefCounted
## Per-shop choices over an injected cookable catalog. Recipe resources stay unchanged.

signal owner_level_changed(level: int)

const MAX_PRICE: int = 9223372036854775807
const MAX_JSON_INTEGER: int = 9007199254740991
const MAX_PRICE_DIV_TEN: int = 922337203685477580
const DEFAULT_NAME: String = "Fool's Kitchen"
const MAX_NAME_LENGTH: int = 24
const SNAPSHOT_VERSION: int = 1
const DEFAULT_TUNING: MenuTuning = preload("res://data/balance/menu.tres")

var _valid: bool = false
var _recipes: Array[RecipeDef] = []
var _by_id: Dictionary[StringName, RecipeDef] = {}
var _standards: Dictionary[StringName, int] = {}
var _enabled: Dictionary[StringName, bool] = {}
var _prices: Dictionary[StringName, int] = {}
var _owner_level: int = 1
var _restaurant_name: String = DEFAULT_NAME
var _tuning: MenuTuning
## Choices of dishes whose station left (sold, or undone), restored if they
## come back the same session: {id: {"enabled": bool, "price": int}}. Not saved.
var _stash: Dictionary[StringName, Dictionary] = {}
## A dish switched on only because every enabled dish left the menu; it goes
## off again when stashed dishes come back (exact undo of a drinks-only menu).
var _fallback_id: StringName = &""
## Drinks a station change would have switched on but the full menu left off,
## in catalogue order; the menu panel names them. Not saved.
var _crowded_out: Array[StringName] = []


func _init(cookable_recipes: Array[RecipeDef] = [], owner_level: int = 1, tuning: MenuTuning = null) -> void:
	if cookable_recipes.is_empty() or owner_level < 1:
		return
	var source_tuning: MenuTuning = tuning if tuning != null else DEFAULT_TUNING
	if not source_tuning.is_valid():
		return
	_tuning = source_tuning.duplicate() as MenuTuning
	var seen: Dictionary[StringName, bool] = {}
	var available: int = 0
	for definition: RecipeDef in cookable_recipes:
		if definition == null or String(definition.id).strip_edges().is_empty() \
				or seen.has(definition.id) or definition.standard_price < 0 or definition.unlock_level < 1 \
				or not RecipeDef.Section.values().has(definition.section):
			return
		seen[definition.id] = true
		if definition.unlock_level <= owner_level:
			available += 1
	if available == 0:
		return
	_owner_level = owner_level
	_recipes.assign(cookable_recipes)
	_recipes.sort_custom(_recipe_before)
	for definition: RecipeDef in _recipes:
		_by_id[definition.id] = definition
		_standards[definition.id] = definition.standard_price
		if definition.unlock_level <= _owner_level and _enabled.size() < _tuning.limit_for_level(_owner_level):
			_enabled[definition.id] = true
		_prices[definition.id] = definition.standard_price
	_valid = true


func is_valid() -> bool:
	return _valid


func owner_level() -> int:
	return _owner_level


func restaurant_name() -> String:
	return _restaurant_name


func set_restaurant_name(value: String) -> bool:
	var next_name: String = normalized_restaurant_name(value)
	if not _valid or next_name.is_empty():
		return false
	_restaurant_name = next_name
	return true


func menu_limit() -> int:
	return _tuning.limit_for_level(_owner_level) if _valid else 0


## A level-up makes recipes selectable without changing today's chosen menu,
## even when an older save left the menu above its dish limit. A downgrade
## cannot leave a recipe enabled above the new level or the new limit.
func set_owner_level(value: int) -> bool:
	if not _valid or value < 1:
		return false
	if value < _owner_level and _enabled.size() > _tuning.limit_for_level(value):
		return false
	for id: StringName in _enabled:
		if _by_id[id].unlock_level > value:
			return false
	if value == _owner_level:
		return true
	_owner_level = value
	owner_level_changed.emit(value)
	return true


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
		if _by_id[id].unlock_level > _owner_level or (not _enabled.has(id) and _enabled.size() >= menu_limit()):
			return false
		_enabled[id] = true
	elif _enabled.has(id):
		if _enabled.size() == 1:
			return false
		_enabled.erase(id)
	return true


## The shop's stations changed (FK-083): a coffee machine bought or a drinks
## shelf sold. Dishes still cookable keep their choices and prices; newly
## cookable dishes join at their standard price, drinks switched on when
## unlocked and food switched off (a croissant waits for the player);
## dishes no longer cookable leave. At least one dish stays on. Returns
## whether the catalogue changed. An invalid list changes nothing.
func set_catalogue(cookable_recipes: Array[RecipeDef]) -> bool:
	if not _valid or cookable_recipes.is_empty():
		return false
	var next: MenuSettings = MenuSettings.new(cookable_recipes, _owner_level, _tuning)
	if not next.is_valid():
		return false
	var same: bool = next._recipes.size() == _recipes.size()
	if same:
		for index: int in range(_recipes.size()):
			same = same and next._recipes[index] == _recipes[index]
	if same:
		return false
	var enabled: Dictionary[StringName, bool] = {}
	var prices: Dictionary[StringName, int] = {}
	var restored_on: bool = false
	# Kept dishes count first; restored and new drinks join only while the
	# menu has room under the owner's dish limit (#181).
	var limit: int = menu_limit()
	var crowded: Array[StringName] = []
	for definition: RecipeDef in next._recipes:
		if _by_id.has(definition.id) and _enabled.has(definition.id):
			enabled[definition.id] = true
	for definition: RecipeDef in next._recipes:
		var id: StringName = definition.id
		if _by_id.has(id):
			prices[id] = clampi(_prices[id], next.minimum_price(id), next.maximum_price(id))
		elif _stash.has(id):
			var kept: Dictionary = _stash[id]
			prices[id] = clampi(int(kept["price"]), next.minimum_price(id), next.maximum_price(id))
			if bool(kept["enabled"]) and definition.unlock_level <= _owner_level:
				if enabled.size() < limit:
					enabled[id] = true
					restored_on = true
				elif definition.is_drink():
					crowded.append(id)
			_stash.erase(id)
		else:
			prices[id] = definition.standard_price
			# New drinks go on at once; a new dish waits for the player.
			if definition.unlock_level <= _owner_level and definition.is_drink():
				if enabled.size() < limit:
					enabled[id] = true
				else:
					crowded.append(id)
	if restored_on and not _fallback_id.is_empty() and enabled.has(_fallback_id) and enabled.size() > 1:
		enabled.erase(_fallback_id)
		_fallback_id = &""
	if enabled.is_empty():
		for definition: RecipeDef in next._recipes:
			if definition.unlock_level <= _owner_level:
				enabled[definition.id] = true
				if not _enabled.has(definition.id):
					_fallback_id = definition.id
				break
	for definition: RecipeDef in _recipes:
		if not next._by_id.has(definition.id):
			_stash[definition.id] = {"enabled": _enabled.has(definition.id), "price": _prices[definition.id]}
	_recipes = next._recipes
	_by_id = next._by_id
	_standards = next._standards
	_enabled = enabled
	_prices = prices
	var still_waiting: Array[StringName] = []
	for id: StringName in _crowded_out:
		if _by_id.has(id) and not _enabled.has(id):
			still_waiting.append(id)
	for id: StringName in crowded:
		if not _enabled.has(id) and not still_waiting.has(id):
			still_waiting.append(id)
	_crowded_out = still_waiting
	return true


## New drinks a full menu left off (see set_catalogue), still off and still
## on the catalogue, so the panel can say why they are not being served.
func crowded_out_drinks() -> Array[RecipeDef]:
	var result: Array[RecipeDef] = []
	for id: StringName in _crowded_out:
		if _by_id.has(id) and not _enabled.has(id):
			result.append(_by_id[id])
	return result


## Session-only memory ends with the edit history (each phase change).
func clear_stash() -> void:
	_stash.clear()
	_fallback_id = &""
	_crowded_out.clear()


## Known dishes accept a whole-dollar request and clamp it to their bounds.
func set_price(id: StringName, price: int) -> bool:
	if not _by_id.has(id) or _by_id[id].unlock_level > _owner_level:
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
	return {"version": SNAPSHOT_VERSION, "name": _restaurant_name, "enabled": enabled, "prices": prices}


## Validate the entire save section before replacing either set of choices.
## Integral JSON numbers are also accepted when their precision is unambiguous.
func from_dict(data: Variant) -> bool:
	if not _valid or typeof(data) != TYPE_DICTIONARY:
		return false
	var section: Dictionary = data
	var legacy: bool = not section.has("version")
	if section.size() != (2 if legacy else 4) or not section.has("enabled") or not section.has("prices"):
		return false
	var allowed_keys: Array[String] = ["enabled", "prices"]
	if not legacy:
		allowed_keys.append_array(["version", "name"])
	for key: Variant in section:
		if typeof(key) != TYPE_STRING or not allowed_keys.has(key):
			return false
	var next_name: String = DEFAULT_NAME
	if not legacy:
		var version: Variant = section["version"]
		if (typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT) or version != SNAPSHOT_VERSION \
				or not section.has("name") or typeof(section["name"]) != TYPE_STRING:
			return false
		var saved_name: String = section["name"]
		next_name = normalized_restaurant_name(saved_name)
		if next_name.is_empty():
			return false
	if typeof(section["enabled"]) != TYPE_ARRAY or typeof(section["prices"]) != TYPE_DICTIONARY:
		return false
	var enabled_data: Array = section["enabled"]
	var price_data: Dictionary = section["prices"]
	# A save from before the dish limit (no version) keeps an oversized menu:
	# FK-083 drinks could switch on 7-8 items at level 1. set_enabled adds
	# nothing more until the player is back under the limit.
	if enabled_data.is_empty() or (not legacy and enabled_data.size() > menu_limit()) \
			or price_data.size() > _recipes.size():
		return false
	var next_enabled: Dictionary[StringName, bool] = {}
	for value: Variant in enabled_data:
		if typeof(value) != TYPE_STRING:
			return false
		var id: StringName = StringName(value)
		if not _by_id.has(id) or next_enabled.has(id) \
				or _by_id[id].unlock_level > _owner_level:
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
	# A save cannot know a dish it never listed (newly authored, or a drink
	# left off because staff could not reach its station). It loads off at its
	# standard price; every enabled dish still needs an explicit saved price.
	for definition: RecipeDef in _recipes:
		if next_prices.has(definition.id):
			continue
		if next_enabled.has(definition.id):
			return false
		next_prices[definition.id] = definition.standard_price
	_enabled = next_enabled
	_prices = next_prices
	_restaurant_name = next_name
	return true


## Shared with request-only presentation and restored session data.
static func normalized_restaurant_name(value: String) -> String:
	var trimmed: String = value.strip_edges()
	if trimmed.is_empty() or trimmed.length() > MAX_NAME_LENGTH:
		return ""
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if code < 32 or (code >= 127 and code <= 159):
			return ""
	return trimmed


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
