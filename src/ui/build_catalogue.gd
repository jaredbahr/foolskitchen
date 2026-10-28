class_name BuildCatalogue
extends Control
## The Sims-style Build and Buy panel (FK-085). Buy lists furniture by room,
## with sub-tabs, theme filters and a price sort, as tiles (picture, price
## under it) with a hover card. Build holds the structure tools: walls,
## floor and paint. Requests only: the session/controller owns every edit.

signal buy_requested(def_id: StringName)
signal swatch_requested(swatch_id: StringName)
## Walls tool (FK-070): the SimGrid.Segment new edges should get.
signal wall_tool_requested(segment: int)
## Floor tool (FK-080): buy floor on the lot.
signal floor_tool_requested()
## Rooms tool (FK-101): paint a room type (SimGrid.Room) onto the floor.
signal rooms_tool_requested(kind: int)
## FK-085: the Build/Buy tabs, the Paint tab, the tools and undo/redo.
signal mode_requested(mode: StringName)
signal paint_requested()
signal tool_requested(tool: int)
signal undo_requested()
signal redo_requested()

const EDGE_MARGIN: float = 12.0
const MAX_PANEL_WIDTH: float = 980.0
const PANEL_HEIGHT_SHARE: float = 0.45
## A catalogue tile: the picture on top, the price (or unlock level) under it.
const CARD_MINIMUM: Vector2 = Vector2(96.0, 104.0)
const THUMBNAIL_WIDTH: int = 64
const CARD_GAP: float = 8.0
const MAX_COLUMNS: int = 12
const MIN_COLUMNS: int = 6
const BUY: StringName = &"buy"
const BUILD: StringName = &"build"
const BUY_CATEGORIES: Array[StringName] = [&"dining", &"kitchen", &"bar_cafe", &"decor", &"lighting", &"restroom"]
const BUILD_CATEGORIES: Array[StringName] = [&"walls", &"floor", &"rooms", &"paint"]
const CATEGORY_IDS: Array[StringName] = [&"dining", &"kitchen", &"bar_cafe", &"decor", &"lighting", &"restroom",
	&"walls", &"floor", &"rooms", &"paint"]
const CATEGORY_LABELS: Dictionary = {
	&"dining": "Dining", &"kitchen": "Kitchen", &"bar_cafe": "Bar & Café", &"decor": "Decor",
	&"lighting": "Lighting", &"restroom": "Restroom", &"walls": "Walls", &"floor": "Floor", &"rooms": "Rooms",
	&"paint": "Paint",
}
const ROOMS: StringName = &"rooms"
## Rooms tab cards: what each room is for (FK-101), by SimGrid.Room.
const ROOM_TIPS: Array[String] = [
	"Dining room: where guests sit. New floor starts as dining",
	"Kitchen: staff only. Guests never walk through it",
	"Restroom: put a toilet in it and guests can use it",
	"Storage: staff only, like the kitchen",
]
const WALLS: StringName = &"walls"
const FLOOR: StringName = &"floor"
const PAINT: StringName = &"paint"
## The sub-tab that shows every group of a room.
const ALL_GROUPS: StringName = &"all"
enum Sort { NAME, PRICE_LOW, PRICE_HIGH }
const SORT_LABELS: Array[String] = ["Sort: A to Z", "Sort: cheapest", "Sort: priciest"]
const TOOL_LABELS: Array[String] = ["Hand", "Eyedropper", "Sell"]
const TOOL_TIPS: Array[String] = [
	"Hand: pick up, move and rotate furniture",
	"Eyedropper: click a placed item to place another one like it",
	"Sell: click a placed item to sell it (Del sells what you point at)",
]
const FLOOR_THUMBNAIL: PackedScene = preload("res://assets/props/floor_tile.tscn")
## The ghost's marker legend; Main shows it in the HUD key strip while a piece is held.
const FURNITURE_HINT: String = "Square: work tile   Circle: seat"
const CHIP_FONT_SIZE: int = 15

