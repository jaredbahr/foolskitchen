class_name EdgeAStar
extends AStarGrid2D
## AStarGrid2D that also respects wall segments on cell edges (FK-070).
## SimGrid only switches to this instance while at least one interior segment
## exists, so a shop without walls keeps the engine's own costs and tie-breaks.
##
## A step across a blocking edge costs BLOCKED_COST rather than being removed,
## because AStarGrid2D has no per-edge solidity. SimGrid rejects any returned
## path that still crosses a blocked edge (which only happens when no open
## route exists). A diagonal step passes the shared grid corner, so it needs
## all four edges meeting at that corner free of any segment (no corner
## cutting past a wall end or a doorway post).

const BLOCKED_COST: float = 1.0e9

## Edge key -> true. Shared by reference with the owning SimGrid; never reassigned.
var blocking: Dictionary[Vector3i, bool] = {}
var occupied: Dictionary[Vector3i, bool] = {}


func _init(blocking_edges: Dictionary[Vector3i, bool], occupied_edges: Dictionary[Vector3i, bool]) -> void:
	blocking = blocking_edges
	occupied = occupied_edges


func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
	if not step_open(from_id, to_id):
		return BLOCKED_COST
	return 1.0 if from_id.x == to_id.x or from_id.y == to_id.y else sqrt(2.0)


## Edges only: callers still check that both cells are walkable.
func step_open(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var delta: Vector2i = to_cell - from_cell
	if absi(delta.x) + absi(delta.y) == 1:
		return not blocking.has(SimGrid.edge_between(from_cell, to_cell))
	if absi(delta.x) != 1 or absi(delta.y) != 1:
		return true
	var corner: Vector2i = Vector2i(maxi(from_cell.x, to_cell.x), maxi(from_cell.y, to_cell.y))
	for edge: Vector3i in SimGrid.edges_at_vertex(corner):
		if occupied.has(edge):
			return false
	return true
