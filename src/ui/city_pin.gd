class_name CityPin
extends Button
## One pin on the city map (docs/CITY_MAP.md section 2.1): a neighbourhood
## label, one of your restaurants, a lot for sale or a locked lot. Shops, boards
## and padlocks are the painted pins in assets/made/city_map/ (built by
## tools/build_city_map.py); a shop's picture follows its state. A neighbourhood
## pin is only a hit area over the name lettered on the map. Pressing a pin asks
## the city screen to show that row.

signal pin_pressed(row_id: StringName)

const AREA: StringName = &"area"
const SHOP: StringName = &"shop"
const FOR_SALE: StringName = &"for_sale"
const LOCKED: StringName = &"locked"
const KINDS: Array[StringName] = [AREA, SHOP, FOR_SALE, LOCKED]

## A shop pin's state: the badge picture on the little shopfront.
const HERE: StringName = &"here"
const MANAGED: StringName = &"managed"
const CLOSED: StringName = &"closed"
const RENOVATING: StringName = &"renovating"
const NEEDS: StringName = &"needs"

const SHOP_ART: Dictionary = {
	&"here": preload("res://assets/made/city_map/pin_here.png"),
	&"managed": preload("res://assets/made/city_map/pin_managed.png"),
	&"closed": preload("res://assets/made/city_map/pin_closed.png"),
	&"renovating": preload("res://assets/made/city_map/pin_renovating.png"),
	&"needs": preload("res://assets/made/city_map/pin_needs.png"),
}
const FOR_SALE_ART: Texture2D = preload("res://assets/made/city_map/pin_for_sale.png")
const LOCKED_ART: Texture2D = preload("res://assets/made/city_map/pin_locked.png")

## The UI's inks (main_theme.tres), so a pin reads on the paper.
const INK: Color = Color("3b2a20")
const CREAM: Color = Color("f3e6cc")

## Kind -> an art override (empty uses the painted pins above).
@export var icons: Dictionary[StringName, Texture2D] = {}

var row_id: StringName = &""
var kind: StringName = SHOP
var state: StringName = &""
## The title and the state word, kept apart so a small map can show the word alone.
var title: String = ""
var badge: String = ""


func _ready() -> void:
	pressed.connect(_on_pressed)
	_style()


## `badge` is a short state word under a shop pin ("Here", "Managed"...) and
## `pin_state` the picture to match (HERE, MANAGED...).
func set_pin(id: StringName, pin_kind: StringName, pin_title: String, pin_badge: String = "",
		pin_state: StringName = &"") -> void:
	row_id = id
	kind = pin_kind if KINDS.has(pin_kind) else SHOP
	state = pin_state
	title = pin_title
	badge = pin_badge
	text = _label(false)
	tooltip_text = pin_title if pin_badge.is_empty() else "%s (%s)" % [pin_title, pin_badge]
	icon = _art()
	focus_mode = Control.FOCUS_NONE
	_style()


## A small map shows the state word alone; the card under the map has the name.
func set_compact(compact: bool) -> void:
	if kind == AREA:
		return
	text = _label(compact)


## The words under the picture. A board or padlock already says "for sale" or
## "locked" in paint, so it keeps only the name; a shop adds its state word.
func _label(compact: bool) -> String:
	var word: String = badge if kind == SHOP else ""
	if compact:
		# A small map has no room for names: a shop keeps its state word, a
		# board or padlock only its picture (the card under the map has the rest).
		return word
	return title if word.is_empty() else "%s\n%s" % [title, word]


func _art() -> Texture2D:
	if icons.has(kind):
		return icons[kind]
	match kind:
		FOR_SALE:
			return FOR_SALE_ART
		LOCKED:
			return LOCKED_ART
		SHOP:
			return SHOP_ART.get(state, SHOP_ART[CLOSED]) as Texture2D
	return null


func _style() -> void:
	flat = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	# A neighbourhood's hit area takes the size the map gives it, whatever its text.
	autowrap_mode = TextServer.AUTOWRAP_OFF if kind == AREA else TextServer.AUTOWRAP_WORD_SMART
	clip_text = kind == AREA
	var hover: StyleBoxFlat = StyleBoxFlat.new()
	hover.set_corner_radius_all(10)
	for slot: StringName in [&"normal", &"pressed", &"disabled", &"focus"]:
		add_theme_stylebox_override(slot, StyleBoxEmpty.new())
	if kind == AREA:
		# Only a hit area over the lettering on the map: no text of its own.
		hover.bg_color = Color(1, 1, 1, 0.14)
		hover.set_border_width_all(3)
		hover.border_color = Color(INK, 0.7)
		var ghost: Color = Color(0, 0, 0, 0)
		for slot: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
				&"font_hover_pressed_color", &"font_disabled_color"]:
			add_theme_color_override(slot, ghost)
		add_theme_constant_override(&"outline_size", 0)
		# So its text asks for no room: the map decides the size.
		add_theme_font_size_override(&"font_size", 1)
	else:
		hover.bg_color = Color(CREAM, 0.5)
		for slot: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
				&"font_hover_pressed_color", &"font_disabled_color"]:
			add_theme_color_override(slot, INK)
		add_theme_color_override(&"font_outline_color", CREAM)
		add_theme_constant_override(&"outline_size", 6)
	add_theme_stylebox_override(&"hover", hover)
	add_theme_stylebox_override(&"hover_pressed", hover)
	add_theme_constant_override(&"h_separation", 0)


func _on_pressed() -> void:
	pin_pressed.emit(row_id)
