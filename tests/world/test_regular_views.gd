extends TestCase
## Live native rigs, retained indicator nodes and UI snapshots; presentation
## never advances the sim or consumes its random stream.

var _view: ShopView


func after_each() -> void:
	if is_instance_valid(_view):
		_view.free()


func test_fixed_model_clothing_and_star_follow_drawn_person_without_draws() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = world
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 166
	var guest: CustomerAgent = CustomerAgent.new(sim, random)
	world.add_agent(guest)
	guest.regular_profile = _profile()
	guest.regular_arrival_tick = 0
	guest.cell = Vector2i(1, 1)
	guest.state = CustomerAgent.State.QUEUED
	guest.queue_patience = 100
	var before: int = random.state
	var packed: PackedScene = load("res://src/world/shop_view.tscn") as PackedScene
	_view = packed.instantiate() as ShopView
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(_view)
	_view.set_process(false)
	_view.show_world(world)
	var body: PersonView = _view.agent_nodes[guest.id] as PersonView
	var icon: RegularGuestIndicator = _view.regular_nodes[guest.id]
	assert_eq(body.model_name(), guest.regular_profile.model_id)
	assert_eq(body.regular_tint(), &"sage")
	assert_eq(icon.get_parent(), body)
	assert_eq(icon.star.texture, RegularGuestIndicator.STAR)
	assert_eq(icon.name_label.text, "Rosa")
	assert_eq(icon.greeting.text, "The usual!")
	assert_true(icon.greeting.visible)
	assert_true(icon.position.y > _view.mood_nodes[guest.id].position.y)
	var body_mesh: MeshInstance3D = body._model.find_child("body-mesh", true, false) as MeshInstance3D
	var head_mesh: MeshInstance3D = body._model.find_child("head-mesh", true, false) as MeshInstance3D
	assert_not_null(body_mesh.get_surface_override_material(0))
	assert_null(head_mesh.get_surface_override_material(0), "head and hair keep the kit material")
	var source: StandardMaterial3D = body_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var material: StandardMaterial3D = body_mesh.get_surface_override_material(0) as StandardMaterial3D
	var tinted: Image = material.albedo_texture.get_image()
	var original: Image = source.albedo_texture.get_image()
	assert_ne(material, source, "regular tint never changes the shared kit material")
	assert_eq(tinted.get_pixel(336, 388), original.get_pixel(336, 388), "light skin ramp stays untouched")
	assert_eq(tinted.get_pixel(400, 388), original.get_pixel(400, 388), "dark skin ramp stays untouched")
	assert_ne(tinted.get_pixel(368, 260), original.get_pixel(368, 260), "authored shirt ramp changes")
	assert_false(body._cap.visible, "a fixed shirt tint needs no second hat through the bun")
	var original_model: Object = body._model
	world.now = 2 * SimClock.TICKS_PER_SECOND
	for frame: int in 3:
		_view._process(0.1)
	assert_eq(_view.regular_nodes[guest.id], icon)
	assert_eq(body._model, original_model, "fixed appearance does not rebuild each frame")
	assert_false(icon.greeting.visible)
	assert_eq(random.state, before)
	assert_eq(guest.state, CustomerAgent.State.QUEUED)
	guest.regular_profile = null
	_view._process(0.0)
	assert_false(_view.regular_nodes.has(guest.id))
	assert_false(is_instance_valid(icon))
	assert_eq(body.model_name(), PersonPresentation.model_for(&"customer", guest.id))
	var plain_body: MeshInstance3D = body._model.find_child("body-mesh", true, false) as MeshInstance3D
	assert_null(plain_body.get_surface_override_material(0), "removing a regular restores the imported outfit")
	_view.show_world(null)
	assert_true(_view.regular_nodes.is_empty())


func test_all_authored_regular_looks_use_the_fixed_model_and_private_clothing_tint() -> void:
	var tuning: RegularsTuning = load("res://data/regulars/cast.tres") as RegularsTuning
	var packed: PackedScene = load("res://assets/people/person.tscn") as PackedScene
	var person: PersonView = packed.instantiate() as PersonView
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(person)
	for index: int in tuning.model_ids.size():
		var model: StringName = tuning.model_ids[index]
		var tint: StringName = tuning.tint_ids[index % tuning.tint_ids.size()]
		assert_true(person.set_regular_look(model, tint))
		assert_true(person.set_look(&"customer", 1000 + index))
		assert_eq(person.model_name(), model)
		assert_eq(person.regular_tint(), tint)
		assert_true(person.set_pose(false, false, false, false))
	assert_false(person.set_regular_look(&"unapproved_model", &"sage"))
	assert_false(person.set_regular_look(tuning.model_ids[0], &"unapproved_tint"))
	person.free()


