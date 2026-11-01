extends TestCase
## FK-045 selection, pointer state, keyboard rotation and native ghost geometry.

const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

class Catalog extends ContentDB:
	var extra: Dictionary[StringName, ItemDef] = {}

	func item(id: StringName) -> ItemDef:
		return extra[id] if extra.has(id) else super.item(id)


var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _mode: BuildMode
var _library: BlueprintLibrary
var _cash: int = 10000
var _stamp_calls: int = 0


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 83, errors)
	assert_eq(errors, [] as Array[String])
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash))
	_library = BlueprintLibrary.new()
	_mode = BuildMode.new()
	_mode.bind_session(_editor, _sim.world, _content, _move, _buy, _sell)
	_mode.bind_blueprints(_library, _stamp)
	assert_true(_mode.enter())


func after_each() -> void:
	_mode.bind_blueprints(null, Callable())
	_mode.bind_session(null, null, null, Callable(), Callable(), Callable())
	_mode = null
	_editor = null
	_library = null
	_sim = null
	_content = null


func test_box_in_both_directions_selects_whole_items_but_not_door() -> void:
	assert_true(_mode.begin_blueprint_selection())
	var grid: SimGrid = _sim.world.grid
	assert_true(_mode.blueprint_press(grid.bounds.end - Vector2i.ONE))
	_mode.blueprint_pointer(grid.bounds.position)
	assert_true(_mode.blueprint_release(grid.bounds.position))
	for placed: PlacedItem in grid.items():
		assert_eq(_mode.blueprint_selection.has(placed.id), Blueprint.eligible(placed.def as ItemDef))
	assert_true(_mode.save_blueprint(""))
	assert_eq(_library.blueprints.size(), 1)
	assert_eq(_library.blueprints[0].display_name, CatalogueText.blueprint_default_name(1))
	assert_eq(_mode.state, BuildMode.State.IDLE)


func test_partial_footprint_is_not_selected_and_empty_selection_cannot_save() -> void:
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	assert_true(_mode.begin_blueprint_selection())
	assert_true(_mode.blueprint_press(table.origin))
	_mode.blueprint_release(table.origin)
	assert_false(_mode.blueprint_selection.has(table.id))
	assert_false(_mode.save_blueprint("Partial table"))
	assert_eq(_library.blueprints.size(), 0)


func test_rugs_and_furniture_above_them_are_selected_together() -> void:
	var grid: SimGrid = _sim.world.grid
	var table: PlacedItem = ShopBuilder.items_with_def(_sim.world, &"table_2")[0]
	var rug: PlacedItem = grid.place_def(_content.item(&"rug_round"), table.origin)
	assert_not_null(rug)
	assert_true(_mode.begin_blueprint_selection())
	assert_true(_mode.blueprint_press(table.origin))
	_mode.blueprint_release(table.origin + Vector2i.ONE)
	assert_true(_mode.blueprint_selection.has(table.id))
	assert_true(_mode.blueprint_selection.has(rug.id))
	assert_true(_mode.save_blueprint("Table and rug"))
	assert_eq(_library.blueprints[0].entries.size(), 2)


func test_ghost_rotates_four_ways_and_refusal_never_calls_stamp() -> void:
	var blueprint: Blueprint = _plant_blueprint()
	assert_true(_mode.begin_blueprint(blueprint, Vector2i(-50, -50)))
	assert_true(_mode.has_ghost())
	for turns: int in range(4):
		assert_eq(_mode.quarter_turns, turns)
		assert_false(_mode.current_check.ok)
		assert_false(_mode.commit())
		assert_true(_mode.rotate())
	assert_eq(_stamp_calls, 0)
	assert_eq(_mode.quarter_turns, 0)
	assert_true(_mode.rotate(-1))
	assert_eq(_mode.quarter_turns, 3)
	_mode.update_origin(Vector2i(9, 9))
	assert_eq(_mode.origin, Vector2i(9, 9))
	assert_eq(_mode.blueprint_cost(), blueprint.total_price(_content))
	assert_true(_mode.blueprint_summary().contains(Fmt.money(blueprint.total_price(_content))))
	assert_true(_mode.cancel_ghost())
	assert_eq(_mode.state, BuildMode.State.IDLE)
	assert_null(_mode.selected_blueprint)


