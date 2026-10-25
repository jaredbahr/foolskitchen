class_name MilestoneSettlement
extends RefCounted
## A prepared day-close reward batch. The caller installs these detached models
## and records cash only after preparation succeeds; this model never pays.

const MAX_CASH: int = 9223372036854775807

var tracker: MilestoneTracker
var owner_progress: OwnerProgress
var reached: Array[Milestone] = []
var cash_reward: int = 0
var xp_reward: int = 0
var owner_xp_result: Dictionary = {}


static func prepare(live_tracker: MilestoneTracker, catalogue: MilestoneSet,
		observation: MilestoneDay, live_owner: OwnerProgress, ledger_cash: int) -> MilestoneSettlement:
	if live_tracker == null or live_owner == null or live_owner.tuning == null or observation == null \
			or observation.day <= live_tracker.last_evaluated_day:
		return null
	var staged_tracker: MilestoneTracker = MilestoneTracker.new()
	if not staged_tracker.from_dict(live_tracker.to_dict()):
		return null
	var staged_tuning: ProgressionTuning = live_owner.tuning.duplicate(true) as ProgressionTuning
	var staged_owner: OwnerProgress = OwnerProgress.new(staged_tuning)
	if not staged_owner.from_dict(live_owner.to_dict()):
		return null
	var newly_reached: Array[Milestone] = staged_tracker.evaluate_day(observation, catalogue)
	# An empty batch can still be a valid close. Refused evaluation never advances
	# the clone's day, so it must not masquerade as that valid empty result.
	if staged_tracker.last_evaluated_day != observation.day:
		return null
	var total_cash: int = 0
	var total_xp: int = 0
	for goal: Milestone in newly_reached:
		if goal.reward_xp > OwnerProgress.MAX_TOTAL_XP - staged_owner.total_xp - total_xp \
				or goal.reward_cash > MAX_CASH - total_cash:
			return null
		total_xp += goal.reward_xp
		total_cash += goal.reward_cash
	if ledger_cash > MAX_CASH - total_cash:
		return null
	var bonus: Dictionary = staged_owner.award_bonus(total_xp)
	if bonus.is_empty():
		return null
	var result: MilestoneSettlement = MilestoneSettlement.new()
	result.tracker = staged_tracker
	result.owner_progress = staged_owner
	for goal: Milestone in newly_reached:
		result.reached.append(goal.duplicate(true) as Milestone)
	result.cash_reward = total_cash
	result.xp_reward = total_xp
	result.owner_xp_result = bonus.duplicate(true)
	return result
