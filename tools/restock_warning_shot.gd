extends SceneTree
## Manual native FK-096 warning evidence, using the production floor preview.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name() == "headless":
		print("Use a fresh --out directory in a rendered Compatibility session")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	var errors: ErrorCounter = ErrorCounter.new()
	OS.add_logger(errors)
	root.size = Vector2i(1600, 900)
	var main: Node = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", 23)
	root.add_child(main)
	main.call("start")
	main.set_process(false)
	root.get_node("Clock").call("set_speed", 0)
	main.call("set_build_active", true)
	main.call("begin_floor_tool")
	# Resolve through Main after autoload startup. Loading BuildMode's type in
	# this entry script retained its cyclic script graph at native shutdown.
	var mode: RefCounted = main.get("build_mode") as RefCounted
	mode.call("floor_press", Vector2i(14, 5))
	mode.call("floor_pointer", Vector2i(14, 9))
	var check: RefCounted = mode.get("current_check") as RefCounted
	var cost: int = int(check.get("cost"))
	var economy: Node = root.get_node("Economy")
	economy.call("add_cash", 75 + cost - int(economy.get("cash")), Ledger.OTHER)
	for frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	check = mode.get("current_check") as RefCounted
	var allowed: bool = bool(check.get("ok"))
	var warning: String = main.call("build_restock_warning")
	var hud: Node = main.get_node("HUD")
	var hint: Label = hud.get("_build_hint_text")
	var line: Label = hud.get("_build_warning_text")
	var visible: bool = line.is_visible_in_tree() and root.get_visible_rect().encloses(line.get_global_rect())
	var amber: bool = line.get_theme_color("font_color") == hud.get("ADVICE_COLOR") \
		and not hint.has_theme_color_override("font_color")
	var valid: bool = allowed and not warning.is_empty() and line.text == warning \
		and not hint.text.contains(warning) and visible and amber
	var metadata: Dictionary = {"fixture": "Paused original five-cell expansion preview; input polling frozen; cash set through the ledger; no purchase committed",
		"cash": int(economy.get("cash")), "preview_cost": cost, "leaves": int(economy.get("cash")) - cost,
		"restock_estimate": main.call("build_restock_estimate"), "warning": warning,
		"placement_allowed": allowed, "warning_in_viewport": visible, "warning_amber": amber, "engine_errors": errors.count()}
	if root.get_texture().get_image().save_png(output.path_join("restock-warning.png")) != OK:
		valid = false
	var file: FileAccess = FileAccess.open(output.path_join("restock-warning.json"), FileAccess.WRITE)
	if file == null:
		valid = false
	else:
		file.store_string(JSON.stringify(metadata, "\t") + "\n")
		file.close()
	root.remove_child(main)
	main.free()
	OS.remove_logger(errors)
	print("RESTOCK WARNING NATIVE: ", "PASS" if valid and errors.count() == 0 else "FAIL")
	quit(0 if valid and errors.count() == 0 else 1)
