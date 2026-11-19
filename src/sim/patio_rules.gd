class_name PatioRules
extends RefCounted
## Daily weather changes seating eligibility, never paths or random streams.


static func is_open(weather_kind: int) -> bool:
	return weather_kind == WeatherState.Kind.SUNNY or weather_kind == WeatherState.Kind.CLOUDY


## A patio seat is open in fair weather, and in rain only under rain cover (#625).
static func seat_is_open(grid: SimGrid, cell: Vector2i, weather_kind: int) -> bool:
	return not grid.is_outdoor_floor(cell) or is_open(weather_kind) or grid.is_rain_covered(cell)


## Patio table seats under rain cover (#625), for the rainy-day forecast line.
static func covered_seat_count(grid: SimGrid) -> int:
	var count: int = 0
	for placed: PlacedItem in grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition == null or definition.category != ItemDef.Category.TABLE:
			continue
		for seat: Vector2i in placed.seat_cells:
			if grid.is_outdoor_floor(seat) and grid.is_rain_covered(seat):
				count += 1
	return count


## Seating only: an open patio seat takes a new guest only while the kitchen
## keeps up (RestaurantSim.patio_keeping_up). Outdoor tables then add covers
## instead of overfilling a busy shop until guests time out.
## `keeping_up` is only called for an open outdoor seat; invalid means yes.
static func can_seat(grid: SimGrid, cell: Vector2i, weather_kind: int, keeping_up: Callable = Callable()) -> bool:
	if not grid.is_outdoor_floor(cell):
		return true
	return (is_open(weather_kind) or grid.is_rain_covered(cell)) \
		and (not keeping_up.is_valid() or keeping_up.call())
