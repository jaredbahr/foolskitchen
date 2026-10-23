extends Control
## Standalone closing report. Integration supplies data and handles Next day.

signal next_day_pressed

const LEAVE_LABELS: Dictionary = {
	&"waited_too_long": "Waited too long",
	&"too_expensive": "Too expensive",
	&"no_table": "No table available",
}
const PROFIT_GREEN: Color = Color("38764b")
const LOSS_RED: Color = Color("a83e35")

@onready var _header: Label = %Header
@onready var _profit: Label = %Profit
@onready var _income: GridContainer = %IncomeRows
@onready var _costs: GridContainer = %CostRows
@onready var _dishes: GridContainer = %DishRows
@onready var _guests: Label = %Guests
@onready var _guest_bar: ProgressBar = %GuestBar
@onready var _reasons: GridContainer = %ReasonRows
@onready var _reviews: VBoxContainer = %ReviewRows


func _ready() -> void:
	%NextDay.pressed.connect(_on_next_day_pressed)
	show_report(DayReport.new())


## Replaces every section with the supplied day's results, including empty states.
func show_report(report: DayReport) -> void:
	_header.text = "Day %d: Closed" % report.day
	_profit.text = "%s profit" % _money(report.profit())
	_profit.add_theme_color_override("font_color", PROFIT_GREEN if report.profit() >= 0 else LOSS_RED)
	_fill_money(_income, report.income, "No income today")
	_fill_money(_costs, report.costs, "No costs today")
	_clear(_dishes)
	var best: StringName = report.best_dish()
	for id: String in _sorted_ids(report.dishes_sold):
		var title: String = id.capitalize()
		if StringName(id) == best:
			title += " (best seller)"
		_add_row(_dishes, title, str(report.dishes_sold[StringName(id)]))
	if report.dishes_sold.is_empty():
		_add_row(_dishes, "No dishes sold today", "")
	_guests.text = "%d served  /  %d lost" % [report.customers_served, report.customers_lost]
	var guest_total: int = report.customers_served + report.customers_lost
	_guest_bar.max_value = maxi(guest_total, 1)
	_guest_bar.value = report.customers_served
	_guest_bar.tooltip_text = "Guests served out of all guests"
	if guest_total == 0:
		_guests.text = "No guests visited today"
	_fill_reasons(report.leave_reasons)
	_clear(_reviews)
	for index: int in range(mini(report.reviews.size(), 3)):
		_add_label(_reviews, '“%s”' % report.reviews[index])
	if report.reviews.is_empty():
		_add_label(_reviews, "No reviews yet — tomorrow is a fresh start")
	show()


func _fill_money(rows: GridContainer, amounts: Dictionary, empty_text: String) -> void:
	_clear(rows)
	for id: String in _sorted_ids(amounts):
		_add_row(rows, id.capitalize(), _money(int(amounts[StringName(id)])))
	if amounts.is_empty():
		_add_row(rows, empty_text, "")


func _fill_reasons(reasons: Dictionary) -> void:
	_clear(_reasons)
	var ids: Array[String] = _sorted_ids(reasons)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var a_count: int = int(reasons[StringName(a)])
		var b_count: int = int(reasons[StringName(b)])
		return a_count > b_count if a_count != b_count else a < b
	)
	for id: String in ids:
		var title: String = str(LEAVE_LABELS.get(StringName(id), id.capitalize()))
		_add_row(_reasons, title, str(reasons[StringName(id)]))
	if reasons.is_empty():
		_add_row(_reasons, "No unhappy departures today", "")


func _sorted_ids(values: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in values:
		ids.append(str(key))
	ids.sort()
	return ids


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.free()


func _add_row(parent: GridContainer, title: String, amount: String) -> void:
	_add_label(parent, title)
	var value: Label = _add_label(parent, amount)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _add_label(parent: Node, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _money(amount: int) -> String:
	var digits: String = str(amount).trim_prefix("-")
	var grouped: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += ","
		grouped += digits[index]
	return ("-$" if amount < 0 else "$") + grouped


func _on_next_day_pressed() -> void:
	next_day_pressed.emit()
