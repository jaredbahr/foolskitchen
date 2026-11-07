class_name ReputationBook
extends RefCounted
## A deterministic rolling review window. The caller owns the named RNG and
## invokes record_visit once at departure; this model has no scene or autoload.

const WINDOW: int = 30
const INITIAL_REVIEWS: int = 5
const INITIAL_STARS: int = 3
const VIBE_TUNING: VibeTuning = preload("res://data/balance/vibe.tres")

var _scores: Array[int] = []
## Report wording is day-local. It is deliberately absent from the save format.
var _quotes_used_today: Dictionary[String, bool] = {}


func _init() -> void:
	reset()


func reset() -> void:
	_scores.clear()
	_quotes_used_today.clear()
	for _index: int in range(INITIAL_REVIEWS):
		_scores.append(INITIAL_STARS)


func begin_day() -> void:
	_quotes_used_today.clear()


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
		random: RandomNumberGenerator, vibe_tuning: VibeTuning = VIBE_TUNING) -> Dictionary:
	if visit == null or visit.closing or tuning == null or not tuning.is_valid() \
			or quotes == null or random == null:
		return {}
	if not is_finite(visit.review_chance_multiplier) or visit.review_chance_multiplier < 0.0:
		return {}
	var chance: float = clampf(tuning.review_chance * visit.review_chance_multiplier, 0.0, 1.0)
	if random.randf() >= chance:
		return {}
	var before: float = average()
	var stars: int = score_visit(visit, tuning, vibe_tuning)
	var cause: StringName = cause_of(visit, tuning, vibe_tuning)
	var quote: String = quotes.pick(cause, random, _quotes_used_today)
	if not quote.is_empty():
		_quotes_used_today[quote] = true
	_scores.append(stars)
	if _scores.size() > WINDOW:
		_scores.pop_front()
	return {"stars": stars, "cause": cause, "quote": quote,
		"before": before, "after": average()}


## One booking-level review uses the average measured guest score. Only a
## complete, well-served party receives its authored weight; no member writes
## a separate solo review.
func record_booking(visits: Array[ReviewVisit], tuning: ReviewTuning, quotes: ReviewQuotes,
		random: RandomNumberGenerator, booking_tuning: BookingTuning = null,
		expected_members: int = 0) -> Dictionary:
	var terms: BookingTuning = booking_tuning if booking_tuning != null else BookingTuning.new()
	if visits.is_empty() or tuning == null or not tuning.is_valid() or quotes == null \
			or random == null or not terms.is_valid() or expected_members < 0:
		return {}
	var total: int = 0
	var worst_score: int = 6
	var cause: StringName = &"lovely_place"
	for visit: ReviewVisit in visits:
		if visit == null:
			return {}
		# Booking accountability includes a group that expires at closing, while
		# ordinary closing reviews remain suppressed. Scoring never mutates input.
		var score: int = score_visit(visit, tuning, VIBE_TUNING, true)
		total += score
		if score < worst_score:
			worst_score = score
			cause = cause_of(visit, tuning, VIBE_TUNING, true)
	var stars: int = clampi(roundi(float(total) / float(visits.size())), 1, 5)
	var all_served: bool = expected_members > 0 and visits.size() == expected_members
	for visit: ReviewVisit in visits:
		all_served = all_served and visit.served
	var good_service: bool = all_served and stars >= terms.good_service_stars
	var weight: int = terms.review_weight if good_service else 1
	var before: float = average()
	var quote: String = quotes.pick(cause, random, _quotes_used_today)
	if not quote.is_empty():
		_quotes_used_today[quote] = true
	for _copy: int in weight:
		_scores.append(stars)
	while _scores.size() > WINDOW:
		_scores.pop_front()
	return {"stars": stars, "cause": cause, "quote": quote, "weight": weight,
		"good_service": good_service, "before": before, "after": average()}


## The disguised critic's review (#303): always written (no review-chance draw),
## scored from the same causes as any guest, and counted several times in the
## window (min(weight, a quarter of the reviews held, at least 1)). The headline quote comes from the critic groups by verdict; the
## stream is the critic's own. Returns the report row, or {} for a closing guest.
func record_critic(visit: ReviewVisit, tuning: ReviewTuning, quotes: ReviewQuotes,
		random: RandomNumberGenerator, critic: CriticTuning, vibe_tuning: VibeTuning = VIBE_TUNING) -> Dictionary:
	if visit == null or visit.closing or tuning == null or not tuning.is_valid() \
			or quotes == null or random == null or critic == null or not critic.is_valid():
		return {}
	var before: float = average()
	var stars: int = score_visit(visit, tuning, vibe_tuning)
	var cause: StringName = &"critic_good" if stars >= critic.good_stars else &"critic_bad"
	var quote: String = quotes.pick(cause, random, _quotes_used_today)
	# Up to review_weight copies, but never more than a quarter of the reviews
	# already in the window, so a young shop is not swung by one visit.
	var copies: int = mini(critic.review_weight, maxi(1, _scores.size() / 4))
	for _count: int in copies:
		_scores.append(stars)
	while _scores.size() > WINDOW:
		_scores.pop_front()
	return {"stars": stars, "cause": cause, "quote": quote, "before": before, "after": average()}


