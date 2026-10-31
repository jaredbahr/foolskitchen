extends "res://src/world/main.gd"
## Fixed real Main service, not a staged report or the probe's RNG-reset profile.
## The existing expanded_tables fixture builds free; stock and service are paid.

const REVIEW_DAYS: int = 14
const REVIEW_SETUP: String = "expanded_tables"
const REVIEW_RULES: StaffAdviceTuning = preload("res://data/balance/staff_advice.tres")

var _review_ready: bool = false
var _review_frames: int = 0
var _review_state: Dictionary = {}
var _review_report: Dictionary = {}
var _review_daily: Array[Dictionary] = []
var _review_setup: Dictionary = {}


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	if sim == null or Clock.sim.day != 1 or Clock.sim.phase != SimClock.Phase.MORNING \
			or GameState.master_seed != 1 or not ProbeSetups.apply(REVIEW_SETUP, self):
		_review_fail("the fixed seed-one morning setup failed")
		return
	_review_setup = {"cash_after_free_construction": Economy.cash,
		"staff": staff_roster.to_dict(), "owner_mode": String(sim.owner_agent().current_mode()),
		"tables": _review_tables()}
	# Main already prepared the paid morning. Do not reset its day or RNGs.
	for day_index: int in range(REVIEW_DAYS):
		if day_index > 0 and not ProbeSetups.morning(REVIEW_SETUP, self):
			_review_fail("the ordinary setup morning failed")
			return
		if not Clock.sim.start_service():
			_review_fail("the real service did not open")
			return
		var batches: int = 0
		while Clock.sim.phase != SimClock.Phase.CLOSED and batches < 30:
			run_ticks(1000)
			batches += 1
		if Clock.sim.phase != SimClock.Phase.CLOSED or shown_report == null \
				or shown_report.day != day_index + 1:
			_review_fail("the real service did not produce its closing report")
			return
		_review_daily.append({"day": shown_report.day, "cash": Economy.cash,
			"report": shown_report.to_dict(),
			"advice": String(REVIEW_RULES.recommendation(shown_report.staff_activity, shown_report.leave_reasons))})
		if day_index + 1 < REVIEW_DAYS and not Clock.sim.next_day():
			_review_fail("the next ordinary morning did not start")
			return
	Clock.set_speed(0)
	_review_state = BalanceProbe._control_snapshot(self, sim)
	_review_report = shown_report.to_dict().duplicate(true)
	# Ordinary growth notices can leave Staff open. Its normal Close restores
	# the existing evening report without settling the service again.
	if is_staff_visible() and not set_staff_visible(false):
		_review_fail("the ordinary Staff close did not restore the report")
		return
	# Keep the actual result even when the declared case fails the advice gate.
	print("STAFF_ACTIVITY_SERVICE_RESULT ", JSON.stringify({"setup": REVIEW_SETUP,
		"seed": str(GameState.master_seed), "days": REVIEW_DAYS, "cash": Economy.cash,
		"report": _review_report, "daily": _review_daily,
		"advice": String(REVIEW_RULES.recommendation(shown_report.staff_activity, shown_report.leave_reasons))}))
	_review_ready = true


func _process(_delta: float) -> void:
	if not _review_ready:
		return
	_review_frames += 1
	if _review_state != BalanceProbe._control_snapshot(self, sim) \
			or shown_report == null or _review_report != shown_report.to_dict() or use_saves:
		_review_fail("presentation changed the closed session snapshot")
		return
	var section: Control = _report.get_node_or_null("%TeamSection") as Control
	if section == null:
		_review_fail("Your team section is missing")
		return
	if _review_frames == 10:
		var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
		var reasons: Control = _report.get_node("Panel/Scroll/Content/ReasonHeading") as Control
		scroll.scroll_vertical = maxi(0, roundi(reasons.position.y))
	elif _review_frames == 25:
		RenderingServer.frame_post_draw.connect(_review_validate, CONNECT_ONE_SHOT)


