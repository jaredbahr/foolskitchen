class_name MenuPanel
extends Control
## Request-only view. The session accepts changes, refreshes and saves them.

signal restaurant_name_requested(restaurant_name: String)
signal enable_requested(recipe_id: StringName, enabled: bool)
signal price_requested(recipe_id: StringName, price: int)
signal settings_requested()
signal goals_requested()
## Morning opening-hours request (FK-083); the session checks the limits.
signal hours_requested(open_minute: int, close_minute: int)

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const STANDARD_COLOR: Color = Color("3b2a20")
const LOWER_COLOR: Color = Color("38764b")
const HIGHER_COLOR: Color = Color("a83e35")
const LOCKED_COLOR: Color = Color("766b60")
const SECTION_FONT_SIZE: int = 22
const MORNING_HINT: String = "Menu changes are available in the morning."

var _name_edit: LineEdit
var _name_apply: Button
var _name_feedback: Label
var _menu_count: Label
var _name_dirty: bool = false
var _menu: MenuSettings
var _phase: int = SimClock.Phase.MORNING
var _status: Label
var _empty: Label
var _rows_node: VBoxContainer
var _settings_button: Button
var _goals_button: Button
var _rows: Dictionary[StringName, Dictionary] = {}
var _needs_rebuild: bool = true
## Food rows stay in Rows under their section headings; drinks get the Drinks
## section block below (FK-083).
var _drinks_title: Label
var _drink_rows: VBoxContainer
var _food_hints_box: VBoxContainer
var _hints_box: VBoxContainer
var _drink_hints: Array[String] = []
var _food_hints: Array[String] = []
var _hours_box: VBoxContainer
var _hours_controls: Dictionary[String, Control] = {}
var _open_minute: int = 11 * 60
var _close_minute: int = 21 * 60
var _hours_tuning: OpeningHoursTuning = null


func _ready() -> void:
	refresh()


func bind_menu(model: MenuSettings) -> void:
	if _menu != model:
		if _menu != null and _menu.owner_level_changed.is_connected(_on_owner_level_changed):
			_menu.owner_level_changed.disconnect(_on_owner_level_changed)
		_menu = model
		_name_dirty = false
		if _name_feedback != null:
			_name_feedback.text = ""
			_name_feedback.visible = false
		_needs_rebuild = true
		if _menu != null:
			_menu.owner_level_changed.connect(_on_owner_level_changed)
	refresh()


func set_phase(phase: int) -> void:
	_phase = phase
	refresh()


func refresh() -> void:
	_bind_nodes()
	if _needs_rebuild or _catalogue_changed():
		_rebuild_rows()
	var editable: bool = _phase == SimClock.Phase.MORNING
	_status.text = "Choose dishes, drinks, prices and opening hours for today." if editable else MORNING_HINT
	_empty.visible = _rows.is_empty()
	_name_edit.editable = editable and _menu != null and _menu.is_valid()
	_name_apply.disabled = not _name_edit.editable
	_name_edit.tooltip_text = "Name your restaurant (up to 24 characters)." if editable else MORNING_HINT
	_name_apply.tooltip_text = "Use this restaurant name." if editable else MORNING_HINT
	_refresh_hours(editable)
	_refresh_drinks_section()
	if _menu == null or not _menu.is_valid():
		_menu_count.text = ""
		return
	if not _name_dirty and _name_edit.text != _menu.restaurant_name():
		_name_edit.text = _menu.restaurant_name()
	_menu_count.text = "%d / %d dishes on the menu" % [_menu.enabled_count(), _menu.menu_limit()]
	for definition: RecipeDef in _menu.recipes():
		var row: Dictionary = _rows[definition.id]
		var title: Label = row["title"]
		var unlock: Label = row["unlock"]
		var toggle: Button = row["toggle"]
		var minus: Button = row["minus"]
		var plus: Button = row["plus"]
		var amount: Label = row["amount"]
		var standard_label: Label = row["standard"]
		var ratio_label: Label = row["ratio"]
		var locked: bool = definition.unlock_level > _menu.owner_level()
		var unlock_hint: String = "Unlocks at level %d" % definition.unlock_level
		var enabled: bool = _menu.is_enabled(definition.id)
		var last_enabled: bool = enabled and _menu.enabled_count() == 1
		var at_limit: bool = not enabled and _menu.enabled_count() >= _menu.menu_limit()
		var limit_hint: String = "Your menu is full. Take a dish off before adding another."
		var price: int = _menu.price_of(definition)
		var standard: int = _menu.standard_price(definition.id)
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
		toggle.text = "Locked" if locked else ("On menu" if enabled else "Off menu")
		toggle.disabled = locked or not editable or last_enabled or at_limit
		toggle.tooltip_text = unlock_hint if locked else (MORNING_HINT if not editable else ("Keep at least one dish on the menu." if last_enabled else (limit_hint if at_limit else "Offer this dish today.")))
		minus.disabled = locked or not editable or price <= minimum
		plus.disabled = locked or not editable or price >= maximum
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
		if locked:
			ratio_label.add_theme_color_override("font_color", LOCKED_COLOR)


