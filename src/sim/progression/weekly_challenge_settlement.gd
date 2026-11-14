class_name WeeklyChallengeSettlement
extends RefCounted
## Prepared close-day progress. The session installs the result before paying cash.

const MAX_CASH: int = 9223372036854775807

var state: WeeklyChallengeState
var completed: bool = false
var expired: bool = false
var cash_reward: int = 0
var report_text: String = ""


static func prepare(live_state: WeeklyChallengeState, observation: MilestoneDay,
		ledger_cash: int, first_week_pool: WeeklyChallengePool = null,
		seats: int = 0) -> WeeklyChallengeSettlement:
	if live_state == null or not live_state.is_active() or observation == null \
			or observation.day <= live_state.last_evaluated_day:
		return null
	var staged: WeeklyChallengeState = WeeklyChallengeState.new()
	if not staged.from_dict(live_state.to_dict()):
		return null
	if first_week_pool != null:
		staged.size_first_week(first_week_pool, observation, seats)
	var outcome: Dictionary = staged.apply_day(observation)
	if outcome.is_empty():
		return null
	var reward: int = int(outcome.get("reward_cash", 0))
	if reward < 0 or reward > MAX_CASH or ledger_cash > MAX_CASH - reward:
		return null
	var result: WeeklyChallengeSettlement = WeeklyChallengeSettlement.new()
	result.state = staged
	result.completed = bool(outcome.get("completed", false))
	result.expired = bool(outcome.get("expired", false))
	result.cash_reward = reward
	if result.completed:
		result.report_text = "Weekly challenge: +$%d" % reward
	return result
