extends Control
## Standalone closing report. Integration supplies data and handles Next day.

signal next_day_pressed

const LOAN_INTRODUCTION: String = "The bank covered your shortfall. It'll take a share of your profits until it's paid back."
const MONEY_LABELS: Dictionary = {
	Ledger.BANK_LOAN: "Bank loan",
	Ledger.LOAN_INTEREST: "Loan interest",
	Ledger.LOAN_REPAYMENT: "Loan repayment",
	Ledger.MILESTONE_BONUS: "Milestone bonus",
}

const LEAVE_LABELS: Dictionary = {
	&"out_of_stock": "Dish was out of stock",
	&"kitchen_failed": "The kitchen couldn't make the dish",
	&"no_menu": "Nothing on the menu",
	&"closing": "Shop closed",
	&"waited_too_long": "Waited too long",
	&"too_expensive": "Too expensive",
	&"no_table": "No table available",
	&"no_clean_plates": "No clean plates",
}
const PROFIT_GREEN: Color = Color("38764b")
const LOSS_RED: Color = Color("a83e35")

var _header: Label
var _profit: Label
var _income: GridContainer
var _costs: GridContainer
var _loan_notice: Label
var _dishes: GridContainer
var _guests: Label
var _cleanliness: Label
var _guest_bar: ProgressBar
var _reasons: GridContainer
var _review_stats: Label
var _reputation: Label
var _reviews: VBoxContainer
var _owner_level: Label
var _owner_callout: HBoxContainer
var _owner_level_up: Label
var _owner_xp_rows: GridContainer
var _owner_unlocks: Label
var _milestone_heading: Label
var _milestone_rows: VBoxContainer
var _nodes_bound: bool = false
var _report_shown: bool = false
var vibe_summary: Label
var _vibe_text: String = ""


func _ready() -> void:
	_bind_nodes()
	if not _report_shown:
		show_report(DayReport.new())


## Replaces every section with the supplied day's results, including empty states.
func show_report(report: DayReport) -> void:
	_bind_nodes()
	_report_shown = true
	_header.text = "Day %d: Closed" % report.day
	var operating_profit: int = report.operating_profit()
	_profit.text = "%s operating profit" % _money(operating_profit)
	_profit.add_theme_color_override("font_color", PROFIT_GREEN if operating_profit >= 0 else LOSS_RED)
	_fill_money(_income, report.income, "No income today")
	_fill_money(_costs, report.costs, "No costs today")
	_loan_notice.text = LOAN_INTRODUCTION if report.loan_first_advance else ""
	_loan_notice.visible = report.loan_first_advance
	_fill_milestones(report.milestones_reached)
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
	_cleanliness.text = "Cleanliness: %s" % report.cleanliness_label \
		if not report.cleanliness_label.is_empty() else ""
	_cleanliness.visible = not report.cleanliness_label.is_empty()
	_fill_reasons(report.leave_reasons)
	if report.review_cards.is_empty():
		_review_stats.text = "Today's reviews: none"
	else:
		_review_stats.text = "Today's reviews: %.1f stars" % report.today_review_average
	_reputation.text = "Reputation: %.1f to %.1f stars" % [report.reputation_before, report.reputation_after]
	_clear(_reviews)
	if not report.review_cards.is_empty():
		for index: int in range(mini(report.review_cards.size(), 3)):
			var card: Dictionary = report.review_cards[index]
			_add_label(_reviews, '%d stars - "%s"' % [int(card.get("stars", 1)), str(card.get("quote", ""))])
	elif not report.reviews.is_empty():
		# Older saved reports have quotes but no rating metadata.
		for index: int in range(mini(report.reviews.size(), 3)):
			_add_label(_reviews, '"%s"' % report.reviews[index])
	else:
		_add_label(_reviews, "No reviews today")
	_fill_owner_progress(report)
	_render_vibe()
	show()


## Current room presentation is derived, never part of the saved day report.
## The optional label comes from paid guests' captured arrival effects, not
## a rating or an endorsement of the visit as a whole.
func set_vibe(result: VibeModel.Result, experienced_theme_label: String = "") -> void:
	_bind_nodes()
	_vibe_text = ""
	if not experienced_theme_label.is_empty():
		_vibe_text = "Guests noticed the %s vibe." % experienced_theme_label.to_lower()
	elif result != null and result.valid and is_finite(result.score) and roundi(result.score) > 0:
		var theme_name: String = result.theme_label if not result.active_theme.is_empty() else "No active theme"
		_vibe_text = "Vibe: %s, %d / 100." % [theme_name, roundi(result.score)]
	_render_vibe()


func _render_vibe() -> void:
	vibe_summary.text = _vibe_text
	vibe_summary.visible = not _vibe_text.is_empty()


