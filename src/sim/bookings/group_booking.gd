class_name GroupBooking
extends RefCounted
## One morning offer and its accepted next-day booking. Pure sim; the session
## supplies the lazily fetched named RNG and applies ledger movements.

const SAVE_VERSION: int = 1
const STATUS_ACCEPTED: StringName = &"accepted"
const STATUS_SETTLED: StringName = &"settled"
const STATUS_REFUNDED: StringName = &"refunded"
const EFFECT_TIP: StringName = &"tip"
const EFFECT_REVIEW: StringName = &"review"
const EFFECT_PAYMENT: StringName = &"payment"
const EFFECT_NO_SEAT: StringName = &"no_seat"

var tuning: BookingTuning
var planned_day: int = 0
var offer: Dictionary = {}
var booking: Dictionary = {}


func _init(config: BookingTuning = null) -> void:
	tuning = config if config != null else BookingTuning.new()


func has_active_booking() -> bool:
	return not booking.is_empty() and booking.get("status", "") == STATUS_ACCEPTED


## Rolls once for an eligible morning. Ineligible calls do not fetch the named
## stream, which keeps lower-level runs and shops without a menu unchanged.
func plan_offer(day: int, owner_level: int, menu_ids: Array[StringName],
		open_minute: int, close_minute: int, random_provider: Callable, seating_capacity: int) -> Dictionary:
	if day < 1 or not tuning.is_valid() or has_active_booking():
		return offer.duplicate(true)
	var maximum_party: int = mini(tuning.max_party_size, seating_capacity)
	if planned_day == day:
		if int(offer.get("party_size", 0)) > maximum_party:
			offer.clear()
		return offer.duplicate(true)
	# A previously unaccepted offer expires even if today's shop is ineligible.
	offer.clear()
	if owner_level < tuning.unlock_level or menu_ids.is_empty() or not random_provider.is_valid() \
			or maximum_party < tuning.min_party_size:
		return {}
	var slots: Array[int] = _valid_slots(open_minute, close_minute)
	if slots.is_empty():
		return {}
	var random: RandomNumberGenerator = random_provider.call() as RandomNumberGenerator
	if random == null:
		return {}
	planned_day = day
	if random.randf() >= tuning.offer_chance:
		return {}
	var size: int = random.randi_range(tuning.min_party_size, maximum_party)
	var occasion: String = tuning.occasions[random.randi_range(0, tuning.occasions.size() - 1)]
	var recipe: StringName = menu_ids[random.randi_range(0, menu_ids.size() - 1)]
	var slot: int = slots[random.randi_range(0, slots.size() - 1)]
	var guest_seeds: Array[int] = []
	for _member: int in size:
		guest_seeds.append(random.randi())
	offer = {
		"offer_day": day,
		"service_day": day + 1,
		"occasion": occasion,
		"party_size": size,
		"slot_minute": slot,
		"recipe_id": String(recipe),
		"dish_preference": tuning.preferred_dish_chance,
		"guest_seeds": guest_seeds,
	}
	return offer.duplicate(true)


func accept_offer(day: int) -> Dictionary:
	if day != planned_day or offer.is_empty() or has_active_booking():
		return {}
	booking = offer.duplicate(true)
	booking["booking_id"] = day
	booking["status"] = String(STATUS_ACCEPTED)
	booking["deposit_amount"] = int(booking["party_size"]) * tuning.deposit_per_guest
	booking["held_group_id"] = 0
	booking["held_group_members"] = [] as Array[int]
	booking["effects"] = [] as Array[String]
	offer.clear()
	return booking.duplicate(true)


## Declining consumes only today's offer; it has no economy or RNG effects.
func decline_offer(day: int) -> bool:
	if day != planned_day or offer.is_empty() or has_active_booking():
		return false
	offer.clear()
	return true


