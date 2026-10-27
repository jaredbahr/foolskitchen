extends CanvasLayer
## Event-driven day, speed and cash controls. refresh() also supports scenes
## instantiated before SceneTree readiness (including the custom test runner).

const SPEEDS: Array[int] = [0, 1, 2, 4]
const PHASE_NAMES: Array[String] = ["Morning", "Open", "Last orders", "Closed"]
const STAFF_PHASES: Array[int] = [SimClock.Phase.MORNING, SimClock.Phase.OPEN,
	SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED]
const GAIN_COLOR: Color = Color("286B3B")
const LOSS_COLOR: Color = Color("A42E2E")

signal build_toggled()
signal paint_toggled()
signal menu_pressed()
signal staff_pressed()
signal stock_pressed()
signal settings_pressed()
signal header_layout_changed()

var _day_label: Label
var _time_label: Label
var _phase_label: Label
var _cash_label: Label
var _loan_label: Label
var _loan_principal: int = 0
var _loan_repay_share: float = 0.0
var _loan_daily_interest: float = 0.0
var _reputation_label: Label
var _owner_level_label: Label
var _owner_xp_bar: ProgressBar
var _plate_label: Label
var _context: Button
var _deltas: Control
var _merge_label: Label = null
var _merge_frame: int = -1
var _merge_amount: int = 0
var _buttons: Array[Button] = []
var _cash: int = 0
var _reputation_average: float = 3.0
var _reputation_count: int = 5
var _vibe_theme: String = ""
var _owner_level: int = 1
var _owner_xp_into: int = 0
var _owner_xp_needed: int = 1
var _wall_button: Button
var _shop_view: ShopView
var _build_button: Button
var _paint_button: Button
var _paint_active: bool = false
var _build_hints: PanelContainer
var _build_hint_text: Label
var _build_hint_scroll: ScrollContainer
var _hint_viewport: Viewport
var _build_available: bool = false
var _build_active: bool = false
var _build_reason: String = ""
var _build_state: int = BuildMode.State.IDLE
var _menu_button: Button
var _staff_button: Button
var _stock_button: Button
var _sold_out_label: Label
var _sold_out_names: Array[String] = []
var _settings_button: Button
var _header_bottom: float = -1.0
var _preferences: SettingsPreferences


func bind_preferences(model: SettingsPreferences) -> void:
	_preferences = model


func _ready() -> void:
	refresh()


