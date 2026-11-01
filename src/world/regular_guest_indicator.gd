class_name RegularGuestIndicator
extends Node3D
## Same native billboard mechanism as GuestMoodIndicator, following the drawn
## person. Greeting time comes from sim ticks, so pausing does not consume it.

const STAR: Texture2D = preload("res://assets/kenney/icons/star.png")
const CREAM: SwatchDef = preload("res://data/swatches/cream.tres")
const HONEY: SwatchDef = preload("res://data/swatches/honey.tres")
const INK: SwatchDef = preload("res://data/swatches/charcoal.tres")

var star: Sprite3D
var name_label: Label3D
var greeting: Label3D


func _init() -> void:
	name = "RegularIndicator"
	star = Sprite3D.new()
	star.name = "Star"
	star.texture = STAR
	star.pixel_size = 0.0013
	star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	star.no_depth_test = true
	star.shaded = false
	star.modulate = HONEY.color
	star.position.y = -0.07
	add_child(star)
	name_label = _label("RegularName", 0.06)
	greeting = _label("Greeting", 0.22)


func present(person_name: String, words: String, greeting_visible: bool) -> void:
	if name_label.text != person_name:
		name_label.text = person_name
	if greeting.text != words:
		greeting.text = words
	greeting.visible = greeting_visible and not words.is_empty()


func _label(node_name: String, height: float) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = node_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 32
	label.pixel_size = 0.0023
	label.modulate = CREAM.color
	label.outline_modulate = INK.color
	label.outline_size = 8
	label.render_priority = 2
	label.outline_render_priority = 1
	label.position.y = height
	add_child(label)
	return label
