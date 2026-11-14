extends TestCase
## #497: every panel scrolls its one scroll area by the same wheel step from
## its header, body and footer, the wheel never changes a control's value, and
## PgUp/PgDn/Home/End scroll the open panel. Real Main panels at 1600x900.
## Where a panel's content is short, its list gets a taller minimum size: an
## explicit presentation fixture so there is room to scroll.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const PANELS: Array[String] = ["menu", "stock", "staff", "goals", "property", "report", "settings", "catalogue"]

var _nodes: Array[Node] = []
var _old_clock: Dictionary = {}
var _old_books: Dictionary = {}
var _old_providers: Dictionary = {}
var _old_rngs: Dictionary[StringName, RandomNumberGenerator] = {}
var _old_seed: int


func before_each() -> void:
	_old_clock = {"sim": Clock.sim, "speed": Clock.speed, "last_speed": Clock._last_non_zero_speed,
		"accumulator": Clock._accumulator, "world": Clock.attached_world, "driver": Clock.tick_driver,
		"driven_tick": Clock.driven_world_tick, "processing": Clock.is_processing()}
	_old_books = {"ledger": Economy.ledger, "stock": Economy.stock, "loan": Economy.loan}
	_old_providers = SaveSystem._providers.duplicate()
	_old_seed = GameState.master_seed
	_old_rngs = GameState._rngs.duplicate()
	Clock.set_process(false)
	Clock.attach_world(null)
	Clock.sim = SimClock.new()
	Clock.set_speed(0)
	Economy.reset(1234)
	GameState.new_run(7)


func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	Clock.attach_world(_old_clock["world"], _old_clock["driver"])
	Clock.sim = _old_clock["sim"]
	Clock.set_speed(int(_old_clock["speed"]))
	Clock._last_non_zero_speed = int(_old_clock["last_speed"])
	Clock._accumulator = float(_old_clock["accumulator"])
	Clock.driven_world_tick = int(_old_clock["driven_tick"])
	Clock.set_process(bool(_old_clock["processing"]))
	Economy.ledger = _old_books["ledger"]
	Economy.stock = _old_books["stock"]
	Economy.loan = _old_books["loan"]
	GameState.master_seed = _old_seed
	GameState._rngs = _old_rngs
	SaveSystem._providers = _old_providers


