extends Container
## Keep the public direct-child paths while laying out three intact HUD groups.
## Native minimum sizes decide wrapping; neither text nor touch targets shrink.

const CONTROL_GAP: float = 6.0
const GROUP_GAP: float = 24.0
const ROW_GAP: float = 12.0
const GROUPS: Array[Array] = [
	["Day", "Time", "Phase", "Speed0", "Speed1", "Speed2", "Speed4"],
	["Cash", "Loan", "Reputation", "OwnerProgress", "Plates"],
	["Walls", "Build", "Paint", "Context", "Menu", "Staff", "Settings"],
]


func _get_minimum_size() -> Vector2:
	var measures: Array[Vector2] = _group_sizes()
	var minimum_width: float = 0.0
	for measure: Vector2 in measures:
		minimum_width = maxf(minimum_width, measure.x)
	var rows: Array[PackedInt32Array] = _rows(measures, maxf(size.x, minimum_width))
	var height: float = 0.0
	for row: PackedInt32Array in rows:
		if height > 0.0:
			height += ROW_GAP
		height += _row_height(row, measures)
	return Vector2(minimum_width, height)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		update_minimum_size()
		queue_sort()
	elif what == NOTIFICATION_SORT_CHILDREN:
		_layout_groups()


func _group_sizes() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for names: Array in GROUPS:
		var measure: Vector2 = Vector2.ZERO
		var count: int = 0
		for child_name: String in names:
			var child: Control = get_node_or_null(child_name) as Control
			if child == null or not child.visible:
				continue
			var minimum: Vector2 = child.get_combined_minimum_size()
			measure.x += minimum.x + (CONTROL_GAP if count > 0 else 0.0)
			measure.y = maxf(measure.y, minimum.y)
			count += 1
		result.append(measure)
	return result


func _rows(measures: Array[Vector2], width: float) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	var row: PackedInt32Array = PackedInt32Array()
	var used: float = 0.0
	for index: int in range(measures.size()):
		if measures[index].x <= 0.0:
			continue
		var needed: float = measures[index].x + (GROUP_GAP if not row.is_empty() else 0.0)
		if not row.is_empty() and used + needed > width:
			result.append(row)
			row = PackedInt32Array()
			used = 0.0
		row.append(index)
		used += measures[index].x + (GROUP_GAP if row.size() > 1 else 0.0)
	if not row.is_empty():
		result.append(row)
	return result


func _row_height(row: PackedInt32Array, measures: Array[Vector2]) -> float:
	var height: float = 0.0
	for index: int in row:
		height = maxf(height, measures[index].y)
	return height


func _layout_groups() -> void:
	var measures: Array[Vector2] = _group_sizes()
	var rows: Array[PackedInt32Array] = _rows(measures, size.x)
	var y: float = 0.0
	for row: PackedInt32Array in rows:
		var height: float = _row_height(row, measures)
		var starts: Dictionary[int, float] = {}
		if row.has(0):
			starts[0] = 0.0
		if row.has(2):
			starts[2] = size.x - measures[2].x
		if row.has(1):
			var left: float = measures[0].x + GROUP_GAP if row.has(0) else 0.0
			var right: float = starts[2] - GROUP_GAP - measures[1].x if row.has(2) else size.x - measures[1].x
			starts[1] = clampf((size.x - measures[1].x) * 0.5, left, right)
		for index: int in row:
			var x: float = starts[index]
			for child_name: String in GROUPS[index]:
				var child: Control = get_node_or_null(child_name) as Control
				if child == null or not child.visible:
					continue
				var minimum: Vector2 = child.get_combined_minimum_size()
				fit_child_in_rect(child, Rect2(Vector2(x, y + (height - minimum.y) * 0.5), minimum))
				x += minimum.x + CONTROL_GAP
		y += height + ROW_GAP
