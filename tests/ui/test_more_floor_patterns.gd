extends TestCase
## Analytic thumbnail/layout tests. Rendered panning/zoom acceptance is separate.


func test_integer_hash_has_stable_negative_and_large_coordinate_samples() -> void:
	for p: Vector2i in [Vector2i.ZERO, Vector2i(-1, -1), Vector2i(7, 91), Vector2i(-200, 37), Vector2i(65535, 65535)]:
		var h: float = FloorThumbnail._lattice_hash(p)
		assert_true(h >= 0.0 and h <= 1.0)
		assert_eq(h, FloorThumbnail._lattice_hash(p + Vector2i(65536, -65536)))
	assert_eq(FloorThumbnail._lattice_hash(Vector2i.ZERO), 0.0)
	assert_ne(FloorThumbnail._lattice_hash(Vector2i(1, 2)), FloorThumbnail._lattice_hash(Vector2i(2, 1)))


func test_terrazzo_chips_follow_world_lattice_and_have_two_accent_shades() -> void:
	for cell: Vector2i in [Vector2i(-2, 0), Vector2i.ZERO, Vector2i(1, 3), Vector2i(8, -7)]:
		var h: float = FloorThumbnail._lattice_hash(cell)
		var j: float = FloorThumbnail._lattice_hash(cell + Vector2i(37, 91))
		var centre: Vector2 = (Vector2(cell) + Vector2(0.25 + h * 0.5, 0.25 + j * 0.5)) * 0.125
		var expected: Color = Color.WHITE * (1.0 if h < 0.5 else 0.8)
		expected.a = 1.0
		assert_eq(_sample(FloorStyleDef.Pattern.TERRAZZO, centre, Color.BLACK), expected)
		assert_eq(_sample(FloorStyleDef.Pattern.TERRAZZO, Vector2(cell) * 0.125, Color.BLACK), Color.BLACK)


func test_concrete_joints_are_metres_apart_not_cell_boundaries() -> void:
	var pattern: int = FloorStyleDef.Pattern.CONCRETE
	assert_eq(_sample(pattern, Vector2(0.0, 0.3)), Color.WHITE)
	assert_eq(_sample(pattern, Vector2(-1.0, 0.3)), Color.WHITE)
	assert_ne(_sample(pattern, Vector2(0.5, 0.3)), Color.WHITE)


func test_carpet_weave_repeats_across_cells_without_a_joint() -> void:
	var pattern: int = FloorStyleDef.Pattern.CARPET
	for p: Vector2 in [Vector2(-0.49, 0.01), Vector2(0.017, 0.02), Vector2(0.5, 0.5)]:
		assert_eq(_sample(pattern, p), _sample(pattern, p + Vector2(0.5, 0.5)))
		assert_ne(_sample(pattern, p), Color.WHITE)


func test_new_thumbnails_are_distinct_repeatable_and_opaque() -> void:
	var pictures: Array[PackedByteArray] = []
	for pattern: int in [FloorStyleDef.Pattern.TERRAZZO, FloorStyleDef.Pattern.CONCRETE, FloorStyleDef.Pattern.CARPET]:
		var picture: Image = FloorThumbnail.image(pattern, Color(0.6, 0.5, 0.4), Color.WHITE, false)
		assert_eq(picture.get_data(), FloorThumbnail.image(pattern, Color(0.6, 0.5, 0.4), Color.WHITE, false).get_data())
		assert_false(pictures.has(picture.get_data()))
		pictures.append(picture.get_data())
		for y: int in range(picture.get_height()):
			for x: int in range(picture.get_width()):
				assert_eq(picture.get_pixel(x, y).a, 1.0)


func _sample(pattern: int, p: Vector2, main: Color = Color(0.6, 0.5, 0.4)) -> Color:
	return FloorThumbnail._colour(pattern, p, main, Color.WHITE, Color.WHITE)