## Idempotently binds controls and events, then renders current simulation state.
func refresh() -> void:
	if _day_label == null:
		_day_label = get_node("Top/Row/Day") as Label
		_time_label = get_node("Top/Row/Time") as Label
		_phase_label = get_node("Top/Row/Phase") as Label
		_cash_label = get_node("Top/Row/Cash") as Label
		_loan_label = get_node("Top/Row/Loan") as Label
		_reputation_label = get_node("Top/Row/Reputation") as Label
		_owner_level_label = get_node("Top/Row/OwnerProgress/OwnerLevel") as Label
		_owner_xp_bar = get_node("Top/Row/OwnerProgress/OwnerXPBar") as ProgressBar
		_context = get_node("Top/Row/Context") as Button
		_deltas = get_node("Deltas") as Control
		_wall_button = get_node("Top/Row/Walls") as Button
		_wall_button.pressed.connect(_on_wall_button_pressed)
		_build_button = get_node("Top/Row/Build") as Button
		_build_hints = get_node("BuildHints") as PanelContainer
		_build_hint_scroll = get_node("BuildHints/Scroll") as ScrollContainer
		_build_hint_text = get_node("BuildHints/Scroll/Text") as Label
		var style: StyleBox = _build_hints.theme.get_stylebox("panel", "PanelContainer").duplicate() as StyleBox
		style.set_content_margin(SIDE_LEFT, 10.0)
		style.set_content_margin(SIDE_RIGHT, 10.0)
		style.set_content_margin(SIDE_TOP, 6.0)
		style.set_content_margin(SIDE_BOTTOM, 6.0)
		_build_hints.add_theme_stylebox_override("panel", style)
		_build_button.pressed.connect(_on_build_pressed)
		_paint_button = get_node("Top/Row/Paint") as Button
		_paint_button.pressed.connect(_on_paint_pressed)
		_menu_button = get_node("Top/Row/Menu") as Button
		_menu_button.pressed.connect(_on_menu_pressed)
		_staff_button = get_node("Top/Row/Staff") as Button
		_staff_button.pressed.connect(_on_staff_pressed)
		_stock_button = get_node("Top/Row/Stock") as Button
		_stock_button.pressed.connect(_on_stock_pressed)
		_sold_out_label = get_node("Top/Row/SoldOut") as Label
		_settings_button = get_node("Top/Row/Settings") as Button
		_settings_button.pressed.connect(_on_settings_pressed)
		_style_header()
		(get_node("Top") as Control).resized.connect(_on_header_resized)
		(get_node("Top/Row") as Control).minimum_size_changed.connect(_fit_header_height)
		_cash = Economy.cash
		for speed: int in SPEEDS:
			var button: Button = get_node("Top/Row/Speed%d" % speed) as Button
			_buttons.append(button)
			button.pressed.connect(_set_speed.bind(speed))
		_context.pressed.connect(_on_context_pressed)
	if not EventBus.sim_ticked.is_connected(_on_sim_ticked):
		EventBus.sim_ticked.connect(_on_sim_ticked)
		EventBus.day_phase_changed.connect(_on_phase_changed)
		EventBus.speed_changed.connect(_on_speed_changed)
		EventBus.cash_changed.connect(_on_cash_changed)
	_day_label.text = "Day %d" % Clock.sim.day
	_time_label.text = Fmt.clock(Clock.sim.display_minutes())
	_phase_label.text = PHASE_NAMES[Clock.sim.phase]
	_cash_label.text = Fmt.money(_cash)
	_render_loan()
	_render_reputation()
	_render_owner_progress()
	if _sold_out_label.visible != (not _sold_out_names.is_empty() and (Clock.sim.phase == SimClock.Phase.OPEN
			or Clock.sim.phase == SimClock.Phase.LAST_ORDERS)):
		_render_sold_out()
	_context.visible = Clock.sim.phase == SimClock.Phase.MORNING or Clock.sim.phase == SimClock.Phase.CLOSED
	_context.text = "Open shop" if Clock.sim.phase == SimClock.Phase.MORNING else "Next day"
	_context.tooltip_text = "Open for today's service" if Clock.sim.phase == SimClock.Phase.MORNING else "Begin the next morning"
	_on_speed_changed(Clock.speed)
	_refresh_wall_mode()
	if is_inside_tree() and _hint_viewport != get_viewport():
		if _hint_viewport != null and _hint_viewport.size_changed.is_connected(_layout_build_hints):
			_hint_viewport.size_changed.disconnect(_layout_build_hints)
		_hint_viewport = get_viewport()
		_hint_viewport.size_changed.connect(_layout_build_hints)
	_refresh_build_controls()
	_menu_button.disabled = Clock.sim.phase != SimClock.Phase.MORNING
	_menu_button.tooltip_text = "Choose today's menu and prices" if not _menu_button.disabled else "Menu changes are available in the morning."
	_stock_button.disabled = Clock.sim.phase != SimClock.Phase.MORNING
	_stock_button.tooltip_text = "Check the fridge, buy ingredients and set auto-reorder" if not _stock_button.disabled \
		else "Stock is bought in the morning."
	_staff_button.disabled = not STAFF_PHASES.has(Clock.sim.phase)
	_staff_button.tooltip_text = "Hire staff and plan today's wages" if Clock.sim.phase == SimClock.Phase.MORNING \
		else "Set staff job priorities. Hiring and upgrades are available in the morning."
	_layout_header()


## Main supplies the rolling score and sample count; the HUD only presents it.
func set_reputation(average: float, count: int) -> void:
	_reputation_average = clampf(average, 0.0, 5.0)
	_reputation_count = clampi(count, 0, 30)
	if _reputation_label == null:
		_reputation_label = get_node("Top/Row/Reputation") as Label
	_render_reputation()


func _render_reputation() -> void:
	_reputation_label.text = "%.1f" % _reputation_average
	var text: String = "%.1f stars from your last %d reviews" % [_reputation_average, _reputation_count]
	_reputation_label.tooltip_text = text + ("\nTheme: %s" % _vibe_theme if not _vibe_theme.is_empty() else "")


