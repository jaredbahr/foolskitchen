extends TitleScreen
## Capture the untouched Normal default along the real New game -> Career route.


func _ready() -> void:
	build_version = "dev"
	var old_save_dir: String = SaveSystem.save_dir
	SaveSystem.save_dir = "user://difficulty-title-review-%d" % OS.get_process_id()
	super._ready()
	SaveSystem.save_dir = old_save_dir
	set_process(false)

	new_button.pressed.emit()
	var career: Button = mode_choice.find_child("Career", true, false) as Button
	career.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var normal: Button = difficulty_choice.find_child("Normal", true, false) as Button
	if continue_button.visible or menu.visible or mode_choice.visible or confirmation.visible \
			or not difficulty_choice.is_visible_in_tree() or not normal.button_pressed \
			or not get_viewport_rect().encloses(difficulty_choice.get_global_rect()):
		push_error("Difficulty title review did not reach the uncommitted Career picker")
		get_tree().quit(1)
		return
	print("DIFFICULTY_TITLE_REVIEW: New game -> Career, Normal selected, no game started")
