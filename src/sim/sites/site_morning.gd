class_name SiteMorning
extends RefCounted
## What the morning site card (FK-087, #464) shows for each of the owner's
## sites: pure reads of the books and a site's saved staff. Words live in
## SiteCard.

## Ledger categories that count as a site's takings: money taken from guests
## where the owner worked, or by its manager while the owner was away.
const TAKINGS: Array[StringName] = [Ledger.SALE, Ledger.TIP, Ledger.AWAY_SITE_INCOME]


## A site's takings on `day` from its own ledger entries (0 when it made
## none, or the day has been pruned).
static func takings(ledger: Ledger, day: int, site: StringName) -> int:
	if ledger == null or day < 1 or not Ledger.is_valid_site(site):
		return 0
	var total: int = 0
	for entry: Dictionary in ledger.entries_for_day(day, site):
		if TAKINGS.has(StringName(entry["category"])):
			total += int(entry["amount"])
	return total


## The display name of `member_id` in a saved "staff" section, or "".
static func manager_name(staff: Dictionary, member_id: StringName) -> String:
	if member_id.is_empty() or staff.is_empty():
		return ""
	var roster: StaffRoster = StaffRoster.new()
	if not roster.from_dict(staff):
		return ""
	return member_name(roster.members(), member_id)


## The display name of `member_id` among `members`, or "".
static func member_name(members: Array[StaffMember], member_id: StringName) -> String:
	if member_id.is_empty():
		return ""
	for member: StaffMember in members:
		if member.id == member_id:
			return member.display_name
	return ""
