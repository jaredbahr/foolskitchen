extends "res://src/world/main.gd"
## Open actual Career Settings and show a scheduled switch to Custom.

func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	set_process(false)
	Clock.set_speed(0)
	($HUD/Top/Row/Settings as Button).pressed.emit()
	var choice: OptionButton = _settings_panel.get_node("%DifficultyChoice") as OptionButton
	choice.item_selected.emit(Difficulty.MODES.find(&"custom"))
	await get_tree().process_frame
	await get_tree().process_frame
	var premium: CheckButton = _settings_panel.get_node("%AutoBuyPremium") as CheckButton
	var scroll: Control = _settings_panel.get_node("Panel/Column/Scroll") as Control
	if not premium.is_visible_in_tree() or not scroll.get_global_rect().encloses(premium.get_global_rect()) \
			or difficulty.mode() != &"normal" or difficulty.pending_mode() != &"custom":
		push_error("Difficulty Settings review did not show both Custom switches in the real Settings view")
		get_tree().quit(1)
