class_name StockPanel
extends Control
## Request-only order cart (FK-087, from #54's Stock panel). Ingredients are
## grouped by where they are kept (Fridge, Freezer, Dry) with each group's
## used / capacity, −/+ steppers set the cart, the footer shows its running
## total, and a Next delivery bar counts down. The session pays, places and
## cancels orders and sends a fresh view back; nothing here touches stock or
## cash. Ingredients nothing on today's menu uses are greyed out, still orderable.

signal cart_requested(ingredient_id: StringName, qty: int)
signal order_requested()
signal clear_requested()
signal cancel_requested()
signal auto_requested(ingredient_id: StringName, enabled: bool)
signal target_requested(ingredient_id: StringName, target: int)
signal close_requested()

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const MUTED_COLOR: Color = Color("766b60")
const WARNING_COLOR: Color = Color("a83e35")
## Greyed-out rows (not on today's menu) fade, keeping their own colours.
const UNUSED_ALPHA: float = 0.55
const CART_STEPS: Array[int] = [-1, 1, 5]
const MAX_CART: int = 99

var _status: Label
var _notes: Label
var _rows_node: VBoxContainer
var _close: Button
var _delivery_label: Label
var _delivery_bar: ProgressBar
var _cart_total: Label
var _order: Button
var _clear: Button
var _pending: Label
var _cancel: Button
var _rows: Dictionary[StringName, Dictionary] = {}
var _groups: Dictionary[int, Dictionary] = {}
var _data: Array[Dictionary] = []
var _group_data: Array[Dictionary] = []
var _view: Dictionary = {}
var _layout_key: String = ""


func _ready() -> void:
	refresh()


## View: {rows, groups, cash, editable, notes, premium, cart_total,
## cart_refusal, pending, refund, delivery: {text, fraction}}.
## rows: {id, name, count, expiring, unit_cost, enabled, target, max_target,
## kind, in_use, cart, on_order}; groups: {kind, label, in_stock, on_order,
## capacity, cart}. Text is already player wording (rule 11).
func set_view(view: Dictionary) -> void:
	_view = view.duplicate(true)
	_data.assign(_view.get("rows", []))
	_group_data.assign(_view.get("groups", []))
	_bind_nodes()
	var notes: Array = _view.get("notes", [])
	_notes.text = "\n".join(PackedStringArray(notes))
	_notes.visible = not notes.is_empty()
	var key: String = ""
	for group: Dictionary in _group_data:
		key += "g%d;" % int(group["kind"])
	for data: Dictionary in _data:
		key += "%s:%d:%s;" % [data["id"], int(data.get("kind", 0)), data.get("in_use", true)]
	if key != _layout_key:
		_layout_key = key
		_rebuild_rows()
	refresh()


