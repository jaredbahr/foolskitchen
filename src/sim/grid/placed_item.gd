class_name PlacedItem
extends RefCounted
## One item placed on a SimGrid. All cell lists are absolute grid cells,
## already rotated. Work cells are where a worker stands to use the item;
## seat cells are where a customer sits. Each work/seat cell can be reserved
## by one agent at a time.

## Unique id within its grid (never reused).
var id: int = 0
## Whatever describes the item (an ItemDef once FK-011 lands). The grid never reads it.
var def: Resource = null
var origin: Vector2i = Vector2i.ZERO
var quarter_turns: int = 0
var solid: bool = true
var cells: Array[Vector2i] = []
var work_cells: Array[Vector2i] = []
var seat_cells: Array[Vector2i] = []

## cell -> agent id holding it.
var _reservations: Dictionary[Vector2i, int] = {}


## Reserves a work or seat cell for an agent. False if it is not one of this
## item's cells or another agent holds it. Re-reserving your own cell is fine.
func reserve(cell: Vector2i, agent_id: int) -> bool:
	if not (work_cells.has(cell) or seat_cells.has(cell)):
		return false
	var holder: int = _reservations.get(cell, -1)
	if holder != -1 and holder != agent_id:
		return false
	_reservations[cell] = agent_id
	return true


## Releases a cell if the agent holds it. Returns true if something was released.
func release(cell: Vector2i, agent_id: int) -> bool:
	if _reservations.get(cell, -1) != agent_id:
		return false
	_reservations.erase(cell)
	return true


## Releases every cell held by an agent (used when an agent drops a task).
func release_all(agent_id: int) -> void:
	for cell: Vector2i in _reservations.keys():
		if _reservations[cell] == agent_id:
			_reservations.erase(cell)


## Agent holding a cell, or -1.
func reserved_by(cell: Vector2i) -> int:
	return _reservations.get(cell, -1)


## First work cell nobody holds, or Vector2i(-1, -1) if all are taken.
func free_work_cell() -> Vector2i:
	for cell in work_cells:
		if not _reservations.has(cell):
			return cell
	return Vector2i(-1, -1)


## First seat cell nobody holds, or Vector2i(-1, -1) if all are taken.
func free_seat_cell() -> Vector2i:
	for cell in seat_cells:
		if not _reservations.has(cell):
			return cell
	return Vector2i(-1, -1)
