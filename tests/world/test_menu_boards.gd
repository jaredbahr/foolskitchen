extends TestCase
## Placed chalkboards use today's accepted menu and the normal inspection path.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const WEST: int = 3

var _main: Node3D
var _viewport: SubViewport


func before_each() -> void:
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	if is_instance_valid(_viewport):
		_viewport.get_parent().remove_child(_viewport)
		_viewport.free()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_two_boards_keep_independent_sections_and_refresh_on_menu_and_name_edits() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	var auto_anchor: Vector3i = Vector3i(1, 6, WEST)
	var mains_anchor: Vector3i = Vector3i(1, 9, WEST)
	assert_true(_main.call("shop_hang", &"menu_board", auto_anchor))
	assert_true(_main.call("shop_hang", &"menu_board", mains_anchor))
	var settings: MenuSettings = _main.get("menu_settings") as MenuSettings
	assert_eq(_board_text(auto_anchor), MenuBoardText.text(settings.restaurant_name(), settings.enabled_recipes()))
	assert_true(_main.call("shop_menu_board_section", mains_anchor, RecipeDef.Section.MAINS))
	assert_eq(_board_text(mains_anchor), MenuBoardText.text(settings.restaurant_name(),
		settings.enabled_recipes(), RecipeDef.Section.MAINS))
	assert_ne(_board_text(auto_anchor), _board_text(mains_anchor))
	assert_true(_main.call("menu_set_restaurant_name", "  Nora's Place  "))
	assert_true(_board_text(auto_anchor).begins_with("Nora's Place\n"))
	assert_true(_board_text(mains_anchor).begins_with("Nora's Place\n"))
	assert_true(_main.call("menu_set_enabled", &"tomato_soup", false))
	assert_eq(_board_text(auto_anchor), MenuBoardText.text("Nora's Place", settings.enabled_recipes()),
		"automatic board moves to the first section still on today's menu")
	assert_eq(_board_text(mains_anchor), MenuBoardText.text("Nora's Place", settings.enabled_recipes(),
		RecipeDef.Section.MAINS))
	assert_eq((_main.get("shop_editor") as ShopEditor).decor.item(mains_anchor).menu_section,
		RecipeDef.Section.MAINS)
	assert_true(_main.call("shop_menu_board_section", auto_anchor, RecipeDef.Section.SIDES))
	assert_true(_board_text(auto_anchor).contains("No dishes today"), "an explicit empty section stays selected")
	assert_eq(_board_text(mains_anchor), MenuBoardText.text("Nora's Place", settings.enabled_recipes(),
		RecipeDef.Section.MAINS), "the second board keeps its own section")
	assert_false(_main.call("shop_menu_board_section", auto_anchor, 999))
	assert_false(_main.call("shop_menu_board_section", Vector3i(5, 5, WEST), RecipeDef.Section.MAINS))


func test_idle_wall_hit_selects_board_and_inspector_requests_section() -> void:
	await _start()
	Economy.add_cash(500, Ledger.OTHER)
	var anchor: Vector3i = Vector3i(1, 6, WEST)
	assert_true(_main.call("shop_hang", &"menu_board", anchor))
	var view: ShopView = _main.get_node("ShopView") as ShopView
	view.set_wall_mode(ShopView.WallMode.UP)
	var node: ItemVisual = view.wall_finish_view.item_nodes[anchor]
	var centre: Vector3 = node.global_transform * node.get_aabb().get_center()
	var camera: Camera3D = _main.get_node("CameraRig/Camera3D") as Camera3D
	var screen: Vector2 = camera.unproject_position(centre)
	assert_eq(_main.call("wall_item_at_screen_position", screen), anchor)
	_main.call("pick_screen_position", screen)
	var panel: InspectPanel = _main.get_node("Overlay/InspectPanel") as InspectPanel
	assert_eq(panel.selected_menu_board_anchor, anchor)
	assert_true(panel.visible)
	assert_eq(panel.selected_agent_id, -1)
	assert_eq(panel.selected_item_id, -1)
	var row: Control = panel.get_node("Panel/Rows/MenuSectionRow") as Control
	var option: OptionButton = panel.get_node("Panel/Rows/MenuSectionRow/MenuSectionOption") as OptionButton
	assert_true(row.visible)
	panel.refresh()
	assert_true(row.visible, "tick refresh preserves the active section control")
	var mains_index: int = _section_index(option, RecipeDef.Section.MAINS)
	option.select(mains_index)
	option.item_selected.emit(mains_index)
	assert_eq((_main.get("shop_editor") as ShopEditor).decor.item(anchor).menu_section,
		RecipeDef.Section.MAINS, "the native control requests the editor-owned change")
	assert_true(_board_text(anchor).contains("Mains"))
	var escape: InputEventKey = InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	_main.call("_unhandled_input", escape)
	assert_eq(panel.selected_menu_board_anchor, WallFaces.NO_FACE)
	assert_false(panel.visible)
	assert_false(row.visible)
	assert_false(_main.call("is_settings_visible"), "Escape dismisses the board first")


func _start() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(_viewport)
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_viewport.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	_main.set_process(false)
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	rig.edge_pan_enabled = false
	(_main.get_node("ShopView") as ShopView).set_process(false)
	for frame: int in range(3):
		await tree.process_frame


func _board_text(anchor: Vector3i) -> String:
	var view: ShopView = _main.get_node("ShopView") as ShopView
	var node: ItemVisual = view.wall_finish_view.item_nodes[anchor]
	var label: Label3D = node.prop.get_node("WallMount/MenuText") as Label3D
	assert_eq(label.font_size, MenuBoardText.FONT_SIZE)
	assert_almost_eq(label.pixel_size, MenuBoardText.PIXEL_SIZE)
	return label.text


func _section_index(option: OptionButton, section: int) -> int:
	for index: int in range(option.item_count):
		if int(option.get_item_metadata(index)) == section:
			return index
	return -1
