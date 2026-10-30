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


static func forecast_for(kind: int) -> String:
	return name_for(kind) + " today"


static func icon_for(kind: int) -> StringName:
	match kind:
		WeatherState.Kind.CLOUDY:
			return &"weather_cloudy"
		WeatherState.Kind.RAIN:
			return &"weather_rain"
	return &"weather_sunny"
