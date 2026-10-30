class_name DemandBreakdown
extends RefCounted
## Detached multiplicative factors, suitable for a report or a forecast.

var reputation: float = 1.0
var word_of_mouth: float = 1.0
var menu: float = 1.0
var vibe: float = 1.0
var curb_appeal: float = 1.0
var total: float = 1.0


## Invalid facts fail without changing a live session or emitting engine errors.
static func evaluate(tuning: DemandTuning, stars: float, renown: float,
		enabled_dishes: int, vibe_score: float, day: int,
		curb_factor: float = 1.0) -> DemandBreakdown:
	if tuning == null or not tuning.is_valid() or not is_finite(stars) \
			or not is_finite(renown) or renown < 0.0 or enabled_dishes < 0 \
			or not is_finite(vibe_score) or vibe_score < 0.0 \
			or vibe_score > tuning.vibe_score_max or day < 1 \
			or not is_finite(curb_factor) or curb_factor <= 0.0:
		return null
	if stars < tuning.reputation_stars[0] or stars > tuning.reputation_stars[2]:
		return null
	var result: DemandBreakdown = DemandBreakdown.new()
	var lower: int = 0 if stars <= tuning.reputation_stars[1] else 1
	var proportion: float = (stars - tuning.reputation_stars[lower]) \
		/ (tuning.reputation_stars[lower + 1] - tuning.reputation_stars[lower])
	result.reputation = lerpf(tuning.reputation_factors[lower],
		tuning.reputation_factors[lower + 1], proportion)
	# Dividing first avoids overflow for a large, otherwise finite renown.
	var share: float = 0.0 if renown == 0.0 else 1.0 / (1.0 + tuning.renown_half_saturation / renown)
	result.word_of_mouth = 1.0 + (tuning.renown_max_factor - 1.0) * share
	result.menu = 1.0 + minf(tuning.menu_max_bonus,
		float(maxi(0, enabled_dishes - tuning.starting_dishes)) * tuning.menu_per_extra_dish)
	result.vibe = lerpf(tuning.vibe_min_factor, tuning.vibe_max_factor,
		vibe_score / tuning.vibe_score_max)
	if day <= tuning.intro_days:
		result.vibe = maxf(result.vibe, tuning.intro_vibe_floor)
	result.curb_appeal = curb_factor
	var product: float = result.reputation * result.word_of_mouth * result.menu * result.vibe * result.curb_appeal
	if not is_finite(product) or product <= 0.0:
		return null
	result.total = minf(tuning.total_cap, product)
	return result


func to_dict() -> Dictionary:
	return {"reputation": reputation, "word_of_mouth": word_of_mouth,
		"menu": menu, "vibe": vibe, "curb_appeal": curb_appeal, "total": total}
