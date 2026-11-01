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


static func forecast_for(kind: int, has_patio: bool = false) -> String:
	var text: String = name_for(kind) + " today"
	if has_patio:
		text += "  |  " + patio_for(kind)
	return text


static func patio_for(kind: int) -> String:
	return "Patio open today" if PatioRules.is_open(kind) else "Patio closed in rain"


static func icon_for(kind: int) -> StringName:
	match kind:
		WeatherState.Kind.CLOUDY:
			return &"weather_cloudy"
		WeatherState.Kind.RAIN:
			return &"weather_rain"
	return &"weather_sunny"
