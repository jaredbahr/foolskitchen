extends Label3D
## Label3D has no Control theme lookup. Give it the same font resource that the
## shared UI theme uses, falling back to ThemeDB's standard font when unset.

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
