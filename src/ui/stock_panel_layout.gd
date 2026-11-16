class_name StockPanelLayout
extends Container
## Keep the list and checkout in the same card at every scale. Wide cards put
## the controls beside the list so the catalogue can use the full card height.

const SIDE_WIDTH: float = 370.0
const COLUMN_GAP: float = 18.0
const ROW_GAP: float = 6.0

var wide: bool = false:
	set(value):
		if wide == value:
			return
		wide = value
		var total: Control = get_node_or_null("Cart/CartTotal") as Control
		if total != null:
			total.custom_minimum_size.x = SIDE_WIDTH if wide else 200.0
		update_minimum_size()
		queue_sort()


func _get_minimum_size() -> Vector2:
	var visible_items: Array[Control] = _visible_controls()
	if not wide:
		return _stack_size(visible_items)
	var title: Control = get_node_or_null("Title") as Control
	var list: Control = get_node_or_null("Scroll") as Control
	if title == null or list == null:
		return Vector2.ZERO
	visible_items.erase(title)
	visible_items.erase(list)
	var header: Vector2 = title.get_combined_minimum_size()
	var list_minimum: Vector2 = list.get_combined_minimum_size()
	var side_minimum: Vector2 = _stack_size(visible_items)
	return Vector2(maxf(header.x, list_minimum.x + COLUMN_GAP + maxf(side_minimum.x, SIDE_WIDTH)),
		header.y + ROW_GAP + maxf(list_minimum.y, side_minimum.y))


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var controls: Array[Control] = _visible_controls()
	var list: Control = get_node_or_null("Scroll") as Control
	var title: Control = get_node_or_null("Title") as Control
	if list == null or title == null:
		return
	if not wide:
		var list_extra: float = maxf(0.0, size.y - _stack_size(controls).y)
		var y: float = 0.0
		for control: Control in controls:
			var height: float = control.get_combined_minimum_size().y
			if control == list:
				height += list_extra
			fit_child_in_rect(control, Rect2(0.0, y, size.x, height))
			y += height + ROW_GAP
		return
	controls.erase(title)
	controls.erase(list)
	var title_height: float = title.get_combined_minimum_size().y
	fit_child_in_rect(title, Rect2(0.0, 0.0, size.x, title_height))
	var body_y: float = title_height + ROW_GAP
	var side_x: float = size.x - SIDE_WIDTH
	fit_child_in_rect(list, Rect2(0.0, body_y, side_x - COLUMN_GAP, size.y - body_y))
	for control: Control in controls:
		var height: float = control.get_combined_minimum_size().y
		fit_child_in_rect(control, Rect2(side_x, body_y, SIDE_WIDTH, height))
		body_y += height + ROW_GAP


func _visible_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for node: Node in get_children():
		var control: Control = node as Control
		if control != null and control.visible:
			controls.append(control)
	return controls


static func _stack_size(controls: Array[Control]) -> Vector2:
	var minimum: Vector2 = Vector2(0.0, ROW_GAP * maxi(controls.size() - 1, 0))
	for control: Control in controls:
		var child_minimum: Vector2 = control.get_combined_minimum_size()
		minimum.x = maxf(minimum.x, child_minimum.x)
		minimum.y += child_minimum.y
	return minimum
