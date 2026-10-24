class_name Order
extends RefCounted
## A guest's ticket; prices are captured when the server takes the order.

enum State { PLACED, COOKING, READY, DELIVERED, CANCELLED }

var id: int = 0
var customer_id: int = 0
var table_item_id: int = 0
var seat_cell: Vector2i = SimGrid.NO_CELL
var recipe_id: StringName = &""
var price: int = 0
var placed_tick: int = 0
var state: State = State.PLACED

## Final clamped dish quality for future guest reviews.
var quality: float = 0.0
## Why preparation or delivery was cancelled; carried through to the guest.
var cancellation_reason: StringName = &""
