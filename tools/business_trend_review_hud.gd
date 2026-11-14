extends "res://src/ui/hud.gd"
## Avoid repainting the HUD on every tick during the capture's synchronous service run.

var skip_tick_refresh: bool = false


func _on_sim_ticked(tick: int) -> void:
	if not skip_tick_refresh:
		super._on_sim_ticked(tick)
