class_name TaskStep
extends RefCounted
## One step of a SimTask. Steps run in order:
## - GO_TO_ITEM: walk to a free work cell (or seat cell) of an item and reserve it.
## - GO_TO_CELL: walk to a fixed cell (no reservation).
## - WORK: stay put for `ticks` sim ticks (scaled by the agent's work speed).
## - WAIT_UNTIL: keep the current spot until a predicate accepts; the ordinary
##   claimed-task timeout still bounds the wait.
## `on_done` (optional) runs when the step finishes: it receives the agent and
## returns false to fail WORK (for example "fridge is empty"). For WAIT_UNTIL,
## false means keep waiting, while true advances to the next step.

enum Kind { GO_TO_ITEM, GO_TO_CELL, WORK, WAIT_UNTIL }

var kind: Kind = Kind.WORK
var item_id: int = 0
## For GO_TO_ITEM: use a seat cell instead of a work cell.
var use_seat: bool = false
## -1 chooses any free work cell; nonnegative selects one exact rotated work cell.
var work_cell_index: int = -1
var cell: Vector2i = Vector2i.ZERO
var ticks: int = 0
## Short text for the "why" readout, e.g. "fetching ingredients".
var label: String = ""
var on_done: Callable = Callable()
## Optional live station factor. Receives the worker; neutral when absent.
var work_rate: Callable = Callable()


static func go_to_item(target_item_id: int, step_label: String = "", seat: bool = false) -> TaskStep:
	var s := TaskStep.new()
	s.kind = Kind.GO_TO_ITEM
	s.item_id = target_item_id
	s.use_seat = seat
	s.label = step_label
	return s


## Uses one exact work cell, retaining ordinary item reservation and removal handling.
static func go_to_work_cell(target_item_id: int, index: int, step_label: String = "") -> TaskStep:
	var s: TaskStep = go_to_item(target_item_id, step_label)
	s.work_cell_index = index
	return s


static func go_to_cell(target: Vector2i, step_label: String = "") -> TaskStep:
	var s := TaskStep.new()
	s.kind = Kind.GO_TO_CELL
	s.cell = target
	s.label = step_label
	return s


static func work(duration_ticks: int, step_label: String = "", done: Callable = Callable()) -> TaskStep:
	var s := TaskStep.new()
	s.kind = Kind.WORK
	s.ticks = maxi(duration_ticks, 1)
	s.label = step_label
	s.on_done = done
	return s


static func wait_until(condition: Callable, step_label: String) -> TaskStep:
	var s: TaskStep = TaskStep.new()
	s.kind = Kind.WAIT_UNTIL
	s.label = step_label
	s.on_done = condition
	return s
