extends TestCase
## Request-only controls; these tests do not claim guest/order/sale integration.

const PANEL: PackedScene = preload("res://src/ui/menu_panel.tscn")

var _name_requests: Array[String] = []
var _panel: MenuPanel
var _menu: MenuSettings
var _burger: RecipeDef
var _enable_requests: Array[Dictionary] = []
var _price_requests: Array[Dictionary] = []
var _reset_requests: int = 0
var _special_requests: Array[StringName] = []
var _signature_requests: Array[StringName] = []
var _settings_requests: int = 0
var _goals_requests: int = 0


func before_each() -> void:
	_name_requests.clear()
	_signature_requests.clear()
	_settings_requests = 0
	_goals_requests = 0
	_special_requests.clear()
	_reset_requests = 0
	_burger = _recipe(&"burger", "Burger", 12)
	_menu = MenuSettings.new([_recipe(&"tomato_soup", "Tomato soup", 9), _burger,
		_recipe(&"grilled_cheese", "Grilled cheese", 8)])
	_panel = PANEL.instantiate() as MenuPanel
	_panel.restaurant_name_requested.connect(_record_name)
	_panel.enable_requested.connect(_record_enable)
	_panel.price_requested.connect(_record_price)
	_panel.reset_prices_requested.connect(_record_reset)
	_panel.special_requested.connect(_record_special)
	_panel.signature_requested.connect(_record_signature)
	_panel.settings_requested.connect(_record_settings)
	_panel.goals_requested.connect(_record_goals)
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
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Body/Scroll") as ScrollContainer
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
	var rows: Node = _panel.get_node("%Rows")
	assert_eq(rows.get_child_count(), 4)
	assert_eq((rows.get_child(1).get_node("Top/Name") as Label).text, "Burger")
	assert_eq((rows.get_child(2).get_node("Top/Name") as Label).text, "Grilled cheese")
	assert_eq((rows.get_child(3).get_node("Top/Name") as Label).text, "Tomato soup")
	assert_eq(_label(&"burger", "Price/Amount").text, "$12")
	assert_eq(_label(&"burger", "Reference/Standard").text, "Suggested $12")
	assert_eq(_label(&"burger", "Reference/Ratio").text, "100% of suggested")
	assert_eq(_label(&"burger", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.STANDARD_COLOR)
	assert_eq(_bulk_button("MinusTen").text, "−10%")
	assert_eq(_bulk_button("PlusTen").text, "+10%")
	assert_eq(_bulk_button("Reset").text, "Reset to standard")
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


func test_daily_special_picker_is_request_only_enabled_menu_and_morning_gated() -> void:
	assert_true(_menu.set_enabled(&"grilled_cheese", false))
	_panel.refresh()
	var picker: OptionButton = _panel.get_node(
		"Panel/Content/Body/Scroll/Pad/List/DailySpecial/Choice") as OptionButton
	assert_eq(picker.item_count, 3, "None plus the two enabled recipes")
	assert_eq(picker.get_item_text(0), "None")
	assert_eq(picker.get_item_metadata(picker.selected), &"", "None is the default selection")
	_panel.set_special(&"tomato_soup")
	var burger_index: int = -1
	for index: int in picker.item_count:
		var recipe_id: StringName = StringName(picker.get_item_metadata(index))
		assert_ne(recipe_id, &"grilled_cheese", "disabled dishes are not selectable specials")
		if recipe_id == &"burger":
			burger_index = index
	assert_true(burger_index > 0)
	var before: Dictionary = _menu.to_dict()
	picker.item_selected.emit(burger_index)
	assert_eq(_special_requests, [&"burger"] as Array[StringName])
	assert_eq(_menu.to_dict(), before, "the panel only requests a special")
	assert_eq(picker.get_item_metadata(picker.selected), &"tomato_soup",
		"a rejected request restores the accepted selection")
	_panel.set_special(&"burger")
	assert_eq(picker.get_item_metadata(picker.selected), &"burger")
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_true(picker.disabled)
	picker.item_selected.emit(0)
	assert_eq(_special_requests, [&"burger"] as Array[StringName],
		"a forged selection event outside morning is ignored")
	assert_eq(picker.get_item_metadata(picker.selected), &"burger")


func test_secondary_settings_button_requests_panel_without_editing_dishes() -> void:
	var before: Dictionary = _menu.to_dict()
	var button: Button = _panel.get_node("%SettingsButton") as Button
	assert_eq(button.text, "Settings")
	assert_eq(button.theme, MenuPanel.SHARED_THEME)
	button.pressed.emit()
	assert_eq(_settings_requests, 1)
	assert_eq(_menu.to_dict(), before)


func test_rush_notice_is_visible_only_in_the_morning_menu() -> void:
	_panel.set_rush_notice("Book club: expect a rush around 1:15 pm.")
	var notice: Label = _panel.get_node("%RushNotice") as Label
	assert_true(notice.visible)
	assert_eq(notice.text, "Book club: expect a rush around 1:15 pm.")
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_false(notice.visible)
	_panel.set_phase(SimClock.Phase.MORNING)
	assert_true(notice.visible)


func test_theme_readout_tracks_accepted_enabled_dishes_without_editing_menu() -> void:
	var diner: RecipeDef = _recipe(&"diner", "Diner dish", 8)
	diner.theme_tags = [&"diner"]
	var cafe: RecipeDef = _recipe(&"cafe", "Café drink", 5)
	cafe.theme_tags = [&"cafe"]
	var plain: RecipeDef = _recipe(&"plain", "Plain dish", 6)
	var settings: MenuSettings = MenuSettings.new([diner, cafe, plain])
	_panel.bind_menu(settings)
	var readout: Label = _panel.get_node("Panel/Content/Body/Scroll/Pad/List/MenuTheme") as Label
	assert_eq(readout.theme, MenuPanel.SHARED_THEME)
	assert_eq(readout.text, "Menu leans: Diner 50%, Café 50%")
	var before: Dictionary = settings.to_dict()
	_panel.refresh()
	assert_eq(settings.to_dict(), before, "the readout does not change menu choices")
	assert_true(settings.set_enabled(&"cafe", false))
	_panel.refresh()
	assert_eq(readout.text, "Menu leans: Diner 100%")
	_panel.bind_menu(null)
	assert_eq(readout.text, "Menu leans: No theme")


func test_goals_button_requests_panel_without_editing_menu_or_phase() -> void:
	var before: Dictionary = _menu.to_dict()
	_panel.set_phase(SimClock.Phase.OPEN)
	var button: Button = _panel.get_node("%GoalsButton") as Button
	assert_eq(button.text, "Career goals")
	assert_eq(button.theme, MenuPanel.SHARED_THEME)
	assert_eq(button.focus_mode, Control.FOCUS_NONE)
	button.pressed.emit()
	assert_eq(_goals_requests, 1)
	assert_eq(_settings_requests, 0, "the goals action stays separate from Settings")
	assert_eq(_enable_requests.size(), 0)
	assert_eq(_price_requests.size(), 0)
	assert_eq(_menu.to_dict(), before)
	assert_true(_button(&"burger", "Price/Plus").disabled, "opening goals does not bypass morning price gates")


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


func test_bulk_ten_percent_requests_only_enabled_dishes_without_mutating_the_view_model() -> void:
	assert_true(_menu.set_enabled(&"grilled_cheese", false))
	assert_true(_menu.set_price(&"burger", 15))
	assert_true(_menu.set_price(&"grilled_cheese", 9))
	assert_true(_menu.set_price(&"tomato_soup", 10))
	_panel.refresh()
	var before: Dictionary = _menu.to_dict()
	_bulk_button("PlusTen").pressed.emit()
	assert_eq(_price_requests, [{"id": &"burger", "price": 17},
		{"id": &"tomato_soup", "price": 11}] as Array[Dictionary])
	_price_requests.clear()
	_bulk_button("MinusTen").pressed.emit()
	assert_eq(_price_requests, [{"id": &"burger", "price": 14},
		{"id": &"tomato_soup", "price": 9}] as Array[Dictionary])
	assert_eq(_menu.to_dict(), before, "the session must accept each request")
	assert_eq(_label(&"burger", "Price/Amount").text, "$15")
	_bulk_button("Reset").pressed.emit()
	assert_eq(_reset_requests, 1, "reset asks the session without mutating the bound model")
	assert_eq(_menu.to_dict(), before)


func test_bulk_acceptance_refreshes_prices_and_reset_includes_disabled_available_dishes() -> void:
	assert_true(_menu.set_enabled(&"grilled_cheese", false))
	assert_true(_menu.set_price(&"burger", 15))
	assert_true(_menu.set_price(&"grilled_cheese", 9))
	_panel.refresh()
	_panel.price_requested.connect(_accept_price)
	_panel.reset_prices_requested.connect(_accept_reset)
	_bulk_button("PlusTen").pressed.emit()
	assert_eq(_menu.price_of(_burger), 17)
	assert_eq(_menu.price_of(_menu.recipe(&"grilled_cheese")), 9)
	assert_eq(_menu.price_of(_menu.recipe(&"tomato_soup")), 10)
	assert_eq(_label(&"burger", "Price/Amount").text, "$17")
	_price_requests.clear()
	_bulk_button("Reset").pressed.emit()
	assert_eq(_reset_requests, 1)
	assert_true(_price_requests.is_empty(), "reset uses its dedicated all-prices request")
	for definition: RecipeDef in _menu.recipes():
		assert_eq(_menu.price_of(definition), definition.standard_price)
	assert_false(_menu.is_enabled(&"grilled_cheese"), "reset does not change today's dishes")
	assert_eq(_label(&"grilled_cheese", "Price/Amount").text, "$8")


func test_every_nonmorning_phase_gates_controls_and_direct_handlers() -> void:
	var before: Dictionary = _menu.to_dict()
	for phase: int in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS, SimClock.Phase.CLOSED, -1]:
		_panel.set_phase(phase)
		for path: String in ["Top/Enabled", "Price/Minus", "Price/Plus"]:
			assert_true(_button(&"burger", path).disabled)
			assert_true(_button(&"burger", path).tooltip_text.contains("morning"))
		_panel._on_price_step(&"burger", 1)
		_panel._on_bulk_price(1)
		_panel._on_bulk_reset()
		_panel._on_enable_toggled(false, &"burger")
		_button(&"burger", "Price/Minus").pressed.emit()
		_button(&"burger", "Top/Enabled").toggled.emit(false)
		for action: String in ["MinusTen", "PlusTen", "Reset"]:
			assert_true(_bulk_button(action).disabled)
			assert_true(_bulk_button(action).tooltip_text.contains("morning"))
			_bulk_button(action).pressed.emit()
	assert_eq(_price_requests.size(), 0)
	assert_eq(_reset_requests, 0)
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
	assert_eq(_label(&"burger", "Reference/Ratio").text, "50% of suggested")
	assert_eq(_label(&"burger", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.LOWER_COLOR)
	assert_true(_button(&"burger", "Price/Minus").disabled)
	_panel._on_price_step(&"burger", -1)
	assert_eq(_price_requests.size(), 0)
	assert_true(_menu.set_price(&"burger", 999))
	_panel.refresh()
	assert_eq(_label(&"burger", "Price/Amount").text, "$24")
	assert_eq(_label(&"burger", "Reference/Ratio").text, "200% of suggested")
	assert_eq(_label(&"burger", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.HIGHER_COLOR)
	assert_true(_button(&"burger", "Price/Plus").disabled)
	_panel._on_price_step(&"burger", 1)
	assert_eq(_price_requests.size(), 0)
	assert_true(_menu.set_price(&"burger", 12))
	_panel.refresh()
	assert_eq(_label(&"burger", "Reference/Ratio").get_theme_color("font_color"), MenuPanel.STANDARD_COLOR)
	assert_eq(_label(&"burger", "Reference/Standard").text, "Suggested $12")
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
	assert_eq(_label(&"free", "Reference/Ratio").text, "Free at suggested price")


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
	assert_eq(_label(&"rice", "Reference/Standard").text, "Suggested $5")
	_panel.bind_menu(null)
	_panel.refresh()
	assert_null(_panel.row_for(&"rice"))
	assert_true((_panel.get_node("%Empty") as Label).visible)
	assert_eq(_enable_requests.size(), 0)
	assert_eq(_price_requests.size(), 0)
	assert_false(_panel.visible)


func test_signature_action_is_eligible_request_only_and_preserves_selected_label() -> void:
	var before: Dictionary = _menu.to_dict()
	var signature: Dictionary = {"sales": 150, "unlock_sales": 150, "selected": false,
		"eligible": true, "can_select": true, "next_change_day": 0, "cooldown_days": 7,
		"is_morning": true}
	_panel.set_recipe_details([_burger] as Array[RecipeDef],
		{&"burger": {"signature": signature}} as Dictionary[StringName, Dictionary])
	var action: Button = _button(&"burger", "Signature/MakeSignature")
	assert_true(action.visible)
	assert_false(action.disabled)
	assert_eq(_label(&"burger", "Signature/Sales").text, "150 / 150 paid sales")
	action.pressed.emit()
	assert_eq(_signature_requests, [&"burger"] as Array[StringName])
	assert_eq(_menu.to_dict(), before, "the panel only requests the Main-owned selection")
	var chosen: Dictionary = signature.duplicate(true)
	chosen["selected"] = true
	chosen["can_select"] = false
	_panel.set_recipe_details([_burger] as Array[RecipeDef],
		{&"burger": {"signature": chosen}} as Dictionary[StringName, Dictionary])
	assert_false(action.visible)
	assert_true(_label(&"burger", "Signature/Status").visible)
	assert_eq(_label(&"burger", "Signature/Status").text, "Signature")
	assert_eq(_signature_requests.size(), 1)


func test_signature_action_explains_cooldown_and_nonmorning_refusals() -> void:
	var signature: Dictionary = {"sales": 150, "unlock_sales": 150, "selected": false,
		"eligible": true, "can_select": false, "next_change_day": 8, "cooldown_days": 7,
		"is_morning": true}
	_panel.set_recipe_details([_burger] as Array[RecipeDef],
		{&"burger": {"signature": signature}} as Dictionary[StringName, Dictionary])
	var action: Button = _button(&"burger", "Signature/MakeSignature")
	assert_true(action.visible)
	assert_true(action.disabled)
	assert_true(action.tooltip_text.contains("day 8"))
	action.pressed.emit()
	assert_true(_signature_requests.is_empty())
	signature["is_morning"] = false
	_panel.set_phase(SimClock.Phase.OPEN)
	_panel.set_recipe_details([_burger] as Array[RecipeDef],
		{&"burger": {"signature": signature}} as Dictionary[StringName, Dictionary])
	assert_true(action.disabled)
	assert_true(action.tooltip_text.contains("morning"))
	signature["eligible"] = false
	_panel.set_recipe_details([_burger] as Array[RecipeDef],
		{&"burger": {"signature": signature}} as Dictionary[StringName, Dictionary])
	assert_false(action.visible, "ineligible dishes do not offer the signature action")


func test_selected_signature_labels_fit_the_visible_menu_at_1600_by_900() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1600, 900)
	tree.root.add_child(host)
	host.add_child(_panel)
	_panel.visible = true
	_panel.set_phase(SimClock.Phase.MORNING)
	_panel.set_recipe_details([_burger] as Array[RecipeDef],
		{&"burger": {"signature": {"sales": 150, "unlock_sales": 150,
			"selected": true, "eligible": true, "can_select": true,
			"next_change_day": 8, "cooldown_days": 7, "is_morning": true}}}
		as Dictionary[StringName, Dictionary])
	assert_true(_panel.select_recipe(&"burger"))
	await tree.process_frame
	await tree.process_frame
	var panel: ScrollContainer = _panel.get_node("Panel") as ScrollContainer
	var detail_scroll: ScrollContainer = _panel.get_node("Panel/Content/Body/DetailScroll") as ScrollContainer
	var row: Control = _panel.row_for(&"burger")
	detail_scroll.ensure_control_visible(row)
	panel.ensure_control_visible(detail_scroll)
	await tree.process_frame
	await tree.process_frame
	var row_rect: Rect2 = row.get_global_rect()
	assert_true(detail_scroll.get_global_rect().grow(1.0).encloses(row_rect),
		"the selected dish row fits in the native detail scroller")
	assert_true(panel.get_global_rect().grow(1.0).encloses(row_rect),
		"the selected dish row stays inside the Menu panel")
	for path: String in ["Signature/Status", "Signature/Sales"]:
		var label: Label = row.get_node(path) as Label
		var rect: Rect2 = label.get_global_rect()
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		var text_width: float = font.get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		assert_true(label.is_visible_in_tree(), "%s is visible" % path)
		assert_true(rect.size.x >= text_width - 1.0,
			"%s shows its full text at readable width: %s" % [path, rect])
		assert_true(rect.size.y > 0.0 and rect.size.y <= font.get_height(font_size) * 2.0,
			"%s stays near one text line: %s" % [path, rect])
		assert_true(row_rect.encloses(rect), "%s stays inside its dish row" % path)
		assert_true(detail_scroll.get_global_rect().grow(1.0).encloses(rect),
			"%s stays inside the native detail scroller" % path)
		assert_true(host.get_visible_rect().grow(1.0).encloses(rect),
			"%s stays inside the 1600 by 900 canvas" % path)
	host.remove_child(_panel)
	host.free()


func _recipe(id: StringName, title: String, price: int) -> RecipeDef:
	var definition: RecipeDef = RecipeDef.new()
	definition.id = id
	definition.display_name = title
	definition.standard_price = price
	return definition


func _button(id: StringName, path: String) -> Button:
	return _panel.row_for(id).get_node(path) as Button


func _bulk_button(action: String) -> Button:
	return _panel.get_node("Panel/Content/Body/Scroll/Pad/List/BulkPrices/" + action) as Button


func _label(id: StringName, path: String) -> Label:
	return _panel.row_for(id).get_node(path) as Label


func _record_enable(id: StringName, enabled: bool) -> void:
	_enable_requests.append({"id": id, "enabled": enabled})


func _record_price(id: StringName, price: int) -> void:
	_price_requests.append({"id": id, "price": price})


func _accept_price(id: StringName, price: int) -> void:
	assert_true(_menu.set_price(id, price))
	_panel.refresh()


func _record_reset() -> void:
	_reset_requests += 1


func _accept_reset() -> void:
	assert_true(_menu.reset_all_prices_to_standard())
	_panel.refresh()


func _record_special(id: StringName) -> void:
	_special_requests.append(id)


func _record_signature(id: StringName) -> void:
	_signature_requests.append(id)


func _record_settings() -> void:
	_settings_requests += 1


func _record_goals() -> void:
	_goals_requests += 1


func _record_name(value: String) -> void:
	_name_requests.append(value)


func test_name_requests_validate_without_mutating_model_and_preserve_edit_draft() -> void:
	var edit: LineEdit = _panel.get_node("%RestaurantName") as LineEdit
	var apply: Button = _panel.get_node("%ApplyName") as Button
	assert_eq(edit.text, MenuSettings.DEFAULT_NAME)
	assert_eq(edit.max_length, MenuSettings.MAX_NAME_LENGTH)
	edit.text = "  Copper Cafe  "
	edit.text_changed.emit(edit.text)
	edit.caret_column = 5
	_panel.refresh()
	assert_eq(edit.text, "  Copper Cafe  ")
	assert_eq(edit.caret_column, 5, "routine refresh must not move the editing caret")
	apply.pressed.emit()
	edit.text_submitted.emit(edit.text)
	assert_eq(_name_requests, ["Copper Cafe", "Copper Cafe"] as Array[String])
	assert_eq(_menu.restaurant_name(), MenuSettings.DEFAULT_NAME, "the session owns acceptance")
	edit.text = "   "
	edit.text_changed.emit(edit.text)
	apply.pressed.emit()
	assert_eq(_name_requests.size(), 2)
	assert_true((_panel.get_node("%NameFeedback") as Label).visible)
	assert_true((_panel.get_node("%NameFeedback") as Label).text.contains("1"))
	edit.text = "Copper Cafe"
	edit.text_changed.emit(edit.text)
	_panel.set_phase(SimClock.Phase.OPEN)
	assert_false(edit.editable)
	assert_true(apply.disabled)
	_panel._on_name_apply_pressed()
	assert_eq(_name_requests.size(), 2, "direct handlers also honor the morning gate")
	_panel.set_phase(SimClock.Phase.MORNING)
	assert_eq(edit.text, "Copper Cafe", "closing and reopening edits retains the draft")


func test_sections_order_dishes_and_full_menu_can_be_reduced_before_adding() -> void:
	var recipes: Array[RecipeDef] = []
	for index: int in 7:
		var recipe: RecipeDef = _recipe(StringName("dish%d" % index), "Dish %d" % index, 6)
		recipe.section = RecipeDef.Section.DRINKS if index == 0 else RecipeDef.Section.MAINS
		recipes.append(recipe)
	var menu: MenuSettings = MenuSettings.new(recipes)
	_panel.bind_menu(menu)
	var rows: Node = _panel.get_node("%Rows")
	assert_eq((rows.get_child(0) as Label).text, "Mains")
	assert_eq((rows.get_child(7) as Label).text, "Drinks")
	assert_eq(_panel.row_for(&"dish0").get_index(), 8, "dish IDs do not override section order")
	var disabled: StringName = &""
	for recipe: RecipeDef in recipes:
		if not menu.is_enabled(recipe.id):
			disabled = recipe.id
	assert_ne(disabled, &"")
	assert_true(_button(disabled, "Top/Enabled").disabled)
	assert_true(_button(disabled, "Top/Enabled").tooltip_text.contains("menu is full"))
	assert_eq((_panel.get_node("%MenuCount") as Label).text, "6 / 6 dishes on the menu")
	_panel._on_enable_toggled(true, disabled)
	assert_true(_enable_requests.is_empty())
	assert_true(menu.set_enabled(menu.enabled_recipes()[0].id, false))
	_panel.refresh()
	assert_false(_button(disabled, "Top/Enabled").disabled)
	_button(disabled, "Top/Enabled").toggled.emit(true)
	assert_eq(_enable_requests.size(), 1)
	assert_false(menu.is_enabled(disabled), "request waits for session acceptance")


func test_identity_and_section_controls_fit_short_and_wide_viewports() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var viewport: SubViewport = SubViewport.new()
	tree.root.add_child(viewport)
	viewport.add_child(_panel)
	_panel.show()
	for dimensions: Vector2i in [Vector2i(853, 480), Vector2i(1600, 900)]:
		viewport.size = dimensions
		for frame: int in 3:
			await tree.process_frame
		var bounds: Rect2 = (_panel.get_node("Panel") as Control).get_global_rect()
		assert_true(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(bounds), "the panel stays on screen")
		assert_true(bounds.size.x <= MenuPanel.PANEL_MAX_WIDTH)
		var edit: LineEdit = _panel.get_node("%RestaurantName") as LineEdit
		var apply: Button = _panel.get_node("%ApplyName") as Button
		assert_true(bounds.encloses(edit.get_global_rect()))
		assert_true(bounds.encloses(apply.get_global_rect()))
		assert_true(edit.size.x > 100.0)
		assert_true(apply.global_position.x >= edit.get_global_rect().end.x)
		var scroll: Control = _panel.get_node("Panel/Content/Body/Scroll") as Control
		assert_true(scroll.size.y > 40.0, "new content must leave a usable scroll viewport")
		var detail: Control = _panel.get_node("Panel/Content/Body/DetailScroll") as Control
		assert_true(detail.global_position.x >= scroll.get_global_rect().end.x, "the dish detail sits beside the tree")
		assert_true(bounds.encloses(detail.get_global_rect()))
	viewport.remove_child(_panel)
	viewport.free()

func test_authored_croissant_tree_and_detail_show_bakery_without_menu_edits() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var croissant: RecipeDef = content.recipe(&"croissant")
	var menu: MenuSettings = MenuSettings.new([croissant] as Array[RecipeDef])
	var before: Dictionary = menu.to_dict()
	_panel.bind_menu(menu)
	assert_eq(_panel.tree_item_for(&"croissant").get_parent().get_text(0), "Bakery")
	assert_true(_panel.select_recipe(&"croissant"))
	assert_eq((_panel.get("_detail_heading") as Label).text, "Croissant - Bakery")
	assert_false(_panel.drinks_section().is_ancestor_of(_panel.row_for(&"croissant")))
	assert_eq(menu.to_dict(), before)
	assert_true(_enable_requests.is_empty() and _price_requests.is_empty())


func test_all_six_sections_use_readable_headings_in_menu_order() -> void:
	var recipes: Array[RecipeDef] = []
	for section: int in [RecipeDef.Section.BAKERY, RecipeDef.Section.DESSERTS, RecipeDef.Section.DRINKS,
		RecipeDef.Section.SIDES, RecipeDef.Section.MAINS, RecipeDef.Section.STARTERS]:
		var dish: RecipeDef = _recipe(StringName("section%d" % section), "Example dish", 6)
		dish.section = section as RecipeDef.Section
		recipes.append(dish)
	_panel.bind_menu(MenuSettings.new(recipes))
	var headings: Array[String] = []
	var tree: Tree = _panel.get("_recipe_tree") as Tree
	for section: TreeItem in tree.get_root().get_children():
		headings.append(section.get_text(0))
	assert_eq(headings, ["Starters", "Mains", "Sides", "Drinks", "Desserts", "Bakery"] as Array[String])
	for dish: RecipeDef in recipes:
		assert_not_null(_panel.row_for(dish.id), "grouping retains each interactive dish row")


func test_tree_links_and_selection_show_only_one_detail_without_menu_mutation() -> void:
	var child: RecipeDef = _recipe(&"child", "Second dish", 14)
	child.unlock_level = 2
	child.unlock_from = &"burger"
	_panel.bind_menu(MenuSettings.new([_burger, child]))
	var before: Dictionary = (_panel.get("_menu") as MenuSettings).to_dict()
	var node: TreeItem = _panel.tree_item_for(&"child")
	assert_eq(node.get_parent(), _panel.tree_item_for(&"burger"))
	assert_eq(node.get_text(1), "Lv 2")
	assert_eq(node.get_tooltip_text(1), "Unlocks at owner level 2.")
	assert_true(_panel.select_recipe(&"child"))
	assert_true(_panel.row_for(&"child").visible)
	assert_false(_panel.row_for(&"burger").visible)
	assert_eq((_panel.get("_detail_heading") as Label).text, "Second dish - Mains")
	assert_eq((_panel.get("_menu") as MenuSettings).to_dict(), before)
	assert_true(_enable_requests.is_empty() and _price_requests.is_empty())
	assert_false(_panel.select_recipe(&"missing"))
	assert_true(_panel.row_for(&"child").visible)


func test_missing_equipment_detail_is_inspectable_but_cannot_enable_or_reprice() -> void:
	var missing: RecipeDef = _recipe(&"missing_machine", "Coffee special", 6)
	missing.order_type = RecipeDef.COFFEE
	missing.section = RecipeDef.Section.DRINKS
	var details: Dictionary[StringName, Dictionary] = {&"missing_machine": {
		"quality": 0.8, "quality_source": "2 served dishes on day 1", "reviews": "Shop reviews: 3.5 / 5 (6 ratings)",
		"equipment": [{"text": "Buy a coffee machine", "met": false}],
		"ingredients": [{"text": "Coffee beans: 0 in stock / 1 needed", "met": false}],
		"other": [{"text": "Owner level 1", "met": true}]}}
	_panel.set_recipe_details([_burger, missing], details)
	assert_true(_panel.select_recipe(missing.id))
	for path: String in ["Top/Enabled", "Price/Minus", "Price/Plus"]:
		assert_true(_button(missing.id, path).disabled)
		assert_eq(_button(missing.id, path).tooltip_text, "Buy a coffee machine")
	assert_eq(_panel.tree_item_for(missing.id).get_text(1), "Buy a coffee machine")
	assert_eq(_label(missing.id, "Reference/Standard").text, "Suggested $6")
	assert_true((_panel.get("_quality_label") as Label).text.contains("Quality: 4 / 5 stars"))
	var slots: VBoxContainer = _panel.get("_requirements_box") as VBoxContainer
	assert_eq((slots.get_node("equipment0") as Label).get_theme_color("font_color"), MenuPanel.HIGHER_COLOR)
	assert_eq((slots.get_node("ingredients0") as Label).get_theme_color("font_color"), MenuPanel.LOCKED_COLOR,
		"ingredients wait, greyed out, until the equipment is in")
	assert_eq((slots.get_node("other0") as Label).get_theme_color("font_color"), MenuPanel.STANDARD_COLOR)
	_panel._on_enable_toggled(true, missing.id)
	_panel._on_price_step(missing.id, 1)
	assert_true(_enable_requests.is_empty() and _price_requests.is_empty())
	assert_eq(_menu.enabled_count(), 3)


func test_tree_level_refresh_preserves_nodes_selection_and_player_choices() -> void:
	var child: RecipeDef = _recipe(&"child", "Second dish", 14)
	child.unlock_from = &"burger"
	child.unlock_level = 2
	var other: RecipeDef = _recipe(&"other", "Another root", 10)
	var neighbour: RecipeDef = _recipe(&"neighbour", "Another child", 12)
	neighbour.unlock_from = other.id
	neighbour.unlock_level = 2
	var settings: MenuSettings = MenuSettings.new([_burger, child, other, neighbour])
	_panel.bind_menu(settings)
	var parent: TreeItem = _panel.tree_item_for(_burger.id)
	parent.collapsed = true
	assert_true(_panel.select_recipe(child.id))
	assert_false(parent.collapsed, "selecting a child reveals its branch")
	var node: TreeItem = _panel.tree_item_for(child.id)
	var other_branch: TreeItem = _panel.tree_item_for(other.id)
	other_branch.collapsed = true
	assert_true(settings.set_owner_level(2))
	assert_eq(_panel.tree_item_for(child.id), node)
	assert_true(other_branch.collapsed, "an unrelated branch remains folded")
	assert_eq(_panel.get("_selected_recipe"), child.id)
	assert_eq(node.get_text(1), "Off menu")
	assert_false(settings.is_enabled(child.id), "learning never adds a dish automatically")
	assert_false(_button(child.id, "Top/Enabled").disabled)
	assert_true(_enable_requests.is_empty())


func test_tree_and_detail_use_shared_warm_styles_and_removal_request() -> void:
	var scene: SceneTree = Engine.get_main_loop() as SceneTree
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(853, 720)
	scene.root.add_child(viewport)
	viewport.add_child(_panel)
	await scene.process_frame
	await scene.process_frame
	var tree: Tree = _panel.get("_recipe_tree") as Tree
	assert_eq(tree.theme, MenuPanel.SHARED_THEME)
	assert_true(tree.get_theme_color("font_color").is_equal_approx(MenuPanel.STANDARD_COLOR))
	assert_eq(tree.get_theme_color("font_color"), MenuPanel.SHARED_THEME.get_color("font_color", "Label"))
	assert_eq(tree.get_theme_stylebox("panel"), MenuPanel.SHARED_THEME.get_stylebox("normal", "LineEdit"))
	assert_eq(_button(&"burger", "Top/Enabled").text, "Remove from menu")
	var before: Dictionary = _menu.to_dict()
	_button(&"burger", "Top/Enabled").toggled.emit(false)
	assert_eq(_enable_requests, [{"id": &"burger", "enabled": false}] as Array[Dictionary])
	assert_eq(_menu.to_dict(), before)
	viewport.remove_child(_panel)
	viewport.free()


func test_ingredient_slots_turn_red_only_once_the_equipment_is_in() -> void:
	var details: Dictionary[StringName, Dictionary] = {&"burger": {
		"equipment": [{"text": "Stove ready", "met": true}],
		"ingredients": [{"text": "Beef: 0 in stock / 1 needed", "met": false},
			{"text": "Bread: 4 in stock / 2 needed", "met": true}],
		"other": []}}
	_panel.set_recipe_details(_menu.recipes(), details)
	assert_true(_panel.select_recipe(&"burger"))
	var slots: VBoxContainer = _panel.get("_requirements_box") as VBoxContainer
	assert_eq((slots.get_node("ingredients0") as Label).get_theme_color("font_color"), MenuPanel.HIGHER_COLOR)
	assert_eq((slots.get_node("ingredients1") as Label).get_theme_color("font_color"), MenuPanel.STANDARD_COLOR)


func test_a_stashed_drink_shows_the_price_it_will_come_back_at() -> void:
	var coffee: RecipeDef = _recipe(&"coffee", "Coffee", 5)
	coffee.order_type = RecipeDef.COFFEE
	coffee.section = RecipeDef.Section.DRINKS
	var menu: MenuSettings = MenuSettings.new([_burger, coffee])
	assert_true(menu.set_price(&"coffee", 7))
	assert_true(menu.set_catalogue([_burger] as Array[RecipeDef]), "the coffee machine was sold")
	assert_null(menu.recipe(&"coffee"))
	assert_eq(menu.shown_price(coffee), 7)
	assert_eq(menu.price_of(coffee), 5, "pricing for service is unchanged")
	_panel.bind_menu(menu)
	_panel.set_recipe_details([_burger, coffee], {} as Dictionary[StringName, Dictionary])
	assert_eq(_label(&"coffee", "Price/Amount").text, "$7")
	assert_eq(_label(&"coffee", "Reference/Ratio").text, "140% of suggested")
	assert_true(menu.set_catalogue([_burger, coffee] as Array[RecipeDef]), "the machine came back")
	assert_eq(menu.price_of(menu.recipe(&"coffee")), 7)


func test_tree_sizes_to_its_rows_without_trapping_the_wheel() -> void:
	var tree: Tree = _panel.get("_recipe_tree") as Tree
	assert_false(tree.scroll_vertical_enabled, "no nested scroll inside the column")
	assert_true(tree.mouse_force_pass_scroll_events, "the wheel reaches the column's scroll")
	assert_false(tree.column_titles_visible)
	var rows: int = 0
	var item: TreeItem = tree.get_root().get_next_in_tree()
	while item != null:
		rows += 1
		item = item.get_next_visible()
	assert_eq(rows, 4, "one section heading and three dishes")
	assert_true(tree.get_combined_minimum_size().y >= 4 * 30.0, "every row has room")
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Body/Scroll") as ScrollContainer
	assert_true(scroll.is_ancestor_of(tree))
	assert_false((_panel.get_node("Panel/Content/Body/DetailScroll") as Node).is_ancestor_of(tree))
	assert_true((_panel.get_node("Panel/Content/Body/DetailScroll") as Node).is_ancestor_of(_panel.row_for(&"burger")))


func test_the_mouse_wheel_over_the_tree_scrolls_its_column() -> void:
	var recipes: Array[RecipeDef] = []
	for index: int in 14:
		recipes.append(_recipe(StringName("dish%02d" % index), "Dish %d" % index, 6))
	_panel.bind_menu(MenuSettings.new(recipes))
	var scene: SceneTree = Engine.get_main_loop() as SceneTree
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1067, 600)
	viewport.gui_disable_input = false
	scene.root.add_child(viewport)
	viewport.add_child(_panel)
	_panel.show()
	for frame: int in 3:
		await scene.process_frame
	var scroll: ScrollContainer = _panel.get_node("Panel/Content/Body/Scroll") as ScrollContainer
	var tree: Tree = _panel.get("_recipe_tree") as Tree
	assert_true(scroll.get_v_scroll_bar().max_value > scroll.size.y, "the column has more rows than fit")
	var visible: Rect2 = tree.get_global_rect().intersection(scroll.get_global_rect())
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = visible.get_center()
	wheel.global_position = wheel.position
	viewport.push_input(wheel)
	var release: InputEventMouseButton = wheel.duplicate() as InputEventMouseButton
	release.pressed = false
	viewport.push_input(release)
	await scene.process_frame
	assert_true(scroll.scroll_vertical > 0, "the tree passes the wheel to the column")
	viewport.remove_child(_panel)
	viewport.free()
