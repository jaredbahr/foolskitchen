extends "res://src/world/main.gd"
## Two actual, paid default weeks in ordinary Main (30 days with --trend-days=30).
## Only report presentation
## follows the final close; no grants, setup edits, day reset or RNG reset.

const REVIEW_SCENE: String = "res://tools/business_trend_review.tscn"
const REVIEW_FRAME: int = 60

var _review_ready: bool = false
var _review_days: int = 14
var _review_range: int = 7
var _review_frames: int = 0
var _review_out: String = ""
var _review_initial_state: Dictionary = {}
var _review_state: Dictionary = {}
var _review_report: Dictionary = {}
var _review_history: Array[Dictionary] = []
var _review_daily: Array[Dictionary] = []


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_review_out = argument.trim_prefix("--out=")
		elif argument == "--trend-days=30":
			_review_days = 30
			_review_range = 30
		elif argument.begins_with("--trend-days=") and argument != "--trend-days=7":
			_review_fail("--trend-days must be 7 or 30")
			return
	if _review_out.is_empty() or FileAccess.file_exists(_review_out.path_join("shot_0060.png")) \
			or FileAccess.file_exists(_review_out.path_join("shot_0060.json")):
		_review_fail("a new capture output directory is required")
		return
	super._ready()
	Clock.set_speed(0)
	if sim == null or Clock.sim.day != 1 or Clock.sim.phase != SimClock.Phase.MORNING \
			or GameState.master_seed != 1 or not business_history.summaries().is_empty():
		_review_fail("the ordinary seed-one morning did not start with empty history")
		return
	_review_initial_state = BalanceProbe._control_snapshot(self, sim)
	# Main already prepared paid stock and the ordinary morning RNG state.
	for day_index: int in range(_review_days):
		if not Clock.sim.start_service():
			_review_fail("the ordinary service did not open")
			return
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < 30:
			run_ticks(1000)
			batches += 1
		if Clock.sim.phase != SimClock.Phase.CLOSED or shown_report == null \
				or shown_report.day != day_index + 1 or shown_report.customers_served <= 0 \
				or not shown_report.operating_profit_recorded():
			_review_fail("the ordinary paid service did not produce its recorded closing report")
			return
		var history: Array[Dictionary] = business_history.summaries()
		var good_reviews: int = 0
		for review: Dictionary in shown_report.review_cards:
			if int(review["stars"]) >= 4:
				good_reviews += 1
		var dishes: Dictionary[String, int] = {}
		for dish: StringName in shown_report.dishes_sold:
			dishes[String(dish)] = shown_report.dishes_sold[dish]
		var actual: Dictionary = {"day": shown_report.day, "served": shown_report.customers_served,
			"lost": shown_report.customers_lost, "dish_profit": shown_report.operating_profit(),
			"dish_profit_recorded": true, "cash_change": shown_report.profit(),
			"reputation": shown_report.reputation_after,
			"weekly_profit": shown_report.purchase_basis_operating_profit(),
			"good_reviews": good_reviews, "no_table": shown_report.leave_reasons.get(&"no_table", 0),
			"dishes_sold": dishes}
		if history.size() != day_index + 1 or history[-1] != actual:
			_review_fail("stored history differs from the closing report on day %d" % shown_report.day)
			return
		_review_daily.append({"day": shown_report.day, "cash": Economy.cash,
			"world_tick": world.now, "report": shown_report.to_dict(), "history_row": actual})
		if day_index + 1 < _review_days and not Clock.sim.next_day():
			_review_fail("the next ordinary morning did not start")
			return
	Clock.set_speed(0)
	_review_state = BalanceProbe._control_snapshot(self, sim)
	_review_report = shown_report.to_dict().duplicate(true)
	_review_history = business_history.summaries()
	# A normal growth notice can leave Staff open; its Close restores the report.
	if is_staff_visible() and not set_staff_visible(false):
		_review_fail("the ordinary Staff close did not restore the report")
		return
	if _review_range == 30:
		var button: Button = _report.get_node("%BusinessTrendSection/BusinessTrendRanges/Days30") as Button
		button.pressed.emit()
	print("BUSINESS_TREND_SERVICE_RESULT ", JSON.stringify({"scene": REVIEW_SCENE,
		"profile": "ordinary Main seed1 default; no additional day or RNG reset; differs from BalanceProbe initialization",
		"days": _review_days, "initial_state": _review_initial_state,
		"daily": _review_daily, "history": _review_history, "report": _review_report}))
	_review_ready = true


