class_name AquariumView
extends PropView
## A fish tank wrapper (#125): the made tank model plus its fish, which swim
## AquariumSwim loops seeded by the placed item's id. View only: the fish have
## no sim state, no physics and nothing is saved. A cloudy tank (sim state,
## AquariumCare) shows murky glass and water. The tank's glow is its lit water
## and the light's strip, both emissive: it adds no light node.

const FISH_SCENES: Array[PackedScene] = [
	preload("res://assets/made/aquarium/fish_neon.glb"),
	preload("res://assets/made/aquarium/fish_orange.glb"),
	preload("res://assets/made/aquarium/fish_yellow.glb"),
	preload("res://assets/made/aquarium/fish_guppy.glb"),
]
## The approved glass material's name in the tank model.
const GLASS_MATERIAL: String = "aquariumGlass"
## The lit water surface's glow material; cloudy water dims it too.
const GLOW_MATERIAL: String = "aquariumGlow"
const PLANT_MATERIAL: String = "plant"
## Cloudy glass: the clear glass mixed toward the tank's own kit `plant` green
## and made less clear, so the water looks green and murky (no new colour).
const CLOUDY_MIX: float = 0.45
const CLOUDY_ALPHA: float = 0.62
## A cloudy tank's light glows dimmer through the murk.
const CLOUDY_GLOW: float = 0.4
## The clear water's glow: its emission colour, unlit, over this share of what
## lies beneath, so the water reads blue-green by day and glows at night.
const GLOW_MIX: float = 0.22

@export_range(4, 6) var fish_count: int = 5
## The swim box in the tank model's own glTF frame (source units, before the
## shared scale); measured by tools/build_aquarium.py (aquarium.metrics.json).
@export var swim_box_model: AABB = AABB()
## The part whose Art node holds the tank model.
@export var tank_part: NodePath = ^"Tank"

var fish: Array[Node3D] = []
var swims: Array[AquariumSwim.Swim] = []
var cloudy: bool = false
var _seed: int = -1
var _time: float = 0.0
var _review_time: float = -1.0
var _fish_root: Node3D
var _surfaces: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	if _seed < 0:
		set_seed(0)


## Wrapper-space swim box: the model box through the Art node's transform.
func swim_box() -> AABB:
	prepare()
	var part: Node3D = get_node_or_null(tank_part) as Node3D
	var art: Node3D = part.get_node_or_null(^"Art") as Node3D if part != null else null
	if art == null:
		return AABB()
	var to_wrapper: Transform3D = part.transform * art.transform
	return to_wrapper * swim_box_model


## (Re)plans the fish for this placed item id. The same id always gives the
## same fish, kinds and loops.
func set_seed(item_id: int) -> void:
	prepare()
	if item_id == _seed and not fish.is_empty():
		return
	_seed = item_id
	if _fish_root == null:
		_fish_root = Node3D.new()
		_fish_root.name = "Fish"
		add_child(_fish_root)
	for node: Node3D in fish:
		node.queue_free() if node.is_inside_tree() else node.free()
	fish.clear()
	swims = AquariumSwim.plan(item_id, fish_count, swim_box(), FISH_SCENES.size())
	for swim: AquariumSwim.Swim in swims:
		var model: Node3D = FISH_SCENES[swim.variant].instantiate() as Node3D
		model.scale = Vector3.ONE * ArtScale.FURNITURE_SCALE
		var holder: Node3D = Node3D.new()
		holder.add_child(model)
		_fish_root.add_child(holder)
		fish.append(holder)
	_place_fish()


## Pins the fish at one moment for still captures (negative: live again).
func set_review_time(seconds: float) -> void:
	_review_time = seconds
	_place_fish()


func _process(delta: float) -> void:
	if _review_time < 0.0:
		_time += delta
		_place_fish()


## Fish time in display seconds; the sim clock never moves the fish.
func swim_time() -> float:
	return _review_time if _review_time >= 0.0 else _time


func _place_fish() -> void:
	var at: float = swim_time()
	for index: int in fish.size():
		fish[index].transform = AquariumSwim.pose(swims[index], at)


## Murky green glass and water while the tank needs cleaning; clear again
## once cleaned.
func set_cloudy(value: bool) -> void:
	prepare()
	cloudy = value
	for entry: Dictionary in _surfaces:
		var mesh_node: MeshInstance3D = entry["mesh"]
		mesh_node.set_surface_override_material(entry["index"], entry["cloudy"] if value else entry["clear"])


## The glass and water surfaces actually drawn, cloudy or clear.
func glass_materials() -> Array[BaseMaterial3D]:
	prepare()
	var result: Array[BaseMaterial3D] = []
	for entry: Dictionary in _surfaces:
		var mesh_node: MeshInstance3D = entry["mesh"]
		result.append(mesh_node.get_active_material(entry["index"]) as BaseMaterial3D)
	return result


func prepare() -> void:
	var first: bool = not _prepared
	super.prepare()
	if first:
		_prepare_water()


## Finds the glass and the lit water. The water's glow is drawn unlit, so it
## reads as soft blue-green light on the water rather than a pale film; a
## cloudy tank swaps both for murky green, made from its own kit `plant` green.
func _prepare_water() -> void:
	var found: Array[Dictionary] = []
	_find_surfaces(self, found)
	var green: Color = Color.TRANSPARENT
	for surface: Dictionary in found:
		if (surface["material"] as BaseMaterial3D).resource_name == PLANT_MATERIAL:
			green = (surface["material"] as BaseMaterial3D).albedo_color
	for surface: Dictionary in found:
		var source: BaseMaterial3D = surface["material"]
		var glow: bool = source.resource_name == GLOW_MATERIAL
		if source.resource_name != GLASS_MATERIAL and not glow:
			continue
		var murky: BaseMaterial3D = source.duplicate() as BaseMaterial3D
		var mixed: Color = source.albedo_color.lerp(green, CLOUDY_MIX) if green.a > 0.0 else source.albedo_color
		murky.albedo_color = Color(mixed.r, mixed.g, mixed.b, CLOUDY_ALPHA)
		var clear: BaseMaterial3D = null
		if glow:
			murky.emission_energy_multiplier = source.emission_energy_multiplier * CLOUDY_GLOW
			clear = source.duplicate() as BaseMaterial3D
			clear.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			clear.albedo_color = Color(source.emission.r, source.emission.g, source.emission.b, GLOW_MIX)
			clear.emission_enabled = false
		_surfaces.append({"mesh": surface["mesh"], "index": surface["index"], "clear": clear, "cloudy": murky})
		(surface["mesh"] as MeshInstance3D).set_surface_override_material(surface["index"], clear)


func _find_surfaces(node: Node, out: Array[Dictionary]) -> void:
	if node == _fish_root:
		return
	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		for index: int in mesh_node.mesh.get_surface_count():
			var source: BaseMaterial3D = mesh_node.mesh.surface_get_material(index) as BaseMaterial3D
			if source != null:
				out.append({"mesh": mesh_node, "index": index, "material": source})
	for child: Node in node.get_children():
		_find_surfaces(child, out)
