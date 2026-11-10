extends Control
## Standalone closing report. Integration supplies data and handles Next day.

signal next_day_pressed

const LOAN_INTRODUCTION: String = "The bank covered your shortfall. It'll take a share of your profits until it's paid back."
const MONEY_LABELS: Dictionary = {
	Ledger.BREAKAGES: "Breakages",
	Ledger.CAT_FOOD: "Cat food",
	Ledger.BANK_LOAN: "Bank loan",
	Ledger.LOAN_INTEREST: "Loan interest",
	Ledger.LOAN_REPAYMENT: "Loan repayment",
	Ledger.MILESTONE_BONUS: "Milestone bonus",
	Ledger.WEEKLY_CHALLENGE_BONUS: "Weekly challenge",
	Ledger.BOOKING_DEPOSIT: "Booking deposit",
	Ledger.BOOKING_REFUND: "Booking refund",
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
	&"no_way_through": "Couldn't get through",
}
const PROFIT_GREEN: Color = Color("38764b")
const LOSS_RED: Color = Color("a83e35")
const STAFF_ADVICE_RULES: StaffAdviceTuning = preload("res://data/balance/staff_advice.tres")

var _restaurant_name: Label
var _header: Label
var _profit: Label
var _income: GridContainer
var _costs: GridContainer
var _stock: GridContainer
var _stock_summary: VBoxContainer
var _cash_change: Label
var _loan_notice: Label
var _dishes: GridContainer
var _slowest_seller: Label
var _daily_special: Label
var _guests: Label
var _cleanliness: Label
var _guest_bar: ProgressBar
var _reasons: GridContainer
var _low_stock: VBoxContainer
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
var regulars_summary: Label
## The disguised food critic's visit (#303), shown only on days one reviewed:
## a heading, then the verdict and the headline quote.
var critic_heading: Label
var critic_summary: Label
var vibe_summary: Label
var _vibe_text: String = ""
var _demand_section: VBoxContainer
var _demand_summary: Label
var _demand_factors: Label
var _demand_explanation: Label
var _trend_days: int = 7
var _trend_rows: Array[Dictionary] = []
var _trend_today: int = 0
var _trend_buttons: Array[Button] = []


func _ready() -> void:
	_bind_nodes()
	_on_report_resized()
	if not _report_shown:
		show_report(DayReport.new())


