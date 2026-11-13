extends TestCase
## The Manager role (FK-087, #408 D2): drawn into candidate pools only from
## the manager tier, saved like any member, no floor work in the restaurant.

const TUNING: EconomyTuning = preload("res://data/balance/tier1_economy.tres")
const LAYOUT: ShopLayout = preload("res://data/layouts/tier1_hole_in_the_wall.tres")
## Twenty mornings of pools for seeds 1, 7 and 42, drawn by the code before
## managers existed. A pool below the manager tier must stay exactly this.
const PRE_MANAGER_POOLS: String = "5a11e59fd5cea7e5cd6cce7b4d9c6f0f4b3c3af22b01563588564510c781ec17"


func _pools(managers: bool) -> Array[String]:
	var out: Array[String] = []
	for seed: int in [1, 7, 42]:
		var roster: StaffRoster = StaffRoster.new(TUNING)
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = seed
		for day: int in range(1, 21):
			assert_true(roster.draw_candidates(day, random, managers))
			for member: StaffMember in roster.candidates():
				out.append("%s|%s|%d|%s|%d" % [member.display_name, member.role, member.skill,
					member.trait_id, member.wage])
		out.append(str(random.state))
	return out


func _manager(id: StringName = &"boss", skill: int = 4) -> StaffMember:
	var member: StaffMember = StaffMember.new()
	member.id = id
	member.display_name = "Morgan"
	member.role = StaffMember.MANAGER
	member.skill = skill
	member.wage = TUNING.staff_wage(StaffMember.MANAGER, skill)
	return member


func test_pools_below_the_manager_tier_are_unchanged() -> void:
	var pools: Array[String] = _pools(false)
	assert_eq(JSON.stringify(pools).sha256_text(), PRE_MANAGER_POOLS)
	for line: String in pools:
		assert_false(line.contains("|manager|"), "no manager below the tier")


func test_pools_at_the_manager_tier_offer_managers() -> void:
	var pools: Array[String] = _pools(true)
	var managers: int = 0
	for line: String in pools:
		if line.contains("|manager|"):
			managers += 1
	assert_true(managers > 0, "managers are drawn at the tier")
	# One draw per candidate either way: the hiring stream moves the same.
	var plain: Array[String] = _pools(false)
	assert_eq(pools.size(), plain.size())
	for index: int in [60, 121, 182]:
		assert_eq(pools[index], plain[index], "the stream ends in the same state")


func test_a_manager_round_trips_and_can_be_let_go() -> void:
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var data: Dictionary = roster.to_dict()
	(data["members"] as Array).append(_manager().to_dict())
	assert_true(roster.from_dict(JSON.parse_string(JSON.stringify(data))))
	var found: StaffMember = roster.members()[2]
	assert_eq(found.role, StaffMember.MANAGER)
	assert_eq(found.skill, 4)
	assert_eq(found.growth_state().skill_level(&"service"), 4, "a manager's skill is service")
	assert_eq(StaffRoster._role_name(StaffMember.MANAGER), "Manager")
	assert_false(found.priority_state().set_priority(&"serving", StaffJobPriorities.Level.LOW),
		"a manager has no floor jobs")
	assert_true(roster.can_let_go(&"boss"))
	assert_true(roster.let_go(&"boss"))
	assert_eq(roster.members().size(), 2)


func test_a_manager_gets_no_worker_in_the_restaurant() -> void:
	var errors: Array[String] = []
	var roster: StaffRoster = StaffRoster.new(TUNING)
	var people: Array[StaffMember] = roster.members()
	people.append(_manager())
	var content: ContentDB = ContentDB.new()
	assert_true(content.load_all().is_empty())
	var sim: RestaurantSim = RestaurantSim.create(LAYOUT, content, 1, errors,
		null, false, false, people)
	assert_eq(errors, [] as Array[String])
	var workers: int = 0
	for agent: SimAgent in sim.world.all_agents():
		if agent is StaffAgent and not agent is OwnerAgent:
			assert_ne((agent as StaffAgent).member_id, &"boss", "no worker for the manager")
			workers += 1
	assert_eq(workers, 2, "the cook and the server")
	# Letting the manager go (or keeping them) leaves the floor workers alone.
	assert_true(sim.set_staff_roster(roster.members()))
	assert_eq(sim.world.agents.size(), 3, "cook, server and owner")
	# A manager does not stand in for a cook and a server: managers alone
	# install (a site still hiring, #464) but put nobody on the floor, and
	# such a roster is not staffed, so the site cannot open.
	var managers_only: Array[StaffMember] = [_manager(&"a"), _manager(&"b")]
	assert_true(sim.set_staff_roster(managers_only))
	for agent: SimAgent in sim.world.all_agents():
		assert_true(not agent is StaffAgent or agent is OwnerAgent, "no floor worker for a manager")
	var unstaffed: StaffRoster = StaffRoster.new(TUNING)
	var data: Dictionary = unstaffed.to_dict()
	data["members"] = [_manager(&"a").to_dict()]
	assert_true(unstaffed.from_dict(data))
	assert_false(unstaffed.is_staffed())
