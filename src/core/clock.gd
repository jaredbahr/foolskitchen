extends Node
## Game clock (stub for Phase 0, filled in by the Phase 1 clock issue).
## The sim advances in fixed ticks, independent of frame rate. Speed changes
## how many ticks run per real second; it never changes the tick length.

## Phases of one in-game day (DESIGN.md section 3).
enum Phase { MORNING, OPEN, LAST_ORDERS, CLOSED }

## Sim ticks per in-game second.
const TICKS_PER_SECOND: int = 10

## Allowed speed multipliers. 0 = paused.
const SPEEDS: Array[int] = [0, 1, 2, 4]

var day: int = 1
var phase: Phase = Phase.MORNING
var speed: int = 0
var tick: int = 0


## Sets the speed. Only values in SPEEDS are accepted; returns false otherwise.
func set_speed(value: int) -> bool:
	if not SPEEDS.has(value):
		return false
	speed = value
	return true
