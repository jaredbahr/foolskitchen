extends TestCase
## Tier 1 shop: builds from data, and every spot staff and guests need is reachable.

const LAYOUT := "res://data/layouts/tier1_hole_in_the_wall.tres"

var content: ContentDB
var world: SimWorld


func before_each() -> void:
	content = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray(), "content loads")
	var errors: Array[String] = []
	world = ShopBuilder.build(load(LAYOUT) as ShopLayout, content, errors)
	assert_eq(errors, [] as Array[String], "layout builds cleanly")


func test_tier1_has_the_designed_items() -> void:
	assert_eq(ShopBuilder.items_with_def(world, &"table_2").size(), 3)
	for id: StringName in [&"fridge", &"prep_counter", &"stove", &"pass_counter"]:
		assert_eq(ShopBuilder.items_with_def(world, id).size(), 1, String(id))


func test_guests_reach_every_seat_from_the_street() -> void:
	var entry := world.grid.entries()[0]
	var seats := 0
	for table in ShopBuilder.items_with_def(world, &"table_2"):
		for seat in table.seat_cells:
			seats += 1
			assert_true(world.grid.is_reachable(entry, seat), "seat %s reachable" % seat)
	assert_eq(seats, 6)


func test_staff_reach_their_stations() -> void:
	var layout := load(LAYOUT) as ShopLayout
	var cook_at: Vector2i = layout.staff_spawns[&"cook"]
	var server_at: Vector2i = layout.staff_spawns[&"server"]
	for id: StringName in [&"fridge", &"prep_counter", &"stove"]:
		var it := ShopBuilder.items_with_def(world, id)[0]
		assert_true(world.grid.free_work_cell(it) != SimGrid.NO_CELL, "%s has a usable work cell" % id)
		assert_true(world.grid.is_reachable(cook_at, it.work_cells[0]), "cook reaches %s" % id)
	var pass_counter := ShopBuilder.items_with_def(world, &"pass_counter")[0]
	assert_eq(pass_counter.work_cells.size(), 2, "kitchen side and dining side")
	for c in pass_counter.work_cells:
		assert_true(world.grid.is_reachable(cook_at, c), "cook reaches pass side %s" % c)
		assert_true(world.grid.is_reachable(server_at, c), "server reaches pass side %s" % c)


func test_a_cook_runs_the_full_line() -> void:
	var cook := StaffAgent.new(&"cook", 3)
	cook.cell = (load(LAYOUT) as ShopLayout).staff_spawns[&"cook"]
	world.add_agent(cook)
	var t := SimTask.new(&"cook", &"cook", "Cook burger")
	for id: StringName in [&"fridge", &"prep_counter", &"stove", &"pass_counter"]:
		t.steps.append(TaskStep.go_to_item(ShopBuilder.items_with_def(world, id)[0].id, String(id)))
		t.steps.append(TaskStep.work(10, String(id)))
	world.board.post(t, world.now)
	for i in 600:
		world.advance()
	assert_eq(t.state, SimTask.State.DONE, "burger made: %s" % [world.event_log])


func test_unknown_item_is_reported() -> void:
	var layout := (load(LAYOUT) as ShopLayout).duplicate(true) as ShopLayout
	var bad := ShopPlacement.new()
	bad.item_id = &"hot_tub"
	layout.placements.append(bad)
	var errors: Array[String] = []
	var w := ShopBuilder.build(layout, content, errors)
	assert_not_null(w, "a world is still returned")
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("hot_tub"))