## Four penalties remain authored in reviews.tres. The optional raw ambience
## term is bounded by vibe.tres before rounding; it is not fractional-star storage.
## The final rating remains in the physical one-to-five-star range.
## Unserved guests always score one star; a closing guest is not scored.
static func score_visit(visit: ReviewVisit, tuning: ReviewTuning, vibe_tuning: VibeTuning = VIBE_TUNING,
		include_closing: bool = false) -> int:
	if visit == null or visit.closing and not include_closing or tuning == null or not tuning.is_valid():
		return 0
	if not visit.served:
		return 1
	var penalty: float = _unit(visit.queue_wait_fraction) * tuning.queue_wait_weight \
		+ _unit(visit.food_wait_fraction) * tuning.food_wait_weight \
		+ _unit(visit.price_ratio - 1.0) * tuning.overprice_weight \
		+ _unit(visit.dirt_fraction) * tuning.dirt_weight
	var maximum: float = vibe_tuning.max_review_bonus if vibe_tuning != null and vibe_tuning.is_valid() else 0.0
	var vibe_bonus: float = clampf(visit.vibe_review_bonus, 0.0, maximum) if is_finite(visit.vibe_review_bonus) else 0.0
	# Keep the physical star domain before integer conversion, even for large
	# finite authored caps. Ordinary rounding and final-score quote policy agree.
	# Half-quality is neutral; bad food can hurt quality-sensitive guests too.
	# Invalid measurements stay neutral; Regular's zero weight is exact.
	var quality_bonus: float = 0.0
	if is_finite(visit.quality) and is_finite(visit.quality_weight) and visit.quality_weight > 0.0:
		quality_bonus = (clampf(visit.quality, 0.0, 1.0) - 0.5) * visit.quality_weight
	# Restrooms (FK-101): both terms are exactly zero in a shop that has none
	# and is below the seat threshold.
	var restroom: float = _bounded(visit.restroom_bonus, 1.0) - _bounded(visit.restroom_penalty, 4.0)
	return roundi(clampf(5.0 - penalty + vibe_bonus + quality_bonus + restroom, 1.0, 5.0))


static func _bounded(value: float, maximum: float) -> float:
	return clampf(value, 0.0, maximum) if is_finite(value) else 0.0


## High ratings and visits without a substantial single complaint get a
## positive quote. For lower ratings, stable ties keep this explicit order.
static func cause_of(visit: ReviewVisit, tuning: ReviewTuning, vibe_tuning: VibeTuning = VIBE_TUNING,
		include_closing: bool = false) -> StringName:
	if visit == null or visit.closing and not include_closing or tuning == null or not tuning.is_valid():
		return &""
	if not visit.served:
		return &"never_served"
	var causes: Array[StringName] = [&"slow_seating", &"slow_food", &"too_pricey", &"dirty_floor", &"no_restroom"]
	var penalties: Array[float] = [
		_unit(visit.queue_wait_fraction) * tuning.queue_wait_weight,
		_unit(visit.food_wait_fraction) * tuning.food_wait_weight,
		_unit(visit.price_ratio - 1.0) * tuning.overprice_weight,
		_unit(visit.dirt_fraction) * tuning.dirt_weight,
		_bounded(visit.restroom_penalty, 4.0),
	]
	var best: int = -1
	var largest: float = 0.0
	for index: int in range(penalties.size()):
		if penalties[index] > largest:
			largest = penalties[index]
			best = index
	# A guest who needed a restroom and couldn't use one says so when that was
	# their biggest complaint, even on a good day (FK-101). Zero otherwise.
	if visit.sticky_floor:
		return &"sticky_floor"
	if best == causes.size() - 1:
		return &"restroom_busy" if visit.restroom_was_busy else &"no_restroom"
	if score_visit(visit, tuning, vibe_tuning, include_closing) >= 4 or largest < tuning.positive_penalty_threshold:
		if visit.petted_cat:
			return &"petted_cat"
		if visit.waited_seated:
			return &"comfortable_wait"
		return &"great_value" if is_finite(visit.price_ratio) and visit.price_ratio < 0.9 else &"lovely_place"
	if best >= 0:
		if best == 0 and visit.waited_seated:
			return &"comfortable_wait"
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
	_quotes_used_today.clear()
	return true


static func _unit(value: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floor(number) == number
