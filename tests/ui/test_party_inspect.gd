extends TestCase
## Read-only native inspect text; no scene tree, ticks or RNG draws needed.

const PANEL: PackedScene = preload("res://src/ui/inspect_panel.tscn")


func test_inspector_shows_the_shared_party_size_without_drawing_or_advancing() -> void:
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	var randoms: Array[RandomNumberGenerator] = []
	for seed_value: int in [1, 7, 42]:
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = seed_value
		randoms.append(random)
	var party: Party = sim.add_party(Vector2i.ONE, randoms)
	var panel: InspectPanel = PANEL.instantiate() as InspectPanel
	panel.bind_world(sim.world)
	for guest: CustomerAgent in sim.customers():
		var before: int = guest.rng.state
		panel.show_agent(guest.id)
		panel.refresh()
		var details: Label = panel.get_node("Panel/Rows/Details") as Label
		assert_true(details.text.contains("Party of 3"))
		assert_eq(guest.party, party)
		assert_eq(guest.rng.state, before)
		assert_eq(sim.world.now, 0)
	panel.free()
