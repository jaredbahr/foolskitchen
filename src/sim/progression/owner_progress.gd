class_name OwnerProgress
extends RefCounted
## Pure day-close XP ledger. The caller persists this at the existing morning
## autosave; neither the model nor its decoder writes files or touches scenes.

const SAVE_VERSION: int = 1
const MAX_TOTAL_XP: int = 1000000000
const MAX_DAILY_COUNT: int = 1000000
const MAX_PROFIT_MAGNITUDE: int = 1000000000
const MAX_LEVEL: int = 1000000

var tuning: ProgressionTuning
var total_xp: int = 0
var level: int = 1
var property_tier: int = 1
## Persisted guard against awarding the same closing day twice.
var last_awarded_day: int = 0


func _init(config: ProgressionTuning) -> void:
	tuning = config


## Level one starts at zero; later levels use the authored power curve.
func threshold_for(target_level: int) -> int:
	if target_level <= 1:
		return 0
	if tuning == null or not tuning.is_valid() or target_level > MAX_LEVEL:
		return MAX_TOTAL_XP + 1
	var threshold: float = float(tuning.level_base) * pow(float(target_level), tuning.level_exponent)
	if threshold > float(MAX_TOTAL_XP):
		return MAX_TOTAL_XP + 1
	return ceili(threshold)


## Binary search keeps even a large, validated saved XP value cheap to load.
@warning_ignore("integer_division")
func level_at(xp: int) -> int:
	if xp <= 0 or tuning == null or not tuning.is_valid():
		return 1
	var low: int = 1
	var high: int = MAX_LEVEL + 1
	while high - low > 1:
		var middle: int = low + (high - low) / 2
		if threshold_for(middle) <= xp:
			low = middle
		else:
			high = middle
	return low


func xp_into_level() -> int:
	return total_xp - threshold_for(level)


func xp_in_level() -> int:
	return threshold_for(level + 1) - threshold_for(level)


## One row per finished day. Positive profit awards one step for each complete
## $10 by default; a negative day cannot subtract owner XP. Five-star reviews
## remain an optional count until the review feature is merged.
@warning_ignore("integer_division")
func award_day(day: int, happy_guests: int, profit: int, five_star_reviews: int = 0) -> Dictionary:
	if tuning == null or not tuning.is_valid() or day <= last_awarded_day \
			or happy_guests < 0 or happy_guests > MAX_DAILY_COUNT \
			or five_star_reviews < 0 or five_star_reviews > MAX_DAILY_COUNT \
			or profit < -MAX_PROFIT_MAGNITUDE or profit > MAX_PROFIT_MAGNITUDE:
		return {}
	var happy_xp: int = happy_guests * tuning.happy_guest_xp
	var profit_xp: int = int(maxi(0, profit) / tuning.profit_step) * tuning.profit_step_xp
	var review_xp: int = five_star_reviews * tuning.five_star_review_xp
	var gained: int = happy_xp + profit_xp + review_xp
	if gained > MAX_TOTAL_XP - total_xp:
		return {}
	var previous_level: int = level
	total_xp += gained
	level = level_at(total_xp)
	last_awarded_day = day
	var gained_levels: Array[int] = []
	for reached: int in range(previous_level + 1, level + 1):
		gained_levels.append(reached)
	return {"happy_xp": happy_xp, "profit_xp": profit_xp, "review_xp": review_xp,
		"total_xp": gained, "level_before": previous_level, "level_after": level,
		"levels_gained": gained_levels}


## Explicit non-daily XP, prepared by the milestone transaction after ordinary
## day XP. Zero is valid; neither success nor refusal changes the daily guard.
func award_bonus(amount: int) -> Dictionary:
	if tuning == null or not tuning.is_valid() or amount < 0 or amount > MAX_TOTAL_XP \
			or total_xp < 0 or total_xp > MAX_TOTAL_XP or amount > MAX_TOTAL_XP - total_xp \
			or level != level_at(total_xp) or last_awarded_day < 0 or last_awarded_day > MAX_TOTAL_XP:
		return {}
	var previous_level: int = level
	total_xp += amount
	level = level_at(total_xp)
	var gained_levels: Array[int] = []
	for reached: int in range(previous_level + 1, level + 1):
		gained_levels.append(reached)
	return {"bonus_xp": amount, "total_xp": amount, "level_before": previous_level,
		"level_after": level, "levels_gained": gained_levels}


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "total_xp": total_xp, "level": level,
		"last_awarded_day": last_awarded_day, "property_tier": property_tier}


## Decode a present section transactionally. The Main save provider supplies
## a fresh level-one model when older saves have no owner section at all.
func from_dict(value: Variant) -> bool:
	if tuning == null or not tuning.is_valid() or not value is Dictionary:
		return false
	var row: Dictionary = value
	if row.size() != (5 if row.has("property_tier") else 4) \
			or not _whole(row.get("property_tier", 1), 1, 2) or not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not _whole(row.get("total_xp"), 0, MAX_TOTAL_XP) \
			or not _whole(row.get("level"), 1, MAX_LEVEL) \
			or not _whole(row.get("last_awarded_day"), 0, MAX_TOTAL_XP):
		return false
	var saved_xp: int = int(row["total_xp"])
	var saved_level: int = int(row["level"])
	if saved_level != level_at(saved_xp):
		return false
	total_xp = saved_xp
	level = saved_level
	last_awarded_day = int(row["last_awarded_day"])
	property_tier = int(row.get("property_tier", 1))
	return true


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floor(number) == number
