extends "res://src/world/main.gd"
## Real, paid default services; frame30 Records, frame90 a new-record notice.
## The first recorded day sets every best quietly, so ordinary days are played
## until a close beats one. No grants, synthetic report, RNG reset, or saves.

const MAX_DAYS: int = 5

var _records_ready: bool = false
var _records_frame: int = 0
var _records_expected: Dictionary = {}
var _records_control: Dictionary = {}


func _ready() -> void:
	use_saves = false
	skip_owner_picker = true
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	if Clock.sim.day != 1:
		_records_fail("the ordinary seed-one game did not start on day one")
		return
	for day_index: int in MAX_DAYS:
		if day_index > 0 and not Clock.sim.next_day():
			_records_fail("the ordinary next morning did not begin")
			return
		if not Clock.sim.start_service():
			_records_fail("the ordinary seed-one service did not open")
			return
		run_ticks(6000)
		if Clock.sim.phase != SimClock.Phase.CLOSED or shown_report == null \
				or shown_report.customers_served <= 0:
			_records_fail("the real service did not close with paid guests")
			return
		if day_index == 0 and not shown_report.record_lines.is_empty():
			_records_fail("the first recorded close announced records")
			return
		if not shown_report.record_lines.is_empty():
			break
	if shown_report.record_lines.is_empty():
		_records_fail("no real close beat a record within the bound")
		return
	_records_expected = shop_records.capture()
	_records_control = BalanceProbe._control_snapshot(self, sim)
	if not set_goals_visible(true):
		_records_fail("the ordinary Goals action did not open")
		return
	_records_ready = true


func _process(_delta: float) -> void:
	if not _records_ready:
		return
	_records_frame += 1
	if shop_records.capture() != _records_expected or BalanceProbe._control_snapshot(self, sim) != _records_control:
		_records_fail("presentation changed the closed session or its records")
		return
	if _records_frame == 5:
		var scroll: ScrollContainer = _goals_panel.get_node("Panel/Content/Scroll") as ScrollContainer
		scroll.ensure_control_visible(_goals_panel.get_node("%RecordsRows") as Control)
	elif _records_frame == 25:
		RenderingServer.frame_post_draw.connect(_records_validate.bind(true), CONNECT_ONE_SHOT)
	elif _records_frame == 48:
		if not set_goals_visible(false):
			_records_fail("the ordinary Goals close did not restore the report")
	elif _records_frame == 55:
		var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
		scroll.ensure_control_visible(_report.get_node("%RecordNotices") as Control)
	elif _records_frame == 75:
		RenderingServer.frame_post_draw.connect(_records_validate.bind(false), CONNECT_ONE_SHOT)


func _records_validate(goals: bool) -> void:
	var scroll: ScrollContainer = (_goals_panel.get_node("Panel/Content/Scroll") if goals \
		else _report.get_node("Panel/Column/Scroll")) as ScrollContainer
	var controls: Array[Control] = []
	var texts: Array[String] = []
	if goals:
		if not is_goals_visible() or _report.is_visible_in_tree():
			_records_fail("Records is obscured by another panel")
			return
		controls.append(_goals_panel.get_node("Panel/Content/Scroll/List/RecordsHeading") as Control)
		var rows: VBoxContainer = _goals_panel.get_node("%RecordsRows") as VBoxContainer
		for child: Node in rows.get_children():
			controls.append(child as Control)
			texts.append((child as Label).text)
		if texts != ShopRecordsText.rows(shop_records.snapshot(), content):
			_records_fail("native Records rows differ from the real lifetime state")
			return
	else:
		var notices: Label = _report.get_node("%RecordNotices") as Label
		controls.append(notices)
		texts.append(notices.text)
		if is_goals_visible() or not _report.is_visible_in_tree() \
				or notices.text != "\n".join(PackedStringArray(shown_report.record_lines)):
			_records_fail("the native record notice differs from the real close")
			return
	var bounds: Array[Dictionary] = []
	for control: Control in controls:
		var rect: Rect2 = control.get_global_rect()
		if not control.is_visible_in_tree() or not scroll.get_global_rect().grow(1.0).encloses(rect) \
				or not get_viewport().get_visible_rect().grow(1.0).encloses(rect):
			_records_fail("a native record line is hidden or clipped")
			return
		bounds.append({"name": String(control.name), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	print("SHOP_RECORDS_REVIEW ", JSON.stringify({"view": "records" if goals else "notice",
		"fixture": "ordinary Main seed1 paid default services until a close beats a record; no grants, synthetic report or saves",
		"observed_frame": _records_frame, "validation_timing": "frame_post_draw",
		"master_seed": str(GameState.master_seed), "world_tick": world.now,
		"records": shop_records.capture(), "report": shown_report.to_dict(), "texts": texts,
		"bounds": bounds, "records_unchanged": shop_records.capture() == _records_expected}))


func _records_fail(reason: String) -> void:
	_records_ready = false
	push_error("Records review: " + reason)
