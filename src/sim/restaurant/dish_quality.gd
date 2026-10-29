class_name DishQuality
extends RefCounted
## A detached explanation of the exact kitchen calculation, including its clamp.

const TUNING: MenuTuning = preload("res://data/balance/menu.tres")

var recipe_base: float = 0.0
var skill: int = 1
var skill_factor: float = 0.0
var trait_bonus: float = 0.0
var station_bonuses: Array[float] = []
var station_names: Array[String] = []
var unclamped: float = 0.0
var quality: float = 0.0
var is_drink: bool = false


static func breakdown(recipe: RecipeDef, worker: StaffAgent, stations: Array[ItemDef],
		tuning: MenuTuning = TUNING) -> DishQuality:
	var result: DishQuality = DishQuality.new()
	result.recipe_base = recipe.base_quality
	result.is_drink = recipe.is_drink()
	var role: StringName = &"server" if result.is_drink else &"cook"
	result.skill = clampi(worker.skill_for(role) if worker != null else 1, 1, 5)
	result.skill_factor = tuning.quality_skill_base + tuning.quality_per_skill * result.skill
	result.unclamped = result.recipe_base * result.skill_factor
	# Drinks have always omitted cooking traits; preserve their quality exactly.
	if not result.is_drink and worker != null:
		result.trait_bonus = worker.cook_quality_bonus
		result.unclamped += result.trait_bonus
	for station: ItemDef in stations:
		result.station_names.append(station.display_name)
		result.station_bonuses.append(station.quality_bonus)
		result.unclamped += station.quality_bonus
	result.quality = clampf(result.unclamped, 0.0, 1.0)
	return result


func explanation() -> String:
	var text: String = "Recipe %.2f × %s skill %d (×%.2f)" % [recipe_base,
		"server" if is_drink else "cook", skill, skill_factor]
	if not is_drink:
		text += ", Cooking trait %+.2f" % trait_bonus
	for index: int in station_names.size():
		text += ", %s %+.2f" % [station_names[index], station_bonuses[index]]
	# End on the same star scale the menu and report use.
	text += " = %.2f (%.1f / 5 stars)" % [quality, quality * 5.0]
	if unclamped != quality:
		text += " (limited to 0–1)"
	return text