func _process(_delta: float) -> void:
	if not _review_ready:
		return
	_review_frames += 1
	if not _review_unchanged():
		_review_fail("report presentation changed the closed session or its history")
		return
	var section: Control = _report.get_node_or_null("%BusinessTrendSection") as Control
	if section == null:
		_review_fail("Business trend section is missing")
		return
	if _review_frames == 10:
		var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
		scroll.ensure_control_visible(section)
	elif _review_frames >= 25:
		# screenshot.gd saves its frame60 PNG and sidecar in this same signal.
		# Its quit is deferred, so the receipt can bind those actual saved bytes.
		RenderingServer.frame_post_draw.connect(_review_validate, CONNECT_ONE_SHOT)


func _review_validate() -> void:
	if not _review_ready:
		return
	var section: Control = _report.get_node("%BusinessTrendSection") as Control
	var heading: Label = _report.get_node("%BusinessTrendHeading") as Label
	var summary: Label = _report.get_node("%BusinessTrendSummary") as Label
	var chart: BusinessTrendChart = _report.get_node("%BusinessTrendChart") as BusinessTrendChart
	var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
	var drawing: Dictionary = chart.review_snapshot()
	var rows: Array[Dictionary] = _review_history.slice(maxi(0, _review_history.size() - _review_range))
	var days: Array[int] = []
	var labels: PackedStringArray = []
	for row: Dictionary in rows:
		days.append(int(row["day"]))
		labels.append(BusinessTrendText.day_label(int(row["day"])))
	if not _review_unchanged() or shown_report.day != _review_days \
			or heading.text != "Business trend" or summary.text != BusinessTrendText.summary(_review_history, _review_days) \
			or summary.text.is_empty() or not _report.is_visible_in_tree() \
			or drawing.get("days") != days or drawing.get("range_days") != _review_range \
			or drawing.get("day_labels") != labels or drawing.get("today_index") != rows.size() - 1:
		_review_fail("the native chart labels, today highlight or summary differ from actual history")
		return
	var profits: Array[int] = []
	var served: Array[int] = []
	for row: Dictionary in rows:
		profits.append(int(row["dish_profit"]))
		served.append(int(row["served"]))
	if drawing.get("profit_values") != profits or drawing.get("served_values") != served \
			or not _review_chart_geometry(chart, drawing, days):
		_review_fail("the drawn values differ from actual paid service history")
		return
	var clip: Rect2 = scroll.get_global_rect().grow(1.0)
	var viewport: Rect2 = get_viewport().get_visible_rect().grow(1.0)
	for control: Control in [section, heading, summary, chart]:
		if not control.is_visible_in_tree() or not clip.encloses(control.get_global_rect()) \
				or not viewport.encloses(control.get_global_rect()):
			_review_fail("the native chart, day labels or summary are hidden or clipped")
			return
	if is_staff_visible() or is_menu_visible() or is_stock_visible() \
			or is_settings_visible() or is_goals_visible():
		_review_fail("another native panel obscures Business trend")
		return
	var png: String = _review_out.path_join("shot_0060.png")
	if not FileAccess.file_exists(png):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(png.get_basename() + ".json"))
	if not parsed is Dictionary:
		_review_fail("the actual screenshot sidecar is missing or invalid")
		return
	var metadata: Dictionary = parsed
	var image_hash: String = FileAccess.get_sha256(png)
	if metadata.get("scene") != REVIEW_SCENE or metadata.get("frame") != REVIEW_FRAME \
			or metadata.get("image_file") != "shot_0060.png" or metadata.get("image_sha256") != image_hash \
			or image_hash.length() != 64 or metadata.get("capture_timing") != "frame_post_draw" \
			or metadata.get("width") != 1600 or metadata.get("height") != 900 \
			or metadata.get("engine_errors") != 0 or metadata.get("master_seed") != "1" \
			or metadata.get("world_tick") != world.now or not _review_unchanged():
		_review_fail("the saved frame60 PNG identity differs from this unchanged native service")
		return
	var source_hashes: Dictionary = {}
	for path: String in ["tools/business_trend_review.gd", "src/world/main.gd", "src/sim/business_history.gd",
			"src/ui/business_trend_chart.gd", "src/ui/business_trend_text.gd", "src/ui/evening_report.gd",
			"src/ui/evening_report.tscn", "tools/screenshot.gd"]:
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
	print("BUSINESS_TREND_REPORT_REVIEW ", JSON.stringify({
		"fixture": "actual ordinary Main seed1 default paid service; no grants, setup edits or saves",
		"profile": "ordinary Main morning; no additional day or RNG reset; differs from BalanceProbe initialization",
		"scene": REVIEW_SCENE, "seed": str(GameState.master_seed), "days": _review_days,
		"day": shown_report.day, "cash": Economy.cash, "world_tick": world.now,
		"history": _review_history, "history_sha256": JSON.stringify(_review_history).sha256_text(),
		"report": _review_report, "report_sha256": JSON.stringify(_review_report).sha256_text(),
		"heading": heading.text, "summary": summary.text, "chart": drawing,
		"player_meaning": "Actual paid service supplies the comparison and chart; the selected range shows dish profit and guests separately, with today highlighted.",
		"section_rect": _review_rect(section), "summary_rect": _review_rect(summary),
		"chart_rect": _review_rect(chart), "scroll_rect": _review_rect(scroll),
		"viewport_rect": [viewport.position.x, viewport.position.y, viewport.size.x, viewport.size.y],
		"image_file": "shot_0060.png", "image_sha256": image_hash,
		"image_metadata_sha256": FileAccess.get_sha256(png.get_basename() + ".json"),
		"frame": REVIEW_FRAME, "validation_timing": "frame_post_draw",
		"source_files_sha256": source_hashes, "rng": GameState._capture_save(), "unchanged": true}))
	_review_ready = false


