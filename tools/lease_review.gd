extends SceneTree
## Native review fixture. Normal modes leave the window interactive; all state
## is in memory (use_saves=false). --capture-set=<fresh output> writes the three
## lease views in one bounded manual process for PR attachment, outside CI.
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
	var fixture: Dictionary = prepare(main, root, mode)
	if not String(fixture["error"]).is_empty():
		printerr(fixture["error"])
		quit(2)
		return
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


## Exactly one declared state per standard screenshot process. The manual
## --capture-set path above stays outside CI and is never called by this option.
static func options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"mode": "", "error": ""}
	for argument: String in arguments:
		if argument.begins_with("--lease-review"):
			var mode: String = argument.trim_prefix("--lease-review=")
			if not mode in ["offer", "short", "expand"] or result["mode"] != "":
				result["error"] = "--lease-review requires exactly one offer, short or expand state"
				return result
			result["mode"] = mode
	if result["mode"] == "":
		return result
	var speeds: int = 0
	var frames: int = 0
	var scenes: int = 0
	var menus: int = 0
	for argument: String in arguments:
		if argument.begins_with("--lease-review=") or argument.begins_with("--out="):
			continue
		if argument == "--speed=0":
			speeds += 1
		elif argument == "--frames=12":
			frames += 1
		elif argument == "--scene=res://src/world/main.tscn":
			scenes += 1
		elif argument == "--menu":
			menus += 1
		else:
			result["error"] = "--lease-review requires paused Main frame 12 without other capture modes"
			return result
	if speeds != 1 or frames != 1 or scenes > 1 or menus != (0 if result["mode"] == "expand" else 1):
		result["error"] = "--lease-review needs one --speed=0, --frames=12, and --menu only for offer or short"
	return result


## Synthetic XP/cash only; the accepted/refused transaction uses Main's real API.
## Raising the fixture level never changes the player's enabled recipe choices.
static func prepare(main: Node, context_root: Node, mode: String) -> Dictionary:
	var result: Dictionary = {"kind": "unsaved_lease_ui_fixture_not_playthrough_or_balance", "mode": mode, "error": ""}
	var clock: Node = context_root.get_node("Clock")
	var time: RefCounted = clock.get("sim")
	var world: RefCounted = main.get("world")
	var progress: RefCounted = main.get("owner_progress")
	if mode not in ["offer", "short", "expand"] or main.get("use_saves") != false \
			or time.get("phase") != 0 or time.get("day") != 1 or world.get("now") != 0 \
			or clock.get("speed") != 0 or main.get("new_game_seed_override") != 1 or progress.get("level") != 1 or progress.get("property_tier") != 1:
		result["error"] = "lease review requires a fresh paused unsaved day-one Main"
		return result
	var lease: Resource = load("res://data/balance/lease_upgrade.tres")
	var menu: RefCounted = main.get("menu_settings")
	var editor: RefCounted = main.get("shop_editor")
	var before: Array[String] = _enabled_recipes(menu)
	var lot: Rect2i = editor.call("footprint").lot
	var grown: Rect2i = Rect2i(lot.position - Vector2i(lease.get("extra_west"), lease.get("extra_north")),
		lot.size + Vector2i(lease.get("extra_west") + lease.get("extra_east"), lease.get("extra_north")))
	progress.call("award_bonus", progress.call("threshold_for", lease.get("owner_level")))
	menu.call("set_owner_level", progress.get("level"))
	editor.call("set_owner_level", progress.get("level"))
	main.get_node("Overlay/BuildCatalogue").call("set_owner_level", progress.get("level"))
	main.get_node("HUD").call("set_owner_progress", progress.get("level"),
		progress.call("xp_into_level"), progress.call("xp_in_level"))
	var economy: Node = context_root.get_node("Economy")
	var deposit: int = lease.get("deposit")
	economy.set("cash", deposit + 5000 if mode == "expand" else deposit - 1 if mode == "short" else deposit + 1)
	var accepted: bool = false
	if mode == "expand":
		accepted = main.call("lease_buy")
		if not accepted or not main.call("set_build_active", true):
			result["error"] = "lease review could not buy the lease and open Build"
			return result
		main.call("_on_floor_tool_requested")
		main.get_node("Overlay/BuildCatalogue").call("set_category", &"floor")
	else:
		if not main.call("set_menu_visible", true):
			result["error"] = "lease review could not open the native Menu"
			return result
		if mode == "short":
			accepted = main.call("lease_buy")
			if accepted:
				result["error"] = "lease review unexpectedly accepted the short-cash purchase"
				return result
	if _enabled_recipes(menu) != before:
		result["error"] = "lease review changed the default enabled recipes"
	result.merge({"starting_enabled_recipes": before, "lot_before": _lot_data(lot), "lot_after": _lot_data(grown),
		"deposit": deposit, "daily_rent": lease.get("daily_rent"), "owner_level": lease.get("owner_level"),
		"purchase_attempted": mode != "offer", "purchase_accepted": accepted, "master_seed": 1})
	return result


