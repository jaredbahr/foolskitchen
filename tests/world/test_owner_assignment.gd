extends TestCase
## Pure target geometry; owner-selected input interception remains session work.

var _grid: SimGrid


func before_each() -> void:
	_grid = SimGrid.new(Vector2i(20, 20))


func test_kitchen_footprints_and_external_work_cells_include_storage_fridge() -> void:
	var definitions: Array[ItemDef] = [
		_definition(&"fridge", ItemDef.Category.STORAGE, &"fridge"),
		_definition(&"prep_counter", ItemDef.Category.STATION, &"prep_counter"),
		_definition(&"stove", ItemDef.Category.STATION, &"stove")]
	for index: int in definitions.size():
		var item: PlacedItem = _grid.place_def(definitions[index], Vector2i(3 + index * 4, 4))
		var footprint: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(item.origin), _grid)
		assert_eq(footprint, {"mode": &"kitchen", "item_id": item.id, "work_cell_index": -1})
		assert_null(_grid.item_at(item.work_cells[0]))
		var work: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[0]), _grid)
		assert_eq(work, {"mode": &"kitchen", "item_id": item.id, "work_cell_index": 0})


func test_shipped_prep_counter_and_its_external_work_cell_assign_kitchen() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var definition: ItemDef = content.item(&"prep_counter")
	assert_not_null(definition)
	if definition == null:
		return
	assert_eq(definition.station_type, &"prep_counter")
	for quarter: int in 4:
		_grid = SimGrid.new(Vector2i(20, 20))
		var item: PlacedItem = _grid.place_def(definition, Vector2i(5, 5), quarter)
		assert_not_null(item)
		var before: Array[Dictionary] = _snapshot()
		assert_eq(OwnerAssignment.resolve(GridMath.cell_to_world(item.origin), _grid),
			{"mode": &"kitchen", "item_id": item.id, "work_cell_index": -1})
		assert_null(_grid.item_at(item.work_cells[0]))
		assert_eq(OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[0]), _grid),
			{"mode": &"kitchen", "item_id": item.id, "work_cell_index": 0})
		assert_eq(_snapshot(), before)


func test_shipped_fryer_oven_and_prep_cabinet_assign_kitchen_and_coffee_machine_does_not() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	for id: StringName in [&"fryer", &"oven", &"prep_cabinet", &"coffee_machine"]:
		var definition: ItemDef = content.item(id)
		assert_not_null(definition, "shipped %s" % id)
		if definition == null:
			continue
		assert_eq(definition.category, ItemDef.Category.STATION)
		for quarter: int in 4:
			_grid = SimGrid.new(Vector2i(20, 20))
			var item: PlacedItem = _grid.place_def(definition, Vector2i(8, 8), quarter)
			assert_not_null(item)
			if item == null or item.work_cells.is_empty():
				continue
			var before: Array[Dictionary] = _snapshot()
			var footprint: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(item.origin), _grid)
			var work: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[0]), _grid)
			if id == &"coffee_machine":
				# Drinks are floor work; croissants there still go to any cook.
				_assert_none(footprint)
				_assert_none(work)
			else:
				assert_eq(footprint, {"mode": &"kitchen", "item_id": item.id, "work_cell_index": -1})
				assert_null(_grid.item_at(item.work_cells[0]))
				assert_eq(work, {"mode": &"kitchen", "item_id": item.id, "work_cell_index": 0})
			assert_eq(_snapshot(), before)


func test_fryer_and_oven_rotations_assign_the_same_owner_to_kitchen_without_advancing_world() -> void:
	for station_type: StringName in [&"fryer", &"oven"]:
		for quarter: int in 4:
			_grid = SimGrid.new(Vector2i(20, 20))
			var definition: ItemDef = _definition(station_type, ItemDef.Category.STATION, station_type)
			var item: PlacedItem = _grid.place_def(definition, Vector2i(5, 5), quarter)
			assert_not_null(item)
			var before: Array[Dictionary] = _snapshot()
			var footprint: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(item.origin), _grid)
			assert_eq(footprint, {"mode": &"kitchen", "item_id": item.id, "work_cell_index": -1})
			assert_null(_grid.item_at(item.work_cells[0]), "the standing cell lies outside the appliance")
			var work: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[0]), _grid)
			assert_eq(work, {"mode": &"kitchen", "item_id": item.id, "work_cell_index": 0})
			var sim: RestaurantSim = RestaurantSim.new()
			sim.world = SimWorld.new(_grid)
			var owner: OwnerAgent = OwnerAgent.new(Vector2i(1, 1))
			sim.world.add_agent(owner)
			assert_eq(owner.current_mode(), &"rest")
			assert_true(sim.assign_owner(work["mode"]))
			assert_true(sim.owner_agent() == owner, "classification changes the existing owner's mode")
			assert_eq(owner.current_mode(), &"kitchen")
			assert_eq(_snapshot(), before)
			assert_eq(sim.world.now, 0)


