extends "res://src/world/main.gd"
## Explicit, unsaved close-data fixture, not a played service/balance claim.
## Ordinary Main close, next-morning and UI paths supply every displayed line.
## Generic screenshot.gd owns exactly frames30/90; observers run at25/75.

const FIXTURE: String = "unsaved Main close data: 34 served/happy, 6 lost, soup20/cheese14; chance1; no played-service claim"

var _review_frame: int = 0
var _review_ready: bool = false
var _review_before: Dictionary = {}
var _review_phase: String = "evening"


func _ready() -> void:
	use_saves = false
	skip_owner_picker = true
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	if sim == null or Clock.sim.phase != SimClock.Phase.MORNING \
			or Clock.sim.day != 1 or GameState.master_seed != 1:
		_review_fail("ordinary seed-one morning did not initialize")
		return
	# Force only the eligible roll in this declared fixture. Production data
	# remains 15%; neither image is offered as evidence of the random odds.
	viral_tuning.viral_chance = 1.0
	sim.served_today = 34
	sim.lost_today = 6
	sim.leave_reasons_today[&"happy"] = 34
	sim.leave_reasons_today[&"waited_too_long"] = 6
	dishes_sold_today = {&"tomato_soup": 20, &"grilled_cheese": 14}
	Clock.sim.phase = SimClock.Phase.CLOSED
	_on_service_closed(1)
	if shown_report == null or not viral_review.triggered_on(1) \
			or shown_report.viral_line != ViralReviewText.evening("Tomato soup") \
			or shown_report.customers_served != 34 or shown_report.customers_lost != 6:
		_review_fail("Main did not close the declared qualifying day")
		return
	if is_staff_visible() and not set_staff_visible(false):
		_review_fail("the ordinary Staff close did not restore the report")
		return
	_review_before = _review_snapshot()
	_review_ready = true


func _process(_delta: float) -> void:
	if not _review_ready:
		return
	_review_frame += 1
	if _review_frame == 10:
		var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
		scroll.ensure_control_visible(_report.get_node("%ViralReviewLine") as Control)
	elif _review_frame == 50:
		if not Clock.sim.next_day() or not set_menu_visible(true):
			_review_fail("the ordinary next-morning Menu path failed")
			return
		_review_phase = "morning"
		_review_before = _review_snapshot()
	if _review_frame == 25 or _review_frame == 75:
		RenderingServer.frame_post_draw.connect(_review_validate, CONNECT_ONE_SHOT)
	elif _review_frame != 50 and _review_before != _review_snapshot():
		_review_fail("presentation mutated service, demand, money or random state")


func _review_validate() -> void:
	if not _review_ready:
		return
	var line: Label
	var clip: Control
	var extra: Label
	if _review_phase == "evening":
		line = _report.get_node("%ViralReviewLine") as Label
		clip = _report.get_node("Panel/Scroll") as Control
		extra = _report.get_node("Panel/Scroll/Content/DemandForecast/Factors") as Label
		if not _report.is_visible_in_tree() or line.text != shown_report.viral_line \
				or not extra.text.contains("Trending online: +35%"):
			_review_fail("native report announcement or separate demand factor is absent")
			return
	else:
		line = _menu_panel.get_node("%ViralNotice") as Label
		clip = _menu_panel.get_node("Panel") as Control
		if not is_menu_visible() or Clock.sim.day != 2 \
				or line.text != ViralReviewText.morning(1.35) \
				or not is_equal_approx(sim.demand_factor, current_demand_snapshot()["total"]):
			_review_fail("native boosted morning reminder or demand did not survive transition")
			return
	var viewport: Rect2 = get_viewport().get_visible_rect()
	for control: Control in [line, extra] if extra != null else [line]:
		if not control.is_visible_in_tree() or not clip.get_global_rect().grow(1.0).encloses(control.get_global_rect()) \
				or not viewport.grow(1.0).encloses(control.get_global_rect()):
			_review_fail("native viral text is hidden or clipped")
			return
	if _review_snapshot() != _review_before:
		_review_fail("observer changed the closed/morning state")
		return
	print("VIRAL_REVIEW ", JSON.stringify({"fixture": FIXTURE, "phase": _review_phase,
		"observer_frame": _review_frame, "photo_frame": 30 if _review_phase == "evening" else 90,
		"timing": "frame_post_draw; before the separately saved photo", "text": line.text,
		"demand_lines": extra.text if extra != null else "", "line_rect": _review_rect(line),
		"demand_rect": _review_rect(extra) if extra != null else [], "clip_rect": _review_rect(clip),
		"viewport_rect": [viewport.position.x, viewport.position.y, viewport.size.x, viewport.size.y],
		"state": _review_before, "unchanged": true, "use_saves": use_saves}))


func _review_snapshot() -> Dictionary:
	return {"day": Clock.sim.day, "phase": Clock.sim.phase, "world_tick": world.now,
		"cash": Economy.cash, "viral": viral_review.to_dict(), "random": GameState._capture_save(),
		"current_demand": current_demand_snapshot(), "next_demand": forecast_next_demand(),
		"served": sim.served_today, "lost": sim.lost_today,
		"report": shown_report.to_dict() if shown_report != null else {}}


func _review_rect(control: Control) -> Array[float]:
	var rect: Rect2 = control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _review_fail(reason: String) -> void:
	_review_ready = false
	push_error("Viral review: " + reason)
