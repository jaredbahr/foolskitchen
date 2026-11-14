extends "res://src/ui/hud.gd"
## Avoid repainting the HUD on every tick during the capture's synchronous service run.
## The fixture plays up to 30 days in one call before any frame is drawn, and the
## per-tick top-bar refresh was a large share of that time on slow runners. The
## capture therefore no longer exercises the per-tick HUD refresh: it switches it
## back on and calls refresh() once before frame 60, so the picture is the normal HUD.

var skip_tick_refresh: bool = false


func _on_sim_ticked(tick: int) -> void:
	if not skip_tick_refresh:
		super._on_sim_ticked(tick)