func test_inspect_names_favourite_and_feelings_use_plain_text_without_ids() -> void:
	var world: SimWorld = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	var sim: RestaurantSim = RestaurantSim.new()
	sim.world = world
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 166
	var guest: CustomerAgent = CustomerAgent.new(sim, random)
	world.add_agent(guest)
	guest.regular_profile = _profile()
	guest.regular_favourite_label = "Tomato soup"
	var packed: PackedScene = load("res://src/ui/inspect_panel.tscn") as PackedScene
	var panel: InspectPanel = packed.instantiate() as InspectPanel
	panel.bind_world(world)
	panel.show_agent(guest.id)
	assert_eq((panel.get_node("%Title") as Label).text, "Rosa (Regular)")
	var details: String = (panel.get_node("%Details") as Label).text
	assert_true(details.contains("Favourite dish: Tomato soup"))
	assert_true(details.contains("Favourite seat: column 3, row 4"))
	assert_true(details.contains("Loves coming here"))
	assert_false(details.contains("tomato_soup"))
	assert_false(details.contains("#"))
	guest.regular_profile.mood = 0.2
	panel.refresh()
	assert_true((panel.get_node("%Details") as Label).text.contains("May stop coming"))
	panel.free()


func test_menu_favourite_marks_refresh_without_editing_the_menu() -> void:
	var soup: RecipeDef = load("res://data/recipes/tomato_soup.tres") as RecipeDef
	var menu: MenuSettings = MenuSettings.new([soup])
	var packed: PackedScene = load("res://src/ui/menu_panel.tscn") as PackedScene
	var panel: MenuPanel = packed.instantiate() as MenuPanel
	panel.bind_menu(menu)
	var before: Dictionary = menu.to_dict()
	panel.set_regular_favourites([&"tomato_soup"])
	assert_eq(panel._tree_items[&"tomato_soup"].get_tooltip_text(0), RegularText.FAVOURITE)
	assert_eq(panel._tree_items[&"tomato_soup"].get_icon(0), IconCatalogue.texture_for(&"reputation"))
	assert_true(panel._quality_label.text.contains(RegularText.FAVOURITE))
	panel.set_regular_favourites([])
	assert_null(panel._tree_items[&"tomato_soup"].get_icon(0))
	assert_false(panel._quality_label.text.contains(RegularText.FAVOURITE))
	assert_eq(menu.to_dict(), before)
	panel.free()


func test_report_shows_names_for_visits_new_regulars_and_departures_then_clears() -> void:
	var cast: RegularCast = RegularCast.new()
	cast.profiles.append(_profile())
	cast.visited_today = [7]
	cast.new_today = [7]
	cast.left_today = [7]
	var before: Dictionary = cast.profiles[0].to_dict()
	var day: DayReport = DayReport.new()
	day.regulars_lines = RegularText.report_lines(cast)
	assert_eq(day.regulars_lines, ["Came: Rosa", "New regulars: Rosa", "Rosa hasn't been back"])
	var packed: PackedScene = load("res://src/ui/evening_report.tscn") as PackedScene
	var report: Control = packed.instantiate() as Control
	report.call("show_report", day)
	var summary: Label = report.get("regulars_summary") as Label
	assert_true(summary.visible)
	assert_eq(summary.text, "Regulars: Came: Rosa; New regulars: Rosa; Rosa hasn't been back")
	assert_eq(summary.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	report.call("show_report", DayReport.new())
	assert_false(summary.visible)
	assert_eq(cast.profiles[0].to_dict(), before)
	report.free()


func _profile() -> RegularProfile:
	var profile: RegularProfile = RegularProfile.new()
	profile.id = 7
	profile.display_name = "Rosa"
	profile.model_id = &"character-female-c"
	profile.tint_id = &"sage"
	profile.greeting = "The usual!"
	profile.favourite_dish = &"tomato_soup"
	profile.favourite_seat = Vector2i(2, 3)
	profile.mood = 0.9
	return profile
