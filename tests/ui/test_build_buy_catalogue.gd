extends TestCase
## FK-085: Buy mode rooms, sub-tabs, theme filters, price sort, the hover
## card, and the Build side. Uses the shipped content where words matter.

const SCENE: PackedScene = preload("res://src/ui/build_catalogue.tscn")

var _catalogue: BuildCatalogue
var _content: ContentDB
var _modes: Array[StringName] = []
var _paint_requests: int = 0
var _tools: Array[int] = []
var _undos: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_catalogue = SCENE.instantiate() as BuildCatalogue
	_catalogue.bind_content(_content)
	_catalogue.set_owner_level(6)
	_catalogue.set_build_visible(true)
	_modes.clear()
	_paint_requests = 0
	_tools.clear()
	_undos = 0
	_catalogue.mode_requested.connect(_on_mode)
	_catalogue.paint_requested.connect(_on_paint)
	_catalogue.tool_requested.connect(_on_tool)
	_catalogue.undo_requested.connect(_on_undo)


func after_each() -> void:
	if is_instance_valid(_catalogue):
		_catalogue.free()
	_content = null


func test_every_catalogue_item_has_a_known_room_and_group() -> void:
	var rooms: Dictionary[StringName, int] = {}
	for definition: ItemDef in _content.items():
		if not _catalogue.item_buttons.has(definition.id):
			assert_true(definition.category == ItemDef.Category.DOOR or not definition.catalogue_visible,
				"%s is missing from the catalogue" % definition.id)
			continue
		var room: StringName = BuildCatalogue.category_for(definition)
		assert_true(BuildCatalogue.BUY_CATEGORIES.has(room), "%s has room %s" % [definition.id, room])
		assert_true(CatalogueText.GROUP_IDS.has(CatalogueText.group_for(definition)))
		assert_false(CatalogueText.does(definition).is_empty(), "%s says what it does" % definition.id)
		rooms[room] = rooms.get(room, 0) + 1
	assert_true(rooms.get(&"dining", 0) > 0)
	assert_true(rooms.get(&"kitchen", 0) > 0)
	assert_true(rooms.get(&"bar_cafe", 0) > 0)
	assert_true(rooms.get(&"decor", 0) > 0)
	assert_eq(BuildCatalogue.category_for(_content.item(&"bar_stool")), &"bar_cafe")
	assert_eq(BuildCatalogue.category_for(_content.item(&"stove")), &"kitchen")
	assert_eq(BuildCatalogue.category_for(_content.item(&"rug_round")), &"decor", "no room set means Decor")
	assert_eq(BuildCatalogue.category_for(_content.item(&"door")), &"", "the door is never sold")


func test_unknown_rooms_fall_back_to_decor_and_content_validation_names_them() -> void:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"odd"
	definition.catalogue_room = &"ballroom"
	assert_eq(definition.buy_room(), &"decor")
	var errors: PackedStringArray = ContentDB.validate_definitions([] as Array[IngredientDef],
		[] as Array[RecipeDef], [definition] as Array[ItemDef])
	var named: bool = false
	for error: String in errors:
		named = named or error.contains("unknown catalogue room")
	assert_true(named)


func test_rooms_without_items_have_no_tab_and_buy_hides_build_tabs() -> void:
	assert_eq(_catalogue.mode, BuildCatalogue.BUY)
	for room: StringName in [&"dining", &"kitchen", &"bar_cafe", &"decor"]:
		assert_true(_catalogue.category_buttons[room].visible, String(room))
	assert_false(_catalogue.category_buttons[&"lighting"].visible, "no lamps exist yet")
	assert_false(_catalogue.category_buttons[&"restroom"].visible)
	assert_eq(_catalogue.category_buttons[&"bar_cafe"].text, "Bar & Café")
	for build: StringName in BuildCatalogue.BUILD_CATEGORIES:
		assert_false(_catalogue.category_buttons[build].visible)


func test_dining_sub_tabs_split_seating_and_tables() -> void:
	_catalogue.set_category(&"dining")
	assert_true(_catalogue.group_buttons[&"all"].visible)
	assert_true(_catalogue.group_buttons[&"seating"].visible)
	assert_true(_catalogue.group_buttons[&"tables"].visible)
	assert_false(_catalogue.group_buttons[&"rugs"].visible)
	var all: Array[StringName] = _catalogue.visible_ids()
	_catalogue.group_buttons[&"tables"].pressed.emit()
	for id: StringName in _catalogue.visible_ids():
		assert_eq(_content.item(id).category, ItemDef.Category.TABLE)
	assert_true(_catalogue.visible_ids().has(&"round_table"))
	_catalogue.group_buttons[&"all"].pressed.emit()
	assert_eq(_catalogue.visible_ids(), all)
	_catalogue.set_category(&"kitchen")
	assert_false(_catalogue.group_buttons[&"equipment"].visible, "one group needs no sub-tabs")
	assert_eq(_catalogue.selected_group, BuildCatalogue.ALL_GROUPS, "a new room starts on All")


