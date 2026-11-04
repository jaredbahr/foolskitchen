extends TestCase
## Morning resets put every staff member on its own post, whatever order the
## night ended in (#298). A higher-ID worker left mid-edge toward a lower-ID
## worker's post must not make that post look claimed.


## Walks its route and does nothing else, like the movement fixtures.
class Walker extends StaffAgent:
	func tick(world: SimWorld) -> void:
		step_move(world)


func test_mid_edge_worker_does_not_displace_a_lower_id_post() -> void:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(SimGrid.from_ascii(PackedStringArray([
		"#######", "#.....#", "#.....#", "#.....#", "#######",
	])))
	var stream: RandomNumberGenerator = RandomNumberGenerator.new()
	stream.seed = 41
	sim.spawner = CustomerSpawner.new(stream)
	var cook: Walker = Walker.new(&"cook", 1)
	cook.cell = Vector2i(2, 3)
	var server: Walker = Walker.new(&"server", 2)
	server.cell = Vector2i(3, 1)
	sim.world.add_agent(cook)
	sim.world.add_agent(server)
	var cook_post := Vector2i(2, 1)
	var server_post := Vector2i(5, 3)
	sim.staff_spawns[&"cook"] = cook_post
	sim.staff_spawns[&"server"] = server_post
	# The server is on its way to the cook's post when the night ends.
	server.install_movement_route([Vector2i(3, 1), cook_post] as Array[Vector2i])
	sim.world.clock.phase = SimClock.Phase.OPEN
	var mid_edge: bool = false
	for _tick: int in 12:
		sim.world.advance()
		if server.move_progress > 0.0 and server.next_cell() == cook_post:
			mid_edge = true
			break
	assert_true(mid_edge, "fixture: the server holds the cook's post as its next cell")
	sim.world.clock.phase = SimClock.Phase.CLOSED
	sim.start_day()
	assert_eq(cook.cell, cook_post, "the cook starts at its own post")
	assert_eq(server.cell, server_post, "the server starts at its own post")
