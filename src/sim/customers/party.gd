class_name Party
extends RefCounted
## One visit's shared table search. IDs avoid a cycle with owning guests;
## orders, payments and reviews remain on each individual CustomerAgent.

const MAX_SIZE: int = 6

var member_ids: Array[int] = []
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


func _init(ids: Array[int] = []) -> void:
	member_ids = ids.duplicate()


func is_valid() -> bool:
	if member_ids.is_empty() or member_ids.size() > MAX_SIZE:
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
