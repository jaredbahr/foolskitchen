extends "res://src/world/main.gd"
## Pays for one spare Pastry with the ordinary Stock cart, then runs three real
## service days until it naturally expires. This disclosed player-action fixture
## is not a default balance trajectory. No cash, stock, reviews or random state
## are injected; saves are disabled. The standard --report validator still
## checks the real review cards. PROFIT_REVIEW_SMALL=1 is a manual 1280x720 /150%
## capture: frames 12,60 show the finances, then the native Next day button.

const REVIEW_DAYS: int = 3
const SPARE_INGREDIENT: StringName = &"pastry"

var _review_frames: int = 0
var _review_tick: int = 0
var _review_ready: bool = false
var _review_small: bool = false
var _review_reports: Array[Dictionary] = []
var _review_purchase: Dictionary = {}
var _review_output: String = ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_review_output = argument.trim_prefix("--out=")
			if not _review_output.is_absolute_path():
				_review_output = ProjectSettings.globalize_path("res://" + _review_output)
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	($CameraRig as CameraRig).edge_pan_enabled = false
	var ingredient: IngredientDef = content.ingredient(SPARE_INGREDIENT)
	var cash_before: int = Economy.cash
	var entries_before: int = Economy.ledger.entries_for_day(Clock.sim.day).size()
	if ingredient == null or Economy.stock.count(SPARE_INGREDIENT) != 0 \
			or not stock_cart_set(SPARE_INGREDIENT, 1) or not stock_place_order() \
			or Economy.cash != cash_before - ingredient.unit_cost \
			or Economy.stock.count(SPARE_INGREDIENT) != 1:
		push_error("Profit review could not pay for one spare Pastry through the real Stock cart")
		return
	_review_purchase = {"ingredient": String(SPARE_INGREDIENT), "units": 1,
		"unit_cost": ingredient.unit_cost, "cash_before": cash_before, "cash_after": Economy.cash,
		"bought_day": Clock.sim.day, "expected_expiry_day": Clock.sim.day + ingredient.shelf_life_days,
		"ledger_entries": Economy.ledger.entries_for_day(Clock.sim.day).slice(entries_before),
		"batches": Economy.stock.to_dict()["batches"][String(SPARE_INGREDIENT)]}
	for index: int in REVIEW_DAYS:
		if not Clock.sim.start_service():
			push_error("Profit review could not open the ordinary shop")
			return
		run_ticks(Clock.sim.open_ticks + Clock.sim.last_orders_max_ticks + 1)
		if Clock.sim.phase != SimClock.Phase.CLOSED or shown_report == null \
				or shown_report.customers_served <= 0 or not shown_report.operating_profit_recorded():
			push_error("Profit review did not reach a valued, paid closing report")
			return
		_review_reports.append(shown_report.to_dict())
		if index < REVIEW_DAYS - 1:
			if Economy.stock.count(SPARE_INGREDIENT) != 1:
				push_error("Profit review's spare Pastry did not remain unused until expiry")
				return
			(_report.get_node("%NextDay") as Button).pressed.emit()
	if int(_expired_this_morning.get(SPARE_INGREDIENT, 0)) != 1 \
			or Economy.stock.count(SPARE_INGREDIENT) != 0 \
			or not shown_report.spoiled_stock_recorded or shown_report.spoiled_stock < ingredient.unit_cost:
		push_error("Profit review did not observe the paid spare Pastry's natural morning expiry")
		return
	_review_tick = world.now
	_review_small = OS.get_environment("PROFIT_REVIEW_SMALL") == "1"
	if _review_small:
		get_window().size = Vector2i(1280, 720)
		if not Preferences.set_ui_scale_percent(150):
			push_error("Profit review could not select the ordinary 150% UI size")
			return
	_review_ready = true


