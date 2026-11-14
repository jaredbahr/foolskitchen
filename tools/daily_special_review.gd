extends "res://src/world/main.gd"
## Three native views of one ordinary seed-one special selection and service.
## No grants, synthetic reports, forced sales or save writes.

const BURGER_ID: StringName = &"burger"
const BURGER_BASE_PRICE: int = 12
const BURGER_SPECIAL_PRICE: int = 11

var _review_frame: int = 0
var _review_failed: bool = false
var _morning_snapshot: Dictionary = {}
var _service_snapshot: Dictionary = {}
var _closed_snapshot: Dictionary = {}
var _closed_report: Dictionary = {}
var _paid_burger_prices: Array[int] = []
var _paid_burger_amounts: Array[int] = []


func _ready() -> void:
	use_saves = false
	skip_owner_picker = true
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	if use_saves or Clock.sim.day != 1 or Clock.sim.phase != SimClock.Phase.MORNING \
			or not set_menu_visible(true):
		_review_fail("the ordinary unsaved seed-one morning menu did not open")
		return
	if sim == null or not sim.customer_paid.is_connected(_record_paid_order):
		if sim == null:
			_review_fail("the ordinary Main service is unavailable")
			return
		sim.customer_paid.connect(_record_paid_order)


func _process(_delta: float) -> void:
	super._process(_delta)
	if _review_failed:
		return
	_review_frame += 1
	if _review_frame == 3:
		_choose_burger_through_menu()
	elif _review_frame == 25:
		RenderingServer.frame_post_draw.connect(_validate_morning, CONNECT_ONE_SHOT)
	elif _review_frame == 42:
		_open_real_service()
	elif _review_frame == 55:
		RenderingServer.frame_post_draw.connect(_validate_service_hud, CONNECT_ONE_SHOT)
	elif _review_frame == 66:
		_run_real_service()
	elif _review_frame == 80:
		_show_report_special()
	elif _review_frame == 105:
		RenderingServer.frame_post_draw.connect(_validate_evening_report, CONNECT_ONE_SHOT)
	if _review_failed:
		return
	if _review_frame > 25 and _review_frame < 42 and not _unchanged(_morning_snapshot):
		_review_fail("rendering the morning menu changed the paused session")
	elif _review_frame > 42 and _review_frame < 66 and not _unchanged(_service_snapshot):
		_review_fail("rendering the service HUD changed the paused session")
	elif _review_frame > 66 and not _unchanged(_closed_snapshot):
		_review_fail("rendering or scrolling the evening report changed the closed session")


func _choose_burger_through_menu() -> void:
	var picker: OptionButton = _menu_panel.get_node(
		"Panel/Content/Body/Scroll/Pad/List/DailySpecial/Choice") as OptionButton
	if picker == null or not picker.is_visible_in_tree() or picker.disabled:
		_review_fail("the native morning special dropdown is unavailable")
		return
	for index: int in picker.item_count:
		if StringName(picker.get_item_metadata(index)) == BURGER_ID:
			picker.select(index)
			picker.item_selected.emit(index)
			if daily_special.recipe_id() != BURGER_ID:
				_review_fail("the normal dropdown request did not select Burger")
			return
	_review_fail("Burger is not an enabled choice in the ordinary seed-one menu")


func _validate_morning() -> void:
	var picker: OptionButton = _menu_panel.get_node(
		"Panel/Content/Body/Scroll/Pad/List/DailySpecial/Choice") as OptionButton
	var scroll: ScrollContainer = _menu_panel.get_node("Panel/Content/Body/Scroll") as ScrollContainer
	var heading: Label = picker.get_parent().get_node("Label") as Label if picker != null else null
	var recipe: RecipeDef = menu_settings.recipe(BURGER_ID)
	var rect: Rect2 = picker.get_global_rect() if picker != null else Rect2()
	if Clock.sim.phase != SimClock.Phase.MORNING or not is_menu_visible() or use_saves \
			or recipe == null or daily_special.recipe_id() != BURGER_ID \
			or picker == null or scroll == null or heading == null or not picker.is_visible_in_tree() \
			or not heading.is_visible_in_tree() or picker.disabled \
			or StringName(picker.get_item_metadata(picker.selected)) != BURGER_ID \
			or picker.get_item_text(picker.selected) != recipe.display_name \
			or menu_settings.price_of(recipe) != BURGER_BASE_PRICE or sim.price_of(recipe) != BURGER_SPECIAL_PRICE \
			or not scroll.get_global_rect().grow(1.0).encloses(rect) \
			or not scroll.get_global_rect().grow(1.0).encloses(heading.get_global_rect()) \
			or not get_viewport().get_visible_rect().encloses(rect):
		_review_fail("the selected morning special or its native dropdown did not match the real menu")
		return
	_morning_snapshot = _snapshot()
	print("SPECIAL_REVIEW ", JSON.stringify({"view": "morning", "validated_frame": _review_frame,
		"validation_timing": "frame_post_draw",
		"fixture": "ordinary Main seed1 morning; no saves or grants", "phase": int(Clock.sim.phase),
		"recipe_id": String(BURGER_ID), "display_name": recipe.display_name,
		"selected_option": picker.get_item_text(picker.selected), "normal_price": menu_settings.price_of(recipe),
		"special_price": sim.price_of(recipe), "bounds": _rect_data(rect), "unchanged": true,
		"saves_disabled": not use_saves, "master_seed": str(GameState.master_seed), "world_tick": world.now}))


