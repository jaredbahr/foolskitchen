class_name WeeklyChallengePool
extends Resource
## Ordered authored challenge candidates. Draw order is stable for a seeded RNG.

const MAX_CHALLENGES: int = 32

@export var challenges: Array[WeeklyChallenge] = []
@export_range(0.0, 0.25, 0.01) var recent_stretch: float = 0.15
@export_range(1, 20, 1) var guests_per_seat_per_day: int = 4
@export_range(0, 10, 1) var max_recent_no_table_losses: int = 1


func is_valid() -> bool:
	if challenges.is_empty() or challenges.size() > MAX_CHALLENGES \
			or not is_finite(recent_stretch) or recent_stretch < 0.0 or recent_stretch > 0.25 \
			or guests_per_seat_per_day < 1 or guests_per_seat_per_day > 20 \
			or max_recent_no_table_losses < 0 or max_recent_no_table_losses > 10:
		return false
	var seen: Dictionary[StringName, bool] = {}
	for challenge: WeeklyChallenge in challenges:
		if challenge == null or not challenge.is_valid() or seen.has(challenge.id):
			return false
		seen[challenge.id] = true
	return true


func by_id(id: StringName) -> WeeklyChallenge:
	for challenge: WeeklyChallenge in challenges:
		if challenge != null and challenge.id == id:
			return challenge
	return null


## Size against the shop's observed rate, projected over the available days
## for cumulative goals. A clean-day draw needs a history of clean service.
func shop_target(challenge: WeeklyChallenge, recent: Array[Dictionary], seats: int,
		service_days: int, dish_id: StringName = &"") -> int:
	var total: float = 0.0
	var measured: int = 0
	var no_table: int = 0
	for row: Dictionary in recent:
		match challenge.kind:
			WeeklyChallenge.Kind.SERVE_IN_ONE_DAY:
				total += float(row["served"])
			WeeklyChallenge.Kind.OPERATING_PROFIT:
				if not row.has("weekly_profit"):
					continue
				total += float(row["weekly_profit"])
			WeeklyChallenge.Kind.NO_LOSS_DAYS:
				# Old rows still prove zero losses. Otherwise their seating cause is unknown.
				no_table += mini(int(row.get("no_table", row["lost"])), max_recent_no_table_losses + 1)
				total += 1.0 if int(row["lost"]) == 0 else 0.0
			WeeklyChallenge.Kind.GOOD_REVIEWS:
				if not row.has("good_reviews"):
					continue
				total += float(row["good_reviews"])
			WeeklyChallenge.Kind.SELL_DISH:
				if not row.has("dishes_sold"):
					continue
				total += float(row["dishes_sold"].get(String(dish_id), 0))
		measured += 1
	var target: int = challenge.base_target
	if challenge.kind == WeeklyChallenge.Kind.NO_LOSS_DAYS:
		if measured == 0:
			return mini(target, service_days)
		if no_table > max_recent_no_table_losses or total == 0.0:
			return 0
		return clampi(roundi(total / measured * service_days), 1, mini(target, service_days))
	if measured > 0:
		if total <= 0.0 and challenge.kind != WeeklyChallenge.Kind.SERVE_IN_ONE_DAY:
			return 0
		var period: int = 1 if challenge.kind == WeeklyChallenge.Kind.SERVE_IN_ONE_DAY else service_days
		var bumped: float = total / measured * period * (1.0 + recent_stretch)
		target = roundi(clampf(bumped, 1.0, WeeklyChallenge.MAX_TARGET))
	if challenge.kind == WeeklyChallenge.Kind.SERVE_IN_ONE_DAY:
		return mini(target, clampi(seats, 0, WeeklyChallenge.MAX_TARGET) * guests_per_seat_per_day)
	return target
