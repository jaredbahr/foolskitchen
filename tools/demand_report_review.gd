extends "res://src/world/main.gd"
## Actual unsaved default service, not a staged demand forecast. Five real days
## earn reviews and word of mouth. Only UI scrolling follows the final close.

const REVIEW_DAYS: int = 5
var _review_ready: bool = false
var _review_frames: int = 0
var _review_state: Dictionary = {}
var _review_report: Dictionary = {}


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	for day_index: int in REVIEW_DAYS:
		if not Clock.sim.start_service():
			_review_fail("the real service did not open")
			return
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < 30:
			run_ticks(1000)
			batches += 1
		if Clock.sim.phase != SimClock.Phase.CLOSED or shown_report == null:
			_review_fail("the real service did not produce a closing report")
			return
		if day_index + 1 < REVIEW_DAYS and not Clock.sim.next_day():
			_review_fail("the next ordinary morning did not start")
			return
	Clock.set_speed(0)
	_review_state = BalanceProbe._control_snapshot(self, sim)
	_review_report = shown_report.to_dict().duplicate(true)
	_review_ready = true


func _process(_delta: float) -> void:
	if not _review_ready:
		return
	_review_frames += 1
	var section: Control = _report.get_node_or_null("Panel/Scroll/Content/DemandForecast") as Control
	if section == null:
		_review_fail("Tomorrow's crowd section is missing")
		return
	if _review_frames == 10:
		var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
		scroll.ensure_control_visible(section)
	elif _review_frames == 25:
		_review_validate(section)


func _review_validate(section: Control) -> void:
	var forecast: Variant = _review_report.get("demand_forecast")
	if not forecast is Dictionary or int(forecast.get("day", 0)) != REVIEW_DAYS + 1 \
			or int(forecast.get("expected_guests", -1)) < 0:
		_review_fail("the report lacks an actual next-day forecast")
		return
	for key: String in ["reputation", "word_of_mouth", "menu", "vibe", "curb_appeal", "total"]:
		var value: Variant = forecast.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) <= 0.0:
			_review_fail("the report has an invalid actual demand factor")
			return
	var heading: Label = section.get_node("Heading") as Label
	var summary: Label = section.get_node("Summary") as Label
	var factors: Label = section.get_node("Factors") as Label
	var explanation: Label = section.get_node("Explanation") as Label
	var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
	var expected_count: String = str(int(forecast["expected_guests"]))
	if not _report.is_visible_in_tree() or not section.is_visible_in_tree() \
			or heading.text != "Tomorrow's crowd" or not summary.text.contains(expected_count + " guests expected") \
			or factors.text.split("\n", false).size() != 5 or explanation.text.is_empty() \
			or not scroll.get_global_rect().grow(1.0).encloses(section.get_global_rect()) \
			or not get_viewport().get_visible_rect().encloses(section.get_global_rect()):
		_review_fail("the native forecast text is missing or clipped")
		return
	if _review_state != BalanceProbe._control_snapshot(self, sim) \
			or _review_report != shown_report.to_dict() or use_saves:
		_review_fail("rendering the report changed the session snapshot")
		return
	print("DEMAND_REPORT_REVIEW ", JSON.stringify({"fixture": "actual default seed1 five-day service; no saves or grants",
		"day": shown_report.day, "forecast": forecast, "heading": heading.text,
		"summary": summary.text, "factors": factors.text, "explanation": explanation.text,
		"rect": [section.global_position.x, section.global_position.y, section.size.x, section.size.y],
		"world_tick": world.now, "rng": GameState._capture_save(), "unchanged": true}))


func _review_fail(reason: String) -> void:
	_review_ready = false
	push_error("Demand report review: " + reason)