## Theme is tooltip-only, so the existing header keeps its native width.
func set_vibe(result: VibeModel.Result) -> void:
	_vibe_theme = result.theme_label if result != null and result.valid \
		and not result.active_theme.is_empty() else "No active theme"
	if _reputation_label == null:
		_reputation_label = get_node("Top/Row/Reputation") as Label
	_render_reputation()


## Primitive presentation only; Main owns the loan and its day-close policy.
func set_loan_state(principal: int, repay_share: float, daily_interest: float) -> void:
	_loan_principal = maxi(0, principal)
	_loan_repay_share = clampf(repay_share, 0.0, 1.0)
	_loan_daily_interest = maxf(0.0, daily_interest)
	if _loan_label == null:
		refresh()
	else:
		_render_loan()


func _render_loan() -> void:
	_loan_label.text = "Loan %s" % Fmt.money(_loan_principal)
	_loan_label.tooltip_text = "The bank takes up to %s of positive daily profit to repay this loan. Interest is %s a day. Big furniture purchases and upgrades wait until it's paid back." % [
		_percentage_text(_loan_repay_share), _percentage_text(_loan_daily_interest)]
	_loan_label.visible = _loan_principal > 0
	var row: Container = get_node("Top/Row") as Container
	row.update_minimum_size()
	row.queue_sort()


func _percentage_text(rate: float) -> String:
	var percent: float = rate * 100.0
	return "%d%%" % roundi(percent) if is_equal_approx(percent, roundf(percent)) else "%.1f%%" % percent


## Main supplies XP within the current level and the next-level requirement.
func set_owner_progress(level: int, into: int, needed: int) -> void:
	_owner_level = maxi(level, 1)
	_owner_xp_needed = maxi(needed, 1)
	_owner_xp_into = clampi(into, 0, _owner_xp_needed)
	if _owner_level_label == null:
		_owner_level_label = get_node("Top/Row/OwnerProgress/OwnerLevel") as Label
		_owner_xp_bar = get_node("Top/Row/OwnerProgress/OwnerXPBar") as ProgressBar
	_render_owner_progress()


func _render_owner_progress() -> void:
	_owner_level_label.text = "Lv %d" % _owner_level
	_owner_xp_bar.max_value = _owner_xp_needed
	_owner_xp_bar.value = _owner_xp_into
	var detail: String = "Owner level %d: %d / %d XP to next level" % [
		_owner_level, _owner_xp_into, _owner_xp_needed]
	_owner_level_label.tooltip_text = detail
	_owner_xp_bar.tooltip_text = detail


## Window's visible rect already uses content-scaled UI coordinates. The row
## container measures native content and wraps intact groups when needed.
func _layout_header() -> void:
	(get_node("Top/Row") as Container).queue_sort()


## Main uses the final native header height to keep morning panels below it.
func panel_top() -> float:
	return maxf(112.0, (get_node("Top") as Control).get_global_rect().end.y + 12.0)


## Controls grow to a larger minimum but never shrink back on their own. When
## the groups need fewer rows (a wider window, a hidden chip) the header
## returns to its native height instead of keeping an empty band.
func _fit_header_height() -> void:
	var top: Control = get_node("Top") as Control
	var minimum: float = top.get_combined_minimum_size().y
	if top.size.y > minimum + 0.5:
		top.size = Vector2(top.size.x, minimum)


func _on_header_resized() -> void:
	if not is_inside_tree():
		return
	_layout_build_hints()
	var bottom: float = (get_node("Top") as Control).get_global_rect().end.y
	if not is_equal_approx(bottom, _header_bottom):
		_header_bottom = bottom
		header_layout_changed.emit()


func _on_staff_pressed() -> void:
	if STAFF_PHASES.has(Clock.sim.phase):
		staff_pressed.emit()


func _on_stock_pressed() -> void:
	if Clock.sim.phase == SimClock.Phase.MORNING:
		stock_pressed.emit()


## Main lists today's sold-out dishes by display name; empty hides the tag.
func set_sold_out(names: Array[String]) -> void:
	_sold_out_names = names.duplicate()
	if _sold_out_label == null:
		refresh()
	_render_sold_out()


