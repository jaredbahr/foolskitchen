extends "res://src/world/main.gd"
## Unsaved review fixture. A mixed dining-room layout earns enough prestige
## for a staged favorable review to award two Ladles through the normal close.

const AWARD_LINE: String = "The critic awarded your kitchen two Golden Ladles!"
var _review_frame: int = 0
var _review_active: bool = false


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 407
	super._ready()
	Clock.set_speed(0)
	if not _buy_review_furnishings():
		push_error("Prestige review: the mixed layout did not fit.")
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


func _buy_review_furnishings() -> bool:
	owner_progress.total_xp = owner_progress.threshold_for(5)
	owner_progress.level = 5
	shop_editor.set_owner_level(owner_progress.effective_level())
	Economy.add_cash(1000, Ledger.MILESTONE_BONUS, "Prestige review funds")
	for pose: Vector3i in [Vector3i(3, 1, 1), Vector3i(9, 1, 1), Vector3i(11, 1, 0)]:
		if not shop_buy(&"cloth_table", Vector2i(pose.x, pose.y), pose.z):
			return false
	for x: int in range(1, 7):
		if not shop_buy(&"lamp_pendant", Vector2i(x, 1)):
			return false
	for x: int in [1, 3, 5, 7]:
		if not shop_hang(&"wall_art_sunrise", Vector3i(x, 1, 0)):
			return false
	for x: int in [9, 11, 13]:
		if not shop_hang(&"wall_art_peaks", Vector3i(x, 1, 0)):
			return false
	return true


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
