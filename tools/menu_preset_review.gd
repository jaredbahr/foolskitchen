extends "res://src/world/main.gd"
## Exercise the production preset controls on an unsaved, paused morning.


func _ready() -> void:
	use_saves = false
	skip_owner_picker = true
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	if not set_menu_visible(true) or not menu_set_price(&"burger", 11):
		push_error("Preset review could not prepare the morning menu")
		return
	var panel: MenuPanel = $Overlay/MenuPanel
	var controls: MenuPresetControls = panel.preset_controls()
	(panel.get_node("%PresetsToggle") as Button).button_pressed = true
	_save_preset(controls, "Lunch menu")
	if not menu_set_price(&"burger", 15) or not menu_set_enabled(&"tomato_soup", false):
		push_error("Preset review could not prepare the second menu")
		return
	_save_preset(controls, "Dinner menu")
	var names: Array[String] = ["Lunch menu", "Dinner menu"]
	if menu_presets.names() != names:
		push_error("Preset review could not save both menus")
		return
	(controls.get_node("%PresetList") as OptionButton).select(0)
	(controls.get_node("%LoadPreset") as Button).pressed.emit()
	if not controls.visible or not menu_settings.is_enabled(&"tomato_soup") \
			or menu_settings.price_of(menu_settings.recipe(&"burger")) != 11:
		push_error("Preset review could not restore Lunch menu")
		return
	print("MENU_PRESET_REVIEW ", JSON.stringify({"presets": names, "loaded": names[0], "seed": 1}))


func _save_preset(controls: MenuPresetControls, preset_name: String) -> void:
	var input: LineEdit = controls.get_node("%PresetName")
	input.text = preset_name
	input.text_changed.emit(preset_name)
	(controls.get_node("%SavePreset") as Button).pressed.emit()
