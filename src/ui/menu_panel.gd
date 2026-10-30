class_name MenuPanel
extends Control
## Request-only view. The session accepts changes, refreshes and saves them.

signal restaurant_name_requested(restaurant_name: String)
signal enable_requested(recipe_id: StringName, enabled: bool)
signal price_requested(recipe_id: StringName, price: int)
signal settings_requested()
signal goals_requested()
signal lease_requested()
signal quit_to_title_requested()
## Morning opening-hours request (FK-083); the session checks the limits.
signal hours_requested(open_minute: int, close_minute: int)

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const STANDARD_COLOR: Color = Color("3b2a20")
const LOWER_COLOR: Color = Color("38764b")
const HIGHER_COLOR: Color = Color("a83e35")
const LOCKED_COLOR: Color = Color("766b60")
## Same amber as the HUD restock advice, without importing its autoload adapter.
const ADVICE_COLOR: Color = Color("7F5100")
const SECTION_FONT_SIZE: int = 22
const MORNING_HINT: String = "Menu changes are available in the morning."
## Widest panel; narrower windows (or a large UI scale) keep a margin each side.
const PANEL_MAX_WIDTH: float = 1000.0
const PANEL_SIDE_MARGIN: float = 12.0

var _catalogue: Array[RecipeDef] = []
var _details: Dictionary[StringName, Dictionary] = {}
var _selected_recipe: StringName = &""
var _recipe_tree: Tree
var _tree_items: Dictionary[StringName, TreeItem] = {}
var _detail_heading: Label
var _quality_label: Label
var _requirements_box: VBoxContainer
var _name_edit: LineEdit
var _name_apply: Button
var _name_feedback: Label
var _menu_count: Label
var _name_dirty: bool = false
var _menu: MenuSettings
var _phase: int = SimClock.Phase.MORNING
var _weather_kind: int = WeatherState.Kind.SUNNY
var _forecast_rendered_kind: int = -1
var _status: Label
var _empty: Label
var _rows_node: VBoxContainer
## The name and hours sit above two columns. Left: the unlock tree and the
## Drinks hints. Right: the selected dish's detail, always beside the tree.
var _list: VBoxContainer
var _detail: VBoxContainer
var _settings_button: Button
var _goals_button: Button
var _rows: Dictionary[StringName, Dictionary] = {}
var _needs_rebuild: bool = true
## Food rows stay in Rows; drink rows are in DrinkRows (FK-083). Both sit in
## the detail column and only the selected dish's row shows.
var _drinks_title: Label
var _drink_rows: VBoxContainer
var _hints_box: VBoxContainer
var _drink_hints: Array[String] = []
var _hours_box: HBoxContainer
var _hours_controls: Dictionary[String, Control] = {}
var _open_minute: int = 11 * 60
var _close_minute: int = 21 * 60
var _hours_tuning: OpeningHoursTuning = null


func _ready() -> void:
	refresh()
	_fit_width()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_width()


## Up to PANEL_MAX_WIDTH wide, centred, never past the screen edges.
func _fit_width() -> void:
	var panel: Control = get_node_or_null("Panel") as Control
	if panel == null:
		return
	var half: float = minf(PANEL_MAX_WIDTH, maxf(size.x - 2.0 * PANEL_SIDE_MARGIN, 0.0)) / 2.0
	panel.offset_left = -half
	panel.offset_right = half


func bind_menu(model: MenuSettings) -> void:
	if _menu != model:
		if _menu != null and _menu.owner_level_changed.is_connected(_on_owner_level_changed):
			_menu.owner_level_changed.disconnect(_on_owner_level_changed)
		_menu = model
		_catalogue.clear()
		_details.clear()
		_selected_recipe = &""
		_name_dirty = false
		if _name_feedback != null:
			_name_feedback.text = ""
			_name_feedback.visible = false
		_needs_rebuild = true
		if _menu != null:
			_menu.owner_level_changed.connect(_on_owner_level_changed)
	refresh()


