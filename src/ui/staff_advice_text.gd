class_name StaffAdviceText
extends RefCounted
## Shared words and display rounding for the last service's team activity.

const TEAM_HEADING: String = "Your team"
const LAST_SERVICE: String = "Last service · Day %d"
const ROLES: Array[StringName] = [&"cook", &"server", &"cleaner", &"owner"]
const ROLE_NODES: Array[StringName] = [
	&"CookActivity", &"ServerActivity", &"CleanerActivity", &"OwnerActivity",
]
const ROLE_LABELS: Dictionary = {
	&"cook": "Cooks",
	&"server": "Servers",
	&"cleaner": "Cleaners",
	&"owner": "Owner",
}
const BUSY_HOURS: String = "%s: busy %d%% of open hours"
const OWNER_BUSY_HOURS: String = "%s: busy %d%% of assigned open hours"
const ADVICE: Dictionary = {
	&"cook": "Your cooks are busy and guests are leaving after waiting. Consider hiring a second cook before adding tables.",
	&"server": "Your servers are busy and guests are leaving after waiting. Consider hiring another server before adding tables.",
	&"tables": "Your team has time to spare. Add tables to make room for more guests.",
	&"keeping_up": "Your team is keeping up.",
}


static func role_line(role: StringName, summary: Dictionary) -> String:
	var clean: Dictionary = StaffActivity.public_snapshot(summary)
	if clean.is_empty() or not ROLE_LABELS.has(role):
		return ""
	var roles: Dictionary = clean["roles"]
	if not roles.has(String(role)):
		return ""
	var activity: Dictionary = roles[String(role)]
	var percent: int = clampi(roundi(100.0 * float(activity["busy_ticks"])
		/ float(activity["open_ticks"])), 0, 100)
	return (OWNER_BUSY_HOURS if role == &"owner" else BUSY_HOURS) % [ROLE_LABELS[role], percent]


static func last_service_heading(summary: Dictionary) -> String:
	var clean: Dictionary = StaffActivity.public_snapshot(summary)
	return "" if clean.is_empty() else LAST_SERVICE % int(clean["day"])


static func recommendation(id: StringName) -> String:
	return String(ADVICE.get(id, ""))