var item_buttons: Dictionary[StringName, Button] = {}
## Walls tab cards by WallKindDef id.
var wall_buttons: Dictionary[StringName, Button] = {}
## Floor tab card (FK-080); its tab hides while the shop has no lot to grow into.
var floor_button: Button
## Rooms tab cards, by SimGrid.Room.
var room_buttons: Array[Button] = []
## Main turns the Rooms tab on once a shop is bound (like the Floor tab's price).
var _rooms_enabled: bool = false
var swatch_buttons: Dictionary[StringName, Button] = {}
var category_buttons: Dictionary[StringName, Button] = {}
var mode_buttons: Dictionary[StringName, Button] = {}
var tool_buttons: Array[Button] = []
var group_buttons: Dictionary[StringName, Button] = {}
var theme_buttons: Dictionary[StringName, Button] = {}
var sort_button: Button
## The divider before the tools, hidden with them in Paint.
var _tool_divider: Control
var undo_button: Button
var redo_button: Button
var selected_category: StringName = &""
var selected_group: StringName = ALL_GROUPS
var mode: StringName = BUY
var sort: Sort = Sort.NAME
## Theme filters that are on; none on shows every theme.
var theme_filters: Dictionary[StringName, bool] = {}
var selected_swatch_id: StringName = &"butter"
## Stable capture path: Panel/Margin/Rows/Scroll/Content/Categories/Readout/VibeMeter.
var vibe_meter: VibeMeter
var theme_label: Label
## The item the hover card describes (empty when hidden).
var hover_id: StringName = &""
var _floor_price: int = 0
var _thumbnails: ItemThumbnailCache
var _fitting: bool = false
var _content: ContentDB
var _ordered_ids: Array[StringName] = []
var _layout_ready: bool = false
var _paint_visible: bool = false
var _owner_level: int = 1
var _tool: int = BuildMode.Tool.HAND
var _editable: bool = true
var _mode_category: Dictionary[StringName, StringName] = {BUY: &"", BUILD: WALLS}


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
	if not active:
		_hide_hover_card()


## Paint shows the Build side with the Paint tab and its swatches.
func set_paint_visible(active: bool) -> void:
	_prepare_layout()
	if _paint_visible == active:
		return
	_paint_visible = active
	if active:
		if mode == BUY:
			_mode_category[BUY] = selected_category
		mode = BUILD
		selected_category = PAINT
	elif selected_category == PAINT:
		selected_category = _mode_category[BUILD] if _mode_category[BUILD] != PAINT else WALLS
	_apply_category()
	_fit_panel()


func is_paint_visible() -> bool:
	return _paint_visible


## Build or Buy. Each side remembers its last category.
func set_mode(next: StringName) -> void:
	_prepare_layout()
	if next != BUY and next != BUILD:
		return
	if mode != next:
		_mode_category[mode] = selected_category
		mode = next
		var remembered: StringName = _mode_category.get(mode, &"")
		selected_category = remembered if _category_shown(remembered) and remembered != PAINT else _first_category(mode)
		selected_group = ALL_GROUPS
	_apply_category()
	_fit_panel()


## Main reports the tool, whether undo/redo can run and what they would undo.
## `editable` is false while the shop is open (paint only).
func set_tool_state(tool: int, can_undo: bool, can_redo: bool, undo_text: String = "",
		redo_text: String = "", editable: bool = true) -> void:
	_prepare_layout()
	_tool = tool
	var editable_changed: bool = _editable != editable
	_editable = editable
	for index: int in range(tool_buttons.size()):
		tool_buttons[index].set_pressed_no_signal(index == tool)
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo
	undo_button.tooltip_text = ("Undo %s (Ctrl+Z)" % undo_text) if can_undo and not undo_text.is_empty() else "Undo (Ctrl+Z)"
	redo_button.tooltip_text = ("Redo %s (Ctrl+Y)" % redo_text) if can_redo and not redo_text.is_empty() else "Redo (Ctrl+Y)"
	# Main calls this on every pointer change; only the open/closed switch
	# changes which tabs work.
	if editable_changed:
		_apply_category()


func set_vibe(result: VibeModel.Result) -> void:
	_prepare_layout()
	vibe_meter.set_vibe(result)
	var text: String = "No theme yet"
	if result != null and result.valid and not result.active_theme.is_empty() and not result.theme_label.strip_edges().is_empty():
		text = "Theme: %s" % result.theme_label
	theme_label.text = text
	_fit_panel()


## Filters never replace the native buttons or alter the underlying definitions.
func set_category(category: StringName) -> void:
	if not CATEGORY_IDS.has(category) or category == PAINT:
		return
	var category_mode: StringName = BUILD if BUILD_CATEGORIES.has(category) else BUY
	if category_mode != mode:
		_mode_category[mode] = selected_category
		mode = category_mode
	if selected_category != category:
		selected_group = ALL_GROUPS
	selected_category = category
	_apply_category()
	_fit_panel()


## Sub-tab inside the current Buy room (ALL_GROUPS shows every group).
func set_group(group: StringName) -> void:
	if group != ALL_GROUPS and not CatalogueText.GROUP_IDS.has(group):
		return
	selected_group = group
	_apply_category()
	_fit_panel()


