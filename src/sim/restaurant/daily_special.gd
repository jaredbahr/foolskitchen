class_name DailySpecial
extends RefCounted
## One morning choice. The session owns phase checks and its normal autosave.

const MAX_DAY: int = 9007199254740991
const PRICE_PARTS: int = 1000000
const DEFAULT_TUNING: MenuTuning = preload("res://data/balance/menu.tres")

var day: int = 1
var _recipe_id: StringName = &""
var _tuning: MenuTuning


func _init(config: MenuTuning = null) -> void:
	_tuning = (config if config != null else DEFAULT_TUNING).duplicate() as MenuTuning


func recipe_id() -> StringName:
	return _recipe_id


## Re-entering today's morning retains the choice; a different day clears it.
func begin_morning(next_day: int) -> bool:
	if next_day < 1 or next_day > MAX_DAY:
		return false
	if day != next_day:
		_recipe_id = &""
	day = next_day
	return true


func select(id: StringName, enabled: Array[RecipeDef]) -> bool:
	if not id.is_empty() and _find(id, enabled) == null:
		return false
	_recipe_id = id
	return true


## Disabling a dish or removing its station also removes its special offer.
func reconcile(enabled: Array[RecipeDef]) -> void:
	if _find(_recipe_id, enabled) == null:
		_recipe_id = &""


## Called after the ordinary private pick, before regular/critic overrides.
## No eligible special means no additional draw, including an empty menu.
func pick(ordinary: RecipeDef, choices: Array[RecipeDef], random: RandomNumberGenerator) -> RecipeDef:
	var special: RecipeDef = _find(_recipe_id, choices)
	if special == null or random == null or not _tuning.is_valid():
		return ordinary
	return special if random.randf() < _tuning.special_pull else ordinary


func price_for(recipe: RecipeDef, base_price: int) -> int:
	if recipe == null or recipe.id != _recipe_id or _recipe_id.is_empty() \
			or base_price <= 0 or not _tuning.is_valid():
		return base_price
	# Split before multiplying: even an int64 price remains exact and cannot
	# overflow. Data discounts are represented to one millionth, half-up.
	var parts: int = PRICE_PARTS - roundi(_tuning.special_discount * PRICE_PARTS)
	@warning_ignore("integer_division")
	var whole: int = base_price / PRICE_PARTS
	@warning_ignore("integer_division")
	var remainder: int = ((base_price % PRICE_PARTS) * parts + (PRICE_PARTS >> 1)) / PRICE_PARTS
	return whole * parts + remainder


func to_dict() -> Dictionary:
	return {"version": 1, "day": day, "recipe": String(_recipe_id)}


## Stage the entire section before installation. Old saves omit this section.
func from_dict(data: Variant, enabled: Array[RecipeDef], morning_day: int) -> bool:
	if typeof(data) != TYPE_DICTIONARY or morning_day < 1 or morning_day > MAX_DAY:
		return false
	var section: Dictionary = data
	if section.size() != 3:
		return false
	for key: Variant in section:
		if typeof(key) != TYPE_STRING or key not in ["version", "day", "recipe"]:
			return false
	var version: Variant = section.get("version")
	var saved_day: Variant = section.get("day")
	var saved_recipe: Variant = section.get("recipe")
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or version != 1 \
			or typeof(saved_day) not in [TYPE_INT, TYPE_FLOAT] \
			or not is_finite(float(saved_day)) or saved_day < 1 or saved_day > morning_day \
			or floor(float(saved_day)) != saved_day or typeof(saved_recipe) != TYPE_STRING:
		return false
	var id: StringName = StringName(saved_recipe)
	if not id.is_empty() and _find(id, enabled) == null:
		return false
	day = morning_day
	_recipe_id = id if saved_day == morning_day else &""
	return true


static func _find(id: StringName, choices: Array[RecipeDef]) -> RecipeDef:
	if not id.is_empty():
		for recipe: RecipeDef in choices:
			if recipe != null and recipe.id == id:
				return recipe
	return null
