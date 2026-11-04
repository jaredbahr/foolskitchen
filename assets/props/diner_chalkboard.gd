extends Label3D
## Label3D has no Control theme lookup. Give it the same font resource that the
## shared UI theme uses, falling back to ThemeDB's standard font when unset.

const FITTED_FONT_SIZE: int = 48
const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")


func _init() -> void:
	var shared_font: Font = SHARED_THEME.default_font
	if shared_font == null:
		shared_font = ThemeDB.fallback_font
	font = shared_font


## Only a placed board calls this. The wrapper keeps its authored preview.
func set_menu_board_text(value: String) -> void:
	font_size = MenuBoardText.FONT_SIZE
	pixel_size = MenuBoardText.PIXEL_SIZE
	text = value


## A street A-frame line: one size per line, as large as the room allows.
func set_fitted_text(value: String, max_width_m: float, max_height_m: float) -> void:
	font_size = FITTED_FONT_SIZE
	text = value
	var line_width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, FITTED_FONT_SIZE).x
	var line_height: float = font.get_height(FITTED_FONT_SIZE)
	pixel_size = minf(max_width_m / maxf(line_width, 1.0), max_height_m / maxf(line_height, 1.0))
