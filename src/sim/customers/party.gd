class_name Party
extends RefCounted
## One visit's shared table search. IDs avoid a cycle with owning guests;
## orders, payments and reviews remain on each individual CustomerAgent.

const MAX_SIZE: int = 6
const BOOKING_MAX_SIZE: int = 10

var member_ids: Array[int] = []
## Only the explicit booking factory may use the larger 6–10 guest bound.
var booking_owned: bool = false
var booking_id: int = 0
var preferred_group_id: int = 0
## Canonical dining group; each guest retains its physical table owner.
var table_item_id: int = 0
## Original physical members, retained through forced topology changes.
var booked_table_ids: Array[int] = []
var seated: bool = false
var departing: bool = false
var queue_wait: int = 0
## The controller runs once per world tick even when each member calls it.
var last_queue_tick: int = -1
var queue_started: bool = false


func _init(ids: Array[int] = [], is_booking: bool = false) -> void:
	member_ids = ids.duplicate()
	booking_owned = is_booking


func is_valid() -> bool:
	var minimum_size: int = 1 if not booking_owned else MAX_SIZE
	var maximum_size: int = MAX_SIZE if not booking_owned else BOOKING_MAX_SIZE
	if member_ids.size() < minimum_size or member_ids.size() > maximum_size:
		return false
	var seen: Dictionary[int, bool] = {}
	for member_id: int in member_ids:
		if member_id <= 0 or seen.has(member_id):
			return false
		seen[member_id] = true
	return true


func size() -> int:
	return member_ids.size()


func label() -> String:
	return "Party of %d" % size()
