class_name WeeklyChallengeText
extends RefCounted
## Shared player wording for the weekly goal's remaining calendar days.


static func days_left(days: int) -> String:
	return "1 day left" if days == 1 else "%d days left" % days
