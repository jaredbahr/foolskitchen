extends TestCase
## Regression: a backrest-clearing pose must not put heads into real tables.
const TABLES: GDScript = preload("res://tools/seated_table_clearance.gd")


func test_authored_cushioned_chair_heads_clear_four_real_tables_with_an_opposite_guest() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	assert_almost_eq(content.item(&"chair").seated_forward_offset, 0.0,
		0.000001, "the accepted small lean keeps the native chair translation")
	assert_true(content.item(&"chair").seated_lean_degrees >= 10.0 \
		and content.item(&"chair").seated_lean_degrees <= 15.0,
		"Jared accepted a small 10–15 degree chair lean")
	var leans: Array[float] = [content.item(&"chair").seated_lean_degrees]
	var turns: Array[int] = [0]
	var looks: Array[int] = [PersonPresentation.GUEST_MODELS.find(&"character-male-c"),
		PersonPresentation.GUEST_MODELS.find(&"character-female-e")]
	var fractions: Array[float] = [0.0]
	var report: Dictionary = await TABLES.run(tree.root, leans, turns, looks, fractions)
	assert_eq(report["errors"], PackedStringArray())
	assert_true(report["coverage_complete"], "all four visible tables and both opposite guests were measured")
	assert_eq((report["pairs"] as Array).size(), 8)
	assert_eq((report["samples"] as Array).size(), 16)
	assert_eq(report["failures"], 0, "no head enters or crosses any real table mesh")
	assert_eq(report["opposite_head_regressions"], 0,
		"the measured small lean must not regress toward the rejected near-collision")
	for sample: Dictionary in report["samples"]:
		var context: String = "%s %s side=%d" % [sample["table"], sample["model"], sample["side"]]
		assert_true(sample["table_visible"], context)
		assert_true(int(sample["table_triangles"]) > 0 and int(sample["head_vertices"]) > 0, context)
		assert_eq(sample["head_vertices_inside_count"], 0, context)
		assert_eq(sample["head_table_surface_crossings"], 0, context)
	for pair: Dictionary in report["pairs"]:
		assert_true(is_finite(float(pair["head_surface_gap"])) and float(pair["head_surface_gap"]) > 0.0,
			"opposite posed head surfaces do not touch; numeric taste acceptance remains Director-owned")
		if pair["table_footprint"] == [2, 1]:
			assert_true(float(pair["head_surface_gap"]) >= TABLES.OPPOSITE_HEAD_REGRESSION_FLOOR,
				"implementation regression floor keeps 2x1 opposite heads apart; not a Director taste assertion")