func test_drink_station_types_and_sink_still_do_not_assign_from_footprints_or_work_cells() -> void:
	# Detached role fixtures also guard against classifying every STATION as kitchen.
	for station_type: StringName in [&"coffee", &"drinks_fridge", &"drinks_shelf", &"sink"]:
		for quarter: int in 4:
			_grid = SimGrid.new(Vector2i(20, 20))
			var item: PlacedItem = _grid.place_def(_definition(station_type,
				ItemDef.Category.STATION, station_type), Vector2i(5, 5), quarter)
			assert_not_null(item)
			var before: Array[Dictionary] = _snapshot()
			_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(item.origin), _grid))
			_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[0]), _grid))
			assert_eq(_snapshot(), before)


func test_rug_covered_real_station_work_cell_still_assigns_existing_owner_in_either_order() -> void:
	var content: ContentDB = ContentDB.new()
	assert_eq(content.load_all(), PackedStringArray())
	var station_def: ItemDef = content.item(&"prep_counter")
	var rug_def: ItemDef = content.item(&"rug_square")
	assert_eq(rug_def.placement_layer, ItemDef.PlacementLayer.FLOOR_DECOR)
	for rug_first: bool in [true, false]:
		for quarter: int in 4:
			_grid = SimGrid.new(Vector2i(20, 20))
			var origin: Vector2i = Vector2i(5, 5)
			var work: Vector2i = origin + GridMath.rotate_cell(station_def.work_cells[0], station_def.footprint, quarter)
			var first: PlacedItem = _grid.place_def(rug_def if rug_first else station_def, work if rug_first else origin, 0 if rug_first else quarter)
			assert_not_null(first)
			var second: PlacedItem = _grid.place_def(station_def if rug_first else rug_def, origin if rug_first else work, quarter if rug_first else 0)
			assert_not_null(second)
			if first == null or second == null:
				return
			var station: PlacedItem = second if rug_first else first
			var rug: PlacedItem = first if rug_first else second
			assert_eq(_grid.item_at(work), rug, "the convenience floor fallback must not swallow external work")
			assert_null(_grid.item_on_layer(work, ItemDef.PlacementLayer.NORMAL))
			var before: Array[Dictionary] = _snapshot()
			var target: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(work), _grid)
			assert_eq(target, {"mode": &"kitchen", "item_id": station.id, "work_cell_index": 0})
			assert_eq(OwnerAssignment.resolve(GridMath.cell_to_world(station.origin), _grid),
				{"mode": &"kitchen", "item_id": station.id, "work_cell_index": -1})
			var sim: RestaurantSim = RestaurantSim.new()
			sim.world = SimWorld.new(_grid)
			var owner: OwnerAgent = OwnerAgent.new(Vector2i(1, 1))
			sim.world.add_agent(owner)
			assert_eq(owner.current_mode(), &"rest")
			assert_true(sim.assign_owner(target["mode"]))
			assert_true(sim.owner_agent() == owner)
			assert_eq(owner.current_mode(), &"kitchen")
			assert_eq(_snapshot(), before)
			assert_eq(sim.world.now, 0)


func test_table_footprint_assigns_floor_and_non_targets_return_none() -> void:
	var table: PlacedItem = _grid.place_def(_definition(&"table", ItemDef.Category.TABLE), Vector2i(3, 4))
	assert_eq(OwnerAssignment.resolve(GridMath.cell_to_world(table.origin), _grid),
		{"mode": &"floor", "item_id": table.id, "work_cell_index": -1})
	var decor: PlacedItem = _grid.place_def(_definition(&"decor", ItemDef.Category.DECOR), Vector2i(7, 4))
	_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(decor.origin), _grid))
	_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(Vector2i(15, 15)), _grid))
	_assert_none(OwnerAssignment.resolve(Vector3(-1, 0, -1), _grid))
	_assert_none(OwnerAssignment.resolve(Vector3.ZERO, null))


func test_all_rotated_pass_sides_use_absolute_work_cells_and_footprint_proximity() -> void:
	for quarter: int in 4:
		_grid = SimGrid.new(Vector2i(20, 20))
		var item: PlacedItem = _grid.place_def(_pass(), Vector2i(8, 8), quarter)
		assert_not_null(item)
		var kitchen: Vector3 = GridMath.cell_to_world(item.work_cells[0])
		var floor_side: Vector3 = GridMath.cell_to_world(item.work_cells[1])
		for side: int in 2:
			assert_null(_grid.item_at(item.work_cells[side]))
			var result: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[side]), _grid)
			assert_eq(result, {"mode": &"kitchen" if side == 0 else &"floor",
				"item_id": item.id, "work_cell_index": side})
		var middle: Vector3 = kitchen.lerp(floor_side, 0.5)
		var direction: Vector3 = (floor_side - kitchen).normalized()
		assert_eq(_grid.item_at(GridMath.world_to_cell(middle)), item)
		assert_eq(OwnerAssignment.resolve(middle - direction * 0.1, _grid)["mode"], &"kitchen")
		assert_eq(OwnerAssignment.resolve(middle + direction * 0.1, _grid)["mode"], &"floor")
		assert_eq(OwnerAssignment.resolve(middle, _grid)["work_cell_index"], 0, "exact ties choose kitchen side")
		middle.y = 99.0
		assert_eq(OwnerAssignment.resolve(middle, _grid)["work_cell_index"], 0, "height does not change floor classification")


