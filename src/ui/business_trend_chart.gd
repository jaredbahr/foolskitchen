class_name BusinessTrendChart
extends Control
## Two independently scaled tracks. Unknown profit never becomes a zero bar.

const TRACK_HEIGHT: float = 200.0
const GRAPH_TOP: float = 72.0
const GRAPH_HEIGHT: float = 54.0
const LEFT: float = 36.0

var _rows: Array[Dictionary] = []
var _today: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(0.0, TRACK_HEIGHT * 2.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)


func set_history(rows: Array[Dictionary], today: int) -> void:
	_today = maxi(0, today)
	_rows = BusinessTrendText.display_rows(rows, _today)
	queue_redraw()


## Serializable evidence of the layout used by _draw, including native bounds.
func review_snapshot() -> Dictionary:
	var days: Array[int] = []
	var labels: PackedStringArray = []
	var profits: Array[Variant] = []
	var served: Array[Variant] = []
	for day: int in range(maxi(1, _today - 6), _today + 1):
		days.append(day)
		labels.append(BusinessTrendText.day_label(day))
		var found: Dictionary = {}
		for row: Dictionary in _rows:
			if int(row["day"]) == day:
				found = row
		profits.append(found["dish_profit"] if not found.is_empty() \
			and bool(found["dish_profit_recorded"]) else null)
		served.append(found["served"] if not found.is_empty() else null)
	var rect: Rect2 = get_global_rect()
	var snapshot: Dictionary = {"today": _today, "today_index": days.find(_today), "days": days,
		"day_labels": labels, "profit_values": profits, "served_values": served,
		"chart_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"tracks": {"profit": _track(profits, days, 0.0),
			"served": _track(served, days, TRACK_HEIGHT)}}
	snapshot["labels"] = _labels(snapshot)
	return snapshot


func _track(values: Array[Variant], days: Array[int], top: float) -> Dictionary:
	var low: int = 0
	var high: int = 0
	for value: Variant in values:
		if value != null:
			low = mini(low, int(value))
			high = maxi(high, int(value))
	var span: float = maxf(1.0, float(high) - float(low))
	var plot: Rect2 = Rect2(LEFT, top + GRAPH_TOP, maxf(0.0, size.x - LEFT - 4.0), GRAPH_HEIGHT)
	var zero_y: float = plot.position.y + float(high) / span * plot.size.y
	var slot: float = plot.size.x / float(maxi(1, days.size()))
	var bars: Array[Dictionary] = []
	for index: int in values.size():
		if values[index] == null:
			continue
		var point_y: float = plot.position.y + (float(high) - float(values[index])) / span * plot.size.y
		var bar: Rect2 = Rect2(plot.position.x + slot * (float(index) + 0.2), minf(point_y, zero_y),
			slot * 0.6, maxf(1.0, absf(point_y - zero_y)))
		if values[index] == 0:
			bar.position.y = clampf(zero_y - 0.5, plot.position.y, plot.end.y - 1.0)
		bars.append({"day": days[index], "value": values[index], "index": index,
			"rect": [bar.position.x, bar.position.y, bar.size.x, bar.size.y]})
	return {"minimum": low, "maximum": high, "zero_y": zero_y,
		"rect": [plot.position.x, plot.position.y, plot.size.x, plot.size.y], "bars": bars}


func _draw() -> void:
	var snapshot: Dictionary = review_snapshot()
	var font: Font = get_theme_font("font", "Label")
	var font_size: int = get_theme_font_size("font_size", "Label")
	var ink: Color = get_theme_color("font_color", "Label")
	var accent: Color = (get_theme_stylebox("fill", "ProgressBar") as StyleBoxFlat).bg_color
	var muted: Color = (get_theme_stylebox("disabled", "Button") as StyleBoxFlat).border_color
	for key: String in ["profit", "served"]:
		var profit: bool = key == "profit"
		var track: Dictionary = snapshot["tracks"][key]
		var plot: Rect2 = _rect(track["rect"])
		var zero_y: float = float(track["zero_y"])
		draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y), Color(ink, 0.4))
		for bar: Dictionary in track["bars"]:
			draw_rect(_rect(bar["rect"]), accent if profit else muted)
		var slot: float = plot.size.x / float(maxi(1, (snapshot["days"] as Array).size()))
		if int(snapshot["today_index"]) >= 0:
			var left: float = plot.position.x + float(snapshot["today_index"]) * slot
			draw_rect(Rect2(left + 1.0, plot.position.y - 3.0, maxf(0.0, slot - 2.0),
				plot.size.y + 6.0), ink, false, 2.0)
	for label: Dictionary in snapshot["labels"]:
		var position: Array = label["position"]
		draw_string(font, Vector2(float(position[0]), float(position[1])), label["text"],
			HORIZONTAL_ALIGNMENT_LEFT, float(label["width"]), font_size, ink)


func _labels(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var font: Font = get_theme_font("font", "Label")
	var font_size: int = get_theme_font_size("font_size", "Label")
	var labels: PackedStringArray = snapshot["day_labels"]
	for key: String in ["profit", "served"]:
		var profit: bool = key == "profit"
		var track: Dictionary = snapshot["tracks"][key]
		var top: float = 0.0 if profit else TRACK_HEIGHT
		var title: String = BusinessTrendText.PROFIT_TRACK if profit else BusinessTrendText.SERVED_TRACK
		result.append(_label(key, "title", title, 0.0, size.x,
			top + font.get_ascent(font_size), false))
		var plot: Rect2 = _rect(track["rect"])
		result.append(_label(key, "zero", BusinessTrendText.profit_label(0) if profit \
			else BusinessTrendText.served_label(0), 0.0, LEFT,
			float(track["zero_y"]) + font.get_ascent(font_size) * 0.5, false))
		var values: Array = snapshot["profit_values"] if profit else snapshot["served_values"]
		var slot: float = plot.size.x / float(maxi(1, labels.size()))
		var day_baseline: float = plot.end.y + 10.0 + font.get_ascent(font_size)
		for index: int in labels.size():
			var left: float = plot.position.x + float(index) * slot
			var text: String = BusinessTrendText.GAP if values[index] == null else (
				BusinessTrendText.profit_label(int(values[index])) if profit \
				else BusinessTrendText.served_label(int(values[index])))
			result.append(_label(key, "value", text, left, slot, plot.position.y - 8.0, true))
			result.append(_label(key, "day", labels[index], left, slot, day_baseline, true))
			if index == int(snapshot["today_index"]):
				result.append(_label(key, "today", BusinessTrendText.TODAY, left, slot,
					day_baseline + font.get_height(font_size) + 6.0, true))
	return result


func _label(track: String, kind: String, text: String, left: float, width: float,
		baseline: float, centered: bool) -> Dictionary:
	var font: Font = get_theme_font("font", "Label")
	var font_size: int = get_theme_font_size("font_size", "Label")
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x: float = left + maxf(0.0, (width - text_width) * 0.5) if centered else left
	return {"track": track, "kind": kind, "text": text, "position": [x, baseline],
		"width": maxf(0.0, width), "rect": [x, baseline - font.get_ascent(font_size),
			minf(text_width, maxf(0.0, width)), font.get_height(font_size)]}


func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
