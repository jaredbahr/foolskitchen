class_name BuildCatalogue
extends Control
## Content-defined furniture requests only. The session/controller owns buying.

signal buy_requested(def_id: StringName)
signal swatch_requested(swatch_id: StringName)

const EDGE_MARGIN: float = 12.0
const MAX_PANEL_WIDTH: float = 760.0
const PANEL_HEIGHT_SHARE: float = 0.42
const CARD_MINIMUM: Vector2 = Vector2(144.0, 80.0)
const THUMBNAIL_WIDTH: int = 56
const CARD_GAP: float = 8.0
const CATEGORY_IDS: Array[StringName] = [&"seating", &"tables", &"kitchen", &"decor"]
const CATEGORY_LABELS: Dictionary = {
	&"seating": "Seating", &"tables": "Tables", &"kitchen": "Kitchen", &"decor": "Decor",
}

var item_buttons: Dictionary[StringName, Button] = {}
var swatch_buttons: Dictionary[StringName, Button] = {}
var category_buttons: Dictionary[StringName, Button] = {}
var selected_category: StringName = &""
var _thumbnails: ItemThumbnailCache
var _fitting: bool = false
var selected_swatch_id: StringName = &"butter"
var _content: ContentDB
var _ordered_ids: Array[StringName] = []
var _layout_ready: bool = false
var _paint_visible: bool = false
var _owner_level: int = 1
## Stable capture path: Panel/Margin/Rows/Scroll/Content/VibeMeter.
var vibe_meter: VibeMeter


func bind_content(content: ContentDB) -> void:
	_prepare_layout()
	_content = content
	refresh_content()


## Main calls this after restoring progress and on each level change.
func set_owner_level(level: int) -> void:
	if level < 1 or level == _owner_level:
		return
	_owner_level = level
	refresh_content()


func set_build_visible(active: bool) -> void:
	if visible != active:
		visible = active


func set_paint_visible(active: bool) -> void:
	_prepare_layout()
	_paint_visible = active
	_refresh_title()
	(get_node("Panel/Margin/Rows/Scroll/Content/Categories") as Control).visible = not active
	(get_node("Panel/Margin/Rows/Scroll/Content/Hint") as Control).visible = not active
	(get_node("Panel/Margin/Rows/Scroll/Content/Items") as Control).visible = not active
	vibe_meter.visible = not active
	(get_node("Panel/Margin/Rows/Scroll/Content/PaintSwatches") as Control).visible = active
	_apply_category()
	_fit_panel()


func set_vibe(result: VibeModel.Result) -> void:
	_prepare_layout()
	vibe_meter.set_vibe(result)
	_fit_panel()


## Filters never replace the native buttons or alter the underlying definitions.
func set_category(category: StringName) -> void:
	if not CATEGORY_IDS.has(category):
		return
	selected_category = category
	_apply_category()
	_fit_panel()


func visible_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in _ordered_ids:
		if item_buttons[id].visible:
			result.append(id)
	return result

func ordered_ids() -> Array[StringName]:
	return _ordered_ids.duplicate()


func _ready() -> void:
	_prepare_layout()
	_fit_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _layout_ready:
		_fit_panel()


