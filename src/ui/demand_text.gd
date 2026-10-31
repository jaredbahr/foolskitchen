class_name DemandText
extends RefCounted
## Shared plain words for read-only demand forecasts and morning notices.

const FORECAST_HEADING: String = "Tomorrow's crowd"
const FORECAST_EXPLANATION: String = "Based on your current menu and shop."
const FACTOR_KEYS: Array[StringName] = [
	&"reputation", &"word_of_mouth", &"menu", &"vibe", &"curb_appeal",
]


static func factor_label(key: StringName) -> String:
	match key:
		&"reputation":
			return "Reputation"
		&"word_of_mouth":
			return "Word of mouth"
		&"menu":
			return "Menu variety"
		&"vibe":
			return "Vibe"
		&"curb_appeal":
			return CurbAppealText.TITLE
	return ""


static func change_text(factor: float) -> String:
	if not is_finite(factor) or factor <= 0.0:
		return "unavailable"
	var percent: float = (factor - 1.0) * 100.0
	if not is_finite(percent):
		return "very large increase"
	var rounded: float = roundf(percent)
	if rounded == 0.0:
		return "no change"
	return ("+" if rounded > 0.0 else "−") + "%.0f%%" % absf(rounded)


static func forecast_summary(forecast: Dictionary) -> String:
	var clean: Dictionary = DayReport.public_demand_forecast(forecast)
	if clean.is_empty():
		return ""
	var count: int = int(clean["expected_guests"])
	var guests: String = "guest" if count == 1 else "guests"
	return "About %d %s expected (demand %s)" % [count, guests, change_text(float(clean["total"]))]


static func factor_lines(forecast: Dictionary) -> PackedStringArray:
	var clean: Dictionary = DayReport.public_demand_forecast(forecast)
	var lines: PackedStringArray = []
	if clean.is_empty():
		return lines
	for key: StringName in FACTOR_KEYS:
		if key == &"curb_appeal":
			lines.append(CurbAppealText.forecast_line(float(clean[String(key)])))
		else:
			lines.append("%s: %s" % [factor_label(key), change_text(float(clean[String(key)]))])
	return lines


static func forecast_note(forecast: Dictionary) -> String:
	var clean: Dictionary = DayReport.public_demand_forecast(forecast)
	if clean.is_empty():
		return ""
	var combined: float = 1.0
	for key: StringName in FACTOR_KEYS:
		combined *= float(clean[String(key)])
	var total: float = float(clean["total"])
	if combined > total and not is_equal_approx(combined, total):
		return FORECAST_EXPLANATION + " Crowd growth is at its limit."
	return FORECAST_EXPLANATION


static func morning_status(factor: float, previous_factor: float) -> String:
	if not is_finite(factor) or not is_finite(previous_factor) \
			or factor <= 0.0 or previous_factor <= 0.0 or factor <= previous_factor:
		return ""
	return "Busier than yesterday"
