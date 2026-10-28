extends TestCase
## D25: the floor's per-cell data texture. One texel per grid cell (r pattern,
## g colour, b accent, a threshold mask) read by the single floor material; a
## default shop is all zero (the legacy planks, unchanged); the entry and a
## back door's threshold tile copy the floor inside them and share the floor
## material; the map follows the grid when floor is bought beyond it.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _view: ShopView
var _content: ContentDB
var _sim: RestaurantSim
var _editor: ShopEditor
var _cash: int = 100000


func before_each() -> void:
	_content = ContentDB.new()
	assert_eq(_content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, _content, 1, errors, null, false)
	assert_eq(errors, [] as Array[String])
	_cash = 100000
	_editor = ShopEditor.new(_sim, _content, ShopEditBooks.new(_can_spend, _record), LAYOUT)
	_editor.set_owner_level(6)
	_view = VIEW.instantiate() as ShopView
	(Engine.get_main_loop() as SceneTree).root.add_child(_view)
	_view.show_world(_sim.world)
	_view.set_paint(_content, _editor.wall_swatch_id, _editor.floor_swatch_id)
	_view.bind_floor_finishes(_editor.floors)


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()
	_editor = null
	_sim = null
	_content = null


func test_default_shop_map_is_all_zero_and_bound_to_the_floor_material() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_eq(_view.finish_image.get_size(), grid.size)
	assert_eq(_view.finish_origin(), grid.origin)
	for cell: Vector2i in grid.cells():
		assert_eq(_view.finish_texel(cell), Color(0, 0, 0, 0), "%s draws the legacy planks" % cell)
	var material: ShaderMaterial = _view.floor_mesh.material_override as ShaderMaterial
	assert_eq(material.shader.resource_path, "res://src/world/floor_finish.gdshader")
	assert_eq(material.get_shader_parameter("finish_map"), _view.finish_texture)
	assert_eq(material.get_shader_parameter("map_size"), grid.size)
	assert_eq(material.get_shader_parameter("map_origin"), grid.origin)
	var palette: PackedColorArray = material.get_shader_parameter("palette")
	assert_eq(palette.size(), ShopView.FINISH_PALETTE_SIZE)
	assert_eq(palette[ShopView.FINISH_FIRST_SWATCH], _content.swatches()[0].color)


func test_laid_floor_writes_pattern_colours_and_thresholds() -> void:
	assert_true(_editor.apply_flooring(_editor.lay_changes(_rect(2, 6, 2, 2), &"checker", &"cream", &"charcoal")))
	assert_true(_editor.apply_flooring(_editor.lay_changes(_rect(4, 6, 1, 1), &"narrow_planks", &"")))
	var checker: Color = _view.finish_texel(Vector2i(2, 6))
	assert_eq(checker.r8, FloorStyleDef.Pattern.CHECKER)
	assert_eq(checker.g8, _palette_index(&"cream"))
	assert_eq(checker.b8, _palette_index(&"charcoal"))
	assert_eq(checker.a8, 1 | 2, "default planks west and north of the corner cell")
	assert_eq(_view.finish_texel(Vector2i(3, 7)).a8, 4 | 8)
	assert_eq(_view.finish_texel(Vector2i(3, 6)).a8, 2 | 4, "narrow planks east are another type too")
	var planks: Color = _view.finish_texel(Vector2i(4, 6))
	assert_eq(planks.r8, FloorStyleDef.Pattern.NARROW_PLANKS)
	assert_eq(_editor.floor_swatch_id, &"", "this shop's floor is the original brown")
	assert_eq(planks.g8, ShopView.FINISH_SHOP_COLOUR, "the shop's own colour reads floor_color, as before")
	assert_eq(planks.b8, 0, "no accent: a darker shade of the colour")
	assert_eq(_view.finish_texel(Vector2i(1, 6)).a8, 4, "the default neighbour gets its half of the line")
	assert_eq(_view.finish_texel(Vector2i(8, 8)), Color(0, 0, 0, 0))
	# With the floor painted another colour, the original brown is a palette colour.
	_view.set_paint(_content, &"", &"walnut")
	assert_eq(_view.finish_texel(Vector2i(4, 6)).g8, ShopView.FINISH_AUTHORED_COLOUR)
	_view.set_paint(_content, &"", &"")
	# Same type, another colour: no threshold line.
	assert_true(_editor.apply_flooring(_editor.recolour_changes(_rect(2, 6, 1, 1), &"sage")))
	assert_eq(_view.finish_texel(Vector2i(2, 6)).a8, 1 | 2)
	assert_eq(_view.finish_texel(Vector2i(2, 6)).g8, _palette_index(&"sage"))