static func evidence(main: Node, context_root: Node, fixture: Dictionary) -> Dictionary:
	var offer: VBoxContainer = main.get_node("Overlay/MenuPanel/Panel/Content/LeaseOffer")
	var warning: Label = offer.get_node("Warning")
	var refusal: Label = offer.get_node("Refusal")
	var cost: Label = offer.get_node("Cost")
	var accept: Button = offer.get_node("Accept")
	var catalogue: Control = main.get_node("Overlay/BuildCatalogue")
	var categories: Dictionary = catalogue.get("category_buttons")
	var expand: Button = categories.get(&"floor") as Button
	var clock: Node = context_root.get_node("Clock")
	var time: RefCounted = clock.get("sim")
	var progress: RefCounted = main.get("owner_progress")
	var editor: RefCounted = main.get("shop_editor")
	var viewport: Rect2 = main.get_viewport().get_visible_rect()
	var menu: Control = main.get_node("Overlay/MenuPanel")
	return {"mode": fixture.get("mode"), "use_saves": main.get("use_saves"), "world_tick": main.get("world").get("now"),
		"phase": time.get("phase"), "speed": clock.get("speed"), "owner_level": progress.get("level"),
		"property_tier": progress.get("property_tier"), "cash": context_root.get_node("Economy").get("cash"),
		"enabled_recipes": _enabled_recipes(main.get("menu_settings")),
		"lot": _lot_data(editor.call("footprint").lot), "view_lot": _lot_data(main.get_node("ShopView").get("_lot")),
		"menu_visible": menu.is_visible_in_tree(), "offer_visible": offer.is_visible_in_tree(),
		"cost": cost.text, "cost_in_viewport": _in_viewport(cost, viewport),
		"warning": warning.text, "warning_in_viewport": _in_viewport(warning, viewport),
		"warning_amber": warning.get_theme_color("font_color") == menu.get("ADVICE_COLOR"),
		"refusal": refusal.text, "refusal_in_viewport": _in_viewport(refusal, viewport),
		"button_disabled": accept.disabled, "button_in_viewport": _in_viewport(accept, viewport),
		"build_visible": catalogue.is_visible_in_tree(), "category": String(catalogue.get("selected_category")),
		"expand_in_viewport": _in_viewport(expand, viewport), "expand_selected": expand != null and expand.button_pressed}


static func valid(state: Dictionary, fixture: Dictionary, frame: int) -> bool:
	var mode: String = fixture.get("mode", "")
	var deposit: int = fixture.get("deposit", 0)
	if fixture.get("error") != "" or frame != 12 or state.get("mode") != mode or state.get("use_saves") != false \
			or state.get("world_tick") != 0 or state.get("phase") != 0 or state.get("speed") != 0 \
			or state.get("owner_level") != fixture.get("owner_level") \
			or state.get("enabled_recipes") != fixture.get("starting_enabled_recipes"):
		return false
	if mode == "expand":
		return fixture.get("purchase_accepted") == true and state.get("property_tier") == 2 and state.get("cash") == 5000 \
			and state.get("lot") == fixture.get("lot_after") and state.get("view_lot") == state.get("lot") \
			and state.get("menu_visible") == false and state.get("build_visible") == true \
			and state.get("category") == "floor" and state.get("expand_in_viewport") == true and state.get("expand_selected") == true
	if mode not in ["offer", "short"] or state.get("property_tier") != 1 or state.get("lot") != fixture.get("lot_before") \
			or state.get("menu_visible") != true or state.get("offer_visible") != true or state.get("cost_in_viewport") != true \
			or state.get("button_in_viewport") != true or not String(state.get("cost", "")).contains(Fmt.money(deposit)) \
			or not String(state.get("cost", "")).contains(Fmt.money(fixture.get("daily_rent", 0))):
		return false
	if mode == "offer":
		return fixture.get("purchase_attempted") == false and state.get("cash") == deposit + 1 \
			and state.get("warning_in_viewport") == true and state.get("warning_amber") == true \
			and String(state.get("warning", "")).contains("Leaves $1") and state.get("button_disabled") == false
	return fixture.get("purchase_attempted") == true and fixture.get("purchase_accepted") == false \
		and state.get("cash") == deposit - 1 and state.get("refusal") == "Not enough cash for the lease deposit" \
		and state.get("refusal_in_viewport") == true and state.get("button_disabled") == true


static func _enabled_recipes(settings: RefCounted) -> Array[String]:
	var ids: Array[String] = []
	for recipe: Resource in settings.call("enabled_recipes"):
		ids.append(String(recipe.get("id")))
	ids.sort()
	return ids


static func _lot_data(lot: Rect2i) -> Array[int]:
	return [lot.position.x, lot.position.y, lot.size.x, lot.size.y]


static func _in_viewport(control: Control, viewport: Rect2) -> bool:
	return control != null and control.is_visible_in_tree() and control.get_global_rect().has_area() \
		and viewport.encloses(control.get_global_rect())
