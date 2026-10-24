extends TestCase
## Request-only controls; these tests do not claim guest/order/sale integration.

const PANEL: PackedScene = preload("res://src/ui/menu_panel.tscn")

var _panel: MenuPanel
var _menu: MenuSettings
var _burger: RecipeDef
var _enable_requests: Array[Dictionary] = []
var _price_requests: Array[Dictionary] = []
var _settings_requests: int = 0


func before_each() -> void:
	_settings_requests = 0
	_burger = _recipe(&"burger", "Burger", 12)
	_menu = MenuSettings.new([_recipe(&"tomato_soup", "Tomato soup", 9), _burger,
		_recipe(&"grilled_cheese", "Grilled cheese", 8)])
	_panel = PANEL.instantiate() as MenuPanel
	_panel.enable_requested.connect(_record_enable)
	_panel.price_requested.connect(_record_price)
	_panel.settings_requested.connect(_record_settings)
	_panel.bind_menu(_menu)


func after_each() -> void:
	_panel.free()


func test_rows_defaults_shared_styles_and_mouse_scope_work_before_ready() -> void:
	assert_false(_panel.is_node_ready())
	assert_false(_panel.visible, "the session owns opening the panel")
	assert_eq(_panel.theme, MenuPanel.SHARED_THEME)
	assert_eq(_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(_panel.anchor_right, 1.0)
	assert_eq(_panel.anchor_bottom, 1.0)
	var panel: Control = _panel.get_node("Panel") as Control
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Scroll") as ScrollContainer
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(panel.mouse_force_pass_scroll_events)
	assert_true(panel.clip_contents)
	assert_eq(panel.anchor_bottom, 1.0)
	assert_eq(panel.offset_top, 112.0)
	assert_eq(panel.offset_bottom, -12.0)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_eq(scroll.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(scroll.mouse_force_pass_scroll_events)
	var rows: Node = _panel.get_node("Panel/Content/Scroll/List/Rows")
	assert_eq(rows.get_child_count(), 3)
	assert_eq((rows.get_child(0).get_node("Top/Name") as Label).text, "Burger")
	assert_eq((rows.get_child(1).get_node("Top/Name") as Label).text, "Grilled cheese")
	assert_eq((rows.get_child(2).get_node("Top/Name") as Label).text, "Tomato soup")
	assert_eq(_label(&"burger", "Price/Amount").text, "$12")
	assert_eq(_label(&"burger", "Reference/Standard").text, "Standard $12")
	assert_eq(_label(&"burger", "Reference/Ratio").text, "100% of standard")
	assert_eq(_label(&"burger", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.STANDARD_COLOR)
	for path: String in ["Top/Enabled", "Price/Minus", "Price/Plus"]:
		var button: Button = _button(&"burger", path)
		assert_eq(button.theme, MenuPanel.SHARED_THEME)
		assert_eq(button.focus_mode, Control.FOCUS_NONE)
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)
		assert_false(button.has_theme_stylebox_override("normal"))
		assert_false(button.has_theme_stylebox_override("pressed"))
		assert_false(button.has_theme_color_override("font_color"))
		assert_eq(button.theme.get_stylebox("normal", "Button"), MenuPanel.SHARED_THEME.get_stylebox("normal", "Button"))
	assert_true(_button(&"burger", "Top/Enabled").button_pressed)
	assert_false(_button(&"burger", "Top/Enabled").disabled)
	assert_false(_label(&"burger", "Unlock").visible)
	assert_false(_label(&"burger", "Top/Name").has_theme_color_override("font_color"))
	assert_null(_panel.row_for(&"missing"))


func test_secondary_settings_button_requests_panel_without_editing_dishes() -> void:
	var before: Dictionary = _menu.to_dict()
	var button: Button = _panel.get_node("Panel/Content/SettingsButton") as Button
	assert_eq(button.text, "Settings")
	assert_eq(button.theme, MenuPanel.SHARED_THEME)
	button.pressed.emit()
	assert_eq(_settings_requests, 1)
	assert_eq(_menu.to_dict(), before)


func test_locked_recipe_is_greyed_out_readable_and_never_emits_requests() -> void:
	var seasonal: RecipeDef = _recipe(&"seasonal", "Seasonal special", 14)
	seasonal.unlock_level = 2
	var menu: MenuSettings = MenuSettings.new([_burger, seasonal])
	_panel.bind_menu(menu)
	assert_eq(_label(&"seasonal", "Unlock").text, "Unlocks at level 2")
	assert_true(_label(&"seasonal", "Unlock").visible)
	for path: String in ["Top/Name", "Price/Amount", "Reference/Standard", "Reference/Ratio"]:
		assert_eq(_label(&"seasonal", path).get_theme_color("font_color"), MenuPanel.LOCKED_COLOR)
	assert_eq(_button(&"seasonal", "Top/Enabled").text, "Locked")
	for phase: int in [SimClock.Phase.MORNING, SimClock.Phase.OPEN]:
		_panel.set_phase(phase)
		for path: String in ["Top/Enabled", "Price/Minus", "Price/Plus"]:
			assert_true(_button(&"seasonal", path).disabled)
			assert_eq(_button(&"seasonal", path).tooltip_text, "Unlocks at level 2")
		_panel._on_enable_toggled(true, &"seasonal")
		_panel._on_price_step(&"seasonal", 1)
		_button(&"seasonal", "Top/Enabled").toggled.emit(true)
		_button(&"seasonal", "Price/Plus").pressed.emit()
	assert_eq(_enable_requests.size(), 0)
	assert_eq(_price_requests.size(), 0)
	assert_false(menu.is_enabled(&"seasonal"))
	assert_eq(menu.price_of(seasonal), 14)


func test_level_change_signal_refreshes_row_without_rebinding_or_auto_enable() -> void:
	var seasonal: RecipeDef = _recipe(&"seasonal", "Seasonal special", 14)
	seasonal.unlock_level = 2
	var menu: MenuSettings = MenuSettings.new([_burger, seasonal])
	_panel.bind_menu(menu)
	var row_id: int = _panel.row_for(&"seasonal").get_instance_id()
	assert_true(menu.set_owner_level(2))
	assert_eq(_panel.row_for(&"seasonal").get_instance_id(), row_id)
	assert_false(_label(&"seasonal", "Unlock").visible)
	assert_false(_label(&"seasonal", "Top/Name").has_theme_color_override("font_color"))
	assert_eq(_label(&"seasonal", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.STANDARD_COLOR)
	assert_false(_button(&"seasonal", "Top/Enabled").disabled)
	assert_false(_button(&"seasonal", "Price/Plus").disabled)
	assert_false(menu.is_enabled(&"seasonal"))
	assert_eq(_enable_requests.size(), 0)
	assert_eq(_price_requests.size(), 0)
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_true(_button(&"seasonal", "Top/Enabled").disabled)
	assert_eq(_button(&"seasonal", "Top/Enabled").tooltip_text, MenuPanel.MORNING_HINT)
	_panel.bind_menu(null)
	assert_false(menu.owner_level_changed.is_connected(_panel._on_owner_level_changed))


func test_buttons_emit_primitive_requests_and_never_change_the_bound_model() -> void:
	var before: Dictionary = _menu.to_dict()
	_panel.bind_menu(_menu)
	_panel.bind_menu(_menu)
	_button(&"burger", "Price/Plus").pressed.emit()
	_button(&"burger", "Price/Minus").pressed.emit()
	_button(&"burger", "Top/Enabled").toggled.emit(false)
	assert_eq(_price_requests, [{"id": &"burger", "price": 13}, {"id": &"burger", "price": 11}] as Array[Dictionary])
	assert_eq(_enable_requests, [{"id": &"burger", "enabled": false}] as Array[Dictionary])
	assert_eq(_menu.to_dict(), before)
	assert_eq(_label(&"burger", "Price/Amount").text, "$12", "ignored requests restore committed values")
	assert_true(_button(&"burger", "Top/Enabled").button_pressed)
	assert_eq(_burger.standard_price, 12)


func test_every_nonmorning_phase_gates_controls_and_direct_handlers() -> void:
	var before: Dictionary = _menu.to_dict()
	for phase: int in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED, -1]:
		_panel.set_phase(phase)
		for path: String in ["Top/Enabled", "Price/Minus", "Price/Plus"]:
			assert_true(_button(&"burger", path).disabled)
			assert_true(_button(&"burger", path).tooltip_text.contains("morning"))
		_panel._on_price_step(&"burger", 1)
		_panel._on_enable_toggled(false, &"burger")
		_button(&"burger", "Price/Minus").pressed.emit()
		_button(&"burger", "Top/Enabled").toggled.emit(false)
	assert_eq(_price_requests.size(), 0)
	assert_eq(_enable_requests.size(), 0)
	assert_eq(_menu.to_dict(), before)
	_panel.set_phase(SimClock.Phase.MORNING)
	assert_false(_button(&"burger", "Price/Plus").disabled)
	assert_false(_button(&"burger", "Top/Enabled").disabled)
	_button(&"burger", "Price/Plus").pressed.emit()
	assert_eq(_price_requests.size(), 1)


func test_last_enabled_guard_applies_to_button_and_handler() -> void:
	assert_true(_menu.set_enabled(&"grilled_cheese", false))
	assert_true(_menu.set_enabled(&"tomato_soup", false))
	_panel.refresh()
	assert_true(_button(&"burger", "Top/Enabled").disabled)
	assert_true(_button(&"burger", "Top/Enabled").tooltip_text.contains("at least one"))
	assert_false(_button(&"grilled_cheese", "Top/Enabled").disabled)
	_panel._on_enable_toggled(false, &"burger")
	_button(&"burger", "Top/Enabled").toggled.emit(false)
	assert_eq(_enable_requests.size(), 0)
	assert_true(_menu.is_enabled(&"burger"))
	_button(&"grilled_cheese", "Top/Enabled").toggled.emit(true)
	assert_eq(_enable_requests, [{"id": &"grilled_cheese", "enabled": true}] as Array[Dictionary])
	assert_false(_menu.is_enabled(&"grilled_cheese"), "requests wait for session acceptance")
	assert_false(_button(&"grilled_cheese", "Top/Enabled").button_pressed)


func test_bounds_and_ratio_hints_follow_accepted_model_prices() -> void:
	assert_true(_menu.set_price(&"burger", 0))
	_panel.refresh()
	assert_eq(_label(&"burger", "Price/Amount").text, "$6")
	assert_eq(_label(&"burger", "Reference/Ratio").text, "50% of standard")
	assert_eq(_label(&"burger", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.LOWER_COLOR)
	assert_true(_button(&"burger", "Price/Minus").disabled)
	_panel._on_price_step(&"burger", -1)
	assert_eq(_price_requests.size(), 0)
	assert_true(_menu.set_price(&"burger", 999))
	_panel.refresh()
	assert_eq(_label(&"burger", "Price/Amount").text, "$24")
	assert_eq(_label(&"burger", "Reference/Ratio").text, "200% of standard")
	assert_eq(_label(&"burger", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.HIGHER_COLOR)
	assert_true(_button(&"burger", "Price/Plus").disabled)
	_panel._on_price_step(&"burger", 1)
	assert_eq(_price_requests.size(), 0)
	assert_true(_menu.set_price(&"burger", 12))
	_panel.refresh()
	assert_eq(_label(&"burger", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.STANDARD_COLOR)
	assert_eq(_label(&"burger", "Reference/Standard").text, "Standard $12")
	assert_eq(_burger.standard_price, 12)


func test_integer_limits_are_guarded_before_price_step_arithmetic() -> void:
	var largest: RecipeDef = _recipe(&"largest", "Large price", MenuSettings.MAX_PRICE)
	var large_menu: MenuSettings = MenuSettings.new([largest])
	_panel.bind_menu(large_menu)
	assert_true(_button(&"largest", "Price/Plus").disabled)
	_panel._on_price_step(&"largest", 1)
	_button(&"largest", "Price/Plus").pressed.emit()
	assert_eq(_price_requests.size(), 0)
	_panel._on_price_step(&"largest", -1)
	assert_eq(_price_requests, [{"id": &"largest", "price": MenuSettings.MAX_PRICE - 1}] as Array[Dictionary])
	assert_eq(large_menu.price_of(largest), MenuSettings.MAX_PRICE)
	_price_requests.clear()
	assert_true(large_menu.set_price(&"largest", 0))
	_panel.refresh()
	_panel._on_price_step(&"largest", -1)
	_panel._on_price_step(&"missing", 1)
	_panel._on_price_step(&"largest", 0)
	assert_eq(_price_requests.size(), 0)
	_panel._on_price_step(&"largest", 1)
	assert_eq(_price_requests[0]["price"], 4611686018427387905)
	var free: RecipeDef = _recipe(&"free", "Free dish", 0)
	_panel.bind_menu(MenuSettings.new([free]))
	_price_requests.clear()
	assert_true(_button(&"free", "Price/Plus").disabled)
	assert_true(_button(&"free", "Price/Minus").disabled)
	_panel._on_price_step(&"free", 1)
	_panel._on_price_step(&"free", -1)
	assert_eq(_price_requests.size(), 0)
	assert_eq(_label(&"free", "Reference/Ratio").text, "Free at standard price")


func test_refresh_is_idempotent_and_rebinding_replaces_rows_without_requests() -> void:
	var original_id: int = _panel.row_for(&"burger").get_instance_id()
	_panel.refresh()
	_panel.refresh()
	_panel._ready()
	assert_eq(_panel.row_for(&"burger").get_instance_id(), original_id)
	var replacement: MenuSettings = MenuSettings.new([_recipe(&"rice", "Rice", 5)])
	_panel.bind_menu(replacement)
	assert_null(_panel.row_for(&"burger"))
	assert_not_null(_panel.row_for(&"rice"))
	assert_true(_button(&"rice", "Top/Enabled").disabled)
	assert_eq(_label(&"rice", "Reference/Standard").text, "Standard $5")
	_panel.bind_menu(null)
	_panel.refresh()
	assert_null(_panel.row_for(&"rice"))
	assert_true((_panel.get_node("Panel/Content/Scroll/List/Empty") as Label).visible)
	assert_eq(_enable_requests.size(), 0)
	assert_eq(_price_requests.size(), 0)
	assert_false(_panel.visible)


func _recipe(id: StringName, title: String, price: int) -> RecipeDef:
	var definition: RecipeDef = RecipeDef.new()
	definition.id = id
	definition.display_name = title
	definition.standard_price = price
	return definition


func _button(id: StringName, path: String) -> Button:
	return _panel.row_for(id).get_node(path) as Button


func _label(id: StringName, path: String) -> Label:
	return _panel.row_for(id).get_node(path) as Label


func _record_enable(id: StringName, enabled: bool) -> void:
	_enable_requests.append({"id": id, "enabled": enabled})


func _record_price(id: StringName, price: int) -> void:
	_price_requests.append({"id": id, "price": price})


func _record_settings() -> void:
	_settings_requests += 1
