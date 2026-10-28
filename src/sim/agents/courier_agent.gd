class_name CourierAgent
extends SimAgent
## The delivery person (FK-099, #187). Walks a fixed route from well beyond the
## lot (out of sight) up to the door (the back door, or the street door when the
## shop has none), stops in the doorway, sets the crates down on the receiving
## cell just inside, then walks the same way back and is gone.
## The route is planned once by DeliveryDock: off-lot cells are not on the
## grid, so this agent walks its cells without path finding or walkability
## checks (it never enters the shop beyond the receiving cell). It holds no
## task, reservation, random stream or reference back to the dock; the dock
## reads `dropped` and `state` each tick. Guests never share its route through
## a back door: they plan on the guest layer (SimGrid.find_guest_path).

enum State { ARRIVING, UNLOADING, LEAVING, GONE }

## Ticks spent setting the crates down from the doorway: one bend (the kit's
## `pick-up` clip, 0.33 s, i.e. about 3.3 ticks at any speed) and a moment.
const UNLOAD_TICKS: int = 4
## The tick of the bend's lowest point (0.2 s in): the crates leave her hands
## for the floor then, not on arrival.
const DROP_TICK: int = 2

var state: State = State.ARRIVING
## True while the crates are in this person's hands.
var carrying: bool = true
## How many crates this delivery brings (the view stacks them).
var crate_count: int = 0
## Set once the crate in her hands is on the floor (the bend's lowest point);
## the dock turns it into put-away work.
var dropped: bool = false
## Set once she has stepped away from the stack: the rest of the delivery
## is down too (on top of the first, where her head no longer is).
var all_dropped: bool = false
## Off-lot start .. door (where she stands to unload).
var route: Array[Vector2i] = []
## The receiving cell the crates go down on, just inside the door.
var drop: Vector2i = SimGrid.NO_CELL
## The stack layer her crate goes down on (the dock keeps it current; the view
## lowers it that far), or -1 when that stack is full: then everything goes
## to the nearest free cell once she has stepped away.
var drop_layer: int = 0

var _unload_left: int = 0


func _init(cells: Array[Vector2i] = [], crates: int = 0, receiving: Vector2i = SimGrid.NO_CELL) -> void:
	role = &"courier"
	display_name = "Delivery driver"
	route = cells.duplicate()
	crate_count = crates
	drop = receiving
	if not route.is_empty():
		cell = route[0]
		path = route.duplicate()
		path_index = 1


## The receiving cell (the route's last cell when none was given).
func drop_cell() -> Vector2i:
	if drop != SimGrid.NO_CELL:
		return drop
	return route.back() if not route.is_empty() else cell


func tick(world: SimWorld) -> void:
	match state:
		State.ARRIVING:
			if _walk(world):
				state = State.UNLOADING
				_unload_left = UNLOAD_TICKS
		State.UNLOADING:
			_unload_left -= 1
			last_progress_tick = world.now
			if UNLOAD_TICKS - _unload_left >= DROP_TICK and not dropped:
				dropped = true
				# With the stack inside the door full she keeps hold of it.
				carrying = drop_layer < 0
			if _unload_left <= 0:
				state = State.LEAVING
				path = route.duplicate()
				path.reverse()
				path_index = 1
				move_progress = 0.0
		State.LEAVING:
			if _walk(world):
				state = State.GONE
			all_dropped = true
			carrying = false


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


## 0..1 through setting the crate down: 1 at the bend's lowest point.
func unload_progress() -> float:
	if state != State.UNLOADING:
		return 0.0
	return clampf(float(UNLOAD_TICKS - _unload_left) / float(DROP_TICK), 0.0, 1.0)


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
