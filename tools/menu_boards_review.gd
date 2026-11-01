extends RefCounted
## Native #161 menu-board review, used by --menu-boards-review. The fixture
## starts from an unsaved, paused seed-1 morning and uses only Main's player
## commands. Frame 12 shows a placed board with its real inspector choice;
## frame 30 shows the real Menu panel's theme readout.

const ANCHOR: Vector3i = Vector3i(1, 6, 3)
const OWNER_CELL: Vector2i = Vector2i(2, 5)
const NAME: String = "Copper Spoon"
const SECTION: int = RecipeDef.Section.MAINS
const MAIN_SCENE: String = "res://src/world/main.tscn"
const FIRST_FRAME: int = 12
const SECOND_FRAME: int = 30


static func options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"enabled": false, "error": ""}
	var speed_seen: bool = false
	var frames_seen: bool = false
	var scene_seen: bool = false
	for argument: String in arguments:
		if argument.begins_with("--menu-boards-review"):
			if argument != "--menu-boards-review" or result["enabled"]:
				result["error"] = "--menu-boards-review is one flag without a value"
				return result
			result["enabled"] = true
	if not result["enabled"]:
		return result
	for argument: String in arguments:
		if argument == "--menu-boards-review" or argument.begins_with("--out="):
			continue
		if argument == "--speed=0" and not speed_seen:
			speed_seen = true
			continue
		if argument == "--frames=12,30" and not frames_seen:
			frames_seen = true
			continue
		if argument == "--scene=" + MAIN_SCENE and not scene_seen:
			scene_seen = true
			continue
		result["error"] = "--menu-boards-review requires a paused fresh Main with --speed=0 --frames=12,30 and no other capture mode"
		return result
	if not speed_seen or not frames_seen:
		result["error"] = "--menu-boards-review requires one --speed=0 and one --frames=12,30"
	return result


static func prepare(main: Node, context_root: Node) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var menu: MenuSettings = main.get("menu_settings") as MenuSettings
	var shop: ShopView = main.get_node_or_null("ShopView") as ShopView
	var rig: CameraRig = main.get_node_or_null("CameraRig") as CameraRig
	var inspector: InspectPanel = main.get_node_or_null("Overlay/InspectPanel") as InspectPanel
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	var economy: Node = context_root.get_node_or_null("Economy")
	var game_state: Node = context_root.get_node_or_null("GameState")
	if world == null or editor == null or menu == null or shop == null or rig == null or inspector == null or restaurant == null \
			or economy == null or game_state == null or bool(main.get("use_saves")) \
			or int(main.get("new_game_seed_override")) != 1 or int(game_state.get("master_seed")) != 1 \
			or world.clock.phase != SimClock.Phase.MORNING or world.now != 0 \
			or int(context_root.get_node("Clock").get("speed")) != 0:
		return {"error": "menu boards review needs an unsaved, paused seed-1 Main morning"}
	var chosen: Array[RecipeDef] = []
	for recipe: RecipeDef in menu.enabled_recipes():
		if recipe.menu_section() == SECTION:
			chosen.append(recipe)
	if chosen.is_empty():
		return {"error": "seed-1 morning has no enabled Mains for the board"}
	var owner: OwnerAgent = restaurant.owner_agent()
	if owner == null or not world.grid.is_walkable(OWNER_CELL) or world.grid.item_at(OWNER_CELL) != null \
			or world.grid.find_path(owner.cell, OWNER_CELL).is_empty():
		return {"error": "menu boards review owner cannot stand on the clear reachable dining cell"}
	var agent_count: int = world.agents.size()
	if not bool(main.call("menu_set_restaurant_name", NAME)):
		return {"error": "menu boards review could not set the restaurant name"}
	if not bool(main.call("shop_hang", &"menu_board", ANCHOR)):
		return {"error": "menu boards review board was refused: " + editor.last_check.why}
	if not bool(main.call("select_menu_board", ANCHOR)):
		return {"error": "menu boards review could not select its placed board"}
	var option: OptionButton = inspector.get_node_or_null("Panel/Rows/MenuSectionRow/MenuSectionOption") as OptionButton
	if option == null:
		return {"error": "menu boards review inspector has no section choice"}
	var index: int = -1
	for candidate: int in range(option.item_count):
		if int(option.get_item_metadata(candidate)) == SECTION:
			index = candidate
			break
	if index < 0:
		return {"error": "menu boards review inspector does not list Mains"}
	# Emit the real native control's request; Main owns acceptance and refresh.
	option.select(index)
	option.item_selected.emit(index)
	var hung: WallDecor.Hung = editor.decor.item(ANCHOR)
	if hung == null or hung.menu_section != SECTION:
		return {"error": "menu boards review inspector section request was not accepted"}
	shop.set_wall_mode(ShopView.WallMode.CUTAWAY)
	var board: ItemVisual = shop.wall_finish_view.item_nodes.get(ANCHOR) as ItemVisual
	var label: Label3D = board.prop.get_node_or_null(^"WallMount/MenuText") as Label3D if board != null and board.prop != null else null
	if label == null:
		return {"error": "menu boards review has no placed Label3D"}
	# Move the existing owner into the review composition. No agent is spawned,
	# and the clock remains paused; the sim and drawn pose are refreshed once.
	owner.cell = OWNER_CELL
	owner.clear_path()
	shop._process(0.0)
	main.call("refresh_presentation")
	# Camera-only framing keeps the tiny wall label legible without changing art.
	rig.minimum_zoom = 2.4
	rig.initial_yaw_degrees = 90.0
	rig.pitch_degrees = 25.0
	rig.frame_area(Vector2(label.global_position.x, label.global_position.z), Vector2(12.0, 12.0), 2.4, true)
	rig.position.y = 0.4
	rig.set_process(false)
	var menu_ids: Array[String] = []
	for recipe: RecipeDef in chosen:
		menu_ids.append(String(recipe.id))
	return {"error": "", "anchor": [ANCHOR.x, ANCHOR.y, ANCHOR.z], "name": NAME,
		"requested_section": SECTION, "menu_ids": menu_ids, "cash_after_hang": int(economy.get("cash")),
		"owner_id": owner.id, "agent_count": agent_count}


