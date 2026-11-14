extends "res://src/world/main.gd"
## Two-frame, unsaved review of the announced rush (#325).
## Capture with the existing screenshot entrypoint:
##   bash tools/screenshot.sh --scene=res://tools/rush_hour_review.tscn --speed=0 --frames=12,90
## Frame 12 shows the morning Menu notice. Frame 90 shows the same seeded plan's
## actual evening report after the real CustomerSpawner and RestaurantSim ticks.

const OWNER_LEVEL: int = 2
const ARRIVAL_GAP: int = 60

var _review_frame: int = 0


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 325
	super._ready()
	Clock.set_speed(0)
	if sim == null:
		return
	owner_progress.award_bonus(owner_progress.threshold_for(OWNER_LEVEL))
	sim.set_customer_level(owner_progress.level)
	$HUD.set_owner_progress(owner_progress.level, owner_progress.xp_into_level(), owner_progress.xp_in_level())
	Clock.sim.day = 2
	sim.rush_hour.tuning = RUSH_TUNING.duplicate(true) as RushTuning
	sim.rush_hour.tuning.daily_chance = 1.0
	sim.customer_types = null
	sim.spawner.min_gap = ARRIVAL_GAP
	sim.spawner.max_gap = ARRIVAL_GAP
	_begin_morning()
	if not sim.rush_hour.has_event():
		push_error("Rush review: the seeded morning plan was not created")
		return
	sim.spawner._remaining = ARRIVAL_GAP
	if not set_menu_visible(true):
		push_error("Rush review: the morning Menu panel did not open")
		return
	print("RUSH_HOUR_REVIEW ", JSON.stringify({"stage": "morning", "day": Clock.sim.day,
		"level": owner_progress.level, "notice": sim.rush_hour.morning_notice(),
		"occasion": sim.rush_hour.occasion, "start_minute": sim.rush_hour.start_minute,
		"duration_minutes": sim.rush_hour.duration_minutes, "use_saves": use_saves,
		"fixture": "unsaved level-2 plan, 100% review-only chance, fixed gap 60, customer types disabled"}))


func _process(delta: float) -> void:
	super._process(delta)
	_review_frame += 1
	if _review_frame == 30:
		_capture_real_service_report()
	elif _review_frame == 42:
		var rush_label: Control = _report.get_node_or_null("Panel/Column/Scroll/Content/RushHour") as Control
		if rush_label != null:
			(_report.get_node("Panel/Column/Scroll") as ScrollContainer).ensure_control_visible(rush_label)


func _capture_real_service_report() -> void:
	set_menu_visible(false)
	if not Clock.sim.start_service():
		push_error("Rush review: service did not start")
		return
	# This single controlled service uses the fixture's actual event clock,
	# spawner, visitors and departure reasons; it does not fabricate report counts.
	var bounded_ticks: int = Clock.sim.open_ticks + Clock.sim.last_orders_max_ticks + 10
	for _tick: int in bounded_ticks:
		sim.advance()
		EventBus.sim_ticked.emit(Clock.sim.tick)
		if Clock.sim.phase == SimClock.Phase.CLOSED:
			break
	if Clock.sim.phase != SimClock.Phase.CLOSED or shown_report == null:
		push_error("Rush review: bounded service run did not reach the actual closed report")
		return
	print("RUSH_HOUR_REVIEW ", JSON.stringify({"stage": "report", "day": shown_report.day,
		"lines": shown_report.rush_hour_lines, "actual_arrival_headcount": sim.rush_hour.cohort_arrivals,
		"no_seat_losses": sim.rush_hour.cohort_lost_no_seat,
		"patience_losses": sim.rush_hour.cohort_lost_patience,
		"event_duration_minutes": sim.rush_hour.duration_minutes, "use_saves": use_saves,
		"fixture": "fixed gap 60, customer types disabled; actual service close"}))