## Request-only morning lease offer, with restock advice directly below cost.
func set_lease_offer(offered: bool, cost: String, warning: String, refusal: String) -> void:
	var box: VBoxContainer = get_node("Panel/Content/LeaseOffer")
	box.visible = offered
	(box.get_node("Cost") as Label).text = cost
	var advice: Label = box.get_node("Warning")
	advice.text = warning
	advice.visible = not warning.is_empty()
	advice.add_theme_color_override("font_color", ADVICE_COLOR)
	var reason: Label = box.get_node("Refusal")
	reason.text = refusal
	reason.visible = not refusal.is_empty()
	var button: Button = box.get_node("Accept")
	button.disabled = not refusal.is_empty()
	if not button.pressed.is_connected(_on_lease_pressed):
		button.pressed.connect(_on_lease_pressed)


func _on_lease_pressed() -> void:
	if _phase == SimClock.Phase.MORNING:
		lease_requested.emit()


func set_weather(kind: int) -> void:
	_weather_kind = kind
	_refresh_forecast()


func _refresh_forecast() -> void:
	var forecast: Label = get_node("Panel/Content/WeatherForecast") as Label
	forecast.visible = _phase == SimClock.Phase.MORNING
	if _forecast_rendered_kind != _weather_kind:
		_forecast_rendered_kind = _weather_kind
		forecast.text = WeatherText.forecast_for(_weather_kind)
		IconStyle.decorate_label(forecast, WeatherText.icon_for(_weather_kind), IconCatalogue.PANEL_SIZE)


func set_phase(phase: int) -> void:
	_phase = phase
	if phase != SimClock.Phase.MORNING:
		get_node("Panel/Content/LeaseOffer").hide()
	refresh()


func refresh() -> void:
	_bind_nodes()
	_refresh_forecast()
	if _needs_rebuild or _catalogue_changed():
		_rebuild_rows()
	var editable: bool = _phase == SimClock.Phase.MORNING
	# Only outside the morning: the controls themselves say what to choose.
	_status.text = MORNING_HINT
	_status.visible = not editable
	_empty.visible = _rows.is_empty()
	_name_edit.editable = editable and _menu != null and _menu.is_valid()
	_name_apply.disabled = not _name_edit.editable
	_name_edit.tooltip_text = "Name your restaurant (up to 24 characters)." if editable else MORNING_HINT
	_name_apply.tooltip_text = "Use this restaurant name." if editable else MORNING_HINT
	_refresh_hours(editable)
	_refresh_drinks_section()
	if _menu == null or not _menu.is_valid():
		_menu_count.text = ""
		_refresh_selection()
		return
	if not _name_dirty and _name_edit.text != _menu.restaurant_name():
		_name_edit.text = _menu.restaurant_name()
	_menu_count.text = "%d / %d dishes on the menu" % [_menu.enabled_count(), _menu.menu_limit()]
	for definition: RecipeDef in _display_recipes():
		var row: Dictionary = _rows[definition.id]
		var title: Label = row["title"]
		var unlock: Label = row["unlock"]
		var toggle: Button = row["toggle"]
		var minus: Button = row["minus"]
		var plus: Button = row["plus"]
		var amount: Label = row["amount"]
		var standard_label: Label = row["standard"]
		var ratio_label: Label = row["ratio"]
		var available: bool = _menu.recipe(definition.id) != null
		var locked: bool = definition.unlock_level > _menu.owner_level()
		var unlock_hint: String = "Unlocks at level %d" % definition.unlock_level
		var enabled: bool = _menu.is_enabled(definition.id)
		var last_enabled: bool = enabled and _menu.enabled_count() == 1
		var at_limit: bool = not enabled and _menu.enabled_count() >= _menu.menu_limit()
		var limit_hint: String = "Your menu is full. Take a dish off before adding another."
		var price: int = _menu.shown_price(definition)
		var standard: int = definition.standard_price
		var minimum: int = _menu.minimum_price(definition.id)
		var maximum: int = _menu.maximum_price(definition.id)
		unlock.visible = locked
		unlock.text = unlock_hint if locked else ""
		for label: Label in [title, amount, standard_label]:
			if locked:
				label.add_theme_color_override("font_color", LOCKED_COLOR)
			else:
				label.remove_theme_color_override("font_color")
		toggle.set_pressed_no_signal(enabled)
		toggle.text = "Locked" if locked else ("Remove from menu" if enabled else "Add to menu")
		toggle.disabled = locked or not available or not editable or last_enabled or at_limit
		toggle.tooltip_text = unlock_hint if locked else (MORNING_HINT if not editable else ("Keep at least one dish on the menu." if last_enabled else (limit_hint if at_limit else "Offer this dish today.")))
		minus.disabled = locked or not available or not editable or price <= minimum
		plus.disabled = locked or not available or not editable or price >= maximum
		minus.tooltip_text = unlock_hint if locked else (MORNING_HINT if not editable else "Minimum price: $%d" % minimum)
		plus.tooltip_text = unlock_hint if locked else (MORNING_HINT if not editable else "Maximum price: $%d" % maximum)
		amount.text = "$%d" % price
		standard_label.text = "Suggested $%d" % standard
		if standard == 0:
			ratio_label.text = "Free at suggested price"
			ratio_label.add_theme_color_override("font_color", STANDARD_COLOR)
		else:
			var ratio: float = float(price) / float(standard)
			ratio_label.text = "%.0f%% of suggested" % (ratio * 100.0)
			var color: Color = LOWER_COLOR if price < standard else (HIGHER_COLOR if price > standard else STANDARD_COLOR)
			ratio_label.add_theme_color_override("font_color", color)
		if not available and not locked:
			for button: Button in [toggle, minus, plus]:
				button.tooltip_text = _equipment_reason(definition.id)
		if locked:
			ratio_label.add_theme_color_override("font_color", LOCKED_COLOR)
	_refresh_tree_state()
	_refresh_selection()