## Turns one theme filter on or off. Items with any chosen theme stay shown.
func set_theme_filter(tag: StringName, active: bool) -> void:
	if not CatalogueText.theme_ids().has(tag):
		return
	if active:
		theme_filters[tag] = true
	else:
		theme_filters.erase(tag)
	_apply_category()
	_fit_panel()


func set_sort(next: Sort) -> void:
	sort = next
	_apply_category()
	_fit_panel()


func visible_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in _display_order():
		if item_buttons[id].visible:
			result.append(id)
	return result


## Every catalogue item by name, independent of filters and sort.
func ordered_ids() -> Array[StringName]:
	return _ordered_ids.duplicate()


## What the hover card says for an item: name first, then price, what it
## does, charm (decor only) and themes. Empty for unknown ids.
func hover_card_lines(id: StringName) -> Array[String]:
	var definition: ItemDef = _content.item(id) if _content != null else null
	if definition == null:
		return []
	return CatalogueText.card_lines(definition, _owner_level)


func _ready() -> void:
	_prepare_layout()
	_fit_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _layout_ready:
		_fit_panel()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _layout_ready and not is_visible_in_tree():
		_hide_hover_card()


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
	var row: GridContainer = _items()
	for id: StringName in item_buttons.keys():
		if not desired_ids.has(id):
			var old_button: Button = item_buttons[id]
			row.remove_child(old_button)
			old_button.free()
			item_buttons.erase(id)
	for definition: ItemDef in definitions:
		var button: Button = item_buttons.get(definition.id) as Button
		if button == null:
			button = _tile("Buy_%s" % definition.id)
			button.pressed.connect(_on_buy_pressed.bind(definition.id))
			button.mouse_entered.connect(_show_hover_card.bind(definition.id))
			button.mouse_exited.connect(_on_tile_exited.bind(definition.id))
			item_buttons[definition.id] = button
			row.add_child(button)
		var locked: bool = definition.unlock_level > _owner_level
		var text: String = CatalogueText.tile_text(definition, _owner_level)
		if button.text != text:
			button.text = text
		button.disabled = locked
		# The hover card describes the item; the tooltip is the short fallback.
		button.tooltip_text = "Unlocks at level %d" % definition.unlock_level if locked else ""
	_ordered_ids = desired_ids
	if selected_category.is_empty() or (mode == BUY and not _category_shown(selected_category)):
		selected_category = _first_category(mode)
	_refresh_groups()
	_refresh_wall_cards()
	_refresh_floor_card()
	_refresh_room_cards()
	_apply_category()
	# Queue the current category first so visible previews arrive first. Every
	# remaining wrapper is still prepared once at startup in the same cache.
	for wanted: bool in [true, false]:
		for definition: ItemDef in definitions:
			if (category_for(definition) == selected_category) == wanted:
				item_buttons[definition.id].icon = _thumbnails.request(definition.view_scene)
	_refresh_swatches()
	if not hover_id.is_empty():
		_show_hover_card(hover_id)
	_fit_panel()


## One tile per wall kind, after the furniture tiles in the same grid.
func _refresh_wall_cards() -> void:
	var row: GridContainer = _items()
	var definitions: Array[WallKindDef] = []
	if _content != null:
		definitions = _content.wall_kinds()
	var desired: Array[StringName] = []
	for definition: WallKindDef in definitions:
		desired.append(definition.id)
	for id: StringName in wall_buttons.keys():
		if not desired.has(id):
			var old_button: Button = wall_buttons[id]
			row.remove_child(old_button)
			old_button.free()
			wall_buttons.erase(id)
	for definition: WallKindDef in definitions:
		var button: Button = wall_buttons.get(definition.id) as Button
		if button == null:
			button = _tile("Wall_%s" % definition.id)
			button.pressed.connect(_on_wall_pressed.bind(definition.id))
			wall_buttons[definition.id] = button
			row.add_child(button)
		row.move_child(button, row.get_child_count() - 1)
		button.text = "%s\n%s" % [definition.display_name, Fmt.money(definition.price)]
		button.tooltip_text = "Build %s for %s each" % [definition.display_name.to_lower(), Fmt.money(definition.price)]
		if definition.segment == SimGrid.Segment.DOORWAY:
			button.tooltip_text += ". On a back or side outside wall, this makes a back door"
		button.icon = _thumbnails.request(definition.thumbnail_scene)


