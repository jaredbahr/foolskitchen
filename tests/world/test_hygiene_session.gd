extends TestCase
## Native Main wiring, paused updates and tint lifecycle, without autosaving.

var _main: Node3D
var _providers: Dictionary[String, Dictionary]
var _window_size: Vector2i


func before_each() -> void:
	_providers = SaveSystem._providers.duplicate(true)
	_window_size = (Engine.get_main_loop() as SceneTree).root.size
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
	_main = null
	(Engine.get_main_loop() as SceneTree).root.content_scale_factor = 1.0
	(Engine.get_main_loop() as SceneTree).root.size = _window_size
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
	# Keep the actual toilet/work spot clear of all current dining seats.
	sim.kitchen.mark_table_dirty(table.id)
	assert_true(sim.cleanliness.add_use_spot(Vector2i(4, 11)))
	assert_true(_main.call("shop_rooms", {Vector2i(4, 11): SimGrid.Room.RESTROOM,
		Vector2i(4, 12): SimGrid.Room.RESTROOM} as Dictionary[Vector2i, int]))
	assert_true(_main.call("shop_buy", &"toilet", Vector2i(4, 12), 0))
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
	assert_eq(preview.displayed_hygiene_cells().count(Vector2i(4, 11)), 1)
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
	sim.cleanliness.clear_spot(Vector2i(4, 11))
	_main.call("refresh_presentation")
	assert_true(catalogue.hygiene_summary.text.contains("Restroom: 0 toilets need a tidy · 0 upkeep spots"))
	assert_false(preview.displayed_hygiene_cells().has(Vector2i(4, 11)))
	assert_true(_main.call("set_build_active", false))
	assert_false(catalogue.hygiene_panel.visible)
	assert_null(preview.hygiene_mesh)
	assert_true(preview.displayed_hygiene_cells().is_empty())
	assert_true(_main.call("set_build_active", true))
	assert_not_null(preview.hygiene_mesh, "reopening Build restores the chosen overview")
	catalogue.set_hygiene_enabled(false)
	assert_null(preview.hygiene_mesh)


## The floating Hygiene card with the real HUD (#542): at 100%, 125% and 150%
## UI size of a 1600x900 window it covers none of the header, the build hints
## or the goals tracker, with four facts or with the fifth (inspection) one.
func test_hygiene_card_stays_off_the_hud_boxes_at_every_ui_scale() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	await tree.process_frame
	_main = (load("res://src/world/main.tscn") as PackedScene).instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	tree.root.add_child(_main)
	var catalogue: BuildCatalogue = _main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
	var hud: Node = _main.get_node("HUD")
	tree.root.size = Vector2i(1600, 900)
	assert_true(_main.call("set_build_active", true))
	catalogue.set_hygiene_enabled(true)
	var four: PackedStringArray = ["Dirty tables: 12", "Floor spots: 12",
		"Restroom: 2 toilets need a tidy · 12 upkeep spots", "Today's cleanliness: A bit messy"]
	var five: PackedStringArray = four.duplicate()
	five.append("Last inspection: B, day 12")
	var card: Control = catalogue.hygiene_panel
	var panel: Control = catalogue.get_node("Panel") as Control
	var scroll: ScrollContainer = catalogue.get_node("Panel/Margin/Rows/Scroll") as ScrollContainer
	var items: Control = scroll.get_node("Content/Items") as Control
	for scale_factor: float in [1.0, 1.25, 1.5]:
		tree.root.content_scale_factor = scale_factor
		for lines: PackedStringArray in [four, five]:
			# Main keeps its own lines fresh while it runs; hold these.
			_main.set_process(true)
			for frame: int in range(6):
				await tree.process_frame
			_main.set_process(false)
			catalogue.set_hygiene_lines(lines)
			await tree.process_frame
			var view: Rect2 = Rect2(Vector2.ZERO, catalogue.size)
			var context: String = "%d%% with %d facts: view=%s card=%s panel=%s" % [roundi(scale_factor * 100.0),
				lines.size(), view.size, card.get_global_rect(), panel.get_global_rect()]
			assert_true(card.is_visible_in_tree(), context)
			assert_true(view.grow(-11.5).encloses(card.get_global_rect()), "inside the view: " + context)
			if scale_factor < 1.5:
				assert_true(card.get_global_rect().end.y <= panel.get_global_rect().position.y, "above the panel: " + context)
			else:
				# About 40 px lie between the goals tracker and the panel at 150%:
				# the card is a short strip over the item cards at the panel's foot.
				assert_true(panel.get_global_rect().encloses(card.get_global_rect()), "over the panel's foot: " + context)
				assert_true(card.get_global_rect().position.y > catalogue.hygiene_button.get_global_rect().end.y \
					and card.size.y <= 36.0, "a short strip under the toolbars: " + context)
				assert_eq(catalogue.hygiene_summary.get_line_count(), 1, "one row of facts: " + context)
				assert_almost_eq(card.get_global_rect().position.x, items.get_global_rect().position.x)
				var summary: Label = catalogue.hygiene_summary
				var width: float = summary.get_theme_font("font").get_string_size(summary.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, summary.get_theme_font_size("font_size")).x
				assert_true(width <= summary.size.x + 0.5, "all facts fit at 1600x900: " + context)
			assert_false(card.get_global_rect().has_point(view.size * 0.5), "off the screen centre: " + context)
			assert_true(card.size.x >= card.get_combined_minimum_size().x - 0.5 \
				and card.size.y >= card.get_combined_minimum_size().y - 0.5, "no fact is cut off: " + context)
			for fact: String in lines:
				var full_text: String = catalogue.hygiene_summary.text if scale_factor < 1.5 \
					else catalogue.hygiene_summary.tooltip_text
				assert_true(full_text.contains(fact), "%s is available: %s" % [fact, context])
			var seen: int = 0
			for path: String in ["Top", "BuildHints", "OpeningWeek"]:
				var box: Control = hud.get_node_or_null(path) as Control
				if box == null or not box.is_visible_in_tree():
					continue
				seen += 1
				assert_false(card.get_global_rect().intersects(box.get_global_rect()),
					"the card covers HUD/%s %s: %s" % [path, box.get_global_rect(), context])
			assert_eq(seen, 3, "the header, build hints and goals tracker all show: " + context)
	assert_true(PanelScroll.overflows(scroll), "the catalogue can scroll")
	scroll.scroll_vertical = 0
	_wheel_over(tree.root, card.get_global_rect().get_center())
	assert_true(scroll.scroll_vertical > 0, "wheel over the strip scrolls the catalogue")

	_press_key(tree.root, KEY_F1)
	assert_true(_main.call("is_shortcuts_visible"), "F1 opens Shortcuts over Build")
	assert_true(card.visible, "opening Shortcuts keeps the Hygiene strip")
	_press_key(tree.root, KEY_ESCAPE)
	assert_false(_main.call("is_shortcuts_visible"), "first Escape closes Shortcuts")
	assert_true(card.visible, "first Escape leaves Hygiene visible")
	_press_key(tree.root, KEY_ESCAPE)
	assert_false(card.visible, "second Escape closes the Hygiene strip")
	assert_true(catalogue.hygiene_enabled, "dismissing the strip keeps Hygiene enabled")
	assert_true(_main.call("is_build_active"), "neither Escape leaves Build")
	tree.root.content_scale_factor = 1.0


func _wheel_over(window: Window, point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	window.push_input(motion, true)
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = point
	wheel.global_position = point
	wheel.factor = 1.0
	wheel.pressed = true
	window.push_input(wheel, true)


func _press_key(window: Window, code: Key) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	window.push_input(key, true)
