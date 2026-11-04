extends TestCase
## #84: lighting decor. Six Kenney lamps in the Lighting tab, placed through
## the real Buy commands; dim by day, full at night; at most eight lights
## shine at once; and they count towards the lamp part of vibe.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const VIBE: VibeTuning = preload("res://data/balance/vibe.tres")
const LAMPS: Array[StringName] = [&"lamp_floor_round", &"lamp_floor_square", &"lamp_table_round",
	&"lamp_table_square", &"lamp_wall", &"lamp_pendant"]

var _main: Node


func before_each() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Economy.add_cash(5000, Ledger.OTHER)
	(_main.get("shop_editor") as ShopEditor).set_owner_level(4)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _world() -> SimWorld:
	return _main.get("world")


func _free_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _world().grid.cells():
		# Dining cells only: decor counts for vibe where guests can see it.
		if _world().grid.terrain(cell) == SimGrid.Terrain.FLOOR and _world().grid.item_at(cell) == null \
				and _world().grid.room(cell) == SimGrid.Room.DINING:
			cells.append(cell)
	return cells


func _buy_floor_lamps(count: int) -> int:
	var placed: int = 0
	for cell: Vector2i in _free_cells():
		if placed >= count:
			break
		if bool(_main.call("shop_buy", &"lamp_floor_round", cell, 0)):
			placed += 1
	return placed


func _visible_lights() -> int:
	var lit: int = 0
	for lamp: ItemVisual in _main.call("lamp_visuals"):
		var light: OmniLight3D = lamp.get_node_or_null(^"Glow") as OmniLight3D
		if light != null and light.visible:
			lit += 1
	return lit


func test_every_lamp_is_a_warm_lighting_item_counted_by_vibe() -> void:
	var content: ContentDB = _main.get("content")
	for lamp_id: StringName in LAMPS:
		var definition: ItemDef = content.item(lamp_id)
		assert_not_null(definition, "%s loads" % lamp_id)
		assert_eq(definition.catalogue_room, &"lighting")
		assert_true(definition.price >= 15 and definition.price <= 40, "%s price" % lamp_id)
		assert_true(definition.unlock_level >= 1 and definition.unlock_level <= 4, "%s unlock" % lamp_id)
		assert_true(definition.glow_color.a > 0.0 and definition.glow_color.r > definition.glow_color.b, "warm light")
		assert_true(VIBE.lamp_item_ids.has(lamp_id), "%s counts as a lamp for vibe" % lamp_id)
		assert_not_null(definition.view_scene, "a Kenney wrapper scene")
	assert_eq((content.item(&"lamp_wall") as ItemDef).placement_layer, ItemDef.PlacementLayer.WALL)
	assert_true((content.item(&"lamp_pendant") as ItemDef).ceiling)


func test_each_lamp_places_through_buy_and_the_wall_lamp_hangs_on_a_face() -> void:
	var cells: Array[Vector2i] = _free_cells()
	var index: int = 0
	for lamp_id: StringName in [&"lamp_floor_round", &"lamp_floor_square", &"lamp_table_round", &"lamp_table_square", &"lamp_pendant"]:
		var placed: bool = false
		while not placed and index < cells.size():
			placed = bool(_main.call("shop_buy", lamp_id, cells[index], 0))
			index += 1
		assert_true(placed, "%s places on a free floor cell" % lamp_id)
	var hung: bool = false
	for face: Vector3i in [Vector3i(1, 7, 3), Vector3i(9, 6, 3), Vector3i(2, 1, 0)]:
		hung = hung or bool(_main.call("shop_hang", &"lamp_wall", face))
	assert_true(hung, "the wall lamp hangs on an inside wall face")
	_main.call("refresh_presentation")
	assert_eq((_main.call("lamp_visuals") as Array).size(), 6, "every lamp has a lit visual")


func test_at_most_eight_lamp_lights_shine_with_ten_lamps() -> void:
	assert_eq(_buy_floor_lamps(10), 10)
	_main.call("refresh_presentation")
	assert_eq((_main.call("lamp_visuals") as Array).size(), 10)
	assert_eq(_visible_lights(), DayNightView.LAMP_LIGHT_CAP, "the nearest eight to the camera shine")


func test_lamps_are_dim_by_day_and_full_at_night() -> void:
	assert_eq(_buy_floor_lamps(1), 1)
	_main.call("refresh_presentation")
	var light: OmniLight3D = (_main.call("lamp_visuals") as Array)[0].get_node("Glow") as OmniLight3D
	var day: float = light.light_energy
	_world().clock.phase = SimClock.Phase.CLOSED
	_main.call("refresh_presentation")
	assert_true(light.light_energy > day * 2.0, "lamps come into their own after dark")
	assert_true(light.light_energy <= DayNightView.MAX_GLOW_ENERGY)


func test_lamps_raise_the_lamp_part_of_vibe() -> void:
	var sim: RestaurantSim = _main.get("sim")
	assert_almost_eq(sim.vibe_result.lamp_points, 0.0, 0.0001, "a default shop owns no lamps")
	# Every shop's first few charm points are a free starter allowance, so
	# place enough lamps to go past it.
	assert_eq(_buy_floor_lamps(8), 8)
	assert_true(sim.vibe_result.lamp_points > 0.0, "lamps add lamp vibe")

