class_name GuestMoodIndicator
extends Node3D
## Native placeholder dot and portable billboard text; no imported assets.

const COLORS: Array[Color] = [Color("38764b"), Color("c9a346"), Color("c8743a"), Color("a83e35")]
const MARKS: Array[String] = ["", "", "!", "!!"]
const HEAD_OFFSET: float = 1.25

var band: int = -1
## Counts actual band presentation changes, independently of rendered frames.
var updates: int = 0
var dot: MeshInstance3D
var mark: Label3D
var _material: StandardMaterial3D


func _init() -> void:
	name = "MoodIndicator"
	position.y = HEAD_OFFSET
	dot = MeshInstance3D.new()
	dot.name = "Dot"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	sphere.radial_segments = 16
	sphere.rings = 6
	dot.mesh = sphere
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.no_depth_test = true
	dot.material_override = _material
	add_child(dot)
	mark = Label3D.new()
	mark.name = "Mark"
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.font_size = 64
	mark.pixel_size = 0.004
	mark.modulate = Color("f3e6cc")
	mark.outline_modulate = Color("3b2a20")
	mark.outline_size = 8
	mark.render_priority = 2
	mark.outline_render_priority = 1
	mark.hide()
	add_child(mark)


func set_band(value: int) -> bool:
	if value < 0 or value >= COLORS.size() or value == band:
		return false
	band = value
	_material.albedo_color = COLORS[band]
	mark.text = MARKS[band]
	mark.visible = not mark.text.is_empty()
	updates += 1
	return true
