class_name MenuPanel
extends Control
## Request-only view. The session accepts changes, refreshes and saves them.

signal enable_requested(recipe_id: StringName, enabled: bool)
signal price_requested(recipe_id: StringName, price: int)

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const STANDARD_COLOR: Color = Color("3b2a20")
const LOWER_COLOR: Color = Color("38764b")
const HIGHER_COLOR: Color = Color("a83e35")
const LOCKED_COLOR: Color = Color("766b60")
const MORNING_HINT: String = "Menu changes are available in the morning."

var _menu: MenuSettings
var _phase: int = SimClock.Phase.MORNING
var _status: Label
var _empty: Label
var _rows_node: VBoxContainer
var _rows: Dictionary[StringName, Dictionary] = {}
var _needs_rebuild: bool = true


func _ready() -> void:
	refresh()


func bind_menu(model: MenuSettings) -> void:
	if _menu != model:
		if _menu != null and _menu.owner_level_changed.is_connected(_on_owner_level_changed):
			_menu.owner_level_changed.disconnect(_on_owner_level_changed)
		_menu = model
		_needs_rebuild = true
		if _menu != null:
			_menu.owner_level_changed.connect(_on_owner_level_changed)
	refresh()


func set_phase(phase: int) -> void:
	_phase = phase
	refresh()


func refresh() -> void:
	_bind_nodes()
	if _needs_rebuild:
		_rebuild_rows()
	var editable: bool = _phase == SimClock.Phase.MORNING
	_status.text = "Choose dishes and prices for today." if editable else MORNING_HINT
	_empty.visible = _rows.is_empty()
	if _menu == null or not _menu.is_valid():
		return
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
		toggle.disabled = locked or not editable or last_enabled
		toggle.tooltip_text = unlock_hint if locked else (MORNING_HINT if not editable else ("Keep at least one dish on the menu." if last_enabled else "Offer this dish today."))
		minus.disabled = locked or not editable or price <= minimum
		plus.disabled = locked or not editable or price >= maximum
		minus.tooltip_text = unlock_hint if locked else (MORNING_HINT if not editable else "Minimum price: $%d" % minimum)
		plus.tooltip_text = unlock_hint if locked else (MORNING_HINT if not editable else "Maximum price: $%d" % maximum)
		amount.text = "$%d" % price
		standard_label.text = "Standard $%d" % standard
		if standard == 0:
			ratio_label.text = "Free at standard price"
			ratio_label.add_theme_color_override("font_color", STANDARD_COLOR)
		else:
			var ratio: float = float(price) / float(standard)
			ratio_label.text = "%.0f%% of standard" % (ratio * 100.0)
			var color: Color = LOWER_COLOR if price < standard else (HIGHER_COLOR if price > standard else STANDARD_COLOR)
			ratio_label.add_theme_color_override("font_color", color)
		if locked:
			ratio_label.add_theme_color_override("font_color", LOCKED_COLOR)


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


func _rebuild_rows() -> void:
	for child: Node in _rows_node.get_children():
		_rows_node.remove_child(child)
		child.free()
	_rows.clear()
	_needs_rebuild = false
	if _menu == null or not _menu.is_valid():
		return
	var index: int = 0
	for definition: RecipeDef in _menu.recipes():
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "Recipe%d" % index
		row.theme = SHARED_THEME
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows_node.add_child(row)
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
	if enabled != current and (enabled or _menu.enabled_count() > 1):
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
