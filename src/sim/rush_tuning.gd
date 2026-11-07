class_name RushTuning
extends Resource
## A short, announced surge (#325), fully described by balance data.

@export var unlock_level: int = 2
@export var min_gap_days: int = 4
@export_range(0.0, 1.0, 0.01) var daily_chance: float = 0.2
@export var min_duration_minutes: int = 45
@export var max_duration_minutes: int = 75
@export var ramp_minutes: int = 10
@export var opening_margin_minutes: int = 30
@export var last_orders_margin_minutes: int = 60
@export var peak_multiplier: float = 2.5
## Short, light occasions shown in the morning notice and evening report.
@export var occasions: PackedStringArray = PackedStringArray([
	"Book club", "Chess meet", "Garden circle", "Craft morning",
	"Walking group", "Choir practice", "Sketch club", "Local meetup",
])


func is_valid() -> bool:
	return unlock_level >= 1 and min_gap_days >= 1 \
		and is_finite(daily_chance) and daily_chance >= 0.0 and daily_chance <= 1.0 \
		and min_duration_minutes >= 1 and max_duration_minutes >= min_duration_minutes \
		and max_duration_minutes <= 240 and ramp_minutes >= 1 \
		and opening_margin_minutes >= 0 and opening_margin_minutes <= 240 \
		and last_orders_margin_minutes >= 0 and last_orders_margin_minutes <= 240 \
		and is_finite(peak_multiplier) and peak_multiplier >= 1.0 and peak_multiplier <= 5.0 \
		and occasions.size() >= 6 and occasions.size() <= 10 and _occasions_valid()


func _occasions_valid() -> bool:
	var seen: Dictionary[String, bool] = {}
	for occasion: String in occasions:
		var clean: String = occasion.strip_edges()
		if clean.is_empty() or clean.length() > 32 or seen.has(clean):
			return false
		seen[clean] = true
	return true
