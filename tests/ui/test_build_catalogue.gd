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
var _host: Control


func before_each() -> void:
	_catalogue = SCENE.instantiate() as BuildCatalogue
	_content = CatalogueContent.new()
	_requests.clear()
	_catalogue.buy_requested.connect(_record_request)


func after_each() -> void:
	if is_instance_valid(_catalogue):
		_catalogue.free()
	if is_instance_valid(_host):
		_host.free()
	_host = null
	_content = null
	_requests.clear()


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
	assert_eq(_catalogue.item_buttons[&"beta"].text, "alpha\n$0")
	var row: HBoxContainer = _scroll().get_node("Content/Items") as HBoxContainer
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
	var expected_count: int = 0
	for definition: ItemDef in shipped.items():
		if definition.category == ItemDef.Category.DOOR:
			assert_false(_catalogue.item_buttons.has(definition.id))
			continue
		expected_count += 1
		assert_true(_catalogue.item_buttons.has(definition.id))
		assert_true(_catalogue.item_buttons[definition.id].text.ends_with("$%d" % definition.price))
	assert_eq(_catalogue.item_buttons.size(), expected_count)
	_catalogue.set_build_visible(true)
	await _mount(Vector2(1600.0, 900.0))
	var panel: PanelContainer = _catalogue.get_node("Panel") as PanelContainer
	var content: Control = _scroll().get_node("Content") as Control
	var natural: Vector2 = content.get_combined_minimum_size()
	var padding: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
	assert_eq(panel.size, natural + padding, "a fitting catalogue uses only its content and compact padding")
	assert_true(panel.size.x < _host.size.x * 0.8, "no empty strip spans the remaining viewport")
	assert_true(panel.size.y < 140.0, "the old176px strip is reduced to its actual contents")
	assert_almost_eq(panel.position.x, 12.0)
	assert_almost_eq(panel.get_rect().end.y, _host.size.y - 12.0)
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
	assert_eq(button.text, "Chair\n$0")
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


func test_bottom_strip_stays_bounded_and_long_catalogue_scrolls_at_small_widths() -> void:
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
		assert_almost_eq(panel.get_rect().end.x, bounds.x - 12.0)
		assert_almost_eq(panel.get_rect().end.y, bounds.y - 12.0)
		assert_true(panel.position.y >= 12.0)
		assert_true(panel.size.x <= bounds.x - 24.0)
		assert_true(panel.size.y <= bounds.y - 24.0)
		var bar: HScrollBar = scroll.get_h_scroll_bar()
		assert_true(bar.visible)
		assert_true(bar.max_value > bar.page)
		scroll.scroll_horizontal = ceili(bar.max_value)
		await tree.process_frame
		assert_true(scroll.scroll_horizontal > 0)
		assert_true((scroll.get_node("Content") as Control).position.x < 0.0)
		if bounds.y <= 120.0:
			var vertical: VScrollBar = scroll.get_v_scroll_bar()
			assert_true(vertical.visible, "short viewports scroll all catalogue content vertically")
			assert_true(vertical.max_value > vertical.page)
			scroll.scroll_vertical = ceili(vertical.max_value)
			await tree.process_frame
			assert_true(scroll.scroll_vertical > 0)
			assert_true((scroll.get_node("Content") as Control).position.y < 0.0)
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


static func _definition(id: StringName, label: String, price: int, category: ItemDef.Category = ItemDef.Category.DECOR) -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = id
	definition.display_name = label
	definition.price = price
	definition.category = category
	return definition