## Main passes the lot's price per floor tile; 0 means there is no lot.
func set_floor_price(price: int) -> void:
	if price == _floor_price:
		return
	_floor_price = maxi(price, 0)
	_refresh_floor_card()
	if selected_category == FLOOR and _floor_price <= 0:
		selected_category = WALLS
	_apply_category()
	_fit_panel()


func _refresh_floor_card() -> void:
	if _thumbnails == null or _floor_price <= 0:
		return
	var row: GridContainer = _items()
	if floor_button == null:
		floor_button = _tile("Floor")
		floor_button.pressed.connect(_on_floor_pressed)
		row.add_child(floor_button)
	row.move_child(floor_button, row.get_child_count() - 1)
	floor_button.text = "Floor\n%s a tile" % Fmt.money(_floor_price)
	floor_button.tooltip_text = "Drag onto your lot to add floor for %s a tile; Shift-drag removes added floor" % Fmt.money(_floor_price)
	floor_button.icon = _thumbnails.request(FLOOR_THUMBNAIL)


## The Rooms tab (FK-101) shows once a shop is bound to paint.
func set_rooms_enabled(enabled: bool) -> void:
	if enabled == _rooms_enabled:
		return
	_rooms_enabled = enabled
	_refresh_room_cards()
	if selected_category == ROOMS and not enabled:
		selected_category = WALLS
	_apply_category()
	_fit_panel()


## One card per room type, with a swatch of the room's floor tint.
func _refresh_room_cards() -> void:
	if not _rooms_enabled:
		return
	var row: GridContainer = _items()
	if room_buttons.is_empty():
		for kind: int in range(RoomRules.LABELS.size()):
			var button: Button = _tile("Room_%s" % RoomRules.IDS[kind])
			button.pressed.connect(_on_room_pressed.bind(kind))
			button.text = "%s\nFree" % RoomRules.label(kind)
			button.tooltip_text = ROOM_TIPS[kind]
			button.icon = _room_swatch(BuildPreview.ROOM_SWATCHES[kind].color)
			row.add_child(button)
			room_buttons.append(button)
	for button: Button in room_buttons:
		row.move_child(button, row.get_child_count() - 1)


## A flat swatch in the room's palette colour with a darker edge of the same
## colour, like the Paint tab's colour chips.
static func _room_swatch(color: Color) -> ImageTexture:
	var image: Image = Image.create(THUMBNAIL_WIDTH, 44, false, Image.FORMAT_RGBA8)
	image.fill(color.darkened(0.35))
	image.fill_rect(Rect2i(3, 3, THUMBNAIL_WIDTH - 6, 38), color)
	return ImageTexture.create_from_image(image)


func _on_room_pressed(kind: int) -> void:
	if not visible or _paint_visible or selected_category != ROOMS \
			or (is_inside_tree() and not is_visible_in_tree()):
		return
	rooms_tool_requested.emit(kind)


func _on_floor_pressed() -> void:
	if not visible or _paint_visible or selected_category != FLOOR or _floor_price <= 0 \
			or (is_inside_tree() and not is_visible_in_tree()):
		return
	floor_tool_requested.emit()


func _on_wall_pressed(id: StringName) -> void:
	if not visible or _paint_visible or _content == null or selected_category != WALLS \
			or (is_inside_tree() and not is_visible_in_tree()):
		return
	var definition: WallKindDef = _content.wall_kind(id)
	if definition != null and wall_buttons.has(id) and wall_buttons[id].visible:
		wall_tool_requested.emit(definition.segment)


