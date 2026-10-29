extends SceneTree
## Native review fixture. Normal modes leave the window interactive; all state
## is in memory (use_saves=false). --capture-set=<fresh output> writes the three
## lease views in one bounded process for the existing visual-review artifact.
## godot --path . --resolution 1600x900 --script tools/lease_review.gd -- offer
## Modes: offer (deposit + $1, amber restock advice), short (cash refusal),
## expand (accepted lease, real Expand tool with the larger lot).


func _initialize() -> void:
	# Load after autoloads exist, as with the balance/capture entry points.
	await process_frame
	var mode: String = "offer"
	var output: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		if args[0].begins_with("--capture-set="):
			output = args[0].trim_prefix("--capture-set=")
			if output.is_empty() or DirAccess.dir_exists_absolute(output) \
					or DisplayServer.get_name() == "headless" \
					or DirAccess.make_dir_recursive_absolute(output) != OK:
				printerr("Use a fresh capture directory in a rendered session")
				quit(2)
				return
		else:
			mode = args[0]
	if not mode in ["offer", "short", "expand"]:
		printerr("Use offer, short or expand")
		quit(2)
		return
	var errors: ErrorCounter = null
	if not output.is_empty():
		errors = ErrorCounter.new()
		OS.add_logger(errors)
		root.size = Vector2i(1600, 900)
	var scene: PackedScene = load("res://src/world/main.tscn")
	var main: Node = scene.instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", 1)
	root.add_child(main)
	main.call("start")
	var clock: Node = root.get_node("Clock")
	clock.call("set_speed", 0)
	var progress: RefCounted = main.get("owner_progress")
	var lease: Resource = load("res://data/balance/lease_upgrade.tres")
	progress.call("award_bonus", progress.call("threshold_for", lease.get("owner_level")))
	var menu: RefCounted = main.get("menu_settings")
	menu.call("set_owner_level", progress.get("level"))
	var editor: RefCounted = main.get("shop_editor")
	editor.call("set_owner_level", progress.get("level"))
	main.get_node("Overlay/BuildCatalogue").call("set_owner_level", progress.get("level"))
	main.get_node("HUD").call("set_owner_progress", progress.get("level"),
		progress.call("xp_into_level"), progress.call("xp_in_level"))
	var economy: Node = root.get_node("Economy")
	var deposit: int = lease.get("deposit")
	economy.set("cash", deposit - 1 if mode == "short" else deposit + 1)
	if mode == "expand":
		economy.set("cash", deposit + 5000)
		if not main.call("lease_buy"):
			printerr("Lease fixture purchase refused")
			quit(2)
			return
		main.call("set_build_active", true)
		main.call("_on_floor_tool_requested")
		main.get_node("Overlay/BuildCatalogue").call("set_category", &"floor")
	else:
		main.call("set_menu_visible", true)
	print("LEASE REVIEW FIXTURE: %s; synthetic owner XP/cash; no saves" % mode)
	if not output.is_empty():
		await _capture_set(main, output, errors)


func _capture_set(main: Node, output: String, errors: ErrorCounter) -> void:
	main.set_process(false)
	var valid: bool = await _capture_view(main, "offer", output, errors)
	var economy: Node = root.get_node("Economy")
	var lease: Resource = load("res://data/balance/lease_upgrade.tres")
	var deposit: int = lease.get("deposit")
	economy.set("cash", deposit - 1)
	valid = await _capture_view(main, "short", output, errors) and valid
	economy.set("cash", deposit + 5000)
	var bought: bool = main.call("lease_buy")
	main.call("set_build_active", true)
	main.call("_on_floor_tool_requested")
	main.get_node("Overlay/BuildCatalogue").call("set_category", &"floor")
	valid = await _capture_view(main, "expand", output, errors) and bought and valid
	root.remove_child(main)
	main.free()
	OS.remove_logger(errors)
	valid = valid and errors.count() == 0
	print("LEASE CAPTURE SET: ", "PASS" if valid else "FAIL")
	quit(0 if valid else 1)


func _capture_view(main: Node, mode: String, output: String, errors: ErrorCounter) -> bool:
	for frame: int in 18:
		await process_frame
	await RenderingServer.frame_post_draw
	var economy: Node = root.get_node("Economy")
	var offer: VBoxContainer = main.get_node("Overlay/MenuPanel/Panel/Content/LeaseOffer")
	var warning: Label = offer.get_node("Warning")
	var refusal: Label = offer.get_node("Refusal")
	var accept: Button = offer.get_node("Accept")
	var progress: RefCounted = main.get("owner_progress")
	var editor: RefCounted = main.get("shop_editor")
	var catalogue: Control = main.get_node("Overlay/BuildCatalogue")
	var valid: bool = errors.count() == 0
	if mode == "offer":
		valid = valid and offer.is_visible_in_tree() and warning.is_visible_in_tree() \
			and root.get_visible_rect().encloses(warning.get_global_rect()) \
			and warning.text.contains("Leaves $1") and not accept.disabled
	elif mode == "short":
		valid = valid and offer.is_visible_in_tree() and refusal.is_visible_in_tree() \
			and refusal.text == "Not enough cash for the lease deposit" and accept.disabled
	else:
		valid = valid and progress.get("property_tier") == 2 and catalogue.is_visible_in_tree() \
			and catalogue.get("selected_category") == &"floor"
	var image: Image = root.get_texture().get_image()
	var png: String = output.path_join("lease-%s.png" % mode)
	if image.save_png(png) != OK:
		return false
	var metadata: Dictionary = {
		"fixture": "Seed 1; synthetic owner XP/cash; no saves; production lease purchase and Expand tab",
		"mode": mode, "engine_errors": errors.count(), "capture_timing": "frame_post_draw",
		"cash": economy.get("cash"), "property_tier": progress.get("property_tier"),
		"cost": (offer.get_node("Cost") as Label).text,
		"warning": warning.text, "warning_visible": warning.is_visible_in_tree(),
		"refusal": refusal.text, "refusal_visible": refusal.is_visible_in_tree(),
		"button_disabled": accept.disabled, "lot": str(editor.call("footprint").lot),
		"category": String(catalogue.get("selected_category")),
		"width": image.get_width(), "height": image.get_height(),
		"image_sha256": FileAccess.get_sha256(png), "valid": valid,
	}
	var file: FileAccess = FileAccess.open(output.path_join("lease-%s.json" % mode), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(metadata, "\t") + "\n")
	file.close()
	return valid
