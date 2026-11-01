class_name ItemVisual
extends Node3D
## Shared model/box adapter. Its origin is the footprint centre on the floor.
## Bounds belong to this root, so callers never assume a single furniture mesh.

var prop: PropView
var fallback: MeshInstance3D
var _fallback_material: Material
const SIGN_THEME: Theme = preload("res://src/ui/theme/main_theme.tres")
const SIGN_FONT_SIZE: int = 48
var restaurant_name_label: Label3D
var _shows_restaurant_name: bool = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# Unbind private materials while every descendant renderer instance is alive.
	# Otherwise MeshInstance3D can release surface override resources before its
	# base destructor flushes dirty instances that still contain their material RIDs.
	for mesh_node: MeshInstance3D in rendered_meshes():
		mesh_node.material_override = null
		for index: int in range(mesh_node.get_surface_override_material_count()):
			mesh_node.set_surface_override_material(index, null)


static func create(definition: ItemDef, fallback_height: float, material: Material) -> ItemVisual:
	var result: ItemVisual = ItemVisual.new()
	if definition.view_scene != null:
		var instance: Node = definition.view_scene.instantiate()
		result.prop = instance as PropView
		if result.prop != null:
			result.add_child(result.prop)
			result.prop.prepare()
		else:
			instance.free()
	if result.prop == null:
		result.fallback = MeshInstance3D.new()
		result.fallback.name = "Box"
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(definition.footprint.x * GridMath.CELL_SIZE,
			fallback_height, definition.footprint.y * GridMath.CELL_SIZE)
		result.fallback.mesh = box
		result.fallback.position.y = fallback_height * 0.5
		result._fallback_material = material
		result.fallback.material_override = material
		result.add_child(result.fallback)
	result._shows_restaurant_name = definition.shows_restaurant_name
	if result._shows_restaurant_name:
		result.set_restaurant_name(MenuSettings.DEFAULT_NAME)
	return result


## Only the purchased name sign gets text; ordinary models remain untouched.
func set_restaurant_name(value: String) -> bool:
	if not _shows_restaurant_name:
		return false
	var normalized: String = MenuSettings.normalized_restaurant_name(value)
	if normalized.is_empty():
		return false
	if restaurant_name_label == null:
		restaurant_name_label = Label3D.new()
		restaurant_name_label.name = "RestaurantName"
		restaurant_name_label.font = SIGN_THEME.default_font if SIGN_THEME.default_font != null else ThemeDB.fallback_font
		restaurant_name_label.font_size = SIGN_FONT_SIZE
		restaurant_name_label.modulate = SIGN_THEME.get_color("font_color", "Label")
		restaurant_name_label.outline_size = 0
		restaurant_name_label.double_sided = false
		restaurant_name_label.no_depth_test = false
		restaurant_name_label.rotation.y = PI
		restaurant_name_label.position = ArtScale.EXTERIOR_SIGN_TEXT_POSITION
		add_child(restaurant_name_label)
	var font: Font = restaurant_name_label.font
	var width: float = font.get_string_size(normalized, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGN_FONT_SIZE).x
	var height: float = font.get_height(SIGN_FONT_SIZE)
	restaurant_name_label.pixel_size = minf(ArtScale.EXTERIOR_SIGN_TEXT_SIZE.x / maxf(width, 1.0),
		ArtScale.EXTERIOR_SIGN_TEXT_SIZE.y / maxf(height, 1.0))
	restaurant_name_label.text = normalized
	restaurant_name_label.set_meta(&"full_name", normalized)
	return true


func apply_variant(look: ItemVariant) -> bool:
	return prop.set_variant(look) if prop != null else look == null


func get_aabb() -> AABB:
	if prop != null:
		return prop.transform * prop.get_combined_aabb()
	if fallback != null:
		return fallback.transform * fallback.get_aabb()
	return AABB()


func apply_paint(color: Color, material: Material) -> void:
	if prop != null:
		prop.set_body_tint(color)
	elif fallback != null:
		fallback.material_override = material


func clear_paint() -> void:
	if prop != null:
		prop.clear_body_tint()
	elif fallback != null:
		fallback.material_override = _fallback_material


func rendered_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_meshes(self, result)
	return result


func primary_body_material() -> BaseMaterial3D:
	if prop != null:
		return prop.active_body_material()
	return fallback.get_active_material(0) as BaseMaterial3D if fallback != null else null


## A build ghost is a separate instance; tint every surface without replacing
## kit textures or mutating the live item's materials. Glass keeps its opacity.
func set_ghost_tint(color: Color) -> void:
	for mesh_node: MeshInstance3D in rendered_meshes():
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh_node.material_override is BaseMaterial3D:
			mesh_node.material_override = _ghost_material(mesh_node.material_override as BaseMaterial3D, color)
		else:
			for index: int in range(mesh_node.mesh.get_surface_count()):
				var source: BaseMaterial3D = mesh_node.get_active_material(index) as BaseMaterial3D
				if source != null:
					mesh_node.set_surface_override_material(index, _ghost_material(source, color))


static func placed_transform(definition: ItemDef, origin: Vector2i, turns: int) -> Transform3D:
	var footprint: Vector2i = GridMath.rotated_footprint(definition.footprint, turns)
	return Transform3D(Basis(Vector3.UP, -turns * PI * 0.5),
		Vector3((origin.x + footprint.x * 0.5) * GridMath.CELL_SIZE, 0.0,
			(origin.y + footprint.y * 0.5) * GridMath.CELL_SIZE))


static func _ghost_material(source: BaseMaterial3D, color: Color) -> BaseMaterial3D:
	var tinted: BaseMaterial3D = source.duplicate() as BaseMaterial3D
	tinted.albedo_color = Color(color.r, color.g, color.b, color.a * source.albedo_color.a)
	tinted.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return tinted


static func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		result.append(mesh_node)
	for child: Node in node.get_children():
		_collect_meshes(child, result)