## A station bought or sold changes which dishes the menu lists (FK-083).
func _catalogue_changed() -> bool:
	if _menu == null or not _menu.is_valid():
		return false
	var recipes: Array[RecipeDef] = _display_recipes()
	if recipes.size() != _rows.size():
		return true
	for definition: RecipeDef in recipes:
		if not _rows.has(definition.id):
			return true
	return false


## Station hints for drinks the shop cannot make yet, as player sentences.
func set_drink_hints(hints: Array[String]) -> void:
	_drink_hints = hints.duplicate()
	_bind_nodes()
	_rebuild_hints()
	_refresh_drinks_section()


func set_hours(open_minute: int, close_minute: int, tuning: OpeningHoursTuning) -> void:
	_open_minute = open_minute
	_close_minute = close_minute
	_hours_tuning = tuning
	_bind_nodes()
	_refresh_hours(_phase == SimClock.Phase.MORNING)


## Read-only access for tests and captures.
func hours_control(name: String) -> Control:
	_bind_nodes()
	return _hours_controls.get(name) as Control


func drinks_section() -> VBoxContainer:
	_bind_nodes()
	return _drink_rows


func _refresh_hours(editable: bool) -> void:
	if _hours_box == null:
		return
	(_hours_controls["open"] as Label).text = "Opens %s" % _clock_text(_open_minute)
	(_hours_controls["close"] as Label).text = "Closes %s" % _clock_text(_close_minute)
	var steps: Dictionary[String, Vector2i] = {
		"open_minus": Vector2i(-1, 0), "open_plus": Vector2i(1, 0),
		"close_minus": Vector2i(0, -1), "close_plus": Vector2i(0, 1)}
	for key: String in steps:
		var button: Button = _hours_controls[key] as Button
		var next: Vector2i = _hours_step(steps[key])
		var allowed: bool = _hours_tuning != null and OpeningHours.allowed(next.x, next.y, _hours_tuning)
		button.disabled = not editable or not allowed
		button.tooltip_text = MORNING_HINT if not editable else ("" if allowed else _hours_limit_text())


## Midnight as a closing time reads 24:00, not 00:00.
static func _clock_text(minute: int) -> String:
	return "24:00" if minute == 24 * 60 else Fmt.clock(minute)


