extends TestCase
## The board selector is usable before tree readiness and survives refreshes.

const PANEL: PackedScene = preload("res://src/ui/inspect_panel.tscn")

var _panel: InspectPanel
var _decor: WallDecor
var _request_anchor: Vector3i = WallFaces.NO_FACE
var _request_section: int = -99


func before_each() -> void:
	_panel = PANEL.instantiate() as InspectPanel
	_panel.bind_world(SimWorld.new(SimGrid.new(Vector2i(8, 8))))
	var recipe: RecipeDef = RecipeDef.new()
	recipe.id = &"test_main"
	recipe.display_name = "A main dish"
	recipe.standard_price = 8
	recipe.section = RecipeDef.Section.MAINS
	var menu: MenuSettings = MenuSettings.new([recipe] as Array[RecipeDef])
	_decor = WallDecor.new()
	assert_true(_decor.add(&"menu_board", Vector3i(2, 2, 0), 2))
	_panel.bind_menu_boards(_decor, menu)
	_panel.menu_board_section_requested.connect(_record_request)


func after_each() -> void:
	_panel.free()


func test_selector_emits_section_and_refresh_keeps_live_option_control() -> void:
	var anchor: Vector3i = Vector3i(2, 2, 0)
	_panel.show_menu_board(anchor)
	var row: Control = _panel.get_node("Panel/Rows/MenuSectionRow") as Control
	var option: OptionButton = _panel.get_node("Panel/Rows/MenuSectionRow/MenuSectionOption") as OptionButton
	assert_true(_panel.visible)
	assert_true(row.visible)
	assert_eq(option.get_item_text(0), "Automatic")
	assert_eq(option.selected, 0)
	_panel.refresh()
	assert_true(row.visible)
	assert_eq(option, _panel.get_node("Panel/Rows/MenuSectionRow/MenuSectionOption"),
		"the active native control is retained across a tick")
	var mains_index: int = -1
	for index: int in range(option.item_count):
		if int(option.get_item_metadata(index)) == RecipeDef.Section.MAINS:
			mains_index = index
	assert_true(mains_index > 0)
	option.select(mains_index)
	option.item_selected.emit(mains_index)
	assert_eq(_request_anchor, anchor)
	assert_eq(_request_section, RecipeDef.Section.MAINS)
	assert_eq(option.selected, 0, "an unaccepted request returns to editor-owned state")
	_panel.clear()
	assert_false(row.visible)
	assert_eq(_panel.selected_menu_board_anchor, WallFaces.NO_FACE)
	assert_false(_panel.visible)


func test_removed_board_clears_selection_on_refresh() -> void:
	var anchor: Vector3i = Vector3i(2, 2, 0)
	_panel.show_menu_board(anchor)
	assert_true(_panel.visible)
	_decor.remove(anchor)
	_panel.refresh()
	assert_eq(_panel.selected_menu_board_anchor, WallFaces.NO_FACE)
	assert_false(_panel.visible)


func test_switching_boards_uses_the_new_boards_section() -> void:
	var second: Vector3i = Vector3i(5, 2, 0)
	assert_true(_decor.add(&"menu_board", second, 2))
	assert_true(_decor.set_menu_section(second, RecipeDef.Section.MAINS))
	_panel.show_menu_board(Vector3i(2, 2, 0))
	var option: OptionButton = _panel.get_node("Panel/Rows/MenuSectionRow/MenuSectionOption") as OptionButton
	assert_eq(option.selected, 0)
	_panel.show_menu_board(second)
	assert_eq(_panel.selected_menu_board_anchor, second)
	assert_eq(int(option.get_item_metadata(option.selected)), RecipeDef.Section.MAINS)
	option.item_selected.emit(0)
	assert_eq(_request_anchor, second)
	assert_eq(_request_section, -1)


func _record_request(anchor: Vector3i, section: int) -> void:
	_request_anchor = anchor
	_request_section = section