## Replaces every section with the supplied day's results, including empty states.
func show_report(report: DayReport) -> void:
	_bind_nodes()
	# Main follows this compatible single-report API with the detached history.
	show_history([], report.day)
	_report_shown = true
	_restaurant_name.text = report.restaurant_name
	var viral: Label = %ViralReviewLine
	viral.text = report.viral_line
	viral.visible = not report.viral_line.is_empty()
	(get_node("Panel/Scroll/Content/ReviewHeading") as Label).text = "Reviews of %s" % report.restaurant_name
	_header.text = "Day %d: Closed" % report.day
	if report.operating_profit_recorded():
		var operating_profit: int = report.operating_profit()
		_profit.text = "%s operating profit" % _money(operating_profit)
		_profit.add_theme_color_override("font_color", PROFIT_GREEN if operating_profit >= 0 else LOSS_RED)
	else:
		_profit.text = "Operating profit not recorded"
		_profit.remove_theme_color_override("font_color")
	_fill_money(_income, report.income, "No income today")
	var displayed_costs: Dictionary = report.costs.duplicate()
	if report.stock_values_recorded:
		displayed_costs.erase(Ledger.INGREDIENTS)
	_fill_money(_costs, displayed_costs, "No costs today" if not report.stock_values_recorded else "")
	if report.stock_values_recorded:
		_add_row(_costs, "Cost of food served", _recorded_money(report.food_cost, report.food_cost_recorded))
	_clear(_stock)
	_add_row(_stock, "Stock bought today", _recorded_money(report.stock_bought,
		report.stock_values_recorded and report.stock_bought_recorded) + (
		" (haggle saved %s)" % _money(report.haggle_saved) if report.haggle_percent > 0 else ""))
	_add_row(_stock, "Spoiled stock", _recorded_money(report.spoiled_stock, report.spoiled_stock_recorded))
	_add_row(_stock, "Stock on hand worth", _recorded_money(report.stock_on_hand, report.stock_on_hand_recorded))
	_cash_change.text = "Cash change today: %s" % _money(report.profit())
	_loan_notice.text = LOAN_INTRODUCTION if report.loan_first_advance else ""
	_loan_notice.visible = report.loan_first_advance
	_fill_milestones(DayReport.public_milestones(report.milestones_reached))
	var weekly_line: Label = %WeeklyChallengeLine
	weekly_line.text = report.weekly_challenge_line
	weekly_line.visible = not report.weekly_challenge_line.is_empty()
	_clear(_dishes)
	var best: StringName = report.best_dish()
	for id: String in _sorted_ids(report.dishes_sold):
		var title: String = id.capitalize()
		if StringName(id) == best:
			title += " (best seller)"
		_add_row(_dishes, title, str(report.dishes_sold[StringName(id)]))
	if report.dishes_sold.is_empty():
		_add_row(_dishes, "No dishes sold today", "")
	_slowest_seller.text = _slowest_seller_text(report)
	_slowest_seller.visible = not _slowest_seller.text.is_empty()
	_daily_special.text = report.daily_special_line
	_daily_special.visible = not _daily_special.text.is_empty()
	_guests.text = "%d served  /  %d lost" % [report.customers_served, report.customers_lost]
	var guest_total: int = report.customers_served + report.customers_lost
	_guest_bar.max_value = maxi(guest_total, 1)
	_guest_bar.value = report.customers_served
	_guest_bar.tooltip_text = "Guests served out of all guests"
	if guest_total == 0:
		_guests.text = "No guests visited today"
	_show_takeaways(report.takeaways)
	(get_node("%FoodQuality") as Label).text = report.food_quality_text()
	_cleanliness.text = "Cleanliness: %s" % report.cleanliness_label \
		if not report.cleanliness_label.is_empty() else ""
	_cleanliness.visible = not report.cleanliness_label.is_empty()
	var mishaps: Label = get_node_or_null("Panel/Scroll/Content/Mishaps") as Label
	if mishaps == null:
		mishaps = Label.new()
		mishaps.name = "Mishaps"
		mishaps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cleanliness.get_parent().add_child(mishaps)
		_cleanliness.get_parent().move_child(mishaps, _cleanliness.get_index() + 1)
	mishaps.text = report.mishaps_text
	mishaps.visible = not report.mishaps_text.is_empty()
	var inspection: Label = get_node_or_null("Panel/Scroll/Content/Inspection") as Label
	if inspection == null:
		inspection = Label.new()
		inspection.name = "Inspection"
		inspection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mishaps.get_parent().add_child(inspection)
		mishaps.get_parent().move_child(inspection, mishaps.get_index() + 1)
	inspection.text = "\n".join(PackedStringArray(report.inspection_lines))
	inspection.visible = not report.inspection_lines.is_empty()
	var bookings: Label = get_node_or_null("Panel/Scroll/Content/Bookings") as Label
	if bookings == null and not report.booking_lines.is_empty():
		bookings = Label.new()
		bookings.name = "Bookings"
		bookings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspection.get_parent().add_child(bookings)
		inspection.get_parent().move_child(bookings, inspection.get_index() + 1)
	if bookings != null:
		bookings.text = "\n".join(PackedStringArray(report.booking_lines))
		bookings.visible = not report.booking_lines.is_empty()
	var rush_hour: Label = get_node_or_null("Panel/Scroll/Content/RushHour") as Label
	if rush_hour == null:
		rush_hour = Label.new()
		rush_hour.name = "RushHour"
		rush_hour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspection.get_parent().add_child(rush_hour)
	inspection.get_parent().move_child(rush_hour, inspection.get_index() + 1)
	rush_hour.text = "\n".join(PackedStringArray(report.rush_hour_lines))
	rush_hour.visible = not report.rush_hour_lines.is_empty()
	if bookings != null:
		inspection.get_parent().move_child(bookings, rush_hour.get_index() + 1)
	regulars_summary.text = "Regulars: " + "; ".join(PackedStringArray(report.regulars_lines))
	regulars_summary.visible = not report.regulars_lines.is_empty()
	critic_heading.text = report.critic_lines[0] if not report.critic_lines.is_empty() else ""
	critic_heading.visible = not report.critic_lines.is_empty()
	critic_summary.text = "\n".join(PackedStringArray(report.critic_lines.slice(1)))
	critic_summary.visible = report.critic_lines.size() > 1
	_fill_reasons(report.leave_reasons)
	_render_team(report.staff_activity, report.leave_reasons)
	_clear(_low_stock)
	for line: String in report.low_stock:
		_add_label(_low_stock, line)
	if report.low_stock.is_empty():
		_add_label(_low_stock, "Nothing ran out, and the fridge is ready for tomorrow")
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
	_render_demand(report.demand_forecast)
	_render_vibe()
	show()


func show_history(rows: Array[Dictionary], today: int) -> void:
	_bind_nodes()
	_trend_rows = BusinessTrendText.display_rows(rows, today)
	_trend_today = today
	_refresh_history()


