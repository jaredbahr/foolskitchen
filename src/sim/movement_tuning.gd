class_name MovementTuning
extends Resource
## Deterministic traffic policy. No random jitter or per-agent streams.

@export_range(1, 120, 1) var repath_after_ticks: int = 6
@export_range(1, 240, 1) var yield_after_ticks: int = 10
@export_range(1, 32, 1) var yield_search_radius: int = 8
@export_range(1, 128, 1) var admission_search_radius: int = 32


func is_valid() -> bool:
	return repath_after_ticks > 0 and yield_after_ticks >= repath_after_ticks \
		and yield_search_radius > 0 and admission_search_radius > 0