func _process(_delta: float) -> void:
	if not _review_ready:
		return
	_review_frames += 1
	if _review_small and _review_frames == 30:
		var next_day: Button = _report.get_node("%NextDay") as Button
		next_day.grab_focus()
		(_report.get_node("Panel/Scroll") as ScrollContainer).ensure_control_visible(next_day)
	if _review_frames in [10, 50]:
		_record_native_report()


func _record_native_report() -> void:
	await RenderingServer.frame_post_draw
	var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
	var viewport: Rect2 = scroll.get_global_rect()
	var rows: Array[Dictionary] = []
	var valid: bool = world.now == _review_tick and Clock.sim.phase == SimClock.Phase.CLOSED \
		and not use_saves and shown_report.day == REVIEW_DAYS \
		and shown_report.operating_profit_recorded() and shown_report.stock_bought_recorded \
		and shown_report.spoiled_stock_recorded and shown_report.stock_on_hand_recorded
	var expected: Dictionary = {
		"Cost of food served": Fmt.money(shown_report.food_cost),
		"Stock bought today": Fmt.money(shown_report.stock_bought),
		"Spoiled stock": Fmt.money(shown_report.spoiled_stock),
		"Stock on hand worth": Fmt.money(shown_report.stock_on_hand),
	}
	for path: String in ["%IncomeRows", "%CostRows", "%StockRows"]:
		var grid: GridContainer = _report.get_node(path) as GridContainer
		for index: int in range(0, grid.get_child_count(), 2):
			var title: Label = grid.get_child(index) as Label
			var amount: Label = grid.get_child(index + 1) as Label
			var bounds: Rect2 = title.get_global_rect().merge(amount.get_global_rect())
			valid = valid and bounds.position.x >= viewport.position.x - 1.0 \
				and bounds.end.x <= viewport.end.x + 1.0
			if expected.has(title.text):
				valid = valid and amount.text == expected[title.text]
				expected.erase(title.text)
				if not _review_small:
					valid = valid and viewport.grow(1.0).encloses(bounds)
			rows.append({"title": title.text, "amount": amount.text,
				"inside_scroll": viewport.grow(1.0).encloses(bounds)})
	var cash_change: Label = _report.get_node("%CashChange") as Label
	var next_day: Button = _report.get_node("%NextDay") as Button
	var cash_visible: bool = viewport.grow(1.0).encloses(cash_change.get_global_rect())
	var next_visible: bool = viewport.grow(1.0).encloses(next_day.get_global_rect())
	valid = valid and expected.is_empty() \
		and cash_change.text == "Cash change today: %s" % Fmt.money(shown_report.profit()) \
		and (_report.get_node("%Profit") as Label).text == "%s operating profit" % Fmt.money(shown_report.operating_profit()) \
		and (cash_visible if not _review_small else (next_visible if _review_frames >= 30 else true))
	var evidence: Dictionary = {"real_service": true, "seed": 1,
		"fixture": "Paid one spare Pastry through Stock on day 1; ordinary service through day 3; not the default balance run",
		"paid_purchase": _review_purchase, "expired_this_morning": _expired_this_morning,
		"days": _review_reports, "world_tick": _review_tick, "use_saves": use_saves,
		"native_rows": rows, "cash_change": cash_change.text, "cash_inside_scroll": cash_visible,
		"next_day_inside_scroll": next_visible, "scroll_vertical": scroll.scroll_vertical,
		"ui_scale_percent": Preferences.ui_scale_percent,
		"window_size": [get_window().size.x, get_window().size.y], "valid": valid,
		"native_frame": _review_frames, "capture_timing": "frame_post_draw"}
	print("PROFIT_REVIEW ", JSON.stringify(evidence))
	if not _review_output.is_empty():
		var file: FileAccess = FileAccess.open(_review_output.path_join("profit-review.json"), FileAccess.WRITE)
		if file == null:
			push_error("Profit review could not write its actual paid-fixture evidence")
			return
		file.store_string(JSON.stringify(evidence, "\t") + "\n")
		file.close()
	if not valid:
		push_error("Profit review failed its real closing state or native report bounds")
