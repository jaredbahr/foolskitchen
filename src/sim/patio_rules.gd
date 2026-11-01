class_name PatioRules
extends RefCounted
## Daily weather changes seating eligibility, never paths or random streams.


static func is_open(weather_kind: int) -> bool:
	return weather_kind == WeatherState.Kind.SUNNY or weather_kind == WeatherState.Kind.CLOUDY


static func seat_is_open(grid: SimGrid, cell: Vector2i, weather_kind: int) -> bool:
	return not grid.is_outdoor_floor(cell) or is_open(weather_kind)
