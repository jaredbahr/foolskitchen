extends TestCase
## Derived lowered-backrest seats (tools/derive_seat_backrests.py, Jared
## 2026-10-28) must stay the same kit pieces: same nodes, materials and faces,
## every vertex at or below the seat top untouched, only heights above it lower.

const KIT: String = "res://assets/kenney/furniture/"
const DERIVED: String = "res://assets/props/seats/derived/"
## Kit source -> seat top (source units) and whether the arms move with the back.
const SEATS: Dictionary[String, Array] = {
	"chair": [0.24, false], "chairCushion": [0.24, false], "chairRounded": [0.22, false],
	"chairModernCushion": [0.24, false], "chairModernFrameCushion": [0.24, false],
	"loungeChair": [0.23, true], "bench": [0.24, false], "benchCushion": [0.24, false],
}
## Lowest acceptable backrest top above the seat, as a share of the kit's:
## a lowered back, never a stump.
const MIN_BACK_SHARE: float = 0.5
## Imported meshes use Godot's default vertex compression, quantised to each
## mesh's own bounds, so unchanged positions agree to about 1e-5, not bitwise.
const QUANTUM: float = 0.00003


func test_derived_seats_keep_the_kit_piece_and_only_lower_the_backrest() -> void:
	for name: String in SEATS:
		var seat_top: float = SEATS[name][0]
		var kit: MeshInstance3D = _mesh(KIT + name + ".glb")
		var derived: MeshInstance3D = _mesh(DERIVED + name + "_low_back.glb")
		assert_not_null(kit, name)
		assert_not_null(derived, name)
		if kit == null or derived == null:
			continue
		assert_eq(derived.name, kit.name, name + " keeps the kit node name")
		assert_eq(derived.mesh.get_surface_count(), kit.mesh.get_surface_count(), name)
		var kit_top: float = 0.0
		var top: float = 0.0
		for surface: int in kit.mesh.get_surface_count():
			var kit_material: Material = kit.mesh.surface_get_material(surface)
			var derived_material: Material = derived.mesh.surface_get_material(surface)
			assert_eq(derived_material.resource_name, kit_material.resource_name, name + " keeps kit materials")
			assert_eq((derived_material as BaseMaterial3D).albedo_color, (kit_material as BaseMaterial3D).albedo_color, name)
			var kit_arrays: Array = kit.mesh.surface_get_arrays(surface)
			var derived_arrays: Array = derived.mesh.surface_get_arrays(surface)
			assert_eq(derived_arrays[Mesh.ARRAY_INDEX], kit_arrays[Mesh.ARRAY_INDEX], name + " keeps topology")
			assert_eq(derived_arrays[Mesh.ARRAY_TEX_UV], kit_arrays[Mesh.ARRAY_TEX_UV], name + " keeps UVs")
			var kit_points: PackedVector3Array = kit_arrays[Mesh.ARRAY_VERTEX]
			var points: PackedVector3Array = derived_arrays[Mesh.ARRAY_VERTEX]
			assert_eq(points.size(), kit_points.size(), name)
			if points.size() != kit_points.size():
				continue
			for index: int in points.size():
				var before: Vector3 = kit_points[index]
				var after: Vector3 = points[index]
				kit_top = maxf(kit_top, before.y)
				top = maxf(top, after.y)
				assert_true(Vector2(after.x, after.z).distance_to(Vector2(before.x, before.z)) < QUANTUM,
					name + " plan shape is unchanged")
				if before.y <= seat_top + QUANTUM:
					assert_true(after.distance_to(before) < QUANTUM, name + " seat, legs and frame below the seat are untouched")
				else:
					assert_true(after.y < before.y and after.y > seat_top, name + " backrest is lowered, not removed")
		assert_true(top < kit_top - 0.05, name + " backrest is lower")
		assert_true(top - seat_top >= MIN_BACK_SHARE * (kit_top - seat_top), name + " is a lowered backrest, not a stump")
		kit.get_parent().free()
		derived.get_parent().free()


func test_catalogue_seats_use_the_derived_meshes_and_never_edit_the_kit_files() -> void:
	for path: String in ["res://assets/props/chair.tscn", "res://assets/props/table_2.tscn", "res://assets/props/table_4.tscn",
			"res://assets/props/wooden_chair.tscn", "res://assets/props/rounded_chair.tscn", "res://assets/props/modern_chair.tscn",
			"res://assets/props/modern_frame_chair.tscn", "res://assets/props/lounge_chair.tscn",
			"res://assets/props/bench.tscn", "res://assets/props/cushioned_bench.tscn"]:
		var view: Node = (load(path) as PackedScene).instantiate()
		var seats: int = 0
		for node: Node in view.find_children("Model", "", true, false):
			var model: String = node.scene_file_path
			if model.ends_with("/table.glb"):
				continue
			seats += 1
			assert_true(model.begins_with(DERIVED) and model.ends_with("_low_back.glb"), path + " uses " + model)
		assert_true(seats > 0, path)
		view.free()


func _mesh(path: String) -> MeshInstance3D:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		root.free()
		return null
	return meshes[0] as MeshInstance3D
