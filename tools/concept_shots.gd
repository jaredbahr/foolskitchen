extends SceneTree
## Manual FK-083 captures (not run in CI): a probe concept set-up in the real
## Main scene. Run under a virtual display, like tools/screenshot.sh:
##   xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 \
##     --resolution 1600x900 --audio-driver Dummy --script tools/concept_shots.gd -- \
##     <out dir> <coffee_shop|bar|default> <service ticks> [seed] [menu|catalogue]
## Service shots: <setup>_full.png, then close-ups from all four camera
## quarters (<setup>_close.png, _close_q1..q3). "menu" captures the morning
## Menu panel top (opening hours) and its end (Drinks); "catalogue" the Buy
## mode Bar & Café tab. The core loads after the autoloads exist.


func _initialize() -> void:
	await process_frame
	var core: Object = (load("res://tools/concept_shots_core.gd") as GDScript).new()
	await core.call("run", self)
	quit()
