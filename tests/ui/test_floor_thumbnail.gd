extends TestCase
## Analytic layout checks, not a substitute for rendered seam/zoom review.


func test_new_patterns_repeat_in_world_space_including_negative_coordinates() -> void:
	for pattern: int in [FloorStyleDef.Pattern.HEX_TILE, FloorStyleDef.Pattern.TERRACOTTA]:
		var period: Vector2 = Vector2(0.125, 0.125 * 1.73205081) if pattern == FloorStyleDef.Pattern.HEX_TILE \
			else Vector2(0.25, 0.5)
		for point: Vector2 in [Vector2(-0.437, -0.241), Vector2(0.497, 0.063), Vector2(-0.003, 0.375)]:
			assert_eq(_sample(pattern, point), _sample(pattern, point + period))
			assert_eq(_sample(pattern, point), _sample(pattern, point - period))


func test_pavers_have_square_half_offset_rows_and_darker_bottom_right_joints() -> void:
	var pattern: int = FloorStyleDef.Pattern.TERRACOTTA
	assert_eq(_sample(pattern, Vector2(0.125, 0.125)), Color.WHITE)
	assert_eq(_sample(pattern, Vector2(0.125, 0.375)), Color(0.82, 0.82, 0.82, 1))
	assert_eq(_sample(pattern, Vector2(0.249, 0.125)), Color(0.65, 0.65, 0.65, 1))
	assert_eq(_sample(pattern, Vector2(0.001, 0.125)), Color(0.82, 0.82, 0.82, 1))


func test_hex_centres_and_opposite_edges_match_the_shader_geometry() -> void:
	var pattern: int = FloorStyleDef.Pattern.HEX_TILE
	assert_eq(_sample(pattern, Vector2.ZERO), Color.WHITE)
	assert_eq(_sample(pattern, Vector2(0.0625, 0.108253175)), Color.WHITE)
	assert_eq(_sample(pattern, Vector2(0.061, 0.0)), Color(0.65, 0.65, 0.65, 1))
	assert_eq(_sample(pattern, Vector2(-0.061, 0.0)), Color(0.82, 0.82, 0.82, 1))


func test_new_thumbnails_are_deterministic_distinct_and_opaque() -> void:
	var hex: Image = FloorThumbnail.image(FloorStyleDef.Pattern.HEX_TILE, Color.WHITE, Color.WHITE, false)
	var pavers: Image = FloorThumbnail.image(FloorStyleDef.Pattern.TERRACOTTA, Color.WHITE, Color.WHITE, false)
	assert_ne(hex.get_data(), pavers.get_data())
	assert_eq(hex.get_data(), FloorThumbnail.image(FloorStyleDef.Pattern.HEX_TILE, Color.WHITE, Color.WHITE, false).get_data())
	for picture: Image in [hex, pavers]:
		for y: int in range(picture.get_height()):
			for x: int in range(picture.get_width()):
				assert_eq(picture.get_pixel(x, y).a, 1.0)


func _sample(pattern: int, point: Vector2) -> Color:
	return FloorThumbnail._colour(pattern, point, Color.WHITE, Color.WHITE, Color.WHITE)