func test_theme_filters_show_items_with_any_chosen_theme() -> void:
	_catalogue.set_category(&"dining")
	var labels: Array[String] = []
	for tag: StringName in _catalogue.theme_buttons:
		labels.append(_catalogue.theme_buttons[tag].text)
	assert_eq(labels, ["Cosy", "Modern", "Rustic", "Diner", "Seafood"] as Array[String],
		"the vibe's own themes and words; no invented Café or Bar tags")
	_catalogue.theme_buttons[&"modern"].pressed.emit()
	var modern: Array[StringName] = _catalogue.visible_ids()
	assert_false(modern.is_empty())
	for id: StringName in modern:
		assert_true(_content.item(id).theme_tags.has(&"modern"), String(id))
	assert_false(modern.has(&"wooden_chair"))
	_catalogue.theme_buttons[&"rustic"].pressed.emit()
	var either: Array[StringName] = _catalogue.visible_ids()
	assert_true(either.has(&"wooden_chair"), "a second theme widens the list")
	assert_true(either.has(&"glass_table"))
	_catalogue.theme_buttons[&"modern"].pressed.emit()
	_catalogue.theme_buttons[&"rustic"].pressed.emit()
	assert_true(_catalogue.theme_filters.is_empty())
	_catalogue.set_theme_filter(&"seafood", true)
	assert_true(_catalogue.visible_ids().is_empty())
	var empty: Label = _catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Empty") as Label
	assert_true(empty.visible)
	assert_eq(empty.text, "No items match these filters")
	_catalogue.set_theme_filter(&"made_up", true)
	assert_false(_catalogue.theme_filters.has(&"made_up"))


func test_price_sort_reorders_the_tiles_without_replacing_them() -> void:
	_catalogue.set_category(&"dining")
	var by_name: Array[StringName] = _catalogue.visible_ids()
	var button: Button = _catalogue.item_buttons[by_name[0]]
	assert_eq(_catalogue.sort_button.text, "Sort: A to Z")
	_catalogue.sort_button.pressed.emit()
	assert_eq(_catalogue.sort_button.text, "Sort: cheapest")
	var cheap: Array[StringName] = _catalogue.visible_ids()
	for index: int in range(1, cheap.size()):
		assert_true(_content.item(cheap[index - 1]).price <= _content.item(cheap[index]).price)
	var grid: GridContainer = _catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Items") as GridContainer
	assert_eq(grid.get_child(0), _catalogue.item_buttons[cheap[0]], "the grid shows the sorted order")
	_catalogue.sort_button.pressed.emit()
	var pricey: Array[StringName] = _catalogue.visible_ids()
	for index: int in range(1, pricey.size()):
		assert_true(_content.item(pricey[index - 1]).price >= _content.item(pricey[index]).price)
	_catalogue.sort_button.pressed.emit()
	assert_eq(_catalogue.visible_ids(), by_name)
	assert_true(_catalogue.item_buttons[by_name[0]] == button)
	# Equal prices keep name order.
	_catalogue.set_sort(BuildCatalogue.Sort.PRICE_LOW)
	var ten: Array[StringName] = []
	for id: StringName in _catalogue.visible_ids():
		if _content.item(id).price == 10:
			ten.append(id)
	assert_eq(ten, [&"chair", &"wooden_chair"] as Array[StringName])


func test_hover_card_text() -> void:
	assert_eq(_catalogue.hover_card_lines(&"cushioned_bench"),
		["Cushioned two-seat bench", "$50", "Seats 2", "Themes: Cosy"] as Array[String])
	assert_eq(_catalogue.hover_card_lines(&"television_vintage"),
		["Vintage television", "$150", "Decoration", "Charm +3", "Themes: Diner"] as Array[String])
	assert_eq(_catalogue.hover_card_lines(&"rug_round"),
		["Round rug", "$30", "Rug: tables and chairs can stand on it", "Charm +1", "Themes: Cosy, Rustic"] as Array[String])
	assert_eq(_catalogue.hover_card_lines(&"stove"),
		["Stove", "$100", "Cooks hot dishes", "Themes: Diner"] as Array[String])
	assert_eq(_catalogue.hover_card_lines(&"fridge")[2], "Stores 20 ingredients")
	assert_eq(_catalogue.hover_card_lines(&"round_table")[2], "Table for 2")
	assert_eq(_catalogue.hover_card_lines(&"table_2")[2], "Table with seats for 2")
	assert_eq(_catalogue.hover_card_lines(&"bar_counter")[3], "Themes: Modern, Diner", "vibe theme order")
	_catalogue.set_owner_level(1)
	assert_eq(_catalogue.hover_card_lines(&"glass_table")[1], "$120  (unlocks at level 6)")
	assert_eq(_catalogue.hover_card_lines(&"no_such_item"), [] as Array[String])
	for definition: ItemDef in _content.items():
		for line: String in _catalogue.hover_card_lines(definition.id):
			assert_false(line.contains("_"), "no raw ids in %s: %s" % [definition.id, line])