func _hours_step(direction: Vector2i) -> Vector2i:
	var step: int = _hours_tuning.step_minutes if _hours_tuning != null else 30
	return Vector2i(_open_minute + direction.x * step, _close_minute + direction.y * step)


func _hours_limit_text() -> String:
	if _hours_tuning == null:
		return ""
	return "Open between %s and %s, for %s to %s hours." % [_clock_text(_hours_tuning.earliest_open_minute),
		_clock_text(_hours_tuning.latest_close_minute), str(floori(_hours_tuning.min_open_minutes / 60.0)),
		str(floori(_hours_tuning.max_open_minutes / 60.0))]


func _on_hours_step(direction: Vector2i) -> void:
	if _phase != SimClock.Phase.MORNING or _hours_tuning == null:
		return
	var next: Vector2i = _hours_step(direction)
	if OpeningHours.allowed(next.x, next.y, _hours_tuning):
		hours_requested.emit(next.x, next.y)
	_refresh_hours(_phase == SimClock.Phase.MORNING)


func _refresh_drinks_section() -> void:
	if _drink_rows == null:
		return
	_drinks_title.visible = not _drink_hints.is_empty()
	_hints_box.visible = not _drink_hints.is_empty()


func _rebuild_hints() -> void:
	for child: Node in _hints_box.get_children():
		_hints_box.remove_child(child)
		child.free()
	for hint: String in _drink_hints:
		var label: Label = _add_label(_hints_box, "Hint%d" % _hints_box.get_child_count(), hint)
		label.add_theme_color_override("font_color", LOCKED_COLOR)


## Read-only access to generated controls for session tests and captures.
func row_for(recipe_id: StringName) -> Control:
	var row: Dictionary = _rows.get(recipe_id, {})
	return row.get("root") as Control


func _on_owner_level_changed(_level: int) -> void:
	refresh()


func _bind_nodes() -> void:
	if _rows_node != null:
		return
	_status = %Status
	_empty = %Empty
	_rows_node = %Rows
	_list = get_node("Panel/Content/Body/Scroll/Pad/List") as VBoxContainer
	_detail = get_node("Panel/Content/Body/DetailScroll/Pad/Detail") as VBoxContainer
	_name_edit = %RestaurantName
	_name_apply = %ApplyName
	_name_feedback = %NameFeedback
	_menu_count = %MenuCount
	_name_edit.max_length = MenuSettings.MAX_NAME_LENGTH
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_apply.pressed.connect(_on_name_apply_pressed)
	_settings_button = %SettingsButton
	_goals_button = %GoalsButton
	IconStyle.decorate_label(get_node("Panel/Content/Header/Title") as Label, &"menu")
	_build_sections()
	_build_recipe_tree()
	IconStyle.configure_button(_settings_button, &"settings", "Settings", "Audio, display and controls", IconCatalogue.PANEL_SIZE)
	_settings_button.pressed.connect(_on_settings_pressed)
	var quit_button: Button = %QuitToTitleButton
	quit_button.text = TitleText.QUIT_TO_TITLE
	quit_button.pressed.connect(_on_quit_to_title_pressed)
	_goals_button.pressed.connect(_on_goals_pressed)


