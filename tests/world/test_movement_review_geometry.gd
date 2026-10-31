extends TestCase
## Capture acceptance must distinguish a shared passing aisle from two paths
## separated by a thin wall. No scene, people, task or service staging.

const REVIEW: Script = preload("res://tools/movement_review.gd")
const ROOMIER: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")


func test_actual_roomier_kitchen_dining_wall_is_not_a_two_cell_passing_aisle() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	var world: SimWorld = ShopBuilder.build(ROOMIER, content, errors)
	assert_eq(errors, [] as Array[String])
	# Both routes are walkable and parallel, but the real north wall separates
	# these lanes. Opposite directions and half-metre spacing are insufficient.
	for cell: Vector2i in [Vector2i(9, 4), Vector2i(10, 4), Vector2i(9, 5), Vector2i(10, 5)]:
		assert_true(world.grid.is_walkable(cell))
	assert_true(world.grid.step_open(Vector2i(9, 4), Vector2i(10, 4)))
	assert_true(world.grid.step_open(Vector2i(10, 5), Vector2i(9, 5)))
	assert_false(REVIEW.shared_aisle_open(world.grid, Vector2i(9, 4), Vector2i(10, 4), Vector2i.DOWN))
	# The real lower dining two-cell aisle is a positive authored-layout control.
	assert_true(REVIEW.shared_aisle_open(world.grid, Vector2i(4, 9), Vector2i(4, 10), Vector2i.RIGHT))


func test_open_strip_accepts_both_directions_but_each_transverse_wall_refuses() -> void:
	var grid: SimGrid = SimGrid.from_ascii(PackedStringArray(["....", "....", "...."]))
	var from_cell: Vector2i = Vector2i(1, 0)
	var to_cell: Vector2i = Vector2i(2, 0)
	assert_true(REVIEW.shared_aisle_open(grid, from_cell, to_cell, Vector2i.DOWN))
	assert_true(REVIEW.shared_aisle_open(grid, to_cell + Vector2i.DOWN, from_cell + Vector2i.DOWN, Vector2i.UP))
	# Either end can be the hidden partition: checking only one cross-lane edge
	# would still produce a false passing proof for the other wall.
	for edge: Vector3i in [Vector3i(1, 1, SimGrid.EDGE_NORTH), Vector3i(2, 1, SimGrid.EDGE_NORTH)]:
		assert_true(grid.set_segments({edge: SimGrid.Segment.WALL} as Dictionary[Vector3i, int]))
		assert_false(REVIEW.shared_aisle_open(grid, from_cell, to_cell, Vector2i.DOWN))
		assert_true(grid.set_segments({edge: SimGrid.Segment.NONE} as Dictionary[Vector3i, int]))
		assert_true(REVIEW.shared_aisle_open(grid, from_cell, to_cell, Vector2i.DOWN))
