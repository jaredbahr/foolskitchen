class_name WeeklyChallengeState
extends RefCounted
## One frozen weekly objective and its day-close progress. UI reads are detached.

const SAVE_VERSION: int = 1
const WEEK_DAYS: int = 7
const MAX_DAY: int = 1000000
const MAX_PROGRESS: int = 1000000000

enum Status { EMPTY, ACTIVE, COMPLETED, EXPIRED }

var status: Status = Status.EMPTY
var challenge_id: StringName = &""
var previous_challenge_id: StringName = &""
var kind: int = WeeklyChallenge.Kind.SERVE_IN_ONE_DAY
var start_day: int = 0
var end_day: int = 0
var target: int = 0
var reward_cash: int = 0
var dish_id: StringName = &""
var dish_name: String = ""
var text: String = ""
var progress: int = 0
var last_evaluated_day: int = 0


func is_active() -> bool:
	return status == Status.ACTIVE


func days_left(day: int) -> int:
	if not is_active() or day < start_day or day > end_day:
		return 0
	return end_day - day + 1


## Request-only display projection. The live challenge changes only at close.
func projected_progress(observation: MilestoneDay) -> int:
	if not is_active() or observation == null or not observation.is_valid() \
			or observation.day != last_evaluated_day + 1 or observation.day > end_day:
		return progress
	match kind:
		WeeklyChallenge.Kind.SERVE_IN_ONE_DAY:
			return maxi(progress, observation.served_today)
		WeeklyChallenge.Kind.OPERATING_PROFIT:
			return progress + observation.operating_profit
		WeeklyChallenge.Kind.NO_LOSS_DAYS:
			# A clean day is committed only by apply_day at service close. The
			# current morning/open observation is not yet a completed day.
			return progress
		WeeklyChallenge.Kind.GOOD_REVIEWS:
			return progress + observation.good_reviews_today
		WeeklyChallenge.Kind.SELL_DISH:
			return progress + int(observation.dishes_sold.get(dish_id, 0))
	return progress


func begin_week(day: int, owner_level: int, pool: WeeklyChallengePool,
		enabled_menu: Array[RecipeDef], random: RandomNumberGenerator) -> bool:
	if day < 1 or day > MAX_DAY - WEEK_DAYS + 1 or not _is_rotation_day(day) \
			or (status != Status.EMPTY and day <= end_day) \
			or (status == Status.EMPTY and challenge_id != &"") or owner_level < 1 or owner_level > MAX_DAY \
			or pool == null or not pool.is_valid() or random == null:
		return false
	var dishes: Array[RecipeDef] = []
	for recipe: RecipeDef in enabled_menu:
		if recipe != null and not recipe.id.is_empty() \
				and recipe.id.length() <= WeeklyChallenge.MAX_ID_LENGTH \
				and not recipe.display_name.strip_edges().is_empty() \
				and recipe.display_name.strip_edges().length() <= WeeklyChallenge.MAX_DISH_NAME_LENGTH:
			dishes.append(recipe)
	var eligible: Array[WeeklyChallenge] = []
	var dish_options: Dictionary = {}
	for candidate: WeeklyChallenge in pool.challenges:
		var candidate_target: int = candidate.target_at_level(owner_level)
		if candidate_target < 1:
			continue
		if candidate.kind != WeeklyChallenge.Kind.SELL_DISH:
			if not candidate.display_text(candidate_target).is_empty():
				eligible.append(candidate)
			continue
		var valid_dishes: Array[RecipeDef] = []
		for recipe: RecipeDef in dishes:
			if not candidate.display_text(candidate_target, recipe.display_name.strip_edges()).is_empty():
				valid_dishes.append(recipe)
		if not valid_dishes.is_empty():
			eligible.append(candidate)
			dish_options[candidate.id] = valid_dishes
	var fresh: Array[WeeklyChallenge] = []
	for candidate: WeeklyChallenge in eligible:
		if candidate.id != previous_challenge_id:
			fresh.append(candidate)
	if not previous_challenge_id.is_empty():
		if fresh.is_empty():
			return false
		eligible = fresh
	if eligible.is_empty():
		return false
	var selected: WeeklyChallenge = eligible[random.randi_range(0, eligible.size() - 1)]
	var frozen_target: int = selected.target_at_level(owner_level)
	if frozen_target < 1:
		return false
	var frozen_dish: RecipeDef = null
	if selected.kind == WeeklyChallenge.Kind.SELL_DISH:
		var selected_dishes: Array[RecipeDef] = dish_options.get(selected.id, []) as Array[RecipeDef]
		if selected_dishes.is_empty():
			return false
		frozen_dish = selected_dishes[random.randi_range(0, selected_dishes.size() - 1)]
	var frozen_text: String = selected.display_text(frozen_target,
		frozen_dish.display_name.strip_edges() if frozen_dish != null else "")
	if frozen_text.is_empty():
		return false
	status = Status.ACTIVE
	challenge_id = selected.id
	previous_challenge_id = selected.id
	kind = selected.kind
	start_day = day
	end_day = day + WEEK_DAYS - 1
	target = frozen_target
	reward_cash = selected.reward_cash
	dish_id = frozen_dish.id if frozen_dish != null else &""
	dish_name = frozen_dish.display_name.strip_edges() if frozen_dish != null else ""
	text = frozen_text
	progress = 0
	last_evaluated_day = day - 1
	return true


