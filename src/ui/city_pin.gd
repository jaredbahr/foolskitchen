class_name CityPin
extends Button
## One pin on the city map (docs/CITY_MAP.md section 2.1): a neighbourhood
## label, one of your restaurants, a lot for sale or a locked lot. Plain until
## the art pass: each kind takes a texture through `icons` (the director's
## paper-map pins), else it shows its title as a flat button. Pressing it
## asks the city screen to show that row.

signal pin_pressed(row_id: StringName)

const AREA: StringName = &"area"
const SHOP: StringName = &"shop"
const FOR_SALE: StringName = &"for_sale"
const LOCKED: StringName = &"locked"
const KINDS: Array[StringName] = [AREA, SHOP, FOR_SALE, LOCKED]

## Kind -> the pin's art (null keeps the plain button).
@export var icons: Dictionary[StringName, Texture2D] = {}

var row_id: StringName = &""
var kind: StringName = SHOP


func _ready() -> void:
	pressed.connect(_on_pressed)


## `badge` is a short state word under a shop pin ("Here", "Managed"...).
func set_pin(id: StringName, pin_kind: StringName, title: String, badge: String = "") -> void:
	row_id = id
	kind = pin_kind if KINDS.has(pin_kind) else SHOP
	text = title if badge.is_empty() else "%s\n%s" % [title, badge]
	tooltip_text = title
	icon = icons.get(kind, null)
	focus_mode = Control.FOCUS_NONE


func _on_pressed() -> void:
	pin_pressed.emit(row_id)
