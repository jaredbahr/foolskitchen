class_name DishVisual
extends Node3D
## One reusable serving. The models and vessels of today's menu (and of any
## recipe still in flight) are warmed between services (FoodPresentation);
## showing a warmed dish only toggles visibility. A dish that was not warmed is
## built once, on demand, the first time this serving shows it.
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
## Darkened dirty-crockery materials, one per source material, shared by every
## serving (ART_STYLE §5): never a private material per pooled serving.
static var _dark_materials: Dictionary[Material, Material] = {}
## Leftover tints, one material per dish colour, shared by every serving.
static var _tint_materials: Dictionary[Color, Material] = {}
## Clean and dirty vessel nodes by RecipeDef vessel id ("plate" is `plate`).
## A dirty copy exists only for a vessel a dirty serving can show: the dine-in
## vessel of a food recipe (FoodPresentation only dirties food at a table).
var vessels: Dictionary[StringName, Node3D] = {}
var dirty_vessels: Dictionary[StringName, Node3D] = {}
## The leftovers inside each dirty vessel (DishVessels.LEFTOVERS), and their
## meshes, tinted with the dish's colour when it is shown dirty.
var leftovers: Dictionary[StringName, Node3D] = {}
var _leftover_meshes: Dictionary[StringName, Array] = {}
## Height of each warmed recipe's food top above the serving origin (steam).
var steam_heights: Dictionary[StringName, float] = {}
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
var _by_key: Dictionary[String, Node3D] = {}
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


## Warms the servings of `recipes` (FoodPresentation passes the menu plus the
## recipes still in flight). Calling it again adds only what is missing.
func prepare(recipes: Array[RecipeDef]) -> void:
	if plate == null:
		plate = _model(PLATE, ArtScale.FOOD_SCALE)
		footprint_radius = _footprint_radius(plate, Transform3D.IDENTITY)
		dirty_plate = _model(PLATE, ArtScale.FOOD_SCALE)
		# ART_STYLE §5 permits a private darker copy for dirty crockery.
		_darken(dirty_plate)
		vessels[RecipeDef.PLATE] = plate
		dirty_vessels[RecipeDef.PLATE] = dirty_plate
	for recipe: RecipeDef in recipes:
		if recipe != null and not recipe.id.is_empty() and not models.has(recipe.id):
			_prepare_recipe(recipe)
	visible = visible and _shown != null


## Drops every warmed serving but the standard plates and warms `recipes`
## instead. Only between services (the menu changed): it allocates. A serving
## in flight keeps its recipe and shows its rebuilt model at the next show.
func rebuild(recipes: Array[RecipeDef]) -> void:
	for child: Node in get_children():
		if child != plate and child != dirty_plate:
			remove_child(child)
			child.free()
	plate.visible = false
	dirty_plate.visible = false
	_shown = null
	vessel = null
	var plate_leftovers: Node3D = leftovers.get(RecipeDef.PLATE)
	var plate_meshes: Array = _leftover_meshes.get(RecipeDef.PLATE, [])
	leftovers.clear()
	_leftover_meshes.clear()
	if plate_leftovers != null:
		leftovers[RecipeDef.PLATE] = plate_leftovers
		_leftover_meshes[RecipeDef.PLATE] = plate_meshes
	steam_heights.clear()
	models.clear()
	takeaway_models.clear()
	_variant_models.clear()
	_by_key.clear()
	vessels.clear()
	dirty_vessels.clear()
	vessels[RecipeDef.PLATE] = plate
	dirty_vessels[RecipeDef.PLATE] = dirty_plate
	prepare(recipes)


func _prepare_recipe(recipe: RecipeDef) -> void:
	if recipe.view_model == null:
		# A future unmapped dish still has an actual, already-warmed serving.
		models[recipe.id] = plate
		return
	_prepare_vessel(recipe.vessel, not recipe.is_drink())
	models[recipe.id] = _prepare_food(recipe.view_model, recipe.vessel)
	steam_heights[recipe.id] = models[recipe.id].position.y + _drawn_aabb(models[recipe.id]).end.y
	if not recipe.is_drink():
		_prepare_leftovers(recipe.vessel)
		if DishVessels.LEFTOVERS.has(recipe.vessel) and bool(DishVessels.LEFTOVERS[recipe.vessel][3]):
			_tint(recipe.view_color)
	if not recipe.view_variants.is_empty():
		var alternatives: Array[Node3D] = []
		for variant: PackedScene in recipe.view_variants:
			if variant != null:
				alternatives.append(_prepare_food(variant, recipe.vessel))
		_variant_models[recipe.id] = alternatives
	var away: StringName = recipe.served_vessel(true)
	if away != recipe.vessel or recipe.served_model(true) != recipe.view_model:
		_prepare_vessel(away, false)
		takeaway_models[recipe.id] = _prepare_food(recipe.served_model(true), away)