static func show_menu_theme(main: Node) -> Dictionary:
	main.call("clear_selection")
	if not bool(main.call("set_menu_visible", true)) or not bool(main.call("is_menu_visible")):
		return {"error": "menu boards review could not open the real Menu panel"}
	var rig: CameraRig = main.get_node_or_null("CameraRig") as CameraRig
	if rig != null:
		rig.minimum_zoom = 8.0
		rig.initial_yaw_degrees = 45.0
		main.call("_frame_shop", true)
		rig.set_process(false)
	return {"error": ""}


static func evidence(main: Node, context_root: Node, frame: int) -> Dictionary:
	var world: SimWorld = main.get("world") as SimWorld
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	var menu: MenuSettings = main.get("menu_settings") as MenuSettings
	var shop: ShopView = main.get_node_or_null("ShopView") as ShopView
	var inspector: InspectPanel = main.get_node_or_null("Overlay/InspectPanel") as InspectPanel
	var panel: MenuPanel = main.get_node_or_null("Overlay/MenuPanel") as MenuPanel
	var camera: Camera3D = main.get_node_or_null("CameraRig/Camera3D") as Camera3D
	var restaurant: RestaurantSim = main.get("sim") as RestaurantSim
	if world == null or editor == null or menu == null or shop == null or inspector == null or panel == null or camera == null or restaurant == null:
		return {}
	var owner: OwnerAgent = restaurant.owner_agent()
	var owner_node: Node3D = shop.agent_nodes.get(owner.id) as Node3D if owner != null else null
	var owner_floor: Vector2 = camera.unproject_position(owner_node.global_position) if owner_node != null else Vector2(-1.0, -1.0)
	var owner_top: Vector2 = camera.unproject_position(owner_node.global_position + Vector3.UP * 0.85) if owner_node != null else Vector2(-1.0, -1.0)
	var hung: WallDecor.Hung = editor.decor.item(ANCHOR)
	var board: ItemVisual = shop.wall_finish_view.item_nodes.get(ANCHOR) as ItemVisual if shop.wall_finish_view != null else null
	var label: Label3D = board.prop.get_node_or_null(^"WallMount/MenuText") as Label3D if board != null and board.prop != null else null
	var option: OptionButton = inspector.get_node_or_null("Panel/Rows/MenuSectionRow/MenuSectionOption") as OptionButton
	var section_row: Control = inspector.get_node_or_null("Panel/Rows/MenuSectionRow") as Control
	var details: Label = inspector.get_node_or_null("Panel/Rows/Details") as Label
	var theme: Label = panel.find_child("MenuTheme", true, false) as Label
	var name_edit: LineEdit = panel.get_node_or_null("%RestaurantName") as LineEdit
	var center: Vector2 = camera.unproject_position(label.global_position) if label != null else Vector2(-1.0, -1.0)
	var em_height: float = absf(camera.unproject_position(label.global_position + Vector3.UP * float(MenuBoardText.FONT_SIZE) * MenuBoardText.PIXEL_SIZE).y - center.y) if label != null else 0.0
	var chosen: Array[RecipeDef] = menu.enabled_recipes()
	var enabled_ids: Array[String] = []
	for recipe: RecipeDef in chosen:
		enabled_ids.append(String(recipe.id))
	return {
		"frame": frame, "phase": int(world.clock.phase), "tick": world.now,
		"speed": int(context_root.get_node("Clock").get("speed")),
		"use_saves": bool(main.get("use_saves")),
		"seed": str(context_root.get_node("GameState").get("master_seed")),
		"restaurant_name": menu.restaurant_name(), "enabled_ids": enabled_ids,
		"owner": {"id": owner.id if owner != null else -1, "agent_count": world.agents.size(),
			"cell": owner.cell if owner != null else SimGrid.NO_CELL,
			"reachable": world.grid.is_walkable(OWNER_CELL) and not world.grid.find_path(OWNER_CELL, owner.home_cell()).is_empty() if owner != null else false,
			"native_person": owner_node is PersonView, "visible": owner_node.is_visible_in_tree() if owner_node != null else false,
			"floor_screen": [owner_floor.x, owner_floor.y], "top_screen": [owner_top.x, owner_top.y]},
		"board": {"present": hung != null, "section": hung.menu_section if hung != null else -2,
			"label_present": label != null, "label_visible": label.is_visible_in_tree() if label != null else false,
			"text": label.text if label != null else "", "expected_text": MenuBoardText.text(menu.restaurant_name(), chosen, hung.menu_section) if hung != null else "",
			"screen_center": [center.x, center.y], "projected_em_height": em_height,
			"camera_behind": camera.is_position_behind(label.global_position) if label != null else true,
			"wall_mode": int(shop.wall_mode)},
		"inspector": {"visible": inspector.is_visible_in_tree(),
			"selected_anchor": inspector.selected_menu_board_anchor,
			"section_row_visible": section_row.is_visible_in_tree() if section_row != null else false,
			"section_choice_visible": option.is_visible_in_tree() if option != null else false,
			"choice_index": option.selected if option != null else -1,
			"choice_section": int(option.get_item_metadata(option.selected)) if option != null and option.selected >= 0 else -2,
			"details": details.text if details != null else ""},
		"menu_panel": {"visible": panel.is_visible_in_tree(),
			"name": name_edit.text if name_edit != null else "",
			"theme_visible": theme.is_visible_in_tree() if theme != null else false,
			"theme_text": theme.text if theme != null else "",
			"expected_theme": MenuThemeText.summary(chosen),
			"theme_bounds": _rect(theme) if theme != null else []},
	}


