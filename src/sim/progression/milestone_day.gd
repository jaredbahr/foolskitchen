class_name MilestoneDay
extends RefCounted
## One immutable-by-convention day-close observation. Main will construct this
## from existing counters before milestone rewards enter the ledger or owner XP.

const MAX_COUNT: int = 1000000
const MAX_PROFIT: int = 1000000000

var day: int = 0
var served_today: int = 0
var lost_today: int = 0
var reputation: float = 3.0
var operating_profit: int = 0
var owner_level: int = 1
var staff_count: int = 0


func is_valid() -> bool:
	return day >= 1 and day <= MAX_COUNT \
		and served_today >= 0 and served_today <= MAX_COUNT \
		and lost_today >= 0 and lost_today <= MAX_COUNT \
		and is_finite(reputation) and reputation >= 0.0 and reputation <= 5.0 \
		and operating_profit >= -MAX_PROFIT and operating_profit <= MAX_PROFIT \
		and owner_level >= 1 and owner_level <= MAX_COUNT \
		and staff_count >= 0 and staff_count <= MAX_COUNT