func begin_legacy_week(day: int, owner_level: int, pool: WeeklyChallengePool,
		enabled_menu: Array[RecipeDef], random: RandomNumberGenerator) -> bool:
	if day < 1 or day > MAX_DAY or status != Status.EMPTY \
			or not challenge_id.is_empty():
		return false
	var week_start: int = ((day - 1) / WEEK_DAYS) * WEEK_DAYS + 1
	var candidate: WeeklyChallengeState = WeeklyChallengeState.new()
	candidate.previous_challenge_id = previous_challenge_id
	if not candidate.begin_week(week_start, owner_level, pool, enabled_menu, random):
		return false
	candidate.last_evaluated_day = day - 1
	previous_challenge_id = candidate.previous_challenge_id
	status = candidate.status
	challenge_id = candidate.challenge_id
	kind = candidate.kind
	start_day = candidate.start_day
	end_day = candidate.end_day
	target = candidate.target
	reward_cash = candidate.reward_cash
	dish_id = candidate.dish_id
	dish_name = candidate.dish_name
	text = candidate.text
	progress = 0
	last_evaluated_day = candidate.last_evaluated_day
	return true


func apply_day(observation: MilestoneDay) -> Dictionary:
	if not is_active() or observation == null or not observation.is_valid() \
			or observation.day != last_evaluated_day + 1 or observation.day > end_day:
		return {}
	var next_progress: int = progress
	match kind:
		WeeklyChallenge.Kind.SERVE_IN_ONE_DAY:
			next_progress = maxi(progress, observation.served_today)
		WeeklyChallenge.Kind.OPERATING_PROFIT:
			next_progress = progress + observation.operating_profit
		WeeklyChallenge.Kind.NO_LOSS_DAYS:
			if observation.lost_today == 0:
				next_progress += 1
		WeeklyChallenge.Kind.GOOD_REVIEWS:
			next_progress += observation.good_reviews_today
		WeeklyChallenge.Kind.SELL_DISH:
			next_progress += int(observation.dishes_sold.get(dish_id, 0))
		_:
			return {}
	if next_progress < -MAX_PROGRESS or next_progress > MAX_PROGRESS:
		return {}
	progress = next_progress
	last_evaluated_day = observation.day
	if progress >= target:
		status = Status.COMPLETED
		return {"completed": true, "expired": false, "reward_cash": reward_cash, "title": text}
	if observation.day == end_day:
		status = Status.EXPIRED
		return {"completed": false, "expired": true, "reward_cash": 0, "title": text}
	return {"completed": false, "expired": false, "reward_cash": 0, "title": text}


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "status": status, "challenge_id": String(challenge_id),
		"previous_challenge_id": String(previous_challenge_id), "kind": kind,
		"start_day": start_day, "end_day": end_day, "target": target,
		"reward_cash": reward_cash, "dish_id": String(dish_id), "dish_name": dish_name,
		"text": text, "progress": progress, "last_evaluated_day": last_evaluated_day}


