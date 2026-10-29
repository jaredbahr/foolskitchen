class_name MenuBoardText
extends RefCounted
## Read-only words for one placed menu board. The caller passes today's enabled
## dishes; the same section choice can be used by inspection and the 3D view.

## The chalkboard's dark face is 0.59 by 0.45 metres. Leave a 0.02-metre
## margin on either side, and room vertically for name, section and four dishes.
const FONT_SIZE: int = 25
const PIXEL_SIZE: float = 0.002
const MAX_LINE_WIDTH_M: float = 0.55
const FACE_HEIGHT_M: float = 0.45
const MAX_DISHES: int = 4
const ELLIPSIS: String = "…"
const THEME: Theme = preload("res://src/ui/theme/main_theme.tres")


## -1 means automatic. An explicit valid section stays selected even when its
## dishes leave today's menu, so the board does not jump to another section.
static func selected_section(menu: Array[RecipeDef], requested: int = -1) -> int:
	if RecipeDef.Section.values().has(requested):
		return requested
	for section: int in RecipeDef.Section.values():
		for recipe: RecipeDef in menu:
			if recipe != null and recipe.menu_section() == section:
				return section
	return -1


static func text(restaurant_name: String, menu: Array[RecipeDef], requested: int = -1) -> String:
	var section: int = selected_section(menu, requested)
	var name: String = _one_line(restaurant_name)
	if name.is_empty():
		name = MenuSettings.DEFAULT_NAME
	var lines: Array[String] = [_fit(name)]
	lines.append(_fit(RecipeDef.section_name(section) if section >= 0 else "Today's menu"))
	var dishes: Array[RecipeDef] = []
	for recipe: RecipeDef in menu:
		if recipe != null and recipe.menu_section() == section:
			dishes.append(recipe)
	dishes.sort_custom(_recipe_before)
	if dishes.is_empty():
		lines.append("No dishes today")
	else:
		for index: int in mini(dishes.size(), MAX_DISHES):
			lines.append(_fit("• " + _one_line(dishes[index].display_name)))
	return "\n".join(lines)


static func _recipe_before(first: RecipeDef, second: RecipeDef) -> bool:
	return String(first.id) < String(second.id)


static func _one_line(value: String) -> String:
	return value.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()


static func _fit(value: String) -> String:
	var font: Font = THEME.default_font if THEME.default_font != null else ThemeDB.fallback_font
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x * PIXEL_SIZE <= MAX_LINE_WIDTH_M:
		return value
	var remaining: String = value
	while not remaining.is_empty():
		remaining = remaining.left(remaining.length() - 1).strip_edges(false, true)
		var candidate: String = remaining + ELLIPSIS
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x * PIXEL_SIZE <= MAX_LINE_WIDTH_M:
			return candidate
	return ELLIPSIS
