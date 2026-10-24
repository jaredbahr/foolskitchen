class_name ProbeSetups
extends RefCounted
## Explicit morning scenarios for the manual balance probe. Add new scenarios
## here so the runner and its output format stay unchanged.


static func names() -> Array[String]:
	return ["default", "extra_cook", "extra_server", "owner_kitchen", "owner_floor"]


static func apply(name: String, main: Node, extra_cook_skill: int = 3) -> bool:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if sim == null or sim.world.clock.phase != SimClock.Phase.MORNING:
		return false
	match name:
		"default":
			return true
		"extra_cook":
			return _add_staff(main, &"cook", extra_cook_skill)
		"extra_server":
			return _add_staff(main, &"server", 3)
		"owner_kitchen":
			return sim.assign_owner(&"kitchen")
		"owner_floor":
			return sim.assign_owner(&"floor")
	return false


static func _add_staff(main: Node, role: StringName, skill: int) -> bool:
	if skill < 1 or skill > 5:
		return false
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var roster: StaffRoster = main.get("staff_roster") as StaffRoster
	if sim == null or roster == null:
		return false
	var snapshot: Dictionary = roster.to_dict()
	var members: Array = snapshot["members"]
	var member: StaffMember = StaffMember.new()
	member.id = StringName("probe_extra_%s" % String(role))
	member.display_name = "Extra %s" % String(role)
	member.role = role
	member.skill = skill
	member.wage = sim.pricing_tuning.staff_wage(role, skill)
	member.trait_id = &"steady"
	members.append(member.to_dict())
	snapshot["members"] = members
	return roster.from_dict(snapshot) and sim.set_staff_roster(roster.members())
