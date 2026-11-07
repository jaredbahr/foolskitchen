class_name BookingTuning
extends Resource
## Morning group-booking choices and settlement terms (data/balance/bookings.tres).

@export var unlock_level: int = 2
@export_range(0.0, 1.0, 0.01) var offer_chance: float = 0.25
@export var min_party_size: int = 6
@export var max_party_size: int = 10
@export var deposit_per_guest: int = 5
@export_range(0.0, 1.0, 0.01) var tip_bonus: float = 0.15
@export_range(0.0, 1.0, 0.01) var preferred_dish_chance: float = 0.75
@export var good_service_stars: int = 4
@export var review_weight: int = 2
@export var slot_minutes: int = 15
@export var hold_before_minutes: int = 20
## Keep enough service time after arrival for an ordinary meal to finish.
@export var min_service_remaining_minutes: int = 90
@export var occasions: PackedStringArray = PackedStringArray([
	"Birthday", "Office lunch", "Family celebration", "Rehearsal dinner",
])


func is_valid() -> bool:
	if unlock_level < 1 or not is_finite(offer_chance) or offer_chance < 0.0 or offer_chance > 1.0:
		return false
	if min_party_size < 6 or max_party_size < min_party_size or max_party_size > 10:
		return false
	if deposit_per_guest < 0 or deposit_per_guest > 1000000:
		return false
	if not is_finite(tip_bonus) or tip_bonus < 0.0 or tip_bonus > 1.0:
		return false
	if not is_finite(preferred_dish_chance) or preferred_dish_chance < 0.0 or preferred_dish_chance > 1.0:
		return false
	if good_service_stars < 1 or good_service_stars > 5 or review_weight < 1 or review_weight > 15:
		return false
	if slot_minutes != 15 or hold_before_minutes < 0 or min_service_remaining_minutes < slot_minutes:
		return false
	if occasions.is_empty():
		return false
	var seen: Dictionary[String, bool] = {}
	for occasion: String in occasions:
		var clean: String = occasion.strip_edges()
		if clean.is_empty() or clean.length() > 48 or seen.has(clean):
			return false
		seen[clean] = true
	return true
