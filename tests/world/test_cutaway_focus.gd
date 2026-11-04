extends TestCase
## #205: Cutaway lowers only the interior walls standing in front of the
## camera focus, per camera quarter; walls behind it stay up with their decor.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")

var _sim: RestaurantSim
var _view: ShopView


func before_each() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var errors: Array[String] = []
	_sim = RestaurantSim.create(LAYOUT, content, 1, errors)
	assert_eq(errors, [] as Array[String])
	_view = VIEW.instantiate() as ShopView
	_view.show_world(_sim.world)


func after_each() -> void:
	_view.free()
	_sim = null


func _interior() -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	for edge: Vector3i in _sim.world.grid.segment_edges():
		if WallRules.is_interior(_sim.world.grid, edge):
			edges.append(edge)
	return edges


func _middle(edge: Vector3i) -> Vector2:
	var ends: Array[Vector2i] = SimGrid.edge_vertices(edge)
	return (Vector2(ends[0]) + Vector2(ends[1])) * 0.5 * GridMath.CELL_SIZE


func _look_at(point: Vector2) -> void:
	_view.set_camera_focus(Vector3(point.x, 0.0, point.y))


func test_the_starter_shop_has_interior_walls_to_cut_away() -> void:
	assert_true(_interior().size() >= 2, "the kitchen divider is interior")


func test_up_and_down_keep_their_meaning() -> void:
	_view.set_wall_mode(ShopView.WallMode.UP)
	assert_true(_view.lowered_interior_edges().is_empty(), "Walls Up lowers nothing")
	_view.set_wall_mode(ShopView.WallMode.DOWN)
	var all: Dictionary[Vector3i, bool] = {}
	for edge: Vector3i in _interior():
		all[edge] = true
	assert_eq(_view.lowered_interior_edges(), all, "Walls Down lowers every interior wall")


func test_each_quarter_lowers_only_walls_in_front_of_the_focus() -> void:
	var center: Vector2 = Vector2(_sim.world.grid.size) * GridMath.CELL_SIZE * 0.5
	_look_at(center)
	var focus: Vector2 = _view.cutaway_focus()
	var some_up: bool = false
	var some_down: bool = false
	for quarter: int in 4:
		_view.set_camera_quarter(quarter)
		var away: Vector2 = Vector2(ShopView.AWAY_FROM_CAMERA[quarter]).normalized()
		var lowered: Dictionary[Vector3i, bool] = _view.lowered_interior_edges()
		for edge: Vector3i in _interior():
			var in_front: bool = (_middle(edge) - focus).dot(away) < -ShopView.CUTAWAY_DEAD_BAND_CELLS * GridMath.CELL_SIZE
			assert_eq(lowered.has(edge), in_front, "quarter %d edge %s" % [quarter, edge])
			some_down = some_down or in_front
			some_up = some_up or not in_front
	assert_true(some_down and some_up, "the rule both lowers and keeps walls across the quarters")


func test_moving_the_focus_past_a_wall_lowers_and_raises_it() -> void:
	var edge: Vector3i = _interior()[0]
	_view.set_camera_quarter(0)
	var away: Vector2 = Vector2(ShopView.AWAY_FROM_CAMERA[0]).normalized()
	_look_at(_middle(edge) + away * GridMath.CELL_SIZE * 3.0)
	assert_true(_view.lowered_interior_edges().has(edge), "behind the wall: it stands between camera and focus")
	_look_at(_middle(edge) - away * GridMath.CELL_SIZE * 3.0)
	assert_false(_view.lowered_interior_edges().has(edge), "in front of the wall: it stays up, decor showing")


func test_small_moves_inside_one_cell_never_rebuild_the_walls() -> void:
	_look_at(Vector2(2.6, 2.6))
	var first: Node = _view.segment_view.get_child(0)
	_look_at(Vector2(2.7, 2.65))
	_look_at(Vector2(2.55, 2.74))
	assert_true(is_instance_valid(first) and first == _view.segment_view.get_child(0), "same nodes, no rebuild")


func test_a_standing_far_wall_keeps_its_faces_and_decor_full_height() -> void:
	var edge: Vector3i = _interior()[0]
	_view.set_camera_quarter(0)
	var away: Vector2 = Vector2(ShopView.AWAY_FROM_CAMERA[0]).normalized()
	_look_at(_middle(edge) - away * GridMath.CELL_SIZE * 3.0)
	var lowered: Dictionary[Vector3i, bool] = _view.lowered_interior_edges()
	var cells: Array[Vector2i] = SimGrid.edge_cells(edge)
	var face: Vector3i = WallFaces.make(cells[0], WallFaces.DIRS.find(cells[1] - cells[0]))
	var frame: Dictionary = WallFinishView.face_frame(_sim.world.grid, face, lowered, {} as Dictionary[Vector2i, bool])
	assert_false(bool(frame["lowered"]), "decor hung on it stays visible")
	assert_almost_eq(float(frame["height"]), ArtScale.WALL_HEIGHT, 0.0001)