func test_entry_and_back_door_copy_the_floor_inside_and_share_the_material() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_editor.apply_flooring(_editor.lay_changes(_editor.floor_room_cells(Vector2i(6, 8)), &"checker",
		&"cream", &"charcoal")))
	for entry: Vector2i in grid.entries():
		assert_eq(_view.finish_texel(entry).r8, FloorStyleDef.Pattern.CHECKER, "street entry %s" % entry)
		assert_eq(_view.finish_texel(entry).a8, 0, "no line across the doorway")
	assert_true(_editor.apply_flooring(_editor.lay_changes(_editor.floor_room_cells(Vector2i(3, 2)), &"small_tile",
		&"cream")))
	var edge: Vector3i = SimGrid.edge_between(Vector2i(10, 1), Vector2i(10, 0))
	grid.set_segment(edge, SimGrid.Segment.DOORWAY)
	assert_eq(_view.finish_texel(Vector2i(10, 0)).r8, FloorStyleDef.Pattern.SMALL_TILE, "the back door's threshold")
	var door: Node3D = _view.segment_view.get_node_or_null("BackDoor_10_0") as Node3D
	assert_not_null(door)
	var tile: MeshInstance3D = door.get_node_or_null("Floor") as MeshInstance3D
	assert_not_null(tile)
	assert_eq(tile.material_override, _view.floor_mesh.material_override, "one floor material, one map")
	assert_eq(_view.finish_texel(Vector2i(9, 0)), Color(0, 0, 0, 0), "walls stay empty")


func test_map_follows_the_grid_when_floor_grows_and_drops_removed_looks() -> void:
	var grid: SimGrid = _sim.world.grid
	assert_true(_editor.apply_flooring(_editor.lay_changes(_rect(2, 6, 1, 1), &"herringbone", &"walnut")))
	var before: Vector2i = grid.size
	assert_true(_editor.apply_floor(_rect(6, -3, 9, 3), true), _editor.last_check.why)
	assert_ne(grid.size, before, "the grid grew")
	assert_eq(_view.finish_image.get_size(), grid.size)
	assert_eq(_view.finish_origin(), grid.origin)
	assert_eq((_view.floor_mesh.material_override as ShaderMaterial).get_shader_parameter("map_origin"), grid.origin)
	assert_eq(_view.finish_texel(Vector2i(2, 6)).r8, FloorStyleDef.Pattern.HERRINGBONE, "kept through the shift")
	assert_eq(_view.finish_texel(Vector2i(8, -2)), Color(0, 0, 0, 0), "new floor is the default")
	assert_true(_editor.apply_flooring(_editor.lay_changes(_rect(8, -2, 1, 1), &"checker", &"cream")))
	assert_eq(_view.finish_texel(Vector2i(8, -2)).r8, FloorStyleDef.Pattern.CHECKER)
	assert_true(_editor.apply_floor(_rect(6, -3, 9, 3), false), _editor.last_check.why)
	assert_eq(_editor.floors.finish(Vector2i(8, -2)).style, FloorStyleDef.DEFAULT_ID)
	assert_eq(_view.finish_texel(Vector2i(8, -2)), Color(0, 0, 0, 0))


func test_previews_draw_over_the_floor_and_clear_without_changing_it() -> void:
	var proposal: Dictionary[Vector2i, FloorFinishes.Finish] = _editor.lay_changes(_rect(2, 6, 2, 1), &"small_tile", &"sage")
	_view.preview_floor_finishes(proposal)
	assert_eq(_view.finish_texel(Vector2i(2, 6)).r8, FloorStyleDef.Pattern.SMALL_TILE)
	assert_eq(_editor.floors.count(), 0, "a preview changes nothing")
	_view.clear_floor_preview()
	assert_eq(_view.finish_texel(Vector2i(2, 6)), Color(0, 0, 0, 0))
	_view.preview_floor_finishes(proposal)
	_view.clear_paint_preview()
	assert_eq(_view.finish_texel(Vector2i(2, 6)), Color(0, 0, 0, 0), "leaving paint clears a floor hover too")


func _palette_index(swatch_id: StringName) -> int:
	return ShopView.FINISH_FIRST_SWATCH + _content.swatches().find(_content.swatch(swatch_id))


func _rect(x: int, y: int, w: int, h: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in range(y, y + h):
		for column: int in range(x, x + w):
			out.append(Vector2i(column, row))
	return out


func _can_spend(amount: int) -> bool:
	return amount <= _cash


func _record(amount: int, _category: StringName) -> void:
	_cash += amount
