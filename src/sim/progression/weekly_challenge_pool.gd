class_name WeeklyChallengePool
extends Resource
## Ordered authored challenge candidates. Draw order is stable for a seeded RNG.

const MAX_CHALLENGES: int = 32

@export var challenges: Array[WeeklyChallenge] = []


func is_valid() -> bool:
	if challenges.is_empty() or challenges.size() > MAX_CHALLENGES:
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