func refresh() -> void:
	_bind_nodes()
	var editable: bool = bool(_view.get("editable", false))
	var premium: float = float(_view.get("premium", 0.0))
	var premium_text: String = "a %d%% premium" % roundi(premium * 100.0) if premium > 0.0 else "list price"
	_status.text = ("Order any time: you pay now and the goods come with the next delivery. "
		+ "Auto-reorder tops each ingredient up to its target with the morning delivery, at %s." % premium_text)
	var delivery: Dictionary = _view.get("delivery", {})
	_delivery_label.text = str(delivery.get("text", "Next delivery: tomorrow morning"))
	_delivery_bar.value = clampf(float(delivery.get("fraction", 0.0)), 0.0, 1.0) * 100.0
	var free: Dictionary[int, int] = {}
	for group: Dictionary in _group_data:
		var kind: int = int(group["kind"])
		var capacity: int = int(group.get("capacity", 0))
		var in_stock: int = int(group.get("in_stock", 0))
		var on_order: int = int(group.get("on_order", 0))
		var cart: int = int(group.get("cart", 0))
		free[kind] = capacity - in_stock - on_order - cart
		if not _groups.has(kind):
			continue
		var parts: Dictionary = _groups[kind]
		(parts["title"] as Label).text = str(group.get("label", ""))
		var extra: Array[String] = []
		if on_order > 0:
			extra.append("%d on order" % on_order)
		if cart > 0:
			extra.append("%d in the cart" % cart)
		var space: Label = parts["space"]
		space.text = "%d / %d units%s" % [in_stock, capacity, (" (" + ", ".join(extra) + ")") if not extra.is_empty() else ""]
		var over: bool = in_stock + on_order > capacity
		space.add_theme_color_override("font_color", WARNING_COLOR if over else SHARED_THEME.get_color("font_color", "Label"))
		space.tooltip_text = "Over capacity: nothing more of this can be ordered until some is used." if over \
			else "%d units free" % maxi(0, capacity - in_stock - on_order)
		var bar: ProgressBar = parts["bar"]
		bar.value = 0.0 if capacity <= 0 else clampf(float(in_stock + on_order) / float(capacity), 0.0, 1.0) * 100.0
	for data: Dictionary in _data:
		var id: StringName = data["id"]
		if not _rows.has(id):
			continue
		_refresh_row(_rows[id], data, editable, int(free.get(int(data.get("kind", 0)), 0)))
	var total: int = int(_view.get("cart_total", 0))
	var refusal: String = str(_view.get("cart_refusal", ""))
	var cash: int = int(_view.get("cash", 0))
	_cart_total.text = "Order total: %s (cash %s)" % [Fmt.money(total), Fmt.money(cash)]
	_order.disabled = not editable or not refusal.is_empty()
	_order.tooltip_text = refusal if not refusal.is_empty() else "Pay %s now; it comes with the next delivery" % Fmt.money(total)
	_clear.disabled = not editable or _cart_units() <= 0
	_clear.tooltip_text = "Empty the cart"
	var pending: String = str(_view.get("pending", ""))
	_pending.text = pending if not pending.is_empty() else "Nothing on order."
	_pending.add_theme_color_override("font_color", SHARED_THEME.get_color("font_color", "Label") if not pending.is_empty() else MUTED_COLOR)
	_cancel.disabled = not editable or pending.is_empty()
	_cancel.tooltip_text = "Cancel everything on order for a full refund of %s" % Fmt.money(int(_view.get("refund", 0))) \
		if not pending.is_empty() else "Nothing on order"


func _refresh_row(row: Dictionary, data: Dictionary, editable: bool, free: int) -> void:
	var display: String = str(data.get("name", ""))
	var count: int = int(data.get("count", 0))
	var expiring: int = int(data.get("expiring", 0))
	var unit_cost: int = int(data.get("unit_cost", 0))
	var enabled: bool = bool(data.get("enabled", false))
	var target: int = int(data.get("target", 0))
	var max_target: int = int(data.get("max_target", ReorderSettings.MAX_TARGET))
	var in_use: bool = bool(data.get("in_use", true))
	var cart: int = int(data.get("cart", 0))
	var on_order: int = int(data.get("on_order", 0))
	(row["root"] as Control).modulate.a = 1.0 if in_use else UNUSED_ALPHA
	(row["name"] as Label).text = display
	var count_text: String = "%d in stock" % count
	if on_order > 0:
		count_text += ", %d on order" % on_order
	(row["count"] as Label).text = count_text
	var expiry: Label = row["expiry"]
	expiry.text = "%d expire tomorrow" % expiring if expiring > 0 \
		else ("0 expire tomorrow" if in_use else "Not on today's menu")
	expiry.add_theme_color_override("font_color", WARNING_COLOR if expiring > 0 else MUTED_COLOR)
	(row["price"] as Label).text = "$%d each" % unit_cost
	(row["cart"] as Label).text = str(cart)
	for step: int in CART_STEPS:
		var button: Button = row["cart%+d" % step]
		var after: int = cart + step
		if step < 0:
			button.disabled = not editable or cart <= 0
			button.tooltip_text = "Order fewer"
		else:
			var fits: bool = step <= free
			button.disabled = not editable or after > MAX_CART or not fits
			button.tooltip_text = ("Not enough %s space" % _space_word(int(data.get("kind", 0)))) if not fits \
				else "Add %d %s for $%d" % [step, display, unit_cost * step]
	var toggle: Button = row["auto"]
	toggle.set_pressed_no_signal(enabled)
	toggle.text = "Auto-reorder on" if enabled else "Auto-reorder off"
	toggle.disabled = not editable
	toggle.tooltip_text = "Each morning, top up to the target with the morning delivery." if enabled \
		else "Not bought automatically. Order it here by hand."
	(row["target"] as Label).text = str(target)
	var target_label: Label = row["target_label"]
	target_label.add_theme_color_override("font_color", SHARED_THEME.get_color("font_color", "Label") if enabled else MUTED_COLOR)
	var minus: Button = row["minus"]
	var plus: Button = row["plus"]
	minus.disabled = not editable or target <= 0
	plus.disabled = not editable or target >= max_target
	minus.tooltip_text = "Keep fewer in stock"
	plus.tooltip_text = "Keep more in stock"


