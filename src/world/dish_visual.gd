class_name DishVisual
extends Node3D
## One reusable serving. All approved recipe models and their vessels are
## warmed before service; showing a dish only toggles visibility.
##
## A serving is a vessel (RecipeDef.vessel: plate, bowl, board, cup and
## saucer, paper tray...) plus the food on it. Food is fitted to fill about
## ArtScale.SERVED_FOOD_FILL of its vessel (ART_STYLE §5); the vessel keeps its
## own size. A dirty serving is a darkened copy of its vessel alone.

const PLATE: PackedScene = preload("res://assets/kenney/food/plate.glb")
## The standard plate: the unmapped-recipe fallback, the sink stack and the
## footprint every vessel stays inside.
var plate: Node3D
var dirty_plate: Node3D
## Clean and dirty vessel nodes by RecipeDef vessel id ("plate" is `plate`).
var vessels: Dictionary[StringName, Node3D] = {}
var dirty_vessels: Dictionary[StringName, Node3D] = {}
var models: Dictionary[StringName, Node3D] = {}
## Takeaway food by recipe id, only for recipes with a takeaway model or vessel.
var takeaway_models: Dictionary[StringName, Node3D] = {}
var recipe_id: StringName = &""
var stage: StringName = &""
var order_id: int = 0
var footprint_radius: float = 0.0
## The vessel node currently visible (clean or dirty), or null.
var vessel: Node3D
var _variant_models: Dictionary[StringName, Array] = {}
var _shown: Node3D
var _dirty: bool = false
var _takeaway: bool = false


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
	plate = _model(PLATE, ArtScale.FOOD_SCALE)
	footprint_radius = _footprint_radius(plate, Transform3D.IDENTITY)
	dirty_plate = _model(PLATE, ArtScale.FOOD_SCALE)
	# ART_STYLE §5 permits a private darker copy for dirty crockery.
	_darken(dirty_plate)
	vessels[RecipeDef.PLATE] = plate
	dirty_vessels[RecipeDef.PLATE] = dirty_plate
	var by_key: Dictionary[String, Node3D] = {}
	for recipe: RecipeDef in recipes:
		if recipe == null or recipe.id.is_empty():
			continue
		if recipe.view_model == null:
			# A future unmapped dish still has an actual, already-warmed serving.
			models[recipe.id] = plate
			continue
		_prepare_vessel(recipe.vessel)
		models[recipe.id] = _prepare_food(recipe.view_model, recipe.vessel, by_key)
		if not recipe.view_variants.is_empty():
			var alternatives: Array[Node3D] = []
			for variant: PackedScene in recipe.view_variants:
				if variant != null:
					alternatives.append(_prepare_food(variant, recipe.vessel, by_key))
			_variant_models[recipe.id] = alternatives
		var away: StringName = recipe.served_vessel(true)
		if away != recipe.vessel or recipe.served_model(true) != recipe.view_model:
			_prepare_vessel(away)
			takeaway_models[recipe.id] = _prepare_food(recipe.served_model(true), away, by_key)
	visible = false


func _prepare_vessel(id: StringName) -> void:
	if vessels.has(id):
		return
	var scene: PackedScene = DishVessels.scene(id)
	if scene == null:
		vessels[id] = null
		dirty_vessels[id] = null
		return
	var vessel_scale: float = DishVessels.scale(id)
	vessels[id] = _model(scene, vessel_scale)
	dirty_vessels[id] = _model(scene, vessel_scale)
	_darken(dirty_vessels[id])


## Food is shared per (scene, vessel): the same model on one vessel is one node.
func _prepare_food(scene: PackedScene, vessel_id: StringName, by_key: Dictionary[String, Node3D]) -> Node3D:
	var key: String = scene.resource_path + "@" + String(vessel_id)
	var model: Node3D = by_key.get(key) as Node3D
	if model != null:
		return model
	var vessel_scale: float = DishVessels.scale(vessel_id)
	var root: Node = scene.instantiate()
	var in_vessel_space: bool = root.has_meta(DishVessels.VESSEL_SPACE)
	root.free()
	if in_vessel_space:
		# Authored inside its vessel (a soup in its bowl): same scale, same origin.
		model = _wrap(scene, vessel_scale)
	else:
		model = _model(scene, ArtScale.FOOD_SCALE)
		var inner: Node3D = model.get_child(0) as Node3D
		var radius: float = _footprint_radius(model, Transform3D.IDENTITY)
		var height: float = _drawn_aabb(model).size.y
		var factor: float = DishVessels.fit_radius(vessel_id) / radius if radius > 0.0 else 1.0
		if height * factor > ArtScale.SERVED_FOOD_MAX_HEIGHT:
			factor = ArtScale.SERVED_FOOD_MAX_HEIGHT / height
		inner.scale *= factor
		inner.position = Vector3.ZERO
		_center(model)
		model.position.y = DishVessels.rest_height(vessel_id)
	by_key[key] = model
	return model


