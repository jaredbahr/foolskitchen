extends "res://src/world/main.gd"
## Explicit paused view fixture, not a playthrough or a balance result. Histories
## use real promotion/arrival/mood APIs; the seated pose and prior schedules are
## staged so two images cover recognition, inspection and all report notes.

const TABLE_CELL: Vector2i = Vector2i(6, 6)
const FRAMES_BEFORE_REPORT: int = 40

var _fixture_frame: int = 0
var _fixture_ready: bool = false
var _fixture_guest: CustomerAgent
var _fixture_profile: RegularProfile
var _fixture_new: RegularProfile
var _fixture_left: RegularProfile
var _cast_snapshot: Dictionary = {}
var _rng_snapshot: Dictionary = {}
var _fixture_tick: int = 0


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 166
	super._ready()
	Clock.set_speed(0)
	var table: PlacedItem = world.grid.item_at(TABLE_CELL)
	if table == null or table.seat_cells.is_empty() or regulars.profiles.size() != 0:
		_fail("requires a fresh shop with the original middle table")
		return
	var seat: Vector2i = table.seat_cells[0]
	# Three promoted identities exercise the third approved look (female-c).
	for index: int in 3:
		if _promote("review_history_%d" % index, 6, seat) == null:
			_fail("could not promote a satisfied repeat guest")
			return
	_fixture_profile = regulars.profiles[2]
	if _fixture_profile.model_id != &"character-female-c":
		_fail("the authored third profile no longer demonstrates the female-c look")
		return
	var visit_day: int = _fixture_profile.next_visit_day
	# Explicit prior calendars keep the pictured identity next in the real due
	# selector. No service time is advanced to search for a convenient image.
	regulars.profiles[0].next_visit_day = visit_day + 2
	regulars.profiles[1].next_visit_day = visit_day + 3
	Clock.sim.day = visit_day
	if not Clock.sim.start_service():
		_fail("could not enter service for a real named arrival")
		return
	regulars.begin_day(visit_day)
	var guest_random: RandomNumberGenerator = RandomNumberGenerator.new()
	guest_random.seed = 166003
	_fixture_guest = sim.add_customer(world.grid.entries()[0], guest_random,
		customer_type_catalogue.find_type(&"regular"))
	if _fixture_guest == null or _fixture_guest.regular_profile != _fixture_profile \
			or not table.reserve(seat, _fixture_guest.id):
		_fail("the real arrival did not select and reserve the pictured regular")
		return
	# Staged seated pose only: no claimed order, payment or served counter.
	_fixture_guest.table_item_id = table.id
	_fixture_guest.seat_cell = seat
	_fixture_guest.cell = seat
	_fixture_guest.path.clear()
	_fixture_guest.state = CustomerAgent.State.EATING
	_fixture_new = _promote("review_new_today", visit_day, seat)
	_fixture_left = regulars.profiles[0]
	# A prior unhappy-history mood is explicit; the departure itself uses the
	# real threshold and farewell path rather than assigning an inactive flag.
	_fixture_left.mood = regulars.tuning.leave_below + 0.01
	regulars.finish_visit(_fixture_left, visit_day, [] as Array[StringName],
		_fixture_left.favourite_seat, false, 0.0, 1.0, false)
	if _fixture_new == null or _fixture_left.active:
		_fail("could not prepare the real new-regular and farewell report notes")
		return
	var rig: CameraRig = $CameraRig
	var focus: Vector3 = GridMath.cell_to_world(seat)
	rig.minimum_zoom = 3.0
	rig.edge_pan_enabled = false
	rig.frame_area(Vector2(focus.x - 0.4, focus.z + 0.4), Vector2(4.0, 4.0), 4.0, true)
	var view: ShopView = $ShopView
	view._process(0.0)
	if not select_agent(_fixture_guest.id):
		_fail("could not open the production regular inspector")
		return
	_cast_snapshot = regulars.to_dict()
	_rng_snapshot = GameState._capture_save()
	_fixture_tick = world.now
	_fixture_ready = true


func _promote(key: String, promotion_day: int, seat: Vector2i) -> RegularProfile:
	regulars.observe_visit(key, &"regular", 1, 4.0, 10.0, &"burger", seat,
		0.9, true, GameState.rng.bind(&"regulars"))
	return regulars.observe_visit(key, &"regular", promotion_day, 4.0, 10.0,
		&"burger", seat, 0.9, true, GameState.rng.bind(&"regulars"))