func test_every_panel_wheel_moves_one_step_from_header_body_and_footer() -> void:
	var main: Node = await _main()
	var steps: Array[int] = []
	for panel_name: String in PANELS:
		var view: Dictionary = await _open(main, panel_name)
		var host: Control = view["host"]
		assert_true(host.is_visible_in_tree(), "%s opens" % panel_name)
		var helper: PanelScroll = _helper(host)
		assert_not_null(helper, "%s uses the shared PanelScroll" % panel_name)
		if helper == null:
			continue
		var scroll: ScrollContainer = helper.main_scroll()
		await _make_room(scroll)
		scroll.scroll_vertical = 0
		await _frames()
		var before: Dictionary = _values(host)
		for spot: String in ["header", "body", "footer"]:
			var point: Vector2 = view[spot]
			assert_true((view["frame"] as Control).get_global_rect().has_point(point),
				"%s %s point is over the panel" % [panel_name, spot])
			var start: int = scroll.scroll_vertical
			await _wheel(main, point, MOUSE_BUTTON_WHEEL_DOWN)
			steps.append(scroll.scroll_vertical - start)
			assert_eq(scroll.scroll_vertical - start, PanelScroll.WHEEL_STEP,
				"%s: a wheel notch over the %s moves the scroll area one step" % [panel_name, spot])
			assert_true(host.is_visible_in_tree(), "%s: the wheel over the %s presses nothing" % [panel_name, spot])
		var top: int = scroll.scroll_vertical
		await _wheel(main, view["body"], MOUSE_BUTTON_WHEEL_UP)
		assert_eq(top - scroll.scroll_vertical, PanelScroll.WHEEL_STEP, "%s: wheel up is the same step" % panel_name)
		assert_eq(_values(host), before, "%s: no slider, choice, toggle or text changed" % panel_name)
		for extra: ScrollContainer in view.get("extra", []) as Array[ScrollContainer]:
			await _make_room(extra)
			extra.scroll_vertical = 0
			var main_at: int = scroll.scroll_vertical
			await _wheel(main, extra.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
			assert_eq(extra.scroll_vertical, PanelScroll.WHEEL_STEP, "%s: its second list keeps the same step" % panel_name)
			assert_eq(scroll.scroll_vertical, main_at, "%s: only the list under the pointer moves" % panel_name)
		await _close(main, panel_name, view)
		assert_false(host.is_visible_in_tree(), "%s closes from its header" % panel_name)
	assert_eq(steps.size(), PANELS.size() * 3)


func test_settings_wheel_over_sliders_and_choices_never_changes_them() -> void:
	var main: Node = await _main()
	var view: Dictionary = await _open(main, "settings")
	var host: Control = view["host"]
	var scroll: ScrollContainer = _helper(host).main_scroll()
	await _make_room(scroll)
	for path: String in ["%MasterSlider", "%MusicSlider", "%ScaleChoice", "%SpeedChoice", "%EdgePanToggle"]:
		var control: Control = host.get_node(path) as Control
		scroll.ensure_control_visible(control)
		await _frames()
		var before: Dictionary = _values(host)
		var start: int = scroll.scroll_vertical
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		var room: int = roundi(bar.max_value - bar.page) - start
		# Down: the sliders sit at 100%, so only a downward notch could move them.
		await _wheel(main, control.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
		assert_eq(_values(host), before, "the wheel over %s changes nothing" % path)
		assert_eq(scroll.scroll_vertical - start, mini(room, PanelScroll.WHEEL_STEP), "%s scrolls the panel instead" % path)


func test_page_keys_scroll_every_open_panel() -> void:
	var main: Node = await _main()
	for panel_name: String in PANELS:
		var view: Dictionary = await _open(main, panel_name)
		var host: Control = view["host"]
		var scroll: ScrollContainer = _helper(host).main_scroll()
		await _make_room(scroll)
		scroll.scroll_vertical = 0
		await _frames()
		var before: Dictionary = _values(host)
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		var bottom: int = roundi(bar.max_value - bar.page)
		await _key(main, KEY_PAGEDOWN)
		var page: int = scroll.scroll_vertical
		assert_true(page >= PanelScroll.WHEEL_STEP, "%s: PgDn moves down a page (%d)" % [panel_name, page])
		await _key(main, KEY_END)
		assert_eq(scroll.scroll_vertical, bottom, "%s: End reaches the bottom" % panel_name)
		await _key(main, KEY_PAGEUP)
		assert_eq(scroll.scroll_vertical, bottom - page, "%s: PgUp moves back a page" % panel_name)
		await _key(main, KEY_HOME)
		assert_eq(scroll.scroll_vertical, 0, "%s: Home returns to the top" % panel_name)
		assert_eq(_values(host), before, "%s: page keys change no control" % panel_name)
		assert_true(host.is_visible_in_tree(), "%s stays open" % panel_name)
		await _close(main, panel_name, view)


func test_an_open_dropdown_keeps_its_own_wheel() -> void:
	var main: Node = await _main()
	var view: Dictionary = await _open(main, "menu")
	var menu: Control = view["host"]
	var scroll: ScrollContainer = _helper(menu).main_scroll()
	await _make_room(scroll)
	scroll.scroll_vertical = 0
	var special: OptionButton = menu.get("_special_option") as OptionButton
	assert_not_null(special)
	if special == null:
		return
	# Presentation fixture: a list long enough to scroll inside the popup.
	for index: int in range(40):
		special.add_item("Fixture dish %d" % index)
	var selected: int = special.selected
	special.show_popup()
	await _frames()
	var popup: PopupMenu = special.get_popup()
	assert_true(popup.visible)
	var inner: ScrollContainer = _first_scroll(popup)
	assert_not_null(inner, "the popup has its own scroll list")
	if inner == null:
		return
	var popup_rect: Rect2 = Rect2(Vector2(popup.position), Vector2(popup.size))
	await _wheel(main, popup_rect.get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	assert_true(inner.scroll_vertical > 0, "the wheel scrolls the open list")
	assert_eq(scroll.scroll_vertical, 0, "the dish list behind it stays put")
	assert_eq(special.selected, selected)
	popup.hide()


func test_page_keys_leave_a_panel_covered_by_another() -> void:
	var main: Node = await _main()
	var view: Dictionary = await _open(main, "menu")
	var scroll: ScrollContainer = _helper(view["host"] as Control).main_scroll()
	await _make_room(scroll)
	scroll.scroll_vertical = 0
	assert_true(main.call("set_shortcuts_visible", true))
	await _frames()
	await _key(main, KEY_PAGEDOWN)
	await _key(main, KEY_END)
	assert_eq(scroll.scroll_vertical, 0, "Shortcuts over the Menu keeps the keys")
	assert_true(main.call("set_shortcuts_visible", false))
	await _frames()
	await _key(main, KEY_PAGEDOWN)
	assert_true(scroll.scroll_vertical > 0, "the Menu scrolls again once uncovered")
	main.call("set_menu_visible", false)
	view = await _open(main, "settings")
	var settings: Control = view["host"]
	var settings_scroll: ScrollContainer = _helper(settings).main_scroll()
	await _make_room(settings_scroll)
	settings_scroll.scroll_vertical = 0
	(settings.get_node("%WhatsNewButton") as Button).pressed.emit()
	await _frames()
	await _key(main, KEY_PAGEDOWN)
	assert_eq(settings_scroll.scroll_vertical, 0, "What's new over Settings keeps the keys")


func test_report_close_and_esc_hide_it_without_starting_the_next_day() -> void:
	var main: Node = await _main()
	var day: int = Clock.sim.day
	for how: String in ["close", "esc"]:
		var view: Dictionary = await _open(main, "report")
		var report: Control = view["host"]
		assert_true(report.visible)
		if how == "close":
			(report.get_node("%Close") as Button).pressed.emit()
		else:
			await _key(main, KEY_ESCAPE)
		await _frames()
		assert_false(report.visible, "the report hides on %s" % how)
		assert_false(main.call("is_settings_visible"), "%s does not open Settings over the report" % how)
		assert_eq(Clock.sim.day, day, "%s does not start the next day" % how)
		assert_false(main.call("show_closed_report"), "only a closed day's report can be reopened")


func test_menu_close_matches_esc() -> void:
	var main: Node = await _main()
	var view: Dictionary = await _open(main, "menu")
	var close: Button = (view["host"] as Control).get_node("Panel/Content/Header/Close") as Button
	assert_eq(close.text, "Close")
	assert_eq(close.get_parent().get_child(close.get_parent().get_child_count() - 1), close,
		"Close is the last header control, at the top right")
	close.pressed.emit()
	assert_false(main.call("is_menu_visible"))
	assert_true(main.call("set_menu_visible", true))
	await _key(main, KEY_ESCAPE)
	assert_false(main.call("is_menu_visible"))


func _main() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1600, 900)
	host.gui_embed_subwindows = true
	_nodes.append(host)
	tree.root.add_child(host)
	var window: Window = Window.new()
	window.borderless = true
	window.size = host.size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	host.add_child(window)
	window.show()
	var main: Node = MAIN.instantiate()
	main.set("use_saves", false)
	main.set("skip_owner_picker", true)
	main.set("new_game_seed_override", 1)
	window.add_child(main)
	main.call("start")
	Clock.set_speed(0)
	await _frames()
	return main


## Opens one panel through Main and names a header, body and footer point.
func _open(main: Node, panel_name: String) -> Dictionary:
	var view: Dictionary = {}
	match panel_name:
		"menu":
			assert_true(main.call("set_menu_visible", true))
			var menu: Control = main.get_node("Overlay/MenuPanel") as Control
			view = {"host": menu, "frame": menu.get_node("Panel"), "header": menu.get_node("Panel/Content/Header/Close"),
				"body": menu.get_node("Panel/Content/Body/Scroll"), "footer": &"bottom",
				"extra": [menu.get_node("Panel/Content/Body/DetailScroll")] as Array[ScrollContainer]}
		"stock":
			assert_true(main.call("set_stock_visible", true))
			var stock: Control = main.get_node("Overlay/StockPanel") as Control
			view = {"host": stock, "frame": stock.get_node("Panel"), "header": stock.get_node("%Close"),
				"body": stock.get_node("Panel/Content/Scroll"), "footer": stock.get_node("%Cancel")}
		"staff":
			assert_true(main.call("set_staff_visible", true))
			var staff: Control = main.get_node("Overlay/StaffPanel") as Control
			view = {"host": staff, "frame": staff.get_node("Panel"), "header": staff.get_node("%Close"),
				"body": staff.get_node("Panel/Content/Scroll"), "footer": &"bottom"}
		"goals":
			assert_true(main.call("set_goals_visible", true))
			var goals: Control = main.get_node("Overlay/GoalsPanel") as Control
			view = {"host": goals, "frame": goals.get_node("Panel"), "header": goals.get_node("Panel/Content/Header/Close"),
				"body": goals.get_node("Panel/Content/Scroll"), "footer": &"bottom"}
		"property":
			# Explicit fixture: the market shows from career Tier 3.
			(main.get("owner_progress") as OwnerProgress).career_tier = 3
			assert_true(main.call("set_property_visible", true))
			var property: Control = main.get_node("Overlay/PropertyPanel") as Control
			view = {"host": property, "frame": property.get_node("Panel"),
				"header": property.get_node("Panel/Content/Header/Close"),
				"body": property.get_node("Panel/Content/Scroll"), "footer": &"bottom"}
		"report":
			main.call("_show_evening_report", main.call("build_report", Clock.sim.day))
			var report: Control = main.get_node("Overlay/EveningReport") as Control
			view = {"host": report, "frame": report.get_node("Panel"), "header": report.get_node("%Close"),
				"body": report.get_node("Panel/Column/Scroll"), "footer": &"bottom"}
		"settings":
			assert_true(main.call("set_settings_visible", true))
			var settings: Control = main.get_node("Overlay/SettingsPanel") as Control
			view = {"host": settings, "frame": settings.get_node("Panel"), "header": settings.get_node("%CloseButton"),
				"body": settings.get_node("%MasterSlider"), "footer": settings.get_node("%QuitToTitleButton")}
		"catalogue":
			assert_true(main.call("set_build_active", true))
			var catalogue: Control = main.get_node("Overlay/BuildCatalogue") as Control
			view = {"host": catalogue, "frame": catalogue.get_node("Panel"), "header": &"top",
				"body": catalogue.get_node("Panel/Margin/Rows/Scroll"), "footer": &"bottom"}
	await _frames()
	var frame: Control = view["frame"] as Control
	var rect: Rect2 = frame.get_global_rect()
	for spot: String in ["header", "body", "footer"]:
		var where: Variant = view[spot]
		if where is Control:
			view[spot] = (where as Control).get_global_rect().get_center()
		elif where == &"top":
			view[spot] = Vector2(rect.get_center().x, rect.position.y + 3.0)
		else:
			# Inside the card's own padding, below every control.
			view[spot] = Vector2(rect.get_center().x, rect.end.y - 3.0)
	return view


func _close(main: Node, panel_name: String, view: Dictionary) -> void:
	var host: Control = view["host"]
	match panel_name:
		"menu", "report":
			(host.get_node("%Close") as Button).pressed.emit()
		"stock", "staff":
			(host.get_node("%Close") as Button).pressed.emit()
		"goals", "property":
			(host.get_node("Panel/Content/Header/Close") as Button).pressed.emit()
		"settings":
			(host.get_node("%CloseButton") as Button).pressed.emit()
		"catalogue":
			main.call("set_build_active", false)
	# Property returns to the morning Menu; close that too.
	if main.call("is_menu_visible"):
		main.call("set_menu_visible", false)
	await _frames()


func _first_scroll(node: Node) -> ScrollContainer:
	for child: Node in node.get_children(true):
		if child is ScrollContainer:
			return child as ScrollContainer
		var found: ScrollContainer = _first_scroll(child)
		if found != null:
			return found
	return null


func _helper(host: Control) -> PanelScroll:
	for child: Node in host.get_children(true):
		if child is PanelScroll:
			return child as PanelScroll
	return null


## Explicit presentation fixture: at least four steps of room to scroll.
func _make_room(scroll: ScrollContainer) -> void:
	var content: Control = null
	for child: Node in scroll.get_children():
		if child is Control:
			content = child as Control
			break
	if content == null:
		return
	content.custom_minimum_size.y = maxf(content.custom_minimum_size.y, scroll.size.y + PanelScroll.WHEEL_STEP * 6.0)
	await _frames()


func _values(root: Node) -> Dictionary:
	var out: Dictionary = {}
	_collect(root, root, out)
	return out


func _collect(root: Node, node: Node, out: Dictionary) -> void:
	var key: String = String(root.get_path_to(node))
	if node is ScrollBar:
		return
	if node is Range:
		out[key] = (node as Range).value
	elif node is OptionButton:
		out[key] = (node as OptionButton).selected
	elif node is BaseButton:
		out[key] = (node as BaseButton).button_pressed
	elif node is LineEdit:
		out[key] = (node as LineEdit).text
	elif node is Tree:
		var selected: TreeItem = (node as Tree).get_selected()
		out[key] = selected.get_text(0) if selected != null else ""
	for child: Node in node.get_children():
		_collect(root, child, out)


func _wheel(main: Node, point: Vector2, button: MouseButton) -> void:
	var window: Window = main.get_viewport() as Window
	var viewport: Viewport = window.get_parent() as Viewport
	var at: Vector2 = window.get_final_transform() * point + Vector2(window.position)
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	viewport.push_input(move, true)
	for down: bool in [true, false]:
		var wheel: InputEventMouseButton = InputEventMouseButton.new()
		wheel.button_index = button
		wheel.position = at
		wheel.global_position = at
		wheel.pressed = down
		wheel.factor = 1.0
		viewport.push_input(wheel, true)
	await _frames()


func _key(main: Node, code: Key) -> void:
	var window: Window = main.get_viewport() as Window
	for down: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = down
		window.push_input(key, true)
	await _frames()


func _frames() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for frame: int in range(4):
		await tree.process_frame
