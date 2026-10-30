extends SceneTree
## Bounded native title capture. The normal screenshot/probe entry points still
## instantiate Main directly, independently of project.godot's startup scene.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output) \
			or DisplayServer.get_name() == "headless":
		printerr("Use a fresh --out directory in a rendered Compatibility session")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	var errors: ErrorCounter = ErrorCounter.new()
	OS.add_logger(errors)
	root.size = Vector2i(1600, 900)
	var saves: Node = root.get_node("SaveSystem")
	var old_save_dir: String = String(saves.get("save_dir"))
	saves.set("save_dir", "user://title-review-no-save/")
	var before: Dictionary = _run_state()
	var title: Control = (load("res://src/ui/title_screen.tscn") as PackedScene).instantiate() as Control
	root.add_child(title)
	title.call("start")
	for frame: int in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var backdrop: Node = title.get("_backdrop") as Node
	var menu: Control = title.get_node("Menu") as Control
	var continue_button: Button = title.get_node("Menu/Column/Continue") as Button
	var new_button: Button = title.get_node("Menu/Column/NewGame") as Button
	var settings_button: Button = title.get_node("Menu/Column/Settings") as Button
	var valid: bool = before == _run_state() and not bool(backdrop.get("_started")) \
		and bool(backdrop.get("display_only")) and not bool(backdrop.get("use_saves")) \
		and not continue_button.visible and new_button.is_visible_in_tree() \
		and settings_button.is_visible_in_tree() \
		and root.get_visible_rect().encloses(menu.get_global_rect()) \
		and (saves.call("list_slots") as PackedStringArray).is_empty()
	var image_path: String = output.path_join("title.png")
	var picture: Image = root.get_texture().get_image()
	if picture.save_png(image_path) != OK:
		valid = false
	var metadata: Dictionary = {"scene": title.scene_file_path, "image_file": "title.png",
		"image_sha256": FileAccess.get_sha256(image_path), "capture_timing": "frame_post_draw",
		"width": picture.get_width(), "height": picture.get_height(), "frame": 30,
		"video_adapter": RenderingServer.get_video_adapter_name(), "engine_errors": errors.count(),
		"fixture": "no save exists; live default shop in display-only mode; no run initialized",
		"continue_visible": continue_button.visible, "new_game_visible": new_button.is_visible_in_tree(),
		"settings_visible": settings_button.is_visible_in_tree(), "menu_in_viewport": root.get_visible_rect().encloses(menu.get_global_rect()),
		"global_run_state_unchanged": before == _run_state(), "backdrop_session_started": backdrop.get("_started"),
		"save_slots": saves.call("list_slots")}
	var file: FileAccess = FileAccess.open(output.path_join("title.json"), FileAccess.WRITE)
	if file == null:
		valid = false
	else:
		file.store_string(JSON.stringify(metadata, "\t") + "\n")
		file.close()
	root.remove_child(title)
	title.free()
	saves.set("save_dir", old_save_dir)
	OS.remove_logger(errors)
	print("TITLE NATIVE: ", "PASS" if valid and errors.count() == 0 else "FAIL")
	quit(0 if valid and errors.count() == 0 else 1)


func _run_state() -> Dictionary:
	var state: Dictionary = {}
	for key: String in ["Clock", "GameState", "Economy"]:
		state[key] = root.get_node(key).call("_capture_save")
	return state