func show_dish(recipe: RecipeDef, dirty: bool, takeaway: bool = false) -> void:
	# Absence clears presentation; it must never become a fallback serving.
	if recipe == null or recipe.id.is_empty():
		clear_dish()
		return
	var model: Node3D = plate
	var vessel_id: StringName = RecipeDef.PLATE
	if recipe.view_model != null and models.get(recipe.id) != null:
		vessel_id = recipe.vessel
		model = models[recipe.id]
		if takeaway and takeaway_models.has(recipe.id):
			vessel_id = recipe.served_vessel(true)
			model = takeaway_models[recipe.id]
		elif _variant_models.has(recipe.id):
			var alternatives: Array = _variant_models[recipe.id]
			var index: int = posmod(order_id, alternatives.size() + 1) - 1
			if index >= 0:
				model = alternatives[index] as Node3D
	if not vessels.has(vessel_id):
		vessel_id = RecipeDef.PLATE
	if visible and recipe_id == recipe.id and _dirty == dirty and _shown == model and _takeaway == takeaway:
		return
	_dirty = dirty
	_takeaway = takeaway
	if _shown != null:
		_shown.visible = false
	if vessel != null:
		vessel.visible = false
	_shown = model
	# Reuse the clean plate itself for an unmapped recipe: exactly one plate,
	# no fabricated dish and no scene allocation in the presentation loop.
	vessel = (dirty_vessels if dirty else vessels)[vessel_id]
	if vessel != null:
		vessel.visible = true
	# The food (the plate itself for an unmapped dish) goes with the meal.
	_shown.visible = not dirty
	recipe_id = recipe.id
	visible = true


func clear_dish() -> void:
	if _shown != null:
		_shown.visible = false
	if vessel != null:
		vessel.visible = false
	if plate != null:
		plate.visible = false
	if dirty_plate != null:
		dirty_plate.visible = false
	vessel = null
	_shown = null
	_dirty = false
	_takeaway = false
	recipe_id = &""
	stage = &""
	order_id = 0
	visible = false


## A hidden wrapper holding the scene at `model_scale`, centred on its
## footprint and standing on y = 0 (vessels and fitted food).
func _model(scene: PackedScene, model_scale: float) -> Node3D:
	var wrapper: Node3D = _wrap(scene, model_scale)
	_center(wrapper)
	return wrapper


func _wrap(scene: PackedScene, model_scale: float) -> Node3D:
	var wrapper: Node3D = Node3D.new()
	var model: Node3D = scene.instantiate() as Node3D
	wrapper.add_child(model)
	model.scale = Vector3.ONE * model_scale
	wrapper.visible = false
	add_child(wrapper)
	return wrapper


static func _center(wrapper: Node3D) -> void:
	var model: Node3D = wrapper.get_child(0) as Node3D
	model.position = Vector3.ZERO
	var bounds: AABB = _drawn_aabb(wrapper)
	model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)


## Bounds of the meshes a serving draws (an imported pizza hides seven of
## its eight wedges), in the wrapper's space.
static func _drawn_aabb(root: Node) -> AABB:
	var pieces: Array[AABB] = []
	for child: Node in root.get_children():
		_append_drawn(child, Transform3D.IDENTITY, pieces)
	var combined: AABB = pieces[0] if not pieces.is_empty() else AABB()
	for piece: AABB in pieces:
		combined = combined.merge(piece)
	return combined


static func _append_drawn(node: Node, parent_transform: Transform3D, pieces: Array[AABB]) -> void:
	var spatial: Node3D = node as Node3D
	var accumulated: Transform3D = parent_transform * spatial.transform if spatial != null else parent_transform
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null and mesh.visible:
		pieces.append(accumulated * mesh.get_aabb())
	for child: Node in node.get_children():
		_append_drawn(child, accumulated, pieces)


## Measured once while warming the pool; any serving rotation stays supported.
static func _footprint_radius(node: Node, transform: Transform3D) -> float:
	var spatial: Node3D = node as Node3D
	var accumulated: Transform3D = transform * spatial.transform if spatial != null else transform
	var radius: float = 0.0
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null and mesh.visible:
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