func test_leaving_build_or_opening_clears_selection_and_ghost() -> void:
	assert_true(_mode.begin_blueprint_selection())
	assert_true(_mode.blueprint_press(Vector2i.ONE))
	_mode.exit()
	assert_false(_mode.blueprint_dragging)
	assert_true(_mode.blueprint_selection.is_empty())
	assert_true(_mode.enter())
	assert_true(_mode.begin_blueprint(_plant_blueprint(), Vector2i.ZERO))
	_sim.world.clock.phase = SimClock.Phase.OPEN
	_mode.refresh()
	assert_eq(_mode.state, BuildMode.State.INACTIVE)
	assert_false(_mode.save_blueprint("During service"))
	assert_false(_mode.begin_blueprint_selection())
	assert_false(_mode.commit())


func test_native_group_ghost_is_red_when_refused_and_clears_on_cancel() -> void:
	var blueprint: Blueprint = _plant_blueprint()
	var second: ShopPlacement = blueprint.entries[0].duplicate() as ShopPlacement
	second.origin = Vector2i(3, 0)
	blueprint.entries.append(second)
	# Acquire native scenes after autoload initialization; entry-script
	# scene preloads can retain a cyclic script graph at shutdown.
	var view: ShopView = (load("res://src/world/shop_view.tscn") as PackedScene).instantiate() as ShopView
	view.show_world(_sim.world)
	var preview: BuildPreview = (load("res://src/world/build_preview.tscn") as PackedScene).instantiate() as BuildPreview
	preview.bind_build_mode(_mode, view)
	assert_true(_mode.begin_blueprint(blueprint, Vector2i(-30, -30)))
	assert_eq(preview.blueprint_ghosts.size(), 2)
	for ghost: ItemVisual in preview.blueprint_ghosts:
		assert_false(ghost.get_meta("valid"))
	assert_eq(preview.invalid_reason(), _mode.current_check.why)
	# Editor proposals use one negative id per entry; warnings must follow
	# both ghosts instead of looking for live items with those ids.
	_mode.current_check = EditCheck.new(true)
	_mode.current_check.unreachable = [-1, -2] as Array[int]
	_mode.changed.emit()
	assert_eq(preview.displayed_warning_ids(), [-2, -1] as Array[int])
	_mode.cancel_ghost()
	assert_true(preview.blueprint_ghosts.is_empty())
	assert_true(_mode.begin_blueprint_selection())
	_mode.blueprint_press(_sim.world.grid.bounds.position)
	_mode.blueprint_release(_sim.world.grid.bounds.end - Vector2i.ONE)
	assert_not_null(preview.blueprint_selection_mesh)
	_mode.exit()
	assert_null(preview.blueprint_selection_mesh)
	preview.clear()
	preview.free()
	view.show_world(null)
	view.free()