func test_hover_card_shows_over_the_world_for_a_visible_tile_only() -> void:
	var host: Control = Control.new()
	host.size = Vector2(1600.0, 900.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(host)
	host.add_child(_catalogue)
	await tree.process_frame
	await tree.process_frame
	_catalogue.set_category(&"dining")
	var card: Control = _catalogue.get_node("HoverCard") as Control
	_catalogue.item_buttons[&"round_table"].mouse_entered.emit()
	assert_true(card.visible)
	assert_eq(_catalogue.hover_id, &"round_table")
	assert_eq((card.get_node("Rows/Name") as Label).text, "Round table")
	assert_true((card.get_node("Rows/Lines") as Label).text.begins_with("$55\nTable for 2"))
	var panel: Rect2 = (_catalogue.get_node("Panel") as Control).get_global_rect()
	assert_true(card.get_global_rect().end.y <= panel.position.y + 0.5, "the card sits above the panel")
	assert_true(Rect2(Vector2.ZERO, host.size).encloses(card.get_global_rect()), "inside: %s" % card.get_global_rect())
	_catalogue.item_buttons[&"round_table"].mouse_exited.emit()
	assert_false(card.visible)
	_catalogue.item_buttons[&"stove"].mouse_entered.emit()
	assert_false(card.visible, "a hidden tile never shows a card")
	_catalogue.item_buttons[&"round_table"].mouse_entered.emit()
	_catalogue.set_category(&"kitchen")
	assert_false(card.visible, "changing room hides the card")
	host.remove_child(_catalogue)
	host.free()


func test_build_side_tabs_modes_tools_and_undo_requests() -> void:
	_catalogue.mode_buttons[BuildCatalogue.BUILD].pressed.emit()
	assert_eq(_modes, [BuildCatalogue.BUILD] as Array[StringName])
	assert_eq(_catalogue.mode, BuildCatalogue.BUILD)
	assert_eq(_catalogue.selected_category, &"walls")
	assert_true(_catalogue.category_buttons[&"walls"].visible)
	assert_true(_catalogue.category_buttons[&"paint"].visible)
	assert_false(_catalogue.category_buttons[&"floor"].visible, "no lot, no Floor tab")
	_catalogue.set_floor_price(15)
	assert_true(_catalogue.category_buttons[&"floor"].visible)
	assert_false(_catalogue.category_buttons[&"dining"].visible)
	for id: StringName in _catalogue.wall_buttons:
		assert_true(_catalogue.wall_buttons[id].visible)
	assert_true(_catalogue.visible_ids().is_empty(), "no furniture on the Build side")
	_catalogue.category_buttons[&"paint"].pressed.emit()
	assert_eq(_paint_requests, 1, "Paint is asked of the session, not switched here")
	_catalogue.set_mode(BuildCatalogue.BUY)
	assert_eq(_catalogue.selected_category, &"dining", "each side remembers its own page")
	_catalogue.set_mode(BuildCatalogue.BUILD)
	assert_eq(_catalogue.selected_category, &"walls")
	_catalogue.tool_buttons[BuildMode.Tool.EYEDROPPER].pressed.emit()
	assert_eq(_tools, [BuildMode.Tool.EYEDROPPER] as Array[int])
	_catalogue.set_tool_state(BuildMode.Tool.SELL, true, false, "buy Round table")
	assert_true(_catalogue.tool_buttons[BuildMode.Tool.SELL].button_pressed)
	assert_false(_catalogue.tool_buttons[BuildMode.Tool.HAND].button_pressed)
	assert_false(_catalogue.undo_button.disabled)
	assert_true(_catalogue.redo_button.disabled)
	assert_eq(_catalogue.undo_button.tooltip_text, "Undo buy Round table (Ctrl+Z)")
	_catalogue.undo_button.pressed.emit()
	assert_eq(_undos, 1)
	# While the shop is open only Paint works.
	_catalogue.set_tool_state(BuildMode.Tool.HAND, false, false, "", "", false)
	assert_true(_catalogue.mode_buttons[BuildCatalogue.BUY].disabled)
	assert_true(_catalogue.category_buttons[&"walls"].disabled)
	assert_false(_catalogue.category_buttons[&"paint"].disabled)


func test_room_readout_shows_vibe_and_theme() -> void:
	var result: VibeModel.Result = VibeModel.Result.new()
	result.valid = true
	result.score = 42.0
	result.active_theme = &"cosy"
	result.theme_label = "Cosy"
	_catalogue.set_vibe(result)
	assert_eq(_catalogue.vibe_meter.caption_label.text, "Vibe 42 / 100")
	assert_eq(_catalogue.theme_label.text, "Theme: Cosy")
	result.active_theme = &""
	_catalogue.set_vibe(result)
	assert_eq(_catalogue.theme_label.text, "No theme yet")
	assert_eq(_catalogue.get_node("Panel/Margin/Rows/Scroll/Content/Categories/Readout/VibeMeter"), _catalogue.vibe_meter)


func _on_mode(mode: StringName) -> void:
	_modes.append(mode)


func _on_paint() -> void:
	_paint_requests += 1


func _on_tool(tool: int) -> void:
	_tools.append(tool)


func _on_undo() -> void:
	_undos += 1
