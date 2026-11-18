class_name MenuPresetLibrary
extends RefCounted
## In-memory named snapshots of menu choices, saved by the owning session.

const VERSION: int = 1
const MAX_PRESETS: int = 8

var _presets: Array[Dictionary] = []


## Adds a named copy of editable cookable prices and enabled dishes.
func save_menu(name: String, menu: MenuSettings) -> bool:
	var normalized: String = MenuSettings.normalized_restaurant_name(name)
	if normalized.is_empty() or _name_in_use(normalized) or menu == null \
			or not menu.is_valid() or _presets.size() >= MAX_PRESETS:
		return false
	var enabled: Array[StringName] = []
	var prices: Dictionary[StringName, int] = {}
	for recipe: RecipeDef in menu.recipes():
		if recipe == null or recipe.id.is_empty() or prices.has(recipe.id):
			return false
		if recipe.unlock_level > menu.owner_level():
			continue
		prices[recipe.id] = menu.price_of(recipe)
		if menu.is_enabled(recipe.id):
			enabled.append(recipe.id)
	if enabled.is_empty() or prices.is_empty():
		return false
	_presets.append({"name": normalized, "enabled": enabled, "prices": prices})
	return true


## Names are returned in preset insertion order.
func names() -> Array[String]:
	var result: Array[String] = []
	for preset: Dictionary in _presets:
		result.append(String(preset["name"]))
	return result


## Returns detached arrays and dictionaries so callers cannot edit a preset in place.
func get_preset(index: int) -> Dictionary:
	if index < 0 or index >= _presets.size():
		return {}
	return _presets[index].duplicate(true)


func index_of_name(name: String) -> int:
	var folded_name: String = name.to_lower()
	for index: int in _presets.size():
		if String(_presets[index]["name"]).to_lower() == folded_name:
			return index
	return -1


func rename(index: int, name: String) -> bool:
	var normalized: String = MenuSettings.normalized_restaurant_name(name)
	if index < 0 or index >= _presets.size() or normalized.is_empty() \
			or _name_in_use(normalized, index):
		return false
	_presets[index]["name"] = normalized
	return true


func remove(index: int) -> bool:
	if index < 0 or index >= _presets.size():
		return false
	_presets.remove_at(index)
	return true


## JSON-safe snapshot. Decimal strings preserve every nonnegative int64 price.
func to_save() -> Dictionary:
	var rows: Array[Dictionary] = []
	for preset: Dictionary in _presets:
		var enabled: Array[String] = []
		for recipe_id: StringName in preset["enabled"]:
			enabled.append(String(recipe_id))
		var prices: Dictionary[String, String] = {}
		var source_prices: Dictionary = preset["prices"]
		for recipe_id: StringName in source_prices:
			prices[String(recipe_id)] = str(int(source_prices[recipe_id]))
		rows.append({"name": String(preset["name"]), "enabled": enabled, "prices": prices})
	return {"version": VERSION, "presets": rows}


## Decodes into a staging array and replaces live state only after full validation.
## Recipe availability is intentionally not checked here; the apply path handles it.
func restore(data: Dictionary) -> bool:
	for key: Variant in data:
		if typeof(key) != TYPE_STRING:
			return false
	if data.size() != 2 or not data.has("version") or not data.has("presets") \
			or not (data["version"] is int or data["version"] is float) or data["version"] != VERSION \
			or not data["presets"] is Array:
		return false
	var rows: Array = data["presets"]
	if rows.size() > MAX_PRESETS:
		return false
	var staged: Array[Dictionary] = []
	var seen_names: Dictionary[String, bool] = {}
	for value: Variant in rows:
		if not value is Dictionary:
			return false
		var row: Dictionary = value
		for key: Variant in row:
			if typeof(key) != TYPE_STRING:
				return false
		if row.size() != 3 or not row.has("name") or not row.has("enabled") or not row.has("prices") \
				or not row["name"] is String or not row["enabled"] is Array \
				or not row["prices"] is Dictionary:
			return false
		var name: String = MenuSettings.normalized_restaurant_name(String(row["name"]))
		var folded_name: String = name.to_lower()
		if name.is_empty() or seen_names.has(folded_name):
			return false
		seen_names[folded_name] = true
		var enabled: Array[StringName] = []
		var enabled_seen: Dictionary[StringName, bool] = {}
		for raw_id: Variant in row["enabled"]:
			if not raw_id is String or String(raw_id).is_empty():
				return false
			var recipe_id: StringName = StringName(raw_id)
			if enabled_seen.has(recipe_id):
				return false
			enabled_seen[recipe_id] = true
			enabled.append(recipe_id)
		if enabled.is_empty():
			return false
		var prices: Dictionary[StringName, int] = {}
		var raw_prices: Dictionary = row["prices"]
		for raw_id: Variant in raw_prices:
			if not raw_id is String or String(raw_id).is_empty():
				return false
			var recipe_id: StringName = StringName(raw_id)
			if prices.has(recipe_id):
				return false
			var raw_price: Variant = raw_prices[raw_id]
			if not raw_price is String:
				return false
			var price: int = MenuSettings.decode_saved_price(raw_price)
			if price < 0:
				return false
			prices[recipe_id] = price
		for recipe_id: StringName in enabled:
			if not prices.has(recipe_id):
				return false
		staged.append({"name": name, "enabled": enabled, "prices": prices})
	_presets = staged
	return true


func _name_in_use(name: String, except_index: int = -1) -> bool:
	var folded_name: String = name.to_lower()
	for index: int in range(_presets.size()):
		if index == except_index:
			continue
		if String(_presets[index]["name"]).to_lower() == folded_name:
			return true
	return false
