extends TestCase
## Native controls and request-only content presentation. Actual appearance needs captures.

const SCENE: PackedScene = preload("res://src/ui/build_catalogue.tscn")

class CatalogueContent extends ContentDB:
	var definitions: Array[ItemDef] = []

	func items() -> Array[ItemDef]:
		return definitions.duplicate()

	func item(id: StringName) -> ItemDef:
		for definition: ItemDef in definitions:
			if definition.id == id:
				return definition
		return null

class ClickProbe extends Node:
	var clicks: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			clicks += 1

## Counts what falls through the interface to the shop.
class InputProbe extends Node:
	var keys: int = 0
	var motions: int = 0
	var left: int = 0
	var right: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and (event as InputEventKey).pressed:
			keys += 1
		elif event is InputEventMouseMotion:
			motions += 1
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				left += 1
			elif (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
				right += 1

var _catalogue: BuildCatalogue
var _content: CatalogueContent
var _requests: Array[StringName] = []
var _swatch_requests: Array[StringName] = []
var _host: Control

## The longest overview: restroom, cleanliness and inspection lines together.
const HYGIENE_LINES: PackedStringArray = ["Dirty tables: 1", "Floor spots: 2",
	"Restroom: 1 toilet needs a tidy · 1 upkeep spot", "Today's cleanliness: Spotless", "Last inspection: B, day 12"]


func before_each() -> void:
	_catalogue = SCENE.instantiate() as BuildCatalogue
	_content = CatalogueContent.new()
	_requests.clear()
	_swatch_requests.clear()
	_catalogue.buy_requested.connect(_record_request)
	_catalogue.swatch_requested.connect(_record_swatch_request)


func after_each() -> void:
	if is_instance_valid(_catalogue):
		_catalogue.free()
	if is_instance_valid(_host):
		_host.free()
	_host = null
	_content = null
	_requests.clear()
	_swatch_requests.clear()


func test_paint_chips_are_named_round_and_request_selected_swatch() -> void:
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	_catalogue.set_paint_visible(true)
	_catalogue.set_build_visible(true)
	assert_eq(_catalogue.swatch_buttons.size(), 40)
	assert_false((_catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Items") as Control).visible)
	var sage: Button = _catalogue.swatch_buttons[&"sage"]
	assert_eq(sage.tooltip_text, "Sage")
	assert_eq((sage.get_theme_stylebox("normal") as StyleBoxFlat).corner_radius_top_left, 15)
	sage.pressed.emit()
	assert_eq(_catalogue.selected_swatch_id, &"sage")
	assert_eq(_swatch_requests, [&"sage"] as Array[StringName])
	assert_eq((_catalogue.get_node("Panel/Margin/Rows/Toolbars/Title") as Label).text,
		"Paint | Sage - Click a wall, floor or item")
	var outline: StyleBoxFlat = _catalogue.theme.get_stylebox("normal", "Button") as StyleBoxFlat
	var selected_style: StyleBoxFlat = sage.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(selected_style.border_color, outline.border_color)
	assert_true(sage.scale.x > 1.0)
	assert_eq(_catalogue.swatch_buttons[&"butter"].scale, Vector2.ONE)


func test_hidden_scene_uses_shared_theme_and_only_panel_consumes_input() -> void:
	assert_false(_catalogue.is_node_ready())
	assert_false(_catalogue.visible)
	assert_eq(_catalogue.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_catalogue.anchor_right, 1.0)
	assert_eq(_catalogue.anchor_bottom, 1.0)
	assert_eq(_catalogue.theme, load("res://src/ui/theme/main_theme.tres"))
	var panel: Control = _catalogue.get_node("Panel") as Control
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(panel.mouse_force_pass_scroll_events)
	assert_eq(panel.anchor_top, 0.0)
	assert_eq(panel.anchor_right, 0.0, "the panel fits content rather than stretching across the viewport")
	assert_eq(panel.anchor_bottom, 0.0)
	var scroll: ScrollContainer = _scroll()
	assert_eq(scroll.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(scroll.mouse_force_pass_scroll_events)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "only the cards scroll, and only up and down (#499)")
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	for path: String in ["Panel/Margin", "Panel/Margin/Rows", "Panel/Margin/Rows/Toolbars", "Panel/Margin/Rows/Scroll/Content",
		"Panel/Margin/Rows/Toolbars/Title", "Panel/Margin/Rows/Scroll/Content/Items"]:
		assert_eq((_catalogue.get_node(path) as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_content_names_then_ids_sort_and_zero_price_is_buyable() -> void:
	_content.definitions = [_definition(&"zeta", "Zulu", 20),
		_definition(&"beta", "alpha", 0), _definition(&"alpha", "Alpha", 12),
		_definition(&"door", "Door", 0, ItemDef.Category.DOOR),
		_definition(&"negative", "Negative", -1)]
	_catalogue.bind_content(_content)
	assert_eq(_catalogue.ordered_ids(), [&"alpha", &"beta", &"zeta"] as Array[StringName])
	assert_eq(_catalogue.item_buttons.size(), 3)
	assert_eq(_catalogue.item_buttons[&"beta"].text, "$0", "a tile shows its price; the hover card names it")
	var row: GridContainer = _scroll().get_node("Content/Items") as GridContainer
	for index: int in range(_catalogue.ordered_ids().size()):
		var id: StringName = _catalogue.ordered_ids()[index]
		var button: Button = _catalogue.item_buttons[id]
		assert_eq(row.get_child(index), button)
		assert_eq(button.theme, _catalogue.theme)
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)
		assert_eq(button.focus_mode, Control.FOCUS_NONE)
		assert_false(button.disabled)
	var ids: Array[StringName] = _catalogue.ordered_ids()
	ids.clear()
	assert_eq(_catalogue.ordered_ids().size(), 3, "diagnostics cannot change ordering")


func test_shipped_catalogue_is_derived_from_every_valid_non_door_definition() -> void:
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	assert_eq(shipped.item(&"chair").id, &"chair", "the saved item identifier stays stable")
	assert_eq(shipped.item(&"chair").display_name, "Cushioned chair")
	var expected_count: int = 0
	for definition: ItemDef in shipped.items():
		if definition.category == ItemDef.Category.DOOR or not definition.catalogue_visible:
			assert_false(_catalogue.item_buttons.has(definition.id))
			continue
		expected_count += 1
		assert_true(_catalogue.item_buttons.has(definition.id))
		var button: Button = _catalogue.item_buttons[definition.id]
		if definition.unlock_level > 1:
			assert_true(button.disabled)
			assert_true(button.text.strip_edges().ends_with("Level %d" % definition.unlock_level))
			assert_eq(button.tooltip_text, "Unlocks at level %d" % definition.unlock_level)
		else:
			assert_false(button.disabled)
			assert_true(button.text.strip_edges().ends_with("$%d" % definition.price))
	for id: StringName in [&"plant_small_1", &"plant_small_2", &"plant_small_3"]:
		var hidden: ItemDef = shipped.item(id)
		assert_not_null(hidden, "hidden floor plants remain valid content for existing placements")
		if hidden == null:
			continue
		assert_false(hidden.catalogue_visible)
		assert_false(_catalogue.item_buttons.has(id))
		assert_not_null(hidden.view_scene)
		if hidden.view_scene != null:
			var thumbnails: ItemThumbnailCache = _catalogue.get("_thumbnails") as ItemThumbnailCache
			var requested_scenes: Dictionary = thumbnails.get("_scenes")
			assert_false(requested_scenes.has(ItemThumbnailCache.Request.new(hidden.view_scene).key),
				"a hidden floor plant never queues a thumbnail")
	var potted_plant: ItemDef = shipped.item(&"potted_plant")
	assert_true(potted_plant.catalogue_visible, "the larger unlockable plant stays in the catalogue")
	assert_true(_catalogue.item_buttons.has(&"potted_plant"))
	assert_eq(_catalogue.item_buttons.size(), expected_count)
	assert_eq(_catalogue.selected_category, &"dining")
	_catalogue.set_build_visible(true)
	await _mount(Vector2(1600.0, 900.0))
	var panel: PanelContainer = _catalogue.get_node("Panel") as PanelContainer
	assert_true(panel.size.x <= BuildCatalogue.MAX_PANEL_WIDTH)
	assert_true(panel.size.y <= _host.size.y * BuildCatalogue.PANEL_HEIGHT_SHARE + 0.5)
	assert_true(panel.size.x < _host.size.x * 0.85, "the catalogue leaves the world visible beside it")
	assert_almost_eq(panel.position.x, 12.0)
	assert_almost_eq(panel.get_rect().end.y, _host.size.y - 12.0)
	assert_false(_scroll().get_h_scroll_bar().visible)
	assert_false((_catalogue.get_node("Panel/Margin/Rows/Toolbars/Title") as Label).visible,
		"outside Paint the Build/Buy and room tabs name the page")


func test_hidden_definition_stays_in_content_without_a_card_thumbnail_or_purchase() -> void:
	var definition: ItemDef = _definition(&"retired_floor_plant", "Retired floor plant", 15)
	definition.catalogue_visible = false
	definition.view_scene = PackedScene.new()
	_content.definitions = [definition]
	_catalogue.bind_content(_content)

	assert_true(_content.item(definition.id) == definition,
		"catalogue visibility does not remove saved-item content")
	assert_false(_catalogue.item_buttons.has(definition.id))
	assert_true(_catalogue.ordered_ids().is_empty())
	var thumbnails: ItemThumbnailCache = _catalogue.get("_thumbnails") as ItemThumbnailCache
	assert_eq(thumbnails.pending_count(), 0, "hidden definitions never request a preview")
	_catalogue.set_build_visible(true)
	_catalogue._on_buy_pressed(definition.id)
	assert_true(_requests.is_empty(), "a hidden definition cannot be bought from a stale request")

func test_single_item_catalogue_uses_a_compact_strip() -> void:
	_content.definitions = [_definition(&"fixture", "Chair", 18)]
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	await _mount(Vector2(1600.0, 900.0))
	var panel: PanelContainer = _catalogue.get_node("Panel") as PanelContainer
	var content: Control = _scroll().get_node("Content") as Control
	var toolbars: Control = _catalogue.get_node("Panel/Margin/Rows/Toolbars") as Control
	var padding: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
	var rows: VBoxContainer = _catalogue.get_node("Panel/Margin/Rows") as VBoxContainer
	assert_eq(panel.size.y, toolbars.get_combined_minimum_size().y + rows.get_theme_constant("separation")
		+ content.get_combined_minimum_size().y + padding.y, "pinned toolbars plus the one card, no spare rows")
	assert_eq(_scroll().size.y, content.get_combined_minimum_size().y)
	assert_true(panel.size.x <= BuildCatalogue.MAX_PANEL_WIDTH + 0.5,
		"a short catalogue keeps the full-catalogue width, so the panel does not jump between tabs")
	assert_false(_scroll().get_h_scroll_bar().visible)
	assert_false(_scroll().get_v_scroll_bar().visible)


func test_refresh_preserves_native_buttons_visibility_and_updates_resource_prices() -> void:
	var definition: ItemDef = _definition(&"fixture", "Chair", 18)
	_content.definitions = [definition]
	_catalogue.bind_content(_content)
	var panel: PanelContainer = _catalogue.get_node("Panel") as PanelContainer
	var shared_style: StyleBoxFlat = _catalogue.theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	var compact_style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(compact_style != shared_style)
	assert_eq(compact_style.bg_color, shared_style.bg_color, "pre-ready layout retains the shared palette")
	assert_eq(compact_style.corner_radius_top_left, shared_style.corner_radius_top_left)
	assert_eq(shared_style.get_content_margin(SIDE_LEFT), 24.0, "shared theme padding is never mutated")
	assert_eq(compact_style.get_content_margin(SIDE_LEFT), 8.0)
	assert_eq(compact_style.get_content_margin(SIDE_TOP), 6.0)
	_catalogue.set_build_visible(true)
	var button: Button = _catalogue.item_buttons[definition.id]
	for _iteration: int in range(5):
		_catalogue.refresh_content()
		_catalogue.bind_content(_content)
		_catalogue.set_build_visible(true)
		assert_true(_catalogue.item_buttons[definition.id] == button)
		assert_true(button.visible)
		assert_false(button.disabled)
	definition.price = 0
	_catalogue.refresh_content()
	assert_true(_catalogue.item_buttons[definition.id] == button)
	assert_eq(button.text, "$0")
	assert_eq(_requests.size(), 0)


func test_buttons_emit_one_request_only_and_hidden_or_stale_items_emit_none() -> void:
	var definition: ItemDef = _definition(&"fixture", "Fixture", 0)
	_content.definitions = [definition]
	_catalogue.bind_content(_content)
	var button: Button = _catalogue.item_buttons[definition.id]
	button.pressed.emit()
	assert_true(_requests.is_empty())
	_catalogue.set_build_visible(true)
	button.pressed.emit()
	assert_eq(_requests, [&"fixture"] as Array[StringName])
	assert_eq(definition.price, 0)
	assert_eq(_content.definitions, [definition] as Array[ItemDef])
	_content.definitions.clear()
	button.pressed.emit()
	assert_eq(_requests.size(), 1, "stale content is rechecked before requesting")
	_catalogue.refresh_content()
	assert_false(is_instance_valid(button))
	assert_true(_catalogue.item_buttons.is_empty())


func test_locked_item_stays_visible_but_never_requests_until_owner_level_advances() -> void:
	var definition: ItemDef = _definition(&"plant", "Potted plant", 15)
	definition.unlock_level = 2
	_content.definitions = [definition]
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	var button: Button = _catalogue.item_buttons[&"plant"]
	assert_true(button.disabled)
	assert_eq(button.text, "Level 2")
	assert_eq(button.tooltip_text, "Unlocks at level 2")
	button.pressed.emit()
	_catalogue._on_buy_pressed(&"plant")
	assert_true(_requests.is_empty(), "a direct request cannot bypass the disabled button")
	_catalogue.set_owner_level(2)
	assert_true(_catalogue.item_buttons[&"plant"] == button)
	assert_false(button.disabled)
	assert_eq(button.text, "$15")
	button.pressed.emit()
	assert_eq(_requests, [&"plant"] as Array[StringName])
	_catalogue.set_owner_level(1)
	assert_true(button.disabled)
	button.pressed.emit()
	assert_eq(_requests.size(), 1)


func test_null_rebind_removes_old_buttons_and_can_repopulate_before_ready() -> void:
	_content.definitions = [_definition(&"fixture", "Fixture", 10)]
	_catalogue.bind_content(_content)
	var button: Button = _catalogue.item_buttons[&"fixture"]
	var remove: Button = _catalogue.wall_remove_button
	assert_not_null(remove)
	_catalogue.bind_content(null)
	_catalogue.bind_content(null)
	assert_false(is_instance_valid(button))
	assert_false(is_instance_valid(remove), "null content also releases the synthetic Remove card")
	assert_null(_catalogue.wall_remove_button)
	assert_true(_catalogue.ordered_ids().is_empty())
	assert_eq(_scroll().get_node("Content/Items").get_child_count(), 0)
	_catalogue.bind_content(_content)
	assert_eq(_catalogue.item_buttons.size(), 1)
	assert_false(_catalogue.is_node_ready())
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	var swatch_count: int = shipped.swatches().size()
	assert_true(swatch_count > 0)
	var swatch: Button = _catalogue.swatch_buttons[shipped.swatches()[0].id]
	_catalogue.bind_content(null)
	assert_false(is_instance_valid(swatch))
	assert_true(_catalogue.swatch_buttons.is_empty())
	assert_eq(_scroll().get_node("Content/PaintArea/PaintSwatches").get_child_count(), 0)
	_catalogue.bind_content(shipped)
	assert_eq(_catalogue.swatch_buttons.size(), swatch_count)
	assert_false(_catalogue.is_node_ready(), "typed clear/rebind also works before native theme readiness")


func test_native_mouse_down_refresh_up_requests_once() -> void:
	_content.definitions = [_definition(&"fixture", "Fixture", 10)]
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	await _mount(Vector2(900.0, 640.0))
	var button: Button = _catalogue.item_buttons[&"fixture"]
	var center: Vector2 = button.get_global_rect().get_center()
	_mouse(center, true)
	assert_true(button.is_pressed(), "native mouse-down starts a press")
	_catalogue.refresh_content()
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	assert_true(_catalogue.item_buttons[&"fixture"] == button)
	assert_true(button.is_pressed(), "refresh must retain the in-flight native press")
	_mouse(center, false)
	assert_eq(_requests, [&"fixture"] as Array[StringName])
	assert_false(button.is_pressed())


func test_bottom_grid_stays_bounded_and_long_catalogue_scrolls_at_small_sizes() -> void:
	for index: int in range(30):
		_content.definitions.append(_definition(StringName("item_%02d" % index), "Furniture %02d" % index, index))
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	await _mount(Vector2(900.0, 640.0))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var panel: Control = _catalogue.get_node("Panel") as Control
	var scroll: ScrollContainer = _scroll()
	# The smallest views the stretch settings allow: 1600x900 at 150% UI scale.
	for bounds: Vector2 in [Vector2(900.0, 640.0), Vector2(1066.0, 600.0)]:
		_host.size = bounds
		await tree.process_frame
		await tree.process_frame
		assert_eq(_catalogue.size, _host.size)
		assert_almost_eq(panel.position.x, 12.0)
		assert_almost_eq(panel.get_rect().end.y, bounds.y - 12.0)
		assert_true(panel.position.y >= 12.0)
		assert_true(panel.size.x <= minf(BuildCatalogue.MAX_PANEL_WIDTH, bounds.x - 24.0))
		assert_true(panel.size.y <= maxf(96.0, bounds.y * BuildCatalogue.PANEL_HEIGHT_SHARE) + 0.5)
		assert_false(scroll.get_h_scroll_bar().visible, "the catalogue never scrolls sideways (#499)")
		var vertical: VScrollBar = scroll.get_v_scroll_bar()
		assert_true(vertical.visible, "a long card grid scrolls vertically inside its bounded panel")
		assert_true(vertical.max_value > vertical.page)
		scroll.scroll_vertical = ceili(vertical.max_value)
		await tree.process_frame
		assert_true(scroll.scroll_vertical > 0)
		assert_true((scroll.get_node("Content") as Control).position.y < 0.0)
		scroll.scroll_vertical = 0
	assert_eq(_catalogue.item_buttons.size(), 30)
	assert_true(_requests.is_empty())


func test_long_catalogue_scrolls_only_its_cards_under_pinned_toolbars() -> void:
	for index: int in range(40):
		_content.definitions.append(_definition(StringName("item_%02d" % index), "Furniture %02d" % index, index))
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	_catalogue.set_curb_appeal(40.0, 1.1, true)
	await _mount(Vector2(1600.0, 900.0))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scroll: ScrollContainer = _scroll()
	var toolbars: Control = _catalogue.get_node("Panel/Margin/Rows/Toolbars") as Control
	var panel: Control = _catalogue.get_node("Panel") as Control
	assert_false(scroll.is_ancestor_of(toolbars), "the toolbars sit outside the scroll")
	assert_true(toolbars.is_ancestor_of(_catalogue.curb_appeal_meter) and _catalogue.curb_appeal_meter.is_visible_in_tree())
	assert_true(panel.position.y > _host.size.y * 0.5, "the panel stays below the screen centre")
	var card: Button = _catalogue.item_buttons[&"item_00"]
	var rows_shown: float = (scroll.size.y + BuildCatalogue.CARD_GAP) / (card.size.y + BuildCatalogue.CARD_GAP)
	assert_almost_eq(rows_shown, float(BuildCatalogue.VISIBLE_ROWS), 0.01, "rows shown: %s" % rows_shown)
	assert_true(scroll.get_v_scroll_bar().visible)
	assert_false(scroll.get_h_scroll_bar().visible)
	var pinned: Dictionary = {}
	for control: Control in [toolbars, _catalogue.mode_buttons[BuildCatalogue.BUY],
			_catalogue.category_buttons[&"walls"], _catalogue.sort_button, _catalogue.vibe_meter,
			_catalogue.curb_appeal_meter, _catalogue.theme_label, _catalogue.hygiene_button, _catalogue.grid_button, panel]:
		pinned[control] = control.get_global_rect()
	# Wheel over the toolbars, the readout and the cards: only the cards move.
	for point: Vector2 in [_catalogue.sort_button.get_global_rect().get_center(),
			_catalogue.vibe_meter.get_global_rect().get_center(), card.get_global_rect().get_center()]:
		scroll.scroll_vertical = 0
		await tree.process_frame
		var start: int = scroll.scroll_vertical
		await _wheel(point, MOUSE_BUTTON_WHEEL_DOWN)
		assert_eq(scroll.scroll_vertical - start, PanelScroll.WHEEL_STEP, "a wheel notch at %s scrolls the cards" % point)
		for control: Control in pinned:
			assert_eq(control.get_global_rect(), pinned[control], "%s never moves with the wheel" % control.name)
	scroll.scroll_vertical = ceili(scroll.get_v_scroll_bar().max_value)
	await tree.process_frame
	for control: Control in pinned:
		assert_eq(control.get_global_rect(), pinned[control], "%s stays put at the bottom of the list" % control.name)
	assert_true(_requests.is_empty(), "the wheel buys nothing")


## Jared's call on #499: wider, not taller. About 1,300 of 1,600 px, the
## vibe/curb readout on the Build/Buy and tools row, two full rows of 13 cards.
func test_wide_panel_shows_two_full_rows_of_thirteen_cards_at_1600x900() -> void:
	for index: int in range(40):
		_content.definitions.append(_definition(StringName("item_%02d" % index), "Furniture %02d" % index, index))
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	_catalogue.set_curb_appeal(40.0, 1.1, true)
	await _mount(Vector2(1600.0, 900.0))
	var panel: Control = _catalogue.get_node("Panel") as Control
	var scroll: ScrollContainer = _scroll()
	var grid: GridContainer = scroll.get_node("Content/Items") as GridContainer
	assert_eq(grid.columns, 13)
	var view: Rect2 = scroll.get_global_rect().grow(0.5)
	var whole: int = 0
	var rows: Dictionary = {}
	var columns: Dictionary = {}
	for id: StringName in _catalogue.visible_ids():
		var card: Rect2 = _catalogue.item_buttons[id].get_global_rect()
		if view.encloses(card):
			whole += 1
			rows[card.position.y] = true
			columns[card.position.x] = true
	assert_eq(rows.size(), 2, "two whole card rows show")
	assert_eq(columns.size(), 13, "thirteen whole card columns show")
	assert_eq(whole, 26)
	assert_true(panel.size.x >= 1250.0 and panel.size.x <= 1350.0, "about 1,300 px wide: %s" % panel.size.x)
	assert_true(panel.size.y <= _host.size.y * BuildCatalogue.PANEL_HEIGHT_SHARE + 0.5)
	# The readout shares the single mode and tool row.
	var bar: Control = _catalogue.get_node("Panel/Margin/Rows/Toolbars/Bar") as Control
	var readout: Control = bar.get_node("Readout") as Control
	assert_eq(_catalogue.vibe_meter.get_parent(), readout)
	assert_eq(_catalogue.curb_appeal_meter.get_parent(), readout)
	var mode_button: Rect2 = _catalogue.mode_buttons[BuildCatalogue.BUILD].get_global_rect()
	for control: Control in [_catalogue.vibe_meter, _catalogue.curb_appeal_meter, _catalogue.theme_label,
			_catalogue.hygiene_button, _catalogue.grid_button]:
		var rect: Rect2 = control.get_global_rect()
		assert_true(rect.position.y < mode_button.end.y and rect.end.y > mode_button.position.y,
			"%s sits on the Build/Buy row: %s" % [control.name, rect])
		assert_true(rect.position.x > mode_button.end.x)
	assert_true(readout.get_global_rect().position.x >= _catalogue.grid_button.get_global_rect().end.x,
		"the readout never overlaps the tools")
	# The same width on a tab with few, wider cards: the panel does not jump.
	var width: float = panel.size.x
	_catalogue.set_category(BuildCatalogue.WALLS)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame
	assert_eq(panel.size.x, width)
	# The widest readout (full scores, the longest bonus line and theme name)
	# still fits on the tools row, and the panel keeps its width.
	_catalogue.set_category(&"decor")
	var vibe: VibeModel.Result = VibeModel.Result.new()
	vibe.valid = true
	vibe.score = 100.0
	vibe.active_theme = &"seafood"
	vibe.theme_label = "Seafood"
	_catalogue.set_vibe(vibe)
	_catalogue.set_curb_appeal(100.0, 1.004, true)
	for frame: int in range(4):
		await tree.process_frame
	assert_eq(_catalogue.theme_label.text, "Theme: Seafood")
	assert_eq(_catalogue.curb_appeal_meter.bonus_label.text, CurbAppealText.SMALL_BONUS)
	mode_button = _catalogue.mode_buttons[BuildCatalogue.BUILD].get_global_rect()
	var widest: Rect2 = readout.get_global_rect()
	assert_true(widest.position.y < mode_button.end.y and widest.end.y > mode_button.position.y,
		"the widest readout stays on the Build/Buy row: %s in %s" % [widest, bar.get_global_rect()])
	assert_true(widest.position.x >= _catalogue.grid_button.get_global_rect().end.x)
	assert_eq(panel.size.x, width)
	assert_eq(grid.columns, 13)


## The shipped Buy cards (some carry look dots, so they are taller) with the
## street-facing curb meter showing: still two whole rows under the height cap.
func test_shipped_buy_cards_show_two_whole_rows_at_1600x900() -> void:
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	_catalogue.set_owner_level(6)
	_catalogue.set_build_visible(true)
	_catalogue.set_curb_appeal(40.0, 1.1, true)
	await _mount(Vector2(1600.0, 900.0))
	_catalogue.set_category(&"dining")
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for frame: int in range(4):
		await tree.process_frame
	var scroll: ScrollContainer = _scroll()
	var ids: Array[StringName] = _catalogue.visible_ids()
	assert_true(ids.size() > 13, "Dining fills more than one row")
	var view: Rect2 = scroll.get_global_rect().grow(0.5)
	var whole: int = 0
	for id: StringName in ids:
		if view.encloses(_catalogue.item_buttons[id].get_global_rect()):
			whole += 1
	assert_eq(whole, mini(ids.size(), 26), "scroll %s, card %s" % [scroll.get_global_rect(),
		_catalogue.item_buttons[ids[0]].get_global_rect()])
	assert_eq((scroll.get_node("Content/Items") as GridContainer).columns, 13)


## Build centres the tile being worked on, so the screen centre must stay
## world: a click there reaches the shop at every supported view, with the
## Hygiene overview closed or open (#542).
func test_screen_centre_stays_clear_of_the_wide_panel() -> void:
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	_catalogue.set_owner_level(6)
	_catalogue.set_build_visible(true)
	_catalogue.set_curb_appeal(40.0, 1.1, true)
	_catalogue.set_hygiene_lines(HYGIENE_LINES)
	await _mount(Vector2(1600.0, 900.0))
	var probe: ClickProbe = ClickProbe.new()
	_host.add_child(probe)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var panel: Control = _catalogue.get_node("Panel") as Control
	var expected: int = 0
	# 1600x900, 1280x720 (125%) and 1066x600 (150%, the smallest view).
	for bounds: Vector2 in [Vector2(1600.0, 900.0), Vector2(1280.0, 720.0), Vector2(1066.0, 600.0)]:
		_host.size = bounds
		for category: StringName in [&"dining", &"decor", BuildCatalogue.WALLS, BuildCatalogue.FLOORS]:
			_catalogue.set_category(category)
			for hygiene: bool in [false, true]:
				# The centre click below puts the card away, so open it afresh.
				_catalogue.set_hygiene_enabled(false)
				_catalogue.set_hygiene_enabled(hygiene)
				for frame: int in range(4):
					await tree.process_frame
				var centre: Vector2 = bounds * 0.5
				var context: String = "%s at %s hygiene=%s panel=%s card=%s" % [category, bounds, hygiene,
					panel.get_global_rect(), _catalogue.hygiene_panel.get_global_rect()]
				assert_eq(_catalogue.hygiene_panel.visible, hygiene, context)
				assert_true(panel.position.y > centre.y, context)
				assert_false(panel.get_global_rect().has_point(centre), context)
				if hygiene:
					assert_false(_catalogue.hygiene_panel.get_global_rect().grow(8.0).has_point(centre),
						"the Hygiene card stays off the centre: " + context)
				_mouse(centre, true)
				_mouse(centre, false)
				expected += 1
				assert_eq(probe.clicks, expected, "a click on the centre reaches the shop: " + context)
	_catalogue.set_hygiene_enabled(false)


## Opening Hygiene takes no height from the cards (#542): the card scroll and
## the panel are the same size open or closed, and 1600x900 keeps two rows.
func test_hygiene_overview_leaves_the_card_rows_alone() -> void:
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	_catalogue.set_owner_level(6)
	_catalogue.set_build_visible(true)
	_catalogue.set_curb_appeal(40.0, 1.1, true)
	_catalogue.set_hygiene_lines(HYGIENE_LINES)
	await _mount(Vector2(1600.0, 900.0))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var panel: Control = _catalogue.get_node("Panel") as Control
	var scroll: ScrollContainer = _scroll()
	for bounds: Vector2 in [Vector2(1600.0, 900.0), Vector2(1280.0, 720.0), Vector2(1066.0, 600.0)]:
		_host.size = bounds
		for category: StringName in [&"dining", &"decor", BuildCatalogue.WALLS]:
			_catalogue.set_category(category)
			_catalogue.set_hygiene_enabled(false)
			for frame: int in range(4):
				await tree.process_frame
			var closed_scroll: Rect2 = scroll.get_global_rect()
			var closed_panel: Rect2 = panel.get_global_rect()
			_catalogue.set_hygiene_enabled(true)
			for frame: int in range(4):
				await tree.process_frame
			var context: String = "%s at %s" % [category, bounds]
			assert_true(_catalogue.hygiene_panel.is_visible_in_tree(), context)
			assert_eq(scroll.get_global_rect(), closed_scroll, "the cards keep their height with Hygiene open: " + context)
			assert_eq(panel.get_global_rect(), closed_panel, "the panel does not grow with Hygiene open: " + context)
			assert_false(panel.is_ancestor_of(_catalogue.hygiene_panel), "the overview is not a row of the panel")
			assert_false(_catalogue.hygiene_panel.get_global_rect().intersects(panel.get_global_rect()),
				"the Hygiene card floats above the panel, never over it: " + context)
			if bounds.x == 1600.0 and category == &"dining":
				var row_height: float = _catalogue.item_buttons[_catalogue.visible_ids()[0]].size.y
				assert_true(scroll.size.y >= BuildCatalogue.VISIBLE_ROWS * (row_height + BuildCatalogue.CARD_GAP) - BuildCatalogue.CARD_GAP - 0.5,
					"two whole card rows show with Hygiene open (%s px of cards)" % scroll.size.y)
	_catalogue.set_hygiene_enabled(false)


## The Hygiene card is a popover under the real stretch settings: inside the
## view at 100%, 125% and 150% UI scale of a 1600x900 window, above the panel.
func test_hygiene_card_stays_inside_the_view_at_every_ui_scale() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.gui_embed_subwindows = true
	tree.root.add_child(viewport)
	var window: Window = Window.new()
	window.borderless = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1600, 900)
	window.size = Vector2i(1600, 900)
	viewport.add_child(window)
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(_host)
	_host.add_child(_catalogue)
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	_catalogue.set_owner_level(6)
	_catalogue.set_build_visible(true)
	_catalogue.set_curb_appeal(40.0, 1.1, true)
	_catalogue.set_hygiene_lines(HYGIENE_LINES)
	var panel: Control = _catalogue.get_node("Panel") as Control
	var card: Control = _catalogue.hygiene_panel
	for scale_factor: float in [1.0, 1.25, 1.5]:
		window.content_scale_factor = scale_factor
		await tree.process_frame
		_host.size = window.get_visible_rect().size
		for category: StringName in [&"dining", BuildCatalogue.WALLS, BuildCatalogue.BLUEPRINTS]:
			_catalogue.set_category(category)
			_catalogue.set_hygiene_enabled(false)
			_catalogue.set_hygiene_enabled(true)
			for frame: int in range(4):
				await tree.process_frame
			var allowed: Rect2 = _host.get_global_rect().grow(-11.5)
			var context: String = "%s at %s%% view=%s card=%s panel=%s" % [category, scale_factor * 100.0,
				_host.size, card.get_global_rect(), panel.get_global_rect()]
			assert_true(card.is_visible_in_tree(), context)
			assert_true(allowed.encloses(card.get_global_rect()), "the Hygiene card stays inside the view: " + context)
			assert_true(card.get_global_rect().end.y <= panel.get_global_rect().position.y, "the card sits above the panel: " + context)
			assert_true(card.size.x >= card.get_combined_minimum_size().x - 0.5 \
				and card.size.y >= card.get_combined_minimum_size().y - 0.5, "no line is cut off: " + context)
			assert_eq(_catalogue.hygiene_summary.text, "\n".join(HYGIENE_LINES))
			var button: Rect2 = _catalogue.hygiene_button.get_global_rect()
			assert_true(absf(card.get_global_rect().end.x - button.end.x) <= 0.5 \
				or card.get_global_rect().position.x <= 12.5, "the card hangs off the Hygiene button: " + context)
	_catalogue.set_hygiene_enabled(false)
	window.remove_child(_host)
	viewport.free()


## Escape or a click elsewhere puts the card away; Hygiene itself (the pressed
## button and the floor highlight) stays on until the button is pressed again.
## The first Escape and a left click on the card stop there; pointer motion
## and a right click over the card still reach the shop.
func test_hygiene_card_closes_on_escape_or_a_click_elsewhere_and_returns_on_hover() -> void:
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	_catalogue.set_hygiene_lines(HYGIENE_LINES)
	await _mount(Vector2(1600.0, 900.0))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var probe: InputProbe = InputProbe.new()
	_host.add_child(probe)
	var toggles: Array[bool] = []
	_catalogue.hygiene_toggled.connect(func(active: bool) -> void: toggles.append(active))
	var card: Control = _catalogue.hygiene_panel
	var button: Button = _catalogue.hygiene_button
	_mouse(button.get_global_rect().get_center(), true)
	_mouse(button.get_global_rect().get_center(), false)
	await tree.process_frame
	assert_true(_catalogue.hygiene_enabled, "the button opens it")
	assert_true(card.visible)
	var on_card: Vector2 = card.get_global_rect().get_center()
	_mouse(on_card, true)
	_mouse(on_card, false)
	assert_true(card.visible, "a left click on the card keeps it")
	assert_eq(probe.left, 0, "a left click on the card never reaches the shop")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = on_card + Vector2(3.0, 0.0)
	motion.global_position = motion.position
	tree.root.push_input(motion, true)
	assert_eq(probe.motions, 1, "pointer motion over the card reaches the shop, so a build ghost keeps following")
	assert_true(card.visible)
	_escape()
	assert_false(card.visible, "Escape puts the card away")
	assert_eq(probe.keys, 0, "the first Escape only puts the card away: nothing else sees it")
	assert_true(_catalogue.hygiene_enabled)
	assert_true(button.button_pressed, "the floor highlight stays on")
	_escape()
	assert_eq(probe.keys, 1, "with the card away, Escape is Build's again")
	button.mouse_entered.emit()
	assert_true(card.visible, "pointing at the button brings the card back")
	_mouse(Vector2(800.0, 200.0), true)
	_mouse(Vector2(800.0, 200.0), false)
	assert_false(card.visible, "a click elsewhere puts the card away")
	assert_eq(probe.left, 1)
	button.mouse_entered.emit()
	assert_true(card.visible)
	for pressed: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = card.get_global_rect().get_center()
		click.global_position = click.position
		click.button_index = MOUSE_BUTTON_RIGHT
		click.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
		click.pressed = pressed
		tree.root.push_input(click, true)
	assert_false(card.visible, "a right click on the card puts it away like one anywhere else")
	assert_eq(probe.right, 1, "and still reaches Build, which drops the ghost")
	assert_true(_catalogue.hygiene_enabled)
	assert_eq(toggles, [true] as Array[bool], "putting the card away never switches Hygiene off")
	_mouse(button.get_global_rect().get_center(), true)
	_mouse(button.get_global_rect().get_center(), false)
	assert_false(_catalogue.hygiene_enabled, "the button switches it off")
	assert_false(card.visible)
	assert_eq(toggles, [true, false] as Array[bool])


## A card put away with Escape comes back with Build or after Paint, as long
## as Hygiene is still on.
func test_hygiene_card_returns_when_build_reopens_or_paint_closes() -> void:
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	_catalogue.set_hygiene_lines(HYGIENE_LINES)
	await _mount(Vector2(1600.0, 900.0))
	var card: Control = _catalogue.hygiene_panel
	_catalogue.set_hygiene_enabled(true)
	_escape()
	assert_false(card.visible)
	_catalogue.set_build_visible(true)
	assert_false(card.visible, "Build staying open does not bring it back")
	_catalogue.set_build_visible(false)
	assert_false(card.visible)
	_catalogue.set_build_visible(true)
	assert_true(card.visible, "reopening Build shows the chosen overview again")
	_escape()
	assert_false(card.visible)
	_catalogue.set_paint_visible(true)
	assert_false(card.visible)
	_catalogue.set_paint_visible(false)
	assert_true(card.visible, "returning from Paint shows it again")
	_catalogue.set_hygiene_enabled(false)
	_catalogue.set_build_visible(false)
	_catalogue.set_build_visible(true)
	assert_false(card.visible, "Hygiene off stays off")


## Without room above the panel the facts share lines; a box in the way
## (the HUD's hints or goals) is never covered.
func test_hygiene_card_packs_its_facts_to_stay_clear_of_a_box_above() -> void:
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	_catalogue.set_hygiene_lines(HYGIENE_LINES)
	await _mount(Vector2(1280.0, 720.0))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	_catalogue.set_hygiene_enabled(true)
	await tree.process_frame
	var card: Control = _catalogue.hygiene_panel
	var panel: Control = _catalogue.get_node("Panel") as Control
	assert_eq(_catalogue.hygiene_summary.text, "\n".join(HYGIENE_LINES), "one fact a line when nothing is in the way")
	var tall: float = card.size.y
	var box: Rect2 = Rect2(900.0, 100.0, 368.0, card.get_global_rect().position.y + 40.0 - 100.0)
	_catalogue.set_hygiene_keep_clear([box] as Array[Rect2])
	assert_true(card.size.y < tall, "the card is shorter: %s" % card.get_global_rect())
	assert_false(card.get_global_rect().intersects(box), "and clear of the box: %s" % card.get_global_rect())
	assert_true(card.get_global_rect().end.y <= panel.get_global_rect().position.y)
	for fact: String in HYGIENE_LINES:
		assert_true(_catalogue.hygiene_summary.text.contains(fact), fact)
	# No room at all above the panel: a strip over the panel's foot.
	box.size.y = panel.get_global_rect().position.y - 20.0 - box.position.y
	_catalogue.set_hygiene_keep_clear([box] as Array[Rect2])
	assert_false(card.get_global_rect().intersects(box))
	assert_true(panel.get_global_rect().encloses(card.get_global_rect()), "over the panel's foot: %s" % card.get_global_rect())
	assert_true(Rect2(Vector2.ZERO, _host.size).grow(-11.5).encloses(card.get_global_rect()))
	_catalogue.set_hygiene_keep_clear([] as Array[Rect2])
	assert_eq(_catalogue.hygiene_summary.text, "\n".join(HYGIENE_LINES))
	assert_almost_eq(card.size.y, tall)


func _escape() -> void:
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	(Engine.get_main_loop() as SceneTree).root.push_input(escape, true)


## Narrow views wrap the readout under the tools instead of clipping it:
## 1280x720 (125%) and 1066x600 (150%), on both sides of the catalogue.
func test_no_control_is_clipped_at_1280x720_or_150_percent() -> void:
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	_catalogue.set_owner_level(6)
	_catalogue.set_build_visible(true)
	_catalogue.set_curb_appeal(40.0, 1.1, true)
	await _mount(Vector2(1600.0, 900.0))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var panel: Control = _catalogue.get_node("Panel") as Control
	var toolbars: Control = _catalogue.get_node("Panel/Margin/Rows/Toolbars") as Control
	var scroll: ScrollContainer = _scroll()
	for bounds: Vector2 in [Vector2(1600.0, 900.0), Vector2(1280.0, 720.0), Vector2(1066.0, 600.0)]:
		_host.size = bounds
		for category: StringName in BuildCatalogue.CATEGORY_IDS:
			if category == BuildCatalogue.PAINT:
				continue
			_catalogue.set_category(category)
			for frame: int in range(4):
				await tree.process_frame
			var context: String = "%s at %s" % [category, bounds]
			var frame_rect: Rect2 = panel.get_global_rect()
			assert_true(Rect2(Vector2.ZERO, bounds).grow(-11.5).encloses(frame_rect), "%s panel=%s" % [context, frame_rect])
			assert_true(frame_rect.grow(0.5).encloses(toolbars.get_global_rect()), context)
			assert_true(toolbars.get_global_rect().end.y <= scroll.get_global_rect().position.y + 0.5,
				"%s: the toolbars end above the cards" % context)
			var content_height: float = (scroll.get_node("Content") as Control).get_combined_minimum_size().y
			assert_true(scroll.size.y >= minf(content_height, 80.0), "%s: part of a card row still shows (%s px)" % [context, scroll.size.y])
			assert_false(scroll.get_h_scroll_bar().visible, context)
			var shown: Array[Control] = []
			_collect_shown(toolbars, shown)
			assert_true(shown.size() >= 12, context)
			for control: Control in shown:
				var rect: Rect2 = control.get_global_rect()
				assert_true(toolbars.get_global_rect().grow(0.5).encloses(rect),
					"%s: %s is clipped: %s outside %s" % [context, control.name, rect, toolbars.get_global_rect()])
				if control is Button:
					assert_false((control as Button).clip_text, "%s: %s" % [context, control.name])
			# Controls that share a row never overlap.
			for row: Node in toolbars.get_children():
				var seen: Array[Rect2] = []
				for child: Node in row.get_children():
					if child is Control and (child as Control).is_visible_in_tree():
						var rect: Rect2 = (child as Control).get_global_rect()
						for other: Rect2 in seen:
							assert_false(rect.grow(-0.5).intersects(other), "%s: %s overlaps a neighbour" % [context, child.name])
						seen.append(rect)
	# The readout is on the tools row when it fits and wraps below it when not.
	var readout: Control = toolbars.get_node("Bar/Readout") as Control
	var mode_button: Control = _catalogue.mode_buttons[BuildCatalogue.BUILD]
	assert_true(readout.get_global_rect().position.y >= mode_button.get_global_rect().end.y,
		"at 150% the readout wraps to its own line")


## Every visible button, label and meter under a toolbar row.
func _collect_shown(node: Node, into: Array[Control]) -> void:
	for child: Node in node.get_children():
		if not (child is Control) or not (child as Control).is_visible_in_tree():
			continue
		if child is BaseButton or child is Label or child is ProgressBar:
			into.append(child as Control)
		_collect_shown(child, into)


func test_only_bottom_panel_blocks_native_world_clicks() -> void:
	_content.definitions = [_definition(&"fixture", "Fixture", 10)]
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	await _mount(Vector2(900.0, 640.0))
	var probe: ClickProbe = ClickProbe.new()
	_host.add_child(probe)
	_mouse(Vector2(400.0, 100.0), true)
	_mouse(Vector2(400.0, 100.0), false)
	assert_eq(probe.clicks, 1, "the full-root catalogue leaves the shop clickable")
	var panel: Control = _catalogue.get_node("Panel") as Control
	var border: Vector2 = panel.get_global_rect().position + Vector2(5.0, 5.0)
	_mouse(border, true)
	_mouse(border, false)
	assert_eq(probe.clicks, 1, "blank panel padding consumes its click")
	assert_true(_requests.is_empty())


func test_category_filters_keep_all_buttons_and_reject_hidden_paint_and_stale_requests() -> void:
	_content.definitions = [
		_definition(&"chair", "Wooden chair", 10, ItemDef.Category.CHAIR, &"dining"),
		_definition(&"table", "Round table", 55, ItemDef.Category.TABLE, &"dining"),
		_definition(&"stove", "Cooking stove", 90, ItemDef.Category.STATION, &"kitchen"),
		_definition(&"fridge", "Fridge", 80, ItemDef.Category.STORAGE, &"kitchen"),
		_definition(&"pass", "Serving counter", 0, ItemDef.Category.PASS, &"kitchen"),
		_definition(&"plant", "Small plant", 15, ItemDef.Category.DECOR),
		_definition(&"door", "Door", 0, ItemDef.Category.DOOR),
	]
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	assert_eq(_catalogue.category_buttons.size(), BuildCatalogue.CATEGORY_IDS.size())
	assert_eq(_catalogue.item_buttons.size(), 6)
	assert_eq(_catalogue.visible_ids(), [&"table", &"chair"] as Array[StringName])
	assert_true(_catalogue.category_buttons[&"dining"].visible)
	assert_false(_catalogue.category_buttons[&"lighting"].visible, "a room without items has no tab")
	assert_false(_catalogue.category_buttons[&"walls"].visible, "Build tabs belong to the Build side")
	var chair: Button = _catalogue.item_buttons[&"chair"]
	var plant: Button = _catalogue.item_buttons[&"plant"]
	plant.pressed.emit()
	assert_true(_requests.is_empty(), "a hidden category cannot request a purchase")
	_catalogue.category_buttons[&"kitchen"].pressed.emit()
	assert_eq(_catalogue.visible_ids(), [&"stove", &"fridge", &"pass"] as Array[StringName])
	assert_eq(_catalogue.category_buttons[&"kitchen"].text, "Kitchen")
	assert_true(_catalogue.category_buttons[&"kitchen"].button_pressed)
	assert_false(_catalogue.category_buttons[&"dining"].button_pressed)
	_catalogue.category_buttons[&"kitchen"].set_pressed_no_signal(false)
	_catalogue.category_buttons[&"kitchen"].pressed.emit()
	assert_true(_catalogue.category_buttons[&"kitchen"].button_pressed, "clicking the active filter keeps it selected")
	assert_true(_catalogue.item_buttons[&"chair"] == chair)
	chair.pressed.emit()
	assert_true(_requests.is_empty())
	_catalogue.set_category(&"decor")
	assert_eq(_catalogue.visible_ids(), [&"plant"] as Array[StringName], "an item without a room is decor")
	_catalogue.refresh_content()
	assert_true(_catalogue.item_buttons[&"plant"] == plant)
	plant.pressed.emit()
	assert_eq(_requests, [&"plant"] as Array[StringName])
	_catalogue.set_paint_visible(true)
	_catalogue._on_buy_pressed(&"plant")
	assert_eq(_requests.size(), 1, "paint mode cannot buy a hidden item")
	assert_true(_catalogue.category_buttons[&"paint"].button_pressed)
	assert_false(_catalogue.category_buttons[&"decor"].visible)
	_catalogue.set_paint_visible(false)
	_catalogue.set_mode(BuildCatalogue.BUY)
	_catalogue.set_category(&"unsupported")
	assert_eq(_catalogue.selected_category, &"decor")
	_content.item(&"plant").catalogue_room = &"dining"
	plant.pressed.emit()
	assert_eq(_requests.size(), 1, "a stale category is rechecked against current content")
	_catalogue.set_category(&"dining")
	assert_true(_catalogue.item_buttons[&"chair"] == chair)
	assert_true(chair.visible)


func test_category_changes_between_native_mouse_down_and_up_never_buy_hidden_items() -> void:
	_content.definitions = [_definition(&"chair", "Chair", 10, ItemDef.Category.CHAIR, &"dining"),
		_definition(&"plant", "Plant", 15, ItemDef.Category.DECOR)]
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	await _mount(Vector2(900.0, 640.0))
	_catalogue.set_category(&"dining")
	var chair: Button = _catalogue.item_buttons[&"chair"]
	var centre: Vector2 = chair.get_global_rect().get_center()
	_mouse(centre, true)
	assert_true(chair.is_pressed())
	_catalogue.set_category(&"decor")
	_catalogue.refresh_content()
	_mouse(centre, false)
	assert_true(_requests.is_empty(), "a filtered in-flight button cannot buy")
	assert_true(_catalogue.item_buttons[&"chair"] == chair)
	_catalogue.set_category(&"dining")
	assert_false(chair.is_pressed())


func test_grid_bounds_at_supported_window_sizes_and_interface_scales() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.gui_embed_subwindows = true
	tree.root.add_child(viewport)
	var window: Window = Window.new()
	window.borderless = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = Vector2i(1600, 900)
	viewport.add_child(window)
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(_host)
	_host.add_child(_catalogue)
	var shipped: ContentDB = ContentDB.new()
	assert_eq(shipped.load_all(), PackedStringArray())
	_catalogue.bind_content(shipped)
	_catalogue.set_owner_level(6)
	_catalogue.set_build_visible(true)
	for physical_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		window.size = physical_size
		for scale_factor: float in [1.25, 1.5]:
			window.content_scale_factor = scale_factor
			await tree.process_frame
			_host.size = window.get_visible_rect().size
			for category: StringName in BuildCatalogue.CATEGORY_IDS:
				if category == BuildCatalogue.PAINT:
					continue
				_catalogue.set_category(category)
				for frame: int in range(4):
					await tree.process_frame
				var panel: Control = _catalogue.get_node("Panel") as Control
				var allowed: Rect2 = _host.get_global_rect().grow(-11.5)
				var context: String = "%s at %s/%s panel=%s allowed=%s" % [
					category, physical_size, scale_factor, panel.get_global_rect(), allowed]
				assert_true(allowed.encloses(panel.get_global_rect()), context)
				assert_true(panel.size.y <= _host.size.y * BuildCatalogue.PANEL_HEIGHT_SHARE + 0.5,
					"%s height=%s cap=%s panel_min=%s scroll_min=%s" % [context, panel.size.y,
						_host.size.y * BuildCatalogue.PANEL_HEIGHT_SHARE,
						panel.get_combined_minimum_size(), _scroll().get_combined_minimum_size()])
				assert_false(_scroll().get_h_scroll_bar().visible, "normal supported sizes need no horizontal scrolling")
				assert_true((_scroll().get_node("Content/Items") as GridContainer).columns >= 1)
				for id: StringName in _catalogue.visible_ids():
					var button: Button = _catalogue.item_buttons[id]
					assert_true(button.size.x >= button.get_combined_minimum_size().x - 0.5,
						"%s item=%s size=%s minimum=%s" % [context, id, button.size, button.get_combined_minimum_size()])
					assert_true(button.size.y >= BuildCatalogue.CARD_MINIMUM.y,
						"%s item=%s height=%s card_min=%s" % [context, id, button.size.y, BuildCatalogue.CARD_MINIMUM.y])
					assert_false(button.clip_text)
					assert_false(button.disabled)
					var dots: HBoxContainer = button.get_node_or_null("VariantDots") as HBoxContainer
					if dots != null:
						for dot: Node in dots.get_children():
							assert_true(button.get_global_rect().grow(0.5).encloses((dot as Control).get_global_rect()),
								"%s item=%s look=%s must stay inside its tile" % [context, id, dot.name])
	window.remove_child(_host)
	viewport.free()


func _mount(size: Vector2) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.size = size
	tree.root.add_child(_host)
	_host.add_child(_catalogue)
	await tree.process_frame
	await tree.process_frame
	assert_true(_catalogue.is_node_ready())


func _mouse(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.push_input(event, true)


func _wheel(position: Vector2, button: MouseButton) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.position = position
	move.global_position = position
	tree.root.push_input(move, true)
	for down: bool in [true, false]:
		var wheel: InputEventMouseButton = InputEventMouseButton.new()
		wheel.button_index = button
		wheel.position = position
		wheel.global_position = position
		wheel.pressed = down
		wheel.factor = 1.0
		tree.root.push_input(wheel, true)
	await tree.process_frame
	await tree.process_frame


func _scroll() -> ScrollContainer:
	return _catalogue.get_node("Panel/Margin/Rows/Scroll") as ScrollContainer


func _record_request(id: StringName) -> void:
	_requests.append(id)


func _record_swatch_request(id: StringName) -> void:
	_swatch_requests.append(id)


static func _definition(id: StringName, label: String, price: int, category: ItemDef.Category = ItemDef.Category.DECOR,
		room: StringName = &"") -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = id
	definition.display_name = label
	definition.price = price
	definition.category = category
	definition.catalogue_room = room
	return definition


func test_variant_dots_select_a_named_look_without_buying_or_mutating_content() -> void:
	var shipped: ContentDB = ContentDB.new()
	assert_true(shipped.load_all().is_empty())
	_catalogue.bind_content(shipped)
	_catalogue.set_owner_level(6)
	_catalogue.set_build_visible(true)
	_catalogue.set_category(&"bar_cafe")
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_catalogue)
	await tree.process_frame
	var button: Button = _catalogue.item_buttons[&"diner_stool"]
	var dots: HBoxContainer = button.get_node("VariantDots") as HBoxContainer
	assert_eq(dots.get_child_count(), 3)
	var teal: Button = dots.get_node("stool_chrome_teal") as Button
	assert_eq(teal.tooltip_text, "Chrome and dark teal")
	teal.pressed.emit()
	assert_eq(_catalogue.selected_variants[&"diner_stool"], &"stool_chrome_teal")
	assert_true(_requests.is_empty(), "choosing a dot does not buy furniture")
	assert_true(_catalogue.hover_card_lines(&"diner_stool").has("Chrome and dark teal"))
	assert_eq(shipped.item(&"diner_stool").theme_tags, [&"diner"] as Array[StringName])
