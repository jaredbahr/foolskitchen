extends "res://src/world/main.gd"
## Explicit, unsaved display fixture for #84, not a service or balance claim.
## A fresh morning shop given cash and level 4, with every lamp placed through
## the real Buy commands on the first free dining cells, shown at
## LAMPS_STAGE = morning (default) or night (closed), with LAMPS_WALLS=up to
## show the ceiling pendant. Nothing is saved.

const FLOOR_LAMPS: Array[StringName] = [&"lamp_floor_round", &"lamp_table_square", &"lamp_pendant",
	&"lamp_floor_square", &"lamp_table_round"]


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null:
		push_error("Lamps review needs a fresh shop")
		return
	Economy.add_cash(2000, Ledger.OTHER)
	shop_editor.set_owner_level(4)
	var placed: Array[String] = []
	var used: Dictionary[Vector2i, bool] = {}
	for lamp_id: StringName in FLOOR_LAMPS:
		for cell: Vector2i in world.grid.cells():
			if world.grid.terrain(cell) != SimGrid.Terrain.FLOOR or world.grid.room(cell) != SimGrid.Room.DINING \
					or used.has(cell):
				continue
			if shop_buy(lamp_id, cell, 0):
				used[cell] = true
				placed.append("%s@%s" % [lamp_id, cell])
				break
	for face: Vector3i in [Vector3i(1, 7, 3), Vector3i(9, 6, 3), Vector3i(2, 1, 0)]:
		if shop_hang(&"lamp_wall", face):
			placed.append("lamp_wall@%s" % face)
			break
	if OS.get_environment("LAMPS_STAGE") == "night":
		world.clock.phase = SimClock.Phase.CLOSED
	if OS.get_environment("LAMPS_WALLS") == "up":
		($ShopView as ShopView).set_wall_mode(ShopView.WallMode.UP)
	Clock.set_speed(0)
	refresh_presentation()
	print("LAMPS_REVIEW ", JSON.stringify({"placed": placed, "lights": lamp_visuals().size(), "use_saves": use_saves}))