## Opening hours with the restaurant name (#181), above both columns, and the
## wage note under them; the Drinks hints close the left column under their
## own heading, apart from the dish detail.
func _build_sections() -> void:
	var list: VBoxContainer = _list
	var identity: VBoxContainer = _name_feedback.get_parent() as VBoxContainer
	# Name [Apply name]   [−] Opens 11:00 [+]  [−] Closes 21:00 [+]
	_hours_box = _add_line(_name_edit.get_parent(), "Hours")
	_hours_box.add_theme_constant_override("separation", 4)
	for side: String in ["open", "close"]:
		var minus: Button = _add_button(_hours_box, side.capitalize() + "Minus", "−")
		minus.custom_minimum_size.x = 40.0
		var label: Label = _add_label(_hours_box, side.capitalize() + "Time", "")
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 118.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var plus: Button = _add_button(_hours_box, side.capitalize() + "Plus", "+")
		plus.custom_minimum_size.x = 40.0
		var direction: Vector2i = Vector2i(1, 0) if side == "open" else Vector2i(0, 1)
		minus.pressed.connect(_on_hours_step.bind(-direction))
		plus.pressed.connect(_on_hours_step.bind(direction))
		_hours_controls[side] = label
		_hours_controls[side + "_minus"] = minus
		_hours_controls[side + "_plus"] = plus
	var note: Label = _add_label(identity, "HoursNote",
		"Staff are paid for the hours you open. Coffee drinkers come early; evening drinkers come late.")
	note.add_theme_color_override("font_color", LOCKED_COLOR)
	identity.move_child(note, _name_feedback.get_index())
	_hours_controls["note"] = note
	_add_separator(identity)
	_drinks_title = _add_label(list, "DrinksTitle", "Drinks")
	_drinks_title.add_theme_font_size_override("font_size", 20)
	_hints_box = VBoxContainer.new()
	_hints_box.name = "DrinkHints"
	_hints_box.theme = SHARED_THEME
	_hints_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(_hints_box)
	_drink_rows = VBoxContainer.new()
	_drink_rows.name = "DrinkRows"
	_drink_rows.theme = SHARED_THEME
	_drink_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(_drink_rows)
	_detail.move_child(_drink_rows, _rows_node.get_index() + 1)


func _add_separator(parent: Node) -> void:
	var separator: HSeparator = HSeparator.new()
	separator.theme = SHARED_THEME
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(separator)


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_quit_to_title_pressed() -> void:
	quit_to_title_requested.emit()


func _on_goals_pressed() -> void:
	goals_requested.emit()


func _rebuild_rows() -> void:
	for container: VBoxContainer in [_rows_node, _drink_rows]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.free()
	_rows.clear()
	_recipe_tree.clear()
	_tree_items.clear()
	_needs_rebuild = false
	if _menu == null or not _menu.is_valid():
		return
	var index: int = 0
	var grouped: Array[RecipeDef] = _display_recipes()
	grouped.sort_custom(_section_before)
	var previous_section: int = -1
	for definition: RecipeDef in grouped:
		var section: int = definition.menu_section()
		if section != previous_section and not definition.is_drink():
			var heading: Label = _add_label(_rows_node, "Section%d" % section, RecipeDef.section_name(section))
			heading.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
			heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		previous_section = section
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "Recipe%d" % index
		row.theme = SHARED_THEME
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(_drink_rows if definition.is_drink() else _rows_node).add_child(row)
		var top: HBoxContainer = _add_line(row, "Top")
		var title: Label = _add_label(top, "Name", definition.display_name)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var toggle: Button = _add_button(top, "Enabled", "On menu")
		toggle.toggle_mode = true
		toggle.toggled.connect(_on_enable_toggled.bind(definition.id))
		var unlock: Label = _add_label(row, "Unlock", "")
		unlock.visible = false
		unlock.add_theme_color_override("font_color", LOCKED_COLOR)
		var price_line: HBoxContainer = _add_line(row, "Price")
		var minus: Button = _add_button(price_line, "Minus", "−")
		minus.pressed.connect(_on_price_step.bind(definition.id, -1))
		var amount: Label = _add_label(price_line, "Amount", "")
		amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var plus: Button = _add_button(price_line, "Plus", "+")
		plus.pressed.connect(_on_price_step.bind(definition.id, 1))
		var reference: HBoxContainer = _add_line(row, "Reference")
		var standard: Label = _add_label(reference, "Standard", "")
		standard.custom_minimum_size.x = 150.0
		var ratio: Label = _add_label(reference, "Ratio", "")
		ratio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ratio.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var separator: HSeparator = HSeparator.new()
		separator.theme = SHARED_THEME
		separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(separator)
		_rows[definition.id] = {"root": row, "title": title, "unlock": unlock,
			"toggle": toggle, "minus": minus,
			"plus": plus, "amount": amount, "standard": standard, "ratio": ratio}
		index += 1
	_rebuild_recipe_tree()
	if not _rows.has(_selected_recipe):
		var definitions: Array[RecipeDef] = _display_recipes()
		_selected_recipe = definitions[0].id if not definitions.is_empty() else &""
	if _tree_items.has(_selected_recipe):
		_recipe_tree.set_block_signals(true)
		_tree_items[_selected_recipe].select(0)
		_recipe_tree.set_block_signals(false)


