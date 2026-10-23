class_name GridMath
extends RefCounted
## Grid conventions shared by the sim and the world view (docs/TECH.md 2.3).
## Cell x -> world +X, cell y -> world +Z; seen from above, +x is right and +y
## is down the screen. An unrotated footprint (w, d) covers x in [0, w),
## y in [0, d) and its front faces -Y (world -Z).

## Size of one grid cell in metres.
const CELL_SIZE: float = 0.5

## Cost of a diagonal step relative to a straight one.
const DIAGONAL_COST: float = 1.41421356


## Rotates a cell given relative to an unrotated footprint by quarter turns
## clockwise (seen from above). One turn maps (x, y) to (d - 1 - y, x) and the
## footprint (w, d) becomes (d, w). Works for cells outside the footprint too.
static func rotate_cell(cell: Vector2i, footprint: Vector2i, quarter_turns: int) -> Vector2i:
	var c := cell
	var f := footprint
	for i in posmod(quarter_turns, 4):
		c = Vector2i(f.y - 1 - c.y, c.x)
		f = Vector2i(f.y, f.x)
	return c


## Footprint size after rotating by quarter turns.
static func rotated_footprint(footprint: Vector2i, quarter_turns: int) -> Vector2i:
	return footprint if posmod(quarter_turns, 2) == 0 else Vector2i(footprint.y, footprint.x)


## World position of a cell's centre on the floor (y = 0).
static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)


## Cell containing a world position (y ignored).
static func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE))


## Movement cost of a path (straight steps 1, diagonal steps DIAGONAL_COST).
## Steps are counted as integers first, so equal paths always give equal costs.
static func path_cost(path: Array[Vector2i]) -> float:
	var straight := 0
	var diagonal := 0
	for i in range(1, path.size()):
		var d := path[i] - path[i - 1]
		if d.x != 0 and d.y != 0:
			diagonal += 1
		else:
			straight += 1
	return straight + diagonal * DIAGONAL_COST


## Lower bound on the path cost between two cells (octile distance).
static func octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxi(dx, dy) - mini(dx, dy) + mini(dx, dy) * DIAGONAL_COST
