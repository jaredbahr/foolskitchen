extends TestCase
## DayNotes: what a close leaves for the evening report (#526). Pure.


func _filled() -> DayNotes:
	var notes: DayNotes = DayNotes.new()
	notes.owner_award = {"happy_xp": 4, "profit_xp": 3, "review_xp": 2, "total_xp": 9, "level_before": 2}
	notes.owner_award_day = 5
	notes.owner_unlocks = ["Round table"] as Array[String]
	notes.owner_tips = ["Students tip little"] as Array[String]
	notes.career_tier_day = 5
	notes.career_tier_reached = 2
	notes.away_site_day = 5
	notes.away_site_lines = ["Second site: closed"] as Array[String]
	notes.loan_notice_day = 5
	notes.milestones_reached = [Milestone.new()] as Array[Milestone]
	notes.milestone_award_day = 5
	notes.milestone_xp = 30
	notes.weekly_challenge_reward_day = 5
	notes.weekly_challenge_line = "Weekly challenge complete"
	notes.opening_week_xp = 12
	notes.opening_week_xp_day = 5
	notes.record_day = 5
	notes.record_lines = ["New record"] as Array[String]
	return notes


func test_first_morning_clearing_drops_records_and_goals_only() -> void:
	var notes: DayNotes = _filled()
	notes.clear_records_and_goals()
	assert_eq(notes.record_day, 0)
	assert_true(notes.record_lines.is_empty())
	assert_true(notes.milestones_reached.is_empty())
	assert_eq(notes.milestone_award_day, 0)
	assert_eq(notes.milestone_xp, 0)
	assert_eq(notes.owner_award_day, 5, "the award waits for the second clearing")
	assert_eq(notes.weekly_challenge_reward_day, 5)
	assert_eq(notes.away_site_lines.size(), 1)


func test_second_morning_clearing_drops_the_awards_and_keeps_goal_chain_xp() -> void:
	var notes: DayNotes = _filled()
	notes.clear_awards()
	assert_true(notes.owner_award.is_empty())
	assert_true(notes.owner_unlocks.is_empty())
	assert_true(notes.owner_tips.is_empty())
	assert_eq(notes.owner_award_day, 0)
	assert_eq(notes.career_tier_day, 0)
	assert_eq(notes.career_tier_reached, 0)
	assert_eq(notes.away_site_day, 0)
	assert_true(notes.away_site_lines.is_empty())
	assert_eq(notes.loan_notice_day, 0)
	assert_eq(notes.weekly_challenge_reward_day, 0)
	assert_eq(notes.weekly_challenge_line, "")
	assert_eq(notes.record_day, 5, "records belong to the first clearing")
	assert_eq(notes.milestone_xp, 30)
	assert_eq(notes.opening_week_xp, 12, "goal-chain XP is dated, never cleared")
	assert_eq(notes.opening_week_xp_day, 5)


func test_bonus_xp_joins_the_days_award() -> void:
	var notes: DayNotes = DayNotes.new()
	notes.owner_award = {"happy_xp": 4, "profit_xp": 3, "review_xp": 2, "total_xp": 9, "level_before": 2}
	notes.owner_award_day = 5
	notes.add_bonus_xp(5, 30, 7, 3)
	assert_eq(int(notes.owner_award["total_xp"]), 39)
	assert_eq(int(notes.owner_award["happy_xp"]), 4)
	assert_eq(int(notes.owner_award["level_before"]), 2, "the day's own starting level stays")
	assert_eq(int(notes.owner_award["level_after"]), 3)
	assert_eq(notes.owner_award_day, 5)


func test_bonus_xp_alone_starts_an_award() -> void:
	var notes: DayNotes = DayNotes.new()
	notes.add_bonus_xp(8, 20, 4, 5)
	assert_eq(notes.owner_award, {"happy_xp": 0, "profit_xp": 0, "review_xp": 0, "total_xp": 20,
		"level_before": 4, "level_after": 5})
	assert_eq(notes.owner_award_day, 8)
	notes.add_bonus_xp(8, 5, 9, 5)
	assert_eq(int(notes.owner_award["total_xp"]), 25)
	assert_eq(int(notes.owner_award["level_before"]), 4, "a second bonus keeps the first starting level")
