extends TestCase
## Approved assets, shared theme styling and actual panel heading integration.

const MAIN_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")


func test_every_mapped_icon_is_a_vendored_100_pixel_texture() -> void:
	for role: StringName in IconCatalogue.ICON_ROLES:
		var path: String = IconCatalogue.path_for(role)
		assert_true(path.begins_with(IconCatalogue.ROOT), "approved icon path for %s" % role)
		assert_true(ResourceLoader.exists(path, "Texture2D"), "vendored icon exists for %s" % role)
		var texture: Texture2D = IconCatalogue.texture_for(role)
		assert_not_null(texture, "icon loads for %s" % role)
		if texture != null:
			assert_eq(texture.get_size(), Vector2(100.0, 100.0), "pack dimensions for %s" % role)
	assert_eq(IconCatalogue.TOP_BAR_SIZE, 28)
	assert_eq(IconCatalogue.PANEL_SIZE, 24)


func test_button_icon_uses_context_size_theme_tints_and_readable_text() -> void:
	var button: Button = Button.new()
	button.theme = MAIN_THEME
	assert_true(IconStyle.configure_button(button, &"pause", "Pause", "Pause the day"))
	assert_not_null(button.icon)
	assert_eq(button.get_theme_constant("icon_max_width"), 28)
	assert_false(button.expand_icon, "the native minimum reserves the full scaled icon")
	assert_eq(button.text, "Pause")
	assert_eq(button.tooltip_text, "Pause the day")
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		var font_colour: StringName = &"font_color"
		if state != &"normal" and state != &"focus":
			font_colour = StringName("font_%s_color" % state)
		assert_eq(
			button.get_theme_color("icon_%s_color" % state),
			MAIN_THEME.get_color(font_colour, "Button"),
			"button icon tint inherits %s theme text" % state
		)
	assert_true(IconStyle.configure_button(
		button, &"menu", "Menu", "Choose menu", IconCatalogue.PANEL_SIZE
	))
	assert_eq(button.get_theme_constant("icon_max_width"), 24)
	button.free()


func test_text_button_minimum_reserves_its_icon_beside_the_complete_label() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var holder: Control = Control.new()
	holder.theme = MAIN_THEME
	tree.root.add_child(holder)
	var plain: Button = Button.new()
	plain.theme = MAIN_THEME
	plain.text = "Build"
	IconStyle.compact_button(plain)
	holder.add_child(plain)
	var decorated: Button = Button.new()
	decorated.theme = MAIN_THEME
	IconStyle.configure_button(decorated, &"build", "Build", "Build furniture")
	IconStyle.compact_button(decorated)
	holder.add_child(decorated)
	await tree.process_frame
	await tree.process_frame
	assert_true(plain.is_inside_tree() and decorated.is_inside_tree())
	assert_true(decorated.get_combined_minimum_size().x >= plain.get_combined_minimum_size().x + 28.0,
		"a native text+icon button cannot allocate its complete content width to text alone")
	assert_eq(decorated.get_combined_minimum_size().y, 46.0)
	assert_false(decorated.expand_icon)
	holder.free()


func test_icon_only_gets_a_tooltip_and_absent_roles_keep_text() -> void:
	var button: Button = Button.new()
	button.theme = MAIN_THEME
	assert_true(IconStyle.configure_button(button, &"pause", "Pause", "", 28, true))
	assert_eq(button.text, "")
	assert_eq(button.tooltip_text, "Pause")
	for role: StringName in [&"cash", &"paint", &"unknown"]:
		assert_eq(IconCatalogue.path_for(role), "", "no substitute icon for %s" % role)
		assert_false(IconStyle.configure_button(button, role, "Cash", "", 28, true))
		assert_null(button.icon)
		assert_eq(button.text, "Cash")
		assert_eq(button.tooltip_text, "Cash")
		assert_false(button.expand_icon)
	assert_true(IconStyle.configure_button(button, &"staff", "Staff", "Hire staff", 28))
	assert_not_null(button.icon)
	assert_eq(button.text, "Staff")
	assert_eq(button.tooltip_text, "Hire staff")
	assert_false(IconStyle.configure_button(button, &"cash", "", "", 28, true))
	assert_eq(button.text, "Cash")
	assert_eq(button.tooltip_text, "Cash")
	button.free()


