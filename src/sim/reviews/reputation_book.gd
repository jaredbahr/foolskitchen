class_name ReputationBook
extends RefCounted
## A deterministic rolling review window. The caller owns the named RNG and
## invokes record_visit once at departure; this model has no scene or autoload.

const WINDOW: int = 30
const INITIAL_REVIEWS: int = 5
const INITIAL_STARS: int = 3

var _scores: Array[int] = []


func _init() -> void:
	reset()


func reset() -> void:
	_scores.clear()
	for _index: int in range(INITIAL_REVIEWS):
		_scores.append(INITIAL_STARS)


func scores() -> Array[int]:
	return _scores.duplicate()


func average() -> float:
	var total: int = 0
	for score: int in _scores:
		total += score
	return float(total) / float(_scores.size()) if not _scores.is_empty() else 3.0


## The caller samples this once before starting the day; later reviews never
## change an already-running day's spawner gap.
func arrival_multiplier(tuning: ReviewTuning) -> float:
	if tuning == null or not tuning.is_valid():
		return 1.0
	return lerpf(tuning.arrivals_at_one_star, tuning.arrivals_at_five_stars,
		clampf((average() - 1.0) / 4.0, 0.0, 1.0))


## A closing-time departure produces no review and consumes no random draw.
## Otherwise one draw decides whether this guest reviews, then quote selection
## uses the same injected, seeded stream. Returns a detached report row.
func record_visit(visit: ReviewVisit, tuning: ReviewTuning, quotes: ReviewQuotes,
		random: RandomNumberGenerator) -> Dictionary:
	if visit == null or visit.closing or tuning == null or not tuning.is_valid() \
			or quotes == null or random == null:
		return {}
	if random.randf() >= tuning.review_chance:
		return {}
	var before: float = average()
	var stars: int = score_visit(visit, tuning)
	var cause: StringName = cause_of(visit, tuning)
	var quote: String = quotes.pick(cause, random)
	_scores.append(stars)
	if _scores.size() > WINDOW:
		_scores.pop_front()
	return {"stars": stars, "cause": cause, "quote": quote,
		"before": before, "after": average()}


## The scoring rule is fixed, with its four penalties authored in reviews.tres.
## Unserved guests always score one star; a closing guest is not scored.
static func score_visit(visit: ReviewVisit, tuning: ReviewTuning) -> int:
	if visit == null or visit.closing or tuning == null or not tuning.is_valid():
		return 0
	if not visit.served:
		return 1
	var penalty: float = _unit(visit.queue_wait_fraction) * tuning.queue_wait_weight \
		+ _unit(visit.food_wait_fraction) * tuning.food_wait_weight \
		+ _unit(visit.price_ratio - 1.0) * tuning.overprice_weight \
		+ _unit(visit.dirt_fraction) * tuning.dirt_weight
	return clampi(roundi(5.0 - penalty), 1, 5)


## High ratings and visits without a substantial single complaint get a
## positive quote. For lower ratings, stable ties keep this explicit order.
static func cause_of(visit: ReviewVisit, tuning: ReviewTuning) -> StringName:
	if visit == null or visit.closing or tuning == null or not tuning.is_valid():
		return &""
	if not visit.served:
		return &"never_served"
	var causes: Array[StringName] = [&"slow_seating", &"slow_food", &"too_pricey", &"dirty_floor"]
	var penalties: Array[float] = [
		_unit(visit.queue_wait_fraction) * tuning.queue_wait_weight,
		_unit(visit.food_wait_fraction) * tuning.food_wait_weight,
		_unit(visit.price_ratio - 1.0) * tuning.overprice_weight,
		_unit(visit.dirt_fraction) * tuning.dirt_weight,
	]
	var best: int = -1
	var largest: float = 0.0
	for index: int in range(penalties.size()):
		if penalties[index] > largest:
			largest = penalties[index]
			best = index
	if score_visit(visit, tuning) >= 4 or largest < tuning.positive_penalty_threshold:
		return &"great_value" if is_finite(visit.price_ratio) and visit.price_ratio < 0.9 else &"lovely_place"
	if best >= 0:
		return causes[best]
	return &"great_value" if is_finite(visit.price_ratio) and visit.price_ratio < 0.9 else &"lovely_place"


func to_dict() -> Dictionary:
	return {"version": 1, "scores": _scores.duplicate()}


## Validate every record before replacing the live window. JSON's integral
## floats are accepted, but fractional, non-finite, or extra fields are not.
func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if data.size() != 2 or not _whole(data.get("version"), 1, 1) or not data.get("scores") is Array:
		return false
	var saved: Array = data["scores"]
	if saved.size() < INITIAL_REVIEWS or saved.size() > WINDOW:
		return false
	var restored: Array[int] = []
	for item: Variant in saved:
		if not _whole(item, 1, 5):
			return false
		restored.append(int(item))
	_scores = restored
	return true


static func _unit(value: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floor(number) == number
