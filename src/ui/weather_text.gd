class_name WeatherText
extends RefCounted
## One plain-language mapping for every weather readout.

static func name_for(kind: int) -> String:
	match kind:
		WeatherState.Kind.CLOUDY:
			return "Cloudy"
		WeatherState.Kind.RAIN:
			return "Rain"
	return "Sunny"


## `covered_seats` is the patio table seats under rain cover (#625); it only
## changes the words on a rainy day.
static func forecast_for(kind: int, has_patio: bool = false, covered_seats: int = 0) -> String:
	var text: String = name_for(kind) + " today"
	if has_patio:
		text += "  |  " + patio_for(kind, covered_seats)
	return text


static func patio_for(kind: int, covered_seats: int = 0) -> String:
	if PatioRules.is_open(kind):
		return "Patio open today"
	if covered_seats <= 0:
		return "Patio closed in rain (no cover)"
	if covered_seats == 1:
		return "1 covered patio seat stays open"
	return "%d covered patio seats stay open" % covered_seats


static func icon_for(kind: int) -> StringName:
	match kind:
		WeatherState.Kind.CLOUDY:
			return &"weather_cloudy"
		WeatherState.Kind.RAIN:
			return &"weather_rain"
	return &"weather_sunny"
