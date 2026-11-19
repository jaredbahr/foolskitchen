class_name GuestQuirkBadge
extends Sprite3D
## The small round badge a guest's quirk shows above their mood dot (#661).
## One shared view for every quirk: the picture comes from GuestQuirk.badge, so
## a new quirk adds a badge through data. Same native billboard mechanism as
## GuestMoodIndicator; it is that indicator's child, so it moves, hides and
## goes away with the mood dot.

## 64 px badge at 0.0072 is 0.46 world units: about 27 px on screen at
## the default zoom, where the mood dot is 11 px and a smaller icon turns to mush.
const PIXEL_SIZE: float = 0.0072
## Lifts the badge's centre in sprite pixels: clear of the dot's top edge.
const LIFT_PIXELS: float = 50.0

var quirk: GuestQuirk = null


func _init() -> void:
	name = "QuirkBadge"
	pixel_size = PIXEL_SIZE
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	shaded = false
	render_priority = 2
	offset = Vector2(0.0, LIFT_PIXELS)
	hide()


## Idempotent: safe to call every frame, only touches the node on a change.
func set_quirk(value: GuestQuirk) -> void:
	if value == quirk:
		return
	quirk = value
	texture = value.badge if value != null else null
	visible = texture != null
