extends "res://src/world/main.gd"
## Explicit, unsaved display fixture for #208, not a service or balance claim.
## The walls-review shop (finishes and hung decor) after a short real
## service, shown at one time of day chosen by DAY_NIGHT_STAGE:
## morning, noon, golden, dusk, last_orders, closed, or minute (an open-hours
## minute from DAY_NIGHT_MINUTE, for a fast-day strip). The clock is set for
## display only; the game is paused and nothing is saved.

const WALLS_REVIEW: Script = preload("res://tools/walls_review.gd")
const STAGE_MINUTES: Dictionary = {"noon": 780, "golden": 1080, "dusk": 1230}


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null:
		push_error("Day/night review needs a fresh shop")
		return
	var prepared: Dictionary = WALLS_REVIEW.prepare(self, get_tree().root)
	if not String(prepared.get("error", "missing")).is_empty():
		push_error("Day/night review could not prepare its walls: " + String(prepared.get("error", "")))
		return
	var stage: String = OS.get_environment("DAY_NIGHT_STAGE")
	if stage.is_empty():
		stage = "morning"
	var clock: SimClock = world.clock
	if stage != "morning":
		if not clock.start_service():
			push_error("Day/night review could not open the shop")
			return
		run_ticks(240)
	match stage:
		"morning":
			pass
		"noon", "golden", "dusk", "minute":
			var minute: float = float(STAGE_MINUTES.get(stage, OS.get_environment("DAY_NIGHT_MINUTE").to_int()))
			clock.phase_tick = roundi((minute - clock.display_open_minute)
				/ float(clock.display_close_minute - clock.display_open_minute) * clock.open_ticks)
		"last_orders":
			clock.phase = SimClock.Phase.LAST_ORDERS
			clock.phase_tick = clock.last_orders_max_ticks / 2
		"closed":
			clock.phase = SimClock.Phase.CLOSED
			clock.phase_tick = 0
		_:
			push_error("Unknown DAY_NIGHT_STAGE: " + stage)
			return
	Clock.set_speed(0)
	refresh_presentation()
	print("DAY_NIGHT_REVIEW ", JSON.stringify({"stage": stage, "phase": clock.phase,
		"minute": DayLight.minute_for(clock, 0.0, DAY_LIGHT), "hung": prepared["hung"], "use_saves": use_saves}))
