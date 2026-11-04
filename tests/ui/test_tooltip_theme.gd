extends TestCase
## Resolve shared tooltip roles through controls, including engine fallbacks.

const SHARED: Theme = preload("res://src/ui/theme/main_theme.tres")


func test_shared_tooltips_use_opaque_approved_panels_and_readable_ink() -> void:
	var controls: Array[Control] = [Label.new(), Button.new()]
	for control: Control in controls:
		control.theme = SHARED
		var panel: StyleBoxFlat = control.get_theme_stylebox("panel", "TooltipPanel") as StyleBoxFlat
		var approved: StyleBoxFlat = control.get_theme_stylebox("panel", "PanelContainer") as StyleBoxFlat
		assert_almost_eq(panel.bg_color.a, 1.0, 0.001, "help must remain readable over any world background")
		assert_eq(panel.bg_color, approved.bg_color, "tooltips reuse the existing warm panel palette")
		var background: float = panel.bg_color.srgb_to_linear().get_luminance()
		var approved_ink: Color = control.get_theme_color("font_color", "Label")
		for role: StringName in [&"Label", &"TooltipLabel"]:
			var ink: Color = control.get_theme_color("font_color", role)
			assert_eq(ink, approved_ink, "tooltip text stays in the approved ink palette")
			var foreground: float = ink.srgb_to_linear().get_luminance()
			var contrast: float = (maxf(foreground, background) + 0.05) / (minf(foreground, background) + 0.05)
			assert_true(contrast >= 4.5, "%s tooltip ink needs readable contrast (%.2f:1)" % [role, contrast])
		control.free()
