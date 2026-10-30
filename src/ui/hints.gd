class_name Hints
extends RefCounted
## Optional presentation progress. No clock, world or random state is changed.

enum Step { MENU, STOCK, BUILD, OPEN, QUEUE, DIRTY, REPORT, DAY_TWO, COMPLETE }

const GOT_IT: String = "Got it"
const SKIP_GUIDE: String = "Skip guide"
const SHOW_AGAIN: String = "Show guide again"
const TITLE: String = "A little help"

class Context extends RefCounted:
	var day: int = 1
	var phase: int = SimClock.Phase.MORNING
	var menu_open: bool = false
	var queued_guest: bool = false
	var dirty_table: bool = false
	var report_visible: bool = false
	var targets_visible: Dictionary[int, bool] = {}

var next_hint: int = Step.MENU
var active_hint: int = -1
var menu_finished: bool = false
var _menu_seen: bool = false
var _queued_seen: bool = false
var _dirty_seen: bool = false
var _report_seen: bool = false
var _first_day: int = 1


func observe(context: Context) -> int:
	if next_hint == Step.COMPLETE and active_hint < 0:
		return -1
	if context.day > _first_day + 1:
		skip()
		return -1
	if context.day == _first_day + 1 and next_hint < Step.DAY_TWO:
		active_hint = -1
		next_hint = Step.DAY_TWO
	if context.day == _first_day:
		if context.menu_open:
			_menu_seen = true
		elif _menu_seen:
			menu_finished = true
		_queued_seen = _queued_seen or context.queued_guest
		_dirty_seen = _dirty_seen or context.dirty_table
		_report_seen = _report_seen or context.report_visible
	if active_hint >= 0:
		if not context.targets_visible.get(active_hint, true) or not _phase_allows(active_hint, context):
			if active_hint == Step.MENU and not context.targets_visible.get(active_hint, true):
				menu_finished = true
			active_hint = -1
		else:
			return active_hint
	while next_hint < Step.COMPLETE:
		if context.day == _first_day and context.phase != SimClock.Phase.MORNING and next_hint <= Step.OPEN:
			next_hint = Step.QUEUE
		if context.day == _first_day and context.phase == SimClock.Phase.CLOSED and next_hint in [Step.QUEUE, Step.DIRTY]:
			next_hint = Step.REPORT
		if not _triggered(next_hint, context):
			return -1
		var step: int = next_hint
		next_hint += 1
		if context.targets_visible.get(step, true):
			active_hint = step
			return step
		if step == Step.MENU:
			menu_finished = true
	return -1


func _phase_allows(step: int, context: Context) -> bool:
	if step <= Step.OPEN or step == Step.DAY_TWO:
		return context.phase == SimClock.Phase.MORNING
	if step == Step.REPORT:
		return context.report_visible
	return context.phase == SimClock.Phase.OPEN or context.phase == SimClock.Phase.LAST_ORDERS


func _triggered(step: int, context: Context) -> bool:
	if step == Step.DAY_TWO:
		return context.day == _first_day + 1 and context.phase == SimClock.Phase.MORNING
	if context.day != _first_day:
		return false
	match step:
		Step.MENU:
			return true
		Step.STOCK:
			return menu_finished
		Step.BUILD, Step.OPEN:
			return true
		Step.QUEUE:
			return _queued_seen
		Step.DIRTY:
			return _dirty_seen
		Step.REPORT:
			return _report_seen and context.report_visible
	return false


func acknowledge() -> void:
	active_hint = -1


func skip() -> void:
	next_hint = Step.COMPLETE
	active_hint = -1


func restart(first_day: int = 1) -> void:
	next_hint = Step.MENU
	active_hint = -1
	menu_finished = false
	_menu_seen = false
	_queued_seen = false
	_dirty_seen = false
	_report_seen = false
	_first_day = maxi(1, first_day)


func capture() -> Dictionary:
	return {"next_hint": next_hint, "active_hint": active_hint, "menu_finished": menu_finished,
		"menu_seen": _menu_seen, "queued_seen": _queued_seen, "dirty_seen": _dirty_seen,
		"report_seen": _report_seen, "first_day": _first_day}


func restore(data: Dictionary) -> bool:
	for key: String in ["next_hint", "active_hint", "first_day"]:
		if not data.has(key) or not (data[key] is int or data[key] is float) \
				or not is_finite(float(data[key])) or float(data[key]) != float(int(data[key])):
			return false
	for key: String in ["menu_finished", "menu_seen", "queued_seen", "dirty_seen", "report_seen"]:
		if not data.get(key) is bool:
			return false
	var next: int = int(data["next_hint"])
	var active: int = int(data["active_hint"])
	if next < Step.MENU or next > Step.COMPLETE or active < -1 or active >= Step.COMPLETE \
			or (active >= 0 and active != next - 1) or int(data["first_day"]) < 1:
		return false
	next_hint = next
	active_hint = active
	menu_finished = data["menu_finished"]
	_menu_seen = data["menu_seen"]
	_queued_seen = data["queued_seen"]
	_dirty_seen = data["dirty_seen"]
	_report_seen = data["report_seen"]
	_first_day = int(data["first_day"])
	return true


static func text_for(step: int) -> String:
	match step:
		Step.MENU: return "Plan today's dishes and prices"
		Step.STOCK: return "Check your fridge and shelves; order what you need"
		Step.BUILD: return "Move or buy furniture; paint rooms in Build"
		Step.OPEN: return "Ready? Open shop to welcome your first guests"
		Step.QUEUE: return "Guests queue by the door until a table is ready"
		Step.DIRTY: return "Staff clear dirty tables so the next guests can sit"
		Step.REPORT: return "Check the evening report to see how today went"
		Step.DAY_TWO: return "Hire and plan in the mornings. You're on your own now"
	return ""