func _render_sold_out() -> void:
	var count: int = _sold_out_names.size()
	_sold_out_label.text = "Sold out: %s" % _sold_out_names[0] if count == 1 else "Sold out: %d dishes" % count
	_sold_out_label.tooltip_text = "Sold out for the rest of today:\n" + "\n".join(_sold_out_names) \
		+ "\nBuy more in the Stock panel tomorrow morning."
	# A service-time tag: the evening report and the next morning explain it.
	_sold_out_label.visible = count > 0 and (Clock.sim.phase == SimClock.Phase.OPEN
		or Clock.sim.phase == SimClock.Phase.LAST_ORDERS)
	var row: Container = get_node("Top/Row") as Container
	row.update_minimum_size()
	row.queue_sort()


func _on_settings_pressed() -> void:
	settings_pressed.emit()


func _style_header() -> void:
	var roles: Dictionary[String, StringName] = {"Speed0": &"pause", "Speed1": &"speed_1",
		"Speed2": &"speed_2", "Speed4": &"speed_4", "Build": &"build", "Menu": &"menu",
		"Staff": &"staff", "Context": &"open_shop", "Settings": &"settings", "Stock": &"stock"}
	for child: Node in (get_node("Top/Row") as Container).get_children():
		var button: Button = child as Button
		if button == null:
			continue
		if roles.has(String(button.name)):
			var label: String = "Pause" if button == get_node("Top/Row/Speed0") else ("Settings" if button == _settings_button else button.text)
			# Stock is icon-only so the whole header still fits one row at 1600 px.
			IconStyle.configure_button(button, roles[String(button.name)], label, button.tooltip_text,
				IconCatalogue.TOP_BAR_SIZE, button == _settings_button or String(button.name) in ["Speed0", "Stock"])
		IconStyle.compact_button(button)
	IconStyle.decorate_label(_reputation_label, &"reputation", IconCatalogue.TOP_BAR_SIZE)
	# Reuse the warm theme's existing cream, ink and accent for the warning chip.
	var header_theme: Theme = (get_node("Top") as Control).theme
	var chip: StyleBoxFlat = header_theme.get_stylebox("normal", "Button").duplicate() as StyleBoxFlat
	var accent: StyleBoxFlat = header_theme.get_stylebox("pressed", "Button") as StyleBoxFlat
	chip.border_color = accent.bg_color
	chip.set_border_width_all(1)
	chip.set_content_margin(SIDE_LEFT, 8.0)
	chip.set_content_margin(SIDE_RIGHT, 8.0)
	chip.set_content_margin(SIDE_TOP, 4.0)
	chip.set_content_margin(SIDE_BOTTOM, 4.0)
	_loan_label.add_theme_stylebox_override("normal", chip)
	_sold_out_label.add_theme_stylebox_override("normal", chip)
	_day_label.tooltip_text = "Current day"
	_time_label.tooltip_text = "Shop clock"
	_phase_label.tooltip_text = "Today's service phase"
	_cash_label.tooltip_text = "Available cash"
	(get_node("Top/Row/Plates") as Label).tooltip_text = "Clean plates available for service"


## State changes only: a refresh between native down/up preserves the button.
func set_build_state(available: bool, active: bool, reason: String = "", held_state: int = BuildMode.State.IDLE) -> void:
	_build_available = available
	_build_active = active
	_build_reason = reason
	_build_state = held_state
	if _build_button == null:
		refresh()
	else:
		_refresh_build_controls()


func set_paint_state(active: bool) -> void:
	_paint_active = active
	if _paint_button == null:
		refresh()
	else:
		_refresh_build_controls()


