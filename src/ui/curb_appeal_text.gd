class_name CurbAppealText
extends RefCounted
## Shared plain words for the read-only score and its authored walk-in factor.

const TITLE: String = "Curb appeal"
const UNAVAILABLE: String = "Curb appeal —"
const BONUS_UNAVAILABLE: String = "Bonus unavailable"
const NO_BONUS: String = "No walk-in bonus"
const SMALL_BONUS: String = "Less than +1% walk-ins"
const EXPLANATION: String = "Your street front can draw more walk-ins. Actual arrivals can vary."


static func is_presentable(score: float, multiplier: float) -> bool:
	return is_finite(score) and is_finite(multiplier) and multiplier >= 1.0 \
		and is_finite((multiplier - 1.0) * 100.0)


static func caption(score: float) -> String:
	if not is_finite(score):
		return UNAVAILABLE
	return "%s %d / 100" % [TITLE, roundi(clampf(score, 0.0, 100.0))]


static func bonus(multiplier: float) -> String:
	if not is_presentable(0.0, multiplier):
		return BONUS_UNAVAILABLE
	if multiplier == 1.0:
		return NO_BONUS
	var rounded: float = roundf((multiplier - 1.0) * 100.0)
	if rounded == 0.0:
		return SMALL_BONUS
	return "About +%.0f%% walk-ins" % rounded


static func explanation(score: float, multiplier: float) -> String:
	if not is_presentable(score, multiplier):
		return "%s. %s." % [UNAVAILABLE, BONUS_UNAVAILABLE]
	return "%s. %s. %s" % [caption(score), bonus(multiplier), EXPLANATION]


## A forecast stores the factor, so this line never invents a historical score.
static func forecast_line(multiplier: float) -> String:
	if not is_presentable(0.0, multiplier):
		return "%s: unavailable" % TITLE
	if multiplier == 1.0:
		return "%s: no change" % TITLE
	var rounded: float = roundf((multiplier - 1.0) * 100.0)
	if rounded == 0.0:
		return "%s: less than +1%%" % TITLE
	return "%s +%.0f%%" % [TITLE, rounded]