## Unchanged definitions retain the same visible/enabled native button, even
## between a real mouse-down and mouse-up. No per-frame rebuild is necessary.
func refresh_content() -> void:
	_prepare_layout()
	var definitions: Array[ItemDef] = []
	if _content != null:
		for definition: ItemDef in _content.items():
			if _buyable(definition):
				definitions.append(definition)
	definitions.sort_custom(_definition_before)
	var desired_ids: Array[StringName] = []
	for definition: ItemDef in definitions:
		desired_ids.append(definition.id)
	var row: GridContainer = get_node("Panel/Margin/Rows/Scroll/Content/Items") as GridContainer
	for id: StringName in item_buttons.keys():
		if not desired_ids.has(id):
			var old_button: Button = item_buttons[id]
			row.remove_child(old_button)
			old_button.free()
			item_buttons.erase(id)
	for index: int in range(definitions.size()):
		var definition: ItemDef = definitions[index]
		var button: Button = item_buttons.get(definition.id) as Button
		if button == null:
			button = Button.new()
			button.name = "Buy_%s" % definition.id
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.theme = theme
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_constant_override("icon_max_width", THUMBNAIL_WIDTH)
			button.add_theme_constant_override("h_separation", 10)
			button.pressed.connect(_on_buy_pressed.bind(definition.id))
			item_buttons[definition.id] = button
			row.add_child(button)
		if button.get_index() != index:
			row.move_child(button, index)
		var label: String = definition.display_name
		var locked: bool = definition.unlock_level > _owner_level
		var text: String = "%s\n$%d" % [label, definition.price]
		var tooltip: String = "Buy %s for $%d" % [label, definition.price]
		if locked:
			text = "%s\nLevel %d" % [label, definition.unlock_level]
			tooltip = "Unlocks at level %d" % definition.unlock_level
		if button.text != text:
			button.text = text
		button.disabled = locked
		button.tooltip_text = tooltip
		_size_card(button)
	_ordered_ids = desired_ids
	if selected_category.is_empty():
		for category: StringName in CATEGORY_IDS:
			for definition: ItemDef in definitions:
				if category_for(definition) == category:
					selected_category = category
					break
			if not selected_category.is_empty():
				break
	_apply_category()
	# Queue the current category first so visible previews arrive first. Every
	# remaining wrapper is still prepared once at startup in the same cache.
	for wanted: bool in [true, false]:
		for definition: ItemDef in definitions:
			if (category_for(definition) == selected_category) == wanted:
				item_buttons[definition.id].icon = _thumbnails.request(definition.view_scene)
	_refresh_swatches()
	_fit_panel()