func mark_held_group(booking_id: int, group_id: int, member_ids: Array[int]) -> bool:
	if not _active_id(booking_id) or group_id <= 0 or member_ids.size() < 2:
		return false
	booking["held_group_id"] = group_id
	booking["held_group_members"] = member_ids.duplicate()
	return true


func clear_held_group(booking_id: int, group_id: int = 0) -> bool:
	if not _active_id(booking_id):
		return false
	if group_id > 0 and int(booking.get("held_group_id", 0)) != group_id:
		return false
	booking["held_group_id"] = 0
	booking["held_group_members"] = [] as Array[int]
	return true


## Claims a one-time side effect before integration code applies it.
func claim_effect(booking_id: int, effect: StringName) -> bool:
	if not _active_id(booking_id) or effect not in [EFFECT_TIP, EFFECT_REVIEW, EFFECT_PAYMENT, EFFECT_NO_SEAT]:
		return false
	var effects: Array = booking.get("effects", [])
	if effects.has(String(effect)):
		return false
	if effect == EFFECT_PAYMENT and effects.has(String(EFFECT_NO_SEAT)) \
			or effect == EFFECT_NO_SEAT and effects.has(String(EFFECT_PAYMENT)):
		return false
	effects.append(String(effect))
	booking["effects"] = effects
	return true


func settle(booking_id: int, refunded: bool = false) -> bool:
	if not _active_id(booking_id):
		return false
	var required_effect: String = String(EFFECT_PAYMENT if not refunded else EFFECT_NO_SEAT)
	var effects: Array = booking.get("effects", [])
	var opposite_effect: String = String(EFFECT_NO_SEAT if not refunded else EFFECT_PAYMENT)
	if not effects.has(required_effect) or effects.has(opposite_effect) \
			or not effects.has(String(EFFECT_REVIEW)):
		return false
	booking["status"] = String(STATUS_REFUNDED if refunded else STATUS_SETTLED)
	booking["held_group_id"] = 0
	booking["held_group_members"] = [] as Array[int]
	return true


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "planned_day": planned_day,
		"offer": offer.duplicate(true), "booking": booking.duplicate(true)}


## Validates before replacing live state; absent older sections start empty.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if not tuning.is_valid() or row.size() != 4 or not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not _whole(row.get("planned_day"), 0, 1000000000) \
			or not row.get("offer") is Dictionary or not row.get("booking") is Dictionary:
		return false
	var restored_offer: Dictionary = row["offer"]
	var restored_booking: Dictionary = row["booking"]
	if not _validate_plan(restored_offer, true) or not _validate_plan(restored_booking, false):
		return false
	var staged_day: int = int(row["planned_day"])
	if not restored_offer.is_empty() and int(restored_offer["offer_day"]) != staged_day:
		return false
	if not restored_booking.is_empty():
		if StringName(restored_booking["status"]) not in [STATUS_ACCEPTED, STATUS_SETTLED, STATUS_REFUNDED]:
			return false
		if int(restored_booking["booking_id"]) != int(restored_booking["offer_day"]) \
				or int(restored_booking["service_day"]) != int(restored_booking["booking_id"]) + 1:
			return false
		if not _whole(restored_booking.get("deposit_amount"), 0, 10000000) \
			or not _whole(restored_booking.get("held_group_id"), 0, 2147483647) \
			or not restored_booking.get("held_group_members") is Array:
			return false
		if int(restored_booking["deposit_amount"]) != int(restored_booking["party_size"]) * tuning.deposit_per_guest:
			return false
		var held_members: Array = restored_booking["held_group_members"]
		if (int(restored_booking["held_group_id"]) == 0) != held_members.is_empty():
			return false
		if held_members.size() > 10:
			return false
		var seen_member_ids: Dictionary[int, bool] = {}
		for member: Variant in held_members:
			if not _whole(member, 1, 2147483647) or seen_member_ids.has(int(member)):
				return false
			seen_member_ids[int(member)] = true
		var effects: Variant = restored_booking.get("effects")
		if not effects is Array:
			return false
		var seen_effects: Dictionary[String, bool] = {}
		for effect: Variant in effects:
			if not effect is String or StringName(effect) not in [EFFECT_TIP, EFFECT_REVIEW,
					EFFECT_PAYMENT, EFFECT_NO_SEAT]:
				return false
			if seen_effects.has(effect):
				return false
			seen_effects[effect] = true
		var has_payment: bool = effects.has(String(EFFECT_PAYMENT))
		var has_no_seat: bool = effects.has(String(EFFECT_NO_SEAT))
		var has_review: bool = effects.has(String(EFFECT_REVIEW))
		var has_tip: bool = effects.has(String(EFFECT_TIP))
		var status: StringName = StringName(restored_booking["status"])
		if status == STATUS_ACCEPTED and not effects.is_empty():
			return false
		if status == STATUS_ACCEPTED and int(restored_booking["offer_day"]) != staged_day:
			return false
		if status == STATUS_SETTLED and (not has_payment or has_no_seat or not has_review):
			return false
		if status == STATUS_REFUNDED and (has_payment or not has_no_seat or not has_review or has_tip):
			return false
		if has_payment and has_no_seat:
			return false
		if not restored_offer.is_empty() and status == STATUS_ACCEPTED:
			return false
		if int(restored_booking["offer_day"]) > staged_day:
			return false
		if not restored_offer.is_empty() and int(restored_offer["offer_day"]) <= int(restored_booking["offer_day"]):
			return false
	planned_day = staged_day
	offer = restored_offer.duplicate(true)
	booking = restored_booking.duplicate(true)
	return true


