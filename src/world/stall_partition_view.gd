class_name StallPartitionView
extends PropView
## The catalogue uses the same thin laminate edge panel as the live wall view.

const SWATCH: SwatchDef = preload("res://data/swatches/cream.tres")


func prepare() -> void:
	if _prepared:
		return
	_prepared = true
	add_child(make_panel(ArtScale.STALL_PARTITION_HEIGHT))


static func make_panel(height: float) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = SWATCH.color
	material.roughness = 0.8
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(GridMath.CELL_SIZE, height, ArtScale.STALL_PARTITION_THICKNESS)
	var panel: MeshInstance3D = MeshInstance3D.new()
	panel.name = "StallPanel"
	panel.mesh = mesh
	panel.material_override = material
	panel.position.y = height * 0.5
	return panel