static func valid(state: Dictionary, frame: int, fixture: Dictionary) -> bool:
	if state.is_empty() or frame not in [FIRST_FRAME, SECOND_FRAME] or state.get("frame") != frame \
			or state.get("phase") != SimClock.Phase.MORNING or state.get("tick") != 0 \
			or state.get("speed") != 0 or state.get("use_saves") != false or state.get("seed") != "1" \
			or state.get("restaurant_name") != NAME:
		return false
	var board: Dictionary = state.get("board", {})
	if board.get("present") != true or board.get("section") != SECTION \
			or board.get("label_present") != true or board.get("label_visible") != true \
			or board.get("text") != board.get("expected_text") \
			or not String(board.get("text", "")).begins_with(NAME + "\nMains\n") \
			or board.get("camera_behind") != false or board.get("wall_mode") != ShopView.WallMode.CUTAWAY:
		return false
	var menu_ids: Array = fixture.get("menu_ids", [])
	for id: String in menu_ids:
		if not (state.get("enabled_ids", []) as Array).has(id):
			return false
	var owner: Dictionary = state.get("owner", {})
	if owner.get("id") != fixture.get("owner_id") or owner.get("agent_count") != fixture.get("agent_count") \
			or owner.get("cell") != OWNER_CELL or owner.get("reachable") != true \
			or owner.get("native_person") != true or owner.get("visible") != true:
		return false
	if frame == FIRST_FRAME:
		var inspector: Dictionary = state.get("inspector", {})
		var center: Array = board.get("screen_center", [])
		var owner_floor: Array = owner.get("floor_screen", [])
		var owner_top: Array = owner.get("top_screen", [])
		return inspector.get("visible") == true and inspector.get("section_row_visible") == true \
			and inspector.get("section_choice_visible") == true \
			and inspector.get("selected_anchor") == ANCHOR and inspector.get("choice_section") == SECTION \
			and String(inspector.get("details", "")).contains("Mains") \
			and center.size() == 2 and float(center[0]) > 400.0 and float(center[0]) < 1500.0 \
			and float(center[1]) > 60.0 and float(center[1]) < 700.0 \
			and float(board.get("projected_em_height", 0.0)) >= 10.0 \
			and owner_floor.size() == 2 and owner_top.size() == 2 \
			and float(owner_floor[0]) > 400.0 and float(owner_floor[0]) < 1600.0 \
			and float(owner_floor[1]) > 160.0 and float(owner_floor[1]) < 875.0 \
			and float(owner_top[0]) > 400.0 and float(owner_top[0]) < 1600.0 \
			and float(owner_top[1]) > 105.0 and float(owner_top[1]) < float(owner_floor[1]) - 100.0
	var panel: Dictionary = state.get("menu_panel", {})
	var bounds: Array = panel.get("theme_bounds", [])
	return panel.get("visible") == true and panel.get("name") == NAME \
		and panel.get("theme_visible") == true and panel.get("theme_text") == panel.get("expected_theme") \
		and String(panel.get("theme_text", "")).begins_with("Menu leans:") \
		and bounds.size() == 4 and float(bounds[2]) > 0.0 and float(bounds[3]) > 0.0 \
		and float(bounds[0]) >= 0.0 and float(bounds[1]) >= 0.0 \
		and float(bounds[0]) + float(bounds[2]) <= 1600.0 \
		and float(bounds[1]) + float(bounds[3]) <= 900.0


static func _rect(control: Control) -> Array[float]:
	var rect: Rect2 = control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