## A catalogue tile: picture centred on top, words centred underneath.
func _tile(node_name: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.theme = theme
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", THUMBNAIL_WIDTH)
	button.add_theme_constant_override("h_separation", 2)
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size = CARD_MINIMUM
	_tighten(button, 6.0, 6.0)
	return button


func _apply_category() -> void:
	var buying: bool = mode == BUY and not _paint_visible
	for category: StringName in category_buttons:
		var button: Button = category_buttons[category]
		button.visible = _category_shown(category) and (BUY_CATEGORIES.has(category) == (mode == BUY))
		button.set_pressed_no_signal(category == selected_category)
		button.disabled = not _editable and category != PAINT
	for key: StringName in mode_buttons:
		mode_buttons[key].set_pressed_no_signal(key == mode)
		mode_buttons[key].disabled = not _editable
	for button: Button in tool_buttons:
		button.visible = not _paint_visible
	_tool_divider.visible = not _paint_visible
	for id: StringName in item_buttons:
		var definition: ItemDef = _content.item(id) if _content != null else null
		item_buttons[id].visible = buying and _passes_filters(definition)
	var order: Array[StringName] = _display_order()
	var row: GridContainer = _items()
	for index: int in range(order.size()):
		if item_buttons[order[index]].get_index() != index:
			row.move_child(item_buttons[order[index]], index)
	for id: StringName in wall_buttons:
		wall_buttons[id].visible = not _paint_visible and mode == BUILD and selected_category == WALLS
	if floor_button != null:
		floor_button.visible = not _paint_visible and mode == BUILD and selected_category == FLOOR and _floor_price > 0
	for button: Button in room_buttons:
		button.visible = not _paint_visible and mode == BUILD and selected_category == ROOMS and _rooms_enabled
	var shown_groups: Array[StringName] = _room_groups(selected_category)
	for group: StringName in group_buttons:
		var button: Button = group_buttons[group]
		button.visible = buying and shown_groups.size() > 1 and (group == ALL_GROUPS or shown_groups.has(group))
		button.set_pressed_no_signal(group == selected_group)
	for tag: StringName in theme_buttons:
		theme_buttons[tag].visible = buying
		theme_buttons[tag].set_pressed_no_signal(theme_filters.has(tag))
	sort_button.visible = buying
	sort_button.text = SORT_LABELS[sort]
	(_content_node().get_node("Filters") as Control).visible = buying
	(_content_node().get_node("Items") as Control).visible = not _paint_visible
	(_content_node().get_node("PaintSwatches") as Control).visible = _paint_visible
	_refresh_title()
	var empty: Label = _content_node().get_node("Empty") as Label
	empty.visible = buying and visible_ids().is_empty()
	empty.text = "No items match these filters" if not theme_filters.is_empty() or selected_group != ALL_GROUPS \
		else "Nothing in this room yet"
	if not hover_id.is_empty() and (not item_buttons.has(hover_id) or not item_buttons[hover_id].visible):
		_hide_hover_card()


## Room, sub-tab and theme filters for one Buy tile.
func _passes_filters(definition: ItemDef) -> bool:
	if definition == null or category_for(definition) != selected_category:
		return false
	if selected_group != ALL_GROUPS and _room_groups(selected_category).size() > 1 \
			and CatalogueText.group_for(definition) != selected_group:
		return false
	if theme_filters.is_empty():
		return true
	for tag: StringName in definition.theme_tags:
		if theme_filters.has(tag):
			return true
	return false


## Item ids in the order the grid shows them (name, or price then name).
func _display_order() -> Array[StringName]:
	var order: Array[StringName] = _ordered_ids.duplicate()
	if sort == Sort.NAME or _content == null:
		return order
	var prices: Dictionary[StringName, int] = {}
	var ranks: Dictionary[StringName, int] = {}
	for index: int in range(order.size()):
		var definition: ItemDef = _content.item(order[index])
		prices[order[index]] = definition.price if definition != null else 0
		ranks[order[index]] = index
	var low_first: bool = sort == Sort.PRICE_LOW
	order.sort_custom(func(a: StringName, b: StringName) -> bool:
		if prices[a] != prices[b]:
			return prices[a] < prices[b] if low_first else prices[a] > prices[b]
		return ranks[a] < ranks[b])
	return order


## The groups (sub-tabs) present in a Buy room, in GROUP_IDS order.
func _room_groups(category: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	if _content == null:
		return found
	for group: StringName in CatalogueText.GROUP_IDS:
		for id: StringName in _ordered_ids:
			var definition: ItemDef = _content.item(id)
			if category_for(definition) == category and CatalogueText.group_for(definition) == group:
				found.append(group)
				break
	return found


## Buy rooms appear once they hold an item; Floor only with a lot to grow.
func _category_shown(category: StringName) -> bool:
	if BUILD_CATEGORIES.has(category):
		return (category != FLOOR or _floor_price > 0) and (category != ROOMS or _rooms_enabled)
	if not BUY_CATEGORIES.has(category) or _content == null:
		return false
	for id: StringName in _ordered_ids:
		if category_for(_content.item(id)) == category:
			return true
	return false


func _first_category(side: StringName) -> StringName:
	if side == BUILD:
		return WALLS
	for category: StringName in BUY_CATEGORIES:
		if _category_shown(category):
			return category
	return BUY_CATEGORIES[0]


func _refresh_groups() -> void:
	var filters: HBoxContainer = _content_node().get_node("Filters") as HBoxContainer
	if group_buttons.is_empty():
		var groups: Array[StringName] = [ALL_GROUPS]
		groups.append_array(CatalogueText.GROUP_IDS)
		for index: int in range(groups.size()):
			var group: StringName = groups[index]
			var button: Button = _chip("Group_%s" % group, "All" if group == ALL_GROUPS else CatalogueText.GROUP_LABELS[group])
			button.pressed.connect(_on_group_pressed.bind(group))
			group_buttons[group] = button
			filters.add_child(button)
			filters.move_child(button, index)


func _on_category_pressed(category: StringName) -> void:
	if not visible or not _editable and category != PAINT:
		return
	if category == PAINT:
		category_buttons[PAINT].set_pressed_no_signal(_paint_visible)
		if not _paint_visible:
			paint_requested.emit()
		return
	if _paint_visible:
		_mode_category[BUILD] = category
		category_buttons[category].set_pressed_no_signal(false)
		mode_requested.emit(BUILD)
		set_category(category)
		return
	set_category(category)


func _on_mode_pressed(next: StringName) -> void:
	if not visible or not _editable:
		mode_buttons[next].set_pressed_no_signal(next == mode)
		return
	if _paint_visible or next != mode:
		mode_requested.emit(next)
	set_mode(next)


func _on_tool_pressed(index: int) -> void:
	tool_buttons[index].set_pressed_no_signal(index == _tool)
	if visible and not _paint_visible:
		tool_requested.emit(index)


func _on_group_pressed(group: StringName) -> void:
	if visible and mode == BUY and not _paint_visible:
		set_group(group)


func _on_theme_pressed(tag: StringName) -> void:
	if visible and mode == BUY and not _paint_visible:
		set_theme_filter(tag, not theme_filters.has(tag))
	else:
		theme_buttons[tag].set_pressed_no_signal(theme_filters.has(tag))


func _on_sort_pressed() -> void:
	if visible and mode == BUY and not _paint_visible:
		set_sort(((sort + 1) % Sort.size()) as Sort)


func _on_undo_pressed() -> void:
	if visible:
		undo_requested.emit()


func _on_redo_pressed() -> void:
	if visible:
		redo_requested.emit()


func _on_thumbnail_ready(scene: PackedScene, texture: Texture2D) -> void:
	if _content == null:
		return
	if floor_button != null and scene == FLOOR_THUMBNAIL:
		floor_button.icon = texture
	for id: StringName in item_buttons:
		var definition: ItemDef = _content.item(id)
		if definition != null and definition.view_scene == scene:
			item_buttons[id].icon = texture
	for id: StringName in wall_buttons:
		var wall: WallKindDef = _content.wall_kind(id)
		if wall != null and wall.thumbnail_scene == scene:
			wall_buttons[id].icon = texture
	if not hover_id.is_empty() and item_buttons.has(hover_id):
		(get_node("HoverCard/Rows/Picture") as TextureRect).texture = item_buttons[hover_id].icon


# --- Hover card ---------------------------------------------------------------

func _show_hover_card(id: StringName) -> void:
	var lines: Array[String] = hover_card_lines(id)
	if lines.is_empty() or not item_buttons.has(id) or not item_buttons[id].visible:
		_hide_hover_card()
		return
	hover_id = id
	var card: PanelContainer = get_node("HoverCard") as PanelContainer
	(card.get_node("Rows/Picture") as TextureRect).texture = item_buttons[id].icon
	(card.get_node("Rows/Name") as Label).text = lines[0]
	(card.get_node("Rows/Lines") as Label).text = "\n".join(lines.slice(1))
	card.visible = true
	card.reset_size()
	_place_hover_card()


## Beside the panel, level with the hovered tile, over the world. A window
## too narrow for that puts it above the panel instead; never over the panel.
func _place_hover_card() -> void:
	var card: PanelContainer = get_node("HoverCard") as PanelContainer
	if not card.visible or not item_buttons.has(hover_id):
		return
	var origin: Vector2 = get_global_rect().position
	var tile: Rect2 = item_buttons[hover_id].get_global_rect()
	tile.position -= origin
	var panel: Rect2 = (get_node("Panel") as Control).get_global_rect()
	panel.position -= origin
	var card_size: Vector2 = card.get_combined_minimum_size()
	var position: Vector2
	if panel.end.x + CARD_GAP + card_size.x <= size.x - EDGE_MARGIN:
		position = Vector2(panel.end.x + CARD_GAP, clampf(tile.end.y - card_size.y,
			EDGE_MARGIN, maxf(EDGE_MARGIN, size.y - EDGE_MARGIN - card_size.y)))
	else:
		position = Vector2(clampf(tile.position.x, EDGE_MARGIN, maxf(EDGE_MARGIN, size.x - EDGE_MARGIN - card_size.x)),
			maxf(EDGE_MARGIN, panel.position.y - CARD_GAP - card_size.y))
	card.position = position
	card.size = card_size


func _hide_hover_card() -> void:
	hover_id = &""
	var card: Control = get_node_or_null("HoverCard") as Control
	if card != null:
		card.visible = false


func _on_tile_exited(id: StringName) -> void:
	if hover_id == id:
		_hide_hover_card()


# --- Paint swatches -------------------------------------------------------------

func _refresh_swatches() -> void:
	var row: HBoxContainer = _content_node().get_node("PaintSwatches") as HBoxContainer
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
	var title: Label = _content_node().get_node("Title") as Label
	title.visible = _paint_visible
	if not _paint_visible:
		# Hidden outside Paint: the Build/Buy and room tabs name the page.
		title.text = CATEGORY_LABELS.get(selected_category, "Furniture")
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


# --- Layout ---------------------------------------------------------------------

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
	var card: PanelContainer = get_node("HoverCard") as PanelContainer
	var card_style: StyleBox = original.duplicate() as StyleBox
	card_style.set_content_margin_all(10.0)
	card.add_theme_stylebox_override("panel", card_style)
	var content: Control = _content_node()
	content.minimum_size_changed.connect(_fit_panel)
	var bar: HBoxContainer = content.get_node("Bar") as HBoxContainer
	for side: StringName in [BUILD, BUY]:
		var button: Button = _chip("Mode_%s" % side, "Build" if side == BUILD else "Buy", 18)
		button.tooltip_text = "Build: walls, doorways, windows, floor, rooms and paint" if side == BUILD \
			else "Buy: furniture and decor by room"
		button.pressed.connect(_on_mode_pressed.bind(side))
		mode_buttons[side] = button
		bar.add_child(button)
	_tool_divider = _divider()
	bar.add_child(_tool_divider)
	for index: int in range(TOOL_LABELS.size()):
		var button: Button = _chip("Tool_%s" % TOOL_LABELS[index], TOOL_LABELS[index], 16)
		button.tooltip_text = TOOL_TIPS[index]
		button.pressed.connect(_on_tool_pressed.bind(index))
		tool_buttons.append(button)
		bar.add_child(button)
	IconStyle.configure_button(tool_buttons[BuildMode.Tool.SELL], &"sell", "Sell", TOOL_TIPS[BuildMode.Tool.SELL],
		IconCatalogue.PANEL_SIZE)
	undo_button = _chip("Undo", "Undo", 16, false)
	undo_button.pressed.connect(_on_undo_pressed)
	redo_button = _chip("Redo", "Redo", 16, false)
	redo_button.pressed.connect(_on_redo_pressed)
	bar.add_child(_divider())
	bar.add_child(undo_button)
	bar.add_child(redo_button)
	var categories: HBoxContainer = content.get_node("Categories") as HBoxContainer
	for category: StringName in CATEGORY_IDS:
		var button: Button = Button.new()
		button.name = String(category).capitalize()
		button.text = CATEGORY_LABELS[category]
		button.tooltip_text = CATEGORY_LABELS[category]
		button.theme = theme
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.pressed.connect(_on_category_pressed.bind(category))
		_tighten(button, 12.0, 5.0)
		category_buttons[category] = button
		categories.add_child(button)
	IconStyle.configure_button(category_buttons[PAINT], &"paint", "Paint", "Paint walls, floor and furniture (P)")
	var readout: HBoxContainer = HBoxContainer.new()
	readout.name = "Readout"
	readout.mouse_filter = Control.MOUSE_FILTER_PASS
	readout.add_theme_constant_override("separation", 10)
	readout.tooltip_text = "Your room's vibe and theme right now"
	categories.add_child(_divider())
	categories.add_child(readout)
	vibe_meter = VibeMeter.new()
	readout.add_child(vibe_meter)
	theme_label = Label.new()
	theme_label.name = "Theme"
	theme_label.text = "No theme yet"
	theme_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.add_child(theme_label)
	var filters: HBoxContainer = content.get_node("Filters") as HBoxContainer
	_refresh_groups()
	filters.add_child(_divider())
	for tag: StringName in CatalogueText.theme_ids():
		var label: String = CatalogueText.theme_label(tag)
		var button: Button = _chip("Theme_%s" % tag, label)
		button.tooltip_text = "Show %s items (pick several to see any of them)" % label
		button.pressed.connect(_on_theme_pressed.bind(tag))
		theme_buttons[tag] = button
		filters.add_child(button)
	filters.add_child(_divider())
	sort_button = _chip("Sort", SORT_LABELS[0], CHIP_FONT_SIZE, false)
	sort_button.tooltip_text = "Sort by name or price"
	sort_button.pressed.connect(_on_sort_pressed)
	filters.add_child(sort_button)
	_thumbnails = ItemThumbnailCache.new()
	_thumbnails.name = "ItemThumbnails"
	_thumbnails.thumbnail_ready.connect(_on_thumbnail_ready)
	add_child(_thumbnails)
	_layout_ready = true
	_apply_category()


## A small toggle (or plain) button in the shared theme with tight padding.
func _chip(node_name: String, label: String, font_size: int = CHIP_FONT_SIZE, toggle: bool = true) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = label
	button.theme = theme
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", font_size)
	_tighten(button, 8.0, 4.0)
	return button


## Shared theme styles with tighter padding (the palette and borders stay).
func _tighten(button: Button, side: float, top: float) -> void:
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style: StyleBox = theme.get_stylebox(state, "Button").duplicate() as StyleBox if theme != null \
			else button.get_theme_stylebox(state).duplicate() as StyleBox
		style.set_content_margin(SIDE_LEFT, side)
		style.set_content_margin(SIDE_RIGHT, side)
		style.set_content_margin(SIDE_TOP, top)
		style.set_content_margin(SIDE_BOTTOM, top)
		button.add_theme_stylebox_override(state, style)


func _divider() -> VSeparator:
	var line: VSeparator = VSeparator.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	return line


func _content_node() -> Control:
	return get_node("Panel/Margin/Rows/Scroll/Content") as Control


func _items() -> GridContainer:
	return get_node("Panel/Margin/Rows/Scroll/Content/Items") as GridContainer


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
	for button: Button in _visible_cards():
		card_width = maxf(card_width, button.get_combined_minimum_size().x)
	var bar_width: float = scroll.get_v_scroll_bar().get_combined_minimum_size().x
	# The tiles fill the width of the tab rows (at least MIN_COLUMNS tiles), so
	# the panel stays narrow enough to leave the shop in view; more tiles scroll.
	var rows_width: float = 0.0
	for child: Node in content.get_children():
		if child != row and child is Control and (child as Control).visible:
			rows_width = maxf(rows_width, (child as Control).get_combined_minimum_size().x)
	var wanted: float = maxf(rows_width, MIN_COLUMNS * (card_width + CARD_GAP) - CARD_GAP)
	var grid_width: float = minf(wanted, limit.x - bar_width)
	var columns: int = clampi(floori((grid_width + CARD_GAP) / (card_width + CARD_GAP)), 1, MAX_COLUMNS)
	if row.columns != columns:
		row.columns = columns
	var natural: Vector2 = content.get_combined_minimum_size()
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
	_place_hover_card()


func _visible_cards() -> Array[Button]:
	var cards: Array[Button] = []
	for button: Button in item_buttons.values():
		if button.visible:
			cards.append(button)
	for button: Button in wall_buttons.values():
		if button.visible:
			cards.append(button)
	if floor_button != null and floor_button.visible:
		cards.append(floor_button)
	for button: Button in room_buttons:
		if button.visible:
			cards.append(button)
	return cards


func _on_buy_pressed(id: StringName) -> void:
	if not visible or _paint_visible or mode != BUY or _content == null or not item_buttons.has(id) \
			or (is_inside_tree() and not is_visible_in_tree()):
		return
	var button: Button = item_buttons[id]
	var definition: ItemDef = _content.item(id)
	if button.visible and not button.disabled and _buyable(definition) and _passes_filters(definition) \
			and definition.unlock_level <= _owner_level:
		buy_requested.emit(id)


static func _buyable(definition: ItemDef) -> bool:
	return definition != null and definition.catalogue_visible and not definition.id.is_empty() \
		and not definition.display_name.strip_edges().is_empty() and not category_for(definition).is_empty() \
		and definition.price >= 0 and definition.unlock_level >= 1 \
		and definition.footprint.x > 0 and definition.footprint.y > 0


## The Buy room an item is listed under; "" for things the catalogue never sells (the door).
static func category_for(definition: ItemDef) -> StringName:
	if definition == null or definition.category == ItemDef.Category.DOOR:
		return &""
	return definition.buy_room()


static func _definition_before(first: ItemDef, second: ItemDef) -> bool:
	var first_name: String = first.display_name.to_lower()
	var second_name: String = second.display_name.to_lower()
	if first_name == second_name:
		return String(first.id) < String(second.id)
	return first_name < second_name