func _size_card(button: Button) -> void:
	var font: Font = button.get_theme_font("font")
	var font_size: int = button.get_theme_font_size("font_size")
	var text_width: float = 0.0
	for line: String in button.text.split("\n"):
		text_width = maxf(text_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	var padding: Vector2 = Vector2.ZERO
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		padding = padding.max(button.get_theme_stylebox(style_name).get_minimum_size())
	# Reserve the real preview's space before it arrives, retaining click bounds
	# even when a render completes between native mouse-down and mouse-up.
	button.custom_minimum_size = Vector2(
		maxf(CARD_MINIMUM.x, text_width + float(THUMBNAIL_WIDTH) + 10.0 + padding.x),
		maxf(CARD_MINIMUM.y, float(THUMBNAIL_WIDTH) + padding.y))


func _apply_category() -> void:
	for category: StringName in category_buttons:
		category_buttons[category].set_pressed_no_signal(category == selected_category)
	for id: StringName in item_buttons:
		var definition: ItemDef = _content.item(id) if _content != null else null
		item_buttons[id].visible = not _paint_visible and category_for(definition) == selected_category
	var empty: Label = get_node("Panel/Margin/Rows/Scroll/Content/Empty") as Label
	empty.visible = not _paint_visible and visible_ids().is_empty()


func _on_category_pressed(category: StringName) -> void:
	if visible and not _paint_visible:
		set_category(category)


func _on_thumbnail_ready(scene: PackedScene, texture: Texture2D) -> void:
	if _content == null:
		return
	for id: StringName in item_buttons:
		var definition: ItemDef = _content.item(id)
		if definition != null and definition.view_scene == scene:
			item_buttons[id].icon = texture

func _refresh_swatches() -> void:
	var row: HBoxContainer = get_node("Panel/Margin/Rows/Scroll/Content/PaintSwatches") as HBoxContainer
	var definitions: Array[SwatchDef] = []
	if _content != null:
		definitions.assign(_content.swatches())
	var desired: Array[StringName] = []
	for definition: SwatchDef in definitions:
		desired.append(definition.id)
	for id: StringName in swatch_buttons.keys():
		if not desired.has(id):
			var old_button: Button = swatch_buttons[id]
			row.remove_child(old_button)
			old_button.free()
			swatch_buttons.erase(id)
	if definitions.is_empty():
		_refresh_title()
		return
	if _content.swatch(selected_swatch_id) == null:
		selected_swatch_id = definitions[0].id
	for index: int in range(definitions.size()):
		var definition: SwatchDef = definitions[index]
		var button: Button = swatch_buttons.get(definition.id) as Button
		if button == null:
			button = Button.new()
			button.name = "Swatch_%s" % definition.id
			button.custom_minimum_size = Vector2(34.0, 34.0)
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.pressed.connect(_on_swatch_pressed.bind(definition.id))
			row.add_child(button)
			swatch_buttons[definition.id] = button
		if button.get_index() != index:
			row.move_child(button, index)
		button.tooltip_text = definition.display_name
	_refresh_swatch_styles()

func _refresh_swatch_styles() -> void:
	if _content == null:
		return
	var button_outline: StyleBoxFlat = theme.get_stylebox("normal", "Button") as StyleBoxFlat
	var selected_ring: Color = button_outline.border_color if button_outline != null else Color("3b2a20")
	for id: StringName in swatch_buttons:
		var definition: SwatchDef = _content.swatch(id)
		var button: Button = swatch_buttons[id]
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = definition.color
		style.set_corner_radius_all(17)
		style.set_border_width_all(3 if id == selected_swatch_id else 1)
		style.border_color = selected_ring if id == selected_swatch_id else Color("5d4637")
		button.pivot_offset = button.custom_minimum_size * 0.5
		button.scale = Vector2.ONE * (1.1 if id == selected_swatch_id else 1.0)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
	_refresh_title()


func _refresh_title() -> void:
	var title: Label = get_node("Panel/Margin/Rows/Scroll/Content/Title") as Label
	if not _paint_visible:
		title.text = "Furniture"
		IconStyle.decorate_label(title, &"catalogue")
		return
	IconStyle.decorate_label(title, &"paint")
	var selected: SwatchDef = _content.swatch(selected_swatch_id) if _content != null else null
	var name: String = selected.display_name if selected != null else "Pick a colour"
	title.text = "Paint | %s - Click a wall, floor or item" % name


func _on_swatch_pressed(id: StringName) -> void:
	if not visible or _content == null or _content.swatch(id) == null or not _paint_visible:
		return
	selected_swatch_id = id
	_refresh_swatch_styles()
	swatch_requested.emit(id)


func _prepare_layout() -> void:
	if _layout_ready:
		return
	var panel: PanelContainer = get_node("Panel") as PanelContainer
	# Keep the shared palette, borders and corners; compact only its padding.
	var original: StyleBox = theme.get_stylebox("panel", "PanelContainer") \
		if theme != null and theme.has_stylebox("panel", "PanelContainer") else panel.get_theme_stylebox("panel")
	var compact: StyleBox = original.duplicate() as StyleBox
	compact.set_content_margin(SIDE_LEFT, 8.0)
	compact.set_content_margin(SIDE_RIGHT, 8.0)
	compact.set_content_margin(SIDE_TOP, 6.0)
	compact.set_content_margin(SIDE_BOTTOM, 6.0)
	panel.add_theme_stylebox_override("panel", compact)
	var content: Control = get_node("Panel/Margin/Rows/Scroll/Content") as Control
	vibe_meter = VibeMeter.new()
	content.add_child(vibe_meter)
	content.move_child(vibe_meter, 1)
	content.minimum_size_changed.connect(_fit_panel)
	var categories: HBoxContainer = content.get_node("Categories") as HBoxContainer
	for category: StringName in CATEGORY_IDS:
		var button: Button = Button.new()
		button.name = String(category).capitalize()
		button.text = CATEGORY_LABELS[category]
		button.theme = theme
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.pressed.connect(_on_category_pressed.bind(category))
		category_buttons[category] = button
		categories.add_child(button)
	_thumbnails = ItemThumbnailCache.new()
	_thumbnails.name = "ItemThumbnails"
	_thumbnails.thumbnail_ready.connect(_on_thumbnail_ready)
	add_child(_thumbnails)
	_layout_ready = true


## Content-sized when it fits. Scrollbars handle both axes when it does not;
## resizing never hides, disables or replaces an in-flight native button.
func _fit_panel() -> void:
	if not _layout_ready or _fitting:
		return
	var panel: PanelContainer = get_node_or_null("Panel") as PanelContainer
	var scroll: ScrollContainer = get_node_or_null("Panel/Margin/Rows/Scroll") as ScrollContainer
	var content: Control = get_node_or_null("Panel/Margin/Rows/Scroll/Content") as Control
	if panel == null or scroll == null or content == null:
		return
	var padding: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
	var available: Vector2 = size - Vector2.ONE * EDGE_MARGIN * 2.0 - padding
	if available.x <= 0.0 or available.y <= 0.0:
		return
	# Native containers round their fitted rectangles to pixels. Round the outer
	# budget down first so a fractional height cap cannot grow past its bound.
	var panel_budget: Vector2 = Vector2(minf(available.x + padding.x, MAX_PANEL_WIDTH),
		minf(available.y + padding.y, maxf(96.0, size.y * PANEL_HEIGHT_SHARE))).floor()
	var limit: Vector2 = panel_budget - padding
	if limit.x <= 0.0 or limit.y <= 0.0:
		return
	_fitting = true
	var row: GridContainer = content.get_node("Items") as GridContainer
	var card_width: float = CARD_MINIMUM.x
	for id: StringName in item_buttons:
		if item_buttons[id].visible:
			card_width = maxf(card_width, item_buttons[id].get_combined_minimum_size().x)
	var columns: int = clampi(floori((limit.x + CARD_GAP) / (card_width + CARD_GAP)), 1, 3)
	if row.columns != columns:
		row.columns = columns
	var natural: Vector2 = content.get_combined_minimum_size()
	var bar_width: float = scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var bar_height: float = scroll.get_h_scroll_bar().get_combined_minimum_size().y
	var horizontal: bool = false
	var vertical: bool = false
	for _pass: int in range(2):
		horizontal = horizontal or natural.x + (bar_width if vertical else 0.0) > limit.x
		vertical = vertical or natural.y + (bar_height if horizontal else 0.0) > limit.y
	var desired: Vector2 = natural + Vector2(bar_width if vertical else 0.0, bar_height if horizontal else 0.0)
	scroll.custom_minimum_size = Vector2(minf(desired.x, limit.x), minf(desired.y, limit.y))
	panel.size = scroll.custom_minimum_size + padding
	panel.position = Vector2(EDGE_MARGIN, size.y - EDGE_MARGIN - panel.size.y)
	_fitting = false

func _on_buy_pressed(id: StringName) -> void:
	if not visible or _paint_visible or _content == null or not item_buttons.has(id) \
			or (is_inside_tree() and not is_visible_in_tree()):
		return
	var button: Button = item_buttons[id]
	var definition: ItemDef = _content.item(id)
	if button.visible and not button.disabled and _buyable(definition) \
			and category_for(definition) == selected_category and definition.unlock_level <= _owner_level:
		buy_requested.emit(id)

static func _buyable(definition: ItemDef) -> bool:
	return definition != null and definition.catalogue_visible and not definition.id.is_empty() \
		and not definition.display_name.strip_edges().is_empty() and not category_for(definition).is_empty() \
		and definition.price >= 0 and definition.unlock_level >= 1 \
		and definition.footprint.x > 0 and definition.footprint.y > 0


static func category_for(definition: ItemDef) -> StringName:
	if definition == null:
		return &""
	match definition.category:
		ItemDef.Category.CHAIR:
			return &"seating"
		ItemDef.Category.TABLE:
			return &"tables"
		ItemDef.Category.STATION, ItemDef.Category.STORAGE, ItemDef.Category.PASS:
			return &"kitchen"
		ItemDef.Category.DECOR:
			return &"decor"
	return &""


static func _definition_before(first: ItemDef, second: ItemDef) -> bool:
	var first_name: String = first.display_name.to_lower()
	var second_name: String = second.display_name.to_lower()
	if first_name == second_name:
		return String(first.id) < String(second.id)
	return first_name < second_name
