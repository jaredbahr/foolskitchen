class_name CourierAgent
extends SimAgent
## The delivery person (FK-099, #187). Walks a fixed route from off the lot to
## the receiving cell (through the back door, or the street door when the shop
## has none), sets the crates down, then walks the same way back and is gone.
## The route is planned once by DeliveryDock: off-lot cells are not on the
## grid, so this agent walks its cells without path finding or walkability
## checks (it never enters the shop beyond the receiving cell). It holds no
## task, reservation, random stream or reference back to the dock; the dock
## reads `dropped` and `state` each tick. Guests never share its route through
## a back door: they plan on the guest layer (SimGrid.find_guest_path).

enum State { ARRIVING, UNLOADING, LEAVING, GONE }

## Ticks spent setting the crates down at the receiving cell.
const UNLOAD_TICKS: int = 12

var state: State = State.ARRIVING
## True while the crates are in this person's hands.
var carrying: bool = true
## How many crates this delivery brings (the view stacks them).
var crate_count: int = 0
## Set once the crates are on the floor; the dock turns them into put-away work.
var dropped: bool = false
## Off-lot start .. door .. receiving cell.
var route: Array[Vector2i] = []

var _unload_left: int = 0


func _init(cells: Array[Vector2i] = [], crates: int = 0) -> void:
	role = &"courier"
	display_name = "Delivery driver"
	route = cells.duplicate()
	crate_count = crates
	if not route.is_empty():
		cell = route[0]
		path = route.duplicate()
		path_index = 1


## The receiving cell (the route's last cell).
func drop_cell() -> Vector2i:
	return route.back() if not route.is_empty() else cell


func tick(world: SimWorld) -> void:
	match state:
		State.ARRIVING:
			if _walk(world):
				state = State.UNLOADING
				_unload_left = UNLOAD_TICKS
				carrying = false
				dropped = true
		State.UNLOADING:
			_unload_left -= 1
			last_progress_tick = world.now
			if _unload_left <= 0:
				state = State.LEAVING
				path = route.duplicate()
				path.reverse()
				path_index = 1
				move_progress = 0.0
		State.LEAVING:
			if _walk(world):
				state = State.GONE


func why() -> String:
	match state:
		State.ARRIVING:
			return "Bringing a delivery"
		State.UNLOADING:
			return "Setting the crates down"
	return "Heading back to the van"


## True while setting the crates down (the view bends down to them).
func unloading() -> bool:
	return state == State.UNLOADING


## Walks the planned cells at the neutral pace (four ticks a straight cell).
## No walkability check: the route was planned when the delivery arrived and
## its off-lot part is not on the grid. True once at the end of the path.
func _walk(world: SimWorld) -> bool:
	if has_arrived():
		return true
	var next: Vector2i = path[path_index]
	var delta: Vector2i = next - cell
	var step_len: float = GridMath.DIAGONAL_COST if delta.x != 0 and delta.y != 0 else 1.0
	move_progress += move_speed / step_len
	last_progress_tick = world.now
	if move_progress >= 1.0:
		move_progress = 0.0
		cell = next
		path_index += 1
	return has_arrived()
