class_name StockPanel
extends Control
## Request-only morning view of the fridge. The session buys, changes reorder
## settings and sends fresh rows back; nothing here touches stock or cash.

signal buy_requested(ingredient_id: StringName, qty: int)
signal auto_requested(ingredient_id: StringName, enabled: bool)
signal target_requested(ingredient_id: StringName, target: int)
signal close_requested()

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const MUTED_COLOR: Color = Color("766b60")
const WARNING_COLOR: Color = Color("a83e35")
const MORNING_HINT: String = "Buying and reorder changes are available in the morning."
const BUY_AMOUNTS: Array[int] = [1, 5]

var _status: Label
var _notes: Label
var _rows_node: VBoxContainer
var _close: Button
var _rows: Dictionary[StringName, Dictionary] = {}
var _data: Array[Dictionary] = []
var _cash: int = 0
var _editable: bool = false
var _premium_text: String = "a small premium"


func _ready() -> void:
	refresh()


## Rows: {id, name, count, expiring, unit_cost, enabled, target, max_target}.
## Notes are short player sentences about this morning's order.
func set_stock(rows: Array[Dictionary], cash: int, editable: bool, notes: Array[String] = [],
		premium: float = 0.1) -> void:
	var ids_changed: bool = rows.size() != _data.size()
	if not ids_changed:
		for index: int in range(rows.size()):
			if rows[index].get("id") != _data[index].get("id"):
				ids_changed = true
				break
	_data = rows.duplicate(true)
	_cash = cash
	_editable = editable
	_premium_text = "a %d%% premium" % roundi(premium * 100.0) if premium > 0.0 else "list price"
	_bind_nodes()
	_notes.text = "\n".join(notes)
	_notes.visible = not notes.is_empty()
	if ids_changed:
		_rebuild_rows()
	refresh()


func refresh() -> void:
	_bind_nodes()
	_status.text = ("Buy now at list price, or let auto-reorder top each ingredient up to its target every morning at %s." % _premium_text) \
		if _editable else MORNING_HINT
	for data: Dictionary in _data:
		var id: StringName = data["id"]
		if not _rows.has(id):
			continue
		var row: Dictionary = _rows[id]
		var display: String = str(data.get("name", ""))
		var count: int = int(data.get("count", 0))
		var expiring: int = int(data.get("expiring", 0))
		var unit_cost: int = int(data.get("unit_cost", 0))
		var enabled: bool = bool(data.get("enabled", false))
		var target: int = int(data.get("target", 0))
		var max_target: int = int(data.get("max_target", ReorderSettings.MAX_TARGET))
		(row["name"] as Label).text = display
		(row["count"] as Label).text = "%d in the fridge" % count
		var expiry: Label = row["expiry"]
		expiry.text = "%d expire tomorrow" % expiring if expiring > 0 else "0 expire tomorrow"
		expiry.add_theme_color_override("font_color", WARNING_COLOR if expiring > 0 else MUTED_COLOR)
		(row["price"] as Label).text = "$%d each" % unit_cost
		for amount: int in BUY_AMOUNTS:
			var button: Button = row["buy%d" % amount]
			var affordable: bool = _cash >= unit_cost * amount
			button.disabled = not _editable or not affordable
			button.tooltip_text = MORNING_HINT if not _editable else (
				"Buy %d %s for $%d" % [amount, display, unit_cost * amount] if affordable
				else "Not enough cash for %d" % amount)
		var toggle: Button = row["auto"]
		toggle.set_pressed_no_signal(enabled)
		toggle.text = "Auto-reorder on" if enabled else "Auto-reorder off"
		toggle.disabled = not _editable
		toggle.tooltip_text = MORNING_HINT if not _editable else (
			"Each morning, top up to the target at %s." % _premium_text if enabled
			else "Not bought automatically. Buy it here by hand.")
		(row["target"] as Label).text = str(target)
		var target_label: Label = row["target_label"]
		target_label.add_theme_color_override("font_color", SHARED_THEME.get_color("font_color", "Label") if enabled else MUTED_COLOR)
		var minus: Button = row["minus"]
		var plus: Button = row["plus"]
		minus.disabled = not _editable or target <= 0
		plus.disabled = not _editable or target >= max_target
		minus.tooltip_text = MORNING_HINT if not _editable else "Keep fewer in the fridge"
		plus.tooltip_text = MORNING_HINT if not _editable else "Keep more in the fridge"


## Read-only access to generated controls for session tests and captures.
func row_for(ingredient_id: StringName) -> Dictionary:
	return _rows.get(ingredient_id, {})


func _bind_nodes() -> void:
	if _rows_node != null:
		return
	_status = %Status
	_notes = %Notes
	_rows_node = %Rows
	_close = %Close
	IconStyle.decorate_label(get_node("Panel/Content/Title") as Label, &"stock")
	_close.pressed.connect(_on_close_pressed)
	_close.tooltip_text = "Close the stock panel (Esc)"


func _rebuild_rows() -> void:
	for child: Node in _rows_node.get_children():
		_rows_node.remove_child(child)
		child.free()
	_rows.clear()
	var index: int = 0
	for data: Dictionary in _data:
		var id: StringName = data["id"]
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "Ingredient%d" % index
		row.theme = SHARED_THEME
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows_node.add_child(row)
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
		for amount: int in BUY_AMOUNTS:
			var buy: Button = _add_button(top, "Buy%d" % amount, "+%d" % amount)
			buy.pressed.connect(_on_buy_pressed.bind(id, amount))
			parts["buy%d" % amount] = buy
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
		_rows[id] = parts
		index += 1


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
	button.custom_minimum_size.x = 52.0
	parent.add_child(button)
	return button


func _row_data(id: StringName) -> Dictionary:
	for data: Dictionary in _data:
		if data["id"] == id:
			return data
	return {}


func _on_buy_pressed(id: StringName, qty: int) -> void:
	if _editable:
		buy_requested.emit(id, qty)
	refresh()


func _on_auto_toggled(enabled: bool, id: StringName) -> void:
	if _editable and bool(_row_data(id).get("enabled", false)) != enabled:
		auto_requested.emit(id, enabled)
	# Restore committed state even when the session rejects the request.
	refresh()


func _on_target_step(id: StringName, direction: int) -> void:
	var data: Dictionary = _row_data(id)
	if not _editable or data.is_empty() or (direction != -1 and direction != 1):
		return
	var target: int = int(data.get("target", 0)) + direction
	if target < 0 or target > int(data.get("max_target", ReorderSettings.MAX_TARGET)):
		return
	target_requested.emit(id, target)
	refresh()


func _on_close_pressed() -> void:
	close_requested.emit()