func _review_validate() -> void:
	if not _review_ready:
		return
	var activity: Dictionary = StaffActivity.public_snapshot(shown_report.staff_activity)
	var advice_id: StringName = REVIEW_RULES.recommendation(activity, shown_report.leave_reasons)
	if activity.is_empty() or activity != sim.staff_activity.snapshot() \
			or shown_report.day != REVIEW_DAYS or Clock.sim.phase != SimClock.Phase.CLOSED \
			or GameState.master_seed != 1 or new_game_seed_override != 1 or use_saves:
		_review_fail("the report does not match the actual fixed service")
		return
	if advice_id != &"cook":
		_review_fail("the fixed day-fourteen service did not naturally recommend a cook; actual result retained")
		return
	var section: Control = _report.get_node("%TeamSection") as Control
	var heading: Label = _report.get_node("%TeamHeading") as Label
	var rows: VBoxContainer = _report.get_node("%TeamActivityRows") as VBoxContainer
	var advice: Label = _report.get_node("%TeamAdvice") as Label
	var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
	var reasons_heading: Label = _report.get_node("Panel/Scroll/Content/ReasonHeading") as Label
	var reasons: GridContainer = _report.get_node("%ReasonRows") as GridContainer
	if heading.text != StaffAdviceText.TEAM_HEADING \
			or advice.text != StaffAdviceText.recommendation(advice_id):
		_review_fail("the native team heading or advice differs from the actual report")
		return
	var controls: Array[Control] = [section, heading, advice, reasons_heading, reasons]
	var role_evidence: Array[Dictionary] = []
	for index: int in range(StaffAdviceText.ROLES.size()):
		var role: StringName = StaffAdviceText.ROLES[index]
		var label: Label = rows.get_node(NodePath(String(StaffAdviceText.ROLE_NODES[index]))) as Label
		var expected: String = StaffAdviceText.role_line(role, activity)
		if label.text != expected or label.visible != (not expected.is_empty()):
			_review_fail("a native role line differs from the actual activity")
			return
		if not expected.is_empty():
			controls.append(label)
			role_evidence.append({"role": String(role), "text": label.text, "rect": _review_rect(label)})
	for child: Node in reasons.get_children():
		if child is Control:
			controls.append(child as Control)
	if is_staff_visible() or is_menu_visible() or is_stock_visible() \
			or is_settings_visible() or is_goals_visible():
		_review_fail("another native panel obscures the report")
		return
	var clip: Rect2 = scroll.get_global_rect().grow(1.0)
	var viewport: Rect2 = get_viewport().get_visible_rect().grow(1.0)
	for control: Control in controls:
		if not control.is_visible_in_tree() or not clip.encloses(control.get_global_rect()) \
				or not viewport.encloses(control.get_global_rect()):
			_review_fail("the native team or departure reasons are hidden or clipped")
			return
	var reason_lines: PackedStringArray = []
	for child: Node in reasons.get_children():
		var label: Label = child as Label
		if label != null:
			reason_lines.append(label.text)
	if _review_state != BalanceProbe._control_snapshot(self, sim) or _review_report != shown_report.to_dict():
		_review_fail("native validation changed the closed session snapshot")
		return
	print("STAFF_ACTIVITY_REPORT_REVIEW ", JSON.stringify({
		"fixture": "actual Main seed1 expanded_tables fourteen-day service; free construction of 15 floor cells and two tables; normal paid stock and service; no grants or saves",
		"profile": "ordinary Main morning; no additional day or RNG reset; differs from BalanceProbe initialization",
		"setup": REVIEW_SETUP, "seed": str(GameState.master_seed), "days": REVIEW_DAYS,
		"day": shown_report.day, "cash": Economy.cash, "initial_setup": _review_setup,
		"report": _review_report, "report_sha256": JSON.stringify(_review_report).sha256_text(),
		"activity": activity, "advice_id": String(advice_id),
		"thresholds": {"high_busy_percent": REVIEW_RULES.high_busy_percent,
			"low_busy_percent": REVIEW_RULES.low_busy_percent,
			"min_waiting_losses": REVIEW_RULES.min_waiting_losses,
			"min_no_table_losses": REVIEW_RULES.min_no_table_losses},
		"heading": heading.text, "roles": role_evidence, "advice": advice.text,
		"reasons": reason_lines, "section_rect": _review_rect(section),
		"heading_rect": _review_rect(heading), "advice_rect": _review_rect(advice),
		"reasons_rect": _review_rect(reasons), "scroll_rect": _review_rect(scroll),
		"viewport_rect": [viewport.position.x, viewport.position.y, viewport.size.x, viewport.size.y],
		"validation_timing": "frame_post_draw", "world_tick": world.now,
		"rng": GameState._capture_save(), "unchanged": true}))


func _review_rect(control: Control) -> Array[float]:
	var rect: Rect2 = control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _review_tables() -> Array[Dictionary]:
	var tables: Array[Dictionary] = []
	for placed: PlacedItem in world.grid.items():
		var definition: ItemDef = placed.def as ItemDef
		if definition != null and definition.category == ItemDef.Category.TABLE:
			tables.append({"id": placed.id, "item": String(definition.id),
				"origin": [placed.origin.x, placed.origin.y], "quarter_turns": placed.quarter_turns})
	return tables


func _review_fail(reason: String) -> void:
	_review_ready = false
	push_error("Staff activity report review: " + reason)