func _open_real_service() -> void:
	if not _unchanged(_morning_snapshot) or not set_menu_visible(false) or not Clock.sim.start_service() \
			or Clock.sim.phase != SimClock.Phase.OPEN or daily_special.recipe_id() != BURGER_ID:
		_review_fail("the selected special did not enter the ordinary paused service")
		return
	Clock.set_speed(0)
	_service_snapshot = _snapshot()


func _validate_service_hud() -> void:
	var phase: Label = $HUD/Top/Row/Phase as Label
	var header: Control = $HUD/Top as Control
	var rect: Rect2 = phase.get_global_rect() if phase != null else Rect2()
	var recipe: RecipeDef = menu_settings.recipe(BURGER_ID)
	if Clock.sim.phase != SimClock.Phase.OPEN or phase == null or not phase.is_visible_in_tree() \
			or phase.text != "Open  ·  Special: %s" % recipe.display_name \
			or rect.size.x <= 0.0 or rect.size.y <= 0.0 \
			or not header.get_global_rect().encloses(rect) \
			or not get_viewport().get_visible_rect().encloses(rect) \
			or phase.get_theme_font("font").get_string_size(phase.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				phase.get_theme_font_size("font_size")).x > rect.size.x \
			or sim.price_of(recipe) != BURGER_SPECIAL_PRICE or not _unchanged(_service_snapshot):
		_review_fail("the actual OPEN HUD did not show the accepted special without changing the paused session")
		return
	print("SPECIAL_REVIEW ", JSON.stringify({"view": "service_hud", "validated_frame": _review_frame,
		"validation_timing": "frame_post_draw",
		"phase": int(Clock.sim.phase), "label": phase.text, "recipe_id": String(BURGER_ID),
		"special_price": sim.price_of(recipe), "bounds": _rect_data(rect), "unchanged": true,
		"master_seed": str(GameState.master_seed), "world_tick": world.now}))


func _run_real_service() -> void:
	if not _unchanged(_service_snapshot):
		_review_fail("the paused OPEN presentation changed before service")
		return
	run_ticks(6000)
	var report: DayReport = shown_report
	var burger_count: int = int(report.dishes_sold.get(BURGER_ID, 0)) if report != null else 0
	var sale_total: int = int(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.SALE, 0))
	if Clock.sim.phase != SimClock.Phase.CLOSED or report == null or report.customers_served <= 0 \
			or burger_count <= 0 or _paid_burger_prices.size() != burger_count \
			or _paid_burger_amounts.size() != burger_count or sale_total <= 0 \
			or report.daily_special_line != DailySpecialText.report("Burger", burger_count):
		_review_fail("the actual paid seed-one close did not record Burger as its special")
		return
	for index: int in _paid_burger_prices.size():
		if _paid_burger_prices[index] != BURGER_SPECIAL_PRICE \
				or _paid_burger_amounts[index] != BURGER_SPECIAL_PRICE:
			_review_fail("an actual Burger ticket was not charged the special price")
			return
	_closed_snapshot = _snapshot()
	_closed_report = report.to_dict().duplicate(true)


func _show_report_special() -> void:
	if not _unchanged(_closed_snapshot) or _closed_report != shown_report.to_dict():
		_review_fail("the actual closing report changed before its view was shown")
		return
	var special: Label = _report.get_node("Panel/Column/Scroll/Content/DailySpecial") as Label
	var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
	if special == null or scroll == null or not _report.visible:
		_review_fail("the actual evening report special line is unavailable")
		return
	scroll.ensure_control_visible(special)


func _validate_evening_report() -> void:
	var report: DayReport = shown_report
	var special: Label = _report.get_node("Panel/Column/Scroll/Content/DailySpecial") as Label
	var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
	var rect: Rect2 = special.get_global_rect() if special != null else Rect2()
	var burger_count: int = int(report.dishes_sold.get(BURGER_ID, 0)) if report != null else 0
	if Clock.sim.phase != SimClock.Phase.CLOSED or report == null or not _report.is_visible_in_tree() \
			or special == null or scroll == null or not special.is_visible_in_tree() \
			or special.text != DailySpecialText.report("Burger", burger_count) \
			or burger_count != _paid_burger_prices.size() or not scroll.get_global_rect().grow(1.0).encloses(rect) \
			or not get_viewport().get_visible_rect().encloses(rect) \
			or _closed_report != report.to_dict() or not _unchanged(_closed_snapshot):
		_review_fail("the paid special line is missing, clipped or inconsistent with the closed report")
		return
	print("SPECIAL_REVIEW ", JSON.stringify({"view": "evening_report", "validated_frame": _review_frame,
		"validation_timing": "frame_post_draw",
		"phase": int(Clock.sim.phase), "recipe_id": String(BURGER_ID),
		"burger_paid_count": _paid_burger_prices.size(), "burger_report_count": burger_count,
		"discounted_ticket_prices": _paid_burger_prices, "sale_total": int(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.SALE, 0)),
		"daily_special_line": report.daily_special_line, "displayed_text": special.text,
		"bounds": _rect_data(rect),
		"unchanged": true, "saves_disabled": not use_saves,
		"master_seed": str(GameState.master_seed), "world_tick": world.now}))


func _record_paid_order(_customer: CustomerAgent, order: Order, amount: int) -> void:
	if order != null and order.recipe_id == BURGER_ID:
		_paid_burger_prices.append(order.price)
		_paid_burger_amounts.append(amount)


func _unchanged(snapshot: Dictionary) -> bool:
	return not snapshot.is_empty() and snapshot == _snapshot()


func _snapshot() -> Dictionary:
	var state: Dictionary = BalanceProbe._control_snapshot(self, sim)
	state["daily_special"] = daily_special.to_dict()
	return state


func _rect_data(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _review_fail(reason: String) -> void:
	_review_failed = true
	push_error("Daily special review: " + reason)
