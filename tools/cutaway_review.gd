extends "res://src/world/main.gd"
## Explicit, unsaved display fixture for #205, not a service or balance claim.
## The walls-review morning edits (an interior wall with finishes and hung
## decor) seen in Cutaway: walls in front of the camera focus lower, walls
## behind it stay up with their decor. Capture with --quarter=0..3.

const WALLS_REVIEW: Script = preload("res://tools/walls_review.gd")


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null:
		push_error("Cutaway review needs a fresh shop")
		return
	var prepared: Dictionary = WALLS_REVIEW.prepare(self, get_tree().root)
	if not String(prepared.get("error", "missing")).is_empty():
		push_error("Cutaway review could not prepare its walls: " + String(prepared.get("error", "")))
		return
	var view: ShopView = $ShopView as ShopView
	view.set_wall_mode(ShopView.WallMode.CUTAWAY)
	print("CUTAWAY_REVIEW ", JSON.stringify({"fixture": "seed 1; unsaved walls-review morning edits in Cutaway",
		"hung": prepared["hung"], "use_saves": use_saves}))


func _process(delta: float) -> void:
	super._process(delta)
	var view: ShopView = $ShopView as ShopView
	if Engine.get_process_frames() % 30 == 0:
		print("CUTAWAY_LOWERED ", JSON.stringify({"quarter": ($CameraRig as CameraRig).camera_quarter(),
			"focus_cell": view.cutaway_focus(), "lowered": view.lowered_interior_edges().keys()}))