## A station bought or sold changes which dishes the menu lists (FK-083).
func _catalogue_changed() -> bool:
	if _menu == null or not _menu.is_valid():
		return false
	var recipes: Array[RecipeDef] = _menu.recipes()
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


## Food equipment reasons share the existing named station hints, outside Drinks.
func set_food_hints(hints: Array[String]) -> void:
	_food_hints = hints.duplicate()
	_bind_nodes()
	_rebuild_food_hints()


func _rebuild_food_hints() -> void:
	for child: Node in _food_hints_box.get_children():
		_food_hints_box.remove_child(child)
		child.free()
	for hint: String in _food_hints:
		var label: Label = _add_label(_food_hints_box, "Hint%d" % _food_hints_box.get_child_count(), hint)
		label.add_theme_color_override("font_color", LOCKED_COLOR)
	_food_hints_box.visible = not _food_hints.is_empty()


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
	_drinks_title.visible = _drink_rows.get_child_count() > 0 or not _drink_hints.is_empty()
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
	IconStyle.decorate_label(get_node("Panel/Content/Title") as Label, &"menu")
	_build_sections()
	IconStyle.configure_button(_settings_button, &"settings", "Settings", "Audio, display and controls", IconCatalogue.PANEL_SIZE)
	_settings_button.pressed.connect(_on_settings_pressed)
	_goals_button.pressed.connect(_on_goals_pressed)


## Opening hours above the dishes; Food and Drinks titles around the rows.
func _build_sections() -> void:
	var list: VBoxContainer = _rows_node.get_parent() as VBoxContainer
	_hours_box = VBoxContainer.new()
	_hours_box.name = "Hours"
	_hours_box.theme = SHARED_THEME
	_hours_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(_hours_box)
	# Under the restaurant name (#181), above the dish count and sections.
	list.move_child(_hours_box, _name_feedback.get_index() + 1)
	var heading: Label = _add_label(_hours_box, "Title", "Opening hours")
	heading.add_theme_font_size_override("font_size", 20)
	for side: String in ["open", "close"]:
		var line: HBoxContainer = _add_line(_hours_box, side.capitalize())
		var minus: Button = _add_button(line, "Minus", "−")
		var label: Label = _add_label(line, "Time", "")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var plus: Button = _add_button(line, "Plus", "+")
		var direction: Vector2i = Vector2i(1, 0) if side == "open" else Vector2i(0, 1)
		minus.pressed.connect(_on_hours_step.bind(-direction))
		plus.pressed.connect(_on_hours_step.bind(direction))
		_hours_controls[side] = label
		_hours_controls[side + "_minus"] = minus
		_hours_controls[side + "_plus"] = plus
	var note: Label = _add_label(_hours_box, "Note",
		"Staff are paid for the hours you open. Coffee drinkers come early; evening drinkers come late.")
	note.add_theme_color_override("font_color", LOCKED_COLOR)
	_hours_controls["note"] = note
	_add_separator(_hours_box)
	# Food rows carry their own section headings (Starters, Mains...); every
	# drink is in the Drinks section, whose heading leads the drinks block.
	_food_hints_box = VBoxContainer.new()
	_food_hints_box.name = "FoodHints"
	_food_hints_box.theme = SHARED_THEME
	_food_hints_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(_food_hints_box)
	_drinks_title = _add_label(list, "DrinksTitle", RecipeDef.section_name(RecipeDef.Section.DRINKS))
	_drinks_title.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	_drink_rows = VBoxContainer.new()
	_drink_rows.name = "DrinkRows"
	_drink_rows.theme = SHARED_THEME
	_drink_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(_drink_rows)
	_hints_box = VBoxContainer.new()
	_hints_box.name = "DrinkHints"
	_hints_box.theme = SHARED_THEME
	_hints_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(_hints_box)


func _add_separator(parent: Node) -> void:
	var separator: HSeparator = HSeparator.new()
	separator.theme = SHARED_THEME
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(separator)


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_goals_pressed() -> void:
	goals_requested.emit()


func _rebuild_rows() -> void:
	for container: VBoxContainer in [_rows_node, _drink_rows]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.free()
	_rows.clear()
	_needs_rebuild = false
	if _menu == null or not _menu.is_valid():
		return
	var index: int = 0
	var grouped: Array[RecipeDef] = _menu.recipes()
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
