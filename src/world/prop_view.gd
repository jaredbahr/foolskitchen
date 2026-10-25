class_name PropView
extends Node3D
## A presentation-only item, centred on its unrotated footprint at floor y = 0.
## Each direct part has an Art child: its rotation belongs to the wrapper scene,
## while this script applies the shared uniform scale and fixes the back-corner pivot.

class BodySurface:
	extends RefCounted
	var mesh: MeshInstance3D
	var index: int
	var source: BaseMaterial3D
	var original_override: Material
	var tinted: BaseMaterial3D

@export var footprint: Vector2i = Vector2i.ONE
## Exact imported material names. All other surfaces keep their kit materials.
@export var body_material_names: PackedStringArray = []
## Sitting surface in unscaled source-model metres. Zero leaves the caller's
## legacy seat-height fallback intact; ArtScale supplies the only scale factor.
@export_range(0.0, 2.0, 0.001) var seat_surface_y: float = 0.0

var _prepared: bool = false
var _body_surfaces: Array[BodySurface] = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		prepare()


func _ready() -> void:
	prepare()


## Also works immediately after PackedScene.instantiate(), outside the scene tree.
func prepare() -> void:
	if _prepared:
		return
	_prepared = true
	for child: Node in get_children():
		var part: Node3D = child as Node3D
		if part == null:
			continue
		var art: Node3D = part.get_node_or_null("Art") as Node3D
		if art == null:
			continue
		var is_food: bool = part.get_meta(&"art_group", &"furniture") == &"food"
		var factor: float = ArtScale.FOOD_SCALE if is_food else ArtScale.FURNITURE_SCALE
		art.scale = Vector3.ONE * factor
		art.position = Vector3.ZERO
		var bounds: AABB = _children_aabb(part)
		art.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
		if not is_food:
			_collect_body_surfaces(art)
	# Supported pieces are placed only after every floor piece has been centred.
	for child: Node in get_children():
		var part: Node3D = child as Node3D
		if part == null or not part.has_meta(&"support"):
			continue
		var support_path: NodePath = part.get_meta(&"support")
		var support: Node3D = part.get_node_or_null(support_path) as Node3D
		if support != null:
			part.position.y = support.position.y + _children_aabb(support).end.y


## Wrapper-local combined bounds, including scaled/rotated nested model nodes.
## Picking, outlines, ghosts and trays can share this geometry without a sim change.
func get_combined_aabb() -> AABB:
	prepare()
	return _children_aabb(self)


func body_surface_count() -> int:
	prepare()
	return _body_surfaces.size()


## View-only geometry: this never changes the physical table's sim seat cells.
func seat_surface_height() -> float:
	return maxf(0.0, seat_surface_y) * ArtScale.FURNITURE_SCALE


## Actual currently drawn named body surface, independent of imported surface order.
func active_body_material() -> BaseMaterial3D:
	prepare()
	if _body_surfaces.is_empty():
		return null
	var body: BodySurface = _body_surfaces[0]
	return body.mesh.get_active_material(body.index) as BaseMaterial3D


## Duplicate only an existing named body material; never mutate imported resources.
## Textures, shading and every non-body surface retain the kit's settings.
func set_body_tint(color: Color) -> void:
	prepare()
	for body: BodySurface in _body_surfaces:
		if body.tinted == null:
			body.tinted = body.source.duplicate() as BaseMaterial3D
		body.tinted.albedo_color = Color(color.r, color.g, color.b, body.source.albedo_color.a)
		body.mesh.set_surface_override_material(body.index, body.tinted)


func clear_body_tint() -> void:
	prepare()
	for body: BodySurface in _body_surfaces:
		body.mesh.set_surface_override_material(body.index, body.original_override)


func _collect_body_surfaces(node: Node) -> void:
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		for index: int in range(mesh_node.mesh.get_surface_count()):
			var imported: Material = mesh_node.mesh.surface_get_material(index)
			if imported == null or not body_material_names.has(imported.resource_name):
				continue
			var source: BaseMaterial3D = mesh_node.get_active_material(index) as BaseMaterial3D
			if source == null:
				continue
			var body: BodySurface = BodySurface.new()
			body.mesh = mesh_node
			body.index = index
			body.source = source
			body.original_override = mesh_node.get_surface_override_material(index)
			_body_surfaces.append(body)
	for child: Node in node.get_children():
		_collect_body_surfaces(child)


static func _children_aabb(root: Node) -> AABB:
	var pieces: Array[AABB] = []
	for child: Node in root.get_children():
		_append_mesh_bounds(child, Transform3D.IDENTITY, pieces)
	if pieces.is_empty():
		return AABB()
	var combined: AABB = pieces[0]
	for index: int in range(1, pieces.size()):
		combined = combined.merge(pieces[index])
	return combined


static func _append_mesh_bounds(node: Node, parent_transform: Transform3D, pieces: Array[AABB]) -> void:
	var accumulated: Transform3D = parent_transform
	var spatial: Node3D = node as Node3D
	if spatial != null:
		accumulated = parent_transform * spatial.transform
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		pieces.append(accumulated * mesh_node.get_aabb())
	for child: Node in node.get_children():
		_append_mesh_bounds(child, accumulated, pieces)
