extends TestCase
## Diner furniture stays on its real geometry and on the shared seat grid.

const SHARED_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")


func test_diner_seats_have_diner_unlocks_and_bench_compatible_seats() -> void:
	var booth: ItemDef = load("res://data/items/diner_booth.tres") as ItemDef
	var stool: ItemDef = load("res://data/items/diner_stool.tres") as ItemDef
	assert_not_null(booth)
	assert_not_null(stool)
	if booth == null or stool == null:
		return
	assert_eq(booth.category, ItemDef.Category.CHAIR)
	assert_eq(booth.footprint, Vector2i(2, 1))
	assert_eq(booth.seat_cells, [Vector2i(0, 0), Vector2i(1, 0)])
	assert_eq(booth.capacity, 2)
	assert_almost_eq(booth.seated_forward_offset, 0.05, 0.000001,
		"booth uses only the supported five-centimetre seated adjustment")
	assert_eq(booth.unlock_level, 3)
	assert_true(booth.theme_tags.has(&"diner"))
	assert_eq(stool.category, ItemDef.Category.CHAIR)
	assert_eq(stool.footprint, Vector2i.ONE)
	assert_eq(stool.seat_cells, [Vector2i.ZERO])
	assert_eq(stool.capacity, 1)
	assert_eq(stool.unlock_level, 3)
	assert_true(stool.theme_tags.has(&"diner"))


func test_diner_seats_remain_walkable_in_every_existing_rotation() -> void:
	var definitions: Array[ItemDef] = [
		load("res://data/items/diner_booth.tres") as ItemDef,
		load("res://data/items/diner_stool.tres") as ItemDef,
	]
	for definition: ItemDef in definitions:
		assert_not_null(definition)
		if definition == null:
			continue
		for turns: int in range(4):
			var grid: SimGrid = SimGrid.new(Vector2i(7, 7))
			var placed: PlacedItem = grid.place_def(definition, Vector2i(2, 2), turns)
			assert_not_null(placed, "%s fits at rotation %d" % [definition.id, turns])
			if placed == null:
				continue
			assert_eq(placed.seat_cells.size(), definition.seat_cells.size())
			for seat: Vector2i in placed.seat_cells:
				assert_true(grid.is_walkable(seat), "%s seat stays walkable" % definition.id)


func test_diner_models_fit_their_cells_and_use_the_named_kit_materials() -> void:
	_assert_model_contract("diner_booth", Vector2i(2, 1), 0.4675, 0.24, [
		"carpet", "wood", "metal", "metalDark", "carpetWhite",
	])
	_assert_model_contract("diner_stool", Vector2i.ONE, 0.4785, 0.435, [
		"carpet", "wood", "metal", "metalDark",
	])


func test_booth_backrest_is_lower_and_set_back_without_shrinking_its_seat_cushions() -> void:
	var packed: PackedScene = load("res://assets/made/diner/diner_booth.glb") as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	var parts: Dictionary[String, AABB] = {}
	var traversal: Array[Dictionary] = [{"node": instance, "transform": Transform3D.IDENTITY}]
	while not traversal.is_empty():
		var current: Dictionary = traversal.pop_back()
		var node: Node = current["node"] as Node
		var accumulated: Transform3D = current["transform"]
		var spatial: Node3D = node as Node3D
		if spatial != null:
			accumulated *= spatial.transform
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var part_name: String = String(mesh.name).to_lower().replace(" ", "").replace("_", "")
			parts[part_name] = accumulated * mesh.get_aabb()
		for child: Node in node.get_children():
			traversal.append({"node": child, "transform": accumulated})
	assert_eq(parts.size(), 7, "booth keeps its original seven upholstered parts")
	assert_true(parts.has("tallbackshell"))
	if parts.has("tallbackshell"):
		var shell: AABB = parts["tallbackshell"]
		assert_almost_eq(shell.end.y, 0.425, 0.0001, "white shell stays below the rear hair region")
		assert_almost_eq(shell.position.z, 0.189, 0.0001, "shell is set back after export centring")
		assert_almost_eq(shell.size.z, 0.06, 0.0001, "shell retains a chunky bevelled thickness")
	for side: String in ["left", "right"]:
		var seat_name: String = side + "seatcushion"
		var back_name: String = side + "backcushion"
		assert_true(parts.has(seat_name))
		assert_true(parts.has(back_name))
		if parts.has(seat_name):
			var seat: AABB = parts[seat_name]
			assert_almost_eq(seat.size.x, 0.435, 0.0001)
			assert_almost_eq(seat.size.z, 0.29, 0.0001)
			assert_almost_eq(seat.end.y, 0.24, 0.0001, "original cushion height and support area remain")
		if parts.has(back_name):
			var back: AABB = parts[back_name]
			assert_almost_eq(back.end.y, 0.405, 0.0001)
			assert_almost_eq(back.position.z, 0.154, 0.0001)
			assert_almost_eq(back.size.z, 0.035, 0.0001, "back cushions retain bevelled padding behind the hair")
	instance.free()