func _add_line(parent: Node, title: String) -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.name = title
	line.theme = SHARED_THEME
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return line


func _add_label(parent: Node, title: String, text: String) -> Label:
	var label: Label = Label.new()
	label.name = title
	label.text = text
	label.theme = SHARED_THEME
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _add_button(parent: Node, title: String, text: String) -> Button:
	var button: Button = Button.new()
	button.name = title
	button.text = text
	button.theme = SHARED_THEME
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size.x = 52.0
	parent.add_child(button)
	return button


func _on_enable_toggled(enabled: bool, recipe_id: StringName) -> void:
	var definition: RecipeDef = _menu.recipe(recipe_id) if _menu != null else null
	if _phase != SimClock.Phase.MORNING or definition == null \
			or definition.unlock_level > _menu.owner_level():
		refresh()
		return
	var current: bool = _menu.is_enabled(recipe_id)
	if enabled != current and ((enabled and _menu.enabled_count() < _menu.menu_limit()) or (not enabled and _menu.enabled_count() > 1)):
		enable_requested.emit(recipe_id, enabled)
	# Restore committed state even when the session rejects or ignores a request.
	refresh()


func _on_price_step(recipe_id: StringName, direction: int) -> void:
	if _phase != SimClock.Phase.MORNING or _menu == null or (direction != -1 and direction != 1):
		return
	var definition: RecipeDef = _menu.recipe(recipe_id)
	if definition == null or definition.unlock_level > _menu.owner_level():
		return
	var price: int = _menu.price_of(definition)
	# Check bounds before +/- 1: the upper bound can be the largest int64.
	if direction > 0:
		if price >= _menu.maximum_price(recipe_id):
			return
		price += 1
	else:
		if price <= _menu.minimum_price(recipe_id):
			return
		price -= 1
	price_requested.emit(recipe_id, price)
	refresh()


static func _section_before(first: RecipeDef, second: RecipeDef) -> bool:
	if first.menu_section() != second.menu_section():
		return first.menu_section() < second.menu_section()
	return String(first.id) < String(second.id)


func _on_name_changed(_text: String) -> void:
	_name_dirty = true
	_name_feedback.text = ""
	_name_feedback.visible = false


func _on_name_submitted(_text: String) -> void:
	_on_name_apply_pressed()


func _on_name_apply_pressed() -> void:
	if _phase != SimClock.Phase.MORNING or _menu == null or not _menu.is_valid():
		_name_feedback.text = MORNING_HINT
		_name_feedback.visible = true
		return
	var canonical: String = MenuSettings.normalized_restaurant_name(_name_edit.text)
	if canonical.is_empty():
		_name_feedback.text = "Use 1–24 characters without line breaks or control characters."
		_name_feedback.visible = true
		return
	_name_feedback.text = ""
	_name_feedback.visible = false
	restaurant_name_requested.emit(canonical)
	# The session may accept synchronously. Ignored requests retain the draft.
	if _menu.restaurant_name() == canonical:
		_name_dirty = false
		if _name_edit.text != canonical:
			_name_edit.text = canonical


## All definitions are visible in the tree; MenuSettings remains the authority
## for which ones the shop can offer and for every accepted price/toggle.
func set_recipe_details(definitions: Array[RecipeDef], details: Dictionary[StringName, Dictionary]) -> void:
	_catalogue = definitions.duplicate()
	_details = details.duplicate(true)
	refresh()


func _display_recipes() -> Array[RecipeDef]:
	return _catalogue.duplicate() if not _catalogue.is_empty() else (_menu.recipes() if _menu != null else [] as Array[RecipeDef])


