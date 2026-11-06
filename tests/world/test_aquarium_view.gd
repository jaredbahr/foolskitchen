extends TestCase
## The fish tank wrappers (#125): made models in their footprints, fish that
## stay inside the glass, deterministic swims and cloudy glass. View only.

const TANKS: Array[String] = ["res://data/items/aquarium.tres", "res://data/items/aquarium_large.tres"]
const MODELS: Dictionary = {
	&"aquarium": "res://assets/made/aquarium/aquarium_2.glb",
	&"aquarium_large": "res://assets/made/aquarium/aquarium_3.glb",
}
const FISH: Array[String] = [
	"res://assets/made/aquarium/fish_neon.glb", "res://assets/made/aquarium/fish_orange.glb",
	"res://assets/made/aquarium/fish_yellow.glb", "res://assets/made/aquarium/fish_guppy.glb",
]
const FRAMES: int = 10000
const FRAME_SECONDS: float = 1.0 / 60.0

var _views: Array[Node] = []


func after_each() -> void:
	for view: Node in _views:
		view.free()
	_views.clear()


func test_tanks_use_their_made_models_and_fit_their_footprints() -> void:
	for path: String in TANKS:
		var definition: ItemDef = load(path) as ItemDef
		var view: AquariumView = _view(definition, 1)
		assert_eq(view.footprint, definition.footprint)
		var model: Node3D = view.get_node("Tank/Art/Model") as Node3D
		assert_eq(model.scene_file_path, MODELS[definition.id])
		assert_eq((view.get_node("Tank/Art") as Node3D).scale, Vector3.ONE * ArtScale.FURNITURE_SCALE)
		assert_eq(view.body_material_names, PackedStringArray(["woodDark"]), "the stand takes paint")
		assert_eq(view.body_surface_count(), 1)
		var bounds: AABB = view.get_combined_aabb()
		assert_almost_eq(bounds.position.y, 0.0, 0.0001, "stands on the floor")
		var allowed: Rect2 = Rect2(-Vector2(definition.footprint) * GridMath.CELL_SIZE * 0.5,
			Vector2(definition.footprint) * GridMath.CELL_SIZE).grow(0.05)
		assert_true(allowed.encloses(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)),
			"%s fits its footprint" % definition.id)
		assert_true(bounds.size.y > 0.55 and bounds.size.y < 0.74, "a tank top below a person's head")
		assert_true(_triangles(model) < 1500, "furniture triangle budget")
		assert_true(view.fish.size() >= AquariumSwim.MIN_FISH and view.fish.size() <= AquariumSwim.MAX_FISH)
		for light: Node in view.find_children("*", "Light3D", true, false):
			fail("%s adds a light node: %s" % [definition.id, light.name])


func test_each_fish_is_a_small_colormap_model_under_100_triangles() -> void:
	for path: String in FISH:
		var fish: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		_views.append(fish)
		assert_true(_triangles(fish) < 100, path)
		for mesh_node: MeshInstance3D in _meshes(fish):
			for index: int in mesh_node.mesh.get_surface_count():
				var material: BaseMaterial3D = mesh_node.mesh.surface_get_material(index) as BaseMaterial3D
				assert_not_null(material.albedo_texture, "coloured through the kit colormap")
				assert_eq(material.albedo_texture.resource_path, "res://assets/kenney/food/Textures/colormap.png")


func test_fish_stay_inside_the_glass_over_ten_thousand_frames() -> void:
	for path: String in TANKS:
		var definition: ItemDef = load(path) as ItemDef
		for seed_value: int in [1, 42, 125]:
			var view: AquariumView = _view(definition, seed_value)
			var glass: AABB = _inside_glass(view)
			assert_true(glass.has_volume(), "%s glass found" % definition.id)
			var escaped: int = 0
			for frame: int in FRAMES:
				view._process(FRAME_SECONDS)
				for holder: Node3D in view.fish:
					var body: AABB = _fish_bounds(holder)
					if not glass.encloses(body):
						escaped += 1
			assert_eq(escaped, 0, "%s seed %d: every fish inside the glass every frame" % [definition.id, seed_value])
			assert_almost_eq(view.swim_time(), FRAMES * FRAME_SECONDS, 0.01, "all the frames ran")


