extends "res://src/world/main.gd"
## Two review frames: original HUD, then the made icons with kit comparisons.
## Only presentation changes; the paused seeded shop never saves or advances.

const REVIEW_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const REFERENCES: Array[String] = ["wrench.png", "star.png", "home.png", "gear.png"]
const LABELS: Array[String] = ["Wrench", "Star", "Home", "Gear", "Chef hat", "Paint brush"]
var _review_strip: PanelContainer
var _review_frame: int = 0


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 118
	super._ready()
	Clock.set_speed(0)
	_build_review_strip()
	_show_made_icons(false)


func _process(delta: float) -> void:
	super._process(delta)
	_review_frame += 1
	if _review_frame == 30:
		_show_made_icons(true)


func _show_made_icons(enabled: bool) -> void:
	var staff: Button = $HUD/Top/Row/Staff as Button
	var paint: Button = $HUD/Top/Row/Paint as Button
	if enabled:
		$HUD.call("_style_header")
	else:
		staff.icon = load(IconCatalogue.ROOT + "singleplayer.png") as Texture2D
		paint.icon = null
		paint.text = "Paint"
	_review_strip.visible = enabled
	$HUD.call("_layout_header")
	print("ICONS_REVIEW ", JSON.stringify({"made_icons": enabled,
		"seed": 118, "world_tick": world.now, "use_saves": use_saves,
		"staff_icon": staff.icon.resource_path if staff.icon != null else "",
		"paint_icon": paint.icon.resource_path if paint.icon != null else "",
		"paint_tooltip": paint.tooltip_text}))


func _build_review_strip() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "IconComparison"
	layer.layer = 50
	add_child(layer)
	_review_strip = PanelContainer.new()
	_review_strip.theme = REVIEW_THEME
	_review_strip.anchor_top = 1.0
	_review_strip.anchor_bottom = 1.0
	_review_strip.offset_left = 16.0
	_review_strip.offset_right = 1030.0
	_review_strip.offset_top = -225.0
	_review_strip.offset_bottom = -16.0
	layer.add_child(_review_strip)
	var rows: VBoxContainer = VBoxContainer.new()
	_review_strip.add_child(rows)
	var title: Label = Label.new()
	title.text = "Kenney Game Icons and the two made icons (100 px)"
	rows.add_child(title)
	var strip: HBoxContainer = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 30)
	rows.add_child(strip)
	for index: int in LABELS.size():
		var column: VBoxContainer = VBoxContainer.new()
		column.custom_minimum_size.x = 125.0
		strip.add_child(column)
		var picture: TextureRect = TextureRect.new()
		picture.custom_minimum_size = Vector2(100, 100)
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.modulate = REVIEW_THEME.get_color("font_color", "Label")
		var path: String = IconCatalogue.ROOT + REFERENCES[index] if index < REFERENCES.size() \
			else "res://assets/made/icons/" + ("chefHat.png" if index == 4 else "paintBrush.png")
		# The original-main paired run only takes frame 12, with this strip hidden.
		if ResourceLoader.exists(path, "Texture2D"):
			picture.texture = load(path) as Texture2D
		column.add_child(picture)
		var caption: Label = Label.new()
		caption.text = LABELS[index]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