func _review_chart_geometry(chart: BusinessTrendChart, drawing: Dictionary, days: Array[int]) -> bool:
	if drawing.get("chart_rect") != _review_rect(chart):
		return false
	var bounds: Rect2 = Rect2(Vector2.ZERO, chart.size).grow(1.0)
	var font: Font = chart.get_theme_font("font", "Label")
	var font_size: int = chart.get_theme_font_size("font_size", "Label")
	var tracks: Dictionary = drawing.get("tracks", {})
	for key: String in ["profit", "served"]:
		var track: Dictionary = tracks.get(key, {})
		var values: Array = track.get("rect", [])
		if values.size() != 4:
			return false
		var plot: Rect2 = Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
		var bars: Array = track.get("bars", [])
		if not bounds.encloses(plot) or bars.size() != days.size() \
				or float(track.get("zero_y", -1)) < plot.position.y \
				or float(track.get("zero_y", -1)) > plot.end.y:
			return false
		for index: int in days.size():
			var bar: Dictionary = bars[index]
			var rect: Array = bar.get("rect", [])
			if rect.size() != 4 or bar.get("day") != days[index] or bar.get("index") != index \
					or not bounds.encloses(Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))):
				return false
	for label: Dictionary in drawing.get("labels", []):
		var rect: Array = label["rect"]
		if not bounds.encloses(Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))) \
				or font.get_string_size(String(label["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x \
				> float(label["width"]):
			return false
	return true


func _review_unchanged() -> bool:
	return not use_saves and shown_report != null and Clock.sim.phase == SimClock.Phase.CLOSED \
		and _review_state == BalanceProbe._control_snapshot(self, sim) \
		and _review_report == shown_report.to_dict() and _review_history == business_history.summaries()


func _review_rect(control: Control) -> Array[float]:
	var rect: Rect2 = control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _review_fail(reason: String) -> void:
	_review_ready = false
	push_error("Business trend review: " + reason)
