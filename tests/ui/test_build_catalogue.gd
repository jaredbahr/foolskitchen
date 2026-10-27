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

var _catalogue: BuildCatalogue
var _content: CatalogueContent
var _requests: Array[StringName] = []
var _swatch_requests: Array[StringName] = []
var _host: Control


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
	assert_eq(_catalogue.swatch_buttons.size(), 12)
	assert_false((_catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Items") as Control).visible)
	var sage: Button = _catalogue.swatch_buttons[&"sage"]
	assert_eq(sage.tooltip_text, "Sage")
	assert_eq((sage.get_theme_stylebox("normal") as StyleBoxFlat).corner_radius_top_left, 17)
	sage.pressed.emit()
	assert_eq(_catalogue.selected_swatch_id, &"sage")
	assert_eq(_swatch_requests, [&"sage"] as Array[StringName])
	assert_eq((_catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Title") as Label).text,
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
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	for path: String in ["Panel/Margin", "Panel/Margin/Rows", "Panel/Margin/Rows/Scroll/Content",
		"Panel/Margin/Rows/Scroll/Content/Title", "Panel/Margin/Rows/Scroll/Content/Items"]:
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
			assert_true(button.text.ends_with("Level %d" % definition.unlock_level))
			assert_eq(button.tooltip_text, "Unlocks at level %d" % definition.unlock_level)
		else:
			assert_false(button.disabled)
			assert_true(button.text.ends_with("$%d" % definition.price))
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
			assert_false(requested_scenes.has(hidden.view_scene.get_instance_id()),
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
	assert_true(panel.size.x < _host.size.x * 0.8, "the catalogue leaves the world visible beside it")
	assert_almost_eq(panel.position.x, 12.0)
	assert_almost_eq(panel.get_rect().end.y, _host.size.y - 12.0)
	assert_false(_scroll().get_h_scroll_bar().visible)
	assert_false((_catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Title") as Label).visible,
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
	var padding: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
	assert_eq(panel.size, content.get_combined_minimum_size() + padding)
	assert_true(panel.size.x < _host.size.x * 0.8, "a short catalogue leaves the remaining viewport empty")
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
	_catalogue.bind_content(null)
	_catalogue.bind_content(null)
	assert_false(is_instance_valid(button))
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
	assert_eq(_scroll().get_node("Content/PaintSwatches").get_child_count(), 0)
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


func test_bottom_grid_stays_bounded_and_long_catalogue_scrolls_at_small_widths() -> void:
	for index: int in range(30):
		_content.definitions.append(_definition(StringName("item_%02d" % index), "Furniture %02d" % index, index))
	_catalogue.bind_content(_content)
	_catalogue.set_build_visible(true)
	await _mount(Vector2(900.0, 640.0))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var panel: Control = _catalogue.get_node("Panel") as Control
	var scroll: ScrollContainer = _scroll()
	for bounds: Vector2 in [Vector2(900.0, 640.0), Vector2(640.0, 120.0), Vector2(360.0, 100.0)]:
		_host.size = bounds
		await tree.process_frame
		await tree.process_frame
		assert_eq(_catalogue.size, _host.size)
		assert_almost_eq(panel.position.x, 12.0)
		assert_almost_eq(panel.get_rect().end.y, bounds.y - 12.0)
		assert_true(panel.position.y >= 12.0)
		assert_true(panel.size.x <= minf(BuildCatalogue.MAX_PANEL_WIDTH, bounds.x - 24.0))
		assert_true(panel.size.y <= bounds.y - 24.0)
		assert_true(panel.size.y <= maxf(96.0, bounds.y * BuildCatalogue.PANEL_HEIGHT_SHARE) + 0.5)
		var vertical: VScrollBar = scroll.get_v_scroll_bar()
		assert_true(vertical.visible, "a long card grid scrolls vertically inside its bounded panel")
		assert_true(vertical.max_value > vertical.page)
		scroll.scroll_vertical = ceili(vertical.max_value)
		await tree.process_frame
		assert_true(scroll.scroll_vertical > 0)
		assert_true((scroll.get_node("Content") as Control).position.y < 0.0)
		if bounds.x <= 360.0:
			var horizontal: HScrollBar = scroll.get_h_scroll_bar()
			assert_true(horizontal.visible, "tiny windows retain readable category buttons through scrolling")
			assert_true(horizontal.max_value > horizontal.page)
			scroll.scroll_horizontal = ceili(horizontal.max_value)
			await tree.process_frame
			assert_true(scroll.scroll_horizontal > 0)
			assert_true((scroll.get_node("Content") as Control).position.x < 0.0)
	assert_eq(_catalogue.item_buttons.size(), 30)
	assert_true(_requests.is_empty())

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
