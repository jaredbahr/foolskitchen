extends "res://src/world/main.gd"
## Explicit, unsaved review of a service event card (#495). Capture with
##   bash tools/screenshot.sh --out=screens/service-event --scene=res://tools/service_event_review.tscn --frames=60 --speed=0
## SERVICE_EVENT_REVIEW_ID picks the card (default busker). The day's real
## service runs for a while so guests are in, then the chosen card comes up
## through the session's own path (its names drawn from the run's seed), and
## the game pauses on it. Nothing is saved.

const WARM_UP_TICKS: int = 900

func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	service_events_for_tools = true
	super._ready()
	Clock.set_speed(0)
	if not Clock.sim.start_service():
		_fail("could not enter service")
		return
	# Today's own cards would come later; keep only the reviewed one.
	service_events.schedule.clear()
	run_ticks(WARM_UP_TICKS)
	var id: StringName = StringName(OS.get_environment("SERVICE_EVENT_REVIEW_ID"))
	if id.is_empty():
		id = &"busker"
	var event: ServiceEventDef = service_events.definition(id)
	if event == null or not service_events.can_show(event, Clock.sim.day, _service_event_context()):
		_fail("%s cannot come up in this shop" % id)
		return
	var minute: int = Clock.sim.display_minutes()
	service_events.schedule = [service_events._entry(event, minute, GameState.master_seed,
		Clock.sim.day, _service_event_context())]
	Clock.set_speed(1)
	_check_service_event()
	if not is_service_event_visible() or Clock.speed != 0:
		_fail("the card did not pause the game")
		return
	print("SERVICE_EVENT_REVIEW ", JSON.stringify({"id": id, "minute": minute,
		"choices": _service_event_card.choice_buttons().size(), "use_saves": use_saves}))


func _fail(reason: String) -> void:
	push_error("service_event_review: " + reason)
	get_tree().quit(1)
