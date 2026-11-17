class_name DayLog
extends RefCounted
## Player-facing facts about the current service. The shop owns this log in
## memory only. The HUD consumes formatted lines and cannot mutate entries.

signal changed()

enum Kind { GUEST_LEFT, SOLD_OUT, STOCK_LOW, INSPECTOR, CRITIC, PLATE_SHORTAGE, REVIEW, SERVICE_EVENT }

const MAX_ENTRIES: int = 200
const REPEAT_MINUTES: int = 5

class Entry extends RefCounted:
	var kind: Kind
	var text: String
	var first_tick: int
	var last_tick: int
	var minute: int
	var count: int = 1

var clock: SimClock = SimClock.new()
var _entries: Array[Entry] = []
var _critic_revealed: bool = false


func add(tick: int, kind: Kind, text: String) -> void:
	if text.is_empty():
		return
	var minutes_open: int = maxi(1, clock.display_close_minute - clock.display_open_minute)
	# Compare exact ticks at the shop's configured clock rate. The displayed
	# minute is rounded (and freezes at closing), so it cannot measure the gap.
	var window_ticks: float = float(clock.open_ticks) * REPEAT_MINUTES / minutes_open
	for index: int in range(_entries.size() - 1, -1, -1):
		var recent: Entry = _entries[index]
		if tick - recent.last_tick > window_ticks:
			break
		if recent.kind == kind and recent.text == text and tick - recent.first_tick <= window_ticks:
			recent.last_tick = tick
			recent.minute = clock.display_minutes()
			recent.count += 1
			_entries.remove_at(index)
			_entries.append(recent)
			changed.emit()
			return
	var entry: Entry = Entry.new()
	entry.kind = kind
	entry.text = text
	entry.first_tick = tick
	entry.last_tick = tick
	entry.minute = clock.display_minutes()
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	changed.emit()


## Keep the timestamp, reveal the visit only with the closing report.
func reveal_critic() -> void:
	_critic_revealed = true
	changed.emit()


func clear() -> void:
	_critic_revealed = false
	if _entries.is_empty():
		return
	_entries.clear()
	changed.emit()


func newest_first() -> Array[String]:
	var lines: Array[String] = []
	for index: int in range(_entries.size() - 1, -1, -1):
		var entry: Entry = _entries[index]
		if entry.kind == Kind.CRITIC and not _critic_revealed:
			continue
		var text: String = entry.text
		if entry.kind == Kind.GUEST_LEFT:
			var subject: String = "A guest left" if entry.count == 1 else "%d guests left" % entry.count
			text = "%s: %s" % [subject, text]
		elif entry.count > 1:
			text = "%s (%d times)" % [text, entry.count]
		lines.append("%s  %s" % [StockAlerts.clock_text(entry.minute), text])
	return lines
