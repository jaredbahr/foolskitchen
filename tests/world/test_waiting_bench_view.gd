extends TestCase
## Waiting seats use the same authored height and facing as dining benches,
## without inventing a dining-table reservation or moving simulation cells.

var _world: SimWorld
var _restaurant: RestaurantSim
var _view: ShopView


func before_each() -> void:
	_world = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	_restaurant = RestaurantSim.new()
	_restaurant.world = _world
	_view = ShopView.new()
	_view.world = _world


func after_each() -> void:
	_view.free()
	_restaurant = null
	_world = null


func test_waiting_bench_supplies_rotated_facing_and_measured_height_without_a_table() -> void:
	for turns: int in range(4):
		var bench: PlacedItem = _bench(turns)
		var guest: CustomerAgent = _guest(bench, bench.seat_cells[0])
		var before: int = guest.rng.state
		var facings: Dictionary[int, Vector3] = _view._dining_seat_facings()
		var heights: Dictionary[int, float] = _view._dining_seat_heights()
		var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(
			guest, _world, heights[guest.id], 0.0, facings[guest.id])
		var origin: Vector2i = GridMath.rotate_cell(Vector2i.ZERO, Vector2i(2, 1), turns)
		var front: Vector2i = GridMath.rotate_cell(Vector2i.UP, Vector2i(2, 1), turns) - origin
		assert_true(frame.seated)
		assert_eq(frame.clip, &"sit")
		assert_almost_eq(frame.seat_height, 0.24 * ArtScale.FURNITURE_SCALE)
		assert_eq(frame.facing_direction, Vector3(front.x, 0.0, front.y))
		assert_eq(frame.floor_position, GridMath.cell_to_world(guest.waiting_cell))
		assert_eq(guest.table_item_id, 0)
		assert_eq(guest.seat_cell, SimGrid.NO_CELL)
		assert_eq(_world.grid.dining_furnishing_id(guest.waiting_cell), 0)
		assert_eq(guest.rng.state, before)
		assert_eq(_world.now, 0)
		_world.remove_agent(guest)
		_world.grid.remove(bench.id)


func test_reserved_waiter_walks_until_arrival_and_lost_reservation_never_sits() -> void:
	var bench: PlacedItem = _bench()
	var guest: CustomerAgent = _guest(bench, bench.seat_cells[0])
	guest.cell = guest.waiting_cell + Vector2i.DOWN
	guest.path = [guest.cell, guest.waiting_cell]
	guest.path_index = 1
	var frame: AgentPresentationController.Frame = AgentPresentationController.frame_for(guest, _world)
	assert_false(frame.seated)
	assert_eq(frame.clip, &"walk")
	guest.cell = guest.waiting_cell
	guest.clear_path()
	assert_true(AgentPresentationController.frame_for(guest, _world).seated)
	bench.release(guest.waiting_cell, guest.id)
	assert_false(AgentPresentationController.frame_for(guest, _world).seated)
	assert_true(bench.reserve(guest.waiting_cell, guest.id))
	_world.grid.remove(bench.id)
	assert_false(AgentPresentationController.frame_for(guest, _world).seated)


func test_two_waiters_keep_distinct_bench_positions_and_share_the_seat_surface() -> void:
	var bench: PlacedItem = _bench()
	var left: CustomerAgent = _guest(bench, bench.seat_cells[0])
	var right: CustomerAgent = _guest(bench, bench.seat_cells[1])
	var frames: Dictionary[int, AgentPresentationController.Frame] = AgentPresentationController.frames_for(
		_world.agents, _world, _view._dining_seat_heights(), _view._dining_seat_facings(),
		_view._dining_seat_offsets(), _view._dining_seat_leans())
	assert_true(frames[left.id].seated)
	assert_true(frames[right.id].seated)
	assert_eq(frames[left.id].display_offset, Vector3.ZERO)
	assert_eq(frames[right.id].display_offset, Vector3.ZERO)
	assert_almost_eq(frames[left.id].floor_position.distance_to(frames[right.id].floor_position), GridMath.CELL_SIZE)
	assert_almost_eq(frames[left.id].seat_height, frames[right.id].seat_height)
	assert_eq(bench.reserved_by(left.waiting_cell), left.id)
	assert_eq(bench.reserved_by(right.waiting_cell), right.id)


func _bench(turns: int = 0) -> PlacedItem:
	var definition: ItemDef = ItemDef.new()
	definition.id = &"waiting_bench"
	definition.category = ItemDef.Category.WAITING
	definition.footprint = Vector2i(2, 1)
	definition.solid = false
	definition.seat_cells = [Vector2i.ZERO, Vector2i.RIGHT]
	var bench: PlacedItem = _world.grid.place_def(definition, Vector2i(3, 3), turns)
	var visual: ItemVisual = ItemVisual.new()
	visual.prop = PropView.new()
	visual.prop.seat_surface_y = 0.24
	visual.add_child(visual.prop)
	_view.add_child(visual)
	_view.item_nodes[bench.id] = visual
	return bench


func _guest(bench: PlacedItem, seat: Vector2i) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	var guest: CustomerAgent = _world.add_agent(CustomerAgent.new(_restaurant, random)) as CustomerAgent
	guest.state = CustomerAgent.State.QUEUED
	guest.waiting_item_id = bench.id
	guest.waiting_cell = seat
	guest.cell = seat
	guest.clear_path()
	assert_true(bench.reserve(seat, guest.id))
	return guest
