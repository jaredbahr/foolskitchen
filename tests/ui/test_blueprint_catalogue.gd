extends TestCase
## FK-045 catalogue names, price, save timing and stable request boundaries.

const SCENE: PackedScene = preload("res://src/ui/build_catalogue.tscn")
var _catalogue: BuildCatalogue
var _content: ContentDB
var _library: BlueprintLibrary
var _selected: Blueprint
var _save_name: String = ""
var _select_requests: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	_library = BlueprintLibrary.new()
	_catalogue = SCENE.instantiate() as BuildCatalogue
	_catalogue.bind_content(_content)
	_catalogue.bind_blueprints(_library)
	_catalogue.set_build_visible(true)
	_catalogue.set_category(BuildCatalogue.BLUEPRINTS)
	_catalogue.blueprint_requested.connect(_on_stamp)
	_catalogue.blueprint_save_requested.connect(_on_save)
	_catalogue.blueprint_selection_requested.connect(_on_select)
	_catalogue.blueprint_rename_requested.connect(_on_rename)
	_catalogue.blueprint_delete_requested.connect(_on_delete)


func after_each() -> void:
	_catalogue.free()
	_library = null
	_content = null
	_selected = null


func test_empty_library_has_tab_name_field_and_disabled_save() -> void:
	assert_true(_catalogue.category_buttons[BuildCatalogue.BLUEPRINTS].visible)
	assert_eq(_catalogue.category_buttons[BuildCatalogue.BLUEPRINTS].text, CatalogueText.BLUEPRINTS)
	assert_eq(_catalogue.blueprint_name.text, "Blueprint 1")
	assert_true(_catalogue.blueprint_save.disabled)
	assert_eq(_catalogue.blueprint_save.tooltip_text, "Saved to your library at the start of tomorrow")
	assert_true(_catalogue.visible_ids().is_empty())
	_catalogue.blueprint_select.pressed.emit()
	assert_eq(_select_requests, 1)
	_catalogue.set_blueprint_selection(2)
	assert_false(_catalogue.blueprint_save.disabled)
	_catalogue.blueprint_name.text = "Breakfast corner"
	_catalogue.blueprint_save.pressed.emit()
	assert_eq(_save_name, "Breakfast corner")
	assert_eq(_library.blueprints.size(), 0, "the catalogue requests rather than saving itself")


func test_cards_show_combined_cost_and_request_the_same_blueprint() -> void:
	var blueprint: Blueprint = _blueprint()
	assert_true(_library.add(blueprint))
	assert_eq(_catalogue.blueprint_buttons.size(), 1)
	var button: Button = _catalogue.blueprint_buttons[0]
	assert_true(button.text.contains(blueprint.display_name))
	assert_true(button.text.contains(Fmt.money(blueprint.total_price(_content))))
	button.pressed.emit()
	assert_eq(_selected, blueprint)
	_catalogue.set_blueprint_selection(3)
	_catalogue.set_tool_state(BuildMode.Tool.HAND, false, false)
	assert_eq(_catalogue.blueprint_buttons[0], button, "pointer refresh preserves native buttons")
	assert_eq(_catalogue.blueprint_name.text, "Blueprint 2")


func test_rename_and_delete_refresh_library_without_mutating_shop() -> void:
	var blueprint: Blueprint = _blueprint()
	assert_true(_library.add(blueprint))
	var row: HBoxContainer = _catalogue.blueprint_rows.get_child(0) as HBoxContainer
	(row.get_node("RenameField") as LineEdit).text = "New corner"
	(row.get_node("Rename") as Button).pressed.emit()
	assert_eq(blueprint.display_name, "New corner")
	assert_true(_catalogue.blueprint_buttons[0].text.contains("New corner"))
	row = _catalogue.blueprint_rows.get_child(0) as HBoxContainer
	(row.get_node("Delete") as Button).pressed.emit()
	assert_true(_library.blueprints.is_empty())
	assert_true(_catalogue.blueprint_buttons.is_empty())


func test_hidden_and_service_catalogue_refuses_requests() -> void:
	var blueprint: Blueprint = _blueprint()
	assert_true(_library.add(blueprint))
	_catalogue.set_blueprint_selection(2)
	_catalogue.set_tool_state(BuildMode.Tool.HAND, false, false, "", "", false)
	assert_true(_catalogue.blueprint_save.disabled)
	assert_true(_catalogue.blueprint_select.disabled)
	assert_true(_catalogue.blueprint_buttons[0].disabled)
	_catalogue.blueprint_select.pressed.emit()
	_catalogue.blueprint_buttons[0].pressed.emit()
	_catalogue.blueprint_save.pressed.emit()
	assert_null(_selected)
	assert_eq(_select_requests, 0)
	assert_eq(_save_name, "")
	_catalogue.set_tool_state(BuildMode.Tool.HAND, false, false, "", "", true)
	_catalogue.set_build_visible(false)
	_catalogue.blueprint_buttons[0].pressed.emit()
	assert_null(_selected)


func _blueprint() -> Blueprint:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "Dining corner"
	for id: StringName in [&"table_2", &"rug_round"]:
		var placement: ShopPlacement = ShopPlacement.new()
		placement.item_id = id
		blueprint.entries.append(placement)
	return blueprint


func _on_stamp(blueprint: Blueprint) -> void:
	_selected = blueprint


func _on_save(name: String) -> void:
	_save_name = name


func _on_select() -> void:
	_select_requests += 1


func _on_rename(blueprint: Blueprint, name: String) -> void:
	_library.rename(blueprint, name)


func _on_delete(blueprint: Blueprint) -> void:
	_library.remove(blueprint)