func test_covered_non_target_takes_precedence_over_hidden_external_work_cell() -> void:
	var item: PlacedItem = _grid.place_def(_pass(), Vector2i(8, 8))
	var decor: ItemDef = _definition(&"plant", ItemDef.Category.DECOR)
	decor.footprint = Vector2i.ONE
	assert_not_null(_grid.place_def(decor, item.work_cells[0]))
	_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[0]), _grid))
	assert_eq(OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[1]), _grid)["mode"], &"floor")


func test_overlapping_external_work_cells_use_stable_item_order() -> void:
	var first: PlacedItem = _grid.place_def(_definition(&"fridge", ItemDef.Category.STORAGE, &"fridge"), Vector2i(3, 4))
	var second_def: ItemDef = _definition(&"prep_counter", ItemDef.Category.STATION, &"prep_counter")
	second_def.work_cells = [Vector2i(-4, -1)] as Array[Vector2i]
	var second: PlacedItem = _grid.place_def(second_def, Vector2i(7, 4))
	assert_eq(first.work_cells[0], second.work_cells[0])
	assert_eq(OwnerAssignment.resolve(GridMath.cell_to_world(first.work_cells[0]), _grid)["item_id"], first.id)


func test_malformed_or_unsupported_targets_do_not_assign() -> void:
	var short_pass: ItemDef = _pass()
	short_pass.work_cells.resize(1)
	var item: PlacedItem = _grid.place_def(short_pass, Vector2i(3, 4))
	_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(item.origin), _grid))
	var unknown: PlacedItem = _grid.place_def(_definition(&"sink", ItemDef.Category.STATION, &"sink"), Vector2i(7, 4))
	_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(unknown.origin), _grid))
	var misleading: PlacedItem = _grid.place_def(_definition(&"decor", ItemDef.Category.DECOR, &"fridge"), Vector2i(11, 4))
	_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(misleading.origin), _grid))
	var anonymous: PlacedItem = _grid.place(Vector2i.ONE, Vector2i(15, 4), 0, true)
	_assert_none(OwnerAssignment.resolve(GridMath.cell_to_world(anonymous.origin), _grid))


func test_resolution_is_read_only_and_results_are_detached() -> void:
	var item: PlacedItem = _grid.place_def(_pass(), Vector2i(8, 8), 3)
	assert_true(item.reserve(item.work_cells[0], 700))
	assert_true(item.reserve(item.work_cells[1], 701))
	var before: Array[Dictionary] = _snapshot()
	for side: int in 2:
		var result: Dictionary = OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[side]), _grid)
		result["mode"] = &"rest"
		result["item_id"] = 999
		result["work_cell_index"] = 99
		assert_eq(OwnerAssignment.resolve(GridMath.cell_to_world(item.work_cells[side]), _grid)["work_cell_index"], side)
	assert_eq(_snapshot(), before)
	assert_eq(item.reserved_by(item.work_cells[0]), 700)
	assert_eq(item.reserved_by(item.work_cells[1]), 701)


func _definition(id: StringName, category: ItemDef.Category, station: StringName = &"") -> ItemDef:
	var definition: ItemDef = ItemDef.new()
	definition.id = id
	definition.category = category
	definition.station_type = station
	definition.footprint = Vector2i(2, 1)
	definition.work_cells = [Vector2i(0, -1)] as Array[Vector2i]
	return definition


func _pass() -> ItemDef:
	var definition: ItemDef = _definition(&"pass", ItemDef.Category.PASS)
	definition.work_cells = [Vector2i(0, -1), Vector2i(0, 1)] as Array[Vector2i]
	return definition


func _assert_none(result: Dictionary) -> void:
	assert_eq(result, {"mode": &"", "item_id": -1, "work_cell_index": -1})


func _snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: PlacedItem in _grid.items():
		var holders: Array[int] = []
		for cell: Vector2i in item.work_cells + item.seat_cells:
			holders.append(item.reserved_by(cell))
		result.append({"id": item.id, "origin": item.origin, "turns": item.quarter_turns,
			"cells": item.cells.duplicate(), "work": item.work_cells.duplicate(),
			"seats": item.seat_cells.duplicate(), "holders": holders, "removed": item.removed})
	return result
