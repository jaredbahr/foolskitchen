class_name WeatherTuning
extends Resource
## Relative daily chances, authored in data/balance/weather.tres. An empty
## resource is deliberately invalid instead of hiding unauthored defaults.

@export var sunny_weight: float = 0.0
@export var cloudy_weight: float = 0.0
@export var rain_weight: float = 0.0


func weights() -> PackedFloat64Array:
	return PackedFloat64Array([sunny_weight, cloudy_weight, rain_weight])


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	var values: PackedFloat64Array = weights()
	var names: PackedStringArray = ["Sunny", "Cloudy", "Rain"]
	for index: int in values.size():
		if not is_finite(values[index]) or values[index] < 0.0:
			errors.append("%s weight must be finite and non-negative" % names[index])
	if errors.is_empty():
		var total: float = sunny_weight + cloudy_weight + rain_weight
		if not is_finite(total) or total <= 0.0:
			errors.append("Weather weights must have a finite positive total")
	return errors


func is_valid() -> bool:
	return validate().is_empty()
