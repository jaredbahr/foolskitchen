extends SceneTree
## Manual FK-099 (#187) captures (not run in CI): a visible delivery in the real
## Main scene. Run under a virtual display, like tools/screenshot.sh:
##   xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 \
##     --resolution 1600x900 --audio-driver Dummy --script tools/delivery_shots.gd -- \
##     <out dir> [north|east] [up|cutaway]
## Builds a back door in the kitchen's north wall (or the dining room's east
## wall), orders cheese and bread during service, and saves the 14:00 delivery:
## the delivery person outside, in the open door, setting crates down, and a
## staff member carrying a crate to storage, each wide and close up, plus
## frame-by-frame sequences of the door swing and a carried crate (seq_*).
## The core loads after the autoloads exist.


func _initialize() -> void:
	await process_frame
	var core: Object = (load("res://tools/delivery_shots_core.gd") as GDScript).new()
	await core.call("run", self)
	quit()
