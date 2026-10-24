class_name IconStyle
extends RefCounted
## One presentation path for Kenney icons. It inherits every tint from the
## existing warm theme; it never introduces a colour or replaces the font.

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")


## Returns whether an icon was applied. Keep a text label for missing icons.
## An icon-only button always gets a tooltip, even if the caller omits one.
static func configure_button(
		button: Button, role: StringName, label: String, tooltip: String,
		pixel_size: int = IconCatalogue.TOP_BAR_SIZE, icon_only: bool = false
	) -> bool:
	var texture: Texture2D = IconCatalogue.texture_for(role)
	var fallback_label: String = label
	if fallback_label.is_empty():
		fallback_label = String(role).replace("_", " ").capitalize()
	if fallback_label.is_empty():
		fallback_label = "Control"
	button.icon = texture
	button.tooltip_text = tooltip if not tooltip.is_empty() else fallback_label
	if texture == null:
		button.text = fallback_label
		button.expand_icon = false
		button.remove_theme_constant_override("icon_max_width")
		return false
	button.text = "" if icon_only else fallback_label
	# Native fixed-size icons contribute to the button minimum. Expanded icons
	# reserve no width and disappear when a text button receives that minimum.
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", pixel_size)
	for state: StringName in [
		&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus",
	]:
		var font_colour: StringName = &"font_color"
		if state != &"normal" and state != &"focus":
			font_colour = StringName("font_%s_color" % state)
		button.add_theme_color_override(
			"icon_%s_color" % state,
			_palette(button).get_color(font_colour, "Button")
		)
	return true


## Callers place this beside their existing heading text; null means text only.
static func heading_icon(role: StringName, heading: Control) -> TextureRect:
	var texture: Texture2D = IconCatalogue.texture_for(role)
	if texture == null:
		return null
	var icon: TextureRect = TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(IconCatalogue.PANEL_SIZE, IconCatalogue.PANEL_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = _palette(heading).get_color("font_color", "Label")
	return icon


## Compact padding keeps the shared palette and native 46px touch height.
static func compact_button(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 46.0)
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style: StyleBox = _palette(button).get_stylebox(state, "Button").duplicate() as StyleBox
		style.set_content_margin(SIDE_LEFT, 6.0)
		style.set_content_margin(SIDE_RIGHT, 6.0)
		style.set_content_margin(SIDE_TOP, 9.0)
		style.set_content_margin(SIDE_BOTTOM, 9.0)
		button.add_theme_stylebox_override(state, style)


## Decorate the existing Label so its public node path and type stay stable.
## Label's native style margins reserve the icon's room in its minimum size.
static func decorate_label(label: Label, role: StringName, pixel_size: int = IconCatalogue.PANEL_SIZE) -> bool:
	var icon: TextureRect = label.get_node_or_null("ThemeIcon") as TextureRect
	if not label.has_meta(&"icon_base_style"):
		label.set_meta(&"icon_base_style", label.get_theme_stylebox("normal").duplicate())
	var style: StyleBox = (label.get_meta(&"icon_base_style") as StyleBox).duplicate() as StyleBox
	var texture: Texture2D = IconCatalogue.texture_for(role)
	if texture == null:
		if icon != null:
			icon.hide()
		label.add_theme_stylebox_override("normal", style)
		return false
	if icon == null:
		icon = TextureRect.new()
		icon.name = "ThemeIcon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_child(icon)
	var left: float = style.get_content_margin(SIDE_LEFT)
	style.set_content_margin(SIDE_LEFT, left + float(pixel_size) + 6.0)
	label.add_theme_stylebox_override("normal", style)
	label.custom_minimum_size.y = maxf(label.custom_minimum_size.y, float(pixel_size))
	icon.texture = texture
	icon.modulate = _palette(label).get_color("font_color", "Label")
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = left
	icon.offset_right = left + float(pixel_size)
	icon.offset_top = -float(pixel_size) * 0.5
	icon.offset_bottom = float(pixel_size) * 0.5
	icon.show()
	return true


## Assigned resources are reliable even before Control's theme cache enters a tree.
static func _palette(control: Control) -> Theme:
	var current: Node = control
	while current != null:
		var parent_control: Control = current as Control
		if parent_control != null and parent_control.theme != null:
			return parent_control.theme
		current = current.get_parent()
	return SHARED_THEME