func test_fish_swims_are_deterministic_for_an_item_and_differ_between_items() -> void:
	var definition: ItemDef = load(TANKS[0]) as ItemDef
	var first: AquariumView = _view(definition, 17)
	var again: AquariumView = _view(definition, 17)
	var other: AquariumView = _view(definition, 18)
	var same: bool = true
	var differs: bool = false
	for time: float in [0.0, 3.25, 61.0, 600.5]:
		first.set_review_time(time)
		again.set_review_time(time)
		other.set_review_time(time)
		for index: int in first.fish.size():
			same = same and first.fish[index].transform.is_equal_approx(again.fish[index].transform)
			if index < other.fish.size():
				differs = differs or not first.fish[index].transform.is_equal_approx(other.fish[index].transform)
	assert_true(same, "the same item id swims the same way")
	assert_true(differs, "another item id swims its own way")
	for index: int in first.swims.size():
		assert_eq(first.swims[index].variant, again.swims[index].variant)
	# Pure plan: equal inputs, equal loops; fish face the way they swim.
	var box: AABB = first.swim_box()
	var plan_a: Array[AquariumSwim.Swim] = AquariumSwim.plan(5, 5, box, FISH.size())
	var plan_b: Array[AquariumSwim.Swim] = AquariumSwim.plan(5, 5, box, FISH.size())
	for index: int in plan_a.size():
		for time: float in [0.0, 1.5, 9.0]:
			assert_true(AquariumSwim.pose(plan_a[index], time).is_equal_approx(AquariumSwim.pose(plan_b[index], time)))
			var ahead: Vector3 = AquariumSwim.heading(plan_a[index], time)
			var nose: Vector3 = -AquariumSwim.pose(plan_a[index], time).basis.z
			var flat_ahead: Vector2 = Vector2(ahead.x, ahead.z).normalized()
			var flat_nose: Vector2 = Vector2(nose.x, nose.z).normalized()
			assert_true(flat_ahead.dot(flat_nose) > cos(AquariumSwim.WAG_ANGLE + 0.01), "nose along the swim")
	assert_eq(AquariumSwim.plan(5, 2, box, FISH.size()).size(), AquariumSwim.MIN_FISH, "never fewer than four")
	assert_eq(AquariumSwim.plan(5, 9, box, FISH.size()).size(), AquariumSwim.MAX_FISH, "never more than six")


func test_cloudy_glass_is_murkier_and_a_clean_restores_the_clear_water() -> void:
	var view: AquariumView = _view(load(TANKS[0]) as ItemDef, 3)
	var clear: Array[BaseMaterial3D] = view.glass_materials()
	assert_eq(clear.size(), 2, "the glass and the lit water")
	view.set_cloudy(true)
	var murky: Array[BaseMaterial3D] = view.glass_materials()
	for index: int in clear.size():
		assert_true(murky[index].albedo_color.a > clear[index].albedo_color.a, "cloudy water is less clear")
		assert_true(murky[index].albedo_color.g > murky[index].albedo_color.b, "and greener")
	view.set_cloudy(false)
	var again: Array[BaseMaterial3D] = view.glass_materials()
	for index: int in clear.size():
		assert_eq(again[index], clear[index])


func _view(definition: ItemDef, item_id: int) -> AquariumView:
	var view: AquariumView = definition.view_scene.instantiate() as AquariumView
	_views.append(view)
	view.set_seed(item_id)
	return view


## Inside of the glass in wrapper space: within the panes and above the tank
## floor, up to the water surface.
func _inside_glass(view: AquariumView) -> AABB:
	var glass: AABB = AABB()
	var water_y: float = INF
	for mesh_node: MeshInstance3D in _meshes(view):
		var to_view: Transform3D = _to_view(mesh_node, view)
		for index: int in mesh_node.mesh.get_surface_count():
			var material: Material = mesh_node.mesh.surface_get_material(index)
			var points: PackedVector3Array = mesh_node.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
			var box: AABB = AABB(to_view * points[0], Vector3.ZERO)
			for point: Vector3 in points:
				box = box.expand(to_view * point)
			if material.resource_name == AquariumView.GLASS_MATERIAL:
				glass = box
			elif material.resource_name == AquariumView.GLOW_MATERIAL:
				water_y = minf(water_y, box.position.y)
	# The panes are 6 mm (source) thick; stay inside them.
	var pane: float = 0.006 * ArtScale.FURNITURE_SCALE
	return AABB(glass.position + Vector3(pane, 0.0, pane),
		Vector3(glass.size.x - 2.0 * pane, water_y - glass.position.y, glass.size.z - 2.0 * pane))


func _fish_bounds(holder: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for mesh_node: MeshInstance3D in _meshes(holder):
		var to_tank: Transform3D = holder.transform * _to_view(mesh_node, holder)
		var box: AABB = to_tank * mesh_node.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


static func _to_view(node: Node3D, root: Node) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		result.append(node as MeshInstance3D)
	return result


static func _triangles(root: Node) -> int:
	var count: int = 0
	for mesh_node: MeshInstance3D in _meshes(root):
		for index: int in mesh_node.mesh.get_surface_count():
			var arrays: Array = mesh_node.mesh.surface_get_arrays(index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			count += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return count