static func _space_word(kind: int) -> String:
	return StorageSpace.SPACE_WORDS.get(kind, "dry storage")


func _cart_units() -> int:
	var units: int = 0
	for data: Dictionary in _data:
		units += int(data.get("cart", 0))
	return units


## Read-only access to generated controls for session tests and captures.
func row_for(ingredient_id: StringName) -> Dictionary:
	return _rows.get(ingredient_id, {})


func group_for(kind: int) -> Dictionary:
	return _groups.get(kind, {})


func _bind_nodes() -> void:
	if _rows_node != null:
		return
	_status = %Status
	_notes = %Notes
	_rows_node = %Rows
	_close = %Close
	_delivery_label = %DeliveryLabel
	_delivery_bar = %DeliveryBar
	_cart_total = %CartTotal
	_order = %Order
	_clear = %Clear
	_pending = %Pending
	_cancel = %Cancel
	IconStyle.decorate_label(get_node("Panel/Content/Title") as Label, &"stock")
	_close.pressed.connect(_on_close_pressed)
	_close.tooltip_text = "Close the stock panel (Esc)"
	_order.pressed.connect(_on_order_pressed)
	_clear.pressed.connect(_on_clear_pressed)
	_cancel.pressed.connect(_on_cancel_pressed)


func _rebuild_rows() -> void:
	for child: Node in _rows_node.get_children():
		_rows_node.remove_child(child)
		child.free()
	_rows.clear()
	_groups.clear()
	var index: int = 0
	for group: Dictionary in _group_data:
		var kind: int = int(group["kind"])
		var header: VBoxContainer = VBoxContainer.new()
		header.name = "Group%d" % kind
		header.theme = SHARED_THEME
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows_node.add_child(header)
		var line: HBoxContainer = _add_line(header, "Header")
		var title: Label = _add_label(line, "Title")
		title.add_theme_font_size_override("font_size", 22)
		title.custom_minimum_size.x = 130.0
		var space: Label = _add_label(line, "Space")
		space.mouse_filter = Control.MOUSE_FILTER_PASS
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		space.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		space.custom_minimum_size.x = 160.0
		var bar: ProgressBar = ProgressBar.new()
		bar.name = "Bar"
		bar.theme = SHARED_THEME
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.custom_minimum_size = Vector2(160.0, 14.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		_groups[kind] = {"root": header, "title": title, "space": space, "bar": bar}
		for data: Dictionary in _data:
			if int(data.get("kind", 0)) != kind:
				continue
			_rows[data["id"]] = _build_row(header, data["id"], index)
			index += 1


func _build_row(parent: Node, id: StringName, index: int) -> Dictionary:
	var row: VBoxContainer = VBoxContainer.new()
	row.name = "Ingredient%d" % index
	row.theme = SHARED_THEME
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var top: HBoxContainer = _add_line(row, "Top")
	var title: Label = _add_label(top, "Name")
	title.custom_minimum_size.x = 130.0
	var count: Label = _add_label(top, "Count")
	count.custom_minimum_size.x = 120.0
	count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var price: Label = _add_label(top, "Price")
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var parts: Dictionary = {"root": row, "name": title, "count": count, "price": price}
	var less: Button = _add_button(top, "CartMinus", "−")
	less.pressed.connect(_on_cart_step.bind(id, -1))
	parts["cart-1"] = less
	var amount: Label = _add_label(top, "Cart")
	amount.custom_minimum_size.x = 36.0
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parts["cart"] = amount
	for step: int in [1, 5]:
		var more: Button = _add_button(top, "CartPlus%d" % step, "+" if step == 1 else "+%d" % step)
		more.pressed.connect(_on_cart_step.bind(id, step))
		parts["cart%+d" % step] = more
	var detail: HBoxContainer = _add_line(row, "Reorder")
	var expiry: Label = _add_label(detail, "Expiry")
	# Wraps rather than widening the panel at large UI scales.
	expiry.custom_minimum_size.x = 120.0
	expiry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	expiry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var auto: Button = _add_button(detail, "Auto", "Auto-reorder on")
	auto.toggle_mode = true
	auto.toggled.connect(_on_auto_toggled.bind(id))
	var target_label: Label = _add_label(detail, "TargetLabel")
	target_label.text = "Target"
	var minus: Button = _add_button(detail, "Minus", "−")
	minus.pressed.connect(_on_target_step.bind(id, -1))
	var target: Label = _add_label(detail, "Target")
	target.custom_minimum_size.x = 36.0
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus: Button = _add_button(detail, "Plus", "+")
	plus.pressed.connect(_on_target_step.bind(id, 1))
	var separator: HSeparator = HSeparator.new()
	separator.theme = SHARED_THEME
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(separator)
	parts.merge({"expiry": expiry, "auto": auto, "target_label": target_label,
		"minus": minus, "target": target, "plus": plus})
	return parts


func _add_line(parent: Node, title: String) -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.name = title
	line.theme = SHARED_THEME
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return line


func _add_label(parent: Node, title: String) -> Label:
	var label: Label = Label.new()
	label.name = title
	label.theme = SHARED_THEME
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _add_button(parent: Node, title: String, text: String) -> Button:
	var button: Button = Button.new()
	button.name = title
	button.text = text
	button.theme = SHARED_THEME
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size.x = 44.0
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(button)
	return button


func _row_data(id: StringName) -> Dictionary:
	for data: Dictionary in _data:
		if data["id"] == id:
			return data
	return {}


func _on_cart_step(id: StringName, step: int) -> void:
	var data: Dictionary = _row_data(id)
	if not bool(_view.get("editable", false)) or data.is_empty():
		return
	var amount: int = clampi(int(data.get("cart", 0)) + step, 0, MAX_CART)
	if amount != int(data.get("cart", 0)):
		cart_requested.emit(id, amount)
	refresh()


func _on_order_pressed() -> void:
	if bool(_view.get("editable", false)):
		order_requested.emit()


func _on_clear_pressed() -> void:
	if bool(_view.get("editable", false)):
		clear_requested.emit()


func _on_cancel_pressed() -> void:
	if bool(_view.get("editable", false)):
		cancel_requested.emit()


func _on_auto_toggled(enabled: bool, id: StringName) -> void:
	if bool(_view.get("editable", false)) and bool(_row_data(id).get("enabled", false)) != enabled:
		auto_requested.emit(id, enabled)
	# Restore committed state even when the session rejects the request.
	refresh()


func _on_target_step(id: StringName, direction: int) -> void:
	var data: Dictionary = _row_data(id)
	if not bool(_view.get("editable", false)) or data.is_empty() or (direction != -1 and direction != 1):
		return
	var target: int = int(data.get("target", 0)) + direction
	if target < 0 or target > int(data.get("max_target", ReorderSettings.MAX_TARGET)):
		return
	target_requested.emit(id, target)
	refresh()


func _on_close_pressed() -> void:
	close_requested.emit()
