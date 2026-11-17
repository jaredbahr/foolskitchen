extends TestCase

const TUNING: TipJarTuning = preload("res://data/balance/tip_jar.tres")
const JAR: ItemDef = preload("res://data/items/tip_jar.tres")
const TABLE: ItemDef = preload("res://data/items/table_2.tres")


func test_shipped_jar_is_level_two_table_decor_and_a_25_dollar_buy() -> void:
	assert_true(JAR.placement_layer_valid())
	assert_true(JAR.sits_on_surface())
	assert_false(JAR.solid)
	assert_eq(JAR.buy_room(), &"decor")
	assert_eq(CatalogueText.group_for(JAR), &"accents")
	assert_eq(JAR.price, 25)
	assert_eq(JAR.unlock_level, 2)
	assert_true(JAR.catalogue_visible)
	assert_false(JAR.announce_unlock)


func test_till_bar_and_pass_each_apply_the_same_three_cell_range() -> void:
	for path: String in ["order_counter", "bar_counter", "pass_counter"]:
		var counter: ItemDef = load("res://data/items/%s.tres" % path) as ItemDef
		var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([
			"........", "........", "........", "........", "........", "........"]))
		assert_not_null(grid.place_def(counter, Vector2i(1, 1)))
		var near: Vector2i = Vector2i(1, 4)
		var far: Vector2i = Vector2i(5, 4)
		assert_not_null(grid.place_def(TABLE, near))
		assert_not_null(grid.place_def(TABLE, far))
		assert_false(TUNING.has_eligible_jar(grid), "no jar")
		var far_jar: PlacedItem = grid.place_def(JAR, far)
		assert_not_null(far_jar)
		assert_false(TUNING.has_eligible_jar(grid), "%s is out of range" % path)
		var near_jar: PlacedItem = grid.place_def(JAR, near)
		assert_not_null(near_jar)
		assert_true(TUNING.has_eligible_jar(grid), "%s is three cells away" % path)
		var another: PlacedItem = grid.place_def(JAR, Vector2i(2, 1))
		assert_not_null(another)
		assert_true(TUNING.has_eligible_jar(grid), "a second qualifying jar also satisfies the check")
		assert_true(grid.remove(near_jar.id))
		assert_true(grid.remove(another.id))
		assert_false(TUNING.has_eligible_jar(grid), "only the distant jar remains")


func test_no_support_means_no_change_even_next_to_the_till() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray([".....", ".....", "....."]))
	assert_not_null(grid.place_def(preload("res://data/items/order_counter.tres"), Vector2i(1, 1)))
	assert_not_null(grid.place_def(JAR, Vector2i(1, 2)))
	assert_false(TUNING.has_eligible_jar(grid))