func test_panel_heading_icon_keeps_label_colour_and_size() -> void:
	var heading: Label = Label.new()
	heading.theme = MAIN_THEME
	var icon: TextureRect = IconStyle.heading_icon(&"report", heading)
	assert_not_null(icon)
	if icon != null:
		assert_eq(icon.custom_minimum_size, Vector2(24.0, 24.0))
		assert_eq(icon.modulate, MAIN_THEME.get_color("font_color", "Label"))
		assert_eq(icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		icon.free()
	assert_null(IconStyle.heading_icon(&"paint", heading))
	heading.free()


func test_existing_panel_heading_paths_gain_one_icon_and_paint_keeps_text() -> void:
	var menu: MenuPanel = load("res://src/ui/menu_panel.tscn").instantiate() as MenuPanel
	menu.refresh()
	menu.refresh()
	_assert_heading(menu.get_node("Panel/Content/Title") as Label, "menuList.png")
	var settings: Button = menu.get_node("Panel/Content/SettingsButton") as Button
	assert_eq(settings.text, "Settings")
	assert_eq(settings.icon.resource_path, IconCatalogue.ROOT + "gear.png")
	assert_eq(settings.get_theme_constant("icon_max_width"), 24)
	menu.free()
	var catalogue: BuildCatalogue = load("res://src/ui/build_catalogue.tscn").instantiate() as BuildCatalogue
	catalogue.set_paint_visible(false)
	var title: Label = catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Title") as Label
	_assert_heading(title, "menuGrid.png")
	var furniture_minimum: Vector2 = title.get_combined_minimum_size()
	catalogue.set_paint_visible(true)
	assert_false((title.get_node("ThemeIcon") as Control).visible, "Paint keeps text until an approved brush exists")
	assert_true(title.text.begins_with("Paint |"))
	catalogue.set_paint_visible(false)
	_assert_heading(title, "menuGrid.png")
	assert_eq(title.get_combined_minimum_size(), furniture_minimum, "repeated heading decoration never accumulates padding")
	catalogue.free()
	var report: Control = load("res://src/ui/evening_report.tscn").instantiate() as Control
	report.call("show_report", DayReport.new())
	report.call("show_report", DayReport.new())
	_assert_heading(report.get_node("Panel/Scroll/Content/Header") as Label, "leaderboardsSimple.png")
	_assert_heading(report.get_node("Panel/Scroll/Content/ReviewHeading") as Label, "star.png")
	_assert_heading(report.get_node("Panel/Scroll/Content/GuestHeading") as Label, "singleplayer.png")
	assert_eq((report.get_node("Panel/Scroll/Content/NextDay") as Button).text, "Next day")
	report.free()


func test_staff_headings_keep_native_paths_padding_and_caches_after_roster_refresh() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var staff: StaffPanel = load("res://src/ui/staff_panel.tscn").instantiate() as StaffPanel
	tree.root.add_child(staff)
	var roster: StaffRoster = StaffRoster.new()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 107
	assert_true(roster.draw_candidates(1, random))
	staff.bind_roster(roster)
	await tree.process_frame
	await tree.process_frame
	var paths: Array[NodePath] = [^"Panel/Content/Title",
		^"Panel/Content/Scroll/List/RosterTitle", ^"Panel/Content/Scroll/List/CandidateTitle"]
	var labels: Array[Label] = []
	var icons: Array[TextureRect] = []
	var styles: Array[StyleBox] = []
	var fonts: Array[Font] = []
	var sizes: Array[int] = []
	var minima: Array[Vector2] = []
	for path: NodePath in paths:
		var label: Label = staff.get_node(path) as Label
		assert_true(label.is_inside_tree(), "theme and minimum checks use native scene caches")
		_assert_heading(label, "singleplayer.png")
		labels.append(label)
		icons.append(label.get_node("ThemeIcon") as TextureRect)
		styles.append(label.get_meta(&"icon_base_style") as StyleBox)
		fonts.append(label.get_theme_font("font"))
		sizes.append(label.get_theme_font_size("font_size"))
		minima.append(label.get_combined_minimum_size())
	assert_eq(sizes[0], 26, "the title keeps its authored font size")
	assert_eq(labels[0].text, "Staff")
	assert_true(labels[1].text.begins_with("Your team (2/6)"))
	assert_eq(labels[2].text, "Available this morning")
	staff.refresh()
	staff.refresh()
	staff.bind_roster(roster)
	await tree.process_frame
	for index: int in paths.size():
		assert_true(staff.get_node(paths[index]) == labels[index])
		assert_true(labels[index].get_node("ThemeIcon") == icons[index])
		assert_eq(labels[index].get_meta(&"icon_base_style"), styles[index])
		assert_eq(labels[index].get_combined_minimum_size(), minima[index],
			"repeated decoration never accumulates native heading padding")
	var candidate: StaffMember = roster.candidates()[0]
	assert_true(roster.hire(candidate.id))
	staff.refresh()
	staff.refresh()
	await tree.process_frame
	await tree.process_frame
	assert_true(labels[1].text.begins_with("Your team (3/6)"), "dynamic roster text still refreshes")
	assert_not_null(staff.row_for(candidate.id).get_node("Top/Name") as Label,
		"dynamic member rows retain their public paths")
	for index: int in paths.size():
		var label: Label = labels[index]
		_assert_heading(label, "singleplayer.png")
		assert_true(label.get_node("ThemeIcon") == icons[index])
		assert_eq(label.get_meta(&"icon_base_style"), styles[index])
		assert_eq(label.get_theme_font("font"), fonts[index])
		assert_eq(label.get_theme_font_size("font_size"), sizes[index])
		assert_almost_eq(label.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT),
			styles[index].get_content_margin(SIDE_LEFT) + 30.0)
		var plain: Label = Label.new()
		plain.theme = MAIN_THEME
		plain.text = label.text
		plain.add_theme_font_override("font", fonts[index])
		plain.add_theme_font_size_override("font_size", sizes[index])
		plain.add_theme_stylebox_override("normal", styles[index])
		tree.root.add_child(plain)
		await tree.process_frame
		assert_true(label.get_combined_minimum_size().x >= plain.get_combined_minimum_size().x + 30.0 - 0.5,
			"the native heading minimum reserves the complete icon and gap beside its text")
		assert_true(label.get_combined_minimum_size().y >= 24.0)
		plain.free()
	staff.free()


func _assert_heading(label: Label, filename: String) -> void:
	var icon: TextureRect = label.get_node("ThemeIcon") as TextureRect
	assert_true(icon.visible)
	assert_eq(icon.texture.resource_path, IconCatalogue.ROOT + filename)
	assert_eq(icon.size, Vector2(24.0, 24.0))
	assert_eq(icon.modulate, MAIN_THEME.get_color("font_color", "Label"))
	assert_eq(icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(label.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT) >= 30.0)
	assert_eq(label.get_child_count(), 1, "refresh retains one native icon under the original Label")
