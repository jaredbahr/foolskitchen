class_name MovementTuning
extends Resource
## Deterministic traffic policy. No random jitter or per-agent streams.

@export_range(1, 120, 1) var repath_after_ticks: int = 6
@export_range(1, 240, 1) var yield_after_ticks: int = 10
@export_range(1, 32, 1) var yield_search_radius: int = 8
@export_range(1, 128, 1) var admission_search_radius: int = 32
## Liveness backstop (#306). Someone with a route who has not moved at all for
## this many service ticks gets right of way, and whoever holds their next
## step is asked to clear to any reachable free cell (no radius limit), pushing
## a line of stationary people along when nobody can step aside on their own.
@export_range(1, 2400, 1) var escape_after_ticks: int = 120
## While still stuck, the escape is retried this often.
@export_range(1, 600, 1) var escape_retry_ticks: int = 40
## Last resort: squeeze past the person in the way, swapping places over one
## ordinary step (staff past a guest, or a guest who is already leaving).
@export_range(1, 4800, 1) var squeeze_after_ticks: int = 240
## A guest who still cannot move gives up and leaves ("couldn't get through").
@export_range(1, 9600, 1) var give_up_after_ticks: int = 450
## Let them out first: while the door is jammed with someone leaving, a guest
## arriving from the street waits outside, but never longer than this; past it
## the arrival comes in anyway and the backstop sorts the crowd out.
@export_range(1, 9600, 1) var door_hold_max_ticks: int = 300


func is_valid() -> bool:
	return repath_after_ticks > 0 and yield_after_ticks >= repath_after_ticks \
		and yield_search_radius > 0 and admission_search_radius > 0 \
		and escape_after_ticks >= yield_after_ticks and escape_retry_ticks > 0 \
		and squeeze_after_ticks > escape_after_ticks and give_up_after_ticks > squeeze_after_ticks \
		and door_hold_max_ticks > 0
