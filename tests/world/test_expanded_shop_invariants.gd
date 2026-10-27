extends "res://tests/world/test_multi_day_invariants.gd"
## FK-080: the same five real days (books, guests, plates, a reload before day
## 3) in a shop the player expanded on the first morning: an east wing beside
## the dining room with a table in it, and a strip at the back. The building is
## then L-shaped. The bought floor must survive the reload and guests must sit
## in the new wing.

const WING: Rect2i = Rect2i(14, 5, 1, 5)
const BACK: Rect2i = Rect2i(8, -1, 5, 1)

var _wing_meals: int = 0


func _shop_morning(main: Node, day: int) -> void:
	var sim: RestaurantSim = main.get("sim")
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	if day == 1:
		var cash: int = Economy.cash
		for rect: Rect2i in [WING, BACK]:
			assert_true(bool(main.call("shop_floor", _cells(rect), true)), editor.last_check.why)
		assert_true(bool(main.call("shop_buy", &"table_2", Vector2i(13, 6), 1)), editor.last_check.why)
		assert_eq(Economy.cash, cash - 10 * 15 - 40, "floor and table are paid for")
	var grid: SimGrid = (main.get("world") as SimWorld).grid
	assert_eq(editor.bought_floor().size(), 10, "day %d: the bought floor is kept" % day)
	for cell: Vector2i in [Vector2i(14, 9), Vector2i(13, 5), Vector2i(10, -1), Vector2i(10, 0)]:
		assert_eq(grid.terrain(cell), SimGrid.Terrain.FLOOR, "day %d: %s is floor" % [day, cell])
	assert_eq(grid.terrain(Vector2i(15, 7)), SimGrid.Terrain.WALL, "day %d: the outer wall moved out" % day)
	assert_eq(ShopBuilder.items_with_def(main.get("world") as SimWorld, &"table_2").size(), 4)
	if not sim.customer_paid.is_connected(_on_wing_paid):
		sim.customer_paid.connect(_on_wing_paid)


func _after_days(_main: Node) -> void:
	assert_true(_wing_meals > 0, "guests eat at the table in the new wing (%d meals)" % _wing_meals)
	print("EXPANDED_SOAK wing_meals=%d" % _wing_meals)


func _on_wing_paid(_customer: CustomerAgent, order: Order, _amount: int) -> void:
	if order.seat_cell.x == 13 and (order.seat_cell.y == 5 or order.seat_cell.y == 8):
		_wing_meals += 1


static func _cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out