func test_variant_buy_then_blueprint_uses_stamp_command() -> void:
	_editor.set_owner_level(6)
	assert_true(_mode.begin_buy(&"diner_stool", Vector2i.ZERO, &"stool_chrome_teal"))
	var blueprint: Blueprint = _plant_blueprint()
	var destination: Vector2i = SimGrid.NO_CELL
	for y: int in range(_sim.world.grid.bounds.position.y, _sim.world.grid.bounds.end.y):
		for x: int in range(_sim.world.grid.bounds.position.x, _sim.world.grid.bounds.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if _editor.check_stamp(blueprint, cell, 0).ok:
				destination = cell
				break
		if destination != SimGrid.NO_CELL:
			break
	assert_ne(destination, SimGrid.NO_CELL)
	assert_true(_mode.begin_blueprint(blueprint, destination))
	assert_eq(_mode.buy_variant_id, &"")
	assert_true(_mode.commit())
	assert_eq(_stamp_calls, 1)


func test_blueprint_presentation_and_native_ghosts_retain_both_authored_looks() -> void:
	var blueprint: Blueprint = Blueprint.new()
	blueprint.display_name = "White and Walnut"
	for index: int in 2:
		var entry: ShopPlacement = ShopPlacement.new()
		entry.item_id = &"diner_booth"
		entry.origin = Vector2i(3 * index, 0)
		entry.variant_id = &"booth_white" if index == 0 else &"booth_walnut"
		blueprint.entries.append(entry)
	var view: ShopView = (load("res://src/world/shop_view.tscn") as PackedScene).instantiate() as ShopView
	view.show_world(_sim.world)
	var preview: BuildPreview = (load("res://src/world/build_preview.tscn") as PackedScene).instantiate() as BuildPreview
	preview.bind_build_mode(_mode, view)
	assert_true(_mode.begin_blueprint(blueprint, Vector2i(-30, -30)))
	for turns: int in 4:
		var visuals: Array = _mode.presentation_state().get("blueprint_visuals", [])
		assert_eq(visuals.size(), 2)
		assert_eq(preview.blueprint_ghosts.size(), 2)
		for index: int in visuals.size():
			var expected: StringName = blueprint.entries[index].variant_id
			assert_eq((visuals[index] as Dictionary).get("variant_id", &""), expected)
			var ghost: ItemVisual = preview.blueprint_ghosts[index]
			assert_not_null(ghost.prop)
			if ghost.prop == null:
				continue
			var applied: ItemVariant = ghost.prop.get("_variant") as ItemVariant
			assert_not_null(applied)
			if applied != null:
				assert_eq(applied.id, expected, "the native wrapper selected the authored look")
			# Remove only the presentation tint to expose the controller's selected
			# material; no variant is applied by this test to repair a lost look.
			ghost.prop.clear_body_tint()
			var colour: StringName = &"carpetWhite" if index == 0 else &"woodDark"
			var material: BaseMaterial3D = _ghost_surface_material(ghost, &"carpetWhite")
			assert_not_null(material)
			if material != null:
				assert_eq(material.albedo_color, KitMaterialColours.colours()[colour])
		assert_true(_mode.rotate())
	assert_true(_mode.cancel_ghost())
	assert_true(preview.blueprint_ghosts.is_empty())
	preview.clear()
	preview.free()
	view.show_world(null)
	view.free()


func test_priced_look_blueprint_cost_summary_and_check_use_variant_total() -> void:
	var catalog: Catalog = Catalog.new()
	assert_eq(catalog.load_all(), PackedStringArray())
	var definition: ItemDef = catalog.item(&"potted_plant").duplicate() as ItemDef
	var original: ItemVariant = ItemVariant.new()
	original.id = &"original"
	original.display_name = "Original"
	var alternative: ItemVariant = original.duplicate() as ItemVariant
	alternative.id = &"plus17"
	alternative.display_name = "Plus 17"
	alternative.price_delta = 17
	definition.variants = [original, alternative]
	catalog.extra[definition.id] = definition
	_content = catalog
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record_cash))
	_editor.set_owner_level(20)
	_mode.bind_session(_editor, _sim.world, _content, _move, _buy, _sell)
	assert_true(_mode.enter())
	var blueprint: Blueprint = _plant_blueprint()
	blueprint.entries[0].variant_id = alternative.id
	assert_true(_mode.begin_blueprint(blueprint, Vector2i(4, 9)))
	var expected: int = definition.price + 17
	assert_true(_mode.current_check.ok, _mode.current_check.why)
	assert_eq(_mode.current_check.cost, expected)
	assert_eq(_mode.blueprint_cost(), expected)
	assert_true(_mode.blueprint_summary().contains(Fmt.money(expected)))


func _ghost_surface_material(ghost: ItemVisual, name: StringName) -> BaseMaterial3D:
	for mesh: MeshInstance3D in ghost.rendered_meshes():
		for index: int in mesh.mesh.get_surface_count():
			var source: Material = mesh.mesh.surface_get_material(index)
			if source != null and StringName(source.resource_name) == name:
				return mesh.get_active_material(index) as BaseMaterial3D
	return null


func _plant_blueprint() -> Blueprint:
	var plants: Array[PlacedItem] = ShopBuilder.items_with_def(_sim.world, &"potted_plant")
	return Blueprint.capture(_sim.world.grid, [plants[0].id] as Array[int], "Plant corner")


func _can_spend(amount: int) -> bool:
	return amount >= 0 and _cash >= amount


func _record_cash(amount: int, _category: StringName) -> void:
	_cash += amount


func _move(id: int, cell: Vector2i, turns: int) -> bool:
	return _editor.move(id, cell, turns)


func _buy(id: StringName, cell: Vector2i, turns: int) -> bool:
	return _editor.buy(id, cell, turns)


func _sell(id: int) -> int:
	return _editor.sell(id)


func _stamp(blueprint: Blueprint, cell: Vector2i, turns: int) -> bool:
	_stamp_calls += 1
	return _editor.stamp(blueprint, cell, turns)
