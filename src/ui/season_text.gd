class_name SeasonText
extends RefCounted
## Plain player-facing names and stock tags for the current season.

static func name_for_day(day: int) -> String:
	match Season.kind_for_day(day):
		Season.Kind.SPRING:
			return "Spring"
		Season.Kind.SUMMER:
			return "Summer"
		Season.Kind.AUTUMN:
			return "Autumn"
		Season.Kind.WINTER:
			return "Winter"
	return "Spring"


static func ingredient_tag(ingredient_id: StringName, day: int, tuning: SeasonTuning) -> String:
	if ingredient_id.is_empty() or tuning == null:
		return ""
	var kind: Season.Kind = Season.kind_for_day(day)
	if tuning.is_in_season(ingredient_id, kind):
		return "In season"
	if tuning.is_out_of_season(ingredient_id, kind):
		return "Pricey this season"
	return ""
