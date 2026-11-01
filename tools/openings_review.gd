extends "res://src/world/main.gd"
## Explicit, unsaved review fixture using the normal morning edit commands.
## OPENINGS_REVIEW_STAGE=before|after selects the supported wall or expanded room.
## The extra $2,000 and wall-decor unlock only prepare this capture, never a save.


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	var stage: String = OS.get_environment("OPENINGS_REVIEW_STAGE")
	if stage not in ["before", "after"] or sim == null:
		push_error("Opening review needs a fresh shop and a before or after stage")
		return
	Economy.add_cash(2000, Ledger.OTHER)
	var window: Vector3i = Vector3i(13, 7, SimGrid.EDGE_WEST)
	var door: Vector3i = Vector3i(13, 6, SimGrid.EDGE_WEST)
	if not shop_walls({window: SimGrid.Segment.WINDOW, door: SimGrid.Segment.DOORWAY}
			as Dictionary[Vector3i, int]):
		push_error("Opening review could not place its openings: " + shop_editor.last_check.why)
		return
	shop_editor.set_owner_level(6)
	if not shop_hang(&"neon_open_sign", Vector3i(12, 7, 1)) \
			or not shop_hang(&"wall_art_sunrise", Vector3i(12, 8, 1)):
		push_error("Opening review could not hang its wall decor: " + shop_editor.last_check.why)
		return
	var cash_before: int = Economy.cash
	var cost: int = 0
	var refund: int = 0
	if stage == "after":
		var cells: Array[Vector2i] = []
		for y: int in range(5, 10):
			cells.append(Vector2i(14, y))
		var check: EditCheck = shop_editor.check_floor(cells, true)
		if not check.ok or not shop_floor(cells, true):
			push_error("Opening review could not expand its floor: " + shop_editor.last_check.why)
			return
		cost = check.cost
		refund = check.refund
		if world.grid.segment(window) != SimGrid.Segment.NONE \
				or world.grid.segment(door) != SimGrid.Segment.NONE \
				or shop_editor.decor.count() != 0 or Economy.cash != cash_before - cost + refund:
			push_error("Opening review expansion did not remove and refund its frames and decor")
			return
	elif not WallRules.has_continuing_wall(world.grid, window) \
			or not WallRules.has_continuing_wall(world.grid, door):
		push_error("Opening review's initial frames have no supporting wall")
		return
	print("OPENINGS_REVIEW ", JSON.stringify({"stage": stage,
		"fixture": "normal morning edits; extra $2000 and wall-decor unlock; saves disabled",
		"window": int(world.grid.segment(window)), "door": int(world.grid.segment(door)),
		"decor": shop_editor.decor.count(), "cash_before": cash_before, "cash_after": Economy.cash,
		"cost": cost, "refund": refund, "use_saves": use_saves}))
