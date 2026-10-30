class_name DishVisual
extends Node3D
## One reusable serving. All approved recipe models are warmed before service.

const PLATE: PackedScene = preload("res://assets/kenney/food/plate.glb")
var plate: Node3D
var dirty_plate: Node3D
var models: Dictionary[StringName, Node3D] = {}
var recipe_id: StringName = &""
var stage: StringName = &""
var order_id: int = 0
var footprint_radius: float = 0.0
var _shown: Node3D
var _dirty: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_clear_overrides(self)


static func _clear_overrides(node: Node) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		for index: int in range(mesh.get_surface_override_material_count()):
			mesh.set_surface_override_material(index, null)
	for child: Node in node.get_children():
		_clear_overrides(child)


func prepare(recipes: Array[RecipeDef]) -> void:
	plate = _model(PLATE)
	footprint_radius = _footprint_radius(plate, Transform3D.IDENTITY)
	dirty_plate = _model(PLATE)
	# ART_STYLE §5 permits a private darker copy for dirty crockery.
	_darken(dirty_plate)
	var plate_height: float = PropView._children_aabb(plate).end.y
	var by_scene: Dictionary[String, Node3D] = {}
	for recipe: RecipeDef in recipes:
		if recipe.view_model == null:
			continue
		var path: String = recipe.view_model.resource_path
		var food: Node3D = by_scene.get(path) as Node3D
		if food == null:
			food = _model(recipe.view_model)
			by_scene[path] = food
		models[recipe.id] = food
		# The same model is shared only by recipes with the same serving style.
		food.position.y = plate_height if not recipe.is_drink() else 0.0
	visible = false


func show_dish(recipe: RecipeDef, dirty: bool) -> void:
	if visible and recipe_id == recipe.id and _dirty == dirty:
		return
	_dirty = dirty
	if _shown != null:
		_shown.visible = false
	plate.visible = not recipe.is_drink() and not dirty
	dirty_plate.visible = not recipe.is_drink() and dirty
	_shown = models.get(recipe.id) as Node3D
	if _shown != null:
		_shown.visible = not dirty
	recipe_id = recipe.id
	visible = true


func _model(scene: PackedScene) -> Node3D:
	var wrapper: Node3D = Node3D.new()
	var model: Node3D = scene.instantiate() as Node3D
	wrapper.add_child(model)
	model.scale = Vector3.ONE * ArtScale.FOOD_SCALE
	var bounds: AABB = PropView._children_aabb(wrapper)
	model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	wrapper.visible = false
	add_child(wrapper)
	return wrapper


## Measured once while warming the pool; any serving rotation stays supported.
static func _footprint_radius(node: Node, transform: Transform3D) -> float:
	var spatial: Node3D = node as Node3D
	var accumulated: Transform3D = transform * spatial.transform if spatial != null else transform
	var radius: float = 0.0
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for vertex: Vector3 in mesh.mesh.get_faces():
			var point: Vector3 = accumulated * vertex
			radius = maxf(radius, Vector2(point.x, point.z).length())
	for child: Node in node.get_children():
		radius = maxf(radius, _footprint_radius(child, accumulated))
	return radius


static func _darken(node: Node) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for index: int in range(mesh.mesh.get_surface_count()):
			var source: BaseMaterial3D = mesh.get_active_material(index) as BaseMaterial3D
			if source != null:
				var material: BaseMaterial3D = source.duplicate() as BaseMaterial3D
				material.albedo_color = source.albedo_color.darkened(0.4)
				mesh.set_surface_override_material(index, material)
	for child: Node in node.get_children():
		_darken(child)