func _refresh_build_controls() -> void:
	var allowed: bool = _build_available and (
		Clock.sim.phase == SimClock.Phase.MORNING or Clock.sim.phase == SimClock.Phase.CLOSED)
	if _build_button.disabled == allowed:
		_build_button.disabled = not allowed
	if _build_button.button_pressed != _build_active:
		_build_button.set_pressed_no_signal(_build_active)
	if _paint_button.button_pressed != _paint_active:
		_paint_button.set_pressed_no_signal(_paint_active)
	var tooltip: String = "Build furniture (B)" if allowed else "Build furniture in the morning or after closing"
	if _build_button.tooltip_text != tooltip:
		_build_button.tooltip_text = tooltip
	var resize_hint: bool = _build_hints.visible != (_build_active or _paint_active)
	if resize_hint:
		_build_hints.visible = _build_active or _paint_active
	var text: String = "Click Pick furniture  |  Alt-click Pick rug  |  Esc Exit"
	if _paint_active:
		text = "Choose a colour, hover to preview, click to paint  |  Esc Exit"
	elif _build_state == BuildMode.State.MOVE:
		text = "R Rotate  |  Del Sell  |  Esc Cancel"
	elif _build_state == BuildMode.State.BUY:
		text = "R Rotate  |  Esc Cancel"
	if not _build_reason.is_empty():
		text += "\n" + _build_reason
	if _build_hint_text.text != text:
		_build_hint_text.text = text
		resize_hint = true
	if resize_hint:
		_layout_build_hints()


