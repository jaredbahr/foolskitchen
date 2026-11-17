class_name DayNotes
extends RefCounted
## What tonight's close decided, kept only for the evening report: the owner's
## XP award and what it unlocked, goals reached, the weekly reward, a career
## tier rise, the away sites' lines, the loan's first advance and new records.
##
## Never saved. Each fact carries the day it was written for, and the report
## shows it only for that day. The session writes these at closing and clears
## them each morning; the close and `build_report()` are the only readers (#526).

## The day's owner XP: {happy_xp, profit_xp, review_xp, total_xp,
## level_before, level_after}; empty when no XP was awarded.
var owner_award: Dictionary = {}
var owner_award_day: int = 0
var owner_unlocks: Array[String] = []
var owner_tips: Array[String] = []
## The close that raised the career tier, and the tier it reached.
var career_tier_day: int = 0
var career_tier_reached: int = 0
## The close that settled the owner's inactive sites, and its report lines
## (FK-087): one per away site, empty with a single site.
var away_site_day: int = 0
var away_site_lines: Array[String] = []
var loan_notice_day: int = 0
var tip_jar_day: int = 0
var tip_jar_bonus: int = -1
var milestones_reached: Array[Milestone] = []
var milestone_award_day: int = 0
var milestone_xp: int = 0
var weekly_challenge_reward_day: int = 0
var weekly_challenge_line: String = ""
## Goal-chain XP (#494). Not cleared in the morning: the day says when it counts.
var opening_week_xp: int = 0
var opening_week_xp_day: int = 0
var record_day: int = 0
var record_lines: Array[String] = []


## The morning's first clearing: yesterday's records and reached goals.
func clear_records_and_goals() -> void:
	record_day = 0
	record_lines.clear()
	milestones_reached.clear()
	milestone_award_day = 0
	milestone_xp = 0


## The morning's second clearing, once the day has started: the owner award,
## the tier, the away sites, the loan notice and the weekly reward.
func clear_awards() -> void:
	owner_award.clear()
	owner_unlocks.clear()
	owner_tips.clear()
	owner_award_day = 0
	career_tier_day = 0
	career_tier_reached = 0
	away_site_day = 0
	away_site_lines.clear()
	loan_notice_day = 0
	tip_jar_day = 0
	tip_jar_bonus = -1
	weekly_challenge_reward_day = 0
	weekly_challenge_line = ""


## Adds XP from a goal (a career goal or a goal chain) to the day's award. A
## day with no ordinary award starts one with only this XP in it.
func add_bonus_xp(day: int, xp: int, level_before: int, level_after: int) -> void:
	if owner_award.is_empty():
		owner_award = {"happy_xp": 0, "profit_xp": 0, "review_xp": 0,
			"total_xp": 0, "level_before": level_before}
	owner_award["total_xp"] = int(owner_award["total_xp"]) + xp
	owner_award["level_after"] = level_after
	owner_award_day = day
