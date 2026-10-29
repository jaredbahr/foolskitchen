extends RefCounted
## FK-045 review fixture for --blueprints=selection|ghost|stamped.
## Uses only real morning commands: rug under the original left-hand table,
## box-select that pair, save it, then rotate/stamp it where the right table
## stood. No state is written to disk and no new assets are involved.

const SOURCE: Vector2i = Vector2i(2, 6)
const TARGET: Vector2i = Vector2i(10, 6)
const PROFILES: Array[String] = ["selection", "ghost", "stamped"]


static func options(arguments: PackedStringArray) -> Dictionary:
	var profile: String = ""
	for argument: String in arguments:
		if argument.begins_with("--blueprints"):
			if not profile.is_empty() or not argument.begins_with("--blueprints=") \
					or not PROFILES.has(argument.trim_prefix("--blueprints=")):
				return {"profile": "", "error": "--blueprints requires one selection, ghost or stamped profile"}
			profile = argument.trim_prefix("--blueprints=")
	if profile.is_empty():
		return {"profile": "", "error": ""}
	var paused: bool = false
	var frames: bool = false
	for argument: String in arguments:
		if argument.begins_with("--blueprints=") or argument.begins_with("--out=") or argument.begins_with("--quarter="):
			continue
		if argument == "--speed=0" and not paused:
			paused = true
			continue
		if argument.begins_with("--frames=") and not frames:
			frames = true
			for frame: String in argument.trim_prefix("--frames=").split(","):
				if not frame.is_valid_int() or int(frame) < 4:
					return {"profile": profile, "error": "blueprint review frames must be at least 4"}
			continue
		return {"profile": profile, "error": "blueprint review requires a paused fresh Main without other options"}
	return {"profile": profile, "error": "" if paused and frames else "blueprint review requires --speed=0 and --frames"}


static func prepare(main: Node, profile: String) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var mode: BuildMode = main.get("build_mode") as BuildMode
	var library: BlueprintLibrary = main.get("blueprint_library") as BlueprintLibrary
	var catalogue: BuildCatalogue = main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	if not PROFILES.has(profile) or world == null or editor == null or mode == null or catalogue == null \
			or world.clock.phase != SimClock.Phase.MORNING or bool(main.get("use_saves")):
		return {"error": "blueprint review needs a fresh unsaved Main morning"}
	if not bool(main.call("shop_buy", &"rug_round", SOURCE, 0)):
		return {"error": "blueprint review rug refused: " + editor.last_check.why}
	var target: PlacedItem = world.grid.item_at(TARGET)
	if target == null or (target.def as ItemDef).id != &"table_2" \
			or int(main.call("shop_sell", target.id)) < 0:
		return {"error": "blueprint review could not clear the original target table"}
	if not bool(main.call("set_build_active", true)):
		return {"error": "blueprint review could not enter Build"}
	catalogue.set_category(BuildCatalogue.BLUEPRINTS)
	catalogue.blueprint_select.pressed.emit()
	if not mode.blueprint_press(SOURCE) or not mode.blueprint_release(SOURCE + Vector2i.ONE) \
			or mode.blueprint_selection.size() != 2:
		return {"error": "blueprint review could not select the whole table and rug"}
	catalogue.blueprint_name.text = "Dining pair"
	if profile == "selection":
		return {"error": "", "profile": profile, "selected": 2}
	catalogue.blueprint_save.pressed.emit()
	if library.blueprints.size() != 1 or library.blueprints[0].entries.size() != 2:
		return {"error": "blueprint review could not save its pair"}
	catalogue.blueprint_buttons[0].pressed.emit()
	mode.update_origin(TARGET)
	if not mode.rotate(1) or not mode.current_check.ok:
		return {"error": "blueprint review stamp refused: " + mode.current_check.why}
	if profile == "stamped" and not mode.commit():
		return {"error": "blueprint review stamp commit refused: " + editor.last_check.why}
	return {"error": "", "profile": profile, "entries": 2, "cost": library.blueprints[0].total_price(main.get("content"))}


static func evidence(main: Node) -> Dictionary:
	var mode: BuildMode = main.get("build_mode") as BuildMode
	var world: SimWorld = main.get("world") as SimWorld
	var preview: BuildPreview = main.get_node_or_null("BuildPreview") as BuildPreview
	var catalogue: BuildCatalogue = main.get_node_or_null("Overlay/BuildCatalogue") as BuildCatalogue
	var library: BlueprintLibrary = main.get("blueprint_library") as BlueprintLibrary
	if mode == null or world == null or preview == null or catalogue == null or library == null:
		return {}
	var target: PlacedItem = world.grid.item_at(TARGET)
	var placed: bool = target != null and (target.def as ItemDef).id == &"table_2" and target.quarter_turns == 1
	var ghosts: Array[Dictionary] = []
	for ghost: ItemVisual in preview.blueprint_ghosts:
		ghosts.append({"visible": ghost.is_visible_in_tree(), "valid": ghost.get_meta("valid", false)})
	return {"state": int(mode.state), "check_ok": mode.current_check.ok,
		"selected": mode.blueprint_selection.size(), "library_size": library.blueprints.size(),
		"catalogue_visible": catalogue.is_visible_in_tree(), "category": String(catalogue.selected_category),
		"selection_visible": is_instance_valid(preview.blueprint_selection_mesh) and preview.blueprint_selection_mesh.is_visible_in_tree(),
		"ghosts": ghosts, "stamped": placed,
		"cash": int(main.get_node("/root/Economy").get("cash")),
		"history_steps": (main.get("edit_history") as ShopEditHistory).undo_count()}


static func valid(state: Dictionary, profile: String) -> bool:
	if not state.get("catalogue_visible", false) or state.get("category", "") != String(BuildCatalogue.BLUEPRINTS):
		return false
	match profile:
		"selection":
			return int(state.get("selected", 0)) == 2 and state.get("selection_visible", false)
		"ghost":
			var ghosts: Array = state.get("ghosts", [])
			return ghosts.size() == 2 and ghosts.all(_visible_valid_ghost) and state.get("check_ok", false)
		"stamped":
			return state.get("stamped", false) and int(state.get("library_size", 0)) == 1 \
				and int(state.get("state", -1)) == BuildMode.State.IDLE
	return false


static func _visible_valid_ghost(value: Dictionary) -> bool:
	return value.get("visible", false) and value.get("valid", false)
