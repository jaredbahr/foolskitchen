class_name SimTask
extends RefCounted
## A unit of work posted on the TaskBoard, e.g. "cook burger for table 3".
## The system that posts it (kitchen, customers) listens to the board's
## task_completed / task_failed signals to react.

enum State { OPEN, CLAIMED, DONE, CANCELLED }

## Assigned by the board on post (never reused).
var id: int = 0
## What kind of work, e.g. &"cook", &"deliver", &"bus_table".
var kind: StringName = &""
## Role allowed to take it (&"cook", &"server", ...). &"any" = everyone.
var role: StringName = &"any"
## 0 low .. 3 urgent. Scales the claim score.
var priority: int = 1
## At claim time, yield to eligible higher-priority OPEN work of this exact role.
## This does not preempt claimed work or change the ordinary distance score.
var defer_to_higher_priority: bool = false
## Player-facing description for the "why" readout, e.g. "Cook burger".
var label: String = ""
var steps: Array[TaskStep] = []
## Ticks a claimant may hold the task before it is taken away (self-heal).
var timeout_ticks: int = 600
## Times the task was dropped; after TaskBoard.MAX_DROPS it fails.
var drops: int = 0
## Free-form data for the posting system (order id, recipe id, ...).
var payload: Dictionary = {}

var state: State = State.OPEN
var claimed_by: int = -1
var claimed_tick: int = -1
var posted_tick: int = 0


func _init(task_kind: StringName = &"", task_role: StringName = &"any", task_label: String = "") -> void:
	kind = task_kind
	role = task_role
	label = task_label


## Item the first step targets, or 0 (used to estimate distance when scoring).
func first_item_id() -> int:
	for s in steps:
		if s.kind == TaskStep.Kind.GO_TO_ITEM:
			return s.item_id
	return 0
