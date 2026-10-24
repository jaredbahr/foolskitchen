class_name OwnerAssignment
extends RefCounted
## Pure target classification. The session calls this before ordinary picking
## only when the live owner is selected, and retains that selection on success.


## mode is kitchen/floor or empty; item_id and work_cell_index identify the
## target without exposing mutable items. Pass side ties choose index zero.
static func resolve(world_position: Vector3, grid: SimGrid) -> Dictionary:
	if grid == null:
		return _none()
	var cell: Vector2i = GridMath.world_to_cell(world_position)
	var covered: PlacedItem = grid.item_at(cell)
	if covered != null:
		return _for_item(covered, world_position, -1)
	# Work cells can lie outside a footprint, where item_at() returns null.
	# Stable item order breaks ties between overlapping external work cells.
	for item: PlacedItem in grid.items():
		var index: int = item.work_cells.find(cell)
		if index >= 0:
			var result: Dictionary = _for_item(item, world_position, index)
			if result["mode"] != &"":
				return result
	return _none()


static func _for_item(item: PlacedItem, world_position: Vector3, work_index: int) -> Dictionary:
	var definition: ItemDef = item.def as ItemDef
	if item.removed or definition == null:
		return _none()
	if definition.category == ItemDef.Category.TABLE:
		return _target(&"floor", item.id, work_index)
	if definition.category == ItemDef.Category.PASS:
		if item.work_cells.size() < 2 or work_index > 1:
			return _none()
		var side: int = work_index
		if side < 0:
			var kitchen: Vector3 = GridMath.cell_to_world(item.work_cells[0])
			var floor_side: Vector3 = GridMath.cell_to_world(item.work_cells[1])
			var hit: Vector2 = Vector2(world_position.x, world_position.z)
			side = 0 if hit.distance_squared_to(Vector2(kitchen.x, kitchen.z)) <= hit.distance_squared_to(Vector2(floor_side.x, floor_side.z)) else 1
		return _target(&"kitchen" if side == 0 else &"floor", item.id, side)
	if definition.category == ItemDef.Category.STORAGE and definition.station_type == &"fridge":
		return _target(&"kitchen", item.id, work_index)
	if definition.category == ItemDef.Category.STATION and definition.station_type in [&"prep_counter", &"stove"]:
		return _target(&"kitchen", item.id, work_index)
	return _none()


static func _target(mode: StringName, item_id: int, work_index: int) -> Dictionary:
	return {"mode": mode, "item_id": item_id, "work_cell_index": work_index}


static func _none() -> Dictionary:
	return _target(&"", -1, -1)