func select_recipe(id: StringName) -> bool:
	if not _rows.has(id):
		return false
	_selected_recipe = id
	if _tree_items.has(id):
		_recipe_tree.set_block_signals(true)
		var ancestor: TreeItem = _tree_items[id].get_parent()
		while ancestor != null:
			ancestor.collapsed = false
			ancestor = ancestor.get_parent()
		_tree_items[id].select(0)
		_recipe_tree.set_block_signals(false)
	_refresh_selection()
	return true


func tree_item_for(id: StringName) -> TreeItem:
	return _tree_items.get(id) as TreeItem


func _on_recipe_selected() -> void:
	var selected: TreeItem = _recipe_tree.get_selected()
	if selected != null and selected.get_metadata(0) != null:
		select_recipe(StringName(selected.get_metadata(0)))


func _build_recipe_tree() -> void:
	_recipe_tree = Tree.new()
	_recipe_tree.name = "RecipeTree"
	_recipe_tree.theme = SHARED_THEME
	_recipe_tree.columns = 2
	_recipe_tree.column_titles_visible = false
	_recipe_tree.set_column_expand_ratio(0, 4)
	_recipe_tree.set_column_expand_ratio(1, 5)
	_recipe_tree.set_column_clip_content(1, true)
	_recipe_tree.hide_root = true
	_recipe_tree.select_mode = Tree.SELECT_ROW
	_recipe_tree.tooltip_text = "Dishes unlock as the owner levels up. Select one to see its detail."
	# Sized to its rows inside the column's scroll: no nested scroll, and the
	# wheel passes through to the column.
	_recipe_tree.scroll_horizontal_enabled = false
	_recipe_tree.scroll_vertical_enabled = false
	_recipe_tree.item_selected.connect(_on_recipe_selected)
	_list.add_child(_recipe_tree)
	_list.move_child(_recipe_tree, _empty.get_index() + 1)
	_detail_heading = _add_label(_detail, "DishDetail", "Dish detail")
	_detail_heading.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_detail.move_child(_detail_heading, 0)
	_quality_label = _add_label(_detail, "DishQuality", "")
	_detail.move_child(_quality_label, 1)
	_requirements_box = VBoxContainer.new()
	_requirements_box.name = "Requirements"
	_requirements_box.theme = SHARED_THEME
	_requirements_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(_requirements_box)


func _rebuild_recipe_tree() -> void:
	_recipe_tree.clear()
	_tree_items.clear()
	var root: TreeItem = _recipe_tree.create_item()
	var sections: Dictionary[int, TreeItem] = {}
	var remaining: Array[RecipeDef] = _display_recipes()
	remaining.sort_custom(_section_before)
	while not remaining.is_empty():
		var advanced: bool = false
		for recipe: RecipeDef in remaining.duplicate():
			var parent: TreeItem = _tree_items.get(recipe.unlock_from) as TreeItem
			if not recipe.unlock_from.is_empty() and parent == null:
				continue
			if parent == null:
				var section: int = recipe.menu_section()
				if not sections.has(section):
					var heading: TreeItem = _recipe_tree.create_item(root)
					heading.set_text(0, RecipeDef.section_name(section))
					heading.set_selectable(0, false)
					heading.set_selectable(1, false)
					sections[section] = heading
				parent = sections[section]
			_add_recipe_node(recipe, parent)
			remaining.erase(recipe)
			advanced = true
		if not advanced:
			# Production data is validated. In-memory view fixtures still fail
			# safely rather than looping on a missing or cyclic parent.
			for recipe: RecipeDef in remaining:
				_add_recipe_node(recipe, root)
			break


func _add_recipe_node(recipe: RecipeDef, parent: TreeItem) -> void:
	var node: TreeItem = _recipe_tree.create_item(parent)
	node.set_text(0, recipe.display_name)
	node.set_metadata(0, recipe.id)
	node.custom_minimum_height = 30
	_tree_items[recipe.id] = node


