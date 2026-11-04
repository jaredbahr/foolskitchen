extends TestCase
## #208: after closing, chairs go up on their tables (view only), except at
## tables left dirty and never while Build or Paint is open. Morning brings
## them back down to exactly where they were.

const MAIN: PackedScene = preload("res://src/world/main.tscn")

var _main: Node


func before_each() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func _world() -> SimWorld:
	return _main.get("world")


func _view() -> ShopView:
	return _main.get_node("ShopView") as ShopView


## Each starter table's own chairs: [table id, chair node].
func _chairs() -> Array:
	var out: Array = []
	for item: PlacedItem in _world().grid.items():
		if (item.def as ItemDef).category != ItemDef.Category.TABLE:
			continue
		for child: Node in (_view().item_nodes[item.id] as ItemVisual).prop.get_children():
			if child.has_meta(&"seat_cell"):
				out.append([item.id, child])
	return out


func _set_phase(phase: SimClock.Phase) -> void:
	_world().clock.phase = phase
	_main.call("refresh_presentation")


func test_chairs_go_up_after_closing_and_come_down_exactly_for_morning() -> void:
	var chairs: Array = _chairs()
	assert_eq(chairs.size(), 6, "three starter tables with two chairs each")
	var rest: Array[Transform3D] = []
	for pair: Array in chairs:
		rest.append((pair[1] as Node3D).transform)
	var layout: Array = _world().grid.items().map(func(item: PlacedItem) -> Array: return [item.id, item.origin])
	_set_phase(SimClock.Phase.CLOSED)
	for pair: Array in chairs:
		var chair: Node3D = pair[1]
		assert_true(chair.transform.basis.y.y < -0.9, "upside down")
		assert_true(chair.position.y > 0.3, "up on the table, not on the floor")
	assert_eq(_world().grid.items().map(func(item: PlacedItem) -> Array: return [item.id, item.origin]), layout,
		"the shop itself never moves")
	_set_phase(SimClock.Phase.MORNING)
	for index: int in chairs.size():
		assert_true((chairs[index][1] as Node3D).transform.is_equal_approx(rest[index]), "back exactly where it was")


func test_a_table_left_dirty_keeps_its_chairs_down() -> void:
	var chairs: Array = _chairs()
	var dirty: int = int(chairs[0][0])
	(_main.get("sim") as RestaurantSim).kitchen.mark_table_dirty(dirty)
	_set_phase(SimClock.Phase.CLOSED)
	for pair: Array in chairs:
		var down: bool = (pair[1] as Node3D).transform.basis.y.y > 0.9
		assert_eq(down, int(pair[0]) == dirty, "only the dirty table's chairs stay down")


func test_evening_build_shows_and_picks_furniture_where_it_stands() -> void:
	_set_phase(SimClock.Phase.CLOSED)
	assert_true(bool(_main.call("set_build_active", true)), "evening Build opens")
	_main.call("refresh_presentation")
	for pair: Array in _chairs():
		assert_true((pair[1] as Node3D).transform.basis.y.y > 0.9, "chairs down while editing")
