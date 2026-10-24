class_name ProgressionTuning
extends Resource
## Owner XP rates and the total-XP level curve, authored in progression.tres.

@export_range(0, 1000, 1) var happy_guest_xp: int = 2
@export_range(1, 1000000, 1) var profit_step: int = 10
@export_range(0, 1000, 1) var profit_step_xp: int = 1
@export_range(0, 1000, 1) var five_star_review_xp: int = 3
## Level N starts at ceil(level_base * N^level_exponent) total XP.
## Day milestones still need the seeds 1/7/42 balance probe.
@export_range(1, 1000000, 1) var level_base: int = 24
@export_range(1.0, 4.0, 0.1) var level_exponent: float = 2.0


func is_valid() -> bool:
	return happy_guest_xp >= 0 and happy_guest_xp <= 1000 \
		and profit_step >= 1 and profit_step <= 1000000 \
		and profit_step_xp >= 0 and profit_step_xp <= 1000 \
		and five_star_review_xp >= 0 and five_star_review_xp <= 1000 \
		and level_base >= 1 and level_base <= 1000000 \
		and is_finite(level_exponent) and level_exponent >= 1.0 and level_exponent <= 4.0
