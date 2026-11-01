extends TestCase
## Native Main wiring, paused updates and tint lifecycle, without autosaving.

var _main: Node3D
var _providers: Dictionary[String, Dictionary]


func before_each() -> void:
	_providers = SaveSystem._providers.duplicate(true)
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_toggle_shows_actual_problem_cells_updates_after_cleaning_and_clears_outside_build() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	_main = (load("res://src/world/main.tscn") as PackedScene).instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.set_process(false)
	var sim: RestaurantSim = _main.get("sim") as RestaurantSim
	var world: SimWorld = sim.world
	var table: PlacedItem = ShopBuilder.items_with_def(world, &"table_2")[0]
	sim.kitchen.mark_table_dirty(table.id)
	assert_true(sim.cleanliness.add_use_spot(Vector2i(2, 8)))
	assert_true(_main.call("shop_rooms", {Vector2i(2, 8): SimGrid.Room.RESTROOM,
		Vector2i(2, 9): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int]))
	assert_true(_main.call("shop_buy", &"toilet", Vector2i(2, 9), 0))
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	var preview: BuildPreview = _main.get_node("BuildPreview") as BuildPreview
	var random: Dictionary = GameState.call("_capture_save")
	var ledger: Dictionary = Economy.ledger.to_dict()
	var providers: Array[String] = []
	providers.assign(SaveSystem._providers.keys())
	assert_true(_main.call("set_build_active", true))
	assert_null(preview.hygiene_mesh)
	catalogue.set_hygiene_enabled(true)
	assert_true(catalogue.hygiene_panel.visible)
	assert_true(catalogue.hygiene_summary.text.contains("Dirty tables: 1"))
	assert_true(catalogue.hygiene_summary.text.contains("Restroom: 1 toilet needs a tidy · 1 upkeep spot"))
	assert_not_null(preview.hygiene_mesh)
	assert_true(preview.displayed_hygiene_cells().has(table.cells[0]))
	assert_eq(preview.displayed_hygiene_cells().count(Vector2i(2, 8)), 1)
	var material: StandardMaterial3D = preview.hygiene_mesh.material_override as StandardMaterial3D
	assert_almost_eq(material.albedo_color.a, BuildPreview.HYGIENE_ALPHA)
	assert_almost_eq(material.albedo_color.r, BuildPreview.HYGIENE_SWATCH.color.r)
	var original_mesh: MeshInstance3D = preview.hygiene_mesh
	_main.call("refresh_presentation")
	assert_eq(preview.hygiene_mesh, original_mesh, "unchanged snapshots do not rebuild native geometry every frame")
	assert_eq(GameState.call("_capture_save"), random)
	assert_eq(Economy.ledger.to_dict(), ledger)
	assert_eq(SaveSystem._providers.keys(), providers)
	assert_eq(world.now, 0)
	assert_true(_main.call("set_paint_active", true))
	assert_false(catalogue.hygiene_button.visible)
	assert_false(catalogue.hygiene_panel.visible)
	assert_null(preview.hygiene_mesh, "Paint does not keep the Build-only overlay")
	assert_true(_main.call("set_build_active", true))
	assert_true(catalogue.hygiene_button.visible)
	assert_true(catalogue.hygiene_panel.visible)
	assert_not_null(preview.hygiene_mesh, "returning from Paint restores the chosen overview")
	sim.cleanliness.clear_spot(Vector2i(2, 8))
	_main.call("refresh_presentation")
	assert_true(catalogue.hygiene_summary.text.contains("Restroom: 0 toilets need a tidy · 0 upkeep spots"))
	assert_false(preview.displayed_hygiene_cells().has(Vector2i(2, 8)))
	assert_true(_main.call("set_build_active", false))
	assert_false(catalogue.hygiene_panel.visible)
	assert_null(preview.hygiene_mesh)
	assert_true(preview.displayed_hygiene_cells().is_empty())
	assert_true(_main.call("set_build_active", true))
	assert_not_null(preview.hygiene_mesh, "reopening Build restores the chosen overview")
	catalogue.set_hygiene_enabled(false)
	assert_null(preview.hygiene_mesh)