func _bind_nodes() -> void:
	if _nodes_bound:
		return
	_header = %Header
	_profit = %Profit
	_income = %IncomeRows
	_costs = %CostRows
	_loan_notice = %LoanNotice
	_dishes = %DishRows
	_guests = %Guests
	_cleanliness = %Cleanliness
	_guest_bar = %GuestBar
	_reasons = %ReasonRows
	_review_stats = %ReviewStats
	_reputation = %Reputation
	_reviews = %ReviewRows
	_owner_level = %OwnerLevel
	_owner_callout = get_node("Panel/Scroll/Content/LevelUpCallout") as HBoxContainer
	_owner_level_up = %OwnerLevelUp
	_owner_xp_rows = %OwnerXPRows
	_owner_unlocks = %OwnerUnlocks
	_milestone_heading = %MilestoneHeading
	_milestone_rows = %MilestoneRows
	var content: VBoxContainer = get_node("Panel/Scroll/Content") as VBoxContainer
	vibe_summary = Label.new()
	vibe_summary.name = "VibeSummary"
	vibe_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vibe_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vibe_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(vibe_summary)
	content.move_child(vibe_summary, (content.get_node("ReviewHeading") as Control).get_index())
	var next_day: Button = %NextDay
	IconStyle.decorate_label(_header, &"report")
	for path: String in ["ReviewHeading", "GuestHeading", "ReasonHeading", "OwnerHeading"]:
		IconStyle.decorate_label(get_node("Panel/Scroll/Content/" + path) as Label,
			&"reputation" if path == "ReviewHeading" else (&"staff" if path == "GuestHeading" else &"report"))
	IconStyle.configure_button(next_day, &"next_day", "Next day", "Begin the next morning", IconCatalogue.PANEL_SIZE)
	next_day.pressed.connect(_on_next_day_pressed)
	_nodes_bound = true


func _fill_owner_progress(report: DayReport) -> void:
	_owner_level.text = "Owner level %d" % report.owner_level_after
	_owner_level_up.visible = report.owner_level_after > report.owner_level_before
	if _owner_level_up.visible:
		_owner_level_up.text = "Level up! Level %d reached" % report.owner_level_after
	_clear(_owner_xp_rows)
	if report.owner_xp_breakdown.is_empty():
		_add_row(_owner_xp_rows, "No owner XP recorded", "")
	else:
		_add_row(_owner_xp_rows, "Happy guests", "+%d XP" % int(report.owner_xp_breakdown.get("happy_xp", 0)))
		_add_row(_owner_xp_rows, "Profit", "+%d XP" % int(report.owner_xp_breakdown.get("profit_xp", 0)))
		_add_row(_owner_xp_rows, "Five-star reviews", "+%d XP" % int(report.owner_xp_breakdown.get("review_xp", 0)))
		var milestone_xp: int = maxi(0, int(report.owner_xp_breakdown.get("milestone_xp", 0)))
		if milestone_xp > 0:
			_add_row(_owner_xp_rows, "Career goals", "+%d XP" % milestone_xp)
		_add_row(_owner_xp_rows, "Total", "+%d XP" % int(report.owner_xp_breakdown.get("total_xp", 0)))
	_owner_unlocks.visible = not report.owner_unlocks.is_empty()
	if _owner_unlocks.visible:
		var names: String = ""
		for name: String in report.owner_unlocks:
			if not names.is_empty():
				names += ", "
			names += name
		_owner_unlocks.text = "Unlocked: %s" % names
	else:
		_owner_unlocks.text = ""
	_owner_callout.visible = _owner_level_up.visible or _owner_unlocks.visible


func _fill_milestones(milestones: Array[Dictionary]) -> void:
	_clear(_milestone_rows)
	var shown: int = 0
	for milestone: Dictionary in milestones:
		var title: String = str(milestone.get("title", "")).strip_edges()
		if title.is_empty():
			continue
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Milestone%d" % shown
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label: Label = _add_label(row, title)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var reward_xp: int = maxi(0, int(milestone.get("reward_xp", 0)))
		var reward_cash: int = maxi(0, int(milestone.get("reward_cash", 0)))
		var reward_label: Label = _add_label(row, "Reward: +%d XP, %s" % [reward_xp, _money(reward_cash)])
		reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_milestone_rows.add_child(row)
		shown += 1
	_milestone_heading.visible = shown > 0
	_milestone_rows.visible = shown > 0


func _fill_money(rows: GridContainer, amounts: Dictionary, empty_text: String) -> void:
	_clear(rows)
	for id: String in _sorted_ids(amounts):
		_add_row(rows, String(MONEY_LABELS.get(StringName(id), id.capitalize())), _money(int(amounts[StringName(id)])))
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