func _refresh_tree_state() -> void:
	if _menu == null or not _menu.is_valid():
		return
	for recipe: RecipeDef in _display_recipes():
		var node: TreeItem = _tree_items.get(recipe.id) as TreeItem
		if node == null:
			continue
		var locked: bool = recipe.unlock_level > _menu.owner_level()
		# Off the catalogue, or listed but with equipment staff can't use
		# (a walled-in fridge): either way the tree shows the red reason.
		var missing: bool = _menu.recipe(recipe.id) == null or _equipment_unmet(recipe.id)
		var state: String = _equipment_reason(recipe.id) if missing \
				else ("On menu" if _menu.is_enabled(recipe.id) else "Off menu")
		# The column is narrow: "Can't reach the fryer"; the tooltip names staff.
		var status: String = state.replace("Staff can't reach", "Can't reach")
		var tooltip: String = state + "."
		if locked:
			status = "Lv %d" % recipe.unlock_level + (", " + status.to_lower() if missing else "")
			tooltip = "Unlocks at owner level %d." % recipe.unlock_level + (" " + state + "." if missing else "")
		node.set_text(1, status)
		node.set_tooltip_text(1, tooltip)
		node.set_custom_color(0, LOCKED_COLOR if locked else STANDARD_COLOR)
		node.set_custom_color(1, HIGHER_COLOR if missing else (LOCKED_COLOR if locked or not _menu.is_enabled(recipe.id) else LOWER_COLOR))


func _equipment_unmet(id: StringName) -> bool:
	var details: Dictionary = _details.get(id, {})
	for row: Dictionary in details.get("equipment", []):
		if not bool(row.get("met", false)):
			return true
	return false


func _equipment_reason(id: StringName) -> String:
	var details: Dictionary = _details.get(id, {})
	for row: Dictionary in details.get("equipment", []):
		if not bool(row.get("met", false)):
			return row.get("text", "Equipment needed")
	return "Equipment needed"


func _refresh_selection() -> void:
	var chosen: RecipeDef = null
	for recipe: RecipeDef in _display_recipes():
		if recipe.id == _selected_recipe:
			chosen = recipe
	for id: StringName in _rows:
		(_rows[id]["root"] as Control).visible = id == _selected_recipe
		(_rows[id]["title"] as Label).visible = false # The detail heading names the dish.
	for child: Node in _rows_node.get_children():
		if child is Label:
			(child as Label).visible = false # Section headings now live in the tree.
	_detail_heading.visible = chosen != null
	_quality_label.visible = chosen != null
	_requirements_box.visible = chosen != null
	for child: Node in _requirements_box.get_children():
		_requirements_box.remove_child(child)
		child.free()
	if chosen == null:
		return
	_detail_heading.text = "%s - %s" % [chosen.display_name, RecipeDef.section_name(chosen.menu_section())]
	var details: Dictionary = _details.get(chosen.id, {})
	var quality: float = float(details.get("quality", chosen.base_quality))
	_quality_label.text = "Quality: %d / 5 stars\n%s" % [RecipeDef.quality_stars(quality),
		details.get("quality_source", "Recipe base quality; no served-dish sample")]
	if details.has("reviews"):
		_quality_label.text += "\n" + String(details["reviews"])
	if details.has("quality_breakdown"):
		_quality_label.text += "\nExpected with today's best worker and station:\n" + String(details["quality_breakdown"])
	# Until its equipment is in, a dish's ingredients are not the problem:
	# they read greyed out rather than red.
	var equipment_met: bool = true
	for row: Dictionary in details.get("equipment", []):
		equipment_met = equipment_met and bool(row.get("met", false))
	for group: String in ["equipment", "ingredients", "other"]:
		var heading: Label = _add_label(_requirements_box, group.capitalize(), group.capitalize())
		heading.add_theme_font_size_override("font_size", 20)
		var requirements: Array = details.get(group, [])
		if requirements.is_empty():
			_add_label(_requirements_box, group + "Empty", "No additional requirements" if group == "other" else "Information unavailable")
		for index: int in requirements.size():
			var row: Dictionary = requirements[index]
			var label: Label = _add_label(_requirements_box, "%s%d" % [group, index], String(row.get("text", "")))
			var color: Color = STANDARD_COLOR if bool(row.get("met", false)) else HIGHER_COLOR
			if group == "ingredients" and not equipment_met:
				color = LOCKED_COLOR
			label.add_theme_color_override("font_color", color)