func _refresh_history() -> void:
	(%BusinessTrendHeading as Label).text = BusinessTrendText.HEADING
	(%BusinessTrendSummary as Label).text = BusinessTrendText.summary(_trend_rows, _trend_today)
	var chart: BusinessTrendChart = %BusinessTrendChart
	chart.set_history(_trend_rows, _trend_today if not _trend_rows.is_empty() else 0, _trend_days)
	chart.visible = not _trend_rows.is_empty()
	for button: Button in _trend_buttons:
		button.set_pressed_no_signal(int(button.get_meta("days")) == _trend_days)
	(%BusinessTrendSection as VBoxContainer).show()


func _on_trend_range_pressed(days: int) -> void:
	_trend_days = days
	_refresh_history()


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


## "Takeaways: N" under the guest bar, only on days the order counter sold any.
func _show_takeaways(count: int) -> void:
	var label: Label = get_node_or_null("Panel/Scroll/Content/Takeaways") as Label
	if label == null:
		label = Label.new()
		label.name = "Takeaways"
		_guest_bar.get_parent().add_child(label)
		_guest_bar.get_parent().move_child(label, _guest_bar.get_index() + 1)
	label.text = "Takeaways: %d" % count
	label.visible = count > 0


func _render_vibe() -> void:
	vibe_summary.text = _vibe_text
	vibe_summary.visible = not _vibe_text.is_empty()


func _render_demand(forecast: Dictionary) -> void:
	_demand_summary.text = DemandText.forecast_summary(forecast)
	_demand_factors.text = "\n".join(DemandText.factor_lines(forecast))
	_demand_explanation.text = DemandText.forecast_note(forecast)
	_demand_section.visible = not _demand_summary.text.is_empty()


func _render_team(summary: Dictionary, leave_reasons: Dictionary) -> void:
	var clean: Dictionary = StaffActivity.public_snapshot(summary)
	var rows: VBoxContainer = %TeamActivityRows
	for index: int in range(StaffAdviceText.ROLES.size()):
		var label: Label = rows.get_node(NodePath(String(StaffAdviceText.ROLE_NODES[index]))) as Label
		label.text = StaffAdviceText.role_line(StaffAdviceText.ROLES[index], clean)
		label.visible = not label.text.is_empty()
	var advice: Label = %TeamAdvice
	advice.text = StaffAdviceText.recommendation(STAFF_ADVICE_RULES.recommendation(clean, leave_reasons))
	advice.visible = not advice.text.is_empty()
	(%TeamSection as VBoxContainer).visible = not clean.is_empty()


func _bind_nodes() -> void:
	if _nodes_bound:
		return
	_restaurant_name = %RestaurantName
	_header = %Header
	_profit = %Profit
	_income = %IncomeRows
	_costs = %CostRows
	_stock = %StockRows
	_stock_summary = %StockSummary
	_cash_change = %CashChange
	_loan_notice = %LoanNotice
	_dishes = %DishRows
	_slowest_seller = %SlowestSeller
	_daily_special = Label.new()
	_daily_special.name = "DailySpecial"
	_daily_special.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_special.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_daily_special.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_daily_special.hide()
	var special_content: VBoxContainer = get_node("Panel/Scroll/Content") as VBoxContainer
	special_content.add_child(_daily_special)
	special_content.move_child(_daily_special, _slowest_seller.get_index() + 1)
	_guests = %Guests
	_cleanliness = %Cleanliness
	_guest_bar = %GuestBar
	_reasons = %ReasonRows
	_low_stock = %LowStockRows
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
	(%TeamHeading as Label).text = StaffAdviceText.TEAM_HEADING
	IconStyle.decorate_label(%TeamHeading as Label, &"staff")
	var content: VBoxContainer = get_node("Panel/Scroll/Content") as VBoxContainer
	regulars_summary = Label.new()
	regulars_summary.name = "RegularsSummary"
	regulars_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	regulars_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	regulars_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(regulars_summary)
	content.move_child(regulars_summary, _cleanliness.get_index() + 1)
	vibe_summary = Label.new()
	vibe_summary.name = "VibeSummary"
	vibe_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vibe_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vibe_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(vibe_summary)
	content.move_child(vibe_summary, (content.get_node("ReviewHeading") as Control).get_index())
	_demand_section = VBoxContainer.new()
	_demand_section.name = "DemandForecast"
	_demand_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_demand_section)
	content.move_child(_demand_section, _reviews.get_index() + 1)
	critic_heading = Label.new()
	critic_heading.name = "CriticHeading"
	critic_heading.add_theme_font_size_override("font_size", 22)
	critic_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(critic_heading)
	content.move_child(critic_heading, _reviews.get_index() + 1)
	critic_summary = Label.new()
	critic_summary.name = "CriticSummary"
	critic_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	critic_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	critic_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(critic_summary)
	content.move_child(critic_summary, critic_heading.get_index() + 1)
	var demand_heading: Label = _add_label(_demand_section, DemandText.FORECAST_HEADING)
	demand_heading.name = "Heading"
	demand_heading.add_theme_font_size_override("font_size", 22)
	IconStyle.decorate_label(demand_heading, &"report")
	_demand_summary = _add_label(_demand_section, "")
	_demand_summary.name = "Summary"
	_demand_factors = _add_label(_demand_section, "")
	_demand_factors.name = "Factors"
	_demand_explanation = _add_label(_demand_section, "")
	_demand_explanation.name = "Explanation"
	_demand_section.hide()
	var next_day: Button = %NextDay
	var ranges: HBoxContainer = HBoxContainer.new()
	ranges.name = "BusinessTrendRanges"
	var trend_section: VBoxContainer = %BusinessTrendSection
	trend_section.add_child(ranges)
	trend_section.move_child(ranges, (%BusinessTrendChart as Control).get_index())
	var group: ButtonGroup = ButtonGroup.new()
	for days: int in [7, 30]:
		var button: Button = Button.new()
		button.name = "Days%d" % days
		button.text = BusinessTrendText.SHORT_RANGE if days == 7 else BusinessTrendText.LONG_RANGE
		button.toggle_mode = true
		button.button_group = group
		button.set_meta("days", days)
		button.pressed.connect(_on_trend_range_pressed.bind(days))
		ranges.add_child(button)
		_trend_buttons.append(button)
	IconStyle.decorate_label(_header, &"report")
	for path: String in ["ReviewHeading", "GuestHeading", "ReasonHeading", "LowStockHeading", "OwnerHeading"]:
		IconStyle.decorate_label(get_node("Panel/Scroll/Content/" + path) as Label,
			&"reputation" if path == "ReviewHeading" else (&"staff" if path == "GuestHeading"
				else (&"stock" if path == "LowStockHeading" else &"report")))
	IconStyle.configure_button(next_day, &"next_day", "Next day", "Begin the next morning", IconCatalogue.PANEL_SIZE)
	next_day.pressed.connect(_on_next_day_pressed)
	_nodes_bound = true
	resized.connect(_on_report_resized)
	_on_report_resized()