func _layout_build_hints() -> void:
	_layout_header()
	if _build_hint_text == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600.0, 900.0)
	var padding: Vector2 = _build_hints.get_theme_stylebox("panel").get_minimum_size()
	var header_bottom: float = (get_node("Top") as Control).get_global_rect().end.y
	var top: float = minf(maxf(104.0, header_bottom + 6.0), maxf(12.0, viewport_size.y - 64.0))
	var available: Vector2 = Vector2(minf(520.0, viewport_size.x - 24.0), viewport_size.y - top - 12.0) - padding
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var font: Font = _build_hint_text.get_theme_font("font")
	var font_size: int = _build_hint_text.get_theme_font_size("font_size")
	var natural_width: float = 0.0
	for line: String in _build_hint_text.text.split("\n"):
		natural_width = maxf(natural_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	var width: float = minf(ceilf(natural_width), available.x)
	_build_hint_text.custom_minimum_size = Vector2(width, 0.0)
	_build_hint_text.size.x = width
	# Native Label metrics include theme line spacing and its final wrapping width.
	var text_height: float = _build_hint_text.get_minimum_size().y
	var bar_width: float = _build_hint_scroll.get_v_scroll_bar().get_combined_minimum_size().x if text_height > available.y else 0.0
	width = minf(width, available.x - bar_width)
	_build_hint_text.custom_minimum_size = Vector2(width, 0.0)
	_build_hint_text.size.x = width
	text_height = _build_hint_text.get_minimum_size().y
	_build_hint_scroll.custom_minimum_size = Vector2(width + bar_width, minf(ceilf(text_height), available.y))
	_build_hints.size = _build_hint_scroll.custom_minimum_size + padding
	_build_hints.position = Vector2(12.0, top)


## Main forwards primitive stock counts; the HUD never owns or changes plates.
func set_plate_counts(clean: int, total: int, dirty: int, in_use: int, enabled: bool = true) -> void:
	if _plate_label == null:
		_plate_label = get_node("Top/Row/Plates") as Label
	var text: String = "Plates %d/%d" % [clean, total] if enabled else "Plates: buy a sink"
	if _plate_label.text != text:
		_plate_label.text = text
	_plate_label.tooltip_text = "Clean: %d | Dirty: %d | In use: %d" % [clean, dirty, in_use] if enabled \
		else "Plate limits are off in this shop. Buy a sink to enable plates and washing."


func _on_build_pressed() -> void:
	if _build_available and (Clock.sim.phase == SimClock.Phase.MORNING or Clock.sim.phase == SimClock.Phase.CLOSED):
		build_toggled.emit()


func _on_paint_pressed() -> void:
	paint_toggled.emit()


## Binds this presentation control to the containing shop view, idempotently.
func bind_shop_view(view: ShopView) -> void:
	if is_instance_valid(_shop_view) and _shop_view.wall_mode_changed.is_connected(_on_wall_mode_changed):
		_shop_view.wall_mode_changed.disconnect(_on_wall_mode_changed)
	_shop_view = view
	if is_instance_valid(_shop_view):
		_shop_view.wall_mode_changed.connect(_on_wall_mode_changed)
	refresh()


func _exit_tree() -> void:
	_disconnect_events()


func _notification(what: int) -> void:
	# Removal before SceneTree readiness still needs to release refresh() bindings.
	if what == NOTIFICATION_UNPARENTED:
		_disconnect_events()


func _disconnect_events() -> void:
	if _hint_viewport != null and _hint_viewport.size_changed.is_connected(_layout_build_hints):
		_hint_viewport.size_changed.disconnect(_layout_build_hints)
	_hint_viewport = null
	if EventBus.sim_ticked.is_connected(_on_sim_ticked):
		EventBus.sim_ticked.disconnect(_on_sim_ticked)
	if EventBus.day_phase_changed.is_connected(_on_phase_changed):
		EventBus.day_phase_changed.disconnect(_on_phase_changed)
	if EventBus.speed_changed.is_connected(_on_speed_changed):
		EventBus.speed_changed.disconnect(_on_speed_changed)
	if EventBus.cash_changed.is_connected(_on_cash_changed):
		EventBus.cash_changed.disconnect(_on_cash_changed)


func _set_speed(speed: int) -> void:
	Clock.set_speed(speed)


func _on_speed_changed(speed: int) -> void:
	for index: int in range(_buttons.size()):
		var button: Button = _buttons[index]
		var active: bool = SPEEDS[index] == speed
		button.set_pressed_no_signal(active)


func _on_wall_button_pressed() -> void:
	if is_instance_valid(_shop_view):
		_shop_view.cycle_wall_mode()


func _on_menu_pressed() -> void:
	if Clock.sim.phase == SimClock.Phase.MORNING:
		menu_pressed.emit()


func _on_wall_mode_changed(_mode: int) -> void:
	_refresh_wall_mode()


func _refresh_wall_mode() -> void:
	_wall_button.disabled = not is_instance_valid(_shop_view)
	var names: Array[String] = ["Up", "Cutaway", "Down"]
	_wall_button.text = "Walls: " + names[_shop_view.wall_mode] if is_instance_valid(_shop_view) else "Walls"


func _on_sim_ticked(_tick: int) -> void:
	refresh()


func _on_phase_changed(_day: int, _phase: int) -> void:
	refresh()


func _on_context_pressed() -> void:
	if Clock.sim.phase == SimClock.Phase.MORNING:
		if Clock.sim.start_service():
			Clock.set_speed(_preferences.default_open_speed if _preferences != null else 1)
	elif Clock.sim.phase == SimClock.Phase.CLOSED:
		Clock.sim.next_day()
	refresh()


func _on_cash_changed(new_cash: int, delta: int, _reason: StringName) -> void:
	_cash = new_cash
	_cash_label.text = Fmt.money(new_cash)
	if delta == 0:
		return
	# Several same-sign changes in one frame (the morning restock buys each
	# ingredient separately) show as one total instead of a stack of labels.
	var frame: int = Engine.get_process_frames()
	if is_instance_valid(_merge_label) and _merge_frame == frame and signi(_merge_amount) == signi(delta):
		_merge_amount += delta
		_merge_label.text = _delta_text(_merge_amount)
		return
	var label: Label = Label.new()
	label.text = _delta_text(delta)
	_merge_label = label
	_merge_frame = frame
	_merge_amount = delta
	label.add_theme_color_override("font_color", LOSS_COLOR if delta < 0 else GAIN_COLOR)
	# A cream outline keeps it readable over the dark room background.
	label.add_theme_color_override("font_outline_color", Color("F3E6CC"))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deltas.add_child(label)
	_place_delta(label)
	_animate_delta(label)


func _delta_text(amount: int) -> String:
	return ("−" if amount < 0 else "+") + Fmt.money(absi(amount))


## Start just under the top bar, below the cash, so the change never covers
## the cash figure itself.
func _place_delta(label: Label) -> void:
	var bar_bottom: float = (get_node("Top") as Control).get_global_rect().end.y
	label.position = Vector2(_cash_label.global_position.x, bar_bottom + 4.0)


## Waits one frame so the top bar has its real layout (a change can arrive
## before the first layout pass, e.g. the first morning's stock purchase).
func _animate_delta(label: Label) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(label) or not is_inside_tree():
		return
	_place_delta(label)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 24.0, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(label.queue_free)