## The fixture never calls Main's driver or advances a gameplay tick. Rendering
## and native UI layout continue normally while the screenshot tool counts frames.
func _process(_delta: float) -> void:
	if not _fixture_ready:
		return
	_fixture_frame += 1
	if _fixture_frame == 10:
		_assert_recognition()
	elif _fixture_frame == FRAMES_BEFORE_REPORT:
		_inspect_panel.clear()
		shown_report = build_report(Clock.sim.day)
		_report.call(&"show_report", shown_report)
	elif _fixture_frame == 70:
		var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
		var summary: Label = _report.get("regulars_summary") as Label
		scroll.ensure_control_visible(summary)
	elif _fixture_frame == 80:
		_assert_report()


func _assert_recognition() -> void:
	var view: ShopView = $ShopView
	var person: PersonView = view.agent_nodes.get(_fixture_guest.id) as PersonView
	var indicator: RegularGuestIndicator = view.regular_nodes.get(_fixture_guest.id) as RegularGuestIndicator
	var camera: Camera3D = get_viewport().get_camera_3d()
	var inspector_card: Control = _inspect_panel.get_node("Panel") as Control
	var details: Label = _inspect_panel.get_node("%Details") as Label
	if person == null or indicator == null or camera == null \
			or not person.is_visible_in_tree() or not person.get_meta("person_ready", false) \
			or person.model_name() != _fixture_profile.model_id \
			or person.regular_tint() != _fixture_profile.tint_id \
			or not indicator.star.is_visible_in_tree() or not indicator.name_label.is_visible_in_tree() \
			or not indicator.greeting.is_visible_in_tree() or not _inspect_panel.is_visible_in_tree() \
			or indicator.name_label.text != _fixture_profile.display_name \
			or indicator.greeting.text != _fixture_profile.greeting:
		_fail("native named look, star, greeting or inspector is missing")
		return
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var star_pixel: Vector2 = camera.unproject_position(indicator.star.global_position)
	var name_pixel: Vector2 = camera.unproject_position(indicator.name_label.global_position)
	var greeting_pixel: Vector2 = camera.unproject_position(indicator.greeting.global_position)
	if not camera.is_position_in_frustum(indicator.star.global_position) \
			or not viewport_rect.grow(-40.0).has_point(star_pixel) \
			or not viewport_rect.grow(-40.0).has_point(name_pixel) \
			or not viewport_rect.grow(-40.0).has_point(greeting_pixel) \
			or inspector_card.get_global_rect().has_point(star_pixel) \
			or not viewport_rect.encloses(inspector_card.get_global_rect()) \
			or not details.text.contains("Favourite dish: Burger") \
			or not details.text.contains("Favourite seat:") \
			or not details.text.contains(RegularText.feeling(_fixture_profile.mood)):
		_fail("regular recognition or complete inspector text is outside the viewport")
		return
	if not _unchanged():
		return
	print("REGULARS_REVIEW ", JSON.stringify({"stage": "recognition", "fixture": _fixture_description(),
		"name": _fixture_profile.display_name, "model": String(person.model_name()),
		"clothing_tint": String(person.regular_tint()), "greeting": indicator.greeting.text,
		"star_pixel": [star_pixel.x, star_pixel.y], "inspector": details.text,
		"world_tick": world.now, "use_saves": use_saves}))


func _assert_report() -> void:
	var summary: Label = _report.get("regulars_summary") as Label
	var scroll: ScrollContainer = _report.get_node("Panel/Scroll") as ScrollContainer
	if shown_report == null or not _report.is_visible_in_tree() or summary == null \
			or not summary.is_visible_in_tree() or shown_report.regulars_lines.size() != 3 \
			or not summary.text.contains("Came: " + _fixture_profile.display_name) \
			or not summary.text.contains("New regulars: " + _fixture_new.display_name) \
			or not summary.text.contains(_fixture_left.display_name + " hasn't been back") \
			or not scroll.get_global_rect().grow(1.0).encloses(summary.get_global_rect()):
		_fail("native report is missing visible came, new and farewell notes")
		return
	if not _unchanged():
		return
	print("REGULARS_REVIEW ", JSON.stringify({"stage": "report", "fixture": _fixture_description(),
		"regulars": summary.text, "day": shown_report.day, "world_tick": world.now,
		"report_rect": [summary.global_position.x, summary.global_position.y, summary.size.x, summary.size.y],
		"use_saves": use_saves}))


func _unchanged() -> bool:
	if use_saves or Clock.speed != 0 or world.now != _fixture_tick \
			or regulars.to_dict() != _cast_snapshot or GameState._capture_save() != _rng_snapshot:
		_fail("rendering the paused fixture changed gameplay state or seeded streams")
		return false
	return true


func _fixture_description() -> String:
	return "synthetic satisfied repeat histories; real named arrival and farewell; staged seated pose, prior schedules and low prior mood; no service ticks or saves"


func _fail(reason: String) -> void:
	_fixture_ready = false
	push_error("Regulars review: " + reason)