## One player-facing helper owns the slow-seller line and both hint branches.
func _slowest_seller_text(report: DayReport) -> String:
	var dish: Dictionary = report.slowest_dish_details()
	if dish.is_empty():
		return ""
	var hint: String = "Try a lower price" if int(dish["price"]) > int(dish["standard_price"]) \
		else "Guests may not fancy it; try another dish"
	return "Slowest seller: %s (%d sold). %s or take it off the menu." % [
		str(dish["display_name"]), int(dish["sold"]), hint]


## Normal windows keep the stock detail beside the books, leaving the real
## review cards in view. Large UI sizes give those rows the full scroll width.
func _on_report_resized() -> void:
	if not is_inside_tree():
		return
	var finances: HBoxContainer = get_node("Panel/Scroll/Content/Finances") as HBoxContainer
	var content: VBoxContainer = get_node("Panel/Scroll/Content") as VBoxContainer
	var target: Node = finances if size.x >= 1100.0 else content
	if _stock_summary.get_parent() != target:
		_stock_summary.reparent(target, false)
	if target == content:
		content.move_child(_stock_summary, finances.get_index() + 1)


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
		var milestone_xp: int = DayReport.milestone_xp(report.owner_xp_breakdown.get("milestone_xp", -1))
		if milestone_xp > 0:
			_add_row(_owner_xp_rows, "Career goals", "+%d XP" % milestone_xp)
		_add_row(_owner_xp_rows, "Total", "+%d XP" % int(report.owner_xp_breakdown.get("total_xp", 0)))
	_owner_unlocks.visible = not report.owner_unlocks.is_empty() or not report.owner_tips.is_empty()
	var lines: PackedStringArray = []
	if not report.owner_unlocks.is_empty():
		lines.append("Unlocked: %s" % ", ".join(PackedStringArray(report.owner_unlocks)))
	lines.append_array(PackedStringArray(report.owner_tips))
	_owner_unlocks.text = "\n".join(lines)
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
		var title: String = String(MONEY_LABELS.get(StringName(id), id.capitalize()))
		if rows == _costs and StringName(id) == Ledger.BOOKING_DEPOSIT:
			title = "Deposit taken off the bill"
		_add_row(rows, title, _money(int(amounts[StringName(id)])))
	if amounts.is_empty() and not empty_text.is_empty():
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
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	var font: Font = value.get_theme_font("font")
	value.custom_minimum_size.x = minf(180.0,
		font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, value.get_theme_font_size("font_size")).x)


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


func _recorded_money(amount: int, recorded: bool) -> String:
	return _money(amount) if recorded else "Not recorded"


func _on_next_day_pressed() -> void:
	next_day_pressed.emit()