func _prepare_vessel(id: StringName, can_be_dirty: bool) -> void:
	var scene: PackedScene = DishVessels.scene(id)
	if not vessels.has(id):
		vessels[id] = _model(scene, DishVessels.scale(id)) if scene != null else null
	if can_be_dirty and dirty_vessels.get(id) == null and scene != null:
		dirty_vessels[id] = _model(scene, DishVessels.scale(id))
		_darken(dirty_vessels[id])


## The leftovers of a cleared serving, inside this serving's dirty vessel.
func _prepare_leftovers(id: StringName) -> void:
	var holder: Node3D = dirty_vessels.get(id)
	if leftovers.has(id) or holder == null or not DishVessels.LEFTOVERS.has(id):
		return
	var entry: Array = DishVessels.LEFTOVERS[id]
	var bits: Node3D = (load(String(entry[0])) as PackedScene).instantiate() as Node3D
	var vessel_scale: float = DishVessels.scale(id)
	bits.scale = Vector3.ONE * vessel_scale * float(entry[2])
	# The dirty wrapper stands the vessel on y = 0 and centres its footprint.
	var model: Node3D = holder.get_child(0) as Node3D
	bits.position = Vector3(0.0, model.position.y + float(entry[1]) * vessel_scale, 0.0)
	holder.add_child(bits)
	leftovers[id] = bits
	var meshes: Array = []
	if bool(entry[3]):
		meshes.assign(bits.find_children("*", "MeshInstance3D", true, false))
	_leftover_meshes[id] = meshes


## One shared leftover material per dish colour, on the kit colormap's white.
static func _tint(color: Color) -> Material:
	var material: Material = _tint_materials.get(color)
	if material == null:
		var tint: StandardMaterial3D = StandardMaterial3D.new()
		tint.albedo_texture = load("res://assets/kenney/food/Textures/colormap.png") as Texture2D
		tint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		tint.albedo_color = color
		material = tint
		_tint_materials[color] = material
	return material


## Food is shared per (scene, vessel): the same model on one vessel is one node.
func _prepare_food(scene: PackedScene, vessel_id: StringName) -> Node3D:
	var key: String = scene.resource_path + "@" + String(vessel_id)
	var model: Node3D = _by_key.get(key) as Node3D
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
	_by_key[key] = model
	return model


func show_dish(recipe: RecipeDef, dirty: bool, takeaway: bool = false) -> void:
	# Absence clears presentation; it must never become a fallback serving.
	if recipe == null or recipe.id.is_empty():
		clear_dish()
		return
	if not models.has(recipe.id):
		# Not warmed (an old order for a dish since taken off the menu): built
		# once, here, rather than shown as an empty plate.
		_prepare_recipe(recipe)
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
	if dirty and dirty_vessels.get(vessel_id) == null:
		# Only dine-in food is ever dirtied; anything else falls back to its
		# own dine-in vessel, then to the standard plate.
		vessel_id = recipe.vessel if dirty_vessels.get(recipe.vessel) != null else RecipeDef.PLATE
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
	if dirty and _leftover_meshes.has(vessel_id):
		# Shared material, cached while warming: no allocation here.
		var leftover_tint: Material = _tint_materials.get(recipe.view_color)
		for mesh: MeshInstance3D in _leftover_meshes[vessel_id]:
			mesh.material_override = leftover_tint
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
				var material: Material = _dark_materials.get(source)
				if material == null:
					var dark: BaseMaterial3D = source.duplicate() as BaseMaterial3D
					dark.albedo_color = source.albedo_color.darkened(0.4)
					material = dark
					_dark_materials[source] = material
				mesh.set_surface_override_material(index, material)
	for child: Node in node.get_children():
		_darken(child)
