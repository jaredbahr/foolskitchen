extends "res://src/world/main.gd"
## Unsaved review fixture. The score comes from ten placed lamps and the
## recognition from a staged favorable review through the normal close.

const AWARD_LINE: String = "The critic awarded your kitchen two Golden Ladles!"
var _review_frame: int = 0
var _review_active: bool = false


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 407
	super._ready()
	Clock.set_speed(0)
	var pendant: ItemDef = content.item(&"lamp_pendant")
	var placed: int = 0
	for cell: Vector2i in world.grid.cells():
		if world.grid.place_def(pendant, cell) != null:
			placed += 1
		if placed == 10:
			break
	if placed != 10:
		push_error("Prestige review: ten pendants did not fit.")
		return
	sim.spawner.min_gap = 100000
	sim.spawner.max_gap = 100000
	sim.spawner.reset()
	Clock.sim.open_ticks = 1
	Clock.sim.last_orders_max_ticks = 1
	if not Clock.sim.start_service():
		push_error("Prestige review: service did not open.")
		return
	var visit: ReviewVisit = ReviewVisit.new()
	visit.served = true
	visit.quality = 0.95
	visit.quality_weight = sim.critic.tuning.quality_weight
	sim._record_critic_review(visit)
	run_ticks(3)
	if sim.critic.golden_ladles != 2 or not set_goals_visible(true):
		push_error("Prestige review: the award or Goals panel is unavailable.")
		return
	_review_active = true


func _process(_delta: float) -> void:
	if not _review_active:
		return
	_review_frame += 1
	if _review_frame == 25:
		var goals: Label = _goals_panel.get_node("%GoldenLadles") as Label
		if not goals.is_visible_in_tree() or goals.text != "Golden Ladles: 2 of 3":
			push_error("Prestige review: the Goals line is missing.")
			return
		print("PRESTIGE_REVIEW goals: Golden Ladles: 2 of 3")
	elif _review_frame == 55:
		if not set_goals_visible(false):
			push_error("Prestige review: Goals did not close.")
	elif _review_frame == 65:
		var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
		scroll.ensure_control_visible(_report.get("critic_summary") as Label)
	elif _review_frame == 82:
		var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
		var summary: Label = _report.get("critic_summary") as Label
		if not summary.is_visible_in_tree() or not summary.text.contains(AWARD_LINE) \
				or not scroll.get_global_rect().grow(1.0).encloses(summary.get_global_rect()):
			push_error("Prestige review: the award line is missing or clipped.")
			return
		print("PRESTIGE_REVIEW report: " + AWARD_LINE)