func test_wall_model_wrappers_keep_bounded_geometry_and_chalkboard_uses_theme_text() -> void:
	var cases: Array[Dictionary] = [
		{"id": "diner_open_sign", "height": 0.41525, "materials": ["metalDark", "metal", "carpet_emissive"]},
		{"id": "diner_chalkboard", "height": 0.616, "materials": ["metalDark", "wood"]},
		{"id": "diner_wall_art_a", "height": 0.517, "materials": ["carpetWhite", "wood", "carpet", "metal"]},
		{"id": "diner_wall_art_b", "height": 0.517, "materials": ["carpetWhite", "wood", "carpet", "metalDark"]},
	]
	for entry: Dictionary in cases:
		var item_id: String = entry["id"]
		var packed: PackedScene = load("res://assets/props/%s.tscn" % item_id) as PackedScene
		assert_not_null(packed, "%s staged wall wrapper loads" % item_id)
		if packed == null:
			continue
		var instance: Node = packed.instantiate()
		var prop: PropView = instance as PropView
		assert_not_null(prop, "%s wrapper uses PropView" % item_id)
		if prop == null:
			instance.free()
			continue
		# Exercise the native label and prop through their real scene-tree lifecycle.
		(Engine.get_main_loop() as SceneTree).root.add_child(instance)
		prop.prepare()
		assert_eq(prop.footprint, Vector2i(2, 1), "%s covers its two-cell wall width" % item_id)
		var bounds: AABB = prop.get_combined_aabb()
		assert_true(bounds.size.x > 0.0 and bounds.size.x <= 1.05,
			"%s width %.3f fits the two-cell allowance" % [item_id, bounds.size.x])
		assert_true(bounds.size.z > 0.0 and bounds.size.z < 0.25,
			"%s depth %.3f remains wall-prop thin" % [item_id, bounds.size.z])
		assert_almost_eq(bounds.size.y, float(entry["height"]), 0.015,
			"%s retains its imported height under ArtScale" % item_id)
		assert_true(bounds.position.y >= 0.6 and bounds.end.y <= ArtScale.WALL_HEIGHT,
			"%s sits inside the existing wall height" % item_id)
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(prop, meshes)
		var triangles: int = 0
		var found_materials: Dictionary[String, bool] = {}
		var lights: Array[Light3D] = []
		_collect_lights(prop, lights)
		assert_true(lights.is_empty(), "%s geometry does not add a real light" % item_id)
		for mesh_instance: MeshInstance3D in meshes:
			if mesh_instance.mesh == null:
				continue
			triangles += int(mesh_instance.mesh.get_faces().size() / 3)
			for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
				var material: Material = mesh_instance.mesh.surface_get_material(surface_index)
				assert_not_null(material, "%s wall surface keeps its source material" % item_id)
				if material == null:
					continue
				var material_name: String = material.resource_name
				assert_true((entry["materials"] as Array).has(material_name),
					"%s material '%s' comes from the referenced kit" % [item_id, material_name])
				found_materials[material_name] = true
		assert_true(triangles > 0 and triangles < 300,
			"%s has %d imported triangles below the wall-prop limit" % [item_id, triangles])
		for material_name: String in entry["materials"]:
			assert_true(found_materials.has(material_name), "%s uses %s" % [item_id, material_name])
		if item_id == "diner_chalkboard":
			var label: Label3D = prop.get_node_or_null("WallMount/MenuText") as Label3D
			assert_not_null(label, "chalkboard lettering remains native 3D text")
			if label != null:
				var shared_font: Font = SHARED_THEME.default_font
				if shared_font == null:
					shared_font = ThemeDB.fallback_font
				assert_eq(label.font, shared_font, "chalkboard uses the shared theme's actual font resource")
				assert_eq(label.text.split("\n").size(), 3, "chalkboard menu keeps three real text lines")
				assert_false(label.text.contains("$"), "decorative text never advertises prices disconnected from Menu")
				var text_front: Vector3 = label.transform.basis * Vector3.BACK
				var text_up: Vector3 = label.transform.basis * Vector3.UP
				assert_almost_eq(text_front.x, 0.0)
				assert_almost_eq(text_front.y, 0.0)
				assert_almost_eq(text_front.z, -1.0, 0.0001,
					"chalkboard text faces the wall wrapper's -Z front")
				assert_almost_eq(text_up.x, 0.0)
				assert_almost_eq(text_up.y, 1.0, 0.0001, "chalkboard text remains upright")
				assert_almost_eq(text_up.z, 0.0)
		instance.free()


