class_name StaffTransfer
extends RefCounted
## Sending an employee from the active restaurant to another of the owner's
## sites (FK-087 part 5, #473). Pure: two rosters in, both changed on success.
## Main owns the morning-only guard, the site book, live agents and saving.
##
## The rules:
## - The departing site keeps its last cook and server: the same rule as
##   letting someone go (StaffRoster.can_let_go).
## - The destination must have room (StaffRoster.CAPACITY).
## - Managers: what makes a site run while the owner is away is its book
##   row's manager (SiteBook.manager, valid when that id is a Manager on its
##   staff: AwaySites.manager_skill). A Manager may move only to a site
##   without such a running manager (`destination_managed` false), and on
##   arrival runs it (main sets them on the destination's row). Leaving
##   clears them as the departing site's manager. A Manager hired at a site
##   takes its row when the owner leaves it (main.gd switch_site,
##   AwaySites.best_manager).
## - The person keeps everything: skill, trait, wage, mood, raise history,
##   job priorities and lifetime work. Only their id may change: ids are
##   unique within one roster, so a clash at the destination gets a suffix.
## - No hiring fee and no severance: no money moves.

enum Refusal { NONE, UNKNOWN, LAST_OF_ROLE, FULL, HAS_MANAGER }


## Why `member_id` cannot move from `source` to `destination`, or NONE.
## Checked in this order: unknown person, last cook or server, a manager to
## a site that already has a running manager (`destination_managed`), a full
## destination.
static func refusal(source: StaffRoster, member_id: StringName, destination: StaffRoster,
		destination_managed: bool = false) -> Refusal:
	var member: StaffMember = _member(source, member_id)
	if member == null or destination == null:
		return Refusal.UNKNOWN
	if not source.can_let_go(member_id):
		return Refusal.LAST_OF_ROLE
	if member.role == StaffMember.MANAGER and destination_managed:
		return Refusal.HAS_MANAGER
	if destination.members().size() >= StaffRoster.CAPACITY:
		return Refusal.FULL
	return Refusal.NONE


## True when someone on the roster has the Manager role.
static func has_manager(roster: StaffRoster) -> bool:
	for member: StaffMember in roster.members():
		if member.role == StaffMember.MANAGER:
			return true
	return false


## Moves `member_id` from `source` to `destination`. Returns the person's id
## at the destination (usually the same), or &"" and changes nothing when
## refused.
static func move(source: StaffRoster, member_id: StringName, destination: StaffRoster,
		destination_managed: bool = false) -> StringName:
	if refusal(source, member_id, destination, destination_managed) != Refusal.NONE:
		return &""
	var member: StaffMember = _member(source, member_id)
	member.id = arrival_id(destination, member.id)
	if not destination.accept_transfer(member):
		return &""
	if not source.let_go(member_id):
		# Not expected (refusal checked can_let_go); undo the arrival.
		var data: Dictionary = destination.to_dict()
		(data["members"] as Array).pop_back()
		destination.from_dict(data)
		return &""
	return member.id


## `id`, or the first of `id_2`, `id_3`... not used on `roster`.
static func arrival_id(roster: StaffRoster, id: StringName) -> StringName:
	if not roster.has_id(id):
		return id
	var number: int = 2
	while roster.has_id(StringName("%s_%d" % [id, number])):
		number += 1
	return StringName("%s_%d" % [id, number])


static func _member(roster: StaffRoster, member_id: StringName) -> StaffMember:
	if roster == null:
		return null
	for member: StaffMember in roster.members():
		if member.id == member_id:
			return member
	return null
