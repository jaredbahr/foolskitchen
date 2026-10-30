extends "res://src/world/main.gd"
## Three ordinary paid service days, with saves disabled. No cash, ingredients,
## reviews or random state are injected. The standard --report validator still
## checks the real review cards. PROFIT_REVIEW_SMALL=1 is a manual 1280x720 /150%
## capture: frames 12,60 show the finances, then the native Next day button.

const REVIEW_DAYS: int = 3

var _review_frames: int = 0
var _review_tick: int = 0
var _review_ready: bool = false
var _review_small: bool = false
var _review_reports: Array[Dictionary] = []


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	($CameraRig as CameraRig).edge_pan_enabled = false
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
			(_report.get_node("%NextDay") as Button).pressed.emit()
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
		and not use_saves and shown_report.day == REVIEW_DAYS
	for path: String in ["%IncomeRows", "%CostRows", "%StockRows"]:
		var grid: GridContainer = _report.get_node(path) as GridContainer
		for index: int in range(0, grid.get_child_count(), 2):
			var title: Label = grid.get_child(index) as Label
			var amount: Label = grid.get_child(index + 1) as Label
			var bounds: Rect2 = title.get_global_rect().merge(amount.get_global_rect())
			valid = valid and bounds.position.x >= viewport.position.x - 1.0 \
				and bounds.end.x <= viewport.end.x + 1.0
			rows.append({"title": title.text, "amount": amount.text,
				"inside_scroll": viewport.grow(1.0).encloses(bounds)})
	var cash_change: Label = _report.get_node("%CashChange") as Label
	var next_day: Button = _report.get_node("%NextDay") as Button
	var cash_visible: bool = viewport.grow(1.0).encloses(cash_change.get_global_rect())
	var next_visible: bool = viewport.grow(1.0).encloses(next_day.get_global_rect())
	valid = valid and (cash_visible if not _review_small else (next_visible if _review_frames >= 30 else true))
	print("PROFIT_REVIEW ", JSON.stringify({"real_service": true, "seed": 1,
		"days": _review_reports, "world_tick": _review_tick, "use_saves": use_saves,
		"native_rows": rows, "cash_change": cash_change.text, "cash_inside_scroll": cash_visible,
		"next_day_inside_scroll": next_visible, "scroll_vertical": scroll.scroll_vertical,
		"ui_scale_percent": Preferences.ui_scale_percent,
		"window_size": [get_window().size.x, get_window().size.y], "valid": valid}))
	if not valid:
		push_error("Profit review failed its real closing state or native report bounds")