func test_open_sign_named_glyph_bounds_read_open_from_its_negative_z_front() -> void:
	var packed: PackedScene = load("res://assets/made/diner/diner_open_sign.glb") as PackedScene
	assert_not_null(packed, "real OPEN GLB loads for the front-facing glyph check")
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(instance)
	var centers: Dictionary[String, float] = {"o": 0.0, "p": 0.0, "e": 0.0, "n": 0.0}
	var counts: Dictionary[String, int] = {"o": 0, "p": 0, "e": 0, "n": 0}
	var n_diagonal_mesh_count: int = 0
	var n_diagonal_vertices: PackedVector3Array = PackedVector3Array()
	var traversal: Array[Dictionary] = [{"node": instance, "transform": Transform3D.IDENTITY}]
	while not traversal.is_empty():
		var current: Dictionary = traversal.pop_back()
		var node: Node = current["node"] as Node
		var accumulated: Transform3D = current["transform"]
		var spatial: Node3D = node as Node3D
		if spatial != null:
			accumulated *= spatial.transform
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			var node_name: String = String(mesh_instance.name).to_lower()
			node_name = node_name.replace("_", "").replace("-", "").replace(" ", "")
			if node_name.begins_with("opensignnstroke2"):
				n_diagonal_mesh_count += 1
				for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
					var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
					if arrays.size() <= Mesh.ARRAY_VERTEX:
						continue
					var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					for vertex: Vector3 in surface_vertices:
						n_diagonal_vertices.append(accumulated * vertex)
			for letter: String in ["o", "p", "e", "n"]:
				if not node_name.begins_with("opensign%sstroke" % letter):
					continue
				var mesh_bounds: AABB = accumulated * mesh_instance.get_aabb()
				centers[letter] = float(centers[letter]) + mesh_bounds.get_center().x
				counts[letter] = int(counts[letter]) + 1
				break
		for child: Node in node.get_children():
			traversal.append({"node": child, "transform": accumulated})
	var expected_counts: Dictionary[String, int] = {"o": 4, "p": 4, "e": 4, "n": 3}
	for letter: String in ["o", "p", "e", "n"]:
		assert_eq(int(counts[letter]), int(expected_counts[letter]),
			"OPEN GLB retains every named %s stroke mesh" % letter.to_upper())
		if int(counts[letter]) > 0:
			centers[letter] = float(centers[letter]) / float(counts[letter])
	# From the -Z face, screen-right is local -X; therefore O must sit at a
	# greater local X than N for the physical sign to read left-to-right.
	assert_true(float(centers["o"]) > float(centers["p"]))
	assert_true(float(centers["p"]) > float(centers["e"]))
	assert_true(float(centers["e"]) > float(centers["n"]))
	assert_eq(n_diagonal_mesh_count, 1, "the named N diagonal is one real mesh")
	assert_true(n_diagonal_vertices.size() >= 6, "the N diagonal exposes actual surface vertices")
	if n_diagonal_vertices.size() >= 6:
		var mean_x: float = 0.0
		var mean_y: float = 0.0
		for vertex: Vector3 in n_diagonal_vertices:
			mean_x += vertex.x
			mean_y += vertex.y
		mean_x /= float(n_diagonal_vertices.size())
		mean_y /= float(n_diagonal_vertices.size())
		var native_xy_covariance: float = 0.0
		for vertex: Vector3 in n_diagonal_vertices:
			native_xy_covariance += (vertex.x - mean_x) * (vertex.y - mean_y)
		native_xy_covariance /= float(n_diagonal_vertices.size())
		# The GLB faces -Z: screen X is -native X, while screen up is native Y.
		# A Latin N diagonal falls from screen-left to screen-right, so its
		# screen-space covariance is negative and its native X/Y covariance positive.
		assert_true(native_xy_covariance > 0.000001,
			"N diagonal vertices slope correctly from the -Z front")
	tree.root.remove_child(instance)
	instance.free()