func from_dict(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var row: Dictionary = value
	if row.size() != 14 or not _whole(row.get("version"), SAVE_VERSION, SAVE_VERSION) \
			or not _whole(row.get("status"), Status.EMPTY, Status.EXPIRED) \
			or not row.get("challenge_id") is String or not row.get("previous_challenge_id") is String \
			or not _whole(row.get("kind"), WeeklyChallenge.Kind.SERVE_IN_ONE_DAY, WeeklyChallenge.Kind.SELL_DISH) \
			or not _whole(row.get("start_day"), 0, MAX_DAY) or not _whole(row.get("end_day"), 0, MAX_DAY) \
			or not _whole(row.get("target"), 0, WeeklyChallenge.MAX_TARGET) \
			or not _whole(row.get("reward_cash"), 0, WeeklyChallenge.MAX_REWARD) \
			or not row.get("dish_id") is String or not row.get("dish_name") is String \
			or not row.get("text") is String or not _whole(row.get("progress"), -MAX_PROGRESS, MAX_PROGRESS) \
			or not _whole(row.get("last_evaluated_day"), 0, MAX_DAY):
		return false
	var next_status: int = int(row["status"])
	var next_id: StringName = StringName(row["challenge_id"])
	var next_previous: StringName = StringName(row["previous_challenge_id"])
	var next_kind: int = int(row["kind"])
	var next_start: int = int(row["start_day"])
	var next_end: int = int(row["end_day"])
	var next_target: int = int(row["target"])
	var next_reward: int = int(row["reward_cash"])
	var next_dish: StringName = StringName(row["dish_id"])
	var next_dish_name: String = str(row["dish_name"])
	var next_text: String = str(row["text"])
	var next_progress: int = int(row["progress"])
	var next_evaluated: int = int(row["last_evaluated_day"])
	if next_id.length() > WeeklyChallenge.MAX_ID_LENGTH \
			or next_previous.length() > WeeklyChallenge.MAX_ID_LENGTH \
			or next_dish.length() > WeeklyChallenge.MAX_ID_LENGTH \
			or next_dish_name.length() > WeeklyChallenge.MAX_DISH_NAME_LENGTH \
			or next_text.length() > WeeklyChallenge.MAX_RENDERED_TEXT_LENGTH:
		return false
	if next_status == Status.EMPTY:
		if not next_id.is_empty() or next_start != 0 or next_end != 0 or next_target != 0 \
				or next_reward != 0 or not next_dish.is_empty() or not next_dish_name.is_empty() \
				or not next_text.is_empty() or next_progress != 0 or next_evaluated != 0:
			return false
	elif next_id.is_empty() or next_previous != next_id or next_start < 1 \
			or next_end != next_start + WEEK_DAYS - 1 or not _is_rotation_day(next_start) \
			or next_target < 1 or next_reward < 1 or next_text.strip_edges().is_empty() \
			or next_evaluated < next_start - 1 or next_evaluated > next_end:
		return false
	if next_status != Status.EMPTY and next_kind != WeeklyChallenge.Kind.OPERATING_PROFIT and next_progress < 0:
		return false
	if next_status != Status.EMPTY and next_kind == WeeklyChallenge.Kind.NO_LOSS_DAYS \
			and next_target > WEEK_DAYS:
		return false
	if next_kind == WeeklyChallenge.Kind.SELL_DISH:
		if next_dish.is_empty() or next_dish_name.strip_edges().is_empty():
			return false
	elif not next_dish.is_empty() or not next_dish_name.is_empty():
		return false
	if next_status == Status.ACTIVE and (next_evaluated >= next_end or next_progress >= next_target):
		return false
	if next_status == Status.COMPLETED and (next_progress < next_target or next_evaluated < next_start):
		return false
	if next_status == Status.EXPIRED and (next_progress >= next_target or next_evaluated != next_end):
		return false
	status = next_status
	challenge_id = next_id
	previous_challenge_id = next_previous
	kind = next_kind
	start_day = next_start
	end_day = next_end
	target = next_target
	reward_cash = next_reward
	dish_id = next_dish
	dish_name = next_dish_name
	text = next_text
	progress = next_progress
	last_evaluated_day = next_evaluated
	return true


static func rotation_day(day: int) -> bool:
	return day >= 1 and (day - 1) % WEEK_DAYS == 0


static func _is_rotation_day(day: int) -> bool:
	return rotation_day(day)


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and floorf(number) == number