func _active_id(booking_id: int) -> bool:
	return has_active_booking() and int(booking.get("booking_id", 0)) == booking_id


func _valid_slots(open_minute: int, close_minute: int) -> Array[int]:
	var slots: Array[int] = []
	if open_minute < 0 or close_minute > 1440 or open_minute >= close_minute:
		return slots
	var first: int = ceili(float(open_minute + tuning.hold_before_minutes) \
		/ float(tuning.slot_minutes)) * tuning.slot_minutes
	var last: int = floori(float(close_minute - tuning.min_service_remaining_minutes \
		- tuning.slot_minutes) \
		/ float(tuning.slot_minutes)) * tuning.slot_minutes
	for minute: int in range(first, last + 1, tuning.slot_minutes):
		slots.append(minute)
	return slots


func _validate_plan(value: Dictionary, is_offer: bool) -> bool:
	if value.is_empty():
		return true
	var required: Array[String] = ["offer_day", "service_day", "occasion", "party_size",
		"slot_minute", "recipe_id", "dish_preference", "guest_seeds"]
	for key: String in required:
		if not value.has(key):
			return false
	if not _whole(value["offer_day"], 1, 1000000000) \
			or not _whole(value["service_day"], 2, 1000000001) \
			or int(value["service_day"]) != int(value["offer_day"]) + 1 \
			or not value["occasion"] is String or String(value["occasion"]).strip_edges().is_empty() \
			or not _whole(value["party_size"], tuning.min_party_size, tuning.max_party_size) \
			or not _whole(value["slot_minute"], 0, 1440) \
			or int(value["slot_minute"]) % tuning.slot_minutes != 0 \
			or not value["recipe_id"] is String or String(value["recipe_id"]).is_empty() \
			or not (value["dish_preference"] is int or value["dish_preference"] is float) \
			or not is_finite(float(value["dish_preference"])) or float(value["dish_preference"]) < 0.0 \
			or float(value["dish_preference"]) > 1.0 \
			or not value["guest_seeds"] is Array or value["guest_seeds"].size() != int(value["party_size"]):
		return false
	for seed: Variant in value["guest_seeds"]:
		if not _whole(seed, 0, 4294967295):
			return false
	if not is_offer and (not _whole(value.get("booking_id"), 1, 1000000000) \
			or not value.get("status") is String or not value.has("effects")):
		return false
	return true


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floorf(number) == number