func _assert_model_contract(item_id: String, footprint: Vector2i, expected_height: float,
		expected_seat_y: float, allowed_material_names: Array[String]) -> void:
	var definition: ItemDef = load("res://data/items/%s.tres" % item_id) as ItemDef
	assert_not_null(definition, "%s definition loads" % item_id)
	if definition == null:
		return
	assert_eq(definition.footprint, footprint)
	assert_not_null(definition.view_scene, "%s has a view scene" % item_id)
	if definition.view_scene == null:
		return
	var instance: Node = definition.view_scene.instantiate()
	var prop: PropView = instance as PropView
	assert_not_null(prop, "%s view uses PropView" % item_id)
	if prop == null:
		instance.free()
		return
	prop.prepare()
	var bounds: AABB = prop.get_combined_aabb()
	var max_width: float = float(footprint.x) * GridMath.CELL_SIZE + 0.05
	var max_depth: float = float(footprint.y) * GridMath.CELL_SIZE + 0.05
	assert_true(bounds.size.x > 0.0 and bounds.size.x <= max_width,
		"%s width %.3f fits its %.3f m footprint allowance" % [item_id, bounds.size.x, max_width])
	assert_true(bounds.size.z > 0.0 and bounds.size.z <= max_depth,
		"%s depth %.3f fits its %.3f m footprint allowance" % [item_id, bounds.size.z, max_depth])
	assert_almost_eq(bounds.size.y, expected_height, 0.015,
		"%s height remains uniform under ArtScale" % item_id)
	assert_almost_eq(bounds.position.y, 0.0, 0.0001, "%s model is grounded" % item_id)
	assert_almost_eq(prop.seat_surface_y, expected_seat_y, 0.001,
		"%s uses the imported seat top" % item_id)
	assert_almost_eq(prop.seat_surface_height(), prop.seat_surface_y * ArtScale.FURNITURE_SCALE)
	assert_true(prop.body_material_names.has("carpet"), "%s paints only its cushion" % item_id)
	assert_true(definition.paintable, "%s exposes the supported cushion paint slot" % item_id)
	assert_true(prop.body_surface_count() > 0, "%s resolves its named paint surface" % item_id)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(prop, meshes)
	var triangles: int = 0
	var found_materials: Dictionary[String, bool] = {}
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		triangles += int(mesh_instance.mesh.get_faces().size() / 3)
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var material: Material = mesh_instance.mesh.surface_get_material(surface_index)
			assert_not_null(material, "%s surface has its authored material" % item_id)
			if material == null:
				continue
			var material_name: String = material.resource_name
			assert_true(allowed_material_names.has(material_name),
				"%s material '%s' remains in the Kenney palette" % [item_id, material_name])
			found_materials[material_name] = true
	assert_true(triangles > 0 and triangles <= 1500,
		"%s has %d imported triangles within the furniture budget" % [item_id, triangles])
	assert_true(found_materials.has("carpet"), "%s has its cushion surface" % item_id)
	var frame_material: String = "wood" if item_id == "diner_booth" else "metal"
	assert_true(found_materials.has(frame_material), "%s keeps its authored frame material" % item_id)
	instance.free()


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null:
		meshes.append(mesh_instance)
	for child: Node in node.get_children():
		_collect_meshes(child, meshes)


func _collect_lights(node: Node, lights: Array[Light3D]) -> void:
	var light: Light3D = node as Light3D
	if light != null:
		lights.append(light)
	for child: Node in node.get_children():
		_collect_lights(child, lights)
